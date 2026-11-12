import colors from "./colors.mjs";
import flex from "./flex.mjs";
import sizing from "./sizing.mjs";
import absolute from "./absolute.mjs";
import borders from "./borders.mjs";
import radius from "./radius.mjs";
import gradients from "./gradients.mjs";
import radial from "./radial.mjs";
import shadow from "./shadow.mjs";
import opacity from "./opacity.mjs";
import overflow from "./overflow.mjs";
import transform from "./transform.mjs";
import text from "./text.mjs";
import images from "./images.mjs";
import grid from "./grid.mjs";
import cards from "./cards.mjs";
import stress from "./stress.mjs";
import gaps from "./gaps.mjs";
import paintfx from "./paintfx.mjs";
import frontend from "./frontend.mjs";
import anim from "./anim.mjs";
import layout2 from "./layout2.mjs";
import layout3 from "./layout3.mjs";

/** All cases: { id, feature, title, width, height, node (object, or HTML string), images?, fonts?, notes?, opts? (extra render options, e.g. css) } */
export const ALL_CASES = [colors, flex, sizing, absolute, borders, radius, gradients, radial, shadow, opacity, overflow, transform, text, images, grid, cards, stress, gaps, paintfx, frontend, anim, layout2, layout3].flat();
// fix-layout fixtures (one contiguous block; ids are prefixed fix-layout-)
import fixLayout from "./fix-layout.mjs";
ALL_CASES.push(...fixLayout);
// end of the fix-layout block
const ids = new Set();
for (const k of ALL_CASES) { if (ids.has(k.id)) throw new Error("duplicate fixture id " + k.id); ids.add(k.id); }

export function selectCases(filter) {
  if (!filter) return ALL_CASES;
  const re = new RegExp(filter, "i");
  return ALL_CASES.filter((k) => re.test(k.id) || re.test(k.feature));
}
/** Cases used for jpeg/webp encoding benchmarks: flat UI card, gradient-heavy, photo. */
export const FORMAT_CASES = ["card-flat-ui", "lingrad-angles", "img-photo-bg"];
export default ALL_CASES;
