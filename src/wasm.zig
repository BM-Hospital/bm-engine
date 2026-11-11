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
    _ = r.registerFont(ptr[0..len], name[0..name_len], @intCast(@min(weight, 1000)), italic) catch |e| return fail(r, e);
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
