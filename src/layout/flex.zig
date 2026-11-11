//! CSS Flexbox (css-flexbox-1 §9), structured after taffy's implementation, axis-indexed (m = main, x = cross).
const std = @import("std");
const st = @import("style.zig");
const tr = @import("tree.zig");

const Tree = tr.Tree;
const In = tr.In;
const Out = tr.Out;
const Box = tr.Box;
const Error = tr.Error;
const NONE = tr.NONE;
const MAXC = tr.MAXC;
const MINC = tr.MINC;
const has = tr.has;
const orElse = tr.orElse;
const minO = tr.minO;
const maxO = tr.maxO;
const clampO = tr.clampO;
const isDef = tr.isDef;
const no_node = tr.no_node;

const Item = struct {
    node: u32,
    box: Box,
    /// relative-position offset (already combined from inset)
    rel: [2]f32,
    al: st.Align,
    grow: f32,
    shrink: f32,
    basis: f32,
    inner_basis: f32,
    violation: f32,
    /// share of the remaining free space (Blink's free_space_fraction)
    frac: f64,
    min_main: f32,
    /// hypothetical border-box size
    hyp: [2]f32,
    target: [2]f32,
    baseline: f32,
    off_main: f32,
    off_cross: f32,
    frozen: bool,
    indef: bool,
    cross_auto: bool,
    basis_definite: bool,
    /// definite cross size used when measuring the item (NaN = none)
    ck: f32,
    cross_avail: f32,
    scroll_main: bool,
};

const Line = struct {
    start: u32,
    end: u32,
    cross: f32 = 0,
    off: f32 = 0,
};

/// Blink's LayoutUnitDiffuser: `size` split into `n` buckets that differ by at most one layout unit
/// (exact division when not laying out on the 1/64 px grid).
pub const Diffuser = struct {
    q: bool = false,
    base: f32 = 0,
    dx: u64 = 0,
    dy: u64 = 0,
    x: u64 = 0,
    y: u64 = 0,

    pub fn init(q: bool, size: f32, n: usize) Diffuser {
        if (n == 0 or !(size > 0)) return .{};
        if (!q) return .{ .base = size / @as(f32, @floatFromInt(n)) };
        const raw: u64 = @intFromFloat(@min(@trunc(size * 64), 2.0e9));
        return .{ .q = true, .base = @as(f32, @floatFromInt(raw / n)) / 64, .dx = (raw % n) * 2, .dy = n * 2, .y = n };
    }
    pub fn next(d: *Diffuser) f32 {
        if (!d.q) return d.base;
        d.x += d.dx;
        if (d.x >= d.y) {
            d.y += d.dy;
            return d.base + 1.0 / 64.0;
        }
        return d.base;
    }
};

/// Blink's InitialContentPositionOffset: offset of the first item/line for a content alignment.
pub fn firstOffset(t: *const Tree, free: f32, n: usize, mode: st.Align, reversed: bool) f32 {
    const flow_start: f32 = if (reversed) free else 0;
    const nf: f32 = @floatFromInt(n);
    return switch (mode) {
        .space_between => if (free > 0 and n > 1) 0 else flow_start,
        .space_around => if (free > 0 and n > 0) t.div(free, 2 * nf) else @max(t.div(free, 2), 0),
        .space_evenly => if (free > 0 and n > 0) t.div(free, nf + 1) else @max(t.div(free, 2), 0),
        .center => t.div(free, 2),
        .start => 0,
        .end => free,
        .flex_end => if (reversed) 0 else free,
        else => flow_start,
    };
}

/// Blink's ContentDistributionSpace: the extra space between adjacent items/lines.
pub fn spacing(t: *const Tree, free: f32, n: usize, mode: st.Align) Diffuser {
    if (!(free > 0) or n <= 1) return .{};
    return switch (mode) {
        .space_between => Diffuser.init(t.q64, free, n - 1),
        .space_evenly => Diffuser.init(t.q64, free, n + 1),
        .space_around => Diffuser.init(t.q64, free, n),
        else => .{},
    };
}

fn gapSum(gap: f32, n: usize) f32 {
    return if (n > 1) gap * @as(f32, @floatFromInt(n - 1)) else 0;
}

pub fn compute(t: *Tree, node: u32, in_: In) Error!Out {
    var in = in_;
    const s = &t.nodes.items[node].style;
    const box = t.sbox(s, &in);
    in.known = tr.styledKnown(in, &box);
    if (!in.layout and has(in.known[0]) and has(in.known[1])) return .{ .size = in.known };
    // width from a definite height through the aspect ratio; under a min-content request the automatic
    // content-based minimum still applies, so the content width is computed as well
    var ratio_w: f32 = NONE;
    if (!has(in.known[0])) {
        var k = in.known;
        _ = t.applyRatio(s, &box, &k);
        ratio_w = k[0];
        if (!(in.avail[0] == MINC and s.overflow_x == .visible and s.min_size[0] == .auto)) in.known[0] = ratio_w;
    }
    if (!has(in.known[0])) {
        // The inline size is always resolved before layout (fit-content of the intrinsic sizes).
        const a0 = in.avail[0] - box.marginSum(0) - box.pb[0];
        if (s.flex_direction == .row or s.flex_direction == .row_reverse) {
            in.known[0] = (try impl(t, node, in, &box, true, NONE)).size[0];
        } else {
            // column: widest item; a wrapping column is as wide as its columns (fit-content)
            var w: f32 = NONE;
            const wrapping = s.flex_wrap != .nowrap and a0 != MINC;
            if (wrapping) {
                var probe = in;
                probe.layout = false;
                w = (try impl(t, node, probe, &box, false, NONE)).size[0];
                if (w - box.pb[0] <= a0) in.known[0] = w;
            }
            if (!has(in.known[0])) {
                const ph: f32 = if (in.indef_h) NONE else maxO(in.known[1] - box.pb[1], 0);
                var mw: f32 = 0;
                var ch = t.firstChild(node);
                while (ch != no_node) : (ch = t.nextSibling(ch)) {
                    const cs = &t.nodes.items[ch].style;
                    if (cs.display == .none or cs.position == .absolute) continue;
                    const cb = t.rbox(cs, .{ NONE, ph });
                    const c = try t.measureChild(ch, .{ .parent = .{ NONE, ph }, .avail = .{ if (wrapping) MINC else a0, MAXC } }, 0);
                    mw = @max(mw, c + cb.marginSum(0));
                }
                mw = @max(clampO(mw + box.pb[0], box.min[0], box.max[0]), box.pb[0]);
                in.known[0] = if (wrapping) @min(w, @max(mw, a0 + box.pb[0])) else mw;
            }
        }
    }
    in.known[0] = maxO(in.known[0], ratio_w);
    if (in.width_only and has(in.known[0])) return .{ .size = .{ in.known[0], NONE } };
    var fbox = box;
    const floor_h = t.applyRatio(s, &box, &in.known);
    if (has(floor_h)) fbox.min[1] = floor_h;
    return impl(t, node, in, &fbox, false, floor_h);
}

fn impl(t: *Tree, node: u32, in: In, box_: *const Box, phase_a: bool, floor_h: f32) Error!Out {
    const s = &t.nodes.items[node].style;
    const box = box_.*;
    const known = in.known;

    const m: usize = @intFromBool(s.flex_direction == .column or s.flex_direction == .column_reverse);
    const x: usize = 1 - m;
    const reverse = s.flex_direction == .row_reverse or s.flex_direction == .column_reverse;
    const wrap = s.flex_wrap != .nowrap;
    const wrap_rev = s.flex_wrap == .wrap_reverse;
    const align_items: st.Align = s.align_items orelse .stretch;
    const align_content: st.Align = s.align_content orelse .stretch;
    const justify: st.Align = switch (s.justify_content orelse .flex_start) {
        .stretch, .baseline => .flex_start,
        else => |v| v,
    };

    var inset: [4]f32 = undefined;
    for (0..4) |i| inset[i] = box.padding[i] + box.border[i];
    const pb = box.pb;
    // node inner (content-box) size; NaN = not yet determined
    var inner: [2]f32 = .{ maxO(known[0] - pb[0], 0), maxO(known[1] - pb[1], 0) };
    // percentage basis for the items
    const pct: [2]f32 = .{ inner[0], if (has(floor_h)) @max(floor_h - pb[1], 0) else if (in.indef_h) NONE else inner[1] };
    var gap: [2]f32 = .{ t.lp(s.gap[0], pct[0]), t.lp(s.gap[1], pct[1]) };
    var avail: [2]f32 = undefined;
    for (0..2) |a| avail[a] = if (has(inner[a])) inner[a] else in.avail[a] - box.marginSum(a) - pb[a];
    // an auto block size is always content-based: the available height never constrains it
    if (!has(inner[1])) avail[1] = MAXC;
    // min/max of the content box
    const min_inner: [2]f32 = .{ box.min[0] - pb[0], box.min[1] - pb[1] };
    const max_inner: [2]f32 = .{ box.max[0] - pb[0], box.max[1] - pb[1] };

    const mark = t.scratch.mark();
    defer t.scratch.release(mark);

    // 1. Generate flex items
    var count: usize = 0;
    {
        var ch = t.firstChild(node);
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display != .none and cs.position != .absolute) count += 1;
        }
    }
    const items = try t.scratch.alloc(t.alloc, Item, count);
    const lines_buf = try t.scratch.alloc(t.alloc, Line, @max(count, 1));
    {
        var i: usize = 0;
        var ch = t.firstChild(node);
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display == .none or cs.position == .absolute) continue;
            const it = &items[i];
            i += 1;
            it.node = ch;
            it.box = t.rbox(cs, pct);
            var al = cs.align_self orelse align_items;
            if (@backingInt(al) >= @backingInt(st.Align.space_between)) al = .start;
            if (al == .baseline and (it.box.margin_auto[x] or it.box.margin_auto[x + 2])) al = .start;
            it.al = al;
            it.rel = .{
                orElse(t.dim(cs.inset.left, pct[0]), -orElse(t.dim(cs.inset.right, pct[0]), 0)),
                orElse(t.dim(cs.inset.top, pct[1]), -orElse(t.dim(cs.inset.bottom, pct[1]), 0)),
            };
            it.grow = @max(cs.flex_grow, 0);
            it.shrink = @max(cs.flex_shrink, 0);
            it.cross_auto = cs.size[x] == .auto;
            it.scroll_main = (if (m == 0) cs.overflow_x else cs.overflow_y) != .visible;
            it.frozen = false;
            it.violation = 0;
            it.baseline = 0;
            it.off_main = 0;
            it.off_cross = 0;
            it.hyp = .{ 0, 0 };
            it.target = .{ 0, 0 };
        }
    }

    // 3. Flex base size and hypothetical main size
    for (items) |*it| {
        const cs = &t.nodes.items[it.node].style;
        const b = &it.box;
        const cmargin_x = b.marginSum(x);
        // available cross space for the child, clamped by its min/max
        var cross_avail = avail[x];
        if (isDef(cross_avail)) {
            cross_avail = clampO(cross_avail, b.min[x] + cmargin_x, b.max[x] + cmargin_x);
        } else if (cross_avail < 0) {
            if (has(b.min[x])) cross_avail = b.min[x] + cmargin_x;
        } else if (has(b.max[x])) cross_avail = b.max[x] + cmargin_x;

        var ck: [2]f32 = b.size;
        ck[m] = NONE;
        if (it.al == .stretch and !has(ck[x]) and !wrap and has(inner[x]) and !b.margin_auto[x] and !b.margin_auto[x + 2]) {
            ck[x] = @max(clampO(inner[x] - cmargin_x, b.min[x], b.max[x]), b.pb[x]);
        }
        ck[x] = clampO(ck[x], b.min[x], b.max[x]);
        const cparent = pct;

        const adj: f32 = if (cs.box_sizing == .content_box) b.pb[m] else 0;
        var basis = t.dim(cs.flex_basis, pct[m]) + adj;
        // a percentage basis against an indefinite main size behaves as `content`
        if (!has(basis) and !cs.flex_basis.hasPercent()) basis = b.size[m];
        it.basis_definite = has(basis);
        // is the item height a definite size for the percentages of its own children?
        it.indef = cs.aspect_ratio == null and (if (m == 1) !has(pct[1]) and !has(basis) else !has(b.size[1]));
        it.ck = ck[x];
        it.cross_avail = cross_avail;
        if (!has(basis)) {
            var ca: [2]f32 = undefined;
            ca[m] = if (avail[m] == MINC) MINC else MAXC;
            ca[x] = cross_avail;
            basis = try t.measureChild(it.node, .{ .known = ck, .parent = cparent, .avail = ca, .content_sizing = true, .cs_axis = @intCast(m) }, m);
        }
        basis = @max(basis, b.pb[m]);
        it.basis = basis;
        it.inner_basis = basis - b.pb[m];

        // automatic minimum size (§4.5)
        var min_main = b.min[m];
        if (!has(min_main)) {
            if (it.scroll_main) {
                min_main = 0;
            } else {
                var ca: [2]f32 = undefined;
                ca[m] = MINC;
                ca[x] = cross_avail;
                const mc = try t.measureChild(it.node, .{ .known = ck, .parent = cparent, .avail = ca, .content_sizing = true, .cs_axis = @intCast(m) }, m);
                min_main = minO(minO(mc, b.size[m]), b.max[m]);
            }
        }
        min_main = @max(min_main, b.pb[m]);
        it.min_main = min_main;
        it.hyp[m] = @max(minO(basis, b.max[m]), min_main);
    }

    // 4. Main size of a row container whose inline size is not known: intrinsic sizes (Blink's
    //    ComputeMinMaxSizeOfRowContainer), then fit-content against the available space.
    if (!has(inner[m]) and m == 0) {
        const need_min = avail[0] != MAXC;
        const need_max = avail[0] != MINC;
        var sums: [2]f32 = .{ 0, 0 }; // min-content, max-content
        var largest_min: f32 = 0;
        for (items) |*it| {
            const b = &it.box;
            const ms = b.marginSum(0);
            for (0..2) |k| {
                if ((k == 0 and !need_min) or (k == 1 and !need_max)) continue;
                var c = try t.measureChild(it.node, .{ .known = .{ NONE, it.ck }, .parent = .{ NONE, pct[1] }, .avail = .{ if (k == 0) MINC else MAXC, it.cross_avail } }, 0);
                if (k == 0 and wrap) {
                    largest_min = @max(largest_min, c + ms);
                    continue;
                }
                if (it.basis_definite and ((c > it.basis and it.grow == 0) or (c < it.basis and it.shrink == 0))) c = it.hyp[0];
                sums[k] += c + ms;
            }
        }
        const g = gapSum(gap[0], items.len);
        const mn = if (wrap) largest_min else sums[0] + g;
        const mx = @max(sums[1] + g, mn);
        const main = if (!need_max) mn else if (!need_min) mx else @min(mx, @max(mn, avail[0]));
        inner[0] = @max(clampO(main, min_inner[0], max_inner[0]), 0);
        gap[0] = t.lp(s.gap[0], inner[0]);
    }
    if (phase_a) return .{ .size = .{ orElse(inner[0], 0) + pb[0], 0 } };

    // 5. Collect flex lines
    var n_lines: usize = 0;
    {
        var wrap_at: f32 = if (!wrap) MAXC else orElse(inner[m], orElse(max_inner[m], MAXC));
        if (wrap and m == 1 and !has(inner[1]) and in.content_sizing) {
            // intrinsic block size of a wrapping column: its columns still break against the styled height
            const own = t.rbox(s, in.parent);
            wrap_at = orElse(maxO(orElse(clampO(own.size[1], own.min[1], own.max[1]), own.max[1]) - pb[1], 0), MAXC);
        }
        var start: usize = 0;
        var len: f32 = 0;
        const g = gap[m];
        for (items, 0..) |*it, i| {
            const outer = it.hyp[m] + it.box.marginSum(m);
            if (i > start) {
                if (len + g + outer > wrap_at + 0.001) {
                    lines_buf[n_lines] = .{ .start = @intCast(start), .end = @intCast(i) };
                    n_lines += 1;
                    start = i;
                    len = outer;
                    continue;
                }
                len += g + outer;
            } else len = outer;
        }
        lines_buf[n_lines] = .{ .start = @intCast(start), .end = @intCast(items.len) };
        n_lines += 1;
    }
    const lines = lines_buf[0..n_lines];

    // Main size of a column container with auto height: the longest line of hypothetical sizes
    if (!has(inner[m])) {
        var main: f32 = 0;
        for (lines) |ln| {
            var sum: f32 = gapSum(gap[m], ln.end - ln.start);
            for (items[ln.start..ln.end]) |*it| sum += it.hyp[m] + it.box.marginSum(m);
            main = @max(main, sum);
        }
        inner[m] = @max(clampO(main, min_inner[m], max_inner[m]), 0);
    }
    const inner_main = inner[m];

    // 6. Resolve flexible lengths (after Blink's LineFlexer, which distributes in layout units)
    for (lines) |ln| {
        const li = items[ln.start..ln.end];
        var hyp_sum: f32 = gapSum(gap[m], li.len);
        for (li) |*it| hyp_sum += it.hyp[m] + it.box.marginSum(m);
        const growing = hyp_sum < inner_main;
        for (li) |*it| {
            const factor = if (growing) it.grow else it.shrink;
            it.frozen = factor == 0 or (if (growing) it.basis > it.hyp[m] else it.basis < it.hyp[m]);
            it.target[m] = it.hyp[m];
        }
        var initial_free: f32 = 0;
        var round: usize = 0;
        while (round <= li.len) : (round += 1) {
            // sums over the unfrozen items; each takes its fraction of what the items after it leave
            var total_factor: f64 = 0;
            var total_weighted: f64 = 0;
            var free: f32 = inner_main;
            for (li) |*it| {
                const ms = it.box.marginSum(m);
                if (it.frozen) {
                    free -= it.target[m] + ms + gap[m];
                    continue;
                }
                it.target[m] = it.hyp[m];
                const factor: f64 = if (growing) it.grow else it.shrink;
                total_factor += factor;
                if (growing) {
                    it.frac = factor / total_factor;
                } else {
                    const w = factor * @as(f64, it.inner_basis);
                    total_weighted += w;
                    it.frac = w / total_weighted;
                }
                free -= it.basis + ms + gap[m];
            }
            free += gap[m];
            if (round == 0) initial_free = free;
            if (total_factor > 0 and total_factor < 1) {
                const fractional = t.qt(@floatCast(@as(f64, initial_free) * total_factor));
                if (@abs(fractional) < @abs(free)) free = fractional;
            }
            if (if (growing) free <= 0 else free >= 0) break;

            var total_violation: f32 = 0;
            var i = li.len;
            while (i > 0) {
                i -= 1;
                const it = &li[i];
                if (it.frozen) continue;
                var extra: f32 = free;
                if (it.frac != 1.0) {
                    const e = @as(f64, free) * it.frac;
                    extra = if (std.math.isFinite(e)) (if (t.q64) @floatCast(@round(e * 64) / 64) else @floatCast(e)) else 0;
                }
                free -= extra;
                const size = it.basis + extra;
                const clamped = @max(minO(size, it.box.max[m]), it.min_main);
                it.target[m] = clamped;
                it.violation = clamped - size;
                total_violation += it.violation;
            }
            if (total_violation == 0) break;
            for (li) |*it| {
                if (!it.frozen and it.violation != 0 and (it.violation < 0) == (total_violation < 0)) it.frozen = true;
            }
        }
    }

    // 7. Hypothetical cross size of each item
    for (items) |*it| {
        const b = &it.box;
        var cross = @as(f32, NONE);
        if (has(b.size[x])) cross = @max(clampO(b.size[x], b.min[x], b.max[x]), b.pb[x]);
        if (!has(cross) and !wrap and has(inner[x]) and it.al == .stretch and it.cross_auto and !b.margin_auto[x] and !b.margin_auto[x + 2]) {
            // will be stretched to the definite line anyway: no need to measure
            cross = inner[x] - b.marginSum(x);
        }
        if (!has(cross)) {
            var ck: [2]f32 = undefined;
            ck[m] = it.target[m];
            ck[x] = NONE;
            var ca: [2]f32 = undefined;
            ca[m] = inner_main;
            ca[x] = avail[x];
            cross = try t.measureChild(it.node, .{ .known = ck, .parent = pct, .avail = ca, .content_sizing = true, .cs_axis = @intCast(x), .indef_h = it.indef }, x);
        }
        it.hyp[x] = @max(clampO(cross, b.min[x], b.max[x]), b.pb[x]);
    }

    // Baselines (rows only)
    if (m == 0) {
        for (lines) |ln| {
            const li = items[ln.start..ln.end];
            var nb: usize = 0;
            for (li) |*it| nb += @intFromBool(it.al == .baseline);
            if (nb <= 1) continue;
            for (li) |*it| {
                if (it.al != .baseline) continue;
                const o = try t.computeNode(it.node, .{
                    .known = .{ it.target[0], it.hyp[1] },
                    .parent = pct,
                    .avail = .{ inner_main, avail[1] },
                    .layout = true,
                    .content_sizing = true,
                    .indef_h = it.indef,
                });
                const bl = orElse(o.baseline, o.size[1]);
                it.baseline = if (wrap_rev) it.box.margin[3] + o.size[1] - bl else it.box.margin[1] + bl;
            }
        }
    } else {
        // column: baselines are synthesized at the cross-start edge
        for (items) |*it| {
            if (it.al == .baseline) it.baseline = if (wrap_rev) it.box.margin[2] + it.hyp[0] else it.box.margin[0];
        }
    }

    // 8. Cross size of each line
    const def_cross = has(inner[x]);
    if (!wrap and def_cross) {
        lines[0].cross = inner[x];
    } else {
        for (lines) |*ln| {
            const li = items[ln.start..ln.end];
            var max_bl: f32 = 0;
            for (li) |*it| max_bl = @max(max_bl, it.baseline);
            var c: f32 = 0;
            for (li) |*it| {
                const outer = it.hyp[x] + it.box.marginSum(x);
                const is_bl = it.al == .baseline and !it.box.margin_auto[x] and !it.box.margin_auto[x + 2];
                c = @max(c, if (is_bl) max_bl - it.baseline + outer else outer);
            }
            ln.cross = c;
        }
        if (!wrap) lines[0].cross = @max(clampO(lines[0].cross, min_inner[x], max_inner[x]), 0);
    }

    // 9. align-content: stretch
    const cross_gap_total = gapSum(gap[x], lines.len);
    var total_cross: f32 = 0;
    for (lines) |ln| total_cross += ln.cross;
    {
        // stretch lines against the definite cross size, or against a min-size that exceeds the content
        const target_inner = if (def_cross) inner[x] else orElse(min_inner[x], 0);
        if (wrap and align_content == .stretch and total_cross + cross_gap_total < target_inner) {
            var add = Diffuser.init(t.q64, target_inner - total_cross - cross_gap_total, lines.len);
            // (in visual order: Blink has applied the wrap-reverse reversal by now)
            for (0..lines.len) |i| lines[if (wrap_rev) lines.len - 1 - i else i].cross += add.next();
            total_cross = target_inner - cross_gap_total;
        }
    }

    // 11. Used cross size of each item
    for (lines) |ln| {
        for (items[ln.start..ln.end]) |*it| {
            const b = &it.box;
            if (it.al == .stretch and !b.margin_auto[x] and !b.margin_auto[x + 2] and it.cross_auto) {
                it.target[x] = @max(clampO(ln.cross - b.marginSum(x), b.min[x], b.max[x]), b.pb[x]);
                if (m == 0) it.indef = false;
            } else {
                it.target[x] = it.hyp[x];
                if (m == 1 and it.cross_auto and !has(b.size[0]) and @abs(ln.cross - avail[0]) > 0.01) {
                    // a column item is fitted against its (multi-line) line, not the whole container
                    const c = try t.measureChild(it.node, .{ .known = .{ NONE, it.target[1] }, .parent = pct, .avail = .{ ln.cross, MAXC }, .content_sizing = true, .indef_h = it.indef }, 0);
                    it.target[0] = @max(clampO(c, b.min[0], b.max[0]), b.pb[0]);
                }
            }
        }
    }

    // 12. Main-axis alignment
    for (lines) |ln| {
        const li = items[ln.start..ln.end];
        var used: f32 = gapSum(gap[m], li.len);
        var n_auto: f32 = 0;
        for (li) |*it| {
            used += it.target[m] + it.box.marginSum(m);
            n_auto += @floatFromInt(@as(u8, @intFromBool(it.box.margin_auto[m])) + @intFromBool(it.box.margin_auto[m + 2]));
        }
        const free = inner_main - used;
        if (free > 0 and n_auto > 0) {
            var mg = Diffuser.init(t.q64, free, @intFromFloat(n_auto));
            for (0..li.len) |i| {
                const it = &li[if (reverse) li.len - 1 - i else i];
                if (it.box.margin_auto[m]) it.box.margin[m] = mg.next();
                if (it.box.margin_auto[m + 2]) it.box.margin[m + 2] = mg.next();
            }
            // items pack from the main-start edge
            for (li, 0..) |*it, i| it.off_main = if (i == (if (reverse) li.len - 1 else 0)) 0 else gap[m];
        } else {
            var between = spacing(t, free, li.len, justify);
            for (0..li.len) |i| {
                const it = &li[if (reverse) li.len - 1 - i else i];
                it.off_main = if (i == 0) firstOffset(t, free, li.len, justify, reverse) else gap[m] + between.next();
            }
        }
    }

    // 13/14. Cross-axis auto margins and alignment
    for (lines) |ln| {
        const li = items[ln.start..ln.end];
        var max_bl: f32 = 0;
        for (li) |*it| max_bl = @max(max_bl, it.baseline);
        for (li) |*it| {
            const b = &it.box;
            const free = ln.cross - it.target[x] - b.marginSum(x);
            const sa = b.margin_auto[x];
            const ea = b.margin_auto[x + 2];
            if (sa or ea) {
                const f = @max(free, 0);
                if (sa and ea) {
                    b.margin[x] = t.div(f, 2);
                    b.margin[x + 2] = t.div(f, 2);
                } else if (sa) {
                    b.margin[x] = f;
                } else b.margin[x + 2] = f;
                continue;
            }
            it.off_cross = switch (it.al) {
                .start => 0,
                .end => free,
                .flex_end => if (wrap_rev) 0 else free,
                .center => t.div(free, 2),
                .baseline => if (wrap_rev) free - (max_bl - it.baseline) else max_bl - it.baseline,
                else => if (wrap_rev) free else 0,
            };
        }
    }

    // 15. Container cross size
    if (!def_cross) inner[x] = @max(clampO(total_cross + cross_gap_total, min_inner[x], max_inner[x]), 0);
    const size: [2]f32 = .{ inner[0] + pb[0], inner[1] + pb[1] };
    if (!in.layout) return .{ .size = size };

    // 16. align-content
    {
        const free = inner[x] - total_cross - cross_gap_total;
        const mode: st.Align = if (wrap) align_content else .stretch;
        var between = spacing(t, free, lines.len, mode);
        for (0..lines.len) |i| {
            const ln = &lines[if (wrap_rev) lines.len - 1 - i else i];
            ln.off = if (i == 0) firstOffset(t, free, lines.len, mode, wrap_rev) else gap[x] + between.next();
        }
    }

    // Final layout pass
    var out: Out = .{ .size = size };
    var content: [2]f32 = .{ 0, 0 };
    var first_bl: f32 = NONE;
    var first_bl_fallback: f32 = NONE;
    {
        var cross_pos = inset[x];
        for (0..lines.len) |k| {
            const lidx = if (wrap_rev) lines.len - 1 - k else k;
            const ln = &lines[lidx];
            const li = items[ln.start..ln.end];
            var main_pos = inset[m];
            cross_pos += ln.off;
            for (0..li.len) |i| {
                const it = &li[if (reverse) li.len - 1 - i else i];
                const b = &it.box;
                const o = try t.computeNode(it.node, .{ .known = it.target, .parent = pct, .avail = inner, .layout = true, .content_sizing = true, .indef_h = it.indef });
                main_pos += it.off_main + b.margin[m];
                var pos: [2]f32 = undefined;
                pos[m] = main_pos;
                pos[x] = cross_pos + it.off_cross + b.margin[x];
                if (k == 0) {
                    const bl = pos[1] + orElse(o.baseline, o.size[1]);
                    // the first item in visual (reversal-applied) order, preferring baseline-aligned ones in a row
                    if (i == 0) first_bl_fallback = bl;
                    if ((m == 1 and i == 0) or (m == 0 and it.al == .baseline and !has(first_bl))) first_bl = bl;
                }
                pos[0] += it.rel[0];
                pos[1] += it.rel[1];
                t.setLayout(it.node, pos, &o, b);
                t.accumContent(&content, it.node);
                main_pos += o.size[m] + b.margin[m + 2];
            }
            cross_pos += ln.cross;
        }
    }
    out.baseline = orElse(first_bl, first_bl_fallback);

    // Absolutely positioned and hidden children
    if (count != t.nodes.items[node].child_count) {
        const area: [4]f32 = .{
            box.border[0],                           box.border[1],
            size[0] - box.border[0] - box.border[2], size[1] - box.border[1] - box.border[3],
        };
        var ch = t.firstChild(node);
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display == .none) {
                t.hide(ch);
                continue;
            }
            if (cs.position != .absolute) continue;
            var sp: Tree.Static = .{ .rect = .{ inset[0], inset[1], inner[0], inner[1] } };
            sp.al[m] = switch (justify) {
                .start => 0,
                .end => 2,
                .flex_end => if (reverse) 0 else 2,
                .center, .space_around, .space_evenly => 1,
                else => if (reverse) 2 else 0,
            };
            sp.al[x] = switch (cs.align_self orelse align_items) {
                .start => 0,
                .end => 2,
                .center => 1,
                .flex_end => if (wrap_rev) 0 else 2,
                else => if (wrap_rev) 2 else 0,
            };
            try t.placeAbsolute(node, ch, area, sp);
            t.accumContent(&content, ch);
        }
    }
    out.content = content;
    return out;
}
