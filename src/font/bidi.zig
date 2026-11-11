//! Unicode Bidirectional Algorithm (UAX #9, Unicode 16): explicit embeddings / overrides /
//! isolates (X1-X8), isolating run sequences (X10), weak types (W1-W7), paired brackets (N0),
//! neutrals (N1-N2) and implicit levels (I1-I2). The caller supplies the paragraph direction
//! (CSS `direction`), applies L1 / L2 per line (`reorderVisual`) and mirrors glyphs of odd
//! levels while shaping.
const std = @import("std");
const uni = @import("unicode.zig");
const B = uni.Bidi;

inline fn c(comptime x: B) u8 {
    return @intFromEnum(x);
}
const WAS_NSM: u8 = 0x80;
const REMOVED: u8 = 0x40; // X9: embedding / override controls, PDF and BN
const MATCHED_PDI: u8 = 0x20;
const max_depth = 125;

inline fn isIsolateInit(k: u8) bool {
    return k == c(.lri) or k == c(.rli) or k == c(.fsi);
}
inline fn isNI(k: u8) bool {
    return k == c(.b) or k == c(.s) or k == c(.ws) or k == c(.on) or isIsolateInit(k) or k == c(.pdi);
}
inline fn dirClass(level: u8) u8 {
    return if (level & 1 != 0) c(.r) else c(.l);
}

/// True when the text needs the algorithm at all (any right-to-left or explicit control).
pub fn needsBidi(cps: []const u21) bool {
    for (cps) |cp| {
        if (cp < 0x590) continue;
        switch (uni.bidiClass(cp)) {
            .r, .al, .an, .rle, .rlo, .rli, .lre, .lro, .lri, .fsi, .pdf, .pdi => return true,
            else => {},
        }
    }
    return false;
}

/// Resolves the embedding level of every character of one paragraph (no paragraph separators
/// inside). `base` is the paragraph level (0 = LTR, 1 = RTL). `levels.len == cps.len`.
/// Scratch memory is taken from `alloc` and freed before returning.
pub fn resolve(alloc: std.mem.Allocator, cps: []const u21, levels: []u8, base: u8) !void {
    const n = cps.len;
    if (n == 0) return;
    const cls = try alloc.alloc(u8, n);
    defer alloc.free(cls);
    // match[i]: for an isolate initiator the index of its PDI (n = none); scratch afterwards
    const match = try alloc.alloc(u32, n);
    defer alloc.free(match);
    const seq = try alloc.alloc(u32, n);
    defer alloc.free(seq);
    const pair = try alloc.alloc(u32, n);
    defer alloc.free(pair);

    for (cps, cls) |cp, *k| k.* = @intFromEnum(uni.bidiClass(cp));

    // BD9: matching PDI of every isolate initiator
    {
        var stack: [max_depth + 2]u32 = undefined;
        var sp: usize = 0;
        var overflow: usize = 0;
        for (cls, 0..) |k, i| {
            match[i] = @intCast(n);
            if (isIsolateInit(k)) {
                if (sp < stack.len) {
                    stack[sp] = @intCast(i);
                    sp += 1;
                } else overflow += 1;
            } else if (k == c(.pdi)) {
                if (overflow > 0) {
                    overflow -= 1;
                } else if (sp > 0) {
                    sp -= 1;
                    match[stack[sp]] = @intCast(i);
                }
            }
        }
    }

    // X1-X8
    {
        const Entry = struct { level: u8, override: u8, isolate: bool };
        var stack: [max_depth + 2]Entry = undefined;
        var sp: usize = 1;
        stack[0] = .{ .level = base, .override = 0, .isolate = false };
        var ov_iso: u32 = 0;
        var ov_emb: u32 = 0;
        var valid_iso: u32 = 0;
        for (cls, 0..) |*k, i| {
            const top = stack[sp - 1];
            const kind = k.*;
            levels[i] = top.level;
            switch (@as(B, @enumFromInt(kind))) {
                .rle, .lre, .rlo, .lro => {
                    const rtl = kind == c(.rle) or kind == c(.rlo);
                    const nl: u8 = if (rtl) (top.level + 1) | 1 else (top.level + 2) & ~@as(u8, 1);
                    if (nl <= max_depth and ov_iso == 0 and ov_emb == 0) {
                        stack[sp] = .{ .level = nl, .override = if (kind == c(.rlo)) c(.r) + 1 else if (kind == c(.lro)) c(.l) + 1 else 0, .isolate = false };
                        sp += 1;
                    } else if (ov_iso == 0) ov_emb += 1;
                    k.* = c(.bn) | REMOVED;
                },
                .rli, .lri, .fsi => {
                    var rtl = kind == c(.rli);
                    if (kind == c(.fsi)) {
                        // first strong character up to the matching PDI, skipping nested isolates
                        var j = i + 1;
                        const end = match[i];
                        var depth: u32 = 0;
                        while (j < end) : (j += 1) {
                            const kj = cls[j] & 0x1f;
                            if (isIsolateInit(kj)) {
                                depth += 1;
                            } else if (kj == c(.pdi)) {
                                if (depth > 0) depth -= 1;
                            } else if (depth == 0 and (kj == c(.l) or kj == c(.r) or kj == c(.al))) {
                                rtl = kj != c(.l);
                                break;
                            }
                        }
                    }
                    if (top.override != 0) k.* = top.override - 1;
                    const nl: u8 = if (rtl) (top.level + 1) | 1 else (top.level + 2) & ~@as(u8, 1);
                    if (nl <= max_depth and ov_iso == 0 and ov_emb == 0) {
                        valid_iso += 1;
                        stack[sp] = .{ .level = nl, .override = 0, .isolate = true };
                        sp += 1;
                    } else ov_iso += 1;
                },
                .pdi => {
                    if (ov_iso > 0) {
                        ov_iso -= 1;
                    } else if (valid_iso > 0) {
                        ov_emb = 0;
                        while (!stack[sp - 1].isolate) sp -= 1;
                        sp -= 1;
                        valid_iso -= 1;
                    }
                    const t2 = stack[sp - 1];
                    levels[i] = t2.level;
                    if (t2.override != 0) k.* = t2.override - 1;
                },
                .pdf => {
                    if (ov_iso > 0) {} else if (ov_emb > 0) {
                        ov_emb -= 1;
                    } else if (!top.isolate and sp >= 2) sp -= 1;
                    k.* = c(.bn) | REMOVED;
                },
                .bn => k.* = c(.bn) | REMOVED,
                .b => levels[i] = base,
                else => if (top.override != 0) {
                    k.* = top.override - 1;
                },
            }
        }
    }

    // X10: isolating run sequences. A sequence starts at a level-run start that is not a PDI
    // matching an isolate initiator (those runs are entered through the initiator); bit 5 of
    // cls marks such PDIs.
    for (match) |m| {
        if (m < n) cls[m] |= MATCHED_PDI;
    }
    var prev_level: ?u8 = null; // level of the previous non-removed character
    for (0..n) |i| {
        if (cls[i] & REMOVED != 0) continue;
        const lv = levels[i];
        const run_start = prev_level == null or prev_level.? != lv;
        const before: u8 = prev_level orelse base;
        prev_level = lv;
        if (!run_start or cls[i] & MATCHED_PDI != 0) continue;
        var len: usize = 0;
        var j = i;
        var after: u8 = base;
        while (true) {
            var last = j;
            while (j < n and (cls[j] & REMOVED != 0 or levels[j] == lv)) : (j += 1) {
                if (cls[j] & REMOVED != 0) continue;
                seq[len] = @intCast(j);
                len += 1;
                last = j;
            }
            const init = isIsolateInitCp(cps[last]);
            // chain into the run that starts with the matching PDI
            if (init and match[last] < n and match[last] >= j) {
                j = match[last];
                continue;
            }
            // eos context: the next non-removed character, unless the sequence ends with an
            // unmatched isolate initiator
            if (!init) {
                var k2 = last + 1;
                while (k2 < n and cls[k2] & REMOVED != 0) k2 += 1;
                if (k2 < n) after = levels[k2];
            }
            break;
        }
        resolveSequence(cps, cls, seq[0..len], pair, lv, dirClass(@max(lv, before)), dirClass(@max(lv, after)));
    }

    // I1 / I2 (types were written back by resolveSequence), removed characters take the level
    // of their predecessor
    var last_level = base;
    for (cls, levels) |k, *l| {
        if (k & REMOVED != 0) {
            l.* = last_level;
            continue;
        }
        const t = k & 0x1f;
        if (l.* & 1 == 0) {
            if (t == c(.r)) l.* += 1 else if (t == c(.an) or t == c(.en)) l.* += 2;
        } else if (t == c(.l) or t == c(.en) or t == c(.an)) l.* += 1;
        last_level = l.*;
    }
}

fn isIsolateInitCp(cp: u21) bool {
    return cp >= 0x2066 and cp <= 0x2068;
}

/// W1-W7, N0-N2 over one isolating run sequence (`seq` = character indices).
fn resolveSequence(cps: []const u21, cls: []u8, seq: []const u32, scratch: []u32, level: u8, sos: u8, eos: u8) void {
    const T = struct {
        inline fn get(k: []const u8, s: []const u32, i: usize) u8 {
            return k[s[i]] & 0x1f;
        }
        inline fn set(k: []u8, s: []const u32, i: usize, v: u8) void {
            k[s[i]] = (k[s[i]] & 0xe0) | v;
        }
    };
    const n = seq.len;
    // W1-W3
    {
        var prev = sos;
        var last_strong = sos;
        for (0..n) |i| {
            var t = T.get(cls, seq, i);
            if (t == c(.nsm)) {
                t = if (isIsolateInit(prev) or prev == c(.pdi)) c(.on) else prev;
                T.set(cls, seq, i, t);
                cls[seq[i]] |= WAS_NSM;
            }
            if (t == c(.en) and last_strong == c(.al)) {
                t = c(.an);
                T.set(cls, seq, i, t);
            }
            if (t == c(.l) or t == c(.r) or t == c(.al)) last_strong = t;
            prev = t;
        }
        for (0..n) |i| {
            if (T.get(cls, seq, i) == c(.al)) T.set(cls, seq, i, c(.r));
        }
    }
    // W4
    if (n >= 3) {
        for (1..n - 1) |i| {
            const t = T.get(cls, seq, i);
            const p = T.get(cls, seq, i - 1);
            const x = T.get(cls, seq, i + 1);
            if (t == c(.es) and p == c(.en) and x == c(.en)) T.set(cls, seq, i, c(.en));
            if (t == c(.cs) and p == x and (p == c(.en) or p == c(.an))) T.set(cls, seq, i, p);
        }
    }
    // W5
    {
        var i: usize = 0;
        while (i < n) {
            if (T.get(cls, seq, i) != c(.et)) {
                i += 1;
                continue;
            }
            var j = i;
            while (j < n and T.get(cls, seq, j) == c(.et)) j += 1;
            const en_before = i > 0 and T.get(cls, seq, i - 1) == c(.en);
            const en_after = j < n and T.get(cls, seq, j) == c(.en);
            if (en_before or en_after) {
                for (i..j) |k| T.set(cls, seq, k, c(.en));
            }
            i = j;
        }
    }
    // W6, W7
    {
        var last_strong = sos;
        for (0..n) |i| {
            var t = T.get(cls, seq, i);
            if (t == c(.es) or t == c(.et) or t == c(.cs)) {
                t = c(.on);
                T.set(cls, seq, i, t);
            }
            if (t == c(.l) or t == c(.r)) last_strong = t;
            if (t == c(.en) and last_strong == c(.l)) T.set(cls, seq, i, c(.l));
        }
    }
    const e = dirClass(level);
    // N0: paired brackets. scratch[seq-pos of opener] = seq-pos of closer + 1 (0 = unpaired).
    {
        var any = false;
        var stack_cp: [63]u21 = undefined;
        var stack_pos: [63]u32 = undefined;
        var sp: usize = 0;
        for (0..n) |i| scratch[i] = 0;
        for (0..n) |i| {
            if (T.get(cls, seq, i) != c(.on)) continue;
            const cp = cps[seq[i]];
            const br = uni.bracket(cp) orelse continue;
            if (br.open) {
                if (sp == stack_cp.len) break;
                stack_cp[sp] = br.pair;
                stack_pos[sp] = @intCast(i);
                sp += 1;
            } else {
                const canon: u21 = if (cp == 0x232a) 0x3009 else cp;
                var k = sp;
                while (k > 0) {
                    k -= 1;
                    if (stack_cp[k] == canon) {
                        scratch[stack_pos[k]] = @intCast(i + 1);
                        any = true;
                        sp = k;
                        break;
                    }
                }
            }
        }
        if (any) {
            for (0..n) |open| {
                if (scratch[open] == 0) continue;
                const close: usize = scratch[open] - 1;
                var found_e = false;
                var found_o = false;
                for (open + 1..close) |k| {
                    var t = T.get(cls, seq, k);
                    if (t == c(.en) or t == c(.an)) t = c(.r);
                    if (t == e) {
                        found_e = true;
                        break;
                    }
                    if (t == c(.l) or t == c(.r)) found_o = true;
                }
                var dir: u8 = 0xff;
                if (found_e) {
                    dir = e;
                } else if (found_o) {
                    // context before the opening bracket
                    var ctx = sos;
                    var k = open;
                    while (k > 0) {
                        k -= 1;
                        var t = T.get(cls, seq, k);
                        if (t == c(.en) or t == c(.an)) t = c(.r);
                        if (t == c(.l) or t == c(.r)) {
                            ctx = t;
                            break;
                        }
                    }
                    dir = if (ctx != e) ctx else e;
                }
                if (dir == 0xff) continue;
                T.set(cls, seq, open, dir);
                T.set(cls, seq, close, dir);
                // NSMs that followed a bracket take its direction
                for ([_]usize{ open, close }) |p| {
                    var k = p + 1;
                    while (k < n and cls[seq[k]] & WAS_NSM != 0) : (k += 1) T.set(cls, seq, k, dir);
                }
            }
        }
    }
    // N1, N2
    {
        var i: usize = 0;
        while (i < n) {
            if (!isNI(T.get(cls, seq, i))) {
                i += 1;
                continue;
            }
            var j = i;
            while (j < n and isNI(T.get(cls, seq, j))) j += 1;
            var before = if (i == 0) sos else T.get(cls, seq, i - 1);
            var after = if (j == n) eos else T.get(cls, seq, j);
            if (before == c(.en) or before == c(.an)) before = c(.r);
            if (after == c(.en) or after == c(.an)) after = c(.r);
            const v = if (before == after) before else e;
            for (i..j) |k| T.set(cls, seq, k, v);
            i = j;
        }
    }
}

/// L2 for one line: fills `order` with a visual-order permutation (order[v] = logical index)
/// for items whose levels are `levels` (already adjusted for L1 by the caller).
pub fn reorderVisual(levels: []const u8, order: []u32) void {
    const n = levels.len;
    var max: u8 = 0;
    var min_odd: u8 = 255;
    for (levels, 0..) |l, i| {
        order[i] = @intCast(i);
        max = @max(max, l);
        if (l & 1 != 0) min_odd = @min(min_odd, l);
    }
    if (min_odd == 255) return;
    var lv = max;
    while (lv >= min_odd) : (lv -= 1) {
        var i: usize = 0;
        while (i < n) {
            if (levels[order[i]] < lv) {
                i += 1;
                continue;
            }
            var j = i;
            while (j < n and levels[order[j]] >= lv) j += 1;
            std.mem.reverse(u32, order[i..j]);
            i = j;
        }
        if (lv == 0) break;
    }
}

test "reorderVisual" {
    var order: [6]u32 = undefined;
    reorderVisual(&.{ 0, 1, 1, 2, 2, 0 }, &order);
    // level-2 run reversed inside the reversed level-1+ run
    try std.testing.expectEqualSlices(u32, &.{ 0, 3, 4, 2, 1, 5 }, &order);
}
