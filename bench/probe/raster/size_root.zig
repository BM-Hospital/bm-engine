//! Size probe: references the raster API the painter uses (plus optional features selected by
//! `-Dfeature`-less comptime switches below: edit FEATURES or build variants with sed).
const std = @import("std");
const r = @import("raster");
const alloc = std.heap.wasm_allocator;
const STROKE = false;
const BLEND = false;
const MASKS = false;

var rz: ?r.Rasterizer = null;
var path: r.Path = .empty;
var out: r.Path = .empty;

export fn base(dst: *r.Pixmap, src: *r.Pixmap, mode: u32, e: f32, sigma: f32) u32 {
    if (rz == null) rz = r.Rasterizer.init(alloc);
    const z = &rz.?;
    if (@hasField(r.Rasterizer, "mode")) z.mode = @fromBackingInt(@intCast(mode)) else z.levels16 = mode != 0;
    path.addRoundRect(alloc, .{ .x = e, .y = 2, .w = 30, .h = 20 }, .{ .{ 3, 3 }, .{ 3, 3 }, .{ 3, 3 }, .{ 3, 3 } }) catch return 1;
    z.fillPath(dst, &path, r.Affine.translate(e, e), .nonzero, &.{ .solid = r.Color.white }, null) catch return 1;
    var m = z.rasterize(alloc, &path, r.Affine.rotate(e), .evenodd, dst.bounds()) catch return 1;
    r.blurMask(alloc, &m, sigma) catch return 1;
    r.fillMask(dst, &m, &.{ .solid = r.Color.black }, null);
    r.drawPixmap(dst, src, r.Affine.scale(e, e), e, .bilinear, null);
    var rs = r.resample(alloc, src, dst.width, dst.height) catch return 1;
    r.blurPixmap(alloc, &rs, sigma) catch return 1;
    if (STROKE) {
        r.strokePath(alloc, &path, .{ .width = e, .join = @fromBackingInt(@intCast(mode % 3)), .cap = @fromBackingInt(@intCast(mode % 3)), .dash = &.{ e, 2 }, .dash_offset = e }, &out) catch return 1;
        z.fillPath(dst, &out, r.Affine.identity, .nonzero, &.{ .solid = r.Color.white }, null) catch return 1;
    }
    if (BLEND) r.drawPixmapBlend(dst, src, 1, 2, e, @fromBackingInt(@intCast(mode % 17)), null);
    if (MASKS) {
        r.maskMultiply(dst, &m);
        r.maskMultiplyPixmap(dst, src, 1, 2, @fromBackingInt(@intCast(mode % 2)));
        const mm = r.maskFromPixmap(alloc, src, 0, 0, .alpha) catch return 1;
        r.fillMask(dst, &mm, &.{ .solid = r.Color.black }, null);
    }
    return 0;
}
