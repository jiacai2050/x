pub const calc = @import("calc.zig");

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
