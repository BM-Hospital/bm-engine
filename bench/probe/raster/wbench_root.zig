//! Wasm micro-benchmark root for the raster module (driver: bench/probe/raster/wbench.mjs).
const std = @import("std");
const r = @import("raster");
const alloc = std.heap.wasm_allocator;

const W = 1200;
const H = 630;
var dst: r.Pixmap = r.Pixmap.empty;
var big: r.Pixmap = r.Pixmap.empty;
var rz: r.Rasterizer = undefined;
var ellipse: r.Path = .empty;
var rrect: r.Path = .empty;
var glyph: r.Path = .empty;
var fbuf: []u8 = &.{};
var sink: u32 = 0;

fn glyphPath(p: *r.Path) !void {
    // an "8"-like glyph in a 1000-unit em: 3 contours of 8 quads each
    const rings = [_][3]f32{ .{ 500, 300, 280 }, .{ 500, 300, 150 }, .{ 500, 720, 200 } };
    for (rings) |ring| {
        const n = 8;
        var i: usize = 0;
        while (i <= n) : (i += 1) {
            const a = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, n));
            const sc = r.sinCos(a);
            const x = ring[0] + ring[2] * sc[1];
            const y = ring[1] + ring[2] * sc[0];
            if (i == 0) {
                try p.moveTo(alloc, x, y);
            } else {
                const am = a - std.math.pi / @as(f32, n);
                const rc = ring[2] / r.sinCos(std.math.pi / @as(f32, n))[1];
                const scm = r.sinCos(am);
                try p.quadTo(alloc, ring[0] + rc * scm[1], ring[1] + rc * scm[0], x, y);
            }
        }
        try p.close(alloc);
    }
}

export fn init() void {
    dst = r.Pixmap.init(alloc, W, H) catch unreachable;
    big = r.Pixmap.init(alloc, W * 2, H * 2) catch unreachable;
    for (big.pixels(), 0..) |*p, i| p.* = r.Color.rgb(@truncate(i), @truncate(i >> 3), @truncate(i >> 7)).premul();
    rz = r.Rasterizer.init(alloc);
    ellipse.addEllipse(alloc, .{ .x = 0, .y = 0, .w = W, .h = H }) catch unreachable;
    const rad: [4][2]f32 = .{ .{ 48, 48 }, .{ 48, 48 }, .{ 48, 48 }, .{ 48, 48 } };
    rrect.addRoundRect(alloc, .{ .x = 0, .y = 0, .w = W, .h = H }, rad) catch unreachable;
    glyphPath(&glyph) catch unreachable;
    fbuf = alloc.alloc(u8, 1 << 20) catch unreachable;
}

fn setMode(mode: u32) void {
    if (@hasField(r.Rasterizer, "mode")) {
        rz.levels16 = false;
        rz.mode = @fromBackingInt(@intCast(mode));
    } else rz.levels16 = mode == 1;
}

const red: r.Paint = .{ .solid = r.Color.rgb(0x33, 0x66, 0x99) };
const stops2 = [_]r.GradientStop{
    .{ .offset = 0, .color = r.Color.rgb(255, 0, 80) },
    .{ .offset = 1, .color = r.Color.rgb(0, 60, 255) },
};

/// what: 0 ellipse solid fill, 1 rrect solid fill, 2 glyph 40px mask, 3 glyph 16px mask, 4 glyph 40px fill,
/// 5 ellipse mask (rasterize only), 6 resample 2400x1260 -> 1200x630, 7 ellipse gradient fill,
/// 8 ellipse 220x160 solid fill, 9 rotated rrect solid, 10 fillRect solid full canvas
export fn run(what: u32, mode: u32, iters: u32) u32 {
    setMode(mode);
    var fba = std.heap.FixedBufferAllocator.init(fbuf);
    var i: u32 = 0;
    while (i < iters) : (i += 1) {
        switch (what) {
            0 => rz.fillPath(&dst, &ellipse, r.Affine.identity, .nonzero, &red, null) catch unreachable,
            1 => rz.fillPath(&dst, &rrect, r.Affine.identity, .nonzero, &red, null) catch unreachable,
            2, 3 => {
                fba.reset();
                const s: f32 = if (what == 2) 0.04 else 0.016;
                const m = rz.rasterize(fba.allocator(), &glyph, r.Affine.translate(3.25, 2.75).mul(r.Affine.scale(s, s)), .nonzero, dst.bounds()) catch unreachable;
                sink +%= m.data[m.data.len / 2];
            },
            4 => rz.fillPath(&dst, &glyph, r.Affine.translate(103.25, 52.75).mul(r.Affine.scale(0.04, 0.04)), .nonzero, &red, null) catch unreachable,
            5 => {
                const m = rz.rasterize(alloc, &ellipse, r.Affine.identity, .nonzero, dst.bounds()) catch unreachable;
                sink +%= m.data[m.data.len / 2];
                alloc.free(m.data);
            },
            6 => {
                var out = r.resample(alloc, &big, W, H) catch unreachable;
                sink +%= out.data[out.data.len / 2 + 1];
                out.deinit(alloc);
            },
            7 => rz.fillPath(&dst, &ellipse, r.Affine.identity, .nonzero, &.{ .linear = .{ .p0 = .{ .x = 100, .y = 0 }, .p1 = .{ .x = 1100, .y = 630 }, .stops = &stops2 } }, null) catch unreachable,
            8 => rz.fillPath(&dst, &ellipse, r.Affine.translate(40, 40).mul(r.Affine.scale(220.0 / 1200.0, 160.0 / 630.0)), .nonzero, &red, null) catch unreachable,
            9 => rz.fillPath(&dst, &rrect, r.Affine.translate(600, 315).mul(r.Affine.rotate(0.1)).mul(r.Affine.scale(0.8, 0.8)).mul(r.Affine.translate(-600, -315)), .nonzero, &red, null) catch unreachable,
            10 => r.fillRect(&dst, .{ .x = 0, .y = 0, .w = W, .h = H }, &red, null),
            else => {},
        }
    }
    sink +%= dst.data[dst.data.len / 2 + 1];
    return sink;
}
