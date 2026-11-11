//! Zero-copy sfnt (TrueType / TrueType collection) parser.
//!
//! All accessors are bounds-checked against the table slices and return 0 / empty on malformed
//! data. Offsets are `u32` combined with saturating arithmetic so behaviour is identical on
//! wasm32 and 64-bit hosts.
const std = @import("std");
const ot = @import("ot.zig");

pub const Error = error{
    /// CFF ('OTTO'), WOFF, WOFF2 or CFF-only fonts: recognised but not supported.
    UnsupportedFontFormat,
    /// Not an sfnt, or the table directory is out of bounds.
    InvalidFont,
    /// One of head/hhea/maxp/hmtx/cmap is missing.
    MissingTable,
};

pub inline fn rd8(t: []const u8, off: u32) u8 {
    if (off >= t.len) return 0;
    return t[off];
}
pub inline fn rd16(t: []const u8, off: u32) u16 {
    if (t.len < 2 or off > t.len - 2) return 0;
    return (@as(u16, t[off]) << 8) | t[off + 1];
}
pub inline fn rdi16(t: []const u8, off: u32) i16 {
    return @bitCast(rd16(t, off));
}
pub inline fn rd32(t: []const u8, off: u32) u32 {
    if (t.len < 4 or off > t.len - 4) return 0;
    return (@as(u32, t[off]) << 24) | (@as(u32, t[off + 1]) << 16) | (@as(u32, t[off + 2]) << 8) | t[off + 3];
}
/// Sub-slice starting at `off` (empty when out of range).
pub inline fn tail(t: []const u8, off: u32) []const u8 {
    if (off >= t.len) return t[0..0];
    return t[off..];
}

fn tag(comptime s: *const [4]u8) u32 {
    return (@as(u32, s[0]) << 24) | (@as(u32, s[1]) << 16) | (@as(u32, s[2]) << 8) | s[3];
}

pub const Bounds = struct { x_min: i16 = 0, y_min: i16 = 0, x_max: i16 = 0, y_max: i16 = 0 };

/// Ascent/descent/leading in font units, chosen the way skrifa's `Metrics` does (which is what
/// takumi feeds into its Blink-style line metrics):
///  * hhea ascender/descender/lineGap by default;
///  * OS/2 sTypo* when fsSelection bit 7 (USE_TYPO_METRICS) is set, or when hhea ascender and
///    descender are both 0 — falling back to usWinAscent/usWinDescent if the typo values are 0.
/// `descent` is positive-down (i.e. `-hhea.descender`).
pub const LineMetrics = struct { ascent: i32, descent: i32, leading: i32 };

/// 2x3 affine used for composite glyphs: x' = a*x + c*y + e, y' = b*x + d*y + f.
const Xf = struct {
    a: f32 = 1,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 1,
    e: f32 = 0,
    f: f32 = 0,
    ident: bool = true,
};

pub const max_feature_lookups = 24;

pub const Font = struct {
    data: []const u8,
    head: []const u8 = &.{},
    hhea: []const u8 = &.{},
    hmtx: []const u8 = &.{},
    cmap_sub: []const u8 = &.{},
    loca: []const u8 = &.{},
    glyf: []const u8 = &.{},
    name: []const u8 = &.{},
    os2: []const u8 = &.{},
    post: []const u8 = &.{},
    kern: []const u8 = &.{},
    gpos: []const u8 = &.{},
    gsub: []const u8 = &.{},
    units_per_em: u16 = 1000,
    num_glyphs: u16 = 0,
    num_hmetrics: u16 = 0,
    cmap_format: u16 = 0,
    loca_long: bool = false,
    /// GPOS lookups of the `kern` feature (ascending lookup index).
    n_kern: u8 = 0,
    kern_lookups: [max_feature_lookups]u16 = undefined,
    /// GSUB lookups (ascending); bit 15 of an entry marks a "discretionary" (liga/clig) lookup
    /// that is switched off when letter-spacing is non-zero.
    n_gsub: u8 = 0,
    gsub_lookups: [max_feature_lookups]u16 = undefined,
    /// First-glyph digests of the lookups above (fast rejection while shaping).
    kern_digests: [max_feature_lookups]ot.Digest = undefined,
    gsub_digests: [max_feature_lookups]ot.Digest = undefined,

    /// Parses the table directory. `data` must outlive the Font. `face_index` selects a face of
    /// a .ttc (must be 0 for plain .ttf).
    pub fn init(data: []const u8, face_index: u32) Error!Font {
        if (data.len < 12 or data.len > 0x7fff_ffff) return error.InvalidFont;
        var dir: u32 = 0;
        var magic = rd32(data, 0);
        if (magic == tag("ttcf")) {
            const n = rd32(data, 8);
            if (face_index >= n) return error.InvalidFont;
            dir = rd32(data, 12 +| face_index *| 4);
            if (dir == 0 or dir > data.len - 12) return error.InvalidFont;
            magic = rd32(data, dir);
        } else if (face_index != 0) return error.InvalidFont;
        if (magic == tag("OTTO") or magic == tag("wOFF") or magic == tag("wOF2")) return error.UnsupportedFontFormat;
        if (magic != 0x00010000 and magic != tag("true")) return error.InvalidFont;

        const num_tables: u32 = rd16(data, dir + 4);
        if (dir + 12 + num_tables * 16 > data.len) return error.InvalidFont;

        var f: Font = .{ .data = data };
        var maxp: []const u8 = &.{};
        var cmap: []const u8 = &.{};
        var has_cff = false;
        var i: u32 = 0;
        while (i < num_tables) : (i += 1) {
            const rec = dir + 12 + i * 16;
            const off = rd32(data, rec + 8);
            const len = rd32(data, rec + 12);
            if (off > data.len or len > data.len - off) continue; // table out of bounds: ignore it
            const t = data[off..][0..len];
            switch (rd32(data, rec)) {
                tag("head") => f.head = t,
                tag("hhea") => f.hhea = t,
                tag("maxp") => maxp = t,
                tag("hmtx") => f.hmtx = t,
                tag("cmap") => cmap = t,
                tag("loca") => f.loca = t,
                tag("glyf") => f.glyf = t,
                tag("name") => f.name = t,
                tag("OS/2") => f.os2 = t,
                tag("post") => f.post = t,
                tag("kern") => f.kern = t,
                tag("GPOS") => f.gpos = t,
                tag("GSUB") => f.gsub = t,
                tag("CFF "), tag("CFF2") => has_cff = true,
                else => {},
            }
        }
        if (f.head.len < 54 or f.hhea.len < 36 or maxp.len < 6 or cmap.len < 4) return error.MissingTable;
        if (f.glyf.len == 0 and has_cff) return error.UnsupportedFontFormat;

        f.units_per_em = rd16(f.head, 18);
        if (f.units_per_em == 0) f.units_per_em = 1000;
        f.loca_long = rd16(f.head, 50) != 0;
        f.num_glyphs = rd16(maxp, 4);
        f.num_hmetrics = rd16(f.hhea, 34);
        f.pickCmap(cmap);
        f.n_kern = @intCast(ot.collectLookups(f.gpos, &.{.{ .tag = tag("kern"), .flag = 0 }}, &f.kern_lookups));
        f.n_gsub = @intCast(ot.collectLookups(f.gsub, &.{
            .{ .tag = tag("ccmp"), .flag = 0 },
            .{ .tag = tag("locl"), .flag = 0 },
            .{ .tag = tag("rlig"), .flag = 0 },
            .{ .tag = tag("liga"), .flag = 0x8000 },
            .{ .tag = tag("clig"), .flag = 0x8000 },
            .{ .tag = tag("calt"), .flag = 0x8000 },
        }, &f.gsub_lookups));
        for (f.kern_lookups[0..f.n_kern], 0..) |li, k| f.kern_digests[k] = ot.lookupDigest(f.gpos, li, 9);
        for (f.gsub_lookups[0..f.n_gsub], 0..) |li, k| f.gsub_digests[k] = ot.lookupDigest(f.gsub, li & 0x7fff, 7);
        return f;
    }

    fn pickCmap(f: *Font, cmap: []const u8) void {
        const n: u32 = rd16(cmap, 2);
        var best: u32 = 0;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const rec = 4 + i * 8;
            const pid = rd16(cmap, rec);
            const eid = rd16(cmap, rec + 2);
            const sub = tail(cmap, rd32(cmap, rec + 4));
            const format = rd16(sub, 0);
            var score: u32 = 0;
            const unicode = pid == 0 or (pid == 3 and (eid == 1 or eid == 10));
            if (unicode) {
                score = switch (format) {
                    12 => if (pid == 3) 6 else 5,
                    4 => if (pid == 3) 4 else 3,
                    13 => 2,
                    6 => 1,
                    else => 0,
                };
            } else if (pid == 3 and eid == 0 and format == 4) score = 1;
            if (score > best) {
                best = score;
                f.cmap_sub = sub;
                f.cmap_format = format;
            }
        }
    }

    // ------------------------------------------------------------------ cmap

    /// Glyph id for a Unicode codepoint, 0 (.notdef) when unmapped.
    pub fn glyphIndex(f: *const Font, cp: u21) u16 {
        const t = f.cmap_sub;
        const c: u32 = cp;
        var gid: u32 = 0;
        switch (f.cmap_format) {
            4 => {
                if (c > 0xffff) return 0;
                const seg_x2: u32 = rd16(t, 6) & 0xfffe;
                const ends: u32 = 14;
                const starts = 16 + seg_x2;
                const deltas = starts + seg_x2;
                const ranges = deltas + seg_x2;
                var lo: u32 = 0;
                var hi: u32 = seg_x2 / 2;
                while (lo < hi) {
                    const mid = (lo + hi) / 2;
                    if (rd16(t, ends + mid * 2) < c) lo = mid + 1 else hi = mid;
                }
                if (lo >= seg_x2 / 2) return 0;
                const start: u32 = rd16(t, starts + lo * 2);
                if (start > c) return 0;
                const delta: u32 = rd16(t, deltas + lo * 2);
                const ro: u32 = rd16(t, ranges + lo * 2);
                if (ro == 0) {
                    gid = (c + delta) & 0xffff;
                } else {
                    const g: u32 = rd16(t, ranges + lo * 2 + ro + (c - start) * 2);
                    gid = if (g == 0) 0 else (g + delta) & 0xffff;
                }
            },
            12, 13 => {
                const avail: u32 = if (t.len > 16) @intCast((t.len - 16) / 12) else 0;
                var hi: u32 = @min(rd32(t, 12), avail);
                var lo: u32 = 0;
                while (lo < hi) {
                    const mid = (lo + hi) / 2;
                    if (rd32(t, 16 + mid * 12 + 4) < c) lo = mid + 1 else hi = mid;
                }
                const g = 16 +| lo *| 12;
                const start = rd32(t, g);
                if (g + 12 > t.len or start > c or rd32(t, g + 4) < c) return 0;
                gid = rd32(t, g + 8);
                if (f.cmap_format == 12) gid +|= c - start;
            },
            6 => {
                const first: u32 = rd16(t, 6);
                if (c < first or c - first >= rd16(t, 8)) return 0;
                gid = rd16(t, 10 + (c - first) * 2);
            },
            else => return 0,
        }
        return if (gid < f.num_glyphs) @intCast(gid) else 0;
    }

    // --------------------------------------------------------------- metrics

    pub fn unitsPerEm(f: *const Font) u16 {
        return f.units_per_em;
    }
    pub fn numGlyphs(f: *const Font) u16 {
        return f.num_glyphs;
    }
    pub fn hheaAscender(f: *const Font) i16 {
        return rdi16(f.hhea, 4);
    }
    pub fn hheaDescender(f: *const Font) i16 {
        return rdi16(f.hhea, 6);
    }
    pub fn hheaLineGap(f: *const Font) i16 {
        return rdi16(f.hhea, 8);
    }
    pub fn typoAscender(f: *const Font) i16 {
        return rdi16(f.os2, 68);
    }
    pub fn typoDescender(f: *const Font) i16 {
        return rdi16(f.os2, 70);
    }
    pub fn typoLineGap(f: *const Font) i16 {
        return rdi16(f.os2, 72);
    }
    pub fn winAscent(f: *const Font) u16 {
        return rd16(f.os2, 74);
    }
    pub fn winDescent(f: *const Font) u16 {
        return rd16(f.os2, 76);
    }
    pub fn fsSelection(f: *const Font) u16 {
        return rd16(f.os2, 62);
    }
    pub fn useTypoMetrics(f: *const Font) bool {
        return f.os2.len >= 78 and f.fsSelection() & 0x80 != 0;
    }
    /// OS/2 sxHeight (0 when the table is older than version 2).
    pub fn xHeight(f: *const Font) i16 {
        return if (rd16(f.os2, 0) >= 2) rdi16(f.os2, 86) else 0;
    }
    pub fn capHeight(f: *const Font) i16 {
        return if (rd16(f.os2, 0) >= 2) rdi16(f.os2, 88) else 0;
    }
    /// OS/2 usWeightClass; 700/400 from macStyle when there is no OS/2 table.
    pub fn weightClass(f: *const Font) u16 {
        if (f.os2.len >= 6) {
            const w = rd16(f.os2, 4);
            if (w >= 1 and w <= 1000) return w;
        }
        return if (rd16(f.head, 44) & 1 != 0) 700 else 400;
    }
    pub fn isItalic(f: *const Font) bool {
        return (f.os2.len >= 64 and f.fsSelection() & 0x201 != 0) or rd16(f.head, 44) & 2 != 0;
    }
    /// post.underlinePosition (y-up font units, usually negative).
    pub fn underlinePosition(f: *const Font) i16 {
        return rdi16(f.post, 8);
    }
    pub fn underlineThickness(f: *const Font) i16 {
        return rdi16(f.post, 10);
    }
    /// OS/2 yStrikeoutPosition (y-up font units).
    pub fn strikeoutPosition(f: *const Font) i16 {
        return rdi16(f.os2, 28);
    }
    pub fn strikeoutThickness(f: *const Font) i16 {
        return rdi16(f.os2, 26);
    }

    /// See `LineMetrics`.
    pub fn lineMetrics(f: *const Font) LineMetrics {
        const has_os2 = f.os2.len >= 78;
        const use_typo = f.useTypoMetrics();
        var m: LineMetrics = .{ .ascent = 0, .descent = 0, .leading = 0 };
        if (!use_typo) {
            m = .{ .ascent = f.hheaAscender(), .descent = -@as(i32, f.hheaDescender()), .leading = f.hheaLineGap() };
        }
        if (has_os2 and ((m.ascent == 0 and m.descent == 0) or use_typo)) {
            const a: i32 = f.typoAscender();
            const d: i32 = f.typoDescender();
            if (a != 0 or d != 0) {
                m = .{ .ascent = a, .descent = -d, .leading = f.typoLineGap() };
            } else {
                m.ascent = f.winAscent();
                m.descent = f.winDescent();
            }
        }
        return m;
    }

    /// Advance width in font units.
    pub fn advanceWidth(f: *const Font, gid: u16) u16 {
        if (f.num_hmetrics == 0) return 0;
        const i: u32 = @min(gid, f.num_hmetrics - 1);
        return rd16(f.hmtx, i * 4);
    }

    // ------------------------------------------------------------------ name

    /// UTF-8 family name (name id 16, else 1) written into `buf`; truncated to fit.
    pub fn familyName(f: *const Font, buf: []u8) []const u8 {
        const s = f.nameString(16, buf);
        return if (s.len != 0) s else f.nameString(1, buf);
    }
    /// UTF-8 subfamily ("Regular", "Bold Italic", ...; name id 17, else 2).
    pub fn subfamilyName(f: *const Font, buf: []u8) []const u8 {
        const s = f.nameString(17, buf);
        return if (s.len != 0) s else f.nameString(2, buf);
    }

    /// Decodes a `name` record to UTF-8. Prefers Windows/en-US, then any Windows or Unicode
    /// record, then Macintosh Roman (non-ASCII bytes become '?').
    pub fn nameString(f: *const Font, name_id: u16, buf: []u8) []const u8 {
        const t = f.name;
        const count: u32 = rd16(t, 2);
        const strings = tail(t, rd16(t, 4));
        var best: u32 = 0;
        var best_rec: u32 = 0;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const rec = 6 + i * 12;
            if (rec + 12 > t.len) break;
            if (rd16(t, rec + 6) != name_id) continue;
            const pid = rd16(t, rec);
            const lang = rd16(t, rec + 4);
            const score: u32 = switch (pid) {
                3 => if (lang == 0x409) 4 else 3,
                0 => 2,
                1 => if (lang == 0) 1 else 0,
                else => 0,
            };
            if (score > best) {
                best = score;
                best_rec = rec;
            }
        }
        if (best == 0) return buf[0..0];
        const len: u32 = rd16(t, best_rec + 8);
        const off: u32 = rd16(t, best_rec + 10);
        if (off > strings.len or len > strings.len - off) return buf[0..0];
        const s = strings[off..][0..len];
        var n: usize = 0;
        if (best == 1) {
            for (s) |ch| {
                if (n >= buf.len) break;
                buf[n] = if (ch < 0x80) ch else '?';
                n += 1;
            }
            return buf[0..n];
        }
        var k: u32 = 0;
        while (k + 1 < s.len) : (k += 2) {
            var cp: u21 = rd16(s, k);
            if (cp >= 0xd800 and cp < 0xdc00 and k + 3 < s.len) {
                const lo = rd16(s, k + 2);
                if (lo >= 0xdc00 and lo < 0xe000) {
                    cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
                    k += 2;
                }
            }
            if (cp >= 0xd800 and cp < 0xe000) cp = 0xfffd;
            var tmp: [4]u8 = undefined;
            const l = encodeUtf8(cp, &tmp);
            if (n + l > buf.len) break;
            @memcpy(buf[n..][0..l], tmp[0..l]);
            n += l;
        }
        return buf[0..n];
    }

    // --------------------------------------------------------------- kerning

    /// Pair kerning in font units (added to the advance of `left`): GPOS `kern` feature when the
    /// font has one, else the legacy `kern` table (format 0).
    pub fn kerning(f: *const Font, left: u16, right: u16) i16 {
        const v = f.pairAdjust(left, right).adv1;
        return @intCast(std.math.clamp(v, -32768, 32767));
    }

    /// Full pair adjustment (x advance / x placement of both glyphs), font units.
    pub fn pairAdjust(f: *const Font, left: u16, right: u16) ot.PairAdjust {
        if (f.n_kern != 0) {
            var r: ot.PairAdjust = .{};
            for (f.kern_lookups[0..f.n_kern], 0..) |li, k| {
                if (f.kern_digests[k].mayHave(left)) ot.pairLookup(f.gpos, li, left, right, &r);
            }
            return r;
        }
        return .{ .adv1 = f.kernTable(left, right) };
    }

    fn kernTable(f: *const Font, left: u16, right: u16) i32 {
        const t = f.kern;
        if (t.len < 4 or rd16(t, 0) != 0) return 0;
        const n: u32 = rd16(t, 2);
        const key: u32 = (@as(u32, left) << 16) | right;
        var off: u32 = 4;
        var sum: i32 = 0;
        var i: u32 = 0;
        while (i < n and off + 14 <= t.len) : (i += 1) {
            const len: u32 = rd16(t, off + 2);
            const cov = rd16(t, off + 4);
            // format 0, horizontal, not minimum / cross-stream
            if (cov >> 8 == 0 and cov & 0x7 == 1) {
                const avail: u32 = @intCast((t.len - off - 14) / 6);
                var hi: u32 = @min(rd16(t, off + 6), avail);
                var lo: u32 = 0;
                while (lo < hi) {
                    const mid = (lo + hi) / 2;
                    const k = rd32(t, off + 14 + mid * 6);
                    if (k < key) lo = mid + 1 else hi = mid;
                }
                const p = off + 14 + lo * 6;
                if (p + 6 <= t.len and rd32(t, p) == key) sum += rdi16(t, p + 4);
            }
            if (len < 6) break;
            off += len;
        }
        return sum;
    }

    // ---------------------------------------------------------------- glyphs

    fn glyphData(f: *const Font, gid: u16) []const u8 {
        if (gid >= f.num_glyphs) return &.{};
        var a: u32 = undefined;
        var b: u32 = undefined;
        if (f.loca_long) {
            if ((@as(u32, gid) + 2) * 4 > f.loca.len) return &.{};
            a = rd32(f.loca, @as(u32, gid) * 4);
            b = rd32(f.loca, @as(u32, gid) * 4 + 4);
        } else {
            if ((@as(u32, gid) + 2) * 2 > f.loca.len) return &.{};
            a = @as(u32, rd16(f.loca, @as(u32, gid) * 2)) * 2;
            b = @as(u32, rd16(f.loca, @as(u32, gid) * 2 + 2)) * 2;
        }
        if (b <= a or b > f.glyf.len) return &.{};
        return f.glyf[a..b];
    }

    /// Bounding box from the glyf header (font units, y-up); zeros for empty glyphs.
    pub fn glyphBounds(f: *const Font, gid: u16) Bounds {
        const g = f.glyphData(gid);
        if (g.len < 10) return .{};
        return .{ .x_min = rdi16(g, 2), .y_min = rdi16(g, 4), .x_max = rdi16(g, 6), .y_max = rdi16(g, 8) };
    }

    /// Emits the outline of `gid` in font units (y-up) to `sink`, which needs
    /// `moveTo(x,y)`, `lineTo(x,y)`, `quadTo(cx,cy,x,y)`, `cubicTo(c1x,c1y,c2x,c2y,x,y)`, `close()`
    /// (f32 args, void result; `cubicTo` is unused by glyf outlines). Every contour is a
    /// moveTo ... close sequence. Returns false when the glyph has no outline.
    pub fn outline(f: *const Font, gid: u16, sink: anytype) bool {
        var budget: u32 = 256;
        return f.outlineRec(gid, .{}, 0, &budget, sink);
    }

    fn outlineRec(f: *const Font, gid: u16, xf: Xf, depth: u32, budget: *u32, sink: anytype) bool {
        const g = f.glyphData(gid);
        if (g.len < 10) return false;
        const nc = rdi16(g, 0);
        if (nc >= 0) return simpleOutline(g, @intCast(nc), xf, sink);
        if (depth >= 8) return false;
        var any = false;
        var off: u32 = 10;
        while (off + 4 <= g.len) {
            if (budget.* == 0) break;
            budget.* -= 1;
            const flags = rd16(g, off);
            const child = rd16(g, off + 2);
            off += 4;
            var dx: f32 = 0;
            var dy: f32 = 0;
            if (flags & 1 != 0) {
                if (flags & 2 != 0) {
                    dx = @floatFromInt(rdi16(g, off));
                    dy = @floatFromInt(rdi16(g, off + 2));
                }
                off += 4;
            } else {
                if (flags & 2 != 0) {
                    dx = @floatFromInt(@as(i8, @bitCast(rd8(g, off))));
                    dy = @floatFromInt(@as(i8, @bitCast(rd8(g, off + 1))));
                }
                off += 2;
            }
            var c: Xf = .{};
            if (flags & 0x8 != 0) {
                c.a = f2dot14(g, off);
                c.d = c.a;
                off += 2;
            } else if (flags & 0x40 != 0) {
                c.a = f2dot14(g, off);
                c.d = f2dot14(g, off + 2);
                off += 4;
            } else if (flags & 0x80 != 0) {
                c.a = f2dot14(g, off);
                c.b = f2dot14(g, off + 2);
                c.c = f2dot14(g, off + 4);
                c.d = f2dot14(g, off + 6);
                off += 8;
            }
            // combined = xf ∘ (c, translate(dx, dy))
            const m: Xf = .{
                .a = xf.a * c.a + xf.c * c.b,
                .b = xf.b * c.a + xf.d * c.b,
                .c = xf.a * c.c + xf.c * c.d,
                .d = xf.b * c.c + xf.d * c.d,
                .e = xf.a * dx + xf.c * dy + xf.e,
                .f = xf.b * dx + xf.d * dy + xf.f,
                .ident = false,
            };
            if (f.outlineRec(child, m, depth + 1, budget, sink)) any = true;
            if (flags & 0x20 == 0) break;
        }
        return any;
    }
};

fn f2dot14(t: []const u8, off: u32) f32 {
    return @as(f32, @floatFromInt(rdi16(t, off))) * (1.0 / 16384.0);
}

const Pt = struct { x: f32, y: f32 };

fn simpleOutline(g: []const u8, nc: u32, xf: Xf, sink: anytype) bool {
    if (nc == 0) return false;
    const end_pts: u32 = 10;
    const npts: u32 = @as(u32, rd16(g, end_pts + (nc - 1) * 2)) + 1;
    const ins_len: u32 = rd16(g, end_pts + nc * 2);
    const flags_off = end_pts + nc * 2 + 2 + ins_len;
    if (flags_off >= g.len) return false;

    // Pass 1: size of the flag and x-coordinate arrays.
    var fo = flags_off;
    var x_bytes: u32 = 0;
    var y_bytes: u32 = 0;
    var n: u32 = 0;
    while (n < npts) {
        if (fo >= g.len) return false;
        const fl = g[fo];
        fo += 1;
        var rep: u32 = 1;
        if (fl & 8 != 0) {
            rep += rd8(g, fo);
            fo += 1;
        }
        const xs: u32 = if (fl & 2 != 0) 1 else if (fl & 0x10 != 0) 0 else 2;
        const ys: u32 = if (fl & 4 != 0) 1 else if (fl & 0x20 != 0) 0 else 2;
        x_bytes += xs * rep;
        y_bytes += ys * rep;
        n += rep;
    }
    var xo = fo;
    var yo = xo + x_bytes;
    if (yo + y_bytes > g.len) return false;

    // Pass 2: stream points through the contour state machine.
    fo = flags_off;
    var fl: u8 = 0;
    var rep: u32 = 0;
    var x: i32 = 0;
    var y: i32 = 0;
    var pi: u32 = 0;
    var ci: u32 = 0;
    var any = false;
    while (ci < nc) : (ci += 1) {
        const end: u32 = rd16(g, end_pts + ci * 2);
        if (end < pi or end >= npts) return any;
        var started = false;
        var start: Pt = undefined;
        var first_off: ?Pt = null;
        var pending: ?Pt = null;
        var k: u32 = 0;
        while (pi <= end) : ({
            pi += 1;
            k += 1;
        }) {
            if (rep == 0) {
                fl = rd8(g, fo);
                fo += 1;
                if (fl & 8 != 0) {
                    rep = rd8(g, fo);
                    fo += 1;
                }
            } else rep -= 1;
            if (fl & 2 != 0) {
                const d: i32 = rd8(g, xo);
                xo += 1;
                x +%= if (fl & 0x10 != 0) d else -d;
            } else if (fl & 0x10 == 0) {
                x +%= rdi16(g, xo);
                xo += 2;
            }
            if (fl & 4 != 0) {
                const d: i32 = rd8(g, yo);
                yo += 1;
                y +%= if (fl & 0x20 != 0) d else -d;
            } else if (fl & 0x20 == 0) {
                y +%= rdi16(g, yo);
                yo += 2;
            }
            var p: Pt = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
            if (!xf.ident) p = .{ .x = xf.a * p.x + xf.c * p.y + xf.e, .y = xf.b * p.x + xf.d * p.y + xf.f };
            const on = fl & 1 != 0;
            if (!started) {
                if (on) {
                    start = p;
                } else if (k == 0) {
                    first_off = p;
                    continue;
                } else {
                    start = midPt(first_off.?, p);
                    pending = p;
                }
                sink.moveTo(start.x, start.y);
                started = true;
            } else if (on) {
                if (pending) |c| sink.quadTo(c.x, c.y, p.x, p.y) else sink.lineTo(p.x, p.y);
                pending = null;
            } else {
                if (pending) |c| {
                    const m = midPt(c, p);
                    sink.quadTo(c.x, c.y, m.x, m.y);
                }
                pending = p;
            }
        }
        if (!started) continue;
        if (first_off) |p| {
            if (pending) |c| {
                const m = midPt(c, p);
                sink.quadTo(c.x, c.y, m.x, m.y);
            }
            pending = p;
        }
        if (pending) |c| sink.quadTo(c.x, c.y, start.x, start.y);
        sink.close();
        any = true;
    }
    return any;
}

inline fn midPt(a: Pt, b: Pt) Pt {
    return .{ .x = (a.x + b.x) * 0.5, .y = (a.y + b.y) * 0.5 };
}

/// Encodes `cp` as UTF-8 into `out`, returning the length (1..4).
pub fn encodeUtf8(cp: u21, out: *[4]u8) u8 {
    if (cp < 0x80) {
        out[0] = @intCast(cp);
        return 1;
    } else if (cp < 0x800) {
        out[0] = @intCast(0xc0 | (cp >> 6));
        out[1] = @intCast(0x80 | (cp & 0x3f));
        return 2;
    } else if (cp < 0x10000) {
        out[0] = @intCast(0xe0 | (cp >> 12));
        out[1] = @intCast(0x80 | ((cp >> 6) & 0x3f));
        out[2] = @intCast(0x80 | (cp & 0x3f));
        return 3;
    }
    out[0] = @intCast(0xf0 | (cp >> 18));
    out[1] = @intCast(0x80 | ((cp >> 12) & 0x3f));
    out[2] = @intCast(0x80 | ((cp >> 6) & 0x3f));
    out[3] = @intCast(0x80 | (cp & 0x3f));
    return 4;
}

fn ScaleSink(comptime S: type) type {
    return struct {
        inner: S,
        s: f32,
        ox: f32,
        oy: f32,
        pub fn moveTo(self: *@This(), x: f32, y: f32) void {
            self.inner.moveTo(self.ox + x * self.s, self.oy - y * self.s);
        }
        pub fn lineTo(self: *@This(), x: f32, y: f32) void {
            self.inner.lineTo(self.ox + x * self.s, self.oy - y * self.s);
        }
        pub fn quadTo(self: *@This(), cx: f32, cy: f32, x: f32, y: f32) void {
            self.inner.quadTo(self.ox + cx * self.s, self.oy - cy * self.s, self.ox + x * self.s, self.oy - y * self.s);
        }
        pub fn cubicTo(self: *@This(), ax: f32, ay: f32, bx: f32, by: f32, x: f32, y: f32) void {
            self.inner.cubicTo(self.ox + ax * self.s, self.oy - ay * self.s, self.ox + bx * self.s, self.oy - by * self.s, self.ox + x * self.s, self.oy - y * self.s);
        }
        pub fn close(self: *@This()) void {
            self.inner.close();
        }
    };
}

/// Emits glyph `gid` scaled to `size_px` with its origin (baseline, pen position) at
/// (`origin_x`, `origin_y`) in a y-DOWN device space. `sink` is the same duck type as for
/// `Font.outline` (pass a pointer). No hinting. Returns false for empty glyphs.
pub fn emitGlyph(face: *const Font, gid: u16, size_px: f32, origin_x: f32, origin_y: f32, sink: anytype) bool {
    var s: ScaleSink(@TypeOf(sink)) = .{
        .inner = sink,
        .s = size_px / @as(f32, @floatFromInt(face.units_per_em)),
        .ox = origin_x,
        .oy = origin_y,
    };
    return face.outline(gid, &s);
}

/// Test hook: decodes a raw simple-glyph record (as stored in `glyf`).
pub fn testSimpleOutline(glyph: []const u8, sink: anytype) bool {
    const nc = rdi16(glyph, 0);
    if (nc <= 0) return false;
    return simpleOutline(glyph, @intCast(nc), .{}, sink);
}
