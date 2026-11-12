//! CSS animations sampled at one point of the timeline (takumi `timeMs`), mirroring takumi-core
//! `style/animation.rs` (`apply_stylesheet_animations`, `sample_animation_progress`,
//! `sample_keyframe_segment`, `resolve_keyframes`) and `properties/animation.rs` (`steps_sample`).
//!
//! takumi semantics (verified in the source, takumi 2.20):
//! - The render time is an integer number of ms (`u64`, default 0): animations ARE applied at
//!   t = 0 when `timeMs` is absent (so `fill-mode: backwards` / a 0% keyframe show at t = 0).
//! - Per animation: active time = t - delay. Before the start only `backwards`/`both` fill
//!   (progress = start of the first iteration, "before" flag set for step easings). Zero duration:
//!   end of the first iteration. Past the active duration only `forwards`/`both` fill; the end
//!   state of a fractional iteration count is that fraction of the last iteration. At an exact
//!   iteration boundary inside the active phase the progress is 1.0 of the previous iteration.
//! - `animation-play-state` is ignored (paused animations still sample at t), like takumi.
//! - Keyframe points are sorted by offset (stable); equal offsets merge (later declarations win).
//!   Each keyframe style = the element's computed style + the keyframe's declarations (which beat
//!   every other origin, `!important` included). Missing 0% / 100% keyframes: the segment runs
//!   from / to the element's own (pre-animation) style, animating only the properties the
//!   keyframe sets.
//! - The ANIMATION's timing function eases each segment's local progress (takumi ignores a
//!   per-keyframe `animation-timing-function`).
//! - Several animations apply in `animation-name` order onto the same style, each sampled
//!   against the pre-animation style; a later one wins for the properties it animates.
//! - Unknown names fall back to Tailwind's built-in `spin` / `ping` / `pulse` / `bounce`.
//! - Not modelled: animated custom properties (takumi re-cascades `var()` users), `@keyframes`
//!   media gates (handled by the css module), animations on `::before` / `::after`.
const std = @import("std");
const style = @import("style/style.zig");
const css = @import("css/css.zig");

const CS = style.ComputedStyle;
const Prop = style.Prop;
const TF = style.TimingFunction;
const Allocator = std.mem.Allocator;
const eps = std.math.floatEps(f32);

pub const Direction = style.computed.AnimDirection;
pub const FillMode = style.computed.FillMode;

/// One sampled point of an animation timeline.
pub const Sample = struct {
    /// Progress through the current iteration, direction applied (0..1).
    progress: f32,
    /// Sampled from before the active phase (step easings take the lower step on a jump).
    before: bool = false,
};

fn applyDirection(p: f32, dir: Direction, iteration: u64) f32 {
    const even = iteration % 2 == 0;
    return switch (dir) {
        .normal => p,
        .reverse => 1 - p,
        .alternate => if (even) p else 1 - p,
        .alternate_reverse => if (even) 1 - p else p,
    };
}

fn toIter(x: f32) u64 {
    if (!(x > 0)) return 0;
    if (x >= 1.0e18) return std.math.maxInt(u64) / 2;
    return @intFromFloat(x);
}

/// takumi `sample_animation_progress`. `iterations` = inf for `infinite`. null = no effect.
pub fn sampleProgress(time_ms: f32, duration_ms: f32, delay_ms: f32, iterations: f32, dir: Direction, fill: FillMode) ?Sample {
    const active = time_ms - delay_ms;
    if (!(active >= 0)) {
        if (active != active) return null;
        return switch (fill) {
            .backwards, .both => .{ .progress = applyDirection(0, dir, 0), .before = true },
            else => null,
        };
    }
    if (!(duration_ms > 0)) return .{ .progress = applyDirection(1, dir, 0) };
    const count = if (iterations != iterations) 1 else @max(iterations, 0);
    const total = if (std.math.isInf(count)) std.math.inf(f32) else duration_ms * count;
    if (active >= total) {
        return switch (fill) {
            .forwards, .both => blk: {
                if (std.math.isInf(count)) break :blk .{ .progress = applyDirection(1, dir, 0) };
                const done = @floor(count);
                const frac = count - done;
                if (frac > eps) break :blk .{ .progress = applyDirection(frac, dir, toIter(done)) };
                break :blk .{ .progress = applyDirection(1, dir, toIter(@max(count, 1)) - 1) };
            },
            else => null,
        };
    }
    const within = active / duration_ms;
    const fl = @floor(within);
    var iteration = toIter(fl);
    var p = within - fl;
    if (active > 0 and @abs(p) <= eps) {
        p = 1;
        iteration -|= 1;
    }
    return .{ .progress = applyDirection(p, dir, iteration) };
}

/// takumi `AnimationTimingFunction::apply(progress, before)`.
pub fn ease(tf: TF, p: f32, before: bool) f32 {
    switch (tf) {
        .steps => |s| if (before) {
            const n: f32 = @floatFromInt(@max(s.n, 1));
            const q = std.math.clamp(p, 0, 1);
            const jumps: f32, const off: f32 = switch (s.pos) {
                .jump_start => .{ n, 1 },
                .jump_end => .{ n, 0 },
                .jump_both => .{ n + 1, 1 },
                .jump_none => .{ @max(n - 1, 1), 0 },
            };
            const scaled = q * n;
            var cur = @floor(scaled + off);
            if (scaled - @floor(scaled) == 0) cur -= 1;
            return std.math.clamp(cur, 0, jumps) / jumps;
        },
        else => {},
    }
    return style.interp.easing(tf, p);
}

/// A merged keyframe point: offset + the keyframes (indices into the rule) applied at it, in order.
pub const Point = struct { offset: f32, first: u32, count: u32 };

/// Segment of the keyframe list containing a progress. `from` / `to` = point index, or null for
/// the element's own style; `mask_from` / `mask_to` = whose declarations make up the animated set.
pub const Segment = struct { from: ?u32, to: ?u32, t: f32 };

/// takumi `resolve_keyframes`: points sorted by offset (stable) with equal offsets merged.
/// `order` receives the keyframe indices in point order (len = frames.len).
pub fn resolvePoints(a: Allocator, frames: []const css.Keyframe) Allocator.Error!struct { points: []Point, order: []u32 } {
    const order = try a.alloc(u32, frames.len);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    // stable insertion sort by offset
    var i: usize = 1;
    while (i < order.len) : (i += 1) {
        const x = order[i];
        var j = i;
        while (j > 0 and frames[order[j - 1]].offset > frames[x].offset) : (j -= 1) order[j] = order[j - 1];
        order[j] = x;
    }
    const points = try a.alloc(Point, frames.len);
    var n: usize = 0;
    for (order, 0..) |k, idx| {
        const off = frames[k].offset;
        if (n > 0 and @abs(points[n - 1].offset - off) <= eps) {
            points[n - 1].count += 1;
            continue;
        }
        points[n] = .{ .offset = off, .first = @intCast(idx), .count = 1 };
        n += 1;
    }
    return .{ .points = points[0..n], .order = order };
}

/// takumi `sample_keyframe_segment`.
pub fn segment(points: []const Point, progress: f32) ?Segment {
    if (points.len == 0) return null;
    const first = points[0];
    if (progress < first.offset) {
        const t = if (first.offset <= 0) 1 else progress / first.offset;
        return .{ .from = null, .to = 0, .t = std.math.clamp(t, 0, 1) };
    }
    var i: usize = 0;
    while (i + 1 < points.len) : (i += 1) {
        const s = points[i];
        const e = points[i + 1];
        if (progress <= e.offset) {
            const w = e.offset - s.offset;
            const t = if (w <= eps) 1 else (progress - s.offset) / w;
            return .{ .from = @intCast(i), .to = @intCast(i + 1), .t = std.math.clamp(t, 0, 1) };
        }
    }
    const last = points[points.len - 1];
    const t = if (last.offset >= 1) 1 else (progress - last.offset) / (1 - last.offset);
    return .{ .from = @intCast(points.len - 1), .to = null, .t = std.math.clamp(t, 0, 1) };
}

// ---- Tailwind built-ins (takumi `tailwind_animation_keyframes`)

fn kf(comptime offset: f32, comptime decls: []const css.Declaration) css.Keyframe {
    return .{ .offset = offset, .declarations = decls };
}
const spin = [_]css.Keyframe{
    kf(0.25, &.{.{ .name = "rotate", .value = "90deg" }}),
    kf(0.5, &.{.{ .name = "rotate", .value = "180deg" }}),
    kf(0.75, &.{.{ .name = "rotate", .value = "270deg" }}),
    kf(1, &.{.{ .name = "rotate", .value = "359.999deg" }}),
};
const ping_decls = [_]css.Declaration{ .{ .name = "scale", .value = "2" }, .{ .name = "opacity", .value = "0" } };
const ping = [_]css.Keyframe{ kf(0.75, &ping_decls), kf(1, &ping_decls) };
const pulse = [_]css.Keyframe{kf(0.5, &.{.{ .name = "opacity", .value = "0.5" }})};
const bounce_up = [_]css.Declaration{.{ .name = "translate", .value = "0px -25%" }};
const bounce = [_]css.Keyframe{ kf(0, &bounce_up), kf(0.5, &.{.{ .name = "translate", .value = "0px 0%" }}), kf(1, &bounce_up) };

pub fn builtinKeyframes(name: []const u8) ?[]const css.Keyframe {
    if (std.ascii.eqlIgnoreCase(name, "spin")) return &spin;
    if (std.ascii.eqlIgnoreCase(name, "ping")) return &ping;
    if (std.ascii.eqlIgnoreCase(name, "pulse")) return &pulse;
    if (std.ascii.eqlIgnoreCase(name, "bounce")) return &bounce;
    return null;
}

// ---- applying animations to a computed style

fn animatable(name: []const u8) ?Prop {
    if (name.len > 2 and name[0] == '-' and name[1] == '-') return null;
    if (std.ascii.startsWithIgnoreCase(name, "animation")) return null;
    return style.propertyId(name);
}

/// Animated style of an element at `time_ms`, or null when no animation has an effect.
/// `host` provides:
///   `fn keyframes(host, name) ?[]const css.Keyframe` (stylesheet / `keyframes` option lookup) and
///   `fn keyframeStyle(host, decls: []const style.Declaration) !*const CS` (the element's style
///   recomputed with `decls` as a top layer that beats every other origin).
/// Everything is allocated in `a` (the per-render arena).
pub fn apply(a: Allocator, base: *const CS, time_ms: f32, host: anytype) !?*CS {
    if (base.animation_name.len == 0) return null;
    var out: ?*CS = null;
    // every animated property (union over the animations)
    var all: std.ArrayList(Prop) = .empty;
    const t = @floor(@max(time_ms, 0));
    for (0..base.animation_name.len) |i| {
        const an = base.animation(i);
        if (an.name.len == 0 or std.ascii.eqlIgnoreCase(an.name, "none")) continue;
        const frames = host.keyframes(an.name) orelse builtinKeyframes(an.name) orelse continue;
        if (frames.len == 0) continue;
        const sample = sampleProgress(t, an.duration_ms, an.delay_ms, an.iteration_count, an.direction, an.fill_mode) orelse continue;
        const res = try resolvePoints(a, frames);
        const seg = segment(res.points, sample.progress) orelse continue;
        // endpoint styles + the animated property set (mask of the keyframe points involved)
        var mask: std.ArrayList(Prop) = .empty;
        const from = if (seg.from) |p| try pointStyle(a, frames, res, p, &mask, host) else base;
        const to = if (seg.to) |p| try pointStyle(a, frames, res, p, &mask, host) else base;
        if (mask.items.len == 0) continue;
        const eased = ease(an.timing, seg.t, sample.before);
        const r = try style.interp.interpolate(a, from, to, eased, mask.items);
        const acc = out orelse blk: {
            const c = try a.create(CS);
            c.* = base.*;
            out = c;
            break :blk c;
        };
        for (mask.items) |p| {
            style.props.copyProp(p, acc, &r);
            if (std.mem.indexOfScalar(Prop, all.items, p) == null) try all.append(a, p);
        }
    }
    // An animated font-size is the element's font size for its own em lengths too (takumi keeps
    // lengths specified and resolves them against the animated font size): recompute the
    // element's style with it, then put the animated values back on top.
    if (out) |o| if (std.mem.indexOfScalar(Prop, all.items, .fontSize) != null and o.font_size != base.font_size) {
        if (comptime @hasDecl(@TypeOf(host), "fontSizeStyle")) {
            const re = try host.fontSizeStyle(o.font_size);
            const c = try a.create(CS);
            c.* = re.*;
            for (all.items) |p| style.props.copyProp(p, c, o);
            return c;
        }
    };
    return out;
}

noinline fn pointStyle(a: Allocator, frames: []const css.Keyframe, res: anytype, pi: u32, mask: *std.ArrayList(Prop), host: anytype) !*const CS {
    const pt = res.points[pi];
    var n: usize = 0;
    for (res.order[pt.first..][0..pt.count]) |k| n += frames[k].declarations.len;
    const decls = try a.alloc(style.Declaration, n);
    n = 0;
    for (res.order[pt.first..][0..pt.count]) |k| for (frames[k].declarations) |d| {
        // keyframe declarations beat every origin (takumi applies them onto the computed style)
        decls[n] = .{ .name = d.name, .value = d.value, .important = true };
        n += 1;
        const p = animatable(d.name) orelse continue;
        if (std.mem.indexOfScalar(Prop, mask.items, p) == null) try mask.append(a, p);
    };
    return host.keyframeStyle(decls);
}

// ------------------------------------------------------------------------------------------------
// tests

const T = std.testing;

fn expectSample(want: ?f32, want_before: bool, got: ?Sample) !void {
    if (want == null) return T.expect(got == null);
    try T.expect(got != null);
    try T.expectApproxEqAbs(want.?, got.?.progress, 1e-5);
    try T.expectEqual(want_before, got.?.before);
}

test "sampleProgress: delay, fill, iterations, direction (takumi vectors)" {
    const inf = std.math.inf(f32);
    // takumi tests
    try expectSample(0, true, sampleProgress(0, 1000, 500, 1, .normal, .backwards));
    try expectSample(1, false, sampleProgress(1000, 1000, 0, inf, .alternate, .both));
    try expectSample(0, false, sampleProgress(2000, 1000, 0, 2, .alternate, .forwards));
    try expectSample(0.5, false, sampleProgress(1500, 1000, 0, 1.5, .normal, .forwards));
    try expectSample(1, false, sampleProgress(1000, 1000, 0, 1, .normal, .forwards));
    // delay without backwards fill: nothing
    try expectSample(null, false, sampleProgress(100, 1000, 500, 1, .normal, .none));
    try expectSample(null, false, sampleProgress(100, 1000, 500, 1, .normal, .forwards));
    try expectSample(1, true, sampleProgress(100, 1000, 500, 1, .reverse, .both));
    // after the end without forwards fill: nothing
    try expectSample(null, false, sampleProgress(1500, 1000, 0, 1, .normal, .none));
    try expectSample(null, false, sampleProgress(1500, 1000, 0, 1, .normal, .backwards));
    // active phase
    try expectSample(0.25, false, sampleProgress(250, 1000, 0, 1, .normal, .none));
    try expectSample(0.75, false, sampleProgress(250, 1000, 0, 1, .reverse, .none));
    try expectSample(0.75, false, sampleProgress(1250, 1000, 0, 3, .alternate, .none)); // 2nd iteration reversed
    try expectSample(0.25, false, sampleProgress(2250, 1000, 0, 3, .alternate, .none));
    try expectSample(0.75, false, sampleProgress(250, 1000, 0, 3, .alternate_reverse, .none));
    try expectSample(0.25, false, sampleProgress(1250, 1000, 0, 3, .alternate_reverse, .none));
    try expectSample(0.25, false, sampleProgress(700, 400, 200, inf, .normal, .none));
    try expectSample(0, false, sampleProgress(0, 1000, 0, 1, .normal, .none));
    // zero duration: end of the first iteration
    try expectSample(1, false, sampleProgress(0, 0, 0, 1, .normal, .none));
    try expectSample(0, false, sampleProgress(5, 0, 0, 1, .reverse, .none));
    // fractional count end state with alternate: 2.5 iterations -> 3rd iteration (even index) at .5
    try expectSample(0.5, false, sampleProgress(9000, 1000, 0, 2.5, .alternate, .forwards));
    // zero iterations: fills with the end of iteration 0
    try expectSample(1, false, sampleProgress(10, 1000, 0, 0, .normal, .forwards));
}

test "ease: steps before flag, linear, cubic" {
    const st: TF = .{ .steps = .{ .n = 4, .pos = .jump_end } };
    try T.expectApproxEqAbs(@as(f32, 0.5), ease(st, 0.5, false), 1e-6);
    try T.expectApproxEqAbs(@as(f32, 0.25), ease(st, 0.5, true), 1e-6);
    const ss: TF = .{ .steps = .{ .n = 1, .pos = .jump_start } };
    try T.expectApproxEqAbs(@as(f32, 1), ease(ss, 0, false), 1e-6);
    try T.expectApproxEqAbs(@as(f32, 0), ease(ss, 0, true), 1e-6);
    try T.expectApproxEqAbs(@as(f32, 0.3), ease(TF.linear, 0.3, false), 1e-6);
}

test "keyframe points and segments" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frames = [_]css.Keyframe{
        .{ .offset = 1, .declarations = &.{} },
        .{ .offset = 0.5, .declarations = &.{} },
        .{ .offset = 0.5, .declarations = &.{} },
        .{ .offset = 0.25, .declarations = &.{} },
    };
    const r = try resolvePoints(a, &frames);
    try T.expectEqual(@as(usize, 3), r.points.len);
    try T.expectEqual(@as(f32, 0.25), r.points[0].offset);
    try T.expectEqual(@as(u32, 2), r.points[1].count);
    try T.expectEqual(@as(u32, 1), r.order[r.points[1].first]); // stable: source order kept
    var s = segment(r.points, 0.125).?;
    try T.expect(s.from == null and s.to.? == 0);
    try T.expectApproxEqAbs(@as(f32, 0.5), s.t, 1e-6);
    s = segment(r.points, 0.375).?;
    try T.expect(s.from.? == 0 and s.to.? == 1);
    try T.expectApproxEqAbs(@as(f32, 0.5), s.t, 1e-6);
    s = segment(r.points, 1).?;
    try T.expect(s.from.? == 1 and s.to.? == 2 and s.t == 1);
    // no 100% keyframe: the last segment runs back to the element's style
    s = segment(r.points[0..2], 0.75).?;
    try T.expect(s.from.? == 1 and s.to == null);
    try T.expectApproxEqAbs(@as(f32, 0.5), s.t, 1e-6);
}
