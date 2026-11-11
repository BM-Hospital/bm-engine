//! Stroker: converts a path into a fillable outline (move/line/close only, NONZERO rule), with
//! joins, caps and dashing. Curves are flattened first; everything is f32 and libm-free.
//!
//! Orientation guarantee: the output is, in the winding-number sense, a sum of simple pieces that
//! all have the same orientation (one half-quad per segment side, one wedge per outer join, one
//! piece per cap), whatever the direction of the input. Overlaps therefore only ever add up, so a
//! NONZERO fill has no holes, also where different subpaths or dashes cross each other.
const std = @import("std");
const types = @import("types.zig");
const path = @import("path.zig");
pub const Path = path.Path;
const Point = types.Point;
const Allocator = std.mem.Allocator;

pub const LineJoin = enum { miter, round, bevel };
pub const LineCap = enum { butt, round, square };

pub const StrokeOptions = struct {
    width: f32,
    join: LineJoin = .miter,
    /// SVG/CSS semantics: miter length / stroke width; joins exceeding it fall back to bevel.
    miter_limit: f32 = 4,
    cap: LineCap = .butt,
    /// Dash array (on, off, on, ...) in path units; odd length repeats (SVG); empty = solid.
    /// Arrays with a negative / NaN entry or a zero sum are ignored (solid).
    dash: []const f32 = &.{},
    dash_offset: f32 = 0,
    /// Device pixels per path unit (max scale of the transform that will be applied when the
    /// outline is filled). Used for the flattening tolerance of curves and round joins/caps.
    scale: f32 = 1,
};

/// Device-space flattening tolerance is 1 / INV_TOL px.
const INV_TOL: f32 = 10;
const MAX_SUBDIV: f32 = 256;
/// A subpath that would produce more dashes than this is emitted solid.
const MAX_DASHES: f32 = 100_000;

/// Appends to `out` (does not reset it) a closed outline of the stroke of `src`, to be filled with
/// the NONZERO rule. `alloc` is used for `out` and for temporary scratch (freed before returning).
/// Emits nothing when `width` is not a positive finite number.
pub fn strokePath(alloc: Allocator, src: *const Path, opts: StrokeOptions, out: *Path) !void {
    if (!(opts.width > 0) or !(opts.width < std.math.floatMax(f32))) return;
    var dashed: Path = .empty;
    defer dashed.deinit(alloc);
    var s = src;
    if (opts.dash.len != 0) {
        try work(alloc, src, &opts, true, &dashed);
        s = &dashed;
    }
    try work(alloc, s, &opts, false, out);
}

/// Dashing only: appends the dashed version of `src` (flattened, open polyline subpaths; a closed
/// subpath that fits in a single dash stays closed) to `out`. The pattern restarts on every
/// subpath. An invalid `dash` (see `StrokeOptions.dash`) appends the flattened path undashed.
pub fn dashPath(alloc: Allocator, src: *const Path, dash: []const f32, offset: f32, scale: f32, out: *Path) !void {
    return work(alloc, src, &.{ .width = 0, .dash = dash, .dash_offset = offset, .scale = scale }, true, out);
}

noinline fn work(alloc: Allocator, src: *const Path, o: *const StrokeOptions, dashing: bool, out: *Path) !void {
    const sc = if (o.scale > 0) types.clampF(o.scale, 1e-6, 1e6) else 1;
    const r = o.width * 0.5;
    // Half-circle segment count for a chord error of one tolerance: step = sqrt(8 * tol / r).
    const nh = types.clampF(@ceil(std.math.pi * @sqrt(r * sc * (INV_TOL * 0.125))), 2, 64);
    const step = types.sinCos(std.math.pi / nh);

    // Pattern period (twice the sum for odd-length arrays); 0 when the array is unusable.
    var period: f32 = 0;
    for (o.dash) |v| {
        if (!(v >= 0)) period = std.math.nan(f32);
        period += v;
    }
    if (o.dash.len & 1 != 0) period *= 2;
    if (!(period > 0) or !(period < std.math.floatMax(f32))) period = 0;
    var phase = o.dash_offset - @floor(o.dash_offset / period) * period;
    if (!(phase >= 0 and phase < period)) phase = 0;

    const m = 1e-3 / sc;
    var job: Job = .{
        .alloc = alloc,
        .out = out,
        .o = o,
        .dashing = dashing,
        .inv_tol = INV_TOL * sc,
        .min2 = m * m,
        .period = period,
        .phase = phase,
        .r = r,
        .ml2 = o.miter_limit * o.miter_limit,
        .sn = step[0],
        .cs = step[1],
        .nh = @intFromFloat(nh),
    };
    defer job.pts.deinit(alloc);
    defer job.held.deinit(alloc);
    job.run(src);
    if (job.oom) return error.OutOfMemory;
}

/// Unit direction and length of a segment.
const Seg = struct {
    x: f32,
    y: f32,
    len: f32,

    fn of(a: Point, b: Point) Seg {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len = @sqrt(dx * dx + dy * dy);
        return .{ .x = dx / len, .y = dy / len, .len = len };
    }
};

fn dist(a: Point, b: Point) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    return @sqrt(dx * dx + dy * dy);
}

fn lerp(a: Point, b: Point, t: f32) Point {
    return .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t };
}

const Job = struct {
    alloc: Allocator,
    out: *Path,
    o: *const StrokeOptions,
    /// Current subpath, flattened, without zero-length segments.
    pts: std.ArrayList(Point) = .empty,
    /// Dasher: first dash of a closed subpath, kept back so the last dash can run into it.
    held: std.ArrayList(Point) = .empty,
    dashing: bool,
    /// An allocation failed (reported once, at the end; the output is then incomplete).
    oom: bool = false,
    /// The next stroke point starts a contour.
    first: bool = true,
    /// 1 / path-space tolerance.
    inv_tol: f32,
    /// Squared length below which a segment is dropped (0.001 px).
    min2: f32,
    /// Dash period (0: no usable pattern) and start phase in [0, period).
    period: f32,
    phase: f32,
    /// Half width, squared miter limit.
    r: f32,
    ml2: f32,
    /// sin / cos of the arc step angle pi / nh; nh = segments per half circle.
    sn: f32,
    cs: f32,
    nh: u32,

    // ---- flattening -------------------------------------------------------------------------

    fn far(self: *const Job, a: Point, b: Point) bool {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const l2 = dx * dx + dy * dy;
        return l2 > self.min2 and l2 < std.math.floatMax(f32); // false for NaN / inf
    }

    noinline fn add(self: *Job, x: f32, y: f32) void {
        const it = self.pts.items;
        const p: Point = .{ .x = x, .y = y };
        const ok = if (it.len == 0) (x - x) + (y - y) == 0 else self.far(it[it.len - 1], p);
        if (ok) self.pts.append(self.alloc, p) catch {
            self.oom = true;
        };
    }

    /// Flattens the cubic `p0, c[0], c[1], c[2]` (without its start point).
    fn cubic(self: *Job, p0: Point, c: *const [3]Point) void {
        const ax = p0.x - 2 * c[0].x + c[1].x;
        const ay = p0.y - 2 * c[0].y + c[1].y;
        const bx = c[0].x - 2 * c[1].x + c[2].x;
        const by = c[0].y - 2 * c[1].y + c[2].y;
        const da = ax * ax + ay * ay;
        const db = bx * bx + by * by;
        // Wang: error <= 6 * dd / (8 n^2)
        const dd = @sqrt(if (da > db) da else db);
        const nf = types.clampF(@ceil(@sqrt(0.75 * dd * self.inv_tol)), 1, MAX_SUBDIV);
        const dt = 1 / nf;
        var t = dt;
        var i: u32 = @intFromFloat(nf);
        while (i > 1) : (i -= 1) {
            const m = 1 - t;
            const w0 = m * m * m;
            const w1 = 3 * m * m * t;
            const w2 = 3 * m * t * t;
            const w3 = t * t * t;
            self.add(
                w0 * p0.x + w1 * c[0].x + w2 * c[1].x + w3 * c[2].x,
                w0 * p0.y + w1 * c[0].y + w2 * c[1].y + w3 * c[2].y,
            );
            t += dt;
        }
        self.add(c[2].x, c[2].y);
    }

    fn run(self: *Job, src: *const Path) void {
        const all = src.points.items;
        var pi: usize = 0;
        var cur: Point = .{ .x = 0, .y = 0 };
        var start = cur;
        var segs = false; // the current subpath has at least one verb besides its `move`
        for (src.verbs.items) |verb| {
            const need: usize = switch (verb) {
                .move, .line => 1,
                .quad => 2,
                .cubic => 3,
                .close => 0,
            };
            if (need > all.len - pi or self.oom) break; // malformed path: ignore the rest
            const p = all[pi..];
            pi += need;
            var last = cur;
            switch (verb) {
                .move, .close => {
                    self.flush(verb == .close, segs or verb == .close);
                    // after a close, a following segment starts a new subpath at `start`
                    if (verb == .move) start = p[0];
                    last = start;
                    segs = false;
                },
                .line => last = p[0],
                .quad => {
                    last = p[1];
                    const c: [3]Point = .{ lerp(cur, p[0], 2.0 / 3.0), lerp(last, p[0], 2.0 / 3.0), last };
                    self.cubic(cur, &c);
                },
                .cubic => {
                    last = p[2];
                    self.cubic(cur, p[0..3]);
                },
            }
            if (need < 2) self.add(last.x, last.y);
            if (need != 0 and verb != .move) segs = true;
            cur = last;
        }
        self.flush(false, segs);
    }

    fn flush(self: *Job, closed_in: bool, segs: bool) void {
        var pts = self.pts.items;
        defer self.pts.clearRetainingCapacity();
        if (pts.len == 0) return;
        if (closed_in) {
            while (pts.len > 1 and !self.far(pts[0], pts[pts.len - 1])) pts.len -= 1;
        }
        const closed = closed_in and pts.len > 1;
        if (self.dashing) {
            if (pts.len > 1) return self.dashSub(pts, closed);
            // zero-length subpath: keep it as one (the stroker draws its caps)
            if (segs) self.putPoly(&.{ pts[0], pts[0] }, true, false);
            return;
        }
        if (pts.len == 1 and (!segs or self.o.cap == .butt)) return;
        self.side(pts, false, closed);
        if (closed) self.putVerb(.close);
        self.side(pts, true, closed);
        self.putVerb(.close);
    }

    // ---- stroking ---------------------------------------------------------------------------

    /// Appends the point `p + v * r`.
    noinline fn emit(self: *Job, px: f32, py: f32, vx: f32, vy: f32) void {
        self.put(self.first, px + vx * self.r, py + vy * self.r);
    }

    noinline fn put(self: *Job, move: bool, x: f32, y: f32) void {
        // the point first: a failed verb append then leaves no verb without its point
        if (self.out.points.append(self.alloc, .{ .x = x, .y = y })) |_| {
            self.putVerb(if (move) .move else .line);
        } else |_| {
            self.oom = true;
        }
    }

    /// Appends a verb; `close` makes the next stroke point start a contour.
    noinline fn putVerb(self: *Job, verb: path.Verb) void {
        self.first = verb == .close;
        self.out.verbs.append(self.alloc, verb) catch {
            self.oom = true;
        };
    }

    /// One side of a polyline (the other one when `rev`, walking backwards). Closed: the whole
    /// offset loop. Open: the offset line from the first to the last point plus the end cap.
    /// A single point is treated as a zero-length horizontal segment.
    /// The side offset to is the one of the normal (-d.y, d.x); arcs turn from it towards d.
    noinline fn side(self: *Job, pts: []const Point, rev: bool, closed: bool) void {
        const n = pts.len;
        const base: usize = if (closed) n - 1 else 0;
        var p = at(pts, rev, base);
        var a: Seg = .{ .x = if (rev) -1 else 1, .y = 0, .len = 0 };
        // Segment j runs from `p` to `next`. The first one only sets the direction (closed: it
        // is the closing segment) or starts the offset line (open); the others join at `p`.
        const count = if (closed) n + 1 else n - 1;
        for (0..count) |j| {
            const next = at(pts, rev, (base + 1 + j) % n);
            const b = Seg.of(p, next);
            defer {
                p = next;
                a = b;
            }
            if (j == 0) {
                if (!closed) self.emit(p.x, p.y, -b.y, b.x);
                continue;
            }
            const cross = a.x * b.y - a.y * b.x;
            const dot = a.x * b.x + a.y * b.y;
            // k * (na + nb): intersection of the two offset lines (miter point on the outside,
            // crossing point on the inside)
            const k = 1 / (1 + dot);
            const short = if (a.len < b.len) a.len else b.len;
            // Inner side (cross > 0): the crossing point is only safe (keeps every piece simple)
            // when it uses at most a quarter of both segments; otherwise go through the pivot.
            // Outer side: turns smaller than one arc step are mitred whatever the join type (the
            // miter point is then within one tolerance of the round / bevel join).
            const use_tip = if (cross > 0)
                self.r * cross * k <= 0.25 * short
            else
                dot >= self.cs or (self.o.join == .miter and self.ml2 * (1 + dot) >= 2);
            if (use_tip) {
                self.emit(p.x, p.y, (-a.y - b.y) * k, (a.x + b.x) * k);
            } else {
                self.emit(p.x, p.y, -a.y, a.x);
                if (cross > 0) {
                    self.emit(p.x, p.y, 0, 0);
                } else if (self.o.join == .round) {
                    self.arc(p, -a.y, a.x, dot);
                }
                self.emit(p.x, p.y, -b.y, b.x);
            }
        }
        if (closed) return;
        self.emit(p.x, p.y, -a.y, a.x);
        switch (self.o.cap) {
            .butt => {},
            .square => {
                const qx = p.x + a.x * self.r;
                const qy = p.y + a.y * self.r;
                self.emit(qx, qy, -a.y, a.x);
                self.emit(qx, qy, a.y, -a.x);
            },
            .round => self.arc(p, -a.y, a.x, -1),
        }
    }

    fn at(pts: []const Point, rev: bool, i: usize) Point {
        return pts[if (rev) pts.len - 1 - i else i];
    }

    /// Interior points of the arc around `c` that starts at the unit vector (fx, fy) and turns
    /// (in the normal -> direction sense) by the angle whose cosine is `cos_end` (at most pi).
    noinline fn arc(self: *Job, c: Point, fx: f32, fy: f32, cos_end: f32) void {
        var uc = self.cs;
        var us = self.sn;
        var i: u32 = 1;
        while (i < self.nh and uc > cos_end + 1e-4) : (i += 1) {
            self.emit(c.x, c.y, fx * uc + fy * us, fy * uc - fx * us);
            const t = uc * self.cs - us * self.sn;
            us = us * self.cs + uc * self.sn;
            uc = t;
        }
    }

    // ---- dashing ----------------------------------------------------------------------------

    noinline fn putPoly(self: *Job, pts: []const Point, move: bool, close: bool) void {
        for (pts, 0..) |p, i| self.put(move and i == 0, p.x, p.y);
        if (close) self.putVerb(.close);
    }

    noinline fn dashPut(self: *Job, hold: bool, move: bool, p: Point) void {
        if (!hold) return self.put(move, p.x, p.y);
        self.held.append(self.alloc, p) catch {
            self.oom = true;
        };
    }

    fn dashSub(self: *Job, pts: []const Point, closed: bool) void {
        const n = pts.len;
        const d = self.o.dash;
        const nseg = if (closed) n else n - 1;
        var total: f32 = 0;
        for (0..nseg) |i| total += dist(pts[i], pts[(i + 1) % n]);
        // period == 0: no usable pattern. The comparison is false for NaN as well.
        if (!(total / self.period * @as(f32, @floatFromInt(d.len)) <= MAX_DASHES)) {
            return self.putPoly(pts, true, closed);
        }

        // state at the start of the subpath
        var idx: usize = 0;
        var on = true;
        var ph = self.phase;
        for (0..2 * d.len) |_| {
            // advance past finished entries, but stay on a zero-length entry at phase 0
            if (!(ph >= d[idx]) or (ph == 0 and d[idx] == 0)) break;
            ph -= d[idx];
            idx = (idx + 1) % d.len;
            on = !on;
        }
        var rem = d[idx] - ph;

        self.held.clearRetainingCapacity();
        var hold = closed and on;
        if (on) self.dashPut(hold, true, pts[0]);
        var budget: u32 = 4 * @as(u32, @intFromFloat(MAX_DASHES));
        for (0..nseg) |i| {
            const a = pts[i];
            const b = pts[(i + 1) % n];
            const len = dist(a, b);
            var pos: f32 = 0;
            while (len - pos > rem and budget > 0) : (budget -= 1) {
                pos += rem;
                self.dashPut(hold, !on, lerp(a, b, pos / len));
                if (on) hold = false;
                on = !on;
                idx = (idx + 1) % d.len;
                rem = d[idx];
            }
            rem -= len - pos;
            if (on) self.dashPut(hold, false, b);
        }

        const h = self.held.items;
        if (h.len == 0) return;
        if (hold) return self.putPoly(h[0 .. h.len - 1], true, true); // one dash covers the loop
        // the dash that reaches the end of the loop continues into the first one
        self.putPoly(if (on) h[1..] else h, !on, false);
    }
};

// =================================================================================================
// Tests
// =================================================================================================

const testing = std.testing;

const TEdge = struct { x0: f32, y0: f32, x1: f32, y1: f32 };

fn tEdges(alloc: Allocator, p: *const Path) !std.ArrayList(TEdge) {
    var list: std.ArrayList(TEdge) = .empty;
    errdefer list.deinit(alloc);
    var pi: usize = 0;
    var start: Point = .{ .x = 0, .y = 0 };
    var cur = start;
    for (p.verbs.items) |v| {
        switch (v) {
            .move => {
                try list.append(alloc, .{ .x0 = cur.x, .y0 = cur.y, .x1 = start.x, .y1 = start.y });
                start = p.points.items[pi];
                cur = start;
                pi += 1;
            },
            .line => {
                const q = p.points.items[pi];
                pi += 1;
                try list.append(alloc, .{ .x0 = cur.x, .y0 = cur.y, .x1 = q.x, .y1 = q.y });
                cur = q;
            },
            .close => {
                try list.append(alloc, .{ .x0 = cur.x, .y0 = cur.y, .x1 = start.x, .y1 = start.y });
                cur = start;
            },
            else => return error.CurveInOutput,
        }
    }
    try list.append(alloc, .{ .x0 = cur.x, .y0 = cur.y, .x1 = start.x, .y1 = start.y });
    return list;
}

const TCross = struct { x: f32, dir: i32 };

fn tCrossLess(_: void, a: TCross, b: TCross) bool {
    return a.x < b.x;
}

const TArea = struct { area: f64, wmin: i32, wmax: i32 };

/// Nonzero-fill area by sampling scanlines (exact along x, `per_unit` lines per unit of y).
fn tArea(p: *const Path, per_unit: f32) !TArea {
    const alloc = testing.allocator;
    var edges = try tEdges(alloc, p);
    defer edges.deinit(alloc);
    var cr: std.ArrayList(TCross) = .empty;
    defer cr.deinit(alloc);
    const b = p.bounds();
    const lines: usize = @intFromFloat(@ceil(b.h * per_unit) + 1);
    const dy: f64 = 1.0 / @as(f64, per_unit);
    var res: TArea = .{ .area = 0, .wmin = 0, .wmax = 0 };
    for (0..lines) |j| {
        const y: f32 = @floatCast(@as(f64, b.y) + (@as(f64, @floatFromInt(j)) + 0.5) * dy);
        cr.clearRetainingCapacity();
        for (edges.items) |e| {
            if ((e.y0 <= y) == (e.y1 <= y)) continue;
            const t = (y - e.y0) / (e.y1 - e.y0);
            try cr.append(alloc, .{ .x = e.x0 + (e.x1 - e.x0) * t, .dir = if (e.y1 > e.y0) 1 else -1 });
        }
        std.mem.sort(TCross, cr.items, {}, tCrossLess);
        var w: i32 = 0;
        var px: f32 = 0;
        for (cr.items) |c| {
            if (w != 0) res.area += @as(f64, c.x - px) * dy;
            // crossings at (numerically) the same x are one event for the min/max bookkeeping
            w += c.dir;
            px = c.x;
        }
        // min / max winding over spans wider than float noise
        w = 0;
        for (cr.items, 0..) |c, i| {
            w += c.dir;
            if (i + 1 < cr.items.len and cr.items[i + 1].x - c.x > 1e-3) {
                res.wmin = @min(res.wmin, w);
                res.wmax = @max(res.wmax, w);
            }
        }
    }
    return res;
}

fn tWinding(p: *const Path, x: f32, y: f32) !i32 {
    var edges = try tEdges(testing.allocator, p);
    defer edges.deinit(testing.allocator);
    var w: i32 = 0;
    for (edges.items) |e| {
        if ((e.y0 <= y) == (e.y1 <= y)) continue;
        const t = (y - e.y0) / (e.y1 - e.y0);
        if (e.x0 + (e.x1 - e.x0) * t > x) w += if (e.y1 > e.y0) 1 else -1;
    }
    return w;
}

fn tStroke(src: *const Path, opts: StrokeOptions) !Path {
    var out: Path = .empty;
    errdefer out.deinit(testing.allocator);
    try strokePath(testing.allocator, src, opts, &out);
    for (out.verbs.items) |v| try testing.expect(v == .move or v == .line or v == .close);
    return out;
}

fn tStrokeArea(src: *const Path, opts: StrokeOptions) !f64 {
    var out = try tStroke(src, opts);
    defer out.deinit(testing.allocator);
    const a = try tArea(&out, 64);
    try testing.expect(a.wmin >= 0 or a.wmax <= 0); // one orientation only
    return a.area;
}

fn tPoly(pts: []const [2]f32, closed: bool) !Path {
    var p: Path = .empty;
    errdefer p.deinit(testing.allocator);
    for (pts, 0..) |q, i| {
        if (i == 0) try p.moveTo(testing.allocator, q[0], q[1]) else try p.lineTo(testing.allocator, q[0], q[1]);
    }
    if (closed) try p.close(testing.allocator);
    return p;
}

fn expectRel(expected: f64, actual: f64, tol: f64) !void {
    if (@abs(actual - expected) > tol * @abs(expected)) {
        std.debug.print("expected {d} got {d} (tol {d})\n", .{ expected, actual, tol });
        return error.TestExpectedApproxEq;
    }
}

/// Appends a convex polygon with a fixed orientation (positive shoelace sum).
fn tAddPoly(p: *Path, pts: []const [2]f32) !void {
    var s: f32 = 0;
    for (pts, 0..) |a, i| {
        const b = pts[(i + 1) % pts.len];
        s += a[0] * b[1] - a[1] * b[0];
    }
    for (0..pts.len) |i| {
        const q = pts[if (s < 0) pts.len - 1 - i else i];
        if (i == 0) try p.moveTo(testing.allocator, q[0], q[1]) else try p.lineTo(testing.allocator, q[0], q[1]);
    }
    try p.close(testing.allocator);
}

fn tAddCircle(p: *Path, c: [2]f32, r: f32) !void {
    var pts: [96][2]f32 = undefined;
    for (&pts, 0..) |*q, i| {
        const a = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / 96.0);
        q.* = .{ c[0] + r * @cos(a), c[1] + r * @sin(a) };
    }
    try tAddPoly(p, &pts);
}

/// Independent reference: the stroke as a union of per-segment rectangles, per-vertex join
/// pieces and cap pieces (each a consistently oriented convex polygon).
fn tReference(pts: []const [2]f32, closed: bool, o: StrokeOptions) !Path {
    var p: Path = .empty;
    errdefer p.deinit(testing.allocator);
    const r = o.width * 0.5;
    const n = pts.len;
    const nseg = if (closed) n else n - 1;
    for (0..nseg) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % n];
        const l = @sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1]));
        const d: [2]f32 = .{ (b[0] - a[0]) / l, (b[1] - a[1]) / l };
        const nx = -d[1] * r;
        const ny = d[0] * r;
        var e0: f32 = 0;
        var e1: f32 = 0;
        if (!closed and o.cap == .square) {
            if (i == 0) e0 = r;
            if (i == nseg - 1) e1 = r;
        }
        const a2: [2]f32 = .{ a[0] - d[0] * e0, a[1] - d[1] * e0 };
        const b2: [2]f32 = .{ b[0] + d[0] * e1, b[1] + d[1] * e1 };
        try tAddPoly(&p, &.{ .{ a2[0] + nx, a2[1] + ny }, .{ b2[0] + nx, b2[1] + ny }, .{ b2[0] - nx, b2[1] - ny }, .{ a2[0] - nx, a2[1] - ny } });
    }
    if (!closed and o.cap == .round) {
        try tAddCircle(&p, pts[0], r);
        try tAddCircle(&p, pts[n - 1], r);
    }
    for (0..n) |i| {
        if (!closed and (i == 0 or i == n - 1)) continue;
        const a = pts[(i + n - 1) % n];
        const v = pts[i];
        const b = pts[(i + 1) % n];
        if (o.join == .round) {
            try tAddCircle(&p, v, r);
            continue;
        }
        const la = @sqrt((v[0] - a[0]) * (v[0] - a[0]) + (v[1] - a[1]) * (v[1] - a[1]));
        const lb = @sqrt((b[0] - v[0]) * (b[0] - v[0]) + (b[1] - v[1]) * (b[1] - v[1]));
        const da: [2]f32 = .{ (v[0] - a[0]) / la, (v[1] - a[1]) / la };
        const db: [2]f32 = .{ (b[0] - v[0]) / lb, (b[1] - v[1]) / lb };
        const cross = da[0] * db[1] - da[1] * db[0];
        const dot = da[0] * db[0] + da[1] * db[1];
        const s: f32 = if (cross < 0) r else -r; // outer side
        const pa: [2]f32 = .{ v[0] - da[1] * s, v[1] + da[0] * s };
        const pb: [2]f32 = .{ v[0] - db[1] * s, v[1] + db[0] * s };
        if (o.join == .miter and o.miter_limit * o.miter_limit * (1 + dot) >= 2) {
            const k = s / (1 + dot);
            const tip: [2]f32 = .{ v[0] + (-da[1] - db[1]) * k, v[1] + (da[0] + db[0]) * k };
            try tAddPoly(&p, &.{ v, pa, tip, pb });
        } else {
            try tAddPoly(&p, &.{ v, pa, pb });
        }
    }
    return p;
}

fn tCompare(pts: []const [2]f32, closed: bool, o: StrokeOptions, tol: f64) !void {
    var src = try tPoly(pts, closed);
    defer src.deinit(testing.allocator);
    var ref = try tReference(pts, closed, o);
    defer ref.deinit(testing.allocator);
    const want = (try tArea(&ref, 64)).area;
    const got = try tStrokeArea(&src, o);
    try expectRel(want, got, tol);
}

/// Every point within 0.45 * width of the centreline must be filled.
fn tNoHoles(pts: []const [2]f32, closed: bool, o: StrokeOptions) !void {
    var src = try tPoly(pts, closed);
    defer src.deinit(testing.allocator);
    var out = try tStroke(&src, o);
    defer out.deinit(testing.allocator);
    var edges = try tEdges(testing.allocator, &out);
    defer edges.deinit(testing.allocator);
    const n = pts.len;
    const nseg = if (closed) n else n - 1;
    for (0..nseg) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % n];
        const l = @sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1]));
        const d: [2]f32 = .{ (b[0] - a[0]) / l, (b[1] - a[1]) / l };
        for (0..41) |ti| {
            const t = (0.001 + 0.998 * @as(f32, @floatFromInt(ti)) / 40.0) * l;
            for (0..19) |si| {
                const s = (@as(f32, @floatFromInt(si)) / 9.0 - 1.0) * 0.45 * o.width;
                // irrational-ish nudge keeps samples off exact edge/vertex coincidences
                const x = a[0] + d[0] * t - d[1] * s + 0.000137;
                const y = a[1] + d[1] * t + d[0] * s + 0.000071;
                var w: i32 = 0;
                for (edges.items) |e| {
                    if ((e.y0 <= y) == (e.y1 <= y)) continue;
                    const u = (y - e.y0) / (e.y1 - e.y0);
                    if (e.x0 + (e.x1 - e.x0) * u > x) w += if (e.y1 > e.y0) 1 else -1;
                }
                if (w == 0) {
                    std.debug.print("hole at ({d}, {d}) seg {d} t {d} s {d}\n", .{ x, y, i, t, s });
                    return error.HoleInStroke;
                }
            }
        }
    }
}

test "straight line: butt, square, round caps" {
    var src = try tPoly(&.{ .{ 3, 5 }, .{ 23, 5 } }, false);
    defer src.deinit(testing.allocator);
    try expectRel(80, try tStrokeArea(&src, .{ .width = 4 }), 0.001);
    try expectRel(96, try tStrokeArea(&src, .{ .width = 4, .cap = .square }), 0.001);
    try expectRel(80.0 + std.math.pi * 4.0, try tStrokeArea(&src, .{ .width = 4, .cap = .round }), 0.01);
    try expectRel(80.0 + std.math.pi * 4.0, try tStrokeArea(&src, .{ .width = 4, .cap = .round, .scale = 8 }), 0.002);

    // slanted, reversed direction
    var s2 = try tPoly(&.{ .{ 13, 17 }, .{ 1, 1 } }, false);
    defer s2.deinit(testing.allocator);
    try expectRel(20 * 3, try tStrokeArea(&s2, .{ .width = 3 }), 0.002);
    try expectRel(23 * 3, try tStrokeArea(&s2, .{ .width = 3, .cap = .square }), 0.002);
    try expectRel(60.0 + std.math.pi * 2.25, try tStrokeArea(&s2, .{ .width = 3, .cap = .round, .scale = 4 }), 0.005);
}

test "circle: ring area" {
    var src: Path = .empty;
    defer src.deinit(testing.allocator);
    try src.addEllipse(testing.allocator, .{ .x = 2, .y = 3, .w = 20, .h = 20 });
    for ([_]LineJoin{ .miter, .round, .bevel }) |j| {
        // ring = 2 * pi * R * w (the 4-cubic circle is ~0.03 % off a true circle)
        try expectRel(2.0 * std.math.pi * 10.0 * 3.0, try tStrokeArea(&src, .{ .width = 3, .join = j }), 0.01);
        try expectRel(2.0 * std.math.pi * 10.0 * 3.0, try tStrokeArea(&src, .{ .width = 3, .join = j, .scale = 4 }), 0.004);
    }
    // stroke wider than the radius of curvature: the disc is completely filled
    try expectRel(std.math.pi * 22.0 * 22.0, try tStrokeArea(&src, .{ .width = 24, .join = .round }), 0.01);
    try expectRel(std.math.pi * 22.0 * 22.0, try tStrokeArea(&src, .{ .width = 24, .join = .bevel }), 0.01);
}

test "joins at 90 degrees: analytic areas" {
    const pts = [_][2]f32{ .{ 2, 2 }, .{ 12, 2 }, .{ 12, 12 } };
    var src = try tPoly(&pts, false);
    defer src.deinit(testing.allocator);
    // two 10 x 2 rectangles overlap in r^2; the join adds r^2 (miter), r^2/2 (bevel), pi r^2/4 (round)
    try expectRel(40, try tStrokeArea(&src, .{ .width = 2, .join = .miter }), 0.002);
    try expectRel(39.5, try tStrokeArea(&src, .{ .width = 2, .join = .bevel }), 0.002);
    try expectRel(39.0 + std.math.pi / 4.0, try tStrokeArea(&src, .{ .width = 2, .join = .round, .scale = 8 }), 0.002);
    try expectRel(39.0 + std.math.pi / 4.0, try tStrokeArea(&src, .{ .width = 2, .join = .round }), 0.01);
    for ([_]LineJoin{ .miter, .round, .bevel }) |j| {
        try tNoHoles(&pts, false, .{ .width = 2, .join = j });
        try tCompare(&pts, false, .{ .width = 2, .join = j }, 0.01);
        // the other turn direction
        const rpts = [_][2]f32{ pts[2], pts[1], pts[0] };
        try tNoHoles(&rpts, false, .{ .width = 2, .join = j });
        try tCompare(&rpts, false, .{ .width = 2, .join = j }, 0.01);
    }
}

test "sharp joins: no holes, miter limit" {
    // 20 degree corner at (20, 5)
    const c = @cos(20.0 * std.math.pi / 180.0);
    const s = @sin(20.0 * std.math.pi / 180.0);
    const pts = [_][2]f32{ .{ 2, 5 }, .{ 20, 5 }, .{ 20 - 18 * c, 5 + 18 * s } };
    const rpts = [_][2]f32{ pts[2], pts[1], pts[0] };
    for ([_]f32{ 1, 3, 8 }) |w| {
        for ([_]LineJoin{ .miter, .round, .bevel }) |j| {
            for ([_]f32{ 4, 10 }) |ml| {
                const o: StrokeOptions = .{ .width = w, .join = j, .miter_limit = ml, .scale = 4 };
                try tNoHoles(&pts, false, o);
                try tNoHoles(&rpts, false, o);
                try tCompare(&pts, false, o, 0.015);
                try tCompare(&rpts, false, o, 0.015);
                try tNoHoles(&pts, true, o);
                try tCompare(&pts, true, o, 0.015);
            }
        }
    }
    // 1 / sin(10 deg) = 5.76: limit 4 gives the bevel, limit 10 the full miter
    var src = try tPoly(&pts, false);
    defer src.deinit(testing.allocator);
    const bevel = try tStrokeArea(&src, .{ .width = 2, .join = .bevel });
    const lim4 = try tStrokeArea(&src, .{ .width = 2, .join = .miter, .miter_limit = 4 });
    const lim10 = try tStrokeArea(&src, .{ .width = 2, .join = .miter, .miter_limit = 10 });
    try expectRel(bevel, lim4, 1e-6);
    // miter kite r^2 tan(80 deg) minus bevel triangle r^2 sin(160 deg) / 2
    const extra = @tan(80.0 * std.math.pi / 180.0) - 0.5 * @sin(160.0 * std.math.pi / 180.0);
    try expectRel(bevel + extra, lim10, 0.002);
    // miter tip is filled only with the larger limit
    var o4 = try tStroke(&src, .{ .width = 2, .join = .miter, .miter_limit = 4 });
    defer o4.deinit(testing.allocator);
    var o10 = try tStroke(&src, .{ .width = 2, .join = .miter, .miter_limit = 10 });
    defer o10.deinit(testing.allocator);
    const tx = 20 + 4 * @cos(10.0 * std.math.pi / 180.0);
    const ty = 5 - 4 * @sin(10.0 * std.math.pi / 180.0);
    try testing.expect(try tWinding(&o4, tx, ty) == 0);
    try testing.expect(try tWinding(&o10, tx, ty) != 0);
}

test "reversal, collinear and tiny segments" {
    // 180 degree turn
    const back = [_][2]f32{ .{ 2, 5 }, .{ 12, 5 }, .{ 4, 5 } };
    for ([_]LineJoin{ .miter, .round, .bevel }) |j| {
        try tNoHoles(&back, false, .{ .width = 2, .join = j });
        const add: f64 = if (j == .round) std.math.pi / 2.0 else 0;
        var src = try tPoly(&back, false);
        defer src.deinit(testing.allocator);
        try expectRel(20.0 + add, try tStrokeArea(&src, .{ .width = 2, .join = j, .scale = 8 }), 0.005);
    }
    // collinear points and repeated points change nothing
    var a = try tPoly(&.{ .{ 1, 1 }, .{ 5, 1 }, .{ 5, 1 }, .{ 9, 1 }, .{ 9, 1 } }, false);
    defer a.deinit(testing.allocator);
    try expectRel(16, try tStrokeArea(&a, .{ .width = 2, .join = .round }), 0.001);
    // closed two-point subpath = the segment with joins instead of caps
    var b = try tPoly(&.{ .{ 1, 1 }, .{ 9, 1 } }, true);
    defer b.deinit(testing.allocator);
    try expectRel(16, try tStrokeArea(&b, .{ .width = 2, .cap = .square }), 0.001);
    try expectRel(16.0 + std.math.pi, try tStrokeArea(&b, .{ .width = 2, .join = .round, .scale = 8 }), 0.004);
}

test "random polylines against the per-segment reference" {
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rnd = prng.random();
    var buf: [8][2]f32 = undefined;
    for (0..60) |iter| {
        const n = 3 + rnd.uintLessThan(usize, 6);
        for (buf[0..n]) |*q| q.* = .{ 4 + rnd.float(f32) * 16, 4 + rnd.float(f32) * 16 };
        const o: StrokeOptions = .{
            .width = 0.3 + rnd.float(f32) * 6,
            .join = rnd.enumValue(LineJoin),
            .cap = rnd.enumValue(LineCap),
            .scale = 6,
        };
        const closed = rnd.boolean();
        tCompare(buf[0..n], closed, o, 0.01) catch |e| {
            std.debug.print("iter {d} n {d} closed {} opts {any}\n", .{ iter, n, closed, o });
            return e;
        };
        try tNoHoles(buf[0..n], closed, o);
    }
}

test "tight curves have one orientation and no holes" {
    // a hairpin whose radius of curvature is far below the stroke radius
    var src: Path = .empty;
    defer src.deinit(testing.allocator);
    try src.moveTo(testing.allocator, 5, 10);
    try src.cubicTo(testing.allocator, 25, 9, 25, 11.5, 5, 10.5);
    try src.quadTo(testing.allocator, 12, 30, 20, 10.2);
    for ([_]LineJoin{ .miter, .round, .bevel }) |j| {
        var out = try tStroke(&src, .{ .width = 6, .join = j, .cap = .round });
        defer out.deinit(testing.allocator);
        const a = try tArea(&out, 32);
        try testing.expect(a.wmin >= 0 or a.wmax <= 0);
        // centreline samples are filled
        var fl: Path = .empty;
        defer fl.deinit(testing.allocator);
        try dashPath(testing.allocator, &src, &.{}, 0, 1, &fl);
        for (fl.points.items) |p| try testing.expect(try tWinding(&out, p.x + 0.0137, p.y + 0.0071) != 0);
    }
}

test "crossing subpaths drawn in opposite directions do not cancel" {
    var src: Path = .empty;
    defer src.deinit(testing.allocator);
    try src.moveTo(testing.allocator, 0, 10);
    try src.lineTo(testing.allocator, 20, 10);
    try src.moveTo(testing.allocator, 10, 20);
    try src.lineTo(testing.allocator, 10, 0);
    try src.moveTo(testing.allocator, 20, 10.5);
    try src.lineTo(testing.allocator, 0, 10.5);
    try src.addRect(testing.allocator, .{ .x = 5, .y = 5, .w = 10, .h = 10 });
    var out = try tStroke(&src, .{ .width = 2 });
    defer out.deinit(testing.allocator);
    const a = try tArea(&out, 32);
    try testing.expect(a.wmin >= 0 or a.wmax <= 0);
    try testing.expect(try tWinding(&out, 10.1, 10.2) != 0);
    try testing.expect(try tWinding(&out, 5.1, 10.2) != 0);
    try testing.expect(try tWinding(&out, 3.1, 10.2) != 0);
}

test "dashes on a line" {
    var src = try tPoly(&.{ .{ 0, 5 }, .{ 100, 5 } }, false);
    defer src.deinit(testing.allocator);
    const Case = struct { dash: []const f32, off: f32, on_len: f64, in: f32, out: f32 };
    const cases = [_]Case{
        .{ .dash = &.{ 10, 5 }, .off = 0, .on_len = 70, .in = 9, .out = 12 },
        .{ .dash = &.{ 10, 5 }, .off = 5, .on_len = 65, .in = 4, .out = 6 },
        .{ .dash = &.{ 10, 5 }, .off = 155, .on_len = 65, .in = 4, .out = 6 },
        .{ .dash = &.{ 10, 5 }, .off = -3, .on_len = 67, .in = 4, .out = 1 },
        .{ .dash = &.{ 10, 5 }, .off = -3 - 15 * 7, .on_len = 67, .in = 4, .out = 1 },
        .{ .dash = &.{ 10, 5 }, .off = 12, .on_len = 67, .in = 4, .out = 1 },
        .{ .dash = &.{10}, .off = 0, .on_len = 50, .in = 25, .out = 15 },
        .{ .dash = &.{ 5, 3, 2 }, .off = 0, .on_len = 50, .in = 9, .out = 6 },
        .{ .dash = &.{ 5, 3, 2 }, .off = 0, .on_len = 50, .in = 16, .out = 12 },
        // invalid arrays are solid
        .{ .dash = &.{ 0, 0 }, .off = 0, .on_len = 100, .in = 9, .out = -1 },
        .{ .dash = &.{ 5, -1 }, .off = 0, .on_len = 100, .in = 9, .out = -1 },
        .{ .dash = &.{ 5, std.math.nan(f32) }, .off = 0, .on_len = 100, .in = 9, .out = -1 },
        .{ .dash = &.{ 5, std.math.inf(f32) }, .off = 0, .on_len = 100, .in = 9, .out = -1 },
    };
    for (cases) |c| {
        const o: StrokeOptions = .{ .width = 2, .dash = c.dash, .dash_offset = c.off };
        try expectRel(c.on_len * 2, try tStrokeArea(&src, o), 0.001);
        var out = try tStroke(&src, o);
        defer out.deinit(testing.allocator);
        try testing.expect(try tWinding(&out, c.in, 5.3) != 0);
        try testing.expect(try tWinding(&out, c.out, 5.3) == 0);
    }
    // every dash gets caps
    try expectRel(70.0 * 2 + 7 * 4, try tStrokeArea(&src, .{ .width = 2, .dash = &.{ 10, 5 }, .cap = .square }), 0.001);
    // zero-length dashes are dots with round caps and nothing with butt caps
    try expectRel(20.0 * std.math.pi, try tStrokeArea(&src, .{ .width = 2, .dash = &.{ 0, 5 }, .cap = .round, .scale = 16 }), 0.01);
    try expectRel(20.0 * 4, try tStrokeArea(&src, .{ .width = 2, .dash = &.{ 0, 5 }, .cap = .square }), 0.001);
    var none = try tStroke(&src, .{ .width = 2, .dash = &.{ 0, 5 } });
    defer none.deinit(testing.allocator);
    try testing.expectEqual(@as(f64, 0), (try tArea(&none, 16)).area);
    // dash pattern continues across corners
    var bent = try tPoly(&.{ .{ 0, 0 }, .{ 12, 0 }, .{ 12, 12 } }, false);
    defer bent.deinit(testing.allocator);
    var d: Path = .empty;
    defer d.deinit(testing.allocator);
    try dashPath(testing.allocator, &bent, &.{ 10, 5 }, 0, 1, &d);
    try testing.expectEqualSlices(@TypeOf(d.verbs.items[0]), &.{ .move, .line, .move, .line }, d.verbs.items);
    try testing.expectApproxEqAbs(@as(f32, 3), d.points.items[2].y, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 12), d.points.items[3].y, 1e-4);
}

test "dashes on closed subpaths" {
    const a = testing.allocator;
    var sq: Path = .empty;
    defer sq.deinit(a);
    try sq.addRect(a, .{ .x = 0, .y = 0, .w = 10, .h = 10 }); // perimeter 40
    {
        // starts and ends "on": last dash runs through the start corner into the first
        var d: Path = .empty;
        defer d.deinit(a);
        try dashPath(a, &sq, &.{ 6, 4 }, 3, 1, &d);
        var moves: usize = 0;
        for (d.verbs.items) |v| {
            try testing.expect(v != .close);
            if (v == .move) moves += 1;
        }
        try testing.expectEqual(@as(usize, 4), moves);
        for (d.verbs.items, 0..) |v, i| {
            if (v == .move) try testing.expect(d.points.items[i].x != 0 or d.points.items[i].y != 0);
        }
        // the start corner is mitred like the other corners
        var out = try tStroke(&sq, .{ .width = 2, .dash = &.{ 6, 4 }, .dash_offset = 3 });
        defer out.deinit(a);
        try testing.expect(try tWinding(&out, -0.5, -0.5) != 0);
        // on length 24; a mitred 90 degree corner inside a dash neither adds nor removes area
        try expectRel(24.0 * 2, (try tArea(&out, 64)).area, 0.002);
    }
    {
        // starts "off"
        var out = try tStroke(&sq, .{ .width = 2, .dash = &.{ 6, 4 }, .dash_offset = 7 });
        defer out.deinit(a);
        try testing.expect(try tWinding(&out, -0.5, -0.5) == 0);
        try testing.expect(try tWinding(&out, 0.5, 0.5) == 0);
    }
    {
        // one dash longer than the loop: stays closed
        var d: Path = .empty;
        defer d.deinit(a);
        try dashPath(a, &sq, &.{ 100, 4 }, 0, 1, &d);
        try testing.expectEqualSlices(@TypeOf(d.verbs.items[0]), &.{ .move, .line, .line, .line, .close }, d.verbs.items);
        try expectRel(80, try tStrokeArea(&sq, .{ .width = 2, .dash = &.{ 100, 4 } }), 0.001);
    }
    // circle, radius 10, circumference 62.83
    var circle: Path = .empty;
    defer circle.deinit(a);
    try circle.addEllipse(a, .{ .x = 2, .y = 2, .w = 20, .h = 20 });
    const circ = 2.0 * std.math.pi * 10.0;
    try expectRel(36.0 + (circ - 60.0), try tStrokeArea(&circle, .{ .width = 1, .dash = &.{ 3, 2 }, .scale = 4 }), 0.01);
    try expectRel(36.0 + (circ - 61.3), try tStrokeArea(&circle, .{ .width = 1, .dash = &.{ 3, 2 }, .dash_offset = -1.3, .scale = 4 }), 0.01);
    try expectRel(30.5 + (circ - 62.0), try tStrokeArea(&circle, .{ .width = 1, .dash = &.{1.5}, .dash_offset = 100, .scale = 4 }), 0.01);
}

test "closed vs open square" {
    const pts = [_][2]f32{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 }, .{ 0, 10 } };
    var closed = try tPoly(&pts, true);
    defer closed.deinit(testing.allocator);
    var open = try tPoly(&(pts ++ [_][2]f32{.{ 0, 0 }}), false);
    defer open.deinit(testing.allocator);
    var oc = try tStroke(&closed, .{ .width = 2 });
    defer oc.deinit(testing.allocator);
    var oo = try tStroke(&open, .{ .width = 2 });
    defer oo.deinit(testing.allocator);
    try testing.expect(try tWinding(&oc, -0.5, -0.5) != 0);
    try testing.expect(try tWinding(&oo, -0.5, -0.5) == 0);
    try testing.expect(try tWinding(&oo, 10.5, 10.5) != 0);
    try testing.expect(try tWinding(&oc, 5, 5) == 0); // the inside stays empty
    try expectRel(144.0 - 64.0, (try tArea(&oc, 64)).area, 0.001);
    try expectRel(144.0 - 64.0 - 1.0, (try tArea(&oo, 64)).area, 0.001);
    // a rectangle border is two 4-point contours
    try testing.expectEqual(@as(usize, 8), oc.points.items.len);
    // explicit closing line + close == close
    try open.close(testing.allocator);
    try expectRel(80, try tStrokeArea(&open, .{ .width = 2 }), 0.001);
}

test "zero-length subpaths" {
    const a = testing.allocator;
    var src: Path = .empty;
    defer src.deinit(a);
    try src.moveTo(a, 5, 5);
    try src.lineTo(a, 5, 5);
    try src.moveTo(a, 15, 5);
    try src.close(a);
    try src.moveTo(a, 25, 5); // lone move: nothing
    try expectRel(2.0 * std.math.pi * 4.0, try tStrokeArea(&src, .{ .width = 4, .cap = .round, .scale = 16 }), 0.005);
    try expectRel(32, try tStrokeArea(&src, .{ .width = 4, .cap = .square }), 0.001);
    var out = try tStroke(&src, .{ .width = 4 });
    defer out.deinit(a);
    try testing.expect(out.isEmpty());
    var sq = try tStroke(&src, .{ .width = 4, .cap = .square });
    defer sq.deinit(a);
    try testing.expect(try tWinding(&sq, 6.9, 6.9) != 0);
    try testing.expect(try tWinding(&sq, 16.9, 3.1) != 0);
    try testing.expect(try tWinding(&sq, 25, 5) == 0);
}

test "degenerate and hostile input does not crash" {
    const a = testing.allocator;
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    var out: Path = .empty;
    defer out.deinit(a);

    var empty: Path = .empty;
    try strokePath(a, &empty, .{ .width = 2 }, &out);
    try testing.expect(out.isEmpty());

    var line = try tPoly(&.{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 } }, false);
    defer line.deinit(a);
    for ([_]f32{ 0, -1, nan, inf, -inf }) |w| {
        try strokePath(a, &line, .{ .width = w }, &out);
        try testing.expect(out.isEmpty());
    }
    for ([_]f32{ 0, -1, nan, inf, 1e-30, 1e30 }) |sc| {
        for ([_]f32{ 0, -1, nan, inf, 1e30 }) |ml| {
            out.reset();
            try strokePath(a, &line, .{ .width = 2, .scale = sc, .miter_limit = ml, .join = .miter, .cap = .round }, &out);
            try testing.expect(!out.isEmpty());
        }
    }
    for ([_]f32{ nan, inf, -inf, 1e30, -1e30 }) |off| {
        out.reset();
        try strokePath(a, &line, .{ .width = 2, .dash = &.{ 3, 1 }, .dash_offset = off }, &out);
        try testing.expect(!out.isEmpty());
    }

    // non-finite and huge coordinates
    var bad: Path = .empty;
    defer bad.deinit(a);
    try bad.moveTo(a, nan, 0);
    try bad.lineTo(a, 5, 5);
    try bad.lineTo(a, inf, 5);
    try bad.lineTo(a, 9, -inf);
    try bad.quadTo(a, nan, nan, 10, 10);
    try bad.cubicTo(a, 1e38, 1e38, -1e38, 1e38, 20, 20);
    try bad.cubicTo(a, inf, 0, 0, inf, 30, 20);
    try bad.close(a);
    try bad.lineTo(a, 3e38, -3e38);
    try bad.moveTo(a, 1e-40, 1e-41);
    try bad.lineTo(a, 2e-40, 1e-41);
    try bad.close(a);
    try bad.close(a);
    for ([_]LineJoin{ .miter, .round, .bevel }) |j| {
        for ([_]LineCap{ .butt, .round, .square }) |c| {
            out.reset();
            try strokePath(a, &bad, .{ .width = 3, .join = j, .cap = c }, &out);
            try strokePath(a, &bad, .{ .width = 3, .join = j, .cap = c, .dash = &.{ 2, 1, 0 }, .dash_offset = -7 }, &out);
        }
    }

    // malformed: verbs without points, segments without a move
    var mal: Path = .empty;
    defer mal.deinit(a);
    try mal.verbs.appendSlice(a, &.{ .line, .close, .cubic, .move, .line, .quad, .line });
    try mal.points.appendSlice(a, &.{ .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 }, .{ .x = 3, .y = 3 }, .{ .x = 4, .y = 4 }, .{ .x = 5, .y = 9 }, .{ .x = 6, .y = 6 } });
    out.reset();
    try strokePath(a, &mal, .{ .width = 1 }, &out);
    try strokePath(a, &mal, .{ .width = 1, .dash = &.{1} }, &out);

    // too many dashes: the subpath is emitted solid instead
    var long = try tPoly(&.{ .{ 0, 0 }, .{ 1e6, 0 } }, false);
    defer long.deinit(a);
    out.reset();
    try strokePath(a, &long, .{ .width = 1, .dash = &.{ 1e-3, 1e-3 } }, &out);
    try testing.expect(out.points.items.len <= 8);
    out.reset();
    try strokePath(a, &long, .{ .width = 1, .dash = &.{ 1e-30, 1e-30 } }, &out);
    try testing.expect(out.points.items.len <= 8);
    // just under the cap, with entries that are tiny next to the coordinates
    out.reset();
    try strokePath(a, &long, .{ .width = 1, .dash = &.{ 50, 0, 1e-9, 0 } }, &out);
    try testing.expect(out.points.items.len > 1000);

    // allocation failure is reported, nothing else
    var circle: Path = .empty;
    defer circle.deinit(a);
    try circle.addEllipse(a, .{ .x = 0, .y = 0, .w = 50, .h = 30 });
    try testing.checkAllAllocationFailures(a, tOom, .{&circle});
}

fn tOom(alloc: Allocator, src: *const Path) !void {
    var out: Path = .empty;
    defer out.deinit(alloc);
    try strokePath(alloc, src, .{ .width = 3, .join = .round, .dash = &.{ 7, 3 }, .dash_offset = 2 }, &out);
}

test "output size stays modest" {
    const a = testing.allocator;
    var rr: Path = .empty;
    defer rr.deinit(a);
    try rr.addRoundRect(a, .{ .x = 10, .y = 10, .w = 300, .h = 120 }, .{ .{ 16, 16 }, .{ 16, 16 }, .{ 16, 16 }, .{ 16, 16 } });
    var out = try tStroke(&rr, .{ .width = 4 });
    defer out.deinit(a);
    // 4 corners x 9 flattened segments + 4 sides, two contours, one point per vertex
    try testing.expect(out.points.items.len <= 100);
    const ring = 4.0 * (2.0 * (268.0 + 88.0) + 2.0 * std.math.pi * 16.0);
    try expectRel(ring, (try tArea(&out, 16)).area, 0.003);
}
