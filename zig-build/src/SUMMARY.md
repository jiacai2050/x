# Summary

[前言](README.md)

# 第一部分：来龙去脉与设计哲学

- [构建系统的演进与痛点](part1/history-and-pain-points.md)
- [Zig 构建系统的哲学与愿景](part1/zig-build-philosophy.md)

# 第二部分：核心概念深度解析

- [两阶段生命周期：配置期与执行期](part2/phases-and-lifecycle.md)
- [计算图抽象：Step 与有向无环图 (DAG)](part2/step-and-dag.md)
- [编译单元与产物解耦：Module vs Step.Compile](part2/module-vs-artifact.md)
- [数据流与惰性路径：LazyPath 设计原理](part2/lazy-path.md)
- [包管理与确定性缓存：build.zig.zon 与缓存布局](part2/package-and-cache.md)

# 第三部分：核心 API 全景与实战用法

- [标准选项与顶层入口：b.standardTargetOptions 与 b.step](part3/options-and-entry.md)
- [产物构建：Executable、Library 与 Test](part3/artifacts-api.md)
- [模块组织与命名空间：createModule、addModule 与 addImport](part3/modules-api.md)
- [C/C++ 互操作与库导出：addTranslateC 与 linkLibrary](part3/c-cpp-interop-api.md)
- [动态生成与模板配置：addConfigHeader 与 addWriteFiles](part3/code-generation-api.md)
- [第三方依赖引入与消费：b.dependency](part3/dependency-api.md)
- [编写自定义 Step：扩展构建管线](part3/custom-steps.md)

# 第四部分：源码级底层运行机制

- [构建自举：Build Runner 的动态编译与调度](part4/build-runner-internals.md)
- [编译器交接：Step.Compile 到子进程拼装](part4/step-compile-internals.md)
- [编译单元：ZCU (Zig Compilation Unit) 与单体编译](part4/zcu-internals.md)
- [内置 C 工具链：嵌入式 Clang 与 LLD 桥接](part4/clang-lld-internals.md)

# 第五部分：实战工程最佳实践

- [实战一：标准 Zig CLI 应用与单元测试](part5/practice-zig-app.md)
- [实战二：Zig 与 C/C++ 混合编程工程结构](part5/practice-mixed-c-zig.md)
- [实战三：复杂第三方 C 库的完整移植实践（以 MariaDB Connector 为例）](part5/practice-porting-c-library.md)
- [实战四：跨平台交叉编译与 Makefile/CI 自动化](part5/practice-cross-compile-ci.md)

# 附录

- [常用构建 API 速查表](appendix/api-cheatsheet.md)
