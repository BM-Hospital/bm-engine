//! bm-render 2D rasterization / compositing.
//!
//! * Surfaces are PREMULTIPLIED RGBA8 (`Pixmap`); colours passed in (`Color`) are straight sRGB.
//! * Source-over everywhere (sRGB-encoded u8, exact div-255 rounding); the CSS blend modes are
//!   only available when compositing a whole layer (`drawPixmapBlend`).
//! * Shapes: `Rasterizer` (exact-area AA or the tiny-skia compatible `.skia_ss` mode) -> A8 `Mask`
//!   -> `fillMask`, or `fillPath` which blends spans directly. Strokes: `strokePath` -> fill.
//! * Paints: solid, linear / radial / conic gradients (takumi LUT sampling rule), images.
//! * Allocation: every function that allocates takes an allocator. Results (`Mask`, `Pixmap`)
//!   are owned by the caller (typically the per-render arena); `Rasterizer` keeps reusable
//!   scratch buffers and wants a long-lived allocator.
//! * No function here traps on NaN / inf / huge / empty input; invalid input draws nothing.
const std = @import("std");
const types = @import("types.zig");
const path_mod = @import("path.zig");
const rasterizer = @import("rasterizer.zig");
const paint_mod = @import("paint.zig");
const image = @import("image.zig");
const blur = @import("blur.zig");
const mask_mod = @import("mask.zig");
const stroke = @import("stroke.zig");
const blend = @import("blend.zig");

pub const Point = types.Point;
pub const Rect = types.Rect;
pub const IRect = types.IRect;
pub const Affine = types.Affine;
pub const Color = types.Color;
pub const Pixmap = types.Pixmap;
pub const Mask = types.Mask;
pub const ClipMask = types.ClipMask;
pub const FillRule = types.FillRule;
pub const Filter = types.Filter;
pub const Extend = types.Extend;
pub const GradientStop = types.GradientStop;
pub const Paint = types.Paint;

pub const Path = path_mod.Path;
pub const PathSink = path_mod.PathSink;
pub const Verb = path_mod.Verb;

pub const Rasterizer = rasterizer.Rasterizer;
pub const RasterMode = rasterizer.Mode;
pub const rasterize = rasterizer.rasterize;
pub const rasterizeSkia = rasterizer.rasterizeSkia;
pub const fillPath = rasterizer.fillPath;

/// Stroker: `strokePath(alloc, src, opts, out)` appends a fillable (NONZERO) outline; `dashPath`
/// only dashes. See stroke.zig.
pub const LineJoin = stroke.LineJoin;
pub const LineCap = stroke.LineCap;
pub const StrokeOptions = stroke.StrokeOptions;
pub const strokePath = stroke.strokePath;
pub const dashPath = stroke.dashPath;

pub const fillMask = paint_mod.fillMask;
pub const fillRect = paint_mod.fillRect;

pub const drawPixmap = image.drawPixmap;
pub const resample = image.resample;
pub const resampleNearest = image.resampleNearest;
pub const drawPixmapNearestRect = image.drawPixmapNearestRect;

/// Layer compositing with a CSS `mix-blend-mode` (integer translation), and mask helpers for
/// `mask-image` / `clip-path` (multiply a layer by coverage in place). See blend.zig.
/// Fill through a mask with a pixmap as paint: `fillMask` with a `.nearest` image paint and
/// `Affine.translate(-x, -y)` is an exact texel copy.
pub const BlendMode = blend.BlendMode;
pub const drawPixmapBlend = blend.drawPixmapBlend;
pub const MaskSource = blend.MaskSource;
pub const maskMultiply = blend.maskMultiply;
pub const maskMultiplyPixmap = blend.maskMultiplyPixmap;
pub const maskFromPixmap = blend.maskFromPixmap;

pub const blurMask = blur.blurMask;
pub const blurMaskClipped = blur.blurMaskClipped;
pub const blurPixmap = blur.blurPixmap;
pub const blurReach = blur.blurReach;

pub const maskFromRect = mask_mod.maskFromRect;
pub const maskIntersect = mask_mod.maskIntersect;
pub const maskInvertWithin = mask_mod.maskInvertWithin;
pub const clipIntersect = mask_mod.clipIntersect;

/// `{ sin, cos }` without libm (use it instead of @sin/@cos to keep trig tables out of the wasm).
pub const sinCos = types.sinCos;

/// Exact `round(x / 255)` for x in 0..65025 (the compositing primitive).
pub const div255 = types.div255;

test {
    _ = @import("tests.zig");
    _ = @import("tests_scan.zig");
    _ = @import("skia_aa.zig");
    _ = @import("stroke.zig");
    _ = @import("blend.zig");
}
