//! Inline rows (`Display.inline_row`): an anonymous line container whose in-flow children are atomic inline
//! boxes (any container node, laid out shrink-to-fit) and measured leaves (text runs, images). They are
//! placed left to right on line boxes and wrap to a new line when the next item does not fit.
//!
//! Model (follows Blink's line layout for atomic inlines, which is what the takumi oracle runs):
//!  * Line breaking: an item goes on the current line when the line is empty or its margin box fits the
//!    remaining width; otherwise it starts a new line. There are no gaps between items; margins count and
//!    never collapse. A box item is shrink-to-fit against the whole line width
//!    (`min(max-content, max(min-content, line width))`); a measured leaf that is wider than the line is
//!    measured again with the line width as available width (it wraps internally) and is then one box.
//!  * Vertical alignment per line, by the item's `Style.vertical_align`. Every line starts from the strut
//!    of the container (`strut_ascent` above / `strut_descent` below the baseline). `baseline` items sit
//!    on the baseline (their baseline is `Out.baseline`, or the bottom margin edge when they have none or
//!    are block containers with a non-visible `overflow_y`); `middle` items are centred `strut_middle`
//!    above the baseline (half the x-height in CSS; the middle of the strut when it is not given). Both
//!    grow the line's ascent / descent. `top` / `bottom` items are then aligned to the line box; a taller
//!    one grows the line downwards (`top`) or upwards (`bottom`) exactly like Blink's
//!    `MetricsForTopAndBottomAlign`. Line height = ascent + descent.
//!  * Horizontal alignment by the container's `Style.text_align`; `justify` spreads the free space between
//!    the items of every line but the last (the oracle has no justification opportunity between adjacent
//!    atomic inlines, so this one is a deliberate extension).
//!  * Size of the row: a known width is used as is; otherwise the width is the widest line (max-content:
//!    all items on one line, min-content: every item on its own line, definite available width: lines broken
//!    at that width, and the row fills that width once something had to wrap or shrink, which is CSS
//!    shrink-to-fit for the block container around it). Height = sum of the line heights. `Out.baseline` =
//!    baseline of the first line; a row without in-flow items has no line, no height and no baseline.
//!  * Percentages of the items resolve against the row's content box; heights against the row's own definite
//!    height, else against `in.parent[1]` (the containing block's height: the row is normally anonymous).
//!    Oracle quirk reproduced: the percentage part of an item's MARGINS resolves to 0 (see `itemWidth`).
//!  * Out-of-flow children take their static position at the current point of the line (line top);
//!    `display: none` children are hidden. Line boxes are not reported.
//!
//! Known gaps against the oracle: an inline-block's baseline is the baseline of its LAST line box / last
//! in-flow child (only the first baseline is available here); a block-level out-of-flow box has its static
//! position below the line (inline-level is assumed); no `vertical-align` lengths / sub / super /
//! text-top / text-bottom.
const std = @import("std");
const st = @import("style.zig");
const tr = @import("tree.zig");

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

/// widths that differ by less than this are "equal" for the fit test (float noise; exact on the 1/64 grid)
const fit_eps: f32 = 0.005;

const Kind = enum(u8) { baseline, top, middle, bottom, out_of_flow };

const Item = struct {
    node: u32,
    kind: Kind,
    /// margin-box left edge on the line before alignment; out-of-flow: the current point
    x: f32,
    /// margin-box size
    mw: f32,
    mh: f32,
    /// baseline, from the margin-box top
    bl: f32,
    /// left / top margins
    ml: f32,
    mt: f32,
    /// out-of-flow only: the line top (static position)
    y: f32,
};

/// Per-container state kept in the tree's scratch arena (see `Tree.computeNode` on stack discipline).
const S = struct {
    in: In,
    box: Box,
    /// box of the child being placed
    cb: Box,
    known: [2]f32,
    inset: [4]f32,
    /// percentage basis of the items (content box of the row)
    parent: [2]f32,
    content: [2]f32,
    ci: In,
    co: Out,
    area: [4]f32,
    sp: tr.StaticPos,
    items: []Item,
    /// width of a line (content-box width; +-inf for the intrinsic sizes)
    line_w: f32,
    /// widest line so far
    max_w: f32,
    /// top of the current line / bottom of the last one, from the border-box top
    y: f32,
    first_bl: f32,
    lines: u32,
    strut: [2]f32,
    /// centre line of `middle` items above the baseline
    middle: f32,
    /// height of the child being placed (NaN = auto)
    ckh: f32,
    /// a line was broken or an item was shrunk to fit the line width
    broke: bool,
};

pub noinline fn compute(t: anytype, node: u32, in_: *const In, out: *Out) Error!void {
    const mark = t.scratch.mark();
    defer t.scratch.release(mark);
    const c = try t.scratch.create(t.alloc, S);
    c.in = in_.*;
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
    // (an infinite border width survives the box resolution: keep the item positions finite)
    for (0..4) |i| c.inset[i] = orElse(tr.fin(box.padding[i] + box.border[i]), 0);
    const pb = box.pb;
    // percentage heights of the items: against the row's own height when it has one, else against the
    // containing block's (the row is normally an anonymous box of a block container)
    const inner_h: f32 = if (has(known[1]) and !in.indef_h) @max(known[1] - pb[1], 0) else in.parent[1];

    // the strut (untrusted: non-finite values count as 0)
    c.strut = .{ t.qt(orElse(tr.fin(s.strut_ascent), 0)), t.qt(orElse(tr.fin(s.strut_descent), 0)) };
    c.middle = t.div(c.strut[0] - c.strut[1], 2);
    if (s.strut_middle) |m| {
        // (Blink rounds half the x-height to the nearest layout unit)
        if (std.math.isFinite(m)) c.middle = if (t.q64) @round(m * 64) / 64 else m;
    }

    var outer_w = known[0];
    if (!has(outer_w)) {
        // intrinsic width: the widest line, percentages of the items being indefinite
        c.parent = .{ NONE, inner_h };
        c.line_w = maxO(tr.minO(in.avail[0] - box.marginSum(0), box.max[0]) - pb[0], 0);
        if (in.avail[0] == MINC) c.line_w = MINC;
        try run(t, c, node, false);
        // (content that had to wrap or shrink fills the available width: CSS shrink-to-fit)
        if (c.broke and tr.isDef(c.line_w)) c.max_w = @max(c.max_w, c.line_w);
        outer_w = @max(clampO(c.max_w + pb[0], box.min[0], box.max[0]), pb[0]);
    }
    if (in.width_only) {
        out.* = .{ .size = .{ outer_w, NONE } };
        return;
    }

    const inner_w = @max(outer_w - pb[0], 0);
    c.parent = .{ inner_w, inner_h };
    c.line_w = inner_w;
    c.content = .{ 0, 0 };
    {
        var count: usize = 0;
        var ch = n.first_child;
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            if (t.nodes.items[ch].style.display != .none) count += 1;
        }
        c.items = try t.scratch.alloc(t.alloc, Item, count);
    }
    try run(t, c, node, true);

    const outer_h = @max(orElse(known[1], clampO(@max(c.y + c.inset[3], 0), box.min[1], box.max[1])), pb[1]);
    if (!in.layout) {
        out.* = .{ .size = .{ outer_w, outer_h } };
        return;
    }
    c.area = .{ box.border[0], box.border[1], outer_w - box.border[0] - box.border[2], outer_h - box.border[1] - box.border[3] };
    for (c.items) |*it| {
        if (it.kind != .out_of_flow) continue;
        c.sp = .{ .rect = .{ it.x, it.y, 0, 0 } };
        try t.placeAbsolute(node, it.node, &c.area, &c.sp);
        t.accumContent(&c.content, it.node);
    }
    out.* = .{ .size = .{ outer_w, outer_h } };
    out.content = c.content;
    out.baseline = c.first_bl;
    // (a row without line boxes is an empty block: margins collapse through it)
    out.collapse_through = c.lines == 0 and outer_h == 0;
}

/// Breaks the in-flow children into lines of `c.line_w`. `full` = false: only the widest line is computed
/// (`c.max_w`); true: the items are laid out and (in a layout pass) positioned, `c.y` ends at the bottom of
/// the last line and `c.items` holds the out-of-flow children with their static positions.
noinline fn run(t: anytype, c: *S, node: u32, full: bool) Error!void {
    const place = full and c.in.layout;
    c.max_w = 0;
    c.y = c.inset[1];
    c.first_bl = NONE;
    c.lines = 0;
    c.broke = false;
    var cur: f32 = 0;
    // items of the current line: c.items[start..len], `inflow` of them in flow
    var start: usize = 0;
    var len: usize = 0;
    var inflow: usize = 0;

    var ch = t.firstChild(node);
    while (ch != no_node) : (ch = t.nextSibling(ch)) {
        const cs = &t.nodes.items[ch].style;
        if (cs.display == .none) {
            if (place) t.hide(ch);
            continue;
        }
        if (cs.position.isOut()) {
            if (full and len < c.items.len) {
                c.items[len] = .{ .node = ch, .kind = .out_of_flow, .x = cur, .mw = 0, .mh = 0, .bl = 0, .ml = 0, .mt = 0, .y = 0 };
                len += 1;
            }
            continue;
        }
        const w = try itemWidth(t, c, ch);
        const cb = &c.cb;
        const mw = w + cb.marginSum(0);
        if (inflow > 0 and cur + mw - c.line_w > fit_eps) {
            c.max_w = @max(c.max_w, cur);
            c.broke = true;
            if (full) finishLine(t, c, node, c.items[start..len], cur, false, place);
            start = len;
            inflow = 0;
            cur = 0;
        }
        if (full and len < c.items.len) {
            c.ci = .{ .known = .{ w, c.ckh }, .parent = c.parent, .avail = .{ c.line_w, MAXC }, .layout = true };
            try t.computeNode(ch, &c.ci, &c.co);
            const o = &c.co;
            const mh = o.size[1] + cb.marginSum(1);
            // an inline-block that is a scroll container takes its bottom margin edge for a baseline
            const synth = !has(o.baseline) or (cs.display == .block and !t.nodes.items[ch].measured and
                (cs.overflow_y == .hidden or cs.overflow_y == .scroll));
            c.items[len] = .{
                .node = ch,
                .kind = switch (cs.vertical_align) {
                    .baseline => .baseline,
                    .top => .top,
                    .middle => .middle,
                    .bottom => .bottom,
                },
                .x = cur,
                .mw = mw,
                .mh = mh,
                .bl = if (synth) mh else cb.margin[1] + o.baseline,
                .ml = cb.margin[0],
                .mt = cb.margin[1],
                .y = 0,
            };
            len += 1;
            // (the position is patched in when the line is finished)
            if (place) t.setLayout(ch, .{ 0, 0 }, o, cb);
        }
        inflow += 1;
        cur += mw;
    }
    if (inflow > 0) c.max_w = @max(c.max_w, cur);
    if (full) finishLine(t, c, node, c.items[start..len], cur, true, place);
}

/// Border-box width of the in-flow item `ch` on a line of `c.line_w`; leaves the item's box in `c.cb` and
/// its height (NaN = auto) in `c.ckh`.
noinline fn itemWidth(t: anytype, c: *S, ch: u32) Error!f32 {
    const cn = &t.nodes.items[ch];
    t.rbox(&c.cb, &cn.style, c.parent);
    const cb = &c.cb;
    {
        // ORACLE QUIRK: takumi resolves the percentage part of an atomic inline's margins to 0
        // (CSS: against the containing block's width). Remove this block to get the CSS behaviour.
        const m: [4]st.Dim = .{ cn.style.margin.left, cn.style.margin.top, cn.style.margin.right, cn.style.margin.bottom };
        for (m, 0..) |d, i| {
            if (d.hasPercent()) cb.margin[i] = t.qt(orElse(tr.resolveDim(d, 0), 0));
        }
    }
    c.ckh = maxO(clampO(cb.size[1], cb.min[1], cb.max[1]), cb.pb[1]);
    var w = cb.size[0];
    if (!has(w)) {
        const ms = cb.marginSum(0);
        c.ci = .{ .known = .{ NONE, c.ckh }, .parent = c.parent, .avail = .{ if (c.line_w == MINC) MINC else MAXC, MAXC } };
        w = try t.measureChild(ch, &c.ci, 0);
        if (tr.isDef(c.line_w) and w + ms - c.line_w > fit_eps) {
            c.broke = true;
            if (cn.measured) {
                // a text run wraps inside the line width
                c.ci = .{ .known = .{ NONE, c.ckh }, .parent = c.parent, .avail = .{ c.line_w, MAXC } };
                w = try t.measureChild(ch, &c.ci, 0);
            } else {
                // shrink-to-fit
                c.ci = .{ .known = .{ NONE, c.ckh }, .parent = c.parent, .avail = .{ MINC, MAXC } };
                const min_w = try t.measureChild(ch, &c.ci, 0);
                w = @min(w, @max(min_w, c.line_w - ms));
            }
        }
    }
    return @max(clampO(w, c.cb.min[0], c.cb.max[0]), c.cb.pb[0]);
}

/// Aligns the items of one line (`used` = sum of their margin-box widths), positions them when `place` is
/// set and advances `c.y`. A line without in-flow items creates no line box.
noinline fn finishLine(t: anytype, c: *S, node: u32, items: []Item, used: f32, last: bool, place: bool) void {
    const s = &t.nodes.items[node].style;
    // metrics of the items aligned relative to the baseline, starting from the strut
    var asc = c.strut[0];
    var desc = c.strut[1];
    var n_in: usize = 0;
    for (items) |*it| {
        if (it.kind == .out_of_flow) continue;
        n_in += 1;
        switch (it.kind) {
            .baseline => {
                asc = @max(asc, it.bl);
                desc = @max(desc, it.mh - it.bl);
            },
            .middle => {
                // `y` = shift of the box below its own baseline position
                it.y = t.div(it.bl - (it.mh - it.bl), 2) - c.middle;
                asc = @max(asc, it.bl - it.y);
                desc = @max(desc, it.mh - it.bl + it.y);
            },
            else => {},
        }
    }
    if (n_in == 0) {
        for (items) |*it| {
            it.x += c.inset[0];
            it.y = c.y;
        }
        return;
    }
    // top / bottom: the box they align to is the above, extended by the tallest of them
    var max_a = asc;
    var max_d = desc;
    for (items) |*it| {
        if ((it.kind == .top or it.kind == .bottom) and it.mh > max_a + max_d) {
            if (it.kind == .top) {
                max_a = asc;
                max_d = it.mh - asc;
            } else {
                max_a = it.mh - desc;
                max_d = desc;
            }
        }
    }
    var line_a = asc;
    var line_d = desc;
    for (items) |*it| {
        if (it.kind == .top) {
            line_a = @max(line_a, max_a);
            line_d = @max(line_d, it.mh - max_a);
        } else if (it.kind == .bottom) {
            line_a = @max(line_a, it.mh - max_d);
            line_d = @max(line_d, max_d);
        }
    }
    const line_h = @max(line_a + line_d, 0);
    const base = c.y + line_a;

    // horizontal alignment
    const free = @max(c.line_w - used, 0);
    var x0 = c.inset[0];
    var spread: f32 = 0;
    switch (s.text_align) {
        .start => {},
        .center => x0 += t.div(free, 2),
        .end => x0 += free,
        .justify => if (!last and n_in > 1 and tr.isDef(free)) {
            spread = free / @as(f32, @floatFromInt(n_in - 1));
        },
    }
    if (!tr.isDef(x0)) x0 = c.inset[0];

    var k: f32 = 0;
    for (items) |*it| {
        const x = x0 + it.x + t.qt(spread * k);
        if (it.kind == .out_of_flow) {
            // (between two justified items the static position is the end of the previous one)
            it.x = x0 + it.x + t.qt(spread * @max(k - 1, 0));
            it.y = c.y;
            continue;
        }
        k += 1;
        if (!place) continue;
        const top = switch (it.kind) {
            .baseline => base - it.bl,
            .middle => base - it.bl + it.y,
            .top => base - max_a,
            else => base + max_d - it.mh,
        };
        const cs = &t.nodes.items[it.node].style;
        const l = &t.layouts.items[it.node];
        l.x = x + it.ml + orElse(t.dim(cs.inset.left, c.parent[0]), -orElse(t.dim(cs.inset.right, c.parent[0]), 0));
        l.y = top + it.mt + orElse(t.dim(cs.inset.top, c.parent[1]), -orElse(t.dim(cs.inset.bottom, c.parent[1]), 0));
        t.accumContent(&c.content, it.node);
    }
    if (c.lines == 0) c.first_bl = base;
    c.lines += 1;
    c.y += line_h;
}
