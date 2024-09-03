# LM Desk

**Welcome to LM Desk 👋!**

The LM Desk project is a central entrypoint for configuring a set of awesome tools that will power your desktop productivity using generative AI. This is a project-of-projects that brings together the best open source tools to get you developing faster.

## Quick Start

```sh
bash -c "$(curl -fsSL 'https://raw.githubusercontent.com/IBM/lm-desk/main/get-lm-desk.sh')"
```

## Principles

- **5-Minutes to Happiness**: You should be able to get up and running with these AI tools in 5 minutes or less (as long as you have a fast internet connection!)
- **Meet You Where You Are**: These tools should work seamlessly with the tools you already have installed on your machine without requiring you to change tools you already love.
- **Open Source:** All code is open source and freely available for anyone to use, modify, and distribute. All models have open weights and are freely available for anyone to use.
- **Interoperability:** The tools should be interoperable with each other so that they can be easily integrated into your workflow.
- **Business Friendly Licensing:** The tools should be business friendly licenses so that you can use them, modify them, and distribute them without any legal hurdles.

## Projects

### Models

- [IBM Granite Code](https://github.com/ibm-granite) ([HuggingFace](https://huggingface.co/collections/ibm-granite/granite-code-models-6624c5cec322e4c148c8b330), [GitHub](https://github.com/ibm-granite)): IBM Granite Code is a set of open weights AI models with permissive licenses that are tuned for code completion, documentation generation, and other development tasks.

### Local Model Serving

- [Ollama](https://ollama.com/) ([GitHub](https://github.com/ollama/ollama)): Ollama is an engine for managing and running multiple AI models in a local environment.
- [ollama-bar](https://github.com/IBM/ollama-bar): `ollama-bar` is a bar macOS app that provides a menu-bar interface to manage Ollama and other tools that work with Ollama.

### AI-Infused Development

- [Visual Studio Code](https://code.visualstudio.com/) ([GitHub](https://github.com/microsoft/vscode)): Visual Studio Code is a free, open-source code editor developed by Microsoft. It can be extended with plugins to add support for generative AI models.
- [Continue](https://www.continue.dev/) ([GitHub](https://github.com/continuedev/continue)): Continue is an IDE plugin that brings together AI models to power your development workflow. It includes features such as code completion, debugging, and linting.

### AI-App Development

- [Open WebUI](https://openwebui.com/) ([GitHub](https://github.com/open-webui/open-webui)): Open WebUI provides a rich web interface for prototyping AI applications using the most popular generative AI design patterns (prompt engineering, RAG, tool calling, etc.). It is build to work seamlessly with `ollama` and take advantage of the models you have available locally.
