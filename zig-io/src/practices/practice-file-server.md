# 实战二：零拷贝流式处理与文件传输

在构建文件服务器、备份工具或数据传输服务时，数据在用户态与内核态之间的多次无谓拷贝是影响传输吞吐的主要瓶颈。

本章利用 `std.Io` 的 `sendFile` 虚表方法，构建零中间拷贝的文件流转管道。

---

## 零拷贝管道设计

```mermaid
graph LR
    SourceFile["源文件 (File)"] -->|"file.reader(io)"| FileReader["Io.File.Reader"]
    FileReader -->|"w.sendFile(file_reader)"| SinkWriter["目标输出流 (Io.Writer)"]
    SinkWriter -->|"内核直接转储 (sendfile / copyfile)"| Dest["目标文件 / 网络套接字"]
```

---

## 核心实现代码

```zig
const std = @import("std");
const Io = std.Io;

pub fn copyFileZeroCopy(io: Io, src_file: Io.File, dst_file: Io.File) !u64 {
    // 1. 获取源文件大小
    const total_size = try src_file.length(io);

    // 2. 构造源端 Reader
    var read_buffer: [4096]u8 = undefined;
    var file_reader = src_file.reader(io, &read_buffer);

    // 3. 构造目标端 Writer（传入空切片作为非缓冲直接刷写模式）
    var file_writer = dst_file.writer(io, &.{});
    const w = &file_writer.interface;

    // 4. 执行零拷贝管道传输
    var bytes_copied: u64 = 0;
    while (bytes_copied < total_size) {
        const remaining = total_size - bytes_copied;
        const n = try w.sendFile(&file_reader, .limited(remaining));
        if (n == 0) break;
        bytes_copied += n;
    }

    try w.flush();
    return bytes_copied;
}
```

---

## 跨语言对比与实现权衡

- **Go 方案**：
  Go 提供了标准库函数 `io.Copy(dst, src)`。在底层实现中，Go 通过运行时类型断言探测 `src` 是否实现了 `io.WriterTo` 或 `dst` 是否实现了 `io.ReaderFrom`。如果两端均为特定类型的 TCP 连接或操作系统文件，Go 会尝试调用 Linux `splice` 或 `sendfile` 系统调用；若断言失败，则在堆上分配一个 32KB 的临时切片进行常规搬运。这种探测方式依赖运行时接口断言。
- **Rust 方案**：
  在 Rust 标准库中，`std::io::copy` 同样尝试探测特化实现；而在异步运行时（Tokio）中，由于异步 Trait 的复杂性，直接跨文件和网络进行 `sendfile` 通常需要借助专门的平台扩展 crate（如 `tokio-splice`），抽象较为分散。
- **Zig 方案**：
  将 `sendFile` 作为 `Writer.VTable` 的核心虚表方法显式暴露。底层后端（如 `Io.Uring`、`Io.Threaded`）按操作系统原生系统调用（Linux `copy_file_range` / `sendfile`、macOS `fcopyfile`）实现；若底层环境不支持，则自动降级为内部缓冲搬运，外部调用代码无需调整。

---

## 单元测试与完整性断言

```zig
test "零拷贝流式文件复制" {
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const src_name = "source.txt";
    const dst_name = "target.txt";
    const content = "Zero-copy streaming pipeline verification.";

    {
        var src = try tmp.dir.createFile(io, src_name, .{});
        defer src.close(io);
        var fw = src.writer(io, &.{});
        try fw.interface.writeAll(content);
        try fw.interface.flush();
    }

    {
        var src = try tmp.dir.openFile(io, src_name, .{});
        defer src.close(io);

        var dst = try tmp.dir.createFile(io, dst_name, .{});
        defer dst.close(io);

        const copied = try copyFileZeroCopy(io, src, dst);
        try std.testing.expectEqual(content.len, copied);
    }

    {
        var dst = try tmp.dir.openFile(io, dst_name, .{});
        defer dst.close(io);

        var read_buf: [128]u8 = undefined;
        var fr = dst.reader(io, &read_buf);
        const actual = try fr.interface.allocRemaining(std.testing.allocator, .limited(1024));
        defer std.testing.allocator.free(actual);

        try std.testing.expectEqualStrings(content, actual);
    }
}
```
