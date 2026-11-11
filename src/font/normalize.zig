//! HarfBuzz-style shaping normalisation (`hb-ot-shape-normalize`): every character is mapped to
//! a glyph, decomposing it when the font lacks the precomposed glyph and recomposing
//! base + mark sequences when the font has one ("composed diacritics" mode). Marks are put into
//! canonical order first. Data: `nfdata.zig` (canonical pairs of Latin / Greek / Cyrillic /
//! Vietnamese and the Hebrew / Arabic / Indic pairs below U+1100).
const std = @import("std");
const ttf = @import("ttf.zig");
const ot = @import("ot.zig");
const uni = @import("unicode.zig");
const nf = @import("nfdata.zig");
const Font = ttf.Font;
const Glyph = ot.Glyph;

/// Canonical decomposition of `cp` into two characters (one step), or null.
pub fn decompose(cp: u21) ?[2]u21 {
    if (cp < 0xc0 or cp > 0x1fff) return null;
    var lo: usize = 0;
    var hi: usize = nf.c.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (nf.c[mid] < cp) lo = mid + 1 else hi = mid;
    }
    if (lo >= nf.c.len or nf.c[lo] != cp) return null;
    return .{ nf.a[lo], nf.marks[nf.b[lo] & 0x7f] };
}

/// Canonical composition of `a` + `b` (composition exclusions honoured), or null.
pub fn compose(a: u21, b: u21) ?u21 {
    if (a > 0xffff or b > 0xffff) return null;
    var mi: usize = 0;
    while (mi < nf.marks.len and nf.marks[mi] != b) mi += 1;
    if (mi == nf.marks.len) return null;
    var lo: usize = 0;
    var hi: usize = nf.by_ab.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        const e = nf.by_ab[mid];
        const em: usize = nf.b[e] & 0x7f;
        if (em < mi or (em == mi and nf.a[e] < a)) lo = mid + 1 else hi = mid;
    }
    if (lo >= nf.by_ab.len) return null;
    const e = nf.by_ab[lo];
    if ((nf.b[e] & 0x7f) != mi or nf.a[e] != a or nf.b[e] & 0x80 != 0) return null;
    return nf.c[e];
}

pub const Mode = enum {
    /// Default shapers: keep what the font has, decompose otherwise, recompose.
    composed,
    /// Indic: always decompose first, recompose non-marks only.
    indic,
};

fn decomposeFor(mode: Mode, cp: u21) ?[2]u21 {
    if (mode == .indic) switch (cp) {
        0x0931, 0x09dc, 0x09dd, 0x0b94 => return null,
        else => {},
    };
    return decompose(cp);
}

fn composeFor(mode: Mode, a: u21, b: u21) ?u21 {
    if (mode == .indic) {
        if (uni.isMark(a)) return null;
        if (a == 0x09af and b == 0x09bc) return 0x09df;
    }
    return compose(a, b);
}

/// Sets gc / ccc / flags of a glyph from its code point (complex-text tables).
pub fn setUnicodeProps(gl: *Glyph, prev: u21) void {
    const cp = gl.cp;
    if (cp < 0x80) {
        // ASCII: letters / digits / other, never marks
        gl.uprops = if ((cp | 0x20) >= 'a' and (cp | 0x20) <= 'z') 5 else if (cp >= '0' and cp <= '9') 6 else 0;
        gl.ccc = 0;
        return;
    }
    var u: u8 = @intFromEnum(uni.gcOf(cp));
    if (cp == 0x200c) u |= Glyph.U_IGNORABLE | Glyph.U_ZWNJ;
    if (cp == 0x200d) u |= Glyph.U_IGNORABLE | Glyph.U_ZWJ;
    if (cp >= 0xfe00 and cp <= 0xfe0f) u |= Glyph.U_IGNORABLE;
    if (uni.isContinuation(prev, cp)) u |= Glyph.U_CONTINUATION;
    gl.uprops = u;
    gl.ccc = if (u & Glyph.U_GC == 1) uni.ccc(cp) else 0;
}

const Out = struct { cps: [8]u21 = undefined, gids: [8]u16 = undefined, n: usize = 0 };

fn push(o: *Out, cp: u21, gid: u16) void {
    if (o.n < o.cps.len) {
        o.cps[o.n] = cp;
        o.gids[o.n] = gid;
        o.n += 1;
    }
}

/// HarfBuzz `decompose()`: returns the number of characters emitted (0 = cannot decompose
/// with this font).
fn decomposeRec(font: *const Font, mode: Mode, shortest: bool, ab: u21, o: *Out, depth: u32) usize {
    if (depth > 6) return 0;
    const d = decomposeFor(mode, ab) orelse return 0;
    const b_gid = font.glyphIndex(d[1]);
    if (b_gid == 0) return 0;
    const a_gid = font.glyphIndex(d[0]);
    if (shortest and a_gid != 0) {
        push(o, d[0], a_gid);
        push(o, d[1], b_gid);
        return 2;
    }
    const r = decomposeRec(font, mode, shortest, d[0], o, depth + 1);
    if (r != 0) {
        push(o, d[1], b_gid);
        return r + 1;
    }
    if (a_gid != 0) {
        push(o, d[0], a_gid);
        push(o, d[1], b_gid);
        return 2;
    }
    return 0;
}

/// Hook called for every maximal run of marks [start, end) after canonical reordering.
pub const ReorderHook = *const fn (b: *ot.Buffer, start: usize, end: usize) void;

/// Maps the buffer's characters to glyphs of `font` (see module doc). Glyph `cp`, `uprops`
/// and `ccc` must be set on entry; they are updated for (de)composed characters.
pub fn normalize(font: *const Font, b: *ot.Buffer, mode: Mode, reorder: ?ReorderHook) !void {
    const shortest = mode != .indic;
    var any_marks = false;
    // round 1: decompose
    var i: usize = 0;
    while (i < b.g().len) {
        const gl = &b.g()[i];
        const cp = gl.cp;
        if (gl.uprops & Glyph.U_GC != 0 and gl.uprops & Glyph.U_GC <= 3) any_marks = true;
        // the caller may have looked the glyph up already
        const direct = if (gl.gid != 0) gl.gid else font.glyphIndex(cp);
        if (shortest and direct != 0) {
            gl.gid = direct;
            i += 1;
            continue;
        }
        var o: Out = .{};
        if (cp >= 0xc0 and decomposeRec(font, mode, shortest, cp, &o, 0) != 0) {
            const proto = gl.*;
            var k: usize = 0;
            while (k < o.n) : (k += 1) {
                if (k != 0) try b.insert(i + k, proto);
                const x = &b.g()[i + k];
                x.cp = o.cps[k];
                x.gid = o.gids[k];
                setUnicodeProps(x, if (k == 0) 0 else o.cps[k - 1]);
                if (k != 0) x.uprops |= Glyph.U_CONTINUATION;
            }
            any_marks = true;
            i += o.n;
            continue;
        }
        if (direct != 0) {
            gl.gid = direct;
        } else if (cp == 0x2011 and font.glyphIndex(0x2010) != 0) {
            gl.gid = font.glyphIndex(0x2010);
        } else switch (cp) {
            // space fallback (widths are not adjusted)
            0xa0, 0x2000...0x200a, 0x202f, 0x205f, 0x3000 => gl.gid = font.glyphIndex(' '),
            else => gl.gid = 0,
        }
        i += 1;
    }
    if (!any_marks) return;

    // round 2: canonical order of marks
    const gs = b.g();
    i = 0;
    while (i < gs.len) {
        if (gs[i].ccc == 0) {
            i += 1;
            continue;
        }
        var end = i + 1;
        while (end < gs.len and gs[end].ccc != 0) end += 1;
        if (end - i <= 32) {
            // stable insertion sort, merging clusters over whatever moved
            var j = i + 1;
            while (j < end) : (j += 1) {
                var k = j;
                while (k > i and gs[k - 1].ccc > gs[j].ccc) k -= 1;
                if (k == j) continue;
                b.mergeClusters(k, j + 1);
                const t = gs[j];
                std.mem.copyBackwards(Glyph, gs[k + 1 .. j + 1], gs[k..j]);
                gs[k] = t;
            }
            if (reorder) |hook| hook(b, i, end);
        }
        i = end;
    }

    // round 3: recompose
    var starter: usize = 0;
    var out: usize = 1;
    i = 1;
    while (i < gs.len) : (i += 1) {
        const cur = gs[i];
        const g3 = cur.uprops & Glyph.U_GC;
        if (g3 >= 1 and g3 <= 3 and (starter == out - 1 or gs[out - 1].ccc < cur.ccc)) {
            if (composeFor(mode, gs[starter].cp, cur.cp)) |composed| {
                const gid = font.glyphIndex(composed);
                if (gid != 0) {
                    var cl = @min(gs[starter].cluster, cur.cluster);
                    for (gs[starter..out]) |x| cl = @min(cl, x.cluster);
                    for (gs[starter..out]) |*x| x.cluster = cl;
                    gs[starter].cp = composed;
                    gs[starter].gid = gid;
                    const keep = gs[starter].uprops & Glyph.U_CONTINUATION;
                    setUnicodeProps(&gs[starter], 0);
                    gs[starter].uprops |= keep;
                    continue;
                }
            }
        }
        gs[out] = cur;
        if (cur.ccc == 0) starter = out;
        out += 1;
    }
    b.list.shrinkRetainingCapacity(out);
}

test "compose / decompose tables" {
    const t = std.testing;
    try t.expectEqual([2]u21{ 'e', 0x301 }, decompose(0xe9).?);
    try t.expectEqual([2]u21{ 0xea, 0x301 }, decompose(0x1ebf).?); // ế -> ê + acute
    try t.expectEqual(@as(?u21, 0xe9), compose('e', 0x301));
    try t.expectEqual(@as(?u21, 0x1ebf), compose(0xea, 0x301));
    try t.expectEqual(@as(?u21, 0x1ec7), compose(0x1eb9, 0x302)); // ẹ + circumflex -> ệ
    try t.expectEqual(@as(?u21, null), compose('q', 0x301));
    try t.expectEqual(@as(?u21, null), compose(0x915, 0x93c)); // क़ is a composition exclusion
    try t.expectEqual([2]u21{ 0x915, 0x93c }, decompose(0x958).?);
    try t.expectEqual(@as(?[2]u21, null), decompose('a'));
    // every table entry round-trips unless excluded
    for (nf.c, 0..) |c, k| {
        const d = decompose(c).?;
        const back = compose(d[0], d[1]);
        if (nf.b[k] & 0x80 != 0) try t.expectEqual(@as(?u21, null), back) else try t.expectEqual(@as(?u21, c), back);
    }
}
