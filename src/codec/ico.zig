//! ICO encoder: one PNG-compressed entry (Windows Vista+ ICO), like takumi's `write_ico`.
const std = @import("std");
const png = @import("png.zig");

/// Encodes straight RGBA8 as an ICO holding one PNG (`png.encode` with default options).
/// ICONDIR (reserved 0, type 1, count 1) + ICONDIRENTRY (width/height byte, 0 = 256; no palette;
/// planes 0; 32 bpp; PNG length; offset 22) + PNG. Each side must be 1..256. The result is
/// allocated from `alloc` (caller owns); the PNG temporary is freed.
pub fn encodeIco(alloc: std.mem.Allocator, rgba: []const u8, w: u32, h: u32) error{ OutOfMemory, InvalidInput, InvalidDimensions }![]u8 {
    if (w == 0 or h == 0 or w > 256 or h > 256) return error.InvalidDimensions;
    if (rgba.len != @as(usize, w) * h * 4) return error.InvalidInput;
    const p = try png.encode(alloc, rgba, w, h, .{});
    defer alloc.free(p);
    const out = try alloc.alloc(u8, 22 + p.len);
    const hdr = [14]u8{ 0, 0, 1, 0, 1, 0, @truncate(w), @truncate(h), 0, 0, 0, 0, 32, 0 };
    out[0..14].* = hdr;
    std.mem.writeInt(u32, out[14..18], @intCast(p.len), .little);
    std.mem.writeInt(u32, out[18..22], 22, .little);
    @memcpy(out[22..], p);
    return out;
}

test "ico wraps one png" {
    const t = std.testing;
    var img: [256 * 3 * 4]u8 = undefined;
    for (&img, 0..) |*b, i| b.* = @truncate(i * 7);
    const ico = try encodeIco(t.allocator, &img, 256, 3);
    defer t.allocator.free(ico);
    try t.expectEqualSlices(u8, &.{ 0, 0, 1, 0, 1, 0, 0, 3, 0, 0, 0, 0, 32, 0 }, ico[0..14]);
    try t.expectEqual(@as(u32, @intCast(ico.len - 22)), std.mem.readInt(u32, ico[14..18], .little));
    try t.expectEqual(@as(u32, 22), std.mem.readInt(u32, ico[18..22], .little));
    const d = try png.decode(t.allocator, ico[22..], .{});
    defer d.deinit(t.allocator);
    try t.expectEqualSlices(u8, &img, d.data);
    try t.expectError(error.InvalidDimensions, encodeIco(t.allocator, &img, 257, 1));
    try t.expectError(error.InvalidDimensions, encodeIco(t.allocator, &img, 0, 1));
    try t.expectError(error.InvalidInput, encodeIco(t.allocator, img[0..8], 1, 1));
}
