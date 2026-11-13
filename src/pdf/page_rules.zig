//! `@page` rules (takumi-pdf `page_kinds.rs` / `PageOptions::with_page_rules` and takumi-core
//! `style/page_rule.rs`, `layout/page_sizes.rs` `PageRules::page_box`): the page a document's
//! stylesheets give the `size` / `margin` options, CSS winning as Chromium's `preferCSSPageSize`
//! lets it.
//!
//! The `@page` rules of the `css` option's string entries and of an HTML source's `<style>` elements
//! (parsed by src/css/sheet.zig, so also inside `@media` (a print medium the size of the options'
//! page), `@supports` and `@layer`): `@page`, `@page :first` / `:left` / `:right` and named pages
//! (`@page name`, `@page name:first` ..., the pages the `page` property names: page_names.zig),
//! cascaded per page name and kind of page as takumi's `PageRule::cascade` (importance, layer,
//! specificity: a name 4, `:first` 2, `:left` / `:right` 1, then source order); the first page is a
//! right page, a left one under a root `direction: rtl` (takumi `PageKind::of`). Descriptors `size`
//! (`auto`, a keyword `A3`..`letter` with `portrait` / `landscape`, an orientation alone, one or two
//! lengths) and `margin` (1-4 values), `margin-top` / `-right` / `-bottom` / `-left`: lengths in
//! any unit (viewport units of the options' page; `em` / `rem` / `ex` / `ch` of the root element's
//! font), `calc()` and the other math functions, `var()` of the root element's custom properties (one
//! that does not resolve unsets the descriptor), percentages of the page's size on the side's axis,
//! `auto` = 0 as Blink's `ResolveAutoMargins`; an invalid declaration is dropped alone. A page whose
//! margins leave no page area keeps the options' geometry (Blink's `LayoutPageContainer`). Pages of
//! different widths each lay their content out at their own width (paged.zig).
//!
//! Not supported: rule objects in `css`; the page-margin boxes (`@top-center` ...) are skipped, as
//! takumi does not draw them either.
const std = @import("std");
const json = @import("../json.zig");
const opt = @import("options.zig");
const css_sheet = @import("../css/sheet.zig");
const css_media = @import("../css/media.zig");
const values = @import("../style/values.zig");
const stok = @import("../style/tokenizer.zig");

const Allocator = std.mem.Allocator;

pub const Kind = enum(u2) { first, left, right };

/// The page geometry of each kind of page.
pub const Pages = struct {
    first: opt.Page,
    left: opt.Page,
    right: opt.Page,
    /// the geometry the bands and the options take (a right page's)
    rest: opt.Page,
    /// the first page is a left page (root `direction: rtl`)
    rtl: bool = false,
    /// the geometry depends on the root element (its direction, font size or custom properties)
    contextual: bool = false,
    /// the pages of each name a rule selects (a page of a name without one is an unnamed page)
    named: []const Named = &.{},

    pub const Named = struct { name: []const u8, first: opt.Page, left: opt.Page, right: opt.Page };

    /// takumi `PageKind::of`
    pub fn kindOf(p: *const Pages, i: usize) Kind {
        if (i == 0) return .first;
        return if ((i + @intFromBool(p.rtl)) % 2 == 1) .left else .right;
    }
    pub fn page(p: *const Pages, i: usize) opt.Page {
        return switch (p.kindOf(i)) {
            .first => p.first,
            .left => p.left,
            .right => p.right,
        };
    }
    /// The entry of page name `name` in `named` (null: none, the page is an unnamed one).
    pub fn namedIndex(p: *const Pages, name: ?[]const u8) ?usize {
        const nm = name orelse return null;
        for (p.named, 0..) |e, k| if (std.mem.eql(u8, e.name, nm)) return k;
        return null;
    }
    /// Page `i`, a page named `name` (null: unnamed).
    pub fn pageNamed(p: *const Pages, i: usize, name: ?[]const u8) opt.Page {
        const k = p.namedIndex(name) orelse return p.page(i);
        const e = p.named[k];
        return switch (p.kindOf(i)) {
            .first => e.first,
            .left => e.left,
            .right => e.right,
        };
    }
};

/// What a page's style takes from the root element (takumi `PageContext`): its direction, font
/// size (`em` / `rem`), its font's x-height and `0` advance (`ex` / `ch`, in em) and custom
/// properties (`var()`); and how `@supports` asks about a declaration.
pub const Context = struct {
    rtl: bool = false,
    font_size: f32 = 16,
    /// the root element's font size (`rem`; null: `font_size`)
    rem: ?f32 = null,
    ex: f32 = 0.5,
    ch: f32 = 0.5,
    ctx: *const anyopaque = undefined,
    custom: ?*const fn (ctx: *const anyopaque, name: []const u8) ?[]const u8 = null,
    /// `@supports (name: value)` (null: every declaration with a value is supported)
    supports: ?*const fn (name: []const u8, value: []const u8) bool = null,
};

const Pseudo = enum { none, first, left, right };

/// A rule that applies (its `@media` / `@supports` hold), split by importance.
const Rule = struct {
    pseudo: Pseudo,
    name: ?[]const u8 = null,
    normal: []const css_sheet.Declaration,
    important: []const css_sheet.Declaration,
    /// the position of its cascade layer (null: unlayered) and its source order
    layer: ?usize,
    order: usize,

    /// Blink's `CSSSelector::Specificity` for a page selector
    fn specificity(r: *const Rule) u64 {
        const pc: u64 = switch (r.pseudo) {
            .none => 0,
            .first => 2,
            .left, .right => 1,
        };
        return @as(u64, if (r.name != null) 4 else 0) + pc;
    }

    /// takumi `PageSelector::matches`: `kind` pages named `name` (null: unnamed) under `rtl`.
    fn matches(r: *const Rule, kind: Kind, name: ?[]const u8, rtl: bool) bool {
        if (r.name) |rn| {
            const nm = name orelse return false;
            if (!std.mem.eql(u8, rn, nm)) return false;
        }
        const is_left = switch (kind) {
            .first => rtl,
            .left => true,
            .right => false,
        };
        return switch (r.pseudo) {
            .none => true,
            .first => kind == .first,
            .left => is_left,
            .right => !is_left,
        };
    }
};

/// A margin descriptor's value.
const MarginV = union(enum) { auto, lp: values.LP };
/// A `size` descriptor's value: `auto`, lengths, or a sheet keyword and / or an orientation.
const SizeV = union(enum) {
    auto,
    lengths: [2]f32,
    sheet: struct { wh: ?[2]f32 = null, landscape: ?bool = null },
};

/// The descriptors a declaration sets, or those that win the cascade (takumi `PageDescriptors`).
const Desc = struct {
    size: ?SizeV = null,
    margin: [4]?MarginV = .{ null, null, null, null },

    fn over(d: *Desc, o: Desc) void {
        if (o.size) |s| d.size = s;
        for (o.margin, 0..) |m, k| if (m) |v| {
            d.margin[k] = v;
        };
    }
    fn any(d: Desc) bool {
        return d.size != null or d.margin[0] != null or d.margin[1] != null or d.margin[2] != null or d.margin[3] != null;
    }
};

/// The rules that apply, in source order, with the layer count.
const Rules = struct { list: []const Rule, layers: usize };

/// The `@page`-styled geometry of `base` for the CSS texts of the document (`css` option strings
/// and, for HTML input, its `<style>` contents), with the root element's `cx`.
pub fn resolve(a: Allocator, base: opt.Page, css: ?json.Value, html: ?[]const u8, cx: Context) Allocator.Error!Pages {
    var texts: std.ArrayList([]const u8) = .empty;
    if (css) |c| switch (c) {
        .string => |s| try texts.append(a, s),
        .array => |arr| for (arr) |e| if (e == .string) try texts.append(a, e.string),
        else => {},
    };
    if (html) |h| try styleTexts(a, h, &texts);
    const rules = try collect(a, texts.items, base, cx);
    if (rules.list.len == 0) return .{ .first = base, .left = base, .right = base, .rest = base, .rtl = cx.rtl };
    const right = try kindPage(a, base, rules, .right, cx, null);
    const left = try kindPage(a, base, rules, .left, cx, null);
    const first = try kindPage(a, base, rules, .first, cx, null);
    // the pages of each name a rule selects
    var named: std.ArrayList(Pages.Named) = .empty;
    for (rules.list) |r| {
        const nm = r.name orelse continue;
        const seen = for (named.items) |e| {
            if (std.mem.eql(u8, e.name, nm)) break true;
        } else false;
        if (seen) continue;
        try named.append(a, .{
            .name = nm,
            .first = try kindPage(a, base, rules, .first, cx, nm),
            .left = try kindPage(a, base, rules, .left, cx, nm),
            .right = try kindPage(a, base, rules, .right, cx, nm),
        });
    }
    // (the root element's direction, font and custom properties may change what the rules give)
    return .{ .first = first, .left = left, .right = right, .rest = right, .rtl = cx.rtl, .contextual = true, .named = named.items };
}

/// The `@page` rules of `texts` whose `@media` (a print medium the size of the options' page,
/// takumi's `Viewport::print_page`) and `@supports` conditions hold, with a valid selector.
fn collect(a: Allocator, texts: []const []const u8, base: opt.Page, cx: Context) Allocator.Error!Rules {
    var sheet: css_sheet.Stylesheet = .{};
    for (texts) |t| try css_sheet.parse(a, t, &sheet);
    if (sheet.pages.items.len == 0) return .{ .list = &.{}, .layers = 0 };
    const env: css_media.Env = .{ .viewport_w = base.width, .viewport_h = base.height, .print = true, .supports = cx.supports };
    const ok = try a.alloc(bool, sheet.gates.items.len);
    for (sheet.gates.items, 0..) |g, i| ok[i] = switch (g) {
        .media => |q| css_media.queryListMatches(q, env),
        .supports => |s| css_media.supportsMatches(s, env, 0),
    };
    // layer order: the declared layers in order, then the layers rules use, first use first
    var names: std.ArrayList([]const u8) = .empty;
    const Names = struct {
        fn add(al: Allocator, list: *std.ArrayList([]const u8), n: []const u8) Allocator.Error!void {
            for (list.items) |x| if (std.mem.eql(u8, x, n)) return;
            try list.append(al, n);
        }
        fn index(list: []const []const u8, n: []const u8) ?usize {
            for (list, 0..) |x, i| if (std.mem.eql(u8, x, n)) return i;
            return null;
        }
    };
    for (sheet.layer_decls.items) |li| try Names.add(a, &names, sheet.layer_names.items[li]);
    for (sheet.rules.items) |r| if (r.layer != css_sheet.no_layer) try Names.add(a, &names, sheet.layer_names.items[r.layer]);
    for (sheet.pages.items) |r| if (r.layer != css_sheet.no_layer) try Names.add(a, &names, sheet.layer_names.items[r.layer]);
    var list: std.ArrayList(Rule) = .empty;
    for (sheet.pages.items, 0..) |pr, order| {
        const pass = for (pr.gates) |g| {
            if (g >= ok.len or !ok[g]) break false;
        } else true;
        if (!pass) continue;
        const s = selector(a, pr.prelude) orelse continue;
        var normal: std.ArrayList(css_sheet.Declaration) = .empty;
        var important: std.ArrayList(css_sheet.Declaration) = .empty;
        for (pr.decls) |d| try (if (d.important) &important else &normal).append(a, d);
        try list.append(a, .{
            .pseudo = s.pseudo,
            .name = s.name,
            .normal = normal.items,
            .important = important.items,
            .layer = if (pr.layer == css_sheet.no_layer) null else Names.index(names.items, sheet.layer_names.items[pr.layer]),
            .order = order,
        });
    }
    return .{ .list = list.items, .layers = names.items.len };
}

/// takumi `PageSelector::parse`: a page name, a pseudo-class, both, or nothing (comments aside).
fn selector(a: Allocator, prelude: []const u8) ?struct { name: ?[]const u8, pseudo: Pseudo } {
    // (comments out)
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < prelude.len) {
        if (prelude[i] == '/' and i + 1 < prelude.len and prelude[i + 1] == '*') {
            i = if (std.mem.indexOfPos(u8, prelude, i + 2, "*/")) |e| e + 2 else prelude.len;
            buf.append(a, ' ') catch return null;
            continue;
        }
        buf.append(a, prelude[i]) catch return null;
        i += 1;
    }
    var rest = std.mem.trim(u8, buf.items, " \t\r\n\x0c");
    var name: ?[]const u8 = null;
    var k: usize = 0;
    while (k < rest.len and (isIdent(rest[k]) or rest[k] >= 0x80)) k += 1;
    if (k > 0) {
        name = rest[0..k];
        rest = std.mem.trim(u8, rest[k..], " \t\r\n\x0c");
    }
    const pseudo: Pseudo = if (rest.len == 0)
        .none
    else if (std.ascii.eqlIgnoreCase(rest, ":first"))
        .first
    else if (std.ascii.eqlIgnoreCase(rest, ":left"))
        .left
    else if (std.ascii.eqlIgnoreCase(rest, ":right"))
        .right
    else
        return null;
    if (name) |nm| if (std.ascii.isDigit(nm[0]) or (nm[0] == '-' and (nm.len < 2 or std.ascii.isDigit(nm[1])))) return null;
    return .{ .name = name, .pseudo = pseudo };
}

/// takumi `PageRule::cascade`: the descriptors that win among the rules matching `kind` pages
/// named `name` (null: unnamed), by importance, layer, specificity and source order, applied to
/// `base`.
fn kindPage(a: Allocator, base: opt.Page, rules: Rules, kind: Kind, cx: Context, name: ?[]const u8) Allocator.Error!opt.Page {
    const Ranked = struct { rank: u64, decls: []const css_sheet.Declaration };
    var ranked: std.ArrayList(Ranked) = .empty;
    const n: u64 = rules.layers;
    for (rules.list) |*r| {
        if (!r.matches(kind, name, cx.rtl)) continue;
        const tail = (r.specificity() << 20) | @as(u64, r.order);
        const layer_n: u64 = if (r.layer) |l| l else n;
        const layer_i: u64 = if (r.layer) |l| n - l else 0;
        try ranked.append(a, .{ .rank = (layer_n << 40) | tail, .decls = r.normal });
        try ranked.append(a, .{ .rank = (@as(u64, 1) << 63) | (layer_i << 40) | tail, .decls = r.important });
    }
    std.mem.sort(Ranked, ranked.items, {}, struct {
        fn lt(_: void, x: Ranked, y: Ranked) bool {
            return x.rank < y.rank;
        }
    }.lt);
    var d: Desc = .{};
    for (ranked.items) |rk| for (rk.decls) |decl| {
        if (try declaration(a, decl.name, decl.value, base, cx)) |x| d.over(x);
    };
    if (!d.any()) return base;
    return apply(base, d);
}

/// takumi `PageDeclaration`: the descriptors `name: value` sets, null for a declaration Blink
/// drops; a `var()` that does not resolve (to a valid value) unsets the descriptor (`size: auto`,
/// a margin 0).
fn declaration(a: Allocator, name: []const u8, value: []const u8, base: opt.Page, cx: Context) Allocator.Error!?Desc {
    if (std.mem.indexOf(u8, value, "var(") == null) return parseDesc(a, name, value, base, cx);
    if (parseDesc(a, name, if (std.ascii.eqlIgnoreCase(name, "size")) "auto" else "0", base, cx) == null) return null;
    if (try substitute(a, value, cx, 0)) |v| if (parseDesc(a, name, v, base, cx)) |x| return x;
    return parseDesc(a, name, if (std.ascii.eqlIgnoreCase(name, "size")) "auto" else "0", base, cx);
}

fn parseDesc(a: Allocator, name: []const u8, value: []const u8, base: opt.Page, cx: Context) ?Desc {
    var lx = stok.Lexer.init(value);
    var d: Desc = .{};
    const env = lengthEnv(a, base, cx);
    if (std.ascii.eqlIgnoreCase(name, "size")) {
        d.size = sizeValue(&lx, &env) orelse return null;
    } else if (std.ascii.eqlIgnoreCase(name, "margin")) {
        var vals: [4]MarginV = undefined;
        var count: usize = 0;
        while (count < 4 and !lx.atEnd()) {
            vals[count] = marginValue(lx.next(), &env) orelse return null;
            count += 1;
        }
        if (count == 0) return null;
        const t = vals[0];
        const r = if (count > 1) vals[1] else t;
        const b = if (count > 2) vals[2] else t;
        const l = if (count > 3) vals[3] else r;
        d.margin = .{ t, r, b, l };
    } else {
        const sides = [_][]const u8{ "margin-top", "margin-right", "margin-bottom", "margin-left" };
        const k = for (sides, 0..) |s, k| {
            if (std.ascii.eqlIgnoreCase(name, s)) break k;
        } else return null;
        if (lx.atEnd()) return null;
        d.margin[k] = marginValue(lx.next(), &env) orelse return null;
    }
    if (!lx.atEnd()) return null;
    return d;
}

/// Lengths in a page rule: the options' page is the viewport (takumi `Viewport::print_page`), the
/// root element's font the `em` / `rem` / `ex` / `ch` units.
fn lengthEnv(a: Allocator, base: opt.Page, cx: Context) values.Env {
    return .{ .vw = base.width, .vh = base.height, .em = cx.font_size, .rem = cx.rem orelse cx.font_size, .ex = cx.ex, .ch = cx.ch, .lh = 1.2 * cx.font_size, .rlh = 1.2 * cx.font_size, .alloc = a };
}

/// takumi `Length::from_css` for a page: a length, a percentage, a math function, or a unitless
/// number (px).
fn lengthToken(t: stok.Token, env: *const values.Env) ?values.LP {
    switch (t.kind) {
        .number, .dimension, .percentage, .function => {},
        else => return null,
    }
    const v = values.lengthPct(t, env) orelse return null;
    if (!std.math.isFinite(v.px) or !std.math.isFinite(v.pct)) return null;
    return v;
}

fn marginValue(t: stok.Token, env: *const values.Env) ?MarginV {
    if (t.isIdent("auto")) return .auto;
    return .{ .lp = lengthToken(t, env) orelse return null };
}

/// `auto | <length [0,∞]>{1,2} | [ <page-size> || [ portrait | landscape ] ]`
fn sizeValue(lx: *stok.Lexer, env: *const values.Env) ?SizeV {
    const first = lx.next();
    if (first.isIdent("auto")) return .auto;
    if (first.kind != .ident) {
        const w = sheetLength(first, env) orelse return null;
        if (lx.atEnd()) return .{ .lengths = .{ w, w } };
        const h = sheetLength(lx.next(), env) orelse return null;
        return .{ .lengths = .{ w, h } };
    }
    var s: SizeV = .{ .sheet = .{} };
    var tok = first;
    while (true) {
        if (tok.kind != .ident) return null;
        if (tok.isIdent("landscape") or tok.isIdent("portrait")) {
            if (s.sheet.landscape != null) return null;
            s.sheet.landscape = tok.isIdent("landscape");
        } else {
            if (s.sheet.wh != null) return null;
            const p = opt.Page.named(tok.text) orelse return null;
            s.sheet.wh = .{ p.width, p.height };
        }
        if (lx.atEnd()) break;
        tok = lx.next();
    }
    return s;
}

/// A length for `size`: no `auto`, no percentage, nothing negative.
fn sheetLength(t: stok.Token, env: *const values.Env) ?f32 {
    if ((t.kind == .number or t.kind == .dimension) and t.num < 0) return null;
    const v = lengthToken(t, env) orelse return null;
    if (v.pct != 0 or v.calc != null) return null;
    return v.px;
}

/// `<style>` element contents of an HTML source (a plain scan; comments and CDATA are not special).
fn styleTexts(a: Allocator, h: []const u8, out: *std.ArrayList([]const u8)) Allocator.Error!void {
    var at: usize = 0;
    while (indexOfIgnoreCase(h, at, "<style")) |i| {
        const gt = std.mem.indexOfScalarPos(u8, h, i, '>') orelse return;
        const end = indexOfIgnoreCase(h, gt + 1, "</style") orelse return;
        try out.append(a, h[gt + 1 .. end]);
        at = end + 7;
    }
}

fn indexOfIgnoreCase(h: []const u8, from: usize, needle: []const u8) ?usize {
    var i = from;
    while (i + needle.len <= h.len) : (i += 1) if (std.ascii.eqlIgnoreCase(h[i .. i + needle.len], needle)) return i;
    return null;
}

fn isIdent(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
}

/// `value` with its `var(--name[, fallback])` references replaced by the root element's custom
/// properties (null: an undefined one without a fallback, so the declaration is invalid).
fn substitute(a: Allocator, value: []const u8, cx: Context, depth: u32) Allocator.Error!?[]const u8 {
    if (std.mem.indexOf(u8, value, "var(") == null) return value;
    if (depth > 8) return null;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, value, i, "var(")) |k| {
        try out.appendSlice(a, value[i..k]);
        // the matching parenthesis
        var d: usize = 0;
        var e = k + 3;
        while (e < value.len) : (e += 1) {
            if (value[e] == '(') d += 1;
            if (value[e] == ')') {
                d -= 1;
                if (d == 0) break;
            }
        }
        if (e >= value.len) return null;
        const inner = value[k + 4 .. e];
        const comma = std.mem.indexOfScalar(u8, inner, ',');
        const name = std.mem.trim(u8, if (comma) |cm| inner[0..cm] else inner, " \t\r\n\x0c");
        const got: ?[]const u8 = if (cx.custom) |f| f(cx.ctx, name) else null;
        const rep = got orelse if (comma) |cm| std.mem.trim(u8, inner[cm + 1 ..], " \t\r\n\x0c") else return null;
        const sub = (try substitute(a, rep, cx, depth + 1)) orelse return null;
        try out.appendSlice(a, std.mem.trim(u8, sub, " \t\r\n\x0c"));
        i = e + 1;
    }
    try out.appendSlice(a, value[i..]);
    return out.items;
}

/// takumi `PageRules::page_box`: the size the descriptors give `base` (`auto` keeps it), turned
/// to the orientation asked, the margins on it (a percentage of the page's size on its own axis,
/// `auto` 0); a page box leaving no page area is ignored (Blink's `LayoutPageContainer`).
fn apply(base: opt.Page, d: Desc) opt.Page {
    var p = base;
    if (d.size) |sz| switch (sz) {
        .auto => {},
        .lengths => |wh| {
            p.width = wh[0];
            p.height = wh[1];
        },
        .sheet => |s| {
            var w = p.width;
            var h = p.height;
            if (s.wh) |wh| {
                w = wh[0];
                h = wh[1];
            }
            if (s.landscape) |land| {
                if ((land and w < h) or (!land and w > h)) std.mem.swap(f32, &w, &h);
            }
            p.width = w;
            p.height = h;
        },
    };
    const axes = [4]f32{ p.height, p.width, p.height, p.width };
    var m = [4]opt.Margin{ p.margin.top, p.margin.right, p.margin.bottom, p.margin.left };
    for (d.margin, 0..) |mv, k| {
        const v = mv orelse continue;
        m[k] = switch (v) {
            .auto => .{ .px = 0 },
            .lp => |lp| .{ .px = lp.resolve(axes[k]) },
        };
    }
    p.margin = .{ .top = m[0], .right = m[1], .bottom = m[2], .left = m[3] };
    if (!(std.math.isFinite(p.width) and std.math.isFinite(p.height))) return base;
    if (p.contentSize(p.resolveMargins(null, null)) == null) return base;
    return p;
}

test "@page named pages" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const aa = arena.allocator();
    const mm = opt.one_mm_in_px;
    const css: json.Value = .{ .string = "@page { size: A5; margin: 15mm } @page cover { margin: 40mm 20mm } @page wide { size: A5 landscape; margin: 10mm } @page wide:first { margin-top: 5mm } @page 9x { size: A3 }" };
    const r = try resolve(aa, opt.Page.a4, css, null, .{});
    try std.testing.expectEqual(@as(usize, 2), r.named.len);
    // a named page takes the unnamed rules, then its own
    const cover = r.pageNamed(1, "cover");
    try std.testing.expectApproxEqAbs(opt.Page.a5.width, cover.width, 0.001);
    try std.testing.expectApproxEqAbs(40 * mm, cover.margin.top.px, 0.001);
    try std.testing.expectApproxEqAbs(20 * mm, cover.margin.left.px, 0.001);
    const wide = r.pageNamed(2, "wide");
    try std.testing.expect(wide.width > wide.height);
    try std.testing.expectApproxEqAbs(10 * mm, wide.margin.top.px, 0.001);
    // `:first` of a name: only on the document's first page
    try std.testing.expectApproxEqAbs(5 * mm, r.pageNamed(0, "wide").margin.top.px, 0.001);
    // a name no rule selects is an unnamed page
    try std.testing.expectApproxEqAbs(15 * mm, r.pageNamed(3, "index").margin.left.px, 0.001);
    try std.testing.expectApproxEqAbs(15 * mm, r.pageNamed(3, null).margin.left.px, 0.001);
}

test "@page size and margins (plain, :first, :left, :right)" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const aa = arena.allocator();
    const mm = opt.one_mm_in_px;
    const css: json.Value = .{ .string = "p{color:red} @page { size: A5; margin: 10mm } @page :first { margin-top: 20mm } @page :left { margin-left: 15mm; margin-right: 5mm }" };
    const r = try resolve(aa, opt.Page.a4, css, null, .{});
    try std.testing.expectApproxEqAbs(opt.Page.a5.width, r.rest.width, 0.001);
    try std.testing.expectApproxEqAbs(10 * mm, r.right.margin.left.px, 0.001);
    try std.testing.expectApproxEqAbs(15 * mm, r.left.margin.left.px, 0.001);
    try std.testing.expectApproxEqAbs(20 * mm, r.first.margin.top.px, 0.001);
    try std.testing.expectApproxEqAbs(10 * mm, r.first.margin.bottom.px, 0.001);
    try std.testing.expectApproxEqAbs(10 * mm, r.first.margin.left.px, 0.001);
    try std.testing.expectEqual(Kind.left, r.kindOf(1));
    try std.testing.expectEqual(Kind.right, r.kindOf(2));
    // under rtl the first page is a left page
    const rr = try resolve(aa, opt.Page.a4, css, null, .{ .rtl = true });
    try std.testing.expectApproxEqAbs(15 * mm, rr.first.margin.left.px, 0.001);
    try std.testing.expectEqual(Kind.right, rr.kindOf(1));
    // :left / :right and :first rules that change the page area's width apply (each page lays
    // its content out at its own width)
    const sides = try resolve(aa, opt.Page.a4, .{ .string = "@page { margin: 10px } @page :left { margin-left: 30px }" }, null, .{});
    try std.testing.expectEqual(@as(f32, 30), sides.left.margin.left.px);
    const wide = try resolve(aa, opt.Page.a4, .{ .string = "@page { size: A5 } @page :first { size: A5 landscape }" }, null, .{});
    try std.testing.expect(wide.first.width > wide.rest.width);
    // the root element's font size and custom properties
    const Root = struct {
        fn custom(_: *const anyopaque, name: []const u8) ?[]const u8 {
            return if (std.mem.eql(u8, name, "--inner")) "3em" else null;
        }
    };
    const em = try resolve(aa, opt.Page.a4, .{ .string = "@page { size: A5; margin: 1em } @page :left { margin-left: var(--inner) } @page :right { margin-right: var(--inner) }" }, null, .{ .rtl = true, .font_size = 20, .custom = Root.custom });
    try std.testing.expectEqual(@as(f32, 60), em.first.margin.left.px);
    try std.testing.expectEqual(@as(f32, 20), em.first.margin.right.px);
    try std.testing.expectEqual(@as(f32, 20), em.page(1).margin.left.px);
    try std.testing.expect(em.contextual);
    // HTML <style>, orientation alone, lengths, auto margins
    const h = try resolve(aa, opt.Page.a4, null, "<style>@page{size:landscape;margin:auto 5%}</style><p>x</p>", .{});
    try std.testing.expect(h.rest.width > h.rest.height);
    try std.testing.expectEqual(@as(f32, 0), h.rest.margin.top.px);
    try std.testing.expectApproxEqAbs(h.rest.width * 0.05, h.rest.margin.left.px, 0.001);
    const l = try resolve(aa, opt.Page.a4, .{ .string = "@page { size: 400px 300px; margin: 0 }" }, null, .{});
    try std.testing.expectEqual(@as(f32, 400), l.rest.width);
    // no @page: the options' page as is
    const none = try resolve(aa, opt.Page.a4, .{ .string = "@media print { p { color: red } }" }, null, .{});
    try std.testing.expectEqual(opt.Page.a4.width, none.first.width);
}

test "@page in @media / @supports / @layer, !important, math functions and units" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const aa = arena.allocator();
    const base: opt.Page = .{ .width = 300, .height = 200, .margin = .{ .top = .{ .px = 10 }, .right = .{ .px = 10 }, .bottom = .{ .px = 10 }, .left = .{ .px = 10 } } };
    const top = struct {
        fn f(al: Allocator, b: opt.Page, css: []const u8) !f32 {
            const r = try resolve(al, b, .{ .string = css }, null, .{});
            return r.first.margin.top.px;
        }
    }.f;
    // print media the size of the options' page
    try std.testing.expectEqual(@as(f32, 60), try top(aa, base, "@media print { @page { margin-top: 60px } }"));
    try std.testing.expectEqual(@as(f32, 10), try top(aa, base, "@media screen { @page { margin-top: 60px } }"));
    try std.testing.expectEqual(@as(f32, 60), try top(aa, base, "@media (min-width: 290px) { @page { margin-top: 60px } }"));
    try std.testing.expectEqual(@as(f32, 10), try top(aa, base, "@media (min-width: 310px) { @page { margin-top: 60px } }"));
    try std.testing.expectEqual(@as(f32, 60), try top(aa, base, "@supports (display: grid) { @page { margin-top: 60px } }"));
    // the cascade: importance, then layers (unlayered wins normal, the first layer wins important)
    try std.testing.expectEqual(@as(f32, 60), try top(aa, base, "@page { margin-top: 60px !important } @page :first { margin-top: 0 }"));
    try std.testing.expectEqual(@as(f32, 30), try top(aa, base, "@page { margin-top: 30px } @layer a { @page { margin-top: 60px } }"));
    try std.testing.expectEqual(@as(f32, 60), try top(aa, base, "@layer a { @page { margin-top: 60px !important } } @page { margin-top: 30px !important }"));
    try std.testing.expectEqual(@as(f32, 60), try top(aa, base, "@layer a, b; @layer b { @page { margin-top: 60px } } @layer a { @page { margin-top: 30px } }"));
    // calc(), viewport units of the options' page, a percentage of the page's height
    try std.testing.expectEqual(@as(f32, 30), try top(aa, base, "@page { margin: calc(10px + 2 * 10px) }"));
    try std.testing.expectEqual(@as(f32, 20), try top(aa, base, "@page { margin-top: 10vh }"));
    try std.testing.expectEqual(@as(f32, 25), try top(aa, base, "@page { margin: calc(10% + 5px) }"));
    // an invalid declaration is dropped alone; a margin box is skipped with the descriptors around it kept
    try std.testing.expectEqual(@as(f32, 60), try top(aa, base, "@page { margin-top: 60px; margin-top: bogus }"));
    try std.testing.expectEqual(@as(f32, 60), try top(aa, base, "@page { @top-left { content: \"X\" } margin-top: 60px }"));
    // size: lengths in any unit, unitless px; an undefined var() unsets the descriptor
    const r = try resolve(aa, base, .{ .string = "@page { size: calc(200px + 100px) 240px }" }, null, .{});
    try std.testing.expectEqual(@as(f32, 300), r.first.width);
    try std.testing.expectEqual(@as(f32, 240), r.first.height);
    const u = try resolve(aa, base, .{ .string = "@page { size: 400 300 } @page { size: var(--nope) 100px }" }, null, .{});
    try std.testing.expectEqual(@as(f32, 300), u.first.width);
}
