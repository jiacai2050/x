# 项目工程实践与技术演进记录

本项目是针对 **Zig 0.16.0 构建系统（Zig Build System）** 编写的系统化、源码级实战教程。本文档记录了从工程立项、章节编排、实战示例构建、文档润色到暗黑模式下 Mermaid 图表动态自适应引擎的完整演进过程。

---

## 目录索引

- [一、项目架构与章节规划](#一项目架构与章节规划)
- [二、实战示例矩阵与 CI 验证](#二实战示例矩阵与-ci-验证)
- [三、全书内容润色与技术去 AI 化](#三全书内容润色与技术去-ai-化)
- [四、Mermaid 暗黑主题适配引擎](#四mermaid-暗黑主题适配引擎)
- [五、维护与扩展指南](#五维护与扩展指南)

---

## 一、项目架构与章节规划

本书采用 [mdBook](https://rust-lang.github.io/mdBook/) 驱动，按照“由浅入深、理论结合源码、落地到工业实战”的思路划分为五个核心部分与一个附录，共 24 篇核心技术文章：

1. **第一部分：来龙去脉与设计哲学**
   - 从传统的 Make / CMake / Autotools 工具链痛点出发，阐明为何需要统一的语言级构建系统。
   - 剖析 Zig 构建系统的核心哲学：“构建逻辑即 Zig 源码”、全自包含交叉编译与确定性缓存。
2. **第二部分：核心概念深度解析**
   - **两阶段生命周期**：严格区分配置期（Graph Evaluation）与执行期（Graph Execution）。
   - **计算图抽象**：`std.Build.Step` 与有向无环图（DAG）的依赖构建与拓扑调度。
   - **编译单元解耦**：`std.Build.Module`（源码逻辑边界）与 `Step.Compile`（物理二进制产物）的解耦设计。
   - **惰性数据流**：`std.Build.LazyPath` 如何解决构建期文件路径尚未生成的时间悖论。
   - **包管理与缓存**：`build.zig.zon` 的包依赖清单与三级哈希缓存目录结构（`.zig-cache` 与 `~/.cache/zig`）。
3. **第三部分：核心 API 全景与实战用法**
   - 标准 CLI 参数解析（`-Dtarget`、`-Doptimize`）、顶层构建目标注册（`b.step`）。
   - 可执行文件、静态库/动态库、单元测试等产物的创建与安装。
   - 模块依赖树组织（`createModule`、`addModule`、`addImport`）。
   - C/C++ 源码混合编译与 `addTranslateC` 自动转译模块。
   - 代码动态生成（`addConfigHeader` 生成 `config.h`、`addWriteFiles` 动态生成 Zig 代码）。
   - 第三方包依赖引入（`b.dependency`）与自定义 `Step` 的实现范式。
4. **第四部分：源码级底层运行机制**
   - **Build Runner 运行器**：`lib/compiler/build_runner.zig` 的自举动态编译与子进程派生机制。
   - **参数序列化**：`Step.Compile.make()` 如何将高层配置平铺序列化为 `zig build-exe` / `zig build-lib` 终端参数。
   - **ZCU 单体编译**：Unity Build 式单体编译单元模型，AST -> ZIR -> AIR -> Native/LLVM 后端流水线。
   - **内置 C 工具链**：编译器进程内静态链接 Clang 与 LLD，通过 C ABI 导出函数 `ZigClang_main` 进程内调度编译。
5. **第五部分：实战工程最佳实践**
   - 标准 CLI 命令行应用与单元测试。
   - Zig 与 C 混合工程目录组织。
   - 复杂成熟 C 库移植范式（以开源的 [zig-mariadb-connector](https://github.com/jiacai2050/zig-mariadb-connector) 为工程蓝本）。
   - 跨平台交叉编译流水线与 Makefile/GitHub Actions CI 最佳实践。
6. **附录**
   - 常用构建 API 签名与使用场景速查表。

---

## 二、实战示例矩阵与 CI 验证

为了杜绝技术文档中常见的“代码示例过期”或“无法实际运行”的问题，项目在 `examples/` 目录下构建了 5 个完全独立的 Zig 0.16.0 真实工程，并在根目录通过 `Makefile` 实现一键全量自动化测试：

| 示例目录 | 核心验证场景 | 测试命令 |
| :--- | :--- | :--- |
| `examples/01-zig-app` | 核心业务库与 CLI 入口解耦、模块导入、单元测试 | `zig build run && zig build test` |
| `examples/02-mixed-c-zig` | C 头文件 `addTranslateC` 自动转译、C 源码与 libc 链接 | `zig build run` |
| `examples/03-code-generation` | CMake 风格 `addConfigHeader` 动态生成配置头文件 | `zig build run` |
| `examples/04-c-library-port` | 复杂 C 静态库封装、头文件树导出与集成测试验证 | `zig build test` |
| `examples/05-custom-step` | 自定义 Step 嵌入 DAG 构建流水线 | `zig build validate && zig build run` |

### 持续集成（CI）
在 `.github/workflows/ci.yml` 与 `deploy.yml` 中配置了：
- 多平台原生矩阵（Linux x86_64、macOS Apple Silicon、Windows x86_64）；
- Linux 下一键交叉编译 Windows x86_64 与 ARM64 验证；
- 自动化 GitHub Pages 文档站点部署。

---

## 三、全书内容润色与技术去 AI 化

使用 `humanizer-zh` 规范对全书共 24 篇 Markdown 文档进行了全面重构：
1. **剔除浮夸与情绪化宣传用词**：清除“精妙的自举动态编译”、“四大拦路虎”、“超级能力”、“革命性突破”等词汇，换以客观事实叙述。
2. **消除无用填充与机械对偶**：去除“不仅是一次……更是一场……”、“正如前面所说”、“让我们深入看看”等句式，删除无意义的“进行+动词”填充。
3. **保持图表与技术规范完整**：严格遵守 Zig 0.16.0 语法与源码链接，所有 Mermaid 架构图完整保留结构与色彩语义。

---

## 四、Mermaid 暗黑主题适配引擎

关于 Mermaid 在 mdBook 暗黑主题下不清晰、框内白底等问题的深度分析与运行时动态颜色映射解决方案，详见专门的技术文档：
- [Mermaid 暗黑主题动态适配技术详解](mermaid-dark-mode.md)

---

## 五、维护与扩展指南

- **本地实时预览**：
  ```bash
  mdbook serve --open
  ```
- **全量测试（书籍构建 + 全部示例工程测试）**：
  ```bash
  make test
  ```
- **格式化检查**：
  ```bash
  make fmt-check
  ```
