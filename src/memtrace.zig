//! Memory checkpoints for measurements: `mark("label")` calls the hook a host installed (the native
//! addon's `memoryTrace`, which records its live byte count); nothing is called without one.
//! Labels must be string literals (the hook may keep them).

pub var hook: ?*const fn (label: []const u8) void = null;

pub inline fn mark(comptime label: []const u8) void {
    if (hook) |h| h(label);
}
