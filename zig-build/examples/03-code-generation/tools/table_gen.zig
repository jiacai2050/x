const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();

    _ = it.next(); // 跳过 argv[0]
    const out_path = it.next() orelse return error.MissingOutputPath;

    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(out_path)) |dir| {
        cwd.createDirPath(io, dir) catch {};
    }

    const file = try cwd.createFile(io, out_path, .{});
    defer file.close(io);

    var write_buffer: [1024]u8 = undefined;
    var file_writer = std.Io.File.Writer.initStreaming(file, io, &write_buffer);

    try file_writer.interface.writeAll(
        \\pub const multiplier: u32 = 10;
        \\pub const base_offset: u32 = 42;
        \\
    );
    try file_writer.flush();
}
