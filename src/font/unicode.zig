//! UTF-8 decoding and a compact UAX #14 line-break subset with Chromium's ASCII overrides
//! (takumi = Blink's line breaker over ICU4X UAX #14 + Chromium's `kLineBreakTable`).
const std = @import("std");

pub const Decoded = struct { cp: u21, len: u8 };

/// Decodes one scalar value at `s[i..]` (`i < s.len`). Invalid, overlong, surrogate or
/// truncated sequences yield U+FFFD and consume a single byte.
pub fn decodeUtf8(s: []const u8, i: usize) Decoded {
    const b0 = s[i];
    if (b0 < 0x80) return .{ .cp = b0, .len = 1 };
    const bad: Decoded = .{ .cp = 0xfffd, .len = 1 };
    var need: u8 = undefined;
    var cp: u32 = undefined;
    var min: u32 = undefined;
    if (b0 & 0xe0 == 0xc0) {
        need = 1;
        cp = b0 & 0x1f;
        min = 0x80;
    } else if (b0 & 0xf0 == 0xe0) {
        need = 2;
        cp = b0 & 0x0f;
        min = 0x800;
    } else if (b0 & 0xf8 == 0xf0) {
        need = 3;
        cp = b0 & 0x07;
        min = 0x10000;
    } else return bad;
    if (s.len - i <= need) return bad;
    var k: u8 = 1;
    while (k <= need) : (k += 1) {
        const b = s[i + k];
        if (b & 0xc0 != 0x80) return bad;
        cp = (cp << 6) | (b & 0x3f);
    }
    if (cp < min or cp > 0x10ffff or (cp >= 0xd800 and cp < 0xe000)) return bad;
    return .{ .cp = @intCast(cp), .len = need + 1 };
}

/// Characters that never produce a glyph or an advance (ZWSP, ZWJ/ZWNJ, marks for direction,
/// word joiner, BOM, soft hyphen, variation selectors, ...).
pub fn isZeroWidth(cp: u21) bool {
    return switch (cp) {
        0xad, 0x34f, 0x61c, 0x180e, 0x200b...0x200f, 0x2028...0x202e, 0x2060...0x2064, 0xfeff, 0xfe00...0xfe0f => true,
        else => false,
    };
}

/// Combining marks: zero advance, never separated from their base.
pub fn isCombining(cp: u21) bool {
    return switch (cp) {
        0x300...0x36f, 0x1ab0...0x1aff, 0x1dc0...0x1dff, 0x20d0...0x20ff, 0xfe20...0xfe2f => true,
        else => false,
    };
}

pub const Class = enum(u8) { al, sp, gl, ba, b2, zw, op, cl, qu, ex, is, ns, id, in, cm };

pub fn lbClass(cp: u21) Class {
    return switch (cp) {
        ' ' => .sp,
        '\t', '-', 0xad, 0x2000...0x2006, 0x2008...0x200a, 0x2010, 0x2012, 0x2013, 0x3000 => .ba,
        '!', '?', 0xff01, 0xff1f => .ex,
        '"', '\'', 0xab, 0xbb, 0x2018...0x201f, 0x2039, 0x203a => .qu,
        '(', '[', '{', 0x301d, 0xff08, 0xff3b, 0xff5b, 0xff5f, 0xff62 => .op,
        ')', ']', '}', 0x3001, 0x3002, 0x301e, 0x301f, 0xff09, 0xff3d, 0xff5d, 0xff60, 0xff63, 0xff0c, 0xff0e, 0xff61, 0xff64 => .cl,
        ',', '.', ':', ';', '/' => .is,
        0xa0, 0x2007, 0x2011, 0x202f, 0x2060, 0xfeff => .gl,
        0x300...0x36f, 0x1ab0...0x1aff, 0x1dc0...0x1dff, 0x20d0...0x20ff, 0xfe00...0xfe0f, 0xfe20...0xfe2f, 0x200c, 0x200d => .cm,
        0x200b => .zw,
        0x2014 => .b2,
        0x2024...0x2026 => .in,
        0x3008...0x3011, 0x3014...0x301b => if (cp & 1 == 0) .op else .cl,
        0x3005, 0x301c, 0x303b, 0x309b...0x309e, 0x30a0, 0x30fb...0x30fe, 0xff1a, 0xff1b, 0xff65, 0xff70, 0xff9e, 0xff9f => .ns,
        // small kana (CJ, resolved to NS under the default strict rules)
        0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308e, 0x3095, 0x3096 => .ns,
        0x30a1, 0x30a3, 0x30a5, 0x30a7, 0x30a9, 0x30c3, 0x30e3, 0x30e5, 0x30e7, 0x30ee, 0x30f5, 0x30f6 => .ns,
        0x1100...0x11ff, 0x2e80...0x2fff, 0x3040, 0x3042, 0x3044, 0x3046, 0x3048, 0x304a...0x3062, 0x3064...0x3082, 0x3084, 0x3086, 0x3088...0x308d, 0x308f...0x3094 => .id,
        0x30a2, 0x30a4, 0x30a6, 0x30a8, 0x30aa...0x30c2, 0x30c4...0x30e2, 0x30e4, 0x30e6, 0x30e8...0x30ed, 0x30ef...0x30f4, 0x30f7...0x30fa, 0x30ff => .id,
        0x3100...0xa4cf, 0xac00...0xd7a3, 0xf900...0xfaff, 0xfe30...0xfe4f => .id,
        0xff02...0xff07, 0xff0a, 0xff0b, 0xff0d, 0xff0f...0xff19, 0xff1c...0xff1e, 0xff20...0xff3a, 0xff3c, 0xff3e...0xff5a, 0xff5c, 0xff5e, 0xff66...0xff6f, 0xff71...0xff9d, 0xffa0...0xffef => .id,
        0x1f000...0x1faff, 0x20000...0x3fffd => .id,
        else => .al,
    };
}

pub const WordBreak = enum { normal, break_all, keep_all };

/// Chromium's `kLineBreakTable` for a pair of printable ASCII characters ('!'..DEL).
fn asciiBreak(b: u21, a: u21) bool {
    switch (b) {
        '$', '\'', '(', '/', '0'...'9', '<', '@', 'A'...'Z', '[', '^', '_', '`', 'a'...'z', '{', 0x7f => return false,
        else => {},
    }
    switch (a) {
        '}', ']', '?', ';', ':', '/', '.', ',', ')', '!' => return false,
        else => {},
    }
    if (b == '-') return a != '$';
    if (b == '?') return a != '"' and a != '\'';
    return a == '{' or a == '[' or a == '<' or a == '(';
}

fn isAsciiAlnum(c: u21) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn uaxBreak(b: u21, a: u21, mode: WordBreak) bool {
    if (b == 0x200d or (a >= 0x1f3fb and a <= 0x1f3ff)) return false; // emoji ZWJ / modifier sequences
    var cb = lbClass(b);
    var ca = lbClass(a);
    if (cb == .sp) return ca != .sp;
    if (ca == .sp) return false;
    if (cb == .zw) return true;
    if (ca == .zw or ca == .cm or ca == .gl or cb == .gl) return false;
    if (cb == .cm) cb = .al;
    if (mode == .break_all) {
        if (cb == .al) cb = .id;
        if (ca == .al) ca = .id;
    }
    switch (ca) {
        .cl, .ex, .ns, .in, .is, .qu, .ba => return false,
        else => {},
    }
    if (cb == .op or cb == .qu) return false;
    if (cb == .ba) return true;
    if (cb == .b2) return ca != .b2;
    if (ca == .b2) return true;
    if (cb == .id or ca == .id) {
        if (mode == .keep_all and (cb == .id or cb == .al) and (ca == .id or ca == .al)) return false;
        // LB30: no break between a letter and a non-East-Asian opening bracket, or after ')'
        if (ca == .op and a < 0x3000 and cb == .al) return false;
        return true;
    }
    if (cb == .is) return false;
    if (cb == .cl) return ca == .op or b >= 0x3000;
    if (cb == .ex or cb == .ns or cb == .in) return ca == .al and b >= 0x80;
    if (ca == .op) return a >= 0x3000;
    return false;
}

/// Whether a soft wrap opportunity exists between `b` and `a` (`bb` = the character before `b`,
/// 0 if none).
pub fn canBreak(bb: u21, b: u21, a: u21, mode: WordBreak) bool {
    if (b == ' ') return a != ' ';
    if (isAsciiPair(b, a)) {
        const t = asciiPairBreak(bb, b, a);
        if (mode != .break_all) return t;
        return t or uaxBreak(b, a, mode);
    }
    return uaxBreak(b, a, mode);
}

/// Both characters are printable ASCII: Blink decides with its own table instead of UAX #14.
pub inline fn isAsciiPair(b: u21, a: u21) bool {
    return b > ' ' and b < 0x80 and a > ' ' and a < 0x80;
}

/// Chromium's rule for a printable-ASCII pair (`bb` = the character before `b`).
pub fn asciiPairBreak(bb: u21, b: u21, a: u21) bool {
    if (b == '-' and a >= '0' and a <= '9') return isAsciiAlnum(bb);
    return asciiBreak(b, a);
}

// ------------------------------------------------------------------------------------------
// Complex-text properties (generated tables in ucd.zig). Nothing below is referenced by the
// simple (`complex = false`) shaping path, so the tables are dropped from such builds.
// ------------------------------------------------------------------------------------------

const ucd = @import("ucd.zig");
pub const Lb = ucd.Lb;
pub const Bidi = ucd.Bidi;
pub const Gc = ucd.Gc;

inline fn mk(lb: Lb, ea: u1, bd: Bidi, g: Gc) u16 {
    return @as(u16, @intFromEnum(lb)) | (@as(u16, ea) << 6) | (@as(u16, @intFromEnum(bd)) << 7) | (@as(u16, @intFromEnum(g)) << 12);
}

/// Packed properties of `cp`: lb | east_asian << 6 | bidi << 7 | gc << 12.
pub fn props(cp: u21) u16 {
    if (cp < ucd.table_limit) {
        const blk: u32 = ucd.props_s1[cp >> ucd.props_shift];
        return ucd.props_vals[ucd.props_s2[(blk << ucd.props_shift) | (cp & ((1 << ucd.props_shift) - 1))]];
    }
    return switch (cp) {
        0x1f1e6...0x1f1ff => mk(.ri, 0, .l, .other),
        0x1f3fb...0x1f3ff => mk(.em, 1, .on, .other),
        0x1f000...0x1f1e5, 0x1f200...0x1f3fa, 0x1f400...0x1faff => mk(.eb, 1, .on, .other),
        0x20000...0x3fffd => mk(.id, 1, .l, .letter),
        0xe0001, 0xe0020...0xe007f => mk(.cm, 0, .bn, .cf),
        0xe0100...0xe01ef => mk(.cm, 0, .nsm, .mn),
        0x10d00...0x10d3f, 0x1ec70...0x1ecbf, 0x1ed00...0x1ed4f, 0x1ee00...0x1eeff => mk(.al, 0, .al, .letter),
        0x10800...0x10cff, 0x10d40...0x10fff, 0x1e800...0x1ec6f, 0x1ecc0...0x1ecff, 0x1ed50...0x1edff, 0x1ef00...0x1efff => mk(.al, 0, .r, .letter),
        else => mk(.al, 0, .l, .letter),
    };
}
pub inline fn bidiClass(cp: u21) Bidi {
    return @enumFromInt(@as(u5, @truncate(props(cp) >> 7)));
}
pub inline fn gcOf(cp: u21) Gc {
    return @enumFromInt(@as(u3, @truncate(props(cp) >> 12)));
}
pub inline fn isMark(cp: u21) bool {
    const g = gcOf(cp);
    return g == .mn or g == .mc or g == .me;
}

/// Script id (index into `ucd.script_iso`); `ucd.sc_*` name the ones the shaper cares about.
pub fn script(cp: u21) u8 {
    if (cp < 0x80) return if ((cp | 0x20) >= 'a' and (cp | 0x20) <= 'z') ucd.sc_latin else ucd.sc_common;
    if (cp >= 0x10000) return if (cp >= 0x20000 and cp < 0xe0000) ucd.sc_han else if (cp >= 0x1f000 and cp < 0x1fb00) ucd.sc_common else ucd.sc_unknown;
    var lo: usize = 0;
    var hi: usize = ucd.script_start.len;
    while (hi - lo > 1) {
        const mid = (lo + hi) / 2;
        if (ucd.script_start[mid] <= cp) lo = mid else hi = mid;
    }
    return ucd.script_val[lo];
}

/// HarfBuzz-modified canonical combining class (0 for starters and everything outside the BMP).
pub fn ccc(cp: u21) u8 {
    if (cp < 0x300 or cp > 0xffff) return 0;
    var lo: usize = 0;
    var hi: usize = ucd.ccc_start.len;
    while (hi - lo > 1) {
        const mid = (lo + hi) / 2;
        if (ucd.ccc_start[mid] <= cp) lo = mid else hi = mid;
    }
    return if (cp - ucd.ccc_start[lo] <= ucd.ccc_len[lo]) ucd.ccc_val[lo] else 0;
}

pub const Joining = enum(u3) { u = 0, l = 1, r = 2, d = 3, t = 7 };

/// Arabic joining type (ArabicShaping.txt for U+0600..U+08FF; elsewhere T for marks / format
/// characters, D for ZWJ and U otherwise).
pub fn joiningType(cp: u21) Joining {
    if (cp >= 0x600 and cp < 0x900) {
        const o = cp - 0x600;
        const nib = (ucd.joining[o >> 1] >> @as(u3, @intCast((o & 1) * 4))) & 15;
        if (nib != 0) return @enumFromInt(@as(u3, @intCast(nib - 1)));
    } else if (cp == 0x200d) return .d else if (cp == 0x200c) return .u;
    return switch (gcOf(cp)) {
        .mn, .me, .cf => .t,
        else => .u,
    };
}

/// Bidi mirrored counterpart of `cp` (`cp` itself when it has none).
pub fn mirror(cp: u21) u21 {
    if (cp > 0xffff) return cp;
    for (ucd.mirror) |p| {
        if (p[0] == cp) return p[1];
        if (p[1] == cp) return p[0];
    }
    return cp;
}

pub const Bracket = struct { open: bool, pair: u21 };

/// Bidi paired bracket lookup (N0), with the canonical equivalents U+2329/232A = U+3008/3009 folded.
pub fn bracket(cp_in: u21) ?Bracket {
    if (cp_in < 0x0f3a) return switch (cp_in) {
        '(' => .{ .open = true, .pair = ')' },
        ')' => .{ .open = false, .pair = '(' },
        '[' => .{ .open = true, .pair = ']' },
        ']' => .{ .open = false, .pair = '[' },
        '{' => .{ .open = true, .pair = '}' },
        '}' => .{ .open = false, .pair = '{' },
        else => null,
    };
    const cp: u21 = if (cp_in == 0x2329) 0x3008 else if (cp_in == 0x232a) 0x3009 else cp_in;
    if (cp > 0xffff) return null;
    for (ucd.brackets) |p| {
        if (p[0] == cp) return .{ .open = true, .pair = p[1] };
        if (p[1] == cp) return .{ .open = false, .pair = p[0] };
    }
    return null;
}

pub fn isExtPict(cp: u21) bool {
    if (cp < 0xa9) return false;
    for (ucd.ext_pict) |r| {
        if (cp < r[0]) return false;
        if (cp <= r[1]) return true;
    }
    return false;
}

/// Default-ignorable code points the shaper keeps in the buffer during substitution (ZWJ / ZWNJ
/// steer joining, conjuncts and emoji sequences; variation selectors take part in ligatures
/// such as keycaps) and removes afterwards when no lookup consumed them.
pub inline fn isShapingControl(cp: u21) bool {
    return cp == 0x200c or cp == 0x200d or (cp >= 0xfe00 and cp <= 0xfe0f);
}

/// Cluster continuation for the simple path (no Unicode tables): combining marks, variation
/// selectors, emoji modifiers, ZWJ and whatever follows a ZWJ.
pub fn isContinuationSimple(prev: u21, cp: u21) bool {
    if (cp < 0x300) return false;
    return isCombining(cp) or prev == 0x200d or cp == 0x200d or (cp >= 0xfe00 and cp <= 0xfe0f) or (cp >= 0x1f3fb and cp <= 0x1f3ff);
}

// ---- UAX #14, adjacency form -------------------------------------------------------------
// takumi breaks lines with ICU4X's rule-based segmenter, which (in the version it ships)
// implements the Unicode 15.0 rule set: LB21a without the 15.1 look-ahead, the pair-based LB25,
// no quotation-mark / Aksara rules (LB15a-b, LB19a, LB20a, LB28a). The class table is generated
// from the 15.0 LineBreak.txt accordingly. One empirical quirk is reproduced as well: a run of
// two or more "complex context" (SA: Thai, Lao, Khmer, Myanmar, ...) characters is handed to a
// dictionary segmenter that is not there, and the end of such a run is always a break
// opportunity while the run itself has none.

/// Internal class: the last character of an SA run of >= 2 characters.
const lb_sa_end: u8 = 63;

/// Line-break byte of `cp` for `lineBreaksPrepare`: class in bits 0-5, East Asian (F/W/H) in bit 6.
pub fn lbByte(cp: u21) u8 {
    if (cp >= 0xac00 and cp <= 0xd7a3 and (cp - 0xac00) % 28 == 0) return L(.h2) | 0x40;
    return @truncate(props(cp) & 0x7f);
}

inline fn L(comptime c: Lb) u8 {
    return @intFromEnum(c);
}
inline fn isAl(c: u8) bool {
    return c == L(.al) or c == L(.hl);
}
inline fn isHangul(c: u8) bool {
    return c == L(.jl) or c == L(.jv) or c == L(.jt) or c == L(.h2) or c == L(.h3);
}

/// UAX #14 break opportunities, step 1. On entry `cls[i]` = `lbByte` of character i (hard
/// breaks as `Lb.bk`); on return the classes are resolved (LB9 / LB10, SA runs, word-break) and
/// `lineBreakAt` answers for any position. Spaces are left to the caller (Blink always breaks
/// after a run of U+0020), so the "SP*" look-behind rules are not modelled.
pub fn lineBreaksPrepare(cls: []u8, mode: WordBreak) void {
    // Bit 7 marks "no break before" (a CM / ZWJ absorbed by its base, or the character after a
    // ZWJ: LB8a).
    var base: u8 = L(.bk);
    var prev_zwj = false;
    var sa_run: usize = 0;
    for (cls, 0..) |*p, i| {
        var c = p.* & 0x3f;
        const raw_zwj = c == L(.zwj);
        var stick: u8 = if (prev_zwj) 0x80 else 0;
        const is_sa = c == L(.sa) or c == L(.sam);
        if (is_sa) {
            sa_run += 1;
        } else {
            if (sa_run >= 2) cls[i - 1] = (cls[i - 1] & 0xc0) | lb_sa_end;
            sa_run = 0;
        }
        if (c == L(.sa)) c = L(.al);
        if (c == L(.sam)) {
            // inside its run a mark sticks to the previous character
            c = L(.cm);
        }
        if (c == L(.cm) or raw_zwj) {
            if (base == L(.bk) or base == L(.sp) or base == L(.zw)) {
                c = L(.al);
            } else {
                c = base;
                stick = 0x80;
            }
        }
        if (mode == .break_all) {
            if (c == L(.al) or c == L(.hl) or c == L(.nu)) c = L(.id);
        } else if (mode == .keep_all) {
            if (c == L(.id) or isHangul(c)) c = L(.al);
        }
        base = c;
        p.* = c | (p.* & 0x40) | stick;
        prev_zwj = raw_zwj;
    }
}

/// Whether a break is allowed before character `i` (`cls` prepared by `lineBreaksPrepare`).
pub fn lineBreakAt(cls: []const u8, i: usize) bool {
    if (i == 0 or i >= cls.len) return false;
    if (cls[i - 1] & 0x3f == lb_sa_end) {
        // the end of a complex-context run breaks before anything but a space / ZWSP / newline
        const a = cls[i] & 0x3f;
        return a != L(.sp) and a != L(.zw) and a != L(.bk);
    }
    return cls[i] & 0x80 == 0 and pairBreak(cls, i);
}

/// Convenience: prepare + evaluate everything; bit 7 of `cls[i]` = break allowed before i.
pub fn lineBreaks(cls: []u8, mode: WordBreak) void {
    lineBreaksPrepare(cls, mode);
    var i: usize = cls.len;
    while (i > 1) {
        i -= 1;
        const brk = lineBreakAt(cls, i);
        cls[i] = (cls[i] & 0x7f) | (if (brk) @as(u8, 0x80) else 0);
    }
    if (cls.len != 0) cls[0] &= 0x7f;
}

inline fn clsAt(cls: []const u8, i: usize) u8 {
    const c = cls[i] & 0x3f;
    return if (c == lb_sa_end) L(.al) else c;
}

/// Break between i-1 and i (i >= 1). Bit 7 of the entries (stick flag or an earlier result) is
/// ignored.
fn pairBreak(cls: []const u8, i: usize) bool {
    const b = clsAt(cls, i - 1);
    const a = clsAt(cls, i);
    const ea_b = cls[i - 1] & 0x40 != 0;
    const ea_a = cls[i] & 0x40 != 0;
    const bb: u8 = if (i >= 2) clsAt(cls, i - 2) else 0xff;
    if (b == L(.bk)) return true;
    if (a == L(.bk) or a == L(.sp) or a == L(.zw)) return false;
    if (b == L(.zw)) return true;
    if (a == L(.wj) or b == L(.wj) or b == L(.gl)) return false; // LB11, LB12
    if (a == L(.gl) and b != L(.sp) and b != L(.ba) and b != L(.hy)) return false; // LB12a
    if (a == L(.cl) or a == L(.cp) or a == L(.ex) or a == L(.is) or a == L(.sy)) return false; // LB13
    if (b == L(.op)) return false; // LB14
    if ((b == L(.cl) or b == L(.cp)) and a == L(.ns)) return false; // LB16
    if (b == L(.b2) and a == L(.b2)) return false; // LB17
    if (b == L(.sp)) return true; // LB18
    if (a == L(.qu) or b == L(.qu)) return false; // LB19
    if (a == L(.cb) or b == L(.cb)) return true; // LB20
    if (a == L(.ba) or a == L(.hy) or a == L(.ns) or b == L(.bb)) return false; // LB21
    if (bb == L(.hl) and (b == L(.hy) or b == L(.ba))) return false; // LB21a
    if (b == L(.sy) and a == L(.hl)) return false; // LB21b
    if (a == L(.in)) return false; // LB22
    if ((isAl(b) and a == L(.nu)) or (b == L(.nu) and isAl(a))) return false; // LB23
    const a_ideo = a == L(.id) or a == L(.eb) or a == L(.em) or a == L(.xp);
    const b_ideo = b == L(.id) or b == L(.eb) or b == L(.em) or b == L(.xp);
    if ((b == L(.pr) and a_ideo) or (b_ideo and a == L(.po))) return false; // LB23a
    if (((b == L(.pr) or b == L(.po)) and isAl(a)) or (isAl(b) and (a == L(.pr) or a == L(.po)))) return false; // LB24
    // LB25 (pair form)
    if ((b == L(.cl) or b == L(.cp) or b == L(.nu)) and (a == L(.po) or a == L(.pr))) return false;
    if ((b == L(.po) or b == L(.pr)) and (a == L(.op) or a == L(.nu))) return false;
    if ((b == L(.hy) or b == L(.is) or b == L(.nu) or b == L(.sy)) and a == L(.nu)) return false;
    // LB26 / LB27
    if (b == L(.jl) and (a == L(.jl) or a == L(.jv) or a == L(.h2) or a == L(.h3))) return false;
    if ((b == L(.jv) or b == L(.h2)) and (a == L(.jv) or a == L(.jt))) return false;
    if ((b == L(.jt) or b == L(.h3)) and a == L(.jt)) return false;
    if ((isHangul(b) and a == L(.po)) or (b == L(.pr) and isHangul(a))) return false;
    if (isAl(b) and isAl(a)) return false; // LB28
    if (b == L(.is) and isAl(a)) return false; // LB29
    if ((isAl(b) or b == L(.nu)) and a == L(.op) and !ea_a) return false; // LB30
    if (b == L(.cp) and !ea_b and (isAl(a) or a == L(.nu))) return false;
    if (b == L(.ri) and a == L(.ri)) { // LB30a
        var k = i - 1;
        var cnt: usize = 1;
        while (k > 0 and cls[k - 1] & 0x3f == L(.ri)) : (k -= 1) cnt += 1;
        if (cnt & 1 == 1) return false;
    }
    if ((b == L(.eb) or b == L(.xp)) and a == L(.em)) return false; // LB30b
    return true;
}

/// Grapheme-cluster continuation in HarfBuzz's sense (marks, ZWJ, emoji modifiers, tags,
/// half-width voiced marks). `prev` is the preceding character (0 if none).
pub inline fn isContinuation(prev: u21, cp: u21) bool {
    if (cp < 0x300) return false;
    return isContinuationSlow(prev, cp);
}
fn isContinuationSlow(prev: u21, cp: u21) bool {
    if (cp == 0x200d or (cp >= 0x1f3fb and cp <= 0x1f3ff) or (cp >= 0xe0020 and cp <= 0xe007f) or cp == 0xff9e or cp == 0xff9f) return true;
    if (prev == 0x200d and isExtPict(cp)) return true;
    return isMark(cp);
}

test "utf8 decoding" {
    const t = std.testing;
    try t.expectEqual(Decoded{ .cp = 'A', .len = 1 }, decodeUtf8("A", 0));
    try t.expectEqual(Decoded{ .cp = 0xe9, .len = 2 }, decodeUtf8("é", 0));
    try t.expectEqual(Decoded{ .cp = 0x1ec7, .len = 3 }, decodeUtf8("ệ", 0));
    try t.expectEqual(Decoded{ .cp = 0x1f600, .len = 4 }, decodeUtf8("\u{1f600}", 0));
    // truncated, stray continuation, overlong, surrogate, > U+10FFFF, 0xff
    for ([_][]const u8{ "\xc3", "\xe1\xbb", "\x80", "\xc0\xaf", "\xe0\x80\xaf", "\xed\xa0\x80", "\xf4\x90\x80\x80", "\xff", "\xf0\x9f\x98" }) |s| {
        try t.expectEqual(Decoded{ .cp = 0xfffd, .len = 1 }, decodeUtf8(s, 0));
    }
    try t.expectEqual(Decoded{ .cp = 0x10ffff, .len = 4 }, decodeUtf8("\xf4\x8f\xbf\xbf", 0));
}

test "break opportunities" {
    const t = std.testing;
    try t.expect(canBreak('a', ' ', 'b', .normal));
    try t.expect(!canBreak('a', 'b', 'c', .normal));
    try t.expect(!canBreak('a', 'b', ' ', .normal));
    try t.expect(canBreak('a', '-', 'b', .normal));
    try t.expect(!canBreak(' ', '-', '1', .normal));
    try t.expect(canBreak('a', '-', '1', .normal));
    try t.expect(!canBreak('a', '/', 'b', .normal));
    try t.expect(!canBreak('a', 0xa0, 'b', .normal));
    try t.expect(!canBreak(0, 'a', 0xa0, .normal));
    try t.expect(canBreak('a', 0xad, 'b', .normal));
    try t.expect(canBreak('a', 0x200b, 'b', .normal));
    try t.expect(canBreak(0, 0x4e2d, 0x6587, .normal));
    try t.expect(!canBreak(0, 0x4e2d, 0x6587, .keep_all));
    try t.expect(!canBreak(0, 0x4e2d, 0x3002, .normal)); // before 。
    try t.expect(canBreak(0, 0x3002, 0x4e2d, .normal)); // after 。
    try t.expect(!canBreak(0, 0x300c, 0x4e2d, .normal)); // after 「
    try t.expect(canBreak(0, 0x4e2d, 0x300c, .normal)); // before 「
    try t.expect(canBreak(0, 'a', 0x4e2d, .normal));
    try t.expect(canBreak(0, 'a', 'b', .break_all));
    try t.expect(!canBreak(0, 'a', '.', .break_all));
    try t.expect(!canBreak(0, 'e', 0x301, .break_all));
}
