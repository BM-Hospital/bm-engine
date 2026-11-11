//! Animation helpers: easing functions and property interpolation between two computed styles
//! (used by the integrator's keyframe engine). Mirrors takumi `style/animation.rs`,
//! `style/properties/animation.rs` (easing) and the `Animatable` impls where cheap.
//!
//! Rules (takumi / CSS):
//! - "discrete" properties switch from `a` to `b` at t >= 0.5 (takumi `discrete`).
//! - lengths lerp `px`/`pct` independently; `calc` trees are combined as `(1-t)*A + t*B`.
//! - colours lerp in premultiplied 8-bit sRGB with per-channel rounding, then demultiply
//!   (takumi `Color::lerp_premultiplied`), `currentColor` resolved against each side's `color`.
//! - transform lists / shadow lists / filter lists are padded to the longest with neutral items
//!   (identity function, transparent zero shadow of the same `inset`, filter initial value) and
//!   lerped pairwise. Mismatched shadow `inset` or filter kinds switch discretely per item (takumi).
//!   Mismatched transform function kinds: both lists are converted to 2D matrices, decomposed
//!   (CSS Transforms 1 §unmatrix) and the decomposition is lerped into one `.matrix` op; if a
//!   translate uses % / calc (box-relative) the whole list switches discretely instead.
//! - visibility: `visible` if either endpoint is visible for 0 < t < 1, else discrete.
//! - integers (z-index, order, font-weight) lerp and round.
//! Extrapolation (t < 0 or t > 1 from overshooting easings) is allowed; values with a valid
//! range are clamped (opacity, widths, blur, colours, font-size/weight).
const std = @import("std");
const computed = @import("computed.zig");
const values = @import("values.zig");
const colorm = @import("color.zig");
const props = @import("props.zig");

const S = computed.ComputedStyle;
const LP = values.LP;
const CalcNode = values.CalcNode;
const Color = colorm.Color;
const ColorValue = colorm.ColorValue;
const Prop = props.Prop;
const Shadow = computed.Shadow;
const Filter = computed.Filter;
const TransformOp = computed.TransformOp;
const TimingFunction = computed.TimingFunction;
const Allocator = std.mem.Allocator;
const OOM = error{OutOfMemory};

// =============================================================================================
// easing
// =============================================================================================

/// Applies an easing function to the input progress `t` (normally 0..1). Mirrors takumi
/// `AnimationTimingFunction::apply(progress, before = false)`:
/// - cubic-bezier: 6 Newton iterations from t (takumi), refined by bisection when Newton did not
///   converge (|x error| > 1e-5); output may overshoot [0,1] (y control points are not clamped).
/// - steps(n, pos): input clamped to [0,1]; jump-start/end use n jumps, jump-both n+1,
///   jump-none max(n-1, 1); the "before flag" is not modelled.
/// - linear(): piecewise linear through the points, extrapolated from the outermost segments.
pub fn easing(tf: TimingFunction, t: f32) f32 {
    if (t != t) return 0;
    return switch (tf) {
        .cubic => |c| cubicBezier(c[0], c[1], c[2], c[3], t),
        .steps => |s| steps(s.n, s.pos, t),
        .linear_points => |pts| linearCurve(pts, t),
    };
}

fn cubicBezier(x1: f32, y1: f32, x2: f32, y2: f32, progress: f32) f32 {
    if (x1 == y1 and x2 == y2) return progress; // linear
    const cx = 3 * x1;
    const bx = 3 * (x2 - x1) - cx;
    const ax = 1 - cx - bx;
    const cy = 3 * y1;
    const by = 3 * (y2 - y1) - cy;
    const ay = 1 - cy - by;
    const sample = struct {
        fn f(a: f32, b: f32, c: f32, x: f32) f32 {
            return ((a * x + b) * x + c) * x;
        }
    }.f;
    var t = std.math.clamp(progress, 0, 1);
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const x = sample(ax, bx, cx, t) - progress;
        const d = (3 * ax * t + 2 * bx) * t + cx;
        if (@abs(d) < std.math.floatEps(f32)) break;
        t = std.math.clamp(t - x / d, 0, 1);
    }
    if (@abs(sample(ax, bx, cx, t) - progress) > 1e-5 and progress > 0 and progress < 1) {
        var lo: f32 = 0;
        var hi: f32 = 1;
        i = 0;
        while (i < 32) : (i += 1) {
            t = (lo + hi) * 0.5;
            if (sample(ax, bx, cx, t) < progress) lo = t else hi = t;
        }
    }
    return sample(ay, by, cy, t);
}

fn steps(n: u32, pos: computed.StepPos, progress0: f32) f32 {
    const cnt: f32 = @floatFromInt(@max(n, 1));
    const progress = std.math.clamp(progress0, 0, 1);
    const jumps: f32, const off: f32 = switch (pos) {
        .jump_start => .{ cnt, 1 },
        .jump_end => .{ cnt, 0 },
        .jump_both => .{ cnt + 1, 1 },
        .jump_none => .{ @max(cnt - 1, 1), 0 },
    };
    const cur = @floor(progress * cnt + off);
    return std.math.clamp(cur, 0, jumps) / jumps;
}

fn linearCurve(pts: []const [2]f32, p: f32) f32 {
    if (pts.len == 0) return p;
    if (pts.len == 1) return pts[0][1];
    const last = pts.len - 1;
    var start: usize = 0;
    var i: usize = pts.len;
    while (i > 0) {
        i -= 1;
        if (pts[i][0] <= p) {
            start = i;
            break;
        }
    }
    start = @min(start, last - 1);
    const from = pts[start];
    const to = pts[start + 1];
    if (from[0] == to[0]) return to[1];
    return lerp(from[1], to[1], (p - from[0]) / (to[0] - from[0]));
}

// =============================================================================================
// interpolation
// =============================================================================================

fn lerp(x: f32, y: f32, t: f32) f32 {
    return x + (y - x) * t;
}

fn lerpNonNeg(x: f32, y: f32, t: f32) f32 {
    return @max(lerp(x, y, t), 0);
}

fn lerpInt(x: i32, y: i32, t: f32) i32 {
    const v = lerp(@floatFromInt(x), @floatFromInt(y), t);
    return @intFromFloat(std.math.clamp(@round(v), -2147483520.0, 2147483520.0));
}

fn calcOf(arena: Allocator, v: LP) OOM!*const CalcNode {
    if (v.calc) |c| return c;
    const n = try arena.create(CalcNode);
    n.* = .{ .op = .leaf, .px = v.px, .pct = v.pct };
    return n;
}

/// Lerps a `<length-percentage>`. Linear values lerp px and pct; when either side is a calc tree
/// the result is `sum(scale(1-t, A), scale(t, B))` allocated in `arena`.
pub fn lerpLP(arena: Allocator, a: LP, b: LP, t: f32) OOM!LP {
    if (a.calc == null and b.calc == null) return .{ .px = lerp(a.px, b.px, t), .pct = lerp(a.pct, b.pct, t) };
    const ca = try calcOf(arena, a);
    const cb = try calcOf(arena, b);
    const args = try arena.alloc(CalcNode, 2);
    const sa = try arena.alloc(CalcNode, 1);
    const sb = try arena.alloc(CalcNode, 1);
    sa[0] = ca.*;
    sb[0] = cb.*;
    args[0] = .{ .op = .scale, .px = 1 - t, .args = sa };
    args[1] = .{ .op = .scale, .px = t, .args = sb };
    const root = try arena.create(CalcNode);
    root.* = .{ .op = .sum, .args = args };
    return .{ .px = root.eval(0), .calc = root };
}

fn mulDiv255(c: u8, a: u8) u8 {
    const p: u32 = @as(u32, c) * a + 128;
    return @intCast((p + (p >> 8)) >> 8);
}

/// Premultiplied 8-bit sRGB lerp with per-channel rounding, then demultiply (takumi
/// `Color::lerp_premultiplied` + tiny-skia premultiply/demultiply rounding).
pub fn lerpColor(x: Color, y: Color, t: f32) Color {
    if (x.eql(y)) return x;
    if (t <= std.math.floatEps(f32)) return x;
    if (t >= 1 - std.math.floatEps(f32)) return y;
    const xp = [4]u8{ mulDiv255(x.r, x.a), mulDiv255(x.g, x.a), mulDiv255(x.b, x.a), x.a };
    const yp = [4]u8{ mulDiv255(y.r, y.a), mulDiv255(y.g, y.a), mulDiv255(y.b, y.a), y.a };
    var m: [4]u8 = undefined;
    for (0..4) |i| {
        const v = @as(f32, @floatFromInt(xp[i])) * (1 - t) + @as(f32, @floatFromInt(yp[i])) * t;
        m[i] = @intFromFloat(std.math.clamp(@round(v), 0, 255));
    }
    for (0..3) |i| m[i] = @min(m[i], m[3]);
    const a = m[3];
    if (a == 255) return .{ .r = m[0], .g = m[1], .b = m[2], .a = a };
    if (a == 0) return .{};
    const af: f32 = @as(f32, @floatFromInt(a)) / 255.0;
    var out: [3]u8 = undefined;
    for (0..3) |i| {
        const v = @as(f32, @floatFromInt(m[i])) / af + 0.5;
        out[i] = if (v >= 255) 255 else @intFromFloat(v);
    }
    return .{ .r = out[0], .g = out[1], .b = out[2], .a = a };
}

const Cx = struct {
    arena: Allocator,
    a: *const S,
    b: *const S,
    t: f32,

    fn cv(c: *const Cx, x: ColorValue, y: ColorValue) ColorValue {
        if (x == .current and y == .current) return .current;
        return .{ .rgba = lerpColor(x.resolve(c.a.color), y.resolve(c.b.color), c.t) };
    }
    fn lp(c: *const Cx, x: LP, y: LP) OOM!LP {
        return lerpLP(c.arena, x, y, c.t);
    }
    fn lpNonNeg(c: *const Cx, x: LP, y: LP) OOM!LP {
        var v = try c.lp(x, y);
        if (v.calc == null) {
            v.px = @max(v.px, 0);
            v.pct = @max(v.pct, 0);
        }
        return v;
    }
    fn la(c: *const Cx, dst: *values.LengthAuto, x: values.LengthAuto, y: values.LengthAuto) OOM!void {
        if (x == .lp and y == .lp) dst.* = .{ .lp = try c.lp(x.lp, y.lp) };
    }
    fn size(c: *const Cx, dst: *values.Size, x: values.Size, y: values.Size) OOM!void {
        if (x == .lp and y == .lp) dst.* = .{ .lp = try c.lpNonNeg(x.lp, y.lp) };
        if (x == .fit_content_lp and y == .fit_content_lp) dst.* = .{ .fit_content_lp = try c.lpNonNeg(x.fit_content_lp, y.fit_content_lp) };
    }
    fn lp2(c: *const Cx, x: [2]LP, y: [2]LP) OOM![2]LP {
        return .{ try c.lp(x[0], y[0]), try c.lp(x[1], y[1]) };
    }
    fn radius(c: *const Cx, dst: *[2]LP, x: [2]LP, y: [2]LP) OOM!void {
        dst.* = .{ try c.lpNonNeg(x[0], y[0]), try c.lpNonNeg(x[1], y[1]) };
    }
};

fn sideOf(p: Prop) usize {
    return switch (p) {
        .top, .marginTop, .paddingTop, .borderTop, .borderTopColor, .borderTopWidth, .borderTopLeftRadius => 0,
        .right, .marginRight, .paddingRight, .borderRight, .borderRightColor, .borderRightWidth, .borderTopRightRadius => 1,
        .bottom, .marginBottom, .paddingBottom, .borderBottom, .borderBottomColor, .borderBottomWidth, .borderBottomRightRadius => 2,
        else => 3,
    };
}

/// Interpolates the properties in `prop_list` from `a` (t = 0) to `b` (t = 1). The result starts
/// as a copy of `a`; every listed property (shorthands expand to the fields they write) is
/// first switched discretely (`b` when t >= 0.5), then its animatable fields are lerped where
/// both endpoints are compatible (see the file comment). Lists and calc trees of the result are
/// allocated in `arena` (or alias `a`/`b`). Other fields (incl. inherited ones) are those of `a`:
/// interpolating `color`/`fontSize` does not re-derive dependent values.
pub fn interpolate(arena: Allocator, a: *const S, b: *const S, t: f32, prop_list: []const Prop) OOM!S {
    var out = a.*;
    const c: Cx = .{ .arena = arena, .a = a, .b = b, .t = if (t != t) 0 else t };
    for (prop_list) |p| try interpProp(&c, &out, p);
    return out;
}

noinline fn interpProp(c: *const Cx, o: *S, p: Prop) OOM!void {
    const a = c.a;
    const b = c.b;
    const t = c.t;
    props.copyProp(p, o, if (t >= 0.5) b else a);
    switch (p) {
        .width => try c.size(&o.width, a.width, b.width),
        .height => try c.size(&o.height, a.height, b.height),
        .minWidth => try c.size(&o.min_width, a.min_width, b.min_width),
        .minHeight => try c.size(&o.min_height, a.min_height, b.min_height),
        .maxWidth => try c.size(&o.max_width, a.max_width, b.max_width),
        .maxHeight => try c.size(&o.max_height, a.max_height, b.max_height),
        .top, .right, .bottom, .left => {
            const i = sideOf(p);
            try c.la(&o.inset[i], a.inset[i], b.inset[i]);
        },
        .inset => for (0..4) |i| try c.la(&o.inset[i], a.inset[i], b.inset[i]),
        .marginTop, .marginRight, .marginBottom, .marginLeft => {
            const i = sideOf(p);
            try c.la(&o.margin[i], a.margin[i], b.margin[i]);
        },
        .margin => for (0..4) |i| try c.la(&o.margin[i], a.margin[i], b.margin[i]),
        .paddingTop, .paddingRight, .paddingBottom, .paddingLeft => {
            const i = sideOf(p);
            o.padding[i] = try c.lpNonNeg(a.padding[i], b.padding[i]);
        },
        .padding => for (0..4) |i| {
            o.padding[i] = try c.lpNonNeg(a.padding[i], b.padding[i]);
        },
        .gap => {
            o.row_gap = try c.lpNonNeg(a.row_gap, b.row_gap);
            o.column_gap = try c.lpNonNeg(a.column_gap, b.column_gap);
        },
        .rowGap => o.row_gap = try c.lpNonNeg(a.row_gap, b.row_gap),
        .columnGap => o.column_gap = try c.lpNonNeg(a.column_gap, b.column_gap),
        .flexGrow => o.flex_grow = lerpNonNeg(a.flex_grow, b.flex_grow, t),
        .flexShrink => o.flex_shrink = lerpNonNeg(a.flex_shrink, b.flex_shrink, t),
        .flexBasis => if (a.flex_basis == .lp and b.flex_basis == .lp) {
            o.flex_basis = .{ .lp = try c.lpNonNeg(a.flex_basis.lp, b.flex_basis.lp) };
        },
        .flex => {
            o.flex_grow = lerpNonNeg(a.flex_grow, b.flex_grow, t);
            o.flex_shrink = lerpNonNeg(a.flex_shrink, b.flex_shrink, t);
            if (a.flex_basis == .lp and b.flex_basis == .lp) o.flex_basis = .{ .lp = try c.lpNonNeg(a.flex_basis.lp, b.flex_basis.lp) };
        },
        .order => o.order = lerpInt(a.order, b.order, t),
        .zIndex => if (a.z_index != null and b.z_index != null) {
            o.z_index = lerpInt(a.z_index.?, b.z_index.?, t);
        },
        .aspectRatio => if (a.aspect_ratio != null and b.aspect_ratio != null) {
            o.aspect_ratio = lerpNonNeg(a.aspect_ratio.?, b.aspect_ratio.?, t);
        },
        .opacity => o.opacity = std.math.clamp(lerp(a.opacity, b.opacity, t), 0, 1),
        .visibility => if (t > 0 and t < 1 and a.visibility != b.visibility and (a.visibility == .visible or b.visibility == .visible)) {
            o.visibility = .visible;
        },
        .color => o.color = lerpColor(a.color, b.color, t),
        .backgroundColor => o.background_color = c.cv(a.background_color, b.background_color),
        .background => {
            o.background_color = c.cv(a.background_color, b.background_color);
            try bgLists(c, o);
        },
        .backgroundPosition, .backgroundSize => try bgLists(c, o),
        .borderColor => for (0..4) |i| {
            o.border_color[i] = c.cv(a.border_color[i], b.border_color[i]);
        },
        .borderTopColor, .borderRightColor, .borderBottomColor, .borderLeftColor => {
            const i = sideOf(p);
            o.border_color[i] = c.cv(a.border_color[i], b.border_color[i]);
        },
        .borderWidth => for (0..4) |i| {
            o.border_width[i] = lerpNonNeg(a.border_width[i], b.border_width[i], t);
        },
        .borderTopWidth, .borderRightWidth, .borderBottomWidth, .borderLeftWidth => {
            const i = sideOf(p);
            o.border_width[i] = lerpNonNeg(a.border_width[i], b.border_width[i], t);
        },
        .border => for (0..4) |i| {
            o.border_width[i] = lerpNonNeg(a.border_width[i], b.border_width[i], t);
            o.border_color[i] = c.cv(a.border_color[i], b.border_color[i]);
        },
        .borderTop, .borderRight, .borderBottom, .borderLeft => {
            const i = sideOf(p);
            o.border_width[i] = lerpNonNeg(a.border_width[i], b.border_width[i], t);
            o.border_color[i] = c.cv(a.border_color[i], b.border_color[i]);
        },
        .borderRadius => for (0..4) |i| try c.radius(&o.border_radius[i], a.border_radius[i], b.border_radius[i]),
        .borderTopLeftRadius, .borderTopRightRadius, .borderBottomRightRadius, .borderBottomLeftRadius => {
            const i = sideOf(p);
            try c.radius(&o.border_radius[i], a.border_radius[i], b.border_radius[i]);
        },
        .outline => {
            o.outline_width = lerpNonNeg(a.outline_width, b.outline_width, t);
            o.outline_color = c.cv(a.outline_color, b.outline_color);
        },
        .outlineWidth => o.outline_width = lerpNonNeg(a.outline_width, b.outline_width, t),
        .outlineColor => o.outline_color = c.cv(a.outline_color, b.outline_color),
        .outlineOffset => o.outline_offset = lerp(a.outline_offset, b.outline_offset, t),
        .boxShadow => o.box_shadow = try shadowList(c, a.box_shadow, b.box_shadow),
        .textShadow => o.text_shadow = try shadowList(c, a.text_shadow, b.text_shadow),
        .filter => o.filter = try filterList(c, a.filter, b.filter),
        .transform => o.transform = try transformList(c, a.transform, b.transform),
        .translate => o.translate = try c.lp2(a.translate, b.translate),
        .rotate => o.rotate = lerp(a.rotate, b.rotate, t),
        .scale => o.scale = .{ lerp(a.scale[0], b.scale[0], t), lerp(a.scale[1], b.scale[1], t) },
        .transformOrigin => o.transform_origin = try c.lp2(a.transform_origin, b.transform_origin),
        .objectPosition => o.object_position = try c.lp2(a.object_position, b.object_position),
        .fontSize => o.font_size = std.math.clamp(lerp(a.font_size, b.font_size, t), 0, 1.0e6),
        .fontWeight => o.font_weight = lerpWeight(a.font_weight, b.font_weight, t),
        .font => {
            o.font_size = std.math.clamp(lerp(a.font_size, b.font_size, t), 0, 1.0e6);
            o.font_weight = lerpWeight(a.font_weight, b.font_weight, t);
            lineHeight(c, o);
        },
        .lineHeight => lineHeight(c, o),
        .letterSpacing => o.letter_spacing = lerp(a.letter_spacing, b.letter_spacing, t),
        .wordSpacing => o.word_spacing = lerp(a.word_spacing, b.word_spacing, t),
        .textIndent => o.text_indent = try c.lp(a.text_indent, b.text_indent),
        .tabSize => {
            if (a.tab_size == .number and b.tab_size == .number) o.tab_size = .{ .number = lerpNonNeg(a.tab_size.number, b.tab_size.number, t) };
            if (a.tab_size == .px and b.tab_size == .px) o.tab_size = .{ .px = lerpNonNeg(a.tab_size.px, b.tab_size.px, t) };
        },
        .textDecorationColor => o.text_decoration_color = c.cv(a.text_decoration_color, b.text_decoration_color),
        .textDecorationThickness => if (a.text_decoration_thickness != null and b.text_decoration_thickness != null) {
            o.text_decoration_thickness = lerpNonNeg(a.text_decoration_thickness.?, b.text_decoration_thickness.?, t);
        },
        .WebkitTextStrokeWidth => o.webkit_text_stroke_width = lerpNonNeg(a.webkit_text_stroke_width, b.webkit_text_stroke_width, t),
        .WebkitTextStrokeColor => o.webkit_text_stroke_color = c.cv(a.webkit_text_stroke_color, b.webkit_text_stroke_color),
        .WebkitTextStroke => {
            o.webkit_text_stroke_width = lerpNonNeg(a.webkit_text_stroke_width, b.webkit_text_stroke_width, t);
            o.webkit_text_stroke_color = c.cv(a.webkit_text_stroke_color, b.webkit_text_stroke_color);
        },
        else => {}, // discrete (already copied)
    }
}

fn lerpWeight(x: u16, y: u16, t: f32) u16 {
    const v = lerp(@floatFromInt(x), @floatFromInt(y), t);
    return @intFromFloat(std.math.clamp(@round(v), 1, 1000));
}

fn lineHeight(c: *const Cx, o: *S) void {
    const x = c.a.line_height;
    const y = c.b.line_height;
    if (x == .number and y == .number) o.line_height = .{ .number = lerpNonNeg(x.number, y.number, c.t) };
    if (x == .px and y == .px) o.line_height = .{ .px = lerpNonNeg(x.px, y.px, c.t) };
}

/// background-position / background-size: same-length lists lerp item by item (sizes only when
/// both items are explicit `<length-percentage>|auto` pairs of matching variants).
fn bgLists(c: *const Cx, o: *S) OOM!void {
    const a = c.a;
    const b = c.b;
    if (a.background_position.len == b.background_position.len and a.background_position.len > 0) {
        const out = try c.arena.alloc([2]LP, a.background_position.len);
        for (out, a.background_position, b.background_position) |*d, x, y| d.* = try c.lp2(x, y);
        o.background_position = out;
    }
    if (a.background_size.len == b.background_size.len and a.background_size.len > 0) {
        const out = try c.arena.alloc(computed.BgSize, a.background_size.len);
        for (out, a.background_size, b.background_size) |*d, x, y| {
            d.* = if (c.t >= 0.5) y else x;
            if (x == .size and y == .size) {
                var r = d.*.size;
                for (0..2) |k| {
                    if (x.size[k] == .lp and y.size[k] == .lp) {
                        r[k] = .{ .lp = try c.lpNonNeg(x.size[k].lp, y.size[k].lp) };
                    } else r[k] = if (c.t >= 0.5) y.size[k] else x.size[k];
                }
                d.* = .{ .size = r };
            }
        }
        o.background_size = out;
    }
}

fn lerpShadow(c: *const Cx, x: Shadow, y: Shadow) Shadow {
    if (x.inset != y.inset) return if (c.t >= 0.5) y else x;
    const t = c.t;
    return .{
        .x = lerp(x.x, y.x, t),
        .y = lerp(x.y, y.y, t),
        .blur = lerpNonNeg(x.blur, y.blur, t),
        .spread = lerp(x.spread, y.spread, t),
        .color = c.cv(x.color, y.color),
        .inset = x.inset,
    };
}

fn neutralShadow(like: Shadow) Shadow {
    return .{ .inset = like.inset, .color = .{ .rgba = Color.transparent } };
}

fn shadowList(c: *const Cx, xs: []const Shadow, ys: []const Shadow) OOM![]const Shadow {
    const n = @max(xs.len, ys.len);
    if (n == 0) return &.{};
    const out = try c.arena.alloc(Shadow, n);
    for (out, 0..) |*d, i| {
        const x = if (i < xs.len) xs[i] else neutralShadow(ys[i]);
        const y = if (i < ys.len) ys[i] else neutralShadow(xs[i]);
        d.* = lerpShadow(c, x, y);
    }
    return out;
}

fn neutralFilter(like: Filter) Filter {
    return switch (like) {
        .blur => .{ .blur = 0 },
        .brightness => .{ .brightness = 1 },
        .contrast => .{ .contrast = 1 },
        .grayscale => .{ .grayscale = 0 },
        .invert => .{ .invert = 0 },
        .opacity => .{ .opacity = 1 },
        .saturate => .{ .saturate = 1 },
        .sepia => .{ .sepia = 0 },
        .hue_rotate => .{ .hue_rotate = 0 },
        .drop_shadow => |s| .{ .drop_shadow = neutralShadow(s) },
    };
}

fn lerpFilter(c: *const Cx, x: Filter, y: Filter) Filter {
    const t = c.t;
    if (std.meta.activeTag(x) != std.meta.activeTag(y)) return if (t >= 0.5) y else x;
    return switch (x) {
        .blur => |v| .{ .blur = lerpNonNeg(v, y.blur, t) },
        .brightness => |v| .{ .brightness = lerpNonNeg(v, y.brightness, t) },
        .contrast => |v| .{ .contrast = lerpNonNeg(v, y.contrast, t) },
        .saturate => |v| .{ .saturate = lerpNonNeg(v, y.saturate, t) },
        .grayscale => |v| .{ .grayscale = std.math.clamp(lerp(v, y.grayscale, t), 0, 1) },
        .invert => |v| .{ .invert = std.math.clamp(lerp(v, y.invert, t), 0, 1) },
        .opacity => |v| .{ .opacity = std.math.clamp(lerp(v, y.opacity, t), 0, 1) },
        .sepia => |v| .{ .sepia = std.math.clamp(lerp(v, y.sepia, t), 0, 1) },
        .hue_rotate => |v| .{ .hue_rotate = lerp(v, y.hue_rotate, t) },
        .drop_shadow => |v| .{ .drop_shadow = lerpShadow(c, v, y.drop_shadow) },
    };
}

fn filterList(c: *const Cx, xs: []const Filter, ys: []const Filter) OOM![]const Filter {
    const n = @max(xs.len, ys.len);
    if (n == 0) return &.{};
    const out = try c.arena.alloc(Filter, n);
    for (out, 0..) |*d, i| {
        const x = if (i < xs.len) xs[i] else neutralFilter(ys[i]);
        const y = if (i < ys.len) ys[i] else neutralFilter(xs[i]);
        d.* = lerpFilter(c, x, y);
    }
    return out;
}

// ---------------------------------------------------------------- transforms
fn neutralOp(like: TransformOp) TransformOp {
    return switch (like) {
        .translate => .{ .translate = .{ .{}, .{} } },
        .scale => .{ .scale = .{ 1, 1 } },
        .rotate => .{ .rotate = 0 },
        .skew => .{ .skew = .{ 0, 0 } },
        .matrix => .{ .matrix = .{ 1, 0, 0, 1, 0, 0 } },
    };
}

fn transformList(c: *const Cx, xs: []const TransformOp, ys: []const TransformOp) OOM![]const TransformOp {
    const n = @max(xs.len, ys.len);
    if (n == 0) return &.{};
    var matched = true;
    for (0..@min(xs.len, ys.len)) |i| {
        if (std.meta.activeTag(xs[i]) != std.meta.activeTag(ys[i])) matched = false;
    }
    const t = c.t;
    if (matched) {
        const out = try c.arena.alloc(TransformOp, n);
        for (out, 0..) |*d, i| {
            const x = if (i < xs.len) xs[i] else neutralOp(ys[i]);
            const y = if (i < ys.len) ys[i] else neutralOp(xs[i]);
            d.* = switch (x) {
                .translate => |v| .{ .translate = try c.lp2(v, y.translate) },
                .scale => |v| .{ .scale = .{ lerp(v[0], y.scale[0], t), lerp(v[1], y.scale[1], t) } },
                .rotate => |v| .{ .rotate = lerp(v, y.rotate, t) },
                .skew => |v| .{ .skew = .{ lerp(v[0], y.skew[0], t), lerp(v[1], y.skew[1], t) } },
                .matrix => |v| blk: {
                    var m: [6]f32 = undefined;
                    for (0..6) |k| m[k] = lerp(v[k], y.matrix[k], t);
                    break :blk .{ .matrix = m };
                },
            };
        }
        return out;
    }
    // mismatched function kinds: matrix decomposition (needs box-independent lists)
    const ma = toMatrix(xs) orelse return if (t >= 0.5) ys else xs;
    const mb = toMatrix(ys) orelse return if (t >= 0.5) ys else xs;
    const out = try c.arena.alloc(TransformOp, 1);
    out[0] = .{ .matrix = lerpMatrix(ma, mb, t) };
    return out;
}

/// Affine (a b c d e f), column-vector convention: x' = a x + c y + e, y' = b x + d y + f.
const M = [6]f32;
const identity: M = .{ 1, 0, 0, 1, 0, 0 };

fn mul(p: M, q: M) M {
    return .{
        p[0] * q[0] + p[2] * q[1],
        p[1] * q[0] + p[3] * q[1],
        p[0] * q[2] + p[2] * q[3],
        p[1] * q[2] + p[3] * q[3],
        p[0] * q[4] + p[2] * q[5] + p[4],
        p[1] * q[4] + p[3] * q[5] + p[5],
    };
}

const d2r: f32 = std.math.pi / 180.0;

fn rotM(deg: f32) M {
    const sc = sinCos(deg * d2r);
    return .{ sc[1], sc[0], -sc[0], sc[1], 0, 0 };
}

fn tanDeg(deg: f32) f32 {
    const sc = sinCos(deg * d2r);
    if (sc[1] == 0) return 0;
    return sc[0] / sc[1];
}

/// Product of the list's matrices, or null if a translate is box-relative (% or calc).
fn toMatrix(ops: []const TransformOp) ?M {
    var m = identity;
    for (ops) |op| {
        const q: M = switch (op) {
            .translate => |v| blk: {
                if (v[0].pct != 0 or v[1].pct != 0 or v[0].calc != null or v[1].calc != null) return null;
                break :blk .{ 1, 0, 0, 1, v[0].px, v[1].px };
            },
            .scale => |v| .{ v[0], 0, 0, v[1], 0, 0 },
            .rotate => |v| rotM(v),
            .skew => |v| .{ 1, tanDeg(v[1]), tanDeg(v[0]), 1, 0, 0 },
            .matrix => |v| v,
        };
        m = mul(m, q);
    }
    return m;
}

const Decomp = struct { tx: f32, ty: f32, sx: f32, sy: f32, angle: f32, m: [4]f32 };

/// CSS Transforms 1 "Decomposing a 2D matrix" (m11=a, m12=b, m21=c, m22=d, m41=e, m42=f).
fn decompose(m: M) Decomp {
    var row0 = [2]f32{ m[0], m[1] };
    var row1 = [2]f32{ m[2], m[3] };
    var sx = @sqrt(row0[0] * row0[0] + row0[1] * row0[1]);
    var sy = @sqrt(row1[0] * row1[0] + row1[1] * row1[1]);
    const det = row0[0] * row1[1] - row0[1] * row1[0];
    if (det < 0) {
        if (row0[0] < row1[1]) sx = -sx else sy = -sy;
    }
    if (sx != 0) {
        row0[0] /= sx;
        row0[1] /= sx;
    }
    if (sy != 0) {
        row1[0] /= sy;
        row1[1] /= sy;
    }
    var angle = atan2(row0[1], row0[0]);
    if (angle != 0) {
        const sn = -row0[1];
        const cs = row0[0];
        const m11 = row0[0];
        const m12 = row0[1];
        const m21 = row1[0];
        const m22 = row1[1];
        row0[0] = cs * m11 + sn * m21;
        row0[1] = cs * m12 + sn * m22;
        row1[0] = -sn * m11 + cs * m21;
        row1[1] = -sn * m12 + cs * m22;
    }
    angle /= d2r;
    return .{ .tx = m[4], .ty = m[5], .sx = sx, .sy = sy, .angle = angle, .m = .{ row0[0], row0[1], row1[0], row1[1] } };
}

/// translate * matrix(m) * rotate * scale (the inverse of `decompose`).
fn recompose(d: Decomp) M {
    var r: M = .{ 1, 0, 0, 1, d.tx, d.ty };
    r = mul(r, .{ d.m[0], d.m[1], d.m[2], d.m[3], 0, 0 });
    r = mul(r, rotM(d.angle));
    return mul(r, .{ d.sx, 0, 0, d.sy, 0, 0 });
}

fn lerpMatrix(ma: M, mb: M, t: f32) M {
    var x = decompose(ma);
    var y = decompose(mb);
    if ((x.sx < 0 and y.sy < 0) or (x.sy < 0 and y.sx < 0)) {
        x.sx = -x.sx;
        x.sy = -x.sy;
        x.angle += if (x.angle < 0) 180 else -180;
    }
    if (x.angle == 0) x.angle = 360;
    if (y.angle == 0) y.angle = 360;
    if (@abs(x.angle - y.angle) > 180) {
        if (x.angle > y.angle) x.angle -= 360 else y.angle -= 360;
    }
    var r: Decomp = .{
        .tx = lerp(x.tx, y.tx, t),
        .ty = lerp(x.ty, y.ty, t),
        .sx = lerp(x.sx, y.sx, t),
        .sy = lerp(x.sy, y.sy, t),
        .angle = lerp(x.angle, y.angle, t),
        .m = undefined,
    };
    for (0..4) |k| r.m[k] = lerp(x.m[k], y.m[k], t);
    return recompose(r);
}

// ---------------------------------------------------------------- small trig (no libm)
/// [sin x, cos x], |error| < 1e-6 for |x| < 1e5.
fn sinCos(x0: f32) [2]f32 {
    if (!(@abs(x0) < 1.0e6)) return .{ 0, 1 };
    const half_pi: f32 = std.math.pi / 2.0;
    const k = @round(x0 / half_pi);
    // two-step Cody-Waite reduction
    const r = (x0 - k * 1.5703125) - k * 4.8382679e-4;
    const r2 = r * r;
    const s = r * (1 + r2 * (-1.0 / 6.0 + r2 * (1.0 / 120.0 + r2 * (-1.0 / 5040.0 + r2 * (1.0 / 362880.0)))));
    const co = 1 + r2 * (-0.5 + r2 * (1.0 / 24.0 + r2 * (-1.0 / 720.0 + r2 * (1.0 / 40320.0))));
    const q: i32 = @intFromFloat(k - 4 * @floor(k / 4));
    return switch (q) {
        0 => .{ s, co },
        1 => .{ co, -s },
        2 => .{ -s, -co },
        else => .{ -co, s },
    };
}

fn atan(z0: f32) f32 {
    // two half-angle reductions: atan(z) = 2 atan(z / (1 + sqrt(1 + z²)))
    var z = z0;
    var k: u32 = 0;
    while (k < 3) : (k += 1) z = z / (1 + @sqrt(1 + z * z));
    const z2 = z * z;
    const p = z * (1 + z2 * (-1.0 / 3.0 + z2 * (1.0 / 5.0 + z2 * (-1.0 / 7.0 + z2 * (1.0 / 9.0)))));
    return 8 * p;
}

fn atan2(y: f32, x: f32) f32 {
    if (x == 0 and y == 0) return 0;
    const pi: f32 = std.math.pi;
    if (@abs(x) >= @abs(y)) {
        const v = atan(y / x);
        if (x > 0) return v;
        return if (y >= 0) v + pi else v - pi;
    }
    const v = atan(x / y);
    return if (y > 0) pi / 2.0 - v else -pi / 2.0 - v;
}

// =============================================================================================
// tests
// =============================================================================================
const T = std.testing;

test "easing" {
    const ease = TimingFunction.ease;
    try T.expectApproxEqAbs(@as(f32, 0.8024033), easing(ease, 0.5), 1e-4);
    try T.expectEqual(@as(f32, 0), easing(ease, 0));
    try T.expectApproxEqAbs(@as(f32, 1), easing(ease, 1), 1e-6);
    try T.expectApproxEqAbs(@as(f32, 0.3), easing(TimingFunction.linear, 0.3), 1e-6);
    // ease-in-out symmetric
    const eio: TimingFunction = .{ .cubic = .{ 0.42, 0, 0.58, 1 } };
    try T.expectApproxEqAbs(@as(f32, 0.5), easing(eio, 0.5), 1e-4);
    try T.expectApproxEqAbs(1 - easing(eio, 0.2), easing(eio, 0.8), 1e-4);
    // overshoot preserved
    const back: TimingFunction = .{ .cubic = .{ 0.3, 1.5, 0.7, 1.5 } };
    try T.expect(easing(back, 0.7) > 1);
    // steps
    const St = struct { n: u32, pos: computed.StepPos, t: f32, want: f32 };
    const cases = [_]St{
        .{ .n = 4, .pos = .jump_end, .t = 0.0, .want = 0 },     .{ .n = 4, .pos = .jump_end, .t = 0.3, .want = 0.25 },
        .{ .n = 4, .pos = .jump_end, .t = 1.0, .want = 1 },     .{ .n = 4, .pos = .jump_start, .t = 0.0, .want = 0.25 },
        .{ .n = 4, .pos = .jump_start, .t = 0.3, .want = 0.5 }, .{ .n = 3, .pos = .jump_both, .t = 0.0, .want = 0.25 },
        .{ .n = 3, .pos = .jump_both, .t = 0.5, .want = 0.5 },  .{ .n = 3, .pos = .jump_both, .t = 1.0, .want = 1 },
        .{ .n = 3, .pos = .jump_none, .t = 0.0, .want = 0 },    .{ .n = 3, .pos = .jump_none, .t = 0.5, .want = 0.5 },
        .{ .n = 3, .pos = .jump_none, .t = 0.99, .want = 1 },   .{ .n = 1, .pos = .jump_start, .t = 0.1, .want = 1 },
        .{ .n = 2, .pos = .jump_end, .t = -1, .want = 0 },      .{ .n = 2, .pos = .jump_end, .t = 2, .want = 1 },
    };
    for (cases) |cs| {
        const v = easing(.{ .steps = .{ .n = cs.n, .pos = cs.pos } }, cs.t);
        T.expectApproxEqAbs(cs.want, v, 1e-6) catch |e| {
            std.debug.print("steps({d},{s}) at {d} = {d}\n", .{ cs.n, @tagName(cs.pos), cs.t, v });
            return e;
        };
    }
    // linear()
    const pts = [_][2]f32{ .{ 0, 0 }, .{ 0.5, 0.8 }, .{ 0.5, 0.2 }, .{ 1, 1 } };
    const lin: TimingFunction = .{ .linear_points = &pts };
    try T.expectApproxEqAbs(@as(f32, 0.4), easing(lin, 0.25), 1e-6);
    try T.expectApproxEqAbs(@as(f32, 0.6), easing(lin, 0.75), 1e-6);
    try T.expectApproxEqAbs(@as(f32, 0.2), easing(lin, 0.5), 1e-6);
    try T.expectApproxEqAbs(@as(f32, 1.4), easing(lin, 1.25), 1e-5); // extrapolated
    try T.expectApproxEqAbs(@as(f32, -0.4), easing(lin, -0.25), 1e-5);
}

test "trig helpers" {
    var x: f32 = -20;
    while (x < 20) : (x += 0.37) {
        const sc = sinCos(x);
        try T.expectApproxEqAbs(@sin(x), sc[0], 2e-6);
        try T.expectApproxEqAbs(@cos(x), sc[1], 2e-6);
    }
    const pts = [_][2]f32{ .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ -1, 1 }, .{ -1, 0.001 }, .{ -1, -1 }, .{ 0, -2 }, .{ 3, -0.5 }, .{ 0.2, 5 } };
    for (pts) |p| try T.expectApproxEqAbs(std.math.atan2(p[1], p[0]), atan2(p[1], p[0]), 2e-6);
}

fn ts(a: *const S) S {
    return a.*;
}

test "lengths, colours, numbers, discrete" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const ar = arena_state.allocator();
    var a: S = .{};
    var b: S = .{};
    a.width = .{ .lp = .{ .px = 10 } };
    b.width = .{ .lp = .{ .px = 30, .pct = 0.5 } };
    a.height = .auto;
    b.height = .{ .lp = .{ .px = 5 } };
    a.opacity = 0;
    b.opacity = 1;
    a.background_color = .{ .rgba = .{ .r = 255, .a = 255 } };
    b.background_color = .{ .rgba = .{ .b = 255, .a = 255 } };
    a.border_color[0] = .current;
    a.color = .{ .g = 255, .a = 255 };
    b.border_color[0] = .{ .rgba = .{ .a = 0 } };
    a.display = .block;
    b.display = .flex;
    a.z_index = 1;
    b.z_index = 4;
    a.font_weight = 400;
    b.font_weight = 700;
    a.visibility = .hidden;
    b.visibility = .visible;
    const list = [_]Prop{ .width, .height, .opacity, .backgroundColor, .borderTopColor, .display, .zIndex, .fontWeight, .visibility };
    const r = try interpolate(ar, &a, &b, 0.25, &list);
    try T.expect(r.width == .lp and r.width.lp.px == 15 and r.width.lp.pct == 0.125);
    try T.expect(r.height == .auto); // auto vs length: discrete, t < 0.5
    try T.expectEqual(@as(f32, 0.25), r.opacity);
    try T.expect(r.background_color.rgba.eql(.{ .r = 191, .b = 64, .a = 255 }));
    // currentColor (green, opaque) -> transparent: premultiplied, rgb kept
    try T.expect(r.border_color[0].rgba.eql(.{ .g = 255, .a = 191 }));
    try T.expect(r.display == .block);
    try T.expectEqual(@as(?i32, 2), r.z_index);
    try T.expectEqual(@as(u16, 475), r.font_weight);
    try T.expect(r.visibility == .visible);
    const r2 = try interpolate(ar, &a, &b, 0.5, &list);
    try T.expect(r2.display == .flex and r2.height == .lp);
    const r0 = try interpolate(ar, &a, &b, 0, &list);
    try T.expect(r0.visibility == .hidden);
    // unlisted props stay as a
    const r3 = try interpolate(ar, &a, &b, 1, &[_]Prop{.opacity});
    try T.expect(r3.display == .block and r3.opacity == 1);
    // colour lerp vectors (premultiplied)
    try T.expect(lerpColor(.{ .r = 255, .a = 255 }, .{ .b = 255 }, 0.5).eql(.{ .r = 255, .a = 128 }));
    try T.expect(lerpColor(.{ .a = 255 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 0.5).eql(.{ .r = 128, .g = 128, .b = 128, .a = 255 }));
}

test "calc lerp" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const ar = arena_state.allocator();
    const args = [_]CalcNode{ .{ .px = 10 }, .{ .pct = 0.5 } };
    const node: CalcNode = .{ .op = .max, .args = &args };
    const x: LP = .{ .px = 10, .calc = &node };
    const y: LP = .{ .px = 20 };
    const v = try lerpLP(ar, x, y, 0.5);
    try T.expect(v.calc != null);
    try T.expectApproxEqAbs(@as(f32, 15), v.resolve(0), 1e-5); // max(10, 0)=10 -> 15
    try T.expectApproxEqAbs(@as(f32, 35), v.resolve(100), 1e-5); // max(10,50)=50 -> 35
}

test "shadows and filters" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const ar = arena_state.allocator();
    var a: S = .{};
    var b: S = .{};
    const sa = [_]Shadow{.{ .x = 0, .y = 0, .blur = 0, .color = .{ .rgba = .{ .a = 255 } } }};
    const sb = [_]Shadow{ .{ .x = 10, .y = 20, .blur = 8, .spread = 2, .color = .{ .rgba = .{ .a = 255 } } }, .{ .x = 4, .inset = true, .color = .{ .rgba = .{ .r = 255, .a = 255 } } } };
    a.box_shadow = &sa;
    b.box_shadow = &sb;
    const fa = [_]Filter{.{ .blur = 2 }};
    const fb = [_]Filter{ .{ .blur = 6 }, .{ .brightness = 2 }, .{ .grayscale = 1 } };
    a.filter = &fa;
    b.filter = &fb;
    const fc = [_]Filter{.{ .sepia = 1 }};
    const r = try interpolate(ar, &a, &b, 0.5, &[_]Prop{ .boxShadow, .filter });
    try T.expectEqual(@as(usize, 2), r.box_shadow.len);
    const s0 = r.box_shadow[0];
    try T.expect(s0.x == 5 and s0.y == 10 and s0.blur == 4 and s0.spread == 1 and !s0.inset);
    const s1 = r.box_shadow[1];
    try T.expect(s1.inset and s1.x == 2 and s1.color.rgba.eql(.{ .r = 255, .a = 128 }));
    try T.expectEqual(@as(usize, 3), r.filter.len);
    try T.expect(r.filter[0].blur == 4 and r.filter[1].brightness == 1.5 and r.filter[2].grayscale == 0.5);
    // kind mismatch per item: discrete
    b.filter = &fc;
    const r2 = try interpolate(ar, &a, &b, 0.4, &[_]Prop{.filter});
    try T.expect(r2.filter[0] == .blur and r2.filter[0].blur == 2);
    // inset mismatch: discrete per item
    const si = [_]Shadow{.{ .x = 8, .inset = true }};
    b.box_shadow = &si;
    const r3 = try interpolate(ar, &a, &b, 0.6, &[_]Prop{.boxShadow});
    try T.expect(r3.box_shadow[0].inset and r3.box_shadow[0].x == 8);
}

fn approxM(x: M, y: M) !void {
    for (0..6) |k| T.expectApproxEqAbs(y[k], x[k], 1e-4) catch |e| {
        std.debug.print("{any} vs {any}\n", .{ x, y });
        return e;
    };
}

test "transforms" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const ar = arena_state.allocator();
    var a: S = .{};
    var b: S = .{};
    // matched lists + none padding
    const tb = [_]TransformOp{ .{ .translate = .{ .{ .px = 10 }, .{ .pct = 1 } } }, .{ .rotate = 90 }, .{ .scale = .{ 3, 3 } } };
    b.transform = &tb;
    var r = try interpolate(ar, &a, &b, 0.5, &[_]Prop{ .transform, .rotate, .translate });
    try T.expectEqual(@as(usize, 3), r.transform.len);
    try T.expect(r.transform[0].translate[0].px == 5 and r.transform[0].translate[1].pct == 0.5);
    try T.expect(r.transform[1].rotate == 45 and r.transform[2].scale[0] == 2);
    // mismatched kinds -> matrix decomposition: rotate(0) vs rotate via matrix
    const ta = [_]TransformOp{.{ .scale = .{ 2, 2 } }};
    const tc = [_]TransformOp{ .{ .rotate = 90 }, .{ .translate = .{ .{ .px = 10 }, .{} } } };
    a.transform = &ta;
    b.transform = &tc;
    r = try interpolate(ar, &a, &b, 0, &[_]Prop{.transform});
    try T.expectEqual(@as(usize, 1), r.transform.len);
    try approxM(r.transform[0].matrix, .{ 2, 0, 0, 2, 0, 0 });
    r = try interpolate(ar, &a, &b, 1, &[_]Prop{.transform});
    try approxM(r.transform[0].matrix, toMatrix(&tc).?);
    r = try interpolate(ar, &a, &b, 0.5, &[_]Prop{.transform});
    // halfway: scale 1.5, rotate 45deg, translate (0, 5)
    const sc = sinCos(std.math.pi / 4.0);
    try approxM(r.transform[0].matrix, .{ 1.5 * sc[1], 1.5 * sc[0], -1.5 * sc[0], 1.5 * sc[1], 0, 5 });
    // decompose/recompose round trip incl. skew + mirror
    const ms = [_]M{ .{ 1, 0.5, 0.3, 2, 7, -3 }, .{ -1, 0, 0, 1, 0, 0 }, .{ 0.2, -1.3, 0.9, 0.4, 1, 2 } };
    for (ms) |m| try approxM(recompose(decompose(m)), m);
    // % translate in a mismatched list -> discrete
    const tp = [_]TransformOp{.{ .translate = .{ .{ .pct = 0.5 }, .{} } }};
    b.transform = &tp;
    const ts2 = [_]TransformOp{.{ .rotate = 10 }};
    a.transform = &ts2;
    r = try interpolate(ar, &a, &b, 0.3, &[_]Prop{.transform});
    try T.expect(r.transform[0] == .rotate);
}

test "fuzz: interpolate all props" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const ar = arena_state.allocator();
    var a: S = .{};
    var b: S = .{};
    a.width = .{ .lp = .{ .px = 1 } };
    b.width = .{ .lp = .{ .px = 3 } };
    const all = std.enums.values(Prop);
    const ts_ = [_]f32{ -0.5, 0, 0.3, 0.5, 1, 1.7, std.math.nan(f32), std.math.inf(f32) };
    for (ts_) |t| _ = try interpolate(ar, &a, &b, t, all);
}
