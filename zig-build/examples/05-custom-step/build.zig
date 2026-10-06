const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. 构建主应用程序
    const exe = b.addExecutable(.{
        .name = "custom_step_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // 2. 编译专用于宿主机的打包辅助工具（必须为 b.graph.host）
    const pack_tool = b.addExecutable(.{
        .name = "pack_tool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/pack.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    // 3. 配置运行步骤与数据流依赖
    const pack_cmd = b.addRunArtifact(pack_tool);
    // 传入主程序二进制 LazyPath 作为命令行输入
    pack_cmd.addFileArg(exe.getEmittedBin());
    // 声明工具生成的 tar.gz 输出文件（返回 LazyPath）
    const output_tar = pack_cmd.addOutputFileArg2("bundle.tar.gz", .{});

    // 将打包好的归档安装到交付目录（zig-out/bundle.tar.gz）
    const install_tar = b.addInstallFile(output_tar, "bundle.tar.gz");

    // 4. 注册顶层命令："zig build pack"
    const top_pack = b.step("pack", "Package distribution archive into tar.gz using helper tool");
    top_pack.dependOn(&install_tar.step);

    // 5. 支持 "zig build run"
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run demo app");
    run_step.dependOn(&run_cmd.step);
}
