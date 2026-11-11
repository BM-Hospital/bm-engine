//! WebP decoder: lossless VP8L (all transforms, color cache, meta prefix codes) and lossy
//! VP8 (+ ALPH alpha, see vp8.zig), plain RIFF or VP8X-wrapped (still image, or the first
//! ANMF frame of an animation on a transparent canvas; full animation: anim.zig).
//! Inputs are untrusted: every read is bounds-checked; allocations are bounded by
//! `Limits.max_pixels`. Temporaries use an internal arena on top of `alloc`; only the
//! returned `Image.data` stays allocated (caller frees with `alloc`).
const std = @import("std");
const types = @import("types.zig");

const Image = types.Image;
const Limits = types.Limits;
const Error = types.Error;

/// VP8L 2D distance codes 1..120: byte = (yoffset << 4) | (8 - xoffset); distance = x + y*width.
pub const code_to_plane: [120]u8 = blk: {
    const pairs = [120][2]i8{
        .{ 0, 1 },  .{ 1, 0 },  .{ 1, 1 },  .{ -1, 1 }, .{ 0, 2 },  .{ 2, 0 },  .{ 1, 2 },  .{ -1, 2 },
        .{ 2, 1 },  .{ -2, 1 }, .{ 2, 2 },  .{ -2, 2 }, .{ 0, 3 },  .{ 3, 0 },  .{ 1, 3 },  .{ -1, 3 },
        .{ 3, 1 },  .{ -3, 1 }, .{ 2, 3 },  .{ -2, 3 }, .{ 3, 2 },  .{ -3, 2 }, .{ 0, 4 },  .{ 4, 0 },
        .{ 1, 4 },  .{ -1, 4 }, .{ 4, 1 },  .{ -4, 1 }, .{ 3, 3 },  .{ -3, 3 }, .{ 2, 4 },  .{ -2, 4 },
        .{ 4, 2 },  .{ -4, 2 }, .{ 0, 5 },  .{ 3, 4 },  .{ -3, 4 }, .{ 4, 3 },  .{ -4, 3 }, .{ 5, 0 },
        .{ 1, 5 },  .{ -1, 5 }, .{ 5, 1 },  .{ -5, 1 }, .{ 2, 5 },  .{ -2, 5 }, .{ 5, 2 },  .{ -5, 2 },
        .{ 4, 4 },  .{ -4, 4 }, .{ 3, 5 },  .{ -3, 5 }, .{ 5, 3 },  .{ -5, 3 }, .{ 0, 6 },  .{ 6, 0 },
        .{ 1, 6 },  .{ -1, 6 }, .{ 6, 1 },  .{ -6, 1 }, .{ 2, 6 },  .{ -2, 6 }, .{ 6, 2 },  .{ -6, 2 },
        .{ 4, 5 },  .{ -4, 5 }, .{ 5, 4 },  .{ -5, 4 }, .{ 3, 6 },  .{ -3, 6 }, .{ 6, 3 },  .{ -6, 3 },
        .{ 0, 7 },  .{ 7, 0 },  .{ 1, 7 },  .{ -1, 7 }, .{ 5, 5 },  .{ -5, 5 }, .{ 7, 1 },  .{ -7, 1 },
        .{ 4, 6 },  .{ -4, 6 }, .{ 6, 4 },  .{ -6, 4 }, .{ 2, 7 },  .{ -2, 7 }, .{ 7, 2 },  .{ -7, 2 },
        .{ 3, 7 },  .{ -3, 7 }, .{ 7, 3 },  .{ -7, 3 }, .{ 5, 6 },  .{ -5, 6 }, .{ 6, 5 },  .{ -6, 5 },
        .{ 8, 0 },  .{ 4, 7 },  .{ -4, 7 }, .{ 7, 4 },  .{ -7, 4 }, .{ 8, 1 },  .{ 8, 2 },  .{ 6, 6 },
        .{ -6, 6 }, .{ 8, 3 },  .{ 5, 7 },  .{ -5, 7 }, .{ 7, 5 },  .{ -7, 5 }, .{ 8, 4 },  .{ 6, 7 },
        .{ -6, 7 }, .{ 7, 6 },  .{ -7, 6 }, .{ 8, 5 },  .{ 7, 7 },  .{ -7, 7 }, .{ 8, 6 },  .{ 8, 7 },
    };
    var t: [120]u8 = undefined;
    for (pairs, 0..) |p, i| t[i] = @intCast((@as(i32, p[1]) << 4) | (8 - @as(i32, p[0])));
    break :blk t;
};

/// Width/height from a VP8 / VP8L / VP8X RIFF header (no pixel decode).
pub fn dimensions(bytes: []const u8) ?[2]u32 {
    if (bytes.len < 30 or !std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WEBP")) return null;
    const tag = bytes[12..16];
    const p = bytes[20..];
    if (std.mem.eql(u8, tag, "VP8L")) {
        if (p[0] != 0x2f) return null;
        const v = std.mem.readInt(u32, p[1..5], .little);
        return .{ (v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1 };
    } else if (std.mem.eql(u8, tag, "VP8X")) {
        return .{ rd24(p[4..7]) + 1, rd24(p[7..10]) + 1 };
    } else if (std.mem.eql(u8, tag, "VP8 ")) {
        if (p[3] != 0x9d or p[4] != 0x01 or p[5] != 0x2a) return null;
        return .{ std.mem.readInt(u16, p[6..8], .little) & 0x3fff, std.mem.readInt(u16, p[8..10], .little) & 0x3fff };
    }
    return null;
}

fn rd24(b: []const u8) u32 {
    return @as(u32, b[0]) | (@as(u32, b[1]) << 8) | (@as(u32, b[2]) << 16);
}

/// Optional decoder features, resolved at compile time so unused code is not linked.
pub const Features = struct {
    /// Lossy VP8 (+ ALPH) support; when false lossy files return error.UnsupportedFormat.
    lossy: bool = true,
};

/// Decodes a WebP file to straight RGBA8 (animated files: the first frame on the canvas).
pub fn decode(alloc: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!Image {
    return decodeEx(alloc, bytes, limits, .{});
}

/// RIFF chunk iterator over `data` (the bytes after a RIFF/ANMF header). Truncated
/// chunk bodies are clipped to the available data.
pub const Chunks = struct {
    data: []const u8,
    pos: usize = 0,

    pub const Chunk = struct { tag: [4]u8, body: []const u8, offset: usize };

    pub fn next(it: *Chunks) ?Chunk {
        if (it.data.len < 8 or it.pos > it.data.len - 8) return null;
        const tag = it.data[it.pos..][0..4].*;
        const len = std.mem.readInt(u32, it.data[it.pos + 4 ..][0..4], .little);
        const start = it.pos + 8;
        const end: usize = @intCast(@min(@as(u64, it.data.len), @as(u64, start) + len));
        const next_pos = @as(u64, start) + len + (len & 1);
        it.pos = @intCast(@min(next_pos, @as(u64, it.data.len)));
        return .{ .tag = tag, .body = it.data[start..end], .offset = start - 8 };
    }
};

/// The chunk area of a RIFF/WEBP file, or null if the header is wrong.
pub fn riffBody(bytes: []const u8) ?[]const u8 {
    if (bytes.len < 12 or !std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WEBP")) return null;
    const riff_len = std.mem.readInt(u32, bytes[4..8], .little);
    const end: usize = @intCast(@min(@as(u64, bytes.len), @as(u64, riff_len) + 8));
    if (end < 12) return null;
    return bytes[12..end];
}

/// Decodes one image from a chunk sequence: `VP8L`, or optional `ALPH` followed by `VP8 `
/// (other chunks are skipped). Used for still files and for ANMF frame payloads.
pub fn decodeImageChunks(alloc: std.mem.Allocator, chunks: []const u8, limits: Limits, comptime f: Features) Error!Image {
    var it = Chunks{ .data = chunks };
    var alph: ?[]const u8 = null;
    while (it.next()) |c| {
        if (std.mem.eql(u8, &c.tag, "VP8L")) return decodeVp8l(alloc, c.body, limits);
        if (std.mem.eql(u8, &c.tag, "ALPH")) {
            alph = c.body;
        } else if (std.mem.eql(u8, &c.tag, "VP8 ")) {
            if (!f.lossy) return error.UnsupportedFormat;
            return @import("vp8.zig").decode(alloc, c.body, alph, limits);
        }
    }
    return error.InvalidData;
}

/// `decode` with compile-time feature selection.
pub fn decodeEx(alloc: std.mem.Allocator, bytes: []const u8, limits: Limits, comptime f: Features) Error!Image {
    const body = riffBody(bytes) orelse return error.InvalidData;
    var it = Chunks{ .data = body };
    var canvas: ?[2]u32 = null;
    while (it.next()) |c| {
        if (std.mem.eql(u8, &c.tag, "VP8X")) {
            if (c.body.len < 10) return error.InvalidData;
            canvas = .{ rd24(c.body[4..7]) + 1, rd24(c.body[7..10]) + 1 };
        } else if (std.mem.eql(u8, &c.tag, "ANMF")) {
            // First frame of an animation, placed on a transparent canvas (frame 0 has
            // nothing below it, so blending is a plain copy).
            const cv = canvas orelse return error.InvalidData;
            if (c.body.len < 16) return error.InvalidData;
            const fx = rd24(c.body[0..3]) * 2;
            const fy = rd24(c.body[3..6]) * 2;
            const n = try types.checkSize(cv[0], cv[1], limits);
            const frame = try decodeImageChunks(alloc, c.body[16..], limits, f);
            defer frame.deinit(alloc);
            const out = try alloc.alloc(u8, n);
            @memset(out, 0);
            blit(out, cv[0], cv[1], frame, fx, fy);
            return .{ .width = cv[0], .height = cv[1], .data = out };
        } else if (std.mem.eql(u8, &c.tag, "VP8L") or std.mem.eql(u8, &c.tag, "VP8 ") or std.mem.eql(u8, &c.tag, "ALPH")) {
            const img = try decodeImageChunks(alloc, body[c.offset..], limits, f);
            if (canvas) |cv| if (cv[0] != img.width or cv[1] != img.height) {
                img.deinit(alloc);
                return error.InvalidData;
            };
            return img;
        }
    }
    return error.InvalidData;
}

/// Copies `src` into the `cw`x`ch` RGBA canvas at (fx, fy), clipped.
pub fn blit(out: []u8, cw: u32, c_h: u32, src: Image, fx: u32, fy: u32) void {
    if (fx >= cw or fy >= c_h) return;
    const wcopy: usize = @min(src.width, cw - fx);
    var y: u32 = 0;
    while (y < src.height and fy + y < c_h) : (y += 1) {
        const dst = (@as(usize, fy + y) * cw + fx) * 4;
        const s = @as(usize, y) * src.width * 4;
        @memcpy(out[dst .. dst + wcopy * 4], src.data[s .. s + wcopy * 4]);
    }
}

// ---------------------------------------------------------------------------------------------
// Bit reader (LSB first). Reads past the end yield zeros; `overrun()` detects it.

const BitReader = struct {
    data: []const u8,
    pos: usize = 0,
    buf: u64 = 0,
    nbits: u32 = 0,

    inline fn fill(br: *BitReader) void {
        if (br.pos + 8 <= br.data.len) {
            const v = std.mem.littleToNative(u64, @as(*align(1) const u64, @ptrCast(br.data.ptr + br.pos)).*);
            br.buf |= v << @intCast(br.nbits);
            const take = (63 - br.nbits) >> 3;
            br.pos += take;
            br.nbits += take * 8;
            return;
        }
        while (br.nbits <= 56) {
            const b: u64 = if (br.pos < br.data.len) br.data[br.pos] else 0;
            br.pos += 1;
            br.buf |= b << @intCast(br.nbits);
            br.nbits += 8;
        }
    }
    inline fn read(br: *BitReader, n: u5) u32 {
        if (br.nbits < 32) br.fill();
        const v: u32 = @intCast(br.buf & ((@as(u64, 1) << n) - 1));
        br.buf >>= n;
        br.nbits -= n;
        return v;
    }
    fn overrun(br: *const BitReader) bool {
        // Bits consumed = pos*8 - nbits; must not exceed data.len*8.
        return @as(u64, br.pos) * 8 - br.nbits > @as(u64, br.data.len) * 8;
    }
};

// ---------------------------------------------------------------------------------------------
// Prefix (Huffman) codes.

const HCode = struct {
    /// (sym << 4) | len for codes of length <= 8; len 0 => long code (slow path).
    lut: [256]u16,
    count: [16]u16,
    syms: []u16,
    /// Single-symbol code: consumes zero bits.
    single: ?u16,

    fn build(hc: *HCode, arena: std.mem.Allocator, lengths: []const u8) Error!void {
        hc.count = @splat(0);
        var nz: usize = 0;
        var last: u16 = 0;
        for (lengths, 0..) |l, i| {
            if (l > 15) return error.InvalidData;
            hc.count[l] += 1;
            if (l != 0) {
                nz += 1;
                last = @intCast(i);
            }
        }
        if (nz == 0) return error.InvalidData;
        if (nz == 1) {
            hc.single = last;
            hc.syms = &.{};
            return;
        }
        hc.single = null;
        hc.count[0] = 0;
        var left: i32 = 1;
        for (1..16) |l| {
            left <<= 1;
            left -= hc.count[l];
            if (left < 0) return error.InvalidData;
        }
        if (left != 0) return error.InvalidData;
        var offs: [16]u16 = undefined;
        offs[1] = 0;
        for (1..15) |l| offs[l + 1] = offs[l] + hc.count[l];
        hc.syms = try arena.alloc(u16, nz);
        for (lengths, 0..) |l, i| {
            if (l != 0) {
                hc.syms[offs[l]] = @intCast(i);
                offs[l] += 1;
            }
        }
        @memset(&hc.lut, 0);
        var code: u32 = 0;
        var idx: usize = 0;
        for (1..9) |l| {
            var c = hc.count[l];
            while (c > 0) : (c -= 1) {
                const rev = @bitReverse(@as(u8, @truncate(code << @intCast(8 - l))));
                const entry: u16 = (hc.syms[idx] << 4) | @as(u16, @intCast(l));
                var k: usize = rev;
                while (k < 256) : (k += @as(usize, 1) << @intCast(l)) hc.lut[k] = entry;
                code += 1;
                idx += 1;
            }
            code <<= 1;
        }
    }

    inline fn decode(hc: *const HCode, br: *BitReader) u16 {
        if (hc.single) |s| return s;
        if (br.nbits < 32) br.fill();
        const e = hc.lut[@intCast(br.buf & 255)];
        if (e & 15 != 0) {
            const l: u5 = @intCast(e & 15);
            br.buf >>= l;
            br.nbits -= l;
            return e >> 4;
        }
        return hc.decodeSlow(br);
    }

    fn decodeSlow(hc: *const HCode, br: *BitReader) u16 {
        var code: i32 = 0;
        var first: i32 = 0;
        var index: i32 = 0;
        for (1..16) |l| {
            code |= @intCast(br.read(1));
            const cnt: i32 = hc.count[l];
            if (code - cnt < first) {
                const k: usize = @intCast(index + (code - first));
                return if (k < hc.syms.len) hc.syms[k] else 0;
            }
            index += cnt;
            first += cnt;
            first <<= 1;
            code <<= 1;
        }
        return 0; // unreachable for complete codes; harmless
    }
};

const code_length_order = [19]u8{ 17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };

fn readCode(hc: *HCode, arena: std.mem.Allocator, br: *BitReader, alphabet: usize, lens: []u8) Error!void {
    const l = lens[0..alphabet];
    @memset(l, 0);
    if (br.read(1) == 1) {
        const n = br.read(1) + 1;
        const first8 = br.read(1);
        const s0 = br.read(if (first8 == 1) 8 else 1);
        if (s0 >= alphabet) return error.InvalidData;
        l[s0] = 1;
        if (n == 2) {
            const s1 = br.read(8);
            if (s1 >= alphabet) return error.InvalidData;
            l[s1] = 1;
        }
        // A simple code with two equal symbols degenerates into a single-symbol code.
        return hc.build(arena, l);
    }
    var cl_lens: [19]u8 = @splat(0);
    const ncl = br.read(4) + 4;
    for (0..ncl) |i| cl_lens[code_length_order[i]] = @intCast(br.read(3));
    var clc: HCode = undefined;
    try clc.build(arena, &cl_lens);
    var max_symbol: usize = alphabet;
    if (br.read(1) == 1) {
        const nb: u5 = @intCast(2 + 2 * br.read(3));
        max_symbol = 2 + br.read(nb);
        if (max_symbol > alphabet) return error.InvalidData;
    }
    var sym: usize = 0;
    var prev: u8 = 8;
    while (sym < alphabet) {
        if (max_symbol == 0) break;
        max_symbol -= 1;
        const c = clc.decode(br);
        if (c < 16) {
            l[sym] = @intCast(c);
            sym += 1;
            if (c != 0) prev = @intCast(c);
        } else {
            const rep: usize, const val: u8 = switch (c) {
                16 => .{ 3 + br.read(2), prev },
                17 => .{ 3 + br.read(3), 0 },
                else => .{ 11 + br.read(7), 0 },
            };
            if (sym + rep > alphabet) return error.InvalidData;
            @memset(l[sym .. sym + rep], val);
            sym += rep;
        }
        if (br.overrun()) return error.InvalidData;
    }
    return hc.build(arena, l);
}

const Group = [5]HCode;

// ---------------------------------------------------------------------------------------------

inline fn subSize(size: u32, bits: u5) u32 {
    return @intCast((@as(u64, size) + (@as(u64, 1) << bits) - 1) >> bits);
}

inline fn prefixValue(br: *BitReader, sym: u32) u32 {
    if (sym < 4) return sym + 1;
    const extra: u5 = @intCast((sym - 2) >> 1);
    const offset = (2 + (sym & 1)) << extra;
    return offset + br.read(extra) + 1;
}

const Dec = struct {
    arena: std.mem.Allocator,
    br: BitReader,
    lens: []u8,

    /// Decodes one entropy-coded image of xs*ys pixels into `out`.
    fn imageData(d: *Dec, xs: u32, ys: u32, out: []u32, level0: bool) Error!void {
        const br = &d.br;
        var cache_bits: u5 = 0;
        if (br.read(1) == 1) {
            const b = br.read(4);
            if (b < 1 or b > 11) return error.InvalidData;
            cache_bits = @intCast(b);
        }
        const cache_size: u32 = if (cache_bits > 0) @as(u32, 1) << cache_bits else 0;
        var meta: []u32 = &.{};
        var meta_bits: u5 = 0;
        var meta_w: u32 = 0;
        var groups: []Group = undefined;
        if (level0 and br.read(1) == 1) {
            meta_bits = @intCast(br.read(3) + 2);
            meta_w = subSize(xs, meta_bits);
            const mh = subSize(ys, meta_bits);
            meta = try d.arena.alloc(u32, @as(usize, meta_w) * mh);
            try d.imageData(meta_w, mh, meta, false);
            // Remap used group ids densely.
            const remap = try d.arena.alloc(u32, 65536);
            @memset(remap, std.math.maxInt(u32));
            var max_id: u32 = 0;
            var used: u32 = 0;
            for (meta) |*m| {
                const id = (m.* >> 8) & 0xffff;
                if (remap[id] == std.math.maxInt(u32)) {
                    remap[id] = used;
                    used += 1;
                }
                max_id = @max(max_id, id);
                m.* = remap[id];
            }
            groups = try d.arena.alloc(Group, used);
            var scratch: Group = undefined;
            var gid: u32 = 0;
            while (gid <= max_id) : (gid += 1) {
                const g: *Group = if (remap[gid] != std.math.maxInt(u32)) &groups[remap[gid]] else &scratch;
                try d.readGroup(g, cache_size);
            }
        } else {
            groups = try d.arena.alloc(Group, 1);
            try d.readGroup(&groups[0], cache_size);
        }

        var cache: []u32 = &.{};
        if (cache_size > 0) {
            cache = try d.arena.alloc(u32, cache_size);
            @memset(cache, 0);
        }
        const cache_shift: u5 = if (cache_bits > 0) @intCast(32 - @as(u32, cache_bits)) else 0;
        const n: usize = @as(usize, xs) * ys;
        if (out.len < n) return error.InvalidData;
        var pos: usize = 0;
        var x: u32 = 0;
        var y: u32 = 0;
        const mask: u32 = if (meta.len > 0) (@as(u32, 1) << meta_bits) - 1 else 0;
        var g: *const Group = &groups[0];
        var cached_upto: usize = 0; // pixels below this index have been inserted in the cache
        while (pos < n) {
            if (meta.len > 0 and (x & mask) == 0) g = &groups[meta[(y >> meta_bits) * meta_w + (x >> meta_bits)]];
            const s = g[0].decode(br);
            if (s < 256) {
                const r = g[1].decode(br);
                const b = g[2].decode(br);
                const a = g[3].decode(br);
                out[pos] = (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, s) << 8) | b;
                pos += 1;
                x += 1;
                if (x == xs) {
                    x = 0;
                    y += 1;
                    if (br.overrun()) return error.InvalidData;
                }
            } else if (s < 256 + 24) {
                const len = prefixValue(br, s - 256);
                const ds = g[4].decode(br);
                if (ds >= 40) return error.InvalidData;
                const dcode = prefixValue(br, ds);
                var dist: usize = undefined;
                if (dcode > 120) {
                    dist = dcode - 120;
                } else {
                    const p = code_to_plane[dcode - 1];
                    const yo: i64 = p >> 4;
                    const xo: i64 = 8 - @as(i64, p & 15);
                    const dd = yo * xs + xo;
                    dist = if (dd < 1) 1 else @intCast(dd);
                }
                if (dist > pos or len > n - pos) return error.InvalidData;
                var i: usize = 0;
                if (dist == 1) {
                    @memset(out[pos .. pos + len], out[pos - 1]);
                } else if (dist >= len) {
                    @memcpy(out[pos .. pos + len], out[pos - dist .. pos - dist + len]);
                } else while (i < len) : (i += 1) out[pos + i] = out[pos + i - dist];
                pos += len;
                x += len % xs;
                y += @intCast(len / xs);
                if (x >= xs) {
                    x -= xs;
                    y += 1;
                }
                if (br.overrun()) return error.InvalidData;
                if (meta.len > 0 and pos < n) g = &groups[meta[(y >> meta_bits) * meta_w + (x >> meta_bits)]];
            } else {
                const idx = s - 280;
                if (idx >= cache_size) return error.InvalidData;
                // bring cache up to date first
                cacheFill(cache, cache_shift, out[cached_upto..pos]);
                cached_upto = pos;
                out[pos] = cache[idx];
                pos += 1;
                x += 1;
                if (x == xs) {
                    x = 0;
                    y += 1;
                }
            }
            if (cache_size > 0 and s < 256 + 24) {
                cacheFill(cache, cache_shift, out[cached_upto..pos]);
                cached_upto = pos;
            }
        }
        if (br.overrun()) return error.InvalidData;
    }

    fn readGroup(d: *Dec, g: *Group, cache_size: u32) Error!void {
        const alpha = [5]usize{ 256 + 24 + cache_size, 256, 256, 256, 40 };
        for (0..5) |i| try readCode(&g[i], d.arena, &d.br, alpha[i], d.lens);
    }
};

const Transform = struct {
    kind: u2,
    bits: u5 = 0,
    data: []u32 = &.{},
    xs: u32 = 0, // image width when this transform was read (before packing)
};

pub fn decodeVp8l(alloc: std.mem.Allocator, body: []const u8, limits: Limits) Error!Image {
    if (body.len < 5 or body[0] != 0x2f) return error.InvalidData;
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var d = Dec{ .arena = arena, .br = .{ .data = body[1..] }, .lens = undefined };
    d.lens = try arena.alloc(u8, 256 + 24 + 2048);
    const br = &d.br;
    const w = br.read(14) + 1;
    const h = br.read(14) + 1;
    _ = br.read(1); // alpha hint
    if (br.read(3) != 0) return error.InvalidData;
    const nbytes = try types.checkSize(w, h, limits);
    const px = try decodeArgb(&d, w, h);
    const out = try alloc.alloc(u8, nbytes);
    toRgba(px, out);
    return .{ .width = w, .height = h, .data = out };
}

/// Decodes the VP8L-compressed alpha plane of an `ALPH` chunk (`data` = bytes after the
/// 1-byte ALPH header): a headerless VP8L image stream whose green channel holds the
/// (still filtered) alpha values. Writes `w*h` bytes to `out`. Caller bounds `w*h`.
pub fn decodeAlphaStream(alloc: std.mem.Allocator, data: []const u8, w: u32, h: u32, out: []u8) Error!void {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var d = Dec{ .arena = arena, .br = .{ .data = data }, .lens = undefined };
    d.lens = try arena.alloc(u8, 256 + 24 + 2048);
    const px = try decodeArgb(&d, w, h);
    if (px.len < out.len) return error.InvalidData;
    for (out, px[0..out.len]) |*o, p| o.* = @truncate(p >> 8);
}

/// Decodes a VP8L image stream (transforms + entropy-coded pixels, no header) of `w`x`h`
/// pixels to ARGB allocated from `d.arena`. Caller must have bounded `w*h`.
fn decodeArgb(d: *Dec, w: u32, h: u32) Error![]u32 {
    const arena = d.arena;
    const br = &d.br;
    const npx = @as(usize, w) * h;

    var transforms: [4]Transform = undefined;
    var nt: usize = 0;
    var seen: u4 = 0;
    var xs: u32 = w;
    while (br.read(1) == 1) {
        const kind: u2 = @intCast(br.read(2));
        const bit = @as(u4, 1) << kind;
        if (seen & bit != 0) return error.InvalidData;
        seen |= bit;
        var t = Transform{ .kind = kind, .xs = xs };
        switch (kind) {
            0, 1 => {
                t.bits = @intCast(br.read(3) + 2);
                const sw = subSize(xs, t.bits);
                const sh = subSize(h, t.bits);
                t.data = try arena.alloc(u32, @as(usize, sw) * sh);
                try d.imageData(sw, sh, t.data, false);
            },
            2 => {},
            3 => {
                const size = br.read(8) + 1;
                t.data = try arena.alloc(u32, 256);
                @memset(t.data, 0);
                try d.imageData(size, 1, t.data, false);
                var i: usize = 1;
                while (i < size) : (i += 1) t.data[i] = addPixels(t.data[i], t.data[i - 1]);
                t.bits = if (size <= 2) 3 else if (size <= 4) 2 else if (size <= 16) 1 else 0;
                xs = subSize(xs, t.bits);
            },
        }
        transforms[nt] = t;
        nt += 1;
    }
    const px = try arena.alloc(u32, npx);
    try d.imageData(xs, h, px, true);

    // Inverse transforms in reverse order.
    var ti = nt;
    while (ti > 0) {
        ti -= 1;
        const t = transforms[ti];
        switch (t.kind) {
            0 => inversePredict(px, t.xs, h, t.bits, t.data),
            1 => inverseColor(px, t.xs, h, t.bits, t.data),
            2 => addGreen(px[0 .. @as(usize, t.xs) * h]),
            3 => unbundle(px, t.xs, h, t.bits, t.data),
        }
    }
    return px;
}

// ---------------------------------------------------------------------------------------------
// Pixel arithmetic shared with the encoder.

/// Per-byte (per ARGB channel) wrapping add / subtract, SWAR on u32.
pub inline fn addPixels(a: u32, b: u32) u32 {
    const ag = (a & 0xff00ff00) +% (b & 0xff00ff00);
    const rb = (a & 0x00ff00ff) +% (b & 0x00ff00ff);
    return (ag & 0xff00ff00) | (rb & 0x00ff00ff);
}
pub inline fn subPixels(a: u32, b: u32) u32 {
    const ag = ((a | 0x00ff00ff) -% (b & 0xff00ff00)) & 0xff00ff00;
    const rb = ((a | 0xff00ff00) -% (b & 0x00ff00ff)) & 0x00ff00ff;
    return ag | rb;
}

/// Predictors on N bytes = N/4 pixels at once (N = 4 for one pixel, 16 for four).
/// Only u8 saturating/wrapping ops, which map 1:1 onto wasm simd128.
pub fn Px(comptime N: usize) type {
    return struct {
        pub const V = @Vector(N, u8);
        const P = @Vector(N / 4, u32);
        inline fn avg2(a: V, b: V) V {
            return (a & b) +% ((a ^ b) >> @splat(1));
        }
        inline fn absdiff(a: V, b: V) V {
            return (a -| b) | (b -| a);
        }
        /// Sum of the 4 bytes of each pixel.
        inline fn hsum(v: V) P {
            const x: P = @bitCast(v);
            const s = (x & @as(P, @splat(0x00ff00ff))) + ((x >> @splat(8)) & @as(P, @splat(0x00ff00ff)));
            return (s + (s >> @splat(16))) & @as(P, @splat(0xffff));
        }
        inline fn sel(l: V, t: V, tl: V) V {
            const pl = hsum(absdiff(t, tl));
            const pt = hsum(absdiff(l, tl));
            return @bitCast(@select(u32, pl < pt, @as(P, @bitCast(l)), @as(P, @bitCast(t))));
        }
        /// clamp(a + b - c) per channel
        inline fn clampFull(a: V, b: V, c: V) V {
            return (a +| (b -| c)) -| (c -| b);
        }
        /// clamp(a + (a - b) / 2) per channel, division truncating toward zero
        inline fn clampHalf(a: V, b: V) V {
            return (a +| ((a -| b) >> @splat(1))) -| ((b -| a) >> @splat(1));
        }
        pub inline fn predict(comptime mode: u4, l: V, t: V, tl: V, tr: V) V {
            return switch (mode) {
                1 => l,
                2 => t,
                3 => tr,
                4 => tl,
                5 => avg2(avg2(l, tr), t),
                6 => avg2(l, tl),
                7 => avg2(l, t),
                8 => avg2(tl, t),
                9 => avg2(t, tr),
                10 => avg2(avg2(l, tl), avg2(t, tr)),
                11 => sel(l, t, tl),
                12 => clampFull(l, t, tl),
                13 => clampHalf(avg2(l, t), tl),
                else => @bitCast(@as(P, @splat(0xff000000))),
            };
        }
        /// Runtime-mode version (one out-of-line copy of each predictor; keeps code small).
        pub fn predictAny(mode: u4, l: V, t: V, tl: V, tr: V) V {
            return switch (mode) {
                inline else => |m| @This().predict(m, l, t, tl, tr),
            };
        }
    };
}

/// VP8L predictor `mode` (runtime) for one pixel.
inline fn avg2s(a: u32, b: u32) u32 {
    return (((a ^ b) & 0xfefefefe) >> 1) + (a & b);
}
inline fn ch(v: u32, comptime k: u5) i32 {
    return @intCast((v >> k) & 0xff);
}
inline fn clamp255(v: i32) u32 {
    return @intCast(@min(@max(v, 0), 255));
}
fn selS(l: u32, t: u32, tl: u32) u32 {
    var pl: i32 = 0;
    var pt: i32 = 0;
    inline for (.{ 0, 8, 16, 24 }) |k| {
        pl += @intCast(@abs(ch(t, k) - ch(tl, k)));
        pt += @intCast(@abs(ch(l, k) - ch(tl, k)));
    }
    return if (pl < pt) l else t;
}
fn clampFullS(a: u32, b: u32, c: u32) u32 {
    var r: u32 = 0;
    inline for (.{ 0, 8, 16, 24 }) |k| r |= clamp255(ch(a, k) + ch(b, k) - ch(c, k)) << k;
    return r;
}
fn clampHalfS(a: u32, b: u32) u32 {
    var r: u32 = 0;
    inline for (.{ 0, 8, 16, 24 }) |k| r |= clamp255(ch(a, k) + @divTrunc(ch(a, k) - ch(b, k), 2)) << k;
    return r;
}

/// VP8L predictor `mode` (runtime) for one pixel, scalar SWAR (fast in wasm).
pub fn predictPx(mode: u4, l: u32, t: u32, tl: u32, tr: u32) u32 {
    return switch (mode) {
        inline else => |m| predictS(m, l, t, tl, tr),
    };
}

/// Comptime-mode scalar predictor.
pub inline fn predictS(comptime mode: u4, l: u32, t: u32, tl: u32, tr: u32) u32 {
    return switch (mode) {
        1 => l,
        2 => t,
        3 => tr,
        4 => tl,
        5 => avg2s(avg2s(l, tr), t),
        6 => avg2s(l, tl),
        7 => avg2s(l, t),
        8 => avg2s(tl, t),
        9 => avg2s(t, tr),
        10 => avg2s(avg2s(l, tl), avg2s(t, tr)),
        11 => selS(l, t, tl),
        12 => clampFullS(l, t, tl),
        13 => clampHalfS(avg2s(l, t), tl),
        else => 0xff000000,
    };
}

fn inversePredict(px: []u32, w: u32, h: u32, bits: u5, modes: []const u32) void {
    if (w == 0 or h == 0) return;
    px[0] = addPixels(px[0], 0xff000000);
    var x: usize = 1;
    while (x < w) : (x += 1) px[x] = addPixels(px[x], px[x - 1]);
    const tw = subSize(w, bits);
    var y: usize = 1;
    while (y < h) : (y += 1) {
        const row = y * w;
        px[row] = addPixels(px[row], px[row - w]);
        const mrow = modes[(y >> bits) * tw ..];
        x = 1;
        while (x < w) {
            const mode: u4 = @truncate(mrow[x >> bits] >> 8);
            const xend = @min(w, ((x >> bits) + 1) << bits);
            switch (mode) {
                1 => while (x < xend) : (x += 1) {
                    px[row + x] = addPixels(px[row + x], px[row + x - 1]);
                },
                // Modes that only read the row above: four pixels per simd vector.
                2, 3, 4, 8, 9 => {
                    const X = Px(16);
                    while (x + 4 <= xend) : (x += 4) {
                        const i = row + x;
                        const ld = struct {
                            inline fn f(p: []u32, k: usize) X.V {
                                return @as(*align(4) const X.V, @ptrCast(p.ptr + k)).*;
                            }
                        }.f;
                        const r = ld(px, i) +% X.predictAny(mode, undefined, ld(px, i - w), ld(px, i - w - 1), ld(px, i - w + 1));
                        @as(*align(4) X.V, @ptrCast(px.ptr + i)).* = r;
                    }
                    while (x < xend) : (x += 1) {
                        const i = row + x;
                        px[i] = addPixels(px[i], predictPx(mode, px[i - 1], px[i - w], px[i - w - 1], px[i - w + 1]));
                    }
                },
                inline 5, 6, 7, 10, 11, 12, 13 => |m| while (x < xend) : (x += 1) {
                    const i = row + x;
                    px[i] = addPixels(px[i], predictS(m, px[i - 1], px[i - w], px[i - w - 1], px[i - w + 1]));
                },
                else => while (x < xend) : (x += 1) {
                    const i = row + x;
                    px[i] = addPixels(px[i], predictPx(mode, px[i - 1], px[i - w], px[i - w - 1], px[i - w + 1]));
                },
            }
        }
    }
}

inline fn ctDelta(t: u8, c: u8) u8 {
    return @truncate(@as(u32, @bitCast((@as(i32, @as(i8, @bitCast(t))) * @as(i8, @bitCast(c))) >> 5)));
}

fn inverseColor(px: []u32, w: u32, h: u32, bits: u5, data: []const u32) void {
    const tw = subSize(w, bits);
    var y: usize = 0;
    while (y < h) : (y += 1) {
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const e = data[(y >> bits) * tw + (x >> bits)];
            const g2r: u8 = @truncate(e);
            const g2b: u8 = @truncate(e >> 8);
            const r2b: u8 = @truncate(e >> 16);
            const p = &px[y * w + x];
            const g: u8 = @truncate(p.* >> 8);
            const r: u8 = @as(u8, @truncate(p.* >> 16)) +% ctDelta(g2r, g);
            const b: u8 = @as(u8, @truncate(p.*)) +% ctDelta(g2b, g) +% ctDelta(r2b, r);
            p.* = (p.* & 0xff00ff00) | (@as(u32, r) << 16) | b;
        }
    }
}

/// In-place color-index expansion; `px` holds the packed image (width subSize(w,bits)) at
/// its start and receives the full w*h image. Processed back to front so no source is
/// overwritten before it is read.
fn unbundle(px: []u32, w: u32, h: u32, bits: u5, pal: []const u32) void {
    const pw = subSize(w, bits);
    const bpp: u5 = @intCast(@as(u32, 8) >> bits);
    const m: u32 = (@as(u32, 1) << bpp) - 1;
    var y: usize = h;
    while (y > 0) {
        y -= 1;
        var x: usize = w;
        while (x > 0) {
            x -= 1;
            const packed_px = px[y * pw + (x >> bits)];
            const sh: u5 = @intCast((x & ((@as(usize, 1) << bits) - 1)) * bpp);
            const idx = ((packed_px >> 8) >> sh) & m;
            px[y * w + x] = pal[idx]; // pal has 256 entries; out-of-range -> 0
        }
    }
}

// ---------------------------------------------------------------------------------------------

test "decode takumi lossless webp" {
    const bytes = @embedFile("testdata/webp_takumi.webp");
    const raw = @embedFile("testdata/webp_takumi.rgba");
    const img = try decode(std.testing.allocator, bytes, .{});
    defer img.deinit(std.testing.allocator);
    const dims = dimensions(bytes).?;
    try std.testing.expectEqual(dims[0], img.width);
    try std.testing.expectEqual(dims[1], img.height);
    try std.testing.expectEqualSlices(u8, raw, img.data);
}

test "fuzz: mutated / truncated / random inputs never crash" {
    const a = std.testing.allocator;
    const seeds = [_][]const u8{
        @embedFile("testdata/webp_takumi.webp"),
        @embedFile("testdata/webp_lib_photo.webp"),
        @embedFile("testdata/webp_lib_pal.webp"),
        @embedFile("testdata/webp_lib_pal2.webp"),
        @embedFile("testdata/webp_lib_mix.webp"),
    };
    var buf: [8192]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(7);
    const rnd = prng.random();
    var decoded: usize = 0;
    for (seeds) |base| {
        // every truncation point of the small seeds / a sample of the big one
        var cut: usize = 0;
        while (cut < base.len) : (cut += if (base.len > 1000) 7 else 1) {
            if (decode(a, base[0..cut], .{ .max_pixels = 1 << 20 })) |img| img.deinit(a) else |_| {}
        }
        for (0..2500) |i| {
            const n = @min(base.len, buf.len);
            @memcpy(buf[0..n], base[0..n]);
            const nmut = 1 + rnd.uintLessThan(usize, 6);
            for (0..nmut) |_| {
                const p = 12 + rnd.uintLessThan(usize, n - 12);
                if (rnd.boolean()) buf[p] ^= @as(u8, 1) << rnd.int(u3) else buf[p] = rnd.int(u8);
            }
            const len = if (i % 5 == 0) rnd.uintLessThan(usize, n) else n;
            if (decode(a, buf[0..len], .{ .max_pixels = 1 << 20 })) |img| {
                decoded += 1;
                img.deinit(a);
            } else |_| {}
        }
    }
    // Valid container + VP8L header, random payload.
    for (0..3000) |_| {
        const n = 30 + rnd.uintLessThan(usize, 600);
        rnd.bytes(buf[0..n]);
        @memcpy(buf[0..4], "RIFF");
        std.mem.writeInt(u32, buf[4..8], @intCast(n - 8), .little);
        @memcpy(buf[8..16], "WEBPVP8L");
        std.mem.writeInt(u32, buf[16..20], @intCast(n - 20), .little);
        buf[20] = 0x2f;
        buf[24] &= 0x1f; // version 0
        if (decode(a, buf[0..n], .{ .max_pixels = 1 << 20 })) |img| img.deinit(a) else |_| {}
    }
    try std.testing.expect(decoded > 0);
}

test "decode libwebp lossless files (cache, meta codes, cross-color, palette)" {
    const names = .{ "photo", "pal", "pal2", "mix" };
    inline for (names) |nm| {
        const bytes = @embedFile("testdata/webp_lib_" ++ nm ++ ".webp");
        const raw = @embedFile("testdata/webp_lib_" ++ nm ++ ".rgba");
        const img = try decode(std.testing.allocator, bytes, .{});
        defer img.deinit(std.testing.allocator);
        std.testing.expectEqualSlices(u8, raw, img.data) catch |e| {
            std.debug.print("mismatch in {s}\n", .{nm});
            return e;
        };
    }
}

/// Inserts `src` pixels into the color cache, skipping immediate repeats (their slot
/// already holds that value).
fn cacheFill(cache: []u32, shift: u5, src: []const u32) void {
    if (src.len == 0) return;
    var last: u32 = ~src[0];
    for (src) |v| {
        if (v == last) continue;
        last = v;
        cache[(0x1e35a7bd *% v) >> shift] = v;
    }
}

test "scalar and simd predictors agree" {
    var prng = std.Random.DefaultPrng.init(9);
    const r = prng.random();
    const X = Px(16);
    for (0..20000) |_| {
        var v: [4][4]u32 = undefined;
        for (&v) |*a| for (a) |*e| {
            e.* = r.int(u32);
        };
        const mode: u4 = r.uintLessThan(u4, 14);
        const got: [4]u32 = @bitCast(X.predictAny(mode, @bitCast(v[0]), @bitCast(v[1]), @bitCast(v[2]), @bitCast(v[3])));
        for (0..4) |k| try std.testing.expectEqual(predictPx(mode, v[0][k], v[1][k], v[2][k], v[3][k]), got[k]);
    }
}

const U4 = @Vector(4, u32);

fn addGreen(px: []u32) void {
    var i: usize = 0;
    while (i + 4 <= px.len) : (i += 4) {
        const p = @as(*align(4) U4, @ptrCast(px.ptr + i));
        const v = p.*;
        const g = (v >> @splat(8)) & @as(U4, @splat(0xff));
        p.* = (v & @as(U4, @splat(0xff00ff00))) | ((v +% (g << @splat(16))) & @as(U4, @splat(0x00ff0000))) | ((v +% g) & @as(U4, @splat(0xff)));
    }
    for (px[i..]) |*p| {
        const g = (p.* >> 8) & 0xff;
        p.* = (p.* & 0xff00ff00) | ((p.* +% (g << 16)) & 0x00ff0000) | ((p.* +% g) & 0xff);
    }
}

/// ARGB u32 -> RGBA bytes.
fn toRgba(px: []const u32, out: []u8) void {
    const dst32: [*]align(1) u32 = @ptrCast(out.ptr);
    var i: usize = 0;
    if (@import("builtin").cpu.arch.endian() == .little) {
        while (i + 4 <= px.len) : (i += 4) {
            const v = @as(*align(4) const U4, @ptrCast(px.ptr + i)).*;
            @as(*align(1) U4, @ptrCast(dst32 + i)).* = (v & @as(U4, @splat(0xff00ff00))) | ((v >> @splat(16)) & @as(U4, @splat(0xff))) | ((v & @as(U4, @splat(0xff))) << @splat(16));
        }
    }
    while (i < px.len) : (i += 1) {
        const p = px[i];
        dst32[i] = std.mem.nativeToLittle(u32, (p & 0xff00ff00) | ((p >> 16) & 0xff) | ((p & 0xff) << 16));
    }
}
