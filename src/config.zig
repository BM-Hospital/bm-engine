//! Compile-time feature switches (single place every module reads them from).
//! `zig build -Dprofile=core|standard|full` selects a preset (see build.zig for what each contains);
//! individual flags can be overridden with -D<name>=true|false. Modules outside src/ root read them
//! through `@import("root").bm_config` (falling back to "enabled" in standalone module tests).
const opts = @import("build_options");

pub const profile: []const u8 = opts.profile;
pub const enable_tw: bool = opts.tw;
pub const enable_css: bool = opts.css;
pub const enable_html: bool = opts.html;
pub const enable_svg: bool = opts.svg;
pub const enable_woff: bool = opts.woff;
pub const enable_variable_fonts: bool = opts.variable_fonts;
pub const enable_cff: bool = opts.cff;
pub const enable_color_fonts: bool = opts.color_fonts;
pub const enable_complex_text: bool = opts.complex_text;
pub const enable_animation: bool = opts.animation;
pub const enable_extra_codecs: bool = opts.extra_codecs;
pub const enable_tables: bool = opts.tables;
pub const enable_floats: bool = opts.floats;
pub const enable_render_svg: bool = opts.render_svg;
pub const enable_effects: bool = opts.effects;
pub const enable_modern_color: bool = opts.modern_color;
pub const enable_webp_gif_decode: bool = opts.webp_gif_decode;
pub const enable_text_wrap_balance: bool = opts.text_wrap_balance;
/// `content` / counters / generated boxes only exist with a stylesheet or Tailwind.
pub const enable_generated_content: bool = opts.css or opts.tw;

/// Bit mask reported by `bm_features()` (js/index.mjs `features`); bit order is ABI.
pub const feature_bits: u32 = bits: {
    const list = [_]bool{ opts.css, opts.tw, opts.html, opts.svg, opts.woff, opts.variable_fonts, opts.cff, opts.effects, opts.modern_color, opts.tables, opts.floats, opts.webp_gif_decode, opts.text_wrap_balance, opts.color_fonts, opts.complex_text, opts.animation, opts.extra_codecs, opts.render_svg };
    var m: u32 = 0;
    for (list, 0..) |on, i| {
        if (on) m |= 1 << i;
    }
    break :bits m;
};
