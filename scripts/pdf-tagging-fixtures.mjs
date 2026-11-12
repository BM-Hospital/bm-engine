// The tagging / PDF/A / PDF/UA fixtures of takumi-pdf's tests/pdf_fixtures.rs (inputs only), for
// scripts/pdf-compare.mjs. `png(rgba, w, h)` encodes the 4 x 4 grey pixel the fixtures register.

const A4 = { size: "a4" };
const INVOICE_PAGE = { size: "a4", margin: { top: 36, right: 36, bottom: "auto", left: 36 }, footerFile: "invoice-footer.html" };
const date = (day) => `2026-08-${String(day).padStart(2, "0")}`;
const FACTUR_X = { name: "Factur-X PDF/A Extension", prefix: "fx", namespace: "urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#", properties: [{ name: "DocumentFileName", value: "factur-x.xml", description: "name of the embedded XML invoice file" }] };
const ATTACHMENT = { name: "factur-x.xml", data: `<invoice total="1290"/>`, mimeType: "application/xml", description: "Factur-X invoice data", relationship: "alternative" };

const FONT_FORMATS = ["assets/fonts/archivo/Archivo-VariableFont_wdth,wght.ttf", "assets/fonts/cjk-locl-test/CJKLoclTest.woff2", "assets/fonts/ubuntu/Ubuntu.ttc",
  "assets/fonts/twemoji/TwemojiMozilla-colr.woff2", "assets/fonts/sil/scheherazade-new-v17-arabic-regular.woff2", "assets/fonts/noto-sans/noto-sans-devanagari-v30-devanagari-regular.woff2"];
const fontFormatsDoc = ([base, cff, collection, colr, arabic, devanagari]) => `<main style="display:flex;flex-direction:column;font-family:${base};font-size:16px;color:#141414;">
      <h1>Font formats</h1>
      <p lang="zh" style="font-family:${cff};">直 骨 今 海 真 令 説 器</p>
      <p style="font-family:${collection};">A face out of a TrueType collection</p>
      <p style="font-family:${colr};">Colour glyphs 🎉 🚀</p>
      <p lang="ar" style="font-family:${arabic};">نص عربي للتشكيل</p>
      <p lang="hi" style="font-family:${devanagari};">संयुक्ताक्षर क्षत्र</p>
    </main>`;

const REPORT_META = { title: "Annual report", creationDate: date(6) };
const LIST_DOC = `<main style="display:flex;flex-direction:column;font-size:14px;color:#141414;">
    <h1>Checklist</h1>
    <p>Steps with <strong>bold</strong> and <code>code</code>:</p>
    <ul><li>First item</li><li>Second item</li></ul>
    <ol><li>Ordered one</li><li>Ordered two</li></ol>
    <ol style="list-style-type:upper-roman"><li>Roman one</li></ol>
  </main>`;

export function taggingFixtures({ png }) {
  const pixel = () => [{ src: "pixel", data: png(new Uint8Array(4 * 4 * 4).fill(128), 4, 4) }];
  return [
    ...[["2b", "ua1"], ["2u", "ua1"], ["2a", "ua1"], ["3b", "ua1"], ["3u", "ua1"], ["3a", "ua1"], ["4", true]].map(([level, tagged]) => ({
      name: `font-formats-pdfa-${level}`, fonts: FONT_FORMATS, page: { ...A4, pdfa: level, tagged, lang: "en", metadata: { title: "Font formats", creationDate: date(7) } }, html: fontFormatsDoc })),
    { name: "invoice-pdfa-2b", page: { ...INVOICE_PAGE, pdfa: "2b" }, htmlFile: "invoice.html" },
    { name: "invoice-pdfa-4", page: { ...INVOICE_PAGE, pdfa: "4" }, htmlFile: "invoice.html" },
    { name: "invoice-pdfa-4f-attachment", page: { ...INVOICE_PAGE, pdfa: "4f", metadata: { title: "Invoice", creationDate: date(6), xmp: [FACTUR_X] }, attachments: [ATTACHMENT] }, htmlFile: "invoice.html" },
    { name: "report-tagged-ua1", page: { ...A4, tagged: "ua1", pdfa: "2a", lang: "en", metadata: REPORT_META }, htmlFile: "report.html" },
    { name: "report-tagged-a2a", page: { ...A4, pdfa: "2a", lang: "en", metadata: REPORT_META }, htmlFile: "report.html" },
    { name: "list-tagged-ua1", page: { ...A4, tagged: "ua1", lang: "en", metadata: REPORT_META }, html: LIST_DOC },
    { name: "inline-block-tagged", page: { ...A4, tagged: "ua1", lang: "en", metadata: { title: "Report" } }, html: `<main style="display:flex;flex-direction:column;font-size:14px;color:#141414;">
    <h1>Report</h1>
    <div>Before <span style="display:inline-block;width:160px;"><span style="display:inline-block;"><h2>Inner heading</h2></span></span> after</div>
  </main>` },
    { name: "structure-types-a4", images: pixel, page: { ...A4, pdfa: "4", lang: "en", metadata: { title: "Structure types", creationDate: date(8) } }, html: `<main style="display:flex;flex-direction:column;font-size:14px;color:#141414;">
    <h1 id="top">Structure types</h1>
    <section>
      <h2>Prose</h2>
      <p>A paragraph with <strong>bold</strong>, <em>italic</em> and <code>code</code>.</p>
      <blockquote>A quotation on its own.</blockquote>
    </section>
    <article>
      <h3>Lists</h3>
      <ul><li>Unordered one</li><li>Unordered two</li></ul>
      <ol><li>Ordered one</li><li>Ordered two</li></ol>
    </article>
    <figure>
      <img src="pixel" alt="a grey square" style="width:40px;height:40px;" />
      <figcaption>A described pixel.</figcaption>
    </figure>
    <p><a href="#top">Back to the top</a> and <a href="https://example.com">out to the web</a>.</p>
  </main>` },
    { name: "table-tagged-ua2", page: { ...A4, pdfa: "4", tagged: "ua2", lang: "en", metadata: { title: "Quarterly totals", creationDate: date(30) } }, html: `<div style="width:700px;font-size:14px;color:#141414">
    <h1>Quarterly totals</h1>
    <table>
      <caption>Quarterly totals</caption>
      <thead><tr><th>Region</th><th>Q1</th><th>Q2</th></tr></thead>
      <tbody>
        <tr><th scope="row">North</th><td>10</td><td>20</td></tr>
        <tr><th scope="row" rowspan="2">South</th><td>30</td><td>40</td></tr>
        <tr><td colspan="2">subtotal</td></tr>
      </tbody>
      <tfoot><tr><td>Total</td><td>40</td><td>60</td></tr></tfoot>
    </table>
  </div>` },
    { name: "report-tagged-ua2", images: pixel, page: { ...A4, pdfa: "4", tagged: "ua2", lang: "en", metadata: { title: "Accessible report", creationDate: date(8) } }, html: `<main style="display:flex;flex-direction:column;font-size:14px;color:#141414;">
    <h1>Accessible report</h1>
    <p>A paragraph of prose.</p>
    <h2>Findings</h2>
    <ul><li>First finding</li><li>Second finding</li></ul>
    <figure>
      <img src="pixel" alt="a grey square" style="width:40px;height:40px;" />
      <figcaption>A described pixel.</figcaption>
    </figure>
  </main>` },
    { name: "borders-tagged-ua1", page: { ...A4, pdfa: "3a", tagged: "ua1", lang: "en", metadata: { title: "Borders", creationDate: date(9) } }, html: `<main style="display:flex;flex-direction:column;gap:8px;font-size:14px;color:#141414;">
    <h1>Borders</h1>
    <p style="border:3px dashed #b91c1c;padding:4px;">Dashed all round</p>
    <p style="border-top:4px solid rgba(255,0,0,0);border-left:2px solid rgba(0,0,255,0);padding:4px;">Invisible sides</p>
  </main>` },
    { name: "decorative-image-ua1", images: pixel, page: { ...A4, tagged: "ua1", lang: "en", metadata: { title: "Images" } }, html: `<main style="display:flex;flex-direction:column;font-size:14px;color:#141414;">
    <h1>Images</h1>
    <img src="pixel" alt="" style="width:40px;height:40px;" />
    <img src="pixel" alt="a described pixel" style="width:40px;height:40px;" />
  </main>` },
    { name: "inline-box-lang-ua1", page: { ...A4, pdfa: "3a", tagged: "ua1", lang: "en", metadata: { title: "Inline language", creationDate: date(7) } }, html: `<main style="display:flex;flex-direction:column;font-size:14px;color:#141414;">
    <h1>Inline language</h1>
    <p lang="ar">before <span style="display:inline-block;" lang="hi">inside</span> after</p>
  </main>` },
    { name: "heading-levels-ua1", page: { ...A4, pdfa: "3a", tagged: "ua1", lang: "en", metadata: { title: "Headings", creationDate: date(7) } }, html: `<main style="display:flex;flex-direction:column;font-size:14px;color:#141414;">
    <h1></h1>
    <h2>Opens below h1</h2>
    <p>Body</p>
    <h4>Skips two levels</h4>
    <h3>Wrapped <strong>bold</strong> text</h3>
    <li>An item with no list</li>
  </main>` },
  ];
}
