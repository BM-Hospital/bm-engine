//! Minimal CSS for SVG: `<style>` sheets with type / class / id / universal / `[attr]` /
//! `[attr=value]` compound selectors, descendant and child combinators, comma lists,
//! `!important`; `style=""` attributes; presentation attributes. Unsupported selectors
//! (pseudo-classes, sibling combinators) drop their rule and set `unsupported.css_selector`.
const std = @import("std");
const dom = @import("dom.zig");
const num = @import("num.zig");
const Allocator = std.mem.Allocator;
const Prop = dom.Prop;
const Decl = dom.Decl;
const Node = dom.Node;

const MAX_RULES = 4096;
const MAX_PARTS = 8;

const Compound = struct {
    tag: ?[]const u8 = null,
    id: ?[]const u8 = null,
    classes: [4][]const u8 = undefined,
    n_classes: u8 = 0,
    attr_name: ?[]const u8 = null,
    attr_value: ?[]const u8 = null,
    /// relation to the compound on the left
    child: bool = false,
};

const Rule = struct {
    parts: []const Compound,
    spec: u32,
    order: u32,
    normal: []const Decl,
    important: []const Decl,
};

/// Parses `name: value; ...` into normal and important declarations.
pub fn parseDecls(arena: Allocator, text: []const u8, normal: *std.ArrayList(Decl), important: *std.ArrayList(Decl)) !void {
    var i: usize = 0;
    while (i < text.len) {
        // find end of declaration (';' outside parentheses / quotes)
        var j = i;
        var depth: u32 = 0;
        var quote: u8 = 0;
        while (j < text.len) : (j += 1) {
            const c = text[j];
            if (quote != 0) {
                if (c == quote) quote = 0;
            } else if (c == '"' or c == '\'') {
                quote = c;
            } else if (c == '(') {
                depth += 1;
            } else if (c == ')') {
                depth -|= 1;
            } else if (c == ';' and depth == 0) break;
        }
        const d = text[i..j];
        i = j + 1;
        const colon = std.mem.indexOfScalar(u8, d, ':') orelse continue;
        const name = num.trim(d[0..colon]);
        var value = num.trim(d[colon + 1 ..]);
        var imp = false;
        if (std.mem.lastIndexOfScalar(u8, value, '!')) |bang| {
            if (num.eqlIgnoreCase(num.trim(value[bang + 1 ..]), "important")) {
                imp = true;
                value = num.trim(value[0..bang]);
            }
        }
        const prop = Prop.fromName(name) orelse continue;
        const list = if (imp) important else normal;
        if (prop == .marker) {
            for ([_]Prop{ .marker_start, .marker_mid, .marker_end }) |p| try list.append(arena, .{ .prop = p, .value = value });
        } else try list.append(arena, .{ .prop = prop, .value = value });
    }
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c >= 0x80;
}

/// Parses one complex selector; null when unsupported.
fn parseSelector(arena: Allocator, s_in: []const u8) !?struct { parts: []Compound, spec: u32 } {
    const s = num.trim(s_in);
    if (s.len == 0) return null;
    var parts: std.ArrayList(Compound) = .empty;
    var spec: u32 = 0;
    var i: usize = 0;
    var cur: Compound = .{};
    var have = false;
    var pending_child = false;
    while (i < s.len) {
        const c = s[i];
        if (num.isWs(c) or c == '>') {
            if (have) {
                if (parts.items.len >= MAX_PARTS) return null;
                try parts.append(arena, cur);
                cur = .{};
                have = false;
            }
            if (c == '>') pending_child = true;
            i += 1;
            continue;
        }
        if (!have) {
            cur.child = pending_child;
            pending_child = false;
        }
        if (c == '*') {
            have = true;
            i += 1;
        } else if (c == '.' or c == '#') {
            i += 1;
            const st = i;
            while (i < s.len and isIdentChar(s[i])) i += 1;
            if (i == st) return null;
            if (c == '#') {
                cur.id = s[st..i];
                spec += 1 << 16;
            } else {
                if (cur.n_classes >= 4) return null;
                cur.classes[cur.n_classes] = s[st..i];
                cur.n_classes += 1;
                spec += 1 << 8;
            }
            have = true;
        } else if (c == '[') {
            const e = std.mem.indexOfScalarPos(u8, s, i, ']') orelse return null;
            const inner = s[i + 1 .. e];
            if (std.mem.indexOfScalar(u8, inner, '=')) |eq| {
                if (eq == 0 or !isIdentChar(inner[eq - 1])) return null; // ~= |= ^= etc.
                cur.attr_name = num.trim(inner[0..eq]);
                cur.attr_value = std.mem.trim(u8, num.trim(inner[eq + 1 ..]), "\"'");
            } else cur.attr_name = num.trim(inner);
            spec += 1 << 8;
            have = true;
            i = e + 1;
        } else if (isIdentChar(c)) {
            const st = i;
            while (i < s.len and isIdentChar(s[i])) i += 1;
            cur.tag = s[st..i];
            spec += 1;
            have = true;
        } else return null; // ':' '+' '~' '|' ...
    }
    if (!have) return null;
    if (parts.items.len >= MAX_PARTS) return null;
    try parts.append(arena, cur);
    return .{ .parts = parts.items, .spec = spec };
}

fn hasClass(n: *const Node, cls: []const u8) bool {
    const list = n.attr("class") orelse return false;
    var it = std.mem.tokenizeAny(u8, list, " \t\r\n");
    while (it.next()) |t| if (std.mem.eql(u8, t, cls)) return true;
    return false;
}

fn matchCompound(c: *const Compound, n: *const Node) bool {
    if (c.tag) |t| {
        if (n.tag == .unknown or !std.mem.eql(u8, t, dom.tag_names[@intFromEnum(n.tag)])) return false;
    }
    if (c.id) |id| {
        if (!std.mem.eql(u8, n.attr("id") orelse return false, id)) return false;
    }
    for (c.classes[0..c.n_classes]) |cls| if (!hasClass(n, cls)) return false;
    if (c.attr_name) |an| {
        const v = n.attr(an) orelse return false;
        if (c.attr_value) |want| if (!std.mem.eql(u8, v, want)) return false;
    }
    return true;
}

/// Right-to-left match; descendant combinators bind to the nearest matching ancestor.
fn matches(nodes: []const Node, parts: []const Compound, idx: u32) bool {
    var k = parts.len;
    var n = idx;
    k -= 1;
    if (!matchCompound(&parts[k], &nodes[n])) return false;
    while (k > 0) {
        const child = parts[k].child;
        k -= 1;
        var p = nodes[n].parent;
        if (child) {
            if (p == dom.NONE or !matchCompound(&parts[k], &nodes[p])) return false;
            n = p;
        } else {
            while (p != dom.NONE and !matchCompound(&parts[k], &nodes[p])) p = nodes[p].parent;
            if (p == dom.NONE) return false;
            n = p;
        }
    }
    return true;
}

fn parseSheet(arena: Allocator, css_in: []const u8, rules: *std.ArrayList(Rule), unsupported: *dom.Unsupported) !void {
    // strip comments
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < css_in.len) {
        if (std.mem.startsWith(u8, css_in[i..], "/*")) {
            i = if (std.mem.indexOfPos(u8, css_in, i + 2, "*/")) |e| e + 2 else css_in.len;
            try buf.append(arena, ' ');
        } else if (std.mem.startsWith(u8, css_in[i..], "<!--")) {
            i += 4;
        } else if (std.mem.startsWith(u8, css_in[i..], "-->")) {
            i += 3;
        } else {
            try buf.append(arena, css_in[i]);
            i += 1;
        }
    }
    const css = buf.items;
    i = 0;
    while (i < css.len) {
        while (i < css.len and num.isWs(css[i])) i += 1;
        if (i >= css.len) break;
        if (css[i] == '@') {
            // skip at-rule: up to ';' or a balanced block
            var j = i;
            while (j < css.len and css[j] != ';' and css[j] != '{') j += 1;
            if (j < css.len and css[j] == '{') {
                var depth: u32 = 0;
                while (j < css.len) : (j += 1) {
                    if (css[j] == '{') depth += 1;
                    if (css[j] == '}') {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
            }
            i = j + 1;
            continue;
        }
        const ob = std.mem.indexOfScalarPos(u8, css, i, '{') orelse break;
        const cb = std.mem.indexOfScalarPos(u8, css, ob, '}') orelse css.len;
        const sel_text = css[i..ob];
        const body = css[ob + 1 .. cb];
        i = cb + 1;
        var normal: std.ArrayList(Decl) = .empty;
        var important: std.ArrayList(Decl) = .empty;
        try parseDecls(arena, body, &normal, &important);
        if (normal.items.len + important.items.len == 0) continue;
        var it = std.mem.splitScalar(u8, sel_text, ',');
        while (it.next()) |one| {
            if (rules.items.len >= MAX_RULES) return;
            const sel = try parseSelector(arena, one) orelse {
                unsupported.css_selector = true;
                continue;
            };
            try rules.append(arena, .{
                .parts = sel.parts,
                .spec = sel.spec,
                .order = @intCast(rules.items.len),
                .normal = normal.items,
                .important = important.items,
            });
        }
    }
}

fn ruleLess(_: void, a: Rule, b: Rule) bool {
    if (a.spec != b.spec) return a.spec < b.spec;
    return a.order < b.order;
}

/// Fills `Node.decls` for every node.
pub fn cascade(comptime stylesheets: bool, arena: Allocator, nodes: []Node, unsupported: *dom.Unsupported) !void {
    var rules: std.ArrayList(Rule) = .empty;
    if (stylesheets) for (nodes) |*n| {
        if (n.tag != .style or n.text.len == 0) continue;
        if (n.attr("type")) |t| if (!std.mem.eql(u8, num.trim(t), "text/css") and num.trim(t).len > 0) continue;
        try parseSheet(arena, n.text, &rules, unsupported);
    };
    std.sort.insertion(Rule, rules.items, {}, ruleLess);

    var vals: [Prop.COUNT]?[]const u8 = undefined;
    var normal: std.ArrayList(Decl) = .empty;
    var important: std.ArrayList(Decl) = .empty;
    for (nodes, 0..) |*n, ni| {
        if (n.tag == .unknown) continue;
        @memset(&vals, null);
        var any = false;
        for (n.attrs) |a| {
            if (std.mem.eql(u8, a.name, "style") or std.mem.eql(u8, a.name, "class") or std.mem.eql(u8, a.name, "id")) continue;
            const p = Prop.fromName(a.name) orelse continue;
            if (p == .marker) continue;
            vals[@intFromEnum(p)] = num.trim(a.value);
            any = true;
        }
        var n_matched: usize = 0;
        for (rules.items) |*r| {
            if (!matches(nodes, r.parts, @intCast(ni))) continue;
            n_matched += 1;
            for (r.normal) |d| vals[@intFromEnum(d.prop)] = d.value;
            any = true;
        }
        normal.clearRetainingCapacity();
        important.clearRetainingCapacity();
        if (n.attr("style")) |st| try parseDecls(arena, st, &normal, &important);
        for (normal.items) |d| vals[@intFromEnum(d.prop)] = d.value;
        if (n_matched > 0) {
            for (rules.items) |*r| {
                if (r.important.len == 0 or !matches(nodes, r.parts, @intCast(ni))) continue;
                for (r.important) |d| vals[@intFromEnum(d.prop)] = d.value;
            }
        }
        for (important.items) |d| vals[@intFromEnum(d.prop)] = d.value;
        if (!any and normal.items.len + important.items.len == 0) continue;
        var cnt: usize = 0;
        for (vals) |v| cnt += @intFromBool(v != null);
        const out = try arena.alloc(Decl, cnt);
        cnt = 0;
        for (vals, 0..) |v, pi| if (v) |val| {
            out[cnt] = .{ .prop = @enumFromInt(pi), .value = val };
            cnt += 1;
        };
        n.decls = out;
    }
}

test "css cascade" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const xml = @import("xml.zig");
    const r = try xml.parse(a,
        \\<svg><style>/* c */ rect { fill: blue } .a { fill: green !important; stroke: red }
        \\ #x { stroke: lime } g > rect.b, svg rect[data-k="v"] { opacity: .5 } @media print { rect { fill: pink } }
        \\ rect:hover { fill: black }</style>
        \\<g><rect id="x" class="a b" fill="yellow" style="fill: purple; stroke: navy"/></g><rect data-k="v" fill="yellow"/></svg>
    );
    var un: dom.Unsupported = .{};
    try cascade(true, a, r.nodes, &un);
    const rect = &r.nodes[3];
    try std.testing.expectEqualStrings("green", rect.decl(.fill).?);
    try std.testing.expectEqualStrings("navy", rect.decl(.stroke).?);
    try std.testing.expectEqualStrings(".5", rect.decl(.opacity).?);
    const r2 = &r.nodes[4];
    try std.testing.expectEqualStrings("blue", r2.decl(.fill).?);
    try std.testing.expectEqualStrings(".5", r2.decl(.opacity).?);
    try std.testing.expect(un.css_selector);
}
