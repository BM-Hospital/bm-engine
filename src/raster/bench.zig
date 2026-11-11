//! Native micro-benchmark (not part of the wasm build, Windows timer).
//! Run from the repo root:  zig run -O ReleaseFast src/raster/bench.zig
const std = @import("std");
const r = @import("raster.zig");

extern "kernel32" fn QueryPerformanceCounter(count: *i64) callconv(.winapi) i32;
extern "kernel32" fn QueryPerformanceFrequency(freq: *i64) callconv(.winapi) i32;

fn now() f64 {
    var c: i64 = 0;
    var f: i64 = 1;
    _ = QueryPerformanceCounter(&c);
    _ = QueryPerformanceFrequency(&f);
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(f));
}

var sink: u64 = 0;

fn touch(pm: *const r.Pixmap) void {
    if (pm.data.len > 0) sink +%= pm.data[pm.data.len / 2 + 1];
}

/// Best-of-N wall time in microseconds.
fn bench(comptime name: []const u8, iters: usize, ctx: anytype, comptime f: anytype) void {
    var best: f64 = 1e30;
    for (0..7) |_| {
        const t0 = now();
        for (0..iters) |_| f(ctx);
        const dt = (now() - t0) / @as(f64, @floatFromInt(iters));
        best = @min(best, dt);
    }
    std.debug.print("{s:<44} {d:>10.2} us\n", .{ name, best * 1e6 });
}

const W = 1200;
const H = 630;

const Ctx = struct {
    alloc: std.mem.Allocator,
    fba: *std.heap.FixedBufferAllocator,
    rz: *r.Rasterizer,
    dst: *r.Pixmap,
    src: *r.Pixmap,
    big: *r.Pixmap,
    glyph: *r.Path,
    rrect: *r.Path,
    border: *r.Path,
};

fn glyphPath(alloc: std.mem.Allocator, p: *r.Path) !void {
    // an "8"-like glyph in a 1000-unit em: 3 contours of 8 quads each (~typical TrueType glyph)
    const rings = [_][3]f32{ .{ 500, 300, 280 }, .{ 500, 300, 150 }, .{ 500, 720, 200 } };
    for (rings) |ring| {
        const n = 8;
        var i: usize = 0;
        while (i <= n) : (i += 1) {
            const a = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, n));
            const x = ring[0] + ring[2] * @cos(a);
            const y = ring[1] + ring[2] * @sin(a);
            if (i == 0) {
                try p.moveTo(alloc, x, y);
            } else {
                const am = a - std.math.pi / @as(f32, n);
                const rc = ring[2] / @cos(std.math.pi / @as(f32, n));
                try p.quadTo(alloc, ring[0] + rc * @cos(am), ring[1] + rc * @sin(am), x, y);
            }
        }
        try p.close(alloc);
    }
}

const red: r.Paint = .{ .solid = r.Color.rgb(0x33, 0x66, 0x99) };
const stops2 = [_]r.GradientStop{
    .{ .offset = 0, .color = r.Color.rgb(255, 0, 80) },
    .{ .offset = 1, .color = r.Color.rgb(0, 60, 255) },
};
const full: r.Rect = .{ .x = 0, .y = 0, .w = W, .h = H };

fn bGlyph(c: Ctx) void {
    c.fba.reset();
    const m = c.rz.rasterize(c.fba.allocator(), c.glyph, r.Affine.translate(3.3, 2.7).mul(r.Affine.scale(0.04, 0.04)), .nonzero, c.dst.bounds()) catch unreachable;
    sink +%= m.data[m.data.len / 2];
}
fn bGlyphFill(c: Ctx) void {
    c.rz.fillPath(c.dst, c.glyph, r.Affine.translate(103.3, 52.7).mul(r.Affine.scale(0.04, 0.04)), .nonzero, &red, null) catch unreachable;
}
fn bGlyphOneShot(c: Ctx) void {
    c.fba.reset();
    const m = r.rasterize(c.fba.allocator(), c.glyph, r.Affine.translate(3.3, 2.7).mul(r.Affine.scale(0.04, 0.04)), .nonzero, c.dst.bounds()) catch unreachable;
    sink +%= m.data[m.data.len / 2];
}
fn bSolid(c: Ctx) void {
    r.fillRect(c.dst, full, &red, null);
    touch(c.dst);
}
fn bSolidAlpha(c: Ctx) void {
    r.fillRect(c.dst, full, &.{ .solid = r.Color.rgba(10, 20, 30, 128) }, null);
    touch(c.dst);
}
fn bLinearH(c: Ctx) void {
    r.fillRect(c.dst, full, &.{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = W, .y = 0 }, .stops = &stops2 } }, null);
    touch(c.dst);
}
fn bLinearV(c: Ctx) void {
    r.fillRect(c.dst, full, &.{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 0, .y = H }, .stops = &stops2 } }, null);
    touch(c.dst);
}
fn bLinearD(c: Ctx) void {
    r.fillRect(c.dst, full, &.{ .linear = .{ .p0 = .{ .x = 100, .y = 0 }, .p1 = .{ .x = 1100, .y = 630 }, .stops = &stops2 } }, null);
    touch(c.dst);
}
fn bRadial(c: Ctx) void {
    r.fillRect(c.dst, full, &.{ .radial = .{ .center = .{ .x = 600, .y = 315 }, .rx = 600, .ry = 315, .stops = &stops2 } }, null);
    touch(c.dst);
}
fn bConic(c: Ctx) void {
    r.fillRect(c.dst, full, &.{ .conic = .{ .center = .{ .x = 600, .y = 315 }, .start_angle = 0.5, .stops = &stops2, .max_radius = 678 } }, null);
    touch(c.dst);
}
fn bRRect(c: Ctx) void {
    c.rz.fillPath(c.dst, c.rrect, r.Affine.identity, .nonzero, &red, null) catch unreachable;
    touch(c.dst);
}
fn bRRectOneShot(c: Ctx) void {
    r.fillPath(c.alloc, c.dst, c.rrect, r.Affine.identity, .nonzero, &red, null) catch unreachable;
    touch(c.dst);
}
fn bRRectGrad(c: Ctx) void {
    c.rz.fillPath(c.dst, c.rrect, r.Affine.identity, .nonzero, &.{ .linear = .{ .p0 = .{ .x = 100, .y = 0 }, .p1 = .{ .x = 1100, .y = 630 }, .stops = &stops2 } }, null) catch unreachable;
    touch(c.dst);
}
fn bRRectRot(c: Ctx) void {
    const t = r.Affine.translate(600, 315).mul(r.Affine.rotate(0.1)).mul(r.Affine.scale(0.8, 0.8)).mul(r.Affine.translate(-600, -315));
    c.rz.fillPath(c.dst, c.rrect, t, .nonzero, &red, null) catch unreachable;
    touch(c.dst);
}
fn bBorder(c: Ctx) void {
    c.rz.fillPath(c.dst, c.border, r.Affine.identity, .evenodd, &red, null) catch unreachable;
    touch(c.dst);
}
fn bBlit(c: Ctx) void {
    r.drawPixmap(c.dst, c.src, r.Affine.identity, 1, .bilinear, null);
    touch(c.dst);
}
fn bBlitOpacity(c: Ctx) void {
    r.drawPixmap(c.dst, c.src, r.Affine.translate(3, 2), 0.5, .bilinear, null);
    touch(c.dst);
}
fn bScale(c: Ctx) void {
    r.drawPixmap(c.dst, c.src, r.Affine.translate(-10.5, -7.25).mul(r.Affine.scale(1.3, 1.3)), 1, .bilinear, null);
    touch(c.dst);
}
fn bRotate(c: Ctx) void {
    const t = r.Affine.translate(600, 315).mul(r.Affine.rotate(0.2)).mul(r.Affine.translate(-600, -315));
    r.drawPixmap(c.dst, c.src, t, 1, .bilinear, null);
    touch(c.dst);
}
fn bResample(c: Ctx) void {
    var out = r.resample(c.alloc, c.big, W, H) catch unreachable;
    touch(&out);
    out.deinit(c.alloc);
}
fn bBlurMask(c: Ctx) void {
    var m = r.maskFromRect(c.alloc, .{ .x = 100, .y = 100, .w = 400, .h = 300 }, c.dst.bounds()) catch unreachable;
    r.blurMask(c.alloc, &m, 10) catch unreachable;
    sink +%= m.data[m.data.len / 2];
    m.deinit(c.alloc);
}
fn bBlurMaskSmall(c: Ctx) void {
    var m = r.maskFromRect(c.alloc, .{ .x = 100, .y = 100, .w = 400, .h = 300 }, c.dst.bounds()) catch unreachable;
    r.blurMask(c.alloc, &m, 1.5) catch unreachable;
    sink +%= m.data[m.data.len / 2];
    m.deinit(c.alloc);
}
fn bBlurPixmap(c: Ctx) void {
    r.blurPixmap(c.alloc, c.dst, 8) catch unreachable;
    touch(c.dst);
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var dst = try r.Pixmap.init(alloc, W, H);
    var src = try r.Pixmap.init(alloc, W, H);
    var big = try r.Pixmap.init(alloc, W * 2, H * 2);
    for (src.pixels(), 0..) |*p, i| p.* = r.Color.rgb(@truncate(i), @truncate(i >> 3), @truncate(i >> 7)).premul();
    for (big.pixels(), 0..) |*p, i| p.* = r.Color.rgb(@truncate(i), @truncate(i >> 3), @truncate(i >> 7)).premul();
    const fbuf = try alloc.alloc(u8, 1 << 20);
    var fba = std.heap.FixedBufferAllocator.init(fbuf);
    var rz = r.Rasterizer.init(alloc);
    var glyph: r.Path = .empty;
    try glyphPath(alloc, &glyph);
    var rrect: r.Path = .empty;
    const rad: [4][2]f32 = .{ .{ 48, 48 }, .{ 48, 48 }, .{ 48, 48 }, .{ 48, 48 } };
    try rrect.addRoundRect(alloc, full, rad);
    var border: r.Path = .empty;
    try border.addRoundRect(alloc, full, rad);
    const rin: [4][2]f32 = .{ .{ 40, 40 }, .{ 40, 40 }, .{ 40, 40 }, .{ 40, 40 } };
    try border.addRoundRect(alloc, .{ .x = 8, .y = 8, .w = W - 16, .h = H - 16 }, rin);
    const c: Ctx = .{ .alloc = alloc, .fba = &fba, .rz = &rz, .dst = &dst, .src = &src, .big = &big, .glyph = &glyph, .rrect = &rrect, .border = &border };

    std.debug.print("canvas {d}x{d}; best of 7\n", .{ W, H });
    bench("glyph 40px rasterize (Rasterizer reuse)", 2000, c, bGlyph);
    bench("glyph 40px rasterize (one-shot wrapper)", 2000, c, bGlyphOneShot);
    bench("glyph 40px Rasterizer.fillPath solid", 2000, c, bGlyphFill);
    bench("fillRect solid opaque, full canvas", 50, c, bSolid);
    bench("fillRect solid alpha .5, full canvas", 20, c, bSolidAlpha);
    bench("fillRect linear horizontal, full", 20, c, bLinearH);
    bench("fillRect linear vertical, full", 20, c, bLinearV);
    bench("fillRect linear diagonal, full", 20, c, bLinearD);
    bench("fillRect radial, full", 10, c, bRadial);
    bench("fillRect conic, full", 10, c, bConic);
    bench("rrect path fill solid (Rasterizer), full", 20, c, bRRect);
    bench("rrect path fill solid (one-shot), full", 20, c, bRRectOneShot);
    bench("rrect path fill linear diagonal, full", 20, c, bRRectGrad);
    bench("rrect rotated+scaled solid", 20, c, bRRectRot);
    bench("border ring (evenodd) 8px, full", 20, c, bBorder);
    bench("drawPixmap identity blit, full", 20, c, bBlit);
    bench("drawPixmap int translate opacity .5", 20, c, bBlitOpacity);
    bench("drawPixmap scale 1.3 bilinear", 10, c, bScale);
    bench("drawPixmap rotate bilinear", 10, c, bRotate);
    bench("resample 2400x1260 -> 1200x630", 3, c, bResample);
    bench("blurMask 400x300 sigma 10", 10, c, bBlurMask);
    bench("blurMask 400x300 sigma 1.5", 10, c, bBlurMaskSmall);
    bench("blurPixmap full canvas sigma 8", 3, c, bBlurPixmap);
    std.debug.print("(sink {d})\n", .{sink});
}
