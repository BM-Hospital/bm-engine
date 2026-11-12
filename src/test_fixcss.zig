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
