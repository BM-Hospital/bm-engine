//! Text of the PDF emitter: everything a paragraph paints except the glyphs themselves, plus the
//! one seam the glyph emission (font subsetting, `Tj`/`TJ`, ToUnicode) plugs into:
//!
//! * inline box fragments (`<span>` backgrounds, borders), as the painter / svg_out_text.zig;
//! * text decorations (underline / overline / line-through: solid and double as filled rects,
//!   dotted / dashed as stroked dashed lines, wavy as a stroked curve, skip-ink cuts from the
//!   painter's glyph coverage), through the paint device;
//! * glyph runs (`emitTextRun`): one call per run of one face / size, per text-shadow pass, with
//!   everything takumi-pdf's `paint_glyph_run` needs, drawn by text.zig (`drawSeamRun`: font
//!   subsetting, `BT .. TJ .. ET`, ToUnicode, Type3 colour glyphs); with `debug_glyph_outlines`
//!   the glyph outlines are filled as plain paths instead;
//! * pagination: a run is drawn on a page that shows its line (takumi-pdf window.rs
//!   `shows_line_item`), as text only on the page that owns the line (`disowns_line`: the page
//!   holding its baseline), as outlines on the others;
//! * `background-clip: text` (`paintClipText`): the box's background fills seen through the glyphs
//!   of its subtree (takumi `fill_text_clip`).
const std = @import("std");
const render = @import("../render.zig");
const style = @import("../style/style.zig");
const font = @import("../font/font.zig");
const raster = @import("../raster/raster.zig");
const pm = @import("../paint.zig");
const ptext = @import("../paint_text.zig");
const pborder = @import("../paint_border.zig");
const emit = @import("emit.zig");
const border = @import("emit_border.zig");
const dev = @import("emit_device.zig");
const sf = @import("emit_surface.zig");
const text = @import("text.zig");
const etag = @import("emit_tag.zig"); // [tagging]
const markers = @import("markers.zig");

const Emitter = emit.Emitter;
const Node = render.Node;
const CS = render.CS;
const none = render.none;
const Rect = raster.Rect;
const Affine = raster.Affine;
const Path = raster.Path;
const Error = render.Error;
const Color = style.Color;

/// Fill glyph outlines as plain paths (no text layer, no fonts) instead of real text (debugging).
pub const debug_glyph_outlines = false;

// ---------------------------------------------------------------------------------------------
// THE TEXT SEAM
// ---------------------------------------------------------------------------------------------

/// A `-webkit-text-stroke`.
pub const TextStroke = struct { width: f32, color: Color };

/// A `text-shadow` pass: the run drawn again, offset, in the shadow colour `color` (after colour
/// filters; takumi-pdf `TextDevice` with `shadow` set; a blur steps through `Band`s like box
/// shadows).
pub const ShadowPass = struct { dx: f32, dy: f32, blur: f32, color: Color };

/// One glyph run as takumi-pdf's `paint_glyph_run` receives it (krilla `draw_glyphs` input).
pub const TextRun = struct {
    /// the text node / paragraph owner, and the run's own style (a `<span>`'s inside a paragraph)
    node: *const Node,
    style: *const CS,
    /// bm-engine font registry face (`Renderer.fonts.font(face)`: the sfnt to subset) and size
    face: font.FaceId,
    size: f32,
    /// the run's glyphs: one face and size, in visual order (both bidi directions possible). `gid` is the glyph id in `face`;
    /// (`x`, `y`) the glyph origin on the baseline in paragraph space (px, y down), so glyph i
    /// lands at (`x + glyphs[i].x`, `y + glyphs[i].y`) in the current user space (CSS px; the
    /// surface's transform maps it to the page); `cluster` is the byte offset of its source
    /// character in the paragraph's concatenated run texts (`text` below, when known); `user`
    /// indexes `Frame.run_styles`.
    glyphs: []const font.PositionedGlyph,
    x: f32,
    y: f32,
    /// the paragraph's source text the clusters index (ToUnicode / ActualText;
    /// `Frame.paragraphText`); empty: a stand-in from the glyphs' cmap codepoints
    text: []const u8 = "",
    /// the run's baseline (paragraph space, px): the faux oblique shears about it
    baseline: f32 = 0,
    /// fill colour after colour filters (`-webkit-text-fill-color` or `color`); alpha 0 = no fill.
    /// Also in a shadow pass (colour glyph silhouettes take it as their context colour).
    fill: Color,
    /// `-webkit-text-stroke` after colour filters (null: none)
    stroke: ?TextStroke = null,
    /// `paint-order: stroke ...`: the stroke pass goes under the fill
    stroke_first: bool = false,
    /// synthetic bold: an extra stroke of this width in the fill colour (0 = none)
    synthetic_bold: f32 = 0,
    /// synthetic oblique: shear by -0.25 about the run's baseline
    synthetic_italic: bool = false,
    /// a colour (COLR / bitmap) glyph run: drawn as the font paints it, not stroked
    colored: bool = false,
    /// set for a text-shadow pass; (`x`, `y`) is then the unshifted origin
    shadow: ?ShadowPass = null,
    /// this page owns the run's line (its text belongs in this page's text layer); false =
    /// outlines only (a line cut by the page edge, drawn as text on the page that owns it)
    owned: bool = true,
    /// `background-clip: text` fills painted through the glyphs (before the glyphs' own paint)
    fills: []const text.GlyphBackground = &.{},
    /// draw the glyphs' own paint (false: the fills only, a `background-clip: text` pass)
    with_paint: bool = true,
};

/// THE TEXT SEAM: draws one glyph run onto `e.s` (the current surface) with the document's font
/// registry `e.fonts` (text.zig `drawSeamRun`: krilla `draw_glyphs` through takumi-pdf's
/// `paint_glyph_run`).
pub fn emitTextRun(e: *Emitter, run: *const TextRun) Error!void {
    if (comptime !debug_glyph_outlines) return text.drawSeamRun(e.fonts, e.s, e.f, run) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => {
            e.fail("PDF text error: ", @errorName(err));
            return;
        },
    };
    if (run.colored or !run.with_paint) return;
    const fnt = e.f.r.fonts.font(run.face);
    var path: Path = .empty;
    var ox = run.x;
    var oy = run.y;
    if (run.shadow) |sh| {
        ox += sh.dx;
        oy += sh.dy;
    }
    for (run.glyphs) |*g| {
        var sink: raster.PathSink = .{ .path = &path, .alloc = e.a, .transform = if (run.synthetic_italic) .{ .c = -0.25 } else Affine.identity };
        const base = path.points.items.len;
        _ = font.emitGlyph(fnt, g.gid, run.size, 0, 0, &sink);
        if (sink.err) return error.OutOfMemory;
        for (path.points.items[base..]) |*q| {
            q.x += ox + g.x;
            q.y += oy + g.y;
        }
    }
    if (path.isEmpty()) return;
    const col = if (run.shadow) |sh| sh.color else run.fill;
    if (col.a != 0) e.d.fillPath(&path, 0, 0, .nonzero, col);
    if (run.stroke) |st| e.d.strokePath(&path, 0, 0, st.width, null, false, if (run.shadow) |sh| sh.color else st.color);
}

// ---------------------------------------------------------------------------------------------
// paragraphs (painter `paintText`, svg_out_text.zig)
// ---------------------------------------------------------------------------------------------

const Synth = struct { italic: bool, bold: bool, colored: bool };

fn synthOf(e: *Emitter, rcs: *const CS, g: *const font.PositionedGlyph) Synth {
    const fc = e.f.r.fonts.face(g.face);
    var sy: Synth = .{ .italic = rcs.font_style != .normal and !fc.italic, .bold = rcs.font_weight >= 600 and fc.weight < 600, .colored = false };
    if (comptime pm.enable_color_fonts) {
        const color = @import("../font/color.zig");
        if (color.glyphKind(&fc.font, g.gid) != .none) sy = .{ .italic = false, .bold = false, .colored = true };
    }
    return sy;
}

fn runStyle(e: *Emitter, n: *const Node, g: *const font.PositionedGlyph) *const CS {
    const rs = e.f.run_styles.items;
    return if (g.user < rs.len) rs[g.user] else n.cs;
}

const Metrics = struct { ascent: f32, descent: f32, ul_pos: f32, ul_thick: f32, em_descent: f32 };

fn metricsOf(e: *Emitter, face: font.FaceId, size: f32) Metrics {
    const fnt = e.f.r.fonts.font(face);
    const sc = size / @as(f32, @floatFromInt(@max(1, fnt.unitsPerEm())));
    const lm = fnt.lineMetrics();
    const ta: f32 = @floatFromInt(fnt.typoAscender());
    const td: f32 = @floatFromInt(-@as(i32, fnt.typoDescender()));
    const a: f32 = @floatFromInt(lm.ascent);
    const d: f32 = @floatFromInt(lm.descent);
    return .{
        .ascent = @round(a * sc),
        .descent = @round(d * sc),
        .ul_pos = -@as(f32, @floatFromInt(fnt.underlinePosition())) * sc,
        .ul_thick = @as(f32, @floatFromInt(fnt.underlineThickness())) * sc,
        .em_descent = if (ta + td > 0) size * td / (ta + td) else if (a + d > 0) size * d / (a + d) else 0,
    };
}

fn hasLine(cs: *const CS) bool {
    const d = cs.text_decoration_line;
    return d.underline or d.overline or d.line_through;
}

const RunSeg = struct { g0: u32, g1: u32, x0: f32, x1: f32, baseline: f32, rcs: *const CS };

/// How a run is drawn on this page (pagination, `background-clip: text`).
const PassOpts = struct {
    shadow: ?ShadowPass = null,
    owned: bool = true,
    fills: []const text.GlyphBackground = &.{},
    with_paint: bool = true,
};

/// Whether the face paints its own colours (colour faces never synthesise bold / oblique).
fn coloredFace(e: *Emitter, face: font.FaceId) bool {
    if (comptime !pm.enable_color_fonts) return false;
    const color = @import("../font/color.zig");
    return color.ColorTables.init(&e.f.r.fonts.face(face).font).hasColor();
}

/// Hands `glyphs[g0..g1]` (one face: a takumi `ShapedRun`) to the seam, split only where the
/// size changes. Synthesis is the run's (face and style), as in takumi: colour and outline
/// glyphs of one run stay in one text object (the seam switches fonts inside it).
fn glyphPass(e: *Emitter, n: *const Node, tl: *const font.TextLayout, x: f32, y: f32, run: *const RunSeg, o: PassOpts) Error!void {
    const rcs = run.rcs;
    const fill_raw = if (rcs.webkit_text_fill_color) |c| rcs.resolveColor(c) else rcs.color;
    const sw = rcs.webkit_text_stroke_width;
    const scol = rcs.resolveColor(rcs.webkit_text_stroke_color);
    const para_text = if (n.para) |pp| render.Frame.paragraphText(pp) else "";
    // the line's overflow marker is a run of its own whose text is its glyphs' characters, not
    // the hidden text it stands in for (takumi-pdf draws it as a separate text run)
    var mk0: u32 = 0;
    var mk1: u32 = 0;
    if (lineOf(tl, run.g0)) |li| {
        mk0 = tl.lines[li].marker0;
        mk1 = tl.lines[li].marker1;
    }
    var i = run.g0;
    while (i < run.g1) {
        const g0 = &tl.glyphs[i];
        const in_marker = i >= mk0 and i < mk1;
        const stop = if (in_marker) mk1 else if (mk1 > mk0 and i < mk0) mk0 else run.g1;
        var j = i + 1;
        while (j < run.g1 and j < stop and tl.glyphs[j].size == g0.size) j += 1;
        const fc = e.f.r.fonts.face(g0.face);
        const colored = coloredFace(e, g0.face);
        const tr: TextRun = .{
            .node = n,
            .style = rcs,
            .face = g0.face,
            .size = g0.size,
            .glyphs = tl.glyphs[i..j],
            .x = x,
            .y = y,
            .text = if (o.with_paint and !in_marker) para_text else "",
            .baseline = run.baseline,
            .fill = dev.filtered(e.filter, fill_raw),
            .stroke = if (sw > 0 and scol.a != 0) .{ .width = sw, .color = dev.filtered(e.filter, scol) } else null,
            .stroke_first = rcs.paint_order == .stroke,
            .synthetic_bold = if (!colored and rcs.font_weight >= 600 and fc.weight < 600) ptext.emboldenWidth(g0.size) else 0,
            .synthetic_italic = !colored and rcs.font_style != .normal and !fc.italic,
            .colored = colored,
            .shadow = if (o.shadow) |sh| .{ .dx = sh.dx, .dy = sh.dy, .blur = sh.blur, .color = dev.filtered(e.filter, sh.color) } else null,
            .owned = o.owned,
            .fills = o.fills,
            .with_paint = o.with_paint,
        };
        try emitTextRun(e, &tr);
        i = j;
    }
}

// ---- pagination (takumi-pdf window.rs)

/// A run or line on its line (takumi-core `LineItem`), in the frame's coordinates.
const LineItem = struct { baseline: f32, top: f32, bottom: f32, l0: f32, l1: f32 };

/// The line box index holding glyph `gi`.
fn lineOf(tl: *const font.TextLayout, gi: u32) ?usize {
    for (tl.lines, 0..) |ln, k| {
        if (gi >= ln.glyph_start and gi < ln.glyph_end) return k;
    }
    return null;
}

/// `it` (current user space) in frame coordinates: through the walk's transform when one is open,
/// its extent across the horizontal span `x0..x1` and its baseline at the span's middle
/// (takumi `LineFrame::map`).
fn mapItem(e: *const Emitter, it: LineItem, x0: f32, x1: f32) LineItem {
    if (e.tf.isIdentity()) return it;
    const t = e.tf;
    const yAt = struct {
        fn f(m: Affine, px: f32, py: f32) f32 {
            return m.b * px + m.d * py + m.f;
        }
    }.f;
    const ext = struct {
        fn f(m: Affine, a: f32, b: f32, top: f32, bottom: f32) [2]f32 {
            const c = [4]f32{ yAt(m, a, top), yAt(m, b, top), yAt(m, a, bottom), yAt(m, b, bottom) };
            return .{ @min(@min(c[0], c[1]), @min(c[2], c[3])), @max(@max(c[0], c[1]), @max(c[2], c[3])) };
        }
    }.f;
    const tb = ext(t, x0, x1, it.top, it.bottom);
    const lb = ext(t, x0, x1, it.l0, it.l1);
    return .{ .baseline = yAt(t, (x0 + x1) / 2, it.baseline), .top = tb[0], .bottom = tb[1], .l0 = lb[0], .l1 = lb[1] };
}

/// takumi `Window::disowns`: the line belongs to another page.
fn disowns(e: *const Emitter, it: LineItem) bool {
    return it.baseline < e.window.lines_top or it.baseline >= e.window.lines_bottom;
}

/// takumi `Window::shows_line_item`: this page draws the item (on the page owning its line, and
/// on every other page its line box reaches).
fn showsItem(e: *const Emitter, it: LineItem) bool {
    return !e.window.excludes(it.top, it.bottom) and (!disowns(e, it) or !e.window.excludes(it.l0, it.l1));
}

/// The line item of a run of `tl` at content origin `y` (current user space, mapped to the frame).
fn runItem(e: *Emitter, tl: *const font.TextLayout, x: f32, y: f32, r: anytype) LineItem {
    const g0 = &tl.glyphs[r.g0];
    const m = metricsOf(e, g0.face, g0.size);
    const base = y + r.baseline;
    var it: LineItem = .{ .baseline = base, .top = base - m.ascent, .bottom = base + m.descent, .l0 = base - m.ascent, .l1 = base + m.descent };
    if (lineOf(tl, r.g0)) |k| {
        const ln = tl.lines[k];
        it.l0 = y + ln.top;
        it.l1 = y + ln.top + ln.height;
    }
    return mapItem(e, it, x + r.x0, x + r.x1);
}

/// Whether this page shows the run (and as text: `owned`). Unpaginated windows show everything.
fn runOnPage(e: *Emitter, tl: *const font.TextLayout, x: f32, y: f32, r: anytype) struct { shows: bool, owned: bool } {
    if (!e.window.paged()) return .{ .shows = true, .owned = true };
    const it = runItem(e, tl, x, y, r);
    return .{ .shows = showsItem(e, it), .owned = !disowns(e, it) };
}

// ---- decorations (painter geometry, svg_out_text.zig)

const DecoKind = enum { underline, overline, line_through };
const Span = struct { a: f32, b: f32 };

/// Strokes the centre line `path`, through one clip of every piece the skip-ink cuts leave
/// (`y`, `h`: the band of the clip rectangles).
fn strokeLine(e: *Emitter, sh: ?ShadowPass, path: *const Path, width: f32, dash: ?pborder.Dash, col: Color, pieces: ?[]const Span, y: f32, h: f32) Error!void {
    const depth0 = e.d.depth();
    defer e.d.restore(depth0);
    const dx: f32 = if (sh) |v| v.dx else 0;
    const dy: f32 = if (sh) |v| v.dy else 0;
    if (pieces) |ps| {
        var clip: Path = .empty;
        for (ps) |pc| try clip.addRect(e.a, .{ .x = pc.a, .y = y, .w = pc.b - pc.a, .h = h });
        // (a clip opened inside a shadow moves with it: takumi `shadow_moved`)
        e.d.pushClip(&clip, dx, dy, .nonzero);
    }
    const ds: ?[2]f32 = if (dash) |d| .{ d.on, d.off } else null;
    const round = if (dash) |d| d.round else false;
    const v = sh orelse return e.d.strokePath(path, 0, 0, width, ds, round, col);
    shadowBands(e, v, struct {
        fn draw(em: *Emitter, c: Color, spread: f32, pth: *const Path, w0: f32, ox: f32, oy: f32, d: ?[2]f32, r: bool) void {
            em.d.strokePath(pth, ox, oy, w0 + spread, d, r, c);
        }
    }.draw, .{ path, width, dx, dy, ds, round });
}

/// takumi `TextDevice::in_shadow_bands`: `draw` once in the shadow colour, or, for a blurred
/// shadow, once per band (an opacity group each, the spread passed on; a translucent colour in an
/// outer group).
fn shadowBands(e: *Emitter, sh: ShadowPass, comptime draw: anytype, args: anytype) void {
    if (!(sh.blur > 0)) return @call(.auto, draw, .{ e, sh.color, @as(f32, 0) } ++ args);
    var opaque_col = sh.color;
    opaque_col.a = 255;
    const translucent = sh.color.a < 255;
    if (translucent) e.d.beginLayer(@as(f32, @floatFromInt(sh.color.a)) / 255.0);
    var buf: [9]emit.Band = undefined;
    for (emit.bandsOf(sh.blur, &buf)) |b| {
        e.d.beginLayer(b.alpha);
        @call(.auto, draw, .{ e, opaque_col, 2 * b.spread } ++ args);
        e.d.endLayer();
    }
    if (translucent) e.d.endLayer();
}

/// A decoration rectangle, or its shadow (takumi `TextDevice::fill_shape`: in the shadow colour,
/// moved by its offset; a blurred one stroked by each band's spread as well).
fn decoFill(e: *Emitter, sh: ?ShadowPass, r: Rect, col: Color) Error!void {
    const v = sh orelse return e.d.fillRRect(r, null, col);
    const rr: Rect = .{ .x = r.x + v.dx, .y = r.y + v.dy, .w = r.w, .h = r.h };
    var path: Path = .empty;
    try path.addRect(e.a, rr);
    shadowBands(e, v, struct {
        fn draw(em: *Emitter, c: Color, spread: f32, rect: Rect, pth: *const Path) void {
            em.d.fillRRect(rect, null, c);
            if (spread > 0) em.d.strokePath(pth, 0, 0, spread, null, false, c);
        }
    }.draw, .{ rr, &path });
}

fn paintDecoLine(e: *Emitter, sh: ?ShadowPass, kind: DecoKind, st: style.computed.DecorationStyle, col: Color, x0: f32, x1: f32, top: f32, thickness: f32, cuts: []const Span) Error!void {
    if (col.a == 0 or !(x1 > x0)) return;
    const h = @max(1, @floor(thickness));
    var pieces: [33]Span = undefined;
    var np: usize = 0;
    var cur = x0;
    for (cuts) |c| {
        if (np >= pieces.len - 1) break;
        if (c.a > cur) {
            pieces[np] = .{ .a = cur, .b = @min(c.a, x1) };
            np += 1;
        }
        cur = @max(cur, c.b);
        if (cur >= x1) break;
    }
    if (cur < x1) {
        pieces[np] = .{ .a = cur, .b = x1 };
        np += 1;
    }
    const second: f32 = switch (kind) {
        .underline => thickness + 1,
        .overline => -(thickness + 1),
        .line_through => @floor(thickness + 1),
    };
    const a = e.a;
    var path: Path = .empty;
    switch (st) {
        .solid, .double => for (pieces[0..np]) |pc| {
            try decoFill(e, sh, .{ .x = pc.a, .y = @floor(top + 0.5), .w = pc.b - pc.a, .h = h }, col);
            if (st == .double) try decoFill(e, sh, .{ .x = pc.a, .y = @floor(top + second + 0.5), .w = pc.b - pc.a, .h = h }, col);
        },
        .dotted, .dashed => {
            const start = @floor(x0);
            const end = @floor(x1);
            const row = @floor(top + @max(thickness / 2, 0.5));
            const t = @max(1, @round(thickness));
            // an odd thickness (`t` is a whole number >= 1; every f32 from 2^24 up is even), tested on the
            // integer: `@mod(t, 2)` compiles to a fused multiply-add on arm64 (`t - 2 * trunc(t / 2)`: exact, so
            // the result is the same, but scripts/build-native.mjs counts every fused instruction)
            const odd = t < 16777216 and (@as(u32, @intFromFloat(t)) & 1) == 1;
            const yl = if (odd) row + 0.5 else row;
            const dash = pborder.dashPattern(if (st == .dotted) .dotted else .dashed, t, end - start, false);
            var la = start;
            var lb = end;
            if (dash != null and dash.?.round) {
                la += t / 2;
                lb -= t / 2;
            }
            if (!(lb > la)) return;
            try path.moveTo(a, la, yl);
            try path.lineTo(a, lb, yl);
            if (cuts.len == 0) return strokeLine(e, sh, &path, t, dash, col, null, 0, 0);
            try strokeLine(e, sh, &path, t, dash, col, pieces[0..np], yl - t / 2 - 1, t + 2);
        },
        .wavy => {
            const t = @max(thickness, 1);
            const wl = 1 + 2 * @round(2 * t + 0.5);
            const cpd = 0.5 + @round(3 * t + 0.5);
            const wavy_off: f32 = switch (kind) {
                .underline => thickness + 1,
                .overline => -(thickness + 1),
                .line_through => 0,
            };
            const yy = top + wavy_off + 0.5;
            const reach = cpd / (2 * @sqrt(3.0)) + thickness / 2;
            const mid = top + wavy_off;
            const ctop = mid + @floor(0.5 - reach);
            const cbot = mid + @ceil(0.5 + reach);
            var xx = x0 - wl;
            try path.moveTo(a, xx, yy);
            var guard: u32 = 0;
            while (xx < x1 + wl and guard < 20000) : (guard += 1) {
                try path.cubicTo(a, xx + wl / 2, yy + cpd, xx + wl / 2, yy - cpd, xx + wl, yy);
                xx += wl;
            }
            try strokeLine(e, sh, &path, thickness, null, col, pieces[0..np], ctop, cbot - ctop);
        },
    }
}

fn paintRunDecos(e: *Emitter, sh: ?ShadowPass, tl: *const font.TextLayout, x: f32, y: f32, run: *const RunSeg, decos: []const *const CS, after: bool) Error!void {
    const g0 = &tl.glyphs[run.g0];
    const tm = metricsOf(e, g0.face, g0.size);
    const text_top = y + run.baseline - tm.ascent;
    for (decos) |dcs| {
        const dl = dcs.text_decoration_line;
        const col = dcs.resolveColor(dcs.text_decoration_color);
        const dm = metricsOf(e, g0.face, dcs.font_size);
        const auto = dcs.font_size / 10.0;
        const thickness = @max(1, if (dcs.text_decoration_thickness) |v| @round(v) else auto);
        const box_top = y + run.baseline - dm.ascent;
        const off = if (dcs.text_underline_offset) |o| o else 0;
        const lx0 = x + run.x0;
        const lx1 = x + run.x1;
        if (after) {
            if (dl.line_through) try paintDecoLine(e, sh, .line_through, dcs.text_decoration_style, col, lx0, lx1, text_top + 2 * dm.ascent / 3 - thickness / 2, thickness, &.{});
            continue;
        }
        inline for (.{ DecoKind.underline, DecoKind.overline }) |kind| {
            if (if (kind == .underline) dl.underline else dl.overline) {
                var top: f32 = undefined;
                if (kind == .overline) {
                    top = text_top - @floor(thickness);
                } else if (dcs.text_underline_position.under) {
                    top = box_top + @floor(@round((dm.ascent + dm.em_descent) * 64) / 64 + @round(off * 64) / 64) + 1;
                } else if (dcs.text_underline_position.from_font and dm.ul_thick > 0) {
                    top = box_top + @round(dm.ascent + dm.ul_pos + off);
                } else {
                    const gap: f32 = if (dcs.text_underline_offset != null) 0 else @max(1, @ceil(thickness / 2));
                    top = box_top + @trunc(dm.ascent + gap + @round(off));
                }
                var cuts: [32]Span = undefined;
                var nc: usize = 0;
                if (dcs.text_decoration_skip_ink != .none and e.plain()) nc = skipInk(e, tl, x, y, run, top, thickness, dcs.text_decoration_style, kind == .underline, &cuts);
                try paintDecoLine(e, sh, kind, dcs.text_decoration_style, col, lx0, lx1, top, thickness, cuts[0..nc]);
            }
        }
    }
}

/// Ink intercepts of the run's glyphs with the decoration band (painter `skipInk`).
fn skipInk(e: *Emitter, tl: *const font.TextLayout, x: f32, y: f32, run: *const RunSeg, top: f32, thickness: f32, st: style.computed.DecorationStyle, underline: bool, out: *[32]Span) usize {
    const pctx = e.ctx();
    var b0 = @floor(top + 0.5);
    var b1 = b0 + thickness;
    if (st == .double) {
        if (underline) b1 += thickness + 1 else b0 -= thickness + 1;
    } else if (st == .wavy) {
        const cpd = 0.5 + @round(3 * @max(thickness, 1) + 0.5);
        const reach = cpd / (2 * @sqrt(3.0)) + thickness / 2;
        const mid = top + (if (underline) thickness + 1 else -(thickness + 1));
        b0 = mid + @floor(0.5 - reach);
        b1 = mid + @ceil(0.5 + reach);
    }
    b0 += 0.5;
    b1 -= 0.5;
    // (takumi `skip_ink_ranges`: nothing to skip when the band is no taller than the 2 x 0.5 px
    // inset, i.e. a decoration up to 1 px thick)
    if (!(b1 - b0 > 0)) return 0;
    const r0: i64 = @intFromFloat(std.math.clamp(@floor(b0), -1.0e6, 1.0e6));
    const r1: i64 = @intFromFloat(std.math.clamp(@ceil(b1), -1.0e6, 1.0e6));
    const grow = @min(thickness, 13);
    var nc: usize = 0;
    for (tl.glyphs[run.g0..run.g1]) |*g| {
        const sy = synthOf(e, run.rcs, g);
        if (sy.colored) continue;
        const m = ptext.glyphPassMask(&e.p, &pctx, g, x + g.x, y + g.y, sy.italic, .fill, 0) orelse continue;
        const mb = m.bounds;
        var lo: i64 = std.math.maxInt(i64);
        var hi: i64 = std.math.minInt(i64);
        const row_end = @min(r1, mb.bottom());
        var xx: u32 = 0;
        while (xx < mb.w) : (xx += 1) {
            var ink = false;
            var row = @max(r0, @as(i64, mb.y));
            while (row < row_end) : (row += 1) {
                if (m.data[@as(usize, @intCast(row - mb.y)) * mb.w + xx] != 0) {
                    ink = true;
                    break;
                }
            }
            const col: i64 = @as(i64, mb.x) + xx;
            if (ink) {
                if (lo > hi) lo = col;
                hi = col;
            }
            if ((!ink or xx + 1 == mb.w) and lo <= hi) {
                const a = @floor(@as(f32, @floatFromInt(lo)) - grow + 0.5);
                const b = @floor(@as(f32, @floatFromInt(hi + 1)) + grow + 0.5);
                if (nc > 0 and a <= out[nc - 1].b) {
                    out[nc - 1].b = @max(out[nc - 1].b, b);
                } else if (nc < out.len) {
                    out[nc] = .{ .a = a, .b = b };
                    nc += 1;
                }
                lo = std.math.maxInt(i64);
                hi = std.math.minInt(i64);
            }
        }
    }
    return nc;
}

// ---- inline box decorations (painter `paintInlineBoxes`)

fn isInlineBox(cs: *const CS) bool {
    if (cs.resolveColor(cs.background_color).a != 0) return true;
    if (cs.background_image.len > 0) return true;
    const bw = cs.usedBorderWidths();
    return bw[0] > 0 or bw[1] > 0 or bw[2] > 0 or bw[3] > 0;
}

fn paintInlineBoxes(e: *Emitter, n: *const Node, tl: *const font.TextLayout, x: f32, y: f32) Error!void {
    const f = e.f;
    for (tl.boxes) |*fr| {
        const fi = f.boxFragment(n, fr) orelse continue;
        if (!isInlineBox(fi.cs)) continue;
        // a fragment is drawn on the pages that show its line (takumi `background_fragments`)
        if (e.window.paged() and fr.line < tl.lines.len) {
            const ln = tl.lines[fr.line];
            const it = mapItem(e, .{ .baseline = y + ln.baseline, .top = y + ln.top, .bottom = y + ln.top + ln.height, .l0 = y + ln.top, .l1 = y + ln.top + ln.height }, x + fi.x0, x + fi.x1);
            if (!showsItem(e, it)) continue;
        }
        try paintFragment(e, fi.cs, fr.face, fi.x0, fi.x1, fr.baseline, fi.left, fi.right, x, y);
    }
}

fn paintFragment(e: *Emitter, cs: *const CS, face: font.FaceId, x0: f32, x1: f32, baseline: f32, first: bool, last: bool, x: f32, y: f32) Error!void {
    const m = metricsOf(e, face, cs.font_size);
    var bw = cs.usedBorderWidths();
    const fs = cs.font_size;
    var pad = [4]f32{ cs.padding[0].resolve(fs), cs.padding[1].resolve(fs), cs.padding[2].resolve(fs), cs.padding[3].resolve(fs) };
    if (!first) {
        bw[3] = 0;
        pad[3] = 0;
    }
    if (!last) {
        bw[1] = 0;
        pad[1] = 0;
    }
    const fx = x + x0 - pad[3] - bw[3];
    const fy = y + baseline - m.ascent - pad[0] - bw[0];
    const fw = (x1 - x0) + pad[3] + bw[3] + pad[1] + bw[1];
    const fh = m.ascent + m.descent + pad[0] + bw[0] + pad[2] + bw[2];
    const plain = e.plain();
    var g: pm.Geom = .{
        .bx = if (plain) pm.snapRect(fx, fy, fw, fh) else .{ .x = fx, .y = fy, .w = fw, .h = fh },
        .bw = bw,
        .pad = pad,
        .radii = undefined,
        .rounded = false,
        .snapped = plain,
    };
    g.radii = pm.resolveRadiiRaw(cs, g.bx.w, g.bx.h);
    if (!first) {
        g.radii[0] = .{ 0, 0 };
        g.radii[3] = .{ 0, 0 };
    }
    if (!last) {
        g.radii[1] = .{ 0, 0 };
        g.radii[2] = .{ 0, 0 };
    }
    pm.scaleRadii(&g.radii, g.bx.w, g.bx.h);
    g.rounded = pm.hasAnyRadius(g.radii);
    try e.paintBackground(cs, &g, g.bx.x, g.bx.y);
    try border.paintBorder(&e.d, cs, &g);
}

/// A text node's paragraph at content origin (`x`, `y`) laid out at width `cw`: inline boxes,
/// text shadows, then per run: underline / overline, glyphs (fill + stroke), line-through. Only
/// the runs this page shows (pagination).
pub fn paintText(e: *Emitter, n: *const Node, x: f32, y: f32, cw: f32) Error!void {
    const f = e.f;
    const tl = (try f.textLayout(f.nodeId(n), cw)) orelse {
        if (e.tagged and textRegions(e, n, null, x, y).shows) etag.end(e, etag.begin(e, f.nodeId(n))); // [tagging]
        return;
    };
    if (e.links) |lk| lk.onText(e, n, tl, x, y); // [interactive] links of the runs
    // [tagging] the paragraph's region, on the pages its box or one of its runs reaches
    const regions: TextRegions = if (e.tagged) textRegions(e, n, tl, x, y) else .{ .shows = false };
    for (0..regions.before) |_| etag.end(e, etag.begin(e, f.nodeId(n)));
    const began = if (regions.shows) etag.begin(e, f.nodeId(n)) else false;
    defer for (0..regions.after) |_| etag.end(e, etag.begin(e, f.nodeId(n)));
    defer etag.end(e, began);
    // a symbol list marker paints its shape, no glyph (takumi `TextFragmentPainter::Paint`)
    if (markers.ofNode(f, f.nodeId(n))) |mk| if (mk.shape) |shape| return paintSymbol(e, n, tl, x, y, mk, shape);
    if (tl.boxes.len > 0) try paintInlineBoxes(e, n, tl, x, y);

    var block_deco: ?*const CS = null;
    if (hasLine(n.cs)) {
        block_deco = n.cs;
    } else if (n.parent != none and (n.kind == .text or n.kind == .anon_text)) {
        const pcs = f.nodes.items[n.parent].cs;
        if (hasLine(pcs)) block_deco = pcs;
    }

    // text shadows, last listed first, under all of the text
    if (n.cs.text_shadow.len > 0 and n.cs.visibility == .visible) {
        var si = n.cs.text_shadow.len;
        while (si > 0) {
            si -= 1;
            const sh = n.cs.text_shadow[si];
            const col = n.cs.resolveColor(sh.color);
            if (col.a == 0) continue;
            var it: render.RunIter = .{ .tl = tl };
            while (it.next()) |r| {
                const rcs = runStyle(e, n, &tl.glyphs[r.g0]);
                if (rcs.visibility != .visible) continue;
                const on = runOnPage(e, tl, x, y, r);
                if (!on.shows) continue;
                const run: RunSeg = .{ .g0 = r.g0, .g1 = r.g1, .x0 = r.x0, .x1 = r.x1, .baseline = r.baseline, .rcs = rcs };
                const pass: ShadowPass = .{ .dx = sh.x, .dy = sh.y, .blur = sh.blur, .color = col };
                // the run's decorations cast the shadow too (takumi's text painter under `begin_shadow`)
                var decos: [2]*const CS = undefined;
                const nd = decosOf(n, rcs, block_deco, &decos);
                if (nd > 0) try paintRunDecos(e, pass, tl, x, y, &run, decos[0..nd], false);
                try glyphPass(e, n, tl, x, y, &run, .{ .shadow = pass, .owned = on.owned });
                if (nd > 0) try paintRunDecos(e, pass, tl, x, y, &run, decos[0..nd], true);
            }
        }
    }

    var it: render.RunIter = .{ .tl = tl };
    while (it.next()) |r| {
        const rcs = runStyle(e, n, &tl.glyphs[r.g0]);
        const run: RunSeg = .{ .g0 = r.g0, .g1 = r.g1, .x0 = r.x0, .x1 = r.x1, .baseline = r.baseline, .rcs = rcs };
        if (rcs.visibility != .visible) continue;
        const on = runOnPage(e, tl, x, y, r);
        if (!on.shows) continue;
        var decos: [2]*const CS = undefined;
        const nd = decosOf(n, rcs, block_deco, &decos);
        if (nd > 0) try paintRunDecos(e, null, tl, x, y, &run, decos[0..nd], false);
        try glyphPass(e, n, tl, x, y, &run, .{ .owned = on.owned });
        if (nd > 0) try paintRunDecos(e, null, tl, x, y, &run, decos[0..nd], true);
    }
}

/// takumi `SymbolMarker::paint` (Blink's `PaintSymbol`): the shape of a symbol marker whose box
/// holds the line `tl` at content origin (`x`, `y`), at its offset from the text start on the
/// baseline; the disc / circle / square in the box pixel-snapped there, the disclosure triangle
/// in the unsnapped one. No shadow, no decoration.
fn paintSymbol(e: *Emitter, n: *const Node, tl: *const font.TextLayout, x: f32, y: f32, mk: *const markers.Info, shape: markers.Shape) Error!void {
    var it: render.RunIter = .{ .tl = tl };
    const r = it.next() orelse return;
    const cs = n.cs;
    if (cs.visibility != .visible) return;
    if (!runOnPage(e, tl, x, y, r).shows) return;
    const col = if (cs.webkit_text_fill_color) |c| cs.resolveColor(c) else cs.color;
    const ox = x + r.x0 + mk.off_x;
    const oy = y + r.baseline + mk.off_y;
    const plain = e.plain();
    const bx: Rect = if (plain) pm.snapRect(ox, oy, mk.side, mk.side) else .{ .x = ox, .y = oy, .w = mk.side, .h = mk.side };
    var path: Path = .empty;
    const a = e.a;
    switch (shape) {
        .disc, .circle => {
            const rx = bx.w / 2;
            const ry = bx.h / 2;
            if (!(rx > 0) or !(ry > 0)) return;
            // (built about the box's origin, then moved there: takumi's `at_snapped` transform)
            const cx = rx;
            const cy = ry;
            const k: f32 = 0.552_284_8;
            try path.moveTo(a, cx + rx, cy);
            try path.cubicTo(a, cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry);
            try path.cubicTo(a, cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy);
            try path.cubicTo(a, cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry);
            try path.cubicTo(a, cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy);
            try path.close(a);
            if (shape == .disc) e.d.fillPath(&path, bx.x, bx.y, .nonzero, col) else e.d.strokePath(&path, bx.x, bx.y, 1, null, false, col);
        },
        .square => e.d.fillRRect(bx, null, col),
        .disclosure_left, .disclosure_right, .disclosure_down => {
            const pts: [3][2]f32 = switch (shape) {
                .disclosure_left => .{ .{ 1, 0 }, .{ 0.14, 0.5 }, .{ 1, 1 } },
                .disclosure_right => .{ .{ 0, 0 }, .{ 0.86, 0.5 }, .{ 0, 1 } },
                else => .{ .{ 0, 0.07 }, .{ 0.5, 0.93 }, .{ 1, 0.07 } },
            };
            try path.moveTo(a, pts[0][0] * mk.side, pts[0][1] * mk.side);
            try path.lineTo(a, pts[1][0] * mk.side, pts[1][1] * mk.side);
            try path.lineTo(a, pts[2][0] * mk.side, pts[2][1] * mk.side);
            try path.close(a);
            e.d.fillPath(&path, ox, oy, .nonzero, col);
        },
    }
}

/// [tagging] The paragraph's regions on this page (takumi: one per fragment of the box whose
/// content chunk is visible; a chunk is visible when the node's paint bounds, its box and its
/// glyphs' ascent / descent in whole pixels, meet the page's window). `before` / `after`:
/// the empty regions of the box's fragments on other pages, around this page's own.
/// How far the text shadows reach above (negative) and below the glyphs.
fn shadowReach(cs: *const CS) [2]f32 {
    var r = [2]f32{ 0, 0 };
    for (cs.text_shadow) |sh| {
        r[0] = @min(r[0], sh.y - sh.blur);
        r[1] = @max(r[1], sh.y + sh.blur);
    }
    return r;
}

const TextRegions = struct { shows: bool, before: u32 = 0, after: u32 = 0 };

fn textRegions(e: *Emitter, n: *const Node, tl_in: ?*const font.TextLayout, x: f32, y: f32) TextRegions {
    if (!e.window.paged() or !e.plain()) return .{ .shows = true };
    const l = e.f.tree.layout(n.lid);
    var top = y - l.border.top - l.padding.top;
    var bottom = top + l.h;
    var run_shows = false;
    if (tl_in) |tl| {
        var it: render.RunIter = .{ .tl = tl };
        while (it.next()) |r| {
            if (runOnPage(e, tl, x, y, r).shows) run_shows = true;
            const g = &tl.glyphs[r.g0];
            const fnt = e.f.r.fonts.font(g.face);
            const sc = g.size / @as(f32, @floatFromInt(@max(1, fnt.unitsPerEm())));
            const lm = fnt.lineMetrics();
            top = @min(top, y + r.baseline - @as(f32, @floatFromInt(lm.ascent)) * sc);
            bottom = @max(bottom, y + r.baseline + @as(f32, @floatFromInt(lm.descent)) * sc);
        }
    }
    const ext = shadowReach(n.cs);
    top = @floor(top + ext[0]);
    bottom = @ceil(bottom + ext[1]);
    const shows = run_shows or !e.window.excludes(top, bottom);
    if (!shows) return .{ .shows = false };
    // the box's fragments (one per page it reaches), each with its part of the box and the
    // glyphs of its lines; those this page's window meets each open a region
    const pg = e.f.paginated() orelse return .{ .shows = true };
    const box_top = y - l.border.top - l.padding.top;
    const box_bottom = box_top + l.h;
    var cur: ?usize = null;
    var count: u32 = 0;
    for (pg.pages, 0..) |p, i| {
        if (box_bottom <= p.top or box_top >= p.top + p.height) continue;
        count += 1;
        if (p.top == e.window.top) cur = i;
    }
    const here = cur orelse return .{ .shows = true };
    if (count <= 1) return .{ .shows = true };
    var out: TextRegions = .{ .shows = true };
    for (pg.pages, 0..) |p, i| {
        if (i == here or box_bottom <= p.top or box_top >= p.top + p.height) continue;
        var lo = @max(box_top, p.top);
        var hi = @min(box_bottom, p.top + p.height);
        if (tl_in) |tl| {
            var it: render.RunIter = .{ .tl = tl };
            while (it.next()) |r| {
                if (pg.pageAt(y + r.baseline) != i) continue;
                const g = &tl.glyphs[r.g0];
                const fnt = e.f.r.fonts.font(g.face);
                const sc = g.size / @as(f32, @floatFromInt(@max(1, fnt.unitsPerEm())));
                const lm = fnt.lineMetrics();
                lo = @min(lo, y + r.baseline - @as(f32, @floatFromInt(lm.ascent)) * sc);
                hi = @max(hi, y + r.baseline + @as(f32, @floatFromInt(lm.descent)) * sc);
            }
        }
        if (e.window.excludes(@floor(lo + ext[0]), @ceil(hi + ext[1]))) continue;
        if (i < here) out.before += 1 else out.after += 1;
    }
    return out;
}

/// The decorations a run draws: the block's, then its own span's.
fn decosOf(n: *const Node, rcs: *const CS, block_deco: ?*const CS, out: *[2]*const CS) usize {
    var nd: usize = 0;
    if (block_deco) |d| {
        out[nd] = d;
        nd += 1;
    }
    if (rcs != n.cs and (block_deco == null or rcs != block_deco.?) and hasLine(rcs)) {
        out[nd] = rcs;
        nd += 1;
    }
    return nd;
}

/// `background-clip: text` (takumi `fill_text_clip`): `fills` seen through the glyphs of node
/// `id` (border box at `x`, `y`) and of its descendants, no own paint.
pub fn paintClipText(e: *Emitter, id: u32, x: f32, y: f32, fills: []const text.GlyphBackground) Error!void {
    return clipNode(e, id, x, y, fills, 0);
}

fn clipNode(e: *Emitter, id: u32, x: f32, y: f32, fills: []const text.GlyphBackground, depth: u32) Error!void {
    const f = e.f;
    const n = &f.nodes.items[id];
    if (depth > 64 or (n.kind != .anon_text and n.cs.display == .none)) return;
    const l = f.tree.layout(n.lid);
    if (n.para != null) {
        const cw = l.w - l.border.left - l.border.right - l.padding.left - l.padding.right;
        const cx = x + l.border.left + l.padding.left;
        const cy = y + l.border.top + l.padding.top;
        if (try f.textLayout(id, cw)) |tl| {
            var it: render.RunIter = .{ .tl = tl };
            while (it.next()) |r| {
                const rcs = runStyle(e, n, &tl.glyphs[r.g0]);
                if (rcs.visibility != .visible) continue;
                const on = runOnPage(e, tl, cx, cy, r);
                if (!on.shows) continue;
                const run: RunSeg = .{ .g0 = r.g0, .g1 = r.g1, .x0 = r.x0, .x1 = r.x1, .baseline = r.baseline, .rcs = rcs };
                try glyphPass(e, n, tl, cx, cy, &run, .{ .owned = on.owned, .fills = fills, .with_paint = false });
            }
        }
    }
    var c = n.first_child;
    while (c != none) : (c = f.nodes.items[c].next) {
        const cl = f.tree.layout(f.nodes.items[c].lid);
        try clipNode(e, c, x + cl.x, y + cl.y, fills, depth + 1);
    }
}
