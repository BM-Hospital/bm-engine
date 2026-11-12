//! `CFF ` table subsetter: a port of subsetter/cff/** from the subsetter crate vendored in
//! takumi-pdf (MIT OR Apache-2.0, ref/takumi/takumi-pdf/LICENSE-SUBSETTER).
//!
//! Every kept charstring is desubroutinised (global and local subroutines inlined, the Subrs
//! entries dropped), SID-keyed fonts are converted to CID-keyed ones (one FDArray entry, ROS
//! Adobe-Identity-0) and the charset maps CID n to new glyph n (identity), so the PDF can use
//! the new glyph id as CID for every font. Byte layout, DICT operand encodings and the
//! FontMatrix rules follow the Rust code exactly.
//!
//! Not supported (as in Rust): `seac`-style `endchar` with 4+ operands (error.Unimplemented).
const std = @import("std");
const subset_mod = @import("subset.zig");
const Allocator = std.mem.Allocator;
const GlyphRemapper = subset_mod.GlyphRemapper;
const W = subset_mod.W;
const be16 = subset_mod.be16;
const be32 = subset_mod.be32;

pub const Error = subset_mod.Error;

// ------------------------------------------------------------------- numbers

const Number = union(enum) {
    real: f32,
    int: i32,
    fixed: i32,

    fn asF64(n: Number) f64 {
        return switch (n) {
            .int => |v| @floatFromInt(v),
            .real => |v| v,
            .fixed => |v| @as(f32, @floatFromInt(v)) / 65536.0,
        };
    }

    fn asI32(n: Number) ?i32 {
        const f: f32 = switch (n) {
            .int => |v| return v,
            .real => |v| v,
            .fixed => |v| @as(f32, @floatFromInt(v)) / 65536.0,
        };
        if (f != @trunc(f)) return null;
        return @intFromFloat(std.math.clamp(f, -2147483648.0, 2147483520.0));
    }

    fn asU32(n: Number) ?u32 {
        const v = n.asI32() orelse return null;
        return if (v < 0) null else @intCast(v);
    }
};

const Reader = struct {
    d: []const u8,
    p: usize = 0,

    fn atEnd(r: *const Reader) bool {
        return r.p >= r.d.len;
    }
    fn peek(r: *const Reader) ?u8 {
        return if (r.p < r.d.len) r.d[r.p] else null;
    }
    fn u8_(r: *Reader) ?u8 {
        if (r.p >= r.d.len) return null;
        r.p += 1;
        return r.d[r.p - 1];
    }
    fn u16_(r: *Reader) ?u16 {
        const v = be16(r.d, r.p) orelse return null;
        r.p += 2;
        return v;
    }
    fn u32_(r: *Reader) ?u32 {
        const v = be32(r.d, r.p) orelse return null;
        r.p += 4;
        return v;
    }
    fn bytes(r: *Reader, n: usize) ?[]const u8 {
        if (r.p > r.d.len or r.d.len - r.p < n) return null;
        r.p += n;
        return r.d[r.p - n .. r.p];
    }
};

fn parseInteger(r: *Reader) ?i32 {
    const b0 = r.u8_() orelse return null;
    return switch (b0) {
        28 => @as(i16, @bitCast(r.u16_() orelse return null)),
        29 => @bitCast(r.u32_() orelse return null),
        32...246 => @as(i32, b0) - 139,
        247...250 => (@as(i32, b0) - 247) * 256 + @as(i32, r.u8_() orelse return null) + 108,
        251...254 => -(@as(i32, b0) - 251) * 256 - @as(i32, r.u8_() orelse return null) - 108,
        else => null,
    };
}

/// CFF real (nibble-encoded), accepted and rounded like Rust's `f32::from_str` on the
/// nibble string (`[-]digits[.digits][E[-]digits]`, at least one mantissa digit).
fn parseReal(r: *Reader) ?f32 {
    if ((r.u8_() orelse return null) != 30) return null;
    var chars: [65]u8 = undefined;
    var n: usize = 0;
    outer: while (true) {
        const b = r.u8_() orelse return null;
        for ([2]u8{ b >> 4, b & 15 }) |nib| {
            if (nib == 0xf) break :outer;
            if (n >= 64) return null;
            switch (nib) {
                0...9 => chars[n] = '0' + nib,
                10 => chars[n] = '.',
                11 => chars[n] = 'E',
                12 => {
                    if (n + 1 >= 64) return null;
                    chars[n] = 'E';
                    n += 1;
                    chars[n] = '-';
                },
                14 => chars[n] = '-',
                else => return null,
            }
            n += 1;
        }
    }
    return decimalStrToF32(chars[0..n]);
}

fn decimalStrToF32(s: []const u8) ?f32 {
    var i: usize = 0;
    const neg = s.len > 0 and s[0] == '-';
    if (neg) i = 1;
    var mant: u64 = 0;
    var exp10: i32 = 0;
    var digits: u32 = 0;
    var dot = false;
    while (i < s.len and s[i] != 'E') : (i += 1) {
        const ch = s[i];
        if (ch == '.') {
            if (dot) return null;
            dot = true;
            continue;
        }
        if (ch < '0' or ch > '9') return null;
        digits += 1;
        if (mant < 1_000_000_000_000_000_000) {
            mant = mant * 10 + (ch - '0');
            if (dot) exp10 -= 1;
        } else if (!dot) exp10 += 1;
    }
    if (digits == 0) return null;
    if (i < s.len) {
        i += 1;
        var eneg = false;
        if (i < s.len and s[i] == '-') {
            eneg = true;
            i += 1;
        }
        if (i == s.len) return null;
        var e: i32 = 0;
        while (i < s.len) : (i += 1) {
            if (s[i] < '0' or s[i] > '9') return null;
            if (e < 10000) e = e * 10 + (s[i] - '0');
        }
        exp10 += if (eneg) -e else e;
    }
    const v: f32 = @floatCast(scale10(@floatFromInt(mant), exp10));
    return if (neg) -v else v;
}

const pow10_exact = blk: {
    var t: [23]f64 = undefined;
    t[0] = 1;
    for (1..23) |k| t[k] = t[k - 1] * 10;
    break :blk t;
};

/// x * 10^k in f64 (one rounding while |k| <= 22).
fn scale10(x: f64, k: i32) f64 {
    var v = x;
    var e = k;
    if (v == 0) return 0;
    while (e > 22) : (e -= 22) v *= pow10_exact[22];
    while (e < -22) : (e += 22) v /= pow10_exact[22];
    return if (e >= 0) v * pow10_exact[@intCast(e)] else v / pow10_exact[@intCast(-e)];
}

/// `v` formatted like Rust's `Display` for f32: the shortest decimal that parses back to `v`,
/// never in exponent notation ("0.001", "1", "-0", "123456790").
fn formatF32(buf: *[64]u8, v: f32) []const u8 {
    var n: usize = 0;
    if (std.math.signbit(v)) {
        buf[0] = '-';
        n = 1;
    }
    const x: f64 = @abs(@as(f64, v));
    if (x == 0 or !std.math.isFinite(v)) {
        buf[n] = '0';
        return buf[0 .. n + 1];
    }
    var e: i32 = 0; // ~floor(log10(x)); verified by the round trip below
    var t = x;
    while (t >= 10) : (e += 1) t /= 10;
    while (t < 1) : (e -= 1) t *= 10;
    var p: i32 = 1;
    while (p <= 9) : (p += 1) {
        const k = p - 1 - e;
        const m_f = @round(scale10(x, k));
        if (m_f < 1 or m_f >= 1e18) continue;
        const m: u64 = @intFromFloat(m_f);
        const back: f32 = @floatCast(scale10(m_f, -k));
        if (back != @abs(v)) continue;
        // digits of m, value = m * 10^-k
        var dg: [20]u8 = undefined;
        var dl: usize = 0;
        var mm = m;
        while (mm > 0) : (mm /= 10) {
            dg[dl] = '0' + @as(u8, @intCast(mm % 10));
            dl += 1;
        }
        std.mem.reverse(u8, dg[0..dl]);
        var q: i32 = -k; // decimal exponent of the last digit
        while (dl > 1 and dg[dl - 1] == '0' and q < 0) {
            dl -= 1;
            q += 1;
        }
        if (q >= 0) {
            @memcpy(buf[n..][0..dl], dg[0..dl]);
            n += dl;
            for (0..@intCast(q)) |_| {
                buf[n] = '0';
                n += 1;
            }
        } else {
            const pos: i32 = @as(i32, @intCast(dl)) + q;
            if (pos > 0) {
                const up: usize = @intCast(pos);
                @memcpy(buf[n..][0..up], dg[0..up]);
                n += up;
                buf[n] = '.';
                n += 1;
                @memcpy(buf[n..][0 .. dl - up], dg[up..dl]);
                n += dl - up;
            } else {
                buf[n] = '0';
                buf[n + 1] = '.';
                n += 2;
                for (0..@intCast(-pos)) |_| {
                    buf[n] = '0';
                    n += 1;
                }
                @memcpy(buf[n..][0..dl], dg[0..dl]);
                n += dl;
            }
        }
        return buf[0..n];
    }
    buf[n] = '0';
    return buf[0 .. n + 1];
}

fn parseNumber(r: *Reader, charstring: bool) ?Number {
    const b = r.peek() orelse return null;
    if (b == 30) return .{ .real = parseReal(r) orelse return null };
    if (b == 255) {
        if (!charstring) return null;
        _ = r.u8_();
        return .{ .fixed = @bitCast(r.u32_() orelse return null) };
    }
    return .{ .int = parseInteger(r) orelse return null };
}

fn writeInt5(w: *W, v: i32) Error!void {
    try w.u8_(29);
    try w.u32_(@bitCast(v));
}

fn writeInt(w: *W, v: i32) Error!void {
    if (v >= -107 and v <= 107) {
        try w.u8_(@intCast(v + 139));
    } else if (v >= 108 and v <= 1131) {
        const t = v - 108;
        try w.u8_(@intCast(@divTrunc(t, 256) + 247));
        try w.u8_(@intCast(@mod(t, 256)));
    } else if (v >= -1131 and v <= -108) {
        const t = -v - 108;
        try w.u8_(@intCast(@divTrunc(t, 256) + 251));
        try w.u8_(@intCast(@mod(t, 256)));
    } else if (v >= -32768 and v <= 32767) {
        try w.u8_(28);
        try w.i16_(@intCast(v));
    } else try writeInt5(w, v);
}

/// Formats like Rust's `Display` for f32 (shortest round-trip digits, never an exponent).
fn writeReal(w: *W, v: f32) Error!void {
    var buf: [64]u8 = undefined;
    const s = formatF32(&buf, v);
    var nibbles: [130]u8 = undefined;
    var n: usize = 0;
    for (s) |ch| {
        nibbles[n] = switch (ch) {
            '0'...'9' => ch - '0',
            '.' => 0xa,
            '-' => 0xe,
            else => continue,
        };
        n += 1;
    }
    nibbles[n] = 0xf;
    n += 1;
    if (n % 2 != 0) {
        nibbles[n] = 0xf;
        n += 1;
    }
    try w.u8_(30);
    var i: usize = 0;
    while (i < n) : (i += 2) try w.u8_(nibbles[i] << 4 | nibbles[i + 1]);
}

fn writeNumber(w: *W, n: Number) Error!void {
    switch (n) {
        .int => |v| try writeInt(w, v),
        .real => |v| try writeReal(w, v),
        .fixed => |v| {
            try w.u8_(255);
            try w.u32_(@bitCast(v));
        },
    }
}

fn writeOp(w: *W, o: u16) Error!void {
    if (o >= 0x0c00) try w.u8_(12);
    try w.u8_(@truncate(o));
}

// --------------------------------------------------------------------- INDEX

const Index = struct {
    /// The object data (offset 1 = data[0]).
    data: []const u8 = &.{},
    /// The raw offset array.
    offsets: []const u8 = &.{},
    off_size: u8 = 1,

    fn offsetCount(ix: *const Index) u32 {
        return @intCast(ix.offsets.len / ix.off_size);
    }

    fn offsetAt(ix: *const Index, i: u32) ?u32 {
        if (i >= ix.offsetCount()) return null;
        const p = @as(usize, i) * ix.off_size;
        var v: u32 = 0;
        for (ix.offsets[p..][0..ix.off_size]) |b| v = v << 8 | b;
        return if (v == 0) null else v - 1;
    }

    fn len(ix: *const Index) u32 {
        return ix.offsetCount() -| 1;
    }

    fn get(ix: *const Index, i: u32) ?[]const u8 {
        const a = ix.offsetAt(i) orelse return null;
        const b = ix.offsetAt(i +% 1) orelse return null;
        if (a > b or b > ix.data.len) return null;
        return ix.data[a..b];
    }

    /// Items up to the first malformed one (like the Rust `IndexIter`).
    fn items(ix: *const Index, a: Allocator) Error![]const []const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        var i: u32 = 0;
        while (i < ix.len()) : (i += 1) try list.append(a, ix.get(i) orelse break);
        return list.items;
    }
};

fn parseIndex(r: *Reader) ?Index {
    const count: u32 = r.u16_() orelse return null;
    if (count == 0) return .{};
    const os = r.u8_() orelse return null;
    if (os < 1 or os > 4) return null;
    const offsets = r.bytes((count + 1) * os) orelse return null;
    var ix: Index = .{ .offsets = offsets, .off_size = os };
    const last = ix.offsetAt(ix.offsetCount() - 1) orelse return .{};
    ix.data = r.bytes(last) orelse return null;
    return ix;
}

/// CFF INDEX of `items`; `header` receives the size of everything before the data.
fn createIndex(w: *W, items: []const []const u8, header: ?*usize) Error!void {
    if (items.len > 0xffff) return error.OverflowError;
    if (items.len == 0) {
        try w.u16_(0);
        if (header) |h| h.* = 2;
        return;
    }
    var total: u64 = 1;
    for (items) |it| total += it.len;
    const os: u8 = if (total <= 0xff) 1 else if (total <= 0xffff) 2 else if (total <= 0xffffff) 3 else 4;
    const start = w.len();
    try w.u16_(@intCast(items.len));
    try w.u8_(os);
    var cur: u32 = 1;
    try putOff(w, cur, os);
    for (items) |it| {
        cur += @intCast(it.len);
        try putOff(w, cur, os);
    }
    if (header) |h| h.* = w.len() - start;
    for (items) |it| try w.bytes(it);
}

fn putOff(w: *W, v: u32, os: u8) Error!void {
    var k: u8 = os;
    while (k > 0) {
        k -= 1;
        try w.u8_(@truncate(v >> @intCast(8 * @as(u32, k))));
    }
}

// --------------------------------------------------------------------- DICT

const op = struct {
    const notice: u16 = 1;
    const font_bbox: u16 = 5;
    const charset: u16 = 15;
    const encoding: u16 = 16;
    const char_strings: u16 = 17;
    const private: u16 = 18;
    const subrs: u16 = 19;
    const copyright: u16 = 0x0c00;
    const font_matrix: u16 = 0x0c07;
    const ros: u16 = 0x0c1e;
    const cid_count: u16 = 0x0c22;
    const fd_array: u16 = 0x0c24;
    const fd_select: u16 = 0x0c25;
    const font_name: u16 = 0x0c26;
};

fn isDictOp(b: u8) bool {
    return b <= 27 or b == 31 or b == 255;
}

const max_operands = 48;

const DictParser = struct {
    data: []const u8,
    offset: usize = 0,
    operands_offset: usize = 0,
    operands: [max_operands]Number = undefined,
    n: usize = 0,

    fn next(p: *DictParser) ?u16 {
        var r: Reader = .{ .d = p.data, .p = p.offset };
        p.operands_offset = p.offset;
        while (!r.atEnd()) {
            const b = r.peek().?;
            if (isDictOp(b)) {
                _ = r.u8_();
                var o: u16 = b;
                if (b == 12) o = 0x0c00 | @as(u16, r.u8_() orelse return null);
                p.offset = r.p;
                return o;
            }
            _ = parseNumber(&r, false) orelse return null;
        }
        return null;
    }

    fn parseOperands(p: *DictParser) ?void {
        var r: Reader = .{ .d = p.data, .p = p.operands_offset };
        p.n = 0;
        while (!r.atEnd()) {
            const b = r.peek().?;
            if (isDictOp(b)) {
                _ = r.u8_();
                break;
            }
            p.operands[p.n] = parseNumber(&r, false) orelse return null;
            p.n += 1;
            if (p.n >= max_operands) break;
        }
    }

    fn ops(p: *const DictParser) []const Number {
        return p.operands[0..p.n];
    }

    fn sid(p: *DictParser) ?u16 {
        p.parseOperands() orelse return null;
        if (p.n != 1) return null;
        const v = p.operands[0].asI32() orelse return null;
        return if (v < 0 or v > 0xffff) null else @intCast(v);
    }

    fn offsetVal(p: *DictParser) ?usize {
        p.parseOperands() orelse return null;
        if (p.n != 1) return null;
        return @as(usize, p.operands[0].asU32() orelse return null);
    }

    fn array(p: *DictParser, comptime N: usize) ?[N]Number {
        p.parseOperands() orelse return null;
        if (p.n != N) return null;
        return p.operands[0..N].*;
    }

    fn range(p: *DictParser) ?[2]usize {
        p.parseOperands() orelse return null;
        if (p.n != 2) return null;
        const l: usize = p.operands[0].asU32() orelse return null;
        const s: usize = p.operands[1].asU32() orelse return null;
        return .{ s, s + l };
    }
};

const TopDict = struct {
    char_strings: ?usize = null,
    private: ?[2]usize = null,
    fd_array: ?usize = null,
    fd_select: ?usize = null,
    notice: ?u16 = null,
    copyright: ?u16 = null,
    font_name: ?u16 = null,
    has_ros: bool = false,
    font_matrix: ?[6]Number = null,
    font_bbox: ?[4]Number = null,
};

fn parseTopDict(r: *Reader) ?TopDict {
    var top: TopDict = .{};
    const ix = parseIndex(r) orelse return null;
    const data = ix.get(0) orelse return null;
    var p: DictParser = .{ .data = data };
    while (p.next()) |o| switch (o) {
        op.notice => top.notice = p.sid() orelse return null,
        op.copyright => top.copyright = p.sid() orelse return null,
        op.font_name => top.font_name = p.sid() orelse return null,
        op.charset => _ = p.offsetVal() orelse return null,
        op.char_strings => top.char_strings = p.offsetVal() orelse return null,
        op.private => top.private = p.range() orelse return null,
        op.ros => top.has_ros = true,
        op.fd_array => top.fd_array = p.offsetVal() orelse return null,
        op.fd_select => top.fd_select = p.offsetVal() orelse return null,
        op.font_matrix => top.font_matrix = p.array(6) orelse return null,
        op.font_bbox => top.font_bbox = p.array(4) orelse return null,
        else => {},
    };
    return top;
}

fn parseSubrOffset(data: []const u8) ?usize {
    var p: DictParser = .{ .data = data };
    while (p.next()) |o| if (o == op.subrs) return p.offsetVal();
    return null;
}

/// Local subrs of a Private DICT at `range` of `cff` (empty when absent).
fn localSubrs(cff: []const u8, range: [2]usize, pd: []const u8) ?Index {
    const off = parseSubrOffset(pd) orelse return .{};
    const start = range[0] + off;
    if (start > cff.len) return null;
    var r: Reader = .{ .d = cff[start..] };
    return parseIndex(&r);
}

const FontDict = struct {
    local_subrs: Index = .{},
    private_dict: []const u8 = &.{},
    font_name: ?u16 = null,
    font_matrix: ?[6]Number = null,
};

fn parseFontDict(cff: []const u8, data: []const u8) ?FontDict {
    var fd: FontDict = .{};
    var p: DictParser = .{ .data = data };
    while (p.next()) |o| switch (o) {
        op.private => {
            const range = p.range() orelse return null;
            if (range[1] > cff.len or range[0] > range[1]) return null;
            fd.private_dict = cff[range[0]..range[1]];
            fd.local_subrs = localSubrs(cff, range, fd.private_dict) orelse return null;
        },
        op.font_name => fd.font_name = p.sid() orelse return null,
        op.font_matrix => fd.font_matrix = p.array(6) orelse return null,
        else => {},
    };
    return fd;
}

const FdSelect = struct {
    format: u8,
    data: []const u8,
    n_glyphs: u16,

    fn index(s: *const FdSelect, gid: u16) ?u8 {
        if (s.format == 0) {
            if (gid >= s.n_glyphs) return null;
            return s.data[gid];
        }
        var r: Reader = .{ .d = s.data };
        const nr = r.u16_() orelse return null;
        if (nr == 0) return null;
        const total = @as(u32, nr) + 1;
        var prev_first = r.u16_() orelse return null;
        var prev_index = r.u8_() orelse return null;
        var i: u32 = 1;
        while (i < total) : (i += 1) {
            const cur_first = r.u16_() orelse return null;
            if (gid >= prev_first and gid < cur_first) return prev_index;
            prev_index = r.u8_() orelse return null;
            prev_first = cur_first;
        }
        return null;
    }
};

// ---------------------------------------------------------------- charstrings

const Subrs = struct {
    list: []const []const u8,
    bias: i32,

    fn init(list: []const []const u8) Subrs {
        const n = list.len;
        return .{ .list = list, .bias = if (n < 1240) 107 else if (n < 33900) 1131 else 32768 };
    }

    fn get(s: *const Subrs, biased: i32) ?[]const u8 {
        const i = std.math.add(i32, biased, s.bias) catch return null;
        if (i < 0 or i >= s.list.len) return null;
        return s.list[@intCast(i)];
    }
};

/// Desubroutinising charstring decompiler (fontTools-style), writing the flattened program.
const Decompiler = struct {
    gsubrs: *const Subrs,
    lsubrs: *const Subrs,
    a: Allocator,
    out: W,
    /// Start offset of every instruction in `out` (so the operand of a call can be removed).
    starts: std.ArrayList(u32) = .empty,
    stack: [max_operands]Number = undefined,
    sp: usize = 0,
    hint_count: u16 = 0,
    hint_mask_bytes: u16 = 0,

    const End = enum { ret, endchar };

    fn begin(d: *Decompiler) Error!void {
        try d.starts.append(d.a, @intCast(d.out.len()));
    }

    fn countHints(d: *Decompiler) void {
        d.hint_count +%= @intCast(d.sp / 2);
        d.sp = 0;
    }

    fn call(d: *Decompiler, subrs: *const Subrs, depth: u8) Error!?End {
        // Pop the subroutine index from the program.
        if (d.starts.pop()) |s| d.out.buf.shrinkRetainingCapacity(s);
        if (d.sp == 0) return error.CFFError;
        d.sp -= 1;
        const idx = d.stack[d.sp].asI32() orelse return error.CFFError;
        const sub = subrs.get(idx) orelse return error.CFFError;
        if (try d.run(sub, depth + 1) == .endchar) return .endchar;
        return null;
    }

    fn run(d: *Decompiler, cs: []const u8, depth: u8) Error!End {
        if (depth > 64) return error.CFFError;
        var r: Reader = .{ .d = cs };
        while (!r.atEnd()) {
            const b0 = r.peek().?;
            if (b0 == 28 or b0 >= 32) {
                const n = parseNumber(&r, true) orelse return error.CFFError;
                if (d.sp == max_operands) return error.CFFError;
                d.stack[d.sp] = n;
                d.sp += 1;
                try d.begin();
                try writeNumber(&d.out, n);
                continue;
            }
            _ = r.u8_();
            var o: u16 = b0;
            if (b0 == 12) o = 0x0c00 | @as(u16, r.u8_() orelse return error.CFFError);
            switch (o) {
                // flex family
                0x0c22,
                0x0c23,
                0x0c24,
                0x0c25,
                // path construction
                4,
                5,
                6,
                7,
                8,
                21,
                22,
                24,
                25,
                26,
                27,
                30,
                31,
                => {
                    d.sp = 0;
                    try d.begin();
                    try writeOp(&d.out, o);
                },
                // stems
                1, 3, 18, 23 => {
                    d.countHints();
                    try d.begin();
                    try writeOp(&d.out, o);
                },
                11 => return .ret,
                29 => if (try d.call(d.gsubrs, depth)) |e| return e,
                10 => if (try d.call(d.lsubrs, depth)) |e| return e,
                // hintmask / cntrmask
                19, 20 => {
                    try d.begin();
                    try writeOp(&d.out, o);
                    if (d.hint_mask_bytes == 0) {
                        d.countHints();
                        d.hint_mask_bytes = (d.hint_count + 7) / 8;
                    }
                    const mask = r.bytes(d.hint_mask_bytes) orelse return error.CFFError;
                    try d.begin();
                    try d.out.bytes(mask);
                },
                14 => {
                    if (d.sp >= 4) return error.Unimplemented; // seac
                    try d.begin();
                    try writeOp(&d.out, o);
                    return .endchar;
                },
                else => return error.CFFError,
            }
        }
        return .ret;
    }
};

// ------------------------------------------------------------------ remappers

/// New SIDs (from 391) for the non-standard strings that are kept.
const SidRemapper = struct {
    strings: std.ArrayList([]const u8) = .empty,
    old: std.ArrayList([2]u16) = .empty,

    fn get(s: *const SidRemapper, str: []const u8) ?u16 {
        for (s.strings.items, 0..) |e, i| if (std.mem.eql(u8, e, str)) return @intCast(391 + i);
        return null;
    }
    fn getNew(s: *const SidRemapper, old_sid: u16) ?u16 {
        for (s.old.items) |e| if (e[0] == old_sid) return e[1];
        return null;
    }
    fn remap(s: *SidRemapper, a: Allocator, str: []const u8) Error!u16 {
        if (s.get(str)) |v| return v;
        if (391 + s.strings.items.len > 0xffff) return error.OverflowError;
        try s.strings.append(a, str);
        return @intCast(391 + s.strings.items.len - 1);
    }
    fn remapOld(s: *SidRemapper, a: Allocator, old_sid: u16, str: []const u8) Error!void {
        if (s.getNew(old_sid) != null) return;
        const n = try s.remap(a, str);
        try s.old.append(a, .{ old_sid, n });
    }
};

// ------------------------------------------------------------------- subset

const Deferred = struct {
    location: usize = 0,
    value: i32 = 0,
    set: bool = false,
};

const Kind = union(enum) {
    sid: struct { local_subrs: Index, private_dict: []const u8 },
    cid: struct { dicts: []const FontDict, fd_select: FdSelect },
};

/// Subsets the `CFF ` table `cff` to the glyphs of `mapper` (in its order). The result is
/// allocated with `a` (meant to be an arena: temporaries are not freed).
pub fn subset(a: Allocator, cff: []const u8, mapper: *const GlyphRemapper) Error![]const u8 {
    // ---- parse
    var r: Reader = .{ .d = cff };
    const major = r.u8_() orelse return error.MalformedFont;
    if (major != 1) return error.CFFError;
    _ = r.u8_();
    const hdr = r.u8_() orelse return error.MalformedFont;
    r.p = hdr;
    const names_start = r.p;
    _ = parseIndex(&r) orelse return error.MalformedFont;
    const names = cff[names_start..r.p];
    const top = parseTopDict(&r) orelse return error.MalformedFont;
    const strings = parseIndex(&r) orelse return error.MalformedFont;
    const gsubr_index = parseIndex(&r) orelse return error.MalformedFont;
    const cs_off = top.char_strings orelse return error.MalformedFont;
    if (cs_off > cff.len) return error.MalformedFont;
    var csr: Reader = .{ .d = cff, .p = cs_off };
    const char_strings = parseIndex(&csr) orelse return error.MalformedFont;
    const n_glyphs_u32 = char_strings.len();
    if (n_glyphs_u32 == 0 or n_glyphs_u32 > 0xffff) return error.MalformedFont;
    const n_glyphs: u16 = @intCast(n_glyphs_u32);

    var kind: Kind = undefined;
    if (top.has_ros) {
        const fa = top.fd_array orelse return error.MalformedFont;
        const fs = top.fd_select orelse return error.MalformedFont;
        if (fa > cff.len or fs >= cff.len) return error.MalformedFont;
        var far: Reader = .{ .d = cff, .p = fa };
        const fd_array = parseIndex(&far) orelse return error.MalformedFont;
        const sel: FdSelect = blk: {
            const fmt = cff[fs];
            const rest = cff[fs + 1 ..];
            switch (fmt) {
                0 => {
                    if (rest.len < n_glyphs) return error.MalformedFont;
                    break :blk .{ .format = 0, .data = rest[0..n_glyphs], .n_glyphs = n_glyphs };
                },
                3 => break :blk .{ .format = 3, .data = rest, .n_glyphs = n_glyphs },
                else => return error.MalformedFont,
            }
        };
        var dicts: std.ArrayList(FontDict) = .empty;
        for (try fd_array.items(a)) |fdd| try dicts.append(a, parseFontDict(cff, fdd) orelse return error.MalformedFont);
        kind = .{ .cid = .{ .dicts = dicts.items, .fd_select = sel } };
    } else {
        kind = .{ .sid = .{ .local_subrs = .{}, .private_dict = &.{} } };
        if (top.private) |range| sid: {
            if (range[1] > cff.len or range[0] > range[1]) break :sid;
            const pd = cff[range[0]..range[1]];
            const ls = localSubrs(cff, range, pd) orelse break :sid;
            kind = .{ .sid = .{ .local_subrs = ls, .private_dict = pd } };
        }
    }

    // ---- charstrings (desubroutinised), used font DICTs
    const gsubrs = Subrs.init(try gsubr_index.items(a));
    var lsubrs: std.ArrayList(Subrs) = .empty;
    switch (kind) {
        .cid => |c| for (c.dicts) |fd| try lsubrs.append(a, Subrs.init(try fd.local_subrs.items(a))),
        .sid => |s| try lsubrs.append(a, Subrs.init(try s.local_subrs.items(a))),
    }
    var used_fds: [256]bool = @splat(false);
    const programs = try a.alloc([]const u8, mapper.numGids());
    for (mapper.gids(), programs) |old, *prog| {
        var fd: u8 = 0;
        switch (kind) {
            .cid => |c| {
                fd = c.fd_select.index(old) orelse return error.MalformedFont;
                used_fds[fd] = true;
            },
            .sid => {},
        }
        if (fd >= lsubrs.items.len) return error.MalformedFont;
        var d: Decompiler = .{ .gsubrs = &gsubrs, .lsubrs = &lsubrs.items[fd], .a = a, .out = W.init(a) };
        const cs = char_strings.get(old) orelse return error.MalformedFont;
        _ = try d.run(cs, 1);
        prog.* = d.out.buf.items;
    }
    // FontDictRemapper over the used FDs in ascending order
    var fd_order: std.ArrayList(u8) = .empty;
    var fd_new: [256]u8 = undefined;
    for (used_fds, 0..) |u, i| if (u) {
        fd_new[i] = @intCast(fd_order.items.len);
        try fd_order.append(a, @intCast(i));
    };

    // ---- strings
    var sids: SidRemapper = .{};
    _ = try sids.remap(a, "Adobe");
    _ = try sids.remap(a, "Identity");
    const remapSid = struct {
        fn f(s: *SidRemapper, al: Allocator, st: *const Index, sid: u16) Error!void {
            if (sid < 391) return;
            const str = st.get(sid - 391) orelse return error.SubsetError;
            try s.remapOld(al, sid, str);
        }
    }.f;
    if (top.copyright) |s| try remapSid(&sids, a, &strings, s);
    if (top.font_name) |s| try remapSid(&sids, a, &strings, s);
    if (top.notice) |s| try remapSid(&sids, a, &strings, s);
    switch (kind) {
        .cid => |c| for (fd_order.items) |fi| {
            if (fi >= c.dicts.len) return error.SubsetError;
            if (c.dicts[fi].font_name) |s| try remapSid(&sids, a, &strings, s);
        },
        .sid => {},
    }

    const n_fd: usize = switch (kind) {
        .cid => fd_order.items.len,
        .sid => 1,
    };
    var priv_len = try a.alloc(Deferred, n_fd);
    var priv_off = try a.alloc(Deferred, n_fd);
    @memset(priv_len, .{});
    @memset(priv_off, .{});
    var charset_off: Deferred = .{};
    var cs_offset: Deferred = .{};
    var fd_array_off: Deferred = .{};
    var fd_select_off: Deferred = .{};

    // ---- write
    var w = W.init(a);
    try w.bytes(&.{ 1, 0, 4, 4 });
    try w.bytes(names);

    // Top DICT
    {
        var t = W.init(a);
        try writeInt(&t, sids.get("Adobe").?);
        try writeInt(&t, sids.get("Identity").?);
        try writeInt(&t, 0);
        try writeOp(&t, op.ros);
        if (top.copyright) |s| if (sids.getNew(s)) |n| {
            try writeInt(&t, n);
            try writeOp(&t, op.copyright);
        };
        if (top.notice) |s| if (sids.getNew(s)) |n| {
            try writeInt(&t, n);
            try writeOp(&t, op.notice);
        };
        if (top.font_name) |s| if (sids.getNew(s)) |n| {
            try writeInt(&t, n);
            try writeOp(&t, op.font_name);
        };
        const def_matrix = [6]Number{ .{ .real = 0.001 }, .{ .int = 0 }, .{ .int = 0 }, .{ .real = 0.001 }, .{ .int = 0 }, .{ .int = 0 } };
        for (top.font_matrix orelse def_matrix) |n| try writeNumber(&t, n);
        try writeOp(&t, op.font_matrix);
        const def_bbox = [4]Number{ .{ .int = 0 }, .{ .int = 0 }, .{ .int = 0 }, .{ .int = 0 } };
        for (top.font_bbox orelse def_bbox) |n| try writeNumber(&t, n);
        try writeOp(&t, op.font_bbox);
        const base = w.len();
        charset_off = .{ .location = base + t.len(), .set = true };
        try writeInt5(&t, 0);
        try writeOp(&t, op.charset);
        cs_offset = .{ .location = base + t.len(), .set = true };
        try writeInt5(&t, 0);
        try writeOp(&t, op.char_strings);
        try writeInt(&t, 0xffff);
        try writeOp(&t, op.cid_count);
        fd_array_off = .{ .location = base + t.len(), .set = true };
        try writeInt5(&t, 0);
        try writeOp(&t, op.fd_array);
        fd_select_off = .{ .location = base + t.len(), .set = true };
        try writeInt5(&t, 0);
        try writeOp(&t, op.fd_select);
        var header: usize = 0;
        try createIndex(&w, &.{t.buf.items}, &header);
        charset_off.location += header;
        cs_offset.location += header;
        fd_array_off.location += header;
        fd_select_off.location += header;
    }
    // String INDEX, empty Global Subr INDEX
    try createIndex(&w, sids.strings.items, null);
    try createIndex(&w, &.{}, null);

    // charset: identity (format 0 with only .notdef, else one format-2 range)
    charset_off.value = try offsetValue(w.len());
    if (mapper.numGids() == 1) {
        try w.u8_(0);
    } else {
        try w.u8_(2);
        try w.u16_(1);
        try w.u16_(mapper.numGids() - 2);
    }

    // Private DICTs
    switch (kind) {
        .sid => |s| try rewritePrivate(&w, s.private_dict, &priv_len[0], &priv_off[0]),
        .cid => |c| for (fd_order.items, 0..) |fi, ni| try rewritePrivate(&w, c.dicts[fi].private_dict, &priv_len[ni], &priv_off[ni]),
    }

    // FDSelect
    fd_select_off.value = try offsetValue(w.len());
    switch (kind) {
        .sid => {
            try w.u8_(3);
            try w.u16_(1);
            try w.u16_(0);
            try w.u8_(0);
            try w.u16_(mapper.numGids());
        },
        .cid => |c| {
            try w.u8_(0);
            for (mapper.gids()) |g| {
                const old = c.fd_select.index(g) orelse return error.MalformedFont;
                if (!used_fds[old]) return error.SubsetError;
                try w.u8_(fd_new[old]);
            }
        },
    }

    // FDArray
    fd_array_off.value = try offsetValue(w.len());
    {
        var dicts: std.ArrayList([]const u8) = .empty;
        const ident = [6]Number{ .{ .int = 1 }, .{ .int = 0 }, .{ .int = 0 }, .{ .int = 1 }, .{ .int = 0 }, .{ .int = 0 } };
        for (0..n_fd) |ni| {
            var t = W.init(a);
            var matrix = ident;
            var font_name: ?u16 = null;
            switch (kind) {
                .sid => {},
                .cid => |c| {
                    const fd = c.dicts[fd_order.items[ni]];
                    if (fd.font_matrix) |m| matrix = if (top.font_matrix == null) combine(m, .{ .{ .real = 1000 }, .{ .int = 0 }, .{ .int = 0 }, .{ .real = 1000 }, .{ .int = 0 }, .{ .int = 0 } }) else m;
                    if (fd.font_name) |s| font_name = sids.getNew(s);
                },
            }
            for (matrix) |n| try writeNumber(&t, n);
            try writeOp(&t, op.font_matrix);
            try writeInt5(&t, priv_len[ni].value);
            try writeInt5(&t, priv_off[ni].value);
            try writeOp(&t, op.private);
            if (font_name) |n| {
                try writeInt(&t, n);
                try writeOp(&t, op.font_name);
            }
            try dicts.append(a, t.buf.items);
        }
        try createIndex(&w, dicts.items, null);
    }

    // CharStrings
    cs_offset.value = try offsetValue(w.len());
    try createIndex(&w, programs, null);

    const out = w.buf.items;
    for ([_]Deferred{ charset_off, cs_offset, fd_select_off, fd_array_off }) |d| {
        if (!d.set) continue;
        if (d.location + 5 > out.len) return error.SubsetError;
        out[d.location] = 29;
        std.mem.writeInt(u32, out[d.location + 1 ..][0..4], @bitCast(d.value), .big);
    }
    return out;
}

fn offsetValue(v: usize) Error!i32 {
    if (v > std.math.maxInt(i32)) return error.OverflowError;
    return @intCast(v);
}

fn rewritePrivate(w: *W, data: []const u8, len_out: *Deferred, off_out: *Deferred) Error!void {
    const start = w.len();
    var p: DictParser = .{ .data = data };
    while (p.next()) |o| {
        if (o == op.subrs) continue;
        p.parseOperands() orelse return error.MalformedFont;
        for (p.ops()) |n| try writeNumber(w, n);
        try writeOp(w, o);
    }
    len_out.value = try offsetValue(w.len() - start);
    off_out.value = try offsetValue(start);
}

fn combine(t1: [6]Number, t2: [6]Number) [6]Number {
    var a: [6]f64 = undefined;
    var b: [6]f64 = undefined;
    for (0..6) |i| {
        a[i] = t1[i].asF64();
        b[i] = t2[i].asF64();
    }
    return .{
        .{ .real = @floatCast(a[0] * b[0] + a[2] * b[1]) },
        .{ .real = @floatCast(a[1] * b[0] + a[3] * b[1]) },
        .{ .real = @floatCast(a[0] * b[2] + a[2] * b[3]) },
        .{ .real = @floatCast(a[1] * b[2] + a[3] * b[3]) },
        .{ .real = @floatCast(a[0] * b[4] + a[2] * b[5] + a[4]) },
        .{ .real = @floatCast(a[1] * b[4] + a[3] * b[5] + a[5]) },
    };
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

fn encInt(v: i32) ![]const u8 {
    const S = struct {
        var buf: [16]u8 = undefined;
    };
    var w = W.init(testing.allocator);
    defer w.buf.deinit(testing.allocator);
    try writeInt(&w, v);
    @memcpy(S.buf[0..w.len()], w.buf.items);
    return S.buf[0..w.len()];
}

test "integer encodings round-trip with the Rust sizes" {
    const cases = [_]struct { v: i32, n: usize }{
        .{ .v = 0, .n = 1 },     .{ .v = -107, .n = 1 },                 .{ .v = 107, .n = 1 },  .{ .v = 108, .n = 2 },
        .{ .v = -1131, .n = 2 }, .{ .v = 1131, .n = 2 },                 .{ .v = 1132, .n = 3 }, .{ .v = -32768, .n = 3 },
        .{ .v = 32768, .n = 5 }, .{ .v = std.math.minInt(i32), .n = 5 },
    };
    for (cases) |c| {
        const b = try encInt(c.v);
        try testing.expectEqual(c.n, b.len);
        var r: Reader = .{ .d = b };
        try testing.expectEqual(c.v, parseInteger(&r).?);
    }
}

test "real numbers: parse and Rust-Display formatting" {
    var r: Reader = .{ .d = &.{ 0x1E, 0xE2, 0x49, 0x32, 0xA1, 0x2C, 0x2F } };
    try testing.expectEqual(@as(f32, -249.3212), parseReal(&r).?);
    for ([_]f32{ 0.58, -0.21, 3.98, 16.49, 159.18, 5906.2, 0.001, 1, 1000, 0.039625 }) |v| {
        var w = W.init(testing.allocator);
        defer w.buf.deinit(testing.allocator);
        try writeReal(&w, v);
        var rr: Reader = .{ .d = w.buf.items };
        try testing.expectEqual(v, parseReal(&rr).?);
    }
    // 0.001 -> "0.001" -> 0 . 0 0 1 f
    var w = W.init(testing.allocator);
    defer w.buf.deinit(testing.allocator);
    try writeReal(&w, 0.001);
    try testing.expectEqualSlices(u8, &.{ 30, 0x0a, 0x00, 0x1f }, w.buf.items);
    w.buf.clearRetainingCapacity();
    try writeReal(&w, 1.0);
    try testing.expectEqualSlices(u8, &.{ 30, 0x1f }, w.buf.items);
}

test "fixed number round-trip" {
    var w = W.init(testing.allocator);
    defer w.buf.deinit(testing.allocator);
    var r: Reader = .{ .d = &.{ 255, 154, 104, 120, 40 } };
    try writeNumber(&w, parseNumber(&r, true).?);
    try testing.expectEqualSlices(u8, &.{ 255, 154, 104, 120, 40 }, w.buf.items);
}
