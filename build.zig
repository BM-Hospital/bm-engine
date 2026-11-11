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
    const wasm = b.addExecutable(.{ .name = "bm_engine", .root_module = wasm_mod });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.import_memory = false;
    wasm.stack_size = 256 * 1024;
    b.installArtifact(wasm);

    const native_target = b.standardTargetOptions(.{});
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = native_target,
        .optimize = .debug,
    });
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);
}
