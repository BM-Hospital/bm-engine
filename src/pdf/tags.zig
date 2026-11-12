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
    path: std.ArrayList(u32) = .empty,

    fn newGroup(wk: *Walk, role: Role) Error!*Group {
        const g = try wk.a.create(Group);
        g.* = .{ .role = role };
        return g;
    }

    /// takumi `name_target`: the `Un.<path>` id when a destination names `node`.
    fn nameTarget(wk: *Walk, node: u32, g: *Group) Error!bool {
        if (!wk.targets.contains(node)) return false;
        var buf: std.ArrayList(u8) = .empty;
        // the document sits under takumi's page root: its paths start at child 0
        try buf.appendSlice(wk.a, "Un.0");
        for (wk.path.items) |i| {
            var t: [16]u8 = undefined;
            try buf.append(wk.a, '.');
            try buf.appendSlice(wk.a, std.fmt.bufPrint(&t, "{d}", .{i}) catch unreachable);
        }
        g.id = buf.items;
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

/// The children the walk visits: an anonymous only child stands for its block, so its children
/// are the block's.
fn firstKid(f: *const Frame, n: *const Node) u32 {
    const c = n.first_child;
    if (c == none) return none;
    if (standsForParent(f, c)) return f.nodes.items[c].first_child;
    return c;
}

/// An anonymous paragraph leaf / line container that is the only child of a block container is
/// that block's own inline layout in takumi's tree (in a flex / grid container it is an
/// anonymous item of its own).
pub fn standsForParent(f: *const Frame, id: u32) bool {
    const n = &f.nodes.items[id];
    if (!(n.kind == .anon_text or n.kind == .anon_box) or n.parent == none) return false;
    const p = &f.nodes.items[n.parent];
    if (p.first_child != id or p.last_child != id) return false;
    return switch (p.cs.display) {
        .flex, .inline_flex, .grid, .inline_grid, .webkit_box, .webkit_inline_box => false,
        else => true,
    };
}

/// The index takumi's path gives node `id`: its element's place among its DOM siblings (text
/// runs included), else its place among the render node's children.
fn pathIndex(f: *const Frame, id: u32, fallback: u32) u32 {
    const n = &f.nodes.items[id];
    if (n.el == none or n.kind == .anon_text or n.kind == .anon_box) return fallback;
    // (white-space-only text runs are not nodes in takumi's tree)
    var k: u32 = 0;
    const paged = f.paginated() != null;
    var p = f.dom.at(n.el).prev;
    var guard: u32 = 0;
    while (p != none and guard < 1 << 20) : (p = f.dom.at(p).prev) {
        guard += 1;
        const sib = f.dom.at(p);
        if (sib.kind == .text and sib.tag.len == 0 and std.mem.trim(u8, sib.text, &std.ascii.whitespace).len == 0) continue;
        // a paged document's repeating fixed boxes leave the tree (takumi `take_repeating_fixed`)
        if (paged and !sib.run and sib.cs.position == .fixed) continue;
        k += 1;
    }
    // (a list item's marker is its first child in takumi's tree)
    const parent = f.dom.at(n.el).parent;
    if (parent != none and markers.hasMarker(f, parent)) k += 1;
    return k;
}

fn buildChildren(wk: *Walk, id: u32, parent: *std.ArrayList(Kid), pending: *std.ArrayList(Ident), nesting: Nesting) Error!void {
    const f = wk.f;
    const n = &f.nodes.items[id];
    const inner: Nesting = .{ .in_row = isRowFlex(n), .in_list = nesting.in_list, .in_figure = nesting.in_figure };
    var c = firstKid(f, n);
    var index: u32 = 0;
    while (c != none) : (c = f.nodes.items[c].next) {
        try wk.path.append(wk.a, pathIndex(f, c, index));
        try buildNode(wk, c, parent, pending, inner);
        wk.path.items.len -= 1;
        index += 1;
    }
}

fn buildNode(wk: *Walk, id: u32, parent: *std.ArrayList(Kid), pending: *std.ArrayList(Ident), nesting: Nesting) Error!void {
    const n = &wk.f.nodes.items[id];
    if (n.kind != .anon_text and isTable(n.cs.display)) {
        try flushParagraph(wk, pending, parent);
        return buildTable(wk, id, parent, nesting);
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

fn childCount(f: *const Frame, n: *const Node) usize {
    var k: usize = 0;
    var c = n.first_child;
    while (c != none) : (c = f.nodes.items[c].next) k += 1;
    return k;
}

/// A table's structure, one `Table` across pages (takumi `build_table`).
fn buildTable(wk: *Walk, id: u32, parent: *std.ArrayList(Kid), outer: Nesting) Error!void {
    const f = wk.f;
    const n = &f.nodes.items[id];
    const rec = try wk.c.take(id);
    var annots: std.ArrayList(Ident) = .empty;
    try annots.appendSlice(wk.a, rec.annots.items);
    const table = try wk.newGroup(.table);
    const is_target = try wk.nameTarget(id, table);
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
            try tableSections(wk, id, &groups, &annots, nesting);
        }
        var c = n.first_child;
        var index: u32 = 0;
        while (c != none) : ({
            c = f.nodes.items[c].next;
            index += 1;
        }) {
            const cn = &f.nodes.items[c];
            if (cn.kind == .anon_text or cn.cs.display != .table_caption or cn.cs.caption_side != side) continue;
            try wk.path.append(wk.a, pathIndex(f, c, index));
            defer wk.path.items.len -= 1;
            if (try buildElement(wk, c, .{ .role = .caption }, nesting, false)) |g| try groups.append(wk.a, .{ .group = g });
        }
    }
    if (groups.items.len > 0 or is_target) {
        try table.kids.appendSlice(wk.a, groups.items);
        try parent.append(wk.a, .{ .group = table });
    }
    try pushLinkWrappers(wk, annots.items, parent);
}

fn isGroupDisplay(d: style.computed.Display) bool {
    return d == .table_header_group or d == .table_row_group or d == .table_footer_group;
}

/// The table's sections in table order: the first header group, the bodies, the first footer
/// group (takumi `table_sections`).
fn tableSections(wk: *Walk, id: u32, groups: *std.ArrayList(Kid), table_annots: *std.ArrayList(Ident), nesting: Nesting) Error!void {
    const f = wk.f;
    const n = &f.nodes.items[id];
    var head: u32 = none;
    var foot: u32 = none;
    var c = n.first_child;
    while (c != none) : (c = f.nodes.items[c].next) {
        const cn = &f.nodes.items[c];
        if (cn.kind == .anon_text) continue;
        if (cn.cs.display == .table_header_group and head == none) head = c;
        if (cn.cs.display == .table_footer_group and foot == none) foot = c;
    }
    var order: std.ArrayList(u32) = .empty;
    if (head != none) try order.append(wk.a, head);
    c = n.first_child;
    while (c != none) : (c = f.nodes.items[c].next) {
        const cn = &f.nodes.items[c];
        if (c == head or c == foot or cn.kind == .anon_text) continue;
        if (isGroupDisplay(cn.cs.display) or cn.cs.display == .table_row) try order.append(wk.a, c);
    }
    if (foot != none) try order.append(wk.a, foot);
    for (order.items) |sec| {
        const sn = &f.nodes.items[sec];
        var index: u32 = 0;
        var k = n.first_child;
        while (k != sec) : (k = f.nodes.items[k].next) index += 1;
        try wk.path.append(wk.a, pathIndex(f, sec, index));
        defer wk.path.items.len -= 1;
        const display = sn.cs.display;
        const in_header = display == .table_header_group;
        // a row outside any group stands for a group of one
        const single_row = display == .table_row;
        const row_count: usize = if (single_row) 1 else childCount(f, sn);
        const section_links = if (single_row) Collector.Recorded{} else try wk.c.take(sec);
        var rows: std.ArrayList(*Group) = .empty;
        var row_index: usize = 0;
        var r: u32 = if (single_row) sec else sn.first_child;
        while (r != none) : ({
            r = if (single_row) none else f.nodes.items[r].next;
            row_index += 1;
        }) {
            const rn = &f.nodes.items[r];
            const row_links = try wk.c.take(r);
            if (!single_row) try wk.path.append(wk.a, pathIndex(f, r, @intCast(row_index)));
            defer {
                if (!single_row) wk.path.items.len -= 1;
            }
            var cells: std.ArrayList(Kid) = .empty;
            var cell_index: u32 = 0;
            var cell = rn.first_child;
            while (cell != none) : ({
                cell = f.nodes.items[cell].next;
                cell_index += 1;
            }) {
                try wk.path.append(wk.a, pathIndex(f, cell, cell_index));
                defer wk.path.items.len -= 1;
                const cn = &f.nodes.items[cell];
                if (try buildElement(wk, cell, cellKind(f, cn, in_header, row_count - row_index), nesting, true)) |g| try cells.append(wk.a, .{ .group = g });
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
    var c = n.first_child;
    while (c != none) : (c = f.nodes.items[c].next) {
        if (figureAlt(f, c, depth + 1)) |x| return x;
    }
    return null;
}

fn listNumbering(n: *const Node) Numbering {
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
            break :blk .none;
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
        if (title.len == 0 and n.first_child == none) return null;
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
    if (eq(tag, "ul") or eq(tag, "ol")) return .{ .role = .l, .numbering = listNumbering(n) };
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
