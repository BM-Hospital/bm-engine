//! Image codecs for bm-engine: format sniffing, header-only dimensions, decoders
//! (PNG, JPEG, WebP lossless, GIF) and encoders (PNG, JPEG, WebP lossless).
//! Everything is pure Zig, allocation goes through explicit allocators, no std.Io.
const std = @import("std");
const types = @import("types.zig");

pub const Image = types.Image;
pub const Limits = types.Limits;
pub const Error = types.Error;

pub const checksum = @import("checksum.zig");
pub const inflate = @import("inflate.zig");
pub const deflate = @import("deflate.zig");
pub const png = @import("png.zig");
pub const jpeg_dec = @import("jpeg_dec.zig");
pub const jpeg_enc = @import("jpeg_enc.zig");
pub const JpegOptions = jpeg_enc.Options;
pub const webp_dec = @import("webp_dec.zig");
pub const webp_enc = @import("webp_enc.zig");
pub const WebpOptions = webp_enc.Options;
pub const gif = @import("gif.zig");

pub const Level = deflate.Level;
pub const FilterStrategy = png.FilterStrategy;
pub const PngOptions = png.EncodeOptions;

pub const Format = enum { png, jpeg, webp, gif, bmp, unknown };

/// Magic-number detection.
pub fn sniff(bytes: []const u8) Format {
    if (bytes.len >= 8 and std.mem.eql(u8, bytes[0..8], &png.signature)) return .png;
    if (bytes.len >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF) return .jpeg;
    if (bytes.len >= 12 and std.mem.eql(u8, bytes[0..4], "RIFF") and std.mem.eql(u8, bytes[8..12], "WEBP")) return .webp;
    if (bytes.len >= 6 and (std.mem.eql(u8, bytes[0..6], "GIF87a") or std.mem.eql(u8, bytes[0..6], "GIF89a"))) return .gif;
    if (bytes.len >= 2 and bytes[0] == 'B' and bytes[1] == 'M') return .bmp;
    return .unknown;
}

pub const Dimensions = struct { w: u32, h: u32 };

/// Header-only image size (cheap). For JPEG this is the stored size (EXIF orientation not applied).
pub fn dimensions(bytes: []const u8) ?Dimensions {
    const d: ?[2]u32 = switch (sniff(bytes)) {
        .png => png.dimensions(bytes),
        .jpeg => jpeg_dec.dimensions(bytes),
        .webp => webp_dec.dimensions(bytes),
        .gif => gif.dimensions(bytes),
        else => null,
    };
    const v = d orelse return null;
    return .{ .w = v[0], .h = v[1] };
}

/// Decodes any supported format to straight RGBA8. The pixel buffer is allocated from `alloc`
/// (caller frees with `image.deinit(alloc)`); temporaries are freed before returning, so an
/// arena or a general-purpose allocator both work.
pub fn decode(alloc: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!Image {
    return switch (sniff(bytes)) {
        .png => png.decode(alloc, bytes, limits),
        .jpeg => jpeg_dec.decode(alloc, bytes, limits),
        .webp => webp_dec.decode(alloc, bytes, limits),
        .gif => gif.decode(alloc, bytes, limits),
        else => error.UnsupportedFormat,
    };
}

/// PNG encode of straight RGBA8 (see `png.EncodeOptions`).
pub fn encodePng(alloc: std.mem.Allocator, straight_rgba: []const u8, w: u32, h: u32, opts: PngOptions) png.EncodeError![]u8 {
    return png.encode(alloc, straight_rgba, w, h, opts);
}

/// Baseline JPEG encode of straight RGBA8 (see `jpeg_enc.Options`; defaults mirror takumi: q75, 4:4:4, alpha dropped).
pub fn encodeJpeg(alloc: std.mem.Allocator, straight_rgba: []const u8, w: u32, h: u32, opts: JpegOptions) jpeg_enc.Error![]u8 {
    return jpeg_enc.encode(alloc, straight_rgba, w, h, opts);
}

/// Lossless WebP (VP8L) encode of straight RGBA8 (takumi wasm always writes VP8L).
pub fn encodeWebp(alloc: std.mem.Allocator, straight_rgba: []const u8, w: u32, h: u32, opts: WebpOptions) webp_enc.EncodeError![]u8 {
    return webp_enc.encodeLossless(alloc, straight_rgba, w, h, opts);
}

test {
    _ = @import("huffman.zig");
    _ = checksum;
    _ = inflate;
    _ = deflate;
    _ = png;
    _ = jpeg_dec;
    _ = jpeg_enc;
    _ = webp_dec;
    _ = webp_enc;
    _ = gif;
    _ = @import("bytes.zig");
}

test "sniff" {
    try std.testing.expectEqual(Format.png, sniff(@embedFile("testdata/yeecord.png")));
    // note: testdata/fuma.jpg (copied from takumi) is actually a PNG with an eXIf chunk
    try std.testing.expectEqual(Format.png, sniff(@embedFile("testdata/fuma.jpg")));
    try std.testing.expectEqual(Format.jpeg, sniff(@embedFile("testdata/jpeg_b420.jpg")));
    const d = dimensions(@embedFile("testdata/jpeg_luma_prog.jpg")).?;
    try std.testing.expectEqual(@as(u32, 525), d.w);
    try std.testing.expectEqual(Format.webp, sniff(@embedFile("testdata/webp_takumi.webp")));
    try std.testing.expectEqual(Format.gif, sniff(@embedFile("testdata/gif_takumi.gif")));
    try std.testing.expect(dimensions(@embedFile("testdata/webp_takumi.webp")) != null);
    try std.testing.expect(dimensions(@embedFile("testdata/gif_takumi.gif")) != null);
    try std.testing.expectEqual(Format.unknown, sniff("hello"));
}
