//! Pagination (fragment.zig). Most cases are ported from takumi-core's `layout/fragmentation_tests.rs`
//! (after Blink's `fragmentation_test.cc`) with the same page sizes and expected fragments: a box's
//! fragment on a page is its stitched border box cut by the page window. The takumi test each case comes
//! from is named in its comment.
const std = @import("std");
const L = @import("layout.zig");
const F = L.fragment;
const Style = L.Style;
const testing = std.testing;
const T = L.Tree;
const Id = L.NodeId;

const Placed = struct { page: u32, y: f32, h: f32 };
fn placed(page: u32, y: f32, h: f32) Placed {
    return .{ .page = page, .y = y, .h = h };
}

/// What a test box is made of (CSS initial values: static position, block display).
const O = struct {
    display: L.Display = .block,
    h: ?f32 = null,
    w: ?f32 = null,
    mt: f32 = 0,
    mb: f32 = 0,
    pt: f32 = 0,
    pb: f32 = 0,
    bt: f32 = 0,
    bb: f32 = 0,
    before: L.BreakBetween = .auto,
    after: L.BreakBetween = .auto,
    avoid: bool = false,
    pos: L.Position = .static,
    top: ?f32 = null,
    bottom: ?f32 = null,
    float: L.Float = .none,
    clear: L.Clear = .none,
    column: bool = false,
    overflow: L.Overflow = .visible,
    widows: u8 = 2,
    orphans: u8 = 2,
    min_h: ?f32 = null,
    hp: ?f32 = null,
    /// `Breaks.page`: a page name id (0 = auto)
    page: u32 = 0,
    /// `box-decoration-break: clone`
    clone: bool = false,
};

const Doc = struct {
    arena: std.heap.ArenaAllocator,
    t: T = undefined,
    /// line count per measured text node (0 = not text: an image of `img_h`)
    n_lines: [512]u16 = @splat(0),
    img_h: [512]f32 = @splat(0),
    line_h: f32 = 20,
    buf: [256]F.LineBox = undefined,
    pages: F.Pages = .{},
    page_heights: []const f32 = &.{},
    /// per page name id: the page height (named pages; overrides `page_heights`)
    name_heights: []const f32 = &.{},

    fn init(d: *Doc) void {
        d.* = .{ .arena = std.heap.ArenaAllocator.init(testing.allocator) };
        d.t = T.init(d.arena.allocator());
    }
    fn deinit(d: *Doc) void {
        d.arena.deinit();
    }
    fn style(o: O) Style {
        var s: Style = .{ .display = o.display, .position = o.pos };
        if (o.h) |v| s.size[1] = .{ .px = v };
        if (o.hp) |v| s.size[1] = .{ .percent = v };
        if (o.w) |v| s.size[0] = .{ .px = v };
        if (o.min_h) |v| s.min_size[1] = .{ .px = v };
        s.margin.top = .{ .px = o.mt };
        s.margin.bottom = .{ .px = o.mb };
        s.padding.top = .{ .px = o.pt };
        s.padding.bottom = .{ .px = o.pb };
        s.border.top = o.bt;
        s.border.bottom = o.bb;
        if (o.top) |v| s.inset.top = .{ .px = v };
        if (o.bottom) |v| s.inset.bottom = .{ .px = v };
        s.float = o.float;
        s.clear = o.clear;
        if (o.column) s.flex_direction = .column;
        s.overflow_x = o.overflow;
        s.overflow_y = o.overflow;
        s.breaks = .{ .before = o.before, .after = o.after, .avoid_inside = o.avoid, .widows = o.widows, .orphans = o.orphans, .page = o.page, .clone = o.clone };
        return s;
    }
    fn add(d: *Doc, parent: ?Id, o: O) Id {
        const n = d.t.addNode(style(o)) catch unreachable;
        if (parent) |p| d.t.appendChild(p, n) catch unreachable;
        return n;
    }
    /// A paragraph of `lines` lines of 20px.
    fn text(d: *Doc, parent: Id, lines: u16, o: O) Id {
        const n = d.add(parent, o);
        d.t.setMeasured(n, true);
        d.n_lines[n] = lines;
        return n;
    }
    /// An unbreakable replaced box `h` tall.
    fn image(d: *Doc, parent: Id, h: f32) Id {
        const n = d.add(parent, .{});
        d.t.setMeasured(n, true);
        d.img_h[n] = h;
        return n;
    }
    fn measure(ctx: *anyopaque, n: Id, known: [2]?f32, avail: [2]L.AvailableSpace) [2]f32 {
        const d: *Doc = @ptrCast(@alignCast(ctx));
        const w: f32 = known[0] orelse switch (avail[0]) {
            .definite => |v| v,
            else => 40,
        };
        const h = if (d.n_lines[n] != 0) @as(f32, @floatFromInt(d.n_lines[n])) * d.line_h else d.img_h[n];
        return .{ w, known[1] orelse h };
    }
    fn linesFn(ctx: *anyopaque, n: Id) []const F.LineBox {
        const d: *Doc = @ptrCast(@alignCast(ctx));
        const l = d.t.layout(n);
        const y0 = l.border.top + l.padding.top;
        const count = d.n_lines[n];
        for (d.buf[0..count], 0..) |*b, i| b.* = .{ .top = y0 + @as(f32, @floatFromInt(i)) * d.line_h, .bottom = y0 + @as(f32, @floatFromInt(i + 1)) * d.line_h };
        return d.buf[0..count];
    }
    fn heightFn(ctx: *anyopaque, page: u32, name: u32) f32 {
        const d: *Doc = @ptrCast(@alignCast(ctx));
        if (d.name_heights.len != 0) return d.name_heights[@min(name, d.name_heights.len - 1)];
        return d.page_heights[@min(page, d.page_heights.len - 1)];
    }
    /// Lays `root` out 300 wide and paginates it on pages `page_h` tall.
    fn run(d: *Doc, root: Id, page_h: f32) !void {
        return d.runMax(root, page_h, 20_000);
    }
    fn runMax(d: *Doc, root: Id, page_h: f32, max_pages: u32) !void {
        try d.t.compute(root, .{ .{ .definite = 300 }, .{ .definite = page_h } }, d, measure, .{});
        d.pages = try F.paginate(&d.t, d.arena.allocator(), root, .{
            .page_height = page_h,
            .page_height_fn = if (d.page_heights.len != 0 or d.name_heights.len != 0) heightFn else null,
            .lines_fn = linesFn,
            .ctx = d,
            .max_pages = max_pages,
        });
    }
    fn top(d: *Doc, n: Id) f32 {
        var y: f32 = 0;
        var cur = n;
        while (cur != L.tree.no_node) : (cur = d.t.nodes.items[cur].parent) y += d.t.layout(cur).y;
        return y;
    }
    /// The fragments of `n`: its border box cut by every page it reaches.
    fn frags(d: *Doc, n: Id, out: []Placed) []Placed {
        const y0 = d.top(n);
        const y1 = y0 + d.t.layout(n).h;
        var k: usize = 0;
        for (d.pages.pages, 0..) |p, i| {
            const s = @max(y0, p.top);
            const en = @min(y1, p.top + p.height);
            const hit = if (y1 > y0) en > s + 0.001 else (y0 >= p.top and y0 < p.top + p.height);
            if (!hit) continue;
            out[k] = .{ .page = @intCast(i), .y = s - p.top, .h = @max(en - s, 0) };
            k += 1;
        }
        return out[0..k];
    }
    fn expect(d: *Doc, n: Id, want: []const Placed) !void {
        var buf: [64]Placed = undefined;
        const got = d.frags(n, &buf);
        var ok = got.len == want.len;
        if (ok) for (got, want) |g, w| {
            if (g.page != w.page or @abs(g.y - w.y) > 0.02 or @abs(g.h - w.h) > 0.02) ok = false;
        };
        if (!ok) {
            std.debug.print("\nnode {d}: stitched y {d} h {d}\n  want:", .{ n, d.top(n), d.t.layout(n).h });
            for (want) |w| std.debug.print(" (p{d} y{d} h{d})", .{ w.page, w.y, w.h });
            std.debug.print("\n  got: ", .{});
            for (got) |g| std.debug.print(" (p{d} y{d} h{d})", .{ g.page, g.y, g.h });
            std.debug.print("\n", .{});
            return error.TestExpectedEqual;
        }
    }
    fn expectPages(d: *Doc, n: usize) !void {
        try testing.expectEqual(n, d.pages.pages.len);
    }
};

// takumi: a_block_that_reaches_past_the_page_end_continues_on_the_next
test "fragment: a block that reaches past the page end continues on the next" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const a = d.add(root, .{ .h = 100 });
    const b = d.add(root, .{ .h = 100 });
    const c = d.add(root, .{ .h = 100 });
    try d.run(root, 250);
    try d.expectPages(2);
    try d.expect(a, &.{placed(0, 0, 100)});
    try d.expect(b, &.{placed(0, 100, 100)});
    try d.expect(c, &.{ placed(0, 200, 50), placed(1, 0, 50) });
}

// named pages (css-page-3 §6, Blink): a change of used page name between block siblings forces a
// break; a page takes the name of the content it starts with, which sizes it
test "fragment: named pages break where the page name changes and size their pages" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    d.name_heights = &.{ 250, 100, 120 };
    const root = d.add(null, .{});
    const a = d.add(root, .{ .h = 50, .page = 1 });
    const b = d.add(root, .{ .h = 50 });
    const c = d.add(root, .{ .page = 2 });
    const c1 = d.add(c, .{ .h = 30 });
    const c2 = d.add(c, .{ .h = 30, .page = 2 });
    const e = d.add(root, .{ .h = 400 });
    try d.run(root, 250);
    try d.expectPages(5);
    try testing.expectEqualSlices(u32, &.{ 1, 0, 2, 0, 0 }, d.pages.names);
    try testing.expectEqualSlices(f32, &.{ 100, 250, 120, 250, 250 }, &.{ d.pages.pages[0].height, d.pages.pages[1].height, d.pages.pages[2].height, d.pages.pages[3].height, d.pages.pages[4].height });
    try d.expect(a, &.{placed(0, 0, 50)});
    try d.expect(b, &.{placed(1, 0, 50)});
    // (a child naming its parent's page again does not break)
    try d.expect(c1, &.{placed(2, 0, 30)});
    try d.expect(c2, &.{placed(2, 30, 30)});
    try d.expect(e, &.{ placed(3, 0, 250), placed(4, 0, 150) });
}

// takumi: break_inside_avoid_moves_a_block_to_the_next_page
test "fragment: break-inside avoid moves a block to the next page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 100 });
    _ = d.add(root, .{ .h = 100 });
    const c = d.add(root, .{ .h = 100, .avoid = true });
    try d.run(root, 250);
    try d.expect(c, &.{placed(1, 0, 100)});
    try d.expectPages(2);
}

// takumi: an_absolute_box_past_the_page_leaves_its_avoiding_containing_block_on_the_page
// (takumi also reports an empty second fragment of `c`; a stitched box has none)
test "fragment: an absolute box past the page leaves its avoiding containing block on the page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 100 });
    _ = d.add(root, .{ .h = 80 });
    const c = d.add(root, .{ .h = 50, .avoid = true, .pos = .relative });
    const abs = d.add(c, .{ .pos = .absolute, .top = 80, .h = 0 });
    try d.run(root, 250);
    try d.expectPages(2);
    try d.expect(c, &.{placed(0, 180, 50)});
    try d.expect(abs, &.{placed(1, 10, 0)});
}

// takumi: a_flex_container_whose_item_margin_overflows_the_page_moves_to_the_next
test "fragment: a flex container whose item margin overflows the page moves to the next" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 25 });
    const flex = d.add(root, .{ .display = .flex });
    const item = d.add(flex, .{ .mb = 25 });
    const inner = d.add(item, .{ .h = 161 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(flex, &.{placed(1, 0, 186)});
    try d.expect(inner, &.{placed(1, 0, 161)});
}

// takumi: a_forced_break_after_a_flex_items_last_child_breaks_after_the_container
test "fragment: a forced break after a flex item's last child breaks after the container" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const flex = d.add(root, .{ .display = .flex });
    const item = d.add(flex, .{});
    _ = d.add(item, .{ .h = 10, .after = .page });
    const next = d.add(root, .{ .h = 10 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(next, &.{placed(1, 0, 10)});
}

// takumi: a_forced_break_before_a_flex_items_first_child_breaks_before_the_container
test "fragment: a forced break before a flex item's first child breaks before the container" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 10 });
    const flex = d.add(root, .{ .display = .flex });
    const item = d.add(flex, .{});
    _ = d.add(item, .{ .h = 10, .before = .page });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(flex, &.{placed(1, 0, 10)});
}

// takumi: a_forced_break_after_a_grid_items_last_child_breaks_after_the_container
test "fragment: a forced break after a grid item's last child breaks after the container" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const grid = d.add(root, .{ .display = .grid });
    const item = d.add(grid, .{});
    _ = d.add(item, .{ .h = 10, .after = .page });
    const next = d.add(root, .{ .h = 10 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(next, &.{placed(1, 0, 10)});
}

// takumi: a_forced_break_after_a_table_row_in_a_flex_item_breaks_after_the_container
test "fragment: a forced break after a table row in a flex item breaks after the container" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const flex = d.add(root, .{ .display = .flex });
    const table = d.add(flex, .{ .display = .table });
    const body = d.add(table, .{ .display = .table_row_group });
    const row = d.add(body, .{ .display = .table_row, .after = .page });
    _ = d.add(row, .{ .display = .table_cell, .h = 10 });
    const next = d.add(root, .{ .h = 10 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(next, &.{placed(1, 0, 10)});
}

// takumi: a_floated_flex_item_is_an_item_that_breaks_after_as_any_other
test "fragment: a floated flex item is an item that breaks after as any other" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const flex = d.add(root, .{ .display = .flex, .column = true });
    _ = d.add(flex, .{ .h = 10, .float = .left, .after = .page });
    const second = d.add(flex, .{ .h = 10 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(second, &.{placed(1, 0, 10)});
}

// takumi: a_forced_break_after_a_box_whose_absolute_child_runs_on_puts_the_next_float_on_the_next_page
test "fragment: a forced break after a box whose absolute child runs on puts the next float on the next page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 110 });
    const rel = d.add(root, .{ .pos = .relative, .after = .page });
    const abs = d.add(rel, .{ .pos = .absolute, .top = 150, .h = 10 });
    const next = d.add(root, .{ .h = 10, .w = 10, .float = .left });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(next, &.{placed(1, 0, 10)});
    try d.expect(abs, &.{placed(1, 60, 10)});
}

// takumi: break_before_page_starts_a_block_on_a_new_page
test "fragment: break-before page starts a block on a new page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const a = d.add(root, .{ .h = 50 });
    const b = d.add(root, .{ .h = 50, .before = .page });
    try d.run(root, 250);
    try d.expectPages(2);
    try d.expect(a, &.{placed(0, 0, 50)});
    try d.expect(b, &.{placed(1, 0, 50)});
}

// takumi: a_margin_after_an_unforced_break_is_truncated
test "fragment: a margin after an unforced break is truncated, after a forced break it stays" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 240 });
    const b = d.add(root, .{ .h = 50, .mt = 30 });
    try d.run(root, 250);
    try d.expect(b, &.{placed(1, 0, 50)});
    try d.expectPages(2);

    // (Blink's AdjustMarginsForFragmentation keeps the block-start margin after a forced break)
    var d2: Doc = undefined;
    d2.init();
    defer d2.deinit();
    const root2 = d2.add(null, .{});
    _ = d2.add(root2, .{ .h = 40 });
    const b2 = d2.add(root2, .{ .h = 50, .mt = 30, .before = .page });
    try d2.run(root2, 250);
    try d2.expect(b2, &.{placed(1, 30, 50)});
}

// takumi: lines_split_between_pages_as_widows_ask
test "fragment: lines split between pages as widows ask" {
    if (!F.enabled) return error.SkipZigTest;
    for ([_]u8{ 2, 6 }) |widows| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        _ = d.add(root, .{ .h = 140 });
        const p = d.text(root, 8, .{ .widows = widows });
        try d.run(root, 200);
        if (widows == 2) {
            // three lines fit after the block, five follow
            try d.expect(p, &.{ placed(0, 140, 60), placed(1, 0, 100) });
            try testing.expectEqual(@as(usize, 1), d.pages.lineShifts(p).len);
            try testing.expectEqual(@as(u32, 3), d.pages.lineShifts(p)[0].first_line);
            try testing.expectEqual(@as(f32, 0), d.pages.lineDy(p, 2));
            try testing.expectEqual(@as(f32, 0), d.pages.lineDy(p, 7));
        } else {
            // six widows leave two lines on the first page
            try d.expect(p, &.{ placed(0, 140, 60), placed(1, 0, 120) });
            try testing.expectEqual(@as(u32, 2), d.pages.lineShifts(p)[0].first_line);
            try testing.expectEqual(@as(f32, 20), d.pages.lineDy(p, 2));
            try testing.expectEqual(@as(f32, 0), d.pages.lineDy(p, 1));
        }
    }
}

// takumi-pdf docs (pagination.mdx): a paragraph moves on when the page cannot hold its orphans
test "fragment: a paragraph that cannot keep its orphans moves to the next page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 170 });
    const p = d.text(root, 5, .{});
    try d.run(root, 200);
    // one line would fit: orphans (2) send the paragraph to the next page
    try d.expect(p, &.{placed(1, 0, 100)});
    try testing.expectEqual(@as(usize, 0), d.pages.line_shifts.len);

    // with `orphans: 1` the line stays, and `widows` still holds
    var d2: Doc = undefined;
    d2.init();
    defer d2.deinit();
    const root2 = d2.add(null, .{});
    _ = d2.add(root2, .{ .h = 170 });
    const p2 = d2.text(root2, 5, .{ .orphans = 1 });
    try d2.run(root2, 200);
    try d2.expect(p2, &.{ placed(0, 170, 30), placed(1, 0, 80) });
    try testing.expectEqual(@as(f32, 10), d2.pages.lineDy(p2, 1));
}

// docs: "If a paragraph is too short to satisfy both, orphans wins"
test "fragment: orphans win over widows in a short paragraph" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 160 });
    const p = d.text(root, 3, .{});
    try d.run(root, 200);
    // two lines fit; the single widow is accepted
    try d.expect(p, &.{ placed(0, 160, 40), placed(1, 0, 20) });
    try testing.expectEqual(@as(u32, 2), d.pages.lineShifts(p)[0].first_line);
}

// takumi: lines_that_ended_stay_on_their_page_in_a_stretched_box
test "fragment: lines that ended stay on their page in a stretched box" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const flex = d.add(root, .{ .display = .flex });
    _ = d.add(flex, .{ .h = 600, .w = 100 });
    const p = d.text(flex, 1, .{});
    try d.run(root, 200);
    try d.expectPages(3);
    try d.expect(p, &.{ placed(0, 0, 200), placed(1, 0, 200), placed(2, 0, 200) });
    try testing.expectEqual(@as(usize, 0), d.pages.line_shifts.len);
}

// takumi: a_sliced_box_leaves_its_border_out_where_it_breaks (the stitched box keeps its borders: the
// page clip leaves them out at the break)
test "fragment: a sliced box spans the break with its borders at its two ends" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 100 });
    const b = d.add(root, .{ .h = 200, .bt = 5, .bb = 5, .pt = 4, .pb = 4 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(b, &.{ placed(0, 100, 100), placed(1, 0, 100) });
    try testing.expectEqual(@as(f32, 5), d.t.layout(b).border.top);
    try testing.expectEqual(@as(f32, 5), d.t.layout(b).border.bottom);
    // what a painter asks: the piece on each page, and which of its ends are cut
    const f0 = d.pages.boxOnPage(0, d.top(b), d.t.layout(b).h).?;
    const f1 = d.pages.boxOnPage(1, d.top(b), d.t.layout(b).h).?;
    try testing.expect(f0.y == 100 and f0.h == 100 and !f0.from_prev and f0.to_next);
    try testing.expect(f1.y == 0 and f1.h == 100 and f1.from_prev and !f1.to_next);
    try testing.expect(d.pages.boxOnPage(1, 0, 100) == null and d.pages.boxOnPage(2, 0, 100) == null);
}

// takumi-pdf 0.20.0 (probe pagination.box-decoration-break.block): with `clone` the content breaks
// above the block-end border and padding every fragment repeats, and resumes below the block-start
// ones on the next page; with `slice` it runs to the page end
test "fragment: box-decoration-break clone repeats the decorations around each fragment's content" {
    if (!F.enabled) return error.SkipZigTest;
    for ([_]bool{ true, false }) |clone| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        _ = d.add(root, .{ .h = 100 });
        const box = d.add(root, .{ .bt = 10, .bb = 10, .clone = clone });
        const txt = d.text(box, 10, .{});
        try d.run(root, 200);
        if (clone) {
            // lines 0-3 end at 190 (the page end less the 10px border), line 4 resumes at 200 + 10
            try testing.expectEqual(@as(f32, 0), d.pages.lineDy(txt, 3));
            try testing.expectEqual(@as(f32, 20), d.pages.lineDy(txt, 4));
            try testing.expectEqual(@as(f32, 240), d.t.layout(box).h);
        } else {
            try testing.expectEqual(@as(f32, 10), d.pages.lineDy(txt, 4));
            try testing.expectEqual(@as(f32, 230), d.t.layout(box).h);
        }
    }
}

// takumi-pdf 0.20.0 (probe tagging.paged.forced-breaks): after a forced break before an empty box
// the margins collapsed through it no longer collapse with those above: the next box keeps its
// block-start margin below it
test "fragment: a forced break before an empty box keeps the margin of the box after it" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 50, .mb = 16 });
    const empty = d.add(root, .{ .before = .page });
    const after = d.add(root, .{ .h = 20, .mt = 16 });
    try d.run(root, 200);
    try d.expect(empty, &.{placed(1, 0, 0)});
    try d.expect(after, &.{placed(1, 16, 20)});
}

// takumi-pdf 0.20.0 (probe pagination.table.tfoot-repeat): a table whose repeated footer ends exactly
// at the page end fits the page
test "fragment: a table that fits with its repeated footer stays on the page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const table = d.add(root, .{ .display = .table });
    const body = d.add(table, .{ .display = .table_row_group });
    for (0..8) |_| {
        const r = d.add(body, .{ .display = .table_row });
        _ = d.add(d.add(r, .{ .display = .table_cell }), .{ .h = 20 });
    }
    const foot = d.add(table, .{ .display = .table_footer_group, .avoid = true });
    _ = d.add(d.add(d.add(foot, .{ .display = .table_row }), .{ .display = .table_cell }), .{ .h = 40 });
    try d.run(root, 200);
    try d.expectPages(1);
    try d.expect(foot, &.{placed(0, 160, 40)});
}

fn tableOf(d: *Doc, root: Id, rows: []Id, cells: []Id, h: f32, row_avoid: bool) Id {
    const table = d.add(root, .{ .display = .table });
    for (rows, cells) |*r, *c| {
        r.* = d.add(table, .{ .display = .table_row, .avoid = row_avoid });
        const td = d.add(r.*, .{ .display = .table_cell });
        c.* = d.add(td, .{ .h = h });
    }
    return table;
}

// takumi: a_table_row_breaks_inside_unless_it_avoids_it
test "fragment: a table row breaks inside unless it avoids it" {
    if (!F.enabled) return error.SkipZigTest;
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        var rows: [5]Id = undefined;
        var cells: [5]Id = undefined;
        const table = tableOf(&d, root, &rows, &cells, 60, false);
        try d.run(root, 200);
        // the fourth row's cell content breaks, and the row with it
        try d.expectPages(2);
        try d.expect(rows[3], &.{ placed(0, 180, 20), placed(1, 0, 40) });
        try d.expect(table, &.{ placed(0, 0, 200), placed(1, 0, 100) });
    }
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        var rows: [5]Id = undefined;
        var cells: [5]Id = undefined;
        const table = tableOf(&d, root, &rows, &cells, 60, true);
        try d.run(root, 200);
        try d.expect(rows[2], &.{placed(0, 120, 60)});
        try d.expect(rows[3], &.{placed(1, 0, 60)});
        try d.expect(rows[4], &.{placed(1, 60, 60)});
        try d.expect(table, &.{ placed(0, 0, 200), placed(1, 0, 120) });
        // the paint geometry of the table follows the rows
        const g = d.t.tableGeom(table).?;
        try testing.expectEqual(@as(f32, 200), g.rows[3].y + g.secs[g.rows[3].sec].y);
        try testing.expectEqual(@as(f32, 200), g.cells[g.rows[3].first].y);
        try testing.expectEqual(@as(f32, 320), g.grid_h);
    }
}

// takumi: a_tall_cell_breaks_its_row_across_pages
test "fragment: a tall cell breaks its row across pages" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    var rows: [1]Id = undefined;
    var cells: [1]Id = undefined;
    _ = tableOf(&d, root, &rows, &cells, 300, false);
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(rows[0], &.{ placed(0, 0, 200), placed(1, 0, 100) });
    try d.expect(cells[0], &.{ placed(0, 0, 200), placed(1, 0, 100) });
}

// takumi: a_top_caption_comes_before_the_rows_it_breaks_with
test "fragment: a top caption comes before the rows it breaks with" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const table = d.add(root, .{ .display = .table });
    const caption = d.add(table, .{ .display = .table_caption, .h = 40 });
    const body = d.add(table, .{ .display = .table_row_group });
    var rows: [3]Id = undefined;
    for (&rows) |*r| {
        r.* = d.add(body, .{ .display = .table_row });
        const td = d.add(r.*, .{ .display = .table_cell });
        _ = d.add(td, .{ .h = 60 });
    }
    try d.run(root, 150);
    try d.expect(caption, &.{placed(0, 0, 40)});
    try d.expect(rows[0], &.{placed(0, 40, 60)});
    try d.expect(rows[1], &.{ placed(0, 100, 50), placed(1, 0, 10) });
}

const Groups = struct { table: Id, thead: Id, h: Id, tfoot: Id, f: Id, rows: [5]Id };
/// takumi's `table_with_groups`: a header group, a body of five 60px rows that avoid breaking and,
/// with `footer`, a footer group.
fn tableWithGroups(d: *Doc, root: Id, head_avoid: bool, head_h: f32, footer: bool) Groups {
    var g: Groups = undefined;
    g.table = d.add(root, .{ .display = .table });
    g.thead = d.add(g.table, .{ .display = .table_header_group, .avoid = head_avoid });
    g.h = d.add(g.thead, .{ .display = .table_row });
    _ = d.add(d.add(g.h, .{ .display = .table_cell }), .{ .h = head_h });
    const body = d.add(g.table, .{ .display = .table_row_group });
    for (&g.rows) |*r| {
        r.* = d.add(body, .{ .display = .table_row, .avoid = true });
        _ = d.add(d.add(r.*, .{ .display = .table_cell }), .{ .h = 60 });
    }
    g.tfoot = L.tree.no_node;
    g.f = L.tree.no_node;
    if (footer) {
        g.tfoot = d.add(g.table, .{ .display = .table_footer_group, .avoid = true });
        g.f = d.add(g.tfoot, .{ .display = .table_row });
        _ = d.add(d.add(g.f, .{ .display = .table_cell }), .{ .h = 20 });
    }
    return g;
}
/// The fragments of a repeated group: where it is, and where its repeats paint it.
fn expectWithRepeats(d: *Doc, n: Id, want: []const Placed) !void {
    var buf: [64]Placed = undefined;
    var got = d.frags(n, &buf).len;
    const y0 = d.top(n);
    const h = d.t.layout(n).h;
    for (d.pages.repeats) |r| {
        if (r.node != n) continue;
        buf[got] = .{ .page = r.page, .y = y0 + r.dy - d.pages.pages[r.page].top, .h = h };
        got += 1;
    }
    std.mem.sort(Placed, buf[0..got], {}, struct {
        fn lt(_: void, a: Placed, b: Placed) bool {
            return a.page < b.page;
        }
    }.lt);
    var ok = got == want.len;
    if (ok) for (buf[0..got], want) |g, w| {
        if (g.page != w.page or @abs(g.y - w.y) > 0.02 or @abs(g.h - w.h) > 0.02) ok = false;
    };
    if (!ok) {
        std.debug.print("\nnode {d} with repeats: got", .{n});
        for (buf[0..got]) |g| std.debug.print(" (p{d} y{d} h{d})", .{ g.page, g.y, g.h });
        std.debug.print("\n", .{});
        return error.TestExpectedEqual;
    }
}

// takumi: a_short_table_header_repeats_on_every_page
test "fragment: a short table header repeats on every page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const g = tableWithGroups(&d, root, true, 20, false);
    try d.run(root, 200);
    try d.expectPages(2);
    try expectWithRepeats(&d, g.thead, &.{ placed(0, 0, 20), placed(1, 0, 20) });
    try expectWithRepeats(&d, g.h, &.{placed(0, 0, 20)});
    try d.expect(g.rows[2], &.{placed(0, 140, 60)});
    try d.expect(g.rows[3], &.{placed(1, 20, 60)});
}

// takumi: a_table_header_repeats_only_when_it_avoids_breaks_and_is_short
test "fragment: a table header repeats only when it avoids breaks and is short" {
    if (!F.enabled) return error.SkipZigTest;
    for ([_]bool{ false, true }) |tall| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        // not avoiding breaks / avoiding them but 80 tall (more than a quarter of the page)
        const g = tableWithGroups(&d, root, tall, if (tall) 80 else 20, false);
        try d.run(root, 200);
        for (d.pages.repeats) |r| try testing.expect(r.node != g.thead);
        try testing.expect(d.pages.pages.len >= 2);
    }
}

// takumi: a_short_table_footer_repeats_at_the_end_of_every_page
test "fragment: a short table footer repeats at the end of every page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const g = tableWithGroups(&d, root, true, 20, true);
    try d.run(root, 200);
    // the header and footer take 40px of each page, so two rows fit on each, and the footer follows
    // the last row on the page
    try d.expectPages(3);
    try d.expect(g.rows[1], &.{placed(0, 80, 60)});
    try d.expect(g.rows[2], &.{placed(1, 20, 60)});
    try d.expect(g.rows[4], &.{placed(2, 20, 60)});
    try expectWithRepeats(&d, g.tfoot, &.{ placed(0, 140, 20), placed(1, 140, 20), placed(2, 80, 20) });
    try expectWithRepeats(&d, g.thead, &.{ placed(0, 0, 20), placed(1, 0, 20), placed(2, 0, 20) });
}

// takumi: an_absolute_box_taller_than_a_page_breaks_across_pages
test "fragment: an absolute box taller than a page breaks across pages" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const container = d.add(root, .{ .pos = .relative });
    const abs = d.add(container, .{ .pos = .absolute, .top = 0, .h = 300 });
    _ = d.add(root, .{ .h = 300 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(abs, &.{ placed(0, 0, 200), placed(1, 0, 100) });
}

// takumi: an_absolute_box_at_the_bottom_waits_for_the_last_fragment_of_its_containing_block
test "fragment: an absolute box at the bottom waits for the last fragment of its containing block" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const container = d.add(root, .{ .pos = .relative });
    const abs = d.add(container, .{ .pos = .absolute, .bottom = 0, .h = 50 });
    _ = d.add(container, .{ .h = 300 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(abs, &.{placed(1, 50, 50)});
}

// (the same once a break has made the containing block taller)
test "fragment: an absolute box at the bottom follows its containing block when a break grows it" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const container = d.add(root, .{ .pos = .relative });
    const abs = d.add(container, .{ .pos = .absolute, .bottom = 0, .h = 10 });
    _ = d.add(container, .{ .h = 150 });
    _ = d.add(container, .{ .h = 100, .avoid = true });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(container, &.{ placed(0, 0, 200), placed(1, 0, 100) });
    try d.expect(abs, &.{placed(1, 90, 10)});
}

// takumi: an_absolute_box_as_tall_as_its_containing_block_covers_all_its_pages
test "fragment: an absolute box as tall as its containing block covers all its pages" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const container = d.add(root, .{ .pos = .relative });
    const abs = d.add(container, .{ .pos = .absolute, .top = 0, .hp = 1 });
    _ = d.add(container, .{ .h = 300 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(abs, &.{ placed(0, 0, 200), placed(1, 0, 100) });
}

// takumi: an_absolute_box_past_the_last_page_adds_pages
test "fragment: an absolute box past the last page adds pages" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const body = d.add(root, .{});
    const abs = d.add(body, .{ .pos = .absolute, .top = 0, .h = 500 });
    try d.run(root, 200);
    try d.expectPages(3);
    try d.expect(abs, &.{ placed(0, 0, 200), placed(1, 0, 200), placed(2, 0, 100) });
}

// takumi: a_fixed_box_repeats_on_every_page
test "fragment: a fixed box repeats on every page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const body = d.add(root, .{});
    const fixed = d.add(body, .{ .pos = .fixed, .top = 10, .h = 20 });
    _ = d.add(body, .{ .h = 500 });
    try d.run(root, 200);
    try d.expectPages(3);
    try expectWithRepeats(&d, fixed, &.{ placed(0, 10, 20), placed(1, 10, 20), placed(2, 10, 20) });
    try testing.expectEqual(@as(usize, 1), d.pages.repeatsOf(1).len);
    try testing.expectEqual(@as(usize, 0), d.pages.repeatsOf(0).len);
}

// takumi: a_fixed_box_repeats_on_the_pages_an_absolute_box_adds
test "fragment: a fixed box repeats on the pages an absolute box adds" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const body = d.add(root, .{});
    const fixed = d.add(body, .{ .pos = .fixed, .top = 10, .h = 20 });
    _ = d.add(body, .{ .pos = .absolute, .top = 0, .h = 500 });
    try d.run(root, 200);
    try d.expectPages(3);
    try expectWithRepeats(&d, fixed, &.{ placed(0, 10, 20), placed(1, 10, 20), placed(2, 10, 20) });
}

// takumi: an_absolute_box_inside_a_clipping_box_adds_no_pages
test "fragment: an absolute box inside a clipping box adds no pages" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const body = d.add(root, .{});
    const clip = d.add(body, .{ .pos = .absolute, .overflow = .clip, .w = 10, .h = 10 });
    _ = d.add(clip, .{ .pos = .absolute, .h = 700 });
    try d.run(root, 200);
    try d.expectPages(1);
}

// takumi: a_resumed_float_drops_its_block_start_margin
test "fragment: a float taller than a page breaks across pages, keeping its margin at its start only" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const float = d.add(root, .{ .float = .left, .w = 50, .h = 300, .mt = 30 });
    try d.run(root, 200);
    try d.expect(float, &.{ placed(0, 30, 170), placed(1, 0, 130) });
}

// takumi: a_forced_break_before_an_absolute_box_moves_its_static_position_to_the_next_page
test "fragment: a forced break before an absolute box moves its static position to the next page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const wrap = d.add(root, .{});
    _ = d.add(wrap, .{ .h = 20, .after = .page });
    const abs = d.add(wrap, .{ .pos = .absolute, .w = 10, .h = 10 });
    try d.run(root, 200);
    try d.expect(abs, &.{placed(1, 0, 10)});
}

// takumi: a_forced_break_before_a_float_leaves_the_container_unbroken_by_inflow_content
test "fragment: a forced break before a float leaves the container unbroken by in-flow content" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const wrap = d.add(root, .{ .bb = 10 });
    _ = d.add(wrap, .{ .h = 20, .after = .page });
    const float = d.add(wrap, .{ .float = .left, .w = 50, .h = 20 });
    try d.run(root, 200);
    try d.expect(float, &.{placed(1, 0, 20)});
    // the float breaks in a parallel flow, so the container keeps its block-end border on the first page
    try d.expect(wrap, &.{placed(0, 0, 30)});
}

// takumi: a_float_taller_than_a_page_breaks_across_pages
test "fragment: a float taller than a page breaks across pages" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const float = d.add(root, .{ .float = .left, .w = 50, .h = 300 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(float, &.{ placed(0, 0, 200), placed(1, 0, 100) });
}

// takumi: a_float_that_avoids_breaking_moves_to_the_next_page_alone
test "fragment: a float that avoids breaking moves to the next page alone" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 150 });
    const float = d.add(root, .{ .float = .left, .w = 50, .h = 80, .avoid = true });
    const b = d.add(root, .{ .h = 20 });
    try d.run(root, 200);
    try d.expect(float, &.{placed(1, 0, 80)});
    // the float flows in parallel, so the block after it stays on the first page
    try d.expect(b, &.{placed(0, 150, 20)});
}

// takumi: a_block_that_clears_a_broken_float_follows_it_to_the_next_page
test "fragment: a block that clears a broken float follows it to the next page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .float = .left, .w = 50, .h = 300 });
    const c = d.add(root, .{ .h = 20, .clear = .both });
    try d.run(root, 200);
    try d.expect(c, &.{placed(1, 100, 20)});
}

/// takumi's `page_area_fragments`: a body of an absolute box laid out before `content_h` of content.
fn pageArea(d: *Doc, top: ?f32, bottom: ?f32, h: f32, content_h: f32) !Id {
    const root = d.add(null, .{});
    const body = d.add(root, .{});
    const abs = d.add(body, .{ .pos = .absolute, .top = top, .bottom = bottom, .h = h });
    _ = d.add(body, .{ .h = content_h });
    try d.run(root, 200);
    return abs;
}

// takumi: an_initial_containing_block_box_below_the_page_moves_to_the_page_it_is_on
// takumi: an_initial_containing_block_box_past_the_root_adds_pages
// takumi: an_initial_containing_block_box_taller_than_a_page_breaks_across_pages
// takumi: an_initial_containing_block_box_taller_than_a_page_resumes_in_the_root_fragment_of_its_page
// takumi: a_box_at_the_bottom_of_the_initial_containing_block_sits_at_the_bottom_of_the_first_page
test "fragment: boxes positioned by the page area" {
    if (!F.enabled) return error.SkipZigTest;
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const abs = try pageArea(&d, 250, null, 50, 300);
        try d.expectPages(2);
        try d.expect(abs, &.{placed(1, 50, 50)});
    }
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const abs = try pageArea(&d, 850, null, 50, 20);
        try d.expectPages(5);
        try d.expect(abs, &.{placed(4, 50, 50)});
    }
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const abs = try pageArea(&d, 0, null, 450, 20);
        try d.expectPages(3);
        try d.expect(abs, &.{ placed(0, 0, 200), placed(1, 0, 200), placed(2, 0, 50) });
    }
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const abs = try pageArea(&d, 150, null, 300, 300);
        try d.expectPages(3);
        try d.expect(abs, &.{ placed(0, 150, 50), placed(1, 0, 200), placed(2, 0, 50) });
    }
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const abs = try pageArea(&d, null, 0, 50, 300);
        try d.expectPages(2);
        try d.expect(abs, &.{placed(0, 150, 50)});
    }
}

// takumi: paged_layout_stops_at_its_page_limit
test "fragment: paged layout stops at its page limit" {
    if (!F.enabled) return error.SkipZigTest;
    for ([_]u32{ 3, 2 }) |limit| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        _ = d.add(root, .{ .h = 100 });
        _ = d.add(root, .{ .h = 100, .before = .page });
        _ = d.add(root, .{ .h = 100, .before = .page });
        if (limit == 3) {
            try d.runMax(root, 200, 3);
            try d.expectPages(3);
        } else try testing.expectError(error.TooManyPages, d.runMax(root, 200, 2));
    }
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .pos = .absolute, .top = 1000, .h = 10 });
    try testing.expectError(error.TooManyPages, d.runMax(root, 200, 4));
}

// takumi: a_page_without_area_fails_and_an_unlaid_page_reaches_nothing
test "fragment: a page without area fails" {
    if (!F.enabled) return error.SkipZigTest;
    const heights = [_][]const f32{ &.{ 200, 0 }, &.{std.math.floatMax(f32)}, &.{ 16_777_216, 1 } };
    for (heights) |hs| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        _ = d.add(root, .{ .h = 100 });
        _ = d.add(root, .{ .h = 100, .before = .page });
        d.page_heights = hs;
        try testing.expectError(error.InvalidPageSize, d.run(root, 200));
    }
}

// takumi-pdf pagination.rs: first_left_and_right_frames_size_their_own_pages (page areas 200, 120, 160,
// 120, 160 ... tall; forty lines of 20px)
test "fragment: pages of different heights" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    var lines: [40]Id = undefined;
    for (&lines) |*l| l.* = d.add(root, .{ .h = 20 });
    d.page_heights = &.{ 200, 120, 160, 120, 160, 120, 160, 120, 160, 120, 160 };
    try d.run(root, 200);
    const want = [_][2]f32{ .{ 0, 200 }, .{ 200, 320 }, .{ 320, 480 }, .{ 480, 600 }, .{ 600, 760 } };
    for (want, 0..) |w, i| {
        try testing.expectEqual(w[0], d.pages.pages[i].top);
        try testing.expectEqual(w[1], d.pages.pages[i].top + d.pages.pages[i].height);
    }
    try d.expect(lines[10], &.{placed(1, 0, 20)});
    try d.expect(lines[16], &.{placed(2, 0, 20)});
    try testing.expectEqual(@as(usize, 6), d.pages.pages.len);
}

// docs (pagination.mdx): "A text line or an image never splits. It moves to the next page, and when it
// is taller than a page it runs on over the pages after it." What follows it in the same container
// starts the next page, over it (takumi-pdf 0.20.0: the monolithic overflow of the root's or a
// container's own child does not carry over; probe pagination.monolithic.taller-than-page).
test "fragment: monolithic content moves to the next page, and runs on when taller than a page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 150 });
    const img = d.image(root, 100);
    const tall = d.image(root, 450);
    const after = d.add(root, .{ .h = 30 });
    try d.run(root, 200);
    try d.expect(img, &.{placed(1, 0, 100)});
    // it does not fit the rest of page 2 either: it starts page 3 and runs on over the page after
    try d.expect(tall, &.{ placed(2, 0, 200), placed(3, 0, 200) });
    // what follows starts the next page, and the overflow adds no page
    try d.expect(after, &.{placed(3, 0, 30)});
    try d.expectPages(4);
}

// takumi-pdf 0.20.0 (probe pagination.monolithic.taller-than-page and its variants): a box that ends
// with monolithic content overflowing the page carries the overflow to the content after it; one
// level deeper, or with block-end padding, it does not.
test "fragment: the overflow of monolithic content carries over through the box that ends with it" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const wrap = d.add(root, .{});
    _ = d.image(wrap, 360);
    const after = d.add(root, .{ .h = 20 });
    try d.run(root, 180);
    try d.expect(after, &.{placed(2, 0, 20)});

    var d2: Doc = undefined;
    d2.init();
    defer d2.deinit();
    const root2 = d2.add(null, .{});
    const outer = d2.add(root2, .{});
    const mid = d2.add(outer, .{});
    const inner = d2.add(mid, .{});
    _ = d2.image(inner, 360);
    const after2 = d2.add(outer, .{ .h = 20 });
    try d2.run(root2, 180);
    try d2.expect(after2, &.{placed(1, 0, 20)});
}

// Blink's AdjustedMarginAfterFinalChildFragment: a trailing margin does not reach into the next page
test "fragment: a trailing margin at the page end adds no page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const wrap = d.add(root, .{ .display = .block });
    _ = d.add(wrap, .{ .h = 190, .mb = 30 });
    try d.run(root, 200);
    try d.expectPages(1);

    // and the next block starts the next page without it
    var d2: Doc = undefined;
    d2.init();
    defer d2.deinit();
    const root2 = d2.add(null, .{});
    _ = d2.add(root2, .{ .h = 190, .mb = 30 });
    const b = d2.add(root2, .{ .h = 50 });
    try d2.run(root2, 200);
    try d2.expect(b, &.{placed(1, 0, 50)});
    try d2.expectPages(2);
}

// Blink early breaks: `break-after: avoid` on a heading keeps it with what follows
test "fragment: break-after avoid takes a box along to the next page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 150 });
    const heading = d.add(root, .{ .h = 30, .after = .avoid });
    const body = d.add(root, .{ .h = 60, .avoid = true });
    try d.run(root, 200);
    try d.expect(heading, &.{placed(1, 0, 30)});
    try d.expect(body, &.{placed(1, 30, 60)});
}

// Blink's UpdateEarlyBreakBetweenLines: with nothing better, the lines before give up their last ones
test "fragment: a box that must stay with a paragraph takes the paragraph's last lines along" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const p = d.text(root, 8, .{});
    const kept = d.add(root, .{ .h = 60, .avoid = true, .before = .avoid });
    try d.run(root, 200);
    // breaking before `kept` violates its break-before: avoid; between the lines is perfect (widows 2)
    try d.expect(p, &.{ placed(0, 0, 200), placed(1, 0, 40) });
    try testing.expectEqual(@as(u32, 6), d.pages.lineShifts(p)[0].first_line);
    try d.expect(kept, &.{placed(1, 40, 60)});
}

// nested breaks: content inside nested blocks, padding and auto heights
test "fragment: a break inside nested blocks grows the boxes around it" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const outer = d.add(root, .{ .pt = 10, .pb = 10 });
    const inner = d.add(outer, .{});
    _ = d.add(inner, .{ .h = 150 });
    const b = d.add(inner, .{ .h = 100, .avoid = true });
    const tail = d.add(root, .{ .h = 20 });
    try d.run(root, 200);
    try d.expect(b, &.{placed(1, 0, 100)});
    try d.expect(inner, &.{ placed(0, 10, 190), placed(1, 0, 100) });
    try d.expect(outer, &.{ placed(0, 0, 200), placed(1, 0, 110) });
    try d.expect(tail, &.{placed(1, 110, 20)});
    try d.expectPages(2);
}

// a min-height box absorbs the push of a break in its free space
test "fragment: free space below the content absorbs a break" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const box = d.add(root, .{ .min_h = 300 });
    _ = d.add(box, .{ .h = 150 });
    const b = d.add(box, .{ .h = 100, .avoid = true });
    const tail = d.add(root, .{ .h = 20 });
    try d.run(root, 200);
    try d.expect(b, &.{placed(1, 0, 100)});
    // 250 of content pushed by 50: still inside the 300 of min-height
    try d.expect(box, &.{ placed(0, 0, 200), placed(1, 0, 100) });
    try d.expect(tail, &.{placed(1, 100, 20)});
}

// flex rows: the items of a row are parallel flows, the row grows by the longest
test "fragment: the items of a flex row break in parallel" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 140 });
    const flex = d.add(root, .{ .display = .flex });
    const left = d.text(flex, 8, .{ .w = 100 });
    const right = d.add(flex, .{ .w = 100 });
    _ = d.add(right, .{ .h = 50 });
    const r2 = d.add(right, .{ .h = 50, .avoid = true });
    const tail = d.add(root, .{ .h = 10 });
    try d.run(root, 200);
    // left: three lines stay, five move (as a paragraph alone would); right: the second box moves
    try d.expect(left, &.{ placed(0, 140, 60), placed(1, 0, 100) });
    try d.expect(r2, &.{placed(1, 0, 50)});
    try d.expect(flex, &.{ placed(0, 140, 60), placed(1, 0, 100) });
    // the stretched item still reaches the end of the row
    try d.expect(right, &.{ placed(0, 140, 60), placed(1, 0, 100) });
    try d.expect(tail, &.{placed(1, 100, 10)});
}

// flex columns and wrapped rows break between their items / lines
test "fragment: a column flex container breaks between its items" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const flex = d.add(root, .{ .display = .flex, .column = true });
    var items: [5]Id = undefined;
    for (&items) |*it| it.* = d.add(flex, .{ .h = 60, .avoid = true });
    const tail = d.add(root, .{ .h = 10 });
    try d.run(root, 200);
    try d.expect(items[2], &.{placed(0, 120, 60)});
    try d.expect(items[3], &.{placed(1, 0, 60)});
    try d.expect(items[4], &.{placed(1, 60, 60)});
    try d.expect(flex, &.{ placed(0, 0, 200), placed(1, 0, 120) });
    try d.expect(tail, &.{placed(1, 120, 10)});
}

test "fragment: a grid breaks between its rows, a row that cannot break moves on whole" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    var st = Doc.style(.{ .display = .grid });
    const cols = [_]L.Track{ L.Track.px(100), L.Track.px(100) };
    st.grid_template_columns = &cols;
    const grid = d.t.addNode(st) catch unreachable;
    d.t.appendChild(root, grid) catch unreachable;
    var items: [6]Id = undefined;
    for (&items) |*it| it.* = d.add(grid, .{ .h = 80, .avoid = true });
    try d.run(root, 200);
    // rows of two items, 80 tall: two rows per page
    try d.expect(items[2], &.{placed(0, 80, 80)});
    try d.expect(items[3], &.{placed(0, 80, 80)});
    try d.expect(items[4], &.{placed(1, 0, 80)});
    try d.expect(items[5], &.{placed(1, 0, 80)});
    try d.expect(grid, &.{ placed(0, 0, 200), placed(1, 0, 80) });
}

// a box of fixed height that ends on the page: what overflows it goes on in a parallel flow
test "fragment: content overflowing a box that fits breaks in a parallel flow" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 100 });
    const box = d.add(root, .{ .h = 50 });
    _ = d.add(box, .{ .h = 60 });
    const over = d.add(box, .{ .h = 80, .avoid = true });
    const next = d.add(root, .{ .h = 20 });
    try d.run(root, 200);
    try d.expect(box, &.{placed(0, 100, 50)});
    try d.expect(over, &.{placed(1, 0, 80)});
    // the flow of the box's container goes on below the box, on the first page
    try d.expect(next, &.{placed(0, 150, 20)});
}

// existing layouts are untouched when nothing breaks
test "fragment: content that fits one page is left alone" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const a = d.add(root, .{ .h = 50, .mt = 10, .mb = 10 });
    const p = d.text(root, 3, .{});
    try d.t.compute(root, .{ .{ .definite = 300 }, .{ .definite = 200 } }, &d, Doc.measure, .{});
    const nodes = [_]Id{ a, p, root };
    var before: [3][4]f32 = undefined;
    for (nodes, &before) |n, *b| b.* = .{ d.t.layout(n).x, d.t.layout(n).y, d.t.layout(n).w, d.t.layout(n).h };
    try d.run(root, 200);
    try d.expectPages(1);
    for (nodes, before) |n, b| try testing.expectEqual(b, [4]f32{ d.t.layout(n).x, d.t.layout(n).y, d.t.layout(n).w, d.t.layout(n).h });
    try testing.expectEqual(@as(usize, 0), d.pages.repeats.len);
}

// takumi: a_column_flex_item_breaks_across_pages
// takumi: a_column_flex_item_after_a_forced_break_starts_the_next_page
test "fragment: column flex items break across pages and after forced breaks" {
    if (!F.enabled) return error.SkipZigTest;
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const flex = d.add(root, .{ .display = .flex, .column = true });
        const a = d.add(flex, .{ .h = 150 });
        const b = d.add(flex, .{ .h = 150 });
        try d.run(root, 200);
        try d.expectPages(2);
        try d.expect(a, &.{placed(0, 0, 150)});
        try d.expect(b, &.{ placed(0, 150, 50), placed(1, 0, 100) });
        try d.expect(flex, &.{ placed(0, 0, 200), placed(1, 0, 100) });
    }
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const flex = d.add(root, .{ .display = .flex, .column = true });
        _ = d.add(flex, .{ .h = 120 });
        const b = d.add(flex, .{ .h = 120, .before = .page });
        try d.run(root, 200);
        try d.expectPages(2);
        try d.expect(b, &.{placed(1, 0, 120)});
    }
}

fn wrapRow(d: *Doc, root: Id) Id {
    var st = Doc.style(.{ .display = .flex });
    st.flex_wrap = .wrap;
    const flex = d.t.addNode(st) catch unreachable;
    d.t.appendChild(root, flex) catch unreachable;
    return flex;
}
fn fullWidth(d: *Doc, parent: Id, o: O) Id {
    var st = Doc.style(o);
    st.size[0] = .{ .percent = 1 };
    const n = d.t.addNode(st) catch unreachable;
    d.t.appendChild(parent, n) catch unreachable;
    return n;
}

// takumi: a_flex_row_item_breaks_inside_where_the_page_ends
// takumi: a_flex_row_that_avoids_breaking_inside_moves_to_the_next_page
test "fragment: the rows of a wrapping flex container" {
    if (!F.enabled) return error.SkipZigTest;
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const flex = wrapRow(&d, root);
        _ = fullWidth(&d, flex, .{ .h = 120 });
        const b = fullWidth(&d, flex, .{ .h = 120 });
        try d.run(root, 200);
        try d.expectPages(2);
        try d.expect(b, &.{ placed(0, 120, 80), placed(1, 0, 40) });
    }
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const flex = wrapRow(&d, root);
        _ = fullWidth(&d, flex, .{ .h = 120 });
        const b = fullWidth(&d, flex, .{ .h = 120, .avoid = true });
        try d.run(root, 200);
        try d.expectPages(2);
        try d.expect(b, &.{placed(1, 0, 120)});
        try d.expect(flex, &.{ placed(0, 0, 200), placed(1, 0, 120) });
    }
}

// takumi: a_grid_item_breaks_across_pages
// takumi: a_grid_row_that_avoids_breaking_inside_moves_to_the_next_page
// takumi: a_grid_row_after_a_forced_break_starts_the_next_page
test "fragment: grid rows" {
    if (!F.enabled) return error.SkipZigTest;
    const Case = enum { plain, avoid, forced };
    for ([_]Case{ .plain, .avoid, .forced }) |case| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const grid = d.add(root, .{ .display = .grid });
        const a = d.add(grid, .{ .h = 150 });
        const b = d.add(grid, .{ .h = 150, .avoid = case == .avoid, .before = if (case == .forced) .page else .auto });
        try d.run(root, 200);
        try d.expectPages(2);
        try d.expect(a, &.{placed(0, 0, 150)});
        if (case == .plain) {
            try d.expect(b, &.{ placed(0, 150, 50), placed(1, 0, 100) });
            try d.expect(grid, &.{ placed(0, 0, 200), placed(1, 0, 100) });
        } else try d.expect(b, &.{placed(1, 0, 150)});
    }
}

// takumi: a_flex_item_with_a_percentage_child_keeps_its_flexed_size_past_a_break (first case; the
// percentage case is not ported: a post-pass does not know which boxes resolve percentages against the item)
test "fragment: a flex item grows to hold the content a forced break pushed down" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const flex = d.add(root, .{ .display = .flex, .column = true, .h = 200 });
    var st = Doc.style(.{});
    st.flex_grow = 1;
    st.flex_shrink = 1;
    st.flex_basis = .{ .px = 0 };
    const item = d.t.addNode(st) catch unreachable;
    d.t.appendChild(flex, item) catch unreachable;
    _ = d.add(item, .{ .h = 50 });
    _ = d.add(item, .{ .h = 180, .before = .page });
    try d.run(root, 100);
    try d.expect(item, &.{ placed(0, 0, 100), placed(1, 0, 100), placed(2, 0, 80) });
}

// takumi: an_absolute_box_taller_than_a_page_breaks_across_the_pages_of_a_flex_container / _a_grid / _a_table
test "fragment: an absolute box taller than a page breaks across the pages of a flex container, a grid and a table" {
    if (!F.enabled) return error.SkipZigTest;
    for ([_]L.Display{ .flex, .grid, .table }) |disp| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const box = d.add(root, .{ .display = disp, .pos = .relative });
        var abs: Id = undefined;
        if (disp == .table) {
            const row = d.add(box, .{ .display = .table_row });
            const cell = d.add(row, .{ .display = .table_cell });
            const inner = d.add(cell, .{});
            abs = d.add(inner, .{ .pos = .absolute, .top = 0, .h = 300 });
            _ = d.add(inner, .{ .h = 300 });
        } else {
            abs = d.add(box, .{ .pos = .absolute, .top = 0, .h = 300 });
            _ = d.add(box, .{ .h = 300 });
        }
        try d.run(root, 200);
        try d.expectPages(2);
        try d.expect(box, &.{ placed(0, 0, 200), placed(1, 0, 100) });
        try d.expect(abs, &.{ placed(0, 0, 200), placed(1, 0, 100) });
    }
}

/// takumi's clipped_overflow_pages: a 100px box, then a 100px box of `o` holding a 400px child, on
/// pages 100px tall.
fn clippedOverflow(d: *Doc, o: O) ![2]Id {
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 100 });
    const clipper = d.add(root, o);
    const inner = d.add(clipper, .{ .h = 400 });
    try d.run(root, 100);
    return .{ clipper, inner };
}

// takumi: the_content_an_overflow_hidden_box_clips_adds_no_pages / _an_overflow_clip_box_ /
// the_content_a_clipping_flex_container_clips_adds_no_pages / _grid_ /
// content_overflowing_a_visible_box_continues_on_later_pages
test "fragment: clipped content adds no pages, visible overflow goes on" {
    if (!F.enabled) return error.SkipZigTest;
    const cases = [_]O{
        .{ .h = 100, .overflow = .hidden },
        .{ .h = 100, .overflow = .clip },
        .{ .h = 100, .overflow = .hidden, .display = .flex },
        .{ .h = 100, .overflow = .hidden, .display = .grid },
    };
    for (cases) |o| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const ids = try clippedOverflow(&d, o);
        try d.expectPages(2);
        try d.expect(ids[0], &.{placed(1, 0, 100)});
        // the clipped child is one piece 400 tall at the top of the box
        try testing.expectEqual(@as(f32, 100), d.top(ids[1]));
        try testing.expectEqual(@as(f32, 400), d.t.layout(ids[1]).h);
    }
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const ids = try clippedOverflow(&d, .{ .h = 100 });
    try d.expectPages(5);
    try d.expect(ids[0], &.{placed(1, 0, 100)});
    try d.expect(ids[1], &.{ placed(1, 0, 100), placed(2, 0, 100), placed(3, 0, 100), placed(4, 0, 100) });
}

// takumi: a_clipping_box_that_breaks_stops_breaking_on_the_page_it_ends
test "fragment: a clipping box that breaks stops breaking on the page it ends" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    _ = d.add(root, .{ .h = 50 });
    const clipper = d.add(root, .{ .h = 150, .overflow = .hidden });
    const inner = d.add(clipper, .{ .h = 400 });
    const after = d.add(root, .{ .h = 50 });
    try d.run(root, 100);
    try d.expectPages(3);
    try d.expect(clipper, &.{ placed(0, 50, 50), placed(1, 0, 100) });
    try testing.expectEqual(@as(f32, 50), d.top(inner));
    try testing.expectEqual(@as(f32, 400), d.t.layout(inner).h);
    try d.expect(after, &.{placed(2, 0, 50)});
}

// takumi-pdf pdf_fixtures.rs: a_forced_break_on_a_node_that_opens_a_page_adds_no_empty_page
// (page area 260 tall; B1 / B2 are 14 tall)
test "fragment: a forced break on a box that opens a page adds no empty page" {
    if (!F.enabled) return error.SkipZigTest;
    const Case = struct { spacer: f32, gap: f32, pt: f32, first: L.BreakBetween, second: L.BreakBetween, second_mt: f32, pages: usize };
    const cases = [_]Case{
        .{ .spacer = 235, .gap = 16, .pt = 0, .first = .auto, .second = .auto, .second_mt = 0, .pages = 2 },
        .{ .spacer = 235, .gap = 16, .pt = 0, .first = .auto, .second = .page, .second_mt = 0, .pages = 2 },
        .{ .spacer = 235, .gap = 0, .pt = 0, .first = .auto, .second = .page, .second_mt = 16, .pages = 2 },
        // Blink's column flex counts the list's padding as separation from its first item, so the forced
        // break before that item leaves the padding alone on page 2
        .{ .spacer = 245, .gap = 0, .pt = 16, .first = .page, .second = .auto, .second_mt = 0, .pages = 3 },
    };
    for (cases) |c| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const col = d.add(root, .{ .display = .flex, .column = true });
        _ = d.add(col, .{ .h = c.spacer, .w = 100 });
        var st = Doc.style(.{ .display = .flex, .column = true, .pt = c.pt });
        st.gap[1] = .{ .px = c.gap };
        const list = d.t.addNode(st) catch unreachable;
        d.t.appendChild(col, list) catch unreachable;
        _ = d.add(list, .{ .h = 14, .avoid = true, .before = c.first });
        const b2 = d.add(list, .{ .h = 14, .avoid = true, .before = c.second, .mt = c.second_mt });
        try d.run(root, 260);
        try d.expectPages(c.pages);
        // (the takumi test checks the page count only. Positions as takumi's golden paged-header-footer
        // shows Blink's column flex fragmentation: after a forced break the item keeps its distance from
        // the break (the row gap, its margin); after an unforced one an item that the gap carried past the
        // page end keeps the part past it (b2 at 235 + 14 + 16 = 265, the page ends at 260), none is pulled up)
        const y2: f32 = if (c.second == .page) c.second_mt + c.gap else 235 + 14 + c.gap - 260;
        if (c.pages == 2) try d.expect(b2, &.{placed(1, y2, 14)});
    }
}

// takumi-pdf pdf_fixtures.rs: forced_breaks_beside_spacing_break_as_blink_separates_them
test "fragment: forced breaks beside spacing break as Blink separates them" {
    if (!F.enabled) return error.SkipZigTest;
    {
        // leading: the item's margin separates it from the start of its column flex container
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const col = d.add(root, .{ .display = .flex, .column = true });
        _ = d.add(col, .{ .display = .flex, .h = 20, .mt = 16, .before = .page });
        try d.run(root, 200);
        try d.expectPages(2);
    }
    {
        // trailing: a break after the last item opens no page
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const col = d.add(root, .{ .display = .flex, .column = true, .pb = 16 });
        _ = d.add(col, .{ .display = .flex, .h = 20, .after = .page });
        try d.run(root, 200);
        try d.expectPages(1);
    }
    {
        // doubled: adjacent break-after / break-before break once
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const col = d.add(root, .{ .display = .flex, .column = true });
        _ = d.add(col, .{ .display = .flex, .h = 20, .after = .page });
        const two = d.add(col, .{ .display = .flex, .h = 20, .mt = 16, .before = .page });
        try d.run(root, 200);
        try d.expectPages(2);
        try d.expect(two, &.{placed(1, 16, 20)});
    }
}

// takumi-pdf pdf_fixtures.rs: trailing_padding_past_the_page_end_goes_to_the_next_page
test "fragment: trailing padding past the page end goes to the next page" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const col = d.add(root, .{ .display = .flex, .column = true, .pb = 40 });
    _ = d.add(col, .{ .h = 240 });
    try d.run(root, 260);
    try d.expectPages(2);
    // the padding is unbreakable: all 40px of it are on the second page
    try d.expect(col, &.{ placed(0, 0, 260), placed(1, 0, 40) });
}

// takumi-pdf pdf_fixtures.rs: a_forced_break_in_a_nested_flex_row_moves_the_row
test "fragment: a forced break in a nested flex row moves the row" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const outer = wrapRow(&d, root);
    var rows: [2]Id = undefined;
    var items: [4]Id = undefined;
    for (&rows, 0..) |*r, ri| {
        var st = Doc.style(.{ .display = .flex });
        st.flex_wrap = .wrap;
        st.size[0] = .{ .percent = 1 };
        r.* = d.t.addNode(st) catch unreachable;
        d.t.appendChild(outer, r.*) catch unreachable;
        for (0..2) |k| {
            var is = Doc.style(.{ .h = 20, .before = if (ri == 1 and k == 0) .page else .auto });
            is.size[0] = .{ .percent = 0.5 };
            items[ri * 2 + k] = d.t.addNode(is) catch unreachable;
            d.t.appendChild(r.*, items[ri * 2 + k]) catch unreachable;
        }
    }
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(items[1], &.{placed(0, 0, 20)});
    try d.expect(items[2], &.{placed(1, 0, 20)});
    try d.expect(items[3], &.{placed(1, 0, 20)});
}

// takumi-pdf pdf_fixtures.rs: a_float_breaks_only_when_it_does_not_fit_its_page (page 75 tall)
test "fragment: a float breaks only when it does not fit its page" {
    if (!F.enabled) return error.SkipZigTest;
    for ([_]f32{ 65, 120 }) |h| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const float = d.add(root, .{ .float = .right, .w = 40, .h = h });
        _ = d.text(root, 6, .{});
        try d.run(root, 75);
        if (h == 65) try d.expect(float, &.{placed(0, 0, 65)}) else try d.expect(float, &.{ placed(0, 0, 75), placed(1, 0, 45) });
    }
}

// many pages: every break is found from where the last one left off
test "fragment: perf, 20000 blocks over 2000 pages" {
    if (!F.enabled) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var t = T.init(arena.allocator());
    const root = try t.addNode(Doc.style(.{}));
    const wrap = try t.addNode(Doc.style(.{ .display = .flex, .column = true }));
    try t.appendChild(root, wrap);
    const n = 20_000;
    for (0..n) |i| {
        const sec = try t.addNode(Doc.style(.{ .mb = 4 }));
        try t.appendChild(wrap, sec);
        const c = try t.addNode(Doc.style(.{ .h = if (i % 7 == 0) 43 else 16, .avoid = true }));
        try t.appendChild(sec, c);
    }
    var dummy: u8 = 0;
    try t.compute(root, .{ .{ .definite = 300 }, .{ .definite = 200 } }, &dummy, @import("tests.zig").noMeasure, .{});
    const t0 = std.Io.Timestamp.now(std.testing.io, .awake);
    var pages = try F.paginate(&t, arena.allocator(), root, .{ .page_height = 200, .max_pages = 100_000 });
    const ns = t0.durationTo(std.Io.Timestamp.now(std.testing.io, .awake)).nanoseconds;
    std.debug.print("fragment: {d} nodes, {d} pages, {d:.3} ms (debug)\n", .{ t.nodes.items.len, pages.pages.len, @as(f64, @floatFromInt(ns)) / 1e6 });
    try testing.expect(pages.pages.len > 1900);
    pages.deinit(arena.allocator());
}

// deep nesting: the probe / apply recursion stays within the stack
test "fragment: 500 nested boxes" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    var cur = root;
    for (0..500) |_| cur = d.add(cur, .{});
    _ = d.add(cur, .{ .h = 150 });
    const b = d.add(cur, .{ .h = 100, .avoid = true });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(b, &.{placed(1, 0, 100)});
    try d.expect(root, &.{ placed(0, 0, 200), placed(1, 0, 100) });
}

// ---- random documents: what must hold whatever the breaks are

const Gen = struct {
    d: *Doc,
    rnd: std.Random,
    count: u32 = 0,

    fn kids(g: *Gen, parent: Id, depth: u32) void {
        const n = g.rnd.intRangeAtMost(u32, 1, 6);
        for (0..n) |_| {
            if (g.count > 160) return;
            g.count += 1;
            const mt: f32 = if (g.rnd.uintLessThan(u8, 4) == 0) 12 else 0;
            const mb: f32 = if (g.rnd.uintLessThan(u8, 4) == 0) 16 else 0;
            const avoid = g.rnd.uintLessThan(u8, 5) == 0;
            const before: L.BreakBetween = switch (g.rnd.uintLessThan(u8, 24)) {
                0 => .page,
                1 => .avoid,
                else => .auto,
            };
            const after: L.BreakBetween = switch (g.rnd.uintLessThan(u8, 24)) {
                0 => .page,
                1 => .avoid,
                else => .auto,
            };
            const kind = g.rnd.uintLessThan(u8, if (depth >= 4) 3 else 7);
            switch (kind) {
                0 => _ = g.d.add(parent, .{ .h = @floatFromInt(g.rnd.intRangeAtMost(u32, 5, 130)), .mt = mt, .mb = mb, .avoid = avoid, .before = before, .after = after }),
                1 => _ = g.d.text(parent, g.rnd.intRangeAtMost(u16, 1, 14), .{ .mt = mt, .mb = mb, .avoid = avoid, .before = before, .after = after, .widows = g.rnd.intRangeAtMost(u8, 1, 3), .orphans = g.rnd.intRangeAtMost(u8, 1, 3) }),
                2 => {
                    const img = g.d.image(parent, @floatFromInt(g.rnd.intRangeAtMost(u32, 10, 160)));
                    g.d.t.nodes.items[img].style.margin.bottom = .{ .px = mb };
                },
                3, 4 => g.kids(g.d.add(parent, .{ .mt = mt, .mb = mb, .pt = if (kind == 4) 8 else 0, .pb = if (kind == 4) 6 else 0, .avoid = avoid and kind == 3, .before = before }), depth + 1),
                5 => g.kids(g.d.add(parent, .{ .display = .flex, .column = true, .mb = mb, .after = after }), depth + 1),
                else => {
                    const row = g.d.add(parent, .{ .display = .flex, .mt = mt });
                    g.kids(g.d.add(row, .{ .w = 140 }), depth + 1);
                    g.kids(g.d.add(row, .{ .w = 140 }), depth + 1);
                },
            }
        }
    }
};

fn checkTree(d: *Doc, n: Id, top: f32, page_h: f32) !void {
    const ns = d.t.nodes.items;
    const l = d.t.layout(n);
    const s = &ns[n].style;
    const P = struct {
        fn of(y: f32, ph: f32) i64 {
            return @intFromFloat(@floor((y + 0.01) / ph));
        }
    };
    if (ns[n].measured) {
        if (d.n_lines[n] == 0) {
            // an image that is not taller than a page is on one page
            if (l.h <= page_h and l.h > 0) try testing.expectEqual(P.of(top, page_h), P.of(top + l.h - 0.02, page_h));
            return;
        }
        // no line is cut by a page boundary; the lines stay in order and inside the box
        var prev_bottom: f32 = top;
        for (0..d.n_lines[n]) |i| {
            const lt = top + @as(f32, @floatFromInt(i)) * d.line_h + d.pages.lineDy(n, @intCast(i));
            const lb = lt + d.line_h;
            try testing.expectEqual(P.of(lt, page_h), P.of(lb - 0.02, page_h));
            try testing.expect(lt >= prev_bottom - 0.02);
            prev_bottom = lb;
        }
        try testing.expect(prev_bottom <= top + l.h + 0.02);
        return;
    }
    // the in-flow children of a block container / column stay in order without overlapping, inside it
    const stacked = s.display == .block or s.flex_direction == .column;
    var prev_end: f32 = top;
    var prev_top: f32 = top;
    var ch = ns[n].first_child;
    while (ch != L.tree.no_node) : (ch = ns[ch].next_sibling) {
        const cl = d.t.layout(ch);
        const ct = top + cl.y;
        if (stacked) {
            // (or it starts a page below content left overflowing the page before: takumi's
            // monolithic overflow that does not carry over)
            const after_overflow = P.of(prev_top, page_h) < P.of(ct, page_h);
            try testing.expect(ct >= prev_end - 0.02 or after_overflow);
            prev_end = ct + cl.h;
            prev_top = ct;
        }
        // (or it starts on an earlier page than the box ends and overflows that page: content after
        // it moved up to the next page's start, its overflow was left behind)
        const left_behind = P.of(ct, page_h) < P.of(top + l.h - 0.02, page_h) or P.of(ct + cl.h - 0.02, page_h) > P.of(top + l.h - 0.02, page_h);
        try testing.expect(ct + cl.h <= top + l.h + 0.02 or left_behind);
        try checkTree(d, ch, ct, page_h);
    }
}

test "fragment: random documents keep their invariants" {
    if (!F.enabled) return error.SkipZigTest;
    var prng = std.Random.DefaultPrng.init(0xf7a9);
    const rnd = prng.random();
    var total_pages: usize = 0;
    var total_shifts: usize = 0;
    for (0..400) |round| {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        var g: Gen = .{ .d = &d, .rnd = rnd };
        g.kids(root, 0);
        const page_h: f32 = @floatFromInt(rnd.intRangeAtMost(u32, 90, 320));
        try d.t.compute(root, .{ .{ .definite = 300 }, .{ .definite = page_h } }, &d, Doc.measure, .{});
        const h0 = d.t.layout(root).h;
        d.run(root, page_h) catch |err| {
            std.debug.print("round {d}: {s}\n", .{ round, @errorName(err) });
            return err;
        };
        checkTree(&d, root, d.t.layout(root).y, page_h) catch |err| {
            std.debug.print("round {d}: page height {d}, {d} pages\n", .{ round, page_h, d.pages.pages.len });
            return err;
        };
        // every forced break adds at most a page, every other break less than one
        try testing.expect(@as(f32, @floatFromInt(d.pages.pages.len)) <= 3 * (h0 / page_h + 1) + @as(f32, @floatFromInt(g.count)));
        total_pages += d.pages.pages.len;
        total_shifts += d.pages.line_shifts.len;
    }
    std.debug.print("fragment: 400 random documents, {d} pages, {d} line breaks\n", .{ total_pages, total_shifts });
    try testing.expect(total_pages > 1200 and total_shifts > 200);
}

// ---- inline formatting contexts (`Config.inline_fn`): the boxes on the lines move with their lines

const TI = L.TreeWith(.{ .inline_fn = true });
/// A paragraph of five 20px lines; item `k` of the paragraph sits on line `item_line[k]`.
const InlineCtx = struct {
    t: *TI,
    item_line: [4]u32 = @splat(0),
    buf: [5]F.LineBox = undefined,

    fn measure(_: *anyopaque, _: Id, known: [2]?f32, _: [2]L.AvailableSpace) [2]f32 {
        return .{ known[0] orelse 0, known[1] orelse 0 };
    }
    fn inlineFn(ctx: *anyopaque, _: Id, io: *L.InlineIo) void {
        const c: *InlineCtx = @ptrCast(@alignCast(ctx));
        io.size = .{ if (@abs(io.width) < std.math.inf(f32)) io.width else 100, 100 };
        io.first_baseline = 16;
        io.last_baseline = 96;
        for (io.items, 0..) |*it, k| {
            it.x = 0;
            it.y = @floatFromInt(c.item_line[k] * 20);
            it.placed = true;
        }
    }
    fn linesFn(ctx: *anyopaque, n: Id) []const F.LineBox {
        const c: *InlineCtx = @ptrCast(@alignCast(ctx));
        if (c.t.style(n).display != .inline_row) return &.{};
        for (&c.buf, 0..) |*b, i| b.* = .{ .top = @floatFromInt(i * 20), .bottom = @floatFromInt(i * 20 + 20) };
        return &c.buf;
    }
};

// takumi: an_absolute_box_among_lines_sits_on_the_page_of_its_line (with a block before the paragraph, so
// that the lines move)
test "fragment: the boxes among lines sit on the page of their line" {
    if (!F.enabled) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var t = TI.init(arena.allocator());
    var c: InlineCtx = .{ .t = &t };
    const root = try t.addNode(Doc.style(.{}));
    const lead = try t.addNode(Doc.style(.{ .h = 10 }));
    try t.appendChild(root, lead);
    const p = try t.addNode(Doc.style(.{ .display = .inline_row }));
    try t.appendChild(root, p);
    // an inline-block on line 1, one on line 3, an absolute box whose static position is on line 4
    const first = try t.addNode(Doc.style(.{ .h = 10, .w = 10 }));
    const second = try t.addNode(Doc.style(.{ .h = 10, .w = 10 }));
    const abs = try t.addNode(Doc.style(.{ .pos = .absolute, .h = 10, .w = 10 }));
    for ([_]Id{ first, second, abs }) |n| try t.appendChild(p, n);
    c.item_line = .{ 1, 3, 4, 0 };
    try t.compute(root, .{ .{ .definite = 300 }, .{ .definite = 60 } }, &c, InlineCtx.measure, .{ .inline_fn = InlineCtx.inlineFn });
    try testing.expectEqual(@as(f32, 100), t.layout(p).h);
    var pages = try F.paginate(&t, arena.allocator(), root, .{ .page_height = 60, .lines_fn = InlineCtx.linesFn, .ctx = &c });
    defer pages.deinit(arena.allocator());
    // lines 0-1 stay (10..50), line 2 would cross the page end: lines 2-4 move down by 10
    try testing.expectEqual(@as(usize, 2), pages.pages.len);
    try testing.expectEqual(@as(usize, 1), pages.lineShifts(p).len);
    try testing.expectEqual(@as(u32, 2), pages.lineShifts(p)[0].first_line);
    try testing.expectEqual(@as(f32, 10), pages.lineDy(p, 2));
    try testing.expectEqual(@as(f32, 110), t.layout(p).h);
    try testing.expectEqual(@as(f32, 20), t.layout(first).y);
    try testing.expectEqual(@as(f32, 70), t.layout(second).y);
    // the absolute box: page 1, 40 below its top
    try testing.expectEqual(@as(f32, 90), t.layout(abs).y);
    try testing.expectEqual(@as(u32, 1), pages.pageAt(t.layout(p).y + t.layout(abs).y));
}

// an early break inside a nested box: the breakpoint between the lines is reached through its containers
test "fragment: an early break is taken inside nested boxes" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const section = d.add(root, .{});
    const p = d.text(section, 8, .{});
    const kept = d.add(root, .{ .h = 60, .avoid = true, .before = .avoid });
    try d.run(root, 200);
    try d.expect(p, &.{ placed(0, 0, 200), placed(1, 0, 40) });
    try d.expect(section, &.{ placed(0, 0, 200), placed(1, 0, 40) });
    try testing.expectEqual(@as(u32, 6), d.pages.lineShifts(p)[0].first_line);
    try d.expect(kept, &.{placed(1, 40, 60)});
    // ... unless the box on the way avoids breaks: every breakpoint then violates an `avoid`, and Blink
    // takes the last of equally appealing ones (MovePastBreakpoint): the break inside `kept`
    var d2: Doc = undefined;
    d2.init();
    defer d2.deinit();
    const root2 = d2.add(null, .{});
    const section2 = d2.add(root2, .{ .avoid = true });
    const p2 = d2.text(section2, 8, .{});
    const kept2 = d2.add(root2, .{ .h = 60, .avoid = true, .before = .avoid });
    try d2.run(root2, 200);
    try d2.expect(p2, &.{placed(0, 0, 160)});
    try d2.expect(kept2, &.{ placed(0, 160, 40), placed(1, 0, 20) });
}

// Blink's table layout: a repeated header sits at the page start, the rows `border-spacing` below it
test "fragment: a repeated header with border-spacing" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    var st = Doc.style(.{ .display = .table });
    st.border_spacing = .{ 0, 2 };
    const table = d.t.addNode(st) catch unreachable;
    d.t.appendChild(root, table) catch unreachable;
    // (the header group comes last in the tree: the table moves it to the top)
    const body = d.add(table, .{ .display = .table_row_group });
    var rows: [8]Id = undefined;
    for (&rows) |*r| {
        r.* = d.add(body, .{ .display = .table_row, .avoid = true });
        _ = d.add(d.add(r.*, .{ .display = .table_cell }), .{ .h = 30 });
    }
    const thead = d.add(table, .{ .display = .table_header_group, .avoid = true });
    _ = d.add(d.add(d.add(thead, .{ .display = .table_row }), .{ .display = .table_cell }), .{ .h = 20 });
    try d.run(root, 200);
    try d.expectPages(2);
    try d.expect(thead, &.{placed(0, 2, 20)});
    try d.expect(rows[4], &.{placed(0, 152, 30)});
    try d.expect(rows[5], &.{placed(1, 22, 30)});
    try d.expect(rows[7], &.{placed(1, 86, 30)});
    try expectWithRepeats(&d, thead, &.{ placed(0, 2, 20), placed(1, 0, 20) });
    try d.expect(table, &.{ placed(0, 0, 200), placed(1, 0, 118) });
}

test "fragment: reversed flex columns break in block order" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    var st = Doc.style(.{ .display = .flex });
    st.flex_direction = .column_reverse;
    const flex = d.t.addNode(st) catch unreachable;
    d.t.appendChild(root, flex) catch unreachable;
    const a = d.add(flex, .{ .h = 150, .avoid = true });
    const b = d.add(flex, .{ .h = 150, .avoid = true });
    try d.run(root, 200);
    try d.expect(b, &.{placed(0, 0, 150)});
    try d.expect(a, &.{placed(1, 0, 150)});
    try d.expectPages(2);
}

test "fragment: a box flagged monolithic moves whole; a cell spanning rows does not stop its rows breaking" {
    if (!F.enabled) return error.SkipZigTest;
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        _ = d.add(root, .{ .h = 150 });
        var st = Doc.style(.{});
        st.breaks.monolithic = true;
        const box = d.t.addNode(st) catch unreachable;
        d.t.appendChild(root, box) catch unreachable;
        _ = d.add(box, .{ .h = 40 });
        _ = d.add(box, .{ .h = 40 });
        try d.run(root, 200);
        try d.expect(box, &.{placed(1, 0, 80)});
    }
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const table = d.add(root, .{ .display = .table });
        var rows: [4]Id = undefined;
        for (&rows, 0..) |*r, i| {
            r.* = d.add(table, .{ .display = .table_row, .avoid = true });
            if (i == 0) {
                var cs = Doc.style(.{ .display = .table_cell });
                cs.row_span = 4;
                const span = d.t.addNode(cs) catch unreachable;
                d.t.appendChild(r.*, span) catch unreachable;
            }
            _ = d.add(d.add(r.*, .{ .display = .table_cell }), .{ .h = 70 });
        }
        try d.run(root, 200);
        try d.expectPages(2);
        try d.expect(rows[1], &.{placed(0, 70, 70)});
        try d.expect(rows[2], &.{placed(1, 0, 70)});
        try d.expect(rows[3], &.{placed(1, 70, 70)});
    }
}

/// Paginates `root` (laid out 300 wide) continuing from `start` (`Options.start` / `start_top`),
/// recording where each page starts.
fn runFrom(d: *Doc, root: Id, page_h: f32, start: F.Start, start_top: ?f32) !void {
    try d.t.compute(root, .{ .{ .definite = 300 }, .{ .definite = page_h } }, d, Doc.measure, .{});
    d.pages = try F.paginate(&d.t, d.arena.allocator(), root, .{ .page_height = page_h, .lines_fn = Doc.linesFn, .ctx = d, .start = start, .start_top = start_top, .record_starts = true });
}

test "fragment: each page records where its content starts" {
    if (!F.enabled) return error.SkipZigTest;
    var d: Doc = undefined;
    d.init();
    defer d.deinit();
    const root = d.add(null, .{});
    const a = d.add(root, .{ .h = 100 });
    const p = d.text(root, 10, .{});
    const b = d.add(root, .{ .h = 100, .before = .page });
    _ = a;
    d.t.compute(root, .{ .{ .definite = 300 }, .{ .definite = 250 } }, &d, Doc.measure, .{}) catch unreachable;
    d.pages = try F.paginate(&d.t, d.arena.allocator(), root, .{ .page_height = 250, .lines_fn = Doc.linesFn, .ctx = &d, .record_starts = true });
    try d.expectPages(3);
    // page 1 continues the paragraph at its line 7 (100 + 7 * 20 = 240 <= 250), page 2 starts with
    // `b` after a forced break
    try testing.expectEqual(L.tree.no_node, d.pages.starts[0].node);
    try testing.expectEqual(p, d.pages.starts[1].node);
    try testing.expectEqual(@as(u32, 7), d.pages.starts[1].line);
    try testing.expectEqual(b, d.pages.starts[2].node);
    try testing.expect(d.pages.starts[2].forced);
}

test "fragment: a pagination that continues from a box or a line starts its page 1 there" {
    if (!F.enabled) return error.SkipZigTest;
    // before a box: page 0 holds what comes before it (a forced break later in it does not break
    // it), page 1 starts with the box, at `start_top`
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const a = d.add(root, .{ .h = 100 });
        const b = d.add(root, .{ .h = 100, .before = .page });
        const c = d.add(root, .{ .h = 100, .mt = 10 });
        try runFrom(&d, root, 150, .{ .node = c }, 500);
        try testing.expectEqual(@as(u32, 1), d.pages.start_page);
        try testing.expectEqual(@as(f32, 500), d.pages.pages[1].top);
        try d.expect(a, &.{placed(0, 0, 100)});
        try d.expect(b, &.{placed(0, 100, 100)});
        // (the margin of an unforced start is truncated)
        try d.expect(c, &.{placed(1, 0, 100)});
        try testing.expectEqual(c, d.pages.starts[1].node);
    }
    // before a line: the lines before it stay on page 0
    {
        var d: Doc = undefined;
        d.init();
        defer d.deinit();
        const root = d.add(null, .{});
        const p = d.text(root, 10, .{});
        try runFrom(&d, root, 100, .{ .node = p, .line = 3 }, null);
        try testing.expectEqual(@as(u32, 1), d.pages.start_page);
        try testing.expectEqual(@as(f32, 60), d.pages.pages[1].top);
        try testing.expectEqual(p, d.pages.starts[1].node);
        try testing.expectEqual(@as(u32, 3), d.pages.starts[1].line);
        // lines 3..7 on page 1 (5 lines of 20 in 100), the rest on page 2
        try testing.expectEqual(@as(u32, 8), d.pages.starts[2].line);
    }
}
