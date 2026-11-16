# Templates

[English](templates.md) · [Tiếng Việt](../../vi/image/templates.md)

Eleven complete, copy-paste templates: Open Graph card, blog cover, social post, repository card, quote
card, product card, event ticket, certificate, weekly report with a bar graph, multi-language card and
event banner. Each one is a plain function that takes your data and returns a node tree (or an HTML
string), so you can drop it into a route handler, a build script or a worker. All of them were rendered
by `docs/examples/templates.mjs` against bm-render 0.1.0; the image under each snippet is the real
output, not a mock-up.

[[toc]]

## How to use these templates

- **Setup once.** Every template uses the renderer and the two helpers from the [setup](#setup) block.
  Register fonts once per renderer and reuse the renderer for every image (see
  [Performance](./performance.md)).
- **Design size.** The templates are laid out at roughly 800 × 420 CSS pixels to keep this page light. For
  the usual 1200 × 630 Open Graph size, render with `devicePixelRatio: 1.5` and `width: 1200, height: 630`:
  the layout stays the same and every length is scaled (see the [handler](#serving-a-template-from-a-handler)
  at the end, and [Output formats](./formats.md)).
- **Profiles.** Most templates use only node trees with inline styles and work on every profile
  (`bm-render/core` included). The product card (SVG image), the certificate (HTML + `<style>`) and the
  multi-language card (Tailwind `tw`) need `standard` or `full`; each section says so.
- **Text fitting.** Titles use `lineClamp` so that long input cannot push the layout apart. For
  shrink-to-fit titles, see [measure](./measure.md). Text details are in [Typography](./typography.md).

## Setup

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

`registerFont` reads the family, weight and style from each file, so this registers one `Inter` family
with four faces (400, 600, 700, italic 400) and a `Noto Sans` family with two. The fonts are the ones in
the repository's `assets/fonts/`; replace the paths with your own files. See [Fonts](./fonts.md).

## Open Graph card

The classic link-preview card: brand row, two-line title, description and tag pills on a dark gradient.
Works on every profile.

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

![Open Graph card with a gradient background, title, description and tags](/img/guide/templates-og-card.png)

- `justifyContent: "space-between"` on the column distributes the three blocks over the full height; no
  absolute positioning needed.
- A text node can carry box styles itself (`padding`, `borderRadius`, `backgroundColor`): the pills are
  single text nodes, blockified because their parent is a flex container.
- `lineClamp: 2` cuts the title and the description after two lines and adds an ellipsis.

## Blog cover

A light editorial cover with an accent bar, a category kicker, a balanced headline and an author line
with an initial avatar. Works on every profile; `textWrap: "balance"` needs `standard` (on `core` the
headline simply wraps greedily).

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

![Blog cover with an amber accent bar, category, balanced headline and author line](/img/guide/templates-blog-cover.png)

- The avatar is a circle with the author's first letter — no image needed. To use a photo, replace it with
  an image node (see [Images](./images.md)).
- `textWrap: "balance"` evens out the line lengths of the headline.
- The author row sets `fontSize` and `color` once; the separate text nodes inherit them.

## Social post

A post card in the style of a microblogging site, floating on a grey background with a soft shadow.
Works on every profile.

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

![Social post card with avatar, name, handle, post text, time and counters](/img/guide/templates-social-post.png)

- The card has a fixed `width: 560`; its height comes from the content, and the outer flex container
  centres it.
- `borderTop` on the stats row draws the divider.
- Replace the gradient circle with the user's avatar image node and `objectFit: "cover"`.

## Repository card

A GitHub-style repository card: `owner/repo`, description, language dot, counters and a coloured bottom
edge. Works on every profile.

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

![Repository card with owner and repository name, description, language and stats](/img/guide/templates-repo-card.png)

- `alignItems: "baseline"` keeps `owner/` and the bold repository name on the same baseline even though
  they use different weights.
- `borderBottom` on the root draws the coloured edge; with the default `box-sizing: border-box` it eats
  into the 400 px height instead of adding to it.

## Quote card

A large opening quote mark, the quote in italic and an attribution line. Works on every profile.

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

![Quote card on dark teal with a large quote mark, italic quote and author](/img/guide/templates-quote.png)

- `fontStyle: "italic"` uses the registered `Inter-Italic.ttf` face. Without an italic face, bm-render
  synthesises a slanted version of the regular face (see [Fonts](./fonts.md)).
- The quote mark is `“` at 120 px with `lineHeight: "60px"` and `height: 60`, so the big glyph does
  not push the quote down.

## Product card

An e-commerce card with an illustration, a discount badge, a rating, a struck-through old price and a
button. The illustration is an inline SVG string, so this template needs **`standard` or `full`** (on
`core` the image paints nothing and the rest of the card renders).

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

![Product card with a red sneaker illustration, discount badge, rating, price and button](/img/guide/templates-product.png)

- The badge is absolutely positioned inside the image pane, which is `position: "relative"`.
- `overflow: "hidden"` with `borderRadius: 24` clips the pink pane to the card's rounded corners.
- The rating stars (`★` / `☆`) are ordinary characters; Inter has glyphs for both.
- `textDecoration: "line-through"` strikes the old price.

## Event ticket

A ticket with a stub separated by a dashed line and two "punched" notches. Works on every profile.

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

![Purple event ticket with title, date, time, venue, a dashed separator and a seat stub](/img/guide/templates-ticket.png)

- The notches are circles in the page colour, positioned over the top and bottom edges at the separator
  (`left: 506` = 520 − 14). `overflow: "hidden"` on the ticket cuts them into half circles.
- `borderLeft: "2px dashed ..."` on the stub draws the perforation.
- A computed key (`[side]: -14`) puts the same helper at the top or the bottom.

## Certificate

A certificate written as **HTML with a `<style>` block** instead of a node tree — useful when designers
hand over markup. HTML input and stylesheets need **`standard` or `full`**.

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

![Certificate with a double gold border, title, recipient name in italic and two signature fields](/img/guide/templates-certificate.png)

- `border: 3px double` plus an `outline` with a negative `outline-offset` gives the two-line frame.
- `h1` and `p` get Chromium's user-agent margins, which the stylesheet resets with `margin: 0`.
- `.row b { display: block }` stacks the bold value over its label inside each signature field.
- Interpolated values go into HTML unescaped here; escape `&`, `<` and `>` in user input. See
  [HTML and Tailwind](./html-and-tailwind.md).

## Weekly report with a bar graph

A dashboard tile with a headline number, a change badge and a seven-day bar graph made of flex boxes,
the highest day highlighted. Works on every profile. More chart techniques are in [Charts](./charts.md).

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

![Dark report card with a big number, a green change badge and seven bars, Friday highlighted](/img/guide/templates-stats.png)

- Each bar sits in a "plot cell" (`flexGrow: 1`, `justifyContent: "flex-end"`), so its percentage height
  is relative to the free space above the day label.
- `flexBasis: 0` on the day columns makes them equally wide whatever the label length.

## Multi-language card

A card in Tailwind classes with one row per language, including Vietnamese, Greek and Cyrillic. `tw`
needs **`standard` or `full`**.

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

![Card with greetings in Vietnamese, English, German, French, Greek and Russian](/img/guide/templates-multilang.png)

- Vietnamese works on every profile as long as the text is precomposed (NFC) and the font has the
  glyphs; call `text.normalize("NFC")` on user input. See [Typography](./typography.md).
- `style` and `tw` combine on the same node: here `style.fontFamily` switches single rows to Noto Sans.
- The gradient is `bg-linear-to-br` (Tailwind v4 naming); the v3 name `bg-gradient-to-br` is skipped
  silently.
- Scripts that need shaping or bidi (Arabic, Hebrew, Devanagari, Thai) need the `full` profile and a
  font that covers them; colour emoji need `full` and an emoji font.

## Event banner

A dark banner with blurred colour "orbs", a date chip, a big title and speaker initials. Works on every
profile.

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

![Dark event banner with pink and blue glows, a yellow date chip, title and three speakers](/img/guide/templates-event-banner.png)

- The glows are `radial-gradient`s that fade to transparent — cheaper than `filter: blur()` on a large
  box, and available on `core`.
- They are absolutely positioned partly outside the banner; `overflow: "hidden"` on the root clips them.
- The content column is `position: "relative"` so that it paints above the absolutely positioned glows.

## Serving a template from a handler

A fetch-style handler that renders the [Open Graph card](#open-graph-card) from query parameters at the
standard 1200 × 630 size. The same function works in Node 18+, Bun, Deno and Cloudflare Workers (on
Workers, initialise the binary as shown in [Getting started](../getting-started.md#edge-runtimes-deno-bun)).

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

- `devicePixelRatio: 1.5` turns the 800 × 420 design into a 1200 × 630 image without touching the
  template.
- bm-render has no `ImageResponse` helper; `new Response(png, ...)` is all it takes, because the result is
  a `Uint8Array` that owns its buffer.
- Rendering is synchronous and CPU-bound. Cache the result (here with `cache-control`) and see
  [Performance](./performance.md) for worker pools.
