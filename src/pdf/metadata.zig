//! Document-level interchange data, as takumi-pdf writes it through its vendored krilla
//! (`interchange/metadata.rs`, `chunk_container.rs`, `serialize.rs`) and the `xmp-writer` crate:
//!
//! * the metadata krilla gets (`PdfMetadata::metadata`): present when the `metadata` option is set,
//!   or on tagged output with a `lang` (tagged standards check the document language); empty
//!   title / description / creator, and empty author / keyword lists, count as absent;
//! * the Info dictionary (`serialize_document_info`): /Producer always, then /Title /Subject
//!   (description) /Keywords (joined with ", ") /Author (joined with ", ") /Creator before PDF 2.0,
//!   /ModDate + /CreationDate from the creation date (full `D:YYYYMMDDHHmmSSZ`) in every version;
//! * the file /ID (`chunk_container.rs`): the document part is `stable_hash_base64(&(version, &title,
//!   &authors))` when the metadata has a title and authors, else the instance id;
//! * the XMP packet: written for every document (krilla's `xmp_metadata` is on by default), with
//!   xmp-writer's byte layout (namespaces in its `Namespace` order, each as ` xmlns:p="url" `);
//! * the catalog entries after /Pages and /Metadata, in krilla's order (`Catalog`).
//!
//! Extension points for the tagging / PDF/A wave: `Catalog` (struct tree root, mark info, output
//! intents, viewer preferences, an empty EmbeddedFiles tree), `Parts.info_dict`, `Parts.history`
//! (the file-provenance events PDF/A wants), `Parts.validators` (XMP written where krilla's
//! validators write theirs: pdfaid / pdfuaid / the extension-schema bag, with `Xmp.use` for their
//! namespaces).
const std = @import("std");
const w = @import("writer.zig");
const opt = @import("options.zig");

const Allocator = std.mem.Allocator;
const Ref = w.Ref;

/// The metadata krilla serializes (`krilla::metadata::Metadata`, the subset takumi fills).
pub const Metadata = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    creator: ?[]const u8 = null,
    /// non-empty when present
    keywords: ?[]const []const u8 = null,
    authors: ?[]const []const u8 = null,
    language: ?[]const u8 = null,
    creation_date: ?opt.PdfDate = null,
    custom_schemas: []const opt.XmpSchema = &.{},

    /// takumi `PdfMetadata::metadata` + krilla's setters (empty strings / lists are dropped).
    pub fn of(m: opt.Metadata, lang: []const u8) Metadata {
        const nonEmpty = struct {
            fn s(v: ?[]const u8) ?[]const u8 {
                const x = v orelse return null;
                return if (x.len > 0) x else null;
            }
            fn l(v: []const []const u8) ?[]const []const u8 {
                return if (v.len > 0) v else null;
            }
        };
        return .{
            .title = nonEmpty.s(m.title),
            .description = nonEmpty.s(m.description),
            .creator = nonEmpty.s(m.creator),
            .keywords = nonEmpty.l(m.keywords),
            .authors = nonEmpty.l(m.authors),
            .language = if (lang.len > 0) lang else null,
            .creation_date = m.creation_date,
            .custom_schemas = m.xmp,
        };
    }

    /// The document's metadata under `o` (takumi `open_document`): the `metadata` option, or an
    /// empty one carrying the language on tagged output with a `lang`; null otherwise.
    pub fn forOptions(o: *const opt.PdfOptions) ?Metadata {
        if (o.metadata) |m| return of(m, o.lang);
        if (o.writesStructure() and o.lang.len > 0) return of(.{}, o.lang);
        return null;
    }
};

pub fn versionString(v: w.Version) []const u8 {
    return switch (v) {
        .v1_4 => "1.4",
        .v1_5 => "1.5",
        .v1_6 => "1.6",
        .v1_7 => "1.7",
        .v2_0 => "2.0",
    };
}

/// krilla `pdf_date`: every field written, UTC.
pub fn pdfDate(d: opt.PdfDate) w.Date {
    return .{ .year = d.year, .month = d.month, .day = d.day, .hour = d.hour, .minute = d.minute, .second = d.second, .utc_offset_hour = 0, .utc_offset_minute = 0 };
}

/// The Info dictionary krilla writes for `m` (`serialize_document_info`).
pub fn info(m: ?*const Metadata, producer: []const u8, version: w.Version, a: Allocator) Allocator.Error!w.Info {
    var out: w.Info = .{};
    if (!version.atLeast(.v2_0)) {
        out.producer = producer;
        if (m) |md| {
            out.title = md.title;
            out.subject = md.description;
            if (md.keywords) |k| out.keywords = try std.mem.join(a, ", ", k);
            if (md.authors) |au| out.author = try std.mem.join(a, ", ", au);
            out.creator = md.creator;
        }
    }
    if (m) |md| if (md.creation_date) |d| {
        out.date = pdfDate(d);
    };
    return out;
}

/// The /ID document part krilla derives from the metadata (`chunk_container.rs`), or null for the
/// instance id. `out` receives the base64 text.
pub fn documentId(m: ?*const Metadata, version: w.Version, out: *[24]u8) ?[]const u8 {
    const md = m orelse return null;
    const title = md.title orelse return null;
    const authors = md.authors orelse return null;
    // Hash of the tuple `(&str, &Option<String>, &Option<Vec<String>>)`: `str` = bytes + 0xFF,
    // `Option` = discriminant (as u64) + value, `Vec` = length (u64) + items.
    var h = w.StableHasher.init();
    // krilla `PdfVersion::as_str`: "PDF 1.7"
    var vb: [8]u8 = undefined;
    h.str(std.fmt.bufPrint(&vb, "PDF {s}", .{versionString(version)}) catch unreachable);
    h.u64_(1);
    h.str(title);
    h.u64_(1);
    h.u64_(authors.len);
    for (authors) |au| h.str(au);
    return h.finalBase64(out);
}

// ---------------------------------------------------------------------------------------------
// XMP (xmp-writer 0.3 byte layout)
// ---------------------------------------------------------------------------------------------

/// xmp-writer's built-in namespaces this crate writes, in its `Namespace` order (the order the
/// packet declares them in). Custom namespaces follow, ordered by (name, prefix, url).
pub const Ns = enum(u8) {
    dc,
    xmp,
    stEvt,
    xmpMM,
    xmpTPg,
    pdf,
    pdfaid,
    pdfuaid,
    pdfaExtension,
    pdfaSchema,
    pdfaProperty,

    pub fn url(n: Ns) []const u8 {
        return switch (n) {
            .dc => "http://purl.org/dc/elements/1.1/",
            .xmp => "http://ns.adobe.com/xap/1.0/",
            .stEvt => "http://ns.adobe.com/xap/1.0/sType/ResourceEvent#",
            .xmpMM => "http://ns.adobe.com/xap/1.0/mm/",
            .xmpTPg => "http://ns.adobe.com/xap/1.0/t/pg/",
            .pdf => "http://ns.adobe.com/pdf/1.3/",
            .pdfaid => "http://www.aiim.org/pdfa/ns/id/",
            .pdfuaid => "http://www.aiim.org/pdfua/ns/id/",
            .pdfaExtension => "http://www.aiim.org/pdfa/ns/extension/",
            .pdfaSchema => "http://www.aiim.org/pdfa/ns/schema#",
            .pdfaProperty => "http://www.aiim.org/pdfa/ns/property#",
        };
    }
};

const ns_count = @typeInfo(Ns).@"enum".field_names.len;

const CustomNs = struct { name: []const u8, prefix: []const u8, url: []const u8 };

/// An XMP packet under construction: elements appended in call order, namespaces collected.
pub const Xmp = struct {
    a: Allocator,
    body: std.ArrayList(u8) = .empty,
    used: [ns_count]bool = @splat(false),
    custom: std.ArrayList(CustomNs) = .empty,

    pub fn init(a: Allocator) Xmp {
        return .{ .a = a };
    }

    /// Declares a built-in namespace (elements written with `raw` must declare theirs).
    pub fn use(x: *Xmp, n: Ns) void {
        x.used[@intFromEnum(n)] = true;
    }

    pub fn useCustom(x: *Xmp, name: []const u8, prefix: []const u8, url: []const u8) Allocator.Error!void {
        for (x.custom.items) |c| {
            if (std.mem.eql(u8, c.name, name) and std.mem.eql(u8, c.prefix, prefix) and std.mem.eql(u8, c.url, url)) return;
        }
        try x.custom.append(x.a, .{ .name = name, .prefix = prefix, .url = url });
    }

    pub fn raw(x: *Xmp, s: []const u8) Allocator.Error!void {
        try x.body.appendSlice(x.a, s);
    }

    /// Escaped text (xmp-writer `XmpType for &str`).
    pub fn text(x: *Xmp, s: []const u8) Allocator.Error!void {
        for (s) |c| switch (c) {
            '<' => try x.raw("&lt;"),
            '>' => try x.raw("&gt;"),
            '&' => try x.raw("&amp;"),
            '\'' => try x.raw("&apos;"),
            '"' => try x.raw("&quot;"),
            else => try x.body.append(x.a, c),
        };
    }

    fn open(x: *Xmp, prefix: []const u8, name: []const u8) Allocator.Error!void {
        try x.raw("<");
        try x.raw(prefix);
        try x.raw(":");
        try x.raw(name);
        try x.raw(">");
    }

    fn close(x: *Xmp, prefix: []const u8, name: []const u8) Allocator.Error!void {
        try x.raw("</");
        try x.raw(prefix);
        try x.raw(":");
        try x.raw(name);
        try x.raw(">");
    }

    /// `<p:name>value</p:name>`
    pub fn element(x: *Xmp, n: Ns, name: []const u8, value: []const u8) Allocator.Error!void {
        x.use(n);
        try x.open(@tagName(n), name);
        try x.text(value);
        try x.close(@tagName(n), name);
    }

    /// A custom-namespace element.
    pub fn customElement(x: *Xmp, prefix: []const u8, name: []const u8, value: []const u8) Allocator.Error!void {
        try x.open(prefix, name);
        try x.text(value);
        try x.close(prefix, name);
    }

    /// `<p:name><rdf:Alt><rdf:li xml:lang="x-default">value</rdf:li></rdf:Alt></p:name>`
    pub fn langAlt(x: *Xmp, n: Ns, name: []const u8, value: []const u8) Allocator.Error!void {
        x.use(n);
        try x.open(@tagName(n), name);
        try x.raw("<rdf:Alt><rdf:li xml:lang=\"x-default\">");
        try x.text(value);
        try x.raw("</rdf:li></rdf:Alt>");
        try x.close(@tagName(n), name);
    }

    /// An ordered (`Seq`) or unordered (`Bag`) array of texts.
    pub fn array(x: *Xmp, n: Ns, name: []const u8, kind: []const u8, items: []const []const u8) Allocator.Error!void {
        x.use(n);
        try x.open(@tagName(n), name);
        try x.raw("<rdf:");
        try x.raw(kind);
        try x.raw(">");
        for (items) |it| {
            try x.raw("<rdf:li>");
            try x.text(it);
            try x.raw("</rdf:li>");
        }
        try x.raw("</rdf:");
        try x.raw(kind);
        try x.raw(">");
        try x.close(@tagName(n), name);
    }

    /// xmp-writer `DateTime` (every field present, UTC offset 0: `+00:00`).
    pub fn date(x: *Xmp, n: Ns, name: []const u8, d: opt.PdfDate) Allocator.Error!void {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}+00:00", .{ d.year, d.month, d.day, d.hour, d.minute, d.second }) catch unreachable;
        try x.element(n, name, s);
    }

    /// xmp-writer `finish(None)`.
    pub fn finish(x: *Xmp) Allocator.Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        const a = x.a;
        try out.appendSlice(a, "<?xpacket begin=\"\xEF\xBB\xBF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?><x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"xmp-writer\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\"");
        for (x.used, 0..) |u, k| {
            if (!u) continue;
            const n: Ns = @enumFromInt(k);
            try out.appendSlice(a, " xmlns:");
            try out.appendSlice(a, @tagName(n));
            try out.appendSlice(a, "=\"");
            try out.appendSlice(a, n.url());
            try out.appendSlice(a, "\" ");
        }
        const cs = try a.dupe(CustomNs, x.custom.items);
        std.mem.sort(CustomNs, cs, {}, struct {
            fn lt(_: void, p: CustomNs, q: CustomNs) bool {
                inline for (.{ "name", "prefix", "url" }) |fld| {
                    switch (std.mem.order(u8, @field(p, fld), @field(q, fld))) {
                        .lt => return true,
                        .gt => return false,
                        .eq => {},
                    }
                }
                return false;
            }
        }.lt);
        for (cs) |c| {
            try out.appendSlice(a, " xmlns:");
            try out.appendSlice(a, c.prefix);
            try out.appendSlice(a, "=\"");
            try out.appendSlice(a, c.url);
            try out.appendSlice(a, "\" ");
        }
        try out.append(a, '>');
        try out.appendSlice(a, x.body.items);
        try out.appendSlice(a, "</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end=\"r\"?>");
        return out.items;
    }
};

/// Writes XMP into `x` where krilla's validators write theirs (`validators.write_xmp`).
pub const XmpHook = struct {
    ctx: *anyopaque,
    run: *const fn (ctx: *anyopaque, x: *Xmp, m: ?*const Metadata) Allocator.Error!void,
};

/// What the document-level pass writes, beyond the pages. Filled by `writeDocument` (and by the
/// tagging / PDF/A wave through its hook) before `finish`.
pub const Parts = struct {
    metadata: ?Metadata = null,
    producer: []const u8 = "bm-render",
    /// krilla writes no Info dictionary when a validator prohibits one (PDF/A-4).
    info_dict: bool = true,
    /// PDF/A's file-provenance `xmpMM:History` (saved + converted events at the creation date).
    history: bool = false,
    /// the history events name `<instance id>_source` (all but PDF/A-4).
    history_instance_ids: bool = true,
    validators: ?XmpHook = null,
    catalog: Catalog = .{},
};

/// The packet krilla writes (`serialize_xmp_metadata` + `chunk_container.rs`).
pub fn xmpPacket(a: Allocator, p: *const Parts, version: w.Version, pages: usize, instance_id: []const u8, document_id: []const u8) Allocator.Error![]const u8 {
    var x = Xmp.init(a);
    const m: ?*const Metadata = if (p.metadata) |*md| md else null;
    if (m) |md| {
        if (md.title) |t| try x.langAlt(.dc, "title", t);
        if (md.description) |d| try x.langAlt(.dc, "description", d);
        if (md.keywords) |k| try x.element(.pdf, "Keywords", try std.mem.join(a, ", ", k));
        if (md.authors) |au| {
            if (version.atLeast(.v2_0)) {
                try x.array(.dc, "creator", "Seq", au);
            } else {
                try x.array(.dc, "creator", "Seq", &.{try std.mem.join(a, ", ", au)});
            }
        }
        if (md.creator) |c| try x.element(.xmp, "CreatorTool", c);
        if (md.language) |l| try x.array(.dc, "language", "Bag", &.{l});
        if (md.creation_date) |d| {
            try x.date(.xmp, "ModifyDate", d);
            try x.date(.xmp, "CreateDate", d);
            if (p.history) try history(&x, d, md.creator, instance_id, p.history_instance_ids);
        }
    }
    if (p.validators) |v| try v.run(v.ctx, &x, m);
    if (m) |md| for (md.custom_schemas) |s| {
        if (s.properties.len > 0) try x.useCustom(s.name, s.prefix, s.namespace);
        for (s.properties) |prop| try x.customElement(s.prefix, prop.name, prop.value);
    };
    try x.element(.pdf, "Producer", p.producer);
    var nb: [24]u8 = undefined;
    try x.element(.xmpTPg, "NPages", w.fmtInt(&nb, @intCast(pages)));
    try x.element(.dc, "format", "application/pdf");
    try x.element(.xmpMM, "InstanceID", instance_id);
    try x.element(.xmpMM, "DocumentID", document_id);
    try x.element(.xmpMM, "RenditionClass", "proof");
    try x.element(.pdf, "PDFVersion", versionString(version));
    return x.finish();
}

fn history(x: *Xmp, d: opt.PdfDate, creator: ?[]const u8, instance_id: []const u8, ids: bool) Allocator.Error!void {
    x.use(.xmpMM);
    x.use(.stEvt);
    try x.raw("<xmpMM:History><rdf:Seq>");
    var buf: [32]u8 = undefined;
    const when = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}+00:00", .{ d.year, d.month, d.day, d.hour, d.minute, d.second }) catch unreachable;
    for ([_][]const u8{ "saved", "converted" }) |action| {
        try x.raw("<rdf:li rdf:parseType=\"Resource\"><stEvt:action>");
        try x.raw(action);
        try x.raw("</stEvt:action><stEvt:when>");
        try x.raw(when);
        try x.raw("</stEvt:when>");
        if (action[0] == 'c') if (creator) |c| {
            try x.raw("<stEvt:softwareAgent>");
            try x.text(c);
            try x.raw("</stEvt:softwareAgent>");
        };
        if (ids) {
            try x.raw("<stEvt:instanceID>");
            try x.text(instance_id);
            try x.raw("_source</stEvt:instanceID>");
        }
        try x.raw("</rdf:li>");
    }
    try x.raw("</rdf:Seq></xmpMM:History>");
}

// ---------------------------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------------------------

/// A name-tree entry (`(name) ref`).
pub const NameRef = struct { name: []const u8, ref: Ref };

/// The catalog entries after /Pages and /Metadata, written in krilla's order
/// (`chunk_container.rs`): PageLabels, OutputIntents, Lang, StructTreeRoot + MarkInfo,
/// ViewerPreferences, Outlines, Names (Dests, EmbeddedFiles), AF.
pub const Catalog = struct {
    page_labels: ?Ref = null,
    output_intents: ?Ref = null,
    lang: ?[]const u8 = null,
    struct_tree_root: ?Ref = null,
    /// with a struct tree root: `/Suspects false` too (PDF 1.6 up to 2.0)
    mark_info_suspects: bool = false,
    display_doc_title: bool = false,
    outlines: ?Ref = null,
    /// named destinations, sorted by name (krilla); takumi uses none
    dests: []const NameRef = &.{},
    /// sorted by name; written when non-empty or `embedded_files_when_empty` (PDF/A-1..3)
    embedded_files: []const NameRef = &.{},
    embedded_files_when_empty: bool = false,
    /// associated files (PDF/A-3, PDF 2.0)
    af: []const Ref = &.{},
};

pub fn writeCatalog(d: *w.Doc, c: *const Catalog) void {
    const b = d.beginCatalog();
    if (c.page_labels) |r| b.pairRef("PageLabels", r);
    if (c.output_intents) |r| b.pairRef("OutputIntents", r);
    if (c.lang) |l| b.pairText("Lang", l);
    if (c.struct_tree_root) |r| {
        b.pairRef("StructTreeRoot", r);
        b.raw("/MarkInfo<</Marked true");
        if (c.mark_info_suspects) b.raw("/Suspects false");
        b.raw(">>");
    }
    if (c.display_doc_title) b.raw("/ViewerPreferences<</DisplayDocTitle true>>");
    if (c.outlines) |r| b.pairRef("Outlines", r);
    const files = c.embedded_files.len > 0 or c.embedded_files_when_empty;
    if (c.dests.len > 0 or files) {
        b.raw("/Names<<");
        if (c.dests.len > 0) {
            b.raw("/Dests<</Names[");
            for (c.dests) |e| {
                b.str(e.name);
                b.ref(e.ref);
            }
            b.raw("]>>");
        }
        if (files) {
            b.raw("/EmbeddedFiles<</Names[");
            for (c.embedded_files) |e| {
                b.str(e.name);
                b.ref(e.ref);
            }
            b.raw("]>>");
        }
        b.raw(">>");
    }
    if (c.af.len > 0) {
        b.key("AF");
        b.refs(c.af);
    }
    d.endCatalog();
}

/// Writer callback context for the XMP packet.
pub const XmpCtx = struct {
    parts: *const Parts,
    version: w.Version,
    pages: usize,

    pub fn callback(ctx: ?*anyopaque, a: Allocator, instance_id: []const u8, document_id: []const u8) error{OutOfMemory}![]const u8 {
        const self: *const XmpCtx = @ptrCast(@alignCast(ctx.?));
        return xmpPacket(a, self.parts, self.version, self.pages, instance_id, document_id);
    }
};

/// Writes the catalog entries and the file (Info, XMP, /ID). `id_buf` must outlive the call.
pub fn finish(d: *w.Doc, out: *std.ArrayList(u8), p: *const Parts) w.Error!void {
    writeCatalog(d, &p.catalog);
    const m: ?*const Metadata = if (p.metadata) |*md| md else null;
    var id_buf: [24]u8 = undefined;
    const doc_id = documentId(m, d.version, &id_buf);
    var xc: XmpCtx = .{ .parts = p, .version = d.version, .pages = d.pageCount() };
    const inf = try info(m, p.producer, d.version, d.a);
    try d.finish(out, .{
        .info = if (p.info_dict) inf else null,
        .xmp = XmpCtx.callback,
        .xmp_ctx = &xc,
        .document_id = doc_id,
    });
}

// ---------------------------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------------------------

const testing = std.testing;

test "document id from title and authors (takumi report-links-outline fixture)" {
    var buf: [24]u8 = undefined;
    const m: Metadata = .{ .title = "Annual report", .authors = &.{"Takumi"} };
    try testing.expectEqualStrings("NWHraa8Gm0G8dQP4RQYw2w==", documentId(&m, .v1_7, &buf).?);
    const no_authors: Metadata = .{ .title = "Annual report" };
    try testing.expect(documentId(&no_authors, .v1_7, &buf) == null);
}

test "xmp packet layout (takumi box-chrome / invoice fixtures)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bare: Parts = .{ .producer = "takumi-pdf fixture" };
    try testing.expectEqualStrings("<?xpacket begin=\"\xEF\xBB\xBF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?><x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"xmp-writer\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"  xmlns:xmpMM=\"http://ns.adobe.com/xap/1.0/mm/\"  xmlns:xmpTPg=\"http://ns.adobe.com/xap/1.0/t/pg/\"  xmlns:pdf=\"http://ns.adobe.com/pdf/1.3/\" ><pdf:Producer>takumi-pdf fixture</pdf:Producer><xmpTPg:NPages>1</xmpTPg:NPages><dc:format>application/pdf</dc:format><xmpMM:InstanceID>gKfRILKOMza1v7WKPelccQ==</xmpMM:InstanceID><xmpMM:DocumentID>gKfRILKOMza1v7WKPelccQ==</xmpMM:DocumentID><xmpMM:RenditionClass>proof</xmpMM:RenditionClass><pdf:PDFVersion>1.7</pdf:PDFVersion></rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end=\"r\"?>", try xmpPacket(a, &bare, .v1_7, 1, "gKfRILKOMza1v7WKPelccQ==", "gKfRILKOMza1v7WKPelccQ=="));
    const fx: opt.XmpSchema = .{ .name = "Factur-X PDF/A Extension", .prefix = "fx", .namespace = "urn:x#", .properties = &.{.{ .name = "DocumentFileName", .value = "a&b.xml", .description = "d" }} };
    const full: Parts = .{ .producer = "p", .metadata = .{ .title = "T<", .description = "D", .keywords = &.{ "a", "b" }, .authors = &.{ "X", "Y" }, .creator = "C", .language = "en", .creation_date = .{ .year = 2026, .month = 8, .day = 6 }, .custom_schemas = &.{fx} } };
    const s = try xmpPacket(a, &full, .v1_7, 3, "I", "D");
    try testing.expect(std.mem.indexOf(u8, s, "rdf:about=\"\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"  xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"  xmlns:xmpMM=") != null);
    try testing.expect(std.mem.indexOf(u8, s, "xmlns:pdf=\"http://ns.adobe.com/pdf/1.3/\"  xmlns:fx=\"urn:x#\" >") != null);
    try testing.expect(std.mem.indexOf(u8, s, "><dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">T&lt;</rdf:li></rdf:Alt></dc:title><dc:description><rdf:Alt><rdf:li xml:lang=\"x-default\">D</rdf:li></rdf:Alt></dc:description><pdf:Keywords>a, b</pdf:Keywords><dc:creator><rdf:Seq><rdf:li>X, Y</rdf:li></rdf:Seq></dc:creator><xmp:CreatorTool>C</xmp:CreatorTool><dc:language><rdf:Bag><rdf:li>en</rdf:li></rdf:Bag></dc:language><xmp:ModifyDate>2026-08-06T00:00:00+00:00</xmp:ModifyDate><xmp:CreateDate>2026-08-06T00:00:00+00:00</xmp:CreateDate><fx:DocumentFileName>a&amp;b.xml</fx:DocumentFileName><pdf:Producer>p</pdf:Producer><xmpTPg:NPages>3</xmpTPg:NPages>") != null);
}

test "info dictionary entries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const m = Metadata.of(.{ .title = "", .authors = &.{ "A", "B" }, .keywords = &.{"k"}, .creation_date = .{ .year = 2026, .month = 1, .day = 2, .hour = 3 } }, "");
    try testing.expect(m.title == null and m.language == null);
    const i = try info(&m, "bm-render", .v1_7, arena.allocator());
    try testing.expectEqualStrings("A, B", i.author.?);
    try testing.expectEqual(@as(?i8, 0), i.date.?.utc_offset_hour);
    const info2 = try info(&m, "bm-render", .v2_0, arena.allocator());
    try testing.expect(info2.producer == null and info2.date != null);
}
