//! TEST-ONLY copy of src/json.zig: src/style is unit-tested standalone (`zig test src/style/style.zig`),
//! where importing ../json.zig is outside the module path. Never referenced from non-test code.
//! Minimal JSON DOM parser (arena-allocated, no std.fmt / std.json to keep the wasm small).
//! Input is untrusted: every access is bounds-checked and nesting depth is limited.
const std = @import("std");

pub const Member = struct { key: []const u8, value: Value };

pub const Value = union(enum) {
    null,
    bool: bool,
    number: f64,
    string: []const u8,
    array: []Value,
    object: []Member,

    pub fn get(self: Value, key: []const u8) ?Value {
        if (self != .object) return null;
        // Last occurrence wins (JS semantics for duplicate keys).
        var i = self.object.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.object[i].key, key)) return self.object[i].value;
        }
        return null;
    }

    pub fn asString(self: Value) ?[]const u8 {
        return if (self == .string) self.string else null;
    }

    pub fn asNumber(self: Value) ?f32 {
        return if (self == .number) @floatCast(self.number) else null;
    }

    pub fn asBool(self: Value) ?bool {
        return if (self == .bool) self.bool else null;
    }
};

pub const Error = error{ InvalidJson, JsonTooDeep, OutOfMemory };

const max_depth = 256;

pub fn parse(arena: std.mem.Allocator, text: []const u8) Error!Value {
    var p: Parser = .{ .a = arena, .s = text };
    p.skipWs();
    const v = try p.value(0);
    p.skipWs();
    if (p.i != p.s.len) return error.InvalidJson;
    return v;
}

const Parser = struct {
    a: std.mem.Allocator,
    s: []const u8,
    i: usize = 0,

    fn peek(p: *Parser) u8 {
        return if (p.i < p.s.len) p.s[p.i] else 0;
    }

    fn skipWs(p: *Parser) void {
        while (p.i < p.s.len) : (p.i += 1) {
            switch (p.s[p.i]) {
                ' ', '\t', '\n', '\r' => {},
                else => return,
            }
        }
    }

    fn lit(p: *Parser, comptime word: []const u8) Error!void {
        if (p.s.len - p.i < word.len or !std.mem.eql(u8, p.s[p.i..][0..word.len], word)) return error.InvalidJson;
        p.i += word.len;
    }

    fn value(p: *Parser, depth: u32) Error!Value {
        if (depth > max_depth) return error.JsonTooDeep;
        switch (p.peek()) {
            '{' => return p.object(depth),
            '[' => return p.array(depth),
            '"' => return .{ .string = try p.string() },
            't' => {
                try p.lit("true");
                return .{ .bool = true };
            },
            'f' => {
                try p.lit("false");
                return .{ .bool = false };
            },
            'n' => {
                try p.lit("null");
                return .null;
            },
            '-', '0'...'9' => return .{ .number = try p.number() },
            else => return error.InvalidJson,
        }
    }

    fn object(p: *Parser, depth: u32) Error!Value {
        p.i += 1;
        var list: std.ArrayList(Member) = .empty;
        p.skipWs();
        if (p.peek() == '}') {
            p.i += 1;
            return .{ .object = &.{} };
        }
        while (true) {
            p.skipWs();
            if (p.peek() != '"') return error.InvalidJson;
            const key = try p.string();
            p.skipWs();
            if (p.peek() != ':') return error.InvalidJson;
            p.i += 1;
            p.skipWs();
            const v = try p.value(depth + 1);
            try list.append(p.a, .{ .key = key, .value = v });
            p.skipWs();
            switch (p.peek()) {
                ',' => p.i += 1,
                '}' => {
                    p.i += 1;
                    return .{ .object = list.items };
                },
                else => return error.InvalidJson,
            }
        }
    }

    fn array(p: *Parser, depth: u32) Error!Value {
        p.i += 1;
        var list: std.ArrayList(Value) = .empty;
        p.skipWs();
        if (p.peek() == ']') {
            p.i += 1;
            return .{ .array = &.{} };
        }
        while (true) {
            p.skipWs();
            const v = try p.value(depth + 1);
            try list.append(p.a, v);
            p.skipWs();
            switch (p.peek()) {
                ',' => p.i += 1,
                ']' => {
                    p.i += 1;
                    return .{ .array = list.items };
                },
                else => return error.InvalidJson,
            }
        }
    }

    fn hex4(p: *Parser) Error!u32 {
        if (p.s.len - p.i < 4) return error.InvalidJson;
        var v: u32 = 0;
        for (p.s[p.i..][0..4]) |c| {
            const d: u32 = switch (c) {
                '0'...'9' => c - '0',
                'a'...'f' => c - 'a' + 10,
                'A'...'F' => c - 'A' + 10,
                else => return error.InvalidJson,
            };
            v = v * 16 + d;
        }
        p.i += 4;
        return v;
    }

    fn string(p: *Parser) Error![]const u8 {
        p.i += 1; // opening quote
        const start = p.i;
        // Fast path: no escapes -> slice of the input.
        while (p.i < p.s.len) : (p.i += 1) {
            const c = p.s[p.i];
            if (c == '"') {
                const out = p.s[start..p.i];
                p.i += 1;
                return out;
            }
            if (c == '\\') break;
            if (c < 0x20) return error.InvalidJson;
        }
        if (p.i >= p.s.len) return error.InvalidJson;
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(p.a, p.s[start..p.i]);
        while (p.i < p.s.len) {
            const c = p.s[p.i];
            p.i += 1;
            switch (c) {
                '"' => return buf.items,
                '\\' => {
                    if (p.i >= p.s.len) return error.InvalidJson;
                    const e = p.s[p.i];
                    p.i += 1;
                    switch (e) {
                        '"', '\\', '/' => try buf.append(p.a, e),
                        'b' => try buf.append(p.a, 8),
                        'f' => try buf.append(p.a, 12),
                        'n' => try buf.append(p.a, '\n'),
                        'r' => try buf.append(p.a, '\r'),
                        't' => try buf.append(p.a, '\t'),
                        'u' => {
                            var cp = try p.hex4();
                            if (cp >= 0xD800 and cp < 0xDC00) {
                                // High surrogate: needs a following \uXXXX low surrogate.
                                if (p.s.len - p.i >= 6 and p.s[p.i] == '\\' and p.s[p.i + 1] == 'u') {
                                    p.i += 2;
                                    const lo = try p.hex4();
                                    if (lo >= 0xDC00 and lo < 0xE000) {
                                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                    } else cp = 0xFFFD;
                                } else cp = 0xFFFD;
                            } else if (cp >= 0xDC00 and cp < 0xE000) cp = 0xFFFD;
                            var tmp: [4]u8 = undefined;
                            const n = encodeUtf8(cp, &tmp);
                            try buf.appendSlice(p.a, tmp[0..n]);
                        },
                        else => return error.InvalidJson,
                    }
                },
                else => {
                    if (c < 0x20) return error.InvalidJson;
                    try buf.append(p.a, c);
                },
            }
        }
        return error.InvalidJson;
    }

    fn number(p: *Parser) Error!f64 {
        const r = parseNumber(p.s[p.i..]) orelse return error.InvalidJson;
        p.i += r.len;
        return r.value;
    }
};

pub fn encodeUtf8(cp: u32, out: *[4]u8) usize {
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
    } else {
        out[0] = @intCast(0xF0 | ((cp >> 18) & 0x07));
        out[1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
        out[2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
        out[3] = @intCast(0x80 | (cp & 0x3F));
        return 4;
    }
}

pub const NumberResult = struct { value: f64, len: usize };

/// Parses a decimal number prefix (`-12.5e3`, `.5`, `+3`) without std.fmt. Shared with the CSS parser.
/// Precision: exact for up to 15 significant digits with small exponents, which is all CSS/JSON
/// layout input needs.
pub fn parseNumber(s: []const u8) ?NumberResult {
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

test "json basics" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const v = try parse(a,
        \\ {"type":"container","n":-12.5e1,"ok":true,"z":null,"s":"a\né😀\"","children":[1,2,{"x":[]}]}
    );
    try std.testing.expectEqualStrings("container", v.get("type").?.string);
    try std.testing.expectEqual(@as(f64, -125), v.get("n").?.number);
    try std.testing.expect(v.get("ok").?.bool);
    try std.testing.expect(v.get("z").? == .null);
    try std.testing.expectEqualStrings("a\n\xc3\xa9\xf0\x9f\x98\x80\"", v.get("s").?.string);
    try std.testing.expectEqual(@as(usize, 3), v.get("children").?.array.len);
    try std.testing.expectError(error.InvalidJson, parse(a, "{\"a\":}"));
    try std.testing.expectError(error.InvalidJson, parse(a, "[1,2"));
    try std.testing.expectError(error.InvalidJson, parse(a, "\"abc"));
    try std.testing.expectEqual(@as(f64, 0.25), parseNumber(".25").?.value);
    try std.testing.expectEqual(@as(usize, 3), parseNumber("1.5px").?.len);
}
