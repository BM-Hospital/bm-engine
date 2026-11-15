//! Bounded arc-length index for SVG text paths and CSS motion paths. Curves retain their
//! parameterization so sampled tangents do not jump between flattened chord directions.
const std = @import("std");
const path = @import("path.zig");
const types = @import("types.zig");
const P = struct {
    x: f64,
    y: f64,
    fn of(p: types.Point) P {
        return .{ .x = p.x, .y = p.y };
    }
    fn mix(a: P, b: P, t: f64) P {
        return .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t };
    }
    fn distance(a: P, b: P) f64 {
        const x = b.x - a.x;
        const y = b.y - a.y;
        return @sqrt(x * x + y * y);
    }
};
const Curve = struct {
    points: [4]P,
    line: bool = false,
    fn at(c: Curve, t: f64) P {
        if (c.line) return P.mix(c.points[0], c.points[3], t);
        const a = P.mix(c.points[0], c.points[1], t);
        const b = P.mix(c.points[1], c.points[2], t);
        const d = P.mix(c.points[2], c.points[3], t);
        return P.mix(P.mix(a, b, t), P.mix(b, d, t), t);
    }
    fn angle(c: Curve, t: f64) f32 {
        const before = c.at(@max(0, t - 0.0001));
        const after = c.at(@min(1, t + 0.0001));
        return @floatCast(std.math.atan2(after.y - before.y, after.x - before.x));
    }
};
const Piece = struct { curve: u32, t0: f64, t1: f64, start: f64, end: f64 };
pub const Sample = struct { x: f32, y: f32, angle: f32 };

pub const Measure = struct {
    curves: std.ArrayList(Curve) = .empty,
    pieces: std.ArrayList(Piece) = .empty,
    length: f64 = 0,
    closed: bool = false,
    svg_lines: bool = false,
    pub const max_pieces = 65536;

    pub fn deinit(m: *Measure, a: std.mem.Allocator) void {
        m.curves.deinit(a);
        m.pieces.deinit(a);
        m.* = .{};
    }

    /// False means the path exceeded the budget or contained non-finite geometry.
    pub fn build(m: *Measure, a: std.mem.Allocator, source: *const path.Path) !bool {
        var current: P = .{ .x = 0, .y = 0 };
        var start = current;
        var p: usize = 0;
        for (source.verbs.items) |verb| {
            var c: Curve = .{ .points = @splat(current) };
            switch (verb) {
                .move => {
                    current = P.of(source.points.items[p]);
                    start = current;
                    p += 1;
                    continue;
                },
                .line => {
                    c.points[3] = P.of(source.points.items[p]);
                    c.line = true;
                    p += 1;
                },
                .quad => {
                    const control = P.of(source.points.items[p]);
                    c.points[3] = P.of(source.points.items[p + 1]);
                    c.points[1] = P.mix(current, control, 2.0 / 3.0);
                    c.points[2] = P.mix(c.points[3], control, 2.0 / 3.0);
                    p += 2;
                },
                .cubic => {
                    for (1..4) |k| c.points[k] = P.of(source.points.items[p + k - 1]);
                    p += 3;
                },
                .close => {
                    c.points[3] = start;
                    c.line = true;
                    m.closed = true;
                },
            }
            for (c.points) |point| if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) return false;
            if (m.svg_lines and c.line) {
                c.line = false;
                c.points[1] = P.mix(c.points[0], c.points[3], 0.33);
                c.points[2] = P.mix(c.points[0], c.points[3], 0.66);
            }
            current = c.points[3];
            if (m.curves.items.len >= max_pieces) return false;
            const id: u32 = @intCast(m.curves.items.len);
            try m.curves.append(a, c);
            if (!try m.subdivide(a, id, 0, 1, c.points[0], c.points[3], 0)) return false;
        }
        return m.length > 0;
    }

    fn subdivide(m: *Measure, a: std.mem.Allocator, id: u32, t0: f64, t1: f64, from: P, to: P, depth: u8) error{OutOfMemory}!bool {
        const c = m.curves.items[id];
        const tm = (t0 + t1) / 2;
        const mid = c.at(tm);
        const quarter = c.at((t0 + tm) / 2);
        const third = c.at((tm + t1) / 2);
        const chord = from.distance(to);
        const polygon = from.distance(quarter) + quarter.distance(mid) + mid.distance(third) + third.distance(to);
        // Relative tolerance bounds work for very large curves too; depth and total piece
        // budgets prevent a hostile path or many references from unbounded subdivision.
        const nonuniform = mid.distance(P.mix(from, to, 0.5));
        if (!c.line and depth < 16 and (polygon - chord > @max(0.00001, polygon * 1e-7) or
            nonuniform > @max(0.001, polygon * 1e-5)))
        {
            if (!try m.subdivide(a, id, t0, tm, from, mid, depth + 1)) return false;
            return m.subdivide(a, id, tm, t1, mid, to, depth + 1);
        }
        if (chord == 0) return true;
        if (m.pieces.items.len >= max_pieces) return false;
        const end = m.length + polygon;
        if (!std.math.isFinite(end)) return false;
        try m.pieces.append(a, .{ .curve = id, .t0 = t0, .t1 = t1, .start = m.length, .end = end });
        m.length = end;
        return true;
    }

    /// Outside distances either clamp to an endpoint (CSS paths) or return null (SVG text).
    pub fn sample(m: *const Measure, distance: f64, clamp: bool) ?Sample {
        if (m.pieces.items.len == 0 or !std.math.isFinite(distance)) return null;
        if (!clamp and (distance < 0 or distance > m.length)) return null;
        const d = std.math.clamp(distance, 0, m.length);
        var lo: usize = 0;
        var hi = m.pieces.items.len - 1;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (m.pieces.items[mid].end < d) lo = mid + 1 else hi = mid;
        }
        const piece = m.pieces.items[lo];
        const t = piece.t0 + (piece.t1 - piece.t0) * ((d - piece.start) / (piece.end - piece.start));
        const c = m.curves.items[piece.curve];
        const point = c.at(t);
        return .{ .x = @floatCast(point.x), .y = @floatCast(point.y), .angle = c.angle(t) };
    }

    /// Takumi SVG uses Kurbo's ITP inverse at 0.1 user units (and cubic-raised lines).
    /// Retain that parameter bracket: replacing it with an exact inverse changes placement.
    pub fn sampleSvg(m: *const Measure, distance: f64) ?Sample {
        return m.sampleApprox(distance, 0.1, true);
    }

    pub fn sampleCss(m: *const Measure, distance: f64) ?Sample {
        return m.sampleApprox(std.math.clamp(distance, 0, m.length), 0.25, false);
    }

    fn sampleApprox(m: *const Measure, distance: f64, accuracy: f64, relative_accuracy: bool) ?Sample {
        if (distance < 0 or distance > m.length or !std.math.isFinite(distance) or m.pieces.items.len == 0) return null;
        var index: usize = 0;
        var end = m.pieces.items.len - 1;
        while (index < end) {
            const mid = index + (end - index) / 2;
            if (m.pieces.items[mid].end < distance) index = mid + 1 else end = mid;
        }
        const id = m.pieces.items[index].curve;
        var first = index;
        while (first > 0 and m.pieces.items[first - 1].curve == id) first -= 1;
        var last = index;
        while (last + 1 < m.pieces.items.len and m.pieces.items[last + 1].curve == id) last += 1;
        const start = m.pieces.items[first].start;
        const total = m.pieces.items[last].end - start;
        const at = distance - start;
        const c = m.curves.items[id];
        if (c.line) {
            const t = at / total;
            const point = c.at(t);
            return .{ .x = @floatCast(point.x), .y = @floatCast(point.y), .angle = c.angle(t) };
        }
        const polygon = c.points[0].distance(c.points[1]) + c.points[1].distance(c.points[2]) + c.points[2].distance(c.points[3]);
        const epsilon = (if (relative_accuracy) @max(accuracy, polygon * 1e-4) else accuracy) / total;
        var a: f64 = 0;
        var b: f64 = 1;
        var ya = -at;
        var yb = total - at;
        const power = @min(60, @max(0, @ceil(@log2(1.0 / epsilon)) - 1) + 1);
        var scaled = epsilon * @exp2(power);
        var t: f64 = if (at <= 0) 0 else if (at >= total) 1 else 0.5;
        if (at > 0 and at < total) {
            var guard: u32 = 0;
            while (b - a > 2 * epsilon and guard < 64) : (guard += 1) {
                const middle = (a + b) / 2;
                const r = scaled - (b - a) / 2;
                const xf = (yb * a - ya * b) / (yb - ya);
                const sigma = middle - xf;
                const delta = 0.2 * (b - a) * (b - a);
                const xt = if (delta <= @abs(sigma)) xf + std.math.copysign(delta, sigma) else middle;
                const x = if (@abs(xt - middle) <= r) xt else middle - std.math.copysign(r, sigma);
                var lo = first;
                var hi = last;
                while (lo < hi) {
                    const mid = lo + (hi - lo) / 2;
                    if (m.pieces.items[mid].t1 < x) lo = mid + 1 else hi = mid;
                }
                const p = m.pieces.items[lo];
                const y = p.start - start + (p.end - p.start) * (x - p.t0) / (p.t1 - p.t0) - at;
                if (y > 0) {
                    b = x;
                    yb = y;
                } else if (y < 0) {
                    a = x;
                    ya = y;
                } else {
                    a = x;
                    b = x;
                    break;
                }
                scaled *= 0.5;
            }
            t = (a + b) / 2;
        }
        const point = c.at(t);
        return .{ .x = @floatCast(point.x), .y = @floatCast(point.y), .angle = c.angle(t) };
    }
};

test "path measure samples lengths, contours, closed edges and curve tangents" {
    const a = std.testing.allocator;
    var p: path.Path = .empty;
    defer p.deinit(a);
    try p.moveTo(a, 0, 0);
    try p.lineTo(a, 30, 40);
    var m: Measure = .{};
    defer m.deinit(a);
    try std.testing.expect(try m.build(a, &p));
    try std.testing.expectApproxEqAbs(@as(f64, 50), m.length, 0.0001);
    const middle = m.sample(25, false).?;
    try std.testing.expectApproxEqAbs(@as(f32, 15), middle.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), middle.y, 0.0001);
    try std.testing.expect(m.sample(-1, false) == null);
    try std.testing.expectEqual(@as(f32, 30), m.sample(100, true).?.x);
    p.reset();
    m.deinit(a);
    try p.moveTo(a, 0, 0);
    try p.cubicTo(a, 0, 100, 100, 100, 100, 0);
    try std.testing.expect(try m.build(a, &p));
    const curve = m.sample(m.length / 2, false).?;
    try std.testing.expectApproxEqAbs(@as(f32, 50), curve.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 75), curve.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), curve.angle, 0.001);
}
