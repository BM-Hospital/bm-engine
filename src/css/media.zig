//! `@media` query lists and `@supports` conditions, mirroring takumi's `media_query.rs` / `supports.rs`:
//!  - media types `all | screen | print` (anything else never matches), `not` / `only` prefixes;
//!  - features `width height` (+ `min-`/`max-`), `aspect-ratio`, `resolution` (dppx/x/dpi/dpcm),
//!    `orientation`, boolean context (`(width)`), range syntax `(400px <= width < 800px)`;
//!  - `and` / `or` / `not` conditions, comma lists (any query matching = match; empty list = match);
//!  - an unsupported feature (e.g. `prefers-color-scheme`, `hover`) makes its whole query `not all`
//!    (takumi rejects the query, so even `not (prefers-color-scheme: dark)` never matches);
//!  - `width`/`height` compare the OUTPUT pixel viewport against lengths scaled by the DPR, i.e. in
//!    CSS px (`viewport / dpr`). A missing viewport dimension makes its features false.
//! `@supports`: `(prop: value)`, `not`, `and`, `or` (mixing without parentheses is invalid); a
//! `selector()` function is not supported by takumi and invalidates the prelude (the block is dropped).
const std = @import("std");
const tk = @import("tokenizer.zig");
const Tokenizer = tk.Tokenizer;
const Token = tk.Token;
const Allocator = std.mem.Allocator;
const Vec = @import("vec.zig").Vec;

/// What `@media` / `@supports` are evaluated against.
pub const Env = struct {
    /// Output-pixel viewport (the render `width` / `height` options); null = not given.
    viewport_w: ?f32 = null,
    viewport_h: ?f32 = null,
    /// Device pixel ratio (<= 0 treated as 1). `resolution` compares against it.
    dpr: f32 = 1,
    /// Initial font size in CSS px for `em`/`rem` in media queries.
    font_size: f32 = 16,
    /// Media type: false = `screen` (raster output), true = `print`.
    print: bool = false,
    /// `@supports (name: value)` test. null = every property with a non-empty value is supported.
    /// The integrator should pass a function that answers "is `name` a known property and does `value`
    /// parse for it" (takumi parses the declaration with its property parser).
    supports: ?*const fn (name: []const u8, value: []const u8) bool = null,

    pub fn effectiveDpr(e: Env) f32 {
        return if (e.dpr > 0) e.dpr else 1;
    }
};

pub const Cmp = enum(u8) { eq, min, max, gt, lt };

const Unit = enum(u8) { px, em, rem, vw, vh, vmin, vmax, cm, mm, q, in, pt, pc };

const FeatureKind = enum(u8) { width, height, resolution, aspect, orientation };

const Feature = struct {
    kind: FeatureKind,
    cmp: Cmp = .eq,
    v: f32 = 0, // length value / dppx / ratio numerator / orientation (0 portrait, 1 landscape)
    d: f32 = 1, // ratio denominator
    unit: Unit = .px,
};

pub const Cond = union(enum) {
    feature: Feature,
    not: *const Cond,
    all_of: []const Cond,
    any_of: []const Cond,
};

const MediaType = enum(u8) { all, screen, print, unsupported };

pub const Query = struct {
    media_type: MediaType = .all,
    cond: ?*const Cond = null,
    negated: bool = false,
};

pub const QueryList = []const Query;

const not_all: Query = .{ .media_type = .all, .negated = true };

const Err = error{ Invalid, OutOfMemory };

const P = struct {
    arena: Allocator,
    src: []const u8,
    t: Tokenizer,
    depth: u32 = 0,

    fn skipWs(p: *P) void {
        while (true) {
            const save = p.t.pos;
            const tok = p.t.next();
            if (tok.kind != .ws) {
                p.t.pos = save;
                return;
            }
        }
    }
    /// next non-whitespace token
    fn next(p: *P) Token {
        p.skipWs();
        return p.t.next();
    }
    fn peek(p: *P) Token {
        const save = p.t.pos;
        const tok = p.next();
        p.t.pos = save;
        return tok;
    }
    fn exhausted(p: *P) bool {
        return p.peek().kind == .eof;
    }
    fn ident(p: *P, tok: Token, name: []const u8) bool {
        return tok.isIdent(p.src, name);
    }
    fn tryIdent(p: *P, name: []const u8) bool {
        const save = p.t.pos;
        if (p.ident(p.next(), name)) return true;
        p.t.pos = save;
        return false;
    }
    fn sub(p: *P, start: usize, end: usize) P {
        return .{ .arena = p.arena, .src = p.src, .t = Tokenizer.range(p.src, start, end), .depth = p.depth + 1 };
    }
};

/// Parses a media query list from `src[start..end]` (an `@media` prelude). Never fails except OOM:
/// malformed queries become `not all`.
pub fn parseQueryList(arena: Allocator, src: []const u8, start: usize, end: usize) error{OutOfMemory}!QueryList {
    var list: Vec(Query) = .empty;
    var t = Tokenizer.range(src, start, end);
    var seg_start = start;
    var any = false;
    while (true) {
        const tok = t.next();
        if (tok.kind != .ws and tok.kind != .eof and tok.kind != .comma) any = true;
        if (tk.opensBlock(tok.kind)) {
            _ = tk.skipBlock(&t, tok.kind);
            continue;
        }
        if (tok.kind == .comma or tok.kind == .eof) {
            if (tok.kind == .comma or any or list.items.len > 0) {
                var p: P = .{ .arena = arena, .src = src, .t = Tokenizer.range(src, seg_start, tok.start) };
                const q = parseQuery(&p) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Invalid => not_all,
                };
                try list.append(arena, q);
            }
            if (tok.kind == .eof) break;
            seg_start = tok.end;
            any = false;
        }
    }
    return list.items;
}

fn parseQuery(p: *P) Err!Query {
    const save = p.t.pos;
    if (parseQueryWithType(p)) |q| {
        if (p.exhausted()) return q;
    } else |e| if (e == error.OutOfMemory) return e;
    p.t.pos = save;
    const c = try parseCondition(p, true);
    if (!p.exhausted()) return error.Invalid;
    return .{ .cond = c };
}

fn parseQueryWithType(p: *P) Err!Query {
    var tok = p.next();
    if (tok.kind != .ident) return error.Invalid;
    var q: Query = .{};
    if (p.ident(tok, "not")) {
        q.negated = true;
        tok = p.next();
    } else if (p.ident(tok, "only")) {
        tok = p.next();
    }
    if (tok.kind != .ident) return error.Invalid;
    q.media_type = if (p.ident(tok, "all")) .all else if (p.ident(tok, "screen")) .screen else if (p.ident(tok, "print")) .print else .unsupported;
    if (p.tryIdent("and")) q.cond = try parseCondition(p, false);
    return q;
}

fn box(p: *P, c: Cond) error{OutOfMemory}!*const Cond {
    const b = try p.arena.create(Cond);
    b.* = c;
    return b;
}

fn parseCondition(p: *P, allow_or: bool) Err!*const Cond {
    if (p.tryIdent("not")) return box(p, .{ .not = try parseInParens(p) });
    const first = try parseInParens(p);
    const kw: ?[]const u8 = if (p.tryIdent("and")) "and" else if (allow_or and p.tryIdent("or")) "or" else null;
    const k = kw orelse return first;
    var list: Vec(Cond) = .empty;
    try list.append(p.arena, first.*);
    try list.append(p.arena, (try parseInParens(p)).*);
    while (p.tryIdent(k)) try list.append(p.arena, (try parseInParens(p)).*);
    if (k[0] == 'a') return box(p, .{ .all_of = list.items });
    return box(p, .{ .any_of = list.items });
}

fn parseInParens(p: *P) Err!*const Cond {
    if (p.depth > 32) return error.Invalid;
    const tok = p.next();
    if (tok.kind != .lparen) return error.Invalid;
    const start = p.t.pos;
    const end = tk.skipBlock(&p.t, .lparen);
    if (p.t.pos == end) return error.Invalid;
    var q = p.sub(start, end);
    if (parseRange(&q)) |r| {
        if (q.exhausted()) {
            if (r[1]) |upper| {
                const l = try p.arena.alloc(Cond, 2);
                l[0] = .{ .feature = r[0] };
                l[1] = .{ .feature = upper };
                return box(p, .{ .all_of = l });
            }
            return box(p, .{ .feature = r[0] });
        }
    } else |e| if (e == error.OutOfMemory) return e;
    q = p.sub(start, end);
    if (parseFeature(&q)) |f| {
        if (q.exhausted()) return box(p, .{ .feature = f });
    } else |e| if (e == error.OutOfMemory) return e;
    q = p.sub(start, end);
    const c = try parseCondition(&q, true);
    if (!q.exhausted()) return error.Invalid;
    return c;
}

const Value = union(enum) {
    resolution: f32,
    ratio: [2]f32,
    number: f32,
    length: struct { v: f32, unit: Unit },
};

fn unitOf(u: []const u8) ?Unit {
    const names = [_]struct { []const u8, Unit }{
        .{ "px", .px }, .{ "em", .em },     .{ "rem", .rem },   .{ "vw", .vw }, .{ "vh", .vh },
        .{ "vmin", .vmin }, .{ "vmax", .vmax }, .{ "cm", .cm }, .{ "mm", .mm }, .{ "q", .q },
        .{ "in", .in }, .{ "pt", .pt },     .{ "pc", .pc },
    };
    for (names) |n| if (tk.ieq(u, n[0])) return n[1];
    return null;
}

fn parseValue(p: *P) Err!Value {
    const tok = p.next();
    switch (tok.kind) {
        .dimension => {
            if (tok.esc) return error.Invalid;
            const u = tok.unit(p.src);
            const eq = tk.ieq;
            if (eq(u, "dppx") or eq(u, "x")) return .{ .resolution = tok.num };
            if (eq(u, "dpi")) return .{ .resolution = tok.num / 96.0 };
            if (eq(u, "dpcm")) {
                const v = tok.num / (96.0 / 2.54) * 100.0;
                return .{ .resolution = @round(v) / 100.0 };
            }
            const unit = unitOf(u) orelse return error.Invalid;
            return .{ .length = .{ .v = tok.num, .unit = unit } };
        },
        .number => {
            const save = p.t.pos;
            const slash = p.next();
            if (slash.isDelim('/')) {
                const d = p.next();
                if (d.kind != .number or d.num <= 0) return error.Invalid;
                return .{ .ratio = .{ tok.num, d.num } };
            }
            p.t.pos = save;
            return .{ .number = tok.num };
        },
        else => return error.Invalid,
    }
}

fn makeFeature(name: []const u8, cmp: Cmp, v: Value) ?Feature {
    const eq = tk.ieq;
    if (eq(name, "width") or eq(name, "height")) {
        const kind: FeatureKind = if (eq(name, "width")) .width else .height;
        return switch (v) {
            .length => |l| .{ .kind = kind, .cmp = cmp, .v = l.v, .unit = l.unit },
            .number => |n| .{ .kind = kind, .cmp = cmp, .v = n, .unit = .px },
            else => null,
        };
    }
    if (eq(name, "resolution")) return switch (v) {
        .resolution => |r| .{ .kind = .resolution, .cmp = cmp, .v = r },
        else => null,
    };
    if (eq(name, "aspect-ratio")) return switch (v) {
        .ratio => |r| .{ .kind = .aspect, .cmp = cmp, .v = r[0], .d = r[1] },
        .number => |n| .{ .kind = .aspect, .cmp = cmp, .v = n, .d = 1 },
        else => null,
    };
    return null;
}

fn parseFeature(p: *P) Err!Feature {
    const name_tok = p.next();
    if (name_tok.kind != .ident or name_tok.esc) return error.Invalid;
    const name = name_tok.rawValue(p.src);
    const save = p.t.pos;
    if (p.next().kind != .colon) {
        p.t.pos = save;
        // boolean context
        const eq = tk.ieq;
        if (eq(name, "resolution")) return .{ .kind = .resolution, .cmp = .gt, .v = 0 };
        if (eq(name, "aspect-ratio")) return .{ .kind = .aspect, .cmp = .gt, .v = 0, .d = 1 };
        return makeFeature(name, .gt, .{ .number = 0 }) orelse error.Invalid;
    }
    if (tk.ieq(name, "orientation")) {
        const o = p.next();
        if (p.ident(o, "portrait")) return .{ .kind = .orientation, .v = 0 };
        if (p.ident(o, "landscape")) return .{ .kind = .orientation, .v = 1 };
        return error.Invalid;
    }
    var cmp: Cmp = .eq;
    var base = name;
    if (name.len > 4 and tk.ieq(name[0..4], "min-")) {
        cmp = .min;
        base = name[4..];
    } else if (name.len > 4 and tk.ieq(name[0..4], "max-")) {
        cmp = .max;
        base = name[4..];
    }
    const v = try parseValue(p);
    return makeFeature(base, cmp, v) orelse error.Invalid;
}

fn parseCmp(p: *P) Err!Cmp {
    const tok = p.next();
    if (tok.kind != .delim) return error.Invalid;
    if (tok.delim == '=') return .eq;
    if (tok.delim != '<' and tok.delim != '>') return error.Invalid;
    // `<=` must be adjacent
    const save = p.t.pos;
    const eq = p.t.next();
    const or_eq = eq.isDelim('=');
    if (!or_eq) p.t.pos = save;
    if (tok.delim == '<') return if (or_eq) .max else .lt;
    return if (or_eq) .min else .gt;
}

fn flip(c: Cmp) Cmp {
    return switch (c) {
        .eq => .eq,
        .min => .max,
        .max => .min,
        .gt => .lt,
        .lt => .gt,
    };
}
fn isUpper(c: Cmp) bool {
    return c == .max or c == .lt;
}

fn parseRange(p: *P) Err!struct { Feature, ?Feature } {
    const save = p.t.pos;
    const first = p.next();
    if (first.kind == .ident) {
        const cmp = try parseCmp(p);
        const v = try parseValue(p);
        return .{ makeFeature(first.rawValue(p.src), cmp, v) orelse return error.Invalid, null };
    }
    p.t.pos = save;
    const lv = try parseValue(p);
    const lower = flip(try parseCmp(p));
    const name_tok = p.next();
    if (name_tok.kind != .ident) return error.Invalid;
    const name = name_tok.rawValue(p.src);
    const lf = makeFeature(name, lower, lv) orelse return error.Invalid;
    if (p.exhausted()) return .{ lf, null };
    const upper = try parseCmp(p);
    if (isUpper(lower) == isUpper(upper)) return error.Invalid;
    const uv = try parseValue(p);
    return .{ lf, makeFeature(name, upper, uv) orelse return error.Invalid };
}

// --- evaluation ---

const layout_epsilon: f32 = 1.0 / 64.0;

fn cmpMatches(c: Cmp, actual: f32, expected: f32, tol: f32) bool {
    if (expected < 0) return c == .min or c == .gt;
    return switch (c) {
        .eq => @abs(actual - expected) <= tol,
        .min => actual >= expected - tol,
        .max => actual <= expected + tol,
        .gt => actual > expected,
        .lt => actual < expected,
    };
}

fn toDevicePx(f: Feature, env: Env, axis_px: f32) f32 {
    const dpr = env.effectiveDpr();
    // takumi resolves media `em`/`rem` against the unscaled initial font size (16), NOT 16*dpr (EMPIRICAL).
    const fs = env.font_size;
    const w = env.viewport_w orelse 0;
    const h = env.viewport_h orelse 0;
    _ = axis_px;
    return switch (f.unit) {
        .px => f.v * dpr,
        .em, .rem => f.v * fs,
        .vw => f.v * w / 100.0,
        .vh => f.v * h / 100.0,
        .vmin => f.v * @min(w, h) / 100.0,
        .vmax => f.v * @max(w, h) / 100.0,
        .cm => f.v * 96.0 / 2.54 * dpr,
        .mm => f.v * 96.0 / 25.4 * dpr,
        .q => f.v * 96.0 / 101.6 * dpr,
        .in => f.v * 96.0 * dpr,
        .pt => f.v * 96.0 / 72.0 * dpr,
        .pc => f.v * 16.0 * dpr,
    };
}

fn featureMatches(f: Feature, env: Env) bool {
    switch (f.kind) {
        .width => {
            const w = env.viewport_w orelse return false;
            return cmpMatches(f.cmp, w, toDevicePx(f, env, w), layout_epsilon);
        },
        .height => {
            const h = env.viewport_h orelse return false;
            return cmpMatches(f.cmp, h, toDevicePx(f, env, h), layout_epsilon);
        },
        .resolution => return cmpMatches(f.cmp, env.effectiveDpr(), f.v, 0),
        .aspect => {
            const w = env.viewport_w orelse return false;
            const h = env.viewport_h orelse return false;
            return cmpMatches(f.cmp, w * f.d, h * f.v, layout_epsilon);
        },
        .orientation => {
            const w = env.viewport_w orelse return false;
            const h = env.viewport_h orelse return false;
            return if (f.v == 0) h >= w else w > h;
        },
    }
}

fn condMatches(c: *const Cond, env: Env, depth: u32) bool {
    if (depth > 64) return false;
    return switch (c.*) {
        .feature => |f| featureMatches(f, env),
        .not => |n| !condMatches(n, env, depth + 1),
        .all_of => |l| blk: {
            for (l) |*x| if (!condMatches(x, env, depth + 1)) break :blk false;
            break :blk true;
        },
        .any_of => |l| blk: {
            for (l) |*x| if (condMatches(x, env, depth + 1)) break :blk true;
            break :blk false;
        },
    };
}

pub fn queryListMatches(list: QueryList, env: Env) bool {
    if (list.len == 0) return true;
    for (list) |q| {
        const type_ok = switch (q.media_type) {
            .all => true,
            .screen => !env.print,
            .print => env.print,
            .unsupported => false,
        };
        const m = type_ok and (if (q.cond) |c| condMatches(c, env, 0) else true);
        if (m != q.negated) return true;
    }
    return false;
}

// ------------------------------------------------------------------------------------------------
// @supports

pub const Supports = union(enum) {
    decl: struct { name: []const u8, value: []const u8 },
    not: *const Supports,
    all_of: []const Supports,
    any_of: []const Supports,
};

/// Parses an `@supports` prelude; null = invalid (the block is dropped, as takumi does).
pub fn parseSupports(arena: Allocator, src: []const u8, start: usize, end: usize) error{OutOfMemory}!?*const Supports {
    var p: P = .{ .arena = arena, .src = src, .t = Tokenizer.range(src, start, end) };
    const r = parseSupportsCond(&p, 0) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => return null,
    };
    return r;
}

fn boxS(p: *P, s: Supports) error{OutOfMemory}!*const Supports {
    const b = try p.arena.create(Supports);
    b.* = s;
    return b;
}

fn parseSupportsCond(p: *P, depth: u32) Err!*const Supports {
    if (depth > 32) return error.Invalid;
    const first = try parseSupportsNot(p, depth);
    var list: Vec(Supports) = .empty;
    var op: ?bool = null;
    while (true) {
        const save = p.t.pos;
        const tok = p.next();
        const is_and = if (p.ident(tok, "and")) true else if (p.ident(tok, "or")) false else {
            p.t.pos = save;
            break;
        };
        if (op) |o| if (o != is_and) return error.Invalid;
        if (op == null) try list.append(p.arena, first.*);
        op = is_and;
        try list.append(p.arena, (try parseSupportsNot(p, depth)).*);
    }
    if (!p.exhausted()) return error.Invalid;
    const o = op orelse return first;
    return boxS(p, if (o) .{ .all_of = list.items } else .{ .any_of = list.items });
}

fn parseSupportsNot(p: *P, depth: u32) Err!*const Supports {
    if (depth > 32) return error.Invalid;
    if (p.tryIdent("not")) return boxS(p, .{ .not = try parseSupportsNot(p, depth + 1) });
    return parseSupportsInParens(p, depth);
}

fn parseSupportsInParens(p: *P, depth: u32) Err!*const Supports {
    const tok = p.next();
    if (tok.kind != .lparen) return error.Invalid;
    const start = p.t.pos;
    const end = tk.skipBlock(&p.t, .lparen);
    if (p.t.pos == end) return error.Invalid;
    var q = p.sub(start, end);
    if (parseSupportsCond(&q, depth + 1)) |c| {
        return c;
    } else |e| if (e == error.OutOfMemory) return e;
    // declaration
    q = p.sub(start, end);
    const name = q.next();
    if (name.kind != .ident) return error.Invalid;
    if (q.next().kind != .colon) return error.Invalid;
    q.skipWs();
    const vs = q.t.pos;
    const value = std.mem.trim(u8, p.src[vs..end], " \t\r\n\x0c");
    return boxS(p, .{ .decl = .{ .name = try name.value(p.arena, p.src), .value = value } });
}

pub fn supportsMatches(s: *const Supports, env: Env, depth: u32) bool {
    if (depth > 64) return false;
    return switch (s.*) {
        .decl => |d| if (env.supports) |f| f(d.name, d.value) else d.value.len != 0,
        .not => |n| !supportsMatches(n, env, depth + 1),
        .all_of => |l| blk: {
            for (l) |*x| if (!supportsMatches(x, env, depth + 1)) break :blk false;
            break :blk true;
        },
        .any_of => |l| blk: {
            for (l) |*x| if (supportsMatches(x, env, depth + 1)) break :blk true;
            break :blk false;
        },
    };
}

// ------------------------------------------------------------------------------------------------

fn evalMedia(text: []const u8, env: Env) !bool {
    var buf: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const l = try parseQueryList(fba.allocator(), text, 0, text.len);
    return queryListMatches(l, env);
}

test "media queries" {
    const e: Env = .{ .viewport_w = 800, .viewport_h = 600 };
    const T = std.testing;
    try T.expect(try evalMedia("", e));
    try T.expect(try evalMedia("all", e));
    try T.expect(try evalMedia("screen", e));
    try T.expect(!try evalMedia("print", e));
    try T.expect(try evalMedia("not print", e));
    try T.expect(!try evalMedia("tv", e));
    try T.expect(try evalMedia("(min-width: 500px)", e));
    try T.expect(!try evalMedia("(max-width: 500px)", e));
    try T.expect(try evalMedia("screen and (min-width: 50em)", e));
    try T.expect(!try evalMedia("screen and (min-width: 51em)", e));
    try T.expect(try evalMedia("(400px <= width < 801px)", e));
    try T.expect(!try evalMedia("(400px <= width < 800px)", e));
    try T.expect(try evalMedia("(width > 799.5px)", e));
    try T.expect(try evalMedia("(orientation: landscape)", e));
    try T.expect(!try evalMedia("(orientation: portrait)", e));
    try T.expect(try evalMedia("(aspect-ratio: 4/3)", e));
    try T.expect(try evalMedia("(min-aspect-ratio: 1)", e));
    try T.expect(try evalMedia("(resolution: 1dppx)", e));
    try T.expect(try evalMedia("(min-resolution: 96dpi)", e));
    try T.expect(!try evalMedia("(min-resolution: 2x)", e));
    try T.expect(try evalMedia("(max-width: 100px), (min-width: 700px)", e));
    try T.expect(try evalMedia("(max-width: 100px) or (min-width: 700px)", e));
    try T.expect(!try evalMedia("(max-width: 100px) and (min-width: 700px)", e));
    try T.expect(try evalMedia("not (max-width: 100px)", e));
    try T.expect(!try evalMedia("(prefers-color-scheme: dark)", e));
    try T.expect(!try evalMedia("not (prefers-color-scheme: dark)", e));
    try T.expect(try evalMedia("(prefers-color-scheme: dark), (width)", e));
    try T.expect(try evalMedia("((width > 1px) and (height > 1px))", e));
    try T.expect(!try evalMedia("garbage (", e));
    try T.expect(try evalMedia("(width: 800)", e));
    try T.expect(try evalMedia("(width >= 50vw)", e));
    // DPR: viewport is output px, lengths are CSS px
    const e2: Env = .{ .viewport_w = 800, .viewport_h = 600, .dpr = 2 };
    try T.expect(try evalMedia("(max-width: 400px)", e2));
    try T.expect(!try evalMedia("(min-width: 401px)", e2));
    try T.expect(try evalMedia("(min-resolution: 2dppx)", e2));
    // no viewport
    try T.expect(!try evalMedia("(min-width: 1px)", .{}));
    try T.expect(try evalMedia("not all and (min-width: 1px)", .{}));
    try T.expect(try evalMedia("print", .{ .print = true }));
}

fn evalSupports(text: []const u8, env: Env) !?bool {
    var buf: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const s = (try parseSupports(fba.allocator(), text, 0, text.len)) orelse return null;
    return supportsMatches(s, env, 0);
}

fn onlyDisplay(name: []const u8, value: []const u8) bool {
    _ = value;
    return tk.seq(name, "display");
}

test "supports" {
    const T = std.testing;
    const e: Env = .{ .supports = onlyDisplay };
    try T.expectEqual(@as(?bool, true), try evalSupports("(display: grid)", e));
    try T.expectEqual(@as(?bool, false), try evalSupports("(foo: bar)", e));
    try T.expectEqual(@as(?bool, true), try evalSupports("not (foo: bar)", e));
    try T.expectEqual(@as(?bool, true), try evalSupports("(display: grid) or (foo: bar)", e));
    try T.expectEqual(@as(?bool, false), try evalSupports("(display: grid) and (foo: bar)", e));
    try T.expectEqual(@as(?bool, null), try evalSupports("(display: grid) and (foo: bar) or (x: y)", e));
    try T.expectEqual(@as(?bool, true), try evalSupports("((display: grid) and (display: flex))", e));
    try T.expectEqual(@as(?bool, null), try evalSupports("selector(a > b)", e));
}
