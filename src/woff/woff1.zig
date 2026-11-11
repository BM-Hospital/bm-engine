//! WOFF 1.0 decoder (W3C WOFF 1.0): header, table directory, per-table zlib (or stored) data,
//! sfnt rebuild. Table records are sorted by tag; table data keeps the WOFF file's data order
//! (which is the original font's order for spec-conforming encoders), each padded to 4 bytes,
//! so a font whose layout was canonical comes back byte-identical. Table checksums and
//! head.checkSumAdjustment are recomputed. Metadata and private blocks are ignored.
const std = @import("std");
const inflate = @import("../codec/inflate.zig");
const sfnt = @import("sfnt.zig");
const tag = sfnt.tag;
const rd16 = sfnt.rd16;
const rd32 = sfnt.rd32;
const wr32 = sfnt.wr32;

pub const Error = error{ InvalidData, OutputTooLarge, OutOfMemory };

const Entry = struct {
    tag: u32,
    off: u32,
    comp_len: u32,
    orig_len: u32,
    dst_off: u32 = 0,
    checksum: u32 = 0,
};

/// Decodes a WOFF 1.0 file into an sfnt allocated from `alloc` (caller owns it); output capped
/// at `max_out` bytes (and at 1.5x the declared totalSfntSize + 64 KiB).
pub fn decode(alloc: std.mem.Allocator, data: []const u8, max_out: usize) Error![]u8 {
    if (data.len < 44 or rd32(data, 0) != tag("wOFF")) return error.InvalidData;
    const flavor = rd32(data, 4);
    const n: usize = rd16(data, 12);
    const total_sfnt = rd32(data, 16);
    if (n == 0 or rd16(data, 14) != 0) return error.InvalidData;
    if (44 + 20 * n > data.len) return error.InvalidData;
    const cap: usize = @min(max_out, @as(usize, total_sfnt) +| (total_sfnt / 2) +| 65536);

    // One allocation for all temporaries: entries, sort keys, two index orders.
    const tmp = try alloc.alignedAlloc(u8, .of(Entry), n * (@sizeOf(Entry) + 8));
    defer alloc.free(tmp);
    const es: []Entry = @as([*]Entry, @ptrCast(tmp.ptr))[0..n];
    const keys: []u32 = @as([*]u32, @ptrCast(@alignCast(tmp.ptr + n * @sizeOf(Entry))))[0..n];
    const order: []u16 = @as([*]u16, @ptrCast(@alignCast(tmp.ptr + n * (@sizeOf(Entry) + 4))))[0..n];
    const by_off: []u16 = @as([*]u16, @ptrCast(@alignCast(tmp.ptr + n * (@sizeOf(Entry) + 6))))[0..n];
    for (es, 0..) |*e, i| {
        const p = 44 + 20 * i;
        e.* = .{ .tag = rd32(data, p), .off = rd32(data, p + 4), .comp_len = rd32(data, p + 8), .orig_len = rd32(data, p + 12) };
        if (e.off > data.len or e.comp_len > data.len - e.off) return error.InvalidData;
        if (e.comp_len > e.orig_len) return error.InvalidData;
        if (e.orig_len > cap) return error.OutputTooLarge;
    }
    // Records sorted by tag (duplicates rejected).
    for (order, 0..) |*o, i| o.* = @intCast(i);
    for (keys, es) |*k, e| k.* = e.tag;
    sfnt.sortByKey(order, keys);
    for (1..n) |k| if (es[order[k]].tag == es[order[k - 1]].tag) return error.InvalidData;

    // Data placed in file order.
    @memcpy(by_off, order);
    for (keys, es) |*k, e| k.* = e.off;
    sfnt.sortByKey(by_off, keys);
    var size: u64 = 12 + 16 * @as(u64, n);
    for (by_off) |k| {
        es[k].dst_off = @intCast(@min(size, 0xffff_ffff));
        size += sfnt.pad4(es[k].orig_len);
        if (size > cap) return error.OutputTooLarge;
    }

    const out = try alloc.alloc(u8, @intCast(size));
    errdefer alloc.free(out);
    var head_off: ?usize = null;
    for (es) |*e| {
        const dst = out[e.dst_off..][0..e.orig_len];
        const src = data[e.off..][0..e.comp_len];
        if (e.comp_len == e.orig_len) {
            @memcpy(dst, src);
        } else {
            const got = inflate.zlibDecompressInto(src, dst, .{}) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidData,
            };
            if (got != e.orig_len) return error.InvalidData;
        }
        @memset(out[e.dst_off + e.orig_len ..][0 .. sfnt.pad4(e.orig_len) - e.orig_len], 0);
        if (e.tag == tag("head")) {
            if (e.orig_len < 12) return error.InvalidData;
            wr32(dst, 8, 0);
            head_off = e.dst_off;
        }
        e.checksum = sfnt.checksum(dst);
    }
    sfnt.writeOffsetTable(out, 0, flavor, @intCast(n));
    var sum: u32 = 0;
    for (order, 0..) |k, i| {
        const e = es[k];
        const p = 12 + 16 * i;
        wr32(out, p, e.tag);
        wr32(out, p + 4, e.checksum);
        wr32(out, p + 8, e.dst_off);
        wr32(out, p + 12, e.orig_len);
        sum +%= e.checksum;
    }
    if (head_off) |h| sfnt.fixHeadAdjustment(out, 0, @intCast(n), h, sum);
    return out;
}
