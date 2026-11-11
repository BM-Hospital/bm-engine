//! Path storage (unmanaged: every appending method takes the allocator).
const std = @import("std");
const types = @import("types.zig");
const Point = types.Point;
const Rect = types.Rect;
const Affine = types.Affine;
const Allocator = std.mem.Allocator;

pub const Verb = enum(u8) { move, line, quad, cubic, close };

/// Control-point distance factor for approximating a quarter ellipse with one cubic.
const KAPPA: f32 = 0.5522847498;

pub const Path = struct {
    verbs: std.ArrayList(Verb) = .empty,
    points: std.ArrayList(Point) = .empty,

    pub const empty: Path = .{};

    pub fn deinit(self: *Path, alloc: Allocator) void {
        self.verbs.deinit(alloc);
        self.points.deinit(alloc);
        self.* = .{};
    }

    /// Clears the path but keeps the allocated capacity.
    pub fn reset(self: *Path) void {
        self.verbs.clearRetainingCapacity();
        self.points.clearRetainingCapacity();
    }

    pub fn isEmpty(self: *const Path) bool {
        return self.verbs.items.len == 0;
    }

    pub fn moveTo(self: *Path, alloc: Allocator, x: f32, y: f32) !void {
        try self.verbs.append(alloc, .move);
        try self.points.append(alloc, .{ .x = x, .y = y });
    }

    pub fn lineTo(self: *Path, alloc: Allocator, x: f32, y: f32) !void {
        try self.verbs.append(alloc, .line);
        try self.points.append(alloc, .{ .x = x, .y = y });
    }

    pub fn quadTo(self: *Path, alloc: Allocator, cx: f32, cy: f32, x: f32, y: f32) !void {
        try self.points.ensureUnusedCapacity(alloc, 2);
        try self.verbs.append(alloc, .quad);
        self.points.appendAssumeCapacity(.{ .x = cx, .y = cy });
        self.points.appendAssumeCapacity(.{ .x = x, .y = y });
    }

    pub fn cubicTo(self: *Path, alloc: Allocator, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) !void {
        try self.points.ensureUnusedCapacity(alloc, 3);
        try self.verbs.append(alloc, .cubic);
        self.points.appendAssumeCapacity(.{ .x = c1x, .y = c1y });
        self.points.appendAssumeCapacity(.{ .x = c2x, .y = c2y });
        self.points.appendAssumeCapacity(.{ .x = x, .y = y });
    }

    pub fn close(self: *Path, alloc: Allocator) !void {
        try self.verbs.append(alloc, .close);
    }

    /// Bounding box of all control points (conservative for curves). Zero rect when empty.
    pub fn bounds(self: *const Path) Rect {
        const pts = self.points.items;
        if (pts.len == 0) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        var x0 = pts[0].x;
        var y0 = pts[0].y;
        var x1 = x0;
        var y1 = y0;
        for (pts[1..]) |p| {
            x0 = @min(x0, p.x);
            y0 = @min(y0, p.y);
            x1 = @max(x1, p.x);
            y1 = @max(y1, p.y);
        }
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    /// Clockwise (y-down) closed rectangle.
    pub fn addRect(self: *Path, alloc: Allocator, r: Rect) !void {
        try self.verbs.ensureUnusedCapacity(alloc, 5);
        try self.points.ensureUnusedCapacity(alloc, 4);
        self.verbs.appendSliceAssumeCapacity(&.{ .move, .line, .line, .line, .close });
        self.points.appendSliceAssumeCapacity(&.{
            .{ .x = r.x, .y = r.y },
            .{ .x = r.x + r.w, .y = r.y },
            .{ .x = r.x + r.w, .y = r.y + r.h },
            .{ .x = r.x, .y = r.y + r.h },
        });
    }

    fn corner(self: *Path, alloc: Allocator, from: Point, c: Point, to: Point) !void {
        if (from.x == to.x and from.y == to.y) return;
        try self.cubicTo(
            alloc,
            from.x + (c.x - from.x) * KAPPA,
            from.y + (c.y - from.y) * KAPPA,
            to.x + (c.x - to.x) * KAPPA,
            to.y + (c.y - to.y) * KAPPA,
            to.x,
            to.y,
        );
    }

    /// Clockwise closed rounded rectangle. `radii` order: top-left, top-right, bottom-right,
    /// bottom-left; each `[rx, ry]`. The caller pre-clamps radii (CSS overlap rule).
    pub fn addRoundRect(self: *Path, alloc: Allocator, r: Rect, radii: [4][2]f32) !void {
        const x0 = r.x;
        const y0 = r.y;
        const x1 = r.x + r.w;
        const y1 = r.y + r.h;
        var rr: [4][2]f32 = radii;
        for (&rr) |*c| {
            // a corner with one zero (or invalid) radius is square
            if (!(c[0] > 0) or !(c[1] > 0)) c.* = .{ 0, 0 };
        }
        try self.verbs.ensureUnusedCapacity(alloc, 10);
        try self.points.ensureUnusedCapacity(alloc, 17);
        try self.moveTo(alloc, x0 + rr[0][0], y0);
        try self.lineTo(alloc, x1 - rr[1][0], y0);
        try self.corner(alloc, .{ .x = x1 - rr[1][0], .y = y0 }, .{ .x = x1, .y = y0 }, .{ .x = x1, .y = y0 + rr[1][1] });
        try self.lineTo(alloc, x1, y1 - rr[2][1]);
        try self.corner(alloc, .{ .x = x1, .y = y1 - rr[2][1] }, .{ .x = x1, .y = y1 }, .{ .x = x1 - rr[2][0], .y = y1 });
        try self.lineTo(alloc, x0 + rr[3][0], y1);
        try self.corner(alloc, .{ .x = x0 + rr[3][0], .y = y1 }, .{ .x = x0, .y = y1 }, .{ .x = x0, .y = y1 - rr[3][1] });
        try self.lineTo(alloc, x0, y0 + rr[0][1]);
        try self.corner(alloc, .{ .x = x0, .y = y0 + rr[0][1] }, .{ .x = x0, .y = y0 }, .{ .x = x0 + rr[0][0], .y = y0 });
        try self.close(alloc);
    }

    /// Clockwise closed ellipse inscribed in `r`.
    pub fn addEllipse(self: *Path, alloc: Allocator, r: Rect) !void {
        const rx = r.w * 0.5;
        const ry = r.h * 0.5;
        try self.addRoundRect(alloc, r, .{ .{ rx, ry }, .{ rx, ry }, .{ rx, ry }, .{ rx, ry } });
    }

    /// Appends `other` transformed by `t`.
    pub fn addPath(self: *Path, alloc: Allocator, other: *const Path, t: Affine) !void {
        try self.verbs.appendSlice(alloc, other.verbs.items);
        try self.points.ensureUnusedCapacity(alloc, other.points.items.len);
        for (other.points.items) |p| self.points.appendAssumeCapacity(t.apply(p));
    }
};

/// Duck-typed outline sink for the font module: `moveTo/lineTo/quadTo/cubicTo/close` return
/// void; coordinates are mapped through `transform`; allocation failure is recorded in `err`.
pub const PathSink = struct {
    path: *Path,
    alloc: Allocator,
    transform: Affine = Affine.identity,
    err: bool = false,

    pub fn moveTo(self: *PathSink, x: f32, y: f32) void {
        const p = self.transform.apply(.{ .x = x, .y = y });
        self.path.moveTo(self.alloc, p.x, p.y) catch {
            self.err = true;
        };
    }

    pub fn lineTo(self: *PathSink, x: f32, y: f32) void {
        const p = self.transform.apply(.{ .x = x, .y = y });
        self.path.lineTo(self.alloc, p.x, p.y) catch {
            self.err = true;
        };
    }

    pub fn quadTo(self: *PathSink, cx: f32, cy: f32, x: f32, y: f32) void {
        const c = self.transform.apply(.{ .x = cx, .y = cy });
        const p = self.transform.apply(.{ .x = x, .y = y });
        self.path.quadTo(self.alloc, c.x, c.y, p.x, p.y) catch {
            self.err = true;
        };
    }

    pub fn cubicTo(self: *PathSink, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) void {
        const c1 = self.transform.apply(.{ .x = c1x, .y = c1y });
        const c2 = self.transform.apply(.{ .x = c2x, .y = c2y });
        const p = self.transform.apply(.{ .x = x, .y = y });
        self.path.cubicTo(self.alloc, c1.x, c1.y, c2.x, c2.y, p.x, p.y) catch {
            self.err = true;
        };
    }

    pub fn close(self: *PathSink) void {
        self.path.close(self.alloc) catch {
            self.err = true;
        };
    }
};
