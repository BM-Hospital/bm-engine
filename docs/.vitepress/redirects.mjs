// Old documentation URLs -> their current place. One table for every layer:
//   - docs/.vitepress/theme/index.ts redirects old paths on the client (SPA navigation, and direct hits that the
//     static host answers with 404.html, e.g. `vitepress preview`), keeping the #anchor;
//   - vercel.json has the same moves as permanent server redirects (checked against this table by
//     bench/browser/docs-site-test.mjs).
// Plain JavaScript so that the config, the theme and the Node.js tests can all import it.

/** Pages that exist in one language only. The language switcher links to the "same" path in the other locale;
 *  these send it to the closest real page instead of a 404 (vercel.json has the same redirects for direct hits). */
export const CROSS_LOCALE = {
  "/benchmark-report": "/benchmark",
  "/vi/results-full": "/results-full",
  "/vi/NATIVE": "/NATIVE",
  "/vi/dev/architecture": "/dev/architecture",
  "/vi/dev/takumi-notes": "/dev/takumi-notes",
  "/vi/dev/conventions": "/dev/conventions",
};

/** Image pages that lived at /<page> (and /vi/<page>) before the Image / PDF split. */
export const IMAGE_PAGES = [
  "concepts", "styles", "html-and-tailwind", "fonts", "typography", "images", "tables", "charts", "effects", "formats",
  "animation", "performance", "measure", "templates", "recipes", "css-support", "api", "playground", "differences-from-takumi",
];
/** Sub-folders that moved under /image/ as a whole. */
export const IMAGE_DIRS = ["frameworks", "migration"];
/** PDF pages that lost their `pdf-` prefix. */
export const PDF_PAGES = {
  "pdf": "/pdf/",
  "pdf-pagination": "/pdf/pagination",
  "pdf-headers-footers": "/pdf/headers-footers",
  "pdf-links-metadata": "/pdf/links-metadata",
  "pdf-fonts": "/pdf/fonts",
  "pdf-accessibility": "/pdf/accessibility",
};
/** Sections of the old /getting-started that moved to the Image quick start (/image/). Keys are heading ids. */
export const MOVED_ANCHORS = {
  "/getting-started": {
    to: "/image/",
    en: ["nodejs", "browser-without-a-bundler", "fonts", "woff-on-core", "images", "output-formats", "see-also"],
    vi: ["nodejs", "trình-duyệt-không-dùng-bundler", "font", "woff-trên-core", "ảnh", "định-dạng-đầu-ra", "xem-thêm"],
  },
};

/** Map of old path (no trailing slash, no .html) -> new path, for both locales. */
export const REDIRECTS = (() => {
  const m = {};
  for (const loc of ["", "/vi"]) {
    for (const p of IMAGE_PAGES) m[`${loc}/${p}`] = `${loc}/image/${p}`;
    for (const [o, n] of Object.entries(PDF_PAGES)) if (o !== "pdf") m[`${loc}/${o}`] = loc + n;
    // product index without the trailing slash (a folder route in VitePress)
    m[`${loc}/pdf`] = `${loc}/pdf/`;
    m[`${loc}/image`] = `${loc}/image/`;
  }
  return m;
})();

/** New path for an old one, or null. Handles the moved folders (/frameworks/x, /vi/migration/x, ...). */
export function redirectFor(pathname) {
  const t = redirectTarget(pathname);
  return t && t !== pathname.replace(/\.html$/, "") ? t : null; // "/pdf/" is current: no redirect to itself
}
function redirectTarget(pathname) {
  let p = pathname.replace(/\.html$/, "");
  if (p.length > 1 && p.endsWith("/") && !/^(\/vi)?\/(frameworks|migration)\/$/.test(p)) p = p.slice(0, -1);
  if (REDIRECTS[p]) return REDIRECTS[p];
  const d = /^(\/vi)?\/(frameworks|migration)(\/.*)?$/.exec(p);
  if (d && IMAGE_DIRS.includes(d[2])) return `${d[1] ?? ""}/image/${d[2]}${d[3] ?? "/"}`;
  return null;
}

/** For a hash on a page whose section moved to another page: the new location, or null. */
export function movedAnchor(pathname, hash) {
  const vi = pathname.startsWith("/vi/");
  const base = pathname.replace(/^\/vi/, "").replace(/\.html$/, "");
  const e = MOVED_ANCHORS[base];
  if (!e || !hash) return null;
  const id = decodeURIComponent(hash.slice(1));
  return (vi ? e.vi : e.en).includes(id) ? (vi ? "/vi" : "") + e.to + hash : null;
}
