# ShellGPT

[中文](README_zh.md)

[![](https://img.shields.io/pypi/v/shgpt)](https://pypi.org/project/shgpt/)
[![](https://github.com/jiacai2050/x/actions/workflows/shellgpt-ci.yml/badge.svg)](https://github.com/jiacai2050/x/actions/workflows/shellgpt-ci.yml)
[![](https://github.com/jiacai2050/x/actions/workflows/shellgpt-release.yml/badge.svg)](https://github.com/jiacai2050/x/actions/workflows/shellgpt-release.yml)

Chat with LLM in your terminal, be it shell generator, story teller, linux-terminal, etc.

# Install

```bash
pip install -U shgpt
```

or if you prefer to use [uvtool](https://docs.astral.sh/uv/concepts/tools/)

```bash
uv tool install shgpt
```

This will install two commands: `sg` and `shellgpt`, which are identical.

After install, use `sg --init` to create the required directory and a default configuration file (`~/.shellgpt/config.toml`).

# Usage

ShellGPT has three modes:

- **Direct mode**: `sg [question]` or via pipeline: `echo question | sg`.
- **REPL mode**: `sg --repl` for an interactive chat.
- **TUI mode**: `sg --tui` for a text user interface, tailored for shell command inference.

## Configuration

ShellGPT is configured via `~/.shellgpt/config.toml`. You can change the configuration directory by setting the `SHELLGPT_CONF_DIR` environment variable.

### Multiple Profiles

Define your API settings in the `[profiles]` section and switch between them using the `-p / --profile` flag.

```toml
# ~/.shellgpt/config.toml
default_profile = "ollama"

[profiles.ollama]
base_url = "http://localhost:11434/v1"
model = "llama3"

[profiles.openai]
base_url = "https://api.openai.com/v1"
# You can provide api_key directly
api_key = "sk-xxxx"
# Or provide the name of the environment variable that contains the API key
# api_key_env = "OPENAI_API_KEY"
model = "gpt-4o"
# Headers support environment variable substitution ($VAR or ${VAR})
headers = { "Authorization" = "Bearer $OPENAI_API_KEY", "X-My-Header" = "value" }

# https://docs.github.com/en/github-models/quickstart
[profiles.github]
base_url = "https://models.github.ai/inference"
api_key = "ghp_xxxx"
model = "gpt-4o"

# https://developers.cloudflare.com/workers-ai/configuration/open-ai-compatibility/
[profiles.cloudflare]
base_url = "https://api.cloudflare.com/client/v4/accounts/<account-id>/ai/v1"
api_key = "<token>"
model = "@cf/meta/llama-3-8b-instruct"

# https://developers.cloudflare.com/ai-gateway/usage/chat-completion/
[profiles.cloudflare-gateway]
base_url = "https://gateway.ai.cloudflare.com/v1/<account-id>/<gateway-id>/compat"
api_key = "sk-xxxx"
model = "gpt-4o"
```

Usage:

```bash
# Uses default_profile (ollama)
sg How to center a div?

# Uses OpenAI profile
sg -p openai Write a poem about rust
```

### Global Settings

You can override global defaults at the top level of the config file:

```toml
timeout = 60
stream = true
temperature = 0.8
```

## Roles

Roles allow you to define specific system prompts for different tasks. They are managed in the `[roles]` section of your config.

Built-in examples (created during `sg --init`):

- `shell`: Infer shell commands.
- `typo`: Correct text typos.
- `code`: Coding assistant.
- `summary`: Summarize text in Markdown.
- `polish`: Polish writing.

Usage:

```bash
# List all available roles and their contents
sg --list

# Use a specific role
sg -s typo I is a enginer
git diff | sg -s commit
```

### Custom Roles

Add your own roles to `config.toml`:

```toml
[roles]
translator = "You are a professional translator. Translate everything to Japanese."
```

Then use it with `sg -s translator Hello world`.

## TUI

Key bindings in TUI mode:

- `ctrl+j`: Infer answer
- `ctrl+r`: Run command
- `ctrl+y`: Yank command

![TUI screenshot](https://github.com/jiacai2050/shellgpt/raw/main/assets/shellgpt-tui.jpg)

# License

[GPL-3.0](https://opensource.org/license/GPL-3.0)
