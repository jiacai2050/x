const std = @import("std");
const Io = std.Io;

/// 文本指标统计结构体
pub const Metrics = struct {
    lines: usize = 0,
    words: usize = 0,
    bytes: usize = 0,
};

/// 流式逐块统计，防止大文件溢出内存
pub fn countMetrics(r: *Io.Reader) !Metrics {
    var metrics = Metrics{};
    var in_word = false;
    var chunk: [256]u8 = undefined;

    while (true) {
        // 使用 readSliceShort 进行切片短读
        const n = try r.readSliceShort(&chunk);
        if (n == 0) break;

        metrics.bytes += n;

        for (chunk[0..n]) |ch| {
            if (ch == '\n') {
                metrics.lines += 1;
            }

            const is_space = switch (ch) {
                ' ', '\t', '\n', '\r' => true,
                else => false,
            };

            if (is_space) {
                in_word = false;
            } else if (!in_word) {
                in_word = true;
                metrics.words += 1;
            }
        }
    }

    return metrics;
}

test "流式文本统计验证" {
    const text = "System programming with Zig.\nEfficient, fast, and concurrent.\n";
    var stream: Io.Reader = .fixed(text);

    const m = try countMetrics(&stream);
    try std.testing.expectEqual(@as(usize, 2), m.lines);
    try std.testing.expectEqual(@as(usize, 8), m.words);
    try std.testing.expectEqual(text.len, m.bytes);
}
