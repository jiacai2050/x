# 实战一：高性能 CLI 文本统计工具（wc 与 grep）

在命令行工具开发中，行数、单词数与字节数的统计（类似 Unix `wc` 工具）属于典型的数据流处理场景。

本章利用 `std.Io.File` 与带缓冲的 `Reader`，构建一个内存占用固定且支持流式处理的文本分析模块。

---

## 核心实现：流式逐块消费

为了防止读取超大文件时占用过多内存，代码采用固定容量的读缓冲区：

```zig
const std = @import("std");
const Io = std.Io;

pub const TextStats = struct {
    lines: usize = 0,
    words: usize = 0,
    bytes: usize = 0,
};

pub fn countStream(r: *Io.Reader) !TextStats {
    var stats = TextStats{};
    var in_word = false;

    // 栈上分配 16KB 的固定块缓冲区
    var chunk: [16 * 1024]u8 = undefined;

    while (true) {
        // 使用 readSliceShort 进行切片短读
        const n = try r.readSliceShort(&chunk);
        if (n == 0) break; // 到达流末尾 EOF

        stats.bytes += n;

        for (chunk[0..n]) |byte| {
            if (byte == '\n') {
                stats.lines += 1;
            }

            const is_space = switch (byte) {
                ' ', '\t', '\n', '\r' => true,
                else => false,
            };

            if (is_space) {
                in_word = false;
            } else if (!in_word) {
                in_word = true;
                stats.words += 1;
            }
        }
    }

    return stats;
}
```

---

## 跨语言对比与实现权衡

- **Go 方案**：
  通常使用 `bufio.NewScanner(file)` 或 `bufio.NewReader(file)`。`Scanner` 默认按行切分，单行超长时需显式调整缓冲区上限；同时 `bufio` 内部通常会在堆上分配一个切片，接口调用也会产生轻微的逃逸分析开销。
- **Rust 方案**：
  通常使用 `std::io::BufReader::new(file)` 配合 `bytes()` 迭代器或手工维护 `read(&mut chunk)`。Rust 的编译期内联能够优化掉绝大多数虚表开销，但泛型结构会增加编译单态化成本。
- **Zig 方案**：
  直接在当前函数栈上开辟 16KB 数组 `var chunk: [16 * 1024]u8 = undefined;`，零堆内存分配。通过 `*Io.Reader` 虚表驱动，接口保持统一。

---

## 单元测试验证

使用内存数据构造虚拟流进行测试：

```zig
test "统计简单文本的指标" {
    const sample = "Zig is a modern systems programming language.\nSimple, fast and safe.\n";

    var stream: Io.Reader = .fixed(sample);
    const stats = try countStream(&stream);

    try std.testing.expectEqual(@as(usize, 2), stats.lines);
    try std.testing.expectEqual(@as(usize, 10), stats.words);
    try std.testing.expectEqual(sample.len, stats.bytes);
}
```
