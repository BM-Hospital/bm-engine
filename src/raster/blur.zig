//! Gaussian blur: port of takumi's `blur.rs` (itself Skia's raster `SkBlurEngine`), so shadow
//! and filter output is byte-comparable:
//!   * sigma <= 0.03: no-op;
//!   * sigma < 2: exact normalised Gaussian kernel of radius ceil(3 sigma), f32;
//!   * 2 <= sigma <= 135: Skia's three-box (tent) integer pass per axis;
//!   * sigma > 135: the buffer is shrunk bilinearly (halving steps, Skia's
//!     `FilterResult::Builder::blur` rule), blurred with sigma 135 and scaled back (`blurRescaled`).
//! Separable, horizontal then vertical; pixels outside the buffer are transparent.
const std = @import("std");
const types = @import("types.zig");
const IRect = types.IRect;
const Mask = types.Mask;
const Pixmap = types.Pixmap;
const Allocator = std.mem.Allocator;

pub const MIN_SIGMA: f32 = 0.03;
pub const MAX_SIGMA: f32 = 135.0;
/// Channels blurred at once by a column pass.
const BAND = 256;
/// Rows transposed at once by the horizontal pass.
const ROW_STRIP = 64; // * 4 channels == BAND
const MAX_GAUSS_WINDOW = 13; // radius ceil(3 * 2) = 6

const Rounding = enum { rgba, alpha };

const Pass = struct {
    gaussian: bool,
    /// rows the output lags the input (= reach of the kernel on each side)
    border: usize,
    window: usize,
    // gaussian
    kernel: [MAX_GAUSS_WINDOW]f32 = undefined,
    // three-box
    factor: u32 = 0,
    seed: u32 = 0,
    bias: u64 = 0,

    fn init(sigma_in: f32, rounding: Rounding) ?Pass {
        if (!std.math.isFinite(sigma_in) or sigma_in <= MIN_SIGMA) return null;
        if (sigma_in < 2.0) {
            const radius: usize = @intFromFloat(@ceil(3.0 * sigma_in));
            var p: Pass = .{ .gaussian = true, .border = radius, .window = 2 * radius + 1 };
            const den = 1.0 / (2.0 * sigma_in * sigma_in);
            var sum: f32 = 0;
            for (0..p.window) |i| {
                const off = @as(f32, @floatFromInt(i)) - @as(f32, @floatFromInt(radius));
                p.kernel[i] = types.expNeg(off * off * den);
                sum += p.kernel[i];
            }
            const scale = 1.0 / sum;
            for (p.kernel[0..p.window]) |*k| k.* *= scale;
            return p;
        }
        const sigma = @min(sigma_in, MAX_SIGMA);
        // Skia BoxBlurWindow
        const window: usize = @max(@as(usize, @intFromFloat(@floor(sigma * 3.0 * @sqrt(2.0 * std.math.pi) / 4.0 + 0.5))), 1);
        if (window <= 1) return null;
        const odd = window % 2 == 1;
        const border = if (odd) 3 * ((window - 1) / 2) else 3 * (window / 2) - 1;
        const cube: u64 = @as(u64, window) * window * window;
        const divisor: u64 = if (odd) cube else cube + window * window;
        const factor: u32 = @intFromFloat(@round((1.0 / @as(f64, @floatFromInt(divisor))) * 4294967296.0));
        return .{
            .gaussian = false,
            .border = border,
            .window = window,
            .factor = factor,
            .seed = if (rounding == .rgba) @intCast((divisor + 1) / 2) else 0,
            .bias = if (rounding == .rgba) 0 else 1 << 31,
        };
    }
};

/// Kernel reach in pixels for `sigma` (how far a blur spreads ink on each side); 0 = no-op.
pub fn blurReach(sigma: f32) u32 {
    if (sigma > MAX_SIGMA) {
        // rescaled blur: the ink spreads 3 sigma (capped; such blurs wash out to nothing anyway)
        return @intFromFloat(@ceil(3.0 * @min(sigma, 5000.0)));
    }
    const p = Pass.init(sigma, .alpha) orelse return 0;
    return @intCast(p.border);
}

const Scratch = struct {
    // three-box
    sum0: [BAND]u32 = undefined,
    sum1: [BAND]u32 = undefined,
    sum2: [BAND]u32 = undefined,
    blurred: [BAND]u8 = undefined,
    zeros: [BAND]u8 = undefined,
    first: []u8 = &.{},
    second: []u16 = &.{},
    third: []u32 = &.{},
    // gaussian
    ring: []f32 = &.{},
    sums: [BAND]f32 = undefined,

    /// In-place init (the struct is several KB; avoids a by-value template copy).
    fn init(s: *Scratch, alloc: Allocator, pass: *const Pass) !void {
        s.first = &.{};
        s.second = &.{};
        s.third = &.{};
        s.ring = &.{};
        @memset(&s.zeros, 0);
        errdefer s.deinit(alloc);
        if (pass.gaussian) {
            s.ring = try alloc.alloc(f32, pass.window * BAND);
        } else {
            const p = pass.window - 1;
            const last = if (pass.window % 2 == 0) p + 1 else p;
            s.first = try alloc.alloc(u8, p * BAND);
            s.second = try alloc.alloc(u16, p * BAND);
            s.third = try alloc.alloc(u32, last * BAND);
        }
    }

    fn deinit(s: *Scratch, alloc: Allocator) void {
        alloc.free(s.first);
        alloc.free(s.second);
        alloc.free(s.third);
        alloc.free(s.ring);
    }
};

/// Blurs `rows` rows of `channels` (<= BAND) adjacent bytes down the columns, in place.
fn columnPass(pass: *const Pass, s: *Scratch, base: [*]u8, rows: usize, row_stride: usize, channels: usize) void {
    const border = pass.border;
    if (pass.gaussian) {
        const window = pass.window;
        // lanes are padded to a multiple of 8 so every loop is a fixed-width SIMD loop
        const cs = (channels + 7) & ~@as(usize, 7);
        const VF8 = @Vector(8, f32);
        var inb: [BAND]u8 = undefined;
        var outb: [BAND]u8 = undefined;
        @memset(inb[0..cs], 0);
        @memset(s.ring[0 .. window * cs], 0);
        var next: usize = 0;
        for (0..rows + border) |index| {
            if (index < rows) {
                @memcpy(inb[0..channels], (base + index * row_stride)[0..channels]);
            } else {
                @memset(inb[0..channels], 0);
            }
            const cell = s.ring[next * cs ..][0..cs];
            var k: usize = 0;
            while (k < cs) : (k += 8) {
                const ints: @Vector(8, i32) = @as(@Vector(8, u8), inb[k..][0..8].*);
                cell[k..][0..8].* = @as(VF8, @floatFromInt(ints)) * @as(VF8, @splat(1.0 / 255.0));
            }
            next = if (next + 1 == window) 0 else next + 1;
            if (index < border) continue;
            const sums = s.sums[0..cs];
            @memset(sums, 0);
            for (pass.kernel[0..window], 0..) |weight, offset| {
                var slot = next + offset;
                if (slot >= window) slot -= window;
                const samples = s.ring[slot * cs ..][0..cs];
                const wv: VF8 = @splat(weight);
                k = 0;
                while (k < cs) : (k += 8) {
                    const acc: VF8 = sums[k..][0..8].*;
                    const smp: VF8 = samples[k..][0..8].*;
                    sums[k..][0..8].* = acc + smp * wv;
                }
            }
            k = 0;
            while (k < cs) : (k += 8) {
                const v: VF8 = sums[k..][0..8].*;
                const t = v * @as(VF8, @splat(255.0)) + @as(VF8, @splat(0.5));
                // NaN-safe clamp to [0, 255]
                const hi: VF8 = @splat(255.0);
                const c = @select(f32, t > @as(VF8, @splat(0)), @select(f32, t < hi, t, hi), @as(VF8, @splat(0)));
                // float -> int via the 2^23 trick (vector trunc_sat is very slow in V8); c is in [0, 255]
                const iv: @Vector(8, u32) = @bitCast(@floor(c) + @as(VF8, @splat(8388608.0)));
                outb[k..][0..8].* = @as(@Vector(8, u8), @truncate(iv));
            }
            @memcpy((base + (index - border) * row_stride)[0..channels], outb[0..channels]);
        }
        return;
    }
    const p = pass.window - 1;
    const last = if (pass.window % 2 == 0) p + 1 else p;
    const sum0 = s.sum0[0..channels];
    const sum1 = s.sum1[0..channels];
    const sum2 = s.sum2[0..channels];
    const blurred = s.blurred[0..channels];
    @memset(sum0, 0);
    @memset(sum1, 0);
    @memset(sum2, pass.seed);
    @memset(s.first[0 .. p * channels], 0);
    @memset(s.second[0 .. p * channels], 0);
    @memset(s.third[0 .. last * channels], 0);
    const factor: u64 = pass.factor;
    const bias = pass.bias;
    var slot: usize = 0;
    var last_slot: usize = 0;
    for (0..rows + border) |index| {
        const entering: [*]const u8 = if (index < rows) base + index * row_stride else &s.zeros;
        const first = s.first[slot * channels ..][0..channels];
        const second = s.second[slot * channels ..][0..channels];
        const third = s.third[last_slot * channels ..][0..channels];
        var lane0: usize = 0;
        const VW = types.LANES;
        const V = @Vector(VW, u32);
        while (lane0 + VW <= channels) : (lane0 += VW) {
            const eb: @Vector(VW, u8) = entering[lane0..][0..VW].*;
            var s0: V = sum0[lane0..][0..VW].*;
            var s1: V = sum1[lane0..][0..VW].*;
            var s2: V = sum2[lane0..][0..VW].*;
            s0 +%= @as(V, eb);
            s1 +%= s0;
            s2 +%= s1;
            const wide = @as(@Vector(VW, u64), s2) * @as(@Vector(VW, u64), @splat(factor)) + @as(@Vector(VW, u64), @splat(bias));
            blurred[lane0..][0..VW].* = @as(@Vector(VW, u8), @truncate(wide >> @splat(32)));
            s2 -%= @as(V, third[lane0..][0..VW].*);
            third[lane0..][0..VW].* = s1;
            s1 -%= @as(V, @as(@Vector(VW, u16), second[lane0..][0..VW].*));
            second[lane0..][0..VW].* = @as(@Vector(VW, u16), @truncate(s0));
            s0 -%= @as(V, @as(@Vector(VW, u8), first[lane0..][0..VW].*));
            first[lane0..][0..VW].* = eb;
            sum0[lane0..][0..VW].* = s0;
            sum1[lane0..][0..VW].* = s1;
            sum2[lane0..][0..VW].* = s2;
        }
        for (lane0..channels) |lane| {
            const leading: u32 = entering[lane];
            sum0[lane] +%= leading;
            sum1[lane] +%= sum0[lane];
            sum2[lane] +%= sum1[lane];
            blurred[lane] = @truncate((@as(u64, sum2[lane]) * factor + bias) >> 32);
            sum2[lane] -%= third[lane];
            third[lane] = sum1[lane];
            sum1[lane] -%= second[lane];
            second[lane] = @truncate(sum0[lane]);
            sum0[lane] -%= first[lane];
            first[lane] = entering[lane];
        }
        if (index >= border) {
            const target = base + (index - border) * row_stride;
            @memcpy(target[0..channels], blurred);
        }
        slot = if (slot + 1 == p) 0 else slot + 1;
        last_slot = if (last_slot + 1 == last) 0 else last_slot + 1;
    }
}

// ---- sigma > 135: shrink, blur, scale back (takumi `blur_rescaled`) ------------------------

const FBounds = struct { l: f32, t: f32, r: f32, b: f32 };

/// Skia's `downscale_step_count`: halvings needed to bring the sigma scale `scale` (< 1) in range.
fn downscaleStepCount(scale: f32) u32 {
    const v: u32 = @intFromFloat(types.clampF(@ceil(1.0 / scale), 1, 1.0e6));
    var steps: u32 = 32 - @clz(v - 1); // ceil(log2(v))
    if (steps > 0) {
        const last = scale * @as(f32, @floatFromInt(@as(u32, 1) << @intCast(steps - 1)));
        const limit: f32 = if (steps == 1) 1.0 - 1e-3 else 0.9;
        if (last >= limit) steps -= 1;
    }
    return steps;
}

/// Skia's `scale_about_center`.
fn scaleAboutCenter(b: FBounds, fx: f32, fy: f32) FBounds {
    const cx = if (fx == 1.0) 0.0 else 0.5 * b.l + 0.5 * b.r;
    const cy = if (fy == 1.0) 0.0 else 0.5 * b.t + 0.5 * b.b;
    return .{ .l = cx + fx * (b.l - cx), .t = cy + fy * (b.t - cy), .r = cx + fx * (b.r - cx), .b = cy + fy * (b.b - cy) };
}

/// An `n`-channel image whose top-left pixel sits at (left, top).
const Raster = struct {
    left: f32,
    top: f32,
    w: usize,
    h: usize,
    n: usize,
    px: []u8,

    /// Bilinear sample at `(x, y)`, transparent outside (takumi `Raster::sample`).
    fn sample(self: *const Raster, x_in: f32, y_in: f32, out: [*]u8) void {
        const x = x_in - self.left - 0.5;
        const y = y_in - self.top - 0.5;
        const col = @floor(x);
        const row = @floor(y);
        const wx = x - col;
        const wy = y - row;
        const n = self.n;
        var tex: [4]?[*]const u8 = undefined;
        for (0..4) |k| {
            const c = col + @as(f32, @floatFromInt(k & 1));
            const r = row + @as(f32, @floatFromInt(k >> 1));
            tex[k] = if (!(c >= 0) or !(r >= 0) or !(c < @as(f32, @floatFromInt(self.w))) or !(r < @as(f32, @floatFromInt(self.h))))
                null
            else
                self.px.ptr + (@as(usize, @intFromFloat(r)) * self.w + @as(usize, @intFromFloat(c))) * n;
        }
        for (0..n) |ch| {
            var t: [4]f32 = undefined;
            for (0..4) |k| t[k] = if (tex[k]) |q| @floatFromInt(q[ch]) else 0;
            const top = t[0] + (t[1] - t[0]) * wx;
            const bot = t[2] + (t[3] - t[2]) * wx;
            out[ch] = @intFromFloat(types.clampF(top + (bot - top) * wy + 0.5, 0, 255));
        }
    }
};

/// Blur with sigma > MAX_SIGMA: the image (bounds = the whole buffer) is resampled bilinearly
/// to `MAX_SIGMA / sigma` of its size in halving steps, blurred, and sampled back.
fn blurRescaled(alloc: Allocator, data: []u8, width: usize, height: usize, comptime n: usize, sigma: f32, rounding: Rounding) Allocator.Error!void {
    const scale = @min(MAX_SIGMA / sigma, 1.0);
    const steps = downscaleStepCount(scale);
    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const image_bounds: FBounds = .{ .l = 0, .t = 0, .r = wf, .b = hf };
    var bounds = image_bounds;
    var image: Raster = .{ .left = 0, .top = 0, .w = width, .h = height, .n = n, .px = data };
    defer if (image.px.ptr != data.ptr) alloc.free(image.px);
    var step = steps;
    while (step > 0) {
        step -= 1;
        const fx = if (step > 0) 0.5 else wf * scale / (bounds.r - bounds.l);
        const fy = if (step > 0) 0.5 else hf * scale / (bounds.b - bounds.t);
        const target = scaleAboutCenter(bounds, fx, fy);
        // the pixels `target` touches
        const l = @floor(target.l);
        const t = @floor(target.t);
        const nw: usize = @intFromFloat(types.clampF(@ceil(target.r) - l, 1, wf + 2));
        const nh: usize = @intFromFloat(types.clampF(@ceil(target.b) - t, 1, hf + 2));
        const npx = try alloc.alloc(u8, nw * nh * n);
        // same operation order as takumi's `map_between`
        const bw = bounds.r - bounds.l;
        const bh = bounds.b - bounds.t;
        const tw = target.r - target.l;
        const th = target.b - target.t;
        for (0..nh) |j| {
            const cy = t + types.fi32(j) + 0.5;
            const my = bounds.t + (cy - target.t) * bh / th;
            for (0..nw) |i| {
                const cx = l + types.fi32(i) + 0.5;
                image.sample(bounds.l + (cx - target.l) * bw / tw, my, npx.ptr + (j * nw + i) * n);
            }
        }
        if (image.px.ptr != data.ptr) alloc.free(image.px);
        image = .{ .left = l, .top = t, .w = nw, .h = nh, .n = n, .px = npx };
        bounds = target;
    }
    const low = @min(@min(sigma * (bounds.r - bounds.l) / wf, sigma * (bounds.b - bounds.t) / hf), MAX_SIGMA);
    try blurBuffer(alloc, image.px, image.w, image.h, n, low, rounding);
    if (image.px.ptr == data.ptr) return;
    const bw = bounds.r - bounds.l;
    const bh = bounds.b - bounds.t;
    for (0..height) |j| {
        const my = bounds.t + (types.fi32(j) + 0.5) * bh / hf;
        for (0..width) |i| {
            image.sample(bounds.l + (types.fi32(i) + 0.5) * bw / wf, my, data.ptr + (j * width + i) * n);
        }
    }
}

/// Blurs a `width` x `height` buffer of `n`-channel pixels in place.
fn blurBuffer(alloc: Allocator, data: []u8, width: usize, height: usize, comptime n: usize, sigma: f32, rounding: Rounding) Allocator.Error!void {
    if (width == 0 or height == 0 or data.len < width * height * n) return;
    if (sigma > MAX_SIGMA and std.math.isFinite(sigma)) {
        return blurRescaled(alloc, data, width, height, n, sigma, rounding);
    }
    const pass = Pass.init(sigma, rounding) orelse return;
    var s: Scratch = undefined;
    try s.init(alloc, &pass);
    defer s.deinit(alloc);
    const row_bytes = width * n;

    // Horizontal: rows blur as the columns of a transposed strip.
    {
        const strip = try alloc.alloc(u8, ROW_STRIP * row_bytes);
        defer alloc.free(strip);
        var y0: usize = 0;
        while (y0 < height) : (y0 += ROW_STRIP) {
            const lanes = @min(ROW_STRIP, height - y0);
            const cw = lanes * n; // bytes per transposed row
            for (0..lanes) |lane| {
                const row = data[(y0 + lane) * row_bytes ..][0..row_bytes];
                for (0..width) |col| {
                    inline for (0..n) |ch| strip[col * cw + lane * n + ch] = row[col * n + ch];
                }
            }
            columnPass(&pass, &s, strip.ptr, width, cw, cw);
            for (0..lanes) |lane| {
                const row = data[(y0 + lane) * row_bytes ..][0..row_bytes];
                for (0..width) |col| {
                    inline for (0..n) |ch| row[col * n + ch] = strip[col * cw + lane * n + ch];
                }
            }
        }
    }
    // Vertical, in bands of adjacent channels.
    var b0: usize = 0;
    while (b0 < row_bytes) : (b0 += BAND) {
        columnPass(&pass, &s, data.ptr + b0, height, row_bytes, @min(BAND, row_bytes - b0));
    }
}

/// Gaussian blur of an A8 mask. The bounds grow by `blurReach(sigma)` on every side and the
/// buffer is reallocated from `alloc` (old data freed with `alloc`). sigma <= 0.03: no-op.
pub fn blurMask(alloc: Allocator, mask: *Mask, sigma: f32) !void {
    return blurMaskClipped(alloc, mask, sigma, .{
        .x = std.math.minInt(i32),
        .y = std.math.minInt(i32),
        .w = std.math.maxInt(u32),
        .h = std.math.maxInt(u32),
    });
}

/// Like `blurMask`, but only the part of the result inside `clip` is produced
/// (result bounds = grown bounds ∩ clip). Values are identical to the unclipped blur; use it
/// to bound memory for large / partly off-canvas shadows.
pub fn blurMaskClipped(alloc: Allocator, mask: *Mask, sigma: f32, clip: IRect) !void {
    const reach = blurReach(sigma);
    if (reach == 0 or mask.bounds.isEmpty()) return;
    if (mask.data.len < @as(u64, mask.bounds.w) * mask.bounds.h) return;
    const grown = mask.bounds.expand(reach);
    const region = grown.intersect(clip);
    if (region.isEmpty()) {
        mask.deinit(alloc);
        return;
    }
    // everything a region pixel can read
    const work = region.expand(reach).intersect(grown);
    var tmp = try Mask.init(alloc, work);
    errdefer tmp.deinit(alloc);
    const src_r = work.intersect(mask.bounds);
    if (!src_r.isEmpty()) {
        var y: i64 = src_r.y;
        while (y < src_r.bottom()) : (y += 1) {
            const so: usize = @as(usize, @intCast(y - mask.bounds.y)) * mask.bounds.w + @as(usize, @intCast(@as(i64, src_r.x) - mask.bounds.x));
            const do: usize = @as(usize, @intCast(y - work.y)) * work.w + @as(usize, @intCast(@as(i64, src_r.x) - work.x));
            @memcpy(tmp.data[do..][0..src_r.w], mask.data[so..][0..src_r.w]);
        }
    }
    try blurBuffer(alloc, tmp.data, work.w, work.h, 1, sigma, .alpha);
    if (region.w == work.w and region.h == work.h) {
        mask.deinit(alloc);
        mask.* = tmp;
        return;
    }
    var out = try Mask.init(alloc, region);
    var y: i64 = region.y;
    while (y < region.bottom()) : (y += 1) {
        const so: usize = @as(usize, @intCast(y - work.y)) * work.w + @as(usize, @intCast(@as(i64, region.x) - work.x));
        const do: usize = @as(usize, @intCast(y - region.y)) * region.w;
        @memcpy(out.data[do..][0..region.w], tmp.data[so..][0..region.w]);
    }
    tmp.deinit(alloc);
    mask.deinit(alloc);
    mask.* = out;
}

/// Gaussian blur of a premultiplied RGBA pixmap in place (same size; outside is transparent).
/// Scratch is allocated from `alloc` and freed before returning.
pub fn blurPixmap(alloc: Allocator, pm: *Pixmap, sigma: f32) !void {
    if (!pm.isValid()) return;
    const n = Pixmap.byteLen(pm.width, pm.height) orelse return;
    try blurBuffer(alloc, pm.data[0..n], pm.width, pm.height, 4, sigma, .rgba);
}
