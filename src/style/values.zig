//! Numeric value parsing: lengths/percentages (incl. calc/min/max/clamp), numbers, angles,
//! sizes and `<position>`. All absolute lengths come out in DEVICE px.
const std = @import("std");
const tok = @import("tokenizer.zig");
const color = @import("color.zig");

const Token = tok.Token;
const Lexer = tok.Lexer;

/// A linear `<length-percentage>`: `px + pct * reference`. `px` is in device pixels, `pct` is a
/// fraction (50% -> 0.5). `calc(100% - 20px)` = `{ .px = -20, .pct = 1 }`.
pub const LP = struct {
    px: f32 = 0,
    pct: f32 = 0,

    pub fn resolve(v: LP, reference: f32) f32 {
        return v.px + v.pct * reference;
    }
    pub fn fromPx(px: f32) LP {
        return .{ .px = px };
    }
    pub fn fromPct(frac: f32) LP {
        return .{ .pct = frac };
    }
    pub fn eql(a: LP, b: LP) bool {
        return a.px == b.px and a.pct == b.pct;
    }
};

/// `width`/`height`/`min-*`/`max-*` value. For `max-*`, `none` is stored as `.auto`.
pub const Size = union(enum) {
    auto,
    lp: LP,
    min_content,
    max_content,
    fit_content,
    stretch,
};

/// `auto | <length-percentage>` (margins, insets).
pub const LengthAuto = union(enum) {
    auto,
    lp: LP,
};

/// Everything a length needs to resolve to device px at compute time.
pub const Env = struct {
    dpr: f32 = 1,
    vw: f32 = 0, // viewport width, output px
    vh: f32 = 0,
    em: f32 = 16, // font-size the `em` unit refers to (device px)
    rem: f32 = 16, // root font-size (device px)
};

fn ieq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// Device px per unit, or null if `unit` is not a length unit.
const unit_names = "px\x00pt\x00pc\x00in\x00cm\x00mm\x00q\x00em\x00rem\x00ch\x00ex\x00vw\x00vh\x00vmin\x00vmax";
const abs_units = [_]f32{ 1, 4.0 / 3.0, 16, 96, 96.0 / 2.54, 96.0 / 25.4, 96.0 / 101.6 };

pub fn lengthUnit(unit: []const u8, env: *const Env) ?f32 {
    const i = tok.matchPacked(unit, unit_names) orelse return null;
    if (i < abs_units.len) return abs_units[i] * env.dpr;
    return switch (i) {
        7 => env.em,
        8 => env.rem,
        // ch/ex are approximated as 0.5em (no font metrics at style time).
        9, 10 => env.em * 0.5,
        11 => env.vw / 100,
        12 => env.vh / 100,
        13 => @min(env.vw, env.vh) / 100,
        else => @max(env.vw, env.vh) / 100,
    };
}

// ------------------------------------------------------------------ calc
const Dim = enum(u8) { number, length, angle, percent };
const CV = struct { v: f32 = 0, pct: f32 = 0, dim: Dim };

const max_calc_depth = 24;

pub fn isMathFn(t: Token) bool {
    if (t.kind != .function) return false;
    return ieq(t.text, "calc") or ieq(t.text, "min") or ieq(t.text, "max") or ieq(t.text, "clamp") or ieq(t.text, "-webkit-calc");
}

fn finite(x: f32) bool {
    return x == x and @abs(x) <= 3.0e38;
}

fn mathFn(t: Token, env: *const Env, depth: u32) ?CV {
    if (depth > max_calc_depth) return null;
    var l = Lexer.init(t.args);
    if (ieq(t.text, "calc") or ieq(t.text, "-webkit-calc")) {
        const r = sum(&l, env, depth + 1) orelse return null;
        if (!l.atEnd()) return null;
        return r;
    }
    const is_min = ieq(t.text, "min");
    const is_clamp = ieq(t.text, "clamp");
    var args: [3]CV = undefined;
    var n: usize = 0;
    var acc: CV = undefined;
    while (true) {
        const a = sum(&l, env, depth + 1) orelse return null;
        if (n == 0) {
            acc = a;
        } else {
            // comparable: same dimension and same "shape" (all absolute or all pure-percent)
            const ad: Dim = if (a.dim == .percent) .length else a.dim;
            const cd: Dim = if (acc.dim == .percent) .length else acc.dim;
            if (ad != cd) return null;
            if ((a.pct != 0 or acc.pct != 0) and (a.v != 0 or acc.v != 0)) return null;
            if (!is_clamp) {
                const av = a.v + a.pct;
                const cv = acc.v + acc.pct;
                const take = if (is_min) av < cv else av > cv;
                if (take) acc = a;
            }
        }
        if (is_clamp) {
            if (n >= 3) return null;
            args[n] = a;
        }
        n += 1;
        const sep = l.next();
        if (sep.kind == .eof) break;
        if (sep.kind != .comma) return null;
        if (n > 64) return null;
    }
    if (is_clamp) {
        if (n != 3) return null;
        const lo = args[0].v + args[0].pct;
        const mid = args[1].v + args[1].pct;
        const hi = args[2].v + args[2].pct;
        var r = args[1];
        if (mid > hi) r = args[2];
        if (@min(mid, hi) < lo) r = args[0];
        _ = &r;
        return r;
    }
    return acc;
}

fn leaf(t: Token, env: *const Env, depth: u32) ?CV {
    switch (t.kind) {
        .number => return .{ .v = t.num, .dim = .number },
        .percentage => return .{ .pct = t.num / 100, .dim = .percent },
        .dimension => {
            if (lengthUnit(t.text, env)) |f| return .{ .v = t.num * f, .dim = .length };
            if (color.angleFactor(t.text)) |f| return .{ .v = t.num * f, .dim = .angle };
            return null;
        },
        .block => {
            if (depth > max_calc_depth) return null;
            var l = Lexer.init(t.args);
            const r = sum(&l, env, depth + 1) orelse return null;
            if (!l.atEnd()) return null;
            return r;
        },
        .function => {
            if (!isMathFn(t)) return null;
            return mathFn(t, env, depth + 1);
        },
        .ident => {
            if (ieq(t.text, "pi")) return .{ .v = std.math.pi, .dim = .number };
            if (ieq(t.text, "e")) return .{ .v = std.math.e, .dim = .number };
            return null;
        },
        else => return null,
    }
}

fn product(l: *Lexer, env: *const Env, depth: u32) ?CV {
    var a = leaf(l.next(), env, depth) orelse return null;
    var guard: u32 = 0;
    while (true) : (guard += 1) {
        if (guard > 256) return null;
        const p = l.peek();
        const is_mul = p.isDelim('*');
        if (!is_mul and p.kind != .slash) return a;
        _ = l.next();
        const b = leaf(l.next(), env, depth) orelse return null;
        if (is_mul) {
            if (a.dim == .number) {
                const k = a.v;
                a = b;
                a.v *= k;
                a.pct *= k;
            } else if (b.dim == .number) {
                a.v *= b.v;
                a.pct *= b.v;
            } else return null;
        } else {
            if (b.dim != .number or b.v == 0) return null;
            a.v /= b.v;
            a.pct /= b.v;
        }
    }
}

fn sum(l: *Lexer, env: *const Env, depth: u32) ?CV {
    var a = product(l, env, depth) orelse return null;
    var guard: u32 = 0;
    while (true) : (guard += 1) {
        if (guard > 256) return null;
        const p = l.peek();
        const plus = p.isDelim('+');
        if (!plus and !p.isDelim('-')) break;
        _ = l.next();
        const b = product(l, env, depth) orelse return null;
        const s: f32 = if (plus) 1 else -1;
        if ((a.dim == .number) != (b.dim == .number)) return null;
        if (a.dim != .percent and b.dim != .percent and a.dim != b.dim) return null;
        if (a.dim == .percent) a.dim = b.dim;
        a.v += s * b.v;
        a.pct += s * b.pct;
    }
    if (!finite(a.v) or !finite(a.pct)) return null;
    return a;
}

// ------------------------------------------------------------------ public value parsers

/// `<length-percentage>` (unitless numbers are px, as in takumi). Returns null if `t` is not a
/// length-ish token at all; errors on malformed math functions.
pub fn lengthPct(t: Token, env: *const Env) ?LP {
    const v = lengthPctRaw(t, env) orelse return null;
    // Reject absurd magnitudes so layout never sees inf/NaN.
    if (!(@abs(v.px) <= 1.0e9) or !(@abs(v.pct) <= 1.0e7)) return null;
    return v;
}

fn lengthPctRaw(t: Token, env: *const Env) ?LP {
    switch (t.kind) {
        .number => return .{ .px = t.num * env.dpr },
        .percentage => return .{ .pct = t.num / 100 },
        .dimension => {
            const f = lengthUnit(t.text, env) orelse return null;
            return .{ .px = t.num * f };
        },
        .function => {
            if (!isMathFn(t)) return null;
            const r = mathFn(t, env, 0) orelse return null;
            return switch (r.dim) {
                .number => .{ .px = r.v * env.dpr },
                .length, .percent => .{ .px = r.v, .pct = r.pct },
                .angle => null,
            };
        },
        else => return null,
    }
}

/// `<length>` (no percentages).
pub fn length(t: Token, env: *const Env) ?f32 {
    if (t.kind == .percentage) return null;
    const v = lengthPct(t, env) orelse return null;
    if (v.pct != 0) return null;
    return v.px;
}

/// `<number>` (incl. calc() of numbers).
pub fn number(t: Token) ?f32 {
    if (t.kind == .number) return t.num;
    if (t.kind == .function and isMathFn(t)) {
        const env: Env = .{};
        const r = mathFn(t, &env, 0) orelse return null;
        if (r.dim != .number) return null;
        return r.v;
    }
    return null;
}

/// `<number> | <percentage>` -> number (50% -> 0.5).
pub fn numberOrPct(t: Token) ?f32 {
    if (t.kind == .percentage) return t.num / 100;
    return number(t);
}

/// `<integer>`.
pub fn integer(t: Token) ?i32 {
    const v = number(t) orelse return null;
    if (t.kind == .number and !t.int) return null;
    if (@floor(v) != v or @abs(v) > 1.0e9) return null;
    return @intFromFloat(v);
}

/// `<angle>` in degrees (unitless 0 allowed; unitless non-zero accepted as degrees only if `loose`).
pub fn angle(t: Token, loose: bool) ?f32 {
    switch (t.kind) {
        .number => return if (t.num == 0 or loose) t.num else null,
        .dimension => {
            const f = color.angleFactor(t.text) orelse return null;
            return t.num * f;
        },
        .function => {
            if (!isMathFn(t)) return null;
            const env: Env = .{};
            const r = mathFn(t, &env, 0) orelse return null;
            if (r.dim != .angle and !(r.dim == .number and r.v == 0)) return null;
            return r.v;
        },
        else => return null,
    }
}

/// `<angle-percentage>` used by conic stops: returned as LP with `px` = degrees, `pct` = fraction of a turn.
pub fn anglePct(t: Token) ?LP {
    switch (t.kind) {
        .percentage => return .{ .pct = t.num / 100 },
        .function => {
            if (!isMathFn(t)) return null;
            const env: Env = .{};
            const r = mathFn(t, &env, 0) orelse return null;
            if (r.dim == .angle or r.dim == .percent) return .{ .px = r.v, .pct = r.pct };
            if (r.dim == .number and r.v == 0) return .{};
            return null;
        },
        else => return if (angle(t, false)) |d| .{ .px = d } else null,
    }
}

/// width/height/min-*/max-* value.
pub fn size(t: Token, env: *const Env) ?Size {
    if (t.kind == .ident) {
        const s = t.text;
        if (ieq(s, "auto") or ieq(s, "none")) return .auto;
        if (ieq(s, "min-content") or ieq(s, "-webkit-min-content")) return .min_content;
        if (ieq(s, "max-content") or ieq(s, "-webkit-max-content")) return .max_content;
        if (ieq(s, "fit-content") or ieq(s, "-webkit-fit-content")) return .fit_content;
        if (ieq(s, "stretch") or ieq(s, "-webkit-fill-available")) return .stretch;
        return null;
    }
    return if (lengthPct(t, env)) |v| .{ .lp = v } else null;
}

pub fn lengthAuto(t: Token, env: *const Env) ?LengthAuto {
    if (t.isIdent("auto")) return .auto;
    return if (lengthPct(t, env)) |v| .{ .lp = v } else null;
}

// ------------------------------------------------------------------ <position>
pub const PosKw = enum { left, center, right, top, bottom };
const PosItem = union(enum) { kw: PosKw, lp: LP };

fn posItem(t: Token, env: *const Env) ?PosItem {
    if (t.kind == .ident) {
        if (tok.kw(PosKw, t)) |k| return .{ .kw = k };
        return null;
    }
    return if (lengthPct(t, env)) |v| .{ .lp = v } else null;
}

fn kwLP(k: PosKw) LP {
    return switch (k) {
        .left, .top => .{},
        .center => .{ .pct = 0.5 },
        .right, .bottom => .{ .pct = 1 },
    };
}

fn isH(k: PosKw) bool {
    return k == .left or k == .right;
}
fn isV(k: PosKw) bool {
    return k == .top or k == .bottom;
}

/// Parses a `<position>` / `<bg-position>` (1-4 values, `max_items` 2 or 4) from the lexer, consuming
/// only position tokens. Returns null if no position token is next. Result = [x, y].
pub fn position(l: *Lexer, env: *const Env, max_items: usize) ?[2]LP {
    var items: [4]PosItem = undefined;
    var n: usize = 0;
    while (n < max_items) {
        const save = l.*;
        const it = posItem(l.next(), env) orelse {
            l.* = save;
            break;
        };
        items[n] = it;
        n += 1;
    }
    if (n == 0) return null;
    switch (n) {
        1 => switch (items[0]) {
            .lp => |v| return .{ v, .{ .pct = 0.5 } },
            .kw => |k| return if (isV(k)) .{ .{ .pct = 0.5 }, kwLP(k) } else .{ kwLP(k), .{ .pct = 0.5 } },
        },
        2 => {
            const a = items[0];
            const b = items[1];
            // keyword pair in either order
            if (a == .kw and b == .kw) {
                const ka = a.kw;
                const kb = b.kw;
                if (isV(ka) or isH(kb)) {
                    if (isV(kb) or isH(ka)) return null;
                    return .{ kwLP(kb), kwLP(ka) };
                }
                return .{ kwLP(ka), kwLP(kb) };
            }
            const x: LP = switch (a) {
                .lp => |v| v,
                .kw => |k| if (isV(k)) return null else kwLP(k),
            };
            const y: LP = switch (b) {
                .lp => |v| v,
                .kw => |k| if (isH(k)) return null else kwLP(k),
            };
            return .{ x, y };
        },
        else => {
            // 3/4-value: two groups `keyword [offset]`, one per axis.
            var res: [2]?LP = .{ null, null };
            var pending_center: u8 = 0;
            var i: usize = 0;
            var groups: usize = 0;
            while (i < n) {
                const k = switch (items[i]) {
                    .kw => |k| k,
                    .lp => return null,
                };
                i += 1;
                var off: ?LP = null;
                if (i < n and items[i] == .lp) {
                    if (k == .center) return null;
                    off = items[i].lp;
                    i += 1;
                }
                groups += 1;
                const axis: usize = if (isH(k)) 0 else if (isV(k)) 1 else 2;
                var v = kwLP(k);
                if (off) |o| {
                    if (k == .right or k == .bottom) {
                        v = .{ .px = -o.px, .pct = 1 - o.pct };
                    } else v = o;
                }
                if (axis == 2) {
                    pending_center += 1;
                    continue;
                }
                if (res[axis] != null) return null;
                res[axis] = v;
            }
            if (groups != 2) return null;
            while (pending_center > 0) : (pending_center -= 1) {
                if (res[0] == null) res[0] = .{ .pct = 0.5 } else if (res[1] == null) res[1] = .{ .pct = 0.5 } else return null;
            }
            return .{ res[0] orelse return null, res[1] orelse return null };
        },
    }
}

// ------------------------------------------------------------------ tests
const T = std.testing;

fn lp1(s: []const u8, env: *const Env) !LP {
    var l = Lexer.init(s);
    const v = lengthPct(l.next(), env) orelse return error.NotLength;
    if (!l.atEnd()) return error.Trailing;
    return v;
}

fn expectLP(s: []const u8, env: *const Env, px: f32, pct: f32) !void {
    const v = lp1(s, env) catch |e| {
        std.debug.print("'{s}' -> {}\n", .{ s, e });
        return e;
    };
    if (!std.math.approxEqAbs(f32, v.px, px, 1e-3) or !std.math.approxEqAbs(f32, v.pct, pct, 1e-5)) {
        std.debug.print("'{s}' -> px {d} pct {d}, expected {d} {d}\n", .{ s, v.px, v.pct, px, pct });
        return error.TestUnexpectedResult;
    }
}

test "units dpr=2" {
    const env: Env = .{ .dpr = 2, .vw = 100, .vh = 50, .em = 32, .rem = 32 };
    try expectLP("10px", &env, 20, 0);
    try expectLP("10", &env, 20, 0);
    try expectLP("50vw", &env, 50, 0);
    try expectLP("10vh", &env, 5, 0);
    try expectLP("10vmin", &env, 5, 0);
    try expectLP("10vmax", &env, 10, 0);
    try expectLP("1em", &env, 32, 0);
    try expectLP("2rem", &env, 64, 0);
    try expectLP("12pt", &env, 32, 0);
    try expectLP("1in", &env, 192, 0);
    try expectLP("1pc", &env, 32, 0);
    try expectLP("2.54cm", &env, 192, 0);
    try expectLP("25.4mm", &env, 192, 0);
    try expectLP("4Q", &env, 192.0 / 25.4, 0);
    try expectLP("10PX", &env, 20, 0);
    try expectLP("50%", &env, 0, 0.5);
    try expectLP("-5px", &env, -10, 0);
}

test "calc" {
    const env: Env = .{ .dpr = 1, .vw = 200, .vh = 100, .em = 10, .rem = 16 };
    try expectLP("calc(100% - 20px)", &env, -20, 1);
    try expectLP("calc((100% - 20px) / 2)", &env, -10, 0.5);
    try expectLP("calc(2 * (1em + 5px))", &env, 30, 0);
    try expectLP("calc(10px + 2 * 3px - 1px)", &env, 15, 0);
    try expectLP("calc(50% + 50%)", &env, 0, 1);
    try expectLP("calc(10vw/4)", &env, 5, 0);
    try expectLP("calc(calc(1px + 1px) * 3)", &env, 6, 0);
    try expectLP("min(10px, 2em, 30px)", &env, 10, 0);
    try expectLP("max(10px, 2em)", &env, 20, 0);
    try expectLP("clamp(10px, 5px, 30px)", &env, 10, 0);
    try expectLP("clamp(10px, 50px, 30px)", &env, 30, 0);
    try expectLP("clamp(10px, 20px, 30px)", &env, 20, 0);
    try expectLP("min(10%, 20%)", &env, 0, 0.1);
    try expectLP("calc(1px + min(2px, 3px))", &env, 3, 0);
    const bad = [_][]const u8{
        "calc(100% -20px)", "calc(10px * 2px)", "calc(10px / 0)", "calc(10px + 2)", "calc(1px +)",
        "min(10%, 20px)",   "calc(1deg + 1px)", "calc(foo)",      "clamp(1px, 2px)", "calc(1px 2px)",
        "calc(((((((((((((((((((((((((((((1px)))))))))))))))))))))))))))))",
    };
    for (bad) |s| {
        if (lp1(s, &env)) |v| {
            std.debug.print("expected error for '{s}', got {any}\n", .{ s, v });
            return error.TestUnexpectedResult;
        } else |_| {}
    }
}

fn expectPos(s: []const u8, max: usize, x: LP, y: LP) !void {
    const env: Env = .{};
    var l = Lexer.init(s);
    const p = position(&l, &env, max) orelse return error.NoPos;
    try T.expect(l.atEnd());
    if (!p[0].eql(x) or !p[1].eql(y)) {
        std.debug.print("pos '{s}' = {any}\n", .{ s, p });
        return error.TestUnexpectedResult;
    }
}

test "position" {
    try expectPos("center", 4, .{ .pct = 0.5 }, .{ .pct = 0.5 });
    try expectPos("left", 4, .{}, .{ .pct = 0.5 });
    try expectPos("top", 4, .{ .pct = 0.5 }, .{});
    try expectPos("10px", 4, .{ .px = 10 }, .{ .pct = 0.5 });
    try expectPos("top left", 4, .{}, .{});
    try expectPos("right bottom", 4, .{ .pct = 1 }, .{ .pct = 1 });
    try expectPos("center top", 4, .{ .pct = 0.5 }, .{});
    try expectPos("top center", 4, .{ .pct = 0.5 }, .{});
    try expectPos("25% 75%", 4, .{ .pct = 0.25 }, .{ .pct = 0.75 });
    try expectPos("right 10px bottom 20%", 4, .{ .px = -10, .pct = 1 }, .{ .pct = 0.8 });
    try expectPos("bottom 5px right", 4, .{ .pct = 1 }, .{ .px = -5, .pct = 1 });
    try expectPos("left 10px top", 4, .{ .px = 10 }, .{});
    try expectPos("center bottom 3px", 4, .{ .pct = 0.5 }, .{ .px = -3, .pct = 1 });
    const env: Env = .{};
    const bad = [_][]const u8{ "top 10px", "left right", "10px left", "left 10px 20px", "center 10px top 5px", "top bottom" };
    for (bad) |s| {
        var l = Lexer.init(s);
        if (position(&l, &env, 4) != null and l.atEnd()) {
            std.debug.print("expected bad pos '{s}'\n", .{s});
            return error.TestUnexpectedResult;
        }
    }
}
