//! Painter: walks the laid-out node tree and draws boxes, text and images (takumi/Blink paint order:
//! outer shadows -> background -> inset shadows -> border -> content -> children).
const std = @import("std");
const render = @import("render.zig");
const style = @import("style/style.zig");
const font = @import("font/font.zig");
const raster = @import("raster/raster.zig");
const rtypes = @import("raster/types.zig");

const Frame = render.Frame;
const Node = render.Node;
const CS = render.CS;
const none = render.none;
const Rect = raster.Rect;
const IRect = raster.IRect;
const Affine = raster.Affine;
const Pixmap = raster.Pixmap;
const ClipMask = raster.ClipMask;
const Paint = raster.Paint;
const Error = render.Error;
const Radii = [4][2]f32;

const Ctx = struct {
    dst: *Pixmap,
    clip: ?*const ClipMask = null,
    tf: Affine = Affine.identity,

    fn plain(c: *const Ctx) bool {
        return c.tf.isIdentity();
    }
};

fn rcolor(c: style.Color) raster.Color {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
}

inline fn roundHalfUp(v: f32) f32 {
    return @floor(v + 0.5);
}

/// Blink `SnapSizeToPixel`.
fn snapSize(pos: f32, size: f32) f32 {
    const frac = pos - @floor(pos);
    const s = roundHalfUp(frac + size) - roundHalfUp(frac);
    if (s == 0 and @abs(size) > 4.0 / 64.0) return if (size > 0) 1 else -1;
    return s;
}

fn snapRect(x: f32, y: f32, w: f32, h: f32) Rect {
    return .{ .x = roundHalfUp(x), .y = roundHalfUp(y), .w = @max(0, snapSize(x, w)), .h = @max(0, snapSize(y, h)) };
}

fn insetRect(r: Rect, t: f32, rg: f32, b: f32, l: f32) Rect {
    return .{ .x = r.x + l, .y = r.y + t, .w = @max(0, r.w - l - rg), .h = @max(0, r.h - t - b) };
}

fn hasRadii(r: Radii) bool {
    for (r) |c| if (c[0] > 0 and c[1] > 0) return true;
    return false;
}

fn insetRadii(r: Radii, t: f32, rg: f32, b: f32, l: f32) Radii {
    return .{
        .{ @max(0, r[0][0] - l), @max(0, r[0][1] - t) },
        .{ @max(0, r[1][0] - rg), @max(0, r[1][1] - t) },
        .{ @max(0, r[2][0] - rg), @max(0, r[2][1] - b) },
        .{ @max(0, r[3][0] - l), @max(0, r[3][1] - b) },
    };
}

fn spreadRadii(r: Radii, spread: f32) Radii {
    var out = r;
    for (&out) |*c| {
        if (c[0] > 0 and c[1] > 0) {
            c[0] = @max(0, c[0] + spread);
            c[1] = @max(0, c[1] + spread);
        } else c.* = .{ 0, 0 };
    }
    return out;
}

fn resolveRadii(cs: *const CS, w: f32, h: f32) Radii {
    var r: Radii = undefined;
    for (0..4) |i| {
        r[i] = .{ @max(0, cs.border_radius[i][0].resolve(w)), @max(0, cs.border_radius[i][1].resolve(h)) };
        if (r[i][0] <= 0 or r[i][1] <= 0) r[i] = .{ 0, 0 };
    }
    // CSS corner overlap: scale all radii by the smallest ratio.
    var f: f32 = 1;
    const sums = [4]struct { s: f32, lim: f32 }{
        .{ .s = r[0][0] + r[1][0], .lim = w },
        .{ .s = r[3][0] + r[2][0], .lim = w },
        .{ .s = r[0][1] + r[3][1], .lim = h },
        .{ .s = r[1][1] + r[2][1], .lim = h },
    };
    for (sums) |e| if (e.s > e.lim and e.s > 0) {
        f = @min(f, e.lim / e.s);
    };
    if (f < 1) for (&r) |*c| {
        c[0] *= f;
        c[1] *= f;
    };
    return r;
}

const Geom = struct {
    /// pixel-snapped border box
    bx: Rect,
    /// border widths top, right, bottom, left
    bw: [4]f32,
    /// layout padding top, right, bottom, left
    pad: [4]f32,
    radii: Radii,
    rounded: bool,
    snapped: bool = true,

    fn padRect(g: *const Geom) Rect {
        return insetRect(g.bx, g.bw[0], g.bw[1], g.bw[2], g.bw[3]);
    }
    fn padRadii(g: *const Geom) ?Radii {
        if (!g.rounded) return null;
        const r = insetRadii(g.radii, g.bw[0], g.bw[1], g.bw[2], g.bw[3]);
        return if (hasRadii(r)) r else null;
    }
    fn contentRect(g: *const Geom) Rect {
        const p = g.padRect();
        if (!g.snapped) return insetRect(p, g.pad[0], g.pad[1], g.pad[2], g.pad[3]);
        const x0 = roundHalfUp(p.x + g.pad[3]);
        const y0 = roundHalfUp(p.y + g.pad[0]);
        const x1 = roundHalfUp(p.x + p.w - g.pad[1]);
        const y1 = roundHalfUp(p.y + p.h - g.pad[2]);
        return .{ .x = x0, .y = y0, .w = @max(0, x1 - x0), .h = @max(0, y1 - y0) };
    }
    fn contentRadii(g: *const Geom) ?Radii {
        if (!g.rounded) return null;
        const r = insetRadii(g.radii, g.bw[0] + g.pad[0], g.bw[1] + g.pad[1], g.bw[2] + g.pad[2], g.bw[3] + g.pad[3]);
        return if (hasRadii(r)) r else null;
    }
    fn outerRadii(g: *const Geom) ?Radii {
        return if (g.rounded) g.radii else null;
    }
};

const Painter = struct {
    f: *Frame,
    a: std.mem.Allocator,
    path: raster.Path = .empty,
    path2: raster.Path = .empty,
    /// reusable full-canvas offscreen layers, one per opacity nesting level
    layers: std.ArrayList(Pixmap) = .empty,
    layer_depth: usize = 0,

    fn rast(p: *Painter) *raster.Rasterizer {
        return &p.f.r.rast;
    }

    fn setRRect(p: *Painter, r: Rect, radii: ?Radii) Error!void {
        p.path.reset();
        if (radii) |rr| {
            p.path.addRoundRect(p.a, r, rr) catch return error.OutOfMemory;
        } else p.path.addRect(p.a, r) catch return error.OutOfMemory;
    }

    noinline fn fillRRect(p: *Painter, ctx: *const Ctx, r: Rect, radii: ?Radii, pt: *const Paint) Error!void {
        if (!(r.w > 0) or !(r.h > 0)) return;
        if (radii == null and ctx.plain()) {
            raster.fillRect(ctx.dst, r, pt, ctx.clip);
            return;
        }
        try p.setRRect(r, radii);
        if (radii != null and ctx.plain() and r.w * r.h >= 4096 and @floor(r.x) == r.x and @floor(r.y) == r.y and @floor(r.w) == r.w and @floor(r.h) == r.h) {
            // Large rounded rect: only the four corner cells go through the path rasterizer.
            const rr = radii.?;
            const a = @ceil(rr[0][0]);
            const b = @ceil(rr[1][0]);
            const d = @ceil(rr[2][0]);
            const c = @ceil(rr[3][0]);
            const top = @max(@ceil(rr[0][1]), @ceil(rr[1][1]));
            const bot = @max(@ceil(rr[2][1]), @ceil(rr[3][1]));
            if (top + bot <= r.h and a + b <= r.w and c + d <= r.w) {
                raster.fillRect(ctx.dst, .{ .x = r.x, .y = r.y + top, .w = r.w, .h = r.h - top - bot }, pt, ctx.clip);
                raster.fillRect(ctx.dst, .{ .x = r.x + a, .y = r.y, .w = r.w - a - b, .h = top }, pt, ctx.clip);
                raster.fillRect(ctx.dst, .{ .x = r.x + c, .y = r.y + r.h - bot, .w = r.w - c - d, .h = bot }, pt, ctx.clip);
                const cells = [4]Rect{
                    .{ .x = r.x, .y = r.y, .w = a, .h = top },
                    .{ .x = r.x + r.w - b, .y = r.y, .w = b, .h = top },
                    .{ .x = r.x + r.w - d, .y = r.y + r.h - bot, .w = d, .h = bot },
                    .{ .x = r.x, .y = r.y + r.h - bot, .w = c, .h = bot },
                };
                for (cells) |cell| {
                    if (!(cell.w > 0) or !(cell.h > 0)) continue;
                    var cc = ClipMask.fromRect(toIRect(cell));
                    if (ctx.clip) |outer| cc = raster.clipIntersect(p.a, outer.*, cc) catch return error.OutOfMemory;
                    if (cc.bounds.isEmpty()) continue;
                    p.rast().fillPath(ctx.dst, &p.path, ctx.tf, .nonzero, pt, &cc) catch return error.OutOfMemory;
                }
                return;
            }
        }
        p.rast().fillPath(ctx.dst, &p.path, ctx.tf, .nonzero, pt, ctx.clip) catch return error.OutOfMemory;
    }

    fn region(ctx: *const Ctx) IRect {
        var reg = ctx.dst.bounds();
        if (ctx.clip) |c| reg = reg.intersect(c.bounds);
        return reg;
    }

    fn toIRect(r: Rect) IRect {
        const lim: f32 = 1.0e6;
        const x0 = std.math.clamp(r.x, -lim, lim);
        const y0 = std.math.clamp(r.y, -lim, lim);
        const x1 = std.math.clamp(r.x + r.w, -lim, lim);
        const y1 = std.math.clamp(r.y + r.h, -lim, lim);
        return .{
            .x = @intFromFloat(@floor(x0)),
            .y = @intFromFloat(@floor(y0)),
            .w = @intFromFloat(@max(0, @ceil(x1) - @floor(x0))),
            .h = @intFromFloat(@max(0, @ceil(y1) - @floor(y0))),
        };
    }

    /// New clip = current clip ∩ (rounded) rect, allocated in the arena.
    noinline fn makeClip(p: *Painter, ctx: *const Ctx, r: Rect, radii: ?Radii) Error!*const ClipMask {
        var c: ClipMask = undefined;
        if (radii == null and ctx.plain()) {
            c = ClipMask.fromRect(toIRect(r).intersect(ctx.dst.bounds()));
        } else {
            try p.setRRect(r, radii);
            const m = p.rast().rasterize(p.a, &p.path, ctx.tf, .nonzero, region(ctx)) catch return error.OutOfMemory;
            c = m.asClip();
        }
        if (ctx.clip) |cc| c = raster.clipIntersect(p.a, cc.*, c) catch return error.OutOfMemory;
        const out = try p.a.create(ClipMask);
        out.* = c;
        return out;
    }

    // ---- gradients

    fn convertStops(p: *Painter, g: *const style.Gradient, len: f32, cur: style.Color) Error![]raster.GradientStop {
        const rs = style.resolveStops(p.a, g.stops, len, cur) catch return error.OutOfMemory;
        const out = try p.a.alloc(raster.GradientStop, rs.len);
        const inv: f32 = if (len > 0) 1.0 / len else 0;
        for (rs, 0..) |s, i| out[i] = .{ .offset = s.offset_px * inv, .color = rcolor(s.color) };
        return out;
    }

    noinline fn gradientPaint(p: *Painter, g: *const style.Gradient, tile: Rect, cur: style.Color, tf: Affine) Error!?Paint {
        const w = tile.w;
        const h = tile.h;
        if (!(w > 0) or !(h > 0) or g.stops.len == 0) return null;
        const plain = tf.isIdentity();
        switch (g.kind) {
            .linear => {
                var dx: f32 = 0;
                var dy: f32 = 0;
                if (g.corner_x != 0 or g.corner_y != 0) {
                    dx = @as(f32, @floatFromInt(g.corner_x)) * h;
                    dy = @as(f32, @floatFromInt(g.corner_y)) * w;
                    const nrm = @sqrt(dx * dx + dy * dy);
                    if (!(nrm > 0)) return null;
                    dx /= nrm;
                    dy /= nrm;
                } else {
                    const deg = @mod(g.angle, 360);
                    if (deg == 0) {
                        dy = -1;
                    } else if (deg == 90) {
                        dx = 1;
                    } else if (deg == 180) {
                        dy = 1;
                    } else if (deg == 270) {
                        dx = -1;
                    } else {
                        const sc = rtypes.sinCos(deg * (std.math.pi / 180.0));
                        dx = sc[0];
                        dy = -sc[1];
                    }
                }
                const len = @abs(w * dx) + @abs(h * dy);
                if (!(len > 0)) return null;
                const cx = tile.x + w * 0.5;
                const cy = tile.y + h * 0.5;
                var p0: raster.Point = .{ .x = cx - dx * len * 0.5, .y = cy - dy * len * 0.5 };
                var p1: raster.Point = .{ .x = cx + dx * len * 0.5, .y = cy + dy * len * 0.5 };
                if (!plain) {
                    p0 = tf.apply(p0);
                    p1 = tf.apply(p1);
                }
                return .{ .linear = .{ .p0 = p0, .p1 = p1, .stops = try p.convertStops(g, len, cur), .repeating = g.repeating } };
            },
            .radial => {
                const px = g.position[0].resolve(w);
                const py = g.position[1].resolve(h);
                const dl = @abs(px);
                const dr = @abs(w - px);
                const dt = @abs(py);
                const db = @abs(h - py);
                var rx: f32 = 0;
                var ry: f32 = 0;
                const circle = g.shape == .circle;
                switch (g.extent) {
                    .closest_side => {
                        rx = @min(dl, dr);
                        ry = @min(dt, db);
                        if (circle) {
                            rx = @min(rx, ry);
                            ry = rx;
                        }
                    },
                    .farthest_side => {
                        rx = @max(dl, dr);
                        ry = @max(dt, db);
                        if (circle) {
                            rx = @max(rx, ry);
                            ry = rx;
                        }
                    },
                    .closest_corner => {
                        rx = @min(dl, dr);
                        ry = @min(dt, db);
                        if (circle) {
                            rx = @sqrt(rx * rx + ry * ry);
                            ry = rx;
                        } else {
                            rx *= std.math.sqrt2;
                            ry *= std.math.sqrt2;
                        }
                    },
                    .farthest_corner => {
                        rx = @max(dl, dr);
                        ry = @max(dt, db);
                        if (circle) {
                            rx = @sqrt(rx * rx + ry * ry);
                            ry = rx;
                        } else {
                            rx *= std.math.sqrt2;
                            ry *= std.math.sqrt2;
                        }
                    },
                    .explicit => {
                        rx = g.radius[0].resolve(w);
                        ry = if (circle) rx else g.radius[1].resolve(h);
                    },
                }
                rx = @max(rx, 1.0e-3);
                ry = @max(ry, 1.0e-3);
                return .{ .radial = .{
                    .center = .{ .x = tile.x + px, .y = tile.y + py },
                    .rx = rx,
                    .ry = ry,
                    .stops = try p.convertStops(g, rx, cur),
                    .repeating = g.repeating,
                    .transform = if (plain) null else (tf.invert() orelse return null),
                } };
            },
            .conic => {
                const px = g.position[0].resolve(w);
                const py = g.position[1].resolve(h);
                const mx = @max(@abs(px), @abs(w - px));
                const my = @max(@abs(py), @abs(h - py));
                var c: raster.Point = .{ .x = tile.x + px, .y = tile.y + py };
                if (!plain) c = tf.apply(c);
                return .{ .conic = .{
                    .center = c,
                    .start_angle = g.angle * (std.math.pi / 180.0),
                    .stops = try p.convertStops(g, 360, cur),
                    .repeating = g.repeating,
                    .max_radius = @sqrt(mx * mx + my * my),
                } };
            },
        }
    }

    // ---- images

    noinline fn drawImage(p: *Painter, ctx: *const Ctx, pm: *const Pixmap, dest: Rect) void {
        if (!(dest.w > 0) or !(dest.h > 0) or pm.width == 0 or pm.height == 0) return;
        const tw: u32 = @intFromFloat(@min(16384, @max(1, roundHalfUp(dest.w))));
        const th: u32 = @intFromFloat(@min(16384, @max(1, roundHalfUp(dest.h))));
        const src = p.f.r.resampled(pm, tw, th);
        const sx = dest.w / @as(f32, @floatFromInt(src.width));
        const sy = dest.h / @as(f32, @floatFromInt(src.height));
        const m = ctx.tf.mul(Affine.translate(dest.x, dest.y)).mul(Affine.scale(sx, sy));
        raster.drawPixmap(ctx.dst, src, m, 1, .bilinear, ctx.clip);
    }

    // ---- background

    const Area = struct { rect: Rect, radii: ?Radii };

    fn area(g: *const Geom, box: anytype) Area {
        return switch (box) {
            .padding_box => .{ .rect = g.padRect(), .radii = g.padRadii() },
            .content_box => .{ .rect = g.contentRect(), .radii = g.contentRadii() },
            else => .{ .rect = g.bx, .radii = g.outerRadii() },
        };
    }

    noinline fn paintBackground(p: *Painter, ctx: *const Ctx, cs: *const CS, g: *const Geom) Error!void {
        const col = cs.resolveColor(cs.background_color);
        if (col.a != 0) {
            const ar = area(g, cs.bgColorClip());
            try p.fillRRect(ctx, ar.rect, ar.radii, &.{ .solid = rcolor(col) });
        }
        var i = cs.background_image.len;
        while (i > 0) {
            i -= 1;
            const layer = cs.bgLayer(i);
            if (layer.image == .none) continue;
            const o = area(g, layer.origin).rect;
            const pa = area(g, layer.clip);
            if (!(o.w > 0) or !(o.h > 0)) continue;

            var iw: f32 = 0;
            var ih: f32 = 0;
            var pm: ?*const Pixmap = null;
            if (layer.image == .url) {
                pm = p.f.r.resolveImage(layer.image.url) orelse continue;
                iw = @as(f32, @floatFromInt(pm.?.width)) * p.f.opts.dpr;
                ih = @as(f32, @floatFromInt(pm.?.height)) * p.f.opts.dpr;
                if (!(iw > 0) or !(ih > 0)) continue;
            }
            var tw: f32 = o.w;
            var th: f32 = o.h;
            switch (layer.size) {
                .cover, .contain => if (pm != null) {
                    const sx = o.w / iw;
                    const sy = o.h / ih;
                    const s = if (layer.size == .cover) @max(sx, sy) else @min(sx, sy);
                    tw = iw * s;
                    th = ih * s;
                },
                .size => |sz| {
                    const a0: ?f32 = if (sz[0] == .lp) sz[0].lp.resolve(o.w) else null;
                    const a1: ?f32 = if (sz[1] == .lp) sz[1].lp.resolve(o.h) else null;
                    if (a0 == null and a1 == null) {
                        if (pm != null) {
                            tw = iw;
                            th = ih;
                        }
                    } else if (a0 != null and a1 != null) {
                        tw = a0.?;
                        th = a1.?;
                    } else if (a0) |v| {
                        tw = v;
                        th = if (pm != null) v * ih / iw else o.h;
                    } else {
                        th = a1.?;
                        tw = if (pm != null) th * iw / ih else o.w;
                    }
                },
            }
            if (!(tw > 0) or !(th > 0)) continue;
            const tx = o.x + layer.position[0].px + layer.position[0].pct * (o.w - tw);
            const ty = o.y + layer.position[1].px + layer.position[1].pct * (o.h - th);
            const rep_x = layer.repeat[0] != .no_repeat;
            const rep_y = layer.repeat[1] != .no_repeat;

            if (layer.image == .gradient and tw == o.w and th == o.h and tx == o.x and ty == o.y) {
                // Single tile covering the positioning area (the overwhelmingly common case).
                const pt = (try p.gradientPaint(layer.image.gradient, o, cs.color, ctx.tf)) orelse continue;
                if (rep_x and rep_y) {
                    try p.fillRRect(ctx, pa.rect, pa.radii, &pt);
                } else {
                    var c2 = ctx.*;
                    c2.clip = try p.makeClip(ctx, pa.rect, pa.radii);
                    try p.fillRRect(&c2, o, null, &pt);
                }
                continue;
            }

            var c2 = ctx.*;
            c2.clip = try p.makeClip(ctx, pa.rect, pa.radii);
            const px0 = pa.rect.x;
            const py0 = pa.rect.y;
            const px1 = pa.rect.x + pa.rect.w;
            const py1 = pa.rect.y + pa.rect.h;
            var y = if (rep_y) ty - @ceil((ty - py0) / th) * th else ty;
            var count: u32 = 0;
            while (y < py1 and count < 20000) : (y += th) {
                var x = if (rep_x) tx - @ceil((tx - px0) / tw) * tw else tx;
                while (x < px1 and count < 20000) : (x += tw) {
                    count += 1;
                    const tile: Rect = .{ .x = x, .y = y, .w = tw, .h = th };
                    if (pm) |im| {
                        p.drawImage(&c2, im, tile);
                    } else {
                        const pt = (try p.gradientPaint(layer.image.gradient, tile, cs.color, ctx.tf)) orelse break;
                        try p.fillRRect(&c2, tile, null, &pt);
                    }
                    if (!rep_x) break;
                }
                if (!rep_y) break;
            }
        }
    }

    // ---- shadows

    fn tfScale(tf: Affine) f32 {
        const det = @abs(tf.a * tf.d - tf.b * tf.c);
        return if (det > 0) @sqrt(det) else 1;
    }

    noinline fn paintOuterShadows(p: *Painter, ctx: *const Ctx, cs: *const CS, g: *const Geom) Error!void {
        var i = cs.box_shadow.len;
        while (i > 0) {
            i -= 1;
            const sh = cs.box_shadow[i];
            if (sh.inset) continue;
            const col = cs.resolveColor(sh.color);
            if (col.a == 0) continue;
            const r: Rect = .{ .x = g.bx.x + sh.x - sh.spread, .y = g.bx.y + sh.y - sh.spread, .w = g.bx.w + 2 * sh.spread, .h = g.bx.h + 2 * sh.spread };
            if (!(r.w > 0) or !(r.h > 0)) continue;
            const radii: ?Radii = if (g.rounded) spreadRadii(g.radii, sh.spread) else null;
            const sigma = sh.blur * 0.5 * tfScale(ctx.tf);
            const reach = raster.blurReach(sigma);
            const visible = region(ctx);
            if (visible.isEmpty()) continue;
            try p.setRRect(r, radii);
            var mask = p.rast().rasterize(p.a, &p.path, ctx.tf, .nonzero, visible.expand(reach)) catch return error.OutOfMemory;
            if (mask.bounds.isEmpty()) continue;
            raster.blurMaskClipped(p.a, &mask, sigma, visible) catch return error.OutOfMemory;
            if (mask.bounds.isEmpty()) continue;
            // Clip the shadow out of the border box.
            if (!g.rounded and ctx.plain()) {
                const hole = toIRect(g.bx).intersect(mask.bounds);
                if (!hole.isEmpty()) {
                    var yy: u32 = 0;
                    while (yy < hole.h) : (yy += 1) {
                        const row: usize = @intCast(@as(i64, hole.y) + yy - mask.bounds.y);
                        const col0: usize = @intCast(@as(i64, hole.x) - mask.bounds.x);
                        @memset(mask.data[row * mask.bounds.w + col0 ..][0..hole.w], 0);
                    }
                }
            } else {
                try p.setRRect(g.bx, g.outerRadii());
                const box = p.rast().rasterize(p.a, &p.path, ctx.tf, .nonzero, mask.bounds) catch return error.OutOfMemory;
                const bb = box.bounds;
                var yy: u32 = 0;
                while (yy < bb.h) : (yy += 1) {
                    const row: usize = @intCast(@as(i64, bb.y) + yy - mask.bounds.y);
                    const col0: usize = @intCast(@as(i64, bb.x) - mask.bounds.x);
                    const dstrow = mask.data[row * mask.bounds.w + col0 ..][0..bb.w];
                    const srow = box.data[@as(usize, yy) * bb.w ..][0..bb.w];
                    for (dstrow, srow) |*d, s| d.* = @intCast(raster.div255(@as(u32, d.*) * (255 - @as(u32, s))));
                }
            }
            raster.fillMask(ctx.dst, &mask, &.{ .solid = rcolor(col) }, ctx.clip);
        }
    }

    noinline fn paintInsetShadows(p: *Painter, ctx: *const Ctx, cs: *const CS, g: *const Geom) Error!void {
        var any = false;
        for (cs.box_shadow) |sh| {
            if (sh.inset) any = true;
        }
        if (!any) return;
        const pr = g.padRect();
        if (!(pr.w > 0) or !(pr.h > 0)) return;
        const prad = g.padRadii();
        const clip = try p.makeClip(ctx, pr, prad);
        // Device-space bounds of the padding box.
        var pb: IRect = undefined;
        if (ctx.plain()) {
            pb = toIRect(pr).intersect(region(ctx));
        } else {
            pb = clip.bounds;
        }
        if (pb.isEmpty()) return;
        var i = cs.box_shadow.len;
        while (i > 0) {
            i -= 1;
            const sh = cs.box_shadow[i];
            if (!sh.inset) continue;
            const col = cs.resolveColor(sh.color);
            if (col.a == 0) continue;
            const sigma = sh.blur * 0.5 * tfScale(ctx.tf);
            const reach = raster.blurReach(sigma);
            const within = pb.expand(reach + 1);
            const r: Rect = .{ .x = pr.x + sh.x + sh.spread, .y = pr.y + sh.y + sh.spread, .w = pr.w - 2 * sh.spread, .h = pr.h - 2 * sh.spread };
            var shape: raster.Mask = raster.Mask.empty;
            if (r.w > 0 and r.h > 0) {
                const radii: ?Radii = if (prad) |rr| spreadRadii(rr, -sh.spread) else null;
                try p.setRRect(r, radii);
                shape = p.rast().rasterize(p.a, &p.path, ctx.tf, .nonzero, within) catch return error.OutOfMemory;
            }
            var inv = raster.maskInvertWithin(p.a, &shape, within) catch return error.OutOfMemory;
            raster.blurMaskClipped(p.a, &inv, sigma, pb) catch return error.OutOfMemory;
            raster.fillMask(ctx.dst, &inv, &.{ .solid = rcolor(col) }, clip);
        }
    }

    // ---- border

    noinline fn paintBorder(p: *Painter, ctx: *const Ctx, cs: *const CS, g: *const Geom) Error!void {
        const bw = g.bw;
        if (bw[0] <= 0 and bw[1] <= 0 and bw[2] <= 0 and bw[3] <= 0) return;
        var cols: [4]style.Color = undefined;
        var uniform = true;
        var first: ?style.Color = null;
        for (0..4) |i| {
            cols[i] = cs.resolveColor(cs.border_color[i]);
            if (bw[i] > 0) {
                if (first) |fc| {
                    if (!fc.eql(cols[i])) uniform = false;
                } else first = cols[i];
            }
        }
        const b = g.bx;
        const in = g.padRect();
        if (uniform) {
            const c = first.?;
            if (c.a == 0) return;
            const pt: Paint = .{ .solid = rcolor(c) };
            if (!g.rounded and ctx.plain()) {
                raster.fillRect(ctx.dst, .{ .x = b.x, .y = b.y, .w = b.w, .h = bw[0] }, &pt, ctx.clip);
                raster.fillRect(ctx.dst, .{ .x = b.x, .y = in.y + in.h, .w = b.w, .h = bw[2] }, &pt, ctx.clip);
                raster.fillRect(ctx.dst, .{ .x = b.x, .y = in.y, .w = bw[3], .h = in.h }, &pt, ctx.clip);
                raster.fillRect(ctx.dst, .{ .x = in.x + in.w, .y = in.y, .w = bw[1], .h = in.h }, &pt, ctx.clip);
                return;
            }
            try p.ringPath(g);
            p.rast().fillPath(ctx.dst, &p.path, ctx.tf, .evenodd, &pt, ctx.clip) catch return error.OutOfMemory;
            return;
        }
        // Per-side colours: intersect the ring with one wedge per side.
        try p.ringPath(g);
        const ring = p.rast().rasterize(p.a, &p.path, ctx.tf, .evenodd, region(ctx)) catch return error.OutOfMemory;
        if (ring.bounds.isEmpty()) return;
        const m = @min(in.w, in.h) * 0.5;
        const x0 = b.x;
        const y0 = b.y;
        const x1 = b.x + b.w;
        const y1 = b.y + b.h;
        const ix0 = in.x;
        const iy0 = in.y;
        const ix1 = in.x + in.w;
        const iy1 = in.y + in.h;
        const wedges = [4][6][2]f32{
            .{ .{ x0, y0 }, .{ x1, y0 }, .{ ix1, iy0 }, .{ ix1 - m, iy0 + m }, .{ ix0 + m, iy0 + m }, .{ ix0, iy0 } },
            .{ .{ x1, y0 }, .{ x1, y1 }, .{ ix1, iy1 }, .{ ix1 - m, iy1 - m }, .{ ix1 - m, iy0 + m }, .{ ix1, iy0 } },
            .{ .{ x1, y1 }, .{ x0, y1 }, .{ ix0, iy1 }, .{ ix0 + m, iy1 - m }, .{ ix1 - m, iy1 - m }, .{ ix1, iy1 } },
            .{ .{ x0, y1 }, .{ x0, y0 }, .{ ix0, iy0 }, .{ ix0 + m, iy0 + m }, .{ ix0 + m, iy1 - m }, .{ ix0, iy1 } },
        };
        const cxm = (x0 + x1) * 0.5;
        const cym = (y0 + y1) * 0.5;
        for (0..4) |i| {
            if (bw[i] <= 0 or cols[i].a == 0) continue;
            p.path.reset();
            var wd = wedges[i];
            // A zero-width neighbour gives its whole corner to this side.
            const far: [4][2][2]f32 = .{
                .{ .{ x1, cym }, .{ x0, cym } },
                .{ .{ cxm, y1 }, .{ cxm, y0 } },
                .{ .{ x0, cym }, .{ x1, cym } },
                .{ .{ cxm, y0 }, .{ cxm, y1 } },
            };
            if (bw[(i + 1) % 4] <= 0) wd[3] = far[i][0];
            if (bw[(i + 3) % 4] <= 0) wd[4] = far[i][1];
            p.path.moveTo(p.a, wd[0][0], wd[0][1]) catch return error.OutOfMemory;
            for (wd[1..]) |pt| p.path.lineTo(p.a, pt[0], pt[1]) catch return error.OutOfMemory;
            p.path.close(p.a) catch return error.OutOfMemory;
            const wm = p.rast().rasterize(p.a, &p.path, ctx.tf, .nonzero, ring.bounds) catch return error.OutOfMemory;
            const side = raster.maskIntersect(p.a, &ring, &wm) catch return error.OutOfMemory;
            raster.fillMask(ctx.dst, &side, &.{ .solid = rcolor(cols[i]) }, ctx.clip);
        }
    }

    fn ringPath(p: *Painter, g: *const Geom) Error!void {
        p.path.reset();
        if (g.rounded) {
            p.path.addRoundRect(p.a, g.bx, g.radii) catch return error.OutOfMemory;
        } else p.path.addRect(p.a, g.bx) catch return error.OutOfMemory;
        const in = g.padRect();
        if (in.w > 0 and in.h > 0) {
            if (g.padRadii()) |rr| {
                p.path.addRoundRect(p.a, in, rr) catch return error.OutOfMemory;
            } else p.path.addRect(p.a, in) catch return error.OutOfMemory;
        }
    }

    // ---- text

    /// Builds the device-space outline of a glyph into `p.path` (synth bit0 = fake italic, skew -14.04deg).
    fn buildGlyph(p: *Painter, face: font.FaceId, gid: u16, size: f32, ox: f32, oy: f32, synth: u2, tf: Affine) bool {
        const fnt = p.f.r.fonts.font(face);
        var local = Affine.translate(ox, oy);
        if (synth & 1 != 0) local = local.mul(.{ .c = -0.25 });
        p.path.reset();
        var sink: raster.PathSink = .{ .path = &p.path, .alloc = p.a, .transform = tf.mul(local) };
        _ = font.emitGlyph(fnt, gid, size, 0, 0, &sink);
        return !sink.err;
    }

    /// Coverage mask of a glyph. synth bit1 = fake bold: the outline grown by half of Skia's
    /// fake-bold stroke width, approximated as the per-pixel max over 9 offset copies.
    noinline fn glyphCoverage(p: *Painter, out: std.mem.Allocator, face: font.FaceId, gid: u16, size: f32, ox: f32, oy: f32, synth: u2, tf: Affine, window: IRect) ?raster.Mask {
        if (!p.buildGlyph(face, gid, size, ox, oy, synth, tf)) return null;
        if (synth & 2 == 0) return p.sampled(out, window);
        const base = p.sampled(p.a, window) orelse return null;
        if (base.bounds.isEmpty()) return raster.Mask.empty;
        const t = std.math.clamp((size - 9) / 27, 0, 1);
        const rad = size * (1.0 / 24.0 + t * (1.0 / 32.0 - 1.0 / 24.0)) * 0.5;
        const grow: u32 = @intFromFloat(@ceil(rad * @max(1, Painter.tfScale(tf))) + 1);
        const win = base.bounds.expand(grow).intersect(window);
        var acc = raster.Mask.init(out, win) catch return null;
        const d = rad * 0.70710678;
        const offs = [8][2]f32{ .{ rad, 0 }, .{ -rad, 0 }, .{ 0, rad }, .{ 0, -rad }, .{ d, d }, .{ -d, d }, .{ d, -d }, .{ -d, -d } };
        mergeMax(&acc, &base);
        for (offs) |o| {
            if (!p.buildGlyph(face, gid, size, ox + o[0], oy + o[1], synth, tf)) continue;
            const m = p.sampled(p.a, win) orelse continue;
            mergeMax(&acc, &m);
        }
        return acc;
    }

    /// Rasterizes `p.path` like a 4x4 supersampling scan converter (what tiny-skia / takumi do):
    /// the path is scan-converted at 4x scale, each sub-cell thresholded at half coverage, and
    /// a pixel's coverage is 16 * (number of covered sub-cells), capped at 255.
    fn sampled(p: *Painter, out: std.mem.Allocator, window: IRect) ?raster.Mask {
        const r = p.f.r;
        const lim = 1 << 26;
        if (window.w > lim or window.h > lim or @abs(window.x) > lim or @abs(window.y) > lim) return null;
        const w4: IRect = .{ .x = window.x * 4, .y = window.y * 4, .w = window.w * 4, .h = window.h * 4 };
        const saved = r.rast.levels16;
        r.rast.levels16 = false;
        defer r.rast.levels16 = saved;
        var hi = r.rast.rasterize(p.a, &p.path, Affine.scale(4, 4), .nonzero, w4) catch return null;
        defer hi.deinit(p.a);
        if (hi.bounds.isEmpty()) return raster.Mask.empty;
        const x0 = @divFloor(hi.bounds.x, 4);
        const y0 = @divFloor(hi.bounds.y, 4);
        const x1 = @divFloor(hi.bounds.x + @as(i32, @intCast(hi.bounds.w)) + 3, 4);
        const y1 = @divFloor(hi.bounds.y + @as(i32, @intCast(hi.bounds.h)) + 3, 4);
        var m = raster.Mask.init(out, .{ .x = x0, .y = y0, .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) }) catch return null;
        const hw: usize = hi.bounds.w;
        var sy: usize = 0;
        while (sy < hi.bounds.h) : (sy += 1) {
            const oy: usize = @intCast(@divFloor(hi.bounds.y + @as(i32, @intCast(sy)), 4) - y0);
            const srow = hi.data[sy * hw ..][0..hw];
            const drow = m.data[oy * m.bounds.w ..][0..m.bounds.w];
            const xoff: usize = @intCast(hi.bounds.x - x0 * 4);
            for (srow, 0..) |v, sx| drow[(sx + xoff) >> 2] += v >> 7;
        }
        for (m.data) |*v| v.* = @intCast(@min(255, @as(u32, v.*) * 16));
        return m;
    }

    fn mergeMax(acc: *raster.Mask, m: *const raster.Mask) void {
        const b = m.bounds.intersect(acc.bounds);
        if (b.isEmpty()) return;
        var yy: u32 = 0;
        while (yy < b.h) : (yy += 1) {
            const ar: usize = @intCast(@as(i64, b.y) + yy - acc.bounds.y);
            const ac: usize = @intCast(@as(i64, b.x) - acc.bounds.x);
            const mr: usize = @intCast(@as(i64, b.y) + yy - m.bounds.y);
            const mc: usize = @intCast(@as(i64, b.x) - m.bounds.x);
            const drow = acc.data[ar * acc.bounds.w + ac ..][0..b.w];
            const srow = m.data[mr * m.bounds.w + mc ..][0..b.w];
            for (drow, srow) |*dv, sv| dv.* = @max(dv.*, sv);
        }
    }

    noinline fn glyphMask(p: *Painter, face: font.FaceId, gid: u16, size: f32, sub: u2, synth: u2) ?render.GlyphMask {
        const r = p.f.r;
        const key: u64 = (@as(u64, synth) << 62) | (@as(u64, face & 0xFFF) << 50) | (@as(u64, gid) << 34) | (@as(u64, sub) << 32) | @as(u32, @bitCast(size));
        if (r.glyphs.get(key)) |gm| return gm;
        const big: IRect = .{ .x = -8192, .y = -8192, .w = 16384, .h = 16384 };
        const m = p.glyphCoverage(r.gpa, face, gid, size, @as(f32, @floatFromInt(sub)) * 0.25, 0, synth, Affine.identity, big) orelse return null;
        const gm: render.GlyphMask = .{ .x = m.bounds.x, .y = m.bounds.y, .w = m.bounds.w, .h = m.bounds.h, .data = m.data };
        r.glyphs.put(r.gpa, key, gm) catch {
            if (m.data.len > 0) r.gpa.free(m.data);
            return null;
        };
        r.glyph_bytes += m.data.len + 48;
        return gm;
    }

    /// text-shadow: the glyph masks of the paragraph merged into one A8 mask, blurred and filled.
    noinline fn paintTextShadows(p: *Painter, ctx: *const Ctx, n: *const Node, tl: *const font.TextLayout, x: f32, y: f32, cw: f32) Error!void {
        const cs = n.cs;
        const vis = region(ctx);
        if (vis.isEmpty()) return;
        var i = cs.text_shadow.len;
        while (i > 0) {
            i -= 1;
            const sh = cs.text_shadow[i];
            const col = cs.resolveColor(sh.color);
            if (col.a == 0) continue;
            const sigma = sh.blur * 0.5;
            const reach = raster.blurReach(sigma);
            const pad = cs.font_size + 2;
            const sarea: Rect = .{ .x = x + sh.x - pad, .y = y + sh.y - pad, .w = @max(cw, tl.width) + 2 * pad, .h = tl.height + 2 * pad };
            const b = toIRect(sarea).intersect(vis.expand(reach));
            if (b.isEmpty()) continue;
            var mask = raster.Mask.init(p.a, b) catch return error.OutOfMemory;
            for (tl.glyphs) |g| {
                if (g.size > 400) continue;
                const fc = p.f.r.fonts.face(g.face);
                const rcs = if (g.user < p.f.run_styles.items.len) p.f.run_styles.items[g.user] else cs;
                var synth: u2 = 0;
                if (rcs.font_style != .normal and !fc.italic) synth |= 1;
                if (rcs.font_weight >= 600 and fc.weight < 600) synth |= 2;
                const qx = roundHalfUp((x + g.x + sh.x) * 4) * 0.25;
                const ix = @floor(qx);
                const sub: u2 = @intFromFloat(std.math.clamp((qx - ix) * 4, 0, 3));
                const iy = roundHalfUp(y + g.y + sh.y);
                if (@abs(ix) > 1.0e6 or @abs(iy) > 1.0e6) continue;
                const gm = p.glyphMask(g.face, g.gid, g.size, sub, synth) orelse continue;
                if (gm.w == 0 or gm.h == 0) continue;
                const one: raster.Mask = .{ .bounds = .{ .x = gm.x + @as(i32, @intFromFloat(ix)), .y = gm.y + @as(i32, @intFromFloat(iy)), .w = gm.w, .h = gm.h }, .data = gm.data };
                mergeMax(&mask, &one);
            }
            raster.blurMaskClipped(p.a, &mask, sigma, vis) catch return error.OutOfMemory;
            raster.fillMask(ctx.dst, &mask, &.{ .solid = rcolor(col) }, ctx.clip);
        }
    }

    noinline fn paintText(p: *Painter, ctx: *const Ctx, n: *const Node, x: f32, y: f32, cw: f32) Error!void {
        const para = n.para orelse return;
        const tl = para.layout(p.a, cw) catch return error.OutOfMemory;
        const f = p.f;
        const plain = ctx.plain();
        if (plain and n.cs.text_shadow.len > 0) try p.paintTextShadows(ctx, n, &tl, x, y, cw);
        for (tl.glyphs) |g| {
            const rcs = if (g.user < f.run_styles.items.len) f.run_styles.items[g.user] else n.cs;
            if (rcs.color.a == 0 or rcs.visibility != .visible) continue;
            const pt: Paint = .{ .solid = rcolor(rcs.color) };
            const gx = x + g.x;
            const gy = y + g.y;
            const fc = f.r.fonts.face(g.face);
            var synth: u2 = 0;
            if (rcs.font_style != .normal and !fc.italic) synth |= 1;
            if (rcs.font_weight >= 600 and fc.weight < 600) synth |= 2;
            if (plain and g.size <= 400) {
                const qx = roundHalfUp(gx * 4) * 0.25;
                const ix = @floor(qx);
                const sub: u2 = @intFromFloat(std.math.clamp((qx - ix) * 4, 0, 3));
                const iy = roundHalfUp(gy);
                if (@abs(ix) > 1.0e6 or @abs(iy) > 1.0e6) continue;
                const gm = p.glyphMask(g.face, g.gid, g.size, sub, synth) orelse continue;
                if (gm.w == 0 or gm.h == 0) continue;
                const mask: raster.Mask = .{
                    .bounds = .{ .x = gm.x + @as(i32, @intFromFloat(ix)), .y = gm.y + @as(i32, @intFromFloat(iy)), .w = gm.w, .h = gm.h },
                    .data = gm.data,
                };
                raster.fillMask(ctx.dst, &mask, &pt, ctx.clip);
            } else {
                const m = p.glyphCoverage(p.a, g.face, g.gid, g.size, gx, gy, synth, ctx.tf, region(ctx)) orelse return error.OutOfMemory;
                raster.fillMask(ctx.dst, &m, &pt, ctx.clip);
            }
        }
        // Decorations (underline / overline / line-through) of the block's own style.
        var deco = n.cs.text_decoration_line;
        var dcs = n.cs;
        if (!(deco.underline or deco.overline or deco.line_through) and n.parent != none and n.kind == .text) {
            dcs = f.nodes.items[n.parent].cs;
            deco = dcs.text_decoration_line;
        }
        if (!(deco.underline or deco.overline or deco.line_through)) return;
        const dcol = dcs.resolveColor(dcs.text_decoration_color);
        const dpt: Paint = .{ .solid = rcolor(if (dcs.text_decoration_color == .current) n.cs.color else dcol) };
        for (tl.lines) |line| {
            if (line.glyph_end <= line.glyph_start or !(line.width > 0)) continue;
            const g0 = tl.glyphs[line.glyph_start];
            const fnt = f.r.fonts.font(g0.face);
            const s = g0.size / @as(f32, @floatFromInt(@max(1, fnt.unitsPerEm())));
            var thick = dcs.text_decoration_thickness orelse @as(f32, @floatFromInt(fnt.underlineThickness())) * s;
            thick = @max(1, roundHalfUp(thick));
            const lx = x + line.x;
            const base = y + line.baseline;
            if (deco.underline) {
                const off = -@as(f32, @floatFromInt(fnt.underlinePosition())) * s;
                try p.fillRRect(ctx, .{ .x = lx, .y = roundHalfUp(base + off - thick * 0.5), .w = line.width, .h = thick }, null, &dpt);
            }
            if (deco.overline) {
                try p.fillRRect(ctx, .{ .x = lx, .y = roundHalfUp(base - line.ascent), .w = line.width, .h = thick }, null, &dpt);
            }
            if (deco.line_through) {
                var off = @as(f32, @floatFromInt(fnt.strikeoutPosition())) * s;
                if (off == 0) off = @as(f32, @floatFromInt(fnt.xHeight())) * s * 0.5;
                try p.fillRRect(ctx, .{ .x = lx, .y = roundHalfUp(base - off - thick * 0.5), .w = line.width, .h = thick }, null, &dpt);
            }
        }
    }

    // ---- nodes

    fn localTransform(cs: *const CS, x: f32, y: f32, w: f32, h: f32) ?Affine {
        const has = cs.transform.len > 0 or cs.rotate != 0 or cs.scale[0] != 1 or cs.scale[1] != 1 or cs.translate[0].px != 0 or cs.translate[0].pct != 0 or cs.translate[1].px != 0 or cs.translate[1].pct != 0;
        if (!has) return null;
        const d2r: f32 = std.math.pi / 180.0;
        const ox = x + cs.transform_origin[0].resolve(w);
        const oy = y + cs.transform_origin[1].resolve(h);
        var m = Affine.translate(ox, oy);
        m = m.mul(Affine.translate(cs.translate[0].resolve(w), cs.translate[1].resolve(h)));
        if (cs.rotate != 0) m = m.mul(Affine.rotate(cs.rotate * d2r));
        if (cs.scale[0] != 1 or cs.scale[1] != 1) m = m.mul(Affine.scale(cs.scale[0], cs.scale[1]));
        for (cs.transform) |op| {
            const t: Affine = switch (op) {
                .translate => |v| Affine.translate(v[0].resolve(w), v[1].resolve(h)),
                .scale => |v| Affine.scale(v[0], v[1]),
                .rotate => |deg| Affine.rotate(deg * d2r),
                .skew => |v| Affine.skew(v[0] * d2r, v[1] * d2r),
                .matrix => |v| .{ .a = v[0], .b = v[1], .c = v[2], .d = v[3], .e = v[4], .f = v[5] },
            };
            m = m.mul(t);
        }
        m = m.mul(Affine.translate(-ox, -oy));
        if (!m.isFinite()) return null;
        return m;
    }

    fn unionRect(a: Rect, b: Rect) Rect {
        if (!(a.w > 0) or !(a.h > 0)) return b;
        if (!(b.w > 0) or !(b.h > 0)) return a;
        const x0 = @min(a.x, b.x);
        const y0 = @min(a.y, b.y);
        const x1 = @max(a.x + a.w, b.x + b.w);
        const y1 = @max(a.y + a.h, b.y + b.h);
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    /// Conservative visual bounds of a subtree whose border box origin is (x, y); null = unknown
    /// (a descendant is transformed).
    fn subtreeBounds(p: *Painter, id: u32, x: f32, y: f32, depth: u32) ?Rect {
        const f = p.f;
        const n = &f.nodes.items[id];
        const cs = n.cs;
        const l = f.tree.layout(n.lid);
        if (depth > 256) return null;
        var r: Rect = .{ .x = x, .y = y, .w = l.w, .h = l.h };
        if (n.kind == .anon_text or n.kind == .text) {
            const m = cs.font_size;
            r = .{ .x = r.x - m, .y = r.y - m, .w = r.w + 2 * m, .h = r.h + 2 * m };
        }
        if (n.kind == .anon_text) return r;
        if (cs.display == .none) return .{ .x = x, .y = y, .w = 0, .h = 0 };
        for (cs.box_shadow) |sh| {
            if (sh.inset) continue;
            const e = @max(0, sh.spread) + @ceil(sh.blur * 1.5) + 2;
            r = unionRect(r, .{ .x = x + sh.x - e, .y = y + sh.y - e, .w = l.w + 2 * e, .h = l.h + 2 * e });
        }
        if (cs.overflow_x != .visible and cs.overflow_y != .visible) return r;
        var c = n.first_child;
        while (c != none) : (c = f.nodes.items[c].next) {
            const cn = &f.nodes.items[c];
            const cl = f.tree.layout(cn.lid);
            if (cn.kind != .anon_text and localTransform(cn.cs, 0, 0, cl.w, cl.h) != null) return null;
            const cb = p.subtreeBounds(c, x + cl.x, y + cl.y, depth + 1) orelse return null;
            r = unionRect(r, cb);
        }
        return r;
    }

    fn paintNode(p: *Painter, id: u32, ox: f32, oy: f32, ctx_in: *const Ctx, depth: u32) Error!void {
        const f = p.f;
        const n = &f.nodes.items[id];
        const cs = n.cs;
        if (n.kind != .anon_text and cs.display == .none) return;
        if (depth > 256) return;
        const l = f.tree.layout(n.lid);
        var x = ox + l.x;
        var y = oy + l.y;
        var ctx = ctx_in.*;

        if (n.kind != .anon_text) {
            if (localTransform(cs, x, y, l.w, l.h)) |m| {
                if (m.isTranslateOnly() and ctx.plain()) {
                    x += m.e;
                    y += m.f;
                } else {
                    ctx.tf = ctx.tf.mul(m);
                    if (ctx.tf.invert() == null) return;
                }
            }
            const op = cs.opacity;
            if (!(op > 0)) return;
            if (op < 1 or cs.filter.len > 0) {
                // Offscreen group, limited to the subtree's visual bounds when they are known.
                var reg = region(&ctx);
                var blur_reach: u32 = 0;
                for (cs.filter) |fl| switch (fl) {
                    .blur => |r| blur_reach += raster.blurReach(r * tfScale(ctx.tf)),
                    else => {},
                };
                if (ctx.plain()) {
                    if (p.subtreeBounds(id, x, y, 0)) |b| reg = reg.intersect(toIRect(b).expand(2 + blur_reach));
                }
                if (reg.isEmpty()) return;
                if (p.layer_depth >= p.layers.items.len) {
                    const data = p.a.alloc(u8, ctx.dst.data.len) catch return error.OutOfMemory;
                    try p.layers.append(p.a, .{ .width = ctx.dst.width, .height = ctx.dst.height, .data = data });
                }
                const layer = &p.layers.items[p.layer_depth];
                const stride = @as(usize, layer.width) * 4;
                var row: usize = @intCast(reg.y);
                const row_end = row + reg.h;
                while (row < row_end) : (row += 1) {
                    const off = row * stride + @as(usize, @intCast(reg.x)) * 4;
                    @memset(layer.data[off..][0 .. @as(usize, reg.w) * 4], 0);
                }
                const reg_clip = ClipMask.fromRect(reg);
                const lctx: Ctx = .{ .dst = layer, .tf = ctx.tf, .clip = &reg_clip };
                p.layer_depth += 1;
                defer p.layer_depth -= 1;
                try p.paintBox(id, x, y, &lctx, depth);
                var comp = reg_clip;
                if (ctx.clip) |c| comp = raster.clipIntersect(p.a, c.*, comp) catch return error.OutOfMemory;
                if (cs.filter.len > 0) {
                    // Filters run on a copy of the group region.
                    var sub = Pixmap.init(p.a, reg.w, reg.h) catch return error.OutOfMemory;
                    const lsrc = &p.layers.items[p.layer_depth - 1];
                    var ry: usize = 0;
                    while (ry < reg.h) : (ry += 1) {
                        const off = (@as(usize, @intCast(reg.y)) + ry) * stride + @as(usize, @intCast(reg.x)) * 4;
                        @memcpy(sub.data[ry * reg.w * 4 ..][0 .. @as(usize, reg.w) * 4], lsrc.data[off..][0 .. @as(usize, reg.w) * 4]);
                    }
                    try p.applyFilters(&sub, cs, tfScale(ctx.tf));
                    raster.drawPixmap(ctx.dst, &sub, Affine.translate(@floatFromInt(reg.x), @floatFromInt(reg.y)), op, .nearest, &comp);
                    return;
                }
                raster.drawPixmap(ctx.dst, &p.layers.items[p.layer_depth - 1], Affine.identity, op, .nearest, &comp);
                return;
            }
        }
        try p.paintBox(id, x, y, &ctx, depth);
    }

    /// CSS filter functions on a premultiplied pixmap (drop-shadow is not implemented).
    noinline fn applyFilters(p: *Painter, pm: *Pixmap, cs: *const CS, scale: f32) Error!void {
        for (cs.filter) |fl| {
            // colour matrix rows (r, g, b) + offset, applied to straight colour; alpha factor
            var m: [3][4]f32 = .{ .{ 1, 0, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 0, 1, 0 } };
            var alpha: f32 = 1;
            switch (fl) {
                .blur => |r| {
                    raster.blurPixmap(p.a, pm, r * scale) catch return error.OutOfMemory;
                    continue;
                },
                .drop_shadow => continue,
                .opacity => |a| alpha = std.math.clamp(a, 0, 1),
                .brightness => |b| m = .{ .{ b, 0, 0, 0 }, .{ 0, b, 0, 0 }, .{ 0, 0, b, 0 } },
                .contrast => |c| {
                    const o = 0.5 - 0.5 * c;
                    m = .{ .{ c, 0, 0, o }, .{ 0, c, 0, o }, .{ 0, 0, c, o } };
                },
                .invert => |a_in| {
                    const a = std.math.clamp(a_in, 0, 1);
                    const k = 1 - 2 * a;
                    m = .{ .{ k, 0, 0, a }, .{ 0, k, 0, a }, .{ 0, 0, k, a } };
                },
                .grayscale => |a_in| {
                    const t = 1 - std.math.clamp(a_in, 0, 1);
                    m = .{
                        .{ 0.2126 + 0.7874 * t, 0.7152 - 0.7152 * t, 0.0722 - 0.0722 * t, 0 },
                        .{ 0.2126 - 0.2126 * t, 0.7152 + 0.2848 * t, 0.0722 - 0.0722 * t, 0 },
                        .{ 0.2126 - 0.2126 * t, 0.7152 - 0.7152 * t, 0.0722 + 0.9278 * t, 0 },
                    };
                },
                .sepia => |a_in| {
                    const t = 1 - std.math.clamp(a_in, 0, 1);
                    m = .{
                        .{ 0.393 + 0.607 * t, 0.769 - 0.769 * t, 0.189 - 0.189 * t, 0 },
                        .{ 0.349 - 0.349 * t, 0.686 + 0.314 * t, 0.168 - 0.168 * t, 0 },
                        .{ 0.272 - 0.272 * t, 0.534 - 0.534 * t, 0.131 + 0.869 * t, 0 },
                    };
                },
                .saturate => |sv| m = .{
                    .{ 0.213 + 0.787 * sv, 0.715 - 0.715 * sv, 0.072 - 0.072 * sv, 0 },
                    .{ 0.213 - 0.213 * sv, 0.715 + 0.285 * sv, 0.072 - 0.072 * sv, 0 },
                    .{ 0.213 - 0.213 * sv, 0.715 - 0.715 * sv, 0.072 + 0.928 * sv, 0 },
                },
                .hue_rotate => |deg| {
                    const sc = rtypes.sinCos(deg * (std.math.pi / 180.0));
                    const sn = sc[0];
                    const cn = sc[1];
                    m = .{
                        .{ 0.213 + cn * 0.787 - sn * 0.213, 0.715 - cn * 0.715 - sn * 0.715, 0.072 - cn * 0.072 + sn * 0.928, 0 },
                        .{ 0.213 - cn * 0.213 + sn * 0.143, 0.715 + cn * 0.285 + sn * 0.140, 0.072 - cn * 0.072 - sn * 0.283, 0 },
                        .{ 0.213 - cn * 0.213 - sn * 0.787, 0.715 - cn * 0.715 + sn * 0.715, 0.072 + cn * 0.928 + sn * 0.072, 0 },
                    };
                },
            }
            var i: usize = 0;
            const d = pm.data;
            while (i + 4 <= d.len) : (i += 4) {
                const a8 = d[i + 3];
                if (a8 == 0) continue;
                const af = @as(f32, @floatFromInt(a8));
                const inv = 1.0 / af;
                const r0 = @as(f32, @floatFromInt(d[i])) * inv;
                const g0 = @as(f32, @floatFromInt(d[i + 1])) * inv;
                const b0 = @as(f32, @floatFromInt(d[i + 2])) * inv;
                const na = af * alpha;
                inline for (0..3) |k| {
                    const v = std.math.clamp(m[k][0] * r0 + m[k][1] * g0 + m[k][2] * b0 + m[k][3], 0, 1);
                    d[i + k] = @intFromFloat(v * na + 0.5);
                }
                d[i + 3] = @intFromFloat(na + 0.5);
            }
        }
    }

    fn paintBox(p: *Painter, id: u32, x: f32, y: f32, ctx: *const Ctx, depth: u32) Error!void {
        const f = p.f;
        const n = &f.nodes.items[id];
        const cs = n.cs;
        const l = f.tree.layout(n.lid);
        const content_x = x + l.border.left + l.padding.left;
        const content_y = y + l.border.top + l.padding.top;
        const content_w = l.w - l.border.left - l.border.right - l.padding.left - l.padding.right;

        if (n.kind == .anon_text) {
            if (cs.visibility == .visible) try p.paintText(ctx, n, content_x, content_y, content_w);
            return;
        }

        var g: Geom = .{
            .bx = if (ctx.plain()) snapRect(x, y, l.w, l.h) else .{ .x = x, .y = y, .w = l.w, .h = l.h },
            .bw = .{ l.border.top, l.border.right, l.border.bottom, l.border.left },
            .pad = .{ l.padding.top, l.padding.right, l.padding.bottom, l.padding.left },
            .radii = undefined,
            .rounded = false,
            .snapped = ctx.plain(),
        };
        g.radii = resolveRadii(cs, g.bx.w, g.bx.h);
        g.rounded = hasRadii(g.radii);

        if (cs.visibility == .visible) {
            if (cs.box_shadow.len > 0) try p.paintOuterShadows(ctx, cs, &g);
            try p.paintBackground(ctx, cs, &g);
            if (cs.box_shadow.len > 0) try p.paintInsetShadows(ctx, cs, &g);
            try p.paintBorder(ctx, cs, &g);

            switch (n.kind) {
                .text => try p.paintText(ctx, n, content_x, content_y, content_w),
                .image => if (n.img) |pm| {
                    const cr = g.contentRect();
                    if (cr.w > 0 and cr.h > 0) {
                        const iw = n.img_w;
                        const ih = n.img_h;
                        var dw = cr.w;
                        var dh = cr.h;
                        const sx = cr.w / iw;
                        const sy = cr.h / ih;
                        switch (cs.object_fit) {
                            .fill => {},
                            .contain => {
                                const s = @min(sx, sy);
                                dw = iw * s;
                                dh = ih * s;
                            },
                            .cover => {
                                const s = @max(sx, sy);
                                dw = iw * s;
                                dh = ih * s;
                            },
                            .none => {
                                dw = iw;
                                dh = ih;
                            },
                            .scale_down => {
                                const s = @min(1, @min(sx, sy));
                                dw = iw * s;
                                dh = ih * s;
                            },
                        }
                        const dx = cr.x + cs.object_position[0].px + cs.object_position[0].pct * (cr.w - dw);
                        const dy = cr.y + cs.object_position[1].px + cs.object_position[1].pct * (cr.h - dh);
                        const crad = g.contentRadii();
                        const overflow = dx < cr.x or dy < cr.y or dx + dw > cr.x + cr.w or dy + dh > cr.y + cr.h;
                        if (crad != null or overflow) {
                            var c2 = ctx.*;
                            c2.clip = try p.makeClip(ctx, cr, crad);
                            p.drawImage(&c2, pm, .{ .x = dx, .y = dy, .w = dw, .h = dh });
                        } else p.drawImage(ctx, pm, .{ .x = dx, .y = dy, .w = dw, .h = dh });
                    }
                },
                else => {},
            }
        }

        if (n.first_child == none) return;
        var cctx = ctx.*;
        if (cs.overflow_x != .visible or cs.overflow_y != .visible) {
            cctx.clip = try p.makeClip(ctx, g.padRect(), g.padRadii());
            if (cctx.clip.?.bounds.isEmpty()) return;
        }

        // Paint order: negative z-index, in-flow, positioned / z-index 0, positive z-index.
        var special = false;
        var c = n.first_child;
        while (c != none) : (c = f.nodes.items[c].next) {
            const ccs = f.nodes.items[c].cs;
            if (f.nodes.items[c].kind != .anon_text and (ccs.z_index != null or ccs.position != .static)) special = true;
        }
        if (!special) {
            c = n.first_child;
            while (c != none) : (c = f.nodes.items[c].next) try p.paintNode(c, x, y, &cctx, depth + 1);
            return;
        }
        const Item = struct { id: u32, key: i64 };
        var items: std.ArrayList(Item) = .empty;
        c = n.first_child;
        var seq: i64 = 0;
        while (c != none) : (c = f.nodes.items[c].next) {
            const cn = &f.nodes.items[c];
            var layer: i64 = 0;
            var z: i64 = 0;
            if (cn.kind != .anon_text) {
                z = cn.cs.z_index orelse 0;
                if (z < 0) {
                    layer = -1;
                } else if (z > 0) {
                    layer = 2;
                } else if (cn.cs.position != .static or cn.cs.z_index != null) layer = 1;
            }
            const zc = std.math.clamp(z, -1000000, 1000000);
            try items.append(p.a, .{ .id = c, .key = (layer * 4000000 + zc) * 1000000 + seq });
            seq += 1;
        }
        var i: usize = 1;
        while (i < items.items.len) : (i += 1) {
            const it = items.items[i];
            var j = i;
            while (j > 0 and items.items[j - 1].key > it.key) : (j -= 1) items.items[j] = items.items[j - 1];
            items.items[j] = it;
        }
        for (items.items) |it| try p.paintNode(it.id, x, y, &cctx, depth + 1);
    }
};

pub fn paintFrame(f: *Frame, pm: *Pixmap) Error!void {
    var p: Painter = .{ .f = f, .a = f.a };
    const ctx: Ctx = .{ .dst = pm };
    try p.paintNode(f.root, 0, 0, &ctx, 0);
}
