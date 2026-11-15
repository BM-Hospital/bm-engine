//! SVG character positioning scopes. Ancestor lists advance through descendant text;
//! a descendant overrides only the entries it supplies, and rotate repeats its last entry.
const std = @import("std");
const num = @import("num.zig");
const dom = @import("dom.zig");

pub const Position = struct {
    byte: u32 = 0,
    x: ?f32 = null,
    y: ?f32 = null,
    dx: f32 = 0,
    dy: f32 = 0,
    rotate: f32 = 0,
    addressed: bool = false,
};

const List = struct {
    reader: num.Reader,
    fn next(l: *List, base: f32, fs: f32) ?f32 {
        l.reader.skipSep();
        const start = l.reader.i;
        _ = l.reader.number() orelse return null;
        _ = l.reader.ident();
        const length = num.parseLength(l.reader.s[start..l.reader.i]) orelse return null;
        return num.resolve(length, base, fs);
    }
};

pub const Scope = struct {
    lists: [5]List,
    last_rotate: ?f32 = null,
    fs: f32,
    pub fn init(n: *const dom.Node, fs: f32) Scope {
        var s: Scope = .{ .lists = undefined, .fs = fs };
        for ([_][]const u8{ "x", "y", "dx", "dy", "rotate" }, 0..) |name, i|
            s.lists[i] = .{ .reader = .{ .s = if (n.tag == .textPath) "" else n.attr(name) orelse "" } };
        return s;
    }
};

pub fn next(scopes: []Scope, width: f32, height: f32) Position {
    var p: Position = .{};
    for (scopes) |*s| {
        if (s.lists[0].next(width, s.fs)) |v| {
            p.x = v;
            p.addressed = true;
        }
        if (s.lists[1].next(height, s.fs)) |v| {
            p.y = v;
            p.addressed = true;
        }
        if (s.lists[2].next(width, s.fs)) |v| {
            p.dx = v;
            p.addressed = true;
        }
        if (s.lists[3].next(height, s.fs)) |v| {
            p.dy = v;
            p.addressed = true;
        }
        if (s.lists[4].next(0, s.fs)) |v| s.last_rotate = v;
        if (s.last_rotate) |v| {
            p.rotate = v;
            p.addressed = true;
        }
    }
    return p;
}

test "SVG text position scopes advance ancestors and repeat rotation" {
    var outer: dom.Node = .{ .tag = .text, .attrs = &.{
        .{ .name = "x", .value = "10,20,30,40" },
        .{ .name = "dx", .value = "1em 2px 3 4" },
        .{ .name = "rotate", .value = "0 15" },
    } };
    var inner: dom.Node = .{ .tag = .tspan, .attrs = &.{.{ .name = "x", .value = "50%" }} };
    var scopes = [_]Scope{ Scope.init(&outer, 12), Scope.init(&inner, 12) };
    const a = next(scopes[0..1], 200, 100);
    try std.testing.expectEqual(@as(?f32, 10), a.x);
    try std.testing.expectEqual(@as(f32, 12), a.dx);
    const b = next(&scopes, 200, 100);
    try std.testing.expectEqual(@as(?f32, 100), b.x);
    try std.testing.expectEqual(@as(f32, 15), b.rotate);
    const c = next(&scopes, 200, 100);
    try std.testing.expectEqual(@as(?f32, 30), c.x);
    try std.testing.expectEqual(@as(f32, 15), c.rotate);
    const d = next(scopes[0..1], 200, 100);
    try std.testing.expectEqual(@as(?f32, 40), d.x);
}
