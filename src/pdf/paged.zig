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
//! breaks the page, fragment.zig). The content lays out once, at the width of the first unnamed
//! page's area; a named page whose area is wider or narrower keeps its own size and margins and
//! shows the content from its area's left edge (takumi lays each page out at its own width).
//! Links / outline belong to the interactive wave.
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

/// One layout of the content, paginated.
pub const Pass = struct {
    frame: *Frame,
    pages: *const layout.fragment.Pages,
    /// the counter hooks met, in document order, and the texts they were laid out with
    hooks: []const counters.Hook,
    texts: []const ?[]const u8,
    /// the repeating `position: fixed` boxes (`emit.repeatingFixed`), as a mask over the nodes, and
    /// which hooks sit inside one
    fixed: []const u32,
    mask: []const bool,
    fixed_hooks: []const bool,

    fn pageCount(p: *const Pass) usize {
        return p.pages.pages.len;
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
    const f = try bands.buildFrame(cx.doc.r, a, cx.doc.o, cx.doc.css, cx.kind, cx.source, null, geo.area(0, null), &subst);
    const g = try a.create(Geo);
    g.* = geo.*;
    g.names = f.tree.paged.page_names;
    const varies = !geo.uniformHeight();
    const pages = try f.paginate(.{ .page_height = geo.area(0, null)[1], .page_height_fn = if (varies) Geo.heightOf else null, .ctx = @ptrCast(g) });
    const fixed = try emit.repeatingFixed(a, f);
    const mask = try counters.fixedMask(a, f, fixed);
    const hooks = subst.hooks.items;
    return .{
        .frame = f,
        .pages = pages,
        .hooks = hooks,
        .texts = texts,
        .fixed = fixed,
        .mask = mask,
        .fixed_hooks = try counters.fixedHooks(a, f, hooks, mask),
    };
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
        const texts = try counters.flowTexts(a, pass.frame, pass.hooks, pass.fixed_hooks, pass.mask);
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
    return page_rules.resolve(a, p, o.css, if (kind == .html) source else null, cx);
}

/// takumi `PageContext`: what the page rules take from the root element of a laid-out frame.
pub fn rootContext(f: *const Frame) page_rules.Context {
    const cs = f.nodes.items[f.root].cs;
    const Get = struct {
        fn custom(ctx: *const anyopaque, name: []const u8) ?[]const u8 {
            const c: *const style.ComputedStyle = @ptrCast(@alignCast(ctx));
            return c.customProperty(name);
        }
    };
    return .{ .rtl = cs.direction == .rtl, .font_size = cs.font_size, .ctx = @ptrCast(cs), .custom = Get.custom };
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
    const paged = content.pages;
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
    while (i < n) : (i += 1) {
        const kept = try sel.pushPage(a);
        if (kept == null) continue;
        const pg = paged.pages[i];
        const name = geo.nameOf(if (i < paged.names.len) paged.names[i] else 0);
        const pp = geo.page(i, name);
        const m = geo.margins(i, name);
        const area = geo.area(i, name);
        var box: emit.PageBox = .{
            .width = pp.width,
            .height = pp.height,
            .content = .{ .x = m.left, .y = m.top, .w = area[0], .h = area[1] },
            .background = background,
            .clip = true,
            .repeats = paged.repeatsOf(@intCast(i)),
            .fixed = content.fixed,
        };
        if (header) |*s| box.header = try bands.forPage(&cx.doc, s, i, n, pp.width, pp.height);
        if (footer) |*s| box.footer = try bands.forPage(&cx.doc, s, i, n, pp.width, pp.height);
        if (fixed_counters) {
            var subst: counters.Subst = .{ .a = a, .mode = .{ .flow = .{ .texts = content.texts, .fixed = content.fixed_hooks, .page = i + 1, .pages = n } } };
            const ff = try bands.buildFrame(r, a, o, css, kind, source, null, geo.area(0, null), &subst);
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
