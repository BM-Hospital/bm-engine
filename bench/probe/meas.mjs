import { ALL_CASES } from "../fixtures/index.mjs";
import bm from "../engines/bm.mjs";
import { fontsFor } from "../lib/fonts.mjs";
const B = await bm.create({ fonts: fontsFor() });
const c = ALL_CASES.find((k) => k.id === process.argv[2]);
const m = await B.measure(c.node, { width: c.width, height: c.height, images: c.images });
const walk = (x, p, d) => { if (d <= +(process.argv[3] || 3)) console.log(p.padEnd(10), x.transform[4], x.transform[5], x.width, x.height); x.children.forEach((k, i) => walk(k, p + "/" + i, d + 1)); };
walk(m, "", 0);
