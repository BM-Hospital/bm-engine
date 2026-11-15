//! Inline formatting contexts (`Config.inline_fn`): a `Display.inline_row` node whose inline content (text
//! and inline boxes) is owned by the caller, and whose children are its inline-level BOXES: atomic inlines
//! (laid out shrink-to-fit here, then positioned on the lines), floats that occur inside the text and
//! out-of-flow boxes (static position at their point of occurrence). A measured leaf flagged
//! `Style.is_inline_content` takes the same path when floats may intrude (it has no items).
//!
//! The engine does not break lines itself. It sizes the atomic items and calls `Options.inline_fn`
//! (`tree.InlineFn`) with an `InlineIo`; the callback breaks its text into lines of `io.width`, treats each
//! atomic item as an unbreakable box of the given margin-box size and baseline, and reports the content size,
//! the baselines and the item positions. While it does so it may ask the engine, per line, for the inline
//! range the floats of the block formatting context leave free (`io.band_fn`: Blink's layout opportunities,
//! in the content-box coordinates of this node) and hand over the floats it meets (`io.float_fn`): the box
//! itself keeps the full width of its containing block, only its lines shorten.
//!
//! Model (Blink's inline layout for atomic inlines, verified against the takumi oracle):
//!  * An atomic item is as wide as its `width` style, else shrink-to-fit against the width of the
//!    containing block (not the room left on its line): `min(max-content, max(min-content, width))`.
//!    Under a max-/min-content constraint it has its max-/min-content width.
//!  * Its baseline is `Out.last_baseline` for a block container (the baseline of its last line box), the
//!    first baseline for other boxes, and the bottom margin edge when there is none or the box is a block
//!    container with a non-visible overflow.
//!  * Oracle quirk reproduced: the percentage part of an item's MARGINS resolves to 0.
//!  * Intrinsic widths: floats take no part in line layout; under max-content they add their widths to the
//!    widest line, under min-content each stands alone.
const std = @import("std");
const st = @import("style.zig");
const tr = @import("tree.zig");
const fl = @import("floats.zig");
const block = @import("block.zig");

const In = tr.In;
const Out = tr.Out;
const Box = tr.Box;
const Error = tr.Error;
const NONE = tr.NONE;
const MAXC = tr.MAXC;
const MINC = tr.MINC;
const has = tr.has;
const orElse = tr.orElse;
const clampO = tr.clampO;
const maxO = tr.maxO;
const no_node = tr.no_node;

const fit_eps: f32 = 0.005;

/// Per-node state kept in the tree's scratch arena (see `Tree.computeNode` on stack discipline).
const S = struct {
    in: In,
    box: Box,
    /// box of the item being sized
    cb: Box,
    known: [2]f32,
    inset: [4]f32,
    /// percentage basis of the items (content box of the node)
    parent: [2]f32,
    content: [2]f32,
    ci: In,
    co: Out,
    area: [4]f32,
    sp: tr.StaticPos,
    io: tr.InlineIo,
    frq: block.FloatReq,
    tree: *anyopaque,
    /// border-box origin in the coordinates of the block formatting context
    org: [2]f32,
    line_w: f32,
    ckh: f32,
    err: ?Error,
    /// the float item placed last and `Bfc.last_top` before it (for `float_fn` how = 3)
    undo_item: u32,
    undo_top: f32,
    resume_from: f32 = std.math.inf(f32),
    resume_dy: f32 = 0,
};

fn Host(comptime T: type) type {
    return struct {
        fn band(io: *const tr.InlineIo, y: f32, h: f32) tr.InlineBand {
            const c: *S = @ptrCast(@alignCast(io.host));
            const t: *T = @ptrCast(@alignCast(c.tree));
            const full: tr.InlineBand = .{ .x0 = 0, .x1 = c.line_w, .next_y = NONE };
            const bf = t.bfc orelse return full;
            const rects = t.float_rects.items[@min(bf.start, t.float_rects.items.len)..];
            if (rects.len == 0 or !(y == y) or !(h == h)) return full;
            const cl = c.org[0] + c.inset[0];
            const ct = c.org[1] + c.inset[1] + (if (y >= c.resume_from) c.resume_dy else 0);
            const e = fl.edges(rects, ct + y, @max(h, 0));
            const x0 = @max(e[0] - cl, 0);
            const x1 = @max(@min(e[1] - cl, c.line_w), x0);
            if (x0 <= 0 and x1 >= c.line_w) return full;
            return .{ .x0 = x0, .x1 = x1, .next_y = fl.nextBottom(rects, ct + y, @max(h, 0)) - ct };
        }

        fn float(io: *const tr.InlineIo, item: u32, y: f32, used: f32, avail: f32, how: u8) bool {
            const c: *S = @ptrCast(@alignCast(io.host));
            const t: *T = @ptrCast(@alignCast(c.tree));
            if (item >= io.items.len or c.err != null) return true;
            const it = &io.items[item];
            if (how == 3) {
                // take back the float placed last (see `InlineIo.float_fn`)
                const bf = t.bfc orelse return true;
                if (it.kind == .float and it.placed and c.undo_item == item and t.float_rects.items.len > bf.start) {
                    t.float_rects.items.len -= 1;
                    bf.last_top = c.undo_top;
                    it.placed = false;
                    c.undo_item = no_node;
                }
                return true;
            }
            if (it.kind != .float or it.placed) return true;
            c.undo_item = no_node;
            if (t.bfc) |bf| c.undo_top = bf.last_top;
            c.frq = .{
                .parent = c.parent,
                .org = c.org,
                .inset_left = c.inset[0],
                .y_top = c.inset[1] + (if (y == y) y else 0),
                .do_layout = c.in.layout,
                .fit = if (how == 1) .{ used, avail } else null,
            };
            const placed = block.placeFloat(t, it.node, &c.frq, &c.content) catch |e| {
                c.err = e;
                return true;
            };
            it.placed = placed;
            if (placed) c.undo_item = item;
            return placed;
        }
    };
}

pub noinline fn compute(t: anytype, node: u32, in_: *const In, out: *Out, in_floats: bool) Error!void {
    const T = @TypeOf(t.*);
    const mark = t.scratch.mark();
    defer t.scratch.release(mark);
    const c = try t.scratch.create(t.alloc, S);
    c.resume_from = std.math.inf(f32);
    c.resume_dy = 0;
    if (comptime st.frag_enabled) if (t.paged.inline_resume) |continuation| if (continuation.node == node) {
        c.resume_from = continuation.from_y;
        c.resume_dy = continuation.dy;
    };
    c.in = in_.*;
    c.tree = t;
    c.err = null;
    c.undo_item = no_node;
    c.undo_top = 0;
    c.org = t.bfc_org;
    const in = &c.in;
    const n = &t.nodes.items[node];
    const s = &n.style;
    t.sbox(&c.box, s, in);
    const box = &c.box;
    c.known = tr.styledKnown(in, box);
    const known = &c.known;
    if (!in.layout and has(known[0]) and has(known[1])) {
        out.* = .{ .size = known.* };
        return;
    }
    const cb_fn = t.inline_fn orelse {
        out.* = .{ .size = .{ orElse(known[0], box.pb[0]), orElse(known[1], box.pb[1]) } };
        return;
    };
    // (an infinite border width survives the box resolution: keep the positions finite)
    for (0..4) |i| c.inset[i] = orElse(tr.fin(box.padding[i] + box.border[i]), 0);
    const pb = box.pb;
    // percentage heights of the items: against the node's own height when it has one, else against the
    // containing block's (the node is normally an anonymous box of a block container)
    const inner_h: f32 = if (has(known[1]) and !in.indef_h) @max(known[1] - pb[1], 0) else in.parent[1];

    // the items: every child that generates a box (a measured leaf has none)
    var items: []tr.InlineItem = &.{};
    if (n.measured) {
        if (n.child_count != 0) {
            var ch = n.first_child;
            while (ch != no_node) : (ch = t.nextSibling(ch)) t.hide(ch);
        }
    } else {
        var count: usize = 0;
        var ch = n.first_child;
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            if (t.nodes.items[ch].style.display != .none) count += 1;
        }
        items = try t.scratch.alloc(t.alloc, tr.InlineItem, count);
        count = 0;
        ch = n.first_child;
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display == .none) {
                if (in.layout) t.hide(ch);
                continue;
            }
            items[count] = .{
                .node = ch,
                .kind = if (cs.position.isOut()) .out_of_flow else if ((comptime T.config.floats) and cs.float != .none) .float else .atomic,
            };
            count += 1;
        }
    }

    var outer_w = known[0];
    if (!has(outer_w)) {
        // intrinsic width: the widest line, percentages of the items being indefinite
        c.parent = .{ NONE, inner_h };
        c.line_w = maxO(tr.minO(in.avail[0] - box.marginSum(0), box.max[0]) - pb[0], 0);
        if (in.avail[0] == MINC) c.line_w = MINC;
        const float_w = try sizeItems(t, c, items, false);
        c.io = .{ .width = c.line_w, .width_only = true, .items = items, .host = c };
        cb_fn(t.ctx, node, &c.io);
        var w = orElse(tr.fin(c.io.size[0]), 0);
        if (c.line_w == MINC) {
            w = @max(w, float_w);
        } else if (float_w > 0) {
            w = if (tr.isDef(c.line_w)) @max(w, @min(w + float_w, c.line_w)) else w + float_w;
        }
        outer_w = @max(clampO(w + pb[0], box.min[0], box.max[0]), pb[0]);
    }
    if (in.width_only) {
        out.* = .{ .size = .{ outer_w, NONE } };
        return;
    }

    const inner_w = @max(outer_w - pb[0], 0);
    c.parent = .{ inner_w, inner_h };
    c.line_w = inner_w;
    c.content = .{ 0, 0 };
    _ = try sizeItems(t, c, items, true);
    c.io = .{ .width = inner_w, .layout = in.layout, .items = items, .host = c };
    if ((comptime T.config.floats) and in_floats) {
        const H = Host(T);
        c.io.band_fn = H.band;
        c.io.float_fn = H.float;
    }
    cb_fn(t.ctx, node, &c.io);
    if (c.err) |e| return e;
    const io = &c.io;
    const text_w = orElse(tr.fin(io.size[0]), 0);
    const text_h = @max(orElse(tr.fin(io.size[1]), 0), 0);

    const outer_h = @max(orElse(known[1], clampO(text_h + pb[1], box.min[1], box.max[1])), pb[1]);
    out.* = .{ .size = .{ outer_w, outer_h } };
    if (has(io.first_baseline)) out.baseline = c.inset[1] + io.first_baseline;
    if (has(io.last_baseline)) out.last_baseline = c.inset[1] + io.last_baseline;
    // (inline content without line boxes is an empty block: margins collapse through it)
    out.collapse_through = !has(io.first_baseline) and outer_h == 0 and !n.measured;
    if (!in.layout) return;

    c.area = .{ box.border[0], box.border[1], outer_w - box.border[0] - box.border[2], outer_h - box.border[1] - box.border[3] };
    for (items) |*it| {
        switch (it.kind) {
            .atomic => {
                // (an item the callback put on no line, e.g. beyond a line clamp, generates no box)
                if (!it.placed) {
                    t.hide(it.node);
                    continue;
                }
                if (!tr.isDef(it.x) or !tr.isDef(it.y)) {
                    it.x = 0;
                    it.y = 0;
                }
                const cs = &t.nodes.items[it.node].style;
                const l = &t.layouts.items[it.node];
                l.x = c.inset[0] + it.x + it.margin[0] + orElse(t.dim(cs.inset.left, c.parent[0]), -orElse(t.dim(cs.inset.right, c.parent[0]), 0));
                l.y = c.inset[1] + it.y + it.margin[1] + orElse(t.dim(cs.inset.top, c.parent[1]), -orElse(t.dim(cs.inset.bottom, c.parent[1]), 0));
                t.accumContent(&c.content, it.node);
            },
            .out_of_flow => {
                const x = if (it.placed and tr.isDef(it.x)) it.x else 0;
                const y = if (it.placed and tr.isDef(it.y)) it.y else 0;
                c.sp = .{ .rect = .{ c.inset[0] + x, c.inset[1] + y, 0, 0 }, .al = .{ if (it.rtl) 2 else 0, 0 } };
                try t.placeAbsolute(node, it.node, &c.area, &c.sp);
                t.accumContent(&c.content, it.node);
            },
            // (placed by `Host.float`; one the callback never met generates no box)
            .float => if (!it.placed) t.hide(it.node),
        }
    }
    out.content = .{ @max(c.content[0], c.inset[0] + text_w), @max(c.content[1], c.inset[1] + text_h) };
}

/// Sizes the atomic items for lines of `c.line_w` (margin-box width; with `full` also the height and the
/// baseline, the item being laid out) and returns the summed (max-content) or largest (min-content)
/// margin-box width of the float items.
noinline fn sizeItems(t: anytype, c: *S, items: []tr.InlineItem, full: bool) Error!f32 {
    var float_w: f32 = 0;
    for (items) |*it| {
        const ch = it.node;
        const cn = &t.nodes.items[ch];
        const cs = &cn.style;
        switch (it.kind) {
            .out_of_flow => {},
            .float => if (!full) {
                t.rbox(&c.cb, cs, c.parent);
                var w = clampO(c.cb.size[0], c.cb.min[0], c.cb.max[0]);
                if (!has(w)) {
                    c.ci = .{ .known = .{ NONE, NONE }, .parent = c.parent, .avail = .{ if (c.line_w == MINC) MINC else MAXC, MAXC } };
                    w = try t.measureChild(ch, &c.ci, 0);
                }
                w = @max(w, c.cb.pb[0]) + c.cb.marginSum(0);
                float_w = if (c.line_w == MINC) @max(float_w, w) else float_w + @max(w, 0);
            },
            .atomic => {
                const w = try itemWidth(t, c, ch);
                const cb = &c.cb;
                it.margin = .{ cb.margin[0], cb.margin[1] };
                it.width = w + cb.marginSum(0);
                if (!full) continue;
                c.ci = .{ .known = .{ w, c.ckh }, .parent = c.parent, .avail = .{ c.line_w, MAXC }, .layout = true };
                try t.computeNode(ch, &c.ci, &c.co);
                const o = &c.co;
                it.height = o.size[1] + cb.marginSum(1);
                // a block container sits on the baseline of its last line box, unless it is a scroll
                // container; a box without a baseline on its bottom margin edge
                const blk = cs.display == .block;
                const bl = if (blk) o.last_baseline else o.baseline;
                const synth = !has(bl) or (blk and (cs.overflow_y != .visible or cs.overflow_x != .visible));
                it.baseline = if (synth) it.height else cb.margin[1] + bl;
                // (the position is patched in once the lines are known)
                if (c.in.layout) t.setLayout(ch, .{ 0, 0 }, o, cb);
            },
        }
    }
    return float_w;
}

/// Border-box width of the atomic item `ch` on lines of `c.line_w`; leaves the item's box in `c.cb` and
/// its height (NaN = auto) in `c.ckh`.
noinline fn itemWidth(t: anytype, c: *S, ch: u32) Error!f32 {
    const cn = &t.nodes.items[ch];
    t.rbox(&c.cb, &cn.style, c.parent);
    const cb = &c.cb;
    // (percentage margins resolve against the containing block width, as in CSS / Chrome; takumi takes
    // their percentage part as 0)
    c.ckh = maxO(clampO(cb.size[1], cb.min[1], cb.max[1]), cb.pb[1]);
    var w = cb.size[0];
    if (!has(w)) {
        const ms = cb.marginSum(0);
        c.ci = .{ .known = .{ NONE, c.ckh }, .parent = c.parent, .avail = .{ if (c.line_w == MINC) MINC else MAXC, MAXC } };
        w = try t.measureChild(ch, &c.ci, 0);
        if (tr.isDef(c.line_w) and w + ms - c.line_w > fit_eps) {
            // shrink-to-fit
            c.ci = .{ .known = .{ NONE, c.ckh }, .parent = c.parent, .avail = .{ MINC, MAXC } };
            const min_w = try t.measureChild(ch, &c.ci, 0);
            w = @min(w, @max(min_w, c.line_w - ms));
        }
    }
    return @max(clampO(w, c.cb.min[0], c.cb.max[0]), c.cb.pb[0]);
}
