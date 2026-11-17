//! The document-level tagging and conformance pass, plugged into `interactive.finishDocument`
//! through its `DocHook` (takumi-pdf `lib.rs::render_settling` / `open_document`, krilla
//! `serialize_tag_tree`, `chunk_container.rs` and the validators' checks):
//!
//! * `annot`: a link annotation of the content joins the structure tree (`/StructParent`, its
//!   URI as `/Contents`); repeated boxes' links stay outside it. Parent-tree numbers follow
//!   krilla: per page, its tagged annotations, then the page itself (when it marked content);
//! * `tree`: builds and writes the structure tree before the destinations (PDF/UA-2
//!   destinations name structure elements);
//! * `run`: catalog / Info / XMP parts the validators change, and the violations of the
//!   metadata, outline, attachments and structure checks.
const std = @import("std");
const render = @import("../render.zig");
const w = @import("writer.zig");
const opt = @import("options.zig");
const meta = @import("metadata.zig");
const sf = @import("emit_surface.zig");
const tags = @import("tags.zig");
const conform = @import("conform.zig");
const interactive = @import("interactive.zig");
const bump = @import("../bump.zig");

const Allocator = std.mem.Allocator;
const Error = render.Error;
const Ref = w.Ref;
const none = render.none;

pub const TagDoc = struct {
    a: Allocator,
    cx: *sf.Ctx,
    cfg: conform.Config,
    report: conform.Report,
    opts: *const opt.PdfOptions,
    /// the document carries a structure tree
    tagged: bool,
    collector: tags.Collector,
    links: *interactive.Collector,
    page_refs: []const Ref = &.{},
    /// per output page drawn so far: its marked-content ids, and its /StructParents
    mcids: std.ArrayList(i32) = .empty,
    page_sp: std.ArrayList(?i32) = .empty,
    /// per page: some annotation (tagged or not) is on it
    page_annots: std.ArrayList(bool) = .empty,
    annots: std.ArrayList(tags.AnnotRef) = .empty,
    parents: std.ArrayList(tags.StructParent) = .empty,
    next_page: u32 = 0,
    /// (chunk, render node) -> structure element (destinations of PDF/UA-2), `tags.nodeKey`
    node_elems: std.AutoHashMapUnmanaged(u64, Ref) = .empty,
    /// the structure tree, built a part of the document at a time (`endChunk`)
    builder: ?tags.Builder = null,
    /// the part of the document being drawn
    chunk: u32 = 0,
    /// the tagged annotations registered by `endChunk`, in the order `finishDocument` writes them
    /// (`annotCb` takes them in turn): their entry in `annots` and their /StructParent
    pre: std.ArrayList(PreAnnot) = .empty,
    pre_next: usize = 0,
    /// what the last part recorded for the part after it (`tags.Builder.add`)
    carry: std.ArrayList(tags.Carry) = .empty,
    tree_root: ?Ref = null,
    xmp: conform.XmpCtx,

    const PreAnnot = struct { idx: u32, sp: i32 };

    pub fn init(a: Allocator, cx: *sf.Ctx, cfg: conform.Config, o: *const opt.PdfOptions, tagged: bool, f: *const render.Frame, links: *interactive.Collector) TagDoc {
        return .{ .a = a, .cx = cx, .cfg = cfg, .report = .{ .a = a, .cfg = cfg }, .opts = o, .tagged = tagged, .collector = tags.Collector.init(a, f), .links = links, .xmp = .{ .cfg = cfg } };
    }

    /// The next output page is drawn, with `mcids` marked-content ids.
    pub fn addPage(t: *TagDoc, mcids: i32) Error!void {
        try t.mcids.append(t.a, mcids);
        try t.page_sp.append(t.a, null);
        try t.page_annots.append(t.a, false);
    }

    pub fn hook(t: *TagDoc) interactive.DocHook {
        return .{ .ctx = t, .annot = annotCb, .run = runCb, .tree = treeCb, .dest = destCb };
    }

    fn flushPages(t: *TagDoc, upto: u32) void {
        while (t.next_page < upto and t.next_page < t.mcids.items.len) : (t.next_page += 1) {
            const i = t.next_page;
            if (!t.tagged or t.mcids.items[i] == 0) continue;
            t.page_sp.items[i] = @intCast(t.parents.items.len);
            t.parents.append(t.a, .{ .page = .{ .index = i, .mcids = t.mcids.items[i] } }) catch {
                t.report.failed = true;
            };
        }
    }

    fn annotCb(ctx: *anyopaque, rec: interactive.AnnotRecord) interactive.AnnotExtra {
        const t: *TagDoc = @ptrCast(@alignCast(ctx));
        if (rec.page < t.page_annots.items.len) t.page_annots.items[rec.page] = true;
        if (!t.tagged or rec.repeated) {
            t.report.add(.missing_annotation_alt, 0);
            return .{};
        }
        // (registered with its part of the document: `endChunk`)
        if (t.pre_next >= t.pre.items.len) {
            t.report.failed = true;
            return .{};
        }
        const p = t.pre.items[t.pre_next];
        t.pre_next += 1;
        t.annots.items[p.idx].ref = rec.ref;
        return .{ .struct_parent = p.sp, .alt = rec.uri };
    }

    /// Starts a part of the document laid out in frame `f` (its pages are drawn next). False: what
    /// the part before recorded for it has no box in `f`.
    pub fn beginChunk(t: *TagDoc, f: *const render.Frame) Error!bool {
        t.collector.f = f;
        if (t.carry.items.len == 0) return true;
        const ok = try tags.takeCarry(&t.collector, t.carry.items);
        t.carry.clearRetainingCapacity();
        return ok;
    }

    /// The pages of a part of the document are drawn (output pages `first`..): registers their
    /// tagged annotations, in the order `interactive.finishDocument` writes them (a link the
    /// document does not write registers nothing: its anchors must be resolved), and adds the
    /// part's structure to the tree. Nothing refers to the part's frame afterwards.
    pub fn endChunk(t: *TagDoc, first: usize, scratch: Allocator, skip: ?tags.Skip) Error!bool {
        defer t.chunk += 1;
        if (!t.tagged) return true;
        const pages = t.links.pages.items;
        var pi = first;
        while (pi < pages.len) : (pi += 1) {
            for ([_][]const interactive.Link{ pages[pi].content.items, pages[pi].fixed.items }, 0..) |list, which| {
                for (list) |lk| {
                    if (which == 1 or lk.repeated) continue;
                    if (try t.links.linkTarget(scratch, lk) == null) continue;
                    t.flushPages(@intCast(pi));
                    const idx: u32 = @intCast(t.annots.items.len);
                    try t.annots.append(t.a, .{ .ref = 0, .page = @intCast(pi) });
                    const sp: i32 = @intCast(t.parents.items.len);
                    try t.parents.append(t.a, .{ .annot = idx });
                    try t.pre.append(t.a, .{ .idx = idx, .sp = sp });
                    t.collector.record(t.collector.owner(lk.node), .annotation, .{ .annot = idx });
                }
            }
        }
        if (t.collector.failed or t.report.failed) return error.OutOfMemory;
        // the render nodes of this part a destination names: anchors (elements with an `id`) and
        // headings
        var tg: std.AutoHashMapUnmanaged(u32, void) = .empty;
        var it = t.links.anchors.valueIterator();
        while (it.next()) |an| if (an.chunk == t.chunk) try tg.put(scratch, an.node, {});
        for (t.links.headings.items) |h| if (h.node != none and h.chunk == t.chunk) try tg.put(scratch, h.node, {});
        if (t.builder == null) t.builder = try tags.Builder.begin(t.a, if (t.opts.lang.len > 0) t.opts.lang else null);
        // (the part's tree is built in `scratch` and what it keeps copied to the document's memory)
        const saved = t.collector.a;
        t.collector.a = scratch;
        defer t.collector.a = saved;
        if (!try t.builder.?.add(&t.collector, &tg, t.chunk, skip, &t.carry, t.a)) return false;
        t.collector.records.clearRetainingCapacity();
        return true;
    }

    fn treeCb(ctx: *anyopaque, d: *w.Doc) Error!void {
        const t: *TagDoc = @ptrCast(@alignCast(ctx));
        t.flushPages(@intCast(t.mcids.items.len));
        if (!t.tagged) return;
        if (t.collector.failed or t.report.failed) return error.OutOfMemory;
        if (t.builder == null) t.builder = try tags.Builder.begin(t.a, if (t.opts.lang.len > 0) t.opts.lang else null);
        const root = t.builder.?.root;
        const wr = try tags.write(t.a, d, root, t.page_refs, t.annots.items, t.parents.items, &t.node_elems);
        t.tree_root = wr.root;
        if (wr.problems.missing_heading_title) t.report.add(.missing_heading_title, 0);
        if (wr.problems.missing_alt) t.report.add(.missing_alt_text, 0);
    }

    fn destCb(ctx: *anyopaque, chunk: u32, node: u32) ?Ref {
        const t: *TagDoc = @ptrCast(@alignCast(ctx));
        if (t.opts.tagged != .ua2 or node == none) return null;
        return t.node_elems.get(tags.nodeKey(chunk, node));
    }

    fn runCb(ctx: *anyopaque, d: *w.Doc, parts: *meta.Parts, records: []const interactive.AnnotRecord) Error!void {
        _ = records;
        const t: *TagDoc = @ptrCast(@alignCast(ctx));
        const c = t.cfg;
        if (t.tree_root) |r| {
            parts.catalog.struct_tree_root = r;
            parts.catalog.mark_info_suspects = !d.version.atLeast(.v2_0);
        } else t.report.add(.missing_tagging, 0);
        parts.info_dict = !c.prohibitsInfo();
        parts.history = c.archival();
        parts.validators = t.xmp.hook();
        parts.catalog.display_doc_title = c.displayDocTitle();
        parts.catalog.embedded_files_when_empty = c.embeddedFilesWhenEmpty();
        if (c.archival()) parts.catalog.output_intents = conform.outputIntents(t.cx);
        // krilla's metadata, outline and attachment checks
        const m: ?*const meta.Metadata = if (parts.metadata) |*md| md else null;
        if (m == null or m.?.title == null) t.report.add(.no_document_title, 0);
        if (m == null or m.?.language == null) t.report.add(.no_document_language, 0);
        if (m) |md| if (md.creation_date == null) t.report.add(.missing_document_date, 0);
        if (parts.catalog.outlines == null) t.report.add(.missing_document_outline, 0);
        const fallback: ?opt.PdfDate = if (t.opts.metadata) |mo| mo.creation_date else null;
        for (t.opts.attachments) |at| {
            t.report.add(.embedded_existence, 0);
            if (at.mime_type == null) t.report.add(.embedded_missing_mime, 0);
            if (at.modification_date == null and fallback == null) t.report.add(.embedded_missing_date, 0);
            if (at.description == null) t.report.add(.embedded_missing_description, 0);
        }
        if (t.cx.postscript) t.report.add(.contains_post_script, 0);
    }

    /// The page dictionary entries: /StructParents and /Tabs (krilla `InternalPage::serialize`).
    pub fn pageEntries(t: *const TagDoc, i: usize) struct { struct_parents: ?i32, tabs: ?[]const u8 } {
        const tabs = t.page_annots.items[i] or (t.tagged and t.cfg.tabsEveryPage());
        return .{ .struct_parents = t.page_sp.items[i], .tabs = if (tabs) "S" else null };
    }

    /// Records the font facts krilla's validators check (`cid.rs`, `content.rs`).
    pub fn fontIssues(t: *TagDoc, is: anytype) void {
        if (is.notdef_shown > 0) t.report.add(.contains_notdef, 0);
        // krilla dedupes by value: one error per distinct (font, glyph, character)
        for (is.list.items) |it| t.report.add(switch (it.kind) {
            .restricted_license => .restricted_license,
            .no_codepoint_mapping => .no_codepoint_mapping,
            .invalid_codepoint_mapping => .invalid_codepoint_mapping,
            .private_use => .private_use,
        }, it.key());
    }
};
