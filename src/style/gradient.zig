//! Gradients (linear/radial/conic, repeating-*) and `<image>` values, plus the stop fix-up helper.
const std = @import("std");
const tok = @import("tokenizer.zig");
const values = @import("values.zig");
const colorm = @import("color.zig");
const Error = tok.Error;
const Token = tok.Token;
const Lexer = tok.Lexer;
const LP = values.LP;
const Env = values.Env;
const Color = colorm.Color;
const ColorValue = colorm.ColorValue;

/// One entry of a gradient's stop list. Positions are kept unresolved.
/// For conic gradients `pos.px` holds DEGREES and `pos.pct` a fraction of a full turn, so
/// `resolveStops(.., 360, ..)` yields degrees.
pub const Stop = struct {
    color: ColorValue = .{ .rgba = .{} },
    pos: ?LP = null,
    /// Colour hint (`red, 30%, blue`): `color` is unused, `pos` is always set.
    hint: bool = false,
};

pub const Kind = enum(u8) { linear, radial, conic };
pub const Shape = enum(u8) { ellipse, circle };
pub const Extent = enum(u8) { farthest_corner, closest_side, closest_corner, farthest_side, explicit };

pub const Gradient = struct {
    kind: Kind,
    repeating: bool = false,
    /// linear: gradient-line angle in degrees (CSS convention: 0 = to top, 90 = to right, default 180);
    /// ignored when `corner_x != 0` (then it is `to <corner>`, which depends on the box aspect ratio).
    /// conic: the `from` angle in degrees (default 0).
    angle: f32 = 180,
    /// linear `to <corner>`: x -1 = left, +1 = right; y -1 = top, +1 = bottom. Both 0 = use `angle`.
    corner_x: i8 = 0,
    corner_y: i8 = 0,
    /// radial only
    shape: Shape = .ellipse,
    extent: Extent = .farthest_corner,
    /// radial `extent == .explicit`: [rx, ry]; for circles both are the same absolute length.
    radius: [2]LP = .{ .{}, .{} },
    /// radial/conic centre (default 50% 50%).
    position: [2]LP = .{ .{ .pct = 0.5 }, .{ .pct = 0.5 } },
    stops: []const Stop = &.{},
    /// Colour interpolation space. `.srgb` = legacy premultiplied 8-bit sRGB lerp (what
    /// `resolveStops` + the rasterizer do). Default `.srgb`, or `.oklab` when any stop uses a modern
    /// colour function and no `in <space>` is given (takumi `gradient_default`). Use
    /// `resolveGradientStops` to honour it.
    space: InterpSpace = .srgb,
    hue: HueMethod = .shorter,
};

pub const InterpSpace = colorm.Space;
pub const HueMethod = colorm.HueMethod;

/// A `background-image` / `<image>` layer.
pub const Image = union(enum) {
    none,
    /// url() contents with quotes stripped (escapes not processed). May alias the JSON input.
    url: []const u8,
    gradient: *const Gradient,
};

fn ieq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// Parses an `<image>` from a token. Returns null if `t` is not an image.
pub fn image(arena: std.mem.Allocator, t: Token, env: *const Env) Error!?Image {
    if (t.isIdent("none")) return .none;
    if (t.kind != .function) return null;
    if (ieq(t.text, "url")) return .{ .url = stripUrl(t.args) };
    var name = t.text;
    var repeating = false;
    if (name.len > 10 and ieq(name[0..10], "repeating-")) {
        repeating = true;
        name = name[10..];
    }
    const kind: Kind = if (ieq(name, "linear-gradient"))
        .linear
    else if (ieq(name, "radial-gradient"))
        .radial
    else if (ieq(name, "conic-gradient"))
        .conic
    else if (ieq(name, "image-set") or ieq(name, "-webkit-image-set") or ieq(name, "image") or ieq(name, "cross-fade") or ieq(name, "element"))
        return error.InvalidStyleValue
    else
        return null;
    const g = try arena.create(Gradient);
    g.* = try parseGradient(arena, kind, t.args, env);
    g.repeating = repeating;
    return .{ .gradient = g };
}

fn stripUrl(a: []const u8) []const u8 {
    var s = std.mem.trim(u8, a, " \t\r\n");
    if (s.len >= 2 and (s[0] == '"' or s[0] == '\'') and s[s.len - 1] == s[0]) s = s[1 .. s.len - 1];
    return s;
}

fn parseInterpolation(g: *Gradient, l: *Lexer) Error!void {
    const m = colorm.parseInterpolationMethod(l) orelse return error.InvalidStyleValue;
    g.space = m.space;
    g.hue = m.hue;
}

/// Whether the prelude (before the first top-level comma) contains an `in` keyword.
fn hasIn(args: []const u8) bool {
    var l = Lexer.init(args);
    while (true) {
        const t = l.next();
        if (t.kind == .eof or t.kind == .comma) return false;
        if (t.isIdent("in")) return true;
    }
}

fn sideX(t: Token) i8 {
    if (t.isIdent("left")) return -1;
    if (t.isIdent("right")) return 1;
    return 0;
}
fn sideY(t: Token) i8 {
    if (t.isIdent("top")) return -1;
    if (t.isIdent("bottom")) return 1;
    return 0;
}

/// Tries to parse the leading configuration group; returns false if the group is not a config
/// (i.e. it starts with a colour) and leaves `l` untouched in that case.
fn parseConfig(g: *Gradient, l: *Lexer, env: *const Env) Error!bool {
    const first = l.peek();
    if (first.kind == .eof or first.kind == .comma) return error.InvalidStyleValue;
    if ((colorm.fromToken(first)) != null) return false;
    switch (g.kind) {
        .linear => {
            var have_dir = false;
            var have_in = false;
            while (true) {
                const t = l.next();
                if (t.kind == .eof or t.kind == .comma) break;
                if (t.isIdent("in") and !have_in) {
                    try parseInterpolation(g, l);
                    have_in = true;
                } else if (t.isIdent("to") and !have_dir) {
                    have_dir = true;
                    const a = l.next();
                    var x = sideX(a);
                    var y = sideY(a);
                    if (x == 0 and y == 0) return error.InvalidStyleValue;
                    const b = l.peek();
                    const bx = sideX(b);
                    const by = sideY(b);
                    if (bx != 0 or by != 0) {
                        _ = l.next();
                        if ((x != 0 and bx != 0) or (y != 0 and by != 0)) return error.InvalidStyleValue;
                        if (bx != 0) x = bx;
                        if (by != 0) y = by;
                    }
                    if (x != 0 and y != 0) {
                        g.corner_x = x;
                        g.corner_y = y;
                    } else {
                        g.angle = if (y == -1) 0 else if (x == 1) 90 else if (y == 1) 180 else 270;
                    }
                } else if (!have_dir) {
                    g.angle = (values.angle(t, false)) orelse return error.InvalidStyleValue;
                    have_dir = true;
                } else return error.InvalidStyleValue;
            }
        },
        .radial => {
            var have_shape = false;
            var have_extent = false;
            var have_in = false;
            var nlen: usize = 0;
            var lens: [2]LP = undefined;
            while (true) {
                const t = l.next();
                if (t.kind == .eof or t.kind == .comma) break;
                if (t.isIdent("in") and !have_in) {
                    try parseInterpolation(g, l);
                    have_in = true;
                } else if (t.isIdent("at")) {
                    g.position = (values.position(l, env, 4)) orelse return error.InvalidStyleValue;
                    const e = l.next();
                    if (e.isIdent("in") and !have_in) {
                        try parseInterpolation(g, l);
                        const e2 = l.next();
                        if (e2.kind != .eof and e2.kind != .comma) return error.InvalidStyleValue;
                    } else if (e.kind != .eof and e.kind != .comma) return error.InvalidStyleValue;
                    break;
                } else if (!have_shape and (t.isIdent("circle") or t.isIdent("ellipse"))) {
                    g.shape = if (t.isIdent("circle")) .circle else .ellipse;
                    have_shape = true;
                } else if (!have_extent and nlen == 0 and tok.kw(Extent, t) != null and !t.isIdent("explicit")) {
                    g.extent = tok.kw(Extent, t).?;
                    have_extent = true;
                } else if (!have_extent and nlen < 2) {
                    lens[nlen] = (values.lengthPct(t, env)) orelse return error.InvalidStyleValue;
                    nlen += 1;
                    // the two lengths must be adjacent
                    if (nlen == 1) {
                        const p = l.peek();
                        if ((values.lengthPct(p, env)) != null) {
                            _ = l.next();
                            lens[1] = (values.lengthPct(p, env)).?;
                            nlen = 2;
                        }
                        have_extent = true;
                    }
                } else return error.InvalidStyleValue;
            }
            if (nlen == 1) {
                if (have_shape and g.shape == .ellipse) return error.InvalidStyleValue;
                if (lens[0].pct != 0 or lens[0].px < 0) return error.InvalidStyleValue;
                g.shape = .circle;
                g.extent = .explicit;
                g.radius = .{ lens[0], lens[0] };
            } else if (nlen == 2) {
                if (have_shape and g.shape == .circle) return error.InvalidStyleValue;
                if (lens[0].px < 0 or lens[1].px < 0 or lens[0].pct < 0 or lens[1].pct < 0) return error.InvalidStyleValue;
                g.shape = .ellipse;
                g.extent = .explicit;
                g.radius = lens;
            }
        },
        .conic => {
            var have_from = false;
            var have_in = false;
            var have_at = false;
            while (true) {
                const t = l.next();
                if (t.kind == .eof or t.kind == .comma) break;
                if (t.isIdent("in") and !have_in) {
                    try parseInterpolation(g, l);
                    have_in = true;
                } else if (t.isIdent("from") and !have_from and !have_at) {
                    g.angle = (values.angle(l.next(), false)) orelse return error.InvalidStyleValue;
                    have_from = true;
                } else if (t.isIdent("at") and !have_at) {
                    g.position = (values.position(l, env, 4)) orelse return error.InvalidStyleValue;
                    have_at = true;
                } else return error.InvalidStyleValue;
            }
        },
    }
    return true;
}

fn stopPos(kind: Kind, t: Token, env: *const Env) ?LP {
    if (kind == .conic) return values.anglePct(t);
    return values.lengthPct(t, env);
}

fn parseGradient(arena: std.mem.Allocator, kind: Kind, args: []const u8, env: *const Env) Error!Gradient {
    var g: Gradient = .{ .kind = kind, .angle = if (kind == .linear) 180 else 0 };
    var l = Lexer.init(args);
    _ = try parseConfig(&g, &l, env);
    const explicit_space = g.space != .srgb or g.hue != .shorter or hasIn(args);
    var modern = false;
    var stops: tok.List(Stop) = .{};
    var ncolor: usize = 0;
    while (true) {
        const t = l.next();
        if (t.kind == .eof) return error.InvalidStyleValue; // empty stop / trailing comma
        if (colorm.fromToken(t)) |c| {
            modern = modern or colorm.isModernColorToken(t);
            var st: Stop = .{ .color = c };
            const p1 = l.peek();
            if (stopPos(kind, p1, env)) |a| {
                _ = l.next();
                st.pos = a;
                try stops.append(arena, st);
                const p2 = l.peek();
                if (stopPos(kind, p2, env)) |b| {
                    _ = l.next();
                    st.pos = b;
                    try stops.append(arena, st);
                }
            } else try stops.append(arena, st);
            ncolor += 1;
        } else if (stopPos(kind, t, env)) |p| {
            try stops.append(arena, .{ .pos = p, .hint = true });
        } else return error.InvalidStyleValue;
        const sep = l.next();
        if (sep.kind == .eof) break;
        if (sep.kind != .comma) return error.InvalidStyleValue;
        if (stops.items.len > 4096) return error.InvalidStyleValue;
    }
    // takumi accepts a single colour stop and stray hints (they are skipped by resolveStops).
    if (ncolor < 1) return error.InvalidStyleValue;
    g.stops = stops.items;
    if (modern and !explicit_space) g.space = .oklab;
    return g;
}

// ------------------------------------------------------------------ stop fix-up

pub const ResolvedStop = struct { offset_px: f32, color: Color };

/// Straight -> premultiplied, rounding like tiny-skia's `premultiply_u8`.
fn mulDiv255(c: u8, a: u8) u8 {
    const p: u32 = @as(u32, c) * a + 128;
    return @intCast((p + (p >> 8)) >> 8);
}

/// 50% premultiplied mix used for colour hints (takumi `lerp_premultiplied(.., 0.5)` incl. demultiply).
pub fn mixHalfPremultiplied(x: Color, y: Color) Color {
    const xp = [4]u8{ mulDiv255(x.r, x.a), mulDiv255(x.g, x.a), mulDiv255(x.b, x.a), x.a };
    const yp = [4]u8{ mulDiv255(y.r, y.a), mulDiv255(y.g, y.a), mulDiv255(y.b, y.a), y.a };
    var m: [4]u8 = undefined;
    for (0..4) |i| {
        const v = @as(f32, @floatFromInt(xp[i])) * 0.5 + @as(f32, @floatFromInt(yp[i])) * 0.5;
        m[i] = @intFromFloat(std.math.clamp(@round(v), 0, 255));
    }
    for (0..3) |i| m[i] = @min(m[i], m[3]);
    const a = m[3];
    if (a == 255) return .{ .r = m[0], .g = m[1], .b = m[2], .a = a };
    if (a == 0) return .{};
    const af: f64 = @as(f64, @floatFromInt(a)) / 255.0;
    var out: [3]u8 = undefined;
    for (0..3) |i| {
        const v = @as(f64, @floatFromInt(m[i])) / af + 0.5;
        out[i] = if (v >= 255) 255 else @intFromFloat(v);
    }
    return .{ .r = out[0], .g = out[1], .b = out[2], .a = a };
}

/// Resolves stop positions along a gradient line of `line_length` px (360 for conic = degrees),
/// replicating takumi's `ResolvedGradientStop::resolve`: specified positions are clamped to be
/// >= the previous specified one (and >= 0); the first/last unspecified become 0 / line_length;
/// runs of unspecified positions are distributed evenly; a hint becomes a stop at its position
/// whose colour is the 50% premultiplied mix of its neighbours. `current` resolves currentColor.
/// Single-stop lists put the stop at `line_length`. Result allocated in `arena`.
pub fn resolveStops(arena: std.mem.Allocator, stops: []const Stop, line_length: f32, current: Color) Error![]ResolvedStop {
    const undef: f32 = -1;
    const buf = try arena.alloc(ResolvedStop, stops.len);
    var n: usize = 0;
    var last: f32 = 0;
    for (stops, 0..) |s, i| {
        if (!s.hint) {
            const c = s.color.resolve(current);
            if (s.pos) |p| {
                const v = @max(p.resolve(line_length), last);
                last = v;
                buf[n] = .{ .offset_px = v, .color = c };
                n += 1;
            } else {
                buf[n] = .{ .offset_px = undef, .color = c };
                n += 1;
            }
        } else {
            if (n == 0) continue;
            if (i + 1 >= stops.len or stops[i + 1].hint) continue;
            const before = buf[n - 1].color;
            const after = stops[i + 1].color.resolve(current);
            const p = s.pos orelse LP{};
            const v = @max(p.resolve(line_length), last);
            last = v;
            buf[n] = .{ .offset_px = v, .color = mixHalfPremultiplied(before, after) };
            n += 1;
        }
    }
    const r = buf[0..n];
    if (r.len == 0) return r;
    if (r.len == 1) {
        r[0].offset_px = line_length;
        return r;
    }
    if (r[0].offset_px == undef) r[0].offset_px = 0;
    if (r[r.len - 1].offset_px == undef) r[r.len - 1].offset_px = line_length;
    var i: usize = 1;
    while (i < r.len - 1) {
        if (r[i].offset_px != undef) {
            i += 1;
            continue;
        }
        const prev = r[i - 1].offset_px;
        var nx = i + 1;
        while (nx < r.len - 1 and r[nx].offset_px == undef) nx += 1;
        const next_pos = r[nx].offset_px;
        const segs: f32 = @floatFromInt(nx - i + 1);
        const step = (next_pos - prev) / segs;
        var j = i;
        while (j < nx) : (j += 1) r[j].offset_px = prev + step * @as(f32, @floatFromInt(j - i + 1));
        i = nx + 1;
    }
    return r;
}

/// Like `resolveStops`, but honours `g.space`/`g.hue`: for any space other than legacy sRGB each
/// interval between adjacent stops is SUBDIVIDED into intermediate sRGB stops whose colours are
/// computed in that space (takumi samples its gradient LUT with `Color::interpolate` per entry), so
/// a rasterizer that lerps premultiplied sRGB between adjacent stops reproduces the curve to within
/// ~1 level: one stop every 3 px (1 unit = 1 degree for conic), refined to 0.5 px where the
/// midpoint deviates by >= 2 levels; at most 256 pieces per interval and 8192 stops in total (beyond
/// that the plain stops are returned). Hint stops keep takumi's 50% premultiplied-sRGB colour.
pub fn resolveGradientStops(arena: std.mem.Allocator, g: *const Gradient, line_length: f32, current: Color) Error![]ResolvedStop {
    const base = try resolveStops(arena, g.stops, line_length, current);
    if (g.space == .srgb or base.len < 2) return base;
    const step: f32 = if (g.kind == .conic) 1 else 3;
    var out: tok.List(ResolvedStop) = .{};
    try out.append(arena, base[0]);
    for (base[0 .. base.len - 1], base[1..]) |x, y| {
        const d = y.offset_px - x.offset_px;
        const k: usize = if (x.color.eql(y.color) or !(d > 0)) 1 else @intFromFloat(std.math.clamp(@ceil(d / step), 1, 256));
        const inv = 1 / @as(f32, @floatFromInt(k));
        var prev = x;
        var j: usize = 1;
        while (j <= k) : (j += 1) {
            const t = @as(f32, @floatFromInt(j)) * inv;
            const cur: ResolvedStop = if (j == k) y else .{ .offset_px = x.offset_px + d * t, .color = colorm.interpolate(x.color, y.color, t, g.space, g.hue) };
            if (k > 1) {
                // refine where the piece is visibly curved
                const t0 = t - inv;
                const mid = colorm.interpolate(x.color, y.color, t0 + inv * 0.5, g.space, g.hue);
                const lin = mixHalfPremultiplied(prev.color, cur.color);
                if (maxDiff(mid, lin) >= 2) {
                    const m: usize = @intFromFloat(std.math.clamp(@ceil(d * inv / 0.5), 2, 8));
                    const sub = inv / @as(f32, @floatFromInt(m));
                    var q: usize = 1;
                    while (q < m) : (q += 1) {
                        const tq = t0 + sub * @as(f32, @floatFromInt(q));
                        try out.append(arena, .{ .offset_px = x.offset_px + d * tq, .color = colorm.interpolate(x.color, y.color, tq, g.space, g.hue) });
                    }
                }
            }
            try out.append(arena, cur);
            prev = cur;
            if (out.items.len > 8192) return base;
        }
    }
    return out.items;
}

fn maxDiff(a: Color, b: Color) u8 {
    const d = [4]u8{ @max(a.r, b.r) - @min(a.r, b.r), @max(a.g, b.g) - @min(a.g, b.g), @max(a.b, b.b) - @min(a.b, b.b), @max(a.a, b.a) - @min(a.a, b.a) };
    return @max(@max(d[0], d[1]), @max(d[2], d[3]));
}

// ------------------------------------------------------------------ tests
const T = std.testing;

fn parseImg(a: std.mem.Allocator, s: []const u8) !*const Gradient {
    const env: Env = .{ .dpr = 1, .vw = 100, .vh = 100, .em = 16, .rem = 16 };
    var l = Lexer.init(s);
    const img = (try image(a, l.next(), &env)) orelse return error.NotImage;
    try T.expect(l.atEnd());
    return img.gradient;
}

test "linear gradient directions" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try T.expectEqual(@as(f32, 180), (try parseImg(a, "linear-gradient(red, blue)")).angle);
    try T.expectEqual(@as(f32, 135), (try parseImg(a, "linear-gradient(135deg, #f97316, #7c3aed)")).angle);
    try T.expectEqual(@as(f32, 90), (try parseImg(a, "linear-gradient(0.25turn, red, blue)")).angle);
    try T.expectEqual(@as(f32, 0), (try parseImg(a, "linear-gradient(to top, red, blue)")).angle);
    try T.expectEqual(@as(f32, 270), (try parseImg(a, "linear-gradient(to left, red, blue)")).angle);
    try T.expectEqual(@as(f32, 90), (try parseImg(a, "linear-gradient(to right in srgb, red, blue)")).angle);
    try T.expectEqual(@as(f32, 0), (try parseImg(a, "linear-gradient(0, red, blue)")).angle);
    const g = try parseImg(a, "linear-gradient(to bottom left, red, blue)");
    try T.expect(g.corner_x == -1 and g.corner_y == 1);
    const g2 = try parseImg(a, "linear-gradient(to right top, red, blue)");
    try T.expect(g2.corner_x == 1 and g2.corner_y == -1);
    const g3 = try parseImg(a, "repeating-linear-gradient(45deg, red 0 10px, blue 10px 20px)");
    try T.expect(g3.repeating and g3.stops.len == 4);
    try T.expect(g3.stops[1].pos.?.px == 10 and g3.stops[2].pos.?.px == 10);
}

test "gradient stops and hints" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = try parseImg(a, "linear-gradient(red 10%, 30%, rgba(0,0,255,0.5) 50% 60%, currentColor)");
    try T.expectEqual(@as(usize, 5), g.stops.len);
    try T.expect(g.stops[1].hint and g.stops[1].pos.?.pct == 0.3);
    try T.expect(g.stops[2].pos.?.pct == 0.5 and g.stops[3].pos.?.pct == 0.6);
    try T.expect(g.stops[4].color == .current and g.stops[4].pos == null);
    const bad = [_][]const u8{
        "linear-gradient(10%)",
        "linear-gradient(red,, blue)",     "linear-gradient(45deg)",
        "linear-gradient(to middle, red, blue)", "linear-gradient(to left right, red, blue)", "linear-gradient(in srgb longer hue, red, blue)",
        "linear-gradient(in foo, red, blue)", "linear-gradient(in oklch longer, red, blue)", "linear-gradient(in, red, blue)",
        "linear-gradient(red 10px 20px 30px, blue)", "linear-gradient(45, red, blue)", "radial-gradient(circle 10% , red, blue)",
        "radial-gradient(ellipse 10px, red, blue)", "radial-gradient(circle 1px 2px, red, blue)", "conic-gradient(from 10px, red, blue)",
        "linear-gradient(red, blue,)",
    };
    for (bad) |s| {
        if (parseImg(a, s)) |_| {
            std.debug.print("expected failure: {s}\n", .{s});
            return error.TestUnexpectedResult;
        } else |_| {}
    }
}

test "radial and conic" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var g = try parseImg(a, "radial-gradient(red, blue)");
    try T.expect(g.kind == .radial and g.shape == .ellipse and g.extent == .farthest_corner);
    g = try parseImg(a, "radial-gradient(circle, red, blue)");
    try T.expect(g.shape == .circle and g.extent == .farthest_corner);
    g = try parseImg(a, "radial-gradient(closest-side circle at top left, red, blue)");
    try T.expect(g.shape == .circle and g.extent == .closest_side and g.position[0].pct == 0 and g.position[1].pct == 0);
    g = try parseImg(a, "radial-gradient(50px, red, blue)");
    try T.expect(g.shape == .circle and g.extent == .explicit and g.radius[0].px == 50);
    g = try parseImg(a, "radial-gradient(ellipse 50% 20px at 10px 30%, red, blue)");
    try T.expect(g.shape == .ellipse and g.radius[0].pct == 0.5 and g.radius[1].px == 20 and g.position[0].px == 10 and g.position[1].pct == 0.3);
    g = try parseImg(a, "radial-gradient(at right, red, blue)");
    try T.expect(g.position[0].pct == 1 and g.position[1].pct == 0.5);
    g = try parseImg(a, "repeating-radial-gradient(farthest-side, red 0, blue 10px)");
    try T.expect(g.repeating and g.extent == .farthest_side);
    g = try parseImg(a, "conic-gradient(red, blue)");
    try T.expect(g.kind == .conic and g.angle == 0);
    g = try parseImg(a, "conic-gradient(from 90deg at 25% 75%, red 0deg, blue 90deg 50%, green 1turn)");
    try T.expect(g.angle == 90 and g.position[0].pct == 0.25 and g.stops.len == 4);
    try T.expect(g.stops[1].pos.?.px == 90 and g.stops[2].pos.?.pct == 0.5 and g.stops[3].pos.?.px == 360);
    g = try parseImg(a, "repeating-conic-gradient(red 0 15deg, blue 15deg 30deg)");
    try T.expect(g.repeating and g.stops.len == 4);
}

fn expectOffsets(stops_src: []const u8, len: f32, want: []const f32) !void {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = try parseImg(a, stops_src);
    const r = try resolveStops(a, g.stops, len, Color.black);
    if (r.len != want.len) {
        std.debug.print("{s}: {any}\n", .{ stops_src, r });
        return error.TestUnexpectedResult;
    }
    for (r, want) |x, w| if (!std.math.approxEqAbs(f32, x.offset_px, w, 1e-3)) {
        std.debug.print("{s}: {any}\n", .{ stops_src, r });
        return error.TestUnexpectedResult;
    };
}

test "stop fix-up" {
    try expectOffsets("linear-gradient(red, blue 30%, green, yellow)", 100, &.{ 0, 30, 65, 100 });
    try expectOffsets("linear-gradient(red, blue)", 200, &.{ 0, 200 });
    try expectOffsets("linear-gradient(red)", 50, &.{50}); // takumi: single stop sits at the end
    try expectOffsets("linear-gradient(red, 10%, 20%, blue)", 100, &.{ 0, 20, 100 }); // first of two hints skipped
    try expectOffsets("linear-gradient(red 150%, blue)", 100, &.{ 150, 100 }); // takumi: last default not clamped
    try expectOffsets("linear-gradient(red, blue, green)", 100, &.{ 0, 50, 100 });
    try expectOffsets("linear-gradient(red 50%, blue 20%)", 100, &.{ 50, 50 });
    try expectOffsets("linear-gradient(red -20px, blue)", 100, &.{ 0, 100 });
    try expectOffsets("linear-gradient(red 10px, blue, green, white 70px)", 100, &.{ 10, 30, 50, 70 });
    try expectOffsets("linear-gradient(red 20%, 40%, blue)", 100, &.{ 20, 40, 100 });
    try expectOffsets("conic-gradient(red, blue 25%, green 180deg, yellow)", 360, &.{ 0, 90, 180, 360 });
    // hint colour
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = try parseImg(a, "linear-gradient(red, 30%, rgba(0,0,255,0))");
    const r = try resolveStops(a, g.stops, 100, Color.black);
    try T.expectEqual(@as(usize, 3), r.len);
    try T.expectApproxEqAbs(@as(f32, 30), r[1].offset_px, 1e-3);
    try T.expect(r[1].color.eql(.{ .r = 255, .g = 0, .b = 0, .a = 128 }));
    const g2 = try parseImg(a, "linear-gradient(white, 50%, black)");
    const r2 = try resolveStops(a, g2.stops, 10, Color.black);
    try T.expect(r2[1].color.eql(.{ .r = 128, .g = 128, .b = 128, .a = 255 }));
}

test "interpolation space" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { []const u8, InterpSpace, HueMethod }{
        .{ "linear-gradient(red, blue)", .srgb, .shorter },
        .{ "linear-gradient(red, oklch(0.5 0.2 250))", .oklab, .shorter },
        .{ "linear-gradient(lab(50 0 0), blue)", .oklab, .shorter },
        .{ "linear-gradient(color-mix(in srgb, red, blue), blue)", .oklab, .shorter },
        .{ "linear-gradient(in srgb, red, oklch(0.5 0.2 250))", .srgb, .shorter },
        .{ "linear-gradient(to right in oklch longer hue, red, blue)", .oklch, .longer },
        .{ "linear-gradient(in hsl decreasing hue 45deg, red, blue)", .hsl, .decreasing },
        .{ "linear-gradient(in display-p3, red, blue)", .display_p3, .shorter },
        .{ "radial-gradient(circle at 10px 10px in lab, red, blue)", .lab, .shorter },
        .{ "radial-gradient(in srgb-linear circle, red, blue)", .srgb_linear, .shorter },
        .{ "conic-gradient(from 10deg in lch increasing hue, red, blue)", .lch, .increasing },
        .{ "repeating-conic-gradient(red, lch(50 30 20) 10%)", .oklab, .shorter },
    };
    for (cases) |cs| {
        const g = try parseImg(a, cs[0]);
        T.expect(g.space == cs[1] and g.hue == cs[2]) catch |e| {
            std.debug.print("{s}: {} {}\n", .{ cs[0], g.space, g.hue });
            return e;
        };
    }
}

test "resolveGradientStops subdivision" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // legacy: identical to resolveStops
    const g0 = try parseImg(a, "linear-gradient(red, blue)");
    try T.expectEqual(@as(usize, 2), (try resolveGradientStops(a, g0, 300, Color.black)).len);
    // oklab: subdivided, endpoints preserved, offsets increasing, midpoint = oracle colour-mix
    const g = try parseImg(a, "linear-gradient(in oklab, red, blue)");
    const r = try resolveGradientStops(a, g, 300, Color.black);
    try T.expect(r.len >= 100 and r.len < 400);
    try T.expect(r[0].color.eql(.{ .r = 255, .a = 255 }) and r[r.len - 1].color.eql(.{ .b = 255, .a = 255 }));
    try T.expectEqual(@as(f32, 300), r[r.len - 1].offset_px);
    for (r[1..], r[0 .. r.len - 1]) |x, y| try T.expect(x.offset_px > y.offset_px);
    var found = false;
    for (r) |s| if (s.offset_px == 150) {
        try T.expect(s.color.eql(.{ .r = 140, .g = 83, .b = 162, .a = 255 }));
        found = true;
    };
    try T.expect(found);
    // hard stops and equal colours are not subdivided; huge lists fall back to the plain stops
    const g2 = try parseImg(a, "linear-gradient(in oklch, red 50%, blue 50%, blue)");
    try T.expectEqual(@as(usize, 3), (try resolveGradientStops(a, g2, 300, Color.black)).len);
    const g3 = try parseImg(a, "linear-gradient(in oklab, red, blue)");
    const r3 = try resolveGradientStops(a, g3, 1.0e9, Color.black);
    try T.expect(r3.len > 2 and r3.len <= 8193 and r3[r3.len - 1].offset_px == 1.0e9);
    // conic: per-degree steps
    const g4 = try parseImg(a, "conic-gradient(in oklch, red, blue)");
    const r4 = try resolveGradientStops(a, g4, 360, Color.black);
    try T.expect(r4.len > 200);
}
