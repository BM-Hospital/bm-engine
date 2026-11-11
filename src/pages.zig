//! wasm-only general allocator: small blocks go to std's size-class allocator, blocks >= 32 KiB
//! are carved from whole 64 KiB wasm pages with a first-fit, coalescing free list. std's
//! allocator rounds every block up to a power of two (a 3.0 MB canvas costs 4 MB, and freed
//! blocks are only reusable for the same class), which is what this avoids.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const page = 64 * 1024;
const threshold = 32 * 1024;
const small = std.heap.wasm_allocator;

const Span = struct { addr: usize, pages: usize };
var free_spans: [128]Span = undefined;
var n_free: usize = 0;

fn pagesFor(len: usize) usize {
    return (len + page - 1) / page;
}

fn allocPages(n: usize) ?usize {
    // best fit
    var best: ?usize = null;
    for (free_spans[0..n_free], 0..) |s, i| {
        if (s.pages < n) continue;
        if (best == null or s.pages < free_spans[best.?].pages) best = i;
    }
    if (best) |i| {
        const s = free_spans[i];
        if (s.pages == n) {
            n_free -= 1;
            free_spans[i] = free_spans[n_free];
        } else {
            free_spans[i] = .{ .addr = s.addr + n * page, .pages = s.pages - n };
        }
        return s.addr;
    }
    // Extend the trailing free span if it touches the end of memory, else grow fresh.
    const end = @wasmMemorySize(0) * page;
    for (free_spans[0..n_free], 0..) |s, i| {
        if (s.addr + s.pages * page == end) {
            if (@wasmMemoryGrow(0, n - s.pages) == -1) return null;
            n_free -= 1;
            free_spans[i] = free_spans[n_free];
            return s.addr;
        }
    }
    const idx = @wasmMemoryGrow(0, n);
    if (idx == -1) return null;
    return @as(usize, @intCast(idx)) * page;
}

fn freePages(addr_in: usize, pages_in: usize) void {
    var addr = addr_in;
    var pages = pages_in;
    // coalesce with neighbours
    var i: usize = 0;
    while (i < n_free) {
        const s = free_spans[i];
        if (s.addr + s.pages * page == addr) {
            addr = s.addr;
            pages += s.pages;
        } else if (addr + pages * page == s.addr) {
            pages += s.pages;
        } else {
            i += 1;
            continue;
        }
        n_free -= 1;
        free_spans[i] = free_spans[n_free];
        i = 0;
    }
    if (n_free < free_spans.len) {
        free_spans[n_free] = .{ .addr = addr, .pages = pages };
        n_free += 1;
    } // else: leak the span (never happens in practice)
}

fn alloc(_: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    if (len < threshold or alignment.toByteUnits() > page) return small.vtable.alloc(small.ptr, len, alignment, ra);
    const addr = allocPages(pagesFor(len)) orelse return null;
    return @ptrFromInt(addr);
}

fn resize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
    if (memory.len < threshold) {
        if (new_len >= threshold) return false;
        return small.vtable.resize(small.ptr, memory, alignment, new_len, ra);
    }
    if (new_len < threshold) return false;
    return pagesFor(new_len) == pagesFor(memory.len);
}

fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
    if (memory.len < threshold and new_len < threshold) return small.vtable.remap(small.ptr, memory, alignment, new_len, ra);
    return if (resize(ctx, memory, alignment, new_len, ra)) memory.ptr else null;
}

fn free(_: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
    if (memory.len < threshold or alignment.toByteUnits() > page) return small.vtable.free(small.ptr, memory, alignment, ra);
    freePages(@intFromPtr(memory.ptr), pagesFor(memory.len));
}

const vtable: Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

pub const allocator: Allocator = .{ .ptr = undefined, .vtable = &vtable };
