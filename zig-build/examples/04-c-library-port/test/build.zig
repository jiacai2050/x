const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const myclib_dep = b.dependency("myclib", .{
        .target = target,
        .optimize = optimize,
    });
    const myclib_art = myclib_dep.artifact("myclib");

    const exe = b.addExecutable(.{
        .name = "test_myclib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.linkLibrary(myclib_art);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run test app");
    run_step.dependOn(&run_cmd.step);
}
