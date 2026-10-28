# 从旧版 std.io 到现代 std.Io 迁移指南

在 Zig 0.17 标准库中，I/O 模块进行了重构。原有的泛型宏混入机制（`std.io`）被替换为基于统一虚表抽象的 **`std.Io`**。

本文档汇总了从旧版向新版迁移时的常见代码模式。

---

## 核心变迁对照表

| 场景 | 旧版范式 (0.16 及更早) | 现代新范式 (0.17+) | 说明与核心收益 |
| :--- | :--- | :--- | :--- |
| **标准库命名空间** | `@import("std").io` (小写) | `@import("std").Io` (大写) | 明确区分命名空间与统一接口类型 |
| **I/O 调用依赖** | 隐式依赖全局系统调用环境 | **显式接收 `io: std.Io`** | 类似 `allocator` 显式注入，实现确定性测试与解耦 |
| **Reader / Writer 抽象** | `std.io.Reader(Context, Error, readFn)` 泛型混入 | **`std.Io.Reader` 结构体** (带虚表与内部缓冲游标) | 消除泛型单态化代码膨胀，加快编译速度 |
| **缓冲读写实现** | 外置嵌套 `std.io.bufferedReader(underlying)` | **在构造时直接传入内存切片作为内部缓冲** | 原生内建缓冲管理，无需多层包装类型嵌套 |
| **零拷贝支持** | 缺乏统一抽象，需手工调用各 OS `sendfile` | **`Writer.VTable.sendFile` 虚表方法** | 跨平台统一支持内核级直接流转 |
| **文件打开与创建** | `std.fs.cwd().openFile(path, .{})` | `dir.openFile(io, path, .{})` | 接受 `io` 驱动，支持完成型底层拦截 |
| **标准错误/输出** | `std.io.getStdErr().writer()` | `io.lockStderr(.escape_codes)` | 内建互斥锁，支持防撕裂与终端色彩检测 |
| **并发任务派生** | 语言级关键字 `async`/`await` 或系统裸线程 | **`io.async` / `io.concurrent` / `Io.Group`** | 结构化有栈纤程并发，消除函数颜色传染 |

---

## 典型代码重构范例

### 1. 文件读取与缓冲消费

#### 旧版代码 (0.16 及更早)
```zig
const std = @import("std");

pub fn readLegacy(path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // 需手动嵌套一层 bufferedReader 获取缓冲能力
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        _ = line;
    }
}
```

#### 现代重构代码 (0.17+)
```zig
const std = @import("std");
const Io = std.Io;

pub fn readModern(io: Io, path: []const u8) !void {
    var cwd = Io.Dir.cwd();
    var file = try cwd.openFile(io, path, .{});
    defer file.close(io);

    // 在创建 reader 时直接将栈内存交由其内部管理缓冲
    var buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    const r = &file_reader.interface;

    var line_buf: [1024]u8 = undefined;
    _ = line_buf;
    _ = r;
}
```

---

### 2. 并发日志输出保护

#### 旧版代码
```zig
// 旧版直接获取全局句柄，多线程并发时输出可能交叉混叠
const stderr = std.io.getStdErr().writer();
try stderr.print("Log line: {d}\n", .{42});
```

#### 现代重构代码
```zig
// 现代机制获取带锁保护的标准错误流
var locked_stderr = try io.lockStderr(.escape_codes);
defer locked_stderr.unlock();

const w = locked_stderr.writer();
try w.print("Log line: {d}\n", .{42});
try w.flush();
```
