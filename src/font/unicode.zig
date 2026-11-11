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
    if (b > ' ' and b < 0x80 and a > ' ' and a < 0x80) {
        if (b == '-' and a >= '0' and a <= '9') return isAsciiAlnum(bb);
        const t = asciiBreak(b, a);
        if (mode != .break_all) return t;
        return t or uaxBreak(b, a, mode);
    }
    return uaxBreak(b, a, mode);
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
