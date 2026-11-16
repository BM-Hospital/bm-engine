# Font

[English](../../en/image/fonts.md) · [Tiếng Việt](fonts.md)

bm-render chỉ vẽ chữ bằng những font bạn đăng ký: package **không** kèm sẵn font nào và không bao giờ đọc
font của hệ thống. Trang này nói về cách nạp font (TTF, OTF/CFF, TTC, WOFF/WOFF2, font biến thiên và font
màu), cách một `font-family` được ghép với một face, cơ chế fallback khi thiếu glyph, chữ đậm và nghiêng
giả lập trông thế nào, mỗi [profile](../profiles-and-size.md) hỗ trợ những gì, và font tốn bao nhiêu bộ
nhớ. Mọi ví dụ bên dưới đều được chạy bởi `docs/examples/fonts.mjs`; ảnh minh hoạ chính là kết quả của nó.

[[toc]]

## Đăng ký font

Tạo một `Renderer` một lần rồi đăng ký font lên nó. `registerFont` nhận bytes của font (`Uint8Array`,
`ArrayBuffer` hoặc `Buffer` của Node) và trả về các family vừa được thêm:

<!-- @example fonts#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
const families = renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
// families: [{ name: "Inter", faces: [{ weight: 400, style: "normal", width: 100, index: 0 }],
//              weight: 400, style: "normal" }]
```

Tên family, độ đậm và kiểu chữ được đọc từ chính các bảng của font (`name` và `OS/2`). Font thuộc về
renderer: một `new Renderer()` thứ hai bắt đầu với không có font nào. Hãy đăng ký một lần lúc khởi động và
dùng lại renderer cho mọi lần render (xem [Hiệu năng](./performance.md)).

Khi chưa đăng ký font, chữ **không được vẽ** và cũng không báo lỗi. Hãy đăng ký ít nhất một font trước khi render chữ.

### Nhiều face trong một family

Đăng ký thêm một file có cùng tên family sẽ thêm một face vào family đó. Bạn cũng có thể ghi đè tên, độ
đậm và kiểu chữ mà file khai báo, chẳng hạn để đặt tên thương hiệu cho font, hoặc để đăng ký một file
như một độ đậm cụ thể:

<!-- @example fonts#faces -->
```js
// More faces of the same family: name, weight and style are read from each file.
renderer.registerFont(readFileSync("assets/fonts/Inter-SemiBold.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
const inter = renderer.registerFont(readFileSync("assets/fonts/Inter-Italic.ttf"));
// inter[0].faces: 400 normal, 600 normal, 700 normal, 400 italic

// Override what the file says: register Roboto Bold as weight 900 of a family called "Brand".
const brand = renderer.registerFont({ name: "Brand", data: readFileSync("assets/fonts/Roboto-Bold.ttf"), weight: 900 });
// brand: [{ name: "Brand", faces: [{ weight: 900, style: "normal", width: 100, index: 0 }], ... }]
```

| Trường của object chi tiết | Ý nghĩa |
|:--|:--|
| `data` | bytes của font (với API async: có thể là hàm hoặc promise trả về bytes) |
| `name` | tên family để đăng ký (mặc định: tên family trong font) |
| `weight` | số ghi đè độ đậm đọc từ file |
| `style` | `"normal"`, `"italic"` hoặc `"oblique"`, ghi đè giá trị trong file |
| `unicodeRange`, `subsetOf`, `generic` | được chấp nhận để tương thích API và **bị bỏ qua** |

Một collection `.ttc` / `.otc` đăng ký mọi face bên trong: một collection có hai face trả về hai
family là `Geist` (face `index: 0`) và `Geist Mono` (face `index: 1`).

## Định dạng font và profile

| Định dạng | core | standard | full |
|:--|:-:|:-:|:-:|
| TrueType `.ttf`, collection `.ttc` | có | có | có |
| OpenType có outline CFF / CFF2 (`.otf`) | không: ném lỗi `unsupported font format` | có | có |
| WOFF / WOFF2 | có, với [add-on WOFF](#woff-và-woff2) | có | có |
| Font biến thiên (variable font) | đăng ký được, chỉ vẽ ở instance mặc định | có | có |
| Glyph màu: COLR v0/v1 | outline thường, không màu | outline thường, không màu | có |
| Glyph màu: bitmap CBDT / sbix | không vẽ | có | có |

Bytes không phải font sẽ ném lỗi `bm-render: invalid font data`. Kiểm tra binary đang nạp hỗ trợ gì qua
`features.woff`, `features.cff`, `features.variableFonts` và `features.colorFonts`.

## Face được chọn như thế nào

Trong một family, bm-render áp dụng thuật toán ghép font của CSS: xét `font-stretch` trước, rồi
`font-style`, rồi `font-weight`. Với độ đậm, điều đó có nghĩa: độ đậm yêu cầu nằm trong khoảng 400–500 sẽ
thử các độ đậm tới 500 trước, rồi đến các độ nhạt hơn, rồi mới tới các độ đậm hơn; dưới 400 thì ưu tiên
độ nhạt hơn, trên 500 thì ưu tiên độ đậm hơn. Khi đã đăng ký Inter Regular (400), SemiBold (600), Bold
(700) và Italic (400 nghiêng):

<!-- @example fonts#matching -->
```js
const row = (text, style) => ({ type: "text", text, style: { fontFamily: "Inter", fontSize: 26, ...style } });
const matching = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", gap: 2, padding: "12px 20px", width: "100%", height: "100%", backgroundColor: "#fff", color: "#111827" },
    children: [
      row("300 → Regular (400)", { fontWeight: 300 }),
      row("500 → Regular (400)", { fontWeight: 500 }),
      row("600 → SemiBold", { fontWeight: 600 }),
      row("800 → Bold (700)", { fontWeight: 800 }),
      row("italic → Inter Italic", { fontStyle: "italic" }),
      row("bold italic → synthesised", { fontStyle: "italic", fontWeight: 700 }),
    ],
  },
  { width: 560, height: 200 },
);
```

![Độ đậm 300 và 500 dùng Inter Regular, 600 dùng SemiBold, 800 dùng Bold; italic dùng Inter Italic; bold italic là face nghiêng được làm đậm](/img/guide/fonts-matching.png)

Dòng cuối yêu cầu độ đậm 700 kiểu nghiêng. Kiểu chữ được ưu tiên hơn độ đậm, nên face Italic (400) được
chọn và độ đậm được **giả lập** thêm lên trên.

### Đậm và nghiêng giả lập

Khi face được chọn nhạt hơn độ đậm yêu cầu, bm-render làm dày outline; khi không có face nghiêng, nó làm
xiên face thường (oblique). Ở đây family "Solo" chỉ có Roboto Regular:

<!-- @example fonts#synthesis -->
```js
// "Solo" has a single regular face: bold and italic are synthesised.
renderer.registerFont({ name: "Solo", data: readFileSync("assets/fonts/Roboto-Regular.ttf") });
const synthesis = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", padding: "12px 20px", width: "100%", height: "100%", backgroundColor: "#fff", fontFamily: "Solo", fontSize: 26 },
    children: [
      { type: "text", text: "Regular face as registered" },
      { type: "text", text: "fontWeight 700: synthetic bold", style: { fontWeight: 700 } },
      { type: "text", text: "fontStyle italic: synthetic oblique", style: { fontStyle: "italic" } },
      { type: "text", text: "fontSynthesis none: still synthesised", style: { fontWeight: 700, fontSynthesis: "none" } },
    ],
  },
  { width: 560, height: 160 },
);
```

![Roboto Regular, một dòng đậm giả lập, một dòng nghiêng giả lập và một dòng vẫn đậm dù đặt fontSynthesis none](/img/guide/fonts-synthesis.png)

::: warning `font-synthesis` không tắt được đậm và nghiêng
`fontSynthesisWeight`, `fontSynthesisStyle` và phần weight / style của `fontSynthesis` được parse nhưng
không có tác dụng trong 0.1.0: giả lập đậm và nghiêng luôn bật (dòng cuối ở trên). Hãy đăng ký file đậm / nghiêng thật khi bản giả lập chưa đủ
đẹp; bản thật luôn đẹp hơn.
:::

Small caps cũng được giả lập: `fontVariant: "small-caps"` dùng feature `smcp` của font nếu có, nếu không
thì vẽ chữ hoa ở 70 % cỡ chữ (Inter và Roboto không có small caps). Khác với đậm và nghiêng, giả lập này
tắt được, bằng `fontSynthesisSmallCaps: "none"` hoặc một giá trị `fontSynthesis` không chứa `small-caps`.
Xem [Typography → Chữ hoa nhỏ](./typography.md#small-caps).

## Fallback

Mỗi ký tự được tìm trước tiên trong danh sách `font-family` của phần tử. Nếu không family nào trong đó có
glyph cho ký tự, bm-render thử **mọi family đã đăng ký, theo thứ tự đăng ký**. Vì vậy chỉ cần đăng ký một
font phủ được chữ viết hay bộ ký hiệu đó là đủ: bạn không phải thêm nó vào mọi `fontFamily`.

Roboto không có glyph cho nhiều ký hiệu. Khi chỉ đăng ký Roboto, chúng hiện thành ô vuông; sau khi đăng ký
thêm Inter (có các ký hiệu này), cùng một cây node sẽ vẽ các ký hiệu bằng Inter:

<!-- @example fonts#fallback -->
```js
const symbols = { type: "text", text: "Roboto: ① ★ ✓ ∑ → ⌘ ⇧ ↗ × ● ▶ ◆ ♥", style: { fontFamily: "Roboto", fontSize: 26 } };
const card = (child) => ({ type: "container", style: { display: "flex", alignItems: "center", padding: "0 20px", width: "100%", height: "100%", backgroundColor: "#fff" }, children: [child] });

const robotoOnly = new Renderer();
robotoOnly.registerFont(readFileSync("assets/fonts/Roboto-Regular.ttf"));
const before = robotoOnly.renderSync(card(symbols), { width: 560, height: 56 });

robotoOnly.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf")); // Inter covers the symbols
const after = robotoOnly.renderSync(card(symbols), { width: 560, height: 56 });
```

![Chỉ có Roboto: các ký hiệu bị vẽ thành ô vuông](/img/guide/fonts-fallback-before.png)

![Roboto rồi Inter: các ký hiệu lấy từ Inter](/img/guide/fonts-fallback-after.png)

### Khi không font nào có glyph

Ký tự mà không font đã đăng ký nào phủ được sẽ được vẽ bằng **glyph `.notdef`** của family đầu tiên trong
danh sách của phần tử (thường là một ô vuông; của Inter có chữ "NOGLYPH"). Ký tự đó vẫn chiếm chỗ, nên
layout không đổi khi sau này bạn thêm font phủ được nó:

<!-- @example fonts#notdef -->
```js
// Characters that no registered font covers are drawn with the .notdef glyph of the
// first family in the element's stack: each font has its own (usually a box).
const notdef = robotoOnly.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", padding: "8px 20px", width: "100%", height: "100%", backgroundColor: "#fff", fontSize: 26 },
    children: [
      { type: "text", text: "Inter: ქართული Հայերեն", style: { fontFamily: "Inter" } },
      { type: "text", text: "Roboto: ქართული Հայերեն", style: { fontFamily: "Roboto" } },
    ],
  },
  { width: 560, height: 90 },
);
```

![Chữ Gruzia và Armenia vẽ thành các ô notdef trong Inter và trong Roboto](/img/guide/fonts-notdef.png)

Hãy đăng ký font cho mọi hệ chữ mà nội dung của bạn có thể chứa (Noto Sans có family cho gần như mọi hệ
chữ). Với tiếng Việt, các font trong repository này (Inter, Noto Sans, Roboto) đã có đủ mọi chữ dựng sẵn;
xem [Typography](./typography.md#tiếng-việt).

### Font stack gốc và tên generic

Phần tử không có `fontFamily` (trực tiếp hay kế thừa) sẽ dùng tuỳ chọn render `fontFamilies`. Các tên
generic như `sans-serif`, `serif` hay `monospace` **không được ánh xạ** tới font nào: chúng không khớp với
gì cả và ký tự rơi xuống fallback theo thứ tự đăng ký (ở đây là Inter, family đăng ký đầu tiên trên
renderer này):

<!-- @example fonts#root-stack -->
```js
// An element without fontFamily uses the fontFamilies option (the root font stack).
// Generic names such as "sans-serif" are not mapped to anything.
const rootStack = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", padding: "8px 20px", width: "100%", height: "100%", backgroundColor: "#fff", fontSize: 26 },
    children: [
      { type: "text", text: "No fontFamily: uses Brand (root stack)" },
      { type: "text", text: "fontFamily sans-serif: falls back too", style: { fontFamily: "sans-serif" } },
      { type: "text", text: "fontFamily Inter", style: { fontFamily: "Inter" } },
    ],
  },
  { width: 560, height: 120, fontFamilies: ["Brand", "Inter"] },
);
```

![Dòng đầu dùng Brand (Roboto Bold), các dòng còn lại dùng Inter](/img/guide/fonts-root-stack.png)

::: tip
Vì tên generic không được ánh xạ, các class Tailwind `font-sans` / `font-mono` và stylesheet kết thúc bằng
`sans-serif` chỉ hoạt động nhờ fallback. Hãy dùng tên family thật (`fontFamily: "Inter"`) ở những chỗ quan
trọng, hoặc đặt font bạn muốn lên đầu `fontFamilies`.
:::

## Tuỳ chọn render `fonts`

Với các method async (`render`, `measure`, `renderAsDataUrl`, `prepare`, ...) bạn có thể truyền font cho
từng lần gọi. Mỗi phần tử là bất cứ thứ gì `registerFont` nhận: bytes, URL, hoặc object chi tiết có `data`
là hàm hay promise. Chúng được đăng ký lên renderer trước khi render và **vẫn được giữ** sau đó. Khi không
có `fontFamilies`, các family của những font này trở thành font stack gốc, nên chữ không có `fontFamily`
sẽ dùng chúng:

<!-- @example fonts#fonts-option -->
```js
// The async API also accepts fonts per call. They are registered on the renderer (and stay
// registered); without fontFamilies their families become the root font stack.
const fresh = new Renderer();
const png = await fresh.render(
  { type: "container", style: { display: "flex", padding: 12, width: "100%", height: "100%", backgroundColor: "#fff", fontSize: 26 },
    children: [{ type: "text", text: "Roboto Bold via the fonts option" }] },
  { width: 560, height: 56, fonts: [{ name: "Roboto", data: () => readFileSync("assets/fonts/Roboto-Bold.ttf") }] },
);
```

![Chữ bằng Roboto Bold](/img/guide/fonts-fonts-option.png)

Các method đồng bộ không nhận `fonts`; hãy gọi `registerFont` trước. Vì các phần tử được đăng ký lại ở mỗi
lần gọi, với font dùng cho mọi lần render nên ưu tiên `registerFont` lúc khởi động (hoặc gọi `prepare()`
một lần).

## Gỡ font

<!-- @example fonts#unregister -->
```js
renderer.unregisterFont("Brand"); // true: every face of the family is removed
renderer.unregisterFont({ name: "Nope" }); // false: nothing to remove
fresh.clearFonts(); // no font at all now: text is not drawn until you register one again
```

`unregisterFont` nhận tên family hoặc `{ name }` và gỡ mọi face của family đó; `clearFonts()` gỡ tất cả.
Sau đó không còn font nào.

## Font biến thiên

Trên `standard` và `full`, font biến thiên đi theo `font-weight` (trục `wght`), `font-stretch` (`wdth`),
`font-optical-sizing` (`opsz`) và `font-variation-settings` (mọi trục). Hãy đăng ký nó **không kèm**
`weight` để nó phục vụ được mọi độ đậm. Ví dụ dùng Archivo, một font biến thiên có trục `wght` và `wdth`
từ file font cục bộ; mọi file TTF hay WOFF2 biến thiên khác đều dùng y như vậy:

<!-- @example fonts#variable -->
```js
// Archivo is a variable font with wght (100-900) and wdth (62-125) axes (OFL; this file
const archivo = readFileSync("./fonts/Archivo-Variable.ttf");
renderer.registerFont({ name: "Archivo", data: archivo }); // no weight: keep the axes free

const line = (text, style) => ({ type: "text", text, style: { fontFamily: "Archivo", fontSize: 26, ...style } });
const variable = {
  type: "container",
  style: { display: "flex", flexDirection: "column", padding: "10px 20px", width: "100%", height: "100%", backgroundColor: "#fff" },
  children: [
    line("fontWeight 100", { fontWeight: 100 }),
    line("fontWeight 450", { fontWeight: 450 }),
    line("fontWeight 900", { fontWeight: 900 }),
    line("fontStretch 62.5%", { fontStretch: "62.5%" }),
    line("fontStretch 125%", { fontStretch: "125%" }),
    line("fontVariationSettings 'wght' 250, 'wdth' 80", { fontVariationSettings: "'wght' 250, 'wdth' 80" }),
  ],
};
const variablePng = renderer.renderSync(variable, { width: 560, height: 200 });
```

![Archivo ở độ đậm 100, 450, 900, dạng hẹp, dạng rộng và với variation settings tường minh](/img/guide/fonts-variable.png)

Trên `core`, font vẫn đăng ký được mà không lỗi nhưng mọi dòng đều được vẽ bằng **instance mặc định**
(của Archivo là độ đậm 600, độ rộng thường; đó cũng là độ đậm `registerFont` báo về):

<!-- @example fonts#variable-core -->
```js
// The same tree on core: the font registers, but only its default instance is drawn.
const { Renderer: CoreRenderer } = await import("bm-render/core");
const coreRenderer = new CoreRenderer();
coreRenderer.registerFont({ name: "Archivo", data: archivo });
const variableCore = coreRenderer.renderSync(variable, { width: 560, height: 200 });
```

![Trên core mọi dòng có cùng độ đậm và độ rộng](/img/guide/fonts-variable-core.png)

## WOFF và WOFF2

`standard` và `full` tự giải mã WOFF và WOFF2. `core` không có bộ giải mã, nhưng add-on WOFF riêng 84 KiB
(`bm-render/woff`) chuyển WOFF / WOFF2 sang TTF / OTF trước khi đăng ký, cho mọi điểm vào trong tiến trình:

<!-- @example fonts#woff -->
```js
// WOFF / WOFF2 work directly on standard and full ...
renderer.registerFont(readFileSync("./fonts/Geist.woff2"));

// ... and on core after loading the 84 KiB WOFF add-on once per process.
const { Renderer: CoreRenderer } = await import("bm-render/core");
const { loadWoff } = await import("bm-render/woff");
await loadWoff();
const geist = new CoreRenderer().registerFont(readFileSync("./fonts/Geist.woff2"));
// geist: [{ name: "Geist", faces: [{ weight: 400, ... }], ... }]
```

Không có add-on, `core` ném lỗi
`bm-render: this build has no WOFF/WOFF2 font support (use the standard / full build, or load the WOFF
add-on: ...)`. Add-on không bổ sung hỗ trợ CFF: một WOFF2 có outline CFF vẫn cần `standard` hoặc `full`.
Chi tiết ở [Profile và kích thước](../profiles-and-size.md#add-on-woff).

## Font màu và emoji

Emoji màu cần một font màu (COLR v0/v1, CBDT hoặc sbix, ví dụ Noto Color Emoji hoặc Twemoji) và một
profile vẽ được định dạng của nó: font bitmap (CBDT, sbix) được vẽ có màu trên `standard` và `full`, font
COLR chỉ trên `full`. Như mọi font khác, chỉ cần đăng ký là đủ, vì fallback sẽ tìm ra glyph emoji:

<!-- @example fonts#emoji -->
```js
// Noto Color Emoji (CBDT bitmaps, 10 MB; OFL). Registering it is enough: fallback finds it.
renderer.registerFont(readFileSync("./fonts/NotoColorEmoji.ttf"));
// ZWJ sequences (👩‍💻), skin tones (👍🏽), flags (🇻🇳), keycaps (1️⃣) and VS16 (❤️) are one glyph each
const emoji = renderer.renderSync(
  { type: "container", style: { display: "flex", alignItems: "center", padding: "0 20px", width: "100%", height: "100%", backgroundColor: "#fff" },
    children: [{ type: "text", text: "Ship it 🚀 🎉 👩‍💻 👍🏽 🇻🇳 1️⃣ ❤️", style: { fontFamily: "Inter", fontSize: 30 } }] },
  { width: 560, height: 64 },
);
```

![Dòng chữ có emoji màu: tên lửa, pháo giấy, nữ lập trình viên, ngón cái giơ lên với màu da trung bình, cờ Việt Nam, keycap 1 và trái tim](/img/guide/fonts-emoji.png)

Cách hiển thị emoji phụ thuộc font đã đăng ký và variation selector trong chuỗi Unicode. Hãy kiểm tra đúng chuỗi emoji mà ứng dụng sử dụng.

Trên `core`, các bảng màu bị bỏ qua. Font COLR được vẽ từ outline thường, không có màu, nhưng font chỉ có
bitmap như Noto Color Emoji (CBDT) thì không có outline nào, nên emoji của nó **không được vẽ** (cùng cây
node trên `core`; chữ số của keycap và trái tim lấy từ Inter, còn dấu keycap hiện thành ô thiếu glyph):

![Trên core các emoji bị mất; chỉ còn chữ số 1, một ô thiếu glyph và trái tim đen](/img/guide/fonts-emoji-core.png)

## Nạp font trong trình duyệt và từ URL

Trong Node, đọc file bằng `readFileSync` / `readFile`. Trong trình duyệt, tải bytes về:

```js
const bytes = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
renderer.registerFont({ name: "Inter", data: bytes });
```

`registerFont` cũng nhận chuỗi URL hoặc object `URL`. Khi đó nó tải file bằng `fetch` toàn cục và trả về
một **Promise** (`http:` / `https:` trong Node; `fetch` của Node không hỗ trợ URL `file:`). Script ví dụ
kiểm tra điều này với một HTTP server cục bộ:

```js
const families = await renderer.registerFont("https://example.com/fonts/Inter-Regular.ttf");
```

bm-render không tải các rule `@font-face` trong stylesheet: descriptor của chúng được đọc nhưng file thì
không được tải. Hãy tự đăng ký file.

Với Google Fonts, hãy tải file về một lần (TTF trong gói tải về của family, hoặc các URL WOFF2 trong CSS
`https://fonts.googleapis.com/css2?family=...`) rồi đóng gói cùng ứng dụng. WOFF2 cần `standard`, `full`
hoặc add-on.

## Chi phí bộ nhớ

Font đã đăng ký được chép vào bộ nhớ wasm một lần và parse tại chỗ, nên tốn xấp xỉ bằng kích thước file,
trong suốt thời gian còn được đăng ký (theo từng renderer: hai renderer cùng một font giữ hai bản sao):

<!-- @example fonts#memory -->
```js
const m = new Renderer();
const start = m.memoryBytes();
m.registerFont(readFileSync("assets/fonts/NotoSans-Regular.ttf")); // a 607 KiB file
m.registerFont(readFileSync("assets/fonts/NotoSans-Bold.ttf")); // a 617 KiB file
const grown = m.memoryBytes() - start; // the wasm memory grows by about the font bytes
```

Trong lần chạy tạo ra tài liệu này, hai file Noto Sans (tổng 1,2 MB) làm bộ nhớ tăng 1,25 MiB, còn Noto
Color Emoji (10 MB) tăng khoảng 10 MiB. Outline glyph được rasterize khi cần vào một glyph cache 8 MiB
cho mỗi renderer. Bộ nhớ WebAssembly không bao giờ co lại, nên gỡ font sẽ chừa chỗ cho các lần cấp phát
sau chứ không trả bộ nhớ về hệ thống (xem [API: bộ nhớ](./api.md#bộ-nhớ-instance-và-luồng)).

Hệ quả thực tế:

- Chỉ đăng ký những face bạn dùng. Một font CJK đầy đủ nặng 5–20 MB; hãy subset nó (ví dụ bằng
  `pyftsubset`) khi bạn biết trước các ký tự.
- Tạo một renderer cho mỗi bộ font và dùng lại; đừng tạo renderer cho mỗi request.
- Trong worker pool, mỗi worker đăng ký font riêng, nên chi phí nhân lên theo số worker.

## Danh sách kiểm tra

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| Không có chữ nào | renderer này chưa đăng ký font | `registerFont(...)` trước khi render |
| Ô vuông thay cho chữ | không font nào phủ được các ký tự đó | đăng ký font cho hệ chữ đó |
| Sai family | `fontFamily` không khớp tên đã đăng ký | dùng `name` mà `registerFont` trả về |
| Chữ đậm trông nhoè | đậm giả lập | đăng ký file đậm thật |
| `.otf` ném lỗi trên core | outline CFF | dùng `standard` / `full` |
| `.woff2` ném lỗi trên core | không có bộ giải mã WOFF | `loadWoff()` hoặc `standard` / `full` |
| Emoji mất hoặc đen trắng | không phải `full`, hoặc thiếu font màu | profile `full` + một font emoji màu |

Xem thêm: [Typography](./typography.md), [Xử lý sự cố](../troubleshooting.md#chữ-không-hiện-hoặc-hiện-thành-ô-vuông),
[API: `registerFont`](./api.md#registerfont).
