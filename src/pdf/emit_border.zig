//! PDF output of borders and outlines: the painter's border algorithm (paint_border.zig, a port
//! of takumi's / Blink's `BoxBorderPainter`, as svg_out_border.zig drives it for SVG) through
//! takumi-pdf's paint device (emit_device.zig): fills are filled paths (`re` / rounded paths,
//! even-odd rings), clips are clip paths (`q .. W n` .. `Q`, mitre clips included), dashed and
//! dotted sides are stroked centre lines with a dash array, translucent side groups that would
//! double-blend go through an opacity group. Geometry is box-local and offset to the box.
const std = @import("std");
const render = @import("../render.zig");
const style = @import("../style/style.zig");
const computed = @import("../style/computed.zig");
const cmath = @import("../style/cmath.zig");
const raster = @import("../raster/raster.zig");
const pm = @import("../paint.zig");
const pborder = @import("../paint_border.zig");
const sborder = @import("../svg_out_border.zig");
const dev = @import("emit_device.zig");

const Geom = pm.Geom;
const Radii = pm.Radii;
const CS = render.CS;
const Rect = raster.Rect;
const Path = raster.Path;
const Error = render.Error;
const Color = style.Color;
const BStyle = computed.BorderStyle;
const Pt = [2]f32;
const Device = dev.Device;

const T = 0;
const R = 1;
const Bo = 2;
const L = 3;

const Miter = enum { none, soft, hard };

pub const Spec = sborder.Spec;

fn effective(st: BStyle, width: f32) BStyle {
    return switch (st) {
        .double => if (width < 3) .solid else st,
        .groove, .ridge => if (width <= 1) .solid else st,
        else => st,
    };
}

fn fillsArea(st: BStyle) bool {
    return st != .dotted and st != .dashed and st != .double;
}

fn is3d(st: BStyle) bool {
    return st == .inset or st == .outset or st == .groove or st == .ridge;
}

fn styleRank(st: BStyle) u8 {
    return switch (st) {
        .dotted, .dashed, .double => 1,
        .inset, .outset, .groove, .ridge => 2,
        else => 3,
    };
}

const side_rank = [4]u8{ 0, 2, 1, 3 };

fn shrinkRadii(r: Radii, t: f32, rg: f32, b: f32, l: f32) Radii {
    const ins = [4][2]f32{ .{ l, t }, .{ rg, t }, .{ rg, b }, .{ l, b } };
    var out = r;
    for (&out, ins) |*c, i| {
        if (c[0] > 0) c[0] = @max(c[0] - i[0], 0);
        if (c[1] > 0) c[1] = @max(c[1] - i[1], 0);
    }
    return out;
}

// ---- colours of the 3D styles (Blink `Color::Dark` / `Light`)

fn scaled(c: Color, f: f32) Color {
    var o = c;
    inline for (.{ "r", "g", "b" }) |n| {
        const v = @as(f32, @floatFromInt(@field(c, n))) / 255.0 * f * 255.99998;
        @field(o, n) = @intFromFloat(std.math.clamp(v, 0, 255));
    }
    return o;
}

fn maxv(c: Color) f32 {
    return @as(f32, @floatFromInt(@max(c.r, @max(c.g, c.b)))) / 255.0;
}

fn dark(c: Color) Color {
    const v = maxv(c);
    return scaled(c, if (v == 0) 0 else @max((v - 0.33) / v, 0));
}

fn light(c: Color) Color {
    const v = maxv(c);
    if (v == 0) return .{ .r = 84, .g = 84, .b = 84, .a = c.a };
    return scaled(c, @min(v + 0.33, 1) / v);
}

fn lin(u: u8) f32 {
    const v = @as(f32, @floatFromInt(u)) / 255.0;
    if (v <= 0.04045) return v / 12.92;
    return @floatCast(cmath.spow((v + 0.055) / 1.055, 2.4));
}

fn insetOutset(c: Color, darken: bool) Color {
    const lum = 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    if (lum <= 0.014443844) return if (darken) light(c) else light(light(c));
    if (darken) return dark(c);
    return if (lum > 0.83077) c else light(c);
}

fn darkenedBy(side: usize, st: BStyle) bool {
    return (side == T or side == L) == (st == .inset);
}

const Dash = pborder.Dash;
const dashPattern = pborder.dashPattern;

fn cross(a: Pt, b: Pt) f32 {
    return a[0] * b[1] - a[1] * b[0];
}

fn meet(a: Pt, b: Pt, c: Pt, d: Pt, fallback: Pt) Pt {
    const den = cross(.{ b[0] - a[0], b[1] - a[1] }, .{ d[0] - c[0], d[1] - c[1] });
    if (den == 0 or den != den) return fallback;
    const t = cross(.{ c[0] - a[0], c[1] - a[1] }, .{ d[0] - c[0], d[1] - c[1] }) / den;
    return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t };
}

/// Length of a closed path the way takumi measures it (cubics as 16 uniform chords).
fn pathLength(path: *const Path) f32 {
    var len: f32 = 0;
    var cur: raster.Point = .{ .x = 0, .y = 0 };
    var start = cur;
    var pi: usize = 0;
    const pts = path.points.items;
    for (path.verbs.items) |v| switch (v) {
        .move => {
            if (pi >= pts.len) return len;
            cur = pts[pi];
            start = cur;
            pi += 1;
        },
        .line => {
            if (pi >= pts.len) return len;
            len += @sqrt((pts[pi].x - cur.x) * (pts[pi].x - cur.x) + (pts[pi].y - cur.y) * (pts[pi].y - cur.y));
            cur = pts[pi];
            pi += 1;
        },
        .cubic => {
            if (pi + 3 > pts.len) return len;
            var prev = cur;
            var i: u32 = 1;
            while (i <= 16) : (i += 1) {
                const t = @as(f32, @floatFromInt(i)) / 16.0;
                const mt = 1 - t;
                const w0 = mt * mt * mt;
                const w1 = 3 * mt * mt * t;
                const w2 = 3 * mt * t * t;
                const w3 = t * t * t;
                const q: raster.Point = .{
                    .x = w0 * cur.x + w1 * pts[pi].x + w2 * pts[pi + 1].x + w3 * pts[pi + 2].x,
                    .y = w0 * cur.y + w1 * pts[pi].y + w2 * pts[pi + 1].y + w3 * pts[pi + 2].y,
                };
                len += @sqrt((q.x - prev.x) * (q.x - prev.x) + (q.y - prev.y) * (q.y - prev.y));
                prev = q;
            }
            cur = pts[pi + 2];
            pi += 3;
        },
        .quad => pi += 2,
        .close => {
            len += @sqrt((start.x - cur.x) * (start.x - cur.x) + (start.y - cur.y) * (start.y - cur.y));
            cur = start;
        },
    };
    return len;
}

const B = struct {
    d: *Device,
    a: std.mem.Allocator,
    s: *const Spec,
    path: *Path,
    path2: *Path,
    inner_radii: Radii,
    rounded: bool,
    inner_renderable: bool,

    fn oom(_: anytype) Error {
        return error.OutOfMemory;
    }

    // ---- paths (box-local)

    fn rrect(b: *B, path: *Path, t: f32, rg: f32, bt: f32, l: f32) Error!void {
        const s = b.s;
        const w = s.w - l - rg;
        const h = s.h - t - bt;
        if (!(w > 0) or !(h > 0)) return;
        const r: Rect = .{ .x = l, .y = t, .w = w, .h = h };
        var rr = shrinkRadii(s.radii, t, rg, bt, l);
        var any = false;
        for (&rr) |*c| {
            if (c[0] <= 0 or c[1] <= 0) c.* = .{ 0, 0 } else any = true;
        }
        if (any) {
            var f: f32 = 1;
            const sums = [4][2]f32{ .{ rr[0][0] + rr[1][0], w }, .{ rr[3][0] + rr[2][0], w }, .{ rr[0][1] + rr[3][1], h }, .{ rr[1][1] + rr[2][1], h } };
            for (sums) |e| if (e[0] > e[1] and e[0] > 0) {
                f = @min(f, e[1] / e[0]);
            };
            if (f < 1) for (&rr) |*c| {
                c[0] *= f;
                c[1] *= f;
            };
            path.addRoundRect(b.a, r, rr) catch return error.OutOfMemory;
        } else path.addRect(b.a, r) catch return error.OutOfMemory;
    }

    fn poly(b: *B, path: *Path, pts: []const Pt) Error!void {
        path.moveTo(b.a, pts[0][0], pts[0][1]) catch return error.OutOfMemory;
        for (pts[1..]) |q| path.lineTo(b.a, q[0], q[1]) catch return error.OutOfMemory;
        path.close(b.a) catch return error.OutOfMemory;
    }

    // ---- clips: pushed on the device now, popped by `restore`

    fn pushClip(b: *B, path: *const Path, out: bool) void {
        if (out) {
            b.d.pushClipOut(path, b.s.x, b.s.y);
        } else b.d.pushClip(path, b.s.x, b.s.y, .nonzero);
    }

    fn fill(b: *B, path: *const Path, rule: raster.FillRule, col: Color) Error!void {
        if (col.a == 0 or path.isEmpty()) return;
        b.d.fillPath(path, b.s.x, b.s.y, if (rule == .evenodd) .even_odd else .nonzero, col);
    }

    fn fillRect(b: *B, x1: f32, y1: f32, x2: f32, y2: f32, col: Color) Error!void {
        if (!(x2 > x1) or !(y2 > y1)) return;
        if (col.a == 0) return;
        b.d.fillRRect(.{ .x = b.s.x + x1, .y = b.s.y + y1, .w = x2 - x1, .h = y2 - y1 }, null, col);
    }

    fn fillBox(b: *B, col: Color) Error!void {
        try b.fillRect(0, 0, b.s.w, b.s.h, col);
    }

    fn stroke(b: *B, width: f32, dash: ?Dash, col: Color) Error!void {
        if (col.a == 0 or b.path.isEmpty()) return;
        b.d.strokePath(b.path, b.s.x, b.s.y, width, if (dash) |ds| .{ ds.on, ds.off } else null, if (dash) |ds| ds.round else false, col);
    }

    // ---- mitre clips (takumi `push_miter_clips`)

    fn pushMiterClips(b: *B, side: usize, first: Miter, second: Miter) Error!void {
        const s = b.s;
        const odd = side & 1 == 1;
        const cw: f32 = if (odd) s.h else s.w;
        const ch: f32 = if (odd) s.w else s.h;
        const t = s.bw[side];
        const l = s.bw[(side + 3) % 4];
        const r = s.bw[(side + 1) % 4];
        const bt = s.bw[(side + 2) % 4];
        const inner = [4]Pt{ .{ l, t }, .{ cw - r, t }, .{ cw - r, ch - bt }, .{ l, ch - bt } };
        var quad = [4]Pt{ .{ 0, 0 }, inner[0], inner[1], .{ cw, 0 } };
        var bound = [2]Pt{ .{ quad[0][0], quad[1][1] }, .{ quad[3][0], quad[2][1] } };
        var pent: ?[5]Pt = null;
        var rad: [2]?Pt = .{ null, null };
        for (0..2) |i| {
            const c = b.inner_radii[(side + i) % 4];
            if (c[0] != 0 or c[1] != 0) rad[i] = if (odd) .{ c[1], c[0] } else c;
        }
        if (rad[0]) |rr| {
            const q = quad;
            quad[1] = meet(q[0], q[1], .{ q[1][0] + rr[0], q[1][1] }, .{ q[1][0], q[1][1] + rr[1] }, q[1]);
            bound[0][1] = quad[1][1];
            bound[1][1] = quad[1][1];
            if (quad[1][1] > inner[2][1]) quad[1] = meet(quad[0], quad[1], inner[3], inner[2], quad[1]);
            if (quad[1][0] > inner[2][0]) quad[1] = meet(quad[0], quad[1], inner[1], inner[2], quad[1]);
            if (quad[2][1] < quad[1][1] and quad[2][0] > quad[1][0]) pent = .{ quad[0], quad[1], .{ quad[2][0], quad[1][1] }, quad[2], quad[3] };
        }
        if (rad[1]) |rr| {
            const q = quad;
            quad[2] = meet(q[3], q[2], .{ q[2][0] - rr[0], q[2][1] }, .{ q[2][0], q[2][1] + rr[1] }, q[2]);
            if (bound[0][1] < quad[2][1]) {
                bound[0][1] = quad[2][1];
                bound[1][1] = quad[2][1];
            }
            if (quad[2][1] > inner[3][1]) quad[2] = meet(quad[3], quad[2], inner[3], inner[2], quad[2]);
            if (quad[2][0] < inner[3][0]) quad[2] = meet(quad[3], quad[2], inner[0], inner[3], quad[2]);
            if (quad[2][1] > quad[1][1] and quad[2][0] > quad[1][0]) pent = .{ quad[0], quad[1], .{ quad[1][0], quad[2][1] }, quad[2], quad[3] };
        }
        const ext: f32 = 0.1;
        if (first == second) {
            if (pent != null and !b.inner_renderable) {
                try b.clipPoly(side, &pent.?);
            } else try b.clipPoly(side, &quad);
            return;
        }
        if (first != .none) {
            const cut = meet(quad[0], quad[1], bound[0], bound[1], .{ 0, 0 });
            try b.clipPoly(side, &.{ .{ quad[0][0] - ext, quad[0][1] }, .{ cut[0] - ext, cut[1] }, bound[1], quad[3] });
        }
        if (second != .none) {
            const cut = meet(quad[2], quad[3], bound[0], bound[1], .{ 0, 0 });
            try b.clipPoly(side, &.{ quad[0], bound[0], .{ cut[0] + ext, cut[1] }, .{ quad[3][0] + ext, quad[3][1] } });
        }
    }

    fn clipPoly(b: *B, side: usize, pts: []const Pt) Error!void {
        const s = b.s;
        var buf: [5]Pt = undefined;
        for (pts, 0..) |q, i| buf[i] = switch (side) {
            T => q,
            R => .{ s.w - q[1], q[0] },
            Bo => .{ s.w - q[0], s.h - q[1] },
            else => .{ q[1], s.h - q[0] },
        };
        const path = b.path2;
        path.reset();
        try b.poly(path, buf[0..pts.len]);
        b.pushClip(path, false);
    }

    // ---- straight sides (takumi `BoxSideRect`)

    fn inward(w: i32) f32 {
        return @floatFromInt(@max(w, 0));
    }
    fn outward(w: i32) f32 {
        return @floatFromInt(@max(-w, 0));
    }

    fn rectSolid(b: *B, side: usize, x1: f32, y1: f32, x2: f32, y2: f32, col: Color, a1: i32, a2: i32) Error!void {
        if (a1 == 0 and a2 == 0) return b.fillRect(x1, y1, x2, y2, col);
        const q: [4]Pt = switch (side) {
            T => .{ .{ x1 + outward(a1), y1 }, .{ x1 + inward(a1), y2 }, .{ x2 - inward(a2), y2 }, .{ x2 - outward(a2), y1 } },
            Bo => .{ .{ x1 + inward(a1), y1 }, .{ x1 + outward(a1), y2 }, .{ x2 - outward(a2), y2 }, .{ x2 - inward(a2), y1 } },
            L => .{ .{ x1, y1 + outward(a1) }, .{ x1, y2 - outward(a2) }, .{ x2, y2 - inward(a2) }, .{ x2, y1 + inward(a1) } },
            else => .{ .{ x1, y1 + inward(a1) }, .{ x1, y2 - inward(a2) }, .{ x2, y2 - outward(a2) }, .{ x2, y1 + outward(a1) } },
        };
        const path = b.path;
        path.reset();
        try b.poly(path, &q);
        try b.fill(path, .nonzero, col);
    }

    fn fi(v: i32) f32 {
        return @floatFromInt(v);
    }

    fn rectPaint(b: *B, side: usize, x1: f32, y1: f32, x2: f32, y2: f32, st_in: BStyle, col: Color, a1: i32, a2: i32, depth: u32) Error!void {
        const horiz = side == T or side == Bo;
        const length = if (horiz) x2 - x1 else y2 - y1;
        const thick_f = if (horiz) y2 - y1 else x2 - x1;
        if (!(length > 0) or !(thick_f > 0) or depth > 3) return;
        const th: i32 = @intFromFloat(@min(@round(thick_f), 1.0e6));
        const st = effective(st_in, fi(th));
        switch (st) {
            .dashed, .dotted => try b.rectPattern(side, x1, y1, x2, y2, st, col, th),
            .double => {
                const third = fi(@divTrunc(th + 1, 3));
                if (a1 == 0 and a2 == 0) {
                    if (horiz) {
                        try b.fillRect(x1, y1, x2, y1 + third, col);
                        try b.fillRect(x1, y2 - third, x2, y2, col);
                    } else {
                        try b.fillRect(x1, y1, x1 + third, y2, col);
                        try b.fillRect(x2 - third, y1, x2, y2, col);
                    }
                    return;
                }
                const b1 = bigDiv(a1, 3);
                const b2 = bigDiv(a2, 3);
                const ip1 = dInset(a1);
                const ip2 = dInset(a2);
                const in1 = dInset(-a1);
                const in2 = dInset(-a2);
                switch (side) {
                    T => {
                        try b.rectSolid(side, x1 + in1, y1, x2 - in2, y1 + third, col, b1, b2);
                        try b.rectSolid(side, x1 + ip1, y2 - third, x2 - ip2, y2, col, b1, b2);
                    },
                    L => {
                        try b.rectSolid(side, x1, y1 + in1, x1 + third, y2 - in2, col, b1, b2);
                        try b.rectSolid(side, x2 - third, y1 + ip1, x2, y2 - ip2, col, b1, b2);
                    },
                    Bo => {
                        try b.rectSolid(side, x1 + ip1, y1, x2 - ip2, y1 + third, col, b1, b2);
                        try b.rectSolid(side, x1 + in1, y2 - third, x2 - in2, y2, col, b1, b2);
                    },
                    else => {
                        try b.rectSolid(side, x1, y1 + ip1, x1 + third, y2 - ip2, col, b1, b2);
                        try b.rectSolid(side, x2 - third, y1 + in1, x2, y2 - in2, col, b1, b2);
                    },
                }
            },
            .groove, .ridge => {
                const s1: BStyle = if (st == .groove) .inset else .outset;
                const s2: BStyle = if (st == .groove) .outset else .inset;
                const bh1 = bigDiv(a1, 2);
                const bh2 = bigDiv(a2, 2);
                const h1 = @divTrunc(a1, 2);
                const h2 = @divTrunc(a2, 2);
                const from = if (horiz) y1 else x1;
                const to = if (horiz) y2 else x2;
                const mid = from + fi(@divTrunc(@as(i32, @intFromFloat(@min(@round(to - from), 1.0e6))) + 1, 2));
                switch (side) {
                    T => {
                        try b.rectPaint(side, x1 + half(-a1), y1, x2 - half(-a2), mid, s1, col, bh1, bh2, depth + 1);
                        try b.rectPaint(side, x1 + half(a1 + 1), mid, x2 - half(a2 + 1), y2, s2, col, h1, h2, depth + 1);
                    },
                    L => {
                        try b.rectPaint(side, x1, y1 + half(-a1), mid, y2 - half(-a2), s1, col, bh1, bh2, depth + 1);
                        try b.rectPaint(side, mid, y1 + half(a1 + 1), x2, y2 - half(a2 + 1), s2, col, h1, h2, depth + 1);
                    },
                    Bo => {
                        try b.rectPaint(side, x1 + half(a1), y1, x2 - half(a2), mid, s2, col, bh1, bh2, depth + 1);
                        try b.rectPaint(side, x1 + half(-a1 + 1), mid, x2 - half(-a2 + 1), y2, s1, col, h1, h2, depth + 1);
                    },
                    else => {
                        try b.rectPaint(side, x1, y1 + half(a1), mid, y2 - half(a2), s2, col, bh1, bh2, depth + 1);
                        try b.rectPaint(side, mid, y1 + half(-a1 + 1), x2, y2 - half(-a2 + 1), s1, col, h1, h2, depth + 1);
                    },
                }
            },
            .inset, .outset => try b.rectSolid(side, x1, y1, x2, y2, insetOutset(col, darkenedBy(side, st)), a1, a2),
            else => try b.rectSolid(side, x1, y1, x2, y2, col, a1, a2),
        }
    }

    fn bigDiv(w: i32, d: i32) i32 {
        return @divTrunc(if (w > 0) w + 1 else w - 1, d);
    }
    fn dInset(w: i32) f32 {
        return fi(@max(@divTrunc(w * 2 + 1, 3), 0));
    }
    fn half(w: i32) f32 {
        return fi(@divTrunc(@max(w, 0), 2));
    }

    /// Dashed / dotted straight side: a stroked centre line (takumi `StyledLine::box_side`).
    fn rectPattern(b: *B, side: usize, x1: f32, y1: f32, x2: f32, y2: f32, st: BStyle, col: Color, th: i32) Error!void {
        const horiz = side == T or side == Bo;
        const w = fi(th);
        const hw = w / 2;
        var from = if (horiz) x1 else y1;
        var to = if (horiz) x2 else y2;
        const c = (if (horiz) y1 else x1) + hw;
        const length = @abs(to - from);
        const dash = dashPattern(st, w, length, false);
        if (st == .dotted and th >= 1 and th <= 3) {
            // Blink `EnforceDotsAtEndpoints`
            const len: i32 = @intFromFloat(@min(@round(to - from), 1.0e7));
            const m4 = @mod(len, 4);
            const m6 = @mod(len, 6);
            var start: ?i32 = null;
            var end: ?i32 = null;
            var start_off: i32 = 0;
            if ((th == 1 and @mod(len, 2) == 0) or (th == 3 and m6 == 0)) {
                start = 1;
                start_off = 1;
            }
            if ((th == 2 and (m4 == 0 or m4 == 1)) or (th == 3 and (m6 == 1 or m6 == 2))) {
                if (start == null) start = 0;
                start_off = -1;
            }
            if ((th == 2 and m4 == 0) or (th == 3 and m6 == 1)) end = 0;
            if ((th == 2 and m4 == 3) or (th == 3 and (m6 == 4 or m6 == 5))) {
                if (start == null) start = 0;
                start_off = 1;
            }
            if (th == 3 and m6 == 5) {
                end = 0;
            } else if (th == 3 and m6 == 0) end = 1;
            if (start) |g| {
                const sz = fi(th + g);
                if (horiz) try b.fillRect(from, c - hw, from + sz, c - hw + w, col) else try b.fillRect(c - hw, from, c - hw + w, from + sz, col);
                from += fi(2 * th + start_off);
            }
            if (end) |g| {
                const sz = fi(th + g);
                if (horiz) try b.fillRect(to - sz, c - hw, to, c - hw + w, col) else try b.fillRect(c - hw, to - sz, c - hw + w, to, col);
                to -= sz + 1;
            }
        } else if (dash != null and dash.?.round) {
            from += hw;
            to -= hw;
        }
        if (!(to > from)) return;
        const path = b.path;
        path.reset();
        if (horiz) {
            path.moveTo(b.a, from, c) catch return error.OutOfMemory;
            path.lineTo(b.a, to, c) catch return error.OutOfMemory;
        } else {
            path.moveTo(b.a, c, from) catch return error.OutOfMemory;
            path.lineTo(b.a, c, to) catch return error.OutOfMemory;
        }
        try b.stroke(w, dash, col);
    }

    // ---- sides

    fn colorsMatch(b: *B, side: usize, nb: usize) bool {
        const s = b.s;
        if (!(s.bw[nb] > 0) or s.col[nb].a == 0 or !s.col[side].eql(s.col[nb])) return false;
        if (is3d(s.st[side])) {
            const lo = @min(side, nb);
            const hi = @max(side, nb);
            if ((lo == T and hi == R) or (lo == Bo and hi == L)) return false;
        }
        return true;
    }

    fn miterBetween(b: *B, side: usize, nb: usize, completed: *const [4]bool) Miter {
        const s = b.s;
        if (!(s.bw[nb] > 0)) return .none;
        if (!completed[nb] and fillsArea(s.st[nb])) return .none;
        if (!b.colorsMatch(side, nb)) return .soft;
        const ns = s.st[nb];
        if (s.st[side] == .double or ns == .double or ns == .groove or ns == .ridge or s.st[side] != ns) return .hard;
        return .none;
    }

    fn paintSide(b: *B, side: usize, col: Color, completed: *const [4]bool) Error!void {
        const s = b.s;
        const st = s.st[side];
        const adj: [2]usize = if (side == T or side == Bo) .{ L, R } else .{ T, Bo };
        const prev_is_adj0 = side == T or side == R;
        const saved = b.d.depth();
        defer b.d.restore(saved);
        const ir = b.inner_radii;
        const c0 = ir[side];
        const c1 = ir[(side + 1) % 4];
        const arcs = c0[0] != 0 or c0[1] != 0 or c1[0] != 0 or c1[1] != 0;
        if (b.rounded and (st == .groove or st == .ridge or st == .double or arcs)) {
            const m0: Miter = if (b.colorsMatch(side, adj[0])) .hard else .soft;
            const m1: Miter = if (b.colorsMatch(side, adj[1])) .hard else .soft;
            try b.pushMiterClips(side, if (prev_is_adj0) m0 else m1, if (prev_is_adj0) m1 else m0);
            if (!b.inner_renderable) {
                const path = b.path;
                path.reset();
                try b.rrect(path, s.bw[T], s.bw[R], s.bw[Bo], s.bw[L]);
                if (!path.isEmpty()) b.pushClip(path, true);
            }
            const sw = @max(s.bw[side], @max(s.bw[adj[0]], s.bw[adj[1]]));
            try b.curvedSide(side, st, col, sw);
            return;
        }
        const m0 = b.miterBetween(side, adj[0], completed);
        const m1 = b.miterBetween(side, adj[1], completed);
        const clipped = m0 == .hard or m1 == .hard or ((m0 != .none or m1 != .none) and (st == .dashed or st == .dotted));
        if (clipped) try b.pushMiterClips(side, if (prev_is_adj0) m0 else m1, if (prev_is_adj0) m1 else m0);
        const a1: i32 = if (clipped or m0 == .none) 0 else @intFromFloat(@min(@round(s.bw[adj[0]]), 1.0e6));
        const a2: i32 = if (clipped or m1 == .none) 0 else @intFromFloat(@min(@round(s.bw[adj[1]]), 1.0e6));
        const w = s.bw[side];
        switch (side) {
            T => try b.rectPaint(side, 0, 0, s.w, w, st, col, a1, a2, 0),
            Bo => try b.rectPaint(side, 0, s.h - w, s.w, s.h, st, col, a1, a2, 0),
            L => try b.rectPaint(side, 0, 0, w, s.h, st, col, a1, a2, 0),
            else => try b.rectPaint(side, s.w - w, 0, s.w, s.h, st, col, a1, a2, 0),
        }
    }

    fn stripe(b: *B, f: f32) [4]f32 {
        var o: [4]f32 = undefined;
        for (&o, b.s.bw) |*v, w| v.* = @round(w * f);
        return o;
    }

    fn clipInset(b: *B, ins: [4]f32, out: bool) Error!void {
        const path = b.path;
        path.reset();
        try b.rrect(path, ins[0], ins[1], ins[2], ins[3]);
        if (path.isEmpty()) {
            // an empty inset shape clips everything (intersect) or nothing (clip-out)
            if (out) return;
            path.addRect(b.a, .{ .x = 0, .y = 0, .w = 0, .h = 0 }) catch return error.OutOfMemory;
        }
        b.pushClip(path, out);
    }

    fn curvedSide(b: *B, side: usize, st: BStyle, col: Color, sw: f32) Error!void {
        const s = b.s;
        switch (st) {
            .dashed, .dotted => {
                const path = b.path;
                path.reset();
                try b.rrect(path, @trunc(s.bw[T] * 0.5), @trunc(s.bw[R] * 0.5), @trunc(s.bw[Bo] * 0.5), @trunc(s.bw[L] * 0.5));
                if (path.isEmpty()) return;
                const length = @trunc(pathLength(path));
                const dashed = st == .dashed or s.bw[side] <= 3;
                try b.stroke(if (dashed) sw * 2.2 else s.bw[side], dashPattern(st, s.bw[side], length, true), col);
            },
            .double => {
                const saved = b.d.depth();
                try b.clipInset(b.stripe(2.0 / 3.0), false);
                try b.fillBox(col);
                b.d.restore(saved);
                try b.clipInset(b.stripe(1.0 / 3.0), true);
                try b.fillBox(col);
                b.d.restore(saved);
            },
            .groove, .ridge => {
                const darken = darkenedBy(side, if (st == .groove) .inset else .outset);
                try b.fillBox(insetOutset(col, darken));
                const saved = b.d.depth();
                try b.clipInset(.{ @trunc(s.bw[T] * 0.5), @trunc(s.bw[R] * 0.5), @trunc(s.bw[Bo] * 0.5), @trunc(s.bw[L] * 0.5) }, false);
                try b.fillBox(insetOutset(col, !darken));
                b.d.restore(saved);
            },
            .inset, .outset => try b.fillBox(insetOutset(col, darkenedBy(side, st))),
            else => try b.fillBox(col),
        }
    }

    /// takumi `paint_opacity_groups`.
    fn groups(b: *B, sides: []const u8, opacity: f32, completed: *[4]bool) Error!void {
        if (sides.len == 0) return;
        const s = b.s;
        const a8 = s.col[sides[sides.len - 1]].a;
        var gi = sides.len - 1;
        while (gi > 0 and s.col[sides[gi - 1]].a == a8) gi -= 1;
        const group = sides[gi..];
        const rest = sides[0..gi];
        const alpha = @as(f32, @floatFromInt(a8)) / 255.0;
        var adjacent = false;
        for (group) |x| for (group) |y| {
            if ((x + 1) % 4 == y) adjacent = true;
        };
        const layered = a8 != 255 and (adjacent or rest.len > 0);
        if (!layered) {
            try b.groups(rest, opacity, completed);
            for (group) |side| {
                var c = s.col[side];
                c.a = @intFromFloat(std.math.clamp(@round(alpha / opacity * 255.0), 0, 255));
                try b.paintSide(side, c, completed);
                completed[side] = true;
            }
            return;
        }
        b.d.beginLayer(alpha / opacity);
        try b.groups(rest, alpha, completed);
        for (group) |side| {
            var c = s.col[side];
            c.a = 255;
            try b.paintSide(side, c, completed);
            completed[side] = true;
        }
        b.d.endLayer();
    }
};

/// Paints the border described by `spec_in` (takumi `BoxBorderPainter::paint`).
pub fn paintSpec(d: *Device, spec_in: *const Spec) Error!void {
    var s = spec_in.*;
    if (!(s.w > 0) or !(s.h > 0)) return;
    var painted: [4]u8 = undefined;
    var np: usize = 0;
    var first_vis: ?usize = null;
    var uniform_color = true;
    for (0..4) |i| {
        if (s.st[i] == .none or s.st[i] == .hidden or !(s.bw[i] > 0)) {
            s.bw[i] = 0;
            continue;
        }
        s.st[i] = effective(s.st[i], s.bw[i]);
        if (first_vis) |fv| {
            if (!s.col[fv].eql(s.col[i])) uniform_color = false;
        } else first_vis = i;
        if (s.col[i].a != 0) {
            painted[np] = @intCast(i);
            np += 1;
        }
    }
    if (np == 0) return;
    var p1: Path = .empty;
    var p2: Path = .empty;
    var b: B = .{
        .d = d,
        .a = d.a,
        .s = &s,
        .path = &p1,
        .path2 = &p2,
        .inner_radii = shrinkRadii(s.radii, s.bw[T], s.bw[R], s.bw[Bo], s.bw[L]),
        .rounded = pm.hasAnyRadius(s.radii),
        .inner_renderable = true,
    };
    const saved = d.depth();
    defer d.restore(saved);
    const iw = s.w - s.bw[L] - s.bw[R];
    const ih = s.h - s.bw[T] - s.bw[Bo];
    {
        const ir = b.inner_radii;
        const lim: f32 = 1.0001;
        if (ir[0][0] + ir[1][0] > iw * lim or ir[3][0] + ir[2][0] > iw * lim or ir[0][1] + ir[3][1] > ih * lim or ir[1][1] + ir[2][1] > ih * lim) b.inner_renderable = false;
    }
    var same_style = true;
    for (painted[1..np]) |i| {
        if (s.st[i] != s.st[painted[0]]) same_style = false;
    }
    const st0 = s.st[painted[0]];
    const col0 = s.col[painted[0]];
    if (uniform_color and same_style and b.inner_renderable) {
        const path = b.path2;
        if (st0 == .solid and np == 4) {
            if (!b.rounded) {
                // the ring as one even-odd path (takumi fills the outer and inner rectangles)
                path.reset();
                try b.rrect(path, 0, 0, 0, 0);
                try b.rrect(path, s.bw[T], s.bw[R], s.bw[Bo], s.bw[L]);
                return b.fill(path, .evenodd, col0);
            }
            path.reset();
            try b.rrect(path, 0, 0, 0, 0);
            try b.rrect(path, s.bw[T], s.bw[R], s.bw[Bo], s.bw[L]);
            return b.fill(path, .evenodd, col0);
        }
        if (st0 == .double and np == 4) {
            const s1 = b.stripe(1.0 / 3.0);
            const s2 = b.stripe(2.0 / 3.0);
            path.reset();
            try b.rrect(path, 0, 0, 0, 0);
            try b.rrect(path, s1[0], s1[1], s1[2], s1[3]);
            try b.fill(path, .evenodd, col0);
            path.reset();
            try b.rrect(path, s2[0], s2[1], s2[2], s2[3]);
            try b.rrect(path, s.bw[T], s.bw[R], s.bw[Bo], s.bw[L]);
            return b.fill(path, .evenodd, col0);
        }
        if (st0 == .solid and !b.rounded and col0.a != 255) {
            path.reset();
            for (painted[0..np]) |i| {
                const r: Rect = switch (i) {
                    T => .{ .x = 0, .y = 0, .w = s.w, .h = s.bw[T] },
                    Bo => .{ .x = 0, .y = s.h - s.bw[Bo], .w = s.w, .h = s.bw[Bo] },
                    L => .{ .x = 0, .y = 0, .w = s.bw[L], .h = s.h },
                    else => .{ .x = s.w - s.bw[R], .y = 0, .w = s.bw[R], .h = s.h },
                };
                path.addRect(b.a, r) catch return error.OutOfMemory;
            }
            return b.fill(path, .nonzero, col0);
        }
    }
    // slow path
    if (b.rounded) {
        const path = b.path;
        path.reset();
        try b.rrect(path, 0, 0, 0, 0);
        b.pushClip(path, false);
        if (b.inner_renderable and iw > 0 and ih > 0) {
            path.reset();
            try b.rrect(path, s.bw[T], s.bw[R], s.bw[Bo], s.bw[L]);
            b.pushClip(path, true);
        }
    }
    var i: usize = 1;
    while (i < np) : (i += 1) {
        const it = painted[i];
        var j = i;
        while (j > 0 and sortKey(&s, painted[j - 1]) > sortKey(&s, it)) : (j -= 1) painted[j] = painted[j - 1];
        painted[j] = it;
    }
    var completed: [4]bool = .{ true, true, true, true };
    for (painted[0..np]) |x| completed[x] = false;
    try b.groups(painted[0..np], 1, &completed);
}

fn sortKey(s: *const Spec, side: u8) u32 {
    return (@as(u32, s.col[side].a) << 8) | (@as(u32, styleRank(s.st[side])) << 4) | side_rank[side];
}

/// The element's border at its geometry `g`.
pub fn paintBorder(d: *Device, cs: *const CS, g: *const Geom) Error!void {
    const bw = g.bw;
    if (bw[0] <= 0 and bw[1] <= 0 and bw[2] <= 0 and bw[3] <= 0) return;
    var spec: Spec = .{ .x = g.bx.x, .y = g.bx.y, .w = g.bx.w, .h = g.bx.h, .bw = bw, .st = cs.border_style, .col = undefined, .radii = if (g.rounded) g.radii else pm.zero_radii };
    for (0..4) |i| spec.col[i] = cs.resolveColor(cs.border_color[i]);
    try paintSpec(d, &spec);
}

/// Whether a `background-clip: border-area` border leaves gaps (a dotted, dashed or double side),
/// so the background goes through a mask of the painted border (takumi `border_mask`, after
/// Blink's `AllBordersFillBorderArea`).
pub fn borderAreaGaps(cs: *const CS, g: *const Geom) bool {
    for (0..4) |i| {
        if (g.bw[i] > 0 and (cs.border_style[i] == .dotted or cs.border_style[i] == .dashed or cs.border_style[i] == .double)) return true;
    }
    return false;
}

/// The element's border at `g` in opaque black on every side (the `border-area` mask).
pub fn paintBorderMask(d: *Device, cs: *const CS, g: *const Geom) Error!void {
    var spec: Spec = .{ .x = g.bx.x, .y = g.bx.y, .w = g.bx.w, .h = g.bx.h, .bw = g.bw, .st = cs.border_style, .col = undefined, .radii = if (g.rounded) g.radii else pm.zero_radii };
    for (0..4) |i| spec.col[i] = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    try paintSpec(d, &spec);
}

/// One side painted as a straight box side (collapsed table borders, painter `paintSideRect`).
pub fn paintSideRect(d: *Device, side: usize, x1: f32, y1: f32, x2: f32, y2: f32, st: BStyle, col: Color) Error!void {
    if (st == .none or st == .hidden or col.a == 0) return;
    var spec: Spec = .{ .x = 0, .y = 0, .w = 1, .h = 1, .bw = .{ 0, 0, 0, 0 }, .st = .{ st, st, st, st }, .col = .{ col, col, col, col }, .radii = pm.zero_radii };
    var p1: Path = .empty;
    var p2: Path = .empty;
    var b: B = .{ .d = d, .a = d.a, .s = &spec, .path = &p1, .path2 = &p2, .inner_radii = pm.zero_radii, .rounded = false, .inner_renderable = true };
    try b.rectPaint(side, x1, y1, x2, y2, st, col, 0, 0, 0);
}

fn snapWidth(v: f32) f32 {
    const t = @trunc(v);
    if (t == 0 and v != 0) return if (v > 0) 1 else -1;
    return t;
}

/// Outline ring around the border box `g` (takumi `OutlineGeometry`), painted as a uniform border.
pub fn paintOutline(d: *Device, cs: *const CS, g: *const Geom) Error!void {
    if (cs.outline_style == .none or cs.outline_style == .hidden) return;
    const width = @max(snapWidth(cs.outline_width), 0);
    if (!(width > 0)) return;
    const col = cs.resolveColor(cs.outline_color);
    if (col.a == 0) return;
    const offset = snapWidth(cs.outline_offset);
    const min_grow = @min(@max(2 * width - g.bx.w, 2 * width - g.bx.h), 0) / 2;
    const grow = @max(offset + width, min_grow);
    var spec: Spec = .{
        .x = g.bx.x - grow,
        .y = g.bx.y - grow,
        .w = g.bx.w + 2 * grow,
        .h = g.bx.h + 2 * grow,
        .bw = .{ width, width, width, width },
        .st = .{ cs.outline_style, cs.outline_style, cs.outline_style, cs.outline_style },
        .col = .{ col, col, col, col },
        .radii = pm.resolveRadiiRaw(cs, g.bx.w, g.bx.h),
    };
    for (&spec.radii) |*c| {
        if (c[0] > 0) c[0] = @max(c[0] + grow, 0);
        if (c[1] > 0) c[1] = @max(c[1] + grow, 0);
        if (c[0] <= 0 or c[1] <= 0) c.* = .{ 0, 0 };
    }
    pm.scaleRadii(&spec.radii, spec.w, spec.h);
    try paintSpec(d, &spec);
}

// ---------------------------------------------------------------------------------------------
// inline outlines (takumi `layout/inline/outline.rs`, `painter/outline.rs`, after Blink's
// `OutlinePainter`)
// ---------------------------------------------------------------------------------------------

/// One line fragment of an outlined inline element: its border box (unsnapped, relative to the
/// paragraph), the element (`owner`, unique within the paragraph) and the line it sits on.
pub const InlineOutlineRect = struct {
    owner: u64,
    line: u32,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    cs: *const CS,

    /// Blink's `ToPixelSnappedRect`: left, top, right, bottom.
    pub fn snapped(r: InlineOutlineRect) [4]f32 {
        const s = pm.snapRect(r.x, r.y, r.w, r.h);
        return .{ s.x, s.y, s.x + s.w, s.y + s.h };
    }

    /// The snapped rect grown by `offset` (no further in than half its size), then by `outset`.
    pub fn grown(r: InlineOutlineRect, offset: f32, outset: f32) [4]f32 {
        const s = r.snapped();
        const hz = @max(offset, -@trunc((s[2] - s[0]) / 2)) + outset;
        const vt = @max(offset, -@trunc((s[3] - s[1]) / 2)) + outset;
        return .{ s[0] - hz, s[1] - vt, s[2] + hz, s[3] + vt };
    }

    /// Whether the two rects meet once each grows as its outline paints.
    fn meets(a: InlineOutlineRect, b: InlineOutlineRect) bool {
        const p = outlinePainted(a.cs);
        const ga = a.grown(p[1], p[0]);
        const gb = b.grown(p[1], p[0]);
        return ga[0] <= gb[2] and gb[0] <= ga[2] and ga[1] <= gb[3] and gb[1] <= ga[3];
    }
};

/// Whether an element paints an inline outline (takumi `InlineOutline::of`).
pub fn hasInlineOutline(cs: *const CS) bool {
    if (cs.outline_style == .none or cs.outline_style == .hidden) return false;
    if (!(cs.outline_width > 0)) return false;
    return cs.resolveColor(cs.outline_color).a != 0;
}

/// `InlineOutline::painted`: the width and offset in whole pixels.
fn outlinePainted(cs: *const CS) [2]f32 {
    return .{ @trunc(@max(cs.outline_width, 0)), @trunc(cs.outline_offset) };
}

/// takumi `OutlineIsland::of` + `paint`: groups the rects (each element's fragments in line
/// order) into islands of fragments on consecutive lines that meet, and paints each at
/// (`ox`, `oy`): a lone fragment of its element as a box outline, an island as one right-angle
/// contour (`ComplexOutline`).
pub fn paintInlineOutlines(d: *Device, rects: []const InlineOutlineRect, ox: f32, oy: f32) Error!void {
    var i: usize = 0;
    while (i < rects.len) {
        var j = i + 1;
        while (j < rects.len and rects[j].owner == rects[j - 1].owner and rects[j - 1].line + 1 == rects[j].line and rects[j - 1].meets(rects[j])) j += 1;
        var count: usize = 0;
        for (rects) |r| count += @intFromBool(r.owner == rects[i].owner);
        try paintIsland(d, rects[i..j], count == 1, ox, oy);
        i = j;
    }
}

fn paintIsland(d: *Device, island: []const InlineOutlineRect, lone: bool, ox: f32, oy: f32) Error!void {
    const cs = island[0].cs;
    const p = outlinePainted(cs);
    const width = p[0];
    const offset = p[1];
    const opacity = std.math.clamp(cs.opacity, 0, 1);
    if (!(opacity > 0) or !(width > 0)) return;
    if (opacity < 1) d.beginLayer(opacity);
    defer if (opacity < 1) d.endLayer();
    if (lone) {
        const s = island[0].snapped();
        var g: Geom = undefined;
        g.bx = .{ .x = ox + s[0], .y = oy + s[1], .w = s[2] - s[0], .h = s[3] - s[1] };
        return paintOutline(d, cs, &g);
    }
    const a = d.a;
    var grown: std.ArrayList([4]f32) = .empty;
    for (island) |r| {
        const gr = r.grown(offset, width);
        if (gr[0] < gr[2] and gr[1] < gr[3]) try grown.append(a, gr);
    }
    const outer = (try RightAngleContour.ofRects(a, grown.items)) orelse return;
    const inner = try outer.shrunk(a, width);
    const col = cs.resolveColor(cs.outline_color);
    const radii = pm.resolveRadiiRaw(cs, island[0].w, island[0].h);
    var rounded = false;
    for (radii) |r| rounded = rounded or (r[0] > 0 and r[1] > 0);
    if (cs.outline_style != .solid or rounded) return @import("emit_outline.zig").paint(d, outer, width, offset, cs.outline_style, col, if (rounded) radii else null, ox, oy);
    // the outer contour clips, the inner one clips out within the outline's bounds, and the
    // bounds are filled (Blink's solid square `ComplexOutlinePainter`)
    var path: Path = .empty;
    try outer.addTo(a, &path, ox, oy);
    d.pushClip(&path, 0, 0, .nonzero);
    defer d.popClip();
    const b = outer.bounds();
    var out: Path = .empty;
    try inner.addTo(a, &out, ox, oy);
    try out.moveTo(a, ox + b[0], oy + b[1]);
    try out.lineTo(a, ox + b[0], oy + b[3]);
    try out.lineTo(a, ox + b[2], oy + b[3]);
    try out.lineTo(a, ox + b[2], oy + b[1]);
    try out.close(a);
    d.pushClip(&out, 0, 0, .nonzero);
    defer d.popClip();
    d.fillRRect(.{ .x = ox + b[0], .y = oy + b[1], .w = b[2] - b[0], .h = b[3] - b[1] }, null, col);
}

/// A clockwise contour turning a right angle at every corner (takumi `RightAngleContour`).
pub const RightAngleContour = struct {
    corners: []const Pt,

    /// The contour around the union of `rects` (left, top, right, bottom), band by band down the
    /// page (takumi `union_outline` + `RightAngleContour::of`); null when it encloses nothing.
    pub fn ofRects(a: std.mem.Allocator, rects: []const [4]f32) Error!?RightAngleContour {
        var edges: std.ArrayList(f32) = .empty;
        for (rects) |r| try edges.appendSlice(a, &.{ r[1], r[3] });
        std.mem.sort(f32, edges.items, {}, std.sort.asc(f32));
        var bands: std.ArrayList([4]f32) = .empty;
        var k: usize = 0;
        while (k + 1 < edges.items.len) : (k += 1) {
            const top = edges.items[k];
            const bottom = edges.items[k + 1];
            if (top == bottom) continue;
            var left: f32 = std.math.inf(f32);
            var right: f32 = -std.math.inf(f32);
            var any = false;
            for (rects) |r| if (r[1] < bottom and r[3] > top) {
                left = @min(left, r[0]);
                right = @max(right, r[2]);
                any = true;
            };
            if (any) try bands.append(a, .{ left, top, right, bottom });
        }
        if (bands.items.len == 0) return null;
        var corners: std.ArrayList(Pt) = .empty;
        try corners.append(a, .{ bands.items[0][0], bands.items[0][1] });
        for (bands.items) |bd| try corners.appendSlice(a, &.{ .{ bd[2], bd[1] }, .{ bd[2], bd[3] } });
        var bi = bands.items.len;
        while (bi > 0) {
            bi -= 1;
            const bd = bands.items[bi];
            try corners.appendSlice(a, &.{ .{ bd[0], bd[3] }, .{ bd[0], bd[1] } });
        }
        const kept = try rightAngleCorners(a, corners.items);
        if (kept.len < 4) return null;
        return .{ .corners = kept };
    }

    fn at(c: RightAngleContour, i: usize) Pt {
        return c.corners[i % c.corners.len];
    }

    /// Blink's `ShrinkRightAnglePath`.
    pub fn shrunk(c: RightAngleContour, a: std.mem.Allocator, inset: f32) Error!RightAngleContour {
        const n = c.corners.len;
        const out = try a.alloc(Pt, n);
        for (0..n) |i| {
            const prev = c.at(i + n - 1);
            const cur = c.at(i);
            const next = c.at(i + 1);
            var dx: f32 = undefined;
            var dy: f32 = undefined;
            if (prev[0] == cur[0]) {
                dx = if (prev[1] < cur[1]) -inset else inset;
                dy = if (cur[0] < next[0]) inset else -inset;
            } else {
                dx = if (cur[1] < next[1]) -inset else inset;
                dy = if (prev[0] < cur[0]) inset else -inset;
            }
            out[i] = .{ cur[0] + dx, cur[1] + dy };
        }
        return .{ .corners = out };
    }

    /// The rect around the contour: left, top, right, bottom.
    pub fn bounds(c: RightAngleContour) [4]f32 {
        var r = [4]f32{ c.corners[0][0], c.corners[0][1], c.corners[0][0], c.corners[0][1] };
        for (c.corners) |q| {
            r[0] = @min(r[0], q[0]);
            r[1] = @min(r[1], q[1]);
            r[2] = @max(r[2], q[0]);
            r[3] = @max(r[3], q[1]);
        }
        return r;
    }

    /// The contour as a closed path, offset by (`ox`, `oy`).
    pub fn addTo(c: RightAngleContour, a: std.mem.Allocator, p: *Path, ox: f32, oy: f32) Error!void {
        try p.moveTo(a, ox + c.corners[0][0], oy + c.corners[0][1]);
        for (c.corners[1..]) |q| try p.lineTo(a, ox + q[0], oy + q[1]);
        try p.close(a);
    }
};

/// takumi `right_angle_corners`: `corners` without repeated points or points in the middle of a
/// straight run.
fn rightAngleCorners(a: std.mem.Allocator, corners: []const Pt) Error![]const Pt {
    const straight = struct {
        fn f(p: Pt, q: Pt, r: Pt) bool {
            return (q[0] == p[0] and q[1] == p[1]) or (p[0] == q[0] and q[0] == r[0]) or (p[1] == q[1] and q[1] == r[1]);
        }
    }.f;
    var kept: std.ArrayList(Pt) = .empty;
    for (corners) |q| {
        while (kept.items.len >= 2 and straight(kept.items[kept.items.len - 2], kept.items[kept.items.len - 1], q)) kept.items.len -= 1;
        const n = kept.items.len;
        if (n == 0 or kept.items[n - 1][0] != q[0] or kept.items[n - 1][1] != q[1]) try kept.append(a, q);
    }
    while (kept.items.len > 4) {
        const n = kept.items.len;
        if (straight(kept.items[n - 2], kept.items[n - 1], kept.items[0])) {
            kept.items.len -= 1;
        } else if (straight(kept.items[n - 1], kept.items[0], kept.items[1])) {
            _ = kept.orderedRemove(0);
        } else break;
    }
    return kept.items;
}

test "inline outline contour: two wrapped fragments" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // a fragment ending line 1 at the right, one starting line 2 at the left, overlapping in x
    const c = (try RightAngleContour.ofRects(a, &.{ .{ 40, 0, 100, 20 }, .{ 0, 20, 60, 40 } })).?;
    try t.expectEqualSlices(Pt, &.{ .{ 40, 0 }, .{ 100, 0 }, .{ 100, 20 }, .{ 60, 20 }, .{ 60, 40 }, .{ 0, 40 }, .{ 0, 20 }, .{ 40, 20 } }, c.corners);
    const s = try c.shrunk(a, 2);
    try t.expectEqualSlices(Pt, &.{ .{ 42, 2 }, .{ 98, 2 }, .{ 98, 18 }, .{ 58, 18 }, .{ 58, 38 }, .{ 2, 38 }, .{ 2, 22 }, .{ 42, 22 } }, s.corners);
    try t.expectEqual([4]f32{ 0, 0, 100, 40 }, c.bounds());
    // a single rect: its four corners
    const r = (try RightAngleContour.ofRects(a, &.{.{ 1, 2, 3, 4 }})).?;
    try t.expectEqual(@as(usize, 4), r.corners.len);
}
