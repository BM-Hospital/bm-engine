//! Arabic-family shaper pieces (port of HarfBuzz `hb-ot-shaper-arabic`): joining analysis that
//! selects the isol / fina / medi / init form of every letter, and the reordering of
//! "modifier combining marks". Covers the scripts whose joining data lives in U+0600..U+08FF
//! (Arabic, Syriac without the Alaph / Dalath-Rish special forms, N'Ko, Mandaic).
//! Not ported: `stch` stretching, presentation-form fallback for fonts without GSUB.
const std = @import("std");
const ot = @import("ot.zig");
const uni = @import("unicode.zig");
const Glyph = ot.Glyph;
const tag = ot.tag;

pub const form_tags = [7]u32{ tag("isol"), tag("fina"), tag("fin2"), tag("fin3"), tag("medi"), tag("med2"), tag("init") };
const ISOL = 0;
const FINA = 1;
const MEDI = 4;
const INIT = 6;
const NONE = 7;

const Entry = struct { prev: u8, cur: u8, next: u8 };
/// Rows: state (0 prev U, 1 prev R / isolated, 2 prev D/L isolated, 3 prev D final);
/// columns: joining type U, L, R, D.
const table = [4][4]Entry{
    .{ .{ .prev = NONE, .cur = NONE, .next = 0 }, .{ .prev = NONE, .cur = ISOL, .next = 2 }, .{ .prev = NONE, .cur = ISOL, .next = 1 }, .{ .prev = NONE, .cur = ISOL, .next = 2 } },
    .{ .{ .prev = NONE, .cur = NONE, .next = 0 }, .{ .prev = NONE, .cur = ISOL, .next = 2 }, .{ .prev = NONE, .cur = ISOL, .next = 1 }, .{ .prev = NONE, .cur = ISOL, .next = 2 } },
    .{ .{ .prev = NONE, .cur = NONE, .next = 0 }, .{ .prev = NONE, .cur = ISOL, .next = 2 }, .{ .prev = INIT, .cur = FINA, .next = 1 }, .{ .prev = INIT, .cur = FINA, .next = 3 } },
    .{ .{ .prev = NONE, .cur = NONE, .next = 0 }, .{ .prev = NONE, .cur = ISOL, .next = 2 }, .{ .prev = MEDI, .cur = FINA, .next = 1 }, .{ .prev = MEDI, .cur = FINA, .next = 3 } },
};

/// Runs the joining state machine and ORs the mask of the chosen form feature into each glyph.
pub fn setupMasks(b: *ot.Buffer, masks: *const [7]u32) void {
    const gs = b.g();
    var state: u8 = 0;
    var prev: ?usize = null;
    for (gs, 0..) |*gl, i| {
        gl.cat = NONE;
        const jt = uni.joiningType(gl.cp);
        if (jt == .t) continue;
        const e = table[state][@intFromEnum(jt)];
        if (e.prev != NONE) {
            if (prev) |p| gs[p].cat = e.prev;
        }
        gl.cat = e.cur;
        prev = i;
        state = e.next;
    }
    for (gs) |*gl| {
        if (gl.cat < 7) gl.mask |= masks[gl.cat];
    }
}

fn isModifierMark(cp: u21) bool {
    return switch (cp) {
        0x0654, 0x0655, 0x0658, 0x06dc, 0x06e3, 0x06e7, 0x06e8, 0x08ca, 0x08cb, 0x08cd, 0x08ce, 0x08cf, 0x08d3, 0x08f3 => true,
        else => false,
    };
}

/// Moves modifier combining marks (hamza above / below, ...) in front of the other marks of
/// their class (Unicode TR53). `normalize.ReorderHook`.
pub fn reorderMarks(b: *ot.Buffer, start_in: usize, end: usize) void {
    const gs = b.g();
    var start = start_in;
    var i = start;
    var cc: u8 = 220;
    while (true) : (cc += 10) {
        while (i < end and gs[i].ccc < cc) i += 1;
        if (i == end) break;
        if (gs[i].ccc <= cc) {
            var j = i;
            while (j < end and gs[j].ccc == cc and isModifierMark(gs[j].cp)) j += 1;
            if (j != i and j - i <= 32) {
                var tmp: [32]Glyph = undefined;
                const n = j - i;
                b.mergeClusters(start, j);
                @memcpy(tmp[0..n], gs[i..j]);
                std.mem.copyBackwards(Glyph, gs[start + n .. j], gs[start..i]);
                @memcpy(gs[start .. start + n], tmp[0..n]);
                // renumber so that the sequence stays sorted
                const new_cc: u8 = if (cc == 220) 22 else 26;
                const new_start = start + n;
                while (start < new_start) : (start += 1) gs[start].ccc = new_cc;
                i = j;
            }
        }
        if (cc == 230) break;
    }
}
