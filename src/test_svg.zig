//! Test root for the SVG module (it imports sibling directories, so it must be rooted at src/).
//! Run: zig test src/test_svg.zig --test-filter svg
//! Also used as the module root of the wasm probes in bench/probe/svg (harness.zig).
pub const svg = @import("svg/svg.zig");
pub const raster = @import("raster/raster.zig");
pub const codec = @import("codec/codec.zig");

test {
    _ = svg;
}
