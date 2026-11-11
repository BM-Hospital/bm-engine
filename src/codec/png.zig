//! PNG decoder (all colour types / bit depths, tRNS, Adam7, multi-IDAT, APNG -> default image)
//! and encoder (indexed when <= 256 colours like takumi, else RGB/RGBA; adaptive filters).
//! CRCs are not verified on decode; gAMA/iCCP/sRGB are ignored (treated as sRGB).
const std = @import("std");
const byt = @import("bytes.zig");
const types = @import("types.zig");
const inflate = @import("inflate.zig");
const deflate = @import("deflate.zig");
const checksum = @import("checksum.zig");

pub const signature = [8]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

/// Width/height from IHDR (header only).
pub fn dimensions(bytes: []const u8) ?[2]u32 {
    if (bytes.len < 24 or !std.mem.eql(u8, bytes[0..8], &signature)) return null;
    if (!std.mem.eql(u8, bytes[12..16], "IHDR")) return null;
    return .{ std.mem.readInt(u32, bytes[16..20], .big), std.mem.readInt(u32, bytes[20..24], .big) };
}

// =================================================================== decoder

const Info = struct {
    w: u32,
    h: u32,
    depth: u8,
    ct: u8,
    interlace: bool,
    channels: u8,
    palette: [256][4]u8 = undefined,
    pal_len: usize = 0,
    has_key: bool = false,
    key: [3]u16 = .{ 0, 0, 0 },

    fn bitsPerPixel(i: *const Info) usize {
        return @as(usize, i.depth) * i.channels;
    }
    fn rowBytes(i: *const Info, w: usize) usize {
        return (w * i.bitsPerPixel() + 7) / 8;
    }
    fn filterBpp(i: *const Info) usize {
        return @max(1, i.bitsPerPixel() / 8);
    }
};

const adam7 = [7][4]u8{ .{ 0, 0, 8, 8 }, .{ 4, 0, 8, 8 }, .{ 0, 4, 4, 8 }, .{ 2, 0, 4, 4 }, .{ 0, 2, 2, 4 }, .{ 1, 0, 2, 2 }, .{ 0, 1, 1, 2 } };

fn passDim(full: u32, start: u8, step: u8) usize {
    if (full <= start) return 0;
    return (full - start + step - 1) / step;
}

/// Decodes a PNG to straight RGBA8. Memory: raw scanlines (temporary) + output, from `alloc`.
/// For APNG this is the default image (IDAT).
pub fn decode(alloc: std.mem.Allocator, bytes: []const u8, limits: types.Limits) types.Error!types.Image {
    var idat_total: usize = 0;
    const info = try parseInfo(bytes, limits, &idat_total);
    if (idat_total == 0) return error.InvalidData;

    // gather IDAT
    const z = try alloc.alloc(u8, idat_total);
    defer alloc.free(z);
    {
        var q: usize = 8;
        var o: usize = 0;
        while (q + 12 <= bytes.len and o < idat_total) {
            const len = byt.be32(bytes, q);
            if (len > bytes.len - q - 12) break;
            if (std.mem.eql(u8, bytes[q + 4 ..][0..4], "IDAT")) {
                @memcpy(z[o..][0..len], bytes[q + 8 ..][0..len]);
                o += len;
            }
            q += 12 + len;
        }
    }
    const out = try decodeImage(alloc, &info, z, info.w, info.h, limits);
    return .{ .width = info.w, .height = info.h, .data = out };
}

/// Header pass: IHDR/PLTE/tRNS validation; also reports the total IDAT payload size.
fn parseInfo(bytes: []const u8, limits: types.Limits, idat_total_out: *usize) types.Error!Info {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], &signature)) return error.InvalidData;
    var info: Info = undefined;
    var have_ihdr = false;
    var idat_total: usize = 0;
    var have_plte = false;

    // pass 1: header chunks, IDAT size
    var p: usize = 8;
    while (true) {
        if (bytes.len - p < 12) return error.InvalidData;
        const len = byt.be32(bytes, p);
        const typ = bytes[p + 4 ..][0..4];
        if (len > bytes.len - p - 12) return error.InvalidData;
        const data = bytes[p + 8 ..][0..len];
        if (std.mem.eql(u8, typ, "IHDR")) {
            if (have_ihdr or len < 13) return error.InvalidData;
            have_ihdr = true;
            info = .{
                .w = std.mem.readInt(u32, data[0..4], .big),
                .h = std.mem.readInt(u32, data[4..8], .big),
                .depth = data[8],
                .ct = data[9],
                .interlace = data[12] == 1,
                .channels = 0,
            };
            if (data[10] != 0 or data[11] != 0 or data[12] > 1) return error.InvalidData;
            const d = info.depth;
            info.channels = switch (info.ct) {
                0 => if (d == 1 or d == 2 or d == 4 or d == 8 or d == 16) 1 else 0,
                2 => if (d == 8 or d == 16) 3 else 0,
                3 => if (d == 1 or d == 2 or d == 4 or d == 8) 1 else 0,
                4 => if (d == 8 or d == 16) 2 else 0,
                6 => if (d == 8 or d == 16) 4 else 0,
                else => 0,
            };
            if (info.channels == 0) return error.InvalidData;
            if (info.w > (1 << 24) or info.h > (1 << 24)) return error.ImageTooLarge;
            _ = try types.checkSize(info.w, info.h, limits);
        } else if (!have_ihdr) {
            return error.InvalidData;
        } else if (std.mem.eql(u8, typ, "PLTE")) {
            if (len % 3 != 0 or len / 3 > 256) return error.InvalidData;
            info.pal_len = len / 3;
            for (0..info.pal_len) |i| info.palette[i] = .{ data[i * 3], data[i * 3 + 1], data[i * 3 + 2], 255 };
            have_plte = true;
        } else if (std.mem.eql(u8, typ, "tRNS")) {
            switch (info.ct) {
                3 => for (0..@min(len, info.pal_len)) |i| {
                    info.palette[i][3] = data[i];
                },
                0 => if (len >= 2) {
                    info.has_key = true;
                    const v = std.mem.readInt(u16, data[0..2], .big);
                    info.key = .{ v, v, v };
                },
                2 => if (len >= 6) {
                    info.has_key = true;
                    for (0..3) |i| info.key[i] = byt.be16(data, i * 2);
                },
                else => {},
            }
        } else if (std.mem.eql(u8, typ, "IDAT")) {
            idat_total += len;
        } else if (std.mem.eql(u8, typ, "IEND")) {
            break;
        }
        p += 12 + len;
        if (p == bytes.len) break; // tolerate missing IEND
    }
    if (!have_ihdr) return error.InvalidData;
    if (info.ct == 3 and !have_plte) return error.InvalidData;
    idat_total_out.* = idat_total;
    return info;
}

/// Inflates + unfilters one zlib image stream of `w`x`h` pixels in `info_in`'s pixel format
/// to straight RGBA8 (allocated from `alloc`).
fn decodeImage(alloc: std.mem.Allocator, info_in: *const Info, z: []const u8, w: u32, h: u32, limits: types.Limits) types.Error![]u8 {
    var info = info_in.*;
    info.w = w;
    info.h = h;
    if (w > (1 << 24) or h > (1 << 24)) return error.ImageTooLarge;
    _ = try types.checkSize(w, h, limits);

    // raw size
    // width <= 2^24 and 64 bits per pixel keep rowBytes < 2^27; the product is checked in u64.
    var raw64: u64 = 0;
    if (info.interlace) {
        for (adam7) |a| {
            const pw = passDim(info.w, a[0], a[2]);
            const ph = passDim(info.h, a[1], a[3]);
            if (pw != 0 and ph != 0) raw64 += @as(u64, ph) * (1 + info.rowBytes(pw));
        }
    } else raw64 = @as(u64, info.h) * (1 + info.rowBytes(info.w));
    if (raw64 > std.math.maxInt(usize)) return error.ImageTooLarge;
    const raw_size: usize = @intCast(raw64);

    const raw = try alloc.alloc(u8, raw_size);
    defer alloc.free(raw);
    const got = inflate.zlibDecompressInto(z, raw, .{}) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidData,
    };
    if (got != raw_size) return error.InvalidData;

    const out_len = try types.checkSize(info.w, info.h, limits);
    const out = try alloc.alloc(u8, out_len);
    errdefer alloc.free(out);

    const zero_row = try alloc.alloc(u8, info.rowBytes(info.w));
    defer alloc.free(zero_row);
    @memset(zero_row, 0);

    var off: usize = 0;
    if (info.interlace) {
        for (adam7) |a| {
            const pw = passDim(info.w, a[0], a[2]);
            const ph = passDim(info.h, a[1], a[3]);
            if (pw == 0 or ph == 0) continue;
            try decodePass(&info, raw[off..], pw, ph, zero_row, out, a);
            off += ph * (1 + info.rowBytes(pw));
        }
    } else {
        try decodePass(&info, raw, info.w, info.h, zero_row, out, .{ 0, 0, 1, 1 });
    }
    return out;
}

// ------------------------------------------------------------------- APNG frame access

/// One APNG frame control (fcTL) record.
pub const ApngFrame = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    delay_ms: u32,
    /// 0 = none, 1 = background (clear to transparent), 2 = previous.
    dispose_op: u8,
    /// 0 = source (replace), 1 = over (alpha blend).
    blend_op: u8,
    /// Byte offset of the chunk after this fcTL (its IDAT/fdAT data follow until the next fcTL).
    data_pos: usize,
};

/// Iterates the chunks after the PNG signature: returns type + payload, or null at the end
/// (or on a truncated chunk).
fn nextChunk(bytes: []const u8, p: *usize) ?struct { typ: *const [4]u8, data: []const u8 } {
    const q = p.*;
    if (q < 8 or bytes.len < 12 or q > bytes.len - 12) return null;
    const len = byt.be32(bytes, q);
    if (len > bytes.len - q - 12) return null;
    p.* = q + 12 + len;
    return .{ .typ = bytes[q + 4 ..][0..4], .data = bytes[q + 8 ..][0..len] };
}

/// Number of APNG frames (fcTL chunks) when an acTL chunk is present, else 0. Header scan only.
pub fn apngFrameCount(bytes: []const u8) u32 {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], &signature)) return 0;
    var p: usize = 8;
    var actl = false;
    var n: u32 = 0;
    while (nextChunk(bytes, &p)) |c| {
        if (std.mem.eql(u8, c.typ, "acTL")) actl = true;
        if (std.mem.eql(u8, c.typ, "fcTL")) n += 1;
        if (std.mem.eql(u8, c.typ, "IEND")) break;
    }
    return if (actl) n else 0;
}

/// The `index`-th fcTL record (null if missing or malformed).
pub fn apngFrame(bytes: []const u8, index: u32) ?ApngFrame {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], &signature)) return null;
    var p: usize = 8;
    var n: u32 = 0;
    while (nextChunk(bytes, &p)) |c| {
        if (std.mem.eql(u8, c.typ, "IEND")) break;
        if (!std.mem.eql(u8, c.typ, "fcTL")) continue;
        if (n == index) {
            const d = c.data;
            if (d.len < 26) return null;
            const num: u32 = byt.be16(d, 20);
            var den: u32 = byt.be16(d, 22);
            if (den == 0) den = 100;
            return .{
                .w = byt.be32(d, 4),
                .h = byt.be32(d, 8),
                .x = byt.be32(d, 12),
                .y = byt.be32(d, 16),
                .delay_ms = num * 1000 / den,
                .dispose_op = d[24],
                .blend_op = d[25],
                .data_pos = p,
            };
        }
        n += 1;
    }
    return null;
}

/// Decodes the pixels of one APNG frame (`fr.w` x `fr.h`, straight RGBA8, not composited).
pub fn decodeApngFrame(alloc: std.mem.Allocator, bytes: []const u8, fr: ApngFrame, limits: types.Limits) types.Error!types.Image {
    var idat_total: usize = 0;
    const info = try parseInfo(bytes, limits, &idat_total);
    if (fr.w == 0 or fr.h == 0) return error.InvalidData;
    // Gather the IDAT / fdAT payloads up to the next fcTL.
    var total: usize = 0;
    var pass: u2 = 0;
    var z: []u8 = &.{};
    defer alloc.free(z);
    while (pass < 2) : (pass += 1) {
        var p = fr.data_pos;
        var o: usize = 0;
        while (nextChunk(bytes, &p)) |c| {
            if (std.mem.eql(u8, c.typ, "fcTL") or std.mem.eql(u8, c.typ, "IEND")) break;
            var payload: []const u8 = &.{};
            if (std.mem.eql(u8, c.typ, "IDAT")) payload = c.data;
            if (std.mem.eql(u8, c.typ, "fdAT") and c.data.len >= 4) payload = c.data[4..];
            if (pass == 0) total += payload.len else {
                @memcpy(z[o..][0..payload.len], payload);
                o += payload.len;
            }
        }
        if (pass == 0) {
            if (total == 0) return error.InvalidData;
            z = try alloc.alloc(u8, total);
        }
    }
    const out = try decodeImage(alloc, &info, z, fr.w, fr.h, limits);
    return .{ .width = fr.w, .height = fr.h, .data = out };
}

fn decodePass(info: *const Info, raw: []u8, pw: usize, ph: usize, zero_row: []const u8, out: []u8, a: [4]u8) types.Error!void {
    const rb = info.rowBytes(pw);
    const bpp = info.filterBpp();
    var prev: []const u8 = zero_row[0..rb];
    for (0..ph) |y| {
        const row = raw[y * (rb + 1) ..][0 .. rb + 1];
        const cur = row[1..];
        try unfilter(row[0], cur, prev, bpp);
        prev = cur;
        const oy = a[1] + y * a[3];
        expandRow(info, cur, out, oy * info.w, a[0], a[2], pw);
    }
}

fn unfilter(ft: u8, cur: []u8, prev: []const u8, bpp: usize) types.Error!void {
    switch (ft) {
        0 => {},
        1 => switch (bpp) {
            inline 3, 4 => |b| unSub(b, cur),
            else => for (bpp..cur.len) |i| {
                cur[i] +%= cur[i - bpp];
            },
        },
        2 => for (cur, prev) |*c, u| {
            c.* +%= u;
        },
        3 => switch (bpp) {
            inline 3, 4 => |b| unAvg(b, cur, prev),
            else => {
                for (0..@min(bpp, cur.len)) |i| cur[i] +%= prev[i] >> 1;
                for (bpp..cur.len) |i| cur[i] +%= @intCast((@as(u16, cur[i - bpp]) + prev[i]) >> 1);
            },
        },
        4 => switch (bpp) {
            inline 3, 4 => |b| unPaeth(b, cur, prev),
            else => {
                for (0..@min(bpp, cur.len)) |i| cur[i] +%= prev[i];
                for (bpp..cur.len) |i| cur[i] +%= paeth(cur[i - bpp], prev[i], prev[i - bpp]);
            },
        },
        else => return error.InvalidData,
    }
}

inline fn paeth(a: u8, b: u8, c: u8) u8 {
    const pa = @abs(@as(i16, b) - c);
    const pb = @abs(@as(i16, a) - c);
    const pc = @abs(@as(i16, a) + b - 2 * @as(i16, c));
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

fn unSub(comptime b: usize, cur: []u8) void {
    const V = @Vector(b, u8);
    var left: V = @splat(0);
    var i: usize = 0;
    while (i + b <= cur.len) : (i += b) {
        const x: V = cur[i..][0..b].*;
        left = x +% left;
        cur[i..][0..b].* = left;
    }
}

fn unAvg(comptime b: usize, cur: []u8, prev: []const u8) void {
    const V = @Vector(b, u16);
    var left: V = @splat(0);
    var i: usize = 0;
    while (i + b <= cur.len) : (i += b) {
        const x: @Vector(b, u8) = cur[i..][0..b].*;
        const up: V = @as(@Vector(b, u8), prev[i..][0..b].*);
        const r: @Vector(b, u8) = x +% @as(@Vector(b, u8), @truncate((left + up) >> @splat(1)));
        cur[i..][0..b].* = r;
        left = r;
    }
}

fn unPaeth(comptime b: usize, cur: []u8, prev: []const u8) void {
    const V = @Vector(b, i16);
    var a: V = @splat(0);
    var c: V = @splat(0);
    var i: usize = 0;
    while (i + b <= cur.len) : (i += b) {
        const bb: V = @as(@Vector(b, u8), prev[i..][0..b].*);
        const pa = @abs(bb - c);
        const pb = @abs(a - c);
        const pc = @abs(a + bb - c - c);
        const pred = @select(i16, (pa <= pb) & (pa <= pc), a, @select(i16, pb <= pc, bb, c));
        const x: @Vector(b, u8) = cur[i..][0..b].*;
        const r = x +% @as(@Vector(b, u8), @intCast(pred));
        cur[i..][0..b].* = r;
        a = @as(@Vector(b, u8), r);
        c = bb;
    }
}

inline fn subSample(row: []const u8, x: usize, depth: u8) u8 {
    const bit = x * depth;
    const shift: u3 = @intCast(8 - depth - (bit & 7));
    const mask: u8 = @intCast((@as(u16, 1) << @intCast(depth)) - 1);
    return (row[bit >> 3] >> shift) & mask;
}

/// Writes pass row `src` (pw pixels) into output row starting at pixel `base`, x = xs + j*dx.
fn expandRow(info: *const Info, src: []const u8, out: []u8, base: usize, xs: usize, dx: usize, pw: usize) void {
    const d = info.depth;
    var o = (base + xs) * 4;
    const step = dx * 4;
    switch (info.ct) {
        0 => for (0..pw) |j| {
            var v: u8 = undefined;
            var raw16: u16 = undefined;
            if (d == 16) {
                raw16 = byt.be16(src, j * 2);
                v = @intCast(raw16 >> 8);
            } else if (d == 8) {
                v = src[j];
                raw16 = v;
            } else {
                const s = subSample(src, j, d);
                raw16 = s;
                v = s * @as(u8, switch (d) {
                    1 => 255,
                    2 => 85,
                    else => 17,
                });
            }
            // Colour-key transparent pixels become (0,0,0,0) like pngjs/libpng-to-premultiplied.
            const al: u8 = if (info.has_key and raw16 == info.key[0]) 0 else 255;
            out[o..][0..4].* = if (al == 0) .{ 0, 0, 0, 0 } else .{ v, v, v, 255 };
            o += step;
        },
        2 => if (d == 8) {
            for (0..pw) |j| {
                const s = src[j * 3 ..][0..3];
                var al: u8 = 255;
                if (info.has_key and s[0] == info.key[0] and s[1] == info.key[1] and s[2] == info.key[2]) al = 0;
                out[o..][0..4].* = if (al == 0) .{ 0, 0, 0, 0 } else .{ s[0], s[1], s[2], 255 };
                o += step;
            }
        } else {
            for (0..pw) |j| {
                const s = src[j * 6 ..][0..6];
                var al: u8 = 255;
                if (info.has_key and std.mem.readInt(u16, s[0..2], .big) == info.key[0] and
                    std.mem.readInt(u16, s[2..4], .big) == info.key[1] and
                    std.mem.readInt(u16, s[4..6], .big) == info.key[2]) al = 0;
                out[o..][0..4].* = if (al == 0) .{ 0, 0, 0, 0 } else .{ s[0], s[2], s[4], 255 };
                o += step;
            }
        },
        3 => for (0..pw) |j| {
            const idx = if (d == 8) src[j] else subSample(src, j, d);
            out[o..][0..4].* = if (idx < info.pal_len) info.palette[idx] else .{ 0, 0, 0, 255 };
            o += step;
        },
        4 => for (0..pw) |j| {
            const g, const al = if (d == 8) .{ src[j * 2], src[j * 2 + 1] } else .{ src[j * 4], src[j * 4 + 2] };
            out[o..][0..4].* = .{ g, g, g, al };
            o += step;
        },
        else => if (d == 8) {
            if (dx == 1) {
                @memcpy(out[o..][0 .. pw * 4], src[0 .. pw * 4]);
            } else for (0..pw) |j| {
                out[o..][0..4].* = src[j * 4 ..][0..4].*;
                o += step;
            }
        } else for (0..pw) |j| {
            const s = src[j * 8 ..][0..8];
            out[o..][0..4].* = .{ s[0], s[2], s[4], s[6] };
            o += step;
        },
    }
}

// =================================================================== encoder

pub const FilterStrategy = enum {
    /// Filter type 0 on every row.
    none,
    /// Up (2) on every row.
    up,
    /// Paeth (4) on every row.
    paeth,
    /// Per row: minimum sum of |signed bytes| among None/Sub/Up/Avg/Paeth.
    adaptive,
    /// Per row: minimum sum among Sub/Up/Paeth (skips the rarely-best None/Avg).
    adaptive_fast,
    /// takumi-like: palette images use None; RGB(A) images try None vs adaptive on a 1-in-32
    /// row sample (deflated at `.fastest`) and keep the smaller.
    auto,
};

pub const EncodeOptions = struct {
    /// null = automatic: `.default` for unfiltered (flat/indexed) data, `.fast` for filtered
    /// (photographic) data, mirroring takumi's level-7-flat / level-3-photo split.
    level: ?deflate.Level = null,
    filter: FilterStrategy = .auto,
    /// Write RGB when every pixel has alpha 255.
    strip_opaque_alpha: bool = true,
    /// Write an indexed PNG (bit depth 1/2/4/8, PLTE + tRNS) when there are <= 256 colours.
    palette: bool = true,
};

pub const EncodeError = error{ OutOfMemory, InvalidInput };

/// Encodes straight RGBA8 to a PNG file. The result is allocated from `alloc` (caller owns);
/// temporaries (~1x the raw image) are allocated from and returned to `alloc`.
pub fn encode(alloc: std.mem.Allocator, rgba: []const u8, w: u32, h: u32, opts: EncodeOptions) EncodeError![]u8 {
    if (w == 0 or h == 0 or w > (1 << 24) or h > (1 << 24)) return error.InvalidInput;
    const npx64 = @as(u64, w) * h;
    if (npx64 > std.math.maxInt(usize) / 8) return error.InvalidInput;
    const npx: usize = @intCast(npx64);
    if (rgba.len != npx * 4) return error.InvalidInput;

    var pal: Palette = undefined;
    const use_pal = opts.palette and pal.build(rgba);
    var ct: u8 = 6;
    var depth: u8 = 8;
    var bpp: usize = 4;
    if (use_pal) {
        ct = 3;
        depth = if (pal.n <= 2) 1 else if (pal.n <= 4) 2 else if (pal.n <= 16) 4 else 8;
        bpp = 1;
    } else if (opts.strip_opaque_alpha and allOpaque(rgba)) {
        ct = 2;
        bpp = 3;
    }
    const rb: usize = if (use_pal) (@as(usize, w) * depth + 7) / 8 else @as(usize, w) * bpp;
    const stride = rb + 1;
    var rows = Rows{ .rgba = rgba, .w = w, .bpp = bpp, .rb = rb, .pal = if (use_pal) &pal else null, .depth = depth };

    // Scratch, allocated first: 3 rows (prev, cur, filtered). Everything else streams.
    const bufs = try alloc.alloc(u8, 3 * rb + 1);
    defer alloc.free(bufs);

    var strat: FilterStrategy = .none;
    if (!use_pal) {
        strat = opts.filter;
        if (strat == .auto) strat = try pickStrategy(alloc, &rows, h, bufs);
    }
    const level = opts.level orelse if (strat != .none) deflate.Level.fast else deflate.Level.default;

    // Chunks before the IDAT data are written into a reserved prefix of the output buffer.
    const pal_bytes: usize = if (use_pal) 12 + pal.n * 3 else 0;
    const trns_n: usize = if (use_pal) pal.ntrans else 0;
    const trns_bytes: usize = if (trns_n > 0) 12 + trns_n else 0;
    const prefix = 8 + 25 + pal_bytes + trns_bytes + 8;
    const raw_len = stride * @as(usize, h);
    var s = try deflate.Stream.init(alloc, .{ .level = level, .dist_hints = .{ @intCast(bpp), @intCast(stride) }, .hash_len = if (use_pal) 6 else 0 }, @max(raw_len / 8, 4096), prefix, true);
    errdefer s.deinit();
    try streamRows(&rows, &s, strat, 0, h, bufs);
    try s.finish();

    const zlen = s.w.pos - prefix;
    if (zlen > std.math.maxInt(i32)) return error.InvalidInput;
    try s.w.ensure(24);
    const out = s.w.buf;
    var o: usize = 0;
    @memcpy(out[0..8], &signature);
    o = 8;
    var ihdr: [13]u8 = undefined;
    byt.putBe32(&ihdr, 0, w);
    byt.putBe32(&ihdr, 4, h);
    ihdr[8] = depth;
    ihdr[9] = ct;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    o = putChunk(out, o, "IHDR", &ihdr);
    if (use_pal) {
        var plte: [768]u8 = undefined;
        var trns: [256]u8 = undefined;
        for (0..pal.n) |i| {
            plte[i * 3 ..][0..3].* = pal.colors[i][0..3].*;
            trns[i] = pal.colors[i][3];
        }
        o = putChunk(out, o, "PLTE", plte[0 .. pal.n * 3]);
        if (trns_n > 0) o = putChunk(out, o, "tRNS", trns[0..trns_n]);
    }
    byt.putBe32(out, o, @intCast(zlen));
    @memcpy(out[o + 4 ..][0..4], "IDAT");
    o += 8;
    std.debug.assert(o == prefix);
    var e = s.w.pos;
    byt.putBe32(out, e, checksum.crc32(0, out[prefix - 4 .. e]));
    e += 4;
    e = putChunk(out, e, "IEND", "");
    s.w.pos = e;
    return s.takeOutput();
}

fn putChunk(out: []u8, at: usize, typ: *const [4]u8, data: []const u8) usize {
    byt.putBe32(out, at, @intCast(data.len));
    @memcpy(out[at + 4 ..][0..4], typ);
    @memcpy(out[at + 8 ..][0..data.len], data);
    const crc = checksum.crc32(0, out[at + 4 .. at + 8 + data.len]);
    byt.putBe32(out, at + 8 + data.len, crc);
    return at + 12 + data.len;
}

fn allOpaque(rgba: []const u8) bool {
    const V = @Vector(64, u8);
    const mask: V = comptime blk: {
        var m: [64]u8 = undefined;
        for (0..64) |i| m[i] = if (i % 4 == 3) 0 else 0xff;
        break :blk m;
    };
    var i: usize = 0;
    while (i + 64 <= rgba.len) : (i += 64) {
        const v: V = rgba[i..][0..64].*;
        if (@reduce(.And, v | mask) != 0xff) return false;
    }
    while (i < rgba.len) : (i += 4) if (rgba[i + 3] != 255) return false;
    return true;
}

/// Bit j set when pixel i+j differs from pixel i+j-1 (16 pixels; requires i >= 1).
/// Edge-heavy rows then cost one mask plus a lookup per colour change instead of a
/// (often mispredicted) branch per pixel.
inline fn changes16(px: [*]align(1) const u32, i: usize) u32 {
    const V = @Vector(16, u32);
    const a: V = @as(*align(1) const V, @ptrCast(px + i)).*;
    const b: V = @as(*align(1) const V, @ptrCast(px + i - 1)).*;
    return @as(u16, @bitCast(a != b));
}

inline fn pixel(px: [*]align(1) const u32, i: usize) u32 {
    return std.mem.littleToNative(u32, px[i]);
}

const Palette = struct {
    const slots = 1024;
    keys: [slots]u32,
    ents: [slots]u16, // index+1, 0 = empty
    colors: [256][4]u8,
    n: usize,
    ntrans: usize, // non-opaque colours are sorted first; tRNS length

    /// Index of a colour known to be in the palette (0 if absent); first probe inlined.
    inline fn find(p: *Palette, key: u32) u8 {
        const s = (key *% 0x9E3779B1) >> 22;
        if (p.keys[s] == key and p.ents[s] != 0) return @intCast(p.ents[s] - 1);
        return p.lookup(key) orelse 0;
    }

    /// Inserts `key` if new; false when the palette is full.
    inline fn has(p: *Palette, key: u32) bool {
        const s = (key *% 0x9E3779B1) >> 22;
        if (p.keys[s] == key and p.ents[s] != 0) return true;
        return p.lookup(key) != null;
    }

    fn lookup(p: *Palette, key: u32) ?u8 {
        var s = (key *% 0x9E3779B1) >> 22;
        while (true) {
            const e = p.ents[s];
            if (e == 0) {
                if (p.n == 256) return null;
                p.keys[s] = key;
                p.colors[p.n] = @bitCast(key);
                p.n += 1;
                p.ents[s] = @intCast(p.n);
                return @intCast(p.n - 1);
            }
            if (p.keys[s] == key) return @intCast(e - 1);
            s = (s + 1) & (slots - 1);
        }
    }

    /// Collects up to 256 colours; false if there are more. Sorts non-opaque colours first.
    fn build(p: *Palette, rgba: []const u8) bool {
        @memset(&p.ents, 0);
        p.n = 0;
        const npx = rgba.len / 4;
        // quick rejection on a sparse sample first (every 61st pixel)
        var i: usize = 0;
        while (i < npx) : (i += 61) {
            if (p.lookup(byt.le32(rgba, i * 4)) == null) return false;
        }
        // Full pass: only pixels that differ from their left neighbour can be new colours
        // (pixel 0 was in the sample), found 16 at a time.
        const px: [*]align(1) const u32 = @ptrCast(rgba.ptr);
        i = 1;
        while (i + 16 <= npx) : (i += 16) {
            var m = changes16(px, i);
            while (m != 0) : (m &= m - 1) {
                if (!p.has(pixel(px, i + @ctz(m)))) return false;
            }
        }
        while (i < npx) : (i += 1) {
            if (pixel(px, i) != pixel(px, i - 1) and !p.has(pixel(px, i))) return false;
        }
        // reorder: transparent-ish colours first so tRNS can be truncated
        var order: [256]u8 = undefined;
        var no: usize = 0;
        for (0..p.n) |c| if (p.colors[c][3] != 255) {
            order[no] = @intCast(c);
            no += 1;
        };
        p.ntrans = no;
        for (0..p.n) |c| if (p.colors[c][3] == 255) {
            order[no] = @intCast(c);
            no += 1;
        };
        var newcol: [256][4]u8 = undefined;
        var remap: [256]u8 = undefined;
        for (0..p.n) |k| {
            newcol[k] = p.colors[order[k]];
            remap[order[k]] = @intCast(k);
        }
        p.colors = newcol;
        for (0..slots) |s| if (p.ents[s] != 0) {
            p.ents[s] = @as(u16, remap[p.ents[s] - 1]) + 1;
        };
        return true;
    }

};

/// Source rows converted to the packed scanline pixel format (RGBA, RGB or palette indices).
const Rows = struct {
    rgba: []const u8,
    w: usize,
    bpp: usize, // bytes per pixel for filtering (1 for palette)
    rb: usize, // packed row bytes
    pal: ?*Palette,
    depth: u8,
    last: u32 = 0,
    last_idx: u8 = 0,
    have_last: bool = false,

    fn pack(r: *Rows, y: usize, dst: []u8) void {
        const src = r.rgba[y * r.w * 4 ..][0 .. r.w * 4];
        if (r.pal) |p| {
            if (!r.have_last) {
                r.last = byt.le32(src, 0);
                r.last_idx = p.lookup(r.last).?;
                r.have_last = true;
            }
            if (r.depth == 8) {
                const px: [*]align(1) const u32 = @ptrCast(src.ptr);
                const w = r.w;
                var idx = r.last_idx;
                if (pixel(px, 0) != r.last) idx = p.find(pixel(px, 0));
                dst[0] = idx;
                var x: usize = 1;
                const B = @Vector(16, u8);
                while (x + 16 <= w) : (x += 16) {
                    var m = changes16(px, x);
                    // 16 indices assembled in `tmp`: each colour change overwrites from its
                    // position to the end of the block.
                    var tmp: [32]u8 align(16) = undefined;
                    @as(*B, @ptrCast(&tmp)).* = @splat(idx);
                    while (m != 0) : (m &= m - 1) {
                        const j = @ctz(m);
                        idx = p.find(pixel(px, x + j));
                        @as(*align(1) B, @ptrCast(&tmp[j])).* = @splat(idx);
                    }
                    @as(*align(1) B, @ptrCast(dst.ptr + x)).* = @as(*B, @ptrCast(&tmp)).*;
                }
                while (x < w) : (x += 1) {
                    if (pixel(px, x) != pixel(px, x - 1)) idx = p.find(pixel(px, x));
                    dst[x] = idx;
                }
                r.last = pixel(px, w - 1);
                r.last_idx = idx;
                return;
            }
            @memset(dst, 0);
            for (0..r.w) |x| {
                const k = byt.le32(src, x * 4);
                if (k != r.last) {
                    r.last = k;
                    r.last_idx = p.lookup(k) orelse 0;
                }
                const bit = x * r.depth;
                dst[bit >> 3] |= r.last_idx << @intCast(8 - r.depth - (bit & 7));
            }
        } else if (r.bpp == 4) {
            @memcpy(dst, src);
        } else {
            // RGBA -> RGB, 4 pixels per shuffle; each 16-byte store overlaps the next by 4.
            const B = @Vector(16, u8);
            var i: usize = 0;
            while (i + 4 <= r.w and i * 3 + 16 <= dst.len) : (i += 4) {
                const v: B = @as(*align(1) const B, @ptrCast(src.ptr + i * 4)).*;
                @as(*align(1) B, @ptrCast(dst.ptr + i * 3)).* = @shuffle(u8, v, undefined, @Vector(16, i32){ 0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 0, 0, 0, 0 });
            }
            while (i < r.w) : (i += 1) {
                dst[i * 3] = src[i * 4];
                dst[i * 3 + 1] = src[i * 4 + 1];
                dst[i * 3 + 2] = src[i * 4 + 2];
            }
        }
    }
};

/// Filters rows [y0, y1) and feeds the scanlines to `s`. `bufs`: 3*rb+1 bytes of scratch.
/// The row above y0 (when y0 > 0) is used as predictor, as in the full image.
fn streamRows(r: *Rows, s: *deflate.Stream, strat: FilterStrategy, y0: usize, y1: usize, bufs: []u8) deflate.Error!void {
    const rb = r.rb;
    var prev: []u8 = bufs[0..rb];
    var cur: []u8 = bufs[rb..][0..rb];
    const out = bufs[2 * rb ..][0 .. rb + 1];
    if (strat == .none) {
        // no predictor: pack straight into the output scanline
        for (y0..y1) |y| {
            out[0] = 0;
            r.pack(y, out[1..]);
            try s.write(out);
        }
        return;
    }
    if (y0 == 0) @memset(prev, 0) else r.pack(y0 - 1, prev);
    for (y0..y1) |y| {
        r.pack(y, cur);
        const ft: u8 = switch (strat) {
            .none => 0,
            .up => 2,
            .paeth => 4,
            .adaptive, .adaptive_fast, .auto => choose(cur, prev, r.bpp, strat == .adaptive),
        };
        out[0] = ft;
        applyFilter(ft, out[1..], cur, prev, r.bpp);
        try s.write(out);
        const t = prev;
        prev = cur;
        cur = t;
    }
}

const VL = 16;
const V8 = @Vector(VL, u8);
const VI = @Vector(VL, i16);
const V16 = @Vector(VL, u16);

inline fn ld(s: []const u8, i: usize) V8 {
    return s[i..][0..VL].*;
}

/// Prediction for 16 bytes at `i` (requires i >= bpp).
inline fn predV(comptime ft: u8, c: []const u8, prev: []const u8, bpp: usize, i: usize) V8 {
    switch (ft) {
        1 => return ld(c, i - bpp),
        2 => return ld(prev, i),
        3 => {
            const a: V16 = ld(c, i - bpp);
            const b: V16 = ld(prev, i);
            return @truncate((a + b) >> @splat(1));
        },
        else => {
            const a: VI = ld(c, i - bpp);
            const b: VI = ld(prev, i);
            const cc: VI = ld(prev, i - bpp);
            const pa = @abs(b - cc);
            const pb = @abs(a - cc);
            const pc = @abs(a + b - cc - cc);
            const r = @select(i16, (pa <= pb) & (pa <= pc), a, @select(i16, pb <= pc, b, cc));
            return @truncate(@as(@Vector(VL, u16), @bitCast(r)));
        },
    }
}

inline fn predS(comptime ft: u8, c: []const u8, prev: []const u8, bpp: usize, i: usize) u8 {
    const a: u8 = if (i >= bpp) c[i - bpp] else 0;
    const b: u8 = prev[i];
    const cc: u8 = if (i >= bpp) prev[i - bpp] else 0;
    return switch (ft) {
        1 => a,
        2 => b,
        3 => @intCast((@as(u16, a) + b) >> 1),
        else => paeth(a, b, cc),
    };
}

inline fn absb(x: u8) u32 {
    return @abs(@as(i8, @bitCast(x)));
}

fn costRow(comptime ft: u8, c: []const u8, prev: []const u8, bpp: usize) u32 {
    const n = c.len;
    var s: u32 = 0;
    var i: usize = 0;
    if (ft != 0) while (i < @min(bpp, n)) : (i += 1) {
        s += absb(c[i] -% predS(ft, c, prev, bpp, i));
    };
    var acc: @Vector(VL, u32) = @splat(0);
    while (i + VL <= n) : (i += VL) {
        const d = if (ft == 0) ld(c, i) else ld(c, i) -% predV(ft, c, prev, bpp, i);
        acc += @as(@Vector(VL, u32), @abs(@as(@Vector(VL, i8), @bitCast(d))));
    }
    while (i < n) : (i += 1) s += absb(if (ft == 0) c[i] else c[i] -% predS(ft, c, prev, bpp, i));
    return s + @reduce(.Add, acc);
}

fn applyRow(comptime ft: u8, out: []u8, c: []const u8, prev: []const u8, bpp: usize) void {
    const n = c.len;
    if (ft == 0) {
        @memcpy(out[0..n], c);
        return;
    }
    var i: usize = 0;
    while (i < @min(bpp, n)) : (i += 1) out[i] = c[i] -% predS(ft, c, prev, bpp, i);
    while (i + VL <= n) : (i += VL) out[i..][0..VL].* = ld(c, i) -% predV(ft, c, prev, bpp, i);
    while (i < n) : (i += 1) out[i] = c[i] -% predS(ft, c, prev, bpp, i);
}

fn costOf(ft: u8, c: []const u8, prev: []const u8, bpp: usize) u32 {
    return switch (ft) {
        inline 0...4 => |f| costRow(f, c, prev, bpp),
        else => unreachable,
    };
}

fn applyFilter(ft: u8, out: []u8, c: []const u8, prev: []const u8, bpp: usize) void {
    switch (ft) {
        inline 0...4 => |f| applyRow(f, out, c, prev, bpp),
        else => unreachable,
    }
}

fn choose(c: []const u8, prev: []const u8, bpp: usize, full: bool) u8 {
    const cands: []const u8 = if (full) &.{ 0, 1, 2, 3, 4 } else &.{ 1, 2, 4 };
    var best: u8 = cands[0];
    var best_cost: u32 = std.math.maxInt(u32);
    for (cands) |ft| {
        const cost = costOf(ft, c, prev, bpp);
        if (cost < best_cost) {
            best_cost = cost;
            best = ft;
            if (cost == 0) break;
        }
    }
    return best;
}

const trial_rows = 8;
const trial_level: deflate.Level = .fast;
/// A second set of bands is sampled when the two best candidates are within 1/close_margin.
const close_margin = 8;

/// Picks the filter strategy by deflating a sample of the image with each candidate: 3 bands
/// of `trial_rows` rows (3 more when the result is close), or the whole image when small.
/// Each band is preceded by its context row, given to the compressor as history only, so
/// unfiltered rows can match the row above just as filtered rows predict from it.
fn pickStrategy(alloc: std.mem.Allocator, rows: *Rows, h: u32, bufs: []u8) EncodeError!FilterStrategy {
    const stride = rows.rb + 1;
    // `.up` won the trials now and then but rarely the full encode; skipping it saves a third.
    const cands = [_]FilterStrategy{ .none, .adaptive_fast };
    var s = try deflate.Stream.init(alloc, .{ .level = trial_level, .dist_hints = .{ @intCast(rows.bpp), @intCast(stride) } }, 64 << 10, 0, false);
    defer s.deinit();
    var size: [cands.len]usize = @splat(0);
    const whole = h <= 12 * (trial_rows + 2);
    for (0..@as(usize, if (whole) 1 else 2)) |pass| {
        for (cands, &size) |c, *sz| {
            if (whole) {
                s.reset();
                try streamRows(rows, &s, c, 0, h, bufs);
                try s.finish();
                sz.* = s.w.pos;
                continue;
            }
            // pass 0: bands centred at 3/12, 7/12, 11/12 of the height; pass 1: 1/12, 5/12, 9/12
            for (0..3) |k| {
                const y0 = (4 * k + 3 - 2 * pass) * h / 12 - trial_rows / 2;
                s.reset();
                try streamRows(rows, &s, c, y0 - 1, y0, bufs);
                s.markHistory();
                try streamRows(rows, &s, c, y0, y0 + trial_rows, bufs);
                try s.finish();
                sz.* += s.w.pos;
            }
        }
        var lo = size[0];
        var lo2: usize = std.math.maxInt(usize);
        for (size[1..]) |v| {
            if (v < lo) {
                lo2 = lo;
                lo = v;
            } else lo2 = @min(lo2, v);
        }
        if (lo2 / close_margin > lo2 - lo) continue; // close: sample more
        break;
    }
    var best: usize = 0;
    for (size, 0..) |v, i| {
        if (v < size[best]) best = i;
    }
    return cands[best];
}

// =================================================================== tests
const testing = std.testing;

test "png encode -> decode round trip (all modes)" {
    var prng = std.Random.DefaultPrng.init(7);
    const rnd = prng.random();
    const sizes = [_][2]u32{ .{ 1, 1 }, .{ 3, 2 }, .{ 17, 9 }, .{ 64, 70 }, .{ 129, 65 } };
    const strats = [_]FilterStrategy{ .none, .up, .paeth, .adaptive, .adaptive_fast, .auto };
    for (sizes) |sz| {
        const n = sz[0] * sz[1] * 4;
        const img = try testing.allocator.alloc(u8, n);
        defer testing.allocator.free(img);
        for (0..6) |kind| {
            for (0..n / 4) |i| {
                const x = i % sz[0];
                const y = i / sz[0];
                const px: [4]u8 = switch (kind) {
                    0 => .{ rnd.int(u8), rnd.int(u8), rnd.int(u8), rnd.int(u8) },
                    1 => .{ @truncate(x * 3), @truncate(y * 5), @truncate(x + y), 255 },
                    2 => .{ @truncate((x / 4) * 40), 0, 0, 255 }, // few colours, opaque
                    3 => .{ 10, 20, 30, if (x % 3 == 0) 0 else 255 }, // 2 colours with alpha
                    4 => if (rnd.boolean()) .{ 1, 2, 3, 255 } else .{ 9, 9, 9, 128 },
                    else => .{ @truncate(x * 7 + y), @truncate(y * 3), 77, @truncate(x * 9) },
                };
                img[i * 4 ..][0..4].* = px;
            }
            for (strats) |s| {
                for ([_]bool{ true, false }) |pal| {
                    const png = try encode(testing.allocator, img, sz[0], sz[1], .{ .filter = s, .palette = pal });
                    defer testing.allocator.free(png);
                    const dec = try decode(testing.allocator, png, .{});
                    defer dec.deinit(testing.allocator);
                    try testing.expectEqual(sz[0], dec.width);
                    try testing.expectEqualSlices(u8, img, dec.data);
                }
            }
        }
    }
}

/// FNV-1a 32 of decoded pixels (reference values computed with pngjs, see testdata/png_suite.json).
fn fnv(data: []const u8) u32 {
    var hsh: u32 = 0x811c9dc5;
    for (data) |b| hsh = (hsh ^ b) *% 0x01000193;
    return hsh;
}

test "png decode yeecord.png vs pngjs checksum" {
    const bytes = @embedFile("testdata/yeecord.png");
    const img = try decode(testing.allocator, bytes, .{});
    defer img.deinit(testing.allocator);
    const want = @import("testdata/png_refs.zig").yeecord;
    try testing.expectEqual(want[0], img.width);
    try testing.expectEqual(want[1], img.height);
    try testing.expectEqual(want[2], fnv(img.data));
}

test "png decode suite (all colour types / depths / interlace) vs pngjs" {
    const refs = @import("testdata/png_refs.zig");
    inline for (refs.suite) |e| {
        const bytes = @embedFile("testdata/png_suite/" ++ e[0]);
        const img = decode(testing.allocator, bytes, .{}) catch |err| {
            std.debug.print("{s}: {s}\n", .{ e[0], @errorName(err) });
            return err;
        };
        defer img.deinit(testing.allocator);
        testing.expectEqual(@as(u32, e[3]), fnv(img.data)) catch |err| {
            std.debug.print("mismatch {s}\n", .{e[0]});
            return err;
        };
    }
}

test "png decoder fuzz (mutations / truncations)" {
    var prng = std.Random.DefaultPrng.init(99);
    const rnd = prng.random();
    // seeds: our own encodings + suite files
    var seeds: std.ArrayList([]u8) = .empty;
    defer {
        for (seeds.items) |s| testing.allocator.free(s);
        seeds.deinit(testing.allocator);
    }
    var img: [40 * 30 * 4]u8 = undefined;
    for (&img, 0..) |*b, i| b.* = @truncate(i * 31 / 7);
    try seeds.append(testing.allocator, try encode(testing.allocator, &img, 40, 30, .{ .palette = false }));
    for (&img, 0..) |*b, i| b.* = if (i % 4 == 3) 255 else @truncate((i / 40) * 16);
    try seeds.append(testing.allocator, try encode(testing.allocator, &img, 40, 30, .{}));
    try seeds.append(testing.allocator, try testing.allocator.dupe(u8, @embedFile("testdata/yeecord.png")));
    const refs = @import("testdata/png_refs.zig");
    inline for (refs.suite) |e| try seeds.append(testing.allocator, try testing.allocator.dupe(u8, @embedFile("testdata/png_suite/" ++ e[0])));

    var buf: [16384]u8 = undefined;
    for (0..6000) |it| {
        const seed = seeds.items[it % seeds.items.len];
        const n = @min(seed.len, buf.len);
        @memcpy(buf[0..n], seed[0..n]);
        var len: usize = n;
        const muts = 1 + rnd.uintLessThan(usize, 8);
        for (0..muts) |_| {
            switch (rnd.uintLessThan(u8, 4)) {
                0 => buf[rnd.uintLessThan(usize, len)] = rnd.int(u8),
                1 => buf[rnd.uintLessThan(usize, len)] ^= @as(u8, 1) << rnd.int(u3),
                2 => len = 8 + rnd.uintLessThan(usize, len - 8 + 1),
                else => {
                    // keep the header but fix chunk-structure-ish damage deeper in the stream
                    const at = 33 + rnd.uintLessThan(usize, @max(1, len -| 33));
                    if (at < len) buf[at] = rnd.int(u8);
                },
            }
        }
        if (decode(testing.allocator, buf[0..len], .{ .max_pixels = 1 << 20 })) |im| im.deinit(testing.allocator) else |_| {}
    }
}

test "png decode fuma.jpg (a PNG with eXIf) vs pngjs checksum" {
    const img = try decode(testing.allocator, @embedFile("testdata/fuma.jpg"), .{});
    defer img.deinit(testing.allocator);
    const want = @import("testdata/png_refs.zig").fuma;
    try testing.expectEqual(want[0], img.width);
    try testing.expectEqual(want[2], fnv(img.data));
}
