//! Node-API (N-API) declarations, written by hand against the ABI-stable C interface (no node
//! headers, no node-gyp). `Api` lists exactly the host functions the addon uses: one field per
//! function, the field name is the symbol name.
//!
//! How the symbols are bound:
//!   * Linux / macOS: plain undefined symbols (`@extern`), resolved by the dynamic loader against
//!     the host executable when the addon is dlopen()ed (linked with "allow undefined" /
//!     `-undefined dynamic_lookup`, see build.zig).
//!   * Windows: NOT through an import library for `node.exe`. `load()` looks every symbol up at
//!     module registration with GetProcAddress, first in the host executable (whatever its file
//!     name: node.exe, a renamed copy, electron.exe, bun.exe, ...), then in node.dll / libnode.dll.
//!     This is what the usual `delayimp` hook of node-gyp addons achieves, without any import of
//!     `node.exe` in the PE import table.
const std = @import("std");
const builtin = @import("builtin");

pub const Env = ?*opaque {};
pub const Value = ?*opaque {};
pub const CallbackInfo = ?*opaque {};
pub const Deferred = ?*opaque {};
pub const AsyncWork = ?*opaque {};

/// `napi_status` (only the values the addon looks at).
pub const Status = enum(c_int) { ok = 0, cancelled = 11, _ };
/// `napi_valuetype`.
pub const ValueType = enum(c_int) { undefined = 0, null, boolean, number, string, symbol, object, function, external, bigint, _ };
/// `napi_typedarray_type` (`napi_uint8_array` = 1).
pub const TypedArrayType = enum(c_int) { int8 = 0, uint8 = 1, uint8_clamped = 2, _ };

pub const Callback = *const fn (Env, CallbackInfo) callconv(.c) Value;
pub const Finalize = *const fn (Env, ?*anyopaque, ?*anyopaque) callconv(.c) void;
pub const AsyncExecute = *const fn (Env, ?*anyopaque) callconv(.c) void;
pub const AsyncComplete = *const fn (Env, Status, ?*anyopaque) callconv(.c) void;

/// Every Node-API function used by the addon (all available since N-API 6 / Node 12.17).
pub const Api = struct {
    napi_create_function: *const fn (Env, ?[*]const u8, usize, Callback, ?*anyopaque, *Value) callconv(.c) Status,
    napi_set_named_property: *const fn (Env, Value, [*:0]const u8, Value) callconv(.c) Status,
    napi_get_cb_info: *const fn (Env, CallbackInfo, ?*usize, ?[*]Value, ?*Value, ?*?*anyopaque) callconv(.c) Status,
    napi_typeof: *const fn (Env, Value, *ValueType) callconv(.c) Status,
    napi_get_undefined: *const fn (Env, *Value) callconv(.c) Status,
    napi_create_object: *const fn (Env, *Value) callconv(.c) Status,
    napi_create_uint32: *const fn (Env, u32, *Value) callconv(.c) Status,
    napi_create_double: *const fn (Env, f64, *Value) callconv(.c) Status,
    napi_create_string_utf8: *const fn (Env, [*]const u8, usize, *Value) callconv(.c) Status,
    napi_get_value_uint32: *const fn (Env, Value, *u32) callconv(.c) Status,
    napi_get_value_double: *const fn (Env, Value, *f64) callconv(.c) Status,
    napi_get_value_string_utf8: *const fn (Env, Value, ?[*]u8, usize, ?*usize) callconv(.c) Status,
    napi_is_typedarray: *const fn (Env, Value, *bool) callconv(.c) Status,
    napi_get_typedarray_info: *const fn (Env, Value, ?*TypedArrayType, ?*usize, ?*?[*]u8, ?*Value, ?*usize) callconv(.c) Status,
    napi_is_array: *const fn (Env, Value, *bool) callconv(.c) Status,
    napi_get_array_length: *const fn (Env, Value, *u32) callconv(.c) Status,
    napi_get_element: *const fn (Env, Value, u32, *Value) callconv(.c) Status,
    napi_create_arraybuffer: *const fn (Env, usize, *?[*]u8, *Value) callconv(.c) Status,
    napi_create_typedarray: *const fn (Env, TypedArrayType, usize, Value, usize, *Value) callconv(.c) Status,
    napi_create_external: *const fn (Env, ?*anyopaque, ?Finalize, ?*anyopaque, *Value) callconv(.c) Status,
    napi_get_value_external: *const fn (Env, Value, *?*anyopaque) callconv(.c) Status,
    napi_create_error: *const fn (Env, Value, Value, *Value) callconv(.c) Status,
    napi_create_type_error: *const fn (Env, Value, Value, *Value) callconv(.c) Status,
    napi_throw: *const fn (Env, Value) callconv(.c) Status,
    napi_create_promise: *const fn (Env, *Deferred, *Value) callconv(.c) Status,
    napi_resolve_deferred: *const fn (Env, Deferred, Value) callconv(.c) Status,
    napi_reject_deferred: *const fn (Env, Deferred, Value) callconv(.c) Status,
    napi_create_async_work: *const fn (Env, Value, Value, AsyncExecute, AsyncComplete, ?*anyopaque, *AsyncWork) callconv(.c) Status,
    napi_queue_async_work: *const fn (Env, AsyncWork) callconv(.c) Status,
    napi_delete_async_work: *const fn (Env, AsyncWork) callconv(.c) Status,
    napi_adjust_external_memory: *const fn (Env, i64, *i64) callconv(.c) Status,
    napi_set_instance_data: *const fn (Env, ?*anyopaque, ?Finalize, ?*anyopaque) callconv(.c) Status,
    napi_get_instance_data: *const fn (Env, *?*anyopaque) callconv(.c) Status,
};

const is_windows = builtin.os.tag == .windows;

/// The bound host functions: `napi.api.napi_create_object(env, &v)`.
pub const api: *const Api = if (is_windows) &win.table else &posix_table;

const posix_table: Api = blk: {
    var t: Api = undefined;
    for (std.meta.fieldNames(Api)) |name| @field(t, name) = @extern(@FieldType(Api, name), .{ .name = name });
    break :blk t;
};

const win = struct {
    extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;

    /// Filled by `load()`. Every environment (main thread, each worker) that loads the addon
    /// stores the same pointers again, so concurrent registrations are harmless.
    var table: Api = undefined;

    fn tryModule(m: *anyopaque) bool {
        var t: Api = undefined;
        inline for (comptime std.meta.fieldNames(Api)) |name| {
            const p = GetProcAddress(m, name) orelse return false;
            @field(t, name) = @ptrCast(@alignCast(p));
        }
        table = t;
        return true;
    }
};

/// Binds the host functions. False when the host process exports no Node-API (Windows only; on the
/// other systems an addon with unresolved symbols is rejected by the loader before this runs).
pub fn load() bool {
    if (!is_windows) return true;
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    const names = [_]?[*:0]const u16{ null, L("node.dll"), L("libnode.dll") };
    for (names) |n| {
        const m = win.GetModuleHandleW(n) orelse continue;
        if (win.tryModule(m)) return true;
    }
    return false;
}
