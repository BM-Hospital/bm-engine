//! Small big-endian / sfnt helpers shared by the WOFF 1 and WOFF 2 decoders.
const std = @import("std");

pub fn tag(comptime s: *const [4]u8) u32 {
    return (@as(u32, s[0]) << 24) | (@as(u32, s[1]) << 16) | (@as(u32, s[2]) << 8) | s[3];
}

/// Callers guarantee `off + 2 <= b.len`.
pub inline fn rd16(b: []const u8, off: usize) u16 {
    return (@as(u16, b[off]) << 8) | b[off + 1];
}

/// Callers guarantee `off + 4 <= b.len`.
pub inline fn rd32(b: []const u8, off: usize) u32 {
    return (@as(u32, b[off]) << 24) | (@as(u32, b[off + 1]) << 16) | (@as(u32, b[off + 2]) << 8) | b[off + 3];
}

pub inline fn wr16(b: []u8, off: usize, v: u16) void {
    b[off] = @truncate(v >> 8);
    b[off + 1] = @truncate(v);
}

pub inline fn wr32(b: []u8, off: usize, v: u32) void {
    b[off] = @truncate(v >> 24);
    b[off + 1] = @truncate(v >> 16);
    b[off + 2] = @truncate(v >> 8);
    b[off + 3] = @truncate(v);
}

pub inline fn pad4(n: usize) usize {
    return (n +| 3) & ~@as(usize, 3); // saturating: callers compare against a cap
}

/// OpenType table checksum: wrapping sum of big-endian u32 words, the tail zero padded.
pub fn checksum(data: []const u8) u32 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i + 4 <= data.len) : (i += 4) {
        const w = std.mem.bigToNative(u32, @as(*align(1) const u32, @ptrCast(data.ptr + i)).*);
        sum +%= w;
    }
    if (i < data.len) {
        var last: [4]u8 = .{ 0, 0, 0, 0 };
        @memcpy(last[0 .. data.len - i], data[i..]);
        sum +%= rd32(&last, 0);
    }
    return sum;
}

/// Writes the 12-byte sfnt offset table header (version + binary-search fields).
pub fn writeOffsetTable(dst: []u8, off: usize, flavor: u32, num_tables: u16) void {
    var max_pow2: u4 = 0;
    if (num_tables != 0) max_pow2 = @intCast(15 - @clz(num_tables));
    const range: u16 = @truncate((@as(u32, 1) << max_pow2) << 4);
    wr32(dst, off, flavor);
    wr16(dst, off + 4, num_tables);
    wr16(dst, off + 6, range);
    wr16(dst, off + 8, max_pow2);
    wr16(dst, off + 10, @truncate((@as(u32, num_tables) << 4) -% range));
}

/// Sets head.checkSumAdjustment for one font: `dir_off` is its offset table, `head_off` the head
/// table offset in `out` (checkSumAdjustment must already be zero), `tables_sum` the sum of
/// the checksums of the font's tables.
pub fn fixHeadAdjustment(out: []u8, dir_off: usize, num_tables: u16, head_off: usize, tables_sum: u32) void {
    const dir_sum = checksum(out[dir_off..][0 .. 12 + 16 * @as(usize, num_tables)]);
    wr32(out, head_off + 8, 0xB1B0AFBA -% (tables_sum +% dir_sum));
}

test "checksum and offset table" {
    try std.testing.expectEqual(@as(u32, 0x01020304 +% 0x05000000), checksum(&.{ 1, 2, 3, 4, 5 }));
    var b: [12]u8 = undefined;
    writeOffsetTable(&b, 0, 0x00010000, 13);
    try std.testing.expectEqual(@as(u16, 128), rd16(&b, 6));
    try std.testing.expectEqual(@as(u16, 3), rd16(&b, 8));
    try std.testing.expectEqual(@as(u16, 13 * 16 - 128), rd16(&b, 10));
}

/// Sorts `idx` by `keys[idx[i]]` (heapsort: O(n log n) on hostile table counts, tiny code;
/// not stable, ties keep a deterministic order).
pub fn sortByKey(idx: []u16, keys: []const u32) void {
    const n = idx.len;
    if (n < 2) return;
    var start = n / 2;
    while (start > 0) {
        start -= 1;
        siftDown(idx, keys, start, n);
    }
    var end = n;
    while (end > 1) {
        end -= 1;
        std.mem.swap(u16, &idx[0], &idx[end]);
        siftDown(idx, keys, 0, end);
    }
}

fn siftDown(idx: []u16, keys: []const u32, start: usize, end: usize) void {
    var root = start;
    while (2 * root + 1 < end) {
        var child = 2 * root + 1;
        if (child + 1 < end and keys[idx[child]] < keys[idx[child + 1]]) child += 1;
        if (keys[idx[root]] >= keys[idx[child]]) return;
        std.mem.swap(u16, &idx[root], &idx[child]);
        root = child;
    }
}

test "sortByKey" {
    const keys = [_]u32{ 50, 10, 40, 10, 99, 0, 7 };
    var idx = [_]u16{ 0, 1, 2, 3, 4, 5, 6 };
    sortByKey(&idx, &keys);
    for (1..idx.len) |i| try std.testing.expect(keys[idx[i - 1]] <= keys[idx[i]]);
}
