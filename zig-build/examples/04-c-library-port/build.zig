const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. 生成配置头文件（ConfigHeader）
    const config_h = b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("upstream/include/config.h.in") },
            .include_path = "config.h",
        },
        .{
            .MYCLIB_VERSION = "2.4.0",
            .HAVE_FAST_MATH = true,
        },
    );

    // 2. 创建静态 C 库模块
    const c_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    c_mod.addConfigHeader(config_h);
    c_mod.addIncludePath(b.path("upstream/include"));
    c_mod.addCSourceFile(.{
        .file = b.path("upstream/src/common.c"),
        .flags = &.{"-Wall"},
    });

    // 3. 构建静态库产物并导出头文件
    const lib = b.addLibrary(.{
        .name = "myclib",
        .linkage = .static,
        .root_module = c_mod,
    });
    lib.installHeadersDirectory(b.path("upstream/include"), "", .{});
    lib.installConfigHeader(config_h);
    b.installArtifact(lib);

    // 4. 测试步骤：在 test/ 子目录运行集成测试
    const test_step = b.step("test", "Run integration tests");
    const test_runner = b.addSystemCommand(&.{ "zig", "build", "run" });
    test_runner.setCwd(b.path("test"));
    test_step.dependOn(&test_runner.step);
}
