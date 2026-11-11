//! Computed-style value types and `ComputedStyle` (one per node). All lengths are DEVICE px.
const std = @import("std");
const values = @import("values.zig");
const colorm = @import("color.zig");
const gradient = @import("gradient.zig");

pub const LP = values.LP;
pub const Size = values.Size;
pub const LengthAuto = values.LengthAuto;
pub const Color = colorm.Color;
pub const ColorValue = colorm.ColorValue;
pub const Image = gradient.Image;
pub const Gradient = gradient.Gradient;

pub const Display = enum(u8) { @"inline", block, inline_block, flex, inline_flex, grid, inline_grid, none, contents, flow_root };
pub const Position = enum(u8) { static, relative, absolute, fixed, sticky };
pub const BoxSizing = enum(u8) { border_box, content_box };
pub const Overflow = enum(u8) { visible, hidden, clip, scroll, auto };
pub const Visibility = enum(u8) { visible, hidden, collapse };
pub const FlexDirection = enum(u8) { row, row_reverse, column, column_reverse };
pub const FlexWrap = enum(u8) { nowrap, wrap, wrap_reverse };
/// Box-alignment keyword (justify-*/align-*). `normal` and `auto` are kept distinct.
/// `first baseline` = baseline; `safe`/`unsafe` prefixes are accepted and dropped.
pub const Align = enum(u8) { normal, stretch, start, end, flex_start, flex_end, center, baseline, space_between, space_around, space_evenly, auto, left, right, self_start, self_end, last_baseline };
pub const FlexBasis = union(enum) { auto, content, lp: LP, min_content, max_content, fit_content };

/// One side of a grid track's sizing function.
pub const TrackSize = union(enum) { auto, lp: LP, fr: f32, min_content, max_content, fit_content: LP };
/// `minmax(min, max)`; a plain size `s` is `{s, s}`, `<flex>` is `{auto, fr}`, `fit-content(x)` is `{auto, fit_content(x)}`.
pub const Track = struct { min: TrackSize, max: TrackSize };
pub const AutoRepeat = enum(u8) { none, fill, fit };
/// `grid-template-columns/rows`. `tracks` is the flattened list with integer `repeat()` expanded.
/// When `auto_repeat != .none`, tracks[auto_repeat_start .. auto_repeat_start+auto_repeat_len] is the
/// `repeat(auto-fill|auto-fit, ...)` group (to be repeated by the layout engine). Line names are discarded.
pub const GridTemplate = struct {
    tracks: []const Track = &.{},
    auto_repeat: AutoRepeat = .none,
    auto_repeat_start: u16 = 0,
    auto_repeat_len: u16 = 0,
};
pub const GridAutoFlow = packed struct(u8) { column: bool = false, dense: bool = false, _pad: u6 = 0 };
/// grid-row/column-start/end. Named lines are not supported (InvalidStyleValue).
pub const GridLine = union(enum) { auto, line: i32, span: u32 };

pub const BorderStyle = enum(u8) { none, hidden, solid, dashed, dotted, double, groove, ridge, inset, outset };
pub const BgRepeat = enum(u8) { repeat, no_repeat, space, round };
pub const BgBox = enum(u8) { border_box, padding_box, content_box, text };
pub const BgSize = union(enum) { cover, contain, size: [2]LengthAuto };
pub const ObjectFit = enum(u8) { fill, contain, cover, none, scale_down };
pub const ImageRendering = enum(u8) { auto, smooth, pixelated, crisp_edges };
pub const BlendMode = enum(u8) { normal, multiply, screen, overlay, darken, lighten, color_dodge, color_burn, hard_light, soft_light, difference, exclusion, hue, saturation, color, luminosity, plus_lighter, plus_darker };

/// box-shadow / text-shadow / drop-shadow entry. Lengths in device px.
pub const Shadow = struct {
    x: f32 = 0,
    y: f32 = 0,
    blur: f32 = 0,
    spread: f32 = 0,
    color: ColorValue = .current,
    inset: bool = false,
};

/// `filter` functions. Amounts are plain factors (50% -> 0.5); blur in device px; hue_rotate in degrees.
pub const Filter = union(enum) {
    blur: f32,
    brightness: f32,
    contrast: f32,
    grayscale: f32,
    invert: f32,
    opacity: f32,
    saturate: f32,
    sepia: f32,
    hue_rotate: f32,
    drop_shadow: Shadow,
};

/// 2D transform functions in source order. Angles in DEGREES; translate % refers to the element's own
/// border box; matrix = (a b c d e f) with e/f in device px.
pub const TransformOp = union(enum) {
    translate: [2]LP,
    scale: [2]f32,
    rotate: f32,
    skew: [2]f32,
    matrix: [6]f32,
};

pub const FontStyle = enum(u8) { normal, italic, oblique };
pub const LineHeight = union(enum) { normal, number: f32, px: f32 };
pub const TextAlign = enum(u8) { start, end, left, right, center, justify };
pub const TextTransform = enum(u8) { none, uppercase, lowercase, capitalize };
pub const DecorationLine = packed struct(u8) { underline: bool = false, overline: bool = false, line_through: bool = false, _pad: u5 = 0 };
pub const DecorationStyle = enum(u8) { solid, double, dotted, dashed, wavy };
pub const WhiteSpaceCollapse = enum(u8) { collapse, preserve, preserve_breaks, preserve_spaces, break_spaces };
pub const TextWrapMode = enum(u8) { wrap, nowrap };
pub const TextWrapStyle = enum(u8) { auto, balance, pretty, stable };
pub const WordBreak = enum(u8) { normal, break_all, keep_all, break_word };
pub const OverflowWrap = enum(u8) { normal, break_word, anywhere };
/// `.string` = a custom marker in `text_overflow_string` (raw, escapes not processed).
pub const TextOverflow = enum(u8) { clip, ellipsis, string };
pub const Direction = enum(u8) { ltr, rtl };
pub const TabSize = union(enum) { number: f32, px: f32 };

pub const center2: [2]LP = .{ .{ .pct = 0.5 }, .{ .pct = 0.5 } };
pub const zero2: [2]LP = .{ .{}, .{} };
const auto2: [2]LengthAuto = .{ .auto, .auto };

pub const default_bg_size = [_]BgSize{.{ .size = auto2 }};
pub const default_bg_position = [_][2]LP{zero2};
pub const default_bg_repeat = [_][2]BgRepeat{.{ .repeat, .repeat }};
pub const default_bg_clip = [_]BgBox{.border_box};
pub const default_bg_origin = [_]BgBox{.padding_box};

/// Side order everywhere: top, right, bottom, left. Corner order: top-left, top-right, bottom-right, bottom-left.
pub const ComputedStyle = struct {
    // ---- box / layout (not inherited)
    display: Display = .@"inline",
    position: Position = .static,
    box_sizing: BoxSizing = .border_box,
    overflow_x: Overflow = .visible,
    overflow_y: Overflow = .visible,
    flex_direction: FlexDirection = .row,
    flex_wrap: FlexWrap = .nowrap,
    justify_content: Align = .normal,
    align_items: Align = .normal,
    align_self: Align = .auto,
    align_content: Align = .normal,
    justify_items: Align = .normal,
    justify_self: Align = .auto,
    grid_auto_flow: GridAutoFlow = .{},
    /// null = auto
    z_index: ?i32 = null,
    order: i32 = 0,
    inset: [4]LengthAuto = .{ .auto, .auto, .auto, .auto },
    width: Size = .auto,
    height: Size = .auto,
    min_width: Size = .auto,
    min_height: Size = .auto,
    /// `none` = .auto
    max_width: Size = .auto,
    max_height: Size = .auto,
    /// width / height; null = auto
    aspect_ratio: ?f32 = null,
    margin: [4]LengthAuto = .{ .{ .lp = .{} }, .{ .lp = .{} }, .{ .lp = .{} }, .{ .lp = .{} } },
    padding: [4]LP = .{ .{}, .{}, .{}, .{} },
    row_gap: LP = .{},
    column_gap: LP = .{},
    flex_grow: f32 = 0,
    flex_shrink: f32 = 1,
    flex_basis: FlexBasis = .auto,
    grid_template_columns: GridTemplate = .{},
    grid_template_rows: GridTemplate = .{},
    /// empty = a single `auto` track
    grid_auto_columns: []const Track = &.{},
    grid_auto_rows: []const Track = &.{},
    grid_row_start: GridLine = .auto,
    grid_row_end: GridLine = .auto,
    grid_column_start: GridLine = .auto,
    grid_column_end: GridLine = .auto,

    // ---- box decoration (not inherited)
    /// SPECIFIED widths (device px). Use `usedBorderWidths()` for painting/layout.
    border_width: [4]f32 = .{ 3, 3, 3, 3 },
    border_style: [4]BorderStyle = .{ .none, .none, .none, .none },
    border_color: [4]ColorValue = .{ .current, .current, .current, .current },
    /// [corner][x, y]
    border_radius: [4][2]LP = .{ zero2, zero2, zero2, zero2 },
    outline_width: f32 = 3,
    outline_style: BorderStyle = .none,
    outline_color: ColorValue = .current,
    outline_offset: f32 = 0,
    background_color: ColorValue = .{ .rgba = Color.transparent },
    /// One entry per layer (empty = no image layers). Other background lists repeat cyclically
    /// against this one (CSS list repetition); use `bgLayer(i)`.
    background_image: []const Image = &.{},
    background_size: []const BgSize = &default_bg_size,
    background_position: []const [2]LP = &default_bg_position,
    /// [x, y]
    background_repeat: []const [2]BgRepeat = &default_bg_repeat,
    background_clip: []const BgBox = &default_bg_clip,
    background_origin: []const BgBox = &default_bg_origin,
    box_shadow: []const Shadow = &.{},
    opacity: f32 = 1,
    filter: []const Filter = &.{},
    transform: []const TransformOp = &.{},
    /// individual transform properties (identity when unset); rotate in degrees
    translate: [2]LP = zero2,
    rotate: f32 = 0,
    scale: [2]f32 = .{ 1, 1 },
    transform_origin: [2]LP = center2,
    object_fit: ObjectFit = .fill,
    object_position: [2]LP = center2,
    mix_blend_mode: BlendMode = .normal,
    visibility: Visibility = .visible, // inherited

    // ---- text (inherited unless noted)
    color: Color = Color.black,
    font_family: []const []const u8 = &.{},
    font_size: f32 = 16,
    font_weight: u16 = 400,
    font_style: FontStyle = .normal,
    line_height: LineHeight = .normal,
    letter_spacing: f32 = 0,
    word_spacing: f32 = 0,
    text_align: TextAlign = .start,
    text_transform: TextTransform = .none,
    /// percentage refers to the containing block width
    text_indent: LP = .{},
    tab_size: TabSize = .{ .number = 8 },
    white_space_collapse: WhiteSpaceCollapse = .collapse,
    text_wrap_mode: TextWrapMode = .wrap,
    text_wrap_style: TextWrapStyle = .auto,
    word_break: WordBreak = .normal,
    overflow_wrap: OverflowWrap = .normal,
    direction: Direction = .ltr,
    image_rendering: ImageRendering = .auto,
    text_shadow: []const Shadow = &.{},
    webkit_text_stroke_width: f32 = 0,
    webkit_text_stroke_color: ColorValue = .current,
    // not inherited text props
    text_decoration_line: DecorationLine = .{},
    text_decoration_style: DecorationStyle = .solid,
    text_decoration_color: ColorValue = .current,
    /// null = auto / from-font
    text_decoration_thickness: ?f32 = null,
    text_overflow: TextOverflow = .clip,
    text_overflow_string: []const u8 = "",
    /// 0 = none
    line_clamp: u32 = 0,

    /// Used border widths (Blink rule): 0 when the side's style is none/hidden, otherwise the
    /// specified width floored to whole device px, but never below 1 when non-zero.
    pub fn usedBorderWidths(s: *const ComputedStyle) [4]f32 {
        var out: [4]f32 = undefined;
        for (0..4) |i| out[i] = usedLineWidth(s.border_width[i], s.border_style[i]);
        return out;
    }

    pub fn usedOutlineWidth(s: *const ComputedStyle) f32 {
        return usedLineWidth(s.outline_width, s.outline_style);
    }

    /// The i-th background layer with CSS list repetition applied (i < background_image.len).
    pub fn bgLayer(s: *const ComputedStyle, i: usize) BgLayer {
        return .{
            .image = s.background_image[i],
            .size = pick(BgSize, s.background_size, i, default_bg_size[0]),
            .position = pick([2]LP, s.background_position, i, zero2),
            .repeat = pick([2]BgRepeat, s.background_repeat, i, default_bg_repeat[0]),
            .clip = pick(BgBox, s.background_clip, i, .border_box),
            .origin = pick(BgBox, s.background_origin, i, .padding_box),
        };
    }

    /// The background painting area of the bottom-most layer (`background-clip` of the last layer),
    /// which is what clips `background-color`.
    pub fn bgColorClip(s: *const ComputedStyle) BgBox {
        const n = @max(s.background_image.len, 1);
        return pick(BgBox, s.background_clip, n - 1, .border_box);
    }

    /// Resolves a ColorValue against this element's `color`.
    pub fn resolveColor(s: *const ComputedStyle, c: ColorValue) Color {
        return c.resolve(s.color);
    }
};

pub const BgLayer = struct {
    image: Image,
    size: BgSize,
    position: [2]LP,
    repeat: [2]BgRepeat,
    clip: BgBox,
    origin: BgBox,
};

fn pick(comptime E: type, list: []const E, i: usize, def: E) E {
    if (list.len == 0) return def;
    return list[i % list.len];
}

pub fn usedLineWidth(w: f32, st: BorderStyle) f32 {
    if (st == .none or st == .hidden) return 0;
    if (!(w > 0)) return 0;
    const f = @floor(w);
    return if (f < 1) 1 else f;
}

/// takumi initial values (Blink initial + takumi's display:inline / box-sizing:border-box).
pub fn initialStyle(dpr: f32) ComputedStyle {
    var s: ComputedStyle = .{};
    s.font_size = 16 * dpr;
    s.border_width = .{ 3 * dpr, 3 * dpr, 3 * dpr, 3 * dpr };
    s.outline_width = 3 * dpr;
    return s;
}
