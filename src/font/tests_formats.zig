//! Tests for the phase-2 font formats: CFF / CFF2 outlines, variable fonts
//! (fvar/avar/gvar/HVAR/MVAR), collections and variable-font instances in `FontCollection`.
//! Numbers marked "oracle" were measured with @takumi-rs/wasm 2.20.0 (`renderer.measure`,
//! `fontKerning: none`, `fontVariantLigatures: none`).
//!
//! Deliberately independent of text.zig / shaping: only ttf.zig, cff.zig, variations.zig and
//! collection.zig are exercised.
const std = @import("std");
const ttf = @import("ttf.zig");
const cff = @import("cff.zig");
const variations = @import("variations.zig");
const collection = @import("collection.zig");
const t = std.testing;
const Font = ttf.Font;
const FontCollection = collection.FontCollection;
const FaceId = collection.FaceId;

const geist_vf = @embedFile("testdata/Geist-VF.ttf");
const archivo_vf = @embedFile("testdata/Archivo-VF.ttf");
const geist_duo = @embedFile("testdata/GeistDuo.ttc");
const ss3 = @embedFile("testdata/SourceSans3-Regular.otf");
const ss3_vf = @embedFile("testdata/SourceSans3VF-Upright.otf");
const serif_it = @embedFile("testdata/SourceSerif4-It.otf");
const cjk_cid = @embedFile("testdata/CJKLoclTest.otf");
const inter = @embedFile("testdata/Inter-Regular.ttf");
const roboto = @embedFile("testdata/Roboto-Regular.ttf");
const z60: [60]u8 = @splat(0);

fn fileData(name: []const u8) []const u8 {
    const names = [_][]const u8{ "Geist-VF.ttf", "Archivo-VF.ttf", "SourceSans3VF-Upright.otf", "SourceSans3-Regular.otf", "SourceSerif4-It.otf" };
    const datas = [_][]const u8{ geist_vf, archivo_vf, ss3_vf, ss3, serif_it };
    for (names, datas) |n, d| if (std.mem.eql(u8, n, name)) return d;
    unreachable;
}

/// Path sink collecting counts, the control box and a position-sensitive checksum.
const Stats = struct {
    moves: u32 = 0,
    lines: u32 = 0,
    quads: u32 = 0,
    cubics: u32 = 0,
    closes: u32 = 0,
    open: bool = false,
    bad: bool = false,
    n: u32 = 0,
    sum: f64 = 0,
    min_x: f32 = std.math.inf(f32),
    min_y: f32 = std.math.inf(f32),
    max_x: f32 = -std.math.inf(f32),
    max_y: f32 = -std.math.inf(f32),

    fn pt(s: *Stats, x: f32, y: f32) void {
        if (!std.math.isFinite(x) or !std.math.isFinite(y)) s.bad = true;
        s.min_x = @min(s.min_x, x);
        s.max_x = @max(s.max_x, x);
        s.min_y = @min(s.min_y, y);
        s.max_y = @max(s.max_y, y);
        s.n += 1;
        s.sum += @as(f64, x) * @as(f64, @floatFromInt(s.n % 7 + 1)) + @as(f64, y) * @as(f64, @floatFromInt(s.n % 5 + 1));
    }
    pub fn moveTo(s: *Stats, x: f32, y: f32) void {
        if (s.open) s.bad = true;
        s.open = true;
        s.moves += 1;
        s.pt(x, y);
    }
    pub fn lineTo(s: *Stats, x: f32, y: f32) void {
        if (!s.open) s.bad = true;
        s.lines += 1;
        s.pt(x, y);
    }
    pub fn quadTo(s: *Stats, cx: f32, cy: f32, x: f32, y: f32) void {
        if (!s.open) s.bad = true;
        s.quads += 1;
        s.pt(cx, cy);
        s.pt(x, y);
    }
    pub fn cubicTo(s: *Stats, ax: f32, ay: f32, bx: f32, by: f32, x: f32, y: f32) void {
        if (!s.open) s.bad = true;
        s.cubics += 1;
        s.pt(ax, ay);
        s.pt(bx, by);
        s.pt(x, y);
    }
    pub fn close(s: *Stats) void {
        if (!s.open) s.bad = true;
        s.open = false;
        s.closes += 1;
    }
    fn ok(s: *const Stats) bool {
        return !s.bad and !s.open and s.moves == s.closes;
    }
};

fn stats(f: *const Font, cp: u21) Stats {
    var s: Stats = .{};
    _ = f.outline(f.glyphIndex(cp), &s);
    return s;
}

/// Advance sum the way HarfBuzz scales it (each advance rounded to 16.16 px).
fn textWidth(f: *const Font, text: []const u8, size: f64) f64 {
    var w: f64 = 0;
    for (text) |ch| {
        const v = @as(f64, @floatFromInt(f.advanceWidth(f.glyphIndex(ch)))) * size * 65536.0 / @as(f64, @floatFromInt(f.unitsPerEm()));
        w += @floor(v + 0.5) / 65536.0;
    }
    return w;
}

fn lineHeight(f: *const Font, size: f32) f32 {
    const lm = f.lineMetrics();
    const s = size / @as(f32, @floatFromInt(f.unitsPerEm()));
    return @floor(@as(f32, @floatFromInt(lm.ascent)) * s + 0.5) + @floor(@as(f32, @floatFromInt(lm.descent)) * s + 0.5) + @floor(@as(f32, @floatFromInt(lm.leading)) * s + 0.5);
}

fn wv(tag: *const [4]u8, v: f32) ttf.AxisValue {
    return .{ .tag = tag.*, .value = v };
}

// ------------------------------------------------------------------ fvar

test "fvar axes, named instances, normalisation with avar" {
    const g = try Font.init(geist_vf, 0);
    try t.expect(g.isVariable());
    try t.expectEqual(@as(u32, 1), g.axisCount());
    const wg = g.axis(0).?;
    try t.expectEqualStrings("wght", &wg.tag);
    try t.expectEqual(@as(f32, 300), wg.min);
    try t.expectEqual(@as(f32, 400), wg.default);
    try t.expectEqual(@as(f32, 800), wg.max);
    try t.expect(g.axis(1) == null);
    try t.expectEqual(@as(usize, 1), g.normalizedCoords().len);
    try t.expectEqual(@as(i16, 0), g.normalizedCoords()[0]);
    try t.expect(!g.varied);

    const a = try Font.init(archivo_vf, 0);
    var buf: [4]ttf.Axis = undefined;
    const axes = a.axes(&buf);
    try t.expectEqual(@as(usize, 2), axes.len);
    try t.expectEqualStrings("wght", &axes[0].tag);
    try t.expectEqualStrings("wdth", &axes[1].tag);
    try t.expectEqual(@as(f32, 62), axes[1].min);
    try t.expectEqual(@as(f32, 125), axes[1].max);
    try t.expectEqual(@as(f32, 100), a.findAxis("wdth").?.default);
    try t.expect(a.findAxis("opsz") == null);
    // Archivo has an avar table: 589 is not (589-400)/500 = 0.378 but -438/16384 on the
    // remapped axis (value cross-checked through oracle advances)
    try t.expectEqual(@as(i16, -438), a.withVariations(&.{wv("wght", 589)}).coords[0]);
    try t.expectEqual(@as(i16, -9901), a.withVariations(&.{wv("wght", 333)}).coords[0]);
    try t.expectEqual(@as(i16, 16384), a.withVariations(&.{wv("wght", 5000)}).coords[0]);
    try t.expectEqual(@as(i16, -16384), a.withVariations(&.{ wv("wght", 400), wv("wdth", 1) }).coords[1]);
    // last setting wins; unknown tags ignored; settings do not accumulate
    const in1 = a.withVariations(&.{ wv("wght", 100), wv("zzzz", 3), wv("wght", 900) });
    try t.expectEqual(@as(i16, 16384), in1.coords[0]);
    const in2 = in1.withVariations(&.{wv("wdth", 125)});
    try t.expectEqualSlices(i16, &.{ 0, 16384 }, in2.normalizedCoords());
    try t.expect(in2.varied);
    try t.expect(!in1.withVariations(&.{}).varied);
    const in3 = a.withNormalizedCoords(&.{ 100, -200, 300 });
    try t.expectEqualSlices(i16, &.{ 100, -200 }, in3.normalizedCoords());

    // named instances
    try t.expect(a.namedInstanceCount() > 4);
    var cb: [4]f32 = undefined;
    const ni = a.namedInstance(0, &cb).?;
    try t.expectEqual(@as(usize, 2), ni.coords.len);
    try t.expect(ni.coords[0] >= 100 and ni.coords[0] <= 900);
    var nb: [64]u8 = undefined;
    try t.expect(a.nameString(ni.subfamily_name_id, &nb).len > 0);
    try t.expect(a.namedInstance(a.namedInstanceCount(), &cb) == null);

    // static fonts
    const s = try Font.init(inter, 0);
    try t.expect(!s.isVariable());
    try t.expectEqual(@as(u32, 0), s.axisCount());
    try t.expect(!s.withVariations(&.{wv("wght", 900)}).varied);
    try t.expectEqual(@as(f32, 0), s.itemVariationDelta(s.gpos, 0, 0, 0));
}

// ------------------------------------------------- advances and metrics

const Oracle = struct { file: []const u8, weight: f32, stretch: f32, w100: f64, w37: f64, h: [4]f32 };
const oracle_text = "Hamburgefonstiv 0123";
// oracle: width of `oracle_text` at 100 px and 37.5 px, `line-height: normal` at 16/44/64/100 px
const oracle_rows = [_]Oracle{
    .{ .file = "Geist-VF.ttf", .weight = 300, .stretch = 100, .w100 = 1045.703125, .w37 = 392.140625, .h = .{ 21, 57, 83, 131 } },
    .{ .file = "Geist-VF.ttf", .weight = 400, .stretch = 100, .w100 = 1061.5, .w37 = 398.0625, .h = .{ 21, 57, 83, 131 } },
    .{ .file = "Geist-VF.ttf", .weight = 550, .stretch = 100, .w100 = 1099.40625, .w37 = 412.28125, .h = .{ 21, 57, 83, 131 } },
    .{ .file = "Geist-VF.ttf", .weight = 700, .stretch = 100, .w100 = 1137.703125, .w37 = 426.640625, .h = .{ 21, 57, 83, 131 } },
    .{ .file = "Geist-VF.ttf", .weight = 800, .stretch = 100, .w100 = 1162.609375, .w37 = 435.984375, .h = .{ 21, 57, 83, 131 } },
    .{ .file = "Geist-VF.ttf", .weight = 900, .stretch = 100, .w100 = 1162.609375, .w37 = 435.984375, .h = .{ 21, 57, 83, 131 } },
    .{ .file = "Archivo-VF.ttf", .weight = 100, .stretch = 100, .w100 = 966.3125, .w37 = 362.375, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "Archivo-VF.ttf", .weight = 400, .stretch = 100, .w100 = 1009.8125, .w37 = 378.6875, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "Archivo-VF.ttf", .weight = 550, .stretch = 100, .w100 = 1036.8125, .w37 = 388.8125, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "Archivo-VF.ttf", .weight = 700, .stretch = 100, .w100 = 1083.609375, .w37 = 406.359375, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "Archivo-VF.ttf", .weight = 900, .stretch = 100, .w100 = 1216.703125, .w37 = 456.265625, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "Archivo-VF.ttf", .weight = 400, .stretch = 62, .w100 = 682.5, .w37 = 255.9375, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "Archivo-VF.ttf", .weight = 550, .stretch = 80, .w100 = 863.3125, .w37 = 323.75, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "Archivo-VF.ttf", .weight = 700, .stretch = 125, .w100 = 1367, .w37 = 512.625, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "Archivo-VF.ttf", .weight = 300, .stretch = 75, .w100 = 777.90625, .w37 = 291.71875, .h = .{ 17, 48, 69, 109 } },
    .{ .file = "SourceSans3VF-Upright.otf", .weight = 200, .stretch = 100, .w100 = 899.609375, .w37 = 337.359375, .h = .{ 21, 58, 85, 133 } },
    .{ .file = "SourceSans3VF-Upright.otf", .weight = 400, .stretch = 100, .w100 = 946.8125, .w37 = 355.0625, .h = .{ 21, 58, 85, 133 } },
    .{ .file = "SourceSans3VF-Upright.otf", .weight = 550, .stretch = 100, .w100 = 969.3125, .w37 = 363.5, .h = .{ 21, 58, 85, 133 } },
    .{ .file = "SourceSans3VF-Upright.otf", .weight = 700, .stretch = 100, .w100 = 1005.40625, .w37 = 377.03125, .h = .{ 21, 58, 85, 133 } },
    .{ .file = "SourceSans3VF-Upright.otf", .weight = 900, .stretch = 100, .w100 = 1028, .w37 = 385.5, .h = .{ 21, 58, 85, 133 } },
    .{ .file = "SourceSans3-Regular.otf", .weight = 400, .stretch = 100, .w100 = 946.8125, .w37 = 355.0625, .h = .{ 21, 58, 85, 133 } },
    .{ .file = "SourceSerif4-It.otf", .weight = 400, .stretch = 100, .w100 = 955.8125, .w37 = 358.4375, .h = .{ 22, 61, 87, 138 } },
};

test "instance advances (HVAR) and line heights vs oracle" {
    for (oracle_rows) |row| {
        const base = try Font.init(fileData(row.file), 0);
        const f = base.withVariations(&.{ wv("wght", row.weight), wv("wdth", row.stretch) });
        // the oracle's layout widths are quantised to 1/64 px
        t.expectApproxEqAbs(row.w100, textWidth(&f, oracle_text, 100), 0.02) catch |e| {
            std.debug.print("{s} wght {d} wdth {d}: got {d}\n", .{ row.file, row.weight, row.stretch, textWidth(&f, oracle_text, 100) });
            return e;
        };
        try t.expectApproxEqAbs(row.w37, textWidth(&f, oracle_text, 37.5), 0.02);
        for ([_]f32{ 16, 44, 64, 100 }, row.h) |size, h| try t.expectEqual(h, lineHeight(&f, size));
    }
}

test "MVAR metric deltas vs oracle (x-height through `ex`)" {
    const g = try Font.init(geist_vf, 0);
    try t.expectEqual(@as(i16, 530), g.xHeight());
    // oracle: 10ex at 100 px = 530 / 533 / 538 for wght 300 / 550 / 800
    try t.expectEqual(@as(i16, 530), g.withVariations(&.{wv("wght", 300)}).xHeight());
    try t.expectEqual(@as(i16, 533), g.withVariations(&.{wv("wght", 550)}).xHeight());
    try t.expectEqual(@as(i16, 538), g.withVariations(&.{wv("wght", 800)}).xHeight());
    const s = try Font.init(ss3_vf, 0);
    // oracle: 478 / 490 / 500 for wght 200 / 550 / 900
    try t.expectEqual(@as(i16, 478), s.withVariations(&.{wv("wght", 200)}).xHeight());
    try t.expectEqual(@as(i16, 490), s.withVariations(&.{wv("wght", 550)}).xHeight());
    try t.expectEqual(@as(i16, 500), s.withVariations(&.{wv("wght", 900)}).xHeight());
    // the other MVAR-backed accessors stay sane on instances
    const b = g.withVariations(&.{wv("wght", 800)});
    try t.expectEqual(@as(i16, 710), b.capHeight());
    try t.expect(b.underlineThickness() > 0 and b.strikeoutThickness() > 0);
    const lm = b.lineMetrics();
    try t.expectEqual(@as(i32, 1005), lm.ascent);
    try t.expectEqual(@as(i32, 295), lm.descent);
}

test "HVAR and gvar phantom points agree" {
    // Without HVAR the advance delta comes from the glyph's phantom points in gvar; the
    // oracle matched both paths exactly (HVAR table renamed in the font), here we check they
    // agree with each other: equal up to the rounding of x.5 deltas.
    const fonts = [_][]const u8{ geist_vf, archivo_vf };
    const settings = [_][]const ttf.AxisValue{
        &.{wv("wght", 800)}, &.{wv("wght", 300)}, &.{wv("wght", 550)}, &.{ wv("wght", 333), wv("wdth", 70) }, &.{ wv("wght", 777), wv("wdth", 125) },
    };
    for (fonts) |d| {
        const base = try Font.init(d, 0);
        for (settings) |set| {
            const with = base.withVariations(set);
            if (!with.varied) continue;
            var without = with;
            without.hvar = &.{};
            var exact: u32 = 0;
            var changed: u32 = 0;
            var gid: u32 = 0;
            while (gid < with.numGlyphs()) : (gid += 1) {
                const a: i32 = with.advanceWidth(@intCast(gid));
                const b: i32 = without.advanceWidth(@intCast(gid));
                try t.expect(@abs(a - b) <= 1);
                if (a == b) exact += 1;
                if (a != base.advanceWidth(@intCast(gid))) changed += 1;
            }
            try t.expect(exact * 100 >= @as(u32, with.numGlyphs()) * 97);
            try t.expect(changed * 2 > with.numGlyphs());
        }
    }
}

// --------------------------------------------------------- glyf + gvar

test "gvar outlines: default instance, extremes, bounds, emitGlyph" {
    const g = try Font.init(geist_vf, 0);
    const base_o = stats(&g, 'O');
    try t.expect(base_o.ok() and base_o.moves == 2 and base_o.quads > 8 and base_o.cubics == 0);
    // the default instance through withVariations takes the static path: identical output
    const def = g.withVariations(&.{wv("wght", 400)});
    try t.expect(!def.varied);
    try t.expectEqual(base_o.sum, stats(&def, 'O').sum);

    const light = g.withVariations(&.{wv("wght", 300)});
    const bold = g.withVariations(&.{wv("wght", 800)});
    for ("OHamburgefonstiv@&%8gQ") |ch| {
        const s0 = stats(&g, ch);
        const sl = stats(&light, ch);
        const sb = stats(&bold, ch);
        try t.expect(sl.ok() and sb.ok());
        // same topology, different coordinates
        try t.expectEqual(s0.moves, sl.moves);
        try t.expectEqual(s0.quads + s0.lines, sb.quads + sb.lines);
        try t.expect(sl.sum != s0.sum and sb.sum != s0.sum);
        // glyphBounds of an instance = control box of its outline
        const gid = g.glyphIndex(ch);
        const bb = bold.glyphBounds(gid);
        try t.expect(@as(f32, @floatFromInt(bb.x_min)) <= sb.min_x and @as(f32, @floatFromInt(bb.x_max)) >= sb.max_x);
        try t.expect(@as(f32, @floatFromInt(bb.y_min)) <= sb.min_y and @as(f32, @floatFromInt(bb.y_max)) >= sb.max_y);
        try t.expect(@as(f32, @floatFromInt(bb.x_max)) - sb.max_x < 1.001);
        // ink stays inside the advance box (Geist has positive side bearings on these)
        try t.expect(sb.min_x >= 0 and sb.max_x <= @as(f32, @floatFromInt(bold.advanceWidth(gid))));
    }
    // heavier = wider stems: the counter of 'O' shrinks, the outer contour barely moves
    const ol = light.glyphBounds(g.glyphIndex('O'));
    const ob = bold.glyphBounds(g.glyphIndex('O'));
    try t.expect(ob.x_max - ob.x_min > ol.x_max - ol.x_min);
    try t.expect(@abs(ob.y_max - ol.y_max) < 12);
    // interpolation is linear between the masters of a 1-axis font: mid = (default + bold) / 2
    const mid = g.withVariations(&.{wv("wght", 600)});
    for ("OagR") |ch| {
        const a = stats(&g, ch);
        const b = stats(&bold, ch);
        const m = stats(&mid, ch);
        try t.expectApproxEqAbs((a.sum + b.sum) * 0.5, m.sum, 0.05 * @as(f64, @floatFromInt(a.n)));
        try t.expectApproxEqAbs((a.max_x + b.max_x) * 0.5, m.max_x, 0.01);
    }

    // composites: component offsets move with the variation (Archivo 'é' = e + acute)
    const a = try Font.init(archivo_vf, 0);
    const wide = a.withVariations(&.{ wv("wght", 900), wv("wdth", 125) });
    const narrow = a.withVariations(&.{ wv("wght", 100), wv("wdth", 62) });
    for ([_]u21{ 0xe9, 0x1ec7, 0xc5, 0xf1 }) |cp| {
        const sw = stats(&wide, cp);
        const sn = stats(&narrow, cp);
        const s0 = stats(&a, cp);
        try t.expect(sw.ok() and sn.ok() and s0.ok());
        try t.expectEqual(s0.moves, sw.moves);
        try t.expectEqual(s0.moves, sn.moves);
        try t.expect(sw.max_x - sw.min_x > sn.max_x - sn.min_x);
        // the accent stays above the base letter and inside the advance
        const gid = a.glyphIndex(cp);
        try t.expect(sw.max_x <= @as(f32, @floatFromInt(wide.advanceWidth(gid))) + 1);
        try t.expect(sn.max_x <= @as(f32, @floatFromInt(narrow.advanceWidth(gid))) + 1);
        try t.expect(sw.max_y > @as(f32, @floatFromInt(wide.xHeight())));
    }

    // emitGlyph: 26.6 grid, y flipped
    var e: Stats = .{};
    try t.expect(ttf.emitGlyph(&bold, bold.glyphIndex('O'), 64, 10, 100, &e));
    try t.expect(e.ok());
    try t.expectApproxEqAbs(@as(f32, 100) - @as(f32, @floatFromInt(ob.y_max)) * 0.064, e.min_y, 0.02);
    try t.expectEqual(@floor(e.min_x * 64), e.min_x * 64);
    try t.expectEqual(@floor(e.max_y * 64), e.max_y * 64);
}

test "scale26_6 mirrors FreeType's 16.16 scale" {
    try t.expectEqual(@as(f32, 0.5), ttf.scale26_6(16, 2048));
    // 6400 / 1000 in 16.16 is 419430 (6.39999...), not 6.4
    try t.expectEqual(@as(f32, 419430.0 / 65536.0), ttf.scale26_6(100, 1000));
    // 13.33 px -> 853/64 px per em
    try t.expectApproxEqAbs(@as(f32, 853.0 / 1000.0), ttf.scale26_6(13.33, 1000), 1e-5);
    try t.expectEqual(@as(f32, 0), ttf.scale26_6(-5, 1000));
    try t.expectEqual(@as(f32, 0), ttf.scale26_6(std.math.nan(f32), 1000));
    try t.expect(ttf.scale26_6(1e30, 0) == 0);
}

// ------------------------------------------------------------ CFF / CFF2

test "CFF: parse, outlines, bounds, advances" {
    const f = try Font.init(ss3, 0);
    try t.expect(f.cff.len != 0 and !f.cff_info.cff2 and f.glyf.len == 0);
    try t.expectEqual(@as(u16, 1000), f.unitsPerEm());
    var nb: [64]u8 = undefined;
    try t.expectEqualStrings("Source Sans 3", f.familyName(&nb));
    try t.expectEqual(@as(u32, f.numGlyphs()), cff.glyphCount(f.cff, f.cff_info));
    try t.expectEqual(@as(u32, 0), f.cff_info.fdarray);
    try t.expect(f.cff_info.private_len != 0);

    const o = stats(&f, 'O');
    try t.expect(o.ok());
    try t.expectEqual(@as(u32, 2), o.moves);
    try t.expect(o.cubics >= 8 and o.quads == 0);
    const h = stats(&f, 'H');
    try t.expect(h.ok() and h.moves == 1 and h.cubics == 0 and h.lines == 11);
    try t.expectEqual(@as(f32, 0), h.min_y);
    try t.expect(h.max_y > 640 and h.max_y <= @as(f32, @floatFromInt(f.capHeight())));
    // coordinates are whole font units
    try t.expectEqual(@floor(o.sum), o.sum);
    // bounds = control box, sits inside the advance
    const bb = f.glyphBounds(f.glyphIndex('O'));
    try t.expectEqual(o.min_x, @as(f32, @floatFromInt(bb.x_min)));
    try t.expectEqual(o.max_y, @as(f32, @floatFromInt(bb.y_max)));
    try t.expect(bb.x_min > 0 and bb.x_max < f.advanceWidth(f.glyphIndex('O')) and bb.y_min < 0 and bb.y_max > 660);
    // space and out-of-range glyphs have no outline
    var e: Stats = .{};
    try t.expect(!f.outline(f.glyphIndex(' '), &e));
    try t.expect(!f.outline(0xffff, &e));
    try t.expectEqual(@as(u32, 0), e.n);
    try t.expectEqual(ttf.Bounds{}, f.glyphBounds(f.glyphIndex(' ')));
    // every glyph interprets cleanly (subroutines, hint masks, flex ...)
    var gid: u32 = 0;
    var with_outline: u32 = 0;
    while (gid < f.numGlyphs()) : (gid += 1) {
        var s: Stats = .{};
        if (f.outline(@intCast(gid), &s)) with_outline += 1;
        try t.expect(s.ok());
        try t.expect(s.n < 4000);
    }
    try t.expect(with_outline * 10 > @as(u32, f.numGlyphs()) * 9);

    // italic serif: same checks on a second CFF font
    const it = try Font.init(serif_it, 0);
    try t.expect(it.isItalic());
    gid = 0;
    while (gid < it.numGlyphs()) : (gid += 1) {
        var s: Stats = .{};
        _ = it.outline(@intCast(gid), &s);
        try t.expect(s.ok());
    }
    // emitGlyph on a CFF font
    var es: Stats = .{};
    try t.expect(ttf.emitGlyph(&f, f.glyphIndex('O'), 100, 0, 0, &es));
    try t.expectApproxEqAbs(-@as(f32, @floatFromInt(bb.y_max)) * 0.1, es.min_y, 0.02);
}

test "CFF2: blend at variation coordinates" {
    const f = try Font.init(ss3_vf, 0);
    try t.expect(f.cff_info.cff2 and f.cff_info.vstore != 0 and f.cff_info.fdarray != 0);
    try t.expectEqual(@as(u32, f.numGlyphs()), cff.glyphCount(f.cff, f.cff_info));
    const wg = f.findAxis("wght").?;
    try t.expectEqual(@as(f32, 200), wg.min);
    try t.expectEqual(@as(f32, 900), wg.max);
    const reg = f.withVariations(&.{wv("wght", 400)});
    const black = f.withVariations(&.{wv("wght", 900)});
    // the static Source Sans 3 Regular is the wght=400 instance of the variable font:
    // identical advances, near-identical outlines
    const st = try Font.init(ss3, 0);
    for ("Hamburgefonstiv08@") |ch| {
        try t.expectEqual(st.advanceWidth(st.glyphIndex(ch)), reg.advanceWidth(reg.glyphIndex(ch)));
        const a = stats(&st, ch);
        const b = stats(&reg, ch);
        try t.expect(b.ok());
        try t.expectApproxEqAbs(a.min_x, b.min_x, 2);
        try t.expectApproxEqAbs(a.max_x, b.max_x, 2);
        try t.expectApproxEqAbs(a.max_y, b.max_y, 2);
        const l = stats(&f, ch);
        const k = stats(&black, ch);
        try t.expect(l.ok() and k.ok());
        try t.expectEqual(l.moves, k.moves);
        try t.expectEqual(l.cubics + l.lines, k.cubics + k.lines);
        try t.expect(k.sum != l.sum);
        try t.expectEqual(@floor(k.sum), k.sum);
    }
    // stems get heavier
    const hl = stats(&f, 'l');
    const hk = stats(&black, 'l');
    try t.expect(hk.max_x - hk.min_x > 2 * (hl.max_x - hl.min_x));
    var gid: u32 = 0;
    while (gid < f.numGlyphs()) : (gid += 37) {
        var s: Stats = .{};
        _ = black.outline(@intCast(gid), &s);
        try t.expect(s.ok());
    }
}

test "CID-keyed CFF: FDArray / FDSelect" {
    const f = try Font.init(cjk_cid, 0);
    try t.expect(f.cff.len != 0 and f.cff_info.fdarray != 0 and f.cff_info.fdselect != 0);
    var any: u32 = 0;
    var gid: u32 = 0;
    while (gid < f.numGlyphs()) : (gid += 1) {
        var s: Stats = .{};
        if (f.outline(@intCast(gid), &s)) any += 1;
        try t.expect(s.ok());
    }
    try t.expect(any >= 4);
    const s = stats(&f, 0x76f4); // 直
    try t.expect(s.ok() and s.moves >= 1 and s.n > 8);
    try t.expect(s.max_y > 500 and s.min_y < 100 and s.max_x <= @as(f32, @floatFromInt(f.advanceWidth(f.glyphIndex(0x76f4)))));
}

// ------------------------------------------------------------ collection

test "collections: every face registered, families listing, unregisterFamily" {
    try t.expectEqual(@as(u32, 2), ttf.faceCount(geist_duo));
    try t.expectEqual(@as(u32, 1), ttf.faceCount(inter));
    try t.expectEqual(@as(u32, 0), ttf.faceCount("ttcf"));
    var fc: FontCollection = .{};
    defer fc.deinit(t.allocator);
    const r = try fc.registerAll(t.allocator, geist_duo, .{});
    try t.expectEqual(@as(FaceId, 0), r.first);
    try t.expectEqual(@as(u16, 2), r.count);
    try t.expectEqualStrings("Geist", fc.face(0).family);
    try t.expectEqualStrings("Geist Mono", fc.face(1).family);
    try t.expectEqual(@as(u32, 1), fc.face(1).index);
    // one face only on request
    try t.expectEqual(@as(FaceId, 2), try fc.register(t.allocator, geist_duo, .{ .face_index = 1, .family = "Mono2" }));
    try t.expectEqual(@as(usize, 3), fc.count());
    try t.expectError(error.InvalidFont, fc.register(t.allocator, geist_duo, .{ .face_index = 2 }));
    _ = try fc.register(t.allocator, ss3, .{});
    _ = try fc.register(t.allocator, archivo_vf, .{});
    _ = try fc.register(t.allocator, serif_it, .{ .family = "source sans 3" });
    try t.expectError(error.Woff2Container, fc.register(t.allocator, "wOF2" ++ z60, .{}));
    try t.expectEqual(@as(usize, 6), fc.count());

    const fams = try fc.families(t.allocator);
    defer FontCollection.freeFamilies(t.allocator, fams);
    try t.expectEqual(@as(usize, 5), fams.len);
    try t.expectEqualStrings("Geist", fams[0].name);
    try t.expectEqualStrings("Source Sans 3", fams[3].name);
    try t.expectEqual(@as(usize, 2), fams[3].faces.len);
    try t.expect(!fams[3].faces[0].italic and fams[3].faces[1].italic);
    try t.expectEqual(@as(FaceId, 5), fams[3].faces[1].id);
    try t.expectEqualStrings("Archivo", fams[4].name);
    const af = fams[4].faces[0];
    try t.expect(af.variable);
    try t.expectEqual(@as(u16, 100), af.weight_min);
    try t.expectEqual(@as(u16, 900), af.weight_max);
    try t.expectEqual(@as(f32, 100), af.width);

    var buf: [8]FaceId = undefined;
    try t.expectEqual(@as(FaceId, 5), fc.match(&.{"Source Sans 3"}, 400, true, &buf)[0]);
    try t.expectEqual(@as(FaceId, 3), fc.match(&.{"Source Sans 3"}, 400, false, &buf)[0]);
    try t.expect(fc.unregisterFamily(t.allocator, "SOURCE SANS 3"));
    try t.expect(!fc.unregisterFamily(t.allocator, "Source Sans 3"));
    try t.expect(!fc.face(3).active and !fc.face(5).active);
    const fams2 = try fc.families(t.allocator);
    defer FontCollection.freeFamilies(t.allocator, fams2);
    try t.expectEqual(@as(usize, 4), fams2.len);
    try t.expectEqual(@as(FaceId, 0), fc.match(&.{"Source Sans 3"}, 400, false, &buf)[0]);
}

test "variable font instances through match / matchEx" {
    var fc: FontCollection = .{};
    defer fc.deinit(t.allocator);
    const gid = try fc.register(t.allocator, geist_vf, .{});
    const aid = try fc.register(t.allocator, archivo_vf, .{});
    const sid = try fc.register(t.allocator, roboto, .{});
    try t.expect(fc.face(gid).variable and fc.face(aid).variable and !fc.face(sid).variable);
    try t.expectEqual(@as(u16, 400), fc.face(gid).weight);
    try t.expectEqual(@as(u16, 300), fc.face(gid).weight_min);
    try t.expectEqual(@as(u16, 800), fc.face(gid).weight_max);
    try t.expectEqual(@as(f32, 62), fc.face(aid).width_min);

    var buf: [8]FaceId = undefined;
    // default instance = the registered face itself
    // (Archivo's default instance is wght 600, so its fallback entry is an instance at 400)
    const d = fc.match(&.{"Geist"}, 400, false, &buf);
    try t.expectEqual(@as(usize, 3), d.len);
    try t.expectEqual(gid, d[0]);
    try t.expectEqual(aid, fc.face(d[1]).base);
    try t.expectEqual(@as(u16, 400), fc.face(d[1]).weight);
    try t.expectEqual(sid, d[2]);
    try t.expectEqual(aid, fc.match(&.{"Archivo"}, 600, false, &buf)[0]);
    try t.expectEqual(@as(u16, 600), fc.face(aid).weight);
    // weight 700 -> an instance reporting 700 (no synthetic bold), cached
    const m = fc.match(&.{"geist"}, 700, false, &buf);
    const b700 = m[0];
    try t.expect(b700 >= collection.instance_base);
    try t.expect(m[1] >= collection.instance_base); // Archivo at 700 as fallback
    try t.expectEqual(sid, m[2]);
    try t.expectEqual(@as(u16, 700), fc.face(b700).weight);
    try t.expectEqualStrings("Geist", fc.face(b700).family);
    try t.expect(!fc.face(b700).variable and fc.face(b700).active);
    try t.expectEqual(b700, fc.match(&.{"Geist"}, 700, false, &buf)[0]);
    const f700 = fc.font(b700);
    try t.expect(f700.varied);
    try t.expectEqual(@as(i16, 12288), f700.normalizedCoords()[0]);
    const direct = fc.font(gid).withVariations(&.{wv("wght", 700)});
    try t.expectEqual(textWidth(&direct, oracle_text, 100), textWidth(f700, oracle_text, 100));
    try t.expectApproxEqAbs(@as(f64, 1137.703125), textWidth(f700, oracle_text, 100), 0.02); // oracle
    // weights beyond the range clamp the axis; Geist reaches past 400, so the instance keeps
    // the requested weight and the painter does not add synthetic bold (Blink behaviour)
    const b900 = fc.match(&.{"Geist"}, 900, false, &buf)[0];
    try t.expectEqual(@as(u16, 900), fc.face(b900).weight);
    try t.expectEqual(@as(i16, 16384), fc.font(b900).normalizedCoords()[0]);
    const l100 = fc.match(&.{"Geist"}, 100, false, &buf)[0];
    try t.expectEqual(@as(u16, 300), fc.face(l100).weight);
    try t.expectEqual(@as(i16, -16384), fc.font(l100).normalizedCoords()[0]);

    // stretch -> wdth, variation settings override, opsz ignored without the axis
    const cond = fc.matchEx(.{ .families = &.{"Archivo"}, .weight = 400, .stretch = 62 }, &buf)[0];
    try t.expectEqual(@as(f32, 62), fc.face(cond).width);
    try t.expectApproxEqAbs(@as(f64, 682.5), textWidth(fc.font(cond), oracle_text, 100), 0.02); // oracle
    // oracle: fontWeight 700 + font-variation-settings "'wght' 250, 'wdth' 80" -> 815.453125
    // for "The quick brown fox jumps over the lazy dog 0123456789" at 40 px
    const fvs = fc.matchEx(.{ .families = &.{"Archivo"}, .weight = 700, .size = 40, .variations = &.{ wv("wght", 250), wv("wdth", 80) } }, &buf)[0];
    try t.expectEqual(@as(u16, 700), fc.face(fvs).weight);
    try t.expectApproxEqAbs(@as(f64, 815.453125), textWidth(fc.font(fvs), "The quick brown fox jumps over the lazy dog 0123456789", 40), 0.02);
    // an explicit weight at registration pins the axis
    const pinned = try fc.register(t.allocator, geist_vf, .{ .family = "Pinned", .weight = 800 });
    const p = fc.match(&.{"Pinned"}, 400, false, &buf)[0];
    try t.expect(p != pinned and fc.face(p).base == pinned);
    try t.expectEqual(@as(u16, 800), fc.face(p).weight);
    try t.expectEqual(@as(i16, 16384), fc.font(p).normalizedCoords()[0]);

    // unregistering the base drops its instances; ids never dangle
    fc.unregister(t.allocator, gid);
    try t.expect(!fc.face(b700).active);
    const again = fc.match(&.{"Geist"}, 700, false, &buf);
    try t.expect(fc.face(again[0]).base == aid);
}

test "instance cache: capacity, frames, eviction" {
    var fc: FontCollection = .{};
    defer fc.deinit(t.allocator);
    const aid = try fc.register(t.allocator, archivo_vf, .{});
    var buf: [2]FaceId = undefined;
    // fill the cache within one frame: nothing is evicted, overflow falls back to the base
    var w: u16 = 0;
    var first: FaceId = 0;
    while (w < collection.max_instances + 10) : (w += 1) {
        const id = fc.match(&.{}, 401 + w, false, &buf)[0];
        if (w == 0) first = id;
        if (w < collection.max_instances) {
            try t.expect(id >= collection.instance_base);
            try t.expectEqual(401 + w, fc.face(id).weight);
        } else try t.expectEqual(aid, id);
    }
    try t.expectEqual(@as(u32, 0), fc.instanceEvictions());
    try t.expectEqual(@as(u16, 401), fc.face(first).weight);
    // next frame: old instances may be recycled, the ones used in this frame are kept
    fc.beginFrame();
    const keep = fc.match(&.{}, 420, false, &buf)[0];
    try t.expectEqual(@as(u32, 0), fc.instanceEvictions());
    const fresh = fc.match(&.{}, 777, false, &buf)[0];
    try t.expect(fresh >= collection.instance_base and fresh != keep);
    try t.expectEqual(@as(u32, 1), fc.instanceEvictions());
    try t.expectEqual(@as(u16, 777), fc.face(fresh).weight);
    try t.expectEqual(@as(u16, 420), fc.face(keep).weight);
    try t.expectEqual(keep, fc.match(&.{}, 420, false, &buf)[0]);
    // clear resets everything
    fc.clear(t.allocator);
    try t.expectEqual(@as(usize, 0), fc.count());
    _ = try fc.register(t.allocator, archivo_vf, .{});
    try t.expectEqual(collection.instance_base, fc.match(&.{}, 700, false, &buf)[0]);
}

// ------------------------------------------------------------------ fuzz

fn exercise(d: []const u8, alloc: std.mem.Allocator) !void {
    var fc: FontCollection = .{};
    defer fc.deinit(alloc);
    const r = fc.registerAll(alloc, d, .{}) catch return;
    const reqs = [_]collection.MatchRequest{
        .{},
        .{ .weight = 700, .stretch = 62, .size = 20 },
        .{ .weight = 250, .italic = true, .stretch = 150, .variations = &.{ wv("wght", 555), wv("opsz", 12), wv("slnt", -8) } },
    };
    const cps = [_]u21{ 'A', 'g', 'O', '8', 0xe9, 0x1ec7, 0x4e2d, 0x76f4, '@' };
    var fi: u16 = 0;
    while (fi < r.count) : (fi += 1) {
        const base = fc.font(r.first + fi);
        var ab: [4]ttf.Axis = undefined;
        _ = base.axes(&ab);
        var cb: [4]f32 = undefined;
        _ = base.namedInstance(0, &cb);
        _ = base.namedInstance(base.namedInstanceCount() -| 1, &cb);
        for (reqs) |rq| {
            var out: [2]FaceId = undefined;
            const ids = fc.matchEx(rq, &out);
            if (ids.len == 0) continue;
            const f = fc.font(ids[0]);
            _ = f.lineMetrics();
            _ = .{ f.xHeight(), f.capHeight(), f.underlinePosition(), f.underlineThickness(), f.strikeoutPosition(), f.strikeoutThickness() };
            _ = f.itemVariationDelta(f.hvar, ttf.rd32(f.hvar, 4), 0, 3);
            for (cps) |cp| {
                const g = f.glyphIndex(cp);
                _ = f.advanceWidth(g);
                _ = f.glyphBounds(g);
                var s: Stats = .{};
                _ = ttf.emitGlyph(f, g, 24, 3, 40, &s);
                if (s.n > 3_000_000) return error.RunawayOutline;
            }
            var g: u32 = 0;
            while (g < 0x10000) : (g += 1637) {
                var s: Stats = .{};
                _ = f.outline(@intCast(g), &s);
                _ = f.advanceWidth(@intCast(g));
                if (s.n > 3_000_000) return error.RunawayOutline;
            }
        }
    }
}

test "fuzz: truncated and corrupted CFF / variable fonts never crash" {
    const alloc = t.allocator;
    var prng = std.Random.DefaultPrng.init(0x0ddba11);
    const rnd = prng.random();
    const fonts = [_][]const u8{ geist_vf, archivo_vf, ss3, ss3_vf, serif_it, cjk_cid, geist_duo };
    for (fonts) |orig| {
        // truncation
        var cut: usize = 0;
        const step = @max(211, orig.len / 400);
        while (cut < orig.len) : (cut += step) try exercise(orig[0..cut], alloc);

        const buf = try alloc.dupe(u8, orig);
        defer alloc.free(buf);
        const f = try Font.init(orig, 0);
        const cs_off = if (f.cff.len != 0) f.cff_info.charstrings else 0;
        const tables = [_][]const u8{
            f.cff,                                              ttf.tail(f.cff, cs_off),                     ttf.tail(f.cff, f.cff_info.gsubrs),
            ttf.tail(f.cff, f.cff_info.fdarray),                ttf.tail(f.cff, f.cff_info.private_off),     ttf.tail(f.cff, f.cff_info.vstore),
            f.fvar,                                             f.avar,                                      f.gvar,
            ttf.tail(f.gvar, ttf.rd32(f.gvar, 16)),             f.hvar,                                      f.mvar,
            f.glyf,                                             f.loca,                                      f.hmtx,
            orig[0..@min(orig.len, 600)],
        };
        var iter: usize = 0;
        while (iter < 500) : (iter += 1) {
            var saved: [8]struct { off: usize, val: u8 } = undefined;
            const flips = rnd.intRangeAtMost(usize, 1, saved.len);
            for (saved[0..flips]) |*s| {
                const tb = tables[rnd.uintLessThan(usize, tables.len)];
                if (tb.len == 0) {
                    s.* = .{ .off = 0, .val = buf[0] };
                    continue;
                }
                const base = @intFromPtr(tb.ptr) - @intFromPtr(orig.ptr);
                // bias towards table headers, where offsets and counts live
                const span = if (rnd.boolean()) @min(tb.len, 96) else tb.len;
                const off = base + rnd.uintLessThan(usize, span);
                s.* = .{ .off = off, .val = buf[off] };
                buf[off] = if (rnd.boolean()) rnd.int(u8) else buf[off] ^ (@as(u8, 1) << rnd.int(u3));
            }
            try exercise(buf, alloc);
            var k = flips;
            while (k > 0) {
                k -= 1;
                buf[saved[k].off] = saved[k].val;
            }
        }
        try t.expectEqualSlices(u8, orig, buf);
    }
}
