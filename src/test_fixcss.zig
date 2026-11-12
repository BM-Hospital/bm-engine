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
