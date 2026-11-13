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
};

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
        return g.margin[g.entry(name)][@intFromEnum(g.pages.kindOf(i))];
    }
    fn area(g: *const Geo, i: usize, name: ?[]const u8) [2]f32 {
        return g.areas[g.entry(name)][@intFromEnum(g.pages.kindOf(i))];
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

fn layPass(cx: *const Ctx, geo: *const Geo, texts: []const ?[]const u8, fixed_hooks: []const bool) Error!Pass {
    const a = cx.doc.a;
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
    } else try laySegments(cx, g, &subst, &segs);
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
fn laySegments(cx: *const Ctx, g: *Geo, subst: *counters.Subst, segs: *std.ArrayList(Seg)) Error!void {
    const a = cx.doc.a;
    const no_node = layout.fragment.Start{};
    var width = g.area(0, null)[0];
    var base: u32 = 0;
    var start: ?layout.fragment.Start = null;
    var cut: ?bands.Cut = null;
    var start_top: f32 = 0;
    var retried = false;
    while (true) {
        const f = try bands.buildFrameCut(cx.doc.r, a, cx.doc.o, cx.doc.css, cx.kind, cx.source, null, .{ width, g.area(base, null)[1] }, subst, cut);
        g.names = f.tree.paged.page_names;
        if (segs.items.len > 0 and !sameNodes(segs.items[0].frame, f)) return extendLast(segs);
        if (start) |*s| if (cut) |c| {
            s.line = lineStarting(f, c.node, c.glyph) orelse return extendLast(segs);
        };
        const sc = try a.create(SegCtx);
        sc.* = .{ .g = g, .base = base, .fake = @intFromBool(start != null) };
        const pages = try f.paginate(.{ .page_height = g.area(base, null)[1], .page_height_fn = SegCtx.height, .ctx = @ptrCast(sc), .start = start, .start_top = if (start != null) start_top else null, .record_starts = true, .max_pages = max_pages + 1 });
        // (page 1 must start where the run before stopped, else the run before goes on)
        if (start) |s| if (pages.start_page == 0 or pages.pages.len < 2 or pages.starts[1].node != s.node or pages.starts[1].line != s.line) return extendLast(segs);
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
        var stop: ?u32 = null;
        var i: u32 = fake + 1;
        while (i < pages.pages.len) : (i += 1) {
            if (g.area(base + i - fake, g.nameOf(pages.names[i]))[0] == width) continue;
            const tok = pages.starts[i];
            if (tok.node == no_node.node) continue;
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
        const tok = pages.starts[s_i];
        width = g.area(base + s_i - fake, g.nameOf(pages.names[s_i]))[0];
        base += s_i - fake;
        // (the run goes on where this one's pages end, in the same block coordinates: takumi's
        // pages stack in one space)
        start_top = pages.pages[s_i].top;
        start = tok;
        cut = null;
        if (tok.line != no_node.line) cut = .{ .node = f.lid_node.items[tok.node], .glyph = lineGlyph(f, tok.node, tok.line).? };
    }
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
fn settle(cx: *const Ctx, geo: *const Geo) Error!Pass {
    const a = cx.doc.a;
    var pass = try layPass(cx, geo, &.{}, &.{});
    if (pass.hooks.len == 0) return pass;
    // the first pass was laid out with every hook as written
    const as_written = try a.alloc(?[]const u8, pass.hooks.len);
    @memset(as_written, null);
    var used: []const ?[]const u8 = as_written;
    var k: usize = 0;
    while (k < counter_passes) : (k += 1) {
        if (k > 0) pass = try layPass(cx, geo, used, pass.fixed_hooks);
        const texts = try counters.flowTexts(a, pass.segs, pass.hooks, pass.fixed_hooks, pass.mask);
        // the pass was laid out with the numbers it gives
        if (counters.sameTexts(texts, used)) return pass;
        used = texts;
    }
    // still moving after the last pass allowed: laid out once more, so the pages show the numbers
    // they were laid out with
    return layPass(cx, geo, used, pass.fixed_hooks);
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
    const Get = struct {
        fn custom(ctx: *const anyopaque, name: []const u8) ?[]const u8 {
            const c: *const style.ComputedStyle = @ptrCast(@alignCast(ctx));
            return c.customProperty(name);
        }
    };
    return .{ .rtl = cs.direction == .rtl, .font_size = cs.font_size, .rem = f.nodes.items[f.root].cs.font_size, .ctx = @ptrCast(cs), .custom = if (props) Get.custom else null };
}

/// Lays the paged document `o_in` (geometry `p_in`) out: `@page` rules, bands, margins, the content
/// with its counters settled, and the kept pages. Page rules that depend on the root element (its
/// direction, font size, custom properties) are resolved again from the laid-out root, and the
/// document laid out again when that changes them.
pub fn layOut(r: *rt.Renderer, a: Allocator, o_in: opt.PdfOptions, css: ?json.Value, kind: rt.SourceKind, source: []const u8, p_in: opt.Page, background: ?style.Color) Error!Document {
    const rules = try pageRules(a, o_in, kind, source, p_in, .{});
    const doc = try layOutRules(r, a, o_in, css, kind, source, rules, background);
    if (!rules.contextual) return doc;
    const again = try pageRules(a, o_in, kind, source, p_in, rootContext(doc.frame));
    if (std.meta.eql(again.first, rules.first) and std.meta.eql(again.left, rules.left) and std.meta.eql(again.right, rules.right) and again.rtl == rules.rtl) return doc;
    return layOutRules(r, a, o_in, css, kind, source, again, background);
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
            content = try settle(&cx, &geo);
        }
    }

    const n = content.pageCount();
    geo.names = content.frame.tree.paged.page_names;
    // fixed boxes holding a page counter lay out again per page (takumi `FixedTemplate`)
    var fixed_counters = false;
    for (content.hooks, content.fixed_hooks) |h, fx| {
        if (fx and h.kind != .target) fixed_counters = true;
    }
    var sel = opt.PageSelection.init(o.page_ranges);
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
        }
        if (header) |*s| box.header = try bands.forPage(&cx.doc, s, i, n, pp.width, pp.height);
        if (footer) |*s| box.footer = try bands.forPage(&cx.doc, s, i, n, pp.width, pp.height);
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
    return .{ .frame = content.frame, .pages = pages.items, .windows = windows.items, .count = n };
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
