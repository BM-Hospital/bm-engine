//! WOFF 2.0 decoder (W3C WOFF2 Recommendation): header, table directory (known-tag indices,
//! UIntBase128), collection directory (TTC output), the single brotli stream, glyf/loca transform
//! reconstruction, hmtx transform reconstruction, sfnt rebuild with table checksums and
//! head.checkSumAdjustment.
//!
//! The output layout follows the reference decoder (google/woff2): table records sorted by tag,
//! table data in that order (glyf immediately followed by its reconstructed loca), every table
//! and every reconstructed glyph padded to 4 bytes, so outputs are byte-identical to it.
//! head.flags bit 11 (set by encoders to flag the lossless transform) is passed through
//! unchanged, as the reference does.
const std = @import("std");
const brotli = @import("brotli.zig");
const sfnt = @import("sfnt.zig");
const tag = sfnt.tag;
const rd16 = sfnt.rd16;
const rd32 = sfnt.rd32;
const wr16 = sfnt.wr16;
const wr32 = sfnt.wr32;

pub const Error = error{ InvalidData, OutputTooLarge, OutOfMemory };

const known_tags = [63]u32{
    tag("cmap"), tag("head"), tag("hhea"), tag("hmtx"), tag("maxp"), tag("name"), tag("OS/2"), tag("post"),
    tag("cvt "), tag("fpgm"), tag("glyf"), tag("loca"), tag("prep"), tag("CFF "), tag("VORG"), tag("EBDT"),
    tag("EBLC"), tag("gasp"), tag("hdmx"), tag("kern"), tag("LTSH"), tag("PCLT"), tag("VDMX"), tag("vhea"),
    tag("vmtx"), tag("BASE"), tag("GDEF"), tag("GPOS"), tag("GSUB"), tag("EBSC"), tag("JSTF"), tag("MATH"),
    tag("CBDT"), tag("CBLC"), tag("COLR"), tag("CPAL"), tag("SVG "), tag("sbix"), tag("acnt"), tag("avar"),
    tag("bdat"), tag("bloc"), tag("bsln"), tag("cvar"), tag("fdsc"), tag("feat"), tag("fmtx"), tag("fvar"),
    tag("gvar"), tag("hsty"), tag("just"), tag("lcar"), tag("mort"), tag("morx"), tag("opbd"), tag("prop"),
    tag("trak"), tag("Zapf"), tag("Silf"), tag("Glat"), tag("Gloc"), tag("Feat"), tag("Sill"),
};

const Table = struct {
    tag: u32,
    transformed: bool,
    orig_len: u32,
    /// Location in the decompressed stream.
    src_off: u32,
    src_len: u32,
    /// Output location (0 = not yet placed).
    dst_off: u32 = 0,
    dst_len: u32 = 0,
    checksum: u32 = 0,
    /// Index into `recons` for a transformed glyf / its loca / a transformed hmtx.
    recon: u16 = 0xffff,
};

const Font = struct {
    flavor: u32,
    /// Range in the shared index list.
    first: u32,
    count: u16,
};

/// A reconstructed glyf/loca pair (or a reconstructed hmtx).
const Recon = struct {
    /// Reconstructed glyf (or hmtx) bytes.
    data: std.ArrayList(u8) = .empty,
    loca: []u8 = &.{},
    xmins: []i16 = &.{},
};

/// Every temporary of one decode, released in one place (keeps the error paths small: a
/// `defer` per buffer would be duplicated at each of the ~60 `try` exits).
const Temps = struct {
    alloc: std.mem.Allocator,
    tables: []Table = &.{},
    fonts: []Font = &.{},
    indices: std.ArrayList(u16) = .empty,
    tags: []u32 = &.{},
    stream: []u8 = &.{},
    recons: std.ArrayList(Recon) = .empty,
    scratch: std.ArrayList(u8) = .empty,
    written: []bool = &.{},

    fn deinit(s: *Temps) void {
        const a = s.alloc;
        for (s.recons.items) |*rc| {
            rc.data.deinit(a);
            a.free(rc.loca);
            a.free(rc.xmins);
        }
        s.recons.deinit(a);
        s.scratch.deinit(a);
        s.indices.deinit(a);
        a.free(s.tables);
        a.free(s.fonts);
        a.free(s.tags);
        a.free(s.stream);
        a.free(s.written);
    }
};

const Reader = struct {
    b: []const u8,
    p: usize = 0,

    fn left(r: *const Reader) usize {
        return r.b.len - r.p;
    }
    fn u8_(r: *Reader) Error!u8 {
        if (r.p >= r.b.len) return error.InvalidData;
        r.p += 1;
        return r.b[r.p - 1];
    }
    fn u16_(r: *Reader) Error!u16 {
        if (r.left() < 2) return error.InvalidData;
        r.p += 2;
        return rd16(r.b, r.p - 2);
    }
    fn u32_(r: *Reader) Error!u32 {
        if (r.left() < 4) return error.InvalidData;
        r.p += 4;
        return rd32(r.b, r.p - 4);
    }
    fn take(r: *Reader, n: usize) Error![]const u8 {
        if (n > r.left()) return error.InvalidData;
        r.p += n;
        return r.b[r.p - n ..][0..n];
    }
    fn base128(r: *Reader) Error!u32 {
        var acc: u32 = 0;
        for (0..5) |i| {
            const b = try r.u8_();
            if (i == 0 and b == 0x80) return error.InvalidData; // leading zeros
            if (acc & 0xFE000000 != 0) return error.InvalidData; // overflow
            acc = (acc << 7) | (b & 0x7f);
            if (b & 0x80 == 0) return acc;
        }
        return error.InvalidData;
    }
    fn read255(r: *Reader) Error!u16 {
        const c = try r.u8_();
        return switch (c) {
            253 => try r.u16_(),
            255 => @as(u16, try r.u8_()) + 253,
            254 => @as(u16, try r.u8_()) + 506,
            else => c,
        };
    }
};

/// Decodes a WOFF2 file into a TrueType/CFF sfnt (or a TTC for collections) allocated from
/// `alloc` (caller owns it). `max_out` caps the output and every intermediate buffer.
/// Temporaries (decompressed stream, reconstructed glyf, dictionary) are allocated before the
/// output and freed before returning.
pub fn decode(alloc: std.mem.Allocator, data: []const u8, max_out: usize) Error![]u8 {
    var s: Temps = .{ .alloc = alloc };
    defer s.deinit();
    return decodeInner(&s, data, max_out);
}

noinline fn decodeInner(s: *Temps, data: []const u8, max_out: usize) Error![]u8 {
    const alloc = s.alloc;
    if (data.len < 48 or rd32(data, 0) != tag("wOF2")) return error.InvalidData;
    const flavor = rd32(data, 4);
    const num_tables = rd16(data, 12);
    const total_sfnt = rd32(data, 16);
    const total_comp = rd32(data, 20);
    if (num_tables == 0) return error.InvalidData;
    // Sanity bound from the header (the reconstructed glyf may legitimately differ a little).
    const cap: usize = @min(max_out, @as(usize, total_sfnt) +| (total_sfnt / 2) +| 65536);

    var r = Reader{ .b = data, .p = 48 };
    s.tables = try alloc.alloc(Table, num_tables);
    const tables = s.tables;
    var src_total: u64 = 0;
    for (tables) |*t| {
        const flags = try r.u8_();
        const tg = if (flags & 63 == 63) try r.u32_() else known_tags[flags & 63];
        const xv = flags >> 6;
        const orig = try r.base128();
        var transformed = false;
        if (tg == tag("glyf") or tg == tag("loca")) {
            if (xv == 0) transformed = true else if (xv != 3) return error.InvalidData;
        } else if (tg == tag("hmtx")) {
            if (xv == 1) transformed = true else if (xv != 0) return error.InvalidData;
        } else if (xv != 0) return error.InvalidData;
        const src_len = if (transformed) try r.base128() else orig;
        if (tg == tag("loca") and transformed and src_len != 0) return error.InvalidData;
        t.* = .{ .tag = tg, .transformed = transformed, .orig_len = orig, .src_off = @intCast(@min(src_total, 0xffff_ffff)), .src_len = src_len };
        src_total += src_len;
        if (src_total > cap) return error.OutputTooLarge;
    }

    // Fonts (one, or the collection directory).
    var ttc_version: u32 = 0;
    const list = &s.indices;
    if (flavor == tag("ttcf")) {
        ttc_version = try r.u32_();
        if (ttc_version != 0x00010000 and ttc_version != 0x00020000) return error.InvalidData;
        const nf = try r.read255();
        if (nf == 0) return error.InvalidData;
        s.fonts = try alloc.alloc(Font, nf);
        for (s.fonts) |*f| {
            const nt = try r.read255();
            const fl = try r.u32_();
            if (nt == 0) return error.InvalidData;
            f.* = .{ .flavor = fl, .first = @intCast(list.items.len), .count = nt };
            for (0..nt) |_| {
                const ix = try r.read255();
                if (ix >= num_tables) return error.InvalidData;
                try list.append(alloc, ix);
            }
        }
    } else {
        try list.resize(alloc, num_tables);
        for (list.items, 0..) |*x, i| x.* = @intCast(i);
        s.fonts = try alloc.alloc(Font, 1);
        s.fonts[0] = .{ .flavor = flavor, .first = 0, .count = num_tables };
    }
    const fonts = s.fonts;
    const indices = list.items;

    // Sort each font's tables by tag; reject duplicate tags within a font.
    s.tags = try alloc.alloc(u32, num_tables);
    const tags = s.tags;
    for (tags, tables) |*k, t| k.* = t.tag;
    for (fonts) |f| {
        const ix = indices[f.first..][0..f.count];
        sfnt.sortByKey(ix, tags);
        for (1..ix.len) |k| if (tables[ix[k]].tag == tables[ix[k - 1]].tag) return error.InvalidData;
    }

    // Decompress the font data stream.
    if (total_comp > r.left()) return error.InvalidData;
    const comp = data[r.p..][0..total_comp];
    s.stream = try alloc.alloc(u8, @intCast(src_total));
    const stream = s.stream;
    const got = brotli.decompressInto(alloc, comp, stream) catch |e| return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidData,
    };
    if (got != stream.len) return error.InvalidData;

    // Reconstruct transformed tables.
    const recons = &s.recons;
    for (fonts) |f| {
        const ix = indices[f.first..][0..f.count];
        var glyf_i: ?u16 = null;
        var loca_i: ?u16 = null;
        var hmtx_i: ?u16 = null;
        var hhea_i: ?u16 = null;
        for (ix) |k| switch (tables[k].tag) {
            tag("glyf") => glyf_i = k,
            tag("loca") => loca_i = k,
            tag("hmtx") => hmtx_i = k,
            tag("hhea") => hhea_i = k,
            else => {},
        };
        if (glyf_i) |g| {
            const l = loca_i orelse return error.InvalidData;
            if (tables[g].transformed != tables[l].transformed) return error.InvalidData;
            if (fonts.len > 1 and l != g + 1) return error.InvalidData; // collections: paired
            if (tables[g].transformed) {
                if (tables[g].recon == 0xffff) {
                    if (tables[l].recon != 0xffff) return error.InvalidData; // loca shared with another glyf
                    try recons.append(alloc, .{});
                    const rc = &recons.items[recons.items.len - 1];
                    try reconstructGlyf(alloc, stream[tables[g].src_off..][0..tables[g].src_len], tables[l].orig_len, rc, &s.scratch, cap);
                    const id: u16 = @intCast(recons.items.len - 1);
                    tables[g].recon = id;
                    tables[l].recon = id;
                    tables[g].dst_len = @intCast(rc.data.items.len);
                    tables[l].dst_len = @intCast(rc.loca.len);
                } else if (tables[l].recon != tables[g].recon) return error.InvalidData;
            }
        } else if (loca_i != null and tables[loca_i.?].transformed) return error.InvalidData;
        if (hmtx_i) |h| {
            if (tables[h].transformed and tables[h].recon == 0xffff) {
                const g = glyf_i orelse return error.InvalidData;
                if (!tables[g].transformed) return error.InvalidData;
                const hh = hhea_i orelse return error.InvalidData;
                if (tables[hh].src_len < 36 or tables[hh].transformed) return error.InvalidData;
                const nh = rd16(stream[tables[hh].src_off..][0..tables[hh].src_len], 34);
                const xm = recons.items[tables[g].recon].xmins;
                try recons.append(alloc, .{});
                const rc = &recons.items[recons.items.len - 1];
                try reconstructHmtx(alloc, stream[tables[h].src_off..][0..tables[h].src_len], xm, nh, &rc.data);
                tables[h].recon = @intCast(recons.items.len - 1);
                tables[h].dst_len = @intCast(rc.data.items.len);
            }
        }
    }
    for (tables) |*t| {
        if (!t.transformed) t.dst_len = t.src_len else if (t.recon == 0xffff) return error.InvalidData;
        if (t.tag == tag("head") and t.dst_len < 12) return error.InvalidData;
    }

    // Layout.
    const collection = fonts.len > 1 or flavor == tag("ttcf");
    var size: u64 = 0;
    if (collection) size = 12 + 4 * @as(u64, fonts.len) + (if (ttc_version == 0x00020000) @as(u64, 12) else 0);
    for (fonts) |f| size += 12 + 16 * @as(u64, f.count);
    const hdr_size = size;
    for (fonts) |f| {
        for (indices[f.first..][0..f.count]) |k| {
            const t = &tables[k];
            if (t.dst_off != 0) continue;
            if (t.tag == tag("loca") and t.transformed) continue; // placed right after its glyf
            t.dst_off = @intCast(@min(size, 0xffff_ffff));
            size += sfnt.pad4(t.dst_len);
            if (t.tag == tag("glyf") and t.transformed) {
                for (tables) |*lt| if (lt.tag == tag("loca") and lt.transformed and lt.recon == t.recon and lt.dst_off == 0) {
                    lt.dst_off = @intCast(@min(size, 0xffff_ffff));
                    size += sfnt.pad4(lt.dst_len);
                };
            }
            if (size > cap) return error.OutputTooLarge;
        }
    }
    // A transformed loca whose glyf is in no font cannot happen (validated above), but guard.
    for (indices) |k| if (tables[k].dst_off == 0) return error.InvalidData;
    if (size > cap) return error.OutputTooLarge;

    s.written = try alloc.alloc(bool, num_tables);
    const written = s.written;
    @memset(written, false);
    // The result is allocated last (no fallible step follows).
    const out = try alloc.alloc(u8, @intCast(size));
    @memset(out[0..@intCast(hdr_size)], 0);

    // Table data + checksums.
    for (indices) |k| {
        if (written[k]) continue;
        written[k] = true;
        const t = &tables[k];
        const dst = out[t.dst_off..][0..t.dst_len];
        if (!t.transformed) {
            @memcpy(dst, stream[t.src_off..][0..t.src_len]);
        } else {
            const rc = recons.items[t.recon];
            @memcpy(dst, if (t.tag == tag("loca")) rc.loca else rc.data.items);
        }
        @memset(out[t.dst_off + t.dst_len ..][0 .. sfnt.pad4(t.dst_len) - t.dst_len], 0);
        if (t.tag == tag("head")) wr32(dst, 8, 0); // checkSumAdjustment is recomputed below
        t.checksum = sfnt.checksum(dst);
    }

    // Headers.
    var off: usize = 0;
    if (collection) {
        wr32(out, 0, tag("ttcf"));
        wr32(out, 4, ttc_version);
        wr32(out, 8, @intCast(fonts.len));
        off = 12 + 4 * fonts.len + (if (ttc_version == 0x00020000) @as(usize, 12) else 0);
    }
    for (fonts, 0..) |f, fi| {
        if (collection) wr32(out, 12 + 4 * fi, @intCast(off));
        const dir = off;
        sfnt.writeOffsetTable(out, off, f.flavor, f.count);
        off += 12;
        var sum: u32 = 0;
        var head_off: ?usize = null;
        for (indices[f.first..][0..f.count]) |k| {
            const t = tables[k];
            wr32(out, off, t.tag);
            wr32(out, off + 4, t.checksum);
            wr32(out, off + 8, t.dst_off);
            wr32(out, off + 12, t.dst_len);
            off += 16;
            sum +%= t.checksum;
            if (t.tag == tag("head")) head_off = t.dst_off;
        }
        if (head_off) |h| sfnt.fixHeadAdjustment(out, dir, f.count, h, sum);
    }
    return out;
}

// ------------------------------------------------------------------ glyf / loca


const glyf_on_curve = 1;
const glyf_x_short = 1 << 1;
const glyf_y_short = 1 << 2;
const glyf_repeat = 1 << 3;
const glyf_x_same = 1 << 4;
const glyf_y_same = 1 << 5;
const glyf_overlap = 1 << 6;

/// Triplet encoding (WOFF2 5.2) as data: `nb` payload bytes read big-endian into v; dx magnitude =
/// bx + (v >> ybits & mask(xbits)), dy magnitude = by + (v & mask(ybits)); the sign of dx is flag
/// bit 0, the sign of dy is flag bit `ysign` (set = positive).
const Triplet = struct { nb: u8, ybits: u8, ysign: u8, xmask: u16, ymask: u16, bx: i16, by: i16 };
fn trip(nb: u8, xbits: u5, ybits: u5, ysign: u8, bx: i16, by: i16) Triplet {
    return .{ .nb = nb, .ybits = ybits, .ysign = ysign, .xmask = @intCast((@as(u32, 1) << xbits) - 1), .ymask = @intCast((@as(u32, 1) << ybits) - 1), .bx = bx, .by = by };
}
const triplets = blk: {
    var t: [128]Triplet = undefined;
    for (0..128) |f| {
        t[f] = if (f < 10)
            trip(1, 0, 8, 0, 0, (f & 14) << 7)
        else if (f < 20)
            trip(1, 8, 0, 0, ((f - 10) & 14) << 7, 0)
        else if (f < 84)
            trip(1, 4, 4, 1, 1 + ((f - 20) & 0x30), 1 + (((f - 20) & 0x0c) << 2))
        else if (f < 120)
            trip(2, 8, 8, 1, 1 + (((f - 84) / 12) << 8), 1 + ((((f - 84) % 12) >> 2) << 8))
        else if (f < 124)
            trip(3, 12, 12, 1, 0, 0)
        else
            trip(4, 16, 16, 1, 0, 0);
    }
    break :blk t;
};

/// Reconstructs glyf + loca from the transformed glyf table (version 0).
/// Output goes to `rc` (owned by the caller's Temps, so no cleanup here); `tmp` is scratch.
noinline fn reconstructGlyf(alloc: std.mem.Allocator, src: []const u8, loca_len: u32, rc: *Recon, tmp: *std.ArrayList(u8), cap: usize) Error!void {
    if (src.len < 36) return error.InvalidData;
    const options = rd16(src, 2);
    const ng: u32 = rd16(src, 4);
    const index_format = rd16(src, 6);
    var r = Reader{ .b = src, .p = 36 };
    var streams: [7]Reader = undefined;
    for (&streams, 0..) |*s, i| s.* = .{ .b = try r.take(rd32(src, 8 + 4 * i)) };
    var overlap: []const u8 = &.{};
    if (options & 1 != 0) overlap = try r.take((ng + 7) >> 3);
    const ncont = &streams[0];
    const npts = &streams[1];
    const flags = &streams[2];
    const glyphs = &streams[3];
    const comps = &streams[4];
    const bbox_bitmap = try streams[5].take(((ng + 31) >> 5) << 2);
    const bboxes = &streams[5];
    const instrs = &streams[6];

    const loca_size = (ng + 1) * @as(u32, if (index_format != 0) 4 else 2);
    if (loca_len != loca_size) return error.InvalidData;
    rc.loca = try alloc.alloc(u8, loca_size);
    rc.xmins = try alloc.alloc(i16, ng);
    @memset(rc.xmins, 0);

    const out = &rc.data;
    // Capacity hint: transformed data is usually ~70-80% of the reconstructed size.
    try out.ensureTotalCapacity(alloc, @min(cap, src.len + src.len / 2 + 64));

    var i: u32 = 0;
    while (i < ng) : (i += 1) {
        const start = out.items.len;
        if (start > cap) return error.OutputTooLarge;
        try storeLoca(rc.loca, index_format, i, start);
        const nc: i16 = @bitCast(try ncont.u16_());
        const has_bbox = bbox_bitmap[i >> 3] & (@as(u8, 0x80) >> @as(u3, @intCast(i & 7))) != 0;
        if (nc == 0) {
            if (has_bbox) return error.InvalidData;
            continue;
        }
        if (nc == -1) {
            // Composite: bbox is mandatory.
            if (!has_bbox) return error.InvalidData;
            const cstart = comps.p;
            var have_instr = false;
            while (true) {
                const fl = try comps.u16_();
                have_instr = have_instr or (fl & 0x100 != 0);
                var arg: usize = 2 + @as(usize, if (fl & 1 != 0) 4 else 2);
                if (fl & 0x8 != 0) arg += 2 else if (fl & 0x40 != 0) arg += 4 else if (fl & 0x80 != 0) arg += 8;
                _ = try comps.take(arg);
                if (fl & 0x20 == 0) break;
            }
            const cdata = comps.b[cstart..comps.p];
            var ilen: u16 = 0;
            if (have_instr) ilen = try glyphs.read255();
            const ins = try instrs.take(ilen);
            const g = try out.addManyAsSlice(alloc, 10 + cdata.len + (if (have_instr) 2 + ins.len else 0));
            wr16(g, 0, 0xffff);
            @memcpy(g[2..10], try bboxes.take(8));
            @memcpy(g[10..][0..cdata.len], cdata);
            if (have_instr) {
                wr16(g, 10 + cdata.len, ilen);
                @memcpy(g[12 + cdata.len ..][0..ins.len], ins);
            }
        } else if (nc > 0) {
            const ncu: usize = @intCast(nc);
            // End points.
            const hdr = try out.addManyAsSlice(alloc, 10 + 2 * ncu);
            wr16(hdr, 0, @bitCast(nc));
            var total: u32 = 0;
            for (0..ncu) |c| {
                total += try npts.read255();
                if (total > 0x10000) return error.InvalidData;
                if (total == 0) return error.InvalidData; // end point would be -1
                wr16(hdr, 10 + 2 * c, @intCast(total - 1));
            }
            const fl = try flags.take(total);
            const has_overlap = overlap.len != 0 and overlap[i >> 3] & (@as(u8, 0x80) >> @as(u3, @intCast(i & 7))) != 0;
            // One fused pass per point: triplet decode, bbox, TrueType flag (RLE) and coordinate
            // bytes into three scratch areas (flags <= n, x <= 2n, y <= 2n, +2 slack each).
            try tmp.resize(alloc, 5 * @as(usize, total) + 8);
            const fbuf = tmp.items[0..];
            const xbuf = tmp.items[total + 2 ..];
            const ybuf = tmp.items[3 * @as(usize, total) + 4 ..];
            var fo: usize = 0;
            var xo: usize = 0;
            var yo: usize = 0;
            var last_flag: u32 = 0xffff;
            var repeat: u8 = 0;
            var x: i32 = 0;
            var y: i32 = 0;
            var ovf: u1 = 0;
            var x0: i32 = std.math.maxInt(i32);
            var y0: i32 = std.math.maxInt(i32);
            var x1: i32 = std.math.minInt(i32);
            var y1: i32 = std.math.minInt(i32);
            const gb = glyphs.b;
            var gp = glyphs.p;
            for (fl, 0..) |f0, k| {
                // Table-driven triplet decoding (branch-free apart from the stream tail).
                const e = triplets[f0 & 0x7f];
                const nb: usize = e.nb;
                var v: u32 = undefined;
                if (gb.len - gp >= 4) {
                    const q = gb.ptr + gp;
                    v = ((@as(u32, q[0]) << 24) | (@as(u32, q[1]) << 16) | (@as(u32, q[2]) << 8) | q[3]) >> @as(u5, @intCast(32 - 8 * nb));
                } else {
                    if (nb > gb.len - gp) return error.InvalidData;
                    v = 0;
                    for (gb[gp..][0..nb]) |b| v = (v << 8) | b;
                }
                gp += nb;
                const xr: i32 = @intCast((v >> @as(u5, @intCast(e.ybits))) & e.xmask);
                const yr: i32 = @intCast(v & e.ymask);
                const xneg: i32 = @as(i32, @intCast(f0 & 1)) - 1; // 0 when positive, -1 when negative
                const yneg: i32 = @as(i32, @intCast((f0 >> @as(u3, @intCast(e.ysign))) & 1)) - 1;
                const dx: i32 = ((e.bx + xr) ^ xneg) - xneg;
                const dy: i32 = ((e.by + yr) ^ yneg) - yneg;
                const sx = @addWithOverflow(x, dx);
                const sy = @addWithOverflow(y, dy);
                x = sx[0];
                y = sy[0];
                ovf |= sx[1] | sy[1];
                x0 = @min(x0, x);
                x1 = @max(x1, x);
                y0 = @min(y0, y);
                y1 = @max(y1, y);
                // Output flag; the deltas equal those of the absolute coordinates.
                const ax = axisFlag(dx, glyf_x_short, glyf_x_same);
                const ay = axisFlag(dy, glyf_y_short, glyf_y_same);
                var flag: u8 = ax.flag | ay.flag | @intFromBool(f0 >> 7 == 0);
                if (has_overlap and k == 0) flag |= glyf_overlap;
                if (flag == last_flag and repeat != 255) {
                    fbuf[fo - 1] |= glyf_repeat;
                    repeat += 1;
                } else {
                    if (repeat != 0) {
                        fbuf[fo] = repeat;
                        fo += 1;
                    }
                    fbuf[fo] = flag;
                    fo += 1;
                    repeat = 0;
                }
                last_flag = flag;
                xo += putCoord(xbuf, xo, dx);
                yo += putCoord(ybuf, yo, dy);
            }
            if (repeat != 0) {
                fbuf[fo] = repeat;
                fo += 1;
            }
            glyphs.p = gp;
            // Coordinates outside i32 are rejected (as the reference decoder does).
            if (ovf != 0) return error.InvalidData;
            const ilen = try glyphs.read255();
            const ins = try instrs.take(ilen);
            const g = try out.addManyAsSlice(alloc, 2 + ins.len + fo + xo + yo);
            wr16(g, 0, ilen);
            @memcpy(g[2..][0..ins.len], ins);
            @memcpy(g[2 + ins.len ..][0..fo], fbuf[0..fo]);
            @memcpy(g[2 + ins.len + fo ..][0..xo], xbuf[0..xo]);
            @memcpy(g[2 + ins.len + fo + xo ..][0..yo], ybuf[0..yo]);
            const gg = out.items[start..];
            if (has_bbox) {
                @memcpy(gg[2..10], try bboxes.take(8));
            } else {
                // (total >= 1, so the extremes are set)
                wr16(gg, 2, @truncate(@as(u32, @bitCast(x0))));
                wr16(gg, 4, @truncate(@as(u32, @bitCast(y0))));
                wr16(gg, 6, @truncate(@as(u32, @bitCast(x1))));
                wr16(gg, 8, @truncate(@as(u32, @bitCast(y1))));
            }
        } else return error.InvalidData;
        rc.xmins[i] = @bitCast(rd16(out.items, start + 2));
        // Pad each glyph to 4 bytes (as the reference decoder does).
        const padded = sfnt.pad4(out.items.len);
        try out.appendNTimes(alloc, 0, padded - out.items.len);
    }
    if (out.items.len > cap) return error.OutputTooLarge;
    try storeLoca(rc.loca, index_format, ng, out.items.len);
}

fn storeLoca(loca: []u8, index_format: u16, i: u32, value: usize) Error!void {
    if (index_format != 0) {
        if (value > 0xffff_ffff) return error.OutputTooLarge;
        wr32(loca, 4 * @as(usize, i), @intCast(value));
    } else {
        if (value >> 1 > 0xffff) return error.InvalidData;
        wr16(loca, 2 * @as(usize, i), @intCast(value >> 1));
    }
}

/// Flag bits and payload size for one coordinate delta (same choices as the reference decoder).
/// Written with masks instead of branches: delta classes are data dependent and unpredictable.
inline fn axisFlag(d: i32, short_bit: u8, same_bit: u8) struct { flag: u8, bytes: u8 } {
    const zero: u8 = @intFromBool(d == 0);
    const short: u8 = @intFromBool(@abs(d) < 256); // includes zero
    const pos: u8 = @intFromBool(d > 0);
    return .{
        .flag = (short_bit * (short & ~zero & 1)) | (same_bit * (zero | (short & pos))),
        .bytes = 2 - short - zero,
    };
}

/// Writes one coordinate delta at `o` (always stores 2 bytes; the caller's buffer has slack and
/// later writes overwrite the unused byte); returns the payload size.
inline fn putCoord(g: []u8, o: usize, d: i32) usize {
    const ad: u32 = @abs(d);
    const short: u32 = @intFromBool(@abs(d) < 256);
    const zero: u32 = @intFromBool(d == 0);
    const u: u32 = @as(u16, @truncate(@as(u32, @bitCast(d))));
    const m = 0 -% short; // all ones when short
    g[o] = @truncate((ad & m) | ((u >> 8) & ~m));
    g[o + 1] = @truncate(u);
    return 2 - short - zero;
}


// ------------------------------------------------------------------ hmtx

noinline fn reconstructHmtx(alloc: std.mem.Allocator, src: []const u8, xmins: []const i16, num_hmetrics: u16, dst: *std.ArrayList(u8)) Error!void {
    var r = Reader{ .b = src };
    const flags = try r.u8_();
    const has_prop = flags & 1 == 0;
    const has_mono = flags & 2 == 0;
    if (flags & 0xfc != 0 or (has_prop and has_mono)) return error.InvalidData;
    const ng = xmins.len;
    const nh: usize = num_hmetrics;
    if (nh > ng or nh < 1) return error.InvalidData;
    const adv = try r.take(2 * nh);
    const prop = if (has_prop) try r.take(2 * nh) else &[_]u8{};
    const mono = if (has_mono) try r.take(2 * (ng - nh)) else &[_]u8{};
    try dst.resize(alloc, 2 * ng + 2 * nh);
    const out = dst.items;
    var o: usize = 0;
    for (0..ng) |i| {
        if (i < nh) {
            @memcpy(out[o..][0..2], adv[2 * i ..][0..2]);
            o += 2;
            if (has_prop) @memcpy(out[o..][0..2], prop[2 * i ..][0..2]) else wr16(out, o, @bitCast(xmins[i]));
        } else {
            if (has_mono) @memcpy(out[o..][0..2], mono[2 * (i - nh) ..][0..2]) else wr16(out, o, @bitCast(xmins[i]));
        }
        o += 2;
    }
}
