const std = @import("std");
const my_lib = @import("my_lib");

pub fn main() void {
    const sum = my_lib.calc.add(40, 2);
    const prod = my_lib.calc.multiply(6, 7);
    std.debug.print("01-zig-app result: sum={}, prod={}\n", .{ sum, prod });
}
