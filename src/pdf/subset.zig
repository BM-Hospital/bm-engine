//! Font subsetting for PDF embedding: a port of the `subsetter` crate vendored in takumi-pdf
//! (ref/takumi/takumi-pdf/src/subsetter, subsetter 0.2.6 by Laurenz Stampfl / typst, MIT OR
//! Apache-2.0, see ref/takumi/takumi-pdf/LICENSE-SUBSETTER) with its `variable-fonts` feature.
//!
//! The result is only meant to be embedded as a CID-keyed font: the `cmap` table (and OS/2,
//! GSUB, ...) is dropped, glyph ids are renumbered in the order of the `GlyphRemapper` and the
//! PDF must address glyphs by the new id (= CID; for CFF the subset is converted to a CID-keyed
//! font with an identity charset, so the new id is the CID there as well).
//!
//! Supported input: sfnt / TTC data (WOFF must be decoded before) with
//!  * `glyf` outlines: composite closure, glyf/loca rebuild (short loca when it fits), hinting
//!    tables copied verbatim;
//!  * `CFF ` outlines: see subset_cff.zig (desubroutinised, SID -> CID-keyed);
//!  * variable fonts: like the Rust crate, a TrueType font at a non-default location and every
//!    CFF2 font are *instanced*: each kept glyph is drawn at the location (here through
//!    bm-render's own variation code, `ttf.Font.outline`, instead of skrifa) and re-encoded as
//!    a simple `glyf` glyph (cubics split into quadratics with kurbo's `to_quads(0.025)`), with
//!    advances / lsb / maxp synthesised. The output of a CFF2 font is therefore TrueType.
//!
//! Tables written: glyf+loca (+cvt/fpgm/prep) or CFF, head, hhea+hmtx, maxp, name, post — the
//! same set and the same byte layout as the Rust crate (table checksums and
//! head.checkSumAdjustment are recomputed).
const std = @import("std");
const ttf = @import("../font/ttf.zig");
const cff = @import("subset_cff.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{
    /// Not an sfnt / TTC.
    UnknownKind,
    /// A table is missing or truncated.
    MalformedFont,
    /// A feature the subsetter does not handle (CFF `seac` accents, CFF2 without CFF support).
    Unimplemented,
    /// Internal inconsistency (should not happen).
    SubsetError,
    /// A count or offset does not fit its field.
    OverflowError,
    /// The CFF table could not be processed.
    CFFError,
    OutOfMemory,
};

pub const Flavor = enum { truetype, cff };

/// Instancing (variable glyf at a non-default location, CFF2) needs bm-render's variation or
/// CFF outline code; with both compiled out (core profile) the interjector is not built.
const can_instance = ttf.enable_variations or ttf.enable_cff;

// ------------------------------------------------------------------ remapper

/// Old glyph id -> new glyph id (= CID in the PDF), assigned in first-use order. `.notdef`
/// (glyph 0) is always new id 0. Mirrors `subsetter::GlyphRemapper`.
pub const GlyphRemapper = struct {
    /// Old glyph ids indexed by new id.
    order: std.ArrayList(u16) = .empty,
    /// Open-addressed hash: 0 = empty, else `(old + 1) << 16 | new`.
    slots: []u32 = &.{},

    pub fn init(a: Allocator) Allocator.Error!GlyphRemapper {
        var r: GlyphRemapper = .{};
        _ = r.remap(a, 0) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.OverflowError => unreachable,
        };
        return r;
    }

    pub fn deinit(r: *GlyphRemapper, a: Allocator) void {
        r.order.deinit(a);
        a.free(r.slots);
        r.* = .{};
    }

    pub fn clone(r: *const GlyphRemapper, a: Allocator) Allocator.Error!GlyphRemapper {
        var c: GlyphRemapper = .{};
        c.order = try r.order.clone(a);
        c.slots = try a.dupe(u32, r.slots);
        return c;
    }

    inline fn hash(old: u16, mask: usize) usize {
        return (@as(usize, old) *% 0x9e37) & mask;
    }

    /// New id of `old`, null when it was never remapped.
    pub fn get(r: *const GlyphRemapper, old: u16) ?u16 {
        if (r.slots.len == 0) return null;
        const mask = r.slots.len - 1;
        var i = hash(old, mask);
        while (true) : (i = (i + 1) & mask) {
            const s = r.slots[i];
            if (s == 0) return null;
            if (s >> 16 == @as(u32, old) + 1) return @truncate(s);
        }
    }

    /// New id of `old`, assigning the next free id on first use.
    pub fn remap(r: *GlyphRemapper, a: Allocator, old: u16) error{ OutOfMemory, OverflowError }!u16 {
        if (r.get(old)) |n| return n;
        // The Rust remapper counts in u16 and panics when the counter overflows.
        if (r.order.items.len >= 0xffff) return error.OverflowError;
        if ((r.order.items.len + 1) * 2 > r.slots.len) try r.grow(a);
        const new: u16 = @intCast(r.order.items.len);
        try r.order.append(a, old);
        r.insert(old, new);
        return new;
    }

    fn insert(r: *GlyphRemapper, old: u16, new: u16) void {
        const mask = r.slots.len - 1;
        var i = hash(old, mask);
        while (r.slots[i] != 0) i = (i + 1) & mask;
        r.slots[i] = (@as(u32, old) + 1) << 16 | new;
    }

    fn grow(r: *GlyphRemapper, a: Allocator) Allocator.Error!void {
        const n = @max(16, r.slots.len * 2);
        const old_slots = r.slots;
        r.slots = try a.alloc(u32, n);
        @memset(r.slots, 0);
        for (old_slots) |s| if (s != 0) r.insert(@intCast((s >> 16) - 1), @truncate(s));
        a.free(old_slots);
    }

    /// Number of glyphs in the subset (new ids are 0 ..< numGids).
    pub fn numGids(r: *const GlyphRemapper) u16 {
        return @intCast(r.order.items.len);
    }

    /// Old glyph ids in new-id order (`gids()[new] == old`).
    pub fn gids(r: *const GlyphRemapper) []const u16 {
        return r.order.items;
    }
};

// ------------------------------------------------------------- byte helpers

inline fn tagInt(comptime s: *const [4]u8) u32 {
    return std.mem.readInt(u32, s, .big);
}

const T = struct {
    const head = tagInt("head");
    const hhea = tagInt("hhea");
    const hmtx = tagInt("hmtx");
    const maxp = tagInt("maxp");
    const name = tagInt("name");
    const post = tagInt("post");
    const glyf = tagInt("glyf");
    const loca = tagInt("loca");
    const prep = tagInt("prep");
    const fpgm = tagInt("fpgm");
    const cvt = tagInt("cvt ");
    const cff1 = tagInt("CFF ");
    const cff2 = tagInt("CFF2");
};

/// Bounds-checked big-endian reads (null when out of range).
pub fn be16(d: []const u8, off: usize) ?u16 {
    if (off > d.len or d.len - off < 2) return null;
    return std.mem.readInt(u16, d[off..][0..2], .big);
}
pub fn be32(d: []const u8, off: usize) ?u32 {
    if (off > d.len or d.len - off < 4) return null;
    return std.mem.readInt(u32, d[off..][0..4], .big);
}

/// Growable big-endian byte writer.
pub const W = struct {
    buf: std.ArrayList(u8) = .empty,
    a: Allocator,

    pub fn init(a: Allocator) W {
        return .{ .a = a };
    }
    pub fn len(w: *const W) usize {
        return w.buf.items.len;
    }
    pub fn u8_(w: *W, v: u8) Allocator.Error!void {
        try w.buf.append(w.a, v);
    }
    pub fn u16_(w: *W, v: u16) Allocator.Error!void {
        var b: [2]u8 = undefined;
        std.mem.writeInt(u16, &b, v, .big);
        try w.buf.appendSlice(w.a, &b);
    }
    pub fn i16_(w: *W, v: i16) Allocator.Error!void {
        try w.u16_(@bitCast(v));
    }
    pub fn u32_(w: *W, v: u32) Allocator.Error!void {
        var b: [4]u8 = undefined;
        std.mem.writeInt(u32, &b, v, .big);
        try w.buf.appendSlice(w.a, &b);
    }
    pub fn bytes(w: *W, b: []const u8) Allocator.Error!void {
        try w.buf.appendSlice(w.a, b);
    }
    pub fn alignTo(w: *W, n: usize) Allocator.Error!void {
        while (w.buf.items.len % n != 0) try w.buf.append(w.a, 0);
    }
};

// --------------------------------------------------------------------- face

const Face = struct {
    data: []const u8,
    /// Offset of the table directory.
    dir: usize,
    num_tables: u16,

    fn parse(data: []const u8, index: u32) Error!Face {
        var magic = be32(data, 0) orelse return error.UnknownKind;
        var dir: usize = 0;
        if (magic == tagInt("ttcf")) {
            dir = be32(data, 12 + 4 * @as(usize, index)) orelse return error.MalformedFont;
            magic = be32(data, dir) orelse return error.MalformedFont;
            if (magic == tagInt("ttcf")) return error.MalformedFont;
            if (!isSingle(magic)) return error.MalformedFont;
        } else if (!isSingle(magic)) return error.UnknownKind;
        const n = be16(data, dir + 4) orelse return error.MalformedFont;
        if (dir + 12 + @as(usize, n) * 16 > data.len) return error.MalformedFont;
        return .{ .data = data, .dir = dir, .num_tables = n };
    }

    fn isSingle(m: u32) bool {
        return m == 0x00010000 or m == tagInt("true") or m == tagInt("OTTO");
    }

    fn table(f: *const Face, tag: u32) ?[]const u8 {
        var i: usize = 0;
        while (i < f.num_tables) : (i += 1) {
            const rec = f.dir + 12 + i * 16;
            if (be32(f.data, rec).? != tag) continue;
            const off: usize = be32(f.data, rec + 8).?;
            const len: usize = be32(f.data, rec + 12).?;
            if (off > f.data.len or len > f.data.len - off) return null;
            return f.data[off..][0..len];
        }
        return null;
    }
};

// ------------------------------------------------------------------ context

const Kind = enum { truetype, cff, cff2 };

const Table = struct { tag: u32, data: []const u8 };

/// maxp v1.0 fields written for instanced (`interjected`) fonts.
const MaxpData = struct {
    max_points: u16 = 0,
    max_contours: u16 = 0,
    max_composite_points: u16 = 0,
    max_composite_contours: u16 = 0,
    max_zones: u16 = 1,
    max_twilight_points: u16 = 0,
    max_storage: u16 = 0,
    max_function_defs: u16 = 0,
    max_instruction_defs: u16 = 0,
    max_stack_elements: u16 = 0,
    max_size_of_instructions: u16 = 0,
    max_component_elements: u16 = 0,
    max_component_depth: u16 = 1,
};

const Metric = struct { adv: u16, lsb: i16 };

const Ctx = struct {
    a: Allocator,
    face: Face,
    mapper: GlyphRemapper,
    kind: Kind,
    /// Non-null: draw glyphs through this instance and re-encode them as simple glyf glyphs.
    inst: ?*const ttf.Font,
    tables: std.ArrayList(Table) = .empty,
    long_loca: bool = false,
    custom_maxp: ?MaxpData = null,
    custom_hmtx: ?[]const Metric = null,

    fn push(c: *Ctx, tag: u32, data: []const u8) Error!void {
        try c.tables.append(c.a, .{ .tag = tag, .data = data });
    }

    fn process(c: *Ctx, tag: u32) Error!void {
        const data = c.face.table(tag) orelse return;
        switch (tag) {
            T.glyf => try glyfSubset(c),
            T.cff1 => if (ttf.enable_cff) try c.push(T.cff1, try cff.subset(c.a, data, &c.mapper)) else return error.Unimplemented,
            T.cff2 => if (can_instance) try cff2Subset(c) else return error.Unimplemented,
            T.head => try headSubset(c, data),
            T.hmtx => try hmtxSubset(c, data),
            T.maxp => try maxpSubset(c, data),
            T.name => try nameSubset(c, data),
            T.post => try postSubset(c, data),
            else => try c.push(tag, data),
        }
    }
};

/// A subset font program.
pub const Subset = struct {
    /// The complete subset OpenType font (owned by the caller's allocator).
    data: []u8,
    /// `.truetype`: embed `data` as /FontFile2 (CIDFontType2, /CIDToGIDMap /Identity) — also
    /// the result for CFF2 and instanced variable fonts. `.cff`: embed `cff` as /FontFile3
    /// with /Subtype /CIDFontType0C (CIDFontType0).
    flavor: Flavor,
    /// `.cff` only: the bare `CFF ` table inside `data` (empty otherwise).
    cff: []const u8 = &.{},

    pub fn deinit(s: *Subset, a: Allocator) void {
        a.free(s.data);
        s.* = undefined;
    }

    /// The bytes to embed in the PDF font file stream (FontFile2 or FontFile3).
    pub fn program(s: *const Subset) []const u8 {
        return if (s.flavor == .cff) s.cff else s.data;
    }
};

/// Subsets face `face_index` of `data` (sfnt or TTC) to the glyphs of `mapper`, instanced at
/// the user-space axis values `variations` (empty for static fonts / the default instance;
/// same semantics as `subset_with_variations` in the Rust crate). `mapper` is not modified:
/// composite components are added to an internal copy (so `mapper.get(gid)` stays the CID).
pub fn subset(a: Allocator, data: []const u8, face_index: u32, variations: []const ttf.AxisValue, mapper: *const GlyphRemapper) Error!Subset {
    var inst: ?ttf.Font = null;
    if (ttf.Font.init(data, face_index)) |base| {
        inst = base.withVariations(variations);
    } else |_| {}
    return subsetImpl(a, data, face_index, if (inst) |*f| f else null, mapper);
}

/// Like `subset`, for a bm-render `ttf.Font` whose variation coordinates (`withVariations` /
/// a collection instance) select the instance. `face_index` must be the index the font was
/// created with (0 for a plain .ttf/.otf).
pub fn subsetFont(a: Allocator, font: *const ttf.Font, face_index: u32, mapper: *const GlyphRemapper) Error!Subset {
    return subsetImpl(a, font.data, face_index, font, mapper);
}

fn subsetImpl(a: Allocator, data: []const u8, face_index: u32, font: ?*const ttf.Font, mapper: *const GlyphRemapper) Error!Subset {
    var arena_state = std.heap.ArenaAllocator.init(a);
    defer arena_state.deinit();
    const ar = arena_state.allocator();

    const face = try Face.parse(data, face_index);
    const kind: Kind = if (face.table(T.glyf) != null)
        .truetype
    else if (face.table(T.cff1) != null)
        .cff
    else if (face.table(T.cff2) != null)
        .cff2
    else
        return error.UnknownKind;

    var c: Ctx = .{ .a = ar, .face = face, .mapper = try mapper.clone(ar), .kind = kind, .inst = null };
    if (c.mapper.numGids() == 0) _ = try c.mapper.remap(ar, 0);

    if (kind == .truetype) try glyfClosure(&c);
    switch (kind) {
        .cff => {},
        // TrueType: only instance when the location is not the default one.
        .truetype => if (font) |f| {
            if (ttf.enable_variations and f.varied) c.inst = f;
        },
        // CFF2: always instance (converted to TrueType).
        .cff2 => {
            const f = font orelse return error.MalformedFont;
            if (!ttf.enable_cff) return error.Unimplemented;
            c.inst = f;
        },
    }

    switch (kind) {
        .truetype => {
            try c.process(T.glyf);
            if (c.inst == null) {
                try c.process(T.cvt);
                try c.process(T.fpgm);
                try c.process(T.prep);
            }
        },
        .cff => try c.process(T.cff1),
        .cff2 => try c.process(T.cff2),
    }
    try c.process(T.head);
    try c.process(T.hmtx);
    try c.process(T.maxp);
    try c.process(T.name);
    try c.process(T.post);

    const flavor: Flavor = if (kind == .cff) .cff else .truetype;
    return construct(a, &c, flavor);
}

fn checksum(data: []const u8) u32 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 4) {
        var b: [4]u8 = .{ 0, 0, 0, 0 };
        const n = @min(4, data.len - i);
        @memcpy(b[0..n], data[i..][0..n]);
        sum +%= std.mem.readInt(u32, &b, .big);
    }
    return sum;
}

fn construct(a: Allocator, c: *Ctx, flavor: Flavor) Error!Subset {
    const tables = c.tables.items;
    // insertion sort by tag (at most ~12 tables; avoids pulling in std.sort)
    for (1..tables.len) |i| {
        const t = tables[i];
        var j = i;
        while (j > 0 and tables[j - 1].tag > t.tag) : (j -= 1) tables[j] = tables[j - 1];
        tables[j] = t;
    }
    const count: u16 = @intCast(tables.len);
    var total: usize = 12 + tables.len * 16;
    for (tables) |t| total += (t.data.len + 3) & ~@as(usize, 3);

    const out = try a.alloc(u8, total);
    errdefer a.free(out);
    @memset(out, 0);
    std.mem.writeInt(u32, out[0..4], if (flavor == .cff) tagInt("OTTO") else 0x00010000, .big);
    const es: u16 = if (count == 0) 0 else std.math.log2_int(u16, count);
    const sr: u16 = (@as(u16, 1) << @intCast(es)) *% 16;
    std.mem.writeInt(u16, out[4..6], count, .big);
    std.mem.writeInt(u16, out[6..8], sr, .big);
    std.mem.writeInt(u16, out[8..10], es, .big);
    std.mem.writeInt(u16, out[10..12], count *% 16 -% sr, .big);

    var adjust_at: ?usize = null;
    var cff_slice: []const u8 = &.{};
    var off: usize = 12 + tables.len * 16;
    for (tables, 0..) |t, i| {
        const rec = out[12 + i * 16 ..][0..16];
        @memcpy(out[off..][0..t.data.len], t.data);
        const body = out[off..][0..t.data.len];
        if (t.tag == T.head) {
            @memset(body[8..12], 0);
            adjust_at = off + 8;
        }
        if (t.tag == T.cff1) cff_slice = body;
        std.mem.writeInt(u32, rec[0..4], t.tag, .big);
        std.mem.writeInt(u32, rec[4..8], checksum(body), .big);
        std.mem.writeInt(u32, rec[8..12], @intCast(off), .big);
        std.mem.writeInt(u32, rec[12..16], @intCast(t.data.len), .big);
        off += (t.data.len + 3) & ~@as(usize, 3);
    }
    if (adjust_at) |p| std.mem.writeInt(u32, out[p..][0..4], 0xB1B0AFBA -% checksum(out), .big);
    return .{ .data = out, .flavor = flavor, .cff = cff_slice };
}

// --------------------------------------------------------------------- glyf

const GlyfTable = struct {
    loca: []const u8,
    glyf: []const u8,
    long: bool,

    fn init(face: *const Face) ?GlyfTable {
        const loca = face.table(T.loca) orelse return null;
        const glyf = face.table(T.glyf) orelse return null;
        const head = face.table(T.head) orelse return null;
        const long = be16(head, 50) orelse return null;
        return .{ .loca = loca, .glyf = glyf, .long = long != 0 };
    }

    fn glyphData(t: *const GlyfTable, id: u16) ?[]const u8 {
        const n: usize = id;
        var from: usize = undefined;
        var to: usize = undefined;
        if (t.long) {
            from = be32(t.loca, 4 * n) orelse return null;
            to = be32(t.loca, 4 * n + 4) orelse return null;
        } else {
            from = 2 * @as(usize, be16(t.loca, 2 * n) orelse return null);
            to = 2 * @as(usize, be16(t.loca, 2 * n + 2) orelse return null);
        }
        if (from > to or to > t.glyf.len) return null;
        return t.glyf[from..to];
    }
};

const ARG_1_AND_2_ARE_WORDS: u16 = 0x0001;
const WE_HAVE_A_SCALE: u16 = 0x0008;
const MORE_COMPONENTS: u16 = 0x0020;
const WE_HAVE_AN_X_AND_Y_SCALE: u16 = 0x0040;
const WE_HAVE_A_TWO_BY_TWO: u16 = 0x0080;
const WE_HAVE_INSTRUCTIONS: u16 = 0x0100;

/// Size of the arguments + transform following a component's flags and glyph index.
fn componentArgSize(flags: u16) usize {
    var n: usize = if (flags & ARG_1_AND_2_ARE_WORDS != 0) 4 else 2;
    if (flags & WE_HAVE_A_SCALE != 0) {
        n += 2;
    } else if (flags & WE_HAVE_AN_X_AND_Y_SCALE != 0) {
        n += 4;
    } else if (flags & WE_HAVE_A_TWO_BY_TWO != 0) {
        n += 8;
    }
    return n;
}

/// Adds the components of every composite glyph to the remapper (in the Rust crate's order:
/// a work stack seeded with the remapped glyphs, popped from the back).
fn glyfClosure(c: *Ctx) Error!void {
    const table = GlyfTable.init(&c.face) orelse return error.MalformedFont;
    var work: std.ArrayList(u16) = .empty;
    try work.appendSlice(c.a, c.mapper.gids());
    while (work.pop()) |glyph| {
        _ = try c.mapper.remap(c.a, glyph);
        const g = table.glyphData(glyph) orelse continue;
        if (g.len == 0) continue;
        const nc: i16 = @bitCast(be16(g, 0) orelse return error.MalformedFont);
        if (nc >= 0) continue;
        // `component_glyphs` needs the 10-byte header, then yields components until the data
        // runs out or MORE_COMPONENTS is clear.
        if (g.len < 10) return error.MalformedFont;
        var off: usize = 10;
        while (true) {
            const flags = be16(g, off) orelse break;
            const comp = be16(g, off + 2) orelse break;
            off += 4 + componentArgSize(flags);
            if (c.mapper.get(comp) == null) try work.append(c.a, comp);
            if (flags & MORE_COMPONENTS == 0) break;
        }
    }
}

fn remapComponentGlyph(c: *Ctx, g: []const u8) Error![]const u8 {
    var w = W.init(c.a);
    if (g.len < 10) return error.MalformedFont;
    try w.bytes(g[0..10]);
    var off: usize = 10;
    while (true) {
        const flags = be16(g, off) orelse return error.MalformedFont;
        const old = be16(g, off + 2) orelse return error.MalformedFont;
        const new = c.mapper.get(old) orelse return error.MalformedFont;
        try w.u16_(flags);
        try w.u16_(new);
        off += 4;
        const n = componentArgSize(flags);
        if (off + n > g.len) return error.MalformedFont;
        try w.bytes(g[off..][0..n]);
        off += n;
        if (flags & MORE_COMPONENTS == 0) {
            if (flags & WE_HAVE_INSTRUCTIONS != 0) try w.bytes(g[off..]);
            break;
        }
    }
    return w.buf.items;
}

fn glyfSubset(c: *Ctx) Error!void {
    const table = GlyfTable.init(&c.face) orelse return error.MalformedFont;
    const n = c.mapper.numGids();
    const entries = try c.a.alloc([]const u8, n);
    if (!can_instance) {
        for (c.mapper.gids(), entries) |old, *e| e.* = table.glyphData(old) orelse return error.MalformedFont;
    } else if (c.inst) |inst| {
        try interjectAll(c, inst, entries);
    } else {
        for (c.mapper.gids(), entries) |old, *e| e.* = table.glyphData(old) orelse return error.MalformedFont;
    }
    try writeGlyfLoca(c, entries);
}

/// CFF2 fonts are always converted to TrueType by drawing them at the instance location.
fn cff2Subset(c: *Ctx) Error!void {
    const inst = c.inst orelse return error.MalformedFont;
    const entries = try c.a.alloc([]const u8, c.mapper.numGids());
    try interjectAll(c, inst, entries);
    try writeGlyfLoca(c, entries);
}

fn writeGlyfLoca(c: *Ctx, entries: [][]const u8) Error!void {
    var size: usize = 0;
    for (entries) |*e| {
        if (e.len == 0) continue;
        const nc: i16 = @bitCast(be16(e.*, 0) orelse return error.MalformedFont);
        if (nc < 0) e.* = try remapComponentGlyph(c, e.*);
        size += e.len + (e.len & 1);
    }
    c.long_loca = size > 2 * 0xffff;

    var glyf = W.init(c.a);
    var loca = W.init(c.a);
    for (entries) |e| {
        try writeLoca(c, &loca, glyf.len());
        try glyf.bytes(e);
        if (!c.long_loca) try glyf.alignTo(2);
    }
    try writeLoca(c, &loca, glyf.len());
    try c.push(T.loca, loca.buf.items);
    try c.push(T.glyf, glyf.buf.items);
}

fn writeLoca(c: *Ctx, loca: *W, off: usize) Error!void {
    if (c.long_loca) try loca.u32_(@intCast(off)) else try loca.u16_(@intCast(off / 2));
}

// ---------------------------------------------------- instancing (interjector)

fn interjectAll(c: *Ctx, inst: *const ttf.Font, entries: [][]const u8) Error!void {
    var maxp: MaxpData = .{};
    const metrics = try c.a.alloc(Metric, entries.len);
    var path: PathRec = .{ .a = c.a };
    for (c.mapper.gids(), entries, metrics) |old, *e, *m| {
        const r = try interject(c.a, inst, &maxp, old, &path);
        e.* = r.data;
        m.* = .{ .adv = r.adv, .lsb = r.lsb };
    }
    c.custom_maxp = maxp;
    c.custom_hmtx = metrics;
}

const El = union(enum) {
    move: [2]f64,
    line: [2]f64,
    quad: [4]f64,
    close,
};

/// Records an outline (bm-render path sink) as a kurbo-style element list, converting cubics
/// to quadratics exactly like the Rust interjector (`CubicBez::to_quads(0.025)`).
const PathRec = struct {
    a: Allocator,
    els: std.ArrayList(El) = .empty,
    last_move: [2]f32 = .{ 0, 0 },
    last: [2]f32 = .{ 0, 0 },
    oom: bool = false,

    fn add(p: *PathRec, e: El) void {
        p.els.append(p.a, e) catch {
            p.oom = true;
        };
    }
    pub fn moveTo(p: *PathRec, x: f32, y: f32) void {
        p.add(.{ .move = .{ x, y } });
        p.last_move = .{ x, y };
        p.last = .{ x, y };
    }
    pub fn lineTo(p: *PathRec, x: f32, y: f32) void {
        p.add(.{ .line = .{ x, y } });
        p.last = .{ x, y };
    }
    pub fn quadTo(p: *PathRec, cx: f32, cy: f32, x: f32, y: f32) void {
        p.add(.{ .quad = .{ cx, cy, x, y } });
        p.last = .{ x, y };
    }
    pub fn cubicTo(p: *PathRec, ax: f32, ay: f32, bx: f32, by: f32, x: f32, y: f32) void {
        const p0: [2]f64 = .{ p.last[0], p.last[1] };
        const p1: [2]f64 = .{ ax, ay };
        const p2: [2]f64 = .{ bx, by };
        const p3: [2]f64 = .{ x, y };
        // kurbo: n = ceil((err / (432 * acc^2))^(1/6)), err = |(3p2 - p3) - (3p1 - p0)|^2
        const accuracy: f64 = 0.025;
        const max_hypot2 = 432.0 * accuracy * accuracy;
        const ex = (3.0 * p2[0] - p3[0]) - (3.0 * p1[0] - p0[0]);
        const ey = (3.0 * p2[1] - p3[1]) - (3.0 * p1[1] - p0[1]);
        const err = ex * ex + ey * ey;
        // ceil(x^(1/6)) = the smallest n >= 1 with n^6 >= x (no pow/log/exp code needed)
        const ratio = err / max_hypot2;
        var n: usize = 1;
        while (n < 1000 and ratio == ratio) : (n += 1) {
            const nf: f64 = @floatFromInt(n);
            if (nf * nf * nf * nf * nf * nf >= ratio) break;
        }
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const t0 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n));
            const t1 = @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(n));
            // subsegment(t0..t1)
            const s0 = cubicEval(p0, p1, p2, p3, t0);
            const s3 = cubicEval(p0, p1, p2, p3, t1);
            const d0 = derivEval(p0, p1, p2, p3, t0);
            const d1 = derivEval(p0, p1, p2, p3, t1);
            const scale = (t1 - t0) * (1.0 / 3.0);
            const s1: [2]f64 = .{ s0[0] + scale * d0[0], s0[1] + scale * d0[1] };
            const s2: [2]f64 = .{ s3[0] - scale * d1[0], s3[1] - scale * d1[1] };
            const q1x = ((3.0 * s1[0] - s0[0]) + (3.0 * s2[0] - s3[0])) / 4.0;
            const q1y = ((3.0 * s1[1] - s0[1]) + (3.0 * s2[1] - s3[1])) / 4.0;
            // The Rust pen goes through f32 `quad_to`.
            p.quadTo(@floatCast(q1x), @floatCast(q1y), @floatCast(s3[0]), @floatCast(s3[1]));
        }
    }
    pub fn close(p: *PathRec) void {
        p.add(.close);
        p.last = p.last_move;
    }
};

/// skrifa draws a varied glyf outline in 26.6 fixed point: every point is the unscaled
/// coordinate plus its 16.16 delta floored to 1/64, and the path is emitted in FreeType's
/// `FT_Outline_Decompose` order with exact midpoints for implied on-curve points. bm-render's
/// varied outline is f32. To reproduce skrifa's path (which decides which implied points
/// write-fonts drops and how coordinates round), recover every source point of the glyph from
/// the recorded path using the glyph's on/off-curve flags, snap it to 1/64 and re-emit the
/// contour like skrifa. When the structure cannot be matched (malformed glyph, components
/// bm-render skips), all coordinates are just snapped.
fn skrifaPath(a: Allocator, f: *const ttf.Font, gid: u16, path: *PathRec) Error!void {
    var flags: std.ArrayList(bool) = .empty;
    var ends: std.ArrayList(u32) = .empty;
    var budget: u32 = 256;
    var out: std.ArrayList(El) = .empty;
    const els = path.els.items;
    var ok = try collectContours(a, f, gid, 0, &budget, &flags, &ends);
    var pts: std.ArrayList([2]f64) = .empty;
    if (ok) {
        var e: usize = 0;
        var fstart: usize = 0;
        for (ends.items) |fend| {
            const fl = flags.items[fstart..fend];
            fstart = fend;
            if (e >= els.len) {
                ok = false;
                break;
            }
            var ee = e + 1;
            while (ee < els.len and els[ee] != .move) ee += 1;
            try pts.resize(a, fl.len);
            if (!absorbContour(fl, els[e..ee], pts.items)) {
                ok = false;
                break;
            }
            for (pts.items) |*p| p.* = .{ snap64(p[0]), snap64(p[1]) };
            try emitFreeType(a, fl, pts.items, &out);
            e = ee;
        }
        if (e != els.len) ok = false;
    }
    if (ok) {
        path.els.clearRetainingCapacity();
        try path.els.appendSlice(path.a, out.items);
        return;
    }
    for (els) |*el| switch (el.*) {
        .move, .line => |*p| for (p) |*v| {
            v.* = snap64(v.*);
        },
        .quad => |*p| for (p) |*v| {
            v.* = snap64(v.*);
        },
        .close => {},
    };
}

fn snap64(v: f64) f64 {
    // + 1/100 of a 26.6 step: absorbs the f32 noise of bm-render's deltas around exact steps
    return @floor(std.math.clamp(v, -1e9, 1e9) * 64.0 + 0.01) / 64.0;
}

/// On/off-curve flags of the contours of `gid` in the order `ttf.Font.outline` draws them
/// (composites expanded with the same depth / component budget). `ends` gets the end index
/// (exclusive) in `flags` of every contour. False when the data is malformed or contains a
/// contour bm-render does not draw.
fn collectContours(a: Allocator, f: *const ttf.Font, gid: u16, depth: u32, budget: *u32, flags: *std.ArrayList(bool), ends: *std.ArrayList(u32)) Error!bool {
    const g = f.glyphData(gid);
    if (g.len < 10) return true;
    const nc: i16 = @bitCast(be16(g, 0).?);
    if (nc > 0) {
        const n: usize = @intCast(nc);
        const npts = @as(usize, be16(g, 10 + (n - 1) * 2) orelse return false) + 1;
        const ins = be16(g, 10 + n * 2) orelse return false;
        var p: usize = 12 + n * 2 + ins;
        const base = flags.items.len;
        while (flags.items.len - base < npts) {
            if (p >= g.len) return false;
            const fl = g[p];
            p += 1;
            var rep: usize = 1;
            if (fl & 8 != 0) {
                if (p >= g.len) return false;
                rep += g[p];
                p += 1;
            }
            for (0..rep) |_| if (flags.items.len - base < npts) try flags.append(a, fl & 1 != 0);
        }
        var prev: usize = 0;
        for (0..n) |ci| {
            const end = @as(usize, be16(g, 10 + ci * 2).?) + 1;
            if (end <= prev or end > npts) return false;
            // a lone off-curve point draws nothing in bm-render
            if (end - prev == 1 and !flags.items[base + prev]) return false;
            try ends.append(a, @intCast(base + end));
            prev = end;
        }
        return true;
    }
    if (nc == 0 or depth >= 8) return true;
    var off: usize = 10;
    while (off + 4 <= g.len) {
        if (budget.* == 0) break;
        budget.* -= 1;
        const cf = be16(g, off).?;
        const child = be16(g, off + 2).?;
        off += 4 + componentArgSize(cf);
        if (!try collectContours(a, f, child, depth + 1, budget, flags, ends)) return false;
        if (cf & MORE_COMPONENTS == 0) break;
    }
    return true;
}

/// Recovers the points of one contour (flags `fl`) from the elements bm-render drew for it
/// (`move ... close`, the walk of ttf.simpleOutline / variations.emitContours).
fn absorbContour(fl: []const bool, els: []const El, pts: [][2]f64) bool {
    if (els.len < 2 or els[0] != .move or els[els.len - 1] != .close) return false;
    var e: usize = 1;
    var started = false;
    var first_off = false;
    var pending: ?usize = null;
    const Take = struct {
        fn quad(es: []const El, i: *usize) ?[4]f64 {
            if (i.* >= es.len or es[i.*] != .quad) return null;
            i.* += 1;
            return es[i.* - 1].quad;
        }
    };
    for (fl, 0..) |on, k| {
        if (!started) {
            if (on) {
                pts[k] = els[0].move;
            } else if (k == 0) {
                first_off = true;
                continue;
            } else pending = k;
            started = true;
        } else if (on) {
            if (pending) |pk| {
                const q = Take.quad(els, &e) orelse return false;
                pts[pk] = q[0..2].*;
                pts[k] = q[2..4].*;
            } else {
                if (e >= els.len or els[e] != .line) return false;
                pts[k] = els[e].line;
                e += 1;
            }
            pending = null;
        } else {
            if (pending) |pk| {
                const q = Take.quad(els, &e) orelse return false;
                pts[pk] = q[0..2].*;
            }
            pending = k;
        }
    }
    if (!started) return false;
    if (first_off) {
        if (pending) |pk| {
            const q = Take.quad(els, &e) orelse return false;
            pts[pk] = q[0..2].*;
        }
        pending = 0;
    }
    if (pending) |pk| {
        const q = Take.quad(els, &e) orelse return false;
        pts[pk] = q[0..2].*;
    }
    return e == els.len - 1;
}

/// One contour in `FT_Outline_Decompose` order (as skrifa draws it), exact midpoints.
fn emitFreeType(a: Allocator, fl: []const bool, pts: []const [2]f64, out: *std.ArrayList(El)) Error!void {
    const mid = struct {
        fn f(p: [2]f64, q: [2]f64) [2]f64 {
            return .{ (p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5 };
        }
    }.f;
    const last: isize = @intCast(fl.len - 1);
    var limit = last;
    var start: [2]f64 = undefined;
    var p: isize = 0;
    if (fl[0]) {
        start = pts[0];
    } else {
        if (fl[@intCast(last)]) {
            start = pts[@intCast(last)];
            limit -= 1;
        } else start = mid(pts[0], pts[@intCast(last)]);
        p = -1;
    }
    try out.append(a, .{ .move = start });
    var closed = false;
    outer: while (p < limit) {
        p += 1;
        if (fl[@intCast(p)]) {
            try out.append(a, .{ .line = pts[@intCast(p)] });
            continue;
        }
        var ctrl = pts[@intCast(p)];
        while (true) {
            if (p < limit) {
                p += 1;
                const v = pts[@intCast(p)];
                if (fl[@intCast(p)]) {
                    try out.append(a, .{ .quad = .{ ctrl[0], ctrl[1], v[0], v[1] } });
                    continue :outer;
                }
                const m = mid(ctrl, v);
                try out.append(a, .{ .quad = .{ ctrl[0], ctrl[1], m[0], m[1] } });
                ctrl = v;
                continue;
            }
            try out.append(a, .{ .quad = .{ ctrl[0], ctrl[1], start[0], start[1] } });
            closed = true;
            break :outer;
        }
    }
    if (!closed) try out.append(a, .{ .line = start });
    try out.append(a, .close);
}

fn cubicEval(p0: [2]f64, p1: [2]f64, p2: [2]f64, p3: [2]f64, t: f64) [2]f64 {
    const mt = 1.0 - t;
    var r: [2]f64 = undefined;
    for (0..2) |k| r[k] = p0[k] * (mt * mt * mt) + (p1[k] * (mt * mt * 3.0) + (p2[k] * (mt * 3.0) + p3[k] * t) * t) * t;
    return r;
}

fn derivEval(p0: [2]f64, p1: [2]f64, p2: [2]f64, p3: [2]f64, t: f64) [2]f64 {
    // deriv = QuadBez(3(p1-p0), 3(p2-p1), 3(p3-p2))
    const mt = 1.0 - t;
    var r: [2]f64 = undefined;
    for (0..2) |k| {
        const q0 = 3.0 * (p1[k] - p0[k]);
        const q1 = 3.0 * (p2[k] - p1[k]);
        const q2 = 3.0 * (p3[k] - p2[k]);
        r[k] = q0 * (mt * mt) + (q1 * (mt * 2.0) + q2 * t) * t;
    }
    return r;
}

/// write-fonts `OtRound` for f64: floor(x + 0.5), saturating like Rust's `as i16`.
fn otRound(v: f64) i16 {
    const r = @floor(v + 0.5);
    if (r != r) return 0;
    return @intFromFloat(std.math.clamp(r, -32768.0, 32767.0));
}

const CurvePoint = struct { x: i16, y: i16, on: bool };
const FPoint = struct { x: f64, y: f64, on: bool };

/// Python's `math.isclose` with the default rel_tol = 1e-9, abs_tol = 0 (write-fonts util).
fn isClose(x: f64, y: f64) bool {
    return @abs(x - y) <= 1e-9 * @max(@abs(x), @abs(y));
}

/// write-fonts `is_implicit_on_curve`: an on-curve point between two off-curve points that
/// sits at their midpoint (exactly before rounding, or after rounding).
fn isImplicitOnCurve(c: []const FPoint, i: usize) bool {
    const p1 = c[i];
    if (!p1.on) return false;
    const p0 = c[if (i == 0) c.len - 1 else i - 1];
    const p2 = c[(i + 1) % c.len];
    if (p0.on or p0.on != p2.on) return false;
    const mx = 0.5 * (p0.x + p2.x);
    const my = 0.5 * (p0.y + p2.y);
    if (isClose(mx, p1.x) and isClose(my, p1.y)) return true;
    const rx = @as(f64, @floatFromInt(otRound(p0.x))) + @as(f64, @floatFromInt(otRound(p2.x)));
    const ry = @as(f64, @floatFromInt(otRound(p0.y))) + @as(f64, @floatFromInt(otRound(p2.y)));
    return rx == @as(f64, @floatFromInt(otRound(p1.x))) * 2 and ry == @as(f64, @floatFromInt(otRound(p1.y))) * 2;
}

fn flushContour(a: Allocator, c: []const FPoint, pts: *std.ArrayList(CurvePoint), ends: *std.ArrayList(u16)) Error!void {
    if (c.len == 0) return;
    for (c, 0..) |p, i| {
        if (isImplicitOnCurve(c, i)) continue;
        try pts.append(a, .{ .x = otRound(p.x), .y = otRound(p.y), .on = p.on });
    }
    if (pts.items.len == 0 or pts.items.len > 0x10000) return error.OverflowError;
    try ends.append(a, @intCast(pts.items.len - 1));
}

const Interjected = struct { adv: u16, lsb: i16, data: []const u8 };

/// Draws `gid` at the instance location and encodes it as a simple glyf glyph, as
/// write-fonts' `SimpleGlyph::from_bezpath` + `dump_table` do.
fn interject(a: Allocator, inst: *const ttf.Font, maxp: *MaxpData, gid: u16, path: *PathRec) Error!Interjected {
    path.els.clearRetainingCapacity();
    path.last = .{ 0, 0 };
    path.last_move = .{ 0, 0 };
    if (gid < inst.num_glyphs) _ = inst.outline(gid, path);
    if (path.oom) return error.OutOfMemory;
    if (gid >= inst.num_glyphs) return error.MalformedFont;
    if (inst.cff.len == 0) try skrifaPath(a, inst, gid, path);
    const adv = inst.advanceWidth(gid);

    // Control box of the (unrounded) path.
    var have = false;
    var x0: f64 = 0;
    var y0: f64 = 0;
    var x1: f64 = 0;
    var y1: f64 = 0;
    var segments = false;
    for (path.els.items) |e| {
        const pts: []const f64 = switch (e) {
            .move => |*p| p,
            .line => |*p| p,
            .quad => |*p| p,
            .close => &.{},
        };
        if (e == .line or e == .quad) segments = true;
        var k: usize = 0;
        while (k + 1 < pts.len) : (k += 2) {
            if (!have) {
                x0 = pts[k];
                x1 = pts[k];
                y0 = pts[k + 1];
                y1 = pts[k + 1];
                have = true;
            } else {
                x0 = @min(x0, pts[k]);
                x1 = @max(x1, pts[k]);
                y0 = @min(y0, pts[k + 1]);
                y1 = @max(y1, pts[k + 1]);
            }
        }
    }
    const bbox = [4]i16{ otRound(x0), otRound(y0), otRound(x1), otRound(y1) };
    const lsb = bbox[0];
    // kurbo `BezPath::is_empty`: no element other than MoveTo / ClosePath.
    if (!segments) return .{ .adv = adv, .lsb = lsb, .data = &.{} };

    // simple_glyphs_from_kurbo: contours of unrounded points; a closing point equal to the
    // move point is removed; implied on-curve points are dropped; then coordinates rounded.
    var pts: std.ArrayList(CurvePoint) = .empty;
    var ends: std.ArrayList(u16) = .empty;
    var cur: std.ArrayList(FPoint) = .empty;
    var open = false;
    for (path.els.items) |e| switch (e) {
        .move => |p| {
            if (open) try flushContour(a, cur.items, &pts, &ends);
            cur.clearRetainingCapacity();
            try cur.append(a, .{ .x = p[0], .y = p[1], .on = true });
            open = true;
        },
        .line => |p| {
            if (!open) return error.MalformedFont;
            try cur.append(a, .{ .x = p[0], .y = p[1], .on = true });
        },
        .quad => |p| {
            if (!open) return error.MalformedFont;
            try cur.append(a, .{ .x = p[0], .y = p[1], .on = false });
            try cur.append(a, .{ .x = p[2], .y = p[3], .on = true });
        },
        .close => {
            if (!open) return error.MalformedFont;
            const c = cur.items;
            if (c.len > 1 and c[c.len - 1].x == c[0].x and c[c.len - 1].y == c[0].y) _ = cur.pop();
        },
    };
    if (open) try flushContour(a, cur.items, &pts, &ends);

    const ncont: u16 = @intCast(ends.items.len);
    maxp.max_points = @max(maxp.max_points, @as(u16, @intCast(pts.items.len)));
    maxp.max_contours = @max(maxp.max_contours, ncont);
    if (ncont == 0) return .{ .adv = adv, .lsb = lsb, .data = &.{} };

    var w = W.init(a);
    try w.i16_(@intCast(ncont));
    for (bbox) |v| try w.i16_(v);
    for (ends.items) |e| try w.u16_(e);
    try w.u16_(0); // instruction length
    // flags, x deltas, y deltas
    const flags = try a.alloc(u8, pts.items.len);
    var xs = W.init(a);
    var ys = W.init(a);
    var lx: i16 = 0;
    var ly: i16 = 0;
    for (pts.items, flags) |p, *fl| {
        const dx = p.x -% lx;
        const dy = p.y -% ly;
        lx = p.x;
        ly = p.y;
        var f: u8 = if (p.on) 0x01 else 0;
        f |= try deltaFlag(dx, 0x02, 0x10, &xs);
        f |= try deltaFlag(dy, 0x04, 0x20, &ys);
        fl.* = f;
    }
    // RepeatableFlag::iter_from_flags: runs of >= 3 equal flags use REPEAT (at most 256 per run)
    var i: usize = 0;
    while (i < flags.len) {
        var j = i + 1;
        while (j < flags.len and flags[j] == flags[i] and j - i < 256) j += 1;
        const run = j - i;
        if (run >= 3) {
            try w.u8_(flags[i] | 0x08);
            try w.u8_(@intCast(run - 1));
        } else {
            for (0..run) |_| try w.u8_(flags[i]);
        }
        i = j;
    }
    try w.bytes(xs.buf.items);
    try w.bytes(ys.buf.items);
    try w.alignTo(2);
    return .{ .adv = adv, .lsb = lsb, .data = w.buf.items };
}

fn deltaFlag(d: i16, short: u8, same_or_pos: u8, out: *W) Error!u8 {
    if (d == 0) return same_or_pos;
    if (d >= -255 and d <= -1) {
        try out.u8_(@intCast(-@as(i32, d)));
        return short;
    }
    if (d >= 1 and d <= 255) {
        try out.u8_(@intCast(d));
        return short | same_or_pos;
    }
    try out.i16_(d);
    return 0;
}

// ---------------------------------------------------------------- head/hmtx

fn headSubset(c: *Ctx, head: []const u8) Error!void {
    if (head.len < 52) return error.MalformedFont;
    const h = try c.a.dupe(u8, head);
    h[50] = 0;
    h[51] = @intFromBool(c.long_loca);
    try c.push(T.head, h);
}

fn hmtxSubset(c: *Ctx, hmtx: []const u8) Error!void {
    const hhea = c.face.table(T.hhea) orelse return error.MalformedFont;
    var metrics: []const Metric = undefined;
    if (c.inst != null) {
        metrics = c.custom_hmtx orelse return error.SubsetError;
    } else {
        const nh = be16(hhea, 34) orelse return error.MalformedFont;
        if (nh == 0) return error.OverflowError;
        const last_adv = be16(hmtx, 4 * (@as(usize, nh) - 1)) orelse return error.MalformedFont;
        const m = try c.a.alloc(Metric, c.mapper.numGids());
        for (c.mapper.gids(), m) |old, *e| {
            if (old < nh) {
                e.* = .{
                    .adv = be16(hmtx, @as(usize, old) * 4) orelse return error.MalformedFont,
                    .lsb = @bitCast(be16(hmtx, @as(usize, old) * 4 + 2) orelse return error.MalformedFont),
                };
            } else {
                const off = @as(usize, nh) * 4 + (@as(usize, old) - nh) * 2;
                e.* = .{ .adv = last_adv, .lsb = @bitCast(be16(hmtx, off) orelse return error.MalformedFont) };
            }
        }
        metrics = m;
    }
    if (metrics.len == 0) return error.OverflowError;
    // Trailing glyphs that share the last advance only store their lsb.
    var last_idx: usize = metrics.len - 1;
    const last_adv = metrics[last_idx].adv;
    var k = metrics.len - 1;
    while (k > 0) {
        k -= 1;
        if (metrics[k].adv == last_adv) last_idx -= 1 else break;
    }
    var w = W.init(c.a);
    for (metrics, 0..) |m, i| {
        if (i <= last_idx) try w.u16_(m.adv);
        try w.i16_(m.lsb);
    }
    try c.push(T.hmtx, w.buf.items);

    if (hhea.len < 2) return error.MalformedFont;
    var hw = W.init(c.a);
    try hw.bytes(hhea[0 .. hhea.len - 2]);
    try hw.u16_(@intCast(last_idx + 1));
    try c.push(T.hhea, hw.buf.items);
}

fn maxpSubset(c: *Ctx, maxp: []const u8) Error!void {
    if (maxp.len < 6) return error.MalformedFont;
    const truetype = c.kind != .cff;
    var w = W.init(c.a);
    try w.u32_(if (truetype) 0x00010000 else 0x00005000);
    try w.u16_(c.mapper.numGids());
    if (truetype) {
        if (c.custom_maxp) |m| {
            for ([_]u16{
                m.max_points,             m.max_contours,             m.max_composite_points,
                m.max_composite_contours, m.max_zones,                m.max_twilight_points,
                m.max_storage,            m.max_function_defs,        m.max_instruction_defs,
                m.max_stack_elements,     m.max_size_of_instructions, m.max_component_elements,
                m.max_component_depth,
            }) |v| try w.u16_(v);
        } else {
            try w.bytes(maxp[6..]);
        }
    }
    try c.push(T.maxp, w.buf.items);
}

// --------------------------------------------------------------------- name

fn nameSubset(c: *Ctx, name: []const u8) Error!void {
    const version = be16(name, 0) orelse return error.MalformedFont;
    if (version != 0) return c.push(T.name, name);
    const count = be16(name, 2) orelse return error.MalformedFont;
    const storage_off = be16(name, 4) orelse return error.MalformedFont;
    if (6 + @as(usize, count) * 12 > name.len) return error.MalformedFont;
    if (storage_off > name.len) return error.MalformedFont;
    const storage = name[storage_off..];

    const Rec = struct { r: [5]u16, len: u16, off: u16 };
    var recs: std.ArrayList(Rec) = .empty;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const p = 6 + i * 12;
        const pid = be16(name, p).?;
        const eid = be16(name, p + 2).?;
        const nid = be16(name, p + 6).?;
        const unicode = pid == 0 or (pid == 3 and (eid == 0 or eid == 1 or eid == 10));
        const keep = nid <= 14 and nid != 10;
        if (!(unicode and keep)) continue;
        try recs.append(c.a, .{ .r = .{ pid, eid, be16(name, p + 4).?, nid, be16(name, p + 8).? }, .len = be16(name, p + 8).?, .off = be16(name, p + 10).? });
    }
    var store = W.init(c.a);
    // dedup by content: first occurrence keeps its new offset
    var seen: std.ArrayList(struct { s: []const u8, off: u16 }) = .empty;
    var cur: u16 = 0;
    for (recs.items) |*r| {
        const end = @as(usize, r.off) + r.len;
        if (end > storage.len) return error.SubsetError;
        const s = storage[r.off..end];
        var found: ?u16 = null;
        for (seen.items) |e| if (std.mem.eql(u8, e.s, s)) {
            found = e.off;
            break;
        };
        if (found) |f| {
            r.off = f;
        } else {
            try store.bytes(s);
            try seen.append(c.a, .{ .s = s, .off = cur });
            r.off = cur;
            cur +%= r.len;
        }
    }
    const n: u16 = @intCast(recs.items.len);
    var w = W.init(c.a);
    try w.u16_(0);
    try w.u16_(n);
    try w.u16_(6 +% n *% 12);
    for (recs.items) |r| {
        for (r.r) |v| try w.u16_(v);
        try w.u16_(r.off);
    }
    try w.bytes(store.buf.items);
    try c.push(T.name, w.buf.items);
}

// --------------------------------------------------------------------- post

fn postSubset(c: *Ctx, post: []const u8) Error!void {
    const version = be32(post, 0) orelse return error.MalformedFont;
    if (version != 0x00020000) return c.push(T.post, post);
    if (post.len < 34) return error.MalformedFont;
    const n_idx = be16(post, 32).?;
    const idx_end = 34 + @as(usize, n_idx) * 2;
    if (idx_end > post.len) return error.MalformedFont;
    const names_data = post[idx_end..];

    // all custom names (stops at an empty or truncated name, like the Rust iterator)
    var names: std.ArrayList([]const u8) = .empty;
    var p: usize = 0;
    while (p < names_data.len) {
        const l = names_data[p];
        p += 1;
        if (l == 0 or p + l > names_data.len) break;
        try names.append(c.a, names_data[p..][0..l]);
        p += l;
    }

    var w = W.init(c.a);
    try w.bytes(post[0..32]);
    try w.u16_(c.mapper.numGids());
    var strings = W.init(c.a);
    var string_index: usize = 0;
    for (c.mapper.gids()) |old| {
        if (old >= n_idx) return error.MalformedFont;
        const index = be16(post, 34 + @as(usize, old) * 2).?;
        if (index <= 257) {
            try w.u16_(index);
        } else {
            const ni = index - 258;
            const nm: []const u8 = if (ni < names.items.len) names.items[ni] else &.{};
            if (nm.len > 255 or string_index + 258 > 0xffff) return error.OverflowError;
            try w.u16_(@intCast(string_index + 258));
            try strings.u8_(@intCast(nm.len));
            try strings.bytes(nm);
            string_index += 1;
        }
    }
    try w.bytes(strings.buf.items);
    try c.push(T.post, w.buf.items);
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

test {
    _ = cff;
    _ = @import("subset_tests.zig");
}

test "remapper: first-use order, notdef first" {
    const a = testing.allocator;
    var r = try GlyphRemapper.init(a);
    defer r.deinit(a);
    for ([_]u16{ 3, 39, 8, 3, 10, 2 }) |g| _ = try r.remap(a, g);
    try testing.expectEqualSlices(u16, &.{ 0, 3, 39, 8, 10, 2 }, r.gids());
    try testing.expectEqual(@as(?u16, 2), r.get(39));
    try testing.expectEqual(@as(?u16, null), r.get(4));
    try testing.expectEqual(@as(u16, 6), r.numGids());
    var i: u16 = 100;
    while (i < 1000) : (i += 1) try testing.expectEqual(i - 100 + 6, try r.remap(a, i));
    try testing.expectEqual(@as(?u16, 5), r.get(2));
}

test "malformed CFF returns CFFError" {
    var font: [32]u8 = undefined;
    std.mem.writeInt(u32, font[0..4], 0x4F54544F, .big);
    std.mem.writeInt(u16, font[4..6], 1, .big);
    @memset(font[6..12], 0);
    @memcpy(font[12..16], "CFF ");
    std.mem.writeInt(u32, font[16..20], 0, .big);
    std.mem.writeInt(u32, font[20..24], 28, .big);
    std.mem.writeInt(u32, font[24..28], 4, .big);
    font[28..32].* = .{ 2, 0, 4, 4 };
    var r = try GlyphRemapper.init(testing.allocator);
    defer r.deinit(testing.allocator);
    try testing.expectError(error.CFFError, subset(testing.allocator, &font, 0, &.{}, &r));
}

test "name table: storage offset respected, records filtered and deduplicated" {
    // count 2, both unicode, same string; plus one Mac record that is dropped
    var t: [6 + 3 * 12 + 4 + 4]u8 = undefined;
    std.mem.writeInt(u16, t[0..2], 0, .big);
    std.mem.writeInt(u16, t[2..4], 3, .big);
    std.mem.writeInt(u16, t[4..6], 6 + 3 * 12 + 4, .big);
    const recs = [_][6]u16{ .{ 1, 0, 0, 1, 2, 0 }, .{ 3, 1, 0x409, 0, 4, 0 }, .{ 3, 1, 0x409, 4, 4, 0 } };
    for (recs, 0..) |r, i| for (r, 0..) |v, k| std.mem.writeInt(u16, t[6 + i * 12 + k * 2 ..][0..2], v, .big);
    @memcpy(t[42..46], "BAD!");
    t[46..50].* = .{ 0, 'O', 0, 'K' };
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var c: Ctx = .{ .a = arena.allocator(), .face = undefined, .mapper = .{}, .kind = .truetype, .inst = null };
    try nameSubset(&c, &t);
    const out = c.tables.items[0].data;
    try testing.expectEqual(@as(usize, 6 + 2 * 12 + 4), out.len);
    try testing.expectEqual(@as(u16, 2), be16(out, 2).?);
    try testing.expectEqual(@as(u16, 0), be16(out, 6 + 10).?);
    try testing.expectEqual(@as(u16, 0), be16(out, 6 + 12 + 10).?);
    try testing.expectEqualSlices(u8, &.{ 0, 'O', 0, 'K' }, out[30..]);
}
