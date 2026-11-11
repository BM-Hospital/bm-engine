//! CSS style-value parsing -> per-node `ComputedStyle`.
//!
//! There is no selector engine: a node's style comes from its `preset` object (lowest priority),
//! then its `style` object (camelCase keys, string or number values), plus inheritance from the parent.
//!
//! Error policy (mirrors takumi): unknown / kebab-case / `--custom` keys are ignored, `null` means "no
//! declaration", and a known property with an invalid value fails with `error.InvalidStyleValue`
//! (`Diagnostics` names the property and value). `inherit`, `initial`, `unset`, `revert`,
//! `revert-layer` work for every property; a trailing `!important` is accepted and ignored;
//! values containing `var(` are rejected.
//!
//! Memory: `compute` allocates lists (font families, shadows, gradients, tracks, ...) in `arena`,
//! which must outlive the returned style; strings may alias the JSON input.
const std = @import("std");
const json = @import("testjson.zig"); // referenced from tests only (see compute())
pub const tokenizer = @import("tokenizer.zig");
pub const color = @import("color.zig");
pub const values = @import("values.zig");
pub const gradient = @import("gradient.zig");
pub const computed = @import("computed.zig");
pub const props = @import("props.zig");

pub const Color = color.Color;
pub const ColorValue = color.ColorValue;
pub const LP = values.LP;
pub const Size = values.Size;
pub const LengthAuto = values.LengthAuto;
pub const Gradient = gradient.Gradient;
pub const GradientStop = gradient.Stop;
pub const ResolvedStop = gradient.ResolvedStop;
pub const Image = gradient.Image;
pub const resolveStops = gradient.resolveStops;
pub const ComputedStyle = computed.ComputedStyle;
pub const BgLayer = computed.BgLayer;
pub const Shadow = computed.Shadow;
pub const Filter = computed.Filter;
pub const TransformOp = computed.TransformOp;
pub const Track = computed.Track;
pub const TrackSize = computed.TrackSize;
pub const GridTemplate = computed.GridTemplate;
pub const GridLine = computed.GridLine;
pub const Display = computed.Display;
pub const Align = computed.Align;
pub const usedLineWidth = computed.usedLineWidth;

pub const Error = error{ InvalidStyleValue, OutOfMemory };

pub const Context = struct {
    /// devicePixelRatio: multiplies absolute lengths (px, pt, ...) and font sizes. Outputs are DEVICE px.
    dpr: f32 = 1,
    /// Output pixels; vw/vh resolve against these directly (not divided by dpr). Missing dimension = 0.
    viewport_w: f32,
    viewport_h: f32,
    /// Root element font-size in device px (16*dpr until the root computes its own); `rem` base.
    root_font_size: f32,
};

/// Filled on error.InvalidStyleValue. `value` is "" for JSON-number values.
pub const Diagnostics = struct { property: []const u8 = "", value: []const u8 = "" };

fn sanitizedDpr(ctx: *const Context) f32 {
    return if (ctx.dpr > 0 and ctx.dpr < 1.0e6) ctx.dpr else 1;
}

/// takumi initial values (display = inline, box-sizing = border-box, font-size 16*dpr, ...).
pub fn initial(ctx: *const Context) ComputedStyle {
    return computed.initialStyle(sanitizedDpr(ctx));
}

const Mode = enum { font_only, all };

/// A declaration value: the subset of `json.Value` (src/json.zig) that style cares about.
pub const RawValue = union(enum) { null, number: f64, string: []const u8, other };

/// Computes a node's style: start from `initial`, copy inherited properties from `parent` (if any),
/// apply `preset` then `style` declarations in object order (later wins; shorthands expand in place).
/// Font-size-setting declarations (`fontSize`, `font`) are evaluated first so `em` in every other
/// property uses this element's final font-size (as CSS computed values do).
///
/// `preset` / `style` are `?json.Value` (src/json.zig). They are taken as `anytype` only so that this
/// directory can be unit-tested standalone (importing ../json.zig is outside the module path when
/// src/style is the test root); any union with `.null`, `.number: f64`, `.string`, `.object: []{key, value}`
/// works, and passing `null` is fine. A non-object, non-null source -> InvalidStyleValue (property "style").
pub fn compute(
    arena: std.mem.Allocator,
    ctx: *const Context,
    parent: ?*const ComputedStyle,
    preset: anytype,
    style: anytype,
    diag: *Diagnostics,
) Error!ComputedStyle {
    const dpr = sanitizedDpr(ctx);
    const init_s = computed.initialStyle(dpr);
    var s = init_s;
    if (parent) |p| props.inheritAll(&s, p);
    const pfs = if (parent) |p| p.font_size else init_s.font_size;
    var cx: props.Cx = .{
        .a = arena,
        .s = &s,
        .env = .{
            .dpr = dpr,
            .vw = if (ctx.viewport_w > 0) ctx.viewport_w else 0,
            .vh = if (ctx.viewport_h > 0) ctx.viewport_h else 0,
            .em = pfs,
            .rem = if (ctx.root_font_size > 0) ctx.root_font_size else 16 * dpr,
        },
        .parent_fs = pfs,
        .parent_weight = if (parent) |p| p.font_weight else 400,
        .parent_color = if (parent) |p| p.color else Color.black,
    };
    const st: State = .{ .init = &init_s, .parent = parent, .diag = diag };
    try applySource(&cx, &st, preset, .font_only);
    try applySource(&cx, &st, style, .font_only);
    cx.env.em = s.font_size;
    try applySource(&cx, &st, preset, .all);
    try applySource(&cx, &st, style, .all);
    return s;
}

const State = struct { init: *const ComputedStyle, parent: ?*const ComputedStyle, diag: *Diagnostics };

fn applySource(cx: *props.Cx, st: *const State, src: anytype, mode: Mode) Error!void {
    const Src = @TypeOf(src);
    if (Src == @TypeOf(null)) return;
    const v = if (@typeInfo(Src) == .optional) (src orelse return) else src;
    switch (v) {
        .null => return,
        .object => |members| for (members) |m| {
            const raw: RawValue = switch (m.value) {
                .null => .null,
                .number => |n| .{ .number = n },
                .string => |str| .{ .string = str },
                else => .other,
            };
            try applyDecl(cx, st, m.key, raw, mode);
        },
        else => {
            st.diag.* = .{ .property = "style", .value = "" };
            return error.InvalidStyleValue;
        },
    }
}

fn applyDecl(cx: *props.Cx, st: *const State, key: []const u8, value: RawValue, mode: Mode) Error!void {
    const p = props.lookup(key) orelse return;
    if (mode == .font_only and p != .fontSize and p != .font) return;
    applyValue(cx, st, p, value) catch |e| {
        if (e == error.InvalidStyleValue) st.diag.* = .{ .property = key, .value = if (value == .string) value.string else "" };
        return e;
    };
}

const CssWide = enum { inherit, initial, unset };

fn cssWide(s: []const u8) ?CssWide {
    if (std.ascii.eqlIgnoreCase(s, "inherit")) return .inherit;
    if (std.ascii.eqlIgnoreCase(s, "initial")) return .initial;
    if (std.ascii.eqlIgnoreCase(s, "unset") or std.ascii.eqlIgnoreCase(s, "revert") or std.ascii.eqlIgnoreCase(s, "revert-layer")) return .unset;
    return null;
}

fn stripImportant(s0: []const u8) []const u8 {
    const s = std.mem.trimEnd(u8, s0, " \t\r\n");
    const bang = std.mem.lastIndexOfScalar(u8, s, '!') orelse return s;
    const rest = std.mem.trim(u8, s[bang + 1 ..], " \t\r\n");
    if (!std.ascii.eqlIgnoreCase(rest, "important")) return s;
    return std.mem.trimEnd(u8, s[0..bang], " \t\r\n");
}

fn containsVar(s: []const u8) bool {
    if (s.len < 4) return false;
    var i: usize = 0;
    while (i + 4 <= s.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(s[i .. i + 4], "var(")) return true;
    }
    return false;
}

fn applyValue(cx: *props.Cx, st: *const State, p: props.Prop, value: RawValue) Error!void {
    switch (value) {
        .null => return,
        .number => |n| {
            var l = tokenizer.Lexer.initNumber(n);
            try props.apply(cx, p, &l);
        },
        .string => |raw| {
            const s = stripImportant(std.mem.trim(u8, raw, " \t\r\n"));
            if (s.len == 0 or containsVar(s)) return error.InvalidStyleValue;
            if (cssWide(s)) |k| {
                const use_parent = switch (k) {
                    .inherit => true,
                    .initial => false,
                    .unset => props.isInherited(p),
                };
                const src: *const ComputedStyle = if (use_parent) (st.parent orelse st.init) else st.init;
                props.copyProp(p, cx.s, src);
                return;
            }
            var l = tokenizer.Lexer.init(s);
            try props.apply(cx, p, &l);
        },
        else => return error.InvalidStyleValue,
    }
}

// =============================================================================================
// tests
// =============================================================================================
const T = std.testing;

test {
    _ = tokenizer;
    _ = color;
    _ = values;
    _ = gradient;
    _ = computed;
    _ = props;
}

const TestCx = struct {
    arena: std.heap.ArenaAllocator,
    ctx: Context = .{ .dpr = 1, .viewport_w = 1200, .viewport_h = 630, .root_font_size = 16 },
    diag: Diagnostics = .{},

    fn init() TestCx {
        return .{ .arena = std.heap.ArenaAllocator.init(T.allocator) };
    }
    fn deinit(t: *TestCx) void {
        t.arena.deinit();
    }
    fn a(t: *TestCx) std.mem.Allocator {
        return t.arena.allocator();
    }
    /// Computes from a JSON style object text.
    fn style(t: *TestCx, parent: ?*const ComputedStyle, src: []const u8) !ComputedStyle {
        const v = try json.parse(t.a(), src);
        return compute(t.a(), &t.ctx, parent, null, v, &t.diag);
    }
    /// Computes `{ key: value }` with a string value.
    fn one(t: *TestCx, key: []const u8, value: []const u8) !ComputedStyle {
        const members = try t.a().alloc(json.Member, 1);
        members[0] = .{ .key = key, .value = .{ .string = value } };
        return compute(t.a(), &t.ctx, null, null, json.Value{ .object = members }, &t.diag);
    }
    fn bad(t: *TestCx, key: []const u8, value: []const u8) !void {
        if (t.one(key, value)) |_| {
            std.debug.print("expected InvalidStyleValue for {s}: '{s}'\n", .{ key, value });
            return error.TestUnexpectedResult;
        } else |e| {
            try T.expectEqual(error.InvalidStyleValue, e);
            try T.expectEqualStrings(key, t.diag.property);
        }
    }
};

fn approx(a: f32, b: f32) bool {
    return @abs(a - b) < 1e-3;
}
fn expectLP(v: LP, px: f32, pct: f32) !void {
    if (!approx(v.px, px) or !approx(v.pct, pct)) {
        std.debug.print("LP {d},{d} expected {d},{d}\n", .{ v.px, v.pct, px, pct });
        return error.TestUnexpectedResult;
    }
}

test "property table lookup" {
    try T.expectEqual(props.Prop.width, props.lookup("width").?);
    try T.expectEqual(props.Prop.WebkitLineClamp, props.lookup("WebkitLineClamp").?);
    try T.expectEqual(props.Prop.zIndex, props.lookup("zIndex").?);
    try T.expectEqual(props.Prop.WebkitLineClamp, props.lookup("WebkitLineClamp").?);
    try T.expect(props.lookup("min-width") == null);
    try T.expect(props.lookup("WebkitBoxOrient") != null);
    try T.expect(props.lookup("Width") == null);
    for (std.enums.values(props.Prop)) |p| try T.expectEqual(p, props.lookup(@tagName(p)).?);
}

test "initial values" {
    const ctx: Context = .{ .dpr = 2, .viewport_w = 100, .viewport_h = 100, .root_font_size = 32 };
    const s = initial(&ctx);
    try T.expectEqual(Display.@"inline", s.display);
    try T.expectEqual(computed.BoxSizing.border_box, s.box_sizing);
    try T.expectEqual(@as(f32, 32), s.font_size);
    try T.expectEqual(@as(f32, 6), s.border_width[0]);
    try T.expectEqual([4]f32{ 0, 0, 0, 0 }, s.usedBorderWidths());
    try T.expect(s.color.eql(Color.black));
    try T.expect(s.line_height == .normal);
    try expectLP(s.transform_origin[0], 0, 0.5);
    try T.expectEqual(computed.ObjectFit.fill, s.object_fit);
    try T.expectEqual(@as(f32, 1), s.flex_shrink);
}

test "ignored keys, null, errors, important, var" {
    var t = TestCx.init();
    defer t.deinit();
    const s = try t.style(null,
        \\{"min-width": "banana", "unknownProp": "x", "--x": "1px", "width": null, "WebkitBoxOrient": "vertical",
        \\ "height": "10px !important", "minHeight": "5px!IMPORTANT"}
    );
    try T.expect(s.width == .auto);
    try expectLP(s.height.lp, 10, 0);
    try expectLP(s.min_height.lp, 5, 0);
    try t.bad("width", "banana");
    try T.expectEqualStrings("banana", t.diag.value);
    try t.bad("width", "var(--x)");
    try t.bad("color", "calc(var(--a) * 1)");
    try t.bad("width", "");
    try t.bad("width", "10px 20px");
    try t.bad("width", "none");
    try T.expect((try t.one("maxWidth", "auto")).max_width == .auto); // takumi accepts
    try t.bad("width", "-10px");
    try t.bad("WebkitBoxOrient", "banana");
    _ = try t.one("WebkitBoxOrient", "vertical");
    // non-string/number value
    try T.expectError(error.InvalidStyleValue, t.style(null, "{\"width\": true}"));
    try T.expectError(error.InvalidStyleValue, t.style(null, "{\"width\": [1]}"));
    // last declaration wins; preset < style
    const preset = try json.parse(t.a(), "{\"width\": 5, \"height\": 7}");
    const sty = try json.parse(t.a(), "{\"width\": 1, \"width\": 2}");
    const s2 = try compute(t.a(), &t.ctx, null, preset, sty, &t.diag);
    try expectLP(s2.width.lp, 2, 0);
    try expectLP(s2.height.lp, 7, 0);
}

test "units with dpr=2" {
    var t = TestCx.init();
    defer t.deinit();
    t.ctx = .{ .dpr = 2, .viewport_w = 100, .viewport_h = 50, .root_font_size = 32 };
    const s = try t.style(null,
        \\{"width": 10, "height": "10", "minWidth": "50vw", "minHeight": "1em", "maxWidth": "2rem",
        \\ "maxHeight": "calc(100% - 1em)", "fontSize": 20, "top": "10vh", "left": "1pt"}
    );
    try T.expectEqual(@as(f32, 40), s.font_size);
    try expectLP(s.width.lp, 20, 0);
    try expectLP(s.height.lp, 20, 0);
    try expectLP(s.min_width.lp, 50, 0); // vw not scaled by dpr
    try expectLP(s.min_height.lp, 40, 0); // em = own (device) font size
    try expectLP(s.max_width.lp, 64, 0);
    try expectLP(s.max_height.lp, -40, 1);
    try expectLP(s.inset[0].lp, 5, 0);
    try expectLP(s.inset[3].lp, 8.0 / 3.0, 0);
    try T.expect(s.inset[1] == .auto);
}

test "font-size: em uses parent, keywords, relative" {
    var t = TestCx.init();
    defer t.deinit();
    t.ctx.dpr = 2;
    t.ctx.root_font_size = 32;
    const root = try t.style(null, "{\"fontSize\": \"20px\"}");
    try T.expectEqual(@as(f32, 40), root.font_size);
    const child = try t.style(&root, "{\"fontSize\": \"2em\", \"width\": \"1em\"}");
    try T.expectEqual(@as(f32, 80), child.font_size);
    try expectLP(child.width.lp, 80, 0);
    // width declared before fontSize still uses the final font size
    const c2 = try t.style(&root, "{\"width\": \"1em\", \"fontSize\": \"50%\"}");
    try T.expectEqual(@as(f32, 20), c2.font_size);
    try expectLP(c2.width.lp, 20, 0);
    const kws = [_]struct { []const u8, f32 }{
        .{ "xx-small", 18 }, .{ "x-small", 20 }, .{ "small", 26 }, .{ "medium", 32 }, .{ "large", 36 },
        .{ "x-large", 48 },  .{ "xx-large", 64 }, .{ "xxx-large", 96 }, .{ "1rem", 32 }, .{ "larger", 48 }, .{ "smaller", 40.0 / 1.2 },
    };
    for (kws) |k| {
        const members = try t.a().alloc(json.Member, 1);
        members[0] = .{ .key = "fontSize", .value = .{ .string = k[0] } };
        const s = try compute(t.a(), &t.ctx, &root, null, json.Value{ .object = members }, &t.diag);
        if (!approx(s.font_size, k[1])) {
            std.debug.print("fontSize {s} = {d}\n", .{ k[0], s.font_size });
            return error.TestUnexpectedResult;
        }
    }
    try T.expectEqual(@as(f32, 0), (try t.one("fontSize", "-1px")).font_size); // takumi accepts
    try t.bad("fontSize", "big");
}

test "inheritance" {
    var t = TestCx.init();
    defer t.deinit();
    const parent = try t.style(null,
        \\{"color": "red", "fontFamily": "Inter, 'Noto Sans', sans-serif", "fontSize": 20, "lineHeight": 1.5,
        \\ "backgroundColor": "blue", "width": 100, "fontWeight": "bold", "textAlign": "center", "letterSpacing": "0.1em",
        \\ "textDecoration": "underline", "textOverflow": "ellipsis", "lineClamp": 2, "visibility": "hidden"}
    );
    try T.expectEqual(@as(usize, 3), parent.font_family.len);
    try T.expectEqualStrings("Noto Sans", parent.font_family[1]);
    try T.expectEqualStrings("sans-serif", parent.font_family[2]);
    try T.expect(approx(parent.letter_spacing, 2));
    const child = try t.style(&parent, "{\"fontSize\": 10}");
    try T.expect(child.color.eql(.{ .r = 255, .a = 255 }));
    try T.expectEqual(@as(usize, 3), child.font_family.len);
    try T.expectEqual(@as(u16, 700), child.font_weight);
    try T.expectEqual(computed.TextAlign.center, child.text_align);
    try T.expect(child.line_height == .number and child.line_height.number == 1.5); // re-multiplied by layout with 10px
    try T.expect(approx(child.letter_spacing, 2)); // computed px inherits
    try T.expect(child.background_color == .rgba and child.background_color.rgba.a == 0);
    try T.expect(child.width == .auto);
    try T.expect(!child.text_decoration_line.underline);
    try T.expectEqual(computed.TextOverflow.clip, child.text_overflow);
    try T.expectEqual(@as(u32, 0), child.line_clamp);
    try T.expectEqual(computed.Visibility.hidden, child.visibility);
    // lineHeight length computes to px at the declaring element and inherits as px
    const p2 = try t.style(null, "{\"fontSize\": 20, \"lineHeight\": \"1.5em\"}");
    try T.expect(p2.line_height == .px and approx(p2.line_height.px, 30));
    const c2 = try t.style(&p2, "{\"fontSize\": 10}");
    try T.expect(c2.line_height == .px and approx(c2.line_height.px, 30));
    const p3 = try t.style(null, "{\"fontSize\": 20, \"lineHeight\": \"150%\"}");
    try T.expect(p3.line_height == .px and approx(p3.line_height.px, 30));
    // currentColor for `color` = parent's colour
    const c3 = try t.style(&parent, "{\"color\": \"currentColor\", \"borderColor\": \"currentcolor\"}");
    try T.expect(c3.color.eql(.{ .r = 255, .a = 255 }));
    try T.expect(c3.border_color[0] == .current);
}

test "css-wide keywords" {
    var t = TestCx.init();
    defer t.deinit();
    const parent = try t.style(null, "{\"color\": \"red\", \"width\": 50, \"padding\": 4, \"fontSize\": 30, \"border\": \"2px solid blue\"}");
    const c1 = try t.style(&parent,
        \\{"color": "inherit", "width": "inherit", "padding": "INHERIT", "border": "inherit", "fontSize": "initial"}
    );
    try T.expect(c1.color.eql(.{ .r = 255, .a = 255 }));
    try expectLP(c1.width.lp, 50, 0);
    try expectLP(c1.padding[2], 4, 0);
    try T.expectEqual(computed.BorderStyle.solid, c1.border_style[1]);
    try T.expectEqual(@as(f32, 16), c1.font_size);
    const c2 = try t.style(&parent, "{\"color\": \"blue\", \"width\": 3}");
    const c3 = try t.style(&c2, "{\"color\": \"initial\", \"width\": \"unset\", \"fontSize\": \"unset\", \"paddingTop\": \"revert\"}");
    try T.expect(c3.color.eql(Color.black));
    try T.expect(c3.width == .auto);
    try T.expectEqual(@as(f32, 30), c3.font_size);
    const c4 = try t.style(&parent, "{\"color\": \"unset\", \"borderTop\": \"inherit\"}");
    try T.expect(c4.color.eql(.{ .r = 255, .a = 255 }));
    try T.expectEqual(computed.BorderStyle.solid, c4.border_style[0]);
    try T.expectEqual(computed.BorderStyle.none, c4.border_style[1]);
    // root: inherit = initial
    const r = try t.style(null, "{\"color\": \"inherit\", \"display\": \"inherit\"}");
    try T.expect(r.color.eql(Color.black));
    try T.expectEqual(Display.@"inline", r.display);
}

test "display / position / box keywords" {
    var t = TestCx.init();
    defer t.deinit();
    const cases = [_]struct { []const u8, Display }{
        .{ "none", .none },               .{ "flex", .flex },             .{ "inline-flex", .inline_flex },
        .{ "grid", .grid },               .{ "inline-grid", .inline_grid }, .{ "block", .block },
        .{ "inline", .@"inline" },        .{ "inline-block", .inline_block }, .{ "contents", .contents },
        .{ "flow-root", .flow_root },     .{ "FLEX", .flex },             .{ "table", .block },
        .{ "list-item", .block },       .{ "-webkit-box", .block },
    };
    for (cases) |cs| try T.expectEqual(cs[1], (try t.one("display", cs[0])).display);
    try t.bad("display", "flexbox");
    try t.bad("display", "1");
    try t.bad("display", "block flex"); // takumi rejects the two-value syntax
    try T.expectEqual(computed.Position.absolute, (try t.one("position", "absolute")).position);
    try T.expectEqual(computed.Position.sticky, (try t.one("position", "sticky")).position);
    try t.bad("position", "absolut");
    try T.expectEqual(computed.BoxSizing.content_box, (try t.one("boxSizing", "content-box")).box_sizing);
    const s = try t.one("overflow", "hidden scroll");
    try T.expect(s.overflow_x == .hidden and s.overflow_y == .scroll);
    try T.expect((try t.one("overflow", "clip")).overflow_y == .clip);
    try T.expect((try t.one("overflowY", "auto")).overflow_y == .auto);
    try t.bad("overflow", "a b");
    try T.expectEqual(@as(?i32, 5), (try t.one("zIndex", "5")).z_index);
    try T.expectEqual(@as(?i32, -3), (try t.one("zIndex", "-3")).z_index);
    try T.expectEqual(@as(?i32, null), (try t.one("zIndex", "auto")).z_index);
    try t.bad("zIndex", "1.5");
    try T.expectEqual(@as(i32, -2), (try t.one("order", "-2")).order);
    try T.expectEqual(computed.Visibility.collapse, (try t.one("visibility", "collapse")).visibility);
    try T.expectEqual(@as(?f32, 16.0 / 9.0), (try t.one("aspectRatio", "16 / 9")).aspect_ratio);
    try T.expectEqual(@as(?f32, 1.5), (try t.one("aspectRatio", "1.5")).aspect_ratio);
    try T.expectEqual(@as(?f32, null), (try t.one("aspectRatio", "auto")).aspect_ratio);
    try T.expectEqual(@as(?f32, 2), (try t.one("aspectRatio", "auto 2/1")).aspect_ratio);
    try t.bad("aspectRatio", "16/");
    try T.expectEqual(@as(?f32, null), (try t.one("aspectRatio", "-1")).aspect_ratio);
    const sz = try t.style(null,
        \\{"width": "min-content", "height": "max-content", "minWidth": "fit-content", "minHeight": "stretch", "maxWidth": "none", "maxHeight": "50%"}
    );
    try T.expect(sz.width == .min_content and sz.height == .max_content and sz.min_width == .fit_content and sz.min_height == .stretch);
    try T.expect(sz.max_width == .auto);
    try expectLP(sz.max_height.lp, 0, 0.5);
}

test "margin / padding / inset / gap shorthands" {
    var t = TestCx.init();
    defer t.deinit();
    var s = try t.one("margin", "1px");
    for (s.margin) |m| try expectLP(m.lp, 1, 0);
    s = try t.one("margin", "1px auto");
    try expectLP(s.margin[0].lp, 1, 0);
    try T.expect(s.margin[1] == .auto and s.margin[3] == .auto);
    try expectLP(s.margin[2].lp, 1, 0);
    s = try t.one("margin", "1px 2px 3px");
    try expectLP(s.margin[3].lp, 2, 0);
    try expectLP(s.margin[2].lp, 3, 0);
    s = try t.one("padding", "1px 2px 3px 4%");
    try expectLP(s.padding[0], 1, 0);
    try expectLP(s.padding[1], 2, 0);
    try expectLP(s.padding[2], 3, 0);
    try expectLP(s.padding[3], 0, 0.04);
    s = try t.style(null, "{\"padding\": 10, \"paddingLeft\": 3, \"marginTop\": \"auto\", \"inset\": \"0 auto\"}");
    try expectLP(s.padding[0], 10, 0);
    try expectLP(s.padding[3], 3, 0);
    try T.expect(s.margin[0] == .auto);
    try expectLP(s.inset[0].lp, 0, 0);
    try T.expect(s.inset[1] == .auto);
    try t.bad("margin", "1px 2px 3px 4px 5px");
    try t.bad("padding", "-1px");
    try expectLP((try t.one("padding", "auto")).padding[0], 0, 0); // takumi accepts
    s = try t.one("gap", "10px 20%");
    try expectLP(s.row_gap, 10, 0);
    try expectLP(s.column_gap, 0, 0.2);
    s = try t.one("gap", "5px");
    try expectLP(s.column_gap, 5, 0);
    s = try t.one("rowGap", "normal");
    try expectLP(s.row_gap, 0, 0);
}

fn expectFlex(t: *TestCx, v: []const u8, g: f32, sh: f32, basis: computed.FlexBasis) !void {
    const s = try t.one("flex", v);
    const ok = s.flex_grow == g and s.flex_shrink == sh and std.meta.eql(s.flex_basis, basis);
    if (!ok) {
        std.debug.print("flex '{s}' -> {d} {d} {any}\n", .{ v, s.flex_grow, s.flex_shrink, s.flex_basis });
        return error.TestUnexpectedResult;
    }
}

test "flex shorthand truth table" {
    var t = TestCx.init();
    defer t.deinit();
    const zero_pct: computed.FlexBasis = .{ .lp = .{ .pct = 0 } };
    try expectFlex(&t, "1", 1, 1, zero_pct);
    try expectFlex(&t, "auto", 1, 1, .auto);
    try expectFlex(&t, "none", 0, 0, .auto);
    try expectFlex(&t, "2 3", 2, 3, zero_pct);
    try expectFlex(&t, "1 30px", 1, 1, .{ .lp = .{ .px = 30 } });
    try expectFlex(&t, "0 0 100px", 0, 0, .{ .lp = .{ .px = 100 } });
    try expectFlex(&t, "30px", 1, 1, .{ .lp = .{ .px = 30 } });
    try expectFlex(&t, "0", 0, 1, zero_pct);
    try expectFlex(&t, "1 0 0", 1, 0, .{ .lp = .{ .px = 0 } });
    try expectFlex(&t, "2 content", 2, 1, .content);
    try expectFlex(&t, "50% 2", 2, 1, .{ .lp = .{ .pct = 0.5 } });
    try expectFlex(&t, "1 1 auto", 1, 1, .auto);
    const s = try t.style(null, "{\"flex\": 1}");
    try T.expect(s.flex_grow == 1 and s.flex_shrink == 1 and std.meta.eql(s.flex_basis, zero_pct));
    const s2 = try t.one("flex", "initial");
    try T.expect(s2.flex_grow == 0 and s2.flex_shrink == 1 and s2.flex_basis == .auto);
    try expectFlex(&t, "1 2 3", 1, 2, .{ .lp = .{ .px = 3 } }); // takumi: unitless basis = px
    try expectFlex(&t, "-1", 0, 1, zero_pct); // takumi accepts negatives; clamped
    try t.bad("flex", "auto 1");
    try t.bad("flex", "10px 20px");
    const fb = try t.style(null, "{\"flexGrow\": 2, \"flexShrink\": \"0\", \"flexBasis\": \"content\", \"flexDirection\": \"column-reverse\", \"flexWrap\": \"wrap\"}");
    try T.expect(fb.flex_grow == 2 and fb.flex_shrink == 0 and fb.flex_basis == .content);
    try T.expect(fb.flex_direction == .column_reverse and fb.flex_wrap == .wrap);
    const ff = try t.one("flexFlow", "wrap-reverse column");
    try T.expect(ff.flex_direction == .column and ff.flex_wrap == .wrap_reverse);
    try T.expectEqual(@as(f32, 0), (try t.one("flexGrow", "-1")).flex_grow);
}

test "alignment" {
    var t = TestCx.init();
    defer t.deinit();
    const s = try t.style(null,
        \\{"justifyContent": "space-between", "alignItems": "center", "alignSelf": "flex-end", "alignContent": "space-evenly",
        \\ "justifyItems": "start", "justifySelf": "auto"}
    );
    try T.expect(s.justify_content == .space_between and s.align_items == .center and s.align_self == .flex_end);
    try T.expect(s.align_content == .space_evenly and s.justify_items == .start and s.justify_self == .auto);
    try T.expect((try t.one("alignItems", "normal")).align_items == .normal);
    try T.expect((try t.one("alignItems", "last baseline")).align_items == .last_baseline);
    try T.expect((try t.one("alignItems", "first baseline")).align_items == .baseline);
    try T.expect((try t.one("justifyContent", "safe center")).justify_content == .center);
    try t.bad("alignItems", "space-between");
    try t.bad("justifyContent", "auto");
    const p = try t.one("placeItems", "center end");
    try T.expect(p.align_items == .center and p.justify_items == .end);
    const p2 = try t.one("placeContent", "space-around");
    try T.expect(p2.align_content == .space_around and p2.justify_content == .space_around);
    const p3 = try t.one("placeSelf", "stretch");
    try T.expect(p3.align_self == .stretch and p3.justify_self == .stretch);
}

test "grid" {
    var t = TestCx.init();
    defer t.deinit();
    var s = try t.one("gridTemplateColumns", "[a] 100px repeat(2, 1fr [b] minmax(10px, auto)) fit-content(40%) [end]");
    const tr = s.grid_template_columns.tracks;
    try T.expectEqual(@as(usize, 6), tr.len);
    try expectLP(tr[0].min.lp, 100, 0);
    try T.expect(tr[1].min == .auto and tr[1].max == .fr and tr[1].max.fr == 1);
    try expectLP(tr[2].min.lp, 10, 0);
    try T.expect(tr[2].max == .auto);
    try T.expect(tr[3].max.fr == 1);
    try T.expect(tr[5].min == .auto and tr[5].max == .fit_content);
    try T.expect(s.grid_template_columns.auto_repeat == .none);
    s = try t.one("gridTemplateRows", "50px repeat(auto-fill, minmax(100px, 1fr)) 20px");
    const g = s.grid_template_rows;
    try T.expect(g.auto_repeat == .fill and g.auto_repeat_start == 1 and g.auto_repeat_len == 1 and g.tracks.len == 3);
    s = try t.one("gridTemplateColumns", "repeat(auto-fit, 10px 20px)");
    try T.expect(s.grid_template_columns.auto_repeat == .fit and s.grid_template_columns.auto_repeat_len == 2);
    s = try t.one("gridTemplateColumns", "none");
    try T.expectEqual(@as(usize, 0), s.grid_template_columns.tracks.len);
    s = try t.one("gridTemplateColumns", "repeat(3, 1fr)");
    try T.expectEqual(@as(usize, 3), s.grid_template_columns.tracks.len);
    s = try t.one("gridAutoRows", "min-content 2fr");
    try T.expect(s.grid_auto_rows.len == 2 and s.grid_auto_rows[0].min == .min_content);
    try t.bad("gridTemplateColumns", "repeat(0, 1fr)");
    try t.bad("gridTemplateColumns", "repeat(auto-fill, 1fr) repeat(auto-fit, 2px)");
    try t.bad("gridTemplateColumns", "minmax(1fr, 2fr)");
    try t.bad("gridTemplateColumns", "repeat(2, repeat(2, 1px))");
    try t.bad("gridTemplateColumns", "banana");
    try t.bad("gridTemplateColumns", "repeat(5000, 1px 2px 3px)");
    try T.expectEqual(@as(usize, 10000), (try t.one("gridTemplateColumns", "repeat(100000, 1px)")).grid_template_columns.tracks.len);
    s = try t.one("gridAutoFlow", "dense column");
    try T.expect(s.grid_auto_flow.column and s.grid_auto_flow.dense);
    s = try t.one("gridAutoFlow", "dense");
    try T.expect(!s.grid_auto_flow.column and s.grid_auto_flow.dense);
    s = try t.one("gridColumn", "1 / span 2");
    try T.expect(s.grid_column_start.line == 1 and s.grid_column_end.span == 2);
    s = try t.one("gridRow", "-1");
    try T.expect(s.grid_row_start.line == -1 and s.grid_row_end == .auto);
    s = try t.one("gridRow", "span 3 / auto");
    try T.expect(s.grid_row_start.span == 3 and s.grid_row_end == .auto);
    s = try t.one("gridArea", "1 / 2 / 3 / 4");
    try T.expect(s.grid_row_start.line == 1 and s.grid_column_start.line == 2 and s.grid_row_end.line == 3 and s.grid_column_end.line == 4);
    s = try t.one("gridArea", "2 / 3");
    try T.expect(s.grid_row_start.line == 2 and s.grid_column_start.line == 3 and s.grid_row_end == .auto);
    s = try t.style(null, "{\"gridColumnStart\": 2, \"gridColumnEnd\": \"span 2\", \"gridRowStart\": \"auto\", \"gridRowEnd\": \"3\"}");
    try T.expect(s.grid_column_start.line == 2 and s.grid_column_end.span == 2 and s.grid_row_end.line == 3);
    // takumi accepts 0 and named lines; named lines are unsupported here and become auto
    try T.expect((try t.one("gridColumn", "0")).grid_column_start == .auto);
    try T.expect((try t.one("gridColumn", "header / span 2")).grid_column_start == .auto);
    try t.bad("gridColumn", "span -1");
    try t.bad("gridArea", "1/2/3/4/5");
}

test "borders and outline" {
    var t = TestCx.init();
    defer t.deinit();
    t.ctx.dpr = 2;
    var s = try t.one("border", "2px solid red");
    for (0..4) |i| {
        try T.expectEqual(@as(f32, 4), s.border_width[i]);
        try T.expectEqual(computed.BorderStyle.solid, s.border_style[i]);
        try T.expect(s.border_color[i].rgba.eql(.{ .r = 255, .a = 255 }));
    }
    s = try t.one("border", "dashed");
    try T.expectEqual(@as(f32, 6), s.border_width[0]); // medium * dpr
    try T.expect(s.border_color[0] == .current);
    s = try t.one("border", "#000 thick double");
    try T.expectEqual(@as(f32, 10), s.border_width[2]);
    try T.expectEqual(computed.BorderStyle.double, s.border_style[2]);
    s = try t.style(null, "{\"border\": \"1px solid\", \"borderLeft\": \"thin dotted blue\", \"borderTopWidth\": 0.3, \"borderRightStyle\": \"none\"}");
    try T.expectEqual(computed.BorderStyle.dotted, s.border_style[3]);
    try T.expectEqual(@as(f32, 2), s.border_width[3]);
    try T.expect(approx(s.border_width[0], 0.6));
    const used = s.usedBorderWidths();
    try T.expectEqual([4]f32{ 1, 0, 2, 2 }, used);
    s = try t.one("borderWidth", "1px 2.7px");
    try T.expectEqual([4]f32{ 2, 5.4, 2, 5.4 }, s.border_width);
    try T.expectEqual(@as(f32, 0), s.usedBorderWidths()[0]); // style none
    s = try t.one("borderStyle", "solid none groove");
    try T.expectEqual([4]computed.BorderStyle{ .solid, .none, .groove, .none }, s.border_style);
    s = try t.one("borderColor", "red green blue yellow");
    try T.expect(s.border_color[3].rgba.eql(.{ .r = 255, .g = 255, .a = 255 }));
    try t.bad("border", "2px 3px");
    try t.bad("border", "solid dashed");
    try t.bad("borderWidth", "-1px");
    try t.bad("borderWidth", "10%");
    try t.bad("borderStyle", "wavy");
    s = try t.one("outline", "3px auto");
    try T.expect(s.outline_style == .solid and s.outline_width == 6);
    s = try t.style(null, "{\"outlineColor\": \"red\", \"outlineOffset\": \"-2px\", \"outlineStyle\": \"dashed\", \"outlineWidth\": \"thin\"}");
    try T.expect(s.outline_offset == -4 and s.outline_style == .dashed and s.outline_width == 2);
    try T.expectEqual(@as(f32, 2), s.usedOutlineWidth());
}

test "border radius" {
    var t = TestCx.init();
    defer t.deinit();
    var s = try t.one("borderRadius", "10px");
    for (s.border_radius) |r| {
        try expectLP(r[0], 10, 0);
        try expectLP(r[1], 10, 0);
    }
    s = try t.one("borderRadius", "1px 2px 3px 4px / 5% 6%");
    try expectLP(s.border_radius[0][0], 1, 0);
    try expectLP(s.border_radius[2][0], 3, 0);
    try expectLP(s.border_radius[0][1], 0, 0.05);
    try expectLP(s.border_radius[1][1], 0, 0.06);
    try expectLP(s.border_radius[2][1], 0, 0.05);
    try expectLP(s.border_radius[3][1], 0, 0.06);
    s = try t.one("borderRadius", "1px 2px 3px");
    try expectLP(s.border_radius[3][0], 2, 0);
    s = try t.style(null, "{\"borderRadius\": 8, \"borderTopLeftRadius\": \"4px 50%\", \"borderBottomLeftRadius\": 0}");
    try expectLP(s.border_radius[0][0], 4, 0);
    try expectLP(s.border_radius[0][1], 0, 0.5);
    try expectLP(s.border_radius[3][0], 0, 0);
    try expectLP(s.border_radius[1][1], 8, 0);
    _ = try t.one("borderRadius", "-1px"); // takumi accepts
    try t.bad("borderRadius", "1px / 2px / 3px");
    try t.bad("borderRadius", "1px 2px 3px 4px 5px");
}

test "backgrounds" {
    var t = TestCx.init();
    defer t.deinit();
    var s = try t.one("backgroundColor", "#ff000080");
    try T.expect(s.background_color.rgba.eql(.{ .r = 255, .a = 128 }));
    s = try t.one("backgroundImage", "linear-gradient(red, blue), url(\"a.png\"), none");
    try T.expectEqual(@as(usize, 3), s.background_image.len);
    try T.expect(s.background_image[0] == .gradient);
    try T.expectEqualStrings("a.png", s.background_image[1].url);
    try T.expect(s.background_image[2] == .none);
    s = try t.style(null,
        \\{"backgroundImage": "url(a), url(b), url(c)", "backgroundSize": "cover, 10px auto",
        \\ "backgroundPosition": "right 10px top", "backgroundRepeat": "no-repeat, repeat-x",
        \\ "backgroundClip": "content-box", "backgroundOrigin": "border-box, content-box"}
    );
    const l2 = s.bgLayer(2);
    try T.expect(l2.size == .cover);
    try T.expect(s.bgLayer(1).size.size[0].lp.px == 10 and s.bgLayer(1).size.size[1] == .auto);
    try expectLP(l2.position[0], -10, 1);
    try expectLP(l2.position[1], 0, 0);
    try T.expectEqual([2]computed.BgRepeat{ .no_repeat, .no_repeat }, l2.repeat);
    try T.expectEqual([2]computed.BgRepeat{ .repeat, .no_repeat }, s.bgLayer(1).repeat);
    try T.expect(l2.clip == .content_box and l2.origin == .border_box);
    try T.expect(s.bgColorClip() == .content_box);
    s = try t.one("backgroundRepeat", "space round");
    try T.expectEqual([2]computed.BgRepeat{ .space, .round }, s.background_repeat[0]);
    s = try t.one("backgroundSize", "50%");
    try T.expect(s.background_size[0].size[0].lp.pct == 0.5 and s.background_size[0].size[1] == .auto);
    s = try t.one("backgroundClip", "text");
    try T.expect(s.background_clip[0] == .text);
    try t.bad("backgroundOrigin", "text");
    try t.bad("backgroundSize", "cover cover");
    try t.bad("backgroundImage", "foo(1)");
    try t.bad("backgroundImage", "url(a),");
    try t.bad("backgroundPosition", "top 10px");
}

test "background shorthand" {
    var t = TestCx.init();
    defer t.deinit();
    var s = try t.one("background", "red");
    try T.expect(s.background_color.rgba.eql(.{ .r = 255, .a = 255 }));
    try T.expectEqual(@as(usize, 1), s.background_image.len);
    try T.expect(s.background_image[0] == .none);
    s = try t.one("background", "url(x.png) center / contain no-repeat padding-box content-box fixed, linear-gradient(red, blue) #00f");
    try T.expectEqual(@as(usize, 2), s.background_image.len);
    const l0 = s.bgLayer(0);
    try T.expectEqualStrings("x.png", l0.image.url);
    try expectLP(l0.position[0], 0, 0.5);
    try T.expect(l0.size == .contain);
    try T.expectEqual([2]computed.BgRepeat{ .no_repeat, .no_repeat }, l0.repeat);
    try T.expect(l0.origin == .padding_box and l0.clip == .content_box);
    const l1 = s.bgLayer(1);
    try T.expect(l1.image == .gradient and l1.clip == .border_box and l1.origin == .padding_box);
    try T.expect(s.background_color.rgba.eql(.{ .b = 255, .a = 255 }));
    s = try t.one("background", "content-box radial-gradient(circle, red, blue) 10px 20px / 5px 6px repeat-y");
    const l = s.bgLayer(0);
    try T.expect(l.origin == .content_box and l.clip == .content_box);
    try expectLP(l.position[0], 10, 0);
    try expectLP(l.size.size[1].lp, 6, 0);
    // background resets previously set longhands
    s = try t.style(null, "{\"backgroundColor\": \"red\", \"backgroundSize\": \"cover\", \"background\": \"none\"}");
    try T.expect(s.background_color.rgba.a == 0 and s.background_size[0] != .cover);
    s = try t.one("background", "red, url(a)"); // takumi accepts a colour in a non-final layer
    try T.expect(s.background_color.rgba.r == 255 and s.background_image.len == 2);
    try t.bad("background", "url(a) url(b)");
    try t.bad("background", "red blue");
    try t.bad("background", "center / ");
    try t.bad("background", ",red");
}

test "shadows" {
    var t = TestCx.init();
    defer t.deinit();
    var s = try t.one("boxShadow", "0 12px 40px rgba(0,0,0,0.35)");
    try T.expectEqual(@as(usize, 1), s.box_shadow.len);
    var sh = s.box_shadow[0];
    try T.expect(sh.x == 0 and sh.y == 12 and sh.blur == 40 and sh.spread == 0 and !sh.inset);
    try T.expect(sh.color.rgba.eql(.{ .a = 89 }));
    s = try t.one("boxShadow", "inset red 1px 2px 3px 4px, 5px 6px, 1px 1px blue inset");
    try T.expectEqual(@as(usize, 3), s.box_shadow.len);
    sh = s.box_shadow[0];
    try T.expect(sh.inset and sh.spread == 4 and sh.color.rgba.r == 255);
    try T.expect(s.box_shadow[1].color == .current and !s.box_shadow[1].inset);
    try T.expect(s.box_shadow[2].inset and s.box_shadow[2].color.rgba.b == 255);
    s = try t.one("boxShadow", "none");
    try T.expectEqual(@as(usize, 0), s.box_shadow.len);
    try t.bad("boxShadow", "1px");
    try T.expectEqual(@as(f32, 0), (try t.one("boxShadow", "1px 2px -3px")).box_shadow[0].blur); // takumi accepts
    try t.bad("boxShadow", "1px 2px red 3px");
    try t.bad("boxShadow", "1px 2px 3px 4px 5px");
    try t.bad("boxShadow", "inset inset 1px 1px");
    try t.bad("boxShadow", "1px 1px,");
    try t.bad("boxShadow", "10% 1px");
    s = try t.one("textShadow", "1px 1px 2px black, 0 0 1em blue");
    try T.expectEqual(@as(usize, 2), s.text_shadow.len);
    try T.expect(s.text_shadow[1].blur == 16);
    try t.bad("textShadow", "1px 1px 1px 1px");
    try t.bad("textShadow", "inset 1px 1px");
}

test "opacity / filter / blend / object / image-rendering" {
    var t = TestCx.init();
    defer t.deinit();
    try T.expectEqual(@as(f32, 0.5), (try t.one("opacity", "50%")).opacity);
    try T.expectEqual(@as(f32, 1), (try t.one("opacity", "2")).opacity);
    try T.expectEqual(@as(f32, 0), (try t.one("opacity", "-1")).opacity);
    try T.expectEqual(@as(f32, 0.25), (try t.style(null, "{\"opacity\": 0.25}")).opacity);
    try t.bad("opacity", "half");
    const s = try t.one("filter", "blur(4px) brightness(150%) contrast(2) grayscale(2) invert() opacity(.5) saturate(0) sepia(100%) hue-rotate(90deg) drop-shadow(1px 2px 3px red)");
    try T.expectEqual(@as(usize, 10), s.filter.len);
    try T.expect(s.filter[0].blur == 4 and s.filter[1].brightness == 1.5 and s.filter[2].contrast == 2);
    try T.expect(s.filter[3].grayscale == 1 and s.filter[4].invert == 1 and s.filter[5].opacity == 0.5);
    try T.expect(s.filter[8].hue_rotate == 90 and s.filter[9].drop_shadow.blur == 3);
    try T.expectEqual(@as(usize, 0), (try t.one("filter", "none")).filter.len);
    try T.expectEqual(@as(f32, 0), (try t.one("filter", "blur(-1px)")).filter[0].blur);
    try t.bad("filter", "url(#f)");
    try t.bad("filter", "brightness(-1)");
    try t.bad("filter", "blur(1px, 2px)");
    try T.expect((try t.one("mixBlendMode", "color-dodge")).mix_blend_mode == .color_dodge);
    try T.expect((try t.one("mixBlendMode", "plus-lighter")).mix_blend_mode == .plus_lighter);
    try t.bad("mixBlendMode", "add");
    try T.expect((try t.one("objectFit", "scale-down")).object_fit == .scale_down);
    const op = try t.one("objectPosition", "left bottom");
    try expectLP(op.object_position[0], 0, 0);
    try expectLP(op.object_position[1], 0, 1);
    try T.expect((try t.one("imageRendering", "pixelated")).image_rendering == .pixelated);
    try T.expect((try t.one("imageRendering", "crisp-edges")).image_rendering == .crisp_edges);
    try T.expect((try t.one("imageRendering", "high-quality")).image_rendering == .smooth);
}

test "transforms" {
    var t = TestCx.init();
    defer t.deinit();
    t.ctx.dpr = 2;
    var s = try t.one("transform", "translate(10px, 50%) translateX(1px) translateY(-5%) scale(2) scale(1, 50%) scaleX(3) scaleY(.5) rotate(90deg) rotate(0.5turn) rotate(3.14159rad) skew(10deg) skewX(5deg) skewY(1grad) matrix(1, 0, 0, 1, 10, 20)");
    const o = s.transform;
    try T.expectEqual(@as(usize, 14), o.len);
    try expectLP(o[0].translate[0], 20, 0);
    try expectLP(o[0].translate[1], 0, 0.5);
    try expectLP(o[1].translate[0], 2, 0);
    try expectLP(o[2].translate[1], 0, -0.05);
    try T.expectEqual([2]f32{ 2, 2 }, o[3].scale);
    try T.expectEqual([2]f32{ 1, 0.5 }, o[4].scale);
    try T.expectEqual([2]f32{ 3, 1 }, o[5].scale);
    try T.expectEqual([2]f32{ 1, 0.5 }, o[6].scale);
    try T.expectEqual(@as(f32, 90), o[7].rotate);
    try T.expectEqual(@as(f32, 180), o[8].rotate);
    try T.expect(approx(o[9].rotate, 180));
    try T.expectEqual([2]f32{ 10, 0 }, o[10].skew);
    try T.expectEqual([2]f32{ 0, 0.9 }, o[12].skew);
    try T.expectEqual([6]f32{ 1, 0, 0, 1, 20, 40 }, o[13].matrix);
    try T.expectEqual(@as(usize, 0), (try t.one("transform", "none")).transform.len);
    try T.expectEqual(@as(f32, 0), (try t.one("transform", "rotate(0)")).transform[0].rotate);
    try T.expectEqual(@as(f32, 45), (try t.one("transform", "rotate(45)")).transform[0].rotate); // takumi: unitless = deg
    try t.bad("transform", "translate3d(1px, 2px, 3px)");
    try t.bad("transform", "matrix(1, 2)");
    try t.bad("transform", "translate(1px 2px)");
    try t.bad("transform", "scale()");
    try t.bad("transform", "rotate(45deg),");
    s = try t.style(null, "{\"translate\": \"10px 20%\", \"rotate\": \"45deg\", \"scale\": \"2 3\", \"transformOrigin\": \"top left\"}");
    try expectLP(s.translate[0], 20, 0);
    try expectLP(s.translate[1], 0, 0.2);
    try T.expectEqual(@as(f32, 45), s.rotate);
    try T.expectEqual([2]f32{ 2, 3 }, s.scale);
    try expectLP(s.transform_origin[0], 0, 0);
    try expectLP(s.transform_origin[1], 0, 0);
    s = try t.one("transformOrigin", "20px 30% 5px");
    try expectLP(s.transform_origin[0], 40, 0);
    try expectLP(s.transform_origin[1], 0, 0.3);
    s = try t.one("transformOrigin", "bottom");
    try expectLP(s.transform_origin[0], 0, 0.5);
    try expectLP(s.transform_origin[1], 0, 1);
    try T.expectEqual([2]f32{ 1.5, 1.5 }, (try t.one("scale", "150%")).scale);
    try T.expectEqual(@as(f32, 0), (try t.one("rotate", "none")).rotate);
    try t.bad("rotate", "x 10deg");
}

test "font properties" {
    var t = TestCx.init();
    defer t.deinit();
    const parent = try t.style(null, "{\"fontWeight\": 300}");
    const wts = [_]struct { []const u8, u16 }{
        .{ "normal", 400 }, .{ "bold", 700 }, .{ "bolder", 400 }, .{ "lighter", 100 }, .{ "1", 1 }, .{ "1000", 1000 }, .{ "550", 550 },
    };
    for (wts) |w| {
        const members = try t.a().alloc(json.Member, 1);
        members[0] = .{ .key = "fontWeight", .value = .{ .string = w[0] } };
        const s = try compute(t.a(), &t.ctx, &parent, null, json.Value{ .object = members }, &t.diag);
        try T.expectEqual(w[1], s.font_weight);
    }
    const p6 = try t.style(null, "{\"fontWeight\": 600}");
    try T.expectEqual(@as(u16, 900), (try t.style(&p6, "{\"fontWeight\": \"bolder\"}")).font_weight);
    try T.expectEqual(@as(u16, 400), (try t.style(&p6, "{\"fontWeight\": \"lighter\"}")).font_weight);
    try t.bad("fontWeight", "0");
    try t.bad("fontWeight", "1001");
    try t.bad("fontWeight", "heavy");
    try T.expectEqual(computed.FontStyle.italic, (try t.one("fontStyle", "italic")).font_style);
    try T.expectEqual(computed.FontStyle.oblique, (try t.one("fontStyle", "oblique 10deg")).font_style);
    var s = try t.one("fontFamily", "\"Helvetica Neue\",  Times   New Roman , monospace");
    try T.expectEqual(@as(usize, 3), s.font_family.len);
    try T.expectEqualStrings("Helvetica Neue", s.font_family[0]);
    try T.expectEqualStrings("Times New Roman", s.font_family[1]);
    try T.expectEqualStrings("monospace", s.font_family[2]);
    try t.bad("fontFamily", "Arial,");
    try t.bad("fontFamily", "12px");
    s = try t.one("font", "italic bold 20px/1.5 Inter, sans-serif");
    try T.expect(s.font_style == .italic and s.font_weight == 700 and s.font_size == 20);
    try T.expect(s.line_height.number == 1.5 and s.font_family.len == 2);
    s = try t.one("font", "12px/30px Georgia");
    try T.expect(s.font_size == 12 and s.line_height.px == 30 and s.font_weight == 400);
    s = try t.one("font", "small-caps 600 condensed 2em/1em 'A B'");
    try T.expect(s.font_size == 32 and s.line_height.px == 32 and s.font_weight == 600);
    s = try t.style(null, "{\"fontWeight\": 700, \"lineHeight\": 3, \"font\": \"16px serif\"}");
    try T.expect(s.font_weight == 400 and s.line_height == .normal);
    try t.bad("font", "bold");
    try t.bad("font", "12px");
    try t.bad("font", "caption");
    s = try t.style(null, "{\"lineHeight\": \"normal\"}");
    try T.expect(s.line_height == .normal);
    s = try t.style(null, "{\"lineHeight\": \"1.25\"}");
    try T.expect(s.line_height.number == 1.25);
    s = try t.style(null, "{\"lineHeight\": 24}");
    try T.expect(s.line_height.number == 24);
    s = try t.style(null, "{\"lineHeight\": \"24px\"}");
    try T.expect(s.line_height.px == 24);
    s = try t.style(null, "{\"lineHeight\": \"calc(1 + 0.5)\"}");
    try T.expect(s.line_height.number == 1.5);
    try T.expect((try t.one("lineHeight", "-1")).line_height.number == 0);
}

test "text properties" {
    var t = TestCx.init();
    defer t.deinit();
    var s = try t.style(null,
        \\{"fontSize": 20, "letterSpacing": "0.5em", "wordSpacing": "normal", "textAlign": "justify", "textTransform": "uppercase",
        \\ "textIndent": "10%", "tabSize": 4, "direction": "rtl", "wordBreak": "break-all", "overflowWrap": "anywhere",
        \\ "textOverflow": "ellipsis", "WebkitLineClamp": 3, "WebkitTextStroke": "2px red"}
    );
    try T.expect(s.letter_spacing == 10 and s.word_spacing == 0 and s.text_align == .justify and s.text_transform == .uppercase);
    try expectLP(s.text_indent, 0, 0.1);
    try T.expect(s.tab_size.number == 4 and s.direction == .rtl and s.word_break == .break_all and s.overflow_wrap == .anywhere);
    try T.expect(s.text_overflow == .ellipsis and s.line_clamp == 3);
    try T.expect(s.webkit_text_stroke_width == 2 and s.webkit_text_stroke_color.rgba.r == 255);
    try T.expect((try t.one("wordWrap", "break-word")).overflow_wrap == .break_word);
    try T.expect((try t.one("lineClamp", "none")).line_clamp == 0);
    try T.expect((try t.one("lineClamp", "0")).line_clamp == 0);
    s = try t.one("textOverflow", "\"--\"");
    try T.expect(s.text_overflow == .string and std.mem.eql(u8, s.text_overflow_string, "--"));
    try t.bad("textOverflow", "string");
    try t.bad("translate", "1px 2px 3px");
    try t.bad("textAlign", "middle");
    try T.expect((try t.one("tabSize", "20px")).tab_size.px == 20);
    // white-space
    const ws = [_]struct { []const u8, computed.WhiteSpaceCollapse, computed.TextWrapMode }{
        .{ "normal", .collapse, .wrap },         .{ "nowrap", .collapse, .nowrap },     .{ "pre", .preserve, .nowrap },
        .{ "pre-wrap", .preserve, .wrap },       .{ "pre-line", .preserve_breaks, .wrap }, .{ "break-spaces", .break_spaces, .wrap },
        .{ "preserve nowrap", .preserve, .nowrap },
    };
    for (ws) |w| {
        s = try t.one("whiteSpace", w[0]);
        try T.expect(s.white_space_collapse == w[1] and s.text_wrap_mode == w[2]);
    }
    try t.bad("whiteSpace", "pre pre");
    s = try t.one("textWrap", "balance");
    try T.expect(s.text_wrap_style == .balance and s.text_wrap_mode == .wrap);
    s = try t.one("textWrap", "nowrap");
    try T.expect(s.text_wrap_mode == .nowrap);
    s = try t.style(null, "{\"textWrapMode\": \"nowrap\", \"textWrapStyle\": \"pretty\", \"whiteSpaceCollapse\": \"preserve-breaks\"}");
    try T.expect(s.text_wrap_mode == .nowrap and s.text_wrap_style == .pretty and s.white_space_collapse == .preserve_breaks);
    // text-decoration
    s = try t.one("textDecoration", "underline line-through wavy red 2px");
    try T.expect(s.text_decoration_line.underline and s.text_decoration_line.line_through and !s.text_decoration_line.overline);
    try T.expect(s.text_decoration_style == .wavy and s.text_decoration_color.rgba.r == 255 and s.text_decoration_thickness.? == 2);
    s = try t.one("textDecoration", "none");
    try T.expect(!s.text_decoration_line.underline);
    s = try t.style(null, "{\"textDecorationLine\": \"overline\", \"textDecorationColor\": \"blue\", \"textDecorationStyle\": \"dotted\", \"textDecorationThickness\": \"from-font\"}");
    try T.expect(s.text_decoration_line.overline and s.text_decoration_style == .dotted and s.text_decoration_thickness == null);
    try T.expect((try t.one("textDecoration", "underline underline")).text_decoration_line.underline);
    try t.bad("textDecorationLine", "solid");
    try t.bad("letterSpacing", "wide");
}

test "fuzz: parsers never crash" {
    var arena_state = std.heap.ArenaAllocator.init(T.allocator);
    defer arena_state.deinit();
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rnd = prng.random();
    const seeds = [_][]const u8{
        "calc(100% - (2 * 3px))", "linear-gradient(45deg, red 10%, 30%, blue 50% 60%)", "rgb(1 2 3 / 50%)",
        "repeat(auto-fill, minmax(10px, 1fr)) [a b]", "inset 1px 2px 3px 4px red, 0 0 #fff", "url(\"a(b)\") center / cover no-repeat",
        "italic bold 12px/1.5 'Inter', sans-serif", "radial-gradient(circle at 10% 20%, red, blue)",
        "conic-gradient(from 10deg at center, red 0 10%, blue)", "translate(1px, 2%) rotate(1turn) matrix(1,2,3,4,5,6)",
        "1 / span 2", "min(1px, max(2px, clamp(1px, 2px, 3px)))", "hsl(120deg 100% 25% / .5)", "drop-shadow(1px 1px red) blur(2px)",
        "right 10px bottom 20%", "1px 2px 3px 4px / 5px", "#0f08", "((((((((", "\"unterminated", "/* comment",
    };
    const alphabet = "()[],/*+- .%#\"'0123456789pxemrdgaucltnbi!\\";
    var buf: [96]u8 = undefined;
    const ctx: Context = .{ .dpr = 1.5, .viewport_w = 100, .viewport_h = 100, .root_font_size = 16 };
    const parent = initial(&ctx);
    var iter: usize = 0;
    while (iter < 3000) : (iter += 1) {
        _ = arena_state.reset(.retain_capacity);
        const a = arena_state.allocator();
        var n: usize = 0;
        if (rnd.boolean()) {
            const seed = seeds[rnd.uintLessThan(usize, seeds.len)];
            n = @min(seed.len, buf.len);
            @memcpy(buf[0..n], seed[0..n]);
            var m: usize = 0;
            while (m < 4) : (m += 1) {
                if (n == 0) break;
                const pos = rnd.uintLessThan(usize, n);
                switch (rnd.uintLessThan(u8, 3)) {
                    0 => buf[pos] = alphabet[rnd.uintLessThan(usize, alphabet.len)],
                    1 => n = pos,
                    else => buf[pos] = rnd.int(u8),
                }
            }
        } else {
            n = rnd.uintLessThan(usize, buf.len);
            for (buf[0..n]) |*b| b.* = if (rnd.boolean()) alphabet[rnd.uintLessThan(usize, alphabet.len)] else rnd.int(u8);
        }
        const val = buf[0..n];
        for (std.enums.values(props.Prop)) |p| {
            const members = try a.alloc(json.Member, 1);
            members[0] = .{ .key = @tagName(p), .value = .{ .string = val } };
            var d: Diagnostics = .{};
            _ = compute(a, &ctx, &parent, null, json.Value{ .object = members }, &d) catch {};
        }
    }
}
