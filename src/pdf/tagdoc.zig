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
    /// marked-content ids per page, and the page's /StructParents
    mcids: []i32,
    page_sp: []?i32,
    /// per page: some annotation (tagged or not) is on it
    page_annots: []bool,
    annots: std.ArrayList(tags.AnnotRef) = .empty,
    parents: std.ArrayList(tags.StructParent) = .empty,
    next_page: u32 = 0,
    /// render node -> structure element (destinations of PDF/UA-2)
    node_elems: std.AutoHashMapUnmanaged(u32, Ref) = .empty,
    tree_root: ?Ref = null,
    xmp: conform.XmpCtx,

    pub fn init(a: Allocator, cx: *sf.Ctx, cfg: conform.Config, o: *const opt.PdfOptions, tagged: bool, f: *const render.Frame, links: *interactive.Collector, pages: usize) Error!TagDoc {
        const sp = try a.alloc(?i32, pages);
        @memset(sp, null);
        const pa = try a.alloc(bool, pages);
        @memset(pa, false);
        const mc = try a.alloc(i32, pages);
        @memset(mc, 0);
        return .{ .a = a, .cx = cx, .cfg = cfg, .report = .{ .a = a, .cfg = cfg }, .opts = o, .tagged = tagged, .collector = tags.Collector.init(a, f), .links = links, .mcids = mc, .page_sp = sp, .page_annots = pa, .xmp = .{ .cfg = cfg } };
    }

    pub fn hook(t: *TagDoc) interactive.DocHook {
        return .{ .ctx = t, .annot = annotCb, .run = runCb, .tree = treeCb, .dest = destCb };
    }

    fn flushPages(t: *TagDoc, upto: u32) void {
        while (t.next_page < upto and t.next_page < t.mcids.len) : (t.next_page += 1) {
            const i = t.next_page;
            if (!t.tagged or t.mcids[i] == 0) continue;
            t.page_sp[i] = @intCast(t.parents.items.len);
            t.parents.append(t.a, .{ .page = .{ .index = i, .mcids = t.mcids[i] } }) catch {
                t.report.failed = true;
            };
        }
    }

    fn annotCb(ctx: *anyopaque, rec: interactive.AnnotRecord) interactive.AnnotExtra {
        const t: *TagDoc = @ptrCast(@alignCast(ctx));
        if (rec.page < t.page_annots.len) t.page_annots[rec.page] = true;
        if (!t.tagged or rec.repeated) {
            t.report.add(.missing_annotation_alt, 0);
            return .{};
        }
        t.flushPages(rec.page);
        const idx: u32 = @intCast(t.annots.items.len);
        t.annots.append(t.a, .{ .ref = rec.ref, .page = rec.page }) catch {
            t.report.failed = true;
            return .{};
        };
        const sp: i32 = @intCast(t.parents.items.len);
        t.parents.append(t.a, .{ .annot = idx }) catch {
            t.report.failed = true;
        };
        t.collector.record(t.collector.owner(rec.node), .annotation, .{ .annot = idx });
        return .{ .struct_parent = sp, .alt = rec.uri };
    }

    /// The render nodes a destination names: anchors (elements with an `id`) and headings.
    fn targets(t: *TagDoc) Error!std.AutoHashMapUnmanaged(u32, void) {
        var set: std.AutoHashMapUnmanaged(u32, void) = .empty;
        var it = t.links.anchors.valueIterator();
        while (it.next()) |an| try set.put(t.a, an.node, {});
        for (t.links.headings.items) |h| if (h.node != none) try set.put(t.a, h.node, {});
        return set;
    }

    fn treeCb(ctx: *anyopaque, d: *w.Doc) Error!void {
        const t: *TagDoc = @ptrCast(@alignCast(ctx));
        t.flushPages(@intCast(t.mcids.len));
        if (!t.tagged) return;
        if (t.collector.failed or t.report.failed) return error.OutOfMemory;
        const tg = try t.targets();
        const lang: ?[]const u8 = if (t.opts.lang.len > 0) t.opts.lang else null;
        const root = try tags.build(&t.collector, lang, &tg);
        const wr = try tags.write(t.a, d, root, t.page_refs, t.annots.items, t.parents.items, &t.node_elems);
        t.tree_root = wr.root;
        if (wr.problems.missing_heading_title) t.report.add(.missing_heading_title, 0);
        if (wr.problems.missing_alt) t.report.add(.missing_alt_text, 0);
    }

    fn destCb(ctx: *anyopaque, node: u32) ?Ref {
        const t: *TagDoc = @ptrCast(@alignCast(ctx));
        if (t.opts.tagged != .ua2 or node == none) return null;
        return t.node_elems.get(node);
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
        const tabs = t.tagged and (t.page_annots[i] or t.cfg.tabsEveryPage());
        return .{ .struct_parents = t.page_sp[i], .tabs = if (tabs) "S" else null };
    }

    /// Records the font facts krilla's validators check (`cid.rs`, `content.rs`).
    pub fn fontIssues(t: *TagDoc, is: anytype) void {
        if (is.restricted_license) t.report.add(.restricted_license, std.hash.Wyhash.hash(0, is.restricted_font));
        if (is.notdef_shown > 0) t.report.add(.contains_notdef, 0);
        if (is.no_codepoint_mapping > 0) t.report.add(.no_codepoint_mapping, 0);
        if (is.invalid_codepoint_mapping > 0) t.report.add(.invalid_codepoint_mapping, 0);
        if (is.private_use > 0) t.report.add(.private_use, 0);
    }
};
