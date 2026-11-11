//! Mask / clip helpers (inset shadows, clip stacks). All results are allocated from the
//! allocator passed in (typically the per-render arena) and owned by the caller.
const std = @import("std");
const types = @import("types.zig");
const Rect = types.Rect;
const IRect = types.IRect;
const Mask = types.Mask;
const ClipMask = types.ClipMask;
const clampF = types.clampF;
const div255 = types.div255;
const Allocator = std.mem.Allocator;

/// Coverage mask of an axis-aligned rectangle (exact-area AA on fractional edges).
/// Result bounds = pixel bounds of `rect` ∩ `clip`.
pub fn maskFromRect(alloc: Allocator, rect: Rect, clip: IRect) !Mask {
    if (clip.isEmpty()) return Mask.empty;
    const lim: f32 = 1.0e6;
    const cx0 = clampF(@floatFromInt(clip.x), -lim, lim);
    const cy0 = clampF(@floatFromInt(clip.y), -lim, lim);
    const cx1 = clampF(@floatFromInt(clip.right()), -lim, lim);
    const cy1 = clampF(@floatFromInt(clip.bottom()), -lim, lim);
    const x0 = clampF(rect.x, cx0, cx1);
    const y0 = clampF(rect.y, cy0, cy1);
    const x1 = clampF(rect.x + rect.w, cx0, cx1);
    const y1 = clampF(rect.y + rect.h, cy0, cy1);
    if (!(x1 > x0) or !(y1 > y0)) return Mask.empty;
    const ix0: i32 = @intFromFloat(@floor(x0));
    const iy0: i32 = @intFromFloat(@floor(y0));
    const ix1: i32 = @intFromFloat(@ceil(x1));
    const iy1: i32 = @intFromFloat(@ceil(y1));
    var m = try Mask.init(alloc, .{ .x = ix0, .y = iy0, .w = @intCast(ix1 - ix0), .h = @intCast(iy1 - iy0) });
    const w: usize = m.bounds.w;
    for (0..m.bounds.h) |j| {
        const yf: f32 = @floatFromInt(iy0 + @as(i32, @intCast(j)));
        const cy = @min(yf + 1, y1) - @max(yf, y0);
        const row = m.data[j * w ..][0..w];
        // only the first and last column can be partially covered horizontally
        @memset(row, @intFromFloat(clampF(cy, 0, 1) * 255 + 0.5));
        const ends = [2]usize{ 0, w - 1 };
        for (ends) |i| {
            const xf: f32 = @floatFromInt(ix0 + @as(i32, @intCast(i)));
            const cx = @min(xf + 1, x1) - @max(xf, x0);
            row[i] = @intFromFloat(clampF(cx * cy, 0, 1) * 255 + 0.5);
        }
    }
    return m;
}

fn clipAt(c: ClipMask, x: i32, y: i32) [*]const u8 {
    const ix: usize = @intCast(@as(i64, x) - c.bounds.x);
    const iy: usize = @intCast(@as(i64, y) - c.bounds.y);
    return c.data.?.ptr + iy * c.bounds.w + ix;
}

/// Intersection of two clips (clip stack push). No allocation when both are plain rects;
/// otherwise the returned `data` is allocated from `alloc`.
pub fn clipIntersect(alloc: Allocator, a: ClipMask, b: ClipMask) !ClipMask {
    const r = a.bounds.intersect(b.bounds);
    if (r.isEmpty()) return .{ .bounds = IRect.empty };
    const a_ok = if (a.data) |d| d.len >= @as(u64, a.bounds.w) * a.bounds.h else false;
    const b_ok = if (b.data) |d| d.len >= @as(u64, b.bounds.w) * b.bounds.h else false;
    if (a.data != null and !a_ok) return .{ .bounds = IRect.empty };
    if (b.data != null and !b_ok) return .{ .bounds = IRect.empty };
    if (!a_ok and !b_ok) return .{ .bounds = r };
    var m = try Mask.init(alloc, r);
    const w: usize = r.w;
    for (0..r.h) |j| {
        const y: i32 = r.y + @as(i32, @intCast(j));
        const o = m.data[j * w ..][0..w];
        if (a_ok and b_ok) {
            const pa = clipAt(a, r.x, y);
            const pb = clipAt(b, r.x, y);
            for (o, 0..) |*v, i| v.* = @intCast(div255(@as(u32, pa[i]) * pb[i]));
        } else {
            const p = if (a_ok) clipAt(a, r.x, y) else clipAt(b, r.x, y);
            @memcpy(o, p[0..w]);
        }
    }
    return .{ .bounds = r, .data = m.data };
}

/// Per-pixel product of two masks over the intersection of their bounds.
pub fn maskIntersect(alloc: Allocator, a: *const Mask, b: *const Mask) !Mask {
    if (a.bounds.isEmpty() or b.bounds.isEmpty()) return Mask.empty;
    const c = try clipIntersect(alloc, a.asClip(), b.asClip());
    if (c.bounds.isEmpty() or c.data == null) return Mask.empty;
    return .{ .bounds = c.bounds, .data = @constCast(c.data.?) };
}

/// `255 - mask` over `within` (pixels of `within` outside the mask bounds become 255).
/// Used for inset shadows: invert the padding-box shape, blur, clip to the padding box.
pub fn maskInvertWithin(alloc: Allocator, mask: *const Mask, within: IRect) !Mask {
    var m = try Mask.init(alloc, within);
    if (within.isEmpty()) return m;
    @memset(m.data, 255);
    if (mask.data.len < @as(u64, mask.bounds.w) * mask.bounds.h) return m;
    const r = within.intersect(mask.bounds);
    if (r.isEmpty()) return m;
    for (0..r.h) |j| {
        const y: i64 = @as(i64, r.y) + @as(i64, @intCast(j));
        const so: usize = @as(usize, @intCast(y - mask.bounds.y)) * mask.bounds.w + @as(usize, @intCast(@as(i64, r.x) - mask.bounds.x));
        const do: usize = @as(usize, @intCast(y - within.y)) * within.w + @as(usize, @intCast(@as(i64, r.x) - within.x));
        for (m.data[do..][0..r.w], mask.data[so..][0..r.w]) |*o, v| o.* = 255 - v;
    }
    return m;
}
