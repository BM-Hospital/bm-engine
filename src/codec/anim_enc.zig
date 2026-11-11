//! Animated image encoders: APNG, GIF89a and animated WebP (lossless VP8L frames).
//!
//! All frames share the canvas size `w` x `h` and are straight-alpha RGBA8 (`rgba.len == w*h*4`).
//! Every allocation goes through `alloc`; temporaries are freed before returning and the result
//! is owned by the caller. Peak memory: APNG ~ output + one PNG frame; GIF ~ output + w*h index
//! bytes + ~300 KB quantiser tables; WebP ~ output + one cropped frame + encoder temporaries.
//! With a bump arena the output buffer grows by copying (it is not the last allocation), so a
//! general-purpose allocator is preferable for long animations.
const std = @import("std");
const png = @import("png.zig");
const webp_enc = @import("webp_enc.zig");
const checksum = @import("checksum.zig");
const byt = @import("bytes.zig");

pub const AnimFrame = struct {
    /// Straight RGBA8, `w*h*4` bytes.
    rgba: []const u8,
    delay_ms: u32,
};

pub const AnimOptions = struct {
    /// Number of loops; 0 = forever (APNG num_plays, WebP ANIM loop count, GIF NETSCAPE2.0 value).
    loop_count: u16 = 0,
    /// GIF/WebP: merge consecutive identical frames (durations add up, like takumi) and encode
    /// each later frame as the bounding rectangle of the pixels that changed. GIF additionally
    /// makes unchanged pixels inside the rectangle transparent.
    frame_diff: bool = true,
    /// GIF: pixels with alpha < this are transparent, all others opaque. 1 mirrors takumi's
    /// `gif` crate (only alpha 0 is transparent); 128 is the common 50% cut. 0 = never transparent.
    gif_alpha_threshold: u8 = 1,
};

pub const EncodeError = error{ OutOfMemory, InvalidInput };

const Out = std.ArrayList(u8);

fn validate(frames: []const AnimFrame, w: u32, h: u32, max_side: u32) EncodeError!usize {
    if (frames.len == 0 or w == 0 or h == 0 or w > max_side or h > max_side) return error.InvalidInput;
    const npx64 = @as(u64, w) * h;
    if (npx64 > std.math.maxInt(usize) / 8) return error.InvalidInput;
    const npx: usize = @intCast(npx64);
    for (frames) |f| if (f.rgba.len != npx * 4) return error.InvalidInput;
    return npx;
}

fn allOpaque(rgba: []const u8) bool {
    var a: u8 = 255;
    var i: usize = 3;
    while (i < rgba.len) : (i += 4) a &= rgba[i];
    return a == 255;
}

inline fn px(rgba: []const u8, i: usize) u32 {
    return byt.le32(rgba, i * 4);
}

fn putLe16(b: []u8, v: u32) void {
    b[0] = @truncate(v);
    b[1] = @truncate(v >> 8);
}

fn putLe24(b: []u8, v: u32) void {
    b[0] = @truncate(v);
    b[1] = @truncate(v >> 8);
    b[2] = @truncate(v >> 16);
}

const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

// =============================================================================== APNG

fn pngChunk(alloc: std.mem.Allocator, out: *Out, typ: *const [4]u8, a: []const u8, b: []const u8) EncodeError!void {
    var hdr: [8]u8 = undefined;
    byt.putBe32(&hdr, 0, @intCast(a.len + b.len));
    hdr[4..8].* = typ.*;
    var crc = checksum.crc32(0, typ);
    crc = checksum.crc32(crc, a);
    crc = checksum.crc32(crc, b);
    var tail: [4]u8 = undefined;
    byt.putBe32(&tail, 0, crc);
    try out.ensureUnusedCapacity(alloc, 12 + a.len + b.len);
    out.appendSliceAssumeCapacity(&hdr);
    out.appendSliceAssumeCapacity(a);
    out.appendSliceAssumeCapacity(b);
    out.appendSliceAssumeCapacity(&tail);
}

/// Animated PNG. Every frame covers the whole canvas (dispose op NONE, blend op SOURCE, delay
/// `delay_ms/1000` clamped to 65535 ms), frame 0 is also the default image. Frames are encoded
/// with `png.encode` (no palette, so all frames share one IHDR; RGB when every frame is fully
/// opaque, else RGBA). takumi always writes RGBA; the pixels are identical.
pub fn encodeApng(alloc: std.mem.Allocator, frames: []const AnimFrame, w: u32, h: u32, opts: AnimOptions) EncodeError![]u8 {
    _ = try validate(frames, w, h, 1 << 24);
    if (frames.len > std.math.maxInt(u32) / 4) return error.InvalidInput;
    var all_opaque = true;
    for (frames) |f| {
        if (!allOpaque(f.rgba)) {
            all_opaque = false;
            break;
        }
    }
    var out: Out = .empty;
    errdefer out.deinit(alloc);
    var seq: u32 = 0;
    for (frames, 0..) |f, fi| {
        const p = try png.encode(alloc, f.rgba, w, h, .{ .palette = false, .strip_opaque_alpha = all_opaque });
        defer alloc.free(p);
        var fctl: [26]u8 = @splat(0);
        byt.putBe32(&fctl, 0, seq);
        byt.putBe32(&fctl, 4, w);
        byt.putBe32(&fctl, 8, h);
        // x/y offsets 0, delay num/den, dispose 0 (none), blend 0 (source)
        const d: u32 = @min(f.delay_ms, 0xffff);
        fctl[20] = @truncate(d >> 8);
        fctl[21] = @truncate(d);
        fctl[22] = 1000 >> 8;
        fctl[23] = 1000 & 0xff;
        seq += 1;
        var pos: usize = 8;
        var fctl_done = false;
        while (pos + 12 <= p.len) {
            const len = byt.be32(p, pos);
            if (len > p.len - pos - 12) break;
            const typ = p[pos + 4 ..][0..4];
            const data = p[pos + 8 ..][0..len];
            pos += 12 + len;
            if (std.mem.eql(u8, typ, "IHDR")) {
                if (fi != 0) continue;
                try out.appendSlice(alloc, &png.signature);
                try pngChunk(alloc, &out, "IHDR", data, "");
                var actl: [8]u8 = undefined;
                byt.putBe32(&actl, 0, @intCast(frames.len));
                byt.putBe32(&actl, 4, opts.loop_count);
                try pngChunk(alloc, &out, "acTL", &actl, "");
            } else if (std.mem.eql(u8, typ, "IDAT")) {
                if (!fctl_done) {
                    try pngChunk(alloc, &out, "fcTL", &fctl, "");
                    fctl_done = true;
                }
                if (fi == 0) {
                    try pngChunk(alloc, &out, "IDAT", data, "");
                    continue;
                }
                var rest = data;
                while (true) {
                    const n = @min(rest.len, 1 << 30);
                    var sq: [4]u8 = undefined;
                    byt.putBe32(&sq, 0, seq);
                    seq += 1;
                    try pngChunk(alloc, &out, "fdAT", &sq, rest[0..n]);
                    rest = rest[n..];
                    if (rest.len == 0) break;
                }
            }
        }
        if (!fctl_done) return error.InvalidInput; // cannot happen with png.encode output
    }
    try pngChunk(alloc, &out, "IEND", "", "");
    return out.toOwnedSlice(alloc);
}

// =============================================================================== WebP

/// takumi's "visibly equal": same bytes, or both fully transparent.
inline fn sameVisible(a: u32, b: u32) bool {
    return a == b or (a | b) >> 24 == 0;
}

fn sameWebp(a: []const u8, b: []const u8) bool {
    for (0..a.len / 4) |i| if (!sameVisible(px(a, i), px(b, i))) return false;
    return true;
}

/// Bounding box of visibly differing pixels with the origin rounded down to even (ANMF stores
/// offsets halved). Null if none differ.
fn diffRectWebp(prev: []const u8, cur: []const u8, w: u32, h: u32) ?Rect {
    var x0: u32 = w;
    var x1: u32 = 0;
    var y0: u32 = h;
    var y1: u32 = 0;
    var i: usize = 0;
    for (0..h) |y| {
        for (0..w) |x| {
            if (!sameVisible(px(prev, i), px(cur, i))) {
                x0 = @min(x0, @as(u32, @intCast(x)));
                x1 = @max(x1, @as(u32, @intCast(x)));
                y0 = @min(y0, @as(u32, @intCast(y)));
                y1 = @intCast(y);
            }
            i += 1;
        }
    }
    if (y0 == h) return null;
    x0 &= ~@as(u32, 1);
    y0 &= ~@as(u32, 1);
    return .{ .x = x0, .y = y0, .w = x1 + 1 - x0, .h = y1 + 1 - y0 };
}

fn cropInto(dst: []u8, src: []const u8, w: u32, r: Rect) []u8 {
    const rb = @as(usize, r.w) * 4;
    for (0..r.h) |yy| {
        const s = ((@as(usize, r.y) + yy) * w + r.x) * 4;
        @memcpy(dst[yy * rb ..][0..rb], src[s..][0..rb]);
    }
    return dst[0 .. rb * r.h];
}

/// Animated WebP: RIFF/WEBP + VP8X (animation flag, alpha flag when any frame has alpha < 255)
/// + ANIM (background 0, `loop_count`) + one ANMF per frame wrapping a lossless VP8L bitstream
/// from `webp_enc.encodeLossless`. Like takumi: identical consecutive frames merge (with
/// `frame_diff`), later frames are cropped to the changed rectangle (even origin), every frame
/// is no-blend / dispose-none so the rectangle replaces the canvas exactly. Canvas <= 16384.
pub fn encodeWebpAnim(alloc: std.mem.Allocator, frames: []const AnimFrame, w: u32, h: u32, opts: AnimOptions) EncodeError![]u8 {
    const npx = try validate(frames, w, h, 16384);
    var any_alpha = false;
    for (frames) |f| any_alpha = any_alpha or !allOpaque(f.rgba);

    var crop: []u8 = &.{};
    defer alloc.free(crop);
    if (opts.frame_diff and frames.len > 1) crop = try alloc.alloc(u8, npx * 4);

    var out: Out = .empty;
    errdefer out.deinit(alloc);
    var hdr: [12 + 18 + 14]u8 = @splat(0);
    hdr[0..4].* = "RIFF".*;
    hdr[8..12].* = "WEBP".*;
    hdr[12..16].* = "VP8X".*;
    hdr[16] = 10;
    hdr[20] = 0x02 | @as(u8, if (any_alpha) 0x10 else 0);
    putLe24(hdr[24..27], w - 1);
    putLe24(hdr[27..30], h - 1);
    hdr[30..34].* = "ANIM".*;
    hdr[34] = 6;
    // bytes 38..42 background colour 0 (transparent)
    putLe16(hdr[42..44], opts.loop_count);
    try out.appendSlice(alloc, &hdr);

    var i: usize = 0;
    while (i < frames.len) {
        const cur = frames[i].rgba;
        var dur: u32 = @min(frames[i].delay_ms, 0xffffff);
        var j = i + 1;
        if (opts.frame_diff) {
            while (j < frames.len and sameWebp(cur, frames[j].rgba)) : (j += 1)
                dur = @min(dur + @min(frames[j].delay_ms, 0xffffff), 0xffffff);
        }
        var r = Rect{ .x = 0, .y = 0, .w = w, .h = h };
        var src = cur;
        if (opts.frame_diff and i > 0) {
            if (diffRectWebp(frames[i - 1].rgba, cur, w, h)) |d| r = d;
            if (r.w != w or r.h != h) src = cropInto(crop, cur, w, r);
        }
        const enc = try webp_enc.encodeLossless(alloc, src, r.w, r.h, .{});
        defer alloc.free(enc);
        // Locate the VP8L chunk (encodeLossless writes RIFF/WEBP/VP8L).
        if (enc.len < 20 or !std.mem.eql(u8, enc[12..16], "VP8L")) return error.InvalidInput;
        const plen = byt.le32(enc, 16);
        if (plen > enc.len - 20) return error.InvalidInput;
        const pad = plen & 1;
        var fh: [24 + 8]u8 = undefined;
        fh[0..4].* = "ANMF".*;
        byt.putLe32(&fh, 4, 16 + 8 + plen + pad);
        putLe24(fh[8..11], r.x / 2);
        putLe24(fh[11..14], r.y / 2);
        putLe24(fh[14..17], r.w - 1);
        putLe24(fh[17..20], r.h - 1);
        putLe24(fh[20..23], dur);
        fh[23] = 0x02; // no blend, dispose none
        fh[24..28].* = "VP8L".*;
        byt.putLe32(&fh, 28, plen);
        try out.ensureUnusedCapacity(alloc, fh.len + plen + pad);
        out.appendSliceAssumeCapacity(&fh);
        out.appendSliceAssumeCapacity(enc[20..][0..plen]);
        if (pad != 0) out.appendAssumeCapacity(0);
        i = j;
    }
    if (out.items.len - 8 > std.math.maxInt(u32)) return error.InvalidInput;
    byt.putLe32(out.items, 4, @intCast(out.items.len - 8));
    return out.toOwnedSlice(alloc);
}

// =============================================================================== GIF

/// Effective GIF pixel: 0xFF000000 for transparent, else 0x00BBGGRR.
inline fn eff(p: u32, thr: u8) u32 {
    return if ((p >> 24) < thr) 0xFF000000 else p & 0xffffff;
}

const Quant = struct {
    const nbins = 1 << 15;
    hist: [nbins]u32,
    cache: [nbins]u16,
    binbox: [nbins]u8,
    bins: [nbins]u16,
    keys: [1024]u32,
    ents: [1024]u16, // palette index + 1, 0 = empty
    sums: [256][4]u64,
    pal: [256][3]u8,
    boxes: [256]Box,
    n: usize,

    inline fn bin(c: u32) u16 {
        return @intCast(((c >> 3) & 0x1f) << 10 | ((c >> 11) & 0x1f) << 5 | ((c >> 19) & 0x1f));
    }
    inline fn binCh(b: u16, ch: u2) u32 {
        return (@as(u32, b) >> (10 - @as(u4, ch) * 5)) & 0x1f;
    }

    /// Exact palette of the opaque pixels (`eff` values < 2^24); false if more than `cap`.
    fn exact(q: *Quant, ids: []const u32, cap: usize) bool {
        @memset(&q.ents, 0);
        q.n = 0;
        var last: u32 = 0xFF000000;
        for (ids) |c| {
            if (c == last or c >> 24 != 0) continue;
            last = c;
            if (q.find(c) == null) {
                if (q.n == cap) return false;
                q.insert(c);
            }
        }
        return true;
    }
    fn find(q: *Quant, c: u32) ?u8 {
        var s = (c *% 0x9E3779B1) >> 22;
        while (true) : (s = (s + 1) & 1023) {
            const e = q.ents[s];
            if (e == 0) return null;
            if (q.keys[s] == c) return @intCast(e - 1);
        }
    }
    fn insert(q: *Quant, c: u32) void {
        var s = (c *% 0x9E3779B1) >> 22;
        while (q.ents[s] != 0) s = (s + 1) & 1023;
        q.keys[s] = c;
        q.pal[q.n] = .{ @truncate(c), @truncate(c >> 8), @truncate(c >> 16) };
        q.n += 1;
        q.ents[s] = @intCast(q.n);
    }

    const Box = struct { lo: u32, hi: u32, score: f64, ch: u2, cut: u32 };

    /// Finds the channel with the largest weighted SSE and the cut level on it that
    /// minimises the two halves' SSE (variance-based median cut on 5-bit levels).
    fn analyze(q: *const Quant, b: *Box) void {
        var cnt: [3][32]u32 = @splat(@splat(0));
        for (q.bins[b.lo..b.hi]) |bn| {
            const n = q.hist[bn];
            inline for (0..3) |ch| cnt[ch][binCh(bn, ch)] += n;
        }
        b.score = 0;
        for (0..3) |ch| {
            var n: f64 = 0;
            var s: f64 = 0;
            var ss: f64 = 0;
            for (cnt[ch], 0..) |c, l| {
                const fc: f64 = @floatFromInt(c);
                const fl: f64 = @floatFromInt(l);
                n += fc;
                s += fc * fl;
                ss += fc * fl * fl;
            }
            if (n == 0) return;
            const sse = ss - s * s / n;
            if (sse <= b.score) continue;
            // best cut: maximise sL^2/nL + sR^2/nR
            var nl: f64 = 0;
            var sl: f64 = 0;
            var best: f64 = -1;
            var cut: u32 = 0;
            for (0..31) |l| {
                const fc: f64 = @floatFromInt(cnt[ch][l]);
                nl += fc;
                sl += fc * @as(f64, @floatFromInt(l));
                const nr = n - nl;
                if (nl == 0 or nr == 0) continue;
                const sr = s - sl;
                const v = sl * sl / nl + sr * sr / nr;
                if (v > best) {
                    best = v;
                    cut = @intCast(l);
                }
            }
            if (best < 0) continue;
            b.score = sse;
            b.ch = @intCast(ch);
            b.cut = cut;
        }
    }

    /// Median cut to at most `cap` colours over the opaque pixels of `ids`.
    fn medianCut(q: *Quant, ids: []const u32, cap: usize) void {
        @memset(&q.hist, 0);
        for (ids) |c| {
            if (c >> 24 == 0) q.hist[bin(c)] += 1;
        }
        var nb: u32 = 0;
        for (0..nbins) |bn| if (q.hist[bn] != 0) {
            q.bins[nb] = @intCast(bn);
            nb += 1;
        };
        const boxes = &q.boxes;
        boxes[0] = .{ .lo = 0, .hi = nb, .score = 0, .ch = 0, .cut = 0 };
        q.analyze(&boxes[0]);
        var nbox: usize = 1;
        while (nbox < cap) {
            var bi: usize = 0;
            for (boxes[0..nbox], 0..) |b, k| if (b.score > boxes[bi].score) {
                bi = k;
            };
            const b = &boxes[bi];
            if (b.score <= 0) break;
            // partition: level <= cut to the left
            var lo = b.lo;
            var hi = b.hi;
            while (lo < hi) {
                if (binCh(q.bins[lo], b.ch) <= b.cut) {
                    lo += 1;
                } else {
                    hi -= 1;
                    std.mem.swap(u16, &q.bins[lo], &q.bins[hi]);
                }
            }
            boxes[nbox] = .{ .lo = lo, .hi = b.hi, .score = 0, .ch = 0, .cut = 0 };
            b.hi = lo;
            q.analyze(b);
            q.analyze(&boxes[nbox]);
            nbox += 1;
        }
        for (boxes[0..nbox], 0..) |b, k| {
            for (q.bins[b.lo..b.hi]) |bn| q.binbox[bn] = @intCast(k);
        }
        q.n = nbox;
        // Palette = mean of the actual colours in each box. (A k-means refinement pass was
        // measured: mean error 1.40 -> 1.39 on a photo, not worth the time.)
        @memset(q.sums[0..nbox], @splat(0));
        for (ids) |c| {
            if (c >> 24 != 0) continue;
            const s = &q.sums[q.binbox[bin(c)]];
            s[0] += c & 0xff;
            s[1] += (c >> 8) & 0xff;
            s[2] += (c >> 16) & 0xff;
            s[3] += 1;
        }
        for (0..nbox) |k| {
            const s = q.sums[k];
            const n = @max(s[3], 1);
            for (0..3) |ch| q.pal[k][ch] = @intCast((s[ch] + n / 2) / n);
        }
        @memset(&q.cache, 0xffff);
    }

    fn nearest(q: *Quant, c: u32) u8 {
        const b = bin(c);
        if (q.cache[b] != 0xffff) return @intCast(q.cache[b]);
        // nearest palette entry to the bin centre
        const r: i32 = @intCast((binCh(b, 0) << 3) | 4);
        const g: i32 = @intCast((binCh(b, 1) << 3) | 4);
        const bl: i32 = @intCast((binCh(b, 2) << 3) | 4);
        var best: i32 = std.math.maxInt(i32);
        var bi: u16 = 0;
        for (q.pal[0..q.n], 0..) |p, k| {
            const dr = r - p[0];
            const dg = g - p[1];
            const db = bl - p[2];
            const d = dr * dr + dg * dg + db * db;
            if (d < best) {
                best = d;
                bi = @intCast(k);
            }
        }
        q.cache[b] = bi;
        return @intCast(bi);
    }
};

/// GIF LZW (variable code size, clear code when the table reaches 4096) into 255-byte sub-blocks.
fn lzw(alloc: std.mem.Allocator, out: *Out, tab: []u32, data: []const u8, min_size: u5) EncodeError!void {
    try out.append(alloc, min_size);
    const W = struct {
        out: *Out,
        alloc: std.mem.Allocator,
        acc: u32 = 0,
        nb: u5 = 0,
        blk: [256]u8 = undefined,
        bl: usize = 1,
        fn emit(s: *@This(), code: u32, size: u5) EncodeError!void {
            s.acc |= code << s.nb;
            s.nb += size;
            while (s.nb >= 8) {
                try s.byte(@truncate(s.acc));
                s.acc >>= 8;
                s.nb -= 8;
            }
        }
        fn byte(s: *@This(), b: u8) EncodeError!void {
            s.blk[s.bl] = b;
            s.bl += 1;
            if (s.bl == 256) try s.flush();
        }
        fn flush(s: *@This()) EncodeError!void {
            if (s.bl == 1) return;
            s.blk[0] = @intCast(s.bl - 1);
            try s.out.appendSlice(s.alloc, s.blk[0..s.bl]);
            s.bl = 1;
        }
    };
    var bw = W{ .out = out, .alloc = alloc };
    const clear: u32 = @as(u32, 1) << min_size;
    var next = clear + 2;
    var size: u5 = min_size + 1;
    @memset(tab, 0);
    try bw.emit(clear, size);
    var prefix: u32 = data[0];
    for (data[1..]) |c| {
        const key = (prefix << 8) | c;
        var hs = (key *% 0x9E3779B1) >> 19;
        while (true) : (hs = (hs + 1) & 8191) {
            const e = tab[hs];
            if (e == 0) break;
            if (e >> 12 == key) break;
        }
        if (tab[hs] != 0) {
            prefix = tab[hs] & 0xfff;
            continue;
        }
        try bw.emit(prefix, size);
        if (next < 4096) {
            tab[hs] = (key << 12) | next;
            next += 1;
            if (next > (@as(u32, 1) << size) and size < 12) size += 1;
        } else {
            try bw.emit(clear, size);
            @memset(tab, 0);
            next = clear + 2;
            size = min_size + 1;
        }
        prefix = c;
    }
    try bw.emit(prefix, size);
    // the decoder adds one more entry after reading the last code
    if (next < 4096) {
        next += 1;
        if (next > (@as(u32, 1) << size) and size < 12) size += 1;
    }
    try bw.emit(clear + 1, size);
    if (bw.nb > 0) try bw.byte(@truncate(bw.acc));
    try bw.flush();
    try out.append(alloc, 0);
}

/// Animated GIF89a: NETSCAPE2.0 loop extension, one local colour table per frame (exact when
/// the frame has <= 256 colours, or <= 255 plus a transparent index; otherwise a variance-based
/// median cut on a 15-bit histogram with nearest-colour mapping, no dithering), delay
/// ceil(ms/10) centiseconds like takumi. Disposal is 1 (keep) except before a frame that needs
/// transparency where the canvas is opaque: then the earlier frame covers the whole canvas and
/// uses disposal 2 (clear). With `frame_diff`, frames after the first are cropped to the changed
/// rectangle and unchanged pixels become transparent. Canvas <= 65535 per side.
pub fn encodeGif(alloc: std.mem.Allocator, frames: []const AnimFrame, w: u32, h: u32, opts: AnimOptions) EncodeError![]u8 {
    const npx = try validate(frames, w, h, 65535);
    if (npx > 1 << 30) return error.InvalidInput; // u32 histogram counts
    const thr = opts.gif_alpha_threshold;
    const q = try alloc.create(Quant);
    defer alloc.destroy(q);
    const tab = try alloc.alloc(u32, 8192);
    defer alloc.free(tab);
    const ids = try alloc.alloc(u32, npx); // effective pixels of the frame rectangle
    defer alloc.free(ids);
    const idx = try alloc.alloc(u8, npx);
    defer alloc.free(idx);

    var out: Out = .empty;
    errdefer out.deinit(alloc);
    var hdr: [13 + 19]u8 = .{ 'G', 'I', 'F', '8', '9', 'a', 0, 0, 0, 0, 0, 0, 0 } ++
        .{ 0x21, 0xff, 0x0b, 'N', 'E', 'T', 'S', 'C', 'A', 'P', 'E', '2', '.', '0', 3, 1, 0, 0, 0 };
    putLe16(hdr[6..8], w);
    putLe16(hdr[8..10], h);
    putLe16(hdr[29..31], opts.loop_count);
    try out.appendSlice(alloc, &hdr);

    var prev: ?[]const u8 = null; // last frame shown and kept on the canvas; null = cleared canvas
    var i: usize = 0;
    while (i < frames.len) {
        const cur = frames[i].rgba;
        var delay: u64 = frames[i].delay_ms;
        var j = i + 1;
        if (opts.frame_diff) {
            outer: while (j < frames.len) : (j += 1) {
                const nx = frames[j].rgba;
                for (0..npx) |k| if (eff(px(cur, k), thr) != eff(px(nx, k), thr)) break :outer;
                delay += frames[j].delay_ms;
            }
        }
        // Does the next frame need transparency where this one is opaque?
        var clear_after = false;
        if (j < frames.len and thr > 0) {
            const nx = frames[j].rgba;
            for (0..npx) |k| {
                if (nx[k * 4 + 3] < thr and cur[k * 4 + 3] >= thr) {
                    clear_after = true;
                    break;
                }
            }
        }
        const use_diff = opts.frame_diff and i > 0 and !clear_after;
        var r = Rect{ .x = 0, .y = 0, .w = w, .h = h };
        if (use_diff) {
            var x0: u32 = w;
            var x1: u32 = 0;
            var y0: u32 = h;
            var y1: u32 = 0;
            var k: usize = 0;
            for (0..h) |y| {
                for (0..w) |x| {
                    const c = eff(px(cur, k), thr);
                    const p = if (prev) |pv| eff(px(pv, k), thr) else 0xFF000000;
                    if (c != p) {
                        x0 = @min(x0, @as(u32, @intCast(x)));
                        x1 = @max(x1, @as(u32, @intCast(x)));
                        y0 = @min(y0, @as(u32, @intCast(y)));
                        y1 = @intCast(y);
                    }
                    k += 1;
                }
            }
            r = if (y0 == h) .{ .x = 0, .y = 0, .w = 1, .h = 1 } else .{ .x = x0, .y = y0, .w = x1 + 1 - x0, .h = y1 + 1 - y0 };
        }
        // Effective pixels of the rectangle (unchanged ones -> transparent when diffing).
        const n = @as(usize, r.w) * r.h;
        var need_t = false;
        {
            var o: usize = 0;
            for (0..r.h) |yy| {
                var k = (@as(usize, r.y) + yy) * w + r.x;
                for (0..r.w) |_| {
                    var c = eff(px(cur, k), thr);
                    if (use_diff) {
                        const p = if (prev) |pv| eff(px(pv, k), thr) else 0xFF000000;
                        if (c == p) c = 0xFF000000;
                    }
                    need_t = need_t or c >> 24 != 0;
                    ids[o] = c;
                    o += 1;
                    k += 1;
                }
            }
        }
        const cap: usize = if (need_t) 255 else 256;
        const ex = q.exact(ids[0..n], cap);
        if (!ex) q.medianCut(ids[0..n], cap);
        const tidx: u8 = @intCast(@min(q.n, 255));
        for (ids[0..n], idx[0..n]) |c, *o| {
            o.* = if (c >> 24 != 0) tidx else if (ex) q.find(c).? else q.nearest(c);
        }
        const total = q.n + @intFromBool(need_t);
        var bits: u5 = 1;
        while ((@as(usize, 1) << bits) < total) bits += 1;

        const disposal: u8 = if (clear_after) 2 else 1;
        const cs: u64 = @min((delay + 9) / 10, 0xffff);
        var fh: [8 + 10]u8 = .{ 0x21, 0xf9, 4, (disposal << 2) | @intFromBool(need_t), 0, 0, tidx, 0, 0x2c, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        putLe16(fh[4..6], @intCast(cs));
        putLe16(fh[9..11], r.x);
        putLe16(fh[11..13], r.y);
        putLe16(fh[13..15], r.w);
        putLe16(fh[15..17], r.h);
        fh[17] = 0x80 | @as(u8, bits - 1);
        const ct_len = @as(usize, 3) << bits;
        try out.ensureUnusedCapacity(alloc, fh.len + ct_len);
        out.appendSliceAssumeCapacity(&fh);
        for (0..@as(usize, 1) << bits) |k| {
            out.appendSliceAssumeCapacity(if (k < q.n) &q.pal[k] else &[3]u8{ 0, 0, 0 });
        }
        try lzw(alloc, &out, tab, idx[0..n], @max(bits, 2));

        prev = if (clear_after) null else cur;
        i = j;
    }
    try out.append(alloc, 0x3b);
    return out.toOwnedSlice(alloc);
}

// =============================================================================== tests

const testing = std.testing;
const webp_dec = @import("webp_dec.zig");
const gif_dec = @import("gif.zig");

fn testFrames(comptime n: usize, w: u32, h: u32) ![n][]u8 {
    var fs: [n][]u8 = undefined;
    for (&fs, 0..) |*f, fi| {
        f.* = try testing.allocator.alloc(u8, @as(usize, w) * h * 4);
        for (0..h) |y| for (0..w) |x| {
            const o = (y * w + x) * 4;
            // flat background + a moving 5x4 square
            const in_sq = x >= fi * 3 and x < fi * 3 + 5 and y >= 2 and y < 6;
            f.*[o..][0..4].* = if (in_sq) .{ 200, 30, 40, 255 } else .{ @intCast((x % 8) * 30), @intCast((y % 4) * 60), 90, 255 };
        };
    }
    return fs;
}

fn freeFrames(fs: anytype) void {
    for (fs) |f| testing.allocator.free(f);
}

test "apng structure and per-frame round trip" {
    const w = 23;
    const h = 11;
    var fs = try testFrames(3, w, h);
    defer freeFrames(&fs);
    fs[2][5] = 7; // alpha < 255 in one pixel -> RGBA for all frames
    fs[2][7] = 7;
    var frames: [3]AnimFrame = undefined;
    for (&frames, 0..) |*f, k| f.* = .{ .rgba = fs[k], .delay_ms = 120 + @as(u32, @intCast(k)) };
    const a = try encodeApng(testing.allocator, &frames, w, h, .{ .loop_count = 3 });
    defer testing.allocator.free(a);

    // default image (frame 0) via the plain PNG decoder
    const img = try png.decode(testing.allocator, a, .{});
    defer img.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, fs[0], img.data);

    // walk chunks, rebuild each frame as a standalone PNG
    var pos: usize = 8;
    var seq: u32 = 0;
    var ihdr: []const u8 = &.{};
    var fidx: usize = 0;
    var data: std.ArrayList(u8) = .empty;
    defer data.deinit(testing.allocator);
    var nframes: usize = 0;
    while (pos < a.len) {
        const len = byt.be32(a, pos);
        const typ = a[pos + 4 ..][0..4];
        const d = a[pos + 8 ..][0..len];
        try testing.expectEqual(checksum.crc32(0, a[pos + 4 .. pos + 8 + len]), byt.be32(a, pos + 8 + len));
        pos += 12 + len;
        const flush = std.mem.eql(u8, typ, "fcTL") or std.mem.eql(u8, typ, "IEND");
        if (flush and data.items.len > 0) {
            var o: Out = .empty;
            defer o.deinit(testing.allocator);
            try o.appendSlice(testing.allocator, &png.signature);
            try pngChunk(testing.allocator, &o, "IHDR", ihdr, "");
            try pngChunk(testing.allocator, &o, "IDAT", data.items, "");
            try pngChunk(testing.allocator, &o, "IEND", "", "");
            const im = try png.decode(testing.allocator, o.items, .{});
            defer im.deinit(testing.allocator);
            try testing.expectEqualSlices(u8, fs[fidx], im.data);
            fidx += 1;
            data.clearRetainingCapacity();
        }
        if (std.mem.eql(u8, typ, "IHDR")) {
            ihdr = d;
            try testing.expectEqual(@as(u8, 6), d[9]);
        } else if (std.mem.eql(u8, typ, "acTL")) {
            try testing.expectEqual(@as(u32, 3), byt.be32(d, 0));
            try testing.expectEqual(@as(u32, 3), byt.be32(d, 4));
        } else if (std.mem.eql(u8, typ, "fcTL")) {
            try testing.expectEqual(seq, byt.be32(d, 0));
            seq += 1;
            try testing.expectEqual(@as(u32, w), byt.be32(d, 4));
            try testing.expectEqual(@as(u16, 120 + @as(u16, @intCast(nframes))), byt.be16(d, 20));
            try testing.expectEqual(@as(u16, 1000), byt.be16(d, 22));
            try testing.expectEqual(@as(u16, 0), byt.be16(d, 24));
            nframes += 1;
        } else if (std.mem.eql(u8, typ, "fdAT")) {
            try testing.expectEqual(seq, byt.be32(d, 0));
            seq += 1;
            try data.appendSlice(testing.allocator, d[4..]);
        } else if (std.mem.eql(u8, typ, "IDAT")) {
            try data.appendSlice(testing.allocator, d);
        }
    }
    try testing.expectEqual(@as(usize, 3), fidx);

    // opaque frames -> RGB
    fs[2][7] = 255;
    const b = try encodeApng(testing.allocator, &frames, w, h, .{});
    defer testing.allocator.free(b);
    try testing.expectEqual(@as(u8, 2), b[8 + 8 + 9]);
    try testing.expectError(error.InvalidInput, encodeApng(testing.allocator, frames[0..0], w, h, .{}));
    try testing.expectError(error.InvalidInput, encodeApng(testing.allocator, &frames, w, h + 1, .{}));
}

/// Decodes an animated WebP produced by encodeWebpAnim (no-blend frames) into canvases.
fn webpCanvases(bytes: []const u8, w: u32, h: u32, out: *std.ArrayList([]u8), durs: *std.ArrayList(u32)) !void {
    try testing.expect(std.mem.eql(u8, bytes[0..4], "RIFF") and std.mem.eql(u8, bytes[8..16], "WEBPVP8X"));
    try testing.expectEqual(@as(u32, @intCast(bytes.len - 8)), byt.le32(bytes, 4));
    try testing.expectEqual(@as(u8, 0x02), bytes[20] & 0x02);
    var canvas = try testing.allocator.alloc(u8, @as(usize, w) * h * 4);
    defer testing.allocator.free(canvas);
    @memset(canvas, 0);
    var pos: usize = 12;
    while (pos + 8 <= bytes.len) {
        const len = byt.le32(bytes, pos + 4);
        const typ = bytes[pos..][0..4];
        const d = bytes[pos + 8 ..][0..len];
        pos += 8 + len + (len & 1);
        if (!std.mem.eql(u8, typ, "ANMF")) continue;
        const fx = (byt.le32(d, 0) & 0xffffff) * 2;
        const fy = (byt.le32(d, 3) & 0xffffff) * 2;
        const fw = (byt.le32(d, 6) & 0xffffff) + 1;
        const fh = (byt.le32(d, 9) & 0xffffff) + 1;
        try durs.append(testing.allocator, byt.le32(d, 12) & 0xffffff);
        try testing.expectEqual(@as(u8, 2), d[15]);
        try testing.expect(std.mem.eql(u8, d[16..20], "VP8L"));
        const im = try webp_dec.decodeVp8l(testing.allocator, d[24..][0..byt.le32(d, 20)], .{});
        defer im.deinit(testing.allocator);
        try testing.expectEqual(fw, im.width);
        try testing.expectEqual(fh, im.height);
        for (0..fh) |yy| @memcpy(canvas[((fy + yy) * w + fx) * 4 ..][0 .. fw * 4], im.data[yy * fw * 4 ..][0 .. fw * 4]);
        try out.append(testing.allocator, try testing.allocator.dupe(u8, canvas));
    }
}

test "animated webp round trip, diff crop and merge" {
    const w = 31;
    const h = 9;
    var fs = try testFrames(4, w, h);
    defer freeFrames(&fs);
    @memcpy(fs[2], fs[1]); // identical -> merged
    fs[3][0] = 1;
    fs[3][3] = 0; // transparent pixel
    var frames: [4]AnimFrame = undefined;
    for (&frames, 0..) |*f, k| f.* = .{ .rgba = fs[k], .delay_ms = 100 };
    for ([_]bool{ true, false }) |diff| {
        const a = try encodeWebpAnim(testing.allocator, &frames, w, h, .{ .loop_count = 7, .frame_diff = diff });
        defer testing.allocator.free(a);
        try testing.expectEqual(@as(u8, 0x12), a[20]);
        try testing.expectEqual(@as(u16, 7), byt.le16(a, 42));
        var cv: std.ArrayList([]u8) = .empty;
        defer {
            for (cv.items) |c| testing.allocator.free(c);
            cv.deinit(testing.allocator);
        }
        var durs: std.ArrayList(u32) = .empty;
        defer durs.deinit(testing.allocator);
        try webpCanvases(a, w, h, &cv, &durs);
        const expect_idx: []const usize = if (diff) &.{ 0, 1, 3 } else &.{ 0, 1, 2, 3 };
        try testing.expectEqual(expect_idx.len, cv.items.len);
        for (expect_idx, cv.items) |k, c| try testing.expectEqualSlices(u8, fs[k], c);
        if (diff) try testing.expectEqualSlices(u32, &.{ 100, 200, 100 }, durs.items);
    }
}

// ------------------------------------------------------------------ test-only GIF decoder

const GifFrameOut = struct { canvas: []u8, delay_cs: u16, disposal: u8 };

fn lzwDecode(data: []const u8, min_size: u5, out: []u8) !usize {
    var prefix: [4096]u16 = undefined;
    var suffix: [4096]u8 = undefined;
    var stack: [4097]u8 = undefined;
    const clear: u32 = @as(u32, 1) << min_size;
    var size: u5 = min_size + 1;
    var next: u32 = clear + 2;
    var old: ?u32 = null;
    var first: u8 = 0;
    var acc: u32 = 0;
    var nb: u5 = 0;
    var bp: usize = 0;
    var o: usize = 0;
    while (true) {
        while (nb < size) {
            if (bp >= data.len) return error.Truncated;
            acc |= @as(u32, data[bp]) << nb;
            bp += 1;
            nb += 8;
        }
        const code = acc & ((@as(u32, 1) << size) - 1);
        acc >>= size;
        nb -= size;
        if (code == clear) {
            size = min_size + 1;
            next = clear + 2;
            old = null;
            continue;
        }
        if (code == clear + 1) break;
        var sp: usize = 0;
        var c = code;
        if (old == null) {
            if (code >= clear) return error.BadCode;
            stack[0] = @intCast(code);
            sp = 1;
        } else {
            if (code > next) return error.BadCode;
            if (code == next) {
                if (next >= 4096) return error.BadCode;
                stack[0] = first;
                sp = 1;
                c = old.?;
            }
            while (c >= clear) {
                stack[sp] = suffix[c];
                sp += 1;
                c = prefix[c];
            }
            stack[sp] = @intCast(c);
            sp += 1;
        }
        first = stack[sp - 1];
        while (sp > 0) {
            sp -= 1;
            if (o >= out.len) return error.Overflow;
            out[o] = stack[sp];
            o += 1;
        }
        if (old) |ov| if (next < 4096) {
            prefix[next] = @intCast(ov);
            suffix[next] = first;
            next += 1;
            if (next == (@as(u32, 1) << size) and size < 12) size += 1;
        };
        old = code;
    }
    return o;
}

/// Strict test decoder: composites every frame (disposal 1/2) and records canvases.
fn gifCanvases(bytes: []const u8, frames: *std.ArrayList(GifFrameOut)) !void {
    try testing.expect(std.mem.eql(u8, bytes[0..6], "GIF89a"));
    const w: usize = byt.le16(bytes, 6);
    const h: usize = byt.le16(bytes, 8);
    const canvas = try testing.allocator.alloc(u8, w * h * 4);
    defer testing.allocator.free(canvas);
    @memset(canvas, 0);
    var pos: usize = 13;
    var gce_flags: u8 = 0;
    var delay: u16 = 0;
    var tidx: u8 = 0;
    var last_disposal: u8 = 0;
    var last_rect = [4]usize{ 0, 0, 0, 0 };
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const idx = try testing.allocator.alloc(u8, w * h + 1);
    defer testing.allocator.free(idx);
    while (true) {
        const t = bytes[pos];
        pos += 1;
        if (t == 0x3b) break;
        if (t == 0x21) {
            const label = bytes[pos];
            pos += 1;
            if (label == 0xf9) {
                gce_flags = bytes[pos + 1];
                delay = byt.le16(bytes, pos + 2);
                tidx = bytes[pos + 4];
            }
            while (bytes[pos] != 0) pos += 1 + @as(usize, bytes[pos]);
            pos += 1;
            continue;
        }
        try testing.expectEqual(@as(u8, 0x2c), t);
        if (last_disposal == 2) {
            for (0..last_rect[3]) |yy| @memset(canvas[((last_rect[1] + yy) * w + last_rect[0]) * 4 ..][0 .. last_rect[2] * 4], 0);
        }
        const fx: usize = byt.le16(bytes, pos);
        const fy: usize = byt.le16(bytes, pos + 2);
        const fw: usize = byt.le16(bytes, pos + 4);
        const fh: usize = byt.le16(bytes, pos + 6);
        const pk = bytes[pos + 8];
        pos += 9;
        try testing.expect(pk & 0x80 != 0);
        const ct = bytes[pos..][0 .. @as(usize, 3) << @intCast((pk & 7) + 1)];
        pos += ct.len;
        const mcs: u5 = @intCast(bytes[pos]);
        pos += 1;
        buf.clearRetainingCapacity();
        while (bytes[pos] != 0) {
            try buf.appendSlice(testing.allocator, bytes[pos + 1 ..][0..bytes[pos]]);
            pos += 1 + @as(usize, bytes[pos]);
        }
        pos += 1;
        const got = try lzwDecode(buf.items, mcs, idx);
        try testing.expectEqual(fw * fh, got);
        for (0..fh) |yy| for (0..fw) |xx| {
            const v = idx[yy * fw + xx];
            if (gce_flags & 1 != 0 and v == tidx) continue;
            const o = ((fy + yy) * w + fx + xx) * 4;
            canvas[o..][0..3].* = ct[@as(usize, v) * 3 ..][0..3].*;
            canvas[o + 3] = 255;
        };
        last_disposal = (gce_flags >> 2) & 7;
        last_rect = .{ fx, fy, fw, fh };
        try frames.append(testing.allocator, .{ .canvas = try testing.allocator.dupe(u8, canvas), .delay_cs = delay, .disposal = last_disposal });
    }
}

fn freeGif(l: *std.ArrayList(GifFrameOut)) void {
    for (l.items) |f| testing.allocator.free(f.canvas);
    l.deinit(testing.allocator);
}

fn expectGifEq(want: []const u8, got: []const u8, thr: u8) !void {
    for (0..want.len / 4) |k| {
        const a = want[k * 4 ..][0..4];
        const b = got[k * 4 ..][0..4];
        if (a[3] < thr) {
            try testing.expectEqual(@as(u8, 0), b[3]);
        } else {
            try testing.expectEqualSlices(u8, a[0..3], b[0..3]);
            try testing.expectEqual(@as(u8, 255), b[3]);
        }
    }
}

test "gif exact frames, diff, merge, transparency clear" {
    const w = 37;
    const h = 13;
    var fs = try testFrames(5, w, h);
    defer freeFrames(&fs);
    @memcpy(fs[2], fs[1]); // merged
    // frame 3: punch a transparent hole where frame 1 is opaque -> frame 1 must use disposal 2
    for (0..3) |k| fs[3][(5 * w + 10 + k) * 4 + 3] = 0;
    fs[4][3] = 100; // semi-transparent, opaque at threshold 1, transparent at 128
    var frames: [5]AnimFrame = undefined;
    for (&frames, 0..) |*f, k| f.* = .{ .rgba = fs[k], .delay_ms = 95 };
    for ([_]u8{ 1, 128 }) |thr| for ([_]bool{ true, false }) |diff| {
        const g = try encodeGif(testing.allocator, &frames, w, h, .{ .frame_diff = diff, .gif_alpha_threshold = thr, .loop_count = 7 });
        defer testing.allocator.free(g);
        try testing.expectEqual(@as(u16, 7), byt.le16(g, 29));
        // frame 0 via the production first-frame decoder
        const im = try gif_dec.decode(testing.allocator, g, .{});
        defer im.deinit(testing.allocator);
        try expectGifEq(fs[0], im.data, thr);
        var l: std.ArrayList(GifFrameOut) = .empty;
        defer freeGif(&l);
        try gifCanvases(g, &l);
        const expect_idx: []const usize = if (diff) &.{ 0, 1, 3, 4 } else &.{ 0, 1, 2, 3, 4 };
        try testing.expectEqual(expect_idx.len, l.items.len);
        for (expect_idx, l.items) |k, f| try expectGifEq(fs[k], f.canvas, thr);
        try testing.expectEqual(@as(u16, if (diff) 19 else 10), l.items[1].delay_cs);
        try testing.expectEqual(@as(u8, 2), l.items[expect_idx.len - 3].disposal);
    };
    try testing.expectError(error.InvalidInput, encodeGif(testing.allocator, &frames, 0, h, .{}));
}

test "gif quantised photo frame and lzw table resets" {
    const w = 160;
    const h = 120;
    const f = try testing.allocator.alloc(u8, w * h * 4);
    defer testing.allocator.free(f);
    var seed: u32 = 1;
    for (0..h) |y| for (0..w) |x| {
        seed = seed *% 1103515245 +% 12345;
        const nz: u32 = (seed >> 16) % 24;
        const o = (y * w + x) * 4;
        f[o..][0..4].* = .{ @intCast((x * 255 / w + nz) % 256), @intCast((y * 255 / h + nz / 2) % 256), @intCast(((x + y) * 128 / (w + h) + nz) % 256), 255 };
    };
    // second frame: exact palette of 300 colours would not fit; third: transparent left half
    const f2 = try testing.allocator.dupe(u8, f);
    defer testing.allocator.free(f2);
    for (0..h) |y| for (0..w / 2) |x| {
        f2[(y * w + x) * 4 + 3] = 0;
    };
    const frames = [_]AnimFrame{ .{ .rgba = f, .delay_ms = 40 }, .{ .rgba = f2, .delay_ms = 40 } };
    const g = try encodeGif(testing.allocator, &frames, w, h, .{});
    defer testing.allocator.free(g);
    var l: std.ArrayList(GifFrameOut) = .empty;
    defer freeGif(&l);
    try gifCanvases(g, &l);
    try testing.expectEqual(@as(usize, 2), l.items.len);
    var sum: u64 = 0;
    var mx: u32 = 0;
    for (0..w * h) |k| for (0..3) |c| {
        const d: u32 = @abs(@as(i32, f[k * 4 + c]) - l.items[0].canvas[k * 4 + c]);
        sum += d;
        mx = @max(mx, d);
    };
    const mean = @as(f64, @floatFromInt(sum)) / (w * h * 3);
    try testing.expect(mean < 5.0);
    try testing.expect(mx < 40);
    // frame 1: right half quantised, left half transparent
    for (0..h) |y| for (0..w) |x| {
        const a = l.items[1].canvas[(y * w + x) * 4 + 3];
        try testing.expectEqual(@as(u8, if (x < w / 2) 0 else 255), a);
    };
}

test "lzw round trip incl. clear codes and code size 2..8" {
    const n = 70000;
    const data = try testing.allocator.alloc(u8, n);
    defer testing.allocator.free(data);
    const back = try testing.allocator.alloc(u8, n);
    defer testing.allocator.free(back);
    const tab = try testing.allocator.alloc(u32, 8192);
    defer testing.allocator.free(tab);
    var seed: u32 = 7;
    for ([_]u5{ 2, 3, 5, 8 }) |ms| {
        for (data, 0..) |*d, k| {
            seed = seed *% 1664525 +% 1013904223;
            const r: u8 = @truncate(seed >> 24);
            d.* = if (k % 97 < 40) @truncate(k / 13) else r;
            d.* &= @truncate((@as(u32, 1) << ms) - 1);
        }
        for ([_]usize{ 1, 2, 300, n }) |len| {
            var o: Out = .empty;
            defer o.deinit(testing.allocator);
            try lzw(testing.allocator, &o, tab, data[0..len], ms);
            var b: std.ArrayList(u8) = .empty;
            defer b.deinit(testing.allocator);
            var p: usize = 1;
            while (o.items[p] != 0) {
                try testing.expect(o.items[p] <= 255);
                try b.appendSlice(testing.allocator, o.items[p + 1 ..][0..o.items[p]]);
                p += 1 + @as(usize, o.items[p]);
            }
            try testing.expectEqual(o.items.len, p + 1);
            const got = try lzwDecode(b.items, ms, back);
            try testing.expectEqualSlices(u8, data[0..len], back[0..got]);
        }
    }
}
