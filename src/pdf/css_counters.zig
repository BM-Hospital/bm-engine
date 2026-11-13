//! CSS counters in generated content for the frames a PDF is drawn from (takumi-core
//! `layout/counters.rs`, Blink's `CountersAttachmentContext`): `counter-reset` / `counter-increment` /
//! `counter-set` and the implicit `list-item` counter of `ol` / `ul` / `li`, applied in document order
//! as the tree is styled (an element, then its `::before`, its children, its `::after`), and read by
//! `counter()` / `counters()` in `content` (dom.zig `contentText`). `counter(page)` and `counter(pages)`
//! name no counter here, as in takumi-pdf: they read 0 unless an element creates a counter of that
//! name. Counter styles: those of the page counters (counters.zig `CounterStyle`), `decimal` otherwise.
const std = @import("std");
const dom_mod = @import("../dom.zig");
const counters = @import("counters.zig");

const Allocator = std.mem.Allocator;

const increment_type: u8 = 1 << 0;
const reset_type: u8 = 1 << 1;
const set_type: u8 = 1 << 2;

const Entry = struct { object: u32, parent: ?u32, value: i32 };
/// a name's counters from the outermost in
const Stack = std.ArrayList(Entry);

/// What the implicit `list-item` counter does on entering an element (takumi `ListItemCounter`).
pub const ListItem = union(enum) {
    none,
    item: struct { explicit: ?i32, reversed: bool },
    ordered: struct { initial: i32, reversed: bool },
    other_list,
};

const Directives = struct {
    name: []const u8,
    reset: ?i64 = null,
    increment: ?i32 = null,
    set: ?i32 = null,

    fn typeAndValue(d: Directives) ?struct { u8, i32 } {
        var t: u8 = 0;
        if (d.increment != null) t |= increment_type;
        if (d.reset != null) t |= reset_type;
        if (d.set != null) t |= set_type;
        if (t == 0) return null;
        const v: i32 = if (d.set) |s| s else saturate((d.reset orelse 0) + @as(i64, d.increment orelse 0));
        return .{ t, v };
    }
};

fn saturate(v: i64) i32 {
    return @intCast(std.math.clamp(v, std.math.minInt(i32), std.math.maxInt(i32)));
}

pub const Context = struct {
    a: Allocator,
    table: std.StringHashMapUnmanaged(Stack) = .empty,
    path: std.ArrayList(u32) = .empty,
    next: u32 = 0,

    /// Enters the box of an element or a `::before` / `::after` (counter properties `reset`,
    /// `increment`, `set`: the raw `name [int]` lists of the computed style).
    pub fn enter(cx: *Context, reset: []const u8, increment: []const u8, set: []const u8, list_item: ListItem) Allocator.Error!void {
        try cx.path.append(cx.a, cx.next);
        cx.next += 1;
        var buf: [16]Directives = undefined;
        const dirs = parseDirectives(&buf, reset, increment, set);
        var has_list_item = false;
        for (dirs) |d| {
            if (std.mem.eql(u8, d.name, "list-item")) has_list_item = true;
            const tv = d.typeAndValue() orelse continue;
            try cx.process(d.name, tv[0], tv[1]);
        }
        if (list_item != .none and !has_list_item) try cx.listItem(list_item);
    }

    /// Leaves the box `enter` entered last, after its descendants.
    pub fn leave(cx: *Context, reset: []const u8, increment: []const u8, set: []const u8, list_item: ListItem) void {
        var buf: [16]Directives = undefined;
        const dirs = parseDirectives(&buf, reset, increment, set);
        var has_list_item = false;
        for (dirs) |d| {
            if (std.mem.eql(u8, d.name, "list-item")) has_list_item = true;
            const tv = d.typeAndValue() orelse continue;
            if (tv[0] & reset_type == 0) continue;
            cx.removeIfAncestorExists(d.name);
        }
        if (list_item != .none and !has_list_item) cx.removeIfAncestorExists("list-item");
        _ = cx.path.pop();
    }

    /// `counter()` (`all` false: the innermost) or `counters()` values of `name`, outermost first.
    fn values(cx: *Context, name: []const u8, all: bool, out: *[64]i32) []const i32 {
        cx.removeStale(name);
        const st = cx.table.getPtr(name) orelse {
            out[0] = 0;
            return out[0..1];
        };
        if (st.items.len == 0) {
            out[0] = 0;
            return out[0..1];
        }
        if (!all) {
            out[0] = st.items[st.items.len - 1].value;
            return out[0..1];
        }
        const from = st.items.len -| out.len;
        for (st.items[from..], 0..) |e, i| out[i] = e.value;
        return out[0 .. st.items.len - from];
    }

    fn listItem(cx: *Context, li: ListItem) Allocator.Error!void {
        cx.removeStale("list-item");
        switch (li) {
            .none => {},
            .item => |it| if (it.explicit) |v| try cx.create("list-item", v) else try cx.update("list-item", increment_type, if (it.reversed) -1 else 1),
            .ordered => |o| try cx.create("list-item", o.initial +| @as(i32, if (o.reversed) 1 else -1)),
            .other_list => try cx.create("list-item", 0),
        }
    }

    fn process(cx: *Context, name: []const u8, t: u8, v: i32) Allocator.Error!void {
        cx.removeStale(name);
        if (t & reset_type != 0) return cx.create(name, v);
        return cx.update(name, t, v);
    }

    fn current(cx: *const Context) u32 {
        return if (cx.path.items.len > 0) cx.path.items[cx.path.items.len - 1] else 0;
    }

    fn currentParent(cx: *const Context) ?u32 {
        return if (cx.path.items.len >= 2) cx.path.items[cx.path.items.len - 2] else null;
    }

    /// `object` is a strict ancestor of the box entered last.
    fn isAncestor(cx: *const Context, object: u32) bool {
        if (cx.path.items.len == 0) return false;
        for (cx.path.items[0 .. cx.path.items.len - 1]) |p| if (p == object) return true;
        return false;
    }

    fn create(cx: *Context, name: []const u8, value: i32) Allocator.Error!void {
        const e: Entry = .{ .object = cx.current(), .parent = cx.currentParent(), .value = value };
        const gop = try cx.table.getOrPut(cx.a, name);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        const st = gop.value_ptr;
        if (st.items.len > 0 and st.items[st.items.len - 1].parent == e.parent) _ = st.pop();
        try st.append(cx.a, e);
    }

    fn update(cx: *Context, name: []const u8, t: u8, v: i32) Allocator.Error!void {
        if (cx.table.getPtr(name)) |st| if (st.items.len > 0) {
            const last = &st.items[st.items.len - 1];
            last.value = if (t & (reset_type | set_type) != 0) v else std.math.add(i32, last.value, v) catch last.value;
            return;
        };
        try cx.create(name, if (t & (reset_type | set_type) != 0) v else v);
    }

    /// Drops the counters whose box's parent is no ancestor of the box entered last.
    fn removeStale(cx: *Context, name: []const u8) void {
        const st = cx.table.getPtr(name) orelse return;
        while (st.items.len > 0) {
            const e = st.items[st.items.len - 1];
            const p = e.parent orelse break;
            if (cx.isAncestor(p)) break;
            _ = st.pop();
        }
    }

    fn removeIfAncestorExists(cx: *Context, name: []const u8) void {
        const st = cx.table.getPtr(name) orelse return;
        if (st.items.len < 2) return;
        const last = st.items[st.items.len - 1];
        const prev = st.items[st.items.len - 2];
        if (last.object != cx.current()) return;
        const removes = cx.isAncestor(prev.object) or (if (prev.parent) |p| cx.isAncestor(p) and p != (cx.currentParent() orelse std.math.maxInt(u32)) else false);
        if (removes) _ = st.pop();
    }

    // ---- dom.zig `contentText` hook

    pub fn hook(cx: *Context) dom_mod.ContentCounters {
        return .{ .ctx = cx, .write = write };
    }

    /// Writes `counter(<args>)` (`all` false) or `counters(<args>)`: `name`, for `counters` a quoted
    /// separator, then an optional counter style.
    fn write(ctx: *anyopaque, a: Allocator, out: *std.ArrayList(u8), args: []const u8, all: bool) Allocator.Error!void {
        const cx: *Context = @ptrCast(@alignCast(ctx));
        var parts: [3][]const u8 = .{ "", "", "" };
        var np: usize = 0;
        var start: usize = 0;
        var quote: u8 = 0;
        var i: usize = 0;
        while (i <= args.len) : (i += 1) {
            const c: u8 = if (i < args.len) args[i] else ',';
            if (quote != 0) {
                if (c == '\\') i += 1 else if (c == quote) quote = 0;
                continue;
            }
            if (c == '"' or c == '\'') {
                quote = c;
                continue;
            }
            if (c == ',') {
                if (np < parts.len) parts[np] = std.mem.trim(u8, args[start..@min(i, args.len)], " \t\r\n");
                np += 1;
                start = i + 1;
            }
        }
        const name = parts[0];
        if (name.len == 0) return;
        var sep: []const u8 = "";
        var style_name: []const u8 = "decimal";
        if (all) {
            sep = unquote(parts[1]);
            if (np > 2 and parts[2].len > 0) style_name = parts[2];
        } else if (np > 1 and parts[1].len > 0) style_name = parts[1];
        if (std.mem.eql(u8, style_name, "none")) return;
        const cs = counters.CounterStyle.fromName(style_name) orelse .decimal;
        var buf: [64]i32 = undefined;
        const vals = cx.values(name, all, &buf);
        for (vals, 0..) |v, k| {
            if (k > 0) try out.appendSlice(a, sep);
            if (v <= 0 and cs != .decimal) {
                var nb: [16]u8 = undefined;
                try out.appendSlice(a, std.fmt.bufPrint(&nb, "{d}", .{v}) catch "0");
            } else if (v < 0) {
                var nb: [16]u8 = undefined;
                try out.appendSlice(a, std.fmt.bufPrint(&nb, "{d}", .{v}) catch "0");
            } else try out.appendSlice(a, try cs.format(a, @intCast(v)));
        }
    }
};

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2 and (s[0] == '"' or s[0] == '\'') and s[s.len - 1] == s[0]) return s[1 .. s.len - 1];
    return s;
}

/// The directives of `counter-reset`, `counter-increment`, `counter-set` (`name [int]` lists; a reset or
/// set defaults to 0, an increment to 1; increments of one name add up, a later reset / set wins).
fn parseDirectives(buf: *[16]Directives, reset: []const u8, increment: []const u8, set: []const u8) []Directives {
    var n: usize = 0;
    const lists = [3][]const u8{ reset, increment, set };
    for (lists, 0..) |list, which| {
        var it = std.mem.tokenizeAny(u8, list, " \t\r\n");
        var name: ?[]const u8 = null;
        while (true) {
            const tok = it.next();
            const num: ?i64 = if (tok) |t| (std.fmt.parseInt(i64, t, 10) catch null) else null;
            if (name) |nm| {
                if (find(buf, &n, nm)) |k| {
                    const v = num orelse (if (which == 1) @as(i64, 1) else 0);
                    switch (which) {
                        0 => buf[k].reset = v,
                        1 => buf[k].increment = saturate(@as(i64, buf[k].increment orelse 0) + v),
                        else => buf[k].set = saturate(v),
                    }
                }
                name = null;
                if (num != null) continue;
            }
            const t = tok orelse break;
            if (num == null and !std.mem.eql(u8, t, "none")) name = t;
        }
    }
    return buf[0..n];
}

fn find(buf: *[16]Directives, n: *usize, name: []const u8) ?usize {
    for (buf[0..n.*], 0..) |d, i| if (std.mem.eql(u8, d.name, name)) return i;
    if (n.* == buf.len) return null;
    buf[n.*] = .{ .name = name };
    n.* += 1;
    return n.* - 1;
}

/// The implicit `list-item` counter of element `el` with display `list_item_display` (takumi
/// `ListItemCounter::of`): a list item (`li`'s `value`, the list `reversed` or not), an `ol` (`start`,
/// else 1; reversed: the number of its items), a `ul` / `menu` / `dir`.
pub fn listItemOf(d: *const dom_mod.Dom, el: u32, is_list_item: bool) ListItem {
    const e = d.at(el);
    const tag = e.tag;
    const is = struct {
        fn f(t: []const u8, n: []const u8) bool {
            return std.ascii.eqlIgnoreCase(t, n);
        }
    }.f;
    if (!(is(tag, "ol") or is(tag, "ul") or is(tag, "li") or is(tag, "menu") or is(tag, "dir"))) return .none;
    if (is_list_item) {
        const explicit: ?i32 = if (d.attr(el, "value")) |v| std.fmt.parseInt(i32, std.mem.trim(u8, v, " \t\r\n"), 10) catch null else null;
        var reversed = false;
        if (e.parent != dom_mod.none) {
            const p = d.at(e.parent);
            if (is(p.tag, "ol") and d.attr(e.parent, "reversed") != null) reversed = true;
        }
        return .{ .item = .{ .explicit = explicit, .reversed = reversed } };
    }
    if (is(tag, "ol")) {
        const reversed = d.attr(el, "reversed") != null;
        var initial: i32 = 1;
        if (d.attr(el, "start")) |s| {
            initial = std.fmt.parseInt(i32, std.mem.trim(u8, s, " \t\r\n"), 10) catch 1;
        } else if (reversed) {
            var count: i32 = 0;
            var k = e.first;
            while (k != dom_mod.none) : (k = d.at(k).next) if (is(d.at(k).tag, "li")) {
                count += 1;
            };
            initial = count;
        }
        return .{ .ordered = .{ .initial = initial, .reversed = reversed } };
    }
    return if (is(tag, "li")) .none else .other_list;
}

test "counters: reset / increment / set, nesting, counters()" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var cx: Context = .{ .a = a };
    var buf: [64]i32 = undefined;
    // body { counter-reset: sec } .h { counter-increment: sec }
    try cx.enter("sec", "", "", .none);
    for (0..3) |k| {
        try cx.enter("", "sec", "", .none);
        try std.testing.expectEqual(@as(i32, @intCast(k + 1)), cx.values("sec", false, &buf)[0]);
        cx.leave("", "sec", "", .none);
    }
    // counter-set wins over the increment
    try cx.enter("", "sec", "sec 10", .none);
    try std.testing.expectEqual(@as(i32, 10), cx.values("sec", false, &buf)[0]);
    cx.leave("", "sec", "sec 10", .none);
    cx.leave("sec", "", "", .none);
    // counters() nested: .o { counter-reset: n } .i { counter-increment: n } (takumi: 1, 1.1, 1.2, 2)
    try cx.enter("n", "", "", .none);
    try cx.enter("", "n", "", .none);
    try std.testing.expectEqualSlices(i32, &.{1}, cx.values("n", true, &buf));
    cx.leave("", "n", "", .none);
    try cx.enter("n", "", "", .none);
    try cx.enter("", "n", "", .none);
    try std.testing.expectEqualSlices(i32, &.{ 1, 1 }, cx.values("n", true, &buf));
    cx.leave("", "n", "", .none);
    try cx.enter("", "n", "", .none);
    try std.testing.expectEqualSlices(i32, &.{ 1, 2 }, cx.values("n", true, &buf));
    cx.leave("", "n", "", .none);
    cx.leave("n", "", "", .none);
    try cx.enter("", "n", "", .none);
    try std.testing.expectEqualSlices(i32, &.{2}, cx.values("n", true, &buf));
    // an unknown counter reads 0
    try std.testing.expectEqualSlices(i32, &.{0}, cx.values("page", false, &buf));
}
