//! SVG images as vector operators (takumi-pdf `svg.rs` `SvgPainter` over takumi-core's
//! `SvgDocument::ops`), for the subset of SVG whose op list bm-engine can reproduce: the root
//! `svg` (viewBox / preserveAspectRatio), `g` / `a`, `path`, `rect`, `circle`, `ellipse`,
//! `polyline`, `polygon`, with transforms, group / element `opacity`, fill and stroke (colours,
//! `currentColor`, linear and radial gradients in either unit system, with `gradientTransform`
//! and `spreadMethod`), `fill-rule`, stroke width / caps / joins / miter limit / dashes,
//! `visibility` and `display`. Every element is a container (takumi `convert_group`): its
//! transform and opacity are pushed around what it draws.
//!
//! Anything else (clip paths, masks, filters, blend modes, isolation, markers, patterns, `use`,
//! `image`, `text`, nested `svg`, `switch`, `line`, gradient `href` chains, `paint-order`,
//! `vector-effect`) makes `draw` return false: the caller then embeds the image rasterised, as
//! before this port.
const std = @import("std");
const sf = @import("emit_surface.zig");
const geom = @import("emit_geom.zig");
const raster = @import("../raster/raster.zig");
const dom = @import("../svg/dom.zig");
const num = @import("../svg/num.zig");
const scolor = @import("../svg/color.zig");
const sstyle = @import("../svg/style.zig");
const pathdata = @import("../svg/pathdata.zig");
const render_svg = @import("../svg/render.zig");

const Allocator = std.mem.Allocator;
const Tf = geom.Tf;
const Path = raster.Path;
const Affine = raster.Affine;
const Node = dom.Node;
const NONE = dom.NONE;

const Error = error{OutOfMemory};

/// Draws SVG markup `src` laid out at its displayed size `w` x `h` with its top-left corner at
/// (`x`, `y`) (takumi `draw_svg` with the viewport = the size), clipped to that canvas. False
/// (nothing drawn) when the markup is not valid SVG or uses what this port does not draw.
pub fn draw(a: Allocator, s: *sf.Surface, src: []const u8, x: f32, y: f32, w: f32, h: f32, current: raster.Color) Error!bool {
    if (!(w > 0) or !(h > 0)) return false;
    const doc = render_svg.parseDoc(true, a, src) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    if (doc.nodes.len == 0 or doc.nodes[0].tag != .svg) return false;
    var p: Painter = .{ .a = a, .s = s, .doc = &doc, .vw = w, .vh = h };
    if (!p.supported()) return false;
    const root = doc.root();
    var root_tf: Affine = .identity;
    if (num.parseViewBox(root.attr("viewBox") orelse "")) |vb| {
        if (!(vb[2] > 0) or !(vb[3] > 0)) return false;
        root_tf = num.viewBoxTransform(vb, num.parseAspectRatio(root.attr("preserveAspectRatio")), w, h);
        p.vw = vb[2];
        p.vh = vb[3];
    }
    const depth0 = s.depth();
    s.pushTransform(Tf.translate(x, y));
    var canvas: Path = .{};
    try canvas.addRect(a, .{ .x = 0, .y = 0, .w = w, .h = h });
    s.pushClip(&canvas, .nonzero);
    var st: sstyle.Style = .{ .color = current };
    try p.group(0, &st, root_tf);
    s.setFill(null);
    s.setStroke(null);
    s.popTo(depth0);
    return true;
}

const Painter = struct {
    a: Allocator,
    s: *sf.Surface,
    doc: *const dom.Document,
    /// the user-space viewport percentages resolve against
    vw: f32,
    vh: f32,

    /// Whether every element that would draw is in the supported subset.
    fn supported(p: *const Painter) bool {
        for (p.doc.nodes, 0..) |*n, i| {
            switch (n.tag) {
                .g, .a, .path, .rect, .circle, .ellipse, .polyline, .polygon => {},
                .svg => if (i != 0) return false,
                .defs, .linearGradient, .radialGradient, .stop, .style, .unknown => {},
                else => return false,
            }
            if (n.tag == .linearGradient or n.tag == .radialGradient) {
                if (n.attr("href") != null) return false;
            }
            for (n.decls) |d| switch (d.prop) {
                .clip_path, .mask, .filter => if (!isNone(d.value)) return false,
                .mix_blend_mode => if (!std.mem.eql(u8, num.trim(d.value), "normal")) return false,
                .isolation => if (std.mem.eql(u8, num.trim(d.value), "isolate")) return false,
                .marker_start, .marker_mid, .marker_end, .marker => if (!isNone(d.value)) return false,
                .paint_order => if (!std.mem.eql(u8, num.trim(d.value), "normal")) return false,
                .vector_effect => if (!isNone(d.value)) return false,
                .fill, .stroke => {
                    const v = num.trim(d.value);
                    if (std.mem.startsWith(u8, v, "url(")) {
                        const t = p.server(v) orelse continue;
                        if (p.doc.nodes[t].tag != .linearGradient and p.doc.nodes[t].tag != .radialGradient) return false;
                    }
                },
                else => {},
            };
        }
        return true;
    }

    fn isNone(v: []const u8) bool {
        const t = num.trim(v);
        return t.len == 0 or std.mem.eql(u8, t, "none");
    }

    /// The element a `url(#id)` paint names.
    fn server(p: *const Painter, v: []const u8) ?u32 {
        const s = num.trim(v);
        if (!std.mem.startsWith(u8, s, "url(")) return null;
        const e = std.mem.indexOfScalar(u8, s, ')') orelse return null;
        var id = num.trim(s[4..e]);
        if (id.len >= 2 and (id[0] == '"' or id[0] == '\'')) id = id[1 .. id.len - 1];
        if (id.len == 0 or id[0] != '#') return null;
        return p.doc.byId(id[1..]);
    }

    fn len(p: *const Painter, n: *const Node, name: []const u8, axis: num.Axis, def: f32, fs: f32) f32 {
        const s = n.attr(name) orelse return def;
        const l = num.parseLength(s) orelse return def;
        const ref = switch (axis) {
            .x => p.vw,
            .y => p.vh,
            .other => @sqrt((p.vw * p.vw + p.vh * p.vh) / 2),
        };
        return num.resolve(l, ref, fs);
    }

    /// takumi `convert_group`: an element's container (transform, opacity) around what it draws.
    fn group(p: *Painter, idx: u32, parent: *const sstyle.Style, tf: Affine) Error!void {
        const n = &p.doc.nodes[idx];
        if (n.decl(.display)) |d| if (std.mem.eql(u8, num.trim(d), "none")) return;
        var st = parent.*;
        st.apply(n);
        const op = if (n.decl(.opacity)) |v| sstyle.opacity(v) orelse 1 else 1;
        const depth0 = p.s.depth();
        if (!isIdentity(tf)) p.s.pushTransform(Tf.fromAffine(tf));
        if (op < 1) p.s.pushOpacity(op);
        switch (n.tag) {
            .svg, .g, .a => {
                var ch = n.first_child;
                while (ch != NONE) : (ch = p.doc.nodes[ch].next_sibling) {
                    const c = &p.doc.nodes[ch];
                    switch (c.tag) {
                        .g, .a, .path, .rect, .circle, .ellipse, .polyline, .polygon => {},
                        else => continue,
                    }
                    var ctf: Affine = .identity;
                    if (c.decl(.transform)) |ts| {
                        if (num.parseTransform(ts)) |t| ctf = t;
                    }
                    try p.group(ch, &st, ctf);
                }
            },
            else => try p.shape(n, &st),
        }
        p.s.popTo(depth0);
    }

    fn isIdentity(t: Affine) bool {
        return t.a == 1 and t.b == 0 and t.c == 0 and t.d == 1 and t.e == 0 and t.f == 0;
    }

    fn shapePath(p: *Painter, n: *const Node, fs: f32) Error!?Path {
        var path: Path = .{};
        const a = p.a;
        switch (n.tag) {
            .path => pathdata.parse(a, n.attr("d") orelse "", &path, null) catch return error.OutOfMemory,
            .polyline, .polygon => pathdata.polyline(a, &path, n.attr("points") orelse "", n.tag == .polygon, null) catch return error.OutOfMemory,
            .rect => {
                const w = p.len(n, "width", .x, 0, fs);
                const h = p.len(n, "height", .y, 0, fs);
                if (!(w > 0 and h > 0)) return null;
                var rx: ?f32 = if (n.attr("rx") != null) p.len(n, "rx", .x, 0, fs) else null;
                var ry: ?f32 = if (n.attr("ry") != null) p.len(n, "ry", .y, 0, fs) else null;
                if (rx != null and !(rx.? >= 0)) rx = null;
                if (ry != null and !(ry.? >= 0)) ry = null;
                pathdata.rect(a, &path, p.len(n, "x", .x, 0, fs), p.len(n, "y", .y, 0, fs), w, h, rx orelse ry orelse 0, ry orelse rx orelse 0) catch return error.OutOfMemory;
            },
            .circle => {
                const r = p.len(n, "r", .other, 0, fs);
                if (!(r > 0)) return null;
                pathdata.ellipse(a, &path, p.len(n, "cx", .x, 0, fs), p.len(n, "cy", .y, 0, fs), r, r) catch return error.OutOfMemory;
            },
            .ellipse => {
                var rx: ?f32 = if (n.attr("rx") != null) p.len(n, "rx", .x, 0, fs) else null;
                var ry: ?f32 = if (n.attr("ry") != null) p.len(n, "ry", .y, 0, fs) else null;
                if (rx == null) rx = ry;
                if (ry == null) ry = rx;
                if (rx == null or !(rx.? > 0) or !(ry.? > 0)) return null;
                pathdata.ellipse(a, &path, p.len(n, "cx", .x, 0, fs), p.len(n, "cy", .y, 0, fs), rx.?, ry.?) catch return error.OutOfMemory;
            },
            else => return null,
        }
        if (path.isEmpty()) return null;
        return path;
    }

    fn shape(p: *Painter, n: *const Node, st: *const sstyle.Style) Error!void {
        if (!st.visible) return;
        var path = (try p.shapePath(n, st.font_size)) orelse return;
        const b = path.bounds();
        const has_bbox = b.w > 0 and b.h > 0;
        const fill: ?sf.Fill = if (try p.paint(st.fill, st, has_bbox, b)) |pp| .{ .paint = pp.paint, .opacity = pp.opacity * st.fill_opacity, .rule = if (st.fill_rule == .evenodd) .even_odd else .nonzero } else null;
        var stroke: ?sf.Stroke = null;
        const sw = num.resolve(st.stroke_width, @sqrt((p.vw * p.vw + p.vh * p.vh) / 2), st.font_size);
        if (sw > 0 and std.math.isFinite(sw)) {
            if (try p.paint(st.stroke, st, has_bbox, b)) |pp| stroke = .{
                .paint = pp.paint,
                .opacity = pp.opacity * st.stroke_opacity,
                .width = sw,
                .miter_limit = st.miter_limit,
                .cap = switch (st.cap) {
                    .butt => .butt,
                    .round => .round,
                    .square => .square,
                },
                .join = switch (st.join) {
                    .miter => .miter,
                    .round => .round,
                    .bevel => .bevel,
                },
                .dash = try p.dashes(st),
            };
        }
        if (fill == null and stroke == null) return;
        p.s.setFill(fill);
        p.s.setStroke(stroke);
        p.s.drawPath(&path);
    }

    /// takumi `dash_pattern`: an even list of user units, none for a solid line.
    fn dashes(p: *Painter, st: *const sstyle.Style) Error!?sf.Dash {
        const v = num.trim(st.dasharray);
        if (v.len == 0 or std.mem.eql(u8, v, "none")) return null;
        var list: std.ArrayList(f32) = .empty;
        var it = std.mem.tokenizeAny(u8, v, " ,\t\r\n");
        const diag = @sqrt((p.vw * p.vw + p.vh * p.vh) / 2);
        var sum: f32 = 0;
        while (it.next()) |t| {
            const l = num.parseLength(t) orelse return null;
            const d = num.resolve(l, diag, st.font_size);
            if (d < 0 or !std.math.isFinite(d)) return null;
            sum += d;
            try list.append(p.a, d);
        }
        if (!(sum > 0)) return null;
        if (list.items.len % 2 == 1) try list.appendSlice(p.a, try p.a.dupe(f32, list.items));
        return .{ .array = list.items, .offset = num.resolve(st.dashoffset, diag, st.font_size) };
    }

    const PaintOut = struct { paint: sf.Paint, opacity: f32 };

    fn colorPaint(c: raster.Color) PaintOut {
        return .{ .paint = .{ .color = .{ c.r, c.g, c.b } }, .opacity = @as(f32, @floatFromInt(c.a)) / 255 };
    }

    /// takumi `convert_paint`.
    fn paint(p: *Painter, sp: sstyle.SPaint, st: *const sstyle.Style, has_bbox: bool, bbox: raster.Rect) Error!?PaintOut {
        const fallback: ?PaintOut = switch (sp.fallback) {
            .color => colorPaint(sp.color),
            .current => colorPaint(st.color),
            else => null,
        };
        return switch (sp.kind) {
            .none => null,
            .color => colorPaint(sp.color),
            .current => colorPaint(st.color),
            .server => blk: {
                const t = p.server(sp.ref) orelse break :blk fallback;
                const g = &p.doc.nodes[t];
                if (g.tag != .linearGradient and g.tag != .radialGradient) break :blk fallback;
                break :blk (try p.gradient(t, st, has_bbox, bbox)) orelse fallback;
            },
        };
    }

    fn number(p: *const Painter, g: *const Node, name: []const u8, bbox_units: bool, axis: num.Axis, def: []const u8, fs: f32) f32 {
        const s = g.attr(name) orelse def;
        const l = num.parseLength(s) orelse num.parseLength(def).?;
        if (bbox_units) return if (l.unit == .percent) l.v / 100 else num.resolve(l, 1, fs);
        const ref = switch (axis) {
            .x => p.vw,
            .y => p.vh,
            .other => @sqrt((p.vw * p.vw + p.vh * p.vh) / 2),
        };
        return num.resolve(l, ref, fs);
    }

    /// takumi `linear_gradient` / `radial_gradient` (`PaintServer`) made drawable (usvg
    /// `process_paint`: bounding-box units folded into the transform).
    fn gradient(p: *Painter, gi: u32, st: *const sstyle.Style, has_bbox: bool, bbox: raster.Rect) Error!?PaintOut {
        const g = &p.doc.nodes[gi];
        const stops = try p.gradientStops(gi, st);
        if (stops.len == 0) return null;
        if (stops.len < 2) return .{ .paint = .{ .color = stops[0].color }, .opacity = stops[0].opacity };
        const units = g.attr("gradientUnits") orelse "objectBoundingBox";
        const bbox_units = !std.mem.eql(u8, num.trim(units), "userSpaceOnUse");
        if (bbox_units and !has_bbox) return null;
        var tf: Affine = .identity;
        if (g.attr("gradientTransform")) |ts| {
            if (num.parseTransform(ts)) |t| tf = t;
        }
        if (bbox_units) tf = (Affine{ .a = bbox.w, .d = bbox.h, .e = bbox.x, .f = bbox.y }).mul(tf);
        const sm = num.trim(g.attr("spreadMethod") orelse "pad");
        const spread: sf.Spread = if (std.mem.eql(u8, sm, "reflect")) .reflect else if (std.mem.eql(u8, sm, "repeat")) .repeat else .pad;
        const fs = st.font_size;
        if (g.tag == .linearGradient) {
            return .{ .paint = .{ .linear = .{
                .x1 = p.number(g, "x1", bbox_units, .x, "0", fs),
                .y1 = p.number(g, "y1", bbox_units, .y, "0", fs),
                .x2 = p.number(g, "x2", bbox_units, .x, "100%", fs),
                .y2 = p.number(g, "y2", bbox_units, .y, "0", fs),
                .transform = Tf.fromAffine(tf),
                .spread = spread,
                .stops = stops,
            } }, .opacity = 1 };
        }
        const r = p.number(g, "r", bbox_units, .other, "50%", fs);
        // a radius of zero paints the last stop's colour
        if (!(r > 0) or !std.math.isFinite(r)) return .{ .paint = .{ .color = stops[stops.len - 1].color }, .opacity = stops[stops.len - 1].opacity };
        const cx = p.number(g, "cx", bbox_units, .x, "50%", fs);
        const cy = p.number(g, "cy", bbox_units, .y, "50%", fs);
        const fx = if (g.attr("fx") != null) p.number(g, "fx", bbox_units, .x, "0", fs) else cx;
        const fy = if (g.attr("fy") != null) p.number(g, "fy", bbox_units, .y, "0", fs) else cy;
        const fr0 = p.number(g, "fr", bbox_units, .other, "0", fs);
        return .{ .paint = .{ .radial = .{
            .fx = fx,
            .fy = fy,
            .fr = if (fr0 > 0 and std.math.isFinite(fr0)) fr0 else 0,
            .cx = cx,
            .cy = cy,
            .cr = r,
            .transform = Tf.fromAffine(tf),
            .spread = spread,
            .stops = stops,
        } }, .opacity = 1 };
    }

    /// takumi `gradient_stops` + `spread_equal_offsets`.
    fn gradientStops(p: *Painter, gi: u32, st: *const sstyle.Style) Error![]sf.Stop {
        var out: std.ArrayList(sf.Stop) = .empty;
        var prev: f32 = 0;
        var ch = p.doc.nodes[gi].first_child;
        while (ch != NONE) : (ch = p.doc.nodes[ch].next_sibling) {
            const n = &p.doc.nodes[ch];
            if (n.tag != .stop) continue;
            var off = prev;
            if (n.attr("offset")) |o| {
                const t = num.trim(o);
                if (t.len > 0 and t[t.len - 1] == '%') {
                    if (num.parseNumber(t[0 .. t.len - 1])) |v| off = v / 100;
                } else if (num.parseNumber(t)) |v| off = v;
            }
            prev = off;
            var sst = st.*;
            sst.apply(n);
            var c: raster.Color = raster.Color.black;
            if (n.decl(.stop_color)) |v| {
                const t = num.trim(v);
                if (num.eqlIgnoreCase(t, "currentColor")) c = sst.color else if (scolor.parse(t)) |x| c = x;
            }
            var so: f32 = 1;
            if (n.decl(.stop_opacity)) |v| so = sstyle.opacity(v) orelse 1;
            try out.append(p.a, .{
                .offset = std.math.clamp(off, 0, 1),
                .color = .{ c.r, c.g, c.b },
                .opacity = @as(f32, @floatFromInt(c.a)) / 255 * so,
            });
        }
        var s = out.items;
        const eq = struct {
            fn f(x: f32, y: f32) bool {
                return @abs(x - y) <= std.math.floatEps(f32) * @max(@max(@abs(x), @abs(y)), 1);
            }
        }.f;
        // the stop in the middle of three at one offset goes
        if (s.len >= 3) {
            var i: usize = 0;
            while (i + 2 < s.len) {
                if (eq(s[i].offset, s[i + 1].offset) and eq(s[i + 1].offset, s[i + 2].offset)) {
                    std.mem.copyForwards(sf.Stop, s[i + 1 ..], s[i + 2 ..]);
                    s = s[0 .. s.len - 1];
                } else i += 1;
            }
        }
        // two stops at zero become zero and a hair above it
        if (s.len >= 2) for (0..s.len - 1) |i| {
            if (eq(s[i].offset, 0) and eq(s[i + 1].offset, 0)) s[i + 1].offset = std.math.clamp(s[i].offset + std.math.floatEps(f32), 0, 1);
        };
        // an offset below the one before it takes the previous one, which moves back a hair
        for (1..@max(s.len, 1)) |i| {
            if (i >= s.len) break;
            const pv = s[i - 1].offset;
            const cur = s[i].offset;
            if (pv > cur or eq(pv, cur)) {
                s[i - 1].offset = std.math.clamp(pv - std.math.floatEps(f32), 0, 1);
                s[i].offset = std.math.clamp(pv, 0, 1);
            }
        }
        return s;
    }
};

test "supported subset" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const aa = arena.allocator();
    const ok = try render_svg.parseDoc(true, aa, "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><defs><linearGradient id='g'><stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue'/></linearGradient></defs><circle cx='12' cy='12' r='10' fill='url(#g)'/><path d='M6 12 L11 17' stroke='#fff'/></svg>");
    var p: Painter = .{ .a = aa, .s = undefined, .doc = &ok, .vw = 24, .vh = 24 };
    try std.testing.expect(p.supported());
    const stops = try p.gradientStops(2, &.{});
    try std.testing.expectEqual(@as(usize, 2), stops.len);
    try std.testing.expectEqual(@as(u8, 255), stops[0].color[0]);
    const no = try render_svg.parseDoc(true, aa, "<svg xmlns='http://www.w3.org/2000/svg'><clipPath id='c'><rect width='4' height='4'/></clipPath><rect width='9' height='9' clip-path='url(#c)'/></svg>");
    p.doc = &no;
    try std.testing.expect(!p.supported());
}

test "draws the svg-vector-image fixture as operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const w = @import("writer.zig");
    var doc = w.Doc.init(a, .{ .compress = false });
    var cx: sf.Ctx = .{ .a = a, .doc = &doc };
    var s = sf.Surface.initPage(&cx, 45);
    const src = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"24\" height=\"24\">\n  <defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"24\" y2=\"24\" gradientUnits=\"userSpaceOnUse\">\n <stop offset=\"0\" stop-color=\"#ff0044\"/><stop offset=\"1\" stop-color=\"#0044ff\"/>\n </linearGradient></defs>\n <circle cx=\"12\" cy=\"12\" r=\"10\" fill=\"url(#g)\"/>\n <path d=\"M6 12 L11 17 L18 7\" stroke=\"#fff\" stroke-width=\"2.5\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n</svg>";
    try std.testing.expect(try draw(a, &s, src, 0, 8, 22, 22, raster.Color.black));
    const st = s.finish();
    try std.testing.expect(std.mem.indexOf(u8, st.content, "1 J") != null);
}
