//! File-layer behaviour checked end to end against what takumi-pdf 0.20.0 writes for the same
//! input (the cases of scripts/pdf-audit/{conformance,links,tagging,fonts}.probe.mjs): page
//! entries, validation error counts, link annotations and the structure tree.
const std = @import("std");
const config = @import("../config.zig");
const rt = @import("../render.zig");
const pdf = @import("pdf.zig");

const testing = std.testing;
const Renderer = rt.Renderer;

const inter = @embedFile("../font/testdata/Inter-Regular.ttf");

const T = struct {
    r: *Renderer,

    fn init() !T {
        const gpa = testing.allocator;
        const r = Renderer.create(gpa).?;
        errdefer r.destroy();
        _ = try r.registerFont(try gpa.dupe(u8, inter), "", 0, -1);
        return .{ .r = r };
    }

    fn deinit(t: T) void {
        t.r.destroy();
    }

    /// The readable PDF of `html` under the options (JSON).
    fn render(t: T, html: []const u8, opts: []const u8) ![]const u8 {
        return pdf.renderReadable(t.r, .html, html, opts);
    }

    /// The error message of a render that must fail.
    fn err(t: T, html: []const u8, opts: []const u8) ![]const u8 {
        try testing.expectError(error.Invalid, pdf.renderReadable(t.r, .html, html, opts));
        return t.r.err;
    }
};

fn count(hay: []const u8, needle: []const u8) usize {
    return std.mem.count(u8, hay, needle);
}

fn has(hay: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, hay, needle) != null;
}

fn expectHas(hay: []const u8, needle: []const u8) !void {
    if (!has(hay, needle)) {
        std.debug.print("missing: {s}\n", .{needle});
        return error.TestUnexpectedResult;
    }
}

const meta = "\"metadata\":{\"title\":\"T\",\"creationDate\":\"2026-08-06T01:02:03\"}";

test "page /Tabs: written for a page with a link also when the document is untagged" {
    if (comptime !config.enable_pdf) return;
    const t = try T.init();
    defer t.deinit();
    const link = "<p><a href=\"https://example.com/\">x</a></p>";
    try expectHas(try t.render(link, "{\"tagged\":false}"), "/Tabs/S");
    try testing.expect(!has(try t.render("<p>x</p>", "{\"tagged\":false}"), "/Tabs"));
    try expectHas(try t.render("<p>x</p>", "{\"pdfa\":\"2a\",\"lang\":\"en\"," ++ meta ++ "}"), "/Tabs/S");
}

test "validation: one error per distinct glyph and character; string, name and q limits" {
    if (comptime !config.enable_pdf) return;
    const t = try T.init();
    defer t.deinit();
    const a4 = "{\"pdfa\":\"4\",\"uncoveredText\":\"blank\"," ++ meta ++ "}";
    // (Inter draws U+E000 and U+E001; U+E002 has no glyph and "blank" leaves it out)
    try testing.expectEqualStrings("Writing the PDF failed: validation failed with 2 errors", try t.err("<p>a\u{E000}b\u{E001}c\u{E002}</p>", a4));
    try testing.expectEqualStrings("Writing the PDF failed: validation failed with 1 error", try t.err("<p>\u{E000} and \u{E000}</p>", a4));
    const a2b = "{\"pdfa\":\"2b\"," ++ meta ++ "}";
    // 40 nested clips nest q deeper than 28; 14 do not
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    for ([_]usize{ 40, 14 }) |n| {
        buf.clearRetainingCapacity();
        for (0..n) |_| try buf.appendSlice(testing.allocator, "<div style=\"overflow:hidden;padding:1px\">");
        try buf.appendSlice(testing.allocator, "x");
        for (0..n) |_| try buf.appendSlice(testing.allocator, "</div>");
        if (n == 40) {
            try testing.expectEqualStrings("Writing the PDF failed: validation failed with 1 error", try t.err(buf.items, a2b));
            // PDF/A-4 has no such limit
            _ = try t.render(buf.items, "{\"pdfa\":\"4\"," ++ meta ++ "}");
        } else _ = try t.render(buf.items, a2b);
    }
    // a link URI over 32767 bytes
    buf.clearRetainingCapacity();
    try buf.appendSlice(testing.allocator, "<p><a href=\"https://e.com/");
    try buf.appendNTimes(testing.allocator, 'a', 40000);
    try buf.appendSlice(testing.allocator, "\">x</a></p>");
    try testing.expectEqualStrings("Writing the PDF failed: validation failed with 1 error", try t.err(buf.items, a2b));
    _ = try t.render(buf.items, "{}");
    // a title of 32768 bytes fails, 32767 pass
    for ([_]usize{ 32768, 32767 }) |n| {
        buf.clearRetainingCapacity();
        try buf.appendSlice(testing.allocator, "{\"pdfa\":\"2b\",\"metadata\":{\"creationDate\":\"2026-08-06\",\"title\":\"");
        try buf.appendNTimes(testing.allocator, 't', n);
        try buf.appendSlice(testing.allocator, "\"}}");
        if (n == 32768) {
            try testing.expectEqualStrings("Writing the PDF failed: validation failed with 1 error", try t.err("<p>x</p>", buf.items));
        } else _ = try t.render("<p>x</p>", buf.items);
    }
}

test "links: anonymous blocks, repeated table header and footer groups" {
    if (comptime !config.enable_pdf) return;
    const t = try T.init();
    defer t.deinit();
    // inline content next to a block-level sibling sits in an anonymous block: not linked
    const anon = try t.render("<div>block</div><a href=\"https://a.example/\">a</a> <span href=\"https://s.example/\">s</span>", "{}");
    try testing.expectEqual(@as(usize, 0), count(anon, "/Subtype/Link"));
    // the inline content of an element is, whatever element carries the href
    const inl = try t.render("<p><span href=\"https://s.example/\">s</span> <a href=\"https://a.example/\">a</a></p>", "{}");
    try testing.expectEqual(@as(usize, 2), count(inl, "/Subtype/Link"));

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try buf.appendSlice(testing.allocator, "<table><thead><tr><th><a href=\"https://thead.example/\">head</a></th></tr></thead><tbody>");
    for (0..40) |_| try buf.appendSlice(testing.allocator, "<tr><td>row</td></tr>");
    try buf.appendSlice(testing.allocator, "</tbody><tfoot><tr><td><a href=\"https://tfoot.example/\">foot</a></td></tr></tfoot></table>");
    const doc = try t.render(buf.items, "{\"size\":\"A5\"}");
    const pages = count(doc, "/Type/Page/");
    try testing.expect(pages >= 2);
    // every page that repeats the groups annotates their links
    try testing.expectEqual(pages, count(doc, "/URI(https://thead.example/)"));
    try testing.expectEqual(pages, count(doc, "/URI(https://tfoot.example/)"));
    // only the first occurrence of each joins the structure tree
    try testing.expectEqual(@as(usize, 2), count(doc, "/StructParent "));
    try testing.expectEqual(@as(usize, 2), count(doc, "/S/Link"));
    // PDF/UA and PDF/A-2a require the alternate text the repeats lack
    try buf.insertSlice(testing.allocator, 0, "<h1>T</h1>");
    try testing.expectEqualStrings("Writing the PDF failed: validation failed with 1 error", try t.err(buf.items, "{\"size\":\"A5\",\"tagged\":\"ua1\",\"lang\":\"en\"," ++ meta ++ "}"));
    try testing.expectEqualStrings("Writing the PDF failed: validation failed with 1 error", try t.err(buf.items, "{\"size\":\"A5\",\"pdfa\":\"2a\",\"lang\":\"en\"," ++ meta ++ "}"));
}

const png1 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP4z8DAAMIM////ZwAAHu8E/KPItPcAAAAASUVORK5CYII=";

test "tagging: heading titles, empty inline blocks, element ids" {
    if (comptime !config.enable_pdf) return;
    const t = try T.init();
    defer t.deinit();
    // no text of a display:none descendant; the heading's text is its own content, no P inside
    const hidden = try t.render("<h1>seen <span style=\"display:none\">hidden</span></h1>", "{}");
    try expectHas(hidden, "/S/H1");
    try expectHas(hidden, "/T(seen)");
    try testing.expect(!has(hidden, "/S/P/"));
    // generated content is part of the title, of the outline entry too
    const gen = try t.render("<style>h2::before{content:\"1. \"}</style><h2>generated prefix</h2>", "{\"outline\":true}");
    try expectHas(gen, "/T(1. generated prefix)");
    try expectHas(gen, "/Title(1. generated prefix)");
    // a heading whose inline content puts nothing on a line keeps its element, with an empty
    // content sequence and no title (PDF/UA: MissingHeadingTitle)
    const blank = try t.render("<h1><span> </span></h1><p>x</p>", "{}");
    try expectHas(blank, "/S/H1");
    try testing.expect(!has(blank, "/T("));
    try testing.expectEqual(@as(usize, 2), count(blank, "BDC"));
    try testing.expectEqualStrings("Writing the PDF failed: validation failed with 2 errors", try t.err("<h1><span> </span></h1><p>x</p>", "{\"tagged\":\"ua1\",\"lang\":\"en\"," ++ meta ++ "}"));
    // `<div>  <span> </span>  </div>` is such a block too; `<p>   </p>` has no child at all
    const ws = try t.render("<p>   </p><p>a</p><div>  <span> </span>  </div>", "{}");
    try testing.expectEqual(@as(usize, 2), count(ws, "BDC"));
    // ids: child indices of takumi's render tree (no display:none box; a list marker first)
    try expectHas(try t.render("<p>0</p><p style=\"display:none\">n</p><ul><li>one</li><li id=\"a\">two</li></ul><p><a href=\"#a\">l</a></p>", "{}"), "/ID(Un.0.1.1)");
    try expectHas(try t.render("<p>0</p><ul><li><p>one</p></li><li><p id=\"a\">two</p></li></ul><p><a href=\"#a\">l</a></p>", "{}"), "/ID(Un.0.1.1.1)");
    // inline content next to a block sits in an anonymous block; white space inside it counts
    try expectHas(try t.render("<p>0</p><div>t <b>b</b> <img id=\"a\" alt=\"i\" width=\"5\" height=\"5\" src=\"" ++ png1 ++ "\"> y<p>q</p></div><p><a href=\"#a\">l</a></p>", "{}"), "/ID(Un.0.1.0.3)");
    // an inline element with a role around an image is an element of its own
    const il = try t.render("<p><a href=\"https://e.com/\"><img alt=\"pic\" width=\"5\" height=\"5\" src=\"" ++ png1 ++ "\"></a> <strong><img alt=\"q\" width=\"5\" height=\"5\" src=\"" ++ png1 ++ "\"></strong></p>", "{}");
    try expectHas(il, "/S/Link");
    try expectHas(il, "/S/Strong");
    try testing.expectEqual(@as(usize, 2), count(il, "/S/Figure"));
}

test "tagging: anonymous table boxes; nothing marked stays outside the tree" {
    if (comptime !config.enable_pdf) return;
    const t = try T.init();
    defer t.deinit();
    // text directly in a table: an anonymous row group, row and cell of its own
    const stray = try t.render("<table>stray text<tr><td>c</td></tr></table>", "{}");
    try testing.expectEqual(@as(usize, 2), count(stray, "/S/TBody"));
    try testing.expectEqual(@as(usize, 2), count(stray, "/S/TD"));
    try testing.expect(!has(stray, "null"));
    // a row group in a block is wrapped in an anonymous table; its block child in a row and cell
    const over = try t.render("<table style=\"display:block\"><tr style=\"display:block\"><td style=\"display:inline\">not a table</td></tr></table>", "{}");
    for ([_][]const u8{ "/S/Table", "/S/TBody", "/S/TR", "/S/TD", "/S/P" }) |role| try testing.expectEqual(@as(usize, 1), count(over, role));
    // cells without a table share one anonymous table and row
    const cells = try t.render("<p>a</p><div style=\"display:table-cell\">one</div><div style=\"display:table-cell\">two</div><p>b</p>", "{}");
    try testing.expectEqual(@as(usize, 1), count(cells, "/S/Table"));
    try testing.expectEqual(@as(usize, 1), count(cells, "/S/TR"));
    try testing.expectEqual(@as(usize, 2), count(cells, "/S/TD"));
    // a row's children that are no cells share one anonymous cell
    const row = try t.render("<div style=\"display:table\"><div style=\"display:table-row\"><p>p1</p><p>p2</p>text</div></div>", "{}");
    try testing.expectEqual(@as(usize, 1), count(row, "/S/TD"));
    try testing.expectEqual(@as(usize, 3), count(row, "/S/P"));
    // flex items are blockified: no table around a table-cell item
    try testing.expect(!has(try t.render("<div style=\"display:flex\"><div style=\"display:table-cell\">x</div></div>", "{}"), "/S/Table"));
}

test "tagging: list labels and numbering" {
    if (comptime !config.enable_pdf) return;
    const t = try T.init();
    defer t.deinit();
    // an inside marker is text of the item's line: no Lbl, one content sequence
    const inside = try t.render("<ul style=\"list-style-position:inside\"><li>inside</li></ul>", "{}");
    try testing.expect(!has(inside, "/S/Lbl"));
    try testing.expectEqual(@as(usize, 1), count(inside, "BDC"));
    // an item's own line: the text, then the marker's label
    const own = try t.render("<ul><li>out</li></ul>", "{}");
    try testing.expectEqual(@as(u8, 49), lblKid(own));
    // an item holding blocks: the label comes first
    const blocks = try t.render("<ul><li><p>one</p><p>two</p></li></ul>", "{}");
    try testing.expectEqual(@as(u8, 48), lblKid(blocks));
    const nested = try t.render("<ul><li>a<ul><li>a1</li></ul></li></ul>", "{}");
    try testing.expectEqual(@as(u8, 48), lblKid(nested));
    // a counter style takumi does not know: the numbering of the element (ol: decimal), and a
    // decimal marker when no font has the style's glyphs, not an uncovered-text failure
    const greek = try t.render("<ol style=\"list-style-type:lower-greek\"><li>g</li></ol>", "{}");
    try expectHas(greek, "/ListNumbering/Decimal");
    const geo = try t.render("<ol style=\"list-style-type:georgian\"><li>g</li></ol><ul style=\"list-style-type:georgian\"><li>g</li></ul>", "{}");
    try expectHas(geo, "/ListNumbering/Decimal");
    try expectHas(geo, "/ListNumbering/Disc");
}

/// The first kid (a marked-content id digit) of the first Lbl element.
fn lblKid(doc: []const u8) u8 {
    const at = std.mem.indexOf(u8, doc, "/S/Lbl") orelse return 0;
    const k = std.mem.indexOfPos(u8, doc, at, "/K[") orelse return 0;
    return doc[k + 3];
}

test "fonts: font-synthesis decides the synthetic bold stroke and the oblique skew" {
    if (comptime !config.enable_pdf) return;
    const t = try T.init();
    defer t.deinit();
    // (only Inter Regular is registered: bold is a stroke `2 Tr`, italic a skewed matrix)
    const skew = "-0.1875 -0.75";
    const both = try t.render("<p style=\"font-weight:700;font-style:italic\">x</p>", "{\"tagged\":false}");
    try testing.expect(has(both, "2 Tr") and has(both, skew));
    const off = try t.render("<p style=\"font-weight:700;font-style:italic;font-synthesis:none\">x</p>", "{\"tagged\":false}");
    try testing.expect(!has(off, "2 Tr") and !has(off, skew));
    const weight = try t.render("<p style=\"font-weight:700;font-style:italic;font-synthesis:weight\">x</p>", "{\"tagged\":false}");
    try testing.expect(has(weight, "2 Tr") and !has(weight, skew));
    const slant = try t.render("<p style=\"font-weight:700;font-style:italic;font-synthesis:style\">x</p>", "{\"tagged\":false}");
    try testing.expect(!has(slant, "2 Tr") and has(slant, skew));
}
