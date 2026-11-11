//! OpenType layout subset: script/feature/lookup lists, coverage, class definitions,
//! GPOS pair positioning (type 2, via type 9 extensions) and GSUB single (1), ligature (4),
//! context (5) and chaining-context (6) format 3 substitutions. Everything is bounds-checked; malformed data
//! simply yields "no adjustment".
const std = @import("std");
const ttf = @import("ttf.zig");
const rd16 = ttf.rd16;
const rdi16 = ttf.rdi16;
const rd32 = ttf.rd32;
const tail = ttf.tail;

pub const FeatureSel = struct { tag: u32, flag: u16 };

const tag_latn: u32 = 0x6c61746e;
const tag_dflt: u32 = 0x44464c54;

/// Collects the lookup indices of the given features from the default LangSys of the `latn`
/// script (else `DFLT`, else the first script). Result is sorted ascending and de-duplicated;
/// `flag` of the selecting feature is OR-ed into the stored index (lookups > 0x7fff are dropped).
pub fn collectLookups(table: []const u8, feats: []const FeatureSel, out: []u16) usize {
    if (table.len < 10) return 0;
    const scripts = tail(table, rd16(table, 4));
    const features = tail(table, rd16(table, 6));
    const n_scripts: u32 = rd16(scripts, 0);
    if (n_scripts == 0) return 0;
    var script_off: u32 = rd16(scripts, 2 + 4);
    var rank: u32 = 0;
    var i: u32 = 0;
    while (i < n_scripts) : (i += 1) {
        const t = rd32(scripts, 2 + i * 6);
        const r: u32 = if (t == tag_latn) 2 else if (t == tag_dflt) 1 else 0;
        if (r > rank) {
            rank = r;
            script_off = rd16(scripts, 2 + i * 6 + 4);
        }
    }
    const script = tail(scripts, script_off);
    var lang_off: u32 = rd16(script, 0);
    if (lang_off == 0) {
        if (rd16(script, 2) == 0) return 0;
        lang_off = rd16(script, 4 + 4);
    }
    const lang = tail(script, lang_off);
    const n_feat: u32 = rd16(lang, 4);
    const total_feat: u32 = rd16(features, 0);
    var n: usize = 0;
    i = 0;
    while (i < n_feat) : (i += 1) {
        const fi: u32 = rd16(lang, 6 + i * 2);
        if (fi >= total_feat) continue;
        const ftag = rd32(features, 2 + fi * 6);
        for (feats) |sel| {
            if (sel.tag != ftag) continue;
            const feat = tail(features, rd16(features, 2 + fi * 6 + 4));
            const nl: u32 = rd16(feat, 2);
            var k: u32 = 0;
            while (k < nl) : (k += 1) {
                if (6 + k * 2 > feat.len) break;
                const li = rd16(feat, 4 + k * 2);
                if (li > 0x7fff) continue;
                // sorted insert, de-duplicated (non-discretionary wins)
                var pos: usize = 0;
                while (pos < n and (out[pos] & 0x7fff) < li) pos += 1;
                if (pos < n and (out[pos] & 0x7fff) == li) {
                    out[pos] &= li | sel.flag;
                    continue;
                }
                if (n >= out.len) continue;
                var m = n;
                while (m > pos) : (m -= 1) out[m] = out[m - 1];
                out[pos] = li | sel.flag;
                n += 1;
            }
        }
    }
    return n;
}

/// Coverage index of `gid`, or null.
pub fn coverage(t: []const u8, gid: u16) ?u32 {
    const format = rd16(t, 0);
    const count: u32 = rd16(t, 2);
    var lo: u32 = 0;
    var hi: u32 = count;
    if (format == 1) {
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            const g = rd16(t, 4 + mid * 2);
            if (g < gid) lo = mid + 1 else hi = mid;
        }
        if (lo < count and 6 + lo * 2 <= t.len and rd16(t, 4 + lo * 2) == gid) return lo;
    } else if (format == 2) {
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (rd16(t, 4 + mid * 6 + 2) < gid) lo = mid + 1 else hi = mid;
        }
        const r = 4 + lo * 6;
        if (lo < count and r + 6 <= t.len and rd16(t, r) <= gid and rd16(t, r + 2) >= gid)
            return @as(u32, rd16(t, r + 4)) + (gid - rd16(t, r));
    }
    return null;
}

pub fn classOf(t: []const u8, gid: u16) u16 {
    const format = rd16(t, 0);
    if (format == 1) {
        const start = rd16(t, 2);
        if (gid < start or gid - start >= rd16(t, 4)) return 0;
        return rd16(t, 6 + @as(u32, gid - start) * 2);
    } else if (format == 2) {
        const count: u32 = rd16(t, 2);
        var lo: u32 = 0;
        var hi: u32 = count;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (rd16(t, 4 + mid * 6 + 2) < gid) lo = mid + 1 else hi = mid;
        }
        const r = 4 + lo * 6;
        if (lo < count and r + 6 <= t.len and rd16(t, r) <= gid) return rd16(t, r + 4);
    }
    return 0;
}

const Lookup = struct { t: []const u8, kind: u16, count: u32 };

fn lookupAt(table: []const u8, index: u16) Lookup {
    const list = tail(table, rd16(table, 8));
    if (index >= rd16(list, 0)) return .{ .t = &.{}, .kind = 0, .count = 0 };
    const t = tail(list, rd16(list, 2 + @as(u32, index) * 2));
    return .{ .t = t, .kind = rd16(t, 0), .count = rd16(t, 4) };
}

/// Resolves subtable `i` of a lookup, following extension subtables (`ext_type` 9 for GPOS,
/// 7 for GSUB). Returns the effective lookup type through `kind`.
fn subtable(l: Lookup, i: u32, ext_type: u16, kind: *u16) []const u8 {
    var st = tail(l.t, rd16(l.t, 6 + i * 2));
    kind.* = l.kind;
    if (l.kind == ext_type) {
        if (rd16(st, 0) != 1) return &.{};
        kind.* = rd16(st, 2);
        st = tail(st, rd32(st, 4));
    }
    return st;
}

/// Bloom-style glyph set (HarfBuzz "set digest"): a cheap may-contain test that lets the shaper
/// skip lookups that cannot apply to a glyph. Never gives false negatives.
pub const Digest = struct {
    m: [3]u64 = .{ 0, 0, 0 },
    const shifts = [3]u4{ 0, 4, 9 };

    pub inline fn mayHave(d: *const Digest, g: u16) bool {
        return (d.m[0] >> @as(u6, @truncate(g))) & (d.m[1] >> @as(u6, @truncate(g >> 4))) & (d.m[2] >> @as(u6, @truncate(g >> 9))) & 1 != 0;
    }
    fn addRange(d: *Digest, a: u16, b: u16) void {
        if (b < a) return;
        for (shifts, 0..) |s, i| {
            const lo: u32 = a >> s;
            const hi: u32 = b >> s;
            if (hi - lo >= 63) {
                d.m[i] = ~@as(u64, 0);
            } else {
                var v = lo;
                while (v <= hi) : (v += 1) d.m[i] |= @as(u64, 1) << @as(u6, @truncate(v));
            }
        }
    }
    fn addCoverage(d: *Digest, t: []const u8) void {
        const format = rd16(t, 0);
        var n: u32 = rd16(t, 2);
        if (format == 1) {
            n = @min(n, @as(u32, @intCast(t.len / 2)));
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                const g = rd16(t, 4 + i * 2);
                d.addRange(g, g);
            }
        } else if (format == 2) {
            n = @min(n, @as(u32, @intCast(t.len / 6)));
            var i: u32 = 0;
            while (i < n) : (i += 1) d.addRange(rd16(t, 4 + i * 6), rd16(t, 4 + i * 6 + 2));
        }
    }
};

/// Digest of the first-glyph coverages of every supported subtable of a lookup
/// (`ext_type`: 9 for GPOS, 7 for GSUB).
pub fn lookupDigest(table: []const u8, index: u16, ext_type: u16) Digest {
    var d: Digest = .{};
    const l = lookupAt(table, index);
    var i: u32 = 0;
    while (i < l.count) : (i += 1) {
        var kind: u16 = 0;
        const st = subtable(l, i, ext_type, &kind);
        const format = rd16(st, 0);
        var cov: u32 = 2;
        if (ext_type == 7) {
            if (kind == 6 and format == 3) {
                cov = 4 + @as(u32, rd16(st, 2)) * 2 + 2;
            } else if (kind == 5 and format == 3) {
                cov = 6;
            } else if (kind != 1 and kind != 4) continue;
        } else if (kind != 2) continue;
        d.addCoverage(tail(st, rd16(st, cov)));
    }
    return d;
}

// ---------------------------------------------------------------------- GPOS

pub const PairAdjust = struct { adv1: i32 = 0, place1: i32 = 0, adv2: i32 = 0, place2: i32 = 0 };

inline fn valueSize(format: u16) u32 {
    return @as(u32, @popCount(format)) * 2;
}

fn readValue(t: []const u8, off: u32, format: u16, place: *i32, adv: *i32) void {
    var o = off;
    if (format & 1 != 0) {
        place.* += rdi16(t, o);
        o += 2;
    }
    if (format & 2 != 0) o += 2;
    if (format & 4 != 0) adv.* += rdi16(t, o);
}

/// Applies one GPOS lookup to the pair (first matching subtable wins), accumulating into `r`.
pub fn pairLookup(gpos: []const u8, index: u16, left: u16, right: u16, r: *PairAdjust) void {
    const l = lookupAt(gpos, index);
    var i: u32 = 0;
    while (i < l.count) : (i += 1) {
        var kind: u16 = 0;
        const st = subtable(l, i, 9, &kind);
        if (kind != 2 or st.len < 10) continue;
        const format = rd16(st, 0);
        const ci = coverage(tail(st, rd16(st, 2)), left) orelse continue;
        const vf1 = rd16(st, 4);
        const vf2 = rd16(st, 6);
        const s1 = valueSize(vf1);
        const s2 = valueSize(vf2);
        if (format == 1) {
            if (ci >= rd16(st, 8)) continue;
            const set = tail(st, rd16(st, 10 + ci * 2));
            const rec = 2 + s1 + s2;
            const count: u32 = rd16(set, 0);
            var lo: u32 = 0;
            var hi: u32 = count;
            while (lo < hi) {
                const mid = (lo + hi) / 2;
                if (rd16(set, 2 + mid * rec) < right) lo = mid + 1 else hi = mid;
            }
            const p = 2 + lo * rec;
            if (lo >= count or p + rec > set.len or rd16(set, p) != right) continue;
            readValue(set, p + 2, vf1, &r.place1, &r.adv1);
            readValue(set, p + 2 + s1, vf2, &r.place2, &r.adv2);
            return;
        } else if (format == 2) {
            const c1: u32 = classOf(tail(st, rd16(st, 8)), left);
            const c2: u32 = classOf(tail(st, rd16(st, 10)), right);
            const n1: u32 = rd16(st, 12);
            const n2: u32 = rd16(st, 14);
            if (c1 >= n1 or c2 >= n2) continue;
            const p = 16 +| (c1 * n2 + c2) *| (s1 + s2);
            if (p > st.len or s1 + s2 > st.len - p) continue;
            readValue(st, p, vf1, &r.place1, &r.adv1);
            readValue(st, p + s1, vf2, &r.place2, &r.adv2);
            return;
        }
    }
}

// ---------------------------------------------------------------------- GSUB

/// Glyph buffer the substitutions operate on: parallel `gids` / `clusters` slices plus a
/// length that shrinks when ligatures form.
pub const GlyphBuf = struct {
    gids: []u16,
    clusters: []u32,
    len: usize,

    fn ligate(b: *GlyphBuf, i: usize, n: usize, lig: u16) void {
        b.gids[i] = lig;
        if (n <= 1) return;
        std.mem.copyForwards(u16, b.gids[i + 1 .. b.len - (n - 1)], b.gids[i + n .. b.len]);
        std.mem.copyForwards(u32, b.clusters[i + 1 .. b.len - (n - 1)], b.clusters[i + n .. b.len]);
        b.len -= n - 1;
    }
};

/// Applies GSUB lookup `index` over the whole buffer. `digest` = `lookupDigest(gsub, index, 7)`.
pub fn substLookup(gsub: []const u8, index: u16, digest: *const Digest, b: *GlyphBuf) void {
    const l = lookupAt(gsub, index);
    if (l.count == 0) return;
    var i: usize = 0;
    while (i < b.len) {
        if (!digest.mayHave(b.gids[i])) {
            i += 1;
            continue;
        }
        i += applyAt(gsub, l, b, i, 0);
    }
}

/// Tries the subtables of `l` at position `i`; returns how many glyphs to advance (>= 1).
fn applyAt(gsub: []const u8, l: Lookup, b: *GlyphBuf, i: usize, depth: u32) usize {
    const gid = b.gids[i];
    var s: u32 = 0;
    while (s < l.count) : (s += 1) {
        var kind: u16 = 0;
        const st = subtable(l, s, 7, &kind);
        if (st.len < 6) continue;
        const format = rd16(st, 0);
        switch (kind) {
            1 => {
                const ci = coverage(tail(st, rd16(st, 2)), gid) orelse continue;
                if (format == 1) {
                    b.gids[i] = gid +% rd16(st, 4);
                } else if (format == 2 and ci < rd16(st, 4)) {
                    b.gids[i] = rd16(st, 6 + ci * 2);
                } else continue;
                return 1;
            },
            4 => {
                if (format != 1) continue;
                const ci = coverage(tail(st, rd16(st, 2)), gid) orelse continue;
                if (ci >= rd16(st, 4)) continue;
                const set = tail(st, rd16(st, 6 + ci * 2));
                const nl: u32 = rd16(set, 0);
                var k: u32 = 0;
                while (k < nl) : (k += 1) {
                    const lig = tail(set, rd16(set, 2 + k * 2));
                    const nc: u32 = rd16(lig, 2);
                    if (nc == 0 or lig.len < 4 or i + nc > b.len) continue;
                    var c: u32 = 1;
                    while (c < nc and b.gids[i + c] == rd16(lig, 4 + (c - 1) * 2)) c += 1;
                    if (c < nc) continue;
                    b.ligate(i, nc, rd16(lig, 0));
                    return 1;
                }
            },
            5, 6 => {
                // (Chaining) context substitution, format 3 (coverage based) only.
                if (format != 3 or depth != 0) continue;
                // layout: [nb, back covs] ni, input covs, [nla, lookahead covs], nrec, records
                var nb: u32 = 0;
                var in_off: u32 = 0; // offset of the input glyph count
                var ni: u32 = undefined;
                var la_off: u32 = 0;
                var nla: u32 = 0;
                var rec_off: u32 = undefined; // offset of the record count
                if (kind == 6) {
                    nb = rd16(st, 2);
                    in_off = 4 + nb * 2;
                    ni = rd16(st, in_off);
                    la_off = in_off + 2 + ni * 2;
                    nla = rd16(st, la_off);
                    rec_off = la_off + 2 + nla * 2;
                } else {
                    // type 5: glyphCount, seqLookupCount, coverages, records
                    ni = rd16(st, 2);
                    in_off = 4; // coverages start at in_off + 2
                    rec_off = 4;
                }
                const recs: u32 = if (kind == 6) rec_off + 2 else 6 + ni * 2;
                if (ni == 0 or recs > st.len or i < nb or i + ni + nla > b.len) continue;
                var ok = true;
                var k: u32 = 0;
                while (ok and k < ni) : (k += 1)
                    ok = coverage(tail(st, rd16(st, in_off + 2 + k * 2)), b.gids[i + k]) != null;
                k = 0;
                while (ok and k < nb) : (k += 1)
                    ok = coverage(tail(st, rd16(st, 4 + k * 2)), b.gids[i - 1 - k]) != null;
                k = 0;
                while (ok and k < nla) : (k += 1)
                    ok = coverage(tail(st, rd16(st, la_off + 2 + k * 2)), b.gids[i + ni + k]) != null;
                if (!ok) continue;
                const nrec: u32 = rd16(st, rec_off);
                var consumed: usize = ni;
                k = 0;
                while (k < nrec) : (k += 1) {
                    const seq: usize = rd16(st, recs + k * 4);
                    const nested = lookupAt(gsub, rd16(st, recs + 2 + k * 4));
                    if (seq >= consumed or i + seq >= b.len) continue;
                    const before = b.len;
                    _ = applyAt(gsub, nested, b, i + seq, depth + 1);
                    consumed -= @min(before - b.len, consumed - 1);
                }
                return @max(consumed, 1);
            },
            else => {},
        }
    }
    return 1;
}
