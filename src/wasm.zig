//! wasm32-freestanding entry point: plain C-ABI exports, no imports.
const std = @import("std");
const render = @import("render.zig");
/// Feature switches, visible to modules as `@import("root").bm_config` (see src/font/ttf.zig).
pub const bm_config = @import("config.zig");

const gpa = @import("pages.zig").allocator;
const Renderer = render.Renderer;

var last_error: []const u8 = "";

fn fail(r: ?*Renderer, e: render.Error) u32 {
    switch (e) {
        error.OutOfMemory => last_error = "out of memory",
        error.Invalid => last_error = if (r) |x| x.err else "invalid input",
    }
    return 1;
}

export fn bm_alloc(n: usize) ?[*]u8 {
    const s = gpa.alloc(u8, if (n == 0) 1 else n) catch return null;
    return s.ptr;
}

export fn bm_free(p: ?[*]u8, n: usize) void {
    if (p) |ptr| gpa.free(ptr[0..if (n == 0) 1 else n]);
}

export fn bm_last_error_ptr() [*]const u8 {
    return last_error.ptr;
}

export fn bm_last_error_len() usize {
    return last_error.len;
}

export fn bm_renderer_new() ?*Renderer {
    return Renderer.create(gpa);
}

export fn bm_renderer_free(r: *Renderer) void {
    r.destroy();
}

/// Takes ownership of the font bytes (`ptr` must come from bm_alloc(len)). Result (bm_result_*):
/// takumi `RegisteredFamily[]` JSON.
export fn bm_register_font(r: *Renderer, ptr: [*]u8, len: usize, name: [*]const u8, name_len: usize, weight: u32, italic: i32) u32 {
    _ = r.registerFont(ptr[0..len], name[0..name_len], @intCast(@min(weight, 1000)), italic, null) catch |e| return fail(r, e);
    return 0;
}

/// Same as bm_register_font, with JSON options `{ "unicodeRange": [[start, end], ...] }`.
export fn bm_register_font_options(r: *Renderer, ptr: [*]u8, len: usize, name: [*]const u8, name_len: usize, weight: u32, italic: i32, opts_ptr: [*]const u8, opts_len: usize) u32 {
    const Options = struct { unicodeRange: ?[]const [2]u32 = null };
    var parsed: ?std.json.Parsed(Options) = null;
    defer if (parsed) |p| p.deinit();
    var ranges: ?[]@import("font/collection.zig").UnicodeRange = null;
    defer if (ranges) |slice| gpa.free(slice);
    if (opts_len > 0) {
        parsed = std.json.parseFromSlice(Options, gpa, opts_ptr[0..opts_len], .{}) catch {
            bm_free(ptr, len);
            last_error = "invalid font options";
            return 1;
        };
        if (parsed.?.value.unicodeRange) |source| {
            ranges = gpa.alloc(@import("font/collection.zig").UnicodeRange, source.len) catch {
                bm_free(ptr, len);
                last_error = "out of memory";
                return 1;
            };
            for (source, 0..) |range, i| {
                if (range[0] > range[1] or range[1] > 0x10ffff) {
                    bm_free(ptr, len);
                    last_error = "invalid unicodeRange";
                    return 1;
                }
                ranges.?[i] = .{ .start = @intCast(range[0]), .end = @intCast(range[1]) };
            }
        }
    }
    _ = r.registerFont(ptr[0..len], name[0..name_len], @intCast(@min(weight, 1000)), italic, ranges) catch |e| return fail(r, e);
    return 0;
}

/// Removes every face of a family; returns 1 when any was removed, else 0.
export fn bm_unregister_font(r: *Renderer, name: [*]const u8, name_len: usize) u32 {
    return @intFromBool(r.unregisterFont(name[0..name_len]));
}

export fn bm_clear_fonts(r: *Renderer) void {
    r.clearFonts();
}

export fn bm_put_image(r: *Renderer, src: [*]const u8, src_len: usize, data: [*]const u8, data_len: usize) u32 {
    r.putImage(src[0..src_len], data[0..data_len], 0, 0, false) catch |e| return fail(r, e);
    return 0;
}

export fn bm_put_rgba(r: *Renderer, src: [*]const u8, src_len: usize, data: [*]const u8, data_len: usize, w: u32, h: u32, premul: u32) u32 {
    if (w == 0 or h == 0) {
        last_error = "raw image must have non-zero size";
        return 1;
    }
    r.putImage(src[0..src_len], data[0..data_len], w, h, premul != 0) catch |e| return fail(r, e);
    return 0;
}

export fn bm_clear_images(r: *Renderer) void {
    r.clearImages();
}

export fn bm_render(r: *Renderer, node: [*]const u8, node_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    _ = r.render(node[0..node_len], opts[0..opts_len]) catch |e| return fail(r, e);
    return 0;
}

export fn bm_measure(r: *Renderer, node: [*]const u8, node_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    _ = r.measure(node[0..node_len], opts[0..opts_len]) catch |e| return fail(r, e);
    return 0;
}

/// Like bm_render, with an explicit source kind: 0 = JSON node tree, 1 = HTML markup.
export fn bm_render_src(r: *Renderer, kind: u32, src: [*]const u8, src_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    const k: render.SourceKind = if (kind == 1) .html else .json;
    _ = r.renderSource(k, src[0..src_len], opts[0..opts_len]) catch |e| return fail(r, e);
    return 0;
}

/// Like bm_measure, with an explicit source kind (see bm_render_src).
export fn bm_measure_src(r: *Renderer, kind: u32, src: [*]const u8, src_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    const k: render.SourceKind = if (kind == 1) .html else .json;
    _ = r.measureSource(k, src[0..src_len], opts[0..opts_len]) catch |e| return fail(r, e);
    return 0;
}

export fn bm_result_ptr(r: *Renderer) [*]const u8 {
    return r.result.ptr;
}

export fn bm_result_len(r: *Renderer) usize {
    return r.result.len;
}

export fn bm_release_result(r: *Renderer) void {
    r.releaseResult();
}

/// takumi `renderAnimation`: `json` = `{scenes:[{node, durationMs}], width, height, fps, format?, ...}`
/// (scene `node`: a node object, an HTML string or `{json}`; binary image sources registered with
/// bm_put_image / bm_put_rgba beforehand). Result (bm_result_*): the encoded WebP / APNG / GIF.
export fn bm_render_animation(r: *Renderer, json: [*]const u8, len: usize) u32 {
    _ = r.renderAnimation(json[0..len]) catch |e| return fail(r, e);
    return 0;
}

/// takumi `renderSvg`: like bm_render_src (kind 0 = JSON node tree, 1 = HTML), but the result
/// (bm_result_*) is an SVG document (UTF-8). Fails ("renderSvg is not supported by this build")
/// when compiled without `-Drender_svg`.
export fn bm_render_svg(r: *Renderer, kind: u32, src: [*]const u8, src_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    const k: render.SourceKind = if (kind == 1) .html else .json;
    _ = r.renderSvg(k, src[0..src_len], opts[0..opts_len]) catch |e| return fail(r, e);
    return 0;
}

/// takumi-pdf `render`: like bm_render_svg (kind 0 = JSON node tree, 1 = HTML; `opts` = the PdfRenderOptions
/// JSON; attachment bytes registered beforehand with bm_put_image under their `dataRef` ids), the result
/// (bm_result_*) is a PDF file. Fails ("renderPdf is not supported by this build") without `-Dpdf`.
export fn bm_render_pdf(r: *Renderer, kind: u32, src: [*]const u8, src_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    const k: render.SourceKind = if (kind == 1) .html else .json;
    _ = r.renderPdf(k, src[0..src_len], opts[0..opts_len]) catch |e| return fail(r, e);
    return 0;
}

/// takumi-pdf `measure`: result (bm_result_*) is `{"width":..,"height":..}` JSON (CSS px). Same build gate.
export fn bm_measure_pdf(r: *Renderer, kind: u32, src: [*]const u8, src_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    const k: render.SourceKind = if (kind == 1) .html else .json;
    _ = r.measurePdf(k, src[0..src_len], opts[0..opts_len]) catch |e| return fail(r, e);
    return 0;
}
export fn bm_needs_pdf(r: *Renderer, kind: u32, src: [*]const u8, src_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    _ = r.needsPdf(if (kind == 1) .html else .json, src[0..src_len], opts[0..opts_len]) catch |e| return fail(r, e);
    return 0;
}

/// Optional features compiled into this binary (bit mask, see src/config.zig `feature_bits`):
/// bit 0 css, 1 tw, 2 html, 3 svg, 4 woff, 5 variable_fonts, 6 cff, 7 effects, 8 modern_color,
/// 9 tables, 10 floats, 11 webp_gif_decode, 12 text_wrap_balance, 13 color_fonts, 14 complex_text,
/// 15 animation, 16 extra_codecs, 17 render_svg, 18 pdf.
export fn bm_features() u32 {
    return bm_config.feature_bits;
}
