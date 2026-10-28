# 子进程、管道与终端交互：Process 与 Terminal

在开发自动化运维系统、编译器前端、CLI 构建工具或测试脚手架时，控制子进程的生命周期、重定向管道流以及精细化操作终端输出是必不可少的系统级能力。

Zig 的 `std.Io` 将子进程派生、跨进程管道（Pipe）与标准错误终端锁定统纳管入标准接口体系中。

---

## 子进程派生与生命周期管理

通过 `std.process.Child` 与 `Io` 协同，可以安全且跨平台地启动外部进程：

```zig
const std = @import("std");
const Io = std.Io;

pub fn spawnChildProcess(allocator: std.mem.Allocator, io: Io) !void {
    // 构造进程参数
    const argv = [_][]const u8{ "git", "status", "--porcelain" };

    // 配置启动选项并派生子进程
    var child = try std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe; // 捕获标准输出
    child.stderr_behavior = .Inherit;

    // 启动进程
    try child.spawn(io);

    // 从子进程管道流中读取输出
    if (child.stdout) |stdout_file| {
        var buf: [1024]u8 = undefined;
        var r = stdout_file.reader(io, &buf);
        const output = try r.interface.allocRemaining(allocator, .limited(1024 * 1024));
        defer allocator.free(output);
        std.debug.print("Git status output:\n{s}\n", .{output});
    }

    // 等待子进程退出并获取最终状态
    const term = try child.wait(io);
    switch (term) {
        .Exited => |code| std.debug.print("Process exited with code {d}\n", .{code}),
        .Signal => |sig| std.debug.print("Process killed by signal {d}\n", .{sig}),
        .Stopped => |sig| std.debug.print("Process stopped by signal {d}\n", .{sig}),
        .Unknown => |code| std.debug.print("Unknown status {d}\n", .{code}),
    }
}
```

---

## 跨进程匿名管道：Pipe

在需要父子进程或同级进程之间进行单向字节流交互时，使用系统管道：

```zig
pub fn pipeDemo(io: Io) !void {
    // 详见 Threaded.zig#L18884
    const fds = try Io.Threaded.pipe2(.{});
    defer {
        Io.Threaded.closeFd(fds[0]);
        Io.Threaded.closeFd(fds[1]);
    }
}
```

---

## 终端与控制台输出：`Terminal` 与 `lockStderr`

在并发日志打印时，若多个并发任务同时向 `stderr` 写入字符，容易导致终端输出交叉乱序。

`std.Io` 内建了 [`lockStderr`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig#L209) 保护机制：

```zig
pub fn safeLogging(io: Io, message: []const u8) !void {
    // 1. 获取全局 stderr 互斥锁，并侦测终端是否支持 ANSI 彩色转义码
    var locked_stderr = try io.lockStderr(.escape_codes);
    defer locked_stderr.unlock();

    // 2. 线程安全地向终端写入带格式的日志
    const w = locked_stderr.writer();
    try w.print("\x1b[32m[SUCCESS]\x1b[0m {s}\n", .{message});
    try w.flush();
}
```

- **原子互斥保证**：在 `locked_stderr` 持有期间，其他线程和纤程的打印调用会安全排队；
- **智能转义码降级**：若检测到标准错误被重定向至文件或非 TTY 管道，会自动禁用彩色字符，避免日志文件中充斥混乱的 ANSI 转义乱码。
