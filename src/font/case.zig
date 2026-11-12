//! Locale-neutral Unicode case mapping (full uppercase with SpecialCasing expansions, simple
//! lowercase) from the generated runs in `case_data.zig` (see `gen/gen_case.mjs` for the Unicode
//! version). Used by synthesized small caps; lookups are binary searches over ~200 runs.
const std = @import("std");
const data = @import("case_data.zig");

fn lookup(comptime t: []const struct { u32, i32 }, cp: u21) u21 {
    var lo: usize = 0;
    var hi: usize = t.len;
    const c: u32 = cp;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        const e = t[mid][0];
        const start = e >> 11;
        const count = ((e >> 1) & 0x3ff) + 1;
        const stride: u32 = if (e & 1 != 0) 2 else 1;
        if (c < start) {
            hi = mid;
        } else if (c >= start + count * stride) {
            lo = mid + 1;
        } else {
            if ((c - start) % stride != 0) return cp;
            const m: i64 = @as(i64, c) + t[mid][1];
            return if (m >= 0 and m <= 0x10FFFF) @intCast(m) else cp;
        }
    }
    return cp;
}

/// Simple uppercase mapping (unchanged when there is none or it expands to several characters).
pub fn upperSimple(cp: u21) u21 {
    if (cp < 0x80) return if (cp >= 'a' and cp <= 'z') cp - 32 else cp;
    return lookup(&data.upper, cp);
}

/// Simple lowercase mapping: the inverse of the uppercase runs (minus the excluded duplicate
/// sources), corrected by `lower_extra`. Linear in the number of runs; only used by unicase.
pub fn lower(cp: u21) u21 {
    if (cp < 0x80) return if (cp >= 'A' and cp <= 'Z') cp + 32 else cp;
    for (data.lower_extra) |e| {
        if (e[0] == cp) return @intCast(e[1]);
    }
    for (data.upper) |r| {
        const src: i64 = @as(i64, cp) - r[1];
        if (src < 0) continue;
        const start: i64 = r[0] >> 11;
        const count: i64 = ((r[0] >> 1) & 0x3ff) + 1;
        const stride: i64 = if (r[0] & 1 != 0) 2 else 1;
        if (src < start or src >= start + count * stride or @mod(src - start, stride) != 0) continue;
        var excluded = false;
        for (data.lower_exclude) |x| excluded = excluded or x == src;
        if (!excluded) return @intCast(src);
    }
    return cp;
}

/// Full uppercase mapping of `cp` into `out` (1 to 3 code points, e.g. U+00DF -> "SS"); returns the
/// number written.
pub fn upper(cp: u21, out: *[3]u21) usize {
    if (cp >= 0xDF) {
        for (data.upper_special) |e| {
            if (e[0] == cp) {
                var n: usize = 0;
                for (e[1..]) |v| {
                    if (v == 0) break;
                    out[n] = v;
                    n += 1;
                }
                return n;
            }
        }
    }
    out[0] = upperSimple(cp);
    return 1;
}

/// Unicode ChangesWhenUppercased.
pub fn changesWhenUppercased(cp: u21) bool {
    var buf: [3]u21 = undefined;
    const n = upper(cp, &buf);
    return n != 1 or buf[0] != cp;
}

test "case mapping" {
    const t = std.testing;
    var b: [3]u21 = undefined;
    try t.expectEqual(@as(usize, 2), upper(0xDF, &b));
    try t.expectEqual(@as(u21, 'S'), b[0]);
    try t.expectEqual(@as(u21, 'S'), b[1]);
    try t.expectEqual(@as(usize, 3), upper(0xFB03, &b)); // ffi ligature -> FFI
    try t.expectEqual(@as(u21, 'A'), upperSimple('a'));
    try t.expectEqual(@as(u21, 0x110), upperSimple(0x111)); // đ
    try t.expectEqual(@as(u21, 0x1EC6), upperSimple(0x1EC7)); // ệ
    try t.expectEqual(@as(u21, 0x3A3), upperSimple(0x3C2)); // final sigma
    try t.expectEqual(@as(u21, 0x386), upperSimple(0x3AC)); // ά
    try t.expectEqual(@as(u21, 0x410), upperSimple(0x430));
    try t.expectEqual(@as(u21, 0x1C4), upperSimple(0x1C6)); // ǆ -> Ǆ
    try t.expectEqual(@as(u21, 0x10400), upperSimple(0x10428)); // Deseret
    try t.expectEqual(@as(u21, 0x1E921), upperSimple(0x1E943)); // Adlam
    try t.expectEqual(@as(u21, 0x3c3), lower(0x3a3));
    try t.expectEqual(@as(u21, 0x101), lower(0x100));
    try t.expectEqual(@as(u21, 0x100), upperSimple(0x101));
    try t.expect(changesWhenUppercased('a'));
    try t.expect(!changesWhenUppercased('A'));
    try t.expect(!changesWhenUppercased('1'));
    try t.expect(changesWhenUppercased(0xDF));
    try t.expect(!changesWhenUppercased(0x10FFFF));
    // exhaustive sanity: no mapping leaves the code space
    var cp: u21 = 0;
    while (cp < 0x10FFFF) : (cp += 1) {
        _ = upper(cp, &b);
        _ = lower(cp);
    }
}
