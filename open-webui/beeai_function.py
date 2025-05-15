"""
General-purpose Open WebUI Function for BeeAI agents
"""
# Standard
from functools import partial
from typing import AsyncGenerator, Awaitable, Callable, List
import logging
import re

# Third Party
from acp import types as acp_types
from beeai_sdk.utils.api import send_request, send_request_with_notifications
from fastapi import Request
from open_webui import config as open_webui_config
from pydantic import BaseModel, Field

class Pipe:
    class Valves(BaseModel):
        BEEAI_URL: str = Field(default="http://localhost:8333")
        ENABLED_AGENTS: List[str] = Field(default=[])

    def __init__(self):
        self.type = "pipe"
        self.valves = self.Valves()
        self.base_url = self.valves.BEEAI_URL.rstrip("/")
        self.mcp_url = f"{self.base_url}/mcp/sse"
        self.api_url = f"{self.base_url}/api/v1"
        self._agents = None
        self._send_request = partial(send_request, self.mcp_url)
        self._send_request_with_notifications = partial(send_request_with_notifications, self.mcp_url)

    async def pipes(self):
        return [
            {"id": agent_name, "name": f"beeai-{agent_name}"}
            for agent_name in await self._get_agents()
            if (
                not self.valves.ENABLED_AGENTS
                or agent_name in self.valves.ENABLED_AGENTS
            )
        ]

    async def pipe(
        self,
        body,
        __user__: dict | None,
        __request__: Request,
        __event_emitter__: Callable[[dict], Awaitable[None]] | None = None,
    ) -> AsyncGenerator[str, None]:
        """The main pipeline invocation function called by Open WebUI"""
        try:
            async def emit_event_safe(message: str):
                if __event_emitter__ is not None:
                    event_data = {
                        "type": "message",
                        "data": {"content": message + "\n"},
                    }
                    try:
                        await __event_emitter__(event_data)
                    except Exception as e:
                        logging.error(f"Error emitting event: {e}")

            # Ignore Open WebUI utility requests
            if self._is_open_webui_request(body):
                return

            # Parse the body parts
            model = body["model"]
            messages = body["messages"]

            # Look up which agent this is
            agent_name = model.rsplit(".")[-1]
            agent = (await self._get_agents()).get(agent_name)
            if agent is None:
                raise ValueError(f"Unknown agent model: {model}")

            # Format the agent input
            # TODO: More robust mapping not based on the UI type!
            match agent.ui.get("type"):
                case "chat":
                    req = {"messages": messages}
                case "hands-off":
                    user_messages = [msg for msg in messages if msg["role"] == "user"]
                    if not user_messages:
                        raise ValueError("No user messages found!")
                    req = {"text": user_messages[-1]["content"]}

                    # Get any context documents
                    if documents := self._parse_context_documents(messages):
                        req["documents"] = documents
                case _ as ui_type:
                    raise ValueError(f"Unknown agent type: {ui_type}")

            # Run the agent with streaming output
            last_result_streamed = False
            async for msg in self._send_request_with_notifications(
                acp_types.RunAgentRequest(
                    method="agents/run",
                    params=acp_types.RunAgentRequestParams(
                        name=agent_name,
                        input=req)
                    ),

                acp_types.RunAgentResult,
            ):
                match msg:
                    case acp_types.ServerNotification(
                        root=acp_types.AgentRunProgressNotification(
                            params=acp_types.AgentRunProgressNotificationParams(
                                delta=delta
                            )
                        )
                    ):
                        if delta_text := delta.get("text"):
                            last_result_streamed = True
                            yield delta_text
                        elif messages := delta.get("messages"):
                            for assistant_msg in messages:
                                if content := assistant_msg.get("content"):
                                    last_result_streamed = True
                                    yield content
                        elif logs := delta.get("logs"):
                            # Ignore logs after the real results start coming
                            if last_result_streamed:
                                continue
                            for log in list(filter(bool, logs)):
                                if text := log.get("message", "").strip():
                                    short_text = text[:50]
                                    if short_text != text:
                                        short_text += "..."
                                    metadata = log.get("metadata") or []
                                    if isinstance(metadata, str):
                                        metadata = [metadata]
                                    metadata = list(filter(bool, metadata))
                                    detail_body = "\n".join([text] + metadata)
                                    details = f"<details>\n\n<summary>{short_text}</summary>\n\n{detail_body}</details>\n"
                                    yield details
                        else:
                            logging.debug("Unknown delta: %s", delta)

                    case acp_types.RunAgentResult() as result:
                        if not last_result_streamed:
                            output_dict = result.model_dump().get("output", {})
                            if text := output_dict.get("text"):
                                last_result_streamed = False
                                yield text
                            elif messages := output_dict.get("messages"):
                                for assistant_msg in messages:
                                    if content := assistant_msg.get("content"):
                                        last_result_streamed = False
                                        yield content

                    case _:
                        log.debug("Unknown message type (%s): %s", type(msg), msg)

        except Exception as err:
            logging.error("Got an error! %s", err, exc_info=True)
            raise err

    ## Implementation Details ##################################################

    async def _get_agents(self) -> dict[str, acp_types.Agent]:
        if self._agents is None:
            result = await self._send_request(
                acp_types.ListAgentsRequest(method="agents/list"),
                acp_types.ListAgentsResult,
            )
            self._agents = {agent.name: agent for agent in result.agents}
        return self._agents

    def _is_open_webui_request(self, body):
        """
        Checks if the request is an Open WebUI task, as opposed to a user task
        """
        message = str(body["messages"][-1])

        prompt_templates = {
            open_webui_config.DEFAULT_RAG_TEMPLATE.replace("\n", "\\n"),
            open_webui_config.DEFAULT_TITLE_GENERATION_PROMPT_TEMPLATE.replace(
                "\n", "\\n"
            ),
            open_webui_config.DEFAULT_TAGS_GENERATION_PROMPT_TEMPLATE.replace(
                "\n", "\\n"
            ),
            open_webui_config.DEFAULT_IMAGE_PROMPT_GENERATION_PROMPT_TEMPLATE.replace(
                "\n", "\\n"
            ),
            open_webui_config.DEFAULT_QUERY_GENERATION_PROMPT_TEMPLATE.replace(
                "\n", "\\n"
            ),
            open_webui_config.DEFAULT_AUTOCOMPLETE_GENERATION_PROMPT_TEMPLATE.replace(
                "\n", "\\n"
            ),
            open_webui_config.DEFAULT_TOOLS_FUNCTION_CALLING_PROMPT_TEMPLATE.replace(
                "\n", "\\n"
            ),
        }

        for template in prompt_templates:
            if template is not None and template[:50] in message:
                return True

        return False

    @staticmethod
    def _parse_context_documents(messages) -> list[dict]:
        """Parse a list of documents in HF format if given in the messages.

        When passing documents to a Function, Open WebUI uses the system prompt
        in the following format:

        ...INSTRUCTIONS...
        <context>
        <source id="1">CONTENT</source>
        ...
        </context>
        ...SUFFIX...
        """
        system_messages = [msg["content"] for msg in messages if msg["role"] == "system"]
        if not system_messages:
            return []
        documents = []
        for msg in system_messages:
            if context_match := re.search("<context>((?s:.*?))</context>", msg):
                for source_match in re.findall(
                    '<source id="([0-9]+)">((?s:.*?))</source>',
                    context_match.group(1)):
                    documents.append({
                        "metadata": {
                            "title": source_match[0],
                        },
                        "page_content": source_match[1],
                    })
        return documents
