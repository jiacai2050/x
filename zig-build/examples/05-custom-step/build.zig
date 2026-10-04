const std = @import("std");

pub const PackReleaseStep = struct {
    step: std.Build.Step,
    binary_path: std.Build.LazyPath,
    output_path: []const u8,

    pub fn create(b: *std.Build, binary_path: std.Build.LazyPath, output_path: []const u8) *PackReleaseStep {
        const self = b.allocator.create(PackReleaseStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "pack-release",
                .owner = b,
                .makeFn = make,
            }),
            .binary_path = binary_path,
            .output_path = output_path,
        };
        binary_path.addStepDependencies(&self.step);
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = options;
        const self: *PackReleaseStep = @fieldParentPtr("step", step);
        const b = step.owner;
        const io = b.graph.io;

        std.debug.print("Packaging release archive to {s} using std.tar + gzip...\n", .{self.output_path});

        // 1. Create the destination .tar.gz file
        const cwd = std.Io.Dir.cwd();
        if (std.fs.path.dirname(self.output_path)) |dir| {
            cwd.createDirPath(io, dir) catch {};
        }
        const tar_file = try cwd.createFile(io, self.output_path, .{});
        defer tar_file.close(io);

        // 2. Underlying file writer
        var write_buffer: [4096]u8 = undefined;
        var file_writer = std.Io.File.Writer.initStreaming(tar_file, io, &write_buffer);

        // 3. Setup gzip compressor stream around the file writer
        var compress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
        var compressor = try std.compress.flate.Compress.init(
            &file_writer.interface,
            &compress_buffer,
            .gzip,
            std.compress.flate.Compress.Options.default,
        );

        // 4. Setup tar writer writing into the gzip compressor
        var tar_writer: std.tar.Writer = .{ .underlying_writer = &compressor.writer };

        // 5. Read the compiled executable and add it into the tar stream
        const bin_path = self.binary_path.getPath2(b, &self.step);
        const bin_file = try cwd.openFile(io, bin_path, .{});
        defer bin_file.close(io);

        var read_buffer: [4096]u8 = undefined;
        var bin_reader = std.Io.File.Reader.init(bin_file, io, &read_buffer);

        // Derive executable filename (e.g. "custom_step_demo" or "custom_step_demo.exe")
        const bin_name = std.fs.path.basename(bin_path);
        const tar_entry_path = try std.fmt.allocPrint(b.allocator, "bin/{s}", .{bin_name});
        defer b.allocator.free(tar_entry_path);

        // Stream file into tar archive
        try tar_writer.writeFile(tar_entry_path, &bin_reader, 0);
        try tar_writer.finishPedantically();

        // 6. Finish compression and flush buffered data to disk
        try compressor.finish();
        try file_writer.flush();

        std.debug.print("Successfully created {s} (pure Zig std.tar + gzip)!\n", .{self.output_path});
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Build main application
    const exe = b.addExecutable(.{
        .name = "custom_step_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // 2. Custom pack step: packaging into tar.gz using pure Zig std.tar + std.compress
    const pack_step = PackReleaseStep.create(
        b,
        exe.getEmittedBin(),
        b.getInstallPath(.prefix, "bundle.tar.gz"),
    );
    // Ensure all artifacts are installed and zig-out prefix exists before packaging
    pack_step.step.dependOn(b.getInstallStep());

    // 3. Register top-level command: "zig build pack"
    const top_pack = b.step("pack", "Package distribution archive into tar.gz using std.tar");
    top_pack.dependOn(&pack_step.step);

    // 4. "zig build run" support
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run demo app");
    run_step.dependOn(&run_cmd.step);
}
