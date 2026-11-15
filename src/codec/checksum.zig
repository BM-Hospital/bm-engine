//! CRC-32 (PNG/zlib polynomial; slicing-by-4 with four 1 KB tables in the native build, one table
//! in the size-budgeted wasm build) and Adler-32 (16-byte SIMD blocks).
const std = @import("std");
const builtin = @import("builtin");
const bytes = @import("bytes.zig");

/// Tables used: 3 KiB more buy about 2x on the megabyte-long IDAT stream of a photo-like PNG
/// (1 ms of a 35 ms encode); the wasm binaries keep the single table.
/// The PDF wasm build checks the CRC of every embedded PNG chunk on each render (krilla
/// `PngData::new`), so it keeps the four tables too.
const pdf_build = blk: {
    const root = @import("root");
    break :blk @hasDecl(root, "bm_config") and root.bm_config.enable_pdf;
};
const crc_slices = if (builtin.cpu.arch.isWasm() and !pdf_build) 1 else 4;

/// `crc_tables[k][b]`: the CRC of byte `b` followed by `k` zero bytes.
const crc_tables: [crc_slices][256]u32 = blk: {
    @setEvalBranchQuota(20000);
    var t: [crc_slices][256]u32 = undefined;
    for (0..256) |i| {
        var c: u32 = @intCast(i);
        for (0..8) |_| c = if (c & 1 != 0) 0xEDB88320 ^ (c >> 1) else c >> 1;
        t[0][i] = c;
    }
    for (1..crc_slices) |k| {
        for (0..256) |i| t[k][i] = (t[k - 1][i] >> 8) ^ t[0][t[k - 1][i] & 0xff];
    }
    break :blk t;
};

/// Continues a CRC-32: start with `crc = 0`.
pub fn crc32(crc: u32, data: []const u8) u32 {
    var c = ~crc;
    var p = data;
    if (crc_slices == 4) {
        // four bytes per step
        while (p.len >= 4) : (p = p[4..]) {
            c ^= bytes.le32(p, 0);
            c = crc_tables[3][c & 0xff] ^ crc_tables[2][(c >> 8) & 0xff] ^ crc_tables[1][(c >> 16) & 0xff] ^ crc_tables[0][c >> 24];
        }
    }
    for (p) |b| c = crc_tables[0][(c ^ b) & 0xff] ^ (c >> 8);
    return ~c;
}

/// Continues an Adler-32: start with `adler = 1`.
pub fn adler32(adler: u32, data: []const u8) u32 {
    const base: u32 = 65521;
    var a: u32 = adler & 0xffff;
    var b: u32 = adler >> 16;
    var p = data;
    const V = @Vector(16, u32);
    const weights: V = .{ 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 };
    while (p.len > 0) {
        // 5552 = NMAX (largest n with 255n(n+1)/2 + (n+1)(BASE-1) < 2^32); multiple of 16.
        const n = @min(p.len, 5552);
        var q = p[0..n];
        while (q.len >= 16) {
            const v: V = @as(@Vector(16, u8), q[0..16].*);
            b += 16 * a + @reduce(.Add, v * weights);
            a += @reduce(.Add, v);
            q = q[16..];
        }
        for (q) |x| {
            a += x;
            b += a;
        }
        a %= base;
        b %= base;
        p = p[n..];
    }
    return (b << 16) | a;
}

test "crc32 and adler32 known values" {
    try std.testing.expectEqual(@as(u32, 0xCBF43926), crc32(0, "123456789"));
    try std.testing.expectEqual(@as(u32, 0x091E01DE), adler32(1, "123456789"));
    // long input vs scalar reference
    var buf: [20000]u8 = undefined;
    for (&buf, 0..) |*x, i| x.* = @truncate(i *% 7919 +% (i >> 3));
    var a: u32 = 1;
    var b: u32 = 0;
    for (buf) |x| {
        a = (a + x) % 65521;
        b = (b + a) % 65521;
    }
    try std.testing.expectEqual((b << 16) | a, adler32(1, &buf));
    try std.testing.expectEqual(adler32(adler32(1, buf[0..777]), buf[777..]), adler32(1, &buf));
    try std.testing.expectEqual(crc32(crc32(0, buf[0..777]), buf[777..]), crc32(0, &buf));
    // every length and split against the bit-by-bit definition
    for (0..70) |n| {
        var c: u32 = 0xFFFFFFFF;
        for (buf[3..][0..n]) |x| {
            c ^= x;
            for (0..8) |_| c = if (c & 1 != 0) 0xEDB88320 ^ (c >> 1) else c >> 1;
        }
        try std.testing.expectEqual(~c, crc32(0, buf[3..][0..n]));
        for (0..n + 1) |cut| try std.testing.expectEqual(~c, crc32(crc32(0, buf[3..][0..cut]), buf[3 + cut ..][0 .. n - cut]));
    }
}
