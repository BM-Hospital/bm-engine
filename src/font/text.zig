//! Shaping (simple LTR: cmap + GSUB ligatures + GPOS/kern pair kerning) and paragraph layout
//! following takumi's (= Blink's) inline layout rules:
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
};

pub const Run = struct { text: []const u8, style: TextStyle = .{} };

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

    /// Soft wrap opportunity before this glyph.
    pub const BREAK_BEFORE: u8 = 1;
    /// Collapsible / hanging space: excluded from line width at line end.
    pub const SPACE: u8 = 2;
    /// Forced line break marker (no glyph to paint).
    pub const HARD_BREAK: u8 = 4;
    /// Word separator (U+0020 / U+00A0): word-spacing and justification apply.
    pub const WORD_SPACE: u8 = 8;
    /// Combining mark: no emergency break before it.
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

const Char = struct { cp: u21, brk: bool = false, run: u16, cluster: u32 };

const max_faces = 16;

/// Shapes `text` with one style: UTF-8 -> glyphs with fallback, ligatures, kerning and spacing.
/// No white-space processing except: control characters are dropped and zero-width characters
/// produce no glyph. Returned slice is owned by the caller (`alloc.free`).
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
    glyphs: []ShapedGlyph,
    metrics: []Metric,
    /// Strut line box contribution.
    strut_ascent: f32 = 0,
    strut_descent: f32 = 0,
    ell_face: FaceId = 0,
    ell_gid: u16 = 0,
    ell_count: u8 = 0,
    ell_adv: f32 = 0,
    ell_size: f32 = 0,
    ell_user: u32 = 0,
    multi_run: bool = false,

    /// Shapes `runs` (concatenated into one paragraph). `alloc` owns the cached glyphs until
    /// `deinit` (a per-render arena is fine). `fonts` is only used during `init`; the texts are
    /// not referenced afterwards.
    pub fn init(alloc: std.mem.Allocator, fonts: *const FontCollection, runs: []const Run, opts: ParagraphOptions) !Paragraph {
        var total: usize = 0;
        for (runs) |r| total += r.text.len;
        if (total > 0x3fff_ffff or runs.len > 0xffff) return error.OutOfMemory;

        const chars = try alloc.alloc(Char, total);
        defer alloc.free(chars);
        const n_chars = collectChars(runs, opts, chars);
        markBreaks(chars[0..n_chars], opts);

        var b: Builder = .{ .alloc = alloc, .fonts = fonts, .opts = opts, .chars = chars[0..n_chars] };
        defer b.deinitTemp();
        errdefer b.glyphs.deinit(alloc);
        errdefer b.metrics.deinit(alloc);
        try b.glyphs.ensureTotalCapacity(alloc, n_chars);
        b.tmp_gids = try alloc.alloc(u16, n_chars);
        b.tmp_idx = try alloc.alloc(u32, n_chars);
        try b.build(runs);

        var p: Paragraph = .{ .alloc = alloc, .opts = opts, .glyphs = &.{}, .metrics = &.{}, .multi_run = runs.len > 1 };
        // strut + ellipsis
        const strut_style: ?TextStyle = opts.strut orelse if (runs.len > 0) runs[0].style else null;
        if (strut_style) |st| {
            var buf: [max_faces]FaceId = undefined;
            const faces = fonts.match(st.families, st.weight, st.italic, &buf);
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
    };

    /// Greedy line breaker reproducing Blink's `ShapingLineBreaker` arithmetic: glyph positions
    /// are cumulative from the paragraph start (`s_cum` at `start`), each ceiled to 1/64 px, and
    /// a break fits when ceil64(position of the break) <= ceil64(position of the line start) +
    /// available width. Kerning against the glyph after a non-space break is undone (Blink
    /// reshapes the line end) and a soft-hyphen break must also fit its hyphen.
    fn nextLine(self: *const Paragraph, start: u32, s_cum: f64, m: Mode) LineInfo {
        const gs = self.glyphs;
        const n: u32 = @intCast(gs.len);
        const wrap = m.avail != null and self.wraps();
        const limit: f64 = ceil64d(s_cum) + @as(f64, if (m.avail) |a| floor64(@max(a, 0)) else 0);
        var i = start;
        var cum = s_cum;
        var cum_content = s_cum;
        var content_end = start;
        var brk: LineInfo = undefined;
        var has_brk = false;
        while (i < n) : (i += 1) {
            const g = gs[i];
            // each style run is its own inline item: its origin is snapped to 1/64 px
            if (self.multi_run and i > start and self.metrics[g.metric].run != self.metrics[gs[i - 1].metric].run)
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

    const LineIter = struct {
        p: *const Paragraph,
        mode: Mode,
        pos: u32 = 0,
        index: u32 = 0,
        cum: f64 = 0,

        fn next(it: *LineIter) ?LineInfo {
            const p = it.p;
            const n: u32 = @intCast(p.glyphs.len);
            if (it.pos >= n) return null;
            if (it.mode.clamp) {
                if (p.opts.max_lines) |ml| if (it.index >= ml) return null;
            }
            var li = p.nextLine(it.pos, it.cum, it.mode);
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
                        // keep combining marks with their base
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
        return .{
            .avail = max_width orelse self.opts.max_width,
            .emergency = self.opts.overflow_wrap != .normal,
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
    /// (typically the per-render arena) and freed with `TextLayout.deinit`.
    pub fn layout(self: *const Paragraph, alloc: std.mem.Allocator, max_width: ?f32) !TextLayout {
        const m = self.modeFor(max_width);
        const size = self.measureMode(m);
        var lines = try alloc.alloc(Line, size.line_count);
        errdefer alloc.free(lines);
        var out: std.ArrayList(PositionedGlyph) = .empty;
        errdefer out.deinit(alloc);
        try out.ensureTotalCapacity(alloc, self.glyphs.len + @as(usize, size.line_count) * (@as(usize, self.ell_count) + 1));

        const container = if (m.avail) |a| a else size.width;
        var it: LineIter = .{ .p = self, .mode = m };
        var top: f32 = 0;
        var li_index: usize = 0;
        while (it.next()) |li| : (li_index += 1) {
            const free = @max(container - li.content_w, 0);
            var x: f32 = switch (self.opts.text_align) {
                .left, .start, .justify => 0,
                .right, .end => free,
                .center => free * 0.5,
            };
            var extra: f32 = 0;
            if (self.opts.text_align == .justify and !li.last and !li.ellipsis and free > 0) {
                var spaces: u32 = 0;
                for (self.glyphs[li.start..li.end]) |g| {
                    if (g.flags & ShapedGlyph.WORD_SPACE != 0) spaces += 1;
                }
                if (spaces > 0) extra = free / @as(f32, @floatFromInt(spaces));
            }
            const line_x = x;
            const baseline = top + li.ascent;
            const g_start = out.items.len;
            var prev_run: u16 = 0xffff;
            for (self.glyphs[li.start..li.end]) |g| {
                const mt = self.metrics[g.metric];
                if (self.multi_run and mt.run != prev_run) {
                    if (prev_run != 0xffff) x = line_x + ceil64(x - line_x);
                    prev_run = mt.run;
                }
                out.appendAssumeCapacity(.{
                    .face = g.face,
                    .gid = g.gid,
                    .x = x + g.x_offset,
                    .y = baseline - g.y_offset,
                    .size = mt.size,
                    .user = mt.user,
                    .cluster = g.cluster,
                });
                x += self.advanceOf(g, x - line_x);
                if (g.flags & ShapedGlyph.WORD_SPACE != 0) x += extra;
            }
            if (li.hyphen and li.end > li.start) {
                const lg = self.glyphs[li.end - 1];
                const mt = self.metrics[lg.metric];
                out.appendAssumeCapacity(.{ .face = mt.face, .gid = mt.hyphen_gid, .x = x - lg.kern, .y = baseline, .size = mt.size, .user = mt.user, .cluster = lg.cluster });
                x += mt.hyphen_adv - lg.kern;
            }
            if (li.ellipsis) {
                const cluster: u32 = if (li.end < self.glyphs.len) self.glyphs[li.end].cluster else if (li.end > 0) self.glyphs[li.end - 1].cluster else 0;
                var k: u8 = 0;
                while (k < self.ell_count) : (k += 1) {
                    out.appendAssumeCapacity(.{ .face = self.ell_face, .gid = self.ell_gid, .x = x, .y = baseline, .size = self.ell_size, .user = self.ell_user, .cluster = cluster });
                    x += self.ell_adv;
                }
            }
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

const Pick = struct { face: FaceId, gid: u16 };

fn pickFace(fonts: *const FontCollection, faces: []const FaceId, cp: u21) Pick {
    for (faces) |id| {
        const g = fonts.font(id).glyphIndex(cp);
        if (g != 0) return .{ .face = id, .gid = g };
    }
    return .{ .face = faces[0], .gid = 0 };
}

const Builder = struct {
    alloc: std.mem.Allocator,
    fonts: *const FontCollection,
    opts: ParagraphOptions,
    chars: []Char,
    glyphs: std.ArrayList(ShapedGlyph) = .empty,
    metrics: std.ArrayList(Metric) = .empty,
    tmp_gids: []u16 = &.{},
    tmp_idx: []u32 = &.{},
    seg_len: usize = 0,
    seg_face: FaceId = 0,
    seg_metric: u16 = 0,
    /// Index of the first char whose break flag has not been attributed to a glyph yet.
    brk_from: usize = 0,

    fn deinitTemp(b: *Builder) void {
        b.alloc.free(b.tmp_gids);
        b.alloc.free(b.tmp_idx);
    }

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

    fn build(b: *Builder, runs: []const Run) !void {
        var faces_buf: [max_faces]FaceId = undefined;
        var faces: []FaceId = &.{};
        var cur_run: u32 = 0xffff_ffff;
        var primary_metric: u16 = 0;
        var style: TextStyle = .{};
        const hang = b.opts.white_space != .pre;
        for (b.chars, 0..) |c, ci| {
            if (c.run != cur_run) {
                b.flush(style);
                cur_run = c.run;
                style = runs[c.run].style;
                faces = b.fonts.match(style.families, style.weight, style.italic, &faces_buf);
                if (faces.len > 0) primary_metric = try b.metricFor(c.run, faces[0], style);
            }
            if (faces.len == 0) continue; // no fonts registered: nothing to shape
            if (c.cp == hard_break_cp) {
                b.flush(style);
                _ = b.takeBreak(ci);
                b.glyphs.appendAssumeCapacity(.{ .face = faces[0], .gid = 0, .cluster = c.cluster, .x_advance = 0, .metric = primary_metric, .flags = ShapedGlyph.HARD_BREAK });
                continue;
            }
            if (uni.isZeroWidth(c.cp)) continue;
            if (c.cp == '\t') {
                b.flush(style);
                const pick = pickFace(b.fonts, faces, ' ');
                const f = b.fonts.font(pick.face);
                const sp = scaleAdvance(f.advanceWidth(pick.gid), @as(f64, style.size) * 65536.0 / @as(f64, @floatFromInt(f.units_per_em))) + style.letter_spacing + style.word_spacing;
                const tab_w = sp * @as(f32, @floatFromInt(b.opts.tab_size));
                var flags: u8 = ShapedGlyph.TAB | (if (hang) ShapedGlyph.SPACE else 0);
                flags |= b.takeBreak(ci);
                b.glyphs.appendAssumeCapacity(.{ .face = pick.face, .gid = pick.gid, .cluster = c.cluster, .x_advance = @max(tab_w, 0), .metric = primary_metric, .flags = flags });
                continue;
            }
            const pick = pickFace(b.fonts, faces, c.cp);
            var metric = primary_metric;
            if (pick.face != faces[0]) metric = try b.metricFor(c.run, pick.face, style);
            if (b.seg_len != 0 and (pick.face != b.seg_face or metric != b.seg_metric)) b.flush(style);
            b.seg_face = pick.face;
            b.seg_metric = metric;
            b.tmp_gids[b.seg_len] = pick.gid;
            b.tmp_idx[b.seg_len] = @intCast(ci);
            b.seg_len += 1;
        }
        b.flush(style);
    }

    /// Shapes the pending same-face segment: GSUB, advances, kerning, spacing.
    fn flush(b: *Builder, style: TextStyle) void {
        if (b.seg_len == 0) return;
        const f = b.fonts.font(b.seg_face);
        var buf: ot.GlyphBuf = .{ .gids = b.tmp_gids[0..b.seg_len], .clusters = b.tmp_idx[0..b.seg_len], .len = b.seg_len };
        b.seg_len = 0;
        const spaced = style.letter_spacing != 0;
        for (f.gsub_lookups[0..f.n_gsub], 0..) |li, k| {
            if (spaced and li & 0x8000 != 0) continue;
            ot.substLookup(f.gsub, li & 0x7fff, &f.gsub_digests[k], &buf);
        }
        const scale = @as(f64, style.size) * 65536.0 / @as(f64, @floatFromInt(f.units_per_em));
        const hang = b.opts.white_space != .pre;
        var carry_adv: i32 = 0;
        var carry_place: i32 = 0;
        var j: usize = 0;
        while (j < buf.len) : (j += 1) {
            const gid = buf.gids[j];
            const ci = buf.clusters[j];
            const c = b.chars[ci];
            var units: i32 = @as(i32, f.advanceWidth(gid)) + carry_adv;
            var kern_units: i32 = 0;
            var place: i32 = carry_place;
            carry_adv = 0;
            carry_place = 0;
            if (j + 1 < buf.len) {
                const pa = f.pairAdjust(gid, buf.gids[j + 1]);
                units += pa.adv1;
                kern_units = pa.adv1;
                place += pa.place1;
                carry_adv = pa.adv2;
                carry_place = pa.place2;
            }
            var flags: u8 = 0;
            var adv: f32 = 0;
            if (uni.isCombining(c.cp)) {
                flags |= ShapedGlyph.NO_SPLIT;
            } else {
                adv = scaleAdvance(units, scale) + style.letter_spacing;
            }
            const kern: f32 = if (kern_units != 0 and adv != 0) scaleAdvance(units, scale) - scaleAdvance(units - kern_units, scale) else 0;
            if (c.cp == ' ' or c.cp == 0xa0) {
                adv += style.word_spacing;
                flags |= ShapedGlyph.WORD_SPACE;
                if (c.cp == ' ' and hang) flags |= ShapedGlyph.SPACE;
            }
            flags |= b.takeBreak(ci);
            b.glyphs.appendAssumeCapacity(.{
                .face = b.seg_face,
                .gid = gid,
                .cluster = c.cluster,
                .x_advance = adv,
                .x_offset = if (place != 0) scaleAdvance(place, scale) else 0,
                .kern = kern,
                .metric = b.seg_metric,
                .flags = flags,
            });
        }
    }
};
