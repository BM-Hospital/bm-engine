//! Colour glyphs: COLR v0/v1 + CPAL paint graphs, CBDT/CBLC and sbix embedded bitmaps, and the
//! emoji-presentation helpers used by font fallback.
//!
//! Design: this module only READS font tables and describes what to draw; it never rasterises.
//!  * `paintColr` walks a COLR glyph and calls back a `Painter` (COLRv1 model: transforms, clips,
//!    fills with solid / linear / radial / sweep brushes, compositing layers). Coordinates are font
//!    units, y-up. The painter fetches clip outlines itself with `Font.outline(gid, sink)`.
//!  * `bitmapGlyph` returns the embedded image bytes (PNG for CBDT formats 17/18/19 and sbix
//!    'png ') plus strike placement; the caller decodes it (codec.decode) and scales by
//!    `font_size / bitmap.ppem`.
//!  * `glyphKind` is a cheap classifier (bitmap first, then COLR v1, then COLR v0 = takumi order).
//!  * Gradient helpers (`gradientT`, `sampleColorLine`, `shadePremul`, `linearDevice`) let a
//!    painter evaluate brushes exactly without knowing COLR conventions.
//!  See `color_example.zig` for a complete reference painter over `raster` (integration recipe).
//!
//! No allocation anywhere: the walker keeps its state on the stack (max depth 64, <= 64 colour
//! stops per colour line, a paint-node budget of 65536 per glyph). Every table access is bounds
//! checked; malformed data yields `error.Malformed` (or `null` / `.none`), never a trap.
//!
//! Not implemented (honest list):
//!  * Variation deltas are applied only through `paintColrVar` / `ColorTables.paintVar` with a
//!    caller-supplied `DeltaFn` (= variations.itemDelta); `paintColr` uses base values.
//!  * SVG-in-OpenType ('SVG ' table): detected (`ColorTables.has_svg`) but never rendered.
//!  * EBDT/EBLC monochrome/grey bitmaps and CBDT image formats other than 17/18/19, sbix 'jpg ',
//!    'tiff', 'mask': reported as `Kind.bitmap_other` / `Bitmap.format == .other` (no decoder).
//!  * Colour lines with more than 64 stops are truncated to the first 64 (by stop order in font).
const std = @import("std");
const ttf = @import("ttf.zig");
const Font = ttf.Font;

// Local bounds-checked big-endian readers (0 when out of range); same semantics as ttf.rd*.
inline fn rd8(t: []const u8, off: u32) u8 {
    return if (off < t.len) t[off] else 0;
}
inline fn rd16(t: []const u8, off: u32) u16 {
    if (t.len < 2 or off > t.len - 2) return 0;
    return (@as(u16, t[off]) << 8) | t[off + 1];
}
inline fn rdi16(t: []const u8, off: u32) i16 {
    return @bitCast(rd16(t, off));
}
inline fn rd32(t: []const u8, off: u32) u32 {
    if (t.len < 4 or off > t.len - 4) return 0;
    return (@as(u32, t[off]) << 24) | (@as(u32, t[off + 1]) << 16) | (@as(u32, t[off + 2]) << 8) | t[off + 3];
}

pub const emoji = @import("color_emoji.zig");
pub const isEmoji = emoji.isEmoji;
pub const isEmojiPresentation = emoji.isEmojiPresentation;
pub const isExtendedPictographic = emoji.isExtendedPictographic;
pub const isEmojiModifier = emoji.isEmojiModifier;
pub const isZWJ = emoji.isZWJ;
pub const isVS15 = emoji.isVS15;
pub const isVS16 = emoji.isVS16;
pub const isRegionalIndicator = emoji.isRegionalIndicator;
pub const scanEmoji = emoji.scanEmoji;
pub const emojiClusterLen = emoji.emojiClusterLen;
pub const EmojiCluster = emoji.Cluster;

pub const max_depth = 64;
pub const max_stops = 64;
pub const max_paint_nodes: u32 = 1 << 16;

pub const Error = error{
    /// The glyph has no COLR v0 or v1 record (or the font has no COLR table).
    NoColorGlyph,
    /// Out-of-bounds offset, null offset where one is required, unknown paint format, or a
    /// PaintColrGlyph pointing at a glyph without a v1 record.
    Malformed,
    /// Paint graph deeper than `max_depth` (also catches PaintColrLayers cycles).
    DepthExceeded,
    /// PaintColrGlyph cycle.
    Cycle,
    /// More than `max_paint_nodes` paint nodes visited (exponential DAG fan-out).
    TooComplex,
};

pub const Kind = enum { none, colr_v0, colr_v1, bitmap_png, bitmap_other };

/// STRAIGHT (non-premultiplied) sRGB colour; same layout as `raster.Color`.
pub const Rgba = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    pub const transparent: Rgba = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
};

pub const Point = struct { x: f32, y: f32 };

/// COLRv1 Affine2x3: x' = xx*x + xy*y + dx ; y' = yx*x + yy*y + dy (font units, y-up).
/// Same field order as `raster.Affine{ .a = xx, .b = yx, .c = xy, .d = yy, .e = dx, .f = dy }`.
pub const Affine2x3 = struct {
    xx: f32 = 1,
    yx: f32 = 0,
    xy: f32 = 0,
    yy: f32 = 1,
    dx: f32 = 0,
    dy: f32 = 0,

    pub const identity: Affine2x3 = .{};

    /// `self * o`: `o` is applied to the point first.
    pub fn mul(self: Affine2x3, o: Affine2x3) Affine2x3 {
        return .{
            .xx = self.xx * o.xx + self.xy * o.yx,
            .yx = self.yx * o.xx + self.yy * o.yx,
            .xy = self.xx * o.xy + self.xy * o.yy,
            .yy = self.yx * o.xy + self.yy * o.yy,
            .dx = self.xx * o.dx + self.xy * o.dy + self.dx,
            .dy = self.yx * o.dx + self.yy * o.dy + self.dy,
        };
    }

    pub fn apply(self: Affine2x3, p: Point) Point {
        return .{ .x = self.xx * p.x + self.xy * p.y + self.dx, .y = self.yx * p.x + self.yy * p.y + self.dy };
    }

    /// null when singular / not finite.
    pub fn invert(self: Affine2x3) ?Affine2x3 {
        const det = self.xx * self.yy - self.yx * self.xy;
        if (!std.math.isFinite(det) or det == 0) return null;
        const inv = 1.0 / det;
        const r: Affine2x3 = .{
            .xx = self.yy * inv,
            .yx = -self.yx * inv,
            .xy = -self.xy * inv,
            .yy = self.xx * inv,
            .dx = (self.xy * self.dy - self.yy * self.dx) * inv,
            .dy = (self.yx * self.dx - self.xx * self.dy) * inv,
        };
        if (!std.math.isFinite(r.xx + r.yx + r.xy + r.yy + r.dx + r.dy)) return null;
        return r;
    }
};

/// Axis-aligned box in the CURRENT transform space (font units, y-up).
pub const ClipBox = struct { x_min: f32, y_min: f32, x_max: f32, y_max: f32 };

pub const Extend = enum(u8) { pad, repeat, reflect };

/// ItemVariationStore evaluator: raw delta (in the field's stored units) of item (outer, inner) of
/// `store` at normalized `coords`. Pass `&variations.itemDelta` (src/font/variations.zig) to
/// `paintColrVar` to apply variable-COLR deltas. color.zig never imports it, so the store code
/// stays out of the binary unless the caller links it.
pub const DeltaFn = *const fn (store: []const u8, outer: u32, inner: u32, coords: []const i16) f32;

/// `offset` as stored in the font (may lie outside 0..1; stops are sorted ascending, stable).
/// `color` already includes the stop alpha and the CPAL alpha.
pub const ColorStop = struct { offset: f32, color: Rgba };

/// COLRv1 composite modes (numeric values = font encoding).
pub const CompositeMode = enum(u8) {
    clear,
    src,
    dest,
    src_over,
    dest_over,
    src_in,
    dest_in,
    src_out,
    dest_out,
    src_atop,
    dest_atop,
    xor,
    plus,
    screen,
    overlay,
    darken,
    lighten,
    color_dodge,
    color_burn,
    hard_light,
    soft_light,
    difference,
    exclusion,
    multiply,
    hsl_hue,
    hsl_saturation,
    hsl_color,
    hsl_luminosity,
};

/// A fill, in the current transform space (font units, y-up). Gradient semantics follow the
/// COLRv1 spec exactly; use `gradientT` + `sampleColorLine` (or `shadePremul`) to evaluate them.
///  * linear: p0..p1 is the colour line, p2 rotates the isolines (they are parallel to p0->p2).
///  * radial: two-point conical between circle (c0, r0) at t=0 and (c1, r1) at t=1.
///  * sweep: angles in DEGREES, counter-clockwise from +x (y-up), t=0 at start, t=1 at end.
/// `stops` is only valid during the `fill` / `fill_glyph` callback (it lives on the walker stack).
pub const Brush = union(enum) {
    solid: Rgba,
    linear: struct { p0: Point, p1: Point, p2: Point, stops: []const ColorStop, extend: Extend },
    radial: struct { c0: Point, r0: f32, c1: Point, r1: f32, stops: []const ColorStop, extend: Extend },
    sweep: struct { c: Point, start_angle: f32, end_angle: f32, stops: []const ColorStop, extend: Extend },
};

/// Paint callbacks (COLRv1 / skrifa `ColorPainter` model). Calls are always balanced, also when
/// `paintColr` returns an error midway (every push gets its pop before the error propagates),
/// so a painter may simply discard its output on error.
///  * push_transform: post-multiply the current transform by `t` (t applies to coordinates first).
///  * push_clip_glyph: intersect the clip with the outline of `gid` (non-zero fill, font units,
///    current transform) — get it with `font.outline(gid, sink)`.
///  * push_clip_box: intersect the clip with the box (current transform).
///  * fill: fill the whole current clip region with `brush` (source-over in the current layer).
///  * fill_glyph (optional, may be null): same as push_clip_glyph(gid); fill(brush); pop_clip().
///  * push_layer: start an isolated transparent layer; pop_layer composites it onto the layer
///    below with the mode given to its push_layer (`src_over` for plain groups).
pub const Painter = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        push_transform: *const fn (ctx: *anyopaque, t: Affine2x3) void,
        pop_transform: *const fn (ctx: *anyopaque) void,
        push_clip_glyph: *const fn (ctx: *anyopaque, gid: u16) void,
        push_clip_box: *const fn (ctx: *anyopaque, box: ClipBox) void,
        pop_clip: *const fn (ctx: *anyopaque) void,
        fill: *const fn (ctx: *anyopaque, brush: *const Brush) void,
        fill_glyph: ?*const fn (ctx: *anyopaque, gid: u16, brush: *const Brush) void = null,
        push_layer: *const fn (ctx: *anyopaque, mode: CompositeMode) void,
        pop_layer: *const fn (ctx: *anyopaque) void,
    };
};

pub const BitmapFormat = enum { png, other };

/// An embedded bitmap glyph (zero-copy; `data` points into the font).
/// Placement (strike pixels, glyph origin = pen position on the baseline):
///   left edge = origin.x + bearing_x, top edge = baseline - bearing_y (bearing_y is y-UP,
///   i.e. positive = above the baseline). At font size S device px: scale = S / ppem.
///   takumi rounds `bearing_x*scale` and `bearing_y*scale` to whole pixels and draws the image
///   scaled by S/ppem_x, S/ppem (see color_example.zig `drawBitmapGlyph`).
pub const Bitmap = struct {
    data: []const u8,
    format: BitmapFormat,
    /// Strike ppem (vertical); `ppem_x` horizontal (equal for sbix).
    ppem: f32,
    ppem_x: f32,
    bearing_x: f32,
    bearing_y: f32,
    /// Image size in strike pixels (from the bitmap metrics or the PNG header; 0 if unknown).
    width: u32,
    height: u32,
    /// sbix graphic type tag ('png ', 'jpg ', 'tiff', ...) or CBDT image format number.
    graphic_type: u32,
};

// ------------------------------------------------------------------------------------------
// Table location

fn tg(comptime s: *const [4]u8) u32 {
    return (@as(u32, s[0]) << 24) | (@as(u32, s[1]) << 16) | (@as(u32, s[2]) << 8) | s[3];
}

inline fn rd24(t: []const u8, off: u32) u32 {
    if (t.len < 3 or off > t.len - 3) return 0;
    return (@as(u32, t[off]) << 16) | (@as(u32, t[off + 1]) << 8) | t[off + 2];
}

inline fn f2dot14(t: []const u8, off: u32) f32 {
    return @as(f32, @floatFromInt(rdi16(t, off))) * (1.0 / 16384.0);
}

inline fn fword(t: []const u8, off: u32) f32 {
    return @floatFromInt(rdi16(t, off));
}

inline fn fixed(t: []const u8, off: u32) f32 {
    return @as(f32, @floatFromInt(@as(i32, @bitCast(rd32(t, off))))) * (1.0 / 65536.0);
}

/// The colour-related tables of one face. Cheap to build (scans the table directory); cache it
/// next to the `Font` when painting many glyphs. Unit tests build it directly from blobs.
pub const ColorTables = struct {
    colr: []const u8 = &.{},
    cpal: []const u8 = &.{},
    cblc: []const u8 = &.{},
    cbdt: []const u8 = &.{},
    sbix: []const u8 = &.{},
    has_svg: bool = false,
    num_glyphs: u16 = 0,

    pub fn init(font: *const Font) ColorTables {
        const data = font.data;
        var dir: u32 = 0;
        if (rd32(data, 0) == tg("ttcf")) {
            // Font does not keep its face index: pick the directory whose 'head' is font.head.
            const head_off: usize = @intFromPtr(font.head.ptr) -% @intFromPtr(data.ptr);
            const n = @min(rd32(data, 8), 1024);
            dir = rd32(data, 12);
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                const d = rd32(data, 12 +| i *| 4);
                if (dirHasTableAt(data, d, tg("head"), head_off)) {
                    dir = d;
                    break;
                }
            }
        }
        var ct = fromDirectory(data, dir);
        ct.num_glyphs = font.num_glyphs;
        return ct;
    }

    /// Reads the sfnt table directory at `dir_off` of `data` (0 for a plain .ttf).
    pub fn fromDirectory(data: []const u8, dir_off: u32) ColorTables {
        var ct: ColorTables = .{};
        const n: u32 = @min(rd16(data, dir_off +| 4), 512);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const rec = dir_off +| 12 +| i * 16;
            if (rec +| 16 > data.len) break;
            const off = rd32(data, rec + 8);
            const len = rd32(data, rec + 12);
            if (off > data.len or len > data.len - off) continue;
            const t = data[off..][0..len];
            switch (rd32(data, rec)) {
                tg("COLR") => ct.colr = t,
                tg("CPAL") => ct.cpal = t,
                tg("CBLC") => ct.cblc = t,
                tg("CBDT") => ct.cbdt = t,
                tg("sbix") => ct.sbix = t,
                tg("SVG ") => ct.has_svg = true,
                tg("maxp") => ct.num_glyphs = rd16(t, 4),
                else => {},
            }
        }
        return ct;
    }

    /// Any colour table we can use (COLR, CBDT+CBLC or sbix)?
    pub fn hasColor(ct: *const ColorTables) bool {
        return ct.colr.len != 0 or (ct.cblc.len != 0 and ct.cbdt.len != 0) or ct.sbix.len != 0;
    }

    pub fn kind(ct: *const ColorTables, gid: u16) Kind {
        if (ct.cblc.len != 0 and ct.cbdt.len != 0) {
            var s: u32 = 0;
            const n = cblcStrikeCount(ct.cblc);
            while (s < n) : (s += 1) {
                if (ct.cblcGlyph(s, gid)) |b| return if (b.format == .png) .bitmap_png else .bitmap_other;
            }
        }
        if (ct.sbix.len != 0) {
            var s: u32 = 0;
            const n = @min(rd32(ct.sbix, 4), 64);
            while (s < n) : (s += 1) {
                if (ct.sbixGlyph(s, gid)) |b| return if (b.format == .png) .bitmap_png else .bitmap_other;
            }
        }
        if (Header.parse(ct.colr)) |h| {
            if (h.v1Base(ct.colr, gid) != null) return .colr_v1;
            if (h.v0Base(ct.colr, gid) != null) return .colr_v0;
        }
        return .none;
    }

    /// See `paintColr` (variation deltas are not applied: use `paintVar`).
    pub fn paint(ct: *const ColorTables, gid: u16, palette: u16, foreground: Rgba, coords: []const i16, painter: Painter) Error!void {
        return ct.paintVar(gid, palette, foreground, coords, null, painter);
    }

    /// See `paintColrVar`.
    pub fn paintVar(ct: *const ColorTables, gid: u16, palette: u16, foreground: Rgba, coords: []const i16, delta_fn: ?DeltaFn, painter: Painter) Error!void {
        const h = Header.parse(ct.colr) orelse return error.NoColorGlyph;
        var w: Walker = .{
            .t = ct.colr,
            .h = h,
            .pal = Palette.get(ct.cpal, palette),
            .fg = foreground,
            .p = painter,
        };
        if (delta_fn != null and coords.len != 0 and h.ivs != 0) {
            w.coords = coords;
            w.delta_fn = delta_fn;
            w.var_store = ct.colr[h.ivs..];
            if (h.vmap != 0) w.var_map = ct.colr[h.vmap..];
        }
        if (h.v1Base(ct.colr, gid)) |po| {
            w.gstack[0] = po;
            w.gn = 1;
            const clip = h.clipBox(ct.colr, gid, &w);
            if (clip) |cb| painter.vtable.push_clip_box(painter.ctx, cb);
            const r = w.paint(po, 0);
            if (clip != null) painter.vtable.pop_clip(painter.ctx);
            return r;
        }
        const v0 = h.v0Base(ct.colr, gid) orelse return error.NoColorGlyph;
        var i: u32 = 0;
        while (i < v0.n) : (i += 1) {
            const rec = h.layers +| (v0.first + i) * 4;
            if (rec +| 4 > ct.colr.len) return error.Malformed;
            const lg = rd16(ct.colr, rec);
            const brush: Brush = .{ .solid = w.pal.color(rd16(ct.colr, rec + 2), 1, foreground) };
            w.fillGlyph(lg, &brush);
        }
    }

    /// COLR v1 ClipBox of `gid` (font units, base values), if the font declares one.
    pub fn clipBox(ct: *const ColorTables, gid: u16) ?ClipBox {
        const h = Header.parse(ct.colr) orelse return null;
        return h.clipBox(ct.colr, gid, null);
    }

    /// Best strike for `ppem` (skrifa rule = what takumi uses: the largest strike <= ppem,
    /// otherwise the smallest one above it; NaN/<=0 picks the largest). CBDT before sbix.
    pub fn bitmap(ct: *const ColorTables, gid: u16, ppem: f32) ?Bitmap {
        const want: f32 = if (ppem > 0) ppem else std.math.floatMax(f32);
        var best: ?Bitmap = null;
        if (ct.cblc.len != 0 and ct.cbdt.len != 0) {
            var s: u32 = 0;
            const n = cblcStrikeCount(ct.cblc);
            while (s < n) : (s += 1) {
                const size: f32 = @floatFromInt(rd8(ct.cblc, 8 + s * 48 + 45));
                if (best != null and !better(size, best.?.ppem, want)) continue;
                if (ct.cblcGlyph(s, gid)) |b| best = b;
            }
            if (best != null) return best;
        }
        if (ct.sbix.len != 0) {
            var s: u32 = 0;
            const n = @min(rd32(ct.sbix, 4), 64);
            while (s < n) : (s += 1) {
                const so = rd32(ct.sbix, 8 + s * 4);
                const size: f32 = @floatFromInt(rd16(ct.sbix, so));
                if (best != null and !better(size, best.?.ppem, want)) continue;
                if (ct.sbixGlyph(s, gid)) |b| best = b;
            }
        }
        return best;
    }

    fn better(size: f32, best: f32, want: f32) bool {
        return (size <= want and size > best) or (best > want and size < best);
    }

    // ---- CBLC / CBDT ----

    fn cblcStrikeCount(cblc: []const u8) u32 {
        const n = rd32(cblc, 4);
        const fit: u32 = if (cblc.len >= 8) @intCast((cblc.len - 8) / 48) else 0;
        return @min(n, fit, 256);
    }

    fn cblcGlyph(ct: *const ColorTables, strike: u32, gid: u16) ?Bitmap {
        const t = ct.cblc;
        const sr = 8 + strike * 48;
        if (gid < rd16(t, sr + 40) or gid > rd16(t, sr + 42)) return null;
        const arr = rd32(t, sr);
        const nsub = @min(rd32(t, sr + 8), 4096);
        var k: u32 = 0;
        while (k < nsub) : (k += 1) {
            const e = arr +| k * 8;
            if (e +| 8 > t.len) return null;
            const first = rd16(t, e);
            const last = rd16(t, e + 2);
            if (gid < first or gid > last) continue;
            const sub = arr +| rd32(t, e + 4);
            if (sub +| 8 > t.len) return null;
            const ifmt = rd16(t, sub);
            const imgfmt = rd16(t, sub + 2);
            const base = rd32(t, sub + 4);
            const i: u32 = gid - first;
            var start: u32 = 0;
            var end: u32 = 0;
            var big: ?u32 = null; // offset of bigGlyphMetrics in CBLC
            switch (ifmt) {
                1 => {
                    const o = sub +| 8 +| i * 4;
                    if (o +| 8 > t.len) return null;
                    start = base +| rd32(t, o);
                    end = base +| rd32(t, o + 4);
                },
                3 => {
                    const o = sub +| 8 +| i * 2;
                    if (o +| 4 > t.len) return null;
                    start = base +| rd16(t, o);
                    end = base +| rd16(t, o + 2);
                },
                2 => {
                    const size = rd32(t, sub +| 8);
                    big = sub +| 12;
                    start = base +| i *| size;
                    end = start +| size;
                },
                4, 5 => {
                    const is4 = ifmt == 4;
                    const ng = rd32(t, if (is4) sub +| 8 else sub +| 20);
                    const arr2: u32 = if (is4) sub +| 12 else sub +| 24;
                    const stride: u32 = if (is4) 4 else 2;
                    const cnt: u32 = @min(ng, @as(u32, @intCast(t.len)) / stride);
                    // binary search glyph id
                    var lo: u32 = 0;
                    var hi: u32 = cnt;
                    var found: ?u32 = null;
                    while (lo < hi) {
                        const mid = lo + (hi - lo) / 2;
                        const g = rd16(t, arr2 +| mid * stride);
                        if (g == gid) {
                            found = mid;
                            break;
                        }
                        if (g < gid) lo = mid + 1 else hi = mid;
                    }
                    const idx = found orelse return null;
                    if (is4) {
                        const o = arr2 +| idx * 4;
                        if (o +| 8 > t.len) return null;
                        start = base +| rd16(t, o + 2);
                        end = base +| rd16(t, o + 6);
                    } else {
                        const size = rd32(t, sub +| 8);
                        big = sub +| 12;
                        start = base +| idx *| size;
                        end = start +| size;
                    }
                },
                else => return null,
            }
            if (end <= start or end > ct.cbdt.len) return null;
            const g = ct.cbdt[start..end];
            const ppem_x: f32 = @floatFromInt(rd8(t, sr + 44));
            const ppem_y: f32 = @floatFromInt(rd8(t, sr + 45));
            var b: Bitmap = .{
                .data = &.{},
                .format = .other,
                .ppem = ppem_y,
                .ppem_x = ppem_x,
                .bearing_x = 0,
                .bearing_y = 0,
                .width = 0,
                .height = 0,
                .graphic_type = imgfmt,
            };
            var data_off: u32 = 0;
            switch (imgfmt) {
                17 => {
                    setMetrics(&b, g, 0);
                    data_off = 5; // smallGlyphMetrics, then dataLen
                },
                18 => {
                    setMetrics(&b, g, 0);
                    data_off = 8; // bigGlyphMetrics, then dataLen
                },
                19 => {
                    if (big) |m| setMetrics(&b, t, m);
                    data_off = 0;
                },
                else => {
                    if (big) |m| setMetrics(&b, t, m);
                    b.data = g;
                    return b;
                },
            }
            const len = rd32(g, data_off);
            const ds = data_off + 4;
            if (ds > g.len or len > g.len - ds or len == 0) return null;
            b.data = g[ds..][0..len];
            b.format = .png;
            if (b.width == 0) pngSize(&b);
            return b;
        }
        return null;
    }

    fn setMetrics(b: *Bitmap, t: []const u8, off: u32) void {
        b.height = rd8(t, off);
        b.width = rd8(t, off + 1);
        b.bearing_x = @floatFromInt(@as(i8, @bitCast(rd8(t, off + 2))));
        b.bearing_y = @floatFromInt(@as(i8, @bitCast(rd8(t, off + 3))));
    }

    fn pngSize(b: *Bitmap) void {
        if (b.data.len >= 24 and rd32(b.data, 12) == tg("IHDR")) {
            b.width = @min(rd32(b.data, 16), 1 << 16);
            b.height = @min(rd32(b.data, 20), 1 << 16);
        }
    }

    // ---- sbix ----

    fn sbixGlyph(ct: *const ColorTables, strike: u32, gid: u16) ?Bitmap {
        const t = ct.sbix;
        const so = rd32(t, 8 + strike * 4);
        if (so == 0 or so +| 4 > t.len) return null;
        var g: u32 = gid;
        var hops: u32 = 0;
        while (true) {
            if (ct.num_glyphs != 0 and g >= ct.num_glyphs) return null;
            const o = so +| 4 +| g * 4;
            if (o +| 8 > t.len) return null;
            const start = so +| rd32(t, o);
            const end = so +| rd32(t, o + 4);
            if (end <= start or end > t.len or end - start < 8) return null;
            const d = t[start..end];
            const typ = rd32(d, 4);
            if (typ == tg("dupe")) {
                hops += 1;
                if (hops > 1 or d.len < 10) return null;
                g = rd16(d, 8);
                continue;
            }
            const ppem: f32 = @floatFromInt(rd16(t, so));
            var b: Bitmap = .{
                .data = d[8..],
                .format = if (typ == tg("png ")) .png else .other,
                .ppem = ppem,
                .ppem_x = ppem,
                .bearing_x = fword(d, 0),
                .bearing_y = fword(d, 2),
                .width = 0,
                .height = 0,
                .graphic_type = typ,
            };
            if (b.format == .png) pngSize(&b);
            // sbix origin is the bitmap's bottom-left corner: convert to the top edge
            b.bearing_y += @floatFromInt(b.height);
            return b;
        }
    }
};

fn dirHasTableAt(data: []const u8, dir: u32, tag: u32, off: usize) bool {
    const n: u32 = @min(rd16(data, dir +| 4), 512);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const rec = dir +| 12 +| i * 16;
        if (rec +| 16 > data.len) return false;
        if (rd32(data, rec) == tag) return rd32(data, rec + 8) == off;
    }
    return false;
}

// ------------------------------------------------------------------------------------------
// Public font-level entry points

/// Classifies `gid`: embedded bitmap (CBDT/sbix) first, then COLR v1, then COLR v0 (takumi
/// priority). Scans the table directory each call; use `ColorTables` to cache.
pub fn glyphKind(font: *const Font, gid: u16) Kind {
    const ct = ColorTables.init(font);
    return ct.kind(gid);
}

/// Walks the COLR paint graph of `gid` (v1 BaseGlyphList first, then v0 layers) and calls
/// `painter`. Units = font units, y-up. Colours come from CPAL palette `palette` (out of range ->
/// palette 0); palette index 0xFFFF = `foreground`. The v1 root is wrapped in push_clip_box /
/// pop_clip when the ClipList has a box for `gid`. v0 layers are emitted as
/// `fill_glyph(layer_gid, solid)` (or clip+fill+pop when `fill_glyph` is null).
/// `coords` is ignored here (base values only); use `paintColrVar` to apply variation deltas.
/// Colour fonts must never be synthesised bold/italic (takumi rule) — callers skip synthesis.
pub fn paintColr(font: *const Font, gid: u16, palette: u16, foreground: Rgba, coords: []const i16, painter: Painter) Error!void {
    const ct = ColorTables.init(font);
    return ct.paint(gid, palette, foreground, coords, painter);
}

/// `paintColr` with variation deltas: `coords` = normalized F2Dot14 coordinates of the instance
/// (fvar axis order), `delta_fn` = `&variations.itemDelta`. Applies the COLR ItemVariationStore /
/// DeltaSetIndexMap to every Var* paint, VarColorStop, VarAffine2x3 and ClipBox format 2.
pub fn paintColrVar(font: *const Font, gid: u16, palette: u16, foreground: Rgba, coords: []const i16, delta_fn: ?DeltaFn, painter: Painter) Error!void {
    const ct = ColorTables.init(font);
    return ct.paintVar(gid, palette, foreground, coords, delta_fn, painter);
}

/// Embedded bitmap for `gid` at the best strike for `ppem` (see `ColorTables.bitmap`).
pub fn bitmapGlyph(font: *const Font, gid: u16, ppem: f32) ?Bitmap {
    const ct = ColorTables.init(font);
    return ct.bitmap(gid, ppem);
}

/// COLR v1 ClipBox of `gid` in font units (useful to size an offscreen layer), if declared.
pub fn colrClipBox(font: *const Font, gid: u16) ?ClipBox {
    const ct = ColorTables.init(font);
    return ct.clipBox(gid);
}

/// Number of CPAL palettes (0 without CPAL).
pub fn paletteCount(font: *const Font) u16 {
    const ct = ColorTables.init(font);
    return rd16(ct.cpal, 4);
}

/// CPAL v1 palette selection: the first palette flagged usable with a dark (or light)
/// background; 0 when none is flagged or for CPAL v0.
pub fn findPalette(font: *const Font, dark_background: bool) u16 {
    const ct = ColorTables.init(font);
    return findPaletteIn(ct.cpal, dark_background);
}

fn findPaletteIn(cpal: []const u8, dark_background: bool) u16 {
    if (rd16(cpal, 0) < 1) return 0;
    const np = @min(rd16(cpal, 4), 1024);
    const types = rd32(cpal, 12 + @as(u32, np) * 2);
    if (types == 0) return 0;
    const want: u32 = if (dark_background) 2 else 1;
    var i: u16 = 0;
    while (i < np) : (i += 1) {
        if (rd32(cpal, types +| @as(u32, i) * 4) & want != 0) return i;
    }
    return 0;
}

// ------------------------------------------------------------------------------------------
// CPAL

const Palette = struct {
    recs: []const u8 = &.{},
    n: u32 = 0,

    fn get(cpal: []const u8, index: u16) Palette {
        if (cpal.len < 12) return .{};
        const entries: u32 = rd16(cpal, 2);
        const np = rd16(cpal, 4);
        const idx: u32 = if (index < np) index else 0;
        if (np == 0) return .{};
        const first: u32 = rd16(cpal, 12 + idx * 2);
        const start = rd32(cpal, 8) +| first * 4;
        if (start >= cpal.len) return .{};
        const avail: u32 = @intCast((cpal.len - start) / 4);
        return .{ .recs = cpal[start..], .n = @min(entries, avail) };
    }

    fn color(p: Palette, index: u16, alpha: f32, fg: Rgba) Rgba {
        var c: Rgba = undefined;
        if (index == 0xFFFF) {
            c = fg;
        } else if (index < p.n) {
            const o = @as(u32, index) * 4; // BGRA
            c = .{ .b = p.recs[o], .g = p.recs[o + 1], .r = p.recs[o + 2], .a = p.recs[o + 3] };
        } else return Rgba.transparent;
        if (alpha != 1) {
            const a = clamp01(alpha) * @as(f32, @floatFromInt(c.a)) + 0.5;
            c.a = @intFromFloat(a);
        }
        return c;
    }
};

inline fn clamp01(v: f32) f32 {
    return if (!(v > 0)) 0 else if (v > 1) 1 else v;
}

// ------------------------------------------------------------------------------------------
// COLR

const Header = struct {
    n_base: u32 = 0,
    base: u32 = 0,
    layers: u32 = 0,
    n_layers: u32 = 0,
    bgl: u32 = 0,
    ll: u32 = 0,
    cl: u32 = 0,
    vmap: u32 = 0,
    ivs: u32 = 0,

    fn parse(t: []const u8) ?Header {
        if (t.len < 14) return null;
        const len: u32 = @intCast(@min(t.len, 0x7fff_ffff));
        var h: Header = .{
            .n_base = rd16(t, 2),
            .base = rd32(t, 4),
            .layers = rd32(t, 8),
            .n_layers = rd16(t, 12),
        };
        if (h.base >= len) h.n_base = 0 else h.n_base = @min(h.n_base, (len - h.base) / 6);
        if (h.layers >= len) h.n_layers = 0;
        if (rd16(t, 0) >= 1 and t.len >= 34) {
            h.bgl = rd32(t, 14);
            h.ll = rd32(t, 18);
            h.cl = rd32(t, 22);
            h.vmap = rd32(t, 26);
            h.ivs = rd32(t, 30);
            if (h.vmap +| 4 > len) h.vmap = 0;
            if (h.ivs +| 8 > len) h.ivs = 0;
            if (h.bgl +| 4 > len) h.bgl = 0;
            if (h.ll +| 4 > len) h.ll = 0;
            if (h.cl +| 5 > len) h.cl = 0;
        }
        return h;
    }

    const V0 = struct { first: u32, n: u32 };

    fn v0Base(h: Header, t: []const u8, gid: u16) ?V0 {
        var lo: u32 = 0;
        var hi: u32 = h.n_base;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const r = h.base + mid * 6;
            const g = rd16(t, r);
            if (g == gid) {
                const first: u32 = rd16(t, r + 2);
                const n: u32 = rd16(t, r + 4);
                if (n == 0) return null;
                return .{ .first = first, .n = n };
            }
            if (g < gid) lo = mid + 1 else hi = mid;
        }
        return null;
    }

    /// Absolute offset (in COLR) of the root paint of `gid`.
    fn v1Base(h: Header, t: []const u8, gid: u16) ?u32 {
        if (h.bgl == 0) return null;
        const avail: u32 = @intCast((t.len - h.bgl - 4) / 6);
        var lo: u32 = 0;
        var hi: u32 = @min(rd32(t, h.bgl), avail);
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const r = h.bgl + 4 + mid * 6;
            const g = rd16(t, r);
            if (g == gid) {
                const po = h.bgl +| rd32(t, r + 2);
                return if (po < t.len) po else null;
            }
            if (g < gid) lo = mid + 1 else hi = mid;
        }
        return null;
    }

    fn layerPaint(h: Header, t: []const u8, idx: u32) ?u32 {
        if (h.ll == 0 or idx >= rd32(t, h.ll)) return null;
        const o = h.ll +| 4 +| idx *| 4;
        if (o +| 4 > t.len) return null;
        const po = h.ll +| rd32(t, o);
        return if (po < t.len) po else null;
    }

    /// `w` (optional) supplies variation deltas for ClipBox format 2.
    fn clipBox(h: Header, t: []const u8, gid: u16, w: ?*const Walker) ?ClipBox {
        if (h.cl == 0 or rd8(t, h.cl) != 1) return null;
        const avail: u32 = @intCast((t.len - h.cl - 5) / 7);
        const n = @min(rd32(t, h.cl + 1), avail);
        // last record with start <= gid
        var lo: u32 = 0;
        var hi: u32 = n;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (rd16(t, h.cl + 5 + mid * 7) <= gid) lo = mid + 1 else hi = mid;
        }
        if (lo == 0) return null;
        const r = h.cl + 5 + (lo - 1) * 7;
        if (gid > rd16(t, r + 2)) return null;
        const b = h.cl +| rd24(t, r + 4);
        const f = rd8(t, b);
        if ((f != 1 and f != 2) or b +| 9 > t.len) return null;
        if (f == 2 and w != null and b +| 13 <= t.len) {
            var v: [6]f32 = undefined;
            w.?.fields(b + 1, 4, 0, 0, true, &v);
            return .{ .x_min = v[0], .y_min = v[1], .x_max = v[2], .y_max = v[3] };
        }
        return .{ .x_min = fword(t, b + 1), .y_min = fword(t, b + 3), .x_max = fword(t, b + 5), .y_max = fword(t, b + 7) };
    }
};

/// DeltaSetIndexMap lookup -> (outer << 16) | inner; without a map the index is used as is.
/// null = entry out of bounds (no delta).
fn deltaSetIndex(map: []const u8, index: u32) ?u32 {
    if (map.len < 4) return index;
    const format = map[0];
    const entry_format = map[1];
    const count: u32 = if (format == 0) rd16(map, 2) else rd32(map, 2);
    const base: u32 = if (format == 0) 4 else 6;
    if (count == 0) return index;
    const i = @min(index, count - 1);
    const size: u32 = ((entry_format >> 4) & 3) + 1;
    const p = base +| i *| size;
    if (p > map.len or size > map.len - p) return null;
    var v: u32 = 0;
    for (map[p..][0..size]) |byte| v = (v << 8) | byte;
    const inner_bits: u5 = @intCast((entry_format & 0xf) + 1);
    const inner = v & ((@as(u32, 1) << inner_bits) - 1);
    const outer = v >> inner_bits;
    return (outer << 16) | (inner & 0xffff);
}

/// Minimum byte size of each paint format (index = format).
const paint_size = [33]u8{ 0, 6, 5, 9, 16, 20, 16, 20, 12, 16, 6, 3, 7, 7, 8, 12, 8, 12, 12, 16, 6, 10, 10, 14, 6, 10, 10, 14, 8, 12, 12, 16, 8 };

const Walker = struct {
    t: []const u8,
    h: Header,
    pal: Palette,
    fg: Rgba,
    p: Painter,
    budget: u32 = max_paint_nodes,
    coords: []const i16 = &.{},
    delta_fn: ?DeltaFn = null,
    var_store: []const u8 = &.{},
    var_map: []const u8 = &.{},
    gstack: [max_depth + 1]u32 = undefined,
    gn: u32 = 0,

    /// Absolute offset of the child paint referenced by the Offset24 at `off + at`.
    fn child(w: *const Walker, off: u32, at: u32) Error!u32 {
        const rel = rd24(w.t, off + at);
        if (rel == 0) return error.Malformed;
        const c = off +| rel;
        if (c >= w.t.len) return error.Malformed;
        return c;
    }

    fn paint(w: *Walker, off: u32, depth: u32) Error!void {
        if (depth >= max_depth) return error.DepthExceeded;
        if (w.budget == 0) return error.TooComplex;
        w.budget -= 1;
        const t = w.t;
        if (off >= t.len) return error.Malformed;
        const fmt = t[off];
        if (fmt == 0 or fmt > 32 or off +| paint_size[fmt] > t.len) return error.Malformed;
        const vt = w.p.vtable;
        const ctx = w.p.ctx;
        switch (fmt) {
            1 => {
                const n: u32 = t[off + 1];
                const first = rd32(t, off + 2);
                var i: u32 = 0;
                while (i < n) : (i += 1) {
                    const lp = w.h.layerPaint(t, first +| i) orelse return error.Malformed;
                    try w.paint(lp, depth + 1);
                }
            },
            2...9 => w.fillPaint(off, null),
            10 => {
                const c = try w.child(off, 1);
                const gid = rd16(t, off + 4);
                const cf = t[c];
                if (cf >= 2 and cf <= 9 and vt.fill_glyph != null and c +| paint_size[cf] <= t.len) {
                    if (w.budget == 0) return error.TooComplex;
                    w.budget -= 1;
                    w.fillPaint(c, gid);
                    return;
                }
                vt.push_clip_glyph(ctx, gid);
                const r = w.paint(c, depth + 1);
                vt.pop_clip(ctx);
                return r;
            },
            11 => {
                const gid = rd16(t, off + 1);
                const po = w.h.v1Base(t, gid) orelse return error.Malformed;
                for (w.gstack[0..w.gn]) |g| if (g == po) return error.Cycle;
                if (w.gn >= w.gstack.len) return error.DepthExceeded;
                w.gstack[w.gn] = po;
                w.gn += 1;
                defer w.gn -= 1;
                const clip = w.h.clipBox(t, gid, w);
                if (clip) |cb| vt.push_clip_box(ctx, cb);
                const r = w.paint(po, depth + 1);
                if (clip != null) vt.pop_clip(ctx);
                return r;
            },
            12...31 => {
                const m = try w.transformOf(off, fmt);
                const c = try w.child(off, 1);
                vt.push_transform(ctx, m);
                const r = w.paint(c, depth + 1);
                vt.pop_transform(ctx);
                return r;
            },
            32 => {
                const src = try w.child(off, 1);
                const back = try w.child(off, 5);
                const mraw = t[off + 4];
                const mode: CompositeMode = if (mraw <= @intFromEnum(CompositeMode.hsl_luminosity)) @enumFromInt(mraw) else .src_over;
                vt.push_layer(ctx, .src_over);
                var r = w.paint(back, depth + 1);
                if (r) |_| {
                    vt.push_layer(ctx, mode);
                    r = w.paint(src, depth + 1);
                    vt.pop_layer(ctx);
                } else |_| {}
                vt.pop_layer(ctx);
                return r;
            },
            else => return error.Malformed,
        }
    }

    /// Reads `n` consecutive 2-byte fields at `at` (bit i of `f2` = F2DOT14, of `uf` = UFWORD,
    /// else FWORD) into `out`; for Var* tables adds the deltas of varIndexBase (at at + 2n) + i.
    fn fields(w: *const Walker, at: u32, n: u32, f2: u32, uf: u32, is_var: bool, out: *[6]f32) void {
        const t = w.t;
        const base = if (is_var) rd32(t, at + 2 * n) else 0xFFFF_FFFF;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const bit = @as(u32, 1) << @intCast(i);
            const o = at + 2 * i;
            var v: f32 = if (uf & bit != 0) @floatFromInt(rd16(t, o)) else fword(t, o);
            v += w.delta(base, i);
            out[i] = if (f2 & bit != 0) v * (1.0 / 16384.0) else v;
        }
    }

    /// Variation delta (raw stored units) of item varIndexBase + k; 0 without coords / store.
    fn delta(w: *const Walker, base: u32, k: u32) f32 {
        if (base == 0xFFFF_FFFF or w.coords.len == 0) return 0;
        const df = w.delta_fn orelse return 0;
        const idx = deltaSetIndex(w.var_map, base +% k) orelse return 0;
        return df(w.var_store, idx >> 16, idx & 0xffff, w.coords);
    }

    fn transformOf(w: *const Walker, off: u32, fmt: u8) Error!Affine2x3 {
        const t = w.t;
        // even formats are the non-variable ones; Var* share the layout (+ varIndexBase)
        const base = fmt & ~@as(u8, 1);
        const is_var = fmt & 1 != 0;
        var v: [6]f32 = undefined;
        var m: Affine2x3 = .{};
        var center: ?Point = null;
        switch (base) {
            12 => {
                const a = off +| rd24(t, off + 4);
                if (rd24(t, off + 4) == 0 or a +| (if (is_var) @as(u32, 28) else 24) > t.len) return error.Malformed;
                const vb = if (is_var) rd32(t, a + 24) else 0xFFFF_FFFF;
                var i: u32 = 0;
                while (i < 6) : (i += 1) v[i] = fixed(t, a + 4 * i) + w.delta(vb, i) * (1.0 / 65536.0);
                m = .{ .xx = v[0], .yx = v[1], .xy = v[2], .yy = v[3], .dx = v[4], .dy = v[5] };
            },
            14 => {
                w.fields(off + 4, 2, 0, 0, is_var, &v);
                m = .{ .dx = v[0], .dy = v[1] };
            },
            16, 18 => {
                w.fields(off + 4, if (base == 18) 4 else 2, 3, 0, is_var, &v);
                m = .{ .xx = v[0], .yy = v[1] };
                if (base == 18) center = .{ .x = v[2], .y = v[3] };
            },
            20, 22 => {
                w.fields(off + 4, if (base == 22) 3 else 1, 1, 0, is_var, &v);
                m = .{ .xx = v[0], .yy = v[0] };
                if (base == 22) center = .{ .x = v[1], .y = v[2] };
            },
            24, 26 => {
                w.fields(off + 4, if (base == 26) 3 else 1, 1, 0, is_var, &v);
                const sc = sinCos(v[0] * std.math.pi);
                m = .{ .xx = sc[1], .yx = sc[0], .xy = -sc[0], .yy = sc[1] };
                if (base == 26) center = .{ .x = v[1], .y = v[2] };
            },
            28, 30 => {
                w.fields(off + 4, if (base == 30) 4 else 2, 3, 0, is_var, &v);
                const sx = sinCos(v[0] * std.math.pi);
                const sy = sinCos(v[1] * std.math.pi);
                m = .{ .xy = -sx[0] / sx[1], .yx = sy[0] / sy[1] };
                if (base == 30) center = .{ .x = v[2], .y = v[3] };
            },
            else => return error.Malformed,
        }
        if (center) |c| {
            // translate(c) * m * translate(-c)
            m.dx = c.x - (m.xx * c.x + m.xy * c.y);
            m.dy = c.y - (m.yx * c.x + m.yy * c.y);
        }
        return m;
    }

    fn fillGlyph(w: *Walker, gid: u16, brush: *const Brush) void {
        const vt = w.p.vtable;
        if (vt.fill_glyph) |fg| {
            fg(w.p.ctx, gid, brush);
        } else {
            vt.push_clip_glyph(w.p.ctx, gid);
            vt.fill(w.p.ctx, brush);
            vt.pop_clip(w.p.ctx);
        }
    }

    /// Builds the brush of a fill paint (formats 2..9, size already checked) and emits it.
    /// noinline: keeps the colour-stop buffer out of the recursive `paint` frame.
    noinline fn fillPaint(w: *Walker, off: u32, gid: ?u16) void {
        const t = w.t;
        const fmt = t[off];
        var buf: [max_stops]ColorStop = undefined;
        const is_var = fmt & 1 != 0;
        var v: [6]f32 = undefined;
        const brush: Brush = switch (fmt) {
            2, 3 => blk: {
                const vb = if (is_var) rd32(t, off + 5) else 0xFFFF_FFFF;
                const alpha = (fword(t, off + 3) + w.delta(vb, 0)) * (1.0 / 16384.0);
                break :blk .{ .solid = w.pal.color(rd16(t, off + 1), alpha, w.fg) };
            },
            4, 5 => blk: {
                const cl = w.colorLine(off, is_var, &buf);
                w.fields(off + 4, 6, 0, 0, is_var, &v);
                break :blk .{ .linear = .{
                    .p0 = .{ .x = v[0], .y = v[1] },
                    .p1 = .{ .x = v[2], .y = v[3] },
                    .p2 = .{ .x = v[4], .y = v[5] },
                    .stops = cl.stops,
                    .extend = cl.extend,
                } };
            },
            6, 7 => blk: {
                const cl = w.colorLine(off, is_var, &buf);
                w.fields(off + 4, 6, 0, 0b100100, is_var, &v);
                break :blk .{ .radial = .{
                    .c0 = .{ .x = v[0], .y = v[1] },
                    .r0 = @max(v[2], 0),
                    .c1 = .{ .x = v[3], .y = v[4] },
                    .r1 = @max(v[5], 0),
                    .stops = cl.stops,
                    .extend = cl.extend,
                } };
            },
            else => blk: {
                const cl = w.colorLine(off, is_var, &buf);
                w.fields(off + 4, 4, 0b1100, 0, is_var, &v);
                break :blk .{ .sweep = .{
                    .c = .{ .x = v[0], .y = v[1] },
                    .start_angle = v[2] * 180,
                    .end_angle = v[3] * 180,
                    .stops = cl.stops,
                    .extend = cl.extend,
                } };
            },
        };
        if (gid) |g| w.fillGlyph(g, &brush) else w.p.vtable.fill(w.p.ctx, &brush);
    }

    const Line = struct { stops: []const ColorStop, extend: Extend };

    fn colorLine(w: *const Walker, paint_off: u32, is_var: bool, buf: *[max_stops]ColorStop) Line {
        const t = w.t;
        const rel = rd24(t, paint_off + 1);
        const cl = paint_off +| rel;
        if (rel == 0 or cl +| 3 > t.len) return .{ .stops = buf[0..0], .extend = .pad };
        const ext: Extend = switch (t[cl]) {
            1 => .repeat,
            2 => .reflect,
            else => .pad,
        };
        const stride: u32 = if (is_var) 10 else 6;
        const avail: u32 = @intCast((t.len - cl - 3) / stride);
        const n = @min(rd16(t, cl + 1), avail, max_stops);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const s = cl + 3 + i * stride;
            const vb = if (is_var) rd32(t, s + 6) else 0xFFFF_FFFF;
            const st: ColorStop = .{
                .offset = (fword(t, s) + w.delta(vb, 0)) * (1.0 / 16384.0),
                .color = w.pal.color(rd16(t, s + 2), (fword(t, s + 4) + w.delta(vb, 1)) * (1.0 / 16384.0), w.fg),
            };
            // stable insertion sort by offset
            var j = i;
            while (j > 0 and buf[j - 1].offset > st.offset) : (j -= 1) buf[j] = buf[j - 1];
            buf[j] = st;
        }
        return .{ .stops = buf[0..n], .extend = ext };
    }
};

// ------------------------------------------------------------------------------------------
// Brush evaluation helpers (for painters)

/// `{ sin, cos }` (f32 polynomial; no libm). |err| < 2e-7 for |rad| < 1e4.
pub fn sinCos(rad: f32) [2]f32 {
    if (!std.math.isFinite(rad) or @abs(rad) > 1.0e6) return .{ 0, 1 };
    const q = @round(rad * (2.0 / std.math.pi));
    const r = (rad - q * 1.5707963705062866) - q * -4.371139000186241e-8;
    const r2 = r * r;
    const s = r + r * r2 * (-1.6666654611e-1 + r2 * (8.3321608736e-3 + r2 * -1.9515295891e-4));
    const c = 1.0 - 0.5 * r2 + r2 * r2 * (4.166664568298827e-2 + r2 * (-1.388731625493765e-3 + r2 * 2.443315711809948e-5));
    const qi: i32 = @intFromFloat(q);
    return switch (qi & 3) {
        0 => .{ s, c },
        1 => .{ c, -s },
        2 => .{ -s, -c },
        else => .{ -c, s },
    };
}

/// atan2 in radians, range (-pi, pi]; |err| < 2e-5 rad.
pub fn atan2(y: f32, x: f32) f32 {
    const ax = @abs(x);
    const ay = @abs(y);
    if (ax == 0 and ay == 0) return 0;
    const swap = ay > ax;
    const z = if (swap) ax / ay else ay / ax;
    const z2 = z * z;
    var a = z * (0.99997726 + z2 * (-0.33262347 + z2 * (0.19354346 + z2 * (-0.11643287 + z2 * (0.05265332 + z2 * -0.01172120)))));
    if (swap) a = std.math.pi / 2.0 - a;
    if (x < 0) a = std.math.pi - a;
    return if (y < 0) -a else a;
}

/// Effective linear gradient end point: p1 projected onto the line through p0 perpendicular to
/// p0->p2 (COLRv1 spec). Returns p1 unchanged when p0 == p2.
pub fn linearEnd(p0: Point, p1: Point, p2: Point) Point {
    const nx = p2.y - p0.y; // perpendicular to p0->p2
    const ny = -(p2.x - p0.x);
    const nn = nx * nx + ny * ny;
    if (!(nn > 0)) return p1;
    const k = ((p1.x - p0.x) * nx + (p1.y - p0.y) * ny) / nn;
    return .{ .x = p0.x + nx * k, .y = p0.y + ny * k };
}

/// Colour-line parameter t of a gradient brush at point `p` (brush space = font units of the
/// fill). null = undefined there (radial outside the cone, degenerate geometry); paint nothing.
pub fn gradientT(brush: *const Brush, p: Point) ?f32 {
    switch (brush.*) {
        .solid => return 0,
        .linear => |g| {
            const e = linearEnd(g.p0, g.p1, g.p2);
            const dx = e.x - g.p0.x;
            const dy = e.y - g.p0.y;
            const dd = dx * dx + dy * dy;
            if (!(dd > 0)) return null;
            return ((p.x - g.p0.x) * dx + (p.y - g.p0.y) * dy) / dd;
        },
        .radial => |g| {
            const cdx = g.c1.x - g.c0.x;
            const cdy = g.c1.y - g.c0.y;
            const pdx = p.x - g.c0.x;
            const pdy = p.y - g.c0.y;
            const dr = g.r1 - g.r0;
            const a = cdx * cdx + cdy * cdy - dr * dr;
            const b = pdx * cdx + pdy * cdy + g.r0 * dr;
            const c = pdx * pdx + pdy * pdy - g.r0 * g.r0;
            if (@abs(a) < 1e-6 * @max(1, cdx * cdx + cdy * cdy + dr * dr)) {
                if (b == 0) return null;
                const t = c / (2 * b);
                return if (g.r0 + t * dr >= 0) t else null;
            }
            const disc = b * b - a * c;
            if (disc < 0) return null;
            const s = @sqrt(disc);
            const t1 = (b + s) / a;
            const t2 = (b - s) / a;
            const hi = @max(t1, t2);
            const lo = @min(t1, t2);
            if (g.r0 + hi * dr >= 0) return hi;
            if (g.r0 + lo * dr >= 0) return lo;
            return null;
        },
        .sweep => |g| {
            const span = g.end_angle - g.start_angle;
            if (span == 0) return null;
            var deg = atan2(p.y - g.c.y, p.x - g.c.x) * (180.0 / std.math.pi);
            if (deg < 0) deg += 360;
            return (deg - g.start_angle) / span;
        },
    }
}

fn applyExtend(t: f32, e: Extend) f32 {
    switch (e) {
        .pad => return clamp01(t),
        .repeat => return t - @floor(t),
        .reflect => {
            const u = t - 2 * @floor(t * 0.5); // [0, 2)
            return if (u > 1) 2 - u else u;
        },
    }
}

/// Premultiplied RGBA as f32 0..255.
pub const PremulF = [4]f32;

fn premulF(c: Rgba) PremulF {
    const a: f32 = @floatFromInt(c.a);
    const k = a / 255.0;
    return .{ @as(f32, @floatFromInt(c.r)) * k, @as(f32, @floatFromInt(c.g)) * k, @as(f32, @floatFromInt(c.b)) * k, a };
}

/// Colour at parameter `t` of a colour line: extend applies over [first stop, last stop]
/// (like FreeType/Skia stop normalisation), interpolation in premultiplied space.
/// Empty stops -> transparent.
pub fn sampleColorLine(stops: []const ColorStop, extend: Extend, t_in: f32) PremulF {
    if (stops.len == 0 or std.math.isNan(t_in)) return .{ 0, 0, 0, 0 };
    const o0 = stops[0].offset;
    const o1 = stops[stops.len - 1].offset;
    const span = o1 - o0;
    if (!(span > 0)) return premulF(if (t_in < o0) stops[0].color else stops[stops.len - 1].color);
    const u = applyExtend((t_in - o0) / span, extend);
    const t = o0 + u * span;
    if (t <= o0) return premulF(stops[0].color);
    var i: usize = 1;
    while (i < stops.len) : (i += 1) {
        const b = stops[i];
        if (t <= b.offset) {
            const a = stops[i - 1];
            const d = b.offset - a.offset;
            const f: f32 = if (d > 0) (t - a.offset) / d else 1;
            const ca = premulF(a.color);
            const cb = premulF(b.color);
            return .{ ca[0] + (cb[0] - ca[0]) * f, ca[1] + (cb[1] - ca[1]) * f, ca[2] + (cb[2] - ca[2]) * f, ca[3] + (cb[3] - ca[3]) * f };
        }
    }
    return premulF(stops[stops.len - 1].color);
}

/// Premultiplied RGBA8 packed little-endian (byte order r, g, b, a = `raster.Pixmap` layout) of
/// `brush` at brush-space point `p`; 0 (transparent) where the gradient is undefined.
pub fn shadePremul(brush: *const Brush, p: Point) u32 {
    const c: PremulF = switch (brush.*) {
        .solid => |s| premulF(s),
        inline .linear, .radial, .sweep => |g| blk: {
            const t = gradientT(brush, p) orelse return 0;
            break :blk sampleColorLine(g.stops, g.extend, t);
        },
    };
    var out: u32 = 0;
    inline for (0..4) |k| {
        const v: u32 = @intFromFloat(@min(@max(c[k] + 0.5, 0), 255));
        out |= v << (8 * k);
    }
    return out;
}

/// Device-space end points of a linear brush whose brush space maps to device space by `m`
/// (affine). The returned (p0, p1) define t = proj(p - p0, p1 - p0) with PERPENDICULAR isolines in
/// device space, so a CSS-style linear shader (`raster.Paint.linear`) reproduces the brush
/// exactly (stops need remapping when they are not within [0, 1]). null when degenerate.
pub fn linearDevice(p0: Point, p1: Point, p2: Point, m: Affine2x3) ?[2]Point {
    const e = linearEnd(p0, p1, p2);
    const inv = m.invert() orelse return null;
    // t(q) = dot(inv(q) - p0, d) / |d|^2 is affine in q: gradient g = inv^T d / |d|^2
    const dx = e.x - p0.x;
    const dy = e.y - p0.y;
    const dd = dx * dx + dy * dy;
    if (!(dd > 0)) return null;
    const gx = (inv.xx * dx + inv.yx * dy) / dd;
    const gy = (inv.xy * dx + inv.yy * dy) / dd;
    const gg = gx * gx + gy * gy;
    if (!(gg > 0)) return null;
    const q0 = m.apply(p0);
    return .{ q0, .{ .x = q0.x + gx / gg, .y = q0.y + gy / gg } };
}

// ------------------------------------------------------------------------------------------
// Tests (synthetic table blobs; no files outside src/)

const testing = std.testing;

const Blob = struct {
    buf: [4096]u8 = undefined,
    n: u32 = 0,
    fn u8_(b: *Blob, v: u8) void {
        b.buf[b.n] = v;
        b.n += 1;
    }
    fn u16_(b: *Blob, v: u16) void {
        b.u8_(@intCast(v >> 8));
        b.u8_(@intCast(v & 0xff));
    }
    fn i16_(b: *Blob, v: i16) void {
        b.u16_(@bitCast(v));
    }
    fn u24_(b: *Blob, v: u32) void {
        b.u8_(@intCast((v >> 16) & 0xff));
        b.u16_(@intCast(v & 0xffff));
    }
    fn u32_(b: *Blob, v: u32) void {
        b.u16_(@intCast(v >> 16));
        b.u16_(@intCast(v & 0xffff));
    }
    fn f2(b: *Blob, v: f32) void {
        b.i16_(@intFromFloat(v * 16384));
    }
    fn set24(b: *Blob, at: u32, v: u32) void {
        b.buf[at] = @intCast((v >> 16) & 0xff);
        b.buf[at + 1] = @intCast((v >> 8) & 0xff);
        b.buf[at + 2] = @intCast(v & 0xff);
    }
    fn set32(b: *Blob, at: u32, v: u32) void {
        b.set24(at + 1, v & 0xffffff);
        b.buf[at] = @intCast(v >> 24);
    }
    fn bytes(b: *const Blob) []const u8 {
        return b.buf[0..b.n];
    }
};

/// Records painter calls as a compact text log and checks push/pop balance.
const Recorder = struct {
    log: [4096]u8 = undefined,
    n: usize = 0,
    depth_t: i32 = 0,
    depth_c: i32 = 0,
    depth_l: i32 = 0,
    bad: bool = false,
    fills: u32 = 0,

    fn put(r: *Recorder, s: []const u8) void {
        if (r.n + s.len > r.log.len) return;
        @memcpy(r.log[r.n..][0..s.len], s);
        r.n += s.len;
    }
    fn putInt(r: *Recorder, v: i64) void {
        var tmp: [24]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return;
        r.put(s);
    }
    fn self(ctx: *anyopaque) *Recorder {
        return @ptrCast(@alignCast(ctx));
    }
    fn pushT(ctx: *anyopaque, t: Affine2x3) void {
        const r = self(ctx);
        r.depth_t += 1;
        r.put("T(");
        r.putInt(@intFromFloat(@round(t.dx)));
        r.put(",");
        r.putInt(@intFromFloat(@round(t.dy)));
        r.put(")");
    }
    fn popT(ctx: *anyopaque) void {
        const r = self(ctx);
        r.depth_t -= 1;
        if (r.depth_t < 0) r.bad = true;
        r.put("t");
    }
    fn clipG(ctx: *anyopaque, gid: u16) void {
        const r = self(ctx);
        r.depth_c += 1;
        r.put("G");
        r.putInt(gid);
    }
    fn clipB(ctx: *anyopaque, b: ClipBox) void {
        const r = self(ctx);
        r.depth_c += 1;
        r.put("B");
        r.putInt(@intFromFloat(b.x_max));
    }
    fn popC(ctx: *anyopaque) void {
        const r = self(ctx);
        r.depth_c -= 1;
        if (r.depth_c < 0) r.bad = true;
        r.put("c");
    }
    fn putBrush(r: *Recorder, b: *const Brush) void {
        r.fills += 1;
        switch (b.*) {
            .solid => |c| {
                r.put("S");
                r.putInt(c.r);
                r.put("/");
                r.putInt(c.a);
            },
            .linear => |g| {
                r.put("L");
                r.putInt(@intCast(g.stops.len));
            },
            .radial => |g| {
                r.put("R");
                r.putInt(@intCast(g.stops.len));
            },
            .sweep => |g| {
                r.put("W");
                r.putInt(@intCast(g.stops.len));
            },
        }
    }
    fn fill(ctx: *anyopaque, b: *const Brush) void {
        const r = self(ctx);
        r.put("F");
        r.putBrush(b);
    }
    fn fillG(ctx: *anyopaque, gid: u16, b: *const Brush) void {
        const r = self(ctx);
        r.put("g");
        r.putInt(gid);
        r.putBrush(b);
    }
    fn pushL(ctx: *anyopaque, m: CompositeMode) void {
        const r = self(ctx);
        r.depth_l += 1;
        r.put("[");
        r.putInt(@intFromEnum(m));
    }
    fn popL(ctx: *anyopaque) void {
        const r = self(ctx);
        r.depth_l -= 1;
        if (r.depth_l < 0) r.bad = true;
        r.put("]");
    }
    const vt_fast: Painter.VTable = .{ .push_transform = pushT, .pop_transform = popT, .push_clip_glyph = clipG, .push_clip_box = clipB, .pop_clip = popC, .fill = fill, .fill_glyph = fillG, .push_layer = pushL, .pop_layer = popL };
    const vt_plain: Painter.VTable = .{ .push_transform = pushT, .pop_transform = popT, .push_clip_glyph = clipG, .push_clip_box = clipB, .pop_clip = popC, .fill = fill, .push_layer = pushL, .pop_layer = popL };
    fn painter(r: *Recorder, fast: bool) Painter {
        return .{ .ctx = r, .vtable = if (fast) &vt_fast else &vt_plain };
    }
    fn str(r: *const Recorder) []const u8 {
        return r.log[0..r.n];
    }
    fn balanced(r: *const Recorder) bool {
        return !r.bad and r.depth_t == 0 and r.depth_c == 0 and r.depth_l == 0;
    }
};

/// CPAL v1 with 2 palettes x 2 entries; palette 1 flagged dark-background.
fn testCpal(b: *Blob) void {
    b.u16_(1); // version
    b.u16_(2); // entries
    b.u16_(2); // palettes
    b.u16_(4); // color records
    b.u32_(28); // records offset
    b.u16_(0);
    b.u16_(2); // record indices
    b.u32_(44); // palette types offset (28 + 16)
    b.u32_(0);
    b.u32_(0);
    // records (BGRA) @28: pal0 = red, green ; pal1 = blue, white(50% alpha)
    for ([_][4]u8{ .{ 0, 0, 255, 255 }, .{ 0, 255, 0, 255 }, .{ 255, 0, 0, 255 }, .{ 255, 255, 255, 128 } }) |c| for (c) |v| b.u8_(v);
    b.u32_(1); // pal0 light
    b.u32_(2); // pal1 dark
}

test "CPAL palettes" {
    var cp: Blob = .{};
    testCpal(&cp);
    const p0 = Palette.get(cp.bytes(), 0);
    const red = p0.color(0, 1, Rgba.transparent);
    try testing.expectEqual(@as(u8, 255), red.r);
    try testing.expectEqual(@as(u8, 0), red.b);
    const p1 = Palette.get(cp.bytes(), 1);
    try testing.expectEqual(@as(u8, 255), p1.color(0, 1, Rgba.transparent).b);
    try testing.expectEqual(@as(u8, 64), p1.color(1, 0.5, Rgba.transparent).a);
    // out-of-range palette -> 0, out-of-range entry -> transparent, 0xFFFF -> foreground
    try testing.expectEqual(@as(u8, 255), Palette.get(cp.bytes(), 9).color(0, 1, Rgba.transparent).r);
    try testing.expectEqual(@as(u8, 0), p0.color(5, 1, .{ .r = 1, .g = 2, .b = 3, .a = 4 }).a);
    try testing.expectEqual(@as(u8, 7), p0.color(0xFFFF, 1, .{ .r = 7, .g = 2, .b = 3, .a = 255 }).r);
    try testing.expectEqual(@as(u16, 1), findPaletteIn(cp.bytes(), true));
    try testing.expectEqual(@as(u16, 0), findPaletteIn(cp.bytes(), false));
}

/// COLR v0: glyph 5 -> layers (1, pal 0), (2, 0xFFFF); glyph 9 -> (3, pal 1).
fn testColrV0(b: *Blob) void {
    b.u16_(0);
    b.u16_(2);
    b.u32_(14);
    b.u32_(26);
    b.u16_(3);
    // base records @14
    b.u16_(5);
    b.u16_(0);
    b.u16_(2);
    b.u16_(9);
    b.u16_(2);
    b.u16_(1);
    // layers @26
    b.u16_(1);
    b.u16_(0);
    b.u16_(2);
    b.u16_(0xFFFF);
    b.u16_(3);
    b.u16_(1);
}

test "COLR v0 layers" {
    var cp: Blob = .{};
    testCpal(&cp);
    var co: Blob = .{};
    testColrV0(&co);
    const ct: ColorTables = .{ .colr = co.bytes(), .cpal = cp.bytes() };
    try testing.expectEqual(Kind.colr_v0, ct.kind(5));
    try testing.expectEqual(Kind.none, ct.kind(6));
    var r: Recorder = .{};
    try ct.paint(5, 0, .{ .r = 9, .g = 9, .b = 9, .a = 255 }, &.{}, r.painter(true));
    try testing.expectEqualStrings("g1S255/255g2S9/255", r.str());
    var r2: Recorder = .{};
    try ct.paint(9, 0, Rgba.transparent, &.{}, r2.painter(false));
    try testing.expectEqualStrings("G3F", r2.str()[0..3]);
    try testing.expect(r2.balanced());
    try testing.expectError(error.NoColorGlyph, ct.paint(6, 0, Rgba.transparent, &.{}, r2.painter(false)));
}

/// COLR v1 test font (all Offset24 point forward: parents are emitted before children, then patched).
/// 10 = ColrLayers[ Glyph(3, Solid entry 1 alpha .5), Translate(10,20, Glyph(4, Linear)) ] + ClipBox;
/// 11 = Composite(src = ColrGlyph 10, multiply, backdrop = Radial); 12 = Rotate(ScaleUniform(Sweep));
/// 13 = ColrGlyph(13) (self cycle); 14 = ColrGlyph(15), 15 = ColrGlyph(14) (mutual cycle).
fn testColrV1(b: *Blob) void {
    b.u16_(1);
    for (0..4) |_| b.u16_(0); // numBase, base offset(2), layer offset(2) -> 0 (fixed below)
    b.n = 14;
    for (0..5) |_| b.u32_(0); // bgl, ll, cl, varIndexMap, ivs
    // header is 34 bytes; BaseGlyphList @34
    const bgl = b.n;
    b.set32(14, bgl);
    b.u32_(6);
    var rec: [6]u32 = undefined;
    for ([_]u16{ 10, 11, 12, 13, 14, 15 }, 0..) |g, i| {
        b.u16_(g);
        rec[i] = b.n;
        b.u32_(0);
    }
    const ll = b.n;
    b.set32(18, ll);
    b.u32_(2);
    const ll0 = b.n;
    b.u32_(0);
    const ll1 = b.n;
    b.u32_(0);
    const cl = b.n;
    b.set32(22, cl);
    b.u8_(1);
    b.u32_(1);
    b.u16_(10);
    b.u16_(10);
    b.u24_(12);
    b.u8_(1);
    for ([_]i16{ 0, 0, 500, 600 }) |v| b.i16_(v);

    // glyph 10
    const lay = b.n;
    b.u8_(1);
    b.u8_(2);
    b.u32_(0);
    const g3 = b.n;
    b.u8_(10);
    b.u24_(6); // -> solid right after
    b.u16_(3);
    b.u8_(2); // solid: entry 1, alpha .5
    b.u16_(1);
    b.f2(0.5);
    const tr = b.n;
    b.u8_(14);
    b.u24_(8);
    b.i16_(10);
    b.i16_(20);
    const g4 = b.n;
    b.u8_(10);
    b.u24_(6);
    b.u16_(4);
    const lin = b.n;
    b.u8_(4);
    b.u24_(16);
    for ([_]i16{ 0, 0, 100, 0, 0, 100 }) |v| b.i16_(v);
    // colour line (reflect): entry 1 @ 1.0 listed before entry 0 @ 0.0 (tests sorting)
    b.u8_(2);
    b.u16_(2);
    b.f2(1);
    b.u16_(1);
    b.f2(1);
    b.f2(0);
    b.u16_(0);
    b.f2(1);
    _ = .{ g4, lin };
    b.set32(ll0, g3 - ll);
    b.set32(ll1, tr - ll);

    // glyph 11
    const comp = b.n;
    b.u8_(32);
    b.u24_(8); // src -> cg10
    b.u8_(@intFromEnum(CompositeMode.multiply));
    b.u24_(11); // backdrop -> rad
    b.u8_(11); // cg10
    b.u16_(10);
    const rad = b.n;
    b.u8_(6);
    b.u24_(16);
    for ([_]i16{ 0, 0 }) |v| b.i16_(v);
    b.u16_(0);
    for ([_]i16{ 0, 0 }) |v| b.i16_(v);
    b.u16_(50);
    b.u8_(0); // colour line: one stop
    b.u16_(1);
    b.f2(0);
    b.u16_(0);
    b.f2(1);
    std.debug.assert(rad == comp + 11);

    // glyph 12
    const rot = b.n;
    b.u8_(24);
    b.u24_(6);
    b.f2(0.5);
    b.u8_(20); // scale uniform
    b.u24_(6);
    b.f2(0.5);
    b.u8_(8); // sweep
    b.u24_(12);
    b.i16_(0);
    b.i16_(0);
    b.f2(0);
    b.f2(1);
    b.u8_(0);
    b.u16_(1);
    b.f2(0);
    b.u16_(0);
    b.f2(1);

    const cg13 = b.n;
    b.u8_(11);
    b.u16_(13);
    const cg15 = b.n;
    b.u8_(11);
    b.u16_(15);
    const cg14 = b.n;
    b.u8_(11);
    b.u16_(14);

    b.set32(rec[0], lay - bgl);
    b.set32(rec[1], comp - bgl);
    b.set32(rec[2], rot - bgl);
    b.set32(rec[3], cg13 - bgl);
    b.set32(rec[4], cg15 - bgl);
    b.set32(rec[5], cg14 - bgl);
}

test "COLR v1 paint graph" {
    var cp: Blob = .{};
    testCpal(&cp);
    var co: Blob = .{};
    testColrV1(&co);
    const ct: ColorTables = .{ .colr = co.bytes(), .cpal = cp.bytes() };
    try testing.expectEqual(Kind.colr_v1, ct.kind(10));
    try testing.expectEqual(@as(f32, 500), ct.clipBox(10).?.x_max);
    try testing.expect(ct.clipBox(11) == null);

    var r: Recorder = .{};
    try ct.paint(10, 0, Rgba.transparent, &.{}, r.painter(true));
    // clip box, glyph 3 solid (palette 0 entry 1 = green, alpha .5), translate + glyph 4 linear
    try testing.expectEqualStrings("B500g3S0/128T(10,20)g4L2tc", r.str());
    try testing.expect(r.balanced());

    var r1: Recorder = .{};
    try ct.paint(11, 1, Rgba.transparent, &.{}, r1.painter(false));
    try testing.expectEqualStrings("[3FR1[23B500G3FS255/64cT(10,20)G4FL2ctc]]", r1.str());
    try testing.expect(r1.balanced());

    var r2: Recorder = .{};
    try ct.paint(12, 0, Rgba.transparent, &.{}, r2.painter(true));
    try testing.expectEqualStrings("T(0,0)T(0,0)FW1tt", r2.str());

    var r3: Recorder = .{};
    try testing.expectError(error.Cycle, ct.paint(13, 0, Rgba.transparent, &.{}, r3.painter(true)));
    try testing.expect(r3.balanced());
    var r4: Recorder = .{};
    try testing.expectError(error.Cycle, ct.paint(14, 0, Rgba.transparent, &.{}, r4.painter(true)));
    try testing.expect(r4.balanced());
}

test "transform formats" {
    var b: Blob = .{};
    // RotateAroundCenter(90deg, center 10,0) child = solid
    b.u8_(26);
    b.u24_(10);
    b.f2(0.5);
    b.i16_(10);
    b.i16_(0);
    b.u8_(2);
    b.u16_(0);
    b.f2(1);
    var w: Walker = .{ .t = b.bytes(), .h = .{}, .pal = .{}, .fg = Rgba.transparent, .p = undefined };
    const m = try w.transformOf(0, 26);
    const p = m.apply(.{ .x = 20, .y = 0 });
    try testing.expectApproxEqAbs(@as(f32, 10), p.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 10), p.y, 1e-4);
    // Skew x 45deg: (0,1) -> (-1, 1)
    var b2: Blob = .{};
    b2.u8_(28);
    b2.u24_(8);
    b2.f2(0.25);
    b2.f2(0);
    const w2: Walker = .{ .t = b2.bytes(), .h = .{}, .pal = .{}, .fg = Rgba.transparent, .p = undefined };
    const m2 = try w2.transformOf(0, 28);
    try testing.expectApproxEqAbs(@as(f32, -1), m2.apply(.{ .x = 0, .y = 1 }).x, 1e-4);
    // Affine inverse round trip
    const a: Affine2x3 = .{ .xx = 2, .yx = 0.5, .xy = -1, .yy = 3, .dx = 7, .dy = -2 };
    const q = a.invert().?.apply(a.apply(.{ .x = 3, .y = 4 }));
    try testing.expectApproxEqAbs(@as(f32, 3), q.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 4), q.y, 1e-4);
}

test "gradient helpers" {
    const stops = [_]ColorStop{
        .{ .offset = 0, .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 } },
        .{ .offset = 1, .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 } },
    };
    // linear with p2 rotating isolines: p0=(0,0), p1=(100,100), p2=(0,100) -> effective p1=(100,0)
    const lb: Brush = .{ .linear = .{ .p0 = .{ .x = 0, .y = 0 }, .p1 = .{ .x = 100, .y = 100 }, .p2 = .{ .x = 0, .y = 100 }, .stops = &stops, .extend = .pad } };
    try testing.expectApproxEqAbs(@as(f32, 0.5), gradientT(&lb, .{ .x = 50, .y = 77 }).?, 1e-5);
    const rb: Brush = .{ .radial = .{ .c0 = .{ .x = 0, .y = 0 }, .r0 = 0, .c1 = .{ .x = 0, .y = 0 }, .r1 = 100, .stops = &stops, .extend = .pad } };
    try testing.expectApproxEqAbs(@as(f32, 0.5), gradientT(&rb, .{ .x = 30, .y = 40 }).?, 1e-5);
    // focal outside: c0=(0,0) r0=0, c1=(100,0) r1=10 -> points behind the focal point undefined
    const rf: Brush = .{ .radial = .{ .c0 = .{ .x = 0, .y = 0 }, .r0 = 0, .c1 = .{ .x = 100, .y = 0 }, .r1 = 10, .stops = &stops, .extend = .pad } };
    try testing.expect(gradientT(&rf, .{ .x = -50, .y = 0 }) == null);
    try testing.expectApproxEqAbs(@as(f32, 1), gradientT(&rf, .{ .x = 90, .y = 0 }).?, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 11.0 / 9.0), gradientT(&rf, .{ .x = 110, .y = 0 }).?, 1e-4); // larger t wins
    const sb: Brush = .{ .sweep = .{ .c = .{ .x = 0, .y = 0 }, .start_angle = 0, .end_angle = 360, .stops = &stops, .extend = .pad } };
    try testing.expectApproxEqAbs(@as(f32, 0.25), gradientT(&sb, .{ .x = 0, .y = 5 }).?, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0.75), gradientT(&sb, .{ .x = 0, .y = -5 }).?, 1e-4);
    // extend modes
    try testing.expectApproxEqAbs(@as(f32, 0.25), applyExtend(1.25, .repeat), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.75), applyExtend(1.25, .reflect), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.75), applyExtend(-0.75 + 2, .reflect), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.25), applyExtend(-0.25, .reflect), 1e-6);
    try testing.expectEqual(@as(f32, 1), applyExtend(7, .pad));
    const mid = sampleColorLine(&stops, .pad, 0.5);
    try testing.expectApproxEqAbs(@as(f32, 127.5), mid[0], 1e-3);
    try testing.expectEqual(@as(u32, 0xff0000ff), shadePremul(&lb, .{ .x = -10, .y = 0 }));
    // stops outside [0,1]: repeat over [first, last]
    const wide = [_]ColorStop{ .{ .offset = -1, .color = stops[0].color }, .{ .offset = 1, .color = stops[1].color } };
    const c = sampleColorLine(&wide, .repeat, 2); // == t 0 == midpoint of the line
    try testing.expectApproxEqAbs(@as(f32, 127.5), c[0], 1e-3);
    // trig
    const sc = sinCos(1.0);
    try testing.expectApproxEqAbs(@as(f32, 0.84147098), sc[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.54030231), sc[1], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, -2.0344439), atan2(-0.3, -0.15) - 0, 3e-5);
    // linearDevice: brush space scaled by (2, -2): device gradient from (0,0) to (200, 0)
    const ld = linearDevice(.{ .x = 0, .y = 0 }, .{ .x = 100, .y = 0 }, .{ .x = 0, .y = 50 }, .{ .xx = 2, .yy = -2 }).?;
    try testing.expectApproxEqAbs(@as(f32, 200), ld[1].x, 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 0), ld[1].y, 1e-3);
}

/// CBLC/CBDT with two strikes (ppem 20: index format 1; ppem 109: index format 5 + image 19).
fn testCbdt(cblc: *Blob, cbdt: *Blob) void {
    // CBDT: header 4 bytes, then glyph images
    cbdt.u16_(3);
    cbdt.u16_(0);
    const png_hdr = [_]u8{ 0x89, 'P', 'N', 'G', 13, 10, 26, 10, 0, 0, 0, 13, 'I', 'H', 'D', 'R', 0, 0, 0, 30, 0, 0, 0, 25 };
    // strike 0 glyph 7 (format 17)
    const g7 = cbdt.n;
    cbdt.u8_(25);
    cbdt.u8_(30);
    cbdt.u8_(@bitCast(@as(i8, -2)));
    cbdt.u8_(20);
    cbdt.u8_(32);
    cbdt.u32_(png_hdr.len);
    for (png_hdr) |v| cbdt.u8_(v);
    const g7_end = cbdt.n;
    // strike 1 glyphs 7, 9 (format 19, fixed size 28)
    const s1 = cbdt.n;
    for (0..2) |_| {
        cbdt.u32_(png_hdr.len);
        for (png_hdr) |v| cbdt.u8_(v);
    }
    // CBLC
    cblc.u16_(3);
    cblc.u16_(0);
    cblc.u32_(2);
    const sz0 = cblc.n;
    for (0..96) |_| cblc.u8_(0);
    // strike 0 index array
    const arr0 = cblc.n;
    cblc.u16_(7);
    cblc.u16_(7);
    cblc.u32_(8);
    cblc.u16_(1);
    cblc.u16_(17);
    cblc.u32_(g7);
    cblc.u32_(0);
    cblc.u32_(g7_end - g7);
    const arr1 = cblc.n;
    cblc.u16_(7);
    cblc.u16_(9);
    cblc.u32_(8);
    cblc.u16_(5);
    cblc.u16_(19);
    cblc.u32_(s1);
    cblc.u32_(28); // image size
    for ([_]u8{ 100, 120, 5, 90, 128, 0, 0, 0 }) |v| cblc.u8_(v); // big metrics
    cblc.u32_(2);
    cblc.u16_(7);
    cblc.u16_(9);
    // fill BitmapSize records
    const recs = [_][3]u32{ .{ arr0, 7, 7 }, .{ arr1, 7, 9 } };
    for (recs, 0..) |rc, i| {
        const o: u32 = sz0 + @as(u32, @intCast(i)) * 48;
        cblc.set32(o, rc[0]);
        cblc.set32(o + 8, 1);
        cblc.buf[o + 40] = 0;
        cblc.buf[o + 41] = @intCast(rc[1]);
        cblc.buf[o + 42] = 0;
        cblc.buf[o + 43] = @intCast(rc[2]);
        const ppem: u8 = if (i == 0) 20 else 109;
        cblc.buf[o + 44] = ppem;
        cblc.buf[o + 45] = ppem;
        cblc.buf[o + 46] = 32;
    }
}

test "CBDT strikes" {
    var cblc: Blob = .{};
    var cbdt: Blob = .{};
    testCbdt(&cblc, &cbdt);
    const ct: ColorTables = .{ .cblc = cblc.bytes(), .cbdt = cbdt.bytes() };
    try testing.expectEqual(Kind.bitmap_png, ct.kind(7));
    try testing.expectEqual(Kind.bitmap_png, ct.kind(9));
    try testing.expectEqual(Kind.none, ct.kind(8));
    const small = ct.bitmap(7, 24).?;
    try testing.expectEqual(@as(f32, 20), small.ppem);
    try testing.expectEqual(@as(f32, -2), small.bearing_x);
    try testing.expectEqual(@as(f32, 20), small.bearing_y);
    try testing.expectEqual(@as(u32, 30), small.width);
    try testing.expectEqual(@as(u8, 0x89), small.data[0]);
    const big = ct.bitmap(7, 200).?;
    try testing.expectEqual(@as(f32, 109), big.ppem);
    try testing.expectEqual(@as(f32, 90), big.bearing_y);
    try testing.expectEqual(@as(u32, 120), big.width);
    try testing.expectEqual(@as(usize, 24), big.data.len);
    // only strike 1 has glyph 9; below the smallest strike -> smallest
    try testing.expectEqual(@as(f32, 109), ct.bitmap(9, 12).?.ppem);
    try testing.expectEqual(@as(f32, 20), ct.bitmap(7, 12).?.ppem);
    try testing.expect(ct.bitmap(8, 64) == null);
}

test "sbix strikes and dupe" {
    var b: Blob = .{};
    b.u16_(1);
    b.u16_(1);
    b.u32_(1);
    b.u32_(12); // strike @12
    const s = b.n;
    b.u16_(64);
    b.u16_(72);
    // 4 glyphs -> 5 offsets
    const offs = b.n;
    for (0..5) |_| b.u32_(0);
    const g1 = b.n - s;
    b.i16_(3);
    b.i16_(-4);
    for ("png ") |c| b.u8_(c);
    for ([_]u8{ 0x89, 'P', 'N', 'G', 13, 10, 26, 10, 0, 0, 0, 13, 'I', 'H', 'D', 'R', 0, 0, 0, 60, 0, 0, 0, 50 }) |v| b.u8_(v);
    const g2 = b.n - s;
    b.i16_(0);
    b.i16_(0);
    for ("dupe") |c| b.u8_(c);
    b.u16_(1);
    const g3 = b.n - s;
    b.i16_(0);
    b.i16_(0);
    for ("jpg ") |c| b.u8_(c);
    b.u8_(0xFF);
    const end = b.n - s;
    const vals = [_]u32{ g1, g1, g2, g3, end };
    for (vals, 0..) |v, i| b.set32(offs + @as(u32, @intCast(i)) * 4, v);
    const ct: ColorTables = .{ .sbix = b.bytes(), .num_glyphs = 4 };
    try testing.expectEqual(Kind.none, ct.kind(0));
    try testing.expectEqual(Kind.bitmap_png, ct.kind(1));
    try testing.expectEqual(Kind.bitmap_png, ct.kind(2));
    try testing.expectEqual(Kind.bitmap_other, ct.kind(3));
    const bm = ct.bitmap(2, 32).?;
    try testing.expectEqual(@as(f32, 64), bm.ppem);
    try testing.expectEqual(@as(f32, 3), bm.bearing_x);
    try testing.expectEqual(@as(f32, 46), bm.bearing_y); // -4 + height 50
    try testing.expectEqual(@as(u32, 60), bm.width);
    try testing.expect(ct.bitmap(4, 32) == null);
}

test "fuzz: mutated tables never trap and keep calls balanced" {
    var cp: Blob = .{};
    testCpal(&cp);
    var v1: Blob = .{};
    testColrV1(&v1);
    var v0: Blob = .{};
    testColrV0(&v0);
    var cblc: Blob = .{};
    var cbdt: Blob = .{};
    testCbdt(&cblc, &cbdt);
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rnd = prng.random();
    var buf: [4096]u8 = undefined;
    var buf2: [4096]u8 = undefined;
    var iter: u32 = 0;
    while (iter < 6000) : (iter += 1) {
        const which = iter % 3;
        const src = switch (which) {
            0 => v1.bytes(),
            1 => v0.bytes(),
            else => cblc.bytes(),
        };
        @memcpy(buf[0..src.len], src);
        var len = src.len;
        const nmut = 1 + rnd.uintLessThan(u32, 6);
        for (0..nmut) |_| {
            const pos = rnd.uintLessThan(usize, len);
            switch (rnd.uintLessThan(u32, 4)) {
                0 => buf[pos] = rnd.int(u8),
                1 => buf[pos] ^= @as(u8, 1) << rnd.int(u3),
                2 => buf[pos] = if (rnd.boolean()) 0xff else 0,
                else => len = @max(1, pos),
            }
        }
        @memcpy(buf2[0..cp.n], cp.bytes());
        if (iter % 7 == 0) buf2[rnd.uintLessThan(usize, cp.n)] = rnd.int(u8);
        const ct: ColorTables = switch (which) {
            0, 1 => .{ .colr = buf[0..len], .cpal = buf2[0..cp.n] },
            else => .{ .cblc = buf[0..len], .cbdt = cbdt.bytes() },
        };
        var g: u16 = 0;
        while (g < 20) : (g += 1) {
            _ = ct.kind(g);
            _ = ct.bitmap(g, 50);
            _ = ct.clipBox(g);
            var r: Recorder = .{};
            ct.paint(g, 0, Rgba.transparent, &.{}, r.painter(g & 1 == 0)) catch {};
            try testing.expect(r.balanced());
        }
    }
}

test "variation deltas via DeltaFn" {
    var b: Blob = .{};
    b.u16_(1);
    for (0..6) |_| b.u16_(0);
    b.n = 14;
    b.u32_(34); // BaseGlyphList
    b.u32_(0);
    b.u32_(0);
    b.u32_(0); // no DeltaSetIndexMap: index = (outer << 16) | inner
    b.u32_(60); // ItemVariationStore (contents are opaque to the fake DeltaFn)
    b.u32_(1); // @34
    b.u16_(1);
    b.u32_(10); // paint @44
    b.u8_(15); // @44 VarTranslate -> solid @56
    b.u24_(12);
    b.i16_(10);
    b.i16_(20);
    b.u32_(5); // varIndexBase
    b.u8_(3); // @56 VarSolid entry 0xFFFF alpha 0.5, varIndexBase 0x10000 -> (outer 1, inner 0)
    b.u16_(0xFFFF);
    b.f2(0.5);
    b.u32_(0x10000);
    for (0..8) |_| b.u8_(0); // @60 fake store
    const Fake = struct {
        fn d(_: []const u8, outer: u32, inner: u32, coords: []const i16) f32 {
            if (coords.len == 0) return 0;
            return if (outer == 1) 4096 else @floatFromInt(inner); // alpha +0.25
        }
    };
    const ct: ColorTables = .{ .colr = b.bytes() };
    var r: Recorder = .{};
    try ct.paintVar(1, 0, .{ .r = 1, .g = 2, .b = 3, .a = 200 }, &.{8192}, &Fake.d, r.painter(true));
    try testing.expectEqualStrings("T(15,26)FS1/150t", r.str()); // 200 * 0.75 = 150
    var r2: Recorder = .{};
    try ct.paint(1, 0, .{ .r = 1, .g = 2, .b = 3, .a = 200 }, &.{8192}, r2.painter(true));
    try testing.expectEqualStrings("T(10,20)FS1/100t", r2.str()); // base values
    try testing.expectEqual(@as(?u32, 0x0003_0007), deltaSetIndex(&[_]u8{ 0, 0x13, 0, 1, 0x00, 0x37 }, 0)); // entry 0x0037: inner 4 bits
}

test {
    _ = emoji;
}
