# Zig 构建系统指南 (`zig-build`) - 开发规范

本文档为参与《Zig 构建系统指南》编写与维护的 AI Agent 及协作者约定核心规范。

---

## 1. 写作与版本约定

- **版本号限制**：版本号只允许在 `README` 与迁移指南章节中出现；正文其余各章节保持通用技术阐述，不出现具体版本号（官方源码外链的不可变 Tag 锚点除外）。
- **代码注释与语言**：
  - 示例工程（`examples/`）及正文代码块中的**代码注释必须一律使用中文**；
  - 交流及文档正文全中文，严格遵循 `humanizer-zh` 风格，表达平实客观，杜绝套话。
- **在线地址**：<https://jiacai2050.github.io/x/zig-build/>（基于 mdBook）。

---

## 2. API 真实性与源码核对（零幻觉）

- **严禁捏造虚构 API**：全书所有构建 API 必须与 Zig 官方源码严格一致，严禁臆测不存在的方法或签名。遇到不确定的 API 或签名问题，必须直接查阅源码确认。
- **源码核对位置**：
  - 本地源码：`~/code/zig-0.17.0`（构建系统核心在 `lib/std/Build.zig` 与 `lib/std/Build/`，如 `Module.zig`、`Step/`）；
  - 远端源码：`https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig`。
- **禁止已废弃 API**：全部使用官方最新推荐 API（例如动态输出参数使用 `addOutputFileArg2`、库链接使用模块级 `linkLibrary`、启用 C++ 使用 `mod.link_libcpp = true` 等）。
- **源码外链锚点**：速查表与源码引用的外链必须使用指向官方源码不可变 Tag 锚点的精确行号链接，确保永久可访问。

---

## 3. 跨平台兼容性

- 示例与辅助工具必须原生支持 Windows、macOS 与 Linux。
- 命令行参数迭代严禁使用 Windows 下会导致 `@compileError` 的裸 `args.iterate()`，必须使用 `argsAlloc` 或 `iterateAllocator`。

---

## 4. Mermaid 图表规范

- 显式声明方向（优先垂直布局 `graph TB` / `flowchart TB`）。
- 包含 `[`、`]`、`(`、`)` 等特殊符号的节点文本必须用双引号包裹。
- 每个 `subgraph` 及其内部组件须配置清晰的语义化对比配色；静态图严禁包含流程箭头。

---

## 5. 质量验证与安全红线

- **自动化验证**：修改后必须运行 `make test`，确保书籍构建与 5 个工程示例全量绿灯通过。
- **安全红线**：任何情况下**严禁执行 `rm` 和 `git` 命令**；其余命令（`make`、`zig`、`mdbook` 等）可直接执行。
