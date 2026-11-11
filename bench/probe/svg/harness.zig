//! Wasm harness for comparing the SVG module with the takumi oracle (bench/probe/svg/oracle.mjs).
//! Build (repo root, ZIG = zig 0.17.1):
//!   ZIG build-exe -target wasm32-freestanding -mcpu=generic+simd128+bulk_memory+sign_ext+nontrapping_fptoint+mutable_globals -O ReleaseSmall -fno-entry -rdynamic -fstrip -femit-bin=<out>/svg_harness.wasm --dep bm -Mroot=bench/probe/svg/harness.zig -Mbm=src/test_svg.zig
const std = @import("std");
const bm = @import("bm");
const svg = bm.svg;
const r = bm.raster;
const gpa = std.heap.wasm_allocator;

var out: r.Pixmap = r.Pixmap.empty;
var last_us: u32 = 0;

export fn buf_alloc(n: usize) ?[*]u8 {
    const s = gpa.alloc(u8, n) catch return null;
    return s.ptr;
}

export fn buf_free(p: [*]u8, n: usize) void {
    gpa.free(p[0..n]);
}

/// Renders `text` into a w x h straight-RGBA buffer (returned pointer); 0 on parse error.
export fn render(p: [*]const u8, n: usize, w: u32, h: u32, levels16: u32, dx: f32, dy: f32, dw: f32, dh: f32) usize {
    out.deinit(gpa);
    out = r.Pixmap.init(gpa, w, h) catch return 0;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const doc = svg.parse(a, p[0..n]) catch return 0;
    var rast = r.Rasterizer.init(gpa);
    defer rast.deinit();
    rast.levels16 = levels16 != 0;
    svg.render(a, &rast, &doc, &out, .{ .x = dx, .y = dy, .w = dw, .h = dh }, null, .{}) catch return 0;
    out.toStraightAlpha();
    return @intFromPtr(out.data.ptr);
}

export fn unsupported_bits(p: [*]const u8, n: usize) u32 {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const doc = svg.parse(arena.allocator(), p[0..n]) catch return 0xFFFFFFFF;
    return @bitCast(doc.unsupported);
}
