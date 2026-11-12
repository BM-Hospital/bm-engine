//! `prepare` (evaluate gates once, order layers, bucket rules) and `match` (cascade-ordered
//! declarations for one element), mirroring takumi `matching.rs` (`RuleIndex`, `finalize_bucket`).
const std = @import("std");
const sel = @import("selector.zig");
const tk = @import("tokenizer.zig");
const media = @import("media.zig");
const sheet_mod = @import("sheet.zig");
const Allocator = std.mem.Allocator;
const Vec = @import("vec.zig").Vec;
const Declaration = sheet_mod.Declaration;
const Stylesheet = sheet_mod.Stylesheet;
const Rule = sheet_mod.Rule;
const Env = media.Env;

pub const Pseudo = enum(u8) { none, before, after };

const ActiveRule = struct {
    rule: *const Rule,
    /// Layer position (0..layer_count-1), or layer_count for unlayered.
    layer: u32,
};

const Bucket = struct {
    kind: sel.KeyKind,
    name: []const u8,
    rule: u32,
};

pub const Matcher = struct {
    rules: []const ActiveRule = &.{},
    layer_count: u32 = 0,
    /// Sorted by (kind, name, rule).
    buckets: []const Bucket = &.{},
    unindexed: []const u32 = &.{},
    keyframes: []const *const sheet_mod.KeyframesRule = &.{},
    font_faces: []const *const sheet_mod.FontFace = &.{},
    /// Whether any active selector targets `::before` / `::after` (lets the caller skip those calls).
    has_before: bool = false,
    has_after: bool = false,
    /// Ordered layer names (index = layer position), for debugging / tests.
    layer_names: []const []const u8 = &.{},
};

fn gatesPass(sheet: *const Stylesheet, gates: []const u32, ok: []const bool) bool {
    _ = sheet;
    for (gates) |g| if (g >= ok.len or !ok[g]) return false;
    return true;
}

fn evalGates(arena: Allocator, sheet: *const Stylesheet, env: Env) error{OutOfMemory}![]bool {
    const ok = try arena.alloc(bool, sheet.gates.items.len);
    for (sheet.gates.items, 0..) |g, i| ok[i] = switch (g) {
        .media => |q| media.queryListMatches(q, env),
        .supports => |s| media.supportsMatches(s, env, 0),
    };
    return ok;
}

fn indexOf(names: []const []const u8, n: []const u8) ?u32 {
    for (names, 0..) |x, i| if (tk.seq(x, n)) return @intCast(i);
    return null;
}

const max_layers = 1000;

/// Evaluates `@media`/`@supports` against `env`, resolves layer order, and indexes the active rules.
/// Everything is allocated in `arena`; the Matcher borrows from `sheet` (keep it alive).
pub fn prepare(arena: Allocator, sheet: *const Stylesheet, env: Env) error{OutOfMemory}!Matcher {
    var m: Matcher = .{};
    // Tailwind Preflight goes first (its `base` layer is declared before everything else).
    var pf: Stylesheet = .{};
    if (sheet.preflight) try sheet_mod.parse(arena, sheet_mod.preflight_css, &pf);
    const sheets = [_]*const Stylesheet{ &pf, sheet };

    // Layer order: declared layers in parse order, then layers only used by rules, first occurrence.
    var names: Vec([]const u8) = .empty;
    for (sheets) |sh| for (sh.layer_decls.items) |li| {
        const n = sh.layer_names.items[li];
        if (indexOf(names.items, n) == null and names.items.len < max_layers) try names.append(arena, n);
    };
    for (sheets) |sh| for (sh.rules.items) |r| {
        if (r.layer == sheet_mod.no_layer) continue;
        const n = sh.layer_names.items[r.layer];
        if (indexOf(names.items, n) == null and names.items.len < max_layers) try names.append(arena, n);
    };
    m.layer_names = names.items;
    m.layer_count = @intCast(names.items.len);

    var rules: Vec(ActiveRule) = .empty;
    var kfs: Vec(*const sheet_mod.KeyframesRule) = .empty;
    var faces: Vec(*const sheet_mod.FontFace) = .empty;
    for (sheets) |sh| {
        const ok = try evalGates(arena, sh, env);
        // per-sheet layer index -> global position
        const lmap = try arena.alloc(u32, sh.layer_names.items.len);
        for (sh.layer_names.items, 0..) |n, i| lmap[i] = indexOf(names.items, n) orelse m.layer_count -| 1;
        for (sh.rules.items) |*r| {
            if (!gatesPass(sh, r.gates, ok)) continue;
            const layer = if (r.layer == sheet_mod.no_layer or r.layer >= lmap.len) m.layer_count else lmap[r.layer];
            try rules.append(arena, .{ .rule = r, .layer = layer });
        }
        for (sh.keyframes.items) |*k| if (gatesPass(sh, k.gates, ok)) try kfs.append(arena, k);
        for (sh.font_faces.items) |*f| if (gatesPass(sh, f.gates, ok)) try faces.append(arena, f);
    }
    for (sheet.extra_keyframes.items) |*k| try kfs.append(arena, k);
    m.rules = rules.items;
    m.keyframes = kfs.items;
    m.font_faces = faces.items;

    // Buckets by the rightmost compound key of every selector; a rule with any unkeyed selector is
    // visited by every element (takumi `RuleIndex::build`).
    var buckets: Vec(Bucket) = .empty;
    var unindexed: Vec(u32) = .empty;
    for (rules.items, 0..) |ar, ri| {
        const idx: u32 = @intCast(ri);
        var any = false;
        const mark = buckets.items.len;
        for (ar.rule.selectors) |*c| {
            switch (c.pseudo) {
                .before => m.has_before = true,
                .after => m.has_after = true,
                else => {},
            }
            const k = sel.bucketKey(c);
            if (k.kind == .any or k.kind == .attr) {
                any = true;
                break;
            }
            try buckets.append(arena, .{ .kind = k.kind, .name = k.name, .rule = idx });
        }
        if (any) {
            buckets.items.len = mark;
            try unindexed.append(arena, idx);
        }
    }
    std.sort.heap(Bucket, buckets.items, {}, bucketLess);
    m.buckets = buckets.items;
    m.unindexed = unindexed.items;
    return m;
}

fn orderStr(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

fn bucketLess(_: void, a: Bucket, b: Bucket) bool {
    if (a.kind != b.kind) return @intFromEnum(a.kind) < @intFromEnum(b.kind);
    switch (orderStr(a.name, b.name)) {
        .lt => return true,
        .gt => return false,
        .eq => return a.rule < b.rule,
    }
}

/// Appends the rule indices of bucket (kind, name) to `out`.
fn lookup(m: *const Matcher, kind: sel.KeyKind, name: []const u8, out: *Vec(u32), gpa: Allocator) error{OutOfMemory}!void {
    const b = m.buckets;
    var lo: usize = 0;
    var hi: usize = b.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = b[mid];
        const less = if (e.kind != kind) @intFromEnum(e.kind) < @intFromEnum(kind) else orderStr(e.name, name) == .lt;
        if (less) lo = mid + 1 else hi = mid;
    }
    while (lo < b.len and b[lo].kind == kind and tk.seq(b[lo].name, name)) : (lo += 1) {
        try out.append(gpa, b[lo].rule);
    }
}

/// Reusable per-render scratch buffers for `match` (allocate with the render arena or a gpa).
pub const Scratch = struct {
    gpa: Allocator,
    cand: Vec(u32) = .empty,
    keys: Vec(u64) = .empty,
    tag_buf: [64]u8 = undefined,
    /// Work budget per `match` call (compound tests); exhausted -> remaining selectors fail.
    budget: u32 = 200_000,
    /// Set when a call ran out of budget (diagnostics).
    exhausted: bool = false,

    pub fn init(gpa: Allocator) Scratch {
        return .{ .gpa = gpa };
    }
    pub fn deinit(s: *Scratch) void {
        s.cand.deinit(s.gpa);
        s.keys.deinit(s.gpa);
    }
};

pub const MatchResult = struct {
    /// Declarations `[start .. important_start)` (appended to `out`) are the normal ones in ascending
    /// precedence; `[important_start .. out.len)` the `!important` ones in ascending precedence.
    important_start: usize,
    /// Where the unlayered normal declarations start (`<= important_start`): `[start ..
    /// unlayered_start)` come from named `@layer`s. takumi puts the `tw` utilities between the two.
    unlayered_start: usize = 0,
    /// Where the `!important` declarations of named layers start (`>= important_start`):
    /// `[important_start .. layered_important_start)` are unlayered ones; `tw` goes between.
    layered_important_start: usize = 0,
    /// For `.before`/`.after`: whether a matched declaration sets `content` (takumi creates the
    /// pseudo-element box only then).
    sets_content: bool = false,
    /// Number of matched rules.
    rules: u32 = 0,
};

fn pseudoOf(p: Pseudo) sel.Pseudo {
    return switch (p) {
        .none => .none,
        .before => .before,
        .after => .after,
    };
}

/// Appends the declarations of every active rule whose selector (targeting `pseudo`) matches `el`
/// to `out`, in cascade order. See `MatchResult` for the two segments. Rule order: normal blocks by
/// (layer position with unlayered last, specificity, source order); `!important` blocks by
/// (unlayered first then layers in REVERSE order, specificity, source order). Within a rule the
/// declarations keep source order. A rule matched by several of its selectors uses the highest
/// specificity among them.
pub fn match(m: *const Matcher, scratch: *Scratch, dom: *const sel.Dom, el: sel.Element, pseudo: Pseudo, out: *std.ArrayList(Declaration)) error{OutOfMemory}!MatchResult {
    const gpa = scratch.gpa;
    scratch.cand.clearRetainingCapacity();
    scratch.keys.clearRetainingCapacity();
    const out_start = out.items.len;
    var res: MatchResult = .{ .important_start = out_start, .unlayered_start = out_start, .layered_important_start = out_start };
    const want = pseudoOf(pseudo);
    if (pseudo == .before and !m.has_before) return res;
    if (pseudo == .after and !m.has_after) return res;
    if (m.rules.len == 0) return res;

    // candidates
    try scratch.cand.appendSlice(gpa, m.unindexed);
    const id = dom.id(dom.ctx, el);
    if (id.len != 0) try lookup(m, .id, id, &scratch.cand, gpa);
    const classes = dom.classes(dom.ctx, el);
    {
        var i: usize = 0;
        while (i < classes.len) {
            while (i < classes.len and isWs(classes[i])) i += 1;
            const s = i;
            while (i < classes.len and !isWs(classes[i])) i += 1;
            if (i > s) try lookup(m, .class, classes[s..i], &scratch.cand, gpa);
        }
    }
    const tag = dom.tag(dom.ctx, el);
    if (tag.len != 0) {
        var lower: []const u8 = tag;
        var needs = false;
        for (tag) |c| if (c >= 'A' and c <= 'Z') {
            needs = true;
        };
        if (needs) {
            const buf = if (tag.len <= scratch.tag_buf.len) scratch.tag_buf[0..tag.len] else try gpa.alloc(u8, tag.len);
            for (tag, 0..) |c, i| buf[i] = std.ascii.toLower(c);
            lower = buf;
        }
        try lookup(m, .tag, lower, &scratch.cand, gpa);
    }
    const cand = scratch.cand.items;
    std.sort.heap(u32, cand, {}, std.sort.asc(u32));

    var cx: sel.MatchCx = .{ .dom = dom, .budget = scratch.budget };
    var prev: u32 = std.math.maxInt(u32);
    for (cand) |ri| {
        if (ri == prev) continue;
        prev = ri;
        const ar = m.rules[ri];
        var best: ?u32 = null;
        for (ar.rule.selectors) |*c| {
            if (c.pseudo != want) continue;
            if (best != null and c.spec <= best.?) continue;
            if (sel.matches(&cx, c, el)) best = c.spec;
        }
        const spec = best orelse continue;
        res.rules += 1;
        // key: layer(10) | spec(30) | rule(24)
        const key = (@as(u64, @min(ar.layer, 1023)) << 54) | (@as(u64, spec & 0x3FFF_FFFF) << 24) | @as(u64, ri & 0xFF_FFFF);
        try scratch.keys.append(gpa, key);
    }
    scratch.exhausted = cx.budget == 0;
    const keys = scratch.keys.items;
    std.sort.heap(u64, keys, {}, std.sort.asc(u64));
    // normal
    var unlayered_seen = false;
    for (keys) |k| {
        if (!unlayered_seen and (k >> 54) >= @min(m.layer_count, 1023)) {
            unlayered_seen = true;
            res.unlayered_start = out.items.len;
        }
        const r = m.rules[@intCast(k & 0xFF_FFFF)].rule;
        for (r.decls) |d| if (!d.important) {
            try out.append(gpa, d);
            if (tk.seq(d.name, "content")) res.sets_content = true;
        };
    }
    res.important_start = out.items.len;
    if (!unlayered_seen) res.unlayered_start = out.items.len;
    res.layered_important_start = out.items.len;
    // important: re-key the layer part (unlayered -> 0, layer i -> L - i)
    var any_imp = false;
    for (keys) |*k| {
        const r = m.rules[@intCast(k.* & 0xFF_FFFF)].rule;
        var has = false;
        for (r.decls) |d| if (d.important) {
            has = true;
        };
        if (!has) {
            k.* |= @as(u64, 1) << 63; // sort to the end, skipped
            continue;
        }
        any_imp = true;
        const layer: u64 = k.* >> 54;
        const L: u64 = @min(m.layer_count, 1023);
        const il: u64 = if (layer >= L) 0 else L - layer;
        k.* = (il << 54) | (k.* & ((@as(u64, 1) << 54) - 1));
    }
    if (any_imp) {
        std.sort.heap(u64, keys, {}, std.sort.asc(u64));
        var layered_seen = false;
        for (keys) |k| {
            if (k >> 63 != 0) break;
            if (!layered_seen and (k >> 54) != 0) {
                layered_seen = true;
                res.layered_important_start = out.items.len;
            }
            const r = m.rules[@intCast(k & 0xFF_FFFF)].rule;
            for (r.decls) |d| if (d.important) {
                try out.append(gpa, d);
                if (tk.seq(d.name, "content")) res.sets_content = true;
            };
        }
        if (!layered_seen) res.layered_important_start = out.items.len;
    }
    return res;
}

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0c;
}

/// The keyframes named `name` (ASCII case-insensitive) whose `@media` matched: the last definition
/// wins; deprecated `keyframes`-option entries win over stylesheet ones. null = none (takumi then
/// falls back to Tailwind's built-in `spin/ping/pulse/bounce`, which is the animation module's job).
pub fn keyframes(m: *const Matcher, name: []const u8) ?[]const sheet_mod.Keyframe {
    var i = m.keyframes.len;
    while (i > 0) {
        i -= 1;
        if (tk.ieq(m.keyframes[i].name, name)) return m.keyframes[i].frames;
    }
    return null;
}
