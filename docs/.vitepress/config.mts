// VitePress site for bm-engine. Sources stay GitHub-friendly (README.md per language folder, relative links);
// this config maps them onto clean routes:
//   docs/index.md, docs/vi/index.md        -> /, /vi/                    (home pages, hero)
//   docs/en/README.md, docs/vi/README.md   -> /overview, /vi/overview    (doc index)
//   docs/en/<page>.md                      -> /<page>
//   docs/vi/<page>.md                      -> /vi/<page>
//   docs/BENCHMARK.md (Vietnamese report)  -> /vi/benchmark-report
//   docs/RESULTS_FULL.md                   -> /results-full
//   docs/ARCHITECTURE.md, TAKUMI_NOTES.md, CONVENTIONS.md -> /dev/architecture, /dev/takumi-notes, /dev/conventions
// Relative Markdown links are rewritten at build time (see `siteLinks` below) so the same files work on GitHub and here.
import { defineConfig, type DefaultTheme } from "vitepress";
import { readdirSync, existsSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SRC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const REPO = "https://github.com/OWNER/bm-engine"; // same OWNER placeholder as package.json
const BLOB = `${REPO}/blob/main/`;
const TREE = `${REPO}/tree/main/`;

// ---------------------------------------------------------------------------------------------- routes
const SPECIAL: Record<string, string> = {
  "en/README.md": "overview.md",
  "vi/README.md": "vi/overview.md",
  "BENCHMARK.md": "vi/benchmark-report.md",
  "RESULTS_FULL.md": "results-full.md",
  "ARCHITECTURE.md": "dev/architecture.md",
  "TAKUMI_NOTES.md": "dev/takumi-notes.md",
  "CONVENTIONS.md": "dev/conventions.md",
};
const rewrites: Record<string, string> = { ...SPECIAL };
const walkEn = (dir: string): void => {
  for (const f of readdirSync(path.join(SRC, "en", dir))) {
    const rel = dir ? dir + "/" + f : f;
    if (statSync(path.join(SRC, "en", rel)).isDirectory()) walkEn(rel);
    else if (f.endsWith(".md") && !rewrites["en/" + rel]) rewrites["en/" + rel] = rel;
  }
};
walkEn("");
const inverse = Object.fromEntries(Object.entries(rewrites).map(([k, v]) => [v, k]));
/** Files under docs/ copied to docs/public/data/ by prepare.mjs (downloadable from the site). */
const DATA_FILES = new Set(["results.json", "PACKAGE_FACTS.json"]);

/** docs-relative source path of a page -> site route ("/x", "/vi/", ...), or null when it is not a page. */
function routeOf(src: string): string | null {
  if (src.includes("feature_table_phase") || src.startsWith("playground-app/") || src.startsWith("public/")) return null;
  const out = rewrites[src] ?? src;
  if (!existsSync(path.join(SRC, src))) return null;
  return "/" + out.replace(/(^|\/)index\.md$/, "$1").replace(/\.md$/, "");
}

/** markdown-it plugin: resolve relative links against the ORIGINAL source file and emit absolute site routes,
 *  GitHub URLs for files outside the site, /data/ URLs for the downloadable JSON files. */
function siteLinks(md: any) {
  md.core.ruler.push("bm-site-links", (state: any) => {
    const rel: string = state.env?.relativePath;
    if (!rel) return;
    const orig = inverse[rel] ?? rel;
    // The "[English](..) · [Tiếng Việt](..)" line under each title is for GitHub; the site has a language menu.
    const toks = state.tokens;
    for (let i = 0; i + 2 < toks.length; i++) {
      if (toks[i].type === "paragraph_open" && toks[i + 1].type === "inline" &&
          /^\[English\]\([^)]*\) · \[Tiếng Việt\]\([^)]*\)$/.test(toks[i + 1].content.trim())) { toks.splice(i, 3); break; }
    }
    const dir = path.posix.dirname(orig);
    const fix = (href: string): string => {
      if (!href || /^(#|[a-z][a-z0-9+.-]*:|\/)/i.test(href)) return href;
      const m = /^([^#?]*)(.*)$/.exec(href)!;
      const target = path.posix.normalize(path.posix.join(dir, decodeURI(m[1])));
      if (target.startsWith("../")) {
        const repoPath = target.slice(3);
        const abs = path.join(SRC, "..", repoPath);
        const isDir = existsSync(abs) && statSync(abs).isDirectory();
        return (isDir ? TREE : BLOB) + repoPath.replace(/\/$/, "") + m[2];
      }
      if (target.endsWith(".md")) {
        const r = routeOf(target);
        return r ? r + m[2] : BLOB + "docs/" + target + m[2];
      }
      if (DATA_FILES.has(target)) return "/data/" + target + m[2];
      return href;
    };
    const walk = (tokens: any[]) => {
      for (const t of tokens) {
        if (t.type === "link_open") t.attrSet("href", fix(t.attrGet("href")));
        if (t.children) walk(t.children);
      }
    };
    walk(state.tokens);
  });
}

/** GitHub-compatible heading ids (github-slugger), so anchors written for GitHub keep working on the site. */
const githubSlug = (s: string) => s.trim().toLowerCase().replace(/[^\p{L}\p{M}\p{N}\p{Pc}\- ]/gu, "").replace(/ /g, "-");

// ---------------------------------------------------------------------------------------------- navigation
const devItems = [
  { text: "Architecture", link: "/dev/architecture" },
  { text: "takumi semantics notes", link: "/dev/takumi-notes" },
  { text: "Engineering conventions", link: "/dev/conventions" },
];
// [slug, English title, Vietnamese title]; a group is [English title, Vietnamese title, pages, collapsed?].
type P = [string, string, string];
const GROUPS: [string, string, P[], boolean?][] = [
  ["Get started", "Bắt đầu", [
    ["overview", "Overview", "Tổng quan"],
    ["getting-started", "Getting started", "Bắt đầu nhanh"],
    ["concepts", "Concepts", "Khái niệm"],
    ["playground", "Playground", "Playground"],
  ]],
  ["Content", "Nội dung", [
    ["styles", "Styles & layout", "Style và layout"],
    ["html-and-tailwind", "HTML & Tailwind", "HTML và Tailwind"],
    ["fonts", "Fonts", "Font"],
    ["typography", "Typography", "Typography"],
    ["images", "Images", "Hình ảnh"],
    ["tables", "Tables & floats", "Bảng và float"],
    ["charts", "Charts", "Biểu đồ"],
    ["effects", "Effects", "Hiệu ứng"],
  ]],
  ["Rendering", "Render", [
    ["formats", "Output formats", "Định dạng đầu ra"],
    ["animation", "Animation", "Hoạt ảnh"],
    ["performance", "Performance", "Hiệu năng"],
    ["profiles-and-size", "Profiles & size", "Profile và kích thước"],
    ["native-vs-wasm", "Native vs WebAssembly", "Native và WebAssembly"],
    ["outputs-compared", "Image, PDF & Paint", "Image, PDF và Paint"],
  ]],
  ["PDF", "PDF", [
    ["pdf", "PDF output", "Đầu ra PDF"],
    ["pdf-pagination", "Pagination", "Phân trang"],
    ["pdf-headers-footers", "Headers, footers, counters", "Header, footer, bộ đếm trang"],
    ["pdf-links-metadata", "Links, bookmarks, metadata", "Liên kết, bookmark, metadata"],
    ["pdf-fonts", "Fonts in PDF", "Font trong PDF"],
    ["pdf-accessibility", "Accessibility & archival", "Khả năng truy cập và lưu trữ"],
  ]],
  ["Frameworks", "Framework", [
    ["frameworks/", "Overview", "Tổng quan"],
    ["frameworks/nextjs", "Next.js", "Next.js"],
    ["frameworks/nuxt-nitro", "Nuxt & Nitro", "Nuxt và Nitro"],
    ["frameworks/nuxt", "Nuxt", "Nuxt"],
    ["frameworks/nitro", "Nitro / h3", "Nitro / h3"],
    ["frameworks/sveltekit", "SvelteKit", "SvelteKit"],
    ["frameworks/astro", "Astro", "Astro"],
    ["frameworks/tanstack-start", "TanStack Start", "TanStack Start"],
    ["frameworks/hono-express", "Hono, Express, node:http", "Hono, Express, node:http"],
    ["frameworks/cloudflare-workers", "Cloudflare Workers", "Cloudflare Workers"],
    ["frameworks/deno-bun", "Deno & Bun", "Deno và Bun"],
    ["frameworks/vite-browser", "Vite & browsers", "Vite và trình duyệt"],
  ], true],
  ["Reference", "Tham chiếu", [
    ["api", "API reference", "Tham chiếu API"],
    ["measure", "measure()", "measure()"],
    ["css-support", "CSS & feature support", "Hỗ trợ CSS và tính năng"],
    ["recipes", "Recipes", "Công thức"],
    ["templates", "Templates", "Mẫu dựng sẵn"],
  ]],
  ["Migration", "Chuyển đổi", [
    ["migration/from-takumi", "From takumi", "Từ takumi"],
    ["migration/from-satori", "From Satori", "Từ Satori"],
    ["differences-from-takumi", "Differences from takumi", "Khác biệt với takumi"],
  ]],
  ["Benchmark", "Benchmark", [
    ["benchmark", "Benchmark summary", "Benchmark (tóm tắt)"],
    ["vi:benchmark-report", "", "Benchmark — báo cáo đầy đủ"],
    ["/results-full", "Per-fixture results", "Kết quả từng fixture"],
  ]],
  ["Help", "Trợ giúp", [
    ["troubleshooting", "Troubleshooting", "Xử lý sự cố"],
    ["building-from-source", "Building from source", "Build từ mã nguồn"],
    ["publishing", "Publishing (maintainers)", "Phát hành (maintainer)"],
  ]],
];
/** Pages that do not exist (yet) are left out, so the sidebar never links to a 404. */
function sidebar(vi: boolean): DefaultTheme.SidebarItem[] {
  const out: DefaultTheme.SidebarItem[] = [];
  for (const [en, viT, pages, collapsed] of GROUPS) {
    const items: DefaultTheme.SidebarItem[] = [];
    for (const [slug, tEn, tVi] of pages) {
      if (slug.startsWith("/")) { items.push({ text: vi ? tVi : tEn, link: slug }); continue; }
      if (slug.startsWith("vi:")) { if (vi) items.push({ text: tVi, link: "/vi/" + slug.slice(3) }); continue; }
      const file = slug === "overview" ? "README.md" : slug.endsWith("/") ? slug + "index.md" : slug + ".md";
      if (!existsSync(path.join(SRC, vi ? "vi" : "en", file))) continue;
      items.push({ text: vi ? tVi : tEn, link: (vi ? "/vi/" : "/") + slug });
    }
    if (items.length) out.push({ text: vi ? viT : en, items, ...(collapsed ? { collapsed: false } : {}) });
  }
  out.push({ text: vi ? "Cho nhà phát triển (tiếng Anh)" : "Developer", collapsed: true, items: devItems });
  return out;
}
const sidebarEn = sidebar(false);
const sidebarVi = sidebar(true);

/** Pages whose wide tables need the full width (no outline column). */
const WIDE = new Set(["results-full.md", "vi/benchmark-report.md", "benchmark.md", "vi/benchmark.md", "profiles-and-size.md", "vi/profiles-and-size.md", "css-support.md", "vi/css-support.md", "native-vs-wasm.md", "vi/native-vs-wasm.md"]);

export default defineConfig({
  title: "bm-engine",
  description: "Render JSX-like node trees / HTML + CSS to PNG, JPEG, WebP, SVG and animations with a dependency-free WebAssembly engine (Zig port of takumi).",
  cleanUrls: true,
  lastUpdated: false,
  rewrites,
  srcExclude: ["feature_table_phase*.md", "playground-app/**", "public/**", "examples/**", "**/node_modules/**"],
  // Only links that are legitimately outside the site (local dev servers mentioned in the docs).
  ignoreDeadLinks: [/^https?:\/\/(localhost|127\.0\.0\.1)/],
  head: [
    ["link", { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" }],
    ["meta", { name: "theme-color", content: "#008046" }],
  ],
  markdown: {
    anchor: { slugify: githubSlug },
    config: (md) => { md.use(siteLinks); },
  },
  transformPageData(page) {
    if (WIDE.has(page.relativePath)) {
      page.frontmatter.aside ??= false;
      page.frontmatter.pageClass ??= "wide-page";
    }
  },
  themeConfig: {
    logo: "/favicon.svg",
    socialLinks: [{ icon: "github", link: REPO }],
    search: { provider: "local", options: {
      locales: { vi: { translations: {
        button: { buttonText: "Tìm kiếm", buttonAriaLabel: "Tìm kiếm" },
        modal: { noResultsText: "Không có kết quả cho", resetButtonTitle: "Xoá", footer: { selectText: "chọn", navigateText: "di chuyển", closeText: "đóng" } },
      } } },
    } },
    outline: { level: [2, 3] },
  },
  locales: {
    root: {
      label: "English",
      lang: "en",
      themeConfig: {
        nav: [
          { text: "Guide", link: "/getting-started", activeMatch: "^/(?!api$|benchmark|results-full|playground|frameworks|dev/)[a-z]" },
          { text: "Frameworks", link: "/frameworks/", activeMatch: "^/frameworks/" },
          { text: "API", link: "/api" },
          { text: "Benchmark", link: "/benchmark", activeMatch: "^/(benchmark|results-full)" },
          { text: "Playground", link: "/playground" },
        ],
        sidebar: { "/": sidebarEn },
        outline: { level: [2, 3], label: "On this page" },
        footer: { message: "Released under the MIT or Apache-2.0 license.", copyright: "bm-engine is a Zig port of takumi." },
      },
    },
    vi: {
      label: "Tiếng Việt",
      lang: "vi",
      link: "/vi/",
      title: "bm-engine",
      description: "Render cây node kiểu JSX / HTML + CSS thành PNG, JPEG, WebP, SVG và ảnh động bằng một engine WebAssembly không phụ thuộc (bản port takumi sang Zig).",
      themeConfig: {
        nav: [
          { text: "Hướng dẫn", link: "/vi/getting-started", activeMatch: "^/vi/(?!api$|benchmark|results-full|playground|frameworks|dev/)[a-z]" },
          { text: "Framework", link: "/vi/frameworks/", activeMatch: "^/vi/frameworks/" },
          { text: "API", link: "/vi/api" },
          { text: "Benchmark", link: "/vi/benchmark", activeMatch: "^/vi/benchmark" },
          { text: "Playground", link: "/vi/playground" },
        ],
        sidebar: { "/vi/": sidebarVi },
        outline: { level: [2, 3], label: "Trên trang này" },
        docFooter: { prev: "Trang trước", next: "Trang sau" },
        darkModeSwitchLabel: "Giao diện",
        lightModeSwitchTitle: "Chuyển sang giao diện sáng",
        darkModeSwitchTitle: "Chuyển sang giao diện tối",
        sidebarMenuLabel: "Mục lục",
        returnToTopLabel: "Lên đầu trang",
        langMenuLabel: "Đổi ngôn ngữ",
        notFound: { title: "KHÔNG TÌM THẤY TRANG", quote: "Trang này không tồn tại hoặc đã được chuyển đi.", linkText: "Về trang chủ", linkLabel: "về trang chủ" },
        footer: { message: "Phát hành theo giấy phép MIT hoặc Apache-2.0.", copyright: "bm-engine là bản port takumi sang Zig." },
      },
    },
  },
});
