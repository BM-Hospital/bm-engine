//! Resource discovery from computed styles, without requiring font bytes or laying out text.
const std = @import("std");
const rt = @import("../render.zig");
const dom = @import("../dom.zig");
const style = @import("../style/style.zig");
const css = @import("../css/css.zig");
const svg_dom = @import("../svg/dom.zig");
const svg_style = @import("../svg/style.zig");
const aType = std.mem.Allocator;

pub const Collector = struct {
    a: aType,
    images: std.StringHashMapUnmanaged(void) = .empty,
    text: std.ArrayList(u8) = .empty,
    requests: std.ArrayList(u8) = .empty,
    faces: std.ArrayList(u8) = .empty,

    fn image(c: *Collector, value: style.Image) !void {
        if (value == .url and value.url.len > 0) try c.images.put(c.a, value.url, {});
    }
    fn textOf(c: *Collector, text: []const u8, cs: *const style.ComputedStyle) !void {
        if (text.len == 0 or cs.display == .none) return;
        const shown = try rt.transformText(c.a, text, cs.text_transform, cs.white_space_collapse == .preserve or cs.white_space_collapse == .preserve_spaces or cs.white_space_collapse == .break_spaces);
        try c.text.appendSlice(c.a, shown);
        if (c.requests.items.len > 0) try c.requests.append(c.a, ',');
        try c.requests.appendSlice(c.a, "{\"text\":");
        try rt.writeJsonString(c.a, &c.requests, shown);
        try c.requests.appendSlice(c.a, ",\"families\":[");
        for (cs.font_family, 0..) |name, i| {
            if (i != 0) try c.requests.append(c.a, ',');
            try rt.writeJsonString(c.a, &c.requests, name);
        }
        try c.requests.appendSlice(c.a, "],\"weight\":");
        try rt.writeNum(c.a, &c.requests, cs.font_weight);
        try c.requests.appendSlice(c.a, if (cs.font_style == .normal) ",\"style\":\"normal\"}" else ",\"style\":\"italic\"}");
    }
    fn svgText(c: *Collector, f: *const rt.Frame, src: []const u8, cs: *const style.ComputedStyle) !void {
        if (comptime !@import("../config.zig").enable_svg) return;
        const source = f.r.resolveSvg(src) orelse return;
        const svg = @import("../svg/svg.zig");
        const tree = svg.parse(c.a, source) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return,
        };
        try c.svgNode(&tree, 0, .{}, cs, false, 0);
    }
    fn svgNode(c: *Collector, tree: *const svg_dom.Document, id: u32, parent: svg_style.Style, cs: *const style.ComputedStyle, referenced: bool, depth: u32) rt.Error!void {
        if (depth >= svg_dom.MAX_DEPTH or id >= tree.nodes.len) return;
        const node = &tree.nodes[id];
        if (node.decl(.display)) |v| if (std.mem.eql(u8, std.mem.trim(u8, v, " \t\r\n"), "none")) return;
        if (!referenced) switch (node.tag) {
            .defs, .symbol, .clipPath, .mask, .pattern, .marker, .filter => return,
            else => {},
        };
        var inherited = parent;
        inherited.apply(node);
        if (node.tag == .textnode and inherited.visible and inherited.font_size > 0) {
            var text_cs = cs.*;
            text_cs.text_transform = .none;
            text_cs.font_style = .normal;
            const weight = std.mem.trim(u8, inherited.font_weight, " \t\r\n");
            text_cs.font_weight = if (std.mem.eql(u8, weight, "bold") or std.mem.eql(u8, weight, "bolder")) 700 else if (std.mem.eql(u8, weight, "lighter")) 300 else std.fmt.parseInt(u16, weight, 10) catch 400;
            if (text_cs.font_weight < 1 or text_cs.font_weight > 1000) text_cs.font_weight = 400;
            var families: std.ArrayList([]const u8) = .empty;
            var it = std.mem.splitScalar(u8, inherited.font_family, ',');
            while (it.next()) |raw| {
                const name = std.mem.trim(u8, raw, " \t\r\n'\"");
                if (name.len > 0) try families.append(c.a, name);
            }
            if (families.items.len > 0) text_cs.font_family = families.items;
            try c.textOf(node.text, &text_cs);
        }
        if (node.tag == .use) {
            if (node.attr("href")) |href| if (tree.byRef(href)) |target| try c.svgNode(tree, target, inherited, cs, true, depth + 1);
            return;
        }
        var child = node.first_child;
        while (child != svg_dom.NONE) : (child = tree.nodes[child].next_sibling) try c.svgNode(tree, child, inherited, cs, false, depth + 1);
    }
    pub fn collect(c: *Collector, f: *const rt.Frame) !void {
        for (f.dom.els.items) |el| {
            if (el.cs.display == .none) continue;
            var parent = el.parent;
            var visible = true;
            var guard: u32 = 0;
            while (parent != dom.none and guard < 512) : (guard += 1) {
                const p = f.dom.at(parent);
                if (p.cs.display == .none) {
                    visible = false;
                    break;
                }
                parent = p.parent;
            }
            if (!visible) continue;
            if (el.kind == .image) if (el.src) |src| {
                if (src.len > 0 and src[0] != '<') try c.images.put(c.a, src, {});
                try c.svgText(f, src, el.cs);
            };
            for (el.cs.background_image) |v| {
                try c.image(v);
                if (v == .url) try c.svgText(f, v.url, el.cs);
            }
            for (el.cs.mask_image) |v| try c.image(v);
            if (el.cs.display == .list_item) try c.image(el.cs.list_style_image);
            try c.textOf(el.text, el.cs);
        }
        for (f.pseudos.items) |p| {
            try c.textOf(p.text, p.cs);
            for (p.cs.background_image) |v| try c.image(v);
            if (p.parts) |parts| for (parts) |part| if (part == .url) try c.images.put(c.a, part.url, {});
        }
        if (comptime @import("../config.zig").enable_css) for (css.fontFaces(&f.cssx.m)) |face| {
            if (c.faces.items.len > 0) try c.faces.append(c.a, ',');
            try c.faces.appendSlice(c.a, "{\"name\":");
            try rt.writeJsonString(c.a, &c.faces, face.family);
            const fields = [_][]const u8{ "src", "font-weight", "font-style", "unicode-range" };
            const keys = [_][]const u8{ "src", "weight", "style", "unicodeRange" };
            for (fields, keys) |field, key| if (face.get(field)) |value| {
                try c.faces.append(c.a, ',');
                try rt.writeJsonString(c.a, &c.faces, key);
                try c.faces.append(c.a, ':');
                try rt.writeJsonString(c.a, &c.faces, value);
            };
            try c.faces.append(c.a, '}');
        };
    }
    pub fn finish(c: *Collector) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(c.a, "{\"images\":[");
        var it = c.images.keyIterator();
        var first = true;
        while (it.next()) |url| {
            if (!first) try out.append(c.a, ',');
            first = false;
            try rt.writeJsonString(c.a, &out, url.*);
        }
        try out.appendSlice(c.a, "],\"text\":");
        try rt.writeJsonString(c.a, &out, c.text.items);
        try out.appendSlice(c.a, ",\"requests\":[");
        try out.appendSlice(c.a, c.requests.items);
        try out.appendSlice(c.a, "],\"faces\":[");
        try out.appendSlice(c.a, c.faces.items);
        try out.appendSlice(c.a, "]}");
        return out.items;
    }
};
