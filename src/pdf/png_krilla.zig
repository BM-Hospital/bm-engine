//! The PNG decode krilla does for an image it cannot pass through (krilla `decode_png` over the
//! `png` crate with `Transformations::EXPAND`): palette images become RGB (RGBA with `tRNS`),
//! grayscale below 8 bits is scaled to 8 bits, a `tRNS` colour key becomes an alpha channel,
//! 16-bit samples stay 16-bit (big-endian, as PDF wants them), gamma / sRGB chunks are ignored.
//! The result is split into the colour samples and the alpha samples of the image XObject and its
//! soft mask. Unlike bm-engine's own decoder (src/codec/png.zig) it checks every CRC up to the end
//! of the image data and fails with the `png` crate's messages, which takumi-pdf reports as
//! `Writing the PDF failed: failed to process image: <message>`.
const std = @import("std");
const checksum = @import("../codec/checksum.zig");
const inflate = @import("../codec/inflate.zig");

pub const Space = enum { luma, rgb };

pub const Decoded = struct {
    w: u32,
    h: u32,
    space: Space,
    /// 8 or 16
    bits: u8,
    /// colour samples, `w * h * comps * bits / 8` bytes
    color: []u8,
    /// alpha samples (same bit depth), null when the image has none (8-bit: or every pixel is opaque)
    alpha: ?[]u8,
};

/// What `png_metadata` (the `png` crate's `read_info`) reads: the header and the chunks before the
/// first IDAT.
pub const Meta = struct {
    w: u32,
    h: u32,
    depth: u8,
    ct: u8,
    interlaced: bool,
    space: Space,
    has_alpha: bool,
    /// the iCCP profile, inflated (null: none, or not inflatable)
    icc: ?[]const u8 = null,
};

pub const Result = union(enum) {
    ok: Decoded,
    /// `read_info` fails: krilla does not take the image (takumi then decodes it itself)
    no_meta,
    /// decoding fails: the `png` crate's message
    fail: []const u8,
};

const signature = "\x89PNG\r\n\x1a\n";

const Chunk = struct { kind: *const [4]u8, data: []const u8, crc: u32, end: usize };

fn chunkAt(b: []const u8, p: usize) ?Chunk {
    if (p > b.len or b.len - p < 8) return null;
    const len = std.mem.readInt(u32, b[p..][0..4], .big);
    if (len > b.len - p - 8 or b.len - p - 8 - len < 4) return null;
    return .{ .kind = b[p + 4 ..][0..4], .data = b[p + 8 ..][0..len], .crc = std.mem.readInt(u32, b[p + 8 + len ..][0..4], .big), .end = p + 12 + len };
}

fn crcOf(c: Chunk) u32 {
    return checksum.crc32(checksum.crc32(0, c.kind), c.data);
}

/// The `png` crate's `CrcMismatch` message.
fn crcMessage(a: std.mem.Allocator, c: Chunk) []const u8 {
    const k = c.kind;
    const bit = struct {
        fn f(x: u8) []const u8 {
            return if (x & 0x20 != 0) "true" else "false";
        }
    }.f;
    return std.fmt.allocPrint(a, "CRC error: expected 0x{x} have 0x{x} while decoding ChunkType {{ type: {s}, critical: {s}, private: {s}, reserved: {s}, safecopy: {s} }} chunk.", .{
        c.crc, crcOf(c), k, if (k[0] & 0x20 == 0) "true" else "false", bit(k[1]), bit(k[2]), bit(k[3]),
    }) catch "CRC error";
}

/// The header and the chunks up to the first IDAT (`read_info`); null when that fails.
pub fn meta(a: std.mem.Allocator, b: []const u8) ?Meta {
    if (b.len < 8 or !std.mem.eql(u8, b[0..8], signature)) return null;
    var p: usize = 8;
    const ih = chunkAt(b, p) orelse return null;
    if (!std.mem.eql(u8, ih.kind, "IHDR") or ih.data.len != 13 or crcOf(ih) != ih.crc) return null;
    const d = ih.data;
    var m: Meta = .{
        .w = std.mem.readInt(u32, d[0..4], .big),
        .h = std.mem.readInt(u32, d[4..8], .big),
        .depth = d[8],
        .ct = d[9],
        .interlaced = d[12] == 1,
        .space = .rgb,
        .has_alpha = false,
    };
    const ok = switch (m.ct) {
        0 => m.depth == 1 or m.depth == 2 or m.depth == 4 or m.depth == 8 or m.depth == 16,
        2, 4, 6 => m.depth == 8 or m.depth == 16,
        3 => m.depth == 1 or m.depth == 2 or m.depth == 4 or m.depth == 8,
        else => false,
    };
    if (!ok or m.w == 0 or m.h == 0 or d[10] != 0 or d[11] != 0 or d[12] > 1) return null;
    p = ih.end;
    var trns = false;
    var plte = false;
    while (true) {
        // (the first IDAT's header ends `read_info`; its data is read when decoding)
        if (p <= b.len and b.len - p >= 8 and std.mem.eql(u8, b[p + 4 ..][0..4], "IDAT")) break;
        const c = chunkAt(b, p) orelse return null;
        if (crcOf(c) != c.crc) return null;
        if (std.mem.eql(u8, c.kind, "IEND")) return null;
        if (std.mem.eql(u8, c.kind, "PLTE")) plte = true;
        if (std.mem.eql(u8, c.kind, "tRNS")) trns = true;
        if (std.mem.eql(u8, c.kind, "iCCP") and m.icc == null) m.icc = iccOf(a, c.data);
        p = c.end;
    }
    if (m.ct == 3 and !plte) return null;
    m.space = if (m.ct == 0 or m.ct == 4) .luma else .rgb;
    m.has_alpha = m.ct == 4 or m.ct == 6 or trns;
    return m;
}

/// An iCCP chunk's profile: name, NUL, compression method 0, zlib data.
fn iccOf(a: std.mem.Allocator, d: []const u8) ?[]const u8 {
    const nul = std.mem.indexOfScalar(u8, d, 0) orelse return null;
    if (nul + 2 > d.len or d[nul + 1] != 0) return null;
    return inflate.zlibDecompressAlloc(a, d[nul + 2 ..], 16 << 20, .{}) catch null;
}

const adam7 = [7][4]u8{ .{ 0, 0, 8, 8 }, .{ 4, 0, 8, 8 }, .{ 0, 4, 4, 8 }, .{ 2, 0, 4, 4 }, .{ 0, 2, 2, 4 }, .{ 1, 0, 2, 2 }, .{ 0, 1, 1, 2 } };

fn passDim(full: u32, start: u8, step: u8) usize {
    if (full <= start) return 0;
    return (full - start + step - 1) / step;
}

/// krilla `decode_png` for a PNG that is not passed through.
pub fn decode(a: std.mem.Allocator, b: []const u8, max_pixels: u64) Result {
    const m = meta(a, b) orelse return .no_meta;
    if (@as(u64, m.w) * m.h > max_pixels) return .{ .fail = "image is too large" };
    // the chunks from the first IDAT on: palette / tRNS were read before it
    var palette: []const u8 = &.{};
    var trns: ?[]const u8 = null;
    var p: usize = 8;
    var z: std.ArrayList(u8) = .empty;
    var in_idat = false;
    while (true) {
        const c = chunkAt(b, p) orelse {
            // (a cut chunk: the image data before it may still be complete)
            if (z.items.len == 0) return .{ .fail = "unexpected end of file" };
            break;
        };
        if (std.mem.eql(u8, c.kind, "IDAT")) {
            if (crcOf(c) != c.crc) return .{ .fail = crcMessage(a, c) };
            z.appendSlice(a, c.data) catch return .{ .fail = "out of memory" };
            in_idat = true;
        } else {
            if (in_idat) break;
            if (std.mem.eql(u8, c.kind, "PLTE")) palette = c.data;
            if (std.mem.eql(u8, c.kind, "tRNS")) trns = c.data;
        }
        p = c.end;
    }
    const ch: usize = switch (m.ct) {
        0, 3 => 1,
        2 => 3,
        4 => 2,
        else => 4,
    };
    const bpp_bits: usize = ch * m.depth;
    const row_bytes = struct {
        fn f(w: usize, bits: usize) usize {
            return (w * bits + 7) / 8;
        }
    }.f;
    var raw_len: usize = 0;
    if (m.interlaced) {
        for (adam7) |pa| {
            const pw = passDim(m.w, pa[0], pa[2]);
            const ph = passDim(m.h, pa[1], pa[3]);
            if (pw != 0 and ph != 0) raw_len += ph * (1 + row_bytes(pw, bpp_bits));
        }
    } else raw_len = @as(usize, m.h) * (1 + row_bytes(m.w, bpp_bits));
    const raw = a.alloc(u8, raw_len) catch return .{ .fail = "out of memory" };
    const got = inflate.zlibDecompressInto(z.items, raw, .{}) catch return .{ .fail = "corrupt deflate stream" };
    if (got < raw_len) return .{ .fail = "unexpected end of file" };

    // output: EXPAND
    const out_bits: u8 = if (m.depth == 16) 16 else 8;
    const sb: usize = out_bits / 8;
    const space: Space = if (m.ct == 0 or m.ct == 4) .luma else .rgb;
    const comps: usize = if (space == .luma) 1 else 3;
    const has_alpha = m.ct == 4 or m.ct == 6 or trns != null;
    const n: usize = @as(usize, m.w) * m.h;
    const color = a.alloc(u8, n * comps * sb) catch return .{ .fail = "out of memory" };
    const alpha: []u8 = if (has_alpha) (a.alloc(u8, n * sb) catch return .{ .fail = "out of memory" }) else &.{};
    @memset(color, 0);
    if (has_alpha) @memset(alpha, 0xFF);

    const filter_bpp = @max(1, bpp_bits / 8);
    var off: usize = 0;
    const max_row = row_bytes(m.w, bpp_bits);
    const prev = a.alloc(u8, max_row) catch return .{ .fail = "out of memory" };
    for (0..7) |pi| {
        const pa: [4]u8 = if (m.interlaced) adam7[pi] else .{ 0, 0, 1, 1 };
        const pw = if (m.interlaced) passDim(m.w, pa[0], pa[2]) else m.w;
        const ph = if (m.interlaced) passDim(m.h, pa[1], pa[3]) else m.h;
        if (pw != 0 and ph != 0) {
            const rb = row_bytes(pw, bpp_bits);
            @memset(prev[0..rb], 0);
            for (0..ph) |ry| {
                const ft = raw[off];
                const row = raw[off + 1 ..][0..rb];
                off += 1 + rb;
                if (!unfilter(ft, row, prev[0..rb], filter_bpp)) return .{ .fail = "invalid filter method" };
                @memcpy(prev[0..rb], row);
                const y = pa[1] + ry * pa[3];
                for (0..pw) |rx| {
                    const x = pa[0] + rx * pa[2];
                    const i = y * m.w + x;
                    writePixel(&m, row, rx, palette, trns, color[i * comps * sb ..][0 .. comps * sb], if (has_alpha) alpha[i * sb ..][0..sb] else &.{});
                }
            }
        }
        if (!m.interlaced) break;
    }
    var mask: ?[]u8 = if (has_alpha) alpha else null;
    // krilla `handle_u8_image`: an 8-bit alpha channel that is all opaque is left out
    if (out_bits == 8 and has_alpha) {
        if (std.mem.allEqual(u8, alpha, 255)) mask = null;
    }
    return .{ .ok = .{ .w = m.w, .h = m.h, .space = space, .bits = out_bits, .color = color, .alpha = mask } };
}

fn paeth(a: u8, b: u8, c: u8) u8 {
    const p: i16 = @as(i16, a) + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

fn unfilter(ft: u8, row: []u8, prev: []const u8, bpp: usize) bool {
    switch (ft) {
        0 => {},
        1 => for (bpp..row.len) |i| {
            row[i] +%= row[i - bpp];
        },
        2 => for (0..row.len) |i| {
            row[i] +%= prev[i];
        },
        3 => for (0..row.len) |i| {
            const l: u16 = if (i >= bpp) row[i - bpp] else 0;
            row[i] +%= @intCast((l + prev[i]) / 2);
        },
        4 => for (0..row.len) |i| {
            const l: u8 = if (i >= bpp) row[i - bpp] else 0;
            const ul: u8 = if (i >= bpp) prev[i - bpp] else 0;
            row[i] +%= paeth(l, prev[i], ul);
        },
        else => return false,
    }
    return true;
}

/// Sample `k` (in units of `depth` bits) of `row`.
fn sample(row: []const u8, k: usize, depth: u8) u16 {
    return switch (depth) {
        16 => std.mem.readInt(u16, row[k * 2 ..][0..2], .big),
        8 => row[k],
        else => blk: {
            const bit = k * depth;
            const shift: u3 = @intCast(8 - depth - (bit % 8));
            const mask: u8 = @intCast((@as(u16, 1) << @intCast(depth)) - 1);
            break :blk (row[bit / 8] >> shift) & mask;
        },
    };
}

fn put(dst: []u8, v: u16, sb: usize) void {
    if (sb == 2) std.mem.writeInt(u16, dst[0..2], v, .big) else dst[0] = @intCast(v);
}

fn writePixel(m: *const Meta, row: []const u8, x: usize, palette: []const u8, trns: ?[]const u8, col: []u8, al: []u8) void {
    const d = m.depth;
    const sb: usize = if (d == 16) 2 else 1;
    switch (m.ct) {
        0 => {
            const v = sample(row, x, d);
            // EXPAND scales low bit depths to 8 bits
            const scaled: u16 = if (d < 8) v * (255 / ((@as(u16, 1) << @intCast(d)) - 1)) else v;
            put(col, scaled, sb);
            if (al.len > 0) if (trns) |t| {
                if (t.len >= 2 and std.mem.readInt(u16, t[0..2], .big) == v) put(al, 0, sb);
            };
        },
        2 => {
            const r = sample(row, x * 3, d);
            const g = sample(row, x * 3 + 1, d);
            const b = sample(row, x * 3 + 2, d);
            put(col[0..], r, sb);
            put(col[sb..], g, sb);
            put(col[2 * sb ..], b, sb);
            if (al.len > 0) if (trns) |t| {
                if (t.len >= 6 and std.mem.readInt(u16, t[0..2], .big) == r and std.mem.readInt(u16, t[2..4], .big) == g and std.mem.readInt(u16, t[4..6], .big) == b) put(al, 0, sb);
            };
        },
        3 => {
            const idx = sample(row, x, d);
            if (idx * 3 + 2 < palette.len) {
                col[0] = palette[idx * 3];
                col[1] = palette[idx * 3 + 1];
                col[2] = palette[idx * 3 + 2];
            }
            if (al.len > 0) {
                const t = trns orelse &.{};
                al[0] = if (idx < t.len) t[idx] else 255;
            }
        },
        4 => {
            put(col, sample(row, x * 2, d), sb);
            put(al, sample(row, x * 2 + 1, d), sb);
        },
        else => {
            for (0..3) |k| put(col[k * sb ..], sample(row, x * 4 + k, d), sb);
            put(al, sample(row, x * 4 + 3, d), sb);
        },
    }
}

test "png krilla decode: gray+alpha stays gray, 16-bit stays 16-bit, crc and truncation fail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const deflate = @import("../codec/deflate.zig");
    const Build = struct {
        fn chunk(out: *std.ArrayList(u8), al: std.mem.Allocator, kind: []const u8, data: []const u8) !void {
            var len: [4]u8 = undefined;
            std.mem.writeInt(u32, &len, @intCast(data.len), .big);
            try out.appendSlice(al, &len);
            try out.appendSlice(al, kind);
            try out.appendSlice(al, data);
            var crc: [4]u8 = undefined;
            std.mem.writeInt(u32, &crc, checksum.crc32(checksum.crc32(0, kind), data), .big);
            try out.appendSlice(al, &crc);
        }
        fn png(al: std.mem.Allocator, w: u8, h: u8, depth: u8, ct: u8, rows: []const u8) ![]u8 {
            var out: std.ArrayList(u8) = .empty;
            try out.appendSlice(al, signature);
            try chunk(&out, al, "IHDR", &.{ 0, 0, 0, w, 0, 0, 0, h, depth, ct, 0, 0, 0 });
            try chunk(&out, al, "IDAT", try deflate.compress(al, rows, .default));
            try chunk(&out, al, "IEND", "");
            return out.items;
        }
    };
    // 2x1 gray+alpha 8-bit
    const ga = try Build.png(a, 2, 1, 8, 4, &.{ 0, 10, 20, 30, 255 });
    const r = decode(a, ga, 1 << 20).ok;
    try std.testing.expectEqual(Space.luma, r.space);
    try std.testing.expectEqualSlices(u8, &.{ 10, 30 }, r.color);
    try std.testing.expectEqualSlices(u8, &.{ 20, 255 }, r.alpha.?);
    // 1x1 RGBA 16-bit, opaque: the alpha channel stays
    const r16 = decode(a, try Build.png(a, 1, 1, 16, 6, &.{ 0, 1, 2, 3, 4, 5, 6, 255, 255 }), 1 << 20).ok;
    try std.testing.expectEqual(@as(u8, 16), r16.bits);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6 }, r16.color);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255 }, r16.alpha.?);
    // a damaged IDAT CRC
    const bad = try a.dupe(u8, ga);
    bad[bad.len - 14] ^= 0xff;
    try std.testing.expect(std.mem.startsWith(u8, decode(a, bad, 1 << 20).fail, "CRC error: expected 0x"));
    try std.testing.expect(std.mem.endsWith(u8, decode(a, bad, 1 << 20).fail, "while decoding ChunkType { type: IDAT, critical: true, private: false, reserved: false, safecopy: false } chunk."));
    // cut inside the IDAT
    try std.testing.expectEqualStrings("unexpected end of file", decode(a, ga[0 .. 33 + 10], 1 << 20).fail);
}
