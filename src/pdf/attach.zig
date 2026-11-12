//! File attachments, as takumi-pdf embeds them through krilla (`options.rs`
//! `Attachment::embedded_file`, `krilla/interchange/embed.rs`, `serialize.rs::embed_file`,
//! `chunk_container.rs`):
//!
//! * per attachment, in option order: a file specification (`.embedded_files`:
//!   `<</Type/Filespec/F(name)/UF(name)/EF<</F s/UF s>>[/AFRelationship/X]/Desc(..)>>`; /UF from
//!   PDF 1.7, /AFRelationship when associated files are supported) and its stream
//!   (`.embedded_file_streams`: `<</Length/Type/EmbeddedFile[/Filter]/Subtype/<mime>/Params<</Size
//!   n[/ModDate]>>>>`, Flate only when it saves more than a quarter); the modification date falls
//!   back to `metadata.creationDate`;
//! * the catalog's EmbeddedFiles name tree and /AF array list them sorted by name (krilla keeps a
//!   `BTreeMap`); /AF only when associated files are supported (PDF/A-3, PDF 2.0).
const std = @import("std");
const w = @import("writer.zig");
const opt = @import("options.zig");
const meta = @import("metadata.zig");

const Allocator = std.mem.Allocator;

/// What the catalog needs from the attachments.
pub const Written = struct {
    /// by name
    names: []const meta.NameRef = &.{},
    /// the /AF array (empty when associated files are not supported)
    af: []const w.Ref = &.{},
};

/// Whether the document supports associated files (krilla `supports_associated_files`: PDF 2.0,
/// or a PDF/A-3 validator).
pub fn associatedFiles(o: *const opt.PdfOptions, version: w.Version) bool {
    if (version.atLeast(.v2_0)) return true;
    return switch (o.pdfa) {
        .a3a, .a3b, .a3u, .a4, .a4f => true,
        else => false,
    };
}

fn relationshipName(r: opt.Relationship) []const u8 {
    return switch (r) {
        .source => "Source",
        .data => "Data",
        .alternative => "Alternative",
        .supplement => "Supplement",
        .unspecified => "Unspecified",
    };
}

/// Writes every attachment of `o`. The names are unique (options.zig rejects duplicates).
pub fn write(d: *w.Doc, a: Allocator, o: *const opt.PdfOptions) Allocator.Error!Written {
    if (o.attachments.len == 0) return .{};
    const associated = associatedFiles(o, d.version);
    const fallback: ?opt.PdfDate = if (o.metadata) |m| m.creation_date else null;
    const names = try a.alloc(meta.NameRef, o.attachments.len);
    for (o.attachments, names) |at, *nr| {
        const spec = d.alloc();
        const stream = d.alloc();
        // the stream (krilla `FilterStreamBuilder::new_auto_compressed`)
        const e = d.encode(at.data, .auto);
        const sb = d.beginStream(stream, .embedded_file_streams, e);
        sb.pairName("Type", "EmbeddedFile");
        sb.filter(e);
        if (at.mime_type) |mt| sb.pairName("Subtype", mt);
        sb.raw("/Params<<");
        sb.pairInt("Size", @intCast(at.data.len));
        if (at.modification_date orelse fallback) |dt| sb.pairDate("ModDate", meta.pdfDate(dt));
        sb.raw(">>");
        d.endDict();
        // the file specification
        const b = d.beginDict(spec, .embedded_files);
        b.pairName("Type", "Filespec");
        b.pairStr("F", at.name);
        const v17 = d.version.atLeast(.v1_7);
        if (v17) b.pairText("UF", at.name);
        b.raw("/EF<<");
        b.pairRef("F", stream);
        if (v17) b.pairRef("UF", stream);
        b.raw(">>");
        if (associated) b.pairName("AFRelationship", relationshipName(at.relationship));
        if (at.description) |desc| b.pairText("Desc", desc);
        d.endDict();
        nr.* = .{ .name = at.name, .ref = spec };
    }
    std.mem.sort(meta.NameRef, names, {}, struct {
        fn lt(_: void, x: meta.NameRef, y: meta.NameRef) bool {
            return std.mem.order(u8, x.name, y.name) == .lt;
        }
    }.lt);
    var af: []w.Ref = &.{};
    if (associated) {
        af = try a.alloc(w.Ref, names.len);
        for (names, af) |n, *r| r.* = n.ref;
    }
    return .{ .names = names, .af = af };
}

test "attachments: file spec, stream, name order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = w.Doc.init(a, .{ .compress = false });
    const p = d.addPage();
    const c = d.alloc();
    d.contentStream(c, "");
    _ = d.beginPage(p, .{ .resources = null, .media_box = .{ 0, 0, 10, 10 }, .contents = c });
    d.endDict();
    const o: opt.PdfOptions = .{
        .pdfa = .a3b,
        .metadata = .{ .creation_date = .{ .year = 2026, .month = 8, .day = 6 } },
        .attachments = &.{
            .{ .name = "z.xml", .data = "<invoice total=\"1290\"/>", .mime_type = "application/xml", .description = "Factur-X invoice data", .relationship = .alternative },
            .{ .name = "a.bin", .data = "\x00\x01" },
        },
    };
    const wr = try write(&d, a, &o);
    try std.testing.expectEqualStrings("a.bin", wr.names[0].name);
    try std.testing.expectEqual(@as(usize, 2), wr.af.len);
    var parts: meta.Parts = .{};
    parts.catalog.embedded_files = wr.names;
    parts.catalog.af = wr.af;
    var out: std.ArrayList(u8) = .empty;
    try meta.finish(&d, &out, &parts);
    const s = out.items;
    const has = struct {
        fn f(hay: []const u8, n: []const u8) !void {
            if (std.mem.indexOf(u8, hay, n) == null) {
                std.debug.print("missing {s}\n", .{n});
                return error.TestUnexpectedResult;
            }
        }
    }.f;
    try has(s, "<</Type/Filespec/F(z.xml)/UF(z.xml)/EF<</F 6 0 R/UF 6 0 R>>/AFRelationship/Alternative/Desc(Factur-X invoice data)>>");
    try has(s, "<</Length 23/Type/EmbeddedFile/Subtype/application#2Fxml/Params<</Size 23/ModDate(D:20260806000000Z)>>>>\nstream\n<invoice total=\"1290\"/>");
    try has(s, "<</Type/Filespec/F(a.bin)/UF(a.bin)/EF<</F 7 0 R/UF 7 0 R>>/AFRelationship/Unspecified>>");
    try has(s, "/Names<</EmbeddedFiles<</Names[(a.bin)4 0 R(z.xml)3 0 R]>>>>/AF[4 0 R 3 0 R]>>");
}
