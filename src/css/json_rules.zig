//! takumi rule OBJECTS (`css` render option entries: `StyleRule`, `AnimationRule`, `MediaRule`,
//! `SupportsRule`, `LayerRule`) and the deprecated `keyframes` option (`KeyframesMap` /
//! `KeyframesRuleList`), arriving as a parsed JSON DOM. Duck-typed over any union with tags
//! `.null .bool .number .string .array .object` where `.object` is a slice of `{ key, value }`
//! (like `src/json.zig`), so this module does not import the project's JSON parser.
//! Like takumi (`css_source.rs`), a rule object is validated and written out as CSS text, which is
//! then parsed like any stylesheet text. Invalid objects are an error (takumi fails the render).
const std = @import("std");
const tk = @import("tokenizer.zig");
const sel = @import("selector.zig");
const media = @import("media.zig");
const sheet_mod = @import("sheet.zig");
const Allocator = std.mem.Allocator;
const Vec = @import("vec.zig").Vec;
const Declaration = sheet_mod.Declaration;

pub const Error = error{ InvalidRule, OutOfMemory };

const max_depth = 32;

/// Validates a `css` entry (string or rule object) and appends its CSS text to `buf`.
/// Use this to build ONE text from all entries (exactly what takumi parses), then call `parse` once.
pub fn writeCssInput(arena: Allocator, buf: *std.ArrayList(u8), v: anytype) Error!void {
    return writeEntry(arena, buf, v, 0);
}

fn writeEntry(arena: Allocator, buf: *std.ArrayList(u8), v: anytype, depth: u32) Error!void {
    if (depth > max_depth) return error.InvalidRule;
    switch (v) {
        .string => |s| return buf.appendSlice(arena, s),
        .object => |members| {
            if (get(members, "selector") != null) return writeStyleRule(arena, buf, members, depth);
            if (get(members, "keyframes") != null) return writeAnimation(arena, buf, members);
            if (get(members, "media")) |q| {
                try onlyKeys(members, &.{ "media", "rules" });
                const text = str(q) orelse return error.InvalidRule;
                if (!balanced(text, true)) return error.InvalidRule;
                return writeGroup(arena, buf, "@media ", text, get(members, "rules") orelse return error.InvalidRule, depth);
            }
            if (get(members, "supports")) |q| {
                try onlyKeys(members, &.{ "supports", "rules" });
                const text = str(q) orelse return error.InvalidRule;
                if ((try media.parseSupports(arena, text, 0, text.len)) == null) return error.InvalidRule;
                return writeGroup(arena, buf, "@supports ", text, get(members, "rules") orelse return error.InvalidRule, depth);
            }
            if (get(members, "layer")) |q| {
                try onlyKeys(members, &.{ "layer", "rules" });
                const text = str(q) orelse return error.InvalidRule;
                if (!validLayerName(text)) return error.InvalidRule;
                const rules = get(members, "rules");
                if (rules == null or rules.? == .null) {
                    try buf.appendSlice(arena, "@layer ");
                    try buf.appendSlice(arena, text);
                    return buf.append(arena, ';');
                }
                return writeGroup(arena, buf, "@layer ", text, rules.?, depth);
            }
            return error.InvalidRule;
        },
        else => return error.InvalidRule,
    }
}

fn get(members: anytype, key: []const u8) ?@TypeOf(members[0].value) {
    var i = members.len;
    while (i > 0) {
        i -= 1;
        if (tk.seq(members[i].key, key)) return members[i].value;
    }
    return null;
}

fn str(v: anytype) ?[]const u8 {
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

fn onlyKeys(members: anytype, allowed: []const []const u8) Error!void {
    outer: for (members) |m| {
        for (allowed) |a| if (tk.seq(m.key, a)) continue :outer;
        return error.InvalidRule;
    }
}

fn writeGroup(arena: Allocator, buf: *std.ArrayList(u8), at: []const u8, prelude: []const u8, rules: anytype, depth: u32) Error!void {
    const items = switch (rules) {
        .array => |a| a,
        else => return error.InvalidRule,
    };
    try buf.appendSlice(arena, at);
    try buf.appendSlice(arena, prelude);
    try buf.append(arena, '{');
    for (items) |it| try writeEntry(arena, buf, it, depth + 1);
    try buf.append(arena, '}');
}

/// No top-level `;`, `{`, `}`, stray closers or bad tokens (so it cannot close its rule/declaration).
fn balanced(text: []const u8, allow_empty: bool) bool {
    var t = tk.Tokenizer.init(text);
    var any = false;
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .eof => return any or allow_empty,
            .ws => {},
            .semicolon, .lbrace, .rbrace, .rparen, .rbracket, .bad_string, .bad_url => return false,
            .lparen, .lbracket, .function => {
                any = true;
                const save = t.pos;
                const end = tk.skipBlock(&t, tok.kind);
                if (t.pos == end) return false; // unterminated
                // inner text must not contain unbalanced `{}`/`;`-free requirement does not apply
                _ = save;
            },
            else => any = true,
        }
    }
}

fn validLayerName(text: []const u8) bool {
    var t = tk.Tokenizer.init(text);
    var need = true;
    var started = false;
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .eof => return started and !need,
            .ws => if (started and need) return false,
            .ident => {
                if (!need) return false;
                need = false;
                started = true;
                const save = t.pos;
                const d = t.next();
                if (d.isDelim('.')) need = true else t.pos = save;
            },
            else => return false,
        }
    }
}

fn writeStyleRule(arena: Allocator, buf: *std.ArrayList(u8), members: anytype, depth: u32) Error!void {
    if (depth > max_depth) return error.InvalidRule;
    try onlyKeys(members, &.{ "selector", "style", "rules" });
    const selector = str(get(members, "selector").?) orelse return error.InvalidRule;
    if ((try sel.parseList(arena, selector, 0, selector.len, .{ .nesting = true }, null)) == null) return error.InvalidRule;
    if (!balanced(selector, false)) return error.InvalidRule;
    try buf.appendSlice(arena, selector);
    try buf.append(arena, '{');
    if (get(members, "style")) |st| try writeStyle(arena, buf, st);
    if (get(members, "rules")) |rs| switch (rs) {
        .array => |a| for (a) |r| {
            const ms = switch (r) {
                .object => |o| o,
                else => return error.InvalidRule,
            };
            if (get(ms, "selector") == null) return error.InvalidRule;
            try writeStyleRule(arena, buf, ms, depth + 1);
        },
        .null => {},
        else => return error.InvalidRule,
    };
    try buf.append(arena, '}');
}

/// Writes a JSON style object (`{ camelCase: value }`) as `name:value;` declarations.
fn writeStyle(arena: Allocator, buf: *std.ArrayList(u8), st: anytype) Error!void {
    const members = switch (st) {
        .object => |o| o,
        .null => return,
        else => return error.InvalidRule,
    };
    for (members) |m| {
        var num_buf: [40]u8 = undefined;
        const value: []const u8 = switch (m.value) {
            .null => continue,
            .string => |s| s,
            .number => |n| fmtNumber(&num_buf, @floatCast(n)),
            else => return error.InvalidRule,
        };
        const custom = std.mem.startsWith(u8, m.key, "--");
        if (!custom and !balanced(value, false)) return error.InvalidRule;
        // takumi parses the value with the property parser, which rejects a trailing `!important` (EMPIRICAL)
        if (!custom and hasImportant(value)) return error.InvalidRule;
        if (custom and !balanced(value, true)) return error.InvalidRule;
        try appendCssName(arena, buf, m.key);
        try buf.append(arena, ':');
        try buf.appendSlice(arena, value);
        try buf.append(arena, ';');
    }
}

/// takumi `Declaration::css_name`: names with `--` or `-` are kept, camelCase becomes kebab-case.
fn appendCssName(arena: Allocator, buf: *std.ArrayList(u8), name: []const u8) error{OutOfMemory}!void {
    if (std.mem.indexOfScalar(u8, name, '-') != null) return buf.appendSlice(arena, name);
    for (name) |c| {
        if (c >= 'A' and c <= 'Z') {
            try buf.append(arena, '-');
            try buf.append(arena, c + 32);
        } else try buf.append(arena, c);
    }
}

fn camelToKebab(arena: Allocator, name: []const u8) error{OutOfMemory}![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    try appendCssName(arena, &buf, name);
    return buf.items;
}

fn writeAnimation(arena: Allocator, buf: *std.ArrayList(u8), members: anytype) Error!void {
    try onlyKeys(members, &.{ "keyframes", "steps" });
    const name = str(get(members, "keyframes").?) orelse return error.InvalidRule;
    {
        var t = tk.Tokenizer.init(name);
        var a = t.next();
        while (a.kind == .ws) a = t.next();
        if (a.kind != .ident) return error.InvalidRule;
        var b = t.next();
        while (b.kind == .ws) b = t.next();
        if (b.kind != .eof) return error.InvalidRule;
    }
    try buf.appendSlice(arena, "@keyframes ");
    try buf.appendSlice(arena, name);
    try buf.append(arena, '{');
    if (get(members, "steps")) |steps| switch (steps) {
        .array => |a| for (a) |step| {
            const ms = switch (step) {
                .object => |o| o,
                else => return error.InvalidRule,
            };
            try onlyKeys(ms, &.{ "offset", "style" });
            const off = str(get(ms, "offset") orelse return error.InvalidRule) orelse return error.InvalidRule;
            if ((try sheet_mod.parseKeyframeOffsets(arena, off, 0, off.len)) == null) return error.InvalidRule;
            try buf.appendSlice(arena, off);
            try buf.append(arena, '{');
            if (get(ms, "style")) |s| try writeStyle(arena, buf, s);
            try buf.append(arena, '}');
        },
        .null => {},
        else => return error.InvalidRule,
    };
    try buf.append(arena, '}');
}

/// Formats a JSON number for CSS text without std.fmt float code: integers exactly (|x| < 2^53),
/// otherwise up to 6 fractional digits, trailing zeros trimmed.
pub fn fmtNumber(out: *[40]u8, x0: f64) []const u8 {
    var x = x0;
    if (x != x) return "0";
    var o: usize = 0;
    if (x < 0) {
        out[o] = '-';
        o += 1;
        x = -x;
    }
    if (x > 1e15) x = 1e15;
    var ip: u64 = @intFromFloat(@floor(x));
    var frac = x - @floor(x);
    var scaled: u64 = @intFromFloat(@round(frac * 1e6));
    if (scaled >= 1_000_000) {
        scaled = 0;
        ip += 1;
    }
    frac = 0;
    var digits: [20]u8 = undefined;
    var n: usize = 0;
    var v = ip;
    while (true) {
        digits[n] = @intCast('0' + v % 10);
        n += 1;
        v /= 10;
        if (v == 0) break;
    }
    while (n > 0) {
        n -= 1;
        out[o] = digits[n];
        o += 1;
    }
    if (scaled != 0) {
        out[o] = '.';
        o += 1;
        var div: u64 = 100_000;
        var rest = scaled;
        while (rest != 0 and div != 0) {
            out[o] = @intCast('0' + rest / div);
            o += 1;
            rest %= div;
            div /= 10;
        }
    }
    if (o == 1 and out[0] == '-') return "0";
    if (o == 2 and out[0] == '-' and out[1] == '0') return "0";
    return out[0..o];
}

/// Parses `css` text produced by `writeCssInput` for one entry and appends it to `sheet`.
pub fn addRuleJson(arena: Allocator, sheet: *sheet_mod.Stylesheet, v: anytype) Error!void {
    var buf: std.ArrayList(u8) = .empty;
    try writeCssInput(arena, &buf, v);
    try sheet_mod.parse(arena, buf.items, sheet);
}

/// Splits a trailing `!important` off a style-object value string.
fn splitImportant(arena: Allocator, s: []const u8) error{OutOfMemory}!struct { []const u8, bool } {
    const ds = try sheet_mod.parseDeclarations(arena, try std.mem.concat(arena, u8, &.{ "x:", s }));
    if (ds.len == 1) return .{ ds[0].value, ds[0].important };
    return .{ std.mem.trim(u8, s, " \t\r\n"), false };
}

/// Style object of the deprecated keyframes option (takumi `StyleDeclarationBlock` deserialization):
/// camelCase keys only (kebab-case keys are ignored, `--custom` kept), string/number values.
fn styleObjectDecls(arena: Allocator, st: anytype) Error![]const Declaration {
    const members = switch (st) {
        .object => |o| o,
        .null => return &.{},
        else => return error.InvalidRule,
    };
    var out: Vec(Declaration) = .empty;
    for (members) |m| {
        const custom = std.mem.startsWith(u8, m.key, "--");
        if (!custom and std.mem.indexOfScalar(u8, m.key, '-') != null) continue;
        var num_buf: [40]u8 = undefined;
        const raw: []const u8 = switch (m.value) {
            .null => continue,
            .string => |s| s,
            .number => |n| try arena.dupe(u8, fmtNumber(&num_buf, @floatCast(n))),
            else => return error.InvalidRule,
        };
        const sv = try splitImportant(arena, raw);
        try out.append(arena, .{ .name = if (custom) m.key else try camelToKebab(arena, m.key), .value = sv[0], .important = false });
    }
    return out.items;
}

fn lessKey(members: anytype, a: u32, b: u32) bool {
    return std.mem.order(u8, members[a].key, members[b].key) == .lt;
}

fn sortedIdx(arena: Allocator, members: anytype) error{OutOfMemory}![]u32 {
    const idx = try arena.alloc(u32, members.len);
    for (idx, 0..) |*x, i| x.* = @intCast(i);
    // insertion sort (maps are small; avoids another generic sort instantiation)
    var i: usize = 1;
    while (i < idx.len) : (i += 1) {
        const x = idx[i];
        var j = i;
        while (j > 0 and lessKey(members, x, idx[j - 1])) : (j -= 1) idx[j] = idx[j - 1];
        idx[j] = x;
    }
    return idx;
}

/// Deprecated `keyframes` render option: `KeyframesMap` (`{ name: { "from, 50%": style } }`, keys
/// sorted like takumi's `sorted_entries`) or `KeyframesRuleList` (`[{ name, keyframes: [{ offsets:
/// number[] (0..1), declarations: style }] }]`). Appended to `sheet.extra_keyframes` (they win over
/// `@keyframes` of the same name).
pub fn addKeyframesJson(arena: Allocator, sheet: *sheet_mod.Stylesheet, v: anytype) Error!void {
    switch (v) {
        .null => return,
        .array => |rules| for (rules) |r| {
            const ms = switch (r) {
                .object => |o| o,
                else => return error.InvalidRule,
            };
            const name = str(get(ms, "name") orelse return error.InvalidRule) orelse return error.InvalidRule;
            var frames: Vec(sheet_mod.Keyframe) = .empty;
            const kfs = get(ms, "keyframes") orelse return error.InvalidRule;
            const arr = switch (kfs) {
                .array => |a| a,
                else => return error.InvalidRule,
            };
            for (arr) |kf| {
                const km = switch (kf) {
                    .object => |o| o,
                    else => return error.InvalidRule,
                };
                const offs = switch (get(km, "offsets") orelse return error.InvalidRule) {
                    .array => |a| a,
                    else => return error.InvalidRule,
                };
                const decls = try styleObjectDecls(arena, get(km, "declarations") orelse return error.InvalidRule);
                for (offs) |o| {
                    const f: f32 = switch (o) {
                        .number => |n| @floatCast(n),
                        else => return error.InvalidRule,
                    };
                    try frames.append(arena, .{ .offset = f, .declarations = decls });
                }
            }
            try sheet.extra_keyframes.append(arena, .{ .name = try arena.dupe(u8, name), .frames = frames.items });
        },
        .object => |names| {
            const order = try sortedIdx(arena, names);
            for (order) |ni| {
                const entry = names[ni];
                const stages = switch (entry.value) {
                    .object => |o| o,
                    else => return error.InvalidRule,
                };
                var frames: Vec(sheet_mod.Keyframe) = .empty;
                const sorder = try sortedIdx(arena, stages);
                for (sorder) |si| {
                    const st = stages[si];
                    const trimmed = std.mem.trim(u8, st.key, " \t\r\n,");
                    if (trimmed.len == 0) return error.InvalidRule;
                    const offs = (try sheet_mod.parseKeyframeOffsets(arena, st.key, 0, st.key.len)) orelse return error.InvalidRule;
                    const decls = try styleObjectDecls(arena, st.value);
                    for (offs) |o| try frames.append(arena, .{ .offset = o, .declarations = decls });
                }
                try sheet.extra_keyframes.append(arena, .{ .name = try arena.dupe(u8, entry.key), .frames = frames.items });
            }
        },
        else => return error.InvalidRule,
    }
}

fn hasImportant(v: []const u8) bool {
    var t = tk.Tokenizer.init(v);
    var bang = false;
    while (true) {
        const tok = t.next();
        switch (tok.kind) {
            .eof => return false,
            .ws => {},
            else => {
                if (bang and tok.isIdent(v, "important")) return true;
                bang = tok.isDelim('!');
            },
        }
    }
}
