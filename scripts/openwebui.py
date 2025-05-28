# /// script
# requires-python = ">=3.11,<3.12"
# dependencies = [
#     "open-webui>=0.6.9",
#     "acp-sdk>=0.10.0,<0.11"
# ]
# ///
"""
This script will configure and launch Open WebUI via uv with the appropriate
added dependencies
"""

# Standard
from pathlib import Path
import argparse
import base64
import importlib.metadata
import os
import random

# Third Party
import uvicorn

def update():
    """When running for an update, don't do anything except print out the
    version of open-webui
    """
    print(f"Open WebUI version: {importlib.metadata.version('open-webui')}")

def main():
    """When running as the persistent server, run and stay alive"""
    KEY_FILE = Path.cwd() / ".webui_secret_key"

    os.environ["FROM_INIT_PY"] = "true"
    os.environ['WEBUI_SECRET_KEY'] = "l*cals3cre7*"
    os.environ["WEBUI_AUTH"] = "False"


    if os.getenv("WEBUI_SECRET_KEY") is None:
        if not KEY_FILE.exists():
            KEY_FILE.write_bytes(base64.b64encode(random.randbytes(12)))
        os.environ["WEBUI_SECRET_KEY"] = KEY_FILE.read_text()

    if os.getenv("USE_CUDA_DOCKER", "false") == "true":
        LD_LIBRARY_PATH = os.getenv("LD_LIBRARY_PATH", "").split(":")
        os.environ["LD_LIBRARY_PATH"] = ":".join(
            LD_LIBRARY_PATH
            + [
                "/usr/local/lib/python3.11/site-packages/torch/lib",
                "/usr/local/lib/python3.11/site-packages/nvidia/cudnn/lib",
            ]
        )
        try:
            import torch

            assert torch.cuda.is_available(), "CUDA not available"
        except Exception as e:
            os.environ["USE_CUDA_DOCKER"] = "false"
            os.environ["LD_LIBRARY_PATH"] = ":".join(LD_LIBRARY_PATH)


    import open_webui.main  # we need set environment variables before importing main

    host: str = "0.0.0.0"
    port: int = 8080
    reload: bool = True

    uvicorn.run(open_webui.main.app, host=host, port=port, forwarded_allow_ips="*")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument(
        "-U",
        "--update",
        action="store_true",
        default=False,
        help="Run in 'update mode'. Just prints the version of Open WebUI and exits",
    )
    args = parser.parse_args()
    if args.update:
        update()
    else:
        main()
