//! GIF decoder: first frame only (GIF87a/89a), LZW, global/local color tables,
//! transparency index from the Graphic Control Extension, interlaced frames.
//! The frame is composited onto a fully transparent canvas of the logical screen size.
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

pub fn decode(alloc: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!Image {
    if (bytes.len < 13 or !std.mem.eql(u8, bytes[0..3], "GIF")) return error.InvalidData;
    var sw = rd16(bytes, 6);
    var sh = rd16(bytes, 8);
    const flags = bytes[10];
    var r = Reader{ .b = bytes, .pos = 13 };
    var gct: []const u8 = &.{};
    if (flags & 0x80 != 0) gct = try r.take(@as(usize, 3) << @intCast((flags & 7) + 1));
    var transparent: ?u8 = null;

    while (true) {
        const tag = try r.byte();
        switch (tag) {
            0x21 => {
                const label = try r.byte();
                if (label == 0xf9) {
                    const n = try r.byte();
                    const blk = try r.take(n);
                    if (n >= 4 and blk[0] & 1 != 0) transparent = blk[3];
                }
                try r.skipSubBlocks();
            },
            0x2c => {
                const d = try r.take(9);
                const fx = rd16(d, 0);
                const fy = rd16(d, 2);
                const fw = rd16(d, 4);
                const fh = rd16(d, 6);
                const iflags = d[8];
                var ct = gct;
                if (iflags & 0x80 != 0) ct = try r.take(@as(usize, 3) << @intCast((iflags & 7) + 1));
                if (sw == 0 or sh == 0) {
                    sw = fx + fw;
                    sh = fy + fh;
                }
                const nbytes = try types.checkSize(sw, sh, limits);
                const min_size = try r.byte();
                if (min_size < 1 or min_size > 11) return error.InvalidData;
                // Gather the LZW data sub-blocks.
                const start = r.pos;
                var total: usize = 0;
                while (true) {
                    const n = try r.byte();
                    if (n == 0) break;
                    _ = try r.take(n);
                    total += n;
                }
                const lzw = try alloc.alloc(u8, total);
                defer alloc.free(lzw);
                var q = start;
                var o: usize = 0;
                while (o < total) {
                    const n: usize = bytes[q];
                    @memcpy(lzw[o .. o + n], bytes[q + 1 .. q + 1 + n]);
                    o += n;
                    q += 1 + n;
                }
                const npx = @as(usize, fw) * fh;
                if (npx > limits.max_pixels) return error.ImageTooLarge;
                const idx = try alloc.alloc(u8, npx);
                defer alloc.free(idx);
                @memset(idx, if (transparent) |t| t else 0);
                lzwDecode(lzw, @intCast(min_size), idx);

                const out = try alloc.alloc(u8, nbytes);
                @memset(out, 0);
                const interlaced = iflags & 0x40 != 0;
                var row: u32 = 0;
                var pass: u3 = 0;
                var y: u32 = 0;
                while (row < fh) : (row += 1) {
                    if (interlaced) {
                        // pass starts / steps: (0,8) (4,8) (2,4) (1,2)
                        const starts = [4]u32{ 0, 4, 2, 1 };
                        while (pass < 4 and y >= fh) {
                            pass += 1;
                            if (pass < 4) y = starts[pass];
                        }
                        if (pass >= 4) break;
                    } else y = row;
                    const dy = @as(u64, fy) + y;
                    if (dy < sh) {
                        var x: u32 = 0;
                        while (x < fw) : (x += 1) {
                            const dx = @as(u64, fx) + x;
                            if (dx >= sw) break;
                            const ci = idx[@as(usize, row) * fw + x];
                            if (transparent != null and ci == transparent.?) continue;
                            const p = @as(usize, ci) * 3;
                            const di = (@as(usize, @intCast(dy)) * sw + @as(usize, @intCast(dx))) * 4;
                            if (p + 3 <= ct.len) {
                                out[di] = ct[p];
                                out[di + 1] = ct[p + 1];
                                out[di + 2] = ct[p + 2];
                            }
                            out[di + 3] = 255;
                        }
                    }
                    if (interlaced) {
                        const steps = [4]u32{ 8, 8, 4, 2 };
                        y += steps[pass];
                    }
                }
                return .{ .width = sw, .height = sh, .data = out };
            },
            else => return error.InvalidData, // 0x3b trailer before any image, or garbage
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
