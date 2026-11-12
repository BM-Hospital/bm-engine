//! Image XObjects (krilla `graphics/image/mod.rs`, takumi-pdf `raster.rs` / `paint.rs`):
//!
//! * a JPEG source that needs no recolouring embeds its original bytes (`/DCTDecode`, the
//!   colour space from its frame header, `/Decode[1 0 ...]` for Adobe CMYK);
//! * so does a PNG source that is grayscale, RGB or indexed without transparency and not
//!   interlaced (krilla `png.rs`): its IDAT stream with `/DecodeParms` PNG predictors (15), an
//!   `/Indexed` colour space over DeviceRGB for a palette;
//! * anything else embeds its decoded pixels: straight-alpha RGB, Flate-compressed, plus a
//!   DeviceGray `/SMask` image when any pixel is not opaque (written first, same category);
//! * one object per distinct source (by source bytes, else by pixels) and colour filter.
//!
//! Not ported: embedded ICC profiles, and krilla's own decoding of other PNGs (bm-engine embeds
//! its decoded pixmap demultiplied, as RGB even for a grayscale PNG with alpha).
const std = @import("std");
const w = @import("writer.zig");
const sf = @import("emit_surface.zig");
const raster = @import("../raster/raster.zig");
const render = @import("../render.zig");
const checksum = @import("../codec/checksum.zig");

const Ref = w.Ref;
const Ctx = sf.Ctx;

/// Colour transform applied to every pixel (CSS colour `filter`s), or null.
pub const PixelFilter = struct {
    ctx: *const anyopaque,
    apply: *const fn (ctx: *const anyopaque, rgba: [4]u8) [4]u8,
    key: u64,
};

const Jpeg = struct { w: u16, h: u16, comps: u8, adobe: bool };

/// Frame header of a baseline / progressive JPEG (SOF0..SOF15 except DHT / JPG / DAC).
fn jpegInfo(b: []const u8) ?Jpeg {
    if (b.len < 4 or b[0] != 0xFF or b[1] != 0xD8) return null;
    var i: usize = 2;
    var adobe = false;
    while (i + 4 <= b.len) {
        if (b[i] != 0xFF) return null;
        const m = b[i + 1];
        if (m == 0xFF) {
            i += 1;
            continue;
        }
        if (m == 0xD8 or (m >= 0xD0 and m <= 0xD7) or m == 0x01) {
            i += 2;
            continue;
        }
        const len = (@as(usize, b[i + 2]) << 8) | b[i + 3];
        if (len < 2 or i + 2 + len > b.len) return null;
        const seg = b[i + 4 .. i + 2 + len];
        if (m == 0xEE and seg.len >= 5 and std.mem.eql(u8, seg[0..5], "Adobe")) adobe = true;
        if (m >= 0xC0 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC) {
            if (seg.len < 6) return null;
            if (seg[0] != 8) return null; // 12-bit JPEGs are not DCT-passed
            return .{ .h = (@as(u16, seg[1]) << 8) | seg[2], .w = (@as(u16, seg[3]) << 8) | seg[4], .comps = seg[5], .adobe = adobe };
        }
        if (m == 0xDA) return null;
        i += 2 + len;
    }
    return null;
}

/// The encoded bytes of image source `src` (a `data:` URL or a registered resource), if known.
pub fn sourceBytes(r: *render.Renderer, a: std.mem.Allocator, src: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, src, "data:")) return render.decodeDataUri(a, src);
    for (r.images.items) |*e| {
        if (e.width == 0 and std.mem.eql(u8, e.src, src)) return e.data;
    }
    return null;
}

/// A JPEG source embedded as is (krilla `Image::from_jpeg`); null when `bytes` is no 8-bit
/// JPEG with 1, 3 or 4 components.
pub fn regJpeg(cx: *Ctx, bytes: []const u8) ?Ref {
    const info = jpegInfo(bytes) orelse return null;
    if (info.comps != 1 and info.comps != 3 and info.comps != 4) return null;
    var h = sf.Hasher.init('J');
    h.bytes(bytes);
    const key = h.final();
    if (cx.doc.cacheGet(key)) |r| return r;
    const r = cx.doc.alloc();
    const b = cx.doc.beginStream(r, .images, .{ .data = bytes });
    b.pairName("Type", "XObject");
    b.pairName("Subtype", "Image");
    b.pairName("Filter", "DCTDecode");
    b.pairInt("Width", info.w);
    b.pairInt("Height", info.h);
    b.pairName("ColorSpace", switch (info.comps) {
        1 => "DeviceGray",
        3 => "DeviceRGB",
        else => "DeviceCMYK",
    });
    if (info.comps == 4) {
        // krilla inverts every CMYK / YCCK JPEG (Photoshop convention)
        b.key("Decode");
        b.reals(&.{ 1, 0, 1, 0, 1, 0, 1, 0 });
    }
    b.pairInt("BitsPerComponent", 8);
    cx.doc.endDict();
    cx.doc.cachePut(key, r);
    return r;
}

const Png = struct { w: u32, h: u32, depth: u8, color: u8, idat: []const u8, palette: ?[]const u8 };

/// krilla `PngData::new`: a PNG whose IDAT stream can be embedded as is: not interlaced, grayscale,
/// RGB or indexed (with its palette), no `tRNS`, valid CRCs on the critical chunks, no unknown
/// critical chunk, ending in IEND. The IDAT data is concatenated into `a`.
fn pngInfo(a: std.mem.Allocator, b: []const u8) ?Png {
    const magic = "\x89PNG\r\n\x1a\n";
    if (b.len < magic.len or !std.mem.eql(u8, b[0..magic.len], magic)) return null;
    var i: usize = magic.len;
    var out: Png = .{ .w = 0, .h = 0, .depth = 0, .color = 0, .idat = &.{}, .palette = null };
    var idat: std.ArrayList(u8) = .empty;
    var seen_idat = false;
    var palette_seen = false;
    var first = true;
    while (i < b.len) {
        if (i + 12 > b.len) return null;
        const len = std.mem.readInt(u32, b[i..][0..4], .big);
        if (len > b.len - i - 12) return null;
        const kind = b[i + 4 .. i + 8];
        const data = b[i + 8 .. i + 8 + len];
        const crc = std.mem.readInt(u32, b[i + 8 + len ..][0..4], .big);
        i += 12 + len;
        const critical = kind[0] & 0x20 == 0;
        const crc_ok = checksum.crc32(checksum.crc32(0, kind), data) == crc;
        if (first) {
            first = false;
            if (!std.mem.eql(u8, kind, "IHDR") or !crc_ok or data.len != 13) return null;
            out.w = std.mem.readInt(u32, data[0..4], .big);
            out.h = std.mem.readInt(u32, data[4..8], .big);
            out.depth = data[8];
            out.color = data[9];
            const depth_ok = switch (out.color) {
                0 => out.depth == 1 or out.depth == 2 or out.depth == 4 or out.depth == 8 or out.depth == 16,
                2 => out.depth == 8 or out.depth == 16,
                3 => out.depth == 1 or out.depth == 2 or out.depth == 4 or out.depth == 8,
                4, 6 => out.depth == 8 or out.depth == 16,
                else => false,
            };
            if (!depth_ok or out.w == 0 or out.h == 0 or data[10] != 0 or data[11] != 0 or data[12] > 1) return null;
            // interlaced, or with an alpha channel
            if (data[12] != 0 or !(out.color == 0 or out.color == 2 or out.color == 3)) return null;
            continue;
        }
        if (critical and !crc_ok) return null;
        if (std.mem.eql(u8, kind, "IHDR") or std.mem.eql(u8, kind, "tRNS")) return null;
        if (std.mem.eql(u8, kind, "PLTE")) {
            const max_len: usize = switch (out.color) {
                3 => 3 * (@as(usize, 1) << @intCast(out.depth)),
                2 => 3 * 256,
                else => return null,
            };
            if (palette_seen or seen_idat or data.len == 0 or data.len % 3 != 0 or data.len > max_len) return null;
            palette_seen = true;
            if (out.color == 3) out.palette = data;
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            seen_idat = true;
            idat.appendSlice(a, data) catch return null;
        } else if (std.mem.eql(u8, kind, "IEND")) {
            if (out.color == 3 and out.palette == null) return null;
            if (!seen_idat) return null;
            out.idat = idat.items;
            return out;
        } else if (critical) return null;
    }
    return null;
}

/// A PNG source whose IDAT stream is embedded as is (krilla `Image::from_png` / `PngRepr`):
/// `/FlateDecode` with the PNG predictors, `/Indexed` over DeviceRGB for a palette image; null
/// when the PNG cannot take that path (it is then decoded).
pub fn regPng(cx: *Ctx, bytes: []const u8) ?Ref {
    var h = sf.Hasher.init('P');
    h.bytes(bytes);
    const key = h.final();
    if (cx.doc.cacheGet(key)) |r| return r;
    const info = pngInfo(cx.a, bytes) orelse return null;
    const colors: i64 = switch (info.color) {
        2 => 3,
        else => 1,
    };
    const r = cx.doc.alloc();
    const b = cx.doc.beginStream(r, .images, .{ .data = info.idat, .flate = true });
    b.pairName("Type", "XObject");
    b.pairName("Subtype", "Image");
    b.pairName("Filter", "FlateDecode");
    b.key("DecodeParms");
    b.dict();
    b.pairInt("Predictor", 15);
    b.pairInt("Colors", colors);
    b.pairInt("BitsPerComponent", info.depth);
    b.pairInt("Columns", info.w);
    b.dictEnd();
    b.pairInt("Width", info.w);
    b.pairInt("Height", info.h);
    b.key("ColorSpace");
    if (info.palette) |pal| {
        b.arr();
        b.name("Indexed");
        b.name("DeviceRGB");
        b.int(@intCast(pal.len / 3 - 1));
        b.str(pal);
        b.arrEnd();
    } else b.name(if (info.color == 2) "DeviceRGB" else "DeviceGray");
    b.pairInt("BitsPerComponent", info.depth);
    cx.doc.endDict();
    cx.doc.cachePut(key, r);
    return r;
}

/// A premultiplied pixmap as an image XObject (krilla `Image::from_rgba8` after takumi's
/// `bitmap_image`: demultiplied, filtered). `key` identifies the pixels (e.g. the source bytes
/// hash); 0 hashes the pixels.
pub fn regPixmap(cx: *Ctx, pm: *const raster.Pixmap, key_in: u64, filter: ?PixelFilter) Ref {
    var h = sf.Hasher.init('I');
    if (key_in != 0) h.u64_(key_in) else h.bytes(pm.data);
    h.u64_(pm.width);
    h.u64_(pm.height);
    h.u64_(if (filter) |f| f.key else 0);
    const key = h.final();
    if (cx.doc.cacheGet(key)) |r| return r;
    const a = cx.a;
    const n: usize = @as(usize, pm.width) * pm.height;
    const px = a.dupe(u8, pm.data[0 .. n * 4]) catch return oom(cx);
    render.unpremultiply(px);
    const rgb = a.alloc(u8, n * 3) catch return oom(cx);
    const alpha = a.alloc(u8, n) catch return oom(cx);
    var translucent = false;
    for (0..n) |i| {
        var p: [4]u8 = px[i * 4 ..][0..4].*;
        if (filter) |f| p = f.apply(f.ctx, p);
        rgb[i * 3 ..][0..3].* = p[0..3].*;
        alpha[i] = p[3];
        if (p[3] != 255) translucent = true;
    }
    var smask: ?Ref = null;
    if (translucent) {
        const sr = cx.doc.alloc();
        const e = cx.doc.encode(alpha, .flate);
        const b = cx.doc.beginStream(sr, .images, e);
        b.pairName("Type", "XObject");
        b.pairName("Subtype", "Image");
        b.filter(e);
        b.pairInt("Width", pm.width);
        b.pairInt("Height", pm.height);
        b.pairName("ColorSpace", "DeviceGray");
        b.pairInt("BitsPerComponent", 8);
        cx.doc.endDict();
        smask = sr;
    }
    const r = cx.doc.alloc();
    const e = cx.doc.encode(rgb, .flate);
    const icc = @import("conform.zig").rgbSpace(cx); // [conformance] PDF/A: ICC-based sRGB
    const b = cx.doc.beginStream(r, .images, e);
    b.pairName("Type", "XObject");
    b.pairName("Subtype", "Image");
    b.filter(e);
    b.pairInt("Width", pm.width);
    b.pairInt("Height", pm.height);
    if (icc) |cs| b.pairRef("ColorSpace", cs) else b.pairName("ColorSpace", "DeviceRGB");
    b.pairInt("BitsPerComponent", 8);
    if (smask) |sr| b.pairRef("SMask", sr);
    cx.doc.endDict();
    cx.doc.cachePut(key, r);
    return r;
}

fn oom(cx: *Ctx) Ref {
    cx.doc.b.failed = true;
    return cx.doc.alloc();
}

test "jpeg frame header" {
    // SOI, APP0 (len 4), SOF0: 8-bit, 2x3, 3 components
    const b = [_]u8{ 0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 17, 8, 0, 3, 0, 2, 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1 };
    const info = jpegInfo(&b).?;
    try std.testing.expectEqual(@as(u16, 2), info.w);
    try std.testing.expectEqual(@as(u16, 3), info.h);
    try std.testing.expectEqual(@as(u8, 3), info.comps);
}

test "png passthrough eligibility" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const aa = arena.allocator();
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
        fn png(al: std.mem.Allocator, color: u8, extra: ?[]const u8) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            try out.appendSlice(al, "\x89PNG\r\n\x1a\n");
            try chunk(&out, al, "IHDR", &.{ 0, 0, 0, 2, 0, 0, 0, 3, 8, color, 0, 0, 0 });
            if (color == 3) try chunk(&out, al, "PLTE", &.{ 255, 0, 0, 0, 0, 255 });
            if (extra) |k| try chunk(&out, al, k, &.{ 1, 2 });
            try chunk(&out, al, "IDAT", "abc");
            try chunk(&out, al, "tEXt", "k\x00v");
            try chunk(&out, al, "IDAT", "de");
            try chunk(&out, al, "IEND", "");
            return out.items;
        }
    };
    const rgb = pngInfo(aa, try Build.png(aa, 2, null)).?;
    try std.testing.expectEqual(@as(u32, 2), rgb.w);
    try std.testing.expectEqual(@as(u32, 3), rgb.h);
    try std.testing.expectEqualStrings("abcde", rgb.idat);
    try std.testing.expect(rgb.palette == null);
    const pal = pngInfo(aa, try Build.png(aa, 3, null)).?;
    try std.testing.expectEqual(@as(usize, 6), pal.palette.?.len);
    // transparency, an alpha channel, an unknown critical chunk: decoded instead
    try std.testing.expect(pngInfo(aa, try Build.png(aa, 2, "tRNS")) == null);
    try std.testing.expect(pngInfo(aa, try Build.png(aa, 6, null)) == null);
    try std.testing.expect(pngInfo(aa, try Build.png(aa, 2, "ABCD")) == null);
}
