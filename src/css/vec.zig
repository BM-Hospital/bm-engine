//! Minimal arena-friendly growable array. Unlike `std.ArrayList`, the growth path is type-erased
//! (one `growRaw` for every element type), which keeps the wasm small. API subset compatible with
//! `std.ArrayList` (`.empty`, `items`, `append`, `appendSlice`, `clearRetainingCapacity`, `deinit`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

pub fn Vec(comptime T: type) type {
    return struct {
        items: []T = &.{},
        cap: usize = 0,
        const Self = @This();
        pub const empty: Self = .{};

        pub fn ensureUnused(self: *Self, a: Allocator, n: usize) error{OutOfMemory}!void {
            const need = std.math.add(usize, self.items.len, n) catch return error.OutOfMemory;
            if (need <= self.cap) return;
            const np = try growRaw(a, @ptrCast(self.items.ptr), self.items.len, &self.cap, need, @sizeOf(T), comptime Alignment.of(T));
            self.items.ptr = @ptrCast(@alignCast(np));
        }
        pub fn append(self: *Self, a: Allocator, x: T) error{OutOfMemory}!void {
            if (self.items.len >= self.cap) try self.ensureUnused(a, 1);
            self.items.len += 1;
            self.items[self.items.len - 1] = x;
        }
        pub fn appendSlice(self: *Self, a: Allocator, xs: []const T) error{OutOfMemory}!void {
            try self.ensureUnused(a, xs.len);
            const old = self.items.len;
            self.items.len += xs.len;
            @memcpy(self.items[old..], xs);
        }
        pub fn clearRetainingCapacity(self: *Self) void {
            self.items.len = 0;
        }
        pub fn deinit(self: *Self, a: Allocator) void {
            if (self.cap > 0 and @sizeOf(T) > 0) {
                const p: [*]u8 = @ptrCast(self.items.ptr);
                a.rawFree(p[0 .. self.cap * @sizeOf(T)], comptime Alignment.of(T), @returnAddress());
            }
            self.* = .{};
        }
    };
}

noinline fn growRaw(a: Allocator, old: [*]u8, len: usize, cap: *usize, need: usize, size: usize, al: Alignment) error{OutOfMemory}![*]u8 {
    var nc = cap.* *| 2;
    if (nc < 8) nc = 8;
    if (nc < need) nc = need;
    const bytes = std.math.mul(usize, nc, size) catch return error.OutOfMemory;
    if (size == 0) return old;
    const np = a.rawAlloc(bytes, al, @returnAddress()) orelse return error.OutOfMemory;
    if (cap.* > 0) {
        @memcpy(np[0 .. len * size], old[0 .. len * size]);
        a.rawFree(old[0 .. cap.* * size], al, @returnAddress());
    }
    cap.* = nc;
    return np;
}

test "vec" {
    var v: Vec(u32) = .empty;
    defer v.deinit(std.testing.allocator);
    for (0..100) |i| try v.append(std.testing.allocator, @intCast(i));
    try v.appendSlice(std.testing.allocator, &.{ 1, 2, 3 });
    try std.testing.expectEqual(@as(usize, 103), v.items.len);
    try std.testing.expectEqual(@as(u32, 99), v.items[99]);
    try std.testing.expectEqual(@as(u32, 3), v.items[102]);
}
