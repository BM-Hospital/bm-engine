//! OpenType font variations.
//!
//!  * `fvar` axes / named instances, `avar` segment maps -> normalised F2Dot14 coordinates
//!    (16.16 fixed-point arithmetic identical to skrifa / FreeType);
//!  * ItemVariationStore deltas (`HVAR`, `MVAR`, CFF2 `blend`, GDEF/GPOS VariationIndex);
//!  * `gvar` tuple variations: shared / private point numbers, packed deltas, intermediate
//!    regions, IUP interpolation of untouched points, component offsets and phantom points;
//!  * varied `glyf` outlines (`glyfOutline`).
//!
//! Everything here is reached only through the clearly marked call sites in ttf.zig
//! (`enable_variations`), cff.zig (CFF2 blend scalars) and collection.zig (instances), so the
//! whole file drops out of the binary when those are compiled out.
//!
//! Not implemented: avar version 2, `VVAR`, `cvar`, HVAR lsb/rsb mappings (unneeded: nothing
//! is hinted and vertical layout is not supported).
const std = @import("std");
const ttf = @import("ttf.zig");
const Font = ttf.Font;
const PathOut = ttf.PathOut;
const Xf = ttf.Xf;
const rd8 = ttf.rd8;
const rd16 = ttf.rd16;
const rdi16 = ttf.rdi16;
const rd32 = ttf.rd32;
const tail = ttf.tail;

/// Fonts with more axes keep their remaining axes at the default.
pub const max_axes = 16;

/// A user-space axis setting (`font-variation-settings: "wght" 650`).
pub const AxisValue = struct { tag: [4]u8, value: f32 };

/// One `fvar` axis in user-space units.
pub const Axis = struct {
    tag: [4]u8,
    min: f32,
    default: f32,
    max: f32,
    hidden: bool = false,
    name_id: u16 = 0,
};

/// One `fvar` named instance; `coords` are user-space values in axis order.
pub const NamedInstance = struct {
    subfamily_name_id: u16,
    /// 0xffff when absent.
    postscript_name_id: u16 = 0xffff,
    coords: []const f32,
};

// ------------------------------------------------------------ 16.16 fixed

pub inline fn fxMul(a: i32, b: i32) i32 {
    const ab = @as(i64, a) * b;
    return @truncate((ab + 0x8000 - @intFromBool(ab < 0)) >> 16);
}

/// `a * b / c` rounded (FT_MulDiv); 0x7fffffff when `c` is 0.
pub fn fxMulDiv(a: i32, b: i32, c: i32) i32 {
    const neg = ((a ^ b ^ c) < 0);
    const ua: u64 = @abs(@as(i64, a));
    const ub: u64 = @abs(@as(i64, b));
    const uc: u64 = @abs(@as(i64, c));
    const d: u64 = if (uc > 0) (ua * ub + (uc >> 1)) / uc else 0x7fff_ffff;
    const r: i32 = @bitCast(@as(u32, @truncate(d)));
    return if (neg) -%r else r;
}

pub inline fn fxDiv(a: i32, b: i32) i32 {
    return fxMulDiv(a, 0x10000, b);
}

fn fromF32(v: f32) i32 {
    if (!(v > -32000.0)) return if (v != v) 0 else -32000 * 65536;
    if (v > 32000.0) return 32000 * 65536;
    return @intFromFloat(@floor(v * 65536.0 + 0.5));
}

inline fn toF32(fx: i32) f32 {
    return @as(f32, @floatFromInt(fx)) * (1.0 / 65536.0);
}

// ------------------------------------------------------------------- fvar

pub fn axisCount(fvar: []const u8) u32 {
    if (fvar.len < 16 or rd16(fvar, 10) < 20) return 0;
    return rd16(fvar, 8);
}

fn axisRec(fvar: []const u8, i: u32) u32 {
    return @as(u32, rd16(fvar, 4)) + i * @as(u32, rd16(fvar, 10));
}

pub fn axisAt(fvar: []const u8, i: u32) ?Axis {
    if (i >= axisCount(fvar)) return null;
    const r = axisRec(fvar, i);
    if (r + 20 > fvar.len) return null;
    return .{
        .tag = fvar[r..][0..4].*,
        .min = toF32(@bitCast(rd32(fvar, r + 4))),
        .default = toF32(@bitCast(rd32(fvar, r + 8))),
        .max = toF32(@bitCast(rd32(fvar, r + 12))),
        .hidden = rd16(fvar, r + 16) & 1 != 0,
        .name_id = rd16(fvar, r + 18),
    };
}

inline fn tagU32(tag: *const [4]u8) u32 {
    return @as(*align(1) const u32, @ptrCast(tag)).*;
}

pub noinline fn findAxis(fvar: []const u8, tag: *const [4]u8) ?Axis {
    var i: u32 = 0;
    const n = axisCount(fvar);
    while (i < n) : (i += 1) {
        const r = axisRec(fvar, i);
        if (r + 20 > fvar.len) return null;
        if (tagU32(fvar[r..][0..4]) == tagU32(tag)) return axisAt(fvar, i);
    }
    return null;
}

pub fn instanceCount(fvar: []const u8) u32 {
    if (axisCount(fvar) == 0) return 0;
    return rd16(fvar, 12);
}

/// Named instance `i`; its coordinates are written to `buf` (truncated to `buf.len` axes).
pub fn instanceAt(fvar: []const u8, i: u32, buf: []f32) ?NamedInstance {
    const na = axisCount(fvar);
    if (i >= instanceCount(fvar)) return null;
    const size: u32 = rd16(fvar, 14);
    if (size < 4 + na * 4) return null;
    const r = axisRec(fvar, na) + i * size;
    if (r + size > fvar.len) return null;
    const n = @min(na, buf.len);
    for (buf[0..n], 0..) |*c, k| c.* = toF32(@bitCast(rd32(fvar, r + 4 + @as(u32, @intCast(k)) * 4)));
    return .{
        .subfamily_name_id = rd16(fvar, r),
        .postscript_name_id = if (size >= 6 + na * 4) rd16(fvar, r + 4 + na * 4) else 0xffff,
        .coords = buf[0..n],
    };
}

/// User-space settings -> normalised F2Dot14 coordinates (one per axis, at most `max_axes`).
/// The last setting of a tag wins, unknown tags are ignored, values are clamped to the axis
/// range, `avar` (version 1) segment maps are applied. Returns the number of coordinates.
pub noinline fn normalize(fvar: []const u8, avar: []const u8, settings: []const AxisValue, out: *[max_axes]i16) u8 {
    const total = axisCount(fvar);
    const n: u32 = @min(total, max_axes);
    const has_avar = avar.len >= 8 and rd16(avar, 0) == 1 and rd16(avar, 6) == total;
    var seg: u32 = 8;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const r = axisRec(fvar, i);
        out[i] = 0;
        if (r + 20 > fvar.len) continue;
        const lo: i32 = @bitCast(rd32(fvar, r + 4));
        const def: i32 = @bitCast(rd32(fvar, r + 8));
        const hi: i32 = @bitCast(rd32(fvar, r + 12));
        var v = def;
        for (settings) |s| {
            if (tagU32(&s.tag) == tagU32(fvar[r..][0..4])) v = fromF32(s.value);
        }
        v = @max(lo, @min(v, @max(lo, hi)));
        var c: i32 = 0;
        if (v < def) {
            c = -fxDiv(def -| v, def -| lo);
        } else if (v > def) {
            c = fxDiv(v -| def, hi -| def);
        }
        c = std.math.clamp(c, -0x10000, 0x10000);
        if (has_avar) {
            const cnt: u32 = rd16(avar, seg);
            c = avarMap(avar, seg + 2, cnt, c);
            seg +|= 2 + cnt * 4;
        }
        out[i] = @intCast(std.math.clamp((c +% 2) >> 2, -0x4000, 0x4000));
    }
    return @intCast(n);
}

fn avarMap(avar: []const u8, off: u32, count: u32, coord: i32) i32 {
    var prev_from: i32 = 0;
    var prev_to: i32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const p = off + i * 4;
        if (p + 4 > avar.len) break;
        const from = @as(i32, rdi16(avar, p)) * 4;
        const to = @as(i32, rdi16(avar, p + 2)) * 4;
        if (from == coord) return to;
        if (from > coord) {
            if (i == 0) return coord;
            return prev_to + fxMulDiv(to - prev_to, coord - prev_from, from - prev_from);
        }
        prev_from = from;
        prev_to = to;
    }
    return coord;
}

// ------------------------------------------------------ ItemVariationStore

/// Scalar (16.16) of variation region `region` of the store at `coords`.
pub noinline fn regionScalar(store: []const u8, region: u32, coords: []const i16) i32 {
    const list = tail(store, rd32(store, 2));
    const axes: u32 = rd16(list, 0);
    if (region >= rd16(list, 2)) return 0;
    var p: u32 = 4 +| region *| (axes * 6);
    if (p > list.len or axes * 6 > list.len - p) return 0;
    var scalar: i32 = 0x10000;
    var i: u32 = 0;
    while (i < axes) : ({
        i += 1;
        p += 6;
    }) {
        const start: i32 = rdi16(list, p);
        const peak: i32 = rdi16(list, p + 2);
        const end: i32 = rdi16(list, p + 4);
        const coord: i32 = if (i < coords.len) coords[i] else 0;
        if (start > peak or peak > end or peak == 0 or (start < 0 and end > 0)) continue;
        if (coord < start or coord > end) return 0;
        if (coord == peak) continue;
        scalar = if (coord < peak)
            fxMulDiv(scalar, coord - start, peak - start)
        else
            fxMulDiv(scalar, end - coord, end - peak);
    }
    return scalar;
}

/// ItemVariationData subtable `outer` of a store (empty when out of range).
pub fn itemData(store: []const u8, outer: u32) []const u8 {
    if (store.len < 8 or rd16(store, 0) != 1 or outer >= rd16(store, 6)) return &.{};
    return tail(store, rd32(store, 8 + outer * 4));
}

/// Delta of item (`outer`, `inner`) at `coords` as a 48.16 fixed-point value (font units).
pub fn itemDeltaFx(store: []const u8, outer: u32, inner: u32, coords: []const i16) i64 {
    const d = itemData(store, outer);
    if (d.len < 6 or inner >= rd16(d, 0)) return 0;
    const wc_raw = rd16(d, 2);
    const long = wc_raw & 0x8000 != 0;
    const words: u32 = wc_raw & 0x7fff;
    const nreg: u32 = rd16(d, 4);
    if (words > nreg) return 0;
    const wsz: u32 = if (long) 4 else 2;
    const ssz: u32 = if (long) 2 else 1;
    const row = words * wsz + (nreg - words) * ssz;
    var p: u32 = 6 +| nreg * 2 +| inner *| row;
    if (p > d.len or row > d.len - p) return 0;
    var acc: i64 = 0;
    var i: u32 = 0;
    while (i < nreg) : (i += 1) {
        var delta: i32 = undefined;
        if (i < words) {
            delta = if (long) @bitCast(rd32(d, p)) else rdi16(d, p);
            p += wsz;
        } else {
            delta = if (long) rdi16(d, p) else @as(i8, @bitCast(rd8(d, p)));
            p += ssz;
        }
        if (delta == 0) continue;
        acc +%= @as(i64, delta) *% regionScalar(store, rd16(d, 6 + i * 2), coords);
    }
    return acc;
}

/// Delta rounded to whole font units (how skrifa / FreeType apply HVAR and MVAR deltas).
pub fn itemDeltaInt(store: []const u8, outer: u32, inner: u32, coords: []const i16) i32 {
    const v = (itemDeltaFx(store, outer, inner, coords) +% 0x8000) >> 16;
    return @intCast(std.math.clamp(v, -0x7fff_ffff, 0x7fff_ffff));
}

/// Unrounded delta in font units.
pub fn itemDelta(store: []const u8, outer: u32, inner: u32, coords: []const i16) f32 {
    return @as(f32, @floatFromInt(itemDeltaFx(store, outer, inner, coords))) * (1.0 / 65536.0);
}

/// DeltaSetIndexMap lookup -> (outer << 16) | inner.
fn deltaSetIndex(map: []const u8, index: u32) u32 {
    if (map.len < 4) return index;
    const format = rd8(map, 0);
    const entry_format = rd8(map, 1);
    const count: u32 = if (format == 0) rd16(map, 2) else rd32(map, 2);
    const base: u32 = if (format == 0) 4 else 6;
    if (count == 0) return index;
    const i = @min(index, count - 1);
    const size: u32 = ((entry_format >> 4) & 3) + 1;
    const p = base +| i *| size;
    if (p > map.len or size > map.len - p) return 0xffff_ffff;
    var v: u32 = 0;
    for (map[p..][0..size]) |b| v = (v << 8) | b;
    const inner_bits: u5 = @intCast((entry_format & 0xf) + 1);
    const inner = v & ((@as(u32, 1) << inner_bits) - 1);
    const outer = v >> inner_bits;
    return (outer << 16) | (inner & 0xffff);
}

/// HVAR advance-width delta of `gid`, whole font units.
pub fn hvarAdvanceDelta(hvar: []const u8, gid: u16, coords: []const i16) i32 {
    if (hvar.len < 20) return 0;
    const store = tail(hvar, rd32(hvar, 4));
    const map_off = rd32(hvar, 8);
    var idx: u32 = gid;
    if (map_off != 0) {
        idx = deltaSetIndex(tail(hvar, map_off), gid);
        if (idx == 0xffff_ffff) return 0;
    }
    return itemDeltaInt(store, idx >> 16, idx & 0xffff, coords);
}

/// MVAR delta of metric `tag` (e.g. "hasc"), whole font units; 0 when the tag is absent.
pub fn mvarDelta(mvar: []const u8, tag: *const [4]u8, coords: []const i16) i32 {
    if (mvar.len < 12) return 0;
    const rec_size: u32 = rd16(mvar, 6);
    const count: u32 = rd16(mvar, 8);
    const store_off: u32 = rd16(mvar, 10);
    if (rec_size < 8 or store_off == 0) return 0;
    const want = (@as(u32, tag[0]) << 24) | (@as(u32, tag[1]) << 16) | (@as(u32, tag[2]) << 8) | tag[3];
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const r = 12 + i * rec_size;
        if (r + 8 > mvar.len) break;
        if (rd32(mvar, r) == want)
            return itemDeltaInt(tail(mvar, store_off), rd16(mvar, r + 4), rd16(mvar, r + 6), coords);
    }
    return 0;
}

// ------------------------------------------------------------------- gvar

fn glyphVarData(gvar: []const u8, gid: u16) []const u8 {
    if (gvar.len < 20 or gid >= rd16(gvar, 12)) return &.{};
    const arr = rd32(gvar, 16);
    var a: u32 = undefined;
    var b: u32 = undefined;
    if (rd16(gvar, 14) & 1 != 0) {
        a = rd32(gvar, 20 + @as(u32, gid) * 4);
        b = rd32(gvar, 24 + @as(u32, gid) * 4);
    } else {
        a = @as(u32, rd16(gvar, 20 + @as(u32, gid) * 2)) * 2;
        b = @as(u32, rd16(gvar, 22 + @as(u32, gid) * 2)) * 2;
    }
    if (b <= a or arr > gvar.len or b > gvar.len - arr) return &.{};
    return gvar[arr..][a..b];
}

/// Packed point numbers. `all` = the tuple applies to every point.
const Points = struct {
    d: []const u8,
    pos: u32,
    left: u32,
    all: bool,
    run: u32 = 0,
    words: bool = false,
    cur: u32 = 0,

    fn init(d: []const u8, off: u32) Points {
        var pos = off;
        var count: u32 = rd8(d, pos);
        pos += 1;
        if (count & 0x80 != 0) {
            count = ((count & 0x7f) << 8) | rd8(d, pos);
            pos += 1;
        }
        return .{ .d = d, .pos = pos, .left = count, .all = count == 0 };
    }

    fn next(p: *Points) ?u32 {
        if (p.left == 0 or p.pos >= p.d.len) return null;
        if (p.run == 0) {
            const c = p.d[p.pos];
            p.pos += 1;
            p.words = c & 0x80 != 0;
            p.run = @as(u32, c & 0x7f) + 1;
        }
        if (p.words) {
            p.cur +%= rd16(p.d, p.pos);
            p.pos += 2;
        } else {
            p.cur +%= rd8(p.d, p.pos);
            p.pos += 1;
        }
        p.run -= 1;
        p.left -= 1;
        return p.cur;
    }

    /// Offset just past the point number data.
    fn end(p: Points) u32 {
        var q = p;
        while (q.next() != null) {}
        return @min(q.pos, @as(u32, @intCast(q.d.len)));
    }
};

/// Packed deltas; yields 0 forever once the data runs out.
const Deltas = struct {
    d: []const u8,
    pos: u32,
    run: u32 = 0,
    kind: u8 = 0,

    /// True once only zeros can follow (keeps loops over huge declared counts bounded by
    /// the actual data size).
    inline fn exhausted(p: *const Deltas) bool {
        return p.run == 0 and p.pos >= p.d.len;
    }

    fn next(p: *Deltas) i32 {
        if (p.run == 0) {
            if (p.pos >= p.d.len) return 0;
            const c = p.d[p.pos];
            p.pos += 1;
            p.kind = c >> 6;
            p.run = @as(u32, c & 0x3f) + 1;
        }
        p.run -= 1;
        switch (p.kind) {
            0 => {
                const v: i8 = @bitCast(rd8(p.d, p.pos));
                p.pos +|= 1;
                return v;
            },
            1 => {
                const v = rdi16(p.d, p.pos);
                p.pos +|= 2;
                return v;
            },
            2 => return 0,
            else => {
                const v: i32 = @bitCast(rd32(p.d, p.pos));
                p.pos +|= 4;
                return v;
            },
        }
    }
};

const Tuple = struct {
    /// 16.16, never 0.
    scalar: i32,
    /// Serialized data of this tuple (private point numbers + deltas).
    data: []const u8,
    private_points: bool,
};

const TupleIter = struct {
    gvar: []const u8,
    gv: []const u8,
    coords: []const i16,
    axes: u32,
    left: u32,
    hdr: u32 = 4,
    cursor: u32,
    /// Shared point numbers (valid when `has_shared`).
    shared: Points,
    has_shared: bool,

    fn init(gvar: []const u8, gid: u16, coords: []const i16) TupleIter {
        const gv = glyphVarData(gvar, gid);
        const tc = rd16(gv, 0);
        const data_off: u32 = rd16(gv, 2);
        var it: TupleIter = .{
            .gvar = gvar,
            .gv = gv,
            .coords = coords,
            .axes = rd16(gvar, 4),
            .left = if (gv.len < 4) 0 else tc & 0x0fff,
            .cursor = data_off,
            .shared = .{ .d = gv, .pos = 0, .left = 0, .all = true },
            .has_shared = tc & 0x8000 != 0,
        };
        if (it.has_shared) {
            it.shared = Points.init(gv, data_off);
            it.cursor = it.shared.end();
        }
        return it;
    }

    fn next(it: *TupleIter) ?Tuple {
        while (it.left != 0) {
            it.left -= 1;
            const gv = it.gv;
            if (it.hdr + 4 > gv.len) return null;
            const size: u32 = rd16(gv, it.hdr);
            const tidx = rd16(gv, it.hdr + 2);
            it.hdr += 4;
            var peak: []const u8 = &.{};
            const tb = it.axes * 2;
            if (tidx & 0x8000 != 0) {
                peak = tail(gv, it.hdr);
                it.hdr += tb;
            } else {
                const si: u32 = tidx & 0x0fff;
                if (si < rd16(it.gvar, 6)) peak = tail(it.gvar, rd32(it.gvar, 8) +| si * tb);
            }
            var inter: []const u8 = &.{};
            if (tidx & 0x4000 != 0) {
                inter = tail(gv, it.hdr);
                it.hdr += tb * 2;
            }
            const start = @min(it.cursor, @as(u32, @intCast(gv.len)));
            const stop = @min(start + size, @as(u32, @intCast(gv.len)));
            it.cursor = stop;
            const scalar = tupleScalar(peak, inter, it.axes, it.coords);
            if (scalar == 0) continue;
            return .{ .scalar = scalar, .data = gv[start..stop], .private_points = tidx & 0x2000 != 0 };
        }
        return null;
    }

    /// Point numbers and delta stream of a tuple.
    fn open(it: *const TupleIter, t: Tuple) struct { pts: Points, deltas: Deltas } {
        if (t.private_points) {
            const p = Points.init(t.data, 0);
            return .{ .pts = p, .deltas = .{ .d = t.data, .pos = p.end() } };
        }
        return .{ .pts = it.shared, .deltas = .{ .d = t.data, .pos = 0 } };
    }
};

fn tupleScalar(peak_t: []const u8, inter: []const u8, axes: u32, coords: []const i16) i32 {
    if (peak_t.len < axes * 2 or (inter.len != 0 and inter.len < axes * 4)) return 0;
    var scalar: i32 = 0x10000;
    var i: u32 = 0;
    while (i < axes) : (i += 1) {
        const peak: i32 = rdi16(peak_t, i * 2);
        if (peak == 0) continue;
        const coord: i32 = if (i < coords.len) coords[i] else 0;
        if (coord == 0) return 0;
        if (peak == coord) continue;
        if (inter.len != 0) {
            const start: i32 = rdi16(inter, i * 2);
            const end: i32 = rdi16(inter, (axes + i) * 2);
            if (start > peak or peak > end or (start < 0 and end > 0)) continue;
            if (coord <= start or coord >= end) return 0;
            scalar = if (coord < peak)
                fxMulDiv(scalar, coord - start, peak - start)
            else
                fxMulDiv(scalar, end - coord, end - peak);
        } else {
            if (coord < @min(peak, 0) or coord > @max(peak, 0)) return 0;
            scalar = fxMulDiv(scalar, coord, peak);
        }
    }
    return scalar;
}

/// Accumulates the deltas of points `first .. first + dx.len` out of `total` points, without
/// IUP (component offsets and phantom points are never interpolated).
fn sparseDeltas(f: *const Font, gid: u16, total: u32, first: u32, dx: []f32, dy: []f32) void {
    @memset(dx, 0);
    @memset(dy, 0);
    var it = TupleIter.init(f.gvar, gid, f.coordSlice());
    while (it.next()) |t| {
        const s = toF32(t.scalar);
        var o = it.open(t);
        var axis: u32 = 0;
        while (axis < 2) : (axis += 1) {
            const dst = if (axis == 0) dx else dy;
            var pts = o.pts;
            var seq: u32 = 0;
            while (!o.deltas.exhausted()) : (seq += 1) {
                var j = seq;
                if (pts.all) {
                    if (seq >= total) break;
                } else j = pts.next() orelse break;
                const d = o.deltas.next();
                if (j >= first and j - first < dst.len) dst[j - first] += @as(f32, @floatFromInt(d)) * s;
            }
            // skip what is left of this axis' deltas so the next axis starts aligned
            if (pts.all) {
                while (seq < total and !o.deltas.exhausted()) : (seq += 1) _ = o.deltas.next();
            } else while (pts.next() != null and !o.deltas.exhausted()) {
                _ = o.deltas.next();
            }
        }
    }
}

/// Number of outline points of a glyph record (components for a composite), i.e. the index
/// of its first phantom point.
fn pointCount(g: []const u8) u32 {
    if (g.len < 10) return 0;
    const nc = rdi16(g, 0);
    if (nc > 0) return @as(u32, rd16(g, 10 + (@as(u32, @intCast(nc)) - 1) * 2)) + 1;
    if (nc == 0) return 0;
    var it: Components = .{ .g = g };
    var n: u32 = 0;
    while (it.next() != null) n += 1;
    return n;
}

/// Advance-width delta of `gid` in whole font units: HVAR when present, else the gvar
/// phantom points.
pub noinline fn advanceDelta(f: *const Font, gid: u16) i32 {
    if (f.hvar.len != 0) return hvarAdvanceDelta(f.hvar, gid, f.coordSlice());
    if (f.gvar.len == 0 or f.glyf.len == 0) return 0;
    var dx: [2]f32 = undefined;
    var dy: [2]f32 = undefined;
    const n = pointCount(f.glyphData(gid));
    sparseDeltas(f, gid, n + 4, n, &dx, &dy);
    return roundInt(dx[1] - dx[0]);
}

inline fn roundInt(v: f32) i32 {
    if (!(@abs(v) < 1.0e9)) return 0;
    return @intFromFloat(@floor(v + 0.5));
}

// ---------------------------------------------------------- glyf outlines

/// Glyphs with more points are drawn unvaried (default instance).
pub const max_points = 2048;
/// Components beyond this many keep their default offsets.
const max_components = 60;

const Scratch = struct {
    /// Original coordinates (font units) incl. the 4 phantom points.
    ox: [max_points + 4]i16,
    oy: [max_points + 4]i16,
    /// Accumulated deltas, then the final coordinates.
    ax: [max_points + 4]f32,
    ay: [max_points + 4]f32,
    /// Deltas of the tuple being applied.
    tx: [max_points + 4]f32,
    ty: [max_points + 4]f32,
    /// bit 0: on-curve, bit 1: touched by the current tuple.
    fl: [max_points + 4]u8,
};

/// Flag/coordinate decoding of a simple glyph into `s` (the same data walk as
/// `ttf.simpleOutline`). Returns the point count or null when malformed / too large.
fn decodeSimple(g: []const u8, nc: u32, s: *Scratch) ?u32 {
    const end_pts: u32 = 10;
    const npts: u32 = @as(u32, rd16(g, end_pts + (nc - 1) * 2)) + 1;
    if (npts > max_points) return null;
    const ins_len: u32 = rd16(g, end_pts + nc * 2);
    var fo = end_pts + nc * 2 + 2 + ins_len;
    if (fo >= g.len) return null;
    var x_bytes: u32 = 0;
    var n: u32 = 0;
    while (n < npts) {
        if (fo >= g.len) return null;
        const fl = g[fo];
        fo += 1;
        var rep: u32 = 1;
        if (fl & 8 != 0) {
            rep += rd8(g, fo);
            fo += 1;
        }
        const xs: u32 = if (fl & 2 != 0) 1 else if (fl & 0x10 != 0) 0 else 2;
        x_bytes += xs * rep;
        while (rep != 0 and n < npts) : (rep -= 1) {
            s.fl[n] = fl;
            n += 1;
        }
    }
    var xo = fo;
    var yo = xo + x_bytes;
    var x: i32 = 0;
    var y: i32 = 0;
    for (0..npts) |i| {
        const fl = s.fl[i];
        if (fl & 2 != 0) {
            const d: i32 = rd8(g, xo);
            xo += 1;
            x +%= if (fl & 0x10 != 0) d else -d;
        } else if (fl & 0x10 == 0) {
            x +%= rdi16(g, xo);
            xo += 2;
        }
        if (fl & 4 != 0) {
            const d: i32 = rd8(g, yo);
            yo += 1;
            y +%= if (fl & 0x20 != 0) d else -d;
        } else if (fl & 0x20 == 0) {
            y +%= rdi16(g, yo);
            yo += 2;
        }
        s.ox[i] = @truncate(x);
        s.oy[i] = @truncate(y);
        s.fl[i] = fl & 1;
    }
    if (yo > g.len) return null;
    return npts;
}

/// Infers the deltas of the untouched points of contour `first..=last` from its touched
/// points (OpenType "interpolation of untouched points").
fn iupContour(o: []const i16, d: []f32, fl: []const u8, first: usize, last: usize) void {
    var t0 = first;
    while (t0 <= last and fl[t0] & 2 == 0) t0 += 1;
    if (t0 > last) return;
    var cur = t0;
    while (true) {
        // next touched point after `cur`, cyclically
        var nxt = cur;
        while (true) {
            nxt = if (nxt == last) first else nxt + 1;
            if (fl[nxt] & 2 != 0) break;
        }
        var a = cur;
        var b = nxt;
        if (o[a] > o[b]) std.mem.swap(usize, &a, &b);
        const oa: f32 = @floatFromInt(o[a]);
        const ob: f32 = @floatFromInt(o[b]);
        const da = d[a];
        const db = d[b];
        var p = cur;
        while (true) {
            p = if (p == last) first else p + 1;
            if (p == nxt) break;
            const op: f32 = @floatFromInt(o[p]);
            d[p] = if (oa == ob)
                (if (da == db) da else 0)
            else if (op <= oa)
                da
            else if (op >= ob)
                db
            else
                da + (db - da) * ((op - oa) / (ob - oa));
        }
        cur = nxt;
        if (cur == t0) break;
    }
}

/// Applies every active tuple of `gid` to the `n` (points + phantoms) entries of `s`:
/// afterwards `s.ax/ay` hold the summed deltas. `g` is the glyph record (contour ends).
fn simpleDeltas(f: *const Font, gid: u16, g: []const u8, nc: u32, n: u32, s: *Scratch) void {
    @memset(s.ax[0..n], 0);
    @memset(s.ay[0..n], 0);
    var it = TupleIter.init(f.gvar, gid, f.coordSlice());
    while (it.next()) |t| {
        const sc = toF32(t.scalar);
        var o = it.open(t);
        if (o.pts.all) {
            for (s.ax[0..n]) |*v| v.* += @as(f32, @floatFromInt(o.deltas.next())) * sc;
            for (s.ay[0..n]) |*v| v.* += @as(f32, @floatFromInt(o.deltas.next())) * sc;
            continue;
        }
        @memset(s.tx[0..n], 0);
        @memset(s.ty[0..n], 0);
        for (s.fl[0..n]) |*v| v.* &= 1;
        var touched: u32 = 0;
        var pts = o.pts;
        while (pts.next()) |j| {
            const d = o.deltas.next();
            if (j < n) {
                s.tx[j] = @floatFromInt(d);
                if (s.fl[j] & 2 == 0) touched += 1;
                s.fl[j] |= 2;
            }
        }
        pts = o.pts;
        while (pts.next()) |j| {
            const d = o.deltas.next();
            if (j < n) s.ty[j] = @floatFromInt(d);
        }
        if (touched < n) {
            var start: u32 = 0;
            var ci: u32 = 0;
            while (ci < nc) : (ci += 1) {
                const end: u32 = rd16(g, 10 + ci * 2);
                if (end < start or end >= n - 4) break;
                iupContour(&s.ox, &s.tx, &s.fl, start, end);
                iupContour(&s.oy, &s.ty, &s.fl, start, end);
                start = end + 1;
            }
        }
        for (s.ax[0..n], s.tx[0..n]) |*v, d| v.* += d * sc;
        for (s.ay[0..n], s.ty[0..n]) |*v, d| v.* += d * sc;
    }
}

/// x of the first phantom point after variation (the outline is shifted left by it, like
/// FreeType / skrifa do): `xMin - lsb + delta`, the delta rounded when HVAR exists.
fn originShift(f: *const Font, gid: u16, g: []const u8, left_delta: f32) f32 {
    const base: f32 = @floatFromInt(@as(i32, rdi16(g, 2)) - f.leftSideBearing(gid));
    return base + if (f.hvar.len != 0) @floor(left_delta + 0.5) else left_delta;
}

noinline fn simpleVar(f: *const Font, gid: u16, g: []const u8, nc: u32, xf_in: Xf, top: bool, out: *const PathOut) bool {
    var s: Scratch = undefined;
    // (too many points: only reachable for a component, see `glyfOutline`)
    const npts = decodeSimple(g, nc, &s) orelse return false;
    const n = npts + 4;
    @memset(s.ox[npts..n], 0);
    @memset(s.oy[npts..n], 0);
    @memset(s.fl[npts..n], 0);
    simpleDeltas(f, gid, g, nc, n, &s);
    var xf = xf_in;
    if (top) {
        const sh = originShift(f, gid, g, s.ax[npts]);
        if (sh != 0) {
            xf.e -= sh;
            xf.ident = false;
        }
    }
    const round = if (comptime ttf.enable_pdf) out.round_points else false;
    for (0..npts) |i| {
        var x = @as(f32, @floatFromInt(s.ox[i])) + s.ax[i];
        var y = @as(f32, @floatFromInt(s.oy[i])) + s.ay[i];
        if (round) {
            x = @floor(x + 0.5);
            y = @floor(y + 0.5);
        }
        s.ax[i] = if (xf.ident) x else xf.a * x + xf.c * y + xf.e;
        s.ay[i] = if (xf.ident) y else xf.b * x + xf.d * y + xf.f;
    }
    return emitContours(g, nc, npts, &s, out);
}

const Pt = struct { x: f32, y: f32 };
inline fn mid(a: Pt, b: Pt) Pt {
    return .{ .x = (a.x + b.x) * 0.5, .y = (a.y + b.y) * 0.5 };
}

/// The TrueType contour state machine over decoded points (`s.ax/ay/fl`).
fn emitContours(g: []const u8, nc: u32, npts: u32, s: *const Scratch, out: *const PathOut) bool {
    var any = false;
    var pi: u32 = 0;
    var ci: u32 = 0;
    while (ci < nc) : (ci += 1) {
        const end: u32 = rd16(g, 10 + ci * 2);
        if (end < pi or end >= npts) return any;
        var started = false;
        var start: Pt = undefined;
        var first_off: ?Pt = null;
        var pending: ?Pt = null;
        var k: u32 = 0;
        while (pi <= end) : ({
            pi += 1;
            k += 1;
        }) {
            const p: Pt = .{ .x = s.ax[pi], .y = s.ay[pi] };
            const on = s.fl[pi] & 1 != 0;
            if (!started) {
                if (on) {
                    start = p;
                } else if (k == 0) {
                    first_off = p;
                    continue;
                } else {
                    start = mid(first_off.?, p);
                    pending = p;
                }
                out.moveTo(start.x, start.y);
                started = true;
            } else if (on) {
                if (pending) |c| out.quadTo(c.x, c.y, p.x, p.y) else out.lineTo(p.x, p.y);
                pending = null;
            } else {
                if (pending) |c| {
                    const m = mid(c, p);
                    out.quadTo(c.x, c.y, m.x, m.y);
                }
                pending = p;
            }
        }
        if (!started) continue;
        if (first_off) |p| {
            if (pending) |c| {
                const m = mid(c, p);
                out.quadTo(c.x, c.y, m.x, m.y);
            }
            pending = p;
        }
        if (pending) |c| out.quadTo(c.x, c.y, start.x, start.y);
        out.close();
        any = true;
    }
    return any;
}

/// Iterator over the component records of a composite glyph.
const Components = struct {
    g: []const u8,
    off: u32 = 10,
    done: bool = false,

    const Item = struct { flags: u16, glyph: u16, dx: f32, dy: f32, m: Xf };

    fn next(it: *Components) ?Item {
        const g = it.g;
        if (it.done or it.off + 4 > g.len) return null;
        const flags = rd16(g, it.off);
        var c: Item = .{ .flags = flags, .glyph = rd16(g, it.off + 2), .dx = 0, .dy = 0, .m = .{} };
        var off = it.off + 4;
        if (flags & 1 != 0) {
            if (flags & 2 != 0) {
                c.dx = @floatFromInt(rdi16(g, off));
                c.dy = @floatFromInt(rdi16(g, off + 2));
            }
            off += 4;
        } else {
            if (flags & 2 != 0) {
                c.dx = @floatFromInt(@as(i8, @bitCast(rd8(g, off))));
                c.dy = @floatFromInt(@as(i8, @bitCast(rd8(g, off + 1))));
            }
            off += 2;
        }
        if (flags & 0x8 != 0) {
            c.m.a = f2dot14(g, off);
            c.m.d = c.m.a;
            off += 2;
        } else if (flags & 0x40 != 0) {
            c.m.a = f2dot14(g, off);
            c.m.d = f2dot14(g, off + 2);
            off += 4;
        } else if (flags & 0x80 != 0) {
            c.m.a = f2dot14(g, off);
            c.m.b = f2dot14(g, off + 2);
            c.m.c = f2dot14(g, off + 4);
            c.m.d = f2dot14(g, off + 6);
            off += 8;
        }
        it.off = off;
        if (flags & 0x20 == 0) it.done = true;
        return c;
    }
};

fn f2dot14(t: []const u8, off: u32) f32 {
    return @as(f32, @floatFromInt(rdi16(t, off))) * (1.0 / 16384.0);
}

fn rec(f: *const Font, gid: u16, xf_in: Xf, depth: u32, budget: *u32, out: *const PathOut) bool {
    const g = f.glyphData(gid);
    if (g.len < 10) return false;
    const nc = rdi16(g, 0);
    if (nc == 0) return false;
    if (nc > 0) return simpleVar(f, gid, g, @intCast(nc), xf_in, depth == 0, out);
    if (depth >= 8) return false;

    var dx: [max_components + 4]f32 = undefined;
    var dy: [max_components + 4]f32 = undefined;
    const ncomp = @min(pointCount(g), max_components);
    sparseDeltas(f, gid, ncomp + 4, 0, dx[0 .. ncomp + 4], dy[0 .. ncomp + 4]);
    var xf = xf_in;
    if (depth == 0) {
        const sh = originShift(f, gid, g, dx[ncomp]);
        if (sh != 0) {
            xf.e -= sh;
            xf.ident = false;
        }
    }
    var any = false;
    var it: Components = .{ .g = g };
    var i: u32 = 0;
    while (it.next()) |c| : (i += 1) {
        if (budget.* == 0) break;
        budget.* -= 1;
        var cx = c.dx;
        var cy = c.dy;
        if (c.flags & 2 != 0 and i < ncomp) {
            // FreeType (and skrifa in its FreeType mode) round component offset deltas
            cx += @floor(dx[i] + 0.5);
            cy += @floor(dy[i] + 0.5);
        }
        const m: Xf = .{
            .a = xf.a * c.m.a + xf.c * c.m.b,
            .b = xf.b * c.m.a + xf.d * c.m.b,
            .c = xf.a * c.m.c + xf.c * c.m.d,
            .d = xf.b * c.m.c + xf.d * c.m.d,
            .e = xf.a * cx + xf.c * cy + xf.e,
            .f = xf.b * cx + xf.d * cy + xf.f,
            .ident = false,
        };
        if (rec(f, c.glyph, m, depth + 1, budget, out)) any = true;
    }
    return any;
}

/// Outline of `gid` of a `glyf` font at the font's variation coordinates, font units, y-up.
/// Point deltas keep full float precision (no rounding), matching skrifa's unhinted output
/// up to its 1/64 px quantisation (applied later by `ttf.emitGlyph`); component offset
/// deltas are rounded like FreeType does.
///
/// Returns null — with nothing emitted — when the glyph is a simple glyph with more than
/// `max_points` points: the caller then draws the unvaried outline. (A *component* that
/// large is skipped.) Stack use: ~44 KiB in one non-recursive leaf frame.
pub fn glyfOutline(f: *const Font, gid: u16, out: *const PathOut) ?bool {
    const g = f.glyphData(gid);
    if (g.len >= 10 and rdi16(g, 0) > 0 and pointCount(g) > max_points) return null;
    var budget: u32 = 256;
    return rec(f, gid, .{}, 0, &budget, out);
}

// ------------------------------------------------------------------ tests

const tst = std.testing;

test "fixed-point helpers" {
    try tst.expectEqual(@as(i32, 0x8000), fxMul(0x10000, 0x8000));
    try tst.expectEqual(@as(i32, -0x8000), fxMul(-0x10000, 0x8000));
    try tst.expectEqual(@as(i32, 0x8000), fxDiv(0x10000, 0x20000));
    try tst.expectEqual(@as(i32, -0x5555), fxDiv(-0x10000, 0x30000));
    try tst.expectEqual(@as(i32, 0x7fffffff), fxDiv(5, 0));
    try tst.expectEqual(@as(i32, 3), fxMulDiv(2, 3, 2));
    try tst.expectEqual(@as(i32, -65536), fromF32(-1));
    try tst.expectEqual(@as(i32, 0), fromF32(std.math.nan(f32)));
}

/// fvar with the given axes (min, default, max) in whole units.
fn testFvar(comptime axes: []const struct { tag: *const [4]u8, min: i16, def: i16, max: i16 }) [16 + axes.len * 20]u8 {
    var b: [16 + axes.len * 20]u8 = @splat(0);
    b[1] = 1;
    b[5] = 16;
    b[9] = @intCast(axes.len);
    b[11] = 20;
    for (axes, 0..) |a, i| {
        const r = 16 + i * 20;
        @memcpy(b[r..][0..4], a.tag);
        std.mem.writeInt(i32, b[r + 4 ..][0..4], @as(i32, a.min) << 16, .big);
        std.mem.writeInt(i32, b[r + 8 ..][0..4], @as(i32, a.def) << 16, .big);
        std.mem.writeInt(i32, b[r + 12 ..][0..4], @as(i32, a.max) << 16, .big);
    }
    return b;
}

test "normalize: fvar clamp, last setting wins, avar segment map" {
    const fvar = testFvar(&.{
        .{ .tag = "wght", .min = 100, .def = 400, .max = 900 },
        .{ .tag = "wdth", .min = 50, .def = 100, .max = 100 },
    });
    var c: [max_axes]i16 = undefined;
    try tst.expectEqual(@as(u8, 2), normalize(&fvar, &.{}, &.{}, &c));
    try tst.expectEqualSlices(i16, &.{ 0, 0 }, c[0..2]);
    _ = normalize(&fvar, &.{}, &.{ .{ .tag = "wght".*, .value = 900 }, .{ .tag = "wght".*, .value = 650 }, .{ .tag = "wdth".*, .value = 75 }, .{ .tag = "zzzz".*, .value = 1 } }, &c);
    try tst.expectEqualSlices(i16, &.{ 8192, -8192 }, c[0..2]);
    _ = normalize(&fvar, &.{}, &.{ .{ .tag = "wght".*, .value = 5000 }, .{ .tag = "wdth".*, .value = 300 } }, &c);
    try tst.expectEqualSlices(i16, &.{ 16384, 0 }, c[0..2]);
    _ = normalize(&fvar, &.{}, &.{.{ .tag = "wght".*, .value = 250 }}, &c);
    try tst.expectEqualSlices(i16, &.{ -8192, 0 }, c[0..2]);

    // avar: axis 0 maps -1 -> -1, 0 -> 0, 0.5 -> 0.25, 1 -> 1; axis 1 has the identity map
    const avar = [_]u8{ 0, 1, 0, 0, 0, 0, 0, 2 } ++
        [_]u8{ 0, 4, 0xc0, 0, 0xc0, 0, 0, 0, 0, 0, 0x20, 0, 0x10, 0, 0x40, 0, 0x40, 0 } ++
        [_]u8{ 0, 3, 0xc0, 0, 0xc0, 0, 0, 0, 0, 0, 0x40, 0, 0x40, 0 };
    _ = normalize(&fvar, &avar, &.{ .{ .tag = "wght".*, .value = 650 }, .{ .tag = "wdth".*, .value = 75 } }, &c);
    try tst.expectEqualSlices(i16, &.{ 4096, -8192 }, c[0..2]);
    _ = normalize(&fvar, &avar, &.{.{ .tag = "wght".*, .value = 775 }}, &c);
    try tst.expectEqual(@as(i16, 4096 + 6144), c[0]); // 0.75 -> 0.25 + 0.75 * 0.5
    _ = normalize(&fvar, &avar, &.{.{ .tag = "wght".*, .value = 525 }}, &c);
    try tst.expectEqual(@as(i16, 2048), c[0]); // 0.25 -> 0.125

    const a = axisAt(&fvar, 1).?;
    try tst.expectEqualStrings("wdth", &a.tag);
    try tst.expectEqual(@as(f32, 50), a.min);
    try tst.expect(axisAt(&fvar, 2) == null);
    try tst.expectEqual(@as(f32, 900), findAxis(&fvar, "wght").?.max);
}

test "ItemVariationStore: regions, intermediate, word/byte deltas, index map" {
    // 1 axis, 2 regions: [0, 1, 1] and [0, 0.5, 1]; one subtable, 2 items, 1 word + 1 byte delta
    const store = [_]u8{ 0, 1, 0, 0, 0, 12, 0, 1, 0, 0, 0, 28 } ++
        [_]u8{ 0, 1, 0, 2, 0, 0, 0x40, 0, 0x40, 0, 0, 0, 0x20, 0, 0x40, 0 } ++
        [_]u8{ 0, 2, 0, 1, 0, 2, 0, 0, 0, 1 } ++
        [_]u8{ 0x01, 0x00, 10, 0xff, 0x00, 0xf6 }; // item0: 256, 10; item1: -256, -10
    try tst.expectEqual(@as(i32, 0x10000), regionScalar(&store, 0, &.{16384}));
    try tst.expectEqual(@as(i32, 0x8000), regionScalar(&store, 0, &.{8192}));
    try tst.expectEqual(@as(i32, 0), regionScalar(&store, 0, &.{-8192}));
    try tst.expectEqual(@as(i32, 0x10000), regionScalar(&store, 1, &.{8192}));
    try tst.expectEqual(@as(i32, 0x8000), regionScalar(&store, 1, &.{12288}));
    try tst.expectEqual(@as(i32, 0), regionScalar(&store, 1, &.{16384}));
    try tst.expectEqual(@as(i32, 0), regionScalar(&store, 2, &.{8192}));
    try tst.expectEqual(@as(i32, 256), itemDeltaInt(&store, 0, 0, &.{16384}));
    try tst.expectEqual(@as(i32, 138), itemDeltaInt(&store, 0, 0, &.{8192}));
    try tst.expectEqual(@as(i32, -138), itemDeltaInt(&store, 0, 1, &.{8192}));
    try tst.expectApproxEqAbs(@as(f32, 197), itemDelta(&store, 0, 0, &.{12288}), 0.001);
    try tst.expectEqual(@as(i32, 0), itemDeltaInt(&store, 0, 2, &.{8192}));
    try tst.expectEqual(@as(i32, 0), itemDeltaInt(&store, 1, 0, &.{8192}));
    try tst.expectEqual(@as(i32, 0), itemDeltaInt(&store, 0, 0, &.{}));

    // DeltaSetIndexMap format 0, 1-byte entries with 4 inner bits: glyph 0 -> (0,1), 1.. -> (0,0)
    const map = [_]u8{ 0, 0x03, 0, 2, 0x01, 0x00 };
    try tst.expectEqual(@as(u32, 1), deltaSetIndex(&map, 0));
    try tst.expectEqual(@as(u32, 0), deltaSetIndex(&map, 1));
    try tst.expectEqual(@as(u32, 0), deltaSetIndex(&map, 900));
    // HVAR wrapping both
    var hvar: [20 + store.len + map.len]u8 = undefined;
    @memcpy(hvar[0..20], &[_]u8{ 0, 1, 0, 0, 0, 0, 0, 20, 0, 0, 0, 20 + store.len, 0, 0, 0, 0, 0, 0, 0, 0 });
    @memcpy(hvar[20..][0..store.len], &store);
    @memcpy(hvar[20 + store.len ..], &map);
    try tst.expectEqual(@as(i32, -138), hvarAdvanceDelta(&hvar, 0, &.{8192}));
    try tst.expectEqual(@as(i32, 138), hvarAdvanceDelta(&hvar, 7, &.{8192}));
    // MVAR: one record 'hasc' -> (0, 1)
    var mvar: [20 + store.len]u8 = undefined;
    @memcpy(mvar[0..20], &[_]u8{ 0, 1, 0, 0, 0, 0, 0, 8, 0, 1, 0, 20 } ++ "hasc" ++ [_]u8{ 0, 0, 0, 1 });
    @memcpy(mvar[20..], &store);
    try tst.expectEqual(@as(i32, -256), mvarDelta(&mvar, "hasc", &.{16384}));
    try tst.expectEqual(@as(i32, 0), mvarDelta(&mvar, "hdsc", &.{16384}));
}

test "packed point numbers and deltas" {
    // 5 points: byte run of 3 (1, +2, +3), word run of 2 (+0x100, +1)
    const pd = [_]u8{ 5, 0x02, 1, 2, 3, 0x81, 0x01, 0x00, 0x00, 0x01, 0xee };
    var p = Points.init(&pd, 0);
    try tst.expect(!p.all);
    try tst.expectEqual(@as(u32, 10), p.end());
    const want = [_]u32{ 1, 3, 6, 0x106, 0x107 };
    for (want) |w| try tst.expectEqual(w, p.next().?);
    try tst.expect(p.next() == null);
    try tst.expect(Points.init(&.{0}, 0).all);
    // two-byte count
    const p2 = Points.init(&.{ 0x81, 0x02 }, 0);
    try tst.expectEqual(@as(u32, 258), p2.left);

    // deltas: 2 bytes (5, -3), 3 zeros, 1 word (-300), then exhausted -> zeros
    var d: Deltas = .{ .d = &.{ 0x01, 5, 0xfd, 0x82, 0x40, 0xfe, 0xd4 }, .pos = 0 };
    const dw = [_]i32{ 5, -3, 0, 0, 0, -300, 0, 0 };
    for (dw) |w| try tst.expectEqual(w, d.next());
}

test "tuple scalar: peak, intermediate, out of range" {
    const pk = [_]u8{ 0x40, 0x00, 0x00, 0x00 }; // peak (1, 0)
    try tst.expectEqual(@as(i32, 0x10000), tupleScalar(&pk, &.{}, 2, &.{ 16384, 5 }));
    try tst.expectEqual(@as(i32, 0x8000), tupleScalar(&pk, &.{}, 2, &.{8192}));
    try tst.expectEqual(@as(i32, 0), tupleScalar(&pk, &.{}, 2, &.{ -8192, 0 }));
    try tst.expectEqual(@as(i32, 0), tupleScalar(&pk, &.{}, 2, &.{ 0, 16384 }));
    // intermediate region 0.25 .. 0.5 .. 1.0 on axis 0
    const pk2 = [_]u8{ 0x20, 0x00, 0x00, 0x00 };
    const inter = [_]u8{ 0x10, 0, 0, 0, 0x40, 0, 0, 0 };
    try tst.expectEqual(@as(i32, 0x10000), tupleScalar(&pk2, &inter, 2, &.{8192}));
    try tst.expectEqual(@as(i32, 0x8000), tupleScalar(&pk2, &inter, 2, &.{6144}));
    try tst.expectEqual(@as(i32, 0x8000), tupleScalar(&pk2, &inter, 2, &.{12288}));
    try tst.expectEqual(@as(i32, 0), tupleScalar(&pk2, &inter, 2, &.{4096}));
    try tst.expectEqual(@as(i32, 0), tupleScalar(&pk2, &inter, 2, &.{16384}));
    try tst.expectEqual(@as(i32, 0), tupleScalar(pk2[0..2], &.{}, 2, &.{8192})); // truncated peak
}

test "IUP: interpolate, clamp outside, coincident references, untouched contour" {
    // contour of 6 points on a line; touched: #0 (delta 10) and #3 (delta 40)
    const o = [_]i16{ 0, 10, 20, 30, 50, -5 };
    var d = [_]f32{ 10, 0, 0, 40, 0, 0 };
    const fl = [_]u8{ 2, 0, 0, 2, 0, 0 };
    iupContour(&o, &d, &fl, 0, 5);
    try tst.expectEqualSlices(f32, &.{ 10, 20, 30, 40, 40, 10 }, &d);
    // references with the same coordinate: equal deltas propagate, different deltas give 0
    const o2 = [_]i16{ 5, 7, 5, 9 };
    var d2 = [_]f32{ 3, 0, 3, 0 };
    const fl2 = [_]u8{ 2, 0, 2, 0 };
    iupContour(&o2, &d2, &fl2, 0, 3);
    try tst.expectEqualSlices(f32, &.{ 3, 3, 3, 3 }, &d2);
    var d3 = [_]f32{ 3, 0, 4, 0 };
    iupContour(&o2, &d3, &fl2, 0, 3);
    try tst.expectEqualSlices(f32, &.{ 3, 0, 4, 0 }, &d3);
    // a single touched point shifts the whole contour
    var d4 = [_]f32{ 0, 0, -6, 0 };
    const fl4 = [_]u8{ 0, 0, 2, 0 };
    iupContour(&o2, &d4, &fl4, 0, 3);
    try tst.expectEqualSlices(f32, &.{ -6, -6, -6, -6 }, &d4);
    // nothing touched: untouched
    var d5 = [_]f32{ 1, 2, 3, 4 };
    const fl5 = [_]u8{ 0, 0, 0, 0 };
    iupContour(&o2, &d5, &fl5, 0, 3);
    try tst.expectEqualSlices(f32, &.{ 1, 2, 3, 4 }, &d5);
    // sub-range only (second contour of a glyph)
    var d6 = [_]f32{ 9, 9, 5, 0 };
    const fl6 = [_]u8{ 0, 0, 2, 0 };
    iupContour(&o2, &d6, &fl6, 2, 3);
    try tst.expectEqualSlices(f32, &.{ 9, 9, 5, 5 }, &d6);
}
