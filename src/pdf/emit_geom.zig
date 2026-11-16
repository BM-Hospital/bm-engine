//! Geometry of the PDF emitter, with the exact f32 arithmetic of the crates takumi-pdf drives
//! (tiny-skia-path `Transform` / `Rect` / path bounds, krilla `simplify_path`), so the numbers in
//! the content streams come out as takumi writes them.
//!
//! Paths are bm-render's `raster.Path` (move / line / quad / cubic / close); "finished" path
//! semantics (tiny-skia `PathBuilder::finish`: nothing for an empty path or a lone move) are in
//! `bounds`.
const std = @import("std");
const raster = @import("../raster/raster.zig");
const ct = @import("content.zig");

pub const Path = raster.Path;
pub const Affine = raster.Affine;
const Allocator = std.mem.Allocator;

/// tiny-skia `Transform` (row order `sx ky kx sy tx ty`, i.e. PDF `a b c d e f`).
pub const Tf = struct {
    sx: f32 = 1,
    ky: f32 = 0,
    kx: f32 = 0,
    sy: f32 = 1,
    tx: f32 = 0,
    ty: f32 = 0,

    pub const identity: Tf = .{};

    pub fn row(sx: f32, ky: f32, kx: f32, sy: f32, tx: f32, ty: f32) Tf {
        return .{ .sx = sx, .ky = ky, .kx = kx, .sy = sy, .tx = tx, .ty = ty };
    }

    pub fn translate(x: f32, y: f32) Tf {
        return .{ .tx = x, .ty = y };
    }

    pub fn scale(x: f32, y: f32) Tf {
        return .{ .sx = x, .sy = y };
    }

    /// bm-render affine (`a b c d e f`, same layout).
    pub fn fromAffine(m: Affine) Tf {
        return row(m.a, m.b, m.c, m.d, m.e, m.f);
    }

    /// tiny-skia `from_rotate` (degrees).
    pub fn rotate(deg: f32) Tf {
        const rad = deg * (std.math.pi / 180.0);
        // (no `@sin` / `@cos`: on macOS those bind to libSystem's libm; the engine's own f64 series, rounded to
        // f32, is the same code on every target. See docs/NATIVE.md "bit-identical output".)
        const sc = @import("../measure_xform.zig").sinCos64(rad);
        const c: f32 = @floatCast(sc[1]);
        const s: f32 = @floatCast(sc[0]);
        return row(c, s, -s, c, 0, 0);
    }

    /// tiny-skia `from_rotate_at`.
    pub fn rotateAt(deg: f32, x: f32, y: f32) Tf {
        return translate(x, y).pre(rotate(deg)).pre(translate(-x, -y));
    }

    pub fn eql(a: Tf, b: Tf) bool {
        return a.sx == b.sx and a.ky == b.ky and a.kx == b.kx and a.sy == b.sy and a.tx == b.tx and a.ty == b.ty;
    }

    pub fn isIdentity(t: Tf) bool {
        return t.eql(identity);
    }

    pub fn hasSkew(t: Tf) bool {
        return t.kx != 0 or t.ky != 0;
    }

    pub fn hasScale(t: Tf) bool {
        return t.sx != 1 or t.sy != 1;
    }

    pub fn isTranslate(t: Tf) bool {
        return !t.hasScale() and !t.hasSkew();
    }

    pub fn isFinite(t: Tf) bool {
        return std.math.isFinite(t.sx) and std.math.isFinite(t.ky) and std.math.isFinite(t.kx) and
            std.math.isFinite(t.sy) and std.math.isFinite(t.tx) and std.math.isFinite(t.ty);
    }

    fn mulAddMul(a: f32, b: f32, c: f32, d: f32) f32 {
        return @floatCast(@as(f64, a) * @as(f64, b) + @as(f64, c) * @as(f64, d));
    }

    /// tiny-skia `concat(a, b)`: `a * b` (b applied to points first).
    pub fn concat(a: Tf, b: Tf) Tf {
        if (a.isIdentity()) return b;
        if (b.isIdentity()) return a;
        if (!a.hasSkew() and !b.hasSkew()) {
            return row(a.sx * b.sx, 0, 0, a.sy * b.sy, a.sx * b.tx + a.tx, a.sy * b.ty + a.ty);
        }
        return row(
            mulAddMul(a.sx, b.sx, a.kx, b.ky),
            mulAddMul(a.ky, b.sx, a.sy, b.ky),
            mulAddMul(a.sx, b.kx, a.kx, b.sy),
            mulAddMul(a.ky, b.kx, a.sy, b.sy),
            mulAddMul(a.sx, b.tx, a.kx, b.ty) + a.tx,
            mulAddMul(a.ky, b.tx, a.sy, b.ty) + a.ty,
        );
    }

    /// `self.pre_concat(other)` = `self * other`.
    pub fn pre(a: Tf, b: Tf) Tf {
        return concat(a, b);
    }

    /// `self.post_concat(other)` = `other * self`.
    pub fn post(a: Tf, b: Tf) Tf {
        return concat(b, a);
    }

    /// tiny-skia `invert`.
    pub fn invert(t: Tf) ?Tf {
        if (t.isIdentity()) return t;
        if (!t.hasSkew()) {
            if (t.hasScale()) {
                const ix = 1.0 / t.sx;
                const iy = 1.0 / t.sy;
                return row(ix, 0, 0, iy, -t.tx * ix, -t.ty * iy);
            }
            return translate(-t.tx, -t.ty);
        }
        const det = @as(f64, t.sx) * @as(f64, t.sy) - @as(f64, t.kx) * @as(f64, t.ky);
        const tol: f32 = (1.0 / 4096.0) * (1.0 / 4096.0) * (1.0 / 4096.0);
        if (@abs(@as(f32, @floatCast(det))) <= tol) return null;
        const inv = 1.0 / det;
        const r = row(
            @floatCast(@as(f64, t.sy) * inv),
            @floatCast(-@as(f64, t.ky) * inv),
            @floatCast(-@as(f64, t.kx) * inv),
            @floatCast(@as(f64, t.sx) * inv),
            @floatCast((@as(f64, t.kx) * @as(f64, t.ty) - @as(f64, t.sy) * @as(f64, t.tx)) * inv),
            @floatCast((@as(f64, t.ky) * @as(f64, t.tx) - @as(f64, t.sx) * @as(f64, t.ty)) * inv),
        );
        return if (r.isFinite()) r else null;
    }

    /// tiny-skia `map_points` for one point.
    pub fn map(t: Tf, x: f32, y: f32) [2]f32 {
        if (t.isIdentity()) return .{ x, y };
        if (t.isTranslate()) return .{ x + t.tx, y + t.ty };
        if (!t.hasSkew()) return .{ x * t.sx + t.tx, y * t.sy + t.ty };
        return .{ x * t.sx + y * t.kx + t.tx, x * t.ky + y * t.sy + t.ty };
    }

    /// `[a b c d e f]` for `cm` / `/Matrix`.
    pub fn pdf(t: Tf) [6]f32 {
        return .{ t.sx, t.ky, t.kx, t.sy, t.tx, t.ty };
    }
};

/// tiny-skia `Rect` (left, top, right, bottom).
pub const LRect = struct {
    l: f32,
    t: f32,
    r: f32,
    b: f32,

    pub fn xywh(x: f32, y: f32, w: f32, h: f32) ?LRect {
        return ltrb(x, y, x + w, y + h);
    }

    /// tiny-skia `Rect::from_ltrb`: finite, not inverted (zero size allowed).
    pub fn ltrb(l: f32, t: f32, r: f32, b: f32) ?LRect {
        if (!std.math.isFinite(l) or !std.math.isFinite(t) or !std.math.isFinite(r) or !std.math.isFinite(b)) return null;
        if (!(l <= r and t <= b)) return null;
        if (!std.math.isFinite(r - l) or !std.math.isFinite(b - t)) return null;
        return .{ .l = l, .t = t, .r = r, .b = b };
    }

    pub fn width(s: LRect) f32 {
        return s.r - s.l;
    }
    pub fn height(s: LRect) f32 {
        return s.b - s.t;
    }

    /// krilla `Rect::expand` (union).
    pub fn expand(s: *LRect, o: LRect) void {
        s.* = .{ .l = @min(s.l, o.l), .t = @min(s.t, o.t), .r = @max(s.r, o.r), .b = @max(s.b, o.b) };
    }

    /// tiny-skia `Rect::transform`: bounds of the four transformed corners.
    pub fn transform(s: LRect, t: Tf) ?LRect {
        if (t.isIdentity()) return s;
        const pts = [4][2]f32{ t.map(s.l, s.t), t.map(s.r, s.t), t.map(s.r, s.b), t.map(s.l, s.b) };
        return fromPoints(&pts);
    }

    /// krilla `to_pdf_rect`: `[l t l+w t+h]`.
    pub fn pdf(s: LRect) [4]f32 {
        return .{ s.l, s.t, s.l + s.width(), s.t + s.height() };
    }
};

fn fromPoints(pts: []const [2]f32) ?LRect {
    if (pts.len == 0) return null;
    var l = pts[0][0];
    var t = pts[0][1];
    var r = l;
    var b = t;
    for (pts[1..]) |p| {
        if (!std.math.isFinite(p[0]) or !std.math.isFinite(p[1])) return null;
        l = @min(l, p[0]);
        t = @min(t, p[1]);
        r = @max(r, p[0]);
        b = @max(b, p[1]);
    }
    return LRect.ltrb(l, t, r, b);
}

/// Bounds of a finished path (tiny-skia `PathBuilder::finish` + `Rect::from_points` over every
/// point, control points included); null when the path would not finish (empty, a lone move).
pub fn bounds(p: *const Path) ?LRect {
    if (p.verbs.items.len <= 1 or p.points.items.len == 0) return null;
    const pts = p.points.items;
    var l = pts[0].x;
    var t = pts[0].y;
    var r = l;
    var b = t;
    for (pts) |q| {
        if (!std.math.isFinite(q.x) or !std.math.isFinite(q.y)) return null;
        l = @min(l, q.x);
        t = @min(t, q.y);
        r = @max(r, q.x);
        b = @max(b, q.y);
    }
    return LRect.ltrb(l, t, r, b);
}

/// `dst` = `src` with every point mapped through `t` (tiny-skia `Path::transform`).
pub fn transformed(a: Allocator, src: *const Path, t: Tf, dst: *Path) error{OutOfMemory}!void {
    dst.reset();
    try dst.verbs.appendSlice(a, src.verbs.items);
    try dst.points.ensureUnusedCapacity(a, src.points.items.len);
    for (src.points.items) |q| {
        const m = t.map(q.x, q.y);
        dst.points.appendAssumeCapacity(.{ .x = m[0], .y = m[1] });
    }
}

/// `dst` = `src` translated by (`dx`, `dy`) (krilla_path with an origin).
pub fn translated(a: Allocator, src: *const Path, dx: f32, dy: f32, dst: *Path) error{OutOfMemory}!void {
    dst.reset();
    try dst.verbs.appendSlice(a, src.verbs.items);
    try dst.points.ensureUnusedCapacity(a, src.points.items.len);
    for (src.points.items) |q| dst.points.appendAssumeCapacity(.{ .x = q.x + dx, .y = q.y + dy });
}

/// tiny-skia `PathBuilder::push_rect`.
pub fn rectPath(a: Allocator, p: *Path, r: LRect) error{OutOfMemory}!void {
    try p.addRect(a, .{ .x = r.l, .y = r.t, .w = r.width(), .h = r.height() });
}

// ---------------------------------------------------------------------------------------------
// krilla `content_draw_path` + `simplify_path`
// ---------------------------------------------------------------------------------------------

const Seg = union(enum) {
    move: [2]f32,
    line: [2]f32,
    quad: [4]f32,
    cubic: [6]f32,
    close,

    fn end(s: Seg) ?[2]f32 {
        return switch (s) {
            .move, .line => |p| p,
            .quad => |q| .{ q[2], q[3] },
            .cubic => |c| .{ c[4], c[5] },
            .close => null,
        };
    }
};

const Writer = struct {
    c: *ct.Content,
    prev: ?[2]f32 = null,
    list: std.ArrayList(Seg) = .empty,
    sub: []Seg = &.{},
    n: usize = 0,

    fn emit(w: *Writer, s: Seg) void {
        switch (s) {
            .move => |p| {
                w.c.moveTo(p[0], p[1]);
                w.prev = p;
            },
            .line => |p| {
                w.c.lineTo(p[0], p[1]);
                w.prev = p;
            },
            .quad => |q| {
                const p0 = w.prev orelse .{ 0, 0 };
                // krilla: quad -> cubic, `(n1 + n2 * 2) / 3`
                w.c.cubicTo((p0[0] + q[0] * 2.0) / 3.0, (p0[1] + q[1] * 2.0) / 3.0, (q[2] + q[0] * 2.0) / 3.0, (q[3] + q[1] * 2.0) / 3.0, q[2], q[3]);
                w.prev = .{ q[2], q[3] };
            },
            .cubic => |q| {
                w.c.cubicTo(q[0], q[1], q[2], q[3], q[4], q[5]);
                w.prev = .{ q[4], q[5] };
            },
            .close => w.c.closePath(),
        }
    }

    fn flush(w: *Writer, closed: bool) void {
        if (closed and w.n == 4) {
            if (w.sub[0] == .move and w.sub[1] == .line and w.sub[2] == .line and w.sub[3] == .line) {
                const p0 = w.sub[0].move;
                const p1 = w.sub[1].line;
                const p2 = w.sub[2].line;
                const p3 = w.sub[3].line;
                if (p0[1] == p1[1] and p1[0] == p2[0] and p2[1] == p3[1] and p3[0] == p0[0]) {
                    w.c.rect(p0[0], p0[1], p1[0] - p0[0], p2[1] - p1[1]);
                    w.n = 0;
                    return;
                }
            }
        }
        for (w.sub[0..w.n]) |s| w.emit(s);
        w.n = 0;
        if (closed) w.emit(.close);
    }

    fn push(w: *Writer, s: Seg) void {
        switch (s) {
            .move => {
                w.flush(false);
                w.add(s);
            },
            .line => |p| {
                // a segment that goes nowhere
                if (w.n > 0) if (w.sub[w.n - 1].end()) |e| if (e[0] == p[0] and e[1] == p[1]) return;
                w.add(s);
            },
            .close => {
                // `h` draws the closing edge itself
                if (w.n >= 2 and w.sub[0] == .move and w.sub[w.n - 1] == .line) {
                    const st = w.sub[0].move;
                    const la = w.sub[w.n - 1].line;
                    if (st[0] == la[0] and st[1] == la[1]) w.n -= 1;
                }
                w.flush(true);
            },
            else => w.add(s),
        }
    }

    fn add(w: *Writer, s: Seg) void {
        w.list.items.len = w.n;
        w.list.append(w.c.b.a, s) catch {
            w.c.b.failed = true;
            return;
        };
        w.sub = w.list.items;
        w.n += 1;
    }
};

/// Writes `p` (already in the stream's coordinates) as path operators, simplified like krilla
/// (`re` for axis-aligned rectangles traced from their top-left, zero-length lines and the
/// explicit closing edge dropped).
pub fn writePath(c: *ct.Content, p: *const Path) void {
    var w: Writer = .{ .c = c };
    const pts = p.points.items;
    var pi: usize = 0;
    for (p.verbs.items) |v| switch (v) {
        .move => {
            if (pi >= pts.len) break;
            w.push(.{ .move = .{ pts[pi].x, pts[pi].y } });
            pi += 1;
        },
        .line => {
            if (pi >= pts.len) break;
            w.push(.{ .line = .{ pts[pi].x, pts[pi].y } });
            pi += 1;
        },
        .quad => {
            if (pi + 2 > pts.len) break;
            w.push(.{ .quad = .{ pts[pi].x, pts[pi].y, pts[pi + 1].x, pts[pi + 1].y } });
            pi += 2;
        },
        .cubic => {
            if (pi + 3 > pts.len) break;
            w.push(.{ .cubic = .{ pts[pi].x, pts[pi].y, pts[pi + 1].x, pts[pi + 1].y, pts[pi + 2].x, pts[pi + 2].y } });
            pi += 3;
        },
        .close => w.push(.close),
    };
    w.flush(false);
}

const testing = std.testing;

test "transform arithmetic matches tiny-skia" {
    const page = Tf.row(1, 0, 0, -1, 0, 120).pre(Tf.scale(0.75, 0.75));
    try testing.expectEqual([6]f32{ 0.75, 0, 0, -0.75, 0, 120 }, page.pdf());
    // gradients.pdf: the conic pattern matrix
    const m = page.pre(Tf.rotateAt(-90, 335, 75));
    try testing.expectEqual(@as(f32, 0.75), m.ky);
    try testing.expectEqual(@as(f32, 195), m.tx);
    try testing.expectEqual(@as(f32, -187.5), m.ty);
    const inv = Tf.row(2, 0, 0, 4, 10, 20).invert().?;
    try testing.expectEqual([6]f32{ 0.5, 0, 0, 0.25, -5, -5 }, inv.pdf());
    try testing.expect(Tf.row(1, 1, 1, 1, 1, 1).invert() == null);
}

test "path simplification" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var c = ct.Content.init(a);
    var p: Path = .empty;
    // krilla `a_rectangle_with_repeated_corners_collapses_to_one_operator`
    try p.moveTo(a, 36, 55);
    try p.lineTo(a, 359, 55);
    try p.lineTo(a, 359, 55);
    try p.lineTo(a, 359, 57);
    try p.lineTo(a, 359, 57);
    try p.lineTo(a, 36, 57);
    try p.lineTo(a, 36, 57);
    try p.lineTo(a, 36, 55);
    try p.close(a);
    writePath(&c, &p);
    try testing.expectEqualStrings("36 55 323 2 re", c.bytes());
    // the other winding stays a path; an open path keeps its closing edge
    c.reset();
    p.reset();
    try p.moveTo(a, 0, 0);
    try p.lineTo(a, 0, 10);
    try p.lineTo(a, 20, 10);
    try p.lineTo(a, 20, 0);
    try p.close(a);
    try p.moveTo(a, 0, 0);
    try p.lineTo(a, 10, 0);
    try p.lineTo(a, 0, 0);
    writePath(&c, &p);
    try testing.expectEqualStrings("0 0 m 0 10 l 20 10 l 20 0 l\nh 0 0 m 10 0 l 0 0 l", c.bytes());
    // the empty clip of an area-less shape
    c.reset();
    p.reset();
    try p.moveTo(a, 390, 100.5);
    try p.lineTo(a, 390, 100.5);
    try p.close(a);
    writePath(&c, &p);
    try testing.expectEqualStrings("390 100.5 m\nh", c.bytes());
    try testing.expect(bounds(&p).?.width() == 0);
}
