//! wasm harness exporting src/woff for the Node probes in this directory (compare.mjs, fuzz.mjs,
//! perf.mjs). Build from the repo root (use -O safe for fuzzing/comparison, -O small for timing):
//!   zig build-exe -target wasm32-freestanding -O safe -fno-entry -rdynamic --dep woff
//!     -Mroot=bench/probe/woff/harness.zig -Mwoff=src/test_woff.zig -femit-bin=<scratch>/harness_safe.wasm
const std = @import("std");
const woff = @import("woff").woff;
const A = std.heap.wasm_allocator;

var out_ptr: [*]u8 = undefined;
var out_len: usize = 0;

export fn alloc(n: usize) ?[*]u8 {
    const s = A.alloc(u8, n) catch return null;
    return s.ptr;
}
export fn free(p: [*]u8, n: usize) void {
    A.free(p[0..n]);
}
export fn outPtr() [*]u8 {
    return out_ptr;
}
export fn freeOut() void {
    if (out_len != 0) A.free(out_ptr[0..out_len]);
    out_len = 0;
}
fn code(e: anyerror) i32 {
    return switch (e) {
        error.InvalidData => -1,
        error.UnsupportedFormat => -2,
        error.OutputTooLarge => -3,
        error.OutOfMemory => -4,
        else => -5,
    };
}
export fn sniff(p: [*]const u8, n: usize) i32 {
    return @intFromEnum(woff.sniff(p[0..n]));
}
export fn woffDecode(p: [*]const u8, n: usize) i32 {
    const r = woff.decode(A, p[0..n]) catch |e| return code(e);
    out_ptr = r.ptr;
    out_len = r.len;
    return @intCast(r.len);
}
export fn brotliDecode(p: [*]const u8, n: usize, max: usize) i32 {
    const r = woff.brotli.decompressAlloc(A, p[0..n], max) catch |e| return code(e);
    out_ptr = r.ptr;
    out_len = r.len;
    return @intCast(r.len);
}
