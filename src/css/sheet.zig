//! Stylesheet parsing (CSS Syntax 3 error recovery + CSS Nesting), mirroring takumi's lossy
//! `StyleSheet::parse_loosy` (`style/selector.rs`):
//!  - style rules (selector list invalid -> whole rule dropped), nested style rules / nested
//!    `@media @supports @layer` inside style rules (CSS Nesting; `&` and implicit `& `);
//!    declarations before a nested rule form their own rule that precedes the nested ones, and the
//!    declarations after it form another rule (takumi order);
//!  - `@media`, `@supports` (kept as gates evaluated in `prepare`), `@layer` (statement and block,
//!    nested, anonymous), `@keyframes` (from/to/percent lists; `!important` inside is ignored but the
//!    declaration kept, like takumi), `@font-face` (raw descriptors), `@theme` (Tailwind: a `:root`
//!    rule), `@import "tailwindcss"` (turns on Tailwind Preflight, prepended in layer `base`);
//!  - `@page @property @namespace @container @scope @apply @counter-style ...` and other at-rules are
//!    consumed and ignored (their blocks never apply, as in takumi);
//!  - a declaration is `name: value [!important]`; names are ASCII-lowercased unless custom (`--x`);
//!    values are the trimmed source text with comments removed; property VALUE validity is NOT checked
//!    here (takumi drops an invalid declaration alone: the style module must do the same).
//! All memory comes from the arena passed to `parse` (results borrow from `text` when possible, so
//! `text` must outlive the sheet).
const std = @import("std");
const tk = @import("tokenizer.zig");
const sel = @import("selector.zig");
const media = @import("media.zig");
const Tokenizer = tk.Tokenizer;
const Token = tk.Token;
const Allocator = std.mem.Allocator;
const Vec = @import("vec.zig").Vec;

pub const Declaration = struct {
    /// Property name as written: ASCII-lowercased kebab-case, or a custom property (`--x`, case kept).
    name: []const u8,
    /// Trimmed raw value text without `!important` and without comments.
    value: []const u8,
    important: bool = false,
};

pub const no_layer: u32 = std.math.maxInt(u32);

pub const Gate = union(enum) {
    media: media.QueryList,
    supports: *const media.Supports,
};

pub const Rule = struct {
    selectors: []const sel.Complex,
    decls: []const Declaration,
    /// Indices into `Stylesheet.gates`; every gate must pass.
    gates: []const u32,
    /// Index into `Stylesheet.layer_names`, or `no_layer`.
    layer: u32 = no_layer,
};

pub const Keyframe = struct {
    /// 0..1
    offset: f32,
    declarations: []const Declaration,
};

pub const KeyframesRule = struct {
    name: []const u8,
    /// One entry per offset (a `from, 50%` selector yields two entries sharing the declarations), in
    /// source order (not sorted).
    frames: []const Keyframe,
    gates: []const u32 = &.{},
};

/// An `@page` rule (PDF builds: src/pdf/page_rules.zig cascades them): its selector text, its
/// declarations (`!important` kept; nested page-margin boxes skipped), its gates and layer.
pub const PageRule = struct {
    prelude: []const u8,
    decls: []const Declaration,
    gates: []const u32 = &.{},
    layer: u32 = no_layer,
};

pub const FontFace = struct {
    /// `font-family` descriptor, unquoted when it is a single string.
    family: []const u8 = "",
    /// Raw `src` descriptor text.
    src: []const u8 = "",
    /// Every descriptor in source order (font-weight, font-style, font-stretch, unicode-range,
    /// font-display, ...), raw. Later duplicates win.
    descriptors: []const Declaration = &.{},
    gates: []const u32 = &.{},
    layer: u32 = no_layer,

    pub fn get(f: *const FontFace, name: []const u8) ?[]const u8 {
        var i = f.descriptors.len;
        while (i > 0) {
            i -= 1;
            if (tk.seq(f.descriptors[i].name, name)) return f.descriptors[i].value;
        }
        return null;
    }
};

/// Arena-owned parsed stylesheet. Several `parse` calls append (takumi concatenates all `css`
/// entries into ONE text before parsing; concatenate yourself if you need its exact behaviour for
/// unterminated blocks spanning entries).
pub const Stylesheet = struct {
    rules: Vec(Rule) = .empty,
    keyframes: Vec(KeyframesRule) = .empty,
    /// Keyframes from the deprecated `keyframes` render option; looked up before `keyframes`.
    extra_keyframes: Vec(KeyframesRule) = .empty,
    font_faces: Vec(FontFace) = .empty,
    /// `@page` rules (collected in PDF builds only)
    pages: Vec(PageRule) = .empty,
    gates: Vec(Gate) = .empty,
    /// Interned layer paths ("a.b"; an anonymous segment is "\x01").
    layer_names: Vec([]const u8) = .empty,
    /// Layer declaration order (indices into `layer_names`), in parse order.
    layer_decls: Vec(u32) = .empty,
    /// `@import "tailwindcss"` seen at top level: Preflight is prepended by `prepare`.
    preflight: bool = false,
};

pub const max_nesting = 24;

const SP = struct {
    arena: Allocator,
    src: []const u8,
    sheet: *Stylesheet,
};

const Ctx = struct {
    gates: []const u32 = &.{},
    layer: u32 = no_layer,
    depth: u32 = 0,
    top: bool = true,
};

/// Parses stylesheet `text` and appends its rules to `sheet`. Never fails on bad CSS (bad parts are
/// skipped); only OOM is reported.
pub fn parse(arena: Allocator, text: []const u8, sheet: *Stylesheet) error{OutOfMemory}!void {
    var sp: SP = .{ .arena = arena, .src = text, .sheet = sheet };
    try ruleList(&sp, 0, text.len, .{});
}

fn ruleList(sp: *SP, start: usize, end: usize, ctx: Ctx) error{OutOfMemory}!void {
    var t = Tokenizer.range(sp.src, start, end);
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .eof => return,
            .ws, .cdo, .cdc => continue,
            .at_keyword => try atRule(sp, &t, tok, ctx, null),
            else => try qualifiedRule(sp, &t, tok, ctx, null),
        }
    }
}

/// Scans a qualified-rule prelude starting with `first` up to its `{`. Returns null (with everything
/// consumed per error recovery) when there is no block.
fn scanPrelude(t: *Tokenizer, first: Token, nested: bool) ?struct { pe: usize, bs: usize, be: usize } {
    var tok = first;
    while (true) {
        switch (tok.kind) {
            .eof => return null,
            .lbrace => {
                const bs = t.pos;
                const be = tk.skipBlock(t, .lbrace);
                return .{ .pe = tok.start, .bs = bs, .be = be };
            },
            .semicolon => if (nested) return null,
            else => if (tk.opensBlock(tok.kind)) {
                _ = tk.skipBlock(t, tok.kind);
            },
        }
        tok = t.next();
    }
}

fn qualifiedRule(sp: *SP, t: *Tokenizer, first: Token, ctx: Ctx, parent: ?[]const sel.Complex) error{OutOfMemory}!void {
    const r = scanPrelude(t, first, parent != null) orelse return;
    if (ctx.depth >= max_nesting) return;
    const list = (try sel.parseList(sp.arena, sp.src, first.start, r.pe, .{ .nesting = parent != null }, parent)) orelse return;
    var c = ctx;
    c.depth += 1;
    c.top = false;
    try styleBlock(sp, r.bs, r.be, list, c);
}

fn addGate(sp: *SP, ctx: Ctx, g: Gate) error{OutOfMemory}!Ctx {
    try sp.sheet.gates.append(sp.arena, g);
    const idx: u32 = @intCast(sp.sheet.gates.items.len - 1);
    const gates = try sp.arena.alloc(u32, ctx.gates.len + 1);
    @memcpy(gates[0..ctx.gates.len], ctx.gates);
    gates[ctx.gates.len] = idx;
    var c = ctx;
    c.gates = gates;
    return c;
}

fn internLayer(sp: *SP, path: []const u8) error{OutOfMemory}!u32 {
    for (sp.sheet.layer_names.items, 0..) |n, i| {
        if (tk.seq(n, path)) return @intCast(i);
    }
    try sp.sheet.layer_names.append(sp.arena, path);
    return @intCast(sp.sheet.layer_names.items.len - 1);
}

fn extendLayer(sp: *SP, cur: u32, name: []const u8) error{OutOfMemory}!u32 {
    if (cur == no_layer) return internLayer(sp, name);
    const base = sp.sheet.layer_names.items[cur];
    const p = try sp.arena.alloc(u8, base.len + 1 + name.len);
    @memcpy(p[0..base.len], base);
    p[base.len] = '.';
    @memcpy(p[base.len + 1 ..], name);
    return internLayer(sp, p);
}

/// Parses `@layer` names: comma list of dotted identifiers. Empty prelude = one anonymous layer.
/// Returns null when invalid.
fn layerNames(sp: *SP, start: usize, end: usize) error{OutOfMemory}!?[]const []const u8 {
    var t = Tokenizer.range(sp.src, start, end);
    var names: Vec([]const u8) = .empty;
    var cur: Vec(u8) = .empty;
    var expect_name = true;
    var any = false;
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .ws => continue,
            .eof, .comma => {
                if (tok.kind == .eof and !any) {
                    try names.append(sp.arena, "\x01");
                    return names.items;
                }
                if (expect_name) return null;
                try names.append(sp.arena, cur.items);
                cur = .empty;
                expect_name = true;
                if (tok.kind == .eof) return names.items;
            },
            .ident => {
                any = true;
                if (!expect_name) return null;
                const v = try tok.value(sp.arena, sp.src);
                // CSS-wide keywords and `default` are reserved
                for ([_][]const u8{ "initial", "inherit", "unset", "revert", "revert-layer", "default" }) |kw| {
                    if (tk.ieq(v, kw)) return null;
                }
                try cur.appendSlice(sp.arena, v);
                expect_name = false;
                // a '.' must follow immediately for a multi-segment name
                const save = t.pos;
                const dot = t.next();
                if (dot.isDelim('.')) {
                    try cur.append(sp.arena, '.');
                    expect_name = true;
                    const nx = t.next();
                    if (nx.kind != .ident) return null;
                    t.pos = nx.start;
                } else t.pos = save;
            },
            else => return null,
        }
    }
}

fn atRule(sp: *SP, t: *Tokenizer, tok: Token, ctx: Ctx, parent: ?[]const sel.Complex) error{OutOfMemory}!void {
    const name = tok.rawValue(sp.src);
    const ps = t.pos;
    var pe: usize = undefined;
    var block: ?[2]usize = null;
    while (true) {
        const x = t.next();
        switch (x.kind) {
            .eof, .semicolon => {
                pe = x.start;
                break;
            },
            .lbrace => {
                pe = x.start;
                const bs = t.pos;
                block = .{ bs, tk.skipBlock(t, .lbrace) };
                break;
            },
            else => if (tk.opensBlock(x.kind)) {
                _ = tk.skipBlock(t, x.kind);
            },
        }
    }
    if (tok.esc) return; // escaped at-rule names: ignore
    if (ctx.depth >= max_nesting) return;
    const eq = tk.ieq;
    var inner = ctx;
    inner.depth += 1;
    inner.top = false;
    if (eq(name, "media")) {
        const b = block orelse return;
        const q = try media.parseQueryList(sp.arena, sp.src, ps, pe);
        inner = try addGate(sp, inner, .{ .media = q });
        return body(sp, b, inner, parent);
    }
    if (eq(name, "supports")) {
        const b = block orelse return;
        const s = (try media.parseSupports(sp.arena, sp.src, ps, pe)) orelse return;
        inner = try addGate(sp, inner, .{ .supports = s });
        return body(sp, b, inner, parent);
    }
    if (eq(name, "layer")) {
        const names = (try layerNames(sp, ps, pe)) orelse return;
        if (block) |b| {
            if (names.len != 1) return;
            const l = try extendLayer(sp, ctx.layer, names[0]);
            if (parent == null) try sp.sheet.layer_decls.append(sp.arena, l);
            inner.layer = l;
            return body(sp, b, inner, parent);
        }
        if (parent != null) return; // statement form is invalid inside style rules
        for (names) |n| try sp.sheet.layer_decls.append(sp.arena, try extendLayer(sp, ctx.layer, n));
        return;
    }
    if (eq(name, "theme")) {
        const b = block orelse return;
        var mt = Tokenizer.range(sp.src, ps, pe);
        while (true) {
            const m = mt.next();
            if (m.kind == .eof) break;
            if (m.kind == .ws) continue;
            const ok = m.isIdent(sp.src, "reference") or m.isIdent(sp.src, "default") or m.isIdent(sp.src, "static") or m.isIdent(sp.src, "inline");
            if (!ok) return;
        }
        return themeBlock(sp, b[0], b[1], inner);
    }
    if (parent != null) {
        // Inside a style rule only the conditional/layer/theme rules above apply.
        return;
    }
    if (eq(name, "keyframes")) {
        // (dropped when the engine is built without animation support)
        if (comptime !keyframes_enabled) return;
        const b = block orelse return;
        var nt = Tokenizer.range(sp.src, ps, pe);
        var kname: ?[]const u8 = null;
        while (true) {
            const n = nt.next();
            if (n.kind == .ws) continue;
            if (n.kind == .eof) break;
            if (kname != null or (n.kind != .ident and n.kind != .string)) return;
            kname = try n.value(sp.arena, sp.src);
        }
        return keyframesBlock(sp, kname orelse return, b[0], b[1], inner);
    }
    if (eq(name, "font-face")) {
        const b = block orelse return;
        if (std.mem.trim(u8, sp.src[ps..pe], " \t\r\n\x0c").len != 0) return;
        return fontFaceBlock(sp, b[0], b[1], ctx);
    }
    if (eq(name, "import")) {
        if (block != null or !ctx.top) return;
        var it = Tokenizer.range(sp.src, ps, pe);
        var n = it.next();
        while (n.kind == .ws) n = it.next();
        if (n.kind != .string) return;
        const target = try n.value(sp.arena, sp.src);
        if (tailwindPreflight(target)) |on| {
            if (on) sp.sheet.preflight = true;
        }
        return;
    }
    if (eq(name, "page")) {
        if (comptime !pages_enabled) return;
        const b = block orelse return;
        var decls: Vec(Declaration) = .empty;
        try declList(sp, b[0], b[1], &decls, true);
        try sp.sheet.pages.append(sp.arena, .{ .prelude = std.mem.trim(u8, sp.src[ps..pe], " \t\r\n\x0c"), .decls = decls.items, .gates = ctx.gates, .layer = ctx.layer });
        return;
    }
    // @property, @namespace, @container, @font-feature-values, @counter-style, ...: ignored.
}

fn body(sp: *SP, b: [2]usize, ctx: Ctx, parent: ?[]const sel.Complex) error{OutOfMemory}!void {
    if (parent) |p| return styleBlock(sp, b[0], b[1], p, ctx);
    return ruleList(sp, b[0], b[1], ctx);
}

/// Whether the Tailwind v4 entry point `target` brings Preflight (null = not a Tailwind entry).
fn tailwindPreflight(target: []const u8) ?bool {
    const pre = "tailwindcss";
    if (!std.mem.startsWith(u8, target, pre)) return null;
    const rest = target[pre.len..];
    for ([_][]const u8{ "", "/index", "/index.css", "/preflight", "/preflight.css" }) |s| if (tk.seq(rest, s)) return true;
    for ([_][]const u8{ "/theme", "/theme.css", "/utilities", "/utilities.css" }) |s| if (tk.seq(rest, s)) return false;
    return null;
}

const DeclResult = union(enum) { decl: Declaration, invalid, not_decl };

/// Parses one declaration starting at ident `name_tok`; on return `t` is after the terminating `;`
/// (or at EOF). `allow_rule`: a value holding a top-level `{}` block means "this is a nested rule".
fn declaration(sp: *SP, t: *Tokenizer, name_tok: Token, allow_rule: bool) error{OutOfMemory}!DeclResult {
    const raw_name = try name_tok.value(sp.arena, sp.src);
    const custom = raw_name.len >= 2 and raw_name[0] == '-' and raw_name[1] == '-';
    var x = t.next();
    while (x.kind == .ws) x = t.next();
    if (x.kind != .colon) {
        if (allow_rule) return .not_decl;
        skipToSemicolon(t, x);
        return .invalid;
    }
    const vs = t.pos;
    var ve: usize = t.end;
    var bad = false;
    var has_block = false;
    var sig1: ?Token = null; // last significant token
    var sig2: ?Token = null; // the one before it
    while (true) {
        const v = t.next();
        switch (v.kind) {
            .eof, .semicolon => {
                ve = v.start;
                break;
            },
            .ws => continue,
            .rparen, .rbracket, .rbrace, .bad_string, .bad_url => bad = true,
            .lbrace => {
                has_block = true;
                _ = tk.skipBlock(t, .lbrace);
            },
            else => if (tk.opensBlock(v.kind)) {
                _ = tk.skipBlock(t, v.kind);
            },
        }
        sig2 = sig1;
        sig1 = v;
    }
    if (has_block and !custom) {
        // takumi: `ident: ... {block} ...;` inside a style rule is consumed as ONE declaration up to the
        // next `;` (an unknown property swallows it), so a nested `span:first-child{...}` rule and any
        // declarations after it up to the next `;` are lost (EMPIRICAL). Mirror that.
        return .invalid;
    }
    if (bad and !custom) return .invalid;
    const important = sig1 != null and sig2 != null and sig1.?.isIdent(sp.src, "important") and sig2.?.isDelim('!');
    const value_end = if (important) sig2.?.start else ve;
    const value = try cleanValue(sp.arena, sp.src, vs, value_end);
    if (value.len == 0 and !custom) return .invalid;
    const name = if (custom) raw_name else try lowerAlloc(sp.arena, raw_name);
    return .{ .decl = .{ .name = name, .value = value, .important = important } };
}

fn skipToSemicolon(t: *Tokenizer, first: Token) void {
    var x = first;
    while (true) {
        switch (x.kind) {
            .eof, .semicolon => return,
            else => if (tk.opensBlock(x.kind)) {
                _ = tk.skipBlock(t, x.kind);
            },
        }
        x = t.next();
    }
}

fn lowerAlloc(arena: Allocator, s: []const u8) error{OutOfMemory}![]const u8 {
    for (s) |c| {
        if (c >= 'A' and c <= 'Z') break;
    } else return s;
    const o = try arena.alloc(u8, s.len);
    for (s, 0..) |c, i| o[i] = std.ascii.toLower(c);
    return o;
}

/// Trimmed source text of `src[start..end]` with comments removed (a comment between two tokens
/// becomes one space). Allocates only when the span contains a comment.
pub fn cleanValue(arena: Allocator, src: []const u8, start: usize, end: usize) error{OutOfMemory}![]const u8 {
    const ws = " \t\r\n\x0c";
    const raw = std.mem.trim(u8, src[start..end], ws);
    if (std.mem.indexOf(u8, raw, "/*") == null) return raw;
    var out: Vec(u8) = .empty;
    var t = Tokenizer.range(src, start, end);
    var prev = start;
    while (true) {
        const tok = t.next();
        if (tok.start > prev and tok.kind != .ws and out.items.len > 0 and !tk.isWs(out.items[out.items.len - 1])) try out.append(arena, ' ');
        if (tok.kind == .eof) break;
        try out.appendSlice(arena, src[tok.start..tok.end]);
        prev = tok.end;
    }
    return std.mem.trim(u8, out.items, ws);
}

fn emitRule(sp: *SP, list: []const sel.Complex, decls: *Vec(Declaration), ctx: Ctx) error{OutOfMemory}!void {
    if (decls.items.len == 0) return;
    try sp.sheet.rules.append(sp.arena, .{ .selectors = list, .decls = decls.items, .gates = ctx.gates, .layer = ctx.layer });
    decls.* = .empty;
}

fn styleBlock(sp: *SP, start: usize, end: usize, list: []const sel.Complex, ctx: Ctx) error{OutOfMemory}!void {
    var decls: Vec(Declaration) = .empty;
    var t = Tokenizer.range(sp.src, start, end);
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .eof => break,
            .ws, .semicolon => continue,
            .at_keyword => {
                // takumi flushes the declarations so far before any nested at-rule that yields rules
                if (nestedAtRuleFlushes(sp, tok)) try emitRule(sp, list, &decls, ctx);
                try atRule(sp, &t, tok, ctx, list);
            },
            .ident => {
                const save = t.pos;
                switch (try declaration(sp, &t, tok, true)) {
                    .decl => |d| try decls.append(sp.arena, d),
                    .invalid => {},
                    .not_decl => {
                        t.pos = save;
                        try nestedRule(sp, &t, tok, list, &decls, ctx);
                    },
                }
            },
            else => try nestedRule(sp, &t, tok, list, &decls, ctx),
        }
    }
    try emitRule(sp, list, &decls, ctx);
}

fn nestedAtRuleFlushes(sp: *SP, tok: Token) bool {
    const n = tok.rawValue(sp.src);
    const eq = tk.ieq;
    // keyframes / font-face / property / page / import / apply inside a style rule are errors in
    // takumi (no flush); everything else (incl. unknown at-rules) yields a (possibly empty) fragment.
    for ([_][]const u8{ "keyframes", "font-face", "property", "page", "import", "apply" }) |x| if (eq(n, x)) return false;
    return true;
}

fn nestedRule(sp: *SP, t: *Tokenizer, first: Token, parent: []const sel.Complex, decls: *Vec(Declaration), ctx: Ctx) error{OutOfMemory}!void {
    const r = scanPrelude(t, first, true) orelse return;
    if (ctx.depth >= max_nesting) return;
    const list = (try sel.parseList(sp.arena, sp.src, first.start, r.pe, .{ .nesting = true }, parent)) orelse return;
    try emitRule(sp, parent, decls, ctx);
    var c = ctx;
    c.depth += 1;
    try styleBlock(sp, r.bs, r.be, list, c);
}

/// Declaration-only block (keyframe, @font-face, style attribute): at-rules and other junk skipped.
fn declList(sp: *SP, start: usize, end: usize, out: *Vec(Declaration), keep_important: bool) error{OutOfMemory}!void {
    var t = Tokenizer.range(sp.src, start, end);
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .eof => return,
            .ws, .semicolon => continue,
            .ident => switch (try declaration(sp, &t, tok, false)) {
                .decl => |d| {
                    var dd = d;
                    if (!keep_important) dd.important = false;
                    try out.append(sp.arena, dd);
                },
                else => {},
            },
            .at_keyword => {
                // consume the at-rule (prelude + optional block)
                while (true) {
                    const x = t.next();
                    if (x.kind == .eof or x.kind == .semicolon) break;
                    if (x.kind == .lbrace) {
                        _ = tk.skipBlock(&t, .lbrace);
                        break;
                    }
                    if (tk.opensBlock(x.kind)) _ = tk.skipBlock(&t, x.kind);
                }
            },
            else => skipToSemicolon(&t, tok),
        }
    }
}

/// Parses a declaration list (the `style` attribute / inline style text).
pub fn parseDeclarations(arena: Allocator, text: []const u8) error{OutOfMemory}![]const Declaration {
    var sheet: Stylesheet = .{};
    var sp: SP = .{ .arena = arena, .src = text, .sheet = &sheet };
    var out: Vec(Declaration) = .empty;
    try declList(&sp, 0, text.len, &out, true);
    return out.items;
}

fn themeBlock(sp: *SP, start: usize, end: usize, ctx: Ctx) error{OutOfMemory}!void {
    // `@theme { --x: y; @keyframes k {...} }` -> a `:root` rule, plus its keyframes.
    const root_sel = try sp.arena.alloc(sel.Complex, 1);
    const simples = try sp.arena.alloc(sel.Simple, 1);
    simples[0] = .{ .pc = .root };
    const comps = try sp.arena.alloc(sel.Compound, 1);
    comps[0] = .{ .simples = simples };
    root_sel[0] = .{ .compounds = comps, .spec = (sel.Spec{ .b = 1 }).pack() };
    var decls: Vec(Declaration) = .empty;
    var t = Tokenizer.range(sp.src, start, end);
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .eof => break,
            .ws, .semicolon => continue,
            .ident => switch (try declaration(sp, &t, tok, false)) {
                .decl => |d| try decls.append(sp.arena, d),
                else => {},
            },
            .at_keyword => {
                const is_kf = tok.isIdent(sp.src, "keyframes") or tk.ieq(tok.rawValue(sp.src), "keyframes");
                if (is_kf) {
                    var c = ctx;
                    c.top = false;
                    try atRule(sp, &t, tok, c, null);
                } else {
                    while (true) {
                        const x = t.next();
                        if (x.kind == .eof or x.kind == .semicolon) break;
                        if (x.kind == .lbrace) {
                            _ = tk.skipBlock(&t, .lbrace);
                            break;
                        }
                        if (tk.opensBlock(x.kind)) _ = tk.skipBlock(&t, x.kind);
                    }
                }
            },
            else => skipToSemicolon(&t, tok),
        }
    }
    try emitRule(sp, root_sel, &decls, ctx);
}

/// Parses a keyframe selector (`from`, `to`, `<percentage>` 0..100, comma list) into offsets 0..1.
pub fn parseKeyframeOffsets(arena: Allocator, src: []const u8, start: usize, end: usize) error{OutOfMemory}!?[]const f32 {
    var t = Tokenizer.range(src, start, end);
    var offs: Vec(f32) = .empty;
    var need = true;
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .ws => continue,
            .eof => return if (need) null else offs.items,
            .comma => {
                if (need) return null;
                need = true;
            },
            .ident, .percentage => {
                if (!need) return null;
                const v: f32 = if (tok.kind == .percentage) blk: {
                    if (!(tok.num >= 0 and tok.num <= 100)) return null;
                    break :blk tok.num / 100.0;
                } else if (tok.isIdent(src, "from")) 0 else if (tok.isIdent(src, "to")) 1 else return null;
                try offs.append(arena, v);
                need = false;
            },
            else => return null,
        }
    }
}

fn keyframesBlock(sp: *SP, name: []const u8, start: usize, end: usize, ctx: Ctx) error{OutOfMemory}!void {
    var frames: Vec(Keyframe) = .empty;
    var t = Tokenizer.range(sp.src, start, end);
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .eof => break,
            .ws, .cdo, .cdc => continue,
            .at_keyword => {
                while (true) {
                    const x = t.next();
                    if (x.kind == .eof or x.kind == .semicolon) break;
                    if (x.kind == .lbrace) {
                        _ = tk.skipBlock(&t, .lbrace);
                        break;
                    }
                    if (tk.opensBlock(x.kind)) _ = tk.skipBlock(&t, x.kind);
                }
            },
            else => {
                const r = scanPrelude(&t, tok, false) orelse break;
                const offs = (try parseKeyframeOffsets(sp.arena, sp.src, tok.start, r.pe)) orelse continue;
                var decls: Vec(Declaration) = .empty;
                try declList(sp, r.bs, r.be, &decls, false);
                for (offs) |o| try frames.append(sp.arena, .{ .offset = o, .declarations = decls.items });
            },
        }
    }
    try sp.sheet.keyframes.append(sp.arena, .{ .name = name, .frames = frames.items, .gates = ctx.gates });
}

fn fontFaceBlock(sp: *SP, start: usize, end: usize, ctx: Ctx) error{OutOfMemory}!void {
    var decls: Vec(Declaration) = .empty;
    try declList(sp, start, end, &decls, true);
    var f: FontFace = .{ .gates = ctx.gates, .layer = ctx.layer };
    var kept: Vec(Declaration) = .empty;
    for (decls.items) |d| {
        if (d.important) continue; // Blink: descriptors with !important are invalid
        try kept.append(sp.arena, d);
        if (tk.seq(d.name, "font-family")) {
            f.family = try unquote(sp.arena, d.value);
        } else if (tk.seq(d.name, "src")) f.src = d.value;
    }
    f.descriptors = kept.items;
    if (f.family.len == 0 or f.src.len == 0) return; // takumi keeps only rules that make a face
    try sp.sheet.font_faces.append(sp.arena, f);
}

/// A value that is exactly one string token -> its unescaped contents; otherwise the value itself.
pub fn unquote(arena: Allocator, v: []const u8) error{OutOfMemory}![]const u8 {
    var t = Tokenizer.init(v);
    const a = t.next();
    if (a.kind == .string and t.next().kind == .eof) return a.value(arena, v);
    return v;
}

/// Tailwind v4 Preflight as takumi ships it (`selector.rs` PREFLIGHT_CSS).
pub const preflight_css =
    \\@layer base{*,::before,::after{box-sizing:border-box;margin:0;padding:0;border:0 solid}
    \\:root{line-height:1.5;tab-size:4}
    \\hr{height:0;color:inherit;border-top-width:1px}
    \\h1,h2,h3,h4,h5,h6{font-size:inherit;font-weight:inherit}
    \\a{color:inherit;text-decoration:inherit}
    \\b,strong{font-weight:bolder}
    \\code,kbd,samp,pre{font-size:1em}
    \\small{font-size:80%}
    \\sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}
    \\sub{bottom:-0.25em}
    \\sup{top:-0.5em}
    \\table{text-indent:0;border-color:inherit;border-collapse:collapse}
    \\ol,ul,menu{list-style:none}
    \\img,svg{display:block;vertical-align:middle}
    \\img{max-width:100%;height:auto}
    \\[hidden]:where(:not([hidden='until-found'])){display:none !important}}
;

/// Build switch: `@page` rules are only collected for PDF output
/// (`@import("root").bm_config.enable_pdf`; on in standalone tests).
const pages_enabled = blk: {
    const root = @import("root");
    break :blk if (@hasDecl(root, "bm_config")) root.bm_config.enable_pdf else true;
};

/// Build switch: `@keyframes` rules are only kept when the engine has animation support
/// (`@import("root").bm_config.enable_animation`; on in standalone tests).
const keyframes_enabled = blk: {
    const root = @import("root");
    break :blk if (@hasDecl(root, "bm_config")) root.bm_config.enable_animation else true;
};
