//! End-to-end tests for the SVG renderer.
const std = @import("std");
const raster = @import("../raster/raster.zig");
const svg = @import("svg.zig");

const Px = [4]u8;

fn renderStr(a: std.mem.Allocator, text: []const u8, w: u32, h: u32) !raster.Pixmap {
    const doc = try svg.parse(a, text);
    var pm = try raster.Pixmap.init(a, w, h);
    var rast = raster.Rasterizer.init(a);
    defer rast.deinit();
    try svg.render(a, &rast, &doc, &pm, .{ .x = 0, .y = 0, .w = @floatFromInt(w), .h = @floatFromInt(h) }, null, .{});
    return pm;
}

fn expectPx(pm: *const raster.Pixmap, x: u32, y: u32, want: Px, tol: u8) !void {
    const got = pm.pixel(x, y);
    for (0..4) |i| {
        const d = @as(i32, got[i]) - @as(i32, want[i]);
        if (@abs(d) > tol) {
            std.debug.print("pixel ({d},{d}) = {any}, want {any}\n", .{ x, y, got, want });
            return error.TestUnexpectedResult;
        }
    }
}

test "basic shapes, viewBox scaling, css" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pm = try renderStr(a,
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><style>.b{fill:#00f}</style>
        \\<rect width="5" height="5" fill="red"/><circle class="b" cx="7.5" cy="7.5" r="2"/>
        \\<path d="M5 0h5v5z" fill="lime" fill-opacity=".5"/></svg>
    , 20, 20);
    try expectPx(&pm, 2, 2, .{ 255, 0, 0, 255 }, 0);
    try expectPx(&pm, 15, 15, .{ 0, 0, 255, 255 }, 0);
    try expectPx(&pm, 19, 1, .{ 0, 128, 0, 128 }, 1);
    try expectPx(&pm, 11, 18, .{ 0, 0, 0, 0 }, 0);
}

test "gradients, use, clip, mask, opacity, stroke, pattern, filter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pm = try renderStr(a,
        \\<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
        \\<defs><linearGradient id="g"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
        \\<clipPath id="c"><rect x="0" y="50" width="50" height="50"/></clipPath>
        \\<mask id="m"><rect x="50" y="50" width="25" height="50" fill="white"/></mask>
        \\<pattern id="p" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="2" height="4" fill="red"/></pattern>
        \\<symbol id="s" viewBox="0 0 1 1"><rect width="1" height="1" fill="blue"/></symbol>
        \\<filter id="f"><feFlood flood-color="lime"/></filter></defs>
        \\<rect width="100" height="10" fill="url(#g)"/>
        \\<use xlink:href="#s" x="0" y="20" width="10" height="10"/>
        \\<g clip-path="url(#c)"><rect width="100" height="100" fill="red" opacity="0.5"/></g>
        \\<rect x="50" y="50" width="50" height="50" fill="#0f0" mask="url(#m)"/>
        \\<line x1="20" y1="25" x2="40" y2="25" stroke="black" stroke-width="4"/>
        \\<rect x="60" y="20" width="8" height="8" fill="url(#p)"/>
        \\<rect x="80" y="20" width="10" height="10" filter="url(#f)"/>
        \\</svg>
    , 100, 100);
    // gradient: dark on the left, light on the right
    try std.testing.expect(pm.pixel(2, 5)[0] < 10);
    try std.testing.expect(pm.pixel(97, 5)[0] > 245);
    try expectPx(&pm, 5, 25, .{ 0, 0, 255, 255 }, 0);
    try expectPx(&pm, 25, 75, .{ 128, 0, 0, 128 }, 1);
    try expectPx(&pm, 75, 25, .{ 0, 0, 0, 0 }, 0);
    try expectPx(&pm, 60, 75, .{ 0, 255, 0, 255 }, 0);
    try expectPx(&pm, 90, 75, .{ 0, 0, 0, 0 }, 0);
    try expectPx(&pm, 30, 24, .{ 0, 0, 0, 255 }, 0);
    try expectPx(&pm, 30, 28, .{ 0, 0, 0, 0 }, 0);
    try expectPx(&pm, 60, 21, .{ 255, 0, 0, 255 }, 0);
    try expectPx(&pm, 62, 21, .{ 0, 0, 0, 0 }, 0);
    try expectPx(&pm, 85, 25, .{ 0, 255, 0, 255 }, 0);
    // filter region extends 10% beyond the bbox
    try expectPx(&pm, 90, 25, .{ 0, 255, 0, 255 }, 0);
}

test "fixtures parse and render" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_][]const u8{
        @embedFile("testdata/avatar.svg"),
        @embedFile("testdata/luma.svg"),
        @embedFile("testdata/sticker.svg"),
        @embedFile("testdata/takumi.svg"),
        @embedFile("testdata/hamburger.svg"),
        @embedFile("testdata/effects.svg"),
    };
    for (files) |f| {
        try std.testing.expect(svg.looksLikeSvg(f));
        const pm = try renderStr(a, f, 64, 64);
        var ink: usize = 0;
        for (0..pm.data.len / 4) |i| ink += @intFromBool(pm.data[i * 4 + 3] != 0);
        try std.testing.expect(ink > 50);
    }
}

test "intrinsic size" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try svg.parse(a, "<svg width='2em' viewBox='0 0 10 5'/>");
    const s = svg.intrinsicSize(&d);
    try std.testing.expectEqual(@as(?f32, 32), s.width);
    try std.testing.expectEqual(@as(?f32, 16), s.height);
    const d2 = try svg.parse(a, "<svg width='50%' height='10pt'/>");
    const s2 = svg.intrinsicSize(&d2);
    try std.testing.expectEqual(@as(?f32, null), s2.width);
    try std.testing.expectApproxEqAbs(@as(f32, 13.333), s2.height.?, 1e-3);
}

fn mutate(rng: std.Random, src: []const u8, buf: []u8) []u8 {
    var n: usize = @min(src.len, buf.len);
    @memcpy(buf[0..n], src[0..n]);
    const k = rng.intRangeAtMost(u32, 1, 12);
    const alphabet = "<>/=\"' #.-0123456789eEMmLlAaZzCc()%,;:&url";
    for (0..k) |_| {
        if (n == 0) break;
        const pos = rng.uintLessThan(usize, n);
        switch (rng.uintLessThan(u32, 5)) {
            0 => buf[pos] = alphabet[rng.uintLessThan(usize, alphabet.len)],
            1 => buf[pos] = rng.int(u8),
            2 => { // delete a span
                const l = @min(rng.uintLessThan(usize, 16) + 1, n - pos);
                std.mem.copyForwards(u8, buf[pos .. n - l], buf[pos + l .. n]);
                n -= l;
            },
            3 => { // duplicate a span
                const l = @min(rng.uintLessThan(usize, 64) + 1, n - pos, buf.len - n);
                std.mem.copyBackwards(u8, buf[pos + l .. n + l], buf[pos..n]);
                n += l;
            },
            else => buf[pos] = '9',
        }
    }
    return buf[0..n];
}

const FUZZ_ITERS = 400;

test "fuzz: mutated documents never crash" {
    const seeds = [_][]const u8{
        @embedFile("testdata/features.svg"),
        @embedFile("testdata/effects.svg"),
        @embedFile("testdata/sticker.svg"),
        @embedFile("testdata/avatar.svg"),
    };
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rng = prng.random();
    var buf: [40000]u8 = undefined;
    var iter: usize = 0;
    while (iter < FUZZ_ITERS) : (iter += 1) {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const src = seeds[iter % seeds.len];
        const m = mutate(rng, src, &buf);
        const doc = svg.parse(a, m) catch continue;
        var pm = try raster.Pixmap.init(a, 48, 40);
        var rast = raster.Rasterizer.init(a);
        defer rast.deinit();
        svg.render(a, &rast, &doc, &pm, .{ .x = -3.5, .y = 1.25, .w = 60, .h = 33 }, null, .{}) catch {};
    }
}

test "hostile: use bombs, deep nesting, huge numbers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // exponential use expansion is cut by the instance budget
    _ = try renderStr(a,
        \\<svg xmlns:x="http://www.w3.org/1999/xlink"><path id="a" d="M0 0h1v1z"/>
        \\<g id="b"><use x:href="#a"/><use x:href="#a"/><use x:href="#a"/><use x:href="#a"/></g>
        \\<g id="c"><use x:href="#b"/><use x:href="#b"/><use x:href="#b"/><use x:href="#b"/></g>
        \\<g id="d"><use x:href="#c"/><use x:href="#c"/><use x:href="#c"/><use x:href="#c"/></g>
        \\<g id="e"><use x:href="#d"/><use x:href="#d"/><use x:href="#d"/><use x:href="#d"/></g>
        \\<g id="f"><use x:href="#e"/><use x:href="#e"/><use x:href="#e"/><use x:href="#e"/></g>
        \\<g id="g"><use x:href="#f"/><use x:href="#f"/><use x:href="#f"/><use x:href="#f"/></g>
        \\<g id="h"><use x:href="#g"/><use x:href="#g"/><use x:href="#g"/><use x:href="#g"/></g>
        \\<g id="i"><use x:href="#h"/><use x:href="#h"/><use x:href="#h"/><use x:href="#h"/></g>
        \\<g id="j"><use x:href="#i"/><use x:href="#i"/><use x:href="#i"/><use x:href="#i"/></g>
        \\<use id="k" x:href="#k"/><g id="l"><use x:href="#l"/></g>
        \\<rect width="1e38" height="1e38" stroke="red" stroke-width="1e30" stroke-dasharray="1e-30"/>
        \\<path d="M0 0L10 10" stroke="red" stroke-dasharray="0.0001" stroke-linecap="round"/>
        \\<circle r="1e20" fill="url(#zz) red"/><pattern id="pp" width="1e9" height="1e9" patternUnits="userSpaceOnUse"/>
        \\<rect width="10" height="10" fill="url(#pp)" filter="url(#ff)"/>
        \\</svg>
    , 32, 32);
    var deep: std.ArrayList(u8) = .empty;
    try deep.appendSlice(a, "<svg>");
    for (0..200) |_| try deep.appendSlice(a, "<g opacity='.9'>");
    try deep.appendSlice(a, "<rect width='5' height='5'/>");
    _ = try renderStr(a, deep.items, 16, 16);
}

test "switch, display, visibility, unsupported flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src =
        \\<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">
        \\<switch><rect systemLanguage="fr" width="10" height="10" fill="red"/><rect width="10" height="10" fill="lime"/><rect width="10" height="10" fill="blue"/></switch>
        \\<g visibility="hidden"><rect x="10" width="5" height="10" fill="red"/><rect x="15" width="5" height="10" fill="blue" visibility="visible"/></g>
        \\<g display="none"><rect width="20" height="10" fill="red"/></g>
        \\<text x="1" y="9">hi</text><image href="https://example.com/a.png"/><filter id="f"><feTurbulence/></filter>
        \\</svg>
    ;
    const pm = try renderStr(a, src, 20, 10);
    try expectPx(&pm, 5, 5, .{ 0, 255, 0, 255 }, 0);
    try expectPx(&pm, 12, 5, .{ 0, 0, 0, 0 }, 0);
    try expectPx(&pm, 17, 5, .{ 0, 0, 255, 255 }, 0);
    const doc = try svg.parse(a, src);
    try std.testing.expect(doc.unsupported.text);
    try std.testing.expect(doc.unsupported.external_href);
    try std.testing.expect(doc.unsupported.filter_primitive);
}

const TextSpy = struct {
    calls: u32 = 0,
    last: [32]u8 = undefined,
    len: usize = 0,
    x: f32 = 0,

    fn draw(ctx: *anyopaque, req: *const svg.TextRequest) void {
        const self: *TextSpy = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        self.len = @min(req.text.len, self.last.len);
        @memcpy(self.last[0..self.len], req.text[0..self.len]);
        self.x = req.transform.apply(.{ .x = req.x, .y = req.y }).x;
    }
};

test "text hook, clip parameter, fractional destination" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const doc = try svg.parse(a,
        \\<svg viewBox="0 0 10 10"><rect width="10" height="10" fill="#00f"/>
        \\<text x="2" y="8" font-size="4"> Hello
        \\  <tspan fill="red">big</tspan>  world </text></svg>
    );
    var spy: TextSpy = .{};
    var pm = try raster.Pixmap.init(a, 40, 40);
    var rast = raster.Rasterizer.init(a);
    defer rast.deinit();
    const clip = raster.ClipMask.fromRect(.{ .x = 0, .y = 0, .w = 30, .h = 40 });
    try svg.render(a, &rast, &doc, &pm, .{ .x = 5.5, .y = 5.5, .w = 20, .h = 20 }, &clip, .{ .text = .{ .ctx = &spy, .draw = TextSpy.draw } });
    try std.testing.expectEqual(@as(u32, 1), spy.calls);
    try std.testing.expectEqualStrings("Hello big world", spy.last[0..spy.len]);
    try std.testing.expectApproxEqAbs(@as(f32, 9.5), spy.x, 1e-4);
    // fractional dest: half-covered edge pixel, interior opaque, outside empty
    try expectPx(&pm, 10, 10, .{ 0, 0, 255, 255 }, 0);
    try expectPx(&pm, 5, 10, .{ 0, 0, 128, 128 }, 1);
    try expectPx(&pm, 4, 10, .{ 0, 0, 0, 0 }, 0);
    try expectPx(&pm, 30, 10, .{ 0, 0, 0, 0 }, 0);
}

test "stroker reuse for css dashed borders" {
    // the integrator strokes a rounded border path with dashes through the public API
    const a = std.testing.allocator;
    var src: raster.Path = .{};
    defer src.deinit(a);
    try src.addRoundRect(a, .{ .x = 10, .y = 10, .w = 80, .h = 40 }, .{ .{ 8, 8 }, .{ 8, 8 }, .{ 8, 8 }, .{ 8, 8 } });
    var out: raster.Path = .{};
    defer out.deinit(a);
    try svg.strokeToPath(a, &src, .{ .width = 4, .dashes = &.{ 12, 6 }, .cap = .butt, .join = .round }, &out);
    try std.testing.expect(out.verbs.items.len > 20);
    var m = try raster.rasterize(a, &out, raster.Affine.identity, .nonzero, .{ .x = 0, .y = 0, .w = 100, .h = 60 });
    defer m.deinit(a);
    var sum: f32 = 0;
    for (m.data) |v| sum += @floatFromInt(v);
    // perimeter ~ 240 - 8*(4-pi) ~ 233; 2/3 dashed, width 4 -> ~620 px
    try std.testing.expectApproxEqAbs(@as(f32, 620), sum / 255, 25);
}
