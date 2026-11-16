//! Round-trip tests of the subsetter against bm-render's own font parser: subset, re-parse the
//! subset with `ttf.Font` and compare every kept glyph's outline and advance with the
//! original's. Also checks the sfnt checksums and that the output shrinks.
const std = @import("std");
const ttf = @import("../font/ttf.zig");
const subset_mod = @import("subset.zig");
const GlyphRemapper = subset_mod.GlyphRemapper;
const testing = std.testing;

const roboto = @embedFile("../font/testdata/Roboto-Regular.ttf");
const noto = @embedFile("../font/testdata/NotoSans-Regular.ttf");
const ss3 = @embedFile("../font/testdata/SourceSans3-Regular.otf");
const cjk_cid = @embedFile("../font/testdata/CJKLoclTest.otf");
const archivo_vf = @embedFile("../font/testdata/Archivo-VF.ttf");
const ss3_vf = @embedFile("../font/testdata/SourceSans3VF-Upright.otf");
const geist_duo = @embedFile("../font/testdata/GeistDuo.ttc");

/// Records an outline as a flat list of (verb, coords).
const Rec = struct {
    a: std.mem.Allocator,
    v: std.ArrayList(f32) = .empty,
    fn put(r: *Rec, vals: []const f32) void {
        r.v.appendSlice(r.a, vals) catch unreachable;
    }
    pub fn moveTo(r: *Rec, x: f32, y: f32) void {
        r.put(&.{ 0, x, y });
    }
    pub fn lineTo(r: *Rec, x: f32, y: f32) void {
        r.put(&.{ 1, x, y });
    }
    pub fn quadTo(r: *Rec, a: f32, b: f32, x: f32, y: f32) void {
        r.put(&.{ 2, a, b, x, y });
    }
    pub fn cubicTo(r: *Rec, a: f32, b: f32, c: f32, d: f32, x: f32, y: f32) void {
        r.put(&.{ 3, a, b, c, d, x, y });
    }
    pub fn close(r: *Rec) void {
        r.put(&.{4});
    }
};

fn outlineOf(a: std.mem.Allocator, f: *const ttf.Font, gid: u16) ![]f32 {
    var r: Rec = .{ .a = a };
    _ = f.outline(gid, &r);
    return r.v.items;
}

/// The subset has no `cmap` (as in Rust); bm-render's parser requires one, so splice in a
/// minimal format-4 cmap (test helper only).
pub fn withDummyCmap(a: std.mem.Allocator, sfnt: []const u8) ![]u8 {
    const cmap = [_]u8{
        0, 0, 0, 1, 0, 3, 0, 1, 0, 0, 0, 12, // header + (3,1) record
        0, 4, 0, 24, 0, 0, 0, 2, 0, 2, 0, 0, 0, 0, // format 4, segX2 = 2
        0xff, 0xff, 0, 0, 0xff, 0xff, 0, 1, 0, 0, // end, pad, start, delta, rangeOffset
    };
    const n: usize = std.mem.readInt(u16, sfnt[4..6], .big);
    const out = try a.alloc(u8, sfnt.len + 16 + cmap.len + 4);
    @memset(out, 0);
    @memcpy(out[0..12], sfnt[0..12]);
    std.mem.writeInt(u16, out[4..6], @intCast(n + 1), .big);
    // records: shift every offset by 16, append cmap record at the end (order is irrelevant
    // for bm-render's linear lookup)
    for (0..n) |i| {
        const src = sfnt[12 + i * 16 ..][0..16];
        const dst = out[12 + i * 16 ..][0..16];
        @memcpy(dst, src);
        std.mem.writeInt(u32, dst[8..12], std.mem.readInt(u32, src[8..12], .big) + 16, .big);
    }
    const rec = out[12 + n * 16 ..][0..16];
    @memcpy(rec[0..4], "cmap");
    const body = 12 + n * 16;
    @memcpy(out[body + 16 ..][0 .. sfnt.len - body], sfnt[body..]);
    const coff = sfnt.len + 16;
    std.mem.writeInt(u32, rec[8..12], @intCast(coff), .big);
    std.mem.writeInt(u32, rec[12..16], cmap.len, .big);
    @memcpy(out[coff..][0..cmap.len], &cmap);
    return out;
}

/// Verifies the table directory checksums and head.checkSumAdjustment.
fn checkChecksums(data: []const u8) !void {
    const n: usize = std.mem.readInt(u16, data[4..6], .big);
    var prev: u32 = 0;
    for (0..n) |i| {
        const rec = data[12 + i * 16 ..][0..16];
        const tag = std.mem.readInt(u32, rec[0..4], .big);
        try testing.expect(tag > prev); // sorted
        prev = tag;
        const off = std.mem.readInt(u32, rec[8..12], .big);
        const len = std.mem.readInt(u32, rec[12..16], .big);
        try testing.expect(off % 4 == 0);
        var t = try testing.allocator.dupe(u8, data[off..][0..len]);
        defer testing.allocator.free(t);
        if (tag == std.mem.readInt(u32, "head", .big)) @memset(t[8..12], 0);
        try testing.expectEqual(std.mem.readInt(u32, rec[4..8], .big), sum(t));
    }
    try testing.expectEqual(@as(u32, 0xB1B0AFBA), sum(data));
}

fn sum(d: []const u8) u32 {
    var s: u32 = 0;
    var i: usize = 0;
    while (i < d.len) : (i += 4) {
        var b: [4]u8 = .{ 0, 0, 0, 0 };
        const k = @min(4, d.len - i);
        @memcpy(b[0..k], d[i..][0..k]);
        s +%= std.mem.readInt(u32, &b, .big);
    }
    return s;
}

fn hasTable(data: []const u8, tag: *const [4]u8) bool {
    const n: usize = std.mem.readInt(u16, data[4..6], .big);
    for (0..n) |i| if (std.mem.eql(u8, data[12 + i * 16 ..][0..4], tag)) return true;
    return false;
}

const Expect = enum { exact, approx };

/// Subsets `data` to the glyphs of `text` (+ `extra`), re-parses and compares outlines and
/// advances of every kept glyph. Returns the subset size.
fn roundTrip(data: []const u8, index: u32, vars: []const ttf.AxisValue, text: []const u8, extra: []const u16, mode: Expect) !usize {
    const a = testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(a);
    defer arena_state.deinit();
    const ar = arena_state.allocator();

    const base = try ttf.Font.init(data, index);
    const orig = base.withVariations(vars);
    var m = try GlyphRemapper.init(a);
    defer m.deinit(a);
    var it = std.unicode.Utf8View.initUnchecked(text).iterator();
    while (it.nextCodepoint()) |cp| _ = try m.remap(a, orig.glyphIndex(cp));
    for (extra) |g| _ = try m.remap(a, g);

    var sub = try subset_mod.subsetFont(a, &orig, index, &m);
    defer sub.deinit(a);
    try checkChecksums(sub.data);
    try testing.expect(sub.data.len < data.len);
    try testing.expect(!hasTable(sub.data, "cmap"));

    const parsed_bytes = try withDummyCmap(ar, sub.data);
    const sf = try ttf.Font.init(parsed_bytes, 0);
    try testing.expect(sf.num_glyphs >= m.numGids());
    for (m.gids(), 0..) |old, new_usize| {
        const new: u16 = @intCast(new_usize);
        try testing.expectEqual(orig.advanceWidth(old), sf.advanceWidth(new));
        const o = try outlineOf(ar, &orig, old);
        const s = try outlineOf(ar, &sf, new);
        switch (mode) {
            .exact => try testing.expectEqualSlices(f32, o, s),
            .approx => {
                // instanced: integer rounding (+ cubic -> quad conversion); compare boxes
                const bo = orig.glyphBounds(old);
                const bs = sf.glyphBounds(new);
                try testing.expect(@abs(@as(i32, bo.x_min) - bs.x_min) <= 1);
                try testing.expect(@abs(@as(i32, bo.y_min) - bs.y_min) <= 1);
                try testing.expect(@abs(@as(i32, bo.x_max) - bs.x_max) <= 1);
                try testing.expect(@abs(@as(i32, bo.y_max) - bs.y_max) <= 1);
                try testing.expectEqual(o.len == 0, s.len == 0);
                // and the lsb equals xMin (required for instanced glyphs)
                if (s.len != 0) try testing.expectEqual(bs.x_min, sf.leftSideBearing(new));
            },
        }
    }
    return sub.data.len;
}

test "TrueType round trip incl. composite closure (Roboto)" {
    // 'Á' (U+00C1) is a composite in Roboto; its components are pulled in by the closure.
    const f = try ttf.Font.init(roboto, 0);
    const g = f.glyphData(f.glyphIndex(0xC1));
    try testing.expect(g.len >= 2 and std.mem.readInt(i16, g[0..2], .big) < 0);
    const size = try roundTrip(roboto, 0, &.{}, "Hi Ágé!", &.{}, .exact);
    try testing.expect(size < 12_000);
}

test "TrueType round trip (Noto Sans), unknown order" {
    _ = try roundTrip(noto, 0, &.{}, "zyx Ő ffi 123", &.{}, .exact);
}

test "TTC face index (GeistDuo face 1)" {
    _ = try roundTrip(geist_duo, 1, &.{}, "Mono 01", &.{}, .exact);
}

test "CFF (SID-keyed, subroutines) round trip: SourceSans3" {
    const size = try roundTrip(ss3, 0, &.{}, "Subroutines & ÅØ", &.{}, .exact);
    try testing.expect(size < 16_000);
}

test "CFF (CID-keyed, FDSelect) round trip: CJKLoclTest" {
    const f = try ttf.Font.init(cjk_cid, 0);
    var extra: [8]u16 = undefined;
    for (&extra, 0..) |*e, i| e.* = @intCast(@min(f.num_glyphs - 1, 1 + i * 7));
    _ = try roundTrip(cjk_cid, 0, &.{}, "", &extra, .exact);
}

test "CFF output is CID-keyed with identity charset" {
    const a = testing.allocator;
    var m = try GlyphRemapper.init(a);
    defer m.deinit(a);
    const f = try ttf.Font.init(ss3, 0);
    for ("cab") |ch| _ = try m.remap(a, f.glyphIndex(ch));
    var sub = try subset_mod.subset(a, ss3, 0, &.{}, &m);
    defer sub.deinit(a);
    try testing.expectEqual(subset_mod.Flavor.cff, sub.flavor);
    try testing.expectEqualSlices(u8, &.{ 1, 0, 4, 4 }, sub.cff[0..4]);
    try testing.expectEqualStrings("OTTO", sub.data[0..4]);
}

test "variable glyf at default location is not instanced" {
    const a = testing.allocator;
    var m = try GlyphRemapper.init(a);
    defer m.deinit(a);
    const f = try ttf.Font.init(archivo_vf, 0);
    for ("Ab") |ch| _ = try m.remap(a, f.glyphIndex(ch));
    var sub = try subset_mod.subset(a, archivo_vf, 0, &.{}, &m);
    defer sub.deinit(a);
    // hinting / original glyf bytes kept: glyph records are byte-identical
    const sf = try ttf.Font.init(try withDummyCmap(a, sub.data), 0);
    defer a.free(sf.data);
    try testing.expectEqualSlices(u8, f.glyphData(f.glyphIndex('A')), sf.glyphData(1)[0..f.glyphData(f.glyphIndex('A')).len]);
}

test "variable glyf instanced (Archivo wght 700, wdth 80)" {
    _ = try roundTrip(archivo_vf, 0, &.{ .{ .tag = "wght".*, .value = 700 }, .{ .tag = "wdth".*, .value = 80 } }, "Hamburgefonstiv Ã&", &.{}, .approx);
}

test "CFF2 converted to TrueType (SourceSans3 VF wght 300)" {
    const a = testing.allocator;
    _ = try roundTrip(ss3_vf, 0, &.{.{ .tag = "wght".*, .value = 300 }}, "Curves sg08", &.{}, .approx);
    var m = try GlyphRemapper.init(a);
    defer m.deinit(a);
    _ = try m.remap(a, 5);
    var sub = try subset_mod.subset(a, ss3_vf, 0, &.{}, &m);
    defer sub.deinit(a);
    try testing.expectEqual(subset_mod.Flavor.truetype, sub.flavor);
    try testing.expect(hasTable(sub.data, "glyf") and hasTable(sub.data, "loca") and !hasTable(sub.data, "CFF2"));
}
