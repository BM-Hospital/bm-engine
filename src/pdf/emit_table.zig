//! Table painting after takumi's `painter/table.rs` (a port of Blink's table_painters.cc):
//!  * a table's box decorations (shadows, background, border) cover its GRID box, not its captions
//!  * `<col>` / `<colgroup>` backgrounds, then row-group and row backgrounds, are painted into the
//!    cells they hold (never into the border-spacing gaps)
//!  * `border-collapse: collapse`: no box paints its own border; every edge of the grid is painted
//!    once, after everything inside the table, with the border that wins it (CSS 2.1 §17.6.2 as
//!    Blink's `TableBorders`: hidden > widest > style rank > box order), joints as Blink's
//!    `ComputeEdgeJoints`
//!  * hidden parts paint nothing: collapsed rows, cells whose columns are all collapsed, and empty
//!    cells under `empty-cells: hide` (separated borders).
//! The grid (rows, columns, each cell's position) comes from the layout engine (`Tree.tableGeom`),
//! the styles from the render nodes.
const std = @import("std");
const render = @import("../render.zig");
const style = @import("../style/style.zig");
const computed = @import("../style/computed.zig");
const raster = @import("../raster/raster.zig");
const layout = @import("../layout/layout.zig");
const pm = @import("../paint.zig");
const border = @import("emit_border.zig");
const emit = @import("emit.zig");
const dev = @import("emit_device.zig");

const Painter = emit.Emitter;
const Ctx = pm.Ctx;
const Geom = pm.Geom;
const CS = render.CS;
const Rect = raster.Rect;
const Error = render.Error;
const none = render.none;
pub const TG = layout.TableGeom;
const BStyle = computed.BorderStyle;

pub const Kind = enum(u8) { none, sec, row, cell };

/// What a render node is inside the table that was painted around it (indexed by render node id).
pub const Part = struct {
    g: ?*const TG = null,
    idx: u32 = 0,
    kind: Kind = .none,
    /// paints nothing at all (the node and its subtree)
    hidden: bool = false,
};

fn nodeOf(p: *Painter, lid: u32) u32 {
    const m = p.f.lid_node.items;
    return if (lid < m.len) m[lid] else none;
}

fn csOf(p: *Painter, lid: u32) ?*const CS {
    const id = nodeOf(p, lid);
    return if (id < p.f.nodes.items.len) p.f.nodes.items[id].cs else null;
}

fn setPart(p: *Painter, lid: u32, part: Part) void {
    const id = nodeOf(p, lid);
    if (id < p.tparts.len) p.tparts[id] = part;
}

fn hasBackground(cs: *const CS) bool {
    return cs.resolveColor(cs.background_color).a != 0 or cs.background_image.len > 0;
}

/// Marks the row groups, rows and cells of `tg` so they paint as table parts.
noinline fn register(p: *Painter, tg: *const TG) Error!void {
    if (p.tparts.len == 0) {
        p.tparts = try p.keep.alloc(Part, p.f.nodes.items.len);
        @memset(p.tparts, .{});
    }
    const sep_hide = !tg.collapse;
    for (tg.secs, 0..) |sec, si| {
        if (sec.node != layout.tree.no_node and sec.node != tg.node) setPart(p, sec.node, .{ .g = tg, .idx = @intCast(si), .kind = .sec });
    }
    for (tg.rows, 0..) |row, ri| {
        if (row.node != layout.tree.no_node and row.node != tg.node) setPart(p, row.node, .{ .g = tg, .idx = @intCast(ri), .kind = .row, .hidden = row.collapsed });
    }
    for (tg.cells, 0..) |cell, ci| {
        if (cell.anon) continue;
        var hidden = cell.hidden;
        if (!hidden and sep_hide and !cell.has_content) {
            if (csOf(p, cell.node)) |cs| hidden = cs.empty_cells == .hide;
        }
        setPart(p, cell.node, .{ .g = tg, .idx = @intCast(ci), .kind = .cell, .hidden = hidden });
    }
}

/// Whether `cell` takes the backgrounds of the parts it lies in.
fn cellVisible(p: *Painter, tg: *const TG, ci: usize) bool {
    const cell = &tg.cells[ci];
    if (cell.hidden) return false;
    if (!cell.anon) {
        const id = nodeOf(p, cell.node);
        if (id >= p.tparts.len) return false;
        return !p.tparts[id].hidden and p.f.nodes.items[id].cs.visibility == .visible;
    }
    // an anonymous cell inherits from the innermost real box around it
    const row = &tg.rows[cell.row];
    var lid = row.node;
    if (lid == layout.tree.no_node) lid = tg.secs[row.sec].node;
    if (lid == layout.tree.no_node) lid = tg.node;
    const cs = csOf(p, lid) orelse return false;
    return cs.visibility == .visible;
}

fn unionRect(a: Rect, b: Rect) Rect {
    const x0 = @min(a.x, b.x);
    const y0 = @min(a.y, b.y);
    const x1 = @max(a.x + a.w, b.x + b.w);
    const y1 = @max(a.y + a.h, b.y + b.h);
    return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

/// The background of the part `id` (a row, row group, column or column group) into one cell:
/// positioned over `part` grown to cover the cell, clipped to the cell (takumi `draw_cell_background`).
noinline fn cellBackground(p: *Painter, ctx: *const Ctx, id: u32, part: Rect, cell: Rect) Error!void {
    if (!(cell.w > 0) or !(cell.h > 0)) return;
    const cs = p.f.nodes.items[id].cs;
    const area = unionRect(part, cell);
    const plain = ctx.plain();
    var g: Geom = .{
        .bx = if (plain) pm.snapRect(area.x, area.y, area.w, area.h) else area,
        .bw = .{ 0, 0, 0, 0 },
        .pad = .{ 0, 0, 0, 0 },
        .radii = undefined,
        .rounded = false,
        .snapped = plain,
    };
    g.radii = pm.resolveRadiiRaw(cs, g.bx.w, g.bx.h);
    pm.scaleRadii(&g.radii, g.bx.w, g.bx.h);
    g.rounded = pm.hasAnyRadius(g.radii);
    // takumi `within_cell`: the background clipped to the (unsnapped) cell rectangle
    // (a surface clip, as takumi's: each fill inside opens its own artifact when tagged)
    var clip: raster.Path = .empty;
    try dev.addRRect(p.a, &clip, cell, null);
    if (@import("emit_geom.zig").bounds(&clip) == null) return;
    const depth0 = p.s.depth();
    defer p.s.popTo(depth0);
    p.s.pushClip(&clip, .nonzero);
    try p.paintBackground(cs, &g, area.x, area.y);
}

/// Table decorations of render node `id` (a table or a part of one), when it is one; false =
/// the node paints like any other box.
pub fn decorations(e: *Painter, id: u32, x: f32, y: f32, g: *const Geom) Error!bool {
    const tg = e.f.tree.tableGeom(e.f.nodes.items[id].lid);
    if (tg == null and e.tparts.len == 0) return false;
    const c = e.ctx();
    return decorationsImpl(e, &c, id, x, y, g, tg);
}

/// Registers the parts of the table laid out at node `id` without painting (a table off the page).
pub fn registerParts(e: *Painter, id: u32) Error!void {
    const tg = e.f.tree.tableGeom(e.f.nodes.items[id].lid) orelse return;
    try register(e, tg);
}

/// The collapsed borders of the table laid out at node `id`, after everything inside it.
pub noinline fn collapsedAfter(e: *Painter, id: u32, x: f32, y: f32) Error!void {
    const tg = e.f.tree.tableGeom(e.f.nodes.items[id].lid) orelse return;
    if (!tg.collapse) return;
    const c = e.ctx();
    try paintCollapsed(e, &c, id, x, y, tg);
}

/// Row / row-group decorations: its shadows, and its background into each of its cells.
noinline fn paintPart(p: *Painter, ctx: *const Ctx, id: u32, g: *const Geom, tg: *const TG, tx: f32, ty: f32, part: Rect, row0: u32, n_rows: u32) Error!void {
    const cs = p.f.nodes.items[id].cs;
    if (cs.box_shadow.len > 0) try p.paintOuterShadows(cs, g);
    if (hasBackground(cs)) {
        var ri = row0;
        while (ri < row0 + n_rows and ri < tg.rows.len) : (ri += 1) {
            const row = &tg.rows[ri];
            if (row.collapsed) continue;
            var ci: usize = row.first;
            while (ci < row.first + row.n and ci < tg.cells.len) : (ci += 1) {
                if (!cellVisible(p, tg, ci)) continue;
                const cell = &tg.cells[ci];
                try cellBackground(p, ctx, id, part, .{ .x = tx + cell.x, .y = ty + cell.y, .w = cell.w, .h = cell.h });
            }
        }
    }
    if (cs.box_shadow.len > 0) try p.paintInsetShadows(cs, g);
}

/// `<col>` / `<colgroup>` backgrounds (Blink `TablePainter::PaintBoxDecorationBackground`): each over
/// the union of the sections, into the cells that start in its columns.
noinline fn paintColumns(p: *Painter, ctx: *const Ctx, tg: *const TG, tx: f32, ty: f32) Error!void {
    if (tg.colels.len == 0 or tg.secs.len == 0 or tg.cols.len == 0) return;
    var y0: f32 = std.math.floatMax(f32);
    var y1: f32 = -y0;
    for (tg.secs) |sec| {
        y0 = @min(y0, sec.y);
        y1 = @max(y1, sec.y + sec.h);
    }
    if (!(y1 >= y0)) return;
    for (tg.colels) |el| {
        if (el.span == 0 or el.start >= tg.cols.len) continue;
        const id = nodeOf(p, el.node);
        if (id >= p.f.nodes.items.len) continue;
        const cs = p.f.nodes.items[id].cs;
        if (!hasBackground(cs)) continue;
        const last = @min(@as(usize, el.start) + el.span - 1, tg.cols.len - 1);
        const first = &tg.cols[el.start];
        var area: Rect = .{
            .x = first.x - tg.cols[0].x,
            .y = ty + y0,
            .w = tg.cols[last].x + tg.cols[last].w - first.x,
            .h = y1 - y0,
        };
        // (a right-to-left table: the columns run from the right, as paint_table.zig)
        area.x = tx + tg.sec_x + (if (tg.rtl) tg.sec_w - area.x - area.w else area.x);
        for (tg.cells, 0..) |*cell, ci| {
            if (cell.col < el.start or cell.col >= el.start + el.span) continue;
            if (tg.rows[cell.row].collapsed or !cellVisible(p, tg, ci)) continue;
            try cellBackground(p, ctx, id, area, .{ .x = tx + cell.x, .y = ty + cell.y, .w = cell.w, .h = cell.h });
        }
    }
}

/// Box decorations of a node that is a table or a part of one. Returns false when the node paints
/// like any other box (the caller then does it). `tg` = the geometry of the table laid out at this
/// very node, `g` = the node's own box, (`x`, `y`) its origin.
noinline fn decorationsImpl(p: *Painter, ctx: *const Ctx, id: u32, x: f32, y: f32, g: *const Geom, tg_in: ?*const TG) Error!bool {
    const f = p.f;
    const n = &f.nodes.items[id];
    const cs = n.cs;
    const l = f.tree.layout(n.lid);
    if (tg_in) |tg| {
        try register(p, tg);
        if (tg.is_table) {
            if (cs.visibility != .visible) return true;
            // the grid box: everything but the captions
            // (collapsed borders: `l.border` holds the half edges; the border itself is not painted here)
            const gg = pm.Painter.geomOf(cs, &.{ .w = l.w, .h = tg.grid_h, .border = l.border, .padding = l.padding }, x, y + tg.grid_y, ctx);
            if (cs.box_shadow.len > 0) try p.paintOuterShadows(cs, &gg);
            try p.paintBackground(cs, &gg, x, y + tg.grid_y);
            if (cs.box_shadow.len > 0) try p.paintInsetShadows(cs, &gg);
            if (!tg.collapse) try border.paintBorder(&p.d, cs, &gg);
            try paintColumns(p, ctx, tg, x, y);
            return true;
        }
        // the anonymous table around a lone row / row group: the node is that part
        if (cs.visibility != .visible) return true;
        const part: Rect = .{ .x = x, .y = y, .w = l.w, .h = l.h };
        if (tg.rows.len > 0 and tg.rows[0].node == tg.node) {
            try paintPart(p, ctx, id, g, tg, x, y, part, 0, 1);
        } else try paintPart(p, ctx, id, g, tg, x, y, part, 0, @intCast(tg.rows.len));
        return true;
    }
    if (id >= p.tparts.len) return false;
    const part = p.tparts[id];
    const tg = part.g orelse return false;
    switch (part.kind) {
        .none => return false,
        .cell => {
            if (!tg.collapse) return false;
            if (cs.visibility != .visible) return true;
            if (cs.box_shadow.len > 0) try p.paintOuterShadows(cs, g);
            try p.paintBackground(cs, g, x, y);
            if (cs.box_shadow.len > 0) try p.paintInsetShadows(cs, g);
            return true;
        },
        .sec, .row => {
            if (cs.visibility != .visible) return true;
            // the table's origin from the part's place in it
            const px = tg.sec_x;
            var py: f32 = 0;
            var row0: u32 = part.idx;
            var n_rows: u32 = 1;
            if (part.kind == .sec) {
                if (part.idx >= tg.secs.len) return true;
                const sec = &tg.secs[part.idx];
                py = sec.y;
                row0 = sec.start;
                n_rows = sec.n_rows;
            } else {
                if (part.idx >= tg.rows.len) return true;
                const row = &tg.rows[part.idx];
                py = tg.secs[row.sec].y + row.y;
            }
            try paintPart(p, ctx, id, g, tg, x - px, y - py, .{ .x = x, .y = y, .w = l.w, .h = l.h }, row0, n_rows);
            return true;
        },
    }
}

// ---------------------------------------------------------------------------------------------------
// collapsed borders

const no_src: u32 = std.math.maxInt(u32);
const side_none: u3 = 4;
const top = 0;
const right = 1;
const bottom = 2;
const left = 3;

/// One edge of the grid (Blink `TableBorders::Edge`): the render node whose border fills it, the
/// side of that box, and the order the box was visited in.
const Edge = struct {
    src: u32 = no_src,
    /// box order << 3 | side (0..3 clockwise from the top; 4 = inside a spanning cell, never filled)
    os: u32 = 0,

    inline fn side(e: Edge) u3 {
        return @truncate(e.os);
    }
    inline fn order(e: Edge) u32 {
        return e.os >> 3;
    }
};

/// Blink `ComputedStyle::CollapsedBorderStyle`.
fn collapsedStyle(s: BStyle) BStyle {
    return switch (s) {
        .inset => .ridge,
        .outset => .groove,
        else => s,
    };
}

fn styleRank(s: BStyle) u8 {
    return switch (s) {
        .none => 0,
        .hidden => 1,
        .inset => 2,
        .groove => 3,
        .outset => 4,
        .ridge => 5,
        .dotted => 6,
        .dashed => 7,
        .solid => 8,
        .double => 9,
    };
}

/// LayoutUnit (1/64 px) of a length.
fn lu(v: f32) i32 {
    if (!(v > 0)) return 0;
    return @intFromFloat(@min(v * 64, 1.0e9));
}

fn luRel(v: f32) i32 {
    return @intFromFloat(std.math.clamp(@trunc(v * 64), -1.0e9, 1.0e9));
}

const Borders = struct {
    p: *Painter,
    edges: []Edge = &.{},
    epr: usize = 0,
    erows: usize = 0,
    /// columns of the grid (Blink's last_column_index)
    bc: u32,
    dry: bool = true,
    /// right-to-left table: the inline-start edge of a box is its right border
    rtl: bool = false,

    fn styleOfSide(b: *const Borders, src: u32, s: u3) BStyle {
        return collapsedStyle(b.p.f.nodes.items[src].cs.border_style[s]);
    }
    fn widthOfSide(b: *const Borders, src: u32, s: u3) i32 {
        const cs = b.p.f.nodes.items[src].cs;
        const st = cs.border_style[s];
        if (st == .none or st == .hidden) return 0;
        return lu(cs.usedBorderWidths()[s]);
    }

    fn width(b: *const Borders, i: usize) i32 {
        if (i >= b.edges.len) return 0;
        const e = b.edges[i];
        if (e.src == no_src or e.side() > 3) return 0;
        return b.widthOfSide(e.src, e.side());
    }
    fn styleAt(b: *const Borders, i: usize) BStyle {
        if (i >= b.edges.len) return .none;
        const e = b.edges[i];
        if (e.src == no_src or e.side() > 3) return .none;
        return b.styleOfSide(e.src, e.side());
    }
    fn color(b: *const Borders, i: usize) style.Color {
        const e = b.edges[i];
        const cs = b.p.f.nodes.items[e.src].cs;
        return cs.resolveColor(cs.border_color[e.side()]);
    }

    fn fit(b: *Borders, row: usize, col: usize) void {
        b.epr = @max(b.epr, (col + 2) * 2);
        b.erows = @max(b.erows, row + 2);
    }

    /// Blink `IsSourceMoreSpecificThanEdge`.
    fn moreSpecific(b: *const Borders, st: BStyle, w: i32, e: Edge) bool {
        if (e.side() == side_none) return false;
        if (e.src == no_src) return true;
        if (st == .hidden) return true;
        const est = b.styleOfSide(e.src, e.side());
        if (est == .hidden) return false;
        const ew = b.widthOfSide(e.src, e.side());
        if (w != ew) return w > ew;
        return styleRank(st) > styleRank(est);
    }

    fn put(b: *Borders, i: usize, src: u32, s: u3, order: u32, st: BStyle, w: i32) void {
        if (i >= b.edges.len) return;
        if (b.moreSpecific(st, w, b.edges[i])) b.edges[i] = .{ .src = src, .os = (order << 3) | s };
    }

    /// Blink `TableBorders::MergeBorders` for the box `lid` covering rows r0..r0+rs, columns c0..c0+cn.
    fn merge(b: *Borders, r0: usize, c0: usize, rs: usize, cn_in: usize, lid: u32, is_cell: bool, order: u32) void {
        if (rs == 0 or cn_in == 0) return;
        const cn = @min(cn_in, @as(usize, b.bc) -| c0);
        const src = nodeOf(b.p, lid);
        if (src >= b.p.f.nodes.items.len) return;
        var st: [4]BStyle = undefined;
        var any = false;
        for (0..4) |s| {
            st[s] = b.styleOfSide(src, @intCast(s));
            if (st[s] != .none) any = true;
        }
        const inner = is_cell and (rs > 1 or cn > 1);
        // sides at the inline start / end of the box
        const ss: u3 = if (b.rtl) right else left;
        const se: u3 = if (b.rtl) left else right;
        if (inner) {
            b.fit(r0 + rs - 1, (c0 + cn) -| 1);
        } else {
            if (!any) return;
            // only the edges a border fills need to exist
            b.fit(
                if (st[left] == .none and st[right] == .none and st[bottom] == .none) r0 else r0 + rs - 1,
                if (st[se] == .none and st[top] == .none and st[bottom] == .none) c0 else (c0 + cn) -| 1,
            );
        }
        if (b.dry) return;
        const epr = b.epr;
        if (st[top] != .none) {
            const w = b.widthOfSide(src, top);
            for (0..cn) |k| b.put(epr * r0 + (c0 + k) * 2 + 1, src, top, order, st[top], w);
        }
        if (st[bottom] != .none) {
            const w = b.widthOfSide(src, bottom);
            for (0..cn) |k| b.put(epr * (r0 + rs) + (c0 + k) * 2 + 1, src, bottom, order, st[bottom], w);
        }
        if (st[ss] != .none) {
            const w = b.widthOfSide(src, ss);
            for (0..rs) |k| b.put(epr * (r0 + k) + c0 * 2, src, ss, order, st[ss], w);
        }
        if (st[se] != .none) {
            const w = b.widthOfSide(src, se);
            for (0..rs) |k| b.put(epr * (r0 + k) + (c0 + cn) * 2, src, se, order, st[se], w);
        }
        if (inner) {
            // MarkInnerBordersAsDoNotFill: no part of the table draws inside a spanning cell
            for (0..rs) |k| {
                const base = epr * (r0 + k) + c0 * 2;
                for (1..@max(cn, 1)) |j| b.block(base + j * 2);
                if (k != 0) {
                    for (0..cn) |j| b.block(base + j * 2 + 1);
                }
            }
        }
    }
    fn block(b: *Borders, i: usize) void {
        if (i < b.edges.len and b.edges[i].src == no_src) b.edges[i].os = side_none;
    }

    /// Every box's borders in Blink's order: cells, rows, row groups, columns, column groups, table.
    fn mergeAll(b: *Borders, tg: *const TG, dry: bool) void {
        b.dry = dry;
        const nn = layout.tree.no_node;
        var order: u32 = 0;
        // (takumi marks the cells before the first spanning one twice; only the box order of the
        // second visit differs, and a later visit never replaces an equal border)
        for (tg.cells) |*cell| {
            order += 1;
            if (!cell.anon) b.merge(cell.row, cell.col, cell.rowspan, cell.colspan, cell.node, true, order);
        }
        for (tg.rows, 0..) |*row, ri| {
            order += 1;
            if (row.node != nn) b.merge(ri, 0, 1, b.bc, row.node, false, order);
        }
        for (tg.secs) |*sec| {
            order += 1;
            if (sec.node != nn) b.merge(sec.start, 0, sec.n_rows, b.bc, sec.node, false, order);
        }
        order += 1;
        for (tg.colels) |el| {
            if (el.group or el.start >= b.bc) continue;
            var k: usize = el.start;
            while (k < @min(@as(usize, el.start) + el.span, b.bc)) : (k += 1) b.merge(0, k, tg.rows.len, 1, el.node, false, order);
        }
        order += 1;
        for (tg.colels) |el| {
            if (el.group and el.start < b.bc) b.merge(0, el.start, tg.rows.len, el.span, el.node, false, order);
        }
        order += 1;
        if (tg.is_table) b.merge(0, 0, tg.rows.len, b.bc, tg.node, false, order);
    }

    // ---- painting (takumi `CollapsedEdge`)

    fn canPaint(b: *const Borders, i: ?usize) bool {
        const k = i orelse return false;
        if (k >= b.edges.len) return false;
        const st = b.styleAt(k);
        return st != .none and st != .hidden and b.width(k) != 0;
    }
    fn widthO(b: *const Borders, i: ?usize) i32 {
        return if (i) |k| b.width(k) else 0;
    }
    fn at(b: *const Borders, i: usize, off: isize) ?usize {
        const v = @as(isize, @intCast(i)) + off;
        if (v < 0 or v >= @as(isize, @intCast(b.edges.len))) return null;
        return @intCast(v);
    }

    /// Blink `TableCollapsedEdge::CompareForPaint`: 1 = `l` paints the joint, -1 = `r`, 0 = neither.
    fn compare(b: *const Borders, l: ?usize, r: ?usize) i8 {
        if (l != null and r != null and l.? == r.?) return 0;
        if (l == null and r == null) return 0;
        const lp = b.canPaint(l);
        const rp = b.canPaint(r);
        if (lp and rp) {
            const lw = b.width(l.?);
            const rw = b.width(r.?);
            if (lw != rw) return if (lw > rw) 1 else -1;
            const ls = b.styleAt(l.?);
            const rs = b.styleAt(r.?);
            if (ls == rs) {
                const lo = b.edges[l.?].order();
                const ro = b.edges[r.?].order();
                return if (lo < ro) 1 else if (lo > ro) -1 else 0;
            }
            if (rs == .hidden) return 1;
            if (ls == .hidden) return -1;
            return if (styleRank(ls) > styleRank(rs)) 1 else -1;
        }
        if (!lp and !rp) return 0;
        return if (lp) 1 else -1;
    }

    const Joint = struct { inline_size: i32, block_size: i32, ic: i8, bc: i8, ivb: i8 };

    fn joint(b: *const Borders, before: ?usize, after: ?usize, over: ?usize, under: ?usize, drops_block: bool) Joint {
        const ic = b.compare(before, after);
        const block_size = if (drops_block) 0 else if (ic == 1) b.widthO(before) else b.widthO(after);
        const bcmp = b.compare(over, under);
        const inline_size = if (bcmp == 1) b.widthO(over) else b.widthO(under);
        const ivb = b.compare(if (ic == 1) before else after, if (bcmp == 1) over else under);
        return .{ .inline_size = inline_size, .block_size = block_size, .ic = ic, .bc = bcmp, .ivb = ivb };
    }
};

fn roundPx(v: f32) f32 {
    return @round(v);
}

/// Blink `TablePainter::PaintCollapsedBorders` for the table laid out at node `id`, whose border
/// box is at (`x`, `y`): painted after everything inside the table.
pub noinline fn paintCollapsed(p: *Painter, ctx: *const Ctx, id: u32, x: f32, y: f32, tg: *const TG) Error!void {
    if (!tg.collapse or tg.n_bcols == 0 or tg.rows.len == 0) return;
    if (p.f.nodes.items[id].cs.visibility != .visible) return;
    var b: Borders = .{ .p = p, .bc = tg.n_bcols, .rtl = tg.rtl };
    b.mergeAll(tg, true);
    if (b.epr == 0) return;
    const len = std.math.mul(usize, b.epr, b.erows) catch return;
    if (len > (1 << 21)) return;
    b.edges = try p.a.alloc(Edge, len);
    @memset(b.edges, .{});
    b.mergeAll(tg, false);

    const per_row = b.epr;
    const pr: isize = @intCast(per_row);
    var prev_row: ?usize = null;
    for (tg.secs) |*sec| {
        if (sec.n_rows == 0) continue;
        const end = @min((@as(usize, sec.start) + sec.n_rows + 1) * per_row, b.edges.len);
        var index: usize = @as(usize, sec.start) * per_row;
        while (index < end) : (index += 1) {
            if (!b.canPaint(index)) continue;
            const trow = index / per_row;
            const tcol = (index % per_row) / 2;
            const frow = trow - sec.start;
            if (tcol >= tg.cols.len + 1) continue;
            const w = b.width(index);
            const inline_axis = (index % per_row) % 2 != 0;
            const row_start: i32 = if (frow < sec.n_rows) luRel(tg.rows[sec.start + frow].y) else luRel(sec.h);
            const col_start: i32 = colEdge(tg, tcol);
            var is: i32 = undefined;
            var bs: i32 = undefined;
            var isz: i32 = undefined;
            var bsz: i32 = undefined;
            if (inline_axis) {
                if (prev_row != null and prev_row.? == trow) continue;
                if (tcol + 1 > tg.cols.len) continue;
                const s = b.joint(b.at(index, -2), index, b.at(index, -(pr + 1)), b.at(index, -1), false);
                const e = b.joint(index, b.at(index, 2), b.at(index, -(pr - 1)), b.at(index, 1), false);
                const start_wins = s.ivb != -1 and s.ic != 1;
                const end_wins = e.ivb != -1 and e.ic != -1;
                is = col_start;
                isz = colEdge(tg, tcol + 1) - col_start;
                bs = row_start - @divTrunc(w, 2);
                bsz = w;
                const sj = @divTrunc(s.inline_size, 2);
                const ej = @divTrunc(e.inline_size, 2);
                if (start_wins) {
                    is -= sj;
                    isz += sj;
                } else {
                    is += sj;
                    isz -= sj;
                }
                if (end_wins) isz += ej else isz -= ej;
            } else {
                // a column line runs only to the last row of the section
                if (frow >= sec.n_rows) continue;
                const s = b.joint(b.at(index, -1), b.at(index, 1), b.at(index, -pr), index, false);
                const e = b.joint(b.at(index, pr - 1), b.at(index, pr + 1), index, b.at(index, pr), false);
                const start_wins = s.ivb != 1 and s.bc != 1;
                const end_wins = e.ivb != 1 and e.bc != -1;
                var row_end: i32 = if (frow + 1 < sec.n_rows) luRel(tg.rows[sec.start + frow + 1].y) else luRel(sec.h);
                // (a row a page break left above the next one ends at its own end: takumi paints
                // the collapsed borders of each table fragment)
                if (frow + 1 < sec.n_rows) {
                    const r = &tg.rows[sec.start + frow];
                    const own_end = luRel(r.y + r.h);
                    if (own_end < row_end - 64) row_end = own_end;
                }
                bs = row_start;
                bsz = row_end - row_start;
                is = col_start - @divTrunc(w, 2);
                isz = w;
                const sj = @divTrunc(s.block_size, 2);
                const ej = @divTrunc(e.block_size, 2);
                if (start_wins) {
                    bs -= sj;
                    bsz += sj;
                } else {
                    bs += sj;
                    bsz -= sj;
                }
                if (end_wins) bsz += ej else bsz -= ej;
            }
            if (tg.rtl) is = luRel(tg.sec_w) - is - isz;
            // (a row line between rows a page break separated is drawn at the end of the one above
            // too: each table fragment paints its own block-end border, takumi)
            var starts: [2]i32 = .{ bs, bs };
            var n_starts: usize = 1;
            // (the end of the fragment above, which its piece stops at for the pages it shows on)
            var frag_end: ?f32 = null;
            if (inline_axis and frow > 0 and frow < sec.n_rows) {
                const pr_row = &tg.rows[sec.start + frow - 1];
                const prev_end = luRel(pr_row.y + pr_row.h);
                if (prev_end < row_start - 64) {
                    starts = .{ prev_end - @divTrunc(w, 2), bs };
                    n_starts = 2;
                    frag_end = y + sec.y + @as(f32, @floatFromInt(prev_end)) / 64;
                }
            }
            _ = ctx;
            for (starts[0..n_starts], 0..) |bs_k, k_start| {
                const fx = x + tg.sec_x + @as(f32, @floatFromInt(is)) / 64;
                const fy = y + sec.y + @as(f32, @floatFromInt(bs_k)) / 64;
                const x1 = roundPx(fx);
                const y1 = roundPx(fy);
                const x2 = @max(roundPx(fx + @as(f32, @floatFromInt(isz)) / 64), x1);
                const y2 = @max(roundPx(fy + @as(f32, @floatFromInt(bsz)) / 64), y1);
                // (a page of a paginated document draws the borders on it, once)
                const hi = if (k_start == 0 and n_starts == 2) @min(@max(y1, y2), frag_end.?) else @max(y1, y2);
                if (!p.pieceShows(@min(y1, y2), hi)) continue;
                try border.paintSideRect(&p.d, if (inline_axis) 0 else 3, x1, y1, x2, y2, b.styleAt(index), b.color(index));
            }
        }
        prev_row = @as(usize, sec.start) + sec.n_rows;
    }
}

/// Inline-start edge of column `k` (the inline-end edge of the last one for k = cols.len).
fn colEdge(tg: *const TG, k: usize) i32 {
    if (tg.cols.len == 0) return 0;
    if (k < tg.cols.len) return luRel(tg.cols[k].x);
    const last = &tg.cols[tg.cols.len - 1];
    return luRel(last.x) + luRel(last.w);
}
