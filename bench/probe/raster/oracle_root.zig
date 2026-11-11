//! Wasm root for comparing raster output with the takumi oracle (bench/probe/raster/oracle.mjs).
const std = @import("std");
const r = @import("raster");
const alloc = std.heap.wasm_allocator;

var stops: [16]r.GradientStop = undefined;
var out: r.Pixmap = r.Pixmap.empty;

export fn set_stop(i: u32, off: f32, red: u32, green: u32, blue: u32, a: u32) void {
    stops[i & 15] = .{ .offset = off, .color = r.Color.rgba(@truncate(red), @truncate(green), @truncate(blue), @truncate(a)) };
}

fn begin(w: u32, h: u32) void {
    out.deinit(alloc);
    out = r.Pixmap.init(alloc, w, h) catch unreachable;
}

fn finish() [*]u8 {
    out.toStraightAlpha();
    return out.data.ptr;
}

fn fullRect() r.Rect {
    return .{ .x = 0, .y = 0, .w = @floatFromInt(out.width), .h = @floatFromInt(out.height) };
}

export fn linear(w: u32, h: u32, x0: f32, y0: f32, x1: f32, y1: f32, n: u32, rep: u32) [*]u8 {
    begin(w, h);
    r.fillRect(&out, fullRect(), &.{ .linear = .{ .p0 = .{ .x = x0, .y = y0 }, .p1 = .{ .x = x1, .y = y1 }, .stops = stops[0..n], .repeating = rep != 0 } }, null);
    return finish();
}

export fn radial(w: u32, h: u32, cx: f32, cy: f32, rx: f32, ry: f32, n: u32, rep: u32) [*]u8 {
    begin(w, h);
    r.fillRect(&out, fullRect(), &.{ .radial = .{ .center = .{ .x = cx, .y = cy }, .rx = rx, .ry = ry, .stops = stops[0..n], .repeating = rep != 0 } }, null);
    return finish();
}

export fn conic(w: u32, h: u32, cx: f32, cy: f32, start: f32, n: u32, rep: u32, max_radius: f32) [*]u8 {
    begin(w, h);
    r.fillRect(&out, fullRect(), &.{ .conic = .{ .center = .{ .x = cx, .y = cy }, .start_angle = start, .stops = stops[0..n], .repeating = rep != 0, .max_radius = max_radius } }, null);
    return finish();
}

/// White canvas, black shadow of an integer box blurred by `sigma`, white box on top.
export fn shadow(w: u32, h: u32, bx: f32, by: f32, bw: f32, bh: f32, sigma: f32) [*]u8 {
    begin(w, h);
    out.clear(r.Color.white);
    var m = r.maskFromRect(alloc, .{ .x = bx, .y = by, .w = bw, .h = bh }, .{ .x = -4096, .y = -4096, .w = 8192, .h = 8192 }) catch unreachable;
    defer m.deinit(alloc);
    r.blurMaskClipped(alloc, &m, sigma, out.bounds()) catch unreachable;
    r.fillMask(&out, &m, &.{ .solid = r.Color.black }, null);
    r.fillRect(&out, .{ .x = bx, .y = by, .w = bw, .h = bh }, &.{ .solid = r.Color.white }, null);
    return finish();
}
