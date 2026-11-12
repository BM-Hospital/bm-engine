//! Gradients and patterns as PDF objects, after krilla's `shading_function.rs`,
//! `shading_pattern.rs`, `tiling_pattern.rs` and `mask.rs` (`new_from_shading`):
//!
//! * pad linear and all radial gradients: axial / radial shadings (types 2 / 3) over one
//!   exponential function (two stops) or a stitching function of exponentials;
//! * repeating / reflecting linear gradients and sweep (conic) gradients: function shadings
//!   (type 1) over a PostScript calculator function (type 4) that wraps the coordinate and
//!   picks the stop pair with nested `ifelse`;
//! * stop opacities: the same shading over the opacities in DeviceGray, drawn into a luminosity
//!   soft mask whose bbox is the filled shape;
//! * shading patterns (type 2) carry the matrix from shading space to the page; tiling
//!   patterns (type 1) carry a content stream, opacity folded into the tile.
const std = @import("std");
const w = @import("writer.zig");
const geom = @import("emit_geom.zig");
const sf = @import("emit_surface.zig");

const Allocator = std.mem.Allocator;
const Tf = geom.Tf;
const LRect = geom.LRect;
const Ref = w.Ref;
const Stop = sf.Stop;
const Spread = sf.Spread;
const Ctx = sf.Ctx;

/// krilla `RadialAxialGradient`
pub const RA = struct { coords: [6]f32, radial: bool, stops: []const Stop };

/// krilla `PostScriptGradient`
pub const PS = struct { min: f32, max: f32, cx: f32 = 0, cy: f32 = 0, stops: []const Stop, domain: LRect, spread: Spread, sweep: bool };

pub const Props = union(enum) {
    ra: RA,
    ps: PS,

    pub fn stops(p: Props) []const Stop {
        return switch (p) {
            .ra => |r| r.stops,
            .ps => |s| s.stops,
        };
    }

    /// krilla `single_stop_color`
    pub fn singleStop(p: Props) ?Stop {
        const s = p.stops();
        return if (s.len == 1) s[0] else null;
    }

    fn hash(p: Props, h: *sf.Hasher) void {
        switch (p) {
            .ra => |r| {
                h.u64_(1);
                const n: usize = if (r.radial) 6 else 4;
                for (r.coords[0..n]) |v| h.f(v);
                h.u64_(@intFromBool(r.radial));
                h.stops(r.stops);
            },
            .ps => |s| {
                h.u64_(2);
                h.f(s.min);
                h.f(s.max);
                h.f(s.cx);
                h.f(s.cy);
                h.stops(s.stops);
                h.rect(s.domain);
                h.u64_(@intFromEnum(s.spread));
                h.u64_(@intFromBool(s.sweep));
            },
        }
    }
};

pub const WithTransform = struct { props: Props, transform: Tf };

/// Rust `f32::to_degrees`.
pub fn toDegrees(rad: f32) f32 {
    const k: f32 = 57.2957795130823208767981548141051703;
    return rad * k;
}

fn expandedBbox(bbox: LRect, t: Tf) LRect {
    var b = bbox;
    if (t.invert()) |inv| {
        if (bbox.transform(inv)) |e| b.expand(e);
    }
    return b;
}

/// krilla `GradientPropertiesExt::gradient_properties` for `paint` over a shape of `bbox`.
pub fn properties(a: Allocator, paint: sf.Paint, bbox: LRect) !WithTransform {
    _ = a;
    switch (paint) {
        .linear => |g| {
            if (g.spread == .pad) return .{ .props = .{ .ra = .{ .coords = .{ g.x1, g.y1, g.x2, g.y2, 0, 0 }, .radial = false, .stops = g.stops } }, .transform = g.transform };
            // get_point_ts: rotate the axis onto the x axis
            const dx = g.x2 - g.x1;
            const dy = g.y2 - g.y1;
            const mag2 = dx * dx + dy * dy;
            const dist: f32 = if (std.math.isFinite(mag2)) @sqrt(mag2) else @floatCast(@sqrt(@as(f64, dx) * dx + @as(f64, dy) * dy));
            const angle = toDegrees(std.math.atan2(dy, dx));
            const ts = Tf.rotateAt(angle, g.x1, g.y1);
            const t = g.transform.pre(ts);
            return .{ .props = .{ .ps = .{ .min = g.x1, .max = g.x1 + dist, .stops = g.stops, .domain = expandedBbox(bbox, t), .spread = g.spread, .sweep = false } }, .transform = t };
        },
        .sweep => |g| return .{ .props = .{ .ps = .{ .min = g.start, .max = g.end, .cx = g.cx, .cy = g.cy, .stops = g.stops, .domain = expandedBbox(bbox, g.transform), .spread = g.spread, .sweep = true } }, .transform = g.transform },
        .radial => |g| return .{ .props = .{ .ra = .{ .coords = .{ g.fx, g.fy, g.fr, g.cx, g.cy, g.cr }, .radial = true, .stops = g.stops } }, .transform = g.transform },
        else => unreachable,
    }
}

/// krilla `Mask::new_from_shading`: a luminosity mask of the stop opacities, or null when
/// every stop is opaque.
pub fn maskFromShading(cx: *Ctx, props: Props, transform: Tf, bbox: LRect) ?sf.Mask {
    var any = false;
    for (props.stops()) |s| {
        if (s.opacity != 1) any = true;
    }
    if (!any) return null;
    const sh = regShadingFn(cx, props, true);
    var s = sf.Surface.initStream(cx);
    s.pushTransform(transform);
    s.drawShading(sh);
    s.pop();
    return .{ .stream = s.finish(), .kind = .luminosity, .custom_bbox = bbox };
}

/// krilla `ShadingPattern` (type 2).
pub fn regShadingPattern(cx: *Ctx, props: Props, matrix: Tf) Ref {
    var h = sf.Hasher.init('P');
    props.hash(&h);
    h.tf(matrix);
    const key = h.final();
    if (cx.doc.cacheGet(key)) |r| return r;
    const r = cx.doc.alloc();
    const sh = regShadingFn(cx, props, false);
    const b = cx.doc.beginDict(r, .patterns);
    b.pairName("Type", "Pattern");
    b.pairInt("PatternType", 2);
    b.pairRef("Shading", sh);
    b.key("Matrix");
    b.reals(&matrix.pdf());
    cx.doc.endDict();
    cx.doc.cachePut(key, r);
    return r;
}

/// krilla `ShadingFunction` (the shading dictionary and its functions).
pub fn regShadingFn(cx: *Ctx, props: Props, use_opacities: bool) Ref {
    var h = sf.Hasher.init('S');
    props.hash(&h);
    h.u64_(@intFromBool(use_opacities));
    const key = h.final();
    if (cx.doc.cacheGet(key)) |r| return r;
    const r = cx.doc.alloc();
    const cs = if (use_opacities) "DeviceGray" else "DeviceRGB";
    switch (props) {
        .ra => |ra| {
            const f = axialRadialFunction(cx, ra.stops, use_opacities);
            const b = cx.doc.beginDict(r, .shading_functions);
            b.pairInt("ShadingType", if (ra.radial) 3 else 2);
            b.pairName("ColorSpace", cs);
            b.pairBool("AntiAlias", false);
            b.pairRef("Function", f);
            b.key("Coords");
            b.reals(ra.coords[0..if (ra.radial) 6 else 4]);
            b.key("Extend");
            b.arr();
            b.boolean(true);
            b.boolean(true);
            b.arrEnd();
            cx.doc.endDict();
        },
        .ps => |ps| {
            const f = postScriptFunction(cx, &ps, use_opacities);
            const b = cx.doc.beginDict(r, .shading_functions);
            b.pairInt("ShadingType", 1);
            b.pairName("ColorSpace", cs);
            b.key("Matrix");
            b.reals(&.{ 1, 0, 0, 1, 0, 0 });
            b.pairBool("AntiAlias", false);
            b.pairRef("Function", f);
            b.key("Domain");
            b.reals(&.{ ps.domain.l, ps.domain.r, ps.domain.t, ps.domain.b });
            cx.doc.endDict();
        },
    }
    cx.doc.cachePut(key, r);
    return r;
}

fn comps(s: Stop, use_opacities: bool, out: *[3]f32) []const f32 {
    if (use_opacities) {
        out[0] = s.opacity;
        return out[0..1];
    }
    for (0..3) |i| out[i] = sf.component(s.color[i]);
    return out[0..3];
}

fn exponential(cx: *Ctx, c0: []const f32, c1: []const f32) Ref {
    const r = cx.doc.alloc();
    const b = cx.doc.beginDict(r, .shading_functions);
    b.pairInt("FunctionType", 2);
    b.key("Range");
    b.arr();
    for (c0) |_| {
        b.int(0);
        b.int(1);
    }
    b.arrEnd();
    b.key("C0");
    b.reals(c0);
    b.key("C1");
    b.reals(c1);
    b.key("Domain");
    b.reals(&.{ 0, 1 });
    b.pairReal("N", 1);
    cx.doc.endDict();
    return r;
}

/// krilla `select_axial_radial_function`: stops padded to 0 and 1, one exponential for two
/// stops, otherwise a stitching function.
fn axialRadialFunction(cx: *Ctx, stops_in: []const Stop, use_opacities: bool) Ref {
    var list: std.ArrayList(Stop) = .empty;
    const a = cx.a;
    if (stops_in.len > 0 and stops_in[0].offset != 0) {
        var s = stops_in[0];
        s.offset = 0;
        list.append(a, s) catch return oom(cx);
    }
    list.appendSlice(a, stops_in) catch return oom(cx);
    if (stops_in.len > 0 and stops_in[stops_in.len - 1].offset != 1) {
        var s = stops_in[stops_in.len - 1];
        s.offset = 1;
        list.append(a, s) catch return oom(cx);
    }
    const stops = list.items;
    var b0: [3]f32 = undefined;
    var b1: [3]f32 = undefined;
    if (stops.len == 2) return exponential(cx, comps(stops[0], use_opacities, &b0), comps(stops[1], use_opacities, &b1));
    // stitching
    var fns: std.ArrayList(Ref) = .empty;
    var bounds: std.ArrayList(f32) = .empty;
    var n: usize = 0;
    for (0..stops.len -| 1) |i| {
        bounds.append(a, stops[i + 1].offset) catch return oom(cx);
        const c0 = comps(stops[i], use_opacities, &b0);
        const c1 = comps(stops[i + 1], use_opacities, &b1);
        n = c0.len;
        fns.append(a, exponential(cx, c0, c1)) catch return oom(cx);
    }
    if (bounds.items.len > 0) bounds.items.len -= 1;
    const r = cx.doc.alloc();
    const b = cx.doc.beginDict(r, .shading_functions);
    b.pairInt("FunctionType", 3);
    b.key("Domain");
    b.reals(&.{ 0, 1 });
    b.key("Range");
    b.arr();
    for (0..n) |_| {
        b.int(0);
        b.int(1);
    }
    b.arrEnd();
    b.key("Functions");
    b.refs(fns.items);
    b.key("Bounds");
    b.reals(bounds.items);
    b.key("Encode");
    b.arr();
    for (fns.items) |_| {
        b.int(0);
        b.int(1);
    }
    b.arrEnd();
    cx.doc.endDict();
    return r;
}

fn oom(cx: *Ctx) Ref {
    cx.doc.b.failed = true;
    return cx.doc.alloc();
}

// ---- PostScript calculator functions (pdf-writer `PostScriptOp`)

const Op = union(enum) {
    real: f32,
    int: i32,
    word: []const u8,
    if_: []const Op,
    ifelse: [2][]const Op,
};

const Code = std.ArrayList(Op);

/// pdf-writer `push_decimal`: always with a decimal point.
fn writeDecimal(out: *std.ArrayList(u8), a: Allocator, v: f32) !void {
    if (std.math.isFinite(v) and @trunc(v) == v and @abs(v) < 1.0e15) {
        var t: [24]u8 = undefined;
        if (v == 0 and std.math.signbit(v)) try out.append(a, '-');
        try out.appendSlice(a, w.fmtInt(&t, @intFromFloat(v)));
        try out.appendSlice(a, ".0");
        return;
    }
    var t: [48]u8 = undefined;
    try out.appendSlice(a, w.fmtReal(&t, v));
}

fn writeSlice(out: *std.ArrayList(u8), a: Allocator, ops: []const Op) !void {
    try out.append(a, '{');
    if (ops.len > 1) try out.append(a, ' ');
    for (ops, 0..) |op, i| {
        if (i > 0) try out.append(a, ' ');
        try writeOp(out, a, op);
    }
    if (ops.len > 1) try out.append(a, ' ');
    try out.append(a, '}');
}

fn writeOp(out: *std.ArrayList(u8), a: Allocator, op: Op) error{OutOfMemory}!void {
    switch (op) {
        .real => |v| try writeDecimal(out, a, v),
        .int => |v| {
            var t: [24]u8 = undefined;
            try out.appendSlice(a, w.fmtInt(&t, v));
        },
        .word => |s| try out.appendSlice(a, s),
        .if_ => |ops| {
            try writeSlice(out, a, ops);
            try out.appendSlice(a, " if");
        },
        .ifelse => |p| {
            try writeSlice(out, a, p[0]);
            try out.append(a, ' ');
            try writeSlice(out, a, p[1]);
            try out.appendSlice(a, " ifelse");
        },
    }
}

fn wd(s: []const u8) Op {
    return .{ .word = s };
}

/// krilla `encode_spread_method`
fn encodeSpread(a: Allocator, code: *Code, min: f32, max: f32, spread: Spread) !void {
    if (spread == .pad) return;
    const length = max - min;
    try code.appendSlice(a, &.{ .{ .real = length }, .{ .real = min }, .{ .int = 2 }, wd("index"), .{ .int = 1 }, wd("index"), wd("sub"), wd("dup"), .{ .int = 3 }, wd("index"), wd("div"), wd("floor"), wd("exch"), .{ .int = 1 }, wd("index"), .{ .int = 4 }, wd("index"), wd("mul"), wd("sub"), wd("exch"), wd("cvi"), wd("abs"), .{ .int = 2 }, wd("mod"), .{ .int = 0 }, wd("gt") });
    if (spread == .reflect) {
        const body = try a.dupe(Op, &.{ .{ .int = 2 }, wd("index"), wd("exch"), wd("sub") });
        try code.append(a, .{ .if_ = body });
    } else try code.append(a, wd("pop"));
    try code.appendSlice(a, &.{ wd("add"), .{ .int = 3 }, .{ .int = 1 }, wd("roll"), wd("pop"), wd("pop") });
}

fn stopComps(s: Stop, use_opacities: bool, out: *[3]f32) []const f32 {
    return comps(s, use_opacities, out);
}

fn encodeTwo(a: Allocator, code: *Code, c0: []const f32, c1: []const f32, min: f32, max: f32) !void {
    if (min == max) {
        try code.append(a, wd("pop"));
        for (c0) |v| try code.append(a, .{ .real = v });
        return;
    }
    try code.appendSlice(a, &.{ .{ .real = min }, wd("sub"), .{ .real = max }, .{ .real = min }, wd("sub"), wd("div") });
    for (c0, c1, 0..) |v0, v1, i| {
        try code.appendSlice(a, &.{ .{ .int = @intCast(i) }, wd("index"), .{ .real = v0 }, wd("exch"), .{ .real = v1 }, .{ .real = v0 }, wd("sub"), wd("mul"), wd("add") });
    }
    try code.appendSlice(a, &.{ .{ .int = @intCast(c0.len + 1) }, .{ .int = -1 }, wd("roll"), wd("pop") });
}

fn encodeStopsImpl(a: Allocator, code: *Code, stops: []const Stop, min: f32, max: f32, use_opacities: bool) !void {
    var b0: [3]f32 = undefined;
    var b1: [3]f32 = undefined;
    if (stops.len == 1) {
        for (stopComps(stops[0], use_opacities, &b0)) |v| try code.append(a, .{ .real = v });
        return;
    }
    const length = max - min;
    const smin = min + length * stops[0].offset;
    const smax = min + length * stops[1].offset;
    var if_code: Code = .empty;
    try encodeTwo(a, &if_code, stopComps(stops[0], use_opacities, &b0), stopComps(stops[1], use_opacities, &b1), smin, smax);
    var else_code: Code = .empty;
    try encodeStopsImpl(a, &else_code, stops[1..], min, max, use_opacities);
    try code.appendSlice(a, &.{ wd("dup"), .{ .real = smax }, wd("le"), .{ .ifelse = .{ if_code.items, else_code.items } } });
}

const max_postscript_stops = 97;

/// krilla `encode_postscript_stops`
fn encodeStops(a: Allocator, code: *Code, stops_in: []const Stop, min: f32, max: f32, use_opacities: bool) !void {
    var stops: std.ArrayList(Stop) = .empty;
    if (stops_in.len > max_postscript_stops) {
        // trim_stops: sample every len/97th stop
        const factor = @as(f32, @floatFromInt(stops_in.len)) / @as(f32, max_postscript_stops);
        var cur: f32 = 0;
        while (@as(usize, @intFromFloat(@round(cur))) < stops_in.len) : (cur += factor) {
            try stops.append(a, stops_in[@intFromFloat(@round(cur))]);
        }
    } else try stops.appendSlice(a, stops_in);
    if (stops.items.len > 0) {
        var f = stops.items[0];
        f.offset = 0;
        try stops.insert(a, 0, f);
        var l = stops.items[stops.items.len - 1];
        l.offset = 1;
        try stops.append(a, l);
    }
    try encodeStopsImpl(a, code, stops.items, min, max, use_opacities);
}

fn postScriptFunction(cx: *Ctx, ps: *const PS, use_opacities: bool) Ref {
    const a = cx.a;
    var code: Code = .empty;
    buildCode(a, &code, ps, use_opacities) catch return oom(cx);
    var out: std.ArrayList(u8) = .empty;
    writeSlice(&out, a, code.items) catch return oom(cx);
    const r = cx.doc.alloc();
    cx.postscript = true; // [conformance] krilla `ContainsPostScript`
    const e = cx.doc.encode(out.items, .content);
    const b = cx.doc.beginStream(r, .shading_function_streams, e);
    b.pairInt("FunctionType", 4);
    b.filter(e);
    b.key("Domain");
    b.reals(&.{ ps.domain.l, ps.domain.r, ps.domain.t, ps.domain.b });
    b.key("Range");
    b.arr();
    for (0..if (use_opacities) @as(usize, 1) else 3) |_| {
        b.int(0);
        b.int(1);
    }
    b.arrEnd();
    cx.doc.endDict();
    return r;
}

fn buildCode(a: Allocator, code: *Code, ps: *const PS, use_opacities: bool) !void {
    if (ps.sweep) {
        const body = try a.dupe(Op, &.{ wd("pop"), .{ .real = 0.0001 } });
        try code.appendSlice(a, &.{ .{ .real = ps.cy }, wd("sub"), wd("exch"), .{ .real = ps.cx }, wd("sub"), wd("dup"), wd("dup"), .{ .real = 0.0001 }, wd("lt"), wd("exch"), .{ .real = -0.0001 }, wd("gt"), wd("and"), .{ .if_ = body }, wd("atan") });
    } else try code.append(a, wd("pop"));
    try encodeSpread(a, code, ps.min, ps.max, ps.spread);
    try encodeStops(a, code, ps.stops, ps.min, ps.max, use_opacities);
}

/// krilla `TilingPattern::new` + `serialize`: a translucent tile is wrapped in an opacity group
/// first.
pub fn regTilingPattern(cx: *Ctx, stream_in: *const sf.Stream, matrix: Tf, opacity: f32, width: f32, height: f32) Ref {
    var stream = stream_in.*;
    if (opacity != 1) {
        var s = sf.Surface.initStream(cx);
        s.drawOpacifiedStream(opacity, stream_in);
        stream = s.finish();
    }
    var h = sf.Hasher.init('T');
    h.stream(&stream);
    h.tf(matrix);
    h.f(opacity);
    h.f(width);
    h.f(height);
    const key = h.final();
    if (cx.doc.cacheGet(key)) |r| return r;
    const r = cx.doc.alloc();
    if (stream.limits.q_over) cx.q_over = true;
    const res = stream.res.write(cx.doc);
    const e = cx.doc.encode(stream.content, .content);
    const b = cx.doc.beginStream(r, .pattern_streams, e);
    b.pairName("Type", "Pattern");
    b.pairInt("PatternType", 1);
    b.filter(e);
    if (res) |rr| b.pairRef("Resources", rr) else b.raw("/Resources<<>>");
    b.pairInt("TilingType", 1);
    b.pairInt("PaintType", 1);
    b.pairRect("BBox", .{ 0, 0, width, height });
    b.key("Matrix");
    b.reals(&matrix.pdf());
    b.pairReal("XStep", width - 0);
    b.pairReal("YStep", height - 0);
    cx.doc.endDict();
    cx.doc.cachePut(key, r);
    return r;
}

const testing = std.testing;

test "postscript encoding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    const body = try a.dupe(Op, &.{ wd("pop"), .{ .real = 0.0001 } });
    try writeSlice(&out, a, &.{ .{ .real = 75 }, wd("sub"), .{ .if_ = body }, .{ .real = 5.625 }, .{ .int = -1 } });
    try testing.expectEqualStrings("{ 75.0 sub { pop 0.0001 } if 5.625 -1 }", out.items);
}
