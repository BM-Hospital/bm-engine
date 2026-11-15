//! Generated text/image sequences. Parse during the counter scope, then materialize after
//! the authored cascade so selectors never match synthetic content children.
const std = @import("std");
const dom = @import("dom.zig");
const style = @import("style/style.zig");
const render = @import("render.zig");
const json = @import("json.zig");
pub const Part = union(enum) { text: []const u8, url: []const u8, gradient: []const u8 };

test "generated images preserve mixed text, attributes and alternative-text boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: dom.Dom = .{};
    const el = try d.add(a, .{ .kind = .container, .attrs = &.{.{ .name = "data-x", .value = "label" }} }, dom.none);
    const p = (try read(a, "'before' url('a.png') attr(data-x) url(b.png) 'after' / 'alt'", &d, el, null)).?;
    try std.testing.expectEqual(@as(usize, 5), p.len);
    try std.testing.expectEqualStrings("before", p[0].text);
    try std.testing.expectEqualStrings("a.png", p[1].url);
    try std.testing.expectEqualStrings("label", p[2].text);
    try std.testing.expectEqualStrings("b.png", p[3].url);
    try std.testing.expectEqualStrings("after", p[4].text);
    const gradients = (try read(a, "'a' linear-gradient(red, blue) 'b' / 'alt'", &d, el, null)).?;
    try std.testing.expectEqual(@as(usize, 3), gradients.len);
    try std.testing.expectEqualStrings("a", gradients[0].text);
    try std.testing.expectEqualStrings("linear-gradient(red, blue)", std.mem.trim(u8, gradients[1].gradient, " \t\r\n"));
    try std.testing.expectEqualStrings("b", gradients[2].text);
}

pub fn read(a: std.mem.Allocator, value: []const u8, d: *const dom.Dom, el: u32, counters: ?dom.ContentCounters) render.Error!?[]const Part {
    var lexer = style.tokenizer.Lexer.init(value);
    var parts: std.ArrayList(Part) = .empty;
    var start: usize = 0;
    var image = false;
    while (true) {
        const before = lexer.i;
        const token = lexer.next();
        if (token.kind == .eof or token.kind == .slash) break;
        const gradient = token.isFunc("linear-gradient") or token.isFunc("radial-gradient") or token.isFunc("conic-gradient") or token.isFunc("repeating-linear-gradient") or token.isFunc("repeating-radial-gradient") or token.isFunc("repeating-conic-gradient");
        if (!token.isFunc("url") and !gradient) continue;
        const text = (try dom.contentText(a, value[start..before], d, el, counters)) orelse "";
        if (text.len > 0) try parts.append(a, .{ .text = text });
        if (gradient) {
            try parts.append(a, .{ .gradient = value[before..lexer.i] });
        } else {
            var url = std.mem.trim(u8, token.args, " \t\r\n\x0c");
            if (url.len >= 2 and (url[0] == '\'' or url[0] == '"') and url[url.len - 1] == url[0]) url = url[1 .. url.len - 1];
            try parts.append(a, .{ .url = url });
        }
        image = true;
        start = lexer.i;
    }
    if (!image) return null;
    const text = (try dom.contentText(a, value[start..], d, el, counters)) orelse "";
    if (text.len > 0) try parts.append(a, .{ .text = text });
    return parts.items;
}

pub fn generate(f: *render.Frame) render.Error!void {
    for (f.pseudos.items) |*pseudo| {
        const parts = pseudo.parts orelse continue;
        const wrapper = try f.dom.add(f.a, .{ .kind = .container, .cs = pseudo.cs }, dom.none);
        var diagnostics: style.Diagnostics = .{};
        const child = try f.a.create(render.CS);
        child.* = style.compute(f.a, &f.ctx, pseudo.cs, null, null, &diagnostics) catch return error.OutOfMemory;
        var image_style: ?*render.CS = null;
        for (parts) |part| switch (part) {
            .text => |text| {
                _ = try f.dom.add(f.a, .{ .kind = .text, .run = true, .text = text, .cs = child }, wrapper);
            },
            .url => |url| {
                if (image_style == null) {
                    const cs = try f.a.create(render.CS);
                    cs.* = child.*;
                    // A URL in a mixed generated-content list is an inline replaced
                    // item in the pseudo's own formatting context. Keeping it inline
                    // lets following text share its line instead of introducing an
                    // extra block line inside `::before` / `::after`.
                    cs.display = .@"inline";
                    cs.max_width = .{ .lp = .{ .pct = 1 } };
                    cs.max_height = .{ .lp = .{ .pct = 1 } };
                    image_style = cs;
                }
                _ = try f.dom.add(f.a, .{ .kind = .image, .generated = true, .src = url, .cs = image_style.? }, wrapper);
            },
            .gradient => |value| {
                // Takumi's anonymous_image_item: a gradient has the CSS default
                // object size, capped to its originating pseudo's content box.
                var declarations = [_]json.Member{
                    .{ .key = "backgroundImage", .value = .{ .string = value } },
                    .{ .key = "display", .value = .{ .string = "block" } },
                    .{ .key = "width", .value = .{ .number = 300 } },
                    .{ .key = "height", .value = .{ .number = 150 } },
                    .{ .key = "maxWidth", .value = .{ .string = "100%" } },
                    .{ .key = "maxHeight", .value = .{ .string = "100%" } },
                };
                const cs = try f.a.create(render.CS);
                cs.* = style.compute(f.a, &f.ctx, pseudo.cs, @as(json.Value, .{ .object = &declarations }), null, &diagnostics) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => continue,
                };
                // A non-replaced inline pseudo has no independent content box
                // against which its anonymous gradient's percentage caps resolve.
                if (pseudo.cs.display == .@"inline") {
                    cs.display = .@"inline";
                    cs.width = .{ .lp = .{} };
                    cs.height = .{ .lp = .{} };
                }
                _ = try f.dom.add(f.a, .{ .kind = .container, .generated = true, .cs = cs }, wrapper);
            },
        };
        pseudo.generated_el = wrapper;
    }
}
