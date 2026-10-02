pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn multiply(a: i32, b: i32) i32 {
    return a * b;
}

test "calc operations" {
    const std = @import("std");
    try std.testing.expectEqual(@as(i32, 42), add(40, 2));
    try std.testing.expectEqual(@as(i32, 20), multiply(4, 5));
}
