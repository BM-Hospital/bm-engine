# Biểu đồ

[English](../../en/image/charts.md) · [Tiếng Việt](charts.md)

bm-render không có component biểu đồ, và cũng không cần: thanh ngang hay cột chỉ là các flex box có
chiều rộng hoặc chiều cao tính theo phần trăm, vòng tiến độ và biểu đồ tròn là `conic-gradient`, heatmap
là CSS grid, còn đường kẻ là một đoạn SVG nhỏ dựng từ dữ liệu của bạn. Trang này dựng từng loại từ đầu.
Mọi ví dụ trên trang đều đã được chạy với bm-render 0.1.0 bằng `docs/examples/charts.mjs`, và ảnh dưới mỗi
đoạn mã chính là kết quả của script đó.

[[toc]]

## Kỹ thuật nào cần profile nào

| Kỹ thuật | Dùng cho | Profile |
|:--|:--|:--|
| Flex box với kích thước `%` | thanh ngang, cột, cột chồng, thanh tiến độ | tất cả (core) |
| CSS grid | heatmap, nhiều biểu đồ nhỏ xếp lưới | tất cả (core) |
| `conic-gradient` + `border-radius: 50%` | vòng tiến độ, biểu đồ donut và pie | tất cả (core) |
| SVG inline (chuỗi `<svg>` làm `src` của ảnh) | sparkline, biểu đồ đường và vùng, mọi thứ cần path | `standard` / `full` (trên `core` ảnh SVG không vẽ gì) |
| Chuỗi HTML hoặc Tailwind `tw` | cùng các biểu đồ đó nhưng viết bằng markup / utility class | `standard` / `full` |

Các ví dụ trên trang dùng điểm vào mặc định `bm-render` (profile `full` trên Node). Mọi biểu đồ dựng bằng
flex, grid và gradient đều render giống hệt trên `bm-render/core`.

## Chuẩn bị

Mọi ví dụ bên dưới dùng renderer này cùng hai hàm trợ giúp nhỏ cho đỡ gõ. `box()` tạo một flex
container (nhớ rằng [`display` mặc định là `inline`](./concepts.md), nên container cần khai báo `display`
rõ ràng); `text()` tạo một text node.

<!-- @example charts#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-SemiBold.ttf") });

// tiny helpers used by every chart on this page
const box = (style, children = []) => ({ type: "container", style: { display: "flex", ...style }, children });
const text = (t, style = {}) => ({ type: "text", text: t, style });
```

Đăng ký hai file dưới cùng một `name` sẽ thêm face thứ hai (weight 600) vào family `Inter`, nên
`fontWeight: 600` chọn đúng file SemiBold thay vì tự giả lập chữ đậm. Xem [Font](./fonts.md).

## Thanh ngang

Mỗi thanh gồm một rãnh (một box nhạt giãn ra lấp đầy hàng) và một box con có màu với `width` bằng giá
trị tính theo phần trăm của giá trị lớn nhất. Hai cột nhãn có chiều rộng cố định ở hai bên giữ cho các
rãnh thẳng hàng.

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

![Biểu đồ thanh ngang: năm ngôn ngữ với các thanh màu](/img/guide/charts-hbar.png)

Những điều giúp ví dụ này chạy đúng:

- Text node có `width` và `textAlign: "right"` được blockify vì cha của nó là flex container, nên
  `width` có tác dụng.
- Thanh màu không có `height`: là flex item trong một hàng, nó tự giãn bằng 22 px của rãnh
  (`align-items: stretch` là mặc định).
- `fontFamily`, `fontSize` và `color` chỉ đặt một lần ở root và được mọi text node kế thừa.

## Cột kèm trục và đường lưới

Biểu đồ cột là cùng ý tưởng nhưng dựng đứng: vùng vẽ là một flex row với `alignItems: "flex-end"`, và
`height` của mỗi cột là phần trăm chiều cao vùng vẽ. Đường lưới là các box 1 px định vị tuyệt đối bằng
`bottom: "<tick>%"`, còn nhãn trục x dùng cùng `flexGrow` và `gap` với các cột để thẳng hàng với chúng.

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

![Biểu đồ cột với mười hai cột gradient, trục y và đường lưới](/img/guide/charts-columns.png)

::: tip Thứ tự vẽ của box được định vị
bm-render theo đúng thứ tự vẽ của CSS: box được định vị được vẽ **sau** toàn bộ nội dung trong luồng
của stacking context chứa nó, bất kể thứ tự trong `children`. Nếu các cột không có `position: "relative"`, đường lưới sẽ bị vẽ đè lên
chúng. Cho các cột cũng là box định vị thì thứ tự trong tài liệu quyết định (đường trước, cột sau);
dùng `zIndex` cũng được.
:::

`linear-gradient(to top, ...)` được tính riêng cho từng cột, nên cột nào cũng chạy hết dải màu bất kể
cao thấp. Muốn một dải màu trải trên cả biểu đồ, hãy đặt gradient lên vùng vẽ và dùng `mask-image`
hoặc các "khe" màu nền (mask cần `standard`, xem [Hiệu ứng](./effects.md)).

## Cột chồng kèm chú giải

Cột chồng là một cột mà các đoạn chia nhau chiều cao bằng `flexGrow` đặt theo giá trị của từng chuỗi dữ
liệu. `flexDirection: "column-reverse"` đặt chuỗi đầu tiên ở dưới cùng. Chú giải là một hàng gồm các cặp
ô màu + nhãn.

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

![Biểu đồ cột chồng cho bốn quý với chú giải ba mục](/img/guide/charts-stacked.png)

Có hai chi tiết quan trọng:

- **Phần trăm được tính theo cái gì.** `height: "90%"` tính theo *cha* của cột. Ở đây cha là một "ô vẽ"
  chiếm phần chiều cao còn trống nhờ `flexGrow: 1`; nếu thanh là con trực tiếp của cột chứa cả nhãn thì
  100 % sẽ gồm cả chiều cao nhãn và các thanh bị co lại cho vừa (`flexShrink: 0` giữ thanh đúng phần trăm).
- **Bo góc cả chồng.** `overflow: "hidden"` cùng `borderRadius` trên chồng cột sẽ cắt các đoạn theo
  hình bo góc, nên từng đoạn không cần bo riêng.

## Heatmap bằng CSS grid

Heatmap kiểu biểu đồ đóng góp là một lưới có một cột nhãn và các ô kích thước cố định. Grid item được
blockify giống flex item, nên các ô `box()` không cần khai báo thêm `display`.

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

![Heatmap bảy nhân mười hai ô vuông xanh lá kèm nhãn ngày trong tuần](/img/guide/charts-grid-heatmap.png)

`renderSync(heatmap)` được gọi **không có** `width` / `height`: khi đó canvas lấy kích thước của root sau
khi layout (ở đây là kích thước max-content của lưới cộng padding), rất tiện cho biểu đồ có kích thước
phụ thuộc dữ liệu. Xem [Khái niệm](./concepts.md) để biết kích thước canvas được chọn thế nào.

## Vòng tiến độ

`conic-gradient(color P%, track 0)` vẽ một hình quạt cạnh sắc bắt đầu từ hướng 12 giờ theo chiều kim đồng
hồ; vị trí stop thứ hai bằng `0` khiến phần rãnh bắt đầu đúng chỗ giá trị kết thúc. Một hình tròn trắng
đặt lên trên biến hình quạt thành vòng và chứa nhãn.

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

![Ba vòng tiến độ ở mức 72, 45 và 91 phần trăm](/img/guide/charts-ring.png)

Cái "lỗ" chỉ dùng được trên nền đặc. Muốn lỗ trong suốt, hãy khoét bằng
`maskImage: "radial-gradient(circle, transparent 46px, black 47px)"` (mask cần `standard`; trên `core`
mask bị bỏ qua và bạn nhận được một hình tròn đặc). Muốn vòng bắt đầu ở chỗ khác thì dùng
`conic-gradient(from -90deg, ...)`.

## Biểu đồ donut và pie

Nhiều lát là nhiều stop cứng trong cùng một conic gradient: mỗi lát là `color start% end%`. Hãy dựng danh
sách stop từ dữ liệu:

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

![Biểu đồ donut với năm lát trình duyệt và chú giải](/img/guide/charts-donut.png)

Bỏ hình tròn bên trong là có biểu đồ pie. Danh sách stop là CSS bình thường, nên
`conic-gradient(from 45deg, ...)` xoay cả biểu đồ, và chèn một khe trắng `0.5%` giữa các lát sẽ tách
chúng ra cho dễ nhìn.

## Sparkline bằng SVG inline

Đường kẻ cần path, và path chính là việc của SVG. Hãy dựng một chuỗi SVG từ dữ liệu rồi đặt vào `src`
của image node — markup được nhận trực tiếp, không cần URL `data:` hay mục `images`. Một polygon nằm dưới
polyline tạo phần tô vùng.

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

![Hai thẻ KPI, mỗi thẻ có giá trị, mức thay đổi và một sparkline](/img/guide/charts-sparkline.png)

::: warning SVG cần standard hoặc full
Trên `bm-render/core` ảnh SVG không được giải mã và không vẽ gì (không báo lỗi). Điều này đã được kiểm
tra: sparkline ở trên cho ra 0 pixel không trong suốt trên `core`. Hãy dùng `bm-render/standard` hoặc
`bm-render/full` cho mọi biểu đồ dựa trên SVG, hoặc giữ các kỹ thuật flex / gradient.
:::

## Một biểu đồ đường hoàn chỉnh trong một SVG

Với thứ gì phức tạp hơn sparkline, vẽ cả biểu đồ — tiêu đề, chú giải, lưới, nhãn trục và các chuỗi dữ liệu
— trong một SVG sẽ đơn giản hơn. Các phần tử `<text>` trong ảnh SVG được vẽ bằng font đã đăng ký trên
renderer, nên nhãn khớp với phần còn lại của ảnh.

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

![Biểu đồ đường với hai chuỗi, một đường nét đứt, đường lưới và nhãn trục](/img/guide/charts-line-chart.png)

### SVG text hỗ trợ những gì

Text trong SVG ở bm-render 0.1.0 được giữ đơn giản có chủ đích. Mỗi phần tử `<text>` trở thành **một
run** tại `x` / `y` của nó, dùng `font-family`, `font-size`, `font-weight`, `text-anchor` và `fill`
**màu đặc** (kế thừa từ phần tử tổ tiên như `<svg>` gốc, như ở trên). Phép thử sau cho thấy giới hạn:

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

![Phép thử SVG text: anchor hoạt động, style của tspan bị bỏ qua, chữ tô gradient không hiện](/img/guide/charts-svg-text.png)

- `text-anchor` `start` / `middle` / `end` và `font-weight` hoạt động.
- Nội dung `<tspan>` (và `<textPath>`) được nối vào run của phần tử cha; `fill`, `font-weight`, `x`, `y`,
  `dx`, `dy` riêng của tspan bị bỏ qua. Hãy dùng các phần tử `<text>` riêng thay thế.
- Chữ tô bằng gradient hoặc pattern (`fill="url(#...)"`) không được vẽ; chữ chỉ có stroke cũng vậy.
- Không có font nào được đăng ký thì SVG text không vẽ gì — y như text node thông thường.

## Dùng thư viện biểu đồ

Các thư viện có thể xuất chuỗi SVG mà không cần trình duyệt (ECharts với `ssr: true` +
`renderToSVGString()`, `toSVG()` của Vega, path từ d3-shape / d3-scale, component SVG của React qua
`renderToStaticMarkup()`) có thể đưa vào bm-render theo cùng cách: truyền chuỗi làm `src` của image node,
kèm `width` / `height`. Hướng dẫn này chưa thử với các thư viện đó, nên hãy đối chiếu đầu ra của chúng với
hai ràng buộc:

- các tính năng SVG liệt kê ở trang [Ảnh](./images.md) (không có `feTurbulence`, `feImage`, filter chiếu
  sáng, tham chiếu ra ngoài), và
- các quy tắc text ở trên: nhãn tạo bằng `<tspan>` có vị trí hoặc màu riêng sẽ không ra đúng ý thư viện.
  Khi điều đó quan trọng, để thư viện chỉ vẽ hình rồi đặt nhãn quanh ảnh bằng text node, như ví dụ
  [cột kèm trục](#cột-kèm-trục-và-đường-lưới).

Tắt animation của thư viện trước khi xuất (nếu không bạn sẽ nhận một khung hình đang vẽ dở), và đăng ký
font phủ mọi nhãn.

## Cùng biểu đồ đó bằng HTML

Biểu đồ chỉ là markup, nên đầu vào HTML cũng dùng được (cần `standard` / `full`). Một template literal
sinh ra mỗi hàng cho một điểm dữ liệu:

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

![Biểu đồ thanh render từ chuỗi HTML](/img/guide/charts-html.png)

Hãy escape nhãn do người dùng nhập (`&`, `<`) trước khi chèn vào HTML. Xem thêm ở
[HTML và Tailwind](./html-and-tailwind.md).

## Cùng biểu đồ đó với Tailwind

Với `tw` (standard / full), các thanh là utility class; chiều cao phụ thuộc dữ liệu vẫn để trong `style`,
và `style` cũng thắng `tw` khi cả hai cùng đặt một thuộc tính.

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

![Năm cột gradient tạo kiểu bằng class Tailwind](/img/guide/charts-tailwind.png)

::: warning Tên gradient của Tailwind v4
Utility gradient là `bg-linear-to-t` (Tailwind v4). Tên cũ của v3 là `bg-gradient-to-t` không nằm trong
tập con được hỗ trợ và bị bỏ qua **trong im lặng** — các cột sẽ đơn giản là vô hình.
:::

## Mẹo

- **Cột đều nhau**: đặt `flexGrow: 1, flexBasis: 0` cho các anh em; với `flexBasis: auto` mặc định, nhãn
  dài hơn sẽ làm cột của nó rộng hơn.
- **Giá trị từ 0 tới max**: tính phần trăm trong JavaScript (`value / max * 100`) và giữ logic tỉ lệ bên
  ngoài cây node. `calc()` cũng dùng được trong style, nhưng số thuần dễ gỡ lỗi hơn.
- **Nhãn dài**: cắt bớt bằng `textOverflow: "ellipsis"` cùng `overflow: "hidden"` và
  `whiteSpace: "nowrap"`, hoặc đo trước bằng [`measure()`](./measure.md).
- **Đường 1 px sắc nét**: cho đường kẻ vị trí và kích thước nguyên; offset `%` của đường lưới ở trên rơi
  đúng pixel nguyên vì chiều cao vùng vẽ (200) chia hết.
- **Ảnh cho màn hình retina**: render ở 2× với `devicePixelRatio: 2` và gấp đôi `width` / `height`; cây
  node giữ nguyên (xem [Định dạng đầu ra](./formats.md)).
- Các thẻ dựng sẵn kết hợp những biểu đồ này với chữ có ở trang [Mẫu](./templates.md).
