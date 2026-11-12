//! `@page` rules (the part of takumi-pdf `page_kinds.rs` / `PageOptions::with_page_rules` and
//! takumi-core `style/page_rule.rs` bm-engine supports): the page a document's stylesheets give the
//! `size` / `margin` options, CSS winning as Chromium's `preferCSSPageSize` lets it.
//!
//! Supported: `@page`, `@page :first`, `@page :left`, `@page :right` and named pages (`@page name`,
//! `@page name:first` ..., the pages the `page` property names: page_names.zig) at the top level of
//! the `css` option's string entries and of an HTML source's `<style>` elements, cascaded per page
//! name and kind of page as Blink's `PageRuleCollector` (specificity: a name 4, `:first` 2,
//! `:left` / `:right` 1, then source order; a rule without a name selects every page, a named one
//! the pages of its name); the first page is a right page, a left one under a root `direction: rtl`
//! (takumi `PageKind::of`). Descriptors `size` (`auto`, a keyword `A3`..`letter` with `portrait` /
//! `landscape`, an orientation alone, one or two lengths) and `margin` (1-4 values), `margin-top` /
//! `-right` / `-bottom` / `-left` (lengths in px, mm, cm, in, pt, pc, q, and `em` / `rem` of the
//! root element's font size; `var()` of the root element's custom properties; percentages of the
//! page's size on the side's axis; `auto` = 0 as Blink's `ResolveAutoMargins`). A page whose
//! margins leave no page area keeps the options' geometry (Blink's `LayoutPageContainer`).
//!
//! Not supported (takumi supports them; bm-engine lays the content out once at one width): pages
//! of different widths. When the `:left` / `:right` rules give left and right pages different page
//! or page-area widths they are ignored as a whole; when the first page then still differs, its
//! `:first` rules are. A named page keeps its size and margins whatever its width: the content,
//! laid out at the unnamed pages' width, sits in its page area from the left (paged.zig). Not
//! supported either: `@page` inside `@media` / `@layer` / `@supports`, viewport units in page
//! descriptors, rule objects in `css`, and the page-margin boxes (`@top-center` ...), which takumi
//! does not draw either.
const std = @import("std");
const json = @import("../json.zig");
const opt = @import("options.zig");

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
/// size (`em` / `rem`) and custom properties (`var()`).
pub const Context = struct {
    rtl: bool = false,
    font_size: f32 = 16,
    ctx: *const anyopaque = undefined,
    custom: ?*const fn (ctx: *const anyopaque, name: []const u8) ?[]const u8 = null,
};

const Pseudo = enum { none, first, left, right };
const Rule = struct { pseudo: Pseudo, body: []const u8, name: ?[]const u8 = null };

const Decls = struct {
    size: ?[]const u8 = null,
    margin: [4]?[]const u8 = .{ null, null, null, null },
    any: bool = false,
};

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
    var rules: std.ArrayList(Rule) = .empty;
    for (texts.items) |t| try scan(a, t, &rules);
    if (rules.items.len == 0) return .{ .first = base, .left = base, .right = base, .rest = base, .rtl = cx.rtl };
    var contextual = false;
    for (rules.items) |r| {
        if (r.pseudo == .left or r.pseudo == .right) contextual = true;
        if (std.mem.indexOf(u8, r.body, "em") != null or std.mem.indexOf(u8, r.body, "var(") != null) contextual = true;
    }
    var sides = true;
    var first_rules = true;
    while (true) {
        const right = try kindPage(a, base, rules.items, .right, cx, sides, first_rules, null);
        const left = try kindPage(a, base, rules.items, .left, cx, sides, first_rules, null);
        // (the content lays out once, at one width)
        if (sides and !sameWidth(left, right)) {
            sides = false;
            continue;
        }
        const first = try kindPage(a, base, rules.items, .first, cx, sides, first_rules, null);
        if (first_rules and !sameWidth(first, right)) {
            first_rules = false;
            continue;
        }
        // the pages of each name a rule selects
        var named: std.ArrayList(Pages.Named) = .empty;
        for (rules.items) |r| {
            const nm = r.name orelse continue;
            const seen = for (named.items) |e| {
                if (std.mem.eql(u8, e.name, nm)) break true;
            } else false;
            if (seen) continue;
            try named.append(a, .{
                .name = nm,
                .first = try kindPage(a, base, rules.items, .first, cx, sides, first_rules, nm),
                .left = try kindPage(a, base, rules.items, .left, cx, sides, first_rules, nm),
                .right = try kindPage(a, base, rules.items, .right, cx, sides, first_rules, nm),
            });
        }
        return .{ .first = first, .left = left, .right = right, .rest = right, .rtl = cx.rtl, .contextual = contextual, .named = named.items };
    }
}

fn sameWidth(x: opt.Page, y: opt.Page) bool {
    const wx = x.width - marginPx(x.margin.left) - marginPx(x.margin.right);
    const wy = y.width - marginPx(y.margin.left) - marginPx(y.margin.right);
    return wx == wy and x.width == y.width;
}

/// The cascade of the rules matching `kind` pages named `name` (null: unnamed) (Blink's
/// `PageRuleCollector`: by specificity, then in source order) applied to `base`.
fn kindPage(a: Allocator, base: opt.Page, rules: []const Rule, kind: Kind, cx: Context, sides: bool, first: bool, name: ?[]const u8) Allocator.Error!opt.Page {
    var d: Decls = .{};
    const is_left = switch (kind) {
        .first => cx.rtl,
        .left => true,
        .right => false,
    };
    for ([_]u3{ 0, 1, 2, 4, 5, 6 }) |spec| for (rules) |r| {
        if (r.name) |rn| {
            const nm = name orelse continue;
            if (!std.mem.eql(u8, rn, nm)) continue;
        }
        const s: u3 = @as(u3, if (r.name != null) 4 else 0) + @as(u3, switch (r.pseudo) {
            .none => 0,
            .left, .right => 1,
            .first => 2,
        });
        const ok = switch (r.pseudo) {
            .none => true,
            .left => sides and is_left,
            .right => sides and !is_left,
            .first => first and kind == .first,
        };
        if (s == spec and ok) try declarations(a, r.body, &d, cx);
    };
    if (!d.any) return base;
    return apply(base, d, cx);
}

fn marginPx(m: opt.Margin) f32 {
    return switch (m) {
        .px => |v| v,
        .auto => 0,
    };
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

/// Collects the top-level `@page` rules of `css` with a supported selector (none, `:first`,
/// `:left`, `:right`; takumi's `PageSelector::parse`), in source order.
fn scan(a: Allocator, css: []const u8, rules: *std.ArrayList(Rule)) Allocator.Error!void {
    var i: usize = 0;
    var depth: usize = 0;
    while (i < css.len) {
        const c = css[i];
        if (c == '/' and i + 1 < css.len and css[i + 1] == '*') {
            i = if (std.mem.indexOfPos(u8, css, i + 2, "*/")) |e| e + 2 else css.len;
            continue;
        }
        if (c == '"' or c == '\'') {
            i = (std.mem.indexOfScalarPos(u8, css, i + 1, c) orelse css.len - 1) + 1;
            continue;
        }
        if (c == '{') depth += 1;
        if (c == '}') depth -|= 1;
        if (c == '@' and depth == 0 and i + 5 <= css.len and std.ascii.eqlIgnoreCase(css[i + 1 .. @min(css.len, i + 5)], "page") and (i + 5 == css.len or !isIdent(css[i + 5]))) {
            const open = std.mem.indexOfScalarPos(u8, css, i, '{') orelse return;
            const prelude = std.mem.trim(u8, css[i + 5 .. open], " \t\r\n\x0c");
            const close = blockEnd(css, open) orelse css.len;
            const body = css[open + 1 .. @min(close, css.len)];
            // takumi `PageSelector::parse`: a page name, a pseudo-class, both, or nothing
            var name: ?[]const u8 = null;
            var rest = prelude;
            var k: usize = 0;
            while (k < rest.len and (isIdent(rest[k]) or rest[k] >= 0x80)) k += 1;
            if (k > 0) {
                name = rest[0..k];
                rest = std.mem.trim(u8, rest[k..], " \t\r\n\x0c");
            }
            const pseudo: ?Pseudo = if (rest.len == 0)
                .none
            else if (std.ascii.eqlIgnoreCase(rest, ":first"))
                .first
            else if (std.ascii.eqlIgnoreCase(rest, ":left"))
                .left
            else if (std.ascii.eqlIgnoreCase(rest, ":right"))
                .right
            else
                null;
            const bad_name = if (name) |nm| std.ascii.isDigit(nm[0]) or (nm[0] == '-' and (nm.len < 2 or std.ascii.isDigit(nm[1]))) else false;
            if (pseudo) |p| if (!bad_name) try rules.append(a, .{ .pseudo = p, .body = body, .name = name });
            i = close + 1;
            continue;
        }
        i += 1;
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

fn blockEnd(css: []const u8, open: usize) ?usize {
    var d: usize = 0;
    var i = open;
    while (i < css.len) : (i += 1) {
        if (css[i] == '{') d += 1;
        if (css[i] == '}') {
            d -= 1;
            if (d == 0) return i;
        }
    }
    return null;
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

fn declarations(a: Allocator, body: []const u8, d: *Decls, cx: Context) Allocator.Error!void {
    var it = std.mem.splitScalar(u8, body, ';');
    while (it.next()) |decl| {
        const colon = std.mem.indexOfScalar(u8, decl, ':') orelse continue;
        const name = std.mem.trim(u8, decl[0..colon], " \t\r\n\x0c");
        var value = std.mem.trim(u8, decl[colon + 1 ..], " \t\r\n\x0c");
        if (std.mem.indexOf(u8, value, "!important")) |k| value = std.mem.trim(u8, value[0..k], " \t\r\n\x0c");
        if (std.mem.indexOfScalar(u8, name, '{') != null) continue; // a nested margin box
        value = (try substitute(a, value, cx, 0)) orelse continue;
        if (std.ascii.eqlIgnoreCase(name, "size")) {
            d.size = value;
        } else if (std.ascii.eqlIgnoreCase(name, "margin")) {
            var vals: [4][]const u8 = undefined;
            var n: usize = 0;
            var vt = std.mem.tokenizeAny(u8, value, " \t\r\n\x0c");
            while (vt.next()) |v| {
                if (n == 4) {
                    n = 5;
                    break;
                }
                vals[n] = v;
                n += 1;
            }
            if (n == 0 or n > 4) continue;
            const t = vals[0];
            const r = if (n > 1) vals[1] else t;
            const b = if (n > 2) vals[2] else t;
            const l = if (n > 3) vals[3] else r;
            d.margin = .{ t, r, b, l };
        } else {
            const sides = [_][]const u8{ "margin-top", "margin-right", "margin-bottom", "margin-left" };
            for (sides, 0..) |s, k| if (std.ascii.eqlIgnoreCase(name, s)) {
                d.margin[k] = value;
            };
            if (!std.ascii.startsWithIgnoreCase(name, "margin")) continue;
        }
        d.any = true;
    }
}

/// A length in px (`basis` resolves a percentage; null: none allowed), null when not one.
fn length(v: []const u8, basis: ?f32, cx: Context) ?f32 {
    if (std.mem.eql(u8, v, "0")) return 0;
    const units = [_]struct { []const u8, f32 }{
        .{ "px", 1 },                .{ "mm", opt.one_mm_in_px },        .{ "cm", opt.one_cm_in_px },
        .{ "in", opt.one_in_px },    .{ "pt", opt.one_pt_in_px },        .{ "pc", 12 * opt.one_pt_in_px },
        .{ "q", opt.one_mm_in_px / 4 }, .{ "rem", cx.font_size },       .{ "em", cx.font_size },
    };
    if (v.len > 1 and v[v.len - 1] == '%') {
        const b = basis orelse return null;
        const n = std.fmt.parseFloat(f32, v[0 .. v.len - 1]) catch return null;
        return n / 100 * b;
    }
    for (units) |u| if (v.len > u[0].len and std.ascii.endsWithIgnoreCase(v, u[0])) {
        const n = std.fmt.parseFloat(f32, v[0 .. v.len - u[0].len]) catch return null;
        return n * u[1];
    };
    return null;
}

fn apply(base: opt.Page, d: Decls, cx: Context) opt.Page {
    var p = base;
    if (d.size) |sz| sized(&p, sz, cx);
    const axes = [4]f32{ p.height, p.width, p.height, p.width };
    var m = [4]opt.Margin{ p.margin.top, p.margin.right, p.margin.bottom, p.margin.left };
    for (d.margin, 0..) |mv, k| {
        const v = mv orelse continue;
        if (std.ascii.eqlIgnoreCase(v, "auto")) {
            m[k] = .{ .px = 0 };
        } else if (length(v, axes[k], cx)) |px| m[k] = .{ .px = px };
    }
    p.margin = .{ .top = m[0], .right = m[1], .bottom = m[2], .left = m[3] };
    // Blink's `LayoutPageContainer` ignores the author's page style when it leaves no page area
    if (p.contentSize(p.resolveMargins(null, null)) == null) return base;
    return p;
}

fn sized(p: *opt.Page, value: []const u8, cx: Context) void {
    var it = std.mem.tokenizeAny(u8, value, " \t\r\n\x0c");
    const first = it.next() orelse return;
    if (std.ascii.eqlIgnoreCase(first, "auto")) return;
    if (length(first, null, cx)) |w| {
        const h = if (it.next()) |s| length(s, null, cx) orelse return else w;
        if (w < 0 or h < 0) return;
        p.width = w;
        p.height = h;
        return;
    }
    var w = p.width;
    var h = p.height;
    var orient: ?bool = null; // landscape
    var tok: ?[]const u8 = first;
    var named = false;
    while (tok) |t| : (tok = it.next()) {
        if (std.ascii.eqlIgnoreCase(t, "landscape") or std.ascii.eqlIgnoreCase(t, "portrait")) {
            if (orient != null) return;
            orient = std.ascii.eqlIgnoreCase(t, "landscape");
        } else {
            if (named) return;
            const s = opt.Page.named(t) orelse return;
            w = s.width;
            h = s.height;
            named = true;
        }
    }
    if (orient) |land| {
        if ((land and w < h) or (!land and w > h)) std.mem.swap(f32, &w, &h);
    }
    p.width = w;
    p.height = h;
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
    // :left / :right that change the page area's width are ignored; a :first rule that changes
    // the width is
    const sides = try resolve(aa, opt.Page.a4, .{ .string = "@page { margin: 10px } @page :left { margin-left: 30px }" }, null, .{});
    try std.testing.expectEqual(@as(f32, 10), sides.left.margin.left.px);
    const wide = try resolve(aa, opt.Page.a4, .{ .string = "@page { size: A5 } @page :first { size: A5 landscape }" }, null, .{});
    try std.testing.expectEqual(wide.rest.width, wide.first.width);
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
