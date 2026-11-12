//! PNG encoder timing on dumped frames (Windows only, like src/raster/bench.zig).
//!
//!   node bench/perf/dump-raw.mjs <dir> img-photo-bg,card-og          # <dir>/<id>.<w>x<h>.rgba
//!   zig build-exe -OReleaseFast -mcpu=x86_64_v2 --dep png -Mroot=bench/perf/pngprof.zig -Mpng=src/codec/png.zig
//!   pngprof.exe <file.WxH.rgba> [...]
//!
//! Prints, per file: best-of-N encode time, the PNG size, and a check that the PNG decodes back
//! to the same pixels.
const std = @import("std");
const png = @import("png");

extern "kernel32" fn QueryPerformanceCounter(count: *i64) callconv(.winapi) i32;
extern "kernel32" fn QueryPerformanceFrequency(freq: *i64) callconv(.winapi) i32;
extern "kernel32" fn GetCommandLineA() callconv(.winapi) [*:0]const u8;
extern "kernel32" fn CreateFileA(name: [*:0]const u8, access: u32, share: u32, sec: ?*anyopaque, disp: u32, flags: u32, tmpl: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn ReadFile(h: *anyopaque, buf: [*]u8, n: u32, got: *u32, ov: ?*anyopaque) callconv(.winapi) i32;
extern "kernel32" fn GetFileSize(h: *anyopaque, high: ?*u32) callconv(.winapi) u32;
extern "kernel32" fn CloseHandle(h: *anyopaque) callconv(.winapi) i32;

fn now() f64 {
    var c: i64 = 0;
    var f: i64 = 1;
    _ = QueryPerformanceCounter(&c);
    _ = QueryPerformanceFrequency(&f);
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(f));
}

fn readFile(alloc: std.mem.Allocator, path: [*:0]const u8) ?[]u8 {
    const invalid: usize = std.math.maxInt(usize);
    const h = CreateFileA(path, 0x80000000, 1, null, 3, 0, null) orelse return null;
    if (@intFromPtr(h) == invalid) return null;
    defer _ = CloseHandle(h);
    const n = GetFileSize(h, null);
    const buf = alloc.alloc(u8, n) catch return null;
    var off: usize = 0;
    while (off < n) {
        var got: u32 = 0;
        if (ReadFile(h, buf.ptr + off, @intCast(n - off), &got, null) == 0 or got == 0) return null;
        off += got;
    }
    return buf;
}

/// "<anything>.<w>x<h>.rgba" -> { w, h }
fn dims(path: []const u8) ?[2]u32 {
    const end = std.mem.lastIndexOf(u8, path, ".rgba") orelse return null;
    const start = (std.mem.lastIndexOfScalar(u8, path[0..end], '.') orelse return null) + 1;
    const x = std.mem.indexOfScalar(u8, path[start..end], 'x') orelse return null;
    const w = std.fmt.parseInt(u32, path[start .. start + x], 10) catch return null;
    const h = std.fmt.parseInt(u32, path[start + x + 1 .. end], 10) catch return null;
    return .{ w, h };
}

pub fn main() !void {
    const page = std.heap.page_allocator;
    const arena_mem = try page.alloc(u8, 256 << 20);
    var fba = std.heap.FixedBufferAllocator.init(arena_mem);
    const cmd = std.mem.span(GetCommandLineA());
    var it = std.mem.tokenizeScalar(u8, cmd, ' ');
    _ = it.next();
    var total_ms: f64 = 0;
    var total_bytes: usize = 0;
    while (it.next()) |arg| {
        const path = std.mem.trim(u8, arg, "\"");
        const wh = dims(path) orelse {
            std.debug.print("{s}: name must end in .<w>x<h>.rgba\n", .{path});
            continue;
        };
        const z = try page.alloc(u8, path.len + 1);
        @memcpy(z[0..path.len], path);
        z[path.len] = 0;
        const rgba = readFile(page, @ptrCast(z.ptr)) orelse {
            std.debug.print("{s}: cannot read\n", .{path});
            continue;
        };
        if (rgba.len != @as(usize, wh[0]) * wh[1] * 4) {
            std.debug.print("{s}: size does not match {d}x{d}\n", .{ path, wh[0], wh[1] });
            continue;
        }
        var best: f64 = 1e30;
        var size: usize = 0;
        var ok = true;
        for (0..9) |round| {
            fba.reset();
            const t0 = now();
            const out = try png.encode(fba.allocator(), rgba, wh[0], wh[1], .{});
            best = @min(best, now() - t0);
            size = out.len;
            if (round == 0) {
                const img = png.decode(fba.allocator(), out, .{}) catch {
                    ok = false;
                    continue;
                };
                ok = img.width == wh[0] and img.height == wh[1] and std.mem.eql(u8, img.data, rgba);
            }
        }
        const name = path[if (std.mem.lastIndexOfAny(u8, path, "/\\")) |i| i + 1 else 0..];
        std.debug.print("{s:<40} {d:>8.3} ms  {d:>9} bytes  {s}\n", .{ name, best * 1e3, size, if (ok) "round-trip ok" else "ROUND-TRIP MISMATCH" });
        total_ms += best * 1e3;
        total_bytes += size;
    }
    std.debug.print("{s:<40} {d:>8.3} ms  {d:>9} bytes\n", .{ "total", total_ms, total_bytes });
}
