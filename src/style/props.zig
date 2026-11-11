//! Property table (camelCase name -> handler), per-property value parsers and the CSS-wide
//! keyword machinery. Every handler parses the complete value or returns InvalidStyleValue.
const std = @import("std");
const tok = @import("tokenizer.zig");
const values = @import("values.zig");
const colorm = @import("color.zig");
const gradient = @import("gradient.zig");
const c = @import("computed.zig");

const Allocator = std.mem.Allocator;
const Error = tok.Error;
const Token = tok.Token;
const Lexer = tok.Lexer;
const LP = values.LP;
const Env = values.Env;
const S = c.ComputedStyle;
const ColorValue = colorm.ColorValue;

pub const Prop = enum(u8) {
    WebkitBoxOrient,
    WebkitLineClamp,
    WebkitTextStroke,
    WebkitTextStrokeColor,
    WebkitTextStrokeWidth,
    alignContent,
    alignItems,
    alignSelf,
    aspectRatio,
    background,
    backgroundClip,
    backgroundColor,
    backgroundImage,
    backgroundOrigin,
    backgroundPosition,
    backgroundRepeat,
    backgroundSize,
    border,
    borderBottom,
    borderBottomColor,
    borderBottomLeftRadius,
    borderBottomRightRadius,
    borderBottomStyle,
    borderBottomWidth,
    borderColor,
    borderLeft,
    borderLeftColor,
    borderLeftStyle,
    borderLeftWidth,
    borderRadius,
    borderRight,
    borderRightColor,
    borderRightStyle,
    borderRightWidth,
    borderStyle,
    borderTop,
    borderTopColor,
    borderTopLeftRadius,
    borderTopRightRadius,
    borderTopStyle,
    borderTopWidth,
    borderWidth,
    bottom,
    boxShadow,
    boxSizing,
    color,
    columnGap,
    direction,
    display,
    filter,
    flex,
    flexBasis,
    flexDirection,
    flexFlow,
    flexGrow,
    flexShrink,
    flexWrap,
    font,
    fontFamily,
    fontSize,
    fontStyle,
    fontWeight,
    gap,
    gridArea,
    gridAutoColumns,
    gridAutoFlow,
    gridAutoRows,
    gridColumn,
    gridColumnEnd,
    gridColumnStart,
    gridRow,
    gridRowEnd,
    gridRowStart,
    gridTemplateColumns,
    gridTemplateRows,
    height,
    imageRendering,
    inset,
    justifyContent,
    justifyItems,
    justifySelf,
    left,
    letterSpacing,
    lineClamp,
    lineHeight,
    margin,
    marginBottom,
    marginLeft,
    marginRight,
    marginTop,
    maxHeight,
    maxWidth,
    minHeight,
    minWidth,
    mixBlendMode,
    objectFit,
    objectPosition,
    opacity,
    order,
    outline,
    outlineColor,
    outlineOffset,
    outlineStyle,
    outlineWidth,
    overflow,
    overflowWrap,
    overflowX,
    overflowY,
    padding,
    paddingBottom,
    paddingLeft,
    paddingRight,
    paddingTop,
    placeContent,
    placeItems,
    placeSelf,
    position,
    right,
    rotate,
    rowGap,
    scale,
    tabSize,
    textAlign,
    textDecoration,
    textDecorationColor,
    textDecorationLine,
    textDecorationStyle,
    textDecorationThickness,
    textIndent,
    textOverflow,
    textShadow,
    textTransform,
    textWrap,
    textWrapMode,
    textWrapStyle,
    top,
    transform,
    transformOrigin,
    translate,
    visibility,
    whiteSpace,
    whiteSpaceCollapse,
    width,
    wordBreak,
    wordSpacing,
    wordWrap,
    zIndex,
};

const tag_names = @typeInfo(Prop).@"enum".field_names;
const n_props = tag_names.len;
/// All property names in one string (no separators) + start offsets: compact binary-search table.
const prop_pack: []const u8 = blk: {
    var out: []const u8 = "";
    for (tag_names) |n| out = out ++ n;
    break :blk out;
};
const prop_off: [n_props + 1]u16 = blk: {
    var o: [n_props + 1]u16 = undefined;
    var k: usize = 0;
    for (tag_names, 0..) |n, i| {
        o[i] = k;
        k += n.len;
    }
    o[n_props] = k;
    break :blk o;
};

comptime {
    // The enum is declared in byte order so lookup can binary-search the tag names directly.
    @setEvalBranchQuota(100000);
    for (1..n_props) |i| {
        if (std.mem.order(u8, tag_names[i - 1], tag_names[i]) != .lt) @compileError("Prop enum not sorted: " ++ tag_names[i]);
    }
}

/// camelCase property name -> Prop (case-sensitive, like takumi).
pub fn lookup(name: []const u8) ?Prop {
    var lo: usize = 0;
    var hi: usize = n_props;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        switch (std.mem.order(u8, prop_pack[prop_off[mid]..prop_off[mid + 1]], name)) {
            .eq => return @enumFromInt(mid),
            .lt => lo = mid + 1,
            .gt => hi = mid,
        }
    }
    return null;
}

// ------------------------------------------------------------------ longhand metadata
const FieldRef = struct { name: []const u8, idx: i8 = -1 };

fn fr(comptime n: []const u8) FieldRef {
    return .{ .name = n };
}
fn fi(comptime n: []const u8, comptime i: i8) FieldRef {
    return .{ .name = n, .idx = i };
}

/// Fields of ComputedStyle written by each property (used for inherit/initial/unset).
fn fieldsOf(comptime p: Prop) []const FieldRef {
    return switch (p) {
        .WebkitBoxOrient => &.{}, // validated, not stored
        .WebkitLineClamp, .lineClamp => &.{fr("line_clamp")},
        .WebkitTextStroke => &.{ fr("webkit_text_stroke_width"), fr("webkit_text_stroke_color") },
        .WebkitTextStrokeColor => &.{fr("webkit_text_stroke_color")},
        .WebkitTextStrokeWidth => &.{fr("webkit_text_stroke_width")},
        .alignContent => &.{fr("align_content")},
        .alignItems => &.{fr("align_items")},
        .alignSelf => &.{fr("align_self")},
        .aspectRatio => &.{fr("aspect_ratio")},
        .background => &.{ fr("background_color"), fr("background_image"), fr("background_size"), fr("background_position"), fr("background_repeat"), fr("background_clip"), fr("background_origin") },
        .backgroundClip => &.{fr("background_clip")},
        .backgroundColor => &.{fr("background_color")},
        .backgroundImage => &.{fr("background_image")},
        .backgroundOrigin => &.{fr("background_origin")},
        .backgroundPosition => &.{fr("background_position")},
        .backgroundRepeat => &.{fr("background_repeat")},
        .backgroundSize => &.{fr("background_size")},
        .border => &.{ fr("border_width"), fr("border_style"), fr("border_color") },
        .borderTop => &.{ fi("border_width", 0), fi("border_style", 0), fi("border_color", 0) },
        .borderRight => &.{ fi("border_width", 1), fi("border_style", 1), fi("border_color", 1) },
        .borderBottom => &.{ fi("border_width", 2), fi("border_style", 2), fi("border_color", 2) },
        .borderLeft => &.{ fi("border_width", 3), fi("border_style", 3), fi("border_color", 3) },
        .borderColor => &.{fr("border_color")},
        .borderStyle => &.{fr("border_style")},
        .borderWidth => &.{fr("border_width")},
        .borderTopColor => &.{fi("border_color", 0)},
        .borderRightColor => &.{fi("border_color", 1)},
        .borderBottomColor => &.{fi("border_color", 2)},
        .borderLeftColor => &.{fi("border_color", 3)},
        .borderTopStyle => &.{fi("border_style", 0)},
        .borderRightStyle => &.{fi("border_style", 1)},
        .borderBottomStyle => &.{fi("border_style", 2)},
        .borderLeftStyle => &.{fi("border_style", 3)},
        .borderTopWidth => &.{fi("border_width", 0)},
        .borderRightWidth => &.{fi("border_width", 1)},
        .borderBottomWidth => &.{fi("border_width", 2)},
        .borderLeftWidth => &.{fi("border_width", 3)},
        .borderRadius => &.{fr("border_radius")},
        .borderTopLeftRadius => &.{fi("border_radius", 0)},
        .borderTopRightRadius => &.{fi("border_radius", 1)},
        .borderBottomRightRadius => &.{fi("border_radius", 2)},
        .borderBottomLeftRadius => &.{fi("border_radius", 3)},
        .top => &.{fi("inset", 0)},
        .right => &.{fi("inset", 1)},
        .bottom => &.{fi("inset", 2)},
        .left => &.{fi("inset", 3)},
        .inset => &.{fr("inset")},
        .boxShadow => &.{fr("box_shadow")},
        .boxSizing => &.{fr("box_sizing")},
        .color => &.{fr("color")},
        .columnGap => &.{fr("column_gap")},
        .rowGap => &.{fr("row_gap")},
        .gap => &.{ fr("row_gap"), fr("column_gap") },
        .direction => &.{fr("direction")},
        .display => &.{fr("display")},
        .filter => &.{fr("filter")},
        .flex => &.{ fr("flex_grow"), fr("flex_shrink"), fr("flex_basis") },
        .flexBasis => &.{fr("flex_basis")},
        .flexDirection => &.{fr("flex_direction")},
        .flexFlow => &.{ fr("flex_direction"), fr("flex_wrap") },
        .flexGrow => &.{fr("flex_grow")},
        .flexShrink => &.{fr("flex_shrink")},
        .flexWrap => &.{fr("flex_wrap")},
        .font => &.{ fr("font_style"), fr("font_weight"), fr("font_size"), fr("line_height"), fr("font_family") },
        .fontFamily => &.{fr("font_family")},
        .fontSize => &.{fr("font_size")},
        .fontStyle => &.{fr("font_style")},
        .fontWeight => &.{fr("font_weight")},
        .gridArea => &.{ fr("grid_row_start"), fr("grid_column_start"), fr("grid_row_end"), fr("grid_column_end") },
        .gridAutoColumns => &.{fr("grid_auto_columns")},
        .gridAutoRows => &.{fr("grid_auto_rows")},
        .gridAutoFlow => &.{fr("grid_auto_flow")},
        .gridColumn => &.{ fr("grid_column_start"), fr("grid_column_end") },
        .gridColumnEnd => &.{fr("grid_column_end")},
        .gridColumnStart => &.{fr("grid_column_start")},
        .gridRow => &.{ fr("grid_row_start"), fr("grid_row_end") },
        .gridRowEnd => &.{fr("grid_row_end")},
        .gridRowStart => &.{fr("grid_row_start")},
        .gridTemplateColumns => &.{fr("grid_template_columns")},
        .gridTemplateRows => &.{fr("grid_template_rows")},
        .width => &.{fr("width")},
        .height => &.{fr("height")},
        .minWidth => &.{fr("min_width")},
        .minHeight => &.{fr("min_height")},
        .maxWidth => &.{fr("max_width")},
        .maxHeight => &.{fr("max_height")},
        .imageRendering => &.{fr("image_rendering")},
        .justifyContent => &.{fr("justify_content")},
        .justifyItems => &.{fr("justify_items")},
        .justifySelf => &.{fr("justify_self")},
        .letterSpacing => &.{fr("letter_spacing")},
        .lineHeight => &.{fr("line_height")},
        .margin => &.{fr("margin")},
        .marginTop => &.{fi("margin", 0)},
        .marginRight => &.{fi("margin", 1)},
        .marginBottom => &.{fi("margin", 2)},
        .marginLeft => &.{fi("margin", 3)},
        .padding => &.{fr("padding")},
        .paddingTop => &.{fi("padding", 0)},
        .paddingRight => &.{fi("padding", 1)},
        .paddingBottom => &.{fi("padding", 2)},
        .paddingLeft => &.{fi("padding", 3)},
        .mixBlendMode => &.{fr("mix_blend_mode")},
        .objectFit => &.{fr("object_fit")},
        .objectPosition => &.{fr("object_position")},
        .opacity => &.{fr("opacity")},
        .order => &.{fr("order")},
        .outline => &.{ fr("outline_width"), fr("outline_style"), fr("outline_color") },
        .outlineColor => &.{fr("outline_color")},
        .outlineOffset => &.{fr("outline_offset")},
        .outlineStyle => &.{fr("outline_style")},
        .outlineWidth => &.{fr("outline_width")},
        .overflow => &.{ fr("overflow_x"), fr("overflow_y") },
        .overflowX => &.{fr("overflow_x")},
        .overflowY => &.{fr("overflow_y")},
        .overflowWrap, .wordWrap => &.{fr("overflow_wrap")},
        .placeContent => &.{ fr("align_content"), fr("justify_content") },
        .placeItems => &.{ fr("align_items"), fr("justify_items") },
        .placeSelf => &.{ fr("align_self"), fr("justify_self") },
        .position => &.{fr("position")},
        .rotate => &.{fr("rotate")},
        .scale => &.{fr("scale")},
        .translate => &.{fr("translate")},
        .tabSize => &.{fr("tab_size")},
        .textAlign => &.{fr("text_align")},
        .textDecoration => &.{ fr("text_decoration_line"), fr("text_decoration_style"), fr("text_decoration_color"), fr("text_decoration_thickness") },
        .textDecorationColor => &.{fr("text_decoration_color")},
        .textDecorationLine => &.{fr("text_decoration_line")},
        .textDecorationStyle => &.{fr("text_decoration_style")},
        .textDecorationThickness => &.{fr("text_decoration_thickness")},
        .textIndent => &.{fr("text_indent")},
        .textOverflow => &.{ fr("text_overflow"), fr("text_overflow_string") },
        .textShadow => &.{fr("text_shadow")},
        .textTransform => &.{fr("text_transform")},
        .textWrap => &.{ fr("text_wrap_mode"), fr("text_wrap_style") },
        .textWrapMode => &.{fr("text_wrap_mode")},
        .textWrapStyle => &.{fr("text_wrap_style")},
        .transform => &.{fr("transform")},
        .transformOrigin => &.{fr("transform_origin")},
        .visibility => &.{fr("visibility")},
        .whiteSpace => &.{ fr("white_space_collapse"), fr("text_wrap_mode") },
        .whiteSpaceCollapse => &.{fr("white_space_collapse")},
        .wordBreak => &.{fr("word_break")},
        .wordSpacing => &.{fr("word_spacing")},
        .zIndex => &.{fr("z_index")},
    };
}

pub fn isInherited(p: Prop) bool {
    return switch (p) {
        .WebkitTextStroke, .WebkitTextStrokeColor, .WebkitTextStrokeWidth, .color, .direction, .font, .fontFamily, .fontSize, .fontStyle, .fontWeight, .imageRendering, .letterSpacing, .lineHeight, .overflowWrap, .wordWrap, .tabSize, .textAlign, .textIndent, .textShadow, .textTransform, .textWrap, .textWrapMode, .textWrapStyle, .visibility, .whiteSpace, .whiteSpaceCollapse, .wordBreak, .wordSpacing => true,
        else => false,
    };
}

/// Byte range of a ComputedStyle field (or array element) — CSS-wide keywords copy these ranges.
const Range = struct { off: u16, len: u16 };

fn rangeOf(comptime f: FieldRef) Range {
    const off = @offsetOf(S, f.name);
    const T = @FieldType(S, f.name);
    if (f.idx < 0) return .{ .off = off, .len = @sizeOf(T) };
    const E = @typeInfo(T).array.child;
    return .{ .off = off + @as(usize, @intCast(f.idx)) * @sizeOf(E), .len = @sizeOf(E) };
}

const n_ranges = blk: {
    @setEvalBranchQuota(200000);
    var total: usize = 0;
    for (0..n_props) |i| total += fieldsOf(@enumFromInt(i)).len;
    break :blk total;
};
const range_list: [n_ranges]Range = blk: {
    @setEvalBranchQuota(200000);
    var ranges: [n_ranges]Range = undefined;
    var k: usize = 0;
    for (0..n_props) |i| {
        for (fieldsOf(@enumFromInt(i))) |f| {
            ranges[k] = rangeOf(f);
            k += 1;
        }
    }
    break :blk ranges;
};
const range_starts: [n_props + 1]u16 = blk: {
    @setEvalBranchQuota(200000);
    var starts: [n_props + 1]u16 = undefined;
    var k: usize = 0;
    for (0..n_props) |i| {
        starts[i] = k;
        k += fieldsOf(@enumFromInt(i)).len;
    }
    starts[n_props] = k;
    break :blk starts;
};

/// Copies every field `p` writes from `src` into `dst`.
pub fn copyProp(p: Prop, dst: *S, src: *const S) void {
    const i = @intFromEnum(p);
    const db = std.mem.asBytes(dst);
    const sb = std.mem.asBytes(src);
    for (range_list[range_starts[i]..range_starts[i + 1]]) |r| {
        @memcpy(db[r.off..][0..r.len], sb[r.off..][0..r.len]);
    }
}

/// Copies all inherited properties from parent.
pub fn inheritAll(dst: *S, parent: *const S) void {
    for (0..n_props) |i| {
        const p: Prop = @enumFromInt(i);
        if (isInherited(p)) copyProp(p, dst, parent);
    }
}

// ------------------------------------------------------------------ parsing context
pub const Cx = struct {
    a: Allocator,
    s: *S,
    /// em base for lengths (this element's font size once known)
    env: Env,
    parent_fs: f32,
    parent_weight: u16,
    parent_color: colorm.Color,
};

const bad = error.InvalidStyleValue;

fn need(comptime T: type, v: ?T) Error!T {
    return v orelse bad;
}

fn ieq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn kwNext(comptime E: type, l: *Lexer) Error!E {
    return tok.kw(E, l.next()) orelse bad;
}

fn isEnd(t: Token) bool {
    return t.kind == .eof or t.kind == .comma;
}

fn lp(cx: *Cx, t: Token) Error!LP {
    return need(LP, values.lengthPct(t, &cx.env));
}

fn len(cx: *Cx, t: Token) Error!f32 {
    return need(f32, values.length(t, &cx.env));
}

fn colorOf(t: Token) Error!ColorValue {
    return need(ColorValue, colorm.fromToken(t));
}

/// `thin | medium | thick | <length>` (>= 0).
fn lineWidth(cx: *Cx, t: Token) Error!?f32 {
    if (t.kind == .ident) {
        const d = cx.env.dpr;
        if (ieq(t.text, "thin")) return 1 * d;
        if (ieq(t.text, "medium")) return 3 * d;
        if (ieq(t.text, "thick")) return 5 * d;
        return null;
    }
    const v = (values.length(t, &cx.env)) orelse return null;
    if (v < 0) return bad;
    return v;
}

/// Expands 1-4 values into [top, right, bottom, left].
fn expand4(comptime T: type, v: []const T) Error![4]T {
    return switch (v.len) {
        1 => .{ v[0], v[0], v[0], v[0] },
        2 => .{ v[0], v[1], v[0], v[1] },
        3 => .{ v[0], v[1], v[2], v[1] },
        4 => .{ v[0], v[1], v[2], v[3] },
        else => bad,
    };
}

/// Reads 1-4 value tokens (stopping at end or '/') and expands them to [top, right, bottom, left].
fn fourTokens(l: *Lexer) Error![4]Token {
    var buf: [4]Token = undefined;
    var n: usize = 0;
    while (!l.atEnd() and l.peek().kind != .slash) {
        if (n == 4) return bad;
        buf[n] = l.next();
        n += 1;
    }
    return expand4(Token, buf[0..n]);
}
// ------------------------------------------------------------------ simple property parsers
fn parseDisplay(l: *Lexer) Error!c.Display {
    const t = l.next();
    if (t.kind != .ident) return bad;
    if (tok.kw(c.Display, t)) |d| return d;
    const s = t.text;
    if (ieq(s, "list-item") or ieq(s, "-webkit-box") or ieq(s, "table") or ieq(s, "table-row-group") or ieq(s, "table-header-group") or ieq(s, "table-footer-group") or ieq(s, "table-row") or ieq(s, "table-cell") or ieq(s, "table-column-group") or ieq(s, "table-column") or ieq(s, "table-caption")) return .block;
    if (ieq(s, "inline-table") or ieq(s, "-webkit-inline-box")) return .inline_block;
    return bad;
}

const AMask = u32;
fn amask(comptime tags: []const c.Align) AMask {
    var m: AMask = 0;
    for (tags) |t| m |= @as(AMask, 1) << @as(u5, @intCast(@intFromEnum(t)));
    return m;
}
const content_mask = amask(&.{ .normal, .stretch, .start, .end, .flex_start, .flex_end, .center, .baseline, .last_baseline, .space_between, .space_around, .space_evenly, .left, .right });
const items_mask = amask(&.{ .normal, .stretch, .start, .end, .flex_start, .flex_end, .center, .baseline, .last_baseline, .self_start, .self_end, .left, .right });
const self_mask = items_mask | amask(&.{.auto});

fn parseAlign(l: *Lexer, mask: AMask) Error!c.Align {
    var t = l.next();
    if (t.isIdent("safe") or t.isIdent("unsafe")) t = l.next();
    var v: c.Align = undefined;
    if (t.isIdent("first") or t.isIdent("last")) {
        const last = t.isIdent("last");
        if (!l.next().isIdent("baseline")) return bad;
        v = if (last) .last_baseline else .baseline;
    } else if (t.isIdent("legacy")) {
        // `legacy [left|right|center]` (justify-items) -> treat as normal / the given keyword
        const n = l.peek();
        if (n.kind == .ident) {
            _ = l.next();
            v = tok.kw(c.Align, n) orelse return bad;
        } else v = .normal;
    } else {
        v = tok.kw(c.Align, t) orelse return bad;
        if (v == .last_baseline) return bad;
        if ((v == .left or v == .right or v == .center) and l.peek().isIdent("legacy")) _ = l.next();
    }
    if (mask & (@as(AMask, 1) << @as(u5, @intCast(@intFromEnum(v)))) == 0) return bad;
    return v;
}

/// A plain negative number/dimension/percentage token (not calc()).
fn isNegative(t: Token) bool {
    return (t.kind == .number or t.kind == .dimension or t.kind == .percentage) and t.num < 0;
}

fn paddingValue(cx: *Cx, t: Token) Error!LP {
    if (t.isIdent("auto")) return .{}; // takumi accepts padding:auto
    if (isNegative(t)) return bad;
    return lp(cx, t);
}

fn parseNonNegNumber(t: Token) Error!f32 {
    const v = try need(f32, values.number(t));
    return @max(v, 0);
}

fn parseFlexBasis(cx: *Cx, t: Token) Error!?c.FlexBasis {
    if (t.kind == .ident) {
        if (t.isIdent("content")) return .content;
        const sz = (values.size(t, &cx.env)) orelse return null;
        return switch (sz) {
            .auto => if (t.isIdent("auto")) .auto else null,
            .min_content => .min_content,
            .max_content => .max_content,
            .fit_content => .fit_content,
            .stretch => null,
            .lp => null,
        };
    }
    return if (values.lengthPct(t, &cx.env)) |v| .{ .lp = v } else null;
}

fn parseFlex(cx: *Cx, l: *Lexer) Error!void {
    const s = cx.s;
    const f = l.peek();
    if (f.isIdent("none")) {
        _ = l.next();
        s.flex_grow = 0;
        s.flex_shrink = 0;
        s.flex_basis = .auto;
        return;
    }
    if (f.isIdent("auto")) {
        _ = l.next();
        s.flex_grow = 1;
        s.flex_shrink = 1;
        s.flex_basis = .auto;
        return;
    }
    var grow: ?f32 = null;
    var shrink: ?f32 = null;
    var basis: ?c.FlexBasis = null;
    while (!l.atEnd()) {
        const t = l.next();
        if (grow == null and (t.kind == .number or (t.kind == .function and (values.number(t)) != null))) {
            grow = try parseNonNegNumber(t);
            const n = l.peek();
            if (n.kind == .number) {
                _ = l.next();
                shrink = try parseNonNegNumber(n);
            }
            continue;
        }
        if (basis == null) {
            if (try parseFlexBasis(cx, t)) |b| {
                basis = b;
                continue;
            }
        }
        return bad;
    }
    if (grow == null and basis == null) return bad;
    s.flex_grow = grow orelse 1;
    s.flex_shrink = shrink orelse 1;
    s.flex_basis = basis orelse .{ .lp = .{ .pct = 0 } };
}

fn parseAspect(l: *Lexer) Error!?f32 {
    var ratio: ?f32 = null;
    var saw_auto = false;
    while (!l.atEnd()) {
        const t = l.next();
        if (t.isIdent("auto") and !saw_auto) {
            saw_auto = true;
            continue;
        }
        if (ratio != null) return bad;
        const w = try parseNonNegNumber(t);
        var h: f32 = 1;
        if (l.peek().kind == .slash) {
            _ = l.next();
            h = try parseNonNegNumber(l.next());
        }
        ratio = if (w <= 0 or h <= 0) 0 else w / h;
    }
    if (ratio == null and !saw_auto) return bad;
    if (ratio) |r| if (r == 0) return null; // degenerate ratio behaves as auto
    return ratio;
}

// ------------------------------------------------------------------ grid
fn trackBreadth(cx: *Cx, t: Token) Error!?c.TrackSize {
    if (t.kind == .ident) {
        if (t.isIdent("auto")) return .auto;
        if (t.isIdent("min-content")) return .min_content;
        if (t.isIdent("max-content")) return .max_content;
        return null;
    }
    if (t.kind == .dimension and ieq(t.text, "fr")) {
        if (t.num < 0) return bad;
        return .{ .fr = t.num };
    }
    return if (values.lengthPct(t, &cx.env)) |v| .{ .lp = v } else null;
}

fn trackSize(cx: *Cx, t: Token) Error!?c.Track {
    if (t.isFunc("minmax")) {
        var l = Lexer.init(t.args);
        const mn = try need(c.TrackSize, try trackBreadth(cx, l.next()));
        if (mn == .fr) return bad;
        if (l.next().kind != .comma) return bad;
        const mx = try need(c.TrackSize, try trackBreadth(cx, l.next()));
        if (!l.atEnd()) return bad;
        return .{ .min = mn, .max = mx };
    }
    if (t.isFunc("fit-content")) {
        var l = Lexer.init(t.args);
        const v = try lp(cx, l.next());
        if (!l.atEnd()) return bad;
        return .{ .min = .auto, .max = .{ .fit_content = v } };
    }
    const b = (try trackBreadth(cx, t)) orelse return null;
    if (b == .fr) return .{ .min = .auto, .max = b };
    return .{ .min = b, .max = b };
}

const max_tracks = 10000;

fn trackList(cx: *Cx, l: *Lexer, out: *tok.List(c.Track), tmpl: ?*c.GridTemplate, nested: bool) Error!void {
    while (!l.atEnd()) {
        const t = l.next();
        if (t.kind == .bracket) continue; // line names: parsed and discarded
        if (t.isFunc("repeat")) {
            if (nested) return bad;
            var rl = Lexer.init(t.args);
            const cnt_t = rl.next();
            var mode: c.AutoRepeat = .none;
            var count: u32 = 0;
            if (cnt_t.isIdent("auto-fill")) {
                mode = .fill;
            } else if (cnt_t.isIdent("auto-fit")) {
                mode = .fit;
            } else {
                const n = try need(i32, values.integer(cnt_t));
                if (n < 1) return bad;
                count = @intCast(@min(n, max_tracks));
            }
            if (rl.next().kind != .comma) return bad;
            const start = out.items.len;
            try trackList(cx, &rl, out, null, true);
            const group = out.items.len - start;
            if (group == 0) return bad;
            if (mode != .none) {
                const tp = tmpl orelse return bad;
                if (tp.auto_repeat != .none) return bad;
                tp.auto_repeat = mode;
                tp.auto_repeat_start = @intCast(start);
                tp.auto_repeat_len = @intCast(group);
            } else {
                if (group * count > max_tracks) return bad;
                var k: u32 = 1;
                while (k < count) : (k += 1) {
                    try out.appendSlice(cx.a, out.items[start .. start + group]);
                }
            }
        } else {
            const tr = try need(c.Track, try trackSize(cx, t));
            try out.append(cx.a, tr);
        }
        if (out.items.len > max_tracks) return bad;
    }
}

fn parseTemplate(cx: *Cx, l: *Lexer) Error!c.GridTemplate {
    var g: c.GridTemplate = .{};
    if (l.peek().isIdent("none")) {
        _ = l.next();
        return g;
    }
    var out: tok.List(c.Track) = .{};
    try trackList(cx, l, &out, &g, false);
    if (out.items.len == 0) return bad;
    g.tracks = out.items;
    return g;
}

fn parseAutoTracks(cx: *Cx, l: *Lexer) Error![]const c.Track {
    var out: tok.List(c.Track) = .{};
    while (!l.atEnd()) {
        if (out.items.len >= max_tracks) return bad;
        try out.append(cx.a, try need(c.Track, try trackSize(cx, l.next())));
    }
    if (out.items.len == 0) return bad;
    return out.items;
}

fn gridLine(l: *Lexer) Error!c.GridLine {
    var t = l.next();
    if (t.isIdent("auto")) return .auto;
    var span = false;
    if (t.isIdent("span")) {
        span = true;
        t = l.next();
    }
    if (t.kind == .ident) return .auto; // named line: unsupported, treated as auto
    const n = try need(i32, values.integer(t));
    if (!span and l.peek().isIdent("span")) {
        _ = l.next();
        span = true;
    }
    if (n == 0) return .auto;
    if (span) {
        if (n < 0) return bad;
        return .{ .span = @intCast(n) };
    }
    return .{ .line = n };
}

/// `<line> [/ <line>]*` up to `max` parts; missing parts are auto.
fn gridLines(l: *Lexer, comptime max: usize) Error![max]c.GridLine {
    var out: [max]c.GridLine = @splat(.auto);
    var n: usize = 0;
    while (true) {
        if (n == max) return bad;
        out[n] = try gridLine(l);
        n += 1;
        const t = l.next();
        if (t.kind == .eof) break;
        if (t.kind != .slash) return bad;
    }
    return out;
}

// ------------------------------------------------------------------ borders / backgrounds
const BorderParts = struct { w: f32, st: c.BorderStyle, col: ColorValue };

fn borderParts(cx: *Cx, l: *Lexer, allow_auto_style: bool) Error!BorderParts {
    var w: ?f32 = null;
    var st: ?c.BorderStyle = null;
    var col: ?ColorValue = null;
    var n: usize = 0;
    while (!l.atEnd()) {
        const t = l.next();
        n += 1;
        if (w == null) {
            if (try lineWidth(cx, t)) |v| {
                w = v;
                continue;
            }
        }
        if (st == null) {
            if (tok.kw(c.BorderStyle, t)) |v| {
                st = v;
                continue;
            }
            if (allow_auto_style and t.isIdent("auto")) {
                st = .solid;
                continue;
            }
        }
        if (col == null) {
            if (colorm.fromToken(t)) |v| {
                col = v;
                continue;
            }
        }
        return bad;
    }
    if (n == 0) return bad;
    return .{ .w = w orelse 3 * cx.env.dpr, .st = st orelse .none, .col = col orelse .current };
}

fn radiusPair(cx: *Cx, l: *Lexer) Error![2]LP {
    const x = try lp(cx, l.next());
    const y = if (l.atEnd()) x else try lp(cx, l.next());
    return .{ x, y };
}

fn parseBorderRadius(cx: *Cx, l: *Lexer) Error![4][2]LP {
    const ht = try fourTokens(l);
    var vt = ht;
    if (l.peek().kind == .slash) {
        _ = l.next();
        vt = try fourTokens(l);
    }
    var out: [4][2]LP = undefined;
    for (0..4) |i| {
        out[i] = .{ try lp(cx, ht[i]), try lp(cx, vt[i]) };
    }
    return out;
}

fn bgSizeItem(cx: *Cx, l: *Lexer) Error!c.BgSize {
    const t = l.next();
    if (t.isIdent("cover")) return .cover;
    if (t.isIdent("contain")) return .contain;
    const a = try need(c.LengthAuto, values.lengthAuto(t, &cx.env));
    var b: c.LengthAuto = .auto;
    const p = l.peek();
    if (!isEnd(p)) {
        if (values.lengthAuto(p, &cx.env)) |v| {
            _ = l.next();
            b = v;
        }
    }
    return .{ .size = .{ a, b } };
}

fn repeatKw(t: Token) ?c.BgRepeat {
    return tok.kw(c.BgRepeat, t);
}

fn bgRepeatItem(l: *Lexer) Error!?[2]c.BgRepeat {
    const t = l.peek();
    if (t.isIdent("repeat-x")) {
        _ = l.next();
        return .{ .repeat, .no_repeat };
    }
    if (t.isIdent("repeat-y")) {
        _ = l.next();
        return .{ .no_repeat, .repeat };
    }
    const a = repeatKw(t) orelse return null;
    _ = l.next();
    if (repeatKw(l.peek())) |b| {
        _ = l.next();
        return .{ a, b };
    }
    return .{ a, a };
}

fn bgBox(t: Token, allow_text: bool) ?c.BgBox {
    const b = tok.kw(c.BgBox, t) orelse return null;
    if (b == .text and !allow_text) return null;
    return b;
}

const ItemKind = enum { size, position, repeat, clip, origin, image };

/// Comma-separated list of one background component.
fn bgList(comptime T: type, comptime kind: ItemKind, cx: *Cx, l: *Lexer) Error![]const T {
    var out: tok.List(T) = .{};
    while (true) {
        const item: T = switch (kind) {
            .size => try bgSizeItem(cx, l),
            .position => try need([2]LP, values.position(l, &cx.env, 4)),
            .repeat => try need([2]c.BgRepeat, try bgRepeatItem(l)),
            .clip => bgBox(l.next(), true) orelse return bad,
            .origin => bgBox(l.next(), false) orelse return bad,
            .image => try need(c.Image, try gradient.image(cx.a, l.next(), &cx.env)),
        };
        try out.append(cx.a, item);
        const sep = l.next();
        if (sep.kind == .eof) break;
        if (sep.kind != .comma) return bad;
        if (out.items.len > 1024) return bad;
    }
    return out.items;
}

fn isPosStart(t: Token, env: *const Env) bool {
    return switch (t.kind) {
        .ident => tok.kw(values.PosKw, t) != null,
        .number, .percentage => true,
        .dimension => values.lengthUnit(t.text, env) != null,
        .function => values.isMathFn(t),
        else => false,
    };
}

fn parseBackground(cx: *Cx, l: *Lexer) Error!void {
    var images: tok.List(c.Image) = .{};
    var sizes: tok.List(c.BgSize) = .{};
    var poss: tok.List([2]LP) = .{};
    var reps: tok.List([2]c.BgRepeat) = .{};
    var clips: tok.List(c.BgBox) = .{};
    var origins: tok.List(c.BgBox) = .{};
    var bg_color: ColorValue = .{ .rgba = colorm.Color.transparent };
    var color_seen = false;
    while (true) {
        var img: ?c.Image = null;
        var pos: ?[2]LP = null;
        var sz: ?c.BgSize = null;
        var rep: ?[2]c.BgRepeat = null;
        var boxes: [2]c.BgBox = undefined;
        var nbox: usize = 0;
        var attach = false;
        var col: ?ColorValue = null;
        var nitems: usize = 0;
        while (true) {
            const t = l.peek();
            if (isEnd(t)) break;
            nitems += 1;
            if (pos == null and isPosStart(t, &cx.env)) {
                pos = try need([2]LP, values.position(l, &cx.env, 4));
                if (l.peek().kind == .slash) {
                    _ = l.next();
                    sz = try bgSizeItem(cx, l);
                }
                continue;
            }
            if (rep == null) {
                if (try bgRepeatItem(l)) |r| {
                    rep = r;
                    continue;
                }
            }
            _ = l.next();
            if (img == null) {
                if (try gradient.image(cx.a, t, &cx.env)) |im| {
                    img = im;
                    continue;
                }
            }
            if (!attach and (t.isIdent("scroll") or t.isIdent("fixed") or t.isIdent("local"))) {
                attach = true;
                continue;
            }
            if (nbox < 2) {
                if (bgBox(t, true)) |b| {
                    boxes[nbox] = b;
                    nbox += 1;
                    continue;
                }
            }
            if (col == null) {
                if (colorm.fromToken(t)) |v| {
                    col = v;
                    continue;
                }
            }
            return bad;
        }
        if (nitems == 0) return bad;
        try images.append(cx.a, img orelse .none);
        try sizes.append(cx.a, sz orelse c.default_bg_size[0]);
        try poss.append(cx.a, pos orelse c.zero2);
        try reps.append(cx.a, rep orelse c.default_bg_repeat[0]);
        var origin: c.BgBox = .padding_box;
        var clip: c.BgBox = .border_box;
        if (nbox == 1) {
            if (boxes[0] == .text) clip = .text else {
                origin = boxes[0];
                clip = boxes[0];
            }
        } else if (nbox == 2) {
            if (boxes[0] == .text) return bad;
            origin = boxes[0];
            clip = boxes[1];
        }
        try origins.append(cx.a, origin);
        try clips.append(cx.a, clip);
        if (col) |v| {
            bg_color = v;
            color_seen = true;
        }
        const sep = l.next();
        if (sep.kind == .eof) break;
        if (images.items.len > 1024) return bad;
    }
    const s = cx.s;
    s.background_color = bg_color;
    s.background_image = images.items;
    s.background_size = sizes.items;
    s.background_position = poss.items;
    s.background_repeat = reps.items;
    s.background_clip = clips.items;
    s.background_origin = origins.items;
}

// ------------------------------------------------------------------ effects
fn parseShadows(cx: *Cx, l: *Lexer, box: bool) Error![]const c.Shadow {
    if (l.peek().isIdent("none")) {
        _ = l.next();
        return &.{};
    }
    var out: tok.List(c.Shadow) = .{};
    while (true) {
        try out.append(cx.a, try shadowItem(cx, l, box));
        const sep = l.next();
        if (sep.kind == .eof) break;
        if (sep.kind != .comma) return bad;
        if (out.items.len > 1024) return bad;
    }
    return out.items;
}

fn shadowItem(cx: *Cx, l: *Lexer, box: bool) Error!c.Shadow {
    var sh: c.Shadow = .{};
    var inset = false;
    var col: ?ColorValue = null;
    var nlen: usize = 0;
    const max_len: usize = if (box) 4 else 3;
    while (true) {
        const t = l.peek();
        if (isEnd(t)) break;
        _ = l.next();
        if (box and !inset and t.isIdent("inset")) {
            inset = true;
            continue;
        }
        if (nlen == 0) {
            if (values.length(t, &cx.env)) |v0| {
                var lens: [4]f32 = .{ v0, 0, 0, 0 };
                nlen = 1;
                while (nlen < max_len) {
                    const p = l.peek();
                    if (isEnd(p)) break;
                    const v = (values.length(p, &cx.env)) orelse break;
                    _ = l.next();
                    lens[nlen] = v;
                    nlen += 1;
                }
                if (nlen < 2) return bad;
                lens[2] = @max(lens[2], 0);
                sh.x = lens[0];
                sh.y = lens[1];
                sh.blur = lens[2];
                sh.spread = lens[3];
                continue;
            }
        }
        if (col == null) {
            if (colorm.fromToken(t)) |v| {
                col = v;
                continue;
            }
        }
        return bad;
    }
    if (nlen == 0) return bad;
    sh.inset = inset;
    sh.color = col orelse .current;
    return sh;
}

fn filterAmount(t: Token, default: f32, clamp1: bool) Error!f32 {
    if (t.kind == .eof) return default;
    const v = try need(f32, values.numberOrPct(t));
    if (v < 0) return bad;
    return if (clamp1) @min(v, 1) else v;
}

fn parseFilter(cx: *Cx, l: *Lexer) Error![]const c.Filter {
    if (l.peek().isIdent("none")) {
        _ = l.next();
        return &.{};
    }
    var out: tok.List(c.Filter) = .{};
    while (!l.atEnd()) {
        const t = l.next();
        if (t.kind != .function) return bad;
        var al = Lexer.init(t.args);
        const n = t.text;
        const f: c.Filter = blk: {
            if (ieq(n, "drop-shadow")) {
                const sh = try shadowItem(cx, &al, false);
                break :blk .{ .drop_shadow = sh };
            }
            const a = al.next();
            if (ieq(n, "blur")) {
                const v: f32 = if (a.kind == .eof) 0 else try len(cx, a);
                break :blk .{ .blur = @max(v, 0) };
            }
            if (ieq(n, "hue-rotate")) break :blk .{ .hue_rotate = if (a.kind == .eof) 0 else try need(f32, values.angle(a, false)) };
            if (ieq(n, "brightness")) break :blk .{ .brightness = try filterAmount(a, 1, false) };
            if (ieq(n, "contrast")) break :blk .{ .contrast = try filterAmount(a, 1, false) };
            if (ieq(n, "saturate")) break :blk .{ .saturate = try filterAmount(a, 1, false) };
            if (ieq(n, "grayscale")) break :blk .{ .grayscale = try filterAmount(a, 1, true) };
            if (ieq(n, "invert")) break :blk .{ .invert = try filterAmount(a, 1, true) };
            if (ieq(n, "opacity")) break :blk .{ .opacity = try filterAmount(a, 1, true) };
            if (ieq(n, "sepia")) break :blk .{ .sepia = try filterAmount(a, 1, true) };
            return bad;
        };
        if (!al.atEnd()) return bad;
        try out.append(cx.a, f);
        if (out.items.len > 256) return bad;
    }
    if (out.items.len == 0) return bad;
    return out.items;
}

/// Reads up to `max` comma-separated argument tokens of a function.
fn fnArgs(args: []const u8, out: []Token) Error!usize {
    var l = Lexer.init(args);
    var n: usize = 0;
    if (l.atEnd()) return 0;
    while (true) {
        if (n == out.len) return bad;
        const t = l.next();
        if (isEnd(t)) return bad;
        out[n] = t;
        n += 1;
        const sep = l.next();
        if (sep.kind == .eof) break;
        if (sep.kind != .comma) return bad;
    }
    return n;
}

fn angleArg(t: Token) Error!f32 {
    return need(f32, values.angle(t, true));
}

const transform_fns = "translate\x00translatex\x00translatey\x00scale\x00scalex\x00scaley\x00rotate\x00rotatez\x00skew\x00skewx\x00skewy\x00matrix";
/// per function: min args, max args
const transform_arity = [_][2]u8{ .{ 1, 2 }, .{ 1, 1 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 1 }, .{ 1, 1 }, .{ 1, 1 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 1 }, .{ 1, 1 }, .{ 6, 6 } };

fn parseTransform(cx: *Cx, l: *Lexer) Error![]const c.TransformOp {
    if (l.peek().isIdent("none")) {
        _ = l.next();
        return &.{};
    }
    var out: tok.List(c.TransformOp) = .{};
    while (!l.atEnd()) {
        const t = l.next();
        if (t.kind != .function) return bad;
        const fi_ = tok.matchPacked(t.text, transform_fns) orelse return bad;
        var a: [6]Token = undefined;
        const n = try fnArgs(t.args, &a);
        if (n < transform_arity[fi_][0] or n > transform_arity[fi_][1]) return bad;
        const op: c.TransformOp = switch (fi_) {
            0...2 => blk: {
                var v: [2]LP = .{ .{}, .{} };
                for (a[0..n], 0..) |x, i| v[i] = try lp(cx, x);
                if (fi_ == 2) {
                    v[1] = v[0];
                    v[0] = .{};
                }
                break :blk .{ .translate = v };
            },
            3...5 => blk: {
                var v: [2]f32 = .{ 1, 1 };
                for (a[0..n], 0..) |x, i| v[i] = values.numberOrPct(x) orelse return bad;
                if (fi_ == 3 and n == 1) v[1] = v[0];
                if (fi_ == 5) {
                    v[1] = v[0];
                    v[0] = 1;
                }
                break :blk .{ .scale = v };
            },
            6, 7 => .{ .rotate = try angleArg(a[0]) },
            8...10 => blk: {
                var v: [2]f32 = .{ 0, 0 };
                for (a[0..n], 0..) |x, i| v[i] = try angleArg(x);
                if (fi_ == 10) {
                    v[1] = v[0];
                    v[0] = 0;
                }
                break :blk .{ .skew = v };
            },
            else => blk: {
                var m: [6]f32 = undefined;
                for (0..6) |i| m[i] = values.number(a[i]) orelse return bad;
                m[4] *= cx.env.dpr;
                m[5] *= cx.env.dpr;
                break :blk .{ .matrix = m };
            },
        };
        try out.append(cx.a, op);
        if (out.items.len > 256) return bad;
    }
    if (out.items.len == 0) return bad;
    return out.items;
}

// ------------------------------------------------------------------ fonts / text
const font_size_kw = [_]struct { []const u8, f32 }{
    .{ "xx-small", 9 }, .{ "x-small", 10 }, .{ "small", 13 }, .{ "medium", 16 },
    .{ "large", 18 },   .{ "x-large", 24 }, .{ "xx-large", 32 }, .{ "xxx-large", 48 },
};

/// font-size value: lengths/% relative to the PARENT font size. Clamped to [0, 1e6] device px
/// (takumi accepts negative sizes; nested `larger` must not overflow).
fn fontSizeValue(cx: *Cx, t: Token) Error!?f32 {
    const v = (try fontSizeRaw(cx, t)) orelse return null;
    return std.math.clamp(v, 0, 1.0e6);
}

fn fontSizeRaw(cx: *Cx, t: Token) Error!?f32 {
    if (t.kind == .ident) {
        for (font_size_kw) |e| if (std.ascii.eqlIgnoreCase(t.text, e[0])) return e[1] * cx.env.dpr;
        if (t.isIdent("smaller")) return cx.parent_fs / 1.2;
        if (t.isIdent("larger")) return cx.parent_fs * 1.2;
        return null;
    }
    var env = cx.env;
    env.em = cx.parent_fs;
    const v = (values.lengthPct(t, &env)) orelse return null;
    const px = v.px + v.pct * cx.parent_fs;
    return @max(px, 0);
}

fn weightValue(cx: *Cx, t: Token) Error!?u16 {
    if (t.kind == .ident) {
        if (t.isIdent("normal")) return 400;
        if (t.isIdent("bold")) return 700;
        const p = cx.parent_weight;
        if (t.isIdent("bolder")) return if (p < 350) 400 else if (p < 550) 700 else if (p < 900) 900 else p;
        if (t.isIdent("lighter")) return if (p < 100) p else if (p < 550) 100 else if (p < 750) 400 else 700;
        return null;
    }
    const v = (values.number(t)) orelse return null;
    if (!(v >= 1 and v <= 1000)) return bad;
    return @intFromFloat(@round(v));
}

fn lineHeightValue(cx: *Cx, t: Token) Error!c.LineHeight {
    if (t.isIdent("normal")) return .normal;
    if (t.kind == .number or (t.kind == .function and !(t.isFunc("min") or t.isFunc("max") or t.isFunc("clamp")))) {
        if (values.number(t)) |v| {
            return .{ .number = @max(v, 0) };
        }
    }
    const v = try lp(cx, t);
    return .{ .px = @max(v.px + v.pct * cx.s.font_size, 0) };
}

fn spacingValue(cx: *Cx, t: Token) Error!f32 {
    if (t.isIdent("normal")) return 0;
    const v = try lp(cx, t);
    return v.px + v.pct * cx.s.font_size;
}

fn parseFamilies(cx: *Cx, l: *Lexer) Error![]const []const u8 {
    var out: tok.List([]const u8) = .{};
    while (true) {
        const t = l.next();
        if (t.kind == .string) {
            try out.append(cx.a, t.text);
        } else if (t.kind == .ident) {
            if (t.isIdent("inherit") or t.isIdent("initial") or t.isIdent("unset") or t.isIdent("default")) return bad;
            const base = @intFromPtr(l.s.ptr);
            const first_off = @intFromPtr(t.text.ptr) - base;
            var last_end = first_off + t.text.len;
            var simple = true;
            while (l.peek().kind == .ident) {
                const n = l.next();
                const off = @intFromPtr(n.text.ptr) - base;
                if (off != last_end + 1 or l.s[last_end] != ' ') simple = false;
                last_end = off + n.text.len;
            }
            const span = l.s[first_off..last_end];
            if (simple) {
                try out.append(cx.a, span);
            } else {
                // re-join with single spaces
                var buf: tok.List(u8) = .{};
                var sub = Lexer.init(span);
                while (!sub.atEnd()) {
                    const p = sub.next();
                    if (buf.items.len > 0) try buf.append(cx.a, ' ');
                    try buf.appendSlice(cx.a, p.text);
                }
                try out.append(cx.a, buf.items);
            }
        } else return bad;
        const sep = l.next();
        if (sep.kind == .eof) break;
        if (sep.kind != .comma) return bad;
        if (out.items.len > 256) return bad;
    }
    return out.items;
}

const stretch_kw = "ultra-condensed\x00extra-condensed\x00condensed\x00semi-condensed\x00semi-expanded\x00expanded\x00extra-expanded\x00ultra-expanded";

fn parseFontShorthand(cx: *Cx, l: *Lexer) Error!void {
    const s = cx.s;
    var style: ?c.FontStyle = null;
    var weight: ?u16 = null;
    var variant = false;
    var stretch = false;
    var pre: usize = 0;
    var size_t: Token = undefined;
    while (true) {
        const t = l.next();
        if (t.kind == .eof) return bad;
        if (pre < 4) {
            if (t.isIdent("normal")) {
                pre += 1;
                continue;
            }
            if (style == null) {
                if (tok.kw(c.FontStyle, t)) |st| {
                    style = st;
                    pre += 1;
                    if (st == .oblique) {
                        if (values.angle(l.peek(), false)) |_| _ = l.next();
                    }
                    continue;
                }
            }
            if (!variant and t.isIdent("small-caps")) {
                variant = true;
                pre += 1;
                continue;
            }
            if (!stretch and t.kind == .ident and tok.matchPacked(t.text, stretch_kw) != null) {
                stretch = true;
                pre += 1;
                continue;
            }
            if (weight == null and (t.kind == .number or (t.kind == .ident and !t.isIdent("smaller") and !t.isIdent("larger")))) {
                if (try weightValue(cx, t)) |w| {
                    weight = w;
                    pre += 1;
                    continue;
                }
            }
        }
        size_t = t;
        break;
    }
    const fs = try need(f32, try fontSizeValue(cx, size_t));
    var lh: c.LineHeight = .normal;
    if (l.peek().kind == .slash) {
        _ = l.next();
        // line-height ems refer to the new font size
        const saved = s.font_size;
        s.font_size = fs;
        lh = try lineHeightValue(cx, l.next());
        s.font_size = saved;
    }
    const fam = try parseFamilies(cx, l);
    s.font_style = style orelse .normal;
    s.font_weight = weight orelse 400;
    s.font_size = fs;
    s.line_height = lh;
    s.font_family = fam;
}

fn decoLine(l: *Lexer) Error!?c.DecorationLine {
    var d: c.DecorationLine = .{};
    var any = false;
    if (l.peek().isIdent("none")) {
        _ = l.next();
        return d;
    }
    while (true) {
        const t = l.peek();
        if (t.isIdent("underline")) {
            d.underline = true;
        } else if (t.isIdent("overline")) {
            d.overline = true;
        } else if (t.isIdent("line-through")) {
            d.line_through = true;
        } else if (t.isIdent("blink")) {} else break;
        _ = l.next();
        any = true;
    }
    return if (any) d else null;
}

fn decoThickness(cx: *Cx, t: Token) Error!??f32 {
    if (t.isIdent("auto") or t.isIdent("from-font")) return @as(?f32, null);
    const v = (values.lengthPct(t, &cx.env)) orelse return null;
    return @as(?f32, v.px + v.pct * cx.s.font_size);
}

fn parseTextDecoration(cx: *Cx, l: *Lexer) Error!void {
    var line: ?c.DecorationLine = null;
    var style: ?c.DecorationStyle = null;
    var col: ?ColorValue = null;
    var thick: ??f32 = null;
    var n: usize = 0;
    while (!l.atEnd()) {
        n += 1;
        if (line == null) {
            if (try decoLine(l)) |d| {
                line = d;
                continue;
            }
        }
        const t = l.next();
        if (style == null) {
            if (tok.kw(c.DecorationStyle, t)) |v| {
                style = v;
                continue;
            }
        }
        if (col == null) {
            if (colorm.fromToken(t)) |v| {
                col = v;
                continue;
            }
        }
        if (thick == null) {
            if (try decoThickness(cx, t)) |v| {
                thick = v;
                continue;
            }
        }
        return bad;
    }
    if (n == 0) return bad;
    const s = cx.s;
    s.text_decoration_line = line orelse .{};
    s.text_decoration_style = style orelse .solid;
    s.text_decoration_color = col orelse .current;
    s.text_decoration_thickness = thick orelse null;
}

fn parseWhiteSpace(cx: *Cx, l: *Lexer) Error!void {
    const s = cx.s;
    const t = l.peek();
    const Pair = struct { []const u8, c.WhiteSpaceCollapse, c.TextWrapMode };
    const tbl = [_]Pair{
        .{ "normal", .collapse, .wrap },          .{ "nowrap", .collapse, .nowrap },
        .{ "pre", .preserve, .nowrap },           .{ "pre-wrap", .preserve, .wrap },
        .{ "pre-line", .preserve_breaks, .wrap }, .{ "break-spaces", .break_spaces, .wrap },
    };
    if (t.kind == .ident) {
        for (tbl) |e| if (std.ascii.eqlIgnoreCase(t.text, e[0])) {
            _ = l.next();
            s.white_space_collapse = e[1];
            s.text_wrap_mode = e[2];
            return;
        };
    }
    var col: ?c.WhiteSpaceCollapse = null;
    var mode: ?c.TextWrapMode = null;
    while (!l.atEnd()) {
        const x = l.next();
        if (col == null) {
            if (tok.kw(c.WhiteSpaceCollapse, x)) |v| {
                col = v;
                continue;
            }
        }
        if (mode == null) {
            if (tok.kw(c.TextWrapMode, x)) |v| {
                mode = v;
                continue;
            }
        }
        return bad;
    }
    if (col == null and mode == null) return bad;
    s.white_space_collapse = col orelse .collapse;
    s.text_wrap_mode = mode orelse .wrap;
}

fn parseTextWrap(cx: *Cx, l: *Lexer) Error!void {
    var mode: ?c.TextWrapMode = null;
    var style: ?c.TextWrapStyle = null;
    while (!l.atEnd()) {
        const t = l.next();
        if (mode == null) {
            if (tok.kw(c.TextWrapMode, t)) |v| {
                mode = v;
                continue;
            }
        }
        if (style == null) {
            if (tok.kw(c.TextWrapStyle, t)) |v| {
                style = v;
                continue;
            }
        }
        return bad;
    }
    if (mode == null and style == null) return bad;
    cx.s.text_wrap_mode = mode orelse .wrap;
    cx.s.text_wrap_style = style orelse .auto;
}

fn parseStroke(cx: *Cx, l: *Lexer) Error!void {
    var w: ?f32 = null;
    var col: ?ColorValue = null;
    while (!l.atEnd()) {
        const t = l.next();
        if (w == null) {
            if (try lineWidth(cx, t)) |v| {
                w = v;
                continue;
            }
        }
        if (col == null) {
            if (colorm.fromToken(t)) |v| {
                col = v;
                continue;
            }
        }
        return bad;
    }
    if (w == null and col == null) return bad;
    cx.s.webkit_text_stroke_width = w orelse 0;
    cx.s.webkit_text_stroke_color = col orelse .current;
}

fn lineClampValue(l: *Lexer) Error!u32 {
    const t = l.next();
    if (t.isIdent("none")) return 0;
    const n = try need(i32, values.integer(t));
    return if (n < 1) 0 else @intCast(n);
}

fn parseTabSize(cx: *Cx, t: Token) Error!c.TabSize {
    if (t.kind == .number) {
        if (t.num < 0) return bad;
        return .{ .number = t.num };
    }
    const v = try len(cx, t);
    if (v < 0) return bad;
    return .{ .px = v };
}

// ------------------------------------------------------------------ single-keyword properties (table-driven)
const KwEntry = struct { names: []const u8, off: u16 };

fn ke(comptime E: type, comptime f: FieldRef) KwEntry {
    if (@sizeOf(E) != 1) @compileError("keyword field must be a u8 enum");
    return .{ .names = tok.packedNames(E), .off = rangeOf(f).off };
}

fn kwEntryOf(comptime p: Prop) ?KwEntry {
    return switch (p) {
        .position => ke(c.Position, fr("position")),
        .boxSizing => ke(c.BoxSizing, fr("box_sizing")),
        .overflowX => ke(c.Overflow, fr("overflow_x")),
        .overflowY => ke(c.Overflow, fr("overflow_y")),
        .visibility => ke(c.Visibility, fr("visibility")),
        .flexDirection => ke(c.FlexDirection, fr("flex_direction")),
        .flexWrap => ke(c.FlexWrap, fr("flex_wrap")),
        .borderTopStyle => ke(c.BorderStyle, fi("border_style", 0)),
        .borderRightStyle => ke(c.BorderStyle, fi("border_style", 1)),
        .borderBottomStyle => ke(c.BorderStyle, fi("border_style", 2)),
        .borderLeftStyle => ke(c.BorderStyle, fi("border_style", 3)),
        .objectFit => ke(c.ObjectFit, fr("object_fit")),
        .mixBlendMode => ke(c.BlendMode, fr("mix_blend_mode")),
        .textTransform => ke(c.TextTransform, fr("text_transform")),
        .textDecorationStyle => ke(c.DecorationStyle, fr("text_decoration_style")),
        .whiteSpaceCollapse => ke(c.WhiteSpaceCollapse, fr("white_space_collapse")),
        .textWrapMode => ke(c.TextWrapMode, fr("text_wrap_mode")),
        .textWrapStyle => ke(c.TextWrapStyle, fr("text_wrap_style")),
        .wordBreak => ke(c.WordBreak, fr("word_break")),
        .overflowWrap, .wordWrap => ke(c.OverflowWrap, fr("overflow_wrap")),
        .direction => ke(c.Direction, fr("direction")),
        else => null,
    };
}

const kw_count = blk: {
    var n: usize = 0;
    for (0..n_props) |i| {
        if (kwEntryOf(@enumFromInt(i)) != null) n += 1;
    }
    break :blk n;
};
const kw_entries: [kw_count]KwEntry = blk: {
    @setEvalBranchQuota(100000);
    var o: [kw_count]KwEntry = undefined;
    var n: usize = 0;
    for (0..n_props) |i| {
        if (kwEntryOf(@enumFromInt(i))) |e| {
            o[n] = e;
            n += 1;
        }
    }
    break :blk o;
};
/// Prop -> index into kw_entries (0xff = not a single-keyword property).
const kw_index: [n_props]u8 = blk: {
    @setEvalBranchQuota(100000);
    var o: [n_props]u8 = undefined;
    var n: usize = 0;
    for (0..n_props) |i| {
        if (kwEntryOf(@enumFromInt(i)) != null) {
            o[i] = n;
            n += 1;
        } else o[i] = 0xff;
    }
    break :blk o;
};

// ------------------------------------------------------------------ dispatch
fn sideIndex(p: Prop) usize {
    return switch (p) {
        .top, .marginTop, .paddingTop, .borderTop, .borderTopColor, .borderTopStyle, .borderTopWidth, .borderTopLeftRadius => 0,
        .right, .marginRight, .paddingRight, .borderRight, .borderRightColor, .borderRightStyle, .borderRightWidth, .borderTopRightRadius => 1,
        .bottom, .marginBottom, .paddingBottom, .borderBottom, .borderBottomColor, .borderBottomStyle, .borderBottomWidth, .borderBottomRightRadius => 2,
        else => 3,
    };
}

/// Parses `l` as the value of `p` and stores it into `cx.s`. The whole input must be consumed.
pub fn apply(cx: *Cx, p: Prop, l: *Lexer) Error!void {
    const s = cx.s;
    const env = &cx.env;
    const ki = kw_index[@intFromEnum(p)];
    if (ki < kw_count) {
        const e = kw_entries[ki];
        const t = l.next();
        if (t.kind != .ident) return bad;
        const v = tok.matchPacked(t.text, e.names) orelse return bad;
        std.mem.asBytes(s)[e.off] = @intCast(v);
    } else switch (p) {
        .display => s.display = try parseDisplay(l),
        .top, .right, .bottom, .left => s.inset[sideIndex(p)] = try need(c.LengthAuto, values.lengthAuto(l.next(), env)),
        .inset, .margin => {
            const ts = try fourTokens(l);
            const dst = if (p == .inset) &s.inset else &s.margin;
            for (ts, 0..) |t, i| dst[i] = values.lengthAuto(t, env) orelse return bad;
        },
        .zIndex => {
            const t = l.next();
            s.z_index = if (t.isIdent("auto")) null else try need(i32, values.integer(t));
        },
        .width, .height, .minWidth, .minHeight, .maxWidth, .maxHeight => {
            const t = l.next();
            const v = try need(c.Size, values.size(t, env));
            if (isNegative(t)) return bad;
            if (t.isIdent("none") and p != .maxWidth and p != .maxHeight) return bad;
            switch (p) {
                .width => s.width = v,
                .height => s.height = v,
                .minWidth => s.min_width = v,
                .minHeight => s.min_height = v,
                .maxWidth => s.max_width = v,
                else => s.max_height = v,
            }
        },
        .aspectRatio => s.aspect_ratio = try parseAspect(l),
        .overflow => {
            const x = try kwNext(c.Overflow, l);
            s.overflow_x = x;
            s.overflow_y = if (l.atEnd()) x else try kwNext(c.Overflow, l);
        },
        .marginTop, .marginRight, .marginBottom, .marginLeft => s.margin[sideIndex(p)] = try need(c.LengthAuto, values.lengthAuto(l.next(), env)),
        .padding => for (try fourTokens(l), 0..) |t, i| {
            s.padding[i] = try paddingValue(cx, t);
        },
        .paddingTop, .paddingRight, .paddingBottom, .paddingLeft => s.padding[sideIndex(p)] = try paddingValue(cx, l.next()),
        .gap, .rowGap, .columnGap => {
            const a = l.next();
            const r: LP = if (a.isIdent("normal")) .{} else try lp(cx, a);
            var col = r;
            if (p == .gap and !l.atEnd()) {
                const b = l.next();
                col = if (b.isIdent("normal")) .{} else try lp(cx, b);
            }
            switch (p) {
                .gap => {
                    s.row_gap = r;
                    s.column_gap = col;
                },
                .rowGap => s.row_gap = r,
                else => s.column_gap = r,
            }
        },
        .flex => try parseFlex(cx, l),
        .flexGrow => s.flex_grow = try parseNonNegNumber(l.next()),
        .flexShrink => s.flex_shrink = try parseNonNegNumber(l.next()),
        .flexBasis => s.flex_basis = try need(c.FlexBasis, try parseFlexBasis(cx, l.next())),
        .flexFlow => {
            var d: ?c.FlexDirection = null;
            var w: ?c.FlexWrap = null;
            while (!l.atEnd()) {
                const t = l.next();
                if (d == null) if (tok.kw(c.FlexDirection, t)) |v| {
                    d = v;
                    continue;
                };
                if (w == null) if (tok.kw(c.FlexWrap, t)) |v| {
                    w = v;
                    continue;
                };
                return bad;
            }
            if (d == null and w == null) return bad;
            s.flex_direction = d orelse .row;
            s.flex_wrap = w orelse .nowrap;
        },
        .justifyContent => s.justify_content = try parseAlign(l, content_mask),
        .alignContent => s.align_content = try parseAlign(l, content_mask),
        .alignItems => s.align_items = try parseAlign(l, items_mask),
        .justifyItems => s.justify_items = try parseAlign(l, items_mask),
        .alignSelf => s.align_self = try parseAlign(l, self_mask),
        .justifySelf => s.justify_self = try parseAlign(l, self_mask),
        .placeContent => {
            s.align_content = try parseAlign(l, content_mask);
            s.justify_content = if (l.atEnd()) s.align_content else try parseAlign(l, content_mask);
            if (l.atEnd() and (s.justify_content == .baseline or s.justify_content == .last_baseline)) s.justify_content = .start;
        },
        .placeItems => {
            s.align_items = try parseAlign(l, items_mask);
            s.justify_items = if (l.atEnd()) s.align_items else try parseAlign(l, items_mask);
        },
        .placeSelf => {
            s.align_self = try parseAlign(l, self_mask);
            s.justify_self = if (l.atEnd()) s.align_self else try parseAlign(l, self_mask);
        },
        .order => s.order = try need(i32, values.integer(l.next())),
        .gridTemplateColumns => s.grid_template_columns = try parseTemplate(cx, l),
        .gridTemplateRows => s.grid_template_rows = try parseTemplate(cx, l),
        .gridAutoColumns => s.grid_auto_columns = try parseAutoTracks(cx, l),
        .gridAutoRows => s.grid_auto_rows = try parseAutoTracks(cx, l),
        .gridAutoFlow => {
            var f: c.GridAutoFlow = .{};
            var dir = false;
            var n: usize = 0;
            while (!l.atEnd()) {
                const t = l.next();
                n += 1;
                if (!dir and (t.isIdent("row") or t.isIdent("column"))) {
                    dir = true;
                    f.column = t.isIdent("column");
                } else if (!f.dense and t.isIdent("dense")) {
                    f.dense = true;
                } else return bad;
            }
            if (n == 0) return bad;
            s.grid_auto_flow = f;
        },
        .gridColumnStart => s.grid_column_start = (try gridLines(l, 1))[0],
        .gridColumnEnd => s.grid_column_end = (try gridLines(l, 1))[0],
        .gridRowStart => s.grid_row_start = (try gridLines(l, 1))[0],
        .gridRowEnd => s.grid_row_end = (try gridLines(l, 1))[0],
        .gridColumn => {
            const v = try gridLines(l, 2);
            s.grid_column_start = v[0];
            s.grid_column_end = v[1];
        },
        .gridRow => {
            const v = try gridLines(l, 2);
            s.grid_row_start = v[0];
            s.grid_row_end = v[1];
        },
        .gridArea => {
            const v = try gridLines(l, 4);
            s.grid_row_start = v[0];
            s.grid_column_start = v[1];
            s.grid_row_end = v[2];
            s.grid_column_end = v[3];
        },
        .border => {
            const b = try borderParts(cx, l, false);
            s.border_width = @splat(b.w);
            s.border_style = @splat(b.st);
            s.border_color = @splat(b.col);
        },
        .borderTop, .borderRight, .borderBottom, .borderLeft => {
            const b = try borderParts(cx, l, false);
            const i = sideIndex(p);
            s.border_width[i] = b.w;
            s.border_style[i] = b.st;
            s.border_color[i] = b.col;
        },
        .borderWidth => for (try fourTokens(l), 0..) |t, i| {
            s.border_width[i] = try need(f32, try lineWidth(cx, t));
        },
        .borderStyle => for (try fourTokens(l), 0..) |t, i| {
            s.border_style[i] = tok.kw(c.BorderStyle, t) orelse return bad;
        },
        .borderColor => for (try fourTokens(l), 0..) |t, i| {
            s.border_color[i] = try colorOf(t);
        },
        .borderTopWidth, .borderRightWidth, .borderBottomWidth, .borderLeftWidth => s.border_width[sideIndex(p)] = try need(f32, try lineWidth(cx, l.next())),
        .borderTopColor, .borderRightColor, .borderBottomColor, .borderLeftColor => s.border_color[sideIndex(p)] = try colorOf(l.next()),
        .borderRadius => s.border_radius = try parseBorderRadius(cx, l),
        .borderTopLeftRadius, .borderTopRightRadius, .borderBottomRightRadius, .borderBottomLeftRadius => s.border_radius[sideIndex(p)] = try radiusPair(cx, l),
        .outline => {
            const b = try borderParts(cx, l, true);
            s.outline_width = b.w;
            s.outline_style = b.st;
            s.outline_color = b.col;
        },
        .outlineWidth => s.outline_width = try need(f32, try lineWidth(cx, l.next())),
        .outlineStyle => {
            const t = l.next();
            s.outline_style = if (t.isIdent("auto")) .solid else tok.kw(c.BorderStyle, t) orelse return bad;
        },
        .outlineColor => {
            const t = l.next();
            s.outline_color = if (t.isIdent("auto")) .current else try colorOf(t);
        },
        .outlineOffset => s.outline_offset = try len(cx, l.next()),
        .backgroundColor => s.background_color = try colorOf(l.next()),
        .backgroundImage => s.background_image = try bgList(c.Image, .image, cx, l),
        .backgroundSize => s.background_size = try bgList(c.BgSize, .size, cx, l),
        .backgroundPosition => s.background_position = try bgList([2]LP, .position, cx, l),
        .backgroundRepeat => s.background_repeat = try bgList([2]c.BgRepeat, .repeat, cx, l),
        .backgroundClip => s.background_clip = try bgList(c.BgBox, .clip, cx, l),
        .backgroundOrigin => s.background_origin = try bgList(c.BgBox, .origin, cx, l),
        .background => try parseBackground(cx, l),
        .boxShadow => s.box_shadow = try parseShadows(cx, l, true),
        .textShadow => s.text_shadow = try parseShadows(cx, l, false),
        .opacity => s.opacity = std.math.clamp(try need(f32, values.numberOrPct(l.next())), 0, 1),
        .filter => s.filter = try parseFilter(cx, l),
        .transform => s.transform = try parseTransform(cx, l),
        .translate => {
            const t = l.next();
            if (t.isIdent("none")) {
                s.translate = c.zero2;
            } else {
                const x = try lp(cx, t);
                var y: LP = .{};
                if (!l.atEnd()) y = try lp(cx, l.next());
                s.translate = .{ x, y };
            }
        },
        .rotate => {
            const t = l.next();
            if (t.isIdent("none")) {
                s.rotate = 0;
            } else if (t.isIdent("z")) {
                s.rotate = try angleArg(l.next());
            } else {
                s.rotate = try angleArg(t);
                if (l.peek().isIdent("z")) _ = l.next();
            }
        },
        .scale => {
            const t = l.next();
            if (t.isIdent("none")) {
                s.scale = .{ 1, 1 };
            } else {
                const x = try need(f32, values.numberOrPct(t));
                var y = x;
                if (!l.atEnd()) {
                    y = try need(f32, values.numberOrPct(l.next()));
                    if (!l.atEnd()) _ = try need(f32, values.numberOrPct(l.next()));
                }
                s.scale = .{ x, y };
            }
        },
        .transformOrigin => {
            s.transform_origin = try need([2]LP, values.position(l, env, 2));
            if (!l.atEnd()) _ = try len(cx, l.next()); // z offset ignored
        },
        .objectPosition => s.object_position = try need([2]LP, values.position(l, env, 4)),
        .imageRendering => {
            const t = l.next();
            s.image_rendering = if (t.isIdent("high-quality") or t.isIdent("optimizeQuality"))
                .smooth
            else if (t.isIdent("optimizeSpeed") or t.isIdent("-webkit-optimize-contrast"))
                .pixelated
            else
                tok.kw(c.ImageRendering, t) orelse return bad;
        },
        .color => {
            const v = try colorOf(l.next());
            s.color = v.resolve(cx.parent_color);
        },
        .fontFamily => s.font_family = try parseFamilies(cx, l),
        .fontSize => s.font_size = try need(f32, try fontSizeValue(cx, l.next())),
        .fontWeight => s.font_weight = try need(u16, try weightValue(cx, l.next())),
        .fontStyle => {
            s.font_style = try kwNext(c.FontStyle, l);
            if (s.font_style == .oblique and !l.atEnd()) _ = try angleArg(l.next());
        },
        .font => try parseFontShorthand(cx, l),
        .lineHeight => s.line_height = try lineHeightValue(cx, l.next()),
        .letterSpacing => s.letter_spacing = try spacingValue(cx, l.next()),
        .wordSpacing => s.word_spacing = try spacingValue(cx, l.next()),
        .textAlign => {
            const t = l.next();
            s.text_align = if (t.isIdent("match-parent") or t.isIdent("-webkit-auto")) .start else tok.kw(c.TextAlign, t) orelse return bad;
        },
        .textIndent => {
            s.text_indent = try lp(cx, l.next());
            while (!l.atEnd()) {
                const t = l.next();
                if (!t.isIdent("hanging") and !t.isIdent("each-line")) return bad;
            }
        },
        .tabSize => s.tab_size = try parseTabSize(cx, l.next()),
        .textDecoration => try parseTextDecoration(cx, l),
        .textDecorationLine => s.text_decoration_line = try need(c.DecorationLine, try decoLine(l)),
        .textDecorationColor => s.text_decoration_color = try colorOf(l.next()),
        .textDecorationThickness => s.text_decoration_thickness = try need(?f32, try decoThickness(cx, l.next())),
        .whiteSpace => try parseWhiteSpace(cx, l),
        .textWrap => try parseTextWrap(cx, l),
        .lineClamp, .WebkitLineClamp => s.line_clamp = try lineClampValue(l),
        .WebkitTextStroke => try parseStroke(cx, l),
        .WebkitTextStrokeWidth => s.webkit_text_stroke_width = try need(f32, try lineWidth(cx, l.next())),
        .WebkitTextStrokeColor => s.webkit_text_stroke_color = try colorOf(l.next()),
        .WebkitBoxOrient => _ = tok.matchPacked(l.next().text, "horizontal\x00vertical\x00inline-axis\x00block-axis") orelse return bad,
        .textOverflow => {
            const t = l.next();
            if (t.kind == .string) {
                s.text_overflow = .string;
                s.text_overflow_string = t.text;
            } else {
                s.text_overflow = tok.kw(c.TextOverflow, t) orelse return bad;
                if (s.text_overflow == .string) return bad;
                s.text_overflow_string = "";
            }
        },
        else => return bad, // single-keyword properties are handled above
    }
    if (!l.atEnd()) return bad;
}
