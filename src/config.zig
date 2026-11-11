//! Compile-time feature switches (single place every module reads them from).
//! `zig build -Dprofile=core|full` selects a preset; individual flags can be overridden with -D<name>=true|false.
const opts = @import("build_options");

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
