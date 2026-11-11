const std = @import("std");
const r = @import("raster.zig");
const testing = std.testing;
const A = testing.allocator;

const big_clip: r.IRect = .{ .x = -1000, .y = -1000, .w = 4000, .h = 4000 };

fn px(pm: *const r.Pixmap, x: u32, y: u32) [4]u8 {
    return pm.pixel(x, y);
}

fn maskSum(m: *const r.Mask) u64 {
    var s: u64 = 0;
    for (m.data) |v| s += v;
    return s;
}

test "irect intersect" {
    const a: r.IRect = .{ .x = 0, .y = 0, .w = 10, .h = 10 };
    const b: r.IRect = .{ .x = 5, .y = -5, .w = 10, .h = 10 };
    const c = a.intersect(b);
    try testing.expectEqual(r.IRect{ .x = 5, .y = 0, .w = 5, .h = 5 }, c);
    try testing.expect(a.intersect(.{ .x = 10, .y = 0, .w = 5, .h = 5 }).isEmpty());
    const huge: r.IRect = .{ .x = std.math.maxInt(i32) - 1, .y = 0, .w = std.math.maxInt(u32), .h = 1 };
    try testing.expect(huge.intersect(a).isEmpty());
}

test "affine mul / invert / apply" {
    const t = r.Affine.translate(10, 20);
    const s = r.Affine.scale(2, 3);
    // document order: `translate(10,20) scale(2,3)` scales the point first, then translates
    const m = t.mul(s);
    const p = m.apply(.{ .x = 1, .y = 1 });
    try testing.expectApproxEqAbs(@as(f32, 12), p.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 23), p.y, 1e-5);
    const rot = r.Affine.rotate(std.math.pi / 2.0);
    const q = rot.apply(.{ .x = 1, .y = 0 });
    try testing.expectApproxEqAbs(@as(f32, 0), q.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 1), q.y, 1e-5);
    const full = t.mul(rot).mul(s).mul(r.Affine.skew(0.3, -0.2));
    const inv = full.invert().?;
    const id = full.mul(inv);
    try testing.expectApproxEqAbs(@as(f32, 1), id.a, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0), id.b, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0), id.c, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 1), id.d, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0), id.e, 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 0), id.f, 1e-3);
    try testing.expect(r.Affine.scale(0, 1).invert() == null);
    try testing.expect(r.Affine.identity.isIdentity());
    try testing.expect(t.isTranslateOnly() and !t.isIdentity());
    try testing.expect(!s.isTranslateOnly());
}

test "exact coverage of fractional rects" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.addRect(A, .{ .x = 0.5, .y = 0, .w = 2, .h = 1 });
    var m = try r.rasterize(A, &p, r.Affine.identity, .nonzero, big_clip);
    defer m.deinit(A);
    try testing.expectEqual(r.IRect{ .x = 0, .y = 0, .w = 3, .h = 1 }, m.bounds);
    try testing.expectEqualSlices(u8, &.{ 128, 255, 128 }, m.data);

    var m2 = try r.rasterize(A, &p, r.Affine.translate(10.25, 5.25), .nonzero, big_clip);
    defer m2.deinit(A);
    try testing.expectEqual(r.IRect{ .x = 10, .y = 5, .w = 3, .h = 2 }, m2.bounds);
    // x: 10.75..12.75 -> .25, 1, .75 ; y: 5.25..6.25 -> .75, .25
    try testing.expectEqualSlices(u8, &.{ 48, 191, 143, 16, 64, 48 }, m2.data);
}

test "circle area" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    const rad: f32 = 50;
    try p.addEllipse(A, .{ .x = 60.3 - rad, .y = 60.7 - rad, .w = 2 * rad, .h = 2 * rad });
    var m = try r.rasterize(A, &p, r.Affine.identity, .nonzero, big_clip);
    defer m.deinit(A);
    const area = @as(f64, @floatFromInt(maskSum(&m))) / 255.0;
    const want = std.math.pi * 50.0 * 50.0;
    try testing.expect(@abs(area - want) / want < 0.005);
    var m2 = try r.rasterize(A, &p, r.Affine.scale(2, 2), .evenodd, big_clip);
    defer m2.deinit(A);
    const area2 = @as(f64, @floatFromInt(maskSum(&m2))) / 255.0;
    try testing.expect(@abs(area2 - want * 4) / (want * 4) < 0.005);
}

test "nonzero vs evenodd, nested rects and border ring" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.addRect(A, .{ .x = 0, .y = 0, .w = 20, .h = 20 });
    try p.addRect(A, .{ .x = 5, .y = 5, .w = 10, .h = 10 });
    var nz = try r.rasterize(A, &p, r.Affine.identity, .nonzero, big_clip);
    defer nz.deinit(A);
    var eo = try r.rasterize(A, &p, r.Affine.identity, .evenodd, big_clip);
    defer eo.deinit(A);
    try testing.expectEqual(@as(u8, 255), nz.at(10, 10));
    try testing.expectEqual(@as(u8, 0), eo.at(10, 10));
    try testing.expectEqual(@as(u8, 255), eo.at(2, 10));
    try testing.expectEqual(@as(u8, 255), nz.at(2, 10));
    try testing.expectEqual(@as(u64, 400 * 255), maskSum(&nz));
    try testing.expectEqual(@as(u64, 300 * 255), maskSum(&eo));

    // fractional inner edge: ring coverage must be 1 - inner coverage
    p.reset();
    try p.addRect(A, .{ .x = 0, .y = 0, .w = 20, .h = 20 });
    try p.addRect(A, .{ .x = 5.25, .y = 5, .w = 10, .h = 10 });
    var eo2 = try r.rasterize(A, &p, r.Affine.identity, .evenodd, big_clip);
    defer eo2.deinit(A);
    try testing.expectEqual(@as(u8, 64), eo2.at(5, 10));
    try testing.expectEqual(@as(u8, 0), eo2.at(6, 10));
    try testing.expectEqual(@as(u8, 191), eo2.at(15, 10));
}

test "rounded rect symmetry and bounds" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    const rr: [4][2]f32 = .{ .{ 12, 12 }, .{ 12, 12 }, .{ 12, 12 }, .{ 12, 12 } };
    try p.addRoundRect(A, .{ .x = 3, .y = 4, .w = 40, .h = 30 }, rr);
    var m = try r.rasterize(A, &p, r.Affine.identity, .nonzero, big_clip);
    defer m.deinit(A);
    try testing.expectEqual(r.IRect{ .x = 3, .y = 4, .w = 40, .h = 30 }, m.bounds);
    var y: i32 = 0;
    var partial: u32 = 0;
    while (y < 30) : (y += 1) {
        var x: i32 = 0;
        while (x < 40) : (x += 1) {
            const v: i32 = m.at(3 + x, 4 + y);
            const hx: i32 = m.at(3 + 39 - x, 4 + y);
            const hy: i32 = m.at(3 + x, 4 + 29 - y);
            try testing.expect(@abs(v - hx) <= 1);
            try testing.expect(@abs(v - hy) <= 1);
            if (v > 0 and v < 255) partial += 1;
        }
    }
    try testing.expect(partial > 20);
    try testing.expectEqual(@as(u8, 255), m.at(20, 4));
    try testing.expect(m.at(3, 4) < 40);
    const area = @as(f64, @floatFromInt(maskSum(&m))) / 255.0;
    const want = 40.0 * 30.0 - (4.0 - std.math.pi) * 144.0;
    if (@abs(area - want) / want >= 0.003) {
        std.debug.print("rrect area {d} want {d}\n", .{ area, want });
        return error.TestUnexpectedResult;
    }

    p.reset();
    try p.addRoundRect(A, .{ .x = 0, .y = 0, .w = 100, .h = 50 }, .{ .{ 50, 25 }, .{ 0, 0 }, .{ 10, 20 }, .{ 0, 5 } });
    var m2 = try r.rasterize(A, &p, r.Affine.identity, .nonzero, big_clip);
    defer m2.deinit(A);
    try testing.expectEqual(r.IRect{ .x = 0, .y = 0, .w = 100, .h = 50 }, m2.bounds);
    try testing.expectEqual(@as(u8, 255), m2.at(99, 0));
    try testing.expectEqual(@as(u8, 0), m2.at(0, 0));
}

test "clipped rasterization equals crop of the full raster" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.addEllipse(A, .{ .x = -20.3, .y = -15.6, .w = 90, .h = 70 });
    try p.moveTo(A, -30, 10);
    try p.lineTo(A, 120, 14.5);
    try p.lineTo(A, 40, 90);
    try p.close(A);
    var full = try r.rasterize(A, &p, r.Affine.identity, .evenodd, big_clip);
    defer full.deinit(A);
    const clips = [_]r.IRect{
        .{ .x = 0, .y = 0, .w = 50, .h = 40 },
        .{ .x = 10, .y = 5, .w = 7, .h = 60 },
        .{ .x = -25, .y = 20, .w = 200, .h = 3 },
        .{ .x = 30, .y = 30, .w = 1, .h = 1 },
    };
    var rz = r.Rasterizer.init(A);
    defer rz.deinit();
    for (clips) |c| {
        var m = try rz.rasterize(A, &p, r.Affine.identity, .evenodd, c);
        defer m.deinit(A);
        try testing.expect(!m.bounds.isEmpty());
        try testing.expectEqual(m.bounds, m.bounds.intersect(c));
        var y: i32 = c.y;
        while (y < c.bottom()) : (y += 1) {
            var x: i32 = c.x;
            while (x < c.right()) : (x += 1) {
                const a: i32 = m.at(x, y);
                const b: i32 = full.at(x, y);
                if (@abs(a - b) > 1) {
                    std.debug.print("clip mismatch at {d},{d}: {d} vs {d}\n", .{ x, y, a, b });
                    return error.TestUnexpectedResult;
                }
            }
        }
    }
    // scratch buffers are clean after use: same result twice
    var m1 = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clips[0]);
    defer m1.deinit(A);
    var m2 = try rz.rasterize(A, &p, r.Affine.identity, .nonzero, clips[0]);
    defer m2.deinit(A);
    try testing.expectEqualSlices(u8, m1.data, m2.data);
    for (rz.accum) |v| try testing.expectEqual(@as(f32, 0), v);
    for (rz.bits) |v| try testing.expectEqual(@as(u32, 0), v);
}

fn refOver(s: u32, d: u32, cov: u32, a: u32) u8 {
    const sp = r.div255(r.div255(s * a) * cov);
    const sa = r.div255(a * cov);
    return @intCast(sp + r.div255(d * (255 - sa)));
}

test "opaque fills are exact, src-over matches reference" {
    var pm = try r.Pixmap.init(A, 16, 8);
    defer pm.deinit(A);
    pm.clear(r.Color.rgb(10, 200, 30));
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.addRect(A, .{ .x = 1.5, .y = 1, .w = 6, .h = 4 });
    const col = r.Color.rgb(0x33, 0x66, 0x99);
    try r.fillPath(A, &pm, &p, r.Affine.identity, .nonzero, &.{ .solid = col }, null);
    try testing.expectEqual([4]u8{ 0x33, 0x66, 0x99, 0xFF }, px(&pm, 3, 2));
    try testing.expectEqual([4]u8{ 10, 200, 30, 255 }, px(&pm, 0, 2));
    // half covered pixel: src = mul255(c, 128); dst = src + mul255(dst, 255 - src.a)
    try testing.expectEqual([4]u8{ refOver(0x33, 10, 128, 255), refOver(0x66, 200, 128, 255), refOver(0x99, 30, 128, 255), 255 }, px(&pm, 1, 2));

    // translucent colour through fillRect with a fractional edge
    pm.clear(r.Color.rgba(200, 100, 50, 255));
    const tc = r.Color.rgba(20, 40, 250, 100);
    r.fillRect(&pm, .{ .x = 2, .y = 2, .w = 3.5, .h = 2 }, &.{ .solid = tc }, null);
    try testing.expectEqual([4]u8{ refOver(20, 200, 255, 100), refOver(40, 100, 255, 100), refOver(250, 50, 255, 100), 255 }, px(&pm, 3, 3));
    try testing.expectEqual([4]u8{ refOver(20, 200, 128, 100), refOver(40, 100, 128, 100), refOver(250, 50, 128, 100), 255 }, px(&pm, 5, 3));
    try testing.expectEqual([4]u8{ 200, 100, 50, 255 }, px(&pm, 6, 3));

    // onto transparent: result is the premultiplied colour
    pm.clear(r.Color.transparent);
    r.fillRect(&pm, .{ .x = 0, .y = 0, .w = 4, .h = 4 }, &.{ .solid = tc }, null);
    try testing.expectEqual([4]u8{ 8, 16, 98, 100 }, px(&pm, 1, 1));
    pm.toStraightAlpha();
    try testing.expectEqual([4]u8{ 20, 41, 250, 100 }, px(&pm, 1, 1));
}

test "fillRect integer rects are exact and clipped to the pixmap" {
    var pm = try r.Pixmap.init(A, 8, 8);
    defer pm.deinit(A);
    r.fillRect(&pm, .{ .x = -5, .y = 2, .w = 8, .h = 100 }, &.{ .solid = r.Color.rgb(1, 2, 3) }, null);
    var y: u32 = 0;
    while (y < 8) : (y += 1) {
        var x: u32 = 0;
        while (x < 8) : (x += 1) {
            const want: [4]u8 = if (x < 3 and y >= 2) .{ 1, 2, 3, 255 } else .{ 0, 0, 0, 0 };
            try testing.expectEqual(want, px(&pm, x, y));
        }
    }
    // sub-pixel sliver
    pm.clear(r.Color.transparent);
    r.fillRect(&pm, .{ .x = 4.25, .y = 4.25, .w = 0.5, .h = 0.5 }, &.{ .solid = r.Color.white }, null);
    try testing.expectEqual([4]u8{ 64, 64, 64, 64 }, px(&pm, 4, 4));
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, px(&pm, 5, 4));
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, px(&pm, 3, 4));
}

test "linear gradient: takumi oracle, endpoints, midpoint" {
    var pm = try r.Pixmap.init(A, 10, 2);
    defer pm.deinit(A);
    const stops = [_]r.GradientStop{
        .{ .offset = 0, .color = r.Color.rgb(255, 0, 0) },
        .{ .offset = 1, .color = r.Color.rgb(0, 0, 255) },
    };
    const paint: r.Paint = .{ .linear = .{ .p0 = .{ .x = 0, .y = 1 }, .p1 = .{ .x = 10, .y = 1 }, .stops = &stops } };
    r.fillRect(&pm, .{ .x = 0, .y = 0, .w = 10, .h = 2 }, &paint, null);
    const want = [10]u8{ 242, 217, 191, 166, 140, 115, 89, 64, 38, 13 };
    for (want, 0..) |w, x| {
        const p = px(&pm, @intCast(x), 1);
        try testing.expectEqual(w, p[0]);
        try testing.expectEqual(@as(u8, 255), p[3]);
        try testing.expectEqual(@as(u8, 0), p[1]);
    }

    // wide: outside the gradient line clamps to the stop colours, midpoint is the mix
    var wide = try r.Pixmap.init(A, 300, 1);
    defer wide.deinit(A);
    const s2 = [_]r.GradientStop{
        .{ .offset = 0, .color = r.Color.rgb(0, 0, 0) },
        .{ .offset = 1, .color = r.Color.rgb(255, 255, 255) },
    };
    const p2: r.Paint = .{ .linear = .{ .p0 = .{ .x = 50, .y = 0 }, .p1 = .{ .x = 250, .y = 0 }, .stops = &s2 } };
    r.fillRect(&wide, .{ .x = 0, .y = 0, .w = 300, .h = 1 }, &p2, null);
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, px(&wide, 0, 0));
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, px(&wide, 49, 0));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, px(&wide, 250, 0));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, px(&wide, 299, 0));
    const mid = px(&wide, 150, 0);
    try testing.expect(mid[0] >= 127 and mid[0] <= 129);
    var x: u32 = 1;
    while (x < 300) : (x += 1) {
        const a = px(&wide, x - 1, 0)[0];
        const b = px(&wide, x, 0)[0];
        try testing.expect(b >= a and b - a <= 2); // monotonic, no banding
    }

    // premultiplied interpolation: red -> transparent blue keeps the red hue
    const s3 = [_]r.GradientStop{
        .{ .offset = 0, .color = r.Color.rgb(255, 0, 0) },
        .{ .offset = 1, .color = r.Color.rgba(0, 0, 255, 0) },
    };
    wide.clear(r.Color.transparent);
    const p3: r.Paint = .{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 300, .y = 0 }, .stops = &s3 } };
    r.fillRect(&wide, .{ .x = 0, .y = 0, .w = 300, .h = 1 }, &p3, null);
    const m3 = px(&wide, 150, 0);
    try testing.expect(m3[2] == 0 and m3[0] == m3[3] and m3[3] > 120 and m3[3] < 135);

    // vertical + repeating + hard stops (period 10 px: 5 red, 5 green)
    var tall = try r.Pixmap.init(A, 3, 40);
    defer tall.deinit(A);
    const s4 = [_]r.GradientStop{
        .{ .offset = 0, .color = r.Color.rgb(255, 0, 0) },
        .{ .offset = 0.125, .color = r.Color.rgb(255, 0, 0) },
        .{ .offset = 0.125, .color = r.Color.rgb(0, 255, 0) },
        .{ .offset = 0.25, .color = r.Color.rgb(0, 255, 0) },
    };
    const p4: r.Paint = .{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 0, .y = 40 }, .stops = &s4, .repeating = true } };
    r.fillRect(&tall, .{ .x = 0, .y = 0, .w = 3, .h = 40 }, &p4, null);
    try testing.expectEqual([4]u8{ 255, 0, 0, 255 }, px(&tall, 1, 2));
    try testing.expectEqual([4]u8{ 0, 255, 0, 255 }, px(&tall, 1, 7));
    try testing.expectEqual([4]u8{ 255, 0, 0, 255 }, px(&tall, 1, 12));
    try testing.expectEqual([4]u8{ 0, 255, 0, 255 }, px(&tall, 1, 37));
}

test "radial and conic gradients" {
    var pm = try r.Pixmap.init(A, 64, 64);
    defer pm.deinit(A);
    const stops = [_]r.GradientStop{
        .{ .offset = 0, .color = r.Color.rgb(255, 255, 255) },
        .{ .offset = 1, .color = r.Color.rgb(0, 0, 0) },
    };
    const full: r.Rect = .{ .x = 0, .y = 0, .w = 64, .h = 64 };
    const paint: r.Paint = .{ .radial = .{ .center = .{ .x = 32, .y = 32 }, .rx = 30, .ry = 30, .stops = &stops } };
    r.fillRect(&pm, full, &paint, null);
    var y: u32 = 0;
    while (y < 64) : (y += 1) {
        var x: u32 = 0;
        while (x < 64) : (x += 1) {
            const v = px(&pm, x, y);
            try testing.expectEqual(v, px(&pm, 63 - x, y));
            try testing.expectEqual(v, px(&pm, x, 63 - y));
            try testing.expectEqual(v, px(&pm, y, x));
        }
    }
    try testing.expect(px(&pm, 32, 32)[0] > 245);
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, px(&pm, 0, 0));
    const half = px(&pm, 32 + 15, 32)[0];
    try testing.expect(half > 118 and half < 128); // t = 15.5/30

    // elliptical: t depends on the normalised distance
    const pe: r.Paint = .{ .radial = .{ .center = .{ .x = 32, .y = 32 }, .rx = 30, .ry = 15, .stops = &stops } };
    r.fillRect(&pm, full, &pe, null);
    const ex: i32 = px(&pm, 32 + 20, 32)[0];
    const ey: i32 = px(&pm, 32, 32 + 10)[0];
    try testing.expect(@abs(ex - ey) <= 6);

    // conic: 0 = up, clockwise
    const cs = [_]r.GradientStop{
        .{ .offset = 0, .color = r.Color.rgb(0, 0, 0) },
        .{ .offset = 1, .color = r.Color.rgb(255, 255, 255) },
    };
    const pc: r.Paint = .{ .conic = .{ .center = .{ .x = 32, .y = 32 }, .start_angle = 0, .stops = &cs, .max_radius = 46 } };
    r.fillRect(&pm, full, &pc, null);
    const right: i32 = px(&pm, 60, 32)[0]; // ~90deg
    const down: i32 = px(&pm, 32, 60)[0]; // ~180deg
    const left: i32 = px(&pm, 3, 31)[0]; // ~270deg
    try testing.expect(@abs(right - 64) < 6);
    try testing.expect(@abs(down - 128) < 6);
    try testing.expect(@abs(left - 191) < 6);
    try testing.expect(px(&pm, 32, 2)[0] < 6); // just clockwise of up
    try testing.expect(px(&pm, 31, 2)[0] > 249); // just counter-clockwise of up
}

test "drawPixmap identity is an exact copy; translate; opacity" {
    var src = try r.Pixmap.init(A, 7, 5);
    defer src.deinit(A);
    for (src.pixels(), 0..) |*p, i| {
        const a: u8 = @intCast((i * 37) % 256);
        p.* = r.Color.rgba(@intCast((i * 91) % 256), @intCast((i * 13) % 256), @intCast((i * 7) % 256), a).premul();
    }
    var dst = try r.Pixmap.init(A, 7, 5);
    defer dst.deinit(A);
    r.drawPixmap(&dst, &src, r.Affine.identity, 1, .bilinear, null);
    try testing.expectEqualSlices(u8, src.data, dst.data);

    dst.clear(r.Color.transparent);
    r.drawPixmap(&dst, &src, r.Affine.translate(3, -2), 1, .nearest, null);
    try testing.expectEqual(px(&src, 0, 2), px(&dst, 3, 0));
    try testing.expectEqual(px(&src, 3, 4), px(&dst, 6, 2));
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, px(&dst, 2, 0));
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, px(&dst, 3, 3));

    // opacity layer over an opaque background
    var blue = try r.Pixmap.init(A, 4, 4);
    defer blue.deinit(A);
    blue.clear(r.Color.rgb(0, 0, 255));
    dst.clear(r.Color.white);
    r.drawPixmap(&dst, &blue, r.Affine.identity, 0.3, .bilinear, null);
    // takumi: rgba(0,0,255,.3) over white -> (178,178,255)
    try testing.expectEqual([4]u8{ 178, 178, 255, 255 }, px(&dst, 1, 1));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, px(&dst, 5, 1));
}

test "drawPixmap scaling and rotation" {
    var src = try r.Pixmap.init(A, 2, 1);
    defer src.deinit(A);
    src.pixels()[0] = r.Color.black.premul();
    src.pixels()[1] = r.Color.white.premul();
    var dst = try r.Pixmap.init(A, 8, 1);
    defer dst.deinit(A);
    r.drawPixmap(&dst, &src, r.Affine.scale(4, 1), 1, .bilinear, null);
    // texel centres at x = 2 and 6; clamped outside, linear ramp between
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, px(&dst, 0, 0));
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, px(&dst, 1, 0));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, px(&dst, 6, 0));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, px(&dst, 7, 0));
    var x: u32 = 1;
    while (x < 8) : (x += 1) try testing.expect(px(&dst, x, 0)[0] >= px(&dst, x - 1, 0)[0]);
    const m = px(&dst, 3, 0)[0];
    try testing.expect(m > 80 and m < 110); // 3/8 of the way
    r.drawPixmap(&dst, &src, r.Affine.scale(4, 1), 1, .nearest, null);
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, px(&dst, 3, 0));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, px(&dst, 4, 0));

    // fractional placement: AA edge, exact interior
    var solid = try r.Pixmap.init(A, 4, 4);
    defer solid.deinit(A);
    solid.clear(r.Color.rgb(200, 100, 50));
    var big = try r.Pixmap.init(A, 32, 32);
    defer big.deinit(A);
    r.drawPixmap(&big, &solid, r.Affine.translate(2.5, 3).mul(r.Affine.scale(2, 2)), 1, .bilinear, null);
    try testing.expectEqual([4]u8{ 200, 100, 50, 255 }, px(&big, 5, 5));
    try testing.expectEqual(@as(u8, 128), px(&big, 2, 5)[3]);
    try testing.expectEqual(@as(u8, 128), px(&big, 10, 5)[3]);
    try testing.expectEqual(@as(u8, 0), px(&big, 11, 5)[3]);

    // 45deg rotation about the centre: area preserved, interior exact, outside untouched
    big.clear(r.Color.transparent);
    var sq = try r.Pixmap.init(A, 12, 12);
    defer sq.deinit(A);
    sq.clear(r.Color.rgb(9, 99, 199));
    const t = r.Affine.translate(16, 16).mul(r.Affine.rotate(std.math.pi / 4.0)).mul(r.Affine.translate(-6, -6));
    r.drawPixmap(&big, &sq, t, 1, .bilinear, null);
    try testing.expectEqual([4]u8{ 9, 99, 199, 255 }, px(&big, 16, 16));
    var asum: u64 = 0;
    for (big.pixels()) |p| asum += p >> 24;
    const area = @as(f64, @floatFromInt(asum)) / 255.0;
    try testing.expect(@abs(area - 144.0) < 144.0 * 0.03);
    try testing.expectEqual(@as(u8, 0), px(&big, 16, 5)[3]);
    try testing.expectEqual(@as(u8, 0), px(&big, 9, 9)[3]);
}

test "image paint extend modes" {
    var src = try r.Pixmap.init(A, 2, 2);
    defer src.deinit(A);
    src.pixels()[0] = r.Color.rgb(255, 0, 0).premul();
    src.pixels()[1] = r.Color.rgb(0, 255, 0).premul();
    src.pixels()[2] = r.Color.rgb(0, 0, 255).premul();
    src.pixels()[3] = r.Color.rgb(255, 255, 255).premul();
    var dst = try r.Pixmap.init(A, 6, 6);
    defer dst.deinit(A);
    const full: r.Rect = .{ .x = 0, .y = 0, .w = 6, .h = 6 };
    r.fillRect(&dst, full, &.{ .image = .{ .pixmap = &src, .transform = r.Affine.identity, .filter = .nearest, .extend = .repeat } }, null);
    try testing.expectEqual([4]u8{ 255, 0, 0, 255 }, px(&dst, 4, 4));
    try testing.expectEqual([4]u8{ 0, 255, 0, 255 }, px(&dst, 5, 2));
    try testing.expectEqual([4]u8{ 0, 0, 255, 255 }, px(&dst, 2, 3));
    dst.clear(r.Color.transparent);
    r.fillRect(&dst, full, &.{ .image = .{ .pixmap = &src, .transform = r.Affine.translate(-2, -2), .filter = .nearest, .extend = .transparent } }, null);
    try testing.expectEqual([4]u8{ 255, 0, 0, 255 }, px(&dst, 2, 2));
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, px(&dst, 1, 2));
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, px(&dst, 4, 3));
    dst.clear(r.Color.transparent);
    r.fillRect(&dst, full, &.{ .image = .{ .pixmap = &src, .transform = r.Affine.translate(-2, -2), .filter = .bilinear, .extend = .pad, .opacity = 0.5 } }, null);
    try testing.expectEqual([4]u8{ 128, 0, 0, 128 }, px(&dst, 0, 0));
    try testing.expectEqual([4]u8{ 128, 128, 128, 128 }, px(&dst, 5, 5));
}

test "resample: checkerboard halves to uniform gray, identity, upscale" {
    var src = try r.Pixmap.init(A, 32, 32);
    defer src.deinit(A);
    for (0..32) |y| {
        for (0..32) |x| {
            src.pixels()[y * 32 + x] = if ((x + y) % 2 == 0) r.Color.white.premul() else r.Color.black.premul();
        }
    }
    var half = try r.resample(A, &src, 16, 16);
    defer half.deinit(A);
    try testing.expectEqual(@as(u32, 16), half.width);
    for (0..16) |y| {
        for (0..16) |x| {
            const p = px(&half, @intCast(x), @intCast(y));
            try testing.expectEqual(@as(u8, 255), p[3]);
            const interior = x >= 2 and x < 14 and y >= 2 and y < 14;
            const tol: i32 = if (interior) 1 else 12;
            try testing.expect(@abs(@as(i32, p[0]) - 128) <= tol);
            try testing.expectEqual(p[0], p[1]);
        }
    }
    var same = try r.resample(A, &src, 32, 32);
    defer same.deinit(A);
    try testing.expectEqualSlices(u8, src.data, same.data);

    var up = try r.resample(A, &half, 40, 23);
    defer up.deinit(A);
    try testing.expect(@abs(@as(i32, px(&up, 20, 11)[0]) - 128) <= 1);

    // translucent data stays valid premultiplied
    for (src.pixels(), 0..) |*p, i| p.* = r.Color.rgba(255, 255, 255, if (i % 3 == 0) 255 else 0).premul();
    var q = try r.resample(A, &src, 13, 9);
    defer q.deinit(A);
    for (q.pixels()) |p| {
        const b: [4]u8 = @bitCast(p);
        try testing.expect(b[0] <= b[3] and b[1] <= b[3] and b[2] <= b[3]);
    }
    var z = try r.resample(A, &src, 0, 9);
    defer z.deinit(A);
    try testing.expectEqual(@as(usize, 0), z.data.len);
}

test "blur: takumi oracle, mass, symmetry" {
    // 10x10 box at (20,20), sigma 5 (box-shadow blur 10px)
    var m = try r.maskFromRect(A, .{ .x = 20, .y = 20, .w = 10, .h = 10 }, big_clip);
    defer m.deinit(A);
    try testing.expectEqual(@as(u64, 100 * 255), maskSum(&m));
    try r.blurMask(A, &m, 5);
    try testing.expectEqual(@as(u32, 12), r.blurReach(5));
    try testing.expectEqual(r.IRect{ .x = 8, .y = 8, .w = 34, .h = 34 }, m.bounds);
    const want = [_]u8{ 1, 2, 5, 9, 14, 21, 30, 42, 55, 68, 83 };
    for (want, 0..) |w, i| try testing.expectEqual(w, m.at(9 + @as(i32, @intCast(i)), 25));
    const mass: f64 = @floatFromInt(maskSum(&m));
    try testing.expect(@abs(mass - 25500.0) / 25500.0 < 0.01);
    // symmetric about the box centre (x = y = 24.5)
    var y: i32 = 8;
    while (y < 42) : (y += 1) {
        var x: i32 = 8;
        while (x < 42) : (x += 1) {
            const v: i32 = m.at(x, y);
            try testing.expect(@abs(v - @as(i32, m.at(49 - x, y))) <= 1);
            try testing.expect(@abs(v - @as(i32, m.at(x, 49 - y))) <= 1);
            try testing.expect(@abs(v - @as(i32, m.at(y, x))) <= 1);
        }
    }

    // small sigma (exact gaussian), even / odd windows, large sigma
    const sigmas = [_]f32{ 0.5, 1.5, 2.0, 3.3, 8, 20 };
    for (sigmas) |s| {
        var b = try r.maskFromRect(A, .{ .x = 0, .y = 0, .w = 16, .h = 12 }, big_clip);
        defer b.deinit(A);
        try r.blurMask(A, &b, s);
        const ms: f64 = @floatFromInt(maskSum(&b));
        try testing.expect(@abs(ms - 16.0 * 12.0 * 255.0) / (16.0 * 12.0 * 255.0) < 0.01);
        const re: i32 = @intCast(r.blurReach(s));
        try testing.expect(@as(f32, @floatFromInt(re)) >= 2 * s and @as(f32, @floatFromInt(re)) <= 3 * s + 3);
        var yy: i32 = -re;
        while (yy < 12 + re) : (yy += 1) {
            var xx: i32 = -re;
            while (xx < 16 + re) : (xx += 1) {
                const v: i32 = b.at(xx, yy);
                try testing.expect(@abs(v - @as(i32, b.at(15 - xx, yy))) <= 1);
                try testing.expect(@abs(v - @as(i32, b.at(xx, 11 - yy))) <= 1);
            }
        }
        // clipped blur gives identical values inside the clip
        var c = try r.maskFromRect(A, .{ .x = 0, .y = 0, .w = 16, .h = 12 }, big_clip);
        defer c.deinit(A);
        const clip: r.IRect = .{ .x = 3, .y = -4, .w = 9, .h = 11 };
        try r.blurMaskClipped(A, &c, s, clip);
        try testing.expectEqual(clip.intersect(b.bounds), c.bounds);
        yy = clip.y;
        while (yy < clip.bottom()) : (yy += 1) {
            var xx: i32 = clip.x;
            while (xx < clip.right()) : (xx += 1) try testing.expectEqual(b.at(xx, yy), c.at(xx, yy));
        }
    }
    // no-op sigmas
    var n = try r.maskFromRect(A, .{ .x = 0, .y = 0, .w = 4, .h = 4 }, big_clip);
    defer n.deinit(A);
    try r.blurMask(A, &n, 0);
    try r.blurMask(A, &n, -3);
    try r.blurMask(A, &n, std.math.nan(f32));
    try testing.expectEqual(r.IRect{ .x = 0, .y = 0, .w = 4, .h = 4 }, n.bounds);
}

test "blurPixmap" {
    var pm = try r.Pixmap.init(A, 48, 40);
    defer pm.deinit(A);
    r.fillRect(&pm, .{ .x = 16, .y = 14, .w = 16, .h = 12 }, &.{ .solid = r.Color.rgb(255, 128, 0) }, null);
    var before: [4]u64 = .{ 0, 0, 0, 0 };
    for (pm.pixels()) |p| {
        const b: [4]u8 = @bitCast(p);
        for (0..4) |k| before[k] += b[k];
    }
    try r.blurPixmap(A, &pm, 3);
    var after: [4]u64 = .{ 0, 0, 0, 0 };
    for (pm.pixels()) |p| {
        const b: [4]u8 = @bitCast(p);
        for (0..4) |k| after[k] += b[k];
    }
    for (0..4) |k| {
        const a: f64 = @floatFromInt(after[k]);
        const b: f64 = @floatFromInt(before[k]);
        if (b > 0) try testing.expect(@abs(a - b) / b < 0.01);
    }
    var y: u32 = 0;
    while (y < 40) : (y += 1) {
        var x: u32 = 0;
        while (x < 48) : (x += 1) {
            const v = px(&pm, x, y);
            const h = px(&pm, 47 - x, y);
            const w = px(&pm, x, 39 - y);
            for (0..4) |k| {
                try testing.expect(@abs(@as(i32, v[k]) - h[k]) <= 1);
                try testing.expect(@abs(@as(i32, v[k]) - w[k]) <= 1);
            }
        }
    }
    try testing.expect(px(&pm, 24, 20)[3] > 230);
    try testing.expect(px(&pm, 14, 20)[3] > 20 and px(&pm, 14, 20)[3] < 128);
}

test "clip masks" {
    var pm = try r.Pixmap.init(A, 20, 20);
    defer pm.deinit(A);
    const red: r.Paint = .{ .solid = r.Color.rgb(255, 0, 0) };
    const rc = r.ClipMask.fromRect(.{ .x = 5, .y = 5, .w = 4, .h = 4 });
    r.fillRect(&pm, .{ .x = 0, .y = 0, .w = 20, .h = 20 }, &red, &rc);
    var count: u32 = 0;
    for (pm.pixels()) |p| {
        if (p != 0) count += 1;
    }
    try testing.expectEqual(@as(u32, 16), count);
    try testing.expectEqual([4]u8{ 255, 0, 0, 255 }, px(&pm, 8, 8));
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, px(&pm, 9, 8));

    // A8 clip (circle) on a path fill, a rect fill and a pixmap draw
    var circle: r.Path = .empty;
    defer circle.deinit(A);
    try circle.addEllipse(A, .{ .x = 4, .y = 4, .w = 12, .h = 12 });
    var cm = try r.rasterize(A, &circle, r.Affine.identity, .nonzero, pm.bounds());
    defer cm.deinit(A);
    const clip = cm.asClip();
    var sq: r.Path = .empty;
    defer sq.deinit(A);
    try sq.addRect(A, .{ .x = 0, .y = 0, .w = 10, .h = 20 });
    var layer = try r.Pixmap.init(A, 20, 20);
    defer layer.deinit(A);
    layer.clear(r.Color.rgb(255, 0, 0));
    for (0..3) |mode| {
        pm.clear(r.Color.transparent);
        switch (mode) {
            0 => try r.fillPath(A, &pm, &sq, r.Affine.identity, .nonzero, &red, &clip),
            1 => r.fillRect(&pm, .{ .x = 0, .y = 0, .w = 10, .h = 20 }, &red, &clip),
            else => {
                const half = r.ClipMask.fromRect(.{ .x = 0, .y = 0, .w = 10, .h = 20 });
                const both = try r.clipIntersect(A, clip, half);
                defer if (both.data) |d| A.free(d);
                r.drawPixmap(&pm, &layer, r.Affine.identity, 1, .nearest, &both);
            },
        }
        var y: i32 = 0;
        while (y < 20) : (y += 1) {
            var x: i32 = 0;
            while (x < 20) : (x += 1) {
                const want: u8 = if (x < 10) cm.at(x, y) else 0;
                try testing.expectEqual(want, px(&pm, @intCast(x), @intCast(y))[3]);
            }
        }
    }

    // mask helpers
    var a = try r.maskFromRect(A, .{ .x = 0, .y = 0, .w = 10, .h = 10 }, big_clip);
    defer a.deinit(A);
    var b = try r.maskFromRect(A, .{ .x = 5.5, .y = 5, .w = 10, .h = 10 }, big_clip);
    defer b.deinit(A);
    var ab = try r.maskIntersect(A, &a, &b);
    defer ab.deinit(A);
    try testing.expectEqual(r.IRect{ .x = 5, .y = 5, .w = 5, .h = 5 }, ab.bounds);
    try testing.expectEqual(@as(u8, 128), ab.at(5, 6));
    try testing.expectEqual(@as(u8, 255), ab.at(6, 6));
    var inv = try r.maskInvertWithin(A, &b, .{ .x = 0, .y = 0, .w = 20, .h = 20 });
    defer inv.deinit(A);
    try testing.expectEqual(@as(u8, 255), inv.at(0, 0));
    try testing.expectEqual(@as(u8, 127), inv.at(5, 6));
    try testing.expectEqual(@as(u8, 0), inv.at(10, 10));
    try testing.expectEqual(@as(u8, 255), inv.at(19, 19));
    const rr = try r.clipIntersect(A, r.ClipMask.fromRect(a.bounds), r.ClipMask.fromRect(b.bounds));
    try testing.expect(rr.data == null);
    try testing.expectEqual(r.IRect{ .x = 5, .y = 5, .w = 5, .h = 5 }, rr.bounds);
}

fn drawGlyphish(s: anytype) void {
    s.moveTo(0, 0);
    s.quadTo(5, 10, 10, 0);
    s.lineTo(10, 5);
    s.cubicTo(8, 6, 2, 6, 0, 5);
    s.close();
}

test "path sink adapter" {
    var p: r.Path = .empty;
    defer p.deinit(A);
    var sink: r.PathSink = .{ .path = &p, .alloc = A, .transform = r.Affine.scale(2, -2).mul(r.Affine.translate(0, -10)) };
    drawGlyphish(&sink);
    try testing.expect(!sink.err);
    try testing.expectEqual(@as(usize, 5), p.verbs.items.len);
    const b = p.bounds();
    try testing.expectApproxEqAbs(@as(f32, 0), b.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 20), b.w, 1e-5);
    var m = try r.rasterize(A, &p, r.Affine.identity, .nonzero, big_clip);
    defer m.deinit(A);
    try testing.expect(maskSum(&m) > 0);
    var failing = testing.FailingAllocator.init(A, .{ .fail_index = 0 });
    var p2: r.Path = .empty;
    defer p2.deinit(failing.allocator());
    var sink2: r.PathSink = .{ .path = &p2, .alloc = failing.allocator() };
    drawGlyphish(&sink2);
    try testing.expect(sink2.err);
}

test "degenerate inputs do not crash" {
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    var pm = try r.Pixmap.init(A, 16, 16);
    defer pm.deinit(A);
    var zero = try r.Pixmap.init(A, 0, 0);
    defer zero.deinit(A);
    var zero_w = try r.Pixmap.init(A, 0, 7);
    defer zero_w.deinit(A);
    const red: r.Paint = .{ .solid = r.Color.rgb(255, 0, 0) };

    var p: r.Path = .empty;
    defer p.deinit(A);
    var m0 = try r.rasterize(A, &p, r.Affine.identity, .nonzero, pm.bounds());
    defer m0.deinit(A);
    try testing.expect(m0.bounds.isEmpty());
    r.fillMask(&pm, &m0, &red, null);
    try r.fillPath(A, &pm, &p, r.Affine.identity, .nonzero, &red, null);

    // NaN / inf / huge coordinates
    try p.moveTo(A, nan, 3);
    try p.lineTo(A, inf, -inf);
    try p.quadTo(A, 1e30, -1e30, 5, 5);
    try p.cubicTo(A, -1e38, 1e38, nan, nan, 8, 2);
    try p.lineTo(A, 3, 12);
    try p.close(A);
    try p.lineTo(A, 4, 4); // segment without moveTo
    try p.addRect(A, .{ .x = -1e20, .y = -1e20, .w = 2e20, .h = 2e20 });
    var m1 = try r.rasterize(A, &p, r.Affine.identity, .evenodd, pm.bounds());
    defer m1.deinit(A);
    try testing.expect(m1.bounds.w <= 16 and m1.bounds.h <= 16);
    try r.fillPath(A, &pm, &p, .{ .a = nan, .b = inf, .c = 1e30, .d = -1e30, .e = nan, .f = 0 }, .nonzero, &red, null);
    try r.fillPath(A, &pm, &p, r.Affine.scale(1e20, 1e20), .nonzero, &red, null);
    // huge clip with a small path stays small
    p.reset();
    try p.addRect(A, .{ .x = 1, .y = 1, .w = 2, .h = 2 });
    var m2 = try r.rasterize(A, &p, r.Affine.identity, .nonzero, .{ .x = std.math.minInt(i32), .y = std.math.minInt(i32), .w = std.math.maxInt(u32), .h = std.math.maxInt(u32) });
    defer m2.deinit(A);
    try testing.expectEqual(@as(usize, 4), m2.data.len);

    // zero-size pixmaps everywhere
    r.fillRect(&zero, .{ .x = 0, .y = 0, .w = 10, .h = 10 }, &red, null);
    r.fillRect(&zero_w, .{ .x = 0, .y = 0, .w = 10, .h = 10 }, &red, null);
    try r.fillPath(A, &zero, &p, r.Affine.identity, .nonzero, &red, null);
    r.drawPixmap(&zero, &pm, r.Affine.identity, 1, .bilinear, null);
    r.drawPixmap(&pm, &zero, r.Affine.identity, 1, .bilinear, null);
    r.drawPixmap(&pm, &zero_w, r.Affine.scale(3, 3), 1, .bilinear, null);
    try r.blurPixmap(A, &zero, 4);
    zero.clear(r.Color.white);
    zero.toStraightAlpha();
    var rz = try r.resample(A, &zero, 4, 4);
    defer rz.deinit(A);

    // NaN rects / transforms / paints
    r.fillRect(&pm, .{ .x = nan, .y = 0, .w = 10, .h = 10 }, &red, null);
    r.fillRect(&pm, .{ .x = 0, .y = 0, .w = inf, .h = nan }, &red, null);
    r.fillRect(&pm, .{ .x = -inf, .y = -inf, .w = inf, .h = inf }, &red, null);
    r.fillRect(&pm, .{ .x = 5, .y = 5, .w = -3, .h = 2 }, &red, null);
    var other = try r.Pixmap.init(A, 3, 3);
    defer other.deinit(A);
    r.drawPixmap(&pm, &other, .{ .a = nan }, 1, .bilinear, null);
    r.drawPixmap(&pm, &other, r.Affine.scale(0, 0), 1, .bilinear, null);
    r.drawPixmap(&pm, &other, r.Affine.scale(1e30, 1e-30), nan, .bilinear, null);
    r.drawPixmap(&pm, &other, r.Affine.rotate(1).mul(r.Affine.scale(1e6, 1e6)), 1, .nearest, null);
    r.drawPixmap(&pm, &other, r.Affine.rotate(1).mul(r.Affine.scale(1e-6, 1e6)), 1, .bilinear, null);
    r.drawPixmap(&pm, &other, r.Affine.translate(1e12, -1e12), 1, .nearest, null);
    const full: r.Rect = .{ .x = 0, .y = 0, .w = 16, .h = 16 };
    const no_stops: []const r.GradientStop = &.{};
    const one = [_]r.GradientStop{.{ .offset = 0.5, .color = r.Color.rgb(1, 2, 3) }};
    const bad = [_]r.GradientStop{ .{ .offset = nan, .color = r.Color.white }, .{ .offset = inf, .color = r.Color.black } };
    const same = [_]r.GradientStop{ .{ .offset = 0.5, .color = r.Color.white }, .{ .offset = 0.5, .color = r.Color.black } };
    const far = [_]r.GradientStop{ .{ .offset = -1e30, .color = r.Color.white }, .{ .offset = 1e30, .color = r.Color.black } };
    const unsorted = [_]r.GradientStop{ .{ .offset = 0.9, .color = r.Color.white }, .{ .offset = 0.1, .color = r.Color.black }, .{ .offset = 0.5, .color = r.Color.white } };
    const stop_sets = [_][]const r.GradientStop{ no_stops, &one, &bad, &same, &far, &unsorted };
    for (stop_sets) |stops| {
        for ([_]bool{ false, true }) |rep| {
            r.fillRect(&pm, full, &.{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 0, .y = 0 }, .stops = stops, .repeating = rep } }, null);
            r.fillRect(&pm, full, &.{ .linear = .{ .p0 = .{ .x = nan, .y = 0 }, .p1 = .{ .x = inf, .y = 0 }, .stops = stops, .repeating = rep } }, null);
            r.fillRect(&pm, full, &.{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 1e30, .y = 1e-30 }, .stops = stops, .repeating = rep } }, null);
            r.fillRect(&pm, full, &.{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 7, .y = 3 }, .stops = stops, .repeating = rep } }, null);
            r.fillRect(&pm, full, &.{ .radial = .{ .center = .{ .x = 8, .y = 8 }, .rx = 0, .ry = nan, .stops = stops, .repeating = rep } }, null);
            r.fillRect(&pm, full, &.{ .radial = .{ .center = .{ .x = 8, .y = 8 }, .rx = 5, .ry = 3, .stops = stops, .repeating = rep, .transform = r.Affine.scale(1e30, 0) } }, null);
            r.fillRect(&pm, full, &.{ .conic = .{ .center = .{ .x = 8.5, .y = 8.5 }, .start_angle = 1e30, .stops = stops, .repeating = rep } }, null);
            r.fillRect(&pm, full, &.{ .conic = .{ .center = .{ .x = inf, .y = 8 }, .start_angle = nan, .stops = stops, .repeating = rep, .max_radius = inf } }, null);
        }
    }
    r.fillRect(&pm, full, &.{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 7, .y = 3 }, .stops = &one } }, null);
    try testing.expectEqual([4]u8{ 1, 2, 3, 255 }, px(&pm, 4, 4));
    r.fillRect(&pm, full, &.{ .image = .{ .pixmap = &zero, .transform = r.Affine.identity } }, null);
    r.fillRect(&pm, full, &.{ .image = .{ .pixmap = &other, .transform = .{ .a = nan } } }, null);
    r.fillRect(&pm, full, &.{ .image = .{ .pixmap = &other, .transform = r.Affine.scale(1e30, -1e30), .extend = .repeat, .opacity = nan } }, null);
    r.fillRect(&pm, full, &.{ .image = .{ .pixmap = &other, .transform = r.Affine.scale(1e30, -1e30), .extend = .repeat, .filter = .nearest } }, null);
    r.fillRect(&pm, full, &.{ .image = .{ .pixmap = &other, .transform = r.Affine.scale(0, 0), .extend = .transparent } }, null);
    // empty / undersized clip buffers draw nothing
    const ec = r.ClipMask.fromRect(r.IRect.empty);
    pm.clear(r.Color.transparent);
    r.fillRect(&pm, full, &red, &ec);
    const short: r.ClipMask = .{ .bounds = .{ .x = 0, .y = 0, .w = 16, .h = 16 }, .data = &.{ 1, 2, 3 } };
    r.fillRect(&pm, full, &red, &short);
    for (pm.pixels()) |v| try testing.expectEqual(@as(u32, 0), v);
    // absurd sigma is clamped
    var bm = try r.maskFromRect(A, .{ .x = 0, .y = 0, .w = 3, .h = 3 }, big_clip);
    defer bm.deinit(A);
    try r.blurMaskClipped(A, &bm, 1e9, .{ .x = -8, .y = -8, .w = 20, .h = 20 });
    try testing.expect(bm.bounds.w <= 20);
    var em: r.Mask = r.Mask.empty;
    try r.blurMask(A, &em, 5);
    var e2 = try r.maskFromRect(A, .{ .x = nan, .y = 0, .w = 1, .h = 1 }, big_clip);
    defer e2.deinit(A);
    try testing.expect(e2.bounds.isEmpty());
}

test "image row cache matches the uncached bilinear path" {
    var src = try r.Pixmap.init(A, 37, 23);
    defer src.deinit(A);
    var seed: u32 = 12345;
    for (src.pixels()) |*p| {
        seed = seed *% 1664525 +% 1013904223;
        p.* = r.Color.rgba(@truncate(seed >> 8), @truncate(seed >> 16), @truncate(seed >> 24), @truncate(seed >> 3)).premul();
    }
    const transforms = [_]r.Affine{
        r.Affine.translate(3.25, 1.5).mul(r.Affine.scale(2.3, 1.7)),
        r.Affine.translate(5, 2).mul(r.Affine.scale(0.8, 0.6)),
        r.Affine.translate(60, 4).mul(r.Affine.scale(-1.5, 2)),
    };
    for (transforms) |t| {
        var a = try r.Pixmap.init(A, 100, 48);
        defer a.deinit(A);
        var b = try r.Pixmap.init(A, 100, 48);
        defer b.deinit(A);
        // cached: one wide draw
        r.drawPixmap(&a, &src, t, 1, .bilinear, null);
        // uncached: 4 px wide strips (below the cache threshold) through rect clips
        var x: i32 = 0;
        while (x < 100) : (x += 4) {
            const clip = r.ClipMask.fromRect(.{ .x = x, .y = 0, .w = 4, .h = 48 });
            r.drawPixmap(&b, &src, t, 1, .bilinear, &clip);
        }
        var nonzero: usize = 0;
        for (a.data, b.data) |va, vb| {
            if (va != 0) nonzero += 1;
            try testing.expect(@abs(@as(i32, va) - @as(i32, vb)) <= 2);
        }
        try testing.expect(nonzero > 1000);
    }
}

test "gradient through a mask with clip matches fillRect" {
    var a = try r.Pixmap.init(A, 90, 20);
    defer a.deinit(A);
    var b = try r.Pixmap.init(A, 90, 20);
    defer b.deinit(A);
    const stops = [_]r.GradientStop{
        .{ .offset = 0, .color = r.Color.rgba(255, 0, 0, 255) },
        .{ .offset = 0.4, .color = r.Color.rgba(0, 255, 0, 128) },
        .{ .offset = 1, .color = r.Color.rgba(0, 0, 255, 255) },
    };
    const paints = [_]r.Paint{
        .{ .linear = .{ .p0 = .{ .x = 3, .y = 2 }, .p1 = .{ .x = 80, .y = 17 }, .stops = &stops } },
        .{ .linear = .{ .p0 = .{ .x = 3, .y = 2 }, .p1 = .{ .x = 20, .y = 9 }, .stops = &stops, .repeating = true } },
        .{ .radial = .{ .center = .{ .x = 40, .y = 9 }, .rx = 35, .ry = 12, .stops = &stops } },
        .{ .radial = .{ .center = .{ .x = 40, .y = 9 }, .rx = 9, .ry = 5, .stops = &stops, .repeating = true } },
        .{ .conic = .{ .center = .{ .x = 41.5, .y = 9.5 }, .start_angle = 1, .stops = &stops, .max_radius = 50 } },
        .{ .conic = .{ .center = .{ .x = 41.5, .y = 9.5 }, .start_angle = 1, .stops = &stops, .repeating = true } },
    };
    var p: r.Path = .empty;
    defer p.deinit(A);
    try p.addRect(A, .{ .x = 0, .y = 0, .w = 90, .h = 20 });
    for (paints) |paint| {
        a.clear(r.Color.rgb(9, 9, 9));
        b.clear(r.Color.rgb(9, 9, 9));
        r.fillRect(&a, .{ .x = 0, .y = 0, .w = 90, .h = 20 }, &paint, null);
        // same fill split in odd-sized pieces through the mask path (different span starts)
        var x: i32 = 0;
        var step: u32 = 1;
        while (x < 90) {
            const clip = r.ClipMask.fromRect(.{ .x = x, .y = 0, .w = step, .h = 20 });
            try r.fillPath(A, &b, &p, r.Affine.identity, .nonzero, &paint, &clip);
            x += @intCast(step);
            step = step % 13 + 3;
        }
        try testing.expectEqualSlices(u8, a.data, b.data);
        var distinct: u32 = 0;
        for (a.pixels()[1..], a.pixels()[0 .. a.pixels().len - 1]) |u, v| {
            if (u != v) distinct += 1;
        }
        try testing.expect(distinct > 50);
    }
}

test "sinCos / expNeg accuracy" {
    const types = @import("types.zig");
    var x: f32 = -50;
    while (x < 50) : (x += 0.0137) {
        const sc = types.sinCos(x);
        try testing.expectApproxEqAbs(@sin(x), sc[0], 2e-7);
        try testing.expectApproxEqAbs(@cos(x), sc[1], 2e-7);
    }
    const big = types.sinCos(12345.678);
    try testing.expectApproxEqAbs(@sin(@as(f32, 12345.678)), big[0], 1e-6);
    try testing.expect(std.math.isNan(types.sinCos(std.math.inf(f32))[0]));
    try testing.expectEqual(@as(f32, 0), types.sinCos(0)[0]);
    try testing.expectEqual(@as(f32, 1), types.sinCos(0)[1]);
    var t: f32 = 0;
    while (t < 40) : (t += 0.0371) {
        const want = @exp(-t);
        try testing.expect(@abs(types.expNeg(t) - want) <= want * 4e-7);
    }
    try testing.expectEqual(@as(f32, 0), types.expNeg(1e9));
    try testing.expectEqual(@as(f32, 1), types.expNeg(0));
}
