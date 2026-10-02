# Zig 构建系统指南

> 基于 Zig 0.16.0 API 与编译器源码分析

---

## 为什么写这本书？

系统级编程中的构建流程通常比较繁琐：
- C/C++ 依赖 Autotools、Make、CMake 等工具，跨平台配置和交叉编译环境搭建成本较高；
- 现代语言（如 Rust Cargo、Go）统一了语言内的包管理，但遇到 C/C++ 依赖混编、代码生成或交叉编译时，仍需通过 `build.rs` 或 CGo 脚本调用外部工具链。

Zig 提供了另一种思路：
1. **直接用 Zig 编写构建逻辑（No DSL, Just Zig）**：不再引入专用的构建脚本语言，构建逻辑直接在 `build.zig` 中使用标准 Zig 编写；
2. **自包含工具链**：Zig 单体二进制内嵌了 Clang 编译器、LLD 链接器以及主流平台的 libc 符号库，无需额外安装目标平台的外部交叉编译环境；
3. **有向无环图（DAG）模型**：构建脚本负责在内存中声明依赖任务图，由多线程调度引擎执行并结合哈希指纹做增量缓存；
4. **编译单元与产物解耦**：通过 `std.Build.Module` 与 `std.Build.Step.Compile` 的分工，模块配置可以在静态库、动态库与测试目标间复用。

由于 Zig 处于快速迭代期（当前开发分支为 0.16.0），网络上较多旧版本（0.11、0.12 等）的代码片段已无法直接使用。本书梳理 Zig 构建系统的核心抽象、常用 API 以及底层执行机制，帮助读者掌握基于现代 Zig 的构建实践。

---

## 本书内容组织

全书分为五个部分与附录：

1. **第一部分：来龙去脉与设计哲学**
   - 梳理构建工具的演进过程与痛点；
   - 介绍 Zig 构建系统的设计哲学与自包含工具链。
2. **第二部分：核心概念深度解析**
   - 配置期（Configuration）与执行期（Execution）生命周期；
   - 任务计算图抽象：`std.Build.Step` 与 DAG 拓扑；
   - 模块与产物解耦：`Module` vs `Step.Compile`；
   - 惰性路径：`LazyPath` 的设计与依赖推导；
   - 包管理模型：`build.zig.zon` 与 `.zig-cache` 缓存布局。
3. **第三部分：核心 API 全景与实战用法**
   - 编译选项解析与顶层 Step 注册；
   - 可执行文件、库与单元测试产物构建；
   - 模块命名空间管理与子模块导入（`addImport`）；
   - C/C++ 互操作、头文件包含路径传播与头文件树导出；
   - 模板替换（`addConfigHeader`）与文件动态生成；
   - 依赖包消费（`b.dependency`）与自定义 Step 开发。
4. **第四部分：源码级底层运行机制**
   - Build Runner 的动态编译与调度流程；
   - `Step.Compile.make()` 拼装底层 CLI 命令细节；
   - 单体编译单元 ZCU 与跨模块 comptime 分析机制；
   - 内置 Clang 前端 C++ FFI 桥接（`ZigClang_main`）与链接器合并机制。
5. **第五部分：实战工程最佳实践**
   - 纯 Zig 应用程序工程范式；
   - Zig 与 C/C++ 混合编程结构；
   - 复杂第三方 C 库的移植实践（以 MariaDB Connector/C 为例）；
   - 跨平台交叉编译与 GitHub Actions CI 流水线。
6. **附录**
   - `std.Build` 常用 API 速查表。

---

## 环境与代码约定

- **Zig 版本**：基于 **Zig 0.16.0**。
- **示例代码**：
  - 本书涉及的全部实战示例均位于 `examples/` 目录下，支持独立编译与测试；
  - 复杂 C 库移植工程参考开源项目 [zig-mariadb-connector](https://github.com/jiacai2050/zig-mariadb-connector)；
  - 源码分析基于 [Zig 官方 0.16.0 源码树](https://codeberg.org/ziglang/zig/src/tag/0.16.0)。
- **代码注释**：示例代码中的注释均使用英文，正文采用中文叙述。
