# 网络通信：TCP/UDP 套接字与高并发监听

网络通信是现代分布式系统与服务端的绝对核心。

在 Zig 中，`std.Io.net` 提供了一套强类型且跨平台的套接字封装，源码定义见 [`lib/std/Io/net.zig`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/net.zig)。

---

## 地址建模：`IpAddress`

[`net.IpAddress`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/net.zig#L57) 采用类型安全的带标签联合体（Tagged Union），支持 IPv4 与 IPv6 的统一解析与格式化：

```zig
const std = @import("std");
const Io = std.Io;
const net = Io.net;

pub fn addressDemo() !void {
    // 1. 解析 IPv4 地址与端口
    const addr_v4 = try net.IpAddress.parse("127.0.0.1", 8080);

    // 2. 解析 IPv6 地址
    const addr_v6 = try net.IpAddress.parse("::1", 9090);

    // 3. 构建全零监听地址
    const bind_all = net.IpAddress.initIpv4(.{ 0, 0, 0, 0 }, 3000);
    _ = addr_v4;
    _ = addr_v6;
    _ = bind_all;
}
```

---

## 构建 TCP 服务器：`Server` 与 `accept`

通过 `address.listen` 可以直接构建一个监听服务端 [`net.Server`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/net.zig#L1551)：

```zig
pub fn runTcpServer(io: Io) !void {
    const bind_addr = try net.IpAddress.parse("127.0.0.1", 9000);

    // 1. 在指定地址上开始监听
    var server = try bind_addr.listen(io, .{
        .kernel_backlog = 128,
        .reuse_address = true,
    });
    defer server.deinit(io);

    std.debug.print("Server listening on 127.0.0.1:9000...\n", .{});

    // 2. 循环接收客户端连接
    while (true) {
        var stream = try server.accept(io);
        // stream 类型为 net.Stream

        // 将连接交由独立的异步任务或纤程处理
        try handleClient(io, stream);
    }
}
```

---

## 客户端连接与双向数据流：`Stream`

[`net.Stream`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/net.zig#L1267) 代表一条已建立的可靠双向流（TCP 或 UNIX Domain Socket）。它能够转换为标准的 `Reader` 与 `Writer`：

```zig
fn handleClient(io: Io, stream: net.Stream) !void {
    defer stream.close(io);

    // 构造栈上读写缓冲区
    var rx_buf: [1024]u8 = undefined;
    var tx_buf: [1024]u8 = undefined;

    var stream_reader = stream.reader(io, &rx_buf);
    var stream_writer = stream.writer(io, &tx_buf);

    const r = &stream_reader.interface;
    const w = &stream_writer.interface;

    // 简单 Echo 回显循环
    while (true) {
        var temp: [256]u8 = undefined;
        const n = r.read(&.{&temp}) catch |err| switch (err) {
            error.EndOfStream => break, // 对端正常关闭
            else => return err,
        };
        if (n == 0) break;

        // 回写数据
        try w.writeAll(temp[0..n]);
        try w.flush();
    }
}
```

---

## 高并发服务心智模型

在现代 `std.Io` 中，`server.accept(io)` 与 `stream.read(io, ...)` 在底层有栈纤程驱动下**看似是阻塞的同步代码，实则是纯非阻塞执行**：
- 当没有任何客户端发起握手时，当前纤程挂起，底层事件环（`io_uring` 或 `kqueue`）脱身去处理其他已有连接的数据包；
- 当客户端连接到达时，操作系统内核产生完成事件，调度器自动唤醒对应纤程并从 `accept` 处继续推进。

开发者不仅拥有类似 Go 语言般的同步心智负担，同时由于没有庞大的垃圾回收（GC）开销与动态栈搬迁惩罚，能够达成极为平稳的 P99 延迟表现。
