//! Inline formatting contexts driven by `Options.inline_fn` (flow.zig): item sizing, per-line float bands,
//! floats met inside the lines, static positions, baselines, caching and nesting.
const std = @import("std");
const L = @import("layout.zig");
const T = L.TreeWith(.{ .inline_fn = true });
const expectEqual = std.testing.expectEqual;

/// A toy line breaker: every atomic item is a word; a measured leaf is `words` words of 40 x 10.
const Ctx = struct {
    words: u32 = 0,
    calls: u32 = 0,
    leaf_calls: u32 = 0,
    last_width: f32 = 0,

    fn measure(ctx: *anyopaque, _: L.NodeId, known: [2]?f32, avail: [2]L.AvailableSpace) [2]f32 {
        const c: *Ctx = @ptrCast(@alignCast(ctx));
        c.leaf_calls += 1;
        const total: f32 = @floatFromInt(c.words * 40);
        const w: f32 = known[0] orelse switch (avail[0]) {
            .definite => |v| @min(v, total),
            .min_content => 40,
            .max_content => total,
        };
        const per: f32 = @max(@floor(w / 40), 1);
        return .{ w, known[1] orelse @ceil(@as(f32, @floatFromInt(c.words)) / per) * 10 };
    }

    fn inlineFn(ctx: *anyopaque, _: L.NodeId, io: *L.InlineIo) void {
        const c: *Ctx = @ptrCast(@alignCast(ctx));
        c.calls += 1;
        c.last_width = io.width;
        var y: f32 = 0;
        var widest: f32 = 0;
        var i: usize = 0;
        var left = c.words;
        const n_atomic = blk: {
            var k: usize = 0;
            for (io.items) |it| k += @intFromBool(it.kind == .atomic);
            break :blk k;
        };
        var placed_atomic: usize = 0;
        while (placed_atomic < n_atomic or left > 0 or i < io.items.len) {
            // one line
            var band: L.InlineBand = .{ .x0 = 0, .x1 = io.width, .next_y = std.math.nan(f32) };
            if (io.band_fn) |bf| if (@abs(io.width) < std.math.inf(f32)) {
                band = bf(io, y, 10);
            };
            var x = band.x0;
            var h: f32 = 0;
            var any = false;
            while (i < io.items.len) : (i += 1) {
                const it = &io.items[i];
                switch (it.kind) {
                    .float => if (io.float_fn) |ff| {
                        if (!ff(io, @intCast(i), y, x - band.x0, band.x1 - band.x0, if (any) 1 else 0)) _ = ff(io, @intCast(i), y + @max(h, 10), 0, 0, 2);
                        if (io.band_fn) |bf| {
                            const b2 = bf(io, y, 10);
                            if (!any) x = b2.x0;
                            band = b2;
                        }
                    },
                    .out_of_flow => {
                        it.x = x;
                        it.y = y;
                        it.placed = true;
                    },
                    .atomic => {
                        if (any and x + it.width > band.x1) break;
                        it.x = x;
                        it.y = y;
                        it.placed = true;
                        x += it.width;
                        h = @max(h, it.height);
                        any = true;
                        placed_atomic += 1;
                        if (io.first_baseline != io.first_baseline) io.first_baseline = y + it.baseline;
                        io.last_baseline = y + it.baseline;
                    },
                }
            }
            while (left > 0 and (!any or x + 40 <= band.x1)) : (left -= 1) {
                x += 40;
                h = @max(h, 10);
                any = true;
                if (io.first_baseline != io.first_baseline) io.first_baseline = y + 8;
                io.last_baseline = y + 8;
            }
            if (!any) break;
            widest = @max(widest, x - band.x0);
            y += h;
        }
        io.size = .{ widest, y };
    }
};

const vp: [2]L.AvailableSpace = .{ .{ .definite = 400 }, .{ .definite = 300 } };
const px = struct {
    fn f(v: f32) L.Dim {
        return .{ .px = v };
    }
}.f;

test "flow: atomic items are sized by the engine and positioned by the callback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var t = T.init(arena.allocator());
    const root = try t.addNode(.{ .display = .block, .size = .{ px(300), .auto }, .padding = .all(.{ .px = 5 }) });
    const row = try t.addNode(.{ .display = .inline_row, .position = .static, .is_inline_content = true });
    try t.appendChild(root, row);
    var kids: [4]L.NodeId = undefined;
    for (&kids, 0..) |*k, i| {
        k.* = try t.addNode(.{ .display = .block, .size = .{ px(100), px(20 + 10 * @as(f32, @floatFromInt(i))) }, .margin = .{ .left = px(4), .top = px(2), .right = .{ .px = 0 }, .bottom = .{ .px = 0 } } });
        try t.appendChild(row, k.*);
    }
    const abs = try t.addNode(.{ .display = .block, .position = .absolute, .size = .{ px(8), px(8) } });
    try t.appendChild(row, abs);
    var ctx: Ctx = .{};
    try t.compute(root, vp, &ctx, Ctx.measure, .{ .inline_fn = Ctx.inlineFn });
    // lines of 290: two items (104 each) per line; line heights follow the margin boxes (22 / 32, 42 / 52)
    const rl = t.layout(row);
    try expectEqual(@as(f32, 290), rl.w);
    try expectEqual(@as(f32, 32 + 52), rl.h);
    try expectEqual(@as(f32, 5), rl.x);
    const a = t.layout(kids[0]);
    const b = t.layout(kids[1]);
    const c = t.layout(kids[2]);
    try std.testing.expect(a.x == 4 and a.y == 2 and b.x == 108 and b.y == 2 and c.x == 4 and c.y == 34);
    try expectEqual(@as(f32, 84 + 10), t.layout(root).h);
    // the out-of-flow child: static position at the end of the last line (its layout is relative to the row)
    const al = t.layout(abs);
    try std.testing.expect(al.w == 8 and al.x == 208 and al.y == 32);
    // intrinsic widths: max-content = all on one line, min-content = the widest item
    const fl = try t.addNode(.{ .display = .flex, .size = .{ .auto, .auto } });
    const root2 = try t.addNode(.{ .display = .flex, .size = .{ px(1000), .auto } });
    const blk = try t.addNode(.{ .display = .block, .flex_shrink = 0 });
    const row2 = try t.addNode(.{ .display = .inline_row, .position = .static, .is_inline_content = true });
    try t.appendChild(root2, fl);
    try t.appendChild(fl, blk);
    try t.appendChild(blk, row2);
    for (0..3) |_| try t.appendChild(row2, try t.addNode(.{ .display = .block, .size = .{ px(50), px(10) } }));
    try t.compute(root2, .{ .{ .definite = 1000 }, .{ .definite = 300 } }, &ctx, Ctx.measure, .{ .inline_fn = Ctx.inlineFn });
    try expectEqual(@as(f32, 150), t.layout(blk).w);
    try expectEqual(@as(f32, 10), t.layout(blk).h);
}

test "flow: lines shorten beside floats while the box keeps its width; leaves take the fast path without floats" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var t = T.init(arena.allocator());
    const root = try t.addNode(.{ .display = .block, .size = .{ px(300), .auto }, .flow_root = true });
    const flt = try t.addNode(.{ .display = .block, .float = .left, .size = .{ px(80), px(25) } });
    const leaf = try t.addNode(.{ .display = .block, .is_inline_content = true });
    t.setMeasured(leaf, true);
    try t.appendChild(root, flt);
    try t.appendChild(root, leaf);
    var ctx: Ctx = .{ .words = 14 };
    try t.compute(root, vp, &ctx, Ctx.measure, .{ .inline_fn = Ctx.inlineFn });
    // 3 lines of 5 words beside the float (220 px, y 0..30), the 4th line would start below it: 15 > 14 words
    const ll = t.layout(leaf);
    try std.testing.expect(ll.x == 0 and ll.w == 300 and ll.h == 30);
    try std.testing.expect(ctx.calls > 0 and ctx.last_width == 300);
    try expectEqual(@as(f32, 8), ll.baseline);
    // 20 words: 3 short lines (15 words), then one full line (5 of 7 possible)
    ctx = .{ .words = 20 };
    try t.compute(root, vp, &ctx, Ctx.measure, .{ .inline_fn = Ctx.inlineFn });
    try expectEqual(@as(f32, 40), t.layout(leaf).h);
    // without floats the leaf is a plain measured leaf (the inline callback is not involved)
    var t2 = T.init(arena.allocator());
    const r2 = try t2.addNode(.{ .display = .block, .size = .{ px(300), .auto } });
    const l2 = try t2.addNode(.{ .display = .block, .is_inline_content = true });
    t2.setMeasured(l2, true);
    try t2.appendChild(r2, l2);
    ctx = .{ .words = 14 };
    try t2.compute(r2, vp, &ctx, Ctx.measure, .{ .inline_fn = Ctx.inlineFn });
    try std.testing.expect(ctx.calls == 0 and ctx.leaf_calls > 0 and t2.layout(l2).h == 20);

    // floats met inside the inline content: beside the line when they fit, else below it
    var t3 = T.init(arena.allocator());
    const r3 = try t3.addNode(.{ .display = .block, .size = .{ px(300), .auto }, .flow_root = true });
    const row = try t3.addNode(.{ .display = .inline_row, .position = .static, .is_inline_content = true });
    try t3.appendChild(r3, row);
    const w1 = try t3.addNode(.{ .display = .block, .size = .{ px(100), px(10) } });
    const f1 = try t3.addNode(.{ .display = .block, .float = .right, .size = .{ px(60), px(30) } });
    const w2 = try t3.addNode(.{ .display = .block, .size = .{ px(100), px(10) } });
    const f2 = try t3.addNode(.{ .display = .block, .float = .left, .size = .{ px(250), px(12) } });
    const w3 = try t3.addNode(.{ .display = .block, .size = .{ px(100), px(10) } });
    for ([_]L.NodeId{ w1, f1, w2, f2, w3 }) |k| try t3.appendChild(row, k);
    ctx = .{};
    try t3.compute(r3, vp, &ctx, Ctx.measure, .{ .inline_fn = Ctx.inlineFn });
    // f1 fits beside w1 (100 + 60 <= 300): top right of line 1; f2 (250) does not fit after w1 w2: it goes
    // below line 1, and there below f1 (only 240 px are free beside it)
    try std.testing.expect(t3.layout(f1).x == 240 and t3.layout(f1).y == 0);
    try std.testing.expect(t3.layout(f2).x == 0 and t3.layout(f2).y == 30);
    try std.testing.expect(t3.layout(w2).x == 100 and t3.layout(w2).y == 0);
    // line 2 (y = 10) still has the 240 px beside f1
    try std.testing.expect(t3.layout(w3).x == 0 and t3.layout(w3).y == 10);
    // the formatting context root grows to contain the floats
    try expectEqual(@as(f32, 42), t3.layout(r3).h);
}

test "flow: untrusted callback results and deep nesting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const Bad = struct {
        fn inlineFn(_: *anyopaque, _: L.NodeId, io: *L.InlineIo) void {
            io.size = .{ std.math.nan(f32), -std.math.inf(f32) };
            io.first_baseline = std.math.inf(f32);
            for (io.items) |*it| {
                it.x = std.math.nan(f32);
                it.y = std.math.inf(f32);
                it.placed = true;
            }
            if (io.float_fn) |ff| _ = ff(io, 99, std.math.nan(f32), 0, 0, 7);
            if (io.band_fn) |bf| _ = bf(io, std.math.nan(f32), std.math.inf(f32));
        }
    };
    var t = T.init(arena.allocator());
    const root = try t.addNode(.{ .display = .block, .size = .{ px(100), .auto }, .flow_root = true });
    try t.appendChild(root, try t.addNode(.{ .display = .block, .float = .left, .size = .{ px(10), px(10) } }));
    const row = try t.addNode(.{ .display = .inline_row, .position = .static, .is_inline_content = true });
    try t.appendChild(root, row);
    const kid = try t.addNode(.{ .display = .block, .size = .{ px(10), px(10) } });
    try t.appendChild(row, kid);
    try t.appendChild(row, try t.addNode(.{ .display = .block, .position = .absolute }));
    try t.appendChild(row, try t.addNode(.{ .display = .block, .float = .right }));
    var ctx: Ctx = .{};
    try t.compute(root, vp, &ctx, Ctx.measure, .{ .inline_fn = Bad.inlineFn });
    for (0..t.nodes.items.len) |i| {
        const l = t.layout(@intCast(i));
        try std.testing.expect(std.math.isFinite(l.x) and std.math.isFinite(l.y) and std.math.isFinite(l.w) and std.math.isFinite(l.h));
    }
    // inline_row > block > inline_row ... : 2 levels per pair, fails cleanly past max_depth
    for ([_]usize{ 200, 300 }) |pairs| {
        var d = T.init(arena.allocator());
        const r = try d.addNode(.{ .display = .block, .size = .{ px(100), .auto } });
        var cur = r;
        for (0..pairs) |_| {
            const ir = try d.addNode(.{ .display = .inline_row, .position = .static, .is_inline_content = true });
            const bl = try d.addNode(.{ .display = .block });
            try d.appendChild(cur, ir);
            try d.appendChild(ir, bl);
            cur = bl;
        }
        const res = d.compute(r, vp, &ctx, Ctx.measure, .{ .inline_fn = Ctx.inlineFn });
        if (pairs * 2 + 1 <= L.max_depth) try res else try std.testing.expectError(error.TooDeep, res);
    }
}
