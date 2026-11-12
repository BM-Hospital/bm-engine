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

/// The `{"width":..,"height":10,"transform":[..]` prefix of the 10 px high block in a measure() output.
fn blockRect(out: []const u8) []const u8 {
    const key = "\"height\":10,\"transform\":[";
    const at = std.mem.lastIndexOf(u8, out, key) orelse return "";
    const start = std.mem.lastIndexOf(u8, out[0..at], "{\"width\":") orelse return "";
    const end = std.mem.indexOfScalarPos(u8, out, at, ']') orelse return "";
    return out[start..end];
}

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

test "block-in-inline: a block-level child splits the inline box around it" {
    const t = try T.init();
    defer t.deinit();
    const css = "<style>div{font-family:Inter;font-size:16px} .b{display:block;height:10px} span{padding:0 4px}</style>";
    // the block is a child of the block container, the inline box is split into a part before (no end
    // edge) and a part after it (no start edge): the same geometry as writing the parts out (measure()
    // reports the split form like takumi: the text as runs of the container, the block in an anonymous box)
    const a = try t.html(css ++ "<div>x <span>y<i class=\"b\"></i>z</span> w</div>");
    defer testing.allocator.free(a);
    const b = try t.html(css ++ "<div>x <span style=\"padding-right:0\">y</span><i class=\"b\"></i><span style=\"padding-left:0\">z</span> w</div>");
    defer testing.allocator.free(b);
    try testing.expectEqualStrings(blockRect(b), blockRect(a));
    try testing.expectEqual(std.mem.count(u8, b, "{\"x\":"), std.mem.count(u8, a, "{\"x\":"));
    // (the anonymous box around the block has its height)
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, a, "\"height\":10,"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, b, "\"height\":10,"));
    // an inline box that only holds a block: no line boxes around it without inline edges
    try t.expectSameHtml(
        "<style>div{font-family:Inter} .b{display:block;height:10px}</style><div><span><i class=\"b\"></i></span></div>",
        "<style>div{font-family:Inter} .b{display:block;height:10px}</style><div><i class=\"b\"></i></div>",
    );
    // nested inline boxes, several blocks, deep nesting: no crash, finite output
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try buf.appendSlice(testing.allocator, "<div style=\"font-family:Inter\">a");
    const depth = 120;
    for (0..depth) |_| try buf.appendSlice(testing.allocator, "<span style=\"border:1px solid\">b<div>c</div>");
    for (0..depth) |_| try buf.appendSlice(testing.allocator, "d</span>");
    try buf.appendSlice(testing.allocator, "</div>");
    const out = try t.html(buf.items);
    defer testing.allocator.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "nan") == null and std.mem.indexOf(u8, out, "inf") == null);
}

test "measure(): transforms through anonymous paragraphs and block-in-inline boxes (merge of fix-css + fix-layout)" {
    const t = try T.init();
    defer t.deinit();
    const css = "<style>div{font-family:Inter;font-size:16px;width:200px;padding:3px 5px;transform:rotate(90deg)} .b{display:block;height:10px} b{display:inline-block;width:8px;height:6px}</style>";
    // every box inherits the container's quarter turn exactly once: the anonymous paragraph leaves beside
    // a block (they share the container's style), the anonymous box around the block-in-inline boxes,
    // the blocks inside it, and the atomic inlines of the split parts
    for ([_][]const u8{
        "<div>text<p>para</p>tail</div>",
        "<div>x <span>y<i class=\"b\"></i><i class=\"b\"></i>z <b></b></span> w <b></b></div>",
        "<div>x <b></b> y</div>",
    }) |src| {
        const full = try std.mem.concat(testing.allocator, u8, &.{ css, src });
        defer testing.allocator.free(full);
        const out = try t.html(full);
        defer testing.allocator.free(out);
        const all = std.mem.count(u8, out, "\"transform\":[");
        try testing.expect(all >= 2);
        try testing.expectEqual(all, std.mem.count(u8, out, "\"transform\":[0,1,-1,0,"));
    }
}
