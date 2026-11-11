//! bm-engine SVG rasteriser (standalone; depends only on raster, codec and json.parseNumber).
//!
//! Usage:
//! ```
//! const doc = try svg.parse(arena, text);              // untrusted input, bounded
//! const sz = svg.intrinsicSize(&doc);                  // CSS px
//! try svg.render(arena, &rasterizer, &doc, &pixmap, dest_rect, null, .{ .current_color = color });
//! ```
//! Allocation: `parse` allocates the whole tree from `arena` (never freed piecemeal); `render`
//! allocates layers, masks, paths and decoded images from `scratch` (a per-render bump arena is
//! expected; nothing is returned). `rast` should be the caller's long-lived Rasterizer
//! (its `levels16` flag is honoured for every fill).
//!
//! Supported: XML (entities incl. internal-subset ENTITY, CDATA, prefixes), `<style>` with
//! type/class/id/attribute compound selectors + descendant/child combinators, `style=""`,
//! presentation attributes; path (full grammar, arcs), rect (rx/ry), circle, ellipse, line,
//! polyline, polygon; g, svg (nested, viewBox + preserveAspectRatio), use (+ symbol), defs, a,
//! switch; fill / stroke (colours, currentColor, gradients, patterns), opacity groups,
//! fill-rule, stroking (joins, caps, dashes, miter limit, paint-order, non-scaling-stroke),
//! transforms, linear / radial gradients (units, transform, spread, href chains; focal point
//! ignored), patterns, clipPath, mask (luminance / alpha), image (data: PNG/JPEG/WebP/GIF and
//! nested SVG), markers, filters (feGaussianBlur, feOffset, feFlood, feColorMatrix,
//! feComposite, feMerge, feBlend, feDropShadow, feComponentTransfer).
//! Not supported: text (delegated to `RenderOptions.text`), other filter primitives (the filter
//! is then skipped), CSS pseudo-classes, mix-blend-mode, external references.
const std = @import("std");
const raster = @import("../raster/raster.zig");
const dom = @import("dom.zig");
const render_mod = @import("render.zig");
const xml = @import("xml.zig");

pub const stroke = @import("stroke.zig");
pub const strokeToPath = stroke.strokeToPath;
pub const Stroker = stroke.Stroker;
pub const StrokeOptions = stroke.Options;

pub const Document = dom.Document;
pub const Unsupported = dom.Unsupported;
pub const RenderOptions = render_mod.RenderOptions;
pub const TextRequest = render_mod.TextRequest;
pub const TextHook = render_mod.TextHook;
pub const Error = render_mod.Error;
pub const Features = render_mod.Features;

/// Parses SVG markup. `error.InvalidSvg` when the first element is not `<svg>`.
/// Bounded: at most 100k elements, nesting depth 64 (deeper content is dropped).
pub fn parse(arena: std.mem.Allocator, text: []const u8) Error!Document {
    return render_mod.parseDoc(true, arena, text);
}

/// `parse` with `<style>` sheet support compiled in or out (must match `renderWith`'s features).
pub fn parseWith(comptime features: Features, arena: std.mem.Allocator, text: []const u8) Error!Document {
    return render_mod.parseDoc(features.stylesheets, arena, text);
}

pub const IntrinsicSize = struct { width: ?f32, height: ?f32, view_box: ?[4]f32 };

/// Root `width` / `height` in CSS px (null for percentages / missing; one missing dimension
/// is derived from the viewBox aspect ratio) and the root viewBox.
pub fn intrinsicSize(doc: *const Document) IntrinsicSize {
    const i = render_mod.intrinsic(doc.root());
    return .{ .width = i.width, .height = i.height, .view_box = i.view_box };
}

/// Renders the document into `dst` (premultiplied RGBA8, source-over) so that the SVG
/// viewport maps onto `dest` (device px, may be fractional or exceed `dst`). With a viewBox
/// the mapping honours preserveAspectRatio; without one the user space is scaled from the
/// intrinsic size (100x100 when unknown) onto `dest`. Content is clipped to `dest` and `clip`.
pub fn render(
    scratch: std.mem.Allocator,
    rast: *raster.Rasterizer,
    doc: *const Document,
    dst: *raster.Pixmap,
    dest: raster.Rect,
    clip: ?*const raster.ClipMask,
    opts: RenderOptions,
) Error!void {
    return renderWith(.{}, scratch, rast, doc, dst, dest, clip, opts);
}

/// `render` with a comptime feature set; disabled features are compiled out (their elements /
/// properties are ignored), e.g. `.{ .filters = false, .markers = false }` for a smaller wasm.
pub fn renderWith(
    comptime features: Features,
    scratch: std.mem.Allocator,
    rast: *raster.Rasterizer,
    doc: *const Document,
    dst: *raster.Pixmap,
    dest: raster.Rect,
    clip: ?*const raster.ClipMask,
    opts: RenderOptions,
) Error!void {
    var r: render_mod.Renderer(features) = .{ .a = scratch, .rast = rast, .doc = doc, .opts = opts };
    try r.renderRoot(dst, dest, clip);
}

/// Sniffing: optional BOM / whitespace / XML declaration / comments / doctype, then `<svg`.
pub fn looksLikeSvg(bytes: []const u8) bool {
    return xml.looksLikeSvg(bytes);
}

test {
    _ = @import("xml.zig");
    _ = @import("css.zig");
    _ = @import("num.zig");
    _ = @import("color.zig");
    _ = @import("pathdata.zig");
    _ = @import("stroke.zig");
    _ = @import("style.zig");
    _ = @import("filter.zig");
    _ = @import("tests.zig");
}
