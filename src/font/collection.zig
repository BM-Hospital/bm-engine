//! Registered font faces and CSS-like family/weight/style matching.
const std = @import("std");
const ttf = @import("ttf.zig");
const Font = ttf.Font;

/// Stable handle of a registered face (index into `FontCollection.faces`).
pub const FaceId = u16;

pub const RegisterOptions = struct {
    /// Overrides the family read from the `name` table.
    family: ?[]const u8 = null,
    /// Overrides OS/2 usWeightClass.
    weight: ?u16 = null,
    /// Overrides the italic flag from OS/2 fsSelection / head.macStyle.
    italic: ?bool = null,
    /// Face index inside a .ttc.
    face_index: u32 = 0,
};

pub const Face = struct {
    font: Font,
    /// Owned copy of the family name (UTF-8).
    family: []u8,
    weight: u16,
    italic: bool,
    /// False after `unregister`; ids are never reused before `clear`.
    active: bool = true,
};

pub const FontCollection = struct {
    faces: std.ArrayList(Face) = .empty,

    /// Frees everything. `alloc` must be the allocator used for `register`.
    pub fn deinit(self: *FontCollection, alloc: std.mem.Allocator) void {
        self.clear(alloc);
        self.faces.deinit(alloc);
    }

    /// Registers a face. `data` is NOT copied and must stay alive until the face is unregistered.
    /// `alloc` should be a long-lived allocator (same one for every call on this collection).
    pub fn register(self: *FontCollection, alloc: std.mem.Allocator, data: []const u8, opts: RegisterOptions) !FaceId {
        const parsed = try Font.init(data, opts.face_index);
        if (self.faces.items.len >= 0xfffe) return error.OutOfMemory;
        var buf: [128]u8 = undefined;
        const fam = opts.family orelse parsed.familyName(&buf);
        const family = try alloc.dupe(u8, fam);
        errdefer alloc.free(family);
        try self.faces.append(alloc, .{
            .font = parsed,
            .family = family,
            .weight = opts.weight orelse parsed.weightClass(),
            .italic = opts.italic orelse parsed.isItalic(),
        });
        return @intCast(self.faces.items.len - 1);
    }

    /// Deactivates a face (its id stays reserved; the caller may free the font bytes afterwards).
    pub fn unregister(self: *FontCollection, alloc: std.mem.Allocator, id: FaceId) void {
        if (id >= self.faces.items.len) return;
        const f = &self.faces.items[id];
        if (!f.active) return;
        f.active = false;
        alloc.free(f.family);
        f.family = &.{};
    }

    /// Removes all faces; ids restart at 0.
    pub fn clear(self: *FontCollection, alloc: std.mem.Allocator) void {
        for (self.faces.items) |f| if (f.active) alloc.free(f.family);
        self.faces.clearRetainingCapacity();
    }

    pub fn count(self: *const FontCollection) usize {
        return self.faces.items.len;
    }

    /// The parsed font of a face. `id` must come from `register`/`match` (out-of-range ids
    /// are clamped to face 0; the collection must not be empty).
    pub fn font(self: *const FontCollection, id: FaceId) *const Font {
        const i = if (id < self.faces.items.len) id else 0;
        return &self.faces.items[i].font;
    }

    pub fn face(self: *const FontCollection, id: FaceId) *const Face {
        const i = if (id < self.faces.items.len) id else 0;
        return &self.faces.items[i];
    }

    /// CSS-like matching. Writes an ordered fallback list into `out` and returns the used prefix:
    /// first the best face (style, then CSS font-weight matching) of each requested family in
    /// order (ASCII case-insensitive names), then the best face of every other registered family
    /// in registration order (takumi falls back to all registered families).
    /// A face whose weight/italic differ from the request is returned as-is: the caller can
    /// compare `face(id).weight/italic` to synthesise bold/oblique.
    pub fn match(self: *const FontCollection, families: []const []const u8, weight: u16, italic: bool, out: []FaceId) []FaceId {
        var n: usize = 0;
        for (families) |fam| {
            if (n >= out.len) break;
            if (self.bestInFamily(fam, weight, italic)) |id| {
                if (std.mem.indexOfScalar(FaceId, out[0..n], id) == null) {
                    out[n] = id;
                    n += 1;
                }
            }
        }
        for (self.faces.items, 0..) |f, i| {
            if (n >= out.len) break;
            if (!f.active) continue;
            // only at the first face of each family
            var first = true;
            for (self.faces.items[0..i]) |p| {
                if (p.active and std.ascii.eqlIgnoreCase(p.family, f.family)) {
                    first = false;
                    break;
                }
            }
            if (!first) continue;
            const id = self.bestInFamily(f.family, weight, italic) orelse continue;
            if (std.mem.indexOfScalar(FaceId, out[0..n], id) == null) {
                out[n] = id;
                n += 1;
            }
        }
        return out[0..n];
    }

    fn bestInFamily(self: *const FontCollection, family: []const u8, weight: u16, italic: bool) ?FaceId {
        var best: ?FaceId = null;
        var best_score: u32 = std.math.maxInt(u32);
        for (self.faces.items, 0..) |f, i| {
            if (!f.active or !std.ascii.eqlIgnoreCase(f.family, family)) continue;
            var score: u32 = weightDistance(weight, f.weight);
            if (f.italic != italic) score += 1 << 20;
            if (score < best_score) {
                best_score = score;
                best = @intCast(i);
            }
        }
        return best;
    }
};

/// Rank of candidate weight `have` for requested weight `want` per the CSS font-weight matching
/// algorithm (lower is better).
fn weightDistance(want: u16, have: u16) u32 {
    const w: i32 = want;
    const h: i32 = have;
    if (h == w) return 0;
    const far: i32 = 2000;
    const d: i32 = if (w >= 400 and w <= 500) blk: {
        if (h > w and h <= 500) break :blk h - w; // up to 500 first
        if (h < w) break :blk 500 + (w - h); // then below, descending
        break :blk far + (h - w); // then above 500
    } else if (w < 400) blk: {
        if (h < w) break :blk w - h;
        break :blk far + (h - w);
    } else blk: {
        if (h > w) break :blk h - w;
        break :blk far + (w - h);
    };
    return @intCast(d);
}

test "weight matching" {
    const t = std.testing;
    try t.expect(weightDistance(400, 500) < weightDistance(400, 300));
    try t.expect(weightDistance(400, 300) < weightDistance(400, 700));
    try t.expect(weightDistance(700, 900) < weightDistance(700, 600));
    try t.expect(weightDistance(300, 100) < weightDistance(300, 400));
    try t.expect(weightDistance(500, 400) < weightDistance(500, 600));
}
