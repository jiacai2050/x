# Summary

[前言](README.md)

# 来龙去脉与设计哲学

- [I/O 模型的演进与两大范式：Readiness 与 Completion](philosophy/readiness-vs-completion.md)
- [语言异步机制的二维空间：推进模型与栈模型](philosophy/push-pull-and-stack-models.md)
- [Zig I/O 的设计抉择：统一抽象与有栈纤程](philosophy/zig-io-philosophy.md)

# 核心概念与对象模型

- [统一接口抽象：std.Io 与 VTable 体系](concepts/io-interface-and-vtable.md)
- [内存借出与取消安全：CancelRegion 与生命周期追踪](concepts/buffer-ownership-and-cancellation.md)
- [现代数据流抽象：Reader 与 Writer 的重新设计](concepts/reader-and-writer.md)
- [并发基石：Task、Future 与 Group 协同](concepts/tasks-futures-and-groups.md)

# 核心 API 与基础 I/O

- [文件系统与目录操作：Dir 与 File API](api/file-system-and-directory.md)
- [高效数据流操作：缓冲读写、格式化与零拷贝 sendFile](api/streaming-reader-writer.md)
- [网络通信：TCP/UDP 套接字与高并发监听](api/networking-sockets.md)
- [子进程、管道与终端交互：Process 与 Terminal](api/process-pipe-terminal.md)
- [并发同步原语：Mutex、RwLock、Semaphore 与 Futex](api/synchronization-primitives.md)

# 运行机制与底层后端

- [纤程调度机制：fiber.zig 与用户态上下文切换](internals/fiber-and-context-switch.md)
- [Linux 完成型驱动：Uring (io_uring) 运行机制](internals/uring-backend.md)
- [macOS 与 BSD 事件集成：Dispatch 与 Kqueue](internals/dispatch-and-kqueue.md)
- [通用线程池降级：Threaded 后端机制](internals/threaded-backend.md)

# 工程实战

- [实战一：高性能 CLI 文本统计工具（wc 与 grep）](practices/practice-cli-text-tool.md)
- [实战二：零拷贝流式处理与文件传输](practices/practice-file-server.md)
- [实战三：高并发网络服务与 Fiber 调度](practices/practice-echo-server.md)
- [实战四：结构化并发与优雅停机（Graceful Shutdown）](practices/practice-structured-concurrency.md)

# 附录

- [Zig I/O API 核心速查表](appendix/api-cheatsheet.md)
- [从旧版 std.io 到现代 std.Io 迁移指南](appendix/migration-guide.md)
