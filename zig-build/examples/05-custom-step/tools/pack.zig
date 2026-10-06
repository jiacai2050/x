const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var it = init.minimal.args.iterate();
    _ = it.next(); // Skip executable argv[0]
    const input_path = it.next() orelse return error.MissingInputPath;
    const output_path = it.next() orelse return error.MissingOutputPath;

    std.debug.print("Packaging release archive: {s} -> {s}\n", .{ input_path, output_path });

    // 1. 创建目标输出 tar.gz 文件
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(output_path)) |dir| {
        cwd.createDirPath(io, dir) catch {};
    }
    const tar_file = try cwd.createFile(io, output_path, .{});
    defer tar_file.close(io);

    // 2. 构造流式文件写入器
    var write_buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.Writer.initStreaming(tar_file, io, &write_buffer);

    // 3. 构造 gzip 压缩器
    var compress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var compressor = try std.compress.flate.Compress.init(
        &file_writer.interface,
        &compress_buffer,
        .gzip,
        std.compress.flate.Compress.Options.default,
    );

    // 4. 构造基于压缩流的 tar 打包器
    var tar_writer: std.tar.Writer = .{ .underlying_writer = &compressor.writer };

    // 5. 打开待打包的输入二进制文件并写入 tar
    const bin_file = try cwd.openFile(io, input_path, .{});
    defer bin_file.close(io);

    var read_buffer: [4096]u8 = undefined;
    var bin_reader = std.Io.File.Reader.init(bin_file, io, &read_buffer);

    const bin_name = std.fs.path.basename(input_path);
    const tar_entry_path = try std.fmt.allocPrint(allocator, "bin/{s}", .{bin_name});
    const bin_size = try bin_reader.getSize();

    // Explicitly record executable permission mode (0o755: rwxr-xr-x)
    try tar_writer.writeFileStream(
        tar_entry_path,
        bin_size,
        &bin_reader.interface,
        .{ .mode = 0o755 },
    );
    try tar_writer.finishPedantically();

    // 6. 结束压缩并刷新缓冲区
    try compressor.finish();
    try file_writer.flush();

    std.debug.print("Successfully created {s}!\n", .{output_path});
}
