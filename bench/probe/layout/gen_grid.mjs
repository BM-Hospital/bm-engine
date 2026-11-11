// Grid fixtures (loaded by gen.mjs).


export function addGrid({ add, F, B, G, box, words, rnd, pick, maybe, c }) {
  const cell = (h, extra = {}) => F({ height: h, ...extra });
  const cells = (n, h = 20) => Array.from({ length: n }, (_, i) => cell(h + (i % 3) * 5));

  add("grid/fixed-cols", G({ width: 300, gridTemplateColumns: "100px 50px 80px" }, ...cells(5)));
  add("grid/fixed-rows-cols", G({ width: 300, height: 200, gridTemplateColumns: "100px 50px", gridTemplateRows: "30px 60px" }, ...cells(4)));
  add("grid/fr", G({ width: 300, gridTemplateColumns: "1fr 2fr 1fr" }, ...cells(4)));
  add("grid/fr-fixed-gap", G({ width: 300, gridTemplateColumns: "100px 1fr", gap: 10 }, ...cells(3), cell(20, { gridColumn: "span 2" })));
  add("grid/fr-fractional", G({ width: 300, gridTemplateColumns: "0.3fr 0.2fr" }, ...cells(2)));
  add("grid/fr-min-content", G({ width: 200, gridTemplateColumns: "1fr 1fr" }, F({}, box(150, 20, { flexShrink: 0 })), cell(10)));
  add("grid/fr-rows", G({ width: 300, height: 200, gridTemplateColumns: "1fr 1fr", gridTemplateRows: "1fr 3fr" }, ...cells(4)));
  add("grid/fr-rows-auto-height", G({ width: 300, gridTemplateColumns: "1fr 1fr", gridTemplateRows: "1fr 3fr" }, ...cells(4)));
  add("grid/percent", G({ width: 300, height: 200, gridTemplateColumns: "25% 50%", gridTemplateRows: "10% 40%" }, ...cells(4)));
  add("grid/percent-auto-height", G({ width: 300, gridTemplateColumns: "25% 50%", gridTemplateRows: "50% 50%" }, ...cells(4)));
  add("grid/auto-cols", G({ width: 300, gridTemplateColumns: "auto auto" }, box(50, 20), box(80, 30), box(20, 10)));
  add("grid/auto-cols-start", G({ width: 300, gridTemplateColumns: "auto auto", justifyContent: "start" }, box(50, 20), box(80, 30), box(20, 10)));
  add("grid/min-max-content", G({ width: 300, gridTemplateColumns: "min-content max-content 1fr" }, words(3), words(3), cell(10)));
  add("grid/minmax", G({ width: 300, gridTemplateColumns: "minmax(50px, 100px) minmax(100px, 1fr) minmax(auto, 60px)" }, ...cells(3)));
  add("grid/minmax-overflow", G({ width: 150, gridTemplateColumns: "minmax(50px, 100px) minmax(100px, 1fr)" }, ...cells(2)));
  add("grid/minmax-content", G({ width: 300, gridTemplateColumns: "minmax(min-content, max-content) minmax(20px, max-content) 1fr" }, words(3), words(2), cell(10)));
  add("grid/fit-content", G({ width: 300, gridTemplateColumns: "fit-content(50px) fit-content(200px) 1fr" }, words(4), words(4), cell(10)));
  add("grid/no-template", G({ width: 300 }, ...cells(3)));
  add("grid/auto-rows", G({ width: 300, gridTemplateColumns: "1fr 1fr", gridAutoRows: "40px" }, ...cells(5)));
  add("grid/auto-rows-list", G({ width: 300, gridTemplateColumns: "1fr 1fr", gridAutoRows: "40px 10px" }, ...cells(7)));
  add("grid/auto-rows-minmax", G({ width: 300, gridTemplateColumns: "1fr 1fr", gridAutoRows: "minmax(25px, auto)" }, ...cells(5)));
  add("grid/auto-flow-column", G({ width: 300, height: 100, gridTemplateRows: "40px 40px", gridAutoFlow: "column", gridAutoColumns: "50px" }, ...cells(5)));
  add("grid/auto-flow-column-auto", G({ width: 300, gridTemplateRows: "40px 40px", gridAutoFlow: "column" }, box(20, 10), box(30, 10), box(40, 10)));
  add("grid/gap", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr", columnGap: 10, rowGap: 5 }, ...cells(6)));
  add("grid/gap-percent", G({ width: 300, height: 200, gridTemplateColumns: "1fr 1fr", gap: "10%" }, ...cells(4)));
  add("grid/padding-border", G({ width: 300, padding: 10, borderWidth: 3, borderStyle: "solid", gridTemplateColumns: "1fr 1fr", gap: 4 }, ...cells(3)));
  add("grid/span", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr", gap: 6 }, cell(20, { gridColumn: "span 2" }), cell(20), cell(30, { gridRow: "span 2" }), cell(20, { gridColumn: "span 2" }), cell(15)));
  add("grid/lines", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr", gridTemplateRows: "30px 30px" }, cell(20, { gridColumn: "2 / 4", gridRow: 1 }), cell(20, { gridColumn: 1, gridRow: "1 / 3" }), cell(20, { gridColumn: 3, gridRow: 2 }), cell(10)));
  add("grid/lines-negative", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr" }, cell(20, { gridColumn: "1 / -1" }), cell(20, { gridColumn: "-2 / -1" }), cell(20, { gridColumn: "-3" })));
  add("grid/lines-implicit", G({ width: 300, gridTemplateColumns: "100px", gridAutoColumns: "40px" }, cell(20, { gridColumn: 3 }), cell(20), cell(20, { gridColumn: "2 / span 3" })));
  add("grid/lines-implicit-before", G({ width: 300, gridTemplateColumns: "100px 100px", gridAutoColumns: "30px", justifyContent: "start" }, cell(20, { gridColumn: "-4" }), cell(20), cell(20)));
  add("grid/row-locked", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr", gridAutoRows: "20px" }, cell(20, { gridRow: 2 }), cell(20), cell(20, { gridRow: 1 }), cell(20), cell(20, { gridRow: 2 }), cell(20)));
  add("grid/col-locked", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr", gridAutoRows: "20px" }, cell(20, { gridColumn: 2 }), cell(20), cell(20, { gridColumn: 1 }), cell(20), cell(20, { gridColumn: 3 }), cell(20, { gridColumn: 2 })));
  add("grid/dense", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr", gridAutoRows: "20px", gridAutoFlow: "row dense" }, cell(20, { gridColumn: "span 2" }), cell(20, { gridColumn: "span 2" }), cell(20), cell(20)));
  add("grid/sparse", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr", gridAutoRows: "20px" }, cell(20, { gridColumn: "span 2" }), cell(20, { gridColumn: "span 2" }), cell(20), cell(20)));
  add("grid/span-intrinsic", G({ width: 300, gridTemplateColumns: "auto auto auto", justifyContent: "start" }, box(30, 10), box(30, 10), box(30, 10), F({ gridColumn: "span 2" }, box(100, 10, { flexShrink: 0 })), box(10, 10)));
  add("grid/span-intrinsic-rows", G({ width: 300, gridTemplateColumns: "100px 100px" }, cell(80, { gridRow: "span 2" }), cell(20), cell(20)));
  add("grid/span-fr", G({ width: 300, gridTemplateColumns: "auto 1fr" }, F({ gridColumn: "span 2" }, box(100, 10)), box(30, 10), box(10, 10)));
  for (const v of ["start", "end", "center", "stretch", "space-between", "space-around", "space-evenly"]) {
    add(`grid/justify-content-${v}`, G({ width: 300, height: 200, gridTemplateColumns: "50px 60px", gridTemplateRows: "30px 40px", justifyContent: v, gap: 4 }, ...cells(4)));
    add(`grid/align-content-${v}`, G({ width: 300, height: 200, gridTemplateColumns: "50px 60px", gridTemplateRows: "30px 40px", alignContent: v, gap: 4 }, ...cells(4)));
    add(`grid/content-auto-${v}`, G({ width: 300, height: 200, gridTemplateColumns: "auto auto", justifyContent: v, alignContent: v }, box(20, 20), box(30, 30), box(40, 10)));
  }
  for (const v of ["start", "end", "center", "stretch"]) {
    add(`grid/justify-items-${v}`, G({ width: 300, gridTemplateColumns: "100px 100px", gridAutoRows: "50px", justifyItems: v }, box(20, 20), F({ height: 20 }), F({ width: 30 }), F({})));
    add(`grid/align-items-${v}`, G({ width: 300, gridTemplateColumns: "100px 100px", gridAutoRows: "50px", alignItems: v }, box(20, 20), F({ height: 20 }), F({ width: 30 }), F({})));
    add(`grid/self-${v}`, G({ width: 300, gridTemplateColumns: "100px 100px", gridAutoRows: "50px" }, box(20, 20, { justifySelf: v, alignSelf: v }), F({ justifySelf: v }, box(10, 10)), F({ alignSelf: v }, box(10, 10))));
  }
  add("grid/item-margins", G({ width: 300, gridTemplateColumns: "100px 100px", gridAutoRows: "50px" }, F({ margin: 5 }), box(20, 20, { margin: "auto" }), box(20, 20, { marginLeft: "auto" }), box(20, 20, { marginTop: "auto", marginRight: 10 })));
  add("grid/item-percent", G({ width: 300, gridTemplateColumns: "100px 200px", gridTemplateRows: "50px 80px" }, F({ width: "50%", height: "50%" }), F({ width: "50%", height: "50%" }), F({ padding: "10%" })));
  add("grid/item-min-max", G({ width: 300, gridTemplateColumns: "100px 100px", gridAutoRows: "50px" }, F({ maxWidth: 40, maxHeight: 20 }), F({ minWidth: 150, minHeight: 70 })));
  add("grid/item-aspect", G({ width: 300, gridTemplateColumns: "100px 100px" }, F({ aspectRatio: 2 }), F({ width: 50, aspectRatio: 1 }), F({ height: 30, aspectRatio: 2 })));
  add("grid/content-height", G({ width: 300, gridTemplateColumns: "1fr 1fr" }, words(5), words(9), F({ flexDirection: "column" }, box(20, 30), box(20, 30))));
  add("grid/auto-width-shrink", F({ width: 300, alignItems: "flex-start" }, G({ gridTemplateColumns: "auto auto", gap: 5 }, box(40, 20), box(60, 20), box(10, 10))));
  add("grid/auto-width-fr", F({ width: 300, alignItems: "flex-start" }, G({ gridTemplateColumns: "1fr 1fr", gap: 5 }, box(40, 20), box(60, 20), box(10, 10))));
  add("grid/auto-width-fixed", F({ width: 300, alignItems: "flex-start" }, G({ gridTemplateColumns: "50px 70px", gap: 5 }, cell(10), cell(10))));
  add("grid/in-column-flex", F({ width: 300, flexDirection: "column" }, G({ gridTemplateColumns: "1fr 1fr", gap: 5 }, box(40, 20), box(60, 20), box(10, 10)), box(10, 10)));
  add("grid/in-block", B({ width: 300, padding: 10 }, G({ gridTemplateColumns: "1fr 1fr", gap: 5, marginBottom: 10 }, cell(20), cell(30)), B({ height: 10, marginTop: 20 })));
  add("grid/nested", G({ width: 300, gridTemplateColumns: "1fr 2fr", gap: 6 }, G({ gridTemplateColumns: "1fr 1fr", gap: 2 }, cell(10), cell(20), cell(30)), F({ flexDirection: "column" }, box(30, 30), G({ gridTemplateColumns: "auto 1fr" }, box(20, 20), cell(10)))));
  add("grid/min-height", G({ width: 300, minHeight: 200, gridTemplateColumns: "1fr 1fr" }, cell(20), cell(30), cell(10)));
  add("grid/fixed-height-auto-rows", G({ width: 300, height: 200, gridTemplateColumns: "1fr 1fr" }, cell(20), cell(30), cell(10)));
  add("grid/fixed-height-auto-rows-stretch-items", G({ width: 300, height: 200, gridTemplateColumns: "1fr 1fr" }, F({}), F({}), F({})));
  add("grid/abs", G({ position: "relative", width: 300, height: 200, padding: 10, gridTemplateColumns: "1fr 1fr" }, F({ position: "absolute", top: 5, right: 5, width: 20, height: 20 }), cell(20), F({ position: "absolute", width: 20, height: 20 }), F({ position: "absolute", inset: 0 })));
  add("grid/none", G({ width: 300, gridTemplateColumns: "1fr 1fr" }, cell(20), c({ display: "none" }), cell(30), cell(10)));
  add("grid/repeat", G({ width: 300, gridTemplateColumns: "repeat(3, 1fr)", gap: 3 }, ...cells(5)));
  add("grid/auto-fill", G({ width: 300, gridTemplateColumns: "repeat(auto-fill, 70px)", gap: 5 }, ...cells(6)));
  add("grid/auto-fill-minmax", G({ width: 300, gridTemplateColumns: "repeat(auto-fill, minmax(80px, 1fr))", gap: 5 }, ...cells(5)));
  add("grid/auto-fit-minmax", G({ width: 300, gridTemplateColumns: "repeat(auto-fit, minmax(60px, 1fr))", gap: 5 }, ...cells(2)));
  add("grid/auto-fill-few", G({ width: 300, gridTemplateColumns: "repeat(auto-fill, minmax(60px, 1fr))", gap: 5 }, ...cells(2)));
  add("grid/auto-fill-mixed", G({ width: 300, gridTemplateColumns: "40px repeat(auto-fill, 50px) 30px", gap: 5 }, ...cells(7)));
  add("grid/auto-fit-fixed", G({ width: 300, gridTemplateColumns: "repeat(auto-fit, 70px)", gap: 5, justifyContent: "center" }, ...cells(2)));
  add("grid/root-auto", G({ gridTemplateColumns: "1fr 1fr" }, cell(20), cell(30)));
  add("grid/overflow-item-min", G({ width: 200, gridTemplateColumns: "1fr 1fr" }, F({ overflow: "hidden" }, box(150, 20, { flexShrink: 0 })), cell(10)));
  add("grid/min-width-0", G({ width: 200, gridTemplateColumns: "1fr 1fr" }, F({ minWidth: 0 }, box(150, 20, { flexShrink: 0 })), cell(10)));
  add("grid/minmax-0-fr", G({ width: 200, gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)" }, F({}, box(150, 20, { flexShrink: 0 })), cell(10)));

  // random grids
  const NG = +(process.env.NG || 120);
  const trackList = (n) => Array.from({ length: n }, () => pick("1fr", "2fr", "auto", "50px", "80px", "20%", "min-content", "max-content", "minmax(30px, 1fr)", "minmax(20px, auto)", "fit-content(60px)")).join(" ");
  for (let i = 0; i < NG; i++) {
    const ncol = 1 + Math.floor(rnd() * 4);
    const style = {
      width: pick(240, 300, 333),
      ...maybe(0.4, { height: pick(150, 220) }),
      gridTemplateColumns: trackList(ncol),
      ...maybe(0.4, { gridTemplateRows: trackList(1 + Math.floor(rnd() * 3)) }),
      ...maybe(0.3, { gridAutoRows: pick("30px", "minmax(20px, auto)", "1fr") }),
      ...maybe(0.5, { gap: pick(4, 8, "3px 9px") }),
      ...maybe(0.3, { padding: pick(5, 10) }),
      ...maybe(0.3, { justifyContent: pick("start", "center", "end", "space-between", "space-around") }),
      ...maybe(0.3, { alignContent: pick("start", "center", "end", "space-between") }),
      ...maybe(0.3, { justifyItems: pick("start", "center", "end", "stretch") }),
      ...maybe(0.3, { alignItems: pick("start", "center", "end", "stretch") }),
      ...maybe(0.15, { gridAutoFlow: pick("column", "row dense") }),
    };
    const n = 1 + Math.floor(rnd() * 7);
    const kids = Array.from({ length: n }, () => {
      const st = {
        ...maybe(0.5, { width: pick(20, 45, 70, "50%") }),
        ...maybe(0.6, { height: pick(15, 25, 40) }),
        ...maybe(0.2, { gridColumn: pick("span 2", "1", "2", "1 / 3", "-1", "span 3") }),
        ...maybe(0.15, { gridRow: pick("span 2", "1", "2", "1 / 3") }),
        ...maybe(0.15, { margin: pick(3, "auto", "2px 6px") }),
        ...maybe(0.15, { justifySelf: pick("start", "center", "end", "stretch") }),
        ...maybe(0.15, { alignSelf: pick("start", "center", "end", "stretch") }),
        ...maybe(0.1, { padding: 4 }),
      };
      const k = rnd();
      if (k < 0.15) return words(1 + Math.floor(rnd() * 5), 25, 10, st);
      if (k < 0.3) return F(st, box(pick(20, 60), pick(10, 30), { flexShrink: 0 }));
      return F(st);
    });
    add(`rand/grid-${i}`, G(style, ...kids));
  }
}
