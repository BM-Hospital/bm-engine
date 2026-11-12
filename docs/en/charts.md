# Charts

[English](charts.md) · [Tiếng Việt](../vi/charts.md)

bm-engine has no chart component, and it does not need one: bars and columns are flex boxes whose width
or height is a percentage, rings and pies are `conic-gradient`s, heatmaps are CSS grids, and lines are a
small inline SVG built from your data. This page builds each kind from scratch. Every example on it was
run against bm-engine 0.1.0 by `docs/examples/charts.mjs`, and the image under each snippet is that
script's output.

[[toc]]

## Which technique needs which profile

| Technique | Used for | Profile |
|:--|:--|:--|
| Flex boxes with `%` sizes | bar, column, stacked and progress bars | all (core) |
| CSS grid | heatmaps, small multiples | all (core) |
| `conic-gradient` + `border-radius: 50%` | progress rings, donut and pie charts | all (core) |
| Inline SVG (`<svg>` markup as an image `src`) | sparklines, line and area charts, anything with paths | `standard` / `full` (on `core` an SVG image paints nothing) |
| HTML string or Tailwind `tw` | the same charts written as markup / utility classes | `standard` / `full` |

The examples on this page use the default `bm-engine` entry (the `full` profile on Node). All the
flex, grid and gradient charts render the same on `bm-engine/core`.

## Setup

Every example below uses this renderer and two tiny helpers that save a lot of typing. `box()` makes a
flex container (remember that [`display` defaults to `inline`](./concepts.md), so containers need an
explicit `display`); `text()` makes a text node.

<!-- @example charts#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-SemiBold.ttf") });

// tiny helpers used by every chart on this page
const box = (style, children = []) => ({ type: "container", style: { display: "flex", ...style }, children });
const text = (t, style = {}) => ({ type: "text", text: t, style });
```

Registering two files under the same `name` adds a second face (weight 600) to the `Inter` family, so
`fontWeight: 600` picks the SemiBold file instead of synthesising bold. See [Fonts](./fonts.md).

## Horizontal bars

A bar is a track (a light box that grows to fill the row) with a coloured child whose `width` is the
value as a percentage of the maximum. Fixed-width label columns on both sides keep the tracks aligned.

<!-- @example charts#hbar -->
```js
const languages = [
  { name: "TypeScript", value: 38, color: "#3178c6" },
  { name: "Rust", value: 24, color: "#dea584" },
  { name: "Zig", value: 17, color: "#f7a41d" },
  { name: "Go", value: 12, color: "#00add8" },
  { name: "Python", value: 9, color: "#3572a5" },
];
const max = Math.max(...languages.map((d) => d.value));

const hbar = box(
  { flexDirection: "column", gap: 12, width: "100%", height: "100%", padding: 24,
    backgroundColor: "#ffffff", fontFamily: "Inter", fontSize: 15, color: "#0f172a" },
  [
    text("Share of commits (%)", { fontWeight: 600, fontSize: 18 }),
    ...languages.map((d) =>
      box({ alignItems: "center", gap: 12 }, [
        text(d.name, { width: 90, textAlign: "right", color: "#475569" }),
        box({ flexGrow: 1, height: 22, backgroundColor: "#f1f5f9", borderRadius: 6 }, [
          box({ width: `${(d.value / max) * 100}%`, backgroundColor: d.color, borderRadius: 6 }),
        ]),
        text(`${d.value}`, { width: 32, fontWeight: 600 }),
      ]),
    ),
  ],
);
const hbarPng = renderer.renderSync(hbar, { width: 560, height: 230 });
```

![Horizontal bar chart: five languages with coloured bars](/img/guide/charts-hbar.png)

Things that make this work:

- A text node with a `width` and `textAlign: "right"` is blockified because its parent is a flex
  container, so the width applies.
- The coloured bar has no `height`: as a flex item of a row it stretches to the track's 22 px
  (`align-items: stretch` is the default).
- `fontFamily`, `fontSize` and `color` are set once on the root and inherited by every text node.

## Columns with an axis and grid lines

Columns are the same idea turned upright: the plot area is a flex row with `alignItems: "flex-end"`,
and each column's `height` is a percentage of the plot height. Grid lines are absolutely positioned
1 px boxes placed with `bottom: "<tick>%"`, and the x-axis labels use the same `flexGrow` and `gap` as
the columns so that they line up.

<!-- @example charts#columns -->
```js
const months = [
  ["Jan", 42], ["Feb", 55], ["Mar", 48], ["Apr", 71], ["May", 66], ["Jun", 90],
  ["Jul", 84], ["Aug", 97], ["Sep", 73], ["Oct", 60], ["Nov", 52], ["Dec", 78],
];
const ticks = [100, 75, 50, 25, 0];
const plotHeight = 200;

const columns = box(
  { width: "100%", height: "100%", padding: "20px 24px", backgroundColor: "#0f172a",
    fontFamily: "Inter", fontSize: 12, color: "#94a3b8", gap: 8 },
  [
    // y axis labels, spaced like the grid lines
    // 14px-tall labels centred on the grid lines: the column is 14px taller and starts 7px higher
    box({ flexDirection: "column", justifyContent: "space-between", height: plotHeight + 14, marginTop: -7 },
      ticks.map((t) => text(String(t), { textAlign: "right", width: 24, lineHeight: "14px" }))),
    box({ flexDirection: "column", flexGrow: 1, gap: 6 }, [
      // plot area: absolutely positioned grid lines; the bars are position: relative so that
      // they paint after (above) the lines, as in a browser
      box({ position: "relative", height: plotHeight, alignItems: "flex-end", gap: 8 }, [
        ...ticks.map((t) =>
          box({ position: "absolute", left: 0, right: 0, bottom: `${t}%`, height: 1, backgroundColor: "#334155" })),
        ...months.map(([, v]) =>
          box({ position: "relative", flexGrow: 1, height: `${v}%`, borderRadius: "4px 4px 0 0",
                backgroundImage: "linear-gradient(to top, #6366f1, #22d3ee)" })),
      ]),
      // x axis labels share the bars' flex sizing, so they line up
      box({ gap: 8 }, months.map(([m]) => text(m, { flexGrow: 1, flexBasis: 0, textAlign: "center" }))),
    ]),
  ],
);
const columnsPng = renderer.renderSync(columns, { width: 600, height: 260 });
```

![Column chart with twelve gradient columns, a y axis and grid lines](/img/guide/charts-columns.png)

::: tip Paint order of positioned boxes
bm-engine follows the CSS painting order: positioned boxes paint **after** the in-flow content of
their whole stacking context, whatever their order in `children`. Without `position: "relative"` on the columns, the grid
lines would be drawn across them. Making the columns positioned too lets document order decide (lines
first, then columns); `zIndex` works as well.
:::

The `linear-gradient(to top, ...)` is evaluated per column, so every column runs through the full
gradient regardless of its height. For one gradient across the whole chart, put the gradient on the plot
area and use a `mask-image` or white "gaps" instead (masks need `standard`, see [Effects](./effects.md)).

## Stacked columns with a legend

Stacking is a column whose segments share its height with `flexGrow` set to each series' value.
`flexDirection: "column-reverse"` puts the first series at the bottom. The legend is a row of
swatch + label pairs.

<!-- @example charts#stacked -->
```js
const quarters = [
  { q: "Q1", parts: [30, 20, 10] },
  { q: "Q2", parts: [35, 25, 15] },
  { q: "Q3", parts: [25, 30, 25] },
  { q: "Q4", parts: [40, 30, 20] },
];
const series = [
  { name: "Web", color: "#6366f1" },
  { name: "iOS", color: "#22c55e" },
  { name: "Android", color: "#f59e0b" },
];

const legend = box({ gap: 16 }, series.map((s) =>
  box({ alignItems: "center", gap: 6 }, [
    box({ width: 12, height: 12, borderRadius: 3, backgroundColor: s.color }),
    text(s.name),
  ])));

const stacked = box(
  { flexDirection: "column", width: "100%", height: "100%", padding: 24, gap: 16,
    backgroundColor: "#fafafa", fontFamily: "Inter", fontSize: 14, color: "#334155" },
  [
    box({ justifyContent: "space-between", alignItems: "center" }, [
      text("Active users by platform", { fontSize: 18, fontWeight: 600, color: "#0f172a" }),
      legend,
    ]),
    box({ flexGrow: 1, gap: 28, padding: "0 12px" }, quarters.map((d) => {
      const total = d.parts.reduce((a, b) => a + b);
      return box({ flexDirection: "column", alignItems: "center", gap: 6, flexGrow: 1, flexBasis: 0 }, [
        // the plot cell takes the free height; the bar's % height resolves against it
        box({ flexDirection: "column", justifyContent: "flex-end", alignItems: "center", flexGrow: 1, width: "100%", gap: 4 }, [
          text(`${total}k`, { fontWeight: 600 }),
          // column-reverse stacks the first series at the bottom
          box({ flexDirection: "column-reverse", flexShrink: 0, width: "100%", height: `${total}%`,
                borderRadius: 6, overflow: "hidden" },
            d.parts.map((p, i) => box({ flexGrow: p, backgroundColor: series[i].color }))),
        ]),
        text(d.q, { color: "#64748b" }),
      ]);
    })),
  ],
);
const stackedPng = renderer.renderSync(stacked, { width: 560, height: 300 });
```

![Stacked column chart for four quarters with a three-entry legend](/img/guide/charts-stacked.png)

Two details matter here:

- **Where the percentage resolves.** A `height: "90%"` resolves against the column's *parent*. Here the
  parent is a "plot cell" that takes the free height with `flexGrow: 1`; had the bar been a direct child
  of the column that also holds the labels, 100 % would include the labels' height and the bars would be
  shrunk to fit (`flexShrink: 0` keeps the bar at its percentage).
- **Rounded stacks.** `overflow: "hidden"` with `borderRadius` on the stack clips the segments to the
  rounded shape, so the individual segments need no radius.

## Heatmap with CSS grid

A contribution-style heatmap is a grid with one label column and fixed-size cells. Grid items are
blockified like flex items, so plain `box()` cells need no further `display`.

<!-- @example charts#grid-heatmap -->
```js
const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const activity = days.map((_, d) => Array.from({ length: 12 }, (_, w) => (d * 7 + w * 5) % 11));
const shade = (v) => ["#ebedf0", "#9be9a8", "#40c463", "#30a14e", "#216e39"][Math.min(4, Math.floor(v / 2.5))];

const heatmap = {
  type: "container",
  style: { display: "grid", gridTemplateColumns: "40px repeat(12, 18px)", gridAutoRows: "18px", gap: 4,
           padding: 20, backgroundColor: "#ffffff", fontFamily: "Inter", fontSize: 11, color: "#57606a" },
  children: days.flatMap((day, d) => [
    text(day, { alignSelf: "center" }),
    ...activity[d].map((v) => box({ backgroundColor: shade(v), borderRadius: 3 })),
  ]),
};
const heatmapPng = renderer.renderSync(heatmap);
```

![Seven-by-twelve heatmap of green squares with weekday labels](/img/guide/charts-grid-heatmap.png)

`renderSync(heatmap)` is called **without** `width` / `height`: the canvas then takes the size of the
laid-out root (here the grid's max-content size plus padding), which is handy for charts whose size
follows from the data. See [Concepts](./concepts.md) for how the canvas size is chosen.

## Progress rings

`conic-gradient(color P%, track 0)` paints a hard-edged wedge from 12 o'clock clockwise; a second stop
position of `0` makes the track start exactly where the value ends. A white circle on top turns the pie
into a ring and holds the label.

<!-- @example charts#ring -->
```js
// a progress ring: a conic gradient with a solid "hole" on top
const ring = (percent, color, label) =>
  box({ flexDirection: "column", alignItems: "center", gap: 10 }, [
    box({ width: 120, height: 120, borderRadius: "50%", alignItems: "center", justifyContent: "center",
          backgroundImage: `conic-gradient(${color} ${percent}%, #e2e8f0 0)` }, [
      box({ width: 92, height: 92, borderRadius: "50%", backgroundColor: "#ffffff",
            alignItems: "center", justifyContent: "center" }, [
        text(`${percent}%`, { fontSize: 26, fontWeight: 600, color: "#0f172a" }),
      ]),
    ]),
    text(label, { fontSize: 14, color: "#64748b" }),
  ]);

const rings = box(
  { width: "100%", height: "100%", alignItems: "center", justifyContent: "space-around",
    backgroundColor: "#ffffff", fontFamily: "Inter" },
  [ring(72, "#6366f1", "Storage"), ring(45, "#22c55e", "Bandwidth"), ring(91, "#ef4444", "Build minutes")],
);
const ringsPng = renderer.renderSync(rings, { width: 520, height: 200 });
```

![Three progress rings at 72, 45 and 91 percent](/img/guide/charts-ring.png)

The "hole" only works on an opaque background. For a transparent hole, cut it out with
`maskImage: "radial-gradient(circle, transparent 46px, black 47px)"` instead (masks need `standard`;
on `core` the mask is ignored and you get a full pie). Start the ring elsewhere with
`conic-gradient(from -90deg, ...)`.

## Donut and pie charts

Several slices are several hard stops in one conic gradient: each slice is `color start% end%`. Build the
stop list from the data:

<!-- @example charts#donut -->
```js
const shares = [
  { name: "Chrome", value: 64, color: "#4285f4" },
  { name: "Safari", value: 19, color: "#0fb5ee" },
  { name: "Edge", value: 5, color: "#0078d7" },
  { name: "Firefox", value: 3, color: "#ff7139" },
  { name: "Other", value: 9, color: "#cbd5e1" },
];
// build "color start% end%" stops for every slice
let acc = 0;
const stops = shares.map((s) => `${s.color} ${acc}% ${(acc += s.value)}%`).join(", ");

const donut = box(
  { width: "100%", height: "100%", alignItems: "center", gap: 36, padding: "0 36px",
    backgroundColor: "#ffffff", fontFamily: "Inter", fontSize: 15, color: "#334155" },
  [
    box({ width: 180, height: 180, borderRadius: "50%", alignItems: "center", justifyContent: "center",
          backgroundImage: `conic-gradient(${stops})` }, [
      box({ width: 104, height: 104, borderRadius: "50%", backgroundColor: "#ffffff",
            flexDirection: "column", alignItems: "center", justifyContent: "center" }, [
        text("Browsers", { fontSize: 13, color: "#64748b" }),
        text("2026", { fontSize: 22, fontWeight: 600, color: "#0f172a" }),
      ]),
    ]),
    box({ flexDirection: "column", gap: 8 }, shares.map((s) =>
      box({ alignItems: "center", gap: 8 }, [
        box({ width: 12, height: 12, borderRadius: 6, backgroundColor: s.color }),
        text(s.name, { width: 70 }),
        text(`${s.value}%`, { fontWeight: 600 }),
      ]))),
  ],
);
const donutPng = renderer.renderSync(donut, { width: 460, height: 230 });
```

![Donut chart with five browser slices and a legend](/img/guide/charts-donut.png)

Drop the inner circle for a pie. The stop list is ordinary CSS, so `conic-gradient(from 45deg, ...)`
rotates the whole chart and a `0.5%` gap of white between slices separates them visually.

## Sparklines with inline SVG

Lines need paths, and paths are what SVG is for. Build an SVG string from the data and put it in an
image node's `src` — markup is accepted directly, no `data:` URL or `images` entry needed. A polygon
under the polyline gives the area fill.

<!-- @example charts#sparkline -->
```js
// builds an SVG polyline (plus a filled area) from a list of numbers
function sparkline(values, { width, height, color }) {
  const min = Math.min(...values), max = Math.max(...values);
  const pts = values.map((v, i) => [
    (i / (values.length - 1)) * width,
    height - 4 - ((v - min) / (max - min)) * (height - 8),
  ]);
  const line = pts.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
    <polygon points="0,${height} ${line} ${width},${height}" fill="${color}" fill-opacity="0.15"/>
    <polyline points="${line}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>
  </svg>`;
}

const stat = (label, value, delta, values, color) =>
  box({ flexDirection: "column", gap: 4, padding: 16, flexGrow: 1, flexBasis: 0,
        border: "1px solid #e2e8f0", borderRadius: 12, backgroundColor: "#ffffff" }, [
    text(label, { fontSize: 13, color: "#64748b" }),
    box({ alignItems: "baseline", gap: 8 }, [
      text(value, { fontSize: 26, fontWeight: 600, color: "#0f172a" }),
      text(delta, { fontSize: 13, fontWeight: 600, color }),
    ]),
    { type: "image", src: sparkline(values, { width: 220, height: 48, color }), width: 220, height: 48 },
  ]);

const kpis = box(
  { width: "100%", height: "100%", gap: 16, padding: 20, backgroundColor: "#f8fafc", fontFamily: "Inter" },
  [
    stat("Revenue", "$48.2k", "+12.4%", [12, 14, 13, 17, 16, 19, 22, 21, 25, 27, 26, 31], "#16a34a"),
    stat("Churn", "2.9%", "-0.6%", [5, 4.8, 4.9, 4.4, 4.1, 3.9, 3.6, 3.7, 3.3, 3.1, 3.0, 2.9], "#ef4444"),
  ],
);
const kpisPng = renderer.renderSync(kpis, { width: 560, height: 180 });
```

![Two KPI cards, each with a value, a delta and a sparkline](/img/guide/charts-sparkline.png)

::: warning SVG needs standard or full
On `bm-engine/core` an SVG image is not decoded and paints nothing (no error). This was checked: the
sparkline above renders zero opaque pixels on `core`. Use `bm-engine/standard` or `bm-engine/full` for
any SVG-based chart, or stay with the flex / gradient techniques.
:::

## A complete line chart in one SVG

For anything more than a sparkline it is simpler to draw the whole chart — title, legend, grid,
axis labels and series — as one SVG. `<text>` elements inside an SVG image are drawn with the fonts
registered on the renderer, so labels match the rest of the image.

<!-- @example charts#line-chart -->
```js
const W = 600, H = 280;                              // whole chart, one SVG
const plotArea = { left: 44, top: 48, right: 584, bottom: 244 };
const visits = [120, 180, 150, 220, 260, 210, 300, 340, 310, 390, 420, 470];
const signups = [20, 35, 30, 50, 45, 60, 80, 70, 95, 110, 105, 140];
const yMax = 500;
const x = (i) => plotArea.left + 8 + (i / 11) * (plotArea.right - plotArea.left - 16);
const y = (v) => plotArea.bottom - (v / yMax) * (plotArea.bottom - plotArea.top);
const points = (vals) => vals.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ");

const chartSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"
     font-family="Inter" font-size="12" fill="#64748b">
  <rect width="${W}" height="${H}" fill="#ffffff"/>
  <text x="20" y="28" font-size="16" font-weight="600" fill="#0f172a">Traffic 2026</text>
  <line x1="430" x2="446" y1="24" y2="24" stroke="#6366f1" stroke-width="3"/><text x="452" y="28">Visits</text>
  <line x1="500" x2="516" y1="24" y2="24" stroke="#f97316" stroke-width="3"/><text x="522" y="28">Sign-ups</text>
  ${[0, 100, 200, 300, 400, 500].map((t) => `
  <line x1="${plotArea.left}" x2="${plotArea.right}" y1="${y(t)}" y2="${y(t)}" stroke="#e2e8f0"/>
  <text x="${plotArea.left - 8}" y="${y(t) + 4}" text-anchor="end">${t}</text>`).join("")}
  ${"JFMAMJJASOND".split("").map((m, i) => `<text x="${x(i)}" y="${H - 16}" text-anchor="middle">${m}</text>`).join("")}
  <polyline points="${points(visits)}" fill="none" stroke="#6366f1" stroke-width="3" stroke-linejoin="round"/>
  <polyline points="${points(signups)}" fill="none" stroke="#f97316" stroke-width="3" stroke-dasharray="6 4"/>
  ${visits.map((v, i) => `<circle cx="${x(i)}" cy="${y(v)}" r="4" fill="#fff" stroke="#6366f1" stroke-width="2"/>`).join("")}
</svg>`;

// the SVG string goes straight into an image node; its <text> uses the registered fonts
const linePng = renderer.renderSync({ type: "image", src: chartSvg, width: W, height: H }, { width: W, height: H });
```

![Line chart with two series, a dashed line, grid lines and axis labels](/img/guide/charts-line-chart.png)

### What SVG text supports

SVG text in bm-engine 0.1.0 is deliberately simple. Each `<text>` element becomes **one run** at its `x` /
`y`, using `font-family`, `font-size`, `font-weight`, `text-anchor` and a **solid** `fill` (inherited from
ancestors such as the root `<svg>`, as above). This test shows the limits:

<!-- @example charts#svg-text -->
```js
const textTest = `<svg xmlns="http://www.w3.org/2000/svg" width="420" height="150" font-family="Inter" font-size="18">
  <rect width="420" height="150" fill="#fff"/>
  <line x1="210" x2="210" y1="0" y2="150" stroke="#cbd5e1"/>
  <text x="210" y="30" text-anchor="start" fill="#0f172a">start</text>
  <text x="210" y="56" text-anchor="middle" fill="#0f172a">middle</text>
  <text x="210" y="82" text-anchor="end" font-weight="600" fill="#6366f1">end, bold</text>
  <text x="20" y="112" fill="#0f172a">a <tspan fill="red" font-weight="600">tspan</tspan> keeps the parent style</text>
  <text x="20" y="140" fill="url(#none)">gradient / url() fill: not drawn</text>
</svg>`;
const svgTextPng = renderer.renderSync({ type: "image", src: textTest, width: 420, height: 150 }, { width: 420, height: 150 });
```

![SVG text test: anchors work, tspan styling is ignored, gradient-filled text is missing](/img/guide/charts-svg-text.png)

- `text-anchor` `start` / `middle` / `end` and `font-weight` work.
- `<tspan>` (and `<textPath>`) content is appended to its parent's run; the tspan's own `fill`,
  `font-weight`, `x`, `y`, `dx`, `dy` are ignored. Use separate `<text>` elements instead.
- Text with a gradient or pattern fill (`fill="url(#...)"`) is not drawn; neither is stroke-only text.
- Without a registered font, SVG text draws nothing — exactly like ordinary text nodes.

## Using a chart library

Libraries that can produce an SVG string without a browser (ECharts with `ssr: true` +
`renderToSVGString()`, Vega's `toSVG()`, d3-shape / d3-scale paths, React SVG components through
`renderToStaticMarkup()`) can feed bm-engine the same way: pass the string as the `src` of an image node,
with `width` / `height`. Nothing in this guide was tested with those libraries, so check their output
against two constraints:

- the SVG features listed in [Images](./images.md) (no `feTurbulence`, `feImage`, lighting filters,
  external references), and
- the text rules above: labels made of `<tspan>`s with their own positions or colours will not come out
  as the library intended. When that matters, let the library draw shapes only and put the labels around
  the image as text nodes, as in the [columns](#columns-with-an-axis-and-grid-lines) example.

Turn off library animations before exporting (a half-finished frame is what you would get), and register
fonts covering every label.

## The same chart as HTML

Charts are just markup, so the HTML input works too (needs `standard` / `full`). A template literal
generates one row per data point:

<!-- @example charts#html -->
```js
const html = `
<div style="display:flex; flex-direction:column; gap:10px; width:100%; height:100%; padding:20px;
            background:#fff; font-family:Inter; font-size:14px; color:#334155">
  <div style="font-size:17px; font-weight:600; color:#0f172a">Build time (s)</div>
  ${[["main", 182], ["release", 241], ["nightly", 96]].map(([branch, s]) => `
  <div style="display:flex; align-items:center; gap:10px">
    <span style="width:64px">${branch}</span>
    <div style="display:flex; height:18px; width:${(s / 241) * 360}px; border-radius:4px;
                background:linear-gradient(90deg,#a78bfa,#7c3aed)"></div>
    <b>${s}</b>
  </div>`).join("")}
</div>`;
const htmlPng = renderer.renderSync(html, { width: 500, height: 150 });
```

![Bar chart rendered from an HTML string](/img/guide/charts-html.png)

Escape user-provided labels (`&`, `<`) before interpolating them into HTML. More in
[HTML and Tailwind](./html-and-tailwind.md).

## The same chart with Tailwind

With `tw` (standard / full) the bars are utility classes; the data-dependent height stays in `style`,
which also wins over `tw` when both set the same property.

<!-- @example charts#tailwind -->
```js
const bars = [["Mon", 40], ["Tue", 65], ["Wed", 50], ["Thu", 85], ["Fri", 70]];
const twChart = {
  type: "container",
  tw: "flex items-end gap-3 w-full h-full p-5 bg-slate-900",
  style: { fontFamily: "Inter" },
  children: bars.map(([day, v]) => ({
    type: "container",
    tw: "flex flex-col items-center justify-end gap-1 grow h-full",
    children: [
      { type: "text", tw: "text-xs text-slate-300", text: `${v}` },
      { type: "container", tw: "w-full rounded-t-md bg-linear-to-t from-emerald-500 to-lime-300", style: { height: `${v}%` } },
      { type: "text", tw: "text-xs text-slate-400", text: day },
    ],
  })),
};
const twPng = renderer.renderSync(twChart, { width: 360, height: 200 });
```

![Five gradient columns styled with Tailwind classes](/img/guide/charts-tailwind.png)

::: warning Tailwind v4 gradient names
The gradient utility is `bg-linear-to-t` (Tailwind v4). The v3 name `bg-gradient-to-t` is not part of
the supported subset and is skipped **silently** — the bars would simply be invisible. The same is true
in takumi.
:::

## Tips

- **Equal columns**: give siblings `flexGrow: 1, flexBasis: 0`; with the default `flexBasis: auto` a
  wider label makes its column wider.
- **Values from 0 to max**: compute percentages in JavaScript (`value / max * 100`) and keep the scale
  logic out of the node tree. `calc()` also works in styles, but plain numbers are easier to debug.
- **Long labels**: fit them with `textOverflow: "ellipsis"` plus `overflow: "hidden"` and
  `whiteSpace: "nowrap"`, or measure them first with [`measure()`](./measure.md).
- **Crisp 1 px lines**: give lines integer positions and sizes; the `%` offsets of the grid lines above
  land on whole pixels because the plot height (200) divides evenly.
- **Retina output**: render at 2× with `devicePixelRatio: 2` and twice the `width` / `height`; the node
  tree stays the same (see [Output formats](./formats.md)).
- Ready-made cards that combine these charts with text are in [Templates](./templates.md).
