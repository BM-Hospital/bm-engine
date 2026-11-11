//! Pixmap compositing (`drawPixmap`) and high-quality resampling (`resample`).
const std = @import("std");
const types = @import("types.zig");
const paint = @import("paint.zig");
const Affine = types.Affine;
const IRect = types.IRect;
const Pixmap = types.Pixmap;
const ClipMask = types.ClipMask;
const Filter = types.Filter;
const clampF = types.clampF;
const Allocator = std.mem.Allocator;

fn isSmallInt(v: f32) bool {
    return @abs(v) < 1.0e9 and @floor(v) == v;
}

/// Source-over composite of the whole `src` pixmap; `transform` maps src pixel space to dst
/// pixel space. `src` must not alias `dst`.
///
/// * integer translation: exact texel copy/blend (any filter);
/// * scale + translate: bilinear (8.8 fixed point, texel centres, edge clamped) with exact-area
///   AA on the fractional destination edges;
/// * general affine: same sampling, edges anti-aliased with an analytic per-edge coverage
///   approximation.
/// Minification is NOT prefiltered here: when the scale is below ~0.5 call `resample` first.
pub fn drawPixmap(dst: *Pixmap, src: *const Pixmap, transform: Affine, opacity: f32, filter: Filter, clip: ?*const ClipMask) void {
    if (!src.isValid() or src.width == 0 or src.height == 0) return;
    if (src.width > (1 << 24) or src.height > (1 << 24)) return;
    const r = paint.clipRegion(dst, clip);
    if (r.isEmpty() or !transform.isFinite()) return;
    const op: u32 = @intFromFloat(clampF(opacity, 0, 1) * 255 + 0.5);
    if (op == 0) return;

    if (transform.isTranslateOnly() and isSmallInt(transform.e) and isSmallInt(transform.f)) {
        const tx: i32 = @intFromFloat(transform.e);
        const ty: i32 = @intFromFloat(transform.f);
        const sr: IRect = .{ .x = tx, .y = ty, .w = src.width, .h = src.height };
        const reg = r.intersect(sr);
        if (reg.isEmpty()) return;
        const clip_data: ?[]const u8 = if (clip) |c| c.data else null;
        const sp: paint.ConstPxPtr = @ptrCast(src.data.ptr);
        var y = reg.y;
        const y1: i32 = @intCast(reg.bottom());
        while (y < y1) : (y += 1) {
            const sy: usize = @intCast(@as(i64, y) - ty);
            const sx: usize = @intCast(@as(i64, reg.x) - tx);
            const s = sp + sy * src.width + sx;
            const d = paint.dstRow(dst, reg.x, y);
            if (clip_data) |cd| {
                const crow = paint.covRow(cd, clip.?.bounds, reg.x, y);
                var buf: [paint.CH]u8 = undefined;
                var off: usize = 0;
                while (off < reg.w) : (off += paint.CH) {
                    const m = @min(paint.CH, reg.w - off);
                    var cp: [*]const u8 = crow + off;
                    if (op != 255) {
                        for (0..m) |i| buf[i] = @intCast(types.div255(@as(u32, cp[i]) * op));
                        cp = &buf;
                    }
                    paint.blendPixels(d + off, s + off, m, cp, 255);
                }
            } else {
                paint.blendPixels(d, s, reg.w, null, op);
            }
        }
        return;
    }

    const inv = transform.invert() orelse return;
    var sh: paint.Shader = undefined;
    const img_paint: types.Paint = .{ .image = .{ .pixmap = src, .transform = inv, .filter = filter, .extend = .pad, .opacity = opacity } };
    sh.init(&img_paint);
    if (sh.kind == .none) return;
    const wf: f32 = @floatFromInt(src.width);
    const hf: f32 = @floatFromInt(src.height);

    if (transform.b == 0 and transform.c == 0) {
        const xa = transform.e;
        const xb = transform.e + transform.a * wf;
        const ya = transform.f;
        const yb = transform.f + transform.d * hf;
        paint.fillRectShader(dst, .{
            .x = @min(xa, xb),
            .y = @min(ya, yb),
            .w = @abs(xb - xa),
            .h = @abs(yb - ya),
        }, &sh, clip);
        return;
    }

    // General affine: per-pixel analytic edge coverage.
    var minx: f32 = std.math.floatMax(f32);
    var miny: f32 = std.math.floatMax(f32);
    var maxx: f32 = -std.math.floatMax(f32);
    var maxy: f32 = -std.math.floatMax(f32);
    const corners = [4][2]f32{ .{ 0, 0 }, .{ wf, 0 }, .{ wf, hf }, .{ 0, hf } };
    for (corners) |c| {
        const p = transform.apply(.{ .x = c[0], .y = c[1] });
        minx = @min(minx, p.x);
        miny = @min(miny, p.y);
        maxx = @max(maxx, p.x);
        maxy = @max(maxy, p.y);
    }
    const rx0: f32 = @floatFromInt(r.x);
    const ry0: f32 = @floatFromInt(r.y);
    const rx1: f32 = @floatFromInt(r.right());
    const ry1: f32 = @floatFromInt(r.bottom());
    const bx0 = clampF(@floor(minx) - 1, rx0, rx1);
    const bx1 = clampF(@ceil(maxx) + 1, rx0, rx1);
    const iy0: i32 = @intFromFloat(clampF(@floor(miny) - 1, ry0, ry1));
    const iy1: i32 = @intFromFloat(clampF(@ceil(maxy) + 1, ry0, ry1));
    if (!(bx1 > bx0)) return;
    // device px per image unit along each edge normal
    const su = 1.0 / @sqrt(inv.a * inv.a + inv.c * inv.c);
    const sv = 1.0 / @sqrt(inv.b * inv.b + inv.d * inv.d);
    if (!std.math.isFinite(su) or !std.math.isFinite(sv)) return;
    var y = iy0;
    while (y < iy1) : (y += 1) {
        const yc: f32 = @as(f32, @floatFromInt(y)) + 0.5;
        const ub = inv.c * yc + inv.e;
        const vb = inv.d * yc + inv.f;
        var xa = bx0;
        var xb = bx1;
        if (!narrow(ub, inv.a, -0.5 / su, wf + 0.5 / su, &xa, &xb)) continue;
        if (!narrow(vb, inv.b, -0.5 / sv, hf + 0.5 / sv, &xa, &xb)) continue;
        const x0: i32 = @intFromFloat(clampF(@floor(xa), bx0, bx1));
        const x1: i32 = @intFromFloat(clampF(@ceil(xb), bx0, bx1));
        var x = x0;
        var ebuf: [paint.CH]u8 = undefined;
        while (x < x1) : (x += paint.CH) {
            const m: usize = @intCast(@min(paint.CH, x1 - x));
            for (0..m) |i| {
                const xc = @as(f32, @floatFromInt(x)) + types.fi32(i) + 0.5;
                const u = ub + inv.a * xc;
                const v = vb + inv.b * xc;
                const cx = clampF(u * su + 0.5, 0, 1) + clampF((wf - u) * su + 0.5, 0, 1) - 1;
                const cy = clampF(v * sv + 0.5, 0, 1) + clampF((hf - v) * sv + 0.5, 0, 1) - 1;
                ebuf[i] = @intFromFloat(clampF(cx, 0, 1) * clampF(cy, 0, 1) * 255 + 0.5);
            }
            const crow: ?[*]const u8 = if (clip) |c| (if (c.data) |cd| paint.covRow(cd, c.bounds, x, y) else null) else null;
            paint.blendSpan(&sh, paint.dstRow(dst, x, y), x, y, m, &ebuf, crow, 255);
        }
    }
}

/// Narrows [xa, xb] (pixel-centre x) to where lo <= base + step*x <= hi. False when empty.
fn narrow(base: f32, step: f32, lo: f32, hi: f32, xa: *f32, xb: *f32) bool {
    if (@abs(step) < 1e-12) return base >= lo and base <= hi;
    var t0 = (lo - base) / step;
    var t1 = (hi - base) / step;
    if (t0 > t1) {
        const t = t0;
        t0 = t1;
        t1 = t;
    }
    xa.* = @max(xa.*, t0 - 1);
    xb.* = @min(xb.*, t1 + 1);
    return xb.* > xa.*;
}

// ---- resample ---------------------------------------------------------------------------

/// Catmull-Rom spline (B = 0, C = 0.5), written like image-rs / takumi.
fn catmullRom(x: f32) f32 {
    const a = @abs(x);
    const k = if (a < 1.0)
        9.0 * (a * a * a) - 15.0 * (a * a) + 6.0
    else if (a < 2.0)
        -3.0 * (a * a * a) + 15.0 * (a * a) - 24.0 * a + 12.0
    else
        0.0;
    return k / 6.0;
}

const Window = struct { left: u32, count: u32 };

/// Source window + normalised weights for one output index (image-rs `resize` semantics).
fn sampleWindow(out: u32, ratio: f32, sratio: f32, source_len: u32, weights: []f32) Window {
    const input = (@as(f32, @floatFromInt(out)) + 0.5) * ratio;
    const src_support = 2.0 * sratio;
    const last: f32 = @floatFromInt(source_len - 1);
    const left: u32 = @intFromFloat(clampF(@floor(input - src_support), 0, last));
    const right_f = clampF(@ceil(input + src_support), @floatFromInt(left + 1), @floatFromInt(source_len));
    var count: u32 = @as(u32, @intFromFloat(right_f)) - left;
    count = @min(count, @as(u32, @intCast(weights.len)));
    const center = input - 0.5;
    var sum: f32 = 0;
    for (0..count) |i| {
        const w = catmullRom((@as(f32, @floatFromInt(left + @as(u32, @intCast(i)))) - center) / sratio);
        weights[i] = w;
        sum += w;
    }
    for (weights[0..count]) |*w| w.* /= sum;
    return .{ .left = left, .count = count };
}

fn maxTaps(sratio: f32, source_len: u32) usize {
    const t: usize = @intFromFloat(clampF(@ceil(4.0 * sratio) + 2, 1, 1.0e9));
    return @min(t, source_len);
}

/// Separable Catmull-Rom resize of a premultiplied RGBA pixmap, numerically following
/// `image::imageops::resize(.., CatmullRom)` as used by takumi (vertical pass into f32, then
/// horizontal, `round(clamp(v, 0, 255))`). The kernel is widened by the scale factor when
/// downscaling, so strong minification does not alias. Colour channels are additionally
/// clamped to alpha so the result is always valid premultiplied data.
/// Scratch memory and the result are allocated from `alloc`; the caller owns the result.
pub fn resample(alloc: Allocator, src: *const Pixmap, new_w: u32, new_h: u32) !Pixmap {
    var out = try Pixmap.init(alloc, new_w, new_h);
    errdefer out.deinit(alloc);
    if (new_w == 0 or new_h == 0 or !src.isValid() or src.width == 0 or src.height == 0) return out;
    const sw = src.width;
    const sh = src.height;
    if (sw > (1 << 24) or sh > (1 << 24) or new_w > (1 << 24) or new_h > (1 << 24)) return error.OutOfMemory;

    const hratio = @as(f32, @floatFromInt(sw)) / @as(f32, @floatFromInt(new_w));
    const hs = @max(hratio, 1.0);
    const vratio = @as(f32, @floatFromInt(sh)) / @as(f32, @floatFromInt(new_h));
    const vs = @max(vratio, 1.0);
    const htaps = maxTaps(hs, sw);
    const vtaps = maxTaps(vs, sh);

    const hwin = try alloc.alloc(Window, new_w);
    defer alloc.free(hwin);
    const hw_len = std.math.mul(usize, htaps, new_w) catch return error.OutOfMemory;
    const hweights = try alloc.alloc(f32, hw_len);
    defer alloc.free(hweights);
    const vweights = try alloc.alloc(f32, vtaps);
    defer alloc.free(vweights);
    const row_len = @as(usize, sw) * 4;
    const inter = try alloc.alloc(f32, row_len);
    defer alloc.free(inter);

    for (hwin, 0..) |*hwp, ox| {
        hwp.* = sampleWindow(@intCast(ox), hratio, hs, sw, hweights[ox * htaps ..][0..htaps]);
    }

    var oy: u32 = 0;
    while (oy < new_h) : (oy += 1) {
        const vw = sampleWindow(oy, vratio, vs, sh, vweights);
        @memset(inter, 0);
        for (vweights[0..vw.count], 0..) |weight, off| {
            const row = src.data[(@as(usize, vw.left) + off) * row_len ..][0..row_len];
            // explicit 8-wide SIMD (same per-element operation order as the scalar loop)
            const VF8 = @Vector(8, f32);
            const wv: VF8 = @splat(weight);
            var k: usize = 0;
            while (k + 8 <= row_len) : (k += 8) {
                const bytes: @Vector(8, u8) = row[k..][0..8].*;
                const ints: @Vector(8, i32) = bytes;
                const acc: VF8 = inter[k..][0..8].*;
                inter[k..][0..8].* = acc + @as(VF8, @floatFromInt(ints)) * wv;
            }
            while (k < row_len) : (k += 1) inter[k] += @as(f32, @floatFromInt(row[k])) * weight;
        }
        const orow = out.data[@as(usize, oy) * new_w * 4 ..][0 .. @as(usize, new_w) * 4];
        for (hwin, 0..) |hwv, ox| {
            var t: @Vector(4, f32) = @splat(0);
            const ws = hweights[ox * htaps ..][0..hwv.count];
            for (ws, 0..) |weight, off| {
                const s: @Vector(4, f32) = inter[(hwv.left + off) * 4 ..][0..4].*;
                t += s * @as(@Vector(4, f32), @splat(weight));
            }
            // round(clamp(t, 0, 255)): NaN-safe clamp, then floor(v + 0.5) through the 2^23
            // mantissa trick (no float -> int instruction, no libm round)
            const VF4 = @Vector(4, f32);
            const zero: VF4 = @splat(0);
            const top: VF4 = @splat(255);
            const cl = @select(f32, t > zero, @select(f32, t < top, t, top), zero);
            const bits: @Vector(4, u32) = @bitCast(@floor(cl + @as(VF4, @splat(0.5))) + @as(VF4, @splat(8388608.0)));
            var px: [4]u8 = @as(@Vector(4, u8), @truncate(bits));
            px[0] = @min(px[0], px[3]);
            px[1] = @min(px[1], px[3]);
            px[2] = @min(px[2], px[3]);
            orow[ox * 4 ..][0..4].* = px;
        }
    }
    return out;
}
