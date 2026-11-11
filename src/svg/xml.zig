//! Lenient, bounded XML parser producing `dom.Node`s. Never fails on malformed markup after the
//! root element was found: it keeps what was parsed so far (like a browser rendering up to the
//! first error). Comments, PIs and the DOCTYPE are skipped; internal-subset `<!ENTITY>`
//! declarations are recorded and expanded one level deep.
const std = @import("std");
const dom = @import("dom.zig");
const Allocator = std.mem.Allocator;
const Node = dom.Node;
const NONE = dom.NONE;

pub const Error = error{ OutOfMemory, InvalidSvg };

const SVG_NS = "http://www.w3.org/2000/svg";
const MAX_ENTITIES = 32;

const Entity = struct { name: []const u8, value: []const u8 };

const Parser = struct {
    arena: Allocator,
    s: []const u8,
    i: usize = 0,
    nodes: std.ArrayList(Node) = .empty,
    stack: [dom.MAX_DEPTH]u32 = undefined,
    depth: u32 = 0,
    /// open elements we are not materialising (too deep / over the node limit)
    skip: u32 = 0,
    entities: [MAX_ENTITIES]Entity = undefined,
    n_entities: usize = 0,
    svg_prefixes: [4][]const u8 = undefined,
    n_prefixes: usize = 0,
    root_closed: bool = false,
    unsupported: dom.Unsupported = .{},

    fn startsWith(p: *const Parser, lit: []const u8) bool {
        return std.mem.startsWith(u8, p.s[p.i..], lit);
    }

    fn skipPast(p: *Parser, lit: []const u8) void {
        if (std.mem.indexOfPos(u8, p.s, p.i, lit)) |j| p.i = j + lit.len else p.i = p.s.len;
    }

    fn skipWs(p: *Parser) void {
        while (p.i < p.s.len and isWs(p.s[p.i])) p.i += 1;
    }

    fn name(p: *Parser) []const u8 {
        const st = p.i;
        while (p.i < p.s.len) : (p.i += 1) {
            const c = p.s[p.i];
            if (isWs(c) or c == '>' or c == '/' or c == '=' or c == '<' or c == '"' or c == '\'') break;
        }
        return p.s[st..p.i];
    }

    fn doctype(p: *Parser) void {
        // <!DOCTYPE name ... [ internal subset ] >
        while (p.i < p.s.len and p.s[p.i] != '[' and p.s[p.i] != '>') p.i += 1;
        if (p.i < p.s.len and p.s[p.i] == '[') {
            p.i += 1;
            while (p.i < p.s.len and p.s[p.i] != ']') {
                if (p.startsWith("<!ENTITY")) {
                    p.i += 8;
                    p.skipWs();
                    const n = p.name();
                    p.skipWs();
                    if (p.i < p.s.len and (p.s[p.i] == '"' or p.s[p.i] == '\'')) {
                        const q = p.s[p.i];
                        const st = p.i + 1;
                        const e = std.mem.indexOfScalarPos(u8, p.s, st, q) orelse p.s.len;
                        if (n.len > 0 and p.n_entities < MAX_ENTITIES and e - st <= 1 << 16) {
                            p.entities[p.n_entities] = .{ .name = n, .value = p.s[st..e] };
                            p.n_entities += 1;
                        }
                        p.i = @min(e + 1, p.s.len);
                    }
                    p.skipPast(">");
                } else if (p.startsWith("<!--")) {
                    p.skipPast("-->");
                } else p.i += 1;
            }
        }
        p.skipPast(">");
    }

    fn isSvgPrefix(p: *const Parser, pre: []const u8) bool {
        for (p.svg_prefixes[0..p.n_prefixes]) |x| if (std.mem.eql(u8, x, pre)) return true;
        return false;
    }

    fn tagOf(p: *const Parser, qname: []const u8) dom.Tag {
        if (std.mem.indexOfScalar(u8, qname, ':')) |c| {
            if (!p.isSvgPrefix(qname[0..c])) return .unknown;
            return dom.Tag.fromName(qname[c + 1 ..]);
        }
        return dom.Tag.fromName(qname);
    }

    fn startTag(p: *Parser) Error!void {
        const qname = p.name();
        if (qname.len == 0) {
            p.skipPast(">");
            return;
        }
        var attrs: std.ArrayList(dom.Attr) = .empty;
        var self_closing = false;
        while (p.i < p.s.len) {
            p.skipWs();
            if (p.i >= p.s.len) break;
            const c = p.s[p.i];
            if (c == '>') {
                p.i += 1;
                break;
            }
            if (c == '/') {
                p.i += 1;
                if (p.i < p.s.len and p.s[p.i] == '>') {
                    p.i += 1;
                    self_closing = true;
                    break;
                }
                continue;
            }
            const an = p.name();
            if (an.len == 0) {
                p.i += 1;
                continue;
            }
            p.skipWs();
            var val: []const u8 = "";
            if (p.i < p.s.len and p.s[p.i] == '=') {
                p.i += 1;
                p.skipWs();
                if (p.i < p.s.len and (p.s[p.i] == '"' or p.s[p.i] == '\'')) {
                    const q = p.s[p.i];
                    const st = p.i + 1;
                    const e = std.mem.indexOfScalarPos(u8, p.s, st, q) orelse p.s.len;
                    val = p.s[st..e];
                    p.i = @min(e + 1, p.s.len);
                } else {
                    const st = p.i;
                    while (p.i < p.s.len and !isWs(p.s[p.i]) and p.s[p.i] != '>') p.i += 1;
                    val = p.s[st..p.i];
                }
            }
            if (p.skip > 0) continue;
            if (std.mem.indexOfScalar(u8, val, '&') != null) val = try p.decode(val);
            if (std.mem.startsWith(u8, an, "xmlns:") and std.mem.eql(u8, std.mem.trim(u8, val, " "), SVG_NS) and p.n_prefixes < 4) {
                p.svg_prefixes[p.n_prefixes] = an[6..];
                p.n_prefixes += 1;
            }
            try attrs.append(p.arena, .{ .name = an, .value = val });
        }

        if (p.root_closed) return;
        if (p.skip > 0 or p.depth >= dom.MAX_DEPTH or p.nodes.items.len >= dom.MAX_NODES) {
            if (!self_closing) p.skip += 1;
            return;
        }
        const tag = p.tagOf(qname);
        if (p.nodes.items.len == 0 and tag != .svg) return error.InvalidSvg;
        switch (tag) {
            .text => p.unsupported.text = true,
            .foreignObject => p.unsupported.foreign_object = true,
            .feImage, .feTile, .feTurbulence, .feMorphology, .feConvolveMatrix, .feDisplacementMap, .feDiffuseLighting, .feSpecularLighting => p.unsupported.filter_primitive = true,
            else => {},
        }
        if (tag == .image or tag == .use or tag == .feImage) {
            for (attrs.items) |at| {
                if (!std.mem.endsWith(u8, at.name, "href")) continue;
                const v = std.mem.trim(u8, at.value, " \t\r\n");
                if (v.len > 0 and v[0] != '#' and !std.mem.startsWith(u8, v, "data:")) p.unsupported.external_href = true;
            }
        }
        const idx: u32 = @intCast(p.nodes.items.len);
        var node: Node = .{ .tag = tag, .attrs = attrs.items, .depth = @intCast(p.depth) };
        if (p.depth > 0) {
            const parent = p.stack[p.depth - 1];
            node.parent = parent;
            const pn = &p.nodes.items[parent];
            if (pn.last_child == NONE) pn.first_child = idx else p.nodes.items[pn.last_child].next_sibling = idx;
            pn.last_child = idx;
        }
        try p.nodes.append(p.arena, node);
        if (self_closing) {
            if (p.depth == 0) p.root_closed = true;
        } else {
            p.stack[p.depth] = idx;
            p.depth += 1;
        }
    }

    fn endTag(p: *Parser) void {
        const qname = p.name();
        p.skipPast(">");
        if (p.skip > 0) {
            p.skip -= 1;
            return;
        }
        if (p.depth == 0) return;
        // pop to the matching open element (lenient); ignore stray end tags
        var d = p.depth;
        const tag = p.tagOf(qname);
        while (d > 0) {
            d -= 1;
            if (p.nodes.items[p.stack[d]].tag == tag) {
                p.depth = d;
                if (d == 0) p.root_closed = true;
                return;
            }
        }
    }

    fn keepsText(p: *const Parser) bool {
        if (p.depth == 0 or p.skip > 0) return false;
        return switch (p.nodes.items[p.stack[p.depth - 1]].tag) {
            .style, .text, .tspan, .textPath => true,
            else => false,
        };
    }

    fn appendText(p: *Parser, raw: []const u8, decode_entities: bool) Error!void {
        if (!p.keepsText() or raw.len == 0) return;
        const t = if (decode_entities and std.mem.indexOfScalar(u8, raw, '&') != null) try p.decode(raw) else raw;
        const parent = p.stack[p.depth - 1];
        if (p.nodes.items[parent].tag != .style) {
            // text content: an ordered child run (keeps interleaving with <tspan>s)
            if (p.nodes.items.len >= dom.MAX_NODES) return;
            const idx: u32 = @intCast(p.nodes.items.len);
            const pn = &p.nodes.items[parent];
            if (pn.last_child == NONE) pn.first_child = idx else p.nodes.items[pn.last_child].next_sibling = idx;
            pn.last_child = idx;
            try p.nodes.append(p.arena, .{ .tag = .textnode, .parent = parent, .depth = @intCast(p.depth), .text = t });
            return;
        }
        const n = &p.nodes.items[parent];
        if (n.text.len == 0) {
            n.text = t;
        } else {
            const cat = try p.arena.alloc(u8, n.text.len + t.len);
            @memcpy(cat[0..n.text.len], n.text);
            @memcpy(cat[n.text.len..], t);
            n.text = cat;
        }
    }

    /// Expands character / predefined / internal-subset entities.
    fn decode(p: *Parser, s: []const u8) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try out.ensureTotalCapacity(p.arena, s.len);
        var i: usize = 0;
        while (i < s.len) {
            const c = s[i];
            if (c != '&') {
                try out.append(p.arena, c);
                i += 1;
                continue;
            }
            const semi = std.mem.indexOfScalarPos(u8, s, i, ';') orelse {
                try out.append(p.arena, c);
                i += 1;
                continue;
            };
            const ent = s[i + 1 .. semi];
            if (ent.len > 0 and ent[0] == '#') {
                var cp: u32 = 0;
                var ok = ent.len > 1;
                if (ent.len > 1 and (ent[1] == 'x' or ent[1] == 'X')) {
                    ok = ent.len > 2;
                    for (ent[2..]) |h| {
                        const v = std.fmt.charToDigit(h, 16) catch {
                            ok = false;
                            break;
                        };
                        cp = @min(cp *% 16 +% v, 0x10FFFF + 1);
                    }
                } else {
                    for (ent[1..]) |h| {
                        if (h < '0' or h > '9') {
                            ok = false;
                            break;
                        }
                        cp = @min(cp *% 10 +% (h - '0'), 0x10FFFF + 1);
                    }
                }
                if (ok and cp <= 0x10FFFF and !(cp >= 0xD800 and cp < 0xE000) and cp != 0) {
                    var buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(@intCast(cp), &buf) catch 0;
                    try out.appendSlice(p.arena, buf[0..n]);
                }
                i = semi + 1;
                continue;
            }
            const rep: ?[]const u8 = if (std.mem.eql(u8, ent, "amp")) "&" else if (std.mem.eql(u8, ent, "lt")) "<" else if (std.mem.eql(u8, ent, "gt")) ">" else if (std.mem.eql(u8, ent, "quot")) "\"" else if (std.mem.eql(u8, ent, "apos")) "'" else blk: {
                for (p.entities[0..p.n_entities]) |e| if (std.mem.eql(u8, e.name, ent)) break :blk e.value;
                break :blk null;
            };
            if (rep) |r| {
                try out.appendSlice(p.arena, r);
                i = semi + 1;
            } else {
                try out.append(p.arena, c);
                i += 1;
            }
        }
        return out.items;
    }

    fn run(p: *Parser) Error!void {
        // BOM
        if (p.startsWith("\xEF\xBB\xBF")) p.i = 3;
        while (p.i < p.s.len and !p.root_closed) {
            const c = p.s[p.i];
            if (c != '<') {
                const st = p.i;
                p.i = std.mem.indexOfScalarPos(u8, p.s, p.i, '<') orelse p.s.len;
                try p.appendText(p.s[st..p.i], true);
                continue;
            }
            if (p.startsWith("<!--")) {
                p.i += 4;
                p.skipPast("-->");
            } else if (p.startsWith("<![CDATA[")) {
                const st = p.i + 9;
                const e = std.mem.indexOfPos(u8, p.s, st, "]]>") orelse p.s.len;
                try p.appendText(p.s[st..e], false);
                p.i = @min(e + 3, p.s.len);
            } else if (p.startsWith("<!DOCTYPE") or p.startsWith("<!doctype")) {
                p.i += 9;
                p.doctype();
            } else if (p.startsWith("<!") or p.startsWith("<?")) {
                p.skipPast(">");
            } else if (p.startsWith("</")) {
                p.i += 2;
                p.endTag();
            } else {
                p.i += 1;
                try p.startTag();
            }
        }
        if (p.nodes.items.len == 0) return error.InvalidSvg;
    }
};

pub fn isWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

pub const Result = struct { nodes: []Node, unsupported: dom.Unsupported };

pub fn parse(arena: Allocator, text: []const u8) Error!Result {
    var p: Parser = .{ .arena = arena, .s = text };
    try p.run();
    return .{ .nodes = p.nodes.items, .unsupported = p.unsupported };
}

/// Sniffing: optional BOM / whitespace / XML declaration / comments / doctype, then `<svg`.
pub fn looksLikeSvg(bytes: []const u8) bool {
    var p: Parser = .{ .arena = undefined, .s = bytes };
    if (p.startsWith("\xEF\xBB\xBF")) p.i = 3;
    var guard: usize = 0;
    while (guard < 64) : (guard += 1) {
        p.skipWs();
        if (p.startsWith("<?")) {
            p.skipPast("?>");
        } else if (p.startsWith("<!--")) {
            p.skipPast("-->");
        } else if (p.startsWith("<!DOCTYPE") or p.startsWith("<!doctype")) {
            p.i += 9;
            // doctype() only reads, never allocates
            p.doctype();
        } else break;
    }
    if (!p.startsWith("<svg")) return false;
    if (p.i + 4 >= bytes.len) return false;
    const c = bytes[p.i + 4];
    return isWs(c) or c == '>' or c == '/' or c == ':';
}

test "xml basics" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const r = try parse(a,
        \\<?xml version="1.0"?><!DOCTYPE svg [ <!ENTITY ns "http://www.w3.org/2000/svg"> ]>
        \\<!-- c --><svg xmlns="&ns;" xmlns:s="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
        \\<style><![CDATA[ .a { fill: red } ]]></style><s:rect id="r" title="a&amp;b&#x41;&#66;"/>
        \\<use xlink:href="#r"/><dc:x><g/></dc:x></svg><rect/>
    );
    try std.testing.expectEqual(@as(usize, 6), r.nodes.len);
    try std.testing.expectEqualStrings("http://www.w3.org/2000/svg", r.nodes[0].attr("xmlns").?);
    try std.testing.expectEqualStrings(" .a { fill: red } ", r.nodes[1].text);
    try std.testing.expectEqual(dom.Tag.rect, r.nodes[2].tag);
    try std.testing.expectEqualStrings("a&bAB", r.nodes[2].attr("title").?);
    try std.testing.expectEqualStrings("#r", r.nodes[3].attr("href").?);
    try std.testing.expectEqual(dom.Tag.unknown, r.nodes[4].tag);
    try std.testing.expect(looksLikeSvg("\xEF\xBB\xBF <?xml?><!-- x --><!DOCTYPE svg><svg>"));
    try std.testing.expect(!looksLikeSvg("<svgx>"));
    try std.testing.expectError(error.InvalidSvg, parse(a, "<html/>"));
}
