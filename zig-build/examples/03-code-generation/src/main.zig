const std = @import("std");
const version = @import("version");
const table = @import("table");

pub fn main() void {
    std.debug.print("03-code-generation result: App={s}, Version={s}, BuildMode={s}, Multiplier={d}\n", .{
        version.app_name,
        version.version,
        version.build_mode,
        table.multiplier,
    });
}
