// Test harness (NOT library code): exposes src/html/html.zig to Node as JSON.
const std = @import("std");
const html = @import("html");

var arena_state = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
var out: std.ArrayList(u8) = .empty;

export fn alloc(n: usize) usize {
    const s = std.heap.wasm_allocator.alloc(u8, n) catch return 0;
    return @intFromPtr(s.ptr);
}
export fn out_len() usize {
    return out.items.len;
}

fn raw(a: std.mem.Allocator, s: []const u8) void {
    out.appendSlice(a, s) catch {};
}

fn str(a: std.mem.Allocator, s: []const u8) void {
    raw(a, "\"");
    for (s) |c| {
        switch (c) {
            '"' => raw(a, "\\\""),
            '\\' => raw(a, "\\\\"),
            '\n' => raw(a, "\\n"),
            '\r' => raw(a, "\\r"),
            '\t' => raw(a, "\\t"),
            0...8, 11, 12, 14...31 => {
                const hex = "0123456789abcdef";
                raw(a, "\\u00");
                out.append(a, hex[c >> 4]) catch {};
                out.append(a, hex[c & 15]) catch {};
            },
            else => out.append(a, c) catch {},
        }
    }
    raw(a, "\"");
}

fn attrs(a: std.mem.Allocator, list: []const html.Attr) void {
    raw(a, "{");
    for (list, 0..) |at, i| {
        if (i != 0) raw(a, ",");
        str(a, at.name);
        raw(a, ":");
        str(a, at.value);
    }
    raw(a, "}");
}

fn node(a: std.mem.Allocator, n: *const html.Node) void {
    if (n.kind == .text) {
        str(a, n.text);
        return;
    }
    raw(a, "{\"t\":");
    str(a, n.tag);
    raw(a, ",\"a\":");
    attrs(a, n.attrs);
    if (std.mem.eql(u8, n.tag, "svg")) {
        raw(a, ",\"svg\":");
        str(a, n.text);
    }
    for (html.preset(n.tag)) |d| {
        if (std.mem.eql(u8, d.name, "display")) {
            raw(a, ",\"d\":");
            str(a, d.value);
        }
    }
    raw(a, ",\"c\":[");
    for (n.children, 0..) |c, i| {
        if (i != 0) raw(a, ",");
        node(a, c);
    }
    raw(a, "]}");
}

export fn parse_json(ptr: [*]const u8, len: usize) usize {
    _ = arena_state.reset(.retain_capacity);
    const a = arena_state.allocator();
    out = .empty;
    const d = html.parse(a, ptr[0..len]) catch |e| {
        raw(a, if (e == error.TooDeep) "{\"error\":\"TooDeep\"}" else "{\"error\":\"OOM\"}");
        return @intFromPtr(out.items.ptr);
    };
    raw(a, "{\"doc\":");
    raw(a, if (d.is_document) "true" else "false");
    raw(a, ",\"title\":");
    str(a, d.title);
    raw(a, ",\"body\":");
    attrs(a, d.body_attrs);
    raw(a, ",\"styles\":[");
    for (d.styles, 0..) |s, i| {
        if (i != 0) raw(a, ",");
        str(a, s);
    }
    raw(a, "],\"roots\":[");
    for (d.root_children, 0..) |c, i| {
        if (i != 0) raw(a, ",");
        node(a, c);
    }
    raw(a, "]}");
    return @intFromPtr(out.items.ptr);
}
