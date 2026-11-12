# Hỗ trợ CSS và tính năng

[English](../en/css-support.md) · [Tiếng Việt](css-support.md)

Trang này cho biết bm-engine 0.1.0 vẽ được những gì, mỗi tính năng cần profile build nào, và đầu ra
khớp với takumi 2.20 tới mức nào. Cột "Trạng thái" lấy từ benchmark tương đương (200 fixture được cả hai
engine render rồi so từng điểm ảnh, cộng thêm các phép thử oracle theo từng module; xem
[Benchmark](benchmark.md)): **identical** (trùng từng byte), **equivalent** (tương đương: SSIM ≥ 0.99
và ≤ 0.5 % điểm ảnh khác — trên thực tế là khác biệt khử răng cưa ở mép cong và mép glyph),
**close** (gần giống: SSIM ≥ 0.95), **một phần** = chạy được nhưng có hạn chế đã ghi rõ, **không** =
chưa hỗ trợ. Profile tối thiểu là bản build nhỏ nhất có chứa tính năng; `full` chứa tất cả. Danh sách
đầy đủ tên thuộc tính nằm ở [phụ lục](#phụ-lục-danh-sách-thuộc-tính-được-hỗ-trợ).

- [Quy ước](#quy-ước)
- [Layout](#layout)
- [Box model và kích thước](#box-model-và-kích-thước)
- [Nền và gradient](#nền-và-gradient)
- [Viền và outline](#viền-và-outline)
- [Bóng đổ và hiệu ứng](#bóng-đổ-và-hiệu-ứng)
- [Transform](#transform)
- [Văn bản](#văn-bản)
- [Font](#font)
- [Màu sắc](#màu-sắc)
- [Giá trị, đơn vị, custom property](#giá-trị-đơn-vị-custom-property)
- [Stylesheet và selector](#stylesheet-và-selector)
- [Tailwind](#tailwind)
- [Đầu vào HTML](#đầu-vào-html)
- [Animation](#animation)
- [Ảnh và SVG](#ảnh-và-svg)
- [Chữ phức, bidi, emoji](#chữ-phức-bidi-emoji)
- [Các hạn chế đã biết](#các-hạn-chế-đã-biết)
- [Phụ lục: danh sách thuộc tính được hỗ trợ](#phụ-lục-danh-sách-thuộc-tính-được-hỗ-trợ)

## Quy ước

- Style inline dùng khoá camelCase (`backgroundColor`); stylesheet, thuộc tính `style=""` của HTML và
  Tailwind dùng cú pháp CSS bình thường. Mọi thuộc tính đều nhận `inherit`, `initial`, `unset`,
  `revert`, `var()` và các hàm toán học.
- Giá trị mặc định theo takumi (vốn theo Blink): **`display: inline`** cho mọi node, **`box-sizing:
  border-box`**, `object-fit: fill`, canvas trong suốt. Node gốc và các item flex / grid được
  blockify.
- Layout tính bằng điểm ảnh thiết bị với độ chính xác 1/64 px (`LayoutUnit` của Blink), việc làm tròn
  về điểm ảnh diễn ra lúc vẽ, giống takumi; `measure()` khớp takumi trong phạm vi 0.001 px trên các
  fixture layout.

## Layout

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| Block layout, gộp margin (margin collapsing), `flow-root` | core | identical / equivalent |
| Định dạng inline (dòng chữ, `inline`, `inline-block`, `inline-flex`, `inline-grid`, `vertical-align`) | core | equivalent (inline nguyên tử tham gia ngắt dòng giữa dòng với mọi `vertical-align`; padding / viền / margin ngang của span đẩy chữ; `white-space` theo từng span, `<br>`, strut theo từng hộp; fixture `inline-flow` / `inline-box-model` đạt SSIM ≥ 0.9999); xem [hạn chế đã biết](#các-hạn-chế-đã-biết) |
| Flexbox (direction, wrap, grow / shrink / basis, `gap`, căn chỉnh kể cả `safe`, `order`, `-webkit-box`) | core | identical (5/5 fixture) |
| Grid: track, `repeat()` kể cả `auto-fill` / `auto-fit`, `fr`, `minmax()`, tự xếp chỗ, span | core | equivalent (4/4) |
| Grid: đường lưới đặt tên, `grid-template-areas`, `grid-area` | core | equivalent (3/3) |
| `position: relative / absolute / fixed`, `inset`, `z-index` | core | identical / equivalent (3/3); `fixed` được định vị theo canvas |
| `position: sticky` | core | parse được, hoạt động như `relative` (không có cuộn) |
| `aspect-ratio`, `min-*` / `max-*`, `fit-content` / `min-content` / `max-content`, kích thước logic | core | identical (5/5 fixture sizing) |
| `overflow: hidden / clip` (kể cả cắt theo góc bo) | core | equivalent |
| Bảng (`display: table*`, layout auto / fixed, `colspan` / `rowspan` qua HTML, `border-collapse`, `border-spacing`, caption, `empty-cells`) | standard | equivalent (8/8 fixture; 339/352 ca oracle layout) |
| Float (`float`, `clear`) | standard (cờ `floats`; cả `full`) | equivalent; 138/138 ca oracle layout; chữ chảy quanh float (hộp dòng ngắn lại cạnh float và nở lại bên dưới, float trong nội dung inline, RTL; 7 fixture `float-text` đạt SSIM ≥ 0.9999) |
| `display: contents` | — | không: được dàn trang và vẽ như `display: block` (phần tử vẫn giữ box, padding và nền của nó) |
| `display: list-item` | core | layout như block; không có ký hiệu đầu dòng (list marker) |
| Chế độ viết (`writing-mode`) | — | không: parse được, chỉ layout theo chiều ngang |

Trên `core`, `display: table*` được layout như `block` và `float` bị bỏ qua (không báo lỗi).

## Box model và kích thước

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| `width` / `height` / `min-*` / `max-*` (px, %, em, rem, vw, vh, `auto`, `fit-content`, ...) | core | identical |
| `margin` (kể cả `auto`), `padding`, dạng logic (`marginInline`, `paddingBlockStart`, ...) | core | identical |
| `box-sizing: border-box` (mặc định) / `content-box` | core | identical |
| `visibility: hidden / collapse` | core | identical |
| `opacity` | core | equivalent (4/4) |

## Nền và gradient

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| `background-color`, shorthand `background`, nhiều lớp nền | core | identical |
| `linear-gradient`, `radial-gradient`, `conic-gradient`, `repeating-*` | core | equivalent (7/7 fixture; các điểm dừng bên trong có thể lệch 1 mức màu) |
| `background-image: url(...)`, `background-size` / `-position` / `-repeat` (kể cả `space`, `round`) / `-origin` / `-clip` | core | equivalent (các fixture ảnh) |
| `background-clip: text` | core | equivalent |
| Không gian nội suy gradient (`linear-gradient(in oklab, ...)`) | standard | trùng takumi trong phạm vi 1–2 mức; bị bỏ qua trên core |
| `background-blend-mode` | standard | identical |

## Viền và outline

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| Độ dày / màu `border`, mọi kiểu: `solid`, `dashed`, `dotted`, `double`, `groove`, `ridge`, `inset`, `outset` | core | identical / equivalent (nét đứt trên góc bo có thể lệch pha ~0.1 px) |
| `border-radius` (elip, từng góc, phần trăm, góc logic) | core | identical (4/4) |
| `outline`, `outline-offset` (px) | core | equivalent; chưa hỗ trợ `outline-offset` theo % |

## Bóng đổ và hiệu ứng

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| `box-shadow` (ngoài, inset, spread, nhiều lớp) | core | identical / equivalent (4/4) |
| `text-shadow` | core | equivalent |
| `filter`: `blur()`, `brightness()`, `contrast()`, `grayscale()`, `hue-rotate()`, `invert()`, `opacity()`, `saturate()`, `sepia()`, `drop-shadow()` | core | identical / equivalent; chưa hỗ trợ `filter: url(...)` |
| `backdrop-filter` | standard | identical |
| `mix-blend-mode` (16 chế độ + `plus-lighter`, `plus-darker`), `isolation` | standard | identical |
| `clip-path`: `inset()`, `circle()`, `ellipse()`, `polygon()` kèm geometry box | standard | identical |
| `clip-path: path()` | standard (cần SVG) | có hỗ trợ; `clip-path: url(#id)` thì không |
| `mask-image` / `mask-*` / `-webkit-mask-*` (gradient và ảnh, `mask-mode`, `mask-type`) | standard | identical; `mask-composite` bị bỏ qua |

Trên `core`, các thuộc tính hiệu ứng cần `standard` trong bảng này được chấp nhận nhưng bị bỏ qua.

## Transform

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| Các hàm `transform` 2D (`translate*`, `rotate`, `scale*`, `skew*`, `matrix`), `transform-origin` | core | equivalent (3/3) |
| Các thuộc tính riêng `translate`, `rotate`, `scale` | core | có hỗ trợ |
| Transform 3D (`rotateX`, `matrix3d`, `perspective()`) | — | không: `transform` inline có hàm 3D sẽ ném lỗi (giống takumi, vốn chỉ hỗ trợ 2D) |

## Văn bản

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| Ngắt dòng (UAX #14), `white-space` (mọi chế độ), `word-break`, `overflow-wrap`, `tab-size` | core | equivalent; bề rộng và vị trí ngắt dòng khớp takumi (825/825 ca oracle) |
| `text-align` (kể cả `justify`), `line-height`, `letter-spacing`, `word-spacing`, `text-transform` | core | equivalent |
| `text-indent` | — | parse được nhưng không có tác dụng trong 0.1.0 (dòng đầu không thụt vào) |
| `text-overflow: ellipsis`, `line-clamp` / `-webkit-line-clamp` | core | equivalent (3/3); giá trị chuỗi tùy ý (`text-overflow: " »"`) được chấp nhận nhưng vẽ như `clip` |
| `text-decoration` (line, style kể cả `wavy`, màu, độ dày), `text-underline-offset` / `-position`, `text-decoration-skip-ink` | core | equivalent |
| `-webkit-text-stroke`, `-webkit-text-fill-color` | core | equivalent (nét viền có thể lệch 1 mức); `paint-order` parse được nhưng nét viền luôn vẽ đè lên phần tô, giống takumi 2.20 |
| Hộp inline có nền / viền / padding, `box-decoration-break` | core | equivalent; padding / viền / margin ngang của span đẩy chữ (mép fragment đầu / cuối, `box-decoration-break: clone`) |
| `text-wrap: balance` / `pretty` | standard | quyết định ngắt dòng trùng takumi (216/216) |
| Tự tạo đậm / nghiêng (synthetic) khi thiếu face | core | equivalent |
| `font-feature-settings`, `font-variant-*`, `font-kerning`, ligature (GSUB 1–8, GPOS 1–9) | core | equivalent |
| `hyphens`, `line-break`, `text-align-last` | — | parse được, chưa có tác dụng trong 0.1.0 |

## Font

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| TrueType (`glyf`), bộ sưu tập (`.ttc`) | core | equivalent |
| CFF / CFF2 (`.otf`) | standard | bề rộng lệch trong 1/64 px |
| WOFF / WOFF2 | standard (core: [add-on](profiles-and-size.md#add-on-woff)) | 17/19 font WOFF2 thử nghiệm của takumi giải mã trùng từng byte với bộ giải mã tham chiếu (2 font còn lại khác một bit cờ) |
| Font biến thiên (`fvar`, `avar`, `gvar`, `HVAR`, `MVAR`), `font-variation-settings`, `font-optical-sizing` | standard | 1 400 phép so bề rộng lệch trong 1/64 px; trên core chỉ vẽ instance mặc định |
| Font màu: COLR v0 / v1, CBDT, sbix | full | SSIM ≥ 0.991 so với Chrome (takumi không vẽ được COLR v1) |
| `@font-face` trong stylesheet | — | không được tải: hãy đăng ký font bằng `registerFont` / `fonts` |

## Màu sắc

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| Tên màu, `#rgb[a]`, `#rrggbb[aa]`, `rgb()` / `rgba()`, `hsl()` / `hsla()`, `hwb()`, `currentColor`, `transparent` | core | identical |
| `lab()`, `lch()`, `oklab()`, `oklch()`, `color()`, `color-mix()`, `light-dark()` | standard | 495/495 màu trùng ở 8 bit. Trên core các giá trị này không hợp lệ: dùng trong style inline sẽ ném lỗi |
| Cú pháp màu tương đối (`rgb(from red r g b / 50%)`) | — | không (giá trị không hợp lệ) |

## Giá trị, đơn vị, custom property

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| `px`, `%`, `em`, `rem`, `vw`, `vh`, `vmin`, `vmax`, `pt`, `pc`, `in`, `cm`, `mm`, `Q`, `ch`, `ex`, `lh`, `rlh`, `cq*` | core | identical (ngữ nghĩa DPR như takumi: `vw`/`vh` tính theo điểm ảnh đầu ra) |
| `calc()`, `min()`, `max()`, `clamp()` và các hàm toán học khác | core | identical |
| Custom property (`--x`) và `var()` có giá trị dự phòng, trong style inline | core | identical |
| `!important` | core | identical |

## Stylesheet và selector

Truyền stylesheet qua tùy chọn `css` (chuỗi, hoặc object luật kiểu takumi `{ selector, style }`) hoặc
dùng `<style>` trong nguồn HTML. Cần `standard`. Trạng thái: 252/252 phép kiểm tra luật thắng trong
cascade trùng takumi; 4 fixture (1 identical, 3 equivalent).

- **Selector**: type, universal, class, id, thuộc tính (đủ 7 toán tử, cờ `i` / `s`); combinator
  hậu duệ, `>`, `+`, `~`; danh sách selector; `:root`, `:empty`, `:first-child`, `:last-child`,
  `:only-child`, `:first-of-type`, `:last-of-type`, `:only-of-type`, `:nth-child(An+B [of S])`,
  `:nth-last-child()`, `:nth-of-type()`, `:nth-last-of-type()`, `:not()`, `:is()`, `:where()`, `:has()`,
  `:lang()`, `:dir()`, `:scope`, trạng thái form (`:checked`, `:disabled`, ...). Pseudo-element
  `::before` / `::after` (với `content`, `attr()`).
- Các pseudo-class động (`:hover`, `:focus`, `:visited`, ...) và các pseudo-element khác (`::marker`,
  `::placeholder`, `::first-line`, ...) parse được nhưng không bao giờ khớp, giống takumi.
- **At-rule**: `@media` (`width`, `height`, `aspect-ratio`, `resolution`, `orientation`, cú pháp khoảng,
  `and` / `or` / `not`; so với kích thước canvas tính bằng CSS px), `@supports`, `@layer`, CSS Nesting
  (`&`), `@keyframes`, `@theme` (biến theme của Tailwind), `@import "tailwindcss"` (bật Tailwind
  Preflight). Descriptor của `@font-face` được đọc nhưng font không được tải về. `@page`, `@property`,
  `@container`, `@scope`, `@apply`, `@counter-style` và các at-rule khác bị bỏ qua, giống takumi.
- Khai báo không hợp lệ bị loại bỏ từng cái một (cơ chế phục hồi lỗi của CSS); stylesheet không bao
  giờ làm render ném lỗi.
- Chưa hỗ trợ: `counter()` / `counters()` trong `content`, ký hiệu đầu dòng của danh sách.

## Tailwind

Đặt class vào trường `tw` của node (trong HTML: thuộc tính `tw="..."`; `class` chỉ dùng cho selector
của stylesheet). Cần `standard`. Trạng thái: 656/657 chuỗi class biên dịch ra đúng các khai báo như
takumi; 4 fixture (2 identical, 2 equivalent). Bộ biên dịch là bản port tập con Tailwind v4 của takumi,
nên hỗ trợ đúng những gì takumi hỗ trợ:

- **Nhóm utility**: layout và display (`flex`, `grid`, `block`, `hidden`, `contents`, ...),
  position và inset, kích thước (`w-*`, `h-*`, `size-*`, `min-*`, `max-*`, `aspect-*`), khoảng cách
  (`m*-*`, `p*-*`, `gap-*`), flex và grid (`basis-*`, `grow`, `shrink`, `grid-cols-*`, `col-span-*`,
  `items-*`, `justify-*`, `self-*`, ...), chữ (`text-*`, `font-*`, `leading-*`, `tracking-*`,
  `line-clamp-*`, `truncate`, `whitespace-*`, các utility trang trí chữ, `uppercase`, ...), nền (`bg-*`,
  gradient với `from-*` / `via-*` / `to-*`, `bg-linear-*`, `bg-radial`, `bg-conic`), viền và bo góc
  (`border*`, `rounded*`, `outline*`), hiệu ứng (`shadow-*`, `inset-shadow-*`, `text-shadow-*`,
  `opacity-*`, `mix-blend-*`, `bg-blend-*`, `mask-*`), filter và backdrop filter, transform
  (`translate-*`, `rotate-*`, `scale-*`, `origin-*`), `object-*`, `overflow-*`, `list-*`.
- **Giá trị**: theme mặc định (thang khoảng cách, toàn bộ bảng màu với modifier `/opacity`, cỡ chữ,
  bán kính bo, bóng đổ, breakpoint), giá trị tùy ý (`w-[37px]`, `bg-[#123456]`, dấu gạch dưới thay cho
  dấu cách), tiền tố `!important`.
- **Variant**: breakpoint `sm` `md` `lg` `xl` `2xl` (min-width so với bề rộng canvas), variant cấu trúc
  `first` `last` `only` `odd` `even` `*-of-type` `empty` `not-*` `nth-*` và `[&:...]`,
  `before:` / `after:`.
- **Chưa hỗ trợ (giống takumi)**: `hover:`, `focus:`, `dark:`, `group-*:`, `peer-*:`, breakpoint
  `max-*:`; `z-*`, `order-*`, `skew-*`, `ring-*`, `space-*`, `divide-*`, `place-*`, `cursor-*`;
  `animate-*` (bị bỏ qua im lặng; hãy dùng thuộc tính `animation` cùng `css`); shorthand `(--var)` và
  class `[prop:value]`. Class không biết bị bỏ qua im lặng.
- `style` thắng `tw`; utility có tiền tố `!` thắng khai báo inline thường.

## Đầu vào HTML

Truyền một chuỗi HTML làm nguồn (mọi chuỗi JS đều được hiểu là HTML, giống takumi). Cần `standard`.
Trạng thái: 55/58 mẫu cấu trúc cho ra cây trùng takumi; 8 fixture equivalent.

- Tokenizer và bộ dựng cây chịu lỗi (cùng tập con thực dụng của thuật toán WHATWG như takumi): tự đóng
  thẻ cho `p`, `li`, `dt`/`dd`, `option`, các phần của bảng; tự thêm `tbody`; phần tử void; tham chiếu
  ký tự (dạng số + 338 tên); chế độ fragment và document.
- Áp dụng phần tử `<style>` (kể cả thuộc tính `media`); thuộc tính `style=""`; `class`, `id` và các
  thuộc tính khác cho selector; `dir` và `lang`.
- Style user-agent của Chromium được áp dụng dưới dạng preset (`h1`, `p`, `b`, `ul`, `table`, ...).
- `<img src>` tra trong tùy chọn `images` hoặc dùng URL `data:`; phần tử `<svg>` inline được vẽ như ảnh
  SVG.
- Nội dung `<script>`, `<template>`, comment và nội dung `<head>` không được vẽ; không có gì được thực
  thi hay tải về.
- Chưa cài (cùng chỗ thiếu như takumi): adoption agency / dựng lại formatting element, foster
  parenting, MathML, điều khiển form dạng widget.

## Animation

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| `@keyframes` + các thuộc tính `animation*` lấy mẫu tại `timeMs` (delay, direction, fill mode, số lần lặp, hàm thời gian kể cả `cubic-bezier()` và `steps()`) | full | 42 fixture: 32 identical, 10 equivalent |
| Tùy chọn render `keyframes` (dạng cũ của takumi, đã deprecated) | full | có hỗ trợ |
| `renderAnimation` → WebP / APNG / GIF động | full | số khung và độ trễ trùng takumi |
| Tên dựng sẵn `spin`, `ping`, `pulse`, `bounce` (keyframes của Tailwind) không cần luật `@keyframes` | full | có hỗ trợ, giống takumi |
| Animation trên `::before` / `::after`, custom property được animate | — | không |
| `transition*` | — | parse được; ảnh tĩnh không có transition |
| `animation-play-state: paused` | full | bị bỏ qua (vẫn lấy mẫu), giống takumi |

Trên `standard`, luật `@keyframes` parse được nhưng animation không được áp dụng; trên `core` thuộc
tính `animation` bị bỏ qua.

## Ảnh và SVG

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| PNG, JPEG (baseline và progressive) | core | equivalent (giải mã JPEG lệch tối đa 4/255 so với takumi) |
| `object-fit`, `object-position`, cắt ảnh theo `border-radius` | core | equivalent |
| WebP lossless, GIF (khung đầu) | standard | có hỗ trợ |
| WebP lossy (VP8; trùng từng bit với libwebp), nguồn GIF / APNG / WebP động | full | trùng các bộ giải mã tham chiếu |
| Ảnh SVG (markup `<svg>`, `data:image/svg+xml`, nền và mask dạng `url()`) | standard | 397/422 file SVG thử nghiệm của takumi identical hoặc equivalent |
| Phạm vi SVG | standard | hình cơ bản, path, `use` / `symbol`, gradient, pattern, `clipPath`, `mask`, marker, `<svg>` / `<image>` lồng nhau, `<style>` với selector đơn giản, filter `feGaussianBlur`, `feOffset`, `feFlood`, `feColorMatrix`, `feComposite`, `feMerge`, `feBlend`, `feDropShadow`, `feComponentTransfer`. `<text>` được vẽ bằng font đã đăng ký theo mô hình đơn giản (mỗi phần tử một run: `x` / `y`, `font-family`, `font-size`, `font-weight`, `text-anchor`, `fill` màu đặc; nội dung `<tspan>` nối vào run cha với style của cha; chữ tô gradient hoặc chỉ có stroke không được vẽ; xem [Biểu đồ](charts.md#svg-text-hỗ-trợ-những-gì)). Chưa hỗ trợ: `feTurbulence`, `feImage`, `feMorphology`, `feConvolveMatrix`, `feDisplacementMap`, filter chiếu sáng, `feTile`, tham chiếu ra ngoài |
| `image-rendering` | core | parse được; ảnh raster luôn được lấy mẫu lại mượt trong 0.1.0 (`pixelated` chỉ có tác dụng bên trong SVG) |
| URL từ xa | — | không bao giờ tải về: truyền byte qua `images` |

## Chữ phức, bidi, emoji

| Tính năng | Profile tối thiểu | Trạng thái |
|:--|:--|:--|
| Latin, Kirin, Hy Lạp, tiếng Việt (dựng sẵn), ngắt dòng CJK | core | equivalent |
| Bidi (UAX #9), `direction`, `dir`, cô lập `unicode-bidi` | full | 91 679/91 679 ca kiểm tra chuẩn bidi |
| Shaping Ả Rập, Hebrew, Devanagari, Bengali, Thái; chuẩn hoá Unicode (tiếng Việt tổ hợp) | full | bề rộng glyph khớp takumi (lệch 0.000 px ở mọi nhóm); các hệ chữ Ấn khác dùng shaper mặc định |
| Emoji màu (khi đã đăng ký font emoji) | full | SSIM ≥ 0.991; vài chuỗi ZWJ chưa gộp thành một glyph, lựa chọn font emoji có thể khác takumi ở vài ký tự (©️, VS15) |

Trên `core` và `standard`, chữ viết phải-sang-trái và chữ phức được shape bằng shaper OpenType mặc định
theo thứ tự logic (không sắp xếp lại).

## Các hạn chế đã biết

Tình trạng ở 0.1.0 (xem [docs/BENCHMARK.md](../BENCHMARK.md) để biết trạng thái cuối cùng):

- **Layout inline (hạn chế còn lại)** — hộp inline hướng RTL bao quanh chữ LTR đặt mép start / end sai phía
  thị giác, và fragment của hộp chưa được tách qua các đoạn bidi bị sắp xếp lại; khoảng trắng treo của RTL +
  `white-space: pre-wrap`; line-clamp / `-webkit-box` quanh float; block-in-inline (span chứa block) vẫn biến
  span thành block; thứ tự vẽ float chỉ xấp xỉ (float vẽ sau nội dung in-flow của stacking context);
  `text-wrap: balance / pretty` quay về ngắt dòng tham lam trong đoạn có hộp inline / inline nguyên tử hoặc
  cạnh float; padding / margin theo % trên hộp inline được tính bằng 0; chuỗi inline-block lồng nhau giới hạn
  khoảng 255 cấp (lỗi "nested too deeply" rõ ràng), trong khi lồng thường hỗ trợ 512.
- **Bảng và RTL** — `dir="rtl"` / `direction: rtl` trên bảng chưa đưa cột đầu tiên sang bên phải ở bản
  0.1.0 (xem [Bảng](tables.md)).
- **Pseudo-class cấu trúc trên text node** — `:first-child`, `:last-child`, `:nth-child()` (và các variant
  Tailwind `first:` / `last:` / `odd:`) khớp với mọi anh em khi các phần tử là `text` node trần; hãy bọc
  text trong container.
- **`measure()` và transform** — ma trận `transform` do `measure()` trả về không gồm `transform` /
  `translate` / `rotate` / `scale` CSS của node (takumi có tính); xem [measure()](measure.md).
- **Hướng chữ trong flex layout** — `direction: rtl` / `dir: "rtl"` chưa đảo trục chính của hàng flex
  trong 0.1.0 (takumi có đảo).
- Chưa hỗ trợ: `display: contents`, ký hiệu đầu dòng và counter, `writing-mode`, transform 3D,
  `filter: url()` / `clip-path: url()`, cú pháp màu tương đối, `outline-offset` theo %, `@apply`,
  `animate-*` của Tailwind, animation trên pseudo-element, xuất PDF.
- Các sai khác 1 mức còn lại: phần trong của gradient, viền nét đứt trên góc bo, chữ bị xoay,
  `text-stroke`.

## Phụ lục: danh sách thuộc tính được hỗ trợ

296 tên thuộc tính mà bộ parse style nhận biết, sinh ra từ `src/style/props.zig` (dạng camelCase như
dùng trong object `style` inline; stylesheet dùng dạng kebab-case). Được nhận biết không có nghĩa là
lúc nào cũng đã được cài đặt: xem phần ghi chú ở cuối.

**Display và định vị:** `display`, `position`, `top`, `right`, `bottom`, `left`, `inset`,
`insetBlock`, `insetBlockEnd`, `insetBlockStart`, `insetInline`, `insetInlineEnd`, `insetInlineStart`,
`zIndex`, `float`, `clear`, `visibility`, `overflow`, `overflowX`, `overflowY`, `overflowBlock`,
`overflowInline`, `contain`, `verticalAlign`, `order`, `boxSizing`, `aspectRatio`.

**Kích thước:** `width`, `height`, `minWidth`, `minHeight`, `maxWidth`, `maxHeight`, `inlineSize`,
`blockSize`, `minInlineSize`, `minBlockSize`, `maxInlineSize`, `maxBlockSize`.

**Khoảng cách:** `margin`, `marginTop`, `marginRight`, `marginBottom`, `marginLeft`, `marginBlock`,
`marginBlockStart`, `marginBlockEnd`, `marginInline`, `marginInlineStart`, `marginInlineEnd`,
`padding`, `paddingTop`, `paddingRight`, `paddingBottom`, `paddingLeft`, `paddingBlock`,
`paddingBlockStart`, `paddingBlockEnd`, `paddingInline`, `paddingInlineStart`, `paddingInlineEnd`,
`gap`, `rowGap`, `columnGap`.

**Flexbox và căn chỉnh:** `flex`, `flexBasis`, `flexDirection`, `flexFlow`, `flexGrow`, `flexShrink`,
`flexWrap`, `alignContent`, `alignItems`, `alignSelf`, `justifyContent`, `justifyItems`, `justifySelf`,
`placeContent`, `placeItems`, `placeSelf`, `WebkitBoxOrient`.

**Grid:** `grid`, `gridArea`, `gridAutoColumns`, `gridAutoFlow`, `gridAutoRows`, `gridColumn`,
`gridColumnEnd`, `gridColumnStart`, `gridRow`, `gridRowEnd`, `gridRowStart`, `gridTemplate`,
`gridTemplateAreas`, `gridTemplateColumns`, `gridTemplateRows`.

**Bảng:** `tableLayout`, `borderCollapse`, `borderSpacing`, `captionSide`, `emptyCells`.

**Viền và outline:** `border`, `borderTop`, `borderRight`, `borderBottom`, `borderLeft`,
`borderColor`, `borderStyle`, `borderWidth`, `borderTopColor`, `borderTopStyle`, `borderTopWidth`,
`borderRightColor`, `borderRightStyle`, `borderRightWidth`, `borderBottomColor`, `borderBottomStyle`,
`borderBottomWidth`, `borderLeftColor`, `borderLeftStyle`, `borderLeftWidth`, `borderBlock`,
`borderBlockColor`, `borderBlockStyle`, `borderBlockWidth`, `borderBlockStart`,
`borderBlockStartColor`, `borderBlockStartStyle`, `borderBlockStartWidth`, `borderBlockEnd`,
`borderBlockEndColor`, `borderBlockEndStyle`, `borderBlockEndWidth`, `borderInline`,
`borderInlineColor`, `borderInlineStyle`, `borderInlineWidth`, `borderInlineStart`,
`borderInlineStartColor`, `borderInlineStartStyle`, `borderInlineStartWidth`, `borderInlineEnd`,
`borderInlineEndColor`, `borderInlineEndStyle`, `borderInlineEndWidth`, `borderRadius`,
`borderTopLeftRadius`, `borderTopRightRadius`, `borderBottomRightRadius`, `borderBottomLeftRadius`,
`borderStartStartRadius`, `borderStartEndRadius`, `borderEndStartRadius`, `borderEndEndRadius`,
`outline`, `outlineColor`, `outlineOffset`, `outlineStyle`, `outlineWidth`.

**Nền:** `background`, `backgroundAttachment`, `backgroundBlendMode`, `backgroundClip`,
`backgroundColor`, `backgroundImage`, `backgroundOrigin`, `backgroundPosition`,
`backgroundPositionX`, `backgroundPositionY`, `backgroundRepeat`, `backgroundSize`.

**Mask và cắt:** `clipPath`, `WebkitClipPath`, `mask`, `maskClip`, `maskComposite`,
`maskImage`, `maskMode`, `maskOrigin`, `maskPosition`, `maskRepeat`, `maskSize`, `maskType`,
`WebkitMask`, `WebkitMaskClip`, `WebkitMaskComposite`, `WebkitMaskImage`, `WebkitMaskOrigin`,
`WebkitMaskPosition`, `WebkitMaskRepeat`, `WebkitMaskSize`.

**Hiệu ứng:** `opacity`, `boxShadow`, `filter`, `backdropFilter`, `WebkitBackdropFilter`,
`mixBlendMode`, `isolation`.

**Transform:** `transform`, `transformOrigin`, `translate`, `rotate`, `scale`.

**Ảnh:** `objectFit`, `objectPosition`, `imageRendering`.

**Văn bản:** `color`, `direction`, `unicodeBidi`, `writingMode`, `textAlign`, `textAlignLast`,
`textIndent`, `textTransform`, `textShadow`, `textOverflow`, `textWrap`, `textWrapMode`,
`textWrapStyle`, `whiteSpace`, `whiteSpaceCollapse`, `wordBreak`, `wordSpacing`, `wordWrap`,
`overflowWrap`, `letterSpacing`, `lineHeight`, `lineBreak`, `lineClamp`, `WebkitLineClamp`,
`hyphens`, `WebkitHyphens`, `tabSize`, `textDecoration`, `textDecorationColor`,
`textDecorationLine`, `textDecorationSkipInk`, `textDecorationStyle`, `textDecorationThickness`,
`textUnderlineOffset`, `textUnderlinePosition`, `WebkitTextFillColor`, `WebkitTextStroke`,
`WebkitTextStrokeColor`, `WebkitTextStrokeWidth`, `paintOrder`, `boxDecorationBreak`,
`WebkitBoxDecorationBreak`.

**Font:** `font`, `fontFamily`, `fontSize`, `fontStyle`, `fontWeight`, `fontStretch`,
`fontFeatureSettings`, `fontKerning`, `fontOpticalSizing`, `fontVariant`, `fontVariantCaps`,
`fontVariantEastAsian`, `fontVariantLigatures`, `fontVariantNumeric`, `fontVariantPosition`,
`fontVariationSettings`, `fontSynthesis`, `fontSynthesisSmallCaps`, `fontSynthesisStyle`,
`fontSynthesisWeight`.

**Nội dung sinh ra và danh sách:** `content`, `counterIncrement`, `counterReset`, `counterSet`,
`listStyle`, `listStyleImage`, `listStylePosition`, `listStyleType`.

**Animation và transition:** `animation`, `animationDelay`, `animationDirection`,
`animationDuration`, `animationFillMode`, `animationIterationCount`, `animationName`,
`animationPlayState`, `animationTimingFunction`, `transition`, `transitionBehavior`,
`transitionDelay`, `transitionDuration`, `transitionProperty`, `transitionTimingFunction`.

**Tương tác (nhận để tương thích):** `cursor`, `pointerEvents`, `userSelect`,
`WebkitUserSelect`, `willChange`.

Ghi chú:

- **Nhận nhưng bỏ qua** (giá trị thậm chí không được parse): `backgroundAttachment`, `willChange`,
  `pointerEvents`, `cursor`, `userSelect`, `WebkitUserSelect`, `transitionBehavior`, `maskComposite`,
  `WebkitMaskComposite`.
- **Parse được nhưng chưa có tác dụng thấy được trong 0.1.0** (xác định bằng cách kiểm tra renderer đọc
  những giá trị computed nào): `writingMode`, `textIndent`, `hyphens` / `WebkitHyphens`, `lineBreak`, `textAlignLast`,
  `unicodeBidi`, `fontSynthesis*` (luôn tự tạo đậm / nghiêng), `counterReset` / `counterIncrement` /
  `counterSet`, `listStyle*` (không có ký hiệu đầu dòng), `transition*`; `imageRendering` chỉ có tác dụng
  bên trong ảnh SVG.
- Thuộc tính của một tính năng bị loại khỏi profile đang nạp được chấp nhận và bỏ qua (ví dụ `float`
  trên `core`), trừ các giá trị cần bộ parse không có mặt (hàm màu hiện đại trên `core`), vốn bị coi là
  không hợp lệ.
- Mọi khoá khác đều bị bỏ qua im lặng, kể cả khoá kebab-case trong object `style` inline.


## Xem thêm

Các trang hướng dẫn đi sâu vào từng chủ đề, kèm ví dụ chạy được và ảnh kết quả:
[Khái niệm](concepts.md) · [Style và layout](styles.md) · [HTML và Tailwind](html-and-tailwind.md) ·
[Font](fonts.md) · [Typography](typography.md) · [Ảnh](images.md) · [Bảng và float](tables.md) ·
[Hiệu ứng](effects.md) · [Định dạng đầu ra](formats.md) · [Animation](animation.md) · [measure()](measure.md) ·
[Biểu đồ](charts.md) · [Mẫu](templates.md) · [Hiệu năng](performance.md)
