import { existsSync } from "node:fs";
import path from "node:path";
import { ROOT_DIR } from "./assets.mjs";
export const FONT_DIR = path.join(ROOT_DIR, "assets", "fonts");
const f = (name, file, weight, style = "normal") => ({ name, file, path: path.join(FONT_DIR, file), weight, style });
/** Every fixture font, registered identically (explicit family/weight/style) into every engine. */
export const FONTS = [
  f("Inter", "Inter-Regular.ttf", 400),
  f("Inter", "Inter-SemiBold.ttf", 600),
  f("Inter", "Inter-Bold.ttf", 700),
  f("Inter", "Inter-Italic.ttf", 400, "italic"),
  f("Noto Sans", "NotoSans-Regular.ttf", 400),
  f("Noto Sans", "NotoSans-Bold.ttf", 700),
  f("Roboto", "Roboto-Regular.ttf", 400),
  f("Roboto", "Roboto-Bold.ttf", 700),
  f("Roboto", "Roboto-Italic.ttf", 400, "italic"),
];
/** Optional fonts outside the repo (the takumi clone's test fonts under ref/). Only registered when a case
 * names them in `fonts`; cases needing one should check `hasOptionalFont` and skip themselves when it is absent. */
const REF_FONTS = path.join(ROOT_DIR, "ref", "takumi", "assets", "fonts");
export const OPTIONAL_FONTS = [
  { name: "Noto Color Emoji", file: "NotoColorEmoji.ttf", path: path.join(REF_FONTS, "noto-sans", "NotoColorEmoji.ttf"), weight: 400, style: "normal" },
  { name: "Twemoji Mozilla", file: "TwemojiMozilla-colr.woff2", path: path.join(REF_FONTS, "twemoji", "TwemojiMozilla-colr.woff2"), weight: 400, style: "normal" },
].filter((x) => existsSync(x.path));
export const hasOptionalFont = (name) => OPTIONAL_FONTS.some((x) => x.name === name);
/** Restrict to a list of family names (case.fonts); undefined = all (optional fonts only when named). */
export const fontsFor = (families) => (families ? [...FONTS, ...OPTIONAL_FONTS].filter((x) => families.includes(x.name)) : FONTS);
