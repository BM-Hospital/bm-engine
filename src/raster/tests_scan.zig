//! Tests for the phase-2 scan converter: tiny-skia compatible mode, direct span fills.
const std = @import("std");
const r = @import("raster.zig");
const testing = std.testing;
const A = testing.allocator;

fn canvasMask(rz: *r.Rasterizer, path: *const r.Path, w: u32, h: u32, rule: r.FillRule) ![]u8 {
    const out = try A.alloc(u8, w * h);
    errdefer A.free(out);
    @memset(out, 0);
    var m = try rz.rasterizeSkia(A, path, r.Affine.identity, rule, .{ .x = 0, .y = 0, .w = w, .h = h });
    defer m.deinit(A);
    var y: u32 = 0;
    while (y < m.bounds.h) : (y += 1) {
        const dy: usize = @intCast(m.bounds.y + @as(i32, @intCast(y)));
        const dx: usize = @intCast(m.bounds.x);
        @memcpy(out[dy * w + dx ..][0..m.bounds.w], m.data[y * m.bounds.w ..][0..m.bounds.w]);
    }
    return out;
}

fn expectGolden(path: *const r.Path, w: u32, h: u32, rule: r.FillRule, golden: []const u8) !void {
    var rz = r.Rasterizer.init(A);
    defer rz.deinit();
    const got = try canvasMask(&rz, path, w, h, rule);
    defer A.free(got);
    try testing.expectEqual(@as(usize, w * h), golden.len);
    try testing.expectEqualSlices(u8, golden, got);
}

// Goldens are the alpha channel rendered by @takumi-rs/wasm 2.20.0 (tiny-skia 0.12);
// regenerate with `node probe/raster/gen_golden.mjs` from bench/.
test "skia_ss: ellipse and rounded rect are byte-identical to takumi" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.addEllipse(A, .{ .x = 5, .y = 9, .w = 23, .h = 9 });
    try expectGolden(&p, 40, 24, .nonzero, @embedFile("testdata/skia_ellipse.a8"));
    p.reset();
    const q: [2]f32 = .{ 9.5, 9.5 };
    try p.addRoundRect(A, .{ .x = 7, .y = 11, .w = 33, .h = 47 }, .{ q, q, q, q });
    try expectGolden(&p, 48, 64, .nonzero, @embedFile("testdata/skia_rrect.a8"));
}

test "skia_ss: quadratic outline is byte-identical to takumi" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.moveTo(A, 5.25, 30.5);
    try p.quadTo(A, 5.25, 5.75, 20.5, 5.75);
    try p.quadTo(A, 34.75, 5.75, 34.75, 30.5);
    try p.lineTo(A, 29.5, 30.5);
    try p.quadTo(A, 29.5, 11.25, 20.5, 11.25);
    try p.quadTo(A, 10.75, 11.25, 10.75, 30.5);
    try p.close(A);
    try expectGolden(&p, 40, 40, .nonzero, @embedFile("testdata/skia_quads.a8"));
}

test "skia_ss: cubics with overshooting control points, evenodd, byte-identical to takumi" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.moveTo(A, 10, 32);
    try p.cubicTo(A, 20, -20, 44, 84, 54, 32);
    try p.lineTo(A, 54, 60);
    try p.lineTo(A, 10, 60);
    try p.close(A);
    try p.moveTo(A, 20, 40);
    try p.cubicTo(A, 24, 30, 40, 62, 44, 50);
    try p.lineTo(A, 30, 58);
    try p.close(A);
    try expectGolden(&p, 64, 64, .evenodd, @embedFile("testdata/skia_cubics.a8"));
}

test "skia_ss: supersampled rectangle coverage values" {
    var rz = r.Rasterizer.init(A);
    defer rz.deinit();
    rz.mode = .skia_ss;
    try testing.expectEqual(r.RasterMode.skia_ss, rz.effectiveMode());
    var p: r.Path = .empty;
    defer p.deinit(A);
    // x: 1.25 .. 5.5 (sub-samples 5 .. 22), y: 2 .. 4.5 (sub-scanlines 8 .. 18)
    try p.addRect(A, .{ .x = 1.25, .y = 2, .w = 4.25, .h = 2.5 });
    var m = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, .{ .x = 0, .y = 0, .w = 16, .h = 16 });
    defer m.deinit(A);
    try testing.expectEqual(r.IRect{ .x = 1, .y = 2, .w = 5, .h = 3 }, m.bounds);
    // full rows: 3 of 4 sub-samples = 48 per sub-scanline; interior 3 * 64 + 63; right 2 of 4
    try testing.expectEqualSlices(u8, &.{ 192, 255, 255, 255, 128 }, m.data[0..5]);
    try testing.expectEqualSlices(u8, &.{ 192, 255, 255, 255, 128 }, m.data[5..10]);
    // last row: 2 of 4 sub-scanlines
    try testing.expectEqualSlices(u8, &.{ 96, 128, 128, 128, 64 }, m.data[10..15]);
    // integer rect: hard edges
    p.reset();
    try p.addRect(A, .{ .x = 3, .y = 3, .w = 4, .h = 2 });
    var m2 = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, .{ .x = 0, .y = 0, .w = 16, .h = 16 });
    defer m2.deinit(A);
    try testing.expectEqual(r.IRect{ .x = 3, .y = 3, .w = 4, .h = 2 }, m2.bounds);
    for (m2.data) |v| try testing.expectEqual(@as(u8, 255), v);
}

test "skia_ss: evenodd hole, nonzero union, clipped raster equals crop" {
    var rz = r.Rasterizer.init(A);
    defer rz.deinit();
    rz.mode = .skia_ss;
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.addRect(A, .{ .x = 0, .y = 0, .w = 20, .h = 20 });
    try p.addRect(A, .{ .x = 5, .y = 5, .w = 10, .h = 10 });
    const clip: r.IRect = .{ .x = 0, .y = 0, .w = 64, .h = 64 };
    var eo = try rz.rasterize(A, &p, r.Affine.identity, .evenodd, clip);
    defer eo.deinit(A);
    try testing.expectEqual(@as(u8, 255), eo.at(2, 2));
    try testing.expectEqual(@as(u8, 0), eo.at(10, 10));
    var nz = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clip);
    defer nz.deinit(A);
    try testing.expectEqual(@as(u8, 255), nz.at(10, 10));

    // a rotated rounded shape: any window gives the same pixels as the full mask
    p.reset();
    const q: [2]f32 = .{ 14, 9 };
    try p.addRoundRect(A, .{ .x = -30, .y = -20, .w = 60, .h = 40 }, .{ q, q, q, q });
    const t = r.Affine.translate(40.3, 33.7).mul(r.Affine.rotate(0.5));
    var full = try rz.rasterize(A, &p, t, .nonzero, .{ .x = -100, .y = -100, .w = 300, .h = 300 });
    defer full.deinit(A);
    const windows = [_]r.IRect{
        .{ .x = 20, .y = 10, .w = 30, .h = 17 },
        .{ .x = 0, .y = 30, .w = 200, .h = 3 },
        .{ .x = 50, .y = 0, .w = 5, .h = 200 },
        .{ .x = 39, .y = 33, .w = 1, .h = 1 },
    };
    for (windows) |win| {
        var part = try rz.rasterize(A, &p, t, .nonzero, win);
        defer part.deinit(A);
        try testing.expectEqual(full.bounds.intersect(win), part.bounds);
        var y = part.bounds.y;
        while (y < part.bounds.bottom()) : (y += 1) {
            var x = part.bounds.x;
            while (x < part.bounds.right()) : (x += 1) try testing.expectEqual(full.at(x, y), part.at(x, y));
        }
    }
}

test "fillPath (direct spans) equals rasterize + fillMask in every mode" {
    var rz = r.Rasterizer.init(A);
    defer rz.deinit();
    var p: r.Path = .empty;
    defer p.deinit(A);
    const q: [2]f32 = .{ 30, 18 };
    try p.addRoundRect(A, .{ .x = 6.5, .y = 4.25, .w = 150, .h = 70 }, .{ q, .{ 0, 0 }, q, .{ 75, 35 } });
    try p.addEllipse(A, .{ .x = 40, .y = 20, .w = 60, .h = 30 });
    const stops = [_]r.GradientStop{ .{ .offset = 0, .color = r.Color.rgba(255, 0, 80, 255) }, .{ .offset = 1, .color = r.Color.rgba(0, 60, 255, 90) } };
    const paints = [_]r.Paint{
        .{ .solid = r.Color.rgb(10, 200, 30) },
        .{ .solid = r.Color.rgba(200, 20, 30, 120) },
        .{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 170, .y = 80 }, .stops = &stops } },
    };
    // an A8 clip with a soft diagonal
    const cb: r.IRect = .{ .x = 3, .y = 2, .w = 140, .h = 70 };
    var cm = try r.Mask.init(A, cb);
    defer cm.deinit(A);
    for (cm.data, 0..) |*v, i| v.* = @truncate((i % 140) * 3 + (i / 140) * 2);
    const clip = cm.asClip();
    const transforms = [_]r.Affine{ r.Affine.identity, r.Affine.translate(20, 8).mul(r.Affine.rotate(0.2)).mul(r.Affine.scale(0.8, 0.9)) };
    const modes = [_]r.RasterMode{ .exact_area, .levels16, .skia_ss };
    for (modes) |mode| for (paints) |paint| for (transforms) |t| for ([_]r.FillRule{ .nonzero, .evenodd }) |rule| for ([_]?*const r.ClipMask{ null, &clip }) |cl| {
        rz.mode = mode;
        var a = try r.Pixmap.init(A, 180, 90);
        defer a.deinit(A);
        var b = try r.Pixmap.init(A, 180, 90);
        defer b.deinit(A);
        a.clear(r.Color.rgba(40, 80, 120, 200));
        b.clear(r.Color.rgba(40, 80, 120, 200));
        try rz.fillPath(&a, &p, t, rule, &paint, cl);
        var m = try rz.rasterize(A, &p, t, rule, b.bounds());
        defer m.deinit(A);
        r.fillMask(&b, &m, &paint, cl);
        try testing.expectEqualSlices(u8, b.data, a.data);
    };
}

test "mode switches: levels16 flag, fallback for huge shapes, degenerate input" {
    var rz = r.Rasterizer.init(A);
    defer rz.deinit();
    try testing.expectEqual(r.RasterMode.exact_area, rz.effectiveMode());
    rz.levels16 = true;
    try testing.expectEqual(r.RasterMode.levels16, rz.effectiveMode());
    rz.mode = .skia_ss;
    try testing.expectEqual(r.RasterMode.skia_ss, rz.effectiveMode());

    var p: r.Path = .empty;
    defer p.deinit(A);
    const clip: r.IRect = .{ .x = 0, .y = 0, .w = 32, .h = 32 };
    // empty path, zero-area paths, lone move
    var m = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clip);
    try testing.expect(m.bounds.isEmpty());
    try p.moveTo(A, 3, 3);
    m = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clip);
    try testing.expect(m.bounds.isEmpty());
    try p.lineTo(A, 20, 3);
    m = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clip);
    try testing.expect(m.bounds.isEmpty());
    // shape larger than the fixed-point range: exact-area fallback still covers the window
    p.reset();
    try p.addRect(A, .{ .x = -10000, .y = -10000, .w = 30000, .h = 30000 });
    m = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clip);
    try testing.expectEqual(clip, m.bounds);
    for (m.data) |v| try testing.expectEqual(@as(u8, 255), v);
    m.deinit(A);
    // large but in range, window far from the origin
    p.reset();
    try p.addEllipse(A, .{ .x = -4000, .y = -3000, .w = 8000, .h = 6000 });
    m = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clip);
    try testing.expectEqual(clip, m.bounds);
    for (m.data) |v| try testing.expectEqual(@as(u8, 255), v);
    m.deinit(A);
    // garbage coordinates and transforms must not trap
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    p.reset();
    try p.moveTo(A, nan, 1);
    try p.quadTo(A, inf, -inf, 5, 5);
    try p.cubicTo(A, 1e30, -1e30, nan, 2, 9, 30);
    try p.lineTo(A, -1e20, 7);
    try p.close(A);
    try p.lineTo(A, 4, 4);
    for ([_]r.Affine{ r.Affine.identity, r.Affine.scale(nan, inf), r.Affine.scale(1e30, 1e-30), .{ .a = 0, .d = 0 } }) |t| {
        var g = try rz.rasterize(A, &p, t, .evenodd, clip);
        g.deinit(A);
        var pm = try r.Pixmap.init(A, 32, 32);
        defer pm.deinit(A);
        try rz.fillPath(&pm, &p, t, .nonzero, &.{ .solid = r.Color.white }, null);
    }
    // malformed verb / point arrays
    p.reset();
    try p.verbs.appendSlice(A, &.{ .move, .cubic, .quad, .line, .close });
    try p.points.appendSlice(A, &.{ .{ .x = 1, .y = 1 }, .{ .x = 9, .y = 2 } });
    var g = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clip);
    g.deinit(A);
}

test "skia_ss: seeded random paths keep coverage sane and scratch state clean" {
    var rz = r.Rasterizer.init(A);
    defer rz.deinit();
    rz.mode = .skia_ss;
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rnd = prng.random();
    var p: r.Path = .empty;
    defer p.deinit(A);
    var ref: r.Path = .empty;
    defer ref.deinit(A);
    try ref.addRect(A, .{ .x = 2, .y = 2, .w = 9, .h = 5 });
    var k: usize = 0;
    while (k < 300) : (k += 1) {
        p.reset();
        const n = rnd.intRangeAtMost(usize, 1, 12);
        for (0..n) |_| {
            const v = [6]f32{ rnd.float(f32) * 80 - 10, rnd.float(f32) * 80 - 10, rnd.float(f32) * 80 - 10, rnd.float(f32) * 80 - 10, rnd.float(f32) * 80 - 10, rnd.float(f32) * 80 - 10 };
            switch (rnd.intRangeAtMost(u8, 0, 5)) {
                0 => try p.moveTo(A, v[0], v[1]),
                1, 2 => try p.lineTo(A, v[0], v[1]),
                3 => try p.quadTo(A, v[0], v[1], v[2], v[3]),
                4 => try p.cubicTo(A, v[0], v[1], v[2], v[3], v[4], v[5]),
                else => try p.close(A),
            }
        }
        const clip: r.IRect = .{ .x = rnd.intRangeAtMost(i32, -5, 30), .y = rnd.intRangeAtMost(i32, -5, 30), .w = rnd.intRangeAtMost(u32, 1, 70), .h = rnd.intRangeAtMost(u32, 1, 70) };
        var m = try rz.rasterize(A, &p, r.Affine.identity, if (k % 2 == 0) .nonzero else .evenodd, clip);
        m.deinit(A);
        // the scratch rows must be back to all-zero: a simple shape still comes out exact
        var c = try rz.rasterize(A, &ref, r.Affine.identity, .nonzero, .{ .x = 0, .y = 0, .w = 40, .h = 40 });
        defer c.deinit(A);
        try testing.expectEqual(r.IRect{ .x = 2, .y = 2, .w = 9, .h = 5 }, c.bounds);
        for (c.data) |v| try testing.expectEqual(@as(u8, 255), v);
    }
}

test "blur with sigma > 135 rescales instead of clamping" {
    // a 40x40 block in the middle of a 600x600 pixmap
    var a = try r.Pixmap.init(A, 600, 600);
    defer a.deinit(A);
    r.fillRect(&a, .{ .x = 280, .y = 280, .w = 40, .h = 40 }, &.{ .solid = r.Color.white }, null);
    var b = try r.Pixmap.init(A, 600, 600);
    defer b.deinit(A);
    @memcpy(b.data, a.data);
    try r.blurPixmap(A, &a, 135);
    try r.blurPixmap(A, &b, 220);
    const ca = a.pixel(300, 300)[3];
    const cb = b.pixel(300, 300)[3];
    // wider blur: lower peak (~ (135 / 220)^2), same ink within rounding, symmetric
    try testing.expect(ca >= 3 and cb >= 1 and cb < ca);
    var sa: u64 = 0;
    var sb: u64 = 0;
    for (0..600 * 600) |i| {
        sa += a.data[i * 4 + 3];
        sb += b.data[i * 4 + 3];
    }
    try testing.expect(sa > 0 and sb > 0);
    try testing.expectEqual(b.pixel(250, 300)[3], b.pixel(349, 300)[3]);
    try testing.expectEqual(b.pixel(300, 250)[3], b.pixel(300, 349)[3]);
    // premultiplied invariant and channel equality (white ink)
    for (0..600 * 600) |i| try testing.expect(b.data[i * 4] == b.data[i * 4 + 3]);
    // reach grows with sigma; masks grow accordingly and do not trap
    try testing.expect(r.blurReach(220) >= 660);
    try testing.expect(r.blurReach(135) < 660);
    var m = try r.maskFromRect(A, .{ .x = 10, .y = 10, .w = 30, .h = 20 }, .{ .x = 0, .y = 0, .w = 100, .h = 100 });
    defer m.deinit(A);
    try r.blurMaskClipped(A, &m, 150, .{ .x = 0, .y = 0, .w = 100, .h = 100 });
    try testing.expectEqual(r.IRect{ .x = 0, .y = 0, .w = 100, .h = 100 }, m.bounds);
    for ([_]f32{ std.math.inf(f32), std.math.nan(f32), 1e30, 136 }) |sg| {
        var t = try r.Pixmap.init(A, 9, 7);
        defer t.deinit(A);
        t.clear(r.Color.white);
        try r.blurPixmap(A, &t, sg);
    }
}

test "resample: fixed-point passes stay within 1 level of the f32 reference" {
    const image = @import("image.zig");
    var prng = std.Random.DefaultPrng.init(77);
    const rnd = prng.random();
    const sizes = [_][4]u32{
        .{ 64, 40, 32, 20 }, .{ 61, 37, 23, 11 }, .{ 30, 30, 77, 51 }, .{ 1, 9, 5, 3 },   .{ 9, 1, 3, 4 },
        .{ 200, 3, 17, 3 },  .{ 33, 47, 33, 47 }, .{ 120, 90, 7, 5 },  .{ 5, 5, 64, 64 }, .{ 2, 2, 1, 1 },
    };
    var total: usize = 0;
    var same: usize = 0;
    for (sizes, 0..) |sz, si| {
        var src = try r.Pixmap.init(A, sz[0], sz[1]);
        defer src.deinit(A);
        for (src.pixels(), 0..) |*p, i| {
            // mix of noise, hard edges and translucent pixels (premultiplied)
            const a: u8 = if (si % 2 == 0) 255 else rnd.int(u8);
            const hard = (i / 7) % 2 == 0;
            const c = r.Color.rgba(if (hard) 255 else rnd.int(u8), rnd.int(u8), if (hard) 0 else rnd.int(u8), a);
            p.* = c.premul();
        }
        var got = try r.resample(A, &src, sz[2], sz[3]);
        defer got.deinit(A);
        var want = try image.resampleReference(A, &src, sz[2], sz[3]);
        defer want.deinit(A);
        for (got.data, want.data, 0..) |g, w, i| {
            const d = @abs(@as(i32, g) - @as(i32, w));
            try testing.expect(d <= 1);
            total += 1;
            if (d == 0) same += 1;
            // premultiplied invariant
            try testing.expect(g <= got.data[i | 3]);
        }
    }
    try testing.expect(same * 100 >= total * 97);
}
