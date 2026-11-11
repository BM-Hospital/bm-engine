//! Image codecs for bm-engine: format sniffing, header-only dimensions, decoders
//! (PNG/APNG, JPEG, WebP lossless + lossy, GIF), animated frame access (GIF / WebP / APNG)
//! and encoders (PNG, JPEG, WebP lossless, animated APNG / GIF / WebP, ICO).
//!
//! Optional parts are only linked when their entry points are referenced: lossy WebP
//! (`decodeEx(.., .{ .webp_lossy = false })` compiles it out), animation (`frameCount`,
//! `decodeFrame`, `anim.Animator`), animated encoders (`encodeApng/Gif/WebpAnim`), ICO.
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
pub const vp8 = @import("vp8.zig");
pub const anim = @import("anim.zig");
pub const anim_enc = @import("anim_enc.zig");
pub const ico = @import("ico.zig");
pub const Frame = anim.Frame;
pub const AnimFrame = anim_enc.AnimFrame;
pub const AnimOptions = anim_enc.AnimOptions;

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
/// Animated GIF / WebP / APNG decode to their first frame (APNG: the default image).
pub fn decode(alloc: std.mem.Allocator, bytes: []const u8, limits: Limits) Error!Image {
    return decodeEx(alloc, bytes, limits, .{});
}

/// Compile-time decoder feature switches (for size-constrained builds).
pub const DecodeFeatures = struct {
    /// Lossy WebP (VP8 + ALPH). When false such files return error.UnsupportedFormat.
    webp_lossy: bool = true,
};

/// `decode` with compile-time feature selection.
pub fn decodeEx(alloc: std.mem.Allocator, bytes: []const u8, limits: Limits, comptime f: DecodeFeatures) Error!Image {
    return switch (sniff(bytes)) {
        .png => png.decode(alloc, bytes, limits),
        .jpeg => jpeg_dec.decode(alloc, bytes, limits),
        .webp => webp_dec.decodeEx(alloc, bytes, limits, .{ .lossy = f.webp_lossy }),
        .gif => gif.decode(alloc, bytes, limits),
        else => error.UnsupportedFormat,
    };
}

/// Number of frames: animated GIF / WebP / APNG frame count, 1 for any other decodable
/// image, 0 if the format is not recognised. Header scan only (no pixel decode).
pub fn frameCount(bytes: []const u8) u32 {
    const n = anim.frameCount(bytes);
    if (n > 0) return n;
    return if (sniff(bytes) == .jpeg) 1 else 0;
}

/// Frame `index` of an animation, fully composited on the canvas (straight RGBA) with its
/// delay; still images have one frame (delay 0). Compositing restarts from frame 0 on every
/// call; use `anim.Animator` to walk all frames in O(n). Result allocated from `alloc`.
pub fn decodeFrame(alloc: std.mem.Allocator, bytes: []const u8, index: u32, limits: Limits) Error!Frame {
    if (sniff(bytes) == .jpeg) {
        if (index != 0) return error.InvalidData;
        return .{ .image = try jpeg_dec.decode(alloc, bytes, limits), .delay_ms = 0 };
    }
    return anim.decodeFrame(alloc, bytes, index, limits);
}

/// Animated PNG (takumi renderAnimation "apng"); see `anim_enc.encodeApng`.
pub fn encodeApng(alloc: std.mem.Allocator, frames: []const AnimFrame, w: u32, h: u32, opts: AnimOptions) anim_enc.EncodeError![]u8 {
    return anim_enc.encodeApng(alloc, frames, w, h, opts);
}

/// Animated GIF with per-frame palettes; see `anim_enc.encodeGif`.
pub fn encodeGif(alloc: std.mem.Allocator, frames: []const AnimFrame, w: u32, h: u32, opts: AnimOptions) anim_enc.EncodeError![]u8 {
    return anim_enc.encodeGif(alloc, frames, w, h, opts);
}

/// Animated lossless WebP (VP8X + ANIM + ANMF/VP8L); see `anim_enc.encodeWebpAnim`.
pub fn encodeWebpAnim(alloc: std.mem.Allocator, frames: []const AnimFrame, w: u32, h: u32, opts: AnimOptions) anim_enc.EncodeError![]u8 {
    return anim_enc.encodeWebpAnim(alloc, frames, w, h, opts);
}

/// ICO with one PNG-compressed entry (Vista+); each side <= 256 else error.InvalidDimensions.
pub fn encodeIco(alloc: std.mem.Allocator, straight_rgba: []const u8, w: u32, h: u32) ![]u8 {
    return ico.encodeIco(alloc, straight_rgba, w, h);
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
    _ = vp8;
    _ = anim;
    _ = anim_enc;
    _ = ico;
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
    // Lossy / VP8X / animated WebP, APNG.
    const lossy = @embedFile("testdata/vp8_q75.webp");
    try std.testing.expectEqual(Format.webp, sniff(lossy));
    try std.testing.expectEqual(Dimensions{ .w = 64, .h = 48 }, dimensions(lossy).?);
    try std.testing.expectEqual(Dimensions{ .w = 37, .h = 29 }, dimensions(@embedFile("testdata/vp8_alpha_raw.webp")).?);
    try std.testing.expectEqual(Dimensions{ .w = 48, .h = 40 }, dimensions(@embedFile("testdata/anim_lossy.webp")).?);
    try std.testing.expectEqual(Dimensions{ .w = 20, .h = 16 }, dimensions(@embedFile("testdata/anim.gif")).?);
    try std.testing.expectEqual(@as(u32, 5), frameCount(@embedFile("testdata/anim_mixed.webp")));
    try std.testing.expectEqual(@as(u32, 1), frameCount(lossy));
    try std.testing.expectEqual(@as(u32, 1), frameCount(@embedFile("testdata/jpeg_b420.jpg")));
    try std.testing.expectEqual(@as(u32, 1), frameCount(@embedFile("testdata/yeecord.png")));
}

test "decode dispatches lossy webp; animated files decode to frame 0" {
    const a = std.testing.allocator;
    const img = try decode(a, @embedFile("testdata/vp8_q75.webp"), .{});
    defer img.deinit(a);
    try std.testing.expectEqualSlices(u8, @embedFile("testdata/vp8_q75.rgba"), img.data);
    try std.testing.expectError(error.UnsupportedFormat, decodeEx(a, @embedFile("testdata/vp8_q75.webp"), .{}, .{ .webp_lossy = false }));
    inline for (.{ "anim_lossy.webp", "anim.gif" }) |n| {
        const file = @embedFile("testdata/" ++ n);
        const d = try decode(a, file, .{});
        defer d.deinit(a);
        const f0 = try decodeFrame(a, file, 0, .{});
        defer f0.image.deinit(a);
        try std.testing.expectEqualSlices(u8, f0.image.data, d.data);
    }
    const j = try decodeFrame(a, @embedFile("testdata/jpeg_b420.jpg"), 0, .{});
    defer j.image.deinit(a);
    try std.testing.expect(j.image.width > 0);
}
