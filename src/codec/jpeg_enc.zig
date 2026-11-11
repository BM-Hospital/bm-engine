//! Baseline JPEG encoder: IJG quality scaling of the Annex K tables, YCbCr 4:4:4 (default,
//! like takumi) or 4:2:0, libjpeg "islow" integer forward DCT, and per-image OPTIMISED Huffman
//! tables (two passes over a compact token list, like jpeg-encoder/libjpeg `optimize_coding`).
//!
//! Alpha: by default it is dropped (straight RGB is encoded as-is), mirroring takumi, which hands
//! RGBA to jpeg-encoder; set `background` to flatten onto a colour instead.
//! Allocation: planes (~3 bytes/pixel) + tokens (~4 bytes per non-zero coefficient) are temporary;
//! the returned file is owned by the caller. All from `alloc`.
const std = @import("std");
const huffman = @import("huffman.zig");

pub const Subsampling = enum { s444, s420 };

pub const Options = struct {
    /// 1..100 (IJG scale). takumi's default is 75.
    quality: u8 = 75,
    /// takumi forces 4:4:4 (sharper coloured text); 4:2:0 gives smaller files.
    subsampling: Subsampling = .s444,
    /// null: ignore alpha (takumi behaviour; transparent straight pixels are usually black).
    /// Otherwise composite onto this RGB colour.
    background: ?[3]u8 = null,
};

pub const Error = error{ OutOfMemory, InvalidInput };

const std_lum = [64]u8{
    16, 11, 10, 16, 24,  40,  51,  61,
    12, 12, 14, 19, 26,  58,  60,  55,
    14, 13, 16, 24, 40,  57,  69,  56,
    14, 17, 22, 29, 51,  87,  80,  62,
    18, 22, 37, 56, 68,  109, 103, 77,
    24, 35, 55, 64, 81,  104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101,
    72, 92, 95, 98, 112, 100, 103, 99,
};
const std_chr = [64]u8{
    17, 18, 24, 47, 99, 99, 99, 99,
    18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99,
    47, 66, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
};
/// zigzag index -> natural index
const zigzag = [64]u8{
    0,  1,  8,  16, 9,  2,  3,  10, 17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
};

const Quant = struct { val: [64]u16, half: [64]u32, recip: [64]u64 };

fn scaleTable(base: *const [64]u8, quality: u8, out: *Quant) void {
    const q: u32 = @max(1, @min(100, quality));
    const scale: u32 = if (q < 50) 5000 / q else 200 - 2 * q;
    for (base, 0..) |b, i| {
        const v = (@as(u32, b) * scale + 50) / 100;
        const qv: u32 = @max(1, @min(255, v));
        out.val[i] = @intCast(qv);
        out.half[i] = qv * 4;
        out.recip[i] = ((@as(u64, 1) << 32) + qv * 8 - 1) / (qv * 8);
    }
}

// ------------------------------------------------------------------ FDCT (libjpeg jfdctint)

const CB = 13;
const P1 = 2;
const V8 = @Vector(8, i32);

inline fn kv(comptime c: i32) V8 {
    return @splat(c);
}

inline fn descaleV(x: V8, comptime n: u5) V8 {
    return (x + kv(1 << (n - 1))) >> @splat(n);
}

/// One 1-D islow pass over 8 independent lanes; v[i] holds element i of each lane's vector.
inline fn dct8(v: *[8]V8, comptime first: bool) void {
    const t0 = v[0] + v[7];
    const t7 = v[0] - v[7];
    const t1 = v[1] + v[6];
    const t6 = v[1] - v[6];
    const t2 = v[2] + v[5];
    const t5 = v[2] - v[5];
    const t3 = v[3] + v[4];
    const t4 = v[3] - v[4];
    const t10 = t0 + t3;
    const t13 = t0 - t3;
    const t11 = t1 + t2;
    const t12 = t1 - t2;
    const sh: u5 = if (first) CB - P1 else CB + P1;
    if (first) {
        v[0] = (t10 + t11) << @splat(P1);
        v[4] = (t10 - t11) << @splat(P1);
    } else {
        v[0] = descaleV(t10 + t11, P1);
        v[4] = descaleV(t10 - t11, P1);
    }
    const z1 = (t12 + t13) * kv(4433);
    v[2] = descaleV(z1 + t13 * kv(6270), sh);
    v[6] = descaleV(z1 - t12 * kv(15137), sh);
    const z5 = (t4 + t6 + t5 + t7) * kv(9633);
    const zz1 = (t4 + t7) * kv(-7373);
    const zz2 = (t5 + t6) * kv(-20995);
    const zz3 = (t4 + t6) * kv(-16069) + z5;
    const zz4 = (t5 + t7) * kv(-3196) + z5;
    v[7] = descaleV(t4 * kv(2446) + zz1 + zz3, sh);
    v[5] = descaleV(t5 * kv(16819) + zz2 + zz4, sh);
    v[3] = descaleV(t6 * kv(25172) + zz2 + zz3, sh);
    v[1] = descaleV(t7 * kv(12299) + zz1 + zz4, sh);
}

/// libjpeg jfdctint ("islow") forward DCT, output scaled by 8. 8 lanes at a time.
fn fdct(d: *[64]i32) void {
    var v: [8]V8 = undefined;
    // rows: lane = row, element = column
    for (0..8) |c| {
        var t: [8]i32 = undefined;
        for (0..8) |r| t[r] = d[r * 8 + c];
        v[c] = t;
    }
    dct8(&v, true);
    // columns: lane = column, element = row  (transpose back through memory)
    for (0..8) |c| {
        const t: [8]i32 = v[c];
        for (0..8) |r| d[r * 8 + c] = t[r];
    }
    for (0..8) |r| v[r] = d[r * 8 ..][0..8].*;
    dct8(&v, false);
    for (0..8) |r| d[r * 8 ..][0..8].* = v[r];
}

// ------------------------------------------------------------------ tokens

/// token: table(2b) << 24 | symbol << 16 | extra-bits value (nbits = symbol & 15)
const Tok = u32;

const Coder = struct {
    toks: std.ArrayList(Tok) = .empty,
    freq: [4][257]u32 = @splat(@splat(0)),
    alloc: std.mem.Allocator,

    inline fn put(c: *Coder, table: u32, sym: u32, val: u32) void {
        c.toks.appendAssumeCapacity((table << 24) | (sym << 16) | val);
        c.freq[table][sym] += 1;
    }
};

inline fn category(v: i32) u5 {
    const a: u32 = @abs(v);
    return @intCast(32 - @clz(a));
}

/// Quantises block `d` (FDCT output) and appends its tokens. Returns the new DC value.
fn encodeBlock(c: *Coder, d: *[64]i32, qt: *const Quant, prev_dc: i32, dc_tab: u32, ac_tab: u32) Error!i32 {
    try c.toks.ensureUnusedCapacity(c.alloc, 64);
    var q: [64]i32 = undefined;
    for (0..64) |k| {
        const nat = zigzag[k];
        const x = d[nat];
        // (|x| + qv/2) / qv via an exact reciprocal multiply (|x| < 2^17)
        const ax: u64 = @as(u32, @intCast(@abs(x))) + qt.half[nat];
        const r: i32 = @intCast((ax * qt.recip[nat]) >> 32);
        q[k] = if (x < 0) -r else r;
    }
    const diff = q[0] - prev_dc;
    const s = category(diff);
    c.put(dc_tab, s, @as(u32, @bitCast(if (diff < 0) diff - 1 else diff)) & ((@as(u32, 1) << s) - 1));
    var run: u32 = 0;
    for (1..64) |k| {
        const v = q[k];
        if (v == 0) {
            run += 1;
            continue;
        }
        while (run >= 16) : (run -= 16) c.put(ac_tab, 0xF0, 0);
        const sz = category(v);
        c.put(ac_tab, (run << 4) | sz, @as(u32, @bitCast(if (v < 0) v - 1 else v)) & ((@as(u32, 1) << sz) - 1));
        run = 0;
    }
    if (run > 0) c.put(ac_tab, 0x00, 0);
    return q[0];
}

// ------------------------------------------------------------------ output

const Out = struct {
    buf: std.ArrayList(u8) = .empty,
    alloc: std.mem.Allocator,
    acc: u32 = 0,
    n: u5 = 0,

    fn bytes(o: *Out, b: []const u8) Error!void {
        try o.buf.appendSlice(o.alloc, b);
    }
    fn u16be(o: *Out, v: usize) Error!void {
        try o.bytes(&.{ @intCast(v >> 8), @truncate(v) });
    }
    /// MSB-first, <= 16 bits, with 0xFF byte stuffing; caller ensured capacity (4 bytes).
    inline fn bits(o: *Out, v: u32, n: u5) void {
        o.acc = (o.acc << n) | v;
        o.n += n;
        while (o.n >= 8) {
            o.n -= 8;
            const b: u8 = @truncate(o.acc >> o.n);
            o.buf.appendAssumeCapacity(b);
            if (b == 0xFF) o.buf.appendAssumeCapacity(0);
        }
    }
};

const HuffTable = struct {
    len: [257]u8,
    code: [257]u16,
};

/// Optimised table: real symbols get doubled weight so the reserved symbol 256 (weight 1) is
/// strictly the rarest, gets the longest length and therefore the all-ones code, which is
/// then left out of the DHT (as libjpeg does).
fn buildTable(freq: *const [257]u32, t: *HuffTable) void {
    var f: [257]u32 = undefined;
    for (0..256) |i| f[i] = if (freq[i] == 0) 0 else freq[i] * 2;
    f[256] = 1;
    _ = huffman.buildLengths(&f, &t.len, 16);
    var bl: [17]u16 = @splat(0);
    for (t.len) |l| bl[l] += 1;
    bl[0] = 0;
    var next: [17]u16 = undefined;
    var code: u16 = 0;
    for (1..17) |b| {
        code = (code +% bl[b - 1]) << 1;
        next[b] = code;
    }
    for (0..257) |i| {
        const l = t.len[i];
        if (l == 0) continue;
        t.code[i] = next[l];
        next[l] +%= 1;
    }
}

fn writeDht(o: *Out, t: *const HuffTable, class_id: u8) Error!void {
    var counts: [17]u8 = @splat(0);
    var n: usize = 0;
    for (0..256) |i| if (t.len[i] != 0) {
        counts[t.len[i]] += 1;
        n += 1;
    };
    try o.bytes(&.{ 0xFF, 0xC4 });
    try o.u16be(2 + 1 + 16 + n);
    try o.bytes(&.{class_id});
    try o.bytes(counts[1..17]);
    for (1..17) |l| for (0..256) |i| if (t.len[i] == l) try o.bytes(&.{@intCast(i)});
}

// ------------------------------------------------------------------ main entry

/// Encodes straight RGBA8 (`w*h*4` bytes) as a baseline JFIF JPEG.
pub fn encode(alloc: std.mem.Allocator, rgba: []const u8, w: u32, h: u32, opts: Options) Error![]u8 {
    if (w == 0 or h == 0 or w > 65535 or h > 65535) return error.InvalidInput;
    if (@as(u64, w) * h * 4 != rgba.len) return error.InvalidInput;
    const sub = opts.subsampling == .s420;
    const mcu: usize = if (sub) 16 else 8;
    const pw = (@as(usize, w) + mcu - 1) / mcu * mcu;
    const ph = (@as(usize, h) + mcu - 1) / mcu * mcu;
    const cw = if (sub) pw / 2 else pw;
    const ch = if (sub) ph / 2 else ph;

    // colour conversion into padded planes (edge replicated)
    const planes = try alloc.alloc(u8, pw * ph + 2 * cw * ch);
    defer alloc.free(planes);
    const Y = planes[0 .. pw * ph];
    const Cb = planes[pw * ph ..][0 .. cw * ch];
    const Cr = planes[pw * ph + cw * ch ..][0 .. cw * ch];
    {
        // full-res chroma rows for 4:2:0 are averaged on the fly, two rows at a time
        const tmp = try alloc.alloc(u8, if (sub) pw * 4 else 0);
        defer alloc.free(tmp);
        const bg = opts.background;
        const flat = try alloc.alloc(u8, if (bg != null) @as(usize, w) * 4 else 0);
        defer alloc.free(flat);
        for (0..ph) |y| {
            const sy = @min(y, h - 1);
            const src = rgba[sy * w * 4 ..][0 .. w * 4];
            const yrow = Y[y * pw ..][0..pw];
            const cbrow = if (sub) tmp[(y & 1) * pw * 2 ..][0..pw] else Cb[y * cw ..][0..pw];
            const crrow = if (sub) tmp[(y & 1) * pw * 2 + pw ..][0..pw] else Cr[y * cw ..][0..pw];
            var row: []const u8 = src;
            if (bg) |c| {
                for (0..w) |x| {
                    const s = src[x * 4 ..][0..4];
                    const a: u32 = s[3];
                    for (0..3) |k| flat[x * 4 + k] = @intCast((@as(u32, s[k]) * a + @as(u32, c[k]) * (255 - a) + 127) / 255);
                }
                row = flat;
            }
            for (0..w) |x| {
                const r: i32 = row[x * 4];
                const g: i32 = row[x * 4 + 1];
                const b: i32 = row[x * 4 + 2];
                // libjpeg jccolor fixed point (16 bits)
                yrow[x] = @intCast((19595 * r + 38470 * g + 7471 * b + 32768) >> 16);
                cbrow[x] = @intCast((-11059 * r - 21709 * g + 32768 * b + (128 << 16) + 32767) >> 16);
                crrow[x] = @intCast((32768 * r - 27439 * g - 5329 * b + (128 << 16) + 32767) >> 16);
            }
            for (w..pw) |x| {
                yrow[x] = yrow[w - 1];
                cbrow[x] = cbrow[w - 1];
                crrow[x] = crrow[w - 1];
            }
            if (sub and (y & 1) == 1) {
                const oy = y / 2;
                for (0..2) |k| {
                    const r0 = tmp[k * pw ..][0..pw];
                    const r1 = tmp[pw * 2 + k * pw ..][0..pw];
                    const dst = if (k == 0) Cb[oy * cw ..][0..cw] else Cr[oy * cw ..][0..cw];
                    for (0..cw) |x| {
                        const sum = @as(u32, r0[2 * x]) + r0[2 * x + 1] + r1[2 * x] + r1[2 * x + 1];
                        dst[x] = @intCast((sum + 1 + (x & 1)) >> 2);
                    }
                }
            }
        }
    }

    var qt: [2]Quant = undefined;
    scaleTable(&std_lum, opts.quality, &qt[0]);
    scaleTable(&std_chr, opts.quality, &qt[1]);

    // pass 1: DCT + quantise + tokenise
    var coder = Coder{ .alloc = alloc };
    defer coder.toks.deinit(alloc);
    try coder.toks.ensureTotalCapacity(alloc, pw * ph / 8);
    var dc = [3]i32{ 0, 0, 0 };
    var blk: [64]i32 = undefined;
    var my: usize = 0;
    while (my < ph) : (my += mcu) {
        var mx: usize = 0;
        while (mx < pw) : (mx += mcu) {
            const nly: usize = if (sub) 2 else 1;
            for (0..nly) |by| for (0..nly) |bx| {
                loadBlock(&blk, Y, pw, mx + bx * 8, my + by * 8);
                fdct(&blk);
                dc[0] = try encodeBlock(&coder, &blk, &qt[0], dc[0], 0, 1);
            };
            const cx = if (sub) mx / 2 else mx;
            const cy = if (sub) my / 2 else my;
            loadBlock(&blk, Cb, cw, cx, cy);
            fdct(&blk);
            dc[1] = try encodeBlock(&coder, &blk, &qt[1], dc[1], 2, 3);
            loadBlock(&blk, Cr, cw, cx, cy);
            fdct(&blk);
            dc[2] = try encodeBlock(&coder, &blk, &qt[1], dc[2], 2, 3);
        }
    }

    var tabs: [4]HuffTable = undefined;
    for (0..4) |i| buildTable(&coder.freq[i], &tabs[i]);

    // headers
    var o = Out{ .alloc = alloc };
    errdefer o.buf.deinit(alloc);
    try o.buf.ensureTotalCapacity(alloc, coder.toks.items.len + 1024);
    try o.bytes(&.{ 0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0 });
    for (0..2) |t| {
        try o.bytes(&.{ 0xFF, 0xDB, 0, 67, @intCast(t) });
        for (0..64) |k| try o.bytes(&.{@intCast(qt[t].val[zigzag[k]])});
    }
    const samp: u8 = if (sub) 0x22 else 0x11;
    try o.bytes(&.{ 0xFF, 0xC0, 0, 17, 8 });
    try o.u16be(h);
    try o.u16be(w);
    try o.bytes(&.{ 3, 1, samp, 0, 2, 0x11, 1, 3, 0x11, 1 });
    try writeDht(&o, &tabs[0], 0x00);
    try writeDht(&o, &tabs[1], 0x10);
    try writeDht(&o, &tabs[2], 0x01);
    try writeDht(&o, &tabs[3], 0x11);
    try o.bytes(&.{ 0xFF, 0xDA, 0, 12, 3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0 });

    // pass 2: entropy data (worst case 2 bytes per byte after stuffing; ensure per chunk)
    const toks = coder.toks.items;
    var i: usize = 0;
    while (i < toks.len) {
        const end = @min(toks.len, i + 4096);
        try o.buf.ensureUnusedCapacity(alloc, (end - i) * 8 + 16);
        for (toks[i..end]) |t| {
            const tab = &tabs[t >> 24];
            const sym = (t >> 16) & 0xff;
            o.bits(tab.code[sym], @intCast(tab.len[sym]));
            const nb: u5 = @intCast(sym & 15);
            if (nb != 0) o.bits(t & 0xffff, nb);
        }
        i = end;
    }
    try o.buf.ensureUnusedCapacity(alloc, 8);
    if (o.n > 0) o.bits((@as(u32, 1) << (8 - @as(u5, o.n))) - 1, 8 - o.n); // pad with ones
    try o.bytes(&.{ 0xFF, 0xD9 });
    return o.buf.toOwnedSlice(alloc);
}

fn loadBlock(blk: *[64]i32, plane: []const u8, stride: usize, x0: usize, y0: usize) void {
    for (0..8) |r| {
        const row = plane[(y0 + r) * stride + x0 ..][0..8];
        for (0..8) |c| blk[r * 8 + c] = @as(i32, row[c]) - 128;
    }
}

// ------------------------------------------------------------------ tests
const testing = std.testing;

fn psnr(a: []const u8, b: []const u8) f64 {
    var se: f64 = 0;
    var n: f64 = 0;
    var i: usize = 0;
    while (i < a.len) : (i += 4) {
        for (0..3) |k| {
            const d = @as(f64, @floatFromInt(a[i + k])) - @as(f64, @floatFromInt(b[i + k]));
            se += d * d;
            n += 1;
        }
    }
    if (se == 0) return 99;
    return 10 * std.math.log10(255.0 * 255.0 / (se / n));
}

test "jpeg encode -> decode PSNR" {
    const dec = @import("jpeg_dec.zig");
    const w = 203;
    const h = 117;
    const img = try testing.allocator.alloc(u8, w * h * 4);
    defer testing.allocator.free(img);
    var prng = std.Random.DefaultPrng.init(3);
    const rnd = prng.random();
    for (0..h) |y| for (0..w) |x| {
        const p = img[(y * w + x) * 4 ..][0..4];
        p[0] = @intCast((x * 255) / w);
        p[1] = @intCast((y * 255) / h);
        p[2] = if ((x / 20 + y / 20) % 2 == 0) 200 else 40;
        p[0] +%= rnd.uintLessThan(u8, 3);
        p[3] = 255;
    };
    // 4:2:0 cannot keep the hard blue checkerboard edges (~29 dB), so test it on a smooth image
    // (luma edges are still sharp: green ramp + noise)
    for ([_]Subsampling{ .s444, .s420 }) |ss| {
        if (ss == .s420) for (0..h) |y| for (0..w) |x| {
            img[(y * w + x) * 4 + 2] = @intCast((x + y) * 255 / (w + h));
        };
        const jpg = try encode(testing.allocator, img, w, h, .{ .quality = 90, .subsampling = ss });
        defer testing.allocator.free(jpg);
        const im = try dec.decode(testing.allocator, jpg, .{});
        defer im.deinit(testing.allocator);
        try testing.expectEqual(@as(u32, w), im.width);
        const p = psnr(img, im.data);
        if (p <= 35) std.debug.print("psnr {s} {d:.2}\n", .{ @tagName(ss), p });
        try testing.expect(p > 35);
    }
    // every quality and tiny sizes decode
    for ([_]u8{ 1, 10, 50, 75, 100 }) |q| for ([_][2]u32{ .{ 1, 1 }, .{ 9, 17 }, .{ 33, 8 } }) |sz| {
        const jpg = try encode(testing.allocator, img[0 .. sz[0] * sz[1] * 4], sz[0], sz[1], .{ .quality = q, .subsampling = if (q > 50) .s420 else .s444 });
        defer testing.allocator.free(jpg);
        const im = try dec.decode(testing.allocator, jpg, .{});
        im.deinit(testing.allocator);
    };
}
