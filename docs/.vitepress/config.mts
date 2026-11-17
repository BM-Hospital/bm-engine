// VitePress site for bm-render. Sources stay GitHub-friendly (README.md per language folder, relative links);
// this config maps them onto clean routes:
//   docs/index.md, docs/vi/index.md        -> /, /vi/                    (home pages, hero)
//   docs/en/README.md, docs/vi/README.md   -> /overview, /vi/overview    (doc index)
//   docs/en/<page>.md                      -> /<page>            (shared, product-neutral pages)
//   docs/en/image/<page>.md, pdf/<page>.md -> /image/<page>, /pdf/<page>   (the two products, each with its own sidebar)
//   docs/vi/<path>.md                      -> /vi/<path>
// Old URLs (before the Image / PDF split) are redirected: see redirects.mjs.
//   docs/BENCHMARK.md (Vietnamese report)  -> /vi/benchmark-report
//   docs/RESULTS_FULL.md                   -> /results-full
//   docs/ARCHITECTURE.md, TAKUMI_NOTES.md, CONVENTIONS.md -> /dev/architecture, /dev/takumi-notes, /dev/conventions
// Relative Markdown links are rewritten at build time (see `siteLinks` below) so the same files work on GitHub and here.
import { defineConfig, type DefaultTheme } from "vitepress";
import { readdirSync, existsSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SRC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const REPO = "https://github.com/BM-Hospital/bm-render";
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
  if ((src.endsWith(".md") && !src.includes("/") && src !== "index.md") || src.includes("feature_table_phase") || src.startsWith("playground-app/") || src.startsWith("public/")) return null;
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
    // The hand-written table of contents under the intro (a list of #anchor links before the first h2) is for GitHub;
    // on the site the "On this page" outline shows the same, so it is dropped where the outline is shown.
    if (!WIDE.has(rel) && state.env?.frontmatter?.aside !== false) {
      const firstH2 = toks.findIndex((t: any) => t.type === "heading_open" && t.tag === "h2");
      const start = toks.findIndex((t: any, i: number) => t.type === "bullet_list_open" && t.level === 0 && (firstH2 < 0 || i < firstH2));
      if (start >= 0) {
        const end = toks.findIndex((t: any, i: number) => i > start && t.type === "bullet_list_close" && t.level === 0);
        const inlines = toks.slice(start, end).filter((t: any) => t.type === "inline");
        const onlyAnchors = inlines.length >= 3 && inlines.every((t: any) => {
          const kids = (t.children ?? []).filter((c: any) => !(c.type === "text" && !c.content.trim()));
          return kids[0]?.type === "link_open" && /^#/.test(kids[0].attrGet("href") ?? "") && kids[kids.length - 1]?.type === "link_close";
        });
        if (end > start && onlyAnchors) toks.splice(start, end - start + 1);
      }
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
      // other files and folders under docs/ that are not pages (docs/examples/...): link to them on GitHub
      const abs = path.join(SRC, target);
      if (!target.startsWith("public/") && existsSync(abs)) return (statSync(abs).isDirectory() ? TREE : BLOB) + "docs/" + target.replace(/\/$/, "") + m[2];
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
// Two products, each with its own sidebar (Image: /image/..., PDF: /pdf/...), plus product-neutral pages at the top
// level (/getting-started, /benchmark, /dev/..., ...) that appear in BOTH sidebars under "Package". A shared page has
// one URL; which product sidebar it shows follows the product the reader chose last (theme/product.ts).
const devItems = [
  { text: "Architecture", link: "/dev/architecture" },
  { text: "Engineering conventions", link: "/dev/conventions" },
];
// [slug, English title, Vietnamese title]; a group is [English title, Vietnamese title, pages, collapsed?].
// Slugs are relative to the locale root ("image/fonts" -> /image/fonts, /vi/image/fonts); "vi:x" is a page that
// exists in Vietnamese only, "/x" a page that exists in one (English) version for both locales.
type P = [string, string, string];
type G = [string, string, P[], boolean?];
const PACKAGE: G = ["Package (shared)", "Gói (dùng chung)", [
  ["overview", "Overview", "Tổng quan"],
  ["getting-started", "Install & entry points", "Cài đặt và điểm vào"],
  ["native-vs-wasm", "Native vs WebAssembly", "Native và WebAssembly"],
  ["profiles-and-size", "Profiles & size", "Profile và kích thước"],
  ["outputs-compared", "Choose an output", "Chọn đầu ra"],
  ["benchmark", "Benchmark", "Benchmark"],
  ["troubleshooting", "Troubleshooting", "Xử lý sự cố"],
  ["building-from-source", "Building from source", "Build từ mã nguồn"],
  ["publishing", "Publishing (maintainers)", "Phát hành (maintainer)"],
]];
const IMAGE_GROUPS: G[] = [
  ["Get started", "Bắt đầu", [
    ["image/", "Image quick start", "Bắt đầu nhanh"],
    ["image/concepts", "Concepts", "Khái niệm"],
    ["image/playground", "Playground", "Playground"],
  ]],
  ["Content", "Nội dung", [
    ["image/styles", "Styles & layout", "Style và layout"],
    ["image/html-and-tailwind", "HTML & Tailwind", "HTML và Tailwind"],
    ["image/fonts", "Fonts", "Font"],
    ["image/typography", "Typography", "Typography"],
    ["image/images", "Images", "Hình ảnh"],
    ["image/tables", "Tables & floats", "Bảng và float"],
    ["image/charts", "Charts", "Biểu đồ"],
    ["image/effects", "Effects", "Hiệu ứng"],
  ]],
  ["Rendering", "Render", [
    ["image/formats", "Output formats", "Định dạng đầu ra"],
    ["image/animation", "Animation", "Hoạt ảnh"],
    ["image/performance", "Performance", "Hiệu năng"],
  ]],
  ["Frameworks", "Framework", [
    ["image/frameworks/", "Overview", "Tổng quan"],
    ["image/frameworks/nextjs", "Next.js", "Next.js"],
    ["image/frameworks/nuxt-nitro", "Nuxt & Nitro", "Nuxt và Nitro"],
    ["image/frameworks/sveltekit", "SvelteKit", "SvelteKit"],
    ["image/frameworks/astro", "Astro", "Astro"],
    ["image/frameworks/tanstack-start", "TanStack Start", "TanStack Start"],
    ["image/frameworks/hono-express", "Hono, Express, node:http", "Hono, Express, node:http"],
    ["image/frameworks/cloudflare-workers", "Cloudflare Workers", "Cloudflare Workers"],
    ["image/frameworks/deno-bun", "Deno & Bun", "Deno và Bun"],
    ["image/frameworks/vite-browser", "Vite & browsers", "Vite và trình duyệt"],
  ], true],
  ["Reference", "Tham chiếu", [
    ["image/api", "API reference", "Tham chiếu API"],
    ["image/measure", "measure()", "measure()"],
    ["image/css-support", "CSS & feature support", "Hỗ trợ CSS và tính năng"],
    ["image/recipes", "Recipes", "Công thức"],
    ["image/templates", "Templates", "Mẫu dựng sẵn"],
  ]],
  ["Migration", "Chuyển đổi", [
    ["image/migration/checklist", "Integration checklist", "Checklist tích hợp"],
    ["image/migration/from-satori", "From Satori", "Từ Satori"],
    ["image/limitations", "Known limitations", "Hạn chế đã biết"],
  ]],
];
const PDF_GROUPS: G[] = [
  ["Get started", "Bắt đầu", [
    ["pdf/", "PDF quick start", "Bắt đầu nhanh"],
    ["pdf/page-size-and-viewport", "Page size, margins, viewport", "Khổ giấy, lề, viewport"],
    ["pdf/native-and-wasm", "Native & WebAssembly", "Native và WebAssembly"],
    ["pdf/playground", "Playground", "Playground"],
  ]],
  ["Guides", "Hướng dẫn", [
    ["pdf/pagination", "Pagination", "Phân trang"],
    ["pdf/headers-footers", "Headers, footers, counters", "Header, footer, bộ đếm trang"],
    ["pdf/links-metadata", "Links, metadata, attachments", "Liên kết, metadata, tệp đính kèm"],
    ["pdf/fonts", "Fonts in PDF", "Font trong PDF"],
    ["pdf/accessibility", "Accessibility, PDF/UA, PDF/A", "Truy cập, PDF/UA, PDF/A"],
  ]],
  ["Use cases", "Ứng dụng", [
    ["pdf/recipes", "Recipes: invoice, report, ticket", "Công thức: hoá đơn, báo cáo, vé"],
    ["pdf/frameworks", "Serving PDFs from a framework", "Trả PDF từ framework"],
  ]],
  ["Reference", "Tham chiếu", [
    ["pdf/api", "PDF API reference", "Tham chiếu API PDF"],
    ["pdf/css-support", "CSS in PDF", "CSS trong PDF"],
    ["pdf/limitations", "Known limitations", "Hạn chế đã biết"],
  ]],
];
/** Source file (under docs/en or docs/vi) of a sidebar slug. */
const fileOf = (slug: string) => slug === "overview" ? "README.md" : slug.endsWith("/") ? slug + "index.md" : slug + ".md";
/** Pages that do not exist (yet) are left out, so the sidebar never links to a 404. */
function sidebar(groups: G[], vi: boolean): DefaultTheme.SidebarItem[] {
  const out: DefaultTheme.SidebarItem[] = [];
  for (const [en, viT, pages, collapsed] of [...groups, PACKAGE]) {
    const items: DefaultTheme.SidebarItem[] = [];
    for (const [slug, tEn, tVi] of pages) {
      if (slug.startsWith("/")) { items.push({ text: vi ? tVi : tEn, link: slug }); continue; }
      if (slug.startsWith("vi:")) { if (vi) items.push({ text: tVi, link: "/vi/" + slug.slice(3) }); continue; }
      if (!existsSync(path.join(SRC, vi ? "vi" : "en", fileOf(slug)))) continue;
      items.push({ text: vi ? tVi : tEn, link: (vi ? "/vi/" : "/") + slug });
    }
    if (items.length) out.push({ text: vi ? viT : en, items, ...(collapsed ? { collapsed: false } : {}) });
  }

  return out;
}
/** Multi-sidebar of one locale. Shared pages (everything outside /image/ and /pdf/) get the Image sidebar on the
 *  server; on the client they switch to the remembered product's sidebar (theme/product.ts). */
function sidebars(vi: boolean): DefaultTheme.SidebarMulti {
  const p = vi ? "/vi/" : "/";
  const image = sidebar(IMAGE_GROUPS, vi), pdf = sidebar(PDF_GROUPS, vi);
  return { [p + "image/"]: image, [p + "pdf/"]: pdf, [p]: image };
}

/** Pages whose wide tables need the full width (no outline column). */
const WIDE = new Set(["results-full.md", "vi/benchmark-report.md", "benchmark.md", "vi/benchmark.md", "profiles-and-size.md",
  "vi/profiles-and-size.md", "image/css-support.md", "vi/image/css-support.md", "native-vs-wasm.md", "vi/native-vs-wasm.md"]);

/** Product a page belongs to, from its (rewritten) relative path; null for shared pages. */
const productOf = (rel: string): "image" | "pdf" | null => {
  const m = /^(?:vi\/|en\/)?(image|pdf)\//.exec(rel); // en/... when given the source path (search index)
  return m ? (m[1] as "image" | "pdf") : null;
};

export default defineConfig({
  title: "bm-render",
  description: "Render JSX-like node trees / HTML + CSS to PNG, JPEG, WebP, SVG and animations with a dependency-free WebAssembly engine.",
  cleanUrls: true,
  lastUpdated: false,
  rewrites,
  srcExclude: [...readdirSync(SRC).filter((f) => f.endsWith(".md") && f !== "index.md"), "feature_table_phase*.md", "playground-app/**", "public/**", "examples/**", "**/node_modules/**"],
  // Only links that are legitimately outside the site (local dev servers mentioned in the docs).
  ignoreDeadLinks: [/^https?:\/\/(localhost|127\.0\.0\.1)/],
  head: [
    ["link", { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" }],
    ["meta", { name: "theme-color", content: "#0f766e" }],
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
      // Results name the product of a page ("PDF › Fonts in PDF"): the h1 of product pages gets a prefix in the index.
      _render(src: string, env: any, md: any) {
        const html = md.render(src, env);
        if (env.frontmatter?.search === false) return "";
        const p = productOf(env.relativePath ?? "");
        return p ? html.replace(/(<h1[^>]*>)/, `$1${p === "pdf" ? "PDF" : "Image"} › `) : html;
      },
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
          { text: "Image", link: "/image/", activeMatch: "^/image/(?!playground)" },
          { text: "PDF", link: "/pdf/", activeMatch: "^/pdf/(?!playground)" },
          { text: "Install", link: "/getting-started", activeMatch: "^/(getting-started|overview|native-vs-wasm|profiles-and-size|outputs-compared|troubleshooting|building-from-source|publishing)" },
          { text: "Benchmark", link: "/benchmark", activeMatch: "^/(benchmark|results-full)" },
          // points at /pdf/playground while the reader is in the PDF product (theme/product.ts)
          { text: "Playground", link: "/image/playground", activeMatch: "^/(image|pdf)/playground" },
        ],
        sidebar: sidebars(false),
        products: {
          label: "Choose a product",
          image: { title: "Image", description: "PNG, JPEG, WebP, SVG, animations" },
          pdf: { title: "PDF", description: "Paged documents" },
        },
        outline: { level: [2, 3], label: "On this page" },
        footer: { message: "Released under the MIT License.", copyright: "bm-render · Zig, native and WebAssembly." },
      },
    },
    vi: {
      label: "Tiếng Việt",
      lang: "vi",
      link: "/vi/",
      title: "bm-render",
      description: "Render cây node kiểu JSX / HTML + CSS thành PNG, JPEG, WebP, SVG và ảnh động bằng một engine WebAssembly không phụ thuộc.",
      themeConfig: {
        nav: [
          { text: "Ảnh", link: "/vi/image/", activeMatch: "^/vi/image/(?!playground)" },
          { text: "PDF", link: "/vi/pdf/", activeMatch: "^/vi/pdf/(?!playground)" },
          { text: "Cài đặt", link: "/vi/getting-started", activeMatch: "^/vi/(getting-started|overview|native-vs-wasm|profiles-and-size|outputs-compared|troubleshooting|building-from-source|publishing)" },
          { text: "Benchmark", link: "/vi/benchmark", activeMatch: "^/vi/benchmark" },
          { text: "Playground", link: "/vi/image/playground", activeMatch: "^/vi/(image|pdf)/playground" },
        ],
        sidebar: sidebars(true),
        products: {
          label: "Chọn sản phẩm",
          image: { title: "Ảnh", description: "PNG, JPEG, WebP, SVG, ảnh động" },
          pdf: { title: "PDF", description: "Tài liệu phân trang" },
        },
        outline: { level: [2, 3], label: "Trên trang này" },
        docFooter: { prev: "Trang trước", next: "Trang sau" },
        darkModeSwitchLabel: "Giao diện",
        lightModeSwitchTitle: "Chuyển sang giao diện sáng",
        darkModeSwitchTitle: "Chuyển sang giao diện tối",
        sidebarMenuLabel: "Mục lục",
        returnToTopLabel: "Lên đầu trang",
        langMenuLabel: "Đổi ngôn ngữ",
        notFound: { title: "KHÔNG TÌM THẤY TRANG", quote: "Trang này không tồn tại hoặc đã được chuyển đi.", linkText: "Về trang chủ", linkLabel: "về trang chủ" },
        footer: { message: "Phát hành theo giấy phép MIT.", copyright: "bm-render · Zig, native và WebAssembly." },
      },
    },
  },
});
