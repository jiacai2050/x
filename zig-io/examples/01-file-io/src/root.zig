const std = @import("std");
const Io = std.Io;

/// 将文本内容安全写入指定路径的文件
pub fn writeTextFile(io: Io, dir: Io.Dir, filename: []const u8, content: []const u8) !void {
    // 创建或截断已有文件
    var file = try dir.createFile(io, filename, .{ .truncate = true });
    defer file.close(io);

    // 构造带缓冲的写入器
    var buffer: [1024]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const w = &file_writer.interface;

    try w.writeAll(content);
    try w.flush();
}

/// 读取指定文件的全部文本内容
pub fn readTextFile(allocator: std.mem.Allocator, io: Io, dir: Io.Dir, filename: []const u8) ![]u8 {
    var file = try dir.openFile(io, filename, .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    const r = &file_reader.interface;

    return try r.allocRemaining(allocator, .limited(10 * 1024 * 1024));
}

test "文件写入与读取完整性验证" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_filename = "demo.txt";
    const expected_content = "Hello Zig 0.17 Modern std.Io Architecture!";

    try writeTextFile(io, tmp.dir, test_filename, expected_content);

    const actual_content = try readTextFile(allocator, io, tmp.dir, test_filename);
    defer allocator.free(actual_content);

    try std.testing.expectEqualStrings(expected_content, actual_content);
}
