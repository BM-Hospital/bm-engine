//! Effects for the painter (`paint.zig`): clip-path shapes, mask-image, drop-shadow, backdrop-filter.
//! Mirrors takumi's effect pipeline (takumi-raster `stacking_context.rs`, `filter.rs`,
//! takumi-core `layout/clip.rs`).
const std = @import("std");
const render = @import("render.zig");
const style = @import("style/style.zig");
const computed = @import("style/computed.zig");
const raster = @import("raster/raster.zig");
const pm = @import("paint.zig");
const svg_path = if (pm.enable_svg) @import("svg/pathdata.zig") else struct {};

const Painter = pm.Painter;
const Ctx = pm.Ctx;
const Geom = pm.Geom;
const Radii = pm.Radii;
const CS = render.CS;
const Rect = raster.Rect;
const IRect = raster.IRect;
const Affine = raster.Affine;
const Pixmap = raster.Pixmap;
const ClipMask = raster.ClipMask;
const Error = render.Error;

pub fn hasMask(cs: *const CS) bool {
    if (comptime !pm.enable_effects) return false;
    for (cs.mask_image) |im| if (im != .none) return true;
    return false;
}

/// takumi `EffectKind::Group` / `Filter`: the element paints into an offscreen layer.
pub fn needsGroup(cs: *const CS) bool {
    if (comptime !pm.enable_effects) return cs.opacity < 1 or cs.filter.len > 0;
    return cs.opacity < 1 or cs.filter.len > 0 or cs.backdrop_filter.len > 0 or cs.mix_blend_mode != .normal or
        cs.isolation == .isolate or cs.clip_path != null or hasMask(cs);
}

pub fn blendMode(m: computed.BlendMode) raster.BlendMode {
    return switch (m) {
        .normal, .plus_darker => .normal,
        .multiply => .multiply,
        .screen => .screen,
        .overlay => .overlay,
        .darken => .darken,
        .lighten => .lighten,
        .color_dodge => .color_dodge,
        .color_burn => .color_burn,
        .hard_light => .hard_light,
        .soft_light => .soft_light,
        .difference => .difference,
        .exclusion => .exclusion,
        .hue => .hue,
        .saturation => .saturation,
        .color => .color,
        .luminosity => .luminosity,
        .plus_lighter => .plus_lighter,
    };
}

/// clip ∩ mask with takumi's mask-stack rounding (`(l * r + 128) >> 8`); result bounds =
/// clip.bounds ∩ mask.bounds, allocated in the arena.
pub noinline fn clipAnd(p: *Painter, clip: ClipMask, mask: *const raster.Mask) Error!ClipMask {
    const b = clip.bounds.intersect(mask.bounds);
    if (b.isEmpty()) return ClipMask.fromRect(IRect.empty);
    const out = p.a.alloc(u8, @as(usize, b.w) * b.h) catch return error.OutOfMemory;
    var yy: u32 = 0;
    while (yy < b.h) : (yy += 1) {
        const mo = (@as(usize, @intCast(@as(i64, b.y) - mask.bounds.y)) + yy) * mask.bounds.w + @as(usize, @intCast(@as(i64, b.x) - mask.bounds.x));
        const mrow = mask.data[mo..][0..b.w];
        const orow = out[@as(usize, yy) * b.w ..][0..b.w];
        if (clip.data) |cd| {
            const co = (@as(usize, @intCast(@as(i64, b.y) - clip.bounds.y)) + yy) * clip.bounds.w + @as(usize, @intCast(@as(i64, b.x) - clip.bounds.x));
            const crow = cd[co..][0..b.w];
            for (orow, mrow, crow) |*o, l, r| {
                o.* = if (l == 255) r else if (r == 255) l else @intCast((@as(u32, l) * r + 128) >> 8);
            }
        } else @memcpy(orow, mrow);
    }
    return .{ .bounds = b, .data = out };
}

fn shapeRadius(r: computed.ShapeRadius, c: f32, full: f32) f32 {
    return switch (r) {
        .closest_side => @min(@abs(c), @abs(full - c)),
        .farthest_side => @max(@abs(c), @abs(full - c)),
        .lp => |v| v.resolve(full),
    };
}

fn ellipsePath(p: *Painter, cx: f32, cy: f32, rx: f32, ry: f32) Error!void {
    if (!(rx > 0) or !(ry > 0)) return;
    const k: f32 = 0.552_284_8;
    const ox = rx * k;
    const oy = ry * k;
    const a = p.a;
    const path = &p.path;
    path.moveTo(a, cx + rx, cy) catch return error.OutOfMemory;
    path.cubicTo(a, cx + rx, cy + oy, cx + ox, cy + ry, cx, cy + ry) catch return error.OutOfMemory;
    path.cubicTo(a, cx - ox, cy + ry, cx - rx, cy + oy, cx - rx, cy) catch return error.OutOfMemory;
    path.cubicTo(a, cx - rx, cy - oy, cx - ox, cy - ry, cx, cy - ry) catch return error.OutOfMemory;
    path.cubicTo(a, cx + ox, cy - ry, cx + rx, cy - oy, cx + rx, cy) catch return error.OutOfMemory;
    path.close(a) catch return error.OutOfMemory;
}

/// AA coverage of `clip-path` in device space within `reg`; null = no clipping (`url()`).
/// `bx` is the unsnapped border box (takumi's reference box).
pub noinline fn clipPathMask(p: *Painter, ctx: *const Ctx, cp: *const computed.ClipPath, cs: *const CS, bx: Rect, g: *const Geom, reg: IRect) Error!?raster.Mask {
    var box = bx;
    switch (cp.box) {
        .padding_box => box = g.padRect(),
        .content_box => box = g.contentRect(),
        else => {},
    }
    const w = box.w;
    const h = box.h;
    const path = &p.path;
    path.reset();
    var rule: raster.FillRule = .nonzero;
    var tf = ctx.tf;
    const shape = cp.shape orelse {
        if (cp.url.len > 0) return null;
        var rr = pm.resolveRadiiRaw(cs, w, h);
        pm.scaleRadii(&rr, w, h);
        try p.setRRect(box, if (pm.hasAnyRadius(rr)) rr else null);
        return p.rast().rasterize(p.a, path, tf, .nonzero, reg) catch return error.OutOfMemory;
    };
    switch (shape) {
        .inset => |in| {
            const t = in.sides[0].resolve(h);
            const r = in.sides[1].resolve(w);
            const b = in.sides[2].resolve(h);
            const l = in.sides[3].resolve(w);
            const rc: Rect = .{ .x = box.x + l, .y = box.y + t, .w = w - l - r, .h = h - t - b };
            if (rc.w > 0 and rc.h > 0) {
                var rr: Radii = undefined;
                for (0..4) |i| {
                    rr[i] = .{ @max(0, in.radius[i][0].resolve(w)), @max(0, in.radius[i][1].resolve(h)) };
                    if (rr[i][0] <= 0 or rr[i][1] <= 0) rr[i] = .{ 0, 0 };
                }
                pm.scaleRadii(&rr, rc.w, rc.h);
                try p.setRRect(rc, if (pm.hasAnyRadius(rr)) rr else null);
            }
        },
        .circle => |c| {
            const cx = c.at[0].resolve(w);
            const cy = c.at[1].resolve(h);
            const r: f32 = switch (c.r) {
                .closest_side => @min(@min(@abs(cx), @abs(w - cx)), @min(@abs(cy), @abs(h - cy))),
                .farthest_side => @max(@max(@abs(cx), @abs(w - cx)), @max(@abs(cy), @abs(h - cy))),
                .lp => |v| v.resolve(@sqrt(w * w + h * h) / std.math.sqrt2),
            };
            try ellipsePath(p, box.x + cx, box.y + cy, r, r);
        },
        .ellipse => |e| {
            const cx = e.at[0].resolve(w);
            const cy = e.at[1].resolve(h);
            try ellipsePath(p, box.x + cx, box.y + cy, shapeRadius(e.rx, cx, w), shapeRadius(e.ry, cy, h));
        },
        .polygon => |pg| {
            rule = if (pg.rule == .evenodd) .evenodd else .nonzero;
            for (pg.points, 0..) |q, i| {
                const x = box.x + q[0].resolve(w);
                const y = box.y + q[1].resolve(h);
                if (i == 0) {
                    path.moveTo(p.a, x, y) catch return error.OutOfMemory;
                } else path.lineTo(p.a, x, y) catch return error.OutOfMemory;
            }
            if (pg.points.len > 0) path.close(p.a) catch return error.OutOfMemory;
        },
        .path => |pd| {
            rule = if (pd.rule == .evenodd) .evenodd else .nonzero;
            if (comptime pm.enable_svg) {
                svg_path.parse(p.a, pd.d, path, null) catch return error.OutOfMemory;
                const dpr = p.f.opts.dpr;
                tf = tf.mul(Affine.translate(box.x, box.y)).mul(Affine.scale(dpr, dpr));
            }
        },
    }
    if (path.isEmpty()) return raster.Mask.empty;
    return p.rast().rasterize(p.a, path, tf, rule, reg) catch return error.OutOfMemory;
}

/// Coverage of the element's `mask-image` layers (source-over, bottom layer = last listed) within
/// `reg`: the alpha (or luminance for `mask-mode: luminance`) of the rendered layers.
pub noinline fn maskImageMask(p: *Painter, ctx: *const Ctx, cs: *const CS, g: *const Geom, reg: IRect) Error!raster.Mask {
    const mreg = Painter.devBounds(ctx.tf, g.bx).intersect(reg);
    if (mreg.isEmpty()) return raster.Mask.empty;
    const layer = try p.beginLayer(ctx, mreg);
    defer p.endLayer();
    const lclip = ClipMask.fromRect(mreg);
    const lctx: Ctx = .{ .dst = layer, .tf = ctx.tf, .clip = &lclip };
    var luma = false;
    var i = cs.mask_image.len;
    while (i > 0) {
        i -= 1;
        const ml = cs.maskLayer(i);
        if (ml.image == .none) continue;
        if (ml.mode == .luminance) luma = true;
        try p.paintBgLayer(&lctx, cs, g, &.{ .image = ml.image, .size = ml.size, .position = ml.position, .repeat = ml.repeat, .clip = ml.clip, .origin = ml.origin }, false);
    }
    var m = raster.Mask.init(p.a, mreg) catch return error.OutOfMemory;
    const stride = @as(usize, layer.width) * 4;
    var yy: u32 = 0;
    while (yy < mreg.h) : (yy += 1) {
        const off = (@as(usize, @intCast(mreg.y)) + yy) * stride + @as(usize, @intCast(mreg.x)) * 4;
        const srow = layer.data[off..][0 .. @as(usize, mreg.w) * 4];
        const drow = m.data[@as(usize, yy) * mreg.w ..][0..mreg.w];
        for (drow, 0..) |*d, x| {
            const px = srow[x * 4 ..][0..4];
            if (!luma or px[3] == 0) {
                d.* = px[3];
            } else {
                // straight-colour luminance times alpha == luminance of the premultiplied colour
                const v = (0.2126 * @as(f32, @floatFromInt(px[0])) + 0.7152 * @as(f32, @floatFromInt(px[1])) + 0.0722 * @as(f32, @floatFromInt(px[2])));
                d.* = @intFromFloat(std.math.clamp(@ceil(v), 0, 255));
            }
        }
    }
    return m;
}

/// `filter: drop-shadow()` on a premultiplied pixmap (takumi `filter.rs`): the alpha, tinted,
/// offset by floor(x, y) and blurred with sigma = blur, composited UNDER the existing pixels.
pub noinline fn dropShadow(p: *Painter, px: *Pixmap, sh: style.Shadow, col: style.Color, scale: f32) Error!void {
    if (col.a == 0 or px.width == 0 or px.height == 0) return;
    const w: usize = px.width;
    const h: usize = px.height;
    const ox: i64 = @intFromFloat(std.math.clamp(@floor(sh.x * scale), -1.0e6, 1.0e6));
    const oy: i64 = @intFromFloat(std.math.clamp(@floor(sh.y * scale), -1.0e6, 1.0e6));
    var m = raster.Mask.init(p.a, .{ .x = 0, .y = 0, .w = px.width, .h = px.height }) catch return error.OutOfMemory;
    @memset(m.data, 0);
    var any = false;
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const ty = @as(i64, @intCast(y)) + oy;
        if (ty < 0 or ty >= h) continue;
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const a = px.data[(y * w + x) * 4 + 3];
            if (a == 0) continue;
            const tx = @as(i64, @intCast(x)) + ox;
            if (tx < 0 or tx >= w) continue;
            m.data[@as(usize, @intCast(ty)) * w + @as(usize, @intCast(tx))] = @intCast(raster.div255(@as(u32, col.a) * a));
            any = true;
        }
    }
    if (!any) return;
    raster.blurMaskClipped(p.a, &m, sh.blur * scale, .{ .x = 0, .y = 0, .w = px.width, .h = px.height }) catch return error.OutOfMemory;
    const mb = m.bounds;
    const cc = [3]u32{ col.r, col.g, col.b };
    var yy: u32 = 0;
    while (yy < mb.h) : (yy += 1) {
        const dy: usize = @intCast(@as(i64, mb.y) + yy);
        var xx: u32 = 0;
        while (xx < mb.w) : (xx += 1) {
            const sa: u32 = m.data[@as(usize, yy) * mb.w + xx];
            if (sa == 0) continue;
            const d = px.data[(dy * w + @as(usize, @intCast(@as(i64, mb.x) + xx))) * 4 ..][0..4];
            if (d[3] == 255) continue;
            const u: u32 = 255 - @as(u32, d[3]);
            inline for (0..3) |k| d[k] = @intCast(@min(255, @as(u32, d[k]) + raster.div255(raster.div255(cc[k] * sa) * u)));
            d[3] = @intCast(@min(255, @as(u32, d[3]) + raster.div255(sa * u)));
        }
    }
}

/// `backdrop-filter`: the part of `ctx.dst` under the (rounded) border box, filtered with
/// mirrored edges and masked by the box shape, written into the (transparent) `layer`.
pub noinline fn backdrop(p: *Painter, ctx: *const Ctx, cs: *const CS, g: *const Geom, layer: *Pixmap, reg: IRect) Error!void {
    var only_shadow = true;
    var pad: u32 = 0;
    const scale = Painter.tfScale(ctx.tf);
    for (cs.backdrop_filter) |fl| switch (fl) {
        .drop_shadow => {},
        .blur => |r| {
            only_shadow = false;
            pad = @max(pad, @as(u32, @intFromFloat(std.math.clamp(@ceil(3 * r * scale), 0, 4096))));
        },
        else => only_shadow = false,
    };
    if (only_shadow) return;
    const mask = try p.rrectMask(ctx, g.bx, g.outerRadii(), reg.intersect(ctx.dst.bounds()));
    const r = mask.bounds;
    if (r.isEmpty()) return;
    pad = @min(pad, @max(ctx.dst.width, ctx.dst.height));
    while (pad > 0 and (@as(u64, r.w) + 2 * pad) * (@as(u64, r.h) + 2 * pad) > (16 << 20)) pad /= 2;
    const bw: u32 = r.w + 2 * pad;
    const bh: u32 = r.h + 2 * pad;
    var buf = Pixmap.init(p.a, bw, bh) catch return error.OutOfMemory;
    const sstride = @as(usize, ctx.dst.width) * 4;
    const xmap = p.a.alloc(u32, bw) catch return error.OutOfMemory;
    for (xmap, 0..) |*v, i| v.* = mirror(@as(i64, @intCast(i)) - pad, r.w);
    var y: u32 = 0;
    while (y < bh) : (y += 1) {
        const sy: usize = @as(usize, @intCast(r.y)) + mirror(@as(i64, y) - pad, r.h);
        const srow = ctx.dst.data[sy * sstride + @as(usize, @intCast(r.x)) * 4 ..];
        const drow = buf.data[@as(usize, y) * bw * 4 ..][0 .. @as(usize, bw) * 4];
        for (xmap, 0..) |sx, x| drow[x * 4 ..][0..4].* = srow[@as(usize, sx) * 4 ..][0..4].*;
    }
    try p.applyFilters(&buf, cs.backdrop_filter, cs, scale, true);
    y = 0;
    while (y < r.h) : (y += 1) {
        const srow = buf.data[(@as(usize, y) + pad) * bw * 4 + @as(usize, pad) * 4 ..];
        const drow = layer.data[(@as(usize, @intCast(r.y)) + y) * sstride + @as(usize, @intCast(r.x)) * 4 ..];
        const mrow = mask.data[@as(usize, y) * r.w ..][0..r.w];
        for (mrow, 0..) |mv, x| {
            if (mv == 0) continue;
            inline for (0..4) |k| drow[x * 4 + k] = @intCast(raster.div255(@as(u32, srow[x * 4 + k]) * mv));
        }
    }
}

fn mirror(i: i64, n: u32) u32 {
    const two: i64 = 2 * @as(i64, n);
    const o = @mod(i, two);
    return @intCast(if (o >= n) two - 1 - o else o);
}
