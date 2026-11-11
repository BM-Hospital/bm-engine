//! Selectors Level 4 subset: parsing, specificity and right-to-left matching over a callback DOM.
//! Mirrors what takumi gets from Servo's `selectors` crate (+ takumi's `PseudoClass` impl):
//!  - type / universal / class / id / attribute (all 7 operators, `i`/`s` flags, HTML case-insensitive
//!    attribute-value list), namespaces (`*|`, `|` prefixes) ignored;
//!  - combinators ` `, `>`, `+`, `~`; selector lists;
//!  - `:root :empty :first-child :last-child :only-child :first-of-type :last-of-type :only-of-type :scope`,
//!    `:nth-child(An+B [of S]) :nth-last-child() :nth-of-type() :nth-last-of-type()`,
//!    `:not() :is() :where() :has()` (forgiving `:is/:where`), `:lang() :dir()`, HTML form states
//!    (`:disabled :enabled :checked :indeterminate :placeholder-shown :read-only :read-write :required :optional`);
//!  - every other pseudo-class (`:hover :focus :link :any-link :visited ...`, unknown names, unknown
//!    functions) parses but NEVER matches (takumi: `PseudoClass::Other`, `is_link() == false`);
//!  - pseudo-elements `::before ::after` (and legacy `:before :after`), others (`::marker ::placeholder
//!    ::selection ::first-line ...`) parse but their selectors never match (takumi `PseudoElement::Other`);
//!  - CSS Nesting `&` (replaced by `:is(<parent list>)`; implicit `& ` prefix for nested selectors without `&`).
//! Matching uses the Servo "restart" results so descendant/sibling chains are not exponential, and a
//! per-call work budget bounds `:has()` and pathological selectors.
const std = @import("std");
const tk = @import("tokenizer.zig");
const Tokenizer = tk.Tokenizer;
const Token = tk.Token;
const Allocator = std.mem.Allocator;
const Vec = @import("vec.zig").Vec;

// ------------------------------------------------------------------------------------------------
// DOM access

/// Opaque element handle (index, pointer cast, ...), interpreted only by the `Dom` callbacks.
pub const Element = usize;

pub const Dir = enum(u8) { none, ltr, rtl };

/// Callback DOM. All functions receive `ctx` back. Only ELEMENTS are visible to selectors: bare text
/// runs (takumi: a `text` node with no tagName) must be skipped by the sibling/child callbacks.
pub const Dom = struct {
    ctx: *const anyopaque,
    /// Tag name as written ("" = none: takumi does not give JSON nodes an implicit tag for matching).
    tag: *const fn (ctx: *const anyopaque, e: Element) []const u8,
    /// `id` ("" = none). Compared case-sensitively.
    id: *const fn (ctx: *const anyopaque, e: Element) []const u8,
    /// Raw `class` attribute ("" = none); split on ASCII whitespace here.
    classes: *const fn (ctx: *const anyopaque, e: Element) []const u8,
    /// Attribute by ASCII-lowercase name, compared case-insensitively; must also answer "id",
    /// "class" and "lang" (takumi keeps those outside the attribute map). null = absent.
    attr: *const fn (ctx: *const anyopaque, e: Element, name_lower: []const u8) ?[]const u8,
    parent: *const fn (ctx: *const anyopaque, e: Element) ?Element,
    prev_sibling: *const fn (ctx: *const anyopaque, e: Element) ?Element,
    next_sibling: *const fn (ctx: *const anyopaque, e: Element) ?Element,
    first_child: *const fn (ctx: *const anyopaque, e: Element) ?Element,
    /// Blink `:empty`: no element child and no non-empty text.
    is_empty: *const fn (ctx: *const anyopaque, e: Element) bool,
    /// The element's own `dir` metadata (not inherited; `:dir()` walks ancestors itself).
    dir: *const fn (ctx: *const anyopaque, e: Element) Dir,
};

// ------------------------------------------------------------------------------------------------
// Data model

pub const AttrOp = enum(u8) { exists, eq, includes, dash, prefix, suffix, substr };
pub const Combinator = enum(u8) { descendant, child, next_sibling, later_sibling };
pub const Pseudo = enum(u8) { none, before, after, other };

pub const PC = enum(u8) {
    root,
    empty,
    first_child,
    last_child,
    only_child,
    first_of_type,
    last_of_type,
    only_of_type,
    scope,
    disabled,
    enabled,
    checked,
    indeterminate,
    placeholder_shown,
    read_only,
    read_write,
    required,
    optional,
    never,
};

pub const Attr = struct {
    name: []const u8, // lowercase
    value: []const u8,
    op: AttrOp,
    /// 0 = case-sensitive, 1 = `i` flag, 2 = HTML default list (case-insensitive).
    ci: bool,
};

pub const Nth = struct {
    a: i32,
    b: i32,
    last: bool,
    of_type: bool,
};

pub const Simple = union(enum) {
    tag: []const u8, // lowercase
    universal,
    id: []const u8,
    class: []const u8,
    attr: Attr,
    pc: PC,
    nth: Nth,
    not: []const Complex,
    is: []const Complex,
    where: []const Complex,
    has: []const Complex, // relative selectors; leftmost compound holds `.anchor`
    lang: []const []const u8,
    dir: Dir, // .none = an unknown keyword (never matches)
    anchor,
};

pub const Compound = struct {
    simples: []const Simple,
    /// Combinator joining this compound to the one on its LEFT (unused for index 0).
    comb: Combinator = .descendant,
};

pub const Complex = struct {
    /// Left-to-right.
    compounds: []const Compound,
    /// Packed specificity (a<<20 | b<<10 | c, each saturating at 1023), like `selectors`.
    spec: u32,
    pseudo: Pseudo = .none,
    /// Contains something that can never match (pseudo-class after a pseudo-element...).
    never: bool = false,
};

pub const Spec = struct {
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,
    pub fn pack(s: Spec) u32 {
        return (@as(u32, @min(s.a, 1023)) << 20) | (@as(u32, @min(s.b, 1023)) << 10) | @as(u32, @min(s.c, 1023));
    }
    pub fn unpack(v: u32) Spec {
        return .{ .a = v >> 20, .b = (v >> 10) & 1023, .c = v & 1023 };
    }
    fn add(s: *Spec, o: Spec) void {
        s.a +|= o.a;
        s.b +|= o.b;
        s.c +|= o.c;
    }
};

fn maxSpec(list: []const Complex) Spec {
    var m: u32 = 0;
    for (list) |c| m = @max(m, c.spec);
    return Spec.unpack(m);
}

fn simpleSpec(s: Simple) Spec {
    return switch (s) {
        .id => .{ .a = 1 },
        .class, .attr, .pc, .lang, .dir => .{ .b = 1 },
        .tag => .{ .c = 1 },
        .universal, .anchor, .where => .{},
        .nth => .{ .b = 1 },
        .not, .is, .has => |l| maxSpec(l),
    };
}

pub fn computeSpec(c: Complex) u32 {
    var s: Spec = .{};
    for (c.compounds) |comp| for (comp.simples) |sm| s.add(simpleSpec(sm));
    if (c.pseudo != .none) s.c +|= 1;
    return s.pack();
}

// ------------------------------------------------------------------------------------------------
// Parsing

pub const max_depth = 12; // nesting of :is/:not/:has/:nth-*(of) arguments
pub const max_compounds = 32;

pub const Mode = struct {
    /// Selector of a nested style rule: implicit `& ` prefix, leading combinator allowed.
    nesting: bool = false,
    /// Relative selector (`:has()` argument): leading combinator allowed, anchor inserted.
    relative: bool = false,
    /// Forgiving list (`:is()`, `:where()`): invalid entries dropped instead of failing.
    forgiving: bool = false,
    /// Pseudo-elements not allowed (inside functional pseudo-classes).
    inner: bool = false,
    in_has: bool = false,
};

const Fail = error{Invalid};
const PErr = error{ Invalid, OutOfMemory };

pub const Parser = struct {
    arena: Allocator,
    src: []const u8,
    t: Tokenizer,
    peeked: ?Token = null,
    /// Parent selector list for `&` (null at top level: `&` = `:scope`).
    parent: ?[]const Complex = null,
    saw_nesting: bool = false,

    fn peekRaw(p: *Parser) Token {
        if (p.peeked == null) p.peeked = p.t.next();
        return p.peeked.?;
    }
    fn nextRaw(p: *Parser) Token {
        const tok = p.peekRaw();
        p.peeked = null;
        return tok;
    }
    fn skipWs(p: *Parser) bool {
        var any = false;
        while (p.peekRaw().kind == .ws) {
            _ = p.nextRaw();
            any = true;
        }
        return any;
    }
    fn val(p: *Parser, tok: Token) error{OutOfMemory}![]const u8 {
        return tok.value(p.arena, p.src);
    }
    fn lower(p: *Parser, s: []const u8) error{OutOfMemory}![]const u8 {
        for (s) |c| {
            if (c >= 'A' and c <= 'Z') break;
        } else return s;
        const o = try p.arena.alloc(u8, s.len);
        for (s, 0..) |c, i| o[i] = std.ascii.toLower(c);
        return o;
    }
};

/// Parses `src[start..end]` as a selector list. Returns null when invalid (the whole rule is dropped).
pub fn parseList(arena: Allocator, src: []const u8, start: usize, end: usize, mode: Mode, parent: ?[]const Complex) error{OutOfMemory}!?[]const Complex {
    var p: Parser = .{ .arena = arena, .src = src, .t = Tokenizer.range(src, start, end), .parent = parent };
    return parseListIn(&p, mode, 0) catch |e| switch (e) {
        error.Invalid => null,
        error.OutOfMemory => error.OutOfMemory,
    };
}

/// Parses a comma-separated list until the parser's range ends.
fn parseListIn(p: *Parser, mode: Mode, depth: u32) PErr![]const Complex {
    if (depth > max_depth) return error.Invalid;
    var list: Vec(Complex) = .empty;
    while (true) {
        // Find the end of this entry at the top level (comma or EOF), so a forgiving list can drop it.
        const entry_start = if (p.peeked) |pk| pk.start else p.t.pos;
        var sub = Tokenizer.range(p.src, entry_start, p.t.end);
        p.peeked = null;
        var entry_end = sub.end;
        while (true) {
            const tok = sub.next();
            if (tok.kind == .eof) break;
            if (tk.opensBlock(tok.kind)) {
                _ = tk.skipBlock(&sub, tok.kind);
                continue;
            }
            if (tok.kind == .comma) {
                entry_end = tok.start;
                break;
            }
        }
        var ep: Parser = .{ .arena = p.arena, .src = p.src, .t = Tokenizer.range(p.src, entry_start, entry_end), .parent = p.parent };
        const r = parseComplex(&ep, mode, depth);
        if (r) |c| {
            try list.append(p.arena, c);
            if (ep.saw_nesting) p.saw_nesting = true;
        } else |e| {
            if (e == error.OutOfMemory) return e;
            if (!mode.forgiving) return error.Invalid;
        }
        // continue after the comma
        p.t.pos = entry_end;
        const tok = p.t.next();
        if (tok.kind != .comma) break;
    }
    if (list.items.len == 0 and !mode.forgiving) return error.Invalid;
    return list.items;
}

fn combOf(tok: Token) ?Combinator {
    if (tok.kind != .delim) return null;
    return switch (tok.delim) {
        '>' => .child,
        '+' => .next_sibling,
        '~' => .later_sibling,
        else => null,
    };
}

fn parseComplex(p: *Parser, mode: Mode, depth: u32) PErr!Complex {
    var comps: Vec(Compound) = .empty;
    var pseudo: Pseudo = .none;
    var never = false;
    _ = p.skipWs();
    var pending: Combinator = .descendant;
    var leading: ?Combinator = null;
    if (combOf(p.peekRaw())) |c| {
        if (!mode.relative and !mode.nesting) return error.Invalid;
        _ = p.nextRaw();
        _ = p.skipWs();
        leading = c;
    }
    if (mode.relative) {
        const simples = try p.arena.alloc(Simple, 1);
        simples[0] = .anchor;
        try comps.append(p.arena, .{ .simples = simples });
        pending = leading orelse .descendant;
    }
    const nesting_before = p.saw_nesting;
    p.saw_nesting = false;
    while (true) {
        if (comps.items.len >= max_compounds) return error.Invalid;
        if (pseudo != .none) return error.Invalid; // a pseudo-element must be in the last compound
        var cr = try parseCompound(p, mode, depth);
        if (cr.simples.len == 0) return error.Invalid;
        cr.comp.comb = pending;
        try comps.append(p.arena, cr.comp);
        pseudo = cr.pseudo;
        never = never or cr.never;
        const ws = p.skipWs();
        const tok = p.peekRaw();
        if (tok.kind == .eof) break;
        if (combOf(tok)) |c| {
            _ = p.nextRaw();
            _ = p.skipWs();
            pending = c;
        } else if (ws) {
            pending = .descendant;
        } else return error.Invalid;
    }
    if (mode.nesting and !p.saw_nesting) {
        // Implicit `&` (with the leading combinator or a descendant one).
        const amp = try nestingSimple(p);
        const simples = try p.arena.alloc(Simple, 1);
        simples[0] = amp;
        const all = try p.arena.alloc(Compound, comps.items.len + 1);
        all[0] = .{ .simples = simples };
        @memcpy(all[1..], comps.items);
        all[1].comb = leading orelse .descendant;
        comps.items = all;
    } else if (leading != null and !mode.relative) {
        return error.Invalid; // a leading combinator needs the implicit `&`
    }
    p.saw_nesting = p.saw_nesting or nesting_before;
    var c: Complex = .{ .compounds = comps.items, .spec = 0, .pseudo = pseudo, .never = never };
    c.spec = computeSpec(c);
    return c;
}

fn nestingSimple(p: *Parser) error{OutOfMemory}!Simple {
    if (p.parent) |par| return .{ .is = par };
    return .{ .pc = .scope };
}

const CompoundResult = struct { comp: Compound, simples: []const Simple, pseudo: Pseudo, never: bool };

fn parseCompound(p: *Parser, mode: Mode, depth: u32) PErr!CompoundResult {
    var simples: Vec(Simple) = .empty;
    var pseudo: Pseudo = .none;
    var never = false;
    // type selector / universal, with optional namespace prefix
    var tok = p.peekRaw();
    if (tok.kind == .ident or tok.isDelim('*') or tok.isDelim('|')) {
        var name_tok: ?Token = null;
        var universal = false;
        if (tok.isDelim('|')) {
            // `|x`: elements in NO namespace. takumi's `has_namespace` is always false -> never matches.
            _ = p.nextRaw();
            try simples.append(p.arena, .{ .pc = .never });
        } else {
            _ = p.nextRaw();
            if (p.peekRaw().isDelim('|')) {
                // ns|x : only `*|` is accepted (no @namespace support)
                if (!tok.isDelim('*')) return error.Invalid;
                _ = p.nextRaw();
            } else {
                if (tok.kind == .ident) name_tok = tok else universal = true;
            }
        }
        if (name_tok == null and !universal) {
            const t2 = p.nextRaw();
            if (t2.kind == .ident) name_tok = t2 else if (t2.isDelim('*')) universal = true else return error.Invalid;
        }
        if (name_tok) |nt| {
            try simples.append(p.arena, .{ .tag = try p.lower(try p.val(nt)) });
        } else try simples.append(p.arena, .universal);
    }
    while (true) {
        tok = p.peekRaw();
        switch (tok.kind) {
            .hash => {
                if (pseudo != .none) return error.Invalid;
                if (!tok.id) return error.Invalid;
                _ = p.nextRaw();
                try simples.append(p.arena, .{ .id = try p.val(tok) });
            },
            .delim => {
                if (tok.delim == '.') {
                    if (pseudo != .none) return error.Invalid;
                    _ = p.nextRaw();
                    const n = p.nextRaw();
                    if (n.kind != .ident) return error.Invalid;
                    try simples.append(p.arena, .{ .class = try p.val(n) });
                } else if (tok.delim == '&') {
                    if (pseudo != .none) return error.Invalid;
                    _ = p.nextRaw();
                    p.saw_nesting = true;
                    try simples.append(p.arena, try nestingSimple(p));
                } else break;
            },
            .lbracket => {
                if (pseudo != .none) return error.Invalid;
                _ = p.nextRaw();
                const start = p.t.pos;
                const end = tk.skipBlock(&p.t, .lbracket);
                if (p.t.pos == end) return error.Invalid; // unterminated
                try simples.append(p.arena, .{ .attr = try parseAttr(p, start, end) });
            },
            .colon => {
                _ = p.nextRaw();
                var t2 = p.nextRaw();
                if (t2.kind == .colon) {
                    // pseudo-element
                    if (mode.inner or pseudo != .none) return error.Invalid;
                    t2 = p.nextRaw();
                    if (t2.kind == .ident) {
                        pseudo = pseudoElement(try p.val(t2));
                    } else if (t2.kind == .function) {
                        _ = tk.skipBlock(&p.t, .function);
                        pseudo = .other;
                    } else return error.Invalid;
                    continue;
                }
                if (t2.kind == .ident) {
                    const name = try p.val(t2);
                    if (legacyPseudoElement(name)) |pe| {
                        if (mode.inner or pseudo != .none) return error.Invalid;
                        pseudo = pe;
                        continue;
                    }
                    if (pseudo != .none) {
                        never = true; // e.g. ::before:hover (state pseudo-classes never match)
                        continue;
                    }
                    try simples.append(p.arena, .{ .pc = pseudoClass(name) });
                } else if (t2.kind == .function) {
                    if (pseudo != .none) {
                        _ = tk.skipBlock(&p.t, .function);
                        never = true;
                        continue;
                    }
                    const start = p.t.pos;
                    const end = tk.skipBlock(&p.t, .function);
                    if (p.t.pos == end) return error.Invalid; // unterminated
                    try simples.append(p.arena, try parseFunctional(p, try p.val(t2), start, end, mode, depth));
                } else return error.Invalid;
            },
            else => break,
        }
    }
    if (simples.items.len == 0 and pseudo != .none) try simples.append(p.arena, .universal);
    return .{ .comp = .{ .simples = simples.items }, .simples = simples.items, .pseudo = pseudo, .never = never };
}

fn pseudoElement(name: []const u8) Pseudo {
    if (tk.ieq(name, "before")) return .before;
    if (tk.ieq(name, "after")) return .after;
    return .other;
}
fn legacyPseudoElement(name: []const u8) ?Pseudo {
    if (tk.ieq(name, "before")) return .before;
    if (tk.ieq(name, "after")) return .after;
    if (tk.ieq(name, "first-line") or tk.ieq(name, "first-letter")) return .other;
    return null;
}

const pc_names = [_]struct { []const u8, PC }{
    .{ "root", .root },                   .{ "empty", .empty },
    .{ "first-child", .first_child },     .{ "last-child", .last_child },
    .{ "only-child", .only_child },       .{ "first-of-type", .first_of_type },
    .{ "last-of-type", .last_of_type },   .{ "only-of-type", .only_of_type },
    .{ "scope", .scope },                 .{ "disabled", .disabled },
    .{ "enabled", .enabled },             .{ "checked", .checked },
    .{ "indeterminate", .indeterminate }, .{ "placeholder-shown", .placeholder_shown },
    .{ "read-only", .read_only },         .{ "read-write", .read_write },
    .{ "required", .required },           .{ "optional", .optional },
};

fn pseudoClass(name: []const u8) PC {
    for (pc_names) |e| if (tk.ieq(name, e[0])) return e[1];
    return .never;
}

fn parseAttr(p: *Parser, start: usize, end: usize) PErr!Attr {
    var q: Parser = .{ .arena = p.arena, .src = p.src, .t = Tokenizer.range(p.src, start, end) };
    _ = q.skipWs();
    var tok = q.nextRaw();
    // namespace prefixes: `*|name`, `|name`
    if (tok.isDelim('*') or tok.isDelim('|')) {
        if (tok.isDelim('*')) {
            if (!q.nextRaw().isDelim('|')) return error.Invalid;
        }
        tok = q.nextRaw();
    } else if (tok.kind == .ident and q.peekRaw().isDelim('|')) {
        // `ns|attr` (but not `attr|=v`)
        var look = q.t;
        const after = look.next();
        if (after.kind != .delim or after.delim != '=') return error.Invalid;
    }
    if (tok.kind != .ident) return error.Invalid;
    const name = try q.lower(try q.val(tok));
    _ = q.skipWs();
    tok = q.nextRaw();
    if (tok.kind == .eof) return .{ .name = name, .value = "", .op = .exists, .ci = false };
    var op: AttrOp = undefined;
    if (tok.isDelim('=')) {
        op = .eq;
    } else if (tok.kind == .delim) {
        op = switch (tok.delim) {
            '~' => .includes,
            '|' => .dash,
            '^' => .prefix,
            '$' => .suffix,
            '*' => .substr,
            else => return error.Invalid,
        };
        const eq = q.nextRaw();
        if (!eq.isDelim('=')) return error.Invalid;
    } else return error.Invalid;
    _ = q.skipWs();
    tok = q.nextRaw();
    if (tok.kind != .ident and tok.kind != .string) return error.Invalid;
    const value = try q.val(tok);
    _ = q.skipWs();
    tok = q.nextRaw();
    var ci = htmlCaseInsensitive(name);
    if (tok.kind == .ident) {
        const f = q.src[tok.vstart..tok.vend];
        if (tk.ieq(f, "i")) ci = true else if (tk.ieq(f, "s")) ci = false else return error.Invalid;
        _ = q.skipWs();
        tok = q.nextRaw();
    }
    if (tok.kind != .eof) return error.Invalid;
    return .{ .name = name, .value = value, .op = op, .ci = ci };
}

/// HTML attributes whose values selectors compare ASCII case-insensitively in HTML documents.
const html_ci_attrs = "accept accept-charset align alink axis bgcolor charset checked clear codetype color compact declare defer dir direction disabled enctype face frame hreflang http-equiv lang language link media method multiple nohref noresize noshade nowrap readonly rel rev rules scope scrolling selected shape target text type valign valuetype vlink ";

fn htmlCaseInsensitive(name: []const u8) bool {
    var it = std.mem.splitScalar(u8, html_ci_attrs, ' ');
    while (it.next()) |n| if (tk.seq(n, name)) return true;
    return false;
}

fn parseFunctional(p: *Parser, name: []const u8, start: usize, end: usize, mode: Mode, depth: u32) PErr!Simple {
    const eq = tk.ieq;
    const inner: Mode = .{ .inner = true, .in_has = mode.in_has };
    var q: Parser = .{ .arena = p.arena, .src = p.src, .t = Tokenizer.range(p.src, start, end), .parent = p.parent };
    defer {
        if (q.saw_nesting) p.saw_nesting = true;
    }
    if (eq(name, "not")) return .{ .not = try parseListIn(&q, inner, depth + 1) };
    if (eq(name, "is") or eq(name, "matches") or eq(name, "-webkit-any") or eq(name, "any")) {
        if (!eq(name, "is")) return .{ .pc = .never };
        var m = inner;
        m.forgiving = true;
        return .{ .is = try parseListIn(&q, m, depth + 1) };
    }
    if (eq(name, "where")) {
        var m = inner;
        m.forgiving = true;
        return .{ .where = try parseListIn(&q, m, depth + 1) };
    }
    if (eq(name, "has")) {
        if (mode.in_has) return error.Invalid;
        var m = inner;
        m.relative = true;
        m.in_has = true;
        return .{ .has = try parseListIn(&q, m, depth + 1) };
    }
    const nth_kind: ?[2]bool = if (eq(name, "nth-child")) .{ false, false } else if (eq(name, "nth-last-child")) .{ true, false } else if (eq(name, "nth-of-type")) .{ false, true } else if (eq(name, "nth-last-of-type")) .{ true, true } else null;
    if (nth_kind) |k| {
        const ab = try parseAnB(p.src[start..end]);
        return .{ .nth = .{ .a = ab[0], .b = ab[1], .last = k[0], .of_type = k[1] } };
    }
    if (eq(name, "lang")) {
        var ranges: Vec([]const u8) = .empty;
        while (true) {
            _ = q.skipWs();
            const tok = q.nextRaw();
            if (tok.kind != .ident and tok.kind != .string) return error.Invalid;
            try ranges.append(p.arena, try q.val(tok));
            _ = q.skipWs();
            const sep = q.nextRaw();
            if (sep.kind == .eof) break;
            if (sep.kind != .comma) return error.Invalid;
        }
        return .{ .lang = ranges.items };
    }
    if (eq(name, "dir")) {
        _ = q.skipWs();
        const tok = q.nextRaw();
        if (tok.kind != .ident) return error.Invalid;
        _ = q.skipWs();
        if (q.nextRaw().kind != .eof) return error.Invalid;
        const v = q.src[tok.vstart..tok.vend];
        return .{ .dir = if (eq(v, "ltr")) .ltr else if (eq(v, "rtl")) .rtl else .none };
    }
    // Unknown functional pseudo-class (incl. :host(), :host-context(), :state()): parses, never matches.
    return .{ .pc = .never };
}

/// An+B microsyntax (https://drafts.csswg.org/css-syntax-3/#anb-microsyntax).
/// An+B microsyntax (https://drafts.csswg.org/css-syntax-3/#anb-microsyntax), parsed from the
/// argument text with whitespace removed (so a few spec-invalid spellings like `2 n` are accepted).
/// `of S` is not supported (takumi rejects it), so any trailing text makes the selector invalid.
fn parseAnB(text: []const u8) PErr![2]i32 {
    var buf: [24]u8 = undefined;
    var n: usize = 0;
    for (text) |c| {
        if (tk.isWs(c)) continue;
        if (n == buf.len) return error.Invalid;
        buf[n] = std.ascii.toLower(c);
        n += 1;
    }
    const s = buf[0..n];
    if (tk.seq(s, "odd")) return .{ 2, 1 };
    if (tk.seq(s, "even")) return .{ 2, 0 };
    var i: usize = 0;
    var neg = false;
    if (i < n and (s[i] == '+' or s[i] == '-')) {
        neg = s[i] == '-';
        i += 1;
    }
    const d0 = i;
    var v: i32 = 0;
    while (i < n and s[i] >= '0' and s[i] <= '9') : (i += 1) v = v *| 10 +| @as(i32, s[i] - '0');
    const has_digits = i > d0;
    if (i < n and s[i] == 'n') {
        const a: i32 = (if (has_digits) v else 1) * @as(i32, if (neg) -1 else 1);
        i += 1;
        if (i == n) return .{ a, 0 };
        if (s[i] != '+' and s[i] != '-') return error.Invalid;
        const bneg = s[i] == '-';
        i += 1;
        const b0 = i;
        var b: i32 = 0;
        while (i < n and s[i] >= '0' and s[i] <= '9') : (i += 1) b = b *| 10 +| @as(i32, s[i] - '0');
        if (i == b0 or i != n) return error.Invalid;
        return .{ a, if (bneg) -b else b };
    }
    if (!has_digits or i != n) return error.Invalid;
    return .{ 0, if (neg) -v else v };
}

// ------------------------------------------------------------------------------------------------
// Matching

pub const MatchCx = struct {
    dom: *const Dom,
    /// Remaining work units (compound tests). When it reaches 0 every further test fails.
    budget: u32 = 200_000,
    anchor: Element = 0,

    fn spend(cx: *MatchCx) bool {
        if (cx.budget == 0) return false;
        cx.budget -= 1;
        return true;
    }
};

const Res = enum { matched, restart_sibling, restart_descendant, not_globally };

/// Whether `sel` (ignoring its pseudo-element, which the caller filters on) matches `el`.
pub fn matches(cx: *MatchCx, sel: *const Complex, el: Element) bool {
    if (sel.never or sel.compounds.len == 0) return false;
    return matchFrom(cx, sel.compounds, sel.compounds.len - 1, el) == .matched;
}

fn matchFrom(cx: *MatchCx, comps: []const Compound, i: usize, el: Element) Res {
    if (!matchCompound(cx, &comps[i], el)) return .restart_sibling;
    if (i == 0) return .matched;
    const comb = comps[i].comb;
    const d = cx.dom;
    const not_found: Res = switch (comb) {
        .next_sibling, .later_sibling => .restart_descendant,
        else => .not_globally,
    };
    var cur = el;
    while (true) {
        const nxt = switch (comb) {
            .descendant, .child => d.parent(d.ctx, cur),
            .next_sibling, .later_sibling => d.prev_sibling(d.ctx, cur),
        } orelse return not_found;
        cur = nxt;
        if (cx.budget == 0) return .not_globally;
        const r = matchFrom(cx, comps, i - 1, cur);
        switch (r) {
            .matched, .not_globally => return r,
            else => {},
        }
        if (comb == .next_sibling) return r;
        if (comb == .child) return .restart_descendant;
        if (r == .restart_descendant and comb == .later_sibling) return r;
    }
}

fn matchCompound(cx: *MatchCx, comp: *const Compound, el: Element) bool {
    if (!cx.spend()) return false;
    for (comp.simples) |*s| {
        if (!matchSimple(cx, s, el)) return false;
    }
    return true;
}

fn anyMatches(cx: *MatchCx, list: []const Complex, el: Element) bool {
    for (list) |*c| {
        if (c.pseudo != .none) continue;
        if (matches(cx, c, el)) return true;
    }
    return false;
}

fn matchSimple(cx: *MatchCx, s: *const Simple, el: Element) bool {
    const d = cx.dom;
    switch (s.*) {
        .universal => return true,
        .tag => |t| {
            const tag = d.tag(d.ctx, el);
            return tag.len != 0 and tk.ieq(tag, t);
        },
        .id => |id| {
            const v = d.id(d.ctx, el);
            return v.len != 0 and tk.seq(v, id);
        },
        .class => |c| return hasClass(d.classes(d.ctx, el), c),
        .attr => |a| return matchAttr(a, d.attr(d.ctx, el, a.name)),
        .pc => |pc| return matchPC(cx, pc, el),
        .nth => |n| return matchNth(cx, &n, el),
        .not => |l| return !anyMatches(cx, l, el),
        .is, .where => |l| return anyMatches(cx, l, el),
        .has => |l| return matchHas(cx, l, el),
        .lang => |ranges| {
            var cur: ?Element = el;
            while (cur) |e| : (cur = d.parent(d.ctx, e)) {
                if (d.attr(d.ctx, e, "lang")) |lang| {
                    for (ranges) |r| if (langMatches(lang, r)) return true;
                    return false;
                }
            }
            return false;
        },
        .dir => |want| {
            if (want == .none) return false;
            var cur: ?Element = el;
            while (cur) |e| : (cur = d.parent(d.ctx, e)) {
                const v = d.dir(d.ctx, e);
                if (v != .none) return v == want;
            }
            return want == .ltr;
        },
        .anchor => return el == cx.anchor,
    }
}

pub fn hasClass(list: []const u8, name: []const u8) bool {
    if (name.len == 0) return false;
    var i: usize = 0;
    while (i < list.len) {
        while (i < list.len and isAsciiWs(list[i])) i += 1;
        const s = i;
        while (i < list.len and !isAsciiWs(list[i])) i += 1;
        if (i > s and tk.seq(list[s..i], name)) return true;
    }
    return false;
}
fn isAsciiWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0c;
}

fn eqlCase(a: []const u8, b: []const u8, ci: bool) bool {
    return if (ci) tk.ieq(a, b) else tk.seq(a, b);
}

fn matchAttr(a: Attr, value: ?[]const u8) bool {
    const v = value orelse return false;
    const w = a.value;
    switch (a.op) {
        .exists => return true,
        .eq => return eqlCase(v, w, a.ci),
        .includes => {
            if (w.len == 0) return false;
            for (w) |c| if (isAsciiWs(c)) return false;
            var i: usize = 0;
            while (i < v.len) {
                while (i < v.len and isAsciiWs(v[i])) i += 1;
                const s = i;
                while (i < v.len and !isAsciiWs(v[i])) i += 1;
                if (i > s and eqlCase(v[s..i], w, a.ci)) return true;
            }
            return false;
        },
        .dash => return eqlCase(v, w, a.ci) or (v.len > w.len and v[w.len] == '-' and eqlCase(v[0..w.len], w, a.ci)),
        .prefix => return w.len != 0 and v.len >= w.len and eqlCase(v[0..w.len], w, a.ci),
        .suffix => return w.len != 0 and v.len >= w.len and eqlCase(v[v.len - w.len ..], w, a.ci),
        .substr => {
            if (w.len == 0 or v.len < w.len) return false;
            var i: usize = 0;
            while (i + w.len <= v.len) : (i += 1) {
                if (eqlCase(v[i .. i + w.len], w, a.ci)) return true;
            }
            return false;
        },
    }
}

/// RFC 4647 basic filtering, as takumi's `lang_matches`.
pub fn langMatches(lang: []const u8, range: []const u8) bool {
    if (tk.seq(range, "*")) return true;
    if (tk.ieq(lang, range)) return true;
    return lang.len > range.len and lang[range.len] == '-' and tk.ieq(lang[0..range.len], range);
}

fn sameType(d: *const Dom, a: Element, b: Element) bool {
    const ta = d.tag(d.ctx, a);
    const tb = d.tag(d.ctx, b);
    return tk.ieq(ta, tb);
}

fn matchPC(cx: *MatchCx, pc: PC, el: Element) bool {
    const d = cx.dom;
    switch (pc) {
        .root, .scope => return d.parent(d.ctx, el) == null,
        .empty => return d.is_empty(d.ctx, el),
        .first_child => return d.prev_sibling(d.ctx, el) == null,
        .last_child => return d.next_sibling(d.ctx, el) == null,
        .only_child => return d.prev_sibling(d.ctx, el) == null and d.next_sibling(d.ctx, el) == null,
        .first_of_type => return countSiblings(cx, el, false, true, 1) == 0,
        .last_of_type => return countSiblings(cx, el, true, true, 1) == 0,
        .only_of_type => return countSiblings(cx, el, false, true, 1) == 0 and countSiblings(cx, el, true, true, 1) == 0,
        .never => return false,
        else => return matchFormState(cx, pc, el),
    }
}

/// Number of preceding (or following) siblings of the same type / matching `of`, stopping at `limit`.
fn countSiblings(cx: *MatchCx, el: Element, following: bool, of_type: bool, limit: u32) u32 {
    const d = cx.dom;
    var n: u32 = 0;
    var cur = el;
    while (true) {
        cur = (if (following) d.next_sibling(d.ctx, cur) else d.prev_sibling(d.ctx, cur)) orelse break;
        if (!cx.spend()) break;
        if (of_type and !sameType(d, cur, el)) continue;
        n += 1;
        if (n >= limit) break;
    }
    return n;
}

fn matchNth(cx: *MatchCx, n: *const Nth, el: Element) bool {
    const a: i64 = n.a;
    const b: i64 = n.b;
    // An upper bound on the index worth counting to.
    var limit: u32 = std.math.maxInt(u32);
    if (a <= 0) {
        if (b < 1) return false;
        limit = @intCast(@min(b, std.math.maxInt(u32)));
    }
    const idx: i64 = @as(i64, countSiblings(cx, el, n.last, n.of_type, limit)) + 1;
    if (a == 0) return idx == b;
    const diff = idx - b;
    if (@rem(diff, a) != 0) return false;
    return @divTrunc(diff, a) >= 0;
}

fn matchHas(cx: *MatchCx, list: []const Complex, el: Element) bool {
    const d = cx.dom;
    const saved = cx.anchor;
    defer cx.anchor = saved;
    cx.anchor = el;
    for (list) |*rel| {
        if (rel.compounds.len < 2 or rel.pseudo != .none) continue;
        const first = rel.compounds[1].comb;
        var deep = false;
        for (rel.compounds[1..]) |c| {
            if (c.comb == .descendant or c.comb == .child) deep = true;
        }
        switch (first) {
            .descendant, .child => {
                // walk the subtree of `el` in preorder (iterative)
                var cur: ?Element = d.first_child(d.ctx, el);
                while (cur) |c| {
                    if (cx.budget == 0) return false;
                    if (matches(cx, rel, c)) return true;
                    cur = nextPreorder(d, c, el, first == .child and !hasDeeper(rel));
                }
            },
            .next_sibling, .later_sibling => {
                var sib = d.next_sibling(d.ctx, el);
                while (sib) |s| {
                    if (cx.budget == 0) return false;
                    if (deep) {
                        if (matches(cx, rel, s)) return true;
                        var cur: ?Element = d.first_child(d.ctx, s);
                        while (cur) |c| {
                            if (cx.budget == 0) return false;
                            if (matches(cx, rel, c)) return true;
                            cur = nextPreorder(d, c, s, false);
                        }
                    } else if (matches(cx, rel, s)) return true;
                    if (first == .next_sibling and !hasLaterSibling(rel)) break;
                    sib = d.next_sibling(d.ctx, s);
                }
            },
        }
    }
    return false;
}

fn hasDeeper(rel: *const Complex) bool {
    for (rel.compounds[2..]) |c| if (c.comb == .descendant or c.comb == .child) return true;
    return false;
}
fn hasLaterSibling(rel: *const Complex) bool {
    for (rel.compounds[2..]) |c| if (c.comb == .later_sibling or c.comb == .next_sibling) return true;
    return false;
}

/// Next element after `cur` in preorder within `root`'s subtree (root excluded). `shallow` = children only.
fn nextPreorder(d: *const Dom, cur: Element, root: Element, shallow: bool) ?Element {
    if (!shallow) {
        if (d.first_child(d.ctx, cur)) |c| return c;
    }
    var c = cur;
    while (c != root) {
        if (d.next_sibling(d.ctx, c)) |s| return s;
        if (shallow) return null;
        c = d.parent(d.ctx, c) orelse return null;
    }
    return null;
}

// --- HTML form states (approximation of takumi's `matches_form_state`) ---

fn isTag(d: *const Dom, el: Element, name: []const u8) bool {
    return tk.ieq(d.tag(d.ctx, el), name);
}
fn hasAttr(d: *const Dom, el: Element, name: []const u8) bool {
    return d.attr(d.ctx, el, name) != null;
}
fn inputType(d: *const Dom, el: Element) ?[]const u8 {
    if (!isTag(d, el, "input")) return null;
    return d.attr(d.ctx, el, "type") orelse "text";
}
fn typeIs(t: []const u8, names: []const u8) bool {
    var it = std.mem.splitScalar(u8, names, ' ');
    while (it.next()) |n| if (tk.ieq(t, n)) return true;
    return false;
}
fn isDisableable(d: *const Dom, el: Element) bool {
    return isTag(d, el, "button") or isTag(d, el, "input") or isTag(d, el, "select") or isTag(d, el, "textarea");
}

fn isDisabled(cx: *MatchCx, el: Element) bool {
    const d = cx.dom;
    if (isDisableable(d, el) or isTag(d, el, "fieldset")) {
        if (hasAttr(d, el, "disabled")) return true;
        // inside a <fieldset disabled>, unless inside its first <legend> child
        var child = el;
        var depth: u32 = 0;
        while (d.parent(d.ctx, child)) |par| : (child = par) {
            depth += 1;
            if (depth > 512 or !cx.spend()) return false;
            if (isTag(d, par, "fieldset") and hasAttr(d, par, "disabled")) {
                if (!(isTag(d, child, "legend") and firstLegend(d, par) == child)) return true;
            }
        }
        return false;
    }
    if (isTag(d, el, "optgroup")) return hasAttr(d, el, "disabled");
    if (isTag(d, el, "option")) {
        if (hasAttr(d, el, "disabled")) return true;
        const par = d.parent(d.ctx, el) orelse return false;
        return isTag(d, par, "optgroup") and hasAttr(d, par, "disabled");
    }
    return false;
}

fn firstLegend(d: *const Dom, fs: Element) ?Element {
    var c = d.first_child(d.ctx, fs);
    var n: u32 = 0;
    while (c) |e| : (c = d.next_sibling(d.ctx, e)) {
        n += 1;
        if (n > 4096) return null;
        if (isTag(d, e, "legend")) return e;
    }
    return null;
}

fn isChecked(cx: *MatchCx, el: Element) bool {
    const d = cx.dom;
    if (inputType(d, el)) |t| {
        if (typeIs(t, "checkbox radio")) return hasAttr(d, el, "checked");
        return false;
    }
    if (!isTag(d, el, "option")) return false;
    // owner <select> (parent, or grandparent through <optgroup>)
    const par = d.parent(d.ctx, el) orelse return hasAttr(d, el, "selected");
    var sel: ?Element = null;
    if (isTag(d, par, "select")) sel = par else if (isTag(d, par, "optgroup")) {
        if (d.parent(d.ctx, par)) |gp| if (isTag(d, gp, "select")) {
            sel = gp;
        };
    }
    const s = sel orelse return hasAttr(d, el, "selected");
    if (hasAttr(d, s, "multiple")) return hasAttr(d, el, "selected");
    // single select: last option with `selected`, else the first enabled option (display size 1)
    var last_sel: ?Element = null;
    var first_enabled: ?Element = null;
    var c = d.first_child(d.ctx, s);
    var n: u32 = 0;
    while (c) |ch| : (c = d.next_sibling(d.ctx, ch)) {
        n += 1;
        if (n > 4096 or !cx.spend()) break;
        if (isTag(d, ch, "option")) {
            if (hasAttr(d, ch, "selected")) last_sel = ch;
            if (first_enabled == null and !isDisabled(cx, ch)) first_enabled = ch;
        } else if (isTag(d, ch, "optgroup")) {
            var o = d.first_child(d.ctx, ch);
            while (o) |oe| : (o = d.next_sibling(d.ctx, oe)) {
                n += 1;
                if (n > 4096) break;
                if (!isTag(d, oe, "option")) continue;
                if (hasAttr(d, oe, "selected")) last_sel = oe;
                if (first_enabled == null and !isDisabled(cx, oe)) first_enabled = oe;
            }
        }
    }
    if (last_sel) |ls| return ls == el;
    if (d.attr(d.ctx, s, "size")) |size| {
        const v = std.mem.trim(u8, size, " \t\n\r");
        var num: u32 = 0;
        var ok = v.len > 0;
        for (v) |ch| {
            if (ch < '0' or ch > '9') {
                ok = false;
                break;
            }
            num = num *| 10 +| (ch - '0');
        }
        if (ok and num > 1) return false;
    }
    return first_enabled == el;
}

fn isReadWrite(cx: *MatchCx, el: Element) bool {
    const d = cx.dom;
    if (inputType(d, el)) |t| {
        const applies = typeIs(t, "text search tel url email password date month week time datetime-local number") or
            !typeIs(t, "hidden range color checkbox radio file submit image reset button");
        return applies and !isDisabled(cx, el) and !hasAttr(d, el, "readonly");
    }
    if (isTag(d, el, "textarea")) return !isDisabled(cx, el) and !hasAttr(d, el, "readonly");
    var cur: ?Element = el;
    var depth: u32 = 0;
    while (cur) |e| : (cur = d.parent(d.ctx, e)) {
        depth += 1;
        if (depth > 512) return false;
        if (d.attr(d.ctx, e, "contenteditable")) |v| {
            if (v.len == 0 or tk.ieq(v, "true") or tk.ieq(v, "plaintext-only")) return true;
            if (tk.ieq(v, "false")) return false;
        }
    }
    return false;
}

fn requiredState(d: *const Dom, el: Element) ?bool {
    if (inputType(d, el)) |t| {
        if (typeIs(t, "hidden range color submit image reset button")) return null;
        return hasAttr(d, el, "required");
    }
    if (isTag(d, el, "select") or isTag(d, el, "textarea")) return hasAttr(d, el, "required");
    return null;
}

fn matchFormState(cx: *MatchCx, pc: PC, el: Element) bool {
    const d = cx.dom;
    return switch (pc) {
        .disabled => isDisabled(cx, el),
        .enabled => (isDisableable(d, el) or isTag(d, el, "fieldset") or isTag(d, el, "optgroup") or isTag(d, el, "option")) and !isDisabled(cx, el),
        .checked => isChecked(cx, el),
        .indeterminate => blk: {
            if (inputType(d, el)) |t| {
                // Approximation: a radio without `checked` whose group is itself (no name).
                if (typeIs(t, "radio")) break :blk !hasAttr(d, el, "checked") and (d.attr(d.ctx, el, "name") orelse @as([]const u8, "")).len == 0;
                break :blk false;
            }
            break :blk isTag(d, el, "progress") and !hasAttr(d, el, "value");
        },
        .placeholder_shown => blk: {
            if (!hasAttr(d, el, "placeholder")) break :blk false;
            if (inputType(d, el)) |t| {
                if (typeIs(t, "hidden range color checkbox radio file submit image reset button date month week time datetime-local")) break :blk false;
                break :blk (d.attr(d.ctx, el, "value") orelse @as([]const u8, "")).len == 0;
            }
            break :blk isTag(d, el, "textarea") and d.is_empty(d.ctx, el);
        },
        .read_write => isReadWrite(cx, el),
        .read_only => !isReadWrite(cx, el),
        .required => requiredState(d, el) == true,
        .optional => requiredState(d, el) == false,
        else => false,
    };
}

// ------------------------------------------------------------------------------------------------
// Bucket key: the rightmost compound's most selective requirement (Blink order id > class > attr > tag).

pub const KeyKind = enum(u8) { any, tag, attr, class, id };
pub const Key = struct { kind: KeyKind = .any, name: []const u8 = "" };

pub fn bucketKey(c: *const Complex) Key {
    var k: Key = .{};
    if (c.compounds.len == 0) return k;
    for (c.compounds[c.compounds.len - 1].simples) |s| {
        const cand: Key = switch (s) {
            .id => |v| .{ .kind = .id, .name = v },
            .class => |v| .{ .kind = .class, .name = v },
            .tag => |v| .{ .kind = .tag, .name = v },
            else => continue,
        };
        if (@intFromEnum(cand.kind) > @intFromEnum(k.kind)) k = cand;
    }
    return k;
}
