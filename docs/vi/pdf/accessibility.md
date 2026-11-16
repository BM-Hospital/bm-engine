# Khả năng truy cập và lưu trữ

[English](../../en/pdf/accessibility.md) · [Tiếng Việt](accessibility.md)

Hai tùy chọn biến một file PDF thành tài liệu tuân thủ chuẩn. `tagged` ghi cây cấu trúc mà trình đọc màn hình dùng
và, ở dạng `"ua1"` hay `"ua2"`, kiểm tra tài liệu theo PDF/UA. `pdfa` ghi PDF/A để lưu trữ lâu dài và kiểm tra tài
liệu theo chuẩn đó. Trang này liệt kê mỗi tùy chọn ghi gì, mỗi chuẩn cần phiên bản PDF nào, những tổ hợp nào bị từ
chối và với lỗi gì, và các kiểm tra đi xa đến đâu. Nó cần [profile `pdf`](index.md). Mọi đoạn mã Node.js là các đoạn
của `docs/examples/pdf-accessibility.mjs` trong repository và đã được chính file đó chạy.

- [Chuẩn bị](#chuẩn-bị)
- [PDF có thẻ](#pdf-có-thẻ)
- [PDF/UA](#pdfua)
- [Văn bản thay thế cho ảnh](#văn-bản-thay-thế-cho-ảnh)
- [PDF/A](#pdfa)
- [Phiên bản và tổ hợp](#phiên-bản-và-tổ-hợp)
- [Tệp đính kèm và PDF/A](#tệp-đính-kèm-và-pdfa)
- [Các kiểm tra đi xa đến đâu](#các-kiểm-tra-đi-xa-đến-đâu)

## Chuẩn bị

<!-- @example pdf-accessibility#setup -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-render/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const doc = `<div style="font-family: Inter"><h1>Annual report</h1><p>Revenue grew.</p></div>`;
```

## PDF có thẻ

`tagged` mặc định là `true`: mọi PDF mang một cây cấu trúc dựng từ ngữ nghĩa HTML của tài liệu. `tagged: false` bỏ
cây này đi.

<!-- @example pdf-accessibility#tagged -->
```js
const tagged = await pdf.render(doc);                         // tagged: true is the default
const untagged = await pdf.render(doc, { tagged: false });    // no structure tree
```

Cây bám theo các phần tử: tiêu đề, đoạn văn, liên kết (mỗi annotation liên kết gia nhập một phần tử `Link` và nhận
URI của nó làm mô tả), ảnh và `figure` (kèm văn bản thay thế), `blockquote`, `section`, `article`, danh sách,
`strong` / `b`, `em` / `i`, `code`, `figcaption`, và bảng có caption, `thead` / `tbody` / `tfoot`, hàng, ô tiêu đề
kèm scope và ô kèm span. Nội dung rời rạc trở thành đoạn văn. Header, footer và ảnh trang trí được đánh dấu là
artifact, mà trình đọc màn hình bỏ qua. Ngôn ngữ của chữ là thuộc tính `lang` gần nhất, nếu không có thì là tùy chọn
`lang`. Trong cây node, đặt `tagName` (`"h1"`, `"p"`, ...) và `attributes` (`alt`, `href`) trên container.

Ký hiệu danh sách được vẽ, cả trong đầu ra nhiều trang lẫn `viewport`, và mỗi mục có ký hiệu có phần tử `Lbl` (nhãn)
và `LBody`. Mục không có ký hiệu chỉ có `LBody` ([Hạn chế đã biết](limitations.md) liệt kê những gì được hỗ trợ).

## PDF/UA

`tagged: "ua1"` hoặc `"ua2"` ghi cây cấu trúc và kiểm tra tài liệu theo PDF/UA-1 (PDF 1.7) hoặc PDF/UA-2 (PDF
2.0). Nó cũng dựng [bookmark](links-metadata.md#bookmark) từ các tiêu đề, như chuẩn đòi hỏi. Tài liệu lỗi khi vi
phạm một quy tắc. Những quy tắc quan trọng trong thực tế:

- tiêu đề tài liệu (`metadata.title`);
- có tiêu đề (heading), vì outline được dựng từ chúng (tài liệu không có heading thì không có outline);
- văn bản thay thế cho mọi ảnh mang thông tin (thuộc tính `alt`);
- với PDF/UA-2, ngôn ngữ tài liệu (`lang`);
- font nhúng được và có ánh xạ Unicode, và không có glyph 0 (`.notdef`) trong chữ.

<!-- @example pdf-accessibility#ua1 -->
```js
const ua1 = await pdf.render(doc, {
  tagged: "ua1",
  lang: "en",                                // the document language
  metadata: { title: "Annual report" },      // PDF/UA needs a title (the outline comes from the headings)
});
```

Vi phạm không được nêu tên. Render ném một lỗi duy nhất kèm số lượng, và nguyên nhân thường gặp là danh sách trên:

<!-- @example pdf-accessibility#ua1-errors -->
```js
const noTitle = await outcome(pdf.render(doc, { tagged: "ua1", lang: "en" }));
// bm-render: Writing the PDF failed: validation failed with 1 error
const noHeading = await outcome(pdf.render(`<p style="font-family: Inter">Text only</p>`, { tagged: "ua1", metadata: { title: "T" } }));
// bm-render: Writing the PDF failed: validation failed with 1 error   (a PDF/UA document needs an outline)
```

## Văn bản thay thế cho ảnh

Với PDF/UA và các mức `a` của PDF/A, `<img>` cần thuộc tính `alt`. `alt=""` đánh dấu ảnh là trang trí: nó được ghi
như artifact và không cần mô tả. `figure` lấy văn bản thay thế từ ảnh bên trong nó.

<!-- @example pdf-accessibility#alt -->
```js
const logo = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==", "base64"));
const withImage = (img) => `<div style="font-family: Inter"><h1>Logo</h1>${img}</div>`;
const options = { tagged: "ua1", lang: "en", metadata: { title: "Logo" }, images: [{ src: "logo", data: logo }] };

const noAlt = await outcome(pdf.render(withImage(`<img src="logo" width="40" height="40">`), options));
const alt = await outcome(pdf.render(withImage(`<img src="logo" alt="Company logo" width="40" height="40">`), options));
const decorative = await outcome(pdf.render(withImage(`<img src="logo" alt="" width="40" height="40">`), options));
// noAlt: validation failed with 1 error; alt: "ok"; decorative (alt=""): "ok", marked as an artifact
```

## PDF/A

`pdfa` nhận `"2a"`, `"2b"`, `"2u"`, `"3a"`, `"3b"`, `"3u"`, `"4"` hoặc `"4f"`; giá trị không biết ném `unknown pdfa
level: <giá trị> (expected 2a, 2b, 2u, 3a, 3b, 3u, 4 or 4f)`. Trong mọi file PDF/A, màu được gắn với profile sRGB
nhúng và một output intent (thay vì `DeviceRGB`), XMP mang phần `pdfaid` và mức tuân thủ, và font được nhúng. Profile
sRGB là sRGB v4 của "Compact ICC Profiles" theo CC0 ([Thông báo bên thứ ba](../../../THIRD-PARTY-NOTICES.md)).

| Mức | Phiên bản PDF | Cây cấu trúc | Tệp đính kèm |
|:--|:--|:--|:--|
| `2a` | 1.7 | luôn có (cả khi `tagged: false`) | không chấp nhận |
| `2b`, `2u` | 1.7 | theo `tagged` | không chấp nhận |
| `3a` | 1.7 | luôn có | chấp nhận, kèm mime type, mô tả và ngày |
| `3b`, `3u` | 1.7 | theo `tagged` | chấp nhận, kèm mime type, mô tả và ngày |
| `4` | 2.0 | theo `tagged` | không chấp nhận |
| `4f` | 2.0 | theo `tagged` | chấp nhận |

Các mức `a` còn cần ngôn ngữ tài liệu (`lang`) và văn bản thay thế cho ảnh. Khi đã đặt `metadata`, PDF/A đòi hỏi
`metadata.creationDate`; không có `metadata` thì không cần ngày. PDF/A-4 và 4f không ghi Info dictionary, metadata
chỉ nằm trong gói XMP. Danh sách tệp nhúng rỗng của PDF/A-4f được ghi kể cả khi không có tệp đính kèm.

<!-- @example pdf-accessibility#pdfa -->
```js
const archival = await pdf.render(doc, {
  pdfa: "2b",
  metadata: { title: "Annual report", creationDate: "2026-01-31" }, // PDF/A needs a date once metadata is set
});
```

<!-- @example pdf-accessibility#pdfa4 -->
```js
const pdfa4 = await pdf.render(doc, { pdfa: "4", tagged: "ua2", lang: "en", metadata: { title: "Annual report", creationDate: "2026-01-31" } });
// PDF/A-4 and PDF/UA-2 are PDF 2.0
```

## Phiên bản và tổ hợp

Phiên bản PDF là phiên bản cao nhất mà mọi chuẩn được yêu cầu cho phép, và PDF thường là 1.7. PDF/A-2, PDF/A-3 và
PDF/UA-1 là PDF 1.7; PDF/A-4 và PDF/UA-2 là PDF 2.0. Vì vậy PDF/UA-1 kết hợp được với các mức PDF/A-2 và PDF/A-3,
còn PDF/UA-2 với PDF/A-4 và 4f. Các cặp còn lại không có phiên bản chung.

Kiểu TypeScript từ chối các tổ hợp bất khả thi ngay lúc biên dịch: `tagged: false` với các mức `a`, PDF/UA-1 với
PDF/A-4, PDF/UA-2 với PDF/A-2 hoặc 3, và tệp đính kèm với PDF/A-2 hoặc PDF/A-4. Khi chạy, engine cũng kiểm tra,
nhưng thông báo là những thông báo dưới đây, không phải thông báo của kiểu:

| Yêu cầu | Kết quả |
|:--|:--|
| `pdfa: "2b"` với `tagged: "ua2"`, hoặc `pdfa: "4"` với `tagged: "ua1"` | ném `The requested archival standard is not available` (không có phiên bản PDF chung) |
| tệp đính kèm với `pdfa: "2a" \| "2b" \| "2u" \| "4"` | ném `Writing the PDF failed: validation failed with 1 error` |
| tệp đính kèm `pdfa: "3b"` thiếu `description` hoặc `mimeType` | ném `Writing the PDF failed: validation failed with N errors` |
| `pdfa: "1b"` hoặc mức không biết khác | ném `` unknown variant `1b`, expected one of `2a`, `3a`, `2b`, `2u`, `3b`, `3u`, `4`, `4f` `` |
| `uncoveredText: "placeholder"` với ký tự không font nào có, dưới `pdfa` hoặc PDF/UA | ném `No font the text can use draws <ký tự> (U+XXXX), and PDF/A-2b forbids the placeholder glyph. Register a font that draws them, or set uncoveredText to "blank".` ([Font trong PDF](fonts.md#ký-tự-không-font-nào-có)) |
| `tagged: false` với `pdfa: "2a"` hoặc `"3a"` | không phải lỗi khi chạy: cây vẫn được ghi (kiểu từ chối nó) |

<!-- @example pdf-accessibility#rejected -->
```js
const attach = [{ name: "a.xml", data: "<x/>", mimeType: "application/xml", description: "d" }];
const results = {
  "2b + ua2": await outcome(pdf.render(doc, { pdfa: "2b", tagged: "ua2" })),
  "4 + ua1": await outcome(pdf.render(doc, { pdfa: "4", tagged: "ua1" })),
  "2b + attachments": await outcome(pdf.render(doc, { pdfa: "2b", metadata: { creationDate: "2026-01-31" }, attachments: attach })),
  "3b + attachment without description": await outcome(pdf.render(doc, { pdfa: "3b", metadata: { creationDate: "2026-01-31" }, attachments: [{ name: "a.xml", data: "x", mimeType: "application/xml" }] })),
  "unknown level": await outcome(pdf.render(doc, { pdfa: "1b" })),
};
// "2b + ua2":  bm-render: The requested archival standard is not available
// "4 + ua1":   bm-render: The requested archival standard is not available
// "2b + attachments": bm-render: Writing the PDF failed: validation failed with 1 error
// "3b + attachment without description": bm-render: Writing the PDF failed: validation failed with 1 error
// "unknown level": bm-render: unknown variant `1b`, expected one of `2a`, `3a`, `2b`, `2u`, `3b`, `3u`, `4`, `4f`
```

## Tệp đính kèm và PDF/A

PDF/A-3 (cả ba mức) là con đường thường dùng để đính dữ liệu đứng sau tài liệu, chẳng hạn XML của hóa đơn điện
tử. Mỗi tệp đính kèm phải có `mimeType` và `description`, cùng một ngày: `modificationDate` của riêng nó hoặc
`metadata.creationDate` của tài liệu. Không có `metadata` thì mỗi tệp đính kèm cần `modificationDate` riêng. Hãy
đặt `relationship` (`"data"`, `"source"`, `"alternative"`, `"supplement"` hoặc `"unspecified"`) để nói tệp liên hệ
với tài liệu ra sao; nó được ghi dưới dạng association của PDF/A-3.

<!-- @example pdf-accessibility#attachments -->
```js
const invoice = await pdf.render(doc, {
  pdfa: "3b",
  metadata: { title: "Invoice 2026-017", creationDate: "2026-01-31" },
  attachments: [{
    name: "factur-x.xml",
    data: "<rsm:CrossIndustryInvoice/>",
    mimeType: "application/xml",             // required by the PDF/A-3 levels
    description: "Invoice data",             // required by the PDF/A-3 levels
    relationship: "data",
    modificationDate: "2026-01-31",          // falls back to metadata.creationDate
  }],
});
```

PDF/A-4f chấp nhận tệp đính kèm. Engine không kiểm tra `mimeType`, `description` hay ngày của chúng ở đó (kiểu
TypeScript `ArchivalAttachment` vẫn yêu cầu; hãy cung cấp chúng). PDF/A-2 và PDF/A-4 từ chối tệp đính kèm.

## Các kiểm tra đi xa đến đâu

Phần kiểm tra áp dụng các quy tắc về tính phù hợp của PDF. Nó kiểm tra tiêu đề tài liệu, ngôn ngữ
tài liệu, văn bản thay thế cho ảnh và liên kết, outline, ngày, tệp nhúng (sự tồn tại, mime type, mô tả, ngày), và
font (giấy phép nhúng, ánh xạ Unicode, `.notdef`) cùng các giới hạn về chuỗi, tên và độ sâu lồng nhau
(`TooLongString`, `TooLongName`, `TooManyIndirectObjects`, `TooHighQNestingLevel`). Nó không đọc lại file như
một validator.

Các fixture về tính phù hợp đã được kiểm tra bằng veraPDF. Kết quả này không chứng nhận mọi tài liệu tạo bởi thư viện: hãy kiểm tra PDF thực tế của ứng dụng. Xem [hạn chế đã biết](limitations.md).
