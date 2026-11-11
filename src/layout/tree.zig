//! Node storage, per-node measurement cache, node dispatch, leaf layout, absolute positioning and rounding.
//!
//! Internal conventions (shared by flex.zig / block.zig / grid.zig):
//!  * axis index 0 = horizontal (width), 1 = vertical (height)
//!  * rects are `[4]f32` ordered left, top, right, bottom so `r[axis]` is the start edge and `r[axis + 2]` the end
//!  * "optional" lengths are plain f32 with NaN meaning "none" (NaN propagates through + and -, which gives
//!    taffy's `maybe_add`/`maybe_sub` for free)
//!  * available space is an f32: finite = definite, +inf = max-content, -inf = min-content
const std = @import("std");
const st = @import("style.zig");
const flex = @import("flex.zig");
const block = @import("block.zig");
const grid = @import("grid.zig");

const Style = st.Style;
pub const NodeId = u32;

pub const NONE: f32 = std.math.nan(f32);
pub const MAXC: f32 = std.math.inf(f32);
pub const MINC: f32 = -std.math.inf(f32);
pub const no_node: u32 = std.math.maxInt(u32);
/// Maximum nesting depth of the node tree; deeper trees make `compute` fail with `error.TooDeep`.
pub const max_depth = 256;

pub const Error = error{ OutOfMemory, TooDeep };

pub inline fn has(v: f32) bool {
    return v == v;
}
pub inline fn orElse(v: f32, d: f32) f32 {
    return if (v == v) v else d;
}
/// min(v, o) where a NaN `o` is ignored (NaN `v` stays NaN).
pub inline fn minO(v: f32, o: f32) f32 {
    return if (o < v) o else v;
}
pub inline fn maxO(v: f32, o: f32) f32 {
    return if (o > v) o else v;
}
pub inline fn clampO(v: f32, lo: f32, hi: f32) f32 {
    return maxO(minO(v, hi), lo);
}
pub inline fn isDef(a: f32) bool {
    return @abs(a) < MAXC;
}
/// definite available space -> value, otherwise none
pub inline fn defOrNone(a: f32) f32 {
    return if (isDef(a)) a else NONE;
}
inline fn same(a: f32, b: f32) bool {
    return a == b or (a != a and b != b);
}

/// Non-finite inputs (untrusted styles) count as "none".
pub inline fn fin(v: f32) f32 {
    return if (std.math.isFinite(v)) v else NONE;
}

pub fn resolveDim(d: st.Dim, base: f32) f32 {
    return switch (d) {
        .auto => NONE,
        .px => |v| fin(v),
        .percent => |p| fin(p * base),
    };
}
pub fn resolveLp(d: st.LengthPercentage, base: f32) f32 {
    return switch (d) {
        .px => |v| orElse(fin(v), 0),
        .percent => |p| orElse(fin(p * base), 0),
    };
}

pub const MarginSet = struct {
    pos: f32 = 0,
    neg: f32 = 0,
    pub fn with(a: MarginSet, m: f32) MarginSet {
        return if (m >= 0) .{ .pos = @max(a.pos, m), .neg = a.neg } else .{ .pos = a.pos, .neg = @min(a.neg, m) };
    }
    pub fn merge(a: MarginSet, b: MarginSet) MarginSet {
        return .{ .pos = @max(a.pos, b.pos), .neg = @min(a.neg, b.neg) };
    }
    pub fn resolve(a: MarginSet) f32 {
        return a.pos + a.neg;
    }
};

/// Inputs of a node computation (taffy's LayoutInput).
pub const In = struct {
    /// border-box size forced by the parent (NaN = not known)
    known: [2]f32 = .{ NONE, NONE },
    /// parent content-box size, for percentage resolution (NaN = indefinite)
    parent: [2]f32 = .{ NONE, NONE },
    /// available space for the margin box
    avail: [2]f32 = .{ MAXC, MAXC },
    /// true = perform layout (positions children), false = only compute this node's size
    layout: bool = false,
    /// taffy SizingMode::ContentSize: ignore the node's own `size` style (parent already applied it)
    content_sizing: bool = false,
    /// with content_sizing: the axis being measured (its min/max are ignored as well)
    cs_axis: u8 = 0,
    /// size-only requests: true = only the width is needed (the returned height is then NaN)
    width_only: bool = false,
    /// block layout only: may this node's top/bottom margins collapse with its children's
    collapse: bool = false,
    /// `known[1]` is a flexed size that is not definite for the percentages of the children
    indef_h: bool = false,
};

pub const Out = struct {
    size: [2]f32,
    /// extent of content measured from the border-box origin
    content: [2]f32 = .{ 0, 0 },
    /// first baseline, distance from border-box top (NaN = none)
    baseline: f32 = NONE,
    top_margin: MarginSet = .{},
    bottom_margin: MarginSet = .{},
    collapse_through: bool = false,
};

/// Computed geometry of a node.
pub const Layout = struct {
    /// border-box position relative to the parent's border-box origin
    x: f32 = 0,
    y: f32 = 0,
    /// border-box size
    w: f32 = 0,
    h: f32 = 0,
    /// extent of the node's content (in-flow + absolute descendants) measured from its border-box origin;
    /// compare against w/h to detect overflow
    content_w: f32 = 0,
    content_h: f32 = 0,
    padding: st.Edges(f32) = .all(0),
    border: st.Edges(f32) = .all(0),
    /// used margins (auto margins resolved; block margins after collapsing)
    margin: st.Edges(f32) = .all(0),
    /// first baseline as distance from the border-box top; NaN when the node has no baseline
    baseline: f32 = NONE,
};

/// Sizes a measured leaf. `known`: content-box dimensions that are already fixed (null = to be determined);
/// `available`: content-box space for the dimensions that are not known (min_content / max_content ask for
/// the intrinsic sizes). Returns the content-box size. Results are cached per node and request, so for a
/// text leaf in a flex row the typical calls are: max-content, min-content, then the final known width.
/// The available height is always reported as max_content (an auto height is content-based).
pub const MeasureFn = *const fn (ctx: *anyopaque, node: NodeId, known: [2]?f32, available: [2]st.AvailableSpace) [2]f32;
/// Optional: first-baseline offset from the content-box top for a measured leaf of the given content size.
pub const BaselineFn = *const fn (ctx: *anyopaque, node: NodeId, content_size: [2]f32) f32;

pub const Options = struct {
    /// taffy-style rounding to whole pixels (edges are rounded in absolute space, sizes derived from them)
    round: bool = false,
    /// snap all positions/sizes to the 1/64 px grid (Blink LayoutUnit) in absolute space; ignored when `round`
    /// (round-to-nearest; Blink itself truncates at every step, so values can differ by 1/64)
    quantize64: bool = false,
    /// called for measured leaves during the final layout pass; without it a leaf's baseline is its bottom
    baseline: ?BaselineFn = null,
};

const Node = struct {
    style: Style,
    parent: u32 = no_node,
    first_child: u32 = no_node,
    last_child: u32 = no_node,
    next_sibling: u32 = no_node,
    child_count: u32 = 0,
    measured: bool = false,
    /// index into Tree.pending of the latest deferred absolute layout of this node
    pending: u32 = no_node,
    /// style contains percentages that resolve against the parent size (part of the cache key then)
    pct: bool = false,
    /// no size/min/max/aspect-ratio styles: content sizing == inherent sizing
    plain: bool = false,
    ratio: bool = false,
};

const Entry = struct {
    known: [2]f32,
    avail: [2]f32,
    parent: [2]f32,
    size: [2]f32,
    /// bit0 content_sizing, bit1 collapse, bit2 indef_h
    flags: u8,
};

const n_slots = 9;
const flag_width_only: u8 = 16;
const Cache = struct {
    /// bit i = measure slot i valid; bit 15 = final valid
    valid: u16 = 0,
    slots: [n_slots]Entry = undefined,
    final: Entry = undefined,
    final_out: Out = undefined,
};

/// Bump allocator with stack discipline whose blocks never move (so slices stay valid across recursion).
pub const Scratch = struct {
    chunks: std.ArrayList([]align(16) u8) = .empty,
    cur: u32 = 0,
    off: usize = 0,

    pub const Mark = struct { cur: u32, off: usize };

    pub fn mark(s: *Scratch) Mark {
        return .{ .cur = s.cur, .off = s.off };
    }
    pub fn release(s: *Scratch, m: Mark) void {
        s.cur = m.cur;
        s.off = m.off;
    }
    pub fn alloc(s: *Scratch, a: std.mem.Allocator, comptime T: type, n: usize) Error![]T {
        const bytes = std.math.mul(usize, n, @sizeOf(T)) catch return error.OutOfMemory;
        const p = try s.raw(a, bytes);
        return @as([*]T, @ptrCast(@alignCast(p)))[0..n];
    }
    fn raw(s: *Scratch, a: std.mem.Allocator, bytes_in: usize) Error![*]align(16) u8 {
        const bytes = std.mem.alignForward(usize, bytes_in, 16);
        while (true) {
            if (s.cur < s.chunks.items.len) {
                const c = s.chunks.items[s.cur];
                if (c.len - s.off >= bytes) {
                    const p: [*]align(16) u8 = @alignCast(c.ptr + s.off);
                    s.off += bytes;
                    return p;
                }
                s.cur += 1;
                s.off = 0;
                continue;
            }
            const want = @max(bytes, @as(usize, 32 * 1024));
            const mem = try a.alignedAlloc(u8, .@"16", want);
            errdefer a.free(mem);
            try s.chunks.append(a, mem);
        }
    }
    fn deinit(s: *Scratch, a: std.mem.Allocator) void {
        for (s.chunks.items) |c| a.free(c);
        s.chunks.deinit(a);
    }
};

const default_style: Style = .{};
const zero_layout: Layout = .{};

/// Resolved box model of a node against a containing size.
pub const Box = struct {
    padding: [4]f32,
    border: [4]f32,
    /// auto margins resolve to 0 here
    margin: [4]f32,
    margin_auto: [4]bool,
    /// padding + border per axis
    pb: [2]f32,
    /// border-box sizes (NaN = auto / none), aspect-ratio applied
    size: [2]f32,
    min: [2]f32,
    max: [2]f32,

    pub inline fn marginSum(b: *const Box, axis: usize) f32 {
        return b.margin[axis] + b.margin[axis + 2];
    }
};

fn rect(comptime T: type, e: st.Edges(T)) [4]T {
    return .{ e.left, e.top, e.right, e.bottom };
}
pub fn toEdges(r: [4]f32) st.Edges(f32) {
    return .{ .left = r[0], .top = r[1], .right = r[2], .bottom = r[3] };
}

/// aspect-ratio transfer: border-box size of `axis` derived from the border-box size `other` of the other
/// axis (the ratio applies to the box selected by box-sizing). NaN when there is no ratio.
pub fn ratioTransfer(s: *const Style, b: *const Box, axis: usize, other: f32) f32 {
    const r = s.aspect_ratio orelse return NONE;
    if (!(r > 0) or !has(other)) return NONE;
    const cbx = s.box_sizing == .content_box;
    const v = if (cbx) @max(other - b.pb[1 - axis], 0) else other;
    const tv = if (axis == 0) v * r else v / r;
    return if (cbx) tv + b.pb[axis] else tv;
}

/// Resolve padding/border/margin/size/min/max of `s`. Percent padding & margin resolve against `basis[0]`
/// (inline size, 0 when indefinite), sizes against `basis` per axis (auto when indefinite).
pub fn resolveBox(s: *const Style, basis: [2]f32) Box {
    var b: Box = undefined;
    const pad = rect(st.LengthPercentage, s.padding);
    const mar = rect(st.Dim, s.margin);
    b.border = rect(f32, s.border);
    for (0..4) |i| {
        b.padding[i] = @max(resolveLp(pad[i], basis[0]), 0);
        b.border[i] = @max(b.border[i], 0);
        b.margin_auto[i] = mar[i] == .auto;
        b.margin[i] = orElse(resolveDim(mar[i], basis[0]), 0);
    }
    b.pb = .{ b.padding[0] + b.padding[2] + b.border[0] + b.border[2], b.padding[1] + b.padding[3] + b.border[1] + b.border[3] };
    const adj: [2]f32 = if (s.box_sizing == .content_box) b.pb else .{ 0, 0 };
    const raw: [3]*const [2]st.Dim = .{ &s.size, &s.min_size, &s.max_size };
    const dst: [3]*[2]f32 = .{ &b.size, &b.min, &b.max };
    for (raw, dst) |r, d| {
        const v: [2]f32 = .{ resolveDim(r[0], basis[0]), resolveDim(r[1], basis[1]) };
        d.* = .{ v[0] + adj[0], v[1] + adj[1] };
    }
    if (s.aspect_ratio != null and !has(b.size[0]) and !has(b.size[1])) {
        // both dimensions automatic: block-axis min/max transfer to the inline axis through the ratio
        if (!has(b.min[0])) b.min[0] = ratioTransfer(s, &b, 0, b.min[1]);
        if (!has(b.max[0])) b.max[0] = ratioTransfer(s, &b, 0, b.max[1]);
    }
    return b;
}

/// Size of a container fixed by its styles (taffy "styled_based_known_dimensions").
pub fn styledKnown(in: In, b: *const Box) [2]f32 {
    var k = in.known;
    for (0..2) |a| {
        if (has(k[a])) continue;
        if (has(b.min[a]) and has(b.max[a]) and b.max[a] <= b.min[a]) {
            k[a] = b.min[a];
        } else if (!in.content_sizing) {
            k[a] = clampO(b.size[a], b.min[a], b.max[a]);
        }
        k[a] = maxO(k[a], b.pb[a]);
    }
    // aspect ratio transfer after clamping (width known through min/max or known dims, height auto)
    return k;
}

fn stylePlain(s: *const Style) bool {
    inline for (.{ s.size, s.min_size, s.max_size }) |v| {
        if (v[0] != .auto or v[1] != .auto) return false;
    }
    return s.aspect_ratio == null;
}

fn stylePct(s: *const Style) bool {
    inline for (.{ s.size, s.min_size, s.max_size }) |v| {
        if (v[0] == .percent or v[1] == .percent) return true;
    }
    inline for (.{ "top", "right", "bottom", "left" }) |f| {
        if (@field(s.margin, f) == .percent or @field(s.padding, f) == .percent) return true;
    }
    return false;
}

pub const Tree = struct {
    alloc: std.mem.Allocator,
    nodes: std.ArrayList(Node) = .empty,
    layouts: std.ArrayList(Layout) = .empty,
    caches: std.ArrayList(Cache) = .empty,
    scratch: Scratch = .{},
    pending: std.ArrayList(Pending) = .empty,
    root: u32 = no_node,
    /// lay out on Blink's 1/64 px LayoutUnit grid (Options.quantize64)
    q64: bool = false,
    ctx: *anyopaque = undefined,
    measure_fn: ?MeasureFn = null,
    baseline_fn: ?BaselineFn = null,
    depth: u32 = 0,
    /// statistics of the last `compute`: number of MeasureFn invocations / node computations (cache misses)
    measure_calls: u32 = 0,
    node_computes: u32 = 0,

    /// All memory (nodes, layouts, caches, scratch) comes from `alloc`; a per-render arena is the expected choice.
    pub fn init(alloc: std.mem.Allocator) Tree {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Tree) void {
        self.nodes.deinit(self.alloc);
        self.layouts.deinit(self.alloc);
        self.caches.deinit(self.alloc);
        self.pending.deinit(self.alloc);
        self.scratch.deinit(self.alloc);
        self.* = undefined;
    }

    /// Pre-size the node arrays (optional).
    pub fn ensureCapacity(self: *Tree, n: usize) !void {
        try self.nodes.ensureTotalCapacity(self.alloc, n);
        try self.layouts.ensureTotalCapacity(self.alloc, n);
        try self.caches.ensureTotalCapacity(self.alloc, n);
    }

    /// Adds a node. The style is copied; slices inside it (grid track lists) stay caller-owned.
    pub fn addNode(self: *Tree, s: Style) !NodeId {
        const id: u32 = @intCast(self.nodes.items.len);
        if (id == no_node) return error.OutOfMemory;
        try self.nodes.append(self.alloc, .{ .style = s, .pct = stylePct(&s), .plain = stylePlain(&s), .ratio = s.aspect_ratio != null });
        errdefer self.nodes.items.len -= 1;
        try self.layouts.append(self.alloc, .{});
        errdefer self.layouts.items.len -= 1;
        try self.caches.append(self.alloc, .{});
        return id;
    }

    /// Appends `child` (which must not have a parent yet) to `parent`'s child list.
    /// Fails with `error.InvalidNode` for unknown ids, a child that already has a parent, or a cycle.
    pub fn appendChild(self: *Tree, parent: NodeId, child: NodeId) !void {
        const n = self.nodes.items;
        if (parent >= n.len or child >= n.len or parent == child or n[child].parent != no_node) return error.InvalidNode;
        // `child` has no parent, so a cycle is only possible when it is the root of `parent`'s tree
        var up = parent;
        while (n[up].parent != no_node) up = n[up].parent;
        if (up == child) return error.InvalidNode;
        n[child].parent = parent;
        n[child].next_sibling = no_node;
        if (n[parent].last_child == no_node) n[parent].first_child = child else n[n[parent].last_child].next_sibling = child;
        n[parent].last_child = child;
        n[parent].child_count += 1;
    }

    /// Marks a leaf as having intrinsic content provided by the MeasureFn (text, images).
    /// Measured nodes are always treated as leaves.
    pub fn setMeasured(self: *Tree, node: NodeId, measured: bool) void {
        if (node < self.nodes.items.len) self.nodes.items[node].measured = measured;
    }

    /// Style of `node` (the default style for an unknown id).
    pub fn style(self: *const Tree, node: NodeId) *const Style {
        return if (node < self.nodes.items.len) &self.nodes.items[node].style else &default_style;
    }

    pub fn setStyle(self: *Tree, node: NodeId, s: Style) void {
        if (node >= self.nodes.items.len) return;
        self.nodes.items[node].style = s;
        self.nodes.items[node].pct = stylePct(&s);
        self.nodes.items[node].plain = stylePlain(&s);
        self.nodes.items[node].ratio = s.aspect_ratio != null;
    }

    /// Result of the last `compute` for `node` (zeroed for display:none subtrees and nodes outside the root's subtree).
    pub fn layout(self: *const Tree, node: NodeId) *const Layout {
        return if (node < self.layouts.items.len) &self.layouts.items[node] else &zero_layout;
    }

    pub inline fn firstChild(self: *const Tree, node: u32) u32 {
        return self.nodes.items[node].first_child;
    }
    pub inline fn nextSibling(self: *const Tree, node: u32) u32 {
        return self.nodes.items[node].next_sibling;
    }

    /// Lays out the subtree of `root`. The root is treated as a block-level box in a containing block of
    /// `available` size: auto width stretches to a definite available width, auto height is content-sized,
    /// percentages resolve against definite available sizes.
    /// `measure` is called (with `ctx`) for nodes flagged with `setMeasured`; it receives the known content-box
    /// dimensions and the available content-box space and returns the content-box size.
    pub fn compute(self: *Tree, root: NodeId, available: [2]st.AvailableSpace, ctx: *anyopaque, measure: MeasureFn, opts: Options) !void {
        if (root >= self.nodes.items.len) return error.InvalidNode;
        for (self.caches.items) |*c| c.valid = 0;
        self.pending.clearRetainingCapacity();
        self.root = root;
        self.ctx = ctx;
        self.measure_fn = measure;
        self.baseline_fn = opts.baseline;
        self.depth = 0;
        self.measure_calls = 0;
        self.node_computes = 0;
        self.scratch.release(.{ .cur = 0, .off = 0 });

        var av: [2]f32 = undefined;
        for (0..2) |a| av[a] = switch (available[a]) {
            .definite => |v| if (std.math.isFinite(v)) v else MAXC,
            .min_content => MINC,
            .max_content => MAXC,
        };
        const parent: [2]f32 = .{ defOrNone(av[0]), defOrNone(av[1]) };
        const s = &self.nodes.items[root].style;
        if (s.display == .none) {
            self.hide(root);
            return;
        }
        self.q64 = opts.quantize64 and !opts.round;
        const b = self.rbox(s, parent);
        var in: In = .{ .parent = parent, .avail = av, .layout = true };
        in.known = styledKnown(in, &b);
        if (!has(in.known[0]) and has(parent[0])) {
            // block-level stretch fit (the root is blockified)
            if (has(in.known[1])) in.known[0] = clampO(self.ratio(s, &b, 0, in.known[1]), b.min[0], b.max[0]);
            if (!has(in.known[0])) in.known[0] = clampO(parent[0] - b.marginSum(0), b.min[0], b.max[0]);
            in.known[0] = @max(in.known[0], b.pb[0]);
        }
        const out = try self.computeNode(root, in);
        self.setLayout(root, .{ b.margin[0], b.margin[1] }, &out, &b);
        try self.flushPending(parent);
        if (opts.round or opts.quantize64) self.roundAll(root, if (opts.round) 1 else 64);
    }

    // ------------------------------------------------------------------------------------------------
    // internals shared with the algorithm files

    /// float -> LayoutUnit: truncation toward zero onto the 1/64 px grid (no-op unless quantize64).
    pub inline fn qt(self: *const Tree, v: f32) f32 {
        return if (self.q64) @trunc(v * 64) / 64 else v;
    }
    /// LayoutUnit / integer: integer division of 1/64 units (truncating toward zero).
    pub inline fn div(self: *const Tree, v: f32, k: f32) f32 {
        return if (self.q64) @trunc(@trunc(v * 64) / k) / 64 else v / k;
    }
    pub fn dim(self: *const Tree, d: st.Dim, base: f32) f32 {
        return self.qt(resolveDim(d, base));
    }
    pub fn lp(self: *const Tree, d: st.LengthPercentage, base: f32) f32 {
        return self.qt(resolveLp(d, base));
    }
    pub fn ratio(self: *const Tree, s: *const Style, b: *const Box, axis: usize, other: f32) f32 {
        return self.qt(ratioTransfer(s, b, axis, other));
    }
    /// `resolveBox` on the layout-unit grid.
    pub fn rbox(self: *const Tree, s: *const Style, basis: [2]f32) Box {
        var b = resolveBox(s, basis);
        if (self.q64) {
            for (0..4) |i| {
                b.padding[i] = self.qt(b.padding[i]);
                b.border[i] = self.qt(b.border[i]);
                b.margin[i] = self.qt(b.margin[i]);
            }
            const pb: [2]f32 = .{ b.padding[0] + b.padding[2] + b.border[0] + b.border[2], b.padding[1] + b.padding[3] + b.border[1] + b.border[3] };
            const adj: [2]f32 = if (s.box_sizing == .content_box) .{ pb[0] - b.pb[0], pb[1] - b.pb[1] } else .{ 0, 0 };
            b.pb = pb;
            for (0..2) |a| {
                b.size[a] = self.qt(b.size[a] + adj[a]);
                b.min[a] = self.qt(b.min[a] + adj[a]);
                b.max[a] = self.qt(b.max[a] + adj[a]);
            }
        }
        return b;
    }

    /// Box of the node being computed: like `rbox` against `in.parent`, but under content sizing the
    /// min/max constraints of the axis being measured are dropped (the parent applies them itself).
    pub fn sbox(self: *const Tree, s: *const Style, in: *const In) Box {
        var b = self.rbox(s, in.parent);
        if (in.content_sizing and !has(in.known[in.cs_axis & 1])) {
            b.min[in.cs_axis & 1] = NONE;
            b.max[in.cs_axis & 1] = NONE;
        }
        return b;
    }

    /// Applies the aspect ratio to a container's known border-box dimensions (call again once the inline size
    /// is settled). A ratio-determined height of a box with visible overflow and automatic min-height is only
    /// a floor (the automatic content-based minimum still applies): it is then returned instead of being
    /// stored in `known[1]`; NaN otherwise.
    pub fn applyRatio(self: *const Tree, s: *const Style, b: *const Box, known: *[2]f32) f32 {
        if (s.aspect_ratio == null) return NONE;
        if (has(known[1]) and !has(known[0])) {
            const w = self.ratio(s, b, 0, known[1]);
            if (has(w)) known[0] = @max(clampO(w, b.min[0], b.max[0]), b.pb[0]);
        } else if (has(known[0]) and !has(known[1])) {
            const h = self.ratio(s, b, 1, known[0]);
            if (!has(h)) return NONE;
            const rh = @max(clampO(h, b.min[1], b.max[1]), b.pb[1]);
            if (s.overflow_x == .visible and s.overflow_y == .visible and s.min_size[1] == .auto) return rh;
            known[1] = rh;
        }
        return NONE;
    }

    pub fn setLayout(self: *Tree, node: u32, pos: [2]f32, out: *const Out, b: *const Box) void {
        self.layouts.items[node] = .{
            .x = pos[0],
            .y = pos[1],
            .w = out.size[0],
            .h = out.size[1],
            .content_w = out.content[0],
            .content_h = out.content[1],
            .padding = toEdges(b.padding),
            .border = toEdges(b.border),
            .margin = toEdges(b.margin),
            .baseline = out.baseline,
        };
    }

    /// Grow `content` (extent from the container's border-box origin) by a laid-out child.
    pub fn accumContent(self: *const Tree, content: *[2]f32, child: u32) void {
        const l = &self.layouts.items[child];
        const s = &self.nodes.items[child].style;
        const ex = if (s.overflow_x == .visible) @max(l.w, l.content_w) else l.w;
        const ey = if (s.overflow_y == .visible) @max(l.h, l.content_h) else l.h;
        content[0] = @max(content[0], l.x + ex);
        content[1] = @max(content[1], l.y + ey);
    }

    /// Zero the layout of a display:none subtree.
    pub fn hide(self: *Tree, root: u32) void {
        const n = self.nodes.items;
        var cur = root;
        while (true) {
            self.layouts.items[cur] = .{};
            if (n[cur].first_child != no_node) {
                cur = n[cur].first_child;
                continue;
            }
            while (true) {
                if (cur == root) return;
                if (n[cur].next_sibling != no_node) {
                    cur = n[cur].next_sibling;
                    break;
                }
                cur = n[cur].parent;
                if (cur == no_node) return;
            }
        }
    }

    pub fn measureChild(self: *Tree, node: u32, in: In, axis: usize) Error!f32 {
        var i = in;
        i.layout = false;
        i.width_only = axis == 0;
        return (try self.computeNode(node, i)).size[axis];
    }

    fn slotOf(in: *const In) u4 {
        const kw = has(in.known[0]);
        const kh = has(in.known[1]);
        if (kw and kh) return 0;
        if (kw) return @as(u4, 1) + @intFromBool(in.avail[1] == MINC);
        if (kh) return @as(u4, 3) + @intFromBool(in.avail[0] == MINC);
        return @as(u4, 5) + @intFromBool(in.avail[1] == MINC) + 2 * @as(u4, @intFromBool(in.avail[0] == MINC));
    }

    fn matches(e: *const Entry, in: *const In, pct: bool, flags: u8, has_ratio: bool) bool {
        // (a full result also answers a width-only request)
        if (e.flags != flags and e.flags != (flags & ~flag_width_only)) return false;
        inline for (0..2) |a| {
            // (a known dimension equal to the cached result is the same request, unless it would newly
            // trigger an aspect-ratio transfer)
            if (!(same(in.known[a], e.known[a]) or (in.known[a] == e.size[a] and !has_ratio))) return false;
            if (!has(in.known[a]) and in.avail[a] != e.avail[a]) return false;
            if (pct and !same(in.parent[a], e.parent[a])) return false;
        }
        return true;
    }

    /// Cached node computation (taffy's compute_cached_layout + dispatch).
    pub fn computeNode(self: *Tree, node: u32, in_: In) Error!Out {
        const n = &self.nodes.items[node];
        const c = &self.caches.items[node];
        var in = in_;
        if (n.plain) in.content_sizing = false;
        if (!in.content_sizing or (has(in.known[0]) and has(in.known[1]))) in.cs_axis = 0;
        if (!has(in.known[1])) in.indef_h = false;
        // The available height never influences a result (auto heights are content-based) and a known
        // dimension makes its available space irrelevant: normalise both for better cache hits.
        in.avail[1] = MAXC;
        if (has(in.known[0])) in.avail[0] = MAXC;
        if (in.layout or has(in.known[0])) in.width_only = false;
        const flags: u8 = @as(u8, @intFromBool(in.content_sizing)) | (@as(u8, @intFromBool(in.collapse)) << 1) | (@as(u8, @intFromBool(in.indef_h)) << 2) |
            ((in.cs_axis & 1) << 3) | (if (in.width_only) flag_width_only else 0);
        if (c.valid & 0x8000 != 0 and matches(&c.final, &in, n.pct, flags, n.ratio)) {
            return c.final_out;
        }
        if (!in.layout) {
            var bits = c.valid & 0x1ff;
            while (bits != 0) {
                const i: u4 = @intCast(@ctz(bits));
                bits &= bits - 1;
                if (matches(&c.slots[i], &in, n.pct, flags, n.ratio)) return .{ .size = c.slots[i].size };
            }
        }
        if (self.depth >= max_depth) return error.TooDeep;
        self.depth += 1;
        defer self.depth -= 1;
        self.node_computes += 1;

        const out: Out = if (n.child_count == 0 or n.measured)
            self.computeLeaf(node, in)
        else switch (n.style.display) {
            .flex => try flex.compute(self, node, in),
            .block => try block.compute(self, node, in),
            .grid => try grid.compute(self, node, in),
            .none => .{ .size = .{ 0, 0 } },
        };

        const e: Entry = .{ .known = in.known, .avail = in.avail, .parent = in.parent, .size = out.size, .flags = flags };
        if (in.layout) {
            c.final = e;
            c.final_out = out;
            c.valid |= 0x8000;
        } else {
            const i = slotOf(&in);
            c.slots[i] = e;
            c.valid |= @as(u16, 1) << i;
        }
        return out;
    }

    fn computeLeaf(self: *Tree, node: u32, in: In) Out {
        const n = &self.nodes.items[node];
        const s = &n.style;
        const b = self.sbox(s, &in);
        var size = in.known;
        const mn = b.min;
        const mx = b.max;
        if (!in.content_sizing) {
            for (0..2) |a| size[a] = orElse(size[a], b.size[a]);
        }
        if (has(size[0]) != has(size[1])) {
            // aspect-ratio transfer from the definite (clamped) dimension
            const a: usize = @intFromBool(has(size[0]));
            const tv = self.ratio(s, &b, a, clampO(size[1 - a], mn[1 - a], mx[1 - a]));
            if (has(tv)) size[a] = tv;
        }
        if (n.measured and n.child_count != 0) {
            // children of a measured node are not laid out
            var ch = n.first_child;
            while (ch != no_node) : (ch = self.nodes.items[ch].next_sibling) self.hide(ch);
        }
        const prevents_collapse = s.display != .block or s.overflow_x != .visible or s.overflow_y != .visible or
            s.position == .absolute or b.padding[1] > 0 or b.padding[3] > 0 or b.border[1] > 0 or b.border[3] > 0 or
            size[1] > 0 or mn[1] > 0 or n.measured;

        var measured: [2]f32 = .{ 0, 0 };
        var content_known: [2]f32 = .{ NONE, NONE };
        for (0..2) |a| {
            if (has(size[a])) content_known[a] = @max(clampO(size[a], mn[a], mx[a]) - b.pb[a], 0);
        }
        if (n.measured and !(has(content_known[0]) and has(content_known[1]))) {
            if (self.measure_fn) |mf| {
                var kn: [2]?f32 = undefined;
                var av: [2]st.AvailableSpace = undefined;
                for (0..2) |a| {
                    kn[a] = if (has(content_known[a])) content_known[a] else null;
                    if (has(content_known[a])) {
                        av[a] = .{ .definite = content_known[a] };
                    } else {
                        var v = in.avail[a] - b.marginSum(a);
                        if (has(mx[a])) v = mx[a];
                        if (isDef(v)) {
                            av[a] = .{ .definite = @max(clampO(v, mn[a], mx[a]) - b.pb[a], 0) };
                        } else av[a] = if (v < 0) .min_content else .max_content;
                    }
                }
                self.measure_calls += 1;
                measured = mf(self.ctx, node, kn, av);
                for (0..2) |a| {
                    if (!(measured[a] >= 0) or measured[a] == MAXC) measured[a] = 0;
                }
            }
        }
        var out: Out = .{ .size = undefined };
        for (0..2) |a| {
            const c = if (has(content_known[a])) content_known[a] else measured[a];
            if (has(content_known[a])) measured[a] = content_known[a];
            out.size[a] = @max(clampO(orElse(size[a], c + b.pb[a]), mn[a], mx[a]), b.pb[a]);
        }
        out.content = .{ b.border[0] + b.padding[0] + measured[0], b.border[1] + b.padding[1] + measured[1] };
        if (n.measured and in.layout) {
            if (self.baseline_fn) |bf| {
                const cb: [2]f32 = .{ @max(out.size[0] - b.pb[0], 0), @max(out.size[1] - b.pb[1], 0) };
                const bl = bf(self.ctx, node, cb);
                if (has(bl)) out.baseline = b.border[1] + b.padding[1] + bl;
            }
        }
        out.collapse_through = !prevents_collapse and out.size[1] == 0;
        return out;
    }

    /// Lays out an absolutely positioned child of `container` now, or defers it when the container is not the
    /// child's containing block (`position: static`): it is then resolved against the nearest positioned
    /// ancestor (or the viewport) once the whole tree has been laid out.
    pub fn placeAbsolute(self: *Tree, container: u32, child: u32, area: [4]f32, sp: Static) Error!void {
        if (self.nodes.items[container].style.position != .static) return self.layoutAbsolute(child, area, sp);
        self.hide(child);
        self.nodes.items[child].pending = @intCast(self.pending.items.len);
        try self.pending.append(self.alloc, .{ .node = child, .parent = container, .sp = sp });
    }

    fn flushPending(self: *Tree, viewport: [2]f32) Error!void {
        var i: usize = 0;
        while (i < self.pending.items.len) : (i += 1) {
            const e = self.pending.items[i];
            if (self.nodes.items[e.node].pending != i) continue;
            var off: [2]f32 = .{ 0, 0 };
            var a = e.parent;
            var area: [4]f32 = undefined;
            while (true) {
                const l = &self.layouts.items[a];
                if (self.nodes.items[a].style.position != .static) {
                    area = .{ l.border.left - off[0], l.border.top - off[1], l.w - l.border.left - l.border.right, l.h - l.border.top - l.border.bottom };
                    break;
                }
                off[0] += l.x;
                off[1] += l.y;
                if (a == self.root or self.nodes.items[a].parent == no_node) {
                    // initial containing block
                    area = .{ -off[0], -off[1], orElse(viewport[0], l.w), orElse(viewport[1], l.h) };
                    break;
                }
                a = self.nodes.items[a].parent;
            }
            try self.layoutAbsolute(e.node, area, e.sp);
        }
    }

    pub const Pending = struct { node: u32, parent: u32, sp: Static };

    pub const Static = struct {
        /// static-position rectangle relative to the container's border-box origin: x, y, w, h
        rect: [4]f32,
        /// alignment inside the rectangle per axis: 0 = start, 1 = center, 2 = end
        al: [2]u8 = .{ 0, 0 },
        /// stretch to the rectangle when size is auto and insets are auto (grid areas)
        stretch: [2]bool = .{ false, false },
    };

    /// Lays out one `position:absolute` child. `area` = containing block (x, y, w, h relative to the container's
    /// border-box origin; normally its padding box).
    pub fn layoutAbsolute(self: *Tree, child: u32, area: [4]f32, sp: Static) Error!void {
        const s = &self.nodes.items[child].style;
        const cb: [2]f32 = .{ area[2], area[3] };
        var b = self.rbox(s, cb);
        const ins_raw = rect(st.Dim, s.inset);
        var ins: [4]f32 = undefined;
        for (0..4) |i| ins[i] = self.dim(ins_raw[i], cb[i & 1]);

        var known: [2]f32 = .{ clampO(b.size[0], b.min[0], b.max[0]), clampO(b.size[1], b.min[1], b.max[1]) };
        var avail: [2]f32 = undefined;
        for (0..2) |a| {
            const both = has(ins[a]) and has(ins[a + 2]);
            const room = if (both or !sp.stretch[a]) cb[a] - orElse(ins[a], 0) - orElse(ins[a + 2], 0) - b.marginSum(a) else sp.rect[a + 2] - b.marginSum(a);
            avail[a] = @max(room, 0);
            if (!has(known[a]) and (both or (sp.stretch[a] and !has(ins[a]) and !has(ins[a + 2])))) {
                // stretch between the insets unless the other axis + aspect ratio determines this one
                const o = 1 - a;
                if (s.aspect_ratio != null and has(known[o])) continue;
                known[a] = clampO(avail[a], b.min[a], b.max[a]);
            }
        }
        if (has(known[0]) != has(known[1])) {
            const a: usize = @intFromBool(has(known[0]));
            known[a] = clampO(self.ratio(s, &b, a, known[1 - a]), b.min[a], b.max[a]);
        }
        for (0..2) |a| known[a] = maxO(known[a], b.pb[a]);
        var in: In = .{ .known = known, .parent = cb, .avail = .{ avail[0] + b.marginSum(0), avail[1] + b.marginSum(1) } };
        if (!has(known[0]) or !has(known[1])) {
            const m = try self.computeNode(child, in);
            for (0..2) |a| {
                if (!has(known[a])) known[a] = @max(clampO(m.size[a], b.min[a], b.max[a]), b.pb[a]);
            }
            in.known = known;
        }
        in.layout = true;
        const out = try self.computeNode(child, in);
        const size = out.size;

        var pos: [2]f32 = undefined;
        for (0..2) |a| {
            const e = a + 2;
            if (has(ins[a]) and has(ins[e])) {
                const free = cb[a] - ins[a] - ins[e] - size[a] - b.marginSum(a);
                const cnt: f32 = @floatFromInt(@as(u8, @intFromBool(b.margin_auto[a])) + @intFromBool(b.margin_auto[e]));
                if (cnt > 0) {
                    if (free >= 0 or a == 1) {
                        if (b.margin_auto[a]) b.margin[a] = free / cnt;
                        if (b.margin_auto[e]) b.margin[e] = free / cnt;
                    } else if (b.margin_auto[e]) b.margin[e] = free;
                }
            }
            if (has(ins[a])) {
                pos[a] = area[a] + ins[a] + b.margin[a];
            } else if (has(ins[e])) {
                pos[a] = area[a] + cb[a] - ins[e] - b.margin[e] - size[a];
            } else {
                const r0 = sp.rect[a];
                const rs = sp.rect[a + 2];
                pos[a] = switch (sp.al[a]) {
                    0 => r0 + b.margin[a],
                    1 => r0 + (rs - size[a] + b.margin[a] - b.margin[e]) / 2,
                    else => r0 + rs - size[a] - b.margin[e],
                };
            }
        }
        self.setLayout(child, pos, &out, &b);
    }

    fn roundAll(self: *Tree, root: u32, scale: f32) void {
        const n = self.nodes.items;
        const k = scale;
        var stack: [max_depth + 2][2]f32 = undefined;
        var sp: usize = 0;
        var cum: [2]f32 = .{ 0, 0 };
        var cur = root;
        while (true) {
            // enter
            const l = &self.layouts.items[cur];
            const o: [2]f32 = .{ cum[0] + l.x, cum[1] + l.y };
            const rx = rnd(o[0], k);
            const ry = rnd(o[1], k);
            const r: Layout = .{
                .x = rx - rnd(cum[0], k),
                .y = ry - rnd(cum[1], k),
                .w = rnd(o[0] + l.w, k) - rx,
                .h = rnd(o[1] + l.h, k) - ry,
                .content_w = rnd(o[0] + l.content_w, k) - rx,
                .content_h = rnd(o[1] + l.content_h, k) - ry,
                .padding = .{
                    .left = rnd(o[0] + l.border.left + l.padding.left, k) - rnd(o[0] + l.border.left, k),
                    .top = rnd(o[1] + l.border.top + l.padding.top, k) - rnd(o[1] + l.border.top, k),
                    .right = rnd(o[0] + l.w - l.border.right, k) - rnd(o[0] + l.w - l.border.right - l.padding.right, k),
                    .bottom = rnd(o[1] + l.h - l.border.bottom, k) - rnd(o[1] + l.h - l.border.bottom - l.padding.bottom, k),
                },
                .border = .{
                    .left = rnd(o[0] + l.border.left, k) - rx,
                    .top = rnd(o[1] + l.border.top, k) - ry,
                    .right = rnd(o[0] + l.w, k) - rnd(o[0] + l.w - l.border.right, k),
                    .bottom = rnd(o[1] + l.h, k) - rnd(o[1] + l.h - l.border.bottom, k),
                },
                .margin = l.margin,
                .baseline = if (has(l.baseline)) rnd(o[1] + l.baseline, k) - ry else NONE,
            };
            l.* = r;
            if (n[cur].first_child != no_node and sp < stack.len) {
                stack[sp] = cum;
                sp += 1;
                cum = o;
                cur = n[cur].first_child;
                continue;
            }
            while (true) {
                if (cur == root) return;
                if (n[cur].next_sibling != no_node) {
                    cur = n[cur].next_sibling;
                    break;
                }
                cur = n[cur].parent;
                if (cur == no_node or sp == 0) return;
                sp -= 1;
                cum = stack[sp];
            }
        }
    }
};

fn rnd(v: f32, k: f32) f32 {
    return @round(v * k) / k;
}
