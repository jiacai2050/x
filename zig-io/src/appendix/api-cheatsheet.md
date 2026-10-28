# Zig I/O API 核心速查表

本文档汇集 Zig `std.Io` 标准库的核心 API 签名与官方源码不可变 Tag 锚点。

---

## 1. 统一接口与调度基石 (`std.Io`)

源码位置：[`lib/std/Io.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig)

| 操作分类 | 常用 API 签名 | 说明与功能 |
| :--- | :--- | :--- |
| **异步派生** | `io.async(function, args)` | 在事件环上派生非阻塞纤程任务，返回 `Future` |
| **并行派生** | `io.concurrent(function, args)` | 派发至工作线程池多核并行执行，返回 `ConcurrentError!Future` |
| **等待结果** | `future.await(io)` | 阻塞/挂起当前上下文，直到目标任务执行完毕返回结果 |
| **任务取消** | `future.cancel(io)` | 触发对目标任务的中断与取消清理 |
| **时间休眠** | `io.sleep(timeout)` | 协作型非阻塞睡眠等待，让出当前纤程 |
| **安全随机** | `io.random(buffer)` / `io.randomSecure(buffer)` | 填充高熵随机字节 |

---

## 2. 结构化任务组 (`Io.Group`)

源码位置：[`lib/std/Io.zig#L1338`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig#L1338)

| 方法签名 | 说明 |
| :--- | :--- |
| `var group: Io.Group = .init` | 静态初始化任务组容器 |
| `group.async(io, func, args)` | 向组内追加协作异步任务 |
| `group.concurrent(io, func, args)` | 向组内追加多核并行任务 |
| `group.await(io)` | 阻塞等待组内全部子任务收敛执行完毕 |
| `group.cancel(io)` | 向组内所有子任务广播中断信号 |

---

## 3. 文件系统与目录 (`Io.Dir` & `Io.File`)

源码位置：[`lib/std/Io/Dir.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Dir.zig) 与 [`lib/std/Io/File.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/File.zig)

| 场景 | 方法调用 |
| :--- | :--- |
| **获取当前目录** | `var cwd = Io.Dir.cwd()` |
| **创建/打开文件** | `var f = try dir.createFile(io, "file.txt", .{})`<br>`var f = try dir.openFile(io, "file.txt", .{})` |
| **定位读写** | `file.readPositional(io, slices, offset)`<br>`file.writePositional(io, header, data, splat, offset)` |
| **查询文件长度** | `try file.length(io)` |
| **持久化刷盘** | `try file.sync(io)` |
| **文件锁控制** | `try file.lock(io, .shared)` / `try file.lock(io, .exclusive)` / `file.unlock(io)` |
| **虚拟内存映射** | `var mmap = try file.memoryMap(io, .{ .protection = .read_only })` |

---

## 4. 流式传输与零拷贝 (`Io.Reader` & `Io.Writer`)

源码位置：[`lib/std/Io/Reader.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Reader.zig) 与 [`lib/std/Io/Writer.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Writer.zig)

| 操作模式 | 典型代码 |
| :--- | :--- |
| **构建带缓冲 Reader** | `var r_inst = file.reader(io, &buffer); const r = &r_inst.interface;` |
| **构建带缓冲 Writer** | `var w_inst = file.writer(io, &buffer); const w = &w_inst.interface;` |
| **格式化写入** | `try w.print("Value: {d}\n", .{val});` |
| **缓冲区刷盘** | `try w.flush();` |
| **读取全部剩余数据** | `const data = try r.allocRemaining(allocator, .limited(max_len));` |
| **短读操作** | `const n = try r.readSliceShort(&buffer);` |
| **内核零拷贝搬运** | `const n = try w.sendFile(&file_reader, .limited(bytes));` |

---

## 5. 网络套接字通信 (`Io.net`)

源码位置：[`lib/std/Io/net.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/net.zig)

| 网络操作 | 典型代码 |
| :--- | :--- |
| **IP 地址解析** | `const addr = try net.IpAddress.parse("0.0.0.0", 8080);` |
| **启动服务监听** | `var server = try addr.listen(io, .{ .reuse_address = true }); defer server.deinit(io);` |
| **接受客户端连接** | `var stream = try server.accept(io); defer stream.close(io);` |
| **建立对端连接** | `var stream = try addr.connect(io, .{});` |
| **连接转流读写** | `var r = stream.reader(io, &rx_buf); var w = stream.writer(io, &tx_buf);` |
