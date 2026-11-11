//! Number / length / list / transform / viewBox parsing and small math helpers (no libm).
const std = @import("std");
const raster = @import("../raster/raster.zig");
const json = @import("../json.zig");
const Affine = raster.Affine;

pub fn isWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '\x0c';
}

pub fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n\x0c");
}

pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// Finite f32 from f64 (clamped to +-1e9; NaN never produced by parseNumber).
pub fn toF32(v: f64) f32 {
    const c = std.math.clamp(v, -1.0e9, 1.0e9);
    return @floatCast(c);
}

/// Sequential number reader for lists separated by whitespace and/or commas.
pub const Reader = struct {
    s: []const u8,
    i: usize = 0,

    pub fn skipSep(r: *Reader) void {
        while (r.i < r.s.len and isWs(r.s[r.i])) r.i += 1;
        if (r.i < r.s.len and r.s[r.i] == ',') r.i += 1;
        while (r.i < r.s.len and isWs(r.s[r.i])) r.i += 1;
    }

    pub fn skipWs(r: *Reader) void {
        while (r.i < r.s.len and isWs(r.s[r.i])) r.i += 1;
    }

    pub fn atEnd(r: *Reader) bool {
        r.skipWs();
        return r.i >= r.s.len;
    }

    pub fn number(r: *Reader) ?f32 {
        r.skipWs();
        const res = json.parseNumber(r.s[r.i..]) orelse return null;
        r.i += res.len;
        // "5." is a valid SVG number
        if (r.i < r.s.len and r.s[r.i] == '.' and (r.i + 1 >= r.s.len or !std.ascii.isDigit(r.s[r.i + 1]))) r.i += 1;
        return toF32(res.value);
    }

    /// number followed by an optional separator
    pub fn next(r: *Reader) ?f32 {
        const v = r.number() orelse return null;
        r.skipSep();
        return v;
    }

    /// Single-character arc flag ('0' / '1').
    pub fn flag(r: *Reader) ?bool {
        r.skipWs();
        if (r.i >= r.s.len) return null;
        const c = r.s[r.i];
        if (c != '0' and c != '1') return null;
        r.i += 1;
        r.skipSep();
        return c == '1';
    }

    /// Identifier [a-zA-Z%]*
    pub fn ident(r: *Reader) []const u8 {
        const st = r.i;
        while (r.i < r.s.len and (std.ascii.isAlphabetic(r.s[r.i]) or r.s[r.i] == '%')) r.i += 1;
        return r.s[st..r.i];
    }
};

pub fn parseNumber(s: []const u8) ?f32 {
    var r: Reader = .{ .s = s };
    const v = r.number() orelse return null;
    if (!r.atEnd()) return null;
    return v;
}

/// Number or percentage -> fraction (`50%` -> 0.5, `0.5` -> 0.5).
pub fn parseFraction(s: []const u8) ?f32 {
    var r: Reader = .{ .s = trim(s) };
    const v = r.number() orelse return null;
    if (r.i < r.s.len and r.s[r.i] == '%') return v / 100;
    return v;
}

pub const Unit = enum { none, px, percent, em, ex, pt, pc, mm, cm, in };

pub const Length = struct {
    v: f32,
    unit: Unit = .none,

    pub fn px(v: f32) Length {
        return .{ .v = v };
    }
};

pub fn parseLength(s: []const u8) ?Length {
    var r: Reader = .{ .s = trim(s) };
    const v = r.number() orelse return null;
    const u = r.ident();
    if (!r.atEnd()) return null;
    return .{ .v = v, .unit = unitOf(u) orelse return null };
}

fn unitOf(u: []const u8) ?Unit {
    if (u.len == 0) return .none;
    const names = [_][]const u8{ "px", "%", "em", "ex", "pt", "pc", "mm", "cm", "in" };
    for (names, 0..) |n, i| if (eqlIgnoreCase(u, n)) return @enumFromInt(i + 1);
    return null;
}

pub const Axis = enum { x, y, other };

/// Resolves a length to user units. `ref` = percentage base, `font_size` for em/ex.
pub fn resolve(l: Length, ref: f32, font_size: f32) f32 {
    return switch (l.unit) {
        .none, .px => l.v,
        .percent => l.v * ref / 100,
        .em => l.v * font_size,
        .ex => l.v * font_size / 2,
        .pt => l.v * 4.0 / 3.0,
        .pc => l.v * 16,
        .mm => l.v * 96.0 / 25.4,
        .cm => l.v * 96.0 / 2.54,
        .in => l.v * 96,
    };
}

/// Parses a transform list (SVG attribute or CSS `transform` property syntax).
/// Returns null on syntax error (the attribute is then ignored, like browsers do).
pub fn parseTransform(s: []const u8) ?Affine {
    var r: Reader = .{ .s = s };
    var m = Affine.identity;
    while (true) {
        r.skipSep();
        if (r.i >= r.s.len) break;
        const name = r.ident();
        r.skipWs();
        if (name.len == 0 or r.i >= r.s.len or r.s[r.i] != '(') return null;
        r.i += 1;
        var a: [6]f32 = undefined;
        var n: usize = 0;
        var angle_unit_rad: f32 = std.math.pi / 180.0;
        while (n < 6) {
            r.skipWs();
            if (r.i < r.s.len and r.s[r.i] == ')') break;
            a[n] = r.number() orelse return null;
            const u = r.ident();
            if (u.len > 0) {
                if (eqlIgnoreCase(u, "rad")) angle_unit_rad = 1 else if (eqlIgnoreCase(u, "turn")) angle_unit_rad = 2 * std.math.pi else if (eqlIgnoreCase(u, "grad")) angle_unit_rad = std.math.pi / 200.0 else if (!eqlIgnoreCase(u, "deg") and !eqlIgnoreCase(u, "px")) return null;
            }
            n += 1;
            r.skipSep();
        }
        r.skipWs();
        if (r.i >= r.s.len or r.s[r.i] != ')') return null;
        r.i += 1;
        const t: Affine = if (std.mem.eql(u8, name, "matrix")) blk: {
            if (n != 6) return null;
            break :blk .{ .a = a[0], .b = a[1], .c = a[2], .d = a[3], .e = a[4], .f = a[5] };
        } else if (std.mem.eql(u8, name, "translate")) blk: {
            if (n < 1 or n > 2) return null;
            break :blk Affine.translate(a[0], if (n == 2) a[1] else 0);
        } else if (std.mem.eql(u8, name, "translateX") and n == 1) Affine.translate(a[0], 0) else if (std.mem.eql(u8, name, "translateY") and n == 1) Affine.translate(0, a[0]) else if (std.mem.eql(u8, name, "scale")) blk: {
            if (n < 1 or n > 2) return null;
            break :blk Affine.scale(a[0], if (n == 2) a[1] else a[0]);
        } else if (std.mem.eql(u8, name, "rotate")) blk: {
            if (n != 1 and n != 3) return null;
            const rot = Affine.rotate(a[0] * angle_unit_rad);
            if (n == 3) break :blk Affine.translate(a[1], a[2]).mul(rot).mul(Affine.translate(-a[1], -a[2]));
            break :blk rot;
        } else if (std.mem.eql(u8, name, "skewX") and n == 1) Affine.skew(a[0] * angle_unit_rad, 0) else if (std.mem.eql(u8, name, "skewY") and n == 1) Affine.skew(0, a[0] * angle_unit_rad) else return null;
        m = m.mul(t);
    }
    if (!m.isFinite()) return null;
    return m;
}

pub fn parseViewBox(s: []const u8) ?[4]f32 {
    var r: Reader = .{ .s = s };
    var v: [4]f32 = undefined;
    for (&v) |*x| x.* = r.next() orelse return null;
    if (!r.atEnd()) return null;
    if (!(v[2] > 0 and v[3] > 0)) return null;
    return v;
}

pub const Align = enum(u8) { none, min, mid, max };
pub const AspectRatio = struct {
    x: Align = .mid,
    y: Align = .mid,
    slice: bool = false,
};

pub fn parseAspectRatio(s_in: ?[]const u8) AspectRatio {
    var s = trim(s_in orelse return .{});
    if (std.mem.startsWith(u8, s, "defer")) s = trim(s[5..]);
    var out: AspectRatio = .{};
    if (std.mem.startsWith(u8, s, "none")) {
        return .{ .x = .none, .y = .none };
    }
    if (s.len >= 8 and s[0] == 'x' and s[4] == 'Y') {
        out.x = alignOf(s[1..4]) orelse return .{};
        out.y = alignOf(s[5..8]) orelse return .{};
        s = trim(s[8..]);
        if (std.mem.eql(u8, s, "slice")) out.slice = true;
    }
    return out;
}

fn alignOf(s: []const u8) ?Align {
    if (std.mem.eql(u8, s, "Min")) return .min;
    if (std.mem.eql(u8, s, "Mid")) return .mid;
    if (std.mem.eql(u8, s, "Max")) return .max;
    return null;
}

/// viewBox -> viewport transform (viewport origin at 0,0, size w x h).
pub fn viewBoxTransform(vb: [4]f32, par: AspectRatio, w: f32, h: f32) Affine {
    var sx = w / vb[2];
    var sy = h / vb[3];
    if (par.x == .none) {
        return .{ .a = sx, .d = sy, .e = -vb[0] * sx, .f = -vb[1] * sy };
    }
    const s = if (par.slice) @max(sx, sy) else @min(sx, sy);
    sx = s;
    sy = s;
    var tx = -vb[0] * s;
    var ty = -vb[1] * s;
    const ew = vb[2] * s;
    const eh = vb[3] * s;
    switch (par.x) {
        .mid => tx += (w - ew) / 2,
        .max => tx += w - ew,
        else => {},
    }
    switch (par.y) {
        .mid => ty += (h - eh) / 2,
        .max => ty += h - eh,
        else => {},
    }
    return .{ .a = sx, .d = sy, .e = tx, .f = ty };
}

// ---- math -------------------------------------------------------------------------------

pub fn atan2(y: f32, x: f32) f32 {
    const ax = @abs(x);
    const ay = @abs(y);
    if (ax == 0 and ay == 0) return 0;
    const mn = @min(ax, ay);
    const mx = @max(ax, ay);
    const a = mn / mx;
    // minimax polynomial for atan on [0,1], |err| < 2e-5 rad
    const s = a * a;
    var r = a * (0.99997726 + s * (-0.33262347 + s * (0.19354346 + s * (-0.11643287 + s * (0.05265332 + s * -0.01172120)))));
    if (ay > ax) r = std.math.pi / 2.0 - r;
    if (x < 0) r = std.math.pi - r;
    if (y < 0) r = -r;
    return r;
}

pub fn hypot(x: f32, y: f32) f32 {
    return @sqrt(x * x + y * y);
}

/// Average scale factor of a transform (sqrt of |det|).
pub fn meanScale(t: Affine) f32 {
    return @sqrt(@abs(t.a * t.d - t.b * t.c));
}

pub fn maxScale(t: Affine) f32 {
    return @max(hypot(t.a, t.b), hypot(t.c, t.d));
}

pub fn finite(v: f32) bool {
    return std.math.isFinite(v);
}

/// Tight device bounds of a user rect under a transform.
pub fn transformRect(t: Affine, r: raster.Rect) raster.Rect {
    const p = [4]raster.Point{
        t.apply(.{ .x = r.x, .y = r.y }),
        t.apply(.{ .x = r.x + r.w, .y = r.y }),
        t.apply(.{ .x = r.x, .y = r.y + r.h }),
        t.apply(.{ .x = r.x + r.w, .y = r.y + r.h }),
    };
    var x0 = p[0].x;
    var y0 = p[0].y;
    var x1 = x0;
    var y1 = y0;
    for (p[1..]) |q| {
        x0 = @min(x0, q.x);
        y0 = @min(y0, q.y);
        x1 = @max(x1, q.x);
        y1 = @max(y1, q.y);
    }
    return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

/// Rounds a float rect out to integer pixels (clamped to +-2^24).
pub fn roundOut(r: raster.Rect) raster.IRect {
    const lim: f32 = 1 << 24;
    const x0 = std.math.clamp(@floor(r.x), -lim, lim);
    const y0 = std.math.clamp(@floor(r.y), -lim, lim);
    const x1 = std.math.clamp(@ceil(r.x + r.w), -lim, lim);
    const y1 = std.math.clamp(@ceil(r.y + r.h), -lim, lim);
    if (!(x1 > x0) or !(y1 > y0)) return raster.IRect.empty;
    return .{ .x = @intFromFloat(x0), .y = @intFromFloat(y0), .w = @intFromFloat(x1 - x0), .h = @intFromFloat(y1 - y0) };
}

test "num" {
    const t = parseTransform("translate(10) rotate(90, 5 5) scale(2)").?;
    const p = t.apply(.{ .x = 1, .y = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 20), p.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 2), p.y, 1e-4);
    try std.testing.expect(parseTransform("rotate(") == null);
    try std.testing.expectEqual(@as(f32, 0.5), parseFraction("50%").?);
    const l = parseLength(" 2em").?;
    try std.testing.expectEqual(@as(f32, 32), resolve(l, 0, 16));
    try std.testing.expect(parseLength("2qq") == null);
    const vb = parseViewBox("0,0 10 20").?;
    try std.testing.expectEqual(@as(f32, 20), vb[3]);
    const vt = viewBoxTransform(.{ 0, 0, 10, 10 }, parseAspectRatio("xMaxYMid slice"), 20, 40);
    try std.testing.expectEqual(@as(f32, 4), vt.a);
    try std.testing.expectEqual(@as(f32, -20), vt.e);
    try std.testing.expectApproxEqAbs(@as(f32, 2.35619), atan2(1, -1), 1e-4);
    var r: Reader = .{ .s = "1.5.5-2e1,3" };
    try std.testing.expectEqual(@as(f32, 1.5), r.next().?);
    try std.testing.expectEqual(@as(f32, 0.5), r.next().?);
    try std.testing.expectEqual(@as(f32, -20), r.next().?);
    try std.testing.expectEqual(@as(f32, 3), r.next().?);
}

/// round-half-up without libm (`@round` lowers to a compiler-rt call on wasm).
pub inline fn rnd(x: f32) f32 {
    return @floor(x + 0.5);
}

/// Floored modulo without libm's fmodf (result in [0, y) for y > 0; NaN-safe -> 0).
pub fn fmod(x: f32, y: f32) f32 {
    const r = x - @floor(x / y) * y;
    return if (std.math.isFinite(r)) r else 0;
}
