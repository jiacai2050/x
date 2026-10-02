# ShellGPT

[English](README.md)

[![](https://img.shields.io/pypi/v/shgpt)](https://pypi.org/project/shgpt/)
[![](https://github.com/jiacai2050/x/actions/workflows/shellgpt-ci.yml/badge.svg)](https://github.com/jiacai2050/x/actions/workflows/shellgpt-ci.yml)
[![](https://github.com/jiacai2050/x/actions/workflows/shellgpt-release.yml/badge.svg)](https://github.com/jiacai2050/x/actions/workflows/shellgpt-release.yml)

在终端直接与大语言模型（LLM）对话。它可以是你的 Shell 命令生成器、故事演说家、Linux 终端专家等。

# 安装

```bash
pip install -U shgpt
```

或者使用 [uvtool](https://docs.astral.sh/uv/concepts/tools/):

```bash
uv tool install shgpt
```

安装后会提供两个完全等价的命令：`sg` 和 `shellgpt`。

首次安装后，请运行 `sg --init` 来创建必要的目录和默认配置文件（`~/.shellgpt/config.toml`）。

# 使用方法

ShellGPT 提供三种模式：

- **直接模式 (Direct mode)**: `sg [问题]` 或通过管道：`echo 问题 | sg`。
- **对话模式 (REPL mode)**: `sg --repl` 进入交互式对话。
- **界面模式 (TUI mode)**: `sg --tui` 进入终端图形界面，专为生成和执行 Shell 命令设计。

## 配置

ShellGPT 通过 `~/.shellgpt/config.toml` 进行配置。你可以通过设置 `SHELLGPT_CONF_DIR` 环境变量来更改配置目录。

### 多 Profile 支持

在 `[profiles]` 部分定义不同的 API 设置，并使用 `-p / --profile` 参数快速切换。

```toml
# ~/.shellgpt/config.toml
default_profile = "ollama"

[profiles.ollama]
base_url = "http://localhost:11434/v1"
model = "llama3"

[profiles.openai]
base_url = "https://api.openai.com/v1"
# 直接提供 API Key
api_key = "sk-xxxx"
# 或者提供包含 API Key 的环境变量名
# api_key_env = "OPENAI_API_KEY"
model = "gpt-4o"
# Headers 支持环境变量替换 ($VAR 或 ${VAR})
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

用法示例：

```bash
# 使用默认配置 (ollama)
sg 如何水平居中一个 div？

# 使用 OpenAI 配置
sg -p openai 用 Rust 写一首诗
```

### 全局设置

你可以在配置文件顶部覆盖全局默认值：

```toml
timeout = 60
stream = true
temperature = 0.8
```

## 角色 (Roles)

角色允许你为不同任务预定义系统提示词（System Prompts）。你可以在配置文件的 `[roles]` 部分进行管理。

内置示例（运行 `sg --init` 后自动生成）：

- `shell`: 推理 Shell 命令。
- `typo`: 纠正文本拼写错误。
- `code`: 编程助手。
- `summary`: 以 Markdown 格式总结文章。
- `polish`: 润色文字。

用法示例：

```bash
# 列出所有可用角色及其内容
sg --list

# 使用特定角色
sg -s typo I is a enginer
git diff | sg -s commit
```

### 自定义角色

在 `config.toml` 中添加你自己的角色：

```toml
[roles]
translator = "你是一位专业的翻译官，请将所有输入翻译成日语。"
```

然后使用 `sg -s translator 你好，世界`。

## TUI 模式

TUI 模式下的快捷键：

- `ctrl+j`: 推理回答
- `ctrl+r`: 运行命令
- `ctrl+y`: 复制命令

![TUI 截图](https://github.com/jiacai2050/shellgpt/raw/main/assets/shellgpt-tui.jpg)

# 许可证

[GPL-3.0](https://opensource.org/license/GPL-3.0)
