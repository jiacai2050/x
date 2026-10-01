# My Works

## Repository Overview
This repository is a monorepo containing various independent projects developed by Jiacai Liu. It includes browser extensions, CLI tools, system-level experiments (OS/Kernel), and FFI demonstrations.

## Project Structure
The repository is organized into subdirectories, each representing a standalone project:

| Category | Projects |
| :--- | :--- |
| **Browser Extensions** | `gooreplacer`, `link-preview`, `text-saver` |
| **CLI Tools (Python)** | `shellgpt`, `video-compress`, `zigcc` |
| **System/Low-level** | `zigos` (OS kernel), `rust-ffi` (FFI demos), `zms` (Zig mirror server) |
| **Proxy & Networking (Go)** | `openai-gateway`, `socks2http` |
| **Serverless** | `serverless-webdav` (Cloudflare Workers) |
| **Shared Scripts** | `common/` (Shared extension build/CSS assets) |

## Shared Tooling & Standards
The root directory provides unified linting and formatting for the entire repository.

### Prerequisites
- Node.js & npm (for linting and formatting)

### Common Commands
| Command | Description |
| :--- | :--- |
| `make write` | Format all supported files using Prettier |
| `make check` | Run ESLint and check formatting without modifying files |
| `make git` | Set up local git hooks (e.g., `prepare-commit-msg`) |

## Development Conventions
- **Formatting:** Prettier is used for global consistency.
- **Linting:** ESLint is used for JavaScript/TypeScript files.
- **Git Hooks:** A custom `prepare-commit-msg` hook is used to maintain commit standards.
- **Documentation:** Each sub-project has its own `GEMINI.md` and usually a `README.org` or `README.md`.
