//! CSS Syntax Level 3 tokenizer (https://drafts.csswg.org/css-syntax-3/#tokenization).
//! Works on byte slices (UTF-8 is passed through; bytes >= 0x80 are identifier code points).
//! Never allocates: tokens are spans into the source; `value()` unescapes into an arena only when the
//! token contained a backslash escape. Comments are skipped (they separate tokens like whitespace does
//! not: `a/**/b` yields `a`, `b`). Every loop advances `pos`, so tokenizing always terminates.
const std = @import("std");

pub const Kind = enum(u8) {
    eof,
    ws,
    ident,
    function, // value = name (without '(')
    at_keyword, // value = name (without '@')
    hash, // value = name (without '#'); `id` = would be a valid identifier
    string, // value = contents without quotes
    bad_string,
    url, // value = url contents (unquoted url(...) form)
    bad_url,
    delim, // `delim` = the byte (0x80.. for non-ASCII starts)
    number,
    percentage,
    dimension, // unit = unit span
    cdo,
    cdc,
    colon,
    semicolon,
    comma,
    lbracket,
    rbracket,
    lparen,
    rparen,
    lbrace,
    rbrace,
};

pub const Token = struct {
    kind: Kind = .eof,
    /// Source span of the whole token.
    start: usize = 0,
    end: usize = 0,
    /// Span of the token's "value" (name / string contents / unit-less number text).
    vstart: usize = 0,
    vend: usize = 0,
    /// Unit span for dimensions.
    ustart: usize = 0,
    uend: usize = 0,
    /// The value span contains a backslash escape (needs `value()` with an allocator).
    esc: bool = false,
    id: bool = false,
    int: bool = false,
    delim: u8 = 0,
    num: f32 = 0,

    pub fn raw(t: Token, src: []const u8) []const u8 {
        return src[t.start..t.end];
    }
    /// Value text as written (escapes NOT processed).
    pub fn rawValue(t: Token, src: []const u8) []const u8 {
        return src[t.vstart..t.vend];
    }
    pub fn unit(t: Token, src: []const u8) []const u8 {
        return src[t.ustart..t.uend];
    }
    /// Unescaped value; allocates only when the token contained escapes.
    pub fn value(t: Token, arena: std.mem.Allocator, src: []const u8) error{OutOfMemory}![]const u8 {
        const v = src[t.vstart..t.vend];
        if (!t.esc) return v;
        return unescape(arena, v);
    }
    pub fn isDelim(t: Token, c: u8) bool {
        return t.kind == .delim and t.delim == c;
    }
    /// ASCII case-insensitive identifier comparison (escape-free identifiers only; escaped ones never
    /// equal a keyword here, which only affects pathological input).
    pub fn isIdent(t: Token, src: []const u8, name: []const u8) bool {
        return t.kind == .ident and !t.esc and ieq(src[t.vstart..t.vend], name);
    }
};

pub inline fn isNameStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c >= 0x80;
}
pub inline fn isName(c: u8) bool {
    return isNameStart(c) or (c >= '0' and c <= '9') or c == '-';
}
inline fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
inline fn isHex(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}
pub inline fn isWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0c;
}

pub const Tokenizer = struct {
    src: []const u8,
    pos: usize,
    end: usize,

    pub fn init(src: []const u8) Tokenizer {
        return .{ .src = src, .pos = 0, .end = src.len };
    }
    /// Tokenize `src[start..end]` (must lie on token boundaries of the enclosing tokenization).
    pub fn range(src: []const u8, start: usize, end: usize) Tokenizer {
        const e = @min(end, src.len);
        return .{ .src = src, .pos = @min(start, e), .end = e };
    }

    inline fn at(t: *const Tokenizer, i: usize) u8 {
        return if (i < t.end) t.src[i] else 0;
    }

    fn validEscape(t: *const Tokenizer, i: usize) bool {
        return i < t.end and t.src[i] == '\\' and (i + 1 >= t.end or t.src[i + 1] != '\n');
    }
    fn startsIdent(t: *const Tokenizer, i: usize) bool {
        const c = t.at(i);
        if (c == '-') {
            const c1 = t.at(i + 1);
            return isNameStart(c1) or c1 == '-' or t.validEscape(i + 1);
        }
        if (isNameStart(c)) return true;
        return t.validEscape(i);
    }
    fn startsNumber(t: *const Tokenizer, i: usize) bool {
        const c = t.at(i);
        if (c == '+' or c == '-') {
            const c1 = t.at(i + 1);
            return isDigit(c1) or (c1 == '.' and isDigit(t.at(i + 2)));
        }
        if (c == '.') return isDigit(t.at(i + 1));
        return isDigit(c);
    }

    /// Skips an escape starting at '\\' (pos points at the backslash).
    fn skipEscape(t: *Tokenizer) void {
        t.pos += 1; // '\'
        if (t.pos >= t.end) return;
        if (isHex(t.src[t.pos])) {
            var n: usize = 0;
            while (n < 6 and t.pos < t.end and isHex(t.src[t.pos])) : (n += 1) t.pos += 1;
            if (t.pos < t.end and isWs(t.src[t.pos])) {
                if (t.src[t.pos] == '\r' and t.at(t.pos + 1) == '\n') t.pos += 1;
                t.pos += 1;
            }
        } else t.pos += 1;
    }

    /// Consumes a name; returns whether it contained escapes.
    fn consumeName(t: *Tokenizer) bool {
        var esc = false;
        while (t.pos < t.end) {
            const c = t.src[t.pos];
            if (isName(c)) {
                t.pos += 1;
            } else if (t.validEscape(t.pos)) {
                esc = true;
                t.skipEscape();
            } else break;
        }
        return esc;
    }

    fn skipComments(t: *Tokenizer) void {
        while (t.pos + 1 < t.end and t.src[t.pos] == '/' and t.src[t.pos + 1] == '*') {
            if (std.mem.indexOfPos(u8, t.src[0..t.end], t.pos + 2, "*/")) |e| {
                t.pos = e + 2;
            } else {
                t.pos = t.end;
            }
        }
    }

    pub fn next(t: *Tokenizer) Token {
        var tok = t.scan();
        tok.end = t.pos;
        return tok;
    }

    fn scan(t: *Tokenizer) Token {
        t.skipComments();
        var tok: Token = .{ .start = t.pos };
        if (t.pos >= t.end) {
            tok.kind = .eof;
            return tok;
        }
        const c = t.src[t.pos];
        if (isWs(c)) {
            while (t.pos < t.end and isWs(t.src[t.pos])) t.pos += 1;
            tok.kind = .ws;
            return tok;
        }
        switch (c) {
            '"', '\'' => {
                t.consumeString(&tok, c);
                return tok;
            },
            '#' => {
                if (isName(t.at(t.pos + 1)) or t.validEscape(t.pos + 1)) {
                    tok.id = t.startsIdent(t.pos + 1);
                    t.pos += 1;
                    tok.vstart = t.pos;
                    tok.esc = t.consumeName();
                    tok.vend = t.pos;
                    tok.kind = .hash;
                    return tok;
                }
            },
            '(' => return t.single(&tok, .lparen),
            ')' => return t.single(&tok, .rparen),
            '[' => return t.single(&tok, .lbracket),
            ']' => return t.single(&tok, .rbracket),
            '{' => return t.single(&tok, .lbrace),
            '}' => return t.single(&tok, .rbrace),
            ',' => return t.single(&tok, .comma),
            ':' => return t.single(&tok, .colon),
            ';' => return t.single(&tok, .semicolon),
            '+', '.' => if (t.startsNumber(t.pos)) {
                t.consumeNumeric(&tok);
                return tok;
            },
            '-' => {
                if (t.startsNumber(t.pos)) {
                    t.consumeNumeric(&tok);
                    return tok;
                }
                if (t.at(t.pos + 1) == '-' and t.at(t.pos + 2) == '>') {
                    t.pos += 3;
                    tok.kind = .cdc;
                    return tok;
                }
                if (t.startsIdent(t.pos)) {
                    t.consumeIdentLike(&tok);
                    return tok;
                }
            },
            '<' => if (t.at(t.pos + 1) == '!' and t.at(t.pos + 2) == '-' and t.at(t.pos + 3) == '-') {
                t.pos += 4;
                tok.kind = .cdo;
                return tok;
            },
            '@' => if (t.startsIdent(t.pos + 1)) {
                t.pos += 1;
                tok.vstart = t.pos;
                tok.esc = t.consumeName();
                tok.vend = t.pos;
                tok.kind = .at_keyword;
                return tok;
            },
            '\\' => if (t.validEscape(t.pos)) {
                t.consumeIdentLike(&tok);
                return tok;
            },
            '0'...'9' => {
                t.consumeNumeric(&tok);
                return tok;
            },
            else => if (isNameStart(c)) {
                t.consumeIdentLike(&tok);
                return tok;
            },
        }
        // delim
        t.pos += 1;
        tok.kind = .delim;
        tok.delim = c;
        // Keep multi-byte UTF-8 sequences in one delim token.
        if (c >= 0x80) {
            while (t.pos < t.end and (t.src[t.pos] & 0xC0) == 0x80) t.pos += 1;
        }
        return tok;
    }

    fn single(t: *Tokenizer, tok: *Token, k: Kind) Token {
        t.pos += 1;
        tok.kind = k;
        tok.end = t.pos;
        return tok.*;
    }

    fn consumeString(t: *Tokenizer, tok: *Token, q: u8) void {
        t.pos += 1;
        tok.vstart = t.pos;
        tok.kind = .string;
        while (t.pos < t.end) {
            const c = t.src[t.pos];
            if (c == q) {
                tok.vend = t.pos;
                t.pos += 1;
                return;
            }
            if (c == '\n') {
                tok.vend = t.pos;
                tok.kind = .bad_string;
                return; // newline not consumed
            }
            if (c == '\\') {
                tok.esc = true;
                if (t.pos + 1 >= t.end) {
                    t.pos += 1;
                } else if (t.src[t.pos + 1] == '\n') {
                    t.pos += 2;
                } else t.skipEscape();
                continue;
            }
            t.pos += 1;
        }
        tok.vend = t.pos; // EOF: string ends (parse error, still a string)
    }

    fn consumeIdentLike(t: *Tokenizer, tok: *Token) void {
        tok.vstart = t.pos;
        tok.esc = t.consumeName();
        tok.vend = t.pos;
        if (t.at(t.pos) == '(') {
            const name = t.src[tok.vstart..tok.vend];
            if (!tok.esc and ieq(name, "url")) {
                // url( followed by optional ws and a quote -> function token
                var i = t.pos + 1;
                while (i < t.end and isWs(t.src[i])) i += 1;
                const q = t.at(i);
                if (q != '"' and q != '\'') {
                    t.pos += 1;
                    t.consumeUrl(tok);
                    return;
                }
            }
            t.pos += 1;
            tok.kind = .function;
            return;
        }
        tok.kind = .ident;
    }

    fn consumeUrl(t: *Tokenizer, tok: *Token) void {
        while (t.pos < t.end and isWs(t.src[t.pos])) t.pos += 1;
        tok.vstart = t.pos;
        tok.kind = .url;
        while (t.pos < t.end) {
            const c = t.src[t.pos];
            if (c == ')') {
                tok.vend = t.pos;
                t.pos += 1;
                return;
            }
            if (isWs(c)) {
                tok.vend = t.pos;
                while (t.pos < t.end and isWs(t.src[t.pos])) t.pos += 1;
                if (t.pos >= t.end) return;
                if (t.src[t.pos] == ')') {
                    t.pos += 1;
                    return;
                }
                break; // bad url
            }
            if (c == '"' or c == '\'' or c == '(' or c < 0x20 or c == 0x7f) break;
            if (c == '\\') {
                if (t.validEscape(t.pos)) {
                    tok.esc = true;
                    t.skipEscape();
                    continue;
                }
                break;
            }
            t.pos += 1;
        }
        if (t.pos >= t.end) {
            tok.vend = t.pos;
            return;
        }
        // bad url: consume the remnants up to ')' (escapes skipped)
        tok.kind = .bad_url;
        while (t.pos < t.end) {
            const c = t.src[t.pos];
            if (c == ')') {
                t.pos += 1;
                break;
            }
            if (t.validEscape(t.pos)) t.skipEscape() else t.pos += 1;
        }
        tok.vend = t.pos;
    }

    fn consumeNumeric(t: *Tokenizer, tok: *Token) void {
        tok.vstart = t.pos;
        var neg = false;
        if (t.src[t.pos] == '+' or t.src[t.pos] == '-') {
            neg = t.src[t.pos] == '-';
            t.pos += 1;
        }
        var mant: u64 = 0;
        var digits: u32 = 0;
        var exp10: i32 = 0;
        var is_int = true;
        while (t.pos < t.end and isDigit(t.src[t.pos])) : (t.pos += 1) {
            if (digits < 18) {
                mant = mant * 10 + (t.src[t.pos] - '0');
                if (mant != 0) digits += 1;
            } else exp10 +|= 1;
        }
        if (t.at(t.pos) == '.' and isDigit(t.at(t.pos + 1))) {
            is_int = false;
            t.pos += 1;
            while (t.pos < t.end and isDigit(t.src[t.pos])) : (t.pos += 1) {
                if (digits < 18) {
                    mant = mant * 10 + (t.src[t.pos] - '0');
                    if (mant != 0) digits += 1;
                    exp10 -|= 1;
                }
            }
        }
        const e = t.at(t.pos);
        if (e == 'e' or e == 'E') {
            const s1 = t.at(t.pos + 1);
            var j = t.pos + 1;
            if (s1 == '+' or s1 == '-') j += 1;
            if (isDigit(t.at(j))) {
                is_int = false;
                const eneg = s1 == '-';
                t.pos = j;
                var ev: i32 = 0;
                while (t.pos < t.end and isDigit(t.src[t.pos])) : (t.pos += 1) {
                    if (ev < 10000) ev = ev * 10 + (t.src[t.pos] - '0');
                }
                exp10 +|= if (eneg) -ev else ev;
            }
        }
        tok.vend = t.pos;
        tok.int = is_int;
        tok.num = scale(mant, exp10, neg);
        if (t.startsIdent(t.pos)) {
            tok.ustart = t.pos;
            tok.esc = t.consumeName();
            tok.uend = t.pos;
            tok.kind = .dimension;
        } else if (t.at(t.pos) == '%') {
            t.pos += 1;
            tok.kind = .percentage;
        } else tok.kind = .number;
    }
};

/// mant * 10^exp10, saturating to +-3.4e38 / 0. Uses f64 internally for precision (no tables).
fn scale(mant: u64, exp10: i32, neg: bool) f32 {
    var v: f64 = @floatFromInt(mant);
    var e = exp10;
    if (mant == 0) return if (neg) -0.0 else 0.0;
    if (e > 60) e = 60;
    if (e < -80) e = -80;
    while (e > 0) : (e -= 1) v *= 10.0;
    while (e < 0) : (e += 1) v /= 10.0;
    if (v > 3.4e38) v = 3.4e38;
    const f: f32 = @floatCast(v);
    return if (neg) -f else f;
}

/// Parses a whole string as a CSS <number> (used for JSON-free numeric checks). Returns null if not a number.
pub fn parseNumber(s: []const u8) ?f32 {
    var t = Tokenizer.init(s);
    const tok = t.next();
    if (tok.kind != .number or t.next().kind != .eof) return null;
    return tok.num;
}

/// Processes CSS escapes (`\41 `, `\.`) into UTF-8. Invalid code points become U+FFFD.
pub fn unescape(arena: std.mem.Allocator, v: []const u8) error{OutOfMemory}![]const u8 {
    var out = try arena.alloc(u8, v.len * 3 + 4);
    var o: usize = 0;
    var i: usize = 0;
    while (i < v.len) {
        const c = v[i];
        if (c != '\\') {
            out[o] = c;
            o += 1;
            i += 1;
            continue;
        }
        i += 1;
        if (i >= v.len) {
            o += encode(0xFFFD, out[o..]);
            break;
        }
        if (v[i] == '\n') { // escaped newline in strings: removed
            i += 1;
            continue;
        }
        if (isHex(v[i])) {
            var cp: u32 = 0;
            var n: usize = 0;
            while (n < 6 and i < v.len and isHex(v[i])) : (n += 1) {
                cp = cp * 16 + hexVal(v[i]);
                i += 1;
            }
            if (i < v.len and isWs(v[i])) {
                if (v[i] == '\r' and i + 1 < v.len and v[i + 1] == '\n') i += 1;
                i += 1;
            }
            if (cp == 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) cp = 0xFFFD;
            o += encode(cp, out[o..]);
        } else {
            out[o] = v[i];
            o += 1;
            i += 1;
        }
    }
    return out[0..o];
}

fn hexVal(c: u8) u32 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        else => c - 'A' + 10,
    };
}

fn encode(cp: u32, out: []u8) usize {
    if (cp < 0x80) {
        out[0] = @intCast(cp);
        return 1;
    } else if (cp < 0x800) {
        out[0] = @intCast(0xC0 | (cp >> 6));
        out[1] = @intCast(0x80 | (cp & 0x3F));
        return 2;
    } else if (cp < 0x10000) {
        out[0] = @intCast(0xE0 | (cp >> 12));
        out[1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
        out[2] = @intCast(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = @intCast(0xF0 | (cp >> 18));
    out[1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
    out[2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
    out[3] = @intCast(0x80 | (cp & 0x3F));
    return 4;
}

// ------------------------------------------------------------------------------------------------
// Block helpers shared by the parsers.

pub fn closer(k: Kind) Kind {
    return switch (k) {
        .lbrace => .rbrace,
        .lbracket => .rbracket,
        else => .rparen, // lparen, function
    };
}
pub fn opensBlock(k: Kind) bool {
    return k == .lbrace or k == .lbracket or k == .lparen or k == .function;
}

/// After an opening token was consumed, skips to just after its matching closer (or EOF).
/// Returns the position of the closer's start (= end of the block contents).
/// Nesting deeper than 256 is tracked by a counter only (closers of any type then close),
/// which keeps it allocation-free and bounded on hostile input.
pub fn skipBlock(t: *Tokenizer, open: Kind) usize {
    var stack: [256]Kind = undefined;
    var depth: usize = 1;
    var overflow: usize = 0;
    stack[0] = closer(open);
    while (true) {
        const tok = t.next();
        if (tok.kind == .eof) return tok.start;
        if (opensBlock(tok.kind)) {
            if (depth < stack.len) {
                stack[depth] = closer(tok.kind);
                depth += 1;
            } else overflow += 1;
            continue;
        }
        if (tok.kind == .rbrace or tok.kind == .rbracket or tok.kind == .rparen) {
            if (overflow > 0) {
                overflow -= 1;
                continue;
            }
            if (tok.kind == stack[depth - 1]) {
                depth -= 1;
                if (depth == 0) return tok.start;
            }
        }
    }
}

test "tokenizer basics" {
    const src = "a.b #id > [x=\"q\\\"\"] 12.5px 50% -3 url( x.png ) f( /*c*/ @media <!-- --> \\31 23";
    var t = Tokenizer.init(src);
    const kinds = [_]Kind{ .ident, .delim, .ident, .ws, .hash, .ws, .delim, .ws, .lbracket, .ident, .delim, .string, .rbracket, .ws, .dimension, .ws, .percentage, .ws, .number, .ws, .url, .ws, .function, .ws, .ws, .at_keyword, .ws, .cdo, .ws, .cdc, .ws, .ident, .eof };
    var vals: [kinds.len]Token = undefined;
    for (kinds, 0..) |k, i| {
        const tok = t.next();
        vals[i] = tok;
        try std.testing.expectEqual(k, tok.kind);
    }
    try std.testing.expectEqualStrings("id", vals[4].rawValue(src));
    try std.testing.expect(vals[4].id);
    try std.testing.expectApproxEqAbs(@as(f32, 12.5), vals[14].num, 1e-6);
    try std.testing.expectEqualStrings("px", vals[14].unit(src));
    try std.testing.expectEqual(@as(f32, -3), vals[18].num);
    try std.testing.expectEqualStrings("x.png", vals[20].rawValue(src));
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    try std.testing.expectEqualStrings("q\"", try vals[11].value(fba.allocator(), src));
    try std.testing.expectEqualStrings("123", try vals[31].value(fba.allocator(), src));
}

test "tokenizer numbers" {
    try std.testing.expectApproxEqRel(@as(f32, 1.5e3), parseNumber("1.5e3").?, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 0.25), parseNumber(".25").?, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, -0.001), parseNumber("-1e-3").?, 1e-6);
    try std.testing.expect(parseNumber("1px") == null);
    try std.testing.expectEqual(@as(f32, 3.4e38), parseNumber("1e999").?);
}

test "skipBlock nesting and unbalanced" {
    const src = "{ a ( } ) [ ] } x";
    var t = Tokenizer.init(src);
    _ = t.next();
    const e = skipBlock(&t, .lbrace);
    try std.testing.expectEqual(@as(usize, 14), e);
    var t2 = Tokenizer.init("( ( ( ");
    _ = t2.next();
    _ = skipBlock(&t2, .lparen);
    try std.testing.expectEqual(t2.end, t2.pos);
}

/// ASCII case-insensitive equality (one out-of-line copy for the whole module).
pub noinline fn ieq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    }
    return true;
}

/// Byte equality (small out-of-line replacement for `std.mem.eql`).
pub noinline fn seq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}
