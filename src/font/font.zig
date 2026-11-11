//! Font parsing, shaping and paragraph layout (takumi/Blink-compatible metrics).
//!
//! Typical use:
//!   var fonts: FontCollection = .{};                    // long-lived
//!   _ = try fonts.register(gpa, ttf_bytes, .{});
//!   var p = try Paragraph.init(arena, &fonts, &.{.{ .text = "Hi", .style = .{ .size = 16 } }}, .{});
//!   const size = p.measure(200);                        // cheap, allocation-free, repeatable
//!   const lay = try p.layout(arena, 200);               // lines + positioned glyphs
//!   for (lay.glyphs) |g| _ = emitGlyph(fonts.font(g.face), g.gid, g.size, g.x, g.y, &path_sink);
const std = @import("std");
pub const ttf = @import("ttf.zig");
pub const ot = @import("ot.zig");
pub const unicode = @import("unicode.zig");
pub const collection = @import("collection.zig");
pub const text = @import("text.zig");
pub const shape_mod = @import("shape.zig");
pub const bidi = @import("bidi.zig");
pub const normalize = @import("normalize.zig");
/// CFF / CFF2 charstring outlines (reached through `Font.outline`).
pub const cff = @import("cff.zig");
/// fvar / avar / gvar / HVAR / MVAR (reached through `Font.withVariations` and friends).
pub const variations = @import("variations.zig");

pub const Font = ttf.Font;
pub const FontError = ttf.Error;
pub const Bounds = ttf.Bounds;
pub const LineMetrics = ttf.LineMetrics;
pub const emitGlyph = ttf.emitGlyph;
pub const faceCount = ttf.faceCount;
pub const PathOut = ttf.PathOut;
pub const AxisValue = ttf.AxisValue;
pub const Axis = ttf.Axis;
pub const NamedInstance = ttf.NamedInstance;
pub const max_axes = ttf.max_axes;
pub const decodeUtf8 = unicode.decodeUtf8;

pub const FaceId = collection.FaceId;
pub const Face = collection.Face;
pub const FontCollection = collection.FontCollection;
pub const RegisterOptions = collection.RegisterOptions;
pub const MatchRequest = collection.MatchRequest;
pub const FamilyInfo = collection.FamilyInfo;
pub const FaceInfo = collection.FaceInfo;
pub const instance_base = collection.instance_base;

pub const TextStyle = text.TextStyle;
pub const Run = text.Run;
pub const LineHeight = text.LineHeight;
pub const TextAlign = text.TextAlign;
pub const WhiteSpace = text.WhiteSpace;
pub const WordBreak = text.WordBreak;
pub const OverflowWrap = text.OverflowWrap;
pub const ParagraphOptions = text.ParagraphOptions;
pub const ShapedGlyph = text.ShapedGlyph;
pub const PositionedGlyph = text.PositionedGlyph;
pub const Line = text.Line;
pub const Size = text.Size;
pub const TextLayout = text.TextLayout;
pub const Paragraph = text.Paragraph;
pub const shape = text.shape;
pub const layoutText = text.layoutText;
pub const FeatureSetting = text.FeatureSetting;
pub const ShapeCache = text.ShapeCache;
pub const Direction = text.Direction;
pub const TextWrap = text.TextWrap;

test {
    _ = ttf;
    _ = ot;
    _ = unicode;
    _ = collection;
    _ = text;
    _ = shape_mod;
    _ = bidi;
    _ = normalize;
    _ = cff;
    _ = variations;
    _ = @import("tests.zig");
    _ = @import("tests_formats.zig");
}
