//! Tests for table layout (oracle replay + unit tests).
//! Fixtures: bench/probe/layout/gen_table.mjs -> testdata/oracle_table.json (takumi's `measure`, anonymous
//! table boxes skipped so that only real nodes are compared).
const std = @import("std");
const T = @import("tests.zig");
const L = T.L;
const testing = std.testing;
const Style = L.Style;
const Tree = L.Tree;

/// Fixtures that are known to deviate from the oracle, each with its cause. A listed case that starts
/// matching fails the test (stale entry).
const expected_failures = [_][]const u8{
    // tree.zig: a table without children is a leaf box and never reaches table.zig (Blink: an empty table is
    // its border + padding wide, nothing when its borders collapse)
    "collapse/empty",
    "empty/table",
    "empty/table-padded",
    // adjacent stray table parts form ONE anonymous table in Blink (a caption among them becomes its caption);
    // here every stray row / row group is an anonymous table of its own and stray captions / cells are blocks
    "anon/section-in-row",
    "stray/rows-adjacent",
    // tree.zig lays a stray cell out as a block (Blink: an anonymous table around it, shrink-to-fit)
    "stray/cell-in-block",
    // flex.zig takes the cross size of a row-flex item from its `height` style; a table's `height` is only a
    // minimum for its grid box (content and captions add to it). The table itself matches, the line does not.
    "ctx/flex-row-height-below-content",
    "ctx/flex-row-height-caption",
    // flex.zig aligns a column-flex item by its `width` style; a table is at least its min-content wide
    "ctx/flex-column-center-width-below-min",
    // flex.zig lets the main size of a row-flex item go down to its `width`; Blink floors a table item at its
    // min-content width (even with min-width: 0)
    "ctx/flex-width-below-min",
    // takumi bug (deviates from Blink): its measure pass reports a table's first-row fallback baseline at the
    // row's minimum height, the layout pass at its final height, so a table whose first row has no
    // baseline-aligned content and grows (table height) is shifted up by the difference. bm-engine uses the
    // laid-out baseline in both passes.
    "quirk/nested-height-fallback-baseline",
    "quirk/flex-baseline-table-height",
};

/// Fixtures that match within the tolerance but not to the exact 1/64 px in quantize64 mode.
const expected_inexact = [_][]const u8{
    // flex.zig shrinks by the flex base size inside the STYLE border + padding; a collapsing table has no
    // padding and half of its outer collapsed edges as border (a 1/32 px difference in the shrink shares)
    "ctx/flex-row-shrink-collapsed-border",
    "rand/odd-3",
};

/// Fixtures that only deviate in the default float mode (no LayoutUnit arithmetic).
const expected_float_only = [_][]const u8{
    // a 30% column of a max-content table: Blink truncates the percentage estimate to 299.984375 px (column
    // 89.98 px, the 3 x 30 px content wraps); in float arithmetic the table is 300 px and nothing wraps
    "width/cells-auto-2",
};

fn listed(list: []const []const u8, name: []const u8) bool {
    for (list) |x| {
        if (T.eq(x, name)) return true;
    }
    return false;
}

fn replay(comptime exact: bool) !void {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const parsed = try std.json.parseFromSliceLeaky(T.J, a, @embedFile("testdata/oracle_table.json"), .{});
    const list: []const []const u8 = if (exact) &(expected_failures ++ expected_inexact) else &(expected_failures ++ expected_float_only);
    var total: usize = 0;
    var failed: usize = 0;
    var known_bad: usize = 0;
    for (parsed.array.items) |case| {
        const o = case.object;
        const name = o.get("name").?.string;
        const vp = o.get("vp").?.array.items;
        var t = Tree.init(a);
        const root = try T.buildNode(a, &t, o.get("node").?);
        const av: [2]L.AvailableSpace = .{ .{ .definite = T.num(vp[0]) }, .{ .definite = T.num(vp[1]) } };
        try t.compute(root, av, &T.dummy, T.noMeasure, .{ .quantize64 = exact });
        var bad: usize = 0;
        // takumi reports positions relative to the root's border box
        const rx = -t.layout(root).x;
        const ry = -t.layout(root).y;
        const cmp = if (exact) T.compareExact else T.compareNode;
        cmp(&t, root, rx, ry, o.get("expect").?, &bad, false);
        total += 1;
        if (listed(list, name)) {
            known_bad += 1;
            if (bad == 0) {
                failed += 1;
                std.debug.print("STALE expected failure {s}\n", .{name});
            }
            continue;
        }
        if (bad != 0) {
            failed += 1;
            std.debug.print("FAIL {s}\n", .{name});
            cmp(&t, root, rx, ry, o.get("expect").?, &bad, true);
        }
    }
    if (exact) {
        std.debug.print("table oracle fixtures, exact LayoutUnit agreement (quantize64): {d}/{d} ({d} listed deviations, {d} unexpected)\n", .{ total - known_bad - failed, total, known_bad, failed });
    } else {
        std.debug.print("table oracle fixtures: {d}/{d} match takumi within 0.07 px ({d} listed deviations, {d} unexpected)\n", .{ total - known_bad - failed, total, known_bad, failed });
    }
    try testing.expect(failed == 0);
    // every listed name must exist
    for (list) |x| {
        var found = false;
        for (parsed.array.items) |case| found = found or T.eq(case.object.get("name").?.string, x);
        if (!found) std.debug.print("unknown fixture in the expected-failure list: {s}\n", .{x});
        try testing.expect(found);
    }
}

test "table oracle fixtures (takumi wasm)" {
    try replay(false);
}

test "table oracle fixtures, exact LayoutUnit agreement (quantize64)" {
    try replay(true);
}

// ---------------------------------------------------------------------------------------------------
// hand-written unit tests

const vp400: [2]L.AvailableSpace = .{ .{ .definite = 400 }, .{ .definite = 300 } };

fn px(v: f32) L.Dim {
    return .{ .px = v };
}
fn add(t: *Tree, parent: ?L.NodeId, s: Style) !L.NodeId {
    var st = s;
    if (st.position == .relative) st.position = .static;
    const id = try t.addNode(st);
    if (parent) |p| try t.appendChild(p, id);
    return id;
}
fn boxIn(t: *Tree, parent: L.NodeId, w: f32, h: f32) !L.NodeId {
    return add(t, parent, .{ .display = .block, .size = .{ px(w), px(h) } });
}
/// A wrapping flex row of `n` boxes `w` wide: min-content `w`, max-content `n * w`.
fn wordsIn(t: *Tree, parent: L.NodeId, n: usize, w: f32) !L.NodeId {
    const f = try add(t, parent, .{ .display = .flex, .flex_wrap = .wrap });
    for (0..n) |_| _ = try add(t, f, .{ .display = .flex, .size = .{ px(w), px(10) }, .flex_shrink = 0 });
    return f;
}
fn expectRect(t: *const Tree, id: L.NodeId, x: f32, y: f32, w: f32, h: f32) !void {
    const l = t.layout(id);
    const ok = @abs(l.x - x) < 0.01 and @abs(l.y - y) < 0.01 and @abs(l.w - w) < 0.01 and @abs(l.h - h) < 0.01;
    if (!ok) {
        std.debug.print("node {d}: got {d:.3},{d:.3} {d:.3}x{d:.3} want {d:.3},{d:.3} {d:.3}x{d:.3}\n", .{ id, l.x, l.y, l.w, l.h, x, y, w, h });
        return error.TestExpectedEqual;
    }
}
fn expectFinite(t: *const Tree) !void {
    for (t.layouts.items, 0..) |l, i| {
        const ok = std.math.isFinite(l.x) and std.math.isFinite(l.y) and std.math.isFinite(l.w) and std.math.isFinite(l.h) and l.w >= 0 and l.h >= 0;
        if (!ok) std.debug.print("node {d} ({s}): {d},{d} {d}x{d}\n", .{ i, @tagName(t.style(@intCast(i)).display), l.x, l.y, l.w, l.h });
        try testing.expect(ok);
    }
}

test "table: width distribution above the maximums, colspan, rowspan (values from the Blink algorithm)" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    // columns.rs "a_wide_table_grows_auto_columns_by_their_maximums": maxima 50 and 150 in 400 -> 100 / 300
    const root = try add(&t, null, .{ .display = .block, .size = .{ px(400), .auto } });
    const tbl = try add(&t, root, .{ .display = .table, .size = .{ px(400), .auto } });
    const row = try add(&t, tbl, .{ .display = .table_row });
    const a = try add(&t, row, .{ .display = .table_cell });
    _ = try wordsIn(&t, a, 5, 10);
    const b = try add(&t, row, .{ .display = .table_cell });
    _ = try wordsIn(&t, b, 5, 30);
    // a second row with one cell over both columns
    const row2 = try add(&t, tbl, .{ .display = .table_row });
    const wide = try add(&t, row2, .{ .display = .table_cell, .col_span = 2 });
    _ = try boxIn(&t, wide, 20, 7);
    try t.compute(root, vp400, &T.dummy, T.noMeasure, .{});
    try expectRect(&t, tbl, 0, 0, 400, 17);
    try expectRect(&t, a, 0, 0, 100, 10);
    try expectRect(&t, b, 100, 0, 300, 10);
    try expectRect(&t, row2, 0, 10, 400, 7);
    try expectRect(&t, wide, 0, 0, 400, 7);

    // rows.rs "a_rowspan_grows_the_rows_it_covers_in_proportion": rows of 10 and 30, a spanning cell of 82 and
    // 2px of spacing -> 20 / 60
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const tbl2 = try add(&t2, null, .{ .display = .table, .border_spacing = .{ 0, 2 } });
    const r1 = try add(&t2, tbl2, .{ .display = .table_row });
    const span = try add(&t2, r1, .{ .display = .table_cell, .row_span = 2, .vertical_align = .top });
    _ = try boxIn(&t2, span, 10, 82);
    const c1 = try add(&t2, r1, .{ .display = .table_cell });
    _ = try boxIn(&t2, c1, 10, 10);
    const r2 = try add(&t2, tbl2, .{ .display = .table_row });
    const c2 = try add(&t2, r2, .{ .display = .table_cell });
    _ = try boxIn(&t2, c2, 10, 30);
    try t2.compute(tbl2, vp400, &T.dummy, T.noMeasure, .{});
    try expectRect(&t2, r1, 0, 2, 20, 20);
    try expectRect(&t2, r2, 0, 24, 20, 60);
    try expectRect(&t2, span, 0, 0, 10, 82);
    try expectRect(&t2, c2, 10, 0, 10, 60);
    try expectRect(&t2, tbl2, 0, 0, 20, 86);
}

test "table: rowspan 0 spans every row left in the section" {
    // (takumi, with rowspan="0": the first cell is 40x110, the cells of the next rows start at x = 40)
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const tbl = try add(&t, null, .{ .display = .table });
    const r1 = try add(&t, tbl, .{ .display = .table_row });
    const all = try add(&t, r1, .{ .display = .table_cell, .row_span = 0 });
    _ = try boxIn(&t, all, 40, 80);
    const a = try add(&t, r1, .{ .display = .table_cell });
    _ = try boxIn(&t, a, 60, 10);
    const r2 = try add(&t, tbl, .{ .display = .table_row });
    const b = try add(&t, r2, .{ .display = .table_cell });
    _ = try boxIn(&t, b, 30, 10);
    const r3 = try add(&t, tbl, .{ .display = .table_row });
    const c = try add(&t, r3, .{ .display = .table_cell });
    _ = try boxIn(&t, c, 30, 20);
    try t.compute(tbl, vp400, &T.dummy, T.noMeasure, .{});
    try expectRect(&t, all, 0, 0, 40, 110);
    try expectRect(&t, r2, 0, 80, 100, 10);
    try expectRect(&t, b, 40, 0, 60, 10);
    try expectRect(&t, r3, 0, 90, 100, 20);
    try expectRect(&t, c, 40, 0, 60, 20);
}

test "table: collapsed borders are reported as used borders" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try add(&t, null, .{ .display = .block, .size = .{ px(300), .auto } });
    const tbl = try add(&t, root, .{ .display = .table, .border_collapse = true, .border = .all(6), .padding = .all(.{ .px = 9 }) });
    const row = try add(&t, tbl, .{ .display = .table_row });
    const a = try add(&t, row, .{ .display = .table_cell, .border = .all(2) });
    const ab = try boxIn(&t, a, 40, 20);
    const b = try add(&t, row, .{ .display = .table_cell, .border = .all(4) });
    _ = try boxIn(&t, b, 60, 20);
    for (0..2) |_| {
        // (twice: the second run starts from the layouts of the first)
        try t.compute(root, vp400, &T.dummy, T.noMeasure, .{});
        // outer edges: max(6, cell) / 2 = 3; the edge between the cells: max(2, 4) / 2 = 2; no table padding
        // (the table's border is the outer half of its edges, the cells' the inner half)
        try expectRect(&t, tbl, 0, 0, 3 + (3 + 40 + 2) + (2 + 60 + 3) + 3, 32);
        try expectRect(&t, row, 3, 3, 110, 26);
        try testing.expectEqual(@as(f32, 3), t.layout(tbl).border.left);
        try testing.expectEqual(@as(f32, 3), t.layout(tbl).border.bottom);
        try testing.expectEqual(@as(f32, 0), t.layout(tbl).padding.left);
        try testing.expectEqual(@as(f32, 3), t.layout(a).border.left);
        try testing.expectEqual(@as(f32, 2), t.layout(a).border.right);
        try testing.expectEqual(@as(f32, 2), t.layout(b).border.left);
        try testing.expectEqual(@as(f32, 3), t.layout(b).border.top);
        try expectRect(&t, a, 0, 0, 45, 26);
        try expectRect(&t, ab, 3, 3, 40, 20);
        try expectRect(&t, b, 45, 0, 65, 26);
        // the cell's own style is untouched
        try testing.expectEqual(@as(f32, 2), t.style(a).border.left);
    }
    // separate borders: the styles' values
    var st = t.style(tbl).*;
    st.border_collapse = false;
    t.setStyle(tbl, st);
    try t.compute(root, vp400, &T.dummy, T.noMeasure, .{});
    try testing.expectEqual(@as(f32, 6), t.layout(tbl).border.left);
    try testing.expectEqual(@as(f32, 9), t.layout(tbl).padding.left);
    try testing.expectEqual(@as(f32, 4), t.layout(b).border.left);
}

test "table: vertical-align shifts are not applied twice when the tree is laid out again" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    // a flex container measures the table before it lays it out; the nested table is laid out repeatedly
    const root = try add(&t, null, .{ .display = .flex, .size = .{ px(300), px(200) }, .align_items = .center });
    const tbl = try add(&t, root, .{ .display = .table, .size = .{ .auto, px(120) } });
    const row = try add(&t, tbl, .{ .display = .table_row });
    const a = try add(&t, row, .{ .display = .table_cell, .vertical_align = .bottom });
    const inner = try add(&t, a, .{ .display = .table });
    const irow = try add(&t, inner, .{ .display = .table_row, .size = .{ .auto, px(50) } });
    const ia = try add(&t, irow, .{ .display = .table_cell, .vertical_align = .middle });
    const ib = try boxIn(&t, ia, 20, 10);
    const b = try add(&t, row, .{ .display = .table_cell, .vertical_align = .middle });
    const bb = try boxIn(&t, b, 30, 40);
    for (0..3) |_| {
        try t.compute(root, vp400, &T.dummy, T.noMeasure, .{ .quantize64 = true });
        try expectRect(&t, tbl, 0, 40, 50, 120);
        try expectRect(&t, inner, 0, 70, 20, 50);
        try expectRect(&t, ib, 0, 20, 20, 10);
        try expectRect(&t, bb, 0, 40, 30, 40);
    }
}

test "table: 150 nested tables" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var t = Tree.init(arena_state.allocator());
    const root = try add(&t, null, .{ .display = .table, .border_spacing = .{ 1, 1 } });
    var tbl = root;
    var cell: L.NodeId = undefined;
    const depth = 150;
    for (0..depth) |i| {
        const row = try add(&t, tbl, .{ .display = .table_row });
        cell = try add(&t, row, .{ .display = .table_cell, .padding = .all(.{ .px = 1 }), .vertical_align = if (i % 2 == 0) .baseline else .middle });
        // a sibling cell so that every level has two columns and a row taller than the nested table
        const side = try add(&t, row, .{ .display = .table_cell });
        _ = try boxIn(&t, side, 3, 5);
        if (i + 1 < depth) tbl = try add(&t, cell, .{ .display = .table, .border_spacing = .{ 1, 1 }, .border_collapse = i % 5 == 4, .border = .all(if (i % 5 == 4) 2 else 0) });
    }
    const leaf = try boxIn(&t, cell, 10, 10);
    for ([_]bool{ false, true }) |q| {
        try t.compute(root, .{ .{ .definite = 4000 }, .{ .definite = 300 } }, &T.dummy, T.noMeasure, .{ .quantize64 = q });
        try expectFinite(&t);
        try testing.expectEqual(@as(f32, 10), t.layout(leaf).w);
        try testing.expectEqual(@as(f32, 10), t.layout(leaf).h);
        try testing.expect(t.layout(root).w > 10 + 2 * depth);
        try testing.expect(t.layout(root).h > 10 + 2 * depth);
    }
    std.debug.print("tables: {d} nested tables, {d} nodes, {d} node computations\n", .{ depth, t.nodes.items.len, t.node_computes });
    // every nesting level is laid out a bounded number of times
    try testing.expect(t.node_computes < 40 * t.nodes.items.len);

    // nesting past max_depth fails cleanly: rows count as levels although they are not computed as nodes
    for (0..40) |_| {
        const inner = try add(&t, cell, .{ .display = .table });
        const row = try add(&t, inner, .{ .display = .table_row });
        cell = try add(&t, row, .{ .display = .table_cell });
    }
    try testing.expectError(error.TooDeep, t.compute(root, vp400, &T.dummy, T.noMeasure, .{}));
}

test "table: hostile spans and sizes" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const inf = std.math.inf(f32);
    const nan = std.math.nan(f32);
    const spans = [_]u16{ 65535, 0, 1000, 1001, 2, 1 };
    const dims = [_]L.Dim{ px(nan), px(-50), px(1e30), .{ .percent = inf }, .{ .percent = -3 }, .{ .percent = 1e20 }, .auto, px(40), .{ .calc = .{ .px = nan, .percent = 2 } } };
    for ([_]bool{ false, true }) |collapse| {
        for ([_]bool{ false, true }) |fixed| {
            var t = Tree.init(a);
            const root = try add(&t, null, .{ .display = .block, .size = .{ px(300), .auto } });
            const tbl = try add(&t, root, .{
                .display = .table,
                .border_collapse = collapse,
                .table_fixed = fixed,
                .size = .{ if (fixed) px(200) else .auto, px(inf) },
                .border_spacing = .{ nan, 1e30 },
                .border = .{ .top = nan, .right = -4, .bottom = 1e30, .left = 3 },
                .padding = .all(.{ .percent = nan }),
            });
            _ = try add(&t, tbl, .{ .display = .table_column, .col_span = 65535, .size = .{ px(1e30), .auto }, .border = .all(1e30) });
            const cg = try add(&t, tbl, .{ .display = .table_column_group, .col_span = 0, .size = .{ .{ .percent = nan }, .auto } });
            _ = try add(&t, cg, .{ .display = .table_column, .col_span = 1000, .visibility_collapse = true });
            _ = try add(&t, tbl, .{ .display = .table_caption, .size = .{ px(nan), px(-1) }, .margin = .all(.auto) });
            var k: usize = 0;
            for (0..6) |ri| {
                const sec = if (ri % 3 == 0) try add(&t, tbl, .{ .display = if (ri == 0) .table_footer_group else .table_row_group, .size = .{ .auto, dims[ri % dims.len] }, .visibility_collapse = ri == 3 }) else tbl;
                const row = try add(&t, sec, .{ .display = .table_row, .size = .{ .auto, dims[(ri + 3) % dims.len] }, .border = .all(if (ri == 1) inf else 2) });
                for (0..6) |ci| {
                    k += 1;
                    const cell = try add(&t, row, .{
                        .display = .table_cell,
                        .col_span = spans[k % spans.len],
                        .row_span = spans[(k / 2 + ci) % spans.len],
                        .size = .{ dims[k % dims.len], dims[(k + 4) % dims.len] },
                        .min_size = .{ dims[(k + 1) % dims.len], .auto },
                        .max_size = .{ dims[(k + 2) % dims.len], .auto },
                        .border = .all(if (k % 4 == 0) nan else @floatFromInt(k % 5)),
                        .padding = .all(.{ .px = if (k % 7 == 0) -inf else 1 }),
                        .box_sizing = if (k % 3 == 0) .content_box else .border_box,
                        .vertical_align = @fromBackingInt(@intCast(k % 4)),
                    });
                    if (k % 4 != 1) _ = try boxIn(&t, cell, 12, 9);
                    if (k % 6 == 2) _ = try add(&t, cell, .{ .display = .block, .size = .{ .{ .percent = 0.5 }, .{ .percent = 0.5 } } });
                }
                // loose boxes and an absolutely positioned child between the rows
                _ = try boxIn(&t, sec, 7, 7);
                _ = try add(&t, row, .{ .display = .block, .position = .absolute, .size = .{ px(5), px(5) } });
            }
            for ([_]bool{ false, true }) |q| {
                try t.compute(root, vp400, &T.dummy, T.noMeasure, .{ .quantize64 = q });
                try expectFinite(&t);
            }
        }
    }

    // many cells with huge spans: time and memory stay proportional to the number of cells
    var t = Tree.init(a);
    const tbl = try add(&t, null, .{ .display = .table, .border_collapse = true, .border = .all(1) });
    for (0..40) |_| {
        const row = try add(&t, tbl, .{ .display = .table_row });
        for (0..25) |_| _ = try add(&t, row, .{ .display = .table_cell, .col_span = 65535, .row_span = 65535, .border = .all(1) });
    }
    try t.compute(tbl, vp400, &T.dummy, T.noMeasure, .{});
    try expectFinite(&t);
}

test "table: a row as a flex item is blockified, a stray row is an anonymous table" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try add(&t, null, .{ .display = .block, .size = .{ px(300), .auto } });
    const row = try add(&t, root, .{ .display = .table_row });
    const a = try add(&t, row, .{ .display = .table_cell });
    _ = try boxIn(&t, a, 20, 20);
    const b = try add(&t, row, .{ .display = .table_cell, .vertical_align = .bottom });
    const bb = try boxIn(&t, b, 30, 10);
    const flex = try add(&t, root, .{ .display = .flex });
    const frow = try add(&t, flex, .{ .display = .table_row });
    const fa = try add(&t, frow, .{ .display = .table_cell });
    _ = try boxIn(&t, fa, 20, 20);
    const fb = try add(&t, frow, .{ .display = .table_cell });
    _ = try boxIn(&t, fb, 30, 10);
    try t.compute(root, vp400, &T.dummy, T.noMeasure, .{});
    // the anonymous table shrinks to fit; its cells sit side by side
    try expectRect(&t, row, 0, 0, 50, 20);
    try expectRect(&t, a, 0, 0, 20, 20);
    try expectRect(&t, b, 20, 0, 30, 20);
    try expectRect(&t, bb, 0, 10, 30, 10);
    // the flex item is a block: its cells stack
    try expectRect(&t, frow, 0, 0, 30, 30);
    try expectRect(&t, fa, 0, 0, 30, 20);
    try expectRect(&t, fb, 0, 20, 30, 10);
}

var deepest_sp: usize = 0;
fn spMeasure(_: *anyopaque, _: L.NodeId, _: [2]?f32, _: [2]L.AvailableSpace) [2]f32 {
    const a = @frameAddress();
    if (deepest_sp == 0 or a < deepest_sp) deepest_sp = a;
    return .{ 10, 10 };
}

test "table: stack use per nested table" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var t = Tree.init(arena_state.allocator());
    const root = try add(&t, null, .{ .display = .table });
    var tbl = root;
    var cell: L.NodeId = undefined;
    const depth = 120;
    for (0..depth) |i| {
        const row = try add(&t, tbl, .{ .display = .table_row });
        cell = try add(&t, row, .{ .display = .table_cell });
        if (i + 1 < depth) tbl = try add(&t, cell, .{ .display = .table });
    }
    const leaf = try add(&t, cell, .{ .display = .block });
    t.setMeasured(leaf, true);
    deepest_sp = 0;
    const top = @frameAddress();
    try t.compute(root, vp400, &T.dummy, spMeasure, .{});
    // one level = table + row + cell: three nodes of nesting
    const per_level = (top - deepest_sp) / depth;
    std.debug.print("tables: {d} bytes of stack per nested table = {d} per node level ({s})\n", .{ per_level, per_level / 3, @tagName(@import("builtin").mode) });
    if (@import("builtin").mode != .debug) try testing.expect(per_level / 3 < 4096);
}

test "table: perf, 60 x 8 cells" {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    var t = Tree.init(arena_state.allocator());
    const root = try add(&t, null, .{ .display = .block, .size = .{ px(1200), .auto } });
    const tbl = try add(&t, root, .{ .display = .table, .size = .{ .{ .percent = 1 }, .auto }, .border_collapse = true, .border = .all(1) });
    for (0..60) |ri| {
        const row = try add(&t, tbl, .{ .display = .table_row });
        for (0..8) |ci| {
            if (ri % 7 == 3 and ci == 1) continue;
            const cell = try add(&t, row, .{ .display = .table_cell, .padding = .all(.{ .px = 4 }), .border = .all(1), .col_span = if (ri % 7 == 3 and ci == 0) 2 else 1, .vertical_align = if (ci == 0) .middle else .baseline });
            _ = try wordsIn(&t, cell, 2 + (ri * 3 + ci) % 6, 18);
        }
    }
    const n_nodes = t.nodes.items.len;
    const full: [2]L.AvailableSpace = .{ .{ .definite = 1200 }, .{ .definite = 630 } };
    try t.compute(root, full, &T.dummy, T.noMeasure, .{});
    const computes = t.node_computes;
    const iters: usize = 50;
    const io = std.testing.io;
    const t0 = std.Io.Timestamp.now(io, .awake);
    for (0..iters) |_| try t.compute(root, full, &T.dummy, T.noMeasure, .{});
    const t1 = std.Io.Timestamp.now(io, .awake);
    const ns: f64 = @floatFromInt(t0.durationTo(t1).nanoseconds);
    const ms = ns / 1e6 / @as(f64, @floatFromInt(iters));
    std.debug.print("tables: {d} nodes ({d} cells), {d:.3} ms per compute ({s}), {d} node computations\n", .{ n_nodes, 60 * 8, ms, @tagName(@import("builtin").mode), computes });
    try expectFinite(&t);
    // each node: min-content, max-content, measure, final (and a few more for the wrapping rows)
    try testing.expect(computes < 8 * n_nodes);
}
