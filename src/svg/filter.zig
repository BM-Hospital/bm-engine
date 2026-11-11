//! SVG filter effects on premultiplied RGBA8 pixmaps covering the filter region.
//! Supported primitives: feGaussianBlur, feOffset, feFlood, feColorMatrix, feComposite,
//! feMerge, feBlend, feDropShadow, feComponentTransfer. Any other primitive makes `run`
//! return null (the caller then renders the element unfiltered).
//! `color-interpolation-filters` (default linearRGB) is honoured per primitive.
const std = @import("std");
const raster = @import("../raster/raster.zig");
const dom = @import("dom.zig");
const num = @import("num.zig");
const color = @import("color.zig");
const style = @import("style.zig");
const Allocator = std.mem.Allocator;
const Pixmap = raster.Pixmap;
const Affine = raster.Affine;

const MAX_PRIMITIVES = 64;

pub const Input = struct {
    a: Allocator,
    doc: *const dom.Document,
    filter: u32,
    /// SourceGraphic (premultiplied sRGB), covers the filter region.
    src: *const Pixmap,
    /// user space (after primitiveUnits) -> pixmap pixel space
    ctm: Affine,
    /// element bounding box in user space (primitiveUnits="objectBoundingBox")
    bbox: ?raster.Rect,
    /// computed style at the filter element (for color-interpolation-filters / currentColor)
    st: style.Style,
    /// viewport size (percentages of userSpaceOnUse primitive subregions)
    vw: f32 = 100,
    vh: f32 = 100,
};

const Result = struct { name: []const u8, pm: Pixmap, linear: bool };

/// Runs the filter chain; returns the result in sRGB, or null when an unsupported
/// primitive is present.
pub fn run(in: Input) !?Pixmap {
    const doc = in.doc;
    const fnode = &doc.nodes[in.filter];
    const w = in.src.width;
    const h = in.src.height;
    const bbox_units = if (fnode.attr("primitiveUnits")) |u| std.mem.eql(u8, num.trim(u), "objectBoundingBox") else false;
    if (bbox_units and in.bbox == null) return null;
    const sx = num.hypot(in.ctm.a, in.ctm.b) * (if (bbox_units) in.bbox.?.w else 1);
    const sy = num.hypot(in.ctm.c, in.ctm.d) * (if (bbox_units) in.bbox.?.h else 1);

    var results: [MAX_PRIMITIVES]Result = undefined;
    var n_res: usize = 0;
    var prev: ?Result = null;
    var source_alpha: ?Pixmap = null;

    var child = fnode.first_child;
    var count: usize = 0;
    while (child != dom.NONE) : (child = doc.nodes[child].next_sibling) {
        const p = &doc.nodes[child];
        if (!p.tag.isFilterPrimitive()) continue;
        if (count >= MAX_PRIMITIVES) break;
        count += 1;
        var st = in.st;
        st.apply(p);
        const linear = st.linear_rgb_filters;
        const ctx: Ctx = .{
            .in = &in,
            .w = w,
            .h = h,
            .sx = sx,
            .sy = sy,
            .linear = linear,
            .results = results[0..n_res],
            .prev = prev,
            .source_alpha = &source_alpha,
        };
        var out = try Pixmap.init(in.a, w, h);
        switch (p.tag) {
            .feGaussianBlur => {
                const src = try ctx.input(p.attr("in"));
                @memcpy(out.data, src.data);
                const sd = stdDev(p.attr("stdDeviation"));
                try blur(in.a, &out, sd[0] * sx, sd[1] * sy);
            },
            .feOffset => {
                const src = try ctx.input(p.attr("in"));
                offset(&out, &src, attrNum(p, "dx", 0) * sx, attrNum(p, "dy", 0) * sy);
            },
            .feFlood => {
                const c = floodColor(p, &st, linear);
                @memset(out.pixels(), c);
            },
            .feColorMatrix => {
                const src = try ctx.input(p.attr("in"));
                colorMatrix(&out, &src, p);
            },
            .feComponentTransfer => {
                const src = try ctx.input(p.attr("in"));
                componentTransfer(&out, &src, doc, p);
            },
            .feComposite => {
                const a = try ctx.input(p.attr("in"));
                const b = try ctx.input(p.attr("in2"));
                composite(&out, &a, &b, p);
            },
            .feBlend => {
                const a = try ctx.input(p.attr("in"));
                const b = try ctx.input(p.attr("in2"));
                blend(&out, &a, &b, p.attr("mode") orelse "normal");
            },
            .feMerge => {
                var m = p.first_child;
                while (m != dom.NONE) : (m = doc.nodes[m].next_sibling) {
                    const mn = &doc.nodes[m];
                    if (mn.tag != .feMergeNode) continue;
                    const src = try ctx.input(mn.attr("in"));
                    over(&out, &src);
                }
            },
            .feDropShadow => {
                const src = try ctx.input(p.attr("in"));
                const sd = stdDev(p.attr("stdDeviation") orelse "2");
                var sh = try Pixmap.init(in.a, w, h);
                offset(&sh, &src, attrNum(p, "dx", 2) * sx, attrNum(p, "dy", 2) * sy);
                try blur(in.a, &sh, sd[0] * sx, sd[1] * sy);
                const c = floodColor(p, &st, linear);
                // shadow = flood colour * blurred alpha
                const sp = sh.pixels();
                for (sp) |*px| px.* = scale(c, px.* >> 24);
                @memcpy(out.data, sh.data);
                over(&out, &src);
            },
            else => return null,
        }
        // primitive subregion
        if (p.attr("x") != null or p.attr("y") != null or p.attr("width") != null or p.attr("height") != null) {
            clearOutside(&out, ctx.subregion(p));
        }
        const r: Result = .{ .name = p.attr("result") orelse "", .pm = out, .linear = linear };
        if (r.name.len > 0 and n_res < MAX_PRIMITIVES) {
            results[n_res] = r;
            n_res += 1;
        }
        prev = r;
    }
    const last = prev orelse return null;
    if (!last.linear) return last.pm;
    var o = try Pixmap.init(in.a, w, h);
    convert(&o, &last.pm, false);
    return o;
}

const Ctx = struct {
    in: *const Input,
    w: u32,
    h: u32,
    sx: f32,
    sy: f32,
    linear: bool,
    results: []const Result,
    prev: ?Result,
    source_alpha: *?Pixmap,

    /// Input image converted to this primitive's colour space (may alias stored results).
    fn input(c: *const Ctx, ref_in: ?[]const u8) !Pixmap {
        const ref = num.trim(ref_in orelse "");
        var pm: Pixmap = undefined;
        var lin = false;
        if (ref.len == 0) {
            if (c.prev) |p| {
                pm = p.pm;
                lin = p.linear;
            } else pm = c.in.src.*;
        } else if (std.mem.eql(u8, ref, "SourceGraphic")) {
            pm = c.in.src.*;
        } else if (std.mem.eql(u8, ref, "SourceAlpha")) {
            if (c.source_alpha.* == null) {
                var sa = try Pixmap.init(c.in.a, c.w, c.h);
                const s = c.in.src.pixels();
                for (sa.pixels(), 0..) |*d, i| d.* = s[i] & 0xFF000000;
                c.source_alpha.* = sa;
            }
            return c.source_alpha.*.?;
        } else blk: {
            var i = c.results.len;
            while (i > 0) {
                i -= 1;
                if (std.mem.eql(u8, c.results[i].name, ref)) {
                    pm = c.results[i].pm;
                    lin = c.results[i].linear;
                    break :blk;
                }
            }
            // unknown reference: previous result (or the source)
            if (c.prev) |p| {
                pm = p.pm;
                lin = p.linear;
            } else pm = c.in.src.*;
        }
        if (lin == c.linear) return pm;
        var o = try Pixmap.init(c.in.a, c.w, c.h);
        convert(&o, &pm, c.linear);
        return o;
    }

    fn subregion(c: *const Ctx, p: *const dom.Node) raster.IRect {
        const full: raster.IRect = .{ .x = 0, .y = 0, .w = c.w, .h = c.h };
        const inv = c.in.ctm.invert() orelse return full;
        // current region in user space
        const ur = num.transformRect(inv, .{ .x = 0, .y = 0, .w = @floatFromInt(c.w), .h = @floatFromInt(c.h) });
        var rr = ur;
        const doc = c.in.doc;
        const bbox_units = if (doc.nodes[c.in.filter].attr("primitiveUnits")) |u| std.mem.eql(u8, num.trim(u), "objectBoundingBox") else false;
        const vals = [4]?[]const u8{ p.attr("x"), p.attr("y"), p.attr("width"), p.attr("height") };
        for (vals, 0..) |v, i| {
            const s = v orelse continue;
            var f: f32 = undefined;
            if (bbox_units) {
                const bb = c.in.bbox orelse return full;
                const fr = num.parseFraction(s) orelse continue;
                f = switch (i) {
                    0 => bb.x + fr * bb.w,
                    1 => bb.y + fr * bb.h,
                    2 => fr * bb.w,
                    else => fr * bb.h,
                };
            } else {
                const l = num.parseLength(s) orelse continue;
                f = num.resolve(l, if (i % 2 == 0) c.in.vw else c.in.vh, 16);
            }
            switch (i) {
                0 => rr.x = f,
                1 => rr.y = f,
                2 => rr.w = f,
                else => rr.h = f,
            }
        }
        return num.roundOut(num.transformRect(c.in.ctm, rr)).intersect(full);
    }
};

fn attrNum(p: *const dom.Node, name: []const u8, def: f32) f32 {
    return num.parseNumber(p.attr(name) orelse return def) orelse def;
}

fn stdDev(s_in: ?[]const u8) [2]f32 {
    var r: num.Reader = .{ .s = s_in orelse return .{ 0, 0 } };
    const a = r.next() orelse return .{ 0, 0 };
    const b = r.next() orelse a;
    if (!(a >= 0) or !(b >= 0)) return .{ 0, 0 };
    return .{ a, b };
}

fn blur(a: Allocator, pm: *Pixmap, sx: f32, sy: f32) !void {
    // the raster blur is isotropic: anisotropic deviations use their mean
    const s = if (sx > 0 and sy > 0) (sx + sy) / 2 else 0;
    if (!(s > 0)) return;
    try raster.blurPixmap(a, pm, @min(s, 500));
}

fn offset(out: *Pixmap, src: *const Pixmap, dx_f: f32, dy_f: f32) void {
    const w: i64 = out.width;
    const h: i64 = out.height;
    const dx: i64 = @intFromFloat(std.math.clamp(num.rnd(dx_f), -1e6, 1e6));
    const dy: i64 = @intFromFloat(std.math.clamp(num.rnd(dy_f), -1e6, 1e6));
    const s = src.pixels();
    const d = out.pixels();
    var y: i64 = @max(0, dy);
    while (y < @min(h, h + dy)) : (y += 1) {
        const sy = y - dy;
        const x0 = @max(0, dx);
        const x1 = @min(w, w + dx);
        if (x1 <= x0) break;
        const di: usize = @intCast(y * w + x0);
        const si: usize = @intCast(sy * w + x0 - dx);
        const n: usize = @intCast(x1 - x0);
        @memcpy(d[di..][0..n], s[si..][0..n]);
    }
}

fn clearOutside(pm: *Pixmap, r: raster.IRect) void {
    const px = pm.pixels();
    var y: u32 = 0;
    while (y < pm.height) : (y += 1) {
        const row = px[@as(usize, y) * pm.width ..][0..pm.width];
        if (r.isEmpty() or @as(i64, y) < r.y or @as(i64, y) >= r.bottom()) {
            @memset(row, 0);
            continue;
        }
        const x0: usize = @intCast(@max(r.x, 0));
        const x1: usize = @intCast(@min(r.right(), pm.width));
        @memset(row[0..@min(x0, row.len)], 0);
        if (x1 < row.len) @memset(row[x1..], 0);
    }
}

inline fn scale(p: u32, a: u32) u32 {
    var rb = (p & 0x00FF00FF) * a + 0x00800080;
    rb = ((rb + ((rb >> 8) & 0x00FF00FF)) >> 8) & 0x00FF00FF;
    var ga = ((p >> 8) & 0x00FF00FF) * a + 0x00800080;
    ga = (ga + ((ga >> 8) & 0x00FF00FF)) & 0xFF00FF00;
    return rb | ga;
}

fn over(dst: *Pixmap, src: *const Pixmap) void {
    const d = dst.pixels();
    for (src.pixels(), 0..) |s, i| {
        const sa = s >> 24;
        if (sa == 255) {
            d[i] = s;
        } else if (s != 0) d[i] = s +% scale(d[i], 255 - sa);
    }
}

fn floodColor(p: *const dom.Node, st: *const style.Style, linear: bool) u32 {
    var c = raster.Color.black;
    if (p.decl(.flood_color)) |v| {
        if (num.eqlIgnoreCase(num.trim(v), "currentColor")) c = st.color else if (color.parse(v)) |x| c = x;
    }
    if (p.decl(.flood_opacity)) |v| {
        if (style.opacity(v)) |o| c.a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * o + 0.5);
    }
    if (linear) {
        const t = tables();
        c.r = t.to_lin[c.r];
        c.g = t.to_lin[c.g];
        c.b = t.to_lin[c.b];
    }
    return c.premul();
}

// ---- colour space ----------------------------------------------------------------------------

const Tables = struct { to_lin: [256]u8, to_srgb: [256]u8 };

fn tables() Tables {
    var t: Tables = undefined;
    for (0..256) |i| {
        const v = @as(f32, @floatFromInt(i)) / 255;
        const lin = if (v <= 0.04045) v / 12.92 else powf((v + 0.055) / 1.055, 2.4);
        t.to_lin[i] = @intFromFloat(num.rnd(lin * 255));
        const s = if (v <= 0.0031308) v * 12.92 else 1.055 * powf(v, 1.0 / 2.4) - 0.055;
        t.to_srgb[i] = @intFromFloat(num.rnd(std.math.clamp(s, 0, 1) * 255));
    }
    return t;
}

/// Converts premultiplied pixels between sRGB and linearRGB (unpremultiply, map, premultiply).
fn convert(out: *Pixmap, src: *const Pixmap, to_linear: bool) void {
    const t = tables();
    const map = if (to_linear) &t.to_lin else &t.to_srgb;
    const s = src.data;
    const d = out.data;
    var i: usize = 0;
    while (i + 4 <= s.len) : (i += 4) {
        const a: u32 = s[i + 3];
        d[i + 3] = @intCast(a);
        if (a == 0) {
            d[i] = 0;
            d[i + 1] = 0;
            d[i + 2] = 0;
            continue;
        }
        for (0..3) |k| {
            const straight = @min(255, (@as(u32, s[i + k]) * 255 + a / 2) / a);
            d[i + k] = @intCast(raster.div255(@as(u32, map[straight]) * a));
        }
    }
}

pub fn log2f(x: f32) f32 {
    if (!(x > 0)) return -1e30;
    const bits: u32 = @bitCast(x);
    const e: i32 = @as(i32, @intCast(bits >> 23)) - 127;
    const m: f32 = @bitCast((bits & 0x007FFFFF) | 0x3F800000);
    const s = (m - 1) / (m + 1);
    const s2 = s * s;
    const ln = 2 * s * (1 + s2 * (1.0 / 3.0 + s2 * (1.0 / 5.0 + s2 * (1.0 / 7.0 + s2 * (1.0 / 9.0)))));
    return @as(f32, @floatFromInt(e)) + ln * std.math.log2e;
}

pub fn exp2f(y: f32) f32 {
    if (!(y > -126)) return 0;
    if (y > 127) return std.math.inf(f32);
    const k = @floor(y);
    const f = (y - k) * std.math.ln2;
    var term: f32 = 1;
    var sum: f32 = 1;
    var i: u32 = 1;
    while (i < 9) : (i += 1) {
        term *= f / @as(f32, @floatFromInt(i));
        sum += term;
    }
    const ki: i32 = @intFromFloat(k);
    const scale_bits: u32 = @intCast((ki + 127) << 23);
    return sum * @as(f32, @bitCast(scale_bits));
}

pub fn powf(x: f32, y: f32) f32 {
    if (x <= 0) return if (y == 0) 1 else 0;
    return exp2f(y * log2f(x));
}

// ---- per-pixel primitives (unpremultiplied float maths) -------------------------------------

fn load(d: []const u8, i: usize) [4]f32 {
    const a = @as(f32, @floatFromInt(d[i + 3])) / 255;
    if (a == 0) return .{ 0, 0, 0, 0 };
    return .{
        @as(f32, @floatFromInt(d[i])) / 255 / a,
        @as(f32, @floatFromInt(d[i + 1])) / 255 / a,
        @as(f32, @floatFromInt(d[i + 2])) / 255 / a,
        a,
    };
}

fn store(d: []u8, i: usize, v: [4]f32) void {
    const a = std.math.clamp(v[3], 0, 1);
    for (0..3) |k| d[i + k] = @intFromFloat(num.rnd(std.math.clamp(v[k], 0, 1) * a * 255));
    d[i + 3] = @intFromFloat(num.rnd(a * 255));
}

fn colorMatrix(out: *Pixmap, src: *const Pixmap, p: *const dom.Node) void {
    const kind = num.trim(p.attr("type") orelse "matrix");
    var m: [20]f32 = .{ 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0 };
    const vals = p.attr("values");
    if (std.mem.eql(u8, kind, "matrix")) {
        if (vals) |v| {
            var r: num.Reader = .{ .s = v };
            var tmp: [20]f32 = undefined;
            var n: usize = 0;
            while (n < 20) : (n += 1) tmp[n] = r.next() orelse break;
            if (n == 20) m = tmp;
        }
    } else if (std.mem.eql(u8, kind, "saturate")) {
        const s = if (vals) |v| (num.parseNumber(v) orelse 1) else 1;
        m = .{
            0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
            0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
            0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
            0,                 0,                 0,                 1, 0,
        };
    } else if (std.mem.eql(u8, kind, "hueRotate")) {
        const deg = if (vals) |v| (num.parseNumber(v) orelse 0) else 0;
        const sc = raster.sinCos(deg * std.math.pi / 180);
        const s = sc[0];
        const c = sc[1];
        m = .{
            0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
            0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
            0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
            0,                             0,                             0,                             1, 0,
        };
    } else if (std.mem.eql(u8, kind, "luminanceToAlpha")) {
        m = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.2125, 0.7154, 0.0721, 0, 0 };
    }
    const s = src.data;
    var i: usize = 0;
    while (i + 4 <= s.len) : (i += 4) {
        const v = load(s, i);
        var o: [4]f32 = undefined;
        for (0..4) |r| o[r] = m[r * 5] * v[0] + m[r * 5 + 1] * v[1] + m[r * 5 + 2] * v[2] + m[r * 5 + 3] * v[3] + m[r * 5 + 4];
        store(out.data, i, o);
    }
}

fn componentTransfer(out: *Pixmap, src: *const Pixmap, doc: *const dom.Document, p: *const dom.Node) void {
    var luts: [4][256]u8 = undefined;
    for (&luts) |*l| {
        for (l, 0..) |*x, i| x.* = @intCast(i);
    }
    var c = p.first_child;
    while (c != dom.NONE) : (c = doc.nodes[c].next_sibling) {
        const f = &doc.nodes[c];
        const ch: usize = switch (f.tag) {
            .feFuncR => 0,
            .feFuncG => 1,
            .feFuncB => 2,
            .feFuncA => 3,
            else => continue,
        };
        const kind = num.trim(f.attr("type") orelse "identity");
        var tv: [64]f32 = undefined;
        var n: usize = 0;
        if (f.attr("tableValues")) |tvs| {
            var r: num.Reader = .{ .s = tvs };
            while (n < tv.len) : (n += 1) tv[n] = r.next() orelse break;
        }
        const slope = attrNum(f, "slope", 1);
        const icpt = attrNum(f, "intercept", 0);
        const amp = attrNum(f, "amplitude", 1);
        const expo = attrNum(f, "exponent", 1);
        const off = attrNum(f, "offset", 0);
        for (&luts[ch], 0..) |*x, i| {
            const v = @as(f32, @floatFromInt(i)) / 255;
            const o: f32 = if (std.mem.eql(u8, kind, "table") and n > 0) blk: {
                if (n == 1) break :blk tv[0];
                const pos = v * @as(f32, @floatFromInt(n - 1));
                const k: usize = @min(@as(usize, @intFromFloat(pos)), n - 2);
                const fr = pos - @as(f32, @floatFromInt(k));
                break :blk tv[k] + (tv[k + 1] - tv[k]) * fr;
            } else if (std.mem.eql(u8, kind, "discrete") and n > 0) blk: {
                const k: usize = @min(@as(usize, @intFromFloat(v * @as(f32, @floatFromInt(n)))), n - 1);
                break :blk tv[k];
            } else if (std.mem.eql(u8, kind, "linear")) slope * v + icpt else if (std.mem.eql(u8, kind, "gamma")) amp * powf(v, expo) + off else v;
            x.* = @intFromFloat(num.rnd(std.math.clamp(o, 0, 1) * 255));
        }
    }
    const s = src.data;
    const d = out.data;
    var i: usize = 0;
    while (i + 4 <= s.len) : (i += 4) {
        const a: u32 = s[i + 3];
        var st: [4]u8 = .{ 0, 0, 0, @intCast(a) };
        if (a > 0) {
            for (0..3) |k| st[k] = @intCast(@min(255, (@as(u32, s[i + k]) * 255 + a / 2) / a));
        }
        const na: u32 = luts[3][st[3]];
        d[i + 3] = @intCast(na);
        for (0..3) |k| d[i + k] = @intCast(raster.div255(@as(u32, luts[k][st[k]]) * na));
    }
}

fn composite(out: *Pixmap, a: *const Pixmap, b: *const Pixmap, p: *const dom.Node) void {
    const op = num.trim(p.attr("operator") orelse "over");
    const as_ = a.data;
    const bs = b.data;
    const d = out.data;
    if (std.mem.eql(u8, op, "arithmetic")) {
        const k1 = attrNum(p, "k1", 0);
        const k2 = attrNum(p, "k2", 0);
        const k3 = attrNum(p, "k3", 0);
        const k4 = attrNum(p, "k4", 0);
        var i: usize = 0;
        while (i + 4 <= d.len) : (i += 4) {
            var res: [4]f32 = undefined;
            for (0..4) |k| {
                const x = @as(f32, @floatFromInt(as_[i + k])) / 255;
                const y = @as(f32, @floatFromInt(bs[i + k])) / 255;
                res[k] = std.math.clamp(k1 * x * y + k2 * x + k3 * y + k4, 0, 1);
            }
            for (0..3) |k| res[k] = @min(res[k], res[3]);
            for (0..4) |k| d[i + k] = @intFromFloat(num.rnd(res[k] * 255));
        }
        return;
    }
    const sp = a.pixels();
    const dp = b.pixels();
    const o = out.pixels();
    const Op = enum { over, in, out, atop, xor, lighter };
    const kind = std.meta.stringToEnum(Op, op) orelse .over;
    for (o, 0..) |*px, i| {
        const s = sp[i];
        const t = dp[i];
        const sa = s >> 24;
        const ta = t >> 24;
        px.* = switch (kind) {
            .over => s +% scale(t, 255 - sa),
            .in => scale(s, ta),
            .out => scale(s, 255 - ta),
            .atop => scale(s, ta) +% scale(t, 255 - sa),
            .xor => scale(s, 255 - ta) +% scale(t, 255 - sa),
            .lighter => addSat(s, t),
        };
    }
}

fn addSat(a: u32, b: u32) u32 {
    var r: u32 = 0;
    for (0..4) |k| {
        const sh: u5 = @intCast(k * 8);
        r |= @as(u32, @min(255, ((a >> sh) & 255) + ((b >> sh) & 255))) << sh;
    }
    return r;
}

pub const BlendMode = enum { normal, multiply, screen, overlay, darken, lighten, @"color-dodge", @"color-burn", @"hard-light", @"soft-light", difference, exclusion, hue, saturation, color, luminosity, @"plus-lighter" };

pub fn blendMode(s: []const u8) BlendMode {
    return std.meta.stringToEnum(BlendMode, num.trim(s)) orelse .normal;
}

fn blend(out: *Pixmap, a: *const Pixmap, b: *const Pixmap, mode: []const u8) void {
    const m = blendMode(mode);
    var i: usize = 0;
    while (i + 4 <= out.data.len) : (i += 4) {
        blendPx(out.data[i..][0..4], a.data[i..][0..4], b.data[i..][0..4], m);
    }
}

/// W3C blending (separable + non-separable) + source-over of premultiplied `s` onto `t`, into `d`.
fn blendPx(d: *[4]u8, s: *const [4]u8, t: *const [4]u8, m: BlendMode) void {
    if (m == .@"plus-lighter") {
        for (0..4) |k| d[k] = @intCast(@min(255, @as(u32, s[k]) + t[k]));
        return;
    }
    const sa = @as(f32, @floatFromInt(s[3])) / 255;
    const ba = @as(f32, @floatFromInt(t[3])) / 255;
    const ra = sa + ba - sa * ba;
    var csp: [3]f32 = undefined;
    var cbp: [3]f32 = undefined;
    var cs: [3]f32 = undefined;
    var cb: [3]f32 = undefined;
    for (0..3) |k| {
        csp[k] = @as(f32, @floatFromInt(s[k])) / 255;
        cbp[k] = @as(f32, @floatFromInt(t[k])) / 255;
        cs[k] = if (sa > 0) csp[k] / sa else 0;
        cb[k] = if (ba > 0) cbp[k] / ba else 0;
    }
    var bv: [3]f32 = undefined;
    switch (m) {
        .hue => bv = setLum(setSat(cs, sat(cb)), lum(cb)),
        .saturation => bv = setLum(setSat(cb, sat(cs)), lum(cb)),
        .color => bv = setLum(cs, lum(cb)),
        .luminosity => bv = setLum(cb, lum(cs)),
        else => for (0..3) |k| {
            const x = cs[k];
            const y = cb[k];
            bv[k] = switch (m) {
                .multiply => x * y,
                .screen => x + y - x * y,
                .overlay => hard(x, y),
                .darken => @min(x, y),
                .lighten => @max(x, y),
                .@"color-dodge" => if (y == 0) 0 else if (x >= 1) 1 else @min(1, y / (1 - x)),
                .@"color-burn" => if (y >= 1) 1 else if (x <= 0) 0 else 1 - @min(1, (1 - y) / x),
                .@"hard-light" => hard(y, x),
                .@"soft-light" => soft(x, y),
                .difference => @abs(x - y),
                .exclusion => x + y - 2 * x * y,
                else => x,
            };
        },
    }
    var o: [4]u8 = undefined;
    o[3] = @intFromFloat(num.rnd(ra * 255));
    for (0..3) |k| {
        const r = csp[k] * (1 - ba) + cbp[k] * (1 - sa) + sa * ba * bv[k];
        o[k] = @intFromFloat(num.rnd(std.math.clamp(r, 0, ra) * 255));
    }
    d.* = o;
}

fn lum(c: [3]f32) f32 {
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2];
}

fn sat(c: [3]f32) f32 {
    return @max(c[0], @max(c[1], c[2])) - @min(c[0], @min(c[1], c[2]));
}

fn setLum(c_in: [3]f32, l: f32) [3]f32 {
    const d = l - lum(c_in);
    var c: [3]f32 = .{ c_in[0] + d, c_in[1] + d, c_in[2] + d };
    const ll = lum(c);
    const n = @min(c[0], @min(c[1], c[2]));
    const x = @max(c[0], @max(c[1], c[2]));
    for (&c) |*v| {
        if (n < 0 and ll - n > 0) v.* = ll + (v.* - ll) * ll / (ll - n);
        if (x > 1 and x - ll > 0) v.* = ll + (v.* - ll) * (1 - ll) / (x - ll);
    }
    return c;
}

fn setSat(c: [3]f32, s: f32) [3]f32 {
    // indices of max / mid / min
    var hi: usize = 0;
    var lo: usize = 0;
    for (1..3) |k| {
        if (c[k] > c[hi]) hi = k;
        if (c[k] < c[lo]) lo = k;
    }
    if (hi == lo) return .{ 0, 0, 0 };
    const mid = 3 - hi - lo;
    var o: [3]f32 = .{ 0, 0, 0 };
    o[mid] = (c[mid] - c[lo]) * s / (c[hi] - c[lo]);
    o[hi] = s;
    return o;
}

/// Composites the layer `src` (placed at `ox, oy` in `dst`) with a blend mode, opacity and clip.
pub fn blendOnto(dst: *Pixmap, src: *const Pixmap, ox: i32, oy: i32, m: BlendMode, opacity: f32, clip: ?*const raster.ClipMask) void {
    var reg = dst.bounds().intersect(.{ .x = ox, .y = oy, .w = src.width, .h = src.height });
    if (clip) |cl| reg = reg.intersect(cl.bounds);
    if (reg.isEmpty()) return;
    const op: u32 = @intFromFloat(std.math.clamp(opacity, 0, 1) * 255 + 0.5);
    var y = reg.y;
    while (y < reg.bottom()) : (y += 1) {
        var x = reg.x;
        while (x < reg.right()) : (x += 1) {
            var cov = op;
            if (clip) |cl| if (cl.data) |cd| {
                const ci = @as(usize, @intCast(y - cl.bounds.y)) * cl.bounds.w + @as(usize, @intCast(x - cl.bounds.x));
                cov = raster.div255(cov * cd[ci]);
            };
            if (cov == 0) continue;
            const si = (@as(usize, @intCast(y - oy)) * src.width + @as(usize, @intCast(x - ox))) * 4;
            const sp: u32 = @as(*align(1) const u32, @ptrCast(src.data[si..].ptr)).*;
            if (sp == 0) continue;
            const s: [4]u8 = @bitCast(scale(sp, cov));
            const di = (@as(usize, @intCast(y)) * dst.width + @as(usize, @intCast(x))) * 4;
            const d = dst.data[di..][0..4];
            const t = d.*;
            blendPx(d, &s, &t, m);
        }
    }
}

/// hard-light with backdrop `cb` and source `cs` swapped as needed by the caller.
fn hard(cb: f32, cs: f32) f32 {
    return if (cs <= 0.5) cb * 2 * cs else {
        const s2 = 2 * cs - 1;
        return cb + s2 - cb * s2;
    };
}

fn soft(cs: f32, cb: f32) f32 {
    if (cs <= 0.5) return cb - (1 - 2 * cs) * cb * (1 - cb);
    const d = if (cb <= 0.25) ((16 * cb - 12) * cb + 4) * cb else @sqrt(cb);
    return cb + (2 * cs - 1) * (d - cb);
}

test "filter math" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.2140), powf(0.5, 2.2223), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 8), exp2f(3), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -1), log2f(0.5), 1e-5);
    const t = tables();
    try std.testing.expectEqual(@as(u8, 55), t.to_lin[128]);
    try std.testing.expectEqual(@as(u8, 128), t.to_srgb[55]);
}
