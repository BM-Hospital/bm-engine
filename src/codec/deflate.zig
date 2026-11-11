//! DEFLATE / zlib compressor (RFC 1950/1951).
//! LZ77 with a 15-bit hash of 4 bytes (3..6 via `Options.hash_len`) + 32 KB hash chains (chain
//! depth, nice length and one-step lazy matching set by `Level`), symbols buffered per block (up to 16 K), each block
//! emitted as the cheapest of dynamic Huffman / fixed Huffman / stored (exact bit costs).
//!
//! Allocation: ~0.5 MB of working tables are allocated from `alloc` and freed before return;
//! the returned slice is owned by the caller (allocated from `alloc`, exactly sized).
const std = @import("std");
const bytes = @import("bytes.zig");
const huffman = @import("huffman.zig");
const checksum = @import("checksum.zig");

pub const Level = enum {
    /// Single hash probe, greedy, no insertion inside matches (fpng/libdeflate-1 class).
    fastest,
    /// Short chains, greedy (default for PNG).
    fast,
    /// chain 32 (8 for the lazy probe after a match >= 8), lazy; long pixel-run matches
    /// only hash their ends.
    default,
    /// chain 512, lazy, nice 258.
    best,
};

const Cfg = struct {
    chain: u32,
    nice: u32,
    lazy: u32,
    max_insert: u32,
    min3: bool = false,
    /// Bytes hashed for the chains (3..6); longer keys give shorter, better chains on image data.
    hash_len: u8 = 4,
    /// The lazy probe after a match of at least `good` walks only chain/4 (zlib good_length).
    good: u32 = 258,
    /// Matches at distance 1 or the first hint (pixel runs) longer than this only get their
    /// last 2 positions hashed: run positions all share one hash and flood its chain,
    /// while the distance hints already find runs.
    run_insert: u32 = 258,
};

fn cfgOf(level: Level) Cfg {
    return switch (level) {
        .fastest => .{ .chain = 1, .nice = 258, .lazy = 0, .max_insert = 0 },
        .fast => .{ .chain = 8, .nice = 258, .lazy = 0, .max_insert = 258 },
        .default => .{ .chain = 32, .nice = 258, .lazy = 258, .max_insert = 258, .run_insert = 16, .good = 8 },
        .best => .{ .chain = 512, .nice = 258, .lazy = 258, .max_insert = 258, .min3 = true, .hash_len = 3 },
    };
}

pub const Error = error{OutOfMemory};

pub const Options = struct {
    level: Level = .default,
    /// Distances always tried before the hash chain (e.g. PNG: bytes per pixel and the
    /// scanline stride), which finds long image matches with short chains. 0 = unused.
    dist_hints: [2]u32 = .{ 0, 0 },
    /// Bytes hashed for match candidates (3..6); 0 = the level default (4, or 3 for `.best`).
    /// 6 suits low-entropy data such as palette indices: shorter chains of better candidates.
    hash_len: u8 = 0,
};

/// zlib-wrapped DEFLATE of `input`.
pub fn compress(alloc: std.mem.Allocator, input: []const u8, level: Level) Error![]u8 {
    return compressEx(alloc, input, .{ .level = level });
}

/// zlib-wrapped DEFLATE of `input` with extra options.
pub fn compressEx(alloc: std.mem.Allocator, input: []const u8, opts: Options) Error![]u8 {
    var s = try Stream.init(alloc, opts, input.len / 2 + 64, 0, true);
    errdefer s.deinit();
    try s.write(input);
    try s.finish();
    return s.takeOutput();
}

/// Raw DEFLATE (no zlib wrapper) of `input`.
pub fn deflateRaw(alloc: std.mem.Allocator, input: []const u8, level: Level) Error![]u8 {
    var s = try Stream.init(alloc, .{ .level = level }, input.len / 2 + 64, 0, false);
    errdefer s.deinit();
    try s.write(input);
    try s.finish();
    return s.takeOutput();
}

const win_size = 4 * wsize;

fn rebase(t: []u32, k: u32) void {
    const V = @Vector(16, u32);
    const kv: V = @splat(k);
    var i: usize = 0;
    while (i + 16 <= t.len) : (i += 16) {
        const p: *align(4) V = @ptrCast(t[i..][0..16]);
        p.* = p.* -| kv;
    }
    while (i < t.len) : (i += 1) t[i] -|= k;
}
const lookahead = 262; // 258 (max match) + 4 (hash/lazy): streamed output equals one-shot output

/// Streaming compressor: feed data with `write` (any chunk sizes), then `finish`.
/// Scratch: hash heads 128 KB + chains 128 KB + symbols 64 KB + 128 KB window, all allocated in
/// `init` BEFORE the output buffer, so the output (the most recent allocation) can grow in
/// place in a bump arena; `deinit` frees in LIFO order.
pub const Stream = struct {
    alloc: std.mem.Allocator,
    st: State,
    win: []u8,
    w: Writer,
    adler: u32 = 1,
    zlib: bool,
    total: usize = 0,

    /// `out_cap`: initial output capacity guess. `prefix`: bytes reserved at the start of the
    /// output for the caller (e.g. PNG chunks before the IDAT data); compressed data follows.
    pub fn init(alloc: std.mem.Allocator, opts: Options, out_cap: usize, prefix: usize, zlib: bool) Error!Stream {
        const head = try alloc.alloc(u32, 1 << hash_bits);
        errdefer alloc.free(head);
        const prev = try alloc.alloc(u32, wsize);
        errdefer alloc.free(prev);
        const syms = try alloc.alloc(u32, block_syms);
        errdefer alloc.free(syms);
        const win = try alloc.alloc(u8, win_size);
        errdefer alloc.free(win);
        var w = try Writer.init(alloc, prefix + out_cap + 16);
        @memset(head, 0);
        w.pos = prefix;
        if (zlib) {
            w.buf[prefix] = 0x78;
            w.buf[prefix + 1] = switch (opts.level) {
                .fastest => 0x01,
                .fast => 0x5E,
                .default => 0x9C,
                .best => 0xDA,
            };
            w.pos += 2;
        }
        var st = State{ .src = win[0..0], .cfg = cfgOf(opts.level), .hints = opts.dist_hints, .head = head, .prev = prev, .syms = syms };
        if (opts.hash_len >= 3 and opts.hash_len <= 6) st.cfg.hash_len = opts.hash_len;
        if (st.cfg.min3) st.mask = 0xFFFFFF;
        st.hmask = (@as(u64, 1) << @intCast(8 * st.cfg.hash_len)) - 1;
        return .{ .alloc = alloc, .st = st, .win = win, .w = w, .zlib = zlib };
    }

    pub fn write(s: *Stream, data: []const u8) Error!void {
        var d = data;
        if (s.zlib) s.adler = adler32(s.adler, d);
        s.total += d.len;
        while (d.len > 0) {
            var fill = s.st.src.len;
            if (fill == s.win.len) {
                try process(&s.w, &s.st, fill - lookahead, false);
                // keep exactly one window of history before the next position
                const k = (s.st.pos - wsize) & ~@as(usize, wmask);
                // window 128K, pos >= 128K - 262  =>  k = 64K and fill - k = 64K: no overlap
                @memcpy(s.win[0 .. fill - k], s.win[k..fill]);
                // Chain entries are window-relative (pos+1): rebase, dropping what fell out.
                // k is a multiple of wsize, so prev[] slot indices (pos & wmask) stay valid.
                rebase(s.st.head, @intCast(k));
                rebase(s.st.prev, @intCast(k));
                s.st.base += k;
                s.st.pos -= k;
                s.st.ins -= k;
                fill -= k;
            }
            const n = @min(d.len, s.win.len - fill);
            @memcpy(s.win[fill..][0..n], d[0..n]);
            s.st.src = s.win[0 .. fill + n];
            d = d[n..];
        }
    }

    /// Restarts a raw (non-zlib, prefix 0) stream, keeping its tables and output buffer.
    pub fn reset(s: *Stream) void {
        @memset(s.st.head, 0);
        const o = s.st;
        s.st = .{ .src = s.win[0..0], .cfg = o.cfg, .hints = o.hints, .head = o.head, .prev = o.prev, .syms = o.syms, .mask = o.mask, .hmask = o.hmask };
        s.w.pos = 0;
        s.w.bits = 0;
        s.w.nbits = 0;
        s.adler = 1;
        s.total = 0;
    }

    /// Turns everything written so far into history: later data can match it, but it is not
    /// emitted (like a preset dictionary). Only valid before anything was encoded, i.e. less
    /// than ~128 KB written since `init`/`reset`. Used for trial compressions with context.
    pub fn markHistory(s: *Stream) void {
        const st = &s.st;
        const n = st.src.len;
        var q = st.ins;
        while (q + 8 <= n) : (q += 1) _ = st.insert(q);
        st.ins = n;
        st.pos = n;
        st.block_start = st.base + n;
        s.adler = 1;
        s.total = 0;
    }

    /// Emits the final block (and the zlib trailer). Output is `w.buf[0..w.pos]`.
    pub fn finish(s: *Stream) Error!void {
        if (s.total == 0) {
            try s.w.ensure(4);
            s.w.put(0b011, 3); // final, fixed
            s.w.put(0, 7); // EOB
        } else try process(&s.w, &s.st, s.st.src.len, true);
        s.w.alignByte();
        if (s.zlib) {
            try s.w.ensure(4);
            bytes.putBe32(s.w.buf, s.w.pos, s.adler);
            s.w.pos += 4;
        }
    }

    /// Frees the scratch tables (most recent first); the output in `w` is kept.
    pub fn freeScratch(s: *Stream) void {
        if (s.win.len == 0) return;
        s.alloc.free(s.win);
        s.alloc.free(s.st.syms);
        s.alloc.free(s.st.prev);
        s.alloc.free(s.st.head);
        s.win = &.{};
    }

    /// Frees everything, output first (LIFO).
    pub fn deinit(s: *Stream) void {
        s.w.deinit();
        s.freeScratch();
    }

    /// Finished output shrunk to size (caller owns it); scratch is freed.
    pub fn takeOutput(s: *Stream) Error![]u8 {
        const out = try s.w.finish();
        s.freeScratch();
        return out;
    }
};

// ------------------------------------------------------------------ bit writer

const Writer = struct {
    alloc: std.mem.Allocator,
    buf: []u8,
    pos: usize = 0,
    bits: u64 = 0,
    nbits: u32 = 0,

    fn init(alloc: std.mem.Allocator, cap: usize) Error!Writer {
        return .{ .alloc = alloc, .buf = try alloc.alloc(u8, @max(cap, 256)) };
    }

    fn deinit(w: *Writer) void {
        w.alloc.free(w.buf);
    }

    /// Guarantees `n` more bytes of room (plus 8 for the bit flusher).
    pub fn ensure(w: *Writer, n: usize) Error!void {
        const need = w.pos + n + 16;
        if (need <= w.buf.len) return;
        const new_len = @max(need, w.buf.len + w.buf.len / 2);
        w.buf = try w.alloc.realloc(w.buf, new_len);
    }

    /// Writes `n` (<= 32) bits; caller ensured room.
    inline fn put(w: *Writer, v: u32, n: u32) void {
        w.bits |= @as(u64, v) << @intCast(w.nbits);
        w.nbits += n;
        if (w.nbits >= 32) {
            bytes.putLe32(w.buf, w.pos, @truncate(w.bits));
            w.pos += 4;
            w.bits >>= 32;
            w.nbits -= 32;
        }
    }

    /// Flushes to a byte boundary (pads with zero bits).
    fn alignByte(w: *Writer) void {
        while (w.nbits > 0) {
            w.buf[w.pos] = @truncate(w.bits);
            w.pos += 1;
            w.bits >>= 8;
            w.nbits -|= 8;
        }
        w.bits = 0;
    }

    fn finish(w: *Writer) Error![]u8 {
        w.alignByte();
        if (w.alloc.resize(w.buf, w.pos)) return w.buf[0..w.pos];
        const r = try w.alloc.alloc(u8, w.pos);
        @memcpy(r, w.buf[0..w.pos]);
        w.alloc.free(w.buf);
        return r;
    }
};

// ------------------------------------------------------------------ tables

const len_base = [29]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
const len_extra = [29]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
const dist_base = [30]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
const dist_extra = [30]u8{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
const cl_order = [19]u8{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

/// Length code index (0..28) of a match length minus 3.
inline fn lenCode(x: u32) u32 {
    if (x < 8) return x;
    if (x == 255) return 28;
    const k: u32 = 31 - @clz(x);
    return 4 * (k - 1) + ((x >> @intCast(k - 2)) & 3);
}

/// Distance code (0..29) of distance minus 1.
inline fn distCode(x: u32) u32 {
    if (x < 4) return x;
    const k: u32 = 31 - @clz(x);
    return 2 * k + ((x >> @intCast(k - 1)) & 1);
}

const fixed_lit_lens: [288]u8 = blk: {
    var l: [288]u8 = undefined;
    for (0..144) |i| l[i] = 8;
    for (144..256) |i| l[i] = 9;
    for (256..280) |i| l[i] = 7;
    for (280..288) |i| l[i] = 8;
    break :blk l;
};

// ------------------------------------------------------------------ LZ77

const hash_bits = 15;
const wsize = 32768;
const wmask = wsize - 1;
const block_syms = 1 << 14;

inline fn read32(s: []const u8, i: usize) u32 {
    return bytes.le32(s, i);
}

/// Hash of the low bytes of the 8 at `i` selected by `m` (needs i + 8 <= s.len).
inline fn hashAt(s: []const u8, i: usize, m: u64) u32 {
    return @intCast(((bytes.le64(s, i) & m) *% 0x9E3779B97F4A7C15) >> (64 - hash_bits));
}

inline fn matchLen(s: []const u8, a: usize, b: usize, max: usize) usize {
    var l: usize = 0;
    while (l + 8 <= max) {
        const x = bytes.le64(s, a + l) ^ bytes.le64(s, b + l);
        if (x != 0) return l + (@ctz(x) >> 3);
        l += 8;
    }
    while (l < max and s[a + l] == s[b + l]) l += 1;
    return l;
}

const State = struct {
    src: []const u8,
    cfg: Cfg,
    hints: [2]u32,
    head: []u32, // position+1 of the latest occurrence of each hash, 0 = none
    prev: []u32, // position+1 of the previous occurrence, indexed by pos & wmask
    syms: []u32, // literal: byte; match: dist<<8 | (len-3)
    nsyms: usize = 0,
    lit_freq: [286]u32 = @splat(0),
    dist_freq: [30]u32 = @splat(0),
    block_start: usize = 0, // ABSOLUTE stream offset of the current block
    ins: usize = 0, // next position to insert into the hash chains (window-relative)
    pos: usize = 0, // next position to encode (window-relative)
    base: usize = 0, // absolute stream offset of src[0]
    mask: u32 = 0xFFFFFFFF, // 0xFFFFFF when 3-byte matches are enabled
    hmask: u64 = 0xFFFFFFFF, // bytes hashed (Cfg.hash_len)

    inline fn insert(st: *State, p: usize) u32 {
        const h = hashAt(st.src, p, st.hmask);
        const cand = st.head[h];
        st.head[h] = @intCast(p + 1);
        st.prev[p & wmask] = cand;
        return cand;
    }

    /// Inserts `p` (must equal `ins`) and returns the best match there (len 0 if none >= 4).
    fn find(st: *State, p: usize, max_chain: u32) struct { len: u32, dist: u32 } {
        const s = st.src;
        var c = st.insert(p);
        st.ins = p + 1;
        const max = @min(258, s.len - p);
        const m3 = st.mask != 0xFFFFFFFF;
        var best: usize = if (m3) 2 else 3;
        var best_d: usize = 0;
        var chain = max_chain;
        const first = read32(s, p) & st.mask;
        for (st.hints) |d| {
            if (d == 0 or d > p or d > wsize or best >= max) continue;
            const cp = p - d;
            if (s[cp + best] == s[p + best] and (read32(s, cp) & st.mask) == first) {
                const l = 3 + matchLen(s, cp + 3, p + 3, max - 3);
                if (l > best and (l > 3 or d <= 4096)) {
                    best = l;
                    best_d = d;
                    if (l >= st.cfg.nice) return .{ .len = @intCast(best), .dist = @intCast(best_d) };
                }
            }
        }
        while (c != 0 and chain > 0 and best < max) : (chain -= 1) {
            const cp: usize = c - 1;
            const d = p - cp;
            if (d > wsize) break;
            if (s[cp + best] == s[p + best] and (read32(s, cp) & st.mask) == first) {
                const l = 3 + matchLen(s, cp + 3, p + 3, max - 3);
                // a 3-byte match far away costs more than its literals (zlib's TOO_FAR)
                if (l > best and (l > 3 or d <= 4096)) {
                    best = l;
                    best_d = d;
                    if (l >= st.cfg.nice) break;
                }
            }
            const nc = st.prev[cp & wmask];
            if (nc >= c) break; // stale entry (slot reused by a newer position)
            c = nc;
        }
        if (best_d == 0) return .{ .len = 0, .dist = 0 };
        return .{ .len = @intCast(best), .dist = @intCast(best_d) };
    }

    inline fn lit(st: *State, b: u8) void {
        st.syms[st.nsyms] = b;
        st.nsyms += 1;
        st.lit_freq[b] += 1;
    }

    inline fn match(st: *State, len: u32, dist: u32) void {
        st.syms[st.nsyms] = (dist << 8) | (len - 3);
        st.nsyms += 1;
        st.lit_freq[257 + lenCode(len - 3)] += 1;
        st.dist_freq[distCode(dist - 1)] += 1;
    }
};

/// Encodes window positions [st.pos, upto). Non-final calls leave >= `lookahead` bytes unread
/// so every match search sees the same data a one-shot call would.
fn process(w: *Writer, stp: *State, upto: usize, final: bool) Error!void {
    // Work on a local copy: through a pointer, every field would be reloaded after each
    // store to head/prev/syms (possible aliasing), which cost ~20% in the hot loop.
    var local = stp.*;
    const st = &local;
    defer stp.* = local;
    const src = st.src;
    const n = src.len;
    var p = st.pos;
    // Positions >= limit cannot be hashed (8-byte loads).
    const limit = if (n >= 8) n - 7 else 0;
    while (p < upto) {
        if (st.nsyms >= block_syms - 2) {
            try emitBlock(w, st, p, false);
        }
        if (p >= limit) {
            st.lit(src[p]);
            p += 1;
            continue;
        }
        var m = st.find(p, st.cfg.chain);
        if (m.len == 0) {
            st.lit(src[p]);
            p += 1;
            continue;
        }
        // one-step lazy evaluation, repeated while it keeps improving
        while (m.len < st.cfg.lazy and p + 1 < limit) {
            const m2 = st.find(p + 1, if (m.len >= st.cfg.good) st.cfg.chain >> 2 else st.cfg.chain);
            if (m2.len <= m.len) break;
            st.lit(src[p]);
            p += 1;
            m = .{ .len = m2.len, .dist = m2.dist };
            if (st.nsyms >= block_syms - 2) break;
        }
        st.match(m.len, m.dist);
        const end = p + m.len;
        {
            // Long matches (beyond max_insert) only get their last 2 positions hashed, which
            // keeps short distances (e.g. one pixel back) reachable for the next match.
            const is_run = m.dist == 1 or m.dist == st.hints[0];
            const lim = if (is_run) st.cfg.run_insert else st.cfg.max_insert;
            var q = if (m.len <= lim) st.ins else @max(st.ins, end - 2);
            const e = @min(end, limit);
            while (q < e) : (q += 1) _ = st.insert(q);
        }
        st.ins = end;
        p = end;
    }
    st.pos = p;
    if (final) try emitBlock(w, st, n, true);
}

/// Encodes the buffered symbols covering src[block_start..end] as one block.
fn emitBlock(w: *Writer, st: *State, end: usize, final: bool) Error!void {
    st.lit_freq[256] = 1;
    var lit_lens: [286]u8 = undefined;
    var dist_lens: [30]u8 = undefined;
    _ = huffman.buildLengths(&st.lit_freq, &lit_lens, 15);
    // Keep at least two distance codes (some decoders reject a single/empty distance tree).
    var dfreq = st.dist_freq;
    var used: u32 = 0;
    for (dfreq) |f| used += @intFromBool(f != 0);
    if (used < 2) {
        if (dfreq[0] == 0) dfreq[0] = 1 else dfreq[1] = 1;
        if (used == 0) dfreq[1] = 1;
    }
    _ = huffman.buildLengths(&dfreq, &dist_lens, 15);

    // code-length RLE
    var hlit: usize = 286;
    while (hlit > 257 and lit_lens[hlit - 1] == 0) hlit -= 1;
    var hdist: usize = 30;
    while (hdist > 1 and dist_lens[hdist - 1] == 0) hdist -= 1;
    var all: [316]u8 = undefined;
    @memcpy(all[0..hlit], lit_lens[0..hlit]);
    @memcpy(all[hlit..][0..hdist], dist_lens[0..hdist]);
    const total = hlit + hdist;
    var items: [316]u16 = undefined; // sym | extra<<5
    var nitems: usize = 0;
    var cl_freq: [19]u32 = @splat(0);
    {
        var i: usize = 0;
        while (i < total) {
            const v = all[i];
            var run: usize = 1;
            while (i + run < total and all[i + run] == v) run += 1;
            i += run;
            if (v == 0) {
                while (run >= 11) {
                    const r = @min(run, 138);
                    items[nitems] = 18 | @as(u16, @intCast(r - 11)) << 5;
                    nitems += 1;
                    cl_freq[18] += 1;
                    run -= r;
                }
                if (run >= 3) {
                    items[nitems] = 17 | @as(u16, @intCast(run - 3)) << 5;
                    nitems += 1;
                    cl_freq[17] += 1;
                    run = 0;
                }
            } else {
                items[nitems] = v;
                nitems += 1;
                cl_freq[v] += 1;
                run -= 1;
                while (run >= 3) {
                    const r = @min(run, 6);
                    items[nitems] = 16 | @as(u16, @intCast(r - 3)) << 5;
                    nitems += 1;
                    cl_freq[16] += 1;
                    run -= r;
                }
            }
            while (run > 0) : (run -= 1) {
                items[nitems] = v;
                nitems += 1;
                cl_freq[v] += 1;
            }
        }
    }
    var cl_lens: [19]u8 = undefined;
    _ = huffman.buildLengths(&cl_freq, &cl_lens, 7);
    var hclen: usize = 19;
    while (hclen > 4 and cl_lens[cl_order[hclen - 1]] == 0) hclen -= 1;

    // exact bit costs
    var extra: u64 = 0;
    for (8..29) |i| extra += @as(u64, st.lit_freq[257 + i]) * len_extra[i];
    for (4..30) |i| extra += @as(u64, st.dist_freq[i]) * dist_extra[i];
    var dyn: u64 = 3 + 14 + 3 * @as(u64, hclen);
    for (items[0..nitems]) |it| {
        const s = it & 31;
        dyn += cl_lens[s] + @as(u64, switch (s) {
            16 => 2,
            17 => 3,
            18 => 7,
            else => 0,
        });
    }
    var fixed: u64 = 3;
    for (0..286) |i| {
        dyn += @as(u64, st.lit_freq[i]) * lit_lens[i];
        fixed += @as(u64, st.lit_freq[i]) * fixed_lit_lens[i];
    }
    for (0..30) |i| {
        dyn += @as(u64, st.dist_freq[i]) * dist_lens[i];
        fixed += @as(u64, st.dist_freq[i]) * 5;
    }
    dyn += extra;
    fixed += extra;
    const raw = st.base + end - st.block_start;
    const nstored = @max(1, (raw + 65534) / 65535);
    // A stored block needs its raw bytes, which must still be in the window.
    const can_store = st.block_start >= st.base;
    const stored: u64 = if (can_store) (raw + 4 * nstored) * 8 + 3 * nstored + 7 else std.math.maxInt(u64);

    try w.ensure(st.nsyms * 6 + (if (can_store) raw + 5 * nstored else 0) + 400);
    const fb: u32 = @intFromBool(final);
    if (stored <= dyn and stored <= fixed) {
        var rest = st.src[st.block_start - st.base .. end];
        while (true) {
            const take = @min(rest.len, 65535);
            const last = take == rest.len;
            w.put(if (last) fb else 0, 3);
            w.alignByte();
            std.mem.writeInt(u16, w.buf[w.pos..][0..2], @intCast(take), .little);
            std.mem.writeInt(u16, w.buf[w.pos + 2 ..][0..2], ~@as(u16, @intCast(take)), .little);
            w.pos += 4;
            @memcpy(w.buf[w.pos..][0..take], rest[0..take]);
            w.pos += take;
            rest = rest[take..];
            if (last) break;
        }
    } else {
        var lc: [288]u16 = undefined;
        var dc: [30]u16 = undefined;
        var ll: [288]u8 = undefined;
        var dl: [30]u8 = undefined;
        if (fixed < dyn) {
            w.put(fb | (1 << 1), 3);
            ll = fixed_lit_lens;
            @memset(&dl, 5);
        } else {
            w.put(fb | (2 << 1), 3);
            w.put(@intCast(hlit - 257), 5);
            w.put(@intCast(hdist - 1), 5);
            w.put(@intCast(hclen - 4), 4);
            for (cl_order[0..hclen]) |o| w.put(cl_lens[o], 3);
            var clc: [19]u16 = undefined;
            huffman.canonicalCodes(&cl_lens, &clc);
            for (items[0..nitems]) |it| {
                const s = it & 31;
                w.put(clc[s], cl_lens[s]);
                switch (s) {
                    16 => w.put(it >> 5, 2),
                    17 => w.put(it >> 5, 3),
                    18 => w.put(it >> 5, 7),
                    else => {},
                }
            }
            @memcpy(ll[0..286], &lit_lens);
            ll[286] = 0;
            ll[287] = 0;
            dl = dist_lens;
        }
        huffman.canonicalCodes(&ll, &lc);
        huffman.canonicalCodes(&dl, &dc);
        writeSyms(w, st.syms[0..st.nsyms], &lc, &ll, &dc, &dl);
        w.put(lc[256], ll[256]);
    }
    if (final) w.alignByte();
    st.nsyms = 0;
    st.lit_freq = @splat(0);
    st.dist_freq = @splat(0);
    st.block_start = st.base + end;
}

fn writeSyms(w: *Writer, syms: []const u32, lc: *const [288]u16, ll: *const [288]u8, dc: *const [30]u16, dl: *const [30]u8) void {
    for (syms) |s| {
        if (s < 256) {
            w.put(lc[s], ll[s]);
            continue;
        }
        const x = s & 255;
        const d = (s >> 8) - 1;
        const li = lenCode(x);
        const di = distCode(d);
        w.put(lc[257 + li], ll[257 + li]);
        w.put(x + 3 - len_base[li], len_extra[li]);
        w.put(dc[di], dl[di]);
        w.put(d + 1 - dist_base[di], dist_extra[di]);
    }
}

// ------------------------------------------------------------------ tests
const testing = std.testing;
const inflate = @import("inflate.zig");

fn roundTrip(data: []const u8, level: Level) !usize {
    const z = try compress(testing.allocator, data, level);
    defer testing.allocator.free(z);
    const back = try inflate.zlibDecompressAlloc(testing.allocator, z, data.len + 1, .{ .verify_checksum = true });
    defer testing.allocator.free(back);
    try testing.expectEqualSlices(u8, data, back);
    return z.len;
}

test "length/distance code helpers" {
    for (3..259) |l| {
        const c = lenCode(@intCast(l - 3));
        try testing.expect(l >= len_base[c] and l - len_base[c] < (@as(usize, 1) << @intCast(len_extra[c])) or (l == 258 and c == 28));
    }
    for (1..32769) |d| {
        const c = distCode(@intCast(d - 1));
        try testing.expect(d >= dist_base[c] and d - dist_base[c] < (@as(usize, 1) << @intCast(dist_extra[c])));
    }
}

test "deflate round trips at every level" {
    var prng = std.Random.DefaultPrng.init(42);
    const rnd = prng.random();
    const big = try testing.allocator.alloc(u8, 300_000);
    defer testing.allocator.free(big);
    const levels = [_]Level{ .fastest, .fast, .default, .best };
    // empty, tiny
    for (levels) |lv| {
        _ = try roundTrip("", lv);
        _ = try roundTrip("a", lv);
        _ = try roundTrip("abcd", lv);
        _ = try roundTrip("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab", lv);
    }
    // random (incompressible -> stored)
    rnd.bytes(big);
    for (levels) |lv| {
        const n = try roundTrip(big, lv);
        try testing.expect(n < big.len + big.len / 100 + 64);
    }
    // zeros
    @memset(big, 0);
    for (levels) |lv| {
        const n = try roundTrip(big, lv);
        if (n >= 1000) std.debug.print("zeros {} -> {}\n", .{ @intFromEnum(lv), n });
    }
    // text-like
    const words = [_][]const u8{ "the ", "quick ", "brown ", "fox ", "jumps ", "over ", "lazy ", "dog ", "and ", "a ", "PNG ", "image\n" };
    var i: usize = 0;
    while (i < big.len) {
        const wd = words[rnd.uintLessThan(usize, words.len)];
        const k = @min(wd.len, big.len - i);
        @memcpy(big[i..][0..k], wd[0..k]);
        i += k;
    }
    for (levels) |lv| {
        const n = try roundTrip(big, lv);
        try testing.expect(n < big.len / 3);
    }
    // image-like: gradient rows with noise, row-repeats
    for (big, 0..) |*b, j| {
        const x = j % 1200;
        const y = j / 1200;
        b.* = @truncate(x / 5 + y / 3 + (if (rnd.uintLessThan(u8, 16) == 0) rnd.int(u8) & 7 else 0));
    }
    for (levels) |lv| _ = try roundTrip(big, lv);
    // random small sizes / short alphabets
    for (0..300) |_| {
        const len = rnd.uintLessThan(usize, 5000);
        const alpha = 1 + rnd.uintLessThan(u8, 6);
        for (big[0..len]) |*b| b.* = rnd.uintLessThan(u8, alpha);
        _ = try roundTrip(big[0..len], levels[rnd.uintLessThan(usize, 4)]);
    }
}

test "hash_len option, reset and markHistory" {
    var prng = std.Random.DefaultPrng.init(11);
    const rnd = prng.random();
    const data = try testing.allocator.alloc(u8, 200_000);
    defer testing.allocator.free(data);
    for (data, 0..) |*b, i| b.* = @truncate((i % 997) / 9 + (if (rnd.uintLessThan(u8, 30) == 0) rnd.int(u8) & 3 else 0));
    for ([_]u8{ 3, 4, 5, 6 }) |hl| for ([_]Level{ .fast, .default }) |lv| {
        const z = try compressEx(testing.allocator, data, .{ .level = lv, .dist_hints = .{ 1, 997 }, .hash_len = hl });
        defer testing.allocator.free(z);
        const back = try inflate.zlibDecompressAlloc(testing.allocator, z, data.len, .{ .verify_checksum = true });
        defer testing.allocator.free(back);
        try testing.expectEqualSlices(u8, data, back);
    };
    // reset() gives the same bytes as a fresh raw stream; history makes the next part smaller
    var s = try Stream.init(testing.allocator, .{ .level = .fast }, 1024, 0, false);
    defer s.deinit();
    try s.write(data[0..50_000]);
    try s.finish();
    const fresh = try testing.allocator.dupe(u8, s.w.buf[0..s.w.pos]);
    defer testing.allocator.free(fresh);
    s.reset();
    try s.write(data[0..50_000]);
    try s.finish();
    try testing.expectEqualSlices(u8, fresh, s.w.buf[0..s.w.pos]);
    s.reset();
    try s.write(data[50_000..60_000]);
    try s.finish();
    const alone = s.w.pos;
    s.reset();
    try s.write(data[40_000..50_000]);
    s.markHistory();
    try s.write(data[50_000..60_000]);
    try s.finish();
    try testing.expect(s.w.pos < alone);
    // Valid deflate once the history precedes it as a (non-final) stored block.
    const cat = try testing.allocator.alloc(u8, 5 + 10_000 + s.w.pos);
    defer testing.allocator.free(cat);
    cat[0] = 0;
    std.mem.writeInt(u16, cat[1..3], 10_000, .little);
    std.mem.writeInt(u16, cat[3..5], ~@as(u16, 10_000), .little);
    @memcpy(cat[5..][0..10_000], data[40_000..50_000]);
    @memcpy(cat[10_005..], s.w.buf[0..s.w.pos]);
    const back = try inflate.inflateAlloc(testing.allocator, cat, 20_000);
    defer testing.allocator.free(back);
    try testing.expectEqualSlices(u8, data[40_000..60_000], back);
}

test "streamed writes in random chunks give the same bytes as one-shot" {
    var prng = std.Random.DefaultPrng.init(5);
    const rnd = prng.random();
    const data = try testing.allocator.alloc(u8, 400_000);
    defer testing.allocator.free(data);
    for (data, 0..) |*b, i| b.* = @truncate((i % 1201) / 7 + (if (rnd.uintLessThan(u8, 20) == 0) rnd.int(u8) else 0));
    for ([_]Level{ .fastest, .fast, .default, .best }) |lv| {
        const one = try compressEx(testing.allocator, data, .{ .level = lv, .dist_hints = .{ 3, 1201 } });
        defer testing.allocator.free(one);
        var s = try Stream.init(testing.allocator, .{ .level = lv, .dist_hints = .{ 3, 1201 } }, 100, 0, true);
        defer s.deinit();
        var rest: []const u8 = data;
        while (rest.len > 0) {
            const k = @min(rest.len, 1 + rnd.uintLessThan(usize, 70_000));
            try s.write(rest[0..k]);
            rest = rest[k..];
        }
        try s.finish();
        try testing.expectEqualSlices(u8, one, s.w.buf[0..s.w.pos]);
        const back = try inflate.zlibDecompressAlloc(testing.allocator, one, data.len, .{ .verify_checksum = true });
        defer testing.allocator.free(back);
        try testing.expectEqualSlices(u8, data, back);
    }
}

// ------------------------------------------------------------------ adler32

/// Adler-32 (same result as `checksum.adler32`), ~4x faster on wasm simd128: per 16-byte
/// block only vector adds; the position weights are applied once per 5552-byte chunk
/// (sum_blocks sum_j (16-j)*x[b][j] == sum_j (16-j) * sum_blocks x[b][j]).
fn adler32(adler: u32, data: []const u8) u32 {
    const base: u32 = 65521;
    var a: u32 = adler & 0xffff;
    var b: u32 = adler >> 16;
    var p = data;
    const V = @Vector(16, u32);
    const weights: V = .{ 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 };
    while (p.len > 0) {
        const n = @min(p.len, 5552);
        const nb = n / 16;
        var s1: V = @splat(0); // per-lane byte sums
        var s2: V = @splat(0); // sum over blocks of s1 before the block
        for (0..nb) |k| {
            const v: @Vector(16, u8) = @as(*align(1) const @Vector(16, u8), @ptrCast(p.ptr + k * 16)).*;
            s2 += s1;
            s1 += @as(V, v);
        }
        b += @as(u32, @intCast(nb * 16)) * a;
        b += 16 * (@reduce(.Add, s2) % base) + @reduce(.Add, s1 * weights);
        a += @reduce(.Add, s1);
        for (p[nb * 16 .. n]) |x| {
            a += x;
            b += a;
        }
        a %= base;
        b %= base;
        p = p[n..];
    }
    return (b << 16) | a;
}

test "adler32 matches checksum.adler32" {
    var buf: [40000]u8 = undefined;
    for (&buf, 0..) |*x, i| x.* = @truncate(i *% 7919 +% (i >> 3) +% (i *% i >> 5));
    for ([_]usize{ 0, 1, 15, 16, 17, 5551, 5552, 5553, 11104, 40000 }) |n| {
        try testing.expectEqual(checksum.adler32(1, buf[0..n]), adler32(1, buf[0..n]));
        try testing.expectEqual(checksum.adler32(0xfff0fff0, buf[0..n]), adler32(0xfff0fff0, buf[0..n]));
    }
    @memset(&buf, 255);
    try testing.expectEqual(checksum.adler32(1, &buf), adler32(1, &buf));
    try testing.expectEqual(checksum.adler32(0xfff0fff0, &buf), adler32(0xfff0fff0, &buf));
}
