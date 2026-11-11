//! Test root for src/font/color*.zig (color_example.zig imports ../raster and ../codec, so it must
//! be compiled from src/ level), and the wasm oracle/fuzz harness used by bench/probe/colorfont/.
//!
//!   zig test src/test_color.zig
//!   zig build-exe src/test_color.zig -target wasm32-freestanding -O ReleaseSafe -fno-entry -rdynamic
//!       --name colorharness   (exports below; driven by bench/probe/colorfont/oracle.mjs, fuzz.mjs)
const std = @import("std");
const builtin = @import("builtin");
const ttf = @import("font/ttf.zig");
const color = @import("font/color.zig");
const example = @import("font/color_example.zig");
const raster = @import("raster/raster.zig");
const fontmod = @import("font/font.zig");
const variations = @import("font/variations.zig");

test {
    _ = color;
    _ = @import("font/color_emoji.zig");
}

// ------------------------------------------------------------------------------------------
// wasm harness (test tooling only: global state is fine here)

const is_wasm = builtin.target.cpu.arch == .wasm32;

const H = struct {
    var font: ?ttf.Font = null;
    var ct: color.ColorTables = .{};
    var arena: std.heap.ArenaAllocator = undefined;
    var arena_ok = false;
    var out: raster.Pixmap = .empty;
    var info: [8]f32 = @splat(0);
};

fn arenaAlloc() std.mem.Allocator {
    if (!H.arena_ok) {
        H.arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
        H.arena_ok = true;
    }
    return H.arena.allocator();
}

fn cfAlloc(n: u32) callconv(.c) ?[*]u8 {
    const s = std.heap.wasm_allocator.alloc(u8, n) catch return null;
    return s.ptr;
}
fn cfFree(p: [*]u8, n: u32) callconv(.c) void {
    std.heap.wasm_allocator.free(p[0..n]);
}
/// Parses the font (bytes must stay alive). Returns 0 ok, else -1.
fn cfLoad(p: [*]const u8, n: u32) callconv(.c) i32 {
    const f = ttf.Font.init(p[0..n], 0) catch return -1;
    H.font = f;
    H.ct = color.ColorTables.init(&H.font.?);
    return 0;
}
/// Loads only colour tables from a raw sfnt directory (font may be unparseable by Font.init).
fn cfLoadTables(p: [*]const u8, n: u32) callconv(.c) void {
    H.font = null;
    H.ct = color.ColorTables.fromDirectory(p[0..n], 0);
}
/// Instances the loaded font at user-space axis values (u32 pairs: tag as big-endian u32, f32 value bits).
fn cfSetVar(p: [*]const u32, n: u32) callconv(.c) void {
    const f = &(H.font orelse return);
    var s: [8]ttf.AxisValue = undefined;
    const m = @min(n, 8);
    for (0..m) |i| {
        const tag: u32 = p[2 * i];
        s[i] = .{ .tag = .{ @truncate(tag >> 24), @truncate(tag >> 16), @truncate(tag >> 8), @truncate(tag) }, .value = @bitCast(p[2 * i + 1]) };
    }
    H.font = f.withVariations(s[0..m]);
}
fn cfGid(cp: u32) callconv(.c) u32 {
    const f = &(H.font orelse return 0);
    return f.glyphIndex(@intCast(@min(cp, 0x10FFFF)));
}
fn cfUpem() callconv(.c) u32 {
    return (H.font orelse return 0).units_per_em;
}
fn cfKind(gid: u32) callconv(.c) u32 {
    return @intFromEnum(H.ct.kind(@truncate(gid)));
}
fn cfInfo() callconv(.c) [*]f32 {
    return &H.info;
}

/// Renders `gid` (bitmap or COLR) at `size` with pen origin (ox, oy) into a w x h canvas.
/// Returns a pointer to straight RGBA, or null. info[0] = kind, info[1..] = bitmap ppem/bearings.
fn cfRender(gid: u32, size: f32, w: u32, h: u32, ox: f32, oy: f32, palette: u32, fg: u32) callconv(.c) ?[*]u8 {
    if (H.arena_ok) _ = H.arena.reset(.retain_capacity);
    const a = arenaAlloc();
    const f = &(H.font orelse return null);
    var dst = raster.Pixmap.init(a, w, h) catch return null;
    const g: u16 = @truncate(gid);
    const k = H.ct.kind(g);
    H.info = @splat(0);
    H.info[0] = @floatFromInt(@intFromEnum(k));
    const fgc: color.Rgba = .{ .r = @truncate(fg), .g = @truncate(fg >> 8), .b = @truncate(fg >> 16), .a = @truncate(fg >> 24) };
    switch (k) {
        .bitmap_png, .bitmap_other => {
            const bm = H.ct.bitmap(g, size) orelse return null;
            H.info[1] = bm.ppem;
            H.info[2] = bm.bearing_x;
            H.info[3] = bm.bearing_y;
            H.info[4] = @floatFromInt(bm.width);
            H.info[5] = @floatFromInt(bm.height);
            if (!(example.drawBitmapGlyph(a, &dst, bm, size, ox, oy, null) catch false)) return null;
        },
        .colr_v0, .colr_v1 => {
            if (!(example.drawColrGlyph(a, &dst, f, &H.ct, g, size, ox, oy, @truncate(palette), fgc, dst.bounds(), &variations.itemDelta) catch false)) return null;
        },
        .none => {
            // plain outline in the foreground colour (what takumi does for non-colour glyphs)
            var path: raster.Path = .empty;
            var sink: raster.PathSink = .{ .path = &path, .alloc = a };
            _ = ttf.emitGlyph(f, g, size, ox, oy, &sink);
            raster.fillPath(a, &dst, &path, raster.Affine.identity, .nonzero, &.{ .solid = .{ .r = fgc.r, .g = fgc.g, .b = fgc.b, .a = fgc.a } }, null) catch return null;
        },
    }
    dst.toStraightAlpha();
    H.out = dst;
    return dst.data.ptr;
}

/// Fuzz entry: walks the paint graph of `gid` with a counting painter and checks balance.
/// Returns 0 ok, 1 = error result, 2 = no colour glyph; traps (unreachable) on imbalance.
fn cfFuzz(gid: u32) callconv(.c) i32 {
    const g: u16 = @truncate(gid);
    _ = H.ct.kind(g);
    _ = H.ct.clipBox(g);
    for ([_]f32{ 0, 16, 64, 300 }) |s| if (H.ct.bitmap(g, s)) |bm| {
        if (bm.data.len > 0) std.mem.doNotOptimizeAway(bm.data[bm.data.len - 1]);
    };
    var c: Counter = .{};
    const p: color.Painter = .{ .ctx = &c, .vtable = &Counter.vt };
    const r = H.ct.paint(g, 0, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, &.{}, p);
    if (c.t != 0 or c.c != 0 or c.l != 0 or c.neg) @panic("unbalanced painter calls");
    // again with variation deltas (exercises DeltaSetIndexMap + ItemVariationStore reads)
    const coords = [_]i16{ 8000, -5000, 16384 };
    const r2 = H.ct.paintVar(g, 1, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, &coords, &variations.itemDelta, p);
    if (c.t != 0 or c.c != 0 or c.l != 0 or c.neg) @panic("unbalanced painter calls (var)");
    std.mem.doNotOptimizeAway(r2);
    if (r) |_| return 0 else |e| return if (e == error.NoColorGlyph) 2 else 1;
}

const Counter = struct {
    t: i32 = 0,
    c: i32 = 0,
    l: i32 = 0,
    neg: bool = false,
    fn s(ctx: *anyopaque) *Counter {
        return @ptrCast(@alignCast(ctx));
    }
    fn pt(ctx: *anyopaque, _: color.Affine2x3) void {
        s(ctx).t += 1;
    }
    fn ppt(ctx: *anyopaque) void {
        s(ctx).t -= 1;
        if (s(ctx).t < 0) s(ctx).neg = true;
    }
    fn cg(ctx: *anyopaque, _: u16) void {
        s(ctx).c += 1;
    }
    fn cb(ctx: *anyopaque, _: color.ClipBox) void {
        s(ctx).c += 1;
    }
    fn pc(ctx: *anyopaque) void {
        s(ctx).c -= 1;
        if (s(ctx).c < 0) s(ctx).neg = true;
    }
    fn f(_: *anyopaque, b: *const color.Brush) void {
        switch (b.*) {
            .solid => {},
            inline else => |g| for (g.stops) |st| std.mem.doNotOptimizeAway(st.offset),
        }
    }
    fn pl(ctx: *anyopaque, _: color.CompositeMode) void {
        s(ctx).l += 1;
    }
    fn ppl(ctx: *anyopaque) void {
        s(ctx).l -= 1;
        if (s(ctx).l < 0) s(ctx).neg = true;
    }
    const vt: color.Painter.VTable = .{ .push_transform = pt, .pop_transform = ppt, .push_clip_glyph = cg, .push_clip_box = cb, .pop_clip = pc, .fill = f, .push_layer = pl, .pop_layer = ppl };
};

/// Shapes UTF-8 text with the font module (GSUB ligatures: ZWJ / flag / modifier sequences) using
/// only the loaded font. Writes up to 64 (gid, advance*64) pairs to info-like buffer; returns count.
var shaped: [128]u32 = undefined;
fn cfShape(p: [*]const u8, n: u32, size: f32) callconv(.c) u32 {
    const a = arenaAlloc();
    const f = H.font orelse return 0;
    var fc: fontmod.FontCollection = .{};
    _ = fc.register(a, f.data, .{ .face_index = 0 }) catch return 0;
    const gl = fontmod.shape(a, &fc, p[0..n], .{ .size = size }) catch return 0;
    const m = @min(gl.len, 64);
    for (gl[0..m], 0..) |g, i| {
        shaped[2 * i] = g.gid;
        shaped[2 * i + 1] = @intFromFloat(@max(0, g.x_advance * 64));
    }
    return @intCast(m);
}
fn cfShaped() callconv(.c) [*]u32 {
    return &shaped;
}

/// Emoji scanner over a UTF-32 buffer (for the JS cross-check against emoji-regex).
fn cfEmojiScan(p: [*]const u32, n: u32) callconv(.c) u32 {
    var buf: [64]u21 = undefined;
    const m = @min(n, 64);
    for (0..m) |i| buf[i] = @intCast(@min(p[i], 0x10FFFF));
    const c = color.scanEmoji(buf[0..m]);
    return @as(u32, @intCast(c.len)) | (@as(u32, @intFromBool(c.emoji_presentation)) << 16);
}

comptime {
    if (is_wasm) {
        @export(&cfAlloc, .{ .name = "cf_alloc" });
        @export(&cfFree, .{ .name = "cf_free" });
        @export(&cfLoad, .{ .name = "cf_load" });
        @export(&cfLoadTables, .{ .name = "cf_load_tables" });
        @export(&cfGid, .{ .name = "cf_gid" });
        @export(&cfSetVar, .{ .name = "cf_set_var" });
        @export(&cfUpem, .{ .name = "cf_upem" });
        @export(&cfKind, .{ .name = "cf_kind" });
        @export(&cfInfo, .{ .name = "cf_info" });
        @export(&cfRender, .{ .name = "cf_render" });
        @export(&cfFuzz, .{ .name = "cf_fuzz" });
        @export(&cfEmojiScan, .{ .name = "cf_emoji_scan" });
        @export(&cfShape, .{ .name = "cf_shape" });
        @export(&cfShaped, .{ .name = "cf_shaped" });
    }
}

// ------------------------------------------------------------------------------------------
// Rendering tests: synthetic COLR v1 tables over real Inter outlines.

const inter = @embedFile("font/testdata/Inter-Regular.ttf");

fn be16(b: []u8, at: usize, v: u16) void {
    b[at] = @intCast(v >> 8);
    b[at + 1] = @intCast(v & 0xff);
}
fn be32(b: []u8, at: usize, v: u32) void {
    be16(b, at, @intCast(v >> 16));
    be16(b, at + 2, @intCast(v & 0xffff));
}

/// COLRv1: base glyph `gid` -> Composite(src = Glyph(gid, Solid fg), mode, backdrop = Glyph(gid, Linear red->blue)).
fn buildColr(buf: []u8, gid: u16, mode: color.CompositeMode) []const u8 {
    @memset(buf, 0);
    be16(buf, 0, 1);
    be32(buf, 14, 34); // BaseGlyphList
    be32(buf, 34, 1);
    be16(buf, 38, gid);
    be32(buf, 40, 10); // paint at 44 (relative to 34)
    var o: usize = 44;
    // Composite @44: src -> +8 (Glyph @52), backdrop -> +19 (Glyph @63)
    buf[o] = 32;
    buf[o + 3] = 8;
    buf[o + 4] = @intFromEnum(mode);
    buf[o + 7] = 19;
    o = 52; // Glyph(gid) -> Solid @58
    buf[o] = 10;
    buf[o + 3] = 6;
    be16(buf, o + 4, gid);
    o = 58; // Solid 0xFFFF alpha 1
    buf[o] = 2;
    be16(buf, o + 1, 0xFFFF);
    be16(buf, o + 3, 16384);
    o = 63; // Glyph(gid) -> Linear @69
    buf[o] = 10;
    buf[o + 3] = 6;
    be16(buf, o + 4, gid);
    o = 69; // Linear: colorline @85 (+16), p0 (0,0) p1 (1000,0) p2 (0,1000)
    buf[o] = 4;
    buf[o + 3] = 16;
    be16(buf, o + 8, 1000);
    be16(buf, o + 14, 1000);
    o = 85; // ColorLine pad, 2 stops: 0 -> entry 0, 1 -> entry 1
    buf[o] = 0;
    be16(buf, o + 1, 2);
    be16(buf, o + 3, 0);
    be16(buf, o + 5, 0);
    be16(buf, o + 7, 16384);
    be16(buf, o + 9, 16384);
    be16(buf, o + 11, 1);
    be16(buf, o + 13, 16384);
    return buf[0..100];
}

// CPAL v0: 1 palette, entries red, blue (BGRA)
const cpal_rb = [_]u8{ 0, 0, 0, 2, 0, 1, 0, 2, 0, 0, 0, 14, 0, 0, 0, 0, 255, 255, 255, 0, 0, 255 };

test "render COLRv1 composite over Inter outlines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try ttf.Font.init(inter, 0);
    const gid = f.glyphIndex('H');
    var buf: [128]u8 = undefined;
    for ([_]color.CompositeMode{ .src_over, .multiply, .dest_out, .hsl_luminosity }) |mode| {
        const ct: color.ColorTables = .{ .colr = buildColr(&buf, gid, mode), .cpal = &cpal_rb };
        try std.testing.expectEqual(color.Kind.colr_v1, ct.kind(gid));
        var dst = try raster.Pixmap.init(a, 64, 64);
        try std.testing.expect(try example.drawColrGlyph(a, &dst, &f, &ct, gid, 48, 4, 52, 0, .{ .r = 0, .g = 200, .b = 0, .a = 255 }, dst.bounds(), null));
        // left stem of 'H' (x ~ 10, y ~ 30) and the gap above the bar (x ~ 22, y ~ 20)
        const stem = dst.pixel(10, 30);
        const gap = dst.pixel(22, 20);
        try std.testing.expectEqual(@as(u8, 0), gap[3]);
        switch (mode) {
            .src_over => try std.testing.expect(stem[1] == 200 and stem[0] == 0),
            .multiply => try std.testing.expect(stem[1] == 0 and stem[0] == 0 and stem[3] == 255), // green * red/blue = black
            .dest_out => try std.testing.expectEqual(@as(u8, 0), stem[3]),
            else => try std.testing.expect(stem[3] == 255),
        }
    }
}

test "ColorTables.init picks the TTC face whose head matches" {
    // ttcf with 2 faces sharing nothing: face 0 = { head @140 }, face 1 = { COLR @160, head @150 }
    var d: [200]u8 = @splat(0);
    @memcpy(d[0..4], "ttcf");
    be32(&d, 8, 2);
    be32(&d, 12, 20);
    be32(&d, 16, 80);
    be16(&d, 24, 1); // face 0 dir @20, records @32
    @memcpy(d[32..36], "head");
    be32(&d, 40, 140);
    be32(&d, 44, 4);
    be16(&d, 84, 2); // face 1 dir @80, records @92
    @memcpy(d[92..96], "COLR");
    be32(&d, 100, 160);
    be32(&d, 104, 14);
    @memcpy(d[108..112], "head");
    be32(&d, 116, 150);
    be32(&d, 120, 4);
    const f1: ttf.Font = .{ .data = &d, .head = d[150..154] };
    const f0: ttf.Font = .{ .data = &d, .head = d[140..144] };
    try std.testing.expectEqual(@as(usize, 14), color.ColorTables.init(&f1).colr.len);
    try std.testing.expectEqual(@as(usize, 0), color.ColorTables.init(&f0).colr.len);
}
