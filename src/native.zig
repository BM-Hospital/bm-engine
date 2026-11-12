//! Node-API addon entry point: the same engine as src/wasm.zig, exposed to Node.js as
//! `bm-engine.<platform>-<arch>[-<abi>].node` (`zig build native`, scripts/build-native.mjs).
//! JavaScript side: js/native.mjs (loader) and the native backend in js/node-backend.mjs; the
//! public API is the one implementation in js/engine.mjs. Contract and design: docs/NATIVE.md.
//!
//! Exports (an internal interface between this file and js/node-backend.mjs, versioned by `abi`):
//!
//!   abi: 1                       features: u32 (src/config.zig feature_bits)
//!   ops: { name: index }         the operation table (src/native/ops.zig)
//!   create() -> handle           a renderer (an opaque external; garbage collection frees it)
//!   destroy(handle)              frees it now (pending async work on it then fails cleanly)
//!   run(handle | null, op, arg0, arg1, input, options, attachments) -> Uint8Array
//!   runAsync(... same ...) -> Promise<Uint8Array>
//!       input / options: string | Uint8Array | null; attachments: null or a flat array of
//!       [key: string, data: Uint8Array, flags, width, height] groups (ops.zig `Attachment`).
//!   memoryBytes() -> number      bytes currently allocated by the addon in this process
//!   tune(stackMode, stackBytes, maxBytes)  test hook (0 keeps a value), see `Instance`
//!
//! Threading: `run` executes on the calling thread; `runAsync` snapshots its inputs (strings and
//! buffers are copied), then executes on a libuv pool thread (napi_create_async_work) and settles
//! the promise back on the JS thread. A renderer is not re-entrant, so calls on ONE renderer are
//! serialised: async calls through a per-renderer FIFO (only one of them occupies a pool thread at a
//! time), sync calls with the renderer's mutex. Different renderers share no mutable state and
//! run in parallel. The engine has no globals; the addon's own are the allocation counter (atomic)
//! and, on Windows, the table of host function pointers (written with identical values by every
//! environment). Per-environment state lives in `Instance` (napi instance data), so the addon can
//! be loaded by several worker_threads at once.
//!
//! Stack: the engine recurses per nesting level (bounded: render.max_node_depth, the parsers' and
//! the layout engine's caps), and a native stack overflow kills the process instead of trapping.
//! Every engine call therefore checks how much stack the calling thread has left; with less than
//! `stack_need` it runs the call on a temporary thread created with exactly that much stack.
const std = @import("std");
const builtin = @import("builtin");
const napi = @import("native/napi.zig");
const os = @import("native/os.zig");
const ops = @import("native/ops.zig");
const render = @import("render.zig");
/// Feature switches, visible to modules as `@import("root").bm_config` (see src/font/ttf.zig).
pub const bm_config = @import("config.zig");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const Renderer = render.Renderer;
const api = napi.api;
const Env = napi.Env;
const Value = napi.Value;

pub const abi_version: u32 = 1;

/// Panics (only reachable in safe builds) print the message and trap; no stack traces, no std.Io.
pub const panic = std.debug.FullPanic(panicImpl);

fn panicImpl(msg: []const u8, _: ?usize) noreturn {
    @branchHint(.cold);
    if (builtin.os.tag == .windows) {
        const k = struct {
            extern "kernel32" fn GetStdHandle(n: u32) callconv(.winapi) ?*anyopaque;
            extern "kernel32" fn WriteFile(h: ?*anyopaque, p: [*]const u8, n: u32, written: ?*u32, ov: ?*anyopaque) callconv(.winapi) c_int;
        };
        const h = k.GetStdHandle(@bitCast(@as(i32, -12)));
        _ = k.WriteFile(h, "bm-engine panic: ", 17, null, null);
        _ = k.WriteFile(h, msg.ptr, @intCast(msg.len), null, null);
        _ = k.WriteFile(h, "\n", 1, null, null);
    } else {
        _ = std.c.write(2, "bm-engine panic: ", 17);
        _ = std.c.write(2, msg.ptr, msg.len);
        _ = std.c.write(2, "\n", 1);
    }
    @trap();
}

// ---------------------------------------------------------------------------------------------
// memory accounting

/// Bytes currently allocated through the addon (every environment of the process).
var live_bytes: std.atomic.Value(usize) = .init(0);

/// The process allocator plus the `live_bytes` counter (inputs / results of async jobs, handles).
const counted: Allocator = .{ .ptr = undefined, .vtable = &counted_vtable };
const counted_vtable: Allocator.VTable = .{ .alloc = countedAlloc, .resize = countedResize, .remap = countedRemap, .free = countedFree };

fn countedAlloc(_: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    const p = os.allocator.rawAlloc(len, alignment, ra) orelse return null;
    _ = live_bytes.fetchAdd(len, .monotonic);
    return p;
}
fn countedResize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
    if (!os.allocator.rawResize(memory, alignment, new_len, ra)) return false;
    _ = live_bytes.fetchAdd(new_len -% memory.len, .monotonic);
    return true;
}
fn countedRemap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
    const p = os.allocator.rawRemap(memory, alignment, new_len, ra) orelse return null;
    _ = live_bytes.fetchAdd(new_len -% memory.len, .monotonic);
    return p;
}
fn countedFree(_: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
    os.allocator.rawFree(memory, alignment, ra);
    _ = live_bytes.fetchSub(memory.len, .monotonic);
}

/// A renderer's allocator: `counted` with a per-renderer cap, so a request the wasm build answers
/// with "out of memory" (its address space is 4 GiB) cannot take the machine down natively.
const limited_vtable: Allocator.VTable = .{ .alloc = limitedAlloc, .resize = limitedResize, .remap = limitedRemap, .free = limitedFree };

fn limitedAlloc(ctx: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    const h: *Handle = @ptrCast(@alignCast(ctx));
    if (len > h.limit -| h.used) return null;
    const p = counted.rawAlloc(len, alignment, ra) orelse return null;
    h.used += len;
    return p;
}
fn limitedResize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
    const h: *Handle = @ptrCast(@alignCast(ctx));
    if (new_len > memory.len and new_len - memory.len > h.limit -| h.used) return false;
    if (!counted.rawResize(memory, alignment, new_len, ra)) return false;
    h.used = h.used - memory.len + new_len;
    return true;
}
fn limitedRemap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
    const h: *Handle = @ptrCast(@alignCast(ctx));
    if (new_len > memory.len and new_len - memory.len > h.limit -| h.used) return null;
    const p = counted.rawRemap(memory, alignment, new_len, ra) orelse return null;
    h.used = h.used - memory.len + new_len;
    return p;
}
fn limitedFree(ctx: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
    const h: *Handle = @ptrCast(@alignCast(ctx));
    counted.rawFree(memory, alignment, ra);
    h.used -= memory.len;
}

// ---------------------------------------------------------------------------------------------
// per-environment and per-renderer state

const StackMode = enum(u32) {
    /// run inline when the calling thread has `stack_need` bytes left, else on a temporary thread
    auto = 1,
    /// always on a temporary thread of `stack_need` bytes (tests)
    thread = 2,
    /// always inline (tests)
    inline_ = 3,
};

/// Stack the engine is guaranteed for one call. Measured worst case (512-level trees, deepest
/// accepted JSON / HTML / CSS nesting; bench/native-tests.mjs "stack") is far below; see docs/NATIVE.md.
const default_stack_need: usize = 2 << 20;
/// Default cap of one renderer's memory.
const default_max_bytes: usize = if (@sizeOf(usize) >= 8) 4 << 30 else std.math.maxInt(usize);

/// State of one Node.js environment (the main thread or one worker).
const Instance = struct {
    /// lowest address of the environment thread's stack (0 = unknown: sync calls use a thread)
    stack_low: usize,
    stack_mode: StackMode = .auto,
    stack_need: usize = default_stack_need,
    max_bytes: usize = default_max_bytes,
};

const Stack = struct { mode: StackMode, need: usize };

const handle_magic: u32 = 0x626d4e31;

/// One renderer. Only the environment thread touches `refs`, `closed`, `running`, the queue and
/// `reported`; `r` and `used` belong to whoever executes a call (under `mutex`).
const Handle = struct {
    magic: u32 = handle_magic,
    mutex: os.Mutex = .{},
    r: ?*Renderer = null,
    /// 1 for the JS external + 1 per pending async job
    refs: u32 = 1,
    /// destroy() was called
    closed: bool = false,
    /// an async job of this renderer is in the libuv queue or executing
    running: bool = false,
    q_head: ?*Job = null,
    q_tail: ?*Job = null,
    used: usize = 0,
    limit: usize,
    /// bytes reported to V8 (napi_adjust_external_memory)
    reported: i64 = 0,

    fn gpa(h: *Handle) Allocator {
        return .{ .ptr = h, .vtable = &limited_vtable };
    }

    /// Tells the garbage collector how much native memory hangs off the JS object.
    fn report(h: *Handle, env: Env) void {
        const now: i64 = @intCast(h.used);
        const delta = now - h.reported;
        if (delta == 0) return;
        var total: i64 = 0;
        if (api.napi_adjust_external_memory(env, delta, &total) == .ok) h.reported = now;
    }

    /// Frees the engine renderer (not the handle). Environment thread, no job running.
    fn destroyRenderer(h: *Handle, env: Env) void {
        if (h.r) |r| {
            h.mutex.lock();
            h.r = null;
            r.destroy();
            h.mutex.unlock();
        }
        h.report(env);
    }

    fn release(h: *Handle, env: Env) void {
        h.refs -= 1;
        if (h.refs != 0) return;
        h.destroyRenderer(env);
        h.mutex.deinit();
        h.magic = 0;
        counted.destroy(h);
    }
};

// ---------------------------------------------------------------------------------------------
// one call

/// The inputs of a call. `copy = false` (sync): typed-array data is borrowed from JS for the
/// duration of the call; strings are always extracted into owned memory.
const Inputs = struct {
    input: []const u8 = "",
    options: []const u8 = "",
    atts: []ops.Attachment = &.{},
    /// owned allocations (`counted`), freed by deinit
    owned: std.ArrayList([]u8) = .empty,

    fn deinit(in: *Inputs) void {
        for (in.owned.items) |b| counted.free(b);
        in.owned.deinit(counted);
        if (in.atts.len != 0) counted.free(in.atts);
        in.* = .{};
    }

    const ReadError = error{ OutOfMemory, BadArgument };

    fn keep(in: *Inputs, buf: []u8) ReadError!void {
        in.owned.append(counted, buf) catch {
            counted.free(buf);
            return error.OutOfMemory;
        };
    }

    /// string | Uint8Array | null | undefined -> bytes
    fn bytes(in: *Inputs, env: Env, v: Value, copy: bool) ReadError![]const u8 {
        var t: napi.ValueType = .undefined;
        if (api.napi_typeof(env, v, &t) != .ok) return error.BadArgument;
        switch (t) {
            .undefined, .null => return "",
            .string => {
                var len: usize = 0;
                if (api.napi_get_value_string_utf8(env, v, null, 0, &len) != .ok) return error.BadArgument;
                if (len == 0) return "";
                const buf = counted.alloc(u8, len + 1) catch return error.OutOfMemory;
                try in.keep(buf);
                var written: usize = 0;
                if (api.napi_get_value_string_utf8(env, v, buf.ptr, len + 1, &written) != .ok) return error.BadArgument;
                return buf[0..written];
            },
            .object => {
                var is_ta = false;
                if (api.napi_is_typedarray(env, v, &is_ta) != .ok or !is_ta) return error.BadArgument;
                var ty: napi.TypedArrayType = .uint8;
                var len: usize = 0;
                var data: ?[*]u8 = null;
                if (api.napi_get_typedarray_info(env, v, &ty, &len, &data, null, null) != .ok) return error.BadArgument;
                if (ty != .uint8 and ty != .uint8_clamped and ty != .int8) return error.BadArgument;
                if (len == 0 or data == null) return "";
                if (!copy) return data.?[0..len];
                const buf = counted.alloc(u8, len) catch return error.OutOfMemory;
                try in.keep(buf);
                @memcpy(buf, data.?[0..len]);
                return buf;
            },
            else => return error.BadArgument,
        }
    }

    fn uint(env: Env, v: Value) ReadError!u32 {
        var n: u32 = 0;
        if (api.napi_get_value_uint32(env, v, &n) != .ok) return error.BadArgument;
        return n;
    }

    /// null | undefined | [key, data, flags, width, height, ...]
    fn attachments(in: *Inputs, env: Env, v: Value, copy: bool) ReadError!void {
        var t: napi.ValueType = .undefined;
        if (api.napi_typeof(env, v, &t) != .ok) return error.BadArgument;
        if (t == .undefined or t == .null) return;
        var is_arr = false;
        if (api.napi_is_array(env, v, &is_arr) != .ok or !is_arr) return error.BadArgument;
        var n: u32 = 0;
        if (api.napi_get_array_length(env, v, &n) != .ok or n % 5 != 0) return error.BadArgument;
        if (n == 0) return;
        const list = counted.alloc(ops.Attachment, n / 5) catch return error.OutOfMemory;
        in.atts = list;
        for (list, 0..) |*a, i| {
            var e: [5]Value = undefined;
            for (&e, 0..) |*x, k| {
                if (api.napi_get_element(env, v, @intCast(i * 5 + k), x) != .ok) return error.BadArgument;
            }
            a.* = .{};
            a.key = try in.bytes(env, e[0], true);
            a.data = try in.bytes(env, e[1], copy);
            a.flags = try uint(env, e[2]);
            a.width = try uint(env, e[3]);
            a.height = try uint(env, e[4]);
        }
    }
};

/// Everything `execute` needs; lives on the stack for sync calls and in a `Job` for async ones.
const Exec = struct {
    h: ?*Handle,
    op: *const ops.Op,
    arg0: u32,
    arg1: u32,
    in: *Inputs,
    stack: Stack,
    /// where the result goes: sync = straight into a new ArrayBuffer (`env` set), async = `out`
    env: Env = null,
    js_result: Value = null,
    out: []u8 = &.{},
    /// "" = success
    err: []const u8 = "",
    err_buf: [300]u8 = undefined,

    fn fail(x: *Exec, msg: []const u8) void {
        const n = @min(msg.len, x.err_buf.len);
        @memcpy(x.err_buf[0..n], msg[0..n]);
        x.err = x.err_buf[0..n];
    }

    /// Locks the renderer and runs the op with enough stack. `stack_low`: of the calling thread.
    fn execute(x: *Exec, stack_low: usize) void {
        if (x.h) |h| h.mutex.lock();
        defer if (x.h) |h| h.mutex.unlock();
        const inline_ok = switch (x.stack.mode) {
            .inline_ => true,
            .thread => false,
            .auto => os.stackLeft(stack_low) >= x.stack.need,
        };
        if (inline_ok) {
            x.runOp();
        } else if (x.env != null) {
            // sync call: the result must be handed to JS on this thread
            const env = x.env;
            x.env = null;
            if (!os.runOnThread(x.stack.need, runOp, x)) return x.fail("out of memory");
            x.env = env;
            if (x.err.len == 0) x.deliver();
        } else {
            if (!os.runOnThread(x.stack.need, runOp, x)) return x.fail("out of memory");
        }
    }

    /// The engine call itself (any thread; the renderer is locked).
    fn runOp(x: *Exec) void {
        const r: ?*Renderer = if (x.h) |h| h.r else null;
        if (x.op.renderer and r == null) return x.fail("renderer has been freed");
        var call: ops.Call = .{
            .r = r,
            .gpa = if (x.h) |h| h.gpa() else counted,
            .arg0 = x.arg0,
            .arg1 = x.arg1,
            .input = x.in.input,
            .options = x.in.options,
            .attachments = x.in.atts,
        };
        const status: ops.Error!void = blk: {
            if (x.op.images) {
                const rr = r.?;
                rr.clearImages();
                for (x.in.atts) |a| {
                    if (a.flags & 1 != 0) {
                        if (a.width == 0 or a.height == 0) {
                            call.err = "raw image must have non-zero size";
                            break :blk error.Invalid;
                        }
                        rr.putImage(a.key, a.data, a.width, a.height, a.flags & 2 != 0) catch |e| break :blk e;
                    } else {
                        rr.putImage(a.key, a.data, 0, 0, false) catch |e| break :blk e;
                    }
                }
            }
            break :blk x.op.run(&call);
        };
        if (status) |_| {
            if (x.env != null) {
                x.js_result = makeBytes(x.env, call.result);
                if (x.js_result == null) x.fail("out of memory");
            } else {
                x.out = counted.dupe(u8, call.result) catch blk: {
                    x.fail("out of memory");
                    break :blk &.{};
                };
            }
        } else |e| switch (e) {
            error.OutOfMemory => x.fail("out of memory"),
            // the wasm binding's message: `last_error`, or "error <status>" when it is empty
            error.Invalid => x.fail(if (call.err.len != 0) call.err else if (r != null and r.?.err.len != 0) r.?.err else "error 1"),
        }
        if (call.owned) call.gpa.free(call.result);
        if (r) |rr| {
            rr.releaseResult();
            if (x.op.images) rr.clearImages();
        }
    }

    /// Sync call that ran on a helper thread: copy `out` into a JS value on the JS thread.
    fn deliver(x: *Exec) void {
        x.js_result = makeBytes(x.env, x.out);
        counted.free(x.out);
        x.out = &.{};
        if (x.js_result == null) x.fail("out of memory");
    }
};

/// A fresh Uint8Array owning a copy of `data` (null when V8 cannot allocate it).
fn makeBytes(env: Env, data: []const u8) Value {
    var ptr: ?[*]u8 = null;
    var ab: Value = null;
    if (api.napi_create_arraybuffer(env, data.len, &ptr, &ab) != .ok) return null;
    if (data.len != 0) {
        if (ptr) |p| @memcpy(p[0..data.len], data) else return null;
    }
    var out: Value = null;
    if (api.napi_create_typedarray(env, .uint8, data.len, ab, 0, &out) != .ok) return null;
    return out;
}

fn makeError(env: Env, msg: []const u8, type_error: bool) Value {
    var buf: [320]u8 = undefined;
    const prefix = "bm-engine: ";
    @memcpy(buf[0..prefix.len], prefix);
    const n = @min(msg.len, buf.len - prefix.len);
    @memcpy(buf[prefix.len..][0..n], msg[0..n]);
    var s: Value = null;
    _ = api.napi_create_string_utf8(env, &buf, prefix.len + n, &s);
    var e: Value = null;
    _ = (if (type_error) api.napi_create_type_error else api.napi_create_error)(env, null, s, &e);
    return e;
}

fn throwError(env: Env, msg: []const u8, type_error: bool) Value {
    _ = api.napi_throw(env, makeError(env, msg, type_error));
    return null;
}

fn undefinedValue(env: Env) Value {
    var v: Value = null;
    _ = api.napi_get_undefined(env, &v);
    return v;
}

/// An async call: owns its inputs and its result.
const Job = struct {
    x: Exec,
    in: Inputs = .{},
    work: napi.AsyncWork = null,
    deferred: napi.Deferred = null,
    next: ?*Job = null,

    fn destroy(j: *Job) void {
        j.in.deinit();
        if (j.x.out.len != 0) counted.free(j.x.out);
        counted.destroy(j);
    }

    /// libuv pool thread.
    fn execute(_: Env, data: ?*anyopaque) callconv(.c) void {
        const j: *Job = @ptrCast(@alignCast(data.?));
        j.x.execute(os.stackLow());
    }

    /// Environment thread.
    fn complete(env: Env, status: napi.Status, data: ?*anyopaque) callconv(.c) void {
        const j: *Job = @ptrCast(@alignCast(data.?));
        const h = j.x.h;
        if (h) |hh| {
            hh.running = false;
            if (hh.closed) hh.destroyRenderer(env) else hh.report(env);
            startNext(env, hh);
        }
        if (status != .ok) j.x.fail("the render was cancelled");
        j.settle(env);
        if (h) |hh| hh.release(env);
    }

    /// Resolves / rejects the promise and frees the job (not its handle reference).
    fn settle(j: *Job, env: Env) void {
        if (j.x.err.len == 0) {
            const v = makeBytes(env, j.x.out);
            if (v != null) {
                _ = api.napi_resolve_deferred(env, j.deferred, v);
            } else {
                _ = api.napi_reject_deferred(env, j.deferred, makeError(env, "out of memory", false));
            }
        } else {
            _ = api.napi_reject_deferred(env, j.deferred, makeError(env, j.x.err, false));
        }
        _ = api.napi_delete_async_work(env, j.work);
        j.destroy();
    }

    /// Hands the next queued job of `h` to the thread pool (jobs that cannot be queued any more,
    /// e.g. while the environment shuts down, are rejected).
    fn startNext(env: Env, h: *Handle) void {
        while (h.q_head) |next| {
            h.q_head = next.next;
            if (h.q_head == null) h.q_tail = null;
            next.next = null;
            if (api.napi_queue_async_work(env, next.work) == .ok) {
                h.running = true;
                return;
            }
            next.x.fail("the render was cancelled");
            next.settle(env);
            h.release(env);
        }
    }
};

// ---------------------------------------------------------------------------------------------
// JS-visible functions

fn instanceOf(data: ?*anyopaque) *Instance {
    return @ptrCast(@alignCast(data.?));
}

const Args = struct { argv: [7]Value, inst: *Instance };

fn getArgs(env: Env, info: napi.CallbackInfo) ?Args {
    var a: Args = undefined;
    var argc: usize = a.argv.len;
    var data: ?*anyopaque = null;
    if (api.napi_get_cb_info(env, info, &argc, &a.argv, null, &data) != .ok or data == null) return null;
    // missing arguments are `undefined`
    if (argc < a.argv.len) {
        const u = undefinedValue(env);
        for (a.argv[argc..]) |*v| v.* = u;
    }
    a.inst = instanceOf(data);
    return a;
}

/// external | null | undefined -> handle (error.BadArgument for anything else)
fn getHandle(env: Env, v: Value) error{BadArgument}!?*Handle {
    var t: napi.ValueType = .undefined;
    if (api.napi_typeof(env, v, &t) != .ok) return error.BadArgument;
    if (t == .undefined or t == .null) return null;
    if (t != .external) return error.BadArgument;
    var p: ?*anyopaque = null;
    if (api.napi_get_value_external(env, v, &p) != .ok or p == null) return error.BadArgument;
    const h: *Handle = @ptrCast(@alignCast(p.?));
    if (h.magic != handle_magic) return error.BadArgument;
    return h;
}

fn jsCreate(env: Env, info: napi.CallbackInfo) callconv(.c) Value {
    const a = getArgs(env, info) orelse return throwError(env, "invalid native call", true);
    const h = counted.create(Handle) catch return throwError(env, "out of memory", false);
    h.* = .{ .limit = a.inst.max_bytes };
    h.r = Renderer.create(h.gpa()) orelse {
        counted.destroy(h);
        return throwError(env, "out of memory", false);
    };
    var v: Value = null;
    if (api.napi_create_external(env, h, finalizeHandle, null, &v) != .ok) {
        h.release(env);
        return throwError(env, "out of memory", false);
    }
    h.report(env);
    return v;
}

fn finalizeHandle(env: Env, data: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const h: *Handle = @ptrCast(@alignCast(data.?));
    h.release(env);
}

fn jsDestroy(env: Env, info: napi.CallbackInfo) callconv(.c) Value {
    const a = getArgs(env, info) orelse return throwError(env, "invalid native call", true);
    const h = (getHandle(env, a.argv[0]) catch null) orelse return throwError(env, "invalid native call", true);
    h.closed = true;
    // an executing job keeps the renderer until it completes (Job.complete frees it then)
    if (!h.running) h.destroyRenderer(env);
    return undefinedValue(env);
}

const Parsed = struct { h: ?*Handle, op: *const ops.Op, arg0: u32, arg1: u32 };

fn parseCall(env: Env, a: *const Args, in: *Inputs, copy: bool) Inputs.ReadError!Parsed {
    const h = try getHandle(env, a.argv[0]);
    const op_index = try Inputs.uint(env, a.argv[1]);
    if (op_index >= ops.table.len) return error.BadArgument;
    const op = &ops.table[op_index];
    if (op.renderer and h == null) return error.BadArgument;
    const arg0 = try Inputs.uint(env, a.argv[2]);
    const arg1 = try Inputs.uint(env, a.argv[3]);
    in.input = try in.bytes(env, a.argv[4], copy);
    in.options = try in.bytes(env, a.argv[5], copy);
    try in.attachments(env, a.argv[6], copy);
    return .{ .h = if (op.renderer) h else null, .op = op, .arg0 = arg0, .arg1 = arg1 };
}

fn jsRun(env: Env, info: napi.CallbackInfo) callconv(.c) Value {
    const a = getArgs(env, info) orelse return throwError(env, "invalid native call", true);
    var in: Inputs = .{};
    defer in.deinit();
    const p = parseCall(env, &a, &in, false) catch |e| return throwError(env, if (e == error.OutOfMemory) "out of memory" else "invalid native call", e != error.OutOfMemory);
    if (p.h) |h| {
        if (h.closed) return throwError(env, "renderer has been freed", false);
    }
    var x: Exec = .{ .h = p.h, .op = p.op, .arg0 = p.arg0, .arg1 = p.arg1, .in = &in, .stack = .{ .mode = a.inst.stack_mode, .need = a.inst.stack_need }, .env = env };
    x.execute(a.inst.stack_low);
    if (p.h) |h| h.report(env);
    if (x.err.len != 0) return throwError(env, x.err, false);
    return x.js_result;
}

fn jsRunAsync(env: Env, info: napi.CallbackInfo) callconv(.c) Value {
    const a = getArgs(env, info) orelse return throwError(env, "invalid native call", true);
    const j = counted.create(Job) catch return throwError(env, "out of memory", false);
    const stack: Stack = .{ .mode = a.inst.stack_mode, .need = a.inst.stack_need };
    j.* = .{ .x = .{ .h = null, .op = &ops.table[0], .arg0 = 0, .arg1 = 0, .in = &j.in, .stack = stack } };
    const p = parseCall(env, &a, &j.in, true) catch |e| {
        j.destroy();
        return throwError(env, if (e == error.OutOfMemory) "out of memory" else "invalid native call", e != error.OutOfMemory);
    };
    j.x = .{ .h = p.h, .op = p.op, .arg0 = p.arg0, .arg1 = p.arg1, .in = &j.in, .stack = stack };

    var promise: Value = null;
    var name: Value = null;
    if (api.napi_create_promise(env, &j.deferred, &promise) != .ok or
        api.napi_create_string_utf8(env, "bm-engine", 9, &name) != .ok or
        api.napi_create_async_work(env, null, name, Job.execute, Job.complete, j, &j.work) != .ok)
    {
        // (a promise that was created is simply dropped)
        j.destroy();
        return throwError(env, "out of memory", false);
    }
    if (p.h) |h| {
        h.refs += 1;
        if (h.running) {
            if (h.q_tail) |t| t.next = j else h.q_head = j;
            h.q_tail = j;
            return promise;
        }
        h.running = true;
    }
    if (api.napi_queue_async_work(env, j.work) != .ok) {
        if (p.h) |h| h.running = false;
        j.x.fail("the render was cancelled");
        j.settle(env);
        if (p.h) |h| h.release(env);
    }
    return promise;
}

fn jsMemoryBytes(env: Env, _: napi.CallbackInfo) callconv(.c) Value {
    var v: Value = null;
    _ = api.napi_create_double(env, @floatFromInt(live_bytes.load(.monotonic)), &v);
    return v;
}

/// tune(stackMode, stackBytes, maxBytes): test hook; 0 / undefined keeps the current value.
fn jsTune(env: Env, info: napi.CallbackInfo) callconv(.c) Value {
    const a = getArgs(env, info) orelse return throwError(env, "invalid native call", true);
    var nums: [3]f64 = .{ 0, 0, 0 };
    for (&nums, 0..) |*n, i| _ = api.napi_get_value_double(env, a.argv[i], n);
    if (nums[0] >= 1 and nums[0] <= 3) a.inst.stack_mode = @enumFromInt(@as(u32, @intFromFloat(nums[0])));
    if (nums[1] >= 16384 and nums[1] <= 1 << 30) a.inst.stack_need = @intFromFloat(nums[1]);
    if (nums[2] >= 1 and nums[2] <= 1 << 46) a.inst.max_bytes = @intFromFloat(nums[2]);
    return undefinedValue(env);
}

fn finalizeInstance(_: Env, data: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    os.allocator.destroy(instanceOf(data));
}

fn addFunction(env: Env, exports: Value, comptime name: [:0]const u8, cb: napi.Callback, inst: *Instance) bool {
    var f: Value = null;
    if (api.napi_create_function(env, name.ptr, name.len, cb, inst, &f) != .ok) return false;
    return api.napi_set_named_property(env, exports, name.ptr, f) == .ok;
}

fn addNumber(env: Env, obj: Value, name: [*:0]const u8, n: u32) bool {
    var v: Value = null;
    if (api.napi_create_uint32(env, n, &v) != .ok) return false;
    return api.napi_set_named_property(env, obj, name, v) == .ok;
}

/// Module registration: called once per environment that loads the addon (context-aware: no
/// static `napi_module`, all state per environment).
export fn napi_register_module_v1(env: Env, exports: Value) callconv(.c) Value {
    if (!napi.load()) return null;
    const inst = os.allocator.create(Instance) catch return null;
    inst.* = .{ .stack_low = os.stackLow() };
    if (api.napi_set_instance_data(env, inst, finalizeInstance, null) != .ok) {
        os.allocator.destroy(inst);
        return null;
    }
    var ok = addNumber(env, exports, "abi", abi_version) and addNumber(env, exports, "features", bm_config.feature_bits);
    var op_map: Value = null;
    ok = ok and api.napi_create_object(env, &op_map) == .ok;
    for (ops.table, 0..) |op, i| ok = ok and addNumber(env, op_map, op.name.ptr, @intCast(i));
    ok = ok and api.napi_set_named_property(env, exports, "ops", op_map) == .ok;
    ok = ok and addFunction(env, exports, "create", jsCreate, inst);
    ok = ok and addFunction(env, exports, "destroy", jsDestroy, inst);
    ok = ok and addFunction(env, exports, "run", jsRun, inst);
    ok = ok and addFunction(env, exports, "runAsync", jsRunAsync, inst);
    ok = ok and addFunction(env, exports, "memoryBytes", jsMemoryBytes, inst);
    ok = ok and addFunction(env, exports, "tune", jsTune, inst);
    return if (ok) exports else null;
}
