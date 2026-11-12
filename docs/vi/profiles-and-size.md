# Profile và kích thước binary

[English](../en/profiles-and-size.md) · [Tiếng Việt](profiles-and-size.md)

bm-engine được biên dịch thành ba binary với tập tính năng khác nhau để bạn chỉ phải tải những gì mình
dùng: `core` (487.0 KiB), `standard` (933.9 KiB) và `full` (1 140.5 KiB), so với 4 234.9 KiB của bản wasm
takumi 2.20. Trang này liệt kê nội dung từng profile, chi phí của từng tính năng tùy chọn, cách một
profile nhỏ xử lý đầu vào nó không hỗ trợ, cách tự build bản riêng, và lý do chỉ có WOFF được tách thành
add-on tải lười. Mọi kích thước đều đo sau `wasm-opt -Oz`; KiB = 1024 byte.

## Kích thước

| Bản build | Gốc | gzip -9 | brotli (q11) | so với takumi (gốc) |
|:--|--:|--:|--:|:--|
| `core` — `bm_engine.core.wasm` | 487.0 KiB | 228.3 KiB | 194.3 KiB | nhỏ hơn 8.7× |
| `standard` — `bm_engine.standard.wasm` | 933.9 KiB | 463.5 KiB | 397.7 KiB | nhỏ hơn 4.5× |
| `full` — `bm_engine.wasm` | 1 140.5 KiB | 558.2 KiB | 469.6 KiB | nhỏ hơn 3.7× |
| Add-on WOFF — `bm_woff.wasm` | 84.2 KiB | 67.7 KiB | 65.5 KiB | — |
| takumi 2.20 (`@takumi-rs/wasm`) | 4 234.9 KiB | 1 860.9 KiB | 1 409.3 KiB | — |

Lớp bọc JavaScript chỉ vài KiB ESM không phụ thuộc gì và giống nhau cho mọi profile. Các binary không
import gì từ môi trường chạy.

### Addon native (Node.js)

Trên Node.js, `bm-engine` dùng addon native khi có addon cho nền tảng đang chạy (một optional dependency cho mỗi
nền tảng; npm chỉ tải gói khớp với máy). Addon luôn có tập tính năng `full`; các profile ở trên chỉ áp dụng cho bản
wasm. Mỗi addon lớn hơn bản wasm `full` vì được biên dịch để chạy nhanh (ReleaseFast) chứ không phải để nhỏ, và bản
wasm vẫn nằm trong gói chính để làm phương án dự phòng. Nên dùng backend nào và so sánh hai backend:
[Native so với WebAssembly](./native-vs-wasm.md).

<!-- native-bench:sizes -->
| File | Target | KiB | gzip -9 KiB | brotli KiB | Trạng thái |
|:--|--:|--:|--:|--:|--:|
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 2 083 | 1 120 | 914 | đã chạy (benchmark này) |
| bm wasm `core` | wasm32 | 487 | 228 | 194 |  |
| bm wasm `standard` | wasm32 | 934 | 463 | 398 |  |
| bm wasm `full` | wasm32 | 1 140 | 558 | 470 |  |
| bm wasm `add-on WOFF` | wasm32 | 84.2 | 67.7 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Addon native lấy từ `native/dist/manifest.json` (build ngày 2026-11-12 với Zig 0.17.1, ReleaseFast). Mỗi người dùng chỉ tải một addon (gói optional cho nền tảng của họ) cộng với bản wasm dự phòng nằm trong gói chính.
<!-- /native-bench:sizes -->

## Mỗi profile gồm những gì

| Tính năng (khoá trong `features`) | core | standard | full |
|:--|:-:|:-:|:-:|
| Cây node (`{ type, style, children }`), nguồn `{ json }`, `style` / `preset` inline, `var()`, `calc()` | ✓ | ✓ | ✓ |
| Block, inline, flex, grid (kể cả đường lưới / vùng đặt tên), định vị absolute / fixed, inline-block | ✓ | ✓ | ✓ |
| Font TrueType / TTC tĩnh với shaper OpenType mặc định (GSUB / GPOS, kerning, ligature) | ✓ | ✓ | ✓ |
| Nền, gradient, mọi kiểu viền, outline, bo góc, bóng hộp / bóng chữ, filter, opacity, transform 2D, trang trí chữ, viền chữ | ✓ | ✓ | ✓ |
| Ảnh PNG / JPEG vào; PNG / JPEG / WebP (lossless) / raw ra; `measure` | ✓ | ✓ | ✓ |
| Stylesheet, selector, `@media` / `@layer` / `@supports`, `::before` / `::after` (`css`) | | ✓ | ✓ |
| Tailwind `tw` (`tw`) | | ✓ | ✓ |
| Nguồn là chuỗi HTML (`html`) | | ✓ | ✓ |
| Ảnh SVG, `clip-path: path()` (`svg`) | | ✓ | ✓ |
| WOFF / WOFF2 (`woff`) | add-on | ✓ | ✓ |
| Font biến thiên (`variableFonts`) | | ✓ | ✓ |
| Outline CFF / CFF2 (`cff`) | | ✓ | ✓ |
| clip-path, mask, blend mode, backdrop-filter, isolation (`effects`) | | ✓ | ✓ |
| `lab()` / `lch()` / `oklab()` / `oklch()` / `color()` / `color-mix()` / `light-dark()`, không gian nội suy gradient (`modernColor`) | | ✓ | ✓ |
| Bảng (`tables`) | | ✓ | ✓ |
| Float (`floats`) | | ✓ | ✓ |
| Nguồn ảnh WebP lossless và GIF (`webpGifDecode`) | | ✓ | ✓ |
| `text-wrap: balance / pretty` (`textWrapBalance`) | | ✓ | ✓ |
| Glyph màu / emoji: COLR v0/v1, CBDT, sbix (`colorFonts`) | | | ✓ |
| Bidi, shaping Ả Rập / Hebrew / Ấn / Thái, chuẩn hoá Unicode (`complexText`) | | | ✓ |
| CSS animation tại `timeMs`, `renderAnimation`, nguồn ảnh động (`animation`) | | | ✓ |
| Giải mã WebP lossy, codec GIF / APNG / WebP động, xuất ICO (`extraCodecs`) | | | ✓ |
| `renderSvg` (`renderSvg`) | | | ✓ |

## Chi phí biên của từng tính năng

Bảng chi phí biên dưới đây được đo ở giai đoạn 2, trước công việc định dạng inline vốn thêm khoảng 26–30 KB cho mỗi profile.

Tính bằng KB sau `wasm-opt`, đo theo hai cách: chỉ thêm tính năng đó vào `core` / chỉ bỏ nó khỏi `full`.

| Tính năng | + vào core | − khỏi full | Ghi chú |
|:--|--:|--:|:--|
| `css` | 62.5 | 60.7 | |
| `tw` | 37.5 | 32.2 | |
| `html` | 27.8 | 27.2 | |
| `svg` | 100.6 | 102.7 | |
| `woff` | 80.1 | 79.5 | 52 KB trong đó là từ điển brotli bắt buộc |
| `variable_fonts` | 15.8 | 14.4 | |
| `cff` | 9.7 | 8.3 | |
| `effects` | 17.4 | 17.6 | |
| `modern_color` | 12.1 | 10.1 | |
| `tables` | 48.1 | 46.1 | |
| `floats` | 6.5 | 4.8 | |
| `color_fonts` | 30.9 | 35.9 | |
| `complex_text` | 52.2 | 53.0 | |
| `animation` | 42.0 | 52.9 | |
| `extra_codecs` | 0.8 | 33.5 | phần lớn chỉ đáng giá khi đi cùng `animation` |
| `render_svg` | 57.0 | 59.1 | |

Vì sao `core` không nhỏ hơn được (bản build duy nhất ở giai đoạn 1 là 320.9 KiB): phần lõi dùng chung đã
lớn thêm khoảng 113 KB tính năng thật — mọi kiểu viền, outline và trang trí chữ (+31 KB), engine
GSUB/GPOS đầy đủ (+26 KB), `var()` / `calc()` / đường lưới đặt tên / thuộc tính logic (+24 KB), khử răng
cưa trùng tiny-skia và bộ stroker (+17 KB), layout (+9 KB), DOM / measure (+20 KB) — trong khi bỏ đầu vào
WebP / GIF (−36 KB). Muốn thu nhỏ hơn nữa thì phải đổi thuật toán hoặc đổi kết quả render của `core`.

## Profile nhỏ xử lý đầu vào không hỗ trợ thế nào

Kiểm tra bằng `bench/probe/profiles.mjs` trên cả ba binary (không đầu vào nào gây trap):

| Đầu vào | core | standard |
|:--|:--|:--|
| Nguồn là chuỗi HTML | ném lỗi `this build has no HTML input support (use the standard / full build)` | ✓ |
| Tùy chọn `css` / `stylesheets` | ném lỗi `this build has no stylesheet (\`css\` option) support ...` | ✓ |
| node có `tw` | ném lỗi `Tailwind (\`tw\`) is not supported by this build` | ✓ |
| Font WOFF / WOFF2 | ném lỗi `this build has no WOFF/WOFF2 font support (use the standard / full build, or load the WOFF add-on ...)` | ✓ |
| Font CFF `.otf` | ném lỗi `unsupported font format` | ✓ |
| `oklch()` / `lab()` / `color-mix()` trong style inline | ném lỗi `invalid value for style property ...` | ✓ |
| Ảnh SVG / WebP / GIF | không vẽ gì | ✓ |
| `clip-path`, `mix-blend-mode`, mask, `backdrop-filter` | bị bỏ qua | ✓ |
| `display: table*` | layout như block | ✓ |
| `float` | bị bỏ qua | ✓ |
| gradient `in oklab` | nội suy trong sRGB | ✓ |
| font biến thiên | vẽ ở instance mặc định | ✓ |
| `text-wrap: balance` | ngắt dòng bình thường | ✓ |
| `animation` / `timeMs` | bị bỏ qua | bị bỏ qua (`@keyframes` parse được, không có gì chuyển động) |
| Chữ RTL / chữ phức | không sắp xếp lại bidi, dùng shaper mặc định | giống core |
| font emoji màu | vẽ outline không màu | giống core |
| `format: "ico"`, `renderSvg()`, `renderAnimation()` | ném lỗi `this build has no ... support` | giống core |

Nếu đầu vào của bạn thay đổi, hãy kiểm tra `features` khi khởi động và chọn profile nhỏ nhất đáp ứng
được. Thông báo lỗi của các tính năng chỉ có ở `full` (`renderSvg`, `renderAnimation`, ICO / codec phụ, font màu, chữ phức tạp) ghi "use the full build".

## Build tùy biến

Mỗi tính năng là một cờ lúc biên dịch; các profile chỉ là bộ cờ đặt sẵn. Với Zig 0.17.x
(xem [Build từ mã nguồn](building-from-source.md)):

```sh
# a preset
zig build -Dprofile=core            # core | standard | full (default)

# a preset plus / minus single features
zig build -Dprofile=core -Dcss=true -Dtw=true
zig build -Dprofile=full -Dcomplex_text=false -Danimation=false

# release build of all profiles (zig build + wasm-opt -Oz) with extra flags applied to each
node scripts/build.mjs -- -Dtables=false
```

Các cờ: `css`, `tw`, `html`, `svg`, `woff`, `variable_fonts`, `cff`, `effects`, `modern_color`,
`tables`, `floats`, `webp_gif_decode`, `text_wrap_balance`, `color_fonts`, `complex_text`,
`animation`, `extra_codecs`, `render_svg`. Các tùy chọn build khác: `-Dwasm-optimize=small|fast|safe|debug`
(mặc định `small`), `-Dstrip=false`, `-Dstack-kib=<n>` (mặc định 1024). Kết quả nằm ở
`zig-out/bin/bm_engine.wasm`; nạp nó bằng `init(bytes)` / `initSync(bytes)`, hoặc trong Node dùng
`BM_WASM=path/to/bm_engine.wasm` với entry `bm-engine`. `features` báo đúng các cờ mà binary được build.

## Add-on WOFF

`bm_woff.wasm` (84.2 KiB, 65.5 KiB brotli) là chính bộ giải mã WOFF / WOFF2 của engine (kể cả brotli)
được tách thành module riêng. `loadWoff()` từ `bm-engine/woff` cài nó vào, sau đó `registerFont` chuyển
WOFF / WOFF2 thành TTF / OTF trước khi giao cho bất kỳ entry nào. Font sau khi chuyển trùng từng byte với
kết quả của bộ giải mã tích hợp. Add-on hữu ích trên `core` khi font của bạn ở dạng WOFF2 (ví dụ lấy từ
Google Fonts); trên `standard` / `full` thì không cần. Xem
[Bắt đầu](getting-started.md#woff-trên-core).

## Vì sao không có add-on tải lười nào khác

Một tính năng chỉ tách được thành module tải riêng nếu nó là hàm thuần byte-vào / byte-ra. Giải mã WOFF
là như vậy. Các tính năng khác thì không:

- **Tailwind** là một tầng cascade riêng: nó sinh pseudo-element và cần cấu trúc phần tử bên trong engine.
- **SVG, stylesheet và shaping** đọc và ghi trực tiếp cấu trúc nội bộ của engine (style đã tính, cây
  layout, cache glyph) trong cùng bộ nhớ tuyến tính. Muốn tách chúng ra thì cần một dynamic linker thật
  cho WebAssembly.

Vì vậy việc chọn tính năng diễn ra theo từng binary: chọn profile, hoặc tự build bản riêng bằng các cờ ở
trên.
