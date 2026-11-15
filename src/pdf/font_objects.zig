//! Document-level PDF fonts: a port of krilla's `FontContainer` / `Type3FontMapper` /
//! `Type3Font` (krilla/text/{mod.rs, type3.rs}) and of the object-writing half of
//! `CIDFont::serialize` / `Type3Font::serialize` / `SerializeContext::serialize_fonts`.
//!
//!  * `FontRegistry` maps a font instance (font bytes + face index + normalised variation
//!    coordinates, i.e. one bm-engine face / variable instance) to one `FontContainer`, in
//!    first-use order (krilla's `font_map` is an `IndexMap`), for the whole document.
//!  * A `FontContainer` holds the CID font of the instance (font_embed.zig `CidFont`) and the
//!    Type3 fonts its colour / bitmap / SVG glyphs go to (at most 256 glyphs each, keyed by glyph
//!    + context colour), and routes every glyph to one of them exactly like krilla's
//!    `FontContainer::add_glyph` / `should_outline`.
//!  * `FontRegistry.flush` (call once, at document end, before the pages' resource dictionaries
//!    are written — krilla serialises fonts before pages) writes, per container in first-use
//!    order, its Type3 fonts and then its CID font:
//!      CID:   Type0, CIDFont, FontDescriptor (category `fonts`), ToUnicode CMap, font program
//!             (category `font_streams`) — key order as takumi-pdf's fixtures;
//!      Type3: per glyph its drawing (a Form XObject, see type3.zig) and the glyph procedure
//!             (`font_streams`), the resource dictionary, FontDescriptor (PDF >= 1.5) and the
//!             Type3 font dictionary (`fonts`), the 1-byte ToUnicode CMap (`font_streams`).
//!    It returns the validation facts krilla records (`FontIssues`): the later PDF/A / PDF/UA
//!    wave decides which of them are errors.
const std = @import("std");
const w = @import("writer.zig");
const ttf = @import("../font/ttf.zig");
const fe = @import("font_embed.zig");
const sf = @import("emit_surface.zig");
const uni = @import("../font/unicode.zig");
const type3 = @import("type3.zig");

const Allocator = std.mem.Allocator;
const Ref = w.Ref;

const root_mod = @import("root");
/// Colour fonts compiled in (src/config.zig); without them every glyph is a CID glyph.
pub const enable_color_fonts = if (@hasDecl(root_mod, "bm_config")) root_mod.bm_config.enable_color_fonts else true;

pub const pdf_units_per_em: f32 = fe.pdf_units_per_em;

/// A glyph as a PDF text code: a 2-byte CID or a 1-byte Type3 code.
pub const PdfGlyph = union(enum) {
    cid: u16,
    t3: u8,

    /// Appends the glyph's bytes in the content stream (krilla `PDFGlyph::encode_into`).
    pub fn encodeInto(g: PdfGlyph, a: Allocator, out: *std.ArrayList(u8)) Allocator.Error!void {
        switch (g) {
            .t3 => |c| try out.append(a, c),
            .cid => |c| try out.appendSlice(a, &.{ @intCast(c >> 8), @intCast(c & 0xff) }),
        }
    }
};

/// Which PDF font of a container: the CID font, or Type3 font `index`.
pub const FontId = union(enum) {
    cid,
    t3: u16,

    pub fn eql(x: FontId, y: FontId) bool {
        return switch (x) {
            .cid => y == .cid,
            .t3 => |i| switch (y) {
                .t3 => |j| i == j,
                .cid => false,
            },
        };
    }
};

/// A Type3 glyph is drawn per context colour (COLR / SVG glyphs can use the text colour).
pub const ColoredGlyph = struct { gid: u16, color: [3]u8 };

pub const Added = struct { font: FontId, glyph: PdfGlyph };

/// krilla `Type3Font`: up to 256 coloured glyphs, code = index in first-use order.
pub const Type3Font = struct {
    glyphs: std.ArrayList(ColoredGlyph) = .empty,
    /// advance in font units per code
    widths: std.ArrayList(f32) = .empty,
    /// ToUnicode text per code (null = none)
    texts: std.ArrayList(?[]const u8) = .empty,
    ref: ?Ref = null,

    pub fn count(t: *const Type3Font) usize {
        return t.glyphs.items.len;
    }

    fn find(t: *const Type3Font, g: ColoredGlyph) ?u8 {
        for (t.glyphs.items, 0..) |x, i| {
            if (x.gid == g.gid and std.mem.eql(u8, &x.color, &g.color)) return @intCast(i);
        }
        return null;
    }
};

/// The validation facts krilla records while writing fonts (`ValidationError` variants), for
/// the PDF/A / PDF/UA checks. Counts are over CIDs / Type3 codes of all fonts.
pub const FontIssues = struct {
    /// OS/2 fsType & 0xF == 2 (`RestrictedLicense`): PDF/A forbids embedding such a font.
    restricted_license: bool = false,
    /// PostScript name of the first restricted font (for an error message).
    restricted_font: []const u8 = "",
    /// Glyphs without ToUnicode text, or with empty text (`NoCodepointMapping`; PDF/A-*u, *a, UA).
    no_codepoint_mapping: u32 = 0,
    /// Glyphs whose text contains U+0000, U+FEFF or U+FFFE (`InvalidCodepointMapping`).
    invalid_codepoint_mapping: u32 = 0,
    /// Glyphs whose text uses a private-use codepoint (`UnicodePrivateArea`; PDF/UA).
    private_use: u32 = 0,
    /// `.notdef` glyphs (or a LastResort font) shown as text (`ContainsNotDefGlyph`; PDF/A, UA).
    notdef_shown: u32 = 0,
    /// One entry per violation krilla registers while writing the fonts, with the values its
    /// `ValidationError` variant carries (krilla dedupes the list by value, so the number of
    /// distinct entries is what `validation failed with N error(s)` counts).
    list: std.ArrayList(Issue) = .empty,

    pub const Kind = enum { restricted_license, no_codepoint_mapping, invalid_codepoint_mapping, private_use };
    pub const Issue = struct {
        kind: Kind,
        /// index of the font (krilla `Font`) in first-use order
        font: u32,
        /// CID, or code within a Type3 font (krilla passes both as the `GlyphId`)
        glyph: u32 = 0,
        /// the offending character (`InvalidCodepointMapping`, `UnicodePrivateArea`)
        ch: u32 = 0,

        /// A value that is equal exactly when krilla's variants are.
        pub fn key(i: Issue) u64 {
            return (@as(u64, i.font) << 37) | (@as(u64, i.glyph & 0xffff) << 21) | @as(u64, i.ch & 0x1fffff);
        }
    };
};

/// krilla `FontContainer`: everything one font instance contributes to the document.
pub const FontContainer = struct {
    a: Allocator,
    /// The instance (variation coordinates applied); `font.data` must outlive the document.
    font: ttf.Font,
    face_index: u32,
    /// see `FontRegistry.container`
    variant: u32 = 0,
    upem: f32,
    /// krilla `can_be_cid_font`: the font has glyf / CFF / CFF2 outlines.
    cid_capable: bool,
    /// postscript name is "LastResort" (every glyph counts as .notdef for validation)
    last_resort: bool = false,
    cid: fe.CidFont,
    cid_ref: ?Ref = null,
    t3: std.ArrayList(Type3Font) = .empty,
    /// gid -> routed to the CID font (true) or Type3 (false); filled by `addGlyph` (looked up
    /// for every drawn glyph, never iterated: a multiplicative hash, not the default Wyhash,
    /// whose 128-bit multiplies are emulated on wasm32)
    route: std.HashMapUnmanaged(u16, bool, GidContext, std.hash_map.default_max_load_percentage) = .empty,
    /// (gid, colour) -> Type3 font index + code
    t3_cache: std.AutoHashMapUnmanaged(u64, Added) = .empty,

    fn init(a: Allocator, font: *const ttf.Font, face_index: u32) !FontContainer {
        var c: FontContainer = .{
            .a = a,
            .font = font.*,
            .face_index = face_index,
            .upem = @floatFromInt(@max(1, font.units_per_em)),
            .cid_capable = font.glyf.len != 0 or font.cff.len != 0,
            .cid = undefined,
        };
        c.cid = try fe.CidFont.init(a, &c.font, face_index);
        return c;
    }

    const GidContext = struct {
        pub fn hash(_: GidContext, k: u16) u64 {
            const h = @as(u64, k) *% 0x9E3779B97F4A7C15;
            return h ^ (h >> 29);
        }
        pub fn eql(_: GidContext, a: u16, b: u16) bool {
            return a == b;
        }
    };

    fn colorKey(g: ColoredGlyph) u64 {
        return (@as(u64, g.gid) << 24) | (@as(u64, g.color[0]) << 16) | (@as(u64, g.color[1]) << 8) | g.color[2];
    }

    /// krilla `should_outline`: the glyph goes into the CID font.
    pub fn shouldOutline(c: *const FontContainer, gid: u16) bool {
        if (!c.cid_capable) return false;
        if (comptime !enable_color_fonts) return true;
        return switch (fe.glyphRoute(c.font.data, c.face_index, gid)) {
            .cid => true,
            // krilla draws only PNG bitmaps (`has_bitmap_data`); other bitmap formats stay outlines
            .type3_bitmap => type3.bitmapKind(&c.font, gid) != .bitmap_png,
            .type3_colr, .type3_svg => false,
        };
    }

    /// krilla `FontContainer::add_glyph`.
    pub fn addGlyph(c: *FontContainer, gid: u16, color: [3]u8) !Added {
        if (c.route.get(gid)) |is_cid| {
            if (is_cid) return .{ .font = .cid, .glyph = .{ .cid = c.cid.getCid(gid).? } };
            if (c.t3_cache.get(colorKey(.{ .gid = gid, .color = color }))) |e| return e;
        }
        const is_cid = c.route.get(gid) orelse c.shouldOutline(gid);
        try c.route.put(c.a, gid, is_cid);
        if (is_cid) {
            const cid = try c.cid.addGlyph(gid);
            return .{ .font = .cid, .glyph = .{ .cid = cid } };
        }
        const cg: ColoredGlyph = .{ .gid = gid, .color = color };
        // Type3FontMapper::add_glyph: an existing font covering it, else the last one, else a new one
        for (c.t3.items, 0..) |*t, i| {
            if (t.find(cg)) |code| {
                const r: Added = .{ .font = .{ .t3 = @intCast(i) }, .glyph = .{ .t3 = code } };
                try c.t3_cache.put(c.a, colorKey(cg), r);
                return r;
            }
        }
        if (c.t3.items.len == 0 or c.t3.items[c.t3.items.len - 1].count() == 256) try c.t3.append(c.a, .{});
        const idx = c.t3.items.len - 1;
        const t = &c.t3.items[idx];
        try t.glyphs.append(c.a, cg);
        try t.widths.append(c.a, c.advance(gid) orelse 0);
        try t.texts.append(c.a, null);
        const r: Added = .{ .font = .{ .t3 = @intCast(idx) }, .glyph = .{ .t3 = @intCast(t.glyphs.items.len - 1) } };
        try c.t3_cache.put(c.a, colorKey(cg), r);
        return r;
    }

    /// krilla `FontContainer::font_identifier` (the glyph must have been added).
    pub fn fontIdOf(c: *const FontContainer, gid: u16, color: [3]u8) ?FontId {
        const is_cid = c.route.get(gid) orelse return null;
        if (is_cid) return .cid;
        const e = c.t3_cache.get(colorKey(.{ .gid = gid, .color = color })) orelse return null;
        return e.font;
    }

    /// The PDF glyph of an added glyph in font `id` (krilla `PdfFont::get_gid`).
    pub fn pdfGlyph(c: *const FontContainer, id: FontId, gid: u16, color: [3]u8) ?PdfGlyph {
        return switch (id) {
            .cid => if (c.cid.getCid(gid)) |x| .{ .cid = x } else null,
            .t3 => |i| if (c.t3.items[i].find(.{ .gid = gid, .color = color })) |x| .{ .t3 = x } else null,
        };
    }

    pub fn getCodepoints(c: *const FontContainer, id: FontId, g: PdfGlyph) ?[]const u8 {
        return switch (id) {
            .cid => c.cid.getCodepoints(g.cid),
            .t3 => |i| c.t3.items[i].texts.items[g.t3],
        };
    }

    pub fn setCodepoints(c: *FontContainer, id: FontId, g: PdfGlyph, text: []const u8) !void {
        switch (id) {
            .cid => try c.cid.setCodepoints(g.cid, text),
            .t3 => |i| c.t3.items[i].texts.items[g.t3] = try c.a.dupe(u8, text),
        }
    }

    /// krilla `PdfFont::units_per_em`: 1000 for the CID font, the font's own for Type3.
    pub fn unitsPerEm(c: *const FontContainer, id: FontId) f32 {
        return switch (id) {
            .cid => pdf_units_per_em,
            .t3 => c.upem,
        };
    }

    /// Type3 glyphs are always filled (`force_fill`).
    pub fn forceFill(id: FontId) bool {
        return id != .cid;
    }

    /// krilla `Font::advance_width` (font units; null past the glyph count).
    pub fn advance(c: *const FontContainer, gid: u16) ?f32 {
        if (gid >= c.font.num_glyphs) return null;
        return @floatFromInt(c.font.advanceWidth(gid));
    }

    /// The font object ref (krilla `register_font_identifier`), allocated on first use.
    pub fn ref(c: *FontContainer, doc: *w.Doc, id: FontId) Ref {
        const slot = switch (id) {
            .cid => &c.cid_ref,
            .t3 => |i| &c.t3.items[i].ref,
        };
        if (slot.* == null) slot.* = doc.alloc();
        return slot.*.?;
    }
};

/// The characters no font covers, and the `uncoveredText` policy (takumi glyph.rs `Uncovered`).
pub const Uncovered = struct {
    policy: Policy = .@"error",
    /// the standard that forbids the placeholder (`PDF/A-2b`, `PDF/UA-1`, ...), if one applies
    forbidden_by: ?[]const u8 = null,
    chars: std.ArrayList(u21) = .empty,

    pub const Policy = enum { @"error", placeholder, blank };

    /// `.notdef` glyphs are drawn (as the font's placeholder) unless the policy is `blank`.
    pub fn drawsPlaceholder(u: *const Uncovered) bool {
        return u.policy != .blank;
    }

    pub fn record(u: *Uncovered, a: Allocator, cp: u21) !void {
        if (std.mem.indexOfScalar(u21, u.chars.items, cp) == null) try u.chars.append(a, cp);
    }

    /// takumi `Uncovered::into_error`: `UncoveredCharacters` when the policy is `error` and
    /// characters were met, `PlaceholderForbidden` when the policy is `placeholder` under a
    /// standard forbidding the `.notdef` glyph (`forbidden_by`), else null.
    pub fn errorMessage(u: *const Uncovered, a: Allocator) !?[]const u8 {
        if (u.chars.items.len == 0) return null;
        if (u.policy == .blank) return null;
        if (u.policy == .placeholder and u.forbidden_by == null) return null;
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(a, "No font the text can use draws ");
        try u.appendNamed(a, &out, u.chars.items.len);
        if (u.policy == .placeholder) {
            try out.appendSlice(a, ", and ");
            try out.appendSlice(a, u.forbidden_by.?);
            try out.appendSlice(a, " forbids the placeholder glyph. Register a font that draws them, or set uncoveredText to \"blank\".");
            return out.items;
        }
        try out.appendSlice(a, ". Check each font's unicodeRange and the font-family stack, or register a font that draws them.");
        return out.items;
    }

    /// The error of text met while no font is registered at all (the bundled Geist last-resort font
    /// unregistered too). Names the first characters, null when none were met.
    pub fn noFontMessage(u: *const Uncovered, a: Allocator) !?[]const u8 {
        if (u.chars.items.len == 0) return null;
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(a, "No font is registered to draw ");
        const shown = @min(u.chars.items.len, 8);
        try u.appendNamed(a, &out, shown);
        if (shown < u.chars.items.len) try out.appendSlice(a, ", ...");
        try out.appendSlice(a, ". Register one with registerFont or the fonts option (unregistering Geist removed the bundled fallback).");
        return out.items;
    }

    /// `c (U+0063), d (U+0064)` for the first `count` recorded characters.
    fn appendNamed(u: *const Uncovered, a: Allocator, out: *std.ArrayList(u8), count: usize) !void {
        for (u.chars.items[0..count], 0..) |cp, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            var b: [4]u8 = undefined;
            try out.appendSlice(a, b[0..ttf.encodeUtf8(cp, &b)]);
            try out.appendSlice(a, " (U+");
            var hex: [8]u8 = undefined;
            var n: usize = 0;
            var v: u32 = cp;
            while (v != 0 or n < 4) : (v >>= 4) {
                hex[n] = hex_digits[v & 15];
                n += 1;
            }
            while (n > 0) {
                n -= 1;
                try out.append(a, hex[n]);
            }
            try out.append(a, ')');
        }
    }
};

/// Key of a font instance.
fn instanceHash(font: *const ttf.Font, face_index: u32, variant: u32) u64 {
    var h = std.hash.Wyhash.init(0x7e47);
    h.update(std.mem.asBytes(&@intFromPtr(font.data.ptr)));
    h.update(std.mem.asBytes(&font.data.len));
    h.update(std.mem.asBytes(&face_index));
    h.update(std.mem.asBytes(&variant));
    h.update(std.mem.sliceAsBytes(font.coords[0..font.n_axes]));
    return h.final();
}

/// All PDF fonts of one document, in first-use order (krilla `font_map`).
pub const FontRegistry = struct {
    a: Allocator,
    containers: std.ArrayList(*FontContainer) = .empty,
    keys: std.ArrayList(u64) = .empty,
    /// collected while drawing (see `FontIssues.notdef_shown`)
    notdef_shown: u32 = 0,
    flushed: bool = false,
    /// characters without a font, met while drawing (takumi `DocumentState.issues.uncovered`)
    uncovered: Uncovered = .{},
    /// (text.zig adapter) cluster starts of the last paragraph seen
    cluster_para: ?*const anyopaque = null,
    cluster_starts: []const u32 = &.{},
    /// (text.zig adapter) the last paragraph text and its white-space-normalised copy
    text_src: []const u8 = "",
    text_clean: []const u8 = "",

    /// Drops the caches keyed by address (`cluster_para`, `text_src`) before a page is drawn: what
    /// a page drew from its working memory is gone, and a new paragraph may take its place.
    pub fn forgetPage(r: *FontRegistry) void {
        r.cluster_para = null;
        r.cluster_starts = &.{};
        r.text_src = "";
        r.text_clean = "";
    }

    /// `a` must live as long as the document (the per-render arena). `policy`: the
    /// `uncoveredText` option.
    pub fn init(a: Allocator, policy: Uncovered.Policy) FontRegistry {
        return .{ .a = a, .uncovered = .{ .policy = policy } };
    }

    /// takumi's `UncoveredCharacters` error message when `uncoveredText` is "error" and some
    /// character had no font (check after drawing all pages), else null.
    pub fn uncoveredError(reg: *const FontRegistry) !?[]const u8 {
        return reg.uncovered.errorMessage(reg.a);
    }

    /// The container of an instance, created on first use (krilla `register_font_container`).
    /// `font` is the instance the text was shaped with (bm-engine `fonts.font(face)`) and
    /// `face_index` its face in a collection (`fonts.face(face).index`).
    /// `variant` tells instances apart that share their coordinates (krilla keys a font by the
    /// variation values it was asked for, see `text.zig opszVariant`); 0 = none.
    pub fn container(reg: *FontRegistry, font: *const ttf.Font, face_index: u32, variant: u32) !*FontContainer {
        const key = instanceHash(font, face_index, variant);
        for (reg.keys.items, 0..) |k, i| {
            const c = reg.containers.items[i];
            if (k == key and c.font.data.ptr == font.data.ptr and c.face_index == face_index and c.variant == variant and
                std.mem.eql(i16, c.font.coords[0..c.font.n_axes], font.coords[0..font.n_axes])) return c;
        }
        const c = try reg.a.create(FontContainer);
        c.* = try FontContainer.init(reg.a, font, face_index);
        c.variant = variant;
        try reg.containers.append(reg.a, c);
        try reg.keys.append(reg.a, key);
        return c;
    }

    /// Writes every font used (krilla `serialize_fonts`). Call once at document end, before the
    /// page objects / page resource dictionaries are written (krilla's object order). Returns
    /// the validation facts; errors are subsetting / allocation failures.
    pub fn flush(reg: *FontRegistry, cx: *sf.Ctx) !FontIssues {
        var issues: FontIssues = .{ .notdef_shown = reg.notdef_shown };
        if (reg.flushed) return issues;
        reg.flushed = true;
        for (reg.containers.items, 0..) |c, fi| {
            const at: IssueAt = .{ .a = cx.a, .issues = &issues, .font = @intCast(fi) };
            for (0..c.t3.items.len) |i| {
                const r = c.ref(cx.doc, .{ .t3 = @intCast(i) });
                try writeType3(cx, c, &c.t3.items[i], r, at);
            }
            if (!c.cid.isEmpty()) try writeCid(cx, c, c.ref(cx.doc, .cid), at);
        }
        if (cx.doc.b.failed) return error.OutOfMemory;
        return issues;
    }
};

// ------------------------------------------------------------------------------- CID fonts

/// Where the violations of one font are recorded.
const IssueAt = struct {
    a: Allocator,
    issues: *FontIssues,
    font: u32,

    fn add(at: IssueAt, kind: FontIssues.Kind, glyph: u32, ch: u32) Allocator.Error!void {
        try at.issues.list.append(at.a, .{ .kind = kind, .font = at.font, .glyph = glyph, .ch = ch });
    }
};

/// krilla `write_cmap_entry`: the validation facts of one glyph's text (`g`: the CID or the
/// Type3 code).
fn checkText(text: ?[]const u8, at: IssueAt, g: u32) Allocator.Error!void {
    const issues = at.issues;
    const t = text orelse {
        issues.no_codepoint_mapping += 1;
        try at.add(.no_codepoint_mapping, g, 0);
        return;
    };
    var invalid_code = false;
    var private = false;
    var invalid_ch: u32 = 0;
    var private_ch: u32 = 0;
    var i: usize = 0;
    while (i < t.len) {
        const d = uni.decodeUtf8(t, i);
        i += d.len;
        if (d.cp == 0 or d.cp == 0xFEFF or d.cp == 0xFFFE) {
            invalid_code = true;
            invalid_ch = d.cp;
        }
        if ((d.cp >= 0xE000 and d.cp <= 0xF8FF) or (d.cp >= 0xF0000 and d.cp <= 0xFFFFD) or (d.cp >= 0x100000 and d.cp <= 0x10FFFD)) {
            private = true;
            private_ch = d.cp;
        }
    }
    if (invalid_code) {
        issues.invalid_codepoint_mapping += 1;
        try at.add(.invalid_codepoint_mapping, g, invalid_ch);
    } else if (t.len == 0) {
        issues.no_codepoint_mapping += 1;
        try at.add(.no_codepoint_mapping, g, 0);
    }
    if (private) {
        issues.private_use += 1;
        try at.add(.private_use, g, private_ch);
    }
}

/// krilla `CIDFont::serialize` (objects: Type0 `root`, CIDFont, FontDescriptor in `fonts`;
/// ToUnicode CMap, then the font program, in `font_streams`).
fn writeCid(cx: *sf.Ctx, c: *FontContainer, root: Ref, at: IssueAt) !void {
    const issues = at.issues;
    const doc = cx.doc;
    const d = try c.cid.finish(cx.a);
    if (d.restricted_license) {
        try at.add(.restricted_license, 0, 0);
        if (!issues.restricted_license) {
            issues.restricted_license = true;
            issues.restricted_font = d.base_font;
        }
    }
    var cid: usize = 1;
    while (cid < c.cid.numCids()) : (cid += 1) try checkText(c.cid.texts.items[cid], at, @intCast(cid));

    const cid_ref = doc.alloc();
    const fd_ref = doc.alloc();
    const cmap_ref = doc.alloc();
    const data_ref = doc.alloc();
    {
        const b = doc.beginDict(root, .fonts);
        b.pairName("Type", "Font");
        b.pairName("Subtype", "Type0");
        b.pairName("BaseFont", d.type0_base_font);
        b.pairName("Encoding", fe.encoding);
        b.key("DescendantFonts");
        b.refs(&.{cid_ref});
        b.pairRef("ToUnicode", cmap_ref);
        doc.endDict();
    }
    {
        const b = doc.beginDict(cid_ref, .fonts);
        b.pairName("Type", "Font");
        b.pairName("Subtype", if (d.cid_font_type == .cid_font_type0) "CIDFontType0" else "CIDFontType2");
        b.pairName("BaseFont", d.base_font);
        b.key("CIDSystemInfo");
        b.dict();
        b.pairStr("Registry", fe.registry);
        b.pairStr("Ordering", fe.ordering);
        b.pairInt("Supplement", fe.supplement);
        b.dictEnd();
        b.pairRef("FontDescriptor", fd_ref);
        b.pairReal("DW", d.default_width);
        if (d.cid_to_gid_identity) b.pairName("CIDToGIDMap", "Identity");
        b.key("W");
        b.arr();
        for (d.widths) |run| {
            b.int(run.first);
            b.int(run.last);
            b.real(run.width);
        }
        b.arrEnd();
        doc.endDict();
    }
    {
        const b = doc.beginDict(fd_ref, .fonts);
        b.pairName("Type", "FontDescriptor");
        b.pairName("FontName", d.base_font);
        b.pairInt("Flags", d.flags);
        b.pairRect("FontBBox", d.bbox);
        b.pairReal("ItalicAngle", d.italic_angle);
        b.pairReal("Ascent", d.ascent);
        b.pairReal("Descent", d.descent);
        b.pairReal("CapHeight", d.cap_height);
        b.pairReal("StemV", d.stem_v);
        b.pairRef(if (d.font_file == .font_file2) "FontFile2" else "FontFile3", data_ref);
        doc.endDict();
    }
    writeCmapStream(doc, cmap_ref, d.to_unicode);
    {
        const e = doc.encode(d.subset.program(), .flate);
        const b = doc.beginStream(data_ref, .font_streams, e);
        b.filter(e);
        if (d.font_file == .font_file3_cid_type0c) b.pairName("Subtype", "CIDFontType0C");
        doc.endDict();
    }
}

/// ToUnicode stream (`new_from_content_stream`): `/Length/Type/CMap/Filter/WMode 0`.
fn writeCmapStream(doc: *w.Doc, r: Ref, program: []const u8) void {
    const e = doc.encode(program, .content);
    const b = doc.beginStream(r, .font_streams, e);
    b.pairName("Type", "CMap");
    b.filter(e);
    b.pairInt("WMode", 0);
    doc.endDict();
}

// ------------------------------------------------------------------------------- Type3 fonts

const hex_digits = "0123456789ABCDEF";

/// The 1-byte ToUnicode CMap of a Type3 font (pdf-writer `UnicodeCmap<u8>`).
pub fn type3Cmap(a: Allocator, texts: []const ?[]const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "%!PS-Adobe-3.0 Resource-CMap\n%%DocumentNeededResources: procset CIDInit\n" ++
        "%%IncludeResource: procset CIDInit\n%%BeginResource: CMap " ++ fe.cmap_name ++ "\n" ++
        "%%Title: (" ++ fe.cmap_name ++ " " ++ fe.registry ++ " " ++ fe.ordering ++ " 0)\n%%Version: 1\n%%EndComments\n" ++
        "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo 3 dict dup begin\n" ++
        "    /Registry (" ++ fe.registry ++ ") def\n    /Ordering (" ++ fe.ordering ++ ") def\n    /Supplement 0 def\nend def\n" ++
        "/CMapName /" ++ fe.cmap_name ++ " def\n/CMapVersion 1 def\n/CMapType 0 def\n/WMode 0 def\n" ++
        "1 begincodespacerange\n<00> <FF>\nendcodespacerange\n");
    var block: std.ArrayList(u8) = .empty;
    var count: u32 = 0;
    for (texts, 0..) |t_opt, code| {
        const t = t_opt orelse continue;
        if (t.len == 0) continue;
        try block.appendSlice(a, &.{ '<', hex_digits[code >> 4], hex_digits[code & 15], '>', ' ', '<' });
        var i: usize = 0;
        while (i < t.len) {
            const d = uni.decodeUtf8(t, i);
            i += d.len;
            if (d.cp >= 0x10000) {
                const v = d.cp - 0x10000;
                try putHex16(&block, a, @intCast(0xd800 + (v >> 10)));
                try putHex16(&block, a, @intCast(0xdc00 + (v & 0x3ff)));
            } else try putHex16(&block, a, @intCast(d.cp));
        }
        try block.appendSlice(a, ">\n");
        count += 1;
        if (count >= 100) try flushBlock(&out, a, &block, &count);
    }
    try flushBlock(&out, a, &block, &count);
    try out.appendSlice(a, "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n%%EndResource\n%%EOF");
    return out.items;
}

fn putHex16(out: *std.ArrayList(u8), a: Allocator, v: u16) Allocator.Error!void {
    try out.appendSlice(a, &.{ hex_digits[v >> 12], hex_digits[(v >> 8) & 15], hex_digits[(v >> 4) & 15], hex_digits[v & 15] });
}

fn flushBlock(out: *std.ArrayList(u8), a: Allocator, block: *std.ArrayList(u8), count: *u32) Allocator.Error!void {
    if (count.* == 0) return;
    var t: [24]u8 = undefined;
    try out.appendSlice(a, w.fmtInt(&t, count.*));
    try out.appendSlice(a, " beginbfchar\n");
    try out.appendSlice(a, block.items);
    try out.appendSlice(a, "endbfchar\n");
    count.* = 0;
    block.clearRetainingCapacity();
}

/// skrifa `Stretch` from OS/2 usWidthClass, as pdf-writer's `FontStretch` names it.
fn stretchName(font: *const ttf.Font) []const u8 {
    if (font.os2.len < 8) return "Normal";
    return switch (ttf.rd16(font.os2, 6)) {
        1 => "UltraCondensed",
        2 => "ExtraCondensed",
        3 => "Condensed",
        4 => "SemiCondensed",
        6 => "SemiExpanded",
        7 => "Expanded",
        8 => "ExtraExpanded",
        9 => "UltraExpanded",
        else => "Normal",
    };
}

fn weightBucket(weight: f32) i64 {
    const v: i32 = @intFromFloat(std.math.clamp(weight, -1e6, 1e6));
    return if (v >= 150 and v < 250) 200 else if (v >= 250 and v < 350) 300 else if (v >= 350 and v < 450) 400 else if (v >= 450 and v < 550) 500 else if (v >= 550 and v < 650) 600 else if (v >= 650 and v < 750) 700 else if (v >= 750 and v < 850) 800 else if (v < 150) 100 else 900;
}

/// krilla `Type3Font::serialize`.
fn writeType3(cx: *sf.Ctx, c: *FontContainer, t: *const Type3Font, root: Ref, at: IssueAt) !void {
    const doc = cx.doc;
    const a = cx.a;
    var res = w.Resources.init(a);
    var bbox: sf.LRect = .{ .l = 0, .t = 0, .r = 1, .b = 1 };
    const procs = try a.alloc(Ref, t.glyphs.items.len);
    for (t.glyphs.items, 0..) |g, i| {
        var s = sf.Surface.initStream(cx);
        if (!(try type3.drawColorGlyph(cx, &s, &c.font, g.color, g.gid, .identity))) {
            // no colour data (e.g. .notdef): the outline in black
            var p: sf.Path = .empty;
            if (try type3.glyphPath(a, &c.font, g.gid, .identity, &p)) {
                s.setFill(.{ .paint = .{ .color = .{ 0, 0, 0 } } });
                s.setStroke(null);
                s.drawPath(&p);
            }
        }
        const st = s.finish();
        var content = @import("content.zig").Content.init(a);
        // pdf-writer `start_color_glyph`: " wx 0 d0"
        var tmp: [48]u8 = undefined;
        content.b.raw(" ");
        content.b.raw(w.fmtReal(&tmp, t.widths.items[i]));
        content.operands = true;
        content.num(0);
        content.op("d0");
        if (st.content.len != 0) {
            bbox.expand(st.bbox);
            const x = sf.regXObject(cx, &st, false, false, null);
            content.xObject(res.add(.x_object, x).slice());
        }
        if (content.failed()) return error.OutOfMemory;
        const pr = doc.alloc();
        const e = doc.encode(content.bytes(), .content);
        const b = doc.beginStream(pr, .font_streams, e);
        b.filter(e);
        doc.endDict();
        procs[i] = pr;
    }
    const res_ref = res.write(doc);
    const info = try fe.fontInfo(a, &c.font);
    const fd_ref: ?Ref = if (doc.version.atLeast(.v1_5)) doc.alloc() else null;
    const cmap_ref = doc.alloc();

    var flags: u32 = 4 | (1 << 17);
    if (info.postscript_name) |n| {
        if (std.mem.indexOf(u8, n, "Serif") != null) flags |= 2;
    }
    if (info.is_monospaced) flags |= 1;
    if (info.italic_angle != 0) flags |= 64;
    const ps = info.postscript_name orelse "unknown";
    const base_font = ps[0..@min(ps.len, 127 - (1 + 1 + fe.encoding.len))];
    const rect = [4]f32{ bbox.l, bbox.t, bbox.r, bbox.b };

    if (fd_ref) |fr| {
        const b = doc.beginDict(fr, .fonts);
        b.pairName("Type", "FontDescriptor");
        b.pairName("FontName", base_font);
        b.pairInt("Flags", flags);
        b.pairRect("FontBBox", rect);
        b.pairReal("ItalicAngle", info.italic_angle);
        b.pairReal("Ascent", bbox.b);
        b.pairReal("Descent", bbox.t);
        b.pairStr("FontFamily", base_font);
        b.pairName("FontStretch", stretchName(&c.font));
        b.pairInt("FontWeight", weightBucket(info.weight));
        doc.endDict();
    }
    {
        const b = doc.beginDict(root, .fonts);
        b.pairName("Type", "Font");
        b.pairName("Subtype", "Type3");
        if (res_ref) |r| b.pairRef("Resources", r) else b.raw("/Resources<<>>");
        b.pairName("Name", base_font);
        b.pairRect("FontBBox", rect);
        b.pairRef("ToUnicode", cmap_ref);
        b.key("FontMatrix");
        b.reals(&.{ 1.0 / c.upem, 0, 0, 1.0 / c.upem, 0, 0 });
        b.pairInt("FirstChar", 0);
        b.pairInt("LastChar", @intCast(t.glyphs.items.len -| 1));
        b.key("Widths");
        b.reals(t.widths.items);
        if (fd_ref) |fr| b.pairRef("FontDescriptor", fr);
        b.key("CharProcs");
        b.dict();
        for (procs, 0..) |pr, i| {
            var nb: [8]u8 = undefined;
            b.name(gName(&nb, i));
            b.ref(pr);
        }
        b.dictEnd();
        b.key("Encoding");
        b.dict();
        b.pairName("Type", "Encoding");
        b.key("Differences");
        b.arr();
        b.int(0);
        for (0..procs.len) |i| {
            var nb: [8]u8 = undefined;
            b.name(gName(&nb, i));
        }
        b.arrEnd();
        b.dictEnd();
        doc.endDict();
    }
    for (t.texts.items, 0..) |x, g| try checkText(x, at, @intCast(g));
    writeCmapStream(doc, cmap_ref, try type3Cmap(a, t.texts.items));
}

fn gName(buf: *[8]u8, i: usize) []const u8 {
    buf[0] = 'g';
    var t: [24]u8 = undefined;
    const s = w.fmtInt(&t, @intCast(i));
    @memcpy(buf[1..][0..s.len], s);
    return buf[0 .. 1 + s.len];
}

