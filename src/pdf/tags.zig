//! Tagged PDF (takumi-pdf `tags.rs`, the tagging calls of `emitter.rs` / `interactive.rs`, and
//! krilla's `interchange/tagging` serialisation with the parent tree of `serialize.rs`):
//!
//! * the emitter records every marked-content id it opens (`Collector.record`) against the render
//!   node whose content it marks: text against the box laying out the paragraph (an anonymous
//!   paragraph leaf that is its block's only child counts as the block, as takumi's block owns its
//!   inline layout), images against the image node; link annotations are recorded when written;
//! * `build` walks the document frame in source order and turns the HTML semantics into structure
//!   elements exactly as takumi does (`role`: headings re-levelled by nesting depth, `p`, `figure`,
//!   `img` with alt, `a href`, `blockquote`, `section`, `article`, `ul`/`ol`, `li` with Lbl/LBody,
//!   `strong`/`b`, `em`/`i`, `code`, `figcaption`; tables with captions, THead/TBody/TFoot, TR,
//!   TH (scope) / TD with spans), runs of bare content becoming `P`s, link annotations joining
//!   `Link` elements; elements a destination names get an `/ID` (`Un.<path>`);
//! * `write` serialises the tree (children before their parent, as krilla), the struct tree root
//!   (RoleMap below PDF 2.0, namespaces in 2.0), the parent tree (per page: annotations first, then
//!   the page's marked-content ids), the ID tree.
const std = @import("std");
const render = @import("../render.zig");
const style = @import("../style/style.zig");
const w = @import("writer.zig");
const markers = @import("markers.zig");
const dom_mod = @import("../dom.zig");

const Allocator = std.mem.Allocator;
const Frame = render.Frame;
const Node = render.Node;
const none = render.none;
const Error = render.Error;
const Ref = w.Ref;

/// A leaf of the structure tree: a marked-content sequence on a page, or an annotation.
pub const Ident = union(enum) {
    mcid: struct { page: u32, mcid: i32 },
    /// index into `Tagging.annots`
    annot: u32,
};

const RecKind = enum { content, label, annotation };

const Record = struct { node: u32, kind: RecKind, id: Ident, taken: bool = false };

/// The marked-content ids recorded during emission, by source node (takumi `TagCollector`).
pub const Collector = struct {
    a: Allocator,
    f: *const Frame,
    records: std.ArrayList(Record) = .empty,
    failed: bool = false,

    pub fn init(a: Allocator, f: *const Frame) Collector {
        return .{ .a = a, .f = f };
    }

    /// The node a content sequence of `id` is recorded against: an anonymous paragraph leaf (or
    /// line container) that is its block's only child stands for the block.
    pub fn owner(c: *const Collector, id: u32) u32 {
        return if (standsForParent(c.f, id)) c.f.nodes.items[id].parent else id;
    }

    pub fn record(c: *Collector, node: u32, kind: RecKind, id: Ident) void {
        // a list marker's content is its list item's label (takumi `start_node_region`:
        // `record_label` against `marker_tag_target`)
        if (kind == .content) if (markers.labelOwner(c.f, node)) |item| {
            c.records.append(c.a, .{ .node = item, .kind = .label, .id = id }) catch {
                c.failed = true;
            };
            return;
        };
        c.records.append(c.a, .{ .node = node, .kind = kind, .id = id }) catch {
            c.failed = true;
        };
    }

    const Recorded = struct { ids: std.ArrayList(Ident) = .empty, labels: std.ArrayList(Ident) = .empty, annots: std.ArrayList(Ident) = .empty };

    /// What `node` recorded that the tree has not taken yet (records sorted by node).
    fn take(c: *Collector, node: u32) Error!Recorded {
        var out: Recorded = .{};
        var lo: usize = 0;
        var hi: usize = c.records.items.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (c.records.items[mid].node < node) lo = mid + 1 else hi = mid;
        }
        var i = lo;
        while (i < c.records.items.len and c.records.items[i].node == node) : (i += 1) {
            const r = &c.records.items[i];
            if (r.taken) continue;
            r.taken = true;
            switch (r.kind) {
                .content => try out.ids.append(c.a, r.id),
                .label => try out.labels.append(c.a, r.id),
                .annotation => try out.annots.append(c.a, r.id),
            }
        }
        return out;
    }
};

// ---------------------------------------------------------------------------------------------
// The tree
// ---------------------------------------------------------------------------------------------

pub const Role = enum { document, p, h, link, figure, block_quote, sect, art, l, li, lbl, lbody, strong, em, code, caption, table, tr, th, td, thead, tbody, tfoot };

pub const Numbering = enum { none, disc, circle, square, decimal, lower_roman, upper_roman, lower_alpha, upper_alpha };
pub const Scope = enum { row, column };

pub const Group = struct {
    role: Role,
    level: u16 = 0,
    title: ?[]const u8 = null,
    alt: ?[]const u8 = null,
    numbering: ?Numbering = null,
    scope: ?Scope = null,
    row_span: u32 = 0,
    col_span: u32 = 0,
    id: ?[]const u8 = null,
    /// the render node a destination names it by (with `id`)
    node: u32 = none,
    kids: std.ArrayList(Kid) = .empty,
};

pub const Kid = union(enum) { group: *Group, leaf: Ident };

const Nesting = struct { in_row: bool = false, in_list: bool = false, in_figure: bool = false };

const Walk = struct {
    c: *Collector,
    a: Allocator,
    f: *const Frame,
    headings: std.ArrayList(u8) = .empty,
    /// render nodes a destination names (anchors with an `id`, headings)
    targets: *const std.AutoHashMapUnmanaged(u32, void),

    fn newGroup(wk: *Walk, role: Role) Error!*Group {
        const g = try wk.a.create(Group);
        g.* = .{ .role = role };
        return g;
    }

    /// takumi `name_target`: the `Un.<path>` id when a destination names `node`.
    fn nameTarget(wk: *Walk, node: u32, g: *Group) Error!bool {
        if (!wk.targets.contains(node)) return false;
        g.id = try tagId(wk.a, wk.f, node);
        g.node = node;
        return true;
    }

    /// Heading levels by nesting depth (takumi `heading_level`).
    fn headingLevel(wk: *Walk, source: u8) Error!u16 {
        while (wk.headings.items.len > 0 and wk.headings.items[wk.headings.items.len - 1] >= source) wk.headings.items.len -= 1;
        try wk.headings.append(wk.a, source);
        return @intCast(@max(1, @min(wk.headings.items.len, 6)));
    }
};

fn tagOf(f: *const Frame, n: *const Node) []const u8 {
    if (n.el == none or n.kind == .anon_text or n.kind == .anon_box) return "";
    return f.dom.at(n.el).tag;
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn attrOf(f: *const Frame, n: *const Node, name: []const u8) ?[]const u8 {
    if (n.el == none or n.kind == .anon_text or n.kind == .anon_box) return null;
    if (eq(name, "alt")) {
        // an image's `alt` is kept on the element (HTML) or in its attributes (JSON)
        if (f.dom.attr(n.el, "alt")) |v| return v;
        return null;
    }
    return f.dom.attr(n.el, name);
}

fn flushParagraph(wk: *Walk, pending: *std.ArrayList(Ident), parent: *std.ArrayList(Kid)) Error!void {
    if (pending.items.len == 0) return;
    const g = try wk.newGroup(.p);
    for (pending.items) |id| try g.kids.append(wk.a, .{ .leaf = id });
    pending.clearRetainingCapacity();
    try parent.append(wk.a, .{ .group = g });
}

fn pushLinkWrappers(wk: *Walk, annots: []const Ident, parent: *std.ArrayList(Kid)) Error!void {
    for (annots) |an| {
        const g = try wk.newGroup(.link);
        try g.kids.append(wk.a, .{ .leaf = an });
        try parent.append(wk.a, .{ .group = g });
    }
}

fn isTable(d: style.computed.Display) bool {
    return d == .table or d == .inline_table;
}

/// Whether the node is a block-level box (a paragraph boundary). Flex / grid items, floats and
/// out-of-flow boxes are blockified, as takumi's computed display is.
fn isBlock(f: *const Frame, n: *const Node) bool {
    if (n.kind == .anon_text or n.kind == .anon_box) return true;
    if (n.cs.float != .none or n.cs.position == .absolute or n.cs.position == .fixed) return true;
    if (n.parent != none) switch (f.nodes.items[n.parent].cs.display) {
        .flex, .inline_flex, .grid, .inline_grid, .webkit_box, .webkit_inline_box => return true,
        else => {},
    };
    return switch (n.cs.display) {
        .@"inline", .inline_block, .inline_flex, .inline_grid => false,
        else => true,
    };
}

fn isRowFlex(n: *const Node) bool {
    if (n.kind == .anon_text) return false;
    const d = n.cs.display;
    if (d != .flex and d != .inline_flex) return false;
    return n.cs.flex_direction == .row or n.cs.flex_direction == .row_reverse;
}

/// A render node takumi's tree does not hold: `display: none` generates no box.
fn gone(f: *const Frame, id: u32) bool {
    const n = &f.nodes.items[id];
    return n.kind != .anon_text and n.kind != .anon_box and n.cs.display == .none;
}

fn firstLive(f: *const Frame, n: *const Node) u32 {
    var c = n.first_child;
    while (c != none and gone(f, c)) c = f.nodes.items[c].next;
    return c;
}

fn nextLive(f: *const Frame, id: u32) u32 {
    var c = f.nodes.items[id].next;
    while (c != none and gone(f, c)) c = f.nodes.items[c].next;
    return c;
}

/// The children the walk visits (no `display: none` box): an anonymous only child stands for
/// its block, so its children are the block's.
fn liveKids(wk: *Walk, id: u32) Error![]const u32 {
    const f = wk.f;
    var out: std.ArrayList(u32) = .empty;
    var c = firstLive(f, &f.nodes.items[id]);
    if (c != none and standsForParent(f, c)) c = firstLive(f, &f.nodes.items[c]);
    while (c != none) : (c = nextLive(f, c)) try out.append(wk.a, c);
    return out.items;
}

/// An anonymous paragraph leaf / line container that is the only child of a block container is
/// that block's own inline layout in takumi's tree (in a flex / grid container it is an
/// anonymous item of its own).
pub fn standsForParent(f: *const Frame, id: u32) bool {
    const n = &f.nodes.items[id];
    if (!(n.kind == .anon_text or n.kind == .anon_box) or n.parent == none) return false;
    const p = &f.nodes.items[n.parent];
    if (firstLive(f, p) != id or nextLive(f, id) != none) return false;
    return switch (p.cs.display) {
        .flex, .inline_flex, .grid, .inline_grid, .webkit_box, .webkit_inline_box => false,
        // a table, row group or row lays out no lines: its text sits in an anonymous cell
        .table, .inline_table, .table_row_group, .table_header_group, .table_footer_group, .table_row => p.kind == .anon_text,
        else => true,
    };
}

const ChildClass = enum { inline_flow, out_of_flow, block };

/// How a child takes part in its parent's layout (takumi `participates_in_*inline_formatting_context`).
fn childClass(e: *const dom_mod.El) ChildClass {
    if (e.run) return .inline_flow;
    const cs = e.cs;
    if (cs.position == .absolute or cs.position == .fixed or cs.float != .none) return .out_of_flow;
    return switch (cs.display) {
        .@"inline", .inline_block, .inline_flex, .inline_grid, .inline_table, .webkit_inline_box => .inline_flow,
        else => .block,
    };
}

fn collapsibleSpace(e: *const dom_mod.El) bool {
    if (!(e.run or (e.kind == .text and e.tag.len == 0))) return false;
    if (e.cs.white_space_collapse != .collapse) return false;
    return std.mem.trim(u8, e.text, &std.ascii.whitespace).len == 0;
}

/// The children of DOM element `parent` as takumi's render tree holds them
/// (`RenderNode::normalize_children`): no `display: none` box, no collapsible white space
/// that follows no inline content (`drop_collapsible_boundary_whitespace`), a paged
/// document's repeating fixed boxes taken out; next to block-level siblings every run of inline
/// content is one anonymous block. `visit` gets each kept child with its place: the index among
/// the parent's children and, inside an anonymous block, the index in it.
const ChildPlaces = struct {
    f: *const Frame,
    parent: u32,
    mixed: bool = false,
    items_parent: bool = false,
    parent_inline: bool = false,

    fn init(f: *const Frame, parent: u32) ChildPlaces {
        var cp: ChildPlaces = .{ .f = f, .parent = parent };
        const pe = f.dom.at(parent);
        const pd = pe.cs.display;
        cp.parent_inline = pd == .@"inline";
        cp.items_parent = switch (pd) {
            .flex, .inline_flex, .grid, .inline_grid, .webkit_box, .webkit_inline_box => true,
            // (table parts: the fix-up keeps the children in order; white space goes)
            .table, .inline_table, .table_row_group, .table_header_group, .table_footer_group, .table_row => true,
            else => false,
        };
        if (!cp.items_parent) {
            var has_inline = false;
            var has_block = false;
            var it = cp.iter();
            while (it.next()) |c| switch (childClass(f.dom.at(c))) {
                .inline_flow => has_inline = true,
                .block => has_block = true,
                .out_of_flow => {},
            };
            cp.mixed = has_inline and has_block and !cp.parent_inline;
        }
        return cp;
    }

    const Iter = struct {
        cp: *const ChildPlaces,
        cur: u32,
        after_inline: bool,
        guard: u32 = 0,

        fn next(it: *Iter) ?u32 {
            const f = it.cp.f;
            const paged = f.paginated() != null;
            while (it.cur != none and it.guard < 1 << 22) {
                it.guard += 1;
                const c = it.cur;
                const e = f.dom.at(c);
                it.cur = e.next;
                if (!e.run and e.cs.display == .none) continue;
                // a paged document's repeating fixed boxes leave the tree (takumi `take_repeating_fixed`)
                if (paged and !e.run and e.cs.position == .fixed) continue;
                if (collapsibleSpace(e) and (it.cp.items_parent or !it.after_inline)) continue;
                const cls = childClass(e);
                if (cls != .out_of_flow) it.after_inline = cls == .inline_flow;
                return c;
            }
            return null;
        }
    };

    fn iter(cp: *const ChildPlaces) Iter {
        return .{ .cp = cp, .cur = cp.f.dom.at(cp.parent).first, .after_inline = cp.parent_inline };
    }

    /// The place of child `el`: `.{ index, index inside the anonymous block or null }`.
    fn of(cp: *const ChildPlaces, el: u32) ?struct { u32, ?u32 } {
        const f = cp.f;
        // (a list item's marker is its first child in takumi's tree)
        var index: u32 = if (markers.hasMarker(f, cp.parent)) 1 else 0;
        var it = cp.iter();
        if (!cp.mixed) {
            while (it.next()) |c| {
                if (c == el) return .{ index, null };
                index += 1;
            }
            return null;
        }
        // runs of inline content (with the floats and out-of-flow boxes inside them): one
        // anonymous block each when the run holds in-flow inline content
        var run: [2]u32 = .{ 0, 0 }; // members so far, in-flow inline members so far
        var found: ?u32 = null;
        while (true) {
            const c = it.next();
            const cls: ChildClass = if (c) |x| childClass(f.dom.at(x)) else .block;
            if (cls == .block) {
                // the run before this child ends
                if (run[0] > 0) {
                    if (run[1] > 0) {
                        if (found) |inner| return .{ index, inner };
                        index += 1;
                    } else {
                        if (found) |inner| return .{ index + inner, null };
                        index += run[0];
                    }
                    run = .{ 0, 0 };
                }
                const x = c orelse return null;
                if (x == el) return .{ index, null };
                index += 1;
                continue;
            }
            if (c.? == el) found = run[0];
            run[0] += 1;
            if (cls == .inline_flow) run[1] += 1;
        }
    }
};

/// takumi `tag_id` of the path to render node `node`: `n` and the child indices from the root
/// (krilla prefixes `U`); the document sits under takumi's page root, so paths start at child 0.
fn tagId(a: Allocator, f: *const Frame, node: u32) Error![]const u8 {
    var rev: std.ArrayList(u32) = .empty;
    const root_el = f.nodes.items[f.root].el;
    var el = f.nodes.items[node].el;
    var guard: u32 = 0;
    while (el != none and el != root_el and guard < 4096) : (guard += 1) {
        const parent = f.dom.at(el).parent;
        if (parent == none) break;
        const cp = ChildPlaces.init(f, parent);
        if (cp.of(el)) |place| {
            if (place[1]) |inner| try rev.append(a, inner);
            try rev.append(a, place[0]);
        } else try rev.append(a, 0);
        el = parent;
    }
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(a, "Un.0");
    var i = rev.items.len;
    while (i > 0) {
        i -= 1;
        var t: [16]u8 = undefined;
        try buf.append(a, '.');
        try buf.appendSlice(a, std.fmt.bufPrint(&t, "{d}", .{rev.items[i]}) catch unreachable);
    }
    return buf.items;
}

/// takumi `should_create_inline_layout` for a block that lays out no line: its children are
/// all inline-level and none of them puts anything on a line (`<h1><span> </span></h1>`).
/// takumi still opens the block's (empty) content region.
pub fn emptyInlineBlock(f: *const Frame, id: u32) bool {
    const n = &f.nodes.items[id];
    if (n.kind != .container or n.el == none) return false;
    switch (n.cs.display) {
        .block, .flow_root, .inline_block, .list_item, .table_cell, .table_caption => {},
        else => return false,
    }
    // (lines, or block-level children, are render nodes)
    var c = firstLive(f, n);
    while (c != none) : (c = nextLive(f, c)) {
        const cn = &f.nodes.items[c];
        if (cn.kind == .anon_text or cn.kind == .anon_box) return false;
        if (!(cn.cs.float != .none or cn.cs.position == .absolute or cn.cs.position == .fixed)) return false;
    }
    var found = false;
    var k = f.dom.at(n.el).first;
    var guard: u32 = 0;
    while (k != none and guard < 1 << 20) : (k = f.dom.at(k).next) {
        guard += 1;
        const e = f.dom.at(k);
        if (e.run) continue;
        if (e.cs.display == .none) continue;
        switch (childClass(e)) {
            .inline_flow => found = true,
            .out_of_flow => {},
            .block => return false,
        }
    }
    return found;
}

/// Whether DOM element `el` has a child in takumi's render tree (an element that generates a
/// box, text that is not only white space, generated content).
fn hasTreeChildren(f: *const Frame, el: u32) bool {
    const e = f.dom.at(el);
    if (e.before != none or e.after != none) return true;
    if (e.kind == .text and std.mem.trim(u8, e.text, &std.ascii.whitespace).len > 0) return true;
    var k = e.first;
    var guard: u32 = 0;
    while (k != none and guard < 1 << 20) : (k = f.dom.at(k).next) {
        guard += 1;
        const c = f.dom.at(k);
        if (c.run) {
            if (std.mem.trim(u8, c.text, &std.ascii.whitespace).len > 0) return true;
            continue;
        }
        if (c.cs.display != .none) return true;
    }
    return false;
}

/// The role of an inline element that is no render node here (an inline box of a paragraph), by
/// its tag (takumi `role`; the roles an inline box can carry).
fn inlineRole(f: *const Frame, el: u32) ?Role {
    const e = f.dom.at(el);
    if (e.kind == .text) return null;
    const tag = e.tag;
    if (eq(tag, "a")) {
        const h = f.dom.attr(el, "href") orelse return null;
        return if (h.len > 0) .link else null;
    }
    if (eq(tag, "strong") or eq(tag, "b")) return .strong;
    if (eq(tag, "em") or eq(tag, "i")) return .em;
    if (eq(tag, "code")) return .code;
    return null;
}

/// Whether the inline content element `el` lays out holds an inline element with a text role
/// (`strong` / `b`, `em` / `i`, `code`): elements that generate a box of their own (blocks, inline
/// blocks, out-of-flow and floating boxes) are not looked into.
fn hasInlineRoleText(f: *const Frame, el: u32) bool {
    var stack: [64]u32 = undefined;
    var sp: usize = 0;
    var k = f.dom.at(el).first;
    var guard: u32 = 0;
    while (guard < 1 << 16) : (guard += 1) {
        if (k == none) {
            if (sp == 0) return false;
            sp -= 1;
            k = f.dom.at(stack[sp]).next;
            continue;
        }
        const c = f.dom.at(k);
        if (c.run or c.kind == .text and c.tag.len == 0 or c.cs.display != .@"inline" or c.cs.position == .absolute or c.cs.position == .fixed or c.cs.float != .none) {
            k = c.next;
            continue;
        }
        if (eq(c.tag, "strong") or eq(c.tag, "b") or eq(c.tag, "em") or eq(c.tag, "i") or eq(c.tag, "code")) return true;
        if (c.first != none and sp < stack.len) {
            stack[sp] = k;
            sp += 1;
            k = c.first;
        } else k = c.next;
    }
    return false;
}

/// An inline element with a role around inline-level boxes (takumi builds it as an element of
/// its own: `<a href><img alt></a>` is `Link > Figure`).
const InlineOpen = struct { el: u32, g: *Group, pending: std.ArrayList(Ident) = .empty };

const max_inline_roles = 16;

/// The inline elements with a role between inline-level box `c` and the block laying it out,
/// outermost first (at most `max_inline_roles`, the innermost ones).
fn inlineRoleChain(f: *const Frame, c: u32, out: *[max_inline_roles]u32) []const u32 {
    const cn = &f.nodes.items[c];
    if (cn.el == none or cn.kind == .anon_text or cn.kind == .anon_box) return out[0..0];
    // the element of the block: the nearest ancestor render node that has one
    var host: u32 = none;
    var p = cn.parent;
    var guard: u32 = 0;
    while (p != none and guard < 64) : (guard += 1) {
        const pn = &f.nodes.items[p];
        if (pn.el != none and pn.kind != .anon_text and pn.kind != .anon_box) {
            host = pn.el;
            break;
        }
        p = pn.parent;
    }
    if (host == none) return out[0..0];
    var k: usize = max_inline_roles;
    var el = f.dom.at(cn.el).parent;
    guard = 0;
    while (el != none and el != host and guard < 4096) : (guard += 1) {
        if (inlineRole(f, el) != null and k > 0) {
            k -= 1;
            out[k] = el;
        }
        el = f.dom.at(el).parent;
    }
    if (el != host) return out[0..0];
    return out[k..];
}

fn closeInline(wk: *Walk, open: *std.ArrayList(*InlineOpen), keep: usize, parent: *std.ArrayList(Kid)) Error!void {
    while (open.items.len > keep) {
        const top = open.items[open.items.len - 1];
        open.items.len -= 1;
        try flushParagraph(wk, &top.pending, &top.g.kids);
        // an empty element goes
        if (top.g.kids.items.len == 0) continue;
        const into = if (open.items.len > 0) &open.items[open.items.len - 1].g.kids else parent;
        try into.append(wk.a, .{ .group = top.g });
    }
}

fn buildChildren(wk: *Walk, id: u32, parent: *std.ArrayList(Kid), pending: *std.ArrayList(Ident), nesting: Nesting) Error!void {
    const n = &wk.f.nodes.items[id];
    const inner: Nesting = .{ .in_row = isRowFlex(n), .in_list = nesting.in_list, .in_figure = nesting.in_figure };
    const items = n.kind != .anon_text and n.kind != .anon_box and switch (n.cs.display) {
        .flex, .inline_flex, .grid, .inline_grid, .webkit_box, .webkit_inline_box => true,
        else => false,
    };
    return buildKids(wk, try liveKids(wk, id), items, parent, pending, inner);
}

/// Builds a run of sibling boxes. A table part outside a table (a cell, row, row group or
/// caption whose parent is none: `items` false, as flex / grid items are blockified) sits in the
/// anonymous table takumi's tree wraps the run of them in (`wrap_orphan_table_parts`).
fn buildKids(wk: *Walk, kids: []const u32, items: bool, parent: *std.ArrayList(Kid), pending: *std.ArrayList(Ident), inner: Nesting) Error!void {
    const f = wk.f;
    var open: std.ArrayList(*InlineOpen) = .empty;
    var i: usize = 0;
    while (i < kids.len) : (i += 1) {
        const c = kids[i];
        if (!items and tpartOf(f, c) != .other and tpartOf(f, c) != .column) {
            var j = i;
            while (j < kids.len and tpartOf(f, kids[j]) != .other) j += 1;
            try closeInline(wk, &open, 0, parent);
            try flushParagraph(wk, pending, parent);
            try buildTable(wk, none, kids[i..j], parent, inner);
            i = j - 1;
            continue;
        }
        var chain_buf: [max_inline_roles]u32 = undefined;
        const chain = inlineRoleChain(f, c, &chain_buf);
        if (chain.len > 0 or open.items.len > 0) {
            var common: usize = 0;
            while (common < chain.len and common < open.items.len and open.items[common].el == chain[common]) common += 1;
            try closeInline(wk, &open, common, parent);
            for (chain[common..]) |el| {
                // the element ends the run of bare content before it
                if (open.items.len > 0) {
                    const top = open.items[open.items.len - 1];
                    try flushParagraph(wk, &top.pending, &top.g.kids);
                } else try flushParagraph(wk, pending, parent);
                const io = try wk.a.create(InlineOpen);
                io.* = .{ .el = el, .g = try wk.newGroup(inlineRole(f, el).?) };
                try open.append(wk.a, io);
            }
        }
        if (open.items.len > 0) {
            const top = open.items[open.items.len - 1];
            try buildNode(wk, c, &top.g.kids, &top.pending, .{ .in_row = inner.in_row, .in_list = false, .in_figure = inner.in_figure });
        } else try buildNode(wk, c, parent, pending, inner);
    }
    try closeInline(wk, &open, 0, parent);
}

fn buildNode(wk: *Walk, id: u32, parent: *std.ArrayList(Kid), pending: *std.ArrayList(Ident), nesting: Nesting) Error!void {
    const n = &wk.f.nodes.items[id];
    if (n.kind != .anon_text and isTable(n.cs.display)) {
        try flushParagraph(wk, pending, parent);
        return buildTable(wk, id, try liveKids(wk, id), parent, nesting);
    }
    var role = try roleOf(wk, id, nesting);
    if (role == null and wk.targets.contains(id)) role = .{ .role = .p };
    if (role) |r| {
        try flushParagraph(wk, pending, parent);
        const is_li = r.role == .li;
        if (try buildElement(wk, id, r, nesting, false)) |g| {
            if (is_li and !nesting.in_list) {
                const list = try wk.newGroup(.l);
                list.numbering = .none;
                try list.kids.append(wk.a, .{ .group = g });
                try parent.append(wk.a, .{ .group = list });
            } else try parent.append(wk.a, .{ .group = g });
        }
        return;
    }
    const rec = try wk.c.take(id);
    const block = isBlock(wk.f, n) and !nesting.in_row;
    if (block) try flushParagraph(wk, pending, parent);
    try pending.appendSlice(wk.a, rec.labels.items);
    try pending.appendSlice(wk.a, rec.ids.items);
    // takumi walks the inline elements of the box's text as render nodes of their own, after the
    // box's content: one with a role (`<b>`, `<em>`, `<code>`...) ends the run of bare content
    // collected so far, and draws nothing of its own (its text is the box's), so its element goes
    if (rec.ids.items.len > 0 and n.el != none and n.kind != .anon_text and n.kind != .anon_box and hasInlineRoleText(wk.f, n.el)) try flushParagraph(wk, pending, parent);
    try buildChildren(wk, id, parent, pending, nesting);
    if (block) try flushParagraph(wk, pending, parent);
    if (rec.annots.items.len > 0) {
        try flushParagraph(wk, pending, parent);
        try pushLinkWrappers(wk, rec.annots.items, parent);
    }
}

/// A role and its attributes (takumi `role`).
const RoleSpec = struct { role: Role, level: u16 = 0, title: ?[]const u8 = null, alt: ?[]const u8 = null, numbering: ?Numbering = null, scope: ?Scope = null, row_span: u32 = 0, col_span: u32 = 0 };

fn buildElement(wk: *Walk, id: u32, spec: RoleSpec, nesting: Nesting, keep_empty: bool) Error!?*Group {
    const rec = try wk.c.take(id);
    const g = try wk.newGroup(spec.role);
    g.level = spec.level;
    g.title = spec.title;
    g.alt = spec.alt;
    g.numbering = spec.numbering;
    g.scope = spec.scope;
    g.row_span = spec.row_span;
    g.col_span = spec.col_span;
    const is_link = spec.role == .link;
    const is_li = spec.role == .li;
    const is_target = try wk.nameTarget(id, g);
    var children: std.ArrayList(Kid) = .empty;
    var child_pending: std.ArrayList(Ident) = .empty;
    var has_content = rec.ids.items.len > 0 or rec.labels.items.len > 0;
    if (is_li) {
        if (rec.labels.items.len > 0) {
            const lbl = try wk.newGroup(.lbl);
            for (rec.labels.items) |x| try lbl.kids.append(wk.a, .{ .leaf = x });
            try g.kids.append(wk.a, .{ .group = lbl });
        }
        try child_pending.appendSlice(wk.a, rec.ids.items);
    } else {
        for (rec.labels.items) |x| try g.kids.append(wk.a, .{ .leaf = x });
        for (rec.ids.items) |x| try g.kids.append(wk.a, .{ .leaf = x });
    }
    try buildChildren(wk, id, &children, &child_pending, .{ .in_row = nesting.in_row, .in_list = spec.role == .l, .in_figure = nesting.in_figure or spec.role == .figure });
    try flushParagraph(wk, &child_pending, &children);
    if (!is_link) try pushLinkWrappers(wk, rec.annots.items, &children);
    has_content = has_content or children.items.len > 0;
    if (is_li) {
        if (children.items.len > 0) {
            const body = try wk.newGroup(.lbody);
            try body.kids.appendSlice(wk.a, children.items);
            try g.kids.append(wk.a, .{ .group = body });
        }
    } else try g.kids.appendSlice(wk.a, children.items);
    if (is_link) {
        has_content = has_content or rec.annots.items.len > 0;
        for (rec.annots.items) |x| try g.kids.append(wk.a, .{ .leaf = x });
    }
    return if (has_content or is_target or keep_empty) g else null;
}

/// Blink's span attributes (`table/parts.rs`): leading white space, then digits.
fn spanAttr(v: []const u8) ?u32 {
    var i: usize = 0;
    while (i < v.len and (v[i] == ' ' or v[i] == '\t' or v[i] == '\n' or v[i] == '\r' or v[i] == 12)) i += 1;
    if (i < v.len and v[i] == '+') i += 1;
    var n: u32 = 0;
    var digits = false;
    while (i < v.len and v[i] >= '0' and v[i] <= '9') : (i += 1) {
        digits = true;
        n = @min(n *| 10 +| (v[i] - '0'), 1 << 30);
    }
    return if (digits) n else null;
}

fn cellSpans(f: *const Frame, n: *const Node) [2]u32 {
    const tag = tagOf(f, n);
    if (!(eq(tag, "td") or eq(tag, "th"))) return .{ 1, 1 };
    var col: u32 = 1;
    var row: u32 = 1;
    if (attrOf(f, n, "colspan")) |v| if (spanAttr(v)) |x| {
        col = std.math.clamp(x, 1, 1000);
    };
    if (attrOf(f, n, "rowspan")) |v| if (spanAttr(v)) |x| {
        row = if (x == 0) 65534 else @min(x, 65534);
    };
    return .{ row, col };
}

/// `TH` or `TD` for a cell (takumi `cell_kind`).
fn cellKind(f: *const Frame, cell: *const Node, in_header: bool, rows_left: usize) RoleSpec {
    const tag = tagOf(f, cell);
    const sp = cellSpans(f, cell);
    const rs: u32 = @intCast(@min(sp[0], rows_left));
    const row_span: u32 = if (rs > 1) rs else 0;
    const col_span: u32 = if (sp[1] > 1) sp[1] else 0;
    const header = if (eq(tag, "th")) true else if (eq(tag, "td")) false else in_header;
    if (!header) return .{ .role = .td, .row_span = row_span, .col_span = col_span };
    var scope: Scope = if (in_header) .column else .row;
    if (attrOf(f, cell, "scope")) |s| {
        const t = std.mem.trim(u8, s, " \t\n\r\x0c");
        if (eq(t, "row") or eq(t, "rowgroup")) scope = .row else if (eq(t, "col") or eq(t, "colgroup")) scope = .column;
    }
    return .{ .role = .th, .scope = scope, .row_span = row_span, .col_span = col_span };
}

const TPart = enum { caption, group, row, cell, column, other };

/// The table part a box is (its display; a float or an out-of-flow box is blockified).
fn tpartOf(f: *const Frame, id: u32) TPart {
    const n = &f.nodes.items[id];
    if (n.kind == .anon_text or n.kind == .anon_box) return .other;
    if (n.cs.float != .none or n.cs.position == .absolute or n.cs.position == .fixed) return .other;
    return switch (n.cs.display) {
        .table_caption => .caption,
        .table_header_group, .table_row_group, .table_footer_group => .group,
        .table_row => .row,
        .table_cell => .cell,
        .table_column, .table_column_group => .column,
        else => .other,
    };
}

/// A table part: a box of the frame, or the anonymous box takumi's tree (Blink's table fix-up)
/// wraps `items` in.
const TBox = struct { node: u32 = none, items: std.ArrayList(u32) = .empty };

/// `kids` as the children of a table (`want` = group), a row group (row) or a row (cell): each
/// kid of that part is a box of its own, every run of other kids is one anonymous box of that
/// part (Blink `LayoutTable::AddChild` and its section / row counterparts).
fn tboxes(wk: *Walk, kids: []const u32, want: TPart) Error![]TBox {
    var out: std.ArrayList(TBox) = .empty;
    var run_open = false;
    for (kids) |k| {
        const p = tpartOf(wk.f, k);
        if (want == .group and (p == .caption or p == .column)) continue;
        if (p == want) {
            try out.append(wk.a, .{ .node = k });
            run_open = false;
            continue;
        }
        if (!run_open) {
            try out.append(wk.a, .{});
            run_open = true;
        }
        try out.items[out.items.len - 1].items.append(wk.a, k);
    }
    return out.items;
}

/// An anonymous cell around `items`: lines of text alone are the cell's own inline layout,
/// anything else its children.
fn anonCell(wk: *Walk, items: []const u32, in_header: bool, nesting: Nesting) Error!*Group {
    const f = wk.f;
    const g = try wk.newGroup(if (in_header) .th else .td);
    if (in_header) g.scope = .column;
    var all_inline = true;
    for (items) |it| {
        const k = f.nodes.items[it].kind;
        if (k != .anon_text and k != .anon_box) all_inline = false;
    }
    var children: std.ArrayList(Kid) = .empty;
    var child_pending: std.ArrayList(Ident) = .empty;
    if (all_inline) {
        var annots: std.ArrayList(Ident) = .empty;
        for (items) |it| {
            const rec = try wk.c.take(it);
            for (rec.labels.items) |x| try g.kids.append(wk.a, .{ .leaf = x });
            for (rec.ids.items) |x| try g.kids.append(wk.a, .{ .leaf = x });
            try annots.appendSlice(wk.a, rec.annots.items);
            try buildChildren(wk, it, &children, &child_pending, nesting);
        }
        try flushParagraph(wk, &child_pending, &children);
        try pushLinkWrappers(wk, annots.items, &children);
    } else {
        try buildKids(wk, items, false, &children, &child_pending, nesting);
        try flushParagraph(wk, &child_pending, &children);
    }
    try g.kids.appendSlice(wk.a, children.items);
    return g;
}

/// A table's structure, one `Table` across pages (takumi `build_table`). `id`: the table box,
/// none for the anonymous table around the table parts `kids`.
fn buildTable(wk: *Walk, id: u32, kids: []const u32, parent: *std.ArrayList(Kid), outer: Nesting) Error!void {
    const f = wk.f;
    var rec: Collector.Recorded = .{};
    if (id != none) rec = try wk.c.take(id);
    var annots: std.ArrayList(Ident) = .empty;
    try annots.appendSlice(wk.a, rec.annots.items);
    const table = try wk.newGroup(.table);
    const is_target = id != none and try wk.nameTarget(id, table);
    const nesting: Nesting = .{ .in_figure = outer.in_figure };
    var groups: std.ArrayList(Kid) = .empty;

    for ([_]style.computed.CaptionSide{ .top, .bottom }, 0..) |side, pass| {
        if (pass == 1) {
            // sections between the captions
            if (rec.ids.items.len > 0) {
                var wrap: std.ArrayList(Kid) = .empty;
                var own: std.ArrayList(Ident) = .empty;
                try own.appendSlice(wk.a, rec.ids.items);
                try flushParagraph(wk, &own, &wrap);
                const td = try wk.newGroup(.td);
                try td.kids.appendSlice(wk.a, wrap.items);
                const tr = try wk.newGroup(.tr);
                try tr.kids.append(wk.a, .{ .group = td });
                try groups.append(wk.a, .{ .group = tr });
            }
            try tableSections(wk, kids, &groups, &annots, nesting);
        }
        for (kids) |c| {
            const cn = &f.nodes.items[c];
            if (tpartOf(f, c) != .caption or cn.cs.caption_side != side) continue;
            if (try buildElement(wk, c, .{ .role = .caption }, nesting, false)) |g| try groups.append(wk.a, .{ .group = g });
        }
    }
    if (groups.items.len > 0 or is_target) {
        try table.kids.appendSlice(wk.a, groups.items);
        try parent.append(wk.a, .{ .group = table });
    }
    try pushLinkWrappers(wk, annots.items, parent);
}

/// The table's sections in table order: the first header group, the bodies, the first footer
/// group (takumi `table_sections`), with the anonymous row groups, rows and cells of the fix-up.
fn tableSections(wk: *Walk, kids: []const u32, groups: *std.ArrayList(Kid), table_annots: *std.ArrayList(Ident), nesting: Nesting) Error!void {
    const f = wk.f;
    const secs = try tboxes(wk, kids, .group);
    var head: ?usize = null;
    var foot: ?usize = null;
    for (secs, 0..) |s, i| {
        if (s.node == none) continue;
        const d = f.nodes.items[s.node].cs.display;
        if (d == .table_header_group and head == null) head = i;
        if (d == .table_footer_group and foot == null) foot = i;
    }
    var order: std.ArrayList(usize) = .empty;
    if (head) |h| try order.append(wk.a, h);
    for (secs, 0..) |_, i| {
        if ((head != null and head.? == i) or (foot != null and foot.? == i)) continue;
        try order.append(wk.a, i);
    }
    if (foot) |x| try order.append(wk.a, x);
    for (order.items) |si| {
        const sec = &secs[si];
        const display: style.computed.Display = if (sec.node != none) f.nodes.items[sec.node].cs.display else .table_row_group;
        const in_header = display == .table_header_group;
        const sec_kids = if (sec.node != none) try liveKids(wk, sec.node) else sec.items.items;
        const row_boxes = try tboxes(wk, sec_kids, .row);
        const section_links = if (sec.node != none) try wk.c.take(sec.node) else Collector.Recorded{};
        var rows: std.ArrayList(*Group) = .empty;
        for (row_boxes, 0..) |*row, row_index| {
            const row_links = if (row.node != none) try wk.c.take(row.node) else Collector.Recorded{};
            const row_kids = if (row.node != none) try liveKids(wk, row.node) else row.items.items;
            var cells: std.ArrayList(Kid) = .empty;
            for (try tboxes(wk, row_kids, .cell)) |*cell| {
                if (cell.node != none) {
                    const cn = &f.nodes.items[cell.node];
                    if (try buildElement(wk, cell.node, cellKind(f, cn, in_header, row_boxes.len - row_index), nesting, true)) |g| try cells.append(wk.a, .{ .group = g });
                } else try cells.append(wk.a, .{ .group = try anonCell(wk, cell.items.items, in_header, nesting) });
            }
            if (cells.items.len > 0) {
                try pushLinkWrappers(wk, row_links.annots.items, &cells.items[cells.items.len - 1].group.kids);
                const tr = try wk.newGroup(.tr);
                try tr.kids.appendSlice(wk.a, cells.items);
                try rows.append(wk.a, tr);
            } else try table_annots.appendSlice(wk.a, row_links.annots.items);
        }
        if (rows.items.len > 0) {
            const last_row = rows.items[rows.items.len - 1];
            const last_cell = last_row.kids.items[last_row.kids.items.len - 1].group;
            try pushLinkWrappers(wk, section_links.annots.items, &last_cell.kids);
            const tag: Role = switch (display) {
                .table_header_group => .thead,
                .table_footer_group => .tfoot,
                else => .tbody,
            };
            const sg = try wk.newGroup(tag);
            for (rows.items) |tr| try sg.kids.append(wk.a, .{ .group = tr });
            try groups.append(wk.a, .{ .group = sg });
        } else try table_annots.appendSlice(wk.a, section_links.annots.items);
    }
}

/// The alternate description a `<figure>` takes from the image it illustrates.
fn figureAlt(f: *const Frame, id: u32, depth: u32) ?[]const u8 {
    if (depth > 512) return null;
    const n = &f.nodes.items[id];
    if (eq(tagOf(f, n), "img")) {
        const alt = attrOf(f, n, "alt") orelse return null;
        return if (alt.len > 0) alt else null;
    }
    var c = firstLive(f, n);
    while (c != none) : (c = nextLive(f, c)) {
        if (figureAlt(f, c, depth + 1)) |x| return x;
    }
    return null;
}

fn listNumbering(f: *const Frame, n: *const Node) Numbering {
    return switch (n.cs.list_style_type) {
        .none, .string => .none,
        .ident => |s| blk: {
            const table = [_]struct { []const u8, Numbering }{
                .{ "disc", .disc },               .{ "circle", .circle },           .{ "square", .square },
                .{ "decimal", .decimal },         .{ "decimal-leading-zero", .decimal }, .{ "lower-alpha", .lower_alpha },
                .{ "lower-latin", .lower_alpha }, .{ "upper-alpha", .upper_alpha }, .{ "upper-latin", .upper_alpha },
                .{ "lower-roman", .lower_roman }, .{ "upper-roman", .upper_roman },
            };
            for (table) |e| if (eq(s, e[0])) break :blk e[1];
            if (eq(s, "disclosure-closed") or eq(s, "disclosure-open")) break :blk .none;
            // a counter style takumi does not parse: its declaration is dropped there, which
            // leaves the list the type its element starts with (`ol`: decimal, else disc)
            break :blk if (eq(tagOf(f, n), "ol")) .decimal else .disc;
        },
    };
}

fn roleOf(wk: *Walk, id: u32, nesting: Nesting) Error!?RoleSpec {
    const f = wk.f;
    const n = &f.nodes.items[id];
    const tag = tagOf(f, n);
    if (tag.len == 0) return null;
    if (tag.len == 2 and (tag[0] == 'h' or tag[0] == 'H') and tag[1] >= '1' and tag[1] <= '6') {
        const title = try @import("interactive.zig").textContent(wk.a, f, n.el);
        if (title.len == 0 and !hasTreeChildren(f, n.el)) return null;
        const level = try wk.headingLevel(tag[1] - '0');
        return .{ .role = .h, .level = level, .title = if (title.len > 0) title else null };
    }
    if (eq(tag, "p")) return .{ .role = .p };
    if (eq(tag, "figure")) {
        const alt = figureAlt(f, id, 0) orelse return null;
        return .{ .role = .figure, .alt = alt };
    }
    if (eq(tag, "img")) {
        if (nesting.in_figure) return null;
        const alt = attrOf(f, n, "alt");
        if (alt) |x| if (x.len == 0) return null;
        return .{ .role = .figure, .alt = alt };
    }
    if (eq(tag, "a")) return if (attrOf(f, n, "href") != null) .{ .role = .link } else null;
    if (eq(tag, "blockquote")) return .{ .role = .block_quote };
    if (eq(tag, "section")) return .{ .role = .sect };
    if (eq(tag, "article")) return .{ .role = .art };
    if (eq(tag, "ul") or eq(tag, "ol")) return .{ .role = .l, .numbering = listNumbering(f, n) };
    if (eq(tag, "li")) return .{ .role = .li };
    if (eq(tag, "strong") or eq(tag, "b")) return .{ .role = .strong };
    if (eq(tag, "em") or eq(tag, "i")) return .{ .role = .em };
    if (eq(tag, "code")) return .{ .role = .code };
    if (eq(tag, "figcaption")) return .{ .role = .caption };
    return null;
}

/// Whether node `id` is an image the document marks as decorative (`alt=""`): an artifact.
pub fn decorativeImage(f: *const Frame, id: u32) bool {
    const n = &f.nodes.items[id];
    if (!eq(tagOf(f, n), "img")) return false;
    const alt = attrOf(f, n, "alt") orelse return false;
    return alt.len == 0;
}

/// The document's structure tree under a `Document` root (takumi `build_tree`).
pub fn build(c: *Collector, lang: ?[]const u8, targets: *const std.AutoHashMapUnmanaged(u32, void)) Error!*Group {
    std.sort.block(Record, c.records.items, {}, struct {
        fn lt(_: void, x: Record, y: Record) bool {
            return x.node < y.node;
        }
    }.lt);
    var wk: Walk = .{ .c = c, .a = c.a, .f = c.f, .targets = targets };
    const root = try wk.newGroup(.document);
    root.title = lang; // the Document root carries the language (written as /Lang)
    var top: std.ArrayList(Kid) = .empty;
    var pending: std.ArrayList(Ident) = .empty;
    try buildNode(&wk, c.f.root, &top, &pending, .{});
    try flushParagraph(&wk, &pending, &top);
    // Whatever the walk did not reach still needs a parent: a marked-content sequence or an
    // annotation outside the structure tree is a null parent-tree entry (krilla refuses to write
    // one). It reads last, as a paragraph / a link of its own.
    for (c.records.items) |*r| {
        if (r.taken) continue;
        r.taken = true;
        if (r.kind == .annotation) {
            try flushParagraph(&wk, &pending, &top);
            try pushLinkWrappers(&wk, &.{r.id}, &top);
        } else try pending.append(c.a, r.id);
    }
    try flushParagraph(&wk, &pending, &top);
    try root.kids.appendSlice(c.a, top.items);
    return root;
}

// ---------------------------------------------------------------------------------------------
// Serialisation (krilla `TagTree::serialize`, `serialize_tag_tree`)
// ---------------------------------------------------------------------------------------------

/// The page / annotation a parent-tree entry stands for (krilla `StructParentElement`).
pub const StructParent = union(enum) { page: struct { index: u32, mcids: i32 }, annot: u32 };

pub const AnnotRef = struct { ref: Ref, page: u32, parent: ?Ref = null };

pub const Problems = struct {
    missing_heading_title: bool = false,
    missing_alt: bool = false,
};

const Ser = struct {
    a: Allocator,
    d: *w.Doc,
    pdf2: bool,
    ssn: Ref,
    page_refs: []const Ref,
    annots: []AnnotRef,
    /// (page, mcid) -> parent element
    mcid_parent: std.AutoHashMapUnmanaged(u64, Ref) = .empty,
    ids: std.ArrayList(struct { name: []const u8, ref: Ref }) = .empty,
    node_elems: *std.AutoHashMapUnmanaged(u32, Ref),
    problems: Problems = .{},
};

fn roleName(g: *const Group, buf: *[3]u8) []const u8 {
    return switch (g.role) {
        .document => "Document",
        .p => "P",
        .h => blk: {
            buf[0] = 'H';
            buf[1] = '0' + @as(u8, @intCast(@min(g.level, 9)));
            break :blk buf[0..2];
        },
        .link => "Link",
        .figure => "Figure",
        .block_quote => "BlockQuote",
        .sect => "Sect",
        .art => "Art",
        .l => "L",
        .li => "LI",
        .lbl => "Lbl",
        .lbody => "LBody",
        .strong => "Strong",
        .em => "Em",
        .code => "Code",
        .caption => "Caption",
        .table => "Table",
        .tr => "TR",
        .th => "TH",
        .td => "TD",
        .thead => "THead",
        .tbody => "TBody",
        .tfoot => "TFoot",
    };
}

/// Roles krilla writes as PDF 1.7 roles even in PDF 2.0 (`write_kind_1_7`): no namespace.
fn plain17(r: Role) bool {
    return r == .block_quote or r == .art or r == .code;
}

fn serialize(s: *Ser, g: *const Group, parent: Ref) Error!Ref {
    const me = s.d.alloc();
    const Child = union(enum) { elem: Ref, leaf: Ident };
    var kids: std.ArrayList(Child) = .empty;
    for (g.kids.items) |k| switch (k) {
        .group => |sub| try kids.append(s.a, .{ .elem = try serialize(s, sub, me) }),
        .leaf => |id| try kids.append(s.a, .{ .leaf = id }),
    };
    const b = s.d.beginDict(me, .struct_elements);
    b.pairName("Type", "StructElem");
    var nb: [3]u8 = undefined;
    b.pairName("S", roleName(g, &nb));
    if (s.pdf2 and !plain17(g.role)) b.pairRef("NS", s.ssn);
    b.pairRef("P", parent);
    if (g.id) |id| {
        b.pairStr("ID", id);
        try s.ids.append(s.a, .{ .name = id, .ref = me });
        if (g.node != none) try s.node_elems.put(s.a, g.node, me);
    }
    if (g.role == .h and (g.title == null or g.title.?.len == 0)) s.problems.missing_heading_title = true;
    if (g.role == .figure and (g.alt == null or g.alt.?.len == 0)) s.problems.missing_alt = true;
    if (g.role == .document) {
        if (g.title) |lang| b.pairText("Lang", lang);
    } else if (g.title) |t| b.pairText("T", t);
    if (g.alt) |alt| b.pairText("Alt", alt);
    if (g.numbering) |num| {
        b.raw("/A[<</O/List");
        b.pairName("ListNumbering", switch (num) {
            .none => "None",
            .disc => "Disc",
            .circle => "Circle",
            .square => "Square",
            .decimal => "Decimal",
            .lower_roman => "LowerRoman",
            .upper_roman => "UpperRoman",
            .lower_alpha => "LowerAlpha",
            .upper_alpha => "UpperAlpha",
        });
        b.raw(">>]");
    } else if (g.scope != null or g.row_span > 0 or g.col_span > 0) {
        b.raw("/A[<</O/Table");
        if (g.scope) |sc| b.pairName("Scope", if (sc == .row) "Row" else "Column");
        if (g.row_span > 0) b.pairInt("RowSpan", g.row_span);
        if (g.col_span > 0) b.pairInt("ColSpan", g.col_span);
        b.raw(">>]");
    }
    b.key("K");
    b.arr();
    var pg: ?u32 = null;
    for (kids.items) |k| switch (k) {
        .elem => |r| b.ref(r),
        .leaf => |id| switch (id) {
            .mcid => |m| {
                if (pg == null) pg = m.page;
                try s.mcid_parent.put(s.a, (@as(u64, m.page) << 32) | @as(u32, @bitCast(m.mcid)), me);
                if (pg.? == m.page) {
                    b.int(m.mcid);
                } else {
                    b.raw("<</Type/MCR");
                    b.pairInt("MCID", m.mcid);
                    b.pairRef("Pg", s.page_refs[m.page]);
                    b.raw(">>");
                }
            },
            .annot => |ai| {
                const an = &s.annots[ai];
                an.parent = me;
                b.raw("<</Type/OBJR");
                b.pairRef("Pg", s.page_refs[an.page]);
                b.pairRef("Obj", an.ref);
                b.raw(">>");
            },
        },
    };
    b.arrEnd();
    if (pg) |p| b.pairRef("Pg", s.page_refs[p]);
    s.d.endDict();
    return me;
}

pub const Written = struct { root: Ref, problems: Problems };

/// Writes the structure tree, its root, the parent tree and the ID tree. `parents`: the parent
/// tree entries in registration order (`StructParents` / `StructParent` numbers).
pub fn write(a: Allocator, d: *w.Doc, root: *const Group, page_refs: []const Ref, annots: []AnnotRef, parents: []const StructParent, node_elems: *std.AutoHashMapUnmanaged(u32, Ref)) Error!Written {
    const pdf2 = d.version.atLeast(.v2_0);
    const tree_root = d.alloc();
    var s: Ser = .{ .a = a, .d = d, .pdf2 = pdf2, .ssn = if (pdf2) d.alloc() else 0, .page_refs = page_refs, .annots = annots, .node_elems = node_elems };
    const krilla_ns: Ref = if (pdf2) d.alloc() else 0;
    const doc_ref = try serialize(&s, root, tree_root);

    // the root, then its sub-objects (namespaces, parent-tree arrays) in the same chunk
    var lists = try a.alloc(Ref, parents.len);
    for (parents, 0..) |p, i| lists[i] = if (p == .page) d.alloc() else 0;
    {
        const b = d.beginDict(tree_root, .struct_tree_root);
        b.pairName("Type", "StructTreeRoot");
        if (!pdf2) {
            b.raw("/RoleMap<</Datetime/Span/Terms/Part/Title/P/Strong/Span/Em/Span>>");
        } else {
            b.key("Namespaces");
            b.refs(&.{ s.ssn, krilla_ns });
        }
        b.key("K");
        b.refs(&.{doc_ref});
        if (parents.len > 0) {
            b.raw("/ParentTree<</Nums[");
            for (parents, 0..) |p, i| {
                b.int(@intCast(i));
                switch (p) {
                    .page => b.ref(lists[i]),
                    .annot => |ai| if (annots[ai].parent) |r| b.ref(r) else b.nul(),
                }
            }
            b.raw("]>>");
        }
        if (s.ids.items.len > 0) {
            const items = s.ids.items;
            std.sort.block(@TypeOf(items[0]), items, {}, struct {
                fn lt(_: void, x: @TypeOf(items[0]), y: @TypeOf(items[0])) bool {
                    return std.mem.order(u8, x.name, y.name) == .lt;
                }
            }.lt);
            b.raw("/IDTree<</Names[");
            for (items) |it| {
                b.str(it.name);
                b.ref(it.ref);
            }
            b.raw("]>>");
        }
        if (parents.len > 0) b.pairInt("ParentTreeNextKey", @intCast(parents.len));
        d.endDict();
    }
    if (pdf2) {
        var b = d.beginDict(s.ssn, .struct_tree_root);
        b.pairName("Type", "Namespace");
        b.pairText("NS", "http://iso.org/pdf2/ssn");
        d.endDict();
        b = d.beginDict(krilla_ns, .struct_tree_root);
        b.pairName("Type", "Namespace");
        b.pairText("NS", "https://github.com/LaurenzV/krilla");
        b.raw("/RoleMapNS<</Datetime[/Span");
        b.ref(s.ssn);
        b.raw("]/Terms[/Part");
        b.ref(s.ssn);
        b.raw("]>>");
        d.endDict();
    }
    for (parents, 0..) |p, i| {
        const pp = switch (p) {
            .page => |x| x,
            .annot => continue,
        };
        const b = d.begin(lists[i], .struct_tree_root);
        b.arr();
        var m: i32 = 0;
        while (m < pp.mcids) : (m += 1) {
            if (s.mcid_parent.get((@as(u64, pp.index) << 32) | @as(u32, @bitCast(m)))) |r| b.ref(r) else b.nul();
        }
        b.arrEnd();
        d.end();
    }
    return .{ .root = tree_root, .problems = s.problems };
}
