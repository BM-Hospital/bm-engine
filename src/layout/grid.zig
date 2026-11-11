//! CSS Grid (css-grid-1): explicit/implicit tracks, line-based + auto placement (sparse/dense), the track
//! sizing algorithm (§11), content/self alignment, absolutely positioned children.
//! Not supported: named lines/areas, subgrid, baseline alignment (treated as start), masonry.
const std = @import("std");
const st = @import("style.zig");
const tr = @import("tree.zig");
const flex = @import("flex.zig");

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

/// Grid lines/spans are clamped to this magnitude (inputs are untrusted).
const max_line = 1000;
const eps: f32 = 0.0001;

const Kind = enum(u8) { fixed, min_content, max_content, auto, fit_content, flex };

const Track = struct {
    min_kind: Kind,
    max_kind: Kind,
    min_v: f32,
    /// fixed size, flex factor or fit-content limit
    max_v: f32,
    base: f32,
    limit: f32,
    off: f32 = 0,
    inf_growable: bool = false,
    touched: bool = false,
    planned: f32 = 0,
    inc: f32 = 0,
    tmp: bool = false,
    /// empty auto-fit track
    collapsed: bool = false,
};

const Place = struct { start: i32, span: i32, def: bool };

const Item = struct {
    node: u32,
    /// placement per axis
    p: [2]Place,
    placed: bool,
    /// placed by the "locked to a row" step
    locked: bool = false,
    /// cached [axis][min-content, max-content] contributions (margin box), NaN = not computed
    contrib: [2][2]f32,
    margin: [2]f32,
    size: [2]f32,
    /// percentage basis for the item while sizing
    area_w: f32,

    inline fn end(it: *const Item, a: usize) i32 {
        return it.p[a].start + it.p[a].span;
    }
};

const G = struct {
    t: *Tree,
    items: []Item,
    tracks: [2][]Track,
    gap: [2]f32,
};

fn lineIdx(l: i16, explicit: i32) i32 {
    const v: i32 = std.math.clamp(@as(i32, l), -max_line, max_line);
    return if (v > 0) v - 1 else explicit + 1 + v;
}

fn resolvePlace(pl: st.Placement, explicit: i32) Place {
    var s = pl.start;
    var e = pl.end;
    if (s == .line and s.line == 0) s = .auto;
    if (e == .line and e.line == 0) e = .auto;
    const spanOf = struct {
        fn f(l: st.Line) i32 {
            return switch (l) {
                .span => |n| std.math.clamp(@as(i32, n), 1, max_line),
                else => 1,
            };
        }
    }.f;
    if (s == .line) {
        const a = lineIdx(s.line, explicit);
        if (e == .line) {
            const b = lineIdx(e.line, explicit);
            if (a == b) return .{ .start = a, .span = 1, .def = true };
            return .{ .start = @min(a, b), .span = @max(a, b) - @min(a, b), .def = true };
        }
        return .{ .start = a, .span = spanOf(e), .def = true };
    }
    if (e == .line) {
        const b = lineIdx(e.line, explicit);
        const n = spanOf(s);
        return .{ .start = b - n, .span = n, .def = true };
    }
    return .{ .start = 0, .span = if (s == .span) spanOf(s) else spanOf(e), .def = false };
}

/// First placed item overlapping the given cell range, if any.
fn overlap(items: []Item, pa: usize, ps: i32, pspan: i32, ss: i32, sspan: i32) ?*Item {
    const sa = 1 - pa;
    for (items) |*o| {
        if (!o.placed) continue;
        if (o.p[pa].start < ps + pspan and ps < o.end(pa) and o.p[sa].start < ss + sspan and ss < o.end(sa)) return o;
    }
    return null;
}

fn definiteSize(tk: st.Track, inner: f32) f32 {
    const f = struct {
        fn f(b: st.TrackBreadth, inner_: f32) f32 {
            return switch (b) {
                .px => |v| v,
                .percent => |p| p * inner_,
                else => NONE,
            };
        }
    }.f;
    return orElse(f(tk.max, inner), f(tk.min, inner));
}

fn repeatCount(rep: st.AutoRepeat, template: []const st.Track, space: f32, inner: f32, gap: f32) usize {
    if (!has(space) or rep.tracks.len == 0) return 1;
    var fixed: f32 = 0;
    for (template) |tk| fixed += orElse(definiteSize(tk, inner), 0);
    var rs: f32 = 0;
    for (rep.tracks) |tk| rs += orElse(definiteSize(tk, inner), 0);
    const per = rs + gap * @as(f32, @floatFromInt(rep.tracks.len));
    if (!(per > 0.01)) return 1;
    const n = (space - fixed - gap * @as(f32, @floatFromInt(template.len)) + gap) / per;
    if (!(n >= 1)) return 1;
    return @intFromFloat(@min(@floor(n + 0.0005), @as(f32, max_line)));
}

fn initTrack(tk: st.Track, inner: f32) Track {
    var r: Track = .{ .min_kind = .auto, .max_kind = .auto, .min_v = 0, .max_v = 0, .base = 0, .limit = MAXC };
    switch (tk.min) {
        .px => |v| {
            r.min_kind = .fixed;
            r.min_v = @max(orElse(tr.fin(v), 0), 0);
        },
        .percent => |p| if (has(tr.fin(p * inner))) {
            r.min_kind = .fixed;
            r.min_v = @max(p * inner, 0);
        },
        .min_content => r.min_kind = .min_content,
        .max_content => r.min_kind = .max_content,
        else => {},
    }
    switch (tk.max) {
        .px => |v| {
            r.max_kind = .fixed;
            r.max_v = @max(orElse(tr.fin(v), 0), 0);
        },
        .percent => |p| if (has(tr.fin(p * inner))) {
            r.max_kind = .fixed;
            r.max_v = @max(p * inner, 0);
        },
        .fr => |f| {
            r.max_kind = .flex;
            r.max_v = @max(orElse(tr.fin(f), 0), 0);
        },
        .min_content => r.max_kind = .min_content,
        .max_content => r.max_kind = .max_content,
        .fit_content => |l| {
            r.max_kind = .fit_content;
            r.max_v = switch (l) {
                .px => |v| @max(orElse(tr.fin(v), 0), 0),
                .percent => |p| @max(orElse(tr.fin(p * inner), MAXC), 0),
                .calc => |c| @max(orElse(tr.fin(c.px + c.percent * inner), MAXC), 0),
            };
        },
        .auto => {},
    }
    if (r.min_kind == .fixed) r.base = r.min_v;
    if (r.max_kind == .fixed) r.limit = @max(r.max_v, r.base);
    return r;
}

fn resetTracks(g: *G, a: usize, s: *const st.Style, tmpl: []const st.Track, neg: i32, fit_range: [2]i32, used: []const bool, inner: f32) void {
    const autos = if (a == 0) s.grid_auto_columns else s.grid_auto_rows;
    for (g.tracks[a], 0..) |*tk, i| {
        const e = @as(i32, @intCast(i)) - neg;
        var src: st.Track = .{};
        if (e >= 0 and e < tmpl.len) {
            src = tmpl[@intCast(e)];
        } else if (autos.len > 0) {
            const len: i32 = @intCast(autos.len);
            const idx = if (e < 0) len - 1 - @mod(-e - 1, len) else @mod(e - @as(i32, @intCast(tmpl.len)), len);
            src = autos[@intCast(idx)];
        }
        tk.* = initTrack(src, inner);
        if (g.t.q64) {
            tk.min_v = g.t.qt(tk.min_v);
            if (tk.max_kind != .flex and tk.max_v != MAXC) tk.max_v = g.t.qt(tk.max_v);
            tk.base = g.t.qt(tk.base);
            if (tk.limit != MAXC) tk.limit = g.t.qt(tk.limit);
        }
        if (e >= fit_range[0] and e < fit_range[1] and !used[i]) {
            tk.* = .{ .min_kind = .fixed, .max_kind = .fixed, .min_v = 0, .max_v = 0, .base = 0, .limit = 0, .collapsed = true };
        }
    }
}

/// Sum of the gaps between the (non-collapsed) tracks.
fn gapsOf(ts: []const Track, gap: f32) f32 {
    var n: f32 = 0;
    for (ts) |tk| n += @floatFromInt(@intFromBool(!tk.collapsed));
    return if (n > 1) gap * (n - 1) else 0;
}

fn spanTracks(g: *G, it: *const Item, a: usize) []Track {
    const ts = g.tracks[a];
    const s: usize = @intCast(std.math.clamp(it.p[a].start, 0, @as(i32, @intCast(ts.len))));
    const e: usize = @intCast(std.math.clamp(it.end(a), 0, @as(i32, @intCast(ts.len))));
    return ts[s..@max(s, e)];
}

fn contrib(g: *G, it: *Item, a: usize, k: usize) Error!f32 {
    if (has(it.contrib[a][k])) return it.contrib[a][k];
    var v: f32 = undefined;
    if (a == 0) {
        v = try g.t.measureChild(it.node, .{ .avail = .{ if (k == 0) MINC else MAXC, MAXC } }, 0);
    } else {
        v = try g.t.measureChild(it.node, .{ .known = .{ it.size[0], NONE }, .parent = .{ it.area_w, NONE }, .avail = .{ it.area_w, MAXC } }, 1);
        it.contrib[1] = .{ v + it.margin[1], v + it.margin[1] };
    }
    v += it.margin[a];
    it.contrib[a][k] = v;
    return v;
}

/// Minimum contribution (§11.5): the content-based automatic minimum, or the specified minimum.
fn minContrib(g: *G, it: *Item, a: usize, allow_auto: bool) Error!f32 {
    const cs = &g.t.nodes.items[it.node].style;
    if (cs.size[a] != .px) {
        switch (cs.min_size[a]) {
            .px => |v| return v + it.margin[a],
            else => {},
        }
        const ov = if (a == 0) cs.overflow_x else cs.overflow_y;
        if (ov != .visible or !allow_auto) return it.margin[a];
    }
    return contrib(g, it, a, 0);
}

fn pred(tk: *const Track, phase: u8, max_constraint: bool, flex_only: bool) bool {
    if (flex_only and tk.max_kind != .flex) return false;
    if (!flex_only and tk.max_kind == .flex and phase >= 3) return false;
    return switch (phase) {
        0 => tk.min_kind != .fixed,
        1 => tk.min_kind == .min_content or tk.min_kind == .max_content,
        2 => tk.min_kind == .max_content or (tk.min_kind == .auto and max_constraint),
        3 => tk.max_kind != .fixed and tk.max_kind != .flex,
        else => tk.max_kind == .max_content or tk.max_kind == .auto or tk.max_kind == .fit_content,
    };
}

/// One item's part of "distribute extra space": records in `planned` how much the tracks spanned by the
/// item must grow to accommodate `size` (the increases are applied once per phase for the whole group).
fn distribute(ts: []Track, gap: f32, size: f32, phase: u8, max_constraint: bool, flex_only: bool) void {
    const to_limit = phase >= 3;
    var sum: f32 = gapsOf(ts, gap);
    var n_aff: f32 = 0;
    var n_free: f32 = 0;
    for (ts) |*tk| {
        sum += if (to_limit and tk.limit != MAXC) tk.limit else tk.base;
        tk.tmp = pred(tk, phase, max_constraint, flex_only);
        if (!tk.tmp) continue;
        n_aff += 1;
        tk.inc = 0;
        if (to_limit) {
            tk.touched = true;
            if (tk.limit == MAXC or tk.inf_growable) n_free += 1;
        }
    }
    var extra = size - sum;
    if (n_aff == 0 or !(extra > eps)) return;
    if (to_limit) {
        // growth limits: tracks that can still grow freely take the space, else all affected tracks
        const n = if (n_free > 0) n_free else n_aff;
        for (ts) |*tk| {
            if (tk.tmp and (n_free == 0 or tk.limit == MAXC or tk.inf_growable)) tk.inc = extra / n;
        }
    } else {
        // base sizes: equally, up to the growth limits
        var guard: usize = 0;
        while (extra > eps and guard <= ts.len) : (guard += 1) {
            var n: f32 = 0;
            for (ts) |*tk| {
                if (tk.tmp and tk.base + tk.inc < tk.limit) n += 1;
            }
            if (n == 0) break;
            const share = extra / n;
            for (ts) |*tk| {
                if (!(tk.tmp and tk.base + tk.inc < tk.limit)) continue;
                const add = @min(share, tk.limit - tk.base - tk.inc);
                tk.inc += add;
                extra -= add;
            }
        }
        if (extra > eps) {
            // beyond the limits: tracks with an intrinsic (or flexible) max sizing function, else all
            var n: f32 = 0;
            for (ts) |*tk| {
                if (tk.tmp and tk.max_kind != .fixed) n += 1;
            }
            const all = n == 0;
            if (all) n = n_aff;
            for (ts) |*tk| {
                if (tk.tmp and (all or tk.max_kind != .fixed)) tk.inc += extra / n;
            }
        }
    }
    for (ts) |*tk| {
        if (tk.tmp) tk.planned = @max(tk.planned, tk.inc);
    }
}

fn findFr(ts: []Track, gap: f32, space: f32) f32 {
    for (ts) |*tk| tk.tmp = tk.max_kind == .flex;
    var guard: usize = 0;
    while (guard <= ts.len) : (guard += 1) {
        var left = space - gapsOf(ts, gap);
        var fsum: f32 = 0;
        for (ts) |*tk| {
            if (tk.tmp) fsum += tk.max_v else left -= tk.base;
        }
        const hyp = @max(left, 0) / @max(fsum, 1);
        var any = false;
        for (ts) |*tk| {
            if (tk.tmp and hyp * tk.max_v < tk.base) {
                tk.tmp = false;
                any = true;
            }
        }
        if (!any) return hyp;
    }
    return 0;
}

/// The track sizing algorithm for one axis. `avail`: content-box space (definite, MINC or MAXC).
fn sizeTracks(g: *G, a: usize, avail: f32, stretch: bool) Error!void {
    const ts = g.tracks[a];
    const gap = g.gap[a];
    // only the intrinsic inline sizing runs under a real max-content constraint; an auto block size is just
    // indefinite free space (tracks are still maximized)
    const max_constraint = avail == MAXC and a == 0;
    var has_flex = false;
    var has_intrinsic = false;
    for (ts) |*tk| {
        has_flex = has_flex or tk.max_kind == .flex;
        has_intrinsic = has_intrinsic or tk.min_kind != .fixed or (tk.max_kind != .fixed and tk.max_kind != .flex);
    }

    // Resolve intrinsic track sizes: items by ascending span, then the ones crossing flexible tracks
    if (has_intrinsic) {
        var span: i32 = 1;
        var pass: u8 = 0;
        while (pass < 2) {
            // Items of one span group are considered together, phase by phase.
            var next: i32 = std.math.maxInt(i32);
            const flex_only = pass == 1;
            for (ts) |*tk| tk.inf_growable = false;
            var ph: u8 = 0;
            while (ph < 5) : (ph += 1) {
                if (flex_only and ph >= 3) break;
                if (ph == 3) {
                    for (ts) |*tk| {
                        if (tk.limit < tk.base) tk.limit = tk.base;
                    }
                }
                for (g.items) |*it| {
                    const sp = it.p[a].span;
                    const sl = spanTracks(g, it, a);
                    var crosses = false;
                    var any = false;
                    for (sl) |*tk| {
                        crosses = crosses or tk.max_kind == .flex;
                        any = any or pred(tk, ph, max_constraint, flex_only);
                    }
                    if (crosses != flex_only) continue;
                    if (!flex_only) {
                        if (sp > span and sp < next) next = sp;
                        if (sp != span) continue;
                    }
                    if (!any) continue;
                    const size = switch (ph) {
                        0 => try minContrib(g, it, a, !(flex_only and sp > 1)),
                        1, 3 => try contrib(g, it, a, 0),
                        else => try contrib(g, it, a, 1),
                    };
                    distribute(sl, gap, size, ph, max_constraint, flex_only);
                }
                // apply the planned increases of this phase
                for (ts) |*tk| {
                    if (ph < 3) {
                        tk.base += tk.planned;
                    } else if (tk.touched) {
                        if (tk.limit == MAXC) {
                            tk.limit = tk.base + tk.planned;
                            tk.inf_growable = true;
                        } else tk.limit += tk.planned;
                    }
                    tk.planned = 0;
                    tk.touched = false;
                }
            }
            if (pass == 0 and next != std.math.maxInt(i32)) {
                span = next;
            } else pass += 1;
        }
    }
    for (ts) |*tk| {
        if (tk.max_kind == .fit_content and tk.limit != MAXC) tk.limit = @min(tk.limit, @max(tk.max_v, tk.base));
        // tracks without items (or flexible ones) keep an infinite limit: it becomes the base size
        if (tk.limit < tk.base or tk.limit == MAXC) tk.limit = tk.base;
    }

    // Maximize tracks
    const gaps = gapsOf(ts, gap);
    if (isDef(avail)) {
        var sum: f32 = gaps;
        for (ts) |*tk| sum += tk.base;
        var free = avail - sum;
        var guard: usize = 0;
        while (free > eps and guard <= ts.len) : (guard += 1) {
            var n: f32 = 0;
            for (ts) |*tk| {
                if (tk.base < tk.limit and tk.max_kind != .flex) n += 1;
            }
            if (n == 0) break;
            const share = free / n;
            for (ts) |*tk| {
                if (!(tk.base < tk.limit and tk.max_kind != .flex)) continue;
                const add = @min(share, tk.limit - tk.base);
                tk.base += add;
                free -= add;
            }
        }
    } else if (avail == MAXC) {
        for (ts) |*tk| {
            if (tk.limit != MAXC and tk.max_kind != .flex) tk.base = tk.limit;
        }
    }

    // Expand flexible tracks
    if (has_flex) {
        var fr: f32 = 0;
        if (isDef(avail)) {
            fr = findFr(ts, gap, avail);
        } else if (avail == MAXC) {
            for (ts) |*tk| {
                if (tk.max_kind == .flex) fr = @max(fr, tk.base / @max(tk.max_v, 1));
            }
            for (g.items) |*it| {
                const sl = spanTracks(g, it, a);
                var crosses = false;
                for (sl) |*tk| crosses = crosses or tk.max_kind == .flex;
                if (crosses) fr = @max(fr, findFr(sl, gap, try contrib(g, it, a, 1)));
            }
        }
        // (on the layout-unit grid each track truncates and hands its remainder to the next one)
        var leftover: f32 = 0;
        for (ts) |*tk| {
            if (tk.max_kind != .flex) continue;
            if (!g.t.q64) {
                tk.base = @max(tk.base, fr * tk.max_v);
                continue;
            }
            const share = fr * 64 * tk.max_v + leftover;
            const expanded = @trunc(share + std.math.floatEps(f32));
            if (expanded / 64 >= tk.base) {
                tk.base = expanded / 64;
                leftover = @max(share - expanded, 0);
            }
        }
    }

    // Stretch auto tracks
    if (stretch and isDef(avail)) {
        var sum: f32 = gaps;
        var n: f32 = 0;
        for (ts) |*tk| {
            sum += tk.base;
            if (tk.max_kind == .auto) n += 1;
        }
        if (avail - sum > eps and n > 0) {
            // equal shares, each taken from what is left (integer layout units when quantized)
            var extra = avail - sum;
            for (ts) |*tk| {
                if (tk.max_kind != .auto) continue;
                const share = g.t.div(extra, n);
                tk.base += share;
                extra -= share;
                n -= 1;
            }
        }
    }
}

fn total(ts: []const Track, gap: f32) f32 {
    var sum: f32 = gapsOf(ts, gap);
    for (ts) |*tk| sum += tk.base;
    return sum;
}

fn selfAlign(self_: ?st.Align, items_: ?st.Align, cs: *const st.Style) st.Align {
    _ = cs;
    const v = self_ orelse items_ orelse return .stretch;
    return switch (v) {
        .flex_start, .baseline, .space_between, .space_around, .space_evenly => .start,
        .flex_end => .end,
        else => v,
    };
}

/// Border-box size of an item along `a` inside an area of size `area` (NaN when it must be measured).
fn usedSize(cs: *const st.Style, b: *const Box, a: usize, area: f32, al: st.Align) f32 {
    if (has(b.size[a])) return @max(clampO(b.size[a], b.min[a], b.max[a]), b.pb[a]);
    if (al == .stretch and !b.margin_auto[a] and !b.margin_auto[a + 2] and cs.size[a] == .auto and
        !(cs.aspect_ratio != null and (a == 1 or has(b.size[1]))))
    {
        return @max(clampO(area - b.marginSum(a), b.min[a], b.max[a]), b.pb[a]);
    }
    return NONE;
}

/// Content alignment (Blink's ComputeSetGeometry): assigns the track offsets (relative to the container's
/// border-box origin).
fn placeTracks(g: *G, a: usize, inner: f32, start: f32, al: st.Align) void {
    const t = g.t;
    const ts = g.tracks[a];
    var n: f32 = 0;
    for (ts) |*tk| n += @floatFromInt(@intFromBool(!tk.collapsed));
    const free = inner - total(ts, g.gap[a]);
    var pos = start;
    var gutter = g.gap[a];
    switch (al) {
        .space_between => if (n >= 2 and free >= 0) {
            gutter += t.div(free, n - 1);
        },
        .space_around => if (free >= 0) {
            if (n < 1) {
                pos += t.div(free, 2);
            } else {
                const space = t.div(free, n);
                pos += t.div(space, 2);
                gutter += space;
            }
        },
        .space_evenly => if (free >= 0) {
            const space = t.div(free, n + 1);
            pos += space;
            gutter += space;
        },
        .center => pos += t.div(free, 2),
        .end, .flex_end => pos += free,
        else => {},
    }
    var first = true;
    for (ts) |*tk| {
        if (!tk.collapsed) {
            if (!first) pos += gutter;
            first = false;
        }
        tk.off = pos;
        pos += tk.base;
    }
}

fn areaOf(ts: []const Track, gap: f32, start: i32, end_: i32) [2]f32 {
    const n: i32 = @intCast(ts.len);
    const s: usize = @intCast(std.math.clamp(start, 0, n));
    const e: usize = @intCast(std.math.clamp(end_, 0, n));
    _ = gap;
    if (e <= s) return .{ if (s < ts.len) ts[s].off else if (ts.len > 0) ts[ts.len - 1].off + ts[ts.len - 1].base else 0, 0 };
    // (track offsets include the content-distribution space, which belongs to spanning areas)
    return .{ ts[s].off, ts[e - 1].off + ts[e - 1].base - ts[s].off };
}

pub fn compute(t: *Tree, node: u32, in_: In) Error!Out {
    var in = in_;
    const s = &t.nodes.items[node].style;
    var box = t.sbox(s, &in);
    in.known = tr.styledKnown(in, &box);
    if (!in.layout and has(in.known[0]) and has(in.known[1])) return .{ .size = in.known };
    _ = t.applyRatio(s, &box, &in.known);
    const pb = box.pb;
    var inset: [4]f32 = undefined;
    for (0..4) |i| inset[i] = box.padding[i] + box.border[i];

    const mark = t.scratch.mark();
    defer t.scratch.release(mark);

    // items
    var count: usize = 0;
    {
        var ch = t.firstChild(node);
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display != .none and cs.position != .absolute) count += 1;
        }
    }
    const items = try t.scratch.alloc(t.alloc, Item, count);

    // explicit grid (with auto-repeat expansion)
    var inner: [2]f32 = .{ maxO(in.known[0] - pb[0], 0), if (in.indef_h) NONE else maxO(in.known[1] - pb[1], 0) };
    var g: G = .{ .t = t, .items = items, .tracks = undefined, .gap = .{ t.lp(s.gap[0], inner[0]), t.lp(s.gap[1], inner[1]) } };
    var tmpl: [2][]const st.Track = .{ s.grid_template_columns, s.grid_template_rows };
    var fit_range: [2][2]i32 = .{ .{ 0, 0 }, .{ 0, 0 } };
    for (0..2) |a| {
        const rep = (if (a == 0) s.grid_auto_repeat_columns else s.grid_auto_repeat_rows) orelse continue;
        const space = orElse(orElse(inner[a], box.max[a] - pb[a]), box.min[a] - pb[a]);
        const n = repeatCount(rep, tmpl[a], space, inner[a], g.gap[a]);
        const at = @min(@as(usize, rep.at), tmpl[a].len);
        const buf = try t.scratch.alloc(t.alloc, st.Track, tmpl[a].len + n * rep.tracks.len);
        @memcpy(buf[0..at], tmpl[a][0..at]);
        for (0..n) |k| @memcpy(buf[at + k * rep.tracks.len ..][0..rep.tracks.len], rep.tracks);
        @memcpy(buf[at + n * rep.tracks.len ..], tmpl[a][at..]);
        tmpl[a] = buf;
        if (rep.fit) fit_range[a] = .{ @intCast(at), @intCast(at + n * rep.tracks.len) };
    }
    const explicit: [2]i32 = .{ @intCast(@min(tmpl[0].len, max_line)), @intCast(@min(tmpl[1].len, max_line)) };

    // placement
    var lo: [2]i32 = .{ 0, 0 };
    {
        var i: usize = 0;
        var ch = t.firstChild(node);
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display == .none or cs.position == .absolute) continue;
            const it = &items[i];
            i += 1;
            it.* = .{
                .node = ch,
                .p = .{ resolvePlace(cs.grid_column, explicit[0]), resolvePlace(cs.grid_row, explicit[1]) },
                .placed = false,
                .contrib = .{ .{ NONE, NONE }, .{ NONE, NONE } },
                .margin = .{ 0, 0 },
                .size = .{ NONE, NONE },
                .area_w = NONE,
            };
            for (0..2) |a| {
                if (it.p[a].def) lo[a] = @min(lo[a], it.p[a].start);
            }
            const cb = t.rbox(cs, .{ NONE, NONE });
            it.margin = .{ cb.marginSum(0), cb.marginSum(1) };
        }
    }
    var n_tracks: [2]i32 = .{ explicit[0] - lo[0], explicit[1] - lo[1] };
    for (items) |*it| {
        for (0..2) |a| {
            if (it.p[a].def) it.p[a].start -= lo[a];
            n_tracks[a] = @max(n_tracks[a], it.p[a].start + it.p[a].span);
        }
    }
    {
        const col_flow = s.grid_auto_flow == .column or s.grid_auto_flow == .column_dense;
        const dense = s.grid_auto_flow == .row_dense or s.grid_auto_flow == .column_dense;
        const pa: usize = @intFromBool(col_flow);
        const sa: usize = 1 - pa;
        for (items) |*it| {
            if (it.p[0].def and it.p[1].def) it.placed = true;
        }
        // items locked to a row (of the flow)
        for (items) |*it| {
            if (it.placed or !it.p[sa].def) continue;
            var cp: i32 = 0;
            if (!dense) {
                // sparse packing: stay past the items this step already placed starting in the same row
                // (Blink keeps one cursor per start line)
                for (items) |*o| {
                    if (o.locked and o.p[sa].start == it.p[sa].start) cp = @max(cp, o.end(pa));
                }
            }
            while (overlap(items, pa, cp, it.p[pa].span, it.p[sa].start, it.p[sa].span)) |o| cp = o.end(pa);
            it.p[pa].start = cp;
            it.placed = true;
            it.locked = true;
            n_tracks[pa] = @max(n_tracks[pa], cp + it.p[pa].span);
        }
        var cp: i32 = 0;
        var cs_: i32 = 0;
        for (items) |*it| {
            if (it.placed) continue;
            const pspan = it.p[pa].span;
            const sspan = it.p[sa].span;
            if (it.p[pa].def) {
                if (dense) cs_ = 0 else if (it.p[pa].start < cp) cs_ += 1;
                cp = it.p[pa].start;
                while (overlap(items, pa, cp, pspan, cs_, sspan)) |o| cs_ = o.end(sa);
            } else {
                if (dense) {
                    cp = 0;
                    cs_ = 0;
                }
                while (true) {
                    if (cp + pspan > n_tracks[pa]) {
                        cp = 0;
                        cs_ += 1;
                        continue;
                    }
                    const o = overlap(items, pa, cp, pspan, cs_, sspan) orelse break;
                    cp = o.end(pa);
                }
            }
            it.p[pa].start = cp;
            it.p[sa].start = cs_;
            it.placed = true;
            n_tracks[sa] = @max(n_tracks[sa], cs_ + sspan);
        }
    }

    // tracks
    var used: [2][]bool = undefined;
    for (0..2) |a| {
        const n: usize = @intCast(@max(n_tracks[a], 0));
        g.tracks[a] = try t.scratch.alloc(t.alloc, Track, n);
        used[a] = try t.scratch.alloc(t.alloc, bool, n);
        @memset(used[a], false);
        for (items) |*it| {
            var k = it.p[a].start;
            while (k < it.end(a)) : (k += 1) {
                if (k >= 0 and k < n) used[a][@intCast(k)] = true;
            }
        }
    }
    const jc: st.Align = s.justify_content orelse .stretch;
    const ac: st.Align = s.align_content orelse .stretch;

    // inline size when not known: fit-content of the intrinsic sizes
    if (!has(in.known[0])) {
        const a0 = in.avail[0] - box.marginSum(0) - pb[0];
        resetTracks(&g, 0, s, tmpl[0], -lo[0], fit_range[0], used[0], NONE);
        var w: f32 = undefined;
        if (a0 == MINC) {
            try sizeTracks(&g, 0, MINC, false);
            w = total(g.tracks[0], g.gap[0]);
        } else {
            try sizeTracks(&g, 0, MAXC, false);
            w = total(g.tracks[0], g.gap[0]);
            if (isDef(a0) and w > a0) {
                resetTracks(&g, 0, s, tmpl[0], -lo[0], fit_range[0], used[0], NONE);
                try sizeTracks(&g, 0, MINC, false);
                w = @max(total(g.tracks[0], g.gap[0]), a0);
            }
        }
        in.known[0] = @max(clampO(w + pb[0], box.min[0], box.max[0]), pb[0]);
        inner[0] = in.known[0] - pb[0];
        g.gap[0] = t.lp(s.gap[0], inner[0]);
    }
    if (in.width_only) return .{ .size = .{ in.known[0], NONE } };
    const floor_h = t.applyRatio(s, &box, &in.known);
    if (has(floor_h)) {
        box.min[1] = floor_h;
        inner[1] = @max(floor_h - pb[1], 0);
    } else if (!in.indef_h) inner[1] = maxO(in.known[1] - pb[1], 0);
    g.gap[1] = t.lp(s.gap[1], inner[1]);

    // columns
    resetTracks(&g, 0, s, tmpl[0], -lo[0], fit_range[0], used[0], inner[0]);
    try sizeTracks(&g, 0, inner[0], jc == .stretch);
    placeTracks(&g, 0, inner[0], inset[0], jc);

    // item inline sizes
    for (items) |*it| {
        const cs = &t.nodes.items[it.node].style;
        const area = areaOf(g.tracks[0], g.gap[0], it.p[0].start, it.end(0));
        it.area_w = area[1];
        const b = t.rbox(cs, .{ area[1], NONE });
        it.margin = .{ b.marginSum(0), b.marginSum(1) };
        var w = usedSize(cs, &b, 0, area[1], selfAlign(cs.justify_self, s.justify_items, cs));
        if (!has(w)) {
            const kh = clampO(b.size[1], b.min[1], b.max[1]);
            w = try t.measureChild(it.node, .{ .known = .{ NONE, kh }, .parent = .{ area[1], NONE }, .avail = .{ area[1], MAXC } }, 0);
        }
        it.size[0] = w;
    }

    // rows
    const known_h = in.known[1];
    const inner_h: f32 = maxO(known_h - pb[1], 0);
    resetTracks(&g, 1, s, tmpl[1], -lo[1], fit_range[1], used[1], inner[1]);
    try sizeTracks(&g, 1, orElse(inner_h, MAXC), ac == .stretch);
    if (!has(inner_h)) {
        const min_h = box.min[1] - pb[1];
        if (total(g.tracks[1], g.gap[1]) < min_h) {
            resetTracks(&g, 1, s, tmpl[1], -lo[1], fit_range[1], used[1], inner[1]);
            try sizeTracks(&g, 1, min_h, ac == .stretch);
        }
    }
    var auto_h: f32 = NONE;
    if (!has(inner_h)) {
        // percentage rows and gaps resolve against the content-based height in a second pass
        var pct = s.gap[1].hasPercent();
        for (tmpl[1]) |tk| pct = pct or tk.min == .percent or tk.max == .percent;
        for (s.grid_auto_rows) |tk| pct = pct or tk.min == .percent or tk.max == .percent;
        if (pct) {
            const h = @max(clampO(total(g.tracks[1], g.gap[1]) + pb[1], box.min[1], box.max[1]) - pb[1], 0);
            g.gap[1] = t.lp(s.gap[1], h);
            resetTracks(&g, 1, s, tmpl[1], -lo[1], fit_range[1], used[1], h);
            for (items) |*it| it.contrib[1] = .{ NONE, NONE };
            try sizeTracks(&g, 1, h, ac == .stretch);
            auto_h = h + pb[1];
        }
    }
    const content_h = total(g.tracks[1], g.gap[1]);
    const size: [2]f32 = .{ in.known[0], orElse(orElse(known_h, auto_h), @max(clampO(content_h + pb[1], box.min[1], box.max[1]), pb[1])) };
    if (!in.layout) return .{ .size = size };
    const final_inner: [2]f32 = .{ @max(size[0] - pb[0], 0), @max(size[1] - pb[1], 0) };

    placeTracks(&g, 1, final_inner[1], inset[1], ac);

    // items
    var out: Out = .{ .size = size };
    var content: [2]f32 = .{ 0, 0 };
    for (items) |*it| {
        const cs = &t.nodes.items[it.node].style;
        const ax = areaOf(g.tracks[0], g.gap[0], it.p[0].start, it.end(0));
        const ay = areaOf(g.tracks[1], g.gap[1], it.p[1].start, it.end(1));
        const area: [2]f32 = .{ ax[1], ay[1] };
        var b = t.rbox(cs, area);
        const al: [2]st.Align = .{ selfAlign(cs.justify_self, s.justify_items, cs), selfAlign(cs.align_self, s.align_items, cs) };
        var known: [2]f32 = .{ it.size[0], usedSize(cs, &b, 1, area[1], al[1]) };
        if (!has(known[1])) {
            known[1] = try t.measureChild(it.node, .{ .known = .{ known[0], NONE }, .parent = area, .avail = .{ area[0], MAXC } }, 1);
            known[1] = @max(clampO(known[1], b.min[1], b.max[1]), b.pb[1]);
        }
        const o = try t.computeNode(it.node, .{ .known = known, .parent = area, .avail = area, .layout = true });
        var pos: [2]f32 = undefined;
        for (0..2) |a| {
            const free = area[a] - o.size[a] - b.marginSum(a);
            const sa = b.margin_auto[a];
            const ea = b.margin_auto[a + 2];
            if (sa or ea) {
                const f = @max(free, 0);
                if (sa and ea) {
                    b.margin[a] = t.div(f, 2);
                    b.margin[a + 2] = t.div(f, 2);
                } else if (sa) {
                    b.margin[a] = f;
                } else b.margin[a + 2] = f;
            }
            const start = if (a == 0) ax[0] else ay[0];
            pos[a] = start + b.margin[a] + (if (sa or ea) 0 else switch (al[a]) {
                .end => free,
                .center => t.div(free, 2),
                else => 0,
            });
        }
        if (cs.position != .absolute) {
            pos[0] += orElse(t.dim(cs.inset.left, area[0]), -orElse(t.dim(cs.inset.right, area[0]), 0));
            pos[1] += orElse(t.dim(cs.inset.top, area[1]), -orElse(t.dim(cs.inset.bottom, area[1]), 0));
        }
        t.setLayout(it.node, pos, &o, &b);
        t.accumContent(&content, it.node);
    }

    // absolutely positioned and hidden children
    if (count != t.nodes.items[node].child_count) {
        const pad_area: [4]f32 = .{ box.border[0], box.border[1], size[0] - box.border[0] - box.border[2], size[1] - box.border[1] - box.border[3] };
        var ch = t.firstChild(node);
        while (ch != no_node) : (ch = t.nextSibling(ch)) {
            const cs = &t.nodes.items[ch].style;
            if (cs.display == .none) {
                t.hide(ch);
                continue;
            }
            if (cs.position != .absolute) continue;
            // the static position of a grid child is the padding edge
            var sp: Tree.Static = .{ .rect = pad_area };
            const al: [2]st.Align = .{ selfAlign(cs.justify_self, s.justify_items, cs), selfAlign(cs.align_self, s.align_items, cs) };
            for (0..2) |a| sp.al[a] = switch (al[a]) {
                .end => 2,
                .center => 1,
                else => 0,
            };
            try t.placeAbsolute(node, ch, pad_area, sp);
            t.accumContent(&content, ch);
        }
    }
    out.content = content;
    return out;
}
