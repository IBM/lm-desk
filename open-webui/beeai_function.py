"""
General-purpose Open WebUI Function for BeeAI agents
"""
# Standard
from typing import AsyncGenerator, Awaitable, Callable, Iterable, List
import logging
import re

# Third Party
from acp_sdk.client import Client
from acp_sdk import (
    Message,
    Agent,
    GenericEvent,
    MessagePartEvent,
    MessagePart,
)



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
        base_url = self.valves.BEEAI_URL.rstrip("/")
        self.client = Client(base_url=f"{base_url}/api/v1/acp")
        self._agents = None

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
            match agent.metadata.ui.get("type"):
                case "chat":
                    req = [Message(parts=[msg]) for msg in messages]
                case "hands-off":
                    user_messages = [msg for msg in messages if msg["role"] == "user"]
                    if not user_messages:
                        raise ValueError("No user messages found!")
                    req = Message(parts=[MessagePart(content=user_messages[-1]["content"])])

                    # Get any context documents
                    documents = []
                    for i, document in enumerate(self._parse_context_documents(messages) or []):
                        if content := document.get("page_content"):
                            title = document.get("metadata", {}).get("title", str(i + 1))
                            documents.append(
                                Message(
                                    parts=[MessagePart(content=content, role="document", title=title)]
                                )
                            )
                    if documents:
                        req = documents + [req]
                case _ as ui_type:
                    raise ValueError(f"Unknown agent type: {ui_type}")

            # Run the agent with streaming output
            logging.info("Calling agent: %s", agent.name)
            last_log = True
            async for event in self.client.run_stream(agent=agent.name, input=req):
                match event:
                    case GenericEvent():
                        if not last_log:
                            continue
                        data = self._filter_dict(event.generic.model_dump())
                        if "agent_name" in data:
                            (_, content) = list(self._omit(data, {"agent_name", "agent_idx"}).items())[0]
                            new_log_type = f"\[{data['agent_name']}]: {new_log_type}"
                        else:
                            (_, content) = list(data.items())[0]
                        content = content.strip()
                        if content:
                            short_text = content[:50]
                            if short_text != content:
                                while short_text[-3:] != "...":
                                    short_text += "."
                            details = f"<details>\n\n<summary>{short_text}</summary>\n\n{content}</details>\n"
                            yield details

                    case MessagePartEvent():
                        last_log = False
                        yield event.part.content

                    case _:
                        logging.debug("Unknown event type (%s): %s", type(event), event)

        except Exception as err:
            logging.error("Got an error! %s", err, exc_info=True)
            raise err

    ## Implementation Details ##################################################

    @staticmethod
    def _filter_dict(map: dict, value_to_exclude=None) -> dict:
        """Remove entries with unwanted values (None by default) from dictionary."""
        return {filter: value for filter, value in map.items() if value is not value_to_exclude}

    @staticmethod
    def _omit(dict: dict, keys: Iterable[str]) -> dict:
        return {key: value for key, value in dict.items() if key not in keys}

    async def _get_agents(self) -> dict[str, Agent]:
        if self._agents is None:
            self._agents = {agent.name: agent async for agent in self.client.agents()}
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
