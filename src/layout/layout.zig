//! bm-engine layout: CSS flexbox / block (with floats) / grid / tables / inline rows over a flat node tree, sized
//! like Chrome (the takumi oracle is a Blink LayoutNG port). See `Tree` for the entry points.
//! `TreeWith(.{ .tables = false, .floats = false, .inline_row = false })` compiles optional features out
//! (`Tree` = `TreeWith(.{})`, everything on): table displays and inline rows then lay out as blocks, floats as
//! in-flow blocks.
//!
//! Usage:
//!   var t = Tree.init(arena);                       // all memory (nodes, caches, scratch) comes from `arena`
//!   const root = try t.addNode(.{ .size = .{ .{ .px = 1200 }, .{ .px = 630 } } });
//!   const child = try t.addNode(.{ .flex_grow = 1 });
//!   try t.appendChild(root, child);
//!   t.setMeasured(text_node, true);                 // leaf sized by the MeasureFn (text, images)
//!   try t.compute(root, .{ .{ .definite = 1200 }, .{ .definite = 630 } }, ctx, measureFn, .{});
//!   const l = t.layout(child);                      // border box relative to the parent's border box
//!
//! Things the caller must know:
//!  * `Style` defaults are convenience defaults (display flex, position relative, border-box), not the CSS
//!    initial values. takumi's initial `display` is `inline` and `position` is `static`: set
//!    `.position = .static` on boxes that must not be the containing block of absolute descendants.
//!  * The root is blockified: an auto width fills a definite available width, an auto height is content-sized,
//!    the root's margins offset it inside the viewport.
//!  * Text is owned by the caller. A block of plain text is a measured leaf (`MeasureFn`). Mixed inline content
//!    is a `Display.inline_row` node: with `Config.inline_fn` (flow.zig) the caller's `Options.inline_fn` breaks
//!    the lines (text and the node's atomic inline children together) and the engine supplies item sizes and,
//!    per line, the inline range left free by floats; inline content flagged `Style.is_inline_content` keeps
//!    its full width beside floats and only its lines shorten. Without `Config.inline_fn`, `inline_row`
//!    (inline.zig) lays atomic boxes and whole measured leaves out on wrapping rows, and next to floats a
//!    measured leaf / formatting context root is fitted into the free band at its top edge (block.zig).
//!  * `Style.order` reorders flex / grid items inside the tree (pre-sorted children with order 0 work as before).
//!  * `Position.fixed` boxes resolve against the `available` size passed to `compute`.
//!  * Results are unrounded f32. `Options.quantize64` snaps edges to Blink's 1/64 px grid, `Options.round` to
//!    whole pixels (edges are rounded in absolute space, so siblings never gap or overlap).
//!  * Nesting deeper than `max_depth` (512) fails with `error.TooDeep`. Per-node algorithm state lives in the
//!    tree's scratch arena: a nesting level costs 64-128 bytes of wasm shadow stack (plus the engine's native
//!    call stack: V8 runs out of it at roughly 1200 levels).
//!  * `compute` may be called again after style changes (`setStyle`); every call recomputes everything.
const std = @import("std");
pub const style = @import("style.zig");
pub const tree = @import("tree.zig");

pub const Dim = style.Dim;
pub const LengthPercentage = style.LengthPercentage;
pub const Edges = style.Edges;
pub const Style = style.Style;
pub const Display = style.Display;
pub const Position = style.Position;
pub const Float = style.Float;
pub const Clear = style.Clear;
pub const VerticalAlign = style.VerticalAlign;
pub const TextAlign = style.TextAlign;
pub const AlignSafe = style.AlignSafe;
pub const BoxSizing = style.BoxSizing;
pub const Overflow = style.Overflow;
pub const FlexDirection = style.FlexDirection;
pub const FlexWrap = style.FlexWrap;
pub const Align = style.Align;
pub const Track = style.Track;
pub const TrackBreadth = style.TrackBreadth;
pub const AutoRepeat = style.AutoRepeat;
pub const Line = style.Line;
pub const Placement = style.Placement;
pub const GridAutoFlow = style.GridAutoFlow;
pub const AvailableSpace = style.AvailableSpace;
pub const NodeId = tree.NodeId;
pub const Tree = tree.Tree;
pub const TreeWith = tree.TreeWith;
pub const Config = tree.Config;
pub const Layout = tree.Layout;
pub const TableGeom = @import("table.zig").Geom;
pub const MeasureFn = tree.MeasureFn;
pub const BaselineFn = tree.BaselineFn;
pub const InlineFn = tree.InlineFn;
pub const InlineIo = tree.InlineIo;
pub const InlineItem = tree.InlineItem;
pub const InlineBand = tree.InlineBand;
pub const Options = tree.Options;
pub const Error = tree.Error;
pub const max_depth = tree.max_depth;

test {
    _ = @import("tests.zig");
    _ = @import("tests_table.zig");
    _ = @import("tests_inline.zig");
    _ = @import("tests_float.zig");
    _ = @import("tests_flow.zig");
}
