const std = @import("std");
const Io = std.Io;
const file_io = @import("file_io");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化通用的多线程调度后端
    var threaded = Io.Threaded.init(allocator, .{
        .stack_size = 64 * 1024,
    });
    defer threaded.deinit();

    const io = threaded.io();

    var cwd = Io.Dir.cwd();
    const sample_file = "zig_io_hello.txt";
    const sample_text = "Zig I/O and Concurrency Guide Example 01.\n";

    try file_io.writeTextFile(io, cwd, sample_file, sample_text);
    defer cwd.deleteFile(io, sample_file) catch {};

    const read_back = try file_io.readTextFile(allocator, io, cwd, sample_file);
    defer allocator.free(read_back);

    std.debug.print("成功读取文件内容: {s}", .{read_back});
}
