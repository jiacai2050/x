const std = @import("std");

extern fn myclib_version() [*:0]const u8;
extern fn myclib_process(val: c_int) c_int;

pub fn main() void {
    const ver = std.mem.span(myclib_version());
    const res = myclib_process(21);
    std.debug.print("04-c-library-port test result: Version={s}, Process(21)={}\n", .{ ver, res });
    std.testing.expectEqualStrings("2.4.0", ver) catch @panic("Version mismatch");
    std.testing.expectEqual(@as(c_int, 42), res) catch @panic("Process result mismatch");
}
