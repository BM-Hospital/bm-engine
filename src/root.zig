//! Native root: pulls in every module's unit tests.
pub const json = @import("json.zig");
pub const render = @import("render.zig");
pub const paint = @import("paint.zig");
/// Feature switches for modules (`@import("root").bm_config`).
pub const bm_config = @import("config.zig");

test {
    _ = json;
    _ = render;
    _ = @import("dom.zig");
    _ = @import("test_fixcss.zig");
    _ = @import("animate.zig");
    _ = paint;
    _ = @import("bump.zig");
    _ = @import("style/style.zig");
    _ = @import("layout/layout.zig");
    _ = @import("font/font.zig");
    _ = @import("raster/raster.zig");
    _ = @import("codec/codec.zig");
}
