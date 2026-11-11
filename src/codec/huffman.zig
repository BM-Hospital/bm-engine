//! Length-limited Huffman code construction shared by the DEFLATE and VP8L encoders.
//! Moffat–Katajainen in-place minimum-redundancy lengths, then the miniz/zlib style
//! Kraft-sum repair to enforce the maximum code length. No allocation.
const std = @import("std");

/// Largest alphabet supported (VP8L green alphabet with an 11-bit color cache = 2328).
pub const max_symbols = 2336;

/// Fills `lengths[i]` (0 = unused) for `freqs[i]`, each length <= `max_len` (1..15).
/// When exactly one symbol is used it gets length 1 (callers that need two codes,
/// like DEFLATE's distance tree, add a dummy symbol themselves).
/// Returns the number of used symbols.
pub fn buildLengths(freqs: []const u32, lengths: []u8, max_len: u5) usize {
    std.debug.assert(freqs.len <= max_symbols and lengths.len >= freqs.len);
    @memset(lengths[0..freqs.len], 0);
    // key = freq<<12 | sym does not fit; keep separate arrays sorted by (freq, sym).
    var syms: [max_symbols]u64 = undefined;
    var n: usize = 0;
    for (freqs, 0..) |f, i| {
        if (f != 0) {
            syms[n] = (@as(u64, f) << 16) | @as(u64, @intCast(i));
            n += 1;
        }
    }
    if (n == 0) return 0;
    if (n == 1) {
        lengths[@intCast(syms[0] & 0xffff)] = 1;
        return 1;
    }
    shellSort(syms[0..n]);

    var a: [max_symbols]u32 = undefined;
    for (0..n) |i| a[i] = @intCast(syms[i] >> 16);
    moffat(a[0..n]);

    // a[i] now holds the code length of sorted symbol i (ascending freq -> descending length).
    var counts: [64]u32 = @splat(0);
    for (a[0..n]) |l| counts[@min(l, 63)] += 1;
    const ml: usize = max_len;
    var i: usize = ml + 1;
    while (i < 64) : (i += 1) {
        counts[ml] += counts[i];
        counts[i] = 0;
    }
    var total: u64 = 0;
    i = ml;
    while (i > 0) : (i -= 1) total += @as(u64, counts[i]) << @intCast(ml - i);
    const target: u64 = @as(u64, 1) << @intCast(ml);
    while (total > target) {
        counts[ml] -= 1;
        var k: usize = ml - 1;
        while (k > 0) : (k -= 1) {
            if (counts[k] != 0) {
                counts[k] -= 1;
                counts[k + 1] += 2;
                break;
            }
        }
        total -= 1;
    }
    // Assign: highest frequency (end of sorted list) gets the shortest code.
    var j: usize = n;
    var l: usize = 1;
    while (l <= ml) : (l += 1) {
        var c = counts[l];
        while (c > 0) : (c -= 1) {
            j -= 1;
            lengths[@intCast(syms[j] & 0xffff)] = @intCast(l);
        }
    }
    return n;
}

/// Shell sort (Ciura gaps): tiny code, fast enough for <= 2336 keys.
fn shellSort(a: []u64) void {
    const gaps = [_]usize{ 701, 301, 132, 57, 23, 10, 4, 1 };
    for (gaps) |g| {
        var i: usize = g;
        while (i < a.len) : (i += 1) {
            const v = a[i];
            var j = i;
            while (j >= g and a[j - g] > v) : (j -= g) a[j] = a[j - g];
            a[j] = v;
        }
    }
}

/// In-place minimum-redundancy code lengths (Moffat & Katajainen) for ascending weights.
fn moffat(a: []u32) void {
    const n = a.len;
    a[0] += a[1];
    var root: usize = 0;
    var leaf: usize = 2;
    var next: usize = 1;
    while (next < n - 1) : (next += 1) {
        if (leaf >= n or a[root] < a[leaf]) {
            a[next] = a[root];
            a[root] = @intCast(next);
            root += 1;
        } else {
            a[next] = a[leaf];
            leaf += 1;
        }
        if (leaf >= n or (root < next and a[root] < a[leaf])) {
            a[next] +%= a[root];
            a[root] = @intCast(next);
            root += 1;
        } else {
            a[next] +%= a[leaf];
            leaf += 1;
        }
    }
    a[n - 2] = 0;
    var k: isize = @as(isize, @intCast(n)) - 3;
    while (k >= 0) : (k -= 1) {
        const ku: usize = @intCast(k);
        a[ku] = a[a[ku]] + 1;
    }
    var avbl: usize = 1;
    var used: usize = 0;
    var dpth: u32 = 0;
    var r: isize = @as(isize, @intCast(n)) - 2;
    var nx: isize = @as(isize, @intCast(n)) - 1;
    while (avbl > 0) {
        while (r >= 0 and a[@intCast(r)] == dpth) {
            used += 1;
            r -= 1;
        }
        while (avbl > used) {
            a[@intCast(nx)] = dpth;
            nx -= 1;
            avbl -= 1;
        }
        avbl = 2 * used;
        dpth += 1;
        used = 0;
    }
}

/// Canonical codes from lengths, returned BIT-REVERSED (ready for LSB-first bit writers,
/// as used by both DEFLATE and VP8L).
pub fn canonicalCodes(lengths: []const u8, codes: []u16) void {
    var bl_count: [16]u16 = @splat(0);
    for (lengths) |l| bl_count[l & 15] += 1;
    bl_count[0] = 0;
    var next_code: [16]u16 = undefined;
    var code: u16 = 0;
    next_code[0] = 0;
    for (1..16) |b| {
        code = (code +% bl_count[b - 1]) << 1;
        next_code[b] = code;
    }
    for (lengths, 0..) |l, i| {
        if (l == 0) {
            codes[i] = 0;
            continue;
        }
        const c = next_code[l & 15];
        next_code[l & 15] +%= 1;
        codes[i] = @bitReverse(c) >> @intCast(16 - @as(u5, @intCast(l & 15)));
    }
}

test "huffman lengths are valid and limited" {
    var prng = std.Random.DefaultPrng.init(1);
    const rnd = prng.random();
    var freqs: [300]u32 = undefined;
    var lens: [300]u8 = undefined;
    for (0..200) |iter| {
        const n = 2 + rnd.uintLessThan(usize, 298);
        for (freqs[0..n]) |*f| {
            f.* = if (rnd.boolean()) 0 else rnd.uintLessThan(u32, if (iter % 2 == 0) 10 else 1 << 20);
        }
        // fibonacci-ish skew to force length limiting
        if (iter % 3 == 0) {
            var x: u32 = 1;
            var y: u32 = 1;
            for (freqs[0..@min(n, 40)]) |*f| {
                f.* = x;
                const t = x +% y;
                x = y;
                y = t;
            }
        }
        const used = buildLengths(freqs[0..n], lens[0..n], 15);
        var kraft: u64 = 0;
        var cnt: usize = 0;
        for (lens[0..n], freqs[0..n]) |l, f| {
            try std.testing.expect(l <= 15);
            try std.testing.expect((l == 0) == (f == 0));
            if (l != 0) {
                kraft += @as(u64, 1) << @intCast(15 - l);
                cnt += 1;
            }
        }
        try std.testing.expectEqual(used, cnt);
        if (cnt >= 2) try std.testing.expectEqual(@as(u64, 1 << 15), kraft);
    }
}
