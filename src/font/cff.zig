//! CFF / CFF2 outlines ('OTTO' fonts): INDEX / DICT parsing, FDArray / FDSelect, and a Type 2
//! charstring interpreter.
//!
//! Behaviour follows skrifa (FreeType's Adobe engine without hinting):
//!  * all arithmetic in 16.16 fixed point; path coordinates are truncated to whole font units
//!    (skrifa's `TransformSink`), so `outline` only ever emits integers;
//!  * degenerate moves / zero-length lines are dropped (`NopFilterSink`), every contour is a
//!    `moveTo ... close` sequence;
//!  * hints are parsed and skipped (stem counting for hintmask / cntrmask);
//!  * CFF2 `blend` / `vsindex` use the font's ItemVariationStore at the given coordinates.
//!
//! Not implemented: `seac`-style accented `endchar` (4 extra operands are ignored); of the
//! deprecated Type 2 arithmetic set only abs/add/sub/mul/div/neg/drop/dup/exch exist (and, or,
//! not, eq, put, get, ifelse, index, roll, random, sqrt clear the stack like any unknown
//! operator — fontTools does not implement them either); non-identity FontMatrix (the matrix is ignored: fonts whose unitsPerEm differs
//! from the CFF matrix scale render at the wrong size), Type 1 charstrings (CharstringType 1).
//!
//! Entry points: `parse` (once per font) and `outline` (per glyph). Nothing else in the
//! module is referenced from outside, so guarding those two call sites removes the file.
const std = @import("std");
const ttf = @import("ttf.zig");
const variations = @import("variations.zig");
const PathOut = ttf.PathOut;
const rd8 = ttf.rd8;
const rd16 = ttf.rd16;
const rd32 = ttf.rd32;
const fxMul = variations.fxMul;

/// Offsets (into the CFF / CFF2 table) found by `parse`.
pub const Info = struct {
    cff2: bool = false,
    /// CharStrings INDEX.
    charstrings: u32 = 0,
    /// Global Subr INDEX.
    gsubrs: u32 = 0,
    /// Font DICT INDEX (0 = none: name-keyed CFF1).
    fdarray: u32 = 0,
    /// FDSelect (0 = none).
    fdselect: u32 = 0,
    /// Private DICT named by the Top DICT (CFF1 without FDArray).
    private_off: u32 = 0,
    private_len: u32 = 0,
    /// CFF2: ItemVariationStore (0 = none).
    vstore: u32 = 0,
};

pub const ParseError = error{InvalidFont};

const Index = struct {
    count: u32 = 0,
    off_size: u32 = 1,
    /// Position of the offset array.
    offs: u32 = 0,
    /// Position just past the INDEX.
    end: u32 = 0,
};

fn rdOff(t: []const u8, p: u32, size: u32) u32 {
    var v: u32 = 0;
    var i: u32 = 0;
    while (i < size) : (i += 1) v = (v << 8) | rd8(t, p +| i);
    return v;
}

fn indexAt(t: []const u8, off: u32, cff2: bool) Index {
    const hdr: u32 = if (cff2) 4 else 2;
    if (off > t.len or t.len - off < hdr) return .{ .end = @intCast(@min(t.len, 0x7fff_ffff)) };
    const count: u32 = if (cff2) rd32(t, off) else rd16(t, off);
    if (count == 0) return .{ .end = off + hdr };
    const os: u32 = rd8(t, off + hdr);
    const offs = off + hdr + 1;
    if (os < 1 or os > 4 or count > 0x00ff_ffff) return .{ .end = off + hdr };
    const data = offs +| (count + 1) * os;
    const last = rdOff(t, offs + count * os, os);
    return .{ .count = count, .off_size = os, .offs = offs, .end = data -| 1 +| last };
}

fn indexGet(t: []const u8, ix: Index, i: u32) []const u8 {
    if (i >= ix.count) return &.{};
    const base = ix.offs + (ix.count + 1) * ix.off_size - 1;
    const a = base +| rdOff(t, ix.offs + i * ix.off_size, ix.off_size);
    const b = base +| rdOff(t, ix.offs + (i + 1) * ix.off_size, ix.off_size);
    if (a > b or b > t.len) return &.{};
    return t[a..b];
}

/// Last operands of operator `op` (two-byte operators as 0x0c00 | b1) in a DICT. Returns how
/// many operands were written to `out` (the last `out.len` at most); 0 when absent.
fn dictFind(dict: []const u8, op: u16, out: []i32) u32 {
    var stack: [8]i32 = undefined;
    var n: u32 = 0;
    var i: u32 = 0;
    while (i < dict.len) {
        const b: u32 = dict[i];
        i += 1;
        var val: i32 = 0;
        switch (b) {
            28 => {
                val = @as(i16, @bitCast(rd16(dict, i)));
                i += 2;
            },
            29 => {
                val = @bitCast(rd32(dict, i));
                i += 4;
            },
            30 => {
                // real number: nibbles up to 0xf (value irrelevant for the keys we read)
                while (i < dict.len) {
                    const v = dict[i];
                    i += 1;
                    if (v & 0x0f == 0x0f or v >> 4 == 0x0f) break;
                }
            },
            32...246 => val = @as(i32, @intCast(b)) - 139,
            247...250 => {
                val = @as(i32, @intCast((b - 247) * 256 + rd8(dict, i))) + 108;
                i += 1;
            },
            251...254 => {
                val = -@as(i32, @intCast((b - 251) * 256 + rd8(dict, i))) - 108;
                i += 1;
            },
            else => {
                var code: u16 = @intCast(b);
                if (b == 12) {
                    code = 0x0c00 | @as(u16, rd8(dict, i));
                    i += 1;
                }
                if (code == op) {
                    const k = @min(n, @as(u32, @intCast(out.len)));
                    @memcpy(out[0..k], stack[n - k .. n]);
                    return k;
                }
                n = 0;
                continue;
            },
        }
        if (n == stack.len) {
            std.mem.copyForwards(i32, stack[0 .. stack.len - 1], stack[1..]);
            n -= 1;
        }
        stack[n] = val;
        n += 1;
    }
    return 0;
}

fn dictOffset(dict: []const u8, op: u16) u32 {
    var v: [1]i32 = undefined;
    if (dictFind(dict, op, &v) != 1 or v[0] <= 0) return 0;
    return @intCast(v[0]);
}

/// Locates the structures needed for outlines. `table` is the 'CFF ' or 'CFF2' table.
pub fn parse(table: []const u8, cff2: bool) ParseError!Info {
    const t = table;
    if (t.len < 5 or t.len > 0x7fff_ffff) return error.InvalidFont;
    var info: Info = .{ .cff2 = cff2 };
    const hdr: u32 = t[2];
    var top: []const u8 = &.{};
    if (cff2) {
        if (t[0] != 2) return error.InvalidFont;
        const top_len: u32 = rd16(t, 3);
        if (hdr < 5 or hdr + top_len > t.len) return error.InvalidFont;
        top = t[hdr..][0..top_len];
        info.gsubrs = hdr + top_len;
        info.vstore = dictOffset(top, 24);
        // the store is preceded by its u16 length
        if (info.vstore != 0) info.vstore +|= 2;
    } else {
        if (t[0] != 1 or hdr < 4) return error.InvalidFont;
        const names = indexAt(t, hdr, false);
        const tops = indexAt(t, names.end, false);
        top = indexGet(t, tops, 0);
        const strings = indexAt(t, tops.end, false);
        info.gsubrs = strings.end;
        var cs_type: [1]i32 = .{2};
        if (dictFind(top, 0x0c06, &cs_type) == 1 and cs_type[0] != 2) return error.InvalidFont;
        var pr: [2]i32 = undefined;
        if (dictFind(top, 18, &pr) == 2 and pr[0] > 0 and pr[1] > 0) {
            info.private_len = @intCast(pr[0]);
            info.private_off = @intCast(pr[1]);
        }
    }
    info.charstrings = dictOffset(top, 17);
    info.fdarray = dictOffset(top, 0x0c24);
    info.fdselect = dictOffset(top, 0x0c25);
    if (info.charstrings == 0 or info.charstrings >= t.len or info.gsubrs > t.len) return error.InvalidFont;
    return info;
}

/// Number of charstrings (glyphs with outlines).
pub fn glyphCount(table: []const u8, info: Info) u32 {
    return indexAt(table, info.charstrings, info.cff2).count;
}

fn fdIndex(t: []const u8, info: Info, gid: u32) u32 {
    const p = info.fdselect;
    if (p == 0 or p >= t.len) return 0;
    switch (t[p]) {
        0 => return rd8(t, p + 1 +| gid),
        3, 4 => |fmt| {
            const wide = fmt == 4;
            const n: u32 = if (wide) rd32(t, p + 1) else rd16(t, p + 1);
            const first: u32 = if (wide) p + 5 else p + 3;
            const rec: u32 = if (wide) 6 else 3;
            const avail: u32 = @intCast((t.len - @min(t.len, first)) / rec);
            // last range whose first glyph is <= gid
            var lo: u32 = 0;
            var hi: u32 = @min(n, avail);
            while (lo < hi) {
                const m = (lo + hi) / 2;
                const g: u32 = if (wide) rd32(t, first + m * rec) else rd16(t, first + m * rec);
                if (g <= gid) lo = m + 1 else hi = m;
            }
            if (lo == 0) return 0;
            const r = first + (lo - 1) * rec;
            return if (wide) rd16(t, r + 4) else rd8(t, r + 2);
        },
        else => return 0,
    }
}

const max_stack = 513;
const max_depth = 10;
const max_ops = 200_000;
/// Path segments per glyph (a hostile charstring could otherwise emit ~10^8 of them).
const max_segments = 60_000;
const max_scalars = 64;

const Frame = struct { d: []const u8, pos: u32 };

const Pending = enum(u8) { none, move, line, curve };

const Interp = struct {
    t: []const u8,
    cff2: bool,
    gsubrs: Index,
    lsubrs: Index,
    out: *const PathOut,

    stack: [max_stack]i32 = undefined,
    top: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    open: bool = false,
    seen_width: bool,
    stems: u32 = 0,
    bad: bool = false,

    // CFF2 blending
    store: []const u8 = &.{},
    coords: []const i16 = &.{},
    regions: u32 = 0,
    region_off: u32 = 0,
    scalars: [max_scalars]i32 = undefined,

    // NopFilterSink state (coordinates already truncated to font units)
    pend: Pending = .none,
    pv: [6]i32 = undefined,
    f_open: bool = false,
    start: [2]i32 = .{ 0, 0 },
    any: bool = false,
    segs: u32 = 0,

    // ---- output: truncate to font units, drop degenerate segments

    inline fn units(v: i32) i32 {
        return fxMul(v, 0x400) >> 10;
    }

    fn flush(s: *Interp, for_close: bool) void {
        const p = s.pv;
        const kind = s.pend;
        s.pend = .none;
        s.segs += 1;
        if (s.segs > max_segments) {
            s.bad = true;
            return;
        }
        switch (kind) {
            .none => {},
            .move => if (!for_close) {
                s.f_open = true;
                s.start = .{ p[0], p[1] };
                s.out.moveTo(@floatFromInt(p[0]), @floatFromInt(p[1]));
            },
            .line => if (!for_close or s.start[0] != p[0] or s.start[1] != p[1]) {
                s.out.lineTo(@floatFromInt(p[0]), @floatFromInt(p[1]));
            },
            .curve => s.out.cubicTo(@floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]), @floatFromInt(p[3]), @floatFromInt(p[4]), @floatFromInt(p[5])),
        }
    }

    fn sinkMove(s: *Interp) void {
        s.pend = .move;
        s.pv[0] = units(s.x);
        s.pv[1] = units(s.y);
    }

    fn sinkClose(s: *Interp) void {
        s.flush(true);
        if (s.f_open) {
            s.out.close();
            s.f_open = false;
            s.any = true;
        }
    }

    fn ensureOpen(s: *Interp) void {
        if (!s.open) {
            s.open = true;
            s.pend = .move;
            s.pv[0] = 0;
            s.pv[1] = 0;
        }
    }

    fn line(s: *Interp) void {
        s.ensureOpen();
        const x = units(s.x);
        const y = units(s.y);
        if (s.pend != .none) {
            const tx = if (s.pend == .curve) s.pv[4] else s.pv[0];
            const ty = if (s.pend == .curve) s.pv[5] else s.pv[1];
            if (tx == x and ty == y) return;
        }
        s.flush(false);
        s.pend = .line;
        s.pv[0] = x;
        s.pv[1] = y;
    }

    fn moveTo(s: *Interp) void {
        if (!s.open) s.open = true else s.sinkClose();
        s.sinkMove();
    }

    // ---- operand stack

    fn push(s: *Interp, v: i32) void {
        if (s.top >= max_stack) {
            s.bad = true;
            return;
        }
        s.stack[s.top] = v;
        s.top += 1;
    }

    fn pop(s: *Interp) i32 {
        if (s.top == 0) {
            s.bad = true;
            return 0;
        }
        s.top -= 1;
        return s.stack[s.top];
    }

    fn arg(s: *Interp, i: u32) i32 {
        if (i >= s.top) {
            s.bad = true;
            return 0;
        }
        return s.stack[i];
    }

    const Mode = enum(u8) { dxdy, xdy, dxy, dydx, dx_init_y, larger };

    /// Consumes operands from `ix.*` according to `modes` (3 per curve) and emits the curves.
    fn curves(s: *Interp, ix: *u32, modes: []const Mode) void {
        const x0 = s.x;
        const y0 = s.y;
        var pts: [4]i32 = undefined;
        var count: u32 = 0;
        s.ensureOpen();
        for (modes) |m| {
            const i = ix.*;
            switch (m) {
                .dxdy => {
                    s.x +%= s.arg(i);
                    s.y +%= s.arg(i + 1);
                    ix.* += 2;
                },
                .dydx => {
                    s.y +%= s.arg(i);
                    s.x +%= s.arg(i + 1);
                    ix.* += 2;
                },
                .xdy => {
                    s.y +%= s.arg(i);
                    ix.* += 1;
                },
                .dxy => {
                    s.x +%= s.arg(i);
                    ix.* += 1;
                },
                .dx_init_y => {
                    s.x +%= s.arg(i);
                    s.y = y0;
                    ix.* += 1;
                },
                .larger => {
                    const d = s.arg(i);
                    if (@abs(@as(i64, s.x) - x0) > @abs(@as(i64, s.y) - y0)) {
                        s.x +%= d;
                        s.y = y0;
                    } else {
                        s.y +%= d;
                        s.x = x0;
                    }
                    ix.* += 1;
                },
            }
            if (count == 2) {
                s.flush(false);
                s.pend = .curve;
                s.pv = .{ units(pts[0]), units(pts[1]), units(pts[2]), units(pts[3]), units(s.x), units(s.y) };
                count = 0;
            } else {
                pts[count * 2] = s.x;
                pts[count * 2 + 1] = s.y;
                count += 1;
            }
        }
    }

    // ---- CFF2 variation support

    fn setVsIndex(s: *Interp, vsindex: u32) void {
        s.regions = 0;
        const d = variations.itemData(s.store, vsindex);
        if (d.len < 6) return;
        const n: u32 = rd16(d, 4);
        if (6 + n * 2 > d.len) return;
        s.regions = n;
        s.region_off = @intCast(@intFromPtr(d.ptr) - @intFromPtr(s.store.ptr) + 6);
        for (0..@min(n, max_scalars)) |i| s.scalars[i] = s.scalar(@intCast(i));
    }

    fn scalar(s: *Interp, i: u32) i32 {
        return variations.regionScalar(s.store, rd16(s.store, s.region_off + i * 2), s.coords);
    }

    fn blend(s: *Interp) void {
        const n_raw = s.pop() >> 16;
        if (n_raw < 0 or s.bad) {
            s.bad = true;
            return;
        }
        const n: u32 = @intCast(n_raw);
        const k = s.regions;
        const total = n *| (k + 1);
        if (total > s.top) {
            s.bad = true;
            return;
        }
        const base = s.top - total;
        var r: u32 = 0;
        while (r < k) : (r += 1) {
            const sc = if (r < max_scalars) s.scalars[r] else s.scalar(r);
            if (sc == 0) continue;
            var v: u32 = 0;
            while (v < n) : (v += 1) {
                s.stack[base + v] +%= fxMul(s.stack[base + n + k * v + r], sc);
            }
        }
        s.top = base + n;
    }

    // ---- hints

    /// hstem / vstem / hintmask preamble: optional width, then stem pairs (only counted).
    fn stemHints(s: *Interp) void {
        var len = s.top;
        if (len & 1 != 0 and !s.seen_width) len -= 1;
        s.seen_width = true;
        s.stems += len / 2;
        s.top = 0;
    }

    fn run(s: *Interp, charstring: []const u8) void {
        var frames: [max_depth + 1]Frame = undefined;
        var depth: u32 = 0;
        var d = charstring;
        var pos: u32 = 0;
        var ops: u32 = 0;
        while (!s.bad) {
            if (pos >= d.len) {
                // end of a (sub)charstring without `return`: resume the caller
                if (depth == 0) break;
                depth -= 1;
                d = frames[depth].d;
                pos = frames[depth].pos;
                continue;
            }
            ops += 1;
            if (ops > max_ops) break;
            const b0: u32 = d[pos];
            pos += 1;
            switch (b0) {
                28 => {
                    s.push(@as(i32, @as(i16, @bitCast(rd16(d, pos)))) << 16);
                    pos += 2;
                },
                32...246 => s.push((@as(i32, @intCast(b0)) - 139) << 16),
                247...250 => {
                    s.push((@as(i32, @intCast((b0 - 247) * 256 + rd8(d, pos))) + 108) << 16);
                    pos += 1;
                },
                251...254 => {
                    s.push((-@as(i32, @intCast((b0 - 251) * 256 + rd8(d, pos))) - 108) << 16);
                    pos += 1;
                },
                255 => {
                    s.push(@bitCast(rd32(d, pos)));
                    pos += 4;
                },
                // hstem, vstem, hstemhm, vstemhm
                1, 3, 18, 23 => s.stemHints(),
                // hintmask, cntrmask
                19, 20 => {
                    s.stemHints();
                    pos +|= (s.stems + 7) / 8;
                },
                // rmoveto
                21 => {
                    s.seen_width = true;
                    const dy = s.pop();
                    const dx = s.pop();
                    if (s.bad) break;
                    s.x +%= dx;
                    s.y +%= dy;
                    s.moveTo();
                    s.top = 0;
                },
                // hmoveto, vmoveto
                22, 4 => {
                    s.seen_width = true;
                    const delta = s.pop();
                    if (s.bad) break;
                    if (b0 == 22) s.x +%= delta else s.y +%= delta;
                    s.moveTo();
                    s.top = 0;
                },
                // rlineto
                5 => {
                    var i: u32 = 0;
                    while (i + 1 < s.top) : (i += 2) {
                        s.x +%= s.stack[i];
                        s.y +%= s.stack[i + 1];
                        s.line();
                    }
                    if (i < s.top) s.bad = true;
                    s.top = 0;
                },
                // hlineto, vlineto
                6, 7 => {
                    var is_x = b0 == 6;
                    for (s.stack[0..s.top]) |delta| {
                        if (is_x) s.x +%= delta else s.y +%= delta;
                        is_x = !is_x;
                        s.line();
                    }
                    s.top = 0;
                },
                // rrcurveto, rcurveline
                8, 24 => {
                    var ix: u32 = 0;
                    while (s.top - ix >= 6) s.curves(&ix, &.{ .dxdy, .dxdy, .dxdy });
                    if (b0 == 24) {
                        s.x +%= s.arg(ix);
                        s.y +%= s.arg(ix + 1);
                        if (!s.bad) s.line();
                    }
                    s.top = 0;
                },
                // rlinecurve
                25 => {
                    var ix: u32 = 0;
                    while (s.top - ix > 6) : (ix += 2) {
                        s.x +%= s.arg(ix);
                        s.y +%= s.arg(ix + 1);
                        if (!s.bad) s.line();
                    }
                    while (s.top - ix >= 6) s.curves(&ix, &.{ .dxdy, .dxdy, .dxdy });
                    s.top = 0;
                },
                // vvcurveto, hhcurveto
                26, 27 => {
                    const count = s.top & ~@as(u32, 2);
                    var ix: u32 = s.top - count;
                    while (ix < count and !s.bad) {
                        if ((count - ix) & 1 != 0) {
                            if (b0 == 26) s.x +%= s.arg(ix) else s.y +%= s.arg(ix);
                            ix += 1;
                        }
                        if (b0 == 26)
                            s.curves(&ix, &.{ .xdy, .dxdy, .xdy })
                        else
                            s.curves(&ix, &.{ .dxy, .dxdy, .dxy });
                    }
                    s.top = 0;
                },
                // vhcurveto, hvcurveto
                30, 31 => {
                    const count = s.top & ~@as(u32, 2);
                    var ix: u32 = s.top - count;
                    var horizontal = b0 == 31;
                    while (ix < count and !s.bad) {
                        const last = count - ix == 5;
                        if (horizontal)
                            s.curves(&ix, &.{ .dxy, .dxdy, if (last) .dydx else .xdy })
                        else
                            s.curves(&ix, &.{ .xdy, .dxdy, if (last) .dxdy else .dxy });
                        horizontal = !horizontal;
                    }
                    s.top = 0;
                },
                // callsubr, callgsubr
                10, 29 => {
                    const ix = if (b0 == 10) s.lsubrs else s.gsubrs;
                    const bias: i32 = if (ix.count < 1240) 107 else if (ix.count < 33900) 1131 else 32768;
                    const n = (s.pop() >> 16) +% bias;
                    if (s.bad or n < 0 or n >= ix.count or depth >= max_depth) {
                        s.bad = true;
                        break;
                    }
                    frames[depth] = .{ .d = d, .pos = pos };
                    depth += 1;
                    d = indexGet(s.t, ix, @intCast(n));
                    pos = 0;
                },
                // return
                11 => {
                    if (depth == 0) break;
                    depth -= 1;
                    d = frames[depth].d;
                    pos = frames[depth].pos;
                },
                // endchar
                14 => break,
                // CFF2: vsindex, blend
                15 => if (s.cff2) s.setVsIndex(@intCast(@max(0, s.pop() >> 16))) else {
                    s.top = 0;
                },
                16 => if (s.cff2) s.blend() else {
                    s.top = 0;
                },
                12 => {
                    const b1 = rd8(d, pos);
                    pos += 1;
                    s.escape(b1);
                },
                else => s.top = 0,
            }
        }
        if (s.open) s.sinkClose();
    }

    fn escape(s: *Interp, op: u8) void {
        var ix: u32 = 0;
        switch (op) {
            // hflex, flex, hflex1, flex1
            34 => s.curves(&ix, &.{ .dxy, .dxdy, .dxy, .dxy, .dx_init_y, .dxy }),
            35 => s.curves(&ix, &.{ .dxdy, .dxdy, .dxdy, .dxdy, .dxdy, .dxdy }),
            36 => s.curves(&ix, &.{ .dxdy, .dxdy, .dxy, .dxy, .dxdy, .dx_init_y }),
            37 => s.curves(&ix, &.{ .dxdy, .dxdy, .dxdy, .dxdy, .dxdy, .larger }),
            // abs, neg
            9, 14 => {
                const a = s.pop();
                const r: i32 = if (a < -0x7fff_ffff) 0x7fff_ffff else if (op == 9) @intCast(@abs(a)) else -a;
                return s.push(r);
            },
            // add, sub, mul, div
            10, 11, 24, 12 => {
                const b = s.pop();
                const a = s.pop();
                return s.push(switch (op) {
                    10 => a +% b,
                    11 => a -% b,
                    24 => fxMul(a, b),
                    else => variations.fxDiv(a, b),
                });
            },
            18 => {
                _ = s.pop();
                return;
            },
            // dup, exch
            27 => {
                const a = s.pop();
                s.push(a);
                return s.push(a);
            },
            28 => {
                const b = s.pop();
                const a = s.pop();
                s.push(b);
                return s.push(a);
            },
            else => {},
        }
        s.top = 0;
    }
};

/// Emits the outline of glyph `gid` in font units (y-up, whole units) to `out`. `coords` are
/// the normalised variation coordinates (CFF2; pass an empty slice for the default
/// instance). Returns false for empty or malformed glyphs.
///
/// Stack use: ~3 KiB (operand stack + scalars), no recursion (subroutine calls use an
/// explicit 10-deep frame stack).
pub noinline fn outline(table: []const u8, info: Info, coords: []const i16, gid: u32, out: *const PathOut) bool {
    const t = table;
    const cs = indexGet(t, indexAt(t, info.charstrings, info.cff2), gid);
    if (cs.len == 0) return false;

    // Private DICT of the glyph's font dict -> local subrs, vsindex
    var p_off = info.private_off;
    var p_len = info.private_len;
    if (info.fdarray != 0) {
        const fd = indexGet(t, indexAt(t, info.fdarray, info.cff2), fdIndex(t, info, gid));
        var pr: [2]i32 = undefined;
        if (dictFind(fd, 18, &pr) == 2 and pr[0] > 0 and pr[1] > 0) {
            p_len = @intCast(pr[0]);
            p_off = @intCast(pr[1]);
        } else p_len = 0;
    }
    var lsubrs: Index = .{};
    var vsindex: u32 = 0;
    if (p_len != 0 and p_off < t.len and p_len <= t.len - p_off) {
        const priv = t[p_off..][0..p_len];
        const rel = dictOffset(priv, 19);
        if (rel != 0) lsubrs = indexAt(t, p_off +| rel, info.cff2);
        var v: [1]i32 = undefined;
        if (info.cff2 and dictFind(priv, 22, &v) == 1 and v[0] > 0) vsindex = @intCast(v[0]);
    }

    var s: Interp = .{
        .t = t,
        .cff2 = info.cff2,
        .gsubrs = indexAt(t, info.gsubrs, info.cff2),
        .lsubrs = lsubrs,
        .out = out,
        .seen_width = info.cff2,
        .coords = coords,
    };
    if (info.cff2 and info.vstore != 0 and info.vstore < t.len) {
        s.store = t[info.vstore..];
        s.setVsIndex(vsindex);
    }
    s.run(cs);
    return s.any;
}

// ------------------------------------------------------------------ tests

const tt = std.testing;

/// Records path commands as text: "M x y", "L x y", "C a b c d x y", "Z".
const Rec = struct {
    buf: [1024]u8 = undefined,
    n: usize = 0,
    fn emit(ctx: *anyopaque, verb: PathOut.Verb, p: *const [6]f32) void {
        const r: *Rec = @ptrCast(@alignCast(ctx));
        const k: usize = switch (verb) {
            .move, .line => 2,
            .quad => 4,
            .cubic => 6,
            .close => 0,
        };
        r.n += (std.fmt.bufPrint(r.buf[r.n..], "{c}", .{"MLQCZ"[@intFromEnum(verb)]}) catch unreachable).len;
        for (p[0..k]) |v| r.n += (std.fmt.bufPrint(r.buf[r.n..], " {d}", .{v}) catch unreachable).len;
        r.n += (std.fmt.bufPrint(r.buf[r.n..], ";", .{}) catch unreachable).len;
    }
    fn out(r: *Rec) PathOut {
        return .{ .ctx = r, .emit = emit };
    }
    fn str(r: *const Rec) []const u8 {
        return r.buf[0..r.n];
    }
};

/// Runs a bare charstring with optional local / global subroutines (given as INDEX bytes).
fn evalCs(cs: []const u8, cff2: bool, r: *Rec) bool {
    return evalCsSubrs(cs, cff2, &.{}, r);
}

fn evalCsSubrs(cs: []const u8, cff2: bool, subr_index: []const u8, r: *Rec) bool {
    const po = r.out();
    var s: Interp = .{
        .t = subr_index,
        .cff2 = cff2,
        .gsubrs = indexAt(subr_index, 0, cff2),
        .lsubrs = indexAt(subr_index, 0, cff2),
        .out = &po,
        .seen_width = cff2,
    };
    s.run(cs);
    return s.any;
}

// number encodings used below: 139 + n for -107..107
fn n8(comptime v: i32) u8 {
    return @intCast(v + 139);
}

test "charstring: moves, lines, width operand, implicit close" {
    var r: Rec = .{};
    // width 50, rmoveto(10,20) rlineto(30,0, 0,40) hlineto(-30) endchar
    try tt.expect(evalCs(&.{ n8(50), n8(10), n8(20), 21, n8(30), n8(0), n8(0), n8(40), 5, n8(-30), 6, 14 }, false, &r));
    try tt.expectEqualStrings("M 10 20;L 40 20;L 40 60;L 10 60;Z;", r.str());
    // hmoveto with width, vlineto alternating, vmoveto starts a second contour
    r = .{};
    try tt.expect(evalCs(&.{ n8(7), n8(5), 22, n8(10), n8(20), n8(-10), 7, n8(100), 4, n8(1), n8(1), 5, 14 }, false, &r));
    try tt.expectEqualStrings("M 5 0;L 5 10;L 25 10;L 25 0;Z;M 25 100;L 26 101;Z;", r.str());
    // a line back to the start is dropped at close; zero-length lines are dropped
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), n8(0), 21, n8(10), n8(0), n8(0), n8(0), n8(0), n8(10), n8(-10), n8(-10), 5, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;L 10 0;L 10 10;Z;", r.str());
    // lone moveto: no contour at all
    r = .{};
    try tt.expect(!evalCs(&.{ n8(1), n8(2), 21, 14 }, false, &r));
    try tt.expectEqualStrings("", r.str());
    // a path operator without moveto starts at the origin
    r = .{};
    try tt.expect(evalCs(&.{ n8(5), n8(5), 5, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;L 5 5;Z;", r.str());
}

test "charstring: number encodings and fractional truncation" {
    var r: Rec = .{};
    // 28: 1000; 247..: 300; 251..: -300; 255: 16.16 2.75 and -0.5 (truncate towards -inf)
    try tt.expect(evalCs(&.{ 28, 0x03, 0xe8, 247, 192, 21, 251, 192, n8(0), 255, 0, 2, 0xc0, 0, 255, 0xff, 0xff, 0x80, 0, 5, 14 }, false, &r));
    try tt.expectEqualStrings("M 1000 300;L 700 300;L 702 299;Z;", r.str());
}

test "charstring: all curve operators" {
    var r: Rec = .{};
    // rrcurveto x2
    try tt.expect(evalCs(&.{ n8(0), n8(0), 21, n8(1), n8(2), n8(3), n8(4), n8(5), n8(6), n8(1), n8(1), n8(1), n8(1), n8(1), n8(1), 8, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 1 2 4 6 9 12;C 10 13 11 14 12 15;Z;", r.str());
    // hhcurveto with leading dy: dy1 dxa dxb dyb dxc
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(5), n8(10), n8(20), n8(30), n8(40), 27, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 10 5 30 35 70 35;Z;", r.str());
    // vvcurveto with leading dx: dx1 dya dxb dyb dyc
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(5), n8(10), n8(20), n8(30), n8(40), 26, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 5 10 25 40 25 80;Z;", r.str());
    // hvcurveto: dx1 dx2 dy2 dy3, then (vertical) dy1 dx2 dy2 dx3 + final dy (odd tail)
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(10), n8(20), n8(30), n8(40), n8(1), n8(2), n8(3), n8(4), n8(5), 31, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 10 0 30 30 30 70;C 30 71 32 74 36 79;Z;", r.str());
    // vhcurveto: dy1 dx2 dy2 dx3
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(10), n8(20), n8(30), n8(40), 30, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 0 10 20 40 60 40;Z;", r.str());
    // rcurveline, rlinecurve
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(1), n8(1), n8(1), n8(1), n8(1), n8(1), n8(5), n8(-5), 24, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 1 1 2 2 3 3;L 8 -2;Z;", r.str());
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(5), n8(-5), n8(1), n8(1), n8(1), n8(1), n8(1), n8(1), 25, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;L 5 -5;C 6 -4 7 -3 8 -2;Z;", r.str());
}

test "charstring: flex variants" {
    var r: Rec = .{};
    // flex: 6 points + fd
    try tt.expect(evalCs(&.{ n8(0), 22, n8(1), n8(2), n8(3), n8(4), n8(5), n8(6), n8(7), n8(8), n8(9), n8(10), n8(11), n8(12), n8(50), 12, 35, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 1 2 4 6 9 12;C 16 20 25 30 36 42;Z;", r.str());
    // hflex: dx1 dx2 dy2 dx3 dx4 dx5 dx6 (returns to the starting y)
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(10), n8(10), n8(5), n8(10), n8(10), n8(10), n8(10), 12, 34, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 10 0 20 5 30 5;C 40 5 50 0 60 0;Z;", r.str());
    // hflex1: dx1 dy1 dx2 dy2 dx3 dx4 dx5 dy5 dx6
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(10), n8(1), n8(10), n8(4), n8(10), n8(10), n8(10), n8(-4), n8(10), 12, 36, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 10 1 20 5 30 5;C 40 5 50 1 60 0;Z;", r.str());
    // flex1: 5 points, last delta applies to the dominant direction (x here)
    r = .{};
    try tt.expect(evalCs(&.{ n8(0), 22, n8(10), n8(1), n8(10), n8(1), n8(10), n8(1), n8(10), n8(-1), n8(10), n8(-1), n8(10), 12, 37, 14 }, false, &r));
    try tt.expectEqualStrings("M 0 0;C 10 1 20 2 30 3;C 40 2 50 1 60 0;Z;", r.str());
}

test "charstring: hints are skipped, hintmask bytes counted" {
    var r: Rec = .{};
    // width + hstemhm (2 stems), vstem via hintmask preamble (1 stem) -> 3 stems -> 1 mask
    // byte (0xff would be an invalid operator if it were executed), cntrmask 1 byte
    try tt.expect(evalCs(&.{ n8(99), n8(1), n8(2), n8(3), n8(4), 18, n8(5), n8(6), 19, 0xff, 20, 0x0e, n8(10), n8(10), 21, n8(5), n8(5), 5, 14 }, false, &r));
    try tt.expectEqualStrings("M 10 10;L 15 15;Z;", r.str());
    // 9 stems need 2 mask bytes
    r = .{};
    var cs: [64]u8 = undefined;
    var n: usize = 0;
    for (0..18) |_| {
        cs[n] = n8(1);
        n += 1;
    }
    for ([_]u8{ 1, 19, 14, 14, n8(3), n8(4), 21, n8(1), n8(1), 5, 14 }) |b| {
        cs[n] = b;
        n += 1;
    }
    try tt.expect(evalCs(cs[0..n], false, &r));
    try tt.expectEqualStrings("M 3 4;L 4 5;Z;", r.str());
}

test "charstring: subroutines with bias, return, depth limit" {
    // INDEX with 2 subrs: #0 = "rlineto(5,5) return", #1 = "callsubr(#0) rlineto(1,0)" (no return)
    const subrs = [_]u8{ 0, 2, 1, 1, 5, 10 } ++ [_]u8{ n8(5), n8(5), 5, 11 } ++ [_]u8{ n8(-107), 10, n8(1), n8(0), 5 };
    var r: Rec = .{};
    try tt.expect(evalCsSubrs(&.{ n8(0), 22, n8(-106), 10, n8(2), n8(2), 5, 14 }, false, &subrs, &r));
    try tt.expectEqualStrings("M 0 0;L 5 5;L 6 5;L 8 7;Z;", r.str());
    // callgsubr uses the same INDEX in this harness
    r = .{};
    try tt.expect(evalCsSubrs(&.{ n8(0), 22, n8(-107), 29, 14 }, false, &subrs, &r));
    try tt.expectEqualStrings("M 0 0;L 5 5;Z;", r.str());
    // out-of-range subr index: glyph stops, path so far is closed
    r = .{};
    _ = evalCsSubrs(&.{ n8(0), 22, n8(3), n8(3), 5, n8(50), 10, n8(9), n8(9), 5, 14 }, false, &subrs, &r);
    try tt.expectEqualStrings("M 0 0;L 3 3;Z;", r.str());
    // infinite recursion: subr #0 calls itself
    const rec = [_]u8{ 0, 1, 1, 1, 3 } ++ [_]u8{ n8(-107), 10 };
    r = .{};
    try tt.expect(!evalCsSubrs(&.{ n8(-107), 10, 14 }, false, &rec, &r));
}

test "charstring: arithmetic operators and malformed input" {
    var r: Rec = .{};
    // 3 4 add 2 mul (=14)  20 5 div (=4)  rmoveto; 7 neg abs dup exch sub (=0) 9 rlineto
    try tt.expect(evalCs(&.{ n8(3), n8(4), 12, 10, n8(2), 12, 24, n8(20), n8(5), 12, 12, 21, n8(7), 12, 14, 12, 9, 12, 27, 12, 28, 12, 11, n8(9), 5, 14 }, false, &r));
    try tt.expectEqualStrings("M 14 4;L 14 13;Z;", r.str());
    // stack underflow, truncated operands, unknown operators: no crash
    const junk = [_][]const u8{ &.{21}, &.{ 12, 35 }, &.{ 28, 1 }, &.{255}, &.{ n8(1), 8 }, &.{ 2, 9, 13, 17, 12, 99, 14 }, &.{ 12, 30 }, &.{ n8(5), n8(1), 12, 30 }, &.{ n8(1), 16 }, &.{ n8(1), 15 }, &.{10}, &.{29}, &.{19} };
    for (junk) |j| {
        r = .{};
        _ = evalCs(j, false, &r);
        r = .{};
        _ = evalCs(j, true, &r);
    }
    // stack overflow
    var big: [600]u8 = @splat(n8(1));
    big[599] = 5;
    r = .{};
    _ = evalCs(&big, false, &r);
}

test "INDEX, DICT and FDSelect parsing" {
    const idx = [_]u8{ 0, 3, 1, 1, 3, 3, 6, 'a', 'b', 'x', 'y', 'z' };
    const ix = indexAt(&idx, 0, false);
    try tt.expectEqual(@as(u32, 3), ix.count);
    try tt.expectEqual(@as(u32, 12), ix.end);
    try tt.expectEqualStrings("ab", indexGet(&idx, ix, 0));
    try tt.expectEqualStrings("", indexGet(&idx, ix, 1));
    try tt.expectEqualStrings("xyz", indexGet(&idx, ix, 2));
    try tt.expectEqualStrings("", indexGet(&idx, ix, 3));
    try tt.expectEqual(@as(u32, 2), indexAt(&.{ 0, 0, 9, 9 }, 0, false).end);
    try tt.expectEqual(@as(u32, 4), indexAt(&.{ 0, 0, 0, 0, 9 }, 0, true).end);
    // truncated data: offsets beyond the table give empty objects
    try tt.expectEqualStrings("", indexGet(idx[0..9], indexAt(idx[0..9], 0, false), 2));

    // DICT: real number, 5-byte int, private (size, offset), escaped operator
    const dict = [_]u8{ 30, 0x1a, 0x5f, 5, 29, 0, 1, 0, 0, 17, n8(20), 28, 0x12, 0x34, 18, 247, 0, 12, 36 };
    var two: [2]i32 = undefined;
    try tt.expectEqual(@as(u32, 0x10000), dictOffset(&dict, 17));
    try tt.expectEqual(@as(u32, 2), dictFind(&dict, 18, &two));
    try tt.expectEqualSlices(i32, &.{ 20, 0x1234 }, &two);
    try tt.expectEqual(@as(u32, 108), dictOffset(&dict, 0x0c24));
    try tt.expectEqual(@as(u32, 0), dictOffset(&dict, 19));

    // FDSelect format 0 and 3
    var info: Info = .{ .fdselect = 1 };
    const f0 = [_]u8{ 9, 0, 4, 5, 6 };
    try tt.expectEqual(@as(u32, 5), fdIndex(&f0, info, 1));
    try tt.expectEqual(@as(u32, 0), fdIndex(&f0, info, 100));
    const f3 = [_]u8{ 9, 3, 0, 2, 0, 0, 7, 0, 10, 8, 0, 20 };
    try tt.expectEqual(@as(u32, 7), fdIndex(&f3, info, 0));
    try tt.expectEqual(@as(u32, 7), fdIndex(&f3, info, 9));
    try tt.expectEqual(@as(u32, 8), fdIndex(&f3, info, 10));
    try tt.expectEqual(@as(u32, 8), fdIndex(&f3, info, 5000));
    info.fdselect = 0;
    try tt.expectEqual(@as(u32, 0), fdIndex(&f3, info, 10));
}

test "CFF2 blend with a variation store" {
    // store: 1 axis, regions [0,1,1] and [-1,-1,0]; subtable 0 uses both, subtable 1 only #1
    const store = [_]u8{ 0, 1, 0, 0, 0, 16, 0, 2, 0, 0, 0, 32, 0, 0, 0, 42 } ++
        [_]u8{ 0, 1, 0, 2, 0, 0, 0x40, 0, 0x40, 0, 0xc0, 0, 0xc0, 0, 0, 0 } ++
        [_]u8{ 0, 0, 0, 0, 0, 2, 0, 0, 0, 1 } ++
        [_]u8{ 0, 0, 0, 0, 0, 1, 0, 1 };
    const Case = struct { coord: i16, vs: u8, want: []const u8 };
    const cases = [_]Case{
        .{ .coord = 0, .vs = 0, .want = "M 10 20;L 110 20;Z;" },
        .{ .coord = 16384, .vs = 0, .want = "M 15 20;L 135 20;Z;" },
        .{ .coord = 8192, .vs = 0, .want = "M 12 20;L 122 20;Z;" },
        .{ .coord = -16384, .vs = 0, .want = "M 4 20;L 94 20;Z;" },
        .{ .coord = -16384, .vs = 1, .want = "M 15 20;L 135 20;Z;" },
    };
    for (cases) |c| {
        var r: Rec = .{};
        const po = r.out();
        var s: Interp = .{ .t = &.{}, .cff2 = true, .gsubrs = .{}, .lsubrs = .{}, .out = &po, .seen_width = true, .coords = &.{c.coord}, .store = &store };
        s.setVsIndex(0);
        // [vsindex] 10 (5 -6) 1 blend 20 rmoveto; 100 (20 -10) 1 blend hlineto
        const k2 = [_]u8{ n8(10), n8(5), n8(-6), n8(1), 16, n8(20), 21, n8(100), n8(20), n8(-10), n8(1), 16, 6 };
        const k1 = [_]u8{ n8(1), 15, n8(10), n8(5), n8(1), 16, n8(20), 21, n8(100), n8(20), n8(1), 16, 6 };
        s.run(if (c.vs == 0) &k2 else &k1);
        try tt.expectEqualStrings(c.want, r.str());
    }
}
