const std = @import("std");
const tw = @import("tw");

var heap: [8 << 20]u8 = undefined;
var in_buf: [1 << 16]u8 = undefined;
var out_buf: [1 << 18]u8 = undefined;

export fn inPtr() [*]u8 {
    return &in_buf;
}
export fn outPtr() [*]u8 {
    return &out_buf;
}

/// Compiles in_buf[0..len]; writes JSON [{"n":..,"v":..,"i":0|1},...] to out_buf, returns its length.
export fn compile(len: u32, vw: f32, vh: f32, dpr: f32, idx: i32, count: u32, target: u32) u32 {
    var fba = std.heap.FixedBufferAllocator.init(&heap);
    const a = fba.allocator();
    var out: std.ArrayList(tw.Declaration) = .empty;
    var env = tw.Env{ .viewport_w = vw, .viewport_h = vh, .dpr = dpr, .target = @enumFromInt(@as(u2, @truncate(target))) };
    if (idx >= 0) env.element = .{ .index = @intCast(idx), .count = count, .type_index = @intCast(idx), .type_count = count };
    tw.compile(a, in_buf[0..@min(len, in_buf.len)], env, &out) catch return 0;
    var n: usize = 0;
    put(&n, "[");
    for (out.items, 0..) |d, i| {
        if (i > 0) put(&n, ",");
        put(&n, "{\"n\":\"");
        esc(&n, d.name);
        put(&n, "\",\"v\":\"");
        esc(&n, d.value);
        put(&n, if (d.important) "\",\"i\":1}" else "\",\"i\":0}");
    }
    put(&n, "]");
    return @intCast(n);
}

fn put(n: *usize, s: []const u8) void {
    if (n.* + s.len > out_buf.len) return;
    @memcpy(out_buf[n.*..][0..s.len], s);
    n.* += s.len;
}

fn esc(n: *usize, s: []const u8) void {
    for (s) |c| {
        if (c == '"' or c == 92) {
            put(n, &.{92});
            put(n, &.{c});
        } else if (c < 0x20) {
            const hex = "0123456789abcdef";
            put(n, &.{ 92, 'u', '0', '0', hex[c >> 4], hex[c & 15] });
        } else put(n, &.{c});
    }
}
