//! Wasm root for comparing src/raster/blend.zig with the takumi oracle and timing it
//! (bench/probe/raster/blend_oracle.mjs). The `raster` module root is blend.zig itself.
const std = @import("std");
const b = @import("raster");

const Pixmap = std.meta.Child(@typeInfo(@TypeOf(b.drawPixmapBlend)).@"fn".param_types[0].?);
const MAX_PX = 1200 * 630;

var dst_buf: [MAX_PX * 4]u8 align(4) = undefined;
var src_buf: [MAX_PX * 4]u8 align(4) = undefined;

export fn dstPtr() [*]u8 {
    return &dst_buf;
}

export fn srcPtr() [*]u8 {
    return &src_buf;
}

/// Blends src (w x h, premultiplied) onto dst (w x h, premultiplied) `reps` times.
export fn blend(w: u32, h: u32, mode: u32, opacity: f32, reps: u32) void {
    if (@as(u64, w) * h > MAX_PX or mode > @intFromEnum(b.BlendMode.plus_lighter)) return;
    var d: Pixmap = .{ .width = w, .height = h, .data = &dst_buf };
    const s: Pixmap = .{ .width = w, .height = h, .data = &src_buf };
    for (0..reps) |_| b.drawPixmapBlend(&d, &s, 0, 0, opacity, @enumFromInt(mode), null);
}

/// Multiplies dst by the alpha (0) or luminance (1) of src, `reps` times.
export fn mask(w: u32, h: u32, source: u32, reps: u32) void {
    if (@as(u64, w) * h > MAX_PX) return;
    var d: Pixmap = .{ .width = w, .height = h, .data = &dst_buf };
    const s: Pixmap = .{ .width = w, .height = h, .data = &src_buf };
    for (0..reps) |_| b.maskMultiplyPixmap(&d, &s, 0, 0, if (source == 0) .alpha else .luminance);
}

/// Demultiplies dst in place (the takumi `raw` output is straight alpha).
export fn straight(w: u32, h: u32) void {
    if (@as(u64, w) * h > MAX_PX) return;
    var d: Pixmap = .{ .width = w, .height = h, .data = &dst_buf };
    d.toStraightAlpha();
}
