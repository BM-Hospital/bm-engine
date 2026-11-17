//! A paged document laid out for drawing (takumi-pdf `PageDrawing::solve` / `stream` / `compose`,
//! `Counted::settle`): the bands measured, the margins resolved around them, the content laid out
//! and paginated until its counters settle, and one `PageBox` + `Window` per page kept by
//! `pageRanges`, each with its header / footer band and, when a repeating `position: fixed` box
//! holds a page counter, that page's own layout of the fixed boxes.
//!
//! Passes (takumi): the bands are measured with the counters of a one-page document, the margins
//! resolved, and the content laid out. Content holding counter hooks lays out again with the numbers
//! the previous pass gave them until they stop changing (`counter_passes` = 3, then once more with
//! the last numbers). Bands that hold a counter or differ per page (dynamic) are measured again with
//! the real page count, and when that moves an `auto` margin the content is laid out again from
//! scratch (`band_passes` = 3).
//!
//! Page geometry: the `size` / `margin` options with the document's `@page`, `:first`, `:left` and
//! `:right` rules over them, and those of the named pages (page_rules.zig), per page: its kind and
//! the name the pagination gave it (the `page` property: page_names.zig; a change of page name
//! breaks the page, fragment.zig).
//!
//! Page widths (takumi `PageStream` / `PageSizer`: each page laid out at its own page area): when
//! every page area has the same width the content lays out once. Otherwise `laySegments` lays it
//! out in runs of pages of one width: a frame at the first page's width shows the pages up to the
//! first page of another width, and the content from where that page starts (`Pages.starts`: a
//! box, or the line a paragraph broke at) is laid out again in a new frame at that width
//! (`layout.fragment.Options.start` / `start_top`, `font.Paragraph.cut`), in the same block
//! coordinates, and so on. The frames are one document (same element model and render nodes):
//! counters (`counters.Seg`), links and anchors (`interactive.Collector.beginRun`), the structure
//! tree and the emitter's neighbouring page passes (`emit.PageBox.frame` / `prev_win` / `next_win`)
//! work across them. A page whose start is not one point (parallel flows broken inside) keeps the
//! width of the run before it.
//!
//! Memory: each layout of the content (`Pass`) has an arena of its own (`Pass.mem`), released as
//! soon as a later pass replaces it, so the counter and band passes of a long document hold one
//! layout at a time; the last one is the `Document`'s, released once the file is written
//! (`Document.release`). What a pass hands on to the next (the hooks' texts, which hooks sit in a
//! fixed box) is copied into the call's arena.
const std = @import("std");
const rt = @import("../render.zig");
const json = @import("../json.zig");
const style = @import("../style/style.zig");
const opt = @import("options.zig");
const emit = @import("emit.zig");
const bands = @import("bands.zig");
const counters = @import("counters.zig");
const layout = @import("../layout/layout.zig");
const page_rules = @import("page_rules.zig");
const bump = @import("../bump.zig");
const memtrace = @import("../memtrace.zig");
const chunks = @import("chunks.zig");

const Allocator = std.mem.Allocator;
const Frame = rt.Frame;
const Seg = counters.Seg;
const Error = rt.Error;

const counter_passes = 3;
const band_passes = 3;

/// The pages of a paged document, ready for `emit.writeDocument`.
pub const Document = struct {
    frame: *Frame,
    pages: []const emit.PageBox,
    windows: []const emit.Window,
    /// the document's page count before `pageRanges` (counters number over it)
    count: usize,
    /// the memory of the content's layout (`Pass.mem`): `frame` and the pages' frames, repeats and
    /// fixed boxes live in it until `release`
    mem: *bump.Bump,
    /// a first layout whose root changed the page rules this one was made with (`layOut`), kept as
    /// long as this one
    prev: ?*bump.Bump = null,

    /// Frees the content's layout (after the file is written: nothing may use the document then).
    pub fn release(d: *const Document, r: *rt.Renderer) void {
        freeMem(r, d.mem);
        if (d.prev) |m| freeMem(r, m);
    }
};

/// A new arena for a pass (`Pass.mem`), on the renderer's allocator.
fn newMem(r: *rt.Renderer) Error!*bump.Bump {
    const m = r.gpa.create(bump.Bump) catch return error.OutOfMemory;
    m.* = bump.Bump.init(r.gpa);
    m.release_freed = true;
    return m;
}

fn freeMem(r: *rt.Renderer, m: *bump.Bump) void {
    m.deinit();
    r.gpa.destroy(m);
}

/// One layout of the content, paginated: one frame, or one per run of pages of one width.
pub const Pass = struct {
    /// the first run's frame (every frame has the same element model and render nodes)
    frame: *Frame,
    segs: []const Seg,
    /// the counter hooks met, in document order, and the texts they were laid out with
    hooks: []const counters.Hook,
    texts: []const ?[]const u8,
    /// the repeating `position: fixed` boxes (`emit.repeatingFixed`), as a mask over the nodes, and
    /// which hooks sit inside one
    fixed: []const u32,
    mask: []const bool,
    fixed_hooks: []const bool,
    /// the pass's arena: its frames and everything above that is not `texts`
    mem: *bump.Bump,

    /// Frees the pass (its `texts` are the caller's).
    fn release(p: *const Pass, r: *rt.Renderer) void {
        freeMem(r, p.mem);
    }

    fn pageCount(p: *const Pass) usize {
        var n: usize = 0;
        for (p.segs) |s| n += s.count;
        return n;
    }
};

const Ctx = struct {
    doc: bands.Doc,
    kind: rt.SourceKind,
    source: []const u8,
};

/// The page geometry of each kind of page (`@page`, `:first`, `:left` / `:right`: page_rules.zig)
/// of the unnamed pages and of each named page, each with its margins resolved around the bands and
/// its page area.
const Geo = struct {
    pages: page_rules.Pages,
    /// per page name entry (0 = unnamed, 1 + k = `pages.named[k]`), per `page_rules.Kind`
    margin: []const [3]opt.Rect,
    areas: []const [3][2]f32,
    /// the page names of the frame being paginated (`layout.fragment.PagedState.page_names`)
    names: []const []const u8 = &.{},

    fn resolve(r: *rt.Renderer, a: Allocator, pages: page_rules.Pages, header: ?f32, footer: ?f32) Error!Geo {
        const n = 1 + pages.named.len;
        const margin = try a.alloc([3]opt.Rect, n);
        const areas = try a.alloc([3][2]f32, n);
        for (0..n) |e| {
            const kinds: [3]opt.Page = if (e == 0) .{ pages.first, pages.left, pages.right } else .{ pages.named[e - 1].first, pages.named[e - 1].left, pages.named[e - 1].right };
            for (kinds, 0..) |p, k| {
                margin[e][k] = p.resolveMargins(header, footer);
                const ar = p.contentSize(margin[e][k]) orelse return invalidPage(r);
                areas[e][k] = .{ ar.width, ar.height };
            }
        }
        return .{ .pages = pages, .margin = margin, .areas = areas };
    }

    /// The name of page name id `id` of the frame (null: unnamed).
    fn nameOf(g: *const Geo, id: u32) ?[]const u8 {
        return if (id >= 1 and id <= g.names.len) g.names[id - 1] else null;
    }
    fn entry(g: *const Geo, name: ?[]const u8) usize {
        return if (g.pages.namedIndex(name)) |k| k + 1 else 0;
    }
    fn page(g: *const Geo, i: usize, name: ?[]const u8) opt.Page {
        return g.pages.pageNamed(i, name);
    }
    fn margins(g: *const Geo, i: usize, name: ?[]const u8) opt.Rect {
        return g.margin[g.entry(name)][@backingInt(g.pages.kindOf(i))];
    }
    fn area(g: *const Geo, i: usize, name: ?[]const u8) [2]f32 {
        return g.areas[g.entry(name)][@backingInt(g.pages.kindOf(i))];
    }
    fn sameMargins(g: *const Geo, o: *const Geo) bool {
        if (g.margin.len != o.margin.len or g.pages.rtl != o.pages.rtl) return false;
        for (g.margin, o.margin) |x, y| if (!std.meta.eql(x, y)) return false;
        return true;
    }
    /// every page area as wide as the first page's
    fn uniformWidth(g: *const Geo) bool {
        const w = g.areas[0][0][0];
        for (g.areas) |e| for (e) |ar| if (ar[0] != w) return false;
        return true;
    }
    /// every page area as tall as the first page's
    fn uniformHeight(g: *const Geo) bool {
        const h = g.areas[0][0][1];
        for (g.areas) |e| for (e) |ar| if (ar[1] != h) return false;
        return true;
    }
    /// `layout.fragment.PageHeightFn`: page `i`'s area height, a page named `name`
    fn heightOf(ctx: *anyopaque, i: u32, name: u32) f32 {
        const g: *const Geo = @ptrCast(@alignCast(ctx));
        return g.area(i, g.nameOf(name))[1];
    }
};

/// One layout of the content, paginated, in an arena of its own (`Pass.mem`). `texts` and
/// `fixed_hooks` (the previous pass's findings) must not live in a pass's arena that is released
/// before this pass is.
fn layPass(cx: *const Ctx, geo: *const Geo, texts: []const ?[]const u8, fixed_hooks: []const bool) Error!Pass {
    const mem = try newMem(cx.doc.r);
    errdefer freeMem(cx.doc.r, mem);
    const a = mem.allocator();
    var subst: counters.Subst = .{ .a = a, .mode = .{ .flow = .{ .texts = texts, .fixed = fixed_hooks } } };
    const g = try a.create(Geo);
    g.* = geo.*;
    var segs: std.ArrayList(Seg) = .empty;
    if (geo.uniformWidth()) {
        // (every page as wide: one layout, paginated)
        const f = try bands.buildFrame(cx.doc.r, a, cx.doc.o, cx.doc.css, cx.kind, cx.source, null, geo.area(0, null), &subst);
        g.names = f.tree.paged.page_names;
        const varies = !geo.uniformHeight();
        const pages = try f.paginate(.{ .page_height = geo.area(0, null)[1], .page_height_fn = if (varies) Geo.heightOf else null, .ctx = @ptrCast(g) });
        try segs.append(a, .{ .frame = f, .first = 0, .local0 = 0, .count = @intCast(pages.pages.len) });
        memtrace.mark("pass: paginated");
    } else try laySegments(cx, a, g, &subst, &segs);
    // (laid out and paginated: the layout is only read from now on)
    for (segs.items) |s| s.frame.tree.dropCaches();
    memtrace.mark("pass: caches dropped");
    const f = segs.items[0].frame;
    const fixed = try emit.repeatingFixed(a, f);
    const mask = try counters.fixedMask(a, f, fixed);
    const hooks = try a.dupe(counters.Hook, subst.hooks.items);
    return .{
        .frame = f,
        .segs = segs.items,
        .hooks = hooks,
        .texts = texts,
        .fixed = fixed,
        .mask = mask,
        .fixed_hooks = try counters.fixedHooks(a, f, hooks, mask),
        .mem = mem,
    };
}

/// The page area heights of a run of pages laid out at one width: page `i` of its frame is page
/// `base + i - fake` of the document (`fake`: page 0 holds what earlier runs show).
const SegCtx = struct {
    g: *const Geo,
    base: u32,
    fake: u32,

    fn height(ctx: *anyopaque, i: u32, name: u32) f32 {
        const c: *const SegCtx = @ptrCast(@alignCast(ctx));
        return c.g.area(c.base + (i -| c.fake), c.g.nameOf(name))[1];
    }
};

/// The pages of the content when page areas differ in width (takumi lays each page out at its own
/// width, `PageStream` / `PageSizer`): a frame laid out at the first page's width shows the pages
/// up to the first page of another width; the content from that page's start (`Pages.starts`: a
/// box, or the line a paragraph broke at) is laid out again at that width, from that point
/// (`layout.fragment.Options.start`; a paragraph broken between lines is broken there again and
/// the rest wraps at the new width: `font.Paragraph.cut`), and so on. The frames are of one
/// document (same element model, same render nodes), so counters, links, anchors and the
/// structure tree work across them. A page whose start is not one point (parallel flows broken
/// inside) keeps the width of the run before it.
fn laySegments(cx: *const Ctx, a: Allocator, g: *Geo, subst: *counters.Subst, segs: *std.ArrayList(Seg)) Error!void {
    const no_node = layout.fragment.Start{};
    var width = g.area(0, null)[0];
    var base: u32 = 0;
    var start: ?layout.fragment.Start = null;
    var cuts: []const bands.Cut = &.{};
    var row_minimums: []const layout.fragment.RowMinimum = &.{};
    var float_shifts: []const f32 = &.{};
    var float_extents: []const f32 = &.{};
    var assigned_rows: []const layout.fragment.RowMinimum = &.{};
    var rows_recorded = false;
    var start_top: f32 = 0;
    var retried = false;
    while (true) {
        const f = try bands.buildFrameCuts(cx.doc.r, a, cx.doc.o, cx.doc.css, cx.kind, cx.source, null, .{ width, g.area(base, null)[1] }, subst, cuts, row_minimums, float_shifts, float_extents);
        g.names = f.tree.paged.page_names;
        if (segs.items.len > 0 and !sameNodes(segs.items[0].frame, f)) return extendLast(segs);
        if (start) |*s| {
            if (s.branches.len > 0) {
                const points = try a.dupe(layout.fragment.ResumePoint, s.branches);
                for (points) |*p| {
                    if (p.finished or p.line == no_node.line) continue;
                    for (cuts) |c| if (c.node == f.lid_node.items[p.node]) {
                        p.line = lineStarting(f, c.node, c.glyph) orelse return extendLast(segs);
                        break;
                    };
                }
                s.branches = points;
            } else if (s.line != no_node.line) {
                for (cuts) |cut| if (cut.node == f.lid_node.items[s.node]) {
                    s.line = lineStarting(f, cut.node, cut.glyph) orelse return extendLast(segs);
                    break;
                };
            }
            const side = try a.dupe(layout.fragment.ResumePoint, s.side_flows);
            for (side) |*point| {
                if (point.finished or point.line == no_node.line) continue;
                for (cuts) |cut| if (cut.node == f.lid_node.items[point.node]) {
                    point.line = lineStarting(f, cut.node, cut.glyph) orelse return extendLast(segs);
                    break;
                };
            }
            s.side_flows = side;
        }
        const sc = try a.create(SegCtx);
        sc.* = .{ .g = g, .base = base, .fake = @intFromBool(start != null) };
        var assigned: std.ArrayList(layout.fragment.RowMinimum) = .empty;
        if (!rows_recorded) for (f.tree.table_geoms.items) |table| {
            const spanning = for (table.cells) |cell| {
                if (cell.rowspan > 1) break true;
            } else false;
            if (!spanning) continue;
            for (table.rows) |row| if (row.node != no_node.node) try assigned.append(a, .{ .node = row.node, .height = row.h });
        };
        const pages = try f.paginate(.{ .page_height = g.area(base, null)[1], .page_height_fn = SegCtx.height, .ctx = @ptrCast(sc), .start = start, .start_top = if (start != null) start_top else null, .record_starts = true, .max_pages = max_pages + 1 });
        // (page 1 must start where the run before stopped, else the run before goes on)
        if (start) |s| if (pages.start_page == 0 or pages.pages.len < 2 or !sameStart(pages.starts[1], s)) {
            return extendLast(segs);
        };
        const fake = pages.start_page;
        // (the first run is as wide as the first page, which may be a named page)
        if (base == 0 and !retried) {
            retried = true;
            const w0 = g.area(0, g.nameOf(pages.names[0]))[0];
            if (w0 != width) {
                width = w0;
                continue;
            }
        }
        if (!rows_recorded) {
            assigned_rows = try assigned.toOwnedSlice(a);
            rows_recorded = true;
        }
        var stop: ?u32 = null;
        var i: u32 = fake + 1;
        while (i < pages.pages.len) : (i += 1) {
            const candidate_width = g.area(base + i - fake, g.nameOf(pages.names[i]))[0];
            if (candidate_width == width) continue;
            const tok = pages.starts[i];
            // A rowspan may be the only flow left on this page boundary: the main-flow token has
            // no node, while the spanning cell's paragraphs continue independently in side_flows.
            if (tok.node == no_node.node and tok.side_flows.len == 0) continue;
            if (tok.line != no_node.line and lineGlyph(f, tok.node, tok.line) == null) continue;
            stop = i;
            break;
        }
        const end: u32 = stop orelse @intCast(pages.pages.len);
        try segs.append(a, .{ .frame = f, .first = base, .local0 = fake, .count = end - fake });
        if (base + end - fake > max_pages) {
            cx.doc.r.setErr(too_many_pages, "");
            return error.Invalid;
        }
        const s_i = stop orelse return;
        var tok = pages.starts[s_i];
        // (a row broken inside whose cells' content ends on the run's last page: their fragments
        // reach past it by their block-end decorations, which the row's rest no longer holds)
        if (tok.branches.len > 0 and tok.row_height > 0 and s_i > 0) {
            var ext: std.ArrayList(layout.fragment.Extend) = .empty;
            const cut = try cellOverflow(a, f, pages.pages, tok.node, pages.pages[s_i - 1].top, pages.pages[s_i].top, &ext);
            if (ext.items.len > 0) {
                tok.row_height -= cut;
                segs.items[segs.items.len - 1].extends = ext.items;
            }
        }
        width = g.area(base + s_i - fake, g.nameOf(pages.names[s_i]))[0];
        base += s_i - fake;
        // (the run goes on where this one's pages end, in the same block coordinates: takumi's
        // pages stack in one space)
        start_top = pages.pages[s_i].top;
        start = tok;
        float_shifts = f.tree.paged.float_shifts;
        float_extents = f.tree.paged.float_extents;
        var rows: std.ArrayList(layout.fragment.RowMinimum) = .empty;
        try rows.appendSlice(a, assigned_rows);
        for (f.tree.table_geoms.items) |table| for (table.rows) |row| {
            for (assigned_rows) |minimum| {
                if (row.node != minimum.node) continue;
                var absolute_top: f32 = 0;
                var ancestor = row.node;
                while (ancestor < f.tree.nodes.items.len) : (ancestor = f.tree.nodes.items[ancestor].parent) absolute_top += f.tree.layout(ancestor).y;
                if (absolute_top <= start_top + 1.0 / 64.0) try rows.append(a, .{ .node = row.node, .height = minimum.height, .top = row.y });
                break;
            }
        };
        if (tok.branches.len > 0 and tok.row_height > 0) {
            try rows.append(a, .{ .node = tok.node, .height = tok.row_height });
        }
        row_minimums = try rows.toOwnedSlice(a);
        var next_cuts: std.ArrayList(bands.Cut) = .empty;
        if (tok.branches.len > 0) {
            for (tok.branches) |p| {
                if (p.finished) {
                    const node = f.lid_node.items[p.node];
                    if (f.nodes.items[node].para) |para| if (para.glyphs.len > 0) {
                        try next_cuts.append(a, .{ .node = node, .glyph = @intCast(para.glyphs.len) });
                    };
                    continue;
                }
                if (p.line == no_node.line) continue;
                const glyph = lineGlyph(f, p.node, p.line) orelse return extendLast(segs);
                try next_cuts.append(a, .{ .node = f.lid_node.items[p.node], .glyph = glyph });
            }
        } else if (tok.line != no_node.line) try next_cuts.append(a, .{ .node = f.lid_node.items[tok.node], .glyph = lineGlyph(f, tok.node, tok.line).? });
        for (tok.side_flows) |point| {
            const id = f.lid_node.items[point.node];
            if (point.finished) {
                if (f.nodes.items[id].para) |paragraph| try next_cuts.append(a, .{ .node = id, .glyph = @intCast(paragraph.glyphs.len) });
            } else if (point.line != no_node.line) {
                const glyph = lineGlyph(f, point.node, point.line) orelse return extendLast(segs);
                try next_cuts.append(a, .{ .node = id, .glyph = glyph });
            }
        }
        cuts = next_cuts.items;
    }
}

/// takumi lays a table cell out at its row's block size and never breaks before its block-end
/// border and padding (`should_prevent_break_before_block_end_decorations`): a cell whose content
/// ends on the page that ends at `at` (and starts at `top`) takes `max(space left, intrinsic block
/// size)` of it (Blink `FinishFragmentation`), so its fragment reaches past `at` by the decorations
/// that do not fit, as do its row's fragment (its largest cell's) and the boxes around the row
/// that `at` cuts; the row consumes that much more of its block size, the rest of it starts at the
/// next page all the same. Fills `out` with those fragments, the outermost box first and the cells
/// last (their paint order), and returns how much less of the row's block size is left past `at`
/// (0: nothing reaches past it, `out` unchanged): the row's fragment on the last page it reaches
/// (`pages`: the frame's) still holds its finished cells' block-end decorations (a finished cell's
/// fragment is at least as tall as them, and the row grows to it). Not for a row that ends there,
/// a collapsed-border table (the table draws its cells' borders) or a cell laid out as one text leaf.
fn cellOverflow(a: Allocator, f: *const Frame, pages: []const layout.fragment.Page, row: u32, top: f32, at: f32, out: *std.ArrayList(layout.fragment.Extend)) Error!f32 {
    const t = &f.tree;
    const eps = 1.0 / 64.0;
    const depth = layout.max_depth + 8;
    var anc = t.nodes.items[row].parent;
    var guard: u32 = 0;
    while (anc < t.nodes.items.len and guard < depth) : (guard += 1) {
        if (t.tableGeom(anc)) |tg| {
            if (tg.collapse) return 0;
            break;
        }
        if (anc == f.lroot) break;
        anc = t.nodes.items[anc].parent;
    }
    const row_top = absTop(f, row);
    var cells: std.ArrayList(layout.fragment.Extend) = .empty;
    var over: f32 = 0;
    var tail: f32 = 0;
    var c = t.nodes.items[row].first_child;
    while (c != rt.none) : (c = t.nodes.items[c].next_sibling) {
        const s = t.nodes.items[c].style;
        if (s.display == .none or s.position.isOut()) continue;
        if (t.nodes.items[c].measured) continue;
        const cl = t.layout(c);
        const cell_top = row_top + cl.y;
        // (a cell is a formatting context: its content's block-end margins stay in it)
        var content_end = cell_top + cl.border.top + cl.padding.top;
        var k = t.nodes.items[c].first_child;
        while (k != rt.none) : (k = t.nodes.items[k].next_sibling) {
            const ks = t.nodes.items[k].style;
            if (ks.display == .none or ks.position.isOut()) continue;
            const kl = t.layout(k);
            content_end = @max(content_end, cell_top + kl.y + kl.h + kl.margin.bottom);
        }
        // (content broken inside: the block-end decorations go with its rest)
        if (content_end > at + eps) continue;
        tail = @max(tail, cl.border.bottom + cl.padding.bottom);
        const reach = @min(@max(content_end, top) + cl.border.bottom + cl.padding.bottom, cell_top + cl.h);
        if (!(reach > at + eps)) continue;
        try cells.append(a, .{ .node = c, .at = at, .bottom = reach });
        over = @max(over, reach - at);
    }
    const row_bottom = row_top + t.layout(row).h;
    if (over == 0 or !(row_bottom > at + over + eps)) return 0;
    var bottom = row_bottom - over;
    var last_top = at;
    for (pages) |p| if (p.top > last_top and p.top < bottom - eps) {
        last_top = p.top;
    };
    bottom = @min(row_bottom, @max(bottom, last_top + tail));
    const mark = out.items.len;
    var n = row;
    guard = 0;
    while (n < t.nodes.items.len and guard < depth) : (guard += 1) {
        const nt = absTop(f, n);
        if (nt < at and nt + t.layout(n).h > at) try out.append(a, .{ .node = n, .at = at, .bottom = at + over });
        if (n == f.lroot) break;
        n = t.nodes.items[n].parent;
    }
    std.mem.reverse(layout.fragment.Extend, out.items[mark..]);
    try out.appendSlice(a, cells.items);
    return row_bottom - bottom;
}

/// Block offset of layout node `n`'s border box in the frame's stitched space.
fn absTop(f: *const Frame, n: u32) f32 {
    var y: f32 = 0;
    var cur = n;
    var guard: u32 = 0;
    while (cur < f.tree.nodes.items.len and guard < layout.max_depth + 8) : (guard += 1) {
        y += f.tree.layout(cur).y;
        if (cur == f.lroot) break;
        cur = f.tree.nodes.items[cur].parent;
    }
    return y;
}

fn sameStart(a: layout.fragment.Start, b: layout.fragment.Start) bool {
    if (a.node != b.node or a.line != b.line or a.forced != b.forced or a.branches.len != b.branches.len or a.side_flows.len != b.side_flows.len) return false;
    for (a.branches, b.branches) |x, y| if (!std.meta.eql(x, y)) return false;
    for (a.side_flows, b.side_flows) |x, y| if (!std.meta.eql(x, y)) return false;
    return true;
}

const max_pages = 20_000;
/// takumi-pdf `PdfError::TooManyPages`
const too_many_pages = "The content spans more than 20000 pages. Give it a height that resolves.";

/// The frame of the last run shows the rest of the document (a run that could not be laid out
/// again at its width).
fn extendLast(segs: *std.ArrayList(Seg)) void {
    const last = &segs.items[segs.items.len - 1];
    const pages = last.frame.paginated().?;
    last.count = @intCast(pages.pages.len - last.local0);
}

/// Two frames of the same document with the same render and layout nodes.
fn sameNodes(x: *const Frame, y: *const Frame) bool {
    return x.nodes.items.len == y.nodes.items.len and x.tree.nodes.items.len == y.tree.nodes.items.len and x.dom.els.items.len == y.dom.els.items.len;
}

/// The paragraph glyph line `line` of layout node `lid` starts at (null: the first line or none).
fn lineGlyph(f: *const Frame, lid: u32, line: u32) ?u32 {
    if (line == 0 or lid >= f.lid_node.items.len) return null;
    const id = f.lid_node.items[lid];
    if (id >= f.nodes.items.len) return null;
    const tl = f.nodes.items[id].tl orelse return null;
    if (line >= tl.lines.len) return null;
    const gl = tl.lines[line].start;
    return if (gl == 0) null else gl;
}

/// The line of render node `id`'s paragraph that starts at glyph `glyph`.
fn lineStarting(f: *Frame, id: u32, glyph: u32) ?u32 {
    if (id >= f.nodes.items.len) return null;
    const n = &f.nodes.items[id];
    if (n.para == null or n.lid == rt.none) return null;
    const l = f.tree.layout(n.lid);
    const cw = l.w - l.border.left - l.border.right - l.padding.left - l.padding.right;
    const tl = (f.textLayout(id, cw) catch return null) orelse return null;
    for (tl.lines, 0..) |ln, k| if (ln.start == glyph) return @intCast(k);
    return null;
}

/// takumi `Counted::settle`: lays the content out until the numbers its hooks receive stop moving.
/// A pass that is laid out again is released first (one layout in memory at a time).
fn settle(cx: *const Ctx, geo: *const Geo) Error!Pass {
    const a = cx.doc.a;
    const r = cx.doc.r;
    var pass = try layPass(cx, geo, &.{}, &.{});
    if (pass.hooks.len == 0) return pass;
    // (`pass` holds an arena)
    var live = true;
    errdefer if (live) pass.release(r);
    // the first pass was laid out with every hook as written
    const as_written = try a.alloc(?[]const u8, pass.hooks.len);
    @memset(as_written, null);
    var used: []const ?[]const u8 = as_written;
    var k: usize = 0;
    while (k < counter_passes) : (k += 1) {
        if (k > 0) {
            const fixed_hooks = try a.dupe(bool, pass.fixed_hooks);
            pass.release(r);
            live = false;
            pass = try layPass(cx, geo, used, fixed_hooks);
            live = true;
        }
        const texts = try counters.flowTexts(a, pass.segs, pass.hooks, pass.fixed_hooks, pass.mask);
        // the pass was laid out with the numbers it gives
        if (counters.sameTexts(texts, used)) return pass;
        used = texts;
    }
    // still moving after the last pass allowed: laid out once more, so the pages show the numbers
    // they were laid out with
    const fixed_hooks = try a.dupe(bool, pass.fixed_hooks);
    pass.release(r);
    live = false;
    return layPass(cx, geo, used, fixed_hooks);
}

fn invalidPage(r: *rt.Renderer) Error {
    r.setErr("Page size must be finite and larger than zero", "");
    return error.Invalid;
}

fn same(x: ?f32, y: ?f32) bool {
    if (x == null or y == null) return x == null and y == null;
    return x.? == y.?;
}

fn heights(s: ?bands.Slot) ?f32 {
    return if (s) |x| x.height else null;
}

/// The options' page with the document's `@page` rules applied (page_rules.zig), `cx` the root
/// element's context.
pub fn pageRules(a: Allocator, o: opt.PdfOptions, kind: rt.SourceKind, source: []const u8, p: opt.Page, cx: page_rules.Context) Error!page_rules.Pages {
    var c = cx;
    c.supports = rt.Frame.cssSupports;
    return page_rules.resolve(a, p, o.css, if (kind == .html) source else null, c);
}

/// takumi `PageContext`: what the page rules take from the root element of a laid-out frame.
pub fn rootContext(f: *const Frame) page_rules.Context {
    // (takumi's tree root of a whole HTML document is its body; several top-level nodes of a
    // fragment sit in a wrapper whose custom properties takumi does not read)
    var id = f.root;
    var props = true;
    const el = f.nodes.items[id].el;
    if (el != rt.none) {
        const tag = f.dom.at(el).tag;
        if (std.ascii.eqlIgnoreCase(tag, "html")) {
            for (f.nodes.items, 0..) |n, k| {
                if (n.parent == f.root and n.el != rt.none and std.ascii.eqlIgnoreCase(f.dom.at(n.el).tag, "body")) {
                    id = @intCast(k);
                    break;
                }
            }
        } else if (tag.len == 0) props = false;
    }
    const cs = f.nodes.items[id].cs;
    var ex: f32 = 0.5;
    var ch: f32 = 0.5;
    var font_ids: [64]@import("../font/collection.zig").FaceId = undefined;
    const matched = f.r.fonts.match(cs.font_family, cs.font_weight, cs.font_style != .normal, &font_ids);
    if (matched.len > 0) {
        const face = f.r.fonts.font(matched[0]);
        const upem = @max(face.unitsPerEm(), 1);
        const xh = face.xHeight();
        if (xh > 0) ex = @as(f32, @floatFromInt(xh)) / @as(f32, @floatFromInt(upem));
        ch = @as(f32, @floatFromInt(face.advanceWidth(face.glyphIndex('0')))) / @as(f32, @floatFromInt(upem));
    }
    const Get = struct {
        fn custom(ctx: *const anyopaque, name: []const u8) ?[]const u8 {
            const c: *const style.ComputedStyle = @ptrCast(@alignCast(ctx));
            return c.customProperty(name);
        }
    };
    return .{ .rtl = cs.direction == .rtl, .font_size = cs.font_size, .rem = f.nodes.items[f.root].cs.font_size, .ex = ex, .ch = ch, .ctx = @ptrCast(cs), .custom = if (props) Get.custom else null };
}

/// Lays the paged document `o_in` (geometry `p_in`) out: `@page` rules, bands, margins, the content
/// with its counters settled, and the kept pages. Page rules that depend on the root element (its
/// direction, font size, custom properties) are resolved again from the laid-out root, and the
/// document laid out again when that changes them.
pub fn layOut(r: *rt.Renderer, a: Allocator, o_in: opt.PdfOptions, css: ?json.Value, kind: rt.SourceKind, source: []const u8, p_in: opt.Page, background: ?style.Color) Error!Document {
    const rules = try pageRules(a, o_in, kind, source, p_in, .{});
    const doc = try layOutRules(r, a, o_in, css, kind, source, rules, background);
    if (!rules.contextual) return doc;
    const again = pageRules(a, o_in, kind, source, p_in, rootContext(doc.frame)) catch |e| {
        doc.release(r);
        return e;
    };
    if (std.meta.eql(again.first, rules.first) and std.meta.eql(again.left, rules.left) and std.meta.eql(again.right, rules.right) and again.rtl == rules.rtl) return doc;
    // (the first layout lives as long as the second: the rules may refer to its root)
    errdefer doc.release(r);
    var second = try layOutRules(r, a, o_in, css, kind, source, again, background);
    second.prev = doc.mem;
    return second;
}

fn layOutRules(r: *rt.Renderer, a: Allocator, o_in: opt.PdfOptions, css: ?json.Value, kind: rt.SourceKind, source: []const u8, rules: page_rules.Pages, background: ?style.Color) Error!Document {
    var o = o_in;
    o.geometry = .{ .page = rules.rest };
    const cx: Ctx = .{ .doc = .{ .r = r, .a = a, .o = o, .css = css }, .kind = kind, .source = source };
    var header = try bands.Slot.init(a, o, true);
    var footer = try bands.Slot.init(a, o, false);
    // Bands lay out at full page width and draw inside the margin areas, like Chromium's print
    // header and footer templates; measured first with a one-page document's counters.
    if (header) |*s| try bands.measure(&cx.doc, s, 1);
    if (footer) |*s| try bands.measure(&cx.doc, s, 1);
    var geo = try Geo.resolve(r, a, rules, heights(header), heights(footer));
    var content = try settle(&cx, &geo);
    // (`content` holds an arena: the document's, or released when the content is laid out again)
    var live = true;
    errdefer if (live) content.release(r);

    // A counter band and the page count depend on each other, so the band is measured again until
    // its height settles; only a margin that follows a band can move the content.
    const dynamic = (if (header) |s| s.dynamic else false) or (if (footer) |s| s.dynamic else false);
    if (dynamic) {
        var follows = rules.first.margin.followBands() or rules.left.margin.followBands() or rules.right.margin.followBands();
        for (rules.named) |e| follows = follows or e.first.margin.followBands() or e.left.margin.followBands() or e.right.margin.followBands();
        var k: usize = 0;
        while (k < band_passes) : (k += 1) {
            const before = .{ heights(header), heights(footer) };
            const n = content.pageCount();
            if (header) |*s| try bands.measure(&cx.doc, s, n);
            if (footer) |*s| try bands.measure(&cx.doc, s, n);
            if (same(before[0], heights(header)) and same(before[1], heights(footer))) break;
            const geo2 = try Geo.resolve(r, a, rules, heights(header), heights(footer));
            if (geo.sameMargins(&geo2)) break;
            if (!follows) break;
            geo = geo2;
            content.release(r);
            live = false;
            content = try settle(&cx, &geo);
            live = true;
        }
    }

    const n = content.pageCount();
    geo.names = content.frame.tree.paged.page_names;
    // fixed boxes holding a page counter lay out again per page (takumi `FixedTemplate`)
    var fixed_counters = false;
    for (content.hooks, content.fixed_hooks) |h, fx| {
        if (fx and h.kind != .target) fixed_counters = true;
    }
    memtrace.mark("paged: content settled");
    var sel = opt.PageSelection.init(o.page_ranges);
    // (the bands of a single page are laid out when it is drawn, from this copy)
    const band_doc = try a.create(bands.Doc);
    band_doc.* = cx.doc;
    var pages: std.ArrayList(emit.PageBox) = .empty;
    var windows: std.ArrayList(emit.Window) = .empty;
    var i: usize = 0;
    var seg_i: usize = 0;
    while (i < n) : (i += 1) {
        const kept = try sel.pushPage(a);
        if (kept == null) continue;
        // (the run of pages laid out at this page's width, and this page in its frame)
        while (seg_i + 1 < content.segs.len and i >= content.segs[seg_i + 1].first) seg_i += 1;
        const sg = content.segs[seg_i];
        const paged = sg.frame.paginated().?;
        const local: usize = sg.local0 + (i - sg.first);
        const pg = paged.pages[local];
        const name = geo.nameOf(if (local < paged.names.len) paged.names[local] else 0);
        const pp = geo.page(i, name);
        const m = geo.margins(i, name);
        const area = geo.area(i, name);
        var box: emit.PageBox = .{
            .width = pp.width,
            .height = pp.height,
            .content = .{ .x = m.left, .y = m.top, .w = area[0], .h = area[1] },
            .background = background,
            .clip = true,
            .repeats = paged.repeatsOf(@intCast(local)),
            .fixed = content.fixed,
            .frame = if (seg_i > 0) sg.frame else null,
        };
        if (content.segs.len > 1) {
            // (the frame's own neighbouring pages, where the document's show another frame)
            const own = struct {
                fn win(p: layout.fragment.Page) emit.Window {
                    return .{ .top = p.top, .bottom = p.top + p.height, .lines_top = p.top, .lines_bottom = p.top + p.height };
                }
            };
            if (i == sg.first and local > 0) box.prev_win = own.win(paged.pages[local - 1]);
            if (i + 1 == sg.first + sg.count and seg_i + 1 < content.segs.len and local + 1 < paged.pages.len) box.next_win = own.win(paged.pages[local + 1]);
            // (fragments of the page before, laid out in the run before, that reach this page)
            if (i + 1 == sg.first + sg.count and seg_i + 1 < content.segs.len) box.extends = sg.extends;
            // (the next run's first page, in the same block coordinates: what reaches up here)
            if (i + 1 == sg.first + sg.count and seg_i + 1 < content.segs.len) {
                const nx = content.segs[seg_i + 1];
                const nx_pages = nx.frame.paginated().?;
                if (nx.first == i + 1 and nx.local0 < nx_pages.pages.len) {
                    box.under_frame = nx.frame;
                    box.under_win = own.win(nx_pages.pages[nx.local0]);
                }
            }
            if (i == sg.first and seg_i > 0) {
                const pv = content.segs[seg_i - 1];
                const pv_pages = pv.frame.paginated().?;
                if (pv.extends.len > 0 and pv.first + pv.count == i and pv.local0 + pv.count >= 1 and pv.local0 + pv.count - 1 < pv_pages.pages.len) {
                    box.over_frame = pv.frame;
                    box.over_extends = pv.extends;
                    box.over_win = own.win(pv_pages.pages[pv.local0 + pv.count - 1]);
                }
            }
        }
        if (header) |*s| box.header = try bands.forPage(band_doc, s, i, n, pp.width, pp.height);
        if (footer) |*s| box.footer = try bands.forPage(band_doc, s, i, n, pp.width, pp.height);
        if (fixed_counters) {
            var subst: counters.Subst = .{ .a = a, .mode = .{ .flow = .{ .texts = content.texts, .fixed = content.fixed_hooks, .page = i + 1, .pages = n } } };
            const ff = try bands.buildFrame(r, a, o, css, kind, source, null, .{ area[0], geo.area(0, null)[1] }, &subst);
            box.fixed = try emit.repeatingFixed(a, ff);
            box.fixed_frame = ff;
        }
        try pages.append(a, box);
        // takumi `PageSlice::lines`: the first page also owns the lines above it, the last the
        // lines below it
        try windows.append(a, .{
            .top = pg.top,
            .bottom = pg.top + pg.height,
            .lines_top = if (i == 0) -std.math.inf(f32) else pg.top,
            .lines_bottom = if (i + 1 == n) std.math.inf(f32) else pg.top + pg.height,
        });
    }
    var diag: opt.Diag = .{};
    sel.finish(&diag) catch {
        r.setErr(diag.message(), "");
        return error.Invalid;
    };
    return .{ .frame = content.frame, .pages = pages.items, .windows = windows.items, .count = n, .mem = content.mem };
}

/// The page area heights of a part of the document (chunks.zig) whose first page is page `base`.
const PartHeights = struct {
    g: *const Geo,
    /// the document page index of the frame's page 0 (may be before the document's first page:
    /// the part before's pages, laid out with this one, are not drawn)
    base: i64,

    fn height(ctx: *anyopaque, i: u32, name: u32) f32 {
        const c: *const PartHeights = @ptrCast(@alignCast(ctx));
        const gi: usize = @intCast(@max(0, c.base + @as(i64, i)));
        return c.g.area(gi, c.g.nameOf(name))[1];
    }
};

/// A part of the document laid out (chunks.zig): its frame and the frame's pages that are the
/// part's, [`s`, `e`) (the pages before / after hold the children of the parts around it).
const LaidPart = struct {
    f: *Frame,
    s: u32,
    e: u32,
    /// the render node of the flow (`tags.Skip.parent`)
    flow: u32,
};

/// The top of source element `el`'s box in frame `f` (laid out and paginated), null: no box.
fn elementTop(f: *const Frame, el: u32) ?f32 {
    for (f.nodes.items) |n| {
        if (n.el != el or n.kind != .container or n.lid == rt.none) continue;
        var y = f.tree.layout(n.lid).y;
        var parent = f.tree.nodes.items[n.lid].parent;
        var guard: u32 = 0;
        while (parent < f.tree.nodes.items.len and guard < 4096) : (guard += 1) {
            y += f.tree.layout(parent).y;
            parent = f.tree.nodes.items[parent].parent;
        }
        return y;
    }
    return null;
}

fn nodeOfElement(f: *const Frame, el: u32) u32 {
    for (f.nodes.items, 0..) |n, k| if (n.el == el and n.kind == .container) return @intCast(k);
    return rt.none;
}

/// Null, after a memory checkpoint naming why the document is not drawn a part at a time.
fn refuse(comptime T: type, comptime why: []const u8) ?T {
    memtrace.mark("chunks: whole: " ++ why);
    return null;
}

/// `rootContext` read from a document's element model and styles (`bands.buildDocument`), as the
/// root render node and its `body` child carry them.
fn docRootContext(doc: *const Frame) page_rules.Context {
    const d = &doc.dom;
    var el = d.root;
    var props = true;
    const tag = d.at(el).tag;
    if (std.ascii.eqlIgnoreCase(tag, "html")) {
        var c = d.at(el).first;
        while (c != rt.none) : (c = d.at(c).next) {
            const ce = d.at(c);
            if (!ce.run and ce.cs.display != .none and std.ascii.eqlIgnoreCase(ce.tag, "body")) {
                el = c;
                break;
            }
        }
    } else if (tag.len == 0) props = false;
    const cs = d.at(el).cs;
    var ex: f32 = 0.5;
    var ch: f32 = 0.5;
    var font_ids: [64]@import("../font/collection.zig").FaceId = undefined;
    const matched = doc.r.fonts.match(cs.font_family, cs.font_weight, cs.font_style != .normal, &font_ids);
    if (matched.len > 0) {
        const face = doc.r.fonts.font(matched[0]);
        const upem = @max(face.unitsPerEm(), 1);
        const xh = face.xHeight();
        if (xh > 0) ex = @as(f32, @floatFromInt(xh)) / @as(f32, @floatFromInt(upem));
        ch = @as(f32, @floatFromInt(face.advanceWidth(face.glyphIndex('0')))) / @as(f32, @floatFromInt(upem));
    }
    const Get = struct {
        fn custom(ctx: *const anyopaque, name: []const u8) ?[]const u8 {
            const c: *const style.ComputedStyle = @ptrCast(@alignCast(ctx));
            return c.customProperty(name);
        }
    };
    return .{ .rtl = cs.direction == .rtl, .font_size = cs.font_size, .rem = d.at(d.root).cs.font_size, .ex = ex, .ch = ch, .ctx = @ptrCast(cs), .custom = if (props) Get.custom else null };
}

/// How far below a page's top a box may be computed and still start that page (`layPart`).
const seam_eps: f32 = 1.0 / 16.0;

/// Where the part before's last child, the first child a part's frame lays out, is in the
/// document: its top, and the document page it starts on (index and top).
const Seam = struct { y: f32, page: usize, top: f32 };

/// Part `k` of `doc`'s document laid out in `a` and paginated, its pages and boxes where the whole
/// document has them: the frame's first child (the part before's last one) at `seam`. Null: its
/// pages cannot be told apart from its neighbours'.
fn layPart(a: Allocator, doc: *const Frame, plan: chunks.Plan, k: usize, geo: *const Geo, seam: ?Seam, blank: bool) Error!?LaidPart {
    const pt = plan.parts[k];
    const f = try a.create(Frame);
    f.* = try Frame.initChunk(doc, a);
    f.tree.paged.chunk = .{ .parent = plan.parent, .lo = pt.lo, .hi = pt.hi };
    try f.prepareLayout();
    try @import("text.zig").requireFont(f, blank);
    var base: i64 = 0;
    var origin: f32 = 0;
    var shift: f32 = 0;
    if (seam) |sm| {
        const y0 = elementTop(f, pt.prev) orelse return refuse(LaidPart, "no seam box");
        base = @intCast(sm.page);
        origin = sm.top;
        shift = sm.y - y0;
    }
    const hc = try a.create(PartHeights);
    hc.* = .{ .g = geo, .base = base };
    const first_h = geo.area(@intCast(base), null)[1];
    const pages = try f.paginate(.{ .page_height = first_h, .page_height_fn = if (geo.uniformHeight()) null else PartHeights.height, .ctx = @ptrCast(hc), .origin = origin, .root_shift = shift });
    f.tree.dropCaches();
    // the part's pages: from the page its first child starts on to the page the next part's
    // first child starts on
    var s: u32 = 0;
    // (a box a forced break starts a page with sits at the page's top, give or take the rounding
    // of the sums that place it)
    if (pt.prev != rt.none) s = pages.pageAt((elementTop(f, pt.own_lo) orelse return refuse(LaidPart, "no first box")) + seam_eps);
    var e: u32 = @intCast(pages.pages.len);
    if (pt.next != rt.none) e = pages.pageAt((elementTop(f, pt.next) orelse return refuse(LaidPart, "no next box")) + seam_eps);
    if (pt.prev != rt.none and s == 0) return refuse(LaidPart, "part starts on the seam's page");
    if (!(s < e)) return refuse(LaidPart, "part has no page");
    const flow = nodeOfElement(f, plan.parent);
    if (flow == rt.none) return refuse(LaidPart, "no flow box");
    // (the part starts on the page after the seam's: where the document has it)
    if (seam != null and base + s < 1) return refuse(LaidPart, "part before page 1");
    return .{ .f = f, .s = s, .e = e, .flow = flow };
}

/// Where the next part's frame starts: part `k`'s last child (laid out as `lp`, whose page `s` is
/// document page `first`).
fn seamAfter(lp: LaidPart, plan: chunks.Plan, k: usize, first: usize) ?Seam {
    if (k + 1 >= plan.parts.len) return null;
    const y = elementTop(lp.f, plan.parts[k + 1].prev) orelse return refuse(Seam, "no last box");
    const pages = lp.f.paginated().?;
    const at = pages.pageAt(y);
    if (at < lp.s or at >= lp.e) return refuse(Seam, "last box outside the part");
    return .{ .y = y, .page = first + (at - lp.s), .top = pages.pages[at].top };
}

/// The page count of `doc`'s document laid out a part at a time (each part released at once).
/// Null: the parts cannot be laid out apart.
fn countParts(r: *rt.Renderer, doc: *const Frame, plan: chunks.Plan, geo: *const Geo, blank: bool) Error!?usize {
    var n: usize = 0;
    var seam: ?Seam = null;
    for (0..plan.parts.len) |k| {
        const mem = try newMem(r);
        defer freeMem(r, mem);
        const lp = try layPart(mem.allocator(), doc, plan, k, geo, seam, blank) orelse return null;
        if (seam) |sm| if (sm.page + lp.s != n) return refuse(usize, "pages moved at a seam");
        if (k + 1 < plan.parts.len) seam = seamAfter(lp, plan, k, n) orelse return null;
        n += lp.e - lp.s;
    }
    return n;
}

/// The paged document `o_in` (geometry `p_in`) laid out and drawn a part at a time when it can be
/// cut at forced page breaks (chunks.zig): the same file as `layOut` + `emit.writeDocument`, with
/// one part's layout in memory at a time. Null: it cannot be (the caller lays it out whole).
pub fn writeChunked(r: *rt.Renderer, a: Allocator, o_in: opt.PdfOptions, css: ?json.Value, kind: rt.SourceKind, source: []const u8, p_in: opt.Page, background: ?style.Color, policy: emit.DocOptions) Error!?[]const u8 {
    if (comptime !layout.fragment.enabled) return null;
    if (!o_in.chunks) return null;
    var rules = try pageRules(a, o_in, kind, source, p_in, .{});
    var o = o_in;
    o.geometry = .{ .page = rules.rest };
    var cx: Ctx = .{ .doc = .{ .r = r, .a = a, .o = o, .css = css }, .kind = kind, .source = source };
    var header = try bands.Slot.init(a, o, true);
    var footer = try bands.Slot.init(a, o, false);
    if (header) |*s| try bands.measure(&cx.doc, s, 1);
    if (footer) |*s| try bands.measure(&cx.doc, s, 1);
    var geo = try Geo.resolve(r, a, rules, heights(header), heights(footer));
    if (!geo.uniformWidth()) return refuse([]const u8, "page widths differ");
    // the document, shared by its parts; page counters in the content lay it out whole
    var subst: counters.Subst = .{ .a = a, .mode = .{ .flow = .{ .texts = &.{}, .fixed = &.{} } } };
    // (the element model and styles in memory of their own, freed once the file is written: the
    // file is in `a`)
    const dmem = try newMem(r);
    defer freeMem(r, dmem);
    const da = dmem.allocator();
    var doc = try bands.buildDocument(r, da, o, css, kind, source, geo.area(0, null), &subst);
    if (subst.hooks.items.len > 0) return refuse([]const u8, "page counters in the content");
    if (rules.contextual) {
        // page rules that read the root element (`layOut`): read again with the document's root;
        // other rules lay the document out with them
        const again = try pageRules(a, o_in, kind, source, p_in, docRootContext(doc));
        if (!(std.meta.eql(again.first, rules.first) and std.meta.eql(again.left, rules.left) and std.meta.eql(again.right, rules.right) and again.rtl == rules.rtl)) {
            rules = again;
            o.geometry = .{ .page = rules.rest };
            cx.doc.o = o;
            header = try bands.Slot.init(a, o, true);
            footer = try bands.Slot.init(a, o, false);
            if (header) |*s| try bands.measure(&cx.doc, s, 1);
            if (footer) |*s| try bands.measure(&cx.doc, s, 1);
            geo = try Geo.resolve(r, a, rules, heights(header), heights(footer));
            if (!geo.uniformWidth()) return refuse([]const u8, "page widths differ");
            subst = .{ .a = a, .mode = .{ .flow = .{ .texts = &.{}, .fixed = &.{} } } };
            doc = try bands.buildDocument(r, da, o, css, kind, source, geo.area(0, null), &subst);
            if (subst.hooks.items.len > 0) return refuse([]const u8, "page counters in the content");
        }
    }
    const plan = try chunks.plan(a, doc, o.chunk_elements) orelse return refuse([]const u8, "no cut");
    const names = doc.tree.paged.page_names;
    geo.names = names;
    const blank = o.uncovered_text == .blank;

    // A band that depends on the page count (its counters, or a rule for the last page) needs the
    // count first: the parts are laid out once to count their pages. A counter band is measured
    // again until its height settles, as `layOutRules` does.
    const dynamic = (if (header) |s| s.dynamic else false) or (if (footer) |s| s.dynamic else false);
    const varies = (if (header) |s| s.varies else false) or (if (footer) |s| s.varies else false);
    var n: usize = 0;
    if (dynamic or varies) {
        n = try countParts(r, doc, plan, &geo, blank) orelse return null;
        if (dynamic) {
            var follows = rules.first.margin.followBands() or rules.left.margin.followBands() or rules.right.margin.followBands();
            for (rules.named) |e| follows = follows or e.first.margin.followBands() or e.left.margin.followBands() or e.right.margin.followBands();
            var k: usize = 0;
            while (k < band_passes) : (k += 1) {
                const before = .{ heights(header), heights(footer) };
                if (header) |*s| try bands.measure(&cx.doc, s, n);
                if (footer) |*s| try bands.measure(&cx.doc, s, n);
                if (same(before[0], heights(header)) and same(before[1], heights(footer))) break;
                var geo2 = try Geo.resolve(r, a, rules, heights(header), heights(footer));
                if (geo.sameMargins(&geo2)) break;
                if (!follows) break;
                geo2.names = names;
                geo = geo2;
                n = try countParts(r, doc, plan, &geo, blank) orelse return null;
            }
        }
    }

    const dw = try emit.DocWriter.init(a, doc, policy);
    defer dw.deinit();
    var sel = opt.PageSelection.init(o.page_ranges);
    // (the bands of a single page are laid out when it is drawn, from this copy)
    const band_doc = try a.create(bands.Doc);
    band_doc.* = cx.doc;
    const own = struct {
        fn win(p: layout.fragment.Page) emit.Window {
            return .{ .top = p.top, .bottom = p.top + p.height, .lines_top = p.top, .lines_bottom = p.top + p.height };
        }
    };
    var i: usize = 0;
    var seam: ?Seam = null;
    for (0..plan.parts.len) |k| {
        memtrace.mark("part: start");
        const mem = try newMem(r);
        defer freeMem(r, mem);
        const pa = mem.allocator();
        const lp = try layPart(pa, doc, plan, k, &geo, seam, blank) orelse return null;
        if (seam) |sm| if (sm.page + lp.s != i) return refuse([]const u8, "pages moved at a seam");
        if (k + 1 < plan.parts.len) seam = seamAfter(lp, plan, k, i) orelse return null;
        memtrace.mark("part: laid out");
        const f = lp.f;
        const paged = f.paginated().?;
        const last_part = k + 1 == plan.parts.len;
        var boxes: std.ArrayList(emit.PageBox) = .empty;
        var windows: std.ArrayList(emit.Window) = .empty;
        var local: usize = lp.s;
        while (local < lp.e) : (local += 1) {
            const pg = paged.pages[local];
            const gi = i + (local - lp.s);
            const kept = try sel.pushPage(a);
            if (kept == null) continue;
            const name = geo.nameOf(if (local < paged.names.len) paged.names[local] else 0);
            const pp = geo.page(gi, name);
            const m = geo.margins(gi, name);
            const area = geo.area(gi, name);
            var box: emit.PageBox = .{
                .width = pp.width,
                .height = pp.height,
                .content = .{ .x = m.left, .y = m.top, .w = area[0], .h = area[1] },
                .background = background,
                .clip = true,
                .repeats = paged.repeatsOf(@intCast(local)),
                .fixed = &.{},
            };
            // (the frame's own pages around the part's take part as neighbouring passes)
            if (local == lp.s and lp.s > 0) box.prev_win = own.win(paged.pages[lp.s - 1]);
            if (local + 1 == lp.e and lp.e < paged.pages.len) box.next_win = own.win(paged.pages[lp.e]);
            if (header) |*s| box.header = try bands.forPage(band_doc, s, gi, n, pp.width, pp.height);
            if (footer) |*s| box.footer = try bands.forPage(band_doc, s, gi, n, pp.width, pp.height);
            try boxes.append(pa, box);
            // takumi `PageSlice::lines`: the first page also owns the lines above it, the last the
            // lines below it
            try windows.append(pa, .{
                .top = pg.top,
                .bottom = pg.top + pg.height,
                .lines_top = if (gi == 0) -std.math.inf(f32) else pg.top,
                .lines_bottom = if (last_part and local + 1 == lp.e) std.math.inf(f32) else pg.top + pg.height,
            });
        }
        i += lp.e - lp.s;
        if (!try dw.beginChunk(f)) return refuse([]const u8, "carried structure has no box");
        // (the part's anchors and headings: those whose box starts between its first page's top and
        // the next part's first page's, as the whole document's first page collects them all)
        const bounds: [2]f32 = .{ if (k == 0) -std.math.inf(f32) else paged.pages[lp.s].top - seam_eps, if (last_part) std.math.inf(f32) else paged.pages[lp.e].top - seam_eps };
        if (boxes.items.len > 0) {
            try dw.drawPages(f, boxes.items, windows.items, pa, bounds);
        } else {
            // every page of the part dropped: its anchors and headings are still the document's
            const pg = paged.pages[lp.s];
            const gi = i - (lp.e - lp.s);
            const name = geo.nameOf(if (lp.s < paged.names.len) paged.names[lp.s] else 0);
            const pp = geo.page(gi, name);
            const m = geo.margins(gi, name);
            const area = geo.area(gi, name);
            _ = pg;
            try dw.collect(f, .{ .width = pp.width, .height = pp.height, .content = .{ .x = m.left, .y = m.top, .w = area[0], .h = area[1] }, .clip = true }, bounds);
        }
        const pt = plan.parts[k];
        if (!chunks.ownsCollected(doc, plan, pt, dw.links.anchors, dw.links.headings.items, dw.links.chunk)) return refuse([]const u8, "an anchor or heading outside its part");
        if (!try dw.endChunk(pa, .{ .parent = lp.flow, .lo = pt.own_lo, .hi = pt.own_hi })) return refuse([]const u8, "structure crosses a seam");
        memtrace.mark("part: drawn");
    }
    var diag: opt.Diag = .{};
    sel.finish(&diag) catch {
        r.setErr(diag.message(), "");
        return error.Invalid;
    };
    return try dw.finish();
}

/// takumi `measure` with page options: the tree laid out like a band (the full page width, an
/// unbounded height) with three-digit counters (`999`), target counters empty; its own size.
pub fn measureBand(r: *rt.Renderer, a: Allocator, o_in: opt.PdfOptions, css: ?json.Value, kind: rt.SourceKind, source: []const u8) Error!*Frame {
    // (at the first page's width, as takumi's `with_page_rules(..).first()`)
    var o = o_in;
    o.geometry = .{ .page = (try pageRules(a, o_in, kind, source, o_in.geometry.page, .{})).first };
    var subst: counters.Subst = .{ .a = a, .mode = .{ .band = .{ .page = 999, .pages = 999 } } };
    return bands.buildFrame(r, a, o, css, kind, source, null, null, &subst);
}
