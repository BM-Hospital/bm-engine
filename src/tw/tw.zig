//! Tailwind `tw` class compiler: a port of takumi's `takumi-core/src/style/tw/*` (Tailwind v4 subset).
//!
//! `compile` turns a node's `tw: "flex p-8 bg-blue-500 ..."` string into plain CSS declarations (kebab-case
//! names, CSS text values) in the order the cascade applies them. The caller applies them, in order, as
//! author-level declarations: above `preset`, below the node's inline `style` (an `important` declaration
//! beats a normal inline one, as in takumi).
//!
//! Semantics mirrored from takumi (not from upstream Tailwind):
//! - Utilities/values/variants are exactly takumi's table (`utility.rs`); unknown classes, unknown variants,
//!   values takumi would not parse, and theme tokens (`bg-brand`, which takumi compiles to an undefined
//!   `var(--color-brand)`, i.e. a no-op) are skipped silently. takumi has no `z-*`, `order-*`, `skew-*`,
//!   `ring-*`, `space-*`, `divide-*`, `place-*`, `cursor-*`, `(--var)` shorthand or
//!   `[prop:value]` classes, so neither does this. Root/keyword matching is case-sensitive for utility names
//!   and case-insensitive for values, as in takumi.
//! - Rules are sorted the way takumi sorts them (`rule.rs` TwOrder + cascade): normal before `!important`,
//!   then selector specificity (structural variants add one pseudo-class each), then breakpoint (none first,
//!   then by width), then variant bits, then Tailwind's property order, then the class text (so of two
//!   conflicting colour utilities the alphabetically later class wins, as in takumi).
//! - takumi composes some utilities through non-inherited `--tw-*` variables (translate/scale axes, the
//!   filter chains, gradient stops, shadow colours, `--tw-border-style`). This compiler resolves them for
//!   the element, so no `var()` is ever emitted. An undefined theme colour in such a variable
//!   (`from-brand`, `shadow-brand`) reads as unset (CSS guaranteed-invalid), exactly as in takumi.
//! - Colours are the palette's sRGB bytes (takumi uses sRGB tables, not oklch), emitted as `#rrggbb[aa]`;
//!   an opacity modifier on a gradient/shadow colour (takumi: `color-mix(in oklab, c p%, transparent)`) is
//!   folded into the alpha byte. Gradients keep takumi's `in oklab` interpolation hint; the logical
//!   properties takumi uses (`margin-inline`, `padding-inline-start`, `inset-inline`, ...) keep their names.
//! - Arbitrary values (`w-[37px]`, underscores -> spaces except inside `url()`, `\_` -> `_`) are passed
//!   through after a light shape check (picks the form of multi-form roots such as `bg-[...]`, drops
//!   `var()` and `calc(1px+2px)` without spaces). takumi silently drops an arbitrary value its typed parser
//!   rejects, and accepts a few values its inline-style parser does not (`display: contents`), so the
//!   integrator must skip (not throw on) a tw declaration its value parser rejects.
//! - Variants: breakpoints `sm md lg xl 2xl` (min-width, `rem*16*dpr` device px against the viewport width;
//!   no viewport width -> never), structural `first last only odd even first-of-type last-of-type
//!   only-of-type empty not-* nth-* nth-last-* nth-of-type-* nth-last-of-type-* [&:...]` (need
//!   `Env.element`; without it they never apply), pseudo-elements `before:`/`after:` (compile again with
//!   `Env.target = .before/.after`). Any other variant (`hover:`, `dark:`, `max-md:`, `group-*:`) never applies
//!   in takumi, so neither here; `Env.dark` is therefore unused.
//!
//! Memory: `arena` holds the returned values and some O(classes) scratch (expected: the per-render bump
//! arena). Names are static. No global state; no std.Io; safe on untrusted input (bounded loops, recursion
//! depth <= 2, control bytes rejected).
const std = @import("std");
const palette = @import("palette.zig");
const Allocator = std.mem.Allocator;

pub const Declaration = struct {
    /// kebab-case CSS property name (static string).
    name: []const u8,
    /// CSS value text (allocated in the arena or static).
    value: []const u8,
    important: bool = false,
};

/// Structural information about the element, for `first:` / `odd:` / `nth-3:` / `empty:` ... variants.
pub const ElementInfo = struct {
    /// 0-based position among the parent's element children (a root is index 0 of 1).
    index: u32 = 0,
    count: u32 = 1,
    /// Same, among siblings with the same tag (`div` containers, `span` text, `img` images).
    type_index: u32 = 0,
    type_count: u32 = 1,
    /// No children at all (a text node with non-empty text is not empty).
    empty: bool = false,
};

pub const Target = enum(u2) { element, before, after };

pub const Env = struct {
    /// Output pixels (the render `width`); <= 0 means "not given" and then no breakpoint matches.
    viewport_w: f32,
    viewport_h: f32,
    dpr: f32 = 1,
    /// Unused: takumi has no `dark:` variant (it never applies).
    dark: bool = false,
    /// Needed for structural variants; null -> they never apply.
    element: ?ElementInfo = null,
    /// Which box to compile for: the element itself, or its `::before` / `::after` pseudo-element
    /// (rules with `before:` / `after:`; each such rule also sets `content: ""`, so a non-empty result means
    /// takumi would generate that pseudo-element box).
    target: Target = .element,
    /// Theme variables (takumi `@theme` / `--color-*`, `--spacing`, ... and `--breakpoint-*`); null when
    /// the render defines none (then every utility keeps its built-in value, as in takumi).
    theme: ?*const Theme = null,
};

/// takumi's theme hooks. A themed utility emits `var(--<namespace><token>)` (or `calc(var(--spacing,
/// 0.25rem) * n)`) only when that variable is defined for the element, else its built-in value or
/// nothing (takumi `TwVarRef`).
pub const Theme = struct {
    ctx: *const anyopaque,
    /// Whether custom property `name` (with `--`) is defined for the element.
    defined: *const fn (ctx: *const anyopaque, name: []const u8) bool,
    /// Value text of `--breakpoint-<token>` from the root's custom properties, if any.
    breakpoint: *const fn (ctx: *const anyopaque, token: []const u8) ?[]const u8,
};

/// Compiles a class string. Appends declarations in the order takumi applies them (normal then important,
/// each in Tailwind's utility order), skipping unknown classes and classes whose variants do not apply.
pub fn compile(arena: Allocator, classes: []const u8, env: Env, out: *std.ArrayList(Declaration)) !void {
    var c = Ctx{ .a = arena, .env = env };
    var i: usize = 0;
    while (i < classes.len) {
        while (i < classes.len and isSpace(classes[i])) i += 1;
        const s = i;
        while (i < classes.len and !isSpace(classes[i])) i += 1;
        if (i > s) try c.rule(classes[s..i]);
    }
    const rules = c.rules.items;
    std.sort.heap(Rule, rules, &c, ruleLess);

    // Pass 1: the element's final `--tw-*` values (cascade order, last wins).
    var slots: [p_count]?[]const u8 = @splat(null);
    for (rules) |r| {
        for (c.decls.items[r.d0..][0..r.dn]) |d| {
            if (isVar(d.p)) slots[@backingInt(d.p)] = d.v;
        }
    }
    // Pass 2: emit, substituting variables.
    for (rules) |r| {
        for (c.decls.items[r.d0..][0..r.dn]) |d| {
            if (isVar(d.p)) continue;
            const v = (try resolve(arena, d.v, &slots)) orelse continue;
            try out.append(arena, .{ .name = pName(d.p), .value = v, .important = r.important });
        }
    }
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0c or ch == 0x0b;
}

// ------------------------------------------------------------------------------------------------
// Properties, in Tailwind's GLOBAL_PROPERTY_ORDER (`property_order.rs`). The enum value is the sort rank.
// `tw_*` entries are the element-local variables takumi composes through; they are never emitted.
// Entries from `outline_style` on are not in Tailwind's list (no rank).

/// Paged output (PDF feature; everything on in standalone tests): the `break-before-*` / `break-inside-*` /
/// `break-after-*` utilities (Tailwind v4; takumi's `tw` has none, but its `break-*` properties are what
/// takumi-pdf paginates by). Without the feature the properties are not even in `P`.
const tw_pdf = blk: {
    const root = @import("root");
    break :blk if (@hasDecl(root, "bm_config")) (@hasDecl(root.bm_config, "enable_pdf") and root.bm_config.enable_pdf) else true;
};

pub const P = if (tw_pdf) P_all else without(P_all, "break_");

fn without(comptime E: type, comptime prefix: []const u8) type {
    @setEvalBranchQuota(50_000);
    var names: []const [:0]const u8 = &.{};
    for (@typeInfo(E).@"enum".field_names) |n| {
        if (!std.mem.startsWith(u8, n, prefix)) names = names ++ .{n};
    }
    return @Enum(u8, .exhaustive, names, &std.simd.iota(u8, names.len));
}

const P_all = enum(u8) {
    visibility,
    position,
    inset,
    inset_inline,
    top,
    right,
    bottom,
    left,
    isolation,
    grid_column,
    grid_column_start,
    grid_column_end,
    grid_row,
    grid_row_start,
    grid_row_end,
    margin,
    margin_inline,
    margin_inline_start,
    margin_inline_end,
    margin_top,
    margin_right,
    margin_bottom,
    margin_left,
    box_sizing,
    display,
    aspect_ratio,
    height,
    max_height,
    min_height,
    width,
    max_width,
    min_width,
    flex,
    flex_shrink,
    flex_grow,
    flex_basis,
    transform_origin,
    translate,
    tw_translate_x,
    tw_translate_y,
    scale,
    tw_scale_x,
    tw_scale_y,
    rotate,
    animation,
    list_style_position,
    list_style_type,
    list_style_image,
    break_before,
    break_inside,
    break_after,
    grid_auto_columns,
    grid_auto_flow,
    grid_auto_rows,
    grid_template_columns,
    grid_template_rows,
    flex_direction,
    flex_wrap,
    align_content,
    align_items,
    justify_content,
    justify_items,
    gap,
    column_gap,
    row_gap,
    align_self,
    justify_self,
    overflow,
    overflow_x,
    overflow_y,
    border_radius,
    border_top_left_radius,
    border_top_right_radius,
    border_bottom_right_radius,
    border_bottom_left_radius,
    border_width,
    border_top_width,
    border_right_width,
    border_bottom_width,
    border_left_width,
    border_style,
    border_top_style,
    border_right_style,
    border_bottom_style,
    border_left_style,
    border_color,
    border_top_color,
    border_right_color,
    border_bottom_color,
    border_left_color,
    background_color,
    background_image,
    tw_gradient_stops,
    tw_gradient_via_stops,
    tw_gradient_from,
    tw_gradient_from_position,
    tw_gradient_via,
    tw_gradient_via_position,
    tw_gradient_to,
    tw_gradient_to_position,
    mask_image,
    background_size,
    background_clip,
    background_position,
    background_repeat,
    object_fit,
    object_position,
    padding,
    padding_inline,
    padding_inline_start,
    padding_inline_end,
    padding_top,
    padding_right,
    padding_bottom,
    padding_left,
    text_align,
    vertical_align,
    font_family,
    font_size,
    line_height,
    font_weight,
    letter_spacing,
    text_wrap,
    overflow_wrap,
    word_break,
    text_overflow,
    white_space,
    color,
    text_transform,
    font_style,
    font_stretch,
    text_decoration_line,
    text_decoration_color,
    text_decoration_style,
    text_decoration_thickness,
    opacity,
    background_blend_mode,
    mix_blend_mode,
    box_shadow,
    tw_shadow_color,
    outline_width,
    outline_offset,
    outline_color,
    tw_blur,
    tw_brightness,
    tw_contrast,
    tw_drop_shadow,
    tw_grayscale,
    tw_hue_rotate,
    tw_invert,
    tw_saturate,
    tw_sepia,
    filter,
    tw_backdrop_blur,
    tw_backdrop_brightness,
    tw_backdrop_contrast,
    tw_backdrop_grayscale,
    tw_backdrop_hue_rotate,
    tw_backdrop_invert,
    tw_backdrop_opacity,
    tw_backdrop_saturate,
    tw_backdrop_sepia,
    backdrop_filter,
    contain,
    content,
    // ---- unranked ----
    outline_style,
    line_clamp,
    text_shadow,
    tw_text_shadow_color,
    tw_border_style,
    none,
};

const p_count = @typeInfo(P).@"enum".field_names.len;
const first_unranked: u8 = @backingInt(P.outline_style);

/// Kebab-case names, packed: `p_text[p_off[i]..p_off[i + 1]]`.
const p_tab = blk: {
    @setEvalBranchQuota(50_000);
    const fields = @typeInfo(P).@"enum".field_names;
    var text: []const u8 = "";
    var off: [fields.len + 1]u16 = undefined;
    for (fields, 0..) |f, i| {
        off[i] = text.len;
        // `tw_*` variables are never emitted: no text.
        if (!std.mem.startsWith(u8, f, "tw_")) {
            var buf: [f.len]u8 = undefined;
            for (f, 0..) |ch, j| buf[j] = if (ch == '_') '-' else ch;
            text = text ++ buf;
        }
    }
    off[fields.len] = text.len;
    const final = text[0..text.len].*;
    break :blk .{ .text = @as([]const u8, &final), .off = off };
};

fn pName(p: P) []const u8 {
    const i = @backingInt(p);
    return p_tab.text[p_tab.off[i]..p_tab.off[i + 1]];
}

const var_mask: [32]u8 = blk: {
    var m: [32]u8 = @splat(0);
    for (@typeInfo(P).@"enum".field_names, 0..) |f, i| {
        if (std.mem.startsWith(u8, f, "tw_")) m[i >> 3] |= 1 << (i & 7);
    }
    break :blk m;
};

fn isVar(p: P) bool {
    const i = @backingInt(p);
    return (var_mask[i >> 3] >> @intCast(i & 7)) & 1 != 0;
}

fn pFromName(comptime name: []const u8) P {
    @setEvalBranchQuota(50_000);
    for (@typeInfo(P).@"enum".field_names, 0..) |f, i| {
        if (f.len != name.len) continue;
        var ok = true;
        for (f, name) |x, y| ok = ok and (x == y or (x == '_' and y == '-'));
        if (ok) return @fromBackingInt(@intCast(i));
    }
    @compileError("unknown property " ++ name);
}

// ------------------------------------------------------------------------------------------------
// Rules

const D = struct { p: P, v: []const u8 };

const Rule = struct {
    name: []const u8,
    d0: u32,
    dn: u16,
    important: bool,
    spec: u8,
    /// 0 = no breakpoint, else 1 + bits of its width in rem (positive f32 bits sort like the value).
    bp: u64,
    ranks: u32,
    nk: u8,
    /// Sorted unique property ranks of the rule's declarations (Tailwind's sort key), then 255.
    keys: [12]u8,
};

fn ruleLess(_: *Ctx, a: Rule, b: Rule) bool {
    if (a.important != b.important) return !a.important;
    if (a.spec != b.spec) return a.spec < b.spec;
    if (a.bp != b.bp) return a.bp < b.bp;
    if (a.ranks != b.ranks) return a.ranks < b.ranks;
    var i: usize = 0;
    while (true) : (i += 1) {
        const ka: u8 = if (i < a.nk) a.keys[i] else 255;
        const kb: u8 = if (i < b.nk) b.keys[i] else 255;
        if (ka != kb) return ka < kb;
        if (ka == 255) break;
    }
    return std.mem.order(u8, a.name, b.name) == .lt;
}

const Ctx = struct {
    a: Allocator,
    env: Env,
    decls: std.ArrayList(D) = .empty,
    rules: std.ArrayList(Rule) = .empty,

    fn add(c: *Ctx, p: P, v: []const u8) !void {
        try c.decls.append(c.a, .{ .p = p, .v = v });
    }

    fn rule(c: *Ctx, source: []const u8) !void {
        for (source) |ch| if (ch < 0x20 or ch == 0x7f) return;
        var vs: Variants = .{};
        var rest = source;
        while (splitVariant(rest)) |i| {
            if (!vs.push(rest[0..i], c.env)) return;
            rest = rest[i + 1 ..];
        }
        if (!vs.applies or vs.pseudo != @backingInt(c.env.target)) return;
        var important = false;
        if (rest.len > 0 and rest[0] == '!') {
            important = true;
            rest = rest[1..];
        } else if (rest.len > 0 and rest[rest.len - 1] == '!') {
            important = true;
            rest = rest[0 .. rest.len - 1];
        }
        const start = c.decls.items.len;
        // Tailwind's before:/after: open with `content: var(--tw-content)`, initially the empty string.
        if (vs.pseudo != 0) try c.add(.content, "\"\"");
        if (!try c.utility(rest)) {
            c.decls.shrinkRetainingCapacity(start);
            return;
        }
        try c.finishBorder(start);
        const n = c.decls.items.len - start;
        if (n == 0 or n > 0xffff) {
            c.decls.shrinkRetainingCapacity(start);
            return;
        }
        var r = Rule{
            .name = source,
            .d0 = @intCast(start),
            .dn = @intCast(n),
            .important = important,
            .spec = vs.spec,
            .bp = vs.bp,
            .ranks = vs.ranks,
            .nk = 0,
            .keys = undefined,
        };
        for (c.decls.items[start..]) |d| {
            const k = @backingInt(d.p);
            if (k >= first_unranked) continue;
            // insertion into a sorted unique list
            var j: usize = 0;
            while (j < r.nk and r.keys[j] < k) j += 1;
            if (j < r.nk and r.keys[j] == k) continue;
            if (r.nk == r.keys.len) continue;
            var m: usize = r.nk;
            while (m > j) : (m -= 1) r.keys[m] = r.keys[m - 1];
            r.keys[j] = k;
            r.nk += 1;
        }
        try c.rules.append(c.a, r);
    }

    /// takumi's builder `finish`: a width utility that sets no style draws in `--tw-border-style`.
    fn finishBorder(c: *Ctx, start: usize) !void {
        var has_style = false;
        var widths: [5]P = undefined;
        var nw: usize = 0;
        for (c.decls.items[start..]) |d| switch (d.p) {
            .border_style, .border_top_style, .border_right_style, .border_bottom_style, .border_left_style => has_style = true,
            .border_width, .border_top_width, .border_right_width, .border_bottom_width, .border_left_width => {
                if (nw < widths.len) {
                    widths[nw] = d.p;
                    nw += 1;
                }
            },
            else => {},
        };
        if (has_style) return;
        for (widths[0..nw]) |w| try c.add(@fromBackingInt(@intCast(@backingInt(w) + 5)), "\x01S");
    }

    /// Emits a utility (variants and `!` already stripped). false = no utility reads it.
    fn utility(c: *Ctx, tok: []const u8) !bool {
        if (findFixed(tok)) |f| {
            var i: usize = 0;
            while (i < f.len) {
                const l = f[i + 1];
                try c.add(@fromBackingInt(@intCast(f[i])), f[i + 2 ..][0..l]);
                i += 2 + l;
            }
            return true;
        }
        var t = tok;
        var neg = false;
        if (t.len > 0 and t[0] == '-') {
            neg = true;
            t = t[1..];
        }
        var i = t.len;
        while (i > 0) {
            i -= 1;
            if (t[i] != '-') continue;
            const alts = findPacked(roots_pack, t[0..i]) orelse continue;
            const suffix = t[i + 1 ..];
            var k: usize = 0;
            while (k + 4 <= alts.len) : (k += 4) {
                const alt = Alt{
                    .f = @fromBackingInt(@intCast(alts[k])),
                    .op = @fromBackingInt(@intCast(alts[k + 1] & 0x7f)),
                    .neg = alts[k + 1] & 0x80 != 0,
                    .p1 = @fromBackingInt(@intCast(alts[k + 2])),
                    .p2 = @fromBackingInt(@intCast(alts[k + 3])),
                };
                var v = (try parseForm(c.a, alt.f, suffix)) orelse continue;
                if (neg and !alt.neg) return false;
                if (c.env.theme != null) if (try c.themeValue(alt, suffix, neg, v)) |tv| {
                    try c.emit(alt, tv);
                    return true;
                };
                if (neg) {
                    if (!alt.neg) return false;
                    v = (try negate(c.a, v)) orelse return false;
                }
                try c.emit(alt, v);
                return true;
            }
            if (c.env.theme != null and try c.themeFallback(alts, suffix, neg)) return true;
        }
        return false;
    }

    fn defined(c: *const Ctx, name: []const u8) bool {
        const t = c.env.theme orelse return false;
        return t.defined(t.ctx, name);
    }

    /// takumi `var_expression` + `TwVarRef` for a value that also has a built-in meaning: the themed
    /// value when the variable is defined, else null (keep `builtin`).
    fn themeValue(c: *Ctx, alt: Alt, suffix: []const u8, neg: bool, builtin: []const u8) !?[]const u8 {
        if (alt.op != .set and alt.op != .font_size and alt.f != .var_color) return null;
        const ns = formNs(alt) orelse return null;
        if (suffix.len == 0 or suffix[0] == '[') return null;
        if (std.mem.indexOfScalar(u8, suffix, '/')) |sl| {
            if (!eql(ns[0], "--color-")) return null;
            const pct = suffix[sl + 1 ..];
            const p = parseNum(pct) orelse return null;
            if (!(p >= 0 and p <= 100)) return null;
            const name = try cat(c.a, &.{ ns[0], suffix[0..sl] });
            if (!c.defined(name)) return null;
            return try cat(c.a, &.{ "color-mix(in oklab, var(", name, ") ", pct, "%, transparent)" });
        }
        if (parseNum(suffix) != null and nsHas(ns, "--spacing-")) {
            if (!c.defined("--spacing")) return null;
            return try cat(c.a, &.{ "calc(var(--spacing, 0.25rem) * ", if (neg) "-" else "", suffix, ")" });
        }
        const e = (try c.themeExpr(ns, suffix, neg)) orelse return null;
        if (alt.op != .font_size) return e.expr;
        // `--text-*`: font-size, then the companion `--text-*--line-height` (else the built-in one)
        const lh_name = try cat(c.a, &.{ e.name, "--line-height" });
        const z = std.mem.indexOfScalar(u8, builtin, 0);
        if (c.defined(lh_name)) return try cat(c.a, &.{ e.expr, "\x00var(", lh_name, ")" });
        return if (z) |k| try cat(c.a, &.{ e.expr, builtin[k..] }) else e.expr;
    }

    const ThemeExpr = struct { name: []const u8, expr: []const u8 };

    /// `var(--ns-token)` (negated: `calc(var(..) * -1)`) for the first namespace in `ns` whose
    /// variable is defined.
    fn themeExpr(c: *Ctx, ns: [2][]const u8, suffix: []const u8, neg: bool) !?ThemeExpr {
        for (ns) |prefix| {
            if (prefix.len == 0) continue;
            const name = try cat(c.a, &.{ prefix, suffix });
            if (!c.defined(name)) continue;
            return .{ .name = name, .expr = try cat(c.a, &.{ if (neg) "calc(var(" else "var(", name, if (neg) ") * -1)" else ")" }) };
        }
        return null;
    }

    /// No value form reads `suffix`: the root's theme groups (takumi `Utility::theme`) emit
    /// `var(--<namespace><suffix>)` for each namespaced form whose variable is defined.
    fn themeFallback(c: *Ctx, alts: []const u8, suffix: []const u8, neg: bool) !bool {
        if (suffix.len == 0 or suffix[0] == '[') return false;
        const slash = std.mem.indexOfScalar(u8, suffix, '/');
        var done = false;
        var k: usize = 0;
        while (k + 4 <= alts.len) : (k += 4) {
            const alt = Alt{
                .f = @fromBackingInt(@intCast(alts[k])),
                .op = @fromBackingInt(@intCast(alts[k + 1] & 0x7f)),
                .neg = alts[k + 1] & 0x80 != 0,
                .p1 = @fromBackingInt(@intCast(alts[k + 2])),
                .p2 = @fromBackingInt(@intCast(alts[k + 3])),
            };
            if (alt.op != .set and alt.op != .font_size) continue;
            if (neg and !alt.neg) continue;
            const ns = formNs(alt) orelse continue;
            if (slash != null) {
                // `bg-brand/50`: colours only (takumi `var_expression`)
                if (!eql(ns[0], "--color-") or neg) continue;
                const v = (try c.themeValue(alt, suffix, false, "")) orelse continue;
                try c.emit(alt, v);
                done = true;
                continue;
            }
            const e = (try c.themeExpr(ns, suffix, neg)) orelse continue;
            if (alt.op == .font_size) {
                const lh_name = try cat(c.a, &.{ e.name, "--line-height" });
                try c.add(.font_size, e.expr);
                if (c.defined(lh_name)) try c.add(.line_height, try cat(c.a, &.{ "var(", lh_name, ")" }));
            } else try c.emit(alt, e.expr);
            done = true;
        }
        return done;
    }

    fn emit(c: *Ctx, alt: Alt, v: []const u8) !void {
        switch (alt.op) {
            .set, .border_width => {
                try c.add(alt.p1, v);
                if (alt.p2 != .none) try c.add(alt.p2, v);
            },
            .font_size => {
                const z = std.mem.indexOfScalar(u8, v, 0) orelse v.len;
                try c.add(.font_size, v[0..z]);
                if (z < v.len) try c.add(.line_height, v[z + 1 ..]);
            },
            .border_style => {
                try c.add(.tw_border_style, v);
                try c.add(.border_style, v);
            },
            .axes => {
                try c.add(alt.p1, v);
                if (alt.p2 != .none) try c.add(alt.p2, v);
                if (alt.p1 == .tw_translate_x or alt.p1 == .tw_translate_y)
                    try c.add(.translate, "\x01x \x01y")
                else
                    try c.add(.scale, "\x01X \x01Y");
            },
            .filter => {
                const k = @backingInt(alt.p1);
                const backdrop = k > @backingInt(P.filter);
                const fn_name = nth("blur|brightness|contrast|drop-shadow|grayscale|hue-rotate|invert|saturate|sepia|" ++
                    "blur|brightness|contrast|grayscale|hue-rotate|invert|opacity|saturate|sepia", k - @backingInt(P.tw_blur) - @intFromBool(backdrop));
                try c.add(alt.p1, try cat(c.a, &.{ fn_name, "(", v, ")" }));
                if (backdrop) try c.add(.backdrop_filter, "\x01B") else try c.add(.filter, "\x01F");
            },
            .grad_color => {
                try c.add(alt.p1, v);
                // `from`/`to` set the stops to `var(--tw-gradient-via-stops, <from>, <to>)` ("F"), `via` to
                // `var(--tw-gradient-via-stops)` without a fallback ("V").
                const via = alt.p1 == .tw_gradient_via;
                try c.add(.tw_gradient_stops, if (via) "V" else "F");
                if (via) try c.add(.tw_gradient_via_stops, "1");
            },
            .shadow_arb => try c.add(alt.p1, try cat(c.a, &.{ if (alt.p1 == .box_shadow) "\x04" else "\x05", v })),
            .bg_linear => try c.add(.background_image, try cat(c.a, &.{ "linear-gradient(", v, " in oklab, \x01G)" })),
            .bg_conic => try c.add(.background_image, if (eql(v, "0deg"))
                "conic-gradient(in oklab, \x01G)"
            else
                try cat(c.a, &.{ "conic-gradient(from ", v, " in oklab, \x01G)" })),
        }
    }
};

/// The theme namespaces (custom-property prefixes, takumi `Namespace`) a value form reads, in order;
/// null = not themable. `max-w-*` reads `--container-*` before `--spacing-*`.
fn formNs(alt: Alt) ?[2][]const u8 {
    const one: []const u8 = switch (alt.f) {
        .color, .var_color => "--color-",
        .length, .size, .basis => if (alt.p1 == .max_width) return .{ "--container-", "--spacing-" } else "--spacing-",
        .radius => "--radius-",
        .font_size => "--text-",
        .font_family => "--font-",
        .font_weight => "--font-weight-",
        .tracking => "--tracking-",
        .line_height => "--leading-",
        .aspect => "--aspect-",
        .animation => "--animate-",
        else => return null,
    };
    return .{ one, "" };
}

fn nsHas(ns: [2][]const u8, prefix: []const u8) bool {
    return eql(ns[0], prefix) or eql(ns[1], prefix);
}

noinline fn cat(a: Allocator, parts: []const []const u8) ![]const u8 {
    return std.mem.concat(a, u8, parts);
}

// ------------------------------------------------------------------------------------------------
// Variants (`variant.rs`)

const Variants = struct {
    applies: bool = true,
    has_bp: bool = false,
    pseudo: u2 = 0,
    bp: u64 = 0,
    ranks: u32 = 0,
    spec: u8 = 1,

    /// false: the class is dropped (unknown non-identifier variant, second breakpoint/pseudo-element).
    fn push(vs: *Variants, tok: []const u8, env: Env) bool {
        if (eql(tok, "before") or eql(tok, "after")) {
            if (vs.pseudo != 0) return false;
            vs.pseudo = if (tok[0] == 'b') 1 else 2;
            vs.ranks |= @as(u32, if (tok[0] == 'b') 1 << 1 else 1 << 2);
            return true;
        }
        if (structural(tok, env.element)) |s| {
            vs.ranks |= @as(u32, 1) << s.rank;
            vs.spec +|= s.spec;
            if (!s.matches) vs.applies = false;
            return true;
        }
        // Breakpoint (any identifier; only the five built-in ones can match).
        const widths = [_]struct { []const u8, f32 }{ .{ "sm", 40 }, .{ "md", 48 }, .{ "lg", 64 }, .{ "xl", 80 }, .{ "2xl", 96 } };
        var rem: ?f32 = null;
        for (widths) |w| {
            if (std.ascii.eqlIgnoreCase(tok, w[0])) rem = w[1];
        }
        if (rem == null and !isIdent(tok)) return false;
        if (vs.has_bp) return false;
        vs.has_bp = true;
        const dpr = if (env.dpr > 0 and env.dpr < 1e6) env.dpr else 1;
        // takumi `collect_breakpoints`: a `--breakpoint-<token>` (rem / px / vw) re-sizes the variant
        var over: ?f32 = null;
        if (env.theme) |t| if (t.breakpoint(t.ctx, tok)) |txt| {
            over = bpLength(txt, env.viewport_w, dpr);
        };
        vs.bp = 1 + @as(u64, @as(u32, @bitCast(rem orelse std.math.inf(f32))));
        if (rem == null and over == null) {
            vs.applies = false;
            return true;
        }
        if (!(env.viewport_w >= 1)) {
            vs.applies = false;
        } else {
            const vw: u32 = if (env.viewport_w >= 4e9) std.math.maxInt(u32) else @intFromFloat(env.viewport_w);
            const px = over orelse rem.? * 16 * dpr;
            const bpx: u32 = if (px >= 4e9) std.math.maxInt(u32) else @intFromFloat(px);
            if (vw < bpx) vs.applies = false;
        }
        return true;
    }
};

/// A `--breakpoint-*` value in device px (takumi `Breakpoint::matches`: rem = 16 px, px, vw); null for
/// any other value.
fn bpLength(txt: []const u8, viewport_w: f32, dpr: f32) ?f32 {
    const s = std.mem.trim(u8, txt, " \t\n\r");
    var unit: usize = s.len;
    while (unit > 0 and std.ascii.isAlphabetic(s[unit - 1])) unit -= 1;
    const n = parseNum(s[0..unit]) orelse return null;
    const u = s[unit..];
    const px = if (std.ascii.eqlIgnoreCase(u, "rem")) n * 16 * dpr else if (std.ascii.eqlIgnoreCase(u, "px")) n * dpr else if (std.ascii.eqlIgnoreCase(u, "vw")) n / 100 * viewport_w else return null;
    return if (px < 0) 0 else px;
}

const Structural = struct { rank: u5, spec: u8, matches: bool };

/// Tailwind's registered structural variants, in registration order, with their pseudo-classes.
const registered = "first=first-child|last=last-child|only=only-child|odd=nth-child(odd)|even=nth-child(even)|" ++
    "first-of-type|last-of-type|only-of-type|empty";
/// The functional ones: `nth-3`, `nth-last-[2n]`, ... (longest prefix first; rank = position in Tailwind's list).
const nth_prefixes = [_]struct { []const u8, []const u8, u5 }{
    .{ "nth-last-of-type-", "nth-last-of-type", 3 },
    .{ "nth-of-type-", "nth-of-type", 2 },
    .{ "nth-last-", "nth-last-child", 1 },
    .{ "nth-", "nth-child", 0 },
};

/// A structural variant (`first`, `not-odd`, `nth-3`, `[&:nth-child(2n)]`), evaluated against `el`.
/// null: not a structural variant.
fn structural(tok: []const u8, el: ?ElementInfo) ?Structural {
    var t = tok;
    var negated = false;
    while (starts(t, "not-")) {
        t = t[4..];
        negated = !negated;
    }
    var rank: u5 = 0;
    var m: Match = .{};
    var buf: [256]u8 = undefined;
    if (lookup(registered, t, false)) |hit| {
        rank = @intCast(3 + hit.idx);
        if (el) |e| m = matchPseudo(hit.val, e);
    } else if (starts(t, "[&") and t.len >= 3 and t[t.len - 1] == ']') {
        const dec = decodeSimple(t[2 .. t.len - 1], &buf) orelse return null;
        if (dec.len == 0 or dec[0] != ':') return null;
        rank = 3 + 9 + 4;
        if (el) |e| m = matchCompound(dec, e, true);
    } else {
        for (nth_prefixes) |np| {
            if (!starts(t, np[0])) continue;
            const arg = t[np[0].len..];
            rank = 3 + 9 + np[2];
            const ab = if (arg.len >= 2 and arg[0] == '[' and arg[arg.len - 1] == ']')
                parseAnB(decodeSimple(arg[1 .. arg.len - 1], &buf) orelse return null)
            else
                AnB{ .a = 0, .b = @intCast(parseUint(arg, u16) orelse return null) };
            if (el) |e| m = if (ab) |x| .{ .ok = matchNth(np[1], x, e) } else .{ .known = false };
            break;
        } else return null;
    }
    if (!eql(t, tok)) rank = 0; // any `not-`
    const ok = el != null and m.known and (m.ok != negated);
    return .{ .rank = rank, .spec = m.spec, .matches = ok };
}

const Match = struct { ok: bool = false, known: bool = true, spec: u8 = 1 };

/// One pseudo-class without its colon (`first-child`, `nth-last-of-type(2n+1)`, `empty`).
fn matchPseudo(css: []const u8, e: ElementInfo) Match {
    var name = css;
    var ab = AnB{ .a = 0, .b = 1 };
    if (std.mem.indexOfScalar(u8, css, '(')) |open| {
        if (css[css.len - 1] != ')' or !starts(css, "nth-")) return .{ .known = false };
        name = css[0..open];
        ab = parseAnB(css[open + 1 .. css.len - 1]) orelse return .{ .known = false };
    }
    if (eql(name, "empty")) return .{ .ok = e.empty };
    if (kw("first-child|last-child|only-child|first-of-type|last-of-type|only-of-type|nth-child|nth-last-child|nth-of-type|nth-last-of-type", name) == null)
        return .{ .known = false };
    if (starts(name, "only-")) {
        const of_type = ends(name, "of-type");
        return .{ .ok = (if (of_type) e.type_count else e.count) == 1 };
    }
    return .{ .ok = matchNth(name, ab, e) };
}

/// A compound of pseudo-classes (`:first-child:nth-child(2n)`, one level of `:not(...)`).
fn matchCompound(s: []const u8, e: ElementInfo, allow_not: bool) Match {
    var res: Match = .{ .ok = true, .spec = 0 };
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] != ':') return .{ .known = false };
        const st = i + 1;
        i = st;
        var depth: usize = 0;
        while (i < s.len and !(s[i] == ':' and depth == 0)) : (i += 1) {
            if (s[i] == '(') depth += 1 else if (s[i] == ')') depth -|= 1;
        }
        const part = s[st..i];
        const m = if (allow_not and starts(part, "not(") and part[part.len - 1] == ')') blk: {
            const inner = matchCompound(trimSp(part[4 .. part.len - 1]), e, false);
            break :blk Match{ .ok = !inner.ok, .known = inner.known, .spec = inner.spec };
        } else matchPseudo(part, e);
        if (!m.known) return m;
        res.ok = res.ok and m.ok;
        res.spec +|= m.spec;
    }
    if (res.spec == 0) return .{ .known = false };
    return res;
}

const AnB = struct { a: i32, b: i32 };

/// `An+B` microsyntax (`odd`, `even`, `3`, `-n+3`, `2n + 1`).
fn parseAnB(s0: []const u8) ?AnB {
    const s = trimSp(s0);
    if (std.ascii.eqlIgnoreCase(s, "odd")) return .{ .a = 2, .b = 1 };
    if (std.ascii.eqlIgnoreCase(s, "even")) return .{ .a = 2, .b = 0 };
    const n = std.mem.indexOfAny(u8, s, "nN") orelse return .{ .a = 0, .b = parseSigned(s) orelse return null };
    const as = trimSp(s[0..n]);
    const a: i32 = if (as.len == 0 or eql(as, "+")) 1 else if (eql(as, "-")) -1 else parseSigned(as) orelse return null;
    const bs = trimSp(s[n + 1 ..]);
    if (bs.len > 0 and bs[0] != '+' and bs[0] != '-') return null;
    return .{ .a = a, .b = if (bs.len == 0) 0 else parseSigned(bs) orelse return null };
}

fn parseSigned(s: []const u8) ?i32 {
    var t = s;
    var neg = false;
    if (t.len > 0 and (t[0] == '+' or t[0] == '-')) {
        neg = t[0] == '-';
        t = trimSp(t[1..]);
    }
    const v = parseUint(t, u32) orelse return null;
    if (v > 100_000_000) return null;
    const x: i32 = @intCast(v);
    return if (neg) -x else x;
}

fn trimSp(s: []const u8) []const u8 {
    var a: usize = 0;
    var b = s.len;
    while (a < b and s[a] == ' ') a += 1;
    while (b > a and s[b - 1] == ' ') b -= 1;
    return s[a..b];
}

/// Entry `i` of a `|` list.
fn nth(list: []const u8, i: usize) []const u8 {
    var start: usize = 0;
    var k: usize = 0;
    while (k < i) : (k += 1) start = (std.mem.indexOfScalarPos(u8, list, start, '|') orelse return "") + 1;
    return list[start .. std.mem.indexOfScalarPos(u8, list, start, '|') orelse list.len];
}

fn matchNth(name: []const u8, ab: AnB, el: ElementInfo) bool {
    const of_type = ends(name, "of-type");
    const idx: i64 = if (of_type) el.type_index else el.index;
    const cnt: i64 = if (of_type) el.type_count else el.count;
    const pos: i64 = if (has(name, "last")) cnt - idx else idx + 1;
    const d = pos - ab.b;
    if (ab.a == 0) return d == 0;
    return @rem(d, ab.a) == 0 and @divTrunc(d, ab.a) >= 0;
}

/// Tailwind `segment` for variants: the first `:` outside brackets / quotes / escapes.
fn splitVariant(tok: []const u8) ?usize {
    var stack: [32]u8 = undefined;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < tok.len) : (i += 1) {
        const ch = tok[i];
        switch (ch) {
            '\\' => i += 1,
            '\'', '"' => {
                i += 1;
                while (i < tok.len and tok[i] != ch) i += if (tok[i] == '\\') 2 else 1;
            },
            '(' => push(&stack, &depth, ')'),
            '[' => push(&stack, &depth, ']'),
            '{' => push(&stack, &depth, '}'),
            ')', ']', '}' => if (depth > 0 and (depth > stack.len or stack[depth - 1] == ch)) {
                depth -= 1;
            },
            ':' => if (depth == 0) return i,
            else => {},
        }
    }
    return null;
}

fn push(stack: *[32]u8, depth: *usize, ch: u8) void {
    if (depth.* < stack.len) stack[depth.*] = ch;
    depth.* += 1;
}

/// Variant-argument decoding (`variant.rs` `arbitrary`): `_` -> space, `\_` -> `_`. Bounded by `buf`.
fn decodeSimple(s: []const u8, buf: []u8) ?[]const u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (n >= buf.len) return null;
        if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '_') {
            buf[n] = '_';
            i += 1;
        } else buf[n] = if (s[i] == '_') ' ' else s[i];
        n += 1;
    }
    return buf[0..n];
}

// ------------------------------------------------------------------------------------------------
// Fixed utilities (a root alone): `name` -> declarations. Values may hold variable placeholders:
// `\x01c` = variable c with its default, `\x02c<aa>\x03` = shadow colour c, default `#000000<aa>`.

/// One packed record: `[name len][name][decl bytes len]` then per declaration `[property][value len][value]`.
fn fx(comptime n: []const u8, comptime spec: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(200_000);
        var ds: []const u8 = "";
        var it = std.mem.splitScalar(u8, spec, ';');
        while (it.next()) |part| {
            const colon = std.mem.indexOfScalar(u8, part, ':').?;
            const v = part[colon + 1 ..];
            ds = ds ++ [_]u8{ @backingInt(pFromName(part[0..colon])), v.len } ++ v;
        }
        if (ds.len > 255 or n.len > 255) @compileError("fixed record too long: " ++ n);
        return [_]u8{n.len} ++ n ++ [_]u8{ds.len} ++ ds;
    }
}

fn pack(comptime list: []const []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(200_000);
        var s: []const u8 = "";
        for (list) |x| s = s ++ x;
        const final = s[0..s.len].*;
        return &final;
    }
}

const sc = "\x02s"; // shadow colour slot open
const tc = "\x02t"; // text-shadow colour slot open
const se = "\x03";
fn bsh(comptime inset: bool, comptime oy: []const u8, comptime blur: []const u8, comptime spread: []const u8, comptime a: []const u8) []const u8 {
    return (if (inset) "inset " else "") ++ "0px " ++ oy ++ "px " ++ blur ++ "px " ++ spread ++ "px " ++ sc ++ a ++ se;
}
fn tsh(comptime oy: []const u8, comptime blur: []const u8, comptime a: []const u8) []const u8 {
    return "0px " ++ oy ++ "px " ++ blur ++ "px " ++ tc ++ a ++ se;
}
fn dsh(comptime oy: []const u8, comptime blur: []const u8, comptime a: []const u8) []const u8 {
    return "tw-drop-shadow:drop-shadow(0px " ++ oy ++ "px " ++ blur ++ "px #000000" ++ a ++ ");filter:\x01F";
}
const shadow_sm = bsh(false, "1", "3", "0", "1a") ++ ", " ++ bsh(false, "1", "2", "-1", "1a");

const fixed_pack = pack(&.{
    // display / position / box
    fx("block", "display:block"),
    fx("inline", "display:inline"),
    fx("inline-block", "display:inline-block"),
    fx("inline-flex", "display:inline-flex"),
    fx("inline-grid", "display:inline-grid"),
    fx("flow-root", "display:flow-root"),
    fx("contents", "display:contents"),
    fx("grid", "display:grid"),
    fx("hidden", "display:none"),
    fx("list-item", "display:list-item"),
    fx("flex", "display:flex"),
    fx("absolute", "position:absolute"),
    fx("relative", "position:relative"),
    fx("static", "position:static"),
    fx("fixed", "position:fixed"),
    fx("box-border", "box-sizing:border-box"),
    fx("box-content", "box-sizing:content-box"),
    fx("contain-none", "contain:none"),
    fx("contain-content", "contain:content"),
    fx("contain-layout", "contain:layout"),
    fx("contain-style", "contain:style"),
    fx("contain-paint", "contain:paint"),
    fx("isolate", "isolation:isolate"),
    fx("isolation-auto", "isolation:auto"),
    fx("visible", "visibility:visible"),
    fx("invisible", "visibility:hidden"),
    // sizing
    fx("w-screen", "width:100vw"),
    fx("h-screen", "height:100vh"),
    fx("min-w-screen", "min-width:100vw"),
    fx("min-h-screen", "min-height:100vh"),
    fx("max-w-screen", "max-width:100vw"),
    fx("max-h-screen", "max-height:100vh"),
    fx("aspect-auto", "aspect-ratio:auto"),
    // flex / grid
    fx("flex-auto", "flex:1 1 auto"),
    fx("flex-initial", "flex:0 1 auto"),
    fx("flex-none", "flex:0 0 auto"),
    fx("flex-row", "flex-direction:row"),
    fx("flex-row-reverse", "flex-direction:row-reverse"),
    fx("flex-col", "flex-direction:column"),
    fx("flex-col-reverse", "flex-direction:column-reverse"),
    fx("flex-wrap", "flex-wrap:wrap"),
    fx("flex-wrap-reverse", "flex-wrap:wrap-reverse"),
    fx("flex-nowrap", "flex-wrap:nowrap"),
    fx("grow|flex-grow", "flex-grow:1"),
    fx("shrink|flex-shrink", "flex-shrink:1"),
    fx("grid-flow-row", "grid-auto-flow:row"),
    fx("grid-flow-col", "grid-auto-flow:column"),
    fx("grid-flow-row-dense|grid-flow-dense", "grid-auto-flow:row dense"),
    fx("grid-flow-col-dense", "grid-auto-flow:column dense"),
    fx("col-span-full", "grid-column:1 / -1"),
    fx("row-span-full", "grid-row:1 / -1"),
    fx("col-start-auto", "grid-column-start:auto"),
    fx("col-end-auto", "grid-column-end:auto"),
    fx("row-start-auto", "grid-row-start:auto"),
    fx("row-end-auto", "grid-row-end:auto"),
    // backgrounds
    fx("bg-repeat", "background-repeat:repeat"),
    fx("bg-no-repeat", "background-repeat:no-repeat"),
    fx("bg-space|bg-repeat-space", "background-repeat:space"),
    fx("bg-round|bg-repeat-round", "background-repeat:round"),
    fx("bg-repeat-x", "background-repeat:repeat no-repeat"),
    fx("bg-repeat-y", "background-repeat:no-repeat repeat"),
    fx("bg-radial", "background-image:radial-gradient(in oklab, \x01G)"),
    fx("bg-conic", "background-image:conic-gradient(in oklab, \x01G)"),
    // borders
    fx("border", "border-width:1px"),
    fx("border-t", "border-top-width:1px"),
    fx("border-r", "border-right-width:1px"),
    fx("border-b", "border-bottom-width:1px"),
    fx("border-l", "border-left-width:1px"),
    fx("border-x", "border-left-width:1px;border-right-width:1px"),
    fx("border-y", "border-top-width:1px;border-bottom-width:1px"),
    fx("outline", "outline-width:1px;outline-style:solid"),
    fx("rounded", "border-radius:0.25rem"),
    // typography
    fx("text-ellipsis", "text-overflow:ellipsis"),
    fx("text-clip", "text-overflow:clip"),
    fx("truncate", "text-overflow:ellipsis;white-space:nowrap;overflow:hidden"),
    fx("decoration-solid", "text-decoration-style:solid"),
    fx("decoration-double", "text-decoration-style:double"),
    fx("decoration-dotted", "text-decoration-style:dotted"),
    fx("decoration-dashed", "text-decoration-style:dashed"),
    fx("decoration-wavy", "text-decoration-style:wavy"),
    fx("underline", "text-decoration-line:underline"),
    fx("overline", "text-decoration-line:overline"),
    fx("line-through", "text-decoration-line:line-through"),
    fx("no-underline", "text-decoration-line:none"),
    fx("uppercase", "text-transform:uppercase"),
    fx("lowercase", "text-transform:lowercase"),
    fx("capitalize", "text-transform:capitalize"),
    fx("normal-case", "text-transform:none"),
    fx("italic", "font-style:italic"),
    fx("not-italic", "font-style:normal"),
    fx("break-normal", "word-break:normal"),
    fx("break-all", "word-break:break-all"),
    fx("break-keep", "word-break:keep-all"),
    // effects
    fx("shadow|shadow-sm", "box-shadow:" ++ shadow_sm),
    fx("shadow-2xs", "box-shadow:" ++ bsh(false, "1", "0", "0", "0d")),
    fx("shadow-xs", "box-shadow:" ++ bsh(false, "1", "2", "0", "0d")),
    fx("shadow-md", "box-shadow:" ++ bsh(false, "4", "6", "-1", "1a") ++ ", " ++ bsh(false, "2", "4", "-2", "1a")),
    fx("shadow-lg", "box-shadow:" ++ bsh(false, "10", "15", "-3", "1a") ++ ", " ++ bsh(false, "4", "6", "-4", "1a")),
    fx("shadow-xl", "box-shadow:" ++ bsh(false, "20", "25", "-5", "1a") ++ ", " ++ bsh(false, "8", "10", "-6", "1a")),
    fx("shadow-2xl", "box-shadow:" ++ bsh(false, "25", "50", "-12", "40")),
    fx("shadow-none|inset-shadow-none", "box-shadow:none"),
    fx("inset-shadow-2xs", "box-shadow:" ++ bsh(true, "1", "0", "0", "0d")),
    fx("inset-shadow-xs", "box-shadow:" ++ bsh(true, "1", "1", "0", "0d")),
    fx("inset-shadow-sm", "box-shadow:" ++ bsh(true, "2", "4", "0", "0d")),
    fx("text-shadow-2xs", "text-shadow:" ++ tsh("1", "0", "26")),
    fx("text-shadow-xs", "text-shadow:" ++ tsh("1", "1", "33")),
    fx("text-shadow-sm", "text-shadow:" ++ tsh("1", "0", "13") ++ ", " ++ tsh("1", "1", "13") ++ ", " ++ tsh("2", "2", "13")),
    fx("text-shadow-md", "text-shadow:" ++ tsh("1", "1", "1a") ++ ", " ++ tsh("1", "2", "1a") ++ ", " ++ tsh("2", "4", "1a")),
    fx("text-shadow-lg", "text-shadow:" ++ tsh("1", "2", "1a") ++ ", " ++ tsh("3", "2", "1a") ++ ", " ++ tsh("4", "8", "1a")),
    fx("text-shadow-none", "text-shadow:none"),
    fx("drop-shadow", dsh("1", "2", "1a")),
    fx("drop-shadow-xs", dsh("1", "1", "0d")),
    fx("drop-shadow-sm", dsh("1", "2", "26")),
    fx("drop-shadow-md", dsh("3", "3", "1f")),
    fx("drop-shadow-lg", dsh("4", "4", "26")),
    fx("drop-shadow-xl", dsh("9", "7", "1a")),
    fx("drop-shadow-2xl", dsh("25", "25", "26")),
    fx("drop-shadow-none", "tw-drop-shadow:drop-shadow(0px 0px 0px #00000000);filter:\x01F"),
    fx("grayscale", "tw-grayscale:grayscale(100%);filter:\x01F"),
    fx("invert", "tw-invert:invert(100%);filter:\x01F"),
    fx("sepia", "tw-sepia:sepia(100%);filter:\x01F"),
    fx("backdrop-grayscale", "tw-backdrop-grayscale:grayscale(100%);backdrop-filter:\x01B"),
    fx("backdrop-invert", "tw-backdrop-invert:invert(100%);backdrop-filter:\x01B"),
    fx("backdrop-sepia", "tw-backdrop-sepia:sepia(100%);backdrop-filter:\x01B"),
});

/// Paged output only (`tw_pdf`): `all` breaks every fragmentation context, i.e. the page.
const fixed_pdf_pack = if (tw_pdf) pack(&.{
    fx("break-before-auto", "break-before:auto"),
    fx("break-before-avoid", "break-before:avoid"),
    fx("break-before-all|break-before-page", "break-before:page"),
    fx("break-before-avoid-page", "break-before:avoid-page"),
    fx("break-before-left", "break-before:left"),
    fx("break-before-right", "break-before:right"),
    fx("break-before-column", "break-before:column"),
    fx("break-inside-auto", "break-inside:auto"),
    fx("break-inside-avoid", "break-inside:avoid"),
    fx("break-inside-avoid-page", "break-inside:avoid-page"),
    fx("break-inside-avoid-column", "break-inside:avoid-column"),
    fx("break-after-auto", "break-after:auto"),
    fx("break-after-avoid", "break-after:avoid"),
    fx("break-after-all|break-after-page", "break-after:page"),
    fx("break-after-avoid-page", "break-after:avoid-page"),
    fx("break-after-left", "break-after:left"),
    fx("break-after-right", "break-after:right"),
    fx("break-after-column", "break-after:column"),
}) else "";

/// The declaration bytes of the fixed utility `tok`.
fn findFixed(tok: []const u8) ?[]const u8 {
    if (comptime tw_pdf) if (findPacked(fixed_pdf_pack, tok)) |d| return d;
    return findPacked(fixed_pack, tok);
}

/// Scans `[len][keys][len][payload]` records (`keys` = `|`-separated aliases); returns the payload of `key`.
fn findPacked(data: []const u8, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < data.len) {
        const nl = data[i];
        const name = data[i + 1 ..][0..nl];
        const pl = data[i + 1 + nl];
        const payload = data[i + 2 + nl ..][0..pl];
        if (lookup(name, key, false) != null) return payload;
        i += 2 + nl + pl;
    }
    return null;
}

// ------------------------------------------------------------------------------------------------
// Functional roots (`utility.rs` UTILITIES): root -> value forms tried in order.

const Form = enum(u8) {
    length,
    size,
    basis,
    color,
    var_color,
    angle,
    pct,
    font_size,
    line_height,
    tracking,
    radius,
    line_width,
    border_style,
    font_weight,
    font_family,
    font_stretch,
    flex,
    number,
    grid_template,
    grid_track,
    grid_line,
    grid_placement,
    span,
    aspect,
    line_clamp,
    blur,
    drop_shadow,
    shadow,
    bg_image,
    position,
    bg_size,
    grad_pos,
    thickness,
    bg_clip,
    white_space,
    text_wrap,
    text_align,
    content,
    filters,
    overflow,
    valign,
    object_fit,
    list_type,
    list_pos,
    list_image,
    blend,
    overflow_wrap,
    align_items,
    justify,
    animation,
};

const Op = enum(u8) { set, font_size, border_width, border_style, axes, filter, grad_color, shadow_arb, bg_linear, bg_conic };

const Alt = struct { f: Form, op: Op = .set, neg: bool = false, p1: P = .none, p2: P = .none };

fn s1(f: Form, p: P) Alt {
    return .{ .f = f, .p1 = p };
}
fn s2(f: Form, p: P, q: P) Alt {
    return .{ .f = f, .p1 = p, .p2 = q };
}
fn n1(f: Form, p: P) Alt {
    return .{ .f = f, .p1 = p, .neg = true };
}
fn n2(f: Form, p: P, q: P) Alt {
    return .{ .f = f, .p1 = p, .p2 = q, .neg = true };
}
fn op(f: Form, o: Op, p: P, q: P, neg: bool) Alt {
    return .{ .f = f, .op = o, .p1 = p, .p2 = q, .neg = neg };
}
fn flt(f: Form, p: P, neg: bool) Alt {
    return .{ .f = f, .op = .filter, .p1 = p, .neg = neg };
}

/// A root's packed record: `[len][root][4 * alts]`, each alt `[form][op | neg << 7][p1][p2]`.
fn rt(comptime r: []const u8, comptime alts: []const Alt) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (alts) |x| s = s ++ [_]u8{ @backingInt(x.f), @as(u8, @backingInt(x.op)) | (if (x.neg) 0x80 else 0), @backingInt(x.p1), @backingInt(x.p2) };
        return [_]u8{r.len} ++ r ++ [_]u8{s.len} ++ s;
    }
}

const roots_pack = pack(&.{
    rt("list", &.{ s1(.list_type, .list_style_type), s1(.list_pos, .list_style_position) }),
    rt("list-image", &.{s1(.list_image, .list_style_image)}),
    rt("object", &.{ s1(.object_fit, .object_fit), s1(.position, .object_position) }),
    rt("bg", &.{ s1(.color, .background_color), s1(.bg_image, .background_image), s1(.position, .background_position), s1(.bg_size, .background_size) }),
    rt("bg-clip", &.{s1(.bg_clip, .background_clip)}),
    rt("mask", &.{s1(.bg_image, .mask_image)}),
    rt("bg-linear", &.{op(.angle, .bg_linear, .none, .none, false)}),
    rt("bg-conic", &.{op(.angle, .bg_conic, .none, .none, false)}),
    rt("from", &.{ s1(.grad_pos, .tw_gradient_from_position), op(.var_color, .grad_color, .tw_gradient_from, .none, false) }),
    rt("to", &.{ s1(.grad_pos, .tw_gradient_to_position), op(.var_color, .grad_color, .tw_gradient_to, .none, false) }),
    rt("via", &.{ s1(.grad_pos, .tw_gradient_via_position), op(.var_color, .grad_color, .tw_gradient_via, .none, false) }),
    rt("bg-size", &.{s1(.bg_size, .background_size)}),
    rt("bg-position", &.{s1(.position, .background_position)}),
    rt("w", &.{s1(.size, .width)}),
    rt("h", &.{s1(.size, .height)}),
    rt("min-w", &.{s1(.length, .min_width)}),
    rt("min-h", &.{s1(.length, .min_height)}),
    rt("max-w", &.{s1(.length, .max_width)}),
    rt("max-h", &.{s1(.length, .max_height)}),
    rt("size", &.{s2(.size, .width, .height)}),
    rt("font", &.{ s1(.font_weight, .font_weight), s1(.font_family, .font_family) }),
    rt("font-stretch", &.{s1(.font_stretch, .font_stretch)}),
    rt("gap", &.{s1(.length, .gap)}),
    rt("gap-x", &.{s1(.length, .column_gap)}),
    rt("gap-y", &.{s1(.length, .row_gap)}),
    rt("justify", &.{s1(.justify, .justify_content)}),
    rt("content", &.{ s1(.content, .content), s1(.justify, .align_content) }),
    rt("items", &.{s1(.align_items, .align_items)}),
    rt("self", &.{s1(.align_items, .align_self)}),
    rt("justify-self", &.{s1(.align_items, .justify_self)}),
    rt("justify-items", &.{s1(.align_items, .justify_items)}),
    rt("overflow", &.{s1(.overflow, .overflow)}),
    rt("overflow-x", &.{s1(.overflow, .overflow_x)}),
    rt("overflow-y", &.{s1(.overflow, .overflow_y)}),
    rt("border", &.{ s1(.color, .border_color), op(.border_style, .border_style, .none, .none, false), op(.line_width, .border_width, .border_width, .none, false) }),
    rt("border-t", &.{ s1(.color, .border_top_color), op(.line_width, .border_width, .border_top_width, .none, false) }),
    rt("border-r", &.{ s1(.color, .border_right_color), op(.line_width, .border_width, .border_right_width, .none, false) }),
    rt("border-b", &.{ s1(.color, .border_bottom_color), op(.line_width, .border_width, .border_bottom_width, .none, false) }),
    rt("border-l", &.{ s1(.color, .border_left_color), op(.line_width, .border_width, .border_left_width, .none, false) }),
    rt("border-x", &.{ s2(.color, .border_left_color, .border_right_color), op(.line_width, .border_width, .border_left_width, .border_right_width, false) }),
    rt("border-y", &.{ s2(.color, .border_top_color, .border_bottom_color), op(.line_width, .border_width, .border_top_width, .border_bottom_width, false) }),
    rt("outline", &.{ s1(.color, .outline_color), s1(.border_style, .outline_style), s1(.line_width, .outline_width) }),
    rt("outline-offset", &.{s1(.line_width, .outline_offset)}),
    rt("shadow", &.{ s1(.var_color, .tw_shadow_color), op(.shadow, .shadow_arb, .box_shadow, .none, false) }),
    rt("grow|flex-grow", &.{s1(.number, .flex_grow)}),
    rt("shrink|flex-shrink", &.{s1(.number, .flex_shrink)}),
    rt("basis|flex-basis", &.{s1(.basis, .flex_basis)}),
    rt("aspect", &.{s1(.aspect, .aspect_ratio)}),
    rt("text", &.{ op(.font_size, .font_size, .none, .none, false), s1(.color, .color), s1(.text_align, .text_align), s1(.text_wrap, .text_wrap) }),
    rt("decoration", &.{ s1(.color, .text_decoration_color), s1(.thickness, .text_decoration_thickness) }),
    rt("leading", &.{s1(.line_height, .line_height)}),
    rt("tracking", &.{n1(.tracking, .letter_spacing)}),
    rt("opacity", &.{s1(.pct, .opacity)}),
    rt("animate", &.{s1(.animation, .animation)}),
    rt("line-clamp", &.{s1(.line_clamp, .line_clamp)}),
    rt("whitespace", &.{s1(.white_space, .white_space)}),
    rt("wrap", &.{s1(.overflow_wrap, .overflow_wrap)}),
    rt("flex", &.{s1(.flex, .flex)}),
    rt("origin", &.{s1(.position, .transform_origin)}),
    rt("translate", &.{op(.length, .axes, .tw_translate_x, .tw_translate_y, true)}),
    rt("translate-x", &.{op(.length, .axes, .tw_translate_x, .none, true)}),
    rt("translate-y", &.{op(.length, .axes, .tw_translate_y, .none, true)}),
    rt("rotate", &.{n1(.angle, .rotate)}),
    rt("scale", &.{op(.pct, .axes, .tw_scale_x, .tw_scale_y, true)}),
    rt("scale-x", &.{op(.pct, .axes, .tw_scale_x, .none, true)}),
    rt("scale-y", &.{op(.pct, .axes, .tw_scale_y, .none, true)}),
    rt("m", &.{n1(.length, .margin)}),
    rt("mx", &.{n1(.length, .margin_inline)}),
    rt("my", &.{n2(.length, .margin_top, .margin_bottom)}),
    rt("mt", &.{n1(.length, .margin_top)}),
    rt("mr", &.{n1(.length, .margin_right)}),
    rt("mb", &.{n1(.length, .margin_bottom)}),
    rt("ml", &.{n1(.length, .margin_left)}),
    rt("ms", &.{n1(.length, .margin_inline_start)}),
    rt("me", &.{n1(.length, .margin_inline_end)}),
    rt("p", &.{s1(.length, .padding)}),
    rt("px", &.{s1(.length, .padding_inline)}),
    rt("py", &.{s2(.length, .padding_top, .padding_bottom)}),
    rt("pt", &.{s1(.length, .padding_top)}),
    rt("pr", &.{s1(.length, .padding_right)}),
    rt("pb", &.{s1(.length, .padding_bottom)}),
    rt("pl", &.{s1(.length, .padding_left)}),
    rt("ps", &.{s1(.length, .padding_inline_start)}),
    rt("pe", &.{s1(.length, .padding_inline_end)}),
    rt("inset", &.{n1(.length, .inset)}),
    rt("inset-x", &.{n1(.length, .inset_inline)}),
    rt("inset-y", &.{n2(.length, .top, .bottom)}),
    rt("top", &.{n1(.length, .top)}),
    rt("right", &.{n1(.length, .right)}),
    rt("bottom", &.{n1(.length, .bottom)}),
    rt("left", &.{n1(.length, .left)}),
    rt("rounded", &.{s1(.radius, .border_radius)}),
    rt("rounded-t", &.{s2(.radius, .border_top_left_radius, .border_top_right_radius)}),
    rt("rounded-r", &.{s2(.radius, .border_top_right_radius, .border_bottom_right_radius)}),
    rt("rounded-b", &.{s2(.radius, .border_bottom_right_radius, .border_bottom_left_radius)}),
    rt("rounded-l", &.{s2(.radius, .border_top_left_radius, .border_bottom_left_radius)}),
    rt("rounded-tl", &.{s1(.radius, .border_top_left_radius)}),
    rt("rounded-tr", &.{s1(.radius, .border_top_right_radius)}),
    rt("rounded-br", &.{s1(.radius, .border_bottom_right_radius)}),
    rt("rounded-bl", &.{s1(.radius, .border_bottom_left_radius)}),
    rt("grid-cols", &.{s1(.grid_template, .grid_template_columns)}),
    rt("grid-rows", &.{s1(.grid_template, .grid_template_rows)}),
    rt("auto-cols", &.{s1(.grid_track, .grid_auto_columns)}),
    rt("auto-rows", &.{s1(.grid_track, .grid_auto_rows)}),
    rt("col", &.{s1(.grid_line, .grid_column)}),
    rt("row", &.{s1(.grid_line, .grid_row)}),
    rt("col-span", &.{s1(.span, .grid_column)}),
    rt("row-span", &.{s1(.span, .grid_row)}),
    rt("col-start", &.{n1(.grid_placement, .grid_column_start)}),
    rt("col-end", &.{n1(.grid_placement, .grid_column_end)}),
    rt("row-start", &.{n1(.grid_placement, .grid_row_start)}),
    rt("row-end", &.{n1(.grid_placement, .grid_row_end)}),
    rt("blur", &.{flt(.blur, .tw_blur, false)}),
    rt("brightness", &.{flt(.pct, .tw_brightness, false)}),
    rt("contrast", &.{flt(.pct, .tw_contrast, false)}),
    rt("grayscale", &.{flt(.pct, .tw_grayscale, false)}),
    rt("hue-rotate", &.{flt(.angle, .tw_hue_rotate, true)}),
    rt("invert", &.{flt(.pct, .tw_invert, false)}),
    rt("saturate", &.{flt(.pct, .tw_saturate, false)}),
    rt("sepia", &.{flt(.pct, .tw_sepia, false)}),
    rt("filter", &.{s1(.filters, .filter)}),
    rt("backdrop-blur", &.{flt(.blur, .tw_backdrop_blur, false)}),
    rt("backdrop-brightness", &.{flt(.pct, .tw_backdrop_brightness, false)}),
    rt("backdrop-contrast", &.{flt(.pct, .tw_backdrop_contrast, false)}),
    rt("backdrop-grayscale", &.{flt(.pct, .tw_backdrop_grayscale, false)}),
    rt("backdrop-hue-rotate", &.{flt(.angle, .tw_backdrop_hue_rotate, true)}),
    rt("backdrop-invert", &.{flt(.pct, .tw_backdrop_invert, false)}),
    rt("backdrop-opacity", &.{flt(.pct, .tw_backdrop_opacity, false)}),
    rt("backdrop-saturate", &.{flt(.pct, .tw_backdrop_saturate, false)}),
    rt("backdrop-sepia", &.{flt(.pct, .tw_backdrop_sepia, false)}),
    rt("backdrop-filter", &.{s1(.filters, .backdrop_filter)}),
    rt("drop-shadow", &.{flt(.drop_shadow, .tw_drop_shadow, false)}),
    rt("text-shadow", &.{ s1(.var_color, .tw_text_shadow_color), op(.shadow, .shadow_arb, .text_shadow, .none, false) }),
    rt("mix-blend", &.{s1(.blend, .mix_blend_mode)}),
    rt("bg-blend", &.{s1(.blend, .background_blend_mode)}),
    rt("align", &.{s1(.valign, .vertical_align)}),
});

// ------------------------------------------------------------------------------------------------
// Value forms. Each returns the CSS value text, or null when the suffix is not this form's.

/// Keyword tables: `|`-separated entries, `key` or `key=css`. Matching ignores ASCII case.
noinline fn kw(table: []const u8, s: []const u8) ?[]const u8 {
    return (lookup(table, s, true) orelse return null).val;
}

const Hit = struct { idx: usize, val: []const u8 };

/// Finds `s` among the `|`-separated `key[=value]` entries of `table` (ASCII case-insensitive when `ci`).
noinline fn lookup(table: []const u8, s: []const u8, ci: bool) ?Hit {
    var i: usize = 0;
    var idx: usize = 0;
    while (i <= table.len) : (idx += 1) {
        const end = std.mem.indexOfScalarPos(u8, table, i, '|') orelse table.len;
        const ent = table[i..end];
        const eq = std.mem.indexOfScalar(u8, ent, '=');
        const key = ent[0 .. eq orelse ent.len];
        if (if (ci) std.ascii.eqlIgnoreCase(key, s) else eql(key, s)) return .{ .idx = idx, .val = if (eq) |q| ent[q + 1 ..] else key };
        i = end + 1;
    }
    return null;
}

const kw_length = "auto|dvw=100vw|svw=100vw|lvw=100vw|cqw=100cqw|cqi=100cqw|vi=100vw|dvh=100vh|svh=100vh|lvh=100vh|" ++
    "cqh=100cqh|cqb=100cqh|vb=100vh|vmin=100vmin|cqmin=100cqmin|vmax=100vmax|cqmax=100cqmax|px=1px|full=100%|" ++
    "3xs=16rem|2xs=18rem|xs=20rem|sm=24rem|md=28rem|lg=32rem|xl=36rem|2xl=42rem|3xl=48rem|4xl=56rem|5xl=64rem|6xl=72rem|7xl=80rem";
const kw_size = "min=min-content|max=max-content|fit=fit-content";
const kw_radius = "full=9999px|none=0px|xs=0.125rem|sm=0.25rem|md=0.375rem|lg=0.5rem|xl=0.75rem|2xl=1rem|3xl=1.5rem|4xl=2rem";
const kw_leading = "none=1|tight=1.25|snug=1.375|normal=1.5|relaxed=1.625|loose=2";
const kw_tracking = "tighter=-0.05em|tight=-0.025em|normal=0em|wide=0.025em|wider=0.05em|widest=0.1em";
const kw_weight = "thin=100|extralight=200|light=300|normal=400|medium=500|semibold=600|bold=700|extrabold=800|black=900";
const kw_family = "sans=sans-serif|serif|mono=monospace";
const kw_border_style = "none|hidden|dotted|dashed|solid|double|groove|ridge|inset|outset";
const kw_stretch = "normal|ultra-condensed|extra-condensed|condensed|semi-condensed|semi-expanded|expanded|extra-expanded|ultra-expanded";
const kw_angle = "none=0deg|to-t=0deg|to-tr=45deg|to-r=90deg|to-br=135deg|to-b=180deg|to-bl=225deg|to-l=270deg|to-tl=315deg";
const kw_blur = "none=0px|xs=4px|sm=8px|md=12px|lg=16px|xl=24px|2xl=40px|3xl=64px";
const kw_position = "top-left=left top|top=center top|top-right=right top|left=left center|center=center center|" ++
    "right=right center|bottom-left=left bottom|bottom=center bottom|bottom-right=right bottom";
const kw_bg_size = "auto|cover|contain";
const kw_bg_clip = "border=border-box|padding=padding-box|content=content-box|text";
const kw_white_space = "normal|nowrap|pre|pre-wrap|pre-line";
const kw_text_wrap = "wrap|nowrap|balance|pretty";
const kw_text_align = "left|right|center|justify|start|end";
const kw_overflow = "visible|clip|hidden";
const kw_valign = "baseline|top|middle|bottom|text-top|text-bottom|sub|super";
const kw_object_fit = "fill|contain|cover|scale-down|none";
const kw_list_type = "none|disc|circle|square|decimal|decimal-leading-zero|lower-roman|upper-roman|lower-alpha|upper-alpha|" ++
    "lower-latin|upper-latin|lower-greek|disclosure-open|disclosure-closed";
const kw_list_pos = "inside|outside";
const kw_blend = "normal|multiply|screen|overlay|darken|lighten|color-dodge|color-burn|hard-light|soft-light|difference|" ++
    "exclusion|hue|saturation|color|luminosity|plus-lighter|plus-darker";
const kw_overflow_wrap = "normal|anywhere|break-word";
const kw_align_items = "normal|start|end|flex-start|flex-end|self-start|self-end|center|baseline|stretch";
const kw_justify = "between=space-between|around=space-around|evenly=space-evenly|normal|start|end|flex-start|flex-end|" ++
    "center|stretch|space-between|space-around|space-evenly";
const kw_font_size_css = "xx-small|x-small|small|medium|large|x-large|xx-large|xxx-large|smaller|larger";

const FontSizeEnt = struct { n: []const u8, size: f32, lh: f32 };
const font_sizes = [_]FontSizeEnt{
    .{ .n = "xs", .size = 0.75, .lh = 1 },      .{ .n = "sm", .size = 0.875, .lh = 1.25 },
    .{ .n = "base", .size = 1, .lh = 1.5 },     .{ .n = "lg", .size = 1.125, .lh = 1.75 },
    .{ .n = "xl", .size = 1.25, .lh = 1.75 },   .{ .n = "2xl", .size = 1.5, .lh = 2 },
    .{ .n = "3xl", .size = 1.875, .lh = 2.25 }, .{ .n = "4xl", .size = 2.25, .lh = 2.5 },
    .{ .n = "5xl", .size = 3, .lh = 0 },        .{ .n = "6xl", .size = 3.75, .lh = 0 },
    .{ .n = "7xl", .size = 4.5, .lh = 0 },      .{ .n = "8xl", .size = 6, .lh = 0 },
    .{ .n = "9xl", .size = 8, .lh = 0 },
};

/// Per value form: a keyword table tried first, then (when `unit` is set) a plain number + unit.
/// Forms with neither are handled in `parseForm`'s switch.
const form_count = @typeInfo(Form).@"enum".field_names.len;
/// takumi `Animations::parse_tw` presets (Tailwind's `--animate-*` defaults; the keyframes are built in).
const kw_animate = "spin=1s linear infinite spin|ping=1s cubic-bezier(0, 0, 0.2, 1) infinite ping|pulse=2s cubic-bezier(0.4, 0, 0.6, 1) infinite pulse|bounce=1s infinite bounce|none";
const kw_tables = [_][]const u8{ kw_tracking, kw_radius, kw_border_style, kw_family, kw_blur, kw_position, kw_bg_size, kw_bg_clip, kw_white_space, kw_text_wrap, kw_text_align, kw_overflow, kw_valign, kw_object_fit, kw_list_type, kw_list_pos, kw_blend, kw_overflow_wrap, kw_align_items, kw_justify, "auto|fr=1fr", "none", kw_angle, "auto|from-font", kw_weight, kw_animate };
const unit_names = [_][]const u8{ "deg", "%", "px", "" };
/// Per form: bits 0-4 = 1 + index in `kw_tables` (0: none), bits 5-7 = 1 + index in `unit_names`.
const form_desc: [form_count]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var d: [form_count]u8 = @splat(0);
    for ([_]struct { Form, ?[]const u8, ?[]const u8 }{
        .{ .tracking, kw_tracking, null },
        .{ .radius, kw_radius, null },
        .{ .border_style, kw_border_style, null },
        .{ .font_family, kw_family, null },
        .{ .blur, kw_blur, null },
        .{ .position, kw_position, null },
        .{ .bg_size, kw_bg_size, null },
        .{ .bg_clip, kw_bg_clip, null },
        .{ .white_space, kw_white_space, null },
        .{ .text_wrap, kw_text_wrap, null },
        .{ .text_align, kw_text_align, null },
        .{ .overflow, kw_overflow, null },
        .{ .valign, kw_valign, null },
        .{ .object_fit, kw_object_fit, null },
        .{ .list_type, kw_list_type, null },
        .{ .list_pos, kw_list_pos, null },
        .{ .blend, kw_blend, null },
        .{ .overflow_wrap, kw_overflow_wrap, null },
        .{ .align_items, kw_align_items, null },
        .{ .justify, kw_justify, null },
        .{ .animation, kw_animate, null },
        .{ .grid_track, "auto|fr=1fr", null },
        .{ .bg_image, "none", null },
        .{ .content, "none", null },
        .{ .filters, "none", null },
        .{ .list_image, "none", null },
        .{ .angle, kw_angle, "deg" },
        .{ .pct, null, "%" },
        .{ .line_width, null, "px" },
        .{ .thickness, "auto|from-font", "px" },
        .{ .font_weight, kw_weight, "" },
        .{ .number, null, "" },
    }) |e| {
        var v: u8 = 0;
        if (e[1]) |t| v = for (kw_tables, 1..) |x, i| {
            if (std.mem.eql(u8, x, t)) break i;
        } else @compileError("kw table");
        if (e[2]) |u| v |= (for (unit_names, 1..) |x, i| {
            if (std.mem.eql(u8, x, u)) break i;
        } else @compileError("unit")) << 5;
        d[@backingInt(e[0])] = v;
    }
    break :blk d;
};

fn parseForm(a: Allocator, f: Form, s: []const u8) !?[]const u8 {
    if (s.len == 0) return null;
    if (s[0] == '[') {
        if (s.len < 3 or s[s.len - 1] != ']') return null;
        const v = try decodeArbitrary(a, s[1 .. s.len - 1]);
        if (v.len == 0) return null;
        return arbitrary(f, v);
    }
    const d = form_desc[@backingInt(f)];
    if (d & 31 != 0) if (kw(kw_tables[(d & 31) - 1], s)) |v| return v;
    if (d >> 5 != 0) return if (parseNum(s)) |n| try numUnit(a, n, unit_names[(d >> 5) - 1]) else null;
    if (d != 0) return null;
    const pct_ok = s[s.len - 1] == '%' and parseNum(s[0 .. s.len - 1]) != null;
    return switch (f) {
        .length => try length(a, s),
        .size, .basis => if (f == .basis and std.ascii.eqlIgnoreCase(s, "content")) "content" else (kw(kw_size, s) orelse try length(a, s)),
        .color => try colorInput(a, s),
        .var_color => try varColor(a, s),
        .font_size => try fontSize(a, s),
        .line_height => try lineHeight(a, s),
        .font_stretch => kw(kw_stretch, s) orelse (if (pct_ok) s else null),
        .grad_pos => if (pct_ok) s else null,
        .flex => kw("auto=1 1 auto|none=0 0 auto|initial=0 1 auto", s) orelse
            (if (ratio(s)) |r| try cat(a, &.{ try numUnit(a, r, ""), " 1 0%" }) else null),
        .aspect => kw("square=1|video=16 / 9|auto", s) orelse (if (ratio(s) != null) s else null),
        .grid_template, .line_clamp => if (std.ascii.eqlIgnoreCase(s, "none")) "none" else if (parseUint(s, u32)) |n|
            (if (n == 0) null else if (f == .line_clamp) s else try cat(a, &.{ "repeat(", s, ", minmax(0px, 1fr))" }))
        else
            null,
        .grid_line, .grid_placement => if (f == .grid_line and std.ascii.eqlIgnoreCase(s, "auto")) "auto" else if (parseInt16(s) != null) s else null,
        .span => if (parseUint(s, u16) != null) try cat(a, &.{ "span ", s, " / span ", s }) else null,
        else => null,
    };
}

/// An arbitrary `[...]` value for form `f`: a light shape check (so multi-form roots pick the right
/// form and obviously invalid values are dropped, as takumi's typed parsers would), then the text.
fn arbitrary(f: Form, v: []const u8) ?[]const u8 {
    if (has(v, "var(") or !mathOk(v)) return null; // never resolvable / invalid
    const ok = switch (f) {
        .color, .var_color => isColorLike(v),
        .bg_image, .list_image => isImageLike(v),
        .position => isListOf(v, "left|right|top|bottom|center", 4),
        .bg_size => isListOf(v, kw_bg_size, 2),
        .grad_pos => isLengthLike(v),
        .length, .size, .basis => isLengthLike(v) or fnName(v, "fit-content") or kw("auto|min-content|max-content|fit-content|none|content", v) != null,
        .line_width => isLengthLike(v) or kw("thin|medium|thick", v) != null,
        .font_size => isLengthLike(v) or kw(kw_font_size_css, v) != null,
        .font_weight => isLengthLike(v) or kw("normal|bold|bolder|lighter", v) != null,
        .border_style, .text_align, .text_wrap, .justify, .object_fit => kw(kw_tables[(form_desc[@backingInt(f)] & 31) - 1], v) != null,
        .content => v[0] == '"' or v[0] == '\'' or kw("none|normal", v) != null,
        .list_type => isIdent(v) or v[0] == '"' or v[0] == '\'',
        else => true,
    };
    return if (ok) v else null;
}

/// Inside `calc()`-like math, `+` / `-` need whitespace before them (`calc(100%-2px)` is invalid CSS,
/// which takumi drops; upstream Tailwind would insert the spaces, takumi does not).
fn mathOk(v: []const u8) bool {
    if (std.mem.indexOfScalar(u8, v, '(') == null) return true;
    if (!(has(v, "calc(") or has(v, "min(") or
        has(v, "max(") or has(v, "clamp("))) return true;
    for (v, 0..) |ch, i| {
        if (i == 0 or (ch != '+' and ch != '-')) continue;
        const prev = v[i - 1];
        if (ch == '+' and !(prev == ' ' or prev == '(' or prev == ',' or prev == 'e' or prev == 'E')) return false;
        if (ch == '-' and (isDigit(prev) or prev == '%' or prev == ')' or prev == '.')) return false;
    }
    return true;
}

fn length(a: Allocator, s: []const u8) !?[]const u8 {
    if (parseNum(s)) |n| return try numUnit(a, n * 0.25, "rem");
    if (ratio(s)) |r| return try numUnit(a, r * 100, "%");
    return kw(kw_length, s);
}

/// `AspectRatio::from_css` for a suffix: `a/b` (b > 0) or a number; returns the ratio.
noinline fn ratio(s: []const u8) ?f32 {
    if (parseNum(s)) |n| return n;
    const slash = std.mem.indexOfScalar(u8, s, '/') orelse return null;
    const x = parseNum(s[0..slash]) orelse return null;
    const y = parseNum(s[slash + 1 ..]) orelse return null;
    if (!(y > 0) or x < 0) return null;
    return x / y;
}

fn fontSize(a: Allocator, s: []const u8) !?[]const u8 {
    const slash = std.mem.indexOfScalar(u8, s, '/');
    const base = s[0 .. slash orelse s.len];
    const fs = for (font_sizes) |x| {
        if (std.ascii.eqlIgnoreCase(x.n, base)) break x;
    } else return null;
    var lh: []const u8 = undefined;
    if (slash) |i| {
        const t = s[i + 1 ..];
        if (t.len >= 3 and t[0] == '[' and t[t.len - 1] == ']') {
            lh = try decodeArbitrary(a, t[1 .. t.len - 1]);
            if (lh.len == 0 or has(lh, "var(")) return null;
        } else lh = (try lineHeight(a, t)) orelse return null;
    } else lh = if (fs.lh == 0) "1" else try numUnit(a, fs.lh / fs.size, "em");
    return try cat(a, &.{ try numUnit(a, fs.size, "rem"), "\x00", lh });
}

fn lineHeight(a: Allocator, s: []const u8) !?[]const u8 {
    if (kw(kw_leading, s)) |v| return v;
    if (parseNum(s)) |n| return try numUnit(a, n * 0.25, "rem");
    return null;
}

/// takumi `ColorInput::parse_tw_with_arbitrary` (non-arbitrary part).
fn colorInput(a: Allocator, s: []const u8) !?[]const u8 {
    const base = s[0 .. std.mem.indexOfScalar(u8, s, '/') orelse s.len];
    if (std.ascii.eqlIgnoreCase(base, "current")) return "currentcolor";
    const c = paletteColor(s) orelse return null;
    return try hexColor(a, c);
}

/// takumi `Color::parse_tw`: RGBA or null.
fn paletteColor(s: []const u8) ?u32 {
    const slash = std.mem.indexOfScalar(u8, s, '/');
    const base = s[0 .. slash orelse s.len];
    var c: u32 = if (kw("transparent=\x00|black=\x01|white=\x02", base)) |k|
        @as(u32, if (k[0] == 0) 0 else if (k[0] == 1) 0xff else 0xffffffff)
    else blk: {
        const dash = std.mem.lastIndexOfScalar(u8, base, '-') orelse return null;
        const shade = parseUint(base[dash + 1 ..], u16) orelse return null;
        break :blk ((palette.lookup(base[0..dash], shade) orelse return null) << 8) | 0xff;
    };
    if (slash) |i| {
        const o = parseNum(s[i + 1 ..]) orelse return null;
        const x = @floor(o * 2.55 + 0.5);
        const op_: u32 = if (!(x > 0)) 0 else if (x >= 255) 255 else @intFromFloat(x);
        c = (c & 0xffffff00) | mulDiv255(c & 0xff, op_);
    }
    return c;
}

fn mulDiv255(x: u32, y: u32) u32 {
    const t = x * y + 128;
    return (t + (t >> 8)) >> 8;
}

noinline fn hexColor(a: Allocator, c: u32) ![]const u8 {
    const digits = "0123456789abcdef";
    const opaque_ = (c & 0xff) == 0xff;
    const n: usize = if (opaque_) 7 else 9;
    const out = try a.alloc(u8, n);
    out[0] = '#';
    var i: usize = 1;
    var shift: u5 = 28;
    while (i < n) : (i += 1) {
        out[i] = digits[(c >> shift) & 0xf];
        if (shift >= 4) shift -= 4;
    }
    return out;
}

const poison = "\x00";

/// takumi `TwVarColor` (gradient stops, shadow colours): resolved for an element with no theme variables.
fn varColor(a: Allocator, s: []const u8) !?[]const u8 {
    const slash = std.mem.indexOfScalar(u8, s, '/');
    const base = s[0 .. slash orelse s.len];
    var pct: ?f32 = null;
    if (slash) |i| {
        const p = parseNum(s[i + 1 ..]) orelse return null;
        if (!(p >= 0 and p <= 100)) return null;
        pct = p;
    }
    if (std.ascii.eqlIgnoreCase(base, "current")) {
        const p = pct orelse return "currentcolor";
        return try cat(a, &.{ "color-mix(in oklab, currentcolor ", try numUnit(a, p, "%"), ", transparent)" });
    }
    if (std.ascii.eqlIgnoreCase(base, "transparent")) return "transparent";
    if (base.len == 0) return null;
    for (base) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '-')) return null;
    var c = paletteColor(base) orelse return poison; // `var(--color-<base>)`, undefined
    if (pct) |p| {
        // color-mix(in oklab, c p%, transparent): the colour with its alpha scaled by p.
        const x = @floor(@as(f32, @floatFromInt(c & 0xff)) * p / 100 + 0.5);
        c = (c & 0xffffff00) | @as(u32, @intFromFloat(@min(@max(x, 0), 255)));
    }
    return try hexColor(a, c);
}

/// `-` prefix of a negatable value (`Length::negative`, angles, percentages).
noinline fn negate(a: Allocator, v: []const u8) !?[]const u8 {
    if (v.len == 0 or std.ascii.eqlIgnoreCase(v, "auto")) return null;
    if (v[0] == '-') return v[1..];
    if (isDigit(v[0]) or v[0] == '.') return try cat(a, &.{ "-", v });
    if (v[0] == '+') return try cat(a, &.{ "-", v[1..] });
    return try cat(a, &.{ "calc(", v, " * -1)" });
}

// ---- arbitrary values -------------------------------------------------------------------------

/// Tailwind `decodeArbitraryValue` as takumi ports it: `_` -> space except inside `url(...)` and in
/// the first argument of `var()` / `theme()`; `\_` -> `_`.
noinline fn decodeArbitrary(a: Allocator, v: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, v, '_') == null) return v;
    const out = try a.alloc(u8, v.len);
    var n: usize = 0;
    var depth: usize = 0;
    var url_depth: usize = 0; // paren depth of the open `url(` (0: none)
    var i: usize = 0;
    while (i < v.len) : (i += 1) {
        var ch = v[i];
        if (ch == '\\' and i + 1 < v.len and v[i + 1] == '_') {
            ch = '_';
            i += 1;
        } else if (ch == '(') {
            depth += 1;
            if (url_depth == 0 and i >= 3 and std.ascii.eqlIgnoreCase(v[i - 3 .. i], "url")) url_depth = depth;
        } else if (ch == ')') {
            if (depth == url_depth) url_depth = 0;
            depth -|= 1;
        } else if (ch == '_' and url_depth == 0) ch = ' ';
        out[n] = ch;
        n += 1;
    }
    return out[0..n];
}

/// `v` starts with a function call whose name is in the `|` list.
noinline fn fnName(v: []const u8, names: []const u8) bool {
    const open = std.mem.indexOfScalar(u8, v, '(') orelse return false;
    return kw(names, v[0..open]) != null;
}

noinline fn isColorLike(v: []const u8) bool {
    if (v[0] == '#') return true;
    if (fnName(v, "rgb|rgba|hsl|hsla|hwb|lab|lch|oklab|oklch|color|color-mix|light-dark")) return true;
    for (v) |ch| if (!(std.ascii.isAlphabetic(ch) or ch == '-')) return false;
    for ([_][]const u8{ kw_border_style, kw_text_align, kw_text_wrap, kw_bg_size, kw_font_size_css, "left|right|top|bottom|center|auto|thin|thick|from-font|normal" }) |t| {
        if (kw(t, v) != null) return false;
    }
    return true;
}

fn isImageLike(v: []const u8) bool {
    return fnName(v, "url|image|image-set|cross-fade|element") or has(v, "gradient(");
}

noinline fn isLengthLike(v: []const u8) bool {
    return isDigit(v[0]) or v[0] == '.' or v[0] == '-' or v[0] == '+' or fnName(v, "calc|min|max|clamp");
}

/// 1..max space-separated tokens, each length-like or one of `kws`.
noinline fn isListOf(v: []const u8, kws: []const u8, max: usize) bool {
    var it = std.mem.tokenizeScalar(u8, v, ' ');
    var n: usize = 0;
    while (it.next()) |t| : (n += 1) {
        if (!(isLengthLike(t) or kw(kws, t) != null)) return false;
    }
    return n >= 1 and n <= max;
}

fn isIdent(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_')) return false;
    return true;
}

/// A variable's value; an undefined theme colour (`poison`) is invalid at computed-value time, so the
/// variable falls back to its guaranteed-invalid initial value, i.e. reads as unset.
fn slotVal(slots: *const [p_count]?[]const u8, p: P) ?[]const u8 {
    const s = slots[@backingInt(p)] orelse return null;
    return if (eql(s, poison)) null else s;
}

fn eql(x: []const u8, y: []const u8) bool {
    if (x.len != y.len) return false;
    for (x, y) |c, d| if (c != d) return false;
    return true;
}

noinline fn starts(x: []const u8, prefix: []const u8) bool {
    return x.len >= prefix.len and eql(x[0..prefix.len], prefix);
}

noinline fn ends(x: []const u8, suffix: []const u8) bool {
    return x.len >= suffix.len and eql(x[x.len - suffix.len ..], suffix);
}

/// Substring test (short haystacks).
noinline fn has(x: []const u8, needle: []const u8) bool {
    var i: usize = 0;
    while (i + needle.len <= x.len) : (i += 1) if (eql(x[i..][0..needle.len], needle)) return true;
    return false;
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

// ---- numbers -----------------------------------------------------------------------------------

/// A plain decimal (`4`, `0.5`, `.5`, `-3`, `+2`); no exponent, no inf/nan.
noinline fn parseNum(s: []const u8) ?f32 {
    var i: usize = 0;
    var neg = false;
    if (i < s.len and (s[i] == '-' or s[i] == '+')) {
        neg = s[i] == '-';
        i += 1;
    }
    var mant: u64 = 0;
    var scale: i32 = 0;
    var digits: usize = 0;
    var dot = false;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (ch == '.' and !dot) {
            dot = true;
            continue;
        }
        if (!isDigit(ch)) return null;
        digits += 1;
        if (mant < 100_000_000_000_000_000) {
            mant = mant * 10 + (ch - '0');
            if (dot) scale -= 1;
        } else if (!dot) scale += 1;
    }
    if (digits == 0) return null;
    var x: f64 = @floatFromInt(mant);
    while (scale < 0) : (scale += 1) x /= 10;
    while (scale > 0) : (scale -= 1) x *= 10;
    if (x > 1e30) return null;
    const r: f32 = @floatCast(x);
    return if (neg) -r else r;
}

fn parseUint(s: []const u8, comptime T: type) ?T {
    var t = s;
    if (t.len > 0 and t[0] == '+') t = t[1..];
    if (t.len == 0) return null;
    var v: u64 = 0;
    for (t) |ch| {
        if (!isDigit(ch)) return null;
        v = v * 10 + (ch - '0');
        if (v > std.math.maxInt(T)) return null;
    }
    return @intCast(v);
}

fn parseInt16(s: []const u8) ?i16 {
    if (s.len > 0 and s[0] == '-') {
        const v = parseUint(s[1..], u16) orelse return null;
        if (s.len > 1 and s[1] == '+') return null;
        if (v > 32768) return null;
        return @intCast(-@as(i32, v));
    }
    const v = parseUint(s, u16) orelse return null;
    if (v > 32767) return null;
    return @intCast(v);
}

/// `x` formatted with up to 8 decimals (enough to round-trip the f32 values used here) + `unit`.
noinline fn numUnit(a: Allocator, x: f32, unit: []const u8) ![]const u8 {
    var buf: [48]u8 = undefined;
    var n: usize = 0;
    var v: f64 = x;
    if (!(v == v) or @abs(v) > 1e10) v = 0;
    const neg = v < 0;
    if (neg) v = -v;
    const scaled: u64 = @intFromFloat(@floor(v * 1e8 + 0.5));
    if (neg and scaled != 0) {
        buf[n] = '-';
        n += 1;
    }
    var ip = scaled / 100_000_000;
    var frac = scaled % 100_000_000;
    var tmp: [20]u8 = undefined;
    var t: usize = 0;
    while (true) {
        tmp[t] = @intCast('0' + ip % 10);
        t += 1;
        ip /= 10;
        if (ip == 0) break;
    }
    while (t > 0) {
        t -= 1;
        buf[n] = tmp[t];
        n += 1;
    }
    if (frac != 0) {
        buf[n] = '.';
        n += 1;
        var d: u64 = 10_000_000;
        while (frac != 0) {
            buf[n] = @intCast('0' + frac / d);
            n += 1;
            frac %= d;
            d /= 10;
        }
    }
    return cat(a, &.{ buf[0..n], unit });
}

// ------------------------------------------------------------------------------------------------
// Variable resolution

fn slotOf(code: u8) ?P {
    return switch (code) {
        'x' => .tw_translate_x,
        'y' => .tw_translate_y,
        'X' => .tw_scale_x,
        'Y' => .tw_scale_y,
        'S' => .tw_border_style,
        's' => .tw_shadow_color,
        't' => .tw_text_shadow_color,
        else => null,
    };
}

fn slotDefault(code: u8) []const u8 {
    return switch (code) {
        'x', 'y' => "0px",
        'X', 'Y' => "100%",
        else => "solid",
    };
}

const filter_chain = [_]P{ .tw_blur, .tw_brightness, .tw_contrast, .tw_grayscale, .tw_hue_rotate, .tw_invert, .tw_saturate, .tw_sepia, .tw_drop_shadow };
const backdrop_chain = [_]P{ .tw_backdrop_blur, .tw_backdrop_brightness, .tw_backdrop_contrast, .tw_backdrop_grayscale, .tw_backdrop_hue_rotate, .tw_backdrop_invert, .tw_backdrop_opacity, .tw_backdrop_saturate, .tw_backdrop_sepia };

/// Substitutes placeholders; null = the declaration is invalid at computed-value time (takumi skips it).
fn resolve(a: Allocator, v: []const u8, slots: *const [p_count]?[]const u8) !?[]const u8 {
    if (v.len > 0 and (v[0] == 4 or v[0] == 5)) {
        const col = slotVal(slots, if (v[0] == 4) .tw_shadow_color else .tw_text_shadow_color) orelse return v[1..];
        return try recolorShadow(a, v[1..], col);
    }
    var marked = false;
    for (v) |ch| {
        if (ch < 4) marked = true;
    }
    if (!marked) return v;
    var out = Buf{ .a = a };
    var i: usize = 0;
    while (i < v.len) {
        const ch = v[i];
        if (ch == 1 and i + 1 < v.len) {
            const code = v[i + 1];
            i += 2;
            switch (code) {
                'F', 'B' => {
                    var first = true;
                    for (if (code == 'F') &filter_chain else &backdrop_chain) |p| {
                        const s = slots[@backingInt(p)] orelse continue;
                        if (!first) try out.put(" ");
                        first = false;
                        try out.put(s);
                    }
                    if (first) return null;
                },
                'G' => {
                    const stops = slots[@backingInt(P.tw_gradient_stops)] orelse return null;
                    // An undefined via colour makes `--tw-gradient-via-stops` invalid: the from/to fallback
                    // applies, unless the stops were last set by a `via` utility (no fallback).
                    const via = slots[@backingInt(P.tw_gradient_via_stops)] != null and slotVal(slots, .tw_gradient_via) != null;
                    if (!via and stops[0] == 'V' and slots[@backingInt(P.tw_gradient_via_stops)] != null) return null;
                    const parts = [_]struct { P, []const u8, P, []const u8 }{
                        .{ .tw_gradient_from, "transparent", .tw_gradient_from_position, "0%" },
                        .{ .tw_gradient_via, "", .tw_gradient_via_position, "50%" },
                        .{ .tw_gradient_to, "transparent", .tw_gradient_to_position, "100%" },
                    };
                    for (parts, 0..) |pt, k| {
                        if (k == 1 and !via) continue;
                        const col = slotVal(slots, pt[0]) orelse pt[1];
                        if (col.len == 0) return null;
                        if (k > 0) try out.put(", ");
                        try out.put(col);
                        try out.put(" ");
                        try out.put(slotVal(slots, pt[2]) orelse pt[3]);
                    }
                },
                else => {
                    const p = slotOf(code) orelse return null;
                    try out.put(slotVal(slots, p) orelse slotDefault(code));
                },
            }
        } else if (ch == 2 and i + 1 < v.len) {
            const p = slotOf(v[i + 1]) orelse return null;
            const end = std.mem.indexOfScalarPos(u8, v, i + 2, 3) orelse return null;
            if (slotVal(slots, p)) |col| try out.put(col) else {
                try out.put("#000000"); // shadow presets: black with the given alpha
                try out.put(v[i + 2 .. end]);
            }
            i = end + 1;
        } else {
            try out.put(v[i..][0..1]);
            i += 1;
        }
    }
    return out.items();
}

/// Replaces (or adds) the colour of each layer of an arbitrary shadow list, as takumi's
/// `var(--tw-shadow-color, <layer colour>)` does once a shadow colour utility is set.
fn recolorShadow(a: Allocator, v: []const u8, col: []const u8) ![]const u8 {
    var out = Buf{ .a = a };
    var i: usize = 0;
    var first_layer = true;
    while (i <= v.len) {
        const end = topLevel(v, i, ',');
        if (!first_layer) try out.put(", ");
        first_layer = false;
        var j = i;
        var first_tok = true;
        var colored = false;
        while (j < end) {
            while (j < end and v[j] == ' ') j += 1;
            if (j >= end) break;
            const te = @min(topLevel(v, j, ' '), end);
            const t = v[j..te];
            const is_len = isLengthLike(t) or std.ascii.eqlIgnoreCase(t, "inset");
            if (!first_tok) try out.put(" ");
            first_tok = false;
            if (is_len) try out.put(t) else {
                try out.put(col);
                colored = true;
            }
            j = te;
        }
        if (!colored) {
            try out.put(" ");
            try out.put(col);
        }
        i = end + 1;
    }
    return out.items();
}

/// Minimal growable byte buffer in the arena (keeps the generic `ArrayList(u8)` out of the binary).
const Buf = struct {
    a: Allocator,
    b: []u8 = &.{},
    n: usize = 0,

    noinline fn put(self: *Buf, s: []const u8) !void {
        if (self.n + s.len > self.b.len) {
            const nb = try self.a.alloc(u8, (self.n + s.len) * 2 + 32);
            @memcpy(nb[0..self.n], self.b[0..self.n]);
            self.b = nb;
        }
        @memcpy(self.b[self.n..][0..s.len], s);
        self.n += s.len;
    }

    fn items(self: *const Buf) []const u8 {
        return self.b[0..self.n];
    }
};

/// Index of the next `sep` at parenthesis depth 0 from `from`, or `v.len`.
fn topLevel(v: []const u8, from: usize, sep: u8) usize {
    var depth: usize = 0;
    var i = from;
    while (i < v.len) : (i += 1) {
        switch (v[i]) {
            '(' => depth += 1,
            ')' => depth -|= 1,
            else => if (v[i] == sep and depth == 0) return i,
        }
    }
    return v.len;
}

// ------------------------------------------------------------------------------------------------
// Tests

const testing = std.testing;

const TestCtx = struct {
    arena: std.heap.ArenaAllocator,
    fn init() TestCtx {
        return .{ .arena = std.heap.ArenaAllocator.init(testing.allocator) };
    }
    fn deinit(t: *TestCtx) void {
        t.arena.deinit();
    }
    /// "name:value;name:value!" (a trailing `!` marks important)
    fn css(t: *TestCtx, classes: []const u8, env: Env) ![]const u8 {
        const a = t.arena.allocator();
        var out: std.ArrayList(Declaration) = .empty;
        try compile(a, classes, env, &out);
        var s: std.ArrayList(u8) = .empty;
        for (out.items, 0..) |d, i| {
            if (i > 0) try s.append(a, ';');
            try s.appendSlice(a, d.name);
            try s.append(a, ':');
            try s.appendSlice(a, d.value);
            if (d.important) try s.append(a, '!');
        }
        return s.items;
    }
};

const env0 = Env{ .viewport_w = 1200, .viewport_h = 630 };

fn expectCss(classes: []const u8, want: []const u8) !void {
    var t = TestCtx.init();
    defer t.deinit();
    const got = try t.css(classes, env0);
    testing.expectEqualStrings(want, got) catch |err| {
        std.debug.print("classes: {s}\n", .{classes});
        return err;
    };
}

test "basic utilities" {
    try expectCss("flex p-8 bg-blue-500", "display:flex;background-color:#2b7fff;padding:2rem");
    try expectCss("w-1/2 h-full size-4", "width:1rem;height:1rem;height:100%;width:50%");
    try expectCss("text-sm", "font-size:0.875rem;line-height:1.42857146em");
    try expectCss("text-5xl font-bold", "font-size:3rem;line-height:1;font-weight:700");
    try expectCss("text-xs/6", "font-size:0.75rem;line-height:1.5rem");
    try expectCss("text-base/[12.34]", "font-size:1rem;line-height:12.34");
    try expectCss("unknown-class foo bg-brand z-10", "");
    try expectCss("rounded", "border-radius:0.25rem");
    try expectCss("truncate", "text-overflow:ellipsis;white-space:nowrap;overflow:hidden");
}

test "break utilities (paged output)" {
    if (comptime !tw_pdf) {
        try expectCss("break-before-page break-inside-avoid break-after-avoid-page", "");
        return;
    }
    // (Tailwind's property order: ... display ... list-style, break-before, break-inside, break-after, grid ...)
    try expectCss("flex break-after-avoid-page break-inside-avoid break-before-page", "display:flex;break-before:page;break-inside:avoid;break-after:avoid-page");
    try expectCss("break-before-all break-after-column", "break-before:page;break-after:column");
    try expectCss("break-inside-avoid-column break-after-left", "break-inside:avoid-column;break-after:left");
    try expectCss("break-before-sometimes break-inside-page", "");
}

test "negatives" {
    try expectCss("-mt-4", "margin-top:-1rem");
    try expectCss("-m-[5px]", "margin:-5px");
    try expectCss("-inset-x-[calc(1px_+_2px)]", "inset-inline:calc(calc(1px + 2px) * -1)");
    try expectCss("w-[calc(100%-2px)] mt-[calc(1px+2px)] w-[banana]", "");
    try expectCss("-mt-auto -p-4 -w-4 -bg-red-500", "");
    try expectCss("-rotate-45 -tracking-wide", "rotate:-45deg;letter-spacing:-0.025em");
    try expectCss("-col-start-2", "grid-column-start:-2");
}

test "important prefix and suffix" {
    try expectCss("!mt-4", "margin-top:1rem!");
    try expectCss("mt-4!", "margin-top:1rem!");
    try expectCss("md:!mt-4 sm:mt-8 !mt-12 mt-16", "margin-top:4rem;margin-top:2rem;margin-top:3rem!;margin-top:1rem!");
}

test "opacity modifier" {
    try expectCss("bg-red-500/50", "background-color:#fb2c3680");
    try expectCss("text-black/30", "color:#0000004d");
    try expectCss("bg-white/100 bg-red-500/150", "background-color:#fb2c36;background-color:#ffffff");
    try expectCss("text-current/50", "color:currentcolor");
    try expectCss("bg-red-500/x", "");
}

test "arbitrary values" {
    try expectCss("w-[37px]", "width:37px");
    try expectCss("grid-cols-[repeat(2,minmax(0,1fr))]", "grid-template-columns:repeat(2,minmax(0,1fr))");
    try expectCss("flex-[3_1_auto]", "flex:3 1 auto");
    try expectCss("bg-[url('/a_b.png')]", "background-image:url('/a_b.png')");
    try expectCss("bg-[#ff0]", "background-color:#ff0");
    try expectCss("bg-[center_top]", "background-position:center top");
    try expectCss("bg-[length:10px]", "");
    try expectCss("text-[22px] text-[#333]", "font-size:22px;color:#333");
    try expectCss("border-[3px] border-[#f00]", "border-width:3px;border-style:solid;border-color:#f00");
    try expectCss("[mask-type:luminance]", "");
    try expectCss("font-[foo\\_bar]", "font-family:foo_bar");
}

test "variants" {
    try expectCss("md:flex", "display:flex");
    try expectCss("2xl:flex", "");
    try expectCss("hover:flex dark:flex max-md:flex group-hover:flex before:flex", "");
    {
        var t = TestCtx.init();
        defer t.deinit();
        var env = env0;
        env.target = .before;
        try testing.expectEqualStrings("content:\"\";display:block", try t.css("before:block after:flex p-2", env));
        env.target = .after;
        try testing.expectEqualStrings("content:\"\";display:flex", try t.css("before:block after:flex p-2", env));
    }
    try expectCss("md:lg:flex", "");
    try expectCss("first:flex", ""); // no element info
    var t = TestCtx.init();
    defer t.deinit();
    var env = env0;
    env.element = .{ .index = 0, .count = 3 };
    try testing.expectEqualStrings("display:flex;padding:0.25rem", try t.css("first:flex last:block odd:p-1 even:p-2", env));
    try testing.expectEqualStrings("margin-top:1rem;margin-top:0.5rem", try t.css("odd:mt-2 first:mt-4", env));
    try testing.expectEqualStrings("margin-top:1rem;margin-top:0.5rem", try t.css("first:mt-4 odd:mt-2", env));
    env.element = .{ .index = 2, .count = 3 };
    try testing.expectEqualStrings("display:block;padding:0.25rem", try t.css("first:flex last:block odd:p-1 even:p-2", env));
    try testing.expectEqualStrings("margin:0.25rem", try t.css("nth-3:m-1 nth-2:m-2", env));
    try testing.expectEqualStrings("margin:0.25rem", try t.css("nth-[2n+1]:m-1 not-last:m-2", env));
    try testing.expectEqualStrings("margin:0.5rem", try t.css("[&:nth-child(3)]:m-2 [&:hover]:m-3", env));
    // breakpoints against the viewport and DPR
    env = .{ .viewport_w = 700, .viewport_h = 100 };
    try testing.expectEqualStrings("display:block", try t.css("sm:block md:flex", env));
    env.dpr = 2;
    try testing.expectEqualStrings("", try t.css("sm:block md:flex", env));
    env = .{ .viewport_w = 0, .viewport_h = 100 };
    try testing.expectEqualStrings("", try t.css("sm:block", env));
}

test "ordering follows Tailwind property order and specificity" {
    try expectCss("pt-2 p-4", "padding:1rem;padding-top:0.5rem");
    try expectCss("p-4 pt-2", "padding:1rem;padding-top:0.5rem");
    try expectCss("ms-1 mx-2 m-4", "margin:1rem;margin-inline:0.5rem;margin-inline-start:0.25rem");
    // same property: sorted by class text
    try expectCss("bg-red-500 bg-blue-500", "background-color:#2b7fff;background-color:#fb2c36");
}

test "variables are resolved" {
    try expectCss("translate-x-4 translate-y-2", "translate:1rem 0.5rem;translate:1rem 0.5rem");
    try expectCss("scale-50", "scale:50% 50%");
    try expectCss("blur-sm brightness-150", "filter:blur(8px) brightness(150%);filter:blur(8px) brightness(150%)");
    try expectCss("bg-linear-to-r from-red-500 to-blue-500", "background-image:linear-gradient(90deg in oklab, #fb2c36 0%, #2b7fff 100%)");
    try expectCss("bg-linear-to-r from-10% via-green-500 to-blue-500/50", "background-image:linear-gradient(90deg in oklab, transparent 10%, #00c950 50%, #2b7fff80 100%)");
    try expectCss("bg-linear-to-r", "");
    try expectCss("bg-linear-to-r from-brand", "background-image:linear-gradient(90deg in oklab, transparent 0%, transparent 100%)");
    try expectCss("bg-linear-to-r via-brand", "");
    try expectCss("bg-linear-to-r from-red-500 via-brand to-blue-500", "background-image:linear-gradient(90deg in oklab, #fb2c36 0%, #2b7fff 100%)");
    try expectCss("shadow-red-500 shadow-zz shadow-2xs", "box-shadow:0px 1px 0px 0px #0000000d");
    try expectCss("border-2 border-dashed", "border-width:2px;border-style:dashed;border-style:dashed");
    try expectCss("shadow-sm shadow-red-500", "box-shadow:0px 1px 3px 0px #fb2c36, 0px 1px 2px -1px #fb2c36");
    try expectCss("shadow-md", "box-shadow:0px 4px 6px -1px #0000001a, 0px 2px 4px -2px #0000001a");
    try expectCss("shadow-[0_0_10px_red] shadow-blue-500", "box-shadow:0 0 10px #2b7fff");
    try expectCss("shadow-[0_0_10px] shadow-blue-500", "box-shadow:0 0 10px #2b7fff");
    try expectCss("shadow-[0_0_10px_red]", "box-shadow:0 0 10px red");
}

test "number formatting" {
    var t = TestCtx.init();
    defer t.deinit();
    const a = t.arena.allocator();
    try testing.expectEqualStrings("0.25rem", try numUnit(a, 0.25, "rem"));
    try testing.expectEqualStrings("-1.5", try numUnit(a, -1.5, ""));
    try testing.expectEqualStrings("0", try numUnit(a, -0.0, ""));
    try testing.expectEqualStrings("33.33333588%", try numUnit(a, @as(f32, 1.0 / 3.0) * 100, "%"));
    try testing.expectEqual(@as(?f32, 0.5), parseNum(".5"));
    try testing.expectEqual(@as(?f32, null), parseNum("1e3"));
    try testing.expectEqual(@as(?f32, null), parseNum("."));
}

test "decode arbitrary" {
    var t = TestCtx.init();
    defer t.deinit();
    const a = t.arena.allocator();
    try testing.expectEqualStrings("3 1 auto", try decodeArbitrary(a, "3_1_auto"));
    try testing.expectEqualStrings("foo_bar", try decodeArbitrary(a, "foo\\_bar"));
    try testing.expectEqualStrings("url('https://example.com/my_logo.svg')", try decodeArbitrary(a, "url('https://example.com/my_logo.svg')"));
    try testing.expectEqualStrings("url(a_b) c", try decodeArbitrary(a, "url(a_b)_c"));
    try testing.expectEqualStrings("calc(1 + 2)", try decodeArbitrary(a, "calc(1_+_2)"));
}

test "split variant" {
    try testing.expectEqual(@as(?usize, 2), splitVariant("sm:mt-0"));
    try testing.expectEqual(@as(?usize, null), splitVariant("mask-[url('https://example.com/a.svg')]"));
    try testing.expectEqual(@as(?usize, null), splitVariant("[mask:foo]"));
    try testing.expectEqual(@as(?usize, 2), splitVariant("md:mask-[url('https://example.com/a.svg')]"));
    try testing.expectEqual(@as(?usize, null), splitVariant("content-['a:b]']"));
}

test "fuzz: random class strings never crash" {
    var prng = std.Random.DefaultPrng.init(0x7a11);
    const r = prng.random();
    const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789-_:/![]()#%.,'\" \\&{}+*@";
    const words = [_][]const u8{ "bg-", "text-", "p-", "-m-", "md:", "first:", "not-", "nth-[", "[&:", "from-", "via-", "to-", "shadow-", "border-", "rounded-", "w-", "[", "]", "(", ")", "red-500/", "/50", "!", "url(", "var(", "_", "blur-", "translate-x-", "scale-", "grid-cols-", "col-span-", "text-shadow-[", "shadow-[" };
    var buf: [200]u8 = undefined;
    var iter: usize = 0;
    while (iter < 20000) : (iter += 1) {
        var n: usize = 0;
        const len = r.uintLessThan(usize, buf.len);
        while (n < len) {
            if (r.boolean()) {
                const w = words[r.uintLessThan(usize, words.len)];
                if (n + w.len > len) break;
                @memcpy(buf[n..][0..w.len], w);
                n += w.len;
            } else {
                buf[n] = if (r.uintLessThan(u8, 20) == 0) r.int(u8) else alphabet[r.uintLessThan(usize, alphabet.len)];
                n += 1;
            }
        }
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var out: std.ArrayList(Declaration) = .empty;
        var env = env0;
        if (r.boolean()) env.element = .{ .index = r.uintLessThan(u32, 4), .count = 4, .empty = r.boolean() };
        try compile(arena.allocator(), buf[0..n], env, &out);
        for (out.items) |d| {
            for (d.value) |ch| try testing.expect(ch >= 0x20 or ch == '\t');
        }
    }
}
