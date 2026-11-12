//! `renderPdf` / `measurePdf` options: takumi-pdf's `PdfRenderOptions` (takumi-pdf-js options.rs,
//! metadata.rs, date.rs; takumi-pdf options.rs) parsed from the options JSON (src/json.zig), with the
//! validation rules, defaults and error messages of takumi-pdf.
//!
//! Independent of the renderer and of any feature flag, so it is unit-tested natively. All slices of
//! the result point into the arena passed to `parse` (and into the JSON text parsed from it).
//!
//! JS wire format (js/engine.mjs `#pdfOptions`): the options object as JSON, where
//!   * a band (`header`, `footer`, `pages.*.header|footer`) is a node object, an HTML string or `false`;
//!   * an attachment's `data` is a string (UTF-8 text) or, for binary data, `dataRef` = the id of a blob
//!     the binding moved into the renderer's resource store (`bm_put_image`, ids "bm-att:<n>");
//!   * `images` / `fonts` / `signal` never reach the wasm (images are registered by id beforehand).
const std = @import("std");
const json = @import("../json.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{ OutOfMemory, Invalid };

// ---- geometry constants (takumi-core units.rs, f32 arithmetic exactly as Rust)

pub const one_cm_in_px: f32 = @as(f32, 96.0) / @as(f32, 2.54);
pub const one_mm_in_px: f32 = one_cm_in_px / 10.0;
pub const one_in_px: f32 = @as(f32, 2.54) * one_cm_in_px;
pub const one_pt_in_px: f32 = one_in_px / 72.0;
/// CSS px (96 dpi) to PDF pt (72 dpi).
pub const pt_per_px: f32 = 1.0 / one_pt_in_px;
/// The margin a page starts with (10 mm, what Chromium prints at).
pub const default_margin: f32 = 10.0 * one_mm_in_px;
/// The 15pt band inset of Chromium's `print_header_footer_template_page.html`.
pub const band_edge_padding: f32 = 15.0 * one_pt_in_px;

// ---- types

pub const Margin = union(enum) {
    px: f32,
    /// The space the band on that side takes (at least `default_margin`, and 0 on an axis <= 1 inch).
    auto,

    /// `axis` is the paper length along the side's own axis; `band_height` the band drawn on that side.
    pub fn resolve(self: Margin, axis: f32, band_height: ?f32) f32 {
        return switch (self) {
            .px => |v| v,
            .auto => if (axis <= one_in_px) 0 else if (band_height) |h| @max(h + band_edge_padding, default_margin) else default_margin,
        };
    }
};

pub const Margins = struct {
    top: Margin = .auto,
    right: Margin = .auto,
    bottom: Margin = .auto,
    left: Margin = .auto,

    /// Whether a band height can move a margin.
    pub fn followBands(self: Margins) bool {
        return self.top == .auto or self.bottom == .auto;
    }
};

pub const Rect = struct { top: f32, right: f32, bottom: f32, left: f32 };

/// Paged output geometry in CSS px: page size plus margins.
pub const Page = struct {
    width: f32,
    height: f32,
    margin: Margins = .{},

    pub const a3 = preset(297.0 * one_mm_in_px, 420.0 * one_mm_in_px);
    pub const a4 = preset(210.0 * one_mm_in_px, 297.0 * one_mm_in_px);
    pub const a5 = preset(148.0 * one_mm_in_px, 210.0 * one_mm_in_px);
    pub const b4 = preset(250.0 * one_mm_in_px, 353.0 * one_mm_in_px);
    pub const b5 = preset(176.0 * one_mm_in_px, 250.0 * one_mm_in_px);
    pub const jis_b4 = preset(257.0 * one_mm_in_px, 364.0 * one_mm_in_px);
    pub const jis_b5 = preset(182.0 * one_mm_in_px, 257.0 * one_mm_in_px);
    pub const ledger = preset(11.0 * one_in_px, 17.0 * one_in_px);
    pub const legal = preset(8.5 * one_in_px, 14.0 * one_in_px);
    pub const letter = preset(8.5 * one_in_px, 11.0 * one_in_px);

    fn preset(w: f32, h: f32) Page {
        return .{ .width = w, .height = h };
    }

    pub fn landscape(self: Page) Page {
        return .{ .width = self.height, .height = self.width, .margin = self.margin };
    }

    /// Margins with every `auto` replaced by the band it sits under (`header` / `footer` heights).
    pub fn resolveMargins(self: Page, header: ?f32, footer: ?f32) Rect {
        const m = self.margin;
        return .{
            .top = m.top.resolve(self.height, header),
            .right = m.right.resolve(self.width, null),
            .bottom = m.bottom.resolve(self.height, footer),
            .left = m.left.resolve(self.width, null),
        };
    }

    /// The area inside the margins, or null when it is empty (takumi `InvalidPageSize`).
    pub fn contentSize(self: Page, margin: Rect) ?struct { width: f32, height: f32 } {
        const w = self.width - (margin.left + margin.right);
        const h = self.height - (margin.top + margin.bottom);
        if (!(w >= 1.0 and h >= 1.0)) return null;
        return .{ .width = w, .height = h };
    }

    /// Looks a CSS Paged Media keyword up (ASCII case-insensitive).
    pub fn named(name: []const u8) ?Page {
        var buf: [16]u8 = undefined;
        if (name.len > buf.len) return null;
        const lower = std.ascii.lowerString(&buf, name);
        const table = .{
            .{ "a3", a3 },         .{ "a4", a4 },         .{ "a5", a5 },
            .{ "b4", b4 },         .{ "b5", b5 },         .{ "jis-b4", jis_b4 },
            .{ "jis-b5", jis_b5 }, .{ "ledger", ledger }, .{ "legal", legal },
            .{ "letter", letter },
        };
        inline for (table) |e| if (std.mem.eql(u8, lower, e[0])) return e[1];
        return null;
    }
};

/// Single-page viewport (CSS px). A missing height sizes the page to the laid-out content.
pub const Viewport = struct { width: u32, height: ?u32 };

pub const Geometry = union(enum) {
    viewport: Viewport,
    page: Page,
};

/// What a page draws in a band: nothing, a node tree (a JSON node object) or HTML markup.
pub const Band = union(enum) {
    off,
    node: json.Value,
    html: []const u8,
};

pub const PageOverride = struct { header: ?Band = null, footer: ?Band = null };

/// `first` and `last` win over `odd` and `even`; a field left out falls through to the document's band.
pub const PageRules = struct {
    first: PageOverride = .{},
    last: PageOverride = .{},
    odd: PageOverride = .{},
    even: PageOverride = .{},

    /// The band page `page` of `pages` (1-based) draws: `default` unless a rule replaces it.
    /// null = draws nothing. `which` selects header (true) or footer (false) of the rule.
    pub fn bandFor(self: PageRules, header: bool, default: ?Band, page: usize, pages: usize) ?Band {
        const pick = struct {
            fn f(o: PageOverride, h: bool) ?Band {
                return if (h) o.header else o.footer;
            }
        }.f;
        const parity = if (page % 2 == 1) self.odd else self.even;
        const rule = (if (page == 1) pick(self.first, header) else null) orelse
            (if (page == pages) pick(self.last, header) else null) orelse pick(parity, header);
        const chosen = rule orelse return default;
        return switch (chosen) {
            .off => null,
            else => chosen,
        };
    }
};

/// A 1-based inclusive span of pages to keep. null `from` starts at page 1, null `to` runs to the end.
pub const PageRange = struct {
    from: ?usize = null,
    to: ?usize = null,

    fn contains(self: PageRange, page: usize) bool {
        return (self.from orelse 1) <= page and page <= (self.to orelse std.math.maxInt(usize));
    }
};

pub const PdfDate = struct { year: u16, month: u8, day: u8, hour: u8 = 0, minute: u8 = 0, second: u8 = 0 };

pub const XmpProperty = struct { name: []const u8, value: []const u8, description: []const u8 };
pub const XmpSchema = struct { name: []const u8, prefix: []const u8, namespace: []const u8, properties: []const XmpProperty };

pub const Metadata = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    authors: []const []const u8 = &.{},
    keywords: []const []const u8 = &.{},
    creator: ?[]const u8 = null,
    creation_date: ?PdfDate = null,
    xmp: []const XmpSchema = &.{},
};

pub const Relationship = enum { source, data, alternative, supplement, unspecified };

pub const Attachment = struct {
    name: []const u8,
    /// The file's bytes (a copy-free view into the renderer's resource store, or the JSON string).
    data: []const u8,
    mime_type: ?[]const u8 = null,
    description: ?[]const u8 = null,
    relationship: Relationship = .unspecified,
    modification_date: ?PdfDate = null,
};

/// PDF/A conformance level (`none` = plain PDF 1.7, no validation).
pub const Pdfa = enum {
    none,
    a2a,
    a2b,
    a2u,
    a3a,
    a3b,
    a3u,
    a4,
    a4f,

    pub fn label(self: Pdfa) []const u8 {
        return switch (self) {
            .none => "none",
            .a2a => "PDF/A-2a",
            .a2b => "PDF/A-2b",
            .a2u => "PDF/A-2u",
            .a3a => "PDF/A-3a",
            .a3b => "PDF/A-3b",
            .a3u => "PDF/A-3u",
            .a4 => "PDF/A-4",
            .a4f => "PDF/A-4f",
        };
    }

    /// The `a` levels imply a structure tree.
    pub fn requiresTagging(self: Pdfa) bool {
        return self == .a2a or self == .a3a;
    }

    /// PDF/A-3 and PDF/A-4f accept attachments (and require their descriptive fields).
    pub fn allowsAttachments(self: Pdfa) bool {
        return switch (self) {
            .none, .a3a, .a3b, .a3u, .a4f => true,
            else => false,
        };
    }

    pub fn isPdf2(self: Pdfa) bool {
        return self == .a4 or self == .a4f;
    }

    fn fromString(s: []const u8) ?Pdfa {
        const table = [_]struct { []const u8, Pdfa }{
            .{ "2a", .a2a }, .{ "2b", .a2b }, .{ "2u", .a2u }, .{ "3a", .a3a },
            .{ "3b", .a3b }, .{ "3u", .a3u }, .{ "4", .a4 },   .{ "4f", .a4f },
        };
        for (table) |e| if (std.mem.eql(u8, s, e[0])) return e[1];
        return null;
    }
};

/// Structure-tree emission and the accessibility standard it is validated against.
pub const Tagging = enum {
    off,
    on,
    ua1,
    ua2,

    pub fn label(self: Tagging) ?[]const u8 {
        return switch (self) {
            .off, .on => null,
            .ua1 => "PDF/UA-1",
            .ua2 => "PDF/UA-2",
        };
    }
};

pub const UncoveredText = enum { @"error", placeholder, blank };

pub const PdfOptions = struct {
    /// Single-page viewport, or paged geometry (A4 when neither is given).
    geometry: Geometry = .{ .page = Page.a4 },
    /// Paper colour as a CSS colour string (validated by the caller), painted under every page.
    background_color: ?[]const u8 = null,
    header: ?Band = null,
    footer: ?Band = null,
    pages: PageRules = .{},
    page_ranges: ?[]const PageRange = null,
    /// `css`: a string, a rule object or an array of them (src/render.zig `Options.css` form).
    css: ?json.Value = null,
    /// `cssVariables` as (name with `--` prefix, value) pairs.
    css_variables: []const [2][]const u8 = &.{},
    font_families: []const []const u8 = &.{},
    failed_font_files: []const []const u8 = &.{},
    lang: []const u8 = "",
    metadata: ?Metadata = null,
    outline: bool = false,
    pdfa: Pdfa = .none,
    tagged: Tagging = .on,
    attachments: []const Attachment = &.{},
    uncovered_text: UncoveredText = .@"error",

    /// Whether the document carries a structure tree: asked for, or required by the standard.
    pub fn writesStructure(self: PdfOptions) bool {
        return self.tagged != .off or self.pdfa.requiresTagging();
    }
};

/// A binary resource the JS binding moved into the renderer (`dataRef` target).
pub const Blob = struct { id: []const u8, data: []const u8 };

/// Error message sink (no allocation: fixed buffer, truncated).
pub const Diag = struct {
    buf: [320]u8 = undefined,
    len: usize = 0,

    pub fn set(self: *Diag, parts: []const []const u8) void {
        self.len = 0;
        for (parts) |p| {
            const n = @min(p.len, self.buf.len - self.len);
            @memcpy(self.buf[self.len..][0..n], p[0..n]);
            self.len += n;
        }
    }

    pub fn message(self: *const Diag) []const u8 {
        return self.buf[0..self.len];
    }
};

fn fail(d: *Diag, parts: []const []const u8) Error {
    d.set(parts);
    return error.Invalid;
}

// ---- parsing

/// Parses and validates `text` (the options JSON; empty = all defaults). `blobs` resolve attachment
/// `dataRef`s. On `error.Invalid`, `diag.message()` holds takumi-pdf's message.
pub fn parse(a: Allocator, text: []const u8, blobs: []const Blob, diag: *Diag) Error!PdfOptions {
    if (text.len == 0) return .{};
    const v = json.parse(a, text) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return fail(diag, &.{"invalid options JSON"}),
    };
    return fromValue(a, v, blobs, diag);
}

/// A present, non-null member.
fn field(v: json.Value, key: []const u8) ?json.Value {
    if (v.get(key)) |x| if (x != .null) return x;
    return null;
}

pub fn fromValue(a: Allocator, v: json.Value, blobs: []const Blob, diag: *Diag) Error!PdfOptions {
    var o: PdfOptions = .{};
    if (v != .object) return o;

    o.geometry = try parseGeometry(v, diag);

    if (field(v, "backgroundColor")) |x| o.background_color = try str(x, "backgroundColor", diag);
    if (field(v, "header")) |x| o.header = try parseBand(x, "header", diag);
    if (field(v, "footer")) |x| o.footer = try parseBand(x, "footer", diag);
    if (field(v, "pages")) |x| o.pages = try parseRules(x, diag);
    if (field(v, "pageRanges")) |x| o.page_ranges = try parseRanges(a, x, diag);
    if (field(v, "css")) |x| o.css = x;
    if (field(v, "cssVariables")) |x| o.css_variables = try parseVars(a, x, diag);
    if (field(v, "fontFamilies")) |x| o.font_families = try strList(a, x, "fontFamilies", diag);
    if (field(v, "failedFontFiles")) |x| o.failed_font_files = try strList(a, x, "failedFontFiles", diag);
    if (field(v, "lang")) |x| o.lang = try str(x, "lang", diag);
    if (field(v, "metadata")) |x| o.metadata = try parseMetadata(a, x, diag);
    if (field(v, "outline")) |x| o.outline = try boolean(x, "outline", diag);
    if (field(v, "pdfa")) |x| {
        const s = x.asString() orelse return fail(diag, &.{"invalid pdfa: expected \"2a\", \"2b\", \"2u\", \"3a\", \"3b\", \"3u\", \"4\" or \"4f\""});
        o.pdfa = Pdfa.fromString(s) orelse return fail(diag, &.{ "unknown pdfa level: ", s, " (expected 2a, 2b, 2u, 3a, 3b, 3u, 4 or 4f)" });
    }
    var tagged_set = false;
    if (field(v, "tagged")) |x| {
        tagged_set = true;
        o.tagged = switch (x) {
            .bool => |b| if (b) .on else .off,
            .string => |s| if (std.mem.eql(u8, s, "ua1")) .ua1 else if (std.mem.eql(u8, s, "ua2")) .ua2 else return fail(diag, &.{"invalid tagged: expected true, false, \"ua1\" or \"ua2\""}),
            else => return fail(diag, &.{"invalid tagged: expected true, false, \"ua1\" or \"ua2\""}),
        };
    }
    if (field(v, "attachments")) |x| o.attachments = try parseAttachments(a, x, blobs, diag);
    if (field(v, "uncoveredText")) |x| {
        const s = x.asString() orelse return fail(diag, &.{"invalid uncoveredText: expected \"error\", \"placeholder\" or \"blank\""});
        o.uncovered_text = if (std.mem.eql(u8, s, "error")) .@"error" else if (std.mem.eql(u8, s, "placeholder")) .placeholder else if (std.mem.eql(u8, s, "blank")) .blank else return fail(diag, &.{ "unknown uncoveredText: ", s });
    }
    try validate(&o, tagged_set, diag);
    return o;
}

fn str(x: json.Value, name: []const u8, d: *Diag) Error![]const u8 {
    return x.asString() orelse fail(d, &.{ "invalid ", name, ": expected a string" });
}

fn boolean(x: json.Value, name: []const u8, d: *Diag) Error!bool {
    return x.asBool() orelse fail(d, &.{ "invalid ", name, ": expected a boolean" });
}

fn strList(a: Allocator, x: json.Value, name: []const u8, d: *Diag) Error![]const []const u8 {
    if (x != .array) return fail(d, &.{ "invalid ", name, ": expected an array of strings" });
    const out = try a.alloc([]const u8, x.array.len);
    for (x.array, 0..) |e, i| out[i] = try str(e, name, d);
    return out;
}

fn parseVars(a: Allocator, x: json.Value, d: *Diag) Error![]const [2][]const u8 {
    if (x != .object) return fail(d, &.{"invalid cssVariables: expected an object of strings"});
    const out = try a.alloc([2][]const u8, x.object.len);
    for (x.object, 0..) |m, i| {
        const val = try str(m.value, "cssVariables", d);
        // A name without the `--` prefix gains it.
        out[i] = .{ if (std.mem.startsWith(u8, m.key, "--")) m.key else try std.mem.concat(a, u8, &.{ "--", m.key }), val };
    }
    return out;
}

// -- geometry

/// A margin side value: a number (px) or the keyword "auto".
fn parseSide(x: json.Value, d: *Diag) Error!Margin {
    switch (x) {
        .number => |n| return .{ .px = @floatCast(n) },
        .string => |s| if (std.mem.eql(u8, s, "auto")) return .auto,
        else => {},
    }
    return fail(d, &.{"invalid margin: expected a number or \"auto\""});
}

fn parseMargin(x: json.Value, d: *Diag) Error!Margins {
    if (x == .object) {
        var m: Margins = .{};
        if (field(x, "top")) |s| m.top = try parseSide(s, d);
        if (field(x, "right")) |s| m.right = try parseSide(s, d);
        if (field(x, "bottom")) |s| m.bottom = try parseSide(s, d);
        if (field(x, "left")) |s| m.left = try parseSide(s, d);
        return m;
    }
    const side = try parseSide(x, d);
    return .{ .top = side, .right = side, .bottom = side, .left = side };
}

fn num(x: json.Value, name: []const u8, d: *Diag) Error!f32 {
    return x.asNumber() orelse fail(d, &.{ "invalid ", name, ": expected a number" });
}

fn dimU32(n: f32) u32 {
    if (!(n >= 1)) return 0;
    return @intFromFloat(@min(n, 16384));
}

fn parseGeometry(v: json.Value, d: *Diag) Error!Geometry {
    const size = field(v, "size");
    const landscape = field(v, "landscape");
    const margin = field(v, "margin");
    const paged_field_set = size != null or landscape != null or margin != null or field(v, "header") != null or
        field(v, "footer") != null or field(v, "pages") != null or field(v, "pageRanges") != null;

    if (field(v, "viewport")) |vp| {
        if (paged_field_set) return fail(d, &.{"viewport is mutually exclusive with the paged options (size, landscape, margin, header, footer, pages, pageRanges)"});
        if (vp != .object) return fail(d, &.{"invalid viewport: expected { width, height? }"});
        const w = try num(field(vp, "width") orelse return fail(d, &.{"invalid viewport: width is required"}), "viewport width", d);
        const h: ?f32 = if (field(vp, "height")) |hx| try num(hx, "viewport height", d) else null;
        const wi = dimU32(w);
        const hi: ?u32 = if (h) |hv| dimU32(hv) else null;
        // (takumi-pdf: a zero side is the page's `InvalidPageSize`)
        if (wi == 0 or (hi != null and hi.? == 0)) return fail(d, &.{"Page size must be finite and larger than zero"});
        return .{ .viewport = .{ .width = wi, .height = hi } };
    }

    var page: Page = Page.a4;
    if (size) |s| switch (s) {
        .string => |name| {
            var lower: [32]u8 = undefined;
            page = Page.named(name) orelse {
                const shown = if (name.len <= lower.len) std.ascii.lowerString(&lower, name) else name;
                return fail(d, &.{ "unknown page size: ", shown });
            };
        },
        .object => {
            const w = try num(field(s, "width") orelse return fail(d, &.{"invalid size: expected a preset name or { width, height }"}), "size width", d);
            const h = try num(field(s, "height") orelse return fail(d, &.{"invalid size: expected a preset name or { width, height }"}), "size height", d);
            page = .{ .width = w, .height = h };
        },
        else => return fail(d, &.{"invalid size: expected a preset name or { width, height }"}),
    };
    if (landscape) |l| {
        if (try boolean(l, "landscape", d)) page = page.landscape();
    }
    if (margin) |m| page.margin = try parseMargin(m, d);
    return .{ .page = page };
}

// -- bands and page rules

fn parseBand(x: json.Value, name: []const u8, d: *Diag) Error!Band {
    return switch (x) {
        .bool => |b| if (!b) .off else fail(d, &.{"a band is a node, HTML, or false; true names nothing"}),
        .object => .{ .node = x },
        .string => |s| .{ .html = s },
        else => fail(d, &.{ "invalid ", name, ": a band is a node, HTML, or false" }),
    };
}

const rule_names = [_][]const u8{ "first", "last", "odd", "even" };

fn parseOverride(x: json.Value, rule: []const u8, d: *Diag) Error!PageOverride {
    if (x != .object) return fail(d, &.{ "pages.", rule, " takes an object" });
    for (x.object) |m| {
        if (!std.mem.eql(u8, m.key, "header") and !std.mem.eql(u8, m.key, "footer")) {
            return fail(d, &.{ "unknown field of pages.", rule, ": ", m.key });
        }
    }
    var o: PageOverride = .{};
    if (field(x, "header")) |h| o.header = try parseBand(h, "pages header", d);
    if (field(x, "footer")) |f| o.footer = try parseBand(f, "pages footer", d);
    return o;
}

fn parseRules(x: json.Value, d: *Diag) Error!PageRules {
    if (x != .object) return fail(d, &.{"pages takes an object"});
    for (x.object) |m| {
        var known = false;
        for (rule_names) |n| known = known or std.mem.eql(u8, m.key, n);
        if (!known) return fail(d, &.{ "unknown page rule: ", m.key });
    }
    var r: PageRules = .{};
    if (field(x, "first")) |s| r.first = try parseOverride(s, "first", d);
    if (field(x, "last")) |s| r.last = try parseOverride(s, "last", d);
    if (field(x, "odd")) |s| r.odd = try parseOverride(s, "odd", d);
    if (field(x, "even")) |s| r.even = try parseOverride(s, "even", d);
    return r;
}

// -- page ranges

fn pageInt(x: json.Value) ?usize {
    if (x != .number) return null;
    const n = x.number;
    if (!(n >= 0) or n != @floor(n) or n > 4.0e9) return null;
    return @intFromFloat(n);
}

fn appendInt(buf: []u8, len: *usize, n: usize) void {
    var tmp: [20]u8 = undefined;
    var i: usize = tmp.len;
    var m = n;
    while (true) {
        i -= 1;
        tmp[i] = '0' + @as(u8, @intCast(m % 10));
        m /= 10;
        if (m == 0) break;
    }
    const s = tmp[i..];
    const k = @min(s.len, buf.len - len.*);
    @memcpy(buf[len.*..][0..k], s[0..k]);
    len.* += k;
}

/// `PageRange`'s Display: "3", "2-4", "2-", "-4".
fn rangeText(r: PageRange, buf: []u8) []const u8 {
    var len: usize = 0;
    if (r.from != null and r.to != null and r.from.? == r.to.?) {
        appendInt(buf, &len, r.from.?);
    } else {
        if (r.from) |f| appendInt(buf, &len, f);
        buf[len] = '-';
        len += 1;
        if (r.to) |t| appendInt(buf, &len, t);
    }
    return buf[0..len];
}

fn invalidRange(d: *Diag, r: PageRange) Error {
    var buf: [48]u8 = undefined;
    return fail(d, &.{ "Page range is invalid: ", rangeText(r, &buf), ". Pages are numbered from 1." });
}

fn parseRanges(a: Allocator, x: json.Value, d: *Diag) Error![]const PageRange {
    if (x != .array) return fail(d, &.{"invalid pageRanges: expected an array of page numbers or { from, to } spans"});
    const out = try a.alloc(PageRange, x.array.len);
    for (x.array, 0..) |e, i| {
        var r: PageRange = .{};
        switch (e) {
            .number => {
                const p = pageInt(e) orelse return fail(d, &.{"Page range is invalid: expected whole page numbers. Pages are numbered from 1."});
                r = .{ .from = p, .to = p };
            },
            .object => {
                if (field(e, "from")) |f| r.from = pageInt(f) orelse return fail(d, &.{"Page range is invalid: expected whole page numbers. Pages are numbered from 1."});
                if (field(e, "to")) |t| r.to = pageInt(t) orelse return fail(d, &.{"Page range is invalid: expected whole page numbers. Pages are numbered from 1."});
            },
            else => return fail(d, &.{"invalid pageRanges: expected an array of page numbers or { from, to } spans"}),
        }
        const backwards = r.from != null and r.to != null and r.from.? > r.to.?;
        if (r.from == 0 or r.to == 0 or backwards) return invalidRange(d, r);
        out[i] = r;
    }
    return out;
}

/// Which of the document's pages the render keeps, each mapped to its index in the output.
pub const PageSelection = struct {
    ranges: ?[]const PageRange,
    emitted: std.ArrayList(?usize) = .empty,
    kept: usize = 0,

    pub fn init(ranges: ?[]const PageRange) PageSelection {
        return .{ .ranges = ranges };
    }

    /// Adds the next page of the document; returns its index in the output when it is kept.
    pub fn pushPage(self: *PageSelection, a: Allocator) Allocator.Error!?usize {
        const page = self.emitted.items.len + 1;
        var kept_page = self.ranges == null;
        if (self.ranges) |rs| for (rs) |r| {
            if (r.contains(page)) kept_page = true;
        };
        const idx: ?usize = if (kept_page) self.kept else null;
        self.kept += @intFromBool(kept_page);
        try self.emitted.append(a, idx);
        return idx;
    }

    /// Checks the ranges keep a page once every page is added ("select none of the document's N pages").
    pub fn finish(self: *const PageSelection, d: *Diag) Error!void {
        if (self.ranges != null and self.kept == 0) {
            var nb: [20]u8 = undefined;
            var n: usize = 0;
            appendInt(&nb, &n, self.emitted.items.len);
            return fail(d, &.{ "The page ranges select none of the document's ", nb[0..n], " pages" });
        }
    }

    pub fn keeps(self: *const PageSelection, index: usize) bool {
        return self.emittedIndex(index) != null;
    }

    pub fn emittedIndex(self: *const PageSelection, index: usize) ?usize {
        return if (index < self.emitted.items.len) self.emitted.items[index] else null;
    }
};

// -- dates

fn digits(part: ?[]const u8, width: usize) ?u32 {
    const p = part orelse return null;
    if (p.len != width) return null;
    var n: u32 = 0;
    for (p) |c| {
        if (c < '0' or c > '9') return null;
        n = n * 10 + (c - '0');
    }
    return n;
}

/// `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS` (optional trailing `Z`), UTC.
pub fn parseDate(value: []const u8) ?PdfDate {
    var date = value;
    var time: ?[]const u8 = null;
    if (std.mem.indexOfScalar(u8, value, 'T')) |t| {
        date = value[0..t];
        const rest = value[t + 1 ..];
        time = if (rest.len > 0 and rest[rest.len - 1] == 'Z') rest[0 .. rest.len - 1] else rest;
    }
    var dp = std.mem.splitScalar(u8, date, '-');
    const year = digits(dp.next(), 4) orelse return null;
    const month = digits(dp.next(), 2) orelse return null;
    // Rust's `splitn(3, '-')`: the day part is the whole remainder.
    const day = digits(dp.rest(), 2) orelse return null;
    var hour: u32 = 0;
    var minute: u32 = 0;
    var second: u32 = 0;
    if (time) |tm| {
        var tp = std.mem.splitScalar(u8, tm, ':');
        hour = digits(tp.next(), 2) orelse return null;
        minute = digits(tp.next(), 2) orelse return null;
        second = digits(tp.rest(), 2) orelse return null;
    }
    const leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
    const dim: u32 = switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (leap) 29 else 28,
        else => return null,
    };
    if (day < 1 or day > dim or hour > 23 or minute > 59 or second > 59) return null;
    return .{ .year = @intCast(year), .month = @intCast(month), .day = @intCast(day), .hour = @intCast(hour), .minute = @intCast(minute), .second = @intCast(second) };
}

// -- metadata and attachments

fn parseMetadata(a: Allocator, x: json.Value, d: *Diag) Error!Metadata {
    if (x != .object) return fail(d, &.{"invalid metadata: expected an object"});
    var m: Metadata = .{};
    if (field(x, "title")) |t| m.title = try str(t, "metadata.title", d);
    if (field(x, "description")) |t| m.description = try str(t, "metadata.description", d);
    if (field(x, "authors")) |t| m.authors = try strList(a, t, "metadata.authors", d);
    if (field(x, "keywords")) |t| m.keywords = try strList(a, t, "metadata.keywords", d);
    if (field(x, "creator")) |t| m.creator = try str(t, "metadata.creator", d);
    if (field(x, "creationDate")) |t| {
        const s = try str(t, "metadata.creationDate", d);
        m.creation_date = parseDate(s) orelse return fail(d, &.{"invalid creationDate: expected YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS"});
    }
    if (field(x, "xmp")) |t| {
        if (t != .array) return fail(d, &.{"invalid metadata.xmp: expected an array of schemas"});
        const out = try a.alloc(XmpSchema, t.array.len);
        for (t.array, 0..) |s, i| {
            if (s != .object) return fail(d, &.{"invalid metadata.xmp: expected an array of schemas"});
            const props_v = field(s, "properties") orelse return fail(d, &.{"invalid metadata.xmp: a schema needs properties"});
            if (props_v != .array) return fail(d, &.{"invalid metadata.xmp: properties is an array"});
            const props = try a.alloc(XmpProperty, props_v.array.len);
            for (props_v.array, 0..) |p, j| {
                props[j] = .{
                    .name = try str(field(p, "name") orelse return fail(d, &.{"invalid metadata.xmp: a property needs a name"}), "xmp property name", d),
                    .value = try str(field(p, "value") orelse return fail(d, &.{"invalid metadata.xmp: a property needs a value"}), "xmp property value", d),
                    .description = try str(field(p, "description") orelse return fail(d, &.{"invalid metadata.xmp: a property needs a description"}), "xmp property description", d),
                };
            }
            out[i] = .{
                .name = try str(field(s, "name") orelse return fail(d, &.{"invalid metadata.xmp: a schema needs a name"}), "xmp name", d),
                .prefix = try str(field(s, "prefix") orelse return fail(d, &.{"invalid metadata.xmp: a schema needs a prefix"}), "xmp prefix", d),
                .namespace = try str(field(s, "namespace") orelse return fail(d, &.{"invalid metadata.xmp: a schema needs a namespace"}), "xmp namespace", d),
                .properties = props,
            };
        }
        m.xmp = out;
    }
    return m;
}

fn parseAttachments(a: Allocator, x: json.Value, blobs: []const Blob, d: *Diag) Error![]const Attachment {
    if (x != .array) return fail(d, &.{"invalid attachments: expected an array"});
    const out = try a.alloc(Attachment, x.array.len);
    for (x.array, 0..) |e, i| {
        if (e != .object) return fail(d, &.{"invalid attachments: each attachment is an object"});
        const name = try str(field(e, "name") orelse return fail(d, &.{"invalid attachments: an attachment needs a name"}), "attachment name", d);
        var at: Attachment = .{ .name = name, .data = "" };
        if (field(e, "dataRef")) |r| {
            const id = try str(r, "attachment dataRef", d);
            var found = false;
            var k = blobs.len;
            while (k > 0) {
                k -= 1;
                if (std.mem.eql(u8, blobs[k].id, id)) {
                    at.data = blobs[k].data;
                    found = true;
                    break;
                }
            }
            if (!found) return fail(d, &.{ "attachment data is missing: ", name });
        } else if (field(e, "data")) |dv| {
            at.data = dv.asString() orelse return fail(d, &.{ "attachment data must be bytes or a string: ", name });
        } else return fail(d, &.{ "attachment data is missing: ", name });
        if (field(e, "mimeType")) |t| at.mime_type = try str(t, "attachment mimeType", d);
        if (field(e, "description")) |t| at.description = try str(t, "attachment description", d);
        if (field(e, "relationship")) |t| {
            const s = try str(t, "attachment relationship", d);
            const table = [_]struct { []const u8, Relationship }{
                .{ "source", .source }, .{ "data", .data }, .{ "alternative", .alternative },
                .{ "supplement", .supplement }, .{ "unspecified", .unspecified },
            };
            at.relationship = for (table) |r| {
                if (std.mem.eql(u8, s, r[0])) break r[1];
            } else return fail(d, &.{ "unknown attachment relationship: ", s });
        }
        if (field(e, "modificationDate")) |t| {
            const s = try str(t, "attachment modificationDate", d);
            at.modification_date = parseDate(s) orelse return fail(d, &.{"invalid modificationDate: expected YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS"});
        }
        out[i] = at;
    }
    return out;
}

// ---- cross-field validation (takumi-pdf's types and krilla's validators rejected these)

fn validMimePart(p: []const u8) bool {
    if (p.len == 0) return false;
    for (p) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '-' or c == '+' or c == '.')) return false;
    }
    return true;
}

/// `type/subtype` with krilla's character set.
pub fn validMimeType(m: []const u8) bool {
    const slash = std.mem.indexOfScalar(u8, m, '/') orelse return false;
    return validMimePart(m[0..slash]) and validMimePart(m[slash + 1 ..]) and std.mem.indexOfScalar(u8, m[slash + 1 ..], '/') == null;
}

fn isXmlName(n: []const u8) bool {
    if (n.len == 0) return false;
    for (n, 0..) |c, i| {
        const alpha = std.ascii.isAlphabetic(c) or c >= 0x80;
        if (i == 0) {
            if (!(alpha or c == '_')) return false;
        } else if (!(alpha or std.ascii.isDigit(c) or c == '-' or c == '_' or c == '.')) return false;
    }
    return true;
}

fn validateXmp(s: XmpSchema, d: *Diag) Error!void {
    if (!isXmlName(s.prefix)) return fail(d, &.{ "XMP schema cannot be written as XML: ", s.prefix });
    var bad = s.namespace.len == 0;
    for (s.namespace) |c| bad = bad or std.ascii.isWhitespace(c) or c == '"' or c == '\'' or c == '<' or c == '>' or c == '&';
    if (bad) return fail(d, &.{ "XMP schema cannot be written as XML: ", s.namespace });
    for (s.properties) |p| {
        if (!isXmlName(p.name)) return fail(d, &.{ "XMP schema cannot be written as XML: ", p.name });
    }
}

fn validate(o: *PdfOptions, tagged_set: bool, d: *Diag) Error!void {
    // Page size (explicit dimensions) and the area left inside the margins that no band can shrink.
    switch (o.geometry) {
        .page => |p| {
            const finite = std.math.isFinite(p.width) and std.math.isFinite(p.height);
            if (!finite or p.width <= 0 or p.height <= 0) return fail(d, &.{"Page size must be finite and larger than zero"});
            if (p.contentSize(p.resolveMargins(null, null)) == null) return fail(d, &.{"Page size must be finite and larger than zero"});
        },
        .viewport => {},
    }

    // Conformance (takumi: none of these combinations is rejected up front): a2a / a3a tag even
    // with tagged false (`writes_structure`); validators without a common PDF version fail with
    // InvalidStandard, attachments / dates / placeholders the standard forbids with krilla's
    // validation error or PlaceholderForbidden, both raised while the document is written
    // (conform.zig, tagdoc.zig, font_objects.zig `Uncovered`).
    _ = tagged_set;

    if (o.metadata) |m| {
        for (m.xmp) |s| try validateXmp(s, d);
    }

    // Attachments: names, media types, and what the PDF/A-3 levels require.
    for (o.attachments, 0..) |at, i| {
        for (o.attachments[0..i]) |prev| {
            if (std.mem.eql(u8, prev.name, at.name)) return fail(d, &.{ "Two attachments are named ", at.name });
        }
        if (at.mime_type) |m| if (!validMimeType(m)) return fail(d, &.{ "Attachment mime type is not a type/subtype pair: ", m });
    }
}

fn pdfaName(p: Pdfa) []const u8 {
    return p.label()["PDF/A-".len..];
}

// ---------------------------------------------------------------------------------------------
// tests (ported from takumi-pdf-js date.rs, takumi-pdf options.rs and tests/render.test.ts; the
// remaining cases pin the wire format and the messages above)

const testing = std.testing;

fn tparse(arena: Allocator, text: []const u8) Error!PdfOptions {
    var d: Diag = .{};
    return parse(arena, text, &.{}, &d);
}

fn expectErr(text: []const u8, msg: []const u8) !void {
    return expectErrBlobs(text, &.{}, msg);
}

fn expectErrBlobs(text: []const u8, blobs: []const Blob, msg: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var d: Diag = .{};
    try testing.expectError(error.Invalid, parse(arena.allocator(), text, blobs, &d));
    try testing.expectEqualStrings(msg, d.message());
}

test "parse_date accepts documented formats" {
    try testing.expect(parseDate("2026-08-06") != null);
    try testing.expect(parseDate("2026-08-06T01:02:03") != null);
    try testing.expect(parseDate("2026-08-06T01:02:03Z") != null);
    try testing.expect(parseDate("2028-02-29") != null);
    const d = parseDate("2026-08-06T01:02:03Z").?;
    try testing.expectEqual(@as(u16, 2026), d.year);
    try testing.expectEqual(@as(u8, 3), d.second);
}

test "parse_date rejects invalid input" {
    try testing.expect(parseDate("2026-08-06T01:02:03ZZ") == null);
    try testing.expect(parseDate("2026-02-30") == null);
    try testing.expect(parseDate("2026-13-01") == null);
    try testing.expect(parseDate("26-08-06") == null);
    try testing.expect(parseDate("2026-08-06T24:00:00") == null);
    try testing.expect(parseDate("2026-08-06T01:02") == null);
    try testing.expect(parseDate("2027-02-29") == null);
    try testing.expect(parseDate("2026-08-06-01") == null);
}

test "defaults: paged A4 with auto margins" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{ "", "{}", "null" }) |t| {
        const o = try tparse(arena.allocator(), t);
        try testing.expect(o.geometry == .page);
        try testing.expectEqual(Page.a4.width, o.geometry.page.width);
        try testing.expect(o.geometry.page.margin.top == .auto and o.geometry.page.margin.left == .auto);
        try testing.expectEqual(Tagging.on, o.tagged);
        try testing.expectEqual(Pdfa.none, o.pdfa);
        try testing.expectEqual(UncoveredText.@"error", o.uncovered_text);
        try testing.expect(!o.outline and o.page_ranges == null and o.header == null);
    }
}

test "page presets have the CSS Paged Media sizes" {
    const mm = one_mm_in_px;
    try testing.expectApproxEqAbs(@as(f32, 793.7008), Page.a4.width, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1122.5197), Page.a4.height, 0.001);
    try testing.expectEqual(@as(f32, 210.0) * mm, Page.a4.width);
    try testing.expectEqual(@as(f32, 297.0) * mm, Page.a4.height);
    try testing.expectEqual(@as(f32, 816.0), Page.letter.width);
    try testing.expectEqual(@as(f32, 1056.0), Page.letter.height);
    try testing.expectEqual(@as(f32, 816.0), Page.legal.width);
    try testing.expectEqual(@as(f32, 1344.0), Page.legal.height);
    try testing.expectEqual(@as(f32, 1056.0), Page.ledger.width);
    try testing.expectEqual(@as(f32, 1632.0), Page.ledger.height);
    try testing.expectEqual(@as(f32, 250.0) * mm, Page.b4.width);
    try testing.expectEqual(@as(f32, 257.0) * mm, Page.jis_b4.width);
    try testing.expectEqual(@as(f32, 182.0) * mm, Page.jis_b5.width);
    try testing.expectEqual(@as(f32, 148.0) * mm, Page.a5.width);
    try testing.expectEqual(@as(f32, 420.0) * mm, Page.a3.height);
    try testing.expectEqual(@as(f32, 250.0) * mm, Page.b5.height);
    // 10 mm default margin ("37.8")
    try testing.expectApproxEqAbs(@as(f32, 37.795), default_margin, 0.001);
}

test "size names are case-insensitive; unknown names fail" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const o = try tparse(arena.allocator(), "{\"size\":\"LeTtEr\"}");
    try testing.expectEqual(Page.letter.width, o.geometry.page.width);
    const o2 = try tparse(arena.allocator(), "{\"size\":\"JIS-B5\"}");
    try testing.expectEqual(Page.jis_b5.height, o2.geometry.page.height);
    try expectErr("{\"size\":\"Tabloid\"}", "unknown page size: tabloid");
}

test "explicit size, landscape swaps width and height (also for explicit sizes)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const o = try tparse(arena.allocator(), "{\"size\":{\"width\":400,\"height\":300},\"landscape\":true}");
    try testing.expectEqual(@as(f32, 300), o.geometry.page.width);
    try testing.expectEqual(@as(f32, 400), o.geometry.page.height);
    const p = try tparse(arena.allocator(), "{\"landscape\":true}");
    try testing.expectEqual(Page.a4.height, p.geometry.page.width);
    const f = try tparse(arena.allocator(), "{\"landscape\":false}");
    try testing.expectEqual(Page.a4.width, f.geometry.page.width);
    try expectErr("{\"size\":{\"width\":0,\"height\":300}}", "Page size must be finite and larger than zero");
    try expectErr("{\"size\":{\"width\":-5,\"height\":300}}", "Page size must be finite and larger than zero");
}

test "margins: uniform, per side, auto rule" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const u = try tparse(a, "{\"margin\":24}");
    try testing.expectEqual(@as(f32, 24), u.geometry.page.margin.left.px);
    try testing.expect(!u.geometry.page.margin.followBands());
    const s = try tparse(a, "{\"margin\":{\"top\":10,\"left\":\"auto\"}}");
    try testing.expectEqual(@as(f32, 10), s.geometry.page.margin.top.px);
    try testing.expect(s.geometry.page.margin.left == .auto);
    try testing.expect(s.geometry.page.margin.bottom == .auto); // a side left out is auto
    const au = try tparse(a, "{\"margin\":\"auto\"}");
    try testing.expect(au.geometry.page.margin.right == .auto);
    // auto: never below the default margin, grows with the band (+ 15pt inset), 0 on a short axis
    const m: Margin = .auto;
    try testing.expectEqual(default_margin, m.resolve(1000, null));
    try testing.expectEqual(default_margin, m.resolve(1000, 5));
    try testing.expectApproxEqAbs(@as(f32, 100) + band_edge_padding, m.resolve(1000, 100), 0.001);
    try testing.expectEqual(@as(f32, 0), m.resolve(96, 100));
    try testing.expectEqual(@as(f32, 0), m.resolve(50, null));
    try testing.expectEqual(default_margin, m.resolve(97, null));
    const r = Page.a4.resolveMargins(null, 60);
    try testing.expectEqual(default_margin, r.top);
    try testing.expectEqual(default_margin, r.left);
    try testing.expectApproxEqAbs(@as(f32, 60) + band_edge_padding, r.bottom, 0.001);
    try expectErr("{\"margin\":\"wide\"}", "invalid margin: expected a number or \"auto\"");
    try expectErr("{\"size\":{\"width\":100,\"height\":100},\"margin\":60}", "Page size must be finite and larger than zero");
}

test "viewport and the paged options are mutually exclusive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const v = try tparse(arena.allocator(), "{\"viewport\":{\"width\":600,\"height\":300.9}}");
    try testing.expectEqual(@as(u32, 600), v.geometry.viewport.width);
    try testing.expectEqual(@as(?u32, 300), v.geometry.viewport.height);
    const nh = try tparse(arena.allocator(), "{\"viewport\":{\"width\":600}}");
    try testing.expectEqual(@as(?u32, null), nh.geometry.viewport.height);
    const msg = "viewport is mutually exclusive with the paged options (size, landscape, margin, header, footer, pages, pageRanges)";
    for ([_][]const u8{
        "{\"viewport\":{\"width\":600,\"height\":300},\"pageRanges\":[1]}",
        "{\"viewport\":{\"width\":600},\"size\":\"a4\"}",
        "{\"viewport\":{\"width\":600},\"landscape\":false}",
        "{\"viewport\":{\"width\":600},\"margin\":1}",
        "{\"viewport\":{\"width\":600},\"header\":\"<p>x</p>\"}",
        "{\"viewport\":{\"width\":600},\"footer\":false}",
        "{\"viewport\":{\"width\":600},\"pages\":{}}",
    }) |t| try expectErr(t, msg);
    // null members count as unset (JS `undefined`)
    _ = try tparse(arena.allocator(), "{\"viewport\":{\"width\":600},\"size\":null}");
    try expectErr("{\"viewport\":{\"width\":0}}", "Page size must be finite and larger than zero");
    try expectErr("{\"viewport\":{\"width\":300,\"height\":0}}", "Page size must be finite and larger than zero");
}

test "bands: node, html, false; true is rejected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const o = try tparse(arena.allocator(),
        \\{"header":{"type":"text","text":"h"},"footer":"<p>f</p>",
        \\ "pages":{"first":{"header":false},"last":{"footer":{"type":"container"}},"odd":{},"even":{"header":"<b>e</b>"}}}
    );
    try testing.expect(o.header.? == .node);
    try testing.expectEqualStrings("<p>f</p>", o.footer.?.html);
    try testing.expect(o.pages.first.header.? == .off);
    try testing.expect(o.pages.first.footer == null);
    try testing.expect(o.pages.last.footer.? == .node);
    try testing.expectEqualStrings("<b>e</b>", o.pages.even.header.?.html);
    try expectErr("{\"header\":true}", "a band is a node, HTML, or false; true names nothing");
    try expectErr("{\"pages\":{\"middle\":{}}}", "unknown page rule: middle");
    try expectErr("{\"pages\":{\"first\":{\"body\":1}}}", "unknown field of pages.first: body");
    try expectErr("{\"pages\":{\"first\":3}}", "pages.first takes an object");
    try expectErr("{\"pages\":[]}", "pages takes an object");
}

test "page rules: first and last win over odd and even" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const o = try tparse(arena.allocator(),
        \\{"header":"D","pages":{"first":{"header":"F"},"last":{"header":false},"even":{"header":"E"}}}
    );
    const r = o.pages;
    const d = o.header;
    try testing.expectEqualStrings("F", r.bandFor(true, d, 1, 4).?.html);
    try testing.expectEqualStrings("D", r.bandFor(true, d, 3, 4).?.html); // odd rule left out -> document band
    try testing.expectEqualStrings("E", r.bandFor(true, d, 2, 4).?.html);
    try testing.expect(r.bandFor(true, d, 4, 4) == null); // last: header off wins over even
    try testing.expectEqualStrings("F", r.bandFor(true, d, 1, 1).?.html); // first wins over last
    try testing.expect(r.bandFor(false, null, 2, 4) == null); // no footer anywhere
}

test "pageRanges: validation and selection (render.test.ts: keeps only the listed pages)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = try tparse(a, "{\"pageRanges\":[1,{\"from\":3},{\"to\":2},{\"from\":4,\"to\":8}]}");
    try testing.expectEqual(@as(usize, 4), o.page_ranges.?.len);
    try testing.expectEqual(@as(?usize, 1), o.page_ranges.?[0].to);
    try testing.expectEqual(@as(?usize, null), o.page_ranges.?[1].to);
    // [1, {from: 3}] over 5 pages keeps 1, 3, 4, 5
    const ro = try tparse(a, "{\"pageRanges\":[1,{\"from\":3}]}");
    var sel = PageSelection.init(ro.page_ranges);
    var kept: [5]?usize = undefined;
    for (&kept) |*k| k.* = try sel.pushPage(a);
    var d: Diag = .{};
    try sel.finish(&d);
    try testing.expectEqualSlices(?usize, &.{ 0, null, 1, 2, 3 }, &kept);
    try testing.expect(sel.keeps(0) and !sel.keeps(1) and sel.keeps(4) and !sel.keeps(9));
    try testing.expectEqual(@as(?usize, 3), sel.emittedIndex(4));
    // out of bounds -> "select none"
    const none = try tparse(a, "{\"pageRanges\":[{\"from\":99}]}");
    var s2 = PageSelection.init(none.page_ranges);
    for (0..3) |_| _ = try s2.pushPage(a);
    try testing.expectError(error.Invalid, s2.finish(&d));
    try testing.expectEqualStrings("The page ranges select none of the document's 3 pages", d.message());
    // no ranges keeps everything
    var s3 = PageSelection.init(null);
    try testing.expectEqual(@as(?usize, 0), try s3.pushPage(a));
    try s3.finish(&d);
    // invalid ranges
    try expectErr("{\"pageRanges\":[0]}", "Page range is invalid: 0. Pages are numbered from 1.");
    try expectErr("{\"pageRanges\":[{\"from\":5,\"to\":2}]}", "Page range is invalid: 5-2. Pages are numbered from 1.");
    try expectErr("{\"pageRanges\":[{\"from\":0}]}", "Page range is invalid: 0-. Pages are numbered from 1.");
    try expectErr("{\"pageRanges\":[{\"to\":0}]}", "Page range is invalid: -0. Pages are numbered from 1.");
    try expectErr("{\"pageRanges\":[-1]}", "Page range is invalid: expected whole page numbers. Pages are numbered from 1.");
    try expectErr("{\"pageRanges\":[1.5]}", "Page range is invalid: expected whole page numbers. Pages are numbered from 1.");
}

test "metadata and dates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const o = try tparse(arena.allocator(),
        \\{"metadata":{"title":"T","description":"D","authors":["a","b"],"keywords":["k"],"creator":"c",
        \\ "creationDate":"2026-08-06T01:02:03",
        \\ "xmp":[{"name":"Factur-X","prefix":"fx","namespace":"urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#",
        \\   "properties":[{"name":"DocumentFileName","value":"factur-x.xml","description":"file"}]}]},
        \\ "lang":"en-US","outline":true}
    );
    const m = o.metadata.?;
    try testing.expectEqualStrings("T", m.title.?);
    try testing.expectEqual(@as(usize, 2), m.authors.len);
    try testing.expectEqual(@as(u16, 2026), m.creation_date.?.year);
    try testing.expectEqualStrings("fx", m.xmp[0].prefix);
    try testing.expectEqualStrings("factur-x.xml", m.xmp[0].properties[0].value);
    try testing.expect(o.outline);
    try testing.expectEqualStrings("en-US", o.lang);
    try expectErr("{\"metadata\":{\"creationDate\":\"2026-02-30\"}}", "invalid creationDate: expected YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS");
    try expectErr("{\"metadata\":{\"xmp\":[{\"name\":\"n\",\"prefix\":\"1x\",\"namespace\":\"urn:x\",\"properties\":[]}]}}", "XMP schema cannot be written as XML: 1x");
    try expectErr("{\"metadata\":{\"xmp\":[{\"name\":\"n\",\"prefix\":\"x\",\"namespace\":\"a b\",\"properties\":[]}]}}", "XMP schema cannot be written as XML: a b");
    try expectErr("{\"metadata\":{\"xmp\":[{\"name\":\"n\",\"prefix\":\"x\",\"namespace\":\"urn:x\",\"properties\":[{\"name\":\"a b\",\"value\":\"\",\"description\":\"\"}]}]}}", "XMP schema cannot be written as XML: a b");
}

test "attachments: text, blob refs, mime and duplicates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const blobs = [_]Blob{.{ .id = "bm-att:0", .data = "\x00\x01bytes" }};
    var d: Diag = .{};
    const o = try parse(arena.allocator(),
        \\{"attachments":[{"name":"a.xml","data":"<x/>","mimeType":"application/xml","relationship":"data"},
        \\ {"name":"b.bin","dataRef":"bm-att:0","description":"d","modificationDate":"2026-01-02"}]}
    , &blobs, &d);
    try testing.expectEqualStrings("<x/>", o.attachments[0].data);
    try testing.expectEqual(Relationship.data, o.attachments[0].relationship);
    try testing.expectEqual(Relationship.unspecified, o.attachments[1].relationship);
    try testing.expectEqualStrings("\x00\x01bytes", o.attachments[1].data);
    try testing.expectEqual(@as(u8, 2), o.attachments[1].modification_date.?.day);
    try expectErr("{\"attachments\":[{\"name\":\"a\",\"data\":\"x\"},{\"name\":\"a\",\"data\":\"y\"}]}", "Two attachments are named a");
    try expectErr("{\"attachments\":[{\"name\":\"a\",\"data\":\"x\",\"mimeType\":\"plain\"}]}", "Attachment mime type is not a type/subtype pair: plain");
    try expectErr("{\"attachments\":[{\"name\":\"a\",\"data\":\"x\",\"mimeType\":\"a/b/c\"}]}", "Attachment mime type is not a type/subtype pair: a/b/c");
    try expectErr("{\"attachments\":[{\"name\":\"a\",\"dataRef\":\"bm-att:9\"}]}", "attachment data is missing: a");
    try expectErr("{\"attachments\":[{\"name\":\"a\"}]}", "attachment data is missing: a");
    try expectErr("{\"attachments\":[{\"name\":\"a\",\"data\":\"x\",\"relationship\":\"parent\"}]}", "unknown attachment relationship: parent");
    try expectErr("{\"attachments\":[{\"name\":\"a\",\"data\":\"x\",\"modificationDate\":\"nope\"}]}", "invalid modificationDate: expected YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS");
    try testing.expect(validMimeType("application/vnd.ms-excel") and validMimeType("text/plain+charset"));
    try testing.expect(!validMimeType("text/") and !validMimeType("/plain") and !validMimeType("te xt/plain"));
}

test "pdfa / tagged / attachments / uncoveredText combinations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const date = "\"metadata\":{\"creationDate\":\"2026-01-01\"}";
    // accepted
    _ = try tparse(a, "{\"pdfa\":\"2b\",\"tagged\":false," ++ date ++ "}");
    _ = try tparse(a, "{\"pdfa\":\"2a\",\"tagged\":true," ++ date ++ "}");
    _ = try tparse(a, "{\"pdfa\":\"2a\"," ++ date ++ "}");
    _ = try tparse(a, "{\"pdfa\":\"2u\",\"tagged\":\"ua1\"," ++ date ++ "}");
    _ = try tparse(a, "{\"pdfa\":\"4\",\"tagged\":\"ua2\"," ++ date ++ "}");
    _ = try tparse(a, "{\"tagged\":\"ua1\"}");
    _ = try tparse(a, "{\"tagged\":\"ua2\",\"uncoveredText\":\"blank\"}");
    const o = try tparse(a, "{\"pdfa\":\"4f\",\"attachments\":[{\"name\":\"a.xml\",\"data\":\"x\",\"mimeType\":\"text/xml\",\"description\":\"d\"}]," ++ date ++ "}");
    try testing.expectEqual(Pdfa.a4f, o.pdfa);
    _ = try tparse(a, "{\"pdfa\":\"3b\",\"attachments\":[{\"name\":\"a.xml\",\"data\":\"x\",\"mimeType\":\"text/xml\",\"description\":\"d\",\"modificationDate\":\"2026-01-01\"}],\"metadata\":{\"creationDate\":\"2026-01-01\"}}");
    _ = try tparse(a, "{\"attachments\":[{\"name\":\"a\",\"data\":\"x\"}]}"); // plain PDF: free-form attachments
    // takumi rejects none of these while parsing (they fail while writing: conform.zig)
    _ = try tparse(a, "{\"pdfa\":\"2a\",\"tagged\":false," ++ date ++ "}");
    _ = try tparse(a, "{\"pdfa\":\"4\",\"tagged\":\"ua1\"," ++ date ++ "}");
    _ = try tparse(a, "{\"pdfa\":\"2b\",\"attachments\":[{\"name\":\"a\",\"data\":\"x\"}]," ++ date ++ "}");
    _ = try tparse(a, "{\"pdfa\":\"2b\",\"lang\":\"en\"}");
    _ = try tparse(a, "{\"tagged\":\"ua1\",\"uncoveredText\":\"placeholder\"}");
    const ok = try tparse(a, "{\"uncoveredText\":\"placeholder\"}");
    try testing.expectEqual(UncoveredText.placeholder, ok.uncovered_text);
    try expectErr("{\"pdfa\":\"1b\"}", "unknown pdfa level: 1b (expected 2a, 2b, 2u, 3a, 3b, 3u, 4 or 4f)");
    try expectErr("{\"tagged\":\"ua3\"}", "invalid tagged: expected true, false, \"ua1\" or \"ua2\"");
    try expectErr("{\"uncoveredText\":\"skip\"}", "unknown uncoveredText: skip");
}

test "css variables gain the -- prefix; misc fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const o = try tparse(arena.allocator(),
        \\{"cssVariables":{"accent":"red","--gap":"4px"},"fontFamilies":["A","B"],"failedFontFiles":["f.woff2"],
        \\ "backgroundColor":"#fff","css":[".a{color:red}"],"lang":"fr"}
    );
    try testing.expectEqualStrings("--accent", o.css_variables[0][0]);
    try testing.expectEqualStrings("--gap", o.css_variables[1][0]);
    try testing.expectEqualStrings("red", o.css_variables[0][1]);
    try testing.expectEqual(@as(usize, 2), o.font_families.len);
    try testing.expectEqualStrings("f.woff2", o.failed_font_files[0]);
    try testing.expectEqualStrings("#fff", o.background_color.?);
    try testing.expect(o.css.? == .array);
    try expectErr("{", "invalid options JSON");
    try expectErr("{\"outline\":1}", "invalid outline: expected a boolean");
}
