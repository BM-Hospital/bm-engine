//! Tests: hand-written unit tests + replay of oracle fixtures generated from @takumi-rs/wasm
//! (bench/probe/layout/gen.mjs -> testdata/oracle.json).
const std = @import("std");
pub const L = @import("layout.zig");
const testing = std.testing;
const Style = L.Style;
const Tree = L.Tree;
const Dim = L.Dim;

pub fn noMeasure(_: *anyopaque, _: L.NodeId, _: [2]?f32, _: [2]L.AvailableSpace) [2]f32 {
    return .{ 0, 0 };
}
pub var dummy: u8 = 0;

// ---------------------------------------------------------------------------------------------------
// fixture JSON -> Style translator (test only)

pub const J = std.json.Value;

pub fn num(v: J) f32 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        .string => |s| parseNum(s),
        else => 0,
    };
}
fn parseNum(s_: []const u8) f32 {
    var s = std.mem.trim(u8, s_, " ");
    if (std.mem.endsWith(u8, s, "px")) s = s[0 .. s.len - 2];
    if (std.mem.endsWith(u8, s, "fr")) s = s[0 .. s.len - 2];
    if (std.mem.endsWith(u8, s, "%")) s = s[0 .. s.len - 1];
    return std.fmt.parseFloat(f32, s) catch 0;
}
fn dimStr(s_: []const u8) Dim {
    const s = std.mem.trim(u8, s_, " ");
    if (std.mem.eql(u8, s, "auto")) return .auto;
    if (std.mem.endsWith(u8, s, "%")) return .{ .percent = parseNum(s) / 100 };
    return .{ .px = parseNum(s) };
}
fn dim(v: J) Dim {
    return switch (v) {
        .string => |s| dimStr(s),
        else => .{ .px = num(v) },
    };
}
fn lp(v: J) L.LengthPercentage {
    return switch (dim(v)) {
        .percent => |p| .{ .percent = p },
        .px => |p| .{ .px = p },
        else => .{ .px = 0 },
    };
}
fn dimEdges(v: J) L.Edges(Dim) {
    switch (v) {
        .string => |s| {
            var parts: [4]Dim = undefined;
            var n: usize = 0;
            var it = std.mem.tokenizeScalar(u8, s, ' ');
            while (it.next()) |p| {
                if (n < 4) {
                    parts[n] = dimStr(p);
                    n += 1;
                }
            }
            return switch (n) {
                1 => .all(parts[0]),
                2 => .{ .top = parts[0], .bottom = parts[0], .left = parts[1], .right = parts[1] },
                3 => .{ .top = parts[0], .left = parts[1], .right = parts[1], .bottom = parts[2] },
                else => .{ .top = parts[0], .right = parts[1], .bottom = parts[2], .left = parts[3] },
            };
        },
        else => return .all(dim(v)),
    }
}
fn isSafe(v: J) bool {
    return std.mem.startsWith(u8, v.string, "safe ");
}
fn alignOf(v: J) ?L.Align {
    var s = v.string;
    if (std.mem.startsWith(u8, s, "safe ")) s = s[5..];
    if (std.mem.startsWith(u8, s, "unsafe ")) s = s[7..];
    const map = .{
        .{ "start", L.Align.start },               .{ "end", L.Align.end },
        .{ "flex-start", L.Align.flex_start },     .{ "flex-end", L.Align.flex_end },
        .{ "center", L.Align.center },             .{ "stretch", L.Align.stretch },
        .{ "baseline", L.Align.baseline },         .{ "space-between", L.Align.space_between },
        .{ "space-around", L.Align.space_around }, .{ "space-evenly", L.Align.space_evenly },
    };
    inline for (map) |e| if (std.mem.eql(u8, s, e[0])) return e[1];
    return null;
}
fn breadth(s_: []const u8) L.TrackBreadth {
    const s = std.mem.trim(u8, s_, " ");
    if (std.mem.eql(u8, s, "auto")) return .auto;
    if (std.mem.eql(u8, s, "min-content")) return .min_content;
    if (std.mem.eql(u8, s, "max-content")) return .max_content;
    if (std.mem.endsWith(u8, s, "fr")) return .{ .fr = parseNum(s) };
    if (std.mem.endsWith(u8, s, "%")) return .{ .percent = parseNum(s) / 100 };
    return .{ .px = parseNum(s) };
}
fn oneTrack(s: []const u8) L.Track {
    if (std.mem.startsWith(u8, s, "minmax(")) {
        const inner = s[7 .. s.len - 1];
        const comma = std.mem.indexOfScalar(u8, inner, ',').?;
        return .{ .min = breadth(inner[0..comma]), .max = breadth(inner[comma + 1 ..]) };
    }
    if (std.mem.startsWith(u8, s, "fit-content(")) {
        const d = dimStr(s[12 .. s.len - 1]);
        return L.Track.fitContent(switch (d) {
            .percent => |p| .{ .percent = p },
            .px => |p| .{ .px = p },
            else => .{ .px = 0 },
        });
    }
    const b = breadth(s);
    return switch (b) {
        .fr => .{ .min = .auto, .max = b },
        else => .{ .min = b, .max = b },
    };
}
/// Splits a track list on top-level spaces.
fn splitTop(a: std.mem.Allocator, s: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var depth: usize = 0;
    var start: ?usize = null;
    for (s, 0..) |c, i| {
        if (c == '(') depth += 1;
        if (c == ')') depth -= 1;
        if (c == ' ' and depth == 0) {
            if (start) |st| try out.append(a, s[st..i]);
            start = null;
        } else if (start == null) start = i;
    }
    if (start) |st| try out.append(a, s[st..]);
    return out.items;
}
const TrackList = struct { tracks: []const L.Track, rep: ?L.AutoRepeat };
fn tracks(a: std.mem.Allocator, v: J) !TrackList {
    var out: std.ArrayList(L.Track) = .empty;
    var rep: ?L.AutoRepeat = null;
    for (try splitTop(a, v.string)) |p| {
        if (std.mem.startsWith(u8, p, "repeat(")) {
            const inner = p[7 .. p.len - 1];
            const comma = std.mem.indexOfScalar(u8, inner, ',').?;
            const cnt = std.mem.trim(u8, inner[0..comma], " ");
            var sub: std.ArrayList(L.Track) = .empty;
            for (try splitTop(a, std.mem.trim(u8, inner[comma + 1 ..], " "))) |q| try sub.append(a, oneTrack(q));
            if (std.mem.eql(u8, cnt, "auto-fill") or std.mem.eql(u8, cnt, "auto-fit")) {
                rep = .{ .fit = std.mem.eql(u8, cnt, "auto-fit"), .tracks = sub.items, .at = @intCast(out.items.len) };
            } else {
                const k = std.fmt.parseInt(usize, cnt, 10) catch 1;
                for (0..k) |_| try out.appendSlice(a, sub.items);
            }
        } else try out.append(a, oneTrack(p));
    }
    return .{ .tracks = out.items, .rep = rep };
}
fn gridLine(s_: []const u8) L.Line {
    const s = std.mem.trim(u8, s_, " ");
    if (std.mem.eql(u8, s, "auto")) return .auto;
    if (std.mem.startsWith(u8, s, "span")) return .{ .span = std.fmt.parseInt(u16, std.mem.trim(u8, s[4..], " "), 10) catch 1 };
    return .{ .line = std.fmt.parseInt(i16, s, 10) catch 0 };
}
fn placement(v: J) L.Placement {
    switch (v) {
        .string => |s| {
            if (std.mem.indexOfScalar(u8, s, '/')) |i| return .{ .start = gridLine(s[0..i]), .end = gridLine(s[i + 1 ..]) };
            return .{ .start = gridLine(s) };
        },
        else => return .{ .start = .{ .line = @intFromFloat(num(v)) } },
    }
}

pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn styleFrom(a: std.mem.Allocator, obj: J) !Style {
    var s: Style = .{ .position = .static };
    var it = obj.object.iterator();
    while (it.next()) |kv| {
        const k = kv.key_ptr.*;
        const v = kv.value_ptr.*;
        if (eq(k, "display")) {
            const d = v.string;
            s.display = .none;
            inline for (.{
                .{ "flex", .flex },                             .{ "block", .block },                       .{ "grid", .grid },
                .{ "table", .table },                           .{ "inline-table", .inline_table },         .{ "table-row-group", .table_row_group },
                .{ "table-header-group", .table_header_group }, .{ "table-footer-group", .table_footer_group }, .{ "table-row", .table_row },
                .{ "table-cell", .table_cell },                 .{ "table-caption", .table_caption },       .{ "table-column", .table_column },
                .{ "table-column-group", .table_column_group }, .{ "inline-row", .inline_row },             .{ "flow-root", .block },
                .{ "inline-block", .block },                    .{ "inline-flex", .flex },                  .{ "inline-grid", .grid },
            }) |p| {
                if (eq(d, p[0])) s.display = p[1];
            }
            if (eq(d, "flow-root")) s.flow_root = true;
        } else if (eq(k, "position")) {
            s.position = if (eq(v.string, "absolute")) .absolute else if (eq(v.string, "relative")) .relative else if (eq(v.string, "fixed")) .fixed else .static;
        } else if (eq(k, "float")) {
            s.float = if (eq(v.string, "left")) .left else if (eq(v.string, "right")) .right else .none;
        } else if (eq(k, "clear")) {
            s.clear = if (eq(v.string, "left")) .left else if (eq(v.string, "right")) .right else if (eq(v.string, "both")) .both else .none;
        } else if (eq(k, "order")) {
            s.order = @intFromFloat(num(v));
        } else if (eq(k, "visibility")) {
            s.visibility_collapse = eq(v.string, "collapse");
        } else if (eq(k, "borderSpacing")) {
            const e = dimEdges(v); // "h v" (dimEdges reads two values as vertical/horizontal pairs: top=first, right=second)
            s.border_spacing = .{ lpPx(e.top), lpPx(e.right) };
        } else if (eq(k, "borderCollapse")) {
            s.border_collapse = eq(v.string, "collapse");
        } else if (eq(k, "tableLayout")) {
            s.table_fixed = eq(v.string, "fixed");
        } else if (eq(k, "captionSide")) {
            s.caption_bottom = eq(v.string, "bottom");
        } else if (eq(k, "verticalAlign")) {
            s.vertical_align = if (eq(v.string, "top")) .top else if (eq(v.string, "middle")) .middle else if (eq(v.string, "bottom")) .bottom else .baseline;
        } else if (eq(k, "textAlign")) {
            s.text_align = if (eq(v.string, "center")) .center else if (eq(v.string, "end") or eq(v.string, "right")) .end else if (eq(v.string, "justify")) .justify else .start;
        } else if (eq(k, "colSpan")) {
            s.col_span = @intFromFloat(@max(num(v), 1));
        } else if (eq(k, "rowSpan")) {
            s.row_span = @intFromFloat(@max(num(v), 1));
        } else if (eq(k, "strutAscent")) {
            s.strut_ascent = num(v);
        } else if (eq(k, "strutDescent")) {
            s.strut_descent = num(v);
        } else if (eq(k, "boxSizing")) {
            s.box_sizing = if (eq(v.string, "content-box")) .content_box else .border_box;
        } else if (eq(k, "overflow")) {
            const o: L.style.Overflow = if (eq(v.string, "hidden")) .hidden else if (eq(v.string, "scroll")) .scroll else if (eq(v.string, "clip")) .clip else .visible;
            s.overflow_x = o;
            s.overflow_y = o;
        } else if (eq(k, "width")) {
            s.size[0] = dim(v);
        } else if (eq(k, "height")) {
            s.size[1] = dim(v);
        } else if (eq(k, "minWidth")) {
            s.min_size[0] = dim(v);
        } else if (eq(k, "minHeight")) {
            s.min_size[1] = dim(v);
        } else if (eq(k, "maxWidth")) {
            s.max_size[0] = dim(v);
        } else if (eq(k, "maxHeight")) {
            s.max_size[1] = dim(v);
        } else if (eq(k, "aspectRatio")) {
            s.aspect_ratio = num(v);
        } else if (eq(k, "margin")) {
            s.margin = dimEdges(v);
        } else if (eq(k, "marginTop")) {
            s.margin.top = dim(v);
        } else if (eq(k, "marginRight")) {
            s.margin.right = dim(v);
        } else if (eq(k, "marginBottom")) {
            s.margin.bottom = dim(v);
        } else if (eq(k, "marginLeft")) {
            s.margin.left = dim(v);
        } else if (eq(k, "padding")) {
            const e = dimEdges(v);
            s.padding = .{ .top = lpOf(e.top), .right = lpOf(e.right), .bottom = lpOf(e.bottom), .left = lpOf(e.left) };
        } else if (eq(k, "paddingTop")) {
            s.padding.top = lp(v);
        } else if (eq(k, "paddingRight")) {
            s.padding.right = lp(v);
        } else if (eq(k, "paddingBottom")) {
            s.padding.bottom = lp(v);
        } else if (eq(k, "paddingLeft")) {
            s.padding.left = lp(v);
        } else if (eq(k, "borderWidth")) {
            s.border = .all(num(v));
        } else if (eq(k, "borderTopWidth")) {
            s.border.top = num(v);
        } else if (eq(k, "borderRightWidth")) {
            s.border.right = num(v);
        } else if (eq(k, "borderBottomWidth")) {
            s.border.bottom = num(v);
        } else if (eq(k, "borderLeftWidth")) {
            s.border.left = num(v);
        } else if (eq(k, "borderStyle")) {
            //
        } else if (eq(k, "inset")) {
            s.inset = dimEdges(v);
        } else if (eq(k, "top")) {
            s.inset.top = dim(v);
        } else if (eq(k, "right")) {
            s.inset.right = dim(v);
        } else if (eq(k, "bottom")) {
            s.inset.bottom = dim(v);
        } else if (eq(k, "left")) {
            s.inset.left = dim(v);
        } else if (eq(k, "gap")) {
            const e = dimEdges(v); // row-gap column-gap
            s.gap = .{ lpOf(e.left), lpOf(e.top) };
        } else if (eq(k, "columnGap")) {
            s.gap[0] = lp(v);
        } else if (eq(k, "rowGap")) {
            s.gap[1] = lp(v);
        } else if (eq(k, "flexDirection")) {
            s.flex_direction = if (eq(v.string, "row")) .row else if (eq(v.string, "column")) .column else if (eq(v.string, "row-reverse")) .row_reverse else .column_reverse;
        } else if (eq(k, "flexWrap")) {
            s.flex_wrap = if (eq(v.string, "wrap")) .wrap else if (eq(v.string, "wrap-reverse")) .wrap_reverse else .nowrap;
        } else if (eq(k, "flexGrow")) {
            s.flex_grow = num(v);
        } else if (eq(k, "flexShrink")) {
            s.flex_shrink = num(v);
        } else if (eq(k, "flexBasis")) {
            s.flex_basis = dim(v);
        } else if (eq(k, "alignItems")) {
            s.align_items = alignOf(v);
            s.safe.align_items = isSafe(v);
        } else if (eq(k, "alignSelf")) {
            s.align_self = alignOf(v);
            s.safe.align_self = isSafe(v);
        } else if (eq(k, "alignContent")) {
            s.align_content = alignOf(v);
            s.safe.align_content = isSafe(v);
        } else if (eq(k, "justifyContent")) {
            s.justify_content = alignOf(v);
            s.safe.justify_content = isSafe(v);
        } else if (eq(k, "justifyItems")) {
            s.justify_items = alignOf(v);
            s.safe.justify_items = isSafe(v);
        } else if (eq(k, "justifySelf")) {
            s.justify_self = alignOf(v);
            s.safe.justify_self = isSafe(v);
        } else if (eq(k, "gridTemplateColumns")) {
            const tl = try tracks(a, v);
            s.grid_template_columns = tl.tracks;
            s.grid_auto_repeat_columns = tl.rep;
        } else if (eq(k, "gridTemplateRows")) {
            const tl = try tracks(a, v);
            s.grid_template_rows = tl.tracks;
            s.grid_auto_repeat_rows = tl.rep;
        } else if (eq(k, "gridAutoColumns")) {
            s.grid_auto_columns = (try tracks(a, v)).tracks;
        } else if (eq(k, "gridAutoRows")) {
            s.grid_auto_rows = (try tracks(a, v)).tracks;
        } else if (eq(k, "gridAutoFlow")) {
            s.grid_auto_flow = if (eq(v.string, "row")) .row else if (eq(v.string, "column")) .column else if (eq(v.string, "row dense") or eq(v.string, "dense")) .row_dense else .column_dense;
        } else if (eq(k, "gridColumn")) {
            s.grid_column = placement(v);
        } else if (eq(k, "gridRow")) {
            s.grid_row = placement(v);
        } else {
            std.debug.print("unknown style key {s}\n", .{k});
            return error.UnknownKey;
        }
    }
    return s;
}
fn lpPx(d: Dim) f32 {
    return switch (d) {
        .px => |p| p,
        else => 0,
    };
}
fn lpOf(d: Dim) L.LengthPercentage {
    return switch (d) {
        .percent => |p| .{ .percent = p },
        .px => |p| .{ .px = p },
        else => .{ .px = 0 },
    };
}

pub fn buildNode(a: std.mem.Allocator, t: *Tree, v: J) !L.NodeId {
    const s = if (v.object.get("style")) |so| try styleFrom(a, so) else Style{};
    const id = try t.addNode(s);
    if (v.object.get("children")) |ch| {
        for (ch.array.items) |c| try t.appendChild(id, try buildNode(a, t, c));
    }
    return id;
}

const tol: f32 = 0.07;

pub fn compareNode(t: *const Tree, id: L.NodeId, ox: f32, oy: f32, exp: J, bad: *usize, verbose: bool) void {
    const l = t.layout(id);
    const o = exp.object;
    if (o.get("none") != null) {
        if (l.w != 0 or l.h != 0) bad.* += 1;
        return;
    }
    const ex = num(o.get("x").?);
    const ey = num(o.get("y").?);
    const ew = num(o.get("w").?);
    const eh = num(o.get("h").?);
    const ax = ox + l.x;
    const ay = oy + l.y;
    if (@abs(ax - ex) > tol or @abs(ay - ey) > tol or @abs(l.w - ew) > tol or @abs(l.h - eh) > tol) {
        bad.* += 1;
        if (verbose) std.debug.print("    node {d}: got x={d:.3} y={d:.3} w={d:.3} h={d:.3}  want x={d:.3} y={d:.3} w={d:.3} h={d:.3}\n", .{ id, ax, ay, l.w, l.h, ex, ey, ew, eh });
    }
    const kids = if (o.get("children")) |c| c.array.items else &[_]J{};
    var ch = t.firstChild(id);
    var i: usize = 0;
    while (ch != L.tree.no_node) : (ch = t.nextSibling(ch)) {
        if (i < kids.len) compareNode(t, ch, ax, ay, kids[i], bad, verbose) else bad.* += 1;
        i += 1;
    }
    if (i != kids.len) bad.* += 1;
}

test "oracle fixtures (takumi wasm)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const parsed = try std.json.parseFromSliceLeaky(J, a, @embedFile("testdata/oracle.json"), .{});
    const xfail = @embedFile("testdata/oracle_xfail.txt");
    var total: usize = 0;
    var failed: usize = 0;
    var known_bad: usize = 0;
    for (parsed.array.items) |case| {
        const o = case.object;
        const name = o.get("name").?.string;
        const vp = o.get("vp").?.array.items;
        var t = Tree.init(a);
        const root = try buildNode(a, &t, o.get("node").?);
        const av: [2]L.AvailableSpace = .{ .{ .definite = num(vp[0]) }, .{ .definite = num(vp[1]) } };
        try t.compute(root, av, &dummy, noMeasure, .{});
        var bad: usize = 0;
        // takumi reports positions relative to the root's border box
        const rx = -t.layout(root).x;
        const ry = -t.layout(root).y;
        compareNode(&t, root, rx, ry, o.get("expect").?, &bad, false);
        total += 1;
        var is_xfail = false;
        var xit = std.mem.tokenizeAny(u8, xfail, "\r\n");
        while (xit.next()) |x| is_xfail = is_xfail or eq(x, name);
        if (is_xfail) {
            // known deviation from the oracle (see the list file); it must still deviate, else the list is stale
            known_bad += 1;
            if (bad == 0) {
                failed += 1;
                std.debug.print("STALE-XFAIL {s}\n", .{name});
            }
            continue;
        }
        if (bad != 0) {
            failed += 1;
            std.debug.print("FAIL {s}\n", .{name});
            compareNode(&t, root, rx, ry, o.get("expect").?, &bad, true);
        }
    }
    std.debug.print("oracle fixtures: {d}/{d} match takumi within {d} px ({d} known deviations listed in testdata/oracle_xfail.txt, {d} unexpected)\n", .{ total - known_bad - failed, total, tol, known_bad, failed });
    try testing.expect(failed == 0);
}

// Developer aid: set to a fixture name to dump the computed layout of that case.
const debug_case: []const u8 = "";

fn dumpNode(t: *const Tree, id: L.NodeId, ox: f32, oy: f32, depth: usize) void {
    const l = t.layout(id);
    for (0..depth) |_| std.debug.print("  ", .{});
    std.debug.print("#{d} {d:.3},{d:.3} {d:.3}x{d:.3}\n", .{ id, ox + l.x, oy + l.y, l.w, l.h });
    var ch = t.firstChild(id);
    while (ch != L.tree.no_node) : (ch = t.nextSibling(ch)) dumpNode(t, ch, ox + l.x, oy + l.y, depth + 1);
}

test "debug dump" {
    if (debug_case.len == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const parsed = try std.json.parseFromSliceLeaky(J, a, @embedFile("testdata/oracle.json"), .{});
    for (parsed.array.items) |case| {
        const o = case.object;
        if (!eq(o.get("name").?.string, debug_case)) continue;
        const vp = o.get("vp").?.array.items;
        var t = Tree.init(a);
        const root = try buildNode(a, &t, o.get("node").?);
        try t.compute(root, .{ .{ .definite = num(vp[0]) }, .{ .definite = num(vp[1]) } }, &dummy, noMeasure, .{});
        dumpNode(&t, root, 0, 0, 0);
    }
}

// ---------------------------------------------------------------------------------------------------
// hand-written unit tests

const px = struct {
    fn d(v: f32) Dim {
        return .{ .px = v };
    }
    fn size(w: f32, h: f32) [2]Dim {
        return .{ .{ .px = w }, .{ .px = h } };
    }
}.d;
fn sz(w: f32, h: f32) [2]Dim {
    return .{ .{ .px = w }, .{ .px = h } };
}
const vp400: [2]L.AvailableSpace = .{ .{ .definite = 400 }, .{ .definite = 300 } };

fn mk(t: *Tree, parent: L.NodeId, styles: []const Style) ![8]L.NodeId {
    var out: [8]L.NodeId = undefined;
    for (styles, 0..) |s, i| {
        out[i] = try t.addNode(s);
        try t.appendChild(parent, out[i]);
    }
    return out;
}
fn expectRect(t: *const Tree, id: L.NodeId, x: f32, y: f32, w: f32, h: f32) !void {
    const l = t.layout(id);
    const ok = @abs(l.x - x) < 0.01 and @abs(l.y - y) < 0.01 and @abs(l.w - w) < 0.01 and @abs(l.h - h) < 0.01;
    if (!ok) {
        std.debug.print("node {d}: got {d:.3},{d:.3} {d:.3}x{d:.3} want {d:.3},{d:.3} {d:.3}x{d:.3}\n", .{ id, l.x, l.y, l.w, l.h, x, y, w, h });
        return error.TestExpectedEqual;
    }
}
fn run(t: *Tree, root: L.NodeId) !void {
    try t.compute(root, vp400, &dummy, noMeasure, .{});
}

test "flex: grow, shrink, basis, gap, padding, border" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .size = sz(300, 100), .padding = .all(.{ .px = 10 }), .border = .all(5), .gap = .{ .{ .px = 10 }, .{ .px = 0 } } });
    const k = try mk(&t, root, &.{
        .{ .size = .{ px(50), .auto } },
        .{ .flex_grow = 1 },
        .{ .flex_grow = 2, .flex_basis = px(20) },
    });
    try run(&t, root);
    // inner width 270, gaps 20, fixed 50 + 0 + 20 -> free 180 -> 60 / 120
    try expectRect(&t, k[0], 15, 15, 50, 70);
    try expectRect(&t, k[1], 75, 15, 60, 70);
    try expectRect(&t, k[2], 145, 15, 140, 70);
    try testing.expectEqual(@as(f32, 10), t.layout(root).padding.left);
    try testing.expectEqual(@as(f32, 5), t.layout(root).border.top);

    // shrink with weights and a min-width clamp
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .size = sz(200, 50) });
    const k2 = try mk(&t2, r2, &.{
        .{ .size = sz(150, 20), .min_size = .{ px(120), .auto } },
        .{ .size = sz(150, 20) },
        .{ .size = sz(100, 20), .flex_shrink = 0 },
    });
    try run(&t2, r2);
    try expectRect(&t2, k2[0], 0, 0, 120, 20);
    try expectRect(&t2, k2[1], 120, 0, 0, 20);
    try expectRect(&t2, k2[2], 120, 0, 100, 20);
}

test "flex: direction, wrap, align-content, justify, align-self, auto margins" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .size = sz(200, 200), .flex_wrap = .wrap, .align_content = .space_between, .justify_content = .center, .gap = .{ .{ .px = 10 }, .{ .px = 10 } } });
    const k = try mk(&t, root, &.{ .{ .size = sz(80, 40) }, .{ .size = sz(80, 50) }, .{ .size = sz(80, 30), .align_self = .end } });
    try run(&t, root);
    try expectRect(&t, k[0], 15, 0, 80, 40);
    try expectRect(&t, k[1], 105, 0, 80, 50);
    try expectRect(&t, k[2], 60, 170, 80, 30);

    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .size = sz(300, 200), .flex_direction = .column_reverse, .align_items = .center });
    const k2 = try mk(&t2, r2, &.{
        .{ .size = sz(50, 40) },
        .{ .size = sz(60, 30), .margin = .{ .top = .auto, .right = .{ .px = 0 }, .bottom = .{ .px = 0 }, .left = .auto } },
        .{ .size = .{ .auto, px(20) }, .align_self = .stretch },
    });
    try run(&t2, r2);
    try expectRect(&t2, k2[0], 125, 160, 50, 40);
    try expectRect(&t2, k2[1], 240, 130, 60, 30);
    try expectRect(&t2, k2[2], 0, 0, 300, 20);
}

test "flex: percent, min/max, aspect-ratio, content-box, nested auto sizes" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .size = sz(300, 200), .align_items = .flex_start });
    const k = try mk(&t, root, &.{
        .{ .size = .{ .{ .percent = 0.5 }, .{ .percent = 0.25 } }, .max_size = .{ px(120), .auto } },
        .{ .size = .{ px(60), .auto }, .aspect_ratio = 2 },
        .{ .size = sz(20, 20), .padding = .all(.{ .px = 5 }), .box_sizing = .content_box },
        .{ .flex_direction = .column, .padding = .all(.{ .px = 3 }) },
    });
    const inner = try mk(&t, k[3], &.{ .{ .size = sz(30, 10) }, .{ .size = sz(20, 15) } });
    try run(&t, root);
    try expectRect(&t, k[0], 0, 0, 120, 50);
    try expectRect(&t, k[1], 120, 0, 60, 30);
    try expectRect(&t, k[2], 180, 0, 30, 30);
    try expectRect(&t, k[3], 210, 0, 36, 31);
    try expectRect(&t, inner[1], 3, 13, 20, 15);
    // percent height against an auto-height container behaves as auto
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .size = .{ px(300), .auto }, .flex_direction = .column });
    const k2 = try mk(&t2, r2, &.{.{ .size = .{ .auto, .{ .percent = 0.5 } } }});
    try run(&t2, r2);
    try expectRect(&t2, k2[0], 0, 0, 300, 0);
}

test "absolute positioning, static containing block, display none, relative offsets" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .size = sz(300, 200), .padding = .all(.{ .px = 10 }), .border = .all(5), .justify_content = .center, .align_items = .center });
    const k = try mk(&t, root, &.{
        .{ .position = .absolute, .inset = .{ .top = px(10), .left = px(20), .right = .auto, .bottom = .auto }, .size = sz(50, 40) },
        .{ .position = .absolute, .inset = .{ .top = .auto, .left = .auto, .right = px(20), .bottom = px(10) }, .size = sz(50, 40) },
        .{ .position = .absolute, .inset = .all(px(0)) },
        .{ .position = .absolute, .size = sz(30, 20) }, // static position: centered
        .{ .display = .none, .size = sz(100, 100) },
        .{ .size = sz(30, 30), .inset = .{ .top = px(5), .left = px(-5), .right = .auto, .bottom = .auto } },
        .{ .position = .static, .size = sz(40, 40) },
    });
    // a child of the static box resolves against the root's padding box
    const deep = try mk(&t, k[6], &.{.{ .position = .absolute, .inset = .{ .top = px(0), .right = px(0), .left = .auto, .bottom = .auto }, .size = sz(10, 10) }});
    try run(&t, root);
    try expectRect(&t, k[0], 25, 15, 50, 40);
    try expectRect(&t, k[1], 225, 145, 50, 40);
    try expectRect(&t, k[2], 5, 5, 290, 190);
    try expectRect(&t, k[3], 135, 90, 30, 20);
    try expectRect(&t, k[4], 0, 0, 0, 0);
    try expectRect(&t, k[5], 110, 90, 30, 30);
    try expectRect(&t, k[6], 145, 80, 40, 40);
    try expectRect(&t, deep[0], 285 - 145, 5 - 80, 10, 10);
}

test "block: stacking, margin collapsing, auto margins" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .display = .block, .size = .{ px(300), .auto } });
    const m = struct {
        fn tb(top: f32, bottom: f32) L.Edges(Dim) {
            return .{ .top = .{ .px = top }, .bottom = .{ .px = bottom }, .left = .{ .px = 0 }, .right = .{ .px = 0 } };
        }
    }.tb;
    const k = try mk(&t, root, &.{
        .{ .display = .block, .size = .{ .auto, px(50) }, .margin = m(0, 20) },
        .{ .display = .block, .margin = m(40, 25) }, // empty: collapses through
        .{ .display = .block, .size = .{ .auto, px(20) }, .margin = m(5, 0) },
        .{ .display = .block, .margin = m(10, 0) }, // parent / first child collapsing
        .{ .display = .block, .size = sz(100, 10), .margin = .{ .top = px(0), .bottom = px(0), .left = .auto, .right = .auto } },
    });
    const inner = try mk(&t, k[3], &.{.{ .display = .block, .size = .{ .auto, px(30) }, .margin = m(30, 7) }});
    try run(&t, root);
    try expectRect(&t, k[0], 0, 0, 300, 50);
    try expectRect(&t, k[2], 0, 90, 300, 20);
    try expectRect(&t, k[3], 0, 140, 300, 30);
    try expectRect(&t, inner[0], 0, 0, 300, 30);
    try expectRect(&t, k[4], 100, 177, 100, 10);
    try expectRect(&t, root, 0, 0, 300, 187);
}

test "grid: tracks, fr, spans, placement, auto-fill, alignment" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const cols = [_]L.Track{ L.Track.px(100), L.Track.fr(1), L.Track.fr(2) };
    const root = try t.addNode(.{ .display = .grid, .size = .{ px(400), .auto }, .grid_template_columns = &cols, .gap = .{ .{ .px = 10 }, .{ .px = 5 } } });
    const k = try mk(&t, root, &.{
        .{ .size = .{ .auto, px(20) } },
        .{ .size = .{ .auto, px(30) } },
        .{ .size = .{ .auto, px(10) }, .align_self = .end },
        .{ .size = .{ .auto, px(40) }, .grid_column = .{ .start = .{ .span = 2 } } },
        .{ .size = sz(20, 20), .grid_column = .{ .start = .{ .line = -2 } }, .justify_self = .center },
    });
    try run(&t, root);
    // free 400 - 100 - 20 = 280 -> 93.33 / 186.67
    try expectRect(&t, k[0], 0, 0, 100, 20);
    try expectRect(&t, k[1], 110, 0, 280.0 / 3.0, 30);
    try expectRect(&t, k[2], 110 + 280.0 / 3.0 + 10, 20, 560.0 / 3.0, 10);
    try expectRect(&t, k[3], 0, 35, 100 + 10 + 280.0 / 3.0, 40);
    try expectRect(&t, k[4], 110 + 280.0 / 3.0 + 10 + (560.0 / 3.0 - 20.0) / 2.0, 35, 20, 20);
    try expectRect(&t, root, 0, 0, 400, 75);

    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const rep = [_]L.Track{L.Track.minmax(.{ .px = 80 }, .{ .fr = 1 })};
    const r2 = try t2.addNode(.{ .display = .grid, .size = .{ px(300), .auto }, .grid_auto_repeat_columns = .{ .tracks = &rep }, .gap = .{ .{ .px = 5 }, .{ .px = 5 } }, .grid_auto_rows = &.{L.Track.px(20)} });
    const k2 = try mk(&t2, r2, &.{ .{}, .{}, .{}, .{}, .{} });
    try run(&t2, r2);
    // 3 columns of (300 - 10) / 3
    try expectRect(&t2, k2[2], 2 * (290.0 / 3.0 + 5), 0, 290.0 / 3.0, 20);
    try expectRect(&t2, k2[4], 290.0 / 3.0 + 5, 25, 290.0 / 3.0, 20);
}

/// Text-like measured content: 200px of "text", 10px line height, wraps at the available width.
const TextCtx = struct {
    calls: u32 = 0,
    fn measure(ctx: *anyopaque, _: L.NodeId, known: [2]?f32, available: [2]L.AvailableSpace) [2]f32 {
        const self: *TextCtx = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        const total: f32 = 200;
        const word: f32 = 40;
        const w: f32 = known[0] orelse switch (available[0]) {
            .definite => |v| @max(word, @min(total, v)),
            .min_content => word,
            .max_content => total,
        };
        const per_line = @max(@floor(w / word), 1);
        const lines = @ceil(total / word / per_line);
        return .{ if (known[0] != null) w else @min(w, per_line * word), known[1] orelse lines * 10 };
    }
    fn baseline(_: *anyopaque, _: L.NodeId, _: [2]f32) f32 {
        return 8;
    }
};

test "measured leaves: wrapping text, min-content shrink, cache keeps measure calls low" {
    var ctx: TextCtx = .{};
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .size = .{ px(300), .auto }, .flex_direction = .column, .padding = .all(.{ .px = 10 }) });
    const text1 = try t.addNode(.{});
    t.setMeasured(text1, true);
    try t.appendChild(root, text1);
    const row = try t.addNode(.{ .gap = .{ .{ .px = 10 }, .{ .px = 0 } } });
    try t.appendChild(root, row);
    const fixed = try t.addNode(.{ .size = sz(150, 10), .flex_shrink = 0 });
    try t.appendChild(row, fixed);
    const text2 = try t.addNode(.{});
    t.setMeasured(text2, true);
    try t.appendChild(row, text2);
    const text3 = try t.addNode(.{ .padding = .all(.{ .px = 5 }), .align_self = .center });
    t.setMeasured(text3, true);
    try t.appendChild(root, text3);

    try t.compute(root, vp400, &ctx, TextCtx.measure, .{ .baseline = TextCtx.baseline });
    // text1 stretches to 280 (content fits on one line)
    try expectRect(&t, text1, 10, 10, 280, 10);
    // text2 shrinks into the remaining 120px -> 3 words per line -> 2 lines
    try expectRect(&t, row, 10, 20, 280, 20);
    try expectRect(&t, text2, 160, 0, 120, 20);
    // text3 is content-sized and centered: 200 + padding
    try expectRect(&t, text3, 45, 40, 210, 20);
    try testing.expectEqual(@as(f32, 13), t.layout(text3).baseline);
    try testing.expect(ctx.calls <= 9);
    try testing.expectEqual(ctx.calls, t.measure_calls);

    // a second compute resets the caches and gives identical results
    const calls1 = ctx.calls;
    try t.compute(root, vp400, &ctx, TextCtx.measure, .{});
    try testing.expectEqual(calls1 * 2, ctx.calls);
    try expectRect(&t, text2, 160, 0, 120, 20);
}

test "baseline alignment uses the measured baseline" {
    var ctx: TextCtx = .{};
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .size = sz(400, 100), .align_items = .baseline });
    const a = try t.addNode(.{ .padding = .{ .top = .{ .px = 20 }, .right = .{ .px = 0 }, .bottom = .{ .px = 0 }, .left = .{ .px = 0 } } });
    t.setMeasured(a, true);
    const b = try t.addNode(.{});
    t.setMeasured(b, true);
    const c = try t.addNode(.{ .size = sz(10, 50) });
    for ([_]L.NodeId{ a, b, c }) |n| try t.appendChild(root, n);
    try t.compute(root, vp400, &ctx, TextCtx.measure, .{ .baseline = TextCtx.baseline });
    // baselines: a = 28, b = 8, c = 50 (bottom edge) -> shared baseline at 50
    try testing.expectEqual(@as(f32, 22), t.layout(a).y);
    try testing.expectEqual(@as(f32, 42), t.layout(b).y);
    try testing.expectEqual(@as(f32, 0), t.layout(c).y);
}

test "rounding: edges snap without gaps or overlaps" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .size = sz(100, 50.5), .padding = .all(.{ .px = 0.3 }) });
    const k = try mk(&t, root, &.{ .{ .flex_grow = 1 }, .{ .flex_grow = 1 }, .{ .flex_grow = 1 } });
    try t.compute(root, vp400, &dummy, noMeasure, .{ .round = true });
    var x: f32 = 0;
    for (k[0..3]) |id| {
        const l = t.layout(id);
        try testing.expectEqual(x, l.x);
        try testing.expectEqual(@round(l.w), l.w);
        x += l.w;
    }
    try testing.expectEqual(@as(f32, 100), x);
    try testing.expectEqual(@as(f32, 51), t.layout(root).h); // 50.5 rounds half away from zero

    try t.compute(root, vp400, &dummy, noMeasure, .{ .quantize64 = true });
    const w0 = t.layout(k[0]).w;
    try testing.expectEqual(@round(w0 * 64), w0 * 64);
    try testing.expect(@abs(w0 - 33.133) < 0.02);
}

test "errors: nesting deeper than max_depth, invalid ids" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{});
    var cur = root;
    for (0..L.max_depth + 10) |_| {
        const n = try t.addNode(.{ .padding = .all(.{ .px = 1 }) });
        try t.appendChild(cur, n);
        cur = n;
    }
    try testing.expectError(error.TooDeep, run(&t, root));
    try testing.expectError(error.InvalidNode, t.appendChild(root, 999_999));
    try testing.expectError(error.InvalidNode, t.appendChild(cur, root)); // cycle
    try testing.expectEqual(@as(f32, 0), t.layout(999_999).w);
    try testing.expectError(error.InvalidNode, t.appendChild(cur, root + 1)); // already has a parent
    try testing.expectError(error.InvalidNode, t.compute(999_999, vp400, &dummy, noMeasure, .{}));
}

test "untrusted values: NaN/inf/negative sizes do not produce NaN layouts" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const inf = std.math.inf(f32);
    const nan = std.math.nan(f32);
    const root = try t.addNode(.{ .size = .{ px(300), .auto }, .flex_wrap = .wrap, .gap = .{ .{ .px = -5 }, .{ .percent = nan } } });
    const k = try mk(&t, root, &.{
        .{ .size = .{ px(nan), px(-20) }, .flex_grow = nan, .flex_shrink = -1 },
        .{ .size = .{ px(1e30), px(10) }, .padding = .all(.{ .px = -4 }), .border = .all(-2), .aspect_ratio = 0 },
        .{ .size = .{ .{ .percent = inf }, px(10) }, .aspect_ratio = -3, .margin = .all(.{ .px = nan }) },
        .{ .display = .grid, .grid_template_columns = &.{ L.Track.fr(nan), L.Track.px(-10), L.Track.percent(inf) }, .grid_column = .{ .start = .{ .line = 32767 }, .end = .{ .span = 65535 } } },
    });
    _ = try mk(&t, k[3], &.{ .{ .grid_column = .{ .start = .{ .line = -32768 }, .end = .{ .line = 32767 } }, .grid_row = .{ .start = .{ .span = 65535 } } }, .{} });
    try run(&t, root);
    for (t.layouts.items) |l| {
        try testing.expect(!std.math.isNan(l.x) and !std.math.isNan(l.y));
        try testing.expect(!std.math.isNan(l.w) and !std.math.isNan(l.h));
    }
}

fn buildPerfTree(t: *Tree) !L.NodeId {
    const root = try t.addNode(.{ .size = sz(1200, 630), .flex_direction = .column, .padding = .all(.{ .px = 16 }), .gap = .{ .{ .px = 8 }, .{ .px = 8 } } });
    for (0..10) |_| {
        const section = try t.addNode(.{ .flex_direction = .column, .gap = .{ .{ .px = 4 }, .{ .px = 4 } }, .flex_grow = 1 });
        try t.appendChild(root, section);
        for (0..10) |_| {
            const row = try t.addNode(.{ .gap = .{ .{ .px = 6 }, .{ .px = 0 } }, .align_items = .center, .padding = .all(.{ .px = 2 }) });
            try t.appendChild(section, row);
            for (0..4) |ci| {
                const card = try t.addNode(.{ .flex_direction = .column, .flex_grow = if (ci == 0) 0 else 1, .padding = .all(.{ .px = 3 }), .border = .all(1), .min_size = .{ if (ci == 3) px(0) else .auto, .auto } });
                try t.appendChild(row, card);
                for (0..4) |li| {
                    const leaf = try t.addNode(if (li == 0) .{} else .{ .size = .{ if (li == 1) px(24) else .auto, px(6) }, .margin = .all(.{ .px = 1 }) });
                    if (li == 0) t.setMeasured(leaf, true);
                    try t.appendChild(card, leaf);
                }
            }
        }
    }
    return root;
}

test "perf: 2000-node nested flex tree" {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    var ctx: TextCtx = .{};
    var t = Tree.init(arena_state.allocator());
    const root = try buildPerfTree(&t);
    const n_nodes = t.nodes.items.len;
    const full: [2]L.AvailableSpace = .{ .{ .definite = 1200 }, .{ .definite = 630 } };
    try t.compute(root, full, &ctx, TextCtx.measure, .{});
    const calls = ctx.calls;
    const computes = t.node_computes;
    const iters: usize = 200;
    const io = std.testing.io;
    const t0 = std.Io.Timestamp.now(io, .awake);
    for (0..iters) |_| try t.compute(root, full, &ctx, TextCtx.measure, .{});
    const t1 = std.Io.Timestamp.now(io, .awake);
    const ns: f64 = @floatFromInt(t0.durationTo(t1).nanoseconds);
    const ms = ns / 1e6 / @as(f64, @floatFromInt(iters));
    const n_measured = n_nodes / 21 * 4;
    std.debug.print("perf: {d} nodes, {d:.3} ms per compute ({s}), {d} node computations, {d} measure calls for {d} measured leaves\n", .{
        n_nodes, ms, @tagName(@import("builtin").mode), computes, calls, n_measured,
    });
    try testing.expect(n_nodes >= 2000);
    // every text leaf: max-content, min-content, final width (the 400 leaves of fixed-width... cards add none)
    try testing.expect(calls <= n_measured * 4);
    if (@import("builtin").mode == .fast) try testing.expect(ms < 2.0);
}

var deepest_sp: usize = 0;
fn spMeasure(_: *anyopaque, _: L.NodeId, _: [2]?f32, _: [2]L.AvailableSpace) [2]f32 {
    const a = @frameAddress();
    if (deepest_sp == 0 or a < deepest_sp) deepest_sp = a;
    return .{ 10, 10 };
}

test "stack use per nesting level" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const depth = L.max_depth - 6;
    const root = try t.addNode(.{});
    var cur = root;
    for (0..depth) |i| {
        const n = try t.addNode(if (i % 3 == 0) .{ .flex_direction = .column, .padding = .all(.{ .px = 1 }) } else if (i % 3 == 1) .{ .display = .block } else .{ .display = .grid });
        try t.appendChild(cur, n);
        cur = n;
    }
    t.setMeasured(cur, true);
    deepest_sp = 0;
    const top = @frameAddress();
    try t.compute(root, vp400, &dummy, spMeasure, .{});
    const per_level = (top - deepest_sp) / depth;
    std.debug.print("stack: {d} bytes per nesting level ({s})\n", .{ per_level, @tagName(@import("builtin").mode) });
    if (@import("builtin").mode != .debug) try testing.expect(per_level < 4096);
}

pub fn compareExact(t: *const Tree, id: L.NodeId, ox: f32, oy: f32, exp: J, bad: *usize, verbose: bool) void {
    const l = t.layout(id);
    const o = exp.object;
    if (o.get("none") != null) return;
    const ex = num(o.get("x").?);
    const ey = num(o.get("y").?);
    const ew = num(o.get("w").?);
    const eh = num(o.get("h").?);
    const ax = ox + l.x;
    const ay = oy + l.y;
    const e: f32 = 0.001;
    if (@abs(ax - ex) > e or @abs(ay - ey) > e or @abs(l.w - ew) > e or @abs(l.h - eh) > e) {
        bad.* += 1;
        if (verbose) std.debug.print("    node {d}: got {d:.6},{d:.6} {d:.6}x{d:.6}  want {d:.6},{d:.6} {d:.6}x{d:.6}\n", .{ id, ax, ay, l.w, l.h, ex, ey, ew, eh });
    }
    const exp_kids = if (o.get("children")) |c| c.array.items else &[_]J{};
    var ch = t.firstChild(id);
    var i: usize = 0;
    while (ch != L.tree.no_node) : (ch = t.nextSibling(ch)) {
        if (i < exp_kids.len) compareExact(t, ch, ax, ay, exp_kids[i], bad, verbose);
        i += 1;
    }
}

// How many fixtures agree with takumi to the exact 1/64 px LayoutUnit in quantize64 mode.
const exact_verbose: usize = 5;
test "oracle fixtures, exact LayoutUnit agreement (quantize64)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const parsed = try std.json.parseFromSliceLeaky(J, a, @embedFile("testdata/oracle.json"), .{});
    const xfail = @embedFile("testdata/oracle_xfail.txt");
    var total: usize = 0;
    var exact: usize = 0;
    var shown: usize = 0;
    for (parsed.array.items) |case| {
        const o = case.object;
        const name = o.get("name").?.string;
        var is_xfail = false;
        var xit = std.mem.tokenizeAny(u8, xfail, "\r\n");
        while (xit.next()) |x| is_xfail = is_xfail or eq(x, name);
        if (is_xfail) continue;
        const vpa = o.get("vp").?.array.items;
        var t = Tree.init(a);
        const root = try buildNode(a, &t, o.get("node").?);
        try t.compute(root, .{ .{ .definite = num(vpa[0]) }, .{ .definite = num(vpa[1]) } }, &dummy, noMeasure, .{ .quantize64 = true });
        var bad: usize = 0;
        const rx = -t.layout(root).x;
        const ry = -t.layout(root).y;
        compareExact(&t, root, rx, ry, o.get("expect").?, &bad, false);
        total += 1;
        if (bad == 0) {
            exact += 1;
        } else if (shown < exact_verbose) {
            shown += 1;
            std.debug.print("INEXACT {s}\n", .{name});
            compareExact(&t, root, rx, ry, o.get("expect").?, &bad, true);
        }
    }
    std.debug.print("exact LayoutUnit agreement: {d}/{d} fixtures\n", .{ exact, total });
}

test "calc() lengths and intrinsic sizing keywords" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    const root = try t.addNode(.{ .display = .block, .size = sz(300, 200), .padding = .all(.{ .calc = .{ .px = 5, .percent = 0.05 } }) });
    // padding = 5 + 5% of the 400px viewport = 25 -> content box 250 x 150
    const k = try mk(&t, root, &.{
        .{ .display = .block, .size = .{ .{ .calc = .{ .px = -20, .percent = 1 } }, .{ .calc = .{ .px = 10, .percent = 0.25 } } } },
        .{ .size = .{ .max_content, .auto } },
        .{ .size = .{ .min_content, .auto }, .flex_wrap = .wrap },
        .{ .size = .{ .fit_content, .auto }, .flex_wrap = .wrap },
    });
    _ = try mk(&t, k[1], &.{ .{ .size = sz(200, 10), .flex_shrink = 0 }, .{ .size = sz(200, 10), .flex_shrink = 0 } });
    _ = try mk(&t, k[2], &.{ .{ .size = sz(70, 10) }, .{ .size = sz(50, 10) } });
    _ = try mk(&t, k[3], &.{ .{ .size = sz(200, 10) }, .{ .size = sz(200, 10) } });
    try run(&t, root);
    try expectRect(&t, k[0], 25, 25, 230, 47.5);
    try expectRect(&t, k[1], 25, 72.5, 400, 10); // max-content overflows instead of filling
    try expectRect(&t, k[2], 25, 82.5, 70, 20); // min-content: one item per line
    try expectRect(&t, k[3], 25, 102.5, 250, 20); // fit-content: clamped to the available width

    // as flex items: no cross-axis stretch, max-content basis
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .size = sz(300, 100), .flex_direction = .column });
    const k2 = try mk(&t2, r2, &.{ .{ .size = .{ .max_content, .auto } }, .{} });
    _ = try mk(&t2, k2[0], &.{.{ .size = sz(80, 10) }});
    try run(&t2, r2);
    try expectRect(&t2, k2[0], 0, 0, 80, 10);
    try expectRect(&t2, k2[1], 0, 10, 300, 0);
}

test "quantize64: Blink layout-unit arithmetic" {
    var t = Tree.init(testing.allocator);
    defer t.deinit();
    // 908 px split 1fr : 2fr -> 302.65625 / 605.34375 (remainder handed to the next track)
    const cols = [_]L.Track{ L.Track.fr(1), L.Track.fr(2) };
    const root = try t.addNode(.{ .display = .grid, .size = sz(908, 50), .grid_template_columns = &cols });
    const k = try mk(&t, root, &.{ .{}, .{} });
    try t.compute(root, vp400, &dummy, noMeasure, .{ .quantize64 = true });
    try testing.expectEqual(@as(f32, 302.65625), t.layout(k[0]).w);
    try testing.expectEqual(@as(f32, 605.34375), t.layout(k[1]).w);

    // centring halves in whole layout units: (300 - 100.4 -> 100.390625) / 2 truncates
    var t2 = Tree.init(testing.allocator);
    defer t2.deinit();
    const r2 = try t2.addNode(.{ .size = sz(300, 100), .justify_content = .center, .align_items = .center });
    const k2 = try mk(&t2, r2, &.{.{ .size = sz(100.4, 33.3) }});
    try t2.compute(r2, vp400, &dummy, noMeasure, .{ .quantize64 = true });
    try testing.expectEqual(@as(f32, 100.390625), t2.layout(k2[0]).w);
    try testing.expectEqual(@as(f32, 99.796875), t2.layout(k2[0]).x);
    try testing.expectEqual(@as(f32, 33.34375), t2.layout(k2[0]).y);

    // flex-grow: the last item takes its rounded share first, the first one gets what is left
    var t3 = Tree.init(testing.allocator);
    defer t3.deinit();
    const r3 = try t3.addNode(.{ .size = sz(100, 50) });
    const k3 = try mk(&t3, r3, &.{ .{ .flex_grow = 1 }, .{ .flex_grow = 1 }, .{ .flex_grow = 1 } });
    try t3.compute(r3, vp400, &dummy, noMeasure, .{ .quantize64 = true });
    try testing.expectEqual(@as(f32, 33.328125), t3.layout(k3[0]).w);
    try testing.expectEqual(@as(f32, 33.34375), t3.layout(k3[1]).w);
    try testing.expectEqual(@as(f32, 33.328125), t3.layout(k3[2]).w);
}
