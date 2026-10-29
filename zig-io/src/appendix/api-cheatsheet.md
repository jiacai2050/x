# Zig I/O API 核心速查表与系统调用底层映射

本文档汇集 Zig `std.Io` 标准库的核心 API 签名、官方源码不可变 Tag 锚点，以及在 Linux / POSIX 底层对应的系统调用或 `io_uring` 操作码。

---

## 1. 统一接口与调度基石 (`std.Io`)

源码位置：[`lib/std/Io.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig)

| 操作分类 | 常用 API 签名 | 底层系统调用 / 硬件动作 | 说明与功能 |
| :--- | :--- | :--- | :--- |
| **异步纤程派生** | [`io.async(func, args)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig#L2526) | 纯用户态内联汇编（`fiber.zig`） | 在事件环上派生轻量有栈纤程，零跨核同步开销，返回 `Future` |
| **多核并行派发** | [`io.concurrent(func, args)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig#L2565) | 线程池原子入队 + `sys_futex` 唤醒 | 派发至物理工作线程池并行执行，返回 `ConcurrentError!Future` |
| **等待收敛** | `future.await(io)` | 纤程挂起让出 CPU 或条件变量等待 | 挂起当前上下文，直到目标任务执行完毕返回物理结果 |
| **任务中断** | `future.cancel(io)` | `IORING_OP_ASYNC_CANCEL` / 信号中断 | 触发任务取消，经由取消屏障安全收敛 |
| **协作休眠** | `io.sleep(timeout)` | `IORING_OP_TIMEOUT` / `EVFILT_TIMER` | 协作型非阻塞睡眠等待，让出当前纤程 |
| **硬件高熵随机** | `io.random(buffer)` | `getrandom(2)` / `sysctl(KERN_ARND)` | 填充操作系统强随机字节 |

---

## 2. 结构化任务组 (`Io.Group`)

源码位置：[`lib/std/Io.zig#L1338`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig#L1338)

| 方法签名 | 底层数据结构与物理行为 |
| :--- | :--- |
| `var group: Io.Group = .init` | 静态初始化控制块，原子计数器 `active_count = 0` |
| `group.async(io, func, args)` | 原子自增 `active_count`，向当前事件环压入协作纤程 |
| `group.concurrent(io, func, args)` | 原子自增 `active_count`，向全局工作线程池投递并行任务 |
| `group.await(io)` | 挂起父纤程，直到所有子任务退出且 `active_count == 0` 时收敛唤醒 |
| `group.cancel(io)` | 向组内所有未完成的子任务广播原子取消信号，驱动在途 I/O 撤回 |

---

## 3. 文件系统与目录 (`Io.Dir` & `Io.File`)

源码位置：[`lib/std/Io/Dir.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Dir.zig) 与 [`lib/std/Io/File.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/File.zig)

| 场景 | 方法调用 | 操作系统底层系统调用映射 |
| :--- | :--- | :--- |
| **获取进程工作目录** | `var cwd = Io.Dir.cwd()` | 全局 `AT_FDCWD` 虚拟文件描述符 |
| **防御性打开/创建文件** | `var f = try dir.createFile(io, path, .{})`<br>`var f = try dir.openFile(io, path, .{})` | `openat(dir.handle, path, O_CLOEXEC | O_NOFOLLOW)` 防御 TOCTOU |
| **位置无关定位读写** | `file.readPositional(io, slices, offset)`<br>`file.writePositional(io, buffer, offset)` | `preadv` / `pwritev` / `IORING_OP_WRITEV`（零内核游标锁竞争） |
| **物理持久化刷盘** | `try file.sync(io)` | `fsync(2)` / `fdatasync(2)` / `IORING_OP_FSYNC` |
| **内核文件锁** | `try file.lock(io, .shared)` / `unlock(io)` | `fcntl(fd, F_SETLK)` 系统级排他/共享锁 |
| **虚存直接映射** | `var mmap = try file.createMemoryMap(io, .{ .len = size })` | `mmap(NULL, len, PROT_READ, MAP_SHARED, fd, 0)` 页缓存直接映射 |

---

## 4. 流式传输与零拷贝 (`Io.Reader` & `Io.Writer`)

源码位置：[`lib/std/Io/Reader.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Reader.zig) 与 [`lib/std/Io/Writer.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Writer.zig)

| 操作模式 | 典型代码 | 微架构与系统调用行为 |
| :--- | :--- | :--- |
| **构建带缓冲 Reader** | `var r_inst = file.reader(io, &buf); const r = &r_inst.interface;` | 内部维护 `seek` 与 `end` 滑动窗口游标 |
| **构建带缓冲 Writer** | `var w_inst = file.writer(io, &buf); const w = &w_inst.interface;` | 聚合小包写入，仅在满载或显式 `flush()` 时触发系统调用 |
| **短读操作** | `const n = try r.readSliceShort(&buf);` | 快路径走 L1 Cache `@memcpy`；慢路径以向量旁路直击内核 |
| **内核零拷贝流转** | `const n = try w.sendFileAll(&file_reader, limit);` | Linux `copy_file_range` / `sendfile`；不支持时自动降级双缓冲 |

---

## 5. 网络通信套接字 (`Io.net`)

源码位置：[`lib/std/Io/net.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/net.zig)

| 网络操作 | 典型代码 | 内核网络栈与全连接队列行为 |
| :--- | :--- | :--- |
| **启动服务监听** | `var s = try addr.listen(io, .{ .kernel_backlog = 128 });` | `bind(2)` + `listen(2)`，建立半连接与全连接双队列 |
| **异步接收连接** | `var stream = try s.accept(io);` | `IORING_OP_ACCEPT` / `accept4(O_NONBLOCK)`，空队列时切出 CPU |
| **对端连接握手** | `var stream = try addr.connect(io, .{});` | 非阻塞发起三次握手 SYN，挂起等待网络 ACK 完成 |
| **半关闭流** | `try stream.shutdown(io, .send);` | `shutdown(SHUT_WR)`，向对端发送 TCP FIN 报文触发优雅四次挥手 |
