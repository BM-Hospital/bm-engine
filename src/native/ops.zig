//! The operation table of the native addon: THE place where a new output kind plugs in.
//!
//! The addon exposes one generic call to JavaScript (src/native.zig):
//!
//!     run(handle, op, arg0, arg1, input, options, attachments)       -> Uint8Array
//!     runAsync(handle, op, arg0, arg1, input, options, attachments)  -> Promise<Uint8Array>
//!
//! `op` is an index into `table` below (JavaScript reads the name -> index map from the addon's
//! `ops` export, so nothing is hard-coded on the JS side). The glue copies / borrows the inputs,
//! takes the renderer's lock, makes sure enough stack is available, registers the attachments as
//! image sources when the op says so (`images = true`), calls `run`, and turns the result bytes or
//! the error into a JS value / exception / rejection. An op only has to call into the engine.
//!
//! Adding an output kind (e.g. PDF): see docs/NATIVE.md. In short, add ONE entry here:
//!
//!     .{ .name = "pdf", .images = true, .run = pdf },
//!     fn pdf(c: *Call) Error!void { c.result = try c.r.?.renderPdf(sourceKind(c), c.input, c.options); }
//!
//! and the matching entry in the wasm backend + the public method in js/engine.mjs.
const std = @import("std");
const render = @import("../render.zig");
const config = @import("../config.zig");

pub const Error = render.Error;

/// A binary input passed next to the text inputs. For `images` ops: an image source registered
/// under `key` (`flags` bit 0 = raw RGBA of `width` x `height`, bit 1 = premultiplied alpha;
/// otherwise encoded bytes). Other ops give the fields their own meaning (registerFont: the file).
pub const Attachment = struct {
    key: []const u8 = "",
    data: []const u8 = "",
    flags: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
};

pub const Call = struct {
    /// The renderer (null only for ops with `renderer = false`). Locked for the duration of the call.
    r: ?*render.Renderer,
    /// General allocator: the renderer's (accounted, capped) one, or the process allocator.
    gpa: std.mem.Allocator,
    arg0: u32 = 0,
    arg1: u32 = 0,
    /// Borrowed for the duration of the call.
    input: []const u8 = "",
    options: []const u8 = "",
    attachments: []const Attachment = &.{},

    /// OUT: the result bytes. Either memory of the renderer that stays valid until its next call
    /// (the glue copies it out, then calls `releaseResult`), or, with `owned`, a `gpa` allocation
    /// the glue frees.
    result: []const u8 = "",
    owned: bool = false,
    /// OUT: message for `error.Invalid` when it is not `r.err`.
    err: []const u8 = "",

    fn fail(c: *Call, msg: []const u8) Error {
        c.err = msg;
        return error.Invalid;
    }
};

pub const Op = struct {
    name: [:0]const u8,
    run: *const fn (*Call) Error!void,
    /// Register the attachments as the call's image sources before `run` (replacing the previous ones).
    images: bool = false,
    /// Needs a renderer handle.
    renderer: bool = true,
};

pub const table = [_]Op{
    .{ .name = "render", .images = true, .run = renderOp },
    .{ .name = "measure", .images = true, .run = measureOp },
    .{ .name = "svg", .images = true, .run = svgOp },
    .{ .name = "animation", .images = true, .run = animationOp },
    .{ .name = "registerFont", .run = registerFont },
    .{ .name = "unregisterFont", .run = unregisterFont },
    .{ .name = "clearFonts", .run = clearFonts },
    .{ .name = "woffDecode", .renderer = false, .run = woffDecode },
    .{ .name = "mathProbe", .renderer = false, .run = mathProbe },
};

/// `arg0` of the source-taking ops: 0 = JSON node tree, 1 = HTML markup (as the wasm ABI).
fn sourceKind(c: *const Call) render.SourceKind {
    return if (c.arg0 == 1) .html else .json;
}

/// input = source text, options = options JSON; result = encoded image / raw RGBA.
fn renderOp(c: *Call) Error!void {
    c.result = try c.r.?.renderSource(sourceKind(c), c.input, c.options);
}

/// result = takumi `MeasuredNode` JSON.
fn measureOp(c: *Call) Error!void {
    c.result = try c.r.?.measureSource(sourceKind(c), c.input, c.options);
}

/// result = SVG document (UTF-8).
fn svgOp(c: *Call) Error!void {
    c.result = try c.r.?.renderSvg(sourceKind(c), c.input, c.options);
}

/// input = `{scenes, width, height, fps, ...}` JSON; result = encoded WebP / APNG / GIF.
fn animationOp(c: *Call) Error!void {
    c.result = try c.r.?.renderAnimation(c.input);
}

/// input = family name ("" = from the font), arg0 = weight (0 = from the font), arg1 = italic
/// (-1 as u32 = from the font, 0, 1), attachments[0].data = the font file. Result:
/// `RegisteredFamily[]` JSON.
fn registerFont(c: *Call) Error!void {
    if (c.attachments.len != 1) return c.fail("registerFont expects font bytes");
    // the renderer takes ownership of the bytes (and frees them on failure)
    const data = try c.gpa.dupe(u8, c.attachments[0].data);
    c.result = try c.r.?.registerFont(data, c.input, @intCast(@min(c.arg0, 1000)), @bitCast(c.arg1));
}

/// input = family name; result = one byte, 1 when a face was removed.
fn unregisterFont(c: *Call) Error!void {
    c.result = if (c.r.?.unregisterFont(c.input)) "\x01" else "\x00";
}

fn clearFonts(c: *Call) Error!void {
    c.r.?.clearFonts();
}

/// Test hook for src/native/libm.zig (bench/native-tests.mjs "libm"): applies the rounding builtin
/// `arg0` (0 floor, 1 ceil, 2 trunc, 3 round, 4 x mod y as `@rem`) to the f32 (`arg1` = 0) or f64
/// (`arg1` = 1) values in attachments[0].data (pairs for 4) and returns the results. The builtins
/// compile to the instructions / runtime calls the engine itself uses on this target.
fn mathProbe(c: *Call) Error!void {
    if (c.attachments.len != 1) return c.fail("mathProbe expects one buffer");
    const in = c.attachments[0].data;
    const out = try c.gpa.alloc(u8, in.len);
    c.result = out;
    c.owned = true;
    inline for (.{ f32, f64 }, 0..) |T, ti| {
        if (c.arg1 == ti) {
            const n = in.len / @sizeOf(T);
            const U = if (T == f32) u32 else u64;
            var i: usize = 0;
            while (i < n) : (i += 1) {
                const x: T = @bitCast(std.mem.readInt(U, in[i * @sizeOf(T) ..][0..@sizeOf(T)], .little));
                var y: T = 0;
                if (c.arg0 == 4) {
                    if (i + 1 < n) y = @bitCast(std.mem.readInt(U, in[(i + 1) * @sizeOf(T) ..][0..@sizeOf(T)], .little));
                }
                const v: T = switch (c.arg0) {
                    0 => @floor(x),
                    1 => @ceil(x),
                    2 => @trunc(x),
                    3 => @round(x),
                    else => if (y != 0 and y == y and x == x and !std.math.isInf(x)) @rem(x, y) else 0,
                };
                std.mem.writeInt(U, out[i * @sizeOf(T) ..][0..@sizeOf(T)], @bitCast(v), .little);
            }
        }
    }
}

/// attachments[0].data = a WOFF / WOFF2 file; result = the sfnt (same decoder as bm_woff.wasm).
fn woffDecode(c: *Call) Error!void {
    if (comptime !config.enable_woff) return c.fail("WOFF/WOFF2 fonts are not supported by this build");
    const woff = @import("../woff/woff.zig");
    if (c.attachments.len != 1) return c.fail("invalid WOFF/WOFF2 font data");
    const bytes = c.attachments[0].data;
    switch (woff.sniff(bytes)) {
        .woff, .woff2 => {},
        else => return c.fail("invalid WOFF/WOFF2 font data"),
    }
    c.result = woff.decode(c.gpa, bytes) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return c.fail("invalid WOFF/WOFF2 font data");
    };
    c.owned = true;
}
