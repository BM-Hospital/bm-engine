//! Wasm root for comparing the raster module's scan converters with takumi (tiny-skia) coverage.
//! Driver: bench/probe/raster/skia_oracle.mjs
const std = @import("std");
const r = @import("raster");
const alloc = std.heap.wasm_allocator;

var path: r.Path = .empty;
var rz: ?r.Rasterizer = null;
var out: []u8 = &.{};

export fn path_reset() void {
    path.reset();
}
export fn path_move(x: f32, y: f32) void {
    path.moveTo(alloc, x, y) catch unreachable;
}
export fn path_line(x: f32, y: f32) void {
    path.lineTo(alloc, x, y) catch unreachable;
}
export fn path_quad(cx: f32, cy: f32, x: f32, y: f32) void {
    path.quadTo(alloc, cx, cy, x, y) catch unreachable;
}
export fn path_cubic(ax: f32, ay: f32, bx: f32, by: f32, x: f32, y: f32) void {
    path.cubicTo(alloc, ax, ay, bx, by, x, y) catch unreachable;
}
export fn path_close() void {
    path.close(alloc) catch unreachable;
}
export fn path_rrect(x: f32, y: f32, w: f32, h: f32, ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32, dx: f32, dy: f32) void {
    path.addRoundRect(alloc, .{ .x = x, .y = y, .w = w, .h = h }, .{ .{ ax, ay }, .{ bx, by }, .{ cx, cy }, .{ dx, dy } }) catch unreachable;
}

/// Rasterizes the current path into a w*h A8 canvas. mode: 0 exact, 1 levels16, 2 skia_ss.
export fn raster(w: u32, h: u32, mode: u32, evenodd: u32, a: f32, b: f32, c: f32, d: f32, e: f32, f: f32) [*]u8 {
    if (rz == null) rz = r.Rasterizer.init(alloc);
    const z = &rz.?;
    z.mode = @fromBackingInt(@intCast(mode));
    alloc.free(out);
    out = alloc.alloc(u8, w * h) catch unreachable;
    @memset(out, 0);
    var m = z.rasterize(alloc, &path, .{ .a = a, .b = b, .c = c, .d = d, .e = e, .f = f }, if (evenodd != 0) .evenodd else .nonzero, .{ .x = 0, .y = 0, .w = w, .h = h }) catch unreachable;
    defer m.deinit(alloc);
    var y: u32 = 0;
    while (y < m.bounds.h) : (y += 1) {
        const dy: usize = @intCast(m.bounds.y + @as(i32, @intCast(y)));
        const dx: usize = @intCast(m.bounds.x);
        @memcpy(out[dy * w + dx ..][0..m.bounds.w], m.data[y * m.bounds.w ..][0..m.bounds.w]);
    }
    return out.ptr;
}
