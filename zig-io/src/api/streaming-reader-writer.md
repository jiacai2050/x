# 高效数据流操作：缓冲读写、格式化与零拷贝 sendFile

在构建高性能文本处理、网络协议编解码以及静态资源分发系统时，直接使用裸文件读写会频繁引发小包系统调用。

Zig 通过将 `Io.File`、内存切片与套接字无缝衔接至 `Reader` 与 `Writer`，提供了极富弹性的缓冲策略与内核级零拷贝能力。

---

## 构造流式读写器

任何打开的 `Io.File` 均可通过调用其成员方法转换为 `File.Reader` 或 `File.Writer`（详见 [`File.zig#L400`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/File.zig)），其区别仅在于**传入缓冲区的生命周期与大小**：

```zig
const std = @import("std");
const Io = std.Io;

pub fn setupStreams(io: Io, file: Io.File) !void {
    // 1. 在栈上开辟 8KB 的临时读缓冲区
    var read_buf: [8 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const r = &file_reader.interface;

    // 2. 在栈上开辟 4KB 的写缓冲区
    var write_buf: [4 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const w = &file_writer.interface;

    // 3. 构造非缓冲直接写入器（传入空切片 &.{}`）
    var unbuffered_writer = file.writer(io, &.{});
    _ = unbuffered_writer;
}
```

---

## 格式化输出与精细化写入

`Writer` 封装了丰富的格式化与批量写入 API：

```zig
pub fn writeDemo(w: *Io.Writer) !void {
    // 1. 写入单字节
    try w.writeByte(0xAA);

    // 2. 保证全部写入的切片追加
    try w.writeAll("Processing metrics report:\n");

    // 3. 高性能格式化输出
    try w.print("Timestamp: {d}, Status: {s}\n", .{ 1729000000, "OK" });

    // 4. 重复写入指定字节（常用于数据对齐填充）
    try w.splatByteNTimes(' ', 8);

    // 5. 关键动作：冲刷缓冲区，将暂存数据推入底层 sink
    try w.flush();
}
```

---

## 高级数据消费与流式读取

`Reader` 提供了细致的消费控制，避免不必要的堆分配：

```zig
pub fn readDemo(allocator: std.mem.Allocator, r: *Io.Reader) !void {
    // 1. 尝试短读定长数据（返回实际读到的字节数）
    var header: [16]u8 = undefined;
    const n = try r.readSliceShort(&header);
    _ = n;

    // 2. 丢弃不需要的填充字节（无需读取到内存中，由内部快速跳过游标）
    _ = try r.discard(.limited(4));

    // 3. 限制最大分配上限的安全读取剩余内容
    const payload = try r.allocRemaining(allocator, .limited(1024 * 1024));
    defer allocator.free(payload);
}
```

---

## 内核级零拷贝：`sendFile` 实战

在实现文件下载、静态代理或跨设备流转时，传统用户态的数据流转往往需要经历两次无效的内存拷贝（内核态 -> 用户态 -> 内核态）：

```text
[ 传统拷贝路径 ]
Disk -> 内核 PageCache -> 用户态 Buffer -> Socket 内核缓冲 -> 网卡 (4 次上下文切换，2 次 CPU 拷贝)

[ sendFile 零拷贝路径 ]
Disk -> 内核 PageCache --------------------> Socket 描述符 -> 网卡 (2 次上下文切换，0 次 CPU 拷贝)
```

在 Zig 的 `Io.Writer` 体系中，`sendFile` 属于一等公民虚表方法（详见源码 [`lib/std/Io/Writer.zig#L63`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Writer.zig#L63)）：

```zig
pub fn streamFileToSink(w: *Io.Writer, source_file: *Io.File.Reader, max_bytes: u64) !usize {
    // 直接调用 Writer 的 sendFile 接口
    // 底层会优先尝试 Linux sys_sendfile、macOS fcopyfile 等原生系统调用；
    // 若底层后端不支持，则自动降级为利用内部 buffer 循环搬运
    return try w.sendFile(source_file, .limited(max_bytes));
}
```

这使得编写高性能 Web 静态文件服务器、反向代理与日志转储工具时，能够天然压榨出极致的硬件极限。
