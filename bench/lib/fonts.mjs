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
/** Restrict to a list of family names (case.fonts); undefined = all. */
export const fontsFor = (families) => (families ? FONTS.filter((x) => families.includes(x.name)) : FONTS);
