//! Tiny CSS component-value tokenizer shared by every property parser.
//! Never allocates; functions / parenthesised blocks / bracket blocks are returned as one token whose
//! `args` is the (balanced, string-aware) inner text, which callers tokenize again with a fresh `Lexer`.
//! Recursion into nested blocks is done by the callers, which bound their depth.
const std = @import("std");
// NOTE: a private copy of parseNumber (src/json.zig) so `zig test src/style/style.zig` works standalone
// (importing ../json.zig is outside the module path when this directory is the test root).

pub const Error = error{ InvalidStyleValue, OutOfMemory };

pub const Kind = enum(u8) {
    eof,
    ident,
    function, // text = name, args = inside of (...)
    block, // ( ... ) ; args = inside
    bracket, // [ ... ] ; args = inside
    number,
    percentage, // num = value as written (50% -> 50)
    dimension, // num + text = unit
    string, // text = raw contents (escapes not processed)
    hash, // text = name after '#'
    comma,
    slash,
    delim, // text = the single byte
};

pub const Token = struct {
    kind: Kind = .eof,
    text: []const u8 = "",
    args: []const u8 = "",
    num: f32 = 0,
    /// Number/dimension written with integer syntax (no '.' and no exponent).
    int: bool = false,

    pub noinline fn isIdent(t: *const Token, name: []const u8) bool {
        return t.kind == .ident and std.ascii.eqlIgnoreCase(t.text, name);
    }
    pub noinline fn isFunc(t: *const Token, name: []const u8) bool {
        return t.kind == .function and std.ascii.eqlIgnoreCase(t.text, name);
    }
    pub fn isDelim(t: Token, c: u8) bool {
        return t.kind == .delim and t.text.len == 1 and t.text[0] == c;
    }
};

pub const Lexer = struct {
    s: []const u8,
    i: usize = 0,
    /// A pre-made first token (used for JSON numbers, which are not re-stringified).
    forced: ?Token = null,

    pub fn init(s: []const u8) Lexer {
        return .{ .s = s };
    }

    pub fn initNumber(v0: f64) Lexer {
        const v = sane(v0);
        return .{ .s = "", .forced = .{ .kind = .number, .num = v, .int = @floor(v) == v and @abs(v) < 2147483648.0 } };
    }

    fn skipWs(l: *Lexer) void {
        while (l.i < l.s.len) {
            const c = l.s[l.i];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 12) {
                l.i += 1;
            } else if (c == '/' and l.i + 1 < l.s.len and l.s[l.i + 1] == '*') {
                var j = l.i + 2;
                while (j + 1 < l.s.len and !(l.s[j] == '*' and l.s[j + 1] == '/')) j += 1;
                l.i = @min(j + 2, l.s.len);
            } else return;
        }
    }

    pub fn atEnd(l: *Lexer) bool {
        if (l.forced != null) return false;
        l.skipWs();
        return l.i >= l.s.len;
    }

    pub fn peek(l: *Lexer) Token {
        var c = l.*;
        return c.next();
    }

    /// Returns the next token (never fails: unknown bytes become `.delim`).
    pub fn next(l: *Lexer) Token {
        if (l.forced) |f| {
            l.forced = null;
            return f;
        }
        l.skipWs();
        const s = l.s;
        if (l.i >= s.len) return .{ .kind = .eof };
        return l.lex();
    }

    fn lex(l: *Lexer) Token {
        const s = l.s;
        const c = s[l.i];
        if (startsNumber(s, l.i)) {
            const r = parseNumber(s[l.i..]) orelse {
                l.i += 1;
                return .{ .kind = .delim, .text = s[l.i - 1 .. l.i] };
            };
            const numtext = s[l.i .. l.i + r.len];
            l.i += r.len;
            const is_int = std.mem.indexOfAny(u8, numtext, ".eE") == null;
            const v: f32 = sane(r.value);
            if (l.i < s.len and s[l.i] == '%') {
                l.i += 1;
                return .{ .kind = .percentage, .num = v, .int = is_int };
            }
            if (startsIdent(s, l.i)) {
                const unit0 = l.i;
                l.consumeName();
                return .{ .kind = .dimension, .num = v, .int = is_int, .text = s[unit0..l.i] };
            }
            return .{ .kind = .number, .num = v, .int = is_int };
        }
        if (startsIdent(s, l.i)) {
            const n0 = l.i;
            l.consumeName();
            const name = s[n0..l.i];
            if (l.i < s.len and s[l.i] == '(') {
                l.i += 1;
                return .{ .kind = .function, .text = name, .args = l.consumeBlock(')') };
            }
            return .{ .kind = .ident, .text = name };
        }
        switch (c) {
            '"', '\'' => {
                l.i += 1;
                const b = l.i;
                while (l.i < s.len and s[l.i] != c) : (l.i += 1) {
                    if (s[l.i] == '\\') l.i += 1;
                }
                const e = @min(l.i, s.len);
                if (l.i < s.len) l.i += 1 else l.i = s.len;
                return .{ .kind = .string, .text = s[b..e] };
            },
            '#' => {
                l.i += 1;
                const b = l.i;
                while (l.i < s.len and isNameChar(s[l.i])) l.i += 1;
                if (l.i == b) return .{ .kind = .delim, .text = s[b - 1 .. b] };
                return .{ .kind = .hash, .text = s[b..l.i] };
            },
            '(' => {
                l.i += 1;
                return .{ .kind = .block, .args = l.consumeBlock(')') };
            },
            '[' => {
                l.i += 1;
                return .{ .kind = .bracket, .args = l.consumeBlock(']') };
            },
            ',' => {
                l.i += 1;
                return .{ .kind = .comma };
            },
            '/' => {
                l.i += 1;
                return .{ .kind = .slash };
            },
            else => {
                l.i += 1;
                return .{ .kind = .delim, .text = s[l.i - 1 .. l.i] };
            },
        }
    }

    fn consumeName(l: *Lexer) void {
        while (l.i < l.s.len and isNameChar(l.s[l.i])) l.i += 1;
    }

    /// Consumes up to the matching `close` (nesting of (), [] and strings respected). Unterminated
    /// blocks run to the end of input (CSS auto-closes at EOF).
    fn consumeBlock(l: *Lexer, close: u8) []const u8 {
        _ = close;
        const s = l.s;
        const b = l.i;
        var depth: usize = 0;
        while (l.i < s.len) : (l.i += 1) {
            const c = s[l.i];
            switch (c) {
                '(', '[' => depth += 1,
                ')', ']' => {
                    if (depth == 0) {
                        const e = l.i;
                        l.i += 1;
                        return s[b..e];
                    }
                    depth -= 1;
                },
                '"', '\'' => {
                    l.i += 1;
                    while (l.i < s.len and s[l.i] != c) : (l.i += 1) {
                        if (s[l.i] == '\\') l.i += 1;
                    }
                    if (l.i >= s.len) break;
                },
                '\\' => l.i += 1,
                else => {},
            }
        }
        l.i = s.len;
        return s[b..];
    }
};

/// f64 -> f32 with NaN -> 0 and clamping to +-1e30 (keeps all later arithmetic finite).
fn sane(x: f64) f32 {
    if (x != x) return 0;
    return @floatCast(std.math.clamp(x, -1.0e30, 1.0e30));
}

pub fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c >= 0x80;
}

fn isNameStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c >= 0x80;
}

fn startsIdent(s: []const u8, i: usize) bool {
    if (i >= s.len) return false;
    if (isNameStart(s[i])) return true;
    if (s[i] == '-' and i + 1 < s.len) return isNameStart(s[i + 1]) or s[i + 1] == '-';
    return false;
}

fn startsNumber(s: []const u8, i_: usize) bool {
    var i = i_;
    if (s[i] == '+' or s[i] == '-') i += 1;
    if (i >= s.len) return false;
    if (std.ascii.isDigit(s[i])) return true;
    return s[i] == '.' and i + 1 < s.len and std.ascii.isDigit(s[i + 1]);
}

test "tokenizer basics" {
    var l = Lexer.init("  calc(100% - (2 * 3px)) -webkit-box #fff 'a b' 1.5em -.5 +3 50%/2, [a] /*c*/ x");
    var t = l.next();
    try std.testing.expect(t.isFunc("calc"));
    try std.testing.expectEqualStrings("100% - (2 * 3px)", t.args);
    t = l.next();
    try std.testing.expect(t.isIdent("-webkit-box"));
    t = l.next();
    try std.testing.expect(t.kind == .hash and std.mem.eql(u8, t.text, "fff"));
    t = l.next();
    try std.testing.expect(t.kind == .string and std.mem.eql(u8, t.text, "a b"));
    t = l.next();
    try std.testing.expect(t.kind == .dimension and t.num == 1.5 and std.mem.eql(u8, t.text, "em") and !t.int);
    t = l.next();
    try std.testing.expect(t.kind == .number and t.num == -0.5);
    t = l.next();
    try std.testing.expect(t.kind == .number and t.num == 3 and t.int);
    t = l.next();
    try std.testing.expect(t.kind == .percentage and t.num == 50);
    try std.testing.expect(l.next().kind == .slash);
    try std.testing.expect(l.next().kind == .number);
    try std.testing.expect(l.next().kind == .comma);
    t = l.next();
    try std.testing.expect(t.kind == .bracket and std.mem.eql(u8, t.args, "a"));
    try std.testing.expect(l.next().isIdent("x"));
    try std.testing.expect(l.atEnd());
    try std.testing.expect(l.next().kind == .eof);
}
fn parseNumber(s: []const u8) ?struct { value: f64, len: usize } {
    var i: usize = 0;
    var neg = false;
    if (i < s.len and (s[i] == '-' or s[i] == '+')) {
        neg = s[i] == '-';
        i += 1;
    }
    var mant: f64 = 0;
    var digits: usize = 0;
    var frac_digits: i32 = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
        mant = mant * 10 + @as(f64, @floatFromInt(s[i] - '0'));
        digits += 1;
    }
    if (i < s.len and s[i] == '.' and i + 1 < s.len and s[i + 1] >= '0' and s[i + 1] <= '9') {
        i += 1;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
            if (frac_digits < 18) {
                mant = mant * 10 + @as(f64, @floatFromInt(s[i] - '0'));
                frac_digits += 1;
            }
            digits += 1;
        }
    }
    if (digits == 0) return null;
    var exp: i32 = -frac_digits;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        var j = i + 1;
        var eneg = false;
        if (j < s.len and (s[j] == '-' or s[j] == '+')) {
            eneg = s[j] == '-';
            j += 1;
        }
        if (j < s.len and s[j] >= '0' and s[j] <= '9') {
            var e: i32 = 0;
            while (j < s.len and s[j] >= '0' and s[j] <= '9') : (j += 1) {
                if (e < 10000) e = e * 10 + @as(i32, s[j] - '0');
            }
            exp += if (eneg) -e else e;
            i = j;
        }
    }
    var v = mant;
    if (exp != 0) v = scale10(v, exp);
    return .{ .value = if (neg) -v else v, .len = i };
}
fn scale10(v: f64, exp: i32) f64 {
    var e: u32 = @intCast(@min(@abs(exp), 400));
    var p: f64 = 1;
    var base: f64 = 10;
    while (e != 0) : (e >>= 1) {
        if (e & 1 != 0) p *= base;
        base *= base;
    }
    return if (exp < 0) v / p else v * p;
}

// ---------------------------------------------------------------- keyword enums
/// Kebab-case names of an enum's tags (`space_between` -> "space-between"), packed into one
/// NUL-separated string at comptime (much smaller in the binary than a slice table).
/// Enums used with `kw` must have tags numbered 0..n-1 in declaration order.
pub fn packedNames(comptime E: type) []const u8 {
    comptime {
        @setEvalBranchQuota(100000);
        var out: []const u8 = "";
        for (@typeInfo(E).@"enum".field_names, 0..) |n, i| {
            var buf: [n.len]u8 = undefined;
            for (n, 0..) |ch, j| buf[j] = if (ch == '_') '-' else ch;
            const final = buf;
            out = out ++ (if (i == 0) "" else "\x00") ++ &final;
        }
        return out;
    }
}

/// Case-insensitive match of `text` against a NUL-separated name list; returns the index.
pub fn matchPacked(text: []const u8, names: []const u8) ?usize {
    var idx: usize = 0;
    var i: usize = 0;
    while (i <= names.len) {
        var j = i;
        while (j < names.len and names[j] != 0) j += 1;
        if (std.ascii.eqlIgnoreCase(text, names[i..j])) return idx;
        idx += 1;
        i = j + 1;
    }
    return null;
}

/// Ident token -> enum tag by kebab-case name.
pub inline fn kw(comptime E: type, t: Token) ?E {
    if (t.kind != .ident) return null;
    const i = matchPacked(t.text, comptime packedNames(E)) orelse return null;
    return @enumFromInt(i);
}

// ---------------------------------------------------------------- tiny growable list
/// Arena-oriented growable list: much smaller per element type than std.ArrayList (growth is one
/// shared non-generic function; old buffers are not freed, which is fine for an arena).
pub fn List(comptime T: type) type {
    return struct {
        items: []T = &.{},
        cap: usize = 0,
        const Self = @This();
        pub fn append(self: *Self, a: std.mem.Allocator, v: T) Error!void {
            if (self.items.len == self.cap) {
                const raw = try grow(a, @ptrCast(self.items.ptr), self.items.len, @sizeOf(T), @alignOf(T), &self.cap);
                self.items.ptr = @ptrCast(@alignCast(raw));
            }
            self.items.len += 1;
            self.items[self.items.len - 1] = v;
        }
        pub fn appendSlice(self: *Self, a: std.mem.Allocator, vs: []const T) Error!void {
            for (vs) |v| try self.append(a, v);
        }
    };
}

fn grow(a: std.mem.Allocator, old: [*]const u8, len: usize, elem: usize, alignment: usize, cap: *usize) Error![*]u8 {
    const new_cap = cap.* * 2 + 4;
    const bytes = std.math.mul(usize, new_cap, elem) catch return error.OutOfMemory;
    const p = a.rawAlloc(bytes, std.mem.Alignment.fromByteUnits(alignment), @returnAddress()) orelse return error.OutOfMemory;
    if (len > 0) @memcpy(p[0 .. len * elem], old[0 .. len * elem]);
    cap.* = new_cap;
    return p;
}

test "List" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var l: List(u32) = .{};
    for (0..100) |i| try l.append(arena.allocator(), @intCast(i));
    try std.testing.expectEqual(@as(usize, 100), l.items.len);
    try std.testing.expectEqual(@as(u32, 99), l.items[99]);
}
