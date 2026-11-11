//! Style inputs for the layout engine. Plain data; the integrator maps parsed CSS onto `Style`.
//! Defaults follow what takumi containers need most often (flex, border-box), NOT the CSS initial values.

/// `calc()` reduced to a length plus a percentage: px + percent * basis.
pub const Calc = struct {
    px: f32 = 0,
    /// 0..1 fraction
    percent: f32 = 0,
};

/// Size-like value: `auto`, pixels, or a fraction (0..1) of the containing dimension.
pub const Dim = union(enum) {
    auto,
    px: f32,
    /// 0..1 fraction (50% == 0.5)
    percent: f32,
    /// px + percent * basis; behaves as auto where a percentage would (indefinite basis)
    calc: Calc,
    /// Intrinsic sizing keywords. Only meaningful for `size` (width/height) and `flex_basis`; as a height,
    /// min/max size, margin or inset they behave as `auto`.
    min_content,
    max_content,
    fit_content,

    /// true when the value depends on the containing size
    pub fn hasPercent(d: Dim) bool {
        return d == .percent or (d == .calc and d.calc.percent != 0);
    }
    pub fn isKeyword(d: Dim) bool {
        return d == .min_content or d == .max_content or d == .fit_content;
    }
};

/// Length or percentage (fraction 0..1). Used for padding and gap.
pub const LengthPercentage = union(enum) {
    px: f32,
    percent: f32,
    /// px + percent * basis (the percentage part is 0 against an indefinite basis)
    calc: Calc,

    pub fn hasPercent(d: LengthPercentage) bool {
        return d == .percent or (d == .calc and d.calc.percent != 0);
    }
};

pub fn Edges(comptime T: type) type {
    return struct {
        top: T,
        right: T,
        bottom: T,
        left: T,

        pub fn all(v: T) @This() {
            return .{ .top = v, .right = v, .bottom = v, .left = v };
        }
    };
}

pub const Display = enum(u8) { flex, block, grid, none };
/// `static` only matters for absolutely positioned descendants: a static box is not their containing block.
pub const Position = enum(u8) { relative, absolute, static };
pub const BoxSizing = enum(u8) { border_box, content_box };
pub const Overflow = enum(u8) { visible, hidden, scroll, clip };
pub const FlexDirection = enum(u8) { row, column, row_reverse, column_reverse };
pub const FlexWrap = enum(u8) { nowrap, wrap, wrap_reverse };

/// One enum for every alignment property. `null` in `Style` means `normal`/`auto`.
/// Values that are invalid for a given property fall back to `start`
/// (e.g. `space_between` for align-items) or `flex_start` (`stretch` for flex justify-content).
pub const Align = enum(u8) {
    start,
    end,
    flex_start,
    flex_end,
    center,
    stretch,
    baseline,
    space_between,
    space_around,
    space_evenly,
};

/// One side of a grid track sizing function.
pub const TrackBreadth = union(enum) {
    px: f32,
    /// 0..1 fraction of the grid container's content box
    percent: f32,
    /// flex factor; only meaningful as `max`
    fr: f32,
    auto,
    min_content,
    max_content,
    /// fit-content(limit); only meaningful as `max` (with `min = .auto`)
    fit_content: LengthPercentage,
};

/// Grid track sizing function `minmax(min, max)`.
/// `repeat(n, ...)` must be pre-expanded by the caller; see `AutoRepeat` for auto-fill/auto-fit.
pub const Track = struct {
    min: TrackBreadth = .auto,
    max: TrackBreadth = .auto,

    pub const auto: Track = .{};
    pub const min_content: Track = .{ .min = .min_content, .max = .min_content };
    pub const max_content: Track = .{ .min = .max_content, .max = .max_content };
    pub fn px(v: f32) Track {
        return .{ .min = .{ .px = v }, .max = .{ .px = v } };
    }
    pub fn percent(v: f32) Track {
        return .{ .min = .{ .percent = v }, .max = .{ .percent = v } };
    }
    /// `<flex>` == minmax(auto, <flex>)
    pub fn fr(v: f32) Track {
        return .{ .min = .auto, .max = .{ .fr = v } };
    }
    pub fn minmax(mn: TrackBreadth, mx: TrackBreadth) Track {
        return .{ .min = mn, .max = mx };
    }
    pub fn fitContent(limit: LengthPercentage) Track {
        return .{ .min = .auto, .max = .{ .fit_content = limit } };
    }
};

/// `repeat(auto-fill | auto-fit, <tracks>)` inside a track template.
pub const AutoRepeat = struct {
    /// true = auto-fit (empty repeated tracks collapse), false = auto-fill
    fit: bool = false,
    /// the repeated track list (caller-owned)
    tracks: []const Track,
    /// index in the explicit template (grid_template_columns/rows) before which the repetition is inserted
    at: u16 = 0,
};

pub const Line = union(enum) {
    auto,
    /// 1-based grid line; negative counts from the end of the explicit grid; 0 is treated as auto
    line: i16,
    span: u16,
};

pub const Placement = struct {
    start: Line = .auto,
    end: Line = .auto,
};

pub const GridAutoFlow = enum(u8) { row, column, row_dense, column_dense };

pub const Style = struct {
    display: Display = .flex,
    position: Position = .relative,
    box_sizing: BoxSizing = .border_box,
    /// Only affects the automatic minimum size (min-width:auto -> 0 when not visible) and
    /// block margin collapsing (hidden/scroll establish a formatting context).
    overflow_x: Overflow = .visible,
    overflow_y: Overflow = .visible,

    inset: Edges(Dim) = .all(.auto),
    /// [width, height]
    size: [2]Dim = .{ .auto, .auto },
    min_size: [2]Dim = .{ .auto, .auto },
    max_size: [2]Dim = .{ .auto, .auto },
    /// width / height
    aspect_ratio: ?f32 = null,

    margin: Edges(Dim) = .all(.{ .px = 0 }),
    padding: Edges(LengthPercentage) = .all(.{ .px = 0 }),
    border: Edges(f32) = .all(0),
    /// [column-gap (between columns, along x), row-gap (between rows, along y)]
    gap: [2]LengthPercentage = .{ .{ .px = 0 }, .{ .px = 0 } },

    flex_direction: FlexDirection = .row,
    flex_wrap: FlexWrap = .nowrap,
    flex_grow: f32 = 0,
    flex_shrink: f32 = 1,
    flex_basis: Dim = .auto,

    align_items: ?Align = null,
    align_self: ?Align = null,
    align_content: ?Align = null,
    justify_content: ?Align = null,
    justify_items: ?Align = null,
    justify_self: ?Align = null,

    // grid container (slices are caller-owned and must outlive `compute`)
    grid_template_columns: []const Track = &.{},
    grid_template_rows: []const Track = &.{},
    grid_auto_columns: []const Track = &.{},
    grid_auto_rows: []const Track = &.{},
    grid_auto_repeat_columns: ?AutoRepeat = null,
    grid_auto_repeat_rows: ?AutoRepeat = null,
    grid_auto_flow: GridAutoFlow = .row,
    // grid item
    grid_column: Placement = .{},
    grid_row: Placement = .{},
};

pub const AvailableSpace = union(enum) {
    definite: f32,
    min_content,
    max_content,
};
