import { readFileSync, readdirSync } from "node:fs";
const dir = process.argv[2]; const f = readdirSync(dir).filter((x) => x.endsWith(".cpuprofile"))[0];
const p = JSON.parse(readFileSync(dir + "/" + f, "utf8"));
const self = new Map(); const byId = new Map(p.nodes.map((n) => [n.id, n]));
const dt = p.timeDeltas; let total = 0;
p.samples.forEach((id, i) => { const n = byId.get(id); const k = n.callFrame.functionName || "(anon)"; self.set(k, (self.get(k) || 0) + dt[i]); total += dt[i]; });
[...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, +(process.argv[3] || 22)).forEach(([k, v]) => console.log((v / total * 100).toFixed(1).padStart(5) + "%", k.slice(0, 110)));
