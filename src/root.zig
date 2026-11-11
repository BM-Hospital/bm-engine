//! Native root: pulls in every module's unit tests.
pub const json = @import("json.zig");
pub const render = @import("render.zig");
pub const paint = @import("paint.zig");

test {
    _ = json;
    _ = render;
    _ = paint;
    _ = @import("style/style.zig");
    _ = @import("layout/layout.zig");
    _ = @import("font/font.zig");
    _ = @import("raster/raster.zig");
    _ = @import("codec/codec.zig");
}
