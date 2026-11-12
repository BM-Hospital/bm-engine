//! Named pages: the `page` property (takumi-core `breaks.page`, Blink's named pages; css-page-3
//! §6). Read here, between the cascade and the render-node build of a frame a PDF is drawn from
//! (render.zig `Frame.prepare`), from the declarations the element's cascade layers hold (the
//! computed style has no field for it: the property exists in PDF builds only), and handed to the
//! layout as `layout.Breaks.page` ids (render.zig `layoutNode`; fragment.zig forces a break where
//! the used page name changes between block siblings and names each page). The page rules of a
//! name are page_rules.zig's.
//!
//! Values: `auto` (the parent's page) or a custom identifier; anything else is invalid, so the
//! declaration is dropped (`page` is not inherited, so an element without one is `auto`).
const std = @import("std");
const render = @import("../render.zig");
const style = @import("../style/style.zig");
const json = @import("../json.zig");

const Frame = render.Frame;
const Error = render.Error;

/// Whether `text` holds a `page` declaration (`page` as a whole word, then `:`; not `@page`,
/// `page-break-*` or `--page`).
pub fn declaresPage(text: []const u8) bool {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, "page")) |i| {
        at = i + 4;
        if (i > 0) {
            const c = text[i - 1];
            if (c == '@' or c == '-' or c == '_' or std.ascii.isAlphanumeric(c)) continue;
        }
        var k = i + 4;
        while (k < text.len and (text[k] == ' ' or text[k] == '\t' or text[k] == '\n' or text[k] == '\r' or text[k] == '"')) k += 1;
        if (k < text.len and text[k] == ':') return true;
    }
    return false;
}

fn jsonMentions(v: json.Value, depth: u32) bool {
    if (depth > 32) return true;
    return switch (v) {
        .string => |s| declaresPage(s),
        .array => |arr| for (arr) |x| {
            if (jsonMentions(x, depth + 1)) break true;
        } else false,
        .object => |o| for (o) |kv| {
            if (std.mem.eql(u8, kv.key, "page") or jsonMentions(kv.value, depth + 1)) break true;
        } else false,
        else => false,
    };
}

/// A cheap look for any `page` declaration a frame's sources may hold (stylesheets, `<style>`,
/// inline styles, Tailwind arbitrary properties), so documents without one skip the per-element
/// cascade below.
fn mentionsPage(f: *const Frame) bool {
    if (f.opts.css) |c| if (jsonMentions(c, 0)) return true;
    if (f.opts.stylesheets) |c| if (jsonMentions(c, 0)) return true;
    for (f.dom.styles) |s| if (declaresPage(s)) return true;
    for (f.dom.els.items) |*el| {
        if (el.run) continue;
        if (el.tw.len > 0 and std.mem.indexOf(u8, el.tw, "page") != null) return true;
        switch (el.style) {
            .text => |t| if (declaresPage(t)) return true,
            .json => |v| if (jsonMentions(v, 0)) return true,
            .none => {},
        }
    }
    return false;
}

/// A valid `page` value: a custom identifier (null for `auto` and anything invalid).
fn parseName(value: []const u8) ?[]const u8 {
    const v = std.mem.trim(u8, value, " \t\r\n\x0c");
    if (v.len == 0 or std.ascii.eqlIgnoreCase(v, "auto")) return null;
    // (CSS-wide keywords are no names; `initial` / `unset` reset to `auto`)
    for ([_][]const u8{ "inherit", "initial", "unset", "revert", "revert-layer", "default" }) |kw| if (std.ascii.eqlIgnoreCase(v, kw)) return null;
    const first = v[0];
    if (!(std.ascii.isAlphabetic(first) or first == '_' or first == '-' or first >= 0x80)) return null;
    if (first == '-' and (v.len < 2 or std.ascii.isDigit(v[1]))) return null;
    for (v) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-' or c >= 0x80)) return null;
    return v;
}

/// The cascaded `page` value of element `i`: the last declaration of the highest layer, an
/// important one over any normal one (null: `auto`).
fn cascaded(f: *Frame, i: u32) Error!?[]const u8 {
    var diag: style.Diagnostics = .{};
    var layers: [render.Frame.max_layers]style.Layer = undefined;
    const n = try f.elementLayers(i, &diag, &layers);
    var normal: ?[]const u8 = null;
    var important: ?[]const u8 = null;
    var have_normal = false;
    var have_important = false;
    for (layers[0..n]) |layer| for (layer.decls) |d| {
        if (!std.ascii.eqlIgnoreCase(d.name, "page")) continue;
        const v = parseName(d.value);
        // (an invalid value is dropped; `auto` and the CSS-wide keywords count)
        const vt = std.mem.trim(u8, d.value, " \t\r\n\x0c");
        if (v == null and !(std.ascii.eqlIgnoreCase(vt, "auto") or std.ascii.eqlIgnoreCase(vt, "initial") or std.ascii.eqlIgnoreCase(vt, "unset") or std.ascii.eqlIgnoreCase(vt, "inherit"))) continue;
        if (d.important) {
            important = v;
            have_important = true;
        } else {
            normal = v;
            have_normal = true;
        }
    };
    if (have_important) return important;
    if (have_normal) return normal;
    return null;
}

/// Gives the frame's elements their page name ids (`layout.fragment.PagedState.page_of`, by element
/// index; `page_names[id - 1]` is name `id`).
pub fn collect(f: *Frame) Error!void {
    if (!mentionsPage(f)) return;
    const a = f.a;
    const count = f.dom.els.items.len;
    const ids = try a.alloc(u32, count);
    @memset(ids, 0);
    var names: std.ArrayList([]const u8) = .empty;
    var any = false;
    for (0..count) |k| {
        const i: u32 = @intCast(k);
        const el = f.dom.at(i);
        if (el.run) continue;
        const name = (try cascaded(f, i)) orelse continue;
        const id = for (names.items, 0..) |x, j| {
            if (std.mem.eql(u8, x, name)) break j + 1;
        } else blk: {
            try names.append(a, name);
            break :blk names.items.len;
        };
        ids[k] = @intCast(id);
        any = true;
    }
    if (!any) return;
    f.tree.paged.page_of = ids;
    f.tree.paged.page_names = names.items;
}

/// The `layout.Breaks.page` id of element `el` (0 = `auto`).
pub fn idOf(f: *const Frame, el: u32) u32 {
    const ids = f.tree.paged.page_of;
    return if (el < ids.len) ids[el] else 0;
}

/// The name of page name id `id` (null: unnamed).
pub fn nameOf(f: *const Frame, id: u32) ?[]const u8 {
    const names = f.tree.paged.page_names;
    return if (id >= 1 and id <= names.len) names[id - 1] else null;
}

test "the page property: declarations and values" {
    const T = std.testing;
    try T.expect(declaresPage(".cover { page: cover }"));
    try T.expect(declaresPage("page:wide"));
    try T.expect(!declaresPage("@page cover { margin: 0 }"));
    try T.expect(!declaresPage("p { page-break-before: always }"));
    try T.expect(!declaresPage("--page: x"));
    try T.expectEqualStrings("cover", parseName(" cover ").?);
    try T.expect(parseName("auto") == null);
    try T.expect(parseName("initial") == null);
    try T.expect(parseName("1x") == null);
    try T.expect(parseName("a b") == null);
}
