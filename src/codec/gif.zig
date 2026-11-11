//! GIF decoder (GIF87a/89a): LZW, global/local colour tables, GCE transparency / disposal /
//! delay, interlaced frames. `decode` returns the first frame on a fully transparent canvas
//! of the logical screen size; `Gif` + `drawFrame` give every frame (compositing: anim.zig).
//! Untrusted input: all reads bounds-checked; allocation bounded by `Limits.max_pixels`.
const std = @import("std");
const types = @import("types.zig");

const Image = types.Image;
const Limits = types.Limits;
const Error = types.Error;

pub fn dimensions(bytes: []const u8) ?[2]u32 {
    if (bytes.len < 10 or !std.mem.eql(u8, bytes[0..3], "GIF")) return null;
    const w = rd16(bytes, 6);
    const h = rd16(bytes, 8);
    if (w == 0 or h == 0) return null;
    return .{ w, h };
}

inline fn rd16(b: []const u8, i: usize) u32 {
    return @as(u32, b[i]) | (@as(u32, b[i + 1]) << 8);
}

const Reader = struct {
    b: []const u8,
    pos: usize,
    fn byte(r: *Reader) Error!u8 {
        if (r.pos >= r.b.len) return error.InvalidData;
        r.pos += 1;
        return r.b[r.pos - 1];
    }
    fn take(r: *Reader, n: usize) Error![]const u8 {
        if (n > r.b.len - r.pos) return error.InvalidData;
        r.pos += n;
        return r.b[r.pos - n .. r.pos];
    }
    fn skipSubBlocks(r: *Reader) Error!void {
        while (true) {
            const n = try r.byte();
            if (n == 0) return;
            _ = try r.take(n);
        }
    }
};

/// Decodes the first frame of a GIF onto a transparent canvas of the logical screen size.
pub fn decode(alloc: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!Image {
    var g = try Gif.init(bytes);
    const fd = (try g.next()) orelse return error.InvalidData;
    const sz = g.canvasSize(fd);
    const nbytes = try types.checkSize(sz[0], sz[1], limits);
    const out = try alloc.alloc(u8, nbytes);
    errdefer alloc.free(out);
    @memset(out, 0);
    try drawFrame(alloc, bytes, fd, out, sz[0], sz[1], limits);
    return .{ .width = sz[0], .height = sz[1], .data = out };
}

/// One image descriptor plus the Graphic Control Extension that preceded it.
pub const FrameDesc = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    /// Colour table (global or local), 3 bytes per entry.
    ct: []const u8,
    transparent: ?u8,
    /// GCE disposal method (0/1 = keep, 2 = restore to background, 3 = restore previous).
    disposal: u3,
    delay_cs: u16,
    interlaced: bool,
    min_size: u8,
    /// Offset of the first LZW data sub-block (after the min code size byte).
    data_pos: usize,
};

/// Streaming GIF parser (frames in file order).
pub const Gif = struct {
    r: Reader,
    sw: u32,
    sh: u32,
    gct: []const u8,

    pub fn init(bytes: []const u8) Error!Gif {
        if (bytes.len < 13 or !std.mem.eql(u8, bytes[0..3], "GIF")) return error.InvalidData;
        const flags = bytes[10];
        var g = Gif{ .r = .{ .b = bytes, .pos = 13 }, .sw = rd16(bytes, 6), .sh = rd16(bytes, 8), .gct = &.{} };
        if (flags & 0x80 != 0) g.gct = try g.r.take(@as(usize, 3) << @intCast((flags & 7) + 1));
        return g;
    }

    /// Canvas size: the logical screen, or the first frame's extent when that is 0x0.
    pub fn canvasSize(g: *const Gif, first: FrameDesc) [2]u32 {
        if (g.sw == 0 or g.sh == 0) return .{ first.x + first.w, first.y + first.h };
        return .{ g.sw, g.sh };
    }

    /// Next frame, or null at the trailer / end of data.
    pub fn next(g: *Gif) Error!?FrameDesc {
        const r = &g.r;
        var transparent: ?u8 = null;
        var disposal: u3 = 0;
        var delay: u16 = 0;
        while (true) {
            if (r.pos >= r.b.len) return null;
            const tag = try r.byte();
            switch (tag) {
                0x21 => {
                    const label = try r.byte();
                    if (label == 0xf9) {
                        const n = try r.byte();
                        const blk = try r.take(n);
                        if (n >= 4) {
                            transparent = if (blk[0] & 1 != 0) blk[3] else null;
                            disposal = @intCast((blk[0] >> 2) & 7);
                            delay = @intCast(rd16(blk, 1));
                        }
                    }
                    try r.skipSubBlocks();
                },
                0x2c => {
                    const d = try r.take(9);
                    const iflags = d[8];
                    var fd = FrameDesc{
                        .x = rd16(d, 0),
                        .y = rd16(d, 2),
                        .w = rd16(d, 4),
                        .h = rd16(d, 6),
                        .ct = g.gct,
                        .transparent = transparent,
                        .disposal = disposal,
                        .delay_cs = delay,
                        .interlaced = iflags & 0x40 != 0,
                        .min_size = 0,
                        .data_pos = 0,
                    };
                    if (iflags & 0x80 != 0) fd.ct = try r.take(@as(usize, 3) << @intCast((iflags & 7) + 1));
                    fd.min_size = try r.byte();
                    if (fd.min_size < 1 or fd.min_size > 11) return error.InvalidData;
                    fd.data_pos = r.pos;
                    try r.skipSubBlocks();
                    return fd;
                },
                0x3b => return null,
                else => return error.InvalidData,
            }
        }
    }
};

/// Number of frames (image descriptors) in a GIF; stops at the first malformed block.
pub fn frameCount(bytes: []const u8) u32 {
    var g = Gif.init(bytes) catch return 0;
    var n: u32 = 0;
    while (g.next() catch null) |_| n += 1;
    return n;
}

/// LZW-decodes frame `fd` and paints it onto the straight-RGBA canvas (`cw`x`c_h`), skipping
/// transparent-index pixels (they keep the canvas value) and clipping to the canvas.
pub fn drawFrame(alloc: std.mem.Allocator, bytes: []const u8, fd: FrameDesc, out: []u8, cw: u32, c_h: u32, limits: Limits) Error!void {
    // Gather the LZW data sub-blocks.
    var r = Reader{ .b = bytes, .pos = fd.data_pos };
    var total: usize = 0;
    while (true) {
        const n = try r.byte();
        if (n == 0) break;
        _ = try r.take(n);
        total += n;
    }
    const lzw = try alloc.alloc(u8, total);
    defer alloc.free(lzw);
    var q = fd.data_pos;
    var o: usize = 0;
    while (o < total) {
        const n: usize = bytes[q];
        @memcpy(lzw[o .. o + n], bytes[q + 1 .. q + 1 + n]);
        o += n;
        q += 1 + n;
    }
    const fw = fd.w;
    const fh = fd.h;
    const npx = @as(usize, fw) * fh;
    if (npx > limits.max_pixels) return error.ImageTooLarge;
    const idx = try alloc.alloc(u8, npx);
    defer alloc.free(idx);
    @memset(idx, if (fd.transparent) |t| t else 0);
    lzwDecode(lzw, @intCast(fd.min_size), idx);

    const ct = fd.ct;
    var row: u32 = 0;
    var pass: u3 = 0;
    var y: u32 = 0;
    while (row < fh) : (row += 1) {
        if (fd.interlaced) {
            // pass starts / steps: (0,8) (4,8) (2,4) (1,2)
            const starts = [4]u32{ 0, 4, 2, 1 };
            while (pass < 4 and y >= fh) {
                pass += 1;
                if (pass < 4) y = starts[pass];
            }
            if (pass >= 4) break;
        } else y = row;
        const dy = @as(u64, fd.y) + y;
        if (dy < c_h) {
            var x: u32 = 0;
            while (x < fw) : (x += 1) {
                const dx = @as(u64, fd.x) + x;
                if (dx >= cw) break;
                const ci = idx[@as(usize, row) * fw + x];
                if (fd.transparent != null and ci == fd.transparent.?) continue;
                const p = @as(usize, ci) * 3;
                const di = (@as(usize, @intCast(dy)) * cw + @as(usize, @intCast(dx))) * 4;
                if (p + 3 <= ct.len) {
                    out[di..][0..4].* = .{ ct[p], ct[p + 1], ct[p + 2], 255 };
                } else out[di..][0..4].* = .{ 0, 0, 0, 255 };
            }
        }
        if (fd.interlaced) {
            const steps = [4]u32{ 8, 8, 4, 2 };
            y += steps[pass];
        }
    }
}

/// LZW-decodes into `out` (stops when full or at end-of-information / bad data).
fn lzwDecode(data: []const u8, min_size: u4, out: []u8) void {
    var prefix: [4096]u16 = undefined;
    var suffix: [4096]u8 = undefined;
    var first: [4096]u8 = undefined; // first byte of each string
    var lens: [4096]u16 = undefined;
    const clear: u32 = @as(u32, 1) << min_size;
    const eoi = clear + 1;
    var i: u32 = 0;
    while (i < clear) : (i += 1) {
        suffix[i] = @truncate(i);
        first[i] = @truncate(i);
        lens[i] = 1;
        prefix[i] = 0;
    }
    var size: u5 = @as(u5, min_size) + 1;
    var next: u32 = eoi + 1;
    var prev: ?u32 = null;
    var bitbuf: u32 = 0;
    var nbits: u5 = 0;
    var pos: usize = 0;
    var o: usize = 0;
    while (o < out.len) {
        while (nbits < size) {
            if (pos >= data.len) return;
            bitbuf |= @as(u32, data[pos]) << nbits;
            pos += 1;
            nbits += 8;
        }
        const code = bitbuf & ((@as(u32, 1) << size) - 1);
        bitbuf >>= size;
        nbits -= size;
        if (code == clear) {
            size = @as(u5, min_size) + 1;
            next = eoi + 1;
            prev = null;
            continue;
        }
        if (code == eoi) return;
        var cur = code;
        if (prev) |p| {
            if (code > next or (code == next and next >= 4096)) return; // corrupt
            if (next < 4096) {
                // New entry = string(prev) + first(code or prev when KwKwK).
                const f = if (code == next) first[p] else first[code];
                prefix[next] = @intCast(p);
                suffix[next] = f;
                first[next] = first[p];
                lens[next] = lens[p] +| 1;
                next += 1;
                if (next == (@as(u32, 1) << size) and size < 12) size += 1;
            }
        } else if (code >= clear) return; // first code after clear must be a literal
        // Emit string(cur), written back to front.
        const l: usize = lens[cur];
        const end = @min(o + l, out.len);
        var k = o + l;
        while (k > o) {
            k -= 1;
            if (k < end) out[k] = suffix[cur];
            cur = prefix[cur];
        }
        o = end;
        prev = code;
    }
}

test "decode takumi gif first frame" {
    const a = std.testing.allocator;
    const bytes = @embedFile("testdata/gif_takumi.gif");
    // Wyhash of takumi's own decode (takumi wasm, image src at intrinsic size, raw output).
    const ref_hash: u64 = 0x292b661fd1b06428;
    const img = try decode(a, bytes, .{});
    defer img.deinit(a);
    const d = dimensions(bytes).?;
    try std.testing.expectEqual(d[0], img.width);
    try std.testing.expectEqual(ref_hash, std.hash.Wyhash.hash(0, img.data));
}

test "interlaced and small gifs" {
    const a = std.testing.allocator;
    // 3x10 interlaced image, 2-color GCT, transparency index 1. Data built with an
    // "uncompressed" LZW stream (clear code before each literal keeps width at 3 bits).
    const w = 3;
    const h = 10;
    var idxs: [w * h]u8 = undefined;
    for (&idxs, 0..) |*v, k| v.* = @intCast((k / w + k) % 2);
    // interlace order of rows
    const order = [_]usize{ 0, 8, 4, 2, 6, 1, 3, 5, 7, 9 };
    var codes: std.ArrayList(u16) = .empty;
    defer codes.deinit(a);
    for (order) |row| for (0..w) |x| {
        try codes.append(a, 4); // clear (min size 2)
        try codes.append(a, idxs[row * w + x]);
    };
    try codes.append(a, 5); // eoi
    var lzw: std.ArrayList(u8) = .empty;
    defer lzw.deinit(a);
    var acc: u32 = 0;
    var nb: u5 = 0;
    for (codes.items) |c| {
        acc |= @as(u32, c) << nb;
        nb += 3;
        while (nb >= 8) {
            try lzw.append(a, @truncate(acc));
            acc >>= 8;
            nb -= 8;
        }
    }
    if (nb > 0) try lzw.append(a, @truncate(acc));
    var file: std.ArrayList(u8) = .empty;
    defer file.deinit(a);
    try file.appendSlice(a, "GIF89a\x03\x00\x0a\x00\x80\x00\x00");
    try file.appendSlice(a, "\x10\x20\x30\xa0\xb0\xc0");
    try file.appendSlice(a, "\x21\xf9\x04\x01\x00\x00\x01\x00");
    try file.appendSlice(a, "\x2c\x00\x00\x00\x00\x03\x00\x0a\x00\x40\x02");
    try file.append(a, @intCast(lzw.items.len));
    try file.appendSlice(a, lzw.items);
    try file.appendSlice(a, "\x00\x3b");
    const img = try decode(a, file.items, .{});
    defer img.deinit(a);
    for (0..h) |y| for (0..w) |x| {
        const p = img.data[(y * w + x) * 4 ..][0..4];
        if (idxs[y * w + x] == 1) {
            try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, p);
        } else try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x20, 0x30, 255 }, p);
    };
}

test "fuzz gif" {
    const a = std.testing.allocator;
    const base = @embedFile("testdata/gif_takumi.gif");
    var buf: [base.len]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(11);
    const rnd = prng.random();
    var cut: usize = 0;
    while (cut < base.len) : (cut += 3) {
        if (decode(a, base[0..cut], .{ .max_pixels = 1 << 20 })) |img| img.deinit(a) else |_| {}
    }
    for (0..4000) |i| {
        @memcpy(&buf, base);
        for (0..1 + rnd.uintLessThan(usize, 6)) |_| buf[rnd.uintLessThan(usize, buf.len)] = rnd.int(u8);
        const len = if (i % 4 == 0) rnd.uintLessThan(usize, buf.len) else buf.len;
        if (decode(a, buf[0..len], .{ .max_pixels = 1 << 20 })) |img| img.deinit(a) else |_| {}
    }
}
