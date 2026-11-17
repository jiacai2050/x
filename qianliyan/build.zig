const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = if (builtin.os.tag == .macos) .{
            .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } },
        } else .{},
    });
    const optimize = b.standardOptimizeOption(.{});
    const stdgo_dep = b.dependency("stdgo", .{
        .target = target,
        .optimize = optimize,
        .sqlite = true,
    });
    const stdgo_mod = stdgo_dep.module("stdgo");

    const mod = b.addModule("qianliyan", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "stdgo", .module = stdgo_mod },
        },
        .sanitize_c = .off,
    });

    // Static library for Swift / macOS Host GUI integration
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "qianliyan",
        .root_module = mod,
    });
    lib.bundle_compiler_rt = true;
    lib.installHeader(b.path("include/dbcore.h"), "dbcore.h");
    b.installArtifact(lib);

    // Unit tests for core library (src/root.zig)
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_mod_tests.step);

    // WebAssembly target for Qianliyan Web client
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });
    const wasm_stdgo_dep = b.dependency("stdgo", .{
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .sqlite = true,
    });
    const wasm_stdgo_mod = wasm_stdgo_dep.module("stdgo");

    const wasm_mod = b.addModule("qianliyan_wasm", .{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = .small,
        .imports = &.{
            .{ .name = "stdgo", .module = wasm_stdgo_mod },
        },
        .sanitize_c = .off,
    });

    const wasm_exe = b.addExecutable(.{
        .name = "qianliyan",
        .root_module = wasm_mod,
    });
    wasm_exe.rdynamic = true;

    const install_wasm = b.addInstallArtifact(wasm_exe, .{
        .dest_dir = .{ .override = .{ .custom = "web" } },
    });
    const wasm_step = b.step("wasm", "Build WebAssembly module for Web");
    wasm_step.dependOn(&install_wasm.step);
}
