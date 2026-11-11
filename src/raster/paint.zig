//! Paint evaluation ("shaders") and source-over span compositing.
//!
//! All maths is premultiplied sRGB u8 with exact div-255 rounding:
//! `src = mul255(paint, coverage); dst = src + mul255(dst, 255 - src.a)`.
//!
//! Gradients follow takumi's sampling rule so results are byte-comparable: stops are lerped in
//! premultiplied u8 (`round`), baked into a LUT with an entry every half pixel of the gradient
//! axis (stop positions snapped onto entries), and each pixel picks the NEAREST entry for its
//! centre `(x + .5, y + .5)`.
const std = @import("std");
const types = @import("types.zig");
const Point = types.Point;
const Rect = types.Rect;
const IRect = types.IRect;
const Affine = types.Affine;
const Color = types.Color;
const Pixmap = types.Pixmap;
const Mask = types.Mask;
const ClipMask = types.ClipMask;
const Paint = types.Paint;
const GradientStop = types.GradientStop;
const Filter = types.Filter;
const Extend = types.Extend;
const clampF = types.clampF;
const scalePx = types.scalePx;
const div255 = types.div255;

pub const LUT_MAX = 8193;
/// Span chunk size (stack buffers).
pub const CH = 64;
const EPS: f32 = std.math.floatEps(f32);
const TAU: f32 = 6.283185307179586;
/// Stop snapping needs a per-stop index; gradients with more stops skip the snapping step.
const MAX_SNAP_STOPS = 64;

pub const PxPtr = [*]align(1) u32;
pub const ConstPxPtr = [*]align(1) const u32;

/// Widest fill (in device columns) served by the image row cache.
pub const ROW_CACHE_W = 2048;

/// Scratch for axis-aligned bilinear image fills (~48 KB, lives on the stack of the fill
/// function; only touched when `Shader.attachCache` enables it).
pub const RowCache = struct {
    x0: i32,
    n: u32,
    src_y: [2]i32,
    ix: [ROW_CACHE_W]u32,
    ix1: [ROW_CACHE_W]u32,
    fx: [ROW_CACHE_W]u16,
    /// horizontally lerped source rows, 4 x u16 per column (value * 256)
    rows: [2][ROW_CACHE_W * 4]u16,
};

const Kind = enum { none, solid, linear, radial, conic, image };

/// A paint prepared for span evaluation. ~33 KB (gradient LUT); lives on the caller's stack.
pub const Shader = struct {
    kind: Kind,
    is_opaque: bool,
    /// solid colour (premultiplied)
    color: u32,
    /// extra opacity 0..255 folded into coverage (image paints)
    alpha: u32,
    // gradient LUT mapping
    lut_len: u32,
    scale: f32,
    length: f32,
    rep: bool,
    rep_start: f32,
    rep_period: f32,
    // linear
    gx: f32,
    gy: f32,
    gb: f32,
    /// radial: device -> gradient space; image: device -> image pixel space
    m: Affine,
    has_m: bool,
    cx: f32,
    cy: f32,
    inv_rx: f32,
    inv_ry: f32,
    radius_scale: f32,
    start_turns: f32,
    pm: *const Pixmap,
    cache: ?*RowCache,
    filter: Filter,
    extend: Extend,
    lut: [LUT_MAX]u32,

    fn setSolid(self: *Shader, px: u32) void {
        self.color = px;
        self.is_opaque = (px >> 24) == 255;
        self.kind = if ((px >> 24) == 0) .none else .solid;
    }

    pub fn init(self: *Shader, paint: *const Paint) void {
        self.kind = .none;
        self.is_opaque = false;
        self.color = 0;
        self.alpha = 255;
        self.lut_len = 0;
        self.scale = 0;
        self.length = 0;
        self.rep = false;
        self.rep_start = 0;
        self.rep_period = 0;
        self.has_m = false;
        self.cache = null;
        switch (paint.*) {
            .solid => |c| self.setSolid(c.premul()),
            .linear => |g| {
                const dx = g.p1.x - g.p0.x;
                const dy = g.p1.y - g.p0.y;
                const len = @sqrt(dx * dx + dy * dy);
                if (!std.math.isFinite(len) or !std.math.isFinite(g.p0.x * 0 + g.p0.y * 0)) return;
                if (len > 0) {
                    self.gx = dx / len;
                    self.gy = dy / len;
                } else {
                    self.gx = 1;
                    self.gy = 0;
                }
                self.gb = -(g.p0.x * self.gx + g.p0.y * self.gy);
                if (!self.buildLut(g.stops, len, null, g.repeating)) return;
                self.kind = .linear;
            },
            .radial => |g| {
                const rx = clampF(g.rx, 1e-6, 1e9);
                const ry = clampF(g.ry, 1e-6, 1e9);
                if (!std.math.isFinite(g.center.x * 0 + g.center.y * 0)) return;
                if (g.transform) |t| {
                    if (!t.isFinite()) return;
                    self.m = t;
                    self.has_m = true;
                }
                self.cx = g.center.x;
                self.cy = g.center.y;
                self.inv_rx = 1.0 / rx;
                self.inv_ry = 1.0 / ry;
                self.radius_scale = @max(rx, ry);
                const vis = halfPixelSamples(@ceil(self.radius_scale));
                if (!self.buildLut(g.stops, self.radius_scale, vis, g.repeating)) return;
                self.kind = .radial;
            },
            .conic => |g| {
                if (!std.math.isFinite(g.center.x * 0 + g.center.y * 0 + g.start_angle * 0)) return;
                self.cx = g.center.x;
                self.cy = g.center.y;
                const turns = g.start_angle / TAU;
                self.start_turns = turns - @floor(turns);
                const r = if (g.max_radius > 0) g.max_radius else 256;
                const vis: u32 = @intFromFloat(clampF(@ceil(r * TAU), 0, 1e6) + 1);
                if (!self.buildLut(g.stops, 360, vis, g.repeating)) return;
                // non-repeating conic maps a full turn onto lut_len (floor), not lut_len - 1
                if (!self.rep) self.scale = @floatFromInt(self.lut_len);
                self.kind = .conic;
            },
            .image => |im| {
                const pm = im.pixmap;
                if (!pm.isValid() or pm.width == 0 or pm.height == 0) return;
                if (pm.width > (1 << 24) or pm.height > (1 << 24)) return;
                if (!im.transform.isFinite()) return;
                const a: u32 = @intFromFloat(clampF(im.opacity, 0, 1) * 255 + 0.5);
                if (a == 0) return;
                self.alpha = a;
                self.pm = pm;
                self.m = im.transform;
                self.filter = im.filter;
                self.extend = im.extend;
                self.kind = .image;
            },
        }
    }

    // ---- gradient LUT (port of takumi gradient_utils.rs) --------------------------------

    fn halfPixelSamples(pixels: f32) u32 {
        const p: u32 = @intFromFloat(clampF(pixels, 0, 1e6));
        return p * 2 + 1;
    }

    /// Builds the LUT for stops at `offset * axis_len` along an axis of `axis_len` units.
    /// `visible` = number of visible samples (null: one per half unit of the LUT length).
    /// Leaves `kind == .none` for a real gradient; collapses to `.solid` for <= 1 colour.
    fn buildLut(self: *Shader, stops_in: []const GradientStop, axis_len: f32, visible: ?u32, repeating: bool) bool {
        var stops = stops_in;
        if (stops.len == 0) return false;
        if (!std.math.isFinite(axis_len)) return false;
        for (stops) |s| {
            if (!std.math.isFinite(s.offset)) return false;
        }
        var shift: f32 = 0;
        var length = axis_len;
        if (repeating) {
            const first = stops[0].offset * axis_len;
            const period = @max(stops[stops.len - 1].offset * axis_len - first, 0);
            if (period > 1e-6) {
                shift = first;
                length = period;
                self.rep = true;
                self.rep_start = first;
                self.rep_period = period;
            } else {
                // coincident repeating stops: solid last colour
                stops = stops[stops.len - 1 ..];
            }
        }
        if (stops.len == 1) {
            self.setSolid(stops[0].color.premul());
            return false;
        }
        const n = stops.len;

        // LUT size
        var min_interval: f32 = std.math.inf(f32);
        {
            var prev = stops[0].offset * axis_len - shift;
            for (stops[1..]) |s| {
                const p = s.offset * axis_len - shift;
                const d = p - prev;
                if (d > EPS) min_interval = @min(min_interval, d);
                prev = p;
            }
        }
        const n_sat: u32 = @intCast(@min(n, LUT_MAX));
        var size: u32 = visible orelse halfPixelSamples(@ceil(length));
        var seg: u32 = n_sat + 1;
        if (std.math.isFinite(min_interval)) {
            seg += @intFromFloat(clampF(@ceil(length / min_interval), 0, LUT_MAX));
        }
        size = @max(@max(size, seg), @max(n_sat * 2, 2));
        size = @min(size, LUT_MAX);
        self.lut_len = size;
        self.length = length;
        const max_index: f32 = @floatFromInt(size - 1);
        self.scale = if (self.rep)
            max_index / self.rep_period
        else if (@abs(length) <= EPS) 0 else max_index / length;

        // samples
        const step = length / max_index;
        var left: usize = 0;
        var right: usize = 1;
        var right_pos = stops[1].offset * axis_len - shift;
        var left_pos = stops[0].offset * axis_len - shift;
        var left_px = stops[0].color.premul();
        var right_px = stops[1].color.premul();
        var all_opaque = true;
        for (stops) |s| {
            if (s.color.a != 255) all_opaque = false;
        }
        var i: u32 = 0;
        while (i < size) : (i += 1) {
            const pos = types.fi32(i) * step;
            while (right < n and right_pos <= pos) {
                left = right;
                left_pos = right_pos;
                left_px = right_px;
                right += 1;
                if (right < n) {
                    right_pos = stops[right].offset * axis_len - shift;
                    right_px = stops[right].color.premul();
                }
            }
            var px = left_px;
            if (right < n and stops[left].color.bits() != stops[right].color.bits()) {
                const den = right_pos - left_pos;
                const t = if (@abs(den) < EPS) 0 else clampF((pos - left_pos) / den, 0, 1);
                px = lerpPremul(left_px, right_px, t);
            }
            self.lut[i] = px;
        }

        // snap stop colours onto exact entries (assign_stop_sample_indices)
        if (n <= MAX_SNAP_STOPS) {
            var idx: [MAX_SNAP_STOPS]u32 = undefined;
            const mi: u32 = size - 1;
            var s: usize = 0;
            while (s < n) {
                const position = stops[s].offset * axis_len - shift;
                var preferred: u32 = 0;
                if (@abs(length) > EPS) {
                    preferred = @min(@as(u32, @intFromFloat(@round(clampF(position, 0, length) * max_index / length))), mi);
                }
                var run_end = s + 1;
                while (run_end < n and @abs(stops[run_end].offset * axis_len - shift - position) <= EPS) run_end += 1;
                const run_len: u32 = @intCast(run_end - s);
                const run_start = preferred -| (run_len - 1);
                var k: usize = s;
                while (k < run_end) : (k += 1) {
                    const logical = @min(run_start + @as(u32, @intCast(k - s)), mi);
                    const lower: u32 = @min(@as(u32, @intCast(k)), mi);
                    const upper: u32 = mi -| @as(u32, @intCast(n - 1 - k));
                    idx[k] = if (lower <= upper) @min(@max(logical, lower), upper) else logical;
                }
                s = run_end;
            }
            s = 1;
            while (s < n) : (s += 1) idx[s] = @min(@max(idx[s], idx[s - 1] + 1), mi);
            s = n - 1;
            while (s > 0) {
                s -= 1;
                idx[s] = @min(idx[s], idx[s + 1] -| 1);
            }
            for (stops, 0..) |st, k| self.lut[idx[k]] = st.color.premul();
        }
        self.is_opaque = all_opaque;
        return true;
    }

    /// takumi `interpolate_rgba_premultiplied`.
    fn lerpPremul(c1: u32, c2: u32, t: f32) u32 {
        if (t <= EPS) return c1;
        if (t >= 1.0 - EPS) return c2;
        const a: [4]u8 = @bitCast(c1);
        const b: [4]u8 = @bitCast(c2);
        var r: [4]u8 = undefined;
        for (0..4) |i| {
            const v = @as(f32, @floatFromInt(a[i])) * (1.0 - t) + @as(f32, @floatFromInt(b[i])) * t;
            r[i] = @intFromFloat(clampF(@round(v), 0, 255));
        }
        r[0] = @min(r[0], r[3]);
        r[1] = @min(r[1], r[3]);
        r[2] = @min(r[2], r[3]);
        return @bitCast(r);
    }

    /// LUT index for an axis position (linear / radial).
    inline fn lutIndex(self: *const Shader, pos: f32) u32 {
        var p: f32 = undefined;
        if (self.rep) {
            const a = pos - self.rep_start;
            p = clampF(a - @floor(a / self.rep_period) * self.rep_period, 0, self.rep_period);
        } else {
            p = clampF(pos, 0, self.length);
        }
        const i: u32 = @intFromFloat(p * self.scale + 0.5);
        return @min(i, self.lut_len - 1);
    }

    // ---- span evaluation ----------------------------------------------------------------

    /// Writes `n` premultiplied pixels for device pixels (x .. x+n, y).
    pub fn shade(self: *const Shader, x: i32, y: i32, out: PxPtr, n: usize) void {
        const yc: f32 = @as(f32, @floatFromInt(y)) + 0.5;
        switch (self.kind) {
            .none => @memset(out[0..n], 0),
            .solid => fillPixels(out, n, self.color),
            .linear => {
                if (self.gx == 0) {
                    fillPixels(out, n, self.lut[self.lutIndex(yc * self.gy + self.gb)]);
                    return;
                }
                self.shadeGradient(x, yc, out, n);
            },
            .radial, .conic => self.shadeGradient(x, yc, out, n),
            .image => self.shadeImage(x, yc, out, n),
        }
    }

    const GW = types.LANES;
    const VF = @Vector(GW, f32);
    const VI = @Vector(GW, i32);

    inline fn vsplat(v: f32) VF {
        return @splat(v);
    }

    /// NaN-safe clamp to [0, hi] (NaN -> 0).
    inline fn vclamp0(v: VF, hi: f32) VF {
        const h = vsplat(hi);
        // @select instead of @min: float vector @min lowers to per-lane fmin calls on wasm
        return @select(f32, v > vsplat(0), @select(f32, v < h, v, h), vsplat(0));
    }

    /// `v mod period` into [0, period] (NaN -> 0).
    inline fn vwrap(v: VF, period: f32) VF {
        const pv = vsplat(period);
        return vclamp0(v - @floor(v / pv) * pv, period);
    }

    /// Skia's `xy_to_unit_angle` polynomial (as used by takumi): angle of (x, y) in turns
    /// [0, 1), vectorised over y with a scalar x.
    inline fn unitAngleV(x: f32, y: VF) VF {
        const xa = vsplat(@abs(x));
        const ya = @abs(y);
        const mx = @select(f32, xa > ya, xa, ya);
        const mn = @select(f32, xa > ya, ya, xa);
        const slope = @select(f32, mx > vsplat(0), mn / mx, vsplat(0));
        const s = slope * slope;
        var phi = slope * (vsplat(1.5912117e-1) + s * (vsplat(-5.185397e-2) + s * (vsplat(2.476102e-2) + s * vsplat(-7.054738e-3))));
        phi = @select(f32, xa < ya, vsplat(0.25) - phi, phi);
        if (x < 0) phi = vsplat(0.5) - phi;
        phi = @select(f32, y < vsplat(0), vsplat(1.0) - phi, phi);
        // keep [0, 1); also maps NaN to 0
        return @select(f32, phi < vsplat(1.0), @select(f32, phi >= vsplat(0), phi, vsplat(0)), vsplat(0));
    }

    /// LUT indices are computed LANES pixels at a time (explicit SIMD, no gather), then looked up.
    fn shadeGradient(self: *const Shader, x: i32, yc: f32, out: PxPtr, n: usize) void {
        // the common case (plain linear) gets its own loop: ReleaseSmall does not unswitch
        if (self.kind == .linear and !self.rep) {
            self.gradSpan(true, x, yc, out, n);
        } else {
            self.gradSpan(false, x, yc, out, n);
        }
    }

    fn gradSpan(self: *const Shader, comptime plain_linear: bool, x: i32, yc: f32, out: PxPtr, n: usize) void {
        const kind: Kind = if (plain_linear) .linear else self.kind;
        const rep: bool = if (plain_linear) false else self.rep;
        var idx: [CH]u32 = undefined;
        const iota: VF = std.simd.iota(f32, GW);
        const mi: VI = @splat(@intCast(self.lut_len - 1));
        const sc = vsplat(self.scale);
        const half = vsplat(0.5);
        const lut: [*]const u32 = &self.lut;
        // loop-invariant operands
        const rep_start = self.rep_start;
        const rep_period = self.rep_period;
        const length = self.length;
        const cx = vsplat(self.cx);
        // linear: pos = xs * gx + c0
        const gx = vsplat(self.gx);
        const c0 = vsplat(yc * self.gy);
        const gb = vsplat(self.gb);
        // radial: u = xs * ua + ub, v = xs * va + vb (gradient space, relative to the centre)
        const ident = !self.has_m;
        const ua = vsplat((if (ident) 1 else self.m.a) * self.inv_rx);
        const ub = vsplat(((if (ident) 0 else self.m.c * yc + self.m.e) - self.cx) * self.inv_rx);
        const va = vsplat((if (ident) 0 else self.m.b) * self.inv_ry);
        const vb = vsplat(((if (ident) yc else self.m.d * yc + self.m.f) - self.cy) * self.inv_ry);
        const rs = vsplat(self.radius_scale);
        // conic
        const dy = yc - self.cy;
        const start_turns = vsplat(self.start_turns);
        const be: f32 = 0.001; // LUT_INDEX_BOUNDARY_EPSILON

        var off: usize = 0;
        while (off < n) : (off += CH) {
            const m = @min(CH, n - off);
            const xf: f32 = @as(f32, @floatFromInt(x +% @as(i32, @intCast(off)))) + 0.5;
            var k: usize = 0;
            while (k < m) : (k += GW) {
                const xs = vsplat(xf + types.fi32(k)) + iota;
                var smp: VF = undefined;
                if (kind == .conic) {
                    const dx = xs - cx;
                    var adj = unitAngleV(-dy, dx) - start_turns;
                    adj = @select(f32, adj < vsplat(0), adj + vsplat(1.0), adj);
                    if (rep) {
                        const sp = vwrap(adj * vsplat(360.0) - vsplat(rep_start), rep_period) * sc;
                        const fl = @floor(sp);
                        smp = @select(f32, sp - fl >= vsplat(0.5 - be), fl + vsplat(1.0), fl);
                    } else {
                        const sp = vclamp0(adj * sc, 1.0e6);
                        const nearest = @floor(sp + half);
                        smp = @select(f32, @abs(sp - nearest) <= vsplat(be), nearest, @floor(sp));
                    }
                    if (@abs(dy) <= EPS) {
                        // the centre pixel itself samples entry 0
                        smp = @select(f32, @abs(dx) <= vsplat(EPS), vsplat(0), smp);
                    }
                } else {
                    var pos: VF = undefined;
                    if (kind == .linear) {
                        pos = (xs * gx + c0) + gb;
                    } else {
                        const du = xs * ua + ub;
                        const dv = xs * va + vb;
                        pos = @sqrt(du * du + dv * dv) * rs;
                    }
                    const p = if (rep) vwrap(pos - vsplat(rep_start), rep_period) else vclamp0(pos, length);
                    smp = p * sc + half;
                }
                // smp is finite and >= 0 here. Float -> int goes through floor + the 2^23 mantissa
                // trick: a vector `@intFromFloat` (i32x4.trunc_sat_f32x4_s) is ~10x slower in V8.
                const fl = @floor(@select(f32, smp < vsplat(16384.0), smp, vsplat(16384.0)));
                const iv: VI = @as(VI, @bitCast(fl + vsplat(8388608.0))) & @as(VI, @splat(0x007FFFFF));
                idx[k..][0..GW].* = @bitCast(@min(iv, mi));
            }
            const o = out + off;
            for (0..m) |i| o[i] = lut[idx[i]];
        }
    }

    // ---- row cache for axis-aligned bilinear images -------------------------------------

    /// Enables the two-row cache when this paint is an axis-aligned, edge-clamped bilinear
    /// image and the fill touches at most `ROW_CACHE_W` columns starting at device x `x0`.
    /// Each source row is then lerped horizontally once and reused by every destination row
    /// that reads it (same integer maths as `bilerp`, so results are identical).
    pub fn attachCache(self: *Shader, cache: *RowCache, x0: i32, n: usize) void {
        if (self.kind != .image or self.filter != .bilinear or self.extend != .pad) return;
        if (self.m.b != 0 or self.m.c != 0 or n > ROW_CACHE_W or n < 8) return;
        const lastx: f32 = @floatFromInt(self.pm.width - 1);
        const wm1: u32 = self.pm.width - 1;
        const base = self.m.a * (@as(f32, @floatFromInt(x0)) + 0.5) + self.m.e;
        for (0..n) |i| {
            const c = clampF(base + types.fi32(i) * self.m.a - 0.5, 0, lastx);
            const ix: u32 = @intCast(@as(i32, @intFromFloat(c)));
            cache.ix[i] = ix;
            cache.ix1[i] = @min(ix + 1, wm1);
            cache.fx[i] = @intCast(@as(i32, @intFromFloat((c - @as(f32, @floatFromInt(ix))) * 256.0)));
        }
        cache.x0 = x0;
        cache.n = @intCast(n);
        cache.src_y = .{ -1, -1 };
        self.cache = cache;
    }

    /// Slot holding source row `index` lerped across the cached columns; never evicts `keep`.
    fn cacheRow(self: *const Shader, cch: *RowCache, index: i32, keep: i32) usize {
        if (cch.src_y[0] == index) return 0;
        if (cch.src_y[1] == index) return 1;
        const slot: usize = if (cch.src_y[0] == keep and index != keep) 1 else 0;
        cch.src_y[slot] = index;
        const px: ConstPxPtr = @ptrCast(self.pm.data.ptr);
        const row = px + @as(usize, @intCast(index)) * self.pm.width;
        const o = &cch.rows[slot];
        const V = @Vector(4, u16);
        for (0..cch.n) |i| {
            const l: @Vector(4, u8) = @bitCast(row[cch.ix[i]]);
            const rr: @Vector(4, u8) = @bitCast(row[cch.ix1[i]]);
            const fx = cch.fx[i];
            o[i * 4 ..][0..4].* = @as(V, l) * @as(V, @splat(256 - fx)) + @as(V, rr) * @as(V, @splat(fx));
        }
        return slot;
    }

    inline fn fetch(self: *const Shader, ix: i32, iy: i32) u32 {
        const w: i32 = @intCast(self.pm.width);
        const h: i32 = @intCast(self.pm.height);
        var x = ix;
        var y = iy;
        switch (self.extend) {
            .pad => {
                x = @min(@max(x, 0), w - 1);
                y = @min(@max(y, 0), h - 1);
            },
            .repeat => {
                x = @mod(x, w);
                y = @mod(y, h);
            },
            .transparent => {
                if (x < 0 or x >= w or y < 0 or y >= h) return 0;
            },
        }
        const px: ConstPxPtr = @ptrCast(self.pm.data.ptr);
        return px[@as(usize, @intCast(y)) * @as(usize, @intCast(w)) + @as(usize, @intCast(x))];
    }

    /// 8.8 fixed-point bilinear mix, truncating (`sum >> 16`), identical to takumi's `mix_taps`.
    inline fn bilerp(p00: u32, p01: u32, p10: u32, p11: u32, fx: u32, fy: u32) u32 {
        if ((fx | fy) == 0) return p00;
        const V8 = @Vector(8, u16);
        const V4 = @Vector(4, u32);
        const l: @Vector(8, u8) = @bitCast(@Vector(2, u32){ p00, p10 });
        const rr: @Vector(8, u8) = @bitCast(@Vector(2, u32){ p01, p11 });
        // horizontal lerp of both rows at once; each lane <= 255 * 256
        const hz = @as(V8, l) * @as(V8, @splat(@intCast(256 - fx))) + @as(V8, rr) * @as(V8, @splat(@intCast(fx)));
        const top: V4 = @shuffle(u16, hz, undefined, [4]i32{ 0, 1, 2, 3 });
        const bot: V4 = @shuffle(u16, hz, undefined, [4]i32{ 4, 5, 6, 7 });
        const res = (top * @as(V4, @splat(256 - fy)) + bot * @as(V4, @splat(fy))) >> @splat(16);
        const b: @Vector(4, u8) = @truncate(res);
        return @bitCast(b);
    }

    /// One axis of a bilinear lookup: floor index + 8-bit fraction of `coord - 0.5`.
    /// For `.pad` this equals takumi's `BilinearAxis::new` (clamped to [0, extent-1]).
    inline fn axis(self: *const Shader, coord: f32, extent: u32, frac: *u32) i32 {
        const ef: f32 = @floatFromInt(extent);
        var c = coord - 0.5;
        switch (self.extend) {
            .pad => c = clampF(c, 0, ef - 1),
            .repeat => c = clampF(c - @floor(c / ef) * ef, 0, ef),
            .transparent => c = clampF(c, -2, ef + 1),
        }
        const fl = @floor(c);
        frac.* = @intFromFloat((c - fl) * 256.0);
        return @intFromFloat(fl);
    }

    fn shadeImage(self: *const Shader, x: i32, yc: f32, out: PxPtr, n: usize) void {
        const xc: f32 = @as(f32, @floatFromInt(x)) + 0.5;
        const m = self.m;
        const w = self.pm.width;
        const h = self.pm.height;
        const uu0 = m.a * xc + m.c * yc + m.e;
        const vv0 = m.b * xc + m.d * yc + m.f;
        if (self.filter == .nearest) {
            const wf: f32 = @floatFromInt(w);
            const hf: f32 = @floatFromInt(h);
            for (0..n) |i| {
                const fi: f32 = types.fi32(i);
                var u = uu0 + fi * m.a;
                var v = vv0 + fi * m.b;
                if (self.extend == .repeat) {
                    u = u - @floor(u / wf) * wf;
                    v = v - @floor(v / hf) * hf;
                }
                const iu: i32 = @intFromFloat(@floor(clampF(u, -1, wf)));
                const iv: i32 = @intFromFloat(@floor(clampF(v, -1, hf)));
                out[i] = self.fetch(iu, iv);
            }
            return;
        }
        if (self.extend == .pad) {
            // hot path (drawPixmap, object-fit images): clamped taps, no per-tap extend logic
            const px: ConstPxPtr = @ptrCast(self.pm.data.ptr);
            const lastx: f32 = @floatFromInt(w - 1);
            const lasty: f32 = @floatFromInt(h - 1);
            const wm1: usize = w - 1;
            const hm1: usize = h - 1;
            const stride: usize = w;
            if (m.b == 0) {
                // image rows stay rows: vertical taps are constant along the span
                const cyv = clampF(vv0 - 0.5, 0, lasty);
                const iy: usize = @intCast(@as(i32, @intFromFloat(cyv)));
                const fy: u32 = @intCast(@as(i32, @intFromFloat((cyv - @as(f32, @floatFromInt(iy))) * 256.0)));
                const iy1 = @min(iy + 1, hm1);
                if (self.cache) |cch| {
                    const rel = @as(i64, x) - cch.x0;
                    if (rel >= 0 and rel + @as(i64, @intCast(n)) <= cch.n) {
                        const top = cacheRow(self, cch, @intCast(iy), @intCast(iy1));
                        const bot = cacheRow(self, cch, @intCast(iy1), @intCast(iy));
                        const o4 = @as(usize, @intCast(rel)) * 4;
                        const tp: [*]const u16 = cch.rows[top][o4..].ptr;
                        const bp: [*]const u16 = cch.rows[bot][o4..].ptr;
                        const ob: [*]u8 = @ptrCast(out);
                        const V = @Vector(8, u32);
                        const w0: V = @splat(256 - fy);
                        const w1: V = @splat(fy);
                        const total = n * 4;
                        var k: usize = 0;
                        while (k + 8 <= total) : (k += 8) {
                            const tv: V = @as(@Vector(8, u16), tp[k..][0..8].*);
                            const bv: V = @as(@Vector(8, u16), bp[k..][0..8].*);
                            ob[k..][0..8].* = @as(@Vector(8, u8), @truncate((tv * w0 + bv * w1) >> @splat(16)));
                        }
                        while (k < total) : (k += 1) {
                            ob[k] = @truncate((@as(u32, tp[k]) * (256 - fy) + @as(u32, bp[k]) * fy) >> 16);
                        }
                        return;
                    }
                }
                const r0 = px + iy * stride;
                const r1 = px + iy1 * stride;
                for (0..n) |i| {
                    const c = clampF(uu0 + types.fi32(i) * m.a - 0.5, 0, lastx);
                    const ix: usize = @intCast(@as(i32, @intFromFloat(c)));
                    const fx: u32 = @intCast(@as(i32, @intFromFloat((c - @as(f32, @floatFromInt(ix))) * 256.0)));
                    const ix1 = @min(ix + 1, wm1);
                    out[i] = bilerp(r0[ix], r0[ix1], r1[ix], r1[ix1], fx, fy);
                }
                return;
            }
            for (0..n) |i| {
                const fi: f32 = types.fi32(i);
                const c = clampF(uu0 + fi * m.a - 0.5, 0, lastx);
                const cyv = clampF(vv0 + fi * m.b - 0.5, 0, lasty);
                const ix: usize = @intCast(@as(i32, @intFromFloat(c)));
                const iy: usize = @intCast(@as(i32, @intFromFloat(cyv)));
                const fx: u32 = @intCast(@as(i32, @intFromFloat((c - @as(f32, @floatFromInt(ix))) * 256.0)));
                const fy: u32 = @intCast(@as(i32, @intFromFloat((cyv - @as(f32, @floatFromInt(iy))) * 256.0)));
                const ix1 = @min(ix + 1, wm1);
                const r0 = px + iy * stride;
                const r1 = px + @min(iy + 1, hm1) * stride;
                out[i] = bilerp(r0[ix], r0[ix1], r1[ix], r1[ix1], fx, fy);
            }
            return;
        }
        for (0..n) |i| {
            const fi: f32 = types.fi32(i);
            var fx: u32 = 0;
            var fy: u32 = 0;
            const ix = self.axis(uu0 + fi * m.a, w, &fx);
            const iy = self.axis(vv0 + fi * m.b, h, &fy);
            out[i] = bilerp(self.fetch(ix, iy), self.fetch(ix + 1, iy), self.fetch(ix, iy + 1), self.fetch(ix + 1, iy + 1), fx, fy);
        }
    }
};

// ---- span compositing -------------------------------------------------------------------

const VL = types.LANES;
const VU = @Vector(VL, u32);
const sh8: @Vector(VL, u5) = @splat(8);
const sh24: @Vector(VL, u5) = @splat(24);

inline fn loadV(p: ConstPxPtr) VU {
    return @as(*align(1) const [VL]u32, @ptrCast(p)).*;
}

inline fn storeV(p: PxPtr, v: VU) void {
    @as(*align(1) [VL]u32, @ptrCast(p)).* = v;
}

/// Vector form of `types.scalePx` (exact per-channel `round(x * c / 255)`).
inline fn scalePxV(p: VU, c: VU) VU {
    const m: VU = @splat(0x00FF00FF);
    const bias: VU = @splat(0x00800080);
    var rb = (p & m) * c + bias;
    rb = ((rb + ((rb >> sh8) & m)) >> sh8) & m;
    var ga = ((p >> sh8) & m) * c + bias;
    ga = (ga + ((ga >> sh8) & m)) & @as(VU, @splat(0xFF00FF00));
    return rb | ga;
}

inline fn overV(s: VU, d: VU) VU {
    return s +% scalePxV(d, @as(VU, @splat(255)) - (s >> sh24));
}

/// dst[i] = src[i]*c over dst[i], with `cov` per-pixel coverage or (null) constant `ca`.
pub fn blendPixels(d: PxPtr, s: ConstPxPtr, n: usize, cov: ?[*]const u8, ca: u32) void {
    var i: usize = 0;
    if (cov) |c| {
        while (i + VL <= n) : (i += VL) {
            const cv: VU = @as(@Vector(VL, u8), c[i..][0..VL].*);
            storeV(d + i, overV(scalePxV(loadV(s + i), cv), loadV(d + i)));
        }
        while (i < n) : (i += 1) {
            const cv: u32 = c[i];
            if (cv == 0) continue;
            const p = scalePx(s[i], cv);
            d[i] = p +% scalePx(d[i], 255 - (p >> 24));
        }
    } else if (ca == 255) {
        while (i + VL <= n) : (i += VL) {
            const p = loadV(s + i);
            if (@reduce(.And, p) >> 24 == 255) {
                storeV(d + i, p);
            } else {
                storeV(d + i, overV(p, loadV(d + i)));
            }
        }
        while (i < n) : (i += 1) {
            const p = s[i];
            d[i] = p +% scalePx(d[i], 255 - (p >> 24));
        }
    } else {
        const cav: VU = @splat(ca);
        while (i + VL <= n) : (i += VL) {
            storeV(d + i, overV(scalePxV(loadV(s + i), cav), loadV(d + i)));
        }
        while (i < n) : (i += 1) {
            const p = scalePx(s[i], ca);
            d[i] = p +% scalePx(d[i], 255 - (p >> 24));
        }
    }
}

pub const fillPixels = types.fillPixels;

fn blendSolid(d: PxPtr, color: u32, n: usize, cov: ?[*]const u8, ca: u32) void {
    if (cov) |c| {
        const is_opaque = (color >> 24) == 255;
        const colv: VU = @splat(color);
        const CW = if (VL == 4) u32 else u64;
        var i: usize = 0;
        while (i + VL <= n) : (i += VL) {
            // all-zero / all-255 tests on the packed coverage bytes (a vector reduce is slow in wasm)
            const cw = @as(*align(1) const CW, @ptrCast(c + i)).*;
            if (cw == 0) continue;
            if (cw == std.math.maxInt(CW) and is_opaque) {
                storeV(d + i, colv);
                continue;
            }
            const cb: @Vector(VL, u8) = c[i..][0..VL].*;
            storeV(d + i, overV(scalePxV(colv, @as(VU, cb)), loadV(d + i)));
        }
        while (i < n) : (i += 1) {
            const cv: u32 = c[i];
            if (cv == 0) continue;
            const p = scalePx(color, cv);
            d[i] = p +% scalePx(d[i], 255 - (p >> 24));
        }
    } else {
        const p = if (ca == 255) color else scalePx(color, ca);
        const sa = p >> 24;
        if (sa == 255) {
            fillPixels(d, n, p);
        } else if (sa != 0) {
            const ia = 255 - sa;
            const pv: VU = @splat(p);
            const iav: VU = @splat(ia);
            var i: usize = 0;
            while (i + VL <= n) : (i += VL) storeV(d + i, pv +% scalePxV(loadV(d + i), iav));
            while (i < n) : (i += 1) d[i] = p +% scalePx(d[i], ia);
        }
    }
}

/// Combines up to two coverage rows and a constant into `buf`; returns the per-pixel coverage
/// pointer for the chunk, or null when coverage is the constant `alpha`.
inline fn chunkCov(a: ?[*]const u8, b: ?[*]const u8, alpha: u32, off: usize, m: usize, buf: *[CH]u8) ?[*]const u8 {
    if (a) |pa| {
        if (b) |pb| {
            for (0..m) |i| {
                var c = div255(@as(u32, pa[off + i]) * pb[off + i]);
                if (alpha != 255) c = div255(c * alpha);
                buf[i] = @intCast(c);
            }
            return buf;
        }
        if (alpha == 255) return pa + off;
        for (0..m) |i| buf[i] = @intCast(div255(@as(u32, pa[off + i]) * alpha));
        return buf;
    }
    if (b) |pb| {
        if (alpha == 255) return pb + off;
        for (0..m) |i| buf[i] = @intCast(div255(@as(u32, pb[off + i]) * alpha));
        return buf;
    }
    return null;
}

/// Composites `n` pixels of the shader starting at device (x, y) onto `d` with coverage
/// `cov[i] * clip[i] * alpha` (null rows = 255).
pub fn blendSpan(sh: *const Shader, d: PxPtr, x: i32, y: i32, n: usize, cov: ?[*]const u8, clip: ?[*]const u8, alpha_in: u32) void {
    const alpha = if (sh.alpha == 255) alpha_in else div255(alpha_in * sh.alpha);
    if (alpha == 0 or n == 0) return;
    if (sh.kind == .solid and (cov == null or clip == null) and alpha == 255) {
        return blendSolid(d, sh.color, n, cov orelse clip, 255);
    }
    if (sh.kind == .solid and cov == null and clip == null) {
        return blendSolid(d, sh.color, n, null, alpha);
    }
    var cbuf: [CH]u8 = undefined;
    var sbuf: [CH]u32 = undefined;
    var off: usize = 0;
    while (off < n) : (off += CH) {
        const m = @min(CH, n - off);
        var c = chunkCov(cov, clip, alpha, off, m, &cbuf);
        var ca = alpha;
        if (c) |cp| {
            var mn: u8 = 255;
            var mx: u8 = 0;
            for (cp[0..m]) |v| {
                mn = @min(mn, v);
                mx = @max(mx, v);
            }
            if (mx == 0) continue;
            if (mn == 255) {
                c = null;
                ca = 255;
            }
        }
        if (sh.kind == .solid) {
            blendSolid(d + off, sh.color, m, c, ca);
            continue;
        }
        const xo = x +% @as(i32, @intCast(off));
        if (c == null and ca == 255 and sh.is_opaque) {
            sh.shade(xo, y, d + off, m);
            continue;
        }
        sh.shade(xo, y, &sbuf, m);
        blendPixels(d + off, &sbuf, m, c, ca);
    }
}

/// Row pointer helpers ---------------------------------------------------------------------
pub inline fn dstRow(dst: *Pixmap, x: i32, y: i32) PxPtr {
    const off = (@as(usize, @intCast(y)) * dst.width + @as(usize, @intCast(x))) * 4;
    return @ptrCast(dst.data.ptr + off);
}

/// Pointer to coverage of device pixel (x, y) inside an A8 buffer laid out over `b`.
pub inline fn covRow(data: []const u8, b: IRect, x: i32, y: i32) [*]const u8 {
    const ix: usize = @intCast(@as(i64, x) - b.x);
    const iy: usize = @intCast(@as(i64, y) - b.y);
    return data.ptr + iy * b.w + ix;
}

/// Region of `dst` that may be touched under `clip` (validates the clip buffer size).
pub fn clipRegion(dst: *const Pixmap, clip: ?*const ClipMask) IRect {
    if (!dst.isValid()) return IRect.empty;
    var r = dst.bounds();
    if (r.w > std.math.maxInt(i32) or r.h > std.math.maxInt(i32)) return IRect.empty;
    if (clip) |c| {
        r = r.intersect(c.bounds);
        if (c.data) |cd| {
            if (cd.len < @as(u64, c.bounds.w) * c.bounds.h) return IRect.empty;
        }
    }
    return r;
}

pub inline fn clipRow(clip: ?*const ClipMask, x: i32, y: i32) ?[*]const u8 {
    const c = clip orelse return null;
    const d = c.data orelse return null;
    return covRow(d, c.bounds, x, y);
}

/// Source-over fill of `paint` through an A8 coverage mask (and optional clip).
pub fn fillMask(dst: *Pixmap, mask: *const Mask, paint: *const Paint, clip: ?*const ClipMask) void {
    if (mask.bounds.isEmpty() or mask.data.len < @as(u64, mask.bounds.w) * mask.bounds.h) return;
    const r = clipRegion(dst, clip).intersect(mask.bounds);
    if (r.isEmpty()) return;
    var sh: Shader = undefined;
    sh.init(paint);
    if (sh.kind == .none) return;
    var row_cache: RowCache = undefined;
    sh.attachCache(&row_cache, r.x, r.w);
    var y = r.y;
    const y1: i32 = @intCast(r.bottom());
    while (y < y1) : (y += 1) {
        blendSpan(&sh, dstRow(dst, r.x, y), r.x, y, r.w, covRow(mask.data, mask.bounds, r.x, y), clipRow(clip, r.x, y), 255);
    }
}

/// Axis-aligned rectangle fill with exact-area AA on fractional edges, through a prepared
/// shader. Integer-aligned rects take a pure span path (memset for opaque solids).
pub fn fillRectShader(dst: *Pixmap, rect: Rect, sh: *Shader, clip: ?*const ClipMask) void {
    const r = clipRegion(dst, clip);
    if (r.isEmpty() or sh.kind == .none) return;
    const rx0: f32 = @floatFromInt(r.x);
    const ry0: f32 = @floatFromInt(r.y);
    const rx1: f32 = @floatFromInt(r.right());
    const ry1: f32 = @floatFromInt(r.bottom());
    const fx0 = clampF(rect.x, rx0, rx1);
    const fy0 = clampF(rect.y, ry0, ry1);
    const fx1 = clampF(rect.x + rect.w, rx0, rx1);
    const fy1 = clampF(rect.y + rect.h, ry0, ry1);
    if (!(fx1 > fx0) or !(fy1 > fy0)) return;
    const ix0: i32 = @intFromFloat(@floor(fx0));
    const ix1: i32 = @intFromFloat(@ceil(fx1));
    const iy0: i32 = @intFromFloat(@floor(fy0));
    const iy1: i32 = @intFromFloat(@ceil(fy1));
    // horizontal pieces: [left edge px] [interior] [right edge px]
    var row_cache: RowCache = undefined;
    sh.attachCache(&row_cache, ix0, @intCast(ix1 - ix0));
    var lcov: f32 = 1;
    var rcov: f32 = 1;
    var in0 = ix0;
    var in1 = ix1;
    if (ix1 - ix0 == 1) {
        lcov = fx1 - fx0;
        if (lcov < 1) in1 = ix0; // single partially covered column, no interior
    } else {
        lcov = @as(f32, @floatFromInt(ix0 + 1)) - fx0;
        if (lcov < 1) in0 = ix0 + 1;
        rcov = fx1 - @as(f32, @floatFromInt(ix1 - 1));
        if (rcov < 1) in1 = ix1 - 1;
    }
    var y = iy0;
    while (y < iy1) : (y += 1) {
        const yf: f32 = @floatFromInt(y);
        const cy = @min(yf + 1, fy1) - @max(yf, fy0);
        if (in1 > in0) {
            const a: u32 = @intFromFloat(clampF(cy, 0, 1) * 255 + 0.5);
            blendSpan(sh, dstRow(dst, in0, y), in0, y, @intCast(in1 - in0), null, clipRow(clip, in0, y), a);
        }
        if (in0 > ix0 or in1 == ix0) {
            const a: u32 = @intFromFloat(clampF(cy * lcov, 0, 1) * 255 + 0.5);
            blendSpan(sh, dstRow(dst, ix0, y), ix0, y, 1, null, clipRow(clip, ix0, y), a);
        }
        if (in1 < ix1 and in1 != ix0) {
            const a: u32 = @intFromFloat(clampF(cy * rcov, 0, 1) * 255 + 0.5);
            blendSpan(sh, dstRow(dst, ix1 - 1, y), ix1 - 1, y, 1, null, clipRow(clip, ix1 - 1, y), a);
        }
    }
}

/// Axis-aligned rectangle fill (source-over). Fractional edges are anti-aliased by exact area;
/// integer-aligned rects are exact and non-AA (memset when the paint is an opaque solid).
pub fn fillRect(dst: *Pixmap, rect: Rect, paint: *const Paint, clip: ?*const ClipMask) void {
    var sh: Shader = undefined;
    sh.init(paint);
    fillRectShader(dst, rect, &sh, clip);
}
