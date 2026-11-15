const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
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
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
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
