// More takumi-pdf golden fixtures (inputs only) for scripts/pdf-compare.mjs: the ones of
// tests/pdf_fixtures.rs that the main FIXTURES list, pdf-interchange.mjs and pdf-tagging-fixtures.mjs
// leave out. Each entry names the Rust test it is translated from. `jtext` / `jcolumn` are
// pdf_fixtures.rs `text(content, size)` / `column(children)`.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ref = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "ref", "takumi");
const asset = (f) => readFileSync(path.join(ref, "assets", "images", f));
const dataUrl = (mime, bytes) => `data:${mime};base64,${Buffer.from(bytes).toString("base64")}`;

const ARCHIVO = "assets/fonts/archivo/Archivo-VariableFont_wdth,wght.ttf";
const INTER = "assets/fonts/inter/inter-latin-opsz-wght-normal.woff2";
const A4 = { size: "a4" };
/** `PageOptions { width, height, margin: PageMargins::uniform(margin) }` */
const pg = (width, height, margin) => ({ size: { width, height }, margin });
const svgImage = (svg, width, height) => ({ type: "image", src: svg, width, height });
const pageSizedBoxes = (height) => `<div style="background: #e2e8f0; height: ${height}"></div>
       <div style="background: #cbd5e1; height: ${height}"></div>
       <div style="background: #94a3b8; height: ${height}"></div>`;
// pdf_fixtures.rs `stream_section` / `stream_document` / STREAM_PAGE
const streamSection = (id, title, lines) => `<div id="${id}" style="display: flex; flex-direction: column; break-before: page;"><h2 style="font-size: 18px; margin: 0;">${title}</h2>${Array.from({ length: lines }, (_, k) => `<div>${title}, line ${k + 1}</div>`).join("")}</div>`;
const streamDocument = (head, sections, tail) => `<div style="display: flex; flex-direction: column; width: 100%; font-size: 14px; color: #141414;">${head}${sections.map((s) => streamSection(...s)).join("")}${tail}</div>`;
const STREAM_PAGE = pg(320, 240, 24);
const filler = (n) => Array.from({ length: n }, (_, k) => `<p style="margin: 0">line ${k + 1}</p>`).join("");
const CLIP_TEXT = "Our new plan adds scheduled exports, row-level security and a redesigned mobile app.";

const SVG_SINGULAR = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <defs><linearGradient id="g" x1="0" y1="0" x2="8" y2="0" gradientUnits="userSpaceOnUse" gradientTransform="scale(0)" spreadMethod="repeat">
    <stop offset="0" stop-color="#ff0044"/><stop offset="1" stop-color="#0044ff"/>
  </linearGradient>
  <linearGradient id="h" x1="0" y1="0" x2="8" y2="0" gradientUnits="userSpaceOnUse" gradientTransform="matrix(1 1 0 0 0 0)" spreadMethod="repeat">
    <stop offset="0" stop-color="#ff0044"/><stop offset="1" stop-color="#0044ff"/>
  </linearGradient></defs>
  <rect width="24" height="12" fill="url(#g)"/>
  <rect y="12" width="24" height="12" fill="url(#h)"/>
</svg>`;
const SVG_FILTERS = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 24" width="48" height="24">
  <defs>
    <filter id="b"><feGaussianBlur stdDeviation="1"/></filter>
    <mask id="m" maskUnits="userSpaceOnUse" x="16" y="0" width="16" height="24">
      <rect x="16" y="0" width="16" height="24" fill="#888"/>
    </mask>
    <pattern id="p" width="4" height="4" patternUnits="userSpaceOnUse">
      <rect width="2" height="2" fill="#e33"/>
    </pattern>
  </defs>
  <circle cx="8" cy="12" r="6" fill="#3a3" filter="url(#b)"/>
  <rect x="18" y="4" width="12" height="16" fill="#33a" mask="url(#m)"/>
  <rect x="34" y="4" width="12" height="16" fill="url(#p)"/>
</svg>`;
const svgEmbeddedPng = () => { const u = dataUrl("image/png", asset("yeecord.png")); return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 48 24" width="48" height="24">
  <defs><clipPath id="c"><circle cx="12" cy="12" r="10"/></clipPath></defs>
  <image x="2" y="2" width="20" height="20" clip-path="url(#c)" xlink:href="${u}"/>
  <image x="26" y="2" width="20" height="20" transform="rotate(8 36 12)" opacity="0.6" xlink:href="${u}"/>
</svg>`; };
const svgColorFilter = () => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 24" width="48" height="24">
  <defs><linearGradient id="g" x1="0" y1="0" x2="24" y2="0" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#ff0044"/><stop offset="1" stop-color="#0044ff"/>
  </linearGradient></defs>
  <rect width="24" height="24" fill="url(#g)"/>
  <rect x="26" width="10" height="10" fill="#e11d48"/>
  <image x="38" y="0" width="10" height="10" href="${dataUrl("image/png", asset("yeecord.png"))}"/>
</svg>`;

export function moreFixtures({ jtext, jcolumn }) {
  const checker = (dark, light) => {
    const px = [];
    for (let r = 0; r < 8; r++) for (let c = 0; c < 8; c++) px.push(...(((r >> 1) + (c >> 1)) % 2 === 0 ? dark : light));
    return { type: "image", src: { data: new Uint8Array(px), width: 8, height: 8 }, width: 120, height: 120 };
  };
  return [
    // media_print_applies_to_pdf_output
    { name: "media-print", page: { viewport: { width: 600, height: 300 }, css: `@media print { .card { background-color: rgb(20, 120, 60); } }` },
      node: () => ({ type: "container", className: "card", style: { display: "flex", width: "100%", height: "100%" }, children: [jtext("Hello print", 32)] }) },
    // inline_span_background_image
    { name: "inline-span-background-image", vp: [420, 200], html: `<div style="width: 100%; height: 100%; padding: 12px; background-color: #ffffff; font-size: 18px; line-height: 1.6; color: #141414">
      <div style="width: 220px">Ship <span style="padding: 0 6px; background-image: linear-gradient(90deg, #facc15, #ec4899)">a sliced gradient across lines</span> today</div>
      <div style="font-size: 32px; font-weight: 700">Make it <span style="background-image: linear-gradient(90deg, #6366f1, #ec4899); background-clip: text; color: transparent">shine</span></div>
    </div>` },
    // inline_span_background_clip_text_nested
    { name: "inline-span-background-clip-text-nested", vp: [420, 140], html: `<div style="width: 100%; height: 100%; padding: 12px; background-color: #ffffff; font-size: 32px; font-weight: 700; color: #141414">
      <div><span style="background-image: linear-gradient(90deg, #2563eb, #db2777); background-clip: text; color: transparent">Base <span style="background-image: linear-gradient(180deg, transparent 50%, #facc15 50%); background-clip: text">over</span> <span style="background-clip: text">bare</span></span></div>
      <div><span style="background-image: linear-gradient(90deg, #16a34a, #0891b2); background-clip: text; color: transparent">Clip <span style="background-color: #fee2e2">boxed</span></span></div>
    </div>` },
    // inline_span_background_clip_text_decoration
    { name: "inline-span-background-clip-text-decoration", vp: [420, 200], html: `<div style="width: 100%; height: 100%; padding: 12px; background-color: #ffffff; font-size: 32px; font-weight: 700; line-height: 1.5">
      <div><span style="background-image: linear-gradient(90deg, #2563eb, #db2777); background-clip: text; color: transparent; text-decoration: underline 4px">Underlined</span></div>
      <div><span style="background-image: linear-gradient(90deg, #16a34a, #0891b2); background-clip: text; color: transparent; text-decoration: line-through wavy 3px">Wavy strike</span></div>
      <div><span style="background-image: linear-gradient(90deg, #ea580c, #9333ea); background-clip: text; color: transparent; -webkit-text-stroke: 4px transparent">Stroked</span></div>
    </div>` },
    // background_clip_text_descendants
    { name: "background-clip-text-descendants", vp: [420, 200], html: `<div style="width: 100%; height: 100%; padding: 12px; background-color: #ffffff; font-size: 28px; font-weight: 700; line-height: 1.4">
      <div style="background-image: linear-gradient(90deg, #2563eb, #db2777); background-clip: text; color: transparent; text-shadow: 2px 2px 0 rgba(15, 23, 42, 0.35)">
        <div>Nested block</div>
        <div><span style="display: inline-block; padding: 0 6px">Inline block</span> <span style="text-decoration: underline 3px">line</span></div>
        <div style="background-color: #fee2e2">Own background</div>
      </div>
    </div>` },
    // background_clip_text_reach
    { name: "background-clip-text-reach", vp: [420, 200], html: `<div style="width: 100%; height: 100%; padding: 12px; background-color: #ffffff; font-size: 28px; font-weight: 700; line-height: 1.4">
      <div style="background-image: linear-gradient(90deg, #2563eb, #db2777); background-clip: text; color: transparent">
        <div style="float: right">Float</div>
        <div style="float: right; opacity: 0.5">Layered</div>
        <div style="opacity: 0">Zero opacity</div>
        <div style="transform: scale(0)">Scale zero</div>
        <div style="position: absolute; left: 240px; top: 60px">Outside</div>
      </div>
    </div>` },
    // inline_span_box_decoration_break_clone
    { name: "inline-span-box-decoration-break-clone", vp: [320, 160], html: `<div style="width: 100%; height: 100%; padding: 12px; background-color: #ffffff; font-size: 18px; line-height: 2; color: #141414">
      <div style="width: 220px">Ship <span style="padding: 2px 10px; border: 3px solid #2563eb; border-radius: 8px; background-color: #dbeafe; box-decoration-break: clone">a cloned badge that wraps across lines</span> today</div>
    </div>` },
    // sided_and_page_avoiding_breaks_split_the_page
    { name: "sided-avoid-page-breaks", page: pg(300, 160, 20), html: `<div style="font-size: 12px; color: #141414">
        <div>first page</div>
        <div style="break-before: recto">${filler(8)}</div>
        <div style="break-inside: avoid-page; background: #e2e8f0; padding: 8px">
          <p style="margin: 0">kept together</p>
          <p style="margin: 0">across the break</p>
          <p style="margin: 0">by avoid-page</p>
        </div>
      </div>` },
    // an_absolute_box_past_the_page_leaves_an_avoiding_box_in_place
    { name: "avoid-break-out-of-flow-overflow", page: pg(300, 160, 20), html: `<div style="font-size: 12px; color: #141414">
        ${filler(5)}
        <div style="position: relative; break-inside: avoid; background: #e2e8f0; padding: 8px">
          kept on the first page
          <div style="position: absolute; left: 0; bottom: -40px; color: #b91c1c">badge</div>
        </div>
      </div>` },
    // an_img_without_a_source_moves_to_the_next_page_whole
    { name: "img-without-source-past-page", page: pg(300, 160, 10), html: `<div style="font-size: 12px; color: #141414">
      <div style="height: 60px">before the image</div>
      <img width="120" height="110" style="display: block; background: #93c5fd">
      <div>after the image</div>
    </div>` },
    // a_flex_row_whose_item_margin_runs_past_the_page_moves_to_the_next
    { name: "flex-item-margin-past-page", page: pg(300, 160, 10), html: `<div style="font-size: 12px; color: #141414">
      <div style="height: 40px">before the row</div>
      <div style="display: flex; gap: 8px; background: #e2e8f0">
        <div style="height: 80px; margin-bottom: 30px; background: #93c5fd">item</div>
        <div style="height: 50px; background: #fca5a5">short item</div>
      </div>
    </div>` },
    // a_forced_break_after_a_flex_items_last_child_breaks_after_the_container
    { name: "flex-item-child-break-after", page: pg(300, 160, 10), html: `<div style="font-size: 12px; color: #141414">
      <div style="display: flex; gap: 8px">
        <div style="background: #e2e8f0">
          <div>first item</div>
          <div style="break-after: page">ends with a forced break</div>
        </div>
        <div style="background: #fde68a">second item</div>
      </div>
      <div>after the row, on the next page</div>
    </div>` },
    // a_forced_break_after_a_table_row_in_a_flex_item_breaks_after_the_container
    { name: "flex-item-table-row-break-after", page: pg(300, 160, 10), html: `<div style="font-size: 12px; color: #141414">
      <div style="display: flex">
        <table style="border-collapse: collapse">
          <tr><td style="background: #e2e8f0">first row</td></tr>
          <tr style="break-after: page"><td style="background: #fde68a">last row</td></tr>
        </table>
      </div>
      <div>after the table, on the next page</div>
    </div>` },
    // a_floated_flex_item_breaks_after_as_any_other_item
    { name: "floated-flex-item-break-after", page: pg(300, 160, 10), html: `<div style="font-size: 12px; color: #141414">
      <div style="display: flex; flex-direction: column; background: #e2e8f0">
        <div style="float: left; width: 120px; background: #93c5fd; break-after: page">floated item</div>
        <div style="background: #fde68a">next item, on the next page</div>
      </div>
    </div>` },
    // a_forced_break_after_a_box_whose_absolute_child_runs_on_applies_once
    { name: "break-after-with-running-absolute", page: pg(300, 160, 10), html: `<div style="font-size: 12px; color: #141414">
      <div style="height: 80px">before the box</div>
      <div style="position: relative; break-after: page; background: #e2e8f0">
        the box
        <div style="position: absolute; top: 110px; background: #fca5a5">absolute, next page</div>
      </div>
      <div style="float: left; background: #93c5fd">float after the box, next page</div>
    </div>` },
    // a_page_skips_the_clips_of_other_pages
    { name: "paged-offpage-clips", page: pg(400, 300, 20), html: `<div style="overflow:hidden;height:40px;margin-bottom:10px;break-inside:avoid;border:1px solid #888"><div style="opacity:0.5">clipped</div></div>`.repeat(12) },
    // a_forced_break_in_a_nested_flex_row_moves_the_row
    { name: "paged-nested-flex-forced-break", page: A4, html: `<div style="display: flex; flex-wrap: wrap; font-size: 18px;">
        <div style="display: flex; flex-wrap: wrap; width: 100%;">
          <div style="width: 50%;">One</div><div style="width: 50%;">Two</div>
        </div>
        <div style="display: flex; flex-wrap: wrap; width: 100%;">
          <div style="width: 50%; break-before: page;">Three</div><div style="width: 50%;">Four</div>
        </div>
      </div>` },
    // svg_singular_gradient_transform
    { name: "svg-singular-gradient-transform", vp: [60, 60], node: () => ({ type: "container", children: [svgImage(SVG_SINGULAR, 22, 22)] }) },
    // svg_filters_masks_and_patterns
    { name: "svg-filters-masks-and-patterns", vp: [120, 60], node: () => ({ type: "container", style: { display: "flex", paddingTop: 8 }, children: [svgImage(SVG_FILTERS, 48, 24)] }) },
    // svg_embedded_png
    { name: "svg-embedded-png", vp: [120, 60], node: () => ({ type: "container", children: [svgImage(svgEmbeddedPng(), 96, 48)] }) },
    // svg_with_color_filter
    { name: "svg-with-color-filter", vp: [120, 70], html: () => `<div style="padding: 8px;"><img src="${dataUrl("image/svg+xml", Buffer.from(svgColorFilter()))}" style="width: 96px; height: 48px; filter: grayscale(1);"></div>` },
    // inline_outlines
    { name: "inline-outlines", vp: [360, 200], html: `<div style="width: 100%; height: 100%; padding: 24px; background-color: #ffffff; font-size: 20px; line-height: 1.6; color: #111827;">
      Plain words, then <span style="outline: 2px solid #0e7490; outline-offset: 2px;">an outlined phrase that wraps onto the next line</span> and <span style="outline: 3px dashed #be123c; opacity: 0.5;">a faded one</span>.
    </div>` },
    // inline_zero_sized_parents
    { name: "inline-zero-sized-parents", vp: [360, 160], html: `<div style="width: 100%; height: 100%; padding: 24px; background-color: #ffffff; color: #111827;">
      <div style="font-size: 0;"><span style="font-size: 24px;">Sized</span> <span style="font-size: 24px; color: #be123c;">spans</span></div>
      <div style="height: 0; font-size: 20px;">Overflowing text</div>
      <div style="font-size: 20px; margin-top: 32px;">Before <span style="display: inline-block; height: 0;">inside</span> after</div>
    </div>` },
    // background_clip_border_area_gaps
    { name: "background-clip-border-area-gaps", vp: [400, 160], html: `<div style="display: flex; gap: 24px; width: 100%; height: 100%; padding: 24px; background-color: #ffffff;">
      <div style="width: 80px; height: 80px; border: 10px dashed transparent; background-clip: border-area; background-image: linear-gradient(135deg, #2563eb, #dc2626);"></div>
      <div style="width: 80px; height: 80px; border: 10px dotted transparent; border-radius: 16px; background-clip: border-area; background-color: #16a34a;"></div>
      <div style="width: 80px; height: 80px; border: 10px double transparent; background-clip: border-area; background-color: #ea580c;"></div>
    </div>` },
    // paged_clone_decorations
    { name: "paged-clone-decorations", page: pg(360, 260, 20), html: `<div style="display: flex; flex-direction: column; width: 100%; padding: 14px; row-gap: 4px; border: 3px solid #1c1917; border-radius: 14px; box-decoration-break: clone; background-color: #fafaf9;">
        ${Array.from({ length: 24 }, (_, k) => `<div style="font-size: 13px; color: #1c1917;">Clause ${k + 1} of the agreement</div>`).join("")}
        <div style="display: flex; flex-direction: column; row-gap: 4px; padding: 10px; background-color: #e7e5e4; break-inside: avoid;">
          <div style="font-size: 13px;">Kept-together block line one</div>
          <div style="font-size: 13px;">Kept-together block line two</div>
          <div style="font-size: 13px;">Kept-together block line three</div>
        </div>
      </div>` },
    // paged_transforms
    { name: "paged-transforms", page: pg(400, 300, 24), html: `<div style="display: flex; flex-direction: column; width: 100%; row-gap: 10px;">
      <div style="height: 150px; background-color: #dbeafe;"></div>
      <div style="width: 100%; height: 10px; transform: skewY(4deg); background-color: #111111;"></div>
      <div style="width: 220px; height: 90px; transform: rotate(8deg); background-color: #fecaca; border: 2px solid #b91c1c;"></div>
      <div style="height: 140px; background-color: #dcfce7;"></div>
      <div style="width: 200px; height: 70px; transform: scale(1.2) translate(20px, 0px); background-color: #fde68a;"></div>
      <div style="height: 150px; background-color: #f3e8ff;"></div>
    </div>` },
    // paged_overflow_clip_spans_the_stitched_box
    { name: "paged-overflow-clip-stitched", page: pg(200, 100, 0), html: `<div style="height: 200px; overflow: hidden; position: relative">
      <div style="position: absolute; width: 200px; height: 120px; background-color: #ffee00; transform: translate(0px, 50px)"></div>
    </div>` },
    // paged_rounded_clip_waits_for_the_whole_box
    { name: "paged-rounded-clip-stitched", page: pg(200, 100, 0), html: `<div style="height: 400px; overflow: hidden; border-radius: 50%">
      <div style="height: 400px; background-color: #ffee00"></div>
    </div>` },
    // content_moved_past_the_last_page_adds_pages
    { name: "paged-transform-past-the-last-page", page: pg(300, 100, 0), html: `<div style="height: 60px; background: #ddd"></div><div style="height: 30px; background: #f87171; transform: translateY(120px)"></div>` },
    // paged_monolithic_overflow
    { name: "paged-monolithic-overflow", page: pg(400, 300, 24), html: `<div style="font-size: 16px; line-height: 24px; color: #141414">
      <div>Line 1 before the tall line</div>
      <div>Line 2 before the tall line</div>
      <div>Line 3 before the tall line</div>
      <div><span style="display: inline-block; width: 120px; height: 360px; background-image: linear-gradient(#2563eb, #db2777)"></span> tall line text</div>
      <div>Line A after the tall line</div>
      <div>Line B after the tall line</div>
    </div>` },
    // paged_clipped_overflow
    { name: "paged-clipped-overflow", page: pg(200, 100, 0), html: `<div>
      <div style="width: 200px; height: 100px; overflow: hidden; background: #eee">
        <div style="height: 50px; background: red"></div>
      </div>
      <div style="width: 200px; height: 100px; overflow: hidden; background: #eee">
        <div style="height: 400px; background: red"></div>
      </div>
    </div>` },
    // paged_images
    { name: "paged-images", page: pg(300, 260, 20), node: () => jcolumn([jtext("Before the images", 14), checker([220, 60, 60, 255], [255, 235, 235, 255]), checker([60, 60, 220, 255], [235, 235, 255, 255]), checker([60, 180, 90, 255], [230, 250, 235, 255]), jtext("After the images", 14)]) },
    // list_marker_pagination
    { name: "list-marker-pagination", page: { ...pg(240, 75, 0), tagged: false }, html: `<ol style="font-size:16px;line-height:20px;margin:0;">
    <li>one<br>two<br>three<br>four<br>five<br>six<br>seven<br>eight</li>
  </ol>` },
    // outline_over_content
    { name: "outline-over-content", page: A4, html: `<main style="display:flex;font-size:40px;color:#141414;"><div style="display:block;outline:8px solid #ff0000;outline-offset:-8px;background-color:#ffffff;">TEXT</div></main>` },
    // outline_under_transform
    { name: "outline-under-transform", page: A4, html: `<main style="display:flex;font-size:30px;color:#141414;"><div style="display:block;transform:rotate(20deg);outline:6px solid #ff0000;">TEXT</div></main>` },
    // inline_containers
    { name: "inline-containers", page: A4, html: `<main style="display:flex;flex-direction:column;font-size:20px;color:#141414;">
    <div style="display:block">before <span style="display:inline-block;background-color:#ff0000;">block</span> after</div>
    <div style="display:block">before <span style="display:inline-flex;background-color:#00ff00;"><span>fl</span><span>ex</span></span> after</div>
    <div style="display:block">before <span style="display:inline-block;background-color:#0000ff;"><span style="display:inline-block;background-color:#ffff00;">nested</span></span> after</div>
    <div style="display:block"><span style="float:left;width:30px;height:30px;background-color:#ff00ff;"></span>floated</div>
  </main>` },
    // font_variation_settings (latin_font(): Archivo alone)
    { name: "font-variation-settings", fonts: [ARCHIVO], page: A4, html: `<main style="display:flex;flex-direction:column;font-family:Archivo;font-size:32px;color:#141414;">
      <p>Default instance</p>
      <p style="font-variation-settings:'wght' 900;">Black through settings</p>
      <p style="font-variation-settings:'wdth' 62;">Condensed through settings</p>
    </main>` },
    // font_optical_sizing (Inter alone)
    { name: "font-optical-sizing", fonts: [INTER], page: A4, html: `<main style="display:flex;flex-direction:column;font-family:Inter;color:#141414;">
      <p style="font-size:14px;">Text size</p>
      <p style="font-size:72px;">Display size</p>
      <p style="font-size:72px;font-optical-sizing:none;">Text cut</p>
    </main>` },
    // a_box_as_tall_as_the_window_fills_exactly_one_page
    { name: "page-sized-boxes", page: { size: "a4", margin: 0 }, html: pageSizedBoxes("297mm") },
    // viewport_units_in_paged_content_take_the_page_area
    { name: "page-area-viewport-units", page: { size: "a4", margin: 0 }, html: pageSizedBoxes("100vh") },
    // stream_transform_paints_three_pages_back
    { name: "stream-transform-three-pages-back", page: STREAM_PAGE, html: streamDocument("", [["a", "Alpha", 3], ["b", "Beta", 3], ["c", "Gamma", 3], ["d", "Delta", 3]], "")
      .replace("Delta, line 3</div>", `Delta, line 3</div><div style="width: 120px; height: 30px; background-color: rgb(200, 40, 40); transform: translateY(-576px);"></div>`) },
    // stream_relative_body_with_bottom_child
    { name: "stream-relative-body-bottom", page: STREAM_PAGE, html: `<div style="position: relative; display: flex; flex-direction: column; width: 100%; font-size: 14px; color: #141414;">${Array.from({ length: 40 }, (_, k) => `<div>Line ${k + 1}</div>`).join("")}<div style="position: absolute; bottom: 0; left: 0; height: 24px; width: 160px; background-color: rgb(40, 120, 200);">Watermark</div></div>` },
    // paged_lines_under_a_transform_or_a_clip
    { name: "paged-rotated-text", page: pg(400, 200, 0), html: `<div style="height: 200px">Q3 results</div><div style="height: 200px; break-before: page"><div style="transform: rotate(-15deg)">Draft</div></div>` },
    { name: "paged-clipped-line", page: pg(300, 100, 0), html: `<div style="width: 240px; height: 60px; overflow: hidden; line-height: 24px">${CLIP_TEXT}</div>` },
    { name: "paged-clipped-line-at-page-edge", page: pg(300, 100, 0), html: `<html><body style="margin: 0; height: 100px; overflow: hidden"><div style="width: 240px; padding-top: 88px; line-height: 24px">${CLIP_TEXT}</div></body></html>` },
    { name: "paged-translated-text-past-the-end", page: pg(300, 100, 0), html: `<div style="line-height: 24px; transform: translateY(88px)">Total due</div>` },
    { name: "paged-translated-text-across-pages", page: pg(300, 100, 0), html: `<div style="height: 200px"><div style="line-height: 24px; transform: translateY(88px)">Total due</div></div>` },
  ];
}
