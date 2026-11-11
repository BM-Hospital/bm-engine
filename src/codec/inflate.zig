//! DEFLATE / zlib decompressor (RFC 1950/1951). Table-driven: 10-bit primary lookup for both
//! trees with a canonical (puff-style) fallback for longer codes; 64-bit bit buffer with
//! branch-free refill. Untrusted input: every read/write is bounds checked.
//!
//! Allocation: `*Into` variants allocate nothing (the ~6 KB of tables live on the stack);
//! `*Alloc` variants allocate the growing output from the given allocator (the returned
//! slice is owned by the caller; exactly sized).
const std = @import("std");
const bytes = @import("bytes.zig");
const types = @import("types.zig");
const checksum = @import("checksum.zig");

pub const Error = error{ InvalidData, ImageTooLarge, OutOfMemory };

pub const Options = struct {
    /// Verify the zlib Adler-32 trailer (costs ~0.3 ns/byte).
    verify_checksum: bool = false,
};

/// zlib stream -> caller buffer. Returns bytes written. Output larger than `dst` is an error.
pub fn zlibDecompressInto(src: []const u8, dst: []u8, opts: Options) Error!usize {
    var out = Out{ .buf = dst };
    try zlibRun(src, &out, opts);
    return out.pos;
}

/// zlib stream -> newly allocated exact-size buffer, at most `max_out` bytes.
pub fn zlibDecompressAlloc(alloc: std.mem.Allocator, src: []const u8, max_out: usize, opts: Options) Error![]u8 {
    var out = Out{ .buf = &.{}, .alloc = alloc, .limit = max_out };
    errdefer if (out.buf.len != 0) alloc.free(out.buf);
    try zlibRun(src, &out, opts);
    return out.finish();
}

/// Raw DEFLATE -> caller buffer. Returns bytes written.
pub fn inflateInto(src: []const u8, dst: []u8) Error!usize {
    var out = Out{ .buf = dst };
    var br = BitReader{ .src = src };
    try inflateStream(&br, &out);
    return out.pos;
}

/// Raw DEFLATE -> newly allocated exact-size buffer, at most `max_out` bytes.
pub fn inflateAlloc(alloc: std.mem.Allocator, src: []const u8, max_out: usize) Error![]u8 {
    var out = Out{ .buf = &.{}, .alloc = alloc, .limit = max_out };
    errdefer if (out.buf.len != 0) alloc.free(out.buf);
    var br = BitReader{ .src = src };
    try inflateStream(&br, &out);
    return out.finish();
}

fn zlibRun(src: []const u8, out: *Out, opts: Options) Error!void {
    if (src.len < 2) return error.InvalidData;
    const cmf = src[0];
    const flg = src[1];
    if (cmf & 15 != 8 or cmf >> 4 > 7) return error.InvalidData;
    if ((@as(u32, cmf) * 256 + flg) % 31 != 0) return error.InvalidData;
    if (flg & 0x20 != 0) return error.InvalidData; // preset dictionary unsupported
    var br = BitReader{ .src = src, .pos = 2 };
    try inflateStream(&br, out);
    if (opts.verify_checksum) {
        const p = br.alignedPos();
        if (p + 4 > src.len) return error.InvalidData;
        const want = bytes.be32(src, p);
        if (checksum.adler32(1, out.buf[0..out.pos]) != want) return error.InvalidData;
    }
}

const Out = struct {
    buf: []u8,
    pos: usize = 0,
    alloc: ?std.mem.Allocator = null,
    limit: usize = 0,

    fn grow(self: *Out, need: usize) Error!void {
        const a = self.alloc orelse return error.InvalidData;
        const want = std.math.add(usize, self.pos, need) catch return error.ImageTooLarge;
        if (want > self.limit) return error.ImageTooLarge;
        var n = @max(self.buf.len * 2, 4096);
        n = @max(n, want);
        n = @min(n, self.limit);
        if (self.buf.len == 0) {
            self.buf = try a.alloc(u8, n);
        } else {
            self.buf = try a.realloc(self.buf, n);
        }
    }

    inline fn ensure(self: *Out, need: usize) Error!void {
        if (self.buf.len - self.pos < need) try self.grow(need);
    }

    fn finish(self: *Out) Error![]u8 {
        const a = self.alloc.?;
        if (self.buf.len == 0) return try a.alloc(u8, 0);
        if (self.pos == self.buf.len) return self.buf;
        if (a.resize(self.buf, self.pos)) return self.buf[0..self.pos];
        const r = try a.alloc(u8, self.pos);
        @memcpy(r, self.buf[0..self.pos]);
        a.free(self.buf);
        return r;
    }
};

const BitReader = struct {
    src: []const u8,
    pos: usize = 0,
    buf: u64 = 0,
    cnt: u32 = 0,

    /// Ensures >= 56 valid bits. Past the end of input, zero bytes are supplied; reading
    /// more than 8 bytes beyond the end is an error (so truncated streams terminate).
    inline fn refill(self: *BitReader) Error!void {
        if (self.cnt >= 56) return;
        if (self.src.len >= 8 and self.pos <= self.src.len - 8) {
            const w = bytes.le64(self.src, self.pos);
            self.buf |= w << @intCast(self.cnt);
            self.pos += (63 - self.cnt) >> 3;
            self.cnt |= 56;
        } else return self.refillSlow();
    }

    fn refillSlow(self: *BitReader) Error!void {
        while (self.cnt <= 56) {
            var b: u64 = 0;
            if (self.pos < self.src.len) {
                b = self.src[self.pos];
            } else if (self.pos >= self.src.len + 8) return error.InvalidData;
            self.pos += 1;
            // Clear the target byte first: slow refill after a fast one may see stale bits
            // (they are identical bytes, but zero padding beyond the end must not mix).
            self.buf &= (@as(u64, 1) << @intCast(self.cnt)) - 1;
            self.buf |= b << @intCast(self.cnt);
            self.cnt += 8;
        }
    }

    inline fn peek(self: *const BitReader, n: u6) u32 {
        return @truncate(self.buf & ((@as(u64, 1) << n) - 1));
    }

    inline fn consume(self: *BitReader, n: u32) void {
        self.buf >>= @intCast(n);
        self.cnt -= n;
    }

    inline fn bits(self: *BitReader, n: u6) u32 {
        const v = self.peek(n);
        self.consume(n);
        return v;
    }

    /// Byte offset of the next unread whole byte after discarding partial-byte bits.
    fn alignedPos(self: *BitReader) usize {
        self.consume(self.cnt & 7);
        return self.pos - (self.cnt >> 3);
    }

    fn reset(self: *BitReader, p: usize) void {
        self.pos = p;
        self.buf = 0;
        self.cnt = 0;
    }
};

const fast_bits = 10;

const Huff = struct {
    /// (len << 9) | sym; len 0 means "use slow path".
    fast: [1 << fast_bits]u16,
    count: [16]u16,
    sym: [288]u16,

    fn build(h: *Huff, lengths: []const u8) Error!void {
        @memset(&h.count, 0);
        for (lengths) |l| h.count[l] += 1;
        h.count[0] = 0;
        var left: i32 = 1;
        for (1..16) |l| {
            left <<= 1;
            left -= h.count[l];
            if (left < 0) return error.InvalidData; // over-subscribed
        }
        var offs: [16]u16 = undefined;
        offs[1] = 0;
        for (1..15) |l| offs[l + 1] = offs[l] + h.count[l];
        for (lengths, 0..) |l, s| {
            if (l != 0) {
                h.sym[offs[l]] = @intCast(s);
                offs[l] += 1;
            }
        }
        @memset(&h.fast, 0);
        var code: u32 = 0;
        var idx: usize = 0;
        for (1..fast_bits + 1) |l| {
            for (0..h.count[l]) |_| {
                const s = h.sym[idx];
                idx += 1;
                var r: u32 = @bitReverse(@as(u16, @intCast(code))) >> @intCast(16 - l);
                const e: u16 = @intCast((l << 9) | s);
                while (r < (1 << fast_bits)) : (r += @as(u32, 1) << @intCast(l)) h.fast[r] = e;
                code += 1;
            }
            code <<= 1;
        }
    }

    /// Caller guarantees >= 15 valid bits in `br`.
    inline fn decode(h: *const Huff, br: *BitReader) Error!u32 {
        const e = h.fast[br.peek(fast_bits)];
        if (e >> 9 != 0) {
            br.consume(e >> 9);
            return e & 511;
        }
        return h.decodeSlow(br);
    }

    fn decodeSlow(h: *const Huff, br: *BitReader) Error!u32 {
        var code: i32 = 0;
        var first: i32 = 0;
        var index: i32 = 0;
        var b = br.buf;
        for (1..16) |l| {
            code |= @intCast(b & 1);
            b >>= 1;
            const count: i32 = h.count[l];
            if (code - count < first) {
                br.consume(@intCast(l));
                return h.sym[@intCast(index + (code - first))];
            }
            index += count;
            first += count;
            first <<= 1;
            code <<= 1;
        }
        return error.InvalidData;
    }
};

const len_base = [29]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
const len_extra = [29]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
const dist_base = [30]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
const dist_extra = [30]u8{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
const cl_order = [19]u8{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

fn inflateStream(br: *BitReader, out: *Out) Error!void {
    var lit: Huff = undefined;
    var dist: Huff = undefined;
    while (true) {
        try br.refill();
        const final = br.bits(1);
        const btype = br.bits(2);
        switch (btype) {
            0 => {
                const p = br.alignedPos();
                const src = br.src;
                if (p > src.len or src.len - p < 4) return error.InvalidData;
                const len = bytes.le16(src, p);
                const nlen = bytes.le16(src, p + 2);
                if (len != ~nlen) return error.InvalidData;
                if (src.len - (p + 4) < len) return error.InvalidData;
                try out.ensure(len);
                @memcpy(out.buf[out.pos..][0..len], src[p + 4 ..][0..len]);
                out.pos += len;
                br.reset(p + 4 + len);
            },
            1 => {
                var l: [320]u8 = undefined;
                @memset(l[0..144], 8);
                @memset(l[144..256], 9);
                @memset(l[256..280], 7);
                @memset(l[280..288], 8);
                @memset(l[288..318], 5);
                try lit.build(l[0..288]);
                try dist.build(l[288..318]);
                try decodeBlock(br, out, &lit, &dist);
            },
            2 => {
                try readDynamic(br, &lit, &dist);
                try decodeBlock(br, out, &lit, &dist);
            },
            else => return error.InvalidData,
        }
        if (final != 0) return;
    }
}

fn readDynamic(br: *BitReader, lit: *Huff, dist: *Huff) Error!void {
    try br.refill();
    const hlit = br.bits(5) + 257;
    const hdist = br.bits(5) + 1;
    const hclen = br.bits(4) + 4;
    if (hlit > 286 or hdist > 30) return error.InvalidData;
    var cl: [19]u8 = @splat(0);
    for (0..hclen) |i| {
        try br.refill();
        cl[cl_order[i]] = @intCast(br.bits(3));
    }
    var clh: Huff = undefined;
    try clh.build(&cl);
    var lens: [320]u8 = @splat(0);
    const total = hlit + hdist;
    var i: usize = 0;
    while (i < total) {
        try br.refill();
        const s = try clh.decode(br);
        if (s < 16) {
            lens[i] = @intCast(s);
            i += 1;
            continue;
        }
        var rep: u32 = undefined;
        var val: u8 = 0;
        switch (s) {
            16 => {
                if (i == 0) return error.InvalidData;
                val = lens[i - 1];
                rep = 3 + br.bits(2);
            },
            17 => rep = 3 + br.bits(3),
            18 => rep = 11 + br.bits(7),
            else => return error.InvalidData,
        }
        if (i + rep > total) return error.InvalidData;
        @memset(lens[i..][0..rep], val);
        i += rep;
    }
    if (lens[256] == 0) return error.InvalidData;
    try lit.build(lens[0..hlit]);
    try dist.build(lens[hlit..total]);
}

fn decodeBlock(br: *BitReader, out: *Out, lit: *const Huff, dist: *const Huff) Error!void {
    while (true) {
        try br.refill();
        const s = try lit.decode(br);
        if (s < 256) {
            if (out.pos == out.buf.len) try out.grow(1);
            out.buf[out.pos] = @intCast(s);
            out.pos += 1;
            continue;
        }
        if (s == 256) return;
        const li = s - 257;
        if (li >= 29) return error.InvalidData;
        // After a refill we hold >= 56 bits: 15 (lit) + 5 + 15 + 13 = 48 fits.
        const len: usize = len_base[li] + br.bits(@intCast(len_extra[li]));
        const ds = try dist.decode(br);
        if (ds >= 30) return error.InvalidData;
        const d: usize = dist_base[ds] + br.bits(@intCast(dist_extra[ds]));
        if (d > out.pos) return error.InvalidData;
        try out.ensure(len);
        const buf = out.buf;
        const dst = out.pos;
        const from = dst - d;
        if (d >= len) {
            @memcpy(buf[dst..][0..len], buf[from..][0..len]);
        } else if (d == 1) {
            @memset(buf[dst..][0..len], buf[from]);
        } else {
            for (0..len) |k| buf[dst + k] = buf[from + k];
        }
        out.pos += len;
    }
}

// ---------------------------------------------------------------- tests
const testing = std.testing;

test "stored block" {
    const z = [_]u8{ 0x78, 0x01, 0x01, 0x05, 0x00, 0xfa, 0xff, 'h', 'e', 'l', 'l', 'o', 0x06, 0x2c, 0x02, 0x15 };
    var dst: [16]u8 = undefined;
    const n = try zlibDecompressInto(&z, &dst, .{ .verify_checksum = true });
    try testing.expectEqualStrings("hello", dst[0..n]);
    // too small output
    var small: [3]u8 = undefined;
    try testing.expectError(error.InvalidData, zlibDecompressInto(&z, &small, .{}));
}

test "fixed huffman block (zlib -9 of 'hello hello hello hello')" {
    // node: zlib.deflateSync(b'hello hello hello hello', 9)
    const z = [_]u8{ 0x78,0xda,0xcb,0x48,0xcd,0xc9,0xc9,0x57,0xc8,0x40,0x27,0x01,0x68,0x03,0x08,0xb1 };
    const out = try zlibDecompressAlloc(testing.allocator, &z, 1000, .{ .verify_checksum = true });
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("hello hello hello hello", out);
}

test "empty fixed block and edge errors" {
    // raw deflate: final fixed block with only EOB: bits 1,01 then 0000000 -> 0x03 0x00
    var dst: [1]u8 = undefined;
    try testing.expectEqual(@as(usize, 0), try inflateInto(&.{ 0x03, 0x00 }, &dst));
    // btype 3 invalid
    try testing.expectError(error.InvalidData, inflateInto(&.{0x07}, &dst));
    // distance too far back: fixed block, match before any literal
    try testing.expectError(error.InvalidData, inflateInto(&.{ 0x03, 0x02, 0x00 }, &dst));
    // truncated
    try testing.expectError(error.InvalidData, inflateInto(&.{}, &dst));
}

test "dynamic and fixed huffman text vectors" {
    const text = "The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs!";
    const dyn = [_]u8{0x78,0xda,0xb5,0xca,0xc9,0x01,0x80,0x20,0x0c,0x04,0xc0,0x56,0xd6,0x06,0xac,0xc5,0x07,0x0d,0x88,0x44,0x39,0x84,0x28,0x18,0x39,0xaa,0xb7,0x0a,0xe7,0x3d,0xca,0x12,0x6e,0x71,0x5b,0x80,0xce,0x5c,0x13,0x76,0x6e,0xf0,0x12,0xaf,0x02,0x7e,0x29,0xe3,0xb1,0x84,0x73,0x1d,0x1d,0x86,0x8f,0x19,0xea,0xb7,0xbc,0xac,0x5b,0x40,0xec,0xd0,0xdc,0x50,0xdd,0x63,0xb1,0xbb,0x97,0x60,0x78,0x50,0xc2,0xe9,0x6e,0xe1,0x0c,0x2f,0x47,0x99,0x3e,0xb2,0xee,0x3f,0x00};
    const fix = [_]u8{0x78,0x01,0x0b,0xc9,0x48,0x55,0x28,0x2c,0xcd,0x4c,0xce,0x56,0x48,0x2a,0xca,0x2f,0xcf,0x53,0x48,0xcb,0xaf,0x50,0xc8,0x2a,0xcd,0x2d,0x28,0x56,0xc8,0x2f,0x4b,0x2d,0x52,0x28,0xc9,0x48,0x55,0xc8,0x49,0xac,0xaa,0x54,0x48,0xc9,0x4f,0xd7,0x53,0x08,0xa1,0x99,0xe2,0x80,0xc4,0xe4,0x6c,0x85,0xdc,0x4a,0x85,0xa4,0xfc,0x0a,0x85,0xf2,0xcc,0x92,0x0c,0x85,0xb4,0xcc,0xb2,0x54,0x85,0x94,0xfc,0xaa,0xd4,0x3c,0x85,0x9c,0xcc,0xc2,0xd2,0xfc,0x22,0x85,0xac,0xd2,0xf4,0x62,0x45,0x00,0xb2,0xee,0x3f,0x00};
    var dst: [200]u8 = undefined;
    for ([_][]const u8{ &dyn, &fix }) |v| {
        const n = try zlibDecompressInto(v, &dst, .{ .verify_checksum = true });
        try testing.expectEqualStrings(text, dst[0..n]);
        // every truncation must fail cleanly (or decode a prefix without crashing)
        for (0..v.len - 1) |k| _ = zlibDecompressInto(v[0..k], &dst, .{ .verify_checksum = true }) catch continue;
    }
}

test "inflate fuzz: mutated / truncated / random streams never crash" {
    const deflate = @import("deflate.zig");
    var prng = std.Random.DefaultPrng.init(1234);
    const rnd = prng.random();
    var src: [6000]u8 = undefined;
    for (&src, 0..) |*b, i| b.* = @truncate((i * 7) / 13 + (if (i % 97 == 0) i else 0));
    var seeds: [4][]u8 = undefined;
    for ([_]deflate.Level{ .fastest, .fast, .default, .best }, 0..) |lv, i| seeds[i] = try deflate.compress(testing.allocator, &src, lv);
    defer for (seeds) |s| testing.allocator.free(s);
    var buf: [8192]u8 = undefined;
    var dst: [7000]u8 = undefined;
    for (0..20000) |it| {
        var len: usize = 0;
        if (it % 10 == 0) {
            len = rnd.uintLessThan(usize, 300);
            rnd.bytes(buf[0..len]);
            if (len >= 2 and rnd.boolean()) {
                buf[0] = 0x78;
                buf[1] = 0x9c;
            }
        } else {
            const s = seeds[it % 4];
            len = s.len;
            @memcpy(buf[0..len], s);
            for (0..1 + rnd.uintLessThan(usize, 4)) |_| {
                if (rnd.uintLessThan(u8, 5) == 0) {
                    len = rnd.uintLessThan(usize, len + 1);
                } else if (len > 0) buf[rnd.uintLessThan(usize, len)] ^= @as(u8, 1) << rnd.int(u3);
            }
        }
        _ = zlibDecompressInto(buf[0..len], &dst, .{ .verify_checksum = true }) catch {};
        if (zlibDecompressAlloc(testing.allocator, buf[0..len], 100_000, .{})) |o| testing.allocator.free(o) else |_| {}
        if (inflateAlloc(testing.allocator, buf[0..len], 100_000)) |o| testing.allocator.free(o) else |_| {}
    }
}
