//! Basic geometry / pixel types shared by the raster module.
const std = @import("std");
const builtin = @import("builtin");

comptime {
    // Pixels are accessed as packed little-endian u32 (r | g<<8 | b<<16 | a<<24).
    std.debug.assert(builtin.cpu.arch.endian() == .little);
}

pub const Point = struct { x: f32, y: f32 };

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

/// Integer pixel rectangle. `w == 0 or h == 0` means empty.
pub const IRect = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,

    pub const empty: IRect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

    pub fn isEmpty(self: IRect) bool {
        return self.w == 0 or self.h == 0;
    }

    /// Exclusive right edge as i64 (never overflows).
    pub fn right(self: IRect) i64 {
        return @as(i64, self.x) + self.w;
    }

    /// Exclusive bottom edge as i64 (never overflows).
    pub fn bottom(self: IRect) i64 {
        return @as(i64, self.y) + self.h;
    }

    pub fn intersect(self: IRect, other: IRect) IRect {
        const x0 = @max(self.x, other.x);
        const y0 = @max(self.y, other.y);
        const x1 = @min(self.right(), other.right());
        const y1 = @min(self.bottom(), other.bottom());
        if (x1 <= x0 or y1 <= y0) return empty;
        return .{ .x = x0, .y = y0, .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
    }

    /// Grow by `n` pixels on every side (saturating).
    pub fn expand(self: IRect, n: u32) IRect {
        if (self.isEmpty()) return empty;
        const ni: i64 = n;
        const x0 = @max(@as(i64, self.x) - ni, std.math.minInt(i32));
        const y0 = @max(@as(i64, self.y) - ni, std.math.minInt(i32));
        const x1 = @min(self.right() + ni, std.math.maxInt(i32));
        const y1 = @min(self.bottom() + ni, std.math.maxInt(i32));
        return .{ .x = @intCast(x0), .y = @intCast(y0), .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
    }

    pub fn contains(self: IRect, px: i32, py: i32) bool {
        return px >= self.x and py >= self.y and px < self.right() and py < self.bottom();
    }
};

/// 2D affine transform, same layout as CSS `matrix(a, b, c, d, e, f)`:
/// `x' = a*x + c*y + e ; y' = b*x + d*y + f`.
pub const Affine = struct {
    a: f32 = 1,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 1,
    e: f32 = 0,
    f: f32 = 0,

    pub const identity: Affine = .{};

    pub fn translate(tx: f32, ty: f32) Affine {
        return .{ .e = tx, .f = ty };
    }

    pub fn scale(sx: f32, sy: f32) Affine {
        return .{ .a = sx, .d = sy };
    }

    /// Clockwise (in y-down device space) rotation by `rad`, like CSS `rotate()`.
    pub fn rotate(rad: f32) Affine {
        const sc = sinCos(rad);
        const s = sc[0];
        const co = sc[1];
        return .{ .a = co, .b = s, .c = -s, .d = co };
    }

    /// CSS `skew(ax, ay)` (angles in radians).
    pub fn skew(ax: f32, ay: f32) Affine {
        const sy = sinCos(ay);
        const sx = sinCos(ax);
        return .{ .b = sy[0] / sy[1], .c = sx[0] / sx[1] };
    }

    /// Matrix product `self * other`, i.e. document order of a CSS transform list:
    /// `A.mul(B).apply(p) == A.apply(B.apply(p))` (`other` is applied to the point first).
    /// `transform: translate(..) rotate(..)` == `translate(..).mul(rotate(..))`.
    pub fn mul(self: Affine, o: Affine) Affine {
        return .{
            .a = self.a * o.a + self.c * o.b,
            .b = self.b * o.a + self.d * o.b,
            .c = self.a * o.c + self.c * o.d,
            .d = self.b * o.c + self.d * o.d,
            .e = self.a * o.e + self.c * o.f + self.e,
            .f = self.b * o.e + self.d * o.f + self.f,
        };
    }

    /// Returns null when the matrix is singular or not finite.
    pub fn invert(self: Affine) ?Affine {
        const det = self.a * self.d - self.b * self.c;
        if (!std.math.isFinite(det) or det == 0) return null;
        const inv = 1.0 / det;
        if (!std.math.isFinite(inv)) return null;
        const r: Affine = .{
            .a = self.d * inv,
            .b = -self.b * inv,
            .c = -self.c * inv,
            .d = self.a * inv,
            .e = (self.c * self.f - self.d * self.e) * inv,
            .f = (self.b * self.e - self.a * self.f) * inv,
        };
        if (!r.isFinite()) return null;
        return r;
    }

    pub fn apply(self: Affine, p: Point) Point {
        return .{ .x = self.a * p.x + self.c * p.y + self.e, .y = self.b * p.x + self.d * p.y + self.f };
    }

    pub fn isFinite(self: Affine) bool {
        // sum is finite iff every term is finite (no inf/nan); avoids six branches.
        return std.math.isFinite(self.a * 0 + self.b * 0 + self.c * 0 + self.d * 0 + self.e * 0 + self.f * 0);
    }

    pub fn isTranslateOnly(self: Affine) bool {
        return self.a == 1 and self.b == 0 and self.c == 0 and self.d == 1;
    }

    pub fn isIdentity(self: Affine) bool {
        return self.isTranslateOnly() and self.e == 0 and self.f == 0;
    }
};

/// `v / 255` for a product of two bytes, as takumi's `div_255` (`style/math.rs`, used by all of its
/// compositing: `mul_div_255`): `(v + 128 + (v >> 8)) >> 8`. Rounds to nearest except for 126 of the
/// 65536 byte products, where it is one off the exact rounding `((v + 128) + ((v + 128) >> 8)) >> 8`
/// (e.g. 236 * 208 -> 192, exact 193). Those cases are visible as 1-level differences on AA edges, so
/// every byte product of the compositor goes through this.
pub inline fn div255(v: u32) u32 {
    return (v + 128 + (v >> 8)) >> 8;
}

/// Scales all four channels of a packed pixel by `c / 255` (`div255` per channel).
pub inline fn scalePx(p: u32, c: u32) u32 {
    var rb = (p & 0x00FF00FF) * c;
    rb = ((rb + 0x00800080 + ((rb >> 8) & 0x00FF00FF)) >> 8) & 0x00FF00FF;
    var ga = ((p >> 8) & 0x00FF00FF) * c;
    ga = (ga + 0x00800080 + ((ga >> 8) & 0x00FF00FF)) & 0xFF00FF00;
    return rb | ga;
}

/// Source-over of premultiplied `s` on premultiplied `d`.
pub inline fn over(s: u32, d: u32) u32 {
    return s +% scalePx(d, 255 - (s >> 24));
}

/// `d[0..n] = p` with explicit 16-byte stores (ReleaseSmall keeps a plain u32 loop scalar).
/// Full-canvas fills are memory-bound (~0.25 ms for 1200x630 in V8); replicating a chunk with
/// `memory.copy` was measured and is not faster.
pub fn fillPixels(d: [*]align(1) u32, n: usize, p: u32) void {
    const V4 = @Vector(4, u32);
    const pv: V4 = @splat(p);
    var i: usize = 0;
    while (i + 16 <= n) : (i += 16) {
        inline for (0..4) |k| @as(*align(1) [4]u32, @ptrCast(d + i + k * 4)).* = pv;
    }
    while (i + 4 <= n) : (i += 4) @as(*align(1) [4]u32, @ptrCast(d + i)).* = pv;
    while (i < n) : (i += 1) d[i] = p;
}

/// STRAIGHT (non-premultiplied) sRGB colour.
pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const white: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Straight packed value (r | g<<8 | b<<16 | a<<24).
    pub fn bits(self: Color) u32 {
        return @as(u32, self.r) | (@as(u32, self.g) << 8) | (@as(u32, self.b) << 16) | (@as(u32, self.a) << 24);
    }

    /// Premultiplied packed pixel (r | g<<8 | b<<16 | a<<24).
    pub fn premul(self: Color) u32 {
        const a: u32 = self.a;
        if (a == 255) return self.bits();
        return div255(@as(u32, self.r) * a) | (div255(@as(u32, self.g) * a) << 8) |
            (div255(@as(u32, self.b) * a) << 16) | (a << 24);
    }
};

/// PREMULTIPLIED RGBA8 surface, row-major, stride = width*4.
pub const Pixmap = struct {
    width: u32,
    height: u32,
    data: []u8,

    pub const empty: Pixmap = .{ .width = 0, .height = 0, .data = &.{} };

    /// Zero-initialised (transparent). Zero-sized pixmaps are valid.
    pub fn init(alloc: std.mem.Allocator, w: u32, h: u32) !Pixmap {
        const n = byteLen(w, h) orelse return error.OutOfMemory;
        const data = try alloc.alloc(u8, n);
        @memset(data, 0);
        return .{ .width = w, .height = h, .data = data };
    }

    pub fn deinit(self: *Pixmap, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
        self.* = empty;
    }

    pub fn byteLen(w: u32, h: u32) ?usize {
        const n = @as(u64, w) * @as(u64, h) * 4;
        if (n > std.math.maxInt(usize) / 2) return null;
        return @intCast(n);
    }

    /// True when `data` is large enough for width*height pixels.
    pub fn isValid(self: *const Pixmap) bool {
        const n = byteLen(self.width, self.height) orelse return false;
        return self.data.len >= n;
    }

    pub fn bounds(self: *const Pixmap) IRect {
        return .{ .x = 0, .y = 0, .w = self.width, .h = self.height };
    }

    /// Packed-pixel view of the data.
    pub fn pixels(self: *const Pixmap) []align(1) u32 {
        return @as([*]align(1) u32, @ptrCast(self.data.ptr))[0 .. self.data.len / 4];
    }

    /// Fills the whole pixmap with `color` (replace, not blend).
    pub fn clear(self: *Pixmap, color: Color) void {
        const px = self.pixels();
        fillPixels(px.ptr, px.len, color.premul());
    }

    /// Premultiplied pixel at (x, y); caller guarantees in-bounds.
    pub fn pixel(self: *const Pixmap, x: u32, y: u32) [4]u8 {
        const i = (@as(usize, y) * self.width + x) * 4;
        return self.data[i..][0..4].*;
    }

    /// In-place conversion to straight alpha, correctly rounded.
    pub fn toStraightAlpha(self: *Pixmap) void {
        var i: usize = 0;
        const d = self.data;
        while (i + 4 <= d.len) : (i += 4) {
            const a: u32 = d[i + 3];
            if (a == 255) continue;
            if (a == 0) {
                d[i] = 0;
                d[i + 1] = 0;
                d[i + 2] = 0;
                continue;
            }
            inline for (0..3) |k| {
                // same integer formula as takumi's final demultiply
                const v = (@as(u32, d[i + k]) * 510 + a) / (2 * a);
                d[i + k] = @intCast(@min(v, 255));
            }
        }
    }
};

/// A8 coverage mask. `data.len == bounds.w * bounds.h`, row-major. Empty bounds allowed.
pub const Mask = struct {
    bounds: IRect,
    data: []u8,

    pub const empty: Mask = .{ .bounds = IRect.empty, .data = &.{} };

    pub fn init(alloc: std.mem.Allocator, bounds: IRect) !Mask {
        if (bounds.isEmpty()) return empty;
        const n = @as(u64, bounds.w) * bounds.h;
        if (n > std.math.maxInt(usize) / 2) return error.OutOfMemory;
        const data = try alloc.alloc(u8, @intCast(n));
        @memset(data, 0);
        return .{ .bounds = bounds, .data = data };
    }

    pub fn deinit(self: *Mask, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
        self.* = empty;
    }

    /// Coverage at device pixel (x, y); 0 outside bounds.
    pub fn at(self: *const Mask, x: i32, y: i32) u8 {
        if (!self.bounds.contains(x, y)) return 0;
        const ix: usize = @intCast(@as(i64, x) - self.bounds.x);
        const iy: usize = @intCast(@as(i64, y) - self.bounds.y);
        return self.data[iy * self.bounds.w + ix];
    }

    pub fn asClip(self: *const Mask) ClipMask {
        return .{ .bounds = self.bounds, .data = self.data };
    }
};

/// Per-pixel clip. Pixels outside `bounds` are fully clipped. When `data` is null every pixel
/// inside `bounds` is fully visible (cheap integer-rect clip); otherwise `data` is an A8 mask
/// laid out like `Mask.data`.
pub const ClipMask = struct {
    bounds: IRect,
    data: ?[]const u8 = null,

    pub fn fromRect(r: IRect) ClipMask {
        return .{ .bounds = r };
    }
};

pub const FillRule = enum { nonzero, evenodd };
pub const Filter = enum { nearest, bilinear };
pub const Extend = enum { pad, repeat, transparent };

pub const GradientStop = struct { offset: f32, color: Color };

pub const Paint = union(enum) {
    solid: Color,
    /// Device space end points of the CSS gradient line (offset 0 at p0, 1 at p1). Sampling
    /// follows takumi: nearest LUT entry at the pixel centre, positions clamped to the line.
    linear: struct { p0: Point, p1: Point, stops: []const GradientStop, repeating: bool = false },
    /// t = |((p - center) / (rx, ry))|. Device space unless `transform` (device -> gradient space) is given.
    radial: struct {
        center: Point,
        rx: f32,
        ry: f32,
        stops: []const GradientStop,
        repeating: bool = false,
        transform: ?Affine = null,
    },
    /// CSS conic-gradient: 0 = up, clockwise; stop offsets are fractions of a turn.
    /// `max_radius` (optional) = distance in px from `center` to the farthest corner of the
    /// gradient tile; it only selects the LUT resolution (takumi: `ceil(max_radius * TAU) + 1`
    /// visible samples). 0 = assume 256 px.
    conic: struct {
        center: Point,
        start_angle: f32,
        stops: []const GradientStop,
        repeating: bool = false,
        max_radius: f32 = 0,
    },
    image: struct {
        pixmap: *const Pixmap,
        /// device -> image pixel space
        transform: Affine,
        filter: Filter = .bilinear,
        extend: Extend = .pad,
        opacity: f32 = 1,
    },
};

/// NaN-safe clamp (NaN -> lo).
pub inline fn clampF(v: f32, lo: f32, hi: f32) f32 {
    return if (!(v > lo)) lo else if (v > hi) hi else v;
}

/// NaN/inf-safe float -> i32 with clamping to [lo, hi].
pub inline fn toIntClamped(v: f32, lo: i32, hi: i32) i32 {
    const c = clampF(v, @floatFromInt(lo), @floatFromInt(hi));
    const i: i32 = @intFromFloat(c);
    return @min(@max(i, lo), hi);
}

/// usize loop index -> f32 through i32 (a u64 -> f32 conversion defeats SIMD on x86-64).
pub inline fn fi32(i: usize) f32 {
    return @floatFromInt(@as(i32, @intCast(i)));
}

/// Natural SIMD lane count for 32-bit lanes on the target (4 on wasm simd128, 8 with AVX2).
/// Explicit vector loops use it so the wasm build does not pay for double-width code.
pub const LANES: comptime_int = @max(4, @min(8, std.simd.suggestVectorLength(u32) orelse 4));

/// `{ sin(rad), cos(rad) }`. Small self-contained implementation (f64 Taylor after reduction to
/// [-pi/4, pi/4]; abs error < 1e-7 for |rad| < 1e5) so the wasm does not link libm's trig and
/// its ~8 KB of argument-reduction tables. Non-finite input gives NaN.
pub fn sinCos(rad: f32) [2]f32 {
    if (!std.math.isFinite(rad)) return .{ std.math.nan(f32), std.math.nan(f32) };
    const x: f64 = rad;
    const q = @floor(x * (2.0 / std.math.pi) + 0.5);
    const r = x - q * (std.math.pi / 2.0);
    const r2 = r * r;
    const s = r * (1.0 + r2 * (-1.0 / 6.0 + r2 * (1.0 / 120.0 + r2 * (-1.0 / 5040.0 + r2 * (1.0 / 362880.0)))));
    const c = 1.0 + r2 * (-0.5 + r2 * (1.0 / 24.0 + r2 * (-1.0 / 720.0 + r2 * (1.0 / 40320.0 + r2 * (-1.0 / 3628800.0)))));
    const quadrant: u32 = @intFromFloat(q - 4.0 * @floor(q * 0.25)); // 0..3
    const sf: f32 = @floatCast(s);
    const cf: f32 = @floatCast(c);
    return switch (quadrant & 3) {
        0 => .{ sf, cf },
        1 => .{ cf, -sf },
        2 => .{ -sf, -cf },
        else => .{ -cf, sf },
    };
}

/// `exp(-t)` for t >= 0 (rel. error ~1e-9); avoids libm's exp. Returns 0 for huge / NaN t.
pub fn expNeg(t: f32) f32 {
    if (!(t >= 0)) return 1;
    if (!(t < 100)) return 0;
    const x: f64 = t;
    const k = @floor(x * (1.0 / std.math.ln2));
    const r = x - k * std.math.ln2; // [0, ln2)
    // exp(-r), Taylor to r^11
    var term: f64 = 1;
    var sum: f64 = 1;
    var i: u32 = 1;
    while (i <= 11) : (i += 1) {
        term *= -r / @as(f64, @floatFromInt(i));
        sum += term;
    }
    var n: u32 = @intFromFloat(k);
    while (n > 0) : (n -= 1) sum *= 0.5;
    return @floatCast(sum);
}
