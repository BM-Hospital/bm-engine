//! measure() transforms and number printing, mirroring takumi exactly:
//! - `local(cs, w, h)` = takumi `style.local_transform` (stylesheets_query.rs): T(origin) * T(translate)
//!   * rotation(rotate) * scale(scale) * (transform list composed left to right) * T(-origin), each
//!   product with takumi's `Affine * Affine` (a factor within 1e-6 of the identity with no translation
//!   is skipped), rotations exact at quarter turns (`Affine::rotation`), skew via tan of f32 radians.
//! - a node's measured transform = (parent's * T(location)) * local.
//! - `writeExact` prints the f32 exactly (JSON.parse gives the same double as takumi's f32 output).
//! Trig uses an f64 polynomial (no libm); its f32 results equal libm's correctly rounded ones except
//! for values within ~1e-10 of a rounding boundary.
const std = @import("std");
const raster = @import("raster/raster.zig");
const style = @import("style/style.zig");

pub const Affine = raster.Affine;
const CS = style.ComputedStyle;

fn nearIdentity(m: Affine) bool {
    return m.e == 0 and m.f == 0 and @abs(m.a - 1) < 1e-6 and @abs(m.b) < 1e-6 and @abs(m.c) < 1e-6 and @abs(m.d - 1) < 1e-6;
}

/// takumi `impl Mul for Affine`.
pub fn mul(x: Affine, y: Affine) Affine {
    if (nearIdentity(x)) return y;
    if (nearIdentity(y)) return x;
    return x.mul(y);
}

/// Rust `f32::to_radians` (f32 product with the f32 constant PI / 180).
fn toRadians(deg: f32) f32 {
    const rads_per_deg: f32 = @as(f32, std.math.pi) / @as(f32, 180.0);
    return deg * rads_per_deg;
}

/// sin / cos of an f32 angle, in f64 (reduction by pi/2, Taylor series; |error| < 1e-15 for |x| < 1e6).
fn sinCos64(rad: f32) [2]f64 {
    if (!std.math.isFinite(rad)) return .{ std.math.nan(f64), std.math.nan(f64) };
    const x: f64 = rad;
    const q = @floor(x * (2.0 / std.math.pi) + 0.5);
    // pi/2 split in two parts so the reduction stays exact for large q
    const r = (x - q * 1.5707963267341256) - q * 6.077100506506192e-11;
    const r2 = r * r;
    const s = r * (1.0 + r2 * (-1.0 / 6.0 + r2 * (1.0 / 120.0 + r2 * (-1.0 / 5040.0 + r2 * (1.0 / 362880.0 + r2 * (-1.0 / 39916800.0 + r2 * (1.0 / 6227020800.0)))))));
    const c = 1.0 + r2 * (-0.5 + r2 * (1.0 / 24.0 + r2 * (-1.0 / 720.0 + r2 * (1.0 / 40320.0 + r2 * (-1.0 / 3628800.0 + r2 * (1.0 / 479001600.0 + r2 * (-1.0 / 87178291200.0)))))));
    const qm = q - 4.0 * @floor(q * 0.25);
    if (!(qm >= 0 and qm < 4)) return .{ std.math.nan(f64), std.math.nan(f64) };
    const quadrant: u32 = @intFromFloat(qm);
    return switch (quadrant) {
        0 => .{ s, c },
        1 => .{ c, -s },
        2 => .{ -s, -c },
        else => .{ -c, s },
    };
}

/// takumi `Angle::new`: degrees normalised with `rem_euclid(360)` (f32).
fn angle(v: f32) f32 {
    if (!std.math.isFinite(v)) return v;
    const r = @rem(v, 360.0);
    return if (r < 0) r + 360.0 else r;
}

/// takumi `Affine::rotation(angle)` (degrees, normalised first; exact at whole quarter turns).
pub fn rotation(deg_in: f32) Affine {
    const deg = angle(deg_in);
    const qt = deg / 90.0;
    var s: f32 = 0;
    var c: f32 = 1;
    if (qt - @trunc(qt) != 0 or !std.math.isFinite(qt)) {
        const sc = sinCos64(toRadians(deg));
        s = @floatCast(sc[0]);
        c = @floatCast(sc[1]);
    } else {
        // qt is a whole number in [0, 4] here (deg is in [0, 360]); integer arithmetic keeps LLVM from
        // expanding a float remainder into a fused multiply-subtract on aarch64.
        const k: u8 = if (qt >= 0 and qt <= 4) @intCast(@as(u32, @intFromFloat(qt)) % 4) else 0;
        switch (k) {
            0 => {},
            1 => {
                s = 1;
                c = 0;
            },
            2 => c = -1,
            else => {
                s = -1;
                c = 0;
            },
        }
    }
    return .{ .a = c, .b = s, .c = -s, .d = c };
}

fn tanDeg(deg: f32) f32 {
    const sc = sinCos64(toRadians(angle(deg)));
    return @floatCast(sc[0] / sc[1]);
}

/// takumi `Affine::skew(x, y)` (degrees).
pub fn skew(x: f32, y: f32) Affine {
    return .{ .b = tanDeg(y), .c = tanDeg(x) };
}

/// takumi `ComputedStyle::local_transform(width, height)` relative to the border box origin
/// (identity when the element is not transformed).
pub fn local(cs: *const CS, w: f32, h: f32) Affine {
    const ox = cs.transform_origin[0].resolve(w);
    const oy = cs.transform_origin[1].resolve(h);
    var m = Affine.translate(ox, oy);
    const tx = cs.translate[0].resolve(w);
    const ty = cs.translate[1].resolve(h);
    if (tx != 0 or ty != 0) m = mul(m, Affine.translate(tx, ty));
    if (cs.rotate != 0) m = mul(m, rotation(cs.rotate));
    if (cs.scale[0] != 1 or cs.scale[1] != 1) m = mul(m, Affine.scale(cs.scale[0], cs.scale[1]));
    if (cs.transform.len > 0) {
        var list: Affine = .{};
        for (cs.transform) |op| {
            list = mul(list, switch (op) {
                .translate => |v| Affine.translate(v[0].resolve(w), v[1].resolve(h)),
                .scale => |v| Affine.scale(v[0], v[1]),
                .rotate => |deg| rotation(deg),
                .skew => |v| skew(v[0], v[1]),
                .matrix => |v| Affine{ .a = v[0], .b = v[1], .c = v[2], .d = v[3], .e = v[4], .f = v[5] },
            });
        }
        m = mul(m, list);
    }
    return mul(m, Affine.translate(-ox, -oy));
}

const pow5_44: u128 = blk: {
    var p: u128 = 1;
    for (0..44) |_| p *= 5;
    break :blk p;
};

/// Prints `v` (an f32) as the exact decimal value of the float (non-finite / |v| > 1e15 -> 0; below
/// 2^-21 rounded to 44 fraction digits), so JSON.parse yields exactly `(double)v`.
pub fn writeExact(a: std.mem.Allocator, out: *std.ArrayList(u8), v_in: f32) error{OutOfMemory}!void {
    var v = v_in;
    if (!std.math.isFinite(v) or @abs(v) > 1.0e15) v = 0;
    const bits: u32 = @bitCast(v);
    if (bits >> 31 != 0 and v != 0) try out.append(a, '-');
    const exp_bits: i32 = @intCast((bits >> 23) & 0xff);
    var mant: u128 = bits & 0x7f_ffff;
    var e: i32 = exp_bits - 150;
    if (exp_bits == 0) {
        e = -149;
    } else mant |= 0x80_0000;
    // value = mant * 2^e ; N = value * 10^k (exact up to k = 44)
    var n: u128 = undefined;
    var k: u32 = 0;
    if (mant == 0) {
        n = 0;
    } else if (e >= 0) {
        n = mant << @intCast(e); // |v| <= 1e15: fits
    } else {
        const ne: u32 = @intCast(-e);
        if (ne <= 44) {
            var p: u128 = 1;
            for (0..ne) |_| p *= 5;
            n = mant * p;
            k = ne;
        } else {
            const sh: u32 = ne - 44;
            const full = mant * pow5_44; // < 2^24 * 2^103
            n = if (sh >= 127) 0 else (full + (@as(u128, 1) << @intCast(sh - 1))) >> @intCast(sh);
            k = 44;
        }
    }
    // trim trailing zero fraction digits
    while (k > 0 and n % 10 == 0) {
        n /= 10;
        k -= 1;
    }
    var buf: [48]u8 = undefined;
    var i: usize = buf.len;
    var digits: u32 = 0;
    while (true) {
        i -= 1;
        buf[i] = @intCast('0' + @as(u8, @intCast(n % 10)));
        n /= 10;
        digits += 1;
        if (digits == k) {
            i -= 1;
            buf[i] = '.';
            if (n == 0) {
                i -= 1;
                buf[i] = '0';
                break;
            }
        }
        if (n == 0 and digits >= k) break;
    }
    try out.appendSlice(a, buf[i..]);
}

test "writeExact prints the float's exact value" {
    const a = std.testing.allocator;
    const cases = [_]struct { f32, []const u8 }{
        .{ 0, "0" },             .{ 1, "1" },                    .{ -7, "-7" },
        .{ 0.5, "0.5" },         .{ 8.984375, "8.984375" },      .{ 132, "132" },
        .{ -0.25, "-0.25" },     .{ 0.1, "0.100000001490116119384765625" },
        .{ 1.0e-8, "0.00000000999999993922529029077850282192230224609375" },
    };
    for (cases) |cse| {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(a);
        try writeExact(a, &out, cse[0]);
        if (cse[0] == 1.0e-8) {
            // beyond 44 fraction digits: rounded, still parses back to the same f32 / f64
            const parsed = try std.fmt.parseFloat(f64, out.items);
            try std.testing.expectEqual(@as(f64, cse[0]), parsed);
        } else try std.testing.expectEqualStrings(cse[1], out.items);
    }
    // 0.866... = f32 cos(30deg): exact double digits
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    try writeExact(a, &out, 0.8660253882408142);
    try std.testing.expectEqual(@as(f64, @as(f32, 0.8660253882408142)), try std.fmt.parseFloat(f64, out.items));
}

test "rotation is exact at quarter turns and matches libm elsewhere" {
    try std.testing.expectEqual(Affine{ .a = 0, .b = 1, .c = -1, .d = 0 }, rotation(90));
    try std.testing.expectEqual(Affine{ .a = -1, .b = 0, .c = 0, .d = -1 }, rotation(-180));
    try std.testing.expectEqual(Affine{ .a = 0, .b = -1, .c = 1, .d = 0 }, rotation(630));
    const r30 = rotation(30);
    try std.testing.expectEqual(@as(f32, 0.8660253882408142), r30.a); // takumi (Rust f32 sin_cos)
    try std.testing.expectEqual(@as(f32, 0.5), r30.b);
    const r10 = rotation(10);
    try std.testing.expectEqual(@as(f32, 0.9848077297210693), r10.a);
    try std.testing.expectEqual(@as(f32, 0.1736481785774231), r10.b);
    // non-finite input never traps
    _ = rotation(std.math.inf(f32));
    _ = rotation(std.math.nan(f32));
    _ = skew(90, std.math.inf(f32));
}
