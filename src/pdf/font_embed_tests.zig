//! Tests of font_embed.zig. Expected values come from takumi-pdf's own output
//! (ref/takumi/takumi-pdf/tests/fixtures-generated/font-formats-pdfa-2b.pdf and
//! font-weights.pdf); the font programs and ToUnicode CMaps of two of those fonts are kept in
//! src/pdf/testdata/ (subsets of OFL fonts).
const std = @import("std");
const ttf = @import("../font/ttf.zig");
const fe = @import("font_embed.zig");
const testing = std.testing;

const archivo_vf = @embedFile("../font/testdata/Archivo-VF.ttf");
const cjk_cid = @embedFile("../font/testdata/CJKLoclTest.otf");
const roboto = @embedFile("../font/testdata/Roboto-Regular.ttf");
const ref_archivo = @embedFile("testdata/takumi-archivo-wght700.ttf");
const ref_archivo_cmap = @embedFile("testdata/takumi-archivo-wght700-tounicode.txt");
const ref_cjk = @embedFile("testdata/takumi-cjkloclttest-cid.cff");
const ref_cjk_cmap = @embedFile("testdata/takumi-cjkloclttest-tounicode.txt");

fn glyphsOf(a: std.mem.Allocator, f: *const ttf.Font, text: []const u8) ![]fe.SpanGlyph {
    var out: std.ArrayList(fe.SpanGlyph) = .empty;
    var it = std.unicode.Utf8View.initUnchecked(text).iterator();
    var pos: u32 = 0;
    while (it.nextCodepointSlice()) |s| {
        const cp = std.unicode.utf8Decode(s) catch unreachable;
        try out.append(a, .{ .gid = f.glyphIndex(cp), .start = pos, .end = pos + @as(u32, @intCast(s.len)) });
        pos += @intCast(s.len);
    }
    return out.items;
}

test "subset tags match takumi's (SipHash-1-3 of the remapper)" {
    try testing.expectEqualStrings("YSMALC", &fe.subsetTag(&.{ 0, 13, 1, 21, 3, 11, 16, 6, 19, 23 }));
    try testing.expectEqualStrings("VXWFLU", &fe.subsetTag(&.{ 0, 1299, 1266, 1336, 1331, 1333, 1335, 1345, 1351, 1350, 1318, 1348, 1355, 1346, 1342, 1339, 1344 }));
    try testing.expectEqualStrings("TLHLUN", &fe.subsetTag(&.{ 0, 62, 337, 328, 387, 619, 420, 265, 297, 287, 293, 378, 194, 473, 466, 574, 193, 225, 372, 253, 320, 425 }));
    try testing.expectEqualStrings("RHDBEL", &fe.subsetTag(&.{ 0, 87, 100, 81, 34, 232, 71, 31, 90, 82, 3, 304 }));
}

test "Archivo at wght 700, fed run by run: identical to takumi (font-weights.pdf TLHLUN)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try ttf.Font.init(archivo_vf, 0);
    const f = base.withVariations(&.{.{ .tag = "wght".*, .value = 700 }});
    var cf = try fe.CidFont.init(testing.allocator, &f, 0);
    defer cf.deinit();
    try testing.expect(cf.isEmpty());
    for ([_][]const u8{ "Font weights", "Weight 700 · Variable axis" }) |run| {
        const gl = try glyphsOf(a, &f, run);
        try testing.expect(!fe.isReversed(gl));
        try testing.expect(!try fe.useTextSpanner(&cf, gl, run));
    }
    try testing.expectEqual(@as(u16, 22), cf.numCids());
    try testing.expectEqual(@as(?u16, 1), cf.getCid(f.glyphIndex('F')));
    try testing.expectEqualStrings("·", cf.getCodepoints(15).?);

    const d = try cf.finish(a);
    try testing.expectEqualSlices(u8, ref_archivo, d.subset.program());
    try testing.expectEqualStrings(ref_archivo_cmap, d.to_unicode);
    try testing.expectEqualStrings("TLHLUN+Archivo-SemiBold", d.base_font);
    try testing.expectEqualStrings("TLHLUN+Archivo-SemiBold", d.type0_base_font);
    try testing.expect(d.cid_font_type == .cid_font_type2 and d.font_file == .font_file2 and d.cid_to_gid_identity);
    // /DW 267 /W[0 0 651 1 1 622 2 2 613 3 3 602 4 4 342 5 5 196 6 6 798 7 7 584 9 9 607
    //   10 10 602 11 11 556 12 12 964 13 13 596 14 14 595 15 15 333 16 16 694 17 17 580
    //   18 18 380 19 19 608 21 21 572]
    try testing.expectEqual(@as(f32, 267), d.default_width);
    const want = [_][3]u16{ .{ 0, 0, 651 }, .{ 1, 1, 622 }, .{ 2, 2, 613 }, .{ 3, 3, 602 }, .{ 4, 4, 342 }, .{ 5, 5, 196 }, .{ 6, 6, 798 }, .{ 7, 7, 584 }, .{ 9, 9, 607 }, .{ 10, 10, 602 }, .{ 11, 11, 556 }, .{ 12, 12, 964 }, .{ 13, 13, 596 }, .{ 14, 14, 595 }, .{ 15, 15, 333 }, .{ 16, 16, 694 }, .{ 17, 17, 580 }, .{ 18, 18, 380 }, .{ 19, 19, 608 }, .{ 21, 21, 572 } };
    try testing.expectEqual(want.len, d.widths.len);
    for (want, d.widths) |w, got| {
        try testing.expectEqual(w[0], got.first);
        try testing.expectEqual(w[1], got.last);
        try testing.expectEqual(@as(f32, @floatFromInt(w[2])), got.width);
    }
    // /Flags 131076/FontBBox[-246 -406 1315 1092]/ItalicAngle 0/Ascent 878/Descent -210
    // /CapHeight 686/StemV 144.2
    try testing.expectEqual(@as(u32, 131076), d.flags);
    try testing.expectEqualSlices(f32, &.{ -246, -406, 1315, 1092 }, &d.bbox);
    try testing.expectEqual(@as(f32, 0), d.italic_angle);
    try testing.expectEqual(@as(f32, 878), d.ascent);
    try testing.expectEqual(@as(f32, -210), d.descent);
    try testing.expectEqual(@as(f32, 686), d.cap_height);
    try testing.expectEqual(@as(f32, 144.2), d.stem_v);
    try testing.expectEqual(@as(u32, 0), d.missing_unicode);
    try testing.expect(!d.restricted_license);
}

test "CID-keyed CFF (CJKLoclTest): identical to takumi (font-formats YSMALC)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try ttf.Font.init(cjk_cid, 0);
    var cf = try fe.CidFont.init(a, &f, 0);
    // glyphs and texts as takumi met them (the `locl` forms come from shaping)
    const gids = [_]u16{ 13, 1, 21, 3, 11, 16, 6, 19, 23 };
    const texts = [_][]const u8{ "直", " ", "骨", "今", "海", "真", "令", "説", "器" };
    for (gids, texts) |g, t| {
        const cid = try cf.addGlyph(g);
        if (cf.getCodepoints(cid) == null) try cf.setCodepoints(cid, t);
    }
    const d = try cf.finish(a);
    try testing.expectEqualSlices(u8, ref_cjk, d.subset.program());
    try testing.expectEqual(@import("subset.zig").Flavor.cff, d.subset.flavor);
    try testing.expectEqualStrings(ref_cjk_cmap, d.to_unicode);
    try testing.expectEqualStrings("YSMALC+CJKLoclTest-Regular", d.base_font);
    try testing.expectEqualStrings("YSMALC+CJKLoclTest-Regular-Identity-H", d.type0_base_font);
    try testing.expect(d.cid_font_type == .cid_font_type0 and d.font_file == .font_file3_cid_type0c and !d.cid_to_gid_identity);
    // /DW 1000/W[2 2 224]
    try testing.expectEqual(@as(f32, 1000), d.default_width);
    try testing.expectEqual(@as(usize, 1), d.widths.len);
    try testing.expectEqual(fe.WidthRun{ .first = 2, .last = 2, .width = 224 }, d.widths[0]);
    // /Flags 131076/FontBBox[-1002 -1048 2928 1808]/ItalicAngle 0/Ascent 880/Descent -120
    // /CapHeight 733/StemV 95.4
    try testing.expectEqualSlices(f32, &.{ -1002, -1048, 2928, 1808 }, &d.bbox);
    try testing.expectEqual(@as(f32, 880), d.ascent);
    try testing.expectEqual(@as(f32, -120), d.descent);
    try testing.expectEqual(@as(f32, 733), d.cap_height);
    try testing.expectEqual(@as(f32, 95.4), d.stem_v);
}

test "W grouping: equal neighbours share an entry, DW = most common width (last wins ties)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try ttf.Font.init(roboto, 0);
    var cf = try fe.CidFont.init(a, &f, 0);
    // digits share one advance in Roboto; 'i' and 'l' differ
    for ("0123iW") |ch| _ = try cf.addGlyph(f.glyphIndex(ch));
    const d = try cf.finish(a);
    const upem: f32 = @floatFromInt(f.units_per_em);
    const digit = @as(f32, @floatFromInt(f.advanceWidth(f.glyphIndex('0')))) / upem * 1000;
    try testing.expectEqual(@round(digit), d.default_width);
    // CIDs 1..4 are the digits: no /W entry for them unless the width is fractional
    for (d.widths) |w| {
        if (w.first >= 1 and w.last <= 4) try testing.expect(w.width != d.default_width);
    }
    try testing.expectEqual(@as(u32, 6), d.missing_unicode);
    try testing.expectEqualStrings("Roboto-Regular", d.base_font[7..]);
}

test "ToUnicode: multi-codepoint texts, astral planes, blocks of 100" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try ttf.Font.init(roboto, 0);
    var cf = try fe.CidFont.init(a, &f, 0);
    var g: u16 = 1;
    while (g <= 150) : (g += 1) {
        const cid = try cf.addGlyph(g);
        try cf.setCodepoints(cid, if (g == 1) "ffi" else if (g == 2) "😀" else if (g == 3) "" else "a");
    }
    const t = try fe.toUnicodeCmap(a, &cf);
    try testing.expect(std.mem.indexOf(u8, t, "<0001> <006600660069>\n") != null);
    try testing.expect(std.mem.indexOf(u8, t, "<0002> <D83DDE00>\n") != null);
    try testing.expect(std.mem.indexOf(u8, t, "<0003>") == null);
    try testing.expect(std.mem.indexOf(u8, t, "100 beginbfchar\n<0001>") != null);
    try testing.expect(std.mem.indexOf(u8, t, "49 beginbfchar\n<0066>") != null);
    try testing.expect(std.mem.endsWith(u8, t, "%%EndResource\n%%EOF"));
}

test "spanner: shared cluster -> ActualText span, per-glyph text from cmap" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try ttf.Font.init(roboto, 0);
    var cf = try fe.CidFont.init(a, &f, 0);
    // "Śa": 'S' + combining acute drawn as two glyphs of one cluster (bytes 0..3), then 'a'
    const text = "S\u{301}a";
    const gl = [_]fe.SpanGlyph{
        .{ .gid = f.glyphIndex('S'), .start = 0, .end = 3 },
        .{ .gid = f.glyphIndex(0x301), .start = 0, .end = 3 },
        .{ .gid = f.glyphIndex('a'), .start = 3, .end = 4 },
    };
    try testing.expect(try fe.useTextSpanner(&cf, &gl, text));
    var sp = try fe.GlyphSpanner.init(a, &cf, &gl, text, false, true);
    const s1 = (try sp.next()).?;
    try testing.expectEqual(@as(usize, 2), s1.count);
    try testing.expectEqual([2]u32{ 0, 3 }, s1.actual_text.?);
    const s2 = (try sp.next()).?;
    try testing.expectEqual(@as(usize, 1), s2.count);
    try testing.expectEqual(@as(?[2]u32, null), s2.actual_text);
    try testing.expectEqual(@as(?fe.Span, null), try sp.next());
    // each glyph of the cluster maps to its own character
    try testing.expectEqualStrings("S", cf.getCodepoints(cf.getCid(f.glyphIndex('S')).?).?);
    try testing.expectEqualStrings("\u{301}", cf.getCodepoints(cf.getCid(f.glyphIndex(0x301)).?).?);
    try testing.expectEqualStrings("a", cf.getCodepoints(cf.getCid(f.glyphIndex('a')).?).?);
}

test "spanner: a glyph already mapped to other text gets an ActualText span" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try ttf.Font.init(roboto, 0);
    var cf = try fe.CidFont.init(a, &f, 0);
    const sp_gid = f.glyphIndex(' ');
    const r1 = [_]fe.SpanGlyph{.{ .gid = sp_gid, .start = 0, .end = 1 }};
    try testing.expect(!try fe.useTextSpanner(&cf, &r1, " "));
    // the same glyph standing for U+00A0 later
    const r2 = [_]fe.SpanGlyph{ .{ .gid = f.glyphIndex('x'), .start = 0, .end = 1 }, .{ .gid = sp_gid, .start = 1, .end = 3 } };
    const t2 = "x\u{a0}";
    try testing.expect(try fe.useTextSpanner(&cf, &r2, t2));
    var it = try fe.GlyphSpanner.init(a, &cf, &r2, t2, false, true);
    const s1 = (try it.next()).?;
    try testing.expectEqual(@as(usize, 1), s1.count);
    try testing.expectEqual(@as(?[2]u32, null), s1.actual_text);
    const s2 = (try it.next()).?;
    try testing.expectEqual([2]u32{ 1, 3 }, s2.actual_text.?);
    try testing.expectEqualStrings(" ", cf.getCodepoints(cf.getCid(sp_gid).?).?);
}

test "overlapping spans share one range (takumi glyph.rs tests)" {
    const mk = struct {
        fn f(comptime r: []const [2]u32) [r.len]fe.SpanGlyph {
            var out: [r.len]fe.SpanGlyph = undefined;
            for (r, 0..) |x, i| out[i] = .{ .gid = 1, .start = x[0], .end = x[1] };
            return out;
        }
    }.f;
    var spans = mk(&.{ .{ 0, 3 }, .{ 0, 6 }, .{ 6, 9 }, .{ 6, 12 }, .{ 12, 13 } });
    fe.mergeOverlappingSpans(&spans);
    try testing.expectEqualSlices(fe.SpanGlyph, &mk(&.{ .{ 0, 6 }, .{ 0, 6 }, .{ 6, 12 }, .{ 6, 12 }, .{ 12, 13 } }), &spans);
    var asc = mk(&.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 } });
    fe.mergeOverlappingSpans(&asc);
    try testing.expectEqualSlices(fe.SpanGlyph, &mk(&.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 } }), &asc);
    var desc = mk(&.{ .{ 4, 6 }, .{ 2, 4 }, .{ 0, 2 } });
    fe.mergeOverlappingSpans(&desc);
    try testing.expectEqualSlices(fe.SpanGlyph, &mk(&.{ .{ 4, 6 }, .{ 2, 4 }, .{ 0, 2 } }), &desc);
}

test "reversed runs" {
    const rtl = [_]fe.SpanGlyph{ .{ .gid = 1, .start = 4, .end = 6 }, .{ .gid = 2, .start = 2, .end = 4 }, .{ .gid = 3, .start = 0, .end = 2 } };
    try testing.expect(fe.isReversed(&rtl));
    const ltr = [_]fe.SpanGlyph{ .{ .gid = 1, .start = 0, .end = 2 }, .{ .gid = 2, .start = 2, .end = 4 } };
    try testing.expect(!fe.isReversed(&ltr));
    try testing.expect(!fe.isReversed(ltr[0..1]));
}

test "font info and glyph routing" {
    const a = testing.allocator;
    const f = try ttf.Font.init(roboto, 0);
    const info = try fe.fontInfo(a, &f);
    defer a.free(info.postscript_name.?);
    try testing.expectEqualStrings("Roboto-Regular", info.postscript_name.?);
    try testing.expectEqual(@as(f32, 400), info.weight);
    try testing.expect(!info.is_monospaced);
    try testing.expectEqual(fe.Route.cid, fe.glyphRoute(roboto, 0, f.glyphIndex('A')));
    try testing.expectEqual(@as(?u21, 'A'), try (struct {
        fn cp(font: *const ttf.Font) !?u21 {
            var cf = try fe.CidFont.init(testing.allocator, font, 0);
            defer cf.deinit();
            return cf.codepoint(font.glyphIndex('A'));
        }
    }).cp(&f));
}
