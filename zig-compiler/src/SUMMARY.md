# 目录

[前言与导读](README.md)

# 第 1 部分：编译原理入门与 Zig 全景宏观设计
- [1.1 经典编译器的标准阶段](overview/compiler_basics.md)
- [1.2 经典编译器的痛点与反思](overview/traditional_pitfalls.md)
- [1.3 Zig 0.17 编译器全景架构](overview/zig_architecture_overview.md)
- [1.4 Zig 与主流编译器的核心差异对比](overview/zig_vs_others.md)

# 第 2 部分：极致的数据导向设计 (Data-Oriented Design)
- [2.1 为什么面向对象 AST 会摧毁 CPU 缓存](frontend/why_dod.md)
- [2.2 MultiArrayList 的奥秘：SoA 代替 AoS 深度剖析](frontend/multi_array_list.md)
- [2.3 零指针 AST：13 字节紧凑节点与 extra_data](frontend/zero_pointer_ast.md)
- [2.4 Tokenizer 与 8:1 内存估算哲学](frontend/tokenizer_and_allocation.md)

# 第 3 部分：双层 IR 设计与缓存哲学
- [3.1 为什么需要两套 IR：无类型与全类型的解耦](ir/why_dual_ir.md)
- [3.2 ZIR 架构与指令体系](ir/zir_architecture.md)
- [3.3 AstGen：AST 如何平铺降级为线性 ZIR](ir/ast_to_zir.md)
- [3.4 ZIR 独立磁盘缓存与增量编译护城河](ir/zir_caching.md)
- [3.5 AIR 架构与全类型运行时表示](ir/air_architecture.md)

# 第 4 部分：编译器心脏：Sema 与 Comptime 执行引擎
- [4.1 Comptime 到底是什么：无宏与无泛型代码膨胀](sema/comptime_explained.md)
- [4.2 统一语义分析与解释器：Sema.zig 剖析](sema/sema_core.md)
- [4.3 极致的懒惰：按需依赖分析机制](sema/lazy_analysis.md)
- [4.4 类型与常量驻留池：InternPool.zig 深度剖析](sema/intern_pool.md)
- [4.5 细粒度增量依赖追踪：AnalUnit 与级联失效](sema/dependency_tracking.md)

# 第 5 部分：流水线调度与多线程并发模型
- [5.1 编译单元管家：Compilation.zig 与 Zcu.zig](pipeline/compilation_and_zcu.md)
- [5.2 线程模型与分片架构：PerThread 与 Shards](pipeline/concurrency_model.md)
- [5.3 重叠流水线：Sema、Codegen 与 Linker 的异步并发](pipeline/overlapped_pipeline.md)

# 第 6 部分：多后端生态与机器码生成
- [6.1 Zig 后端全景架构与统一调度](codegen/backend_overview.md)
- [6.2 自研原生机器码后端：x86_64 与 AArch64 剖析](codegen/native_backends.md)
- [6.3 C 后端：终极可移植性与自举桥梁](codegen/c_backend.md)
- [6.4 LLVM 后端：AIR 到 LLVM IR 的桥梁与极限优化](codegen/llvm_backend.md)
- [6.5 MIR 机器中间表示、寄存器分配与 Legalize](codegen/mir_and_legalize.md)
- [6.6 后端性能对比与最佳实践](codegen/backend_comparison.md)

# 第 7 部分：颠覆传统的自研增量链接器
- [7.1 为什么现代编译器普遍死在链接上？](linker/why_native_linkers.md)
- [7.2 Zig 自研链接器矩阵：ELF, Mach-O, COFF, WASM](linker/linker_matrix.md)
- [7.3 内存原位增量二进制重写：无需全量重连](linker/incremental_patching.md)
- [7.4 链接器与编译器前端的端到端穿透协作](linker/linker_frontend_synergy.md)

# 第 8 部分：端到端实战演练：跟随 main.zig 走完一生
- [8.1 一个完整 main.zig 程序的端到端编译旅程](walkthrough/example_walkthrough.md)

# 结语
- [总结与未来展望](epilogue/future.md)
- [附录：Zig 0.17.0 Release Notes 编译架构演进深度解读](epilogue/release_0_17_notes.md)
