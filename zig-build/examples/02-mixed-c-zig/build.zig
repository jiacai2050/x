const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. 将 C 头文件转译为 Zig 模块
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("c_include/native_math.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(b.path("c_include"));
    const math_c_module = translate_c.createModule();

    // 2. 创建挂载了 C 源码与头文件的 Zig 主程序模块
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

    // 3. 构建并安装可执行文件
    const exe = b.addExecutable(.{
        .name = "mixed_app",
        .root_module = exe_module,
    });
    b.installArtifact(exe);

    // 4. 注册运行命令
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
