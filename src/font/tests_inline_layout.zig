//! Tests for inline layout features of `text.zig` that are driven by the block's style: text-indent,
//! right-to-left inline box edges, balanced wrapping of paragraphs with inline boxes.
//! Expected numbers marked "oracle" were measured with @takumi-rs/wasm 2.20.0.
const std = @import("std");
const font = @import("font.zig");
const t = std.testing;

const inter = @embedFile("testdata/Inter-Regular.ttf");
const fam: []const []const u8 = &.{"Inter"};

const Fx = struct {
    fc: font.FontCollection = .{},
    fn init() !Fx {
        var fx: Fx = .{};
        errdefer fx.fc.deinit(t.allocator);
        _ = try fx.fc.register(t.allocator, inter, .{});
        return fx;
    }
    fn deinit(fx: *Fx) void {
        fx.fc.deinit(t.allocator);
    }
    fn para(fx: *Fx, text: []const u8, opts: font.ParagraphOptions) !font.Paragraph {
        return font.Paragraph.init(t.allocator, &fx.fc, &.{.{ .text = text, .style = .{ .families = fam, .size = 16 } }}, opts);
    }
};

test "text-indent: first line, each-line, hanging, percentages, intrinsic sizes" {
    var fx = try Fx.init();
    defer fx.deinit();
    const s = "The quick brown fox jumps over the lazy dog";
    var plain = try fx.para(s, .{});
    defer plain.deinit();
    const max0 = plain.maxContentWidth();
    const min0 = plain.minContentWidth();
    {
        var p = try fx.para(s, .{ .indent = 40 });
        defer p.deinit();
        // the indent is part of the first line: max-content grows by it, min-content only when the
        // first word is the widest piece
        try t.expectEqual(max0 + 40, p.maxContentWidth());
        try t.expect(p.minContentWidth() >= min0 and p.minContentWidth() <= min0 + 40);
        var l = try p.layout(t.allocator, 150);
        defer l.deinit(t.allocator);
        var l0 = try plain.layout(t.allocator, 150);
        defer l0.deinit(t.allocator);
        try t.expectEqual(@as(f32, 40), l.lines[0].x);
        try t.expectEqual(@as(f32, 0), l.lines[1].x);
        // 150 - 40 px for the first line: "The quick" (oracle 88.5 with the ellipsis: 3 words do not fit)
        try t.expect(l.lines[0].width <= 110);
        try t.expect(l.lines.len >= l0.lines.len);
        try t.expectEqual(l.lines.len, @as(usize, p.measure(150).line_count));
    }
    {
        // negative: the first line starts left of the content box and has more room
        var p = try fx.para(s, .{ .indent = -30 });
        defer p.deinit();
        try t.expectEqual(max0 - 30, p.maxContentWidth());
        var l = try p.layout(t.allocator, 150);
        defer l.deinit(t.allocator);
        try t.expectEqual(@as(f32, -30), l.lines[0].x);
        try t.expect(l.lines[0].width > 150 - 30 and l.lines[0].width <= 180);
    }
    {
        // hanging: every line but the first; a percentage refers to the width broken at (and to nothing
        // in intrinsic sizing)
        var p = try fx.para(s, .{ .indent_pct = 0.2, .indent_hanging = true });
        defer p.deinit();
        try t.expectEqual(max0, p.maxContentWidth());
        var l = try p.layout(t.allocator, 150);
        defer l.deinit(t.allocator);
        try t.expectEqual(@as(f32, 0), l.lines[0].x);
        try t.expectEqual(@as(f32, 30), l.lines[1].x);
        try t.expectEqual(@as(f32, 30), l.lines[l.lines.len - 1].x);
    }
    {
        // each-line: also after a forced break; centred lines are centred in what the indent leaves
        var p = try fx.para("ab\ncd ef gh\nij", .{ .indent = 20, .indent_each_line = true, .white_space = .pre_line, .text_align = .center });
        defer p.deinit();
        var l = try p.layout(t.allocator, 60);
        defer l.deinit(t.allocator);
        var q = try fx.para("ab\ncd ef gh\nij", .{ .white_space = .pre_line, .text_align = .center });
        defer q.deinit();
        var l0 = try q.layout(t.allocator, 40);
        defer l0.deinit(t.allocator);
        try t.expectEqual(l0.lines[0].x + 20, l.lines[0].x);
        try t.expectEqual(l0.lines[l0.lines.len - 1].x + 20, l.lines[l.lines.len - 1].x);
    }
    {
        // right-to-left paragraphs keep the indent on the right
        var p = try fx.para("abc def", .{ .indent = 25, .direction = .rtl, .text_align = .start });
        defer p.deinit();
        var l = try p.layout(t.allocator, 200);
        defer l.deinit(t.allocator);
        try t.expectApproxEqAbs(@as(f32, 200 - 25), l.lines[0].x + l.lines[0].width, 1.0 / 64.0 + 0.001);
    }
}
