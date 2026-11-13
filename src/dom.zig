//! Uniform element model for the render front-end: a takumi node tree (JSON) and an HTML document
//! both become one flat array of `El`s with parent/sibling links, so selector matching (css `Dom`
//! vtable), Tailwind structural variants (`elementInfo`) and style computation work identically.
//!
//! takumi semantics mirrored here (takumi-core `layout/node/mod.rs`, `html/mod.rs`):
//! - JSON: `{type, tagName?, className?, id?, attributes?, dir?, lang?, tw?, style?, preset?, children?,
//!   text?, src?, width?, height?}`. A `text` node without tagName/className/id/attributes/preset/style/tw
//!   is a bare text RUN (a DOM text node, invisible to selectors); otherwise it is an element holding
//!   text. JSON nodes have NO implicit tag for selectors (`tag` = ""); Tailwind's `*-of-type` variants use
//!   the same selector semantics (tag name; untagged text nodes skipped as siblings).
//! - HTML: document mode builds `html{display:block}` > `body{margin:8px;display:block}` > content;
//!   fragment mode collapses the top-level nodes (0 -> empty container, 1 -> itself, more -> a wrapper
//!   with `display:block;width:100%;height:100%`), trimming white-space-only text roots first. An element
//!   whose children are only (non-blank) text becomes a text element; `<br>` is text "\n"; `<img>` and
//!   `<svg>` are images (svg src = the raw markup); `head/meta/link/style/script` are dropped. UA presets
//!   (`html.presetCss`) are the lowest layer; `<img>/<svg>` sizes in non-px units are presentation hints.
//!
//! Memory: everything lives in the per-render arena passed to the builders; strings alias the input.
const std = @import("std");
const json = @import("json.zig");
const style = @import("style/style.zig");

const Allocator = std.mem.Allocator;
pub const none: u32 = std.math.maxInt(u32);

pub const Kind = enum(u8) { container, text, image };
pub const Dir = enum(u8) { none, ltr, rtl };
pub const Attr = struct { name: []const u8, value: []const u8 };

/// Declaration source of one cascade layer.
pub const Src = union(enum) {
    none,
    /// JSON style object (takumi `style` / `preset`): STRICT layer (invalid value fails the render).
    json: json.Value,
    /// CSS declaration text (HTML `style` attribute, UA preset): LENIENT layer.
    text: []const u8,
};

pub const El = struct {
    kind: Kind,
    /// Bare text run (DOM text node): not an element for selectors / structural variants.
    run: bool = false,
    dir: Dir = .none,
    /// Tag name as written ("" = none).
    tag: []const u8 = "",
    id: []const u8 = "",
    class: []const u8 = "",
    tw: []const u8 = "",
    lang: []const u8 = "",
    /// Remaining attributes (`attributes` map / HTML attributes not consumed elsewhere).
    attrs: []const Attr = &.{},
    preset: Src = .none,
    /// Presentation hints (CSS text, lenient), between preset and author rules.
    pres: []const u8 = "",
    style: Src = .none,
    /// text / text-element content
    text: []const u8 = "",
    /// image source (null = not a string: paints nothing)
    src: ?[]const u8 = null,
    /// image `width` / `height` in CSS px (low-priority size preset)
    width: ?f32 = null,
    height: ?f32 = null,
    parent: u32 = none,
    first: u32 = none,
    last: u32 = none,
    next: u32 = none,
    prev: u32 = none,
    // ---- filled by the style pass (render.zig)
    cs: *const style.ComputedStyle = undefined,
    /// indices into Frame.pseudos (none = no such box)
    before: u32 = none,
    after: u32 = none,
    /// text element with generated content: its own text as an anonymous box between them
    own: u32 = none,
};

pub const Error = error{ OutOfMemory, Invalid };

pub const Dom = struct {
    els: std.ArrayList(El) = .empty,
    root: u32 = none,
    /// HTML `<style>` texts in document order (appended after the `css` option).
    styles: []const []const u8 = &.{},
    /// Render option `lang`: the root's language for `:lang()` when it has none.
    lang: []const u8 = "",
    /// Set by a builder on error.Invalid.
    err_msg: []const u8 = "",
    err_detail: []const u8 = "",
    /// Maximum number of nesting levels accepted by the builders (the root is level 1).
    max_depth: u32 = 128,

    fn fail(d: *Dom, msg: []const u8, detail: []const u8) Error {
        d.err_msg = msg;
        d.err_detail = detail;
        return error.Invalid;
    }

    pub fn at(d: *const Dom, i: u32) *El {
        return &d.els.items[i];
    }

    /// Appends `el` as the last child of `parent` (none = a root).
    pub fn add(d: *Dom, a: Allocator, el: El, parent: u32) Error!u32 {
        try d.els.append(a, el);
        const id: u32 = @intCast(d.els.items.len - 1);
        const e = &d.els.items[id];
        e.parent = parent;
        if (parent != none) {
            const p = &d.els.items[parent];
            if (p.last == none) p.first = id else {
                d.els.items[p.last].next = id;
                e.prev = p.last;
            }
            p.last = id;
        }
        return id;
    }

    // ------------------------------------------------------------------------------- JSON source

    /// Builds the element array from a takumi JSON node tree.
    pub fn fromJson(d: *Dom, a: Allocator, v: json.Value) Error!void {
        d.root = try d.jsonNode(a, v, none, 0);
    }

    fn jsonNode(d: *Dom, a: Allocator, v: json.Value, parent: u32, depth: u32) Error!u32 {
        if (depth >= d.max_depth) return d.fail("node tree is nested too deeply", "");
        const id = try d.jsonElement(a, v, parent);
        if (d.els.items[id].kind == .container) {
            if (v.get("children")) |c| if (c == .array) {
                for (c.array) |cv| {
                    if (cv == .null) continue;
                    _ = try d.jsonNode(a, cv, id, depth + 1);
                }
            };
        }
        return id;
    }

    /// One JSON node as an element (children excluded). Out of line: the `El` under construction
    /// would otherwise sit in every level of the recursion's stack frame.
    noinline fn jsonElement(d: *Dom, a: Allocator, v: json.Value, parent: u32) Error!u32 {
        if (v != .object) return d.fail("node must be an object", "");
        const tv = v.get("type") orelse return d.fail("node is missing `type`", "");
        const t = tv.asString() orelse return d.fail("node `type` must be a string", "");
        var el: El = .{ .kind = undefined };
        if (std.mem.eql(u8, t, "container")) el.kind = .container else if (std.mem.eql(u8, t, "text")) el.kind = .text else if (std.mem.eql(u8, t, "image")) el.kind = .image else return d.fail("unknown node type: ", t);

        var meta = false;
        for (v.object) |m| {
            const k = m.key;
            if (m.value == .null) continue;
            if (std.mem.eql(u8, k, "style")) {
                el.style = .{ .json = m.value };
                meta = true;
            } else if (std.mem.eql(u8, k, "preset")) {
                el.preset = .{ .json = m.value };
                meta = true;
            } else if (std.mem.eql(u8, k, "tagName")) {
                el.tag = m.value.asString() orelse "";
                meta = true;
            } else if (std.mem.eql(u8, k, "className")) {
                el.class = m.value.asString() orelse "";
                meta = true;
            } else if (std.mem.eql(u8, k, "id")) {
                el.id = m.value.asString() orelse "";
                meta = true;
            } else if (std.mem.eql(u8, k, "tw")) {
                el.tw = m.value.asString() orelse "";
                meta = true;
            } else if (std.mem.eql(u8, k, "attributes")) {
                meta = true;
                if (m.value == .object) {
                    const list = try a.alloc(Attr, m.value.object.len);
                    var n: usize = 0;
                    for (m.value.object) |am| {
                        const s = am.value.asString() orelse continue;
                        list[n] = .{ .name = am.key, .value = s };
                        n += 1;
                    }
                    el.attrs = list[0..n];
                }
            } else if (std.mem.eql(u8, k, "lang")) {
                el.lang = m.value.asString() orelse "";
            } else if (std.mem.eql(u8, k, "dir")) {
                el.dir = parseDir(m.value.asString() orelse "");
            }
        }
        switch (el.kind) {
            .text => {
                const tx = v.get("text") orelse return d.fail("text node is missing `text`", "");
                el.text = tx.asString() orelse return d.fail("`text` must be a string", "");
                el.run = !meta;
            },
            .image => {
                const s = v.get("src") orelse return d.fail("image node is missing `src`", "");
                el.src = s.asString();
                if (v.get("width")) |x| el.width = x.asNumber();
                if (v.get("height")) |x| el.height = x.asNumber();
            },
            .container => {},
        }
        return d.add(a, el, parent);
    }

    // ------------------------------------------------------------------------------- HTML source

    /// Builds the element array from a parsed HTML document (`html.parse`). `H` is the html module
    /// (passed as a type so this file does not import it when HTML support is compiled out).
    pub fn fromHtml(d: *Dom, a: Allocator, comptime H: type, doc: *const H.Document) Error!void {
        d.styles = doc.styles;
        if (doc.is_document) {
            const html_el = try d.add(a, .{ .kind = .container, .tag = "html", .preset = .{ .text = H.presetCss("html") } }, none);
            try d.htmlMeta(a, H, html_el, doc.html_attrs, "html");
            const body = try d.add(a, .{ .kind = .container, .tag = "body", .preset = .{ .text = H.presetCss("body") } }, html_el);
            try d.htmlMeta(a, H, body, doc.body_attrs, "body");
            for (doc.root_children) |c| try d.htmlNode(a, H, c, body, 2, false);
            d.root = html_el;
            return;
        }
        // takumi `collapse`: the nodes that will exist (unrendered elements such as <style> and empty
        // texts vanish first), then white-space-only texts trimmed at both ends
        var kids = doc.root_children;
        while (kids.len > 0 and (blankText(H, kids[0]) or vanishes(H, kids[0]))) kids = kids[1..];
        while (kids.len > 0 and (blankText(H, kids[kids.len - 1]) or vanishes(H, kids[kids.len - 1]))) kids = kids[0 .. kids.len - 1];
        var n: usize = 0;
        var only: ?*const H.Node = null;
        for (kids) |c| {
            if (vanishes(H, c)) continue;
            n += 1;
            only = c;
        }
        if (n == 1) {
            const before = d.els.items.len;
            try d.htmlNode(a, H, only.?, none, 0, false);
            d.root = @intCast(before);
            return;
        }
        const style_text: []const u8 = if (n == 0) "" else "display:block;width:100%;height:100%";
        d.root = try d.add(a, .{ .kind = .container, .style = if (n == 0) .none else .{ .text = style_text } }, none);
        for (kids) |c| try d.htmlNode(a, H, c, d.root, 1, false);
    }

    fn vanishes(comptime H: type, n: *const H.Node) bool {
        return (n.kind == .element and H.isUnrendered(n.tag)) or (n.kind == .text and n.text.len == 0);
    }

    fn blankText(comptime H: type, n: *const H.Node) bool {
        if (n.kind != .text) return false;
        for (n.text) |c| if (c != ' ' and c != '\t' and c != '\n' and c != '\r' and c != 0x0c) return false;
        return true;
    }

    fn htmlNode(d: *Dom, a: Allocator, comptime H: type, n: *const H.Node, parent: u32, depth: u32, disabled_fs: bool) Error!void {
        if (depth >= d.max_depth) return d.fail("node tree is nested too deeply", "");
        if (n.kind == .text) {
            if (n.text.len == 0) return;
            _ = try d.add(a, .{ .kind = .text, .run = true, .text = n.text }, parent);
            return;
        }
        const id = (try d.htmlElement(a, H, n, parent, disabled_fs)) orelse return;
        const tag = n.tag;
        const disables = std.mem.eql(u8, tag, "fieldset") and n.attr("disabled") != null;
        var seen_legend = false;
        for (n.children) |c| {
            var dis = disabled_fs or disables;
            if (disables and !seen_legend and c.kind == .element and std.mem.eql(u8, c.tag, "legend")) {
                seen_legend = true;
                dis = disabled_fs; // the first legend of a disabled fieldset is exempt
            }
            try d.htmlNode(a, H, c, id, depth + 1, dis);
        }
    }

    /// One HTML element (children excluded); returns its id when its children must be built, null
    /// when it is unrendered or not a container. Out of line: keeps the `El` under construction out
    /// of the recursion's stack frame.
    noinline fn htmlElement(d: *Dom, a: Allocator, comptime H: type, n: *const H.Node, parent: u32, disabled_fs: bool) Error!?u32 {
        const tag = n.tag;
        if (H.isUnrendered(tag)) return null;
        var el: El = .{ .kind = .container, .tag = tag };
        var pres: std.ArrayList(u8) = .empty;
        if (std.mem.eql(u8, tag, "br")) {
            el.kind = .text;
            el.text = "\n";
        } else if (std.mem.eql(u8, tag, "img") or std.mem.eql(u8, tag, "svg")) {
            el.kind = .image;
            const svg = tag[0] == 's';
            if (svg) {
                el.src = n.text;
            } else {
                const s = std.mem.trim(u8, n.attr("src") orelse "", " \t\n\r\x0c");
                el.src = s; // "" -> resolves to nothing: a replaced element with no pixels
            }
            inline for (.{ "width", "height" }) |name| {
                if (n.attr(name)) |raw| {
                    const dv = dimension(raw, svg);
                    switch (dv) {
                        .none => {},
                        .px => |px| if (name[0] == 'w') {
                            el.width = px;
                        } else {
                            el.height = px;
                        },
                        .css => |txt| {
                            try pres.appendSlice(a, name ++ ":");
                            try pres.appendSlice(a, txt);
                            try pres.append(a, ';');
                        },
                    }
                }
            }
        } else if (n.soleText()) |t| {
            el.kind = .text;
            el.text = t;
        }
        // UA preset
        const is_form = std.mem.eql(u8, tag, "input") or std.mem.eql(u8, tag, "textarea");
        if (is_form) {
            var rows: [3][]const u8 = undefined;
            const k = H.formControlPresets(n, disabled_fs, &rows);
            if (k == 1) el.preset = .{ .text = rows[0] } else if (k > 1) {
                var buf: std.ArrayList(u8) = .empty;
                for (rows[0..k]) |r| {
                    try buf.appendSlice(a, r);
                    try buf.append(a, ';');
                }
                el.preset = .{ .text = buf.items };
            }
        } else {
            const p = H.presetCss(tag);
            if (p.len > 0) el.preset = .{ .text = p };
        }
        el.pres = pres.items;
        const id = try d.add(a, el, parent);
        try d.htmlMeta(a, H, id, n.attrs, tag);
        if (el.kind != .container) return null;
        return id;
    }

    /// takumi `apply_metadata`: class/id/lang/dir/style/tw are structured fields, the rest attributes.
    fn htmlMeta(d: *Dom, a: Allocator, comptime H: type, id: u32, attrs: []const H.Attr, tag: []const u8) Error!void {
        if (attrs.len == 0) return;
        const el = &d.els.items[id];
        const out = try a.alloc(Attr, attrs.len);
        var n: usize = 0;
        const replaced = std.mem.eql(u8, tag, "img") or std.mem.eql(u8, tag, "svg");
        for (attrs) |atr| {
            const k = atr.name;
            if (std.mem.eql(u8, k, "tw")) {
                el.tw = atr.value;
            } else if (std.mem.eql(u8, k, "class")) {
                el.class = atr.value;
            } else if (std.mem.eql(u8, k, "id")) {
                el.id = atr.value;
            } else if (std.mem.eql(u8, k, "lang")) {
                el.lang = atr.value;
            } else if (std.mem.eql(u8, k, "dir")) {
                el.dir = parseDir(atr.value);
            } else if (std.mem.eql(u8, k, "style")) {
                el.style = .{ .text = atr.value };
            } else if (std.mem.eql(u8, k, "src") and std.mem.eql(u8, tag, "img")) {
                // consumed
            } else if (replaced and (std.mem.eql(u8, k, "width") or std.mem.eql(u8, k, "height"))) {
                // consumed
            } else {
                out[n] = .{ .name = k, .value = atr.value };
                n += 1;
            }
        }
        el.attrs = out[0..n];
    }

    // ------------------------------------------------------------------------------- queries

    /// Attribute lookup as takumi's `Node::attribute` (id / class / lang are structured fields).
    /// `name` is compared ASCII case-insensitively.
    pub fn attr(d: *const Dom, i: u32, name: []const u8) ?[]const u8 {
        const el = &d.els.items[i];
        if (std.ascii.eqlIgnoreCase(name, "id")) return if (el.id.len > 0) el.id else null;
        if (std.ascii.eqlIgnoreCase(name, "class")) return if (el.class.len > 0) el.class else null;
        if (std.ascii.eqlIgnoreCase(name, "lang")) {
            if (el.lang.len > 0) return el.lang;
            if (i == d.root and d.lang.len > 0) return d.lang;
            return null;
        }
        for (el.attrs) |atr| if (std.ascii.eqlIgnoreCase(atr.name, name)) return atr.value;
        return null;
    }

    /// takumi matching (`matching.rs` text_of): a `text` node WITHOUT a tag name is not an element for
    /// sibling / child traversal, even when it has a className (EMPIRICAL, probe/frontend/nth.mjs). It is
    /// still matched itself (and is then its own first/last child).
    pub fn selHidden(el: *const El) bool {
        return el.kind == .text and el.tag.len == 0;
    }

    /// Next / previous ELEMENT sibling (untagged text nodes skipped).
    pub fn nextEl(d: *const Dom, i: u32) ?u32 {
        var c = d.els.items[i].next;
        while (c != none) : (c = d.els.items[c].next) if (!selHidden(&d.els.items[c])) return c;
        return null;
    }

    pub fn prevEl(d: *const Dom, i: u32) ?u32 {
        var c = d.els.items[i].prev;
        while (c != none) : (c = d.els.items[c].prev) if (!selHidden(&d.els.items[c])) return c;
        return null;
    }

    pub fn firstEl(d: *const Dom, i: u32) ?u32 {
        var c = d.els.items[i].first;
        while (c != none) : (c = d.els.items[c].next) if (!selHidden(&d.els.items[c])) return c;
        return null;
    }

    /// Blink `:empty`: no element child and no non-empty text.
    pub fn isEmpty(d: *const Dom, i: u32) bool {
        const el = &d.els.items[i];
        if (el.kind == .text and el.text.len > 0) return false;
        var c = el.first;
        while (c != none) : (c = d.els.items[c].next) {
            const ch = &d.els.items[c];
            if (!selHidden(ch) or ch.text.len > 0) return false;
        }
        return true;
    }

    /// Structural position for Tailwind variants (`first:`, `odd:`, `nth-3:`, `*-of-type`, `empty:`),
    /// with takumi's selector semantics: untagged text siblings are skipped (`selHidden`) and the
    /// "type" is the tag name, all untagged nodes sharing one type (EMPIRICAL, probe/frontend/twstruct.mjs).
    pub fn elementInfo(d: *const Dom, i: u32) Info {
        const el = &d.els.items[i];
        var info: Info = .{ .empty = d.isEmpty(i) };
        if (el.parent == none) return info;
        var count: u32 = 0;
        var tcount: u32 = 0;
        var c = d.els.items[el.parent].first;
        while (c != none) : (c = d.els.items[c].next) {
            const ch = &d.els.items[c];
            if (c != i and selHidden(ch)) continue;
            if (c == i) {
                info.index = count;
                info.type_index = tcount;
            }
            count += 1;
            if (std.ascii.eqlIgnoreCase(ch.tag, el.tag)) tcount += 1;
        }
        info.count = count;
        info.type_count = tcount;
        return info;
    }

    pub const Info = struct { index: u32 = 0, count: u32 = 1, type_index: u32 = 0, type_count: u32 = 1, empty: bool = false };
};

pub fn parseDir(s: []const u8) Dir {
    if (std.ascii.eqlIgnoreCase(s, "rtl")) return .rtl;
    if (std.ascii.eqlIgnoreCase(s, "ltr")) return .ltr;
    return .none;
}

const DimValue = union(enum) { none, px: f32, css: []const u8 };

/// `width` / `height` attribute of `<img>` (HTML dimension rules: number of px or a percentage) or
/// `<svg>` (a CSS length; a bare number is px). Non-px values become presentation CSS text.
fn dimension(raw: []const u8, svg: bool) DimValue {
    const v = std.mem.trim(u8, raw, " \t\n\r\x0c");
    if (v.len == 0) return .none;
    if (svg) {
        const r = json.parseNumber(v) orelse return .none;
        const unit = v[r.len..];
        if (unit.len == 0 or std.ascii.eqlIgnoreCase(unit, "px")) return .{ .px = @floatCast(r.value) };
        return .{ .css = v };
    }
    if (v[0] < '0' or v[0] > '9') return .none;
    var e: usize = 0;
    while (e < v.len and v[e] >= '0' and v[e] <= '9') e += 1;
    if (e + 1 < v.len and v[e] == '.' and v[e + 1] >= '0' and v[e + 1] <= '9') {
        e += 1;
        while (e < v.len and v[e] >= '0' and v[e] <= '9') e += 1;
    }
    const r = json.parseNumber(v[0..e]) orelse return .none;
    if (e < v.len and v[e] == '%') return .{ .css = v[0 .. e + 1] };
    return .{ .px = @floatCast(r.value) };
}

// ------------------------------------------------------------------------------------------------
// Generated content

/// The CSS counters `counter()` / `counters()` read (src/pdf/css_counters.zig, PDF frames): `write`
/// appends the text of `counter(args)` (`all` false) or `counters(args)` to `out`.
pub const ContentCounters = struct {
    ctx: *anyopaque,
    write: *const fn (ctx: *anyopaque, a: Allocator, out: *std.ArrayList(u8), args: []const u8, all: bool) Allocator.Error!void,
};

/// Text of a `content` value for a `::before`/`::after` box; null = no box (`none`, `normal`, or a
/// value without any usable item). Strings (with CSS escapes) and `attr(name)` are supported;
/// counters (without `counters`), quotes and images contribute nothing. Alternative text after `/` is
/// ignored. With `counters` (PDF frames, as takumi's `ContentItem`): `counter()` / `counters()` write their
/// values, and a function other than `attr`, `counter`, `counters` or an image makes the value invalid
/// (null: no box).
pub fn contentText(a: Allocator, value: []const u8, d: *const Dom, el: u32, counters: ?ContentCounters) Error!?[]const u8 {
    const v = std.mem.trim(u8, value, " \t\n\r\x0c");
    if (v.len == 0 or std.ascii.eqlIgnoreCase(v, "none") or std.ascii.eqlIgnoreCase(v, "normal")) return null;
    var out: std.ArrayList(u8) = .empty;
    var items: u32 = 0;
    var i: usize = 0;
    while (i < v.len) {
        const c = v[i];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0c) {
            i += 1;
            continue;
        }
        if (c == '/') break;
        if (c == '"' or c == '\'') {
            i += 1;
            while (i < v.len and v[i] != c) {
                if (v[i] == '\\' and i + 1 < v.len) {
                    i += 1;
                    if (isHex(v[i])) {
                        var cp: u32 = 0;
                        var k: usize = 0;
                        while (k < 6 and i < v.len and isHex(v[i])) : (k += 1) {
                            cp = cp * 16 + hexVal(v[i]);
                            i += 1;
                        }
                        if (i < v.len and (v[i] == ' ' or v[i] == '\t' or v[i] == '\n')) i += 1;
                        if (cp == 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) cp = 0xFFFD;
                        var buf: [4]u8 = undefined;
                        const len = json.encodeUtf8(cp, &buf);
                        try out.appendSlice(a, buf[0..len]);
                        continue;
                    }
                    if (v[i] == '\n') {
                        i += 1;
                        continue;
                    }
                }
                try out.append(a, v[i]);
                i += 1;
            }
            i += 1; // closing quote
            items += 1;
            continue;
        }
        // identifier or function
        const s = i;
        while (i < v.len and v[i] != '(' and v[i] != ' ' and v[i] != '"' and v[i] != '\'' and v[i] != '/') i += 1;
        const name = v[s..i];
        if (i < v.len and v[i] == '(') {
            const arg_s = i + 1;
            var depth: u32 = 1;
            i += 1;
            while (i < v.len and depth > 0) : (i += 1) {
                if (v[i] == '(') depth += 1 else if (v[i] == ')') depth -= 1;
            }
            const arg_e = if (depth == 0) i - 1 else v.len;
            const arg = std.mem.trim(u8, v[arg_s..arg_e], " \t\n");
            if (std.ascii.eqlIgnoreCase(name, "attr")) {
                var an = arg;
                if (std.mem.indexOfAny(u8, an, " ,")) |k| an = an[0..k];
                if (d.attr(el, an)) |val| try out.appendSlice(a, val);
                items += 1;
            } else if (std.ascii.eqlIgnoreCase(name, "counter") or std.ascii.eqlIgnoreCase(name, "counters")) {
                items += 1; // (without `counters`: contribute nothing)
                if (counters) |cc| try cc.write(cc.ctx, a, &out, arg, name.len == 8);
            } else if (counters != null and !isImageFunction(name)) {
                return null;
            }
            continue;
        }
        if (std.ascii.eqlIgnoreCase(name, "open-quote") or std.ascii.eqlIgnoreCase(name, "close-quote") or
            std.ascii.eqlIgnoreCase(name, "no-open-quote") or std.ascii.eqlIgnoreCase(name, "no-close-quote")) items += 1;
        if (i == s) i += 1;
    }
    if (items == 0) return null;
    return out.items;
}

/// The CSS functions that are an `<image>` (a `content` item takumi accepts and draws nothing for here).
fn isImageFunction(name: []const u8) bool {
    const names = [_][]const u8{ "url", "image", "image-set", "-webkit-image-set", "cross-fade", "element", "linear-gradient", "radial-gradient", "conic-gradient", "repeating-linear-gradient", "repeating-radial-gradient", "repeating-conic-gradient", "-webkit-linear-gradient", "-webkit-radial-gradient" };
    for (names) |n| if (std.ascii.eqlIgnoreCase(name, n)) return true;
    return false;
}

fn isHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn hexVal(c: u8) u32 {
    return if (c <= '9') c - '0' else (c | 0x20) - 'a' + 10;
}

// ------------------------------------------------------------------------------------------------
// tests

const T = std.testing;

test "json -> elements: runs, metadata, links" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = try json.parse(a,
        \\{"type":"container","className":"card","children":[
        \\ {"type":"text","text":"bare"},
        \\ {"type":"text","text":"elem","id":"t"},
        \\ null,
        \\ {"type":"image","src":"x","width":10,"attributes":{"alt":"A","n":3}},
        \\ {"type":"container","tagName":"section","dir":"RTL","lang":"vi"}]}
    );
    var d: Dom = .{};
    try d.fromJson(a, v);
    try T.expectEqual(@as(usize, 5), d.els.items.len);
    try T.expect(d.at(1).run);
    try T.expect(!d.at(2).run);
    // untagged text nodes (bare or with metadata) are not elements for traversal
    try T.expectEqual(@as(?u32, 3), d.firstEl(0));
    try T.expectEqual(@as(?u32, 3), d.nextEl(2));
    try T.expectEqual(@as(?u32, null), d.prevEl(3));
    try T.expectEqualStrings("A", d.attr(3, "ALT").?);
    try T.expectEqual(@as(?f32, 10), d.at(3).width);
    try T.expectEqual(Dir.rtl, d.at(4).dir);
    try T.expectEqualStrings("section", d.at(4).tag);
    try T.expect(d.isEmpty(4));
    try T.expect(!d.isEmpty(0));
    const info = d.elementInfo(3);
    try T.expectEqual(@as(u32, 0), info.index);
    try T.expectEqual(@as(u32, 2), info.count);
    try T.expectEqual(@as(u32, 0), info.type_index);
    try T.expectEqual(@as(u32, 1), info.type_count); // "" vs "section"
    try T.expectEqual(@as(u32, 0), d.elementInfo(2).index); // self counts, untagged text siblings do not
    try T.expectEqual(@as(u32, 3), d.elementInfo(2).count);
}

test "json errors" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "{\"type\":\"blob\"}", "{\"text\":\"x\"}", "{\"type\":\"text\"}", "{\"type\":\"image\"}", "[1]" }) |src| {
        var d: Dom = .{};
        try T.expectError(error.Invalid, d.fromJson(a, try json.parse(a, src)));
        try T.expect(d.err_msg.len > 0);
    }
}

test "content text" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: Dom = .{};
    _ = try d.add(a, .{ .kind = .container, .attrs = &.{.{ .name = "data-x", .value = "42" }} }, none);
    try T.expect((try contentText(a, "none", &d, 0, null)) == null);
    try T.expect((try contentText(a, "normal", &d, 0, null)) == null);
    try T.expectEqualStrings("", (try contentText(a, "\"\"", &d, 0, null)).?);
    try T.expectEqualStrings("a\"b", (try contentText(a, "'a\"b'", &d, 0, null)).?);
    try T.expectEqualStrings("\u{2192} 42!", (try contentText(a, "\"\\2192  \" attr(data-x) '!' / \"alt\"", &d, 0, null)).?);
    try T.expectEqualStrings("", (try contentText(a, "counter(x)", &d, 0, null)).?);
}
