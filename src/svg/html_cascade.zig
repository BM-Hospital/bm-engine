//! Reach inline SVG descendants with the page's selector engine, keeping image SVGs isolated.
//! Match the SVG subtree with page rules; serialize resolved declarations into the image source.
const std = @import("std");
const rt = @import("../render.zig");
const html_dom = @import("../dom.zig");
const css = @import("../css/css.zig");
const svg_dom = @import("dom.zig");
const svg_css = @import("css.zig");
const xml = @import("xml.zig");

fn escape(a: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8, attribute: bool) !void {
    for (text) |c| switch (c) {
        '&' => try out.appendSlice(a, "&amp;"),
        '<' => try out.appendSlice(a, "&lt;"),
        '"' => if (attribute) try out.appendSlice(a, "&quot;") else try out.append(a, c),
        else => try out.append(a, c),
    };
}

const Writer = struct {
    a: std.mem.Allocator,
    nodes: []const svg_dom.Node,
    styles: []const []const u8,
    out: std.ArrayList(u8) = .empty,
    fn node(w: *Writer, index: u32) error{OutOfMemory}!void {
        const n = &w.nodes[index];
        if (n.tag == .style) return;
        if (n.tag == .textnode) return escape(w.a, &w.out, n.text, false);
        if (n.tag == .unknown) return;
        const tag = svg_dom.tag_names[@backingInt(n.tag)];
        try w.out.append(w.a, '<');
        try w.out.appendSlice(w.a, tag);
        for (n.attrs) |attr| {
            if (std.mem.eql(u8, attr.name, "style")) continue;
            try w.out.append(w.a, ' ');
            try w.out.appendSlice(w.a, attr.name);
            try w.out.appendSlice(w.a, "=\"");
            try escape(w.a, &w.out, attr.value, true);
            try w.out.append(w.a, '"');
        }
        if (w.styles[index].len > 0) {
            try w.out.appendSlice(w.a, " style=\"");
            try escape(w.a, &w.out, w.styles[index], true);
            try w.out.append(w.a, '"');
        }
        try w.out.append(w.a, '>');
        var child = n.first_child;
        while (child != svg_dom.NONE) : (child = w.nodes[child].next_sibling) try w.node(child);
        try w.out.appendSlice(w.a, "</");
        try w.out.appendSlice(w.a, tag);
        try w.out.append(w.a, '>');
    }
};

pub fn generate(f: *rt.Frame) rt.Error!void {
    if (!f.css_on) return;
    const count = f.dom.els.items.len;
    for (0..count) |host| {
        const el = f.dom.els.items[host];
        if (el.kind != .image or !std.ascii.eqlIgnoreCase(el.tag, "svg")) continue;
        const source = el.src orelse continue;
        const parsed = xml.parse(f.a, source) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            continue;
        };
        if (parsed.nodes.len == 0) continue;
        // Takumi gives the SVG layout its subtree and the page rules, rather than a live
        // HTML ancestor chain. Selectors can cross SVG ancestors, but not the image boundary.
        var combined: html_dom.Dom = .{};
        var root = el;
        const root_attrs = try f.a.alloc(html_dom.Attr, parsed.nodes[0].attrs.len);
        for (parsed.nodes[0].attrs, root_attrs) |attr, *dst| dst.* = .{ .name = attr.name, .value = attr.value };
        root.attrs = root_attrs;
        root.parent = html_dom.none;
        root.first = html_dom.none;
        root.last = html_dom.none;
        root.prev = html_dom.none;
        root.next = html_dom.none;
        combined.root = try combined.add(f.a, root, html_dom.none);
        const ids = try f.a.alloc(u32, parsed.nodes.len);
        ids[0] = combined.root;
        for (parsed.nodes[1..], 1..) |n, i| {
            const attrs = try f.a.alloc(html_dom.Attr, n.attrs.len);
            for (n.attrs, attrs) |attr, *dst| dst.* = .{ .name = attr.name, .value = attr.value };
            ids[i] = try combined.add(f.a, .{
                .kind = if (n.tag == .textnode) .text else .container,
                .run = n.tag == .textnode,
                .text = n.text,
                .tag = if (n.tag == .textnode) "" else svg_dom.tag_names[@backingInt(n.tag)],
                .id = n.attr("id") orelse "",
                .class = n.attr("class") orelse "",
                .attrs = attrs,
            }, ids[n.parent]);
        }
        // The page's already active rules and the SVG's own sheets share one cascade.
        var sheet: css.Stylesheet = .{};
        try sheet.layer_names.appendSlice(f.a, f.cssx.m.layer_names);
        for (f.cssx.m.rules) |active| {
            var rule = active.rule.*;
            rule.gates = &.{};
            rule.layer = if (active.layer == f.cssx.m.layer_count) css.sheet.no_layer else active.layer;
            try sheet.rules.append(f.a, rule);
        }
        for (parsed.nodes) |n| if (n.tag == .style) try css.parse(f.a, n.text, &sheet);
        const matcher = try css.prepare(f.a, &sheet, .{ .viewport_w = f.ctx.viewport_w, .viewport_h = f.ctx.viewport_h, .print = if (comptime @import("../config.zig").enable_pdf) f.tree.paged.pdf else false, .dpr = f.opts.dpr });
        var scratch = css.Scratch.init(f.a);
        const vt = rt.CssDom.vtable(&combined);
        var declarations: @TypeOf(f.cssx.decls) = .empty;
        const styles = try f.a.alloc([]const u8, parsed.nodes.len);
        for (parsed.nodes, 0..) |n, i| {
            declarations.clearRetainingCapacity();
            const matched = try css.match(&matcher, &scratch, &vt, ids[i], .none, &declarations);
            var normal: std.ArrayList(svg_dom.Decl) = .empty;
            var important: std.ArrayList(svg_dom.Decl) = .empty;
            try svg_css.parseDecls(f.a, n.attr("style") orelse "", &normal, &important);
            var values: [svg_dom.Prop.COUNT]?[]const u8 = @splat(null);
            for (declarations.items[0..matched.important_start]) |d| if (svg_dom.Prop.fromName(d.name)) |p| {
                values[@backingInt(p)] = d.value;
            };
            for (normal.items) |d| values[@backingInt(d.prop)] = d.value;
            for (declarations.items[matched.important_start..]) |d| if (svg_dom.Prop.fromName(d.name)) |p| {
                values[@backingInt(p)] = d.value;
            };
            for (important.items) |d| values[@backingInt(d.prop)] = d.value;
            if (i == 0) {
                // The host's HTML box already applies these properties around the SVG viewport.
                // Descendant SVG elements still use them in SVG paint space.
                for ([_]svg_dom.Prop{ .opacity, .transform, .mix_blend_mode, .isolation, .clip_path, .mask, .filter }) |p|
                    values[@backingInt(p)] = null;
            }
            var text: std.ArrayList(u8) = .empty;
            for (values, 0..) |value, p| if (value) |v| {
                const name = @tagName(@as(svg_dom.Prop, @fromBackingInt(@intCast(p))));
                for (name) |c| try text.append(f.a, if (c == '_') '-' else c);
                try text.append(f.a, ':');
                try text.appendSlice(f.a, v);
                try text.appendSlice(f.a, "!important;");
            };
            styles[i] = text.items;
        }
        var writer: Writer = .{ .a = f.a, .nodes = parsed.nodes, .styles = styles };
        try writer.node(0);
        f.dom.els.items[host].src = writer.out.items;
    }
}
