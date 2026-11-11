//! Path stroker: converts a path into a fillable outline (fill it with the NONZERO rule).
//!
//! Curves are flattened adaptively (`Options.tolerance`, in path units), then every contour is
//! offset to both sides. The outline is equivalent to the union of per-segment quads plus join
//! wedges / caps, so nonzero filling is exact; inner joins pivot through the centre line (Skia
//! style) unless the two inner offset lines intersect within both segments (then the clean
//! intersection point is used, which avoids overlap on the inside of smooth curves).
//!
//! Supported: width, miter / round / bevel joins + miter limit, butt / round / square caps,
//! dash array + offset (SVG semantics: odd arrays repeat, negative values disable dashing,
//! all-zero = solid), zero-length subpaths with round / square caps draw dots.
//! Reusable for CSS dashed borders / outlines.
const std = @import("std");
const raster = @import("../raster/raster.zig");
const num = @import("num.zig");
const Allocator = std.mem.Allocator;
const Path = raster.Path;
const Point = raster.Point;

pub const Cap = enum { butt, round, square };
pub const Join = enum { miter, round, bevel };

pub const Options = struct {
    width: f32 = 1,
    cap: Cap = .butt,
    join: Join = .miter,
    miter_limit: f32 = 4,
    /// Dash lengths (path units). Empty = solid.
    dashes: []const f32 = &.{},
    dash_offset: f32 = 0,
    /// Max flattening / arc approximation error in path units (pass ~0.1 / device scale).
    tolerance: f32 = 0.1,
};

const MAX_POINTS: usize = 1 << 22;
const MAX_DASHES: usize = 1 << 17;
const MAX_CURVE_STEPS: f32 = 256;

const SP = struct { x: f32, y: f32, corner: bool };
const Contour = struct { start: u32, len: u32, closed: bool, dot: bool = false };

/// Reusable stroker state (keep one around to avoid re-allocating the scratch lists).
pub const Stroker = struct {
    pts: std.ArrayList(SP) = .empty,
    contours: std.ArrayList(Contour) = .empty,
    dpts: std.ArrayList(SP) = .empty,
    dcontours: std.ArrayList(Contour) = .empty,
    left: std.ArrayList(Point) = .empty,
    right: std.ArrayList(Point) = .empty,

    pub fn deinit(s: *Stroker, alloc: Allocator) void {
        s.pts.deinit(alloc);
        s.contours.deinit(alloc);
        s.dpts.deinit(alloc);
        s.dcontours.deinit(alloc);
        s.left.deinit(alloc);
        s.right.deinit(alloc);
        s.* = .{};
    }

    /// Appends the stroke outline of `src` to `out`.
    pub fn stroke(s: *Stroker, alloc: Allocator, src: *const Path, opts: Options, out: *Path) !void {
        const hw = opts.width * 0.5;
        if (!(hw > 0) or !std.math.isFinite(hw)) return;
        var tol = opts.tolerance;
        if (!(tol > 1e-6)) tol = 1e-6;
        if (!(tol < hw)) tol = hw * 0.5;
        try s.flatten(alloc, src, tol);
        var pts = s.pts.items;
        var contours = s.contours.items;
        if (dashPattern(opts.dashes)) |total| {
            try s.dash(alloc, opts.dashes, total, opts.dash_offset);
            pts = s.dpts.items;
            contours = s.dcontours.items;
        }
        var e: Emitter = .{ .alloc = alloc, .out = out, .hw = hw, .tol = tol, .opts = opts };
        for (contours) |c| {
            if (c.len == 0) continue;
            const cp = pts[c.start..][0..c.len];
            if (c.len == 1) {
                if (c.dot) try e.dot(cp[0]);
                continue;
            }
            if (c.closed and c.len >= 2) {
                s.left.clearRetainingCapacity();
                s.right.clearRetainingCapacity();
                try e.side(&s.left, cp, true, 1);
                try e.side(&s.right, cp, true, -1);
                try e.polygon(s.left.items, false);
                try e.polygon(s.right.items, true);
            } else {
                s.left.clearRetainingCapacity();
                s.right.clearRetainingCapacity();
                try e.side(&s.left, cp, false, 1);
                try e.side(&s.right, cp, false, -1);
                const l = s.left.items;
                const r = s.right.items;
                if (l.len == 0 or r.len == 0) continue;
                try out.moveTo(alloc, l[0].x, l[0].y);
                for (l[1..]) |p| try out.lineTo(alloc, p.x, p.y);
                const n = cp.len;
                try e.cap(cp[n - 1], dirOf(cp[n - 2], cp[n - 1]));
                var i = r.len;
                while (i > 0) {
                    i -= 1;
                    try out.lineTo(alloc, r[i].x, r[i].y);
                }
                const d0 = dirOf(cp[0], cp[1]);
                try e.cap(cp[0], .{ .x = -d0.x, .y = -d0.y });
                try out.close(alloc);
            }
        }
    }

    fn push(s: *Stroker, alloc: Allocator, p: Point, corner: bool, eps: f32) !void {
        const c = &s.contours.items[s.contours.items.len - 1];
        if (c.len > 0) {
            const last = &s.pts.items[s.pts.items.len - 1];
            if (@abs(last.x - p.x) + @abs(last.y - p.y) <= eps) {
                if (corner) last.corner = true;
                return;
            }
        }
        if (s.pts.items.len >= MAX_POINTS) return error.OutOfMemory;
        try s.pts.append(alloc, .{ .x = p.x, .y = p.y, .corner = corner });
        c.len += 1;
    }

    fn flatten(s: *Stroker, alloc: Allocator, src: *const Path, tol: f32) !void {
        s.pts.clearRetainingCapacity();
        s.contours.clearRetainingCapacity();
        const eps = tol * 1e-3;
        const pts = src.points.items;
        var pi: usize = 0;
        var cur: Point = .{ .x = 0, .y = 0 };
        var start: Point = cur;
        var open = false;
        for (src.verbs.items) |v| {
            if (v != .move and v != .close and !open) {
                // drawing without a moveto: start at the current point
                try s.contours.append(alloc, .{ .start = @intCast(s.pts.items.len), .len = 0, .closed = false });
                try s.push(alloc, cur, true, eps);
                start = cur;
                open = true;
            }
            switch (v) {
                .move => {
                    if (pi >= pts.len) break;
                    cur = sane(pts[pi]);
                    pi += 1;
                    try s.contours.append(alloc, .{ .start = @intCast(s.pts.items.len), .len = 0, .closed = false });
                    try s.push(alloc, cur, true, eps);
                    start = cur;
                    open = true;
                },
                .line => {
                    if (pi >= pts.len) break;
                    cur = sane(pts[pi]);
                    pi += 1;
                    s.markDot();
                    try s.push(alloc, cur, true, eps);
                },
                .quad => {
                    if (pi + 2 > pts.len) break;
                    const c = sane(pts[pi]);
                    const e = sane(pts[pi + 1]);
                    pi += 2;
                    s.markDot();
                    const dd = @abs(cur.x - 2 * c.x + e.x) + @abs(cur.y - 2 * c.y + e.y);
                    const n = steps(dd * 0.25, tol);
                    var i: u32 = 1;
                    while (i < n) : (i += 1) {
                        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
                        const mt = 1 - t;
                        try s.push(alloc, .{
                            .x = mt * mt * cur.x + 2 * mt * t * c.x + t * t * e.x,
                            .y = mt * mt * cur.y + 2 * mt * t * c.y + t * t * e.y,
                        }, false, eps);
                    }
                    try s.push(alloc, e, true, eps);
                    cur = e;
                },
                .cubic => {
                    if (pi + 3 > pts.len) break;
                    const c1 = sane(pts[pi]);
                    const c2 = sane(pts[pi + 1]);
                    const e = sane(pts[pi + 2]);
                    pi += 3;
                    s.markDot();
                    const dd = @max(@abs(cur.x - 2 * c1.x + c2.x) + @abs(cur.y - 2 * c1.y + c2.y), @abs(c1.x - 2 * c2.x + e.x) + @abs(c1.y - 2 * c2.y + e.y));
                    const n = steps(dd * 0.75, tol);
                    var i: u32 = 1;
                    while (i < n) : (i += 1) {
                        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
                        const mt = 1 - t;
                        const a = mt * mt * mt;
                        const b = 3 * mt * mt * t;
                        const cc = 3 * mt * t * t;
                        const d = t * t * t;
                        try s.push(alloc, .{
                            .x = a * cur.x + b * c1.x + cc * c2.x + d * e.x,
                            .y = a * cur.y + b * c1.y + cc * c2.y + d * e.y,
                        }, false, eps);
                    }
                    try s.push(alloc, e, true, eps);
                    cur = e;
                },
                .close => {
                    if (!open) continue;
                    const c = &s.contours.items[s.contours.items.len - 1];
                    s.markDot();
                    c.closed = true;
                    // drop a duplicate closing point
                    if (c.len > 1) {
                        const last = s.pts.items[s.pts.items.len - 1];
                        const first = s.pts.items[c.start];
                        if (@abs(last.x - first.x) + @abs(last.y - first.y) <= eps) {
                            s.pts.items.len -= 1;
                            c.len -= 1;
                        }
                    }
                    cur = start;
                    open = false;
                },
            }
        }
    }

    /// The current contour has a drawing segment: a single remaining point is a dot.
    fn markDot(s: *Stroker) void {
        s.contours.items[s.contours.items.len - 1].dot = true;
    }

    fn dash(s: *Stroker, alloc: Allocator, dashes: []const f32, total: f32, offset: f32) !void {
        s.dpts.clearRetainingCapacity();
        s.dcontours.clearRetainingCapacity();
        const n = dashes.len;
        const pattern_len: usize = if (n % 2 == 1) n * 2 else n;
        var off = num.fmod(offset, total);
        if (!std.math.isFinite(off)) off = 0;
        for (s.contours.items) |c| {
            if (c.len == 0) continue;
            const cp = s.pts.items[c.start..][0..c.len];
            // initial dash state
            var idx: usize = 0;
            var rem = off;
            while (rem >= dashes[idx % n]) {
                rem -= dashes[idx % n];
                idx = (idx + 1) % pattern_len;
            }
            rem = dashes[idx % n] - rem;
            var on = idx % 2 == 0;
            const first_dash: ?usize = if (on) s.dcontours.items.len else null;
            if (on) try s.beginDash(alloc, .{ .x = cp[0].x, .y = cp[0].y }, true);
            const nseg = if (c.closed) c.len else c.len - 1;
            var i: usize = 0;
            var ended_on = on;
            while (i < nseg) : (i += 1) {
                const a = cp[i];
                const b = cp[(i + 1) % c.len];
                const dx = b.x - a.x;
                const dy = b.y - a.y;
                const len = @sqrt(dx * dx + dy * dy);
                var t: f32 = 0;
                while (len - t > rem) {
                    if (s.dcontours.items.len >= MAX_DASHES) return;
                    t += rem;
                    const f = t / len;
                    const p: Point = .{ .x = a.x + dx * f, .y = a.y + dy * f };
                    if (on) {
                        try s.dashPoint(alloc, p, true);
                    } else {
                        try s.beginDash(alloc, p, true);
                    }
                    idx = (idx + 1) % pattern_len;
                    rem = dashes[idx % n];
                    on = idx % 2 == 0;
                }
                rem -= len - t;
                if (on) try s.dashPoint(alloc, .{ .x = b.x, .y = b.y }, b.corner or (c.closed and (i + 1) % c.len == 0));
                ended_on = on;
            }
            // closed contour: merge the last dash into the first one
            if (c.closed and ended_on and first_dash != null and s.dcontours.items.len - 1 > first_dash.?) {
                const fd = s.dcontours.items[first_dash.?];
                const ld = &s.dcontours.items[s.dcontours.items.len - 1];
                var k: usize = 1;
                while (k < fd.len) : (k += 1) {
                    try s.dpts.append(alloc, s.dpts.items[fd.start + k]);
                    ld.len += 1;
                }
                s.dcontours.items[first_dash.?].len = 0;
            }
        }
    }

    fn beginDash(s: *Stroker, alloc: Allocator, p: Point, corner: bool) !void {
        try s.dcontours.append(alloc, .{ .start = @intCast(s.dpts.items.len), .len = 1, .closed = false, .dot = true });
        try s.dpts.append(alloc, .{ .x = p.x, .y = p.y, .corner = corner });
    }

    fn dashPoint(s: *Stroker, alloc: Allocator, p: Point, corner: bool) !void {
        const c = &s.dcontours.items[s.dcontours.items.len - 1];
        const last = s.dpts.items[s.dpts.items.len - 1];
        if (last.x == p.x and last.y == p.y) return;
        try s.dpts.append(alloc, .{ .x = p.x, .y = p.y, .corner = corner });
        c.len += 1;
    }
};

/// Total pattern length when dashing is active (null = solid stroke).
fn dashPattern(d: []const f32) ?f32 {
    if (d.len == 0) return null;
    var sum: f32 = 0;
    for (d) |v| {
        if (!(v >= 0) or !std.math.isFinite(v)) return null;
        sum += v;
    }
    if (d.len % 2 == 1) sum *= 2;
    if (!(sum > 0) or !std.math.isFinite(sum)) return null;
    return sum;
}

fn sane(p: Point) Point {
    const lim: f32 = 1e7;
    return .{ .x = std.math.clamp(p.x, -lim, lim), .y = std.math.clamp(p.y, -lim, lim) };
}

fn steps(dev: f32, tol: f32) u32 {
    const n = @ceil(@sqrt(dev / tol));
    if (!(n > 1)) return 1;
    return @intFromFloat(@min(n, MAX_CURVE_STEPS));
}

fn dirOf(a: SP, b: SP) Point {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const l = @sqrt(dx * dx + dy * dy);
    if (!(l > 0)) return .{ .x = 1, .y = 0 };
    return .{ .x = dx / l, .y = dy / l };
}

const Emitter = struct {
    alloc: Allocator,
    out: *Path,
    hw: f32,
    tol: f32,
    opts: Options,

    fn polygon(e: *Emitter, pts: []const Point, reverse: bool) !void {
        if (pts.len < 2) return;
        if (reverse) {
            var i = pts.len - 1;
            try e.out.moveTo(e.alloc, pts[i].x, pts[i].y);
            while (i > 0) {
                i -= 1;
                try e.out.lineTo(e.alloc, pts[i].x, pts[i].y);
            }
        } else {
            try e.out.moveTo(e.alloc, pts[0].x, pts[0].y);
            for (pts[1..]) |p| try e.out.lineTo(e.alloc, p.x, p.y);
        }
        try e.out.close(e.alloc);
    }

    /// Forward list of offset points on side `s` (+1 = left of travel in y-up maths).
    fn side(e: *Emitter, list: *std.ArrayList(Point), cp: []const SP, closed: bool, s: f32) !void {
        const n = cp.len;
        const hw = e.hw * s;
        if (!closed) {
            const d0 = dirOf(cp[0], cp[1]);
            try list.append(e.alloc, .{ .x = cp[0].x - d0.y * hw, .y = cp[0].y + d0.x * hw });
            var i: usize = 1;
            while (i + 1 < n) : (i += 1) try e.join(list, cp[i - 1], cp[i], cp[i + 1], s);
            const dl = dirOf(cp[n - 2], cp[n - 1]);
            try list.append(e.alloc, .{ .x = cp[n - 1].x - dl.y * hw, .y = cp[n - 1].y + dl.x * hw });
        } else {
            var i: usize = 0;
            while (i < n) : (i += 1) try e.join(list, cp[(i + n - 1) % n], cp[i], cp[(i + 1) % n], s);
        }
    }

    fn join(e: *Emitter, list: *std.ArrayList(Point), a: SP, p: SP, b: SP, s: f32) !void {
        const alloc = e.alloc;
        const hw = e.hw;
        const din = dirOf(a, p);
        const dout = dirOf(p, b);
        // normals N(d) = (-dy, dx), scaled by side
        const n0: Point = .{ .x = -din.y * s, .y = din.x * s };
        const n1: Point = .{ .x = -dout.y * s, .y = dout.x * s };
        const dp = din.x * dout.x + din.y * dout.y;
        const cross = din.x * dout.y - din.y * dout.x;
        const P: Point = .{ .x = p.x, .y = p.y };
        if (dp > 0.99999 and @abs(cross) < 1e-4) {
            try list.append(alloc, .{ .x = P.x + n1.x * hw, .y = P.y + n1.y * hw });
            return;
        }
        const degenerate = @abs(cross) < 1e-6;
        const outer = if (degenerate) s > 0 else s * cross < 0;
        const k = hw / (1 + dp); // miter point = P + (n0 + n1) * k
        if (!outer) {
            // inner side: clean intersection when it lies within both segments
            const reach = hw * @abs(cross) / (1 + dp);
            const la = num.hypot(p.x - a.x, p.y - a.y);
            const lb = num.hypot(b.x - p.x, b.y - p.y);
            if (dp > -0.999 and reach <= @min(la, lb)) {
                try list.append(alloc, .{ .x = P.x + (n0.x + n1.x) * k, .y = P.y + (n0.y + n1.y) * k });
            } else {
                try list.append(alloc, .{ .x = P.x + n0.x * hw, .y = P.y + n0.y * hw });
                try list.append(alloc, P);
                try list.append(alloc, .{ .x = P.x + n1.x * hw, .y = P.y + n1.y * hw });
            }
            return;
        }
        const join_kind: Join = if (p.corner) e.opts.join else if (dp > 0.5) .miter else .round;
        switch (join_kind) {
            .miter => {
                const lim = if (p.corner) e.opts.miter_limit else 2;
                if ((1 + dp) * lim * lim >= 2 and !degenerate) {
                    try list.append(alloc, .{ .x = P.x + (n0.x + n1.x) * k, .y = P.y + (n0.y + n1.y) * k });
                    return;
                }
            },
            .round => {
                const ang = if (degenerate) -std.math.pi * s else atan2(cross, dp);
                try e.arc(list, P, .{ .x = n0.x * hw, .y = n0.y * hw }, ang);
                return;
            },
            .bevel => {},
        }
        try list.append(alloc, .{ .x = P.x + n0.x * hw, .y = P.y + n0.y * hw });
        try list.append(alloc, .{ .x = P.x + n1.x * hw, .y = P.y + n1.y * hw });
    }

    /// Appends points of the arc around `c` starting at offset `v0`, sweeping `ang` radians
    /// (both end points included).
    fn arc(e: *Emitter, list: *std.ArrayList(Point), c: Point, v0: Point, ang: f32) !void {
        const n = e.arcSteps(ang);
        const sc = raster.sinCos(ang / @as(f32, @floatFromInt(n)));
        var v = v0;
        try list.append(e.alloc, .{ .x = c.x + v.x, .y = c.y + v.y });
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            v = .{ .x = v.x * sc[1] - v.y * sc[0], .y = v.x * sc[0] + v.y * sc[1] };
            try list.append(e.alloc, .{ .x = c.x + v.x, .y = c.y + v.y });
        }
    }

    fn arcSteps(e: *Emitter, ang: f32) u32 {
        // chord error hw * (1 - cos(step / 2)) <= tol / 4  ->  step ~= sqrt(2 tol / hw)
        const step = @min(@sqrt(2 * e.tol / e.hw), std.math.pi / 4.0);
        const n = @ceil(@abs(ang) / step);
        if (!(n > 1)) return 1;
        return @intFromFloat(@min(n, 256));
    }

    /// Cap at end point `p` with outward direction `d`: from the left offset (as seen along
    /// `d`) to the right offset. The left point is already in the path.
    fn cap(e: *Emitter, p: SP, d: Point) !void {
        const hw = e.hw;
        const nx = -d.y * hw;
        const ny = d.x * hw;
        switch (e.opts.cap) {
            .butt => {},
            .square => {
                try e.out.lineTo(e.alloc, p.x + nx + d.x * hw, p.y + ny + d.y * hw);
                try e.out.lineTo(e.alloc, p.x - nx + d.x * hw, p.y - ny + d.y * hw);
            },
            .round => {
                const n = e.arcSteps(std.math.pi);
                const sc = raster.sinCos(-std.math.pi / @as(f32, @floatFromInt(n)));
                var vx = nx;
                var vy = ny;
                var i: u32 = 1;
                while (i < n) : (i += 1) {
                    const tx = vx * sc[1] - vy * sc[0];
                    vy = vx * sc[0] + vy * sc[1];
                    vx = tx;
                    try e.out.lineTo(e.alloc, p.x + vx, p.y + vy);
                }
            },
        }
        try e.out.lineTo(e.alloc, p.x - nx, p.y - ny);
    }

    fn dot(e: *Emitter, p: SP) !void {
        const hw = e.hw;
        switch (e.opts.cap) {
            .butt => {},
            .square => try e.out.addRect(e.alloc, .{ .x = p.x - hw, .y = p.y - hw, .w = 2 * hw, .h = 2 * hw }),
            .round => {
                const n = e.arcSteps(2 * std.math.pi);
                const sc = raster.sinCos(2 * std.math.pi / @as(f32, @floatFromInt(n)));
                var vx = hw;
                var vy: f32 = 0;
                try e.out.moveTo(e.alloc, p.x + vx, p.y);
                var i: u32 = 1;
                while (i < n) : (i += 1) {
                    const tx = vx * sc[1] - vy * sc[0];
                    vy = vx * sc[0] + vy * sc[1];
                    vx = tx;
                    try e.out.lineTo(e.alloc, p.x + vx, p.y + vy);
                }
                try e.out.close(e.alloc);
            },
        }
    }
};

fn atan2(y: f32, x: f32) f32 {
    return num.atan2(y, x);
}

/// One-shot convenience: appends the stroke outline of `src` to `out` (fill it NONZERO).
/// Temporaries are allocated from `alloc` and freed before returning.
pub fn strokeToPath(alloc: Allocator, src: *const Path, opts: Options, out: *Path) !void {
    var s: Stroker = .{};
    defer s.deinit(alloc);
    try s.stroke(alloc, src, opts, out);
}

// ---- tests ---------------------------------------------------------------------------------

fn coverageSum(alloc: Allocator, p: *const Path, w: u32, h: u32) !f32 {
    var m = try raster.rasterize(alloc, p, raster.Affine.identity, .nonzero, .{ .x = 0, .y = 0, .w = w, .h = h });
    defer m.deinit(alloc);
    var sum: f32 = 0;
    for (m.data) |v| sum += @floatFromInt(v);
    return sum / 255;
}

test "stroke areas" {
    const a = std.testing.allocator;
    var src: Path = .{};
    defer src.deinit(a);
    try src.moveTo(a, 10, 50);
    try src.lineTo(a, 90, 50);
    var out: Path = .{};
    defer out.deinit(a);
    // butt: 80 x 10
    try strokeToPath(a, &src, .{ .width = 10 }, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 800), try coverageSum(a, &out, 100, 100), 1);
    out.reset();
    try strokeToPath(a, &src, .{ .width = 10, .cap = .square }, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 900), try coverageSum(a, &out, 100, 100), 1);
    out.reset();
    try strokeToPath(a, &src, .{ .width = 10, .cap = .round }, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 800 + std.math.pi * 25), try coverageSum(a, &out, 100, 100), 1.5);
    // dashes 10 on / 10 off over 80 -> 4 dashes of 10 x 10
    out.reset();
    try strokeToPath(a, &src, .{ .width = 10, .dashes = &.{10} }, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 400), try coverageSum(a, &out, 100, 100), 1);
    // closed square ring: outer 60x60 - inner 40x40 with miter joins
    var sq: Path = .{};
    defer sq.deinit(a);
    try sq.addRect(a, .{ .x = 20, .y = 20, .w = 50, .h = 50 });
    out.reset();
    try strokeToPath(a, &sq, .{ .width = 10 }, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 3600 - 1600), try coverageSum(a, &out, 100, 100), 1);
    // bevel loses 4 corner triangles of 12.5
    out.reset();
    try strokeToPath(a, &sq, .{ .width = 10, .join = .bevel }, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 2000 - 50), try coverageSum(a, &out, 100, 100), 1);
    // thick stroke on a tiny circle fills the disc completely (no hole)
    var c: Path = .{};
    defer c.deinit(a);
    try @import("pathdata.zig").ellipse(a, &c, 50, 50, 2, 2);
    out.reset();
    try strokeToPath(a, &c, .{ .width = 20, .tolerance = 0.05 }, &out);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi * 144), try coverageSum(a, &out, 100, 100), 3);
    // round-capped zero-length subpath = dot
    var z: Path = .{};
    defer z.deinit(a);
    try z.moveTo(a, 50, 50);
    try z.lineTo(a, 50, 50);
    out.reset();
    try strokeToPath(a, &z, .{ .width = 10, .cap = .round }, &out);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi * 25), try coverageSum(a, &out, 100, 100), 1);
}
