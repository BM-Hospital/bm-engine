const std = @import("std");
const root = @import("root.zig");
const alloc = std.heap.wasm_allocator;
export fn bm_alloc(n: usize) ?[*]u8 {
    const s = alloc.alloc(u8, n) catch return null;
    return s.ptr;
}
export fn bm_free(p: [*]u8, n: usize) void {
    alloc.free(p[0..n]);
}
export fn bm_add(a: u32, b: u32) u32 {
    return root.add(a, b);
}
