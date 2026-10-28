const std = @import("std");
const Io = std.Io;
const streaming = @import("streaming");

pub fn main() !void {
    const raw_data = "First line of input.\nSecond line.\nThird line ending.\n";
    var reader: Io.Reader = .fixed(raw_data);

    const metrics = try streaming.countMetrics(&reader);

    std.debug.print("统计结果: 行数={d}, 单词数={d}, 总字节={d}\n", .{
        metrics.lines,
        metrics.words,
        metrics.bytes,
    });
}
