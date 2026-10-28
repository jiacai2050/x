# Zig I/O 与并发编程指南 (`zig-io`) - 开发规范

本文档为参与《Zig I/O 与并发编程指南》编写与维护的 AI Agent 及协作者约定核心规范。

---

## 1. 写作与版本约定

- **版本号限制**：版本号只允许在 `README` 与迁移指南章节中出现；正文其余各章节保持通用技术阐述，不出现具体版本号（官方源码外链的不可变 Tag 锚点除外）。
- **代码注释与语言**：
  - 示例工程（`examples/`）及正文代码块中的**代码注释必须一律使用中文**；
  - 交流及文档正文全中文，严格遵循平实、客观的工程化技术表达，杜绝套话。
- **在线地址**：<https://jiacai2050.github.io/x/zig-io/>（基于 mdBook）。

---

## 2. API 真实性与源码核对（零幻觉）

- **严禁捏造虚构 API**：全书所有 I/O 与并发 API 必须与 Zig 官方源码严格一致，严禁臆测不存在的方法或签名。遇到不确定的 API 或签名问题，必须直接查阅源码确认。
- **源码核对位置**：
  - 本地源码：`~/code/zig-0.17.0`（核心位于 `lib/std/Io.zig` 与 `lib/std/Io/`，如 `Reader.zig`、`Writer.zig`、`fiber.zig`、`File.zig`、`net.zig`、`Threaded.zig`、`Uring.zig`）；
  - 远端源码：`https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig`。
- **杜绝已废弃 API**：全部使用现代 `std.Io` 标准库 API（禁止使用已被替换的泛型 `std.io.Reader`/`std.io.Writer` mixin 宏模式，统一使用 `std.Io.Reader`、`std.Io.Writer`、`std.Io` 实例）。
- **源码外链锚点**：速查表与源码引用的外链必须使用指向官方源码不可变 Tag 锚点的精确行号链接，确保永久可访问。

---

## 3. 跨平台兼容性

- 示例与理论阐述涵盖 Linux、macOS 与 Windows。
- 区分底层驱动模型的差异（Linux `io_uring`、macOS `Dispatch`/`Kqueue`、通用 `Threaded`）。

---

## 4. Mermaid 图表规范

- 显式声明方向（优先垂直布局 `graph TB` / `flowchart TB` 或清晰的时序图 `sequenceDiagram`）。
- 包含 `[`、`]`、`(`、`)` 等特殊符号的节点文本必须用双引号包裹。
- 保证语义清晰与明暗主题自适应。

---

## 5. 质量验证与安全红线

- **自动化验证**：修改后必须运行 `make test`，确保书籍构建（`mdbook build`）与示例工程全量绿灯通过。
- **安全红线**：任何情况下**严禁执行 `rm`、`git push` 和 `git reset --hard` 等破坏性命令**；临时生成文件严禁放置于 `/tmp`，必须位于本地 `.tmp/`。
