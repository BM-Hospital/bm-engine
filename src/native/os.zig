//! The few operating-system services the addon needs, kept away from `std.Io` so the engine stays
//! free of an event loop: a general allocator, a mutex, the stack left on the calling thread and
//! "run this on a thread with a stack of N bytes".
//!
//!   Windows        no libc: process heap (HeapAlloc), SRW lock, GetCurrentThreadStackLimits
//!   Linux / macOS  libc (glibc >= 2.17, musl, libSystem): malloc, pthread mutex, pthread stack query
//!
//! No thread-local storage is used anywhere (see scripts/build-native.mjs: the Linux artifacts are
//! checked to have no PT_TLS segment).
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const is_windows = builtin.os.tag == .windows;

// ---------------------------------------------------------------------------------------------
// allocator

/// Thread-safe general allocator.
pub const allocator: Allocator = if (is_windows) .{ .ptr = undefined, .vtable = &heap.vtable } else std.heap.c_allocator;

const heap = struct {
    extern "kernel32" fn GetProcessHeap() callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn HeapAlloc(h: *anyopaque, flags: u32, n: usize) callconv(.winapi) ?[*]u8;
    extern "kernel32" fn HeapReAlloc(h: *anyopaque, flags: u32, p: *anyopaque, n: usize) callconv(.winapi) ?[*]u8;
    extern "kernel32" fn HeapFree(h: *anyopaque, flags: u32, p: *anyopaque) callconv(.winapi) c_int;
    const REALLOC_IN_PLACE_ONLY: u32 = 0x10;
    /// HeapAlloc aligns to 2 * @sizeOf(usize) (MEMORY_ALLOCATION_ALIGNMENT).
    const natural: usize = 2 * @sizeOf(usize);

    const vtable: Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

    fn alloc(_: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
        const h = GetProcessHeap() orelse return null;
        const al = alignment.toByteUnits();
        if (al <= natural) return HeapAlloc(h, 0, if (len == 0) 1 else len);
        // over-aligned: keep the heap block's address just below the returned pointer
        const total = std.math.add(usize, len, al + @sizeOf(usize)) catch return null;
        const base = HeapAlloc(h, 0, total) orelse return null;
        const addr = alignment.forward(@intFromPtr(base) + @sizeOf(usize));
        @as(*usize, @ptrFromInt(addr - @sizeOf(usize))).* = @intFromPtr(base);
        return @ptrFromInt(addr);
    }

    fn resize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
        if (new_len <= memory.len) return true;
        if (alignment.toByteUnits() > natural) return false;
        const h = GetProcessHeap() orelse return false;
        return HeapReAlloc(h, REALLOC_IN_PLACE_ONLY, memory.ptr, new_len) != null;
    }

    fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
        if (alignment.toByteUnits() > natural) return if (new_len <= memory.len) memory.ptr else null;
        const h = GetProcessHeap() orelse return null;
        return HeapReAlloc(h, 0, memory.ptr, if (new_len == 0) 1 else new_len);
    }

    fn free(_: *anyopaque, memory: []u8, alignment: Alignment, _: usize) void {
        const h = GetProcessHeap() orelse return;
        if (alignment.toByteUnits() <= natural) {
            _ = HeapFree(h, 0, memory.ptr);
        } else {
            const base = @as(*usize, @ptrFromInt(@intFromPtr(memory.ptr) - @sizeOf(usize))).*;
            _ = HeapFree(h, 0, @ptrFromInt(base));
        }
    }
};

// ---------------------------------------------------------------------------------------------
// mutex

pub const Mutex = if (is_windows) struct {
    /// SRWLOCK (statically initialised, nothing to destroy)
    lock_word: usize = 0,

    extern "kernel32" fn AcquireSRWLockExclusive(l: *usize) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(l: *usize) callconv(.winapi) void;

    pub fn lock(m: *@This()) void {
        AcquireSRWLockExclusive(&m.lock_word);
    }
    pub fn unlock(m: *@This()) void {
        ReleaseSRWLockExclusive(&m.lock_word);
    }
    pub fn deinit(_: *@This()) void {}
} else struct {
    inner: std.c.pthread_mutex_t = .{},

    pub fn lock(m: *@This()) void {
        _ = std.c.pthread_mutex_lock(&m.inner);
    }
    pub fn unlock(m: *@This()) void {
        _ = std.c.pthread_mutex_unlock(&m.inner);
    }
    pub fn deinit(m: *@This()) void {
        _ = std.c.pthread_mutex_destroy(&m.inner);
    }
};

// ---------------------------------------------------------------------------------------------
// stack

const posix_stack = struct {
    extern "c" fn pthread_getattr_np(thread: std.c.pthread_t, attr: *std.c.pthread_attr_t) c_int;
    extern "c" fn pthread_attr_getstack(attr: *const std.c.pthread_attr_t, addr: *?*anyopaque, size: *usize) c_int;
    extern "c" fn pthread_get_stackaddr_np(thread: std.c.pthread_t) ?*anyopaque;
    extern "c" fn pthread_get_stacksize_np(thread: std.c.pthread_t) usize;
};
extern "kernel32" fn GetCurrentThreadStackLimits(low: *usize, high: *usize) callconv(.winapi) void;

/// Lowest address of the calling thread's stack, or 0 when it cannot be determined.
/// (glibc reads /proc/self/maps for the initial thread: callers cache the answer per thread.)
pub fn stackLow() usize {
    switch (builtin.os.tag) {
        .windows => {
            var low: usize = 0;
            var high: usize = 0;
            GetCurrentThreadStackLimits(&low, &high);
            return low;
        },
        .linux => {
            var attr: std.c.pthread_attr_t = undefined;
            if (posix_stack.pthread_getattr_np(std.c.pthread_self(), &attr) != 0) return 0;
            defer _ = std.c.pthread_attr_destroy(&attr);
            var addr: ?*anyopaque = null;
            var size: usize = 0;
            if (posix_stack.pthread_attr_getstack(&attr, &addr, &size) != 0) return 0;
            var low = @intFromPtr(addr);
            const linux = std.os.linux;
            if (low != 0 and linux.getpid() == linux.gettid()) {
                // The initial thread's stack grows on demand, down to RLIMIT_STACK below its top. glibc
                // already answers with that extent; musl only with the part mapped so far.
                var lim: linux.rlimit = undefined;
                var max: usize = 8 << 20;
                if (linux.getrlimit(.STACK, &lim) == 0 and lim.cur != linux.RLIM.INFINITY and lim.cur <= 1 << 30) max = @intCast(lim.cur);
                const by_limit = (low + size) -| max;
                if (by_limit != 0 and by_limit < low) low = by_limit;
            }
            return low;
        },
        .macos => {
            const self = std.c.pthread_self();
            const top = @intFromPtr(posix_stack.pthread_get_stackaddr_np(self));
            const size = posix_stack.pthread_get_stacksize_np(self);
            return if (top > size) top - size else 0;
        },
        else => return 0,
    }
}

/// Bytes between the current stack pointer and `low` (0 when `low` is unknown or implausible).
pub inline fn stackLeft(low: usize) usize {
    const sp = @frameAddress();
    // more than 1 GiB away: `low` does not describe this thread's stack
    return if (low != 0 and sp > low and sp - low < (1 << 30)) sp - low else 0;
}

const win_thread = struct {
    extern "kernel32" fn CreateThread(attr: ?*anyopaque, stack: usize, start: *const fn (?*anyopaque) callconv(.winapi) u32, param: ?*anyopaque, flags: u32, id: ?*u32) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn WaitForSingleObject(h: *anyopaque, ms: u32) callconv(.winapi) u32;
    extern "kernel32" fn CloseHandle(h: *anyopaque) callconv(.winapi) c_int;
    /// `stack` is the reserved size (not the initial commit)
    const STACK_SIZE_PARAM_IS_A_RESERVATION: u32 = 0x00010000;
    const INFINITE: u32 = 0xffffffff;
};

/// Runs `f(arg)` on a new thread whose stack is `stack_bytes` and waits for it. False when the
/// thread cannot be created. (Plain CreateThread / pthread_create rather than std.Thread, which
/// brings thread-local storage and a signal stack into the shared object.)
pub fn runOnThread(stack_bytes: usize, comptime f: anytype, arg: anytype) bool {
    const Arg = @TypeOf(arg);
    // whole 64 KiB units: a multiple of every page size (pthread_attr_setstacksize insists on Darwin)
    const size = std.mem.alignForward(usize, @max(stack_bytes, 64 << 10), 64 << 10);
    if (is_windows) {
        const T = struct {
            fn start(p: ?*anyopaque) callconv(.winapi) u32 {
                f(@as(Arg, @ptrCast(@alignCast(p.?))));
                return 0;
            }
        };
        const h = win_thread.CreateThread(null, size, T.start, arg, win_thread.STACK_SIZE_PARAM_IS_A_RESERVATION, null) orelse return false;
        _ = win_thread.WaitForSingleObject(h, win_thread.INFINITE);
        _ = win_thread.CloseHandle(h);
        return true;
    } else {
        const T = struct {
            fn start(p: ?*anyopaque) callconv(.c) ?*anyopaque {
                f(@as(Arg, @ptrCast(@alignCast(p.?))));
                return null;
            }
        };
        var attr: std.c.pthread_attr_t = undefined;
        if (std.c.pthread_attr_init(&attr) != .SUCCESS) return false;
        defer _ = std.c.pthread_attr_destroy(&attr);
        if (std.c.pthread_attr_setstacksize(&attr, size) != .SUCCESS) return false;
        var thread: std.c.pthread_t = undefined;
        if (std.c.pthread_create(&thread, &attr, T.start, arg) != .SUCCESS) return false;
        _ = std.c.pthread_join(thread, null);
        return true;
    }
}
