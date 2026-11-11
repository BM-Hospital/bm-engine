//! Paragraph shaping and layout following takumi's (= Blink's) inline layout rules. Shaping is
//! delegated to `shape.zig` (HarfBuzz-style OpenType shaping); with `complex = true` the
//! paragraph is also run through the Unicode bidi algorithm, split into script runs, broken
//! with the full UAX #14 rules and laid out in visual order. Layout rules:
//!  * glyph advance = round(units * size * 65536 / upem) / 65536 px, letter-spacing added after
//!    every glyph (and disables liga/clig/calt), word-spacing added to U+0020 / U+00A0;
//!  * widths that feed layout are ceiled to 1/64 px (`LayoutUnit`), line heights floored to 1/64;
//!  * font ascent / descent / lineGap are each rounded to whole px at the font size;
//!    `line-height: normal` = asc + desc + gap; the half-leading above the baseline is
//!    floor((line_height - (asc + desc)) / 2) in whole px, the rest goes below;
//!  * a line box is the strut (font + line-height of the block); with `line-height: normal` it is
//!    united with the normal-line-height box of every font actually used on the line. With an
//!    explicit line-height the strut alone decides (verified against takumi for mixed-size runs).
const std = @import("std");
const ttf = @import("ttf.zig");
const uni = @import("unicode.zig");
const coll = @import("collection.zig");
const ot = @import("ot.zig");
const shp = @import("shape.zig");
const bidi = @import("bidi.zig");
const color = @import("color.zig");
const Font = ttf.Font;
const FaceId = coll.FaceId;
const FontCollection = coll.FontCollection;

pub const TextStyle = struct {
    /// Family names in priority order (ASCII case-insensitive). Unknown / empty lists fall back to
    /// every registered family in registration order.
    families: []const []const u8 = &.{},
    weight: u16 = 400,
    italic: bool = false,
    /// Font size in px.
    size: f32 = 16,
    letter_spacing: f32 = 0,
    word_spacing: f32 = 0,
    /// Opaque id copied to every glyph of the run (colour / paint index).
    user: u32 = 0,
    /// font-stretch in percent (drives `wdth` of variable fonts and face selection).
    stretch: f32 = 100,
    /// font-optical-sizing: auto (drives `opsz` from the font size).
    optical_sizing: bool = true,
    /// font-variation-settings.
    variations: []const coll.AxisValue = &.{},
    /// font-feature-settings / font-variant-* of this run, applied after
    /// `ParagraphOptions.features` (together at most 32 entries).
    features: []const shp.FeatureSetting = &.{},
};

/// Fallback chain for a style (variable-font instances included).
fn matchStyle(fonts: *const FontCollection, st: TextStyle, out: []FaceId) []FaceId {
    return fonts.matchEx(.{
        .families = st.families,
        .weight = st.weight,
        .italic = st.italic,
        .stretch = st.stretch,
        .size = if (st.optical_sizing) st.size else 0,
        .variations = st.variations,
    }, out);
}

pub const FeatureSetting = shp.FeatureSetting;
pub const ShapeCache = shp.Cache;
pub const Direction = enum { ltr, rtl };
pub const TextWrap = enum { wrap, balance, pretty };

pub const Run = struct {
    text: []const u8,
    style: TextStyle = .{},
    /// A forced line break follows this run in every white-space mode (HTML `<br>`: pass an
    /// empty or non-empty run with this set). U+2028 inside the text does the same.
    hard_break_after: bool = false,
};

pub const LineHeight = union(enum) {
    normal,
    /// Absolute line height in px.
    px: f32,
    /// Multiple of the strut font size (CSS `line-height: <number>`).
    multiple: f32,
};

pub const TextAlign = enum { left, right, center, justify, start, end };
pub const WhiteSpace = enum { normal, nowrap, pre, pre_wrap, pre_line };
pub const WordBreak = uni.WordBreak;
pub const OverflowWrap = enum { normal, anywhere, break_word };

pub const ParagraphOptions = struct {
    /// Wrap width used when `Paragraph.measure` / `layout` are called with `null`
    /// (null here as well = no wrapping; only forced breaks).
    max_width: ?f32 = null,
    text_align: TextAlign = .left,
    line_height: LineHeight = .normal,
    white_space: WhiteSpace = .normal,
    word_break: WordBreak = .normal,
    overflow_wrap: OverflowWrap = .normal,
    /// line-clamp: keep at most this many lines. As in takumi, a clamped paragraph always gets
    /// "…" on its last kept line (independently of `ellipsis`).
    max_lines: ?u32 = null,
    /// text-overflow: ellipsis — "…" on the last allowed line when clamped, and on any line that
    /// still overflows `max_width` (nowrap / unbreakable content).
    ellipsis: bool = false,
    /// Style of the containing block (Blink's "strut": its font metrics take part in every line
    /// box, and it is the font the ellipsis is shaped with). Defaults to the first run's style.
    strut: ?TextStyle = null,
    /// Tab stops every `tab_size` space advances (white-space: pre / pre-wrap).
    tab_size: u8 = 8,
    /// CSS `direction`: paragraph base direction for bidi; `text-align: start / end` follow it.
    /// (Only honoured by the complex path; the simple path is always left-to-right.)
    direction: Direction = .ltr,
    /// BCP 47 language (selects the OpenType language system, e.g. for `locl`).
    lang: []const u8 = "",
    /// text-wrap-style. `balance` (at most 6 lines) and `pretty` (last 4 lines) use Blink's
    /// score-based breaker, `balance` falling back to bisecting the available width.
    /// Ignored together with `max_lines`.
    text_wrap: TextWrap = .wrap,
    /// font-feature-settings / font-variant-* as OpenType features, applied after the defaults.
    features: []const FeatureSetting = &.{},
    /// Long-lived shape-plan cache (see `shape.Cache`); null = rebuild plans per paragraph.
    shape_cache: ?*ShapeCache = null,
};

pub const ShapedGlyph = struct {
    face: FaceId,
    gid: u16,
    /// Byte offset of the source character in the concatenated run texts.
    cluster: u32,
    /// Advance in px, including kerning, letter- and word-spacing.
    x_advance: f32,
    x_offset: f32 = 0,
    y_offset: f32 = 0,
    /// Part of `x_advance` that comes from pair kerning with the FOLLOWING glyph (px); undone
    /// when a line ends right after this glyph.
    kern: f32 = 0,
    /// Index into `Paragraph.metrics` (style + face this glyph was shaped with).
    metric: u16 = 0,
    flags: u8 = 0,
    /// Bidi embedding level (odd = right-to-left).
    level: u8 = 0,
    /// Inline item (style run x bidi run): its origin is snapped to 1/64 px.
    item: u16 = 0,

    /// Soft wrap opportunity before this glyph.
    pub const BREAK_BEFORE: u8 = 1;
    /// Collapsible / hanging space: excluded from line width at line end.
    pub const SPACE: u8 = 2;
    /// Forced line break marker (no glyph to paint).
    pub const HARD_BREAK: u8 = 4;
    /// Word separator (U+0020 / U+00A0): word-spacing and justification apply.
    pub const WORD_SPACE: u8 = 8;
    /// Not the first glyph of its cluster (marks, reordered parts): no emergency break before it.
    pub const NO_SPLIT: u8 = 16;
    /// The break opportunity before this glyph comes from a soft hyphen (U+00AD).
    pub const SOFT_HYPHEN: u8 = 32;
    /// Tab (white-space: pre / pre-wrap): `x_advance` holds the tab-stop interval; the real
    /// advance depends on the position in the line (`Paragraph` resolves it).
    pub const TAB: u8 = 64;
};

pub const PositionedGlyph = struct {
    face: FaceId,
    gid: u16,
    /// Glyph origin (baseline) in paragraph space, px, y down. Not rounded.
    x: f32,
    y: f32,
    /// Font size in px to scale the outline with.
    size: f32,
    user: u32,
    cluster: u32,
    /// Bidi embedding level of the glyph (odd = part of a right-to-left run).
    bidi_level: u8 = 0,
};

pub const Line = struct {
    /// Y of the baseline, top of the line box, and line box height (paragraph space).
    baseline: f32,
    top: f32,
    height: f32,
    /// Left edge after alignment and exact (unrounded) advance width of the visible content
    /// (trailing spaces excluded, ellipsis included).
    x: f32,
    width: f32,
    /// Range into `TextLayout.glyphs`.
    glyph_start: u32,
    glyph_end: u32,
    /// Line box extent above / below the baseline (half-leading included).
    ascent: f32,
    descent: f32,
    /// Paragraph direction is right-to-left (glyph x positions are visual either way).
    rtl: bool = false,
};

pub const Size = struct {
    /// Widest line, ceiled to 1/64 px (what takumi reports as the text box inline size).
    width: f32,
    /// Sum of the line box heights.
    height: f32,
    line_count: u32 = 0,
    /// Widest line, exact float.
    exact_width: f32 = 0,
};

pub const TextLayout = struct {
    width: f32,
    height: f32,
    /// Widest line before the 1/64 ceil.
    exact_width: f32,
    lines: []Line,
    glyphs: []PositionedGlyph,

    pub fn deinit(self: *TextLayout, alloc: std.mem.Allocator) void {
        alloc.free(self.lines);
        alloc.free(self.glyphs);
        self.* = undefined;
    }
};

/// Per (run, face) data shared by glyphs.
pub const Metric = struct {
    run: u16,
    face: FaceId,
    size: f32,
    user: u32,
    /// Line box contribution above / below the baseline for `line-height: normal` (rounded
    /// font ascent / descent plus the font's line gap split as half-leading), px.
    ascent: f32,
    descent: f32,
    /// Unrounded font ascent / descent at this size (for decoration / selection boxes).
    font_ascent: f32,
    font_descent: f32,
    /// Hyphen shown when a line breaks at a soft hyphen (U+2010, else '-', in this face).
    hyphen_gid: u16 = 0,
    hyphen_adv: f32 = 0,
};

pub inline fn ceil64(x: f32) f32 {
    return @ceil(x * 64.0) * (1.0 / 64.0);
}
inline fn ceil64d(x: f64) f64 {
    return @ceil(x * 64.0) * (1.0 / 64.0);
}
pub inline fn floor64(x: f32) f32 {
    return @trunc(x * 64.0) * (1.0 / 64.0);
}

/// Round half away from zero (Rust `f32::round`), without pulling in compiler-rt's `round`.
inline fn roundAway(x: f32) f32 {
    return if (x >= 0) @floor(x + 0.5) else -@floor(0.5 - x);
}

fn computeMetric(font: *const Font, size: f32, lh: LineHeight) [4]f32 {
    const lm = font.lineMetrics();
    const s = size / @as(f32, @floatFromInt(font.units_per_em));
    const fa = @as(f32, @floatFromInt(lm.ascent)) * s;
    const fd = @as(f32, @floatFromInt(lm.descent)) * s;
    const a = roundAway(fa);
    const d = roundAway(fd);
    const line_height = switch (lh) {
        .normal => a + d + roundAway(@as(f32, @floatFromInt(lm.leading)) * s),
        .px => |v| floor64(v),
        .multiple => |m| floor64(m * size),
    };
    const lead_a = @floor((line_height - (a + d)) * 0.5);
    const lead_d = line_height - (a + d) - lead_a;
    return .{ a + lead_a, d + lead_d, fa, fd };
}

/// Advance of `units` font units at `size` px, rounded to 16.16 like HarfBuzz positions.
inline fn scaleAdvance(units: i32, scale: f64) f32 {
    const v = @as(f64, @floatFromInt(units)) * scale;
    const r = if (v >= 0) @floor(v + 0.5) else -@floor(0.5 - v);
    return @floatCast(r * (1.0 / 65536.0));
}

const Char = struct { cp: u21, brk: bool = false, level: u8 = 0, run: u16, cluster: u32 };

const max_faces = 16;

/// Shapes `text` with one style: UTF-8 -> glyphs with fallback, ligatures, kerning and spacing.
/// No white-space processing except: control characters are dropped and zero-width characters
/// produce no glyph. Glyphs are in logical order. Returned slice is owned by the caller
/// (`alloc.free`).
pub fn shape(alloc: std.mem.Allocator, fonts: *const FontCollection, text: []const u8, style: TextStyle) ![]ShapedGlyph {
    var p = try Paragraph.init(alloc, fonts, &.{.{ .text = text, .style = style }}, .{ .white_space = .pre });
    defer p.deinit();
    var n: usize = 0;
    for (p.glyphs) |g| {
        if (g.flags & ShapedGlyph.HARD_BREAK == 0) {
            p.glyphs[n] = g;
            n += 1;
        }
    }
    return alloc.dupe(ShapedGlyph, p.glyphs[0..n]);
}

/// A paragraph shaped once; line breaking for different widths is cheap (`measure` allocates
/// nothing, `layout` allocates only the result).
pub const Paragraph = struct {
    alloc: std.mem.Allocator,
    opts: ParagraphOptions,
    /// Shaped glyphs in logical order (a right-to-left run is stored first-character-first).
    glyphs: []ShapedGlyph,
    metrics: []Metric,
    /// Strut line box contribution.
    strut_ascent: f32 = 0,
    strut_descent: f32 = 0,
    strut_size: f32 = 16,
    ell_face: FaceId = 0,
    ell_gid: u16 = 0,
    ell_count: u8 = 0,
    ell_adv: f32 = 0,
    ell_size: f32 = 0,
    ell_user: u32 = 0,
    /// More than one inline item (style run or bidi run).
    multi_run: bool = false,
    /// Paragraph direction is right-to-left.
    rtl: bool = false,
    /// Some glyph has a non-zero bidi level (lines need visual reordering).
    has_bidi: bool = false,

    /// Compile-time selection of the optional text machinery (see `initWith`).
    pub const Features = struct {
        /// Bidi, script shapers (Arabic, Hebrew, Thai, Indic), normalisation, full UAX #14.
        /// false: default shaper only, left-to-right, none of the Unicode tables are linked.
        complex: bool = true,
        /// Emoji-presentation clusters prefer a face with colour tables (links `color.zig`'s
        /// emoji scanner and `ColorTables`).
        color_emoji: bool = false,
    };

    /// Shapes `runs` (concatenated into one paragraph) with complex-text support (bidi, script
    /// shapers, normalisation, full UAX #14). `alloc` owns the cached glyphs until `deinit`
    /// (a per-render arena is fine). `fonts` is only used during `init`; the texts are not
    /// referenced afterwards.
    /// (In an engine build the complex machinery follows the `complex_text` build switch, read
    /// through `@import("root").bm_config`, so helper callers such as SVG text do not link it.)
    pub fn init(alloc: std.mem.Allocator, fonts: *const FontCollection, runs: []const Run, opts: ParagraphOptions) !Paragraph {
        return initWith(.{ .complex = build_complex }, alloc, fonts, runs, opts);
    }

    const build_complex = blk: {
        const root = @import("root");
        break :blk if (@hasDecl(root, "bm_config")) root.bm_config.enable_complex_text else true;
    };

    /// `init` with complex text selectable at compile time (no colour-emoji font preference).
    pub fn initEx(comptime complex: bool, alloc: std.mem.Allocator, fonts: *const FontCollection, runs: []const Run, opts: ParagraphOptions) !Paragraph {
        return initWith(.{ .complex = complex }, alloc, fonts, runs, opts);
    }

    /// `init` with the optional machinery selected at compile time: code and tables of a
    /// feature that is off are not referenced, so they do not reach the binary.
    pub fn initWith(comptime feat: Features, alloc: std.mem.Allocator, fonts: *const FontCollection, runs: []const Run, opts: ParagraphOptions) !Paragraph {
        const complex = feat.complex;
        var total: usize = 0;
        for (runs) |r| total += r.text.len;
        if (total > 0x3fff_ffff or runs.len > 0xffff) return error.OutOfMemory;

        const chars = try alloc.alloc(Char, total + runs.len);
        defer alloc.free(chars);
        const n_chars = collectChars(runs, opts, chars);
        const rtl_base = complex and opts.direction == .rtl;
        if (complex) {
            try markBreaksFull(alloc, chars[0..n_chars], opts);
            try resolveBidi(alloc, chars[0..n_chars], rtl_base);
        } else markBreaks(chars[0..n_chars], opts);

        var local_cache = shp.Cache.init(alloc);
        defer local_cache.deinit();
        var b: Builder = .{
            .alloc = alloc,
            .fonts = fonts,
            .opts = opts,
            .chars = chars[0..n_chars],
            .cache = opts.shape_cache orelse &local_cache,
            .buf = .{ .alloc = alloc },
        };
        defer b.buf.deinit();
        errdefer b.glyphs.deinit(alloc);
        errdefer b.metrics.deinit(alloc);
        try b.glyphs.ensureTotalCapacity(alloc, n_chars);
        try b.buf.list.ensureTotalCapacity(alloc, @min(n_chars, 256));
        try b.build(feat, runs);

        var p: Paragraph = .{ .alloc = alloc, .opts = opts, .glyphs = &.{}, .metrics = &.{}, .multi_run = b.item > 1, .rtl = rtl_base, .has_bidi = b.any_rtl or rtl_base };
        // strut + ellipsis
        const strut_style: ?TextStyle = opts.strut orelse if (runs.len > 0) runs[0].style else null;
        if (strut_style) |st| {
            var buf: [max_faces]FaceId = undefined;
            const faces = matchStyle(fonts, st, &buf);
            p.strut_size = st.size;
            if (faces.len > 0) {
                const m = computeMetric(fonts.font(faces[0]), st.size, opts.line_height);
                p.strut_ascent = m[0];
                p.strut_descent = m[1];
                if (opts.ellipsis or opts.max_lines != null) {
                    var cp: u21 = 0x2026;
                    p.ell_count = 1;
                    var pick = pickFace(fonts, faces, cp);
                    if (pick.gid == 0) {
                        cp = '.';
                        p.ell_count = 3;
                        pick = pickFace(fonts, faces, cp);
                    }
                    const f = fonts.font(pick.face);
                    p.ell_face = pick.face;
                    p.ell_gid = pick.gid;
                    p.ell_size = st.size;
                    p.ell_user = st.user;
                    p.ell_adv = scaleAdvance(f.advanceWidth(pick.gid), @as(f64, st.size) * 65536.0 / @as(f64, @floatFromInt(f.units_per_em)));
                }
            }
        }
        p.glyphs = try b.glyphs.toOwnedSlice(alloc);
        errdefer alloc.free(p.glyphs);
        p.metrics = try b.metrics.toOwnedSlice(alloc);
        return p;
    }

    pub fn deinit(self: *Paragraph) void {
        self.alloc.free(self.glyphs);
        self.alloc.free(self.metrics);
        self.* = undefined;
    }

    fn wraps(self: *const Paragraph) bool {
        return switch (self.opts.white_space) {
            .normal, .pre_wrap, .pre_line => true,
            .nowrap, .pre => false,
        };
    }

    const LineInfo = struct {
        start: u32,
        /// End of the visible content (trailing spaces excluded; after ellipsis truncation).
        end: u32,
        next: u32,
        width: f32,
        /// Width used for alignment (differs from `width` only for hanging pre-wrap spaces).
        content_w: f32 = 0,
        /// Line ends the paragraph or at a forced break (not justified).
        last: bool,
        /// Broken at a soft hyphen: a visible hyphen follows the content.
        hyphen: bool = false,
        ellipsis: bool = false,
        /// Paragraph-cumulative advance at `next`.
        cum: f64 = 0,
        ascent: f32 = 0,
        descent: f32 = 0,
    };

    const Mode = struct {
        avail: ?f32,
        /// Honour max_lines / ellipsis.
        clamp: bool = true,
        emergency: bool,
        /// text-wrap strategy (only set by measure / layout proper, not by min/max content).
        strategy: TextWrap = .wrap,
    };

    const no_stop: u32 = 0xffff_ffff;

    /// Greedy line breaker reproducing Blink's `ShapingLineBreaker` arithmetic: glyph positions
    /// are cumulative from the paragraph start (`s_cum` at `start`), each ceiled to 1/64 px, and
    /// a break fits when ceil64(position of the break) <= ceil64(position of the line start) +
    /// available width. Kerning against the glyph after a non-space break is undone (Blink
    /// reshapes the line end) and a soft-hyphen break must also fit its hyphen.
    /// `stop_at` != `no_stop` forces the line to end exactly before that glyph (score breaker).
    fn nextLine(self: *const Paragraph, start: u32, s_cum: f64, m: Mode, stop_at: u32) LineInfo {
        const gs = self.glyphs;
        const n: u32 = @intCast(gs.len);
        const forced = stop_at < n;
        const end_i = if (forced) stop_at else n;
        const wrap = !forced and m.avail != null and self.wraps();
        const limit: f64 = ceil64d(s_cum) + @as(f64, if (m.avail) |a| floor64(@max(a, 0)) else 0);
        var i = start;
        var cum = s_cum;
        var cum_content = s_cum;
        var content_end = start;
        var brk: LineInfo = undefined;
        var has_brk = false;
        while (i < end_i) : (i += 1) {
            const g = gs[i];
            // every inline item (style run / bidi run) has its origin snapped to 1/64 px
            if (self.multi_run and i > start and g.item != gs[i - 1].item)
                cum = s_cum + ceil64d(cum - s_cum);
            if (g.flags & ShapedGlyph.HARD_BREAK != 0)
                return self.fin(.{ .start = start, .end = content_end, .next = i + 1, .width = @floatCast(cum_content - s_cum), .last = true, .cum = cum }, s_cum);
            if (wrap and i > start and g.flags & ShapedGlyph.BREAK_BEFORE != 0) {
                var e = cum_content;
                var hyphen = false;
                if (content_end == i) {
                    e -= gs[i - 1].kern;
                    if (g.flags & ShapedGlyph.SOFT_HYPHEN != 0) {
                        hyphen = true;
                        e += self.metrics[gs[i - 1].metric].hyphen_adv;
                    }
                }
                if (!has_brk or e <= limit) {
                    has_brk = true;
                    brk = .{ .start = start, .end = content_end, .next = i, .width = @floatCast(e - s_cum), .last = false, .hyphen = hyphen, .cum = cum };
                }
            }
            const nc = cum + self.advanceOf(g, @floatCast(cum - s_cum));
            if (g.flags & ShapedGlyph.SPACE != 0) {
                cum = nc;
                continue;
            }
            if (wrap and ceil64d(nc) > limit) {
                if (has_brk) return self.fin(brk, s_cum);
                if (m.emergency and i > start and g.flags & ShapedGlyph.NO_SPLIT == 0)
                    return self.fin(.{ .start = start, .end = content_end, .next = i, .width = @floatCast(cum_content - gs[i - 1].kern - s_cum), .last = false, .cum = cum }, s_cum);
            }
            cum = nc;
            cum_content = nc;
            content_end = i + 1;
        }
        if (forced) {
            if (gs[i].flags & ShapedGlyph.HARD_BREAK != 0)
                return self.fin(.{ .start = start, .end = content_end, .next = i + 1, .width = @floatCast(cum_content - s_cum), .last = true, .cum = cum }, s_cum);
            var e = cum_content;
            var hyphen = false;
            if (content_end == i and i > start) {
                e -= gs[i - 1].kern;
                if (gs[i].flags & ShapedGlyph.SOFT_HYPHEN != 0) {
                    hyphen = true;
                    e += self.metrics[gs[i - 1].metric].hyphen_adv;
                }
            }
            return self.fin(.{ .start = start, .end = content_end, .next = i, .width = @floatCast(e - s_cum), .last = false, .hyphen = hyphen, .cum = cum }, s_cum);
        }
        return self.fin(.{ .start = start, .end = content_end, .next = n, .width = @floatCast(cum_content - s_cum), .last = true, .cum = cum }, s_cum);
    }

    /// pre-wrap: hanging spaces count in the reported width (as takumi reports them) but only
    /// take part in alignment on the last line of a paragraph.
    fn fin(self: *const Paragraph, line: LineInfo, s_cum: f64) LineInfo {
        var li = line;
        li.content_w = li.width;
        if (self.opts.white_space == .pre_wrap) {
            li.width = @max(li.width, @as(f32, @floatCast(li.cum - s_cum)));
            if (li.last) li.content_w = li.width;
        }
        return li;
    }

    /// Advance of a glyph at `line_pos` px from the line start (tabs depend on the position).
    inline fn advanceOf(self: *const Paragraph, g: ShapedGlyph, line_pos: f32) f32 {
        if (g.flags & ShapedGlyph.TAB == 0) return g.x_advance;
        const interval = g.x_advance;
        if (!(interval > 0)) return 0;
        var d = interval - (line_pos - interval * @floor(line_pos / interval));
        // Blink: a tab is at least half a space wide
        if (d < interval / @as(f32, @floatFromInt(2 * @as(u32, @max(self.opts.tab_size, 1))))) d += interval;
        return d;
    }

    /// Build switch `text_wrap_balance` (src/config.zig via the root module; on in standalone
    /// tests): without it `balance` / `pretty` wrap greedily like `wrap`.
    const wrap_balance = blk: {
        const root = @import("root");
        break :blk if (@hasDecl(root, "bm_config")) root.bm_config.enable_text_wrap_balance else true;
    };
    const max_balance_lines = 6;
    const max_pretty_lines = 4;
    const max_candidates = 192;

    const LineIter = struct {
        p: *const Paragraph,
        mode: Mode,
        pos: u32 = 0,
        index: u32 = 0,
        cum: f64 = 0,
        /// Break points chosen by the score breaker for the next lines (glyph indices).
        forced: [max_balance_lines]u32 = undefined,
        n_forced: u8 = 0,
        forced_i: u8 = 0,
        /// The current paragraph part has been examined: no new attempt until it ends.
        suspended: bool = false,

        /// Blink's `ScoreLineBreaker` for the paragraph part starting at the current position:
        /// fills `forced` when better break points than the greedy ones are found; `balance`
        /// falls back to bisecting the available width.
        noinline fn prepare(it: *LineIter) void {
            const p = it.p;
            const balance = it.mode.strategy == .balance;
            const avail = floor64(@max(it.mode.avail.?, 0));
            const max_lines: u32 = if (balance) max_balance_lines else max_pretty_lines;
            const n: u32 = @intCast(p.glyphs.len);
            const greedy: Mode = .{ .avail = it.mode.avail, .clamp = false, .emergency = it.mode.emergency };
            // greedy pass
            var pos = it.pos;
            var cum = it.cum;
            var lines: u32 = 0;
            var width_sum: f32 = 0;
            var last: LineInfo = undefined;
            while (true) {
                last = p.nextLine(pos, cum, greedy, no_stop);
                lines += 1;
                width_sum += last.width;
                pos = last.next;
                cum = last.cum;
                if (last.last or pos >= n) break;
                if (lines >= max_lines) return; // too long: try again at the next line (pretty)
            }
            it.suspended = true;
            if (lines <= 1) return;
            if (!balance) {
                // worth it only when the greedy last line is short and a single word
                if (!(last.width < avail / 3.0)) return;
                var k = last.start + 1;
                while (k < last.end) : (k += 1) {
                    if (p.glyphs[k].flags & ShapedGlyph.BREAK_BEFORE != 0) return;
                }
            }
            if (it.score(avail, lines, balance)) return;
            if (!balance or pos < n or it.pos != 0) return;
            // bisection: the narrowest width (to 1 px) that keeps the number of lines
            var upper = avail;
            var lower = floor64(width_sum / @as(f32, @floatFromInt(lines)) * 0.8 + 1.0 / 128.0);
            while (lower + 1.0 < upper) {
                const mid = floor64((upper + lower) * 0.5);
                var m2 = greedy;
                m2.avail = mid;
                var q: u32 = 0;
                var c2: f64 = 0;
                var cnt: u32 = 0;
                while (q < n and cnt <= lines) : (cnt += 1) {
                    const li = p.nextLine(q, c2, m2, no_stop);
                    q = li.next;
                    c2 = li.cum;
                }
                if (cnt <= lines) upper = mid else lower = mid;
            }
            it.mode.avail = upper;
        }

        fn score(it: *LineIter, avail: f32, greedy_lines: u32, balance: bool) bool {
            const p = it.p;
            const gs = p.glyphs;
            const n: u32 = @intCast(gs.len);
            var glyph: [max_candidates]u32 = undefined;
            var pos_no: [max_candidates]f32 = undefined;
            var pos_if: [max_candidates]f32 = undefined;
            var pen: [max_candidates]f32 = undefined;
            const justified = p.opts.text_align == .justify;
            const wfs = avail * p.strut_size;
            const hyphen_penalty: f32 = if (justified) wfs / 2.0 else wfs * 2.0;
            const line_penalty: f32 = if (justified) 0 else hyphen_penalty * 2.0;
            // candidates: every break opportunity of the part, between two sentinels
            var nc: usize = 1;
            glyph[0] = it.pos;
            pos_no[0] = 0;
            pos_if[0] = 0;
            pen[0] = 0;
            const s_cum = it.cum;
            var cum = s_cum;
            var cum_content = s_cum;
            var content_end = it.pos;
            var last_hyphen_run = true;
            var i = it.pos;
            while (i < n) : (i += 1) {
                const g = gs[i];
                if (p.multi_run and i > it.pos and g.item != gs[i - 1].item) cum = s_cum + ceil64d(cum - s_cum);
                if (g.flags & ShapedGlyph.HARD_BREAK != 0) break;
                if (i > it.pos and g.flags & ShapedGlyph.BREAK_BEFORE != 0) {
                    if (nc + 1 >= max_candidates) return false;
                    var e = cum_content;
                    var hy = false;
                    if (content_end == i) {
                        e -= gs[i - 1].kern;
                        if (g.flags & ShapedGlyph.SOFT_HYPHEN != 0) {
                            hy = true;
                            e += p.metrics[gs[i - 1].metric].hyphen_adv;
                        }
                    }
                    glyph[nc] = i;
                    pos_no[nc] = @floatCast(cum - s_cum);
                    pos_if[nc] = @floatCast(e - s_cum);
                    pen[nc] = if (hy) hyphen_penalty else 0;
                    nc += 1;
                }
                const nx = cum + p.advanceOf(g, @floatCast(cum - s_cum));
                cum = nx;
                if (g.flags & ShapedGlyph.SPACE != 0) continue;
                cum_content = nx;
                content_end = i + 1;
            }
            glyph[nc] = i;
            pos_no[nc] = @floatCast(cum_content - s_cum);
            pos_if[nc] = pos_no[nc];
            pen[nc] = 0;
            nc += 1;
            if (nc < 3 + 2) return false;
            // orphans cost more: the last opportunity (and hyphenated ones before it)
            {
                var k = nc - 1;
                while (k > 1 and last_hyphen_run) {
                    k -= 1;
                    last_hyphen_run = pen[k] != 0;
                    pen[k] += 10000.0;
                }
            }
            const overfull: f32 = 1e12;
            var sc: [max_candidates]f32 = undefined;
            var prev: [max_candidates]u8 = undefined;
            var line_ix: [max_candidates]u8 = undefined;
            sc[0] = 0;
            prev[0] = 0;
            line_ix[0] = 0;
            const fit = avail + 1.0 / 64.0;
            var active: usize = 0;
            var end: usize = 1;
            while (end < nc) : (end += 1) {
                const is_last = end == nc - 1;
                var best: f32 = std.math.floatMax(f32);
                var best_prev: usize = 0;
                const start_edge = pos_if[end] - fit;
                var best_hope: f32 = 0;
                const first = active;
                var st: usize = first;
                while (st < end) : (st += 1) {
                    if (sc[st] + best_hope >= best) continue;
                    const delta = pos_no[st] - start_edge;
                    var width_score: f32 = 0;
                    var extra: f32 = 0;
                    if (delta < 0) {
                        width_score = overfull;
                    } else if (is_last and !balance) {
                        extra = 4.0 * pen[st];
                    } else width_score = delta * delta;
                    if (delta < 0) active = st + 1 else best_hope = width_score;
                    const s = sc[st] + width_score + extra;
                    if (s <= best) {
                        best = s;
                        best_prev = st;
                    }
                }
                sc[end] = best + pen[end] + line_penalty;
                prev[end] = @intCast(best_prev);
                line_ix[end] = line_ix[best_prev] +| 1;
            }
            if (line_ix[nc - 1] != greedy_lines or greedy_lines > max_balance_lines) return false;
            var k = nc - 1;
            var li: usize = greedy_lines;
            while (k > 0 and li > 0) {
                li -= 1;
                it.forced[li] = glyph[k];
                k = prev[k];
            }
            if (k != 0 or li != 0) return false;
            it.n_forced = @intCast(greedy_lines);
            it.forced_i = 0;
            return true;
        }

        fn next(it: *LineIter) ?LineInfo {
            const p = it.p;
            const n: u32 = @intCast(p.glyphs.len);
            if (it.pos >= n) return null;
            if (it.mode.clamp) {
                if (p.opts.max_lines) |ml| if (it.index >= ml) return null;
            }
            var stop: u32 = no_stop;
            if ((comptime wrap_balance) and it.mode.strategy != .wrap) {
                if (it.forced_i >= it.n_forced and !it.suspended and (it.mode.strategy == .pretty or it.pos == 0)) it.prepare();
                if (it.forced_i < it.n_forced) {
                    stop = it.forced[it.forced_i];
                    it.forced_i += 1;
                    // the last forced point is the end of the part: break normally there
                    if (stop >= n) stop = no_stop;
                }
            }
            var li = p.nextLine(it.pos, it.cum, it.mode, stop);
            if (li.last) {
                // paragraph part ended: `pretty` looks at the next part afresh
                it.n_forced = 0;
                it.forced_i = 0;
                it.suspended = it.mode.strategy == .balance;
            }
            it.pos = li.next;
            it.cum = li.cum;
            it.index += 1;
            if (it.mode.clamp and p.ell_count != 0) {
                const clamped = if (p.opts.max_lines) |ml| it.index >= ml and li.next < n else false;
                const ell_w = p.ell_adv * @as(f32, @floatFromInt(p.ell_count));
                if (it.mode.avail) |a| {
                    const avail = floor64(@max(a, 0));
                    if ((p.opts.ellipsis and ceil64(li.width) > avail) or (clamped and ceil64(li.width + ell_w) > avail)) {
                        // truncate so that content + ellipsis fits
                        var w: f32 = 0;
                        var k = li.start;
                        while (k < li.end) : (k += 1) {
                            const nw = w + p.advanceOf(p.glyphs[k], w);
                            if (ceil64(nw + ell_w) > avail) break;
                            w = nw;
                        }
                        // keep clusters (marks, reordered syllable parts) whole
                        while (k > li.start and k < li.end and p.glyphs[k].flags & ShapedGlyph.NO_SPLIT != 0) {
                            k -= 1;
                            w -= p.glyphs[k].x_advance;
                        }
                        li.end = k;
                        li.width = w + ell_w;
                        li.content_w = li.width;
                        li.ellipsis = true;
                        li.hyphen = false;
                    } else if (clamped) {
                        li.width += ell_w;
                        li.content_w = li.width;
                        li.ellipsis = true;
                    }
                } else if (clamped) {
                    li.width += ell_w;
                    li.content_w = li.width;
                    li.ellipsis = true;
                }
            }
            // line box: strut united with every (run, face) on the line
            var a = p.strut_ascent;
            var d = p.strut_descent;
            if (p.opts.line_height != .normal) {
                // explicit line-height: the strut alone decides (takumi/Blink text items)
            } else if (p.metrics.len == 1) {
                a = @max(a, p.metrics[0].ascent);
                d = @max(d, p.metrics[0].descent);
            } else {
                var last_m: u16 = 0xffff;
                for (p.glyphs[li.start..li.end]) |g| {
                    if (g.metric == last_m) continue;
                    last_m = g.metric;
                    a = @max(a, p.metrics[g.metric].ascent);
                    d = @max(d, p.metrics[g.metric].descent);
                }
            }
            li.ascent = a;
            li.descent = d;
            return li;
        }
    };

    fn modeFor(self: *const Paragraph, max_width: ?f32) Mode {
        const avail = max_width orelse self.opts.max_width;
        return .{
            .avail = avail,
            .emergency = self.opts.overflow_wrap != .normal,
            .strategy = if (avail != null and self.opts.max_lines == null and self.wraps()) self.opts.text_wrap else .wrap,
        };
    }

    /// Size of the paragraph wrapped at `max_width` (null = `opts.max_width`, which may itself
    /// be null = no wrapping). Allocation-free; safe to call repeatedly from a measure callback.
    pub fn measure(self: *const Paragraph, max_width: ?f32) Size {
        return self.measureMode(self.modeFor(max_width));
    }

    fn measureMode(self: *const Paragraph, m: Mode) Size {
        var it: LineIter = .{ .p = self, .mode = m };
        var s: Size = .{ .width = 0, .height = 0 };
        while (it.next()) |li| {
            s.exact_width = @max(s.exact_width, li.width);
            s.height += li.ascent + li.descent;
            s.line_count += 1;
        }
        s.width = ceil64(s.exact_width);
        return s;
    }

    /// Widest line when breaking only at forced breaks (1/64-ceiled).
    pub fn maxContentWidth(self: *const Paragraph) f32 {
        return self.measureMode(.{ .avail = null, .clamp = false, .emergency = false }).width;
    }

    /// Widest unbreakable piece (1/64-ceiled): the width when every soft wrap opportunity is
    /// taken (`overflow-wrap: anywhere` also splits words; `break-word` does not, as in CSS).
    pub fn minContentWidth(self: *const Paragraph) f32 {
        return self.measureMode(.{ .avail = 0, .clamp = false, .emergency = self.opts.overflow_wrap == .anywhere }).width;
    }

    /// Full layout at `max_width` (null = `opts.max_width`; alignment then uses the widest
    /// line as the container width when both are null). The result is allocated with `alloc`
    /// (typically the per-render arena) and freed with `TextLayout.deinit`. Glyph x positions
    /// are visual (left to right on screen) whatever the direction of their run.
    pub fn layout(self: *const Paragraph, alloc: std.mem.Allocator, max_width: ?f32) !TextLayout {
        const m = self.modeFor(max_width);
        const size = self.measureMode(m);
        // scratch for visual reordering (allocated first: the outputs can then grow in place
        // in a bump arena)
        const scratch_n = if (self.has_bidi) self.glyphs.len else 0;
        const order = try alloc.alloc(u32, scratch_n);
        defer alloc.free(order);
        const levels = try alloc.alloc(u8, scratch_n);
        defer alloc.free(levels);
        var lines = try alloc.alloc(Line, size.line_count);
        errdefer alloc.free(lines);
        @memset(lines, std.mem.zeroes(Line));
        var out: std.ArrayList(PositionedGlyph) = .empty;
        errdefer out.deinit(alloc);
        try out.ensureTotalCapacity(alloc, self.glyphs.len + @as(usize, size.line_count) * (@as(usize, self.ell_count) + 1));

        const container = if (m.avail) |a| a else size.width;
        const base_level: u8 = @intFromBool(self.rtl);
        var it: LineIter = .{ .p = self, .mode = m };
        var top: f32 = 0;
        var li_index: usize = 0;
        while (it.next()) |li| : (li_index += 1) {
            if (li_index >= lines.len) break;
            // Blink aligns on the LayoutUnit grid: free space = available - snapped line width
            const free_raw = floor64(container) - ceil64(li.content_w);
            const free = @max(free_raw, 0);
            var extra: f32 = 0;
            if (self.opts.text_align == .justify and !li.last and !li.ellipsis and free > 0) {
                var spaces: u32 = 0;
                for (self.glyphs[li.start..li.end]) |g| {
                    if (g.flags & ShapedGlyph.WORD_SPACE != 0) spaces += 1;
                }
                if (spaces > 0) extra = free / @as(f32, @floatFromInt(spaces));
            }
            var x: f32 = switch (self.opts.text_align) {
                .left => 0,
                .right => free,
                .center => floor64(free * 0.5),
                .start => if (self.rtl) free else 0,
                .end => if (self.rtl) 0 else free,
                .justify => if (self.rtl and extra == 0) free else 0,
            };
            // an overflowing line keeps its start edge: in a right-to-left paragraph it sticks
            // out on the left
            if (free_raw < 0) x = if (self.rtl) free_raw else 0;
            const line_x = x;
            const baseline = top + li.ascent;
            const g_start = out.items.len;
            const count: usize = li.end - li.start;
            const ell_cluster: u32 = if (li.end < self.glyphs.len) self.glyphs[li.end].cluster else if (li.end > 0) self.glyphs[li.end - 1].cluster else 0;
            // visual order of the line's glyphs (L1 + L2)
            var visual = false;
            if (self.has_bidi and count != 0) {
                const lv = levels[0..count];
                var trailing = true;
                var k = count;
                while (k > 0) {
                    k -= 1;
                    const g = self.glyphs[li.start + k];
                    lv[k] = g.level;
                    // L1: tabs, and white space before them / at the line end, take the paragraph level
                    if (g.flags & ShapedGlyph.TAB != 0) {
                        lv[k] = base_level;
                        trailing = true;
                    } else if (trailing and g.flags & ShapedGlyph.WORD_SPACE != 0) {
                        lv[k] = base_level;
                    } else trailing = false;
                    if (lv[k] != 0) visual = true;
                }
                if (visual) bidi.reorderVisual(lv, order[0..count]);
            }
            // in a right-to-left paragraph the ellipsis sits at the left (end) edge
            if (li.ellipsis and self.rtl) x = self.putEllipsis(&out, x, baseline, ell_cluster);
            var prev_item: u32 = 0xffff_ffff;
            var v: usize = 0;
            while (v < count) : (v += 1) {
                const gi = li.start + (if (visual) order[v] else @as(u32, @intCast(v)));
                const g = self.glyphs[gi];
                const mt = self.metrics[g.metric];
                if (self.multi_run and g.item != prev_item) {
                    if (prev_item != 0xffff_ffff) x = line_x + ceil64(x - line_x);
                    prev_item = g.item;
                }
                // soft-hyphen break: the hyphen follows the last logical glyph of the line
                const hyphen_here = li.hyphen and gi + 1 == li.end;
                if (hyphen_here and g.level & 1 != 0) {
                    out.appendAssumeCapacity(.{ .face = mt.face, .gid = mt.hyphen_gid, .x = x, .y = baseline, .size = mt.size, .user = mt.user, .cluster = g.cluster, .bidi_level = g.level });
                    x += mt.hyphen_adv - g.kern;
                }
                out.appendAssumeCapacity(.{
                    .face = g.face,
                    .gid = g.gid,
                    .x = x + g.x_offset,
                    .y = baseline - g.y_offset,
                    .size = mt.size,
                    .user = mt.user,
                    .cluster = g.cluster,
                    .bidi_level = g.level,
                });
                x += self.advanceOf(g, x - line_x);
                if (g.flags & ShapedGlyph.WORD_SPACE != 0) x += extra;
                if (hyphen_here and g.level & 1 == 0) {
                    out.appendAssumeCapacity(.{ .face = mt.face, .gid = mt.hyphen_gid, .x = x - g.kern, .y = baseline, .size = mt.size, .user = mt.user, .cluster = g.cluster, .bidi_level = g.level });
                    x += mt.hyphen_adv - g.kern;
                }
            }
            if (li.ellipsis and !self.rtl) x = self.putEllipsis(&out, x, baseline, ell_cluster);
            lines[li_index] = .{
                .baseline = baseline,
                .top = top,
                .height = li.ascent + li.descent,
                .x = line_x,
                .width = if (extra != 0) x - line_x else li.width,
                .glyph_start = @intCast(g_start),
                .glyph_end = @intCast(out.items.len),
                .ascent = li.ascent,
                .descent = li.descent,
                .rtl = self.rtl,
            };
            top += li.ascent + li.descent;
        }
        return .{
            .width = size.width,
            .height = size.height,
            .exact_width = size.exact_width,
            .lines = lines,
            .glyphs = try out.toOwnedSlice(alloc),
        };
    }

    fn putEllipsis(self: *const Paragraph, out: *std.ArrayList(PositionedGlyph), x_in: f32, baseline: f32, cluster: u32) f32 {
        var x = x_in;
        var k: u8 = 0;
        while (k < self.ell_count) : (k += 1) {
            out.appendAssumeCapacity(.{ .face = self.ell_face, .gid = self.ell_gid, .x = x, .y = baseline, .size = self.ell_size, .user = self.ell_user, .cluster = cluster, .bidi_level = @intFromBool(self.rtl) });
            x += self.ell_adv;
        }
        return x;
    }

    /// Alias of `layout` (name used in the module brief).
    pub fn breakLines(self: *const Paragraph, alloc: std.mem.Allocator, max_width: ?f32) !TextLayout {
        return self.layout(alloc, max_width);
    }
};

/// One-shot convenience: shape + lay out at `opts.max_width`.
pub fn layoutText(alloc: std.mem.Allocator, fonts: *const FontCollection, runs: []const Run, opts: ParagraphOptions) !TextLayout {
    var p = try Paragraph.init(alloc, fonts, runs, opts);
    defer p.deinit();
    return p.layout(alloc, null);
}

// ------------------------------------------------------------------ internals

const hard_break_cp: u21 = '\n';

/// White-space processing: UTF-8 decode all runs into `out`, collapsing / preserving spaces
/// per `white-space`. Returns the number of characters written.
fn collectChars(runs: []const Run, opts: ParagraphOptions, out: []Char) usize {
    const collapse = switch (opts.white_space) {
        .normal, .nowrap, .pre_line => true,
        .pre, .pre_wrap => false,
    };
    var n: usize = 0;
    var base: u32 = 0;
    var prev_space = true; // strips leading collapsible space
    var prev_cr = false;
    for (runs, 0..) |r, ri| {
        const s = r.text;
        var i: usize = 0;
        while (i < s.len) {
            const d = uni.decodeUtf8(s, i);
            const cluster = base + @as(u32, @intCast(i));
            i += d.len;
            var cp = d.cp;
            const was_cr = prev_cr;
            prev_cr = cp == '\r';
            if (cp == 0x2028) {
                // LINE SEPARATOR: a preserved segment break in every white-space mode
                if (collapse and n > 0 and out[n - 1].cp == ' ') n -= 1;
                if (collapse) prev_space = true;
                out[n] = .{ .cp = hard_break_cp, .run = @intCast(ri), .cluster = cluster };
                n += 1;
                continue;
            }
            if (cp == '\n' or cp == '\r' or cp == 0x0c) {
                if (collapse and opts.white_space != .pre_line) {
                    cp = ' ';
                } else {
                    if (cp == '\n' and was_cr) continue; // CRLF
                    if (collapse) {
                        // pre-line: spaces around a preserved newline vanish
                        if (n > 0 and out[n - 1].cp == ' ') n -= 1;
                        prev_space = true;
                    }
                    out[n] = .{ .cp = hard_break_cp, .run = @intCast(ri), .cluster = cluster };
                    n += 1;
                    continue;
                }
            }
            if (collapse) {
                if (cp == ' ' or cp == '\t') {
                    if (prev_space) continue;
                    prev_space = true;
                    cp = ' ';
                } else prev_space = false;
            }
            if (cp != '\t' and (cp < 0x20 or (cp >= 0x7f and cp < 0xa0))) continue;
            out[n] = .{ .cp = cp, .run = @intCast(ri), .cluster = cluster };
            n += 1;
        }
        base += @intCast(s.len);
        if (r.hard_break_after) {
            if (collapse and n > 0 and out[n - 1].cp == ' ') n -= 1;
            if (collapse) prev_space = true;
            out[n] = .{ .cp = hard_break_cp, .run = @intCast(ri), .cluster = base };
            n += 1;
            prev_cr = false;
        }
    }
    return n;
}

fn markBreaks(chars: []Char, opts: ParagraphOptions) void {
    if (opts.white_space == .nowrap or opts.white_space == .pre) return;
    var bb: u21 = 0;
    var b: u21 = 0;
    for (chars, 0..) |*c, i| {
        if (i > 0 and b != hard_break_cp and c.cp != hard_break_cp)
            c.brk = uni.canBreak(bb, if (b == '\t') ' ' else b, if (c.cp == '\t') ' ' else c.cp, opts.word_break);
        bb = b;
        b = c.cp;
    }
}

/// `markBreaks` with the full UAX #14 rules (`unicode.lineBreaks`) behind Blink's overrides:
/// always break after a run of spaces, Chromium's table for printable-ASCII pairs.
fn markBreaksFull(alloc: std.mem.Allocator, chars: []Char, opts: ParagraphOptions) !void {
    if (opts.white_space == .nowrap or opts.white_space == .pre) return;
    // pure ASCII without break-all never consults UAX #14
    var need_uax = opts.word_break == .break_all;
    if (!need_uax) {
        for (chars) |c| {
            if (c.cp >= 0x80) {
                need_uax = true;
                break;
            }
        }
    }
    const cls = try alloc.alloc(u8, if (need_uax) chars.len else 0);
    defer alloc.free(cls);
    if (need_uax) {
        for (chars, cls) |c, *k| {
            k.* = if (c.cp == hard_break_cp) @backingInt(uni.Lb.bk) else if (c.cp == '\t') @backingInt(uni.Lb.sp) else uni.lbByte(c.cp);
        }
        uni.lineBreaksPrepare(cls, opts.word_break);
    }
    var bb: u21 = 0;
    var b: u21 = 0;
    for (chars, 0..) |*c, i| {
        const a: u21 = if (c.cp == '\t') ' ' else c.cp;
        if (b != 0 and b != hard_break_cp and a != hard_break_cp) {
            if (b == ' ') {
                c.brk = a != ' ';
            } else if (uni.isAsciiPair(b, a)) {
                c.brk = uni.asciiPairBreak(bb, b, a) or (opts.word_break == .break_all and uni.lineBreakAt(cls, i));
            } else c.brk = uni.lineBreakAt(cls, i);
        }
        bb = b;
        b = a;
    }
}

/// UAX #9 levels for every paragraph part (parts are separated by forced breaks).
fn resolveBidi(alloc: std.mem.Allocator, chars: []Char, rtl_base: bool) !void {
    const n = chars.len;
    if (n == 0) return;
    var need = rtl_base;
    if (!need) {
        for (chars) |c| {
            if (c.cp >= 0x590) {
                need = true;
                break;
            }
        }
    }
    if (!need) return;
    const cps = try alloc.alloc(u21, n);
    defer alloc.free(cps);
    for (chars, cps) |c, *p| p.* = c.cp;
    if (!rtl_base and !bidi.needsBidi(cps)) return;
    const levels = try alloc.alloc(u8, n);
    defer alloc.free(levels);
    const base: u8 = @intFromBool(rtl_base);
    var s: usize = 0;
    while (s < n) {
        var e = s;
        while (e < n and cps[e] != hard_break_cp) e += 1;
        try bidi.resolve(alloc, cps[s..e], levels[s..e], base);
        if (e < n) levels[e] = base;
        s = e + 1;
    }
    for (chars, levels) |*c, l| c.level = l;
}

const Pick = struct { face: FaceId, gid: u16 };

fn pickFace(fonts: *const FontCollection, faces: []const FaceId, cp: u21) Pick {
    for (faces) |id| {
        const g = fonts.font(id).glyphIndex(cp);
        if (g != 0) return .{ .face = id, .gid = g };
    }
    return .{ .face = faces[0], .gid = 0 };
}

const BracketRec = struct { close: u16, script: u8 };

const Builder = struct {
    alloc: std.mem.Allocator,
    fonts: *const FontCollection,
    opts: ParagraphOptions,
    chars: []Char,
    cache: *shp.Cache,
    /// Pending segment (same style run, face, script and bidi level) awaiting shaping.
    buf: ot.Buffer,
    glyphs: std.ArrayList(ShapedGlyph) = .empty,
    metrics: std.ArrayList(Metric) = .empty,
    seg_face: FaceId = 0,
    seg_metric: u16 = 0,
    seg_script: u8 = 0,
    seg_level: u8 = 0,
    /// Running starter of the current cluster (for composition-aware font fallback).
    starter: u21 = 0,
    prev_cp: u21 = 0,
    /// Inline item counter (style run x bidi run).
    item: u16 = 0,
    /// Features of the current style run (`ParagraphOptions.features` + `TextStyle.features`).
    feats: [32]shp.FeatureSetting = undefined,
    n_feats: u8 = 0,
    /// Open brackets and the script of the run they were opened in.
    brackets: [32]BracketRec = undefined,
    n_brackets: u8 = 0,
    any_rtl: bool = false,
    /// Index of the first char whose break flag has not been attributed to a glyph yet.
    brk_from: usize = 0,

    fn metricFor(b: *Builder, run: u16, face: FaceId, style: TextStyle) !u16 {
        for (b.metrics.items, 0..) |m, i| {
            if (m.run == run and m.face == face) return @intCast(i);
        }
        if (b.metrics.items.len >= 0xffff) return error.OutOfMemory;
        const f = b.fonts.font(face);
        const m = computeMetric(f, style.size, .normal);
        var hy = f.glyphIndex(0x2010);
        if (hy == 0) hy = f.glyphIndex('-');
        try b.metrics.append(b.alloc, .{
            .run = run,
            .face = face,
            .size = style.size,
            .user = style.user,
            .ascent = m[0],
            .descent = m[1],
            .font_ascent = m[2],
            .font_descent = m[3],
            .hyphen_gid = hy,
            .hyphen_adv = scaleAdvance(f.advanceWidth(hy), @as(f64, style.size) * 65536.0 / @as(f64, @floatFromInt(f.units_per_em))),
        });
        return @intCast(b.metrics.items.len - 1);
    }

    /// Break flags (BREAK_BEFORE / SOFT_HYPHEN) for a glyph whose first character is `upto`,
    /// gathering the opportunities of skipped (zero-width) characters before it.
    fn takeBreak(b: *Builder, upto: usize) u8 {
        var fl: u8 = 0;
        if (upto < b.brk_from) return 0;
        var i = b.brk_from;
        while (i <= upto) : (i += 1) {
            if (b.chars[i].brk) {
                fl |= ShapedGlyph.BREAK_BEFORE;
                if (i > 0 and b.chars[i - 1].cp == 0xad) fl |= ShapedGlyph.SOFT_HYPHEN;
            }
        }
        b.brk_from = upto + 1;
        return fl;
    }

    fn build(b: *Builder, comptime feat: Paragraph.Features, runs: []const Run) !void {
        const complex = feat.complex;
        // characters left in the current emoji-presentation cluster, and its colour face
        var emoji_left: usize = 0;
        var emoji_face: ?FaceId = null;
        var faces_buf: [max_faces]FaceId = undefined;
        var faces: []FaceId = &.{};
        var cur_run: u32 = 0xffff_ffff;
        var cur_level: u8 = 0;
        var primary_metric: u16 = 0;
        var style: TextStyle = .{};
        // script of the last strong character (Common / Inherited characters take it)
        var cur_script: u8 = 0;
        const hang = b.opts.white_space != .pre;
        try b.glyphs.ensureUnusedCapacity(b.alloc, b.chars.len);
        for (b.chars, 0..) |c, ci| {
            if (c.run != cur_run or c.level != cur_level) {
                try b.flush(complex, style);
                if (c.run != cur_run) {
                    cur_run = c.run;
                    style = runs[c.run].style;
                    faces = matchStyle(b.fonts, style, &faces_buf);
                    // paragraph features first, then the run's own
                    b.n_feats = 0;
                    for ([_][]const shp.FeatureSetting{ b.opts.features, style.features }) |list| {
                        for (list) |ft| {
                            if (b.n_feats < b.feats.len) {
                                b.feats[b.n_feats] = ft;
                                b.n_feats += 1;
                            }
                        }
                    }
                    if (faces.len > 0) primary_metric = try b.metricFor(c.run, faces[0], style);
                    cur_script = 0;
                }
                cur_level = c.level;
                if (c.level != 0) b.any_rtl = true;
                b.item +|= 1;
            }
            if (faces.len == 0) continue; // no fonts registered: nothing to shape
            if (c.cp == hard_break_cp) {
                try b.flush(complex, style);
                _ = b.takeBreak(ci);
                try b.glyphs.append(b.alloc, .{ .face = faces[0], .gid = 0, .cluster = c.cluster, .x_advance = 0, .metric = primary_metric, .flags = ShapedGlyph.HARD_BREAK, .level = c.level, .item = b.item });
                continue;
            }
            const joiner = uni.isShapingControl(c.cp);
            if (uni.isZeroWidth(c.cp) and !joiner) continue;
            if (c.cp == '\t') {
                try b.flush(complex, style);
                const pick = pickFace(b.fonts, faces, ' ');
                const f = b.fonts.font(pick.face);
                const sp = scaleAdvance(f.advanceWidth(pick.gid), @as(f64, style.size) * 65536.0 / @as(f64, @floatFromInt(f.units_per_em))) + style.letter_spacing + style.word_spacing;
                const tab_w = sp * @as(f32, @floatFromInt(b.opts.tab_size));
                var flags: u8 = ShapedGlyph.TAB | (if (hang) ShapedGlyph.SPACE else 0);
                flags |= b.takeBreak(ci);
                try b.glyphs.append(b.alloc, .{ .face = pick.face, .gid = pick.gid, .cluster = c.cluster, .x_advance = @max(tab_w, 0), .metric = primary_metric, .flags = flags, .level = c.level, .item = b.item });
                continue;
            }
            const pending = b.buf.g().len != 0;
            // font: joiners and cluster continuations stay with the face of their base when it
            // can render them; everything else takes the first face that covers it
            var face: FaceId = if (pending) b.seg_face else faces[0];
            var gid: u16 = 0;
            if (feat.color_emoji and emoji_left == 0 and (c.cp >= 0x203c or c.cp == '#' or c.cp == '*' or (c.cp >= '0' and c.cp <= '9') or c.cp == 0xa9 or c.cp == 0xae)) {
                // emoji sequence starting here? (Blink segments emoji-presentation runs and
                // gives them to colour faces first)
                var look: [24]u21 = undefined;
                var nl: usize = 0;
                while (nl < look.len and ci + nl < b.chars.len and b.chars[ci + nl].run == c.run) : (nl += 1) look[nl] = b.chars[ci + nl].cp;
                const cl = color.scanEmoji(look[0..nl]);
                if (cl.len != 0 and cl.emoji_presentation) {
                    emoji_left = cl.len;
                    emoji_face = null;
                    for (faces) |id| {
                        const fnt = b.fonts.font(id);
                        if (fnt.glyphIndex(c.cp) != 0 and color.ColorTables.init(fnt).hasColor()) {
                            emoji_face = id;
                            break;
                        }
                    }
                    // an emoji run never shares a segment with the text before it
                    if (pending and emoji_face != null and emoji_face.? != b.seg_face) try b.flush(complex, style);
                }
            }
            var forced = false;
            if (feat.color_emoji and emoji_left != 0) {
                emoji_left -= 1;
                if (emoji_face) |ef| {
                    face = ef;
                    gid = b.fonts.font(ef).glyphIndex(c.cp);
                    b.starter = c.cp;
                    forced = true;
                }
            }
            if (joiner or forced) {
                // never a reason to fall back
            } else {
                // a cluster continuation (mark, modifier, ...) stays in the face of its base even
                // when that face has no glyph for it: Blink picks fallback fonts per cluster from
                // the base character (oracle: Inter "1" + U+20E3 renders .notdef, not Roboto's keycap)
                const cont = pending and (if (complex) uni.isContinuation(b.prev_cp, c.cp) else uni.isContinuationSimple(b.prev_cp, c.cp));
                if (cont) {
                    gid = b.fonts.font(b.seg_face).glyphIndex(c.cp);
                } else {
                    face = faces[0];
                    for (faces) |id| {
                        gid = b.fonts.font(id).glyphIndex(c.cp);
                        var st: u21 = 0;
                        if (gid != 0 or (complex and c.cp >= 0xc0 and shp.fontCovers(complex, b.fonts.font(id), &st, c.cp))) {
                            face = id;
                            break;
                        }
                    }
                    b.starter = c.cp;
                }
            }
            b.prev_cp = c.cp;
            var metric = primary_metric;
            if (face != faces[0]) metric = try b.metricFor(c.run, face, style);
            // script: strong characters decide, the rest follow
            var script = cur_script;
            if (!joiner) {
                const s: u8 = if (complex) uni.script(c.cp) else shp.simpleScript(c.cp);
                const strong = if (complex) s > 2 else s != 0;
                if (strong) {
                    script = s;
                    // brackets opened before the run had a script take it now
                    if (complex and cur_script == 0) {
                        for (b.brackets[0..b.n_brackets]) |*e| {
                            if (e.script == 0) e.script = s;
                        }
                    }
                } else if (complex and c.cp < 0x10000) {
                    // Blink's ScriptRunIterator: a closing bracket takes the script of its opener
                    if (uni.bracket(c.cp)) |br| {
                        if (br.open) {
                            if (b.n_brackets == b.brackets.len) {
                                std.mem.copyForwards(BracketRec, b.brackets[0 .. b.brackets.len - 1], b.brackets[1..]);
                                b.n_brackets -= 1;
                            }
                            b.brackets[b.n_brackets] = .{ .close = @intCast(br.pair), .script = cur_script };
                            b.n_brackets += 1;
                        } else {
                            var k = b.n_brackets;
                            while (k > 0) {
                                k -= 1;
                                if (b.brackets[k].close == c.cp) {
                                    if (b.brackets[k].script != 0) script = b.brackets[k].script;
                                    b.n_brackets = k + 1;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            if (pending) {
                if (face != b.seg_face or metric != b.seg_metric) {
                    try b.flush(complex, style);
                } else if (script != b.seg_script) {
                    // a segment that has seen no strong character yet adopts the script
                    if (b.seg_script == 0) b.seg_script = script else try b.flush(complex, style);
                }
            }
            cur_script = script;
            if (b.buf.g().len == 0) {
                b.buf.reset(c.level & 1 != 0);
                b.seg_face = face;
                b.seg_metric = metric;
                b.seg_script = script;
                b.seg_level = c.level;
            }
            try b.buf.list.append(b.alloc, .{ .cp = c.cp, .cluster = @intCast(ci), .gid = gid });
        }
        try b.flush(complex, style);
    }

    /// Shapes the pending segment and appends its glyphs: advances, kerning, spacing, flags.
    fn flush(b: *Builder, comptime complex: bool, style: TextStyle) !void {
        if (b.buf.g().len == 0) return;
        const f = b.fonts.font(b.seg_face);
        const rtl = b.seg_level & 1 != 0;
        try shp.shape(complex, b.cache, f, &b.buf, .{
            .script = b.seg_script,
            .rtl = rtl,
            .lang = b.opts.lang,
            .spaced = style.letter_spacing != 0,
            .features = b.feats[0..b.n_feats],
        });
        const gs = b.buf.g();
        defer b.buf.list.clearRetainingCapacity();
        try b.glyphs.ensureUnusedCapacity(b.alloc, gs.len);
        const scale = @as(f64, style.size) * 65536.0 / @as(f64, @floatFromInt(f.units_per_em));
        const hang = b.opts.white_space != .pre;
        const spacing: f32 = if (complex and shp.isCursiveScript(b.seg_script)) 0 else style.letter_spacing;
        for (gs, 0..) |g, j| {
            const first = j == 0 or gs[j - 1].cluster != g.cluster;
            const last = j + 1 == gs.len or gs[j + 1].cluster != g.cluster;
            const ci: usize = @min(g.cluster, b.chars.len - 1);
            const c = b.chars[ci];
            var flags: u8 = 0;
            var adv: f32 = scaleAdvance(g.x_adv, scale);
            const kern: f32 = if (g.kern != 0 and g.x_adv != 0) adv - scaleAdvance(g.x_adv - g.kern, scale) else 0;
            // letter-spacing goes after every cluster (on its last glyph; the first one in a
            // right-to-left run, where it is the visually last)
            if (if (rtl) first else last) adv += spacing;
            if (first) {
                if (c.cp == ' ' or c.cp == 0xa0) {
                    adv += style.word_spacing;
                    flags |= ShapedGlyph.WORD_SPACE;
                    if (c.cp == ' ' and hang) flags |= ShapedGlyph.SPACE;
                }
                flags |= b.takeBreak(ci);
            } else flags |= ShapedGlyph.NO_SPLIT;
            b.glyphs.appendAssumeCapacity(.{
                .face = b.seg_face,
                .gid = g.gid,
                .cluster = c.cluster,
                .x_advance = adv,
                .x_offset = if (g.x_off != 0) scaleAdvance(g.x_off, scale) else 0,
                .y_offset = if (g.y_off != 0) scaleAdvance(g.y_off, scale) else 0,
                .kern = kern,
                .metric = b.seg_metric,
                .flags = flags,
                .level = b.seg_level,
                .item = b.item,
            });
        }
    }
};
