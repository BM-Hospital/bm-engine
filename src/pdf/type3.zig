//! Glyph drawing for PDF text: krilla's text/glyph/{mod.rs, outline.rs, colr.rs, bitmap.rs}
//! on top of the emitter's surface (emit_surface.zig).
//!
//!  * `glyphPath`: an outline in font units (y up), transformed (krilla `glyph_path`).
//!  * `drawColorGlyph` (krilla `draw_color_glyph`): COLR (v0 and v1, through bm-render's COLR
//!    walker, font/color.zig) turned into krilla's instruction tree (layers, composites, clipped
//!    fills; gradients become shading patterns, `SrcIn` / `DestIn` soft masks) and replayed onto
//!    the surface; PNG bitmap glyphs (CBDT / sbix) as image XObjects. SVG glyphs are not drawn
//!    (bm-render has no SVG-in-OpenType renderer): they fall back to the outline, like krilla does
//!    for a glyph whose colour data it cannot read.
//!  * `drawGlyph` (krilla `glyph::draw_glyph`): colour glyph, else the outline with the surface's
//!    current fill / stroke.
//! With colour fonts compiled out (`config.enable_color_fonts` false) only outlines exist.
const std = @import("std");
const ttf = @import("../font/ttf.zig");
const sf = @import("emit_surface.zig");
const geom = @import("emit_geom.zig");
const raster = @import("../raster/raster.zig");
const fo = @import("font_objects.zig");

const Allocator = std.mem.Allocator;
const Tf = geom.Tf;
const Path = geom.Path;

const enable_color_fonts = fo.enable_color_fonts;
const color = if (enable_color_fonts) @import("../font/color.zig") else struct {};
const variations = @import("../font/variations.zig");

pub const BitmapKind = enum { none, bitmap_png, bitmap_other };

/// Whether `gid` is an embedded bitmap glyph and of which format.
pub fn bitmapKind(font: *const ttf.Font, gid: u16) BitmapKind {
    if (comptime !enable_color_fonts) return .none;
    const ct = color.ColorTables.init(font);
    return switch (ct.kind(gid)) {
        .bitmap_png => .bitmap_png,
        .bitmap_other => .bitmap_other,
        else => .none,
    };
}

/// Outline of `gid` in font units (y up) mapped through `t` into `out` (reset first). False when
/// the glyph has no outline (tiny-skia `PathBuilder::finish` -> None).
pub fn glyphPath(a: Allocator, font: *const ttf.Font, gid: u16, t: Tf, out: *Path) !bool {
    out.reset();
    var tmp: Path = .empty;
    var sink: raster.PathSink = .{ .path = if (t.isIdentity()) out else &tmp, .alloc = a };
    // (varied points on whole font units, as krilla draws them through skrifa)
    _ = font.outlineWith(gid, &sink, true);
    if (sink.err) return error.OutOfMemory;
    if (!t.isIdentity()) try geom.transformed(a, &tmp, t, out);
    return geom.bounds(out) != null;
}

/// krilla `glyph::draw_glyph`: the colour glyph, else the outline drawn with the surface's
/// current fill and stroke, placed by `base` (glyph units -> surface space).
pub fn drawGlyph(cx: *sf.Ctx, s: *sf.Surface, font: *const ttf.Font, ctx_color: [3]u8, gid: u16, base: Tf) !void {
    if (try drawColorGlyph(cx, s, font, ctx_color, gid, base)) return;
    var p: Path = .empty;
    if (try glyphPath(cx.a, font, gid, base, &p)) s.drawPath(&p);
}

/// krilla `draw_color_glyph`: COLR, then (SVG: not supported), then a PNG bitmap. Returns
/// whether anything was drawn (when not, the surface is unchanged).
pub fn drawColorGlyph(cx: *sf.Ctx, s: *sf.Surface, font: *const ttf.Font, ctx_color: [3]u8, gid: u16, base: Tf) !bool {
    if (comptime !enable_color_fonts) return false;
    const ct = color.ColorTables.init(font);
    const kind = ct.kind(gid);
    if (kind == .colr_v0 or kind == .colr_v1) {
        if (try buildColr(cx.a, font, &ct, gid, ctx_color, null)) |ins| {
            s.pushTransform(base);
            s.pushTransform(Tf.scale(1, -1));
            s.pushTransform(Tf.scale(1, -1));
            try interpret(cx, s, ins);
            s.pop();
            s.pop();
            s.pop();
            return true;
        }
    }
    if (kind == .bitmap_png) {
        const upem: f32 = @floatFromInt(@max(1, font.units_per_em));
        // skrifa `glyph_for_size(Size::unscaled())`: the largest strike
        const bm = ct.bitmap(gid, 0) orelse return false;
        const img = pngXObject(cx, bm.data) orelse return false;
        const sc = if (bm.ppem > 0) upem / bm.ppem else 1;
        var ty = -bm.bearing_y;
        // sbix: Apple's emoji shift (krilla bitmap.rs)
        if (ct.sbix.len != 0 and !(ct.cblc.len != 0 and ct.cbdt.len != 0)) ty += 0.128 * upem / sc;
        const t = Tf.scale(sc, sc).pre(Tf.translate(bm.bearing_x, ty));
        s.pushTransform(base);
        s.pushTransform(Tf.scale(1, -1));
        s.pushTransform(t);
        s.drawImage(img.ref, @floatFromInt(img.w), @floatFromInt(img.h));
        s.pop();
        s.pop();
        s.pop();
        return true;
    }
    return false;
}

const ImageRef = struct { ref: sf.Ref, w: u32, h: u32 };

/// A PNG glyph image as an image XObject (krilla `Image::from_png`: decoded, straight RGB
/// samples + DeviceGray SMask when translucent; same objects as emit_image.zig `regPixmap`,
/// which would lose the colour of faint pixels by going through premultiplied pixels).
fn pngXObject(cx: *sf.Ctx, png: []const u8) ?ImageRef {
    if (comptime !enable_color_fonts) return null;
    const codec = @import("../codec/codec.zig");
    const img = codec.decode(cx.a, png, .{ .max_pixels = 4 << 20 }) catch return null;
    return .{ .ref = straightImage(cx, img.data, img.width, img.height, std.hash.Wyhash.hash(0x9c1, png)) orelse return null, .w = img.width, .h = img.height };
}

/// Straight RGBA8 as an image XObject (+ SMask), deduplicated by `key`.
fn straightImage(cx: *sf.Ctx, rgba: []const u8, iw: u32, ih: u32, key: u64) ?sf.Ref {
    const doc = cx.doc;
    var h = sf.Hasher.init('I');
    h.u64_(key);
    h.u64_(iw);
    h.u64_(ih);
    h.u64_(0x5747);
    const k = h.final();
    if (doc.cacheGet(k)) |r| return r;
    const n: usize = @as(usize, iw) * ih;
    if (rgba.len < n * 4) return null;
    const rgb = cx.a.alloc(u8, n * 3) catch return null;
    const alpha = cx.a.alloc(u8, n) catch return null;
    var translucent = false;
    for (0..n) |i| {
        rgb[i * 3 ..][0..3].* = rgba[i * 4 ..][0..3].*;
        alpha[i] = rgba[i * 4 + 3];
        if (alpha[i] != 255) translucent = true;
    }
    var smask: ?sf.Ref = null;
    if (translucent) {
        const sr = doc.alloc();
        const e = doc.encode(alpha, .flate);
        const b = doc.beginStream(sr, .images, e);
        b.pairName("Type", "XObject");
        b.pairName("Subtype", "Image");
        b.filter(e);
        b.pairInt("Width", iw);
        b.pairInt("Height", ih);
        b.pairName("ColorSpace", "DeviceGray");
        b.pairInt("BitsPerComponent", 8);
        doc.endDict();
        smask = sr;
    }
    const r = doc.alloc();
    const e = doc.encode(rgb, .flate);
    const b = doc.beginStream(r, .images, e);
    b.pairName("Type", "XObject");
    b.pairName("Subtype", "Image");
    b.filter(e);
    b.pairInt("Width", iw);
    b.pairInt("Height", ih);
    b.pairName("ColorSpace", "DeviceRGB");
    b.pairInt("BitsPerComponent", 8);
    if (smask) |sr| b.pairRef("SMask", sr);
    doc.endDict();
    doc.cachePut(k, r);
    return r;
}

// ------------------------------------------------------------------------------------ COLR

/// krilla colr.rs `Instruction`.
const Ins = union(enum) {
    layer: struct { mode: u8, body: []const Ins },
    composite: struct { source: []const Ins, mode: u8, backdrop: []const Ins },
    filled: struct { fill: sf.Fill, clips: []const Path },
};

/// krilla `ColrBuilder` as a bm-render COLR painter.
const Builder = struct {
    a: Allocator,
    font: *const ttf.Font,
    ctx_color: [3]u8,
    /// Resolved shadow outlines use the requested ppem, unlike Type3 glyph programs.
    outline_ppem: ?f32 = null,
    clips: std.ArrayList([]const Path) = .empty,
    stack: std.ArrayList(std.ArrayList(Ins)) = .empty,
    layers: std.ArrayList(u8) = .empty,
    transforms: std.ArrayList(Tf) = .empty,
    err: bool = false,

    fn self(ctx: *anyopaque) *Builder {
        return @ptrCast(@alignCast(ctx));
    }

    fn pushT(ctx: *anyopaque, t: color.Affine2x3) void {
        const b = self(ctx);
        const last = b.transforms.getLastOrNull() orelse return b.fail();
        b.transforms.append(b.a, last.pre(Tf.row(t.xx, t.yx, t.xy, t.yy, t.dx, t.dy))) catch b.fail();
    }
    fn popT(ctx: *anyopaque) void {
        const b = self(ctx);
        if (b.transforms.pop() == null) b.fail();
    }
    fn pushClipPath(b: *Builder, p: Path) void {
        const old = b.clips.getLastOrNull() orelse return b.fail();
        const n = b.a.alloc(Path, old.len + 1) catch return b.fail();
        @memcpy(n[0..old.len], old);
        n[old.len] = p;
        b.clips.append(b.a, n) catch b.fail();
    }
    fn clipG(ctx: *anyopaque, gid: u16) void {
        const b = self(ctx);
        const t = b.transforms.getLastOrNull() orelse return b.fail();
        var p: Path = .empty;
        const ok = if (b.outline_ppem) |size| blk: {
            var raw: Path = .empty;
            var sink: raster.PathSink = .{ .path = &raw, .alloc = b.a };
            if (!b.font.outlineResolved(gid, size, &sink)) break :blk false;
            if (sink.err) return b.fail();
            geom.transformed(b.a, &raw, t, &p) catch return b.fail();
            break :blk true;
        } else glyphPath(b.a, b.font, gid, t, &p) catch return b.fail();
        if (!ok) return b.fail();
        b.pushClipPath(p);
    }
    fn clipB(ctx: *anyopaque, box: color.ClipBox) void {
        const b = self(ctx);
        const t = b.transforms.getLastOrNull() orelse return b.fail();
        var p: Path = .empty;
        var q: Path = .empty;
        q.moveTo(b.a, box.x_min, box.y_min) catch return b.fail();
        q.lineTo(b.a, box.x_min, box.y_max) catch return b.fail();
        q.lineTo(b.a, box.x_max, box.y_max) catch return b.fail();
        q.lineTo(b.a, box.x_max, box.y_min) catch return b.fail();
        q.close(b.a) catch return b.fail();
        geom.transformed(b.a, &q, t, &p) catch return b.fail();
        b.pushClipPath(p);
    }
    fn popC(ctx: *anyopaque) void {
        const b = self(ctx);
        if (b.clips.pop() == null) b.fail();
    }
    fn stops(b: *Builder, in: []const color.ColorStop) ?[]const sf.Stop {
        const out = b.a.alloc(sf.Stop, in.len) catch return null;
        for (in, out) |s, *o| {
            // krilla: NormalizedF32::new(offset)? fails outside 0..1
            if (!(s.offset >= 0 and s.offset <= 1)) return null;
            o.* = .{ .offset = s.offset, .color = .{ s.color.r, s.color.g, s.color.b }, .opacity = @as(f32, @floatFromInt(s.color.a)) / 255.0 };
        }
        return out;
    }
    const Normalized = struct { stops: []const color.ColorStop, range: ?[2]f32 = null };

    /// skrifa's colour-line normalisation (krilla draws COLR glyphs through skrifa): stops that do
    /// not run from 0 to 1 are rescaled to, and the gradient's geometry moved to, the first and
    /// the last stop; a padded line whose stops all sit at one offset gets a last stop one further.
    /// Null: nothing to draw (one offset, not padded).
    fn normalized(b: *Builder, in: []const color.ColorStop, extend: color.Extend) ?Normalized {
        if (in.len == 0) return .{ .stops = in };
        const first = in[0].offset;
        var last = in[in.len - 1].offset;
        var range = last - first;
        var line = in;
        if (range == 0) {
            if (extend != .pad) return null;
            const ext = b.a.alloc(color.ColorStop, in.len + 1) catch {
                b.fail();
                return null;
            };
            @memcpy(ext[0..in.len], in);
            ext[in.len] = in[in.len - 1];
            ext[in.len].offset += 1;
            line = ext;
            last += 1;
            range = 1;
        }
        if (range == 1 and first == 0) return .{ .stops = line };
        const out = b.a.alloc(color.ColorStop, line.len) catch {
            b.fail();
            return null;
        };
        const scale = 1 / range;
        for (line, out) |st, *o| {
            o.* = st;
            o.offset = (st.offset - first) * scale;
        }
        return .{ .stops = out, .range = .{ first, last } };
    }

    fn spread(e: color.Extend) sf.Spread {
        return switch (e) {
            .pad => .pad,
            .repeat => .repeat,
            .reflect => .reflect,
        };
    }
    fn fill(ctx: *anyopaque, brush: *const color.Brush) void {
        const b = self(ctx);
        const t = b.transforms.getLastOrNull() orelse return b.fail();
        const f: sf.Fill = switch (brush.*) {
            .solid => |c| .{ .paint = .{ .color = .{ c.r, c.g, c.b } }, .opacity = @as(f32, @floatFromInt(c.a)) / 255.0 },
            .linear => |g| blk: {
                var p0 = g.p0;
                var p1 = color.linearEnd(g.p0, g.p1, g.p2);
                const n = b.normalized(g.stops, g.extend) orelse return;
                if (n.range) |r| {
                    const d: color.Point = .{ .x = p1.x - p0.x, .y = p1.y - p0.y };
                    p1 = .{ .x = p0.x + d.x * r[1], .y = p0.y + d.y * r[1] };
                    p0 = .{ .x = p0.x + d.x * r[0], .y = p0.y + d.y * r[0] };
                }
                const st = b.stops(n.stops) orelse return b.fail();
                break :blk .{ .paint = .{ .linear = .{ .x1 = p0.x, .y1 = p0.y, .x2 = p1.x, .y2 = p1.y, .transform = t, .spread = spread(g.extend), .stops = st } } };
            },
            .radial => |g| blk: {
                var c0 = g.c0;
                var c1 = g.c1;
                var r0 = g.r0;
                var r1 = g.r1;
                const n = b.normalized(g.stops, g.extend) orelse return;
                if (n.range) |r| {
                    c0 = .{ .x = g.c0.x + (g.c1.x - g.c0.x) * r[0], .y = g.c0.y + (g.c1.y - g.c0.y) * r[0] };
                    c1 = .{ .x = g.c0.x + (g.c1.x - g.c0.x) * r[1], .y = g.c0.y + (g.c1.y - g.c0.y) * r[1] };
                    r0 = @max(g.r0 + (g.r1 - g.r0) * r[0], 0);
                    r1 = @max(g.r0 + (g.r1 - g.r0) * r[1], 0);
                }
                const st = b.stops(n.stops) orelse return b.fail();
                break :blk .{ .paint = .{ .radial = .{ .fx = c0.x, .fy = c0.y, .fr = r0, .cx = c1.x, .cy = c1.y, .cr = r1, .transform = t, .spread = spread(g.extend), .stops = st } } };
            },
            .sweep => |g0| blk: {
                var g = g0;
                const n = b.normalized(g0.stops, g0.extend) orelse return;
                if (n.range) |r| {
                    const sweep = g0.end_angle - g0.start_angle;
                    g.start_angle = g0.start_angle + sweep * r[0];
                    g.end_angle = g0.start_angle + sweep * r[1];
                }
                const st = b.stops(n.stops) orelse return b.fail();
                // krilla sweeps the other way: y flipped
                break :blk .{ .paint = .{ .sweep = .{ .cx = g.c.x, .cy = -g.c.y, .start = g.start_angle, .end = g.end_angle, .transform = t.pre(Tf.scale(1, -1)), .spread = spread(g.extend), .stops = st } } };
            },
        };
        const clips = b.clips.getLastOrNull() orelse return b.fail();
        const top = if (b.stack.items.len > 0) &b.stack.items[b.stack.items.len - 1] else return b.fail();
        top.append(b.a, .{ .filled = .{ .fill = f, .clips = clips } }) catch b.fail();
    }
    fn pushL(ctx: *anyopaque, mode: color.CompositeMode) void {
        const b = self(ctx);
        b.layers.append(b.a, @backingInt(mode)) catch return b.fail();
        b.stack.append(b.a, .empty) catch b.fail();
    }
    fn popL(ctx: *anyopaque) void {
        const b = self(ctx);
        const mode = b.layers.pop() orelse return b.fail();
        var ins = b.stack.pop() orelse return b.fail();
        if (b.stack.items.len == 0) return b.fail();
        const top = &b.stack.items[b.stack.items.len - 1];
        if (mode == @backingInt(color.CompositeMode.src_over) and ins.items.len > 0 and ins.items[ins.items.len - 1] == .layer) {
            const last = ins.pop().?.layer;
            top.append(b.a, .{ .composite = .{ .source = last.body, .mode = last.mode, .backdrop = ins.items } }) catch b.fail();
            return;
        }
        top.append(b.a, .{ .layer = .{ .mode = mode, .body = ins.items } }) catch b.fail();
    }
    fn fail(b: *Builder) void {
        b.err = true;
    }
};

/// Paints COLR glyph `gid` into an instruction list (null: no COLR data or an error).
fn buildColr(a: Allocator, font: *const ttf.Font, ct: *const color.ColorTables, gid: u16, ctx_color: [3]u8, outline_ppem: ?f32) !?[]const Ins {
    var b: Builder = .{ .a = a, .font = font, .ctx_color = ctx_color, .outline_ppem = outline_ppem };
    try b.clips.append(a, &.{});
    try b.stack.append(a, .empty);
    try b.transforms.append(a, .identity);
    const vt: color.Painter.VTable = .{
        .push_transform = Builder.pushT,
        .pop_transform = Builder.popT,
        .push_clip_glyph = Builder.clipG,
        .push_clip_box = Builder.clipB,
        .pop_clip = Builder.popC,
        .fill = Builder.fill,
        .push_layer = Builder.pushL,
        .pop_layer = Builder.popL,
    };
    const fg: color.Rgba = .{ .r = ctx_color[0], .g = ctx_color[1], .b = ctx_color[2], .a = 255 };
    ct.paintVar(gid, 0, fg, font.normalizedCoords(), &variations.itemDelta, .{ .ctx = &b, .vtable = &vt }) catch return null;
    if (b.err or b.stack.items.len == 0) return null;
    return b.stack.items[b.stack.items.len - 1].items;
}

fn blendOf(mode: u8) ?sf.Blend {
    const M = color.CompositeMode;
    return switch (@as(M, @fromBackingInt(@intCast(mode)))) {
        .src_over => .normal,
        .screen => .screen,
        .overlay => .overlay,
        .darken => .darken,
        .lighten => .lighten,
        .color_dodge => .color_dodge,
        .color_burn => .color_burn,
        .hard_light => .hard_light,
        .soft_light => .soft_light,
        .difference => .difference,
        .exclusion => .exclusion,
        .multiply => .multiply,
        .hsl_hue => .hue,
        .hsl_color => .color,
        .hsl_luminosity => .luminosity,
        .hsl_saturation => .saturation,
        else => null,
    };
}

/// krilla colr.rs `interpret`.
fn interpret(cx: *sf.Ctx, s: *sf.Surface, ins: []const Ins) error{OutOfMemory}!void {
    for (ins) |in| switch (in) {
        .layer => |l| {
            s.pushBlend(blendOf(l.mode) orelse .normal);
            s.pushIsolated();
            try interpret(cx, s, l.body);
            s.pop();
            s.pop();
        },
        .composite => |c| try interpretComposite(cx, s, c.source, c.mode, c.backdrop),
        .filled => |f| {
            if (f.clips.len == 0) continue;
            const n = f.clips.len - 1;
            for (f.clips[0..n]) |*p| s.pushClip(p, .nonzero);
            const old_fill = s.fill;
            const old_stroke = s.stroke;
            s.setFill(f.fill);
            s.setStroke(null);
            s.drawPath(&f.clips[n]);
            s.setFill(old_fill);
            s.setStroke(old_stroke);
            for (0..n) |_| s.pop();
        },
    };
}

fn interpretComposite(cx: *sf.Ctx, s: *sf.Surface, source: []const Ins, mode: u8, backdrop: []const Ins) !void {
    const M = color.CompositeMode;
    switch (@as(M, @fromBackingInt(@intCast(mode)))) {
        .clear => {},
        .src => {
            s.pushIsolated();
            try interpret(cx, s, source);
            s.pop();
        },
        .dest => {
            s.pushIsolated();
            try interpret(cx, s, backdrop);
            s.pop();
        },
        .src_over => {
            s.pushIsolated();
            try interpret(cx, s, backdrop);
            try interpret(cx, s, source);
            s.pop();
        },
        .dest_over => {
            s.pushIsolated();
            try interpret(cx, s, source);
            try interpret(cx, s, backdrop);
            s.pop();
        },
        .src_in => try interpretMasked(cx, s, source, backdrop),
        .dest_in => try interpretMasked(cx, s, backdrop, source),
        else => {
            const blend = blendOf(mode) orelse {
                s.pushIsolated();
                try interpret(cx, s, backdrop);
                try interpret(cx, s, source);
                s.pop();
                return;
            };
            s.pushIsolated();
            try interpret(cx, s, backdrop);
            s.pushBlend(blend);
            s.pushIsolated();
            try interpret(cx, s, source);
            s.pop();
            s.pop();
            s.pop();
        },
    }
}

fn interpretMasked(cx: *sf.Ctx, s: *sf.Surface, visible: []const Ins, mask: []const Ins) !void {
    var ms = sf.Surface.initStream(cx);
    try interpret(cx, &ms, mask);
    const st = ms.finish();
    s.pushMask(.{ .stream = st, .kind = .alpha });
    try interpret(cx, s, visible);
    s.pop();
}

// ------------------------------------------------------------------- shadow silhouettes

/// One layer of a colour glyph's silhouette (takumi glyph.rs `ColorGlyphs`): a placed path and
/// the alpha its layer paints with (opaque layers joined).
pub const Silhouette = struct { alpha: f32, path: Path };

/// takumi `ColorGlyphs::of` for one COLR glyph at `at` (px, y down) and `size`: the solid
/// layers' outlines in page space; gradient fills count as opaque. Appends to `out`.
pub fn colrSilhouette(a: Allocator, font: *const ttf.Font, gid: u16, fg: [4]u8, size: f32, at: [2]f32, opaque_path: *Path, out: *std.ArrayList(Silhouette)) !void {
    if (comptime !enable_color_fonts) return;
    const ct = color.ColorTables.init(font);
    const k = ct.kind(gid);
    if (k != .colr_v0 and k != .colr_v1) return;
    const upem: f32 = @floatFromInt(@max(1, font.units_per_em));
    const place = Tf.translate(at[0], at[1]).pre(Tf.scale(size / upem, -size / upem));
    const ins = (try buildColr(a, font, &ct, gid, .{ fg[0], fg[1], fg[2] }, size)) orelse return;
    try collectLayers(a, ins, place, fg[3], opaque_path, out);
}

fn collectLayers(a: Allocator, ins: []const Ins, place: Tf, fg_alpha: u8, opaque_path: *Path, out: *std.ArrayList(Silhouette)) !void {
    for (ins) |in| switch (in) {
        .layer => |l| try collectLayers(a, l.body, place, fg_alpha, opaque_path, out),
        .composite => |c| {
            try collectLayers(a, c.backdrop, place, fg_alpha, opaque_path, out);
            try collectLayers(a, c.source, place, fg_alpha, opaque_path, out);
        },
        .filled => |f| {
            if (f.clips.len == 0) continue;
            const alpha: u8 = switch (f.fill.paint) {
                .color => @intFromFloat(@round(f.fill.opacity * 255)),
                else => 255,
            };
            if (alpha == 0) continue;
            var p: Path = .empty;
            try geom.transformed(a, &f.clips[f.clips.len - 1], place, &p);
            if (alpha == 255) {
                try opaque_path.verbs.appendSlice(a, p.verbs.items);
                try opaque_path.points.appendSlice(a, p.points.items);
            } else try out.append(a, .{ .alpha = @as(f32, @floatFromInt(alpha)) / 255.0, .path = p });
        },
    };
}
