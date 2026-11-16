//! Everything a CID-keyed font needs in a PDF except the PDF objects themselves: a port of the
//! font side of takumi-pdf's krilla (krilla/text/{cid.rs, font.rs, mod.rs, group.rs}).
//!
//!  * `CidFont` collects the glyphs of one font instance (font file + face + variation
//!    coordinates) while the emitter walks text runs: glyph id -> CID in first-use order,
//!    CID 0 = .notdef always present, the advance of every CID, and the Unicode text each CID
//!    maps to.
//!  * `useTextSpanner` / `GlyphSpanner` / `clusterUnicode` decide, exactly like krilla, which
//!    text a CID maps to in ToUnicode and which glyph runs need an `/ActualText` span.
//!  * `CidFont.finish` subsets the font (subset.zig) and computes the values of the Type0 font,
//!    CIDFont, FontDescriptor and ToUnicode CMap (`EmbedData`).
//!
//! Glyphs that krilla routes to Type3 fonts (COLR / bitmap / SVG glyphs) must not be added
//! here: `glyphRoute` tells which ones.
const std = @import("std");
const ttf = @import("../font/ttf.zig");
const uni = @import("../font/unicode.zig");
const normalize = @import("../font/normalize.zig");
const color = @import("../font/color.zig");
const root_mod = @import("root");
/// Colour fonts compiled in (src/config.zig); without them every glyph is drawn as an outline.
const enable_color_fonts = if (@hasDecl(root_mod, "bm_config")) root_mod.bm_config.enable_color_fonts else true;
const subset = @import("subset.zig");
const Allocator = std.mem.Allocator;

pub const GlyphRemapper = subset.GlyphRemapper;
pub const Subset = subset.Subset;

/// Glyph space of every CIDFont (PDF 32000 9.7.4.3).
pub const pdf_units_per_em: f32 = 1000;
/// /CIDSystemInfo of every CIDFont and of the ToUnicode CMap.
pub const registry = "Adobe";
pub const ordering = "Identity";
pub const supplement: i32 = 0;
/// Predefined /Encoding of the Type0 font (2-byte big-endian CIDs in the content stream).
pub const encoding = "Identity-H";
/// /CMapName of the ToUnicode CMap.
pub const cmap_name = "Custom";
const subset_tag_len = 6;

// ------------------------------------------------------------------ font info

/// Font-level metrics, as krilla's `FontInfo` derives them through skrifa.
pub const FontInfo = struct {
    units_per_em: f32,
    /// OS/2 sTypoAscender / sTypoDescender when there is an OS/2 table, else the line metrics
    /// (hhea / typo per USE_TYPO_METRICS, MVAR applied). Font units, descent negative.
    ascent: f32,
    descent: f32,
    /// OS/2 sCapHeight (version >= 2, MVAR `cpht` applied), else null.
    cap_height: ?f32,
    /// post.italicAngle in degrees.
    italic_angle: f32,
    /// OS/2 usWeightClass (700 / 400 from head.macStyle without OS/2).
    weight: f32,
    /// post.isFixedPitch != 0.
    is_monospaced: bool,
    /// head xMin, yMin, xMax, yMax (font units); (0, 0, upem, upem) when it is not a valid box.
    bbox: [4]f32,
    /// First name record with id 6 (PostScript name), decoded; null when there is none.
    postscript_name: ?[]const u8,
    /// OS/2 fsType & 0xF == 2 ("Restricted License embedding"): PDF/A forbids embedding.
    restricted_license: bool,
};

/// Computes `FontInfo` for `font` (at its variation coordinates). `postscript_name` is
/// allocated with `a`.
pub fn fontInfo(a: Allocator, font: *const ttf.Font) Allocator.Error!FontInfo {
    const upem: f32 = @floatFromInt(font.units_per_em);
    const has_os2 = font.os2.len >= 78;
    const lm = font.lineMetrics();
    var info: FontInfo = .{
        .units_per_em = upem,
        .ascent = if (has_os2) @floatFromInt(font.typoAscender()) else @floatFromInt(lm.ascent),
        .descent = if (has_os2) @floatFromInt(font.typoDescender()) else -@as(f32, @floatFromInt(lm.descent)),
        .cap_height = if (font.os2.len >= 90 and ttf.rd16(font.os2, 0) >= 2) @floatFromInt(font.capHeight()) else null,
        .italic_angle = if (font.post.len >= 8) @as(f32, @floatFromInt(@as(i32, @bitCast(ttf.rd32(font.post, 4))))) / 65536.0 else 0,
        .weight = if (has_os2) @floatFromInt(ttf.rd16(font.os2, 4)) else if (ttf.rd16(font.head, 44) & 1 != 0) 700 else 400,
        .is_monospaced = font.post.len >= 16 and ttf.rd32(font.post, 12) != 0,
        .bbox = .{ 0, 0, upem, upem },
        .postscript_name = try postscriptName(a, font.name),
        .restricted_license = font.os2.len >= 10 and ttf.rd16(font.os2, 8) & 0xf == 2,
    };
    const b = [4]f32{
        @floatFromInt(ttf.rdi16(font.head, 36)), @floatFromInt(ttf.rdi16(font.head, 38)),
        @floatFromInt(ttf.rdi16(font.head, 40)), @floatFromInt(ttf.rdi16(font.head, 42)),
    };
    if (b[0] <= b[2] and b[1] <= b[3]) info.bbox = b;
    return info;
}

/// The first `name` record with id 6, decoded like read-fonts (`NameString::to_string`).
fn postscriptName(a: Allocator, name: []const u8) Allocator.Error!?[]const u8 {
    const count: u32 = ttf.rd16(name, 2);
    const storage = ttf.tail(name, ttf.rd16(name, 4));
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const rec = 6 + i * 12;
        if (rec + 12 > name.len) break;
        if (ttf.rd16(name, rec + 6) != 6) continue;
        const pid = ttf.rd16(name, rec);
        const eid = ttf.rd16(name, rec + 2);
        const len: u32 = ttf.rd16(name, rec + 8);
        const off: u32 = ttf.rd16(name, rec + 10);
        if (off > storage.len or len > storage.len - off) continue;
        const s = storage[off..][0..len];
        var out: std.ArrayList(u8) = .empty;
        const utf16 = pid == 0 or (pid == 3 and (eid == 0 or eid == 1 or eid == 10));
        if (utf16) {
            var k: usize = 0;
            while (k + 1 < s.len) : (k += 2) {
                var cp: u21 = std.mem.readInt(u16, s[k..][0..2], .big);
                if (cp >= 0xd800 and cp < 0xdc00 and k + 3 < s.len) {
                    const lo = std.mem.readInt(u16, s[k + 2 ..][0..2], .big);
                    if (lo >= 0xdc00 and lo < 0xe000) {
                        cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
                        k += 2;
                    }
                }
                if (cp >= 0xd800 and cp < 0xe000) cp = 0xfffd;
                try appendUtf8(a, &out, cp);
            }
        } else if (pid == 1 and eid == 0) {
            for (s) |ch| try appendUtf8(a, &out, if (ch < 0x80) ch else mac_roman_high[ch - 0x80]);
        }
        return try out.toOwnedSlice(a);
    }
    return null;
}

const mac_roman_high = [128]u21{
    0xC4,   0xC5,   0xC7,   0xC9,   0xD1,   0xD6,   0xDC,   0xE1,   0xE0,   0xE2,   0xE4,   0xE3,   0xE5,   0xE7,   0xE9,   0xE8,
    0xEA,   0xEB,   0xED,   0xEC,   0xEE,   0xEF,   0xF1,   0xF3,   0xF2,   0xF4,   0xF6,   0xF5,   0xFA,   0xF9,   0xFB,   0xFC,
    0x2020, 0xB0,   0xA2,   0xA3,   0xA7,   0x2022, 0xB6,   0xDF,   0xAE,   0xA9,   0x2122, 0xB4,   0xA8,   0x2260, 0xC6,   0xD8,
    0x221E, 0xB1,   0x2264, 0x2265, 0xA5,   0xB5,   0x2202, 0x2211, 0x220F, 0x3C0,  0x222B, 0xAA,   0xBA,   0x3A9,  0xE6,   0xF8,
    0xBF,   0xA1,   0xAC,   0x221A, 0x192,  0x2248, 0x2206, 0xAB,   0xBB,   0x2026, 0xA0,   0xC0,   0xC3,   0xD5,   0x152,  0x153,
    0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0xF7,   0x25CA, 0xFF,   0x178,  0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
    0x2021, 0xB7,   0x201A, 0x201E, 0x2030, 0xC2,   0xCA,   0xC1,   0xCB,   0xC8,   0xCD,   0xCE,   0xCF,   0xCC,   0xD3,   0xD4,
    0xF8FF, 0xD2,   0xDA,   0xDB,   0xD9,   0x131,  0x2C6,  0x2DC,  0xAF,   0x2D8,  0x2D9,  0x2DA,  0xB8,   0x2DD,  0x2DB,  0x2C7,
};

fn appendUtf8(a: Allocator, out: *std.ArrayList(u8), cp: u21) Allocator.Error!void {
    var b: [4]u8 = undefined;
    const n = ttf.encodeUtf8(cp, &b);
    try out.appendSlice(a, b[0..n]);
}

// ------------------------------------------------------------ glyph routing

pub const Route = enum {
    /// Outline glyph: goes into the CID font (`CidFont.addGlyph`).
    cid,
    /// Colour / bitmap / SVG glyph: krilla draws it into a Type3 font (out of scope here).
    type3_colr,
    type3_bitmap,
    type3_svg,
};

/// Where krilla's `should_outline` sends glyph `gid` of face `face_index` of `data`.
/// Always `.cid` when colour fonts are compiled out (the raster renderer then draws outlines).
pub fn glyphRoute(data: []const u8, face_index: u32, gid: u16) Route {
    if (!enable_color_fonts) return .cid;
    var dir: u32 = 0;
    if (ttf.rd32(data, 0) == 0x74746366) dir = ttf.rd32(data, 12 +| face_index *| 4);
    const ct = color.ColorTables.fromDirectory(data, dir);
    if (ct.has_svg and svgHasGlyph(data, dir, gid)) return .type3_svg;
    return switch (ct.kind(gid)) {
        .none => .cid,
        .colr_v0, .colr_v1 => .type3_colr,
        .bitmap_png, .bitmap_other => .type3_bitmap,
    };
}

fn svgHasGlyph(data: []const u8, dir: u32, gid: u16) bool {
    const n: u32 = ttf.rd16(data, dir + 4);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const rec = dir + 12 + i * 16;
        if (ttf.rd32(data, rec) != 0x53564720) continue;
        const t = ttf.tail(data, ttf.rd32(data, rec + 8));
        const list = ttf.tail(t, ttf.rd32(t, 2));
        const count: u32 = ttf.rd16(list, 0);
        var k: u32 = 0;
        while (k < count) : (k += 1) {
            const e = 2 + k * 12;
            if (gid >= ttf.rd16(list, e) and gid <= ttf.rd16(list, e + 2)) return true;
        }
        return false;
    }
    return false;
}

// --------------------------------------------------------------- the CID font

/// The glyphs of one font instance used in a document. Owns its memory (allocator `a`).
pub const CidFont = struct {
    a: Allocator,
    /// The instance (variation coordinates applied).
    font: ttf.Font,
    face_index: u32,
    remapper: GlyphRemapper,
    /// Advance (font units, as skrifa reports it at the location) indexed by CID.
    widths: std.ArrayList(f32) = .empty,
    /// ToUnicode text indexed by CID (owned copies; null = none yet).
    texts: std.ArrayList(?[]const u8) = .empty,
    /// Lowest cmap codepoint per glyph id (maxInt = none), built on first use.
    lowest_cp: ?[]u32 = null,
    empty: bool = true,

    /// `font` must be the instance the text was shaped with; `font.data` must stay alive.
    pub fn init(a: Allocator, font: *const ttf.Font, face_index: u32) Allocator.Error!CidFont {
        var c: CidFont = .{ .a = a, .font = font.*, .face_index = face_index, .remapper = try GlyphRemapper.init(a) };
        try c.widths.append(a, c.advance(0));
        try c.texts.append(a, null);
        return c;
    }

    pub fn deinit(c: *CidFont) void {
        c.remapper.deinit(c.a);
        c.widths.deinit(c.a);
        for (c.texts.items) |t| if (t) |s| c.a.free(s);
        c.texts.deinit(c.a);
        if (c.lowest_cp) |l| c.a.free(l);
        c.* = undefined;
    }

    fn advance(c: *const CidFont, gid: u16) f32 {
        if (gid >= c.font.num_glyphs) return 0;
        return @floatFromInt(c.font.advanceWidth(gid));
    }

    /// True until the first `addGlyph`.
    pub fn isEmpty(c: *const CidFont) bool {
        return c.empty;
    }

    /// CID of `gid`, assigning the next one on first use (krilla `CIDFont::add_glyph`).
    pub fn addGlyph(c: *CidFont, gid: u16) error{ OutOfMemory, OverflowError }!u16 {
        c.empty = false;
        const cid = try c.remapper.remap(c.a, gid);
        if (cid >= c.widths.items.len) {
            try c.widths.append(c.a, c.advance(gid));
            try c.texts.append(c.a, null);
        }
        return cid;
    }

    /// CID of an already added glyph.
    pub fn getCid(c: *const CidFont, gid: u16) ?u16 {
        return c.remapper.get(gid);
    }

    /// Number of CIDs (0 ..< numCids), .notdef included.
    pub fn numCids(c: *const CidFont) u16 {
        return c.remapper.numGids();
    }

    /// The text CID `cid` maps to in ToUnicode, if set.
    pub fn getCodepoints(c: *const CidFont, cid: u16) ?[]const u8 {
        if (cid >= c.texts.items.len) return null;
        return c.texts.items[cid];
    }

    /// Sets (replaces) the text of `cid` (copied).
    pub fn setCodepoints(c: *CidFont, cid: u16, text: []const u8) Allocator.Error!void {
        if (cid >= c.texts.items.len) return;
        const copy = try c.a.dupe(u8, text);
        if (c.texts.items[cid]) |old| c.a.free(old);
        c.texts.items[cid] = copy;
    }

    /// The lowest codepoint the font's cmap maps to `gid` (krilla `Font::codepoint`).
    pub fn codepoint(c: *CidFont, gid: u16) Allocator.Error!?u21 {
        if (c.lowest_cp == null) {
            const l = try c.a.alloc(u32, c.font.num_glyphs);
            @memset(l, std.math.maxInt(u32));
            reverseCmap(&c.font, l);
            c.lowest_cp = l;
        }
        const l = c.lowest_cp.?;
        if (gid >= l.len) return null;
        const v = l[gid];
        if (v > 0x10ffff or (v >= 0xd800 and v < 0xe000)) return null;
        return @intCast(v);
    }

    /// Subsets the font and computes the PDF font values (krilla `CIDFont::serialize`). All
    /// returned memory comes from `out` (an arena is fine). The CID font itself is unchanged.
    pub fn finish(c: *const CidFont, out: Allocator) subset.Error!EmbedData {
        const sub = try subset.subsetFont(out, &c.font, c.face_index, &c.remapper);
        const info = try fontInfo(out, &c.font);
        const is_cff = sub.flavor == .cff;
        const upem = info.units_per_em;
        const toPdf = struct {
            fn f(v: f32, u: f32) f32 {
                return v / u * pdf_units_per_em;
            }
        }.f;

        // names
        const ps = info.postscript_name orelse "unknown";
        const max_len = 127 - (subset_tag_len + 1 + 1 + encoding.len);
        const trimmed = ps[0..@min(ps.len, max_len)];
        const tag = subsetTag(c.remapper.gids());
        const base_font = try std.mem.concat(out, u8, &.{ &tag, "+", trimmed });
        const type0_base = if (is_cff) try std.mem.concat(out, u8, &.{ base_font, "-", encoding }) else base_font;

        // widths
        const dw = @round(toPdf(mostCommonWidth(c.widths.items), upem));
        var runs: std.ArrayList(WidthRun) = .empty;
        var first: usize = 0;
        const ws = c.widths.items;
        while (first < ws.len) {
            var end = first + 1;
            while (end < ws.len and ws[end] == ws[first]) end += 1;
            const w = toPdf(ws[first], upem);
            if (w != dw) try runs.append(out, .{ .first = @intCast(first), .last = @intCast(end - 1), .width = w });
            first = end;
        }

        var flags: u32 = 4 | (1 << 17); // SYMBOLIC | SMALL_CAP
        if (std.mem.indexOf(u8, ps, "Serif") != null and info.postscript_name != null) flags |= 2;
        if (info.is_monospaced) flags |= 1;
        if (info.italic_angle != 0) flags |= 64;

        const ascent = toPdf(info.ascent, upem);
        return .{
            .subset = sub,
            .base_font = base_font,
            .type0_base_font = type0_base,
            .cid_font_type = if (is_cff) .cid_font_type0 else .cid_font_type2,
            .cid_to_gid_identity = !is_cff,
            .font_file = if (is_cff) .font_file3_cid_type0c else .font_file2,
            .default_width = dw,
            .widths = try runs.toOwnedSlice(out),
            .flags = flags,
            .bbox = .{ toPdf(info.bbox[0], upem), toPdf(info.bbox[1], upem), toPdf(info.bbox[2], upem), toPdf(info.bbox[3], upem) },
            .italic_angle = info.italic_angle,
            .ascent = ascent,
            .descent = toPdf(info.descent, upem),
            .cap_height = if (info.cap_height) |h| toPdf(h, upem) else ascent,
            .stem_v = 10.0 + 0.244 * (info.weight - 50.0),
            .to_unicode = try toUnicodeCmap(out, c),
            .missing_unicode = countMissing(c),
            .restricted_license = info.restricted_license,
        };
    }
};

/// One `/W` entry: CIDs `first..=last` all have `width` (PDF glyph units).
pub const WidthRun = struct { first: u16, last: u16, width: f32 };

/// The values of the four font objects krilla writes for a CID font:
///
///   Type0 font:      /Type/Font /Subtype/Type0 /BaseFont `type0_base_font`
///                    /Encoding/Identity-H /DescendantFonts[cidfont] /ToUnicode cmap
///   CIDFont:         /Type/Font /Subtype `cid_font_type` /BaseFont `base_font`
///                    /CIDSystemInfo<</Registry(Adobe)/Ordering(Identity)/Supplement 0>>
///                    /FontDescriptor fd /DW `default_width`
///                    [/CIDToGIDMap/Identity if `cid_to_gid_identity`]
///                    /W[`first last width` for each of `widths`]
///   FontDescriptor:  /Type/FontDescriptor /FontName `base_font` /Flags `flags`
///                    /FontBBox `bbox` /ItalicAngle /Ascent /Descent /CapHeight /StemV
///                    /FontFile2 or /FontFile3 (per `font_file`) -> stream
///   font stream:     `subset.program()`; for `.font_file3_cid_type0c` the stream dict also
///                    gets /Subtype/CIDFontType0C
///   ToUnicode:       stream with `to_unicode` (dict: /Type/CMap /WMode 0 in krilla)
///
/// (Key order as in the takumi fixtures: see the doc of each field.)
pub const EmbedData = struct {
    subset: Subset,
    /// "ABCDEF+PostScriptName": CIDFont /BaseFont and FontDescriptor /FontName.
    base_font: []const u8,
    /// Type0 /BaseFont: `base_font` + "-Identity-H" for CFF fonts, else `base_font`.
    type0_base_font: []const u8,
    cid_font_type: enum { cid_font_type0, cid_font_type2 },
    /// Write /CIDToGIDMap /Identity (TrueType outlines only).
    cid_to_gid_identity: bool,
    font_file: enum { font_file2, font_file3_cid_type0c },
    /// /DW: always integral.
    default_width: f32,
    /// /W content, ascending CIDs.
    widths: []const WidthRun,
    /// FontDescriptor /Flags.
    flags: u32,
    /// FontDescriptor /FontBBox [llx lly urx ury] (glyph space).
    bbox: [4]f32,
    italic_angle: f32,
    ascent: f32,
    descent: f32,
    cap_height: f32,
    stem_v: f32,
    /// The ToUnicode CMap program (uncompressed bytes).
    to_unicode: []const u8,
    /// CIDs >= 1 without (or with empty) Unicode text: krilla reports these as validation
    /// errors under PDF/A-*u/a and PDF/UA (`NoCodepointMapping`).
    missing_unicode: u32,
    /// OS/2 says "restricted license embedding" (PDF/A validation error in krilla).
    restricted_license: bool,
};

/// The width most CIDs share; ties go to the one appearing last (Rust `max_by_key`).
fn mostCommonWidth(widths: []const f32) f32 {
    var best: f32 = 0;
    var best_n: usize = 0;
    for (widths, 0..) |w, i| {
        var n: usize = 0;
        for (widths) |v| {
            if (@as(u32, @bitCast(v)) == @as(u32, @bitCast(w))) n += 1;
        }
        if (n >= best_n or i == 0) {
            best_n = n;
            best = w;
        }
    }
    return best;
}

fn countMissing(c: *const CidFont) u32 {
    var n: u32 = 0;
    for (c.texts.items[1..]) |t| {
        if (t == null or t.?.len == 0) n += 1;
    }
    return n;
}

/// The 6-letter subset tag: SipHash-1-3 (128 bit, zero key) of the glyph remapper as Rust's
/// `Hash` feeds it (u64 length + the old glyph ids as little-endian u16), then base 26.
pub fn subsetTag(gids: []const u16) [subset_tag_len]u8 {
    var h = std.crypto.auth.siphash.SipHash128(1, 3).init(&@as([16]u8, @splat(0)));
    var len: [8]u8 = undefined;
    std.mem.writeInt(u64, &len, gids.len, .little);
    h.update(&len);
    for (gids) |g| {
        var b: [2]u8 = undefined;
        std.mem.writeInt(u16, &b, g, .little);
        h.update(&b);
    }
    var out: [16]u8 = undefined;
    h.final(&out);
    var v = std.mem.readInt(u128, &out, .little);
    var tag: [subset_tag_len]u8 = undefined;
    for (&tag) |*l| {
        l.* = 'A' + @as(u8, @intCast(v % 26));
        v /= 26;
    }
    return tag;
}

// ----------------------------------------------------------------- ToUnicode

const hex_digits = "0123456789ABCDEF";

fn putHex16(out: *std.ArrayList(u8), a: Allocator, v: u16) Allocator.Error!void {
    try out.appendSlice(a, &.{ hex_digits[v >> 12], hex_digits[(v >> 8) & 15], hex_digits[(v >> 4) & 15], hex_digits[v & 15] });
}

/// The ToUnicode CMap exactly as pdf-writer's `UnicodeCmap` writes it (bfchar blocks of at
/// most 100 entries, UTF-16BE destinations). CID 0 is never mapped.
pub fn toUnicodeCmap(a: Allocator, c: *const CidFont) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "%!PS-Adobe-3.0 Resource-CMap\n%%DocumentNeededResources: procset CIDInit\n" ++
        "%%IncludeResource: procset CIDInit\n%%BeginResource: CMap " ++ cmap_name ++ "\n" ++
        "%%Title: (" ++ cmap_name ++ " " ++ registry ++ " " ++ ordering ++ " 0)\n%%Version: 1\n%%EndComments\n" ++
        "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo 3 dict dup begin\n" ++
        "    /Registry (" ++ registry ++ ") def\n    /Ordering (" ++ ordering ++ ") def\n    /Supplement 0 def\nend def\n" ++
        "/CMapName /" ++ cmap_name ++ " def\n/CMapVersion 1 def\n/CMapType 0 def\n/WMode 0 def\n" ++
        "1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n");
    var block: std.ArrayList(u8) = .empty;
    defer block.deinit(a);
    var count: u32 = 0;
    var cid: usize = 1;
    while (cid < c.numCids()) : (cid += 1) {
        const text = c.texts.items[cid] orelse continue;
        if (text.len == 0) continue;
        try block.append(a, '<');
        try putHex16(&block, a, @intCast(cid));
        try block.appendSlice(a, "> <");
        var i: usize = 0;
        while (i < text.len) {
            const d = uni.decodeUtf8(text, i);
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
    return out.toOwnedSlice(a);
}

fn flushBlock(out: *std.ArrayList(u8), a: Allocator, block: *std.ArrayList(u8), count: *u32) Allocator.Error!void {
    if (count.* == 0) return;
    // count is 1..100
    if (count.* >= 100) try out.append(a, '1');
    if (count.* >= 10) try out.append(a, '0' + @as(u8, @intCast(count.* / 10 % 10)));
    try out.append(a, '0' + @as(u8, @intCast(count.* % 10)));
    try out.appendSlice(a, " beginbfchar\n");
    try out.appendSlice(a, block.items);
    try out.appendSlice(a, "endbfchar\n");
    count.* = 0;
    block.clearRetainingCapacity();
}

// ------------------------------------------------------------------ reverse cmap

/// Fills `lowest[gid]` with the lowest codepoint the font's chosen cmap subtable maps to gid.
fn reverseCmap(f: *const ttf.Font, lowest: []u32) void {
    const t = f.cmap_sub;
    const put = struct {
        fn p(l: []u32, cp: u32, gid: u32) void {
            if (gid != 0 and gid < l.len and cp < l[gid]) l[gid] = cp;
        }
    }.p;
    switch (f.cmap_format) {
        4 => {
            const seg_x2: u32 = ttf.rd16(t, 6) & 0xfffe;
            const starts = 16 + seg_x2;
            const deltas = starts + seg_x2;
            const ranges = deltas + seg_x2;
            var s: u32 = 0;
            while (s < seg_x2 / 2) : (s += 1) {
                const end: u32 = ttf.rd16(t, 14 + s * 2);
                const start: u32 = ttf.rd16(t, starts + s * 2);
                const delta: u32 = ttf.rd16(t, deltas + s * 2);
                const ro: u32 = ttf.rd16(t, ranges + s * 2);
                if (start > end) continue;
                var cp = start;
                while (cp <= end) : (cp += 1) {
                    var gid: u32 = 0;
                    if (ro == 0) {
                        gid = (cp + delta) & 0xffff;
                    } else {
                        const g: u32 = ttf.rd16(t, ranges + s * 2 + ro + (cp - start) * 2);
                        gid = if (g == 0) 0 else (g + delta) & 0xffff;
                    }
                    put(lowest, cp, gid);
                }
            }
        },
        12, 13 => {
            const avail: u32 = if (t.len > 16) @intCast((t.len - 16) / 12) else 0;
            const n = @min(ttf.rd32(t, 12), avail);
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                const g = 16 + i * 12;
                const start = ttf.rd32(t, g);
                const end = @min(ttf.rd32(t, g + 4), 0x10ffff);
                const sg = ttf.rd32(t, g + 8);
                if (start > end) continue;
                // the lowest codepoint of a group is its start; per gid that is all we need
                if (f.cmap_format == 13) {
                    put(lowest, start, sg);
                } else {
                    var cp = start;
                    while (cp <= end) : (cp += 1) {
                        const gid = sg +% (cp - start);
                        if (gid >= lowest.len) break;
                        put(lowest, cp, gid);
                    }
                }
            }
        },
        6 => {
            const first: u32 = ttf.rd16(t, 6);
            const n: u32 = ttf.rd16(t, 8);
            var i: u32 = 0;
            while (i < n) : (i += 1) put(lowest, first + i, ttf.rd16(t, 10 + i * 2));
        },
        else => {},
    }
}

// ------------------------------------------------------------ text spanning

/// A glyph of a run as the PDF text code sees it: glyph id + the byte range (into the run
/// text) of the cluster it belongs to (krilla `Glyph::text_range`).
pub const SpanGlyph = struct { gid: u16, start: u32, end: u32 };

fn sameRange(x: SpanGlyph, y: SpanGlyph) bool {
    return x.start == y.start and x.end == y.end;
}

/// takumi glyph.rs `merge_overlapping_spans`: glyphs whose cluster ranges overlap the running
/// group get the union of the group, so krilla puts them under one `/ActualText` (in place).
/// Apply to a run's glyphs before `useTextSpanner` (takumi also drops `.notdef` glyphs unless
/// a placeholder is drawn, and maps every glyph to the whole run when clusters are unknown).
pub fn mergeOverlappingSpans(glyphs: []SpanGlyph) void {
    var group: usize = 0;
    var i: usize = 1;
    while (i < glyphs.len) : (i += 1) {
        const g = glyphs[group];
        const n = glyphs[i];
        if (!(g.start < n.end and n.start < g.end)) {
            group = i;
            continue;
        }
        const s = @min(g.start, n.start);
        const e = @max(g.end, n.end);
        for (glyphs[group .. i + 1]) |*x| {
            x.start = s;
            x.end = e;
        }
    }
}

/// The run is in reverse text order (every glyph's cluster ends at or before the previous
/// one's start): krilla then always spans and writes `/ReversedChars` marked content.
pub fn isReversed(glyphs: []const SpanGlyph) bool {
    if (glyphs.len <= 1) return false;
    for (glyphs[0 .. glyphs.len - 1], glyphs[1..]) |p, n| if (!(p.start >= n.end)) return false;
    return true;
}

/// krilla `use_text_spanner`: adds the run's glyphs and records each glyph's cluster text
/// as its ToUnicode text until a glyph is found whose CID already maps to other text (or two
/// glyphs share a cluster); returns whether the run needs `/ActualText` spans (then iterate
/// a `GlyphSpanner` over it). Call it only when `isReversed` is false (krilla short-circuits).
pub fn useTextSpanner(c: *CidFont, glyphs: []const SpanGlyph, text: []const u8) !bool {
    if (glyphs.len == 0) return false;
    var span = false;
    for (glyphs, 0..) |g, i| {
        if (i + 1 < glyphs.len and sameRange(g, glyphs[i + 1])) span = true;
        if (span) continue;
        const cid = try c.addGlyph(g.gid);
        const t = text[g.start..g.end];
        if (c.getCodepoints(cid)) |existing| {
            if (!std.mem.eql(u8, existing, t)) span = true;
        } else try c.setCodepoints(cid, t);
    }
    return span;
}

/// A fragment of a run: `count` glyphs, wrapped in `/Span <</ActualText (text[start..end])>>`
/// marked content when `actual_text` is set.
pub const Span = struct { count: usize, actual_text: ?[2]u32 };

/// krilla `GlyphSpanner`: splits a run into fragments that need an `/ActualText` span and
/// fragments that do not, assigning ToUnicode text as it goes. Memory from `a` (arena).
pub const GlyphSpanner = struct {
    c: *CidFont,
    glyphs: []const SpanGlyph,
    text: []const u8,
    reversed: bool,
    forbid_invalid_codepoints: bool,
    unicode: []const ?[]const u8,
    offset: usize = 0,

    /// takumi always passes `forbid_invalid_codepoints = true`.
    pub fn init(a: Allocator, c: *CidFont, glyphs: []const SpanGlyph, text: []const u8, reversed: bool, forbid_invalid_codepoints: bool) !GlyphSpanner {
        return .{
            .c = c,
            .glyphs = glyphs,
            .text = text,
            .reversed = reversed,
            .forbid_invalid_codepoints = forbid_invalid_codepoints,
            .unicode = try clusterUnicode(a, c, glyphs, text),
        };
    }

    const Res = struct { start: u32, end: u32, incompatible: bool };

    fn visit(s: *GlyphSpanner, g: SpanGlyph, prev: ?SpanGlyph, unicode: ?[]const u8) !Res {
        const cid = try s.c.addGlyph(g.gid);
        const t = unicode orelse s.text[g.start..g.end];
        const cps = s.c.getCodepoints(cid);
        const incompatible = if (cps) |x| !std.mem.eql(u8, x, t) else false;
        const new_range = if (prev) |p| !sameRange(p, g) else true;
        if (!incompatible and (new_range or s.forbid_invalid_codepoints or unicode != null) and cps == null)
            try s.c.setCodepoints(cid, t);
        return .{ .start = g.start, .end = g.end, .incompatible = incompatible };
    }

    pub fn next(s: *GlyphSpanner) !?Span {
        const rest = s.glyphs[s.offset..];
        if (rest.len == 0) return null;
        const uni_rest = s.unicode[s.offset..];
        var use_span: ?bool = null;
        var count: usize = 1;
        const first = try s.visit(rest[0], null, uni_rest[0]);
        var prev = rest[0];
        var i: usize = 1;
        while (i < rest.len) : (i += 1) {
            const nx = try s.visit(rest[i], prev, uni_rest[i]);
            const same = sameRange(prev, rest[i]);
            if (use_span) |u| {
                if (u) {
                    if (!same) break;
                } else {
                    if (same) {
                        count -= 1;
                        break;
                    }
                    if (nx.incompatible) break;
                }
            } else {
                if (same) {
                    use_span = true;
                } else {
                    use_span = first.incompatible;
                    if (first.incompatible or nx.incompatible) break;
                }
            }
            prev = rest[i];
            count += 1;
            if (s.reversed and count > 1 and std.mem.eql(u8, s.text[prev.start..prev.end], " ")) break;
        }
        if (count == 1) use_span = first.incompatible;
        s.offset += count;
        return .{ .count = count, .actual_text = if (use_span orelse false) .{ first.start, first.end } else null };
    }
};

/// krilla `cluster_unicode`: for clusters of several glyphs, each glyph with a cmap codepoint
/// maps to that codepoint, the others share what is left of the cluster's NFD text evenly
/// (in glyph order). null = use the glyph's whole cluster text.
pub fn clusterUnicode(a: Allocator, c: *CidFont, glyphs: []const SpanGlyph, text: []const u8) ![]const ?[]const u8 {
    const out = try a.alloc(?[]const u8, glyphs.len);
    @memset(out, null);
    var start: usize = 0;
    while (start < glyphs.len) {
        var end = start + 1;
        while (end < glyphs.len and sameRange(glyphs[end], glyphs[start])) end += 1;
        if (end - start > 1) {
            var rest: std.ArrayList(u21) = .empty;
            try nfd(a, text[glyphs[start].start..glyphs[start].end], &rest);
            var uncovered: std.ArrayList(usize) = .empty;
            var tmp: std.ArrayList(u21) = .empty;
            for (start..end) |idx| {
                const ch = (try c.codepoint(glyphs[idx].gid)) orelse {
                    try uncovered.append(a, idx);
                    continue;
                };
                tmp.clearRetainingCapacity();
                var b: [4]u8 = undefined;
                try nfd(a, b[0..ttf.encodeUtf8(ch, &b)], &tmp);
                for (tmp.items) |d| {
                    if (std.mem.indexOfScalar(u21, rest.items, d)) |at| _ = rest.orderedRemove(at);
                }
                var s: std.ArrayList(u8) = .empty;
                try appendUtf8(a, &s, ch);
                out[idx] = s.items;
            }
            const n = rest.items.len;
            for (uncovered.items, 0..) |idx, share| {
                const from = share * n / uncovered.items.len;
                const to = (share + 1) * n / uncovered.items.len;
                if (from < to) {
                    var s: std.ArrayList(u8) = .empty;
                    for (rest.items[from..to]) |cp| try appendUtf8(a, &s, cp);
                    out[idx] = s.items;
                }
            }
        }
        start = end;
    }
    return out;
}

/// Canonical decomposition (NFD) of UTF-8 `s`, appended to `out`. Uses bm-render's
/// decomposition data (Latin, Greek, Cyrillic, Vietnamese, and the Hebrew / Arabic / Indic
/// pairs below U+1100, see font/nfdata.zig) plus algorithmic Hangul; characters outside
/// that data are kept as they are.
fn nfd(a: Allocator, s: []const u8, out: *std.ArrayList(u21)) Allocator.Error!void {
    const base = out.items.len;
    var i: usize = 0;
    while (i < s.len) {
        const d = uni.decodeUtf8(s, i);
        i += d.len;
        try decomposeInto(a, d.cp, out);
    }
    // canonical ordering (stable insertion sort of runs of non-starters by ccc)
    const xs = out.items[base..];
    var k: usize = 1;
    while (k < xs.len) : (k += 1) {
        const cc = uni.ccc(xs[k]);
        if (cc == 0) continue;
        var j = k;
        while (j > 0) {
            const pc = uni.ccc(xs[j - 1]);
            if (pc == 0 or pc <= cc) break;
            std.mem.swap(u21, &xs[j], &xs[j - 1]);
            j -= 1;
        }
    }
}

fn decomposeInto(a: Allocator, cp: u21, out: *std.ArrayList(u21)) Allocator.Error!void {
    if (cp >= 0xac00 and cp < 0xac00 + 11172) {
        const si = cp - 0xac00;
        try out.append(a, 0x1100 + si / 588);
        try out.append(a, 0x1161 + (si % 588) / 28);
        if (si % 28 != 0) try out.append(a, 0x11a7 + si % 28);
        return;
    }
    if (normalize.decompose(cp)) |pair| {
        try decomposeInto(a, pair[0], out);
        try decomposeInto(a, pair[1], out);
        return;
    }
    try out.append(a, cp);
}

// -------------------------------------------------------------------- tests

test {
    _ = @import("font_embed_tests.zig");
}
