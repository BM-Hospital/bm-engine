# Liên kết, bookmark, metadata và tệp đính kèm

[English](../en/pdf-links-metadata.md) · [Tiếng Việt](pdf-links-metadata.md)

Các phần tương tác và mô tả của PDF đến từ chính tài liệu: một `<a href>` trở thành liên kết bấm được, các tiêu đề
có thể trở thành bảng bookmark, và tùy chọn `metadata` điền vào thuộc tính tài liệu. Tệp có thể được nhúng làm tệp
đính kèm. Trang này nói về từng phần, kèm quy tắc chính xác về liên kết nào được giữ, outline được lồng ra sao và
các trường metadata làm gì. Nó cần [profile `pdf`](pdf.md). Mọi đoạn mã Node.js là các đoạn của
`docs/examples/pdf-links-metadata.mjs` trong repository và đã được chính file đó chạy.

- [Chuẩn bị](#chuẩn-bị)
- [Liên kết](#liên-kết)
- [Bookmark](#bookmark)
- [Metadata](#metadata)
- [XMP tùy biến](#xmp-tùy-biến)
- [Tệp đính kèm](#tệp-đính-kèm)

## Chuẩn bị

<!-- @example pdf-links-metadata#setup -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const page = { size: { width: 400, height: 300 }, margin: 24 };
```

## Liên kết

Mỗi phần tử có `href` mà engine chấp nhận trở thành một annotation liên kết trong PDF:

- `#id` liên kết tới phần tử có `id` đó, dù nó rơi ở đâu (kể cả trang khác). Đích là một vị trí ở đầu phần tử.
  Fragment không trỏ phần tử nào, hoặc phần tử nằm trên trang mà `pageRanges` đã loại, thì không ghi liên kết.
- Liên kết `http:`, `https:`, `mailto:` và `tel:` mở URI.
- Mọi thứ khác (`ftp:`, `javascript:`, đường dẫn tương đối) bị bỏ qua.

Một hộp có `href` (ví dụ `<a>` dạng block) là một liên kết trên toàn bộ border box. Chữ inline bên trong `<a>` là
một liên kết cho mỗi dòng được vẽ, phủ bề rộng dòng và ascent cùng descent của font. Liên kết vắt qua chỗ ngắt
trang nhận một annotation ở mỗi trang nó chạm tới. Liên kết không có viền nhìn thấy (`/Border [0 0 0]`) và có in
(`/F 4`).

<!-- @example pdf-links-metadata#links -->
```js
const linked = await pdf.render(
  `<div style="font: 14px Inter">
     <p>Read <a href="https://example.com/docs">the docs</a>, write to <a href="mailto:hi@example.com">us</a>
        or jump to <a href="#details">the details</a>.</p>
     <a href="https://example.com/card" style="display: block; padding: 12px; background: #e2e8f0">A whole box is one link</a>
     <h2 id="details" style="break-before: page">Details</h2>
   </div>`,
  page,
);
```

[Band](pdf-headers-footers.md) header và footer không bao giờ mang liên kết. Hộp `position: fixed` lặp lại thì có,
trên mọi trang.

Trong cây node, liên kết là một container có `tagName: "a"` và `attributes: { href }`:

<!-- @example pdf-links-metadata#link-node -->
```js
const nodeLink = await pdf.render(
  {
    type: "container",
    tagName: "a",
    attributes: { href: "https://example.com" },
    style: { display: "flex", padding: 12, backgroundColor: "#dbeafe" },
    children: [{ type: "text", text: "Open example.com", style: { fontFamily: "Inter", fontSize: 14 } }],
  },
  page,
);
```

## Bookmark

`outline: true` dựng bảng bookmark từ các tiêu đề `h1` đến `h6` có chữ. Tiêu đề được sắp theo thứ tự xuất hiện và
lồng theo cấp (`h3` dưới `h2` là con của nó), mỗi mục trỏ tới đầu tiêu đề của nó, và cây ở trạng thái đóng khi mở
file. Nếu `pageRanges` loại trang của một tiêu đề, các mục con của nó được đẩy lên. Đầu ra có thẻ với
`tagged: "ua1"` hoặc `"ua2"` cũng dựng outline, vì PDF/UA đòi hỏi nó ([Khả năng truy cập và lưu
trữ](pdf-accessibility.md)).

<!-- @example pdf-links-metadata#outline -->
```js
const book = `<div style="font: 14px Inter">
  <h1>Handbook</h1><p>Intro.</p>
  <h2 style="break-before: page">Install</h2><p>Steps.</p>
  <h2 style="break-before: page">Use</h2><h3>Options</h3><p>Flags.</p>
</div>`;
const withOutline = await pdf.render(book, { ...page, outline: true });
// bookmarks: Handbook > (Install, Use > Options), each pointing at its heading
```

Trong cây node, tiêu đề là container có `tagName: "h1"` đến `"h6"`.

## Metadata

`metadata` điền vào thuộc tính tài liệu (Info dictionary và gói XMP mà file nào cũng có):

| Trường | Ý nghĩa |
|:--|:--|
| `title` | Tiêu đề tài liệu. |
| `description` | Chủ đề (subject). |
| `authors` | Danh sách tên, nối bằng `, ` trong Info dictionary. |
| `keywords` | Danh sách từ khóa, nối bằng `, ` trong Info dictionary. |
| `creator` | Công cụ đã tạo tài liệu nguồn. |
| `creationDate` | UTC, `YYYY-MM-DD` hoặc `YYYY-MM-DDTHH:MM:SS`. Dùng cho ngày tạo và ngày sửa. Các mức PDF/A đòi hỏi khi đã đặt `metadata`. |
| `xmp` | Schema XMP tùy biến, xem bên dưới. |

`title`, `description` hoặc `creator` rỗng và danh sách `authors` hoặc `keywords` rỗng được coi là không có. `lang`
(thẻ BCP-47 như `"en"` hay `"vi"`) là ngôn ngữ tài liệu và đồng thời là ngôn ngữ của metadata; PDF/A-2a, PDF/A-3a
và PDF/UA-2 đòi hỏi nó. Ngày không hợp lệ ném `invalid creationDate: expected YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS`.
PDF/A-4 và PDF/A-4f không ghi Info dictionary, chỉ có XMP, và `creator` chỉ vào Info dictionary ở file dưới
PDF 2.0.

<!-- @example pdf-links-metadata#metadata -->
```js
const described = await pdf.render(book, {
  ...page,
  lang: "en",
  metadata: {
    title: "Handbook",
    description: "Setup and usage guide",
    authors: ["A. Writer", "B. Editor"],
    keywords: ["guide", "setup"],
    creator: "bm-engine docs",
    creationDate: "2026-08-06T09:30:00", // UTC; or just "2026-08-06"
  },
});
```

Info dictionary ghi `bm-engine` là producer.

## XMP tùy biến

`metadata.xmp` thêm schema XMP của riêng bạn, ví dụ phần mở rộng Factur-X. Mỗi schema có `name`, `prefix`,
`namespace` (một URI) và `properties`; mỗi property có `name`, `value` và `description` (PDF/A đòi hỏi mô tả).
Prefix, namespace và tên property phải viết được thành XML, nếu không render ném `XMP schema cannot be written as
XML: <giá trị vi phạm>`.

<!-- @example pdf-links-metadata#xmp -->
```js
const custom = await pdf.render(book, {
  ...page,
  metadata: {
    title: "Handbook",
    xmp: [{
      name: "Acme workflow",
      prefix: "acme",
      namespace: "https://example.com/ns/acme/1.0/",
      properties: [{ name: "Ticket", value: "DOC-1234", description: "Tracking ticket of the document" }],
    }],
  },
});
```

## Tệp đính kèm

`attachments` nhúng tệp; trình xem liệt kê chúng trong bảng tệp đính kèm.

| Trường | Ý nghĩa |
|:--|:--|
| `name` | Tên tệp, duy nhất trong tài liệu (nếu không: `Two attachments are named <tên>`). |
| `data` | Byte (`Uint8Array`, `ArrayBuffer`) hoặc một chuỗi, được mã hóa UTF-8. Bắt buộc. |
| `mimeType` | Media type dạng `type/subtype`; dạng khác ném `Attachment mime type is not a type/subtype pair: <giá trị>`. |
| `description` | Mô tả dành cho người đọc. |
| `relationship` | `source`, `data`, `alternative`, `supplement` hoặc `unspecified` (mặc định). Chỉ được ghi ở nơi có associated file: PDF/A-3 và PDF 2.0. |
| `modificationDate` | Ngày UTC; nếu bỏ trống thì lấy `metadata.creationDate`. |

Các tệp được liệt kê sắp theo tên, và dữ liệu được nén khi việc đó tiết kiệm hơn một phần tư kích thước. Với PDF/A
chỉ các mức PDF/A-3 và PDF/A-4f chấp nhận tệp đính kèm, và các mức PDF/A-3 đòi hỏi `mimeType`, `description` và một ngày;
xem [Khả năng truy cập và lưu trữ](pdf-accessibility.md#tệp-đính-kèm-và-pdfa).

<!-- @example pdf-links-metadata#attachments -->
```js
const bytes = new Uint8Array([0x50, 0x4b, 3, 4]); // any binary data
const attached = await pdf.render("<p style=\"font-family: Inter\">See the attached files.</p>", {
  attachments: [
    { name: "data.csv", data: "a,b\n1,2\n", mimeType: "text/csv", relationship: "data" }, // a string is encoded as UTF-8
    { name: "archive.zip", data: bytes, mimeType: "application/zip", description: "Source files" },
  ],
});
// the viewer lists both files in its attachment panel
```

<!-- @example pdf-links-metadata#attachment-errors -->
```js
const messages = [];
for (const attachments of [
  [{ name: "a.txt", data: "x" }, { name: "a.txt", data: "y" }],
  [{ name: "a.txt", data: "x", mimeType: "plain" }],
]) {
  try { await pdf.render("<p>x</p>", { attachments }); } catch (e) { messages.push(e.message); }
}
// bm-engine: Two attachments are named a.txt
// bm-engine: Attachment mime type is not a type/subtype pair: plain
```
