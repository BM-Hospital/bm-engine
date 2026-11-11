const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.option(std.builtin.Optimize, "wasm-optimize", "wasm optimize mode (small|fast|safe|debug)") orelse .small;
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{ .simd128, .bulk_memory, .sign_ext, .nontrapping_fptoint, .mutable_globals }),
    });
    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .strip = b.option(bool, "strip", "strip wasm debug info (default true)") orelse true,
        .unwind_tables = .none,
        .single_threaded = true,
    });
    // Feature flags (see src/config.zig). -Dprofile=core disables every optional feature.
    const profile = b.option([]const u8, "profile", "feature preset: full (default) | core") orelse "full";
    const full = !std.mem.eql(u8, profile, "core");
    const flags = b.addOptions();
    inline for (.{ "tw", "css", "html", "svg", "woff", "variable_fonts", "cff", "color_fonts", "complex_text", "animation", "extra_codecs" }) |name| {
        flags.addOption(bool, name, b.option(bool, name, "enable optional feature " ++ name) orelse full);
    }
    wasm_mod.addOptions("build_options", flags);

    const wasm = b.addExecutable(.{ .name = "bm_engine", .root_module = wasm_mod });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.import_memory = false;
    wasm.stack_size = (b.option(u64, "stack-kib", "wasm shadow stack size in KiB (default 1024)") orelse 1024) * 1024;
    b.installArtifact(wasm);

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
