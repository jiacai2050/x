# Summary

[前言](README.md)

# 来龙去脉与设计哲学

- [构建系统的演进与痛点](philosophy/history-and-pain-points.md)
- [Zig 构建系统的哲学与愿景](philosophy/zig-build-philosophy.md)

# 核心概念解析

- [两阶段生命周期：配置期与执行期](concepts/phases-and-lifecycle.md)
- [计算图抽象：Step 与有向无环图 (DAG)](concepts/step-and-dag.md)
- [数据流与惰性路径：LazyPath 设计原理](concepts/lazy-path.md)
- [编译单元与产物解耦：Module vs Step.Compile](concepts/module-vs-artifact.md)
- [包管理与确定性缓存：build.zig.zon 与缓存布局](concepts/package-and-cache.md)

# 核心 API 与用法

- [标准选项与顶层入口：b.standardTargetOptions 与 b.step](api/options-and-entry.md)
- [产物构建与测试验证：Executable、Library、Test 与 ObjCopy](api/artifacts-api.md)
- [模块组织与命名空间：createModule、addModule 与 addImport](api/modules-api.md)
- [C/C++ 互操作与库导出：addTranslateC 与 linkLibrary](api/c-cpp-interop-api.md)
- [代码生成与配置注入：ConfigHeader、Options、WriteFiles 与 UpdateSourceFiles](api/code-generation-api.md)
- [第三方依赖引入与消费：b.dependency、--fork 与系统包集成](api/dependency-api.md)
- [编写自定义 Step：扩展构建管线](api/custom-steps.md)

# 工程实践

- [实战一：标准 Zig CLI 应用与单元测试](practices/practice-zig-app.md)
- [实战二：Zig 与 C/C++ 混合编程工程结构](practices/practice-mixed-c-zig.md)
- [实战三：复杂第三方 C 库的移植（以 MariaDB Connector 为例）](practices/practice-porting-c-library.md)
- [实战四：跨平台交叉编译与 Makefile/CI 自动化](practices/practice-cross-compile-ci.md)

# 底层运行机制

- [构建自举与双进程：Maker 与 Configurer 架构流转](internals/build-runner-internals.md)
- [编译器交接：Step.Compile 到子进程拼装](internals/step-compile-internals.md)
- [编译单元：ZCU (Zig Compilation Unit) 与单体编译](internals/zcu-internals.md)
- [内置 C 工具链：嵌入式 Clang 与 LLD 桥接](internals/clang-lld-internals.md)

# 附录

- [常用构建 API 速查表](appendix/api-cheatsheet.md)
- [从 0.16 迁移到 0.17 构建指南](appendix/migration-016-to-017.md)
