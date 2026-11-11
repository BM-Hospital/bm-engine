// Shared helpers for layout2 probes: both engines + compact measure-tree formatting.
import tw from "../../engines/takumi-wasm.mjs";
import bm from "../../engines/bm.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
export const T = await tw.create({ fonts: fontsFor() });
export const B = await bm.create({ fonts: fontsFor() });
import { fmt } from "./fmt.mjs";
export { fmt };
export async function both(name, node, opts = { width: 400, height: 200 }, runs = true) {
  console.log("=== " + name);
  try { console.log("takumi:\n" + fmt(await T.measure(node, opts), "", runs)); } catch (e) { console.log("takumi ERR", e.message); }
  try { console.log("bm:\n" + fmt(await B.measure(node, opts), "", runs)); } catch (e) { console.log("bm ERR", e.message); }
}
