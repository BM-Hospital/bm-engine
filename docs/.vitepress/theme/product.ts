// Which product (Image or PDF) the reader is in.
//   - On a product page (/image/..., /pdf/..., /vi/image/..., /vi/pdf/...) the product comes from the URL.
//   - On a shared page (/getting-started, /benchmark, /dev/..., ...) it is the product chosen last, remembered in
//     localStorage (default Image). The server always renders shared pages with the Image sidebar; the client
//     applies the remembered product after mounting (see useRememberedProduct), so hydration matches the HTML.
import { computed, ref, type App, type ComputedRef } from "vue";
import { dataSymbol, type Router } from "vitepress";

export type Product = "image" | "pdf";
export const PRODUCTS: Product[] = ["image", "pdf"];
const KEY = "bm-docs-product";

/** Product of a page from its relative path ("image/fonts.md", "vi/pdf/index.md"), or null for shared pages. */
export function productOfPath(rel: string): Product | null {
  const m = /^(?:vi\/)?(image|pdf)\//.exec(rel.replace(/^\//, ""));
  return m ? (m[1] as Product) : null;
}

/** The product chosen last. Module state: one per browser tab; on the server it stays "image". */
export const remembered = ref<Product>("image");

export function loadRemembered(): void {
  try {
    const v = localStorage.getItem(KEY);
    if (v === "image" || v === "pdf") remembered.value = v;
  } catch { /* storage blocked: keep the default */ }
}
export function saveRemembered(p: Product): void {
  remembered.value = p;
  try { localStorage.setItem(KEY, p); } catch { /* storage blocked */ }
}

// Pages that exist in both products under the same name; the switcher keeps the reader on the "same" page.
const SAME = new Set(["", "fonts", "api", "css-support", "recipes", "differences-from-takumi"]);
/** Route of the page that corresponds to `pathname` in product `to` (its index when there is no counterpart). */
export function counterpart(pathname: string, to: Product): string {
  const vi = /^\/vi(\/|$)/.test(pathname);
  const prefix = (vi ? "/vi/" : "/") + to + "/";
  const m = /^(?:\/vi)?\/(image|pdf)\/(.*)$/.exec(pathname.replace(/\.html$/, ""));
  if (!m) return prefix;
  const rest = m[2].replace(/\/$/, "");
  if (m[1] === to) return pathname;
  if (to === "pdf" && (rest === "frameworks" || rest.startsWith("frameworks/"))) return prefix + "frameworks";
  if (to === "image" && rest === "frameworks") return prefix + "frameworks/";
  return SAME.has(rest) ? prefix + rest : prefix;
}

/** Replaces the injected `theme` data so that shared pages get the sidebar of the remembered product. VitePress's
 *  sidebar is configured per path prefix; config.mts gives "/" (and "/vi/") the Image sidebar, and the PDF sidebar is
 *  available under "/pdf/" ("/vi/pdf/"). Returns the effective product of the current page. */
export function installProductSidebar(app: App, router: Router): ComputedRef<Product> {
  const data = (app as any)._context.provides[dataSymbol];
  const product = computed<Product>(() => productOfPath(router.route.data.relativePath) ?? remembered.value);
  if (!data?.theme) return product;
  const original = data.theme;
  data.theme = computed(() => {
    const t = original.value;
    const rel: string = router.route.data.relativePath ?? "";
    if (!t.sidebar || Array.isArray(t.sidebar) || productOfPath(rel) || remembered.value === "image") return t;
    const key = (rel.startsWith("vi/") ? "/vi/" : "/") + remembered.value + "/";
    return t.sidebar[key] ? { ...t, sidebar: { [rel.startsWith("vi/") ? "/vi/" : "/"]: t.sidebar[key] } } : t;
  });
  return product;
}
