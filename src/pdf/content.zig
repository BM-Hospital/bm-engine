//! Content-stream builder (pdf-writer `Content`, non-pretty): operands are separated lazily like
//! object tokens; an operator is preceded by a space when it has operands and by a newline when
//! it has none, unless the previous byte is a delimiter (`q 0.75 0 0 -0.75 0 180 cm/x0 Do\nQ`,
//! `EMC/P<</MCID 0>>BDC`, `[(..)34.99951(..)]TJ`). Covers every operator krilla emits.
//!
//! Resource operands (`/g0 gs`, `/f0 12 Tf`, `/x0 Do`, ...) take the names handed out by
//! `writer.Resources.add`. Allocation errors are sticky (`failed`), see writer.zig.
const std = @import("std");
const w = @import("writer.zig");

const Allocator = std.mem.Allocator;

pub const FillRule = enum { nonzero, even_odd };

pub const Content = struct {
    b: w.Buf,
    /// Whether the operation being written already has operands (decides the separator).
    operands: bool = false,
    /// Current q/Q nesting depth (krilla caps it at 28).
    q_depth: u32 = 0,

    pub fn init(a: Allocator) Content {
        return .{ .b = .init(a) };
    }

    /// The finished content stream bytes (pass to `Doc.contentStream` / `Doc.formXObject`).
    pub fn bytes(c: *const Content) []const u8 {
        return c.b.list.items;
    }

    pub fn failed(c: *const Content) bool {
        return c.b.failed;
    }

    /// Clears the stream for reuse (keeps capacity).
    pub fn reset(c: *Content) void {
        c.b.list.clearRetainingCapacity();
        c.operands = false;
        c.q_depth = 0;
        c.b.limits = .{};
    }

    // -- generic -------------------------------------------------------------------------------

    /// Writes operator `name` after the operands written so far.
    pub fn op(c: *Content, operator: []const u8) void {
        const it = c.b.list.items;
        if (it.len > 0 and !w.isDelim(it[it.len - 1])) c.b.byte(if (c.operands) ' ' else '\n');
        c.b.raw(operator);
        c.operands = false;
    }

    pub fn num(c: *Content, v: f32) void {
        c.b.real(v);
        c.operands = true;
    }

    pub fn int(c: *Content, v: i64) void {
        c.b.int(v);
        c.operands = true;
    }

    pub fn name(c: *Content, n: []const u8) void {
        c.b.name(n);
        c.operands = true;
    }

    fn nums(c: *Content, vs: []const f32) void {
        for (vs) |v| c.num(v);
    }

    fn numsOp(c: *Content, vs: []const f32, o: []const u8) void {
        c.nums(vs);
        c.op(o);
    }

    // -- graphics state ------------------------------------------------------------------------

    pub fn save(c: *Content) void {
        c.op("q");
        c.q_depth += 1;
        if (c.q_depth > w.Limits.max_q_depth) c.b.limits.q_over = true;
    }

    pub fn restore(c: *Content) void {
        c.op("Q");
        c.q_depth -|= 1;
    }

    /// `a b c d e f cm`
    pub fn transform(c: *Content, m: [6]f32) void {
        c.numsOp(&m, "cm");
    }

    pub fn lineWidth(c: *Content, v: f32) void {
        c.numsOp(&.{v}, "w");
    }

    /// 0 butt, 1 round, 2 square
    pub fn lineCap(c: *Content, v: u8) void {
        c.int(v);
        c.op("J");
    }

    /// 0 miter, 1 round, 2 bevel
    pub fn lineJoin(c: *Content, v: u8) void {
        c.int(v);
        c.op("j");
    }

    pub fn miterLimit(c: *Content, v: f32) void {
        c.numsOp(&.{v}, "M");
    }

    /// `[a b ..]phase d`
    pub fn dash(c: *Content, array: []const f32, phase: f32) void {
        c.b.reals(array);
        c.operands = true;
        c.numsOp(&.{phase}, "d");
    }

    /// `/name gs`
    pub fn extGState(c: *Content, n: []const u8) void {
        c.name(n);
        c.op("gs");
    }

    // -- paths ---------------------------------------------------------------------------------

    pub fn moveTo(c: *Content, x: f32, y: f32) void {
        c.numsOp(&.{ x, y }, "m");
    }

    pub fn lineTo(c: *Content, x: f32, y: f32) void {
        c.numsOp(&.{ x, y }, "l");
    }

    pub fn cubicTo(c: *Content, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        c.numsOp(&.{ x1, y1, x2, y2, x3, y3 }, "c");
    }

    pub fn closePath(c: *Content) void {
        c.op("h");
    }

    pub fn rect(c: *Content, x: f32, y: f32, width: f32, height: f32) void {
        c.numsOp(&.{ x, y, width, height }, "re");
    }

    /// `f` / `f*`
    pub fn fill(c: *Content, rule: FillRule) void {
        c.op(if (rule == .nonzero) "f" else "f*");
    }

    pub fn stroke(c: *Content) void {
        c.op("S");
    }

    /// `B` / `B*`
    pub fn fillStroke(c: *Content, rule: FillRule) void {
        c.op(if (rule == .nonzero) "B" else "B*");
    }

    /// `n`
    pub fn endPath(c: *Content) void {
        c.op("n");
    }

    /// `W` / `W*` (follow with `endPath` or a painting operator)
    pub fn clip(c: *Content, rule: FillRule) void {
        c.op(if (rule == .nonzero) "W" else "W*");
    }

    // -- colour --------------------------------------------------------------------------------

    pub fn fillRgb(c: *Content, r: f32, g: f32, b: f32) void {
        c.numsOp(&.{ r, g, b }, "rg");
    }
    pub fn strokeRgb(c: *Content, r: f32, g: f32, b: f32) void {
        c.numsOp(&.{ r, g, b }, "RG");
    }
    pub fn fillGray(c: *Content, v: f32) void {
        c.numsOp(&.{v}, "g");
    }
    pub fn strokeGray(c: *Content, v: f32) void {
        c.numsOp(&.{v}, "G");
    }
    pub fn fillCmyk(c: *Content, cy: f32, m: f32, y: f32, k: f32) void {
        c.numsOp(&.{ cy, m, y, k }, "k");
    }
    pub fn strokeCmyk(c: *Content, cy: f32, m: f32, y: f32, k: f32) void {
        c.numsOp(&.{ cy, m, y, k }, "K");
    }
    /// `/name cs` (a ColorSpace resource name, or "Pattern", "DeviceRGB", ...)
    pub fn fillColorSpace(c: *Content, n: []const u8) void {
        c.name(n);
        c.op("cs");
    }
    pub fn strokeColorSpace(c: *Content, n: []const u8) void {
        c.name(n);
        c.op("CS");
    }
    /// `c1 .. cn scn`
    pub fn fillColor(c: *Content, comps: []const f32) void {
        c.numsOp(comps, "scn");
    }
    pub fn strokeColor(c: *Content, comps: []const f32) void {
        c.numsOp(comps, "SCN");
    }
    /// `/p0 scn` (after `fillColorSpace("Pattern")`)
    pub fn fillPattern(c: *Content, n: []const u8) void {
        c.name(n);
        c.op("scn");
    }
    pub fn strokePattern(c: *Content, n: []const u8) void {
        c.name(n);
        c.op("SCN");
    }

    // -- external objects ----------------------------------------------------------------------

    /// `/x0 Do`
    pub fn xObject(c: *Content, n: []const u8) void {
        c.name(n);
        c.op("Do");
    }

    /// `/s0 sh`
    pub fn shading(c: *Content, n: []const u8) void {
        c.name(n);
        c.op("sh");
    }

    // -- text ----------------------------------------------------------------------------------

    pub fn beginText(c: *Content) void {
        c.op("BT");
    }
    pub fn endText(c: *Content) void {
        c.op("ET");
    }
    /// `/f0 size Tf`
    pub fn font(c: *Content, n: []const u8, size: f32) void {
        c.name(n);
        c.numsOp(&.{size}, "Tf");
    }
    /// `x y Td`
    pub fn textMove(c: *Content, x: f32, y: f32) void {
        c.numsOp(&.{ x, y }, "Td");
    }
    /// `a b c d e f Tm`
    pub fn textMatrix(c: *Content, m: [6]f32) void {
        c.numsOp(&m, "Tm");
    }
    /// `mode Tr` (0 fill, 1 stroke, 2 fill+stroke, 3 invisible, 7 clip)
    pub fn textRenderMode(c: *Content, mode: u8) void {
        c.int(mode);
        c.op("Tr");
    }
    pub fn charSpacing(c: *Content, v: f32) void {
        c.numsOp(&.{v}, "Tc");
    }
    pub fn wordSpacing(c: *Content, v: f32) void {
        c.numsOp(&.{v}, "Tw");
    }
    pub fn textRise(c: *Content, v: f32) void {
        c.numsOp(&.{v}, "Ts");
    }
    pub fn horizontalScale(c: *Content, percent: f32) void {
        c.numsOp(&.{percent}, "Tz");
    }
    /// `(..) Tj` with pdf-writer's `Str` choice (literal for ASCII bytes, hex otherwise).
    pub fn show(c: *Content, s: []const u8) void {
        c.b.str(s);
        c.operands = true;
        c.op("Tj");
    }
    /// `<..> Tj` (forced hex string, e.g. 2-byte CIDs).
    pub fn showHex(c: *Content, s: []const u8) void {
        c.b.hexStr(s);
        c.operands = true;
        c.op("Tj");
    }
    /// Starts a `[...]TJ` array: add `tjStr` / `tjHex` / `tjAdjust` items, then `tjEnd`.
    pub fn tjBegin(c: *Content) void {
        c.b.arr();
        c.operands = true;
    }
    pub fn tjStr(c: *Content, s: []const u8) void {
        c.b.str(s);
    }
    pub fn tjHex(c: *Content, s: []const u8) void {
        c.b.hexStr(s);
    }
    /// Positioning adjustment in thousandths of a text space unit (positive moves left).
    pub fn tjAdjust(c: *Content, v: f32) void {
        c.b.real(v);
    }
    pub fn tjEnd(c: *Content) void {
        c.b.arrEnd();
        c.op("TJ");
    }

    // -- marked content ------------------------------------------------------------------------

    /// `/Tag BMC`
    pub fn beginMarked(c: *Content, tag: []const u8) void {
        c.name(tag);
        c.op("BMC");
    }
    /// `/Tag<</MCID n>>BDC`
    pub fn beginMarkedMcid(c: *Content, tag: []const u8, mcid: i32) void {
        c.bdcBegin(tag);
        c.b.pairInt("MCID", mcid);
        c.bdcEnd();
    }
    /// `/Tag<<` ... write property pairs into `c.b` ... `bdcEnd()` -> `>>BDC`.
    pub fn bdcBegin(c: *Content, tag: []const u8) void {
        c.name(tag);
        c.b.dict();
    }
    pub fn bdcEnd(c: *Content) void {
        c.b.dictEnd();
        c.op("BDC");
    }
    /// `/Tag/props BDC` (property list from the Properties resource dictionary).
    pub fn beginMarkedProps(c: *Content, tag: []const u8, props: []const u8) void {
        c.name(tag);
        c.name(props);
        c.op("BDC");
    }
    pub fn endMarked(c: *Content) void {
        c.op("EMC");
    }
};

const testing = std.testing;

test "operator spelling and separators match takumi-pdf" {
    var c = Content.init(testing.allocator);
    defer c.b.list.deinit(testing.allocator);
    // transformed-overflow-clip.pdf
    c.beginMarked("Artifact");
    c.save();
    c.transform(.{ 0.75, 0, 0, -0.75, 0, 180 });
    c.fillRgb(1, 1, 1);
    c.rect(0, 0, 240, 240);
    c.fill(.nonzero);
    c.restore();
    c.endMarked();
    c.save();
    c.rect(0, 180, 150, -150);
    c.clip(.nonzero);
    c.endPath();
    c.beginMarked("Artifact");
    c.restore();
    c.endMarked();
    c.restore();
    try testing.expectEqualStrings("/Artifact BMC\nq 0.75 0 0 -0.75 0 180 cm 1 1 1 rg 0 0 240 240 re\nf\nQ\nEMC\n" ++
        "q 0 180 150 -150 re\nW\nn/Artifact BMC\nQ\nEMC\nQ", c.bytes());
}

test "text, marked content, xobjects" {
    var c = Content.init(testing.allocator);
    defer c.b.list.deinit(testing.allocator);
    // text-basic.pdf
    c.endMarked();
    c.beginMarkedMcid("P", 0);
    c.save();
    c.fillRgb(0.0784, 0.0784, 0.0784);
    c.beginText();
    c.textRenderMode(0);
    c.font("f0", 32);
    c.textMatrix(.{ 1, 0, 0, -1, 0, 28 });
    c.tjBegin();
    c.tjStr(&.{ 0, 1, 0, 8 });
    c.tjAdjust(34.99951);
    c.tjStr(&.{ 0, 5 });
    c.tjEnd();
    c.endText();
    c.restore();
    c.save();
    c.extGState("g0");
    c.xObject("x0");
    c.restore();
    c.dash(&.{ 3, 2 }, 0);
    c.fillColorSpace("Pattern");
    c.fillPattern("p0");
    c.showHex(&.{ 0, 0x41 });
    try testing.expectEqualStrings("EMC/P<</MCID 0>>BDC\nq 0.0784 0.0784 0.0784 rg\nBT 0 Tr/f0 32 Tf 1 0 0 -1 0 28 Tm" ++
        "[(\\000\\001\\000\\b)34.99951(\\000\\005)]TJ\nET\nQ\nq/g0 gs/x0 Do\nQ[3 2]0 d/Pattern cs/p0 scn<0041>Tj", c.bytes());
}

test "content: q nesting over 28 is recorded" {
    var c = Content.init(testing.allocator);
    defer c.b.list.deinit(testing.allocator);
    for (0..28) |_| c.save();
    try testing.expect(!c.b.limits.q_over);
    c.restore();
    c.save();
    try testing.expect(!c.b.limits.q_over);
    c.save();
    try testing.expect(c.b.limits.q_over);
}
