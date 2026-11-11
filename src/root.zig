const std = @import("std");
pub fn add(a: u32, b: u32) u32 {
    return a + b;
}
test "add" {
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(std.testing.allocator);
    try list.append(std.testing.allocator, add(1, 2));
    try std.testing.expectEqual(@as(u32, 3), list.items[0]);
}
