//! Emoji properties (UTS #51) and a small emoji-sequence scanner for font fallback.
//!
//! Tables: `color_emoji_tables.zig`, GENERATED from Unicode `emoji-data.txt` (17.0) by
//! `bench/probe/colorfont/gen_emoji_tables.mjs` (see its header for the exact command). 388 packed
//! u32 ranges = 1.5 KB. Lookups are a binary search (<= 8 probes).
//!
//! The text engine's font fallback should run `scanEmoji` at each cluster start: when it returns
//! `len > 0` and `emoji_presentation == true`, the whole sequence should be shaped with a colour
//! (emoji) face first (takumi / Blink `emoji_presentation_scanner.rs` behaviour); text-presentation
//! emoji (e.g. U+00A9 without VS16) prefer the normal text fallback chain.
const tables = @import("color_emoji_tables.zig");

fn inTable(comptime t: []const u32, cp: u21) bool {
    var lo: usize = 0;
    var hi: usize = t.len;
    const c: u32 = cp;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        const e = t[mid];
        const start = e >> 11;
        if (c < start) {
            hi = mid;
        } else if (c > start + (e & 0x7ff)) {
            lo = mid + 1;
        } else return true;
    }
    return false;
}

/// Unicode property Emoji=Yes (includes digits, '#', '*', '©', ... which are text-default).
pub fn isEmoji(cp: u21) bool {
    if (cp < 0x23) return false;
    return inTable(&tables.emoji, cp);
}
/// Emoji_Presentation=Yes: displayed as emoji (colour) by default, without VS16.
pub fn isEmojiPresentation(cp: u21) bool {
    if (cp < 0x231a) return false;
    return inTable(&tables.emoji_presentation, cp);
}
/// Extended_Pictographic=Yes (used for ZWJ sequence elements; includes unassigned pictographic blocks).
pub fn isExtendedPictographic(cp: u21) bool {
    if (cp < 0xa9) return false;
    return inTable(&tables.extended_pictographic, cp);
}
/// Fitzpatrick skin-tone modifiers U+1F3FB..U+1F3FF.
pub fn isEmojiModifier(cp: u21) bool {
    return cp >= 0x1F3FB and cp <= 0x1F3FF;
}
pub fn isZWJ(cp: u21) bool {
    return cp == 0x200D;
}
/// VARIATION SELECTOR-15 (text presentation).
pub fn isVS15(cp: u21) bool {
    return cp == 0xFE0E;
}
/// VARIATION SELECTOR-16 (emoji presentation).
pub fn isVS16(cp: u21) bool {
    return cp == 0xFE0F;
}
pub fn isRegionalIndicator(cp: u21) bool {
    return cp >= 0x1F1E6 and cp <= 0x1F1FF;
}
fn isKeycapBase(cp: u21) bool {
    return (cp >= '0' and cp <= '9') or cp == '#' or cp == '*';
}
fn isTagSpec(cp: u21) bool {
    return cp >= 0xE0020 and cp <= 0xE007E;
}

pub const Cluster = struct {
    /// Number of code points of the emoji sequence starting at `cps[0]`; 0 = not an emoji.
    len: usize,
    /// True when the sequence should be drawn with a colour/emoji face (default emoji presentation,
    /// VS16, keycap, flag, modifier, tag or ZWJ sequence). False for text-default emoji such as
    /// U+00A9 or anything followed by VS15.
    emoji_presentation: bool,
};

/// One sequence element: pictograph + optional VS15/VS16, skin-tone modifier, tag sequence.
fn element(cps: []const u21, start: usize, pres: *bool) usize {
    var i = start;
    const c = cps[i];
    if (isRegionalIndicator(c)) {
        pres.* = true;
        return if (i + 1 < cps.len and isRegionalIndicator(cps[i + 1])) 2 else 1;
    }
    if (!isEmoji(c) and !isExtendedPictographic(c)) return 0;
    pres.* = isEmojiPresentation(c) or isEmojiModifier(c);
    i += 1;
    if (i < cps.len and isVS16(cps[i])) {
        pres.* = true;
        i += 1;
    } else if (i < cps.len and isVS15(cps[i])) {
        pres.* = false;
        return i + 1 - start;
    }
    if (i < cps.len and isEmojiModifier(cps[i])) {
        pres.* = true;
        i += 1;
    }
    // tag sequence (subdivision flags): base (tag_spec)+ U+E007F
    if (i < cps.len and isTagSpec(cps[i])) {
        var j = i;
        while (j < cps.len and isTagSpec(cps[j])) j += 1;
        if (j < cps.len and cps[j] == 0xE007F) {
            pres.* = true;
            i = j + 1;
        }
    }
    return i - start;
}

/// Scans the emoji sequence (UTS #51 `emoji_zwj_sequence` / keycap / flag / modifier / tag
/// sequence) starting at `cps[0]`. Lenient like browsers: any pictograph may take a modifier and
/// any pictographs may be joined by ZWJ. Plain digits / '#' / '*' are not emoji unless followed
/// by VS16 or U+20E3.
pub fn scanEmoji(cps: []const u21) Cluster {
    if (cps.len == 0) return .{ .len = 0, .emoji_presentation = false };
    const c = cps[0];
    if (isKeycapBase(c)) {
        var i: usize = 1;
        var vs = false;
        if (i < cps.len and isVS16(cps[i])) {
            vs = true;
            i += 1;
        }
        // (Blink: a keycap without VS16 is a text-presentation sequence; takumi draws "1" + U+20E3 from the text font)
        if (i < cps.len and cps[i] == 0x20E3) return .{ .len = i + 1, .emoji_presentation = vs };
        if (vs) return .{ .len = 2, .emoji_presentation = true };
        return .{ .len = 0, .emoji_presentation = false };
    }
    var pres = false;
    var len = element(cps, 0, &pres);
    if (len == 0) return .{ .len = 0, .emoji_presentation = false };
    var guard: u32 = 0;
    while (len + 1 < cps.len and isZWJ(cps[len]) and guard < 64) : (guard += 1) {
        var p2 = false;
        const n = element(cps, len + 1, &p2);
        if (n == 0) break;
        len += 1 + n;
        pres = true;
    }
    return .{ .len = len, .emoji_presentation = pres };
}

/// Length in code points of the emoji sequence at `cps[0]` (0 when it does not start one).
pub fn emojiClusterLen(cps: []const u21) usize {
    return scanEmoji(cps).len;
}

const std = @import("std");
const testing = std.testing;

test "emoji properties" {
    try testing.expect(isEmoji('#'));
    try testing.expect(!isEmojiPresentation('#'));
    try testing.expect(isEmoji(0xA9) and !isEmojiPresentation(0xA9));
    try testing.expect(isEmojiPresentation(0x1F600));
    try testing.expect(isEmojiPresentation(0x231A));
    try testing.expect(!isEmojiPresentation('A') and !isEmoji('A'));
    try testing.expect(isExtendedPictographic(0x1FC00)); // reserved pictographic block
    try testing.expect(isEmojiModifier(0x1F3FD) and !isEmojiModifier(0x1F3FA));
    try testing.expect(isEmojiPresentation(0x1FAE8)); // shaking face (15.0)
    try testing.expect(!isEmoji(0x10FFFF));
}

test "emoji sequences" {
    const E = struct {
        fn c(s: []const u21) Cluster {
            return scanEmoji(s);
        }
    };
    try testing.expectEqual(@as(usize, 1), E.c(&.{ 0x1F600, 'a' }).len);
    try testing.expectEqual(@as(usize, 2), E.c(&.{ 0x1F44D, 0x1F3FD }).len); // thumbs up + medium skin
    try testing.expectEqual(@as(usize, 2), E.c(&.{ 0x1F1FB, 0x1F1F3, 0x1F1FB }).len); // VN flag
    const fam = E.c(&.{ 0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467, 'x' });
    try testing.expectEqual(@as(usize, 5), fam.len);
    try testing.expect(fam.emoji_presentation);
    try testing.expectEqual(@as(usize, 3), E.c(&.{ '1', 0xFE0F, 0x20E3 }).len);
    try testing.expectEqual(@as(usize, 2), E.c(&.{ '#', 0x20E3 }).len);
    try testing.expectEqual(@as(usize, 0), E.c(&.{ '1', '2' }).len);
    const copy = E.c(&.{0xA9});
    try testing.expect(copy.len == 1 and !copy.emoji_presentation);
    try testing.expect(E.c(&.{ 0xA9, 0xFE0F }).emoji_presentation);
    try testing.expect(!E.c(&.{ 0x1F600, 0xFE0E }).emoji_presentation);
    // England flag: 1F3F4 E0067 E0062 E0065 E006E E0067 E007F
    try testing.expectEqual(@as(usize, 7), E.c(&.{ 0x1F3F4, 0xE0067, 0xE0062, 0xE0065, 0xE006E, 0xE0067, 0xE007F }).len);
    // rainbow flag: 1F3F3 FE0F 200D 1F308
    try testing.expectEqual(@as(usize, 4), E.c(&.{ 0x1F3F3, 0xFE0F, 0x200D, 0x1F308 }).len);
    // dangling ZWJ is not consumed
    try testing.expectEqual(@as(usize, 1), E.c(&.{ 0x1F600, 0x200D }).len);
    try testing.expectEqual(@as(usize, 0), E.c(&.{}).len);
    try testing.expectEqual(@as(usize, 0), emojiClusterLen(&.{'a'}));
}
