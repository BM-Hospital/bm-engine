//! Compact f64 math for colour-space conversion (no libm): ln/exp/pow, sin/cos/atan2 in degrees.
//! Accurate to ~1e-12 relative over the ranges colour conversion uses, which is far below the
//! 1/510 needed for 8-bit rounding. Inputs are sanitised (NaN/inf never loop or trap).
const std = @import("std");

const ln2: f64 = 0.6931471805599453;
const pi: f64 = 3.141592653589793;

/// Natural log; returns -inf-ish (-1e300) for x <= 0 and NaN-safe.
pub fn ln(x: f64) f64 {
    if (!(x > 0)) return -1.0e300;
    if (x > 1.0e300) return 690.8;
    var bits: u64 = @bitCast(x);
    var e: i32 = @as(i32, @intCast((bits >> 52) & 0x7ff)) - 1023;
    if (e == -1023) { // subnormal: scale up
        const y = x * 4503599627370496.0; // 2^52
        bits = @bitCast(y);
        e = @as(i32, @intCast((bits >> 52) & 0x7ff)) - 1023 - 52;
    }
    var m: f64 = @bitCast((bits & 0x000fffffffffffff) | 0x3ff0000000000000);
    if (m > 1.4142135623730951) {
        m *= 0.5;
        e += 1;
    }
    const s = (m - 1) / (m + 1);
    const s2 = s * s;
    // 2s(1 + s²/3 + s⁴/5 + ... + s¹⁴/15)
    var p: f64 = 1.0 / 15.0;
    var k: f64 = 13;
    while (k >= 1) : (k -= 2) p = p * s2 + 1.0 / k;
    return 2 * s * p + @as(f64, @floatFromInt(e)) * ln2;
}

/// e^x, clamped to x in [-700, 700].
pub fn exp(x0: f64) f64 {
    if (x0 != x0) return 0;
    const x = std.math.clamp(x0, -700, 700);
    const kf = @round(x / ln2);
    const r = x - kf * ln2;
    // Taylor to r^13 (|r| <= 0.347)
    var p: f64 = 1;
    var i: f64 = 13;
    while (i >= 1) : (i -= 1) p = 1 + p * r / i;
    const k: i64 = @intFromFloat(kf);
    const scale: f64 = @bitCast(@as(u64, @intCast(k + 1023)) << 52);
    return p * scale;
}

/// x^y for x >= 0 (0 for x <= 0).
pub noinline fn pow(x: f64, y: f64) f64 {
    if (!(x > 0)) return 0;
    return exp(y * ln(x));
}

/// Sign-preserving |x|^y.
pub fn spow(x: f64, y: f64) f64 {
    return if (x < 0) -pow(-x, y) else pow(x, y);
}

/// Cube root (sign-preserving).
pub fn cbrt(x: f64) f64 {
    return spow(x, 1.0 / 3.0);
}

/// sin and cos of an angle in DEGREES.
pub noinline fn sinCosDeg(deg0: f64) [2]f64 {
    var deg = deg0;
    if (!(@abs(deg) < 1.0e15)) deg = 0;
    deg -= 360 * @floor(deg / 360);
    const q = @round(deg / 90);
    const r = (deg - q * 90) * (pi / 180); // |r| <= pi/4
    const r2 = r * r;
    // sin r, cos r by Taylor (to r^15 / r^14)
    var sp: f64 = 1;
    var cp: f64 = 1;
    var n: f64 = 14;
    while (n >= 2) : (n -= 2) {
        sp = 1 - sp * r2 / ((n + 1) * n);
        cp = 1 - cp * r2 / (n * (n - 1));
    }
    const s = r * sp;
    const c = cp;
    const qi: u32 = @as(u32, @intFromFloat(q)) & 3;
    return switch (qi) {
        0 => .{ s, c },
        1 => .{ c, -s },
        2 => .{ -s, -c },
        else => .{ -c, s },
    };
}

/// atan of z in [0, 1], radians.
fn atan01(z: f64) f64 {
    var w = z;
    var base: f64 = 0;
    if (w > 0.4142135623730950) {
        w = (w - 1) / (w + 1);
        base = pi / 4;
    }
    // further halve: atan(w) = 2 atan(w / (1 + sqrt(1 + w²)))
    const h = w / (1 + @sqrt(1 + w * w));
    const h2 = h * h;
    var p: f64 = 0;
    var k: f64 = 21;
    while (k >= 1) : (k -= 2) p = 1.0 / k - h2 * p;
    return base + 2 * h * p;
}

/// atan2(y, x) in DEGREES, range (-180, 180].
pub noinline fn atan2Deg(y: f64, x: f64) f64 {
    if (y != y or x != x) return 0;
    const ax = @abs(x);
    const ay = @abs(y);
    if (ax == 0 and ay == 0) return 0;
    var a: f64 = if (ay <= ax) atan01(ay / ax) else pi / 2 - atan01(ax / ay);
    if (x < 0) a = pi - a;
    if (y < 0) a = -a;
    return a * (180 / pi);
}

test "cmath accuracy" {
    const T = std.testing;
    var x: f64 = 0.0001;
    while (x < 50) : (x *= 1.37) {
        try T.expectApproxEqRel(@log(x), ln(x), 1e-12);
        try T.expectApproxEqRel(std.math.pow(f64, x, 2.4), pow(x, 2.4), 1e-11);
        try T.expectApproxEqRel(std.math.cbrt(x), cbrt(x), 1e-11);
        try T.expectApproxEqRel(@exp(-x), exp(-x), 1e-11);
    }
    var d: f64 = -720;
    while (d < 720) : (d += 7.3) {
        const sc = sinCosDeg(d);
        try T.expectApproxEqAbs(@sin(d * pi / 180), sc[0], 1e-13);
        try T.expectApproxEqAbs(@cos(d * pi / 180), sc[1], 1e-13);
        const y = sc[0] * 3;
        const xx = sc[1] * 3;
        try T.expectApproxEqAbs(std.math.atan2(y, xx) * 180 / pi, atan2Deg(y, xx), 1e-10);
    }
    try T.expectEqual(@as(f64, 0), pow(0, 2));
}
