const std = @import("std");
const simargs = @import("simargs");

const MAX_FILE_SIZE: usize = 1024 * 1024 * 500; // 500M
const UPSTREAM_URL: []const u8 = "https://ziglang.org";
const Context = struct {
    arena: std.heap.ArenaAllocator,
    download_dir: []const u8,

    mutex: *std.Thread.Mutex,
    pending_downloads: *std.StringHashMap(void),

    fn init(
        arena: std.heap.ArenaAllocator,
        dir: []const u8,
        mutex: *std.Thread.Mutex,
        pending: *std.StringHashMap(void),
    ) Context {
        return .{
            .arena = arena,
            .download_dir = dir,
            .mutex = mutex,
            .pending_downloads = pending,
        };
    }

    fn deinit(ctx: Context) void {
        ctx.arena.deinit();
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var options = try simargs.parse(allocator, struct {
        host: []const u8 = "0.0.0.0",
        port: u16 = 9090,
        threads: u32 = 32,
        tarball_dir: []const u8 = "/tmp",
        help: bool = false,

        pub const __messages__ = .{
            .host = "HTTP server bind host",
            .port = "HTTP server bind port",
            .threads = "Number of threads to use for serving HTTP requests",
            .tarball_dir = "Directory for storing zig tarballs",
            .help = "Show help",
        };

        pub const __shorts__ = .{
            .host = .h,
            .port = .p,
            .threads = .t,
            .tarball_dir = .d,
            .help = .h,
        };
    }, null, null);
    defer options.deinit();

    const bind_addr = try std.net.Address.parseIp(options.args.host, options.args.port);
    var server = try bind_addr.listen(.{
        .kernel_backlog = 128,
        .reuse_address = true,
    });
    defer server.deinit();
    std.log.info("Welcome to Zig Mirror Server, listen on {any}", .{server.listen_address});

    var pool = try allocator.create(std.Thread.Pool);
    defer pool.deinit();
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = options.args.threads,
    });

    var downloads_mutex = std.Thread.Mutex{};
    var pending_downloads = std.StringHashMap(void).init(allocator);
    defer pending_downloads.deinit();

    while (true) {
        const conn = server.accept() catch |err| {
            std.log.err("Accept connection failed, err: {s}", .{@errorName(err)});
            continue;
        };
        std.log.debug("Got new connection, addr:{any}", .{conn.address});
        var ctx = Context.init(
            std.heap.ArenaAllocator.init(allocator),
            options.args.tarball_dir,
            &downloads_mutex,
            &pending_downloads,
        );
        pool.spawn(accept, .{ &ctx, conn }) catch |err| {
            std.log.err("Spawn worker task failed, err: {s}", .{@errorName(err)});
            continue;
        };
    }
}

fn accept(ctx: *Context, conn: std.net.Server.Connection) void {
    defer conn.stream.close();
    defer ctx.deinit();

    var read_buffer: [0x4000]u8 = undefined;
    var server = std.http.Server.init(conn, &read_buffer);
    while (server.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.log.err("closing http connection: {s}", .{@errorName(err)});
                return;
            },
        };
        serveRequest(ctx, &request) catch |err| switch (err) {
            else => |e| {
                std.log.err("unable to serve {s}: {s}", .{ request.head.target, @errorName(e) });
                return;
            },
        };
    }
}

fn serveRequest(ctx: *Context, request: *std.http.Server.Request) !void {
    const allocator = ctx.arena.allocator();
    const path = request.head.target;
    const i = std.mem.lastIndexOfScalar(u8, path, '/') orelse unreachable;
    const requested_file = path[i + 1 ..];

    if (requested_file.len == 0) {
        return try request.respond(
            \\ <h1>Zig tarballs mirror</h1>
            \\ <p>This site acts as a mirror of ziglang.org/download</p>
            \\ <p><a href="https://github.com/jiacai2050/x/tree/main/zms">Source code</a></p>
        , .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html; charset=utf-8" },
            },
        });
    }

    const bytes = try loadTarball(ctx, allocator, requested_file);
    try request.respond(bytes, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/octet-stream" },
        },
    });
}

fn loadTarball(
    ctx: *Context,
    arena_allocator: std.mem.Allocator,
    filename: []const u8,
) ![]u8 {
    const tarball_path = try std.fmt.allocPrint(arena_allocator, "{s}/{s}", .{ ctx.download_dir, filename });
    return loadFromDisk(arena_allocator, tarball_path) catch |err| switch (err) {
        error.FileNotFound => {
            {
                ctx.mutex.lock();
                const existing = ctx.pending_downloads.contains(filename);
                if (existing) {
                    ctx.mutex.unlock();

                    std.log.debug("{s} is being fetched from upstream, wait 5s and retry...", .{filename});
                    std.time.sleep(5 * std.time.ns_per_s);
                    return loadTarball(ctx, arena_allocator, filename);
                }

                defer ctx.mutex.unlock();
                try ctx.pending_downloads.put(filename, {});
            }

            defer {
                ctx.mutex.lock();
                std.debug.assert(ctx.pending_downloads.remove(filename));
                ctx.mutex.unlock();
            }
            const tarball_bytes = try loadFromUpstream(arena_allocator, filename);
            const tmp_path = try std.fmt.allocPrint(arena_allocator, "{s}.tmp", .{tarball_path});
            const tmp_file = try std.fs.createFileAbsolute(tmp_path, .{ .exclusive = true });
            errdefer std.fs.deleteFileAbsolute(tmp_path) catch |err2| {
                std.log.err("Delete tmp file failed, file:{s}, err:{any}", .{ tmp_path, err2 });
            };

            try tmp_file.writeAll(tarball_bytes);
            tmp_file.close();

            try std.fs.renameAbsolute(tmp_path, tarball_path);
            return tarball_bytes;
        },
        else => return err,
    };
}

fn loadFromDisk(arena_allocator: std.mem.Allocator, filepath: []const u8) ![]u8 {
    std.log.debug("Try load from disk, path:{s}", .{filepath});
    const f = try std.fs.openFileAbsolute(filepath, .{});
    defer f.close();

    return try f.readToEndAlloc(arena_allocator, MAX_FILE_SIZE);
}

fn loadFromUpstream(arena_allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const sub_dir = if (std.mem.indexOf(u8, filename, "dev")) |_|
        // "https://ziglang.org/builds/zig-linux-armv7a-0.14.0-dev.1651+ffd071f55.tar.xz"
        "builds"
    else blk: {
        // We need to extract the version number from the filename
        // "https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz"
        const a = std.mem.lastIndexOfScalar(u8, filename, '-') orelse return error.BadFilename;
        const b = std.mem.indexOfScalarPos(u8, filename, a + 1, '.') orelse return error.BadFilename; // major version
        const c = std.mem.indexOfScalarPos(u8, filename, b + 1, '.') orelse return error.BadFilename; // min version
        const d = std.mem.indexOfScalarPos(u8, filename, c + 1, '.') orelse return error.BadFilename; // patch version

        const version = filename[a + 1 .. d];
        break :blk try std.fmt.allocPrint(arena_allocator, "download/{s}", .{version});
    };
    const tarball_url = try std.fmt.allocPrint(arena_allocator, "{s}/{s}/{s}", .{
        UPSTREAM_URL,
        sub_dir,
        filename,
    });
    std.log.debug("Downloading {s} from upstream", .{tarball_url});

    var client = std.http.Client{ .allocator = arena_allocator };
    var resp_buffer = std.ArrayList(u8).init(arena_allocator);
    const ret = try client.fetch(.{
        .location = .{ .url = tarball_url },
        .response_storage = .{ .dynamic = &resp_buffer },
        .max_append_size = MAX_FILE_SIZE,
    });

    if (ret.status != .ok) {
        std.log.err("Failed to download {s} from upstream: {d}", .{ tarball_url, ret.status });
        return error.UnexpectedHttpStatusCode;
    }
    return resp_buffer.items;
}
