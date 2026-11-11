//! Render pipeline: JSON node tree -> computed styles -> layout -> paint -> encode.
//!
//! Memory model: `Renderer.gpa` is long-lived (fonts, image + glyph caches); `Renderer.arena` holds
//! everything of one render (including the returned bytes) and is reset at the start of the next call.
const std = @import("std");
const json = @import("json.zig");
const style = @import("style/style.zig");
const layout = @import("layout/layout.zig");
const font = @import("font/font.zig");
const raster = @import("raster/raster.zig");
const codec = @import("codec/codec.zig");
const paint = @import("paint.zig");
const bump = @import("bump.zig");

const Allocator = std.mem.Allocator;
pub const CS = style.ComputedStyle;
pub const none: u32 = std.math.maxInt(u32);

pub const Error = error{ OutOfMemory, Invalid };

pub const Kind = enum(u8) { container, text, image, anon_text };

pub const Node = struct {
    kind: Kind,
    cs: *const CS,
    parent: u32 = none,
    first_child: u32 = none,
    last_child: u32 = none,
    next: u32 = none,
    lid: u32 = none,
    para: ?*font.Paragraph = null,
    img: ?*const raster.Pixmap = null,
    /// intrinsic image size in device px
    img_w: f32 = 0,
    img_h: f32 = 0,
};

const ImageEntry = struct {
    src: []u8,
    data: []u8,
    /// raw RGBA entries: width/height > 0
    width: u32 = 0,
    height: u32 = 0,
    premultiplied: bool = false,
};

const CachedImage = struct {
    key: u64,
    /// 0 = original decode; otherwise the resampled target size
    tw: u32,
    th: u32,
    pm: *raster.Pixmap,
};

pub const GlyphMask = struct { x: i32, y: i32, w: u32, h: u32, data: []u8 };

pub const Format = enum { png, jpeg, webp, raw };

pub const Options = struct {
    width: ?u32 = null,
    height: ?u32 = null,
    format: Format = .png,
    quality: ?u8 = null,
    dpr: f32 = 1,
};

pub const Renderer = struct {
    gpa: Allocator,
    arena: bump.Bump,
    fonts: font.FontCollection = .{},
    font_blobs: std.ArrayList([]u8) = .empty,
    images: std.ArrayList(ImageEntry) = .empty,
    img_cache: std.ArrayList(CachedImage) = .empty,
    img_cache_bytes: usize = 0,
    rast: raster.Rasterizer,
    glyphs: std.AutoHashMapUnmanaged(u64, GlyphMask) = .empty,
    glyph_bytes: usize = 0,
    result: []const u8 = "",
    err: []const u8 = "",
    err_buf: [256]u8 = undefined,

    pub const glyph_budget: usize = 8 << 20;
    pub const image_budget: usize = 96 << 20;

    pub fn create(gpa: Allocator) ?*Renderer {
        const self = gpa.create(Renderer) catch return null;
        self.* = .{ .gpa = gpa, .arena = bump.Bump.init(gpa), .rast = raster.Rasterizer.init(gpa) };
        return self;
    }

    pub fn destroy(self: *Renderer) void {
        self.clearFonts();
        self.clearImages();
        self.clearImageCache();
        self.fonts.deinit(self.gpa);
        self.font_blobs.deinit(self.gpa);
        self.images.deinit(self.gpa);
        self.img_cache.deinit(self.gpa);
        self.glyphs.deinit(self.gpa);
        self.rast.deinit();
        self.arena.deinit();
        self.gpa.destroy(self);
    }

    pub fn setErr(self: *Renderer, comptime prefix: []const u8, detail: []const u8) void {
        var n: usize = 0;
        for (prefix) |c| {
            self.err_buf[n] = c;
            n += 1;
        }
        const room = self.err_buf.len - n;
        const m = @min(room, detail.len);
        @memcpy(self.err_buf[n..][0..m], detail[0..m]);
        self.err = self.err_buf[0 .. n + m];
    }

    fn clearGlyphs(self: *Renderer) void {
        var it = self.glyphs.valueIterator();
        while (it.next()) |g| self.gpa.free(g.data);
        self.glyphs.clearRetainingCapacity();
        self.glyph_bytes = 0;
    }

    fn clearImageCache(self: *Renderer) void {
        for (self.img_cache.items) |c| {
            c.pm.deinit(self.gpa);
            self.gpa.destroy(c.pm);
        }
        self.img_cache.clearRetainingCapacity();
        self.img_cache_bytes = 0;
    }

    /// Takes ownership of `data` (allocated with `gpa`). Returns a JSON description in the arena.
    pub fn registerFont(self: *Renderer, data: []u8, name: []const u8, weight: u16, italic: i32) Error![]const u8 {
        self.arena.reset();
        const id = self.fonts.register(self.gpa, data, .{
            .family = if (name.len > 0) name else null,
            .weight = if (weight > 0) weight else null,
            .italic = if (italic < 0) null else italic != 0,
        }) catch |e| {
            self.gpa.free(data);
            switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnsupportedFontFormat => self.setErr("unsupported font format (only static TrueType .ttf/.ttc is supported)", ""),
                else => self.setErr("invalid font data", ""),
            }
            return error.Invalid;
        };
        self.font_blobs.append(self.gpa, data) catch return error.OutOfMemory;
        const face = self.fonts.face(id);
        const a = self.arena.allocator();
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(a, "{\"name\":");
        try writeJsonString(a, &out, face.family);
        try out.appendSlice(a, ",\"weight\":");
        try writeNum(a, &out, @floatFromInt(face.weight));
        try out.appendSlice(a, if (face.italic) ",\"style\":\"italic\"}" else ",\"style\":\"normal\"}");
        self.result = out.items;
        return self.result;
    }

    pub fn clearFonts(self: *Renderer) void {
        self.clearGlyphs();
        self.fonts.clear(self.gpa);
        for (self.font_blobs.items) |b| self.gpa.free(b);
        self.font_blobs.clearRetainingCapacity();
    }

    pub fn putImage(self: *Renderer, src: []const u8, data: []const u8, w: u32, h: u32, premul: bool) Error!void {
        if (w != 0 and (@as(u64, w) * h * 4 != data.len)) {
            self.setErr("raw image data length must be width*height*4", "");
            return error.Invalid;
        }
        const s = try self.gpa.dupe(u8, src);
        errdefer self.gpa.free(s);
        const d = try self.gpa.dupe(u8, data);
        errdefer self.gpa.free(d);
        try self.images.append(self.gpa, .{ .src = s, .data = d, .width = w, .height = h, .premultiplied = premul });
    }

    pub fn clearImages(self: *Renderer) void {
        for (self.images.items) |e| {
            self.gpa.free(e.src);
            self.gpa.free(e.data);
        }
        self.images.clearRetainingCapacity();
    }

    pub fn releaseResult(self: *Renderer) void {
        self.result = "";
        self.arena.reset();
    }

    fn beginCall(self: *Renderer) void {
        self.result = "";
        self.err = "";
        self.arena.reset();
        if (self.glyph_bytes > glyph_budget) self.clearGlyphs();
        if (self.img_cache_bytes > image_budget) self.clearImageCache();
    }

    pub fn render(self: *Renderer, node_json: []const u8, opts_json: []const u8) Error![]const u8 {
        self.beginCall();
        const a = self.arena.allocator();
        const opts = try self.parseOptions(opts_json);
        var f: Frame = .{ .r = self, .a = a, .opts = opts, .tree = layout.Tree.init(a), .ctx = undefined };
        try f.prepare(node_json);

        var pm = raster.Pixmap.init(a, f.canvas_w, f.canvas_h) catch return error.OutOfMemory;
        try paint.paintFrame(&f, &pm);
        unpremultiply(pm.data);

        self.result = switch (opts.format) {
            .raw => pm.data,
            .png => codec.encodePng(a, pm.data, pm.width, pm.height, .{}) catch return error.OutOfMemory,
            .jpeg => codec.encodeJpeg(a, pm.data, pm.width, pm.height, .{ .quality = opts.quality orelse 75 }) catch return error.OutOfMemory,
            .webp => codec.encodeWebp(a, pm.data, pm.width, pm.height, .{}) catch return error.OutOfMemory,
        };
        return self.result;
    }

    pub fn measure(self: *Renderer, node_json: []const u8, opts_json: []const u8) Error![]const u8 {
        self.beginCall();
        const a = self.arena.allocator();
        const opts = try self.parseOptions(opts_json);
        var f: Frame = .{ .r = self, .a = a, .opts = opts, .tree = layout.Tree.init(a), .ctx = undefined };
        try f.prepare(node_json);
        var out: std.ArrayList(u8) = .empty;
        try f.writeMeasured(&out, f.root, 0, 0);
        self.result = out.items;
        return self.result;
    }

    fn parseOptions(self: *Renderer, text: []const u8) Error!Options {
        var o: Options = .{};
        if (text.len == 0) return o;
        const v = json.parse(self.arena.allocator(), text) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.setErr("invalid options JSON", "");
                return error.Invalid;
            },
        };
        if (v.get("width")) |w| if (w.asNumber()) |n| {
            o.width = dimOpt(n);
        };
        if (v.get("height")) |h| if (h.asNumber()) |n| {
            o.height = dimOpt(n);
        };
        if ((o.width != null and o.width.? == 0) or (o.height != null and o.height.? == 0)) {
            self.setErr("invalid viewport: width/height must be > 0", "");
            return error.Invalid;
        }
        if (v.get("devicePixelRatio")) |d| if (d.asNumber()) |n| {
            if (n > 0 and n < 64) o.dpr = n;
        };
        if (v.get("quality")) |q| if (q.asNumber()) |n| {
            o.quality = @intFromFloat(@min(100, @max(1, n)));
        };
        if (v.get("format")) |fv| if (fv.asString()) |s| {
            if (std.mem.eql(u8, s, "png")) o.format = .png else if (std.mem.eql(u8, s, "jpeg") or std.mem.eql(u8, s, "jpg")) o.format = .jpeg else if (std.mem.eql(u8, s, "webp")) o.format = .webp else if (std.mem.eql(u8, s, "raw")) o.format = .raw else {
                self.setErr("unsupported format: ", s);
                return error.Invalid;
            }
        };
        return o;
    }

    // ---- images

    fn findImage(self: *Renderer, src: []const u8) ?*const ImageEntry {
        var i = self.images.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.images.items[i].src, src)) return &self.images.items[i];
        }
        return null;
    }

    fn cacheLookup(self: *Renderer, key: u64, tw: u32, th: u32) ?*raster.Pixmap {
        for (self.img_cache.items) |c| {
            if (c.key == key and c.tw == tw and c.th == th) return c.pm;
        }
        return null;
    }

    fn cacheStore(self: *Renderer, key: u64, tw: u32, th: u32, pm: raster.Pixmap) ?*raster.Pixmap {
        const p = self.gpa.create(raster.Pixmap) catch return null;
        p.* = pm;
        self.img_cache.append(self.gpa, .{ .key = key, .tw = tw, .th = th, .pm = p }) catch {
            self.gpa.destroy(p);
            return null;
        };
        self.img_cache_bytes += pm.data.len;
        return p;
    }

    /// Resolves an image `src` (data: URI or a key of the `images` option) to a decoded,
    /// premultiplied pixmap (cached across renders by content hash). null = paints nothing.
    pub fn resolveImage(self: *Renderer, src: []const u8) ?*const raster.Pixmap {
        var bytes: []const u8 = undefined;
        var raw: ?*const ImageEntry = null;
        if (std.mem.startsWith(u8, src, "data:")) {
            bytes = decodeDataUri(self.arena.allocator(), src) orelse return null;
        } else if (self.findImage(src)) |e| {
            bytes = e.data;
            if (e.width != 0) raw = e;
        } else return null;

        const key = std.hash.Wyhash.hash(bytes.len, bytes);
        if (self.cacheLookup(key, 0, 0)) |pm| return pm;

        var pm: raster.Pixmap = undefined;
        if (raw) |e| {
            pm = raster.Pixmap.init(self.gpa, e.width, e.height) catch return null;
            @memcpy(pm.data, bytes);
            if (!e.premultiplied) premultiply(pm.data);
        } else {
            const img = codec.decode(self.gpa, bytes, .{ .max_pixels = 40 << 20 }) catch return null;
            premultiply(img.data);
            pm = .{ .width = img.width, .height = img.height, .data = img.data };
        }
        return self.cacheStore(key, 0, 0, pm) orelse {
            pm.deinit(self.gpa);
            return null;
        };
    }

    /// Catmull-Rom downscaled variant of a cached image (cached as well).
    pub fn resampled(self: *Renderer, src: *const raster.Pixmap, tw: u32, th: u32) *const raster.Pixmap {
        if (tw == 0 or th == 0 or (tw >= src.width and th >= src.height)) return src;
        const w = @min(tw, src.width);
        const h = @min(th, src.height);
        const key = @as(u64, @intFromPtr(src.data.ptr)) ^ 0x9e3779b97f4a7c15;
        if (self.cacheLookup(key, w, h)) |pm| return pm;
        const pm = raster.resample(self.gpa, src, w, h) catch return src;
        return self.cacheStore(key, w, h, pm) orelse blk: {
            // could not cache: keep it alive in the arena instead
            const a = self.arena.allocator();
            const copy = a.create(raster.Pixmap) catch break :blk src;
            copy.* = raster.Pixmap.init(a, w, h) catch break :blk src;
            @memcpy(copy.data, pm.data);
            var tmp = pm;
            tmp.deinit(self.gpa);
            break :blk copy;
        };
    }
};

fn dimOpt(n: f32) u32 {
    if (!(n >= 1)) return 0;
    return @intFromFloat(@min(n, 16384));
}

/// 2^32 / (2a), rounded up: `(n * recip[a]) >> 32 == n / (2a)` for every n < 2^17.
const recip: [256]u32 = blk: {
    @setEvalBranchQuota(4000);
    var t: [256]u32 = undefined;
    t[0] = 0;
    for (1..256) |a| t[a] = @intCast(((@as(u64, 1) << 32) + 2 * @as(u64, a) - 1) / (2 * @as(u64, a)));
    break :blk t;
};

/// In-place premultiplied -> straight alpha with takumi's rounding `(c*510 + a) / (2a)`.
pub fn unpremultiply(data: []u8) void {
    var i: usize = 0;
    const n = data.len & ~@as(usize, 3);
    var lut: [256]u8 = undefined;
    var lut_a: u32 = 256; // alpha the LUT was built for
    var prev_a: u32 = 256;
    while (i < n) {
        // fast skip over fully opaque / fully transparent runs, two pixels at a time
        while (i + 8 <= n) {
            const two = @as(*align(1) const u64, @ptrCast(data[i..].ptr)).* & 0xFF000000_FF000000;
            if (two != 0xFF000000_FF000000 and two != 0) break;
            i += 8;
        }
        if (i >= n) break;
        const a: u32 = data[i + 3];
        if (a == 0) {
            data[i] = 0;
            data[i + 1] = 0;
            data[i + 2] = 0;
        } else if (a != 255) {
            if (a == lut_a) {
                data[i] = lut[data[i]];
                data[i + 1] = lut[data[i + 1]];
                data[i + 2] = lut[data[i + 2]];
            } else {
                const m: u64 = recip[a];
                if (a == prev_a) {
                    // a run of the same alpha: build a per-alpha table once
                    for (&lut, 0..) |*e, c| e.* = @intCast(@min(255, (@as(u64, @as(u32, @intCast(c)) * 510 + a) * m) >> 32));
                    lut_a = a;
                }
                inline for (0..3) |k| {
                    const v: u32 = @intCast((@as(u64, @as(u32, data[i + k]) * 510 + a) * m) >> 32);
                    data[i + k] = @intCast(@min(v, 255));
                }
            }
        }
        prev_a = a;
        i += 4;
    }
}

test "unpremultiply matches the division formula" {
    var buf: [4]u8 = undefined;
    var a: u32 = 1;
    while (a < 256) : (a += 1) {
        var c: u32 = 0;
        while (c < 256) : (c += 1) {
            buf = .{ @intCast(c), @intCast(c), @intCast(c), @intCast(a) };
            unpremultiply(&buf);
            const want: u32 = @min(255, (c * 510 + a) / (2 * a));
            try std.testing.expectEqual(want, @as(u32, buf[0]));
        }
    }
}

fn premultiply(data: []u8) void {
    var i: usize = 0;
    while (i + 4 <= data.len) : (i += 4) {
        const a: u32 = data[i + 3];
        if (a == 255) continue;
        data[i] = @intCast(raster.div255(@as(u32, data[i]) * a));
        data[i + 1] = @intCast(raster.div255(@as(u32, data[i + 1]) * a));
        data[i + 2] = @intCast(raster.div255(@as(u32, data[i + 2]) * a));
    }
}

fn decodeDataUri(a: Allocator, src: []const u8) ?[]const u8 {
    const comma = std.mem.indexOfScalar(u8, src, ',') orelse return null;
    const meta = src[5..comma];
    const payload = src[comma + 1 ..];
    if (!std.mem.endsWith(u8, meta, ";base64")) return payload;
    const out = a.alloc(u8, payload.len / 4 * 3 + 3) catch return null;
    var n: usize = 0;
    var acc: u32 = 0;
    var bits: u32 = 0;
    for (payload) |c| {
        const v: u32 = switch (c) {
            'A'...'Z' => c - 'A',
            'a'...'z' => c - 'a' + 26,
            '0'...'9' => c - '0' + 52,
            '+', '-' => 62,
            '/', '_' => 63,
            else => continue,
        };
        acc = (acc << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[n] = @truncate(acc >> @intCast(bits));
            n += 1;
        }
    }
    return out[0..n];
}

pub fn writeJsonString(a: Allocator, out: *std.ArrayList(u8), s: []const u8) Error!void {
    try out.append(a, '"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(a, "\\\""),
            '\\' => try out.appendSlice(a, "\\\\"),
            '\n' => try out.appendSlice(a, "\\n"),
            '\r' => try out.appendSlice(a, "\\r"),
            '\t' => try out.appendSlice(a, "\\t"),
            else => {
                if (c < 0x20) {
                    const hex = "0123456789abcdef";
                    try out.appendSlice(a, "\\u00");
                    try out.append(a, hex[c >> 4]);
                    try out.append(a, hex[c & 15]);
                } else try out.append(a, c);
            },
        }
    }
    try out.append(a, '"');
}

/// Decimal printer (up to 6 fraction digits, trailing zeros trimmed) without std.fmt.
pub fn writeNum(a: Allocator, out: *std.ArrayList(u8), v_in: f32) Error!void {
    var v: f64 = v_in;
    if (!(v == v) or @abs(v) > 1.0e15) v = 0;
    if (v < 0) {
        try out.append(a, '-');
        v = -v;
    }
    var scaled: u64 = @intFromFloat(@floor(v * 1.0e6 + 0.5));
    const int_part = scaled / 1_000_000;
    scaled %= 1_000_000;
    var buf: [24]u8 = undefined;
    var n: usize = buf.len;
    var ip = int_part;
    while (true) {
        n -= 1;
        buf[n] = @intCast('0' + ip % 10);
        ip /= 10;
        if (ip == 0) break;
    }
    try out.appendSlice(a, buf[n..]);
    if (scaled != 0) {
        var frac: [6]u8 = undefined;
        var i: usize = 6;
        while (i > 0) {
            i -= 1;
            frac[i] = @intCast('0' + scaled % 10);
            scaled /= 10;
        }
        var end: usize = 6;
        while (end > 0 and frac[end - 1] == '0') end -= 1;
        try out.append(a, '.');
        try out.appendSlice(a, frac[0..end]);
    }
}

// ------------------------------------------------------------------------------------------------

pub const Frame = struct {
    r: *Renderer,
    a: Allocator,
    opts: Options,
    ctx: style.Context,
    tree: layout.Tree,
    nodes: std.ArrayList(Node) = .empty,
    /// TextStyle.user -> style of the run (colour, decorations)
    run_styles: std.ArrayList(*const CS) = .empty,
    lid_node: std.ArrayList(u32) = .empty,
    root: u32 = none,
    lroot: u32 = none,
    canvas_w: u32 = 0,
    canvas_h: u32 = 0,

    fn fail(f: *Frame, comptime msg: []const u8, detail: []const u8) Error {
        f.r.setErr(msg, detail);
        return error.Invalid;
    }

    fn prepare(f: *Frame, node_json: []const u8) Error!void {
        const o = f.opts;
        f.ctx = .{
            .dpr = o.dpr,
            .viewport_w = if (o.width) |w| @floatFromInt(w) else 0,
            .viewport_h = if (o.height) |h| @floatFromInt(h) else 0,
            .root_font_size = 16 * o.dpr,
        };
        const v = json.parse(f.a, node_json) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.JsonTooDeep => return f.fail("node tree is nested too deeply", ""),
            else => return f.fail("invalid node JSON", ""),
        };
        f.root = try f.buildElement(v, null, none, 0);

        // Initial containing block.
        var icb: layout.Style = .{ .display = .block };
        if (o.width) |w| icb.size[0] = .{ .px = @floatFromInt(w) };
        if (o.height) |h| icb.size[1] = .{ .px = @floatFromInt(h) };
        f.lroot = f.tree.addNode(icb) catch return error.OutOfMemory;
        const lr = try f.buildLayout(f.root);
        f.tree.appendChild(f.lroot, lr) catch return error.OutOfMemory;
        const avail: [2]layout.AvailableSpace = .{
            if (o.width) |w| .{ .definite = @floatFromInt(w) } else .max_content,
            if (o.height) |h| .{ .definite = @floatFromInt(h) } else .max_content,
        };
        f.tree.compute(f.lroot, avail, f, measureCb, .{ .quantize64 = true, .baseline = baselineCb }) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return f.fail("node tree is nested too deeply", ""),
        };
        const rl = f.tree.layout(lr);
        const cw: f32 = if (o.width) |w| @floatFromInt(w) else @floor(rl.x + rl.w + rl.margin.right + 0.5);
        const ch: f32 = if (o.height) |h| @floatFromInt(h) else @floor(rl.y + rl.h + rl.margin.bottom + 0.5);
        if (!(cw >= 1) or !(ch >= 1)) return f.fail("invalid viewport: content has zero size and no width/height was given", "");
        if (cw > 16384 or ch > 16384 or cw * ch > 64.0e6) return f.fail("canvas too large", "");
        f.canvas_w = @intFromFloat(cw);
        f.canvas_h = @intFromFloat(ch);
    }

    fn addNode(f: *Frame, n: Node) Error!u32 {
        try f.nodes.append(f.a, n);
        const id: u32 = @intCast(f.nodes.items.len - 1);
        const p = n.parent;
        if (p != none) {
            const pn = &f.nodes.items[p];
            if (pn.last_child == none) pn.first_child = id else f.nodes.items[pn.last_child].next = id;
            pn.last_child = id;
        }
        return id;
    }

    fn computeStyle(f: *Frame, v: json.Value, parent: ?*const CS) Error!*const CS {
        var diag: style.Diagnostics = .{};
        const cs = try f.a.create(CS);
        cs.* = style.compute(f.a, &f.ctx, parent, v.get("preset"), v.get("style"), &diag) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidStyleValue => return f.fail("invalid value for style property ", diag.property),
        };
        return cs;
    }

    fn typeOf(f: *Frame, v: json.Value) Error!Kind {
        const t = (v.get("type") orelse return f.fail("node is missing `type`", "")).asString() orelse return f.fail("node `type` must be a string", "");
        if (std.mem.eql(u8, t, "container")) return .container;
        if (std.mem.eql(u8, t, "text")) return .text;
        if (std.mem.eql(u8, t, "image")) return .image;
        return f.fail("unknown node type: ", t);
    }

    fn buildElement(f: *Frame, v: json.Value, parent_cs: ?*const CS, parent: u32, depth: u32) Error!u32 {
        if (depth > 200) return f.fail("node tree is nested too deeply", "");
        if (v != .object) return f.fail("node must be an object", "");
        const kind = try f.typeOf(v);
        var cs = try f.computeStyle(v, parent_cs);
        if (parent == none) f.ctx.root_font_size = cs.font_size;
        switch (kind) {
            .text => {
                const text = (v.get("text") orelse return f.fail("text node is missing `text`", "")).asString() orelse return f.fail("`text` must be a string", "");
                const id = try f.addNode(.{ .kind = .text, .cs = cs, .parent = parent });
                var runs: [1]font.Run = .{try f.makeRun(text, cs)};
                f.nodes.items[id].para = try f.makeParagraph(&runs, cs);
                return id;
            },
            .image => {
                var img: ?*const raster.Pixmap = null;
                if (v.get("src")) |s| {
                    if (s.asString()) |src| img = f.r.resolveImage(src);
                } else return f.fail("image node is missing `src`", "");
                // `width` / `height` attributes act as a low-priority size preset.
                const wa = if (v.get("width")) |x| x.asNumber() else null;
                const ha = if (v.get("height")) |x| x.asNumber() else null;
                if ((wa != null and cs.width == .auto) or (ha != null and cs.height == .auto)) {
                    const m = try f.a.create(CS);
                    m.* = cs.*;
                    if (wa != null and m.width == .auto) m.width = .{ .lp = .{ .px = wa.? * f.opts.dpr } };
                    if (ha != null and m.height == .auto) m.height = .{ .lp = .{ .px = ha.? * f.opts.dpr } };
                    cs = m;
                }
                var n: Node = .{ .kind = .image, .cs = cs, .parent = parent, .img = img };
                if (img) |pm| {
                    n.img_w = @as(f32, @floatFromInt(pm.width)) * f.opts.dpr;
                    n.img_h = @as(f32, @floatFromInt(pm.height)) * f.opts.dpr;
                }
                return f.addNode(n);
            },
            else => {},
        }
        const id = try f.addNode(.{ .kind = .container, .cs = cs, .parent = parent });
        const children: []json.Value = if (v.get("children")) |c| (if (c == .array) c.array else &.{}) else &.{};
        const inline_ctx = switch (cs.display) {
            .flex, .inline_flex, .grid, .inline_grid => false,
            else => true,
        };
        var pending: std.ArrayList(font.Run) = .empty;
        for (children) |cv| {
            if (cv == .null) continue;
            if (inline_ctx and isInlineLevel(cv, 0)) {
                try f.collectRuns(cv, cs, &pending, depth + 1);
                continue;
            }
            try f.flushRuns(&pending, cs, id);
            _ = try f.buildElement(cv, cs, id, depth + 1);
        }
        try f.flushRuns(&pending, cs, id);
        return id;
    }

    fn flushRuns(f: *Frame, pending: *std.ArrayList(font.Run), cs: *const CS, parent: u32) Error!void {
        if (pending.items.len == 0) return;
        defer pending.* = .empty;
        if (cs.white_space_collapse == .collapse) {
            var all_ws = true;
            for (pending.items) |r| {
                for (r.text) |c| {
                    if (c != ' ' and c != '\n' and c != '\t' and c != '\r') {
                        all_ws = false;
                        break;
                    }
                }
            }
            if (all_ws) return;
        }
        const id = try f.addNode(.{ .kind = .anon_text, .cs = cs, .parent = parent });
        f.nodes.items[id].para = try f.makeParagraph(pending.items, cs);
    }

    fn collectRuns(f: *Frame, v: json.Value, parent_cs: *const CS, out: *std.ArrayList(font.Run), depth: u32) Error!void {
        if (depth > 200) return f.fail("node tree is nested too deeply", "");
        const kind = try f.typeOf(v);
        const cs = try f.computeStyle(v, parent_cs);
        if (cs.display == .none) return;
        if (kind == .text) {
            const text = (v.get("text") orelse return f.fail("text node is missing `text`", "")).asString() orelse return f.fail("`text` must be a string", "");
            try out.append(f.a, try f.makeRun(text, cs));
            return;
        }
        if (v.get("children")) |c| if (c == .array) {
            for (c.array) |cv| if (cv != .null) try f.collectRuns(cv, cs, out, depth + 1);
        };
    }

    fn makeRun(f: *Frame, text: []const u8, cs: *const CS) Error!font.Run {
        try f.run_styles.append(f.a, cs);
        return .{
            .text = try transformText(f.a, text, cs.text_transform),
            .style = textStyle(cs, @intCast(f.run_styles.items.len - 1)),
        };
    }

    fn makeParagraph(f: *Frame, runs: []const font.Run, cs: *const CS) Error!*font.Paragraph {
        const ws: font.WhiteSpace = switch (cs.white_space_collapse) {
            .collapse => if (cs.text_wrap_mode == .nowrap) .nowrap else .normal,
            .preserve, .preserve_spaces => if (cs.text_wrap_mode == .nowrap) .pre else .pre_wrap,
            .preserve_breaks => .pre_line,
            .break_spaces => .pre_wrap,
        };
        const clip = cs.overflow_x != .visible;
        const opts: font.ParagraphOptions = .{
            .text_align = switch (cs.text_align) {
                .start => .start,
                .end => .end,
                .left => .left,
                .right => .right,
                .center => .center,
                .justify => .justify,
            },
            .line_height = switch (cs.line_height) {
                .normal => .normal,
                .number => |n| .{ .multiple = n },
                .px => |p| .{ .px = p },
            },
            .white_space = ws,
            .word_break = switch (cs.word_break) {
                .normal, .break_word => .normal,
                .break_all => .break_all,
                .keep_all => .keep_all,
            },
            .overflow_wrap = if (cs.word_break == .break_word) .anywhere else switch (cs.overflow_wrap) {
                .normal => .normal,
                .break_word => .break_word,
                .anywhere => .anywhere,
            },
            .max_lines = if (cs.line_clamp > 0) cs.line_clamp else null,
            .ellipsis = cs.text_overflow == .ellipsis and clip,
            .strut = textStyle(cs, 0),
        };
        const p = try f.a.create(font.Paragraph);
        p.* = font.Paragraph.init(f.a, &f.r.fonts, runs, opts) catch return error.OutOfMemory;
        return p;
    }

    // ---- layout tree

    fn buildLayout(f: *Frame, id: u32) Error!u32 {
        const n = f.nodes.items[id];
        const cs = n.cs;
        var st: layout.Style = if (n.kind == .anon_text) .{ .display = .block } else mapStyle(f, cs);
        const leaf = n.kind != .container;
        if (leaf and st.display != .none) st.display = .block;
        if (n.kind == .image and st.aspect_ratio == null and n.img_w > 0 and n.img_h > 0) st.aspect_ratio = n.img_w / n.img_h;
        const lid = f.tree.addNode(st) catch return error.OutOfMemory;
        f.nodes.items[id].lid = lid;
        while (f.lid_node.items.len <= lid) try f.lid_node.append(f.a, none);
        f.lid_node.items[lid] = id;
        if (leaf) {
            f.tree.setMeasured(lid, true);
            return lid;
        }
        // children, honouring `order` for flex/grid containers
        var needs_order = false;
        var c = n.first_child;
        while (c != none) : (c = f.nodes.items[c].next) {
            if (f.nodes.items[c].cs.order != 0 and f.nodes.items[c].kind != .anon_text) needs_order = true;
        }
        if (!needs_order or st.display == .block) {
            c = n.first_child;
            while (c != none) : (c = f.nodes.items[c].next) {
                const cl = try f.buildLayout(c);
                f.tree.appendChild(lid, cl) catch return error.OutOfMemory;
            }
        } else {
            var list: std.ArrayList(u32) = .empty;
            c = n.first_child;
            while (c != none) : (c = f.nodes.items[c].next) try list.append(f.a, c);
            // stable insertion sort by order
            var i: usize = 1;
            while (i < list.items.len) : (i += 1) {
                const x = list.items[i];
                const ox = f.nodes.items[x].cs.order;
                var j = i;
                while (j > 0 and f.nodes.items[list.items[j - 1]].cs.order > ox) : (j -= 1) list.items[j] = list.items[j - 1];
                list.items[j] = x;
            }
            for (list.items) |x| {
                const cl = try f.buildLayout(x);
                f.tree.appendChild(lid, cl) catch return error.OutOfMemory;
            }
        }
        return lid;
    }

    fn measureCb(ctx: *anyopaque, lid: layout.NodeId, known: [2]?f32, avail: [2]layout.AvailableSpace) [2]f32 {
        const f: *Frame = @ptrCast(@alignCast(ctx));
        if (lid >= f.lid_node.items.len) return .{ 0, 0 };
        const id = f.lid_node.items[lid];
        if (id == none) return .{ 0, 0 };
        const n = &f.nodes.items[id];
        if (n.kind == .image) {
            const iw = n.img_w;
            const ih = n.img_h;
            if (known[0]) |w| {
                if (known[1]) |h| return .{ w, h };
                return .{ w, if (iw > 0) w * ih / iw else 0 };
            }
            if (known[1]) |h| return .{ if (ih > 0) h * iw / ih else 0, h };
            return .{ iw, ih };
        }
        const p = n.para orelse return .{ known[0] orelse 0, known[1] orelse 0 };
        const limit: ?f32 = known[0] orelse switch (avail[0]) {
            .definite => |v| v,
            .min_content => p.minContentWidth(),
            .max_content => null,
        };
        const sz = p.measure(limit);
        return .{ known[0] orelse sz.width, known[1] orelse sz.height };
    }

    fn baselineCb(ctx: *anyopaque, lid: layout.NodeId, content_size: [2]f32) f32 {
        const f: *Frame = @ptrCast(@alignCast(ctx));
        if (lid >= f.lid_node.items.len) return content_size[1];
        const id = f.lid_node.items[lid];
        if (id == none) return content_size[1];
        const p = f.nodes.items[id].para orelse return content_size[1];
        const tl = p.layout(f.a, content_size[0]) catch return content_size[1];
        if (tl.lines.len == 0) return content_size[1];
        return tl.lines[0].baseline;
    }

    // ---- measure() output

    fn writeMeasured(f: *Frame, out: *std.ArrayList(u8), id: u32, ox: f32, oy: f32) Error!void {
        const a = f.a;
        const n = f.nodes.items[id];
        const l = f.tree.layout(n.lid);
        const x = ox + l.x;
        const y = oy + l.y;
        try out.appendSlice(a, "{\"width\":");
        try writeNum(a, out, l.w);
        try out.appendSlice(a, ",\"height\":");
        try writeNum(a, out, l.h);
        try out.appendSlice(a, ",\"transform\":[1,0,0,1,");
        try writeNum(a, out, x);
        try out.append(a, ',');
        try writeNum(a, out, y);
        try out.appendSlice(a, "],\"children\":[");
        var c = n.first_child;
        var first = true;
        while (c != none) : (c = f.nodes.items[c].next) {
            if (!first) try out.append(a, ',');
            first = false;
            try f.writeMeasured(out, c, x, y);
        }
        try out.appendSlice(a, "],\"runs\":[");
        if (n.para) |p| {
            const cw = l.w - l.padding.left - l.padding.right - l.border.left - l.border.right;
            const tl = p.layout(a, cw) catch return error.OutOfMemory;
            for (tl.lines, 0..) |line, i| {
                if (i != 0) try out.append(a, ',');
                try out.appendSlice(a, "{\"x\":");
                try writeNum(a, out, l.border.left + l.padding.left + line.x);
                try out.appendSlice(a, ",\"y\":");
                try writeNum(a, out, l.border.top + l.padding.top + line.top);
                try out.appendSlice(a, ",\"width\":");
                try writeNum(a, out, line.width);
                try out.appendSlice(a, ",\"height\":");
                try writeNum(a, out, line.height);
                try out.append(a, '}');
            }
        }
        try out.appendSlice(a, "]}");
    }
};

fn jsonDisplay(v: json.Value) ?[]const u8 {
    if (v.get("style")) |s| if (s.get("display")) |d| return d.asString() orelse "";
    if (v.get("preset")) |s| if (s.get("display")) |d| return d.asString() orelse "";
    return null;
}

/// True when `v` is inline-level content that joins the parent's paragraph: a text node, or a
/// "span" (container whose descendants are all inline-level), with `display` unset or `inline`.
fn isInlineLevel(v: json.Value, depth: u32) bool {
    if (v != .object or depth > 64) return false;
    if (jsonDisplay(v)) |d| if (!std.mem.eql(u8, d, "inline")) return false;
    const t = (v.get("type") orelse return false).asString() orelse return false;
    if (std.mem.eql(u8, t, "text")) return true;
    if (!std.mem.eql(u8, t, "container")) return false;
    const c = v.get("children") orelse return false;
    if (c != .array or c.array.len == 0) return false;
    for (c.array) |cv| {
        if (cv == .null) continue;
        if (!isInlineLevel(cv, depth + 1)) return false;
    }
    return true;
}

pub fn textStyle(cs: *const CS, user: u32) font.TextStyle {
    return .{
        .families = cs.font_family,
        .weight = cs.font_weight,
        .italic = cs.font_style != .normal,
        .size = cs.font_size,
        .letter_spacing = cs.letter_spacing,
        .word_spacing = cs.word_spacing,
        .user = user,
    };
}

fn decodeCp(s: []const u8, i: *usize) u21 {
    const b0 = s[i.*];
    var len: usize = 1;
    var cp: u21 = b0;
    if (b0 >= 0xF0 and b0 < 0xF8) {
        len = 4;
        cp = b0 & 0x07;
    } else if (b0 >= 0xE0) {
        len = 3;
        cp = b0 & 0x0F;
    } else if (b0 >= 0xC0) {
        len = 2;
        cp = b0 & 0x1F;
    } else {
        i.* += 1;
        return b0;
    }
    if (i.* + len > s.len) {
        i.* += 1;
        return 0xFFFD;
    }
    var k: usize = 1;
    while (k < len) : (k += 1) {
        const b = s[i.* + k];
        if (b & 0xC0 != 0x80) {
            i.* += 1;
            return 0xFFFD;
        }
        cp = (cp << 6) | (b & 0x3F);
    }
    i.* += len;
    return cp;
}

fn caseMap(cp: u21, upper: bool) u21 {
    if (cp < 0x80) {
        if (upper and cp >= 'a' and cp <= 'z') return cp - 32;
        if (!upper and cp >= 'A' and cp <= 'Z') return cp + 32;
        return cp;
    }
    // Latin-1 Supplement
    if (cp >= 0xC0 and cp <= 0xDE and cp != 0xD7) return if (upper) cp else cp + 32;
    if (cp >= 0xE0 and cp <= 0xFE and cp != 0xF7) return if (upper) cp - 32 else cp;
    if (cp == 0xFF) return if (upper) 0x178 else cp;
    // Latin Extended-A (pairs, with the well-known irregular ranges) and Extended Additional (Vietnamese)
    const paired_even = (cp >= 0x100 and cp <= 0x137 and cp != 0x130 and cp != 0x131) or (cp >= 0x14A and cp <= 0x177) or (cp >= 0x1E00 and cp <= 0x1E95) or (cp >= 0x1EA0 and cp <= 0x1EFF) or (cp >= 0x1A0 and cp <= 0x1A5) or (cp >= 0x1AF and cp <= 0x1B0 and false);
    if (paired_even) {
        const is_lower = cp & 1 == 1;
        if (upper and is_lower) return cp - 1;
        if (!upper and !is_lower) return cp + 1;
        return cp;
    }
    const paired_odd = (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E);
    if (paired_odd) {
        const is_lower = cp & 1 == 0;
        if (upper and is_lower) return cp - 1;
        if (!upper and !is_lower) return cp + 1;
        return cp;
    }
    // Ư ư
    if (cp == 0x1AF and !upper) return 0x1B0;
    if (cp == 0x1B0 and upper) return 0x1AF;
    // Greek / Cyrillic basics
    if (cp >= 0x391 and cp <= 0x3A9 and cp != 0x3A2) return if (upper) cp else cp + 32;
    if (cp >= 0x3B1 and cp <= 0x3C9 and cp != 0x3C2) return if (upper) cp - 32 else cp;
    if (cp >= 0x410 and cp <= 0x42F) return if (upper) cp else cp + 32;
    if (cp >= 0x430 and cp <= 0x44F) return if (upper) cp - 32 else cp;
    return cp;
}

fn transformText(a: Allocator, text: []const u8, tt: anytype) Error![]const u8 {
    if (tt == .none) return text;
    var out: std.ArrayList(u8) = .empty;
    try out.ensureTotalCapacity(a, text.len + 8);
    var i: usize = 0;
    var word_start = true;
    while (i < text.len) {
        const cp = decodeCp(text, &i);
        const is_space = cp == ' ' or cp == '\n' or cp == '\t' or cp == 0xA0;
        const m: u21 = switch (tt) {
            .uppercase => caseMap(cp, true),
            .lowercase => caseMap(cp, false),
            .capitalize => if (word_start) caseMap(cp, true) else cp,
            else => cp,
        };
        word_start = is_space;
        if (tt == .uppercase and cp == 0xDF) {
            try out.appendSlice(a, "SS");
            continue;
        }
        var buf: [4]u8 = undefined;
        const len = json.encodeUtf8(m, &buf);
        try out.appendSlice(a, buf[0..len]);
    }
    return out.items;
}

// ---- ComputedStyle -> layout.Style

fn dimLp(lp: style.LP) layout.Dim {
    if (lp.pct == 0) return .{ .px = lp.px };
    if (lp.px == 0) return .{ .percent = lp.pct };
    return .{ .calc = .{ .px = lp.px, .percent = lp.pct } };
}

fn dimSize(s: style.Size) layout.Dim {
    return switch (s) {
        .lp => |lp| dimLp(lp),
        .min_content => .min_content,
        .max_content => .max_content,
        .fit_content => .fit_content,
        else => .auto,
    };
}

fn dimAuto(s: style.LengthAuto) layout.Dim {
    return switch (s) {
        .auto => .auto,
        .lp => |lp| dimLp(lp),
    };
}

fn lpOf(lp: style.LP) layout.LengthPercentage {
    if (lp.pct == 0) return .{ .px = lp.px };
    if (lp.px == 0) return .{ .percent = lp.pct };
    return .{ .calc = .{ .px = lp.px, .percent = lp.pct } };
}

fn alignOf(al: style.Align) ?layout.Align {
    return switch (al) {
        .normal, .auto => null,
        .stretch => .stretch,
        .start, .self_start, .left => .start,
        .end, .self_end, .right => .end,
        .flex_start => .flex_start,
        .flex_end => .flex_end,
        .center => .center,
        .baseline, .last_baseline => .baseline,
        .space_between => .space_between,
        .space_around => .space_around,
        .space_evenly => .space_evenly,
    };
}

fn breadth(t: style.TrackSize) layout.TrackBreadth {
    return switch (t) {
        .auto => .auto,
        .lp => |lp| if (lp.pct == 0) .{ .px = lp.px } else .{ .percent = lp.pct },
        .fr => |v| .{ .fr = v },
        .min_content => .min_content,
        .max_content => .max_content,
        .fit_content => |lp| .{ .fit_content = lpOf(lp) },
    };
}

fn tracks(f: *Frame, src: []const style.Track) []const layout.Track {
    if (src.len == 0) return &.{};
    const out = f.a.alloc(layout.Track, src.len) catch return &.{};
    for (src, 0..) |t, i| out[i] = .{ .min = breadth(t.min), .max = breadth(t.max) };
    return out;
}

fn template(f: *Frame, t: style.GridTemplate, list: *[]const layout.Track, rep: *?layout.AutoRepeat) void {
    const all = tracks(f, t.tracks);
    if (t.auto_repeat == .none or t.auto_repeat_len == 0 or @as(usize, t.auto_repeat_start) + t.auto_repeat_len > all.len) {
        list.* = all;
        return;
    }
    const s: usize = t.auto_repeat_start;
    const e: usize = s + t.auto_repeat_len;
    const rest = f.a.alloc(layout.Track, all.len - t.auto_repeat_len) catch return;
    @memcpy(rest[0..s], all[0..s]);
    @memcpy(rest[s..], all[e..]);
    list.* = rest;
    rep.* = .{ .fit = t.auto_repeat == .fit, .tracks = all[s..e], .at = @intCast(s) };
}

fn gridLine(g: style.GridLine) layout.Line {
    return switch (g) {
        .auto => .auto,
        .line => |v| .{ .line = @intCast(std.math.clamp(v, -30000, 30000)) },
        .span => |v| .{ .span = @intCast(@min(v, 30000)) },
    };
}

fn mapStyle(f: *Frame, cs: *const CS) layout.Style {
    var s: layout.Style = .{};
    s.display = switch (cs.display) {
        .none => .none,
        .flex, .inline_flex => .flex,
        .grid, .inline_grid => .grid,
        else => .block,
    };
    s.position = switch (cs.position) {
        .static => .static,
        .relative, .sticky => .relative,
        .absolute, .fixed => .absolute,
    };
    s.box_sizing = if (cs.box_sizing == .border_box) .border_box else .content_box;
    s.overflow_x = mapOverflow(cs.overflow_x);
    s.overflow_y = mapOverflow(cs.overflow_y);
    s.inset = .{ .top = dimAuto(cs.inset[0]), .right = dimAuto(cs.inset[1]), .bottom = dimAuto(cs.inset[2]), .left = dimAuto(cs.inset[3]) };
    s.size = .{ dimSize(cs.width), dimSize(cs.height) };
    s.min_size = .{ dimSize(cs.min_width), dimSize(cs.min_height) };
    s.max_size = .{ dimSize(cs.max_width), dimSize(cs.max_height) };
    s.aspect_ratio = cs.aspect_ratio;
    s.margin = .{ .top = dimAuto(cs.margin[0]), .right = dimAuto(cs.margin[1]), .bottom = dimAuto(cs.margin[2]), .left = dimAuto(cs.margin[3]) };
    s.padding = .{ .top = lpOf(cs.padding[0]), .right = lpOf(cs.padding[1]), .bottom = lpOf(cs.padding[2]), .left = lpOf(cs.padding[3]) };
    const bw = cs.usedBorderWidths();
    s.border = .{ .top = bw[0], .right = bw[1], .bottom = bw[2], .left = bw[3] };
    s.gap = .{ lpOf(cs.column_gap), lpOf(cs.row_gap) };
    s.flex_direction = switch (cs.flex_direction) {
        .row => .row,
        .row_reverse => .row_reverse,
        .column => .column,
        .column_reverse => .column_reverse,
    };
    s.flex_wrap = switch (cs.flex_wrap) {
        .nowrap => .nowrap,
        .wrap => .wrap,
        .wrap_reverse => .wrap_reverse,
    };
    s.flex_grow = cs.flex_grow;
    s.flex_shrink = cs.flex_shrink;
    s.flex_basis = switch (cs.flex_basis) {
        .lp => |lp| dimLp(lp),
        .min_content => .min_content,
        .max_content => .max_content,
        .fit_content => .fit_content,
        else => .auto,
    };
    s.align_items = alignOf(cs.align_items);
    s.align_self = alignOf(cs.align_self);
    s.align_content = alignOf(cs.align_content);
    s.justify_content = alignOf(cs.justify_content);
    s.justify_items = alignOf(cs.justify_items);
    s.justify_self = alignOf(cs.justify_self);
    if (s.display == .grid) {
        template(f, cs.grid_template_columns, &s.grid_template_columns, &s.grid_auto_repeat_columns);
        template(f, cs.grid_template_rows, &s.grid_template_rows, &s.grid_auto_repeat_rows);
        s.grid_auto_columns = tracks(f, cs.grid_auto_columns);
        s.grid_auto_rows = tracks(f, cs.grid_auto_rows);
        s.grid_auto_flow = if (cs.grid_auto_flow.column) (if (cs.grid_auto_flow.dense) .column_dense else .column) else (if (cs.grid_auto_flow.dense) .row_dense else .row);
    }
    s.grid_column = .{ .start = gridLine(cs.grid_column_start), .end = gridLine(cs.grid_column_end) };
    s.grid_row = .{ .start = gridLine(cs.grid_row_start), .end = gridLine(cs.grid_row_end) };
    return s;
}

fn mapOverflow(o: anytype) layout.style.Overflow {
    return switch (o) {
        .visible => .visible,
        .hidden => .hidden,
        .clip => .clip,
        .scroll, .auto => .scroll,
    };
}

test "writeNum" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var out: std.ArrayList(u8) = .empty;
    try writeNum(a, &out, 12.5);
    try out.append(a, ' ');
    try writeNum(a, &out, -0.015625);
    try out.append(a, ' ');
    try writeNum(a, &out, 300);
    try std.testing.expectEqualStrings("12.5 -0.015625 300", out.items);
}
