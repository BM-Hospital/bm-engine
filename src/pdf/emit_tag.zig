//! The emitter's marked-content calls (takumi-pdf `emitter.rs`: `emit_tagged_content`,
//! `start_node_region`, `content_tag`, `in_artifact`; `window.rs` / `bands.rs` artifacts). Every
//! function is a no-op on an untagged walk (`Emitter.tags` null or `Emitter.tagged` false), and the
//! surface writes nothing unless it is a tagged page (emit_surface.zig `startTagged`).
const std = @import("std");
const render = @import("../render.zig");
const sf = @import("emit_surface.zig");
const tags = @import("tags.zig");

const none = render.none;

/// The language a node's content is in: the nearest `lang` attribute, else the document's.
fn langOf(e: anytype, id: u32) []const u8 {
    const f = e.f;
    var nid = id;
    var guard: u32 = 0;
    while (nid != none and guard < 1024) : (guard += 1) {
        const n = &f.nodes.items[nid];
        if (n.el != none and n.kind != .anon_text and n.kind != .anon_box) {
            var el = n.el;
            var g2: u32 = 0;
            while (el != none and g2 < 1024) : (g2 += 1) {
                const x = f.dom.at(el);
                if (x.lang.len > 0) return x.lang;
                el = x.parent;
            }
            return e.doc_lang;
        }
        nid = n.parent;
    }
    return e.doc_lang;
}

/// takumi `content_tag`: a `Span` with the language when it differs from the document's.
fn contentTag(e: anytype, id: u32) sf.ContentTag {
    const lang = langOf(e, id);
    if (lang.len > 0 and !std.mem.eql(u8, lang, e.doc_lang)) return .{ .span = lang };
    return .other;
}

/// Opens the region node `id`'s own content (text or image) draws in (takumi
/// `emit_tagged_content` / `start_node_region`): an artifact for a decorative image or a repeated
/// fragment, otherwise a content sequence recorded against the node. Returns whether a section
/// was opened (pass it to `end`).
pub fn begin(e: anytype, id: u32) bool {
    if (!e.tagged) return false;
    const c = e.tags orelse return false;
    if (e.in_repeat or tags.decorativeImage(e.f, id)) {
        e.s.startArtifact();
        return true;
    }
    const owner = c.owner(id);
    if (e.s.startTagged(contentTag(e, owner))) |mcid| {
        c.record(owner, .content, .{ .mcid = .{ .page = e.page_index, .mcid = mcid } });
    }
    return true;
}

pub fn end(e: anytype, began: bool) void {
    if (began) e.s.endTagged();
}

/// Records an empty content sequence of `owner` (takumi reopens the owner's region after each
/// inline replaced box it hands its region to).
pub fn reopen(e: anytype, owner: u32) void {
    if (!e.tagged or e.in_repeat) return;
    const began = begin(e, owner);
    end(e, began);
}

/// `/Artifact BMC` around a window drawn untagged (bands, repeated fixed boxes) when the document
/// is tagged.
pub fn startWindow(e: anytype) void {
    if (e.tags != null) e.s.startArtifact();
}

pub fn endWindow(e: anytype) void {
    if (e.tags != null) e.s.endArtifact();
}
