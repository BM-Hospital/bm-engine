//! Exact-area analytic anti-aliasing scan converter (signed-area accumulation, font-rs style).
//!
//! Curves are flattened in device space (tolerance 0.05 px) into a reusable segment list, the
//! tight bounds are intersected with the clip, and every segment adds its signed area/coverage
//! deltas to an f32 accumulation buffer. A per-row dirty bitmap (16-cell blocks) lets the final
//! prefix-sum pass skip untouched stretches with a memset, so large shapes with solid interiors
//! cost O(edge pixels) float work.
const std = @import("std");
const types = @import("types.zig");
const path_mod = @import("path.zig");
const paint_mod = @import("paint.zig");
const Allocator = std.mem.Allocator;
const Point = types.Point;
const IRect = types.IRect;
const Affine = types.Affine;
const Mask = types.Mask;
const FillRule = types.FillRule;
const Path = path_mod.Path;

/// Max chord deviation in device px. 0.05 keeps the inward area bias of flattened arcs ~0.15%.
const TOLERANCE: f32 = 0.05;
/// Device coordinates are clamped to +-COORD_LIMIT (also maps NaN to a finite value).
const COORD_LIMIT: f32 = 1.0e6;
const MAX_SUBDIV: f32 = 512;
const BLOCK_SHIFT = 4;
const BLOCK = 1 << BLOCK_SHIFT;

const Seg = struct { x0: f32, y0: f32, x1: f32, y1: f32 };

inline fn sanitize(v: f32) f32 {
    return types.clampF(v, -COORD_LIMIT, COORD_LIMIT);
}

/// Reusable scan-converter scratch state. Keep one around (backed by a long-lived allocator)
/// when rasterizing many paths (glyphs); `rasterize()` below is a one-shot wrapper.
pub const Rasterizer = struct {
    /// Allocator for the scratch buffers (long-lived).
    gpa: Allocator,
    /// Quantise coverage to 17 levels (multiples of 16), matching 4x4-supersampling rasterizers
    /// such as tiny-skia. Fewer distinct edge values also compress much better in PNG.
    levels16: bool = false,
    segs: std.ArrayList(Seg) = .empty,
    /// Invariant: all zero between calls.
    accum: []f32 = &.{},
    /// Invariant: all zero between calls.
    bits: []u32 = &.{},
    mask_buf: []u8 = &.{},
    // current window
    w: usize = 0,
    h: usize = 0,
    stride: usize = 0,
    words: usize = 0,
    // flattening state
    minx: f32 = 0,
    miny: f32 = 0,
    maxx: f32 = 0,
    maxy: f32 = 0,

    pub fn init(gpa: Allocator) Rasterizer {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Rasterizer) void {
        self.segs.deinit(self.gpa);
        self.gpa.free(self.accum);
        self.gpa.free(self.bits);
        self.gpa.free(self.mask_buf);
        self.* = .{ .gpa = self.gpa };
    }

    /// Rasterizes `path` (transformed by `transform`) into a new A8 mask allocated from
    /// `mask_alloc`. Result bounds = tight path bounds ∩ clip. Open contours are closed implicitly.
    pub fn rasterize(self: *Rasterizer, mask_alloc: Allocator, path: *const Path, transform: Affine, rule: FillRule, clip: IRect) !Mask {
        const b = try self.prepare(path, transform, clip);
        if (b.isEmpty()) return Mask.empty;
        var mask = try Mask.init(mask_alloc, b);
        errdefer mask.deinit(mask_alloc);
        try self.render(b, mask.data, rule);
        return mask;
    }

    /// Rasterize + `fillMask` using an internal reusable mask buffer (no per-call allocation
    /// once the buffers are warm).
    pub fn fillPath(
        self: *Rasterizer,
        dst: *types.Pixmap,
        path: *const Path,
        transform: Affine,
        rule: FillRule,
        paint: *const types.Paint,
        clip: ?*const types.ClipMask,
    ) !void {
        var region = dst.bounds();
        if (clip) |c| region = region.intersect(c.bounds);
        const b = try self.prepare(path, transform, region);
        if (b.isEmpty()) return;
        const n = @as(usize, b.w) * b.h; // bounded by dst size
        if (self.mask_buf.len < n) {
            self.gpa.free(self.mask_buf);
            self.mask_buf = &.{};
            self.mask_buf = try self.gpa.alloc(u8, n);
        }
        const mask: Mask = .{ .bounds = b, .data = self.mask_buf[0..n] };
        try self.render(b, mask.data, rule);
        paint_mod.fillMask(dst, &mask, paint, clip);
    }

    /// Flattens the path and returns tight bounds ∩ clip.
    fn prepare(self: *Rasterizer, path: *const Path, transform: Affine, clip: IRect) !IRect {
        self.segs.clearRetainingCapacity();
        if (clip.isEmpty() or path.verbs.items.len == 0) return IRect.empty;
        try self.flatten(path, transform);
        if (self.segs.items.len == 0) return IRect.empty;
        const lim: i32 = @intFromFloat(COORD_LIMIT);
        const x0 = types.toIntClamped(@floor(self.minx), -lim, lim);
        const y0 = types.toIntClamped(@floor(self.miny), -lim, lim);
        const x1 = types.toIntClamped(@ceil(self.maxx), -lim, lim);
        const y1 = types.toIntClamped(@ceil(self.maxy), -lim, lim);
        if (x1 <= x0 or y1 <= y0) return IRect.empty;
        const b: IRect = .{ .x = x0, .y = y0, .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
        return b.intersect(clip);
    }

    fn render(self: *Rasterizer, b: IRect, out: []u8, rule: FillRule) !void {
        const w: usize = b.w;
        const h: usize = b.h;
        const stride = w + 2;
        const total64 = @as(u64, stride) * h;
        if (total64 > std.math.maxInt(usize) / 8) return error.OutOfMemory;
        const total: usize = @intCast(total64);
        const blocks = (stride + BLOCK - 1) >> BLOCK_SHIFT;
        const words = (blocks + 31) >> 5;
        if (self.accum.len < total) {
            self.gpa.free(self.accum);
            self.accum = &.{};
            self.accum = try self.gpa.alloc(f32, total);
            @memset(self.accum, 0);
        }
        if (self.bits.len < words * h) {
            self.gpa.free(self.bits);
            self.bits = &.{};
            self.bits = try self.gpa.alloc(u32, words * h);
            @memset(self.bits, 0);
        }
        self.w = w;
        self.h = h;
        self.stride = stride;
        self.words = words;
        const ox: f32 = @floatFromInt(b.x);
        const oy: f32 = @floatFromInt(b.y);
        for (self.segs.items) |s| {
            self.drawLine(s.x0 - ox, s.y0 - oy, s.x1 - ox, s.y1 - oy);
        }
        self.accumulate(out, rule == .evenodd);
    }

    // ---- flattening -------------------------------------------------------------------

    fn xform(self: *Rasterizer, t: *const Affine, p: Point) Point {
        const q: Point = .{ .x = sanitize(t.a * p.x + t.c * p.y + t.e), .y = sanitize(t.b * p.x + t.d * p.y + t.f) };
        self.minx = @min(self.minx, q.x);
        self.miny = @min(self.miny, q.y);
        self.maxx = @max(self.maxx, q.x);
        self.maxy = @max(self.maxy, q.y);
        return q;
    }

    /// Appends a segment; capacity must have been reserved. Horizontal segments carry no area.
    fn emit(self: *Rasterizer, a: Point, b: Point) void {
        if (a.y == b.y) return;
        self.segs.appendAssumeCapacity(.{ .x0 = a.x, .y0 = a.y, .x1 = b.x, .y1 = b.y });
    }

    /// Number of uniform chords for a curve whose second-difference magnitude is `dev`
    /// (`k` = 1/4 for quadratics, 3/4 for cubics: Wang's formula).
    fn subdivisions(dev: f32, k: f32) f32 {
        return types.clampF(@ceil(@sqrt(dev * (k / TOLERANCE))), 1, MAX_SUBDIV);
    }

    fn flatten(self: *Rasterizer, path: *const Path, transform: Affine) !void {
        const t = &transform;
        self.minx = std.math.floatMax(f32);
        self.miny = std.math.floatMax(f32);
        self.maxx = -std.math.floatMax(f32);
        self.maxy = -std.math.floatMax(f32);
        const pts = path.points.items;
        var pi: usize = 0;
        var start: Point = .{ .x = 0, .y = 0 };
        var cur: Point = start;
        var open = false;
        for (path.verbs.items) |verb| {
            const need: usize = switch (verb) {
                .move, .line => 1,
                .quad => 2,
                .cubic => 3,
                .close => 0,
            };
            if (pi + need > pts.len) break; // malformed path: ignore the rest
            try self.segs.ensureUnusedCapacity(self.gpa, 1);
            if (verb == .move or verb == .close) {
                if (open) self.emit(cur, start);
                if (verb == .move) {
                    start = self.xform(t, pts[pi]);
                    pi += 1;
                    open = true;
                }
                cur = start;
                continue;
            }
            if (!open) {
                // segment without a moveTo: start at the origin
                start = self.xform(t, .{ .x = 0, .y = 0 });
                cur = start;
                open = true;
            }
            // control points as a cubic-shaped array: p0, c1, c2, p3
            var c: [4]Point = undefined;
            c[0] = cur;
            for (0..need) |k| c[k + 1] = self.xform(t, pts[pi + k]);
            pi += need;
            const end = c[need];
            var nf: f32 = 1;
            if (verb == .quad) {
                const ddx = c[0].x - 2 * c[1].x + c[2].x;
                const ddy = c[0].y - 2 * c[1].y + c[2].y;
                nf = subdivisions(@sqrt(ddx * ddx + ddy * ddy), 0.25);
            } else if (verb == .cubic) {
                const ax = c[0].x - 2 * c[1].x + c[2].x;
                const ay = c[0].y - 2 * c[1].y + c[2].y;
                const bx = c[1].x - 2 * c[2].x + c[3].x;
                const by = c[1].y - 2 * c[2].y + c[3].y;
                nf = subdivisions(@sqrt(@max(ax * ax + ay * ay, bx * bx + by * by)), 0.75);
            }
            const n: u32 = @intFromFloat(nf);
            try self.segs.ensureUnusedCapacity(self.gpa, n);
            var prev = cur;
            const step = 1.0 / nf;
            var i: u32 = 1;
            while (i < n) : (i += 1) {
                const tt = @as(f32, @floatFromInt(i)) * step;
                const mt = 1 - tt;
                var q: Point = undefined;
                if (verb == .quad) {
                    const w0 = mt * mt;
                    const w1 = 2 * mt * tt;
                    const w2 = tt * tt;
                    q = .{ .x = w0 * c[0].x + w1 * c[1].x + w2 * c[2].x, .y = w0 * c[0].y + w1 * c[1].y + w2 * c[2].y };
                } else {
                    const w0 = mt * mt * mt;
                    const w1 = 3 * mt * mt * tt;
                    const w2 = 3 * mt * tt * tt;
                    const w3 = tt * tt * tt;
                    q = .{
                        .x = w0 * c[0].x + w1 * c[1].x + w2 * c[2].x + w3 * c[3].x,
                        .y = w0 * c[0].y + w1 * c[1].y + w2 * c[2].y + w3 * c[3].y,
                    };
                }
                self.emit(prev, q);
                prev = q;
            }
            self.emit(prev, end);
            cur = end;
        }
        try self.segs.ensureUnusedCapacity(self.gpa, 1);
        if (open) self.emit(cur, start);
    }

    // ---- scan conversion --------------------------------------------------------------

    fn drawLine(self: *Rasterizer, ax: f32, ay: f32, bx: f32, by: f32) void {
        var x0 = ax;
        var y0 = ay;
        var x1 = bx;
        var y1 = by;
        var dir: f32 = 1;
        if (y0 > y1) {
            x0 = bx;
            y0 = by;
            x1 = ax;
            y1 = ay;
            dir = -1;
        }
        const hf: f32 = @floatFromInt(self.h);
        const wf: f32 = @floatFromInt(self.w);
        if (!(y1 > 0) or !(y0 < hf) or !(y1 > y0)) return;
        const dxdy = (x1 - x0) / (y1 - y0);
        if (!std.math.isFinite(dxdy)) return;
        if (y0 < 0) {
            x0 -= y0 * dxdy;
            y0 = 0;
        }
        if (y1 > hf) {
            x1 -= (y1 - hf) * dxdy;
            y1 = hf;
        }
        const lo = @min(x0, x1);
        const hi = @max(x0, x1);
        if (lo >= 0 and hi <= wf) return self.scan(x0, y0, y1, dxdy, dir);
        // Everything left of the window acts like a vertical edge at x = 0; everything right of
        // it contributes nothing.
        if (hi <= 0) return self.scan(0, y0, y1, 0, dir);
        if (lo >= wf) return;
        const inv = (y1 - y0) / (x1 - x0);
        var ya = y0 + (0 - x0) * inv;
        var yb = y0 + (wf - x0) * inv;
        if (ya > yb) {
            const tmp = ya;
            ya = yb;
            yb = tmp;
        }
        const cuts = [4]f32{ y0, types.clampF(ya, y0, y1), types.clampF(yb, y0, y1), y1 };
        for (0..3) |i| {
            const sa = cuts[i];
            const sb = cuts[i + 1];
            if (!(sb > sa)) continue;
            const xa = x0 + (sa - y0) * dxdy;
            const xb = x0 + (sb - y0) * dxdy;
            const mid = (xa + xb) * 0.5;
            if (mid <= 0) {
                self.scan(0, sa, sb, 0, dir);
            } else if (mid < wf) {
                const cxa = types.clampF(xa, 0, wf);
                const cxb = types.clampF(xb, 0, wf);
                self.scan(cxa, sa, sb, (cxb - cxa) / (sb - sa), dir);
            }
        }
    }

    /// Pre-clipped segment: y in [0, h], x in [0, w], y0 < y1.
    fn scan(self: *Rasterizer, x0: f32, y0: f32, y1: f32, dxdy: f32, dir: f32) void {
        const wf: f32 = @floatFromInt(self.w);
        const stride = self.stride;
        const words = self.words;
        var x = types.clampF(x0, 0, wf);
        var y: usize = @intFromFloat(y0);
        const yend: usize = @min(self.h, @as(usize, @intFromFloat(@ceil(y1))));
        while (y < yend) : (y += 1) {
            const yf: f32 = @floatFromInt(y);
            const dy = @min(yf + 1, y1) - @max(yf, y0);
            if (!(dy > 0)) continue;
            const xnext = types.clampF(x + dxdy * dy, 0, wf);
            const d = dy * dir;
            const xl = @min(x, xnext);
            const xr = @max(x, xnext);
            const x0floor = @floor(xl);
            const x0i: usize = @intFromFloat(x0floor);
            const x1ceil = @ceil(xr);
            const x1i: usize = @intFromFloat(x1ceil);
            const row = self.accum.ptr + y * stride;
            var last = x0i + 1;
            if (x1i <= x0i + 1) {
                const xmf = 0.5 * (x + xnext) - x0floor;
                row[x0i] += d - d * xmf;
                row[x0i + 1] += d * xmf;
            } else {
                const s = 1.0 / (xr - xl);
                const x0f = xl - x0floor;
                const a0 = 0.5 * s * (1 - x0f) * (1 - x0f);
                const x1f = xr - x1ceil + 1;
                const am = 0.5 * s * x1f * x1f;
                row[x0i] += d * a0;
                if (x1i == x0i + 2) {
                    row[x0i + 1] += d * (1 - a0 - am);
                } else {
                    const a1 = s * (1.5 - x0f);
                    row[x0i + 1] += d * (a1 - a0);
                    const ds = d * s;
                    var xi = x0i + 2;
                    while (xi < x1i - 1) : (xi += 1) row[xi] += ds;
                    const a2 = a1 + @as(f32, @floatFromInt(x1i - x0i - 3)) * s;
                    row[x1i - 1] += d * (1 - a2 - am);
                }
                row[x1i] += d * am;
                last = x1i;
            }
            // mark dirty blocks
            const brow = self.bits.ptr + y * words;
            var b = x0i >> BLOCK_SHIFT;
            const b1 = last >> BLOCK_SHIFT;
            while (b <= b1) : (b += 1) {
                brow[b >> 5] |= @as(u32, 1) << @intCast(b & 31);
            }
            x = xnext;
        }
    }

    inline fn cov(acc: f32, evenodd: bool, q16: bool) u8 {
        var v = @abs(acc);
        if (evenodd) {
            v = v - 2 * @floor(v * 0.5);
            if (v > 1) v = 2 - v;
        }
        // NaN-safe clamp to [0, 1]
        v = if (v < 1) v else 1;
        v = if (v > 0) v else 0;
        if (q16) {
            // 17 coverage levels (0, 16, .., 240, 255) like 4x4 supersampling (tiny-skia / Skia AAA off).
            const q: u32 = @intFromFloat(v * 16 + 0.5);
            return @intCast(@min(255, q * 16));
        }
        return @intFromFloat(v * 255 + 0.5);
    }

    /// Prefix-sums the accumulation buffer into `out` (w*h bytes) and restores the all-zero
    /// invariant of `accum` / `bits`.
    fn accumulate(self: *Rasterizer, out: []u8, evenodd: bool) void {
        const w = self.w;
        const stride = self.stride;
        const words = self.words;
        const q16 = self.levels16;
        var y: usize = 0;
        while (y < self.h) : (y += 1) {
            const row = self.accum.ptr + y * stride;
            const brow = self.bits.ptr + y * words;
            const orow = out.ptr + y * w;
            var acc: f32 = 0;
            var cur: u8 = 0;
            var done: usize = 0; // cells [0, done) already written
            var wi: usize = 0;
            while (wi < words) : (wi += 1) {
                var word = brow[wi];
                if (word == 0) continue;
                brow[wi] = 0;
                while (word != 0) {
                    const bit: usize = @ctz(word);
                    word &= word - 1;
                    const c0 = ((wi << 5) + bit) << BLOCK_SHIFT;
                    const c1 = @min(c0 + BLOCK, stride);
                    if (c0 > done and done < w) @memset(orow[done..@min(c0, w)], cur);
                    const ce = @min(c1, w);
                    var c = c0;
                    while (c < ce) : (c += 1) {
                        acc += row[c];
                        row[c] = 0;
                        orow[c] = cov(acc, evenodd, q16);
                    }
                    // slack cells past the right edge only need clearing
                    c = @max(c0, ce);
                    while (c < c1) : (c += 1) row[c] = 0;
                    cur = cov(acc, evenodd, q16);
                    done = c1;
                }
            }
            if (done < w) @memset(orow[done..w], cur);
        }
    }
};

/// One-shot convenience wrapper around `Rasterizer` (allocates scratch from `alloc` and frees
/// it before returning; the mask is owned by the caller). Exact-area anti-aliasing with 256
/// coverage levels; curves are flattened adaptively (0.05 px) after `transform`.
/// Result bounds = tight path bounds ∩ clip. For many small paths keep a `Rasterizer` instead.
pub fn rasterize(alloc: Allocator, path: *const Path, transform: Affine, rule: FillRule, clip: IRect) !Mask {
    var r = Rasterizer.init(alloc);
    defer r.deinit();
    return r.rasterize(alloc, path, transform, rule, clip);
}

/// Rasterize + fill (source-over). One-shot; see `Rasterizer.fillPath` for the reusable form.
pub fn fillPath(
    alloc: Allocator,
    dst: *types.Pixmap,
    path: *const Path,
    transform: Affine,
    rule: FillRule,
    paint: *const types.Paint,
    clip: ?*const types.ClipMask,
) !void {
    var r = Rasterizer.init(alloc);
    defer r.deinit();
    return r.fillPath(dst, path, transform, rule, paint, clip);
}
