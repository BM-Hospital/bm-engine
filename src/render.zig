//! Render pipeline: source (JSON node tree | HTML) -> element model (dom.zig) -> cascade
//! (preset < presentation hints < Tailwind < stylesheet rules < inline style, `!important`
//! reversed per CSS) -> render nodes (inline runs merged into paragraphs, `::before`/`::after`
//! boxes) -> layout -> paint -> encode.
//!
//! Optional front-end modules (css, tw, html) are referenced only behind comptime `config` flags,
//! so a `-Dprofile=core` build does not link them.
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
const config = @import("config.zig");
const dom_mod = @import("dom.zig");
const css = @import("css/css.zig");
const twc = @import("tw/tw.zig");
const html = @import("html/html.zig");
const animate = @import("animate.zig");
const svgm = @import("svg/svg.zig");
const mx = @import("measure_xform.zig");

const Allocator = std.mem.Allocator;
pub const CS = style.ComputedStyle;
pub const none: u32 = std.math.maxInt(u32);
/// Maximum number of node nesting levels (takumi's MAXIMUM_DOM_TREE_DEPTH: 512 levels pass, 513 fail).
/// Every phase recurses per level on the 1 MiB wasm shadow stack. Measured on a ReleaseSafe build
/// (frames larger than the shipped ReleaseSmall ones; bench/probe/layout2/deep*.mjs): paint is the
/// limit at ~320-370 B per level (Painter.paintNode / paintBox) plus ~100-140 KB used once by the
/// rasterizer's fill path; JSON parsing ~144 B per level (json.Parser.value, two JSON levels per
/// node); a 512-level heavy tree renders + measures with a 384 KiB stack (>2.5x margin). Anonymous
/// line containers add layout levels: the layout engine's own 512-level limit then fails first.
pub const max_node_depth = 512;

/// The layout tree with the optional features selected in config.zig (tables / floats compile out;
/// a disabled table display lays out as a block, a disabled float as an in-flow block).
pub const LTree = layout.TreeWith(.{ .tables = config.enable_tables, .floats = config.enable_floats, .inline_row = true, .inline_fn = true });

pub const Error = error{ OutOfMemory, Invalid };

/// `anon_text`: anonymous paragraph leaf (merged inline runs of its parent block; `cs` = the block's).
/// `anon_box`: anonymous inline formatting context (layout `inline_row`) of a run of inline content that
/// contains inline-level boxes: its `para` holds the text with one object per box, its children are
/// those boxes (atomic inlines, floats and out-of-flow boxes met inside the text, in document order =
/// object id order); `cs` is an initial-value style inheriting from the block, so it paints nothing.
pub const Kind = enum(u8) { container, text, image, anon_text, anon_box };

pub const Node = struct {
    kind: Kind,
    cs: *const CS,
    /// source element (dom index; none for anonymous / generated boxes)
    el: u32 = none,
    parent: u32 = none,
    first_child: u32 = none,
    last_child: u32 = none,
    next: u32 = none,
    lid: u32 = none,
    para: ?*font.Paragraph = null,
    /// Line layout of `para` (see `Frame.textLayout`): the one the layout pass produced for inline
    /// content laid out in its formatting context (`tl_w` NaN), else the last one computed for the
    /// content width `tl_w`.
    tl: ?*const font.TextLayout = null,
    tl_w: f32 = 0,
    /// First entry of `Frame.inline_boxes` that belongs to `para` (`BoxFragment.box` is relative to it).
    box_base: u32 = 0,
    /// The node is an inline-level box inside an inline box (`<span>`) of its paragraph.
    in_inline_box: bool = false,
    img: ?*const raster.Pixmap = null,
    /// SVG image source: the document markup (per-render arena or renderer-owned image bytes,
    /// valid for the frame). `img` stays null; `img_w`/`img_h` hold its intrinsic size.
    svg: ?[]const u8 = null,
    /// intrinsic image size in device px (0 x 0 = no natural size)
    img_w: f32 = 0,
    img_h: f32 = 0,
    /// natural aspect ratio when there is no natural size (SVG with only a viewBox); 0 = none
    img_ratio: f32 = 0,
    /// image nodes: the `src` the image was resolved from (svg_out embeds the original bytes)
    src: ?[]const u8 = null,
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

/// Persistent colour-glyph raster (COLR / bitmap glyph rendered once per key; `pix` owned by
/// `Renderer.gpa`). The key is chosen by the painter (face, gid, size, foreground).
pub const ColorGlyphEntry = struct { pix: raster.Pixmap, ox: i32, oy: i32 };

/// An inline box (tagged inline element or generated box) enclosing text runs of a paragraph.
pub const InlineBox = struct { cs: *const CS, parent: u32 };

/// Iterates the painted runs of a line layout: maximal glyph sequences of one source run and one
/// face on one line, with their horizontal extent and baseline.
pub const RunIter = struct {
    tl: *const font.TextLayout,
    line: usize = 0,
    seg: usize = 0,
    gi: u32 = 0,

    pub const Run = struct { g0: u32, g1: u32, x0: f32, x1: f32, baseline: f32 };

    pub fn next(it: *RunIter) ?Run {
        const tl = it.tl;
        const gs = tl.glyphs;
        if (tl.segments.len > 0) {
            // (paragraphs with inline boxes / objects: exact segments from the text engine)
            while (it.seg < tl.segments.len) {
                const sg = tl.segments[it.seg];
                const end = @min(sg.g1, gs.len);
                if (it.gi < sg.g0) it.gi = sg.g0;
                if (it.gi >= end) {
                    it.seg += 1;
                    continue;
                }
                const g0 = it.gi;
                var ge = g0 + 1;
                while (ge < end and gs[ge].face == gs[g0].face) ge += 1;
                it.gi = ge;
                return .{ .g0 = g0, .g1 = ge, .x0 = if (g0 == sg.g0) sg.x0 else gs[g0].x, .x1 = if (ge < end) gs[ge].x else sg.x1, .baseline = sg.baseline };
            }
            return null;
        }
        while (it.line < tl.lines.len) {
            const line = tl.lines[it.line];
            const end = @min(line.glyph_end, gs.len);
            if (it.gi < line.glyph_start) it.gi = line.glyph_start;
            if (it.gi >= end) {
                it.line += 1;
                continue;
            }
            const g0 = it.gi;
            var ge = g0 + 1;
            while (ge < end and gs[ge].user == gs[g0].user and gs[ge].face == gs[g0].face) ge += 1;
            it.gi = ge;
            return .{ .g0 = g0, .g1 = ge, .x0 = gs[g0].x, .x1 = if (ge < end) gs[ge].x else @max(gs[g0].x, line.x + line.width), .baseline = line.baseline };
        }
        return null;
    }
};

pub const Format = enum { png, jpeg, webp, ico, raw };

/// `renderAnimation` output formats (takumi default: webp).
pub const AnimFormat = enum { webp, apng, gif };

/// How the `source` bytes of a render are interpreted (C ABI `kind` argument).
pub const SourceKind = enum(u8) { json = 0, html = 1 };

/// Render options (takumi `RenderOptions`). JSON-valued entries live in the per-call arena.
pub const Options = struct {
    width: ?u32 = null,
    height: ?u32 = null,
    format: Format = .png,
    quality: ?u8 = null,
    dpr: f32 = 1,
    /// `css`: array of stylesheet strings / takumi rule objects (or one string).
    css: ?json.Value = null,
    /// deprecated `stylesheets` (strings), used when `css` is absent.
    stylesheets: ?json.Value = null,
    /// deprecated `keyframes` option (KeyframesMap / KeyframesRuleList).
    keyframes: ?json.Value = null,
    /// root language (`:lang()` fallback for the root element).
    lang: []const u8 = "",
    /// root font-family fallback stack (used when the root sets no `font-family`).
    font_families: []const []const u8 = &.{},
    /// animation timeline position in ms (takumi: integer ms; default 0 = animations sampled at 0).
    time_ms: f32 = 0,
};

pub const Renderer = struct {
    gpa: Allocator,
    arena: bump.Bump,
    /// Short-lived scratch (hi-res glyph coverage), rewound after every glyph.
    scratch: bump.Bump,
    fonts: font.FontCollection = .{},
    font_blobs: std.ArrayList([]u8) = .empty,
    images: std.ArrayList(ImageEntry) = .empty,
    img_cache: std.ArrayList(CachedImage) = .empty,
    img_cache_bytes: usize = 0,
    rast: raster.Rasterizer,
    /// Glyph-mask cache. The key is 128 bits wide so a full 16-bit face id (variable-font
    /// instances are >= 0x8000) fits next to gid / size / subpixel phase / synthesis bits.
    glyphs: std.AutoHashMapUnmanaged(u128, GlyphMask) = .empty,
    glyph_bytes: usize = 0,
    /// Colour-glyph cache (cleared with `glyphs`; `color_glyph_bytes` counts against `glyph_budget`).
    color_glyphs: std.AutoHashMapUnmanaged(u64, ColorGlyphEntry) = .empty,
    color_glyph_bytes: usize = 0,
    /// `fonts.instanceEvictions()` at the last frame (glyph cache flushed when it changes).
    font_evictions: u32 = 0,
    /// Canvas pixels, kept between renders (so the per-render arena can be recycled before encoding).
    canvas: []u8 = &.{},
    result: []const u8 = "",
    err: []const u8 = "",
    err_buf: [256]u8 = undefined,
    /// Timeline position of the frame being rendered (animated image sources).
    time_ms: f32 = 0,
    /// Shape-plan cache (long-lived; plans reference font data: cleared with the fonts).
    shape_cache: font.ShapeCache,

    pub const glyph_budget: usize = 8 << 20;
    pub const image_budget: usize = 96 << 20;

    pub fn create(gpa: Allocator) ?*Renderer {
        const self = gpa.create(Renderer) catch return null;
        self.* = .{ .gpa = gpa, .arena = bump.Bump.init(gpa), .scratch = bump.Bump.init(gpa), .rast = raster.Rasterizer.init(gpa), .shape_cache = font.ShapeCache.init(gpa) };
        self.rast.levels16 = true;
        self.scratch.idle_limit = 255;
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
        self.color_glyphs.deinit(self.gpa);
        self.shape_cache.deinit();
        self.rast.deinit();
        self.gpa.free(self.canvas);
        self.scratch.deinit();
        self.arena.deinit();
        self.gpa.destroy(self);
    }

    pub fn setErr(self: *Renderer, prefix: []const u8, detail: []const u8) void {
        var n: usize = 0;
        for (prefix[0..@min(prefix.len, 128)]) |c| {
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
        if (comptime config.enable_color_fonts or config.enable_bitmap_glyphs) {
            var ci = self.color_glyphs.valueIterator();
            while (ci.next()) |g| g.pix.deinit(self.gpa);
            self.color_glyphs.clearRetainingCapacity();
            self.color_glyph_bytes = 0;
        }
    }

    fn clearImageCache(self: *Renderer) void {
        for (self.img_cache.items) |c| {
            c.pm.deinit(self.gpa);
            self.gpa.destroy(c.pm);
        }
        self.img_cache.clearRetainingCapacity();
        self.img_cache_bytes = 0;
    }

    /// Takes ownership of `data` (allocated with `gpa`): TTF/OTF/TTC (every face of a collection is
    /// registered) or, with WOFF support compiled in, WOFF/WOFF2 (decoded to sfnt, the container is
    /// freed). Returns takumi's `RegisteredFamily[]` JSON in the arena: `[{name, faces:[{weight, style,
    /// width, index}], weight, style}]` (`weight`/`style` of the first face kept for compatibility).
    pub fn registerFont(self: *Renderer, data_in: []u8, name: []const u8, weight: u16, italic: i32) Error![]const u8 {
        self.arena.reset();
        var data = data_in;
        if (comptime config.enable_woff) {
            const woff = @import("woff/woff.zig");
            switch (woff.sniff(data)) {
                .woff, .woff2 => {
                    const dec = woff.decode(self.gpa, data) catch |e| {
                        self.gpa.free(data);
                        if (e == error.OutOfMemory) return error.OutOfMemory;
                        self.setErr("invalid WOFF/WOFF2 font data", "");
                        return error.Invalid;
                    };
                    self.gpa.free(data);
                    data = dec;
                },
                else => {},
            }
        }
        const reg = self.fonts.registerAll(self.gpa, data, .{
            .family = if (name.len > 0) name else null,
            .weight = if (weight > 0) weight else null,
            .italic = if (italic < 0) null else italic != 0,
        }) catch |e| {
            self.gpa.free(data);
            switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnsupportedFontFormat => self.setErr("unsupported font format", ""),
                error.WoffContainer, error.Woff2Container => self.setErr("WOFF/WOFF2 fonts are not supported by this build", ""),
                else => self.setErr("invalid font data", ""),
            }
            return error.Invalid;
        };
        self.font_blobs.append(self.gpa, data) catch return error.OutOfMemory;
        // the families this call touched, in registration order
        const a = self.arena.allocator();
        const fams = self.fonts.families(a) catch return error.OutOfMemory;
        var out: std.ArrayList(u8) = .empty;
        try out.append(a, '[');
        var first = true;
        for (fams) |fam| {
            var touched = false;
            var k: u16 = 0;
            while (k < reg.count) : (k += 1) {
                if (std.ascii.eqlIgnoreCase(self.fonts.face(reg.first + k).family, fam.name)) touched = true;
            }
            if (!touched) continue;
            if (!first) try out.append(a, ',');
            first = false;
            try out.appendSlice(a, "{\"name\":");
            try writeJsonString(a, &out, fam.name);
            try out.appendSlice(a, ",\"faces\":[");
            for (fam.faces, 0..) |fc, i| {
                if (i != 0) try out.append(a, ',');
                try out.appendSlice(a, "{\"weight\":");
                try writeNum(a, &out, @floatFromInt(fc.weight));
                try out.appendSlice(a, if (fc.italic) ",\"style\":\"italic\"" else ",\"style\":\"normal\"");
                try out.appendSlice(a, ",\"width\":");
                try writeNum(a, &out, fc.width);
                try out.appendSlice(a, ",\"index\":");
                try writeNum(a, &out, @floatFromInt(fc.index));
                try out.append(a, '}');
            }
            try out.append(a, ']');
            if (fam.faces.len > 0) {
                try out.appendSlice(a, ",\"weight\":");
                try writeNum(a, &out, @floatFromInt(fam.faces[0].weight));
                try out.appendSlice(a, if (fam.faces[0].italic) ",\"style\":\"italic\"" else ",\"style\":\"normal\"");
            }
            try out.append(a, '}');
        }
        try out.append(a, ']');
        self.result = out.items;
        return self.result;
    }

    /// takumi `unregisterFont(family)`: removes every face of `family`; true when any was removed.
    pub fn unregisterFont(self: *Renderer, family: []const u8) bool {
        const any = self.fonts.unregisterFamily(self.gpa, family);
        if (any) {
            self.clearGlyphs();
            self.shape_cache.clear();
        }
        return any;
    }

    pub fn clearFonts(self: *Renderer) void {
        self.clearGlyphs();
        self.shape_cache.clear();
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
        self.fonts.beginFrame();
        // variable-font instance ids are recycled: cached glyph masks keyed by them go stale
        const ev = self.fonts.instanceEvictions();
        if (ev != self.font_evictions) {
            self.font_evictions = ev;
            self.clearGlyphs();
        }
        if (self.glyph_bytes + self.color_glyph_bytes > glyph_budget) self.clearGlyphs();
        if (self.img_cache_bytes > image_budget) self.clearImageCache();
    }

    /// Renders a JSON node tree (takumi `{json}` source).
    pub fn render(self: *Renderer, node_json: []const u8, opts_json: []const u8) Error![]const u8 {
        return self.renderSource(.json, node_json, opts_json);
    }

    /// Renders `source` (a JSON node tree or HTML markup) with the JSON options `opts_json`.
    pub fn renderSource(self: *Renderer, kind: SourceKind, source: []const u8, opts_json: []const u8) Error![]const u8 {
        self.beginCall();
        const a = self.arena.allocator();
        const opts = try self.parseOptions(opts_json);
        const pm = try self.renderPixels(.{ .kind = kind, .text = source }, opts);

        self.result = switch (opts.format) {
            .raw => pm.data,
            .png => codec.encodePng(a, pm.data, pm.width, pm.height, .{}) catch return error.OutOfMemory,
            .jpeg => codec.encodeJpeg(a, pm.data, pm.width, pm.height, .{ .quality = opts.quality orelse 75 }) catch return error.OutOfMemory,
            .webp => codec.encodeWebp(a, pm.data, pm.width, pm.height, .{}) catch return error.OutOfMemory,
            .ico => blk: {
                if (comptime !config.enable_extra_codecs) unreachable; // rejected by parseOptions
                if (pm.width > 256 or pm.height > 256) {
                    var buf: [64]u8 = undefined;
                    self.setErr("ICO images are 1 to 256 pixels on a side, not ", decimal(&buf, @max(pm.width, pm.height)));
                    return error.Invalid;
                }
                break :blk codec.encodeIco(a, pm.data, pm.width, pm.height) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => {
                        self.setErr("ICO encoding failed", "");
                        return error.Invalid;
                    },
                };
            },
        };
        return self.result;
    }

    /// A render source: text (JSON node tree / HTML) or an already parsed JSON node value
    /// (`renderAnimation` scenes; the value must outlive the call).
    pub const Source = struct { kind: SourceKind = .json, text: []const u8 = "", value: ?json.Value = null };

    /// Lays out and paints one frame into `self.canvas` and un-premultiplies it. The per-render
    /// arena is reset afterwards (everything of the layout / paint phase is dead), so `opts` must
    /// not reference it when the caller still needs them; scalar fields are fine.
    fn renderPixels(self: *Renderer, src: Source, opts: Options) Error!raster.Pixmap {
        const a = self.arena.allocator();
        self.time_ms = opts.time_ms;
        var f: Frame = .{ .r = self, .a = a, .opts = opts, .tree = LTree.init(a), .ctx = undefined, .pre = src.value };
        try f.prepare(src.kind, src.text);

        const need = @as(usize, f.canvas_w) * f.canvas_h * 4;
        if (self.canvas.len != need) {
            self.gpa.free(self.canvas);
            self.canvas = &.{};
            self.canvas = self.gpa.alloc(u8, need) catch return error.OutOfMemory;
        }
        @memset(self.canvas, 0);
        var pm: raster.Pixmap = .{ .width = f.canvas_w, .height = f.canvas_h, .data = self.canvas };
        try paint.paintFrame(&f, &pm);
        unpremultiply(pm.data);
        // Recycle the arena so the encoder reuses the same chunks instead of growing memory.
        self.arena.reset();
        return pm;
    }

    // ---- renderAnimation

    /// Upper bound of the raw frames kept for one `renderAnimation` call.
    pub const max_animation_bytes: usize = 512 << 20;

    /// takumi `renderAnimation`. `json_text`: `{scenes: [{node, durationMs}], width, height, fps,
    /// format?: "webp"|"apng"|"gif" (default webp), quality?, lossless? (ignored: webp is always
    /// lossless, like takumi-wasm), css?, stylesheets?, keyframes?, devicePixelRatio?,
    /// fontFamilies?, lang?}`; a scene `node` is a node object, an HTML string or `{json}`.
    /// Frame schedule (takumi-raster `frame_spans`): total = sum of durations, frame count =
    /// ceil(total * fps / 1000), frame i starts at floor(i * 1000 / fps) ms and lasts until the next
    /// start (clamped to total; zero-length frames dropped); a frame renders the scene active at its
    /// start with that scene's local time (time restarts per scene). Result in the arena.
    pub fn renderAnimation(self: *Renderer, json_text: []const u8) Error![]const u8 {
        if (comptime !config.enable_animation) {
            self.beginCall();
            self.setErr("renderAnimation is not supported by this build", "");
            return error.Invalid;
        }
        return self.renderAnimationImpl(json_text);
    }

    noinline fn renderAnimationImpl(self: *Renderer, json_text: []const u8) Error![]const u8 {
        self.beginCall();
        // the options + scenes live in their own arena for the whole call (the render arena is
        // recycled after every frame)
        var keep = bump.Bump.init(self.gpa);
        defer keep.deinit();
        const ka = keep.allocator();
        const v = json.parse(ka, json_text) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.JsonTooDeep => return self.invalid("node tree is nested too deeply"),
            else => return self.invalid("invalid animation options JSON"),
        };
        if (v != .object) return self.invalid("invalid animation options JSON");
        const opts = try self.optionsFrom(ka, v, true);
        const scenes_v = v.get("scenes") orelse return self.invalid("Expected at least one animation scene");
        if (scenes_v != .array or scenes_v.array.len == 0) return self.invalid("Expected at least one animation scene");
        const fps_n = (if (v.get("fps")) |x| x.asNumber() else null) orelse return self.invalid("missing field `fps`");
        if (!(fps_n >= 1)) return self.invalid("Expected fps to be greater than 0");
        const fps: u64 = @intFromFloat(@min(fps_n, 1.0e6));
        if (opts.width == null or opts.height == null) return self.invalid("renderAnimation needs `width` and `height`");
        var format: AnimFormat = .webp;
        if (v.get("format")) |fv| if (fv.asString()) |s| {
            if (std.mem.eql(u8, s, "webp")) format = .webp else if (std.mem.eql(u8, s, "apng")) format = .apng else if (std.mem.eql(u8, s, "gif")) format = .gif else {
                self.setErr("unsupported animation format: ", s);
                return error.Invalid;
            }
        };
        // takumi `AnimationFormat::max_fps`: GIF 20 ms, WebP / APNG 11 ms shortest frame
        const max_fps: u64 = if (format == .gif) 1000 / 20 else 1000 / 11;
        if (fps > max_fps) {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            var msg: [128]u8 = undefined;
            var n: usize = 0;
            for ([_][]const u8{ "Frame rate ", decimal(&b1, fps), " fps exceeds the maximum ", decimal(&b2, max_fps), " fps for this animation format" }) |part| {
                @memcpy(msg[n..][0..part.len], part);
                n += part.len;
            }
            self.setErr(msg[0..n], "");
            return error.Invalid;
        }

        // scenes
        const Scene = struct { src: Source, dur: u64 };
        const scenes = try ka.alloc(Scene, scenes_v.array.len);
        var total: u64 = 0;
        for (scenes_v.array, scenes) |sv, *sc| {
            const node = sv.get("node") orelse return self.invalid("animation scene is missing `node`");
            const d = (if (sv.get("durationMs")) |x| x.asNumber() else null) orelse return self.invalid("animation scene is missing `durationMs`");
            sc.dur = if (d >= 0 and d < 4.0e9) @intFromFloat(d) else 0;
            total += sc.dur;
            sc.src = switch (node) {
                .string => |s| .{ .kind = .html, .text = s },
                .object => if (node.get("type") == null and node.get("json") != null and node.get("json").? == .string)
                    .{ .kind = .json, .text = node.get("json").?.string }
                else
                    .{ .kind = .json, .value = node },
                else => return self.invalid("animation scene `node` must be a node, an HTML string or {json}"),
            };
        }
        if (total == 0) return self.invalid("Animation must contain at least one frame");
        const count = (total * fps + 999) / 1000;
        const w = opts.width.?;
        const h = opts.height.?;
        const frame_bytes = @as(usize, w) * h * 4;
        if (count > 1 << 20 or @as(u64, frame_bytes) * count > max_animation_bytes) return self.invalid("animation too large");

        var frames: std.ArrayList(codec.AnimFrame) = .empty;
        defer {
            for (frames.items) |fr| self.gpa.free(fr.rgba);
            frames.deinit(self.gpa);
        }
        try frames.ensureTotalCapacity(self.gpa, @intCast(count));
        var i: u64 = 0;
        while (i < count) : (i += 1) {
            const start = i * 1000 / fps;
            const end = @min((i + 1) * 1000 / fps, total);
            if (end <= start) continue;
            // scene active at `start` (clamped to the last ms), time restarting per scene
            const at = @min(start, total - 1);
            var elapsed: u64 = 0;
            var si: usize = 0;
            while (si + 1 < scenes.len and at >= elapsed + scenes[si].dur) : (si += 1) elapsed += scenes[si].dur;
            var fo = opts;
            fo.time_ms = @floatFromInt(at - elapsed);
            fo.format = .raw;
            // per-frame housekeeping (arena, font frame, glyph / image cache budgets)
            self.beginCall();
            const pm = try self.renderPixels(scenes[si].src, fo);
            if (pm.width != w or pm.height != h) return self.invalid("Animation frames must share the same dimensions");
            const copy = try self.gpa.dupe(u8, pm.data);
            frames.appendAssumeCapacity(.{ .rgba = copy, .delay_ms = @intCast(end - start) });
        }
        if (frames.items.len == 0) return self.invalid("Animation must contain at least one frame");
        // the canvas is not needed any more: give its memory back before encoding
        self.gpa.free(self.canvas);
        self.canvas = &.{};
        self.arena.reset();
        const a = self.arena.allocator();
        const eo: codec.AnimOptions = .{};
        const out = switch (format) {
            .webp => codec.encodeWebpAnim(a, frames.items, w, h, eo),
            .apng => codec.encodeApng(a, frames.items, w, h, eo),
            .gif => codec.encodeGif(a, frames.items, w, h, eo),
        } catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                if (format == .gif and (w > 65535 or h > 65535)) return self.invalid("GIF frame dimensions must be <= 65535x65535");
                return self.invalid("animation encoding failed");
            },
        };
        self.result = out;
        return self.result;
    }

    fn invalid(self: *Renderer, msg: []const u8) Error {
        self.setErr(msg, "");
        return error.Invalid;
    }

    pub fn measure(self: *Renderer, node_json: []const u8, opts_json: []const u8) Error![]const u8 {
        return self.measureSource(.json, node_json, opts_json);
    }

    pub fn measureSource(self: *Renderer, kind: SourceKind, source: []const u8, opts_json: []const u8) Error![]const u8 {
        self.beginCall();
        const a = self.arena.allocator();
        const opts = try self.parseOptions(opts_json);
        self.time_ms = opts.time_ms;
        var f: Frame = .{ .r = self, .a = a, .opts = opts, .tree = LTree.init(a), .ctx = undefined };
        try f.prepare(kind, source);
        var out: std.ArrayList(u8) = .empty;
        try f.writeMeasured(&out, f.root, .{});
        self.result = out.items;
        return self.result;
    }

    /// takumi `renderSvg`: the frame as a vector SVG document (UTF-8, in the arena; see svg_out.zig).
    /// `format` / `quality` options are ignored. Fails with a clear error when compiled out.
    pub fn renderSvg(self: *Renderer, kind: SourceKind, source: []const u8, opts_json: []const u8) Error![]const u8 {
        if (comptime !config.enable_render_svg) {
            self.beginCall();
            self.setErr("renderSvg is not supported by this build", "");
            return error.Invalid;
        }
        return self.renderSvgImpl(kind, source, opts_json);
    }

    noinline fn renderSvgImpl(self: *Renderer, kind: SourceKind, source: []const u8, opts_json: []const u8) Error![]const u8 {
        self.beginCall();
        const a = self.arena.allocator();
        var opts = try self.parseOptions(opts_json);
        // takumi `RenderOptions::svg`: SVG output always draws at a device pixel ratio of 1
        opts.dpr = 1;
        self.time_ms = opts.time_ms;
        var f: Frame = .{ .r = self, .a = a, .opts = opts, .tree = LTree.init(a), .ctx = undefined };
        try f.prepare(kind, source);
        var out: std.ArrayList(u8) = .empty;
        try @import("svg_out.zig").write(&f, &out);
        self.result = out.items;
        return self.result;
    }

    fn parseOptions(self: *Renderer, text: []const u8) Error!Options {
        if (text.len == 0) return .{};
        const v = json.parse(self.arena.allocator(), text) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.setErr("invalid options JSON", "");
                return error.Invalid;
            },
        };
        return self.optionsFrom(self.arena.allocator(), v, false);
    }

    /// Render options from a parsed JSON object (`a` holds the derived lists; it must live as
    /// long as `v`).
    fn optionsFrom(self: *Renderer, a: Allocator, v: json.Value, anim: bool) Error!Options {
        var o: Options = .{};
        if (v != .object) return o;
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
        if (!anim) if (v.get("format")) |fv| if (fv.asString()) |s| {
            if (std.mem.eql(u8, s, "png")) o.format = .png else if (std.mem.eql(u8, s, "jpeg") or std.mem.eql(u8, s, "jpg")) o.format = .jpeg else if (std.mem.eql(u8, s, "webp")) o.format = .webp else if (std.mem.eql(u8, s, "raw")) o.format = .raw else if (config.enable_extra_codecs and std.mem.eql(u8, s, "ico")) o.format = .ico else {
                self.setErr("unsupported format: ", s);
                return error.Invalid;
            }
        };
        if (v.get("css")) |x| if (x != .null) {
            o.css = x;
        };
        if (v.get("stylesheets")) |x| if (x != .null) {
            o.stylesheets = x;
        };
        if (v.get("keyframes")) |x| if (x != .null) {
            o.keyframes = x;
        };
        if (v.get("lang")) |x| if (x.asString()) |s| {
            o.lang = s;
        };
        if (v.get("timeMs")) |x| if (x.asNumber()) |n| {
            o.time_ms = if (n >= 0 and n < 1.0e15) @floor(n) else 0;
        };
        if (v.get("fontFamilies")) |x| switch (x) {
            .string => |s| {
                const l = try a.alloc([]const u8, 1);
                l[0] = s;
                o.font_families = l;
            },
            .array => |arr| {
                const l = try a.alloc([]const u8, arr.len);
                var n: usize = 0;
                for (arr) |e| if (e.asString()) |s| {
                    l[n] = s;
                    n += 1;
                };
                o.font_families = l[0..n];
            },
            else => {},
        };
        // `lossless` (webp is always lossless, like takumi-wasm), `drawDebugBorder` and `dithering`
        // are accepted and ignored.
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
    /// Animated GIF / WebP / APNG sources show the frame at the render's `timeMs` (looping over
    /// the animation's total duration, like takumi `AnimatedSource::frame_at_time`) when
    /// animation support and the animated decoders are compiled in; otherwise their first frame.
    /// SVG sources resolve to null here (see `resolveSvg`).
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
        if (comptime config.enable_animation and config.enable_extra_codecs) {
            if (raw == null and self.time_ms > 0) {
                if (self.animatedFrame(key, bytes)) |pm| return pm;
            }
        }
        if (self.cacheLookup(key, 0, 0)) |pm| return pm;

        var pm: raster.Pixmap = undefined;
        if (raw) |e| {
            pm = raster.Pixmap.init(self.gpa, e.width, e.height) catch return null;
            @memcpy(pm.data, bytes);
            if (!e.premultiplied) premultiply(pm.data);
        } else {
            if (codec.sniff(bytes) == .unknown) return null; // SVG, text, unsupported formats
            const img = codec.decodeEx(self.gpa, bytes, .{ .max_pixels = max_image_pixels }, codec.build_decoders) catch return null;
            premultiply(img.data);
            pm = .{ .width = img.width, .height = img.height, .data = img.data };
        }
        return self.cacheStore(key, 0, 0, pm) orelse {
            pm.deinit(self.gpa);
            return null;
        };
    }

    /// Largest decoded image: one image may fill the whole decoded-image cache budget.
    pub const max_image_pixels: u64 = image_budget / 4;

    /// Frame of an animated source shown at `self.time_ms` (null: still image / frame 0 / error,
    /// the caller then decodes normally). Cached per (content, frame index).
    noinline fn animatedFrame(self: *Renderer, key: u64, bytes: []const u8) ?*const raster.Pixmap {
        const n = codec.frameCount(bytes);
        if (n <= 1) return null;
        const limits: codec.Limits = .{ .max_pixels = max_image_pixels };
        // pass 1: frame delays -> total loop duration -> frame index
        var delays: std.ArrayList(u32) = .empty;
        defer delays.deinit(self.gpa);
        {
            var an = codec.anim.Animator.init(self.gpa, bytes, limits) catch return null;
            defer an.deinit();
            while (an.next() catch return null) |d| delays.append(self.gpa, d) catch return null;
        }
        var total: u64 = 0;
        for (delays.items) |d| total += d;
        if (total == 0 or delays.items.len <= 1) return null;
        const target = @as(u64, @intFromFloat(self.time_ms)) % total;
        var idx: u32 = @intCast(delays.items.len - 1);
        var acc: u64 = 0;
        for (delays.items, 0..) |d, k| {
            acc += d;
            if (target < acc) {
                idx = @intCast(k);
                break;
            }
        }
        if (idx == 0) return null;
        const fkey = key ^ (@as(u64, idx) *% 0x9E3779B97F4A7C15);
        if (self.cacheLookup(fkey, 0, 0)) |pm| return pm;
        const fr = codec.decodeFrame(self.gpa, bytes, idx, limits) catch return null;
        premultiply(fr.image.data);
        var pm: raster.Pixmap = .{ .width = fr.image.width, .height = fr.image.height, .data = fr.image.data };
        return self.cacheStore(fkey, 0, 0, pm) orelse {
            pm.deinit(self.gpa);
            return null;
        };
    }

    /// SVG markup behind an image `src` / `url()`: inline markup (takumi: a string that starts like
    /// `<svg`), a `data:` URI (base64 or percent-encoded, decoded into the per-render arena) or an
    /// `images` option entry, when the bytes sniff as SVG. null when SVG support is compiled out.
    /// The slice is valid for the current render.
    pub fn resolveSvg(self: *Renderer, src: []const u8) ?[]const u8 {
        if (comptime !config.enable_svg) return null;
        if (std.mem.startsWith(u8, src, "data:")) {
            const b = decodeDataUri(self.arena.allocator(), src) orelse return null;
            return if (svgm.looksLikeSvg(b)) b else null;
        }
        if (svgm.looksLikeSvg(src)) return src;
        const e = self.findImage(src) orelse return null;
        if (e.width != 0) return null;
        return if (svgm.looksLikeSvg(e.data)) e.data else null;
    }

    /// Alias of `resolveSvg` (the name paint_svg.zig probes for).
    pub fn svgSource(self: *Renderer, src: []const u8) ?[]const u8 {
        return self.resolveSvg(src);
    }

    /// Catmull-Rom (or, `nearest`, nearest-neighbour) downscaled variant of a cached image (cached as well).
    pub fn resampled(self: *Renderer, src: *const raster.Pixmap, tw: u32, th: u32, nearest: bool) *const raster.Pixmap {
        if (tw == 0 or th == 0 or (tw >= src.width and th >= src.height)) return src;
        var w = @min(tw, src.width);
        var h = @min(th, src.height);
        if (nearest) {
            // takumi `DecodeTarget::covering`: one uniform scale covering the box, never upscaling
            const sw: f32 = @floatFromInt(src.width);
            const sh: f32 = @floatFromInt(src.height);
            const s = @min(1.0, @max(@as(f32, @floatFromInt(tw)) / sw, @as(f32, @floatFromInt(th)) / sh));
            w = @intFromFloat(std.math.clamp(@round(sw * s), 1, sw));
            h = @intFromFloat(std.math.clamp(@round(sh * s), 1, sh));
            if (w >= src.width and h >= src.height) return src;
        }
        const key = @as(u64, @intFromPtr(src.data.ptr)) ^ @as(u64, if (nearest) 0x51ed270b27a4f1c3 else 0x9e3779b97f4a7c15);
        if (self.cacheLookup(key, w, h)) |pm| return pm;
        const pm = (if (nearest) raster.resampleNearest(self.gpa, src, w, h) else raster.resample(self.gpa, src, w, h)) catch return src;
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

pub const SvgSize = struct { w: f32, h: f32, ratio: f32 };

/// Root `width` / `height` attribute of an SVG image source in CSS px, resolved like takumi's
/// image sizing: font-relative units against 12 px (em, rem) / 6 px (ex), absolute units at
/// 96 dpi; percentages and anything else = not specified.
fn svgLength(attr: ?[]const u8) ?f32 {
    const s = std.mem.trim(u8, attr orelse return null, " \t\r\n\x0c");
    const r = json.parseNumber(s) orelse return null;
    const v: f32 = @floatCast(r.value);
    const u = s[r.len..];
    const k: f32 = if (u.len == 0 or std.ascii.eqlIgnoreCase(u, "px")) 1 else if (std.ascii.eqlIgnoreCase(u, "em") or std.ascii.eqlIgnoreCase(u, "rem")) 12 else if (std.ascii.eqlIgnoreCase(u, "ex")) 6 else if (std.ascii.eqlIgnoreCase(u, "pt")) 4.0 / 3.0 else if (std.ascii.eqlIgnoreCase(u, "pc")) 16 else if (std.ascii.eqlIgnoreCase(u, "in")) 96 else if (std.ascii.eqlIgnoreCase(u, "cm")) 96.0 / 2.54 else if (std.ascii.eqlIgnoreCase(u, "mm")) 96.0 / 25.4 else if (std.ascii.eqlIgnoreCase(u, "q")) 96.0 / 101.6 else return null;
    const px = v * k;
    return if (px > 0 and px < 1.0e7) px else null;
}

/// Natural size (device px) and ratio of an SVG image source, mirroring takumi (EMPIRICAL,
/// bench/probe/anim/svgsize*.mjs): width + height -> that size; one of them + a viewBox -> the
/// other from the viewBox ratio; one of them without a viewBox -> the other defaults to 300 / 150
/// (no natural ratio); only a viewBox -> no natural size, ratio only; nothing -> 300 x 150.
pub fn svgSizeFrom(w_attr: ?f32, h_attr: ?f32, view_box: ?[4]f32, dpr: f32) SvgSize {
    var vr: f32 = 0;
    if (view_box) |vb| {
        if (vb[2] > 0 and vb[3] > 0) vr = vb[2] / vb[3];
    }
    if (w_attr) |w| {
        if (h_attr) |h| return .{ .w = w * dpr, .h = h * dpr, .ratio = w / h };
        if (vr > 0) return .{ .w = w * dpr, .h = w / vr * dpr, .ratio = vr };
        return .{ .w = w * dpr, .h = 150 * dpr, .ratio = 0 };
    }
    if (h_attr) |h| {
        if (vr > 0) return .{ .w = h * vr * dpr, .h = h * dpr, .ratio = vr };
        return .{ .w = 300 * dpr, .h = h * dpr, .ratio = 0 };
    }
    if (vr > 0) return .{ .w = 0, .h = 0, .ratio = vr };
    return .{ .w = 300 * dpr, .h = 150 * dpr, .ratio = 0 };
}

fn svgIntrinsic(doc: *const svgm.Document, dpr: f32) SvgSize {
    const root = doc.root();
    return svgSizeFrom(svgLength(root.attr("width")), svgLength(root.attr("height")), svgm.intrinsicSize(doc).view_box, dpr);
}

/// Decimal text of `n` in `buf` (no std.fmt).
fn decimal(buf: []u8, n_in: u64) []const u8 {
    var n = n_in;
    var i: usize = buf.len;
    while (true) {
        i -= 1;
        buf[i] = @intCast('0' + n % 10);
        n /= 10;
        if (n == 0 or i == 0) break;
    }
    return buf[i..];
}

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

fn hexDigit(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

/// RFC 3986 percent-decoding of a non-base64 `data:` payload (malformed escapes kept literally).
/// Returns `payload` itself when it holds no escape.
fn percentDecode(a: Allocator, payload: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, payload, '%') == null) return payload;
    const out = a.alloc(u8, payload.len) catch return null;
    var n: usize = 0;
    var i: usize = 0;
    while (i < payload.len) : (i += 1) {
        const c = payload[i];
        if (c == '%' and i + 2 < payload.len) {
            if (hexDigit(payload[i + 1])) |h| if (hexDigit(payload[i + 2])) |l| {
                out[n] = h * 16 + l;
                n += 1;
                i += 2;
                continue;
            };
        }
        out[n] = c;
        n += 1;
    }
    return out[0..n];
}

/// Payload bytes of a `data:` URI (base64 decoded, or percent-decoded), in `a`.
fn decodeDataUri(a: Allocator, src: []const u8) ?[]const u8 {
    const comma = std.mem.indexOfScalar(u8, src, ',') orelse return null;
    const meta = src[5..comma];
    const payload = src[comma + 1 ..];
    if (!std.ascii.endsWithIgnoreCase(meta, ";base64")) return percentDecode(a, payload);
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

/// `,"transform":[a,b,c,d,e,f]` of a measured node (exact f32 values).
fn writeAffine(a: Allocator, out: *std.ArrayList(u8), t: mx.Affine) Error!void {
    try out.appendSlice(a, ",\"transform\":[");
    for ([6]f32{ t.a, t.b, t.c, t.d, t.e, t.f }, 0..) |v, i| {
        if (i > 0) try out.append(a, ',');
        try mx.writeExact(a, out, v);
    }
    try out.append(a, ']');
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
    tree: LTree,
    nodes: std.ArrayList(Node) = .empty,
    /// TextStyle.user -> style of the run (colour, decorations)
    run_styles: std.ArrayList(*const CS) = .empty,
    lid_node: std.ArrayList(u32) = .empty,
    root: u32 = none,
    lroot: u32 = none,
    canvas_w: u32 = 0,
    canvas_h: u32 = 0,
    /// Source elements (JSON or HTML) with their computed styles.
    dom: dom_mod.Dom = .{},
    /// Generated boxes (`::before` / `::after`, and the own text of a text element that has them).
    pseudos: std.ArrayList(Pseudo) = .empty,
    /// Stylesheet rules are active (selector matching runs for every element).
    css_on: bool = false,
    cssx: CssState = .{},
    /// Already parsed JSON node tree (renderAnimation scenes); used instead of the source text.
    pre: ?json.Value = null,
    /// `lang` of the element being built (nearest ancestor's, else the `lang` option).
    cur_lang: []const u8 = "",
    /// Inline boxes (tagged inline elements and generated boxes whose runs join a paragraph),
    /// parents before children; `parent` = enclosing inline box index or `none`.
    inline_boxes: std.ArrayList(InlineBox) = .empty,
    /// Per run (`TextStyle.user`, parallel to `run_styles`): innermost inline box or `none`.
    run_box: std.ArrayList(u32) = .empty,
    /// Innermost inline box while collecting runs (`none` outside of one).
    cur_box: u32 = none,
    /// While collecting the runs of a paragraph: its first inline box, and the inline-level boxes met
    /// so far (built as children of the paragraph's node once it exists).
    box_base: u32 = 0,
    pend_objs: std.ArrayList(PendingObj) = .empty,
    /// A line layout could not be allocated during the layout pass.
    layout_oom: bool = false,
    /// The inputs mention a Tailwind theme variable (`--color-*`, `--spacing`, `--breakpoint-*`, ...):
    /// `tw` compiles with theme lookups (else every utility keeps its built-in value).
    tw_theme: bool = false,
    /// Computed style of the root element once styled (`--breakpoint-*` lookups).
    tw_root_cs: ?*const CS = null,

    pub const Pseudo = struct { cs: *const CS, text: []const u8 };

    const CssState = if (config.enable_css) struct {
        m: css.Matcher = .{},
        scratch: css.Scratch = undefined,
        decls: std.ArrayList(css.Declaration) = .empty,
        vt: css.Dom = undefined,
    } else struct {};

    fn fail(f: *Frame, msg: []const u8, detail: []const u8) Error {
        f.r.setErr(msg, detail);
        return error.Invalid;
    }

    /// Keyframes of `name` from the stylesheet (`@keyframes`) or the deprecated `keyframes` option;
    /// null when undefined or when CSS support is compiled out. For the animation pass.
    pub fn keyframes(f: *const Frame, name: []const u8) ?[]const css.Keyframe {
        if (comptime !config.enable_css) return null;
        return css.keyframes(&f.cssx.m, name);
    }

    fn prepare(f: *Frame, kind: SourceKind, source: []const u8) Error!void {
        const o = f.opts;
        f.ctx = .{
            .dpr = o.dpr,
            .viewport_w = if (o.width) |w| @floatFromInt(w) else 0,
            .viewport_h = if (o.height) |h| @floatFromInt(h) else 0,
            .root_font_size = 16 * o.dpr,
        };
        f.dom = .{ .lang = o.lang, .max_depth = max_node_depth };
        switch (kind) {
            .json => {
                const v = f.pre orelse json.parse(f.a, source) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.JsonTooDeep => return f.fail("node tree is nested too deeply", ""),
                    else => return f.fail("invalid node JSON", ""),
                };
                f.dom.fromJson(f.a, v) catch |e| return f.domError(e);
            },
            .html => {
                if (comptime !config.enable_html) return f.fail("HTML input is not supported by this build", "");
                const doc = html.parse(f.a, source) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.TooDeep => return f.fail("node tree is nested too deeply", ""),
                };
                f.dom.fromHtml(f.a, html, &doc) catch |e| return f.domError(e);
            },
        }
        if (comptime config.enable_css) {
            try f.prepareCss();
        } else if (nonEmpty(o.css) or nonEmpty(o.stylesheets)) {
            return f.fail("the `css` option is not supported by this build", "");
        }
        if (comptime config.enable_tw) if (hasThemeVar(source)) {
            f.tw_theme = true;
        };
        try f.styleTree(f.dom.root, null, 0);
        f.cur_lang = o.lang;
        f.root = try f.buildElement(f.dom.root, none, 0);

        // The layout root is the root element itself; the available size is the initial containing
        // block (the engine resolves the root's percentages, margins and fixed boxes against it). Like
        // takumi, a relative offset or auto margins of the root move nothing. An out-of-flow root is
        // placed by its insets inside an explicit initial containing block node (one more layout
        // level, so such a tree reaches the layout engine's depth limit one level earlier).
        const rcs = f.nodes.items[f.root].cs;
        const lr = try f.buildLayout(f.root);
        f.lroot = lr;
        if (rcs.position == .absolute or rcs.position == .fixed) {
            var icb: layout.Style = .{ .display = .block };
            if (o.width) |w| icb.size[0] = .{ .px = @floatFromInt(w) };
            if (o.height) |h| icb.size[1] = .{ .px = @floatFromInt(h) };
            f.lroot = f.tree.addNode(icb) catch return error.OutOfMemory;
            f.tree.appendChild(f.lroot, lr) catch return error.OutOfMemory;
        }
        const avail: [2]layout.AvailableSpace = .{
            if (o.width) |w| .{ .definite = @floatFromInt(w) } else .max_content,
            if (o.height) |h| .{ .definite = @floatFromInt(h) } else .max_content,
        };
        f.tree.compute(f.lroot, avail, f, measureCb, .{ .quantize64 = true, .baseline = baselineCb, .inline_fn = inlineCb }) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return f.fail("node tree is nested too deeply", ""),
        };
        if (f.layout_oom) return error.OutOfMemory;
        const rl = f.tree.layout(lr);
        const cw: f32 = if (o.width) |w| @floatFromInt(w) else @floor(rl.x + rl.w + rl.margin.right + 0.5);
        const ch: f32 = if (o.height) |h| @floatFromInt(h) else @floor(rl.y + rl.h + rl.margin.bottom + 0.5);
        if (!(cw >= 1) or !(ch >= 1)) return f.fail("invalid viewport: content has zero size and no width/height was given", "");
        if (cw > 16384 or ch > 16384 or cw * ch > 40.0e6) return f.fail("canvas too large", "");
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

    fn domError(f: *Frame, e: dom_mod.Error) Error {
        return switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            error.Invalid => f.fail(f.dom.err_msg, f.dom.err_detail),
        };
    }

    fn nonEmpty(v: ?json.Value) bool {
        const x = v orelse return false;
        return switch (x) {
            .array => |arr| arr.len > 0,
            .string => |s| s.len > 0,
            .null => false,
            else => true,
        };
    }

    // ---- stylesheet (css option + HTML <style>)

    noinline fn prepareCss(f: *Frame) Error!void {
        if (comptime !config.enable_css) return;
        const a = f.a;
        const o = f.opts;
        var buf: std.ArrayList(u8) = .empty;
        // takumi: every `css` entry (or the deprecated `stylesheets` when `css` is absent) written out
        // as CSS text and concatenated, followed by the HTML source's <style> texts; parsed once.
        if (o.css orelse o.stylesheets) |list| switch (list) {
            .array => |arr| for (arr) |e| {
                if (e == .null) continue;
                css.writeCssInput(a, &buf, e) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidRule => return f.fail("invalid css rule object", ""),
                };
            },
            .string => |s| try buf.appendSlice(a, s),
            else => return f.fail("the `css` option must be an array", ""),
        };
        for (f.dom.styles) |s| try buf.appendSlice(a, s);
        if (comptime config.enable_tw) if (hasThemeVar(buf.items)) {
            f.tw_theme = true;
        };
        var sheet: css.Stylesheet = .{};
        if (buf.items.len > 0) try css.parse(a, buf.items, &sheet);
        if (comptime config.enable_animation) if (o.keyframes) |k| css.addKeyframesJson(a, &sheet, k) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidRule => return f.fail("invalid keyframes option", ""),
        };
        if (sheet.rules.items.len == 0 and sheet.keyframes.items.len == 0 and sheet.extra_keyframes.items.len == 0 and !sheet.preflight) return;
        const st = &f.cssx;
        st.m = try css.prepare(a, &sheet, .{
            .viewport_w = if (o.width) |w| @floatFromInt(w) else null,
            .viewport_h = if (o.height) |h| @floatFromInt(h) else null,
            .dpr = o.dpr,
            .supports = cssSupports,
        });
        st.scratch = css.Scratch.init(a);
        st.vt = CssDom.vtable(&f.dom);
        f.css_on = st.m.rules.len > 0;
    }

    fn cssSupports(name: []const u8, value: []const u8) bool {
        _ = value;
        if (name.len > 2 and name[0] == '-' and name[1] == '-') return true;
        return style.propertyId(name) != null;
    }

    /// Matched declarations of element `i` (or its pseudo-element) as style declarations, in cascade
    /// order with `important` flags (the style module orders normal < important itself).
    /// Matched stylesheet declarations with takumi's layer split points (indices into `decls`).
    const CssOut = struct { decls: []const style.Declaration = &.{}, unlayered: usize = 0, important: usize = 0, imp_layered: usize = 0 };

    fn cssDecls(f: *Frame, i: u32, pseudo: css.Pseudo, sets_content: ?*bool) Error!CssOut {
        const st = &f.cssx;
        st.decls.clearRetainingCapacity();
        const r = try css.match(&st.m, &st.scratch, &st.vt, i, pseudo, &st.decls);
        if (sets_content) |p| p.* = r.sets_content;
        return .{ .decls = try convertDecls(f.a, st.decls.items), .unlayered = r.unlayered_start, .important = r.important_start, .imp_layered = r.layered_important_start };
    }

    /// Room for preset, presentation hints, the six author parts, inline style and a keyframe layer.
    const max_layers = 10;

    /// Appends the author origin in takumi's cascade order (matching.rs `layer_order`): normal
    /// declarations of named `@layer`s < `tw` utilities < unlayered rules; `!important` ones
    /// unlayered < `tw` < named layers. (`tw` lists its normal declarations first.)
    fn authorLayers(layers: []style.Layer, n: *usize, tw: []const style.Declaration, c: CssOut) void {
        var k: usize = 0;
        while (k < tw.len and !tw[k].important) k += 1;
        const d = c.decls;
        const parts = [_][]const style.Declaration{ d[0..c.unlayered], tw[0..k], d[c.unlayered..c.important], d[c.important..c.imp_layered], tw[k..], d[c.imp_layered..] };
        for (parts) |p| if (p.len > 0) {
            layers[n.*] = .{ .decls = p, .lenient = true };
            n.* += 1;
        };
    }

    /// Tailwind declarations of element `i` for `target` (lenient layer).
    /// Theme lookups for `tw` (takumi `TwVarRef`): a variable is defined for element `i` when its
    /// parent's computed style has it, or the element's own inline style / matched rules declare it.
    const TwTheme = struct {
        f: *Frame,
        i: u32,
        own: []const style.Declaration,

        fn defined(ctx: *const anyopaque, name: []const u8) bool {
            const t: *const TwTheme = @ptrCast(@alignCast(ctx));
            const el = t.f.dom.at(t.i);
            if (el.parent != none) if (t.f.dom.at(el.parent).cs.customProperty(name) != null) return true;
            for (t.own) |d| if (std.mem.eql(u8, d.name, name)) return true;
            return switch (el.style) {
                .json => |v| v.get(name) != null,
                .text => |s| std.mem.indexOf(u8, s, name) != null,
                .none => false,
            };
        }

        fn breakpoint(ctx: *const anyopaque, token: []const u8) ?[]const u8 {
            const t: *const TwTheme = @ptrCast(@alignCast(ctx));
            const root = t.f.tw_root_cs orelse return null;
            var buf: [96]u8 = undefined;
            const pre = "--breakpoint-";
            if (token.len > buf.len - pre.len) return null;
            @memcpy(buf[0..pre.len], pre);
            @memcpy(buf[pre.len..][0..token.len], token);
            return root.customProperty(buf[0 .. pre.len + token.len]);
        }
    };

    /// Whether `text` mentions a Tailwind theme variable namespace (`--color-`, `--spacing`, ...).
    fn hasThemeVar(text: []const u8) bool {
        const prefixes = [_][]const u8{ "color-", "spacing", "radius-", "text-", "font-", "tracking-", "leading-", "aspect-", "container-", "animate-", "breakpoint-" };
        var k: usize = 0;
        while (std.mem.indexOfPos(u8, text, k, "--")) |p| {
            k = p + 2;
            for (prefixes) |pr| if (std.mem.startsWith(u8, text[k..], pr)) return true;
        }
        return false;
    }

    fn twDecls(f: *Frame, i: u32, target: twc.Target, own_css: []const style.Declaration) Error![]const style.Declaration {
        const el = f.dom.at(i);
        var env: twc.Env = .{ .viewport_w = f.ctx.viewport_w, .viewport_h = f.ctx.viewport_h, .dpr = f.opts.dpr, .target = target };
        // every variant contains ':'; only then is the structural information needed
        if (std.mem.indexOfScalar(u8, el.tw, ':') != null) {
            const info = f.dom.elementInfo(i);
            env.element = .{ .index = info.index, .count = info.count, .type_index = info.type_index, .type_count = info.type_count, .empty = info.empty };
        }
        var th: TwTheme = .{ .f = f, .i = i, .own = own_css };
        const theme: twc.Theme = .{ .ctx = &th, .defined = TwTheme.defined, .breakpoint = TwTheme.breakpoint };
        if (f.tw_theme) env.theme = &theme;
        var out: std.ArrayList(twc.Declaration) = .empty;
        twc.compile(f.a, el.tw, env, &out) catch return error.OutOfMemory;
        return convertDecls(f.a, out.items);
    }

    // ---- style pass: every element's style exactly once, top-down

    fn styleTree(f: *Frame, i: u32, parent_cs: ?*const CS, depth: u32) Error!void {
        if (depth >= max_node_depth) return f.fail("node tree is nested too deeply", "");
        try f.styleElement(i, parent_cs);
        const cs = f.dom.at(i).cs;
        if (parent_cs == null) f.tw_root_cs = cs;
        var c = f.dom.at(i).first;
        while (c != none) : (c = f.dom.at(c).next) try f.styleTree(c, cs, depth + 1);
    }

    fn styleFail(f: *Frame, e: style.Error, diag: *const style.Diagnostics) Error {
        return switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidStyleValue => f.fail("invalid value for style property ", diag.property),
        };
    }

    fn jsonOf(s: dom_mod.Src) ?json.Value {
        return switch (s) {
            .json => |v| v,
            else => null,
        };
    }

    /// Declarations of a preset / inline-style source and whether the layer is lenient.
    fn srcLayer(f: *Frame, s: dom_mod.Src, diag: *style.Diagnostics) Error!style.Layer {
        return switch (s) {
            .none => .{ .decls = &.{} },
            .json => |v| .{ .decls = style.jsonDecls(f.a, v, diag) catch |e| return f.styleFail(e, diag) },
            // CSS-text sources only come from HTML input
            .text => |t| if (comptime config.enable_html) .{ .decls = try parseBlock(f.a, t), .lenient = true } else .{ .decls = &.{} },
        };
    }

    /// Cascade layers of element `i`: preset (UA) < presentation hints < tw utilities < stylesheet
    /// rules < inline style. Returns the count written to `layers` (room for one extra layer).
    fn elementLayers(f: *Frame, i: u32, diag: *style.Diagnostics, layers: *[max_layers]style.Layer) Error!usize {
        const a = f.a;
        const el = f.dom.at(i);
        var n: usize = 0;
        layers[n] = try f.srcLayer(el.preset, diag);
        n += 1;
        if (el.pres.len > 0 or el.dir != .none) {
            var list: std.ArrayList(style.Declaration) = .empty;
            if (comptime config.enable_html) if (el.pres.len > 0) try list.appendSlice(a, try parseBlock(a, el.pres));
            if (el.dir != .none) try list.append(a, .{ .name = "direction", .value = if (el.dir == .rtl) "rtl" else "ltr" });
            layers[n] = .{ .decls = list.items, .lenient = true };
            n += 1;
        }
        const cs_out: CssOut = if (comptime config.enable_css) (if (f.css_on) try f.cssDecls(i, .none, null) else .{}) else .{};
        const tw: []const style.Declaration = if (comptime config.enable_tw) (if (el.tw.len > 0) try f.twDecls(i, .element, cs_out.decls) else &.{}) else &.{};
        authorLayers(layers, &n, tw, cs_out);
        layers[n] = try f.srcLayer(el.style, diag);
        n += 1;
        return n;
    }

    /// Applies the element's CSS animations at `opts.time_ms` to `cs` in place (see animate.zig).
    noinline fn animateElement(f: *Frame, i: u32, cs: *CS, parent_cs: ?*const CS) Error!void {
        const Host = struct {
            f: *Frame,
            i: u32,
            parent: ?*const CS,
            pub fn keyframes(h: @This(), name: []const u8) ?[]const css.Keyframe {
                return h.f.keyframes(name);
            }
            /// The element's style with `decls` as the top (lenient) layer.
            pub fn keyframeStyle(h: @This(), decls: []const style.Declaration) Error!*const CS {
                var diag: style.Diagnostics = .{};
                var layers: [max_layers]style.Layer = undefined;
                var n = try h.f.elementLayers(h.i, &diag, &layers);
                layers[n] = .{ .decls = decls, .lenient = true };
                n += 1;
                const out = try h.f.a.create(CS);
                out.* = style.computeLayers(h.f.a, &h.f.ctx, h.parent, layers[0..n], &diag) catch |e| return h.f.styleFail(e, &diag);
                return out;
            }
            /// The element's style with its font size forced to `px` (device px; animated font-size).
            pub fn fontSizeStyle(h: @This(), px: f32) Error!*const CS {
                var txt: std.ArrayList(u8) = .empty;
                try writeNum(h.f.a, &txt, px / h.f.opts.dpr);
                try txt.appendSlice(h.f.a, "px");
                const decls = [1]style.Declaration{.{ .name = "font-size", .value = txt.items, .important = true }};
                return h.keyframeStyle(&decls);
            }
        };
        const r = animate.apply(f.a, cs, f.opts.time_ms, Host{ .f = f, .i = i, .parent = parent_cs }) catch |e| return e;
        if (r) |x| cs.* = x.*;
    }

    noinline fn styleElement(f: *Frame, i: u32, parent_cs: ?*const CS) Error!void {
        const a = f.a;
        const el = f.dom.at(i);
        var diag: style.Diagnostics = .{};
        if (comptime !config.enable_tw) if (el.tw.len > 0) return f.fail("Tailwind (`tw`) is not supported by this build", "");
        const cs = try a.create(CS);
        const has_tw = config.enable_tw and el.tw.len > 0;
        const from_html = config.enable_html and (el.preset == .text or el.style == .text or el.pres.len > 0);
        const general = !el.run and (f.css_on or has_tw or from_html or el.dir != .none);
        if (!general) {
            // fast path (JSON source, no stylesheet, no tw): exactly the phase-1 computation
            cs.* = style.compute(a, &f.ctx, parent_cs, jsonOf(el.preset), jsonOf(el.style), &diag) catch |e| return f.styleFail(e, &diag);
        } else {
            var layers: [max_layers]style.Layer = undefined;
            const n = try f.elementLayers(i, &diag, &layers);
            cs.* = style.computeLayers(a, &f.ctx, parent_cs, layers[0..n], &diag) catch |e| return f.styleFail(e, &diag);
        }
        // CSS animations sampled at `timeMs`, before the children inherit from this style
        if (comptime config.enable_animation) if (!el.run and cs.animation_name.len > 0) try f.animateElement(i, cs, parent_cs);
        if (parent_cs == null) {
            if (f.opts.font_families.len > 0 and cs.font_family.len == 0) cs.font_family = f.opts.font_families;
            f.ctx.root_font_size = cs.font_size;
        }
        el.cs = cs;
        if (el.run or el.kind == .image) return;
        if (comptime config.enable_css or config.enable_tw) {
            el.before = try f.pseudoBox(i, .before);
            el.after = try f.pseudoBox(i, .after);
            if (el.kind == .text and (el.before != none or el.after != none)) {
                // the element's own text moves into an anonymous box between the generated ones
                const own = try a.create(CS);
                own.* = style.compute(a, &f.ctx, cs, null, null, &diag) catch |e| return f.styleFail(e, &diag);
                try f.pseudos.append(a, .{ .cs = own, .text = el.text });
                el.own = @intCast(f.pseudos.items.len - 1);
            }
        }
    }

    /// Creates the `::before` / `::after` box of element `i` when a stylesheet rule or a Tailwind
    /// `before:` / `after:` utility sets `content` to something other than none/normal.
    fn pseudoBox(f: *Frame, i: u32, which: enum { before, after }) Error!u32 {
        const el = f.dom.at(i);
        var layers: [6]style.Layer = undefined;
        var n: usize = 0;
        var tw: []const style.Declaration = &.{};
        if (comptime config.enable_tw) {
            const key = if (which == .before) "before:" else "after:";
            if (el.tw.len > 0 and std.mem.indexOf(u8, el.tw, key) != null) tw = try f.twDecls(i, if (which == .before) .before else .after, &.{});
        }
        var cs_out: CssOut = .{};
        if (comptime config.enable_css) if (f.css_on and (if (which == .before) f.cssx.m.has_before else f.cssx.m.has_after)) {
            var sets = false;
            const d = try f.cssDecls(i, if (which == .before) .before else .after, &sets);
            if (sets) cs_out = d;
        };
        authorLayers(&layers, &n, tw, cs_out);
        if (n == 0) return none;
        var diag: style.Diagnostics = .{};
        const pcs = try f.a.create(CS);
        pcs.* = style.computeLayers(f.a, &f.ctx, el.cs, layers[0..n], &diag) catch |e| return f.styleFail(e, &diag);
        if (pcs.display == .none) return none;
        const text = (try dom_mod.contentText(f.a, pcs.content, &f.dom, i)) orelse return none;
        try f.pseudos.append(f.a, .{ .cs = pcs, .text = text });
        return @intCast(f.pseudos.items.len - 1);
    }

    // ---- render nodes

    /// A child item of a box: a source element, or a generated box (index into `pseudos`).
    const Item = union(enum) { el: u32, ps: u32 };

    /// An inline-level box met while collecting the runs of a paragraph (object id = its index).
    const PendingObj = struct { item: Item, lang: []const u8, boxed: bool };

    /// Iterates `::before`, own text (text elements with generated content), children, `::after`.
    const Items = struct {
        f: *const Frame,
        el: u32,
        stage: u8 = 0,
        cur: u32 = none,

        fn next(it: *Items) ?Item {
            const e = it.f.dom.at(it.el);
            while (true) switch (it.stage) {
                0 => {
                    it.stage = 1;
                    if (e.before != none) return .{ .ps = e.before };
                },
                1 => {
                    it.stage = 2;
                    it.cur = e.first;
                    if (e.own != none) return .{ .ps = e.own };
                },
                2 => {
                    if (it.cur != none) {
                        const c = it.cur;
                        it.cur = it.f.dom.at(c).next;
                        return .{ .el = c };
                    }
                    it.stage = 3;
                },
                3 => {
                    it.stage = 4;
                    if (e.after != none) return .{ .ps = e.after };
                },
                else => return null,
            };
        }
    };

    fn hasGenerated(el: *const dom_mod.El) bool {
        return el.before != none or el.after != none;
    }

    /// True when the item joins its parent's paragraph as text / an inline box: inline, in flow, and
    /// (for boxes) holding only inline-level content. With `objects` (the paragraph is in a block
    /// container) that content may include inline-level boxes (`objectKind`).
    fn isInlineLevel(f: *const Frame, item: Item, depth: u32, objects: bool) bool {
        switch (item) {
            .ps => |p| return inFlowInline(f.pseudos.items[p].cs),
            .el => |i| {
                const el = f.dom.at(i);
                if (depth > 64 or !inFlowInline(el.cs)) return false;
                if (el.run) return true;
                switch (el.kind) {
                    .image => return false,
                    .text => if (!hasGenerated(el)) return true,
                    .container => {},
                }
                // (an empty inline box is inline content too: it adds no run, like takumi's empty spans)
                var it: Items = .{ .f = f, .el = i };
                while (it.next()) |c| {
                    if (f.isInlineLevel(c, depth + 1, objects)) continue;
                    if (objects and f.objectKind(c) != null) continue;
                    if (f.itemStyle(c).display == .none) continue;
                    return false;
                }
                return true;
            },
        }
    }

    fn hasInlineEdges(cs: *const CS) bool {
        const bw = cs.usedBorderWidths();
        for ([2]usize{ 1, 3 }) |k| {
            if (bw[k] > 0 or cs.padding[k].resolve(0) != 0) return true;
            switch (cs.margin[k]) {
                .lp => |lp| if (lp.resolve(0) != 0) return true,
                else => {},
            }
        }
        return false;
    }

    fn itemStyle(f: *const Frame, item: Item) *const CS {
        return switch (item) {
            .ps => |p| f.pseudos.items[p].cs,
            .el => |i| f.dom.at(i).cs,
        };
    }

    /// The kind of inline-level BOX an item is inside a paragraph (null = not one): an out-of-flow
    /// box (static position at its place in the text), a float, or an atomic inline.
    fn objectKind(f: *const Frame, item: Item) ?font.Object.Kind {
        const cs = f.itemStyle(item);
        if (cs.display == .none) return null;
        if (cs.position == .absolute or cs.position == .fixed) return .out_of_flow;
        if (cs.float != .none) return if (config.enable_floats) .float else null;
        return if (f.isAtomic(item)) .atomic else null;
    }

    /// Does the item put anything on a line (text that survives white-space collapsing, an atomic
    /// inline)? A run of children without any generates no paragraph.
    fn hasLineContent(f: *const Frame, item: Item, depth: u32) bool {
        if (f.objectKind(item)) |k| return k == .atomic;
        switch (item) {
            .ps => |p| {
                const ps = f.pseudos.items[p];
                if (ps.cs.white_space_collapse != .collapse) return ps.text.len > 0;
                for (ps.text) |c| if (!isSpace(c)) return true;
                return hasInlineEdges(ps.cs);
            },
            .el => |i| {
                const el = f.dom.at(i);
                if (el.cs.display == .none or depth > 64) return false;
                // (an inline box with inline edges makes a line even when it is empty)
                if (!el.run and el.tag.len > 0 and hasInlineEdges(el.cs)) return true;
                if (el.kind == .text and !hasGenerated(el)) {
                    if (el.tag.len == 2 and std.ascii.eqlIgnoreCase(el.tag, "br")) return true;
                    if (el.cs.white_space_collapse != .collapse) return el.text.len > 0;
                    for (el.text) |c| if (!isSpace(c)) return true;
                    return false;
                }
                var it: Items = .{ .f = f, .el = i };
                while (it.next()) |c| {
                    if (f.hasLineContent(c, depth + 1)) return true;
                }
                return false;
            },
        }
    }

    /// takumi `participates_in_inflow_inline_formatting_context` after an in-flow child; floats and
    /// out-of-flow boxes keep `prev`.
    fn afterInline(f: *const Frame, item: Item, prev: bool) bool {
        const cs = f.itemStyle(item);
        if (cs.display == .none or cs.position == .absolute or cs.position == .fixed or cs.float != .none) return prev;
        return switch (cs.display) {
            .@"inline", .inline_block, .inline_flex, .inline_grid, .inline_table, .webkit_inline_box => true,
            else => false,
        };
    }

    fn inFlowInline(cs: *const CS) bool {
        // (a float is blockified)
        return cs.display == .@"inline" and cs.position != .absolute and cs.position != .fixed and cs.float == .none;
    }

    /// Atomic inline-level box (inline-block / -flex / -grid / -table, or an image with an inline
    /// display, takumi's default for images): in a block container it becomes an item of an
    /// anonymous line container (`Kind.anon_box`) instead of being blockified.
    fn isAtomic(f: *const Frame, item: Item) bool {
        var image = false;
        const cs = switch (item) {
            .ps => |p| f.pseudos.items[p].cs,
            .el => |i| blk: {
                const el = f.dom.at(i);
                image = el.kind == .image;
                break :blk el.cs;
            },
        };
        if (cs.position == .absolute or cs.position == .fixed or cs.float != .none) return false;
        return switch (cs.display) {
            .inline_block, .inline_flex, .inline_grid, .inline_table, .webkit_inline_box => true,
            .@"inline" => image,
            else => false,
        };
    }

    /// Block containers lay inline-level children out on lines; flex / grid containers blockify
    /// them and table boxes other than cells / captions wrap them in anonymous cells (layout engine).
    fn hasLines(d: style.computed.Display) bool {
        return switch (d) {
            .flex, .inline_flex, .grid, .inline_grid, .none => false,
            .table, .inline_table, .table_row, .table_row_group, .table_header_group, .table_footer_group, .table_column, .table_column_group => !config.enable_tables,
            else => true,
        };
    }

    /// Text elements with a flex / grid / table display become a box holding their text as an
    /// anonymous leaf: takumi lays the text out as an anonymous flex / grid item (aligned by the
    /// container, reported by measure() as a child box); a measured leaf could not be aligned inside a
    /// cell by `vertical-align` either.
    fn needsTextBox(d: style.computed.Display) bool {
        return switch (d) {
            .flex, .inline_flex, .grid, .inline_grid => true,
            .table, .inline_table, .table_row, .table_row_group, .table_header_group, .table_footer_group, .table_cell, .table_caption => config.enable_tables,
            else => false,
        };
    }

    /// Collapsible white-space-only text (takumi `is_collapsible_whitespace_only_text_node`): a bare
    /// run, or with `elements` also a text element (class / style / tw ...), never `<br>`.
    fn isBlankText(f: *const Frame, item: Item, elements: bool) bool {
        const i = switch (item) {
            .el => |i| i,
            .ps => return false,
        };
        const el = f.dom.at(i);
        if (el.kind != .text or el.own != none or el.cs.white_space_collapse != .collapse) return false;
        if (!el.run and (!elements or std.ascii.eqlIgnoreCase(el.tag, "br"))) return false;
        for (el.text) |c| if (c != ' ' and c != '\n' and c != '\t' and c != '\r' and c != 0x0c) return false;
        return true;
    }

    noinline fn buildPseudo(f: *Frame, p: u32, parent: u32) Error!u32 {
        const ps = f.pseudos.items[p];
        const id = try f.addNode(.{ .kind = .text, .cs = ps.cs, .parent = parent });
        f.nodes.items[id].para = try f.soloParagraph(ps.text, ps.cs);
        return id;
    }

    /// Paragraph of a text box of its own: one run, no inline boxes.
    noinline fn soloParagraph(f: *Frame, text: []const u8, cs: *const CS) Error!*font.Paragraph {
        const saved_base = f.box_base;
        const saved_box = f.cur_box;
        defer {
            f.box_base = saved_base;
            f.cur_box = saved_box;
        }
        f.box_base = @intCast(f.inline_boxes.items.len);
        f.cur_box = none;
        var runs: [1]font.Run = .{try f.makeRun(text, cs)};
        return f.makeParagraph(&runs, cs);
    }

    fn buildItem(f: *Frame, item: Item, parent: u32, depth: u32) Error!void {
        switch (item) {
            .el => |c| _ = try f.buildElement(c, parent, depth),
            .ps => |p| _ = try f.buildPseudo(p, parent),
        }
    }

    fn buildElement(f: *Frame, i: u32, parent: u32, depth: u32) Error!u32 {
        if (depth >= max_node_depth) return f.fail("node tree is nested too deeply", "");
        const el = f.dom.at(i);
        const saved_lang = f.cur_lang;
        defer f.cur_lang = saved_lang;
        if (el.lang.len > 0) f.cur_lang = el.lang;
        const cs = el.cs;
        switch (el.kind) {
            .text => if (!hasGenerated(el)) return if (needsTextBox(cs.display)) f.buildTextBox(i, parent) else f.buildText(i, parent),
            .image => return f.buildImage(i, parent),
            else => {},
        }
        const id = try f.addNode(.{ .kind = .container, .cs = cs, .el = i, .parent = parent });
        const inline_ctx = switch (cs.display) {
            .flex, .inline_flex, .grid, .inline_grid => false,
            else => true,
        };
        const lines = hasLines(cs.display);
        // The children are split into runs of consecutive ones that take part in one inline formatting
        // context: inline-level content and, in a block container, the inline-level boxes, floats and
        // out-of-flow boxes among it (Blink's MakeChildrenNonInline). A run with line content becomes a
        // paragraph; in a run without any, floats and out-of-flow boxes stay children of the block.
        var it: Items = .{ .f = f, .el = i };
        var run_start = it;
        var run_len: u32 = 0;
        var run_content = false;
        // takumi `drop_collapsible_boundary_whitespace`: white-space-only text (bare or a text element)
        // not preceded by in-flow inline content generates nothing.
        var after_inline = cs.display == .@"inline";
        while (true) {
            const before = it;
            const c = it.next();
            var drop = false;
            if (c) |x| {
                drop = !after_inline and f.isBlankText(x, true);
                if (!drop) after_inline = f.afterInline(x, after_inline);
            }
            if (drop and run_len == 0) continue;
            var joins = false;
            if (c) |x| {
                if (inline_ctx) {
                    joins = f.isInlineLevel(x, 0, lines) or (lines and f.objectKind(x) != null);
                    if (joins and !run_content) run_content = f.hasLineContent(x, 0);
                }
            }
            if (joins) {
                if (run_len == 0) run_start = before;
                run_len += 1;
                continue;
            }
            if (run_len > 0) {
                try f.buildInlineRun(run_start, run_len, run_content, cs, id, depth);
                run_len = 0;
                run_content = false;
            }
            const x = c orelse break;
            // white-space-only text between boxes generates nothing
            if (drop or f.isBlankText(x, !inline_ctx)) continue;
            try f.buildItem(x, id, depth + 1);
        }
        return id;
    }

    /// Builds the `count` children starting at `start_it` that form one inline formatting context
    /// of block `parent` (style `cs`).
    noinline fn buildInlineRun(f: *Frame, start_it: Items, count: u32, content: bool, cs: *const CS, parent: u32, depth: u32) Error!void {
        var it = start_it;
        var k: u32 = 0;
        if (!content) {
            // no line box: only the boxes are built
            while (k < count) : (k += 1) {
                const c = it.next() orelse break;
                if (f.objectKind(c) != null) try f.buildItem(c, parent, depth + 1);
            }
            return;
        }
        var pending: std.ArrayList(font.Run) = .empty;
        const saved_base = f.box_base;
        const saved_box = f.cur_box;
        const saved_objs = f.pend_objs;
        defer {
            f.box_base = saved_base;
            f.cur_box = saved_box;
            f.pend_objs = saved_objs;
        }
        f.box_base = @intCast(f.inline_boxes.items.len);
        f.cur_box = none;
        f.pend_objs = .empty;
        while (k < count) : (k += 1) {
            const c = it.next() orelse break;
            try f.collectRuns(c, &pending, depth + 1, cs);
        }
        const objs = f.pend_objs.items;
        if (objs.len == 0) return f.flushRuns(&pending, cs, parent);
        // inline-level boxes: an anonymous inline formatting context holding them as children
        const id = try f.openAnonBox(cs, parent);
        // (the paragraph's own properties are the block's: alignment, wrapping, clamping)
        f.nodes.items[id].para = try f.makeParagraph(pending.items, cs);
        const lang = f.cur_lang;
        defer f.cur_lang = lang;
        f.cur_box = none;
        for (objs) |o| {
            f.cur_lang = o.lang;
            const first: u32 = @intCast(f.nodes.items.len);
            try f.buildItem(o.item, id, depth + 1);
            if (first < f.nodes.items.len) f.nodes.items[first].in_inline_box = o.boxed;
        }
    }

    fn isSpace(c: u8) bool {
        return c == ' ' or c == '\n' or c == '\t' or c == '\r' or c == 0x0c;
    }

    /// Text element with a table display: a box (the cell) holding its text as an anonymous leaf.
    noinline fn buildTextBox(f: *Frame, i: u32, parent: u32) Error!u32 {
        const el = f.dom.at(i);
        const id = try f.addNode(.{ .kind = .container, .cs = el.cs, .el = i, .parent = parent });
        const t = try f.addNode(.{ .kind = .anon_text, .cs = el.cs, .parent = id });
        f.nodes.items[t].para = try f.soloParagraph(el.text, el.cs);
        return id;
    }
    /// Text element without generated content: one paragraph. (Out of line: keeps the run and the
    /// paragraph options out of buildElement's recursive stack frame.)
    noinline fn buildText(f: *Frame, i: u32, parent: u32) Error!u32 {
        const el = f.dom.at(i);
        const id = try f.addNode(.{ .kind = .text, .cs = el.cs, .el = i, .parent = parent });
        f.nodes.items[id].para = try f.soloParagraph(el.text, el.cs);
        return id;
    }

    /// Image element: raster pixmap (decoded, cached) or SVG markup with its intrinsic size.
    noinline fn buildImage(f: *Frame, i: u32, parent: u32) Error!u32 {
        const el = f.dom.at(i);
        var cs = el.cs;
        {
            var img: ?*const raster.Pixmap = null;
            var svg_src: ?[]const u8 = null;
            if (el.src) |src| {
                img = f.r.resolveImage(src);
                if (comptime config.enable_svg) if (img == null) {
                    svg_src = f.r.resolveSvg(src);
                };
            }
            // `width` / `height` attributes act as a low-priority size preset.
            const wa = el.width;
            const ha = el.height;
            if ((wa != null and cs.width == .auto) or (ha != null and cs.height == .auto)) {
                const m = try f.a.create(CS);
                m.* = cs.*;
                if (wa != null and m.width == .auto) m.width = .{ .lp = .{ .px = wa.? * f.opts.dpr } };
                if (ha != null and m.height == .auto) m.height = .{ .lp = .{ .px = ha.? * f.opts.dpr } };
                cs = m;
            }
            var n: Node = .{ .kind = .image, .cs = cs, .el = i, .parent = parent, .img = img, .src = el.src };
            if (img) |pm| {
                n.img_w = @as(f32, @floatFromInt(pm.width)) * f.opts.dpr;
                n.img_h = @as(f32, @floatFromInt(pm.height)) * f.opts.dpr;
                n.img_ratio = n.img_w / n.img_h;
            } else if (comptime config.enable_svg) if (svg_src) |s| {
                if (svgm.parse(f.a, s)) |doc| {
                    n.svg = s;
                    const sz = svgIntrinsic(&doc, f.opts.dpr);
                    n.img_w = sz.w;
                    n.img_h = sz.h;
                    n.img_ratio = sz.ratio;
                } else |e| if (e == error.OutOfMemory) return error.OutOfMemory;
            };
            return f.addNode(n);
        }
    }

    /// Anonymous inline formatting context node of block `parent` (style `cs`). Out of line: the
    /// computed style temporary must not sit in the recursive frame of `buildInlineRun`.
    noinline fn openAnonBox(f: *Frame, cs: *const CS, parent: u32) Error!u32 {
        var diag: style.Diagnostics = .{};
        const rcs = try f.a.create(CS);
        rcs.* = style.compute(f.a, &f.ctx, cs, null, null, &diag) catch |e| return f.styleFail(e, &diag);
        return f.addNode(.{ .kind = .anon_box, .cs = rcs, .parent = parent, .box_base = f.box_base });
    }

    /// The collected runs (a run of children with line content, see `hasLineContent`) as a paragraph leaf.
    noinline fn flushRuns(f: *Frame, pending: *std.ArrayList(font.Run), cs: *const CS, parent: u32) Error!void {
        if (pending.items.len == 0) return;
        defer pending.* = .empty;
        const id = try f.addNode(.{ .kind = .anon_text, .cs = cs, .parent = parent, .box_base = f.box_base });
        f.nodes.items[id].para = try f.makeParagraph(pending.items, cs);
    }

    /// `pcs`: style of the enclosing inline box (or of the block), for the items that are boxes.
    fn collectRuns(f: *Frame, item: Item, out: *std.ArrayList(font.Run), depth: u32, pcs: *const CS) Error!void {
        if (depth >= max_node_depth) return f.fail("node tree is nested too deeply", "");
        if (f.objectKind(item)) |kind| return f.appendObject(out, item, kind, pcs);
        switch (item) {
            .ps => |p| {
                const ps = f.pseudos.items[p];
                if (ps.cs.display == .none) return;
                const saved = f.cur_box;
                defer f.cur_box = saved;
                try f.openInlineBox(ps.cs);
                try f.appendRun(out, ps.text, ps.cs, false);
            },
            .el => |i| {
                const el = f.dom.at(i);
                if (el.cs.display == .none) return;
                const saved = f.cur_box;
                defer f.cur_box = saved;
                // a real (tagged) element is an inline box; bare text nodes are not
                const br = el.tag.len == 2 and std.ascii.eqlIgnoreCase(el.tag, "br");
                const boxed = !el.run and el.tag.len > 0 and !br;
                if (boxed) try f.openInlineBox(el.cs);
                if (el.kind == .text and !hasGenerated(el)) return f.appendRun(out, el.text, el.cs, br);
                const before = out.items.len;
                var it: Items = .{ .f = f, .el = i };
                while (it.next()) |c| try f.collectRuns(c, out, depth + 1, el.cs);
                // (an empty inline box still has its edges)
                if (boxed and out.items.len == before) try f.appendRun(out, "", el.cs, false);
            },
        }
    }

    /// An inline-level box inside the paragraph being collected: an object run now, its node later.
    noinline fn appendObject(f: *Frame, out: *std.ArrayList(font.Run), item: Item, kind: font.Object.Kind, pcs: *const CS) Error!void {
        const cs = f.itemStyle(item);
        const id: u32 = @intCast(f.pend_objs.items.len);
        // (inside an inline box that generates box fragments: border, background, padding, margin)
        var boxed = false;
        var bx = f.cur_box;
        while (bx != none and bx >= f.box_base and bx < f.inline_boxes.items.len) : (bx = f.inline_boxes.items[bx].parent) {
            const bcs = f.inline_boxes.items[bx].cs;
            if (hasInlineEdges(bcs) or bcs.resolveColor(bcs.background_color).a != 0 or bcs.background_image.len > 0) boxed = true;
        }
        try f.pend_objs.append(f.a, .{ .item = item, .lang = f.cur_lang, .boxed = boxed });
        const inline_level = switch (cs.display) {
            .@"inline", .inline_block, .inline_flex, .inline_grid, .inline_table, .webkit_inline_box => true,
            else => false,
        };
        try out.append(f.a, .{
            .text = "",
            .white_space = whiteSpaceOf(pcs),
            .box = if (f.cur_box != none and f.cur_box >= f.box_base) f.cur_box - f.box_base else font.no_box,
            .object = .{ .id = id, .kind = kind, .valign = f.valignOf(cs), .block_level = !inline_level },
        });
    }

    /// `vertical-align` for the text engine (a percentage refers to the element's own line-height).
    fn valignOf(f: *const Frame, cs: *const CS) font.VerticalAlign {
        return switch (cs.vertical_align) {
            .baseline => .baseline,
            .sub => .sub,
            .super => .super,
            .top => .top,
            .middle => .middle,
            .bottom => .bottom,
            .text_top => .text_top,
            .text_bottom => .text_bottom,
            .lp => |lp| blk: {
                var v = lp.px;
                if (lp.pct != 0 or lp.calc != null) {
                    const st = strutFrom(emMetrics(&f.r.fonts, cs), cs.font_size, cs.line_height);
                    v = lp.resolve(st[0] + st[1]);
                }
                break :blk if (v == 0 or !std.math.isFinite(v)) .baseline else .{ .length = v };
            },
        };
    }

    /// Pushes an inline box nested in the current one and makes it current.
    noinline fn openInlineBox(f: *Frame, cs: *const CS) Error!void {
        try f.inline_boxes.append(f.a, .{ .cs = cs, .parent = f.cur_box });
        f.cur_box = @intCast(f.inline_boxes.items.len - 1);
    }

    /// Appends the run of a text element (HTML `<br>`: an empty run ending in a forced break, in
    /// every white-space mode). Out of line so collectRuns' recursive frame stays small.
    noinline fn appendRun(f: *Frame, out: *std.ArrayList(font.Run), text: []const u8, cs: *const CS, br: bool) Error!void {
        if (br) {
            var r = try f.makeRun("", cs);
            r.hard_break_after = true;
            return out.append(f.a, r);
        }
        try out.append(f.a, try f.makeRun(text, cs));
    }

    fn whiteSpaceOf(cs: *const CS) font.WhiteSpace {
        return switch (cs.white_space_collapse) {
            .collapse => if (cs.text_wrap_mode == .nowrap) .nowrap else .normal,
            .preserve, .preserve_spaces => if (cs.text_wrap_mode == .nowrap) .pre else .pre_wrap,
            .preserve_breaks => .pre_line,
            .break_spaces => .pre_wrap,
        };
    }

    /// The inline boxes `f.inline_boxes[f.box_base..]` for the text engine: font / line-height strut,
    /// `vertical-align` and inline edges (margin + border + padding; percentages count as 0, like
    /// takumi), on the 1/64 px grid.
    noinline fn paragraphBoxes(f: *Frame) Error![]const font.InlineBox {
        const src = f.inline_boxes.items[@min(f.box_base, f.inline_boxes.items.len)..];
        if (src.len == 0) return &.{};
        const out = try f.a.alloc(font.InlineBox, src.len);
        for (src, out) |ib, *o| {
            const cs = ib.cs;
            const bw = cs.usedBorderWidths();
            var edge: [2]f32 = undefined;
            var mar: [2]f32 = undefined;
            // (sides 3 = left, 1 = right)
            for ([2]usize{ 3, 1 }, 0..) |side, k| {
                const m: f32 = switch (cs.margin[side]) {
                    .lp => |lp| lp.resolve(0),
                    else => 0,
                };
                mar[k] = @trunc(m * 64) / 64;
                edge[k] = mar[k] + @trunc(bw[side] * 64) / 64 + @trunc(@max(cs.padding[side].resolve(0), 0) * 64) / 64;
            }
            const rtl = cs.direction == .rtl;
            o.* = .{
                .parent = if (ib.parent == none or ib.parent < f.box_base) font.no_box else ib.parent - f.box_base,
                .style = textStyle(cs, 0),
                .line_height = switch (cs.line_height) {
                    .normal => .normal,
                    .number => |n| .{ .multiple = n },
                    .px => |p| .{ .px = p },
                },
                .valign = f.valignOf(cs),
                .start = edge[@intFromBool(rtl)],
                .end = edge[@intFromBool(!rtl)],
                .margin_start = mar[@intFromBool(rtl)],
                .margin_end = mar[@intFromBool(!rtl)],
                .clone = cs.box_decoration_break == .clone,
                .decorated = cs.resolveColor(cs.background_color).a != 0 or cs.background_image.len > 0 or bw[0] > 0 or bw[1] > 0 or bw[2] > 0 or bw[3] > 0,
            };
        }
        return out;
    }

    noinline fn makeRun(f: *Frame, text: []const u8, cs: *const CS) Error!font.Run {
        try f.run_styles.append(f.a, cs);
        try f.run_box.append(f.a, f.cur_box);
        var st = textStyle(cs, @intCast(f.run_styles.items.len - 1));
        // font-variant-* / font-kerning / font-feature-settings as OpenType features
        const feats = try cs.fontFeatures(f.a);
        if (feats.len > 0) {
            const out = try f.a.alloc(font.FeatureSetting, feats.len);
            for (feats, out) |x, *o| o.* = .{ .tag = x.tag, .value = @intCast(@min(x.value, 0xFFFF)) };
            st.features = out;
        }
        return .{
            .text = try transformText(f.a, text, cs.text_transform),
            .style = st,
            .white_space = whiteSpaceOf(cs),
            .box = if (f.cur_box != none and f.cur_box >= f.box_base) f.cur_box - f.box_base else font.no_box,
        };
    }

    noinline fn makeParagraph(f: *Frame, runs: []const font.Run, cs: *const CS) Error!*font.Paragraph {
        const ws = whiteSpaceOf(cs);
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
            .ellipsis = cs.text_overflow != .clip and clip,
            .ellipsis_text = if (cs.text_overflow == .string) cs.text_overflow_string else null,
            .clamp_text = if (cs.block_ellipsis == .string) cs.block_ellipsis_string else null,
            .clamp_no_ellipsis = cs.block_ellipsis == .none,
            .strut = textStyle(cs, 0),
            .direction = if (cs.direction == .rtl) .rtl else .ltr,
            .lang = f.cur_lang,
            .text_wrap = switch (cs.text_wrap_style) {
                .balance => .balance,
                .pretty => .pretty,
                .auto, .stable => .wrap,
            },
            .shape_cache = &f.r.shape_cache,
            .boxes = try f.paragraphBoxes(),
        };
        const p = try f.a.create(font.Paragraph);
        p.* = font.Paragraph.initWith(.{ .complex = config.enable_complex_text, .color_emoji = config.enable_color_fonts or config.enable_bitmap_glyphs }, f.a, &f.r.fonts, runs, opts) catch return error.OutOfMemory;
        return p;
    }

    // ---- layout tree

    /// Layout node of render node `id` (style mapped, measured leaves flagged). Kept out of the
    /// recursion: `layout.Style` is large and would otherwise sit in every level's stack frame.
    noinline fn layoutNode(f: *Frame, id: u32) Error!struct { lid: u32, ordered: bool, leaf: bool } {
        const n = f.nodes.items[id];
        var st: layout.Style = switch (n.kind) {
            // (anonymous inline content: shortens beside floats)
            .anon_text => .{ .display = .block, .is_inline_content = true },
            .anon_box => .{ .display = .inline_row, .position = .static, .is_inline_content = true },
            else => mapStyle(f, n.cs),
        };
        const leaf = n.kind == .text or n.kind == .image or n.kind == .anon_text;
        if (leaf and st.display != .none) st.display = .block;
        // (a block of text: its lines shorten beside floats)
        if (n.kind == .text and (n.cs.display == .block or n.cs.display == .@"inline")) st.is_inline_content = true;
        if (n.kind == .image and st.aspect_ratio == null and n.img_ratio > 0) st.aspect_ratio = n.img_ratio;
        if (n.el != none) {
            if (comptime config.enable_tables) tableSpans(&f.dom, n.el, &st);
            if (n.parent != none and (st.grid_column.start == .auto or st.grid_column.end == .auto or st.grid_row.start == .auto or st.grid_row.end == .auto)) {
                const pcs = f.nodes.items[n.parent].cs;
                if (pcs.display == .grid or pcs.display == .inline_grid) gridNames(pcs, n.cs, &st);
            }
        }
        // the root element establishes a block formatting context (its margins never collapse with
        // its children's)
        if (id == f.root) st.flow_root = true;
        const lid = f.tree.addNode(st) catch return error.OutOfMemory;
        f.nodes.items[id].lid = lid;
        while (f.lid_node.items.len <= lid) try f.lid_node.append(f.a, none);
        f.lid_node.items[lid] = id;
        if (leaf) f.tree.setMeasured(lid, true);
        return .{ .lid = lid, .ordered = st.display == .flex or st.display == .grid, .leaf = leaf };
    }

    /// Children of `id` in `order` order (stable), or null when document order applies.
    noinline fn orderedChildren(f: *Frame, id: u32, ordered: bool) Error!?[]const u32 {
        if (!ordered) return null;
        var needs_order = false;
        var c = f.nodes.items[id].first_child;
        while (c != none) : (c = f.nodes.items[c].next) {
            if (f.nodes.items[c].cs.order != 0 and f.nodes.items[c].kind != .anon_text) needs_order = true;
        }
        if (!needs_order) return null;
        var list: std.ArrayList(u32) = .empty;
        c = f.nodes.items[id].first_child;
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
        return list.items;
    }

    fn buildLayout(f: *Frame, id: u32) Error!u32 {
        const ln = try f.layoutNode(id);
        if (ln.leaf) return ln.lid;
        // children, honouring `order` for flex/grid containers
        if (try f.orderedChildren(id, ln.ordered)) |list| {
            for (list) |x| {
                const cl = try f.buildLayout(x);
                f.tree.appendChild(ln.lid, cl) catch return error.OutOfMemory;
            }
        } else {
            var c = f.nodes.items[id].first_child;
            while (c != none) : (c = f.nodes.items[c].next) {
                const cl = try f.buildLayout(c);
                f.tree.appendChild(ln.lid, cl) catch return error.OutOfMemory;
            }
        }
        return ln.lid;
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
            const r = n.img_ratio;
            if (known[0]) |w| {
                if (known[1]) |h| return .{ w, h };
                return .{ w, if (r > 0) w / r else ih };
            }
            if (known[1]) |h| return .{ if (r > 0) h * r else iw, h };
            if (iw > 0 or ih > 0 or !(r > 0)) return .{ iw, ih };
            // ratio only (SVG with just a viewBox): fill the available width
            return switch (avail[0]) {
                .definite => |w| .{ w, w / r },
                else => .{ 0, 0 },
            };
        }
        const p = n.para orelse return .{ known[0] orelse 0, known[1] orelse 0 };
        const limit: ?f32 = known[0] orelse switch (avail[0]) {
            .definite => |v| v,
            .min_content => p.minContentWidth(),
            .max_content => null,
        };
        const sz = p.measure(limit);
        // (the min-content width may exceed the widest line it produces: inline edges, see text.zig)
        const w = if (avail[0] == .min_content) @max(sz.width, limit orelse 0) else sz.width;
        return .{ known[0] orelse w, known[1] orelse sz.height };
    }

    /// First / last baseline of a text leaf (NaN for a leaf without line boxes, e.g. an image: the
    /// layout engine then synthesizes one from its box).
    fn baselineCb(ctx: *anyopaque, lid: layout.NodeId, content_size: [2]f32) [2]f32 {
        const f: *Frame = @ptrCast(@alignCast(ctx));
        const nan = std.math.nan(f32);
        if (lid >= f.lid_node.items.len) return .{ nan, nan };
        const id = f.lid_node.items[lid];
        if (id == none) return .{ nan, nan };
        const p = f.nodes.items[id].para orelse return .{ nan, nan };
        const sz = p.measure(content_size[0]);
        if (sz.line_count == 0) return .{ content_size[1], content_size[1] };
        return .{ sz.first_baseline, sz.last_baseline };
    }

    /// Bridge between the layout engine's inline formatting protocol and the text engine's `Flow`.
    const FlowCtx = struct {
        io: *layout.InlineIo,

        fn band(fl: *const font.Flow, y: f32, h: f32) font.Band {
            const c: *FlowCtx = @ptrCast(@alignCast(fl.ctx.?));
            const b = c.io.band_fn.?(c.io, y, h);
            return .{ .x0 = b.x0, .x1 = b.x1, .next_y = b.next_y };
        }
        fn float(fl: *const font.Flow, id: u32, y: f32, used: f32, avail: f32, how: font.FloatPlace) bool {
            const c: *FlowCtx = @ptrCast(@alignCast(fl.ctx.?));
            return c.io.float_fn.?(c.io, id, y, used, avail, @intFromEnum(how));
        }
    };

    /// `layout.InlineFn`: lines of the paragraph of node `lid` (text, inline boxes and the atomic
    /// items of `io`) in the exclusion space the engine exposes; a layout pass keeps the line layout
    /// for the painters (`Node.tl`).
    fn inlineCb(ctx: *anyopaque, lid: layout.NodeId, io: *layout.InlineIo) void {
        const f: *Frame = @ptrCast(@alignCast(ctx));
        if (lid >= f.lid_node.items.len) return;
        const id = f.lid_node.items[lid];
        if (id == none) return;
        const n = &f.nodes.items[id];
        const p = n.para orelse return;
        f.inlineLayout(n, p, io) catch {
            f.layout_oom = true;
        };
    }

    noinline fn inlineLayout(f: *Frame, n: *Node, p: *const font.Paragraph, io: *layout.InlineIo) Error!void {
        var fc: FlowCtx = .{ .io = io };
        var flow: font.Flow = .{ .alloc = f.a, .ctx = &fc };
        if (io.items.len > 0) {
            const objs = try f.a.alloc(font.ObjectMetrics, io.items.len);
            for (io.items, objs) |it, *o| o.* = if (it.kind == .atomic) .{ .width = it.width, .ascent = it.baseline, .descent = it.height - it.baseline } else .{};
            flow.objects = objs;
        }
        if (io.band_fn != null) flow.band_fn = FlowCtx.band;
        if (io.float_fn != null) flow.float_fn = FlowCtx.float;
        const w = io.width;
        if (!(@abs(w) < std.math.inf(f32))) {
            // intrinsic sizes
            const iw = if (w < 0) p.minContentWidthFlow(&flow) else p.maxContentWidthFlow(&flow);
            io.size = .{ iw, 0 };
            if (io.width_only) return;
            const sz = p.measureFlow(&flow, if (w < 0) iw else null);
            io.size[1] = sz.height;
            if (sz.line_count > 0) {
                io.first_baseline = sz.first_baseline;
                io.last_baseline = sz.last_baseline;
            }
            return;
        }
        if (!io.layout) {
            const sz = p.measureFlow(&flow, w);
            io.size = .{ sz.width, sz.height };
            if (sz.line_count > 0) {
                io.first_baseline = sz.first_baseline;
                io.last_baseline = sz.last_baseline;
            }
            return;
        }
        const tl = try f.a.create(font.TextLayout);
        tl.* = p.layoutFlow(f.a, &flow, w) catch return error.OutOfMemory;
        n.tl = tl;
        n.tl_w = std.math.nan(f32);
        io.size = .{ tl.width, tl.height };
        if (tl.lines.len > 0) {
            io.first_baseline = tl.lines[0].baseline;
            io.last_baseline = tl.lines[tl.lines.len - 1].baseline;
        }
        for (tl.objects) |o| {
            if (o.id >= io.items.len) continue;
            io.items[o.id].x = o.x;
            io.items[o.id].y = o.y;
            io.items[o.id].placed = true;
            io.items[o.id].rtl = p.rtl;
        }
    }

    /// Index of a node of `f.nodes` from its pointer.
    pub fn nodeId(f: *const Frame, n: *const Node) u32 {
        return @intCast((@intFromPtr(n) - @intFromPtr(f.nodes.items.ptr)) / @sizeOf(Node));
    }

    pub const FragInfo = struct { cs: *const CS, x0: f32, x1: f32, left: bool, right: bool };

    /// Painter view of an inline box fragment of paragraph node `n`: the box's style, its CONTENT
    /// extent, and whether its left / right padding + border are present on this fragment
    /// (`box-decoration-break: clone`: always). Null for a fragment without extent or a hidden box.
    pub fn boxFragment(f: *const Frame, n: *const Node, fr: *const font.BoxFragment) ?FragInfo {
        const gi = @as(u64, n.box_base) + fr.box;
        if (gi >= f.inline_boxes.items.len or !(fr.x1 >= fr.x0)) return null;
        const cs = f.inline_boxes.items[@intCast(gi)].cs;
        if (cs.visibility != .visible) return null;
        const clone = cs.box_decoration_break == .clone;
        // (the start edge is on the right in a right-to-left fragment)
        const has_left = if (fr.rtl) fr.last else fr.first;
        const has_right = if (fr.rtl) fr.first else fr.last;
        const bw = cs.usedBorderWidths();
        const el = @trunc(bw[3] * 64) / 64 + @trunc(@max(cs.padding[3].resolve(0), 0) * 64) / 64;
        const er = @trunc(bw[1] * 64) / 64 + @trunc(@max(cs.padding[1].resolve(0), 0) * 64) / 64;
        return .{
            .cs = cs,
            .x0 = if (has_left) fr.x0 + el else fr.x0,
            .x1 = if (has_right) fr.x1 - er else fr.x1,
            .left = has_left or clone,
            .right = has_right or clone,
        };
    }

    /// Line layout of paragraph node `id` for painting / reporting: the one its layout pass left
    /// (inline content in a formatting context), else computed for content width `cw` (and kept).
    pub fn textLayout(f: *Frame, id: u32, cw: f32) Error!?*const font.TextLayout {
        const n = &f.nodes.items[id];
        const p = n.para orelse return null;
        if (n.tl) |tl| {
            if (n.tl_w != n.tl_w or n.tl_w == cw) return tl;
        }
        const tl = try f.a.create(font.TextLayout);
        tl.* = p.layout(f.a, cw) catch return error.OutOfMemory;
        n.tl = tl;
        n.tl_w = cw;
        return tl;
    }

    // ---- measure() output

    /// takumi's `MeasuredNode` shape: a block container's inline content is reported as the block's
    /// own `runs` (x / y relative to its content box) with its atomic inline boxes as `children`;
    /// anonymous paragraph leaves / line containers only appear as boxes of their own beside
    /// block-level siblings (takumi's anonymous block wrappers).
    /// `pt` = the parent's measured transform (takumi: parent * T(location) * own local transform).
    fn writeMeasured(f: *Frame, out: *std.ArrayList(u8), id: u32, pt: mx.Affine) Error!void {
        const a = f.a;
        const n = &f.nodes.items[id];
        const l = f.tree.layout(n.lid);
        const t = mx.mul(mx.mul(pt, mx.Affine.translate(l.x, l.y)), mx.local(n.cs, l.w, l.h));
        try out.appendSlice(a, "{\"width\":");
        try mx.writeExact(a, out, l.w);
        try out.appendSlice(a, ",\"height\":");
        try mx.writeExact(a, out, l.h);
        try writeAffine(a, out, t);
        try out.appendSlice(a, ",\"children\":[");
        // the anonymous child holding all in-flow content, reported as this box's inline content
        var inl = if (n.kind == .container and hasLines(n.cs.display)) f.soleInline(id) else none;
        // (inline content holding out-of-flow boxes is reported as takumi's anonymous block around it)
        if (inl != none and f.hasOutOfFlow(inl)) inl = none;
        var first = true;
        if (n.kind == .anon_box) try f.writePlaceholders(out, id, t, &first);
        if (inl != none and f.nodes.items[inl].kind == .anon_box) {
            const il = f.tree.layout(f.nodes.items[inl].lid);
            try f.writeChildren(out, inl, mx.mul(t, mx.Affine.translate(il.x, il.y)), none, &first);
        }
        try f.writeChildren(out, id, t, inl, &first);
        try out.appendSlice(a, "],\"runs\":[");
        first = true;
        const cx = l.border.left + l.padding.left;
        const cy = l.border.top + l.padding.top;
        if (n.para != null) {
            try f.writeRuns(out, id, 0, 0, &first);
        } else if (inl != none) {
            const il = f.tree.layout(f.nodes.items[inl].lid);
            try f.writeRuns(out, inl, il.x - cx, il.y - cy, &first);
        }
        try out.appendSlice(a, "]}");
    }

    /// Children of `id` except `skip` (and the inline-level boxes of an inline formatting context
    /// that are on no line, e.g. cut off by a line clamp).
    fn writeChildren(f: *Frame, out: *std.ArrayList(u8), id: u32, pt: mx.Affine, skip: u32, first: *bool) Error!void {
        const tl: ?*const font.TextLayout = if (f.nodes.items[id].kind == .anon_box) f.nodes.items[id].tl else null;
        var k: u32 = 0;
        var c = f.nodes.items[id].first_child;
        while (c != none) : (c = f.nodes.items[c].next) {
            defer k += 1;
            if (c == skip) continue;
            if (tl) |t| {
                const ccs = f.nodes.items[c].cs;
                if (ccs.float == .none and !isOutOfFlow(ccs)) {
                    var on_line = false;
                    for (t.objects) |o| {
                        if (o.id == k) on_line = true;
                    }
                    if (!on_line) continue;
                }
            }
            if (!first.*) try out.append(f.a, ',');
            first.* = false;
            try f.writeMeasured(out, c, pt);
        }
    }

    fn isOutOfFlow(cs: *const CS) bool {
        return cs.display != .none and (cs.position == .absolute or cs.position == .fixed);
    }

    noinline fn hasOutOfFlow(f: *const Frame, id: u32) bool {
        if (f.nodes.items[id].kind != .anon_box) return false;
        var c = f.nodes.items[id].first_child;
        while (c != none) : (c = f.nodes.items[c].next) {
            if (isOutOfFlow(f.nodes.items[c].cs)) return true;
        }
        return false;
    }

    /// takumi reports an empty box at the static position of every out-of-flow box of an inline
    /// formatting context, before its boxes.
    noinline fn writePlaceholders(f: *Frame, out: *std.ArrayList(u8), id: u32, pt: mx.Affine, first: *bool) Error!void {
        const n = &f.nodes.items[id];
        const tl = n.tl orelse return;
        var k: u32 = 0;
        var c = n.first_child;
        while (c != none) : (c = f.nodes.items[c].next) {
            defer k += 1;
            // (only for the out-of-flow boxes that are direct children of the block)
            if (!isOutOfFlow(f.nodes.items[c].cs) or f.nodes.items[c].in_inline_box) continue;
            for (tl.objects) |o| {
                if (o.id != k) continue;
                if (!first.*) try out.append(f.a, ',');
                first.* = false;
                try out.appendSlice(f.a, "{\"width\":0,\"height\":0");
                try writeAffine(f.a, out, mx.mul(pt, mx.Affine.translate(o.x, o.y)));
                try out.appendSlice(f.a, ",\"children\":[],\"runs\":[]}");
                break;
            }
        }
    }

    /// The anonymous paragraph leaf / line container that is the only in-flow child of `id`.
    noinline fn soleInline(f: *const Frame, id: u32) u32 {
        var found: u32 = none;
        var c = f.nodes.items[id].first_child;
        while (c != none) : (c = f.nodes.items[c].next) {
            const cn = &f.nodes.items[c];
            if (cn.kind != .anon_text and cn.kind != .anon_box) {
                const cs = cn.cs;
                if (cs.display == .none or cs.position == .absolute or cs.position == .fixed or cs.float != .none) continue;
                return none;
            }
            if (found != none) return none;
            found = c;
        }
        return found;
    }


    /// Text runs of paragraph node `id` (one per line and source run); (dx, dy) = the node's
    /// border-box offset from the content box the runs are reported against.
    noinline fn writeRuns(f: *Frame, out: *std.ArrayList(u8), id: u32, dx: f32, dy: f32, first: *bool) Error!void {
        const a = f.a;
        const l = f.tree.layout(f.nodes.items[id].lid);
        const cw = l.w - l.padding.left - l.padding.right - l.border.left - l.border.right;
        const tl = (try f.textLayout(id, cw)) orelse return;
        const ox = dx + l.border.left + l.padding.left;
        const oy = dy + l.border.top + l.padding.top;
        if (tl.segments.len > 0) {
            // (inline boxes / objects: the exact extent of every run segment)
            for (tl.segments) |sg| {
                if (sg.line >= tl.lines.len) continue;
                const line = tl.lines[sg.line];
                if (!first.*) try out.append(a, ',');
                first.* = false;
                try out.appendSlice(a, "{\"x\":");
                try mx.writeExact(a, out, ox + @min(sg.x0, sg.x1));
                try out.appendSlice(a, ",\"y\":");
                try mx.writeExact(a, out, oy + line.top + (sg.baseline - line.baseline));
                try out.appendSlice(a, ",\"width\":");
                try mx.writeExact(a, out, @abs(sg.x1 - sg.x0));
                try out.appendSlice(a, ",\"height\":");
                try mx.writeExact(a, out, line.height);
                try out.append(a, '}');
            }
            return;
        }
        for (tl.lines) |line| {
            var g = line.glyph_start;
            const end = @min(line.glyph_end, tl.glyphs.len);
            // one run per source run (glyph `user`) of the line; an empty line still reports one
            while (true) {
                var x0 = line.x;
                var x1 = line.x + line.width;
                if (g < end) {
                    var e = g + 1;
                    while (e < end and tl.glyphs[e].user == tl.glyphs[g].user) e += 1;
                    if (g != line.glyph_start) x0 = tl.glyphs[g].x;
                    if (e < end) x1 = tl.glyphs[e].x;
                    g = e;
                }
                if (!first.*) try out.append(a, ',');
                first.* = false;
                try out.appendSlice(a, "{\"x\":");
                try mx.writeExact(a, out, ox + @min(x0, x1));
                try out.appendSlice(a, ",\"y\":");
                try mx.writeExact(a, out, oy + line.top);
                try out.appendSlice(a, ",\"width\":");
                try mx.writeExact(a, out, @abs(x1 - x0));
                try out.appendSlice(a, ",\"height\":");
                try mx.writeExact(a, out, line.height);
                try out.append(a, '}');
                if (g >= end) break;
            }
        }
    }
};

fn parseBlock(a: Allocator, text: []const u8) Error![]const style.Declaration {
    return style.parseDeclarationBlock(a, text) catch error.OutOfMemory;
}

/// css / tw declarations (kebab-case name, value text, important flag) -> style declarations.
fn convertDecls(a: Allocator, src: anytype) Error![]const style.Declaration {
    if (src.len == 0) return &.{};
    const out = try a.alloc(style.Declaration, src.len);
    for (src, out) |d, *o| o.* = .{ .name = d.name, .value = d.value, .important = d.important };
    return out;
}

/// `css.Dom` callbacks over the element model (only ELEMENTS are visible; bare text runs skipped).
const CssDom = struct {
    fn d(ctx: *const anyopaque) *const dom_mod.Dom {
        return @ptrCast(@alignCast(ctx));
    }
    fn e(x: usize) u32 {
        return @intCast(x);
    }
    fn tag(ctx: *const anyopaque, x: usize) []const u8 {
        return d(ctx).at(e(x)).tag;
    }
    fn id(ctx: *const anyopaque, x: usize) []const u8 {
        return d(ctx).at(e(x)).id;
    }
    fn classes(ctx: *const anyopaque, x: usize) []const u8 {
        return d(ctx).at(e(x)).class;
    }
    fn attr(ctx: *const anyopaque, x: usize, name: []const u8) ?[]const u8 {
        return d(ctx).attr(e(x), name);
    }
    fn parent(ctx: *const anyopaque, x: usize) ?usize {
        const p = d(ctx).at(e(x)).parent;
        return if (p == none) null else p;
    }
    fn prev(ctx: *const anyopaque, x: usize) ?usize {
        return if (d(ctx).prevEl(e(x))) |v| v else null;
    }
    fn next(ctx: *const anyopaque, x: usize) ?usize {
        return if (d(ctx).nextEl(e(x))) |v| v else null;
    }
    fn first(ctx: *const anyopaque, x: usize) ?usize {
        return if (d(ctx).firstEl(e(x))) |v| v else null;
    }
    fn empty(ctx: *const anyopaque, x: usize) bool {
        return d(ctx).isEmpty(e(x));
    }
    fn dir(ctx: *const anyopaque, x: usize) css.Dir {
        return switch (d(ctx).at(e(x)).dir) {
            .none => .none,
            .ltr => .ltr,
            .rtl => .rtl,
        };
    }
    fn vtable(dm: *const dom_mod.Dom) css.Dom {
        return .{ .ctx = dm, .tag = tag, .id = id, .classes = classes, .attr = attr, .parent = parent, .prev_sibling = prev, .next_sibling = next, .first_child = first, .is_empty = empty, .dir = dir };
    }
};

pub fn textStyle(cs: *const CS, user: u32) font.TextStyle {
    var ts: font.TextStyle = .{
        .families = cs.font_family,
        .weight = cs.font_weight,
        .italic = cs.font_style != .normal,
        .size = cs.font_size,
        .letter_spacing = cs.letter_spacing,
        .word_spacing = cs.word_spacing,
        .user = user,
        .stretch = cs.font_stretch,
        .optical_sizing = cs.font_optical_sizing != .none,
        // (same member order: normal, small, all-small, petite, all-petite, unicase, titling)
        .caps = @enumFromInt(@intFromEnum(cs.font_variant_caps)),
        .synth_small_caps = cs.font_synthesis.small_caps,
    };
    // style.FontVariation and font.AxisValue are both { tag: [4]u8, value: f32 }
    const V = @typeInfo(@TypeOf(ts.variations)).pointer.child;
    comptime std.debug.assert(@sizeOf(V) == @sizeOf(style.computed.FontVariation));
    const vs = cs.font_variation_settings;
    ts.variations = @as([*]const V, @ptrCast(vs.ptr))[0..vs.len];
    return ts;
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

/// Greek final-sigma context helpers (Unicode 3.13 Final_Sigma, approximated: cased = has a
/// case mapping, case-ignorable = apostrophes and combining marks).
fn isCased(cp: u21) bool {
    return font.case.upperSimple(cp) != cp or font.case.lower(cp) != cp;
}
fn isCaseIgnorable(cp: u21) bool {
    return cp == 0x27 or cp == 0x2019 or cp == 0xB7 or (cp >= 0x300 and cp <= 0x36F);
}
fn nextCased(text: []const u8, from: usize) bool {
    var i = from;
    while (i < text.len) {
        const cp = decodeCp(text, &i);
        if (!isCaseIgnorable(cp)) return isCased(cp);
    }
    return false;
}

/// Titlecase for capitalize: uppercase, except the Latin digraphs (DŽ/Dž/dž -> Dž, ...).
fn titleCase(cp: u21) u21 {
    return switch (cp) {
        0x1C4...0x1C6 => 0x1C5,
        0x1C7...0x1C9 => 0x1C8,
        0x1CA...0x1CC => 0x1CB,
        0x1F1...0x1F3 => 0x1F2,
        else => font.case.upperSimple(cp),
    };
}

/// text-transform without a language (takumi with no `lang`): full uppercase (SpecialCasing
/// expansions: ß -> SS, ﬁ -> FI, ...), simple lowercase with the final-sigma rule and
/// U+0130 -> i + U+0307; capitalize = titlecase of a word start (a character not preceded by a
/// letter / digit, nor by an apostrophe, period, colon or middle dot between letters: UAX #29 approximated).
fn transformText(a: Allocator, text: []const u8, tt: anytype) Error![]const u8 {
    if (tt == .none) return text;
    var out: std.ArrayList(u8) = .empty;
    try out.ensureTotalCapacity(a, text.len + 8);
    var i: usize = 0;
    var word_start = true;
    var prev_cased = false;
    var prev: u21 = 0;
    var prev2: u21 = 0;
    while (i < text.len) {
        const cp = decodeCp(text, &i);
        var m: [3]u21 = .{ cp, 0, 0 };
        var n: usize = 1;
        switch (tt) {
            .uppercase => n = font.case.upper(cp, &m),
            .lowercase => {
                m[0] = font.case.lower(cp);
                if (cp == 0x3A3 and prev_cased and !nextCased(text, i)) m[0] = 0x3C2;
                if (cp == 0x130) {
                    m = .{ 'i', 0x307, 0 };
                    n = 2;
                }
            },
            .capitalize => {
                const wordy = struct {
                    fn f(c: u21) bool {
                        // letters and digits (non-ASCII: anything outside the punctuation / symbol blocks)
                        if (isCased(c) or (c >= 0x30 and c <= 0x39)) return true;
                        return c >= 0xC0 and c != 0xD7 and c != 0xF7 and !(c >= 0x2000 and c <= 0x2BFF) and !(c >= 0x3000 and c <= 0x303F) and !(c >= 0xFE10 and c <= 0xFE6F) and !(c >= 0xFF00 and c <= 0xFF20);
                    }
                }.f;
                const mid = prev == 0x27 or prev == 0x2019 or prev == 0x2E or prev == 0x3A or prev == 0xB7;
                word_start = !(wordy(prev) or (mid and wordy(prev2)));
                if (word_start) m[0] = titleCase(cp);
            },
            else => {},
        }
        if (!isCaseIgnorable(cp)) prev_cased = isCased(cp);
        prev2 = prev;
        prev = cp;
        for (m[0..n]) |c| {
            var buf: [4]u8 = undefined;
            const len = json.encodeUtf8(c, &buf);
            try out.appendSlice(a, buf[0..len]);
        }
    }
    return out.items;
}

// ---- ComputedStyle -> layout.Style

// Non-linear math (`min()/max()/clamp()` mixing % and lengths, `lp.isCalc()`) has no layout
// representation: such values degrade to their value at a reference of 0.

fn dimLp(lp: style.LP) layout.Dim {
    if (lp.isCalc()) return .{ .px = lp.resolve(0) };
    if (lp.pct == 0) return .{ .px = lp.px };
    if (lp.px == 0) return .{ .percent = lp.pct };
    return .{ .calc = .{ .px = lp.px, .percent = lp.pct } };
}

fn dimSize(s: style.Size) layout.Dim {
    return switch (s) {
        .lp => |lp| dimLp(lp),
        .min_content => .min_content,
        .max_content => .max_content,
        // fit-content(<limit>): the layout keyword has no limit, see mapStyle
        .fit_content, .fit_content_lp => .fit_content,
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
    if (lp.isCalc()) return .{ .px = lp.resolve(0) };
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
        .lp => |lp| if (lp.isCalc()) .{ .px = lp.resolve(0) } else if (lp.pct == 0) .{ .px = lp.px } else .{ .percent = lp.pct },
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
    const tables = config.enable_tables;
    s.display = switch (cs.display) {
        .none => .none,
        .flex, .inline_flex => .flex,
        .grid, .inline_grid => .grid,
        .table => if (tables) .table else .block,
        .inline_table => if (tables) .inline_table else .block,
        .table_row_group => if (tables) .table_row_group else .block,
        .table_header_group => if (tables) .table_header_group else .block,
        .table_footer_group => if (tables) .table_footer_group else .block,
        .table_row => if (tables) .table_row else .block,
        .table_cell => if (tables) .table_cell else .block,
        .table_caption => if (tables) .table_caption else .block,
        .table_column => if (tables) .table_column else .block,
        .table_column_group => if (tables) .table_column_group else .block,
        else => .block,
    };
    // inline-block / flow-root establish an independent formatting context
    s.flow_root = cs.display == .flow_root or cs.display == .inline_block;
    if (comptime config.enable_floats) if (cs.position != .absolute and cs.position != .fixed) {
        const rtl = cs.direction == .rtl;
        s.float = switch (cs.float) {
            .none => .none,
            .left => .left,
            .right => .right,
            .inline_start => if (rtl) .right else .left,
            .inline_end => if (rtl) .left else .right,
        };
        s.clear = switch (cs.clear) {
            .none => .none,
            .left => .left,
            .right => .right,
            .both => .both,
            .inline_start => if (rtl) .right else .left,
            .inline_end => if (rtl) .left else .right,
        };
    };
    // (sub / super / text-top / text-bottom / <length> are not supported by the layout engine)
    s.vertical_align = switch (cs.vertical_align) {
        .top => .top,
        .middle => .middle,
        .bottom => .bottom,
        else => .baseline,
    };
    if (s.display.isTablePart() or s.display.isTable()) {
        // inherited in CSS, per node in the layout engine
        s.border_spacing = cs.border_spacing;
        s.border_collapse = cs.border_collapse == .collapse;
        s.caption_bottom = cs.caption_side == .bottom;
        s.table_fixed = cs.table_layout == .fixed;
    }
    s.position = switch (cs.position) {
        .static => .static,
        .relative, .sticky => .relative,
        .absolute => .absolute,
        .fixed => .fixed,
    };
    s.box_sizing = if (cs.box_sizing == .border_box) .border_box else .content_box;
    s.order = cs.order;
    s.visibility_collapse = cs.visibility == .collapse;
    s.overflow_x = mapOverflow(cs.overflow_x);
    s.overflow_y = mapOverflow(cs.overflow_y);
    // inset properties do not apply to position: static
    if (cs.position != .static) s.inset = .{ .top = dimAuto(cs.inset[0]), .right = dimAuto(cs.inset[1]), .bottom = dimAuto(cs.inset[2]), .left = dimAuto(cs.inset[3]) };
    s.size = .{ dimSize(cs.width), dimSize(cs.height) };
    s.min_size = .{ dimSize(cs.min_width), dimSize(cs.min_height) };
    s.max_size = .{ dimSize(cs.max_width), dimSize(cs.max_height) };
    // fit-content(L) = min(max-content, max(min-content, L)), approximated as fit-content capped by
    // max-size L (the min-content floor is lost when L is smaller)
    if (cs.width == .fit_content_lp and s.max_size[0] == .auto) s.max_size[0] = dimLp(cs.width.fit_content_lp);
    if (cs.height == .fit_content_lp and s.max_size[1] == .auto) s.max_size[1] = dimLp(cs.height.fit_content_lp);
    s.aspect_ratio = cs.aspect_ratio;
    s.margin = .{ .top = dimAuto(cs.margin[0]), .right = dimAuto(cs.margin[1]), .bottom = dimAuto(cs.margin[2]), .left = dimAuto(cs.margin[3]) };
    s.padding = .{ .top = lpOf(cs.padding[0]), .right = lpOf(cs.padding[1]), .bottom = lpOf(cs.padding[2]), .left = lpOf(cs.padding[3]) };
    const bw = cs.usedBorderWidths();
    s.border = .{ .top = bw[0], .right = bw[1], .bottom = bw[2], .left = bw[3] };
    if (@hasField(layout.Style, "border_hidden")) {
        s.border_hidden = .{ .top = cs.border_style[0] == .hidden, .right = cs.border_style[1] == .hidden, .bottom = cs.border_style[2] == .hidden, .left = cs.border_style[3] == .hidden };
    }
    if (@hasDecl(CS, "alignSafe")) s.safe = @bitCast(cs.alignSafe());
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
        // grid-template-areas also sizes the explicit grid; the extra tracks are sized by grid-auto-*
        const ar = cs.grid_template_areas;
        padTracks(f, &s.grid_template_columns, ar.cols, s.grid_auto_columns, cs.grid_template_columns);
        padTracks(f, &s.grid_template_rows, ar.rows, s.grid_auto_rows, cs.grid_template_rows);
        s.grid_auto_flow = if (cs.grid_auto_flow.column) (if (cs.grid_auto_flow.dense) .column_dense else .column) else (if (cs.grid_auto_flow.dense) .row_dense else .row);
    }
    s.grid_column = .{ .start = gridLine(cs.grid_column_start), .end = gridLine(cs.grid_column_end) };
    s.grid_row = .{ .start = gridLine(cs.grid_row_start), .end = gridLine(cs.grid_row_end) };
    return s;
}

/// grid-template-areas larger than the track list: the extra explicit tracks take grid-auto-* sizes.
fn padTracks(f: *Frame, list: *[]const layout.Track, want: u16, auto: []const layout.Track, t: style.computed.GridTemplate) void {
    if (t.auto_repeat != .none or want <= list.len) return;
    const out = f.a.alloc(layout.Track, want) catch return;
    @memcpy(out[0..list.len], list.*);
    for (out[list.len..], 0..) |*o, k| o.* = if (auto.len > 0) auto[k % auto.len] else .auto;
    list.* = out;
}

// ---- anonymous line containers

/// Font metrics in em: ascent, descent (positive down), line gap, x-height.
pub const EmMetrics = struct { ascent: f32, descent: f32, gap: f32, x_height: f32 };
/// Geist (takumi's bundled default font): the strut font when no font is registered.
pub const geist_em: EmMetrics = .{ .ascent = 1.005, .descent = 0.295, .gap = 0, .x_height = 0.53 };

/// Strut of a line container (Blink): A, D, G = ascent / descent / line gap of the primary font at
/// `size`, each rounded to whole px; L = line-height (normal = A + D + G); half-leading
/// floor((L - (A + D)) / 2) goes above. Returns [strut ascent, strut descent (may be negative),
/// distance from the baseline to the `vertical-align: middle` line (half the x-height)].
pub fn strutFrom(m: EmMetrics, size: f32, lh: style.computed.LineHeight) [3]f32 {
    const a = @round(m.ascent * size);
    const d = @round(m.descent * size);
    const g = @round(m.gap * size);
    const l: f32 = switch (lh) {
        .normal => a + d + g,
        .number => |k| @floor(k * size * 64) / 64,
        .px => |p| @floor(p * 64) / 64,
    };
    const asc = a + @floor((l - (a + d)) / 2);
    return .{ asc, l - asc, m.x_height * size / 2 };
}

/// Metrics of the primary font of `cs` (first face the font matcher returns), Geist's without fonts.
fn emMetrics(fonts: *const font.FontCollection, cs: *const CS) EmMetrics {
    var buf: [4]font.FaceId = undefined;
    const faces = fonts.match(cs.font_family, cs.font_weight, cs.font_style != .normal, &buf);
    if (faces.len == 0) return geist_em;
    const fo = fonts.font(faces[0]);
    const lm = fo.lineMetrics();
    const upm: f32 = @floatFromInt(@max(fo.units_per_em, 1));
    const asc = @as(f32, @floatFromInt(lm.ascent)) / upm;
    const xh = fo.xHeight();
    return .{
        .ascent = asc,
        .descent = @as(f32, @floatFromInt(lm.descent)) / upm,
        .gap = @as(f32, @floatFromInt(lm.leading)) / upm,
        // (Blink's fallback without an OS/2 x-height)
        .x_height = if (xh > 0) @as(f32, @floatFromInt(xh)) / upm else asc * 0.56,
    };
}

// ---- tables

/// HTML "rules for parsing non-negative integers", saturating (Blink's ParseHTMLClampedNonNegativeInteger).
fn parseSpanAttr(v: []const u8) ?u32 {
    var i: usize = 0;
    while (i < v.len and (v[i] == ' ' or v[i] == '\t' or v[i] == '\n' or v[i] == '\r' or v[i] == 0x0c)) i += 1;
    if (i < v.len and v[i] == '+') i += 1;
    var n: u32 = 0;
    var digits = false;
    while (i < v.len and v[i] >= '0' and v[i] <= '9') : (i += 1) {
        digits = true;
        n = @min(n *| 10 +| (v[i] - '0'), 1 << 30);
    }
    return if (digits) n else null;
}

/// takumi (`table/parts.rs`): `colspan` (1..1000) / `rowspan` (0..65534, 0 = every remaining row)
/// attributes of a `td` / `th` element, `span` (1..1000) of a `col` / `colgroup` element.
fn tableSpans(d: *const dom_mod.Dom, i: u32, st: *layout.Style) void {
    const tag = d.at(i).tag;
    const eq = std.ascii.eqlIgnoreCase;
    if (eq(tag, "td") or eq(tag, "th")) {
        if (d.attr(i, "colspan")) |v| if (parseSpanAttr(v)) |n| {
            st.col_span = @intCast(std.math.clamp(n, 1, 1000));
        };
        if (d.attr(i, "rowspan")) |v| if (parseSpanAttr(v)) |n| {
            st.row_span = if (n == 0) 65534 else @intCast(@min(n, 65534));
        };
    } else if (eq(tag, "col") or eq(tag, "colgroup")) {
        if (d.attr(i, "span")) |v| if (parseSpanAttr(v)) |n| {
            st.col_span = @intCast(std.math.clamp(n, 1, 1000));
        };
    }
}

// ---- named grid lines / areas

/// x == a ++ b
fn eqlCat(x: []const u8, a: []const u8, b: []const u8) bool {
    return x.len == a.len + b.len and std.mem.startsWith(u8, x, a) and std.mem.endsWith(u8, x, b);
}

/// a1 ++ a2 == b1 ++ b2
fn eqlCat2(a1: []const u8, a2: []const u8, b1: []const u8, b2: []const u8) bool {
    if (a1.len + a2.len != b1.len + b2.len) return false;
    var i: usize = 0;
    while (i < a1.len + a2.len) : (i += 1) {
        const x = if (i < a1.len) a1[i] else a2[i - a1.len];
        const y = if (i < b1.len) b1[i] else b2[i - b1.len];
        if (x != y) return false;
    }
    return true;
}

/// Number of explicit grid lines of an axis (template tracks, an auto-repeat group counted once, or
/// the rows / columns of grid-template-areas).
fn explicitLines(c: *const CS, col: bool) i32 {
    const t = if (col) c.grid_template_columns else c.grid_template_rows;
    const ar = if (col) c.grid_template_areas.cols else c.grid_template_areas.rows;
    return @as(i32, @intCast(@max(t.tracks.len, ar) & 0xffff)) + 1;
}

/// Sorted 1-based lines of an axis named `base ++ suffix`: names in the track list (lines inside an
/// auto-repeat group counted for one repetition) and the `<area>-start` / `<area>-end` lines that
/// grid-template-areas defines.
fn namedLines(c: *const CS, col: bool, base: []const u8, suffix: []const u8, buf: []i32) []i32 {
    var n: usize = 0;
    const t = if (col) c.grid_template_columns else c.grid_template_rows;
    for (t.line_names) |ln| {
        if (n == buf.len) break;
        if (!eqlCat(ln.name, base, suffix)) continue;
        buf[n] = @as(i32, ln.line) + 1 + (if (ln.in_repeat) @as(i32, t.auto_repeat_start) else 0);
        n += 1;
    }
    for (c.grid_template_areas.areas) |ar| {
        if (n + 2 > buf.len) break;
        if (eqlCat2(ar.name, "-start", base, suffix)) {
            buf[n] = @as(i32, if (col) ar.col_start else ar.row_start) + 1;
            n += 1;
        }
        if (eqlCat2(ar.name, "-end", base, suffix)) {
            buf[n] = @as(i32, if (col) ar.col_end else ar.row_end) + 1;
            n += 1;
        }
    }
    // sort + dedupe
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const x = buf[i];
        var j = i;
        while (j > 0 and buf[j - 1] > x) : (j -= 1) buf[j] = buf[j - 1];
        buf[j] = x;
    }
    var m: usize = 0;
    for (buf[0..n]) |x| {
        if (m > 0 and buf[m - 1] == x) continue;
        buf[m] = x;
        m += 1;
    }
    return buf[0..m];
}

/// Line of a `[<integer>] <name>` reference (CSS Grid §8.3.1): a lone name first looks for
/// `<name>-start` / `<name>-end`; the n-th line with the name (negative n counts from the end);
/// past the named lines the implicit lines count as named, so an unknown name is the first implicit
/// line after the explicit grid (EMPIRICAL, takumi). null only for n = 0.
/// (takumi's parser rejects the `<integer> <name>` forms; the style module accepts them, resolved per CSS.)
fn namedLine(c: *const CS, col: bool, name: []const u8, n: i32, is_end: bool, lines_n: i32) ?i32 {
    var buf: [64]i32 = undefined;
    if (n == 1) {
        const l = namedLines(c, col, name, if (is_end) "-end" else "-start", &buf);
        if (l.len > 0) return l[0];
    }
    const l = namedLines(c, col, name, "", &buf);
    if (n == 0) return null;
    const cnt: i32 = @intCast(l.len);
    if (n > 0) return if (n <= cnt) l[@intCast(n - 1)] else lines_n + (n - cnt);
    const k = -n;
    return if (k <= cnt) l[@intCast(cnt - k)] else 1 - (k - cnt);
}

/// Absolute line number -> layout line (1-based; lines before the first explicit line counted from
/// the end of the explicit grid).
fn toLine(v: i32, lines_n: i32) layout.Line {
    const x = if (v >= 1) v else v - lines_n - 1;
    return .{ .line = @intCast(std.math.clamp(x, -30000, 30000)) };
}

/// Resolves the named references of one axis of a grid item (`sref` / `eref` = start / end).
fn resolveNamed(c: *const CS, col: bool, sref: style.computed.GridLineRef, eref: style.computed.GridLineRef, cur: layout.Placement) layout.Placement {
    const ln = explicitLines(c, col);
    var p = cur;
    if (sref.name.len > 0 and !sref.span) p.start = if (namedLine(c, col, sref.name, sref.n, false, ln)) |v| toLine(v, ln) else .auto;
    if (eref.name.len > 0 and !eref.span) p.end = if (namedLine(c, col, eref.name, eref.n, true, ln)) |v| toLine(v, ln) else .auto;
    // `span <name>` is `span 1` in takumi (EMPIRICAL, probe/layout2/gridnames.mjs; CSS counts named lines)
    if (sref.name.len > 0 and sref.span) p.start = .{ .span = 1 };
    if (eref.name.len > 0 and eref.span) p.end = if (p.start == .span) .auto else .{ .span = 1 };
    return p;
}

/// Named lines / areas of grid item `item` resolved against its container `c`.
fn gridNames(c: *const CS, item: *const CS, st: *layout.Style) void {
    const r = item.grid_line_names; // row start, column start, row end, column end
    if (r[0].name.len > 0 or r[2].name.len > 0) st.grid_row = resolveNamed(c, false, r[0], r[2], st.grid_row);
    if (r[1].name.len > 0 or r[3].name.len > 0) st.grid_column = resolveNamed(c, true, r[1], r[3], st.grid_column);
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

fn testRender(node: []const u8, opts: []const u8) !void {
    const gpa = std.testing.allocator;
    const r = Renderer.create(gpa).?;
    defer r.destroy();
    const font_bytes = @embedFile("font/testdata/Inter-Regular.ttf");
    _ = try r.registerFont(try gpa.dupe(u8, font_bytes), "", 0, -1);
    _ = r.render(node, opts) catch |e| switch (e) {
        error.Invalid => {},
        else => return e,
    };
}

test "regression: text shifted above the canvas by a relative offset" {
    const node = "{\"type\":\"container\",\"style\":{},\"children\":[{\"type\":\"container\",\"style\":{\"borderTop\":\"6px solid green\"},\"children\":[{\"type\":\"container\",\"style\":{\"bottom\":20},\"children\":[{\"type\":\"container\",\"style\":{},\"children\":[{\"type\":\"container\",\"style\":{},\"children\":[{\"type\":\"text\",\"text\":\"Xin ch\u{00e0}o Vi\u{1ec7}t Nam \u{2014} ti\u{1ebf}ng Vi\u{1ec7}t c\u{00f3} d\u{1ea5}u\",\"style\":{}}]},{\"type\":\"container\",\"style\":{},\"children\":[]}]}]}]}]}";
    try testRender(node, "{\"height\":1,\"format\":\"raw\"}");
}

// ---- front-end integration tests (cascade order, HTML mapping, generated content)

const TestFrame = struct {
    r: *Renderer,
    f: Frame,

    fn init(kind: SourceKind, src: []const u8, opts: []const u8) !*TestFrame {
        const gpa = std.testing.allocator;
        const r = Renderer.create(gpa).?;
        errdefer r.destroy();
        _ = try r.registerFont(try gpa.dupe(u8, @embedFile("font/testdata/Inter-Regular.ttf")), "", 0, -1);
        r.beginCall();
        const a = r.arena.allocator();
        const t = try a.create(TestFrame);
        t.r = r;
        t.f = .{ .r = r, .a = a, .opts = try r.parseOptions(opts), .tree = LTree.init(a), .ctx = undefined };
        t.f.prepare(kind, src) catch |e| {
            if (e == error.Invalid) std.debug.print("render error: {s}\n", .{r.err});
            return e;
        };
        return t;
    }
    fn deinit(t: *TestFrame) void {
        t.r.destroy();
    }
    fn el(t: *TestFrame, i: u32) *dom_mod.El {
        return t.f.dom.at(i);
    }
    /// First element with `id`.
    fn byId(t: *TestFrame, id: []const u8) *dom_mod.El {
        for (t.f.dom.els.items) |*e| if (std.mem.eql(u8, e.id, id)) return e;
        @panic("no such id");
    }
};

fn bgOf(cs: *const CS) style.Color {
    return switch (cs.background_color) {
        .rgba => |c| c,
        else => .{},
    };
}

fn pxOf(s: style.Size) f32 {
    return switch (s) {
        .lp => |lp| lp.px,
        else => -1,
    };
}

test "cascade order: preset < tw < stylesheet < inline style; !important reverses" {
    if (comptime !(config.enable_css and config.enable_tw)) return error.SkipZigTest;
    const t = try TestFrame.init(.json,
        \\{"type":"container","children":[
        \\ {"type":"container","id":"a","className":"x","tw":"bg-[#000001] w-[1px]",
        \\  "preset":{"backgroundColor":"#000002","width":2,"height":2,"opacity":0.5},"style":{"height":3}},
        \\ {"type":"container","id":"b","className":"x","style":{"height":"5px !important","backgroundColor":"#000009"}},
        \\ {"type":"container","id":"c","tw":"!w-[7px] h-[8px]","style":{"width":6,"height":9}},
        \\ {"type":"container","id":"d","className":"y bogus","style":{}}
        \\]}
    ,
        \\{"width":100,"height":100,"css":[".x{background-color:#000003;height:4px !important}",
        \\ {"selector":".y","style":{"width":"banana","height":"11px"}}]}
    );
    defer t.deinit();
    const a = t.byId("a").cs;
    try std.testing.expectEqual(@as(u8, 3), bgOf(a).b); // css beats tw beats preset
    try std.testing.expectEqual(@as(f32, 1), pxOf(a.width)); // tw beats preset
    try std.testing.expectEqual(@as(f32, 4), pxOf(a.height)); // css !important beats inline normal
    try std.testing.expectEqual(@as(f32, 0.5), a.opacity); // preset survives
    const b = t.byId("b").cs;
    try std.testing.expectEqual(@as(f32, 5), pxOf(b.height)); // inline !important beats css !important
    try std.testing.expectEqual(@as(u8, 9), bgOf(b).b); // inline normal beats css normal
    const c = t.byId("c").cs;
    try std.testing.expectEqual(@as(f32, 7), pxOf(c.width)); // tw !important beats inline normal
    try std.testing.expectEqual(@as(f32, 9), pxOf(c.height)); // inline beats tw
    const d = t.byId("d").cs;
    try std.testing.expectEqual(@as(f32, 11), pxOf(d.height)); // invalid rule value dropped alone (lenient)
    try std.testing.expect(d.width == .auto);
}

test "strict inline style still fails; tw / css / html never do" {
    const gpa = std.testing.allocator;
    const r = Renderer.create(gpa).?;
    defer r.destroy();
    try std.testing.expectError(error.Invalid, r.render("{\"type\":\"container\",\"style\":{\"width\":\"banana\"}}", "{\"width\":10,\"height\":10,\"format\":\"raw\"}"));
    try std.testing.expect(std.mem.indexOf(u8, r.err, "width") != null);
    _ = try r.render("{\"type\":\"container\",\"tw\":\"w-[banana] p-[1px_2px_3px_4px_5px]\",\"className\":\"q\"}", "{\"width\":10,\"height\":10,\"format\":\"raw\",\"css\":[\".q{width:banana}\"]}");
    if (comptime config.enable_html) _ = try r.renderSource(.html, "<div style=\"width:banana;height:5px\">x</div>", "{\"width\":10,\"height\":10,\"format\":\"raw\"}");
}

test "html -> elements: fragment collapse, document wrappers, presets, text elements" {
    if (comptime !config.enable_html) return error.SkipZigTest;
    {
        const t = try TestFrame.init(.html, "\n  <p id=\"p\">Hello <b>bold</b><br>x</p>\n  <h1 id=\"h\" style=\"color:#00ff00\">Title</h1><img src=\"\" width=\"10\" height=\"50%\"><style>.c{}</style>", "{\"width\":200,\"height\":100}");
        defer t.deinit();
        const root = t.el(t.f.dom.root);
        try std.testing.expect(root.tag.len == 0 and root.kind == .container); // several roots -> wrapper
        try std.testing.expect(root.style == .text);
        const p = t.byId("p");
        try std.testing.expectEqual(dom_mod.Kind.container, p.kind);
        try std.testing.expect(t.el(p.first).run); // "Hello "
        const h = t.byId("h");
        try std.testing.expectEqual(dom_mod.Kind.text, h.kind); // element holding only text
        try std.testing.expectEqualStrings("Title", h.text);
        try std.testing.expectEqual(@as(f32, 32), h.cs.font_size); // preset font-size: 2em
        try std.testing.expectEqual(@as(u16, 700), h.cs.font_weight);
        try std.testing.expectEqual(@as(u8, 255), h.cs.color.g); // style attribute
        try std.testing.expectEqual(style.Display.block, h.cs.display);
        // <br> is a text element "\n"; <img> an image with a px width preset and a % height hint
        var saw_br = false;
        var saw_img = false;
        for (t.f.dom.els.items) |*e| {
            if (std.mem.eql(u8, e.tag, "br")) saw_br = e.kind == .text and std.mem.eql(u8, e.text, "\n");
            if (std.mem.eql(u8, e.tag, "img")) {
                saw_img = e.kind == .image and e.width.? == 10 and e.height == null and std.mem.eql(u8, e.pres, "height:50%;");
            }
            try std.testing.expect(!std.mem.eql(u8, e.tag, "style")); // unrendered
        }
        try std.testing.expect(saw_br and saw_img);
        try std.testing.expectEqual(@as(usize, 1), t.f.dom.styles.len);
    }
    {
        const t = try TestFrame.init(.html, "<!doctype html><html lang=\"vi\"><body class=\"b\"><div>x</div></body></html>", "{\"width\":200,\"height\":100}");
        defer t.deinit();
        const root = t.el(t.f.dom.root);
        try std.testing.expectEqualStrings("html", root.tag);
        try std.testing.expectEqualStrings("vi", root.lang);
        const body = t.el(root.first);
        try std.testing.expectEqualStrings("body", body.tag);
        try std.testing.expectEqualStrings("b", body.class);
        try std.testing.expectEqual(@as(f32, 8), body.cs.margin[0].lp.px);
    }
    {
        const t = try TestFrame.init(.html, "  ", "{\"width\":20,\"height\":10}");
        defer t.deinit();
        try std.testing.expectEqual(@as(usize, 1), t.f.dom.els.items.len); // empty container
    }
}

test "pseudo-elements: ::before/::after from css and tw, content parsing, own text box" {
    if (comptime !(config.enable_css and config.enable_tw)) return error.SkipZigTest;
    const t = try TestFrame.init(.json,
        \\{"type":"container","children":[
        \\ {"type":"text","id":"t","className":"s","text":"mid","attributes":{"data-n":"7"}},
        \\ {"type":"container","id":"c","className":"s"},
        \\ {"type":"container","id":"n","className":"none"},
        \\ {"type":"image","id":"i","className":"s","src":"x"},
        \\ {"type":"container","id":"w","tw":"after:content-['tw'] after:text-[#ff0000]"}
        \\]}
    ,
        \\{"width":100,"height":100,"css":[".s::before{content:'<' attr(data-n);color:#0000ff}.s::after{content:\">\";display:block} .none::before{content:none}"]}
    );
    defer t.deinit();
    const tx = t.byId("t");
    try std.testing.expect(tx.before != none and tx.after != none and tx.own != none);
    try std.testing.expectEqualStrings("<7", t.f.pseudos.items[tx.before].text);
    try std.testing.expectEqual(@as(u8, 255), t.f.pseudos.items[tx.before].cs.color.b);
    try std.testing.expectEqualStrings(">", t.f.pseudos.items[tx.after].text);
    try std.testing.expectEqual(style.Display.block, t.f.pseudos.items[tx.after].cs.display);
    try std.testing.expectEqualStrings("mid", t.f.pseudos.items[tx.own].text);
    const c = t.byId("c");
    try std.testing.expectEqualStrings("<", t.f.pseudos.items[c.before].text);
    try std.testing.expect(t.byId("n").before == none); // content: none
    try std.testing.expect(t.byId("i").before == none); // never for images
    const w = t.byId("w");
    try std.testing.expect(w.before == none and w.after != none);
    try std.testing.expectEqualStrings("tw", t.f.pseudos.items[w.after].text);
    try std.testing.expectEqual(@as(u8, 255), t.f.pseudos.items[w.after].cs.color.r);
    // render nodes: text element "t" becomes a container: one paragraph (before + own text), then the block ::after
    var tn: u32 = none;
    for (t.f.nodes.items, 0..) |n, k| {
        if (n.cs == tx.cs and tn == none) tn = @intCast(k);
    }
    try std.testing.expect(tn != none);
    try std.testing.expectEqual(Kind.container, t.f.nodes.items[tn].kind);
    const first = t.f.nodes.items[tn].first_child;
    try std.testing.expectEqual(Kind.anon_text, t.f.nodes.items[first].kind);
    try std.testing.expectEqual(Kind.text, t.f.nodes.items[t.f.nodes.items[first].next].kind);
}

test "stylesheet selectors see takumi's element tree; options" {
    if (comptime !config.enable_css) return error.SkipZigTest;
    const t = try TestFrame.init(.json,
        \\{"type":"container","children":[
        \\ {"type":"text","id":"t1","className":"i","text":"a"},
        \\ {"type":"container","id":"c1","className":"i"},
        \\ {"type":"container","id":"c2","className":"i","tagName":"section","lang":"vi"}
        \\]}
    ,
        \\{"width":100,"height":100,"lang":"en","fontFamilies":["Inter"],"timeMs":5,
        \\ "css":[".i:first-child{opacity:0.5} section:last-child{opacity:0.25} :root:lang(en){opacity:0.75} :lang(vi){order:3}"]}
    );
    defer t.deinit();
    try std.testing.expectEqual(@as(f32, 0.5), t.byId("t1").cs.opacity); // untagged text: its own first child
    try std.testing.expectEqual(@as(f32, 0.5), t.byId("c1").cs.opacity); // text sibling skipped
    try std.testing.expectEqual(@as(f32, 0.25), t.byId("c2").cs.opacity);
    try std.testing.expectEqual(@as(i32, 3), t.byId("c2").cs.order);
    try std.testing.expectEqual(@as(f32, 0.75), t.el(t.f.dom.root).cs.opacity); // `lang` option on the root
    try std.testing.expectEqualStrings("Inter", t.el(t.f.dom.root).cs.font_family[0]);
    try std.testing.expectEqual(@as(f32, 5), t.f.opts.time_ms);
}

test "keyframes option is parsed and exposed" {
    if (comptime !config.enable_css) return error.SkipZigTest;
    const t = try TestFrame.init(.json, "{\"type\":\"container\"}",
        \\{"width":10,"height":10,"keyframes":{"spin":{"from":{"opacity":0},"to":{"opacity":1}}},
        \\ "css":["@keyframes fade{0%{opacity:0}100%{opacity:1}}"]}
    );
    defer t.deinit();
    try std.testing.expect(t.f.keyframes("spin") != null);
    try std.testing.expect(t.f.keyframes("fade") != null);
    try std.testing.expect(t.f.keyframes("nope") == null);
}

test "animation layering at timeMs: keyframe layer, missing 100%, two animations, inheritance" {
    if (comptime !(config.enable_css and config.enable_animation)) return error.SkipZigTest;
    const t = try TestFrame.init(.json,
        \\{"type":"container","id":"p","className":"p","children":[
        \\ {"type":"container","id":"a","className":"a","style":{"opacity":0.5,"width":"10px !important"}},
        \\ {"type":"container","id":"c"}]}
    ,
        \\{"width":100,"height":100,"timeMs":250,"css":[
        \\ "@keyframes w{from{width:0px}to{width:100px}} @keyframes o{50%{opacity:1}}",
        \\ "@keyframes w2{from{width:200px}to{width:400px}} @keyframes col{from{color:#000000}to{color:#ff0000}}",
        \\ ".a{animation:w 1000ms linear, o 1000ms linear, w2 1000ms linear 500ms} .p{animation:col 500ms linear}"]}
    );
    defer t.deinit();
    const a = t.byId("a").cs;
    // keyframes beat `!important` inline; w2 (delay 500ms, fill none) has no effect yet
    try std.testing.expectApproxEqAbs(@as(f32, 25), pxOf(a.width), 0.01);
    // no 0% / 100% keyframes: 0.5 -> 1 over the first half
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), a.opacity, 0.001);
    // the parent's animated colour is inherited by the children
    const pc = t.byId("p").cs.color;
    try std.testing.expect(pc.r > 120 and pc.r < 135);
    try std.testing.expectEqual(pc.r, t.byId("c").cs.color.r);
    try std.testing.expectEqual(pc.r, a.color.r);
}

test "animation: later animation wins per property; default timeMs is 0 with backwards fill" {
    if (comptime !(config.enable_css and config.enable_animation)) return error.SkipZigTest;
    {
        const t = try TestFrame.init(.json, "{\"type\":\"container\",\"id\":\"a\",\"className\":\"a\"}",
            \\{"width":10,"height":10,"timeMs":750,"css":["@keyframes w{to{width:100px}} @keyframes w2{from{width:200px}to{width:400px}}",
            \\ ".a{width:0px;animation:w 1000ms linear, w2 1000ms linear 500ms}"]}
        );
        defer t.deinit();
        try std.testing.expectApproxEqAbs(@as(f32, 250), pxOf(t.byId("a").cs.width), 0.01);
    }
    {
        const t = try TestFrame.init(.json, "{\"type\":\"container\",\"id\":\"a\",\"className\":\"a\"}",
            \\{"width":10,"height":10,"css":["@keyframes f{from{opacity:0.2}to{opacity:1}} .a{animation:f 1s linear 1s backwards}"]}
        );
        defer t.deinit();
        try std.testing.expectApproxEqAbs(@as(f32, 0.2), t.byId("a").cs.opacity, 0.001);
    }
}

test "svg intrinsic size mapping (takumi probe values)" {
    const S = SvgSize;
    const eq = struct {
        fn f(want: S, got: S) !void {
            try std.testing.expectApproxEqAbs(want.w, got.w, 0.001);
            try std.testing.expectApproxEqAbs(want.h, got.h, 0.001);
            try std.testing.expectApproxEqAbs(want.ratio, got.ratio, 0.001);
        }
    }.f;
    const vb: [4]f32 = .{ 0, 0, 40, 20 };
    try eq(.{ .w = 40, .h = 20, .ratio = 2 }, svgSizeFrom(40, 20, null, 1));
    try eq(.{ .w = 0, .h = 0, .ratio = 2 }, svgSizeFrom(null, null, vb, 1));
    try eq(.{ .w = 80, .h = 40, .ratio = 2 }, svgSizeFrom(40, null, vb, 2));
    try eq(.{ .w = 80, .h = 40, .ratio = 2 }, svgSizeFrom(null, 40, vb, 1));
    try eq(.{ .w = 300, .h = 150, .ratio = 0 }, svgSizeFrom(null, null, null, 1));
    try eq(.{ .w = 600, .h = 60, .ratio = 0 }, svgSizeFrom(null, 30, null, 2));
    try eq(.{ .w = 40, .h = 150, .ratio = 0 }, svgSizeFrom(40, null, null, 1));
    try std.testing.expectEqual(@as(?f32, 24), svgLength("2em"));
    try std.testing.expectEqual(@as(?f32, 24), svgLength(" 2rem "));
    try std.testing.expectEqual(@as(?f32, 12), svgLength("2ex"));
    try std.testing.expectEqual(@as(?f32, 96), svgLength("1in"));
    try std.testing.expectEqual(@as(?f32, 40), svgLength("40px"));
    try std.testing.expectEqual(@as(?f32, null), svgLength("50%"));
    try std.testing.expectEqual(@as(?f32, null), svgLength("0"));
    try std.testing.expectEqual(@as(?f32, null), svgLength(null));
}

test "data: URI decoding (base64, percent-encoded, malformed escapes)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings("<svg a=\"1\">", decodeDataUri(a, "data:image/svg+xml,%3Csvg%20a=%221%22%3E").?);
    try std.testing.expectEqualStrings("<svg>", decodeDataUri(a, "data:image/svg+xml;utf8,<svg>").?);
    try std.testing.expectEqualStrings("100%zz%4", decodeDataUri(a, "data:text/plain,100%25zz%4").?);
    try std.testing.expectEqualStrings("<svg/>", decodeDataUri(a, "data:image/svg+xml;BASE64,PHN2Zy8+").?);
    try std.testing.expect(decodeDataUri(a, "data:nocomma") == null);
}

test "svg image sources: intrinsic size, inline markup, data URIs" {
    if (comptime !config.enable_svg) return error.SkipZigTest;
    const t = try TestFrame.init(.json,
        \\{"type":"container","style":{"display":"flex","alignItems":"flex-start"},"children":[
        \\ {"type":"image","src":"<svg xmlns='http://www.w3.org/2000/svg' width='40' height='20'/>"},
        \\ {"type":"image","src":"data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20height='10'%20viewBox='0%200%2040%2020'/%3E"},
        \\ {"type":"image","src":"<svg xmlns='http://www.w3.org/2000/svg'/>"}]}
    , "{\"width\":400,\"height\":300,\"devicePixelRatio\":2}");
    defer t.deinit();
    var seen: usize = 0;
    for (t.f.nodes.items) |n| {
        if (n.kind != .image) continue;
        try std.testing.expect(n.svg != null and n.img == null);
        const want: [2]f32 = switch (seen) {
            0 => .{ 80, 40 },
            1 => .{ 40, 20 },
            else => .{ 600, 300 },
        };
        try std.testing.expectEqual(want[0], n.img_w);
        try std.testing.expectEqual(want[1], n.img_h);
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), seen);
}

test "renderAnimation: frame schedule, formats, errors; ico output" {
    if (comptime !(config.enable_animation and config.enable_extra_codecs)) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const r = Renderer.create(gpa).?;
    defer r.destroy();
    const scene = "{\"type\":\"container\",\"style\":{\"width\":8,\"height\":8,\"backgroundColor\":\"red\"}}";
    for ([_][]const u8{ "webp", "apng", "gif" }) |fmt| {
        var buf: [512]u8 = undefined;
        const j = try std.fmt.bufPrint(&buf, "{{\"scenes\":[{{\"node\":{s},\"durationMs\":250}},{{\"node\":{{\"type\":\"container\",\"style\":{{\"width\":8,\"height\":8,\"backgroundColor\":\"blue\"}}}},\"durationMs\":100}}],\"width\":8,\"height\":8,\"fps\":10,\"format\":\"{s}\"}}", .{ scene, fmt });
        const out = try r.renderAnimation(j);
        // 4 frames (red 0/100/200, blue 300); identical neighbours may be merged by the encoder
        const n = codec.frameCount(out);
        try std.testing.expect(n >= 2 and n <= 4);
    }
    try std.testing.expectError(error.Invalid, r.renderAnimation("{\"scenes\":[],\"width\":8,\"height\":8,\"fps\":10}"));
    try std.testing.expectError(error.Invalid, r.renderAnimation("{\"scenes\":[{\"node\":{\"type\":\"container\"},\"durationMs\":100}],\"width\":8,\"height\":8,\"fps\":0}"));
    try std.testing.expectError(error.Invalid, r.renderAnimation("{\"scenes\":[{\"node\":{\"type\":\"container\"},\"durationMs\":100}],\"width\":8,\"height\":8,\"fps\":51,\"format\":\"gif\"}"));
    try std.testing.expect(std.mem.indexOf(u8, r.err, "maximum 50 fps") != null);
    const ico = try r.render(scene, "{\"width\":8,\"height\":8,\"format\":\"ico\"}");
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 1, 0, 1, 0, 8, 8 }, ico[0..8]);
    try std.testing.expectError(error.Invalid, r.render(scene, "{\"width\":300,\"height\":8,\"format\":\"ico\"}"));
}

// ---- phase 2 layout integration (tables, floats, inline rows, grid names)

/// Render node of the element with `id` (`.el` set), or none.
fn nodeOfId(t: *TestFrame, id: []const u8) u32 {
    for (t.f.nodes.items, 0..) |n, k| {
        if (n.el != none and std.mem.eql(u8, t.f.dom.at(n.el).id, id)) return @intCast(k);
    }
    return none;
}

fn kindsOf(t: *TestFrame, id: u32, buf: []Kind) []Kind {
    var n: usize = 0;
    var c = t.f.nodes.items[id].first_child;
    while (c != none and n < buf.len) : (c = t.f.nodes.items[c].next) {
        buf[n] = t.f.nodes.items[c].kind;
        n += 1;
    }
    return buf[0..n];
}

fn styleOfId(t: *TestFrame, id: []const u8) *const layout.Style {
    return t.f.tree.style(t.f.nodes.items[nodeOfId(t, id)].lid);
}

test "layout2: table spans from td/th/col attributes" {
    if (comptime !config.enable_tables) return error.SkipZigTest;
    try std.testing.expectEqual(@as(?u32, 3), parseSpanAttr(" +3x"));
    try std.testing.expectEqual(@as(?u32, null), parseSpanAttr("x3"));
    try std.testing.expectEqual(@as(?u32, 1 << 30), parseSpanAttr("99999999999999"));
    const t = try TestFrame.init(.json,
        \\{"type":"container","style":{"display":"table"},"children":[
        \\ {"type":"container","tagName":"colgroup","id":"g","style":{"display":"table-column-group"},"attributes":{"span":"0"}},
        \\ {"type":"container","tagName":"col","id":"col","style":{"display":"table-column"},"attributes":{"span":"2"}},
        \\ {"type":"container","style":{"display":"table-row"},"children":[
        \\  {"type":"container","tagName":"td","id":"a","style":{"display":"table-cell"},"attributes":{"colspan":"2","rowspan":"0"}},
        \\  {"type":"text","tagName":"TH","id":"b","text":"x","style":{"display":"table-cell"},"attributes":{"colspan":"5000","rowspan":"3"}},
        \\  {"type":"container","tagName":"div","id":"c","style":{"display":"table-cell"},"attributes":{"colspan":"2"}}]}]}
    , "{\"width\":200,\"height\":100}");
    defer t.deinit();
    try std.testing.expectEqual(@as(u16, 1), styleOfId(t, "g").col_span); // clamped to 1
    try std.testing.expectEqual(@as(u16, 2), styleOfId(t, "col").col_span);
    try std.testing.expectEqual(layout.Display.table_column, styleOfId(t, "col").display);
    try std.testing.expect(styleOfId(t, "a").col_span == 2 and styleOfId(t, "a").row_span == 65534); // rowspan=0: all rows
    try std.testing.expect(styleOfId(t, "b").col_span == 1000 and styleOfId(t, "b").row_span == 3);
    try std.testing.expectEqual(@as(u16, 1), styleOfId(t, "c").col_span); // only td / th
    // a text element with a table-cell display holds its text as a child leaf
    const b = nodeOfId(t, "b");
    try std.testing.expectEqual(Kind.container, t.f.nodes.items[b].kind);
    try std.testing.expectEqual(Kind.anon_text, t.f.nodes.items[t.f.nodes.items[b].first_child].kind);
    try std.testing.expectEqual(layout.Display.table_cell, styleOfId(t, "b").display);
}

test "layout2: inline-level runs, atomic inlines and anonymous line containers" {
    const t = try TestFrame.init(.json,
        \\{"type":"container","style":{"display":"block"},"children":[
        \\ {"type":"container","id":"txt","style":{"display":"block"},"children":[{"type":"text","text":"a "},{"type":"container","children":[{"type":"text","text":"b"}]}]},
        \\ {"type":"container","id":"mix","style":{"display":"block","textAlign":"center"},"children":[{"type":"text","text":" a "},
        \\   {"type":"container","style":{"display":"inline-block","width":10,"height":10}},{"type":"text","text":" "},
        \\   {"type":"container","style":{"display":"inline-flex","width":10,"height":10}},{"type":"text","text":" b "}]},
        \\ {"type":"container","id":"blk","style":{"display":"block"},"children":[{"type":"container","style":{"display":"block"}},
        \\   {"type":"image","src":"x","width":5,"height":5},{"type":"image","src":"x","style":{"float":"left"}}]},
        \\ {"type":"container","id":"flex","style":{"display":"flex"},"children":[{"type":"container","style":{"display":"inline-block"}},{"type":"text","text":"t"}]}]}
    , "{\"width\":200,\"height\":100}");
    defer t.deinit();
    var buf: [8]Kind = undefined;
    // text only: one merged paragraph leaf, no line container
    try std.testing.expectEqualSlices(Kind, &.{.anon_text}, kindsOf(t, nodeOfId(t, "txt"), &buf));
    // mixed: one inline formatting context: its paragraph holds the text, its children are the boxes
    const mix = nodeOfId(t, "mix");
    try std.testing.expectEqualSlices(Kind, &.{.anon_box}, kindsOf(t, mix, &buf));
    const row = t.f.nodes.items[mix].first_child;
    try std.testing.expectEqualSlices(Kind, &.{ .container, .container }, kindsOf(t, row, &buf));
    const rst = t.f.tree.style(t.f.nodes.items[row].lid);
    try std.testing.expectEqual(layout.Display.inline_row, rst.display);
    try std.testing.expectEqual(layout.Position.static, rst.position);
    try std.testing.expect(rst.is_inline_content);
    const rn = &t.f.nodes.items[row];
    try std.testing.expect(rn.para != null and rn.para.?.complex);
    // the line layout of the pass is kept: two objects on one centred line, a space between them
    const tl = rn.tl.?;
    try std.testing.expectEqual(@as(usize, 1), tl.lines.len);
    try std.testing.expectEqual(@as(usize, 2), tl.objects.len);
    const gap = tl.objects[1].x - (tl.objects[0].x + 10);
    try std.testing.expect(gap > 3 and gap < 6);
    try std.testing.expect(tl.lines[0].x > 50 and tl.objects[0].x > tl.lines[0].x);
    const b0 = t.f.tree.layout(t.f.nodes.items[rn.first_child].lid);
    try std.testing.expectApproxEqAbs(tl.objects[0].x, b0.x, 0.02);
    // block + inline image + float: the image and the float share one inline formatting context
    if (config.enable_floats) {
        try std.testing.expectEqualSlices(Kind, &.{ .container, .anon_box }, kindsOf(t, nodeOfId(t, "blk"), &buf));
    } else try std.testing.expectEqualSlices(Kind, &.{ .container, .anon_box, .image }, kindsOf(t, nodeOfId(t, "blk"), &buf));
    // flex containers blockify everything
    try std.testing.expectEqualSlices(Kind, &.{ .container, .text }, kindsOf(t, nodeOfId(t, "flex"), &buf));
    // the root establishes a block formatting context
    try std.testing.expect(t.f.tree.style(t.f.nodes.items[t.f.root].lid).flow_root);
}

/// Layout width of the k-th child of render node `id`.
fn layoutWidth(t: *TestFrame, id: u32, k: usize) !f32 {
    var c = t.f.nodes.items[id].first_child;
    var i: usize = 0;
    while (c != none) : (c = t.f.nodes.items[c].next) {
        if (i == k) return t.f.tree.layout(t.f.nodes.items[c].lid).w;
        i += 1;
    }
    return error.NoSuchChild;
}

test "layout2: line container strut (Geist example and font metrics)" {
    // 16 px Geist: A = 16, D = 5, L = 21 -> strut 16 / 5; middle = x-height / 2
    const g = strutFrom(geist_em, 16, .normal);
    try std.testing.expectEqual(@as(f32, 16), g[0]);
    try std.testing.expectEqual(@as(f32, 5), g[1]);
    try std.testing.expectApproxEqAbs(@as(f32, 4.24), g[2], 1e-4);
    // line-height 1.5: L = 24, half-leading floor(3 / 2) = 1 above, 2 below
    const h = strutFrom(geist_em, 16, .{ .number = 1.5 });
    try std.testing.expect(h[0] == 17 and h[1] == 7);
    // a line-height below the content area: negative descent
    const s = strutFrom(geist_em, 16, .{ .px = 4 });
    try std.testing.expect(s[0] == 7 and s[1] == -3);
    // with Inter registered its metrics are used (ascent 0.96875 -> 16, descent 0.2421875 -> 4)
    const t = try TestFrame.init(.json, "{\"type\":\"container\",\"style\":{\"display\":\"block\",\"fontSize\":16},\"children\":[{\"type\":\"image\",\"src\":\"x\",\"width\":4,\"height\":4}]}", "{\"width\":50,\"height\":50}");
    defer t.deinit();
    const row = t.f.nodes.items[t.f.root].first_child;
    try std.testing.expectEqual(Kind.anon_box, t.f.nodes.items[row].kind);
    // the line is the strut: image bottom on the baseline
    const il = t.f.tree.layout(t.f.nodes.items[t.f.nodes.items[row].first_child].lid);
    try std.testing.expectEqual(@as(f32, 12), il.y);
    try std.testing.expectEqual(@as(f32, 20), t.f.tree.layout(t.f.nodes.items[row].lid).h);
}

test "layout2: grid template areas and named lines" {
    const t = try TestFrame.init(.json,
        \\{"type":"container","style":{"display":"grid","gridTemplateAreas":"\"h h h\" \"s m m\"","gridTemplateColumns":"[a] 10px [b] 10px [a] 10px [a]"},"children":[
        \\ {"type":"container","id":"m","style":{"gridArea":"m"}},
        \\ {"type":"container","id":"h","style":{"gridRow":"h","gridColumn":"h-start / h-end"}},
        \\ {"type":"container","id":"n","style":{"gridColumn":"a / span a"}},
        \\ {"type":"container","id":"bk","style":{"gridColumnStart":"span a","gridColumnEnd":"-1"}},
        \\ {"type":"container","id":"u","style":{"gridColumn":"zzz","gridRow":"1"}}]}
    , "{\"width\":200,\"height\":100}");
    defer t.deinit();
    const S = struct {
        fn eq(p: layout.Placement, s: layout.Line, e: layout.Line) !void {
            try std.testing.expectEqual(s, p.start);
            try std.testing.expectEqual(e, p.end);
        }
    };
    try S.eq(styleOfId(t, "m").grid_row, .{ .line = 2 }, .{ .line = 3 });
    try S.eq(styleOfId(t, "m").grid_column, .{ .line = 2 }, .{ .line = 4 });
    // a single name in the grid-row / grid-column shorthand leaves the end auto (takumi)
    try S.eq(styleOfId(t, "h").grid_row, .{ .line = 1 }, .auto);
    try S.eq(styleOfId(t, "h").grid_column, .{ .line = 1 }, .{ .line = 4 });
    // first line named a = 1; `span <name>` is span 1 (takumi)
    try S.eq(styleOfId(t, "n").grid_column, .{ .line = 1 }, .{ .span = 1 });
    try S.eq(styleOfId(t, "bk").grid_column, .{ .span = 1 }, .{ .line = -1 });
    // unknown name: the first implicit line after the explicit grid (4 explicit lines)
    try S.eq(styleOfId(t, "u").grid_column, .{ .line = 5 }, .auto);
    // the areas size the explicit grid: two rows although grid-template-rows is none
    try std.testing.expectEqual(@as(usize, 2), t.f.tree.style(t.f.nodes.items[t.f.root].lid).grid_template_rows.len);
}

test "layout2: measure() tree shape follows takumi (inline content = the block's runs)" {
    const gpa = std.testing.allocator;
    const r = Renderer.create(gpa).?;
    defer r.destroy();
    _ = try r.registerFont(try gpa.dupe(u8, @embedFile("font/testdata/Inter-Regular.ttf")), "", 0, -1);
    const opts = "{\"width\":200,\"height\":100}";
    const count = std.mem.count;
    // block with text only: no child box, two runs (one per source run)
    var out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[{\"type\":\"text\",\"text\":\"a \"},{\"type\":\"text\",\"text\":\"b\",\"style\":{\"color\":\"red\"}}]}", opts);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"children\":[],\"runs\":[{") != null);
    try std.testing.expectEqual(@as(usize, 2), count(u8, out, "{\"x\":"));
    // text, inline-block, text: runs on the block, the inline-block as its only child
    out = try r.measure("{\"type\":\"container\",\"style\":{\"display\":\"block\"},\"children\":[{\"type\":\"text\",\"text\":\"a \"},{\"type\":\"container\",\"style\":{\"display\":\"inline-block\",\"width\":5,\"height\":5}},{\"type\":\"text\",\"text\":\" b\"}]}", opts);
    try std.testing.expectEqual(@as(usize, 2), count(u8, out, "{\"width\":")); // block + inline-block
    try std.testing.expectEqual(@as(usize, 2), count(u8, out, "{\"x\":"));
    // a text element with display: flex reports its anonymous flex item
    out = try r.measure("{\"type\":\"text\",\"text\":\"hi\",\"style\":{\"display\":\"flex\",\"padding\":4}}", opts);
    try std.testing.expect(std.mem.startsWith(u8, out, "{\"width\":200,\"height\":"));
    try std.testing.expect(std.mem.indexOf(u8, out, "\"children\":[{\"width\":") != null);
}
