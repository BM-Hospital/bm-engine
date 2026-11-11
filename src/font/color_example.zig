//! Reference colour-glyph renderer over `raster` + `codec` — the integration recipe for the
//! painter (src/paint.zig). It favours clarity over speed: brushes are evaluated per pixel with
//! `color.shadePremul` (exact COLRv1 semantics: two-point radial, p2-rotated linear, sweep,
//! pad/repeat/reflect, all 28 composite modes); clips are A8 masks from `raster.rasterize`.
//! Used by `src/test_color.zig` (unit test + wasm oracle harness, bench/probe/colorfont/).
//!
//! It imports ../raster and ../codec, so it only compiles from a root at src/ level.
//!
//! Recipe (per glyph run item):
//!   const ct = color.ColorTables.init(font);               // cache per face
//!   if (ct.hasColor()) switch (ct.kind(gid)) {
//!       .bitmap_png => drawBitmapGlyph(arena, dst, ct.bitmap(gid, size).?, size, x, y, clip),
//!       .colr_v0, .colr_v1 => drawColrGlyph(arena, dst, font, &ct, gid, size, x, y, palette, fg),
//!       else => plain outline path (no synthetic bold/italic for colour faces),
//!   };
//! A production painter would: render the COLR glyph once into a glyph-sized offscreen (cache by
//! (face, gid, size, palette, fg)), map solid/linear brushes onto `raster.Paint` (`linearDevice`)
//! and keep the per-pixel path for radial/sweep, and only allocate layers for PaintComposite.
const std = @import("std");
const color = @import("color.zig");
const ttf = @import("ttf.zig");
const raster = @import("../raster/raster.zig");
const codec = @import("../codec/codec.zig");

const Allocator = std.mem.Allocator;
const Affine2x3 = color.Affine2x3;
const IRect = raster.IRect;
const Mask = raster.Mask;
const Pixmap = raster.Pixmap;

fn toAffine(m: Affine2x3) raster.Affine {
    return .{ .a = m.xx, .b = m.yx, .c = m.xy, .d = m.yy, .e = m.dx, .f = m.dy };
}

const Layer = struct { pix: Pixmap, ox: i32, oy: i32, mode: color.CompositeMode };

/// `color.Painter` implementation drawing into `dst` (premultiplied), restricted to `work`.
/// All scratch memory comes from `alloc` (use an arena; nothing is freed individually).
pub const RasterPainter = struct {
    alloc: Allocator,
    font: *const ttf.Font,
    work: IRect,
    xf: std.ArrayList(Affine2x3) = .empty,
    clips: std.ArrayList(?Mask) = .empty, // null entry = unclipped
    layers: std.ArrayList(Layer) = .empty,
    path: raster.Path = .empty,
    err: bool = false,

    /// `base` maps font units (y-up) to device pixels, e.g. for size S at pen (x, y):
    /// `.{ .xx = S/upem, .yy = -S/upem, .dx = x, .dy = y }`.
    pub fn init(alloc: Allocator, font: *const ttf.Font, dst: *Pixmap, work: IRect, base: Affine2x3) !RasterPainter {
        var p: RasterPainter = .{ .alloc = alloc, .font = font, .work = work.intersect(dst.bounds()) };
        try p.xf.append(alloc, base);
        try p.clips.append(alloc, null);
        try p.layers.append(alloc, .{ .pix = dst.*, .ox = 0, .oy = 0, .mode = .src_over });
        return p;
    }

    pub fn painter(self: *RasterPainter) color.Painter {
        return .{ .ctx = self, .vtable = &vtable };
    }

    const vtable: color.Painter.VTable = .{
        .push_transform = pushTransform,
        .pop_transform = popTransform,
        .push_clip_glyph = pushClipGlyph,
        .push_clip_box = pushClipBox,
        .pop_clip = popClip,
        .fill = fill,
        .push_layer = pushLayer,
        .pop_layer = popLayer,
    };

    fn me(ctx: *anyopaque) *RasterPainter {
        return @ptrCast(@alignCast(ctx));
    }
    fn top(p: *RasterPainter) Affine2x3 {
        return p.xf.items[p.xf.items.len - 1];
    }

    fn pushTransform(ctx: *anyopaque, t: Affine2x3) void {
        const p = me(ctx);
        p.xf.append(p.alloc, p.top().mul(t)) catch {
            p.err = true;
        };
    }
    fn popTransform(ctx: *anyopaque) void {
        const p = me(ctx);
        if (p.xf.items.len > 1) _ = p.xf.pop();
    }

    /// Intersects the current clip with the coverage of `p.path` (device space) and pushes it.
    fn pushPathClip(p: *RasterPainter) void {
        var m = raster.rasterize(p.alloc, &p.path, raster.Affine.identity, .nonzero, p.work) catch {
            p.err = true;
            p.clips.append(p.alloc, Mask.empty) catch {};
            return;
        };
        if (p.clips.items[p.clips.items.len - 1]) |cur| {
            m = raster.maskIntersect(p.alloc, &cur, &m) catch blk: {
                p.err = true;
                break :blk Mask.empty;
            };
        }
        p.clips.append(p.alloc, m) catch {
            p.err = true;
        };
    }

    fn pushClipGlyph(ctx: *anyopaque, gid: u16) void {
        const p = me(ctx);
        p.path.reset();
        var sink: raster.PathSink = .{ .path = &p.path, .alloc = p.alloc, .transform = toAffine(p.top()) };
        _ = p.font.outline(gid, &sink);
        if (sink.err) p.err = true;
        p.pushPathClip();
    }

    fn pushClipBox(ctx: *anyopaque, b: color.ClipBox) void {
        const p = me(ctx);
        p.path.reset();
        const m = p.top();
        const pts = [4]color.Point{ .{ .x = b.x_min, .y = b.y_min }, .{ .x = b.x_max, .y = b.y_min }, .{ .x = b.x_max, .y = b.y_max }, .{ .x = b.x_min, .y = b.y_max } };
        for (pts, 0..) |pt, i| {
            const q = m.apply(pt);
            (if (i == 0) p.path.moveTo(p.alloc, q.x, q.y) else p.path.lineTo(p.alloc, q.x, q.y)) catch {
                p.err = true;
            };
        }
        p.path.close(p.alloc) catch {
            p.err = true;
        };
        p.pushPathClip();
    }

    fn popClip(ctx: *anyopaque) void {
        const p = me(ctx);
        if (p.clips.items.len > 1) _ = p.clips.pop();
    }

    fn fill(ctx: *anyopaque, brush: *const color.Brush) void {
        const p = me(ctx);
        const inv = p.top().invert() orelse return;
        const clip = p.clips.items[p.clips.items.len - 1];
        const r = if (clip) |c| c.bounds.intersect(p.work) else p.work;
        if (r.isEmpty()) return;
        const L = &p.layers.items[p.layers.items.len - 1];
        const lw: usize = L.pix.width;
        var y = r.y;
        while (y < r.bottom()) : (y += 1) {
            var x = r.x;
            while (x < r.right()) : (x += 1) {
                const cov: u32 = if (clip) |c| c.at(x, y) else 255;
                if (cov == 0) continue;
                const q = inv.apply(.{ .x = @as(f32, @floatFromInt(x)) + 0.5, .y = @as(f32, @floatFromInt(y)) + 0.5 });
                var s = color.shadePremul(brush, q);
                if (cov != 255) s = scalePx(s, cov);
                const i = (@as(usize, @intCast(y - L.oy)) * lw + @as(usize, @intCast(x - L.ox))) * 4;
                const d = std.mem.readInt(u32, L.pix.data[i..][0..4], .little);
                std.mem.writeInt(u32, L.pix.data[i..][0..4], s +% scalePx(d, 255 - (s >> 24)), .little);
            }
        }
    }

    fn pushLayer(ctx: *anyopaque, mode: color.CompositeMode) void {
        const p = me(ctx);
        const pix = Pixmap.init(p.alloc, p.work.w, p.work.h) catch {
            p.err = true;
            return;
        };
        p.layers.append(p.alloc, .{ .pix = pix, .ox = p.work.x, .oy = p.work.y, .mode = mode }) catch {
            p.err = true;
        };
    }

    fn popLayer(ctx: *anyopaque) void {
        const p = me(ctx);
        if (p.layers.items.len < 2) return;
        const src = p.layers.pop().?;
        const dst = &p.layers.items[p.layers.items.len - 1];
        const r = p.work;
        var y = r.y;
        while (y < r.bottom()) : (y += 1) {
            var x = r.x;
            while (x < r.right()) : (x += 1) {
                const si = (@as(usize, @intCast(y - src.oy)) * src.pix.width + @as(usize, @intCast(x - src.ox))) * 4;
                const di = (@as(usize, @intCast(y - dst.oy)) * dst.pix.width + @as(usize, @intCast(x - dst.ox))) * 4;
                const s = unpack(src.pix.data[si..][0..4]);
                const d = unpack(dst.pix.data[di..][0..4]);
                pack(dst.pix.data[di..][0..4], blendPremul(src.mode, s, d));
            }
        }
    }
};

inline fn scalePx(p: u32, c: u32) u32 {
    var out: u32 = 0;
    inline for (0..4) |k| {
        const v = (p >> (8 * k)) & 0xff;
        out |= raster.div255(v * c) << (8 * k);
    }
    return out;
}

fn unpack(b: *const [4]u8) [4]f32 {
    return .{ @as(f32, @floatFromInt(b[0])) / 255, @as(f32, @floatFromInt(b[1])) / 255, @as(f32, @floatFromInt(b[2])) / 255, @as(f32, @floatFromInt(b[3])) / 255 };
}
fn pack(b: *[4]u8, c: [4]f32) void {
    const a = std.math.clamp(c[3], 0, 1);
    b[3] = @intFromFloat(a * 255 + 0.5);
    for (0..3) |k| b[k] = @intFromFloat(std.math.clamp(c[k], 0, a) * 255 + 0.5);
}

// ---- W3C Compositing and Blending Level 1, premultiplied 0..1 ----

fn lum(c: [3]f32) f32 {
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2];
}
fn clipColor(c: [3]f32) [3]f32 {
    const l = lum(c);
    const n = @min(c[0], c[1], c[2]);
    const x = @max(c[0], c[1], c[2]);
    var o = c;
    for (0..3) |k| {
        if (n < 0) o[k] = l + (o[k] - l) * l / (l - n);
        if (x > 1) o[k] = l + (o[k] - l) * (1 - l) / (x - l);
    }
    return o;
}
fn setLum(c: [3]f32, l: f32) [3]f32 {
    const d = l - lum(c);
    return clipColor(.{ c[0] + d, c[1] + d, c[2] + d });
}
fn sat(c: [3]f32) f32 {
    return @max(c[0], c[1], c[2]) - @min(c[0], c[1], c[2]);
}
fn setSat(c: [3]f32, s: f32) [3]f32 {
    const mx = @max(c[0], c[1], c[2]);
    const mn = @min(c[0], c[1], c[2]);
    var o: [3]f32 = .{ 0, 0, 0 };
    if (mx > mn) {
        for (0..3) |k| o[k] = if (c[k] == mx) s else if (c[k] == mn) 0 else (c[k] - mn) * s / (mx - mn);
        // two channels equal to max: both get s
    }
    return o;
}

fn blendChannel(mode: color.CompositeMode, cb: f32, cs: f32) f32 {
    return switch (mode) {
        .multiply => cb * cs,
        .screen => cb + cs - cb * cs,
        .overlay => blendChannel(.hard_light, cs, cb),
        .darken => @min(cb, cs),
        .lighten => @max(cb, cs),
        .color_dodge => if (cb == 0) 0 else if (cs >= 1) 1 else @min(1, cb / (1 - cs)),
        .color_burn => if (cb >= 1) 1 else if (cs <= 0) 0 else 1 - @min(1, (1 - cb) / cs),
        .hard_light => if (cs <= 0.5) cb * 2 * cs else blendChannel(.screen, cb, 2 * cs - 1),
        .soft_light => if (cs <= 0.5) cb - (1 - 2 * cs) * cb * (1 - cb) else blk: {
            const d = if (cb <= 0.25) ((16 * cb - 12) * cb + 4) * cb else @sqrt(cb);
            break :blk cb + (2 * cs - 1) * (d - cb);
        },
        .difference => @abs(cb - cs),
        .exclusion => cb + cs - 2 * cb * cs,
        else => cs,
    };
}

/// Composites premultiplied `s` (layer) onto premultiplied `d` with a COLRv1 mode.
pub fn blendPremul(mode: color.CompositeMode, s: [4]f32, d: [4]f32) [4]f32 {
    const as = s[3];
    const ad = d[3];
    const pd = struct {
        fn f(sv: [4]f32, dv: [4]f32, fa: f32, fb: f32) [4]f32 {
            return .{ sv[0] * fa + dv[0] * fb, sv[1] * fa + dv[1] * fb, sv[2] * fa + dv[2] * fb, sv[3] * fa + dv[3] * fb };
        }
    }.f;
    switch (mode) {
        .clear => return .{ 0, 0, 0, 0 },
        .src => return s,
        .dest => return d,
        .src_over => return pd(s, d, 1, 1 - as),
        .dest_over => return pd(s, d, 1 - ad, 1),
        .src_in => return pd(s, d, ad, 0),
        .dest_in => return pd(s, d, 0, as),
        .src_out => return pd(s, d, 1 - ad, 0),
        .dest_out => return pd(s, d, 0, 1 - as),
        .src_atop => return pd(s, d, ad, 1 - as),
        .dest_atop => return pd(s, d, 1 - ad, as),
        .xor => return pd(s, d, 1 - ad, 1 - as),
        .plus => return .{ @min(1, s[0] + d[0]), @min(1, s[1] + d[1]), @min(1, s[2] + d[2]), @min(1, as + ad) },
        else => {},
    }
    // blend modes: co = cs(1-ad) + cd(1-as) + as*ad*B(Cb, Cs) on unpremultiplied Cb, Cs
    const cs: [3]f32 = if (as > 0) .{ s[0] / as, s[1] / as, s[2] / as } else .{ 0, 0, 0 };
    const cb: [3]f32 = if (ad > 0) .{ d[0] / ad, d[1] / ad, d[2] / ad } else .{ 0, 0, 0 };
    const b: [3]f32 = switch (mode) {
        .hsl_hue => setLum(setSat(cs, sat(cb)), lum(cb)),
        .hsl_saturation => setLum(setSat(cb, sat(cs)), lum(cb)),
        .hsl_color => setLum(cs, lum(cb)),
        .hsl_luminosity => setLum(cb, lum(cs)),
        else => .{ blendChannel(mode, cb[0], cs[0]), blendChannel(mode, cb[1], cs[1]), blendChannel(mode, cb[2], cs[2]) },
    };
    var o: [4]f32 = undefined;
    for (0..3) |k| o[k] = s[k] * (1 - ad) + d[k] * (1 - as) + as * ad * b[k];
    o[3] = as + ad - as * ad;
    return o;
}

/// Renders COLR glyph `gid` at `size_px` with its pen origin at (`x`, `y`) (y-down device) into
/// `dst`. `work` limits the touched area (pass the glyph's device bounds; dst.bounds() works).
/// Returns false when the glyph is not a COLR glyph or the paint graph is invalid (then nothing
/// usable was drawn: render into a scratch layer first if partial output matters).
/// Variable fonts: `font` is the instance (`Font.withVariations`), its coordinates drive both the
/// clip outlines and, when `delta_fn` (= &variations.itemDelta) is given, the COLR deltas.
pub fn drawColrGlyph(alloc: Allocator, dst: *Pixmap, font: *const ttf.Font, ct: *const color.ColorTables, gid: u16, size_px: f32, x: f32, y: f32, palette: u16, fg: color.Rgba, work: IRect, delta_fn: ?color.DeltaFn) !bool {
    const s = size_px / @as(f32, @floatFromInt(font.units_per_em));
    var rp = try RasterPainter.init(alloc, font, dst, work, .{ .xx = s, .yy = -s, .dx = x, .dy = y });
    ct.paintVar(gid, palette, fg, font.normalizedCoords(), delta_fn, rp.painter()) catch return false;
    if (rp.err) return error.OutOfMemory;
    return true;
}

/// Draws an embedded bitmap glyph the way takumi does (`resources/glyph.rs` scale_bitmap_glyph):
/// scale = size / strike ppem, placement offsets rounded to whole pixels, bilinear image draw.
pub fn drawBitmapGlyph(alloc: Allocator, dst: *Pixmap, bm: color.Bitmap, size_px: f32, x: f32, y: f32, clip: ?*const raster.ClipMask) !bool {
    if (bm.format != .png) return false;
    const img = codec.decode(alloc, bm.data, .{ .max_pixels = 4 << 20 }) catch return false;
    var pix: Pixmap = .{ .width = img.width, .height = img.height, .data = img.data };
    // straight -> premultiplied in place
    var i: usize = 0;
    while (i + 4 <= pix.data.len) : (i += 4) {
        const a: u32 = pix.data[i + 3];
        if (a == 255) continue;
        for (0..3) |k| pix.data[i + k] = @intCast(raster.div255(@as(u32, pix.data[i + k]) * a));
    }
    const sx = if (bm.ppem_x > 0) size_px / bm.ppem_x else 1;
    const sy = if (bm.ppem > 0) size_px / bm.ppem else 1;
    const left = @round(bm.bearing_x * sx);
    const top_ = @round(bm.bearing_y * sy);
    var src = pix;
    var tf: raster.Affine = .{ .a = sx, .d = sy, .e = x + left, .f = y - top_ };
    if (sx < 0.5 or sy < 0.5) {
        // drawPixmap does not prefilter strong minification
        const w: u32 = @max(1, @as(u32, @intFromFloat(@round(@as(f32, @floatFromInt(pix.width)) * sx))));
        const h: u32 = @max(1, @as(u32, @intFromFloat(@round(@as(f32, @floatFromInt(pix.height)) * sy))));
        src = try raster.resample(alloc, &pix, w, h);
        tf.a = sx * @as(f32, @floatFromInt(pix.width)) / @as(f32, @floatFromInt(w));
        tf.d = sy * @as(f32, @floatFromInt(pix.height)) / @as(f32, @floatFromInt(h));
    }
    raster.drawPixmap(dst, &src, tf, 1, .bilinear, clip);
    return true;
}
