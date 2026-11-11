//! Indic shaper (port of HarfBuzz `hb-ot-shaper-indic`): syllable segmentation, initial
//! reordering (base consonant search, reph, pre-base matras, old-spec halant move), per-glyph
//! masks for the basic shaping features, and final reordering (matra / reph / pre-base
//! reordering consonant placement, `init`). Category data: `indic_data.zig` (U+0900..U+0DFF,
//! Vedic extensions, Devanagari Extended). Verified against the oracle for Devanagari and
//! Bengali; the other eight scripts share the code and the per-script configuration table but
//! are untested. Not ported: Sinhala's base rule, Kannada Ra+H+ZWJ legacy swap is included,
//! Uniscribe bug-compatibility mode, Khmer / Myanmar / USE (those scripts use the default shaper).
const std = @import("std");
const ttf = @import("ttf.zig");
const ot = @import("ot.zig");
const data = @import("indic_data.zig");
const ucd = @import("ucd.zig");
const Font = ttf.Font;
const Glyph = ot.Glyph;
const tag = ot.tag;

// categories
const X = 0;
const C = 1;
const V = 2;
const N = 3;
const H = 4;
const ZWNJ = 5;
const ZWJ = 6;
const M = 7;
const SM = 8;
const A = 9;
const PLACEHOLDER = 10;
const DOTTED = 11;
const RS = 12;
const MPst = 13;
const Repha = 14;
const Ra = 15;
const CM = 16;
const Symbol = 17;
const CS = 18;

// positions
const POS_START = 0;
const POS_RA_TO_BECOME_REPH = 1;
const POS_PRE_M = 2;
const POS_PRE_C = 3;
const POS_BASE_C = 4;
const POS_AFTER_MAIN = 5;
const POS_ABOVE_C = 6;
const POS_BEFORE_SUB = 7;
const POS_BELOW_C = 8;
const POS_AFTER_SUB = 9;
const POS_BEFORE_POST = 10;
const POS_POST_C = 11;
const POS_AFTER_POST = 12;
const POS_SMVD = 13;
const POS_END = 14;

const consonant_flags: u32 = (1 << C) | (1 << CS) | (1 << Ra) | (1 << CM) | (1 << V) | (1 << PLACEHOLDER) | (1 << DOTTED);
const joiner_flags: u32 = (1 << ZWJ) | (1 << ZWNJ);

const RephPos = enum(u8) { after_main = POS_AFTER_MAIN, before_sub = POS_BEFORE_SUB, after_sub = POS_AFTER_SUB, before_post = POS_BEFORE_POST, after_post = POS_AFTER_POST };
const RephMode = enum { implicit, explicit, log_repha };
const BlwfMode = enum { pre_and_post, post_only };

const Config = struct { script: u8, virama: u21, reph_pos: RephPos, reph_mode: RephMode = .implicit, blwf_mode: BlwfMode = .pre_and_post };

const configs = [_]Config{
    .{ .script = ucd.sc_devanagari, .virama = 0x094d, .reph_pos = .before_post },
    .{ .script = ucd.sc_bengali, .virama = 0x09cd, .reph_pos = .after_sub },
    .{ .script = ucd.sc_gurmukhi, .virama = 0x0a4d, .reph_pos = .before_sub },
    .{ .script = ucd.sc_gujarati, .virama = 0x0acd, .reph_pos = .before_post },
    .{ .script = ucd.sc_oriya, .virama = 0x0b4d, .reph_pos = .after_main },
    .{ .script = ucd.sc_tamil, .virama = 0x0bcd, .reph_pos = .after_post },
    .{ .script = ucd.sc_telugu, .virama = 0x0c4d, .reph_pos = .after_post, .reph_mode = .explicit, .blwf_mode = .post_only },
    .{ .script = ucd.sc_kannada, .virama = 0x0ccd, .reph_pos = .after_post, .blwf_mode = .post_only },
    .{ .script = ucd.sc_malayalam, .virama = 0x0d4d, .reph_pos = .after_main, .reph_mode = .log_repha },
};

pub fn isIndicScript(script: u8) bool {
    for (configs) |c| if (c.script == script) return true;
    return false;
}

/// Script tags to try, newest spec first.
pub fn scriptTags(script: u8) [3]u32 {
    return switch (script) {
        ucd.sc_devanagari => .{ tag("dev3"), tag("dev2"), tag("deva") },
        ucd.sc_bengali => .{ tag("bng3"), tag("bng2"), tag("beng") },
        ucd.sc_gurmukhi => .{ tag("gur3"), tag("gur2"), tag("guru") },
        ucd.sc_gujarati => .{ tag("gjr3"), tag("gjr2"), tag("gujr") },
        ucd.sc_oriya => .{ tag("ory3"), tag("ory2"), tag("orya") },
        ucd.sc_tamil => .{ tag("tml3"), tag("tml2"), tag("taml") },
        ucd.sc_telugu => .{ tag("tel3"), tag("tel2"), tag("telu") },
        ucd.sc_kannada => .{ tag("knd3"), tag("knd2"), tag("knda") },
        else => .{ tag("mlm3"), tag("mlm2"), tag("mlym") },
    };
}

/// Stage layout of the Indic feature plan (see `features`).
pub const stage_syllables = 1; // hook after this stage: find syllables
pub const stage_initial = 2; // hook after: initial reordering
pub const stage_basic_last = 13; // hook after: final reordering
pub const stage_final = 14;

const F = ot.FeatureReq;
const J = ot.F_MANUAL_JOINERS | ot.F_PER_SYLLABLE;
const GJ = ot.F_GLOBAL | J;
/// Shaper features (the caller appends the common GSUB / GPOS features at `stage_final`).
pub const features = [_]F{
    .{ .tag = tag("locl"), .flags = ot.F_GLOBAL | ot.F_PER_SYLLABLE, .stage = 2 },
    .{ .tag = tag("ccmp"), .flags = ot.F_GLOBAL | ot.F_PER_SYLLABLE, .stage = 2 },
    .{ .tag = tag("nukt"), .flags = GJ, .stage = 3 },
    .{ .tag = tag("akhn"), .flags = GJ, .stage = 4 },
    .{ .tag = tag("rphf"), .flags = J, .stage = 5 },
    .{ .tag = tag("rkrf"), .flags = GJ, .stage = 6 },
    .{ .tag = tag("pref"), .flags = J, .stage = 7 },
    .{ .tag = tag("blwf"), .flags = J, .stage = 8 },
    .{ .tag = tag("abvf"), .flags = J, .stage = 9 },
    .{ .tag = tag("half"), .flags = J, .stage = 10 },
    .{ .tag = tag("pstf"), .flags = J, .stage = 11 },
    .{ .tag = tag("vatu"), .flags = GJ, .stage = 12 },
    .{ .tag = tag("cjct"), .flags = GJ, .stage = 13 },
    .{ .tag = tag("init"), .flags = J, .stage = 14 },
    .{ .tag = tag("pres"), .flags = GJ, .stage = 14 },
    .{ .tag = tag("abvs"), .flags = GJ, .stage = 14 },
    .{ .tag = tag("blws"), .flags = GJ, .stage = 14 },
    .{ .tag = tag("psts"), .flags = GJ, .stage = 14 },
    .{ .tag = tag("haln"), .flags = GJ, .stage = 14 },
};

pub const IndicPlan = struct {
    config: Config = configs[0],
    is_old_spec: bool = false,
    zero_context: bool = true,
    virama_gid: u16 = 0,
    dotted_gid: u16 = 0,
    rphf: u32 = 0,
    pref: u32 = 0,
    blwf: u32 = 0,
    abvf: u32 = 0,
    half: u32 = 0,
    pstf: u32 = 0,
    init_mask: u32 = 0,

    pub fn create(plan: *const ot.Plan, font: *const Font, script: u8) IndicPlan {
        var ip: IndicPlan = .{};
        for (configs) |c| if (c.script == script) {
            ip.config = c;
        };
        ip.is_old_spec = (plan.gsub.script_tag & 0xff) != '2' and (plan.gsub.script_tag & 0xff) != '3';
        ip.zero_context = !ip.is_old_spec and script != ucd.sc_malayalam;
        ip.virama_gid = font.glyphIndex(ip.config.virama);
        ip.dotted_gid = font.glyphIndex(0x25cc);
        ip.rphf = plan.maskOf(tag("rphf"));
        ip.pref = plan.maskOf(tag("pref"));
        ip.blwf = plan.maskOf(tag("blwf"));
        ip.abvf = plan.maskOf(tag("abvf"));
        ip.half = plan.maskOf(tag("half"));
        ip.pstf = plan.maskOf(tag("pstf"));
        ip.init_mask = plan.maskOf(tag("init"));
        return ip;
    }
};

fn categorize(cp: u21) [2]u8 {
    return switch (cp) {
        0x0900...0x0dff => data.pairs[data.main[cp - 0x900]],
        0x1cd0...0x1cff => data.pairs[data.vedic[cp - 0x1cd0]],
        0xa8e0...0xa8ff => data.pairs[data.deva_ext[cp - 0xa8e0]],
        0x200c => .{ ZWNJ, POS_END },
        0x200d => .{ ZWJ, POS_END },
        0x25cc => .{ DOTTED, POS_BASE_C },
        '-', '0'...'9', 0xa0, 0xd7, 0x2010...0x2014 => .{ PLACEHOLDER, POS_BASE_C },
        else => .{ X, POS_END },
    };
}

pub fn setupMasks(b: *ot.Buffer) void {
    for (b.g()) |*gl| {
        const cp = categorize(gl.cp);
        gl.cat = cp[0];
        gl.pos = cp[1];
    }
}

// ---------------------------------------------------------------------------- syllables

const Syl = enum(u4) { consonant, vowel, standalone, symbol, broken, non_indic };

const Scan = struct {
    gs: []const Glyph,

    inline fn cat(s: Scan, i: usize) u8 {
        return if (i < s.gs.len) s.gs[i].cat else 0xff;
    }
    inline fn isZ(c: u8) bool {
        return c == ZWJ or c == ZWNJ;
    }
    fn mN(s: Scan, p: usize) usize {
        var q = p;
        if (s.cat(q) == RS) {
            q += 1;
        } else if (s.cat(q) == ZWNJ and s.cat(q + 1) == RS) q += 2;
        if (s.cat(q) == N) {
            q += 1;
            if (s.cat(q) == N) q += 1;
        }
        return q;
    }
    fn mCn(s: Scan, p: usize) ?usize {
        const c = s.cat(p);
        if (c != C and c != Ra) return null;
        var q = p + 1;
        if (s.cat(q) == ZWJ) q += 1;
        return s.mN(q);
    }
    fn mMatra(s: Scan, p: usize) ?usize {
        var q = p;
        while (isZ(s.cat(q))) q += 1;
        if (s.cat(q) == M or s.cat(q) == MPst) {
            q += 1;
        } else if (s.cat(q) == SM and s.cat(q + 1) == MPst) {
            q += 2;
        } else return null;
        if (s.cat(q) == N) q += 1;
        if (s.cat(q) == H) q += 1;
        return q;
    }
    fn mTail(s: Scan, p: usize) usize {
        var q = p;
        var r = q;
        if (isZ(s.cat(r))) r += 1;
        if (s.cat(r) == SM) {
            r += 1;
            if (s.cat(r) == SM) r += 1;
            if (s.cat(r) == ZWNJ) r += 1;
            q = r;
        }
        while (s.cat(q) == A) q += 1;
        return q;
    }
    fn mHalant(s: Scan, p: usize) ?usize {
        var q = p;
        if (isZ(s.cat(q))) q += 1;
        if (s.cat(q) != H) return null;
        q += 1;
        if (s.cat(q) == ZWJ) {
            q += 1;
            if (s.cat(q) == N) q += 1;
        }
        return q;
    }
    fn complexTail(s: Scan, p_in: usize) usize {
        var p = p_in;
        while (true) {
            const h = s.mHalant(p) orelse break;
            p = s.mCn(h) orelse break;
        }
        if (s.cat(p) == CM) p += 1;
        var best = s.mTail(p);
        if (s.mHalant(p)) |q| best = @max(best, s.mTail(q));
        if (s.cat(p) == H and s.cat(p + 1) == ZWNJ) best = @max(best, s.mTail(p + 2));
        var q = p;
        while (s.mMatra(q)) |r| {
            q = r;
            best = @max(best, s.mTail(q));
        }
        return best;
    }
    /// Length-maximal syllable at `p`.
    fn next(s: Scan, p: usize, kind: *Syl) usize {
        var best: usize = p;
        const c0 = s.cat(p);
        // consonant syllable: (Repha|CS)? cn tail
        {
            const q: usize = if (c0 == Repha or c0 == CS) p + 1 else p;
            for ([_]usize{ q, p }) |st| {
                if (s.mCn(st)) |r| {
                    const e = s.complexTail(r);
                    if (e > best) {
                        best = e;
                        kind.* = .consonant;
                    }
                }
            }
        }
        // start after an optional reph (Ra H | Repha)
        const after_reph: usize = if (c0 == Repha) p + 1 else if (c0 == Ra and s.cat(p + 1) == H) p + 2 else p;
        // vowel syllable: reph? V n? (ZWJ | tail)
        for ([_]usize{ after_reph, p }) |st| {
            if (s.cat(st) != V) continue;
            const q = s.mN(st + 1);
            var e = s.complexTail(q);
            if (s.cat(q) == ZWJ) e = @max(e, q + 1);
            if (e > best) {
                best = e;
                kind.* = .vowel;
            }
        }
        // standalone cluster: ((Repha|CS)? PLACEHOLDER | reph? DOTTEDCIRCLE) n? tail
        {
            const q: usize = if (c0 == Repha or c0 == CS) p + 1 else p;
            for ([_]usize{ q, p, after_reph }) |st| {
                const cc = s.cat(st);
                const ok = (cc == PLACEHOLDER and (st == q or st == p)) or (cc == DOTTED and (st == after_reph or st == p));
                if (!ok) continue;
                const e = s.complexTail(s.mN(st + 1));
                if (e > best) {
                    best = e;
                    kind.* = .standalone;
                }
            }
        }
        // symbol cluster: Symbol N? syllable_tail
        if (c0 == Symbol) {
            var q = p + 1;
            if (s.cat(q) == N) q += 1;
            const e = s.mTail(q);
            if (e > best) {
                best = e;
                kind.* = .symbol;
            }
        }
        // broken cluster: reph? n? tail
        for ([_]usize{ after_reph, p }) |st| {
            const e = s.complexTail(s.mN(st));
            if (e > best) {
                best = e;
                kind.* = .broken;
            }
        }
        if (best == p) {
            kind.* = .non_indic;
            return p + 1;
        }
        return best;
    }
};

pub fn findSyllables(b: *ot.Buffer) void {
    const gs = b.g();
    const s: Scan = .{ .gs = gs };
    var serial: u8 = 1;
    var p: usize = 0;
    while (p < gs.len) {
        var kind: Syl = .non_indic;
        const e = @min(s.next(p, &kind), gs.len);
        for (gs[p..e]) |*gl| gl.syllable = (serial << 4) | @intFromEnum(kind);
        serial += 1;
        if (serial == 16) serial = 1;
        p = e;
    }
}

// ---------------------------------------------------------------------------- helpers

inline fn isOneOf(gl: *const Glyph, flags: u32) bool {
    if (gl.ligated()) return false;
    return gl.cat < 32 and (@as(u32, 1) << @intCast(gl.cat)) & flags != 0;
}
inline fn isConsonant(gl: *const Glyph) bool {
    return isOneOf(gl, consonant_flags);
}
inline fn isJoiner(gl: *const Glyph) bool {
    return isOneOf(gl, joiner_flags);
}
inline fn isHalant(gl: *const Glyph) bool {
    return isOneOf(gl, 1 << H);
}

fn would(plan: *const ot.Plan, ip: *const IndicPlan, feature: u32, glyphs: []const u16) bool {
    for (plan.featureLookups(feature)) |ref| {
        if (ot.wouldSubstitute(plan.gsub_table, ref.index, glyphs, ip.zero_context)) return true;
    }
    return false;
}

fn consonantPosition(plan: *const ot.Plan, ip: *const IndicPlan, consonant: u16) u8 {
    const g = [3]u16{ ip.virama_gid, consonant, ip.virama_gid };
    if (would(plan, ip, tag("blwf"), g[0..2]) or would(plan, ip, tag("blwf"), g[1..3]) or
        would(plan, ip, tag("vatu"), g[0..2]) or would(plan, ip, tag("vatu"), g[1..3])) return POS_BELOW_C;
    if (would(plan, ip, tag("pstf"), g[0..2]) or would(plan, ip, tag("pstf"), g[1..3])) return POS_POST_C;
    if (would(plan, ip, tag("pref"), g[0..2]) or would(plan, ip, tag("pref"), g[1..3])) return POS_POST_C;
    return POS_BASE_C;
}

fn moveForward(gs: []Glyph, from: usize, to: usize) void {
    // moves gs[from] to index `to` (to > from), shifting the glyphs in between down
    const t = gs[from];
    std.mem.copyForwards(Glyph, gs[from..to], gs[from + 1 .. to + 1]);
    gs[to] = t;
}

// ---------------------------------------------------------------------------- initial reordering

pub fn initialReordering(ip: *const IndicPlan, plan: *const ot.Plan, b: *ot.Buffer) !void {
    // consonant positions from the font
    if (ip.virama_gid != 0) {
        for (b.g()) |*gl| {
            if (gl.pos == POS_BASE_C) gl.pos = consonantPosition(plan, ip, gl.gid);
        }
    }
    // dotted circles for broken clusters
    if (ip.dotted_gid != 0) {
        var i: usize = 0;
        var last: u8 = 0;
        while (i < b.g().len) : (i += 1) {
            const sy = b.g()[i].syllable;
            if (sy == last) continue;
            last = sy;
            if (sy & 0x0f != @intFromEnum(Syl.broken)) continue;
            var at = i;
            while (at < b.g().len and b.g()[at].syllable == sy and b.g()[at].cat == Repha) at += 1;
            var dot = b.g()[i];
            dot.gid = ip.dotted_gid;
            dot.cp = 0x25cc;
            dot.cat = DOTTED;
            dot.pos = POS_END;
            dot.uprops = 0;
            dot.ccc = 0;
            dot.lig = 0;
            dot.props = if (plan.gdef.hasClasses()) plan.gdef.props(dot.gid) else Glyph.BASE;
            try b.insert(at, dot);
            i += 1;
        }
    }
    const gs = b.g();
    var start: usize = 0;
    while (start < gs.len) {
        var end = start + 1;
        while (end < gs.len and gs[end].syllable == gs[start].syllable) end += 1;
        const kind = gs[start].syllable & 0x0f;
        if (kind != @intFromEnum(Syl.symbol) and kind != @intFromEnum(Syl.non_indic))
            reorderConsonantSyllable(ip, plan, b, start, end);
        start = end;
    }
}

fn reorderConsonantSyllable(ip: *const IndicPlan, plan: *const ot.Plan, b: *ot.Buffer, start: usize, end: usize) void {
    const gs = b.g();
    const script = ip.config.script;
    if (script == ucd.sc_kannada and start + 3 <= end and isOneOf(&gs[start], 1 << Ra) and isOneOf(&gs[start + 1], 1 << H) and isOneOf(&gs[start + 2], 1 << ZWJ)) {
        b.mergeClusters(start + 1, start + 3);
        std.mem.swap(Glyph, &gs[start + 1], &gs[start + 2]);
    }

    // 1. find the base consonant
    var base = end;
    var has_reph = false;
    {
        var limit = start;
        if (ip.rphf != 0 and start + 3 <= end and
            ((ip.config.reph_mode == .implicit and !isJoiner(&gs[start + 2])) or
                (ip.config.reph_mode == .explicit and gs[start + 2].cat == ZWJ)))
        {
            const g = [3]u16{ gs[start].gid, gs[start + 1].gid, if (ip.config.reph_mode == .explicit) gs[start + 2].gid else 0 };
            if (would(plan, ip, tag("rphf"), g[0..2]) or (ip.config.reph_mode == .explicit and would(plan, ip, tag("rphf"), g[0..3]))) {
                limit += 2;
                while (limit < end and isJoiner(&gs[limit])) limit += 1;
                base = start;
                has_reph = true;
            }
        } else if (ip.config.reph_mode == .log_repha and gs[start].cat == Repha) {
            limit += 1;
            while (limit < end and isJoiner(&gs[limit])) limit += 1;
            base = start;
            has_reph = true;
        }
        // starting from the end of the syllable, move backwards until a consonant is found
        // that has no below-base or post-base form
        var i = end;
        var seen_below = false;
        while (true) {
            i -= 1;
            if (isConsonant(&gs[i])) {
                if (gs[i].pos != POS_BELOW_C and (gs[i].pos != POS_POST_C or seen_below)) {
                    base = i;
                    break;
                }
                if (gs[i].pos == POS_BELOW_C) seen_below = true;
                base = i;
            } else {
                // a ZWJ after a halant stops the base search and requests an explicit half form
                if (start < i and gs[i].cat == ZWJ and gs[i - 1].cat == H) break;
            }
            if (i <= limit) break;
        }
        // no other consonant: the reph is not formed and Ra becomes the base
        if (has_reph and base == start and limit - base <= 2) has_reph = false;
    }

    for (gs[start..base]) |*gl| gl.pos = @min(POS_PRE_C, gl.pos);
    if (base < end) gs[base].pos = POS_BASE_C;
    if (has_reph) gs[start].pos = POS_RA_TO_BECOME_REPH;

    // old-spec fonts: move the first post-base halant after the last consonant
    if (ip.is_old_spec) {
        const disallow_double = script == ucd.sc_kannada;
        var i = base + 1;
        while (i < end) : (i += 1) {
            if (gs[i].cat != H) continue;
            var j = end - 1;
            while (j > i) : (j -= 1) {
                if (isConsonant(&gs[j]) or (disallow_double and gs[j].cat == H)) break;
            }
            if (gs[j].cat != H and j > i) moveForward(gs, i, j);
            break;
        }
    }

    // attach misc marks to the previous char so that they move with it
    {
        var last_pos: u8 = POS_START;
        var i = start;
        while (i < end) : (i += 1) {
            const fl: u32 = if (gs[i].cat < 32) @as(u32, 1) << @intCast(gs[i].cat) else 0;
            if (fl & (joiner_flags | (1 << N) | (1 << RS) | (1 << CM) | (1 << H)) != 0) {
                gs[i].pos = last_pos;
                if (gs[i].cat == H and gs[i].pos == POS_PRE_M) {
                    // the halant does not move with a left matra
                    var j = i;
                    while (j > start) : (j -= 1) {
                        if (gs[j - 1].pos != POS_PRE_M) {
                            gs[i].pos = gs[j - 1].pos;
                            break;
                        }
                    }
                }
            } else if (gs[i].pos != POS_SMVD) {
                if (gs[i].cat == MPst and i > start and gs[i - 1].cat == SM) gs[i - 1].pos = gs[i].pos;
                last_pos = gs[i].pos;
            }
        }
    }
    // post-base consonants own anything before them since the last consonant or matra
    {
        var last = base;
        var i = base + 1;
        while (i < end) : (i += 1) {
            if (isConsonant(&gs[i])) {
                var j = last + 1;
                while (j < i) : (j += 1) {
                    if (gs[j].pos < POS_SMVD) gs[j].pos = gs[i].pos;
                }
                last = i;
            } else if (gs[i].cat == M or gs[i].cat == MPst) last = i;
        }
    }

    {
        // stable sort by position; the syllable byte temporarily holds the original index
        const syllable = gs[start].syllable;
        for (gs[start..end], 0..) |*gl, k| gl.syllable = @intCast(@min(k, 255));
        var i = start + 1;
        while (i < end) : (i += 1) {
            var k = i;
            while (k > start and gs[k - 1].pos > gs[i].pos) k -= 1;
            if (k == i) continue;
            const t = gs[i];
            std.mem.copyBackwards(Glyph, gs[k + 1 .. i + 1], gs[k..i]);
            gs[k] = t;
        }
        // find the base again; flip a left-matra sequence
        var first_left = end;
        var last_left = end;
        base = end;
        i = start;
        while (i < end) : (i += 1) {
            if (gs[i].pos == POS_BASE_C) {
                base = i;
                break;
            } else if (gs[i].pos == POS_PRE_M) {
                if (first_left == end) first_left = i;
                last_left = i;
            }
        }
        if (first_left < last_left) {
            std.mem.reverse(Glyph, gs[first_left .. last_left + 1]);
            // reverse back nuktas etc.
            var s = first_left;
            var j = first_left;
            while (j <= last_left) : (j += 1) {
                if (gs[j].cat == M or gs[j].cat == MPst) {
                    std.mem.reverse(Glyph, gs[s .. j + 1]);
                    s = j + 1;
                }
            }
        }
        // merge clusters where the post-base order changed
        if (ip.is_old_spec or end - start > 127) {
            b.mergeClusters(base, end);
        } else {
            i = base;
            while (i < end) : (i += 1) {
                if (gs[i].syllable == 255) continue;
                var mn = i;
                var mx = i;
                var j = start + gs[i].syllable;
                var guard: usize = 0;
                while (j != i and j < end and guard < 256) : (guard += 1) {
                    mn = @min(mn, j);
                    mx = @max(mx, j);
                    const nx = start + gs[j].syllable;
                    gs[j].syllable = 255;
                    j = nx;
                }
                b.mergeClusters(@max(base, mn), mx + 1);
            }
        }
        for (gs[start..end]) |*gl| gl.syllable = syllable;
    }

    // masks
    {
        var i = start;
        while (i < end and gs[i].pos == POS_RA_TO_BECOME_REPH) : (i += 1) gs[i].mask |= ip.rphf;
        var mask = ip.half;
        if (!ip.is_old_spec and ip.config.blwf_mode == .pre_and_post) mask |= ip.blwf;
        for (gs[start..@min(base, end)]) |*gl| gl.mask |= mask;
        mask = ip.blwf | ip.abvf | ip.pstf;
        if (base + 1 < end) for (gs[base + 1 .. end]) |*gl| {
            gl.mask |= mask;
        };
    }
    if (ip.is_old_spec and script == ucd.sc_devanagari) {
        // old-spec eyelash Ra
        var i = start;
        while (i + 1 < base) : (i += 1) {
            if (gs[i].cat == Ra and gs[i + 1].cat == H and (i + 2 == base or gs[i + 2].cat != ZWJ)) {
                gs[i].mask |= ip.blwf;
                gs[i + 1].mask |= ip.blwf;
            }
        }
    }
    if (ip.pref != 0 and base + 2 < end) {
        // find a Halant,Ra sequence and mark it for pre-base-reordering processing
        var i = base + 1;
        while (i + 1 < end) : (i += 1) {
            const g = [2]u16{ gs[i].gid, gs[i + 1].gid };
            if (would(plan, ip, tag("pref"), &g)) {
                gs[i].mask |= ip.pref;
                gs[i + 1].mask |= ip.pref;
                break;
            }
        }
    }
    // ZWJ / ZWNJ effects
    {
        var i = start + 1;
        while (i < end) : (i += 1) {
            if (!isJoiner(&gs[i])) continue;
            const non_joiner = gs[i].cat == ZWNJ;
            var j = i;
            while (true) {
                j -= 1;
                // a ZWNJ disables HALF
                if (non_joiner) gs[j].mask &= ~ip.half;
                if (!(j > start and !isConsonant(&gs[j]))) break;
            }
        }
    }
}

// ---------------------------------------------------------------------------- final reordering

pub fn finalReordering(ip: *const IndicPlan, b: *ot.Buffer) void {
    const gs = b.g();
    var start: usize = 0;
    while (start < gs.len) {
        var end = start + 1;
        while (end < gs.len and gs[end].syllable == gs[start].syllable) end += 1;
        finalSyllable(ip, b, start, end);
        start = end;
    }
}

fn finalSyllable(ip: *const IndicPlan, b: *ot.Buffer, start: usize, end: usize) void {
    const gs = b.g();
    const script = ip.config.script;
    // recover the halant category lost to ligation + multiplication
    if (ip.virama_gid != 0) {
        for (gs[start..end]) |*gl| {
            if (gl.gid == ip.virama_gid and gl.ligated() and gl.multiplied()) {
                gl.cat = H;
                gl.props &= ~(Glyph.LIGATED | Glyph.MULTIPLIED);
            }
        }
    }
    var try_pref = ip.pref != 0;

    // find the base again
    var base = start;
    while (base < end) : (base += 1) {
        if (gs[base].pos < POS_BASE_C) continue;
        if (try_pref and base + 1 < end) {
            var i = base + 1;
            while (i < end) : (i += 1) {
                if (gs[i].mask & ip.pref == 0) continue;
                if (!(gs[i].props & Glyph.SUBSTITUTED != 0 and gs[i].ligatedAndDidntMultiply())) {
                    // a 'pref' candidate that did not form: the base is around here
                    base = i;
                    while (base < end and isHalant(&gs[base])) base += 1;
                    if (base < end) gs[base].pos = POS_BASE_C;
                    try_pref = false;
                }
                break;
            }
            if (base == end) break;
        }
        if (script == ucd.sc_malayalam) {
            // skip over unformed below- (but not post-) forms
            var i = base + 1;
            while (i < end) : (i += 1) {
                while (i < end and isJoiner(&gs[i])) i += 1;
                if (i == end or !isHalant(&gs[i])) break;
                i += 1;
                while (i < end and isJoiner(&gs[i])) i += 1;
                if (i < end and isConsonant(&gs[i]) and gs[i].pos == POS_BELOW_C) {
                    base = i;
                    gs[base].pos = POS_BASE_C;
                }
            }
        }
        if (start < base and gs[base].pos > POS_BASE_C) base -= 1;
        break;
    }
    if (base == end and start < base and isOneOf(&gs[base - 1], 1 << ZWJ)) base -= 1;
    if (base < end) {
        while (start < base and isOneOf(&gs[base], (1 << N) | (1 << H))) base -= 1;
    }

    // reorder pre-base matras: after the last standalone halant before the base
    if (start + 1 < end and start < base) {
        var new_pos: usize = if (base == end) base - 2 else base - 1;
        if (base == end and base < start + 2) new_pos = start;
        if (script != ucd.sc_malayalam and script != ucd.sc_tamil) {
            while (true) {
                while (new_pos > start and !isOneOf(&gs[new_pos], (1 << M) | (1 << MPst) | (1 << H))) new_pos -= 1;
                // only proceed if the halant does not belong to the matra itself
                if (isHalant(&gs[new_pos]) and gs[new_pos].pos != POS_PRE_M) {
                    // if ZWJ follows this halant, the matra is NOT repositioned after it
                    if (new_pos + 1 < end and gs[new_pos + 1].cat == ZWJ and new_pos > start) {
                        new_pos -= 1;
                        continue;
                    }
                } else new_pos = start; // no move
                break;
            }
        }
        if (start < new_pos and gs[new_pos].pos != POS_PRE_M) {
            var i = new_pos;
            while (i > start) : (i -= 1) {
                if (gs[i - 1].pos != POS_PRE_M) continue;
                const old_pos = i - 1;
                if (old_pos < base and base <= new_pos) base -= 1;
                moveForward(gs, old_pos, new_pos);
                b.mergeClusters(new_pos, @min(end, base + 1));
                new_pos -= 1;
            }
        } else {
            var i = start;
            while (i < base) : (i += 1) {
                if (gs[i].pos == POS_PRE_M) {
                    b.mergeClusters(i, @min(end, base + 1));
                    break;
                }
            }
        }
    }

    // reorder reph
    if (start + 1 < end and gs[start].pos == POS_RA_TO_BECOME_REPH and
        ((gs[start].cat == Repha) != gs[start].ligatedAndDidntMultiply()))
    {
        const reph_pos = ip.config.reph_pos;
        var new_reph: usize = undefined;
        find: {
            if (reph_pos != .after_post) {
                // 2. after the first explicit halant between the first post-reph consonant and
                // the last main consonant
                new_reph = start + 1;
                while (new_reph < base and !isHalant(&gs[new_reph])) new_reph += 1;
                if (new_reph < base and isHalant(&gs[new_reph])) {
                    if (new_reph + 1 < base and isJoiner(&gs[new_reph + 1])) new_reph += 1;
                    break :find;
                }
                // 3. after the main consonant
                if (reph_pos == .after_main) {
                    new_reph = base;
                    while (new_reph + 1 < end and gs[new_reph + 1].pos <= POS_AFTER_MAIN) new_reph += 1;
                    if (new_reph < end) break :find;
                }
                // 4. before the post-base consonant forms
                if (reph_pos == .after_sub) {
                    new_reph = base;
                    while (new_reph + 1 < end) : (new_reph += 1) {
                        const p = gs[new_reph + 1].pos;
                        if (p == POS_POST_C or p == POS_AFTER_POST or p == POS_SMVD) break;
                    }
                    if (new_reph < end) break :find;
                }
            }
            // 5.
            new_reph = start + 1;
            while (new_reph < base and !isHalant(&gs[new_reph])) new_reph += 1;
            if (new_reph < base and isHalant(&gs[new_reph])) {
                if (new_reph + 1 < base and isJoiner(&gs[new_reph + 1])) new_reph += 1;
                break :find;
            }
            // 6. the end of the syllable
            new_reph = end - 1;
            while (new_reph > start and gs[new_reph].pos == POS_SMVD) new_reph -= 1;
            // before a Matra,Halant sequence so that it can interact with the matra
            if (isHalant(&gs[new_reph])) {
                var i = base + 1;
                while (i < new_reph) : (i += 1) {
                    if (gs[i].cat == M or gs[i].cat == MPst) {
                        new_reph -= 1;
                    }
                }
            }
        }
        if (new_reph > start and new_reph < end) {
            b.mergeClusters(start, new_reph + 1);
            moveForward(gs, start, new_reph);
            if (start < base and base <= new_reph) base -= 1;
        }
    }

    // reorder pre-base-reordering consonants
    if (try_pref and base + 1 < end) {
        var i = base + 1;
        while (i < end) : (i += 1) {
            if (gs[i].mask & ip.pref == 0) continue;
            if (gs[i].ligatedAndDidntMultiply()) {
                var new_pos = base;
                if (script != ucd.sc_malayalam and script != ucd.sc_tamil) {
                    while (new_pos > start and !isOneOf(&gs[new_pos - 1], (1 << M) | (1 << MPst) | (1 << H))) new_pos -= 1;
                }
                if (new_pos > start and isHalant(&gs[new_pos - 1])) {
                    if (new_pos < end and isJoiner(&gs[new_pos])) new_pos += 1;
                }
                const old_pos = i;
                if (new_pos < old_pos) {
                    b.mergeClusters(new_pos, old_pos + 1);
                    const t = gs[old_pos];
                    std.mem.copyBackwards(Glyph, gs[new_pos + 1 .. old_pos + 1], gs[new_pos..old_pos]);
                    gs[new_pos] = t;
                    if (new_pos <= base and base < old_pos) base += 1;
                }
            }
            break;
        }
    }

    // 'init' applies to a left matra at a word start
    if (gs[start].pos == POS_PRE_M) {
        var word_start = start == 0;
        if (!word_start) {
            const gc = gs[start - 1].uprops & Glyph.U_GC;
            // letters, marks, format and unassigned characters continue a word
            word_start = !(gc == 1 or gc == 2 or gc == 3 or gc == 4 or gc == 5 or gc == 7);
        }
        if (word_start) gs[start].mask |= ip.init_mask;
    }
}
