//! Layer compositing with CSS `mix-blend-mode` (`drawPixmapBlend`) and mask application
//! (`maskMultiply*`, `maskFromPixmap`) for CSS `mask-image` / `clip-path` / SVG `<mask>`.
//!
//! What takumi 2.20 does when a group layer is composited with a blend mode (takumi-raster
//! `canvas.rs: composite_subcanvas`; verified against the wasm oracle, see
//! bench/probe/raster/blend_oracle.mjs), and what is mirrored here:
//! * the layer is first scaled by the clip coverage (`clip_layer`, takumi `mul_div_255`);
//! * `normal`: source-over. Here: exactly `image.drawPixmap` with an integer translation
//!   (exact div255 rounding, opacity folded into the coverage) - NOT takumi's rounding;
//! * `color-dodge`, `color-burn`: the layer is scaled by `round(opacity * 255)` and blended
//!   per pixel by `blend.rs: blend_premultiplied_pixel` (demultiply, integer blend in
//!   straight u8, premultiply). Mirrored exactly, including takumi's `div_255` rounding;
//! * every other mode goes to tiny-skia `draw_pixmap`, i.e. its f32 "highp" pipeline
//!   (the nearest-neighbour `gather` stage has no lowp version): source * f32 opacity,
//!   Skia's premultiplied blend formulas, `round(clamp(v, 0, 1) * 255)` on store.
//!   `floatPixel` is that pipeline: the same f32 operations in the same order, written
//!   branch-free on a 4-lane vector (r, g, b, a), so the results are bit-identical to takumi
//!   with and without opacity (17/17 modes in the oracle probe);
//! * tiny-skia's `clip_color` tests `mx >= 0` where Skia / W3C ClipColor test `mn >= 0`, so in
//!   the non-separable modes (hue, saturation, color, luminosity) a negative channel is
//!   clamped to 0 instead of being pulled towards the luminance. takumi inherits this; it is
//!   mirrored when `tiny_skia_clip_color` is true (results then differ from browsers by up
//!   to ~170 levels on saturated colours; set it to false for the W3C behaviour).
const std = @import("std");
const types = @import("types.zig");
const paint = @import("paint.zig");
const IRect = types.IRect;
const Pixmap = types.Pixmap;
const Mask = types.Mask;
const ClipMask = types.ClipMask;
const clampF = types.clampF;
const scalePx = types.scalePx;
const div255 = types.div255;
const Allocator = std.mem.Allocator;
const PxPtr = paint.PxPtr;
const ConstPxPtr = paint.ConstPxPtr;

/// true: hue / saturation / color / luminosity match takumi (tiny-skia `clip_color` quirk, see
/// the file header); false: W3C Compositing 1 `ClipColor`.
const tiny_skia_clip_color = true;

/// CSS `mix-blend-mode` values (W3C Compositing and Blending Level 1 + `plus-lighter`).
pub const BlendMode = enum(u8) {
    normal,
    multiply,
    screen,
    overlay,
    darken,
    lighten,
    color_dodge,
    color_burn,
    hard_light,
    soft_light,
    difference,
    exclusion,
    hue,
    saturation,
    color,
    luminosity,
    plus_lighter,
};

/// Composites the whole `src` layer onto `dst` at integer offset (tx, ty) with `opacity` (0..1) and
/// CSS `mix-blend-mode` `mode`, through `clip`. `src` must not alias `dst`.
///
/// Per pixel (premultiplied S, D; alphas sa, da; S and sa already scaled by clip and opacity):
/// `co = S*(1-da) + D*(1-sa) + sa*da*B(Cb, Cs)`, `ao = sa + da - sa*da`; `plus_lighter` is a
/// clamped premultiplied add of all four channels. Rounding follows takumi (file header).
/// `.normal` gives byte-identical results to `image.drawPixmap` with an integer translation.
/// Invalid pixmaps / clip buffers, NaN opacity or opacity < 1/510: nothing is drawn.
pub fn drawPixmapBlend(dst: *Pixmap, src: *const Pixmap, tx: i32, ty: i32, opacity: f32, mode: BlendMode, clip: ?*const ClipMask) void {
    if (!src.isValid() or src.width == 0 or src.height == 0) return;
    if (src.width > (1 << 24) or src.height > (1 << 24)) return;
    const r = paint.clipRegion(dst, clip);
    if (r.isEmpty()) return;
    const opf = clampF(opacity, 0, 1);
    const op: u32 = @intFromFloat(opf * 255 + 0.5);
    if (op == 0) return;
    const reg = r.intersect(.{ .x = tx, .y = ty, .w = src.width, .h = src.height });
    if (reg.isEmpty()) return;
    const clip_data: ?[]const u8 = if (clip) |c| c.data else null;
    const sp: ConstPxPtr = @ptrCast(src.data.ptr);
    const sx: usize = @intCast(@as(i64, reg.x) - tx);
    var y = reg.y;
    const y1: i32 = @intCast(reg.bottom());
    while (y < y1) : (y += 1) {
        const sy: usize = @intCast(@as(i64, y) - ty);
        const s = sp + sy * src.width + sx;
        const d = paint.dstRow(dst, reg.x, y);
        const crow: ?[*]const u8 = if (clip_data) |cd| paint.covRow(cd, clip.?.bounds, reg.x, y) else null;
        if (mode != .normal) {
            blendRow(mode, d, s, reg.w, crow, op, opf);
            continue;
        }
        // same calls as image.drawPixmap (integer-translate branch)
        const cr = crow orelse {
            paint.blendPixels(d, s, reg.w, null, op);
            continue;
        };
        var buf: [paint.CH]u8 = undefined;
        var off: usize = 0;
        while (off < reg.w) : (off += paint.CH) {
            const m = @min(paint.CH, reg.w - off);
            var cp: [*]const u8 = cr + off;
            if (op != 255) {
                for (0..m) |i| buf[i] = @intCast(div255(@as(u32, cp[i]) * op));
                cp = &buf;
            }
            paint.blendPixels(d + off, s + off, m, cp, 255);
        }
    }
}

/// One row of a non-normal mode: `d[i] = blend(s[i] * cov[i] * opacity, d[i])` (`cov` null = 255);
/// `op` = round(opacity * 255), `opf` = opacity.
fn blendRow(mode: BlendMode, d: PxPtr, s: ConstPxPtr, n: usize, cov: ?[*]const u8, op: u32, opf: f32) void {
    switch (mode) {
        .normal => {},
        .color_dodge, .color_burn => dodgeBurnRow(mode == .color_burn, d, s, n, cov, op),
        else => floatRow(mode, d, s, n, cov, if (op == 255) 1 else opf, op == 255),
    }
}

/// takumi `div_255` (`style/math.rs`): `(v + 128 + (v >> 8)) >> 8`; one above the exact
/// rounding for 126 of the byte products.
inline fn tk255(v: u32) u32 {
    return (v + 128 + (v >> 8)) >> 8;
}

/// takumi `blend.rs: scale_premultiplied_pixel` (`tk255` on the four channels at once).
inline fn tkScalePx(p: u32, c: u32) u32 {
    var rb = (p & 0x00FF00FF) * c;
    rb = ((rb + 0x00800080 + ((rb >> 8) & 0x00FF00FF)) >> 8) & 0x00FF00FF;
    var ga = ((p >> 8) & 0x00FF00FF) * c;
    ga = (ga + 0x00800080 + ((ga >> 8) & 0x00FF00FF)) & 0xFF00FF00;
    return rb | ga;
}

/// Layer pixel `i` after takumi's `clip_layer` (scaled by the clip coverage).
inline fn srcPx(s: ConstPxPtr, i: usize, cov: ?[*]const u8) u32 {
    const p = s[i];
    const c: u32 = if (cov) |cp| cp[i] else return p;
    return if (c == 255) p else tkScalePx(p, c);
}

// ---- f32 pipeline (tiny-skia highp formulas) ---------------------------------------------

const F4 = @Vector(4, f32);

inline fn f4(v: f32) F4 {
    return @splat(v);
}

// @select instead of @min/@max: float-vector min/max are very slow in V8
inline fn vmin(a: F4, b: F4) F4 {
    return @select(f32, a < b, a, b);
}

inline fn vmax(a: F4, b: F4) F4 {
    return @select(f32, a > b, a, b);
}

/// tiny-skia highp `gather` / `load_dst`: bytes -> f32 * (1/255), lanes r, g, b, a.
inline fn loadPx(p: u32) F4 {
    const b: @Vector(4, u8) = @bitCast(p);
    return @as(F4, @floatFromInt(@as(@Vector(4, i32), b))) * f4(1.0 / 255.0);
}

// compare-selects (like SSE min/max in tiny-skia); scalar @min/@max on f32 become libcalls
inline fn min3(c: [3]f32) f32 {
    const m = if (c[1] < c[2]) c[1] else c[2];
    return if (c[0] < m) c[0] else m;
}

inline fn max3(c: [3]f32) f32 {
    const m = if (c[1] > c[2]) c[1] else c[2];
    return if (c[0] > m) c[0] else m;
}

inline fn lum(c: [3]f32) f32 {
    return c[0] * 0.30 + c[1] * 0.59 + c[2] * 0.11;
}

inline fn sat(c: [3]f32) f32 {
    return max3(c) - min3(c);
}

/// tiny-skia highp `set_sat`.
fn setSat(c: *[3]f32, sv: f32) void {
    const mn = min3(c.*);
    const mx = max3(c.*);
    const range = mx - mn;
    for (c) |*v| v.* = if (range == 0) 0 else (v.* - mn) * sv / range;
}

/// tiny-skia highp `set_lum` followed by `clip_color(.., a)`.
fn setLumClip(c: *[3]f32, lv: f32, a: f32) void {
    const diff = lv - lum(c.*);
    for (c) |*v| v.* += diff;
    const mn = min3(c.*);
    const mx = max3(c.*);
    const l = lum(c.*);
    const low = if (tiny_skia_clip_color) !(mx >= 0) else mn < 0 and l != mn;
    for (c) |*v| {
        var x = v.*;
        if (low) x = l + (x - l) * l / (l - mn);
        if (mx > a and l != mx) x = l + (x - l) * (a - l) / (mx - l);
        v.* = if (x > 0) x else 0;
    }
}

/// Blend term of tiny-skia's highp `hue` / `saturation` / `color` / `luminosity` stages
/// (premultiplied `s`, `d`); lane 3 is 0.
noinline fn nonSeparable(mode: BlendMode, sv: F4, dv: F4) F4 {
    const s: [3]f32 = .{ sv[0], sv[1], sv[2] };
    const d: [3]f32 = .{ dv[0], dv[1], dv[2] };
    const sa = sv[3];
    const da = dv[3];
    var b: [3]f32 = undefined;
    const from_src = mode == .hue or mode == .color;
    const scale = if (mode == .color) da else sa;
    for (&b, s, d) |*v, x, y| v.* = (if (from_src) x else y) * scale;
    if (mode == .hue) setSat(&b, sat(d) * sa);
    if (mode == .saturation) setSat(&b, sat(s) * da);
    setLumClip(&b, if (mode == .luminosity) lum(s) * da else lum(d) * sa, sa * da);
    return .{ b[0], b[1], b[2], 0 };
}

/// Blend term of tiny-skia's highp `soft_light` (all lanes; the alpha lane is meaningless).
inline fn softLight(s: F4, d: F4, sa: F4, da: F4) F4 {
    const m = @select(f32, da > f4(0), d / da, f4(0));
    const s2 = s + s;
    const m4 = (m + m) + (m + m);
    const d4 = (d + d) + (d + d);
    const dark_src = d * (sa + (s2 - sa) * (f4(1) - m));
    const dark_dst = (m4 * m4 + m4) * (m - f4(1)) + f4(7) * m;
    const lite_dst = @sqrt(m) - m;
    const lite_src = d * sa + da * (s2 - sa) * @select(f32, d4 <= da, dark_dst, lite_dst);
    return @select(f32, s2 <= sa, dark_src, lite_src);
}

/// Any mode except normal / color-dodge / color-burn on one premultiplied pixel pair: the
/// tiny-skia highp pipeline `gather`, `scale_1_float(opacity)`, blend stage (`multiply`,
/// `screen`, `overlay`, `darken`, `lighten`, `hard_light`, `soft_light`, `difference`,
/// `exclusion`, `hue`, `saturation`, `color`, `luminosity`, `plus`), `store`; same f32
/// operations in the same order, branch-free over the four channels.
inline fn floatPixel(mode: BlendMode, p: u32, q: u32, opf: f32) u32 {
    const s = loadPx(p) * f4(opf);
    const d = loadPx(q);
    const sa = f4(s[3]);
    const da = f4(d[3]);
    const one = f4(1);
    const base = s * (one - da) + d * (one - sa);
    const sd = s * d;
    var o: F4 = switch (mode) {
        .multiply => base + sd,
        .screen => s + d - sd,
        .darken => s + d - vmax(s * da, d * sa),
        .lighten => s + d - vmin(s * da, d * sa),
        .difference => blk: {
            const m = vmin(s * da, d * sa);
            break :blk s + d - (m + m);
        },
        .exclusion => s + d - (sd + sd),
        .hard_light, .overlay => blk: {
            const t = (da - d) * (sa - s);
            const dark = if (mode == .overlay) (d + d) <= da else (s + s) <= sa;
            break :blk base + @select(f32, dark, sd + sd, sa * da - (t + t));
        },
        .plus_lighter => s + d,
        .soft_light => base + softLight(s, d, sa, da),
        else => base + nonSeparable(mode, s, d),
    };
    if (mode != .plus_lighter) o[3] = s[3] + d[3] - s[3] * d[3];
    // `store`: round_ties_even(clamp(o, 0, 1) * 255). NaN -> 0. Adding 2^23 rounds to an integer
    // (ties to even) that can be read from the low mantissa bits, without a float -> int op.
    const c = @select(f32, o > f4(0), vmin(o, one), f4(0)) * f4(255);
    const bits: @Vector(4, u32) = @bitCast(c + f4(8388608.0));
    return @bitCast(@as(@Vector(4, u8), @truncate(bits)));
}

/// `opaque_op`: opacity is 1 (then a transparent backdrop takes the source unchanged and
/// `plus_lighter` is a saturating byte add - both equal to what the f32 pipeline gives).
fn floatRow(mode: BlendMode, d: PxPtr, s: ConstPxPtr, n: usize, cov: ?[*]const u8, opf: f32, opaque_op: bool) void {
    const fast = opaque_op and cov == null and switch (mode) {
        .multiply, .screen, .darken, .lighten, .difference, .plus_lighter => true,
        else => false,
    };
    var i: usize = 0;
    while (i < n) {
        var m: usize = 1;
        if (fast and i + VL <= n) {
            const dp: *align(1) [VL]u32 = @ptrCast(d + i);
            const p: VU = @as(*align(1) const [VL]u32, @ptrCast(s + i)).*;
            const q: VU = dp.*;
            if (@reduce(.And, p & q) >> 24 == 255) {
                dp.* = opaqueBlend(mode, p, q);
                i += VL;
                continue;
            }
            m = VL;
        }
        for (i..i + m) |j| {
            const p = srcPx(s, j, cov);
            if (p >> 24 == 0) continue;
            const q = d[j];
            if (opaque_op) {
                if (q >> 24 == 0) {
                    d[j] = p;
                    continue;
                }
                if (mode == .plus_lighter) {
                    d[j] = @bitCast(@as(@Vector(4, u8), @bitCast(p)) +| @as(@Vector(4, u8), @bitCast(q)));
                    continue;
                }
            }
            d[j] = floatPixel(mode, p, q, opf);
        }
        i += m;
    }
}

/// multiply / screen / darken / lighten / difference / plus-lighter of `VL` OPAQUE pixels over `VL` opaque
/// pixels, in integer SIMD. With both alphas 255 the f32 pipeline reduces to
/// `round(S*D/255)`, `S + D - round(S*D/255)`, `min`, `max`, `|S - D|`, `min(S + D, 255)` per channel (S*D/255 is
/// never a rounding tie, so the exact integer rounding equals the f32 result; tested).
inline fn opaqueBlend(mode: BlendMode, p: VU, q: VU) VU {
    const NB = VL * 4;
    const B = @Vector(NB, u8);
    const W = @Vector(NB, u16);
    const a: B = @bitCast(p);
    const b: B = @bitCast(q);
    const r: B = switch (mode) {
        .darken => @min(a, b),
        .lighten => @max(a, b),
        .plus_lighter => a +| b,
        .difference => return @as(VU, @bitCast((a -| b) | (b -| a))) | @as(VU, @splat(0xFF000000)),
        else => blk: {
            const t = @as(W, a) * @as(W, b) + @as(W, @splat(128));
            const m: B = @truncate((t + (t >> @splat(8))) >> @splat(8));
            break :blk if (mode == .multiply) m else a +% b -% m;
        },
    };
    return @bitCast(r);
}

// ---- color-dodge / color-burn (takumi blend.rs) ------------------------------------------

/// takumi `blend.rs: demultiplied` (channel `c` of a pixel whose alpha has reciprocal `inv`).
inline fn tkDemul(c: u32, inv: f32) u32 {
    const v: u32 = @intFromFloat(@as(f32, @floatFromInt(c)) * inv + 0.5);
    return @min(v, 255);
}

/// takumi `blend.rs: color_dodge_integer` / `color_burn_integer` (straight u8 channels).
inline fn dodgeBurn(burn: bool, b: u32, t: u32) u32 {
    if (burn) {
        if (b == 255) return 255;
        if (t == 0 or b + t <= 255) return 0;
        return ((b + t - 255) * 255 + t / 2) / t;
    }
    if (b == 0) return 0;
    if (b + t >= 255) return 255;
    const den = 255 - t;
    return (b * 255 + den / 2) / den;
}

/// takumi `canvas.rs: composite_subcanvas` (non tiny-skia branch): layer scaled by
/// `round(opacity * 255)`, then `blend.rs: blend_premultiplied_pixel_slow` -> `blend_pixel` ->
/// `blend_with_integer` with `color_dodge_integer` / `color_burn_integer`.
fn dodgeBurnRow(burn: bool, d: PxPtr, s: ConstPxPtr, n: usize, cov: ?[*]const u8, op: u32) void {
    for (0..n) |i| {
        var p = srcPx(s, i, cov);
        if (op != 255) p = tkScalePx(p, op);
        const ta = p >> 24;
        if (ta == 0) continue;
        const q = d[i];
        const ba = q >> 24;
        if (ta == 255 and ba == 255) {
            var out: u32 = 0xFF000000;
            for ([_]u5{ 0, 8, 16 }) |sh| out |= dodgeBurn(burn, (q >> sh) & 255, (p >> sh) & 255) << sh;
            d[i] = out;
            continue;
        }
        const tinv: f32 = 255.0 / @as(f32, @floatFromInt(ta));
        const binv: f32 = if (ba == 0) 0 else 255.0 / @as(f32, @floatFromInt(ba));
        const ra = if (ba == 0) ta else ta + ba - tk255(ba * ta);
        var out: u32 = ra << 24;
        for ([_]u5{ 0, 8, 16 }) |sh| {
            const tp = (p >> sh) & 255;
            const bp = (q >> sh) & 255;
            const t = if (ta == 255) tp else tkDemul(tp, tinv);
            var v = t; // backdrop alpha 0: the straight top colour
            if (ba != 0) {
                const b = if (ba == 255) bp else tkDemul(bp, binv);
                const comp = ((255 - ta) * ba * b + (255 - ba) * ta * t + ta * ba * dodgeBurn(burn, b, t) + 32512) / 65025;
                v = @min((comp * 255 + ra / 2) / ra, 255);
            }
            out |= (if (ra == 255) v else tk255(v * ra)) << sh;
        }
        d[i] = out;
    }
}

// ---- masks -------------------------------------------------------------------------------

/// What a pixmap contributes as mask coverage. `.luminance` mirrors tiny-skia
/// `Mask::from_pixmap(.., MaskType::Luminance)` (the only luminance mask in takumi, used for
/// SVG `<mask>`): `ceil(clamp((0.2126 R + 0.7152 G + 0.0722 B) * alpha * 255, 0, 255))` with
/// R, G, B the STRAIGHT (demultiplied) colour in 0..1 (verified against the takumi oracle for opaque
/// mask colours, bench/probe/raster/blend_luma_oracle.mjs). CSS `mask-image` in takumi only ever
/// uses `.alpha` (`canvas/mask.rs: alpha_mask`).
pub const MaskSource = enum { alpha, luminance };

fn lumaCov(p: u32) u8 {
    const a8 = p >> 24;
    if (a8 == 0) return 0;
    const a = @as(f32, @floatFromInt(a8)) / 255.0;
    const r = @as(f32, @floatFromInt(p & 255)) / 255.0 / a;
    const g = @as(f32, @floatFromInt((p >> 8) & 255)) / 255.0 / a;
    const b = @as(f32, @floatFromInt((p >> 16) & 255)) / 255.0 / a;
    const luma = r * 0.2126 + g * 0.7152 + b * 0.0722;
    return @intFromFloat(@ceil(clampF(luma * a * 255.0, 0, 255)));
}

inline fn covOf(p: u32, source: MaskSource) u8 {
    return if (source == .alpha) @intCast(p >> 24) else lumaCov(p);
}

const VL = types.LANES;
const VU = @Vector(VL, u32);

/// `d[i] = d[i] * cov[i] / 255` on all four channels (exact rounding, `types.scalePx`).
fn scaleRow(d: PxPtr, cov: [*]const u8, n: usize) void {
    var i: usize = 0;
    const m: VU = @splat(0x00FF00FF);
    const bias: VU = @splat(0x00800080);
    const s8: @Vector(VL, u5) = @splat(8);
    while (i + VL <= n) : (i += VL) {
        const c: VU = @as(@Vector(VL, u8), cov[i..][0..VL].*);
        const dp: *align(1) [VL]u32 = @ptrCast(d + i);
        const p: VU = dp.*;
        var rb = (p & m) * c + bias;
        rb = ((rb + ((rb >> s8) & m)) >> s8) & m;
        var ga = ((p >> s8) & m) * c + bias;
        ga = (ga + ((ga >> s8) & m)) & ~m;
        dp.* = rb | ga;
    }
    while (i < n) : (i += 1) d[i] = scalePx(d[i], cov[i]);
}

/// Shared driver: multiplies `dst` by a coverage image occupying `b` (A8 `data`, or the alpha /
/// luminance of `pm`), clearing everything outside `b`.
fn maskApply(dst: *Pixmap, b: IRect, data: ?[*]const u8, pm: ?*const Pixmap, source: MaskSource) void {
    if (!dst.isValid() or dst.width == 0 or dst.height == 0) return;
    if (dst.width > std.math.maxInt(i32) or dst.height > std.math.maxInt(i32)) return;
    const reg = dst.bounds().intersect(b);
    const w: usize = dst.width;
    const px: PxPtr = @ptrCast(dst.data.ptr);
    const x0: usize = if (reg.isEmpty()) 0 else @intCast(reg.x);
    var y: usize = 0;
    while (y < dst.height) : (y += 1) {
        const row = px + y * w;
        const yi: i64 = @intCast(y);
        if (reg.isEmpty() or yi < reg.y or yi >= reg.bottom()) {
            @memset(row[0..w], 0);
            continue;
        }
        @memset(row[0..x0], 0);
        @memset(row[x0 + reg.w .. w], 0);
        const mx: usize = @intCast(@as(i64, reg.x) - b.x);
        const my: usize = @intCast(yi - b.y);
        const off = my * b.w + mx;
        if (data) |dp| {
            scaleRow(row + x0, dp + off, reg.w);
            continue;
        }
        const sp = @as(ConstPxPtr, @ptrCast(pm.?.data.ptr)) + off;
        var buf: [paint.CH]u8 = undefined;
        var o: usize = 0;
        while (o < reg.w) : (o += paint.CH) {
            const m = @min(paint.CH, reg.w - o);
            for (0..m) |i| buf[i] = covOf(sp[o + i], source);
            scaleRow(row + x0 + o, &buf, m);
        }
    }
}

/// Multiplies every pixel (all 4 premultiplied channels) of `dst` by the mask coverage (exact
/// div255 rounding; takumi's `scale_premultiplied_pixel` uses its `div_255`, which is one higher
/// for 126 of the 65536 products); pixels of `dst` outside `mask.bounds` become transparent.
/// An empty mask, or one whose `data` is shorter than its bounds, clears `dst` entirely.
pub fn maskMultiply(dst: *Pixmap, mask: *const Mask) void {
    const ok = !mask.bounds.isEmpty() and mask.data.len >= @as(u64, mask.bounds.w) * mask.bounds.h;
    maskApply(dst, if (ok) mask.bounds else IRect.empty, mask.data.ptr, null, .alpha);
}

/// Same, the mask being a pixmap placed at integer offset (ox, oy) in dst space, using its alpha
/// (`.alpha`) or its luminance (`.luminance`, see `MaskSource`). An invalid or empty `mask`
/// clears `dst` entirely. `mask` must not alias `dst`.
pub fn maskMultiplyPixmap(dst: *Pixmap, mask: *const Pixmap, ox: i32, oy: i32, source: MaskSource) void {
    const ok = mask.isValid() and mask.width <= (1 << 24) and mask.height <= (1 << 24);
    const b: IRect = if (ok) .{ .x = ox, .y = oy, .w = mask.width, .h = mask.height } else IRect.empty;
    maskApply(dst, b, null, mask, source);
}

/// Converts a pixmap to an A8 coverage mask (alpha or luminance), allocated from `alloc` (the
/// caller owns it: `Mask.deinit`), bounds = (ox, oy, src.width, src.height). An invalid or
/// zero-sized `src` gives `Mask.empty`.
pub fn maskFromPixmap(alloc: Allocator, src: *const Pixmap, ox: i32, oy: i32, source: MaskSource) !Mask {
    if (!src.isValid()) return Mask.empty;
    const m = try Mask.init(alloc, .{ .x = ox, .y = oy, .w = src.width, .h = src.height });
    const sp: ConstPxPtr = @ptrCast(src.data.ptr);
    for (m.data, 0..) |*v, i| v.* = covOf(sp[i], source);
    return m;
}

// ---- tests -------------------------------------------------------------------------------

const testing = std.testing;
const Color = types.Color;

const Rng = struct {
    s: u64,
    fn next(self: *Rng) u32 {
        self.s = self.s *% 6364136223846793005 +% 1442695040888963407;
        return @truncate(self.s >> 32);
    }
    /// Valid premultiplied pixel; alpha is often 0, tiny or 255, channels often 0 or alpha.
    fn px(self: *Rng) u32 {
        const v = self.next();
        const a: u32 = switch (self.next() % 6) {
            0 => 255,
            1 => 0,
            2 => 1 + self.next() % 8,
            else => self.next() % 256,
        };
        const hi: u32 = switch (self.next() % 8) {
            0 => 0,
            1 => a,
            else => 256,
        };
        var out: u32 = a << 24;
        inline for (.{ 0, 8, 16 }) |sh| {
            const c = if (hi == 256) ((v >> sh) & 255) % (a + 1) else hi;
            out |= c << sh;
        }
        return out;
    }
};

fn fillRandom(pm: *Pixmap, rng: *Rng) void {
    for (pm.pixels()) |*p| p.* = rng.px();
}

/// Independent per-channel takumi `mul_div_255` scale of a packed pixel.
fn refTkScale(p: u32, c: u32) u32 {
    var out: u32 = 0;
    inline for (.{ 0, 8, 16, 24 }) |sh| {
        const v = ((p >> sh) & 255) * c;
        out |= ((v + 128 + (v >> 8)) >> 8) << sh;
    }
    return out;
}

fn refChannel(mode: BlendMode, cb: f64, cs: f64) f64 {
    return switch (mode) {
        .normal => cs,
        .multiply => cb * cs,
        .screen => cb + cs - cb * cs,
        .overlay => refChannel(.hard_light, cs, cb),
        .darken => @min(cb, cs),
        .lighten => @max(cb, cs),
        .color_dodge => if (cb == 0) 0 else if (cs >= 1) 1 else @min(1, cb / (1 - cs)),
        .color_burn => if (cb >= 1) 1 else if (cs <= 0) 0 else 1 - @min(1, (1 - cb) / cs),
        .hard_light => if (cs <= 0.5) cb * 2 * cs else cb + (2 * cs - 1) - cb * (2 * cs - 1),
        .soft_light => blk: {
            if (cs <= 0.5) break :blk cb - (1 - 2 * cs) * cb * (1 - cb);
            const dd = if (cb <= 0.25) ((16 * cb - 12) * cb + 4) * cb else @sqrt(cb);
            break :blk cb + (2 * cs - 1) * (dd - cb);
        },
        .difference => @abs(cb - cs),
        .exclusion => cb + cs - 2 * cb * cs,
        else => unreachable,
    };
}

fn refLum(c: [3]f64) f64 {
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2];
}

/// W3C SetLum + ClipColor; with `tiny_skia_clip_color` the `n < 0` branch is replaced by what
/// tiny-skia effectively does (clamp negative channels to 0).
fn refSetLum(c_in: [3]f64, l: f64) [3]f64 {
    var c = c_in;
    const dl = l - refLum(c);
    for (&c) |*v| v.* += dl;
    const ll = refLum(c);
    const n = @min(c[0], @min(c[1], c[2]));
    const x = @max(c[0], @max(c[1], c[2]));
    if (n < 0 and !tiny_skia_clip_color) for (&c) |*v| {
        v.* = ll + (v.* - ll) * ll / (ll - n);
    };
    if (x > 1) for (&c) |*v| {
        v.* = ll + (v.* - ll) * (1 - ll) / (x - ll);
    };
    for (&c) |*v| v.* = @max(v.*, 0);
    return c;
}

fn refSat(c: [3]f64) f64 {
    return @max(c[0], @max(c[1], c[2])) - @min(c[0], @min(c[1], c[2]));
}

fn refSetSat(c: [3]f64, s: f64) [3]f64 {
    const n = @min(c[0], @min(c[1], c[2]));
    const x = @max(c[0], @max(c[1], c[2]));
    var o: [3]f64 = .{ 0, 0, 0 };
    if (x > n) for (&o, c) |*v, cv| {
        v.* = (cv - n) * s / (x - n);
    };
    return o;
}

/// W3C Compositing 1 reference in f64 on straight colours, source alpha scaled by `opacity`;
/// returns premultiplied 0..255 floats.
fn refBlend(mode: BlendMode, sp: u32, dp: u32, opacity: f64) [4]f64 {
    const as: f64 = @as(f64, @floatFromInt(sp >> 24)) / 255.0 * opacity;
    const ab: f64 = @as(f64, @floatFromInt(dp >> 24)) / 255.0;
    var cs: [3]f64 = undefined;
    var cb: [3]f64 = undefined;
    inline for (0..3) |k| {
        const sv: f64 = @floatFromInt((sp >> (8 * k)) & 255);
        const dv: f64 = @floatFromInt((dp >> (8 * k)) & 255);
        cs[k] = if (sp >> 24 != 0) sv / @as(f64, @floatFromInt(sp >> 24)) else 0;
        cb[k] = if (dp >> 24 != 0) dv / @as(f64, @floatFromInt(dp >> 24)) else 0;
        if (mode == .color_dodge or mode == .color_burn) {
            // takumi blends these two in straight u8: the reference starts from the same
            // 8-bit demultiplied colours (dividing by a small Cs / 1-Cs amplifies that
            // quantisation without bound, so the unquantised reference is not comparable)
            cs[k] = @min(255.0, @floor(cs[k] * 255.0 + 0.5)) / 255.0;
            cb[k] = @min(255.0, @floor(cb[k] * 255.0 + 0.5)) / 255.0;
        }
    }
    var out: [4]f64 = undefined;
    if (mode == .plus_lighter) {
        inline for (0..3) |k| out[k] = @min(255.0, (cs[k] * as + cb[k] * ab) * 255.0);
        out[3] = @min(255.0, (as + ab) * 255.0);
        return out;
    }
    var b: [3]f64 = undefined;
    switch (mode) {
        .hue => b = refSetLum(refSetSat(cs, refSat(cb)), refLum(cb)),
        .saturation => b = refSetLum(refSetSat(cb, refSat(cs)), refLum(cb)),
        .color => b = refSetLum(cs, refLum(cb)),
        .luminosity => b = refSetLum(cb, refLum(cs)),
        else => inline for (0..3) |k| {
            b[k] = refChannel(mode, cb[k], cs[k]);
        },
    }
    inline for (0..3) |k| out[k] = (as * (1 - ab) * cs[k] + as * ab * b[k] + (1 - as) * ab * cb[k]) * 255.0;
    out[3] = (as + ab - as * ab) * 255.0;
    return out;
}

/// Tolerance (8-bit levels, premultiplied result) against the f64 reference.
fn tolerance(mode: BlendMode, opacity: f32) f64 {
    return switch (mode) {
        // drawPixmap path: exact at opacity 1; otherwise opacity, source and backdrop terms are
        // each rounded to 8 bits (up to 0.5 level each)
        .normal => if (opacity == 1) 0.5001 else 1.51,
        // takumi's integer path: demultiply to u8 (shared with the reference), blend, round
        // the straight result, premultiply
        .color_dodge, .color_burn => 2.0,
        // one rounding of the exact value (integer path, or f32 with ~1e-4 of noise)
        else => 0.501,
    };
}

test "every mode against the W3C float reference" {
    const alloc = testing.allocator;
    const W = 64;
    const H = 16;
    var src = try Pixmap.init(alloc, W, H);
    defer src.deinit(alloc);
    var dst = try Pixmap.init(alloc, W, H);
    defer dst.deinit(alloc);
    var before = try Pixmap.init(alloc, W, H);
    defer before.deinit(alloc);
    var rng: Rng = .{ .s = 0x1234 };
    for (std.enums.values(BlendMode)) |mode| for ([_]f32{ 1, 0.5, 0.3 }) |opacity| {
        fillRandom(&src, &rng);
        fillRandom(&before, &rng);
        // rows 0-3: opaque source; rows 0-1 and 4-5: opaque backdrop
        for (0..W * 4) |i| src.pixels()[i] |= 0xFF000000;
        for (0..W * 2) |i| before.pixels()[i] |= 0xFF000000;
        for (W * 4..W * 6) |i| before.pixels()[i] |= 0xFF000000;
        @memcpy(dst.data, before.data);
        drawPixmapBlend(&dst, &src, 0, 0, opacity, mode, null);
        const dodge_burn = mode == .color_dodge or mode == .color_burn;
        for (src.pixels(), before.pixels(), dst.pixels(), 0..) |sp, bp, got, i| {
            // dodge / burn quantise the opacity-scaled source like takumi does
            const want = if (dodge_burn and opacity != 1)
                refBlend(mode, refTkScale(sp, @intFromFloat(opacity * 255 + 0.5)), bp, 1)
            else
                refBlend(mode, sp, bp, opacity);
            inline for (0..4) |k| {
                const g: f64 = @floatFromInt((got >> (8 * k)) & 255);
                if (@abs(g - want[k]) > tolerance(mode, opacity)) {
                    std.debug.print("mode {s} opacity {d} px {d} ch {d}: src {x:0>8} dst {x:0>8} got {x:0>8} want {d:.3}\n", .{ @tagName(mode), opacity, i, k, sp, bp, got, want[k] });
                    return error.TestExpectedEqual;
                }
            }
        }
    };
}

test "opaque integer SIMD path == f32 pipeline" {
    const alloc = testing.allocator;
    const N = 8191;
    var src = try Pixmap.init(alloc, N, 1);
    defer src.deinit(alloc);
    var dst = try Pixmap.init(alloc, N, 1);
    defer dst.deinit(alloc);
    var before = try Pixmap.init(alloc, N, 1);
    defer before.deinit(alloc);
    var rng: Rng = .{ .s = 0xBEEF };
    for ([_]BlendMode{ .multiply, .screen, .darken, .lighten, .difference, .plus_lighter }) |mode| {
        // mostly opaque runs, with a translucent / transparent pixel now and then
        for (src.pixels(), before.pixels()) |*sp, *bp| {
            sp.* = if (rng.next() % 37 == 0) rng.px() else rng.next() | 0xFF000000;
            bp.* = if (rng.next() % 41 == 0) rng.px() else rng.next() | 0xFF000000;
        }
        // every byte value against every byte value in the first 65536 channel pairs
        for (0..N) |i| {
            const k: u32 = @intCast(i * 3);
            const sv = ((k >> 8) & 255) | ((((k + 1) >> 8) & 255) << 8) | ((((k + 2) >> 8) & 255) << 16);
            const dv = (k & 255) | (((k + 1) & 255) << 8) | (((k + 2) & 255) << 16);
            if (k + 2 < 65536) {
                src.pixels()[i] = sv | 0xFF000000;
                before.pixels()[i] = dv | 0xFF000000;
            }
        }
        @memcpy(dst.data, before.data);
        drawPixmapBlend(&dst, &src, 0, 0, 1, mode, null);
        for (src.pixels(), before.pixels(), dst.pixels()) |sp, bp, got| {
            const want = if (sp >> 24 == 0) bp else if (bp >> 24 == 0) sp else floatPixel(mode, sp, bp, 1);
            try testing.expectEqual(want, got);
        }
    }
}

test "normal is byte-identical to drawPixmap" {
    const image = @import("image.zig");
    const alloc = testing.allocator;
    var src = try Pixmap.init(alloc, 37, 21);
    defer src.deinit(alloc);
    var a = try Pixmap.init(alloc, 50, 30);
    defer a.deinit(alloc);
    var b = try Pixmap.init(alloc, 50, 30);
    defer b.deinit(alloc);
    var clip_mask = try Mask.init(alloc, .{ .x = 3, .y = -2, .w = 40, .h = 25 });
    defer clip_mask.deinit(alloc);
    var rng: Rng = .{ .s = 77 };
    for (clip_mask.data) |*v| v.* = @truncate(rng.next() >> (@as(u5, @truncate(rng.next() % 3)) * 4));
    const clip = clip_mask.asClip();
    const rect_clip = ClipMask.fromRect(.{ .x = 10, .y = 5, .w = 20, .h = 40 });
    const clips = [_]?*const ClipMask{ null, &clip, &rect_clip };
    const offsets = [_][2]i32{ .{ 0, 0 }, .{ 7, 4 }, .{ -9, -6 }, .{ 30, 20 }, .{ 49, 29 }, .{ -36, -20 } };
    for (clips) |c| for ([_]f32{ 1, 0.5, 0.3, 0.004, 0.001 }) |op| for (offsets) |o| {
        fillRandom(&src, &rng);
        fillRandom(&a, &rng);
        @memcpy(b.data, a.data);
        image.drawPixmap(&a, &src, types.Affine.translate(@floatFromInt(o[0]), @floatFromInt(o[1])), op, .nearest, c);
        drawPixmapBlend(&b, &src, o[0], o[1], op, .normal, c);
        try testing.expectEqualSlices(u8, a.data, b.data);
    };
}

test "rgba(0,0,255,0.3) over white is (178,178,255)" {
    const alloc = testing.allocator;
    var src = try Pixmap.init(alloc, 3, 3);
    defer src.deinit(alloc);
    var dst = try Pixmap.init(alloc, 3, 3);
    defer dst.deinit(alloc);
    dst.clear(Color.white);
    src.clear(Color.rgba(0, 0, 255, 77)); // 0.3 * 255 = 76.5 -> 77
    drawPixmapBlend(&dst, &src, 0, 0, 1, .normal, null);
    try testing.expectEqual([4]u8{ 178, 178, 255, 255 }, dst.pixel(1, 1));
    // the same through layer opacity
    dst.clear(Color.white);
    src.clear(Color.rgb(0, 0, 255));
    drawPixmapBlend(&dst, &src, 0, 0, 0.3, .normal, null);
    try testing.expectEqual([4]u8{ 178, 178, 255, 255 }, dst.pixel(1, 1));
}

test "known values from the takumi 2.20.0 oracle" {
    if (!tiny_skia_clip_color) return error.SkipZigTest;
    const alloc = testing.allocator;
    var src = try Pixmap.init(alloc, 1, 1);
    defer src.deinit(alloc);
    var dst = try Pixmap.init(alloc, 1, 1);
    defer dst.deinit(alloc);
    // backdrop / source premultiplied pixels (r, g, b, a), opacity, expected STRAIGHT output
    const Case = struct { mode: BlendMode, want: [3][4]u8 };
    const setups = [3]struct { bg: [4]u8, fg: [4]u8, op: f32 }{
        // rgb(200,100,50) under rgb(30,180,220)
        .{ .bg = .{ 200, 100, 50, 255 }, .fg = .{ 30, 180, 220, 255 }, .op = 1 },
        // the same at opacity 0.4
        .{ .bg = .{ 200, 100, 50, 255 }, .fg = .{ 30, 180, 220, 255 }, .op = 0.4 },
        // rgba(200,100,50,0.6) under rgba(30,180,220,0.5)
        .{ .bg = .{ 120, 60, 30, 153 }, .fg = .{ 15, 90, 110, 128 }, .op = 1 },
    };
    const cases = [_]Case{
        .{ .mode = .multiply, .want = .{ .{ 24, 71, 43, 255 }, .{ 129, 88, 47, 255 }, .{ 91, 109, 90, 204 } } },
        .{ .mode = .screen, .want = .{ .{ 206, 209, 227, 255 }, .{ 203, 144, 121, 255 }, .{ 160, 161, 159, 204 } } },
        .{ .mode = .overlay, .want = .{ .{ 158, 141, 86, 255 }, .{ 183, 116, 65, 255 }, .{ 141, 135, 106, 204 } } },
        .{ .mode = .darken, .want = .{ .{ 30, 100, 50, 255 }, .{ 132, 100, 50, 255 }, .{ 94, 120, 93, 204 } } },
        .{ .mode = .lighten, .want = .{ .{ 200, 180, 220, 255 }, .{ 200, 132, 118, 255 }, .{ 158, 150, 156, 204 } } },
        .{ .mode = .color_dodge, .want = .{ .{ 227, 255, 255, 255 }, .{ 211, 162, 132, 255 }, .{ 168, 179, 170, 204 } } },
        .{ .mode = .color_burn, .want = .{ .{ 0, 35, 17, 255 }, .{ 120, 74, 37, 255 }, .{ 83, 95, 80, 204 } } },
        .{ .mode = .hard_light, .want = .{ .{ 47, 164, 199, 255 }, .{ 139, 126, 109, 255 }, .{ 100, 144, 148, 204 } } },
        .{ .mode = .soft_light, .want = .{ .{ 167, 125, 96, 255 }, .{ 187, 110, 68, 255 }, .{ 145, 129, 110, 204 } } },
        .{ .mode = .difference, .want = .{ .{ 170, 80, 170, 255 }, .{ 188, 92, 98, 255 }, .{ 146, 113, 138, 204 } } },
        .{ .mode = .exclusion, .want = .{ .{ 183, 139, 184, 255 }, .{ 193, 116, 103, 255 }, .{ 151, 135, 143, 204 } } },
        .{ .mode = .hue, .want = .{ .{ 38, 157, 188, 255 }, .{ 135, 123, 105, 255 }, .{ 96, 141, 145, 204 } } },
        .{ .mode = .saturation, .want = .{ .{ 220, 93, 30, 255 }, .{ 208, 97, 42, 255 }, .{ 165, 118, 85, 204 } } },
        .{ .mode = .color, .want = .{ .{ 15, 165, 205, 255 }, .{ 126, 126, 112, 255 }, .{ 88, 145, 151, 204 } } },
        .{ .mode = .luminosity, .want = .{ .{ 215, 115, 65, 255 }, .{ 206, 106, 56, 255 }, .{ 163, 125, 98, 204 } } },
        .{ .mode = .plus_lighter, .want = .{ .{ 230, 255, 255, 255 }, .{ 212, 172, 138, 255 }, .{ 135, 150, 140, 255 } } },
    };
    for (cases) |c| for (setups, c.want) |su, want| {
        dst.data[0..4].* = su.bg;
        src.data[0..4].* = su.fg;
        drawPixmapBlend(&dst, &src, 0, 0, su.op, c.mode, null);
        dst.toStraightAlpha();
        try testing.expectEqual(want, dst.pixel(0, 0));
    };
    // tiny-skia clip_color quirk (hue of rgb(249,123,198) over rgb(0,0,195)): W3C gives (59,0,35)
    dst.data[0..4].* = .{ 0, 0, 195, 255 };
    src.data[0..4].* = .{ 249, 123, 198, 255 };
    drawPixmapBlend(&dst, &src, 0, 0, 1, .hue, null);
    try testing.expectEqual([4]u8{ 145, 0, 66, 255 }, dst.pixel(0, 0));
}

test "blend: clip, offsets, opacity and invalid input" {
    const alloc = testing.allocator;
    var src = try Pixmap.init(alloc, 8, 8);
    defer src.deinit(alloc);
    var dst = try Pixmap.init(alloc, 16, 12);
    defer dst.deinit(alloc);
    var ref = try Pixmap.init(alloc, 16, 12);
    defer ref.deinit(alloc);
    var one_s = try Pixmap.init(alloc, 1, 1);
    defer one_s.deinit(alloc);
    var one_d = try Pixmap.init(alloc, 1, 1);
    defer one_d.deinit(alloc);
    var rng: Rng = .{ .s = 5 };
    fillRandom(&src, &rng);
    fillRandom(&ref, &rng);
    var cm = try Mask.init(alloc, .{ .x = 2, .y = 1, .w = 9, .h = 7 });
    defer cm.deinit(alloc);
    for (cm.data, 0..) |*v, i| v.* = if (i % 5 == 0) 0 else if (i % 5 == 1) 255 else @truncate(rng.next());
    const clip = cm.asClip();
    const imax = std.math.maxInt(i32);
    const imin = std.math.minInt(i32);

    for (std.enums.values(BlendMode)) |mode| {
        // nothing drawn: far offsets, zero / NaN opacity, short clip data, invalid pixmaps
        @memcpy(dst.data, ref.data);
        const far = [_][2]i32{ .{ 16, 0 }, .{ 0, 12 }, .{ -8, 0 }, .{ 0, -8 }, .{ imax, 3 }, .{ imin, 3 }, .{ imin, imin }, .{ 3, imax } };
        for (far) |o| drawPixmapBlend(&dst, &src, o[0], o[1], 1, mode, null);
        drawPixmapBlend(&dst, &src, 1, 1, 0, mode, null);
        drawPixmapBlend(&dst, &src, 1, 1, -3, mode, null);
        drawPixmapBlend(&dst, &src, 1, 1, std.math.nan(f32), mode, null);
        const short: ClipMask = .{ .bounds = cm.bounds, .data = cm.data[0 .. cm.data.len - 1] };
        drawPixmapBlend(&dst, &src, 1, 1, 1, mode, &short);
        const empty_clip = ClipMask.fromRect(IRect.empty);
        drawPixmapBlend(&dst, &src, 1, 1, 1, mode, &empty_clip);
        const bad_src: Pixmap = .{ .width = 8, .height = 9, .data = src.data };
        drawPixmapBlend(&dst, &bad_src, 1, 1, 1, mode, null);
        drawPixmapBlend(&dst, &Pixmap.empty, 1, 1, 1, mode, null);
        var bad_dst: Pixmap = .{ .width = 16, .height = 13, .data = dst.data };
        drawPixmapBlend(&bad_dst, &src, 1, 1, 1, mode, null);
        try testing.expectEqualSlices(u8, ref.data, dst.data);

        // a clipped draw == per pixel, the unclipped blend of the source scaled by the clip
        // coverage (takumi rounding; `.normal`: exact div255(clip * op) like drawPixmap)
        for ([_]f32{ 1, 0.6, 3.0 }) |opacity| {
            const tx: i32 = 5;
            const ty: i32 = -2;
            @memcpy(dst.data, ref.data);
            drawPixmapBlend(&dst, &src, tx, ty, opacity, mode, &clip);
            const op: u32 = @intFromFloat(@min(opacity, 1) * 255 + 0.5);
            var y: i32 = 0;
            while (y < 12) : (y += 1) {
                var x: i32 = 0;
                while (x < 16) : (x += 1) {
                    const di: usize = @intCast(y * 16 + x);
                    var want = ref.pixels()[di];
                    const cov: u32 = cm.at(x, y);
                    if (x >= tx and x < tx + 8 and y >= ty and y < ty + 8 and cov != 0) {
                        const sp = src.pixels()[@intCast((y - ty) * 8 + (x - tx))];
                        if (mode == .normal) {
                            want = types.over(scalePx(sp, div255(cov * op)), want);
                        } else {
                            one_s.pixels()[0] = refTkScale(sp, cov);
                            one_d.pixels()[0] = want;
                            drawPixmapBlend(&one_d, &one_s, 0, 0, opacity, mode, null);
                            want = one_d.pixels()[0];
                        }
                    }
                    try testing.expectEqual(want, dst.pixels()[di]);
                }
            }
        }
    }
}

test "maskMultiply: inside / outside bounds, exact values" {
    const alloc = testing.allocator;
    var dst = try Pixmap.init(alloc, 23, 9);
    defer dst.deinit(alloc);
    var ref = try Pixmap.init(alloc, 23, 9);
    defer ref.deinit(alloc);
    var rng: Rng = .{ .s = 99 };
    const bounds_list = [_]IRect{
        .{ .x = 2, .y = 1, .w = 19, .h = 5 },   .{ .x = -4, .y = -3, .w = 40, .h = 30 },
        .{ .x = 20, .y = 7, .w = 9, .h = 9 },   .{ .x = 100, .y = 100, .w = 4, .h = 4 },
        .{ .x = -50, .y = 0, .w = 50, .h = 9 }, .{ .x = std.math.maxInt(i32), .y = std.math.minInt(i32), .w = 3, .h = 3 },
    };
    for (bounds_list) |b| {
        var m = try Mask.init(alloc, b);
        defer m.deinit(alloc);
        for (m.data, 0..) |*v, i| v.* = if (i % 7 == 0) 255 else if (i % 7 == 1) 0 else @truncate(rng.next());
        fillRandom(&ref, &rng);
        @memcpy(dst.data, ref.data);
        maskMultiply(&dst, &m);
        for (0..9) |y| for (0..23) |x| {
            const c: u32 = m.at(@intCast(x), @intCast(y));
            const p = ref.pixel(@intCast(x), @intCast(y));
            var want: [4]u8 = undefined;
            // round(p * c / 255), computed independently of div255
            for (&want, p) |*w, v| w.* = @intCast((@as(u32, v) * c * 2 + 255) / 510);
            try testing.expectEqual(want, dst.pixel(@intCast(x), @intCast(y)));
        };
    }
    // empty mask and short data clear everything
    fillRandom(&dst, &rng);
    maskMultiply(&dst, &Mask.empty);
    for (dst.data) |v| try testing.expectEqual(@as(u8, 0), v);
    fillRandom(&dst, &rng);
    var one = [_]u8{255};
    maskMultiply(&dst, &.{ .bounds = .{ .x = 0, .y = 0, .w = 23, .h = 9 }, .data = &one });
    for (dst.data) |v| try testing.expectEqual(@as(u8, 0), v);
    // invalid dst: untouched, no trap
    var bad: Pixmap = .{ .width = 23, .height = 10, .data = dst.data };
    maskMultiply(&bad, &Mask.empty);
}

test "maskMultiplyPixmap / maskFromPixmap: alpha and luminance" {
    const alloc = testing.allocator;
    var mp = try Pixmap.init(alloc, 4, 2);
    defer mp.deinit(alloc);
    const cols = [_]Color{
        Color.white,          Color.black,                    Color.rgb(255, 0, 0), Color.rgb(0, 255, 0),
        Color.rgb(0, 0, 255), Color.rgba(255, 255, 255, 128), Color.transparent,    Color.rgb(128, 128, 128),
    };
    for (mp.pixels(), cols) |*p, c| p.* = c.premul();
    // luminance = ceil((0.2126 R + 0.7152 G + 0.0722 B) * alpha * 255); alpha = alpha
    const want_alpha = [_]u8{ 255, 255, 255, 255, 255, 128, 0, 255 };
    var ma = try maskFromPixmap(alloc, &mp, -1, 3, .alpha);
    defer ma.deinit(alloc);
    try testing.expectEqual(IRect{ .x = -1, .y = 3, .w = 4, .h = 2 }, ma.bounds);
    try testing.expectEqualSlices(u8, &want_alpha, ma.data);
    var ml = try maskFromPixmap(alloc, &mp, -1, 3, .luminance);
    defer ml.deinit(alloc);
    try testing.expectEqual(@as(u8, 255), ml.data[0]);
    try testing.expectEqual(@as(u8, 0), ml.data[1]);
    try testing.expectEqual(@as(u8, 55), ml.data[2]); // 54.19 -> ceil
    try testing.expectEqual(@as(u8, 183), ml.data[3]); // 182.43
    try testing.expectEqual(@as(u8, 19), ml.data[4]); // 18.39
    try testing.expect(ml.data[5] == 128 or ml.data[5] == 129); // 128.0 +- float noise, ceil
    try testing.expectEqual(@as(u8, 0), ml.data[6]);
    try testing.expect(ml.data[7] == 128 or ml.data[7] == 129);

    // maskMultiplyPixmap == maskMultiply with the converted mask, at several offsets
    var dst = try Pixmap.init(alloc, 7, 5);
    defer dst.deinit(alloc);
    var ref = try Pixmap.init(alloc, 7, 5);
    defer ref.deinit(alloc);
    var big = try Pixmap.init(alloc, 150, 3);
    defer big.deinit(alloc);
    var rng: Rng = .{ .s = 4242 };
    fillRandom(&big, &rng);
    const masks = [_]*const Pixmap{ &mp, &big };
    for (masks) |mpm| for ([_]MaskSource{ .alpha, .luminance }) |source| {
        for ([_][2]i32{ .{ 0, 0 }, .{ 2, 1 }, .{ -2, -1 }, .{ 6, 4 }, .{ 7, 0 }, .{ -149, 2 }, .{ std.math.minInt(i32), 0 } }) |o| {
            fillRandom(&ref, &rng);
            @memcpy(dst.data, ref.data);
            maskMultiplyPixmap(&dst, mpm, o[0], o[1], source);
            var m = try maskFromPixmap(alloc, mpm, o[0], o[1], source);
            defer m.deinit(alloc);
            maskMultiply(&ref, &m);
            try testing.expectEqualSlices(u8, ref.data, dst.data);
        }
    };
    // invalid mask pixmap clears dst; maskFromPixmap gives an empty mask
    const bad: Pixmap = .{ .width = 4, .height = 3, .data = mp.data };
    fillRandom(&dst, &rng);
    maskMultiplyPixmap(&dst, &bad, 0, 0, .alpha);
    for (dst.data) |v| try testing.expectEqual(@as(u8, 0), v);
    const e = try maskFromPixmap(alloc, &bad, 0, 0, .alpha);
    try testing.expect(e.bounds.isEmpty());
}

test "paint.fillMask with a nearest image paint and integer translation is an exact texel copy" {
    const alloc = testing.allocator;
    var src = try Pixmap.init(alloc, 90, 7);
    defer src.deinit(alloc);
    var dst = try Pixmap.init(alloc, 100, 12);
    defer dst.deinit(alloc);
    var ref = try Pixmap.init(alloc, 100, 12);
    defer ref.deinit(alloc);
    var rng: Rng = .{ .s = 31337 };
    fillRandom(&src, &rng);
    const tx: i32 = 6;
    const ty: i32 = 3;
    // mask strictly inside the placed pixmap, so no extend mode is involved
    var m = try Mask.init(alloc, .{ .x = 8, .y = 4, .w = 85, .h = 5 });
    defer m.deinit(alloc);
    for (m.data, 0..) |*v, i| v.* = if (i % 3 == 0) 255 else @truncate(rng.next());
    var cm = try Mask.init(alloc, .{ .x = 0, .y = 0, .w = 100, .h = 12 });
    defer cm.deinit(alloc);
    for (cm.data) |*v| v.* = @truncate(rng.next() | 0x80);
    const clip = cm.asClip();
    for ([_]?*const ClipMask{ null, &clip }) |c| {
        fillRandom(&ref, &rng);
        @memcpy(dst.data, ref.data);
        const pnt: types.Paint = .{ .image = .{
            .pixmap = &src,
            .transform = types.Affine.translate(@floatFromInt(-tx), @floatFromInt(-ty)),
            .filter = .nearest,
        } };
        paint.fillMask(&dst, &m, &pnt, c);
        var y: i32 = 0;
        while (y < 12) : (y += 1) {
            var x: i32 = 0;
            while (x < 100) : (x += 1) {
                const di: usize = @intCast(y * 100 + x);
                var cov: u32 = m.at(x, y);
                if (c != null) cov = div255(cov * cm.at(x, y));
                var want = ref.pixels()[di];
                if (cov != 0) {
                    const si: usize = @intCast((y - ty) * 90 + (x - tx));
                    want = types.over(scalePx(src.pixels()[si], cov), want);
                }
                try testing.expectEqual(want, dst.pixels()[di]);
            }
        }
    }
}
