//! takumi-pdf's `SurfaceDevice` (emitter.rs): the shape-level drawing calls the box painters
//! make (fill / stroke a shape, push a clip or a clip-out, open an opacity layer), mapped onto
//! the krilla surface model (emit_surface.zig), with every colour passed through the subtree's
//! colour `filter` (takumi `filter.rs` / takumi-core `ColorMatrixChain`).
//!
//! Coordinates are absolute (the emitter folds pure translations into them, like takumi's flat
//! transforms); a clip whose shape has no area hides every draw until it is popped.
const std = @import("std");
const style = @import("../style/style.zig");
const raster = @import("../raster/raster.zig");
const render = @import("../render.zig");
const sf = @import("emit_surface.zig");
const geom = @import("emit_geom.zig");

const Allocator = std.mem.Allocator;
const Path = geom.Path;
const Rect = raster.Rect;
const Color = style.Color;
pub const Radii = [4][2]f32;

// ---------------------------------------------------------------------------------------------
// colour filters (takumi-core filter.rs)
// ---------------------------------------------------------------------------------------------

const M = [4][5]f32;

const identity_m: M = .{ .{ 1, 0, 0, 0, 0 }, .{ 0, 1, 0, 0, 0 }, .{ 0, 0, 1, 0, 0 }, .{ 0, 0, 0, 1, 0 } };

fn toRadians(deg: f32) f32 {
    const pi: f32 = std.math.pi;
    return deg * (pi / 180.0);
}

fn scaleM(s: f32, off: f32) M {
    var m = identity_m;
    for (0..3) |i| {
        m[i][i] = s;
        m[i][4] = off;
    }
    return m;
}

fn toward(weights: [3][3]f32, amount: f32) M {
    var m = identity_m;
    for (0..3) |i| {
        for (0..3) |c| m[i][c] = amount * weights[i][c] + (if (i == c) 1.0 - amount else 0.0);
    }
    return m;
}

const luma = [3]f32{ 0.2126, 0.7152, 0.0722 };
const sepia_w = [3][3]f32{ .{ 0.393, 0.769, 0.189 }, .{ 0.349, 0.686, 0.168 }, .{ 0.272, 0.534, 0.131 } };

/// takumi-core `ColorMatrix::from_filter`; null for blur / drop-shadow.
fn fromFilter(fl: style.Filter) ?M {
    return switch (fl) {
        .brightness => |v| scaleM(v, 0),
        .contrast => |v| scaleM(v, 0.5 - 0.5 * v),
        .invert => |v_in| blk: {
            const v = std.math.clamp(v_in, 0, 1);
            break :blk scaleM(1.0 - 2.0 * v, v);
        },
        .opacity => |v| blk: {
            var m = identity_m;
            m[3][3] = std.math.clamp(v, 0, 1);
            break :blk m;
        },
        .grayscale => |v| toward(.{ luma, luma, luma }, std.math.clamp(v, 0, 1)),
        .sepia => |v| toward(sepia_w, std.math.clamp(v, 0, 1)),
        .saturate => |a| blk: {
            var m = identity_m;
            const rows = [3][3]f32{
                .{ 0.213 + 0.787 * a, 0.715 - 0.715 * a, 0.072 - 0.072 * a },
                .{ 0.213 - 0.213 * a, 0.715 + 0.285 * a, 0.072 - 0.072 * a },
                .{ 0.213 - 0.213 * a, 0.715 - 0.715 * a, 0.072 + 0.928 * a },
            };
            for (0..3) |i| m[i][0..3].* = rows[i];
            break :blk m;
        },
        .hue_rotate => |deg| blk: {
            const base = [3][3]f32{ .{ 0.213, 0.715, 0.072 }, .{ 0.213, 0.715, 0.072 }, .{ 0.213, 0.715, 0.072 } };
            const cosine = [3][3]f32{ .{ 0.787, -0.715, -0.072 }, .{ -0.213, 0.285, -0.072 }, .{ -0.213, -0.715, 0.928 } };
            const sine = [3][3]f32{ .{ -0.213, -0.715, 0.928 }, .{ 0.143, 0.140, -0.283 }, .{ -0.787, 0.715, 0.072 } };
            const r = toRadians(deg);
            // (the engine's own sin / cos: see emit_geom.zig `Tf.rotate`)
            const sc = @import("../measure_xform.zig").sinCos64(r);
            const s: f32 = @floatCast(sc[0]);
            const c: f32 = @floatCast(sc[1]);
            var m = identity_m;
            for (0..3) |i| {
                for (0..3) |k| m[i][k] = base[i][k] + c * cosine[i][k] + s * sine[i][k];
            }
            break :blk m;
        },
        .blur, .drop_shadow => null,
    };
}

fn staysInRange(m: *const M) bool {
    for (m) |row| {
        var sum: f32 = 0;
        for (row) |v| {
            if (!(v >= 0)) return false;
            sum += v;
        }
        if (!(sum <= 1)) return false;
    }
    return true;
}

/// `self` applied after `first`.
fn after(self: *const M, first: *const M) M {
    var out: M = undefined;
    for (0..4) |i| {
        for (0..5) |c| {
            var carried: f32 = 0;
            for (0..4) |k| carried += self[i][k] * first[k][c];
            out[i][c] = carried + (if (c == 4) self[i][4] else 0.0);
        }
    }
    return out;
}

pub const ColorFilter = struct {
    m: [12]M = undefined,
    n: u8 = 0,

    fn push(f: *ColorFilter, m: M) void {
        if (f.n > 0 and staysInRange(&f.m[f.n - 1])) {
            f.m[f.n - 1] = after(&m, &f.m[f.n - 1]);
            return;
        }
        if (f.n < f.m.len) {
            f.m[f.n] = m;
            f.n += 1;
        }
    }

    /// takumi-pdf `ColorFilter::compose`: the element's functions, then the ancestors'.
    pub fn compose(outer: ?*const ColorFilter, filters: []const style.Filter) ?ColorFilter {
        var f: ColorFilter = .{};
        for (filters) |fl| if (fromFilter(fl)) |m| f.push(m);
        if (outer) |o| for (o.m[0..o.n]) |m| f.push(m);
        return if (f.n > 0) f else null;
    }

    pub fn applyF(f: *const ColorFilter, c_in: [4]f32) [4]f32 {
        var c = c_in;
        for (f.m[0..f.n]) |*m| {
            var o: [4]f32 = undefined;
            for (0..4) |i| {
                const r = m[i];
                o[i] = std.math.clamp(r[0] * c[0] + r[1] * c[1] + r[2] * c[2] + r[3] * c[3] + r[4], 0, 1);
            }
            c = o;
        }
        return c;
    }

    pub fn apply(f: *const ColorFilter, rgba: [4]u8) [4]u8 {
        var c: [4]f32 = undefined;
        for (0..4) |i| c[i] = @as(f32, @floatFromInt(rgba[i])) * (1.0 / 255.0);
        const o = f.applyF(c);
        var out: [4]u8 = undefined;
        for (0..4) |i| out[i] = @intFromFloat(o[i] * 255.0 + 0.5);
        return out;
    }

    pub fn key(f: *const ColorFilter) u64 {
        var h = std.hash.Wyhash.init(0xF1);
        h.update(std.mem.sliceAsBytes(f.m[0..f.n]));
        return h.final() | 1;
    }
};

/// `color` as the filter leaves it.
pub fn filtered(f: ?*const ColorFilter, c: Color) Color {
    const fl = f orelse return c;
    const o = fl.apply(.{ c.r, c.g, c.b, c.a });
    return .{ .r = o[0], .g = o[1], .b = o[2], .a = o[3] };
}

/// The first function of `filters` a PDF cannot draw (blur / drop-shadow), as CSS.
pub fn unsupported(a: Allocator, filters: []const style.Filter) ?[]const u8 {
    for (filters) |fl| switch (fl) {
        .blur => |r| {
            var s: std.ArrayList(u8) = .empty;
            s.appendSlice(a, "blur(") catch return "blur()";
            render.writeNum(a, &s, r) catch return "blur()";
            s.appendSlice(a, "px)") catch return "blur()";
            return s.items;
        },
        .drop_shadow => |sh| return dropShadowCss(a, sh) catch "drop-shadow()",
        else => {},
    };
    return null;
}

/// `drop-shadow(...)` as takumi's `ToCss` writes it (`TextShadow::to_css`: `x y [blur] [color]`,
/// the blur left out when zero, the colour as `rgb(r, g, b)` / `rgba(r, g, b, a)` with six decimals).
fn dropShadowCss(a: Allocator, sh: style.Shadow) ![]const u8 {
    var s: std.ArrayList(u8) = .empty;
    try s.appendSlice(a, "drop-shadow(");
    try render.writeNum(a, &s, sh.x);
    try s.appendSlice(a, "px ");
    try render.writeNum(a, &s, sh.y);
    try s.appendSlice(a, "px");
    if (sh.blur != 0) {
        try s.append(a, ' ');
        try render.writeNum(a, &s, sh.blur);
        try s.appendSlice(a, "px");
    }
    switch (sh.color) {
        .current => {},
        .rgba => |c| {
            var buf: [64]u8 = undefined;
            const txt = if (c.a == 255)
                std.fmt.bufPrint(&buf, " rgb({d}, {d}, {d})", .{ c.r, c.g, c.b }) catch unreachable
            else
                std.fmt.bufPrint(&buf, " rgba({d}, {d}, {d}, {d:.6})", .{ c.r, c.g, c.b, @as(f32, @floatFromInt(c.a)) / 255.0 }) catch unreachable;
            try s.appendSlice(a, txt);
        },
    }
    try s.append(a, ')');
    return s.items;
}

/// krilla `fill_from_rgba(rgba, opacity)`.
pub fn fillOf(c: Color, opacity: f32, rule: sf.FillRule) sf.Fill {
    return .{ .paint = .{ .color = .{ c.r, c.g, c.b } }, .opacity = std.math.clamp(@as(f32, @floatFromInt(c.a)) / 255.0 * opacity, 0, 1), .rule = rule };
}

// ---------------------------------------------------------------------------------------------
// the device
// ---------------------------------------------------------------------------------------------

const Saved = enum(u8) { clip, empty_clip, layer };

pub const Device = struct {
    s: *sf.Surface,
    a: Allocator,
    filter: ?*const ColorFilter = null,
    stack: std.ArrayList(Saved) = .empty,
    tmp: Path = .empty,
    tmp2: Path = .empty,
    /// each draw opens its own artifact section (takumi `SurfaceDevice::artifact`)
    artifact: bool = true,
    /// `background-clip: text` mask (takumi `TextDevice::through`): fills and strokes paint each of
    /// these backgrounds, within its clip, instead of their colour (`fill_shape_with`,
    /// `stroke_shape_with`)
    through: ?[]const @import("text.zig").GlyphBackground = null,

    pub fn isHidden(d: *const Device) bool {
        for (d.stack.items) |x| if (x == .empty_clip) return true;
        return false;
    }

    fn open(d: *Device, sv: Saved) void {
        if (d.artifact and d.stack.items.len == 0) d.s.startArtifact();
        d.stack.append(d.a, sv) catch {
            d.s.cx.doc.b.failed = true;
        };
    }

    fn close(d: *Device) void {
        const sv = d.stack.pop() orelse return;
        if (sv != .empty_clip) d.s.pop();
        if (d.artifact and d.stack.items.len == 0) d.s.endArtifact();
    }

    pub fn depth(d: *const Device) usize {
        return d.stack.items.len;
    }

    /// Pops clips / layers until `n` remain.
    pub fn restore(d: *Device, n: usize) void {
        while (d.stack.items.len > n) d.close();
    }

    fn drawWith(d: *Device, path: *const Path, fill: ?sf.Fill, stroke: ?sf.Stroke) void {
        if (d.isHidden()) return;
        const art = d.artifact and d.stack.items.len == 0;
        if (art) d.s.startArtifact();
        d.s.setFill(fill);
        d.s.setStroke(stroke);
        d.s.drawPath(path);
        d.s.setStroke(null);
        if (art) d.s.endArtifact();
    }

    /// Fills `path` (offset by `dx`, `dy`) with `c` (takumi `fill_shape`).
    pub fn fillPath(d: *Device, path: *const Path, dx: f32, dy: f32, rule: sf.FillRule, c: Color) void {
        const p = d.offset(path, dx, dy) orelse return;
        if (d.through) |fills| {
            for (fills) |bg| {
                var f = bg.fill;
                f.rule = rule;
                d.within(bg.clip, p, f, null);
            }
            return;
        }
        d.drawWith(p, fillOf(filtered(d.filter, c), 1, rule), null);
    }

    /// `drawWith` inside `clip` (takumi `SurfaceDevice::within`).
    fn within(d: *Device, clip: ?*const Path, p: *const Path, fill: ?sf.Fill, stroke: ?sf.Stroke) void {
        if (d.isHidden()) return;
        if (clip) |c| d.s.pushClip(c, .nonzero);
        d.drawWith(p, fill, stroke);
        if (clip != null) d.s.pop();
    }

    pub fn fillRRect(d: *Device, r: Rect, radii: ?Radii, c: Color) void {
        d.tmp2.reset();
        addRRect(d.a, &d.tmp2, r, radii) catch return;
        d.fillPath(&d.tmp2, 0, 0, .nonzero, c);
    }

    /// Strokes `path` (offset by `dx`, `dy`) (takumi `stroke_shape`: the colour's alpha is not
    /// carried, as in takumi-pdf).
    pub fn strokePath(d: *Device, path: *const Path, dx: f32, dy: f32, width: f32, dash: ?[2]f32, round_cap: bool, c: Color) void {
        if (c.a == 0 or !(width > 0)) return;
        const p = d.offset(path, dx, dy) orelse return;
        const fc = filtered(d.filter, c);
        var arr: ?sf.Dash = null;
        if (dash) |ds| {
            const buf = d.a.alloc(f32, 2) catch return;
            buf[0] = ds[0];
            buf[1] = ds[1];
            arr = .{ .array = buf };
        }
        const st: sf.Stroke = .{ .paint = .{ .color = .{ fc.r, fc.g, fc.b } }, .width = width, .cap = if (round_cap) .round else .butt, .dash = arr };
        if (d.through) |fills| {
            for (fills) |bg| {
                var s2 = st;
                s2.paint = bg.fill.paint;
                s2.opacity = bg.fill.opacity;
                d.within(bg.clip, p, null, s2);
            }
            return;
        }
        d.drawWith(p, null, st);
    }

    fn offset(d: *Device, path: *const Path, dx: f32, dy: f32) ?*const Path {
        if (dx == 0 and dy == 0) return path;
        geom.translated(d.a, path, dx, dy, &d.tmp) catch return null;
        return &d.tmp;
    }

    /// Clips later draws to `path` (offset); an unfinished / area-less path... is still a clip
    /// in takumi when it finishes; a path that does not finish hides everything.
    pub fn pushClip(d: *Device, path: *const Path, dx: f32, dy: f32, rule: sf.FillRule) void {
        const p = d.offset(path, dx, dy) orelse return d.open(.empty_clip);
        if (geom.bounds(p) == null) return d.open(.empty_clip);
        d.open(.clip);
        d.s.pushClip(p, rule);
    }

    pub fn pushClipRRect(d: *Device, r: Rect, radii: ?Radii) void {
        d.tmp2.reset();
        addRRect(d.a, &d.tmp2, r, radii) catch return;
        d.pushClip(&d.tmp2, 0, 0, .nonzero);
    }

    /// Clips later draws to everything outside `path` (takumi `push_clip_out`: a 2e6 square
    /// around the origin plus the shape, even-odd).
    pub fn pushClipOut(d: *Device, path: *const Path, dx: f32, dy: f32) void {
        const unb: f32 = 1_000_000;
        var p: Path = .empty;
        p.addRect(d.a, .{ .x = -unb, .y = -unb, .w = unb * 2, .h = unb * 2 }) catch return;
        for (path.verbs.items) |v| p.verbs.append(d.a, v) catch return;
        for (path.points.items) |q| p.points.append(d.a, .{ .x = q.x + dx, .y = q.y + dy }) catch return;
        d.open(.clip);
        d.s.pushClip(&p, .even_odd);
    }

    pub fn popClip(d: *Device) void {
        d.close();
    }

    /// takumi `with_border_mask`: later draws go through the soft mask `m` (`endLayer` ends it).
    pub fn beginMask(d: *Device, m: sf.Mask) void {
        d.open(.layer);
        d.s.pushMask(m);
    }

    /// takumi `begin_layer`: an opacity group.
    pub fn beginLayer(d: *Device, opacity: f32) void {
        d.open(.layer);
        d.s.pushOpacity(std.math.clamp(opacity, 0, 1));
    }

    pub fn endLayer(d: *Device) void {
        d.close();
    }
};

/// Rounded (or plain) rectangle path, bm-engine's path builder (`radii` null: a rectangle).
pub fn addRRect(a: Allocator, p: *Path, r: Rect, radii: ?Radii) error{OutOfMemory}!void {
    if (radii) |rr| {
        try p.addRoundRect(a, r, rr);
    } else try p.addRect(a, r);
}

/// `addRRect` with the shape built relative to the box origin (`ox`, `oy`) and then moved there,
/// in that order (takumi `shape_path`: box-relative commands + origin), so rounded corners get
/// takumi's exact numbers.
pub fn addRRectAt(a: Allocator, p: *Path, r: Rect, radii: ?Radii, ox: f32, oy: f32) error{OutOfMemory}!void {
    if (radii == null) return p.addRect(a, r);
    const base = p.points.items.len;
    try p.addRoundRect(a, .{ .x = r.x - ox, .y = r.y - oy, .w = r.w, .h = r.h }, radii.?);
    for (p.points.items[base..]) |*q| {
        q.x += ox;
        q.y += oy;
    }
}

/// A rounded rectangle relative to (`ox`, `oy`) filled with `c`.
pub fn fillRRectAt(d: *Device, r: Rect, radii: ?Radii, ox: f32, oy: f32, c: Color) void {
    d.tmp2.reset();
    addRRectAt(d.a, &d.tmp2, r, radii, ox, oy) catch return;
    d.fillPath(&d.tmp2, 0, 0, .nonzero, c);
}

test "colour filters match takumi-pdf" {
    // filter.rs tests
    const f1 = ColorFilter.compose(null, &.{ .{ .brightness = 2 }, .{ .grayscale = 1 } }).?;
    const o1 = f1.apply(.{ 0xcc, 0x33, 0x33, 255 });
    try std.testing.expectEqual([3]u8{ 0x87, 0x87, 0x87 }, o1[0..3].*);
    const outer = ColorFilter.compose(null, &.{.{ .brightness = 0.5 }}).?;
    const f2 = ColorFilter.compose(&outer, &.{.{ .contrast = 2 }}).?;
    try std.testing.expectEqual([4]u8{ 0x40, 0x40, 0x40, 255 }, f2.apply(.{ 0x80, 0x80, 0x80, 255 }));
    const f3 = ColorFilter.compose(null, &.{.{ .hue_rotate = 180 }}).?;
    try std.testing.expectEqual([4]u8{ 0, 119, 76, 255 }, f3.apply(.{ 225, 29, 72, 255 }));
    const f4 = ColorFilter.compose(null, &.{.{ .invert = 2 }}).?;
    try std.testing.expectEqual([4]u8{ 0xbf, 0xbf, 0xbf, 255 }, f4.apply(.{ 0x40, 0x40, 0x40, 255 }));
    // color-filters.pdf: grayscale(1) of #e11d48 is 74, 74, 74
    const g = ColorFilter.compose(null, &.{.{ .grayscale = 1 }}).?;
    try std.testing.expectEqual([4]u8{ 74, 74, 74, 255 }, g.apply(.{ 225, 29, 72, 255 }));
}

test "unsupported drop-shadow() named as takumi's ToCss writes it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const black: style.computed.ColorValue = .{ .rgba = .{ .r = 0, .g = 0, .b = 0, .a = 255 } };
    try std.testing.expectEqualStrings("drop-shadow(2px 2px 2px rgb(0, 0, 0))", unsupported(a, &.{.{ .drop_shadow = .{ .x = 2, .y = 2, .blur = 2, .color = black } }}).?);
    try std.testing.expectEqualStrings("drop-shadow(2px 2px rgb(0, 0, 0))", unsupported(a, &.{.{ .drop_shadow = .{ .x = 2, .y = 2, .color = black } }}).?);
    try std.testing.expectEqualStrings("drop-shadow(1px -3px)", unsupported(a, &.{.{ .drop_shadow = .{ .x = 1, .y = -3 } }}).?);
}
