//! Edge setup of Skia's / tiny-skia's supersampling scan converter (`SkEdge`, `SkQuadraticEdge`,
//! `SkCubicEdge`, `SkEdgeBuilder`, the Y/X-extrema chops of `SkGeometry`), reproduced bit for bit
//! as far as the algorithm is known: coordinates are converted to 26.6 fixed point at 4x
//! supersampling (`SHIFT = 2`, i.e. 1/256 px units), curves are forward-differenced into line
//! segments in 16.16, and every line advances by `dx` per sub-scanline.
//!
//! The scan-line walk and coverage accumulation live in `rasterizer.zig` (`Rasterizer`, mode
//! `.skia_ss`). All fixed-point arithmetic wraps (untrusted input never traps).
const std = @import("std");
const types = @import("types.zig");

/// log2 of the supersampling factor per axis.
pub const SHIFT = 2;
pub const SCALE = 1 << SHIFT;
/// Largest mask side (px) the 16.16 edge maths supports (tiny-skia: `rect_overflows_short_shift`).
pub const MAX_SIDE = 32767 >> SHIFT;
pub const NONE: u32 = 0xFFFF_FFFF;

/// Points as `{x, y}` arrays so the chop helpers can be shared between the axes.
pub const P = [2]f32;

const MAX_COEFF_SHIFT = 6;

pub const Kind = enum(u8) { line, quad, cubic };

pub const Edge = struct {
    /// 16.16 x at the centre of the current sub-scanline.
    x: i32 = 0,
    dx: i32 = 0,
    /// Sub-scanline range [first_y, last_y] of the current line segment.
    first_y: i32 = 0,
    last_y: i32 = 0,
    /// Bucket chain (edges starting on the same sub-scanline).
    next: u32 = NONE,
    winding: i8 = 1,
    kind: Kind = .line,
    /// quad: segments left (> 0); cubic: -(segments left) (< 0).
    curve_count: i8 = 0,
    curve_shift: u8 = 0,
    dshift: u8 = 0,
    /// quad: x, y, dx, dy, ddx, ddy, last_x, last_y. cubic: x, y, dx, dy, ddx, ddy, dddx, dddy, last_x, last_y.
    c: [10]i32 = undefined,

    /// `SkEdge::updateLine` (16.16 inputs) / `SkEdge::setLine` (26.6 inputs, `fdot6 = true`).
    noinline fn setLine(e: *Edge, ax: i32, ay: i32, bx: i32, by: i32, fdot6: bool) bool {
        var x0 = ax;
        var y0 = ay;
        var x1 = bx;
        var y1 = by;
        if (!fdot6) {
            y0 >>= 10;
            y1 >>= 10;
        }
        const top = (y0 +% 32) >> 6;
        const bot = (y1 +% 32) >> 6;
        if (top == bot) return false;
        if (!fdot6) {
            x0 >>= 10;
            x1 >>= 10;
        }
        const den = y1 -% y0;
        if (den == 0) return false;
        const slope = fdot6Div(x1 -% x0, den);
        const dy = ((top << 6) +% 32) -% y0;
        e.x = (x0 +% mul16(slope, dy)) << 10;
        e.dx = slope;
        e.first_y = top;
        e.last_y = bot -% 1;
        return true;
    }

    /// Advances a curve edge to its next non-empty line segment. False when exhausted.
    pub fn update(e: *Edge) bool {
        return if (e.kind == .quad) e.updateQuad() else e.updateCubic();
    }

    noinline fn updateQuad(e: *Edge) bool {
        var count = e.curve_count;
        var ox = e.c[0];
        var oy = e.c[1];
        var dx = e.c[2];
        var dy = e.c[3];
        const shift: u5 = @intCast(e.curve_shift & 31);
        var nx: i32 = undefined;
        var ny: i32 = undefined;
        var ok = false;
        while (true) {
            count -%= 1;
            if (count > 0) {
                nx = ox +% (dx >> shift);
                dx +%= e.c[4];
                ny = oy +% (dy >> shift);
                dy +%= e.c[5];
            } else {
                nx = e.c[6];
                ny = e.c[7];
            }
            ok = e.setLine(ox, oy, nx, ny, false);
            ox = nx;
            oy = ny;
            if (count <= 0 or ok) break;
        }
        e.c[0] = nx;
        e.c[1] = ny;
        e.c[2] = dx;
        e.c[3] = dy;
        e.curve_count = @max(count, 0);
        return ok;
    }

    noinline fn updateCubic(e: *Edge) bool {
        var count = e.curve_count;
        var ox = e.c[0];
        var oy = e.c[1];
        const dd_shift: u5 = @intCast(e.curve_shift & 31);
        const d_shift: u5 = @intCast(e.dshift & 31);
        var nx: i32 = undefined;
        var ny: i32 = undefined;
        var ok = false;
        while (true) {
            count +%= 1;
            if (count < 0) {
                nx = ox +% (e.c[2] >> d_shift);
                e.c[2] +%= e.c[4] >> dd_shift;
                e.c[4] +%= e.c[6];
                ny = oy +% (e.c[3] >> d_shift);
                e.c[3] +%= e.c[5] >> dd_shift;
                e.c[5] +%= e.c[7];
            } else {
                nx = e.c[8];
                ny = e.c[9];
            }
            // the finite fixed point does not always keep y monotonic: pin it
            if (ny < oy) ny = oy;
            ok = e.setLine(ox, oy, nx, ny, false);
            ox = nx;
            oy = ny;
            if (count >= 0 or ok) break;
        }
        e.c[0] = nx;
        e.c[1] = ny;
        e.curve_count = @min(count, 0);
        return ok;
    }
};

inline fn mul16(a: i32, b: i32) i32 {
    return @truncate((@as(i64, a) * @as(i64, b)) >> 16);
}

/// `SkFDot6Div`: 16.16 quotient of two 26.6 values, saturated.
inline fn fdot6Div(a: i32, b: i32) i32 {
    const v = @divTrunc(@as(i64, a) << 16, @as(i64, b));
    return @intCast(@min(@max(v, std.math.minInt(i32)), std.math.maxInt(i32)));
}

/// `(v * 256.0) as i32` (Rust cast: truncating, saturating, NaN -> 0).
inline fn toFDot6(v: f32) i32 {
    const s = v * @as(f32, 1 << (SHIFT + 6));
    if (s != s) return 0;
    return @intFromFloat(types.clampF(s, -2.0e9, 2.0e9));
}

inline fn cheapDistance(dx_in: i32, dy_in: i32) i32 {
    const dx: i32 = @intCast(@abs(dx_in) & 0x7FFF_FFFF);
    const dy: i32 = @intCast(@abs(dy_in) & 0x7FFF_FFFF);
    return if (dx > dy) dx +% (dy >> 1) else dy +% (dx >> 1);
}

/// Number of subdivisions (log2) for a curve whose control polygon deviates by (dx, dy).
inline fn diffToShift(dx: i32, dy: i32) i32 {
    var dist = cheapDistance(dx, dy);
    // 1/8 px accuracy, relaxed by the AA shift
    dist = (dist +% (1 << 4)) >> (3 + SHIFT);
    return @as(i32, 32 - @as(i32, @clz(@as(u32, @bitCast(dist))))) >> 1;
}

/// f(1/3) - b and f(2/3) - c of a cubic, with 19/512 approximating 1/27.
inline fn cubicDeltaFromLine(a: i32, b: i32, c: i32, d: i32) i32 {
    const one_third = ((a *% 8 -% b *% 15 +% 6 *% c +% d) *% 19) >> 9;
    const two_third = ((a +% 6 *% b -% c *% 15 +% d *% 8) *% 19) >> 9;
    const x: i32 = @intCast(@abs(one_third) & 0x7FFF_FFFF);
    const y: i32 = @intCast(@abs(two_third) & 0x7FFF_FFFF);
    return @max(x, y);
}

// ---- float geometry (SkGeometry) -----------------------------------------------------------

inline fn interp(a: P, b: P, t: f32) P {
    return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t };
}

/// `valid_unit_divide`: numer / denom when it lies strictly inside (0, 1).
fn validUnitDivide(numer_in: f32, denom_in: f32) ?f32 {
    var numer = numer_in;
    var denom = denom_in;
    if (numer < 0) {
        numer = -numer;
        denom = -denom;
    }
    if (denom == 0 or numer == 0 or numer >= denom) return null;
    const r = numer / denom;
    if (r != r or r == 0) return null;
    if (!(r < 1)) return null;
    return r;
}

/// `SkFindUnitQuadRoots`: roots of A t^2 + B t + C strictly inside (0, 1), ascending.
fn findUnitQuadRoots(a: f32, b: f32, c: f32, roots: *[2]f32) usize {
    var n: usize = 0;
    if (a == 0) {
        if (validUnitDivide(-c, b)) |r| {
            roots[0] = r;
            n = 1;
        }
        return n;
    }
    var dr: f64 = @as(f64, b) * @as(f64, b) - 4.0 * @as(f64, a) * @as(f64, c);
    if (!(dr >= 0)) return 0;
    dr = @sqrt(dr);
    const r: f32 = @floatCast(dr);
    if (!std.math.isFinite(r)) return 0;
    const q = if (b < 0) -(b - r) / 2 else -(b + r) / 2;
    if (validUnitDivide(q, a)) |v| {
        roots[n] = v;
        n += 1;
    }
    if (validUnitDivide(c, q)) |v| {
        roots[n] = v;
        n += 1;
    }
    if (n == 2) {
        if (roots[0] > roots[1]) {
            const t = roots[0];
            roots[0] = roots[1];
            roots[1] = t;
        } else if (roots[0] == roots[1]) n = 1;
    }
    return n;
}

/// `SkFindCubicExtrema`: parameters where the derivative of one coordinate vanishes.
fn findCubicExtrema(a: f32, b: f32, c: f32, d: f32, ts: *[2]f32) usize {
    const A = d - a + 3 * (b - c);
    const B = 2 * (a - b - b + c);
    const C = b - a;
    return findUnitQuadRoots(A, B, C, ts);
}

fn chopQuadAt(src: *const [3]P, dst: *[5]P, t: f32) void {
    const p01 = interp(src[0], src[1], t);
    const p12 = interp(src[1], src[2], t);
    dst[0] = src[0];
    dst[1] = p01;
    dst[2] = interp(p01, p12, t);
    dst[3] = p12;
    dst[4] = src[2];
}

/// `SkChopQuadAtYExtrema` (axis 1) / `SkChopQuadAtXExtrema` (axis 0). Returns the number of
/// extra quads (0 or 1); `dst` then holds 1 or 2 quads monotonic in that axis.
fn chopQuadAtExtrema(src: *const [3]P, dst: *[5]P, axis: usize) usize {
    const a = src[0][axis];
    var b = src[1][axis];
    const c = src[2][axis];
    const ab = a - b;
    var bc = b - c;
    if (ab < 0) bc = -bc;
    if (ab == 0 or bc < 0) {
        if (validUnitDivide(a - b, a - b - b + c)) |t| {
            chopQuadAt(src, dst, t);
            dst[1][axis] = dst[2][axis];
            dst[3][axis] = dst[2][axis];
            return 1;
        }
        // could not compute the split (underflow): force monotonic
        b = if (@abs(a - b) < @abs(b - c)) a else c;
    }
    dst[0] = src[0];
    dst[1] = src[1];
    dst[2] = src[2];
    dst[1][axis] = b;
    return 0;
}

fn chopCubicAt(src: *const [4]P, dst: *[7]P, t: f32) void {
    const ab = interp(src[0], src[1], t);
    const bc = interp(src[1], src[2], t);
    const cd = interp(src[2], src[3], t);
    const abc = interp(ab, bc, t);
    const bcd = interp(bc, cd, t);
    dst[0] = src[0];
    dst[1] = ab;
    dst[2] = abc;
    dst[3] = interp(abc, bcd, t);
    dst[4] = bcd;
    dst[5] = cd;
    dst[6] = src[3];
}

/// `SkChopCubicAtYExtrema` / `SkChopCubicAtXExtrema`. Returns the number of extra cubics (0..2).
fn chopCubicAtExtrema(src: *const [4]P, dst: *[10]P, axis: usize) usize {
    var ts: [2]f32 = undefined;
    const roots = findCubicExtrema(src[0][axis], src[1][axis], src[2][axis], src[3][axis], &ts);
    if (roots == 0) {
        dst[0..4].* = src.*;
        return 0;
    }
    var cur: [4]P = src.*;
    var t = ts[0];
    var off: usize = 0;
    var i: usize = 0;
    while (i < roots) : (i += 1) {
        var tmp: [7]P = undefined;
        chopCubicAt(&cur, &tmp, t);
        dst[off..][0..7].* = tmp;
        if (i == roots - 1) break;
        off += 3;
        cur = dst[off..][0..4].*;
        if (validUnitDivide(ts[i + 1] - ts[i], 1.0 - ts[i])) |nt| {
            t = nt;
        } else {
            // the renormalised t is out of range: degenerate last cubic
            dst[off + 4] = cur[3];
            dst[off + 5] = cur[3];
            dst[off + 6] = cur[3];
            break;
        }
    }
    // make the extrema flat
    dst[2][axis] = dst[3][axis];
    dst[4][axis] = dst[3][axis];
    if (roots == 2) {
        dst[5][axis] = dst[6][axis];
        dst[7][axis] = dst[6][axis];
    }
    return roots;
}

// ---- bounds (tiny-skia `Path::bounds` / `Path::compute_tight_bounds`) ----------------------

pub const Bounds = struct {
    /// Control-point bounds.
    cmin: P = .{ std.math.floatMax(f32), std.math.floatMax(f32) },
    cmax: P = .{ -std.math.floatMax(f32), -std.math.floatMax(f32) },
    /// Tight bounds (curve extrema).
    tmin: P = .{ std.math.floatMax(f32), std.math.floatMax(f32) },
    tmax: P = .{ -std.math.floatMax(f32), -std.math.floatMax(f32) },

    fn tight(b: *Bounds, p: P) void {
        for (0..2) |k| {
            b.tmin[k] = @min(b.tmin[k], p[k]);
            b.tmax[k] = @max(b.tmax[k], p[k]);
        }
    }

    fn control(b: *Bounds, p: P) void {
        for (0..2) |k| {
            b.cmin[k] = @min(b.cmin[k], p[k]);
            b.cmax[k] = @max(b.cmax[k], p[k]);
        }
    }

    /// An on-curve point (move / line end).
    pub fn point(b: *Bounds, p: P) void {
        b.control(p);
        b.tight(p);
    }

    pub fn quad(b: *Bounds, p: *const [3]P) void {
        b.control(p[1]);
        b.point(p[2]);
        for (0..2) |k| {
            if (validUnitDivide(p[0][k] - p[1][k], p[0][k] - p[1][k] - p[1][k] + p[2][k])) |t| {
                // QuadCoeff: (A t + B) t + C
                var q: P = undefined;
                for (0..2) |j| {
                    const bb = 2 * (p[1][j] - p[0][j]);
                    const aa = p[2][j] - 2 * p[1][j] + p[0][j];
                    q[j] = (aa * t + bb) * t + p[0][j];
                }
                b.tight(q);
            }
        }
    }

    pub fn cubic(b: *Bounds, p: *const [4]P) void {
        b.control(p[1]);
        b.control(p[2]);
        b.point(p[3]);
        for (0..2) |k| {
            var ts: [2]f32 = undefined;
            const n = findCubicExtrema(p[0][k], p[1][k], p[2][k], p[3][k], &ts);
            for (ts[0..n]) |t| {
                // CubicCoeff: ((A t + B) t + C) t + D
                var q: P = undefined;
                for (0..2) |j| {
                    const aa = p[3][j] + 3 * (p[1][j] - p[2][j]) - p[0][j];
                    const bb = 3 * (p[2][j] - 2 * p[1][j] + p[0][j]);
                    const cc = 3 * (p[1][j] - p[0][j]);
                    q[j] = ((aa * t + bb) * t + cc) * t + p[0][j];
                }
                b.tight(q);
            }
        }
    }
};

// ---- edge builder (`SkEdgeBuilder` / tiny-skia `BasicEdgeBuilder`) -------------------------

pub const Builder = struct {
    gpa: std.mem.Allocator,
    edges: *std.ArrayList(Edge),
    /// Mimic the clipped build path (`SkEdgeClipper`): curves are also chopped at their X
    /// extrema. tiny-skia takes it when the control-point bounds stick out of the mask.
    chop_x: bool = false,

    pub fn line(b: *Builder, p0: P, p1: P) !void {
        var x0 = toFDot6(p0[0]);
        var y0 = toFDot6(p0[1]);
        var x1 = toFDot6(p1[0]);
        var y1 = toFDot6(p1[1]);
        var e: Edge = .{};
        if (y0 > y1) {
            std.mem.swap(i32, &x0, &x1);
            std.mem.swap(i32, &y0, &y1);
            e.winding = -1;
        }
        if (!e.setLine(x0, y0, x1, y1, true)) return;
        try b.edges.append(b.gpa, e);
    }

    pub fn quad(b: *Builder, p: *const [3]P) !void {
        var my: [5]P = undefined;
        const n = chopQuadAtExtrema(p, &my, 1);
        var i: usize = 0;
        while (i <= n) : (i += 1) {
            const seg = my[i * 2 ..][0..3];
            if (b.chop_x) {
                var mx: [5]P = undefined;
                const m = chopQuadAtExtrema(seg, &mx, 0);
                var j: usize = 0;
                while (j <= m) : (j += 1) try b.monoQuad(mx[j * 2 ..][0..3]);
            } else try b.monoQuad(seg);
        }
    }

    pub fn cubic(b: *Builder, p: *const [4]P) !void {
        var my: [10]P = undefined;
        const n = chopCubicAtExtrema(p, &my, 1);
        var i: usize = 0;
        while (i <= n) : (i += 1) {
            const seg = my[i * 3 ..][0..4];
            if (b.chop_x) {
                var mx: [10]P = undefined;
                const m = chopCubicAtExtrema(seg, &mx, 0);
                var j: usize = 0;
                while (j <= m) : (j += 1) try b.monoCubic(mx[j * 3 ..][0..4]);
            } else try b.monoCubic(seg);
        }
    }

    /// `SkQuadraticEdge::setQuadratic`.
    fn monoQuad(b: *Builder, p: *const [3]P) !void {
        var x0 = toFDot6(p[0][0]);
        var y0 = toFDot6(p[0][1]);
        const x1 = toFDot6(p[1][0]);
        const y1 = toFDot6(p[1][1]);
        var x2 = toFDot6(p[2][0]);
        var y2 = toFDot6(p[2][1]);
        var e: Edge = .{ .kind = .quad };
        if (y0 > y2) {
            std.mem.swap(i32, &x0, &x2);
            std.mem.swap(i32, &y0, &y2);
            e.winding = -1;
        }
        const top = (y0 +% 32) >> 6;
        const bot = (y2 +% 32) >> 6;
        if (top == bot) return;
        var shift: i32 = diffToShift(((x1 << 1) -% x0 -% x2) >> 2, ((y1 << 1) -% y0 -% y2) >> 2);
        // need at least 1 subdivision for the bias trick
        if (shift == 0) shift = 1 else if (shift > MAX_COEFF_SHIFT) shift = MAX_COEFF_SHIFT;
        const sh: u5 = @intCast(shift);
        e.curve_count = @intCast(@as(i32, 1) << sh);
        e.curve_shift = @intCast(shift - 1);
        // A and B hold half of the real coefficients
        var a = (x0 -% x1 -% x1 +% x2) << 9;
        var bb = (x1 -% x0) << 10;
        e.c[0] = x0 << 10;
        e.c[2] = bb +% (a >> sh);
        e.c[4] = a >> (sh - 1);
        a = (y0 -% y1 -% y1 +% y2) << 9;
        bb = (y1 -% y0) << 10;
        e.c[1] = y0 << 10;
        e.c[3] = bb +% (a >> sh);
        e.c[5] = a >> (sh - 1);
        e.c[6] = x2 << 10;
        e.c[7] = y2 << 10;
        if (!e.updateQuad()) return;
        try b.edges.append(b.gpa, e);
    }

    /// `SkCubicEdge::setCubic`.
    fn monoCubic(b: *Builder, p: *const [4]P) !void {
        // v[axis][point], 26.6
        var v: [2][4]i32 = undefined;
        for (0..4) |i| {
            v[0][i] = toFDot6(p[i][0]);
            v[1][i] = toFDot6(p[i][1]);
        }
        var e: Edge = .{ .kind = .cubic };
        if (v[1][0] > v[1][3]) {
            for (&v) |*a| {
                std.mem.swap(i32, &a[0], &a[3]);
                std.mem.swap(i32, &a[1], &a[2]);
            }
            e.winding = -1;
        }
        const top = (v[1][0] +% 32) >> 6;
        const bot = (v[1][3] +% 32) >> 6;
        if (top == bot) return;
        // steps from the two off-curve points ("+ 1 by observation")
        var shift: i32 = diffToShift(cubicDeltaFromLine(v[0][0], v[0][1], v[0][2], v[0][3]), cubicDeltaFromLine(v[1][0], v[1][1], v[1][2], v[1][3])) + 1;
        if (shift > MAX_COEFF_SHIFT) shift = MAX_COEFF_SHIFT;
        // the data is shifted down by 8 (AA): the safest up-shift with the 3x coefficients is 6
        var up_shift: i32 = 6;
        var down_shift: i32 = shift + up_shift - 10;
        if (down_shift < 0) {
            down_shift = 0;
            up_shift = 10 - shift;
        }
        const sh: u5 = @intCast(shift);
        const up: u5 = @intCast(up_shift);
        e.curve_count = @intCast(-(@as(i32, 1) << sh));
        e.curve_shift = @intCast(shift);
        e.dshift = @intCast(down_shift);
        for (0..2) |k| {
            const a = &v[k];
            const bq = (3 *% (a[1] -% a[0])) << up;
            const cq = (3 *% (a[0] -% a[1] -% a[1] +% a[2])) << up;
            const dq = (a[3] +% 3 *% (a[1] -% a[2]) -% a[0]) << up;
            e.c[k] = a[0] << 10;
            e.c[2 + k] = bq +% (cq >> sh) +% (dq >> (2 * sh)); // biased by shift
            e.c[4 + k] = 2 *% cq +% ((3 *% dq) >> (sh - 1)); // biased by 2*shift
            e.c[6 + k] = (3 *% dq) >> (sh - 1); // biased by 2*shift
            e.c[8 + k] = a[3] << 10;
        }
        if (!e.updateCubic()) return;
        try b.edges.append(b.gpa, e);
    }
};

test "line edge setup" {
    var list: std.ArrayList(Edge) = .empty;
    defer list.deinit(std.testing.allocator);
    var b: Builder = .{ .gpa = std.testing.allocator, .edges = &list };
    // vertical line at x = 1.5 from y = 0 to y = 2: 8 sub-scanlines, x = 6 sub-pixels
    try b.line(.{ 1.5, 0 }, .{ 1.5, 2 });
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    const e = list.items[0];
    try std.testing.expectEqual(@as(i32, 0), e.first_y);
    try std.testing.expectEqual(@as(i32, 7), e.last_y);
    try std.testing.expectEqual(@as(i32, 6 << 16), e.x);
    try std.testing.expectEqual(@as(i32, 0), e.dx);
    // upward line has winding -1; horizontal lines give no edge
    try b.line(.{ 0, 3 }, .{ 4, 1 });
    try std.testing.expectEqual(@as(i8, -1), list.items[1].winding);
    try b.line(.{ 0, 3 }, .{ 9, 3 });
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
}

test "curve edges cover their whole y range without gaps" {
    var list: std.ArrayList(Edge) = .empty;
    defer list.deinit(std.testing.allocator);
    var b: Builder = .{ .gpa = std.testing.allocator, .edges = &list };
    // a quad with a y extremum is split in two monotonic edges
    try b.quad(&.{ .{ 0, 0 }, .{ 10, 20 }, .{ 20, 0 } });
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try b.cubic(&.{ .{ 0, 0 }, .{ 0, 30 }, .{ 40, 30 }, .{ 40, 60.3 } });
    for (list.items) |*e| {
        const first = e.first_y;
        var y = e.first_y;
        var last = e.last_y;
        var guard: usize = 0;
        while (guard < 200) : (guard += 1) {
            try std.testing.expect(e.last_y >= e.first_y);
            try std.testing.expectEqual(y, e.first_y);
            y = e.last_y + 1;
            last = e.last_y;
            if (!e.update()) break;
        }
        try std.testing.expect(guard < 200);
        try std.testing.expect(last > first);
    }
    // the cubic ends at round(60.3 * 4) = 241 sub-scanlines
    try std.testing.expectEqual(@as(i32, 240), list.items[list.items.len - 1].last_y);
}

test "degenerate and non-finite input does not trap" {
    var list: std.ArrayList(Edge) = .empty;
    defer list.deinit(std.testing.allocator);
    var b: Builder = .{ .gpa = std.testing.allocator, .edges = &list, .chop_x = true };
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    try b.line(.{ nan, 0 }, .{ inf, 5 });
    try b.quad(&.{ .{ 0, 0 }, .{ nan, 1e30 }, .{ -inf, 3 } });
    try b.cubic(&.{ .{ 1e9, -1e9 }, .{ 0, 0 }, .{ nan, nan }, .{ 4, 1e12 } });
    try b.cubic(&.{ .{ 1, 1 }, .{ 1, 1 }, .{ 1, 1 }, .{ 1, 1 } });
    for (list.items) |*e| {
        var guard: usize = 0;
        while (e.kind != .line and e.update() and guard < 300) guard += 1;
        try std.testing.expect(guard < 300);
    }
    var bd: Bounds = .{};
    bd.quad(&.{ .{ 0, 0 }, .{ nan, 1e30 }, .{ -inf, 3 } });
    bd = .{};
    bd.point(.{ 0, 0 });
    bd.cubic(&.{ .{ 0, 0 }, .{ 0, 10 }, .{ 10, 10 }, .{ 10, 0 } });
    try std.testing.expect(bd.tmax[1] > 7.4 and bd.tmax[1] < 7.6);
}
