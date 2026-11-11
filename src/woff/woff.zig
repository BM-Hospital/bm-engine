//! WOFF 1.0 / WOFF 2.0 -> sfnt converter.
//!
//! Entry points: `sniff` (format detection, no allocation) and `decode` (WOFF/WOFF2 -> plain
//! sfnt bytes: TrueType or CFF flavoured, or a TTC for WOFF2 collections). Includes a complete
//! brotli decoder (`brotli.zig`, RFC 7932 incl. the static dictionary) for WOFF2 and uses
//! `codec/inflate.zig` for WOFF1's zlib streams.
//!
//! Untrusted input: every offset/length is validated, output is capped at `max_output` (and at
//! 1.5x the header's declared totalSfntSize + 64 KiB), memory is bounded (output + decompressed
//! stream + reconstruction temporaries), no recursion.
//!
//! Allocation: `alloc` receives the result (caller owns it, free with the same allocator) and
//! temporaries, which are allocated before the result and freed before returning. A long-lived
//! allocator is the natural choice since the result typically becomes registered font data.
const std = @import("std");
pub const brotli = @import("brotli.zig");
const woff1 = @import("woff1.zig");
const woff2 = @import("woff2.zig");
const sfnt = @import("sfnt.zig");

pub const Kind = enum { sfnt, woff, woff2, unknown };

pub const Error = error{
    /// Malformed or inconsistent input.
    InvalidData,
    /// Not a WOFF/WOFF2 file (plain sfnt or unknown data).
    UnsupportedFormat,
    /// The decoded font would exceed the output cap.
    OutputTooLarge,
    OutOfMemory,
};

/// Hard cap on the decoded font size (and on WOFF2's decompressed table stream).
pub const max_output: usize = 64 << 20;

/// Classifies font bytes by their magic number.
pub fn sniff(bytes: []const u8) Kind {
    if (bytes.len < 4) return .unknown;
    return switch (sfnt.rd32(bytes, 0)) {
        sfnt.tag("wOFF") => .woff,
        sfnt.tag("wOF2") => .woff2,
        0x00010000, sfnt.tag("true"), sfnt.tag("OTTO"), sfnt.tag("ttcf"), sfnt.tag("typ1") => .sfnt,
        else => .unknown,
    };
}

/// Returns plain sfnt bytes (TrueType/CFF, or a TTC for WOFF2 collections) allocated from
/// `alloc`. Fails with `error.UnsupportedFormat` for anything that is not WOFF/WOFF2.
pub fn decode(alloc: std.mem.Allocator, bytes: []const u8) Error![]u8 {
    return switch (sniff(bytes)) {
        .woff => woff1.decode(alloc, bytes, max_output),
        .woff2 => woff2.decode(alloc, bytes, max_output),
        .sfnt, .unknown => error.UnsupportedFormat,
    };
}
