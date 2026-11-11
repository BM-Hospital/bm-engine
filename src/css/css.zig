//! CSS stylesheet / selector / cascade module (takumi `css` render option, `<style>` of HTML input,
//! inline `style` attribute text). Standalone: std only. Property VALUES are not parsed here; the
//! output is ordered declaration lists for the style module.
//!
//! Typical use (per render, `arena` = render arena):
//! ```
//! var sheet: css.Stylesheet = .{};
//! for (css_entries) |e| try css.addRuleJson(arena, &sheet, e);      // strings or rule objects
//!   // (or: build one text with css.writeCssInput for every entry, then css.parse once: exact takumi
//!   //  behaviour for unterminated blocks that span entries)
//! try css.addKeyframesJson(arena, &sheet, deprecated_keyframes_option);  // optional
//! const m = try css.prepare(arena, &sheet, .{ .viewport_w = w, .viewport_h = h, .dpr = dpr, .supports = fn });
//! var scratch = css.Scratch.init(arena);
//! for each element el (in any order):
//!     decls.clearRetainingCapacity();
//!     const r = try css.match(&m, &scratch, &dom, el, .none, &decls);
//!     // apply, last wins:  presets/presentation attrs  <  decls[0..r.important_start]
//!     //   <  inline style normal  <  decls[r.important_start..]  <  inline style !important
//!     // (preset / tw ordering is the integrator's: takumi puts `tw` utilities in a layer declared
//!     //  after every named @layer of the sheet, i.e. after layered rules but before unlayered ones.)
//!     if (m.has_before and !replaced) { r2 = css.match(..., .before, ...); create ::before only if r2.sets_content }
//! ```
//! Importance: the returned list is already fully ordered — normal declarations ascending, then
//! `!important` ones ascending (unlayered important first, then layered important in REVERSE layer
//! order, as CSS Cascade 5 requires). A consumer applying "last wins" in list order gets the right
//! result, provided it inserts inline-style normal declarations at `important_start` and inline
//! `!important` ones at the end. Invalid values must be dropped one declaration at a time (takumi).
//! Pseudo-elements: only `::before` / `::after` produce matches; takumi creates the box only when a
//! matched declaration sets `content` (`MatchResult.sets_content`) and never for replaced elements
//! (images). Each call with `.before`/`.after` only considers selectors ending in that pseudo-element;
//! the pseudo's style inherits from the element.
const std = @import("std");

pub const tokenizer = @import("tokenizer.zig");
pub const selector = @import("selector.zig");
pub const media = @import("media.zig");
pub const sheet = @import("sheet.zig");
pub const cascade = @import("cascade.zig");
pub const json_rules = @import("json_rules.zig");

pub const Declaration = sheet.Declaration;
pub const Stylesheet = sheet.Stylesheet;
pub const Keyframe = sheet.Keyframe;
pub const KeyframesRule = sheet.KeyframesRule;
pub const FontFace = sheet.FontFace;
pub const Env = media.Env;
pub const Matcher = cascade.Matcher;
pub const Scratch = cascade.Scratch;
pub const MatchResult = cascade.MatchResult;
pub const Pseudo = cascade.Pseudo;
pub const Element = selector.Element;
pub const Dom = selector.Dom;
pub const Dir = selector.Dir;

/// Parses stylesheet text, appending to `sheet` (error tolerant; only OOM fails). `text` must outlive
/// the sheet (declarations borrow from it).
pub const parse = sheet.parse;
/// Parses a declaration list (`style="..."` attribute text). Invalid declarations are skipped.
pub const parseDeclarations = sheet.parseDeclarations;
/// One `css` option entry (string or rule object, as a JSON DOM value) -> parsed into `sheet`.
/// error.InvalidRule mirrors takumi failing the render for an invalid rule object.
pub const addRuleJson = json_rules.addRuleJson;
/// Validates one `css` entry and appends its CSS text to a buffer (to parse all entries as one text).
pub const writeCssInput = json_rules.writeCssInput;
/// Deprecated `keyframes` render option (KeyframesMap or KeyframesRuleList JSON).
pub const addKeyframesJson = json_rules.addKeyframesJson;
/// Evaluates @media/@supports for `env`, orders layers, buckets rules.
pub const prepare = cascade.prepare;
/// Cascade-ordered declarations of the rules matching an element (see module doc).
pub const match = cascade.match;
/// Keyframes by animation name (last matching definition wins; null = not defined).
pub const keyframes = cascade.keyframes;

/// Active `@font-face` rules (their `@media` matched) after `prepare`, in source order.
pub fn fontFaces(m: *const Matcher) []const *const FontFace {
    return m.font_faces;
}

/// Whether a declaration list sets `content` (for pseudo-element creation).
pub fn setsContent(decls: []const Declaration) bool {
    for (decls) |d| if (std.mem.eql(u8, d.name, "content")) return true;
    return false;
}

// =================================================================================================
// Tests

test {
    _ = @import("vec.zig");
    _ = tokenizer;
    _ = selector;
    _ = media;
    _ = sheet;
    _ = cascade;
    _ = json_rules;
}

const T = std.testing;

/// Tiny test DOM: nodes in preorder with parent links.
pub const TestDom = struct {
    pub const Node = struct {
        tag: []const u8 = "",
        id: []const u8 = "",
        class: []const u8 = "",
        attrs: []const [2][]const u8 = &.{},
        parent: ?usize = null,
        text: bool = false, // bare text run (not an element)
        text_len: u32 = 0, // for :empty of an element holding text
        dir: Dir = .none,
    };
    nodes: []const Node,

    fn self(ctx: *const anyopaque) *const TestDom {
        return @ptrCast(@alignCast(ctx));
    }
    fn n(ctx: *const anyopaque, e: Element) Node {
        return self(ctx).nodes[e];
    }
    fn tag(ctx: *const anyopaque, e: Element) []const u8 {
        return n(ctx, e).tag;
    }
    fn id(ctx: *const anyopaque, e: Element) []const u8 {
        return n(ctx, e).id;
    }
    fn classes(ctx: *const anyopaque, e: Element) []const u8 {
        return n(ctx, e).class;
    }
    fn attr(ctx: *const anyopaque, e: Element, name: []const u8) ?[]const u8 {
        const node = n(ctx, e);
        if (std.mem.eql(u8, name, "id")) return if (node.id.len > 0) node.id else null;
        if (std.mem.eql(u8, name, "class")) return if (node.class.len > 0) node.class else null;
        for (node.attrs) |a| if (std.ascii.eqlIgnoreCase(a[0], name)) return a[1];
        return null;
    }
    fn parent(ctx: *const anyopaque, e: Element) ?Element {
        return n(ctx, e).parent;
    }
    fn sib(ctx: *const anyopaque, e: Element, dir_: i32) ?Element {
        const d = self(ctx);
        const p = d.nodes[e].parent;
        var i: i64 = @as(i64, @intCast(e)) + dir_;
        while (i >= 0 and i < d.nodes.len) : (i += dir_) {
            const k: usize = @intCast(i);
            if (d.nodes[k].parent == p and p != null) {
                if (!d.nodes[k].text) return k;
            }
            // stop when leaving the parent's subtree going backwards past the parent
            if (dir_ < 0 and p != null and k == p.?) return null;
        }
        return null;
    }
    fn prev(ctx: *const anyopaque, e: Element) ?Element {
        return sib(ctx, e, -1);
    }
    fn next(ctx: *const anyopaque, e: Element) ?Element {
        return sib(ctx, e, 1);
    }
    fn first(ctx: *const anyopaque, e: Element) ?Element {
        const d = self(ctx);
        var k = e + 1;
        while (k < d.nodes.len) : (k += 1) {
            if (d.nodes[k].parent == e and !d.nodes[k].text) return k;
        }
        return null;
    }
    fn empty(ctx: *const anyopaque, e: Element) bool {
        const d = self(ctx);
        if (d.nodes[e].text_len > 0) return false;
        for (d.nodes, 0..) |c, k| {
            _ = k;
            if (c.parent == e and (!c.text or c.text_len > 0)) return false;
        }
        return true;
    }
    fn dirf(ctx: *const anyopaque, e: Element) Dir {
        return n(ctx, e).dir;
    }
    pub fn dom(d: *const TestDom) Dom {
        return .{ .ctx = d, .tag = tag, .id = id, .classes = classes, .attr = attr, .parent = parent, .prev_sibling = prev, .next_sibling = next, .first_child = first, .is_empty = empty, .dir = dirf };
    }
};

/// Matches `css` against node `el` and returns the winning value of `prop` (or null).
fn winner(arena: std.mem.Allocator, css_text: []const u8, d: *const TestDom, el: Element, pseudo: Pseudo, env: Env, prop: []const u8) !?[]const u8 {
    var sh: Stylesheet = .{};
    try parse(arena, css_text, &sh);
    const m = try prepare(arena, &sh, env);
    var scratch = Scratch.init(arena);
    var out: std.ArrayList(Declaration) = .empty;
    _ = try match(&m, &scratch, &d.dom(), el, pseudo, &out);
    var w: ?[]const u8 = null;
    for (out.items) |dd| if (std.mem.eql(u8, dd.name, prop)) {
        w = dd.value;
    };
    return w;
}

fn selMatches(arena: std.mem.Allocator, s: []const u8, d: *const TestDom, el: Element) !bool {
    const list = (try selector.parseList(arena, s, 0, s.len, .{}, null)) orelse return error.InvalidSelector;
    const dm = d.dom();
    var cx: selector.MatchCx = .{ .dom = &dm };
    for (list) |*c| if (c.pseudo == .none and selector.matches(&cx, c, el)) return true;
    return false;
}

fn specOf(arena: std.mem.Allocator, s: []const u8) !u32 {
    const list = (try selector.parseList(arena, s, 0, s.len, .{}, null)) orelse return error.InvalidSelector;
    return list[0].spec;
}

fn spec3(a: u32, b: u32, c: u32) u32 {
    return (selector.Spec{ .a = a, .b = b, .c = c }).pack();
}

// html > body > (div#main.a.b[data-x="Hello World"] > (p, span.x, p.y, em), section[lang=en-US] > p, ul > li*4)
const tree = [_]TestDom.Node{
    .{ .tag = "html" }, // 0
    .{ .tag = "body", .parent = 0 }, // 1
    .{ .tag = "div", .id = "main", .class = "a  b", .attrs = &.{ .{ "data-x", "Hello World" }, .{ "type", "TEXT" } }, .parent = 1 }, // 2
    .{ .tag = "p", .parent = 2 }, // 3
    .{ .text = true, .text_len = 3, .parent = 2 }, // 4 bare text
    .{ .tag = "span", .class = "x", .parent = 2 }, // 5
    .{ .tag = "P", .class = "y", .parent = 2 }, // 6
    .{ .tag = "em", .parent = 2, .text_len = 0 }, // 7
    .{ .tag = "section", .attrs = &.{.{ "lang", "en-US" }}, .parent = 1, .dir = .rtl }, // 8
    .{ .tag = "p", .parent = 8, .text_len = 2 }, // 9
    .{ .tag = "ul", .parent = 1 }, // 10
    .{ .tag = "li", .parent = 10 }, // 11
    .{ .tag = "li", .parent = 10 }, // 12
    .{ .tag = "li", .class = "z", .parent = 10 }, // 13
    .{ .tag = "li", .parent = 10 }, // 14
};

test "selector matching" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const d: TestDom = .{ .nodes = &tree };
    const yes = [_]struct { []const u8, Element }{
        .{ "div", 2 },                         .{ "DIV", 2 },                     .{ "*", 3 },
        .{ "#main", 2 },                       .{ ".a.b", 2 },                    .{ "div.a#main", 2 },
        .{ "[data-x]", 2 },                    .{ "[DATA-X]", 2 },                .{ "[data-x=\"Hello World\"]", 2 },
        .{ "[data-x~=World]", 2 },             .{ "[data-x^=Hell]", 2 },          .{ "[data-x$=rld]", 2 },
        .{ "[data-x*=\"o W\"]", 2 },           .{ "[data-x=\"hello world\" i]", 2 }, .{ "[type=text]", 2 },
        .{ "[lang|=en]", 8 },                  .{ "body > div > p", 3 },          .{ "html p", 9 },
        .{ "p + span", 5 },                    .{ "p ~ em", 7 },                  .{ "p ~ p", 6 },
        .{ ":root", 0 },                       .{ "p:first-child", 3 },           .{ "em:last-child", 7 },
        .{ "section > p:only-child", 9 },      .{ "span:first-of-type", 5 },      .{ "p:last-of-type", 6 },
        .{ "span:only-of-type", 5 },           .{ "em:empty", 7 },                .{ "li:nth-child(2n+1)", 13 },
        .{ "li:nth-child(odd)", 11 },          .{ "li:nth-child(even)", 14 },     .{ "li:nth-child(3)", 13 },
        .{ "li:nth-last-child(1)", 14 },       .{ "li:nth-child(-n+2)", 12 },     .{ "li:nth-child(n+3)", 14 },
        .{ "li:nth-of-type(4)", 14 },         .{ "li:nth-child(1)", 11 },        .{ "li:nth-last-of-type(4)", 11 },
        .{ "p:not(.y)", 3 },                   .{ ":is(span, em)", 7 },           .{ ":where(.x)", 5 },
        .{ "div:has(> span.x)", 2 },           .{ "body:has(li.z)", 1 },          .{ "p:has(+ span)", 3 },
        .{ "span:has(~ em)", 5 },              .{ "html:has(section p)", 0 },     .{ "p:lang(en)", 9 },
        .{ "p:dir(rtl)", 9 },                  .{ "p:dir(ltr)", 3 },              .{ "*|p", 3 },
        .{ "li:nth-child( 2n + 1 )", 11 },     .{ "li:nth-child(+n)", 11 },       .{ "li:nth-child(-2n+3)", 11 },
        .{ ":is(div, nonsense:foo(), ::before) > p", 3 },
    };
    for (yes) |c| {
        if (!try selMatches(a, c[0], &d, c[1])) {
            std.debug.print("expected match: {s} on {d}\n", .{ c[0], c[1] });
            return error.TestExpectedMatch;
        }
    }
    const no = [_]struct { []const u8, Element }{
        .{ "span", 2 },             .{ "#MAIN", 2 },              .{ ".A", 2 },
        .{ "[data-x=hello]", 2 },   .{ "[data-x~=\"o W\"]", 2 },  .{ "[data-x=\"hello world\" s]", 2 },
        .{ "[data-x^=\"\"]", 2 },   .{ "div > p.y > em", 7 },    .{ "span + em", 7 },
        .{ "p:first-child", 6 },    .{ "span:last-child", 5 },    .{ "p:empty", 9 },
        .{ "li:nth-child(2n)", 13 }, .{ "li:nth-child(-n+2)", 13 }, .{ "p:hover", 3 },
        .{ "p:not(p)", 3 },         .{ "div:has(> em.x)", 2 },    .{ "p:lang(fr)", 9 },
        .{ "p:dir(rtl)", 3 },       .{ ":root", 1 },              .{ "a:link", 2 },
        .{ "div:any-link", 2 },     .{ "p:nth-of-type(3)", 6 },   .{ "section ~ div", 2 },
    };
    for (no) |c| {
        if (try selMatches(a, c[0], &d, c[1])) {
            std.debug.print("unexpected match: {s} on {d}\n", .{ c[0], c[1] });
            return error.TestUnexpectedMatch;
        }
    }
    const invalid = [_][]const u8{ "", "a,", ">a", "a >", "#1a", ".", "[a", "[a=]", "a::before.x", ":not()", "li:nth-child(2n+)", ":has(:has(a))", "::before::after", "ns|a", "a{", "li:nth-of-type(1 of a)", "li:nth-child(1 of .z)" };
    for (invalid) |s| {
        if ((try selector.parseList(a, s, 0, s.len, .{}, null)) != null) {
            std.debug.print("expected invalid: {s}\n", .{s});
            return error.TestExpectedInvalid;
        }
    }
}

test "specificity" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const cases = [_]struct { []const u8, u32 }{
        .{ "*", spec3(0, 0, 0) },
        .{ "li", spec3(0, 0, 1) },
        .{ "ul li", spec3(0, 0, 2) },
        .{ "ul ol+li", spec3(0, 0, 3) },
        .{ "h1 + *[rel=up]", spec3(0, 1, 1) },
        .{ "ul ol li.red", spec3(0, 1, 3) },
        .{ "li.red.level", spec3(0, 2, 1) },
        .{ "#x34y", spec3(1, 0, 0) },
        .{ "#s12:not(FOO)", spec3(1, 0, 1) },
        .{ ".foo :is(.bar, #baz)", spec3(1, 1, 0) },
        .{ ":where(#a, .b) p", spec3(0, 0, 1) },
        .{ "a:has(> #x)", spec3(1, 0, 1) },
        .{ "p::before", spec3(0, 0, 2) },
        .{ "p:before", spec3(0, 0, 2) },
        .{ ":root", spec3(0, 1, 0) },
        .{ "a:hover", spec3(0, 1, 1) },
    };
    for (cases) |c| {
        const got = try specOf(a, c[0]);
        if (got != c[1]) {
            std.debug.print("{s}: got {x} want {x}\n", .{ c[0], got, c[1] });
            return error.TestSpec;
        }
    }
}

test "cascade order, layers, importance" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const d: TestDom = .{ .nodes = &tree };
    const env: Env = .{ .viewport_w = 800, .viewport_h = 600 };
    const W = struct {
        fn w(al: std.mem.Allocator, dd: *const TestDom, e: Env, css_text: []const u8, el: Element) !?[]const u8 {
            return winner(al, css_text, dd, el, .none, e, "width");
        }
    };
    // specificity beats order
    try T.expectEqualStrings("1", (try W.w(a, &d, env, "#main{width:1} div{width:2}", 2)).?);
    // later source wins at equal specificity
    try T.expectEqualStrings("2", (try W.w(a, &d, env, ".a{width:1} .b{width:2}", 2)).?);
    // !important beats specificity
    try T.expectEqualStrings("2", (try W.w(a, &d, env, "#main{width:1} div{width:2 !important}", 2)).?);
    try T.expectEqualStrings("2", (try W.w(a, &d, env, "div{width:2!IMPORTANT} #main{width:1}", 2)).?);
    // unlayered beats layered; later layer beats earlier
    try T.expectEqualStrings("3", (try W.w(a, &d, env, "div{width:3} @layer x{#main{width:1}}", 2)).?);
    try T.expectEqualStrings("2", (try W.w(a, &d, env, "@layer a, b; @layer b{div{width:2}} @layer a{#main{width:1}}", 2)).?);
    // important: earlier layer wins, layered beats unlayered
    try T.expectEqualStrings("1", (try W.w(a, &d, env, "@layer a, b; @layer b{div{width:2!important}} @layer a{div{width:1!important}}", 2)).?);
    try T.expectEqualStrings("1", (try W.w(a, &d, env, "@layer a{div{width:1!important}} #main{width:2!important}", 2)).?);
    // nested layer names
    try T.expectEqualStrings("2", (try W.w(a, &d, env, "@layer a{@layer b{#main{width:1}}} @layer a.c{div{width:2}}", 2)).?);
    // media
    try T.expectEqualStrings("1", (try W.w(a, &d, env, "div{width:1} @media (max-width: 500px){div{width:2}}", 2)).?);
    try T.expectEqualStrings("2", (try W.w(a, &d, env, "div{width:1} @media (min-width: 500px){div{width:2}}", 2)).?);
    try T.expectEqualStrings("2", (try W.w(a, &d, env, "div{width:1} @media screen{@media (min-width: 500px){div{width:2}}}", 2)).?);
    try T.expect((try W.w(a, &d, env, "@media print{div{width:2}}", 2)) == null);
    // supports
    try T.expectEqualStrings("2", (try W.w(a, &d, env, "@supports (display:grid){div{width:2}}", 2)).?);
    try T.expect((try W.w(a, &d, env, "@supports selector(a){div{width:2}}", 2)) == null);
    // error recovery
    try T.expectEqualStrings("3", (try W.w(a, &d, env, "div{width:1;;width;: x; height 3; width:3} div;{width:9} } div{x:y", 2)).?);
    try T.expectEqualStrings("4", (try W.w(a, &d, env, "@foo bar { div{width:9} } @import url(x.css); div{width:4}", 2)).?);
    try T.expect((try W.w(a, &d, env, "p, #1x, div{width:9}", 2)) == null);
    try T.expect((try W.w(a, &d, env, "p, div:foo(, div{width:9} div{width:5}", 2)) == null);
    try T.expectEqualStrings("6", (try W.w(a, &d, env, "<!-- div{width:6} -->", 2)).?);
    try T.expectEqualStrings("calc(1px + 2px)", (try W.w(a, &d, env, "div{width:/*c*/calc(1px /*x*/+ 2px)/*e*/}", 2)).?);
    // nesting
    try T.expectEqualStrings("7", (try W.w(a, &d, env, "body{ div{width:7} }", 2)).?);
    try T.expectEqualStrings("8", (try W.w(a, &d, env, ".a{ &.b{width:8} }", 2)).?);
    try T.expectEqualStrings("9", (try W.w(a, &d, env, "body{ > div{width:9} }", 2)).?);
    try T.expect((try W.w(a, &d, env, "html{ > div{width:9} }", 2)) == null);
    try T.expectEqualStrings("10", (try W.w(a, &d, env, "div{ @media (min-width:1px){ width:10 } }", 2)).?);
    try T.expectEqualStrings("11", (try W.w(a, &d, env, "div{ p:first-child &{width:1} } p:first-child ~ div, div{width:11}", 2)).?);
    // takumi swallows `ident:...{}` as a declaration (nested `tag:pseudo{}` rules are lost)
    try T.expect((try W.w(a, &d, env, "body{ div:first-child{width:12} }", 2)) == null);
    try T.expectEqualStrings("12", (try W.w(a, &d, env, "body{ :is(div):first-child{width:12} }", 2)).?);
    // nested: specificity of & = parent's
    try T.expectEqualStrings("13", (try W.w(a, &d, env, "#main{ &{width:13} } .a.b.a.b{width:1}", 2)).?);
    // theme / preflight
    try T.expectEqualStrings("1.5", (try winner(a, "@import \"tailwindcss\";", &d, 0, .none, env, "line-height")).?);
    try T.expectEqualStrings("2", (try winner(a, "@import \"tailwindcss\"; :root{line-height:2}", &d, 0, .none, env, "line-height")).?);
    try T.expectEqualStrings("red", (try winner(a, "@theme { --c: red; }", &d, 0, .none, env, "--c")).?);
    // pseudo-elements
    try T.expectEqualStrings("\"x\"", (try winner(a, "div::before{content:\"x\"} div{content:none}", &d, 2, .before, env, "content")).?);
    try T.expect((try winner(a, "div::after{content:\"x\"}", &d, 2, .before, env, "content")) == null);
    try T.expect((try winner(a, "div::marker{content:\"x\"}", &d, 2, .none, env, "content")) == null);
}

test "match result segments" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const d: TestDom = .{ .nodes = &tree };
    var sh: Stylesheet = .{};
    try parse(a, "div{color:red !important; width:1px} #main{width:2px; --X: { a } } div::after{content:''}", &sh);
    const m = try prepare(a, &sh, .{});
    try T.expect(m.has_after and !m.has_before);
    var scratch = Scratch.init(a);
    var out: std.ArrayList(Declaration) = .empty;
    const r = try match(&m, &scratch, &d.dom(), 2, .none, &out);
    try T.expectEqual(@as(usize, 3), r.important_start);
    try T.expectEqual(@as(usize, 4), out.items.len);
    try T.expectEqualStrings("width", out.items[0].name);
    try T.expectEqualStrings("--X", out.items[2].name);
    try T.expectEqualStrings("{ a }", out.items[2].value);
    try T.expectEqualStrings("color", out.items[3].name);
    try T.expect(out.items[3].important);
    out.clearRetainingCapacity();
    const r2 = try match(&m, &scratch, &d.dom(), 2, .after, &out);
    try T.expect(r2.sets_content);
}

test "declarations, keyframes, font-face" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const ds = try parseDeclarations(a, "  COLOR : Red ; ; bad ; width: 1px !important; margin: {x}; --Foo:  bar baz ;  background: url( a.png ) ");
    try T.expectEqual(@as(usize, 4), ds.len);
    try T.expectEqualStrings("color", ds[0].name);
    try T.expectEqualStrings("Red", ds[0].value);
    try T.expect(ds[1].important);
    try T.expectEqualStrings("--Foo", ds[2].name);
    try T.expectEqualStrings("bar baz", ds[2].value);
    try T.expectEqualStrings("url( a.png )", ds[3].value);

    var sh: Stylesheet = .{};
    try parse(a,
        \\@keyframes fade { from { opacity: 0 } 50%, 75% { opacity: .5 !important; animation-timing-function: ease-in } to { opacity: 1 } 120% { opacity: 9 } }
        \\@media (max-width: 1px) { @keyframes fade { from { opacity: 7 } } }
        \\@font-face { font-family: "My Font"; src: url(a.woff2) format("woff2"); font-weight: 100 900; unicode-range: U+0-FF }
        \\@font-face { font-family: Nope }
    , &sh);
    const m = try prepare(a, &sh, .{ .viewport_w = 100 });
    const kf = keyframes(&m, "FADE").?;
    try T.expectEqual(@as(usize, 4), kf.len);
    try T.expectEqual(@as(f32, 0.75), kf[2].offset);
    try T.expectEqualStrings("ease-in", kf[1].declarations[1].value);
    try T.expect(!kf[1].declarations[0].important);
    try T.expect(keyframes(&m, "nope") == null);
    const ff = fontFaces(&m);
    try T.expectEqual(@as(usize, 1), ff.len);
    try T.expectEqualStrings("My Font", ff[0].family);
    try T.expectEqualStrings("100 900", ff[0].get("font-weight").?);
    try T.expectEqualStrings("U+0-FF", ff[0].get("unicode-range").?);
}

// --- JSON rule objects (tests use std.json; the module itself is duck-typed) ---

const JV = union(enum) {
    null,
    bool: bool,
    number: f64,
    string: []const u8,
    array: []JV,
    object: []JM,
};
const JM = struct { key: []const u8, value: JV };

fn toJV(a: std.mem.Allocator, v: std.json.Value) !JV {
    return switch (v) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .number = @floatFromInt(i) },
        .float => |f| .{ .number = f },
        .number_string => |s| .{ .string = s },
        .string => |s| .{ .string = s },
        .array => |arr| blk: {
            const out = try a.alloc(JV, arr.items.len);
            for (arr.items, 0..) |x, i| out[i] = try toJV(a, x);
            break :blk .{ .array = out };
        },
        .object => |o| blk: {
            const out = try a.alloc(JM, o.count());
            var it = o.iterator();
            var i: usize = 0;
            while (it.next()) |e| : (i += 1) out[i] = .{ .key = e.key_ptr.*, .value = try toJV(a, e.value_ptr.*) };
            break :blk .{ .object = out };
        },
    };
}

fn parseJV(a: std.mem.Allocator, text: []const u8) !JV {
    const v = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
    return toJV(a, v);
}

test "rule objects" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const v = try parseJV(a,
        \\[".a{width:1px}",
        \\ {"selector":".card","style":{"marginTop":2,"--brand":"#5b21b6","WebkitLineClamp":3,"border-width":"1px","color":null},
        \\  "rules":[{"selector":"&:hover","style":{"color":"blue"}}]},
        \\ {"media":"(min-width: 10px)","rules":[{"selector":"p","style":{"width":"5px"}}, "q{width:6px}"]},
        \\ {"supports":"(display: grid)","rules":[{"layer":"base","rules":[{"selector":"i","style":{"width":"7px"}}]}]},
        \\ {"layer":"late"},
        \\ {"keyframes":"spin","steps":[{"offset":"from","style":{"rotate":"0deg"}},{"offset":"to, 50%","style":{"rotate":"1turn"}}]}]
    );
    var buf: std.ArrayList(u8) = .empty;
    for (v.array) |e| try writeCssInput(a, &buf, e);
    try T.expectEqualStrings(".a{width:1px}.card{margin-top:2;--brand:#5b21b6;-webkit-line-clamp:3;border-width:1px;&:hover{color:blue;}}@media (min-width: 10px){p{width:5px;}q{width:6px}}@supports (display: grid){@layer base{i{width:7px;}}}@layer late;@keyframes spin{from{rotate:0deg;}to, 50%{rotate:1turn;}}", buf.items);
    var sh: Stylesheet = .{};
    for (v.array) |e| try addRuleJson(a, &sh, e);
    try T.expectEqual(@as(usize, 6), sh.rules.items.len);
    const bad = [_][]const u8{
        \\{"selector":".a{color:red}.b","style":{}}
        ,
        \\{"selector":".a","style":{"color":"red; width: 999px"}}
        ,
        \\{"selector":".a","extra":1}
        ,
        \\{"keyframes":"a b","steps":[]}
        ,
        \\{"layer":"a b"}
        ,
        \\{"supports":"selector(a)","rules":[]}
        ,
        \\{"keyframes":"k","steps":[{"offset":"middle"}]}
        ,
        \\42
    };
    for (bad) |b| {
        const bv = try parseJV(a, b);
        var bb: std.ArrayList(u8) = .empty;
        if (writeCssInput(a, &bb, bv)) |_| {
            std.debug.print("expected invalid rule object: {s}\n", .{b});
            return error.TestExpectedError;
        } else |_| {}
    }
}

test "deprecated keyframes option" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var sh: Stylesheet = .{};
    try parse(a, "@keyframes fade{from{opacity:0}}", &sh);
    try addKeyframesJson(a, &sh, try parseJV(a,
        \\{"zoom":{"to":{"scale":2}},"fade":{"to":{"opacity":1,"background-color":"red","backgroundColor":"blue"},"from, 50%":{"opacity":"0.5 !important"}}}
    ));
    try addKeyframesJson(a, &sh, try parseJV(a,
        \\[{"name":"slide","keyframes":[{"offsets":[0,0.5],"declarations":{"translate":"10px"}}]}]
    ));
    const m = try prepare(a, &sh, .{});
    const f = keyframes(&m, "fade").?;
    try T.expectEqual(@as(usize, 3), f.len); // "from, 50%" sorts before "to"
    try T.expectEqual(@as(f32, 0), f[0].offset);
    try T.expectEqualStrings("0.5", f[0].declarations[0].value);
    try T.expectEqual(@as(f32, 1), f[2].offset);
    try T.expectEqual(@as(usize, 2), f[2].declarations.len);
    try T.expectEqualStrings("background-color", f[2].declarations[1].name);
    try T.expectEqual(@as(usize, 2), keyframes(&m, "slide").?.len);
    try T.expect(keyframes(&m, "zoom") != null);
    var bad: Stylesheet = .{};
    try T.expectError(error.InvalidRule, addKeyframesJson(a, &bad, try parseJV(a,
        \\{"x":{" , ":{"opacity":1}}}
    )));
}

// --- oracle replay: expectations recorded from takumi by bench/probe/css/oracle.mjs ---

fn testSupports(name: []const u8, value: []const u8) bool {
    _ = value;
    const known = [_][]const u8{ "display", "width", "height", "color", "margin", "padding" };
    for (known) |k| if (std.mem.eql(u8, k, name)) return true;
    return false;
}

test "oracle: takumi cascade winners" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text = @embedFile("testdata/oracle.json");
    const root = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
    const cases = root.object.get("cases").?.array.items;
    var failures: usize = 0;
    var checked: usize = 0;
    for (cases) |c| {
        const name = c.object.get("name").?.string;
        const env_v = c.object.get("env").?.object;
        var env: Env = .{ .supports = testSupports };
        if (env_v.get("w")) |w| env.viewport_w = @floatCast(numOf(w));
        if (env_v.get("h")) |h| env.viewport_h = @floatCast(numOf(h));
        if (env_v.get("dpr")) |d| env.dpr = @floatCast(numOf(d));
        // nodes
        const nv = c.object.get("nodes").?.array.items;
        const nodes = try a.alloc(TestDom.Node, nv.len);
        for (nv, 0..) |n, i| {
            const o = n.object;
            const attrs_v = o.get("attrs").?.array.items;
            const attrs = try a.alloc([2][]const u8, attrs_v.len);
            for (attrs_v, 0..) |p, k| attrs[k] = .{ p.array.items[0].string, p.array.items[1].string };
            const dir_s = o.get("dir").?.string;
            nodes[i] = .{
                .tag = o.get("tag").?.string,
                .id = o.get("id").?.string,
                .class = o.get("cls").?.string,
                .attrs = attrs,
                .parent = switch (o.get("parent").?) {
                    .integer => |p| @intCast(p),
                    else => null,
                },
                .dir = if (std.mem.eql(u8, dir_s, "rtl")) .rtl else if (std.mem.eql(u8, dir_s, "ltr")) .ltr else .none,
            };
        }
        const d: TestDom = .{ .nodes = nodes };
        // css: all entries concatenated into one text, as takumi does
        var buf: std.ArrayList(u8) = .empty;
        for (c.object.get("css").?.array.items) |entry| try writeCssInput(a, &buf, try toJV(a, entry));
        var sh: Stylesheet = .{};
        try parse(a, buf.items, &sh);
        const m = try prepare(a, &sh, env);
        var scratch = Scratch.init(a);
        const expect = c.object.get("expect").?.array.items;
        for (expect, 0..) |ev, i| {
            var out: std.ArrayList(Declaration) = .empty;
            _ = try match(&m, &scratch, &d.dom(), i, .none, &out);
            var got: ?f32 = null;
            for (out.items) |decl| if (std.mem.eql(u8, decl.name, "width")) {
                const v = if (std.mem.endsWith(u8, decl.value, "px")) decl.value[0 .. decl.value.len - 2] else decl.value;
                got = tokenizer.parseNumber(v);
            };
            const want: ?f32 = if (ev == .null) null else @floatCast(numOf(ev));
            checked += 1;
            const ok = if (want) |w| (got != null and @abs(got.? - w) < 0.01) else got == null;
            if (!ok) {
                failures += 1;
                std.debug.print("oracle mismatch [{s}] node {d} <{s}>: want {?d} got {?d}\n", .{ name, i, nodes[i].tag, want, got });
            }
        }
    }
    if (failures > 0) {
        std.debug.print("oracle: {d}/{d} node results differ\n", .{ failures, checked });
        return error.OracleMismatch;
    }
    try T.expect(checked > 200);
}

fn numOf(v: std.json.Value) f64 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => 0,
    };
}

// --- robustness: hostile inputs must not crash, hang or recurse unboundedly ---

fn runAll(a: std.mem.Allocator, text: []const u8, d: *const TestDom) !void {
    var sh: Stylesheet = .{};
    try parse(a, text, &sh);
    _ = try parseDeclarations(a, text);
    const m = try prepare(a, &sh, .{ .viewport_w = 800, .viewport_h = 600 });
    var scratch = Scratch.init(a);
    var out: std.ArrayList(Declaration) = .empty;
    for (0..d.nodes.len) |i| {
        if (d.nodes[i].text) continue;
        out.clearRetainingCapacity();
        _ = try match(&m, &scratch, &d.dom(), i, .none, &out);
        _ = try match(&m, &scratch, &d.dom(), i, .before, &out);
    }
    _ = keyframes(&m, "a");
}

test "fuzz: mutated css never crashes" {
    const d: TestDom = .{ .nodes = &tree };
    const seeds = [_][]const u8{
        "div > p:nth-child(2n+1 of .a), .x:not(#y)::before{width:1px !important; --v: { a } } @media (min-width: 1px) and (orientation: landscape){ p{color:red} }",
        "@layer a, b.c; @layer b.c{ :is(p, :where(em, :has(> i ~ b))) [data-x~=\"q\" i]{x:y} } @supports not ((a:b) or (c:d)){ e{f:g} }",
        ".a{ &.b{ > c{ d:e } @media print{ f:g } } h:i{j:k} l:m; } @keyframes k{ from{a:b} 50%,to{c:d} } @font-face{font-family:\"x\";src:url(a)}",
        "@import \"tailwindcss\"; @theme{ --c: red; @keyframes q{to{x:y}} } u\\31 \\:x{y:z} /* c */ url( a ) \"str\\\"\" <!-- -->",
    };
    const specials = "{}()[];:,.#>+~*|&!@\"'\\/ \n-_0123456789n%";
    var prng = std.Random.DefaultPrng.init(0x5eed_c55);
    const rnd = prng.random();
    var buf: [600]u8 = undefined;
    var iter: usize = 0;
    while (iter < 6000) : (iter += 1) {
        var arena_state = std.heap.ArenaAllocator.init(T.allocator);
        defer arena_state.deinit();
        const a = arena_state.allocator();
        const seed = seeds[rnd.uintLessThan(usize, seeds.len)];
        var len: usize = @min(seed.len, buf.len);
        @memcpy(buf[0..len], seed[0..len]);
        const muts = 1 + rnd.uintLessThan(usize, 8);
        for (0..muts) |_| {
            const pos = if (len == 0) 0 else rnd.uintLessThan(usize, len);
            switch (rnd.uintLessThan(u8, 4)) {
                0 => if (len > 0) {
                    buf[pos] = specials[rnd.uintLessThan(usize, specials.len)];
                },
                1 => if (len < buf.len) { // insert
                    std.mem.copyBackwards(u8, buf[pos + 1 .. len + 1], buf[pos..len]);
                    buf[pos] = specials[rnd.uintLessThan(usize, specials.len)];
                    len += 1;
                },
                2 => if (len > 0) { // delete
                    std.mem.copyForwards(u8, buf[pos .. len - 1], buf[pos + 1 .. len]);
                    len -= 1;
                },
                else => len = pos, // truncate
            }
        }
        try runAll(a, buf[0..len], &d);
    }
    // random bytes
    iter = 0;
    while (iter < 2000) : (iter += 1) {
        var arena_state = std.heap.ArenaAllocator.init(T.allocator);
        defer arena_state.deinit();
        const len = rnd.uintLessThan(usize, buf.len);
        for (buf[0..len]) |*c| c.* = if (rnd.boolean()) specials[rnd.uintLessThan(usize, specials.len)] else rnd.int(u8);
        try runAll(arena_state.allocator(), buf[0..len], &d);
    }
}

test "fuzz: deep nesting and pathological selectors are bounded" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // a 3000-deep chain of <i> plus siblings
    const n_nodes = 3000;
    const nodes = try a.alloc(TestDom.Node, n_nodes);
    for (nodes, 0..) |*nd, i| nd.* = .{ .tag = "i", .class = if (i % 7 == 0) "a" else "b", .parent = if (i == 0) null else i - 1 };
    const deep: TestDom = .{ .nodes = nodes };
    const piece_kinds = [_][]const u8{ "(", "{", "[", ":is(", ":not(", "@media (", "a{", "@layer x{", ".a{&{", ":has(" };
    for (piece_kinds) |pk| {
        var text: std.ArrayList(u8) = .empty;
        for (0..20000) |_| try text.appendSlice(a, pk);
        try text.appendSlice(a, "i{width:1px}");
        var sh: Stylesheet = .{};
        try parse(a, text.items, &sh);
    }
    {
        var text: std.ArrayList(u8) = .empty;
        for (0..5000) |_| try text.appendSlice(a, "not ");
        var sh: Stylesheet = .{};
        const s = try std.fmt.allocPrint(a, "@supports {s}(a:b){{i{{w:1}}}} @media {s}(width){{i{{w:1}}}}", .{ text.items, text.items });
        try parse(a, s, &sh);
    }
    // exponential-looking descendant chains and :has on a deep tree: bounded by the work budget
    const css_text = ".a .b .a .b .a .b .a .b .a .c{w:1} :has(.a .b .a .c) .b{w:2} .b:nth-last-child(n+1):has(~ .c){w:3} " ++
        ":is(:is(:is(:is(.a .b .a .c)))) i{w:4} i:not(:has(.c)){w:5}";
    var sh: Stylesheet = .{};
    try parse(a, css_text, &sh);
    const m = try prepare(a, &sh, .{});
    var scratch = Scratch.init(a);
    scratch.budget = 20_000;
    var out: std.ArrayList(Declaration) = .empty;
    var i: usize = 0;
    while (i < n_nodes) : (i += 97) {
        out.clearRetainingCapacity();
        _ = try match(&m, &scratch, &deep.dom(), i, .none, &out);
    }
}
