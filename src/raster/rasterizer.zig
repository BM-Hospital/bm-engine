//! Scan converter with two anti-aliasing engines (see `Mode`):
//!
//! * exact area (`.exact_area` / `.levels16`): signed-area accumulation, font-rs style. Curves
//!   are flattened in device space (tolerance 0.05 px) into a reusable segment list, the tight
//!   bounds are intersected with the clip, and every segment adds its signed area/coverage
//!   deltas to an f32 accumulation buffer.
//! * `.skia_ss`: Skia's / tiny-skia's 4x4 supersampling rasterizer (what takumi uses for every
//!   shape and glyph): fixed-point edges (`skia_aa.zig`) walked one sub-scanline at a time, each
//!   span adding partial (16 per sub-sample) or full (64, 63 on the last sub-scanline) coverage.
//!
//! Both engines write coverage DELTAS into f32 rows with a per-row dirty bitmap (16-cell
//! blocks). The row pass prefix-sums only the dirty blocks and hands the result to a sink as
//! runs: constant-coverage runs (interior / exterior) and per-pixel coverage runs (edges). The
//! mask sink turns them into memset / bytes; the fill sink blends them straight onto the
//! destination (memset-style spans for the interior, no intermediate A8 mask), so large shapes
//! cost O(edge pixels) of per-pixel work.
const std = @import("std");
const types = @import("types.zig");
const path_mod = @import("path.zig");
const paint_mod = @import("paint.zig");
const skia = @import("skia_aa.zig");
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
const BLOCK_SHIFT = 3;
const BLOCK = 1 << BLOCK_SHIFT;

const Seg = struct { x0: f32, y0: f32, x1: f32, y1: f32 };

/// Anti-aliasing engine.
pub const Mode = enum(u8) {
    /// Exact pixel-area coverage, 256 levels.
    exact_area,
    /// Exact area quantised to 17 levels (multiples of 16, 255 for full); same as the legacy
    /// `levels16 = true` flag.
    levels16,
    /// Reproduces tiny-skia's `fill_path(.., anti_alias = true)` (Skia SuperBlitter, SHIFT = 2):
    /// the mask is placed like takumi does (floor / ceil of the tight path bounds, path translated
    /// to the mask origin before the fixed-point conversion). Shapes whose tight bounds exceed
    /// 8191 px on a side fall back to `.exact_area`.
    skia_ss,
};

/// Where finished coverage rows go: an A8 mask, or source-over blending onto a pixmap.
const Sink = struct {
    w: usize,
    /// Mask rows (`w` bytes each); null = fill mode.
    mask: ?[*]u8 = null,
    /// Fill mode: scratch coverage row (`w` bytes).
    cov: [*]u8 = undefined,
    dst: *types.Pixmap = undefined,
    sh: *const paint_mod.Shader = undefined,
    clip: ?*const types.ClipMask = null,
    /// Device position of cell (0, 0).
    x0: i32 = 0,
    y0: i32 = 0,

    /// Buffer that receives the per-pixel coverage of row `y`.
    inline fn row(s: *const Sink, y: usize) [*]u8 {
        return if (s.mask) |m| m + y * s.w else s.cov;
    }

    /// Cells [a, b) of row `y` have constant coverage `v`.
    fn flat(s: *const Sink, y: usize, a: usize, b: usize, v: u8) void {
        if (s.mask) |m| {
            @memset((m + y * s.w)[a..b], v);
            return;
        }
        if (v == 0) return;
        const dx = s.x0 + @as(i32, @intCast(a));
        const dy = s.y0 + @as(i32, @intCast(y));
        paint_mod.blendSpan(s.sh, paint_mod.dstRow(s.dst, dx, dy), dx, dy, b - a, null, paint_mod.clipRow(s.clip, dx, dy), v);
    }

    /// Cells [a, b) of row `y` have their coverage in `row(y)[a..b]`.
    fn edge(s: *const Sink, y: usize, a: usize, b: usize) void {
        if (s.mask != null) return;
        const dx = s.x0 + @as(i32, @intCast(a));
        const dy = s.y0 + @as(i32, @intCast(y));
        paint_mod.blendSpan(s.sh, paint_mod.dstRow(s.dst, dx, dy), dx, dy, b - a, s.cov + a, paint_mod.clipRow(s.clip, dx, dy), 255);
    }
};

/// Placement of a `.skia_ss` rasterization.
const SkiaPrep = struct {
    /// Shape too large for the fixed-point edges: use the exact-area engine.
    fallback: bool = false,
    /// Output rectangle (mask bounds ∩ clip); empty = nothing to draw.
    b: IRect = IRect.empty,
    /// Mask origin = floor of the tight bounds.
    left: i32 = 0,
    top: i32 = 0,
    /// Full mask size (ceil - floor of the tight bounds).
    lw: u32 = 0,
    lh: u32 = 0,
    /// Control points stick out of the mask: tiny-skia then builds edges through its clipper.
    chop_x: bool = false,
};

inline fn sanitize(v: f32) f32 {
    return types.clampF(v, -COORD_LIMIT, COORD_LIMIT);
}

/// Reusable scan-converter scratch state. Keep one around (backed by a long-lived allocator)
/// when rasterizing many paths (glyphs); `rasterize()` below is a one-shot wrapper.
pub const Rasterizer = struct {
    /// Allocator for the scratch buffers (long-lived).
    gpa: Allocator,
    /// Legacy switch: quantise exact-area coverage to 17 levels (multiples of 16). Only looked
    /// at while `mode == .exact_area`; equivalent to `mode = .levels16`.
    levels16: bool = false,
    /// Anti-aliasing engine used by `rasterize` / `fillPath`.
    mode: Mode = .exact_area,
    segs: std.ArrayList(Seg) = .empty,
    /// Invariant: all zero between calls.
    accum: []f32 = &.{},
    /// Invariant: all zero between calls.
    bits: []u32 = &.{},
    /// Coverage scratch row for fills.
    cov_row: []u8 = &.{},
    // `.skia_ss` scratch
    edges: std.ArrayList(skia.Edge) = .empty,
    /// First edge starting on each sub-scanline.
    heads: []u32 = &.{},
    /// Edges crossing the current sub-scanline, sorted by x.
    active: []u32 = &.{},
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
        self.gpa.free(self.cov_row);
        self.edges.deinit(self.gpa);
        self.gpa.free(self.heads);
        self.gpa.free(self.active);
        self.* = .{ .gpa = self.gpa };
    }

    /// The engine `rasterize` / `fillPath` will use.
    pub fn effectiveMode(self: *const Rasterizer) Mode {
        if (self.mode == .exact_area and self.levels16) return .levels16;
        return self.mode;
    }

    /// Rasterizes `path` (transformed by `transform`) into a new A8 mask allocated from
    /// `mask_alloc`, with the current mode. Result bounds = pixel bounds of the path ∩ clip
    /// (possibly empty). Open contours are closed implicitly.
    pub fn rasterize(self: *Rasterizer, mask_alloc: Allocator, path: *const Path, transform: Affine, rule: FillRule, clip: IRect) !Mask {
        return self.rasterizeMode(self.effectiveMode(), mask_alloc, path, transform, rule, clip);
    }

    /// `rasterize` with the tiny-skia compatible engine (`Mode.skia_ss`) whatever `mode` is.
    /// This is how takumi turns every outline (boxes, clips, glyphs) into coverage: pass the
    /// outline in device space (`transform` applied here) and the mask comes out bit-compatible
    /// with `tiny_skia::Mask::fill_path(.., anti_alias = true)` on the same f32 path.
    pub fn rasterizeSkia(self: *Rasterizer, mask_alloc: Allocator, path: *const Path, transform: Affine, rule: FillRule, clip: IRect) !Mask {
        return self.rasterizeMode(.skia_ss, mask_alloc, path, transform, rule, clip);
    }

    fn rasterizeMode(self: *Rasterizer, mode: Mode, mask_alloc: Allocator, path: *const Path, transform: Affine, rule: FillRule, clip: IRect) !Mask {
        var sp: SkiaPrep = .{ .fallback = true };
        if (mode == .skia_ss) sp = self.prepareSkia(path, transform, clip);
        const b = if (sp.fallback) try self.prepare(path, transform, clip) else sp.b;
        if (b.isEmpty()) return Mask.empty;
        const n = @as(u64, b.w) * b.h;
        if (n > std.math.maxInt(usize) / 2) return error.OutOfMemory;
        // every byte is written by the row pass: no need to clear
        var mask: Mask = .{ .bounds = b, .data = try mask_alloc.alloc(u8, @intCast(n)) };
        errdefer mask.deinit(mask_alloc);
        const sink: Sink = .{ .w = b.w, .mask = mask.data.ptr };
        if (sp.fallback) {
            try self.render(b, &sink, rule, mode == .levels16);
        } else {
            try self.renderSkia(&sp, path, transform, rule, &sink);
        }
        return mask;
    }

    /// Scan-converts and composites (source-over) in one pass: interior runs are blended as
    /// constant-coverage spans straight from the accumulation rows (memset for opaque solid
    /// paints), only edge cells go through per-pixel coverage. No per-call allocation once the
    /// scratch buffers are warm. Pixel results are identical to `rasterize` + `fillMask`.
    pub fn fillPath(
        self: *Rasterizer,
        dst: *types.Pixmap,
        path: *const Path,
        transform: Affine,
        rule: FillRule,
        paint: *const types.Paint,
        clip: ?*const types.ClipMask,
    ) !void {
        const region = paint_mod.clipRegion(dst, clip);
        if (region.isEmpty()) return;
        const mode = self.effectiveMode();
        var sp: SkiaPrep = .{ .fallback = true };
        if (mode == .skia_ss) sp = self.prepareSkia(path, transform, region);
        const b = if (sp.fallback) try self.prepare(path, transform, region) else sp.b;
        if (b.isEmpty()) return;
        if (self.cov_row.len < b.w) {
            self.gpa.free(self.cov_row);
            self.cov_row = &.{};
            self.cov_row = try self.gpa.alloc(u8, b.w);
        }
        var sh: paint_mod.Shader = undefined;
        sh.init(paint);
        if (sh.kind == .none) return;
        var row_cache: paint_mod.RowCache = undefined;
        sh.attachCache(&row_cache, b.x, b.w);
        const sink: Sink = .{ .w = b.w, .cov = self.cov_row.ptr, .dst = dst, .sh = &sh, .clip = clip, .x0 = b.x, .y0 = b.y };
        if (sp.fallback) {
            try self.render(b, &sink, rule, mode == .levels16);
        } else {
            try self.renderSkia(&sp, path, transform, rule, &sink);
        }
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

    /// Makes `accum` hold `cells` zeroed f32 and `bits` hold `nbits` zeroed words.
    fn reserve(self: *Rasterizer, cells: usize, nbits: usize) !void {
        if (self.accum.len < cells) {
            self.gpa.free(self.accum);
            self.accum = &.{};
            self.accum = try self.gpa.alloc(f32, cells);
            @memset(self.accum, 0);
        }
        if (self.bits.len < nbits) {
            self.gpa.free(self.bits);
            self.bits = &.{};
            self.bits = try self.gpa.alloc(u32, nbits);
            @memset(self.bits, 0);
        }
    }

    fn render(self: *Rasterizer, b: IRect, sink: *const Sink, rule: FillRule, q16: bool) !void {
        const w: usize = b.w;
        const h: usize = b.h;
        const stride = w + 2;
        const total64 = @as(u64, stride) * h;
        if (total64 > std.math.maxInt(usize) / 8) return error.OutOfMemory;
        const total: usize = @intCast(total64);
        const blocks = (stride + BLOCK - 1) >> BLOCK_SHIFT;
        const words = (blocks + 31) >> 5;
        try self.reserve(total, words * h);
        self.w = w;
        self.h = h;
        self.stride = stride;
        self.words = words;
        const ox: f32 = @floatFromInt(b.x);
        const oy: f32 = @floatFromInt(b.y);
        for (self.segs.items) |s| {
            self.drawLine(s.x0 - ox, s.y0 - oy, s.x1 - ox, s.y1 - oy);
        }
        const evenodd = rule == .evenodd;
        var y: usize = 0;
        while (y < h) : (y += 1) {
            self.accumulateRow(false, self.accum.ptr + y * stride, self.bits.ptr + y * words, y, sink, evenodd, q16);
        }
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
            // 17 coverage levels (0, 16, .., 240, 255)
            const q: u32 = @intFromFloat(v * 16 + 0.5);
            return @intCast(@min(255, q * 16));
        }
        return @intFromFloat(v * 255 + 0.5);
    }

    /// `.skia_ss` rows accumulate alpha directly (integer-valued); the sum saturates at 255.
    inline fn covRaw(acc: f32) u8 {
        var v = if (acc < 255) acc else 255;
        v = if (v > 0) v else 0;
        return @intFromFloat(v);
    }

    /// Prefix-sums one delta row (`w + 2` cells) and emits it to `sink` as row `y`: dirty blocks
    /// become per-pixel coverage runs, the stretches between them constant runs. Restores the
    /// all-zero invariant of `row` / `brow`.
    fn accumulateRow(self: *Rasterizer, comptime raw: bool, row: [*]f32, brow: [*]u32, y: usize, sink: *const Sink, evenodd: bool, q16: bool) void {
        const w = self.w;
        const stride = w + 2;
        const words = self.words;
        const orow = sink.row(y);
        var acc: f32 = 0;
        var cur: u8 = 0;
        var done: usize = 0; // cells [0, done) are handled
        var run0: usize = 0; // pending per-pixel run = [run0, done)
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
                if (c0 > done) {
                    if (done > run0) sink.edge(y, run0, @min(done, w));
                    if (done < w) sink.flat(y, done, @min(c0, w), cur);
                    run0 = c0;
                }
                const ce = @min(c1, w);
                var c = c0;
                while (c < ce) : (c += 1) {
                    acc += row[c];
                    row[c] = 0;
                    orow[c] = if (raw) covRaw(acc) else cov(acc, evenodd, q16);
                }
                // slack cells past the right edge only need clearing
                c = @max(c0, ce);
                while (c < c1) : (c += 1) row[c] = 0;
                cur = if (raw) covRaw(acc) else cov(acc, evenodd, q16);
                done = c1;
            }
        }
        if (done > run0 and run0 < w) sink.edge(y, run0, @min(done, w));
        if (done < w) sink.flat(y, done, w, cur);
    }

    // ---- tiny-skia compatible supersampling engine ---------------------------------------

    /// Maps a path point to device space exactly like tiny-skia's `Transform::map_points`
    /// followed by takumi's translation to the mask origin (`off`).
    inline fn skPoint(t: *const Affine, p: Point, off: skia.P) skia.P {
        return .{
            sanitize(t.a * p.x + t.c * p.y + t.e) - off[0],
            sanitize(t.b * p.x + t.d * p.y + t.f) - off[1],
        };
    }

    /// One pass over `path` (contours closed implicitly) in device space minus `off`: collects
    /// bounds into `bd` and / or builds edges with `eb`.
    noinline fn walkPath(path: *const Path, t: *const Affine, off: skia.P, bd: ?*skia.Bounds, eb: ?*skia.Builder) !void {
        const pts = path.points.items;
        var pi: usize = 0;
        var start: skia.P = .{ 0, 0 };
        var cur: skia.P = start;
        var open = false;
        var c: [4]skia.P = undefined;
        var vi: usize = 0;
        const nverbs = path.verbs.items.len;
        // one extra iteration closes the last contour
        while (vi <= nverbs) : (vi += 1) {
            const verb: path_mod.Verb = if (vi < nverbs) path.verbs.items[vi] else .close;
            var need: usize = switch (verb) {
                .move, .line => 1,
                .quad => 2,
                .cubic => 3,
                .close => 0,
            };
            if (pi + need > pts.len) {
                // malformed path: ignore the rest, but still close what is open
                if (vi < nverbs) {
                    vi = nverbs - 1;
                    continue;
                }
                need = 0;
            }
            const starts = verb == .move or (!open and verb != .close);
            if (verb == .move or verb == .close) {
                // implicit closing line
                c[0] = cur;
                c[1] = start;
                if (open) {
                    if (eb) |b| try b.line(c[0], c[1]);
                }
            }
            if (starts) {
                start = if (verb == .move) skPoint(t, pts[pi], off) else skPoint(t, .{ .x = 0, .y = 0 }, off);
                open = true;
                if (bd) |b| b.point(start);
            }
            if (verb == .move or verb == .close) {
                if (verb == .move) pi += 1;
                cur = start;
                continue;
            }
            if (starts) cur = start;
            c[0] = cur;
            for (0..need) |k| c[k + 1] = skPoint(t, pts[pi + k], off);
            pi += need;
            switch (verb) {
                .line => {
                    if (bd) |b| b.point(c[1]);
                    if (eb) |b| try b.line(c[0], c[1]);
                },
                .quad => {
                    if (bd) |b| b.quad(c[0..3]);
                    if (eb) |b| try b.quad(c[0..3]);
                },
                else => {
                    if (bd) |b| b.cubic(&c);
                    if (eb) |b| try b.cubic(&c);
                },
            }
            cur = c[need];
        }
    }

    /// Mask placement for `.skia_ss`: floor / ceil of the tight bounds (takumi `rasterize_mask`).
    fn prepareSkia(self: *Rasterizer, path: *const Path, transform: Affine, clip: IRect) SkiaPrep {
        _ = self;
        if (clip.isEmpty() or path.verbs.items.len == 0) return .{};
        var bounds: skia.Bounds = .{};
        walkPath(path, &transform, .{ 0, 0 }, &bounds, null) catch return .{};
        const bd = &bounds;
        if (!(bd.tmax[0] >= bd.tmin[0]) or !(bd.tmax[1] >= bd.tmin[1])) return .{};
        // tiny-skia refuses paths whose (control) bounds have no width or height
        const nearly_zero: f32 = 1.0 / 4096.0;
        if (bd.cmax[0] - bd.cmin[0] <= nearly_zero or bd.cmax[1] - bd.cmin[1] <= nearly_zero) return .{};
        const lim: i32 = @intFromFloat(COORD_LIMIT);
        const x0 = types.toIntClamped(@floor(bd.tmin[0]), -lim, lim);
        const y0 = types.toIntClamped(@floor(bd.tmin[1]), -lim, lim);
        const x1 = types.toIntClamped(@ceil(bd.tmax[0]), -lim, lim);
        const y1 = types.toIntClamped(@ceil(bd.tmax[1]), -lim, lim);
        if (x1 <= x0 or y1 <= y0) return .{};
        if (x1 - x0 > skia.MAX_SIDE or y1 - y0 > skia.MAX_SIDE) return .{ .fallback = true };
        const full: IRect = .{ .x = x0, .y = y0, .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
        const contained = @floor(bd.cmin[0]) >= @as(f32, @floatFromInt(x0)) and @floor(bd.cmin[1]) >= @as(f32, @floatFromInt(y0)) and
            @ceil(bd.cmax[0]) <= @as(f32, @floatFromInt(x1)) and @ceil(bd.cmax[1]) <= @as(f32, @floatFromInt(y1));
        return .{ .b = full.intersect(clip), .left = x0, .top = y0, .lw = full.w, .lh = full.h, .chop_x = !contained };
    }

    inline fn mark(brow: [*]u32, c: usize) void {
        const blk = c >> BLOCK_SHIFT;
        brow[blk >> 5] |= @as(u32, 1) << @intCast(blk & 31);
    }

    /// One supersampled span [start, stop) (sub-pixel units, start < stop) of a sub-scanline
    /// whose fully covered pixels are worth `full` (`SuperBlitter::blit_h` + `AlphaRuns::add`).
    fn addSpan(row: [*]f32, brow: [*]u32, start: usize, stop: usize, full: f32) void {
        const fb = start & (skia.SCALE - 1);
        const fe = stop & (skia.SCALE - 1);
        var px = start >> skia.SHIFT;
        const pe = stop >> skia.SHIFT;
        const unit: f32 = 1 << (8 - 2 * skia.SHIFT);
        if (px == pe) {
            const v = @as(f32, @floatFromInt(fe - fb)) * unit;
            row[px] += v;
            row[px + 1] -= v;
            mark(brow, px);
            mark(brow, px + 1);
            return;
        }
        if (fb != 0) {
            const v = @as(f32, @floatFromInt(skia.SCALE - fb)) * unit;
            row[px] += v;
            row[px + 1] -= v;
            mark(brow, px);
            px += 1;
        }
        // pixels [px, pe) are covered over the whole sub-scanline width
        row[px] += full;
        row[pe] -= full;
        mark(brow, px);
        mark(brow, pe);
        if (fe != 0) {
            const v = @as(f32, @floatFromInt(fe)) * unit;
            row[pe] += v;
            row[pe + 1] -= v;
            mark(brow, pe + 1);
        }
    }

    /// Builds the fixed-point edges in mask-local coordinates and walks them one sub-scanline
    /// at a time (Skia `walk_edges`), flushing a pixel row to `sink` every 4 sub-scanlines.
    fn renderSkia(self: *Rasterizer, sp: *const SkiaPrep, path: *const Path, transform: Affine, rule: FillRule, sink: *const Sink) !void {
        const b = sp.b;
        const w: usize = b.w;
        const h: usize = b.h;
        self.edges.clearRetainingCapacity();
        var eb: skia.Builder = .{ .gpa = self.gpa, .edges = &self.edges, .chop_x = sp.chop_x };
        try walkPath(path, &transform, .{ @floatFromInt(sp.left), @floatFromInt(sp.top) }, null, &eb);
        const edges = self.edges.items;
        // window inside the mask
        const wx0: usize = @intCast(@as(i64, b.x) - sp.left);
        const wy0: usize = @intCast(@as(i64, b.y) - sp.top);
        const nsub: usize = (wy0 + h) << skia.SHIFT;
        const stride = w + 2;
        const blocks = (stride + BLOCK - 1) >> BLOCK_SHIFT;
        const words = (blocks + 31) >> 5;
        try self.reserve(stride, words);
        if (self.heads.len < nsub) {
            self.gpa.free(self.heads);
            self.heads = &.{};
            self.heads = try self.gpa.alloc(u32, nsub);
        }
        if (self.active.len < edges.len) {
            self.gpa.free(self.active);
            self.active = &.{};
            self.active = try self.gpa.alloc(u32, edges.len);
        }
        self.w = w;
        self.words = words;
        const heads = self.heads[0..nsub];
        @memset(heads, skia.NONE);
        if (edges.len >= 2) {
            for (edges, 0..) |*e, i| {
                // edges that start above the mask enter on its first sub-scanline (as in Skia)
                const fy: usize = @intCast(@max(e.first_y, 0));
                if (fy >= nsub) continue;
                e.next = heads[fy];
                heads[fy] = @intCast(i);
            }
        }
        const active = self.active.ptr;
        var na: usize = 0;
        const row = self.accum.ptr;
        const brow = self.bits.ptr;
        const wind_mask: i32 = if (rule == .evenodd) 1 else -1;
        const sx0: i32 = @intCast(wx0 << skia.SHIFT);
        const sx1: i32 = @intCast((wx0 + w) << skia.SHIFT);
        const right_clip: i32 = @intCast(sp.lw << skia.SHIFT);
        const emit_from = wy0 << skia.SHIFT;
        var dirty = false;
        var y: usize = 0;
        while (y < nsub) : (y += 1) {
            var ei = heads[y];
            while (ei != skia.NONE) : (ei = edges[ei].next) {
                active[na] = ei;
                na += 1;
            }
            if (na != 0) {
                // keep the list sorted by x (it is nearly sorted already)
                var i: usize = 1;
                while (i < na) : (i += 1) {
                    const id = active[i];
                    const x = edges[id].x;
                    var j = i;
                    while (j > 0 and edges[active[j - 1]].x > x) : (j -= 1) active[j] = active[j - 1];
                    active[j] = id;
                }
                const vis = y >= emit_from;
                const yi: i32 = @intCast(y);
                // full pixels are worth 64 per sub-scanline, 63 on the last one (3 * 64 + 63 = 255)
                const full: f32 = if ((y & (skia.SCALE - 1)) == skia.SCALE - 1) 63 else 64;
                var winding: i32 = 0;
                var left: i32 = 0;
                var keep: usize = 0;
                i = 0;
                while (i < na) : (i += 1) {
                    const id = active[i];
                    const e = &edges[id];
                    const x = (e.x +% 0x8000) >> 16;
                    if ((winding & wind_mask) == 0) left = x;
                    winding += e.winding;
                    if ((winding & wind_mask) == 0 and vis) {
                        const a = @min(@max(left, sx0), sx1) - sx0;
                        const z = @min(@max(x, sx0), sx1) - sx0;
                        if (z > a) {
                            addSpan(row, brow, @intCast(a), @intCast(z), full);
                            dirty = true;
                        }
                    }
                    // step the edge to the next sub-scanline
                    if (e.last_y <= yi) {
                        if (e.kind == .line or e.curve_count == 0 or !e.update()) continue;
                    } else {
                        e.x +%= e.dx;
                    }
                    active[keep] = id;
                    keep += 1;
                }
                if ((winding & wind_mask) != 0 and vis) {
                    // unbalanced winding: Skia fills to the right clip edge
                    const a = @min(@max(left, sx0), sx1) - sx0;
                    const z = @min(@max(right_clip, sx0), sx1) - sx0;
                    if (z > a) {
                        addSpan(row, brow, @intCast(a), @intCast(z), full);
                        dirty = true;
                    }
                }
                na = keep;
            }
            if ((y & (skia.SCALE - 1)) == skia.SCALE - 1 and y >= emit_from) {
                const oy = (y >> skia.SHIFT) - wy0;
                if (dirty) {
                    self.accumulateRow(true, row, brow, oy, sink, false, false);
                    dirty = false;
                } else sink.flat(oy, 0, w, 0);
            }
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

/// One-shot tiny-skia compatible rasterization (see `Rasterizer.rasterizeSkia`); scratch comes
/// from `alloc` and is freed before returning, the mask is owned by the caller. Glyph loops
/// should keep a `Rasterizer` and call its method instead.
pub fn rasterizeSkia(alloc: Allocator, path: *const Path, transform: Affine, rule: FillRule, clip: IRect) !Mask {
    var r = Rasterizer.init(alloc);
    defer r.deinit();
    return r.rasterizeSkia(alloc, path, transform, rule, clip);
}
