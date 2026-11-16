# Mẫu

[English](../../en/image/templates.md) · [Tiếng Việt](templates.md)

Mười một mẫu hoàn chỉnh, copy là dùng được: thẻ Open Graph, ảnh bìa bài blog, bài đăng mạng xã hội, thẻ
repository, thẻ trích dẫn, thẻ sản phẩm, vé sự kiện, giấy chứng nhận, báo cáo tuần có biểu đồ cột, thẻ đa
ngôn ngữ và banner sự kiện. Mỗi mẫu là một hàm bình thường nhận dữ liệu của bạn và trả về một cây node
(hoặc một chuỗi HTML), nên bạn có thể đặt nó vào route handler, script build hay worker. Tất cả đều đã
được render bằng `docs/examples/templates.mjs` với bm-render 0.1.0; ảnh dưới mỗi đoạn mã là kết quả thật,
không phải ảnh dựng minh họa.

[[toc]]

## Cách dùng các mẫu này

- **Chuẩn bị một lần.** Mọi mẫu đều dùng renderer và hai hàm trợ giúp trong khối [chuẩn bị](#chuẩn-bị).
  Đăng ký font một lần cho mỗi renderer và dùng lại renderer cho mọi ảnh (xem
  [Hiệu năng](./performance.md)).
- **Kích thước thiết kế.** Các mẫu được layout ở khoảng 800 × 420 pixel CSS để trang này nhẹ. Với kích
  thước Open Graph thông dụng 1200 × 630, hãy render với `devicePixelRatio: 1.5` và
  `width: 1200, height: 630`: layout giữ nguyên còn mọi độ dài được nhân lên (xem
  [handler](#phục-vụ-mẫu-từ-một-handler) ở cuối trang và [Định dạng đầu ra](./formats.md)).
- **Profile.** Phần lớn các mẫu chỉ dùng cây node với style inline và chạy trên mọi profile (kể cả
  `bm-render/core`). Thẻ sản phẩm (ảnh SVG), giấy chứng nhận (HTML + `<style>`) và thẻ đa ngôn ngữ
  (Tailwind `tw`) cần `standard` hoặc `full`; từng phần đều ghi rõ.
- **Cho chữ vừa khung.** Tiêu đề dùng `lineClamp` để nội dung dài không làm vỡ layout. Muốn tiêu đề tự
  thu nhỏ cho vừa, xem [measure](./measure.md). Chi tiết về chữ có ở [Typography](./typography.md).

## Chuẩn bị

<!-- @example templates#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
for (const file of ["Inter-Regular", "Inter-SemiBold", "Inter-Bold", "Inter-Italic", "NotoSans-Regular", "NotoSans-Bold"]) {
  renderer.registerFont(readFileSync(`assets/fonts/${file}.ttf`)); // family/weight/style read from the file
}

const box = (style, children = []) => ({ type: "container", style: { display: "flex", ...style }, children });
const text = (t, style = {}) => ({ type: "text", text: t, style });
```

`registerFont` đọc family, weight và style từ từng file, nên đoạn này đăng ký một family `Inter` với bốn
face (400, 600, 700, italic 400) và một family `Noto Sans` với hai face. Các font này nằm trong
`assets/fonts/` của repository; hãy thay đường dẫn bằng file của bạn. Xem [Font](./fonts.md).

## Thẻ Open Graph

Thẻ xem trước liên kết kinh điển: hàng thương hiệu, tiêu đề hai dòng, mô tả và các nhãn tag trên nền
gradient tối. Chạy trên mọi profile.

<!-- @example templates#og-card -->
```js
function ogCard({ site, title, description, tags }) {
  return box({
    flexDirection: "column", justifyContent: "space-between", width: "100%", height: "100%", padding: 48,
    backgroundImage: "linear-gradient(135deg, #0f172a 0%, #1e1b4b 55%, #4c1d95 100%)",
    fontFamily: "Inter", color: "#f8fafc",
  }, [
    box({ alignItems: "center", gap: 12 }, [
      box({ width: 36, height: 36, borderRadius: 10, backgroundImage: "linear-gradient(135deg, #f97316, #db2777)" }),
      text(site, { fontSize: 22, fontWeight: 600 }),
    ]),
    box({ flexDirection: "column", gap: 14 }, [
      text(title, { fontSize: 48, fontWeight: 700, lineHeight: 1.1, letterSpacing: -1, lineClamp: 2 }),
      text(description, { fontSize: 20, color: "#cbd5e1", lineHeight: 1.4, lineClamp: 2 }),
    ]),
    box({ gap: 10 }, tags.map((tag) =>
      text(tag, { fontSize: 16, fontWeight: 600, color: "#c4b5fd", padding: "6px 14px", borderRadius: 999,
                  backgroundColor: "rgba(167, 139, 250, 0.18)" }))),
  ]);
}

const ogPng = renderer.renderSync(ogCard({
  site: "acme.dev",
  title: "Rendering Open Graph images without a headless browser",
  description: "Layout, text shaping and PNG encoding in a 450 KiB WebAssembly module that runs anywhere.",
  tags: ["WebAssembly", "Zig", "Images"],
}), { width: 800, height: 420 });
```

![Thẻ Open Graph với nền gradient, tiêu đề, mô tả và các tag](/img/guide/templates-og-card.png)

- `justifyContent: "space-between"` trên cột chia ba khối ra hết chiều cao; không cần định vị tuyệt đối.
- Bản thân text node cũng mang được style của box (`padding`, `borderRadius`, `backgroundColor`): mỗi
  nhãn tag chỉ là một text node, được blockify vì cha của nó là flex container.
- `lineClamp: 2` cắt tiêu đề và mô tả sau hai dòng và thêm dấu ba chấm.

## Ảnh bìa bài blog

Ảnh bìa phong cách tạp chí trên nền sáng, với thanh nhấn màu, dòng chuyên mục, tiêu đề cân dòng và dòng
tác giả có avatar bằng chữ cái đầu. Chạy trên mọi profile; `textWrap: "balance"` cần `standard` (trên
`core` tiêu đề chỉ xuống dòng theo kiểu tham lam thông thường).

<!-- @example templates#blog-cover -->
```js
function blogCover({ category, title, author, date, readTime }) {
  return box({ width: "100%", height: "100%", backgroundColor: "#fffbeb", fontFamily: "Inter" }, [
    box({ width: 16, height: "100%", backgroundColor: "#f59e0b" }),
    box({ flexDirection: "column", justifyContent: "center", gap: 22, padding: "0 56px", flexGrow: 1 }, [
      text(category.toUpperCase(), { fontSize: 16, fontWeight: 700, letterSpacing: 3, color: "#b45309" }),
      text(title, { fontSize: 44, fontWeight: 700, lineHeight: 1.15, color: "#1c1917", textWrap: "balance" }),
      box({ alignItems: "center", gap: 14, fontSize: 18, color: "#57534e" }, [
        box({ width: 44, height: 44, borderRadius: 22, alignItems: "center", justifyContent: "center",
              backgroundColor: "#1c1917", color: "#fffbeb", fontWeight: 700 }, [text(author[0])]),
        text(author, { fontWeight: 600, color: "#1c1917" }),
        text("·"), text(date), text("·"), text(readTime),
      ]),
    ]),
  ]);
}

const coverPng = renderer.renderSync(blogCover({
  category: "Engineering",
  title: "How we moved our image service to the edge without a headless browser",
  author: "Linh Tran", date: "Nov 12, 2026", readTime: "8 min read",
}), { width: 800, height: 420 });
```

![Ảnh bìa blog với thanh màu hổ phách, chuyên mục, tiêu đề cân dòng và dòng tác giả](/img/guide/templates-blog-cover.png)

- Avatar là một hình tròn chứa chữ cái đầu của tác giả — không cần ảnh. Muốn dùng ảnh thật, thay nó bằng
  một image node (xem [Ảnh](./images.md)).
- `textWrap: "balance"` làm các dòng của tiêu đề dài gần bằng nhau.
- Hàng tác giả đặt `fontSize` và `color` một lần; các text node riêng lẻ kế thừa chúng.

## Bài đăng mạng xã hội

Thẻ bài đăng theo phong cách mạng microblog, nổi trên nền xám với bóng đổ mềm. Chạy trên mọi profile.

<!-- @example templates#social-post -->
```js
function socialPost({ name, handle, body, time, stats }) {
  return box({ width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
               backgroundColor: "#e2e8f0", fontFamily: "Inter" }, [
    box({ flexDirection: "column", gap: 16, width: 560, padding: 28, borderRadius: 20,
          backgroundColor: "#ffffff", boxShadow: "0 10px 30px rgba(15, 23, 42, 0.12)" }, [
      box({ alignItems: "center", gap: 12 }, [
        box({ width: 52, height: 52, borderRadius: 26, backgroundImage: "linear-gradient(135deg, #38bdf8, #6366f1)" }),
        box({ flexDirection: "column" }, [
          text(name, { fontSize: 18, fontWeight: 700, color: "#0f172a" }),
          text(handle, { fontSize: 15, color: "#64748b" }),
        ]),
      ]),
      text(body, { fontSize: 22, lineHeight: 1.45, color: "#0f172a" }),
      text(time, { fontSize: 15, color: "#64748b" }),
      box({ gap: 28, paddingTop: 14, borderTop: "1px solid #e2e8f0", fontSize: 15, color: "#475569" },
        stats.map(([n, label]) => box({ gap: 6 }, [text(n, { fontWeight: 700, color: "#0f172a" }), text(label)]))),
    ]),
  ]);
}

const postPng = renderer.renderSync(socialPost({
  name: "Minh Anh", handle: "@minhanh",
  body: "Shipped our OG images on the edge today. Same node tree as before, a binary 9× smaller, and no Chromium in sight.",
  time: "9:41 AM · Nov 12, 2026",
  stats: [["128", "Reposts"], ["1,024", "Likes"], ["42", "Bookmarks"]],
}), { width: 680, height: 380 });
```

![Thẻ bài đăng với avatar, tên, handle, nội dung, thời gian và các bộ đếm](/img/guide/templates-social-post.png)

- Thẻ có `width: 560` cố định; chiều cao do nội dung quyết định, và flex container bên ngoài căn nó vào
  giữa.
- `borderTop` trên hàng thống kê vẽ đường phân cách.
- Thay hình tròn gradient bằng image node chứa avatar người dùng với `objectFit: "cover"`.

## Thẻ repository

Thẻ repository kiểu GitHub: `owner/repo`, mô tả, chấm màu ngôn ngữ, các bộ đếm và viền dưới có màu. Chạy
trên mọi profile.

<!-- @example templates#repo-card -->
```js
function repoCard({ owner, repo, description, language, stars, forks, issues }) {
  const stat = (label, value) => box({ flexDirection: "column", gap: 2 }, [
    text(value, { fontSize: 22, fontWeight: 700, color: "#1f2328" }),
    text(label, { fontSize: 14, color: "#59636e" }),
  ]);
  return box({ flexDirection: "column", width: "100%", height: "100%", backgroundColor: "#ffffff",
               fontFamily: "Inter", borderBottom: "10px solid #fb923c" }, [
    box({ flexDirection: "column", flexGrow: 1, padding: "44px 48px", gap: 18 }, [
      box({ alignItems: "baseline", fontSize: 40, color: "#1f2328" }, [
        text(`${owner}/`, { color: "#59636e" }),
        text(repo, { fontWeight: 700 }),
      ]),
      text(description, { fontSize: 20, lineHeight: 1.45, color: "#59636e", lineClamp: 2 }),
      box({ alignItems: "center", gap: 8, fontSize: 16, color: "#1f2328" }, [
        box({ width: 14, height: 14, borderRadius: 7, backgroundColor: language.color }),
        text(language.name),
      ]),
    ]),
    box({ gap: 48, padding: "0 48px 32px" }, [stat("Stars", stars), stat("Forks", forks), stat("Issues", issues)]),
  ]);
}

const repoPng = renderer.renderSync(repoCard({
  owner: "acme", repo: "bm-render",
  description: "Render node trees, HTML and Tailwind to PNG, JPEG, WebP and SVG with a dependency-free WebAssembly engine.",
  language: { name: "Zig", color: "#ec915c" },
  stars: "4.2k", forks: "186", issues: "23",
}), { width: 800, height: 400 });
```

![Thẻ repository với tên chủ sở hữu và repository, mô tả, ngôn ngữ và số liệu](/img/guide/templates-repo-card.png)

- `alignItems: "baseline"` giữ `owner/` và tên repository in đậm trên cùng một đường baseline dù chúng
  khác weight.
- `borderBottom` trên root vẽ viền màu; với `box-sizing: border-box` mặc định, viền lấn vào 400 px chiều
  cao thay vì cộng thêm.

## Thẻ trích dẫn

Một dấu mở ngoặc kép lớn, câu trích dẫn in nghiêng và dòng ghi nguồn. Chạy trên mọi profile.

<!-- @example templates#quote -->
```js
function quoteCard({ quote, author, role }) {
  return box({ flexDirection: "column", justifyContent: "center", width: "100%", height: "100%",
               padding: "40px 64px", gap: 20, backgroundColor: "#134e4a", fontFamily: "Inter" }, [
    text("“", { fontSize: 120, lineHeight: "60px", height: 60, fontWeight: 700, color: "#5eead4" }),
    text(quote, { fontSize: 32, fontStyle: "italic", lineHeight: 1.35, color: "#f0fdfa" }),
    box({ alignItems: "center", gap: 12 }, [
      box({ width: 40, height: 3, backgroundColor: "#5eead4" }),
      text(author, { fontSize: 18, fontWeight: 700, color: "#ccfbf1" }),
      text(role, { fontSize: 18, color: "#99f6e4" }),
    ]),
  ]);
}

const quotePng = renderer.renderSync(quoteCard({
  quote: "Simplicity is prerequisite for reliability.",
  author: "Edsger W. Dijkstra", role: "Computer scientist",
}), { width: 720, height: 380 });
```

![Thẻ trích dẫn trên nền xanh mòng két đậm với dấu ngoặc kép lớn, câu nghiêng và tác giả](/img/guide/templates-quote.png)

- `fontStyle: "italic"` dùng face `Inter-Italic.ttf` đã đăng ký. Nếu không có face nghiêng, bm-render tự
  giả lập bằng cách làm nghiêng face thường (xem [Font](./fonts.md)).
- Dấu ngoặc kép là `“` cỡ 120 px với `lineHeight: "60px"` và `height: 60`, nên glyph lớn không đẩy
  câu trích dẫn xuống.

## Thẻ sản phẩm

Thẻ thương mại điện tử với hình minh họa, nhãn giảm giá, đánh giá, giá cũ gạch ngang và một nút bấm. Hình
minh họa là chuỗi SVG inline, nên mẫu này cần **`standard` hoặc `full`** (trên `core` ảnh không vẽ gì,
phần còn lại của thẻ vẫn render).

<!-- @example templates#product -->
```js
// an inline SVG illustration (SVG images need the standard or full profile)
const sneaker = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 120" width="200" height="120">
  <path d="M10 80 Q20 40 60 45 L95 30 Q110 60 150 62 Q190 66 192 90 L192 100 L10 100 Z" fill="#ef4444"/>
  <rect x="10" y="96" width="182" height="12" rx="6" fill="#f8fafc"/>
  <path d="M70 48 L80 62 M82 42 L92 56 M94 36 L104 50" stroke="#fff" stroke-width="4" stroke-linecap="round"/>
</svg>`;

function productCard({ name, price, oldPrice, rating, badge }) {
  return box({ width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
               backgroundColor: "#f1f5f9", fontFamily: "Inter" }, [
    box({ width: 620, height: 300, borderRadius: 24, overflow: "hidden", backgroundColor: "#ffffff",
          boxShadow: "0 12px 40px rgba(15, 23, 42, 0.15)" }, [
      box({ width: 260, alignItems: "center", justifyContent: "center", position: "relative",
            backgroundImage: "radial-gradient(circle at 50% 40%, #fee2e2, #fecaca)" }, [
        { type: "image", src: sneaker, width: 200, height: 120 },
        text(badge, { position: "absolute", top: 16, left: 16, fontSize: 13, fontWeight: 700, color: "#ffffff",
                      backgroundColor: "#ef4444", padding: "4px 10px", borderRadius: 6 }),
      ]),
      box({ flexDirection: "column", justifyContent: "center", gap: 14, padding: 32, flexGrow: 1, flexBasis: 0 }, [
        text(name, { fontSize: 28, fontWeight: 700, color: "#0f172a", lineHeight: 1.2 }),
        text(`${"★".repeat(Math.round(rating))}${"☆".repeat(5 - Math.round(rating))}  ${rating.toFixed(1)}`,
             { fontSize: 16, color: "#f59e0b" }),
        box({ alignItems: "baseline", gap: 12 }, [
          text(price, { fontSize: 40, fontWeight: 700, color: "#0f172a" }),
          text(oldPrice, { fontSize: 20, color: "#94a3b8", textDecoration: "line-through" }),
        ]),
        text("Add to cart", { alignSelf: "flex-start", fontSize: 16, fontWeight: 600, color: "#ffffff",
                              backgroundColor: "#0f172a", padding: "10px 20px", borderRadius: 10 }),
      ]),
    ]),
  ]);
}

const productPng = renderer.renderSync(productCard({
  name: "Runner Pro 2 Sneakers", price: "$89", oldPrice: "$129", rating: 4.4, badge: "-31%",
}), { width: 700, height: 360 });
```

![Thẻ sản phẩm với hình giày đỏ, nhãn giảm giá, đánh giá, giá và nút bấm](/img/guide/templates-product.png)

- Nhãn giảm giá được định vị tuyệt đối bên trong khung ảnh, vốn có `position: "relative"`.
- `overflow: "hidden"` cùng `borderRadius: 24` cắt khung màu hồng theo góc bo của thẻ.
- Các ngôi sao đánh giá (`★` / `☆`) là ký tự bình thường; Inter có glyph cho cả hai.
- `textDecoration: "line-through"` gạch ngang giá cũ.

## Vé sự kiện

Một tấm vé có cuống tách bằng đường nét đứt và hai vết "bấm lỗ". Chạy trên mọi profile.

<!-- @example templates#ticket -->
```js
function ticket({ event, date, time, venue, seat, code }) {
  const field = (label, value) => box({ flexDirection: "column", gap: 2 }, [
    text(label.toUpperCase(), { fontSize: 11, fontWeight: 700, letterSpacing: 1.5, color: "#a5b4fc" }),
    text(value, { fontSize: 18, fontWeight: 600, color: "#ffffff" }),
  ]);
  // the two half circles are the "punched" notches between stub and body
  const notch = (side) => box({ position: "absolute", [side]: -14, left: 506, width: 28, height: 28,
                                borderRadius: 14, backgroundColor: "#f5f3ff" });
  return box({ width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
               backgroundColor: "#f5f3ff", fontFamily: "Inter" }, [
    box({ position: "relative", width: 700, height: 240, borderRadius: 18, overflow: "hidden",
          backgroundImage: "linear-gradient(110deg, #4338ca, #7c3aed)" }, [
      box({ flexDirection: "column", justifyContent: "space-between", width: 520, padding: 28 }, [
        text(event, { fontSize: 30, fontWeight: 700, color: "#ffffff", lineHeight: 1.15 }),
        box({ gap: 32 }, [field("Date", date), field("Time", time), field("Venue", venue)]),
      ]),
      box({ flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 12, flexGrow: 1,
            borderLeft: "2px dashed rgba(255, 255, 255, 0.5)" }, [
        field("Seat", seat),
        text(code, { fontSize: 13, letterSpacing: 2, color: "#c7d2fe", fontFamily: "Noto Sans" }),
      ]),
      notch("top"), notch("bottom"),
    ]),
  ]);
}

const ticketPng = renderer.renderSync(ticket({
  event: "WebAssembly Summit 2026 — Ho Chi Minh City",
  date: "Dec 5", time: "09:00", venue: "Hall B", seat: "C-14", code: "WS26-00142",
}), { width: 760, height: 300 });
```

![Vé sự kiện màu tím với tiêu đề, ngày, giờ, địa điểm, đường phân cách nét đứt và cuống ghi số ghế](/img/guide/templates-ticket.png)

- Vết bấm là các hình tròn cùng màu nền trang, đặt đè lên mép trên và mép dưới tại đường phân cách
  (`left: 506` = 520 − 14). `overflow: "hidden"` trên vé cắt chúng thành nửa hình tròn.
- `borderLeft: "2px dashed ..."` trên cuống vé vẽ đường xé.
- Khóa tính toán (`[side]: -14`) cho phép cùng một hàm trợ giúp đặt vết bấm ở trên hoặc ở dưới.

## Giấy chứng nhận

Giấy chứng nhận viết bằng **HTML kèm khối `<style>`** thay vì cây node — tiện khi designer bàn giao
markup. Đầu vào HTML và stylesheet cần **`standard` hoặc `full`**.

<!-- @example templates#certificate -->
```js
// written as HTML + a <style> block (HTML input and stylesheets need standard / full)
function certificate({ name, course, date, signer }) {
  return `
<style>
  .page { display: flex; width: 100%; height: 100%; padding: 18px; background: #fdfcf7; font-family: Inter; }
  .frame { display: flex; flex-direction: column; align-items: center; justify-content: center; flex-grow: 1;
           gap: 10px; border: 3px double #a16207; outline: 1px solid #a16207; outline-offset: -10px; }
  .kicker { font-size: 13px; letter-spacing: 4px; color: #a16207; font-weight: 700; }
  h1 { margin: 0; font-size: 40px; color: #1c1917; }
  .name { font-size: 34px; font-style: italic; color: #a16207; padding: 0 24px 6px; border-bottom: 1px solid #d6d3d1; }
  p { margin: 0; font-size: 16px; color: #57534e; text-align: center; max-width: 520px; line-height: 1.5; }
  .row { display: flex; gap: 120px; margin-top: 14px; font-size: 13px; color: #78716c; }
  .row b { display: block; font-size: 15px; color: #1c1917; }
</style>
<div class="page"><div class="frame">
  <div class="kicker">CERTIFICATE OF COMPLETION</div>
  <h1>Certificate</h1>
  <div class="name">${name}</div>
  <p>has successfully completed <b>${course}</b>, including all labs and the final project.</p>
  <div class="row"><div><b>${date}</b>Date</div><div><b>${signer}</b>Instructor</div></div>
</div></div>`;
}

const certPng = renderer.renderSync(certificate({
  name: "Nguyễn Thị Lan", course: "Rendering Images with WebAssembly", date: "November 12, 2026", signer: "Tran Van Minh",
}), { width: 760, height: 440 });
```

![Giấy chứng nhận với viền vàng đôi, tiêu đề, tên người nhận in nghiêng và hai ô chữ ký](/img/guide/templates-certificate.png)

- `border: 3px double` cộng với `outline` có `outline-offset` âm tạo khung hai đường.
- `h1` và `p` nhận margin user-agent của Chromium, stylesheet đặt lại bằng `margin: 0`.
- `.row b { display: block }` xếp giá trị in đậm lên trên nhãn của nó trong mỗi ô chữ ký.
- Ở đây giá trị được chèn vào HTML mà không escape; hãy escape `&`, `<` và `>` trong dữ liệu người dùng.
  Xem [HTML và Tailwind](./html-and-tailwind.md).

## Báo cáo tuần có biểu đồ cột

Một ô dashboard với con số chính, nhãn mức thay đổi và biểu đồ cột bảy ngày dựng bằng flex box, ngày cao
nhất được tô nổi. Chạy trên mọi profile. Các kỹ thuật biểu đồ khác có ở [Biểu đồ](./charts.md).

<!-- @example templates#stats -->
```js
// a weekly report card with a bar graph built from flex boxes
function weeklyReport({ title, total, change, days }) {
  const max = Math.max(...days.map(([, v]) => v));
  return box({ flexDirection: "column", width: "100%", height: "100%", padding: 36, gap: 20,
               backgroundColor: "#0b1120", fontFamily: "Inter", color: "#e2e8f0" }, [
    box({ justifyContent: "space-between", alignItems: "flex-start" }, [
      box({ flexDirection: "column", gap: 6 }, [
        text(title, { fontSize: 18, color: "#94a3b8" }),
        text(total, { fontSize: 48, fontWeight: 700, color: "#ffffff" }),
      ]),
      text(change, { fontSize: 16, fontWeight: 700, color: "#4ade80", padding: "6px 12px", borderRadius: 999,
                     backgroundColor: "rgba(74, 222, 128, 0.12)" }),
    ]),
    box({ flexGrow: 1, gap: 14 }, days.map(([day, v]) =>
      box({ flexDirection: "column", alignItems: "center", gap: 8, flexGrow: 1, flexBasis: 0 }, [
        box({ flexDirection: "column", justifyContent: "flex-end", flexGrow: 1, width: "100%" }, [
          box({ height: `${(v / max) * 100}%`, borderRadius: 8,
                backgroundColor: v === max ? "#38bdf8" : "#1e3a5f" }),
        ]),
        text(day, { fontSize: 14, color: "#64748b" }),
      ]))),
  ]);
}

const statsPng = renderer.renderSync(weeklyReport({
  title: "Images rendered this week", total: "1,284,092", change: "▲ 18.2%",
  days: [["Mon", 160], ["Tue", 172], ["Wed", 190], ["Thu", 205], ["Fri", 230], ["Sat", 140], ["Sun", 120]],
}), { width: 640, height: 380 });
```

![Thẻ báo cáo nền tối với con số lớn, nhãn tăng trưởng màu xanh và bảy cột, thứ Sáu được tô nổi](/img/guide/templates-stats.png)

- Mỗi cột nằm trong một "ô vẽ" (`flexGrow: 1`, `justifyContent: "flex-end"`), nên chiều cao phần trăm của
  nó tính theo khoảng trống phía trên nhãn ngày.
- `flexBasis: 0` trên các cột ngày giúp chúng rộng bằng nhau bất kể nhãn dài ngắn.

## Thẻ đa ngôn ngữ

Một thẻ viết bằng class Tailwind, mỗi hàng một ngôn ngữ, gồm cả tiếng Việt, tiếng Hy Lạp và chữ Kirin.
`tw` cần **`standard` hoặc `full`**.

<!-- @example templates#multilang -->
```js
// Tailwind classes (standard / full); one row per language. Inter covers all of them; the
// Greek and Cyrillic rows switch to Noto Sans only to show a per-row font family
function welcomeCard(rows) {
  return {
    type: "container",
    tw: "flex flex-col justify-center w-full h-full px-14 gap-5 bg-linear-to-br from-rose-50 to-orange-100",
    style: { fontFamily: "Inter" },
    children: [
      { type: "text", tw: "text-sm font-bold tracking-widest text-rose-700", text: "WELCOME · CHÀO MỪNG · WILLKOMMEN" },
      ...rows.map(([lang, line, font]) => ({
        type: "container", tw: "flex items-baseline gap-5",
        children: [
          { type: "text", tw: "w-12 text-sm font-bold text-rose-400", text: lang },
          { type: "text", tw: "text-2xl font-semibold text-stone-900", style: font ? { fontFamily: font } : {}, text: line },
        ],
      })),
    ],
  };
}

const multiPng = renderer.renderSync(welcomeCard([
  ["VI", "Xin chào! Phở bò Hà Nội ngon tuyệt."],
  ["EN", "Hello! Rendered in WebAssembly."],
  ["DE", "Grüß Gott! Schöne Grüße."],
  ["FR", "Bonjour ! Ça déçoit rarement."],
  ["EL", "Γειά σου κόσμε!", "Noto Sans"],
  ["RU", "Привет, мир! Съешь же ещё.", "Noto Sans"],
]), { width: 760, height: 420 });
```

![Thẻ với lời chào bằng tiếng Việt, Anh, Đức, Pháp, Hy Lạp và Nga](/img/guide/templates-multilang.png)

- Tiếng Việt chạy trên mọi profile miễn là văn bản ở dạng dựng sẵn (NFC) và font có đủ glyph; hãy gọi
  `text.normalize("NFC")` với dữ liệu người dùng. Xem [Typography](./typography.md).
- `style` và `tw` kết hợp được trên cùng một node: ở đây `style.fontFamily` chuyển riêng vài hàng sang
  Noto Sans.
- Gradient là `bg-linear-to-br` (cách đặt tên của Tailwind v4); tên cũ của v3 là `bg-gradient-to-br` bị
  bỏ qua trong im lặng.
- Các hệ chữ cần shaping hoặc bidi (Ả Rập, Do Thái, Devanagari, Thái) cần profile `full` và một font phủ
  chúng; emoji màu cần `full` và một font emoji.

## Banner sự kiện

Banner nền tối với các "quả cầu" màu nhòe, chip ngày, tiêu đề lớn và chữ cái đầu của diễn giả. Chạy trên
mọi profile.

<!-- @example templates#event-banner -->
```js
function eventBanner({ title, subtitle, date, speakers }) {
  return box({ width: "100%", height: "100%", fontFamily: "Inter", backgroundColor: "#111827", overflow: "hidden",
               position: "relative" }, [
    // decorative circles, clipped by overflow: hidden on the root
    box({ position: "absolute", right: -80, top: -80, width: 320, height: 320, borderRadius: "50%",
          backgroundImage: "radial-gradient(circle, rgba(236, 72, 153, 0.55), rgba(236, 72, 153, 0) 70%)" }),
    box({ position: "absolute", left: 220, bottom: -140, width: 360, height: 360, borderRadius: "50%",
          backgroundImage: "radial-gradient(circle, rgba(59, 130, 246, 0.45), rgba(59, 130, 246, 0) 70%)" }),
    box({ position: "relative", flexDirection: "column", justifyContent: "space-between", padding: 44, width: "100%" }, [
      text(date, { alignSelf: "flex-start", fontSize: 15, fontWeight: 700, color: "#111827",
                   backgroundColor: "#facc15", padding: "6px 12px", borderRadius: 6 }),
      box({ flexDirection: "column", gap: 8 }, [
        text(title, { fontSize: 52, fontWeight: 700, color: "#ffffff", letterSpacing: -1.5, lineHeight: 1.05 }),
        text(subtitle, { fontSize: 20, color: "#d1d5db" }),
      ]),
      box({ gap: 22 }, speakers.map(([name, color]) =>
        box({ alignItems: "center", gap: 10 }, [
          box({ width: 36, height: 36, borderRadius: 18, alignItems: "center", justifyContent: "center",
                backgroundColor: color, fontSize: 15, fontWeight: 700, color: "#111827" },
            [text(name.split(" ").map((w) => w[0]).join(""))]),
          text(name, { fontSize: 16, color: "#f3f4f6" }),
        ]))),
    ]),
  ]);
}

const bannerPng = renderer.renderSync(eventBanner({
  title: "Frontend Night #12",
  subtitle: "Edge rendering, image pipelines and fonts that just work",
  date: "THU · DEC 18 · 19:00",
  speakers: [["Hoang Nam", "#93c5fd"], ["Mai Phuong", "#f9a8d4"], ["Lucas Weber", "#fde68a"]],
}), { width: 800, height: 420 });
```

![Banner sự kiện nền tối với quầng sáng hồng và xanh, chip ngày màu vàng, tiêu đề và ba diễn giả](/img/guide/templates-event-banner.png)

- Quầng sáng là các `radial-gradient` mờ dần về trong suốt — rẻ hơn `filter: blur()` trên một box lớn, và
  có sẵn trên `core`.
- Chúng được định vị tuyệt đối, một phần nằm ngoài banner; `overflow: "hidden"` trên root cắt bỏ phần thừa.
- Cột nội dung có `position: "relative"` để được vẽ đè lên các quầng sáng định vị tuyệt đối.

## Phục vụ mẫu từ một handler

Một handler kiểu fetch render [thẻ Open Graph](#thẻ-open-graph) từ tham số query ở kích thước chuẩn
1200 × 630. Cùng hàm này chạy được trên Node 18+, Bun, Deno và Cloudflare Workers (trên Workers, khởi tạo
binary như hướng dẫn ở [Bắt đầu](../getting-started.md#edge-runtime-deno-bun)).

<!-- @example templates#handler -->
```js
// a fetch-style handler (Node 18+, Bun, Deno, Workers): /og?title=...&site=...
function handleOg(request) {
  const url = new URL(request.url);
  const png = renderer.renderSync(ogCard({
    site: url.searchParams.get("site") ?? "acme.dev",
    title: url.searchParams.get("title") ?? "Untitled",
    description: url.searchParams.get("description") ?? "",
    tags: (url.searchParams.get("tags") ?? "").split(",").filter(Boolean),
  }), { width: 1200, height: 630, devicePixelRatio: 1.5 });
  return new Response(png, {
    headers: { "content-type": "image/png", "cache-control": "public, max-age=86400, immutable" },
  });
}

const res = handleOg(new Request("https://example.com/og?title=Hello%20from%20a%20handler&tags=Edge,PNG"));
console.log(res.status, res.headers.get("content-type"), (await res.arrayBuffer()).byteLength > 0);
```

- `devicePixelRatio: 1.5` biến thiết kế 800 × 420 thành ảnh 1200 × 630 mà không phải sửa mẫu.
- bm-render không có helper `ImageResponse`; chỉ cần `new Response(png, ...)`, vì kết quả là một
  `Uint8Array` sở hữu buffer của riêng nó.
- Render là thao tác đồng bộ và tốn CPU. Hãy cache kết quả (ở đây bằng `cache-control`) và xem
  [Hiệu năng](./performance.md) để dùng worker pool.
