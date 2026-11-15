//! Tests of the performance paths: tight offscreen-group regions under transforms, the raw frame
//! target of the hosts, and hostile sizes for both.
const std = @import("std");
const render = @import("render.zig");
const config = @import("config.zig");
const Renderer = render.Renderer;
const testing = std.testing;

fn newRenderer() !*Renderer {
    const gpa = testing.allocator;
    const r = Renderer.create(gpa).?;
    errdefer r.destroy();
    _ = try r.registerFont(try gpa.dupe(u8, @embedFile("font/testdata/Inter-Regular.ttf")), "", 0, -1, null);
    return r;
}

/// Raw RGBA of `node` (caller frees).
fn frame(r: *Renderer, node: []const u8, opts: []const u8) ![]u8 {
    const out = try r.render(node, opts);
    return testing.allocator.dupe(u8, out);
}

fn maxDiff(a: []const u8, b: []const u8) u32 {
    var m: u32 = 0;
    for (a, b) |x, y| m = @max(m, @abs(@as(i32, x) - @as(i32, y)));
    return m;
}

const opts200 = "{\"width\":200,\"height\":160,\"format\":\"raw\"}";

test "group region: a mirrored (non-identity transform) filtered box equals the plain one" {
    const r = try newRenderer();
    defer r.destroy();
    // a 60x40 box centred in the canvas; scaleX(-1) maps it onto itself, but takes the transformed path
    const plain = "{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"width\":\"100%\",\"height\":\"100%\",\"alignItems\":\"center\",\"justifyContent\":\"center\",\"backgroundColor\":\"#204060\"},\"children\":[{\"type\":\"container\",\"style\":{\"width\":60,\"height\":40,\"backgroundColor\":\"#ffffff\",\"filter\":\"blur(5px)\"}}]}";
    const mirrored = "{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"width\":\"100%\",\"height\":\"100%\",\"alignItems\":\"center\",\"justifyContent\":\"center\",\"backgroundColor\":\"#204060\"},\"children\":[{\"type\":\"container\",\"style\":{\"width\":60,\"height\":40,\"backgroundColor\":\"#ffffff\",\"filter\":\"blur(5px)\",\"transform\":\"scaleX(-1)\"}}]}";
    const a = try frame(r, plain, opts200);
    defer testing.allocator.free(a);
    const b = try frame(r, mirrored, opts200);
    defer testing.allocator.free(b);
    try testing.expectEqualSlices(u8, a, b);
    // the blur really spread: a pixel 8 px outside the box edge is lighter than the background
    const px = (80 * 200 + (70 - 8)) * 4;
    try testing.expect(a[px] > 0x20 + 4);
}

test "group region: transformed, shadowed, filtered and text descendants are not clipped" {
    const r = try newRenderer();
    defer r.destroy();
    // The same subtree inside a group (opacity 0.999) and painted directly: a region that
    // is too tight cuts ink off, which shows as a large difference; rounding accounts for <= 2.
    const kids = "[{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":30,\"top\":30,\"width\":50,\"height\":30,\"backgroundColor\":\"#e11d48\",\"boxShadow\":\"6px 8px 12px rgba(0,0,0,0.8)\",\"transform\":\"rotate(30deg)\"}}," ++
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":120,\"top\":20,\"width\":40,\"height\":40,\"backgroundColor\":\"#22c55e\",\"filter\":\"blur(6px)\"}}," ++
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":100,\"top\":100,\"width\":30,\"height\":20,\"backgroundColor\":\"#f59e0b\",\"transform\":\"translate(25px, 10px) scale(1.5, 0.5) skewX(20deg)\",\"outline\":\"3px solid #ffffff\",\"outlineOffset\":4}}," ++
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":10,\"top\":110,\"transform\":\"rotate(-12deg)\"},\"children\":[{\"type\":\"text\",\"text\":\"Tight\",\"style\":{\"fontSize\":22,\"color\":\"#ffffff\",\"textShadow\":\"0 2px 6px #000000\"}}]}]";
    const head = "{\"type\":\"container\",\"style\":{\"width\":\"100%\",\"height\":\"100%\",\"backgroundColor\":\"#1e3a8a\"},\"children\":[{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":0,\"top\":0,\"width\":20,\"height\":20";
    const direct = head ++ "},\"children\":" ++ kids ++ "}]}";
    const grouped = head ++ ",\"opacity\":0.999},\"children\":" ++ kids ++ "}]}";
    const rotated_group = head ++ ",\"opacity\":0.999,\"transform\":\"rotate(0.001deg)\"},\"children\":" ++ kids ++ "}]}";
    const a = try frame(r, direct, opts200);
    defer testing.allocator.free(a);
    const b = try frame(r, grouped, opts200);
    defer testing.allocator.free(b);
    try testing.expect(maxDiff(a, b) <= 2);
    // the group itself transformed (by almost nothing): edges may move by a fraction of a pixel,
    // so only the bulk is compared: no large area may differ
    const c = try frame(r, rotated_group, opts200);
    defer testing.allocator.free(c);
    var far: usize = 0;
    for (a, c) |x, y| {
        if (@abs(@as(i32, x) - @as(i32, y)) > 48) far += 1;
    }
    try testing.expect(far < 200);

    // each kind of descendant alone (so that no sibling's bounds cover for it)
    const solo = [_][]const u8{
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":90,\"top\":60,\"width\":30,\"height\":30,\"backgroundColor\":\"#22c55e\",\"filter\":\"blur(6px)\"}}",
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":90,\"top\":60,\"width\":30,\"height\":30,\"backgroundColor\":\"#22c55e\",\"filter\":\"drop-shadow(14px 9px 5px #000000)\",\"transform\":\"rotate(45deg)\"}}",
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":90,\"top\":60,\"width\":40,\"height\":10,\"backgroundColor\":\"#22c55e\",\"boxShadow\":\"0 0 16px 6px #ffffff\",\"transform\":\"rotate(70deg) scale(1.6, 0.7)\"}}",
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":60,\"top\":60,\"transform\":\"skewX(-30deg) rotate(20deg)\"},\"children\":[{\"type\":\"text\",\"text\":\"Wy\",\"style\":{\"fontSize\":40,\"color\":\"#ffffff\",\"textShadow\":\"5px 5px 8px #000000\",\"WebkitTextStroke\":\"3px #ff0000\"}}]}",
        // text overflowing its box: nowrap to the right, centred to both sides, wrapped downwards; plain and transformed
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":10,\"top\":20,\"width\":20,\"height\":10},\"children\":[{\"type\":\"text\",\"text\":\"overflowing nowrap text line\",\"style\":{\"fontSize\":11,\"color\":\"#ffffff\",\"whiteSpace\":\"nowrap\"}}]}",
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":90,\"top\":20,\"width\":16,\"height\":10,\"transform\":\"rotate(25deg)\"},\"children\":[{\"type\":\"text\",\"text\":\"centred overflow\",\"style\":{\"fontSize\":11,\"color\":\"#ffffff\",\"whiteSpace\":\"nowrap\",\"textAlign\":\"center\",\"width\":16}}]}",
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":60,\"top\":10,\"width\":50,\"height\":12,\"transform\":\"scale(1.3, 0.8)\"},\"children\":[{\"type\":\"text\",\"text\":\"a paragraph that wraps onto many more lines than its box is tall\",\"style\":{\"fontSize\":11,\"color\":\"#ffffff\",\"width\":50,\"height\":12}}]}",
        "{\"type\":\"container\",\"style\":{\"position\":\"absolute\",\"left\":90,\"top\":60,\"width\":30,\"height\":30,\"transform\":\"translate(-40px, 30px)\"},\"children\":[{\"type\":\"container\",\"style\":{\"width\":30,\"height\":30,\"backgroundColor\":\"#f59e0b\",\"transform\":\"rotate(15deg)\",\"filter\":\"blur(3px)\",\"outline\":\"5px solid #ffffff\",\"outlineOffset\":6}}]}",
    };
    for (solo) |kid| {
        var nb: [2][1600]u8 = undefined;
        const d = try std.fmt.bufPrint(&nb[0], "{s}}},\"children\":[{s}]}}]}}", .{ head, kid });
        const g = try std.fmt.bufPrint(&nb[1], "{s},\"opacity\":0.999}},\"children\":[{s}]}}]}}", .{ head, kid });
        const fa = try frame(r, d, opts200);
        defer testing.allocator.free(fa);
        const fb = try frame(r, g, opts200);
        defer testing.allocator.free(fb);
        try testing.expect(maxDiff(fa, fb) <= 2);
    }
}

test "group region: hostile blur radii, degenerate transforms and extreme canvases do not crash" {
    const r = try newRenderer();
    defer r.destroy();
    const filters = [_][]const u8{ "blur(0px)", "blur(0.001px)", "blur(1e9px)", "blur(134.9px)", "blur(136px)", "blur(5px) blur(1e6px)", "drop-shadow(1e7px 1e7px 1e7px #000000)", "blur(3px) drop-shadow(0 0 1e30px red)" };
    const transforms = [_][]const u8{ "none", "rotate(33deg)", "scale(0)", "scale(1e-20)", "scale(1e18)", "matrix(1e30,1e30,-1e30,1e30,1e30,-1e30)", "rotate(1e30deg) skew(89.999deg)", "translate(1e30px, -1e30px)" };
    const sizes = [_][2]u32{ .{ 1, 1 }, .{ 37, 3 }, .{ 16384, 1 }, .{ 1, 16384 } };
    var buf: [1024]u8 = undefined;
    var obuf: [96]u8 = undefined;
    for (sizes) |sz| {
        const opts = try std.fmt.bufPrint(&obuf, "{{\"width\":{d},\"height\":{d},\"format\":\"raw\"}}", .{ sz[0], sz[1] });
        for (filters) |fl| for (transforms) |tf| {
            const node = try std.fmt.bufPrint(&buf, "{{\"type\":\"container\",\"style\":{{\"width\":\"100%\",\"height\":\"100%\",\"backgroundColor\":\"#123456\"}},\"children\":[{{\"type\":\"container\",\"style\":{{\"width\":20,\"height\":2,\"backgroundColor\":\"#ffffff\",\"opacity\":0.9,\"boxShadow\":\"0 0 1e7px 1e7px #000\",\"filter\":\"{s}\",\"transform\":\"{s}\"}},\"children\":[{{\"type\":\"container\",\"style\":{{\"width\":5,\"height\":5,\"filter\":\"{s}\",\"transform\":\"{s}\",\"backgroundColor\":\"red\"}}}}]}}]}}", .{ fl, tf, fl, tf });
            const out = r.render(node, opts) catch |e| switch (e) {
                error.Invalid, error.OutOfMemory => continue,
            };
            try testing.expectEqual(@as(usize, sz[0]) * sz[1] * 4, out.len);
        };
    }
}

const Target = struct {
    buf: []u8 = &.{},
    calls: u32 = 0,
    refuse: bool = false,

    fn alloc(ctx: ?*anyopaque, len: usize) ?[*]u8 {
        const t: *Target = @ptrCast(@alignCast(ctx.?));
        t.calls += 1;
        if (t.refuse) return null;
        t.buf = testing.allocator.alloc(u8, len) catch return null;
        @memset(t.buf, 0);
        return t.buf.ptr;
    }
};

test "raw target: the frame is painted into the host's buffer, other formats and refusals use the canvas" {
    const r = try newRenderer();
    defer r.destroy();
    const node = "{\"type\":\"container\",\"style\":{\"display\":\"flex\",\"width\":\"100%\",\"height\":\"100%\",\"backgroundImage\":\"linear-gradient(90deg, rgba(255,0,0,0.5), #0000ff)\"},\"children\":[{\"type\":\"text\",\"text\":\"raw\",\"style\":{\"fontSize\":30,\"color\":\"#ffffff\",\"opacity\":0.6}}]}";
    const want = try frame(r, node, opts200);
    defer testing.allocator.free(want);

    var t: Target = .{};
    r.raw_target = .{ .ctx = &t, .alloc = Target.alloc };
    const got = try r.render(node, opts200);
    try testing.expectEqual(@as(u32, 1), t.calls);
    try testing.expect(got.ptr == t.buf.ptr and got.len == t.buf.len);
    try testing.expectEqualSlices(u8, want, got);
    testing.allocator.free(t.buf);
    t.buf = &.{};

    // an encoded format never asks for the target
    const png = try r.render(node, "{\"width\":200,\"height\":160,\"format\":\"png\"}");
    try testing.expect(png.len > 8 and png[1] == 'P');
    try testing.expectEqual(@as(u32, 1), t.calls);

    // the host refuses: the canvas is used, same bytes
    t.refuse = true;
    const again = try r.render(node, opts200);
    try testing.expectEqual(@as(u32, 2), t.calls);
    try testing.expectEqualSlices(u8, want, again);

    // a failing render after the target was handed out leaves the buffer to the host
    t.refuse = false;
    try testing.expectError(error.Invalid, r.render("{\"type\":\"container\",\"style\":{\"width\":\"banana\"}}", opts200));
    try testing.expectEqual(@as(u32, 2), t.calls); // (fails before layout: never asked)
    const tiny = try r.render(node, "{\"width\":1,\"height\":1,\"format\":\"raw\"}");
    try testing.expectEqual(@as(usize, 4), tiny.len);
    try testing.expect(tiny.ptr == t.buf.ptr);
    testing.allocator.free(t.buf);
    r.raw_target = null;

    if (comptime config.enable_animation) {
        // animation frames are raw internally but never go to the target
        r.raw_target = .{ .ctx = &t, .alloc = Target.alloc };
        const calls = t.calls;
        _ = try r.renderAnimation("{\"scenes\":[{\"node\":{\"type\":\"container\",\"style\":{\"width\":8,\"height\":8,\"backgroundColor\":\"red\"}},\"durationMs\":100}],\"width\":8,\"height\":8,\"fps\":10}");
        try testing.expectEqual(calls, t.calls);
        r.raw_target = null;
    }
}
