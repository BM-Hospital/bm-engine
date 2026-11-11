//! Exclusion space of a block formatting context (CSS 2.1 §9.5.1, after Blink's ExclusionSpace): the margin
//! boxes of the floats placed so far, in the coordinate space of the BFC root's border box.
//! Only referenced when `Config.floats` is on.
const std = @import("std");
const st = @import("style.zig");

pub const Rect = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    left: bool,
};

/// Per-BFC bookkeeping; the rectangles live in `Tree.float_rects[start..]`.
pub const Bfc = struct {
    start: u32,
    /// outer top of the last float placed (a float may not sit above an earlier one)
    last_top: f32 = -std.math.inf(f32),
};

const eps: f32 = 1.0 / 128.0;

inline fn overlaps(r: *const Rect, y: f32, h: f32) bool {
    // (empty exclusions never intrude)
    if (!(r.y1 > r.y0) or !(r.x1 > r.x0)) return false;
    return r.y1 > y + eps and r.y0 < y + @max(h, 2 * eps) - eps;
}

/// Free horizontal band [left, right] for a box spanning [y, y + h) inside the containing block [lo, hi].
pub fn band(rects: []const Rect, y: f32, h: f32, lo: f32, hi: f32) [2]f32 {
    var l = lo;
    var r = hi;
    for (rects) |*f| {
        if (!overlaps(f, y, h)) continue;
        if (f.left) l = @max(l, f.x1) else r = @min(r, f.x0);
    }
    return .{ l, r };
}

/// Float edges around a box spanning [y, y + h): the right edge of the left floats (-inf when none) and
/// the left edge of the right floats (+inf when none).
pub fn edges(rects: []const Rect, y: f32, h: f32) [2]f32 {
    return band(rects, y, h, -std.math.inf(f32), std.math.inf(f32));
}

/// The lowest float bottom edge strictly below `y` among the floats overlapping [y, y + h) (NaN when none).
pub fn nextBottom(rects: []const Rect, y: f32, h: f32) f32 {
    var best: f32 = std.math.nan(f32);
    for (rects) |*f| {
        if (!overlaps(f, y, h)) continue;
        if (!(best <= f.y1)) best = f.y1;
    }
    return best;
}

/// Bottom edge of the floats that `clear` clears (-inf when there are none).
pub fn clearY(rects: []const Rect, clear: st.Clear) f32 {
    var y: f32 = -std.math.inf(f32);
    if (clear == .none) return y;
    for (rects) |*f| {
        if (clear == .both or (clear == .left) == f.left) y = @max(y, f.y1);
    }
    return y;
}

/// Bottom edge of the lowest float (-inf when there are none).
pub fn bottom(rects: []const Rect) f32 {
    var y: f32 = -std.math.inf(f32);
    for (rects) |*f| y = @max(y, f.y1);
    return y;
}

/// Position (x, y of the margin box) of a new float of margin-box size w x h that may not be placed above
/// `top`, in the containing block [lo, hi]: as high as possible, then as far to its side as possible.
pub fn place(rects: []const Rect, left: bool, w: f32, h: f32, top: f32, lo: f32, hi: f32) [2]f32 {
    var y = top;
    var guard: usize = 0;
    while (guard <= rects.len) : (guard += 1) {
        const b = band(rects, y, h, lo, hi);
        const free = b[0] <= lo and b[1] >= hi;
        if (free or b[1] - b[0] >= w - eps) return .{ if (left) b[0] else b[1] - w, y };
        const nb = nextBottom(rects, y, h);
        if (!(nb > y)) break;
        y = nb;
    }
    return .{ if (left) lo else hi - w, y };
}
