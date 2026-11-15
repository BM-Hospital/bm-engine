//! Per-render bump allocator that keeps its chunks between renders.
//!
//! `std.heap.ArenaAllocator.reset(.retain_capacity)` frees every chunk and allocates one of the
//! combined size, which on wasm (size-class based BrkAllocator, memory never returned) strands
//! the old chunks and balloons linear memory. This allocator instead rewinds and reuses chunks:
//! steady-state renders perform no backing allocations at all.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

pub const Bump = struct {
    backing: Allocator,
    chunks: std.ArrayList(Chunk) = .empty,
    /// index of the chunk currently being filled
    cur: usize = 0,
    /// high-water statistics of the current cycle
    used_this_cycle: usize = 0,
    /// A chunk untouched for this many consecutive resets is returned to the backing allocator.
    idle_limit: u8 = 3,
    /// A chunk larger than `min_chunk` (one made for a big allocation) that a `free` empties goes
    /// back to the backing allocator at once instead of waiting for a reset: for an arena that is
    /// never reset (a PDF layout pass), where the old buffers of a growing large list would
    /// otherwise stay allocated.
    release_freed: bool = false,

    const Chunk = struct {
        mem: []align(16) u8,
        used: usize = 0,
        /// number of consecutive resets this chunk stayed unused
        idle: u8 = 0,
    };

    const min_chunk: usize = 256 * 1024;

    pub fn init(backing: Allocator) Bump {
        return .{ .backing = backing };
    }

    pub fn deinit(self: *Bump) void {
        for (self.chunks.items) |c| self.backing.free(c.mem);
        self.chunks.deinit(self.backing);
        self.* = .{ .backing = self.backing };
    }

    pub fn allocator(self: *Bump) Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    /// Rewinds every chunk. Chunks that went unused for several cycles are released.
    pub fn reset(self: *Bump) void {
        var i: usize = 0;
        while (i < self.chunks.items.len) {
            const c = &self.chunks.items[i];
            if (c.used == 0) {
                c.idle +|= 1;
                if (c.idle >= self.idle_limit) {
                    self.backing.free(c.mem);
                    _ = self.chunks.orderedRemove(i);
                    continue;
                }
            } else c.idle = 0;
            c.used = 0;
            i += 1;
        }
        self.cur = 0;
        self.used_this_cycle = 0;
    }

    /// Bytes currently retained from the backing allocator.
    pub fn capacity(self: *const Bump) usize {
        var n: usize = 0;
        for (self.chunks.items) |c| n += c.mem.len;
        return n;
    }

    fn tryChunk(c: *Chunk, len: usize, alignment: Alignment) ?[*]u8 {
        const base = @intFromPtr(c.mem.ptr);
        const start = alignment.forward(base + c.used) - base;
        if (start > c.mem.len or c.mem.len - start < len) return null;
        c.used = start + len;
        return c.mem.ptr + start;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Bump = @ptrCast(@alignCast(ctx));
        if (alignment.toByteUnits() > 16) return null;
        self.used_this_cycle += len;
        const big = len >= min_chunk / 2;
        if (!big) {
            // small: fill the current chunk, then later small chunks
            var i = self.cur;
            while (i < self.chunks.items.len) : (i += 1) {
                const c = &self.chunks.items[i];
                if (c.mem.len > min_chunk * 4 and c.used == 0) continue; // keep big chunks for big requests
                if (tryChunk(c, len, alignment)) |p| {
                    self.cur = i;
                    return p;
                }
            }
        } else {
            // big: best-fitting empty chunk (so same-sized canvases reuse the same block)
            var best: ?usize = null;
            for (self.chunks.items, 0..) |c, i| {
                if (c.used != 0 or c.mem.len < len) continue;
                if (best == null or c.mem.len < self.chunks.items[best.?].mem.len) best = i;
            }
            if (best) |i| {
                if (self.chunks.items[i].mem.len <= len + len / 2 + 64) return tryChunk(&self.chunks.items[i], len, alignment);
            }
        }
        const size = if (big) len else @max(min_chunk, len);
        const mem = self.backing.alignedAlloc(u8, .@"16", size) catch return null;
        self.chunks.append(self.backing, .{ .mem = mem }) catch {
            self.backing.free(mem);
            return null;
        };
        const c = &self.chunks.items[self.chunks.items.len - 1];
        if (!big) self.cur = self.chunks.items.len - 1;
        return tryChunk(c, len, alignment);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        _ = alignment;
        _ = ret_addr;
        const self: *Bump = @ptrCast(@alignCast(ctx));
        // grow in place only when `memory` is the last allocation of its chunk (a shrink of the last
        // allocation gives its tail back: `toOwnedSlice` of a list with spare capacity)
        const ci = self.find(memory.ptr) orelse return new_len <= memory.len;
        const c = &self.chunks.items[ci];
        const off = @intFromPtr(memory.ptr) - @intFromPtr(c.mem.ptr);
        if (off + memory.len != c.used) return new_len <= memory.len;
        if (new_len <= memory.len) {
            c.used = off + new_len;
            return true;
        }
        if (c.mem.len - off < new_len) return false;
        c.used = off + new_len;
        return true;
    }

    /// The chunk holding `ptr`: the current one, else the most recent first (what is resized or
    /// freed was mostly allocated last; a front-to-back search made each call cost every chunk).
    fn find(self: *const Bump, ptr: [*]u8) ?usize {
        const p = @intFromPtr(ptr);
        const items = self.chunks.items;
        if (self.cur < items.len) {
            const base = @intFromPtr(items[self.cur].mem.ptr);
            if (p >= base and p < base + items[self.cur].mem.len) return self.cur;
        }
        var i = items.len;
        while (i > 0) {
            i -= 1;
            const base = @intFromPtr(items[i].mem.ptr);
            if (p >= base and p < base + items[i].mem.len) return i;
        }
        return null;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        const self: *Bump = @ptrCast(@alignCast(ctx));
        // pop when it is the last allocation of its chunk (cheap LIFO reuse)
        const i = self.find(memory.ptr) orelse return;
        const c = &self.chunks.items[i];
        const off = @intFromPtr(memory.ptr) - @intFromPtr(c.mem.ptr);
        if (off + memory.len == c.used) c.used = off;
        if (self.release_freed and c.used == 0 and c.mem.len > min_chunk) {
            self.backing.free(c.mem);
            _ = self.chunks.orderedRemove(i);
            if (self.cur > i) self.cur -= 1 else if (self.cur == i) self.cur = 0;
        }
    }

    const vtable: Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };
};

test "bump reuse" {
    var b = Bump.init(std.testing.allocator);
    defer b.deinit();
    const a = b.allocator();
    var cap: usize = 0;
    for (0..5) |round| {
        const big = try a.alloc(u8, 3 << 20);
        @memset(big, 1);
        var list: std.ArrayList(u32) = .empty;
        for (0..10000) |i| try list.append(a, @intCast(i));
        const small = try a.create(u64);
        small.* = 7;
        try std.testing.expectEqual(@as(u32, 9999), list.items[9999]);
        if (round == 1) cap = b.capacity();
        if (round > 1) try std.testing.expectEqual(cap, b.capacity());
        b.reset();
    }
}
