//! Renderer-level tests of the layout fixes (display: contents, direction: rtl mapping, block-in-inline),
//! through the public `measure` API: the box tree an input makes must equal the one of an equivalent
//! input. (Included from root.zig; `zig build test`.)
const std = @import("std");
const render = @import("render.zig");
const testing = std.testing;

const T = struct {
    r: *render.Renderer,

    fn init() !T {
        const gpa = testing.allocator;
        const r = render.Renderer.create(gpa).?;
        errdefer r.destroy();
        _ = try r.registerFont(try gpa.dupe(u8, @embedFile("font/testdata/Inter-Regular.ttf")), "", 0, -1);
        return .{ .r = r };
    }
    fn deinit(t: T) void {
        t.r.destroy();
    }
    /// measure() output of a JSON node (copied: the next call reuses the result buffer).
    fn json(t: T, node: []const u8) ![]u8 {
        return testing.allocator.dupe(u8, try t.r.measure(node, "{\"width\":300,\"height\":200}"));
    }
    fn html(t: T, src: []const u8) ![]u8 {
        return testing.allocator.dupe(u8, try t.r.measureSource(.html, src, "{\"width\":300,\"height\":200}"));
    }
    fn expectSame(t: T, a: []const u8, b: []const u8) !void {
        const x = try t.json(a);
        defer testing.allocator.free(x);
        const y = try t.json(b);
        defer testing.allocator.free(y);
        try testing.expectEqualStrings(y, x);
    }
    fn expectSameHtml(t: T, a: []const u8, b: []const u8) !void {
        const x = try t.html(a);
        defer testing.allocator.free(x);
        const y = try t.html(b);
        defer testing.allocator.free(y);
        try testing.expectEqualStrings(y, x);
    }
};

const box_a = "{\"type\":\"container\",\"style\":{\"width\":30,\"height\":10}}";
const box_b = "{\"type\":\"container\",\"style\":{\"width\":50,\"height\":20,\"marginLeft\":4}}";
const box_c = "{\"type\":\"container\",\"style\":{\"width\":20,\"height\":15}}";

test "display: contents generates no box: the children are items of the parent" {
    const t = try T.init();
    defer t.deinit();
    // flex items, through two levels; the box properties of the element do nothing
    try t.expectSame(
        "{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"gap\":6},\"children\":[" ++ box_a ++
            ",{\"type\":\"container\",\"style\":{\"display\":\"contents\",\"padding\":20,\"margin\":9,\"border\":\"3px solid red\",\"width\":5,\"position\":\"relative\"},\"children\":[" ++ box_b ++
            ",{\"type\":\"container\",\"style\":{\"display\":\"contents\"},\"children\":[" ++ box_c ++ "]}]}," ++ box_a ++ "]}",
        "{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"gap\":6},\"children\":[" ++ box_a ++ "," ++ box_b ++ "," ++ box_c ++ "," ++ box_a ++ "]}",
    );
    // grid items and block children
    try t.expectSame(
        "{\"type\":\"container\",\"style\":{\"display\":\"grid\",\"gridTemplateColumns\":\"60px 1fr\"},\"children\":[{\"type\":\"container\",\"style\":{\"display\":\"contents\"},\"children\":[" ++ box_a ++ "," ++ box_b ++ "]}," ++ box_c ++ "]}",
        "{\"type\":\"container\",\"style\":{\"display\":\"grid\",\"gridTemplateColumns\":\"60px 1fr\"},\"children\":[" ++ box_a ++ "," ++ box_b ++ "," ++ box_c ++ "]}",
    );
    try t.expectSame(
        "{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[" ++ box_a ++ ",{\"type\":\"container\",\"style\":{\"display\":\"contents\"},\"children\":[" ++ box_b ++ "]},{\"type\":\"container\",\"style\":{\"display\":\"contents\"},\"children\":[]}," ++ box_c ++ "]}",
        "{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[" ++ box_a ++ "," ++ box_b ++ "," ++ box_c ++ "]}",
    );
    // inline content joins the paragraph of the parent (inherited properties still come from the element)
    try t.expectSame(
        "{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[{\"type\":\"text\",\"text\":\"a \"},{\"type\":\"container\",\"style\":{\"display\":\"contents\",\"fontSize\":30},\"children\":[{\"type\":\"text\",\"text\":\"b \"}]},{\"type\":\"text\",\"text\":\"c\"}]}",
        "{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[{\"type\":\"text\",\"text\":\"a \"},{\"type\":\"text\",\"text\":\"b \",\"style\":{\"fontSize\":30}},{\"type\":\"text\",\"text\":\"c\"}]}",
    );
    // the root element is a block after all; a replaced element generates nothing; a text element keeps
    // its text without its box
    try t.expectSame(
        "{\"type\":\"container\",\"style\":{\"display\":\"contents\",\"padding\":7},\"children\":[" ++ box_a ++ "]}",
        "{\"type\":\"container\",\"style\":{\"display\":\"block\",\"padding\":7},\"children\":[" ++ box_a ++ "]}",
    );
    try t.expectSame(
        "{\"type\":\"container\",\"style\":{\"display\":\"flex\"},\"children\":[{\"type\":\"image\",\"src\":\"x\",\"width\":40,\"height\":40,\"style\":{\"display\":\"contents\"}}," ++ box_a ++ "]}",
        "{\"type\":\"container\",\"style\":{\"display\":\"flex\"},\"children\":[{\"type\":\"image\",\"src\":\"x\",\"width\":40,\"height\":40,\"style\":{\"display\":\"none\"}}," ++ box_a ++ "]}",
    );
    try t.expectSame(
        "{\"type\":\"container\",\"style\":{\"display\":\"flex\"},\"children\":[{\"type\":\"text\",\"text\":\"hi\",\"style\":{\"display\":\"contents\",\"padding\":20,\"fontSize\":20}}]}",
        "{\"type\":\"container\",\"style\":{\"display\":\"flex\"},\"children\":[{\"type\":\"text\",\"text\":\"hi\",\"style\":{\"fontSize\":20}}]}",
    );
    // deep nesting stays within the node depth limit and does not recurse per level
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try buf.appendSlice(testing.allocator, "{\"type\":\"container\",\"style\":{\"display\":\"flex\"},\"children\":[");
    const depth = 400;
    for (0..depth) |_| try buf.appendSlice(testing.allocator, "{\"type\":\"container\",\"style\":{\"display\":\"contents\"},\"children\":[");
    try buf.appendSlice(testing.allocator, box_a);
    for (0..depth) |_| try buf.appendSlice(testing.allocator, "]}");
    try buf.appendSlice(testing.allocator, "]}");
    try t.expectSame(buf.items, "{\"type\":\"container\",\"style\":{\"display\":\"flex\"},\"children\":[" ++ box_a ++ "]}");
}
