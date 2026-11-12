const std = @import("std");

/// Optional features (see src/config.zig) and the profiles that enable them. Every flag can be
/// overridden on top of a profile with `-D<name>=true|false`.
const Feature = struct { name: []const u8, desc: []const u8, standard: bool };
const features = [_]Feature{
    .{ .name = "css", .desc = "stylesheets (`css` option, HTML <style>), selectors, @keyframes", .standard = true },
    .{ .name = "tw", .desc = "Tailwind `tw` utilities", .standard = true },
    .{ .name = "html", .desc = "HTML markup input", .standard = true },
    .{ .name = "svg", .desc = "SVG images (image src / url(), clip-path path())", .standard = true },
    .{ .name = "woff", .desc = "WOFF / WOFF2 fonts (brotli)", .standard = true },
    .{ .name = "variable_fonts", .desc = "variable fonts (fvar/gvar/HVAR/MVAR/avar instances)", .standard = true },
    .{ .name = "cff", .desc = "CFF / CFF2 outlines (OpenType .otf)", .standard = true },
    .{ .name = "effects", .desc = "clip-path, masks, mix-/background-blend-mode, backdrop-filter, isolation", .standard = true },
    .{ .name = "modern_color", .desc = "lab/lch/oklab/oklch/color()/color-mix()/light-dark(), gradient `in <space>`", .standard = true },
    .{ .name = "tables", .desc = "table layout", .standard = true },
    .{ .name = "floats", .desc = "floats", .standard = true },
    .{ .name = "webp_gif_decode", .desc = "WebP (lossless) and GIF image sources", .standard = true },
    .{ .name = "text_wrap_balance", .desc = "text-wrap: balance / pretty (score-based line breaking)", .standard = true },
    .{ .name = "color_fonts", .desc = "colour glyphs (COLR v0/v1, CBDT/sbix PNG), emoji presentation", .standard = false },
    .{ .name = "bitmap_glyphs", .desc = "colour bitmap glyphs only (CBDT/CBLC, sbix PNG emoji) + emoji presentation; implied by color_fonts", .standard = true },
    .{ .name = "complex_text", .desc = "bidi, Arabic/Hebrew/Indic/Thai shaping, normalisation", .standard = false },
    .{ .name = "animation", .desc = "CSS animations / transitions, renderAnimation, animated image sources", .standard = false },
    .{ .name = "extra_codecs", .desc = "WebP lossy (VP8) decode, animated GIF/APNG/WebP decode + encode, ICO output", .standard = false },
    .{ .name = "render_svg", .desc = "renderSvg (vector SVG output)", .standard = false },
};

pub fn build(b: *std.Build) void {
    const optimize = b.option(std.builtin.Optimize, "wasm-optimize", "wasm optimize mode (small|fast|safe|debug)") orelse .small;
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{ .simd128, .bulk_memory, .sign_ext, .nontrapping_fptoint, .mutable_globals }),
    });
    const strip = b.option(bool, "strip", "strip wasm debug info (default true)") orelse true;
    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .strip = strip,
        .unwind_tables = .none,
        .single_threaded = true,
    });
    // Feature flags (see src/config.zig): -Dprofile=core|standard|full (default full).
    const profile = b.option([]const u8, "profile", "feature preset: core | standard | full (default)") orelse "full";
    const level: u2 = if (std.mem.eql(u8, profile, "core")) 0 else if (std.mem.eql(u8, profile, "standard")) 1 else if (std.mem.eql(u8, profile, "full")) 2 else {
        std.debug.panic("unknown -Dprofile={s} (core | standard | full)", .{profile});
    };
    const flags = b.addOptions();
    inline for (features) |ft| {
        const def = level == 2 or (level == 1 and ft.standard);
        flags.addOption(bool, ft.name, b.option(bool, ft.name, ft.desc) orelse def);
    }
    flags.addOption([]const u8, "profile", profile);
    wasm_mod.addOptions("build_options", flags);

    const stack = (b.option(u64, "stack-kib", "wasm shadow stack size in KiB (default 1024)") orelse 1024) * 1024;
    const wasm = b.addExecutable(.{ .name = "bm_engine", .root_module = wasm_mod });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.import_memory = false;
    wasm.stack_size = stack;
    b.installArtifact(wasm);

    // Stand-alone add-on modules (lazy-loaded by js/addons.mjs): WOFF/WOFF2 -> sfnt.
    const woff_mod = b.createModule(.{
        .root_source_file = b.path("src/addon_woff.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .strip = strip,
        .unwind_tables = .none,
        .single_threaded = true,
    });
    const woff = b.addExecutable(.{ .name = "bm_woff", .root_module = woff_mod });
    woff.entry = .disabled;
    woff.rdynamic = true;
    woff.import_memory = false;
    woff.stack_size = 256 * 1024;
    const woff_install = b.addInstallArtifact(woff, .{});
    b.getInstallStep().dependOn(&woff_install.step);
    b.step("addons", "Build the add-on wasm modules only").dependOn(&woff_install.step);

    const native_target = b.standardTargetOptions(.{});
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = native_target,
        .optimize = .debug,
    });
    test_mod.addOptions("build_options", flags);
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);
}
