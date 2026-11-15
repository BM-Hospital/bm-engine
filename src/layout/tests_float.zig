//! Tests for floats and the phase-2 additions (order, safe alignment, position: fixed, grid-area containing
//! blocks, aspect-ratio automatic minimums, nesting depth, feature configuration): replay of oracle fixtures
//! generated from @takumi-rs/wasm (bench/probe/layout/gen_float.mjs -> testdata/oracle_float.json,
//! gen_misc.mjs -> testdata/oracle_misc.json) + unit tests.
const std = @import("std");
const T = @import("tests.zig");
const L = T.L;
const testing = std.testing;
const Style = L.Style;

/// Known deviations from the oracle (name, cause). A listed case that starts to match fails the test.
const xfail = [_][2][]const u8{
    .{ "fixed/in-grid", "a fixed-position grid child with grid-placement properties: takumi keeps the given grid lines as containing-block edges and the viewport for the others; we resolve it against the viewport only" },
};

fn isXfail(name: []const u8) bool {
    for (xfail) |x| if (T.eq(x[0], name)) return true;
    return false;
}

fn replay(comptime file: []const u8, comptime exact: bool) !void {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const parsed = try std.json.parseFromSliceLeaky(T.J, a, @embedFile("testdata/" ++ file), .{});
    var total: usize = 0;
    var failed: usize = 0;
    var known_bad: usize = 0;
    for (parsed.array.items) |case| {
        const o = case.object;
        const name = o.get("name").?.string;
        const vpa = o.get("vp").?.array.items;
        var t = L.Tree.init(a);
        const root = try T.buildNode(a, &t, o.get("node").?);
        try t.compute(root, .{ .{ .definite = T.num(vpa[0]) }, .{ .definite = T.num(vpa[1]) } }, &T.dummy, T.noMeasure, .{ .quantize64 = exact });
        var bad: usize = 0;
        const rx = -t.layout(root).x;
        const ry = -t.layout(root).y;
        const cmp = if (exact) T.compareExact else T.compareNode;
        cmp(&t, root, rx, ry, o.get("expect").?, &bad, false);
        total += 1;
        if (isXfail(name)) {
            known_bad += 1;
            if (bad == 0) {
                failed += 1;
                std.debug.print("STALE-XFAIL {s}\n", .{name});
            }
            continue;
        }
        if (bad != 0) {
            failed += 1;
            std.debug.print("FAIL {s}\n", .{name});
            cmp(&t, root, rx, ry, o.get("expect").?, &bad, true);
        }
    }
    std.debug.print("{s} ({s}): {d}/{d} match takumi ({d} known deviations, {d} unexpected)\n", .{ file, if (exact) "exact 1/64 px" else "0.07 px", total - known_bad - failed, total, known_bad, failed });
    try testing.expect(failed == 0);
}

test "float oracle fixtures (takumi wasm)" {
    try replay("oracle_float.json", false);
}

test "float oracle fixtures, exact LayoutUnit agreement (quantize64)" {
    try replay("oracle_float.json", true);
}

test "misc oracle fixtures: order, safe alignment, fixed, grid areas, aspect-ratio minimums" {
    try replay("oracle_misc.json", false);
    try replay("oracle_misc.json", true);
}

// ---------------------------------------------------------------------------------------------------

fn px(v: f32) L.Dim {
    return .{ .px = v };
}
const vp: [2]L.AvailableSpace = .{ .{ .definite = 400 }, .{ .definite = 300 } };

fn expectRect(t: anytype, id: L.NodeId, x: f32, y: f32, w: f32, h: f32) !void {
    const l = t.layout(id);
    const e: f32 = 0.01;
    if (@abs(l.x - x) > e or @abs(l.y - y) > e or @abs(l.w - w) > e or @abs(l.h - h) > e) {
        std.debug.print("node {d}: got {d},{d} {d}x{d}  want {d},{d} {d}x{d}\n", .{ id, l.x, l.y, l.w, l.h, x, y, w, h });
        return error.TestExpectedEqual;
    }
}

const Text = struct {
    /// natural (single-line) width and line height of every measured leaf
    natural: f32 = 200,
    line: f32 = 10,
    min: f32 = 40,
    fn measure(ctx: *anyopaque, _: L.NodeId, known: [2]?f32, av: [2]L.AvailableSpace) [2]f32 {
        const self: *Text = @ptrCast(@alignCast(ctx));
        const w = known[0] orelse switch (av[0]) {
            .definite => |v| @max(@min(v, self.natural), self.min),
            .min_content => self.min,
            .max_content => self.natural,
        };
        return .{ w, known[1] orelse @ceil(self.natural / @max(w, 1)) * self.line };
    }
};

test "floats: a text leaf shortens next to a float, moves below when its longest word does not fit" {
    var t = L.Tree.init(testing.allocator);
    defer t.deinit();
    var text: Text = .{};
    const root = try t.addNode(.{ .display = .block, .size = .{ px(300), .auto } });
    const fl = try t.addNode(.{ .display = .block, .float = .left, .size = .{ px(100), px(50) } });
    const p = try t.addNode(.{ .display = .block });
    const leaf = try t.addNode(.{ .display = .block, .is_inline_content = true });
    t.setMeasured(leaf, true);
    try t.appendChild(root, fl);
    try t.appendChild(root, p);
    try t.appendChild(p, leaf);
    try t.compute(root, vp, &text, Text.measure, .{});
    // the paragraph box overlaps the float, its text is fitted into the 200px band beside it
    try expectRect(&t, p, 0, 0, 300, 10);
    try expectRect(&t, leaf, 100, 0, 200, 10);
    try expectRect(&t, root, 0, 0, 300, 50);

    // a float that leaves less than the longest word: the text starts below it
    try t.setStyle(fl, .{ .display = .block, .float = .left, .size = .{ px(280), px(50) } });
    try t.compute(root, vp, &text, Text.measure, .{});
    try expectRect(&t, leaf, 0, 50, 300, 10);
    try expectRect(&t, root, 0, 0, 300, 60);

    // right float + narrower band: the text wraps (documented approximation: it keeps the band width)
    try t.setStyle(fl, .{ .display = .block, .float = .right, .size = .{ px(220), px(15) } });
    try t.compute(root, vp, &text, Text.measure, .{});
    try expectRect(&t, leaf, 0, 0, 80, 30);
}

test "floats: disabled by configuration they lay out as in-flow blocks" {
    const Plain = L.TreeWith(.{ .floats = false, .tables = false, .inline_row = false });
    var t = Plain.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .display = .block, .size = .{ px(300), .auto } });
    const a = try t.addNode(.{ .display = .block, .float = .left, .size = .{ px(100), px(50) } });
    const b = try t.addNode(.{ .display = .flex, .size = .{ .auto, px(20) } });
    const tb = try t.addNode(.{ .display = .table });
    const cell = try t.addNode(.{ .display = .table_cell, .size = .{ px(40), px(10) } });
    try t.appendChild(root, a);
    try t.appendChild(root, b);
    try t.appendChild(root, tb);
    try t.appendChild(tb, cell);
    try t.compute(root, vp, &T.dummy, T.noMeasure, .{});
    try expectRect(&t, a, 0, 0, 100, 50);
    try expectRect(&t, b, 0, 50, 300, 20);
    try expectRect(&t, tb, 0, 70, 300, 10);
    try expectRect(&t, root, 0, 0, 300, 80);
}

test "floats: untrusted values and deep nesting" {
    var t = L.Tree.init(testing.allocator);
    defer t.deinit();
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    const root = try t.addNode(.{ .display = .block, .size = .{ px(300), .auto } });
    var cur = root;
    for (0..200) |i| {
        const f = try t.addNode(.{ .display = .block, .float = if (i % 2 == 0) .left else .right, .size = .{ px(if (i % 7 == 0) nan else 10), px(if (i % 5 == 0) inf else 5) }, .margin = .all(.{ .px = if (i % 11 == 0) -inf else 1 }) });
        const blk = try t.addNode(.{ .display = .block, .clear = if (i % 9 == 0) .both else .none, .margin = .all(.{ .px = 1 }) });
        const root_box = try t.addNode(.{ .display = .flex, .size = .{ .auto, px(3) } });
        try t.appendChild(cur, f);
        try t.appendChild(cur, root_box);
        try t.appendChild(cur, blk);
        cur = blk;
    }
    try t.compute(root, vp, &T.dummy, T.noMeasure, .{ .quantize64 = true });
    for (0..t.nodes.items.len) |i| {
        const l = t.layout(@intCast(i));
        try testing.expect(std.math.isFinite(l.x) and std.math.isFinite(l.y) and std.math.isFinite(l.w) and std.math.isFinite(l.h));
    }
}

test "nesting: 512 levels of flex / block / grid / absolute boxes" {
    var t = L.Tree.init(testing.allocator);
    defer t.deinit();
    try testing.expectEqual(@as(usize, 512), L.max_depth);
    const root = try t.addNode(.{ .display = .block, .size = .{ px(400), px(300) } });
    var cur = root;
    const depth = L.max_depth - 2;
    for (0..depth) |i| {
        const s: Style = switch (i % 5) {
            0 => .{ .flex_direction = .column, .padding = .all(.{ .px = 0.25 }) },
            1 => .{ .display = .block },
            2 => .{ .display = .grid },
            3 => .{ .align_items = .baseline, .flex_wrap = .wrap },
            else => .{ .display = .block, .position = .absolute, .inset = .all(.{ .px = 0 }) },
        };
        const n = try t.addNode(s);
        try t.appendChild(cur, n);
        cur = n;
    }
    const leaf = try t.addNode(.{ .display = .block });
    t.setMeasured(leaf, true);
    try t.appendChild(cur, leaf);
    var text: Text = .{};
    try t.compute(root, vp, &text, Text.measure, .{ .quantize64 = true });
    try testing.expect(t.layout(leaf).w > 0 and t.layout(leaf).h > 0);
    // one level more than the limit fails cleanly
    var deeper = cur;
    for (0..4) |_| {
        const n = try t.addNode(.{ .display = .block });
        try t.appendChild(deeper, n);
        deeper = n;
    }
    const leaf2 = try t.addNode(.{ .size = .{ px(1), px(1) } });
    try t.appendChild(deeper, leaf2);
    try testing.expectError(error.TooDeep, t.compute(root, vp, &text, Text.measure, .{}));
}

test "order: large reversed input sorts in n log n and stays stable" {
    var t = L.Tree.init(testing.allocator);
    defer t.deinit();
    const n = 3000;
    const root = try t.addNode(.{ .flex_direction = .column, .size = .{ px(100), .auto } });
    var ids: [n]L.NodeId = undefined;
    for (0..n) |i| {
        ids[i] = try t.addNode(.{ .size = .{ px(10), px(1) }, .flex_shrink = 0, .order = @intCast(@as(i64, n / 2) - @as(i64, @intCast(i / 2))) });
        try t.appendChild(root, ids[i]);
    }
    try t.compute(root, vp, &T.dummy, T.noMeasure, .{});
    // orders descend in pairs: the last pair comes first, each pair keeps its document order
    try testing.expectEqual(@as(f32, 0), t.layout(ids[n - 2]).y);
    try testing.expectEqual(@as(f32, 1), t.layout(ids[n - 1]).y);
    try testing.expectEqual(@as(f32, n - 2), t.layout(ids[0]).y);
    try testing.expectEqual(@as(f32, n - 1), t.layout(ids[1]).y);
}
