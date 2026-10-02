const std = @import("std");
const math = @import("native_math");

pub fn main() void {
    const sum = math.native_add(10, 20);
    const prod = math.native_multiply(6, 7);
    std.debug.print("02-mixed-c-zig result: native_add={}, native_multiply={}\n", .{ sum, prod });
}
