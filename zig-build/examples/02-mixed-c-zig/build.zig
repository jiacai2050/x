const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Translate C header file into a Zig Module
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("c_include/native_math.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(b.path("c_include"));
    const math_c_module = translate_c.createModule();

    // 2. Create main Zig executable module with C source attached
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "native_math", .module = math_c_module },
        },
    });

    exe_module.addCSourceFile(.{
        .file = b.path("c_src/native_math.c"),
        .flags = &.{"-Wall", "-Wextra"},
    });
    exe_module.addIncludePath(b.path("c_include"));

    // 3. Build and install executable
    const exe = b.addExecutable(.{
        .name = "mixed_app",
        .root_module = exe_module,
    });
    b.installArtifact(exe);

    // 4. Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
