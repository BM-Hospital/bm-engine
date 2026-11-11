//! Block layout: vertical stacking of block-level children with margin collapsing (CSS 2.1 §8.3.1, §10).
//! No floats and no inline formatting; text is a measured leaf treated as a block-level box.
const std = @import("std");
const st = @import("style.zig");
const tr = @import("tree.zig");

const Tree = tr.Tree;
const In = tr.In;
const Out = tr.Out;
const Error = tr.Error;
const MarginSet = tr.MarginSet;
const NONE = tr.NONE;
const MAXC = tr.MAXC;
const has = tr.has;
const orElse = tr.orElse;
const clampO = tr.clampO;
const maxO = tr.maxO;
const no_node = tr.no_node;

const AbsItem = struct { node: u32, y: f32 };

pub fn compute(t: *Tree, node: u32, in: In) Error!Out {
    const n = &t.nodes.items[node];
    const s = &n.style;
    var box = t.sbox(s, &in);
    var known = tr.styledKnown(in, &box);
    if (!in.layout and has(known[0]) and has(known[1])) return .{ .size = known };
    _ = t.applyRatio(s, &box, &known);

    var inset: [4]f32 = undefined;
    for (0..4) |i| inset[i] = box.padding[i] + box.border[i];
    const pb = box.pb;
    var inner_h: f32 = if (in.indef_h) NONE else maxO(known[1] - pb[1], 0);

    // container width
    var outer_w = known[0];
    if (!has(outer_w)) {
        const avail_w = in.avail[0] - box.marginSum(0) - pb[0];
        var max_w: f32 = 0;
        var ch = n.first_child;
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display == .none or cs.position == .absolute) continue;
            const cb = t.rbox(cs, .{ NONE, inner_h });
            const ms = cb.marginSum(0);
            var w = clampO(orElse(cb.size[0], t.ratio(cs, &cb, 0, clampO(cb.size[1], cb.min[1], cb.max[1]))), cb.min[0], cb.max[0]);
            if (!has(w)) {
                w = try t.measureChild(ch, .{
                    .known = .{ NONE, clampO(cb.size[1], cb.min[1], cb.max[1]) },
                    .parent = .{ NONE, inner_h },
                    .avail = .{ avail_w, MAXC },
                }, 0);
            }
            max_w = @max(max_w, @max(w, cb.pb[0]) + ms);
        }
        outer_w = @max(clampO(max_w + pb[0], box.min[0], box.max[0]), pb[0]);
    }
    known[0] = outer_w;
    if (in.width_only) return .{ .size = .{ outer_w, NONE } };
    {
        const floor_h = t.applyRatio(s, &box, &known);
        if (has(floor_h)) {
            box.min[1] = floor_h;
            inner_h = @max(floor_h - pb[1], 0);
        } else if (!in.indef_h) inner_h = maxO(known[1] - pb[1], 0);
    }
    if (!in.layout and has(known[1])) return .{ .size = .{ outer_w, known[1] } };

    const bfc = !in.collapse or s.position == .absolute or
        s.overflow_x == .hidden or s.overflow_x == .scroll or s.overflow_y == .hidden or s.overflow_y == .scroll;
    const collapse_top = !bfc and inset[1] == 0;
    var collapse_bottom = !bfc and inset[3] == 0 and !has(known[1]);
    const prevents_collapse_through = bfc or inset[1] > 0 or inset[3] > 0 or known[1] > 0 or box.min[1] > 0;

    const inner_w = @max(outer_w - pb[0], 0);
    const parent: [2]f32 = .{ inner_w, inner_h };

    const mark = t.scratch.mark();
    defer t.scratch.release(mark);
    var n_abs: usize = 0;
    var abs: []AbsItem = &.{};
    if (in.layout) {
        var ch = n.first_child;
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display != .none and cs.position == .absolute) n_abs += 1;
        }
        if (n_abs > 0) abs = try t.scratch.alloc(t.alloc, AbsItem, n_abs);
        n_abs = 0;
    }

    var content: [2]f32 = .{ 0, 0 };
    var y = inset[1];
    var y_abs = y;
    var first_set: MarginSet = .{};
    var active: MarginSet = .{};
    var with_first = true;
    var all_through = true;
    var first_bl: f32 = NONE;

    var ch = n.first_child;
    while (ch != no_node) : (ch = t.nextSibling(ch)) {
        const cs = &t.nodes.items[ch].style;
        if (cs.display == .none) {
            if (in.layout) t.hide(ch);
            continue;
        }
        if (cs.position == .absolute) {
            if (in.layout) {
                abs[n_abs] = .{ .node = ch, .y = y_abs };
                n_abs += 1;
            }
            continue;
        }
        var cb = t.rbox(cs, parent);
        const ms = cb.marginSum(0);
        const ckh = maxO(clampO(cb.size[1], cb.min[1], cb.max[1]), cb.pb[1]);
        // width: explicit, else from a definite height through the aspect ratio, else fill the container
        const ckw = orElse(orElse(cb.size[0], t.ratio(cs, &cb, 0, ckh)), inner_w - ms);
        const ck: [2]f32 = .{ @max(clampO(ckw, cb.min[0], cb.max[0]), cb.pb[0]), ckh };
        const o = try t.computeNode(ch, .{ .known = ck, .parent = parent, .avail = .{ inner_w, MAXC }, .layout = true, .collapse = true });

        const top_set = o.top_margin.with(cb.margin[1]);
        const bottom_set = o.bottom_margin.with(cb.margin[3]);

        // auto horizontal margins
        const free_x = @max(inner_w - o.size[0] - ms, 0);
        const n_auto: f32 = @floatFromInt(@as(u8, @intFromBool(cb.margin_auto[0])) + @intFromBool(cb.margin_auto[2]));
        if (n_auto > 0) {
            if (cb.margin_auto[0]) cb.margin[0] = free_x / n_auto;
            if (cb.margin_auto[2]) cb.margin[2] = free_x / n_auto;
        }
        cb.margin[1] = top_set.resolve();
        cb.margin[3] = bottom_set.resolve();

        const y_margin: f32 = if (with_first and collapse_top) 0 else active.merge(top_set).resolve();
        if (in.layout) {
            const rel: [2]f32 = .{
                orElse(t.dim(cs.inset.left, inner_w), -orElse(t.dim(cs.inset.right, inner_w), 0)),
                orElse(t.dim(cs.inset.top, inner_h), -orElse(t.dim(cs.inset.bottom, inner_h), 0)),
            };
            t.setLayout(ch, .{ inset[0] + cb.margin[0] + rel[0], y + y_margin + rel[1] }, &o, &cb);
            t.accumContent(&content, ch);
            if (!has(first_bl) and has(o.baseline)) first_bl = y + y_margin + o.baseline;
        }

        if (with_first) {
            first_set = first_set.merge(top_set);
            if (o.collapse_through) first_set = first_set.merge(bottom_set) else with_first = false;
        }
        if (o.collapse_through) {
            active = active.merge(top_set).merge(bottom_set);
            y_abs = y + o.size[1] + y_margin;
        } else {
            all_through = false;
            y += o.size[1] + y_margin;
            active = bottom_set;
            y_abs = y + active.resolve();
        }
    }

    y += inset[3];
    if (collapse_bottom and box.min[1] > y) {
        // min-height enlarges the box: the last child's margin stays inside and is not propagated
        collapse_bottom = false;
        active = .{};
    }
    // (when every child collapsed through and the top collapses, these margins already left through the top)
    if (!collapse_bottom and !(with_first and collapse_top)) y += active.resolve();
    const outer_h = @max(orElse(known[1], clampO(@max(y, 0), box.min[1], box.max[1])), pb[1]);
    var out: Out = .{ .size = .{ outer_w, outer_h } };
    if (!in.layout) return out;

    if (n_abs > 0) {
        const area: [4]f32 = .{ box.border[0], box.border[1], outer_w - box.border[0] - box.border[2], outer_h - box.border[1] - box.border[3] };
        for (abs[0..n_abs]) |a| {
            try t.placeAbsolute(node, a.node, area, .{ .rect = .{ inset[0], a.y, inner_w, 0 } });
            t.accumContent(&content, a.node);
        }
    }
    out.content = content;
    out.baseline = first_bl;
    out.top_margin = if (collapse_top) first_set else .{};
    out.bottom_margin = if (collapse_bottom) active else .{};
    out.collapse_through = !prevents_collapse_through and all_through and outer_h == 0;
    return out;
}
