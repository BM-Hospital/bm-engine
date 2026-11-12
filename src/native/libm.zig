//! floor / ceil / trunc / round / fmod for the native addon.
//!
//! Where the CPU has no instruction for them (x86-64 baseline: all of them; arm64: only fmod), LLVM
//! lowers `@floor`, `@ceil`, `@trunc`, `@round` and float `@mod` / `@rem` to calls of the C names
//! `floorf`, `floor`, ... . In a binary linked against a C library those calls would bind to the
//! platform's libm (glibc, musl, libSystem), while the wasm build and the libc-free Windows build use
//! the copies compiled into them. All five are exactly defined operations (one correct result per
//! input, no rounding freedom), so every conforming libm agrees; the addon still must not depend on
//! that: the strong, hidden definitions below are what every native target links, the same code on
//! all of them. scripts/build-native.mjs checks that no artifact imports a math function, and
//! bench/native-tests.mjs ("libm") compares these against JavaScript's exact results bit for bit.
//!
//! Plain integer bit manipulation only: nothing in here may be turned back into a libm call.
const std = @import("std");

comptime {
    for (.{
        .{ &floorf, "floorf" }, .{ &floor, "floor" }, .{ &ceilf, "ceilf" }, .{ &ceil, "ceil" },
        .{ &truncf, "truncf" }, .{ &trunc, "trunc" }, .{ &roundf, "roundf" }, .{ &round, "round" },
    }) |e| @export(e[0], .{ .name = e[1], .linkage = .strong, .visibility = .hidden });
    @export(&fmodf, .{ .name = "fmodf", .linkage = .strong, .visibility = .hidden });
    @export(&fmod, .{ .name = "fmod", .linkage = .strong, .visibility = .hidden });
}

fn floorf(x: f32) callconv(.c) f32 {
    return toIntegral(f32, .floor, x);
}
fn floor(x: f64) callconv(.c) f64 {
    return toIntegral(f64, .floor, x);
}
fn ceilf(x: f32) callconv(.c) f32 {
    return toIntegral(f32, .ceil, x);
}
fn ceil(x: f64) callconv(.c) f64 {
    return toIntegral(f64, .ceil, x);
}
fn truncf(x: f32) callconv(.c) f32 {
    return toIntegral(f32, .trunc, x);
}
fn trunc(x: f64) callconv(.c) f64 {
    return toIntegral(f64, .trunc, x);
}
fn roundf(x: f32) callconv(.c) f32 {
    return toIntegral(f32, .round, x);
}
fn round(x: f64) callconv(.c) f64 {
    return toIntegral(f64, .round, x);
}
fn fmodf(x: f32, y: f32) callconv(.c) f32 {
    return rem(f32, x, y);
}
fn fmod(x: f64, y: f64) callconv(.c) f64 {
    return rem(f64, x, y);
}

const Mode = enum { floor, ceil, trunc, round };

/// IEEE 754 roundToIntegral: toward negative (floor), toward positive (ceil), toward zero (trunc),
/// ties away from zero (round). The sign of a zero result is the sign of `x`; NaN / infinity return `x`.
pub inline fn toIntegral(comptime T: type, comptime mode: Mode, x: T) T {
    const bits = @bitSizeOf(T);
    const U = if (T == f32) u32 else u64;
    const mant = std.math.floatMantissaBits(T);
    const exp_mask: U = (1 << (bits - 1 - mant)) - 1;
    const bias: i32 = @intCast(exp_mask >> 1);
    const sign_bit: U = 1 << (bits - 1);

    const u: U = @bitCast(x);
    const negative = u & sign_bit != 0;
    const e: i32 = @as(i32, @intCast((u >> mant) & exp_mask)) - bias;
    if (e >= mant) return x; // already integral, infinite or NaN
    if (e < 0) {
        // |x| < 1: the result is a zero or a one with the sign of x
        const zero: U = u & sign_bit;
        const one: U = zero | (@as(U, @intCast(bias)) << mant);
        const is_zero = (u << 1) == 0;
        const r: U = switch (mode) {
            .trunc => zero,
            .floor => if (negative and !is_zero) one else zero,
            .ceil => if (!negative and !is_zero) one else zero,
            .round => if (e == -1) one else zero,
        };
        return @bitCast(r);
    }
    // 0 <= e < mant: the low (mant - e) bits are the fraction
    const unit: U = @as(U, 1) << @intCast(mant - e);
    const frac = u & (unit - 1);
    if (frac == 0) return x;
    var r = u - frac; // magnitude truncated
    // the next integer away from zero: adding `unit` carries into the exponent when the mantissa overflows
    const away = switch (mode) {
        .trunc => false,
        .floor => negative,
        .ceil => !negative,
        .round => frac >= unit >> 1,
    };
    if (away) r += unit;
    return @bitCast(r);
}

/// C `fmod`: x - trunc(x / y) * y computed exactly (the result has the sign of x). After musl.
pub fn rem(comptime T: type, x: T, y: T) T {
    const bits = @bitSizeOf(T);
    const U = if (T == f32) u32 else u64;
    const Shift = std.math.Log2Int(U);
    const mant = std.math.floatMantissaBits(T);
    const exp_bits = bits - 1 - mant;
    const exp_mask: U = (1 << exp_bits) - 1;
    const sign_bit: U = 1 << (bits - 1);
    const implicit: U = 1 << mant;

    var ux: U = @bitCast(x);
    var uy: U = @bitCast(y);
    var ex: i32 = @intCast((ux >> mant) & exp_mask);
    var ey: i32 = @intCast((uy >> mant) & exp_mask);
    const sx = ux & sign_bit;

    // y = 0, y = NaN, x = infinity or NaN: NaN
    if ((uy << 1) == 0 or (uy << 1) > (exp_mask << (mant + 1)) or ex == exp_mask) {
        const nan: U = (exp_mask << mant) | (implicit >> 1);
        return @bitCast(nan);
    }
    if ((ux << 1) <= (uy << 1)) {
        if ((ux << 1) == (uy << 1)) return @bitCast(sx); // |x| = |y|: zero with the sign of x
        return x; // |x| < |y|
    }

    // normalise both to "1.mantissa" with the hidden bit set
    if (ex == 0) {
        var i = ux << (exp_bits + 1);
        while (i & sign_bit == 0) : (i <<= 1) ex -= 1;
        ux <<= @as(Shift, @intCast(1 - ex));
    } else {
        ux &= implicit - 1;
        ux |= implicit;
    }
    if (ey == 0) {
        var i = uy << (exp_bits + 1);
        while (i & sign_bit == 0) : (i <<= 1) ey -= 1;
        uy <<= @as(Shift, @intCast(1 - ey));
    } else {
        uy &= implicit - 1;
        uy |= implicit;
    }

    // long division, one quotient bit per exponent step
    while (ex > ey) : (ex -= 1) {
        const i = ux -% uy;
        if (i & sign_bit == 0) {
            if (i == 0) return @bitCast(sx);
            ux = i;
        }
        ux <<= 1;
    }
    const i = ux -% uy;
    if (i & sign_bit == 0) {
        if (i == 0) return @bitCast(sx);
        ux = i;
    }
    while (ux & implicit == 0) : (ux <<= 1) ex -= 1;

    // back to the IEEE encoding (subnormal when the exponent ran out)
    if (ex > 0) {
        ux -= implicit;
        ux |= @as(U, @intCast(ex)) << mant;
    } else {
        ux >>= @as(Shift, @intCast(1 - ex));
    }
    return @bitCast(ux | sx);
}
