//! Block fragmentation (pagination) for paged output: a post-layout pass over a tree that `Tree.compute`
//! laid out once at page width with an unbounded height.
//!
//! Model. The pages stack in the block direction of ONE coordinate space ("stitched" space, as takumi's
//! `PageSizes` / `PageWindows`): page `i` is the window `[pages[i].top, pages[i].top + pages[i].height)`.
//! `paginate` chooses the page breaks by Blink LayoutNG's rules and moves the content after each break
//! down to the start of the next page by rewriting `Layout.y` / `Layout.h` in place. Afterwards a page is
//! painted by painting the whole tree translated by `-pages[i].top` and clipped to the page: a box that
//! spans a page boundary is cut by the clip, which is `box-decoration-break: slice`.
//! What the boxes alone cannot say is returned in `Pages`:
//!  * `line_shifts`: the line boxes of a text node are owned by the caller; the lines from `first_line`
//!    on sit `dy` lower than in the caller's line layout (a line never splits);
//!  * `repeats`: subtrees painted again on other pages (repeated table header / footer groups,
//!    `position: fixed` boxes), translated by `dy`.
//!
//! Break decisions follow Blink's `fragmentation_utils.cc` / `block_layout_algorithm.cc` as ported by
//! takumi-core (class A / B / C break opportunities, break appeal, early breaks, forced breaks,
//! `break-inside: avoid`, `orphans` / `widows`, monolithic content, margins truncated at unforced breaks,
//! parallel flows for table cells / flex rows / grid rows / floats / overflowing content of boxes that end
//! on the page). Blink lays every page out again from a break token; here one page at a time is "probed"
//! on the finished layout (pure, no mutation: `probe`) and the break it finds is then applied (`apply`):
//! the positions before a page's first break are those of the unfragmented layout, so no re-layout is
//! needed (Blink's own flex and grid fragmentation works the same way: one layout, then per-page offsets).
//!
//! Usage (see tests_fragment.zig):
//!   try t.compute(root, .{ .{ .definite = page_w }, .{ .definite = page_h } }, ctx, measure, opts);
//!   var pages = try fragment.paginate(&t, arena, root, .{ .page_height = page_h, .lines_fn = linesFn, .ctx = ctx });
//!   for (pages.pages, 0..) |pg, i| {
//!       // clip to the page, translate by -pg.top, paint the tree: text lines at their y + pages.lineDy(node, line);
//!       // then for (pages.repeatsOf(i)) |r| paint the subtree of r.node translated by a further r.dy
//!   }
//!
//! Limits of a post-layout pass (nothing is laid out again):
//!  * lines do not re-flow beside a float that moved to another page; percentages and stretching never saw
//!    a page size; a box with a definite `height` keeps it (its content overflows, as in Blink), any other
//!    box grows by what a break pushed down;
//!  * the page inline size cannot change from page to page (block sizes can: `Options.page_height_fn`);
//!  * `box-decoration-break: clone` is only carried in `Breaks` (the boxes are sliced, not grown by the
//!    cloned decorations); a cell that spans rows is not fragmented; anonymous table rows / cells keep
//!    their `TableGeom`; `position: relative` offsets take part in the break positions.
const std = @import("std");
const sty = @import("style.zig");
const tr = @import("tree.zig");

const Allocator = std.mem.Allocator;
const no_node = tr.no_node;
const BB = sty.BreakBetween;

pub const enabled = sty.frag_enabled;
pub const Breaks = sty.Breaks;
pub const BreakBetween = sty.BreakBetween;

/// A line box of a text node: block offsets from the node's border-box top.
pub const LineBox = struct { top: f32, bottom: f32 };
/// The line boxes of `node` in block order, valid until the next call. Empty: the node has none (an image,
/// or inline content the caller cannot split): it is monolithic. Called for measured leaves and
/// `Display.inline_row` nodes.
pub const LinesFn = *const fn (ctx: *anyopaque, node: tr.NodeId) []const LineBox;
/// Block size of the page area of page `page` (0-based), a page named `name` (`Breaks.page` ids, 0 =
/// unnamed: the used page name of the content that starts the page, as Blink's
/// `PageNameForChildFragment`).
pub const PageHeightFn = *const fn (ctx: *anyopaque, page: u32, name: u32) f32;

pub const Options = struct {
    /// block size of the page area (inside the page margins) of every page
    page_height: f32,
    /// per-page block sizes (named pages / `@page`); overrides `page_height`. The inline size cannot vary:
    /// the tree is laid out once.
    page_height_fn: ?PageHeightFn = null,
    lines_fn: ?LinesFn = null,
    ctx: *anyopaque = undefined,
    /// `error.TooManyPages` beyond this (takumi-pdf's MAX_PAGES)
    max_pages: u32 = 20_000,
};

pub const Page = struct { top: f32, height: f32 };
/// Lines `first_line..` of `node` (up to the next entry of the same node) are painted `dy` lower.
pub const LineShift = struct { node: u32, first_line: u32, dy: f32 };
/// Paint the subtree of `node` once more on page `page`, translated by `dy` in stitched space.
pub const Repeat = struct { node: u32, page: u32, dy: f32 };

pub const BoxFragment = struct { y: f32, h: f32, from_prev: bool, to_next: bool };

pub const Pages = struct {
    pages: []Page = &.{},
    /// the page name of each page (`Breaks.page` ids, 0 = unnamed)
    names: []u32 = &.{},
    /// sorted by (node, first_line)
    line_shifts: []LineShift = &.{},
    /// sorted by page
    repeats: []Repeat = &.{},

    pub fn deinit(p: *Pages, a: Allocator) void {
        a.free(p.pages);
        a.free(p.names);
        a.free(p.line_shifts);
        a.free(p.repeats);
        p.* = .{};
    }
    /// Index of the page that holds stitched block offset `y` (the last page for anything below).
    pub fn pageAt(p: *const Pages, y: f32) u32 {
        var i: u32 = 0;
        while (i + 1 < p.pages.len and y >= p.pages[i + 1].top) i += 1;
        return i;
    }
    /// The part of a box (stitched border-box block start `top`, block size `h`) that is on page `page`:
    /// null when the page shows none of it. `y` is relative to the page start; `from_prev` / `to_next`:
    /// the box continues from the page before / onto the page after (its block-start / block-end edge
    /// is not on this page: where `box-decoration-break: slice` leaves the border out).
    pub fn boxOnPage(p: *const Pages, page: u32, top: f32, h: f32) ?BoxFragment {
        if (page >= p.pages.len) return null;
        const pg = p.pages[page];
        const last = page + 1 == p.pages.len;
        const s = @max(top, pg.top);
        const e = if (last) top + h else @min(top + h, pg.top + pg.height);
        if (h > 0) {
            if (!(e > s)) return null;
        } else if (!(top >= pg.top and (last or top < pg.top + pg.height))) return null;
        return .{ .y = s - pg.top, .h = @max(e - s, 0), .from_prev = top < pg.top, .to_next = !last and top + h > pg.top + pg.height };
    }
    /// The shifts of the lines of `node` (ascending `first_line`).
    pub fn lineShifts(p: *const Pages, node: u32) []const LineShift {
        var lo: usize = 0;
        var hi: usize = p.line_shifts.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (p.line_shifts[mid].node < node) lo = mid + 1 else hi = mid;
        }
        var end = lo;
        while (end < p.line_shifts.len and p.line_shifts[end].node == node) end += 1;
        return p.line_shifts[lo..end];
    }
    /// Block shift of line `line` of `node`.
    pub fn lineDy(p: *const Pages, node: u32, line: u32) f32 {
        var dy: f32 = 0;
        for (p.lineShifts(node)) |s| {
            if (s.first_line > line) break;
            dy = s.dy;
        }
        return dy;
    }
    /// The repeats of page `page`.
    pub fn repeatsOf(p: *const Pages, page: u32) []const Repeat {
        var lo: usize = 0;
        while (lo < p.repeats.len and p.repeats[lo].page < page) lo += 1;
        var end = lo;
        while (end < p.repeats.len and p.repeats[end].page == page) end += 1;
        return p.repeats[lo..end];
    }
};

pub const Error = error{ OutOfMemory, TooManyPages, InvalidPageSize };

/// Paged-layout state a tree carries with the PDF feature (`Tree.paged`; `void` without it, so the
/// other builds do not change). Filled by the caller (render.zig `Frame.setPaged` / `paginate`).
pub const PagedState = struct {
    /// page area (content box) size in px when laid out for pages; 0 = not paged. `page_h` is also the
    /// block size of the initial containing block of `position: fixed` boxes (tree.zig)
    page_w: f32 = 0,
    page_h: f32 = 0,
    /// the result of `paginate`
    pages: ?Pages = null,
    /// the caller's `LinesFn` result buffer and per-page heights
    lines: std.ArrayList(LineBox) = .empty,
    height_fn: ?PageHeightFn = null,
    height_ctx: *anyopaque = undefined,
    /// called by `Frame.prepare` with (`dom_ctx`, the frame) once the element model is built, before
    /// the cascade (PDF page counters: src/pdf/counters.zig). Any frame, paged or not.
    dom_hook: ?*const fn (ctx: *anyopaque, frame: *anyopaque) error{OutOfMemory}!void = null,
    dom_ctx: *anyopaque = undefined,
    /// The frame is laid out for PDF output (set by src/pdf before `Frame.prepare`, paged or not):
    /// list markers, takumi's glyph placement (render.zig `listMarkers`, `makeParagraph`).
    pdf: bool = false,
    /// The frame's list markers (`src/pdf/markers.zig` `State`, opaque here); null = none generated.
    markers: ?*anyopaque = null,
    /// Named pages (src/pdf/page_names.zig): the page name id of each source element (0 = `auto`,
    /// empty when no element names a page) and the names (id `k` is `page_names[k - 1]`).
    page_of: []const u32 = &.{},
    page_names: []const []const u8 = &.{},
};

/// Paginates the subtree of `root` (laid out by `t.compute`, normally with a definite available width =
/// the page area's width and an unbounded height). Rewrites the layouts of `t` in place (stitched space,
/// see the module doc) and returns the pages; the slices of the result come from `a`.
pub fn paginate(t: anytype, a: Allocator, root: tr.NodeId, opts: Options) Error!Pages {
    if (!enabled) @compileError("fragment.paginate needs the PDF feature (config.enable_pdf)");
    const E = Engine(@TypeOf(t.*));
    var e: E = .{ .t = t, .a = a, .opts = opts };
    defer e.deinit();
    return e.run(root);
}

/// Blink's BreakAppeal, worst first.
const Appeal = enum(u8) { last_resort, violating_avoid, violating_orphans_widows, perfect };
inline fn rank(x: Appeal) u8 {
    return @intFromEnum(x);
}
inline fn worse(x: Appeal, y: Appeal) Appeal {
    return if (rank(x) < rank(y)) x else y;
}
/// Blink's JoinFragmentainerBreakValues (the second value wins a tie).
inline fn join(first: BB, second: BB) BB {
    return if (@intFromEnum(second) >= @intFromEnum(first)) second else first;
}

const eps: f32 = 1.0 / 128.0;
const ninf: f32 = -std.math.inf(f32);

/// The window of the current page for a flow: content may use `[start, end)`, and what breaks continues at
/// `next` (a table shrinks the window by its repeated header / footer).
const Pg = struct { start: f32, end: f32, next: f32 };

/// How a node's content is walked.
const K = enum(u8) {
    /// never split
    mono,
    /// line boxes (`LinesFn`)
    text,
    /// children in document order, one after the other (floats / static-position boxes ride along)
    block,
    /// captions and row groups in block order
    table,
    /// rows in document order
    group,
    /// cells side by side: one band of parallel flows
    row,
    /// flex / grid: items grouped into bands (rows) of parallel flows, bands in block order
    bands,
};

const Kind = enum(u8) { none, before, inside, line, span, push };
/// The breakpoint a probe chose inside a node for the current page (`brk`), or the best one it saw while
/// the node fit (an "early break" an ancestor may come back to). `arg`: item index / line index.
const Slot = struct {
    stamp: u32 = 0,
    arg: u32 = 0,
    /// trailing margin cut where the page ends (the node fits once shortened by it)
    trim: f32 = 0,
    kind: Kind = .none,
    brk: bool = false,
    forced: bool = false,
    /// the node itself ends on the page: its break continues in a parallel flow
    par: bool = false,
};
const State = struct {
    /// item index of the band to resume at (containers) / line index (text)
    @"resume": u32 = 0,
    seq: u32 = no_node,
    /// text: block shift of the lines from `resume` on
    shift: f32 = 0,
    /// broke inside on an earlier page
    started: bool = false,
    /// the band at `resume` is being continued (it broke inside), not started
    child_inside: bool = false,
    /// item of a parallel band whose content ended on an earlier page
    done: bool = false,
    queued: bool = false,
    /// the break before the band at `resume` was a forced one (its margin stays below the page start)
    forced_resume: bool = false,
    /// scratch of `applyBand`: the item reached the band's block end
    full: bool = false,
    /// block start a forced break moves this float / static-position box to (while `pushed`)
    push_y: f32 = 0,
    pushed: bool = false,
};
const Item = struct {
    node: u32,
    /// in-flow (false: a float / static-position box that only rides along with the flow)
    flow: bool,
    /// starts a band
    first: bool,
};
const Seq = struct {
    items: []Item,
    /// free block space below the content of the box (min-height, stretching): absorbs growth
    slack: f32,
    /// block size before pagination
    h0: f32,
    /// block shift not yet written to `items[lazy_from..]`
    lazy: f32 = 0,
    lazy_from: u32 = 0,
    dirty: bool = false,
    /// has `position: absolute` children anchored to the block end
    bottom_abs: bool = false,
};
const Early = struct {
    has: bool = false,
    appeal: Appeal = .perfect,
    kind: Kind = .none,
    item: u32 = 0,
    /// a box on the path to the breakpoint has `break-inside: avoid`
    avoid: bool = false,
};
/// Result of probing a node (or a band) on one page.
const R = struct {
    /// border-box block end reached on this page
    end: f32,
    /// the same with block-end margins (bands only)
    mend: f32 = 0,
    brk: bool = false,
    par: bool = false,
    forced: bool = false,
    /// `brk`: appeal of the break as the container rates it
    appeal: Appeal = .perfect,
    early: bool = false,
    early_appeal: Appeal = .perfect,
    early_avoid: bool = false,
    /// break values propagated from the first / last child
    first: BB = .auto,
    last: BB = .auto,
};
const TableInfo = struct {
    hdr: u32 = no_node,
    hdr_idx: u32 = 0,
    hdr_block: f32 = 0,
    ftr: u32 = no_node,
    ftr_idx: u32 = 0,
    ftr_block: f32 = 0,
    /// border-spacing after a section (0 when collapsed)
    spacing: f32 = 0,
};
const RepeatRaw = struct { node: u32, page: u32, y: f32 };

fn Engine(comptime T: type) type {
    return struct {
        const Self = @This();
        const tables_on: bool = T.config.tables;
        const floats_on: bool = T.config.floats;

        t: *T,
        a: Allocator,
        opts: Options,
        st: []State = &.{},
        slot: []Slot = &.{},
        seqs: std.ArrayList(Seq) = .empty,
        dirty: std.ArrayList(u32) = .empty,
        queue: std.ArrayList(u32) = .empty,
        /// page tops, one more than the pages known
        tops: std.ArrayList(f32) = .empty,
        /// the name of each page of `tops` (named pages), and whether any box names a page
        names: std.ArrayList(u32) = .empty,
        any_names: bool = false,
        shifts: std.ArrayList(LineShift) = .empty,
        reps: std.ArrayList(RepeatRaw) = .empty,
        fixed: std.ArrayList(u32) = .empty,
        pushes: std.ArrayList(u32) = .empty,
        stamp: u32 = 0,
        page: u32 = 0,
        page_h: f32 = 0,

        fn deinit(e: *Self) void {
            for (e.seqs.items) |s| e.a.free(s.items);
            e.seqs.deinit(e.a);
            e.dirty.deinit(e.a);
            e.queue.deinit(e.a);
            e.tops.deinit(e.a);
            e.names.deinit(e.a);
            e.shifts.deinit(e.a);
            e.reps.deinit(e.a);
            e.fixed.deinit(e.a);
            e.pushes.deinit(e.a);
            e.a.free(e.st);
            e.a.free(e.slot);
        }

        inline fn lay(e: *Self, n: u32) *tr.Layout {
            return &e.t.layouts.items[n];
        }
        inline fn style(e: *Self, n: u32) *const sty.Style {
            return &e.t.nodes.items[n].style;
        }

        // ------------------------------------------------------------------------------------ pages

        fn pageHeight(e: *Self, page: u32) Error!f32 {
            const name = if (!e.any_names) 0 else if (page == 0) e.startName(e.t.root, 0) else e.resumeName();
            try e.names.append(e.a, name);
            const h = if (e.opts.page_height_fn) |f| f(e.opts.ctx, page, name) else e.opts.page_height;
            if (!(h >= 1) or !(h < 16_777_216)) return error.InvalidPageSize;
            return h;
        }
        /// Makes `tops[page + 1]` exist.
        fn need(e: *Self, page: u32) Error!void {
            if (page >= e.opts.max_pages) return error.TooManyPages;
            while (e.tops.items.len < @as(usize, page) + 2) {
                const k: u32 = @intCast(e.tops.items.len - 1);
                const h = try e.pageHeight(k);
                try e.tops.append(e.a, e.tops.items[k] + h);
            }
        }
        fn window(e: *Self, page: u32) Error!Pg {
            try e.need(page);
            const s = e.tops.items[page];
            const en = e.tops.items[page + 1];
            e.page = page;
            e.page_h = en - s;
            return .{ .start = s, .end = en, .next = en };
        }
        fn pageAt(e: *Self, y: f32) Error!u32 {
            var p: u32 = 0;
            while (true) : (p += 1) {
                try e.need(p);
                if (y < e.tops.items[p + 1] - eps) return p;
            }
        }

        // ------------------------------------------------------------------------------------ tree access

        fn kindOf(e: *Self, n: u32) K {
            const nd = &e.t.nodes.items[n];
            const s = &nd.style;
            if (s.breaks.monolithic) return .mono;
            if (nd.measured or s.display == .inline_row) return .text;
            return switch (s.display) {
                .flex, .grid => .bands,
                .table, .inline_table => if (tables_on) .table else .block,
                .table_row_group, .table_header_group, .table_footer_group => if (tables_on) .group else .block,
                .table_row => if (tables_on) .row else .block,
                else => .block,
            };
        }
        fn heightDefinite(e: *Self, n: u32) bool {
            const s = e.style(n);
            if (tables_on and (s.display.isTable() or s.display.isTablePart())) return false;
            return switch (s.size[1]) {
                .px => true,
                .calc => |c| c.percent == 0,
                else => false,
            };
        }
        /// Blink's "block size is bounded" (`max_block_size != LayoutUnit::Max`).
        fn bounded(e: *Self, n: u32) bool {
            if (e.heightDefinite(n)) return true;
            const s = e.style(n);
            if (tables_on and (s.display.isTable() or s.display.isTablePart())) return false;
            return s.max_size[1] == .px;
        }
        fn linesOf(e: *Self, n: u32) []const LineBox {
            return if (e.opts.lines_fn) |f| f(e.opts.ctx, n) else &.{};
        }
        /// Block offset of `n`'s border box in stitched space (no shift may be pending above it).
        fn absTopOf(e: *Self, n: u32) f32 {
            var y: f32 = 0;
            var cur = n;
            var guard: u32 = 0;
            while (cur != no_node and guard < tr.max_depth + 8) : (guard += 1) {
                y += e.lay(cur).y;
                if (cur == e.t.root) break;
                cur = e.t.nodes.items[cur].parent;
            }
            return y;
        }

        // ------------------------------------------------------------------------------------ page names

        /// An in-flow child (named pages look through the others).
        fn inFlow(e: *Self, c: u32) bool {
            const s = e.style(c);
            return s.display != .none and !s.position.isOut() and (!floats_on or s.float == .none);
        }
        fn leafish(e: *Self, n: u32) bool {
            const nd = &e.t.nodes.items[n];
            return nd.measured or nd.first_child == no_node or e.kindOf(n) == .mono or e.kindOf(n) == .text;
        }
        /// The used page name of `n`: its own, else `inherited` (`page: auto`).
        fn usedName(e: *Self, n: u32, inherited: u32) u32 {
            const own = e.style(n).breaks.page;
            return if (own != 0) own else inherited;
        }
        /// The used page name of `n` from its ancestors.
        fn usedNameUp(e: *Self, n: u32) u32 {
            var cur = n;
            var guard: u32 = 0;
            while (cur != no_node and guard < tr.max_depth + 8) : (guard += 1) {
                const own = e.style(cur).breaks.page;
                if (own != 0) return own;
                if (cur == e.t.root) break;
                cur = e.t.nodes.items[cur].parent;
            }
            return 0;
        }
        /// CSS's start page value of `n`: its first in-flow child's, else its used page name.
        fn startName(e: *Self, n: u32, inherited: u32) u32 {
            var cur = n;
            var name = e.usedName(n, inherited);
            var guard: u32 = 0;
            while (guard < tr.max_depth + 8 and !e.leafish(cur)) : (guard += 1) {
                var c = e.t.nodes.items[cur].first_child;
                while (c != no_node and !e.inFlow(c)) c = e.t.nodes.items[c].next_sibling;
                if (c == no_node) break;
                name = e.usedName(c, name);
                cur = c;
            }
            return name;
        }
        /// CSS's end page value of `n`: its last in-flow child's, else its used page name.
        fn endName(e: *Self, n: u32, inherited: u32) u32 {
            var cur = n;
            var name = e.usedName(n, inherited);
            var guard: u32 = 0;
            while (guard < tr.max_depth + 8 and !e.leafish(cur)) : (guard += 1) {
                var last: u32 = no_node;
                var c = e.t.nodes.items[cur].first_child;
                while (c != no_node) : (c = e.t.nodes.items[c].next_sibling) {
                    if (e.inFlow(c)) last = c;
                }
                if (last == no_node) break;
                name = e.usedName(last, name);
                cur = last;
            }
            return name;
        }

        /// The page name of the page the main flow resumes on (asked for when that page opens, right
        /// after the break before it is applied): the used page name of the content it resumes with,
        /// down the chain of boxes broken inside (Blink's `PageNameForChildFragment`).
        fn resumeName(e: *Self) u32 {
            var cur = e.t.root;
            var name = e.usedName(cur, 0);
            var guard: u32 = 0;
            while (guard < tr.max_depth + 8) : (guard += 1) {
                const st = &e.st[cur];
                if (!st.started or st.seq == no_node) return name;
                const sq = &e.seqs.items[st.seq];
                if (st.@"resume" >= sq.items.len) return name;
                const c = sq.items[st.@"resume"].node;
                // (a box that starts on the page: its start page value)
                if (!st.child_inside) return e.startName(c, name);
                name = e.usedName(c, name);
                cur = c;
            }
            return name;
        }

        fn seqOf(e: *Self, n: u32, k: K) Error!u32 {
            if (e.st[n].seq != no_node) return e.st[n].seq;
            const ns = e.t.nodes.items;
            var list: std.ArrayList(Item) = .empty;
            errdefer list.deinit(e.a);
            var bottom_abs = false;
            var ch = ns[n].first_child;
            while (ch != no_node) : (ch = ns[ch].next_sibling) {
                const cs = &ns[ch].style;
                if (cs.display == .none) continue;
                if (cs.position.isOut()) {
                    if (cs.position != .absolute) continue;
                    if (cs.inset.top == .auto and cs.inset.bottom != .auto) bottom_abs = true;
                    // (a static-position box follows the content it sits after)
                    if (k == .block and cs.inset.top == .auto and cs.inset.bottom == .auto) try list.append(e.a, .{ .node = ch, .flow = false, .first = true });
                    continue;
                }
                if (k == .table and (cs.display == .table_column or cs.display == .table_column_group)) continue;
                // (a cell that spans rows reaches past its row: it is not fragmented, it moves with the row)
                if (k == .row and e.t.layouts.items[ch].h > e.lay(n).h + eps) continue;
                const side = floats_on and k == .block and cs.float != .none;
                try list.append(e.a, .{ .node = ch, .flow = !side, .first = true });
            }
            const items = try list.toOwnedSlice(e.a);
            errdefer e.a.free(items);
            const lays = e.t.layouts.items;
            if (k == .table or k == .bands or k == .group) {
                // block order: the items are sorted already unless `order`, a reversed direction or a
                // header / footer group placed them elsewhere
                var sorted = true;
                var si: usize = 1;
                while (si < items.len) : (si += 1) {
                    if (lays[items[si - 1].node].y > lays[items[si].node].y) sorted = false;
                }
                if (!sorted) std.sort.heap(Item, items, lays, itemLess);
            }
            if (k == .row) {
                for (items, 0..) |*it, i| it.first = i == 0;
            } else if (k != .block) {
                // a band = the items whose block extents overlap (a flex line, a grid row)
                var band_end: f32 = ninf;
                for (items) |*it| {
                    const l = &lays[it.node];
                    it.first = l.y >= band_end - eps;
                    band_end = if (it.first) l.y + l.h else @max(band_end, l.y + l.h);
                }
            }
            const l = e.lay(n);
            var ce: f32 = l.border.top + l.padding.top;
            for (items) |it| {
                if (!it.flow) continue;
                const cl = &lays[it.node];
                ce = @max(ce, cl.y + cl.h + @max(cl.margin.bottom, 0));
            }
            ce += l.padding.bottom + l.border.bottom;
            const idx: u32 = @intCast(e.seqs.items.len);
            try e.seqs.append(e.a, .{ .items = items, .slack = if (k == .table) 0 else @max(l.h - ce, 0), .h0 = l.h, .bottom_abs = bottom_abs });
            e.st[n].seq = idx;
            return idx;
        }
        fn bandEnd(sq: *const Seq, i: u32) u32 {
            var j = i + 1;
            while (j < sq.items.len and !sq.items[j].first) j += 1;
            return j;
        }
        inline fn itemTop(e: *Self, sq: *const Seq, k: u32, top: f32) f32 {
            return top + e.lay(sq.items[k].node).y + (if (k >= sq.lazy_from) sq.lazy else 0);
        }
        /// Block start of the band `[i, j)`: its highest item that still has content to place.
        fn bandTop(e: *Self, sq: *const Seq, i: u32, j: u32, top: f32) f32 {
            var y: f32 = std.math.inf(f32);
            var any: f32 = std.math.inf(f32);
            var k = i;
            while (k < j) : (k += 1) {
                const it = sq.items[k];
                const ty = e.itemTop(sq, k, top);
                any = @min(any, ty);
                if (it.flow and !e.st[it.node].done) y = @min(y, ty);
            }
            return if (y < std.math.inf(f32)) y else any;
        }
        /// Border-box block end of the last in-flow band before item `i` (-inf: none); `trim`: apply the
        /// margin cuts recorded for its items.
        fn prevReach(e: *Self, sq: *const Seq, i: u32, top: f32, trim: bool) f32 {
            var p = i;
            while (p > 0 and !sq.items[p - 1].flow) p -= 1;
            if (p == 0) return ninf;
            var b = p - 1;
            while (b > 0 and !sq.items[b].first) b -= 1;
            var reach: f32 = ninf;
            var k = b;
            while (k < p) : (k += 1) {
                const c = sq.items[k].node;
                if (!sq.items[k].flow) continue;
                if (trim) e.applyTrim(c);
                reach = @max(reach, e.itemTop(sq, k, top) + e.lay(c).h);
            }
            return reach;
        }

        fn lazyShift(e: *Self, sq_i: u32, from_in: u32, d: f32) Error!void {
            const sq = &e.seqs.items[sq_i];
            const from: u32 = @min(from_in, @as(u32, @intCast(sq.items.len)));
            if (from > sq.lazy_from) {
                if (sq.lazy != 0) for (sq.items[sq.lazy_from..from]) |it| {
                    e.lay(it.node).y += sq.lazy;
                };
                sq.lazy_from = from;
            } else if (from < sq.lazy_from) {
                // (does not happen: breaks only move forward; keep the positions consistent anyway)
                for (sq.items[from..sq.lazy_from]) |it| e.lay(it.node).y -= sq.lazy;
                sq.lazy_from = from;
            }
            sq.lazy += d;
            if (!sq.dirty) {
                sq.dirty = true;
                try e.dirty.append(e.a, sq_i);
            }
        }
        fn flush(e: *Self) void {
            for (e.dirty.items) |sq_i| {
                const sq = &e.seqs.items[sq_i];
                if (sq.lazy != 0) for (sq.items[sq.lazy_from..]) |it| {
                    e.lay(it.node).y += sq.lazy;
                };
                sq.lazy = 0;
                sq.dirty = false;
            }
            e.dirty.clearRetainingCapacity();
        }

        fn tableInfo(e: *Self, n: u32, sq: *const Seq) TableInfo {
            var info: TableInfo = .{};
            const s = e.style(n);
            const spacing: f32 = if (s.border_collapse) 0 else @max(s.border_spacing[1], 0);
            const quarter = e.page_h / 4;
            info.spacing = spacing;
            for (sq.items, 0..) |it, i| {
                const cs = e.style(it.node);
                const is_h = cs.display == .table_header_group and info.hdr == no_node;
                const is_f = cs.display == .table_footer_group and info.ftr == no_node;
                if (!is_h and !is_f) continue;
                const h = e.lay(it.node).h;
                // a group repeats when it avoids breaking inside and is at most a quarter of the page
                const ok = cs.breaks.avoid_inside and h > 0 and h <= quarter + eps;
                if (is_h) {
                    info.hdr = it.node;
                    info.hdr_idx = @intCast(i);
                    if (ok) info.hdr_block = h + spacing;
                } else {
                    info.ftr = it.node;
                    info.ftr_idx = @intCast(i);
                    if (ok) info.ftr_block = h + spacing;
                }
            }
            return info;
        }
        /// The page window of a table's rows: past its repeated header, short of its repeated footer.
        fn tablePg(e: *Self, n: u32, info: *const TableInfo, pg: Pg) Pg {
            var out = pg;
            const stt = &e.st[n];
            if (info.hdr_block > 0) {
                if (stt.started and stt.@"resume" > info.hdr_idx) out.start += info.hdr_block;
                out.next += info.hdr_block;
            }
            if (info.ftr_block > 0 and (!stt.started or stt.@"resume" <= info.ftr_idx)) out.end -= info.ftr_block;
            if (!(out.end > out.start + 1)) out.end = pg.end;
            return out;
        }

        // ------------------------------------------------------------------------------------ probe

        fn setBreak(e: *Self, n: u32, kind: Kind, arg: u32, forced: bool, appeal: Appeal, known_fit: bool, bottom: f32, pg_end: f32) Error!R {
            const sl = &e.slot[n];
            sl.kind = kind;
            sl.arg = arg;
            sl.brk = true;
            sl.forced = forced;
            sl.par = known_fit;
            var ap: Appeal = if (forced) .perfect else appeal;
            // Blink's CalculateBreakAppealInside
            if (!forced and e.style(n).breaks.avoid_inside and rank(ap) > rank(Appeal.violating_avoid)) ap = .violating_avoid;
            if (known_fit) {
                // the box ends on this page: what broke goes on in a parallel flow (`runFlow` later)
                if (!e.st[n].queued) {
                    e.st[n].queued = true;
                    try e.queue.append(e.a, n);
                }
                return .{ .end = bottom, .brk = true, .par = true, .forced = forced, .appeal = ap };
            }
            return .{ .end = pg_end, .brk = true, .forced = forced, .appeal = ap };
        }
        fn useEarly(e: *Self, n: u32, early: Early, known_fit: bool, bottom: f32, pg_end: f32) Error!R {
            // (Blink re-lays out to break at the early breakpoint with a perfect appeal; a box on the way
            // that avoids breaks lowers it)
            return try e.setBreak(n, early.kind, early.item, false, if (early.avoid) .violating_avoid else .perfect, known_fit, bottom, pg_end);
        }

        /// Finds what happens to `n` (border-box block start `top`) on the page `pg`: it fits, or it breaks
        /// (the breakpoint goes to `slot[n]`). Does not change any layout.
        noinline fn probe(e: *Self, n: u32, top: f32, pg: Pg, requires: bool) Error!R {
            const bottom = top + e.lay(n).h;
            e.slot[n] = .{ .stamp = e.stamp };
            const k = e.kindOf(n);
            if (k == .mono) return .{ .end = bottom };
            if (k == .text) return e.probeText(n, top, pg, requires);
            // Blink's is_known_to_fit_in_fragmentainer: a box of bounded block size that ends on this page
            const known_fit = e.bounded(n) and bottom <= pg.end + eps;
            // (a clipping box that fits is not fragmented for its content: Blink's DisableFragmentation)
            if (known_fit and e.style(n).overflow_y != .visible and n != e.t.root) return .{ .end = bottom };
            var first: BB = .auto;
            var r = try e.probeSeq(n, top, pg, k, known_fit, requires, &first);
            // (the break value before the first child reaches the container even where the box breaks)
            if (r.brk and !e.st[n].started) r.first = first;
            return r;
        }

        noinline fn probeSeq(e: *Self, n: u32, top: f32, pg_in: Pg, k: K, known_fit: bool, requires_in: bool, first_out: *BB) Error!R {
            const sq_i = try e.seqOf(n, k);
            const stt = &e.st[n];
            const l = e.lay(n);
            const bottom0 = top + l.h;
            var pg = pg_in;
            var info: TableInfo = .{};
            if (k == .table) {
                info = e.tableInfo(n, &e.seqs.items[sq_i]);
                pg = e.tablePg(n, &info, pg_in);
            }
            // Blink's MustStayInCurrentFragmentainer
            var requires = requires_in or (known_fit and !stt.started);
            var opp = false;
            const first_sep = k == .bands and (e.style(n).display == .grid or e.style(n).flex_direction == .column or e.style(n).flex_direction == .column_reverse);
            var early: Early = .{};
            var prev_after: BB = .auto;
            var first_bb: ?BB = null;
            // (named pages: the used page name here, and the end page value of the sibling before)
            const names_here = e.any_names and k == .block;
            const used_here: u32 = if (names_here) e.usedNameUp(n) else 0;
            var prev_name: ?u32 = null;
            var flow_end: f32 = top + l.border.top + l.padding.top;
            var last_end: f32 = ninf;
            var i: u32 = if (stt.started) stt.@"resume" else 0;
            while (true) {
                const sq = &e.seqs.items[sq_i];
                if (i >= sq.items.len) break;
                const j = bandEnd(sq, i);
                const it0 = sq.items[i];
                if (!it0.flow) {
                    // a float / out-of-flow box after a forced break value goes to the next page on its
                    // own (a parallel flow: this box goes on, and the value still applies to what follows)
                    if (prev_after == .page) try e.push(it0.node, pg_in.next);
                    i = j;
                    continue;
                }
                const resumed = stt.started and i == stt.@"resume";
                const resumed_band = resumed and stt.child_inside;
                const band_top = e.bandTop(sq, i, j, top);
                // pushed below monolithic content of an earlier page: as if after a perfect breakpoint
                if (resumed and !stt.child_inside and !stt.forced_resume and band_top > pg.start + eps) opp = true;
                // Blink's flex columns and grids: anything before the first item / row (padding, its own
                // margin, an alignment offset) separates it from the start of its container
                if (first_sep and !stt.started and i == 0 and band_top > top + eps) opp = true;
                var bpg = pg;
                // (the repeated footer itself is placed in the space reserved for it)
                if (k == .table and it0.node == info.ftr and info.ftr_block > 0) bpg.end = @max(pg.end, pg_in.end);
                const single = j == i + 1;
                var rb: R = undefined;
                var cb: Breaks = .{};
                if (single) {
                    rb = try e.probe(it0.node, band_top, bpg, requires);
                    cb = e.style(it0.node).breaks;
                    rb.mend = rb.end + @max(e.lay(it0.node).margin.bottom, 0);
                } else rb = try e.probeBand(sq_i, i, j, top, band_top, bpg, requires);
                if (!resumed_band) {
                    const child_first = join(rb.first, cb.before);
                    var between = join(prev_after, child_first);
                    // Blink: siblings whose page names differ are separated by a forced break
                    if (names_here and single) {
                        if (prev_name) |pn| if (pn != e.startName(it0.node, used_here)) {
                            between = .page;
                        };
                    }
                    if (first_bb == null) {
                        first_bb = child_first;
                        first_out.* = child_first;
                    }
                    if (opp and between == .page and !resumed) return try e.setBreak(n, .before, i, true, .perfect, known_fit, bottom0, pg.end);
                    // Blink's CalculateBreakAppealBefore
                    const appeal_before: Appeal = if (!opp) .last_resort else if (between == .avoid) .violating_avoid else .perfect;
                    // Blink's MovePastBreakpoint
                    const space_left = bpg.end - band_top;
                    var mp = false;
                    if (!(space_left < -eps or (space_left <= eps and rb.brk and !rb.par))) {
                        // (breaking at the page start makes no progress)
                        mp = band_top <= bpg.start + eps;
                        if (!mp) {
                            if (rb.brk) {
                                // breaking inside is better than before only where it is as good
                                mp = rank(rb.appeal) >= rank(appeal_before) and (!early.has or rank(rb.appeal) >= rank(early.appeal));
                            } else if (rb.end <= bpg.end + eps) {
                                mp = true;
                            } else if (appeal_before == .last_resort and requires) mp = true;
                        }
                        if (mp) {
                            if (single) {
                                // Blink's UpdateEarlyBreakAtBlockChild
                                var ai: Appeal = .last_resort;
                                var done = false;
                                if (rb.early and !rb.brk) {
                                    ai = if (cb.avoid_inside and rank(rb.early_appeal) > rank(Appeal.violating_avoid)) .violating_avoid else rb.early_appeal;
                                    if (!early.has or rank(early.appeal) <= rank(rb.early_appeal))
                                        early = .{ .has = true, .appeal = ai, .kind = .inside, .item = i, .avoid = cb.avoid_inside or rb.early_avoid };
                                }
                                if (rank(appeal_before) <= rank(ai)) done = true;
                                if (!done and early.has and rank(early.appeal) > rank(appeal_before)) done = true;
                                if (!done) early = .{ .has = true, .appeal = appeal_before, .kind = .before, .item = i };
                            } else if (opp and (!early.has or rank(appeal_before) >= rank(early.appeal))) {
                                // Blink's MovePastRowBreakPoint
                                early = .{ .has = true, .appeal = appeal_before, .kind = .before, .item = i };
                            }
                        }
                    }
                    if (!mp) {
                        // Blink's AttemptSoftBreak
                        if (early.has and rank(early.appeal) > rank(appeal_before)) return try e.useEarly(n, early, known_fit, bottom0, pg.end);
                        return try e.setBreak(n, .before, i, false, appeal_before, known_fit, bottom0, pg.end);
                    }
                }
                if (rb.brk and !rb.par) return try e.setBreak(n, .inside, i, rb.forced, rb.appeal, known_fit, bottom0, pg.end);
                requires = false;
                // (a repeated header takes no part in breaking: no breakpoint between it and the rows)
                if (!(k == .table and it0.node == info.hdr and info.hdr_block > 0)) opp = true;
                prev_after = join(rb.last, cb.after);
                if (names_here and single) prev_name = e.endName(it0.node, used_here);
                last_end = rb.end;
                flow_end = @max(flow_end, rb.mend);
                i = j;
            }

            // every child that is left fits on this page
            const sl = &e.slot[n];
            var bottom = bottom0;
            const inset_b = l.padding.bottom + l.border.bottom;
            if (k == .block and !e.bounded(n) and bottom > pg.end + eps and last_end > ninf) {
                // Blink's AdjustedMarginAfterFinalChildFragment: the last child's block-end margin stops
                // at the page end
                const ce = bottom - inset_b;
                if (last_end <= pg.end + eps and ce > pg.end + eps) {
                    sl.trim = ce - @max(last_end, pg.end);
                    bottom -= sl.trim;
                }
            }
            if (bottom <= pg.end + eps) {
                var r: R = .{ .end = bottom, .first = first_bb orelse .auto, .last = prev_after };
                if (early.has and !known_fit) {
                    sl.kind = early.kind;
                    sl.arg = early.item;
                    r.early = true;
                    r.early_appeal = early.appeal;
                    r.early_avoid = early.avoid;
                }
                return r;
            }
            // the box itself reaches past the page end (Blink's FinishFragmentation): in the free space
            // below its content that is a perfect break; inside its block-end padding / border it goes
            // back to an earlier breakpoint, or is a last resort
            if (bottom > flow_end + inset_b + eps) return try e.setBreak(n, .span, 0, false, .perfect, false, bottom0, pg.end);
            if (early.has) return try e.useEarly(n, early, false, bottom0, pg.end);
            // (the block-end padding / border alone does not fit: Blink breaks before it)
            const push_end = inset_b > 0 and bottom - inset_b <= pg.end + eps and !e.heightDefinite(n) and e.style(n).display != .table_cell;
            return try e.setBreak(n, .span, @intFromBool(push_end), false, .last_resort, false, bottom0, pg.end);
        }

        /// A band of parallel flows (table cells, the items of a flex line / grid row) as one child.
        noinline fn probeBand(e: *Self, sq_i: u32, i: u32, j: u32, top: f32, band_top: f32, pg: Pg, requires: bool) Error!R {
            var agg: R = .{ .end = ninf, .mend = ninf };
            var k = i;
            while (k < j) : (k += 1) {
                const sq = &e.seqs.items[sq_i];
                const it = sq.items[k];
                if (!it.flow) continue;
                const c = it.node;
                const ct = e.itemTop(sq, k, top);
                const cl = e.lay(c);
                if (e.st[c].done) {
                    agg.end = @max(agg.end, ct + cl.h);
                    agg.mend = @max(agg.mend, ct + cl.h + @max(cl.margin.bottom, 0));
                    continue;
                }
                const rc = try e.probe(c, ct, pg, requires);
                const cb = e.style(c).breaks;
                agg.first = join(agg.first, join(rc.first, cb.before));
                agg.last = join(agg.last, join(rc.last, cb.after));
                var end = rc.end;
                if (rc.brk and !rc.par) {
                    agg.brk = true;
                    agg.forced = agg.forced or rc.forced;
                    agg.appeal = worse(agg.appeal, rc.appeal);
                    end = pg.end;
                } else if (!rc.brk and rc.end > pg.end + eps) {
                    // unbreakable and too tall: it stays where a break before it makes no progress, else
                    // it goes to the next page alone (a last resort unless it sits lower than its row)
                    const sep = ct > band_top + eps;
                    if (!(ct <= pg.start + eps or (requires and !sep))) {
                        e.slot[c] = .{ .stamp = e.stamp, .kind = .push, .brk = true };
                        agg.brk = true;
                        agg.appeal = worse(agg.appeal, if (sep) .perfect else .last_resort);
                        end = pg.end;
                    }
                }
                agg.end = @max(agg.end, end);
                agg.mend = @max(agg.mend, end + @max(cl.margin.bottom, 0));
            }
            if (agg.forced) agg.appeal = .perfect;
            return agg;
        }

        /// Index of the line that has `count` non-empty lines of `lines[from..]` before it.
        fn nthLine(lines: []const LineBox, from: u32, count: u32) u32 {
            var seen: u32 = 0;
            var i = from;
            while (i < lines.len) : (i += 1) {
                const empty = !(lines[i].bottom - lines[i].top > 0);
                if (empty) continue;
                if (seen == count) return i;
                seen += 1;
            }
            return @intCast(lines.len);
        }

        noinline fn probeText(e: *Self, n: u32, top: f32, pg: Pg, requires: bool) Error!R {
            const l = e.lay(n);
            const stt = &e.st[n];
            const bottom = top + l.h;
            const lines = e.linesOf(n);
            // (no line boxes: an image, or inline content that cannot be split)
            if (lines.len == 0) return .{ .end = bottom };
            const br = e.style(n).breaks;
            const widows: u32 = @max(br.widows, 1);
            const orphans: u32 = @max(br.orphans, 1);
            const start: u32 = if (stt.started) stt.@"resume" else 0;
            const shift = stt.shift;
            // Blink's line_count / first_overflowing_line_ (0 = none) / fit_all_lines_
            var lc: u32 = 0;
            var first_over: u32 = 0;
            var fit_all = false;
            var opp = false;
            var brk_line: u32 = no_node;
            var brk_appeal: Appeal = .perfect;
            var last_bottom: f32 = top + l.border.top + l.padding.top;
            var i = start;
            while (i < lines.len) : (i += 1) {
                const lt = top + lines[i].top + shift;
                const lb = top + lines[i].bottom + shift;
                const empty = !(lb - lt > 0);
                var appeal_before: Appeal = if (opp) .perfect else .last_resort;
                var mp: bool = undefined;
                if (pg.end - lt < -eps) {
                    mp = false;
                } else if (lt <= pg.start + eps or lb <= pg.end + eps) {
                    mp = true;
                } else mp = appeal_before == .last_resort and requires;
                if (!mp) {
                    var go_on = false;
                    if (lc != 0) {
                        if (first_over == 0) first_over = lc;
                        // (widows before an earlier break are orphans after it)
                        const min_lines = if (stt.started) @max(orphans, widows) else orphans;
                        if (lc < min_lines) {
                            appeal_before = worse(appeal_before, .violating_orphans_widows);
                        } else if (lc - first_over + 1 < widows or empty) {
                            // lay out on to find where to break so the next page gets its widows
                            go_on = true;
                        }
                        if (!go_on) fit_all = true;
                    }
                    if (!go_on) {
                        brk_line = i;
                        brk_appeal = appeal_before;
                        break;
                    }
                } else last_bottom = @max(last_bottom, lb);
                if (!empty) {
                    lc += 1;
                    opp = true;
                }
            }
            if (first_over != 0 and first_over < lc) {
                // every line that overflows has been seen: break so that `widows` lines move on, keeping
                // `orphans` (which wins)
                const ln = if (fit_all) first_over else @max(lc -| widows, @min(lc, orphans));
                brk_line = nthLine(lines, start, ln);
                brk_appeal = .perfect;
            }
            if (brk_line != no_node and brk_line < lines.len) return try e.setBreak(n, .line, brk_line, false, brk_appeal, false, bottom, pg.end);

            var r: R = .{ .end = bottom };
            const sl = &e.slot[n];
            if (lc >= 2 and first_over == 0) {
                // Blink's UpdateEarlyBreakBetweenLines
                var ln = @max(lc -| widows, @min(lc - 1, orphans));
                var ap: Appeal = .perfect;
                if (ln < orphans or lc - ln < widows) {
                    ln = lc - 1;
                    ap = .violating_orphans_widows;
                }
                sl.kind = .line;
                sl.arg = nthLine(lines, start, ln);
                r.early = true;
                r.early_appeal = ap;
            }
            if (bottom <= pg.end + eps) return r;
            const inset_b = l.padding.bottom + l.border.bottom;
            if (bottom > last_bottom + inset_b + eps) return try e.setBreak(n, .span, 0, false, .perfect, false, bottom, pg.end);
            if (r.early) return try e.setBreak(n, .line, sl.arg, false, .perfect, false, bottom, pg.end);
            return try e.setBreak(n, .span, 0, false, .last_resort, false, bottom, pg.end);
        }

        // ------------------------------------------------------------------------------------ apply

        fn applyTrim(e: *Self, n: u32) void {
            var cur = n;
            var guard: u32 = 0;
            while (guard < tr.max_depth + 8) : (guard += 1) {
                const sl = &e.slot[cur];
                if (sl.stamp != e.stamp or sl.brk or sl.trim == 0) return;
                const l = e.lay(cur);
                l.h = @max(l.h - sl.trim, 0);
                sl.trim = 0;
                // the cut margin is that of the last in-flow child, which may have been cut the same way
                const sq_i = e.st[cur].seq;
                if (sq_i == no_node) return;
                const sq = &e.seqs.items[sq_i];
                var p = sq.items.len;
                while (p > 0 and !sq.items[p - 1].flow) p -= 1;
                if (p == 0) return;
                cur = sq.items[p - 1].node;
            }
        }

        /// Where the content of `n` ends on the current page once its break is applied (for the repeated
        /// table footer). Call before `apply`.
        fn cutY(e: *Self, n: u32, top: f32, pg_end: f32) f32 {
            const sl = e.slot[n];
            if (sl.stamp != e.stamp or e.st[n].seq == no_node) return pg_end;
            const sq = &e.seqs.items[e.st[n].seq];
            if (sl.arg >= sq.items.len) return pg_end;
            switch (sl.kind) {
                .before => {
                    const reach = e.prevReach(sq, sl.arg, top, false);
                    return if (reach > ninf) @min(reach, pg_end) else @min(top, pg_end);
                },
                .inside => {
                    if (bandEnd(sq, sl.arg) != sl.arg + 1) return pg_end;
                    return e.cutY(sq.items[sl.arg].node, e.itemTop(sq, sl.arg, top), pg_end);
                },
                else => return pg_end,
            }
        }

        /// Applies the breakpoint `slot[n]` of the current page: moves what follows it to `pg.next`.
        /// Returns the growth of `n`'s block size.
        noinline fn apply(e: *Self, n: u32, top: f32, pg: Pg) Error!f32 {
            const sl = e.slot[n];
            const stt = &e.st[n];
            if (sl.stamp != e.stamp) return 0;
            switch (sl.kind) {
                .none, .push => return 0,
                .span => {
                    stt.started = true;
                    if (stt.seq != no_node) _ = e.prevReach(&e.seqs.items[stt.seq], @intCast(e.seqs.items[stt.seq].items.len), top, true);
                    if (sl.arg == 0) return 0;
                    // the block-end padding and border start the next page
                    const l = e.lay(n);
                    const g = @max(pg.next - (top + l.h - l.padding.bottom - l.border.bottom), 0);
                    l.h += g;
                    return g;
                },
                .line => return e.applyText(n, top, pg, sl.arg),
                .before, .inside => return e.applySeq(n, top, pg, sl),
            }
        }

        noinline fn applySeq(e: *Self, n: u32, top: f32, pg_in: Pg, sl: Slot) Error!f32 {
            const stt = &e.st[n];
            const sq_i = stt.seq;
            if (sq_i == no_node) return 0;
            const k = e.kindOf(n);
            const i = sl.arg;
            if (i >= e.seqs.items[sq_i].items.len) return 0;
            const j = bandEnd(&e.seqs.items[sq_i], i);
            var pg = pg_in;
            var next = pg_in.next;
            if (k == .table) {
                const info = e.tableInfo(n, &e.seqs.items[sq_i]);
                pg = e.tablePg(n, &info, pg_in);
                const past_hdr = info.hdr_block > 0 and i > info.hdr_idx;
                if (past_hdr) {
                    // the header goes at the start of the next page, the rows below it
                    next = pg.next;
                    try e.reps.append(e.a, .{ .node = info.hdr, .page = e.page + 1, .y = pg_in.next });
                } else pg.next = pg_in.next;
                // the footer follows the last row of the page (unless it is what moves on, or no row
                // of the table is on the page)
                if (info.ftr_block > 0 and i < info.ftr_idx and (sl.kind == .inside or e.prevReach(&e.seqs.items[sq_i], i, top, false) > ninf))
                    // (Blink's AddPendingRepeatedFooter: at the offset past the last row and its border spacing,
                    // at most where it ends exactly at the page end, i.e. the start of its reserved space)
                    try e.reps.append(e.a, .{ .node = info.ftr, .page = e.page, .y = @min(e.cutY(n, top, pg.end) + info.spacing, pg.end) });
            }
            var d: f32 = 0;
            if (sl.kind == .before) {
                const sq = &e.seqs.items[sq_i];
                const reach = e.prevReach(sq, i, top, true);
                const band_top = e.bandTop(sq, i, j, top);
                // content resumes at the page start, below what an earlier page left overflowing; the
                // margins (and row gap) adjoining an unforced break are truncated, any other distance
                // to the content before (clearance) stays; the margin after a forced break stays
                var gap: f32 = 0;
                if (sq.items[i].flow) gap = @max(e.lay(sq.items[i].node).margin.top, 0);
                var p = i;
                while (p > 0 and !sq.items[p - 1].flow) p -= 1;
                if (p > 0) gap = @max(gap, e.lay(sq.items[p - 1].node).margin.bottom);
                if (k == .bands) gap += @max(tr.resolveLp(e.style(n).gap[1], 0), 0);
                // (a column flex container never pulls an item up: Blink's flex fragmentation moves an
                // item down to the page start only when it began before it, so an item that the gap
                // carried past the page end keeps its distance; takumi golden paged-header-footer)
                const ns = e.style(n);
                if (k == .bands and ns.display == .flex and (ns.flex_direction == .column or ns.flex_direction == .column_reverse)) gap = 0;
                var target = @max(@max(next, reach), band_top - gap);
                if (sl.forced and sq.items[i].flow) {
                    // (a flex container keeps the row gap before an item resumed after a forced break:
                    // takumi / Blink's flex fragmentation offsets it from the break by its unfragmented offset)
                    var fgap: f32 = 0;
                    if (k == .bands and i > 0 and e.style(n).display == .flex) fgap = @max(tr.resolveLp(e.style(n).gap[1], 0), 0);
                    target = @max(next, reach) + @max(e.lay(sq.items[i].node).margin.top, 0) + fgap;
                }
                d = target - band_top;
                try e.lazyShift(sq_i, i, d);
                stt.child_inside = false;
                stt.forced_resume = sl.forced;
            } else {
                if (j == i + 1) {
                    const sq = &e.seqs.items[sq_i];
                    const c = sq.items[i].node;
                    d = try e.apply(c, e.itemTop(sq, i, top), pg);
                    // (a column flex container counts the block decorations a broken
                    // `box-decoration-break: clone` item clones as none of the item's content: the items
                    // after it move by its growth less them; takumi / Blink flex fragmentation
                    // `cloned_block_decorations`)
                    const ns = e.style(n);
                    if (k == .bands and e.style(c).breaks.clone and ns.display == .flex and (ns.flex_direction == .column or ns.flex_direction == .column_reverse)) {
                        const cl = e.lay(c);
                        d = @max(d - (cl.border.top + cl.border.bottom + cl.padding.top + cl.padding.bottom), 0);
                    }
                } else d = try e.applyBand(sq_i, i, j, top, pg);
                try e.lazyShift(sq_i, j, d);
                stt.child_inside = true;
            }
            stt.@"resume" = i;
            stt.started = true;
            return e.grow(n, sq_i, d);
        }

        noinline fn applyBand(e: *Self, sq_i: u32, i: u32, j: u32, top: f32, pg: Pg) Error!f32 {
            var old_bottom: f32 = ninf;
            var k = i;
            while (k < j) : (k += 1) {
                const sq = &e.seqs.items[sq_i];
                if (!sq.items[k].flow) continue;
                old_bottom = @max(old_bottom, e.itemTop(sq, k, top) + e.lay(sq.items[k].node).h);
            }
            var new_bottom: f32 = ninf;
            k = i;
            while (k < j) : (k += 1) {
                var sq = &e.seqs.items[sq_i];
                if (!sq.items[k].flow) continue;
                const c = sq.items[k].node;
                const ct = e.itemTop(sq, k, top);
                const cst = &e.st[c];
                cst.full = ct + e.lay(c).h >= old_bottom - eps;
                if (!cst.done) {
                    const cs = e.slot[c];
                    if (cs.stamp == e.stamp and cs.brk and !cs.par) {
                        if (cs.kind == .push) {
                            e.lay(c).y += @max(pg.next - ct, 0);
                            cst.full = false;
                        } else _ = try e.apply(c, ct, pg);
                    } else cst.done = true;
                }
                sq = &e.seqs.items[sq_i];
                new_bottom = @max(new_bottom, e.itemTop(sq, k, top) + e.lay(c).h);
            }
            const g = @max(new_bottom - old_bottom, 0);
            if (g > 0) {
                // the items that reached the end of the row keep reaching it (table cells, stretched items)
                k = i;
                while (k < j) : (k += 1) {
                    const sq = &e.seqs.items[sq_i];
                    if (!sq.items[k].flow) continue;
                    const c = sq.items[k].node;
                    if (!e.st[c].full or e.heightDefinite(c)) continue;
                    const cl = e.lay(c);
                    cl.h = @max(cl.h, new_bottom - e.itemTop(sq, k, top));
                }
            }
            return g;
        }

        fn grow(e: *Self, n: u32, sq_i: u32, d: f32) f32 {
            if (d == 0) return 0;
            const l = e.lay(n);
            const sq = &e.seqs.items[sq_i];
            l.content_h += d;
            var g: f32 = 0;
            if (!e.heightDefinite(n)) {
                if (sq.slack > 0) {
                    if (d <= sq.slack) {
                        sq.slack -= d;
                    } else {
                        g = d - sq.slack;
                        sq.slack = 0;
                    }
                } else g = d;
            }
            if (g == 0) return 0;
            if (l.h + g < 0) g = -l.h;
            l.h += g;
            if (sq.bottom_abs) {
                const ns = e.t.nodes.items;
                var ch = ns[n].first_child;
                while (ch != no_node) : (ch = ns[ch].next_sibling) {
                    const cs = &ns[ch].style;
                    if (cs.display != .none and cs.position == .absolute and cs.inset.top == .auto and cs.inset.bottom != .auto) e.lay(ch).y += g;
                }
            }
            return g;
        }

        noinline fn applyText(e: *Self, n: u32, top: f32, pg: Pg, k: u32) Error!f32 {
            const stt = &e.st[n];
            const l = e.lay(n);
            const lines = e.linesOf(n);
            stt.started = true;
            if (k >= lines.len) return 0;
            const old = stt.shift;
            const d = @max(pg.next - (top + lines[k].top + old), 0);
            stt.shift = old + d;
            stt.@"resume" = k;
            const nd = &e.t.nodes.items[n];
            if (d != 0 and !nd.measured) {
                // the inline-level boxes on the lines that move
                const cut = lines[k].top + old - eps;
                var ch = nd.first_child;
                while (ch != no_node) : (ch = e.t.nodes.items[ch].next_sibling) {
                    const cs = e.style(ch);
                    if (cs.display == .none) continue;
                    if (cs.position.isOut() and (cs.position == .fixed or cs.inset.top != .auto or cs.inset.bottom != .auto)) continue;
                    const cl = e.lay(ch);
                    if (cl.y + cl.h * 0.5 >= cut) cl.y += d;
                }
            }
            try e.shifts.append(e.a, .{ .node = n, .first_line = k, .dy = stt.shift });
            l.content_h += d;
            if (e.heightDefinite(n)) return 0;
            const ce = lines[lines.len - 1].bottom + stt.shift + l.padding.bottom + l.border.bottom;
            const g = @max(ce - l.h, 0);
            l.h += g;
            return g;
        }

        // ------------------------------------------------------------------------------------ driver

        /// Fragments the flow rooted at `f` over the pages from the one its block start is on.
        fn runFlow(e: *Self, f: u32) Error!void {
            const top = e.absTopOf(f);
            var page = try e.pageAt(top);
            while (true) {
                const pg = try e.window(page);
                e.stamp += 1;
                const r = try e.probe(f, top, pg, false);
                if (!r.brk) {
                    e.applyTrim(f);
                    break;
                }
                _ = try e.apply(f, top, pg);
                page += 1;
            }
            e.flush();
        }
        fn drain(e: *Self, qi: *[2]usize) Error!void {
            while (qi[0] < e.pushes.items.len or qi[1] < e.queue.items.len) {
                while (qi[0] < e.pushes.items.len) : (qi[0] += 1) {
                    const n = e.pushes.items[qi[0]];
                    const d = e.st[n].push_y - e.absTopOf(n);
                    if (d > 0) e.lay(n).y += d;
                    e.st[n].pushed = false;
                }
                if (qi[1] < e.queue.items.len) {
                    const n = e.queue.items[qi[1]];
                    qi[1] += 1;
                    // (a box the main flow went on to break itself is done)
                    if (!e.st[n].started) try e.runFlow(n);
                }
            }
        }
        fn push(e: *Self, n: u32, y: f32) Error!void {
            e.st[n].push_y = y;
            if (e.st[n].pushed) return;
            e.st[n].pushed = true;
            try e.pushes.append(e.a, n);
        }

        /// A float that neither fits nor breaks well moves to the next page on its own (Blink positions it
        /// in a parallel flow; the lines beside it are not re-flowed here).
        fn pushFloat(e: *Self, n: u32) Error!void {
            const top = e.absTopOf(n);
            const pg = try e.window(try e.pageAt(top));
            if (top <= pg.start + eps) return;
            e.stamp += 1;
            const r = try e.probe(n, top, pg, false);
            const l = e.lay(n);
            const fits = !r.brk and r.end <= pg.end + eps;
            if (fits or (r.brk and (r.forced or r.appeal == .perfect))) return;
            l.y += pg.next + @max(l.margin.top, 0) - top;
        }

        fn run(e: *Self, root: u32) Error!Pages {
            const ns = e.t.nodes.items;
            if (root >= ns.len) return .{};
            e.st = try e.a.alloc(State, ns.len);
            @memset(e.st, .{});
            e.slot = try e.a.alloc(Slot, ns.len);
            @memset(e.slot, .{});
            for (ns) |*nd| {
                if (nd.style.breaks.page != 0) e.any_names = true;
            }
            try e.tops.append(e.a, 0);
            try e.need(0);

            // 1. the main flow, 2. the flows it left behind, 3. floats and out-of-flow boxes (document order)
            try e.runFlow(root);
            var qi: [2]usize = .{ 0, 0 };
            try e.drain(&qi);
            if (ns[root].first_child != no_node and !ns[root].measured and ns[root].style.display != .none) {
                var cur = ns[root].first_child;
                walk: while (true) {
                    const s = &ns[cur].style;
                    const pk = e.kindOf(ns[cur].parent);
                    const is_abs = s.position == .absolute;
                    const is_float = floats_on and !is_abs and s.float != .none and (pk == .block or pk == .text);
                    var descend = s.display != .none and !ns[cur].measured and e.kindOf(cur) != .mono and (s.overflow_y == .visible or e.st[cur].started);
                    // (an atomic inline box is monolithic)
                    if (pk == .text and !is_abs and !is_float) descend = false;
                    if (s.display != .none) {
                        if (s.position == .fixed) {
                            try e.fixed.append(e.a, cur);
                            descend = false;
                        } else if (is_abs or is_float) {
                            if (is_float) try e.pushFloat(cur);
                            if (!e.st[cur].started) try e.runFlow(cur);
                            try e.drain(&qi);
                        }
                    }
                    if (descend and ns[cur].first_child != no_node) {
                        cur = ns[cur].first_child;
                        continue;
                    }
                    while (true) {
                        if (ns[cur].next_sibling != no_node) {
                            cur = ns[cur].next_sibling;
                            break;
                        }
                        cur = ns[cur].parent;
                        if (cur == root or cur == no_node) break :walk;
                    }
                }
            }
            if (tables_on) e.syncTables();

            // the pages: down to the block end of everything that paints
            var extent: f32 = 0;
            try e.extentOf(root, &extent);
            var count: u32 = 1;
            while (true) {
                try e.need(count - 1);
                if (!(e.tops.items[count] < extent - eps)) break;
                count += 1;
            }

            var out: Pages = .{};
            errdefer out.deinit(e.a);
            out.pages = try e.a.alloc(Page, count);
            for (out.pages, 0..) |*p, i| p.* = .{ .top = e.tops.items[i], .height = e.tops.items[i + 1] - e.tops.items[i] };
            out.names = try e.a.alloc(u32, count);
            for (out.names, 0..) |*nm, i| nm.* = e.names.items[i];
            std.sort.heap(LineShift, e.shifts.items, {}, shiftLess);
            out.line_shifts = try e.a.dupe(LineShift, e.shifts.items);
            var n_rep: usize = 0;
            for (e.reps.items) |r| n_rep += @intFromBool(r.page < count);
            n_rep += e.fixed.items.len * (count - 1);
            out.repeats = try e.a.alloc(Repeat, n_rep);
            var w: usize = 0;
            for (e.reps.items) |r| {
                if (r.page >= count) continue;
                out.repeats[w] = .{ .node = r.node, .page = r.page, .dy = r.y - e.absTopOf(r.node) };
                w += 1;
            }
            // a fixed box is laid out against the first page and painted on every page
            for (e.fixed.items) |f| {
                var p: u32 = 1;
                while (p < count) : (p += 1) {
                    out.repeats[w] = .{ .node = f, .page = p, .dy = e.tops.items[p] };
                    w += 1;
                }
            }
            std.sort.heap(Repeat, out.repeats, {}, repeatLess);
            return out;
        }

        /// Block end of everything painted in the subtree of `root` (clipped content and fixed boxes aside).
        fn extentOf(e: *Self, root: u32, extent: *f32) Error!void {
            const ns = e.t.nodes.items;
            const stack = try e.a.alloc(f32, tr.max_depth + 8);
            defer e.a.free(stack);
            var sp: usize = 0;
            var base: f32 = 0;
            var cur = root;
            while (true) {
                const s = &ns[cur].style;
                const l = e.lay(cur);
                var descend = false;
                if (s.display != .none and (s.position != .fixed or cur == root)) {
                    const y = base + l.y;
                    extent.* = @max(extent.*, y + l.h);
                    descend = !ns[cur].measured and (s.overflow_y == .visible or cur == root) and ns[cur].first_child != no_node and sp < stack.len;
                    if (descend) {
                        stack[sp] = base;
                        sp += 1;
                        base = y;
                        cur = ns[cur].first_child;
                        continue;
                    }
                }
                while (true) {
                    if (cur == root) return;
                    if (ns[cur].next_sibling != no_node) {
                        cur = ns[cur].next_sibling;
                        break;
                    }
                    cur = ns[cur].parent;
                    if (cur == no_node or sp == 0) return;
                    sp -= 1;
                    base = stack[sp];
                }
            }
        }

        /// Brings the paint geometry of the tables that were fragmented (`Tree.tableGeom`) in line with the
        /// moved rows (parts with a node of their own; anonymous rows / cells keep their geometry).
        fn syncTables(e: *Self) void {
            const ns = e.t.nodes.items;
            for (e.t.table_geoms.items) |*g| {
                if (g.node >= ns.len or e.st[g.node].seq == no_node) continue;
                g.grid_h += e.lay(g.node).h - e.seqs.items[e.st[g.node].seq].h0;
                for (g.secs) |*sec| {
                    if (sec.node == no_node or sec.node == g.node or ns[sec.node].parent != g.node) continue;
                    sec.y = e.lay(sec.node).y;
                    sec.h = e.lay(sec.node).h;
                }
                for (g.rows) |*row| {
                    if (row.node == no_node or row.node == g.node or row.sec >= g.secs.len) continue;
                    const sec = g.secs[row.sec];
                    const in_sec = sec.node != no_node and ns[row.node].parent == sec.node;
                    row.y = if (in_sec) e.lay(row.node).y else e.lay(row.node).y - sec.y;
                    row.h = e.lay(row.node).h;
                }
                for (g.cells) |*cell| {
                    if (cell.anon or cell.node == no_node or cell.node >= ns.len) continue;
                    var y: f32 = 0;
                    var cur = cell.node;
                    var guard: u32 = 0;
                    while (cur != g.node and cur != no_node and guard < 4) : (guard += 1) {
                        y += e.lay(cur).y;
                        cur = ns[cur].parent;
                    }
                    if (cur != g.node) continue;
                    cell.y = y;
                    cell.h = e.lay(cell.node).h;
                }
            }
        }
    };
}

fn shiftLess(_: void, a: LineShift, b: LineShift) bool {
    return if (a.node != b.node) a.node < b.node else a.first_line < b.first_line;
}
fn repeatLess(_: void, a: Repeat, b: Repeat) bool {
    return if (a.page != b.page) a.page < b.page else a.node < b.node;
}
fn itemLess(lays: []const tr.Layout, a: Item, b: Item) bool {
    const ya = lays[a.node].y;
    const yb = lays[b.node].y;
    return if (ya != yb) ya < yb else a.node < b.node;
}
