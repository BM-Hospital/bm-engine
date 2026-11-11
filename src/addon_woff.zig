//! Add-on wasm module `bm_woff.wasm`: WOFF / WOFF2 -> sfnt (TTF/OTF) conversion, for engine builds
//! compiled without `-Dwoff` (js/addons.mjs `loadWoff()` instantiates it on demand and feeds the
//! decoded font to `registerFont`). Same code as the built-in path (src/woff), so the result is
//! byte-identical. C ABI, no imports:
//!   bm_alloc(n) / bm_free(p, n)             buffers in this module's memory
//!   bm_woff_decode(p, n) -> 0 ok | 1 error  input is borrowed; output via bm_woff_result_*
//!   bm_woff_result_ptr() / _len()           sfnt bytes (valid until the next decode / release)
//!   bm_woff_release()                       frees the last result
const std = @import("std");
const woff = @import("woff/woff.zig");
const gpa = @import("pages.zig").allocator;

var result: []u8 = &.{};

export fn bm_alloc(n: usize) ?[*]u8 {
    const s = gpa.alloc(u8, if (n == 0) 1 else n) catch return null;
    return s.ptr;
}

export fn bm_free(p: ?[*]u8, n: usize) void {
    if (p) |ptr| gpa.free(ptr[0..if (n == 0) 1 else n]);
}

export fn bm_woff_release() void {
    if (result.len > 0) gpa.free(result);
    result = &.{};
}

/// 0 = decoded, 1 = not a WOFF/WOFF2 file or corrupt data, 2 = out of memory.
export fn bm_woff_decode(p: [*]const u8, n: usize) u32 {
    bm_woff_release();
    const bytes = p[0..n];
    switch (woff.sniff(bytes)) {
        .woff, .woff2 => {},
        else => return 1,
    }
    result = woff.decode(gpa, bytes) catch |e| return if (e == error.OutOfMemory) 2 else 1;
    return 0;
}

export fn bm_woff_result_ptr() [*]const u8 {
    return result.ptr;
}

export fn bm_woff_result_len() usize {
    return result.len;
}
