//! fix-css regression tests (structural selectors with text nodes, white-space-only text, measure()
//! transforms, ...), driven through the public `Renderer` like takumi's own measure tests.
const std = @import("std");
const render = @import("render.zig");
const Renderer = render.Renderer;

fn newRenderer() !*Renderer {
    const gpa = std.testing.allocator;
    const r = Renderer.create(gpa) orelse return error.OutOfMemory;
    errdefer r.destroy();
    _ = try r.registerFont(try gpa.dupe(u8, @embedFile("font/testdata/Inter-Regular.ttf")), "", 0, -1);
    return r;
}

fn expectContains(hay: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, hay, needle) == null) {
        std.debug.print("expected to find\n  {s}\nin\n  {s}\n", .{ needle, hay });
        return error.TestExpectedEqual;
    }
}

test "text nodes: untagged text is no sibling for selectors; blank text generates no box" {
    const r = try newRenderer();
    defer r.destroy();
    const css = "{\"width\":100,\"height\":100,\"css\":[\".x{display:block;height:1px} .x:first-child{height:2px} .x:last-child{height:3px}\"]}";
    // untagged text elements never count as siblings (takumi matching.rs `element_from`): each is first and last
    var out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[{\"type\":\"text\",\"text\":\"a\",\"className\":\"x\"},{\"type\":\"text\",\"text\":\"b\",\"className\":\"x\"}]}", css);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out, "\"height\":3,"));
    // with a tag name they are elements
    out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[{\"type\":\"text\",\"text\":\"a\",\"tagName\":\"span\",\"className\":\"x\"},{\"type\":\"text\",\"text\":\"b\",\"tagName\":\"span\",\"className\":\"x\"}]}", css);
    try expectContains(out, "\"height\":2,");
    try expectContains(out, "\"height\":3,");
    // empty / white-space-only text elements (even display:block with a class) are dropped
    out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[{\"type\":\"text\",\"text\":\"\",\"className\":\"x\"},{\"type\":\"text\",\"text\":\"  \",\"className\":\"x\"}]}", css);
    try expectContains(out, "\"children\":[]");
}

test "measure(): transforms compose like takumi (exact quarter turns, exact f32 printing)" {
    const r = try newRenderer();
    defer r.destroy();
    const opts = "{\"width\":300,\"height\":300}";
    var out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"width\":100,\"height\":50,\"transform\":\"translateX(50px) rotate(90deg)\"}}", opts);
    try expectContains(out, "\"transform\":[0,1,-1,0,125,-25]");
    // nested: parent scale(2) about its centre, child at (5,5) inside it
    out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"width\":100,\"height\":50,\"padding\":5,\"transform\":\"scale(2)\"},\"children\":[{\"type\":\"container\",\"style\":{\"width\":10,\"height\":10}}]}", opts);
    try expectContains(out, "\"transform\":[2,0,0,2,-50,-25]");
    try expectContains(out, "\"transform\":[2,0,0,2,-40,-15]");
    // individual properties (rotate 30deg: Rust f32 sin_cos values)
    out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"width\":100,\"height\":50,\"rotate\":\"30deg\",\"transformOrigin\":\"0 0\"}}", opts);
    try expectContains(out, "\"transform\":[0.866025388240814208984375,0.5,-0.5,0.866025388240814208984375,0,0]");
}

test "renderSvg draws at device pixel ratio 1 whatever the option says (takumi RenderOptions::svg)" {
    if (!@import("config.zig").enable_render_svg) return error.SkipZigTest;
    const r = try newRenderer();
    defer r.destroy();
    const node = "{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"width\":100,\"height\":50,\"backgroundColor\":\"red\",\"padding\":10},\"children\":[{\"type\":\"text\",\"text\":\"Hi\"}]}";
    const one = try std.testing.allocator.dupe(u8, try r.renderSvg(.json, node, "{\"width\":200,\"height\":100}"));
    defer std.testing.allocator.free(one);
    const two = try r.renderSvg(.json, node, "{\"width\":200,\"height\":100,\"devicePixelRatio\":2}");
    try std.testing.expectEqualStrings(one, two);
}

test "image-rendering pixelated: nearest resize picks floor((out + 0.5) * ratio) (image-rs box kernel, support 0)" {
    const raster = @import("raster/raster.zig");
    const gpa = std.testing.allocator;
    var src = try raster.Pixmap.init(gpa, 5, 1);
    defer src.deinit(gpa);
    for (0..5) |i| @memset(src.data[i * 4 ..][0..4], @intCast(10 * (i + 1)));
    var out = try raster.resampleNearest(gpa, &src, 2, 1);
    defer out.deinit(gpa);
    // ratio 2.5: centres 1.25 -> 1, 3.75 -> 3
    try std.testing.expectEqual(@as(u8, 20), out.data[0]);
    try std.testing.expectEqual(@as(u8, 40), out.data[4]);
}

test "tw: theme variables only when defined (TwVarRef), animate-* presets" {
    const tw = @import("tw/tw.zig");
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const Stub = struct {
        fn defined(_: *const anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "--color-brand") or std.mem.eql(u8, name, "--spacing");
        }
        fn bp(_: *const anyopaque, token: []const u8) ?[]const u8 {
            return if (std.mem.eql(u8, token, "tab")) "10px" else null;
        }
    };
    const dummy: u8 = 0;
    const theme: tw.Theme = .{ .ctx = &dummy, .defined = Stub.defined, .breakpoint = Stub.bp };
    var out: std.ArrayList(tw.Declaration) = .empty;
    try tw.compile(arena.allocator(), "bg-brand bg-nope/50 p-2 tab:w-4 animate-spin", .{ .viewport_w = 100, .viewport_h = 100, .theme = &theme }, &out);
    var seen: u32 = 0;
    for (out.items) |d| {
        if (std.mem.eql(u8, d.name, "background-color")) {
            try std.testing.expectEqualStrings("var(--color-brand)", d.value);
            seen |= 1;
        } else if (std.mem.eql(u8, d.name, "padding")) {
            try std.testing.expectEqualStrings("calc(var(--spacing, 0.25rem) * 2)", d.value);
            seen |= 2;
        } else if (std.mem.eql(u8, d.name, "width")) {
            seen |= 4;
        } else if (std.mem.eql(u8, d.name, "animation")) {
            try std.testing.expectEqualStrings("1s linear infinite spin", d.value);
            seen |= 8;
        }
    }
    try std.testing.expectEqual(@as(u32, 15), seen);
    // without theme lookups: built-in values, unknown tokens dropped
    out.clearRetainingCapacity();
    try tw.compile(arena.allocator(), "bg-brand p-2 tab:w-4", .{ .viewport_w = 100, .viewport_h = 100 }, &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqualStrings("0.5rem", out.items[0].value);
}

test "cascade: named @layer < tw < unlayered; own em lengths follow an animated font-size" {
    const r = try newRenderer();
    defer r.destroy();
    const node = "{\"type\":\"container\",\"style\":{\"display\":\"flex\"},\"children\":[{\"type\":\"container\",\"className\":\"q\",\"tw\":\"w-5 h-5\"}]}";
    var out = try r.measure(node, "{\"width\":100,\"height\":100,\"css\":[\"@layer x { .q { width: 30px } }\"]}");
    try expectContains(out, "\"children\":[{\"width\":20,");
    out = try r.measure(node, "{\"width\":100,\"height\":100,\"css\":[\".q { width: 30px }\"]}");
    try expectContains(out, "\"children\":[{\"width\":30,");
    if (!@import("config.zig").enable_animation) return;
    out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"flex\"},\"children\":[{\"type\":\"container\",\"className\":\"a\"}]}", "{\"width\":100,\"height\":100,\"timeMs\":500,\"css\":[\"@keyframes fs{from{font-size:10px}to{font-size:30px}} .a{animation:fs 1000ms linear;width:1em;height:2em}\"]}");
    try expectContains(out, "\"children\":[{\"width\":20,\"height\":40,");
}
