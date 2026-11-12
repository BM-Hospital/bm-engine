//! PDF/A and PDF/UA conformance (krilla `configure/{mod,validate,version}.rs`, `graphics/icc.rs`,
//! the validator calls of `chunk_container.rs`, `serialize.rs`, `metadata.rs`, `embed.rs`,
//! `annotation.rs`, `cid.rs`, `shading_function.rs`, and takumi-pdf `lib.rs::open_document`):
//!
//! * `Config.of`: the validators the options ask for (`pdfa` -> an archival validator, `tagged:
//!   "ua1" | "ua2"` -> an accessibility validator) and the PDF version: the highest version every
//!   validator accepts (A-2/3 and UA-1: 1.7; A-4 and UA-2: 2.0; none: 1.7). Validators without a
//!   common version fail the render as takumi does (`PdfError::InvalidStandard`);
//! * what the validators change in the output: tagging forced (A-2a/3a, UA), ICC-based sRGB
//!   instead of DeviceRGB plus the sRGB OutputIntent (every PDF/A level), no Info dictionary
//!   (A-4), the xmpMM:History events, the pdfaid / pdfuaid XMP properties and the extension
//!   schema bag (A-2/3, or custom schemas), /DisplayDocTitle (UA), an empty EmbeddedFiles tree
//!   (A-4f), /Tabs /S on every page (UA, A-2a/3a);
//! * `Report`: the violations krilla records (deduplicated like krilla's list); a non-empty list
//!   fails the render with takumi's message `Writing the PDF failed: validation failed with N
//!   error(s)` (krilla `KrillaError::Validation` through `PdfError::Krilla`).
//!
//! The sRGB profile (`srgb-v4.icc`, 480 bytes) is krilla's `icc/sRGB-v4.icc`, the "Compact ICC
//! Profiles" sRGB v4 profile by Clinton Ingram (saucecontrol), released under CC0 1.0 (its `cprt`
//! tag reads "CC0"); the bytes were taken from takumi's PDF/A goldens.
const std = @import("std");
const w = @import("writer.zig");
const opt = @import("options.zig");
const meta = @import("metadata.zig");
const sf = @import("emit_surface.zig");

const Allocator = std.mem.Allocator;
const Ref = w.Ref;

pub const srgb_v4 = @embedFile("srgb-v4.icc");

pub const Ua = enum { ua1, ua2 };

/// The krilla validation errors bm-engine can raise.
pub const Err = enum {
    contains_post_script,
    contains_notdef,
    no_codepoint_mapping,
    invalid_codepoint_mapping,
    private_use,
    restricted_license,
    no_document_language,
    no_document_title,
    missing_alt_text,
    missing_heading_title,
    missing_document_outline,
    missing_annotation_alt,
    missing_document_date,
    embedded_existence,
    embedded_missing_date,
    embedded_missing_description,
    embedded_missing_mime,
    missing_tagging,
    too_long_string,
    too_long_name,
    too_many_indirect_objects,
    too_high_q_nesting,
};

pub const Config = struct {
    a: opt.Pdfa = .none,
    ua: ?Ua = null,
    version: w.Version = .v1_7,

    fn maxOfA(p: opt.Pdfa) w.Version {
        return if (p.isPdf2()) .v2_0 else .v1_7;
    }

    /// krilla `ConfigurationBuilder::finish` for takumi's `open_document`; null: the validators
    /// share no PDF version (`PdfError::InvalidStandard`).
    pub fn of(o: *const opt.PdfOptions) ?Config {
        var c: Config = .{ .a = o.pdfa };
        c.ua = switch (o.tagged) {
            .ua1 => .ua1,
            .ua2 => .ua2,
            else => null,
        };
        var min: w.Version = .v1_4;
        var max: w.Version = .v2_0;
        if (c.a != .none) {
            if (c.a.isPdf2()) min = .v2_0;
            max = maxOfA(c.a);
        }
        if (c.ua) |u| {
            if (u == .ua2 and @intFromEnum(min) < @intFromEnum(w.Version.v2_0)) min = .v2_0;
            const um: w.Version = if (u == .ua1) .v1_7 else .v2_0;
            if (@intFromEnum(um) < @intFromEnum(max)) max = um;
        }
        if (@intFromEnum(min) > @intFromEnum(max)) return null;
        c.version = if (c.a == .none and c.ua == null) .v1_7 else max;
        return c;
    }

    pub fn archival(c: Config) bool {
        return c.a != .none;
    }

    pub fn requiresTagging(c: Config) bool {
        return c.ua != null or c.a.requiresTagging();
    }

    fn a23(c: Config) bool {
        return c.a != .none and !c.a.isPdf2();
    }

    /// `requires_xmp_metadata_extension_schema`
    pub fn extensionSchema(c: Config) bool {
        return c.a23();
    }

    /// `prohibits_info_dict`
    pub fn prohibitsInfo(c: Config) bool {
        return c.a.isPdf2();
    }

    /// `requires_embedded_files_when_empty`
    pub fn embeddedFilesWhenEmpty(c: Config) bool {
        return c.a == .a4f;
    }

    /// `requires_display_doc_title`
    pub fn displayDocTitle(c: Config) bool {
        return c.ua != null;
    }

    /// krilla `page.rs`: `/Tabs /S` on every page when an accessibility validator, or one that
    /// requires tagging, is set (else only on pages with annotations).
    pub fn tabsEveryPage(c: Config) bool {
        return c.ua != null or c.a.requiresTagging();
    }

    /// The standard that forbids the `.notdef` placeholder (takumi `forbids_placeholder`).
    pub fn forbidsPlaceholder(c: Config) ?[]const u8 {
        if (c.a != .none) return c.a.label();
        if (c.ua) |u| return if (u == .ua1) "PDF/UA-1" else "PDF/UA-2";
        return null;
    }

    fn aProhibits(p: opt.Pdfa, e: Err) bool {
        const is_a = p == .a2a or p == .a3a;
        const is_u = p == .a2u or p == .a3u;
        if (p.isPdf2()) return switch (e) {
            .contains_notdef, .no_codepoint_mapping, .invalid_codepoint_mapping, .private_use, .restricted_license, .missing_document_date => true,
            .embedded_existence, .embedded_missing_description => p == .a4,
            else => false,
        };
        const a2 = p == .a2a or p == .a2b or p == .a2u;
        return switch (e) {
            .contains_post_script, .contains_notdef, .restricted_license, .missing_document_date => true,
            .too_long_string, .too_long_name, .too_many_indirect_objects, .too_high_q_nesting => true,
            .embedded_existence => a2,
            .embedded_missing_date, .embedded_missing_description, .embedded_missing_mime => !a2,
            .private_use, .no_document_language, .missing_alt_text, .missing_annotation_alt, .missing_tagging => is_a,
            .no_codepoint_mapping, .invalid_codepoint_mapping => is_a or is_u,
            else => false,
        };
    }

    fn uaProhibits(u: Ua, e: Err) bool {
        if (u == .ua2 and e == .no_document_language) return true;
        return switch (e) {
            .contains_notdef, .no_codepoint_mapping, .invalid_codepoint_mapping, .restricted_license, .no_document_title, .missing_alt_text, .missing_heading_title, .missing_document_outline, .missing_annotation_alt, .embedded_missing_description, .missing_tagging => true,
            else => false,
        };
    }

    /// krilla `Validators::prohibits`.
    pub fn prohibits(c: Config, e: Err) bool {
        if (c.a != .none and aProhibits(c.a, e)) return true;
        if (c.ua) |u| if (uaProhibits(u, e)) return true;
        return false;
    }
};

/// The recorded violations (krilla `validation_errors`, deduplicated by value: `key` stands for
/// the font / glyph / text a variant carries).
pub const Report = struct {
    a: Allocator,
    cfg: Config,
    list: std.ArrayList(struct { e: Err, key: u64 }) = .empty,
    failed: bool = false,

    pub fn add(r: *Report, e: Err, key: u64) void {
        if (!r.cfg.prohibits(e)) return;
        for (r.list.items) |it| if (it.e == e and it.key == key) return;
        r.list.append(r.a, .{ .e = e, .key = key }) catch {
            r.failed = true;
        };
    }

    /// takumi's message, or null when the document conforms.
    pub fn message(r: *const Report, a: Allocator) Allocator.Error!?[]const u8 {
        const n = r.list.items.len;
        if (n == 0) return null;
        return try std.fmt.allocPrint(a, "Writing the PDF failed: validation failed with {d} {s}", .{ n, if (n == 1) "error" else "errors" });
    }
};

// ---------------------------------------------------------------------------------------------
// Colour: the ICC-based sRGB space and the output intent (krilla `color.rs`, `icc.rs`)
// ---------------------------------------------------------------------------------------------

/// The ICC profile stream (`<</Length/N 3/Range[0 1 0 1 0 1]/Filter>>`, category `icc_profiles`).
pub fn profileRef(cx: *sf.Ctx) Ref {
    if (cx.icc_profile) |r| return r;
    const d = cx.doc;
    const r = d.alloc();
    const e = d.encode(srgb_v4, .flate);
    const b = d.beginStream(r, .icc_profiles, e);
    b.pairInt("N", 3);
    b.raw("/Range[0 1 0 1 0 1]");
    b.filter(e);
    d.endDict();
    cx.icc_profile = r;
    return r;
}

/// The `[/ICCBased profile]` colour space (category `color_spaces`), or null when device colour
/// spaces are allowed.
pub fn rgbSpace(cx: *sf.Ctx) ?Ref {
    if (!cx.no_device_cs) return null;
    if (cx.icc_rgb) |r| return r;
    const d = cx.doc;
    const r = d.alloc();
    const p = profileRef(cx);
    const b = d.begin(r, .color_spaces);
    b.arr();
    b.name("ICCBased");
    b.ref(p);
    b.arrEnd();
    d.end();
    cx.icc_rgb = r;
    return r;
}

/// The OutputIntents array krilla writes for a PDF/A document (`serialize_destination_profiles`).
pub fn outputIntents(cx: *sf.Ctx) Ref {
    const d = cx.doc;
    const intent = d.alloc();
    const arr = d.alloc();
    const p = profileRef(cx);
    {
        const b = d.beginDict(intent, .destination_profiles);
        b.pairName("Type", "OutputIntent");
        b.pairRef("DestOutputProfile", p);
        b.pairName("S", "GTS_PDFA1");
        b.pairText("OutputConditionIdentifier", "Custom");
        b.pairText("OutputCondition", "sRGB");
        b.pairText("RegistryName", "");
        b.pairText("Info", "sRGB v4.2");
        d.endDict();
    }
    const b = d.begin(arr, .destination_profiles);
    b.arr();
    b.ref(intent);
    b.arrEnd();
    d.end();
    return arr;
}

// ---------------------------------------------------------------------------------------------
// XMP (krilla `Validators::write_xmp`, xmp-writer's PDF/A extension schema writer)
// ---------------------------------------------------------------------------------------------

pub const XmpCtx = struct {
    cfg: Config,

    pub fn hook(x: *XmpCtx) meta.XmpHook {
        return .{ .ctx = x, .run = run };
    }

    fn property(xm: *meta.Xmp, category: []const u8, description: []const u8, name: []const u8, value_type: []const u8) Allocator.Error!void {
        try xm.raw("<rdf:li rdf:parseType=\"Resource\"><pdfaProperty:category>");
        try xm.raw(category);
        try xm.raw("</pdfaProperty:category><pdfaProperty:description>");
        try xm.raw(description);
        try xm.raw("</pdfaProperty:description><pdfaProperty:name>");
        try xm.raw(name);
        try xm.raw("</pdfaProperty:name><pdfaProperty:valueType>");
        try xm.raw(value_type);
        try xm.raw("</pdfaProperty:valueType></rdf:li>");
    }

    fn schemaOpen(xm: *meta.Xmp, schema: []const u8, ns: []const u8, prefix: []const u8) Allocator.Error!void {
        try xm.raw("<rdf:li rdf:parseType=\"Resource\"><pdfaSchema:schema>");
        try xm.text(schema);
        try xm.raw("</pdfaSchema:schema><pdfaSchema:namespaceURI>");
        try xm.text(ns);
        try xm.raw("</pdfaSchema:namespaceURI><pdfaSchema:prefix>");
        try xm.text(prefix);
        try xm.raw("</pdfaSchema:prefix><pdfaSchema:property><rdf:Seq>");
    }

    fn schemaClose(xm: *meta.Xmp) Allocator.Error!void {
        try xm.raw("</rdf:Seq></pdfaSchema:property></rdf:li>");
    }

    fn run(ctx: *anyopaque, xm: *meta.Xmp, m: ?*const meta.Metadata) Allocator.Error!void {
        const self: *XmpCtx = @ptrCast(@alignCast(ctx));
        const c = self.cfg;
        const custom: []const opt.XmpSchema = if (m) |md| md.custom_schemas else &.{};
        if (c.extensionSchema() or custom.len > 0) {
            xm.use(.pdfaExtension);
            xm.use(.pdfaSchema);
            xm.use(.pdfaProperty);
            try xm.raw("<pdfaExtension:schemas><rdf:Bag>");
            if (c.extensionSchema()) {
                try schemaOpen(xm, "XMP Media Management schema", "http://ns.adobe.com/xap/1.0/mm/", "xmpMM");
                try property(xm, "internal", "UUID based identifier for specific incarnation of a document", "InstanceID", "Text");
                try schemaClose(xm);
                try schemaOpen(xm, "Adobe PDF schema", "http://ns.adobe.com/pdf/1.3/", "pdf");
                try property(xm, "external", "Keywords associated with the document", "Keywords", "Text");
                try property(xm, "internal", "Version of the PDF specification to which the document conforms", "PDFVersion", "Text");
                try property(xm, "internal", "Name of the application that created the PDF document", "Producer", "Text");
                try property(xm, "internal", "Whether the document has been trapped", "Trapped", "Text");
                try schemaClose(xm);
            }
            if (c.ua) |u| {
                try schemaOpen(xm, "PDF/UA Identification schema", "http://www.aiim.org/pdfua/ns/id/", "pdfuaid");
                try property(xm, "internal", "Part Number of ISO 14289 (PDF/UA)", "part", "Integer");
                // xmp-writer `describe_rev`
                if (u == .ua2) try property(xm, "internal", "Revision of ISO 14289 (PDF/UA) as a four-digit year", "rev", "Integer");
                try schemaClose(xm);
            }
            for (custom) |s| {
                // (the namespace is declared by the schema's first property element, so a schema
                // without properties declares none)
                if (s.properties.len > 0) try xm.useCustom(s.name, s.prefix, s.namespace);
                try xm.raw("<rdf:li rdf:parseType=\"Resource\"><pdfaSchema:schema>");
                try xm.text(s.name);
                try xm.raw(" schema</pdfaSchema:schema><pdfaSchema:namespaceURI>");
                try xm.text(s.namespace);
                try xm.raw("</pdfaSchema:namespaceURI><pdfaSchema:prefix>");
                try xm.text(s.prefix);
                try xm.raw("</pdfaSchema:prefix><pdfaSchema:property><rdf:Seq>");
                for (s.properties) |p| {
                    try xm.raw("<rdf:li rdf:parseType=\"Resource\"><pdfaProperty:name>");
                    try xm.text(p.name);
                    try xm.raw("</pdfaProperty:name><pdfaProperty:valueType>Text</pdfaProperty:valueType><pdfaProperty:category>external</pdfaProperty:category><pdfaProperty:description>");
                    try xm.text(p.description);
                    try xm.raw("</pdfaProperty:description></rdf:li>");
                }
                try schemaClose(xm);
            }
            try xm.raw("</rdf:Bag></pdfaExtension:schemas>");
        }
        if (c.a != .none) {
            const part: []const u8 = switch (c.a) {
                .a2a, .a2b, .a2u => "2",
                .a3a, .a3b, .a3u => "3",
                else => "4",
            };
            try xm.element(.pdfaid, "part", part);
            if (c.a.isPdf2()) try xm.element(.pdfaid, "rev", "2020");
            const conf: ?[]const u8 = switch (c.a) {
                .a2a, .a3a => "A",
                .a2b, .a3b => "B",
                .a2u, .a3u => "U",
                .a4f => "F",
                else => null,
            };
            if (conf) |x| try xm.element(.pdfaid, "conformance", x);
        }
        if (c.ua) |u| {
            try xm.element(.pdfuaid, "part", if (u == .ua1) "1" else "2");
            if (u == .ua2) try xm.element(.pdfuaid, "rev", "2024");
        }
    }
};

const testing = std.testing;

test "conformance: versions, invalid pairs, prohibitions" {
    const C = struct {
        fn of(pdfa: opt.Pdfa, tagged: opt.Tagging) ?Config {
            const o: opt.PdfOptions = .{ .pdfa = pdfa, .tagged = tagged };
            return Config.of(&o);
        }
    };
    try testing.expectEqual(w.Version.v1_7, C.of(.none, .on).?.version);
    try testing.expectEqual(w.Version.v1_7, C.of(.a2b, .on).?.version);
    try testing.expectEqual(w.Version.v1_7, C.of(.a3u, .ua1).?.version);
    try testing.expectEqual(w.Version.v2_0, C.of(.a4, .on).?.version);
    try testing.expectEqual(w.Version.v2_0, C.of(.none, .ua2).?.version);
    try testing.expectEqual(w.Version.v1_7, C.of(.none, .ua1).?.version);
    try testing.expect(C.of(.a4, .ua1) == null);
    try testing.expect(C.of(.a2b, .ua2) == null);
    const a2b = C.of(.a2b, .on).?;
    try testing.expect(a2b.prohibits(.embedded_existence) and !a2b.prohibits(.no_codepoint_mapping) and a2b.prohibits(.contains_post_script));
    try testing.expect(C.of(.a3b, .on).?.prohibits(.embedded_missing_mime));
    try testing.expect(!C.of(.a4f, .on).?.prohibits(.embedded_existence));
    try testing.expect(C.of(.none, .ua1).?.prohibits(.missing_alt_text));
    try testing.expect(!C.of(.none, .ua1).?.prohibits(.no_document_language));
    try testing.expect(C.of(.none, .ua2).?.prohibits(.no_document_language));
    try testing.expect(srgb_v4.len == 480 and std.mem.eql(u8, srgb_v4[36..40], "acsp"));
}

test "report: one error per distinct value (krilla dedupes by value)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const o: opt.PdfOptions = .{ .pdfa = .a4 };
    var r: Report = .{ .a = arena.allocator(), .cfg = Config.of(&o).? };
    const fo = @import("font_objects.zig");
    const I = fo.FontIssues.Issue;
    // the same private-use character on two glyphs of one font, and on a glyph of another font
    for ([_]I{
        .{ .kind = .private_use, .font = 0, .glyph = 3, .ch = 0xE000 },
        .{ .kind = .private_use, .font = 0, .glyph = 3, .ch = 0xE000 },
        .{ .kind = .private_use, .font = 0, .glyph = 4, .ch = 0xE000 },
        .{ .kind = .private_use, .font = 1, .glyph = 3, .ch = 0xE000 },
        .{ .kind = .private_use, .font = 1, .glyph = 3, .ch = 0xE001 },
    }) |i| r.add(.private_use, i.key());
    r.add(.restricted_license, (I{ .kind = .restricted_license, .font = 0 }).key());
    r.add(.restricted_license, (I{ .kind = .restricted_license, .font = 1 }).key());
    r.add(.missing_heading_title, 0); // not prohibited by PDF/A-4
    try testing.expectEqual(@as(usize, 6), r.list.items.len);
    try testing.expectEqualStrings("Writing the PDF failed: validation failed with 6 errors", (try r.message(arena.allocator())).?);
}
