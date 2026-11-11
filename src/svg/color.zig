//! CSS colour parsing (hex, rgb[a](), hsl[a](), named colours, transparent). `currentColor`
//! and `none` are handled by callers.
const std = @import("std");
const raster = @import("../raster/raster.zig");
const num = @import("num.zig");
const Color = raster.Color;

/// "name rrggbb" records, space separated (lower-case names).
const NAMED =
    "aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff beige f5f5dc bisque ffe4c4 " ++
    "black 000000 blanchedalmond ffebcd blue 0000ff blueviolet 8a2be2 brown a52a2a burlywood deb887 cadetblue 5f9ea0 " ++
    "chartreuse 7fff00 chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c cyan 00ffff " ++
    "darkblue 00008b darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 darkgreen 006400 darkgrey a9a9a9 " ++
    "darkkhaki bdb76b darkmagenta 8b008b darkolivegreen 556b2f darkorange ff8c00 darkorchid 9932cc darkred 8b0000 " ++
    "darksalmon e9967a darkseagreen 8fbc8f darkslateblue 483d8b darkslategray 2f4f4f darkslategrey 2f4f4f " ++
    "darkturquoise 00ced1 darkviolet 9400d3 deeppink ff1493 deepskyblue 00bfff dimgray 696969 dimgrey 696969 " ++
    "dodgerblue 1e90ff firebrick b22222 floralwhite fffaf0 forestgreen 228b22 fuchsia ff00ff gainsboro dcdcdc " ++
    "ghostwhite f8f8ff gold ffd700 goldenrod daa520 gray 808080 green 008000 greenyellow adff2f grey 808080 " ++
    "honeydew f0fff0 hotpink ff69b4 indianred cd5c5c indigo 4b0082 ivory fffff0 khaki f0e68c lavender e6e6fa " ++
    "lavenderblush fff0f5 lawngreen 7cfc00 lemonchiffon fffacd lightblue add8e6 lightcoral f08080 lightcyan e0ffff " ++
    "lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgreen 90ee90 lightgrey d3d3d3 lightpink ffb6c1 " ++
    "lightsalmon ffa07a lightseagreen 20b2aa lightskyblue 87cefa lightslategray 778899 lightslategrey 778899 " ++
    "lightsteelblue b0c4de lightyellow ffffe0 lime 00ff00 limegreen 32cd32 linen faf0e6 magenta ff00ff maroon 800000 " ++
    "mediumaquamarine 66cdaa mediumblue 0000cd mediumorchid ba55d3 mediumpurple 9370db mediumseagreen 3cb371 " ++
    "mediumslateblue 7b68ee mediumspringgreen 00fa9a mediumturquoise 48d1cc mediumvioletred c71585 " ++
    "midnightblue 191970 mintcream f5fffa mistyrose ffe4e1 moccasin ffe4b5 navajowhite ffdead navy 000080 " ++
    "oldlace fdf5e6 olive 808000 olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6 palegoldenrod eee8aa " ++
    "palegreen 98fb98 paleturquoise afeeee palevioletred db7093 papayawhip ffefd5 peachpuff ffdab9 peru cd853f " ++
    "pink ffc0cb plum dda0dd powderblue b0e0e6 purple 800080 rebeccapurple 663399 red ff0000 rosybrown bc8f8f " ++
    "royalblue 4169e1 saddlebrown 8b4513 salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee " ++
    "sienna a0522d silver c0c0c0 skyblue 87ceeb slateblue 6a5acd slategray 708090 slategrey 708090 snow fffafa " ++
    "springgreen 00ff7f steelblue 4682b4 tan d2b48c teal 008080 thistle d8bfd8 tomato ff6347 turquoise 40e0d0 " ++
    "violet ee82ee wheat f5deb3 white ffffff whitesmoke f5f5f5 yellow ffff00 yellowgreen 9acd32 ";

fn hex(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn hexColor(h: []const u8) ?Color {
    var v: [8]u8 = undefined;
    if (h.len != 3 and h.len != 4 and h.len != 6 and h.len != 8) return null;
    for (h, 0..) |c, i| v[i] = hex(c) orelse return null;
    return switch (h.len) {
        3 => Color.rgb(v[0] * 17, v[1] * 17, v[2] * 17),
        4 => Color.rgba(v[0] * 17, v[1] * 17, v[2] * 17, v[3] * 17),
        6 => Color.rgb(v[0] * 16 + v[1], v[2] * 16 + v[3], v[4] * 16 + v[5]),
        else => Color.rgba(v[0] * 16 + v[1], v[2] * 16 + v[3], v[4] * 16 + v[5], v[6] * 16 + v[7]),
    };
}

fn named(name: []const u8) ?Color {
    if (name.len > 24) return null;
    var buf: [24]u8 = undefined;
    const n = std.ascii.lowerString(&buf, name);
    var i: usize = 0;
    while (i < NAMED.len) {
        const sp = std.mem.indexOfScalarPos(u8, NAMED, i, ' ') orelse return null;
        if (std.mem.eql(u8, NAMED[i..sp], n)) return hexColor(NAMED[sp + 1 .. sp + 7]);
        i = sp + 8;
    }
    return null;
}

fn clamp255(v: f32) u8 {
    if (!(v > 0)) return 0;
    if (v >= 255) return 255;
    return @intFromFloat(v + 0.5);
}

/// Parses a colour; returns null for `none`, `currentColor`, url() and invalid input.
/// Trailing ICC colour specifications (`#fff icc-color(...)`) are ignored.
pub fn parse(s_in: []const u8) ?Color {
    const s = num.trim(s_in);
    if (s.len == 0) return null;
    if (s[0] == '#') {
        var e: usize = 1;
        while (e < s.len and hex(s[e]) != null) e += 1;
        return hexColor(s[1..e]);
    }
    const paren = std.mem.indexOfScalar(u8, s, '(') orelse {
        if (num.eqlIgnoreCase(s, "transparent")) return Color.transparent;
        // first word only (e.g. "red icc-color(..)")
        var e: usize = 0;
        while (e < s.len and std.ascii.isAlphabetic(s[e])) e += 1;
        return named(s[0..e]);
    };
    const fname = num.trim(s[0..paren]);
    const close = std.mem.indexOfScalarPos(u8, s, paren, ')') orelse s.len;
    var r: num.Reader = .{ .s = s[paren + 1 .. close] };
    var v: [4]f32 = .{ 0, 0, 0, 1 };
    var pct: [4]bool = .{ false, false, false, false };
    var n: usize = 0;
    while (n < 4) {
        r.skipWs();
        if (r.i < r.s.len and r.s[r.i] == '/') {
            r.i += 1;
            if (n != 3) return null;
        }
        v[n] = r.number() orelse break;
        const u = r.ident();
        pct[n] = std.mem.eql(u8, u, "%");
        if (n == 0 and u.len > 0 and !pct[0]) {
            // hue units
            if (num.eqlIgnoreCase(u, "rad")) v[0] = v[0] * 180 / std.math.pi else if (num.eqlIgnoreCase(u, "turn")) v[0] *= 360;
        }
        n += 1;
        r.skipSep();
    }
    if (n < 3) return null;
    const alpha: f32 = if (n == 4) (if (pct[3]) v[3] / 100 else v[3]) else 1;
    const a8 = clamp255(alpha * 255);
    if (num.eqlIgnoreCase(fname, "rgb") or num.eqlIgnoreCase(fname, "rgba")) {
        var c: [3]u8 = undefined;
        for (0..3) |i| c[i] = clamp255(if (pct[i]) v[i] * 2.55 else v[i]);
        return Color.rgba(c[0], c[1], c[2], a8);
    }
    if (num.eqlIgnoreCase(fname, "hsl") or num.eqlIgnoreCase(fname, "hsla")) {
        var h = num.fmod(v[0], 360) / 60;
        if (!std.math.isFinite(h)) h = 0;
        const sat = std.math.clamp(v[1] / 100, 0, 1);
        const l = std.math.clamp(v[2] / 100, 0, 1);
        const ch = (1 - @abs(2 * l - 1)) * sat;
        const x = ch * (1 - @abs(num.fmod(h, 2) - 1));
        const m = l - ch / 2;
        var rgb: [3]f32 = switch (@as(u32, @intFromFloat(@min(h, 5.999)))) {
            0 => .{ ch, x, 0 },
            1 => .{ x, ch, 0 },
            2 => .{ 0, ch, x },
            3 => .{ 0, x, ch },
            4 => .{ x, 0, ch },
            else => .{ ch, 0, x },
        };
        for (&rgb) |*c| c.* = (c.* + m) * 255;
        return Color.rgba(clamp255(rgb[0]), clamp255(rgb[1]), clamp255(rgb[2]), a8);
    }
    return null;
}

test "color" {
    const eq = std.testing.expectEqual;
    try eq(Color.rgb(255, 0, 0), parse("red").?);
    try eq(Color.rgb(0x66, 0x33, 0x99), parse("RebeccaPurple").?);
    try eq(Color.rgb(0x9a, 0xcd, 0x32), parse("yellowgreen").?);
    try eq(Color.rgb(0xf0, 0xf8, 0xff), parse("aliceblue").?);
    try eq(Color.rgba(17, 34, 51, 68), parse("#1234").?);
    try eq(Color.rgba(10, 20, 30, 128), parse("rgba(10, 20, 30, 0.5)").?);
    try eq(Color.rgba(255, 128, 0, 255), parse("rgb(100% 50.2% 0)").?);
    try eq(Color.rgba(0, 255, 0, 51), parse("hsl(120 100% 50% / 20%)").?);
    try eq(@as(?Color, null), parse("nonsense"));
    try eq(Color.rgb(255, 255, 255), parse("#fff icc-color(x, 1)").?);
}
