//! SVG path data (`d`) and basic-shape geometry -> `raster.Path` (user space).
//! Arcs become cubics. On a syntax error the path is kept up to the error (SVG error handling).
const std = @import("std");
const raster = @import("../raster/raster.zig");
const num = @import("num.zig");
const Allocator = std.mem.Allocator;
const Path = raster.Path;
const Point = raster.Point;

const KAPPA: f32 = 0.5522847498;

/// A path vertex for markers: position plus incoming / outgoing tangent directions.
pub const Vertex = struct { x: f32, y: f32, in: ?Point = null, out: ?Point = null };

const Builder = struct {
    alloc: Allocator,
    out: *Path,
    verts: ?*std.ArrayList(Vertex),
    cur: Point = .{ .x = 0, .y = 0 },
    start: Point = .{ .x = 0, .y = 0 },
    /// a drawing command after Z starts a new subpath at `start`
    need_move: bool = true,
    start_vertex: usize = 0,

    fn moveTo(b: *Builder, p: Point) !void {
        try b.out.moveTo(b.alloc, p.x, p.y);
        b.cur = p;
        b.start = p;
        b.need_move = false;
        if (b.verts) |v| {
            b.start_vertex = v.items.len;
            try v.append(b.alloc, .{ .x = p.x, .y = p.y });
        }
    }

    fn ensureMove(b: *Builder) !void {
        if (b.need_move) try b.moveTo(b.cur);
    }

    /// Records a segment for marker tangents. `d0` / `d1` are the start / end directions.
    fn seg(b: *Builder, d0: Point, d1: Point, end: Point) !void {
        const v = b.verts orelse return;
        if (v.items.len > 0) {
            const last = &v.items[v.items.len - 1];
            if (last.out == null) last.out = d0;
        }
        try v.append(b.alloc, .{ .x = end.x, .y = end.y, .in = d1 });
    }

    fn lineTo(b: *Builder, p: Point) !void {
        try b.ensureMove();
        try b.out.lineTo(b.alloc, p.x, p.y);
        const d: Point = .{ .x = p.x - b.cur.x, .y = p.y - b.cur.y };
        try b.seg(d, d, p);
        b.cur = p;
    }

    fn cubicTo(b: *Builder, c1: Point, c2: Point, p: Point) !void {
        try b.ensureMove();
        try b.out.cubicTo(b.alloc, c1.x, c1.y, c2.x, c2.y, p.x, p.y);
        try b.seg(dir3(b.cur, c1, c2, p, null), dir3(p, c2, c1, b.cur, true), p);
        b.cur = p;
    }

    fn quadTo(b: *Builder, c: Point, p: Point) !void {
        try b.ensureMove();
        try b.out.quadTo(b.alloc, c.x, c.y, p.x, p.y);
        try b.seg(dir3(b.cur, c, p, p, null), dir3(p, c, b.cur, b.cur, true), p);
        b.cur = p;
    }

    fn close(b: *Builder) !void {
        if (b.need_move) return;
        try b.out.close(b.alloc);
        if (b.verts) |v| {
            if (v.items.len > b.start_vertex) {
                const d: Point = .{ .x = b.start.x - b.cur.x, .y = b.start.y - b.cur.y };
                const zero = d.x == 0 and d.y == 0;
                const last = &v.items[v.items.len - 1];
                if (!zero) {
                    if (last.out == null) last.out = d;
                    try v.append(b.alloc, .{ .x = b.start.x, .y = b.start.y, .in = d });
                }
                // closed subpath: the start vertex's incoming / the end vertex's outgoing tangent
                const first = v.items[b.start_vertex];
                const end = &v.items[v.items.len - 1];
                if (end.out == null) end.out = first.out;
                v.items[b.start_vertex].in = end.in;
            }
        }
        b.cur = b.start;
        b.need_move = true;
    }
};

/// First non-degenerate direction among p->a, p->b, p->c (reversed when `rev`).
fn dir3(p: Point, a: Point, bb: Point, c: Point, rev_in: ?bool) Point {
    const rev = rev_in orelse false;
    for ([_]Point{ a, bb, c }) |q| {
        const d: Point = .{ .x = q.x - p.x, .y = q.y - p.y };
        if (d.x != 0 or d.y != 0) return if (rev) .{ .x = -d.x, .y = -d.y } else d;
    }
    return .{ .x = 0, .y = 0 };
}

fn isCmd(c: u8) bool {
    return switch (c) {
        'M', 'm', 'L', 'l', 'H', 'h', 'V', 'v', 'C', 'c', 'S', 's', 'Q', 'q', 'T', 't', 'A', 'a', 'Z', 'z' => true,
        else => false,
    };
}

/// Parses path data into `out` (appending). `verts` (optional) receives marker vertices.
pub fn parse(alloc: Allocator, d: []const u8, out: *Path, verts: ?*std.ArrayList(Vertex)) !void {
    var r: num.Reader = .{ .s = d };
    var b: Builder = .{ .alloc = alloc, .out = out, .verts = verts };
    var cmd: u8 = 0;
    var last_ctrl: Point = .{ .x = 0, .y = 0 };
    var last_cmd: u8 = 0;
    var first = true;
    while (true) {
        r.skipWs();
        if (r.i >= r.s.len) break;
        const c = r.s[r.i];
        if (isCmd(c)) {
            cmd = c;
            r.i += 1;
            r.skipWs();
        } else if (cmd == 0 or cmd == 'z' or cmd == 'Z') {
            return; // numbers without a command
        } else if (!(std.ascii.isDigit(c) or c == '-' or c == '+' or c == '.')) return;
        if (first and cmd != 'M' and cmd != 'm') return;
        first = false;
        const rel = std.ascii.isLower(cmd);
        const ox = if (rel) b.cur.x else 0;
        const oy = if (rel) b.cur.y else 0;
        const up = std.ascii.toUpper(cmd);
        switch (up) {
            'Z' => {
                try b.close();
                last_cmd = 'Z';
                continue;
            },
            'M' => {
                const x = r.next() orelse return;
                const y = r.next() orelse return;
                try b.moveTo(.{ .x = ox + x, .y = oy + y });
                cmd = if (rel) 'l' else 'L'; // implicit lineto
            },
            'L' => {
                const x = r.next() orelse return;
                const y = r.next() orelse return;
                try b.lineTo(.{ .x = ox + x, .y = oy + y });
            },
            'H' => {
                const x = r.next() orelse return;
                try b.lineTo(.{ .x = ox + x, .y = b.cur.y });
            },
            'V' => {
                const y = r.next() orelse return;
                try b.lineTo(.{ .x = b.cur.x, .y = oy + y });
            },
            'C' => {
                var v: [6]f32 = undefined;
                for (&v) |*x| x.* = r.next() orelse return;
                const c2: Point = .{ .x = ox + v[2], .y = oy + v[3] };
                try b.cubicTo(.{ .x = ox + v[0], .y = oy + v[1] }, c2, .{ .x = ox + v[4], .y = oy + v[5] });
                last_ctrl = c2;
            },
            'S' => {
                var v: [4]f32 = undefined;
                for (&v) |*x| x.* = r.next() orelse return;
                const c1: Point = if (last_cmd == 'C' or last_cmd == 'S') .{ .x = 2 * b.cur.x - last_ctrl.x, .y = 2 * b.cur.y - last_ctrl.y } else b.cur;
                const c2: Point = .{ .x = ox + v[0], .y = oy + v[1] };
                try b.cubicTo(c1, c2, .{ .x = ox + v[2], .y = oy + v[3] });
                last_ctrl = c2;
            },
            'Q' => {
                var v: [4]f32 = undefined;
                for (&v) |*x| x.* = r.next() orelse return;
                const q: Point = .{ .x = ox + v[0], .y = oy + v[1] };
                try b.quadTo(q, .{ .x = ox + v[2], .y = oy + v[3] });
                last_ctrl = q;
            },
            'T' => {
                var v: [2]f32 = undefined;
                for (&v) |*x| x.* = r.next() orelse return;
                const q: Point = if (last_cmd == 'Q' or last_cmd == 'T') .{ .x = 2 * b.cur.x - last_ctrl.x, .y = 2 * b.cur.y - last_ctrl.y } else b.cur;
                try b.quadTo(q, .{ .x = ox + v[0], .y = oy + v[1] });
                last_ctrl = q;
            },
            'A' => {
                const rx = r.next() orelse return;
                const ry = r.next() orelse return;
                const phi = r.next() orelse return;
                const large = r.flag() orelse return;
                const sweep = r.flag() orelse return;
                const x = r.next() orelse return;
                const y = r.next() orelse return;
                try arcTo(&b, rx, ry, phi, large, sweep, .{ .x = ox + x, .y = oy + y });
            },
            else => return,
        }
        last_cmd = up;
    }
}

fn arcTo(b: *Builder, rx_in: f32, ry_in: f32, phi_deg: f32, large: bool, sweep: bool, p: Point) !void {
    const p0 = b.cur;
    if (p0.x == p.x and p0.y == p.y) return;
    var rx = @abs(rx_in);
    var ry = @abs(ry_in);
    if (rx == 0 or ry == 0) return b.lineTo(p);
    const sc = raster.sinCos(num.fmod(phi_deg, 360) * (std.math.pi / 180.0));
    const sin_phi = sc[0];
    const cos_phi = sc[1];
    const dx2 = (p0.x - p.x) / 2;
    const dy2 = (p0.y - p.y) / 2;
    const x1p = cos_phi * dx2 + sin_phi * dy2;
    const y1p = -sin_phi * dx2 + cos_phi * dy2;
    const lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lambda > 1) {
        const s = @sqrt(lambda);
        rx *= s;
        ry *= s;
    }
    const rx2 = rx * rx;
    const ry2 = ry * ry;
    const numr = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p;
    const den = rx2 * y1p * y1p + ry2 * x1p * x1p;
    var coef: f32 = if (den > 0 and numr > 0) @sqrt(numr / den) else 0;
    if (large == sweep) coef = -coef;
    const cxp = coef * rx * y1p / ry;
    const cyp = -coef * ry * x1p / rx;
    const cx = cos_phi * cxp - sin_phi * cyp + (p0.x + p.x) / 2;
    const cy = sin_phi * cxp + cos_phi * cyp + (p0.y + p.y) / 2;
    const ux = (x1p - cxp) / rx;
    const uy = (y1p - cyp) / ry;
    const vx = (-x1p - cxp) / rx;
    const vy = (-y1p - cyp) / ry;
    const theta1 = num.atan2(uy, ux);
    var dtheta = num.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    if (!sweep and dtheta > 0) dtheta -= 2 * std.math.pi;
    if (sweep and dtheta < 0) dtheta += 2 * std.math.pi;
    if (!std.math.isFinite(dtheta) or !std.math.isFinite(cx) or !std.math.isFinite(cy)) return b.lineTo(p);
    const n: u32 = @intFromFloat(@min(@ceil(@abs(dtheta) / (std.math.pi / 2.0) - 0.001), 4));
    const segs = @max(n, 1);
    const delta = dtheta / @as(f32, @floatFromInt(segs));
    const tsc = raster.sinCos(delta / 4);
    const k = 4.0 / 3.0 * tsc[0] / tsc[1];
    var t = theta1;
    var i: u32 = 0;
    var start = p0;
    var first_dir: Point = undefined;
    var last_dir: Point = undefined;
    try b.ensureMove();
    while (i < segs) : (i += 1) {
        const s1 = raster.sinCos(t);
        const s2 = raster.sinCos(t + delta);
        // derivative directions on the unit circle, mapped through the ellipse
        const e1: Point = .{ .x = s1[1] - k * s1[0], .y = s1[0] + k * s1[1] };
        const e2: Point = .{ .x = s2[1] + k * s2[0], .y = s2[0] - k * s2[1] };
        const end: Point = if (i + 1 == segs) p else map(cx, cy, rx, ry, cos_phi, sin_phi, s2[1], s2[0]);
        const c1 = map(cx, cy, rx, ry, cos_phi, sin_phi, e1.x, e1.y);
        const c2 = map(cx, cy, rx, ry, cos_phi, sin_phi, e2.x, e2.y);
        try b.out.cubicTo(b.alloc, c1.x, c1.y, c2.x, c2.y, end.x, end.y);
        if (i == 0) first_dir = dir3(start, c1, c2, end, null);
        last_dir = dir3(end, c2, c1, start, true);
        start = end;
        t += delta;
    }
    try b.seg(first_dir, last_dir, p);
    b.cur = p;
}

fn map(cx: f32, cy: f32, rx: f32, ry: f32, cp: f32, sp: f32, ux: f32, uy: f32) Point {
    const x = ux * rx;
    const y = uy * ry;
    return .{ .x = cx + cp * x - sp * y, .y = cy + sp * x + cp * y };
}

// ---- basic shapes --------------------------------------------------------------------------

/// Ellipse starting at (cx + rx, cy), clockwise in y-down space (SVG 2 order).
pub fn ellipse(alloc: Allocator, out: *Path, cx: f32, cy: f32, rx: f32, ry: f32) !void {
    const kx = rx * KAPPA;
    const ky = ry * KAPPA;
    try out.moveTo(alloc, cx + rx, cy);
    try out.cubicTo(alloc, cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry);
    try out.cubicTo(alloc, cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy);
    try out.cubicTo(alloc, cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry);
    try out.cubicTo(alloc, cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy);
    try out.close(alloc);
}

pub fn rect(alloc: Allocator, out: *Path, x: f32, y: f32, w: f32, h: f32, rx_in: f32, ry_in: f32) !void {
    const rx = @min(rx_in, w / 2);
    const ry = @min(ry_in, h / 2);
    if (rx > 0 and ry > 0) {
        try out.addRoundRect(alloc, .{ .x = x, .y = y, .w = w, .h = h }, .{ .{ rx, ry }, .{ rx, ry }, .{ rx, ry }, .{ rx, ry } });
    } else {
        try out.addRect(alloc, .{ .x = x, .y = y, .w = w, .h = h });
    }
}

/// `points` attribute (polyline / polygon). An odd trailing coordinate is ignored.
pub fn polyline(alloc: Allocator, out: *Path, points: []const u8, close: bool, verts: ?*std.ArrayList(Vertex)) !void {
    var r: num.Reader = .{ .s = points };
    var b: Builder = .{ .alloc = alloc, .out = out, .verts = verts };
    var first = true;
    while (true) {
        const x = r.next() orelse break;
        const y = r.next() orelse break;
        if (first) try b.moveTo(.{ .x = x, .y = y }) else try b.lineTo(.{ .x = x, .y = y });
        first = false;
    }
    if (close and !first) try b.close();
}

/// Vertices of a line (for markers).
pub fn lineVerts(alloc: Allocator, verts: *std.ArrayList(Vertex), x1: f32, y1: f32, x2: f32, y2: f32) !void {
    const d: Point = .{ .x = x2 - x1, .y = y2 - y1 };
    try verts.append(alloc, .{ .x = x1, .y = y1, .out = d });
    try verts.append(alloc, .{ .x = x2, .y = y2, .in = d });
}

/// Tight bounds of a path (curve extrema included). Null when empty.
pub fn tightBounds(p: *const Path) ?raster.Rect {
    var bb: Box = .{};
    var pi: usize = 0;
    var cur: Point = .{ .x = 0, .y = 0 };
    const pts = p.points.items;
    for (p.verbs.items) |v| {
        switch (v) {
            .move, .line => {
                if (pi >= pts.len) break;
                cur = pts[pi];
                bb.add(cur);
                pi += 1;
            },
            .quad => {
                if (pi + 2 > pts.len) break;
                const c = pts[pi];
                const e = pts[pi + 1];
                // elevate to cubic
                const c1: Point = .{ .x = cur.x + 2.0 / 3.0 * (c.x - cur.x), .y = cur.y + 2.0 / 3.0 * (c.y - cur.y) };
                const c2: Point = .{ .x = e.x + 2.0 / 3.0 * (c.x - e.x), .y = e.y + 2.0 / 3.0 * (c.y - e.y) };
                bb.cubic(cur, c1, c2, e);
                cur = e;
                pi += 2;
            },
            .cubic => {
                if (pi + 3 > pts.len) break;
                bb.cubic(cur, pts[pi], pts[pi + 1], pts[pi + 2]);
                cur = pts[pi + 2];
                pi += 3;
            },
            .close => {},
        }
    }
    if (!bb.any) return null;
    return .{ .x = bb.x0, .y = bb.y0, .w = bb.x1 - bb.x0, .h = bb.y1 - bb.y0 };
}

const Box = struct {
    any: bool = false,
    x0: f32 = 0,
    y0: f32 = 0,
    x1: f32 = 0,
    y1: f32 = 0,

    fn add(b: *Box, p: Point) void {
        if (!b.any) {
            b.* = .{ .any = true, .x0 = p.x, .y0 = p.y, .x1 = p.x, .y1 = p.y };
            return;
        }
        b.x0 = @min(b.x0, p.x);
        b.y0 = @min(b.y0, p.y);
        b.x1 = @max(b.x1, p.x);
        b.y1 = @max(b.y1, p.y);
    }

    fn cubic(b: *Box, p0: Point, p1: Point, p2: Point, p3: Point) void {
        b.add(p3);
        const xs = [2][4]f32{ .{ p0.x, p1.x, p2.x, p3.x }, .{ p0.y, p1.y, p2.y, p3.y } };
        for (xs) |v| {
            const a0 = v[0];
            const a1 = v[1];
            const a2 = v[2];
            const a3 = v[3];
            // derivative coefficients: a t^2 + b t + c
            const qa = -a0 + 3 * a1 - 3 * a2 + a3;
            const qb = 2 * (a0 - 2 * a1 + a2);
            const qc = a1 - a0;
            var roots: [2]f32 = .{ -1, -1 };
            if (@abs(qa) < 1e-12) {
                if (@abs(qb) > 1e-12) roots[0] = -qc / qb;
            } else {
                const disc = qb * qb - 4 * qa * qc;
                if (disc >= 0) {
                    const sq = @sqrt(disc);
                    roots[0] = (-qb + sq) / (2 * qa);
                    roots[1] = (-qb - sq) / (2 * qa);
                }
            }
            for (roots) |t| {
                if (t > 0 and t < 1) {
                    const mt = 1 - t;
                    const x = mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x + 3 * mt * t * t * p2.x + t * t * t * p3.x;
                    const y = mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y + 3 * mt * t * t * p2.y + t * t * t * p3.y;
                    b.add(.{ .x = x, .y = y });
                }
            }
        }
    }
};

test "path data" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var p: Path = .{};
    var v: std.ArrayList(Vertex) = .empty;
    try parse(a, "M10 10h10v10H10zm5 5l1-1 2 2 A5 5 0 0 1 30 30 q1 1 2 2t3 3 s1 1 2 2c1,1,1,1,1,1z x 1", &p, &v);
    try std.testing.expect(p.verbs.items.len > 10);
    try std.testing.expectEqual(raster.Verb.move, p.verbs.items[0]);
    // after z, 'm5 5' is relative to the subpath start (10,10)
    try std.testing.expectEqual(@as(f32, 15), p.points.items[4].x);
    var p2: Path = .{};
    try parse(a, "M0 0 A10 10 0 0 1 20 0", &p2, null);
    const bb = tightBounds(&p2).?;
    try std.testing.expectApproxEqAbs(@as(f32, -10), bb.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 20), bb.w, 0.01);
    var p3: Path = .{};
    try parse(a, "M1 2 3", &p3, null); // error after M: keep the moveto only
    try std.testing.expectEqual(@as(usize, 1), p3.verbs.items.len);
}
