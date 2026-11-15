//! Multi-fragment outline islands (Takumi/Blink ComplexOutlinePainter).
//! Right-angle contour construction stays in emit_border; this handles style and rounded corners.
//! Blink's algorithm is covered by the Chromium notice in THIRD-PARTY-NOTICES.md.
const std = @import("std");
const border = @import("emit_border.zig");
const dev = @import("emit_device.zig");
const pm = @import("../paint.zig");
const pb = @import("../paint_border.zig");
const raster = @import("../raster/raster.zig");
const style = @import("../style/style.zig");
const Error = @import("../render.zig").Error;
const Path = raster.Path;
const Pt = [2]f32;
const Contour = border.RightAngleContour;
const Radii = pm.Radii;
const K: f32 = (4.0 / 3.0) * (@as(f32, std.math.sqrt2) - 1);

pub fn paint(d: *dev.Device, outer: Contour, width: f32, offset: f32, st_in: style.computed.BorderStyle, col_in: style.Color, radius: ?Radii, ox: f32, oy: f32) Error!void {
    var st = st_in;
    var col = col_in;
    if (st == .double and width <= 2) st = .solid;
    if ((st == .groove or st == .ridge) and width == 1) {
        st = .solid;
        const shade = dark(col);
        col.r = @intCast((@as(u16, col.r) + shade.r + 1) / 2);
        col.g = @intCast((@as(u16, col.g) + shade.g + 1) / 2);
        col.b = @intCast((@as(u16, col.b) + shade.b + 1) / 2);
    }
    const alpha = col.a < 255 and st != .solid and st != .double;
    if (alpha) {
        d.beginLayer(@as(f32, @floatFromInt(col.a)) / 255);
        col.a = 255;
    }
    defer if (alpha) d.endLayer();
    var p: Painter = .{ .d = d, .outer = outer, .width = width, .offset = offset, .radius = radius, .ox = ox, .oy = oy };
    const inner = try outer.shrunk(d.a, width);
    var path = try p.makePath(outer, width, 0);
    d.pushClip(&path, 0, 0, .nonzero);
    defer d.popClip();
    path = try p.clipOut(try p.makePath(inner, 0, width));
    d.pushClip(&path, 0, 0, .nonzero);
    defer d.popClip();
    switch (st) {
        .double => {
            const third = @round(width / 3);
            const near_inner = try outer.shrunk(d.a, width - third);
            const near_outer = try outer.shrunk(d.a, third);
            path = try p.makePath(near_inner, third, width - third);
            d.fillPath(&path, 0, 0, .nonzero, col);
            path = try p.clipOut(try p.makePath(near_outer, width - third, third));
            d.pushClip(&path, 0, 0, .nonzero);
            defer d.popClip();
            p.fillBounds(col);
        },
        .dotted, .dashed => {
            const thickness = p.strokeWidth(st == .dashed or width <= 3);
            const center = try p.centerPath(false);
            if (radius != null) {
                path = try p.makePath(center.contour, center.inset, center.inset);
                const dash = pb.dashPattern(st, width, @trunc(pathLength(&path)), true);
                d.strokePath(&path, 0, 0, thickness, if (dash) |x| .{ x.on, x.off } else null, if (dash) |x| x.round else false, col);
            } else for (center.contour.corners, 0..) |start, i| try p.edge(start, at(center.contour, i + 1), thickness, st, col);
        },
        .inset, .outset => try p.insetOutset(st == .inset, col),
        .groove, .ridge => {
            const groove = st == .groove;
            const center = try p.centerPath(false);
            try p.insetOutset(groove, col);
            path = try p.makePath(center.contour, center.inset, center.inset);
            d.pushClip(&path, 0, 0, .nonzero);
            defer d.popClip();
            try p.edges(!groove, dark(col));
            const odd = @as(i32, @intFromFloat(width)) & 1 != 0;
            if (odd) {
                const outer_center = try p.centerPath(true);
                path = try p.makePath(outer_center.contour, outer_center.inset, outer_center.inset);
                d.pushClip(&path, 0, 0, .nonzero);
            }
            defer if (odd) d.popClip();
            try p.edges(groove, col);
        },
        else => p.fillBounds(col),
    }
}

fn at(c: Contour, i: usize) Pt {
    return c.corners[i % c.corners.len];
}
fn before(c: Contour, i: usize) Pt {
    return at(c, i + c.corners.len - 1);
}
fn grown(radii: Radii, by: f32) Radii {
    var out = radii;
    for (&out) |*r| {
        if (r[0] > 0) r[0] = @max(0, r[0] + by);
        if (r[1] > 0) r[1] = @max(0, r[1] + by);
    }
    return out;
}
fn cornerRadius(convex: Radii, concave: Radii, a: Pt, b: Pt, c: Pt) Pt {
    if (a[0] == b[0]) {
        if (b[1] < a[1]) return if (c[0] > b[0]) convex[0] else concave[1];
        return if (c[0] > b[0]) concave[3] else convex[2];
    }
    if (a[0] < b[0]) return if (c[1] > b[1]) convex[1] else concave[2];
    return if (c[1] > b[1]) concave[0] else convex[3];
}
const Line = struct { start: Pt, end: Pt };
fn step(from: Pt, toward: Pt, by: f32) Pt {
    return .{ from[0] + std.math.sign(toward[0] - from[0]) * by, from[1] + std.math.sign(toward[1] - from[1]) * by };
}
fn roundedLines(a: std.mem.Allocator, c: Contour, convex: Radii, concave: Radii) ![]Line {
    const lines = try a.alloc(Line, c.corners.len);
    for (lines, 0..) |*line, i| {
        const start = at(c, i);
        const end = at(c, i + 1);
        const r0 = cornerRadius(convex, concave, before(c, i), start, end);
        const r1 = cornerRadius(convex, concave, start, end, at(c, i + 2));
        const axis: usize = if (start[0] == end[0]) 1 else 0;
        const length = @abs(end[axis] - start[axis]);
        var near = r0[axis];
        var far = r1[axis];
        if (near + far > length) {
            const ratio = length / (near + far);
            near = @floor(near * ratio);
            far = @floor(far * ratio);
        }
        line.* = .{ .start = step(start, end, near), .end = step(end, start, far) };
    }
    return lines;
}
fn arc(a: std.mem.Allocator, p: *Path, from: Pt, corner: Pt, to: Pt) !void {
    try p.cubicTo(a, from[0] + (corner[0] - from[0]) * K, from[1] + (corner[1] - from[1]) * K, to[0] + (corner[0] - to[0]) * K, to[1] + (corner[1] - to[1]) * K, to[0], to[1]);
}
fn shifted(a: std.mem.Allocator, p: Path, ox: f32, oy: f32) !Path {
    var out: Path = .empty;
    try out.addPath(a, &p, raster.Affine.translate(ox, oy));
    return out;
}

const Painter = struct {
    d: *dev.Device,
    outer: Contour,
    width: f32,
    offset: f32,
    radius: ?Radii,
    ox: f32,
    oy: f32,
    fn makePath(p: *Painter, c: Contour, convex: f32, concave: f32) !Path {
        var out: Path = .empty;
        if (p.radius) |radii| {
            const lines = try roundedLines(p.d.a, c, grown(radii, p.offset + convex), grown(radii, p.offset + concave));
            var current = lines[lines.len - 1].end;
            try out.moveTo(p.d.a, current[0], current[1]);
            for (lines, 0..) |line, i| {
                try arc(p.d.a, &out, current, at(c, i), line.start);
                try out.lineTo(p.d.a, line.end[0], line.end[1]);
                current = line.end;
            }
            try out.close(p.d.a);
        } else try c.addTo(p.d.a, &out, 0, 0);
        return shifted(p.d.a, out, p.ox, p.oy);
    }
    fn clipOut(p: *Painter, path: Path) !Path {
        var out = path;
        const b = p.outer.bounds();
        try out.moveTo(p.d.a, p.ox + b[0], p.oy + b[1]);
        try out.lineTo(p.d.a, p.ox + b[0], p.oy + b[3]);
        try out.lineTo(p.d.a, p.ox + b[2], p.oy + b[3]);
        try out.lineTo(p.d.a, p.ox + b[2], p.oy + b[1]);
        try out.close(p.d.a);
        return out;
    }
    fn fillBounds(p: *Painter, col: style.Color) void {
        const b = p.outer.bounds();
        p.d.fillRRect(.{ .x = p.ox + b[0], .y = p.oy + b[1], .w = b[2] - b[0], .h = b[3] - b[1] }, null, col);
    }
    const Center = struct { contour: Contour, inset: f32 };
    fn centerPath(p: *Painter, prefer_outer: bool) !Center {
        const w: i32 = @intFromFloat(p.width);
        const inset: f32 = @floatFromInt(@divTrunc(w + @as(i32, if (prefer_outer) 0 else 1), 2));
        return .{ .contour = try p.outer.shrunk(p.d.a, p.width - inset), .inset = inset };
    }
    fn strokeWidth(p: *Painter, dashed: bool) f32 {
        return p.width + if (dashed and @as(i32, @intFromFloat(p.width)) & 1 != 0) @as(f32, 2) else 0;
    }
    fn edge(p: *Painter, first: Pt, second: Pt, thickness: f32, st: style.computed.BorderStyle, col: style.Color) !void {
        const horizontal = first[1] == second[1];
        const axis: usize = if (horizontal) 0 else 1;
        const start = if (first[axis] <= second[axis]) first else second;
        const end = if (first[axis] <= second[axis]) second else first;
        const joint = @floor((p.width + 1) / 2);
        const half_pixel: f32 = if (@as(i32, @intFromFloat(@round(thickness))) & 1 != 0) 0.5 else 0;
        const low = @round(start[axis] - joint);
        const high = @round(end[axis] + joint);
        const center_at = @round(start[1 - axis]) + half_pixel;
        if (st == .solid) {
            var path: Path = .empty;
            if (horizontal) {
                try path.moveTo(p.d.a, p.ox + low, p.oy + center_at);
                try path.lineTo(p.d.a, p.ox + high, p.oy + center_at);
            } else {
                try path.moveTo(p.d.a, p.ox + center_at, p.oy + low);
                try path.lineTo(p.d.a, p.ox + center_at, p.oy + high);
            }
            p.d.strokePath(&path, 0, 0, thickness, null, false, col);
            return;
        }
        if (horizontal) try border.paintSideRect(p.d, 0, p.ox + low, p.oy + center_at - thickness / 2, p.ox + high, p.oy + center_at + thickness / 2, st, col) else try border.paintSideRect(p.d, 1, p.ox + center_at - thickness / 2, p.oy + low, p.ox + center_at + thickness / 2, p.oy + high, st, col);
    }
    fn insetOutset(p: *Painter, inset: bool, col: style.Color) !void {
        try p.edges(!inset, col);
        try p.edges(inset, dark(col));
    }
    fn edges(p: *Painter, top_left: bool, col: style.Color) !void {
        const center = try p.centerPath(false);
        const lines = if (p.radius) |r| try roundedLines(p.d.a, center.contour, grown(r, p.offset + center.inset), grown(r, p.offset + center.inset)) else null;
        const c = if (lines != null) p.outer else center.contour;
        const thickness = p.strokeWidth(true);
        const extension = @floor((p.width + 1) / 2);
        for (c.corners, 0..) |start, i| {
            const end = at(c, i + 1);
            if ((start[0] < end[0] or start[1] > end[1]) != top_left) continue;
            const clip = try p.miterClip(before(c, i), start, end, at(c, i + 2));
            p.d.pushClip(&clip.path, 0, 0, clip.rule);
            defer p.d.popClip();
            if (lines) |ls| {
                const line = ls[i];
                const arc_start = ls[(i + ls.len - 1) % ls.len].end;
                const arc_end = ls[(i + 1) % ls.len].start;
                const first_corner = at(center.contour, i);
                const second_corner = at(center.contour, i + 1);
                var path: Path = .empty;
                const from = step(arc_start, if (std.meta.eql(arc_start, line.start)) second_corner else first_corner, -extension);
                try path.moveTo(p.d.a, from[0], from[1]);
                if (!std.meta.eql(arc_start, line.start)) {
                    try path.lineTo(p.d.a, arc_start[0], arc_start[1]);
                    try arc(p.d.a, &path, arc_start, first_corner, line.start);
                }
                try path.lineTo(p.d.a, line.end[0], line.end[1]);
                if (!std.meta.eql(line.end, arc_end)) try arc(p.d.a, &path, line.end, second_corner, arc_end);
                const to = step(arc_end, if (std.meta.eql(line.end, arc_end)) first_corner else second_corner, -extension);
                try path.lineTo(p.d.a, to[0], to[1]);
                path = try shifted(p.d.a, path, p.ox, p.oy);
                p.d.strokePath(&path, 0, 0, thickness, null, false, col);
            } else try p.edge(start, end, thickness, .solid, col);
        }
    }
    const Clip = struct { path: Path, rule: @import("emit_surface.zig").FillRule = .nonzero };
    fn miterClip(p: *Painter, previous: Pt, start: Pt, end: Pt, next: Pt) !Clip {
        const bounds = p.outer.bounds();
        const s0 = slope(previous, start, end);
        const s1 = slope(start, end, next);
        var path: Path = .empty;
        try path.moveTo(p.d.a, start[0] + s0 * (start[1] - bounds[1]), bounds[1]);
        try path.lineTo(p.d.a, end[0] + s1 * (end[1] - bounds[1]), bounds[1]);
        try path.lineTo(p.d.a, end[0] - s1 * (bounds[3] - end[1]), bounds[3]);
        try path.lineTo(p.d.a, start[0] - s0 * (bounds[3] - start[1]), bounds[3]);
        try path.close(p.d.a);
        const inverse = s0 != s1 and start[0] == end[0];
        if (inverse) {
            const reach = bounds[2] - bounds[0] + bounds[3] - bounds[1];
            try path.addRect(p.d.a, .{ .x = bounds[0] - reach, .y = bounds[1] - reach, .w = bounds[2] - bounds[0] + 2 * reach, .h = bounds[3] - bounds[1] + 2 * reach });
        }
        return .{ .path = try shifted(p.d.a, path, p.ox, p.oy), .rule = if (inverse) .even_odd else .nonzero };
    }
};
fn slope(a: Pt, b: Pt, c: Pt) f32 {
    const same = if (a[0] == b[0]) (c[0] > b[0]) == (b[1] > a[1]) else (c[1] > b[1]) == (b[0] > a[0]);
    return if (same) 1 else -1;
}
fn dark(c: style.Color) style.Color {
    var out = c;
    const v = @as(f32, @floatFromInt(@max(c.r, @max(c.g, c.b)))) / 255;
    const scale = if (v == 0) 0 else @max(0, (v - 0.33) / v);
    inline for (.{ "r", "g", "b" }) |name| @field(out, name) = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(@field(c, name))) / 255 * scale * 255.99998, 0, 255));
    return out;
}
fn distance(a: raster.Point, b: raster.Point) f32 {
    const x = b.x - a.x;
    const y = b.y - a.y;
    return @sqrt(x * x + y * y);
}
fn pathLength(path: *const Path) f32 {
    var length: f32 = 0;
    var current: raster.Point = .{ .x = 0, .y = 0 };
    var start = current;
    var index: usize = 0;
    for (path.verbs.items) |verb| switch (verb) {
        .move => {
            current = path.points.items[index];
            start = current;
            index += 1;
        },
        .line => {
            const end = path.points.items[index];
            length += distance(current, end);
            current = end;
            index += 1;
        },
        .close => {
            length += distance(current, start);
            current = start;
        },
        .cubic => {
            const first = path.points.items[index];
            const second = path.points.items[index + 1];
            const end = path.points.items[index + 2];
            var previous = current;
            for (1..17) |i| {
                const t = @as(f32, @floatFromInt(i)) / 16;
                const u = 1 - t;
                const a = u * u * u;
                const b = 3 * u * u * t;
                const c = 3 * u * t * t;
                const d = t * t * t;
                const point: raster.Point = .{ .x = a * current.x + b * first.x + c * second.x + d * end.x, .y = a * current.y + b * first.y + c * second.y + d * end.y };
                length += distance(previous, point);
                previous = point;
            }
            current = end;
            index += 3;
        },
        .quad => {
            current = path.points.items[index + 1];
            index += 2;
        }, // rounded contours contain cubics only
    };
    return length;
}
