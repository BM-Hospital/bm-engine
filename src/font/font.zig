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

pub const Font = ttf.Font;
pub const FontError = ttf.Error;
pub const Bounds = ttf.Bounds;
pub const LineMetrics = ttf.LineMetrics;
pub const emitGlyph = ttf.emitGlyph;
pub const decodeUtf8 = unicode.decodeUtf8;

pub const FaceId = collection.FaceId;
pub const Face = collection.Face;
pub const FontCollection = collection.FontCollection;
pub const RegisterOptions = collection.RegisterOptions;

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

test {
    _ = ttf;
    _ = ot;
    _ = unicode;
    _ = collection;
    _ = text;
    _ = @import("tests.zig");
}
