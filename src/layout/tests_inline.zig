//! Tests for inline layout (oracle replay + unit tests).
//! Fixtures: bench/probe/layout/gen_inline.mjs -> testdata/oracle_inline.json (takumi lays `inline-block` /
//! `inline-flex` / `inline-grid` children of a block container out on line boxes). The fixtures store the
//! oracle's tree; the replay inserts the anonymous `inline_row` nodes an integrator would create.
const std = @import("std");
const T = @import("tests.zig");
const L = T.L;
const testing = std.testing;
const J = T.J;
const Style = L.Style;
const Tree = L.Tree;
const Dim = L.Dim;
const no_node = L.tree.no_node;

// ---------------------------------------------------------------------------------------------------
// fixture tree -> layout tree with anonymous rows

const Builder = struct {
    a: std.mem.Allocator,
    t: *Tree,
    /// per node: true = anonymous inline_row inserted by the builder (not part of the fixture tree)
    anon: std.ArrayList(bool) = .empty,

    fn add(b: *Builder, s: Style, is_anon: bool) !L.NodeId {
        const id = try b.t.addNode(s);
        try b.anon.append(b.a, is_anon);
        return id;
    }

    fn displayOf(v: J) []const u8 {
        const so = v.object.get("style") orelse return "";
        const d = so.object.get("display") orelse return "";
        return d.string;
    }

    /// Builds `v`; when it carries `inlineRow` every run of consecutive inline-level children is wrapped in an
    /// anonymous `inline_row` with the container's strut and (inherited) text-align.
    fn node(b: *Builder, v: J) !L.NodeId {
        const o = v.object;
        const s = if (o.get("style")) |so| try T.styleFrom(b.a, so) else Style{};
        const id = try b.add(s, false);
        const row = o.get("inlineRow");
        var cur: ?L.NodeId = null;
        const kids = if (o.get("children")) |c| c.array.items else &[_]J{};
        for (kids) |c| {
            const d = displayOf(c);
            const inl = row != null and std.mem.startsWith(u8, d, "inline-");
            if (inl and cur == null) {
                const ro = row.?.object;
                const strut = ro.get("strut").?.array.items;
                const al = ro.get("align").?.string;
                cur = try b.add(.{
                    .display = .inline_row,
                    .position = .static,
                    .text_align = if (T.eq(al, "center")) .center else if (T.eq(al, "end") or T.eq(al, "right")) .end else if (T.eq(al, "justify")) .justify else .start,
                    .strut_ascent = T.num(strut[0]),
                    .strut_descent = T.num(strut[1]),
                    .strut_middle = T.num(strut[2]),
                }, true);
                try b.t.appendChild(id, cur.?);
            }
            if (!inl and !T.eq(d, "none")) cur = null;
            try b.t.appendChild(cur orelse id, try b.node(c));
        }
        return id;
    }

    /// Compares the real nodes against the oracle (absolute positions), looking through anonymous rows.
    fn compare(b: *const Builder, id: L.NodeId, ox: f32, oy: f32, exp: J, tol: f32, bad: *usize, verbose: bool) void {
        const l = b.t.layout(id);
        const o = exp.object;
        if (o.get("none") != null) {
            if (l.w != 0 or l.h != 0) bad.* += 1;
            return;
        }
        const ex = T.num(o.get("x").?);
        const ey = T.num(o.get("y").?);
        const ew = T.num(o.get("w").?);
        const eh = T.num(o.get("h").?);
        const ax = ox + l.x;
        const ay = oy + l.y;
        if (!(@abs(ax - ex) <= tol and @abs(ay - ey) <= tol and @abs(l.w - ew) <= tol and @abs(l.h - eh) <= tol)) {
            bad.* += 1;
            if (verbose) std.debug.print("    node {d}: got {d:.6},{d:.6} {d:.6}x{d:.6}  want {d:.6},{d:.6} {d:.6}x{d:.6}\n", .{ id, ax, ay, l.w, l.h, ex, ey, ew, eh });
        }
        const kids = if (o.get("children")) |c| c.array.items else &[_]J{};
        var i: usize = 0;
        b.walkKids(id, ax, ay, kids, &i, tol, bad, verbose);
        if (i != kids.len) bad.* += 1;
    }

    fn walkKids(b: *const Builder, parent: L.NodeId, ox: f32, oy: f32, exp: []const J, i: *usize, tol: f32, bad: *usize, verbose: bool) void {
        var ch = b.t.firstChild(parent);
        while (ch != no_node) : (ch = b.t.nextSibling(ch)) {
            if (b.anon.items[ch]) {
                const l = b.t.layout(ch);
                b.walkKids(ch, ox + l.x, oy + l.y, exp, i, tol, bad, verbose);
                continue;
            }
            if (i.* < exp.len) b.compare(ch, ox, oy, exp[i.*], tol, bad, verbose) else bad.* += 1;
            i.* += 1;
        }
    }
};

const XFail = struct { name: []const u8, cause: []const u8 };

/// Known deviations from the oracle (both modes). A listed case that starts matching fails the test.
const xfail = [_]XFail{
    // takumi (Blink) justifies at justification opportunities (spaces); adjacent atomic inlines have none, so
    // its lines stay start-aligned. The row spreads the free space between the items (deliberate extension).
    .{ .name = "align/justify", .cause = "oracle has no justification opportunity between atomic inlines" },
    .{ .name = "align/justify-odd", .cause = "oracle has no justification opportunity between atomic inlines" },
    // An inline-block's baseline is the baseline of its LAST line box / last in-flow child with a baseline;
    // `Out.baseline` is the first one.
    .{ .name = "baseline/ib-two-flex-children", .cause = "inline-block baseline = last child's baseline; Out.baseline is the first" },
    .{ .name = "baseline/nested-ib-two-lines", .cause = "inline-block baseline = last line's baseline; Out.baseline is the first" },
    .{ .name = "rand/row-2", .cause = "nested inline-block with two lines (last-line baseline)" },
    .{ .name = "rand/row-7", .cause = "nested inline-block with two lines (last-line baseline)" },
    .{ .name = "rand/row-10", .cause = "nested inline-block with two lines (last-line baseline)" },
    .{ .name = "rand/row-12", .cause = "nested inline-block with two lines (last-line baseline)" },
    .{ .name = "rand/row-31", .cause = "nested inline-block with two lines (last-line baseline)" },
    .{ .name = "rand/row-36", .cause = "nested inline-block with two lines (last-line baseline)" },
    // grid.zig reports no baseline for a grid whose items have none; Blink synthesizes it from the first item
    // of the first row, the row falls back to the bottom margin edge.
    .{ .name = "baseline/igrid", .cause = "grid container reports no (synthesized) first baseline" },
};

/// Cases that match within the tolerance but not to the exact layout unit in quantize64 mode.
const xfail_exact = [_]XFail{};

fn listed(list: []const XFail, name: []const u8) bool {
    for (list) |x| {
        if (T.eq(x.name, name)) return true;
    }
    return false;
}

fn replay(exact: bool) !void {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const parsed = try std.json.parseFromSliceLeaky(J, a, @embedFile("testdata/oracle_inline.json"), .{});
    const tol: f32 = if (exact) 0.001 else 0.07;
    var total: usize = 0;
    var failed: usize = 0;
    var known_bad: usize = 0;
    for (parsed.array.items) |case| {
        const o = case.object;
        const name = o.get("name").?.string;
        const vp = o.get("vp").?.array.items;
        var t = Tree.init(a);
        var b: Builder = .{ .a = a, .t = &t };
        const root = try b.node(o.get("node").?);
        try t.compute(root, .{ .{ .definite = T.num(vp[0]) }, .{ .definite = T.num(vp[1]) } }, &T.dummy, T.noMeasure, .{ .quantize64 = exact });
        var bad: usize = 0;
        // takumi reports positions relative to the root's border box
        const rx = -t.layout(root).x;
        const ry = -t.layout(root).y;
        b.compare(root, rx, ry, o.get("expect").?, tol, &bad, false);
        total += 1;
        if (listed(&xfail, name) or (exact and listed(&xfail_exact, name))) {
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
            b.compare(root, rx, ry, o.get("expect").?, tol, &bad, true);
        }
    }
    std.debug.print("inline oracle fixtures ({s}): {d}/{d} match takumi within {d} px ({d} known deviations, {d} unexpected)\n", .{ if (exact) "quantize64, exact" else "float", total - known_bad - failed, total, tol, known_bad, failed });
    try testing.expect(failed == 0);
    try testing.expect(total >= 60);
}

test "inline oracle fixtures (takumi wasm)" {
    try replay(false);
}

test "inline oracle fixtures, exact LayoutUnit agreement (quantize64)" {
    try replay(true);
}

// ---------------------------------------------------------------------------------------------------
// hand-written unit tests

fn px(v: f32) Dim {
    return .{ .px = v };
}
fn sz(w: f32, h: f32) [2]Dim {
    return .{ .{ .px = w }, .{ .px = h } };
}
const vp400: [2]L.AvailableSpace = .{ .{ .definite = 400 }, .{ .definite = 300 } };

fn child(t: *Tree, parent: L.NodeId, s: Style) !L.NodeId {
    const id = try t.addNode(s);
    try t.appendChild(parent, id);
    return id;
}
fn bx(w: f32, h: f32) Style {
    return .{ .display = .block, .size = sz(w, h) };
}
fn expectRect(t: *const Tree, id: L.NodeId, x: f32, y: f32, w: f32, h: f32) !void {
    const l = t.layout(id);
    const ok = @abs(l.x - x) < 0.01 and @abs(l.y - y) < 0.01 and @abs(l.w - w) < 0.01 and @abs(l.h - h) < 0.01;
    if (!ok) {
        std.debug.print("node {d}: got {d:.3},{d:.3} {d:.3}x{d:.3} want {d:.3},{d:.3} {d:.3}x{d:.3}\n", .{ id, l.x, l.y, l.w, l.h, x, y, w, h });
        return error.TestExpectedEqual;
    }
}
fn run(t: *Tree, root: L.NodeId) !void {
    try t.compute(root, vp400, &T.dummy, T.noMeasure, .{});
}

/// A text run: 200 px of 40 px words, 10 px lines, baseline 8 px below each line top.
const TextCtx = struct {
    calls: u32 = 0,
    fn measure(ctx: *anyopaque, _: L.NodeId, known: [2]?f32, available: [2]L.AvailableSpace) [2]f32 {
        const self: *TextCtx = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        const total: f32 = 200;
        const word: f32 = 40;
        const w: f32 = known[0] orelse switch (available[0]) {
            .definite => |v| @max(word, @min(total, v)),
            .min_content => word,
            .max_content => total,
        };
        const per_line = @max(@floor(w / word), 1);
        const lines = @ceil(total / word / per_line);
        return .{ if (known[0] != null) w else @min(w, per_line * word), known[1] orelse lines * 10 };
    }
    fn baseline(_: *anyopaque, _: L.NodeId, _: [2]f32) f32 {
        return 8;
    }
};
fn text(t: *Tree, parent: L.NodeId, s: Style) !L.NodeId {
    const id = try child(t, parent, s);
    t.setMeasured(id, true);
    return id;
}

test "inline row: boxes on one line, strut, vertical-align, baseline of the row" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .display = .inline_row, .size = .{ px(300), .auto }, .strut_ascent = 16, .strut_descent = 5, .strut_middle = 4 });
    const a = try child(&t, root, bx(10, 2));
    const b = try child(&t, root, .{ .display = .block, .size = sz(20, 40), .vertical_align = .top });
    const c = try child(&t, root, .{ .display = .block, .size = sz(30, 10), .vertical_align = .middle });
    const d = try child(&t, root, .{ .display = .block, .size = sz(40, 6), .vertical_align = .bottom });
    try run(&t, root);
    // strut 16 + 5; the top item (40) extends the line downwards: height 40, baseline stays at 16
    try expectRect(&t, root, 0, 0, 300, 40);
    try testing.expectEqual(@as(f32, 16), t.layout(root).baseline);
    try expectRect(&t, a, 0, 14, 10, 2);
    try expectRect(&t, b, 10, 0, 20, 40);
    // centre 4 above the baseline
    try expectRect(&t, c, 30, 7, 30, 10);
    try expectRect(&t, d, 60, 34, 40, 6);

    // without `strut_middle` the middle of the strut is used: (16 - 5) / 2 above the baseline
    var s = t.style(root).*;
    s.strut_middle = null;
    t.setStyle(root, s);
    try run(&t, root);
    try expectRect(&t, c, 30, 5.5, 30, 10);
}

test "inline row: wrapping, margins, text-align, justify" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .display = .inline_row, .size = .{ px(100), .auto }, .text_align = .justify });
    var k: [5]L.NodeId = undefined;
    for (&k) |*id| id.* = try child(&t, root, bx(30, 10));
    try run(&t, root);
    // 3 per line (90 of 100): the free 10 px go between the items; the last line is start-aligned
    try expectRect(&t, k[0], 0, 0, 30, 10);
    try expectRect(&t, k[1], 35, 0, 30, 10);
    try expectRect(&t, k[2], 70, 0, 30, 10);
    try expectRect(&t, k[3], 0, 10, 30, 10);
    try expectRect(&t, k[4], 30, 10, 30, 10);
    try expectRect(&t, root, 0, 0, 100, 20);

    var s = t.style(root).*;
    s.text_align = .center;
    t.setStyle(root, s);
    try run(&t, root);
    try expectRect(&t, k[0], 5, 0, 30, 10);
    try expectRect(&t, k[4], 50, 10, 30, 10);
    s.text_align = .end;
    t.setStyle(root, s);
    try run(&t, root);
    try expectRect(&t, k[2], 70, 0, 30, 10);
    try expectRect(&t, k[3], 40, 10, 30, 10);

    // margins count and do not collapse; an item wider than the line gets its own line
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .display = .inline_row, .size = .{ px(100), .auto }, .padding = .all(.{ .px = 5 }) });
    // (border-box 100: lines are 90 wide)
    const m0 = try child(&t2, r2, .{ .display = .block, .size = sz(40, 10), .margin = .all(.{ .px = 4 }) });
    const m1 = try child(&t2, r2, bx(150, 10));
    const m2 = try child(&t2, r2, .{ .display = .block, .size = sz(40, 10), .margin = .{ .top = px(3), .right = px(0), .bottom = px(0), .left = px(0) } });
    const m3 = try child(&t2, r2, .{ .display = .block, .size = sz(50, 20), .position = .relative, .inset = .{ .top = px(2), .left = px(1), .right = .auto, .bottom = .auto } });
    try run(&t2, r2);
    try expectRect(&t2, m0, 9, 9, 40, 10);
    try expectRect(&t2, m1, 5, 23, 150, 10);
    // line 3: m2 (margin box 13, baseline at its bottom) and m3 (20): ascent 20
    try expectRect(&t2, m2, 5, 43, 40, 10);
    try expectRect(&t2, m3, 46, 35, 50, 20);
    try expectRect(&t2, r2, 0, 0, 100, 58);
    try testing.expectEqual(@as(f32, 23), t2.layout(r2).baseline);
}

test "inline row: measured text leaves mixed with boxes" {
    var ctx: TextCtx = .{};
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .display = .inline_row, .size = .{ px(300), .auto }, .strut_ascent = 8, .strut_descent = 2 });
    const a = try child(&t, root, bx(50, 30));
    const tx = try text(&t, root, .{ .display = .block });
    const img = try child(&t, root, .{ .display = .block, .size = sz(20, 5), .vertical_align = .top });
    try t.compute(root, vp400, &ctx, TextCtx.measure, .{ .baseline = TextCtx.baseline });
    // box: baseline at its bottom (30); text: 200x10 with its baseline at 8
    try expectRect(&t, root, 0, 0, 300, 32);
    try expectRect(&t, a, 0, 0, 50, 30);
    try expectRect(&t, tx, 50, 22, 200, 10);
    try expectRect(&t, img, 250, 0, 20, 5);
    try testing.expectEqual(@as(f32, 30), t.layout(root).baseline);
    try testing.expectEqual(@as(f32, 8), t.layout(tx).baseline);

    // a text leaf that does not fit the rest of the line moves to the next line; wider than the line it
    // wraps inside the line width and is one box
    var s = t.style(root).*;
    s.size[0] = px(100);
    t.setStyle(root, s);
    try t.compute(root, vp400, &ctx, TextCtx.measure, .{ .baseline = TextCtx.baseline });
    try expectRect(&t, a, 0, 0, 50, 30);
    // 2 words per line -> 80 x 30, first baseline 8: ascent 8, descent 22
    try expectRect(&t, tx, 0, 32, 80, 30);
    // the image (top-aligned) still fits next to the text
    try expectRect(&t, img, 80, 32, 20, 5);
    try expectRect(&t, root, 0, 0, 100, 62);

    // padding and margins of the text leaf count
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .display = .inline_row, .size = .{ px(100), .auto } });
    const p = try text(&t2, r2, .{ .display = .block, .padding = .all(.{ .px = 5 }), .margin = .all(.{ .px = 3 }) });
    try t2.compute(r2, vp400, &ctx, TextCtx.measure, .{ .baseline = TextCtx.baseline });
    // available content width 100 - 6 - 10 = 84 -> 2 words per line
    try expectRect(&t2, p, 3, 3, 90, 40);
    try expectRect(&t2, r2, 0, 0, 100, 46);
    try testing.expectEqual(@as(f32, 16), t2.layout(r2).baseline);
}

test "inline row: intrinsic min/max-content width inside a shrink-to-fit flex item" {
    var ctx: TextCtx = .{};
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    // max-content: all items on one line
    const root = try t.addNode(.{ .size = .{ px(400), .auto }, .align_items = .flex_start });
    const row = try child(&t, root, .{ .display = .inline_row, .strut_ascent = 10, .strut_descent = 2 });
    const a = try child(&t, row, bx(40, 10));
    const b = try child(&t, row, .{ .display = .block, .size = sz(40, 10), .margin = .all(.{ .px = 5 }) });
    const c = try child(&t, row, bx(40, 20));
    try t.compute(root, vp400, &ctx, TextCtx.measure, .{});
    try expectRect(&t, row, 0, 0, 130, 22);
    try expectRect(&t, a, 0, 10, 40, 10);
    try expectRect(&t, b, 45, 5, 40, 10);
    try expectRect(&t, c, 90, 0, 40, 20);

    // min-content: the widest item (the flex item cannot shrink below it)
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .size = .{ px(60), .auto }, .align_items = .flex_start });
    const row2 = try child(&t2, r2, .{ .display = .inline_row });
    const a2 = try child(&t2, row2, bx(40, 10));
    const b2 = try child(&t2, row2, .{ .display = .block, .size = sz(40, 10), .margin = .all(.{ .px = 5 }) });
    const c2 = try child(&t2, row2, bx(40, 20));
    _ = try child(&t2, r2, .{ .size = sz(30, 10), .flex_shrink = 0 });
    try t2.compute(r2, vp400, &ctx, TextCtx.measure, .{});
    try expectRect(&t2, row2, 0, 0, 50, 50);
    try expectRect(&t2, a2, 0, 0, 40, 10);
    try expectRect(&t2, b2, 5, 15, 40, 10);
    try expectRect(&t2, c2, 0, 30, 40, 20);

    // a text leaf contributes its longest word / its unwrapped width
    var t3 = Tree.init(testing.allocator);
    defer t3.deinit();
    const r3 = try t3.addNode(.{ .size = .{ px(150), .auto }, .align_items = .flex_start });
    const row3 = try child(&t3, r3, .{ .display = .inline_row });
    const tx = try text(&t3, row3, .{ .display = .block });
    const bx3 = try child(&t3, row3, bx(30, 10));
    try t3.compute(r3, vp400, &ctx, TextCtx.measure, .{ .baseline = TextCtx.baseline });
    // max-content 230 shrinks to the 150 available; the text wraps at 150 (3 words per line), the box follows
    // (box: baseline at its bottom, ascent 10; text: baseline 8, descent 12)
    try expectRect(&t3, row3, 0, 0, 150, 22);
    try expectRect(&t3, tx, 0, 2, 120, 20);
    try expectRect(&t3, bx3, 120, 0, 30, 10);
}

test "inline row: absolute child static position, display none" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .display = .inline_row, .size = .{ px(200), .auto }, .text_align = .center, .padding = .all(.{ .px = 10 }) });
    const a = try child(&t, root, bx(20, 30));
    const abs = try child(&t, root, .{ .display = .block, .position = .absolute, .size = sz(5, 5) });
    const hidden = try child(&t, root, .{ .display = .none, .size = sz(500, 500) });
    const b = try child(&t, root, bx(10, 10));
    const abs2 = try child(&t, root, .{ .display = .block, .position = .absolute, .size = sz(7, 7), .inset = .{ .top = px(1), .right = px(2), .bottom = .auto, .left = .auto } });
    const c = try child(&t, root, bx(170, 10));
    const abs3 = try child(&t, root, .{ .display = .block, .position = .absolute, .size = sz(5, 5) });
    try run(&t, root);
    // line 1: 30 px centred in 180 -> starts at 10 + 75
    try expectRect(&t, a, 85, 10, 20, 30);
    try expectRect(&t, abs, 105, 10, 5, 5);
    try expectRect(&t, hidden, 0, 0, 0, 0);
    try expectRect(&t, b, 105, 30, 10, 10);
    // insets win over the static position (padding box of the row)
    try expectRect(&t, abs2, 191, 1, 7, 7);
    try expectRect(&t, c, 15, 40, 170, 10);
    // after the last item of line 2
    try expectRect(&t, abs3, 185, 40, 5, 5);
    try expectRect(&t, root, 0, 0, 200, 60);

    // only out-of-flow / hidden children: no line box, no baseline
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .display = .block, .size = .{ px(200), .auto } });
    _ = try child(&t2, r2, bx(50, 10));
    const row = try child(&t2, r2, .{ .display = .inline_row, .strut_ascent = 16, .strut_descent = 5 });
    const o = try child(&t2, row, .{ .display = .block, .position = .absolute, .size = sz(5, 5) });
    _ = try child(&t2, row, .{ .display = .none });
    try run(&t2, r2);
    try expectRect(&t2, row, 0, 10, 200, 0);
    try expectRect(&t2, o, 0, 0, 5, 5);
    try testing.expect(std.math.isNan(t2.layout(row).baseline));
    try expectRect(&t2, r2, 0, 0, 200, 10);
}

test "inline row: percentages resolve against the row, quantize64 keeps the grid" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .display = .block, .size = sz(300, 200) });
    const row = try child(&t, root, .{ .display = .inline_row, .size = .{ .auto, .{ .percent = 0.5 } }, .text_align = .center });
    const a = try child(&t, row, .{ .display = .block, .size = .{ .{ .percent = 0.333 }, .{ .percent = 0.5 } } });
    const b = try child(&t, row, .{ .display = .block, .size = .{ .{ .percent = 0.333 }, px(10) }, .margin = .{ .left = .{ .percent = 0.1 }, .top = px(0), .right = px(0), .bottom = px(0) } });
    try t.compute(root, vp400, &T.dummy, T.noMeasure, .{ .quantize64 = true });
    try expectRect(&t, row, 0, 0, 300, 100);
    // 99.9 -> 99.890625 (1/64 grid). The percentage margin is 0 (oracle quirk, see inline.zig `itemWidth`):
    // free = 300 - 2 * 99.890625 = 100.21875 -> half 50.109375
    try expectRect(&t, a, 50.109375, 0, 99.890625, 50);
    try expectRect(&t, b, 150, 40, 99.890625, 10);
}

/// No NaN anywhere; `strict`: no infinity either.
fn expectFinite(t: *const Tree, id: L.NodeId, strict: bool) !void {
    const l = t.layout(id);
    inline for (.{ l.x, l.y, l.w, l.h, l.content_w, l.content_h }) |v| try testing.expect(if (strict) std.math.isFinite(v) else !std.math.isNan(v));
    var ch = t.firstChild(id);
    while (ch != no_node) : (ch = t.nextSibling(ch)) try expectFinite(t, ch, strict);
}

test "inline row: NaN / inf / negative style values do not produce NaN layouts" {
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    var ctx: TextCtx = .{};
    const bad = [_]f32{ nan, inf, -inf, -50, 1e30, -1e30 };
    for (bad) |v| {
        for ([_]bool{ false, true }) |q| {
            var t = Tree.init(testing.allocator);
            defer t.deinit();
            const root = try t.addNode(.{ .display = .block, .size = .{ px(200), .auto } });
            const row = try child(&t, root, .{
                .display = .inline_row,
                .text_align = .justify,
                .strut_ascent = v,
                .strut_descent = -v,
                .strut_middle = v,
                .padding = .all(.{ .px = v }),
                .border = .all(v),
                .margin = .all(.{ .px = v }),
            });
            _ = try child(&t, row, .{ .display = .block, .size = .{ px(v), px(v) }, .margin = .all(.{ .px = v }), .vertical_align = .middle });
            _ = try child(&t, row, .{ .display = .block, .size = sz(30, 10), .min_size = .{ px(v), px(v) }, .max_size = .{ px(v), px(v) }, .vertical_align = .top });
            _ = try child(&t, row, .{ .display = .block, .size = .{ .{ .percent = v }, .{ .percent = v } }, .padding = .all(.{ .percent = v }), .vertical_align = .bottom });
            _ = try text(&t, row, .{ .display = .block, .margin = .all(.{ .percent = v }), .inset = .all(.{ .px = v }) });
            _ = try child(&t, row, .{ .display = .block, .position = .absolute, .size = .{ px(v), .auto }, .inset = .all(.{ .px = v }) });
            const row2 = try child(&t, row, .{ .display = .inline_row, .strut_ascent = v, .aspect_ratio = v });
            _ = try child(&t, row2, .{ .size = sz(10, 10), .aspect_ratio = v });
            for ([_]L.AvailableSpace{ .{ .definite = 400 }, .min_content, .max_content, .{ .definite = v } }) |av| {
                try t.compute(root, .{ av, .{ .definite = 300 } }, &ctx, TextCtx.measure, .{ .baseline = TextCtx.baseline, .quantize64 = q });
                // (an infinite border width is not sanitised by the box resolution: sizes may become infinite,
                // but never NaN)
                expectFinite(&t, root, !std.math.isInf(v)) catch |e| {
                    std.debug.print("non-finite layout: v={d} q64={} avail={any}\n", .{ v, q, av });
                    return e;
                };
            }
        }
    }
}

test "inline row: 150-deep nesting of inline_row > block > inline_row" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var t = Tree.init(arena_state.allocator());
    const root = try t.addNode(.{ .display = .inline_row, .size = .{ px(1000), .auto }, .strut_ascent = 3, .strut_descent = 1 });
    var cur = root;
    for (0..150) |_| {
        const blk = try child(&t, cur, .{ .display = .block, .padding = .all(.{ .px = 1 }) });
        _ = try child(&t, cur, bx(1, 1));
        cur = try child(&t, blk, .{ .display = .inline_row, .strut_ascent = 3, .strut_descent = 1 });
    }
    const leaf = try child(&t, cur, bx(10, 10));
    try run(&t, root);
    try expectFinite(&t, root, true);
    try expectRect(&t, leaf, 0, 0, 10, 10);
    // the innermost line is 10 + 1 tall; every level adds the padding of its block
    try testing.expectEqual(@as(f32, 11 + 150 * 2), t.layout(root).h);

    // too deep is an error, not a crash
    var t2 = Tree.init(arena_state.allocator());
    const r2 = try t2.addNode(.{ .display = .inline_row });
    cur = r2;
    for (0..L.max_depth) |_| cur = try child(&t2, cur, .{ .display = .inline_row });
    _ = try child(&t2, cur, bx(1, 1));
    try testing.expectError(error.TooDeep, t2.compute(r2, vp400, &T.dummy, T.noMeasure, .{}));
}
