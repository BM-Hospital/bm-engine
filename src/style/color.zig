//! CSS colour parsing: hex, rgb()/rgba(), hsl()/hsla(), hwb(), named colours, transparent, currentColor.
//! Modern colour spaces (lab/lch/oklab/oklch/color()/color-mix()) are NOT supported -> InvalidStyleValue.
const std = @import("std");
const tok = @import("tokenizer.zig");
const Error = tok.Error;
const Token = tok.Token;
const Lexer = tok.Lexer;

/// Straight (non-premultiplied) sRGB colour.
pub const Color = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    pub const transparent: Color = .{};
    pub const black: Color = .{ .a = 255 };

    pub fn eql(x: Color, y: Color) bool {
        return x.r == y.r and x.g == y.g and x.b == y.b and x.a == y.a;
    }
};

/// A computed colour that may still refer to the element's `color` (currentColor).
pub const ColorValue = union(enum) {
    rgba: Color,
    current,

    pub fn resolve(v: ColorValue, current_color: Color) Color {
        return switch (v) {
            .rgba => |c| c,
            .current => current_color,
        };
    }
};

fn clampByte(v: f32) u8 {
    if (!(v > 0)) return 0; // also NaN
    if (v >= 255) return 255;
    return @intFromFloat(@round(v));
}

/// Parses a colour from an already-read token. Returns null if the token cannot start a colour
/// or is malformed / an unsupported colour space (lab, lch, oklab, oklch, color(), color-mix()); callers
/// treat null as "not a colour", which ends in InvalidStyleValue wherever a colour is required.
pub fn fromToken(t: Token) ?ColorValue {
    switch (t.kind) {
        .hash => return .{ .rgba = parseHex(t.text) orelse return null },
        .ident => {
            if (std.ascii.eqlIgnoreCase(t.text, "currentcolor")) return .current;
            if (named(t.text)) |c| return .{ .rgba = c };
            return null;
        },
        .function => {
            const n = t.text;
            if (std.ascii.eqlIgnoreCase(n, "rgb") or std.ascii.eqlIgnoreCase(n, "rgba"))
                return .{ .rgba = parseFunc(t.args, .rgb) orelse return null };
            if (std.ascii.eqlIgnoreCase(n, "hsl") or std.ascii.eqlIgnoreCase(n, "hsla"))
                return .{ .rgba = parseFunc(t.args, .hsl) orelse return null };
            if (std.ascii.eqlIgnoreCase(n, "hwb"))
                return .{ .rgba = parseFunc(t.args, .hwb) orelse return null };
            return null;
        },
        else => return null,
    }
}

/// Parses a whole string as one colour (whitespace allowed around it).
pub fn parse(s: []const u8) Error!ColorValue {
    var l = Lexer.init(s);
    const c = fromToken(l.next()) orelse return error.InvalidStyleValue;
    if (!l.atEnd()) return error.InvalidStyleValue;
    return c;
}

fn hexVal(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn parseHex(h: []const u8) ?Color {
    var d: [8]u8 = undefined;
    if (h.len != 3 and h.len != 4 and h.len != 6 and h.len != 8) return null;
    for (h, 0..) |c, i| d[i] = hexVal(c) orelse return null;
    if (h.len <= 4) {
        return .{ .r = d[0] * 17, .g = d[1] * 17, .b = d[2] * 17, .a = if (h.len == 4) d[3] * 17 else 255 };
    }
    return .{
        .r = d[0] * 16 + d[1],
        .g = d[2] * 16 + d[3],
        .b = d[4] * 16 + d[5],
        .a = if (h.len == 8) d[6] * 16 + d[7] else 255,
    };
}

const FuncKind = enum { rgb, hsl, hwb };

const Arg = struct { v: f32, pct: bool, none: bool = false };

fn angleDeg(t: Token) ?f32 {
    if (t.kind == .number) return t.num;
    if (t.kind != .dimension) return null;
    const f = angleFactor(t.text) orelse return null;
    return t.num * f;
}

pub fn angleFactor(unit: []const u8) ?f32 {
    if (std.ascii.eqlIgnoreCase(unit, "deg")) return 1;
    if (std.ascii.eqlIgnoreCase(unit, "rad")) return 180.0 / std.math.pi;
    if (std.ascii.eqlIgnoreCase(unit, "grad")) return 0.9;
    if (std.ascii.eqlIgnoreCase(unit, "turn")) return 360;
    return null;
}

fn parseFunc(args: []const u8, kind: FuncKind) ?Color {
    var l = Lexer.init(args);
    var vals: [4]Arg = undefined;
    var n: usize = 0;
    var legacy: ?bool = null; // comma syntax?
    var saw_slash = false;
    while (true) {
        var cur = l.next();
        if (cur.kind == .eof) break;
        if (n > 0) {
            if (legacy == null) legacy = (cur.kind == .comma);
            if (legacy.?) {
                if (cur.kind != .comma) return null;
                cur = l.next();
            } else if (cur.kind == .slash) {
                if (n != 3 or saw_slash) return null;
                saw_slash = true;
                cur = l.next();
            } else if (n == 3) return null; // modern alpha needs '/'
        }
        if (n >= 4) return null;
        vals[n] = switch (cur.kind) {
            .number => .{ .v = cur.num, .pct = false },
            .percentage => .{ .v = cur.num, .pct = true },
            .dimension => if (n == 0 and kind != .rgb)
                .{ .v = angleDeg(cur) orelse return null, .pct = false }
            else
                return null,
            .ident => if (legacy != true and std.ascii.eqlIgnoreCase(cur.text, "none"))
                .{ .v = 0, .pct = false, .none = true }
            else
                return null,
            else => return null,
        };
        n += 1;
    }
    if (n < 3) return null;
    if (legacy == true and kind == .hwb) return null;
    var a: u8 = 255;
    if (n == 4) {
        const av = if (vals[3].pct) vals[3].v / 100 else vals[3].v;
        a = clampByte(std.math.clamp(av, 0, 1) * 255);
    }
    switch (kind) {
        .rgb => {
            var out: [3]u8 = undefined;
            for (0..3) |i| out[i] = clampByte(if (vals[i].pct) vals[i].v * 2.55 else vals[i].v);
            return .{ .r = out[0], .g = out[1], .b = out[2], .a = a };
        },
        .hsl, .hwb => {
            if (vals[0].pct) return null;
            if (legacy == true and (!vals[1].pct or !vals[2].pct)) return null;
            const h = vals[0].v;
            const p1 = std.math.clamp(vals[1].v / 100, 0, 1);
            const p2 = std.math.clamp(vals[2].v / 100, 0, 1);
            var rgb: [3]f32 = undefined;
            if (kind == .hsl) {
                rgb = hslToRgb(h, p1, p2);
            } else {
                const w = p1;
                const bk = p2;
                if (w + bk >= 1) {
                    const g = w / (w + bk);
                    rgb = .{ g, g, g };
                } else {
                    rgb = hslToRgb(h, 1, 0.5);
                    for (&rgb) |*c| c.* = c.* * (1 - w - bk) + w;
                }
            }
            return .{ .r = clampByte(rgb[0] * 255), .g = clampByte(rgb[1] * 255), .b = clampByte(rgb[2] * 255), .a = a };
        },
    }
}

fn hslToRgb(h_deg: f32, s: f32, l: f32) [3]f32 {
    var h = h_deg - 360 * @floor(h_deg / 360);
    if (!(h >= 0 and h < 360)) h = 0; // NaN / inf guard
    var out: [3]f32 = undefined;
    const ns = [3]f32{ 0, 8, 4 };
    for (ns, 0..) |n, i| {
        const kk = n + h / 30;
        const k = kk - 12 * @floor(kk / 12);
        const a = s * @min(l, 1 - l);
        out[i] = l - a * @max(-1, @min(@min(k - 3, 9 - k), 1));
    }
    return out;
}

// ---- named colours (CSS Color 4, 148 names), sorted for binary search ----
const Named = struct { n: []const u8, c: u32 };
const names = [_]Named{
    .{ .n = "aliceblue", .c = 0xf0f8ff },            .{ .n = "antiquewhite", .c = 0xfaebd7 },
    .{ .n = "aqua", .c = 0x00ffff },                 .{ .n = "aquamarine", .c = 0x7fffd4 },
    .{ .n = "azure", .c = 0xf0ffff },                .{ .n = "beige", .c = 0xf5f5dc },
    .{ .n = "bisque", .c = 0xffe4c4 },               .{ .n = "black", .c = 0x000000 },
    .{ .n = "blanchedalmond", .c = 0xffebcd },       .{ .n = "blue", .c = 0x0000ff },
    .{ .n = "blueviolet", .c = 0x8a2be2 },           .{ .n = "brown", .c = 0xa52a2a },
    .{ .n = "burlywood", .c = 0xdeb887 },            .{ .n = "cadetblue", .c = 0x5f9ea0 },
    .{ .n = "chartreuse", .c = 0x7fff00 },           .{ .n = "chocolate", .c = 0xd2691e },
    .{ .n = "coral", .c = 0xff7f50 },                .{ .n = "cornflowerblue", .c = 0x6495ed },
    .{ .n = "cornsilk", .c = 0xfff8dc },             .{ .n = "crimson", .c = 0xdc143c },
    .{ .n = "cyan", .c = 0x00ffff },                 .{ .n = "darkblue", .c = 0x00008b },
    .{ .n = "darkcyan", .c = 0x008b8b },             .{ .n = "darkgoldenrod", .c = 0xb8860b },
    .{ .n = "darkgray", .c = 0xa9a9a9 },             .{ .n = "darkgreen", .c = 0x006400 },
    .{ .n = "darkgrey", .c = 0xa9a9a9 },             .{ .n = "darkkhaki", .c = 0xbdb76b },
    .{ .n = "darkmagenta", .c = 0x8b008b },          .{ .n = "darkolivegreen", .c = 0x556b2f },
    .{ .n = "darkorange", .c = 0xff8c00 },           .{ .n = "darkorchid", .c = 0x9932cc },
    .{ .n = "darkred", .c = 0x8b0000 },              .{ .n = "darksalmon", .c = 0xe9967a },
    .{ .n = "darkseagreen", .c = 0x8fbc8f },         .{ .n = "darkslateblue", .c = 0x483d8b },
    .{ .n = "darkslategray", .c = 0x2f4f4f },        .{ .n = "darkslategrey", .c = 0x2f4f4f },
    .{ .n = "darkturquoise", .c = 0x00ced1 },        .{ .n = "darkviolet", .c = 0x9400d3 },
    .{ .n = "deeppink", .c = 0xff1493 },             .{ .n = "deepskyblue", .c = 0x00bfff },
    .{ .n = "dimgray", .c = 0x696969 },              .{ .n = "dimgrey", .c = 0x696969 },
    .{ .n = "dodgerblue", .c = 0x1e90ff },           .{ .n = "firebrick", .c = 0xb22222 },
    .{ .n = "floralwhite", .c = 0xfffaf0 },          .{ .n = "forestgreen", .c = 0x228b22 },
    .{ .n = "fuchsia", .c = 0xff00ff },              .{ .n = "gainsboro", .c = 0xdcdcdc },
    .{ .n = "ghostwhite", .c = 0xf8f8ff },           .{ .n = "gold", .c = 0xffd700 },
    .{ .n = "goldenrod", .c = 0xdaa520 },            .{ .n = "gray", .c = 0x808080 },
    .{ .n = "green", .c = 0x008000 },                .{ .n = "greenyellow", .c = 0xadff2f },
    .{ .n = "grey", .c = 0x808080 },                 .{ .n = "honeydew", .c = 0xf0fff0 },
    .{ .n = "hotpink", .c = 0xff69b4 },              .{ .n = "indianred", .c = 0xcd5c5c },
    .{ .n = "indigo", .c = 0x4b0082 },               .{ .n = "ivory", .c = 0xfffff0 },
    .{ .n = "khaki", .c = 0xf0e68c },                .{ .n = "lavender", .c = 0xe6e6fa },
    .{ .n = "lavenderblush", .c = 0xfff0f5 },        .{ .n = "lawngreen", .c = 0x7cfc00 },
    .{ .n = "lemonchiffon", .c = 0xfffacd },         .{ .n = "lightblue", .c = 0xadd8e6 },
    .{ .n = "lightcoral", .c = 0xf08080 },           .{ .n = "lightcyan", .c = 0xe0ffff },
    .{ .n = "lightgoldenrodyellow", .c = 0xfafad2 }, .{ .n = "lightgray", .c = 0xd3d3d3 },
    .{ .n = "lightgreen", .c = 0x90ee90 },           .{ .n = "lightgrey", .c = 0xd3d3d3 },
    .{ .n = "lightpink", .c = 0xffb6c1 },            .{ .n = "lightsalmon", .c = 0xffa07a },
    .{ .n = "lightseagreen", .c = 0x20b2aa },        .{ .n = "lightskyblue", .c = 0x87cefa },
    .{ .n = "lightslategray", .c = 0x778899 },       .{ .n = "lightslategrey", .c = 0x778899 },
    .{ .n = "lightsteelblue", .c = 0xb0c4de },       .{ .n = "lightyellow", .c = 0xffffe0 },
    .{ .n = "lime", .c = 0x00ff00 },                 .{ .n = "limegreen", .c = 0x32cd32 },
    .{ .n = "linen", .c = 0xfaf0e6 },                .{ .n = "magenta", .c = 0xff00ff },
    .{ .n = "maroon", .c = 0x800000 },               .{ .n = "mediumaquamarine", .c = 0x66cdaa },
    .{ .n = "mediumblue", .c = 0x0000cd },           .{ .n = "mediumorchid", .c = 0xba55d3 },
    .{ .n = "mediumpurple", .c = 0x9370db },         .{ .n = "mediumseagreen", .c = 0x3cb371 },
    .{ .n = "mediumslateblue", .c = 0x7b68ee },      .{ .n = "mediumspringgreen", .c = 0x00fa9a },
    .{ .n = "mediumturquoise", .c = 0x48d1cc },      .{ .n = "mediumvioletred", .c = 0xc71585 },
    .{ .n = "midnightblue", .c = 0x191970 },         .{ .n = "mintcream", .c = 0xf5fffa },
    .{ .n = "mistyrose", .c = 0xffe4e1 },            .{ .n = "moccasin", .c = 0xffe4b5 },
    .{ .n = "navajowhite", .c = 0xffdead },          .{ .n = "navy", .c = 0x000080 },
    .{ .n = "oldlace", .c = 0xfdf5e6 },              .{ .n = "olive", .c = 0x808000 },
    .{ .n = "olivedrab", .c = 0x6b8e23 },            .{ .n = "orange", .c = 0xffa500 },
    .{ .n = "orangered", .c = 0xff4500 },            .{ .n = "orchid", .c = 0xda70d6 },
    .{ .n = "palegoldenrod", .c = 0xeee8aa },        .{ .n = "palegreen", .c = 0x98fb98 },
    .{ .n = "paleturquoise", .c = 0xafeeee },        .{ .n = "palevioletred", .c = 0xdb7093 },
    .{ .n = "papayawhip", .c = 0xffefd5 },           .{ .n = "peachpuff", .c = 0xffdab9 },
    .{ .n = "peru", .c = 0xcd853f },                 .{ .n = "pink", .c = 0xffc0cb },
    .{ .n = "plum", .c = 0xdda0dd },                 .{ .n = "powderblue", .c = 0xb0e0e6 },
    .{ .n = "purple", .c = 0x800080 },               .{ .n = "rebeccapurple", .c = 0x663399 },
    .{ .n = "red", .c = 0xff0000 },                  .{ .n = "rosybrown", .c = 0xbc8f8f },
    .{ .n = "royalblue", .c = 0x4169e1 },            .{ .n = "saddlebrown", .c = 0x8b4513 },
    .{ .n = "salmon", .c = 0xfa8072 },               .{ .n = "sandybrown", .c = 0xf4a460 },
    .{ .n = "seagreen", .c = 0x2e8b57 },             .{ .n = "seashell", .c = 0xfff5ee },
    .{ .n = "sienna", .c = 0xa0522d },               .{ .n = "silver", .c = 0xc0c0c0 },
    .{ .n = "skyblue", .c = 0x87ceeb },              .{ .n = "slateblue", .c = 0x6a5acd },
    .{ .n = "slategray", .c = 0x708090 },            .{ .n = "slategrey", .c = 0x708090 },
    .{ .n = "snow", .c = 0xfffafa },                 .{ .n = "springgreen", .c = 0x00ff7f },
    .{ .n = "steelblue", .c = 0x4682b4 },            .{ .n = "tan", .c = 0xd2b48c },
    .{ .n = "teal", .c = 0x008080 },                 .{ .n = "thistle", .c = 0xd8bfd8 },
    .{ .n = "tomato", .c = 0xff6347 },               .{ .n = "transparent", .c = 0xffffffff },
    .{ .n = "turquoise", .c = 0x40e0d0 },            .{ .n = "violet", .c = 0xee82ee },
    .{ .n = "wheat", .c = 0xf5deb3 },                .{ .n = "white", .c = 0xffffff },
    .{ .n = "whitesmoke", .c = 0xf5f5f5 },           .{ .n = "yellow", .c = 0xffff00 },
    .{ .n = "yellowgreen", .c = 0x9acd32 },
};

// Runtime form of `names`: one concatenated string + u16 offsets + packed RGB (the slice table
// above is only used at comptime and in tests).
const color_pack: []const u8 = blk: {
    @setEvalBranchQuota(20000);
    var out: []const u8 = "";
    for (names) |n| out = out ++ n.n;
    break :blk out;
};
const color_off: [names.len + 1]u16 = blk: {
    var o: [names.len + 1]u16 = undefined;
    var k: usize = 0;
    for (names, 0..) |n, i| {
        o[i] = k;
        k += n.n.len;
    }
    o[names.len] = k;
    break :blk o;
};
const color_rgb: [names.len]u32 = blk: {
    var o: [names.len]u32 = undefined;
    for (names, 0..) |n, i| o[i] = n.c;
    break :blk o;
};

/// Case-insensitive named-colour lookup (includes `transparent`).
pub fn named(name: []const u8) ?Color {
    if (name.len < 3 or name.len > 20) return null;
    var buf: [20]u8 = undefined;
    const low = std.ascii.lowerString(&buf, name);
    var lo: usize = 0;
    var hi: usize = names.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        switch (std.mem.order(u8, color_pack[color_off[mid]..color_off[mid + 1]], low)) {
            .eq => {
                const c = color_rgb[mid];
                if (c == 0xffffffff) return Color.transparent;
                return .{ .r = @truncate(c >> 16), .g = @truncate(c >> 8), .b = @truncate(c), .a = 255 };
            },
            .lt => lo = mid + 1,
            .gt => hi = mid,
        }
    }
    return null;
}

// ---------------------------------------------------------------------------------------------
const t_ = std.testing;

fn expectColor(s: []const u8, r: u8, g: u8, b: u8, a: u8) !void {
    const v = parse(s) catch |e| {
        std.debug.print("colour '{s}' failed: {}\n", .{ s, e });
        return e;
    };
    try t_.expect(v == .rgba);
    t_.expect(v.rgba.eql(.{ .r = r, .g = g, .b = b, .a = a })) catch |e| {
        std.debug.print("colour '{s}' = {any}\n", .{ s, v.rgba });
        return e;
    };
}

test "named table sorted and complete" {
    try t_.expectEqual(@as(usize, 149), names.len); // 148 + transparent
    for (1..names.len) |i| try t_.expect(std.mem.order(u8, names[i - 1].n, names[i].n) == .lt);
    for (names) |n| try t_.expect(named(n.n) != null);
}

test "colour vectors" {
    try expectColor("#f00", 255, 0, 0, 255);
    try expectColor("#0f08", 0, 255, 0, 136);
    try expectColor("#123456", 0x12, 0x34, 0x56, 255);
    try expectColor("#12345678", 0x12, 0x34, 0x56, 0x78);
    try expectColor("#ABCDEF", 0xab, 0xcd, 0xef, 255);
    try expectColor("red", 255, 0, 0, 255);
    try expectColor("RebeccaPurple", 0x66, 0x33, 0x99, 255);
    try expectColor("transparent", 0, 0, 0, 0);
    try expectColor("rgb(255, 0, 0)", 255, 0, 0, 255);
    try expectColor("rgba(255,0,0,0.5)", 255, 0, 0, 128);
    try expectColor("rgb(255 0 0 / 50%)", 255, 0, 0, 128);
    try expectColor("rgb(100% 50% 0%)", 255, 128, 0, 255);
    try expectColor("rgba(0 0 0 / .35)", 0, 0, 0, 89);
    try expectColor("rgb(300 -5 12.6)", 255, 0, 13, 255);
    try expectColor("rgb(255 0 0 / 2)", 255, 0, 0, 255);
    try expectColor("rgb(none 0 0)", 0, 0, 0, 255);
    try expectColor("rgba(255,0,0)", 255, 0, 0, 255);
    try expectColor("rgb(10 20 30 / 0)", 10, 20, 30, 0);
    try expectColor("hsl(120deg 100% 25%)", 0, 128, 0, 255);
    try expectColor("hsl(0, 100%, 50%)", 255, 0, 0, 255);
    try expectColor("hsla(240, 100%, 50%, 0.5)", 0, 0, 255, 128);
    try expectColor("hsl(0.5turn 100% 50%)", 0, 255, 255, 255);
    try expectColor("hsl(-120 100% 50%)", 0, 0, 255, 255);
    try expectColor("hsl(60 100 50)", 255, 255, 0, 255);
    try expectColor("hwb(0 0% 0%)", 255, 0, 0, 255);
    try expectColor("hwb(120 50% 50%)", 128, 128, 128, 255);
    try expectColor("hwb(240 20% 30% / 0.5)", 51, 51, 179, 128);
    const cc = try parse("currentColor");
    try t_.expect(cc == .current);
    try t_.expect((try parse("CURRENTCOLOR")) == .current);
}

test "colour errors" {
    const bad = [_][]const u8{
        "#ff",       "#fffff",              "#ggg",                "rgb(1,2)",               "rgb(1 2 3 4)",
        "rgb(1,2 3)", "rgb(1, 2, 3, 4, 5)", "rgb(1px 2 3)",       "hsl(1%, 2%, 3%)",
        "oklch(0.5 0.1 20)", "lab(50 20 20)", "color-mix(in srgb, red, blue)", "notacolor", "rgb(1 2 3 /)",
        "hwb(1, 2%, 3%)", "rgb()",          "red blue",            "rgb(1 2 3 / 4 / 5)",
    };
    for (bad) |s| {
        if (parse(s)) |v| {
            std.debug.print("expected failure for '{s}', got {any}\n", .{ s, v });
            return error.TestUnexpectedResult;
        } else |_| {}
    }
}
