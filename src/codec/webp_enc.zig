//! Lossless WebP (VP8L) encoder.
//!
//! Pipeline: palette (color-indexing transform with pixel bundling) when the image has
//! <= 256 colors, otherwise subtract-green + per-tile predictor transform (mode picked by
//! a sum-of-abs-residual heuristic). Then LZ77 over ARGB pixels (left/up candidates +
//! hash chains in a 64K-pixel window, VP8L 2D distance codes), a color cache, and one set
//! of 5 canonical Huffman codes (length-limited to 15). Output: RIFF/WEBP/VP8L.
//! All memory comes from `alloc`; temporaries are freed before return; the returned
//! slice is owned by the caller.
const std = @import("std");
const huffman = @import("huffman.zig");
const dec = @import("webp_dec.zig");

pub const Options = struct {
    /// 0 = fastest (predictor search on every 4th row, chain 4, 10-bit cache),
    /// 1 = default (every 2nd row, chain 16, 11-bit cache),
    /// 2 = slower/smaller (all rows, 16x16 tiles, chain 64, cache size chosen by entropy).
    effort: u2 = 1,
    /// Color cache size in bits (0 = off, 1..11); null = per `effort`.
    cache_bits: ?u4 = null,
};

pub const EncodeError = error{ OutOfMemory, InvalidInput };

/// Encodes straight-alpha RGBA8 to a lossless WebP file.
pub fn encodeLossless(alloc: std.mem.Allocator, straight_rgba: []const u8, width: u32, height: u32, opts: Options) EncodeError![]u8 {
    if (width == 0 or height == 0 or width > 16384 or height > 16384) return error.InvalidInput;
    const n: usize = @as(usize, width) * height;
    if (straight_rgba.len != n * 4) return error.InvalidInput;

    const argb = try alloc.alloc(u32, n);
    defer alloc.free(argb);
    // NB: plain *align(1) loads; `slice[i..][0..4].*` lowers to a memcpy call under -Oz (wasm).
    const src32: [*]align(1) const u32 = @ptrCast(straight_rgba.ptr);
    var alpha_and: u32 = 0xff000000;
    for (argb, 0..) |*p, i| {
        const s = std.mem.littleToNative(u32, src32[i]); // A B G R
        alpha_and &= s;
        p.* = (s & 0xff00ff00) | ((s >> 16) & 0xff) | ((s & 0xff) << 16);
    }
    alpha_and &= 0xff000000;

    var bw = BitWriter{ .alloc = alloc };
    defer bw.out.deinit(alloc);
    try bw.out.ensureTotalCapacity(alloc, 4096 + n / 4);
    try bw.out.appendSlice(alloc, "RIFF\x00\x00\x00\x00WEBPVP8L\x00\x00\x00\x00\x2f");
    try bw.put(width - 1, 14);
    try bw.put(height - 1, 14);
    try bw.put(@intFromBool(alpha_and != 0xff000000), 1);
    try bw.put(0, 3);

    var enc = Enc{ .alloc = alloc, .bw = &bw, .opts = opts };
    var main_px: []u32 = argb;
    var main_w: u32 = width;
    var packed_buf: []u32 = &.{};
    defer if (packed_buf.len > 0) alloc.free(packed_buf);

    var pal: [256]u32 = undefined;
    if (findPalette(argb, &pal)) |pal_size| {
        // Color-indexing transform.
        const palette = pal[0..pal_size];
        sortU32(palette);
        const bits: u5 = if (pal_size <= 2) 3 else if (pal_size <= 4) 2 else if (pal_size <= 16) 1 else 0;
        try bw.put(1, 1);
        try bw.put(3, 2);
        try bw.put(@intCast(pal_size - 1), 8);
        var delta: [256]u32 = undefined;
        delta[0] = palette[0];
        for (1..pal_size) |i| delta[i] = dec.subPixels(palette[i], palette[i - 1]);
        try enc.writeImage(delta[0..pal_size], @intCast(pal_size), 1, false);

        const pw: u32 = @intCast((@as(u64, width) + (@as(u64, 1) << bits) - 1) >> bits);
        packed_buf = try alloc.alloc(u32, @as(usize, pw) * height);
        var lut = ColorLut.init(palette);
        const bpp: u5 = @intCast(@as(u32, 8) >> bits);
        const per: u32 = @as(u32, 1) << bits;
        var y: usize = 0;
        while (y < height) : (y += 1) {
            const row = argb[y * width ..][0..width];
            var px: usize = 0;
            while (px < pw) : (px += 1) {
                var v: u32 = 0;
                var k: u32 = 0;
                while (k < per) : (k += 1) {
                    const x = px * per + k;
                    if (x >= width) break;
                    v |= lut.get(row[x]) << @intCast(k * bpp);
                }
                packed_buf[y * pw + px] = 0xff000000 | (v << 8);
            }
        }
        main_px = packed_buf;
        main_w = pw;
    } else {
        // Subtract green.
        for (argb) |*p| {
            const g = (p.* >> 8) & 0xff;
            p.* = (p.* & 0xff00ff00) | ((p.* -% (g << 16)) & 0x00ff0000) | ((p.* -% g) & 0xff);
        }
        try bw.put(1, 1);
        try bw.put(2, 2);
        // Predictor.
        const tb: u5 = if (opts.effort >= 2) 4 else 5;
        const tw: u32 = (width + (@as(u32, 1) << tb) - 1) >> tb;
        const th: u32 = (height + (@as(u32, 1) << tb) - 1) >> tb;
        const modes = try alloc.alloc(u32, @as(usize, tw) * th);
        defer alloc.free(modes);
        chooseModes(argb, width, height, tb, tw, modes, @max(1, @as(u32, 4) >> opts.effort));
        applyPredictor(argb, width, height, tb, tw, modes);
        try bw.put(1, 1);
        try bw.put(0, 2);
        try bw.put(tb - 2, 3);
        try enc.writeImage(modes, tw, th, false);
    }
    try bw.put(0, 1); // no more transforms
    try enc.writeImage(main_px, main_w, height, true);
    try bw.flushAll();

    var out = bw.out;
    bw.out = .empty;
    if (out.items.len & 1 == 1) try out.append(alloc, 0);
    const total: u32 = @intCast(out.items.len);
    std.mem.writeInt(u32, out.items[4..8], total - 8, .little);
    // VP8L chunk size excludes the pad byte.
    const payload: u32 = total - 20 - @as(u32, @intFromBool((bw.byte_len & 1) == 1));
    std.mem.writeInt(u32, out.items[16..20], payload, .little);
    return out.toOwnedSlice(alloc);
}

// ---------------------------------------------------------------------------------------------

const BitWriter = struct {
    alloc: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    acc: u64 = 0,
    n: u6 = 0,
    byte_len: usize = 0, // set by flushAll: unpadded length

    fn put(bw: *BitWriter, v: u32, nbits: u5) !void {
        bw.acc |= @as(u64, v) << bw.n;
        bw.n += nbits;
        if (bw.n >= 32) {
            try bw.out.ensureUnusedCapacity(bw.alloc, 4);
            const len = bw.out.items.len;
            bw.out.items.len = len + 4;
            @as(*align(1) u32, @ptrCast(bw.out.items.ptr + len)).* = std.mem.nativeToLittle(u32, @truncate(bw.acc));
            bw.acc >>= 32;
            bw.n -= 32;
        }
    }
    fn flushAll(bw: *BitWriter) !void {
        while (bw.n > 0) {
            try bw.out.append(bw.alloc, @truncate(bw.acc));
            bw.acc >>= 8;
            bw.n -|= 8;
        }
        bw.byte_len = bw.out.items.len;
    }
};

// ---------------------------------------------------------------------------------------------
// Palette detection.

const ColorLut = struct {
    keys: [1024]u32 = undefined,
    vals: [1024]u16 = @splat(0), // index+1, 0 = empty

    fn slot(k: u32) usize {
        return (k *% 0x9E3779B1) >> 22;
    }
    fn init(pal: []const u32) ColorLut {
        var l = ColorLut{};
        for (pal, 0..) |c, i| _ = l.insert(c, @intCast(i));
        return l;
    }
    fn insert(l: *ColorLut, k: u32, idx: u16) bool {
        var s = slot(k);
        while (true) : (s = (s + 1) & 1023) {
            if (l.vals[s] == 0) {
                l.keys[s] = k;
                l.vals[s] = idx + 1;
                return true;
            }
            if (l.keys[s] == k) return false;
        }
    }
    fn get(l: *const ColorLut, k: u32) u32 {
        var s = slot(k);
        while (true) : (s = (s + 1) & 1023) {
            if (l.vals[s] == 0) return 0;
            if (l.keys[s] == k) return l.vals[s] - 1;
        }
    }
};

/// Insertion sort (palettes have <= 256 entries; avoids pulling in std.sort code).
fn sortU32(a: []u32) void {
    var i: usize = 1;
    while (i < a.len) : (i += 1) {
        const v = a[i];
        var j = i;
        while (j > 0 and a[j - 1] > v) : (j -= 1) a[j] = a[j - 1];
        a[j] = v;
    }
}

fn findPalette(px: []const u32, pal: *[256]u32) ?usize {
    var l = ColorLut{};
    var count: usize = 0;
    var last: u32 = px[0] +% 1;
    for (px) |p| {
        if (p == last) continue;
        last = p;
        var s = ColorLut.slot(p);
        while (true) : (s = (s + 1) & 1023) {
            if (l.vals[s] == 0) {
                if (count == 256) return null;
                l.keys[s] = p;
                l.vals[s] = 1;
                pal[count] = p;
                count += 1;
                break;
            }
            if (l.keys[s] == p) break;
        }
    }
    return count;
}

// ---------------------------------------------------------------------------------------------
// Predictor transform.

const X4 = dec.Px(16); // four pixels per vector

const V16 = X4.V;

/// Candidate predictor modes (evaluated together; one instantiation keeps code small).
const mode_set = [_]u4{ 11, 1, 2, 12, 13, 7, 5, 10 };

inline fn load4(px: []const u32, i: usize) V16 {
    return @as(*align(4) const V16, @ptrCast(px.ptr + i)).*;
}

/// Picks, per tile, the mode with the least sum of |residual| over every `row_step`-th
/// row. All candidate modes are evaluated in one pass, four pixels per simd vector.
fn chooseModes(px: []const u32, w: u32, h: u32, tb: u5, tw: u32, modes: []u32, row_step: u32) void {
    const ts: u32 = @as(u32, 1) << tb;
    for (modes, 0..) |*m, ti| {
        const tx: u32 = @intCast(ti % tw);
        const ty: u32 = @intCast(ti / tw);
        const x0 = @max(tx * ts, 1);
        const y0 = @max(ty * ts, 1);
        const x1 = @min(w, (tx + 1) * ts);
        const y1 = @min(h, (ty + 1) * ts);
        var acc: [mode_set.len]@Vector(16, u16) = @splat(@splat(0));
        var y = y0;
        while (y < y1) : (y += row_step) {
            const row = @as(usize, y) * w;
            var x = x0;
            while (x + 4 <= x1) : (x += 4) {
                const i = row + x;
                const p = load4(px, i);
                const l = load4(px, i - 1);
                const t = load4(px, i - w);
                const tl = load4(px, i - w - 1);
                const tr = load4(px, i - w + 1);
                inline for (mode_set, 0..) |mode, k| {
                    const d: @Vector(16, i8) = @bitCast(p -% X4.predict(mode, l, t, tl, tr));
                    acc[k] += @as(@Vector(16, u16), @abs(d));
                }
            }
        }
        var best: usize = 0;
        var best_cost: u32 = std.math.maxInt(u32);
        for (acc, 0..) |a, k| {
            const total = @reduce(.Add, @as(@Vector(16, u32), a));
            if (total < best_cost) {
                best_cost = total;
                best = k;
            }
        }
        m.* = 0xff000000 | (@as(u32, mode_set[best]) << 8);
    }
}

/// Replaces pixels by residuals, in place, last pixel first (predictions read originals;
/// each 4-pixel chunk is loaded before it is stored, and its left neighbour is untouched).
fn applyPredictor(px: []u32, w: u32, h: u32, tb: u5, tw: u32, modes: []const u32) void {
    var y: usize = h;
    while (y > 1) {
        y -= 1;
        const row = y * w;
        const mrow = modes[(y >> tb) * tw ..];
        var x: usize = w;
        while (x > 1) {
            const xstart = @max((x - 1) >> tb << tb, 1);
            const mode: u4 = @truncate(mrow[(x - 1) >> tb] >> 8);
            while (x >= xstart + 4) {
                x -= 4;
                const i = row + x;
                const r = load4(px, i) -% X4.predictAny(mode, load4(px, i - 1), load4(px, i - w), load4(px, i - w - 1), load4(px, i - w + 1));
                @as(*align(4) V16, @ptrCast(px.ptr + i)).* = r;
            }
            while (x > xstart) {
                x -= 1;
                const i = row + x;
                px[i] = dec.subPixels(px[i], dec.predictPx(mode, px[i - 1], px[i - w], px[i - w - 1], px[i - w + 1]));
            }
        }
        px[row] = dec.subPixels(px[row], px[row - w]);
    }
    var x: usize = w;
    while (x > 1) {
        x -= 1;
        px[x] = dec.subPixels(px[x], px[x - 1]);
    }
    px[0] = dec.subPixels(px[0], 0xff000000);
}

// ---------------------------------------------------------------------------------------------
// LZ77 + entropy coding.

/// inverse of code_to_plane: [yoff][8 - xoff] -> code (1..120), 0 = none.
const plane_to_code: [8][16]u8 = blk: {
    var t: [8][16]u8 = @splat(@splat(0));
    for (dec.code_to_plane, 0..) |b, i| t[b >> 4][b & 15] = i + 1;
    break :blk t;
};

inline fn distCode(dist: u32, w: u32) u32 {
    const yo = dist / w;
    const xo = dist - yo * w;
    if (xo <= 8 and yo < 8) {
        const c = plane_to_code[yo][8 - xo];
        if (c != 0) return c;
    } else if (w - xo <= 7 and yo + 1 < 8) {
        const c = plane_to_code[yo + 1][8 + (w - xo)];
        if (c != 0) return c;
    }
    return dist + 120;
}

/// Prefix-coded value v>=1 -> (symbol, extra bit count, extra value).
fn prefixEncode(v: u32) struct { sym: u32, nb: u5, extra: u32 } {
    const n = v - 1;
    if (n < 4) return .{ .sym = n, .nb = 0, .extra = 0 };
    const hb: u5 = @intCast(31 - @clz(n));
    const second = (n >> (hb - 1)) & 1;
    const nb: u5 = hb - 1;
    return .{ .sym = 2 * @as(u32, hb) + second, .nb = nb, .extra = n & ((@as(u32, 1) << nb) - 1) };
}

/// Token: len == 0 => literal (pixel taken from the image), else copy of `len` with dist code.
const Tok = packed struct(u64) { len: u32, dcode: u32 };

const max_len = 4096;
/// LZ77 window (pixels); the hash chain is a ring buffer of this size.
const window_bits = 16;
const max_dist: u32 = (1 << window_bits) - 1;
const hash_bits = 16;

const Enc = struct {
    alloc: std.mem.Allocator,
    bw: *BitWriter,
    opts: Options,

    fn lz77(e: *Enc, px: []const u32, w: u32, toks: *std.ArrayList(Tok)) !void {
        const n = px.len;
        const head = try e.alloc.alloc(u32, 1 << hash_bits);
        defer e.alloc.free(head);
        @memset(head, std.math.maxInt(u32));
        const prev = try e.alloc.alloc(u32, 1 << window_bits);
        defer e.alloc.free(prev);
        const chain: u32 = switch (e.opts.effort) {
            0 => 4,
            1 => 16,
            else => 64,
        };
        // Positions inside a match that get indexed: all for short matches, else only the
        // first and last `skip_keep` (runs and repeated rows would flood the chains).
        const skip_thr: usize = if (e.opts.effort >= 2) 32 else 4;
        const skip_keep: usize = if (e.opts.effort >= 2) 8 else 2;
        const nice: u32 = switch (e.opts.effort) {
            0 => 64,
            1 => 256,
            else => 1024,
        };
        var i: usize = 0;
        while (i < n) {
            var best_len: usize = 0;
            var best_dist: usize = 0;
            const lim = @min(max_len, n - i);
            if (lim >= 2) {
                if (i >= 1) {
                    const l = matchLen(px, i, i - 1, lim);
                    best_len = l;
                    best_dist = 1;
                }
                if (i >= w and best_len < lim) {
                    const l = matchLen(px, i, i - w, lim);
                    if (l > best_len) {
                        best_len = l;
                        best_dist = w;
                    }
                }
                if (best_len < nice and best_len < lim) {
                    var cand = head[hash(px[i], px[i + 1])];
                    var depth = chain;
                    while (cand != std.math.maxInt(u32) and depth > 0) : (depth -= 1) {
                        const d = i - cand;
                        if (d > max_dist) break;
                        if (px[cand + best_len] == px[i + best_len]) {
                            const l = matchLen(px, i, cand, lim);
                            if (l > best_len) {
                                best_len = l;
                                best_dist = d;
                                if (l >= nice or l == lim) break;
                            }
                        }
                        cand = prev[cand & max_dist];
                    }
                }
            }
            const min_len: usize = if (best_dist == 1 or best_dist == w) 2 else 3;
            if (best_len >= min_len) {
                try toks.append(e.alloc, .{ .len = @intCast(best_len), .dcode = distCode(@intCast(best_dist), w) });
                const end = i + best_len;
                // Long matches: only index their first and last few positions (runs and
                // repeated rows would otherwise flood the chains with useless entries).
                const skip_from = if (best_len > skip_thr) i + skip_keep else end;
                const skip_to = if (best_len > skip_thr) end - skip_keep else end;
                while (i < end) : (i += 1) {
                    if (i == skip_from) i = skip_to;
                    if (i + 1 < n) {
                        const hsh = hash(px[i], px[i + 1]);
                        prev[i & max_dist] = head[hsh];
                        head[hsh] = @intCast(i);
                    }
                }
            } else {
                try toks.append(e.alloc, .{ .len = 0, .dcode = 0 });
                if (i + 1 < n) {
                    const hsh = hash(px[i], px[i + 1]);
                    prev[i & max_dist] = head[hsh];
                    head[hsh] = @intCast(i);
                }
                i += 1;
            }
        }
    }

    inline fn hash(a: u32, b: u32) u32 {
        return ((a *% 0x9E3779B1) ^ (b *% 0x85EBCA6B)) >> (32 - hash_bits);
    }

    fn matchLen(px: []const u32, a: usize, b: usize, lim: usize) usize {
        const V = @Vector(8, u32);
        var l: usize = 0;
        while (l + 8 <= lim) {
            const va = @as(*align(4) const V, @ptrCast(px.ptr + a + l)).*;
            const vb = @as(*align(4) const V, @ptrCast(px.ptr + b + l)).*;
            const ne: u8 = @bitCast(va != vb);
            if (ne != 0) return l + @ctz(ne);
            l += 8;
        }
        while (l < lim and px[a + l] == px[b + l]) l += 1;
        return l;
    }

    /// Simulates a color cache of each size in `cands` (0 = none) in one pass, builds the
    /// symbol histograms for each, and returns the index of the cheapest candidate with its
    /// histograms in `out`. Each literal token's `dcode` receives a bitmask of the
    /// candidates whose cache it hits, so emission needs no second replay.
    fn selectCache(e: *Enc, px: []const u32, toks: []Tok, cands: []const u4, out: *Histos) !usize {
        const nc = cands.len;
        const caches = try e.alloc.alloc(u32, nc << 11);
        defer e.alloc.free(caches);
        @memset(caches, 0);
        const hs = try e.alloc.alloc(Histos, nc);
        defer e.alloc.free(hs);
        for (hs) |*h| h.* = .{};
        var shifts: [16]u5 = undefined;
        var any_cache = false;
        for (cands, 0..) |cb, ci| {
            shifts[ci] = if (cb > 0) @intCast(32 - @as(u32, cb)) else 0;
            any_cache = any_cache or cb > 0;
        }
        out.* = .{};
        var pos: usize = 0;
        for (toks) |*t| {
            if (t.len == 0) {
                const v = px[pos];
                pos += 1;
                const m = 0x1e35a7bd *% v;
                var mask: u32 = 0;
                for (hs[0..nc], 0..) |*h, ci| {
                    if (cands[ci] != 0) {
                        const k = m >> shifts[ci];
                        const c = &caches[(ci << 11) + k];
                        if (c.* == v) {
                            h.g[280 + k] += 1;
                            mask |= @as(u32, 1) << @intCast(ci);
                            continue;
                        }
                        c.* = v;
                    }
                    h.g[(v >> 8) & 0xff] += 1;
                    h.r[(v >> 16) & 0xff] += 1;
                    h.b[v & 0xff] += 1;
                    h.a[v >> 24] += 1;
                }
                t.dcode = mask;
            } else {
                out.g[256 + prefixEncode(t.len).sym] += 1;
                out.d[prefixEncode(t.dcode).sym] += 1;
                const run = px[pos .. pos + t.len];
                pos += t.len;
                if (!any_cache) continue;
                for (0..nc) |ci| {
                    if (cands[ci] == 0) continue;
                    const cache = caches[ci << 11 ..][0 .. @as(usize, 1) << 11];
                    const sh = shifts[ci];
                    var last: u32 = ~run[0];
                    for (run) |v| {
                        if (v == last) continue;
                        last = v;
                        cache[(0x1e35a7bd *% v) >> sh] = v;
                    }
                }
            }
        }
        var best: f32 = std.math.floatMax(f32);
        var best_ci: usize = 0;
        for (hs[0..nc], cands, 0..) |*h, cb, ci| {
            const c = h.cost(@as(usize, 280) + (if (cb > 0) @as(usize, 1) << cb else 0));
            if (c < best) {
                best = c;
                best_ci = ci;
            }
        }
        const b = &hs[best_ci];
        for (out.g[0..256], b.g[0..256]) |*o, s| o.* = s;
        for (out.g[280..], b.g[280..]) |*o, s| o.* = s;
        out.r = b.r;
        out.b = b.b;
        out.a = b.a;
        return best_ci;
    }

    fn writeImage(e: *Enc, px: []const u32, w: u32, h: u32, main: bool) !void {
        _ = h;
        var toks: std.ArrayList(Tok) = .empty;
        defer toks.deinit(e.alloc);
        try e.lz77(px, w, &toks);

        const histos = try e.alloc.create(Histos);
        defer e.alloc.destroy(histos);

        var single: [1]u4 = .{0};
        const cands: []const u4 = if (!main) &single else if (e.opts.cache_bits) |cb| blk: {
            single[0] = @min(cb, 11);
            break :blk &single;
        } else switch (e.opts.effort) {
            0 => &.{10},
            1 => &.{11},
            else => &.{ 0, 2, 4, 6, 7, 8, 9, 10, 11 },
        };
        const ci = try e.selectCache(px, toks.items, cands, histos);
        const cache_bits = cands[ci];
        const hit_bit = @as(u32, 1) << @intCast(ci);
        const shift: u5 = if (cache_bits > 0) @intCast(32 - @as(u32, cache_bits)) else 0;

        const bw = e.bw;
        if (cache_bits > 0) {
            try bw.put(1, 1);
            try bw.put(cache_bits, 4);
        } else try bw.put(0, 1);
        if (main) try bw.put(0, 1); // no meta prefix codes

        const green_size: usize = 280 + (if (cache_bits > 0) @as(usize, 1) << cache_bits else 0);
        var codes = try e.alloc.create(Codes);
        defer e.alloc.destroy(codes);
        try writeCode(bw, histos.g[0..green_size], &codes.gl, &codes.gc);
        try writeCode(bw, &histos.r, &codes.rl, &codes.rc);
        try writeCode(bw, &histos.b, &codes.bl, &codes.bc);
        try writeCode(bw, &histos.a, &codes.al, &codes.ac);
        try writeCode(bw, &histos.d, &codes.dl, &codes.dc);

        // Emit.
        var pos: usize = 0;
        for (toks.items) |t| {
            if (t.len == 0) {
                const v = px[pos];
                pos += 1;
                if (t.dcode & hit_bit != 0) {
                    const k = 280 + ((0x1e35a7bd *% v) >> shift);
                    try bw.put(codes.gc[k], @intCast(codes.gl[k]));
                    continue;
                }
                const g = (v >> 8) & 0xff;
                const r = (v >> 16) & 0xff;
                const b = v & 0xff;
                const a = v >> 24;
                try bw.put(codes.gc[g], @intCast(codes.gl[g]));
                try bw.put(codes.rc[r], @intCast(codes.rl[r]));
                try bw.put(codes.bc[b], @intCast(codes.bl[b]));
                try bw.put(codes.ac[a], @intCast(codes.al[a]));
            } else {
                const lp = prefixEncode(t.len);
                try bw.put(codes.gc[256 + lp.sym], @intCast(codes.gl[256 + lp.sym]));
                if (lp.nb > 0) try bw.put(lp.extra, lp.nb);
                const dp = prefixEncode(t.dcode);
                try bw.put(codes.dc[dp.sym], @intCast(codes.dl[dp.sym]));
                if (dp.nb > 0) try bw.put(dp.extra, dp.nb);
                pos += t.len;
            }
        }
    }
};

const Histos = struct {
    g: [280 + 2048]u32 = @splat(0),
    r: [256]u32 = @splat(0),
    b: [256]u32 = @splat(0),
    a: [256]u32 = @splat(0),
    d: [40]u32 = @splat(0),

    fn cost(h: *const Histos, gsize: usize) f32 {
        return entropy(h.g[0..gsize]) + entropy(&h.r) + entropy(&h.b) + entropy(&h.a);
    }
};

fn entropy(h: []const u32) f32 {
    var total: u64 = 0;
    var sum: f32 = 0;
    var nz: u32 = 0;
    for (h) |c| {
        if (c == 0) continue;
        total += c;
        const f: f32 = @floatFromInt(c);
        sum += f * log2f(f);
        nz += 1;
    }
    if (nz <= 1) return @floatFromInt(nz * 8);
    const t: f32 = @floatFromInt(total);
    return t * log2f(t) - sum + @as(f32, @floatFromInt(nz)) * 4.0;
}

const Codes = struct {
    gl: [280 + 2048]u8,
    gc: [280 + 2048]u16,
    rl: [256]u8,
    rc: [256]u16,
    bl: [256]u8,
    bc: [256]u16,
    al: [256]u8,
    ac: [256]u16,
    dl: [40]u8,
    dc: [40]u16,
};

const code_length_order = [19]u8{ 17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };

/// Writes the prefix code for `freqs` and fills emission lengths/codes (length 0 for
/// symbols that cost zero bits, i.e. the single used symbol of a one-symbol code).
fn writeCode(bw: *BitWriter, freqs: []const u32, lens: []u8, codes: []u16) !void {
    const n = freqs.len;
    var used: usize = 0;
    var s: [2]usize = .{ 0, 0 };
    for (freqs, 0..) |f, i| {
        if (f != 0) {
            if (used < 2) s[used] = i;
            used += 1;
        }
    }
    @memset(lens[0..n], 0);
    @memset(codes[0..n], 0);
    if (used == 0 or (used <= 2 and s[0] < 256 and s[1] < 256)) {
        try bw.put(1, 1);
        if (used <= 1) {
            try bw.put(0, 1);
            if (s[0] < 2) {
                try bw.put(0, 1);
                try bw.put(@intCast(s[0]), 1);
            } else {
                try bw.put(1, 1);
                try bw.put(@intCast(s[0]), 8);
            }
            return; // zero-bit code
        }
        try bw.put(1, 1);
        if (s[0] < 2) {
            try bw.put(0, 1);
            try bw.put(@intCast(s[0]), 1);
        } else {
            try bw.put(1, 1);
            try bw.put(@intCast(s[0]), 8);
        }
        try bw.put(@intCast(s[1]), 8);
        lens[s[0]] = 1;
        lens[s[1]] = 1;
        huffman.canonicalCodes(lens[0..n], codes[0..n]);
        return;
    }
    _ = huffman.buildLengths(freqs, lens[0..n], 15);

    // RLE the code lengths.
    var rle_sym: [2328 + 8]u8 = undefined;
    var rle_ext: [2328 + 8]u8 = undefined;
    var nr: usize = 0;
    var cl_freq: [19]u32 = @splat(0);
    var prev: u8 = 8;
    var i: usize = 0;
    while (i < n) {
        const v = lens[i];
        var run: usize = 1;
        while (i + run < n and lens[i + run] == v) run += 1;
        i += run;
        if (v == 0) {
            while (run >= 11) {
                const k = @min(run, 138);
                rle_sym[nr] = 18;
                rle_ext[nr] = @intCast(k - 11);
                nr += 1;
                run -= k;
            }
            if (run >= 3) {
                rle_sym[nr] = 17;
                rle_ext[nr] = @intCast(run - 3);
                nr += 1;
                run = 0;
            }
            while (run > 0) : (run -= 1) {
                rle_sym[nr] = 0;
                nr += 1;
            }
        } else {
            if (v != prev) {
                rle_sym[nr] = v;
                nr += 1;
                run -= 1;
                prev = v;
            }
            while (run >= 3) {
                const k = @min(run, 6);
                rle_sym[nr] = 16;
                rle_ext[nr] = @intCast(k - 3);
                nr += 1;
                run -= k;
            }
            while (run > 0) : (run -= 1) {
                rle_sym[nr] = v;
                nr += 1;
            }
        }
    }
    for (rle_sym[0..nr]) |c| cl_freq[c] += 1;
    var cl_lens: [19]u8 = undefined;
    var cl_codes: [19]u16 = undefined;
    const cl_used = huffman.buildLengths(&cl_freq, &cl_lens, 7);
    huffman.canonicalCodes(&cl_lens, &cl_codes);
    var ncl: usize = 19;
    while (ncl > 4 and cl_lens[code_length_order[ncl - 1]] == 0) ncl -= 1;
    try bw.put(0, 1);
    try bw.put(@intCast(ncl - 4), 4);
    for (code_length_order[0..ncl]) |k| try bw.put(cl_lens[k], 3);
    try bw.put(0, 1); // max_symbol = alphabet size
    const cl_single = cl_used == 1;
    for (rle_sym[0..nr], rle_ext[0..nr]) |c, x| {
        if (!cl_single) try bw.put(cl_codes[c], @intCast(cl_lens[c]));
        switch (c) {
            16 => try bw.put(x, 2),
            17 => try bw.put(x, 3),
            18 => try bw.put(x, 7),
            else => {},
        }
    }
    huffman.canonicalCodes(lens[0..n], codes[0..n]);
    // One used symbol => decoder reads zero bits for it.
    var nz: usize = 0;
    for (lens[0..n]) |l| nz += @intFromBool(l != 0);
    if (nz == 1) @memset(lens[0..n], 0);
}

// ---------------------------------------------------------------------------------------------

fn roundTrip(rgba: []const u8, w: u32, h: u32, opts: Options) !usize {
    const a = std.testing.allocator;
    const out = try encodeLossless(a, rgba, w, h, opts);
    defer a.free(out);
    const img = try dec.decode(a, out, .{});
    defer img.deinit(a);
    try std.testing.expectEqual(w, img.width);
    try std.testing.expectEqual(h, img.height);
    try std.testing.expectEqualSlices(u8, rgba, img.data);
    const d = dec.dimensions(out).?;
    try std.testing.expectEqual(w, d[0]);
    return out.len;
}

test "round trip varied images" {
    const a = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(42);
    const rnd = prng.random();
    const sizes = [_][2]u32{ .{ 1, 1 }, .{ 2, 1 }, .{ 1, 7 }, .{ 3, 3 }, .{ 17, 9 }, .{ 64, 64 }, .{ 131, 77 }, .{ 300, 41 } };
    for (sizes) |sz| {
        const w = sz[0];
        const h = sz[1];
        const buf = try a.alloc(u8, w * h * 4);
        defer a.free(buf);
        for (0..6) |kind| {
            for (0..h) |y| for (0..w) |x| {
                const p = buf[(y * w + x) * 4 ..][0..4];
                switch (kind) {
                    0 => rnd.bytes(p),
                    1 => p.* = .{ @truncate(x * 3), @truncate(y * 5), @truncate(x + y), 255 },
                    2 => p.* = .{ 10, 200, 30, 255 },
                    3 => p.* = .{ @truncate(x * 7), @truncate(y), 99, @truncate((x * y) & 0xff) },
                    4 => {
                        const c: u8 = @truncate(((x / 3) ^ (y / 2)) % 5);
                        p.* = .{ c * 40, 255 - c, c, if (c == 2) 0 else 255 };
                    },
                    else => {
                        const c: u8 = @truncate(((x / 4) + (y / 4)) & 1);
                        p.* = .{ c * 255, c * 255, c * 255, 255 };
                    },
                }
            };
            for (0..3) |eff| _ = try roundTrip(buf, w, h, .{ .effort = @intCast(eff) });
            _ = try roundTrip(buf, w, h, .{ .cache_bits = 11 });
            _ = try roundTrip(buf, w, h, .{ .cache_bits = 1 });
        }
    }
}

test "round trip takumi render" {
    const raw = @embedFile("testdata/webp_takumi.rgba");
    const len = try roundTrip(raw, 120, 48, .{});
    try std.testing.expect(len < @embedFile("testdata/webp_takumi.webp").len);
}

test "rejects bad input" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.InvalidInput, encodeLossless(a, &.{}, 0, 0, .{}));
    try std.testing.expectError(error.InvalidInput, encodeLossless(a, &.{ 1, 2, 3 }, 1, 1, .{}));
}

/// Fast log2 approximation (|err| < 0.005), good enough for entropy estimates and avoids
/// linking compiler-rt's log2f.
fn log2f(x: f32) f32 {
    const bits: u32 = @bitCast(x);
    const e: f32 = @floatFromInt(@as(i32, @intCast(bits >> 23)) - 127);
    const m: f32 = @bitCast((bits & 0x007fffff) | 0x3f800000);
    return e + (-0.34484843 * m + 2.02466578) * m - 0.67487759;
}
