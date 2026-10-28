# 文件系统与目录操作：Dir 与 File API

在操作系统编程中，直接操作绝对路径不仅效率低下，而且极易遭受目录遍历攻击与竞态条件漏洞（TOCTOU: Time-Of-Check to Time-Of-Use）。

Zig 的文件系统 API 始终坚持**以目录句柄为锚点（Handle-based & Capability-based）**的设计理念：所有文件与子目录的创建、查找与删除，均围绕 `Io.Dir` 与 `Io.File` 展开。

---

## 目录操作核心：`Io.Dir`

在源码 [`lib/std/Io/Dir.zig#L13`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Dir.zig#L13) 中，`Dir` 封装了指向某个目录的文件描述符句柄，并提供了一组严格接受 `io: Io` 参数的方法。

### 1. 目录打开与创建

```zig
const std = @import("std");
const Io = std.Io;

pub fn exploreDirectories(io: Io) !void {
    // 获取当前工作目录（CWD）
    var cwd = Io.Dir.cwd();

    // 在当前目录下创建新文件夹
    try cwd.createDir(io, "output_dir", .default_dir);

    // 打开子目录
    var sub_dir = try cwd.openDir(io, "output_dir", .{
        .iterate = true, // 允许后续遍历该目录
    });
    defer sub_dir.close(io);

    // 递归创建多级目录
    _ = try cwd.createDirPath(io, "nested/logs/daily", .default_dir);
}
```

### 2. 遍历目录条目

```zig
pub fn listDirectory(io: Io, dir: Io.Dir) !void {
    var iter = dir.iterate(io);
    while (try iter.next(io)) |entry| {
        // entry.name: []const u8
        // entry.kind: File.Kind (.file, .directory, .sym_link 等)
        std.debug.print("Found {s}: {s}\n", .{ @tagName(entry.kind), entry.name });
    }
}
```

---

## 文件操作核心：`Io.File`

在源码 [`lib/std/Io/File.zig#L11`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/File.zig#L11) 中，`File` 抽象代表一个已打开的文件句柄。

### 1. 文件的创建与打开

```zig
// 创建新文件（若已存在则默认截断覆盖）
var file = try dir.createFile(io, "data.bin", .{
    .read = true, // 允许后续读取
    .truncate = true,
});
defer file.close(io);

// 以只读模式打开已有文件
var read_file = try dir.openFile(io, "data.bin", .{
    .mode = .read_only,
});
defer read_file.close(io);
```

### 2. 基础读写与基于偏移量的定位操作

`File` 提供了两种不同心智模型的读写接口：
- **流式递增操作**：利用文件内部维护的游标偏移；
- **位置无关操作（Positional I/O）**：显式传入 `offset`，天然具备线程安全与并发能力（对应底层的 `pread`/`pwrite` 或 Windows `ReadFile`/`WriteFile` 传结构体），互不干扰文件指针。

```zig
pub fn fileOperations(io: Io, file: Io.File) !void {
    const payload = "Deterministic data block";

    // 1. 指定文件偏移量的确定性写入 (Positional Write)
    const bytes_written = try file.writePositional(io, "", &.{payload}, 0, 1024);
    _ = bytes_written;

    // 2. 查询文件当前大小
    const size = try file.length(io);
    _ = size;

    // 3. 将内核脏页强制刷入物理存储
    try file.sync(io);
}
```

### 3. 排他锁与共享锁（File Locking）

为了防止跨进程或跨协程的数据写入撕裂，`Io.File` 原生支持系统级文件锁：

```zig
// 获取共享锁（读锁）
try file.lock(io, .shared);

// 获取独占排他锁（写锁）
try file.lock(io, .exclusive);

// 解锁
file.unlock(io);
```

### 4. 内存映射文件（Memory Mapped File）

对于极高频的只读或随机大文件访问，`File.MemoryMap` 提供了零拷贝的虚拟内存映射机制：

```zig
// 将文件整个映射入用户进程虚拟地址空间
var mmap = try file.memoryMap(io, .{
    .protection = .read_only,
});
defer mmap.destroy(io);

// 直接以切片形式零拷贝访问文件内容
const slice: []const u8 = mmap.slice;
std.debug.print("First byte: {x}\n", .{slice[0]});
```
