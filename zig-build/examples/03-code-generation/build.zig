const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. 生成配置头文件（ConfigHeader）
    const config_h = b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("include/config.h.in") },
            .include_path = "config.h",
        },
        .{
            .HAVE_FEATURE_A = true,
            .HAVE_FEATURE_B = false,
            .APP_NAME = "CodegenDemo",
            .APP_PORT = @as(i64, 8080),
        },
    );

    // 2. 动态生成源码文件（WriteFiles）
    const write_files = b.addWriteFiles();
    const version_zig = write_files.add("version.zig", b.fmt(
        \\pub const app_name = "CodegenDemo";
        \\pub const version = "1.0.0-rc.1";
        \\pub const build_mode = "{s}";
        ,
        .{@tagName(optimize)},
    ));

    const version_mod = b.createModule(.{
        .root_source_file = version_zig,
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "codegen_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "version", .module = version_mod },
            },
        }),
    });
    exe.root_module.addConfigHeader(config_h);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
