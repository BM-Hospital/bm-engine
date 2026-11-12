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
for (const f of readdirSync(path.join(SRC, "en"))) if (f.endsWith(".md") && !rewrites[`en/${f}`]) rewrites[`en/${f}`] = f;
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
const sidebarEn: DefaultTheme.SidebarItem[] = [
  { text: "Guide", items: [
    { text: "Overview", link: "/overview" },
    { text: "Getting started", link: "/getting-started" },
    { text: "API reference", link: "/api" },
    { text: "CSS & feature support", link: "/css-support" },
    { text: "Profiles & size", link: "/profiles-and-size" },
    { text: "Differences from takumi", link: "/differences-from-takumi" },
  ] },
  { text: "Benchmark", items: [
    { text: "Benchmark summary", link: "/benchmark" },
    { text: "Per-fixture results", link: "/results-full" },
  ] },
  { text: "Tools", items: [
    { text: "Playground", link: "/playground" },
    { text: "Building from source", link: "/building-from-source" },
    { text: "Troubleshooting", link: "/troubleshooting" },
  ] },
  { text: "Developer", collapsed: true, items: devItems },
];
const sidebarVi: DefaultTheme.SidebarItem[] = [
  { text: "Hướng dẫn", items: [
    { text: "Tổng quan", link: "/vi/overview" },
    { text: "Bắt đầu", link: "/vi/getting-started" },
    { text: "Tham chiếu API", link: "/vi/api" },
    { text: "Hỗ trợ CSS và tính năng", link: "/vi/css-support" },
    { text: "Profile và kích thước", link: "/vi/profiles-and-size" },
    { text: "Khác biệt với takumi", link: "/vi/differences-from-takumi" },
  ] },
  { text: "Benchmark", items: [
    { text: "Benchmark (tóm tắt)", link: "/vi/benchmark" },
    { text: "Benchmark — báo cáo đầy đủ", link: "/vi/benchmark-report" },
    { text: "Kết quả từng fixture", link: "/results-full" },
  ] },
  { text: "Công cụ", items: [
    { text: "Playground", link: "/vi/playground" },
    { text: "Build từ mã nguồn", link: "/vi/building-from-source" },
    { text: "Xử lý sự cố", link: "/vi/troubleshooting" },
  ] },
  { text: "Cho nhà phát triển (tiếng Anh)", collapsed: true, items: devItems },
];

/** Pages whose wide tables need the full width (no outline column). */
const WIDE = new Set(["results-full.md", "vi/benchmark-report.md", "benchmark.md", "vi/benchmark.md", "profiles-and-size.md", "vi/profiles-and-size.md", "css-support.md", "vi/css-support.md"]);

export default defineConfig({
  title: "bm-engine",
  description: "Render JSX-like node trees / HTML + CSS to PNG, JPEG, WebP, SVG and animations with a dependency-free WebAssembly engine (Zig port of takumi).",
  cleanUrls: true,
  lastUpdated: false,
  rewrites,
  srcExclude: ["feature_table_phase*.md", "playground-app/**", "public/**", "**/node_modules/**"],
  // Only links that are legitimately outside the site (local dev servers mentioned in the docs).
  ignoreDeadLinks: [/^https?:\/\/(localhost|127\.0\.0\.1)/],
  head: [
    ["link", { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" }],
    ["meta", { name: "theme-color", content: "#5b4bdb" }],
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
          { text: "Guide", link: "/getting-started", activeMatch: "^/(overview|getting-started|css-support|profiles-and-size|differences-from-takumi|building-from-source|troubleshooting)" },
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
          { text: "Hướng dẫn", link: "/vi/getting-started", activeMatch: "^/vi/(overview|getting-started|css-support|profiles-and-size|differences-from-takumi|building-from-source|troubleshooting)" },
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
