//! Unaligned little/big-endian loads and stores. `std.mem.readInt` compiles to a byte loop
//! under ReleaseSmall (-Oz) on wasm32, which made hot loops 2-3x slower; these are single
//! unaligned loads/stores (wasm and x86 are little-endian; byte swaps are added elsewhere).
const std = @import("std");

pub inline fn le16(s: []const u8, i: usize) u16 {
    return std.mem.littleToNative(u16, @as(*align(1) const u16, @ptrCast(s[i..][0..2])).*);
}
pub inline fn le32(s: []const u8, i: usize) u32 {
    return std.mem.littleToNative(u32, @as(*align(1) const u32, @ptrCast(s[i..][0..4])).*);
}
pub inline fn le64(s: []const u8, i: usize) u64 {
    return std.mem.littleToNative(u64, @as(*align(1) const u64, @ptrCast(s[i..][0..8])).*);
}
pub inline fn be16(s: []const u8, i: usize) u16 {
    return std.mem.bigToNative(u16, @as(*align(1) const u16, @ptrCast(s[i..][0..2])).*);
}
pub inline fn be32(s: []const u8, i: usize) u32 {
    return std.mem.bigToNative(u32, @as(*align(1) const u32, @ptrCast(s[i..][0..4])).*);
}
pub inline fn putLe32(s: []u8, i: usize, v: u32) void {
    @as(*align(1) u32, @ptrCast(s[i..][0..4])).* = std.mem.nativeToLittle(u32, v);
}
pub inline fn putBe32(s: []u8, i: usize, v: u32) void {
    @as(*align(1) u32, @ptrCast(s[i..][0..4])).* = std.mem.nativeToBig(u32, v);
}

test "bytes" {
    const b = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    try std.testing.expectEqual(@as(u32, 0x04030201), le32(&b, 0));
    try std.testing.expectEqual(@as(u32, 0x02030405), be32(&b, 1));
    try std.testing.expectEqual(@as(u64, 0x0908070605040302), le64(&b, 1));
    try std.testing.expectEqual(@as(u16, 0x0203), be16(&b, 1));
    var o: [4]u8 = undefined;
    putBe32(&o, 0, 0x01020304);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, &o);
}
