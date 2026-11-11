//! Test wasm root for `svg_out.zig` (SVG output) until the integrator wires `Renderer.renderSvg`.
//! Re-exports the normal C ABI of wasm.zig plus `bm_render_svg`.
//!
//! NOTE: it calls `Renderer.beginCall`, `Renderer.parseOptions` and `Frame.prepare`, which are
//! private in render.zig; it is built from a scratch copy of src/ where they are made `pub`
//! (see the svg_out probe's build script). It is not part of `zig build`.
const std = @import("std");
const render = @import("render.zig");
const layout = @import("layout/layout.zig");
const svg_out = @import("svg_out.zig");

pub const bm_config = @import("config.zig");

comptime {
    _ = @import("wasm.zig");
}

const Renderer = render.Renderer;

/// Like bm_render_src, but the result (bm_result_*) is an SVG document (UTF-8). On failure the
/// message is in bm_svg_err_* (the renderer's error string, or "out of memory").
export fn bm_render_svg(r: *Renderer, kind: u32, src: [*]const u8, src_len: usize, opts: [*]const u8, opts_len: usize) u32 {
    renderSvg(r, if (kind == 1) .html else .json, src[0..src_len], opts[0..opts_len]) catch |e| {
        if (e == error.OutOfMemory) r.err = "out of memory";
        return 1;
    };
    return 0;
}

export fn bm_svg_err_ptr(r: *Renderer) [*]const u8 {
    return r.err.ptr;
}

export fn bm_svg_err_len(r: *Renderer) usize {
    return r.err.len;
}

fn renderSvg(r: *Renderer, kind: render.SourceKind, source: []const u8, opts_json: []const u8) render.Error!void {
    r.beginCall();
    const a = r.arena.allocator();
    const opts = try r.parseOptions(opts_json);
    r.time_ms = opts.time_ms;
    var f: render.Frame = .{ .r = r, .a = a, .opts = opts, .tree = layout.Tree.init(a), .ctx = undefined };
    try f.prepare(kind, source);
    var out: std.ArrayList(u8) = .empty;
    try svg_out.write(&f, &out);
    r.result = out.items;
}
