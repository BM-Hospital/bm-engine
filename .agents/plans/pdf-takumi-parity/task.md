# Kế hoạch hoàn thiện bm-engine PDF theo Takumi

Ngày rà: 2026-11-13. Trạng thái: needs review, implementation chưa hoàn tất. Xem checkpoint và trạng thái từng task trong todo.md.

## Checkpoint implementation

Zig 664/664; API 389/389 và focused source-reference 73/73 trên cả native/WASM. 136 golden: 123 IDENTICAL, 9 CLOSE, 4 DIFFER, 0 lỗi render, structure/parent tree 136/136. Validator: byte identity và semantics 16/16, veraPDF 14/14 mỗi engine, 0 bm-only issue. Audit tổng 1.516 probes: 1.442 pass, 74 fail, 0 unverified. Gate tổng chưa sạch; task 16–21 còn pending; chưa benchmark.

## Mốc đối chiếu và bằng chứng ban đầu (lịch sử)

- Upstream cố định: `ff9a5d411310c8cdd1ac76a4f106c123d309e0a4`; corpus trong `tests/upstream/takumi`, manifest 1.909 file. Source đầy đủ của cùng commit đang ở `ref/takumi`; corpus test không phải toàn bộ crate có thể build độc lập.
- Test gần nhất: wasm PDF render đủ 136 golden, 118 IDENTICAL, 8 CLOSE, 10 DIFFER, 0 ERROR; 123/136 khớp cả page content và interchange trong tolerance. Các số này không phải phần trăm đã port toàn bộ PDF.
- PDF API: 373/373; nhóm Zig PDF: 130/130 (lần gọi gần nhất dùng cache test hợp lệ). Toàn bộ Zig: 640/647, 7 lỗi codec PNG/WebP/animation đã có ở baseline; không phải 7 lỗi mới của PDF.
- `docs/PDF_AUDIT.md` là audit cũ theo 33eed4a/npm 0.20.0; dùng như danh sách cần rà, không coi mọi dòng là kết luận mới trên pinned reference. Những hạn chế xác nhận qua source được ghi dưới đây; các probe chưa chạy lại ở commit mới phải giữ trạng thái cần xác minh.
- Có khoảng 272 khai báo #[test] tĩnh trong cây takumi-pdf được nhập; đây không phải 272 public API behaviors độc lập. Cần phân loại cả test nội bộ krilla/subsetter, streaming/window/memory và 3 file JS PDF trước khi tính coverage theo test.

## Phần chưa port hoặc mới port một phần

| Nhóm | Kết luận hiện tại và bằng chứng | Task |
|:--|:--|:--|
| Transform của box qua trang | Chưa có fragment decoration/per-fragment origin tương đương. `src/pdf/emit.zig` vẫn gắn transformed box với trang bắt đầu; `paged-transforms` DIFFER. Chữ xoay đã sửa: `paged-rotated-text` CLOSE, không lên lịch port lại. | 02–03 |
| Clip và marked content qua trang | Đã có clip/tagging nhưng còn sai khác ở `paged-clipped-overflow`, `paged-monolithic-overflow`; cái sau khác struct/parents. Đây là lỗi/partial parity, không phải chưa có PDF tags. | 04–05 |
| Inline backgrounds/text clip | Có implementation, nhưng ba golden inline background image/nested clip/reach vẫn DIFFER. | 06–07 |
| Form-control text | DOM mới áp UA presets; audit ghi thiếu value/placeholder/password presentation, textarea lines và select offset. Đối chiếu `src/dom.zig`, `src/html/html.zig` với `takumi-core/src/form_control.rs` và form_control_tests.rs. Đây là phần shared engine ảnh hưởng PDF. | 08–09 |
| Bidi overrides | `unicode_bidi` có trong parser/computed style, chưa được shared text engine tiêu thụ. Ordinary bidi/Arabic không thuộc phần thiếu này. | 10 |
| Marker ảnh và generated image | `src/pdf/markers.zig` ghi rõ list-style-image chưa làm; `content:url()` missing trong audit, cần probe hiện tại trước khi code. Marker text/symbol và counters đã có. | 11–12 |
| SVG text positioning | `src/pdf/emit_svg.zig` lấy phần tử đầu x/y/dx/dy; comment xác nhận chưa có rotate/textPath/decorations. | 13–14 |
| Inline SVG CSS | Audit có failing probe images.svg-inline.css-fill; SVG được xử lý như tài liệu riêng. Cần xác nhận scope selector trên pinned oracle trước khi port. | 15 |
| SVG font glyph | bm phát hiện SVG table nhưng không render; pinned krilla callback `render_svg_glyph_fn` mặc định trả None, PDF source không cấu hình lại. Chưa đủ cơ sở gọi đây là thiếu port; nhiều khả năng là N/A/extension. | 22 (audit) |
| Table/flex continuation khi đổi width | Named pages đã port; `laySegments` vẫn giữ width cũ khi start token không biểu diễn được parallel continuation. | 16 |
| Grid-row fragments/float reflow | Audit xác định chưa có grid-row fragments và không reflow text cạnh float đã chuyển trang; cần layout theo fragment, không chỉ sửa PDF emitter. | 17–18 |
| Streaming layout/giới hạn bộ nhớ | Takumi phát trang đã settled khi layout còn tiếp tục; bm giữ laid-out document. Case trong streaming_tests.rs/window_scenes.rs/memory_tests.rs chưa được ánh xạ đầy đủ. Streaming nội bộ không đồng nghĩa có public streaming byte API. | 19–21 |
| Relative colors/offset-path | Shared parser/paint chưa có parity theo audit; chỉ port phạm vi cú pháp pinned reference xác nhận. | 23–24 |
| Inline outline/text tail cases | Outline island nhiều dòng non-solid/radii còn đơn giản hóa; ellipsis/RTL/soft-hyphen còn khác presentation/run grouping theo audit cũ. Cần probe trước khi xác nhận backlog mới. | 25, 28, 29 |
| Resource preparation/fallback | Pinned `PdfRenderer.prepare` gọi `inner.needs` và `prepareSource`, có `fontFiles`/font subsets/failedFontFiles; bm mới fetch ảnh. Đây là khoảng trống preparation. Không bundle Geist là lựa chọn riêng, không tự coi là bug phải sửa. | 26 |

## Các phần đã có, không port lại

Page sizes/margins/ranges; header/footer/page counters; named pages; image embedding PNG/JPEG và vector SVG cơ bản; font subsetting/ToUnicode; links/outline/metadata/XMP/attachments; structure tree; PDF/A-2/3/4 và PDF/UA-1/2 validation đều đã có implementation và test. Một số còn lỗi hẹp ở fragment/annotation/font program; không được mô tả là chưa hỗ trợ toàn bộ tính năng.

## Sai khác cần phân loại, không tự bắt chước

- `list-marker-pagination`: bm giữ marker trên dòng đầu; Takumi chuyển sang fragment cuối. Giữ behavior hiện tại nếu không có yêu cầu đổi.
- `named-pages`: Takumi có các nét table ngoài clip vô hình; không cần tạo thêm lệnh vô hình để nâng điểm identical.
- `svg-singular-gradient-transform`: khác biểu diễn ma trận suy biến, không có nội dung thấy được.
- `color-glyph-text-shadow`: khác BBox nhỏ do stroker; chỉ sửa nếu ảnh hưởng crop/visual/validation thực tế, không đồng nghĩa thiếu hỗ trợ color glyph/shadow.
- `report-links-outline`, `report-tagged-ua1`, `report-tagged-a2a`: 3 case khác annotation; audit cũ coi padding offset của Takumi là lỗi. Phải kiểm tra rect có phủ đúng text trước khi quyết định sửa hay chấp nhận.
- Font program byte-identical chỉ 71/136; khác byte nén/subset không phải thiếu glyph. Kiểm tra dict, widths, ToUnicode và render trước.
- CSS-correct gradient interpolation, currentColor shadow và các extension hợp lệ không tự hạ cấp theo giới hạn Takumi. Prefix producer/error, giới hạn kích thước, font validation và JSX hooks là policy/API differences được quản lý riêng.
- AcroForm, encryption, digital signatures, linearization, PDF/A-1 và page-margin boxes không nằm trong mục tiêu port nếu pinned public Takumi cũng không cung cấp chúng.

## Thứ tự thực hiện

1. **Nền tảng và thiết kế rủi ro:** 00 → 01 → 02. Tạo coverage map, pinned oracle và fragment/lifetime design trước khi sửa sâu.
2. **Đầu ra PDF thấy được:** 03 → 04 → 05; 06 → 07; 08 → 09. Sau mỗi nhánh chạy gate 27. Ưu tiên transform/clip/tagging và form text vì có thể mất nội dung hoặc sai lớp đọc.
3. **Text/SVG/generated content:** 10–15, 26; task 22 chỉ audit SVG font, không mặc định triển khai; chạy gate sau mỗi nhóm 2–3 task. Không cần phụ thuộc toàn bộ nhánh streaming.
4. **Pagination nâng cao và bộ nhớ:** 16 → (17,18); 19 → 20 → 21. Dùng các interface đã chốt ở 02; không gộp thành một PR rewrite lớn.
5. **Shared CSS và polish:** 23–25, 28–29; chỉ nhận các case đã được task 00/01 xác nhận. Các quyết định compatibility/fallback được ghi vào audit.
6. **Nghiệm thu:** 27 ở từng checkpoint và cuối plan. Không yêu cầu commit/deploy trong kế hoạch này.

Các task là thứ tự công việc, không phải chỉ định spawn agent. Đã triển khai nhiều nhóm đầu ra PDF; các task kiến trúc 16–21 còn pending. Chưa chạy benchmark.

## Quy tắc implementation và nghiệm thu

- Mỗi task phải thêm/chuyển một case upstream có assertion thật, tái hiện được fail trước fix. File Rust được copy hoặc một render thành công không đủ để đánh dấu đã port.
- Dùng chung test input và font bytes cho wasm/native/reference. Không trộn npm 0.20.0 với ff9a5d4 mà không ghi revision.
- So sánh tách lớp: layout/page geometry → visual/normalized operators → text extraction → links/structure/fonts → validator. Không chỉ chấm IDENTICAL của page stream.
- Không dùng miễn trừ theo cả file cho khác biệt mới. Ngoại lệ phải chỉ rõ thuộc tính, lý do, giới hạn và test giữ các thuộc tính còn lại.
- Yêu cầu cuối: không còn unmapped PDF case mà không có lý do; mọi feature được nhận có adapter và pass trên backend được hỗ trợ; 0 unexpected differences/render errors/missing fixtures. Khác biệt có chủ đích hoặc N/A phải nằm trong báo cáo.
- Các conformance validator mới chạy trong implementation checkpoint; số 45 file compliant trong tài liệu cũ không được ghi là kết quả vừa chạy ở plan này.
- 7 codec fail baseline được theo dõi riêng. Không mở rộng thành rewrite codec trong plan PDF; khi case PDF mới đụng decoder lỗi, thêm reproducer PDF và task codec liên quan rõ ràng.

## Lệnh kiểm tra dự kiến

```powershell
npm run test:takumi:verify
npm run build:pdf
$env:BM_ENGINE_BACKEND = 'wasm'
npm run test:pdf:takumi
node scripts/pdf-compare.mjs --strict <fixture-da-sua>
node scripts/pdf-test.mjs --no-build
zig build test -Dpdf=true -Dtest-filter=pdf -j1 --summary all
# Build native tương ứng trước khi dùng BM_ENGINE_BACKEND=native.
# Chạy probes bằng reference được build từ pinned ff9a5d4; thiếu reference => UNVERIFIED.
# bench/pdf/validate.mjs và visual.mjs cần setup toolchain đã pin trước khi chạy.
```

`--strict` hiện tại chưa hiểu allowlist; task 01 phải bổ sung gate cho baseline deliberate differences trước khi dùng strict toàn bộ suite trong CI.

## Rủi ro và cách giới hạn

| Rủi ro | Cách xử lý |
|:--|:--|
| Thay fragment làm đổi paint order, duplicate text/MCID | Thiết kế 02, test window scene, rồi đi từng task 03/04/05. |
| Release arena làm hỏng forward links, fonts và tags | Tách document metadata/page allocations; không release trước settled-page test. |
| Shared CSS/font fix ảnh hưởng PNG/SVG output | Chạy oracle/layout/shaping và image regression phù hợp, không chỉ PDF. |
| Adapter chạy nhưng không thật sự assert parity | Coverage map yêu cầu thuộc tính/assertion và backend/reference rõ ràng. |
| Kích thước bundle tăng vì fallback/font/stream infrastructure | Giữ default font policy; báo raw/gzip wasm size và memory benchmark theo từng checkpoint. |
| Plan rộng vượt một phiên | Mỗi ID là một lát công việc S/M; nếu hơn 5 file logic hoặc nhiều nguyên nhân, tách task tiếp trước code. |

## Phát hiện mới so với audit cũ

- `@font-face`/subset preparation là gap có source trace rõ: `takumi-pdf-js/src/export.ts::prepare` → `bindings-js/src/prepared.ts` và test fontFiles/failure. Xếp P1 thay vì gộp với quyết định fallback font.
- SVG-in-OpenType không mặc định là missing parity: krilla có helper nhưng `serialize.rs` gán callback None và PDF wrapper không override. Task 22 xác nhận và ghi N/A nếu public output cũng fallback.

## Quyết định chưa cần chặn việc P0

Giữ list marker trên dòng đầu, link rectangle phủ đúng text và CSS-correct behavior làm mặc định. Fallback Geist/addon, hooks React và bug-compatibility chỉ đổi sau khi có quyết định riêng. Không cần chờ các quyết định này để làm 00–09.

Danh sách công việc và tiêu chí từng task nằm trong [todo.md](todo.md).

## Execution plan: PDF output correctness and speed

The completion target is correct, robust PDFs and faster generation than the pinned
Takumi PDF build on the same input corpus. Reproducing Takumi's Rust internals, mapping
every internal source test, and implementing its streaming/memory architecture are not
acceptance requirements. Zig-native implementations are preferred when they preserve
page geometry, visible paint, extracted text, links, accessibility structure and valid
PDF behavior.

### Ordered phases

1. **Lock comparable inputs.** Build native and optimized WASM from current source;
   use the same DOM/HTML, fonts, options and fixtures for bm-engine and the pinned
   Takumi oracle. Record artifacts, backend, commands and current output differences.
2. **Fix output defects by user impact.** Prioritize page count/content loss, pagination
   and positioning, text/font coverage, visible paint/clipping, images, links, then
   tagged structure. For each candidate, reproduce the output, inspect rendered pages
   or semantic geometry, and decide whether Takumi or bm-engine is correct before
   changing behavior. Keep deliberate CSS/API extensions where they produce valid
   output; do not force byte-identical PDF streams.
3. **Verify each fix.** Keep a narrow regression fixture with assertions for the
   affected page count, positions, extracted text or raster result. Run that fixture
   on native and WASM, then the affected audit group and PDF API regression suite.
   Periodically run the full PDF Zig suite and full output audit; classify remaining
   mismatches as fixed, intentional, or still incorrect.
4. **Benchmark after output gates.** Use the same warmed corpus and fonts for bm-native,
   bm-wasm and pinned Takumi. Compare latency/throughput, scaling and memory separately;
   require bm-engine to beat Takumi on the agreed generation workload without output
   regressions. Publish the exact results and environment in the docs.
5. **Close the deliverable.** Update the PDF docs and parity report with actual
   remaining limitations, verified output results and benchmark numbers. Do not use
   upstream source-test mapping percentage as the definition of completion.

### Current execution checkpoint

The latest complete strict audit before the current source change was 1,501/1,567
probes passing with 66 failing. The `pagination.misc` failure for
`display:contents; break-before:page` was corrected by no longer transferring break
properties from a boxless element to its children; the focused probe passes 42/42 on
WASM. The full PDF Zig suite passes 676/676 and public PDF API suite passes 393/393 on
WASM with this change. The pagination group still has other layout/paint differences;
the full audit must be rerun after the next output fixes before claiming an updated
overall pass count. Benchmark is pending output-correctness work.


## Checkpoint continuation và resolved glyphs

Table-cell continuation khi đổi width: 6/8 probe qua, gồm text, ô dài/ngắn và links; còn painted-cell overflow và rowspan. Grid start/center/end với prefix, flex và grid regression: 9/9. Full Zig tại mốc continuation/grid: 668/668, exit 0; chưa phải full run của thay đổi glyph mới hơn. PDF API WASM 389/389. Resolved glyf dùng ppem + integer 26.6 midpoint, shadow/SVG 123/123 source probes; golden 123 IDENTICAL, 10 CLOSE, 3 DIFFER, 0 errors, structure/parent 136/136. CLOSE của color-glyph-text-shadow có gate riêng kiểm tra extraction và 6 raster comparisons mỗi run; mutation gate tests 5/5. Native/optimized artifact và full suite mới nhất đang kiểm tra tiếp. Task 18–21 và case-level mapping vẫn chưa hoàn tất; chưa benchmark.


## Checkpoint resource discovery, text variants and float reflow

Full Zig tại mốc generated images: 671/671, exit 0; trước sửa SVG needs/variants/float. API optimized WASM hiện tại: 393/393, Poppler bắt buộc. SVG needs theo CSS font family/weight và use, bỏ defs chưa dùng/display none/hidden, giới hạn vòng tham chiếu; font-face-only stylesheet không còn bị bỏ qua; fetched SVG có thể tải font-face mà không cần khai báo font subsets. Generated URL/gradient + tag ownership và text-transform full-width/full-size-kana đã có oracle probes. Focused 32/32 và native text variants 10/10. Float whole-box placement được đưa lại vào BFC exclusions rồi layout lại dòng; float group 54 assertions, nested BFC/RTL/variable-height 12 assertions; native float regression 13/13. Task 18 mới một phần, không đóng width-changing continuation hay split-float state. Audit tổng mới: 1559 probes, 1480 pass, 79 fail, 0 unverified; chưa có phân loại/ngoại lệ đủ cho mọi fail. Gate regression 6/6; missing/malformed Poppler output không thể pass bằng hai mảng rỗng, blank page warning có kiểm chứng page elements. Native artifact mới và full Zig mới hơn đang chạy; task 16/17 và 19–21 còn việc. Chưa benchmark runtime, chưa commit.

## Latest execution checkpoint (2026-11-14)

The rowspan width-reflow defect is fixed in `src/pdf/paged.zig`: a page-start token with `node == no_node` is still a valid segment boundary when it carries side-flow continuation state. The targeted strict probe passes 5/5 on native and optimized WASM; the continuation group passes 18/18 on both. Non-finite JS margins are rejected before JSON serialization, and native N-API preserves full PDF error diagnostics. Full PDF Zig tests pass 676/676 and public PDF API tests pass 393/393 on each backend. Native and WASM strict audits match exactly: 1,499/1,567 probes pass, 68 probes (128 assertions) fail, zero unverified. Root-image dimensions and `@page` `ch`/`ex` now match the pinned cases. The upstream source mapping still has 151 Rust and 69 JS declarations awaiting adapter or review. The final correctness and source-coverage gates remain open, so the benchmark gate remains open too.
