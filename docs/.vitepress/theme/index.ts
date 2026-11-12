import DefaultTheme from "vitepress/theme";
import { inBrowser, useRoute, useRouter, type Theme } from "vitepress";
import { computed, defineComponent, h, inject, onMounted, watch, type Ref } from "vue";
import PlaygroundFrame from "./PlaygroundFrame.vue";
import ProductSwitcher from "./ProductSwitcher.vue";
import ProductCards from "./ProductCards.vue";
import PlaygroundSwitcher from "./PlaygroundSwitcher.vue";
import { installProductSidebar, loadRemembered, productOfPath, saveRemembered, type Product } from "./product";
import { CROSS_LOCALE, redirectFor, movedAnchor } from "../redirects.mjs";
import "./custom.css";

/** Where an old or single-language URL should go (keeping the #anchor), or null. */
function target(pathname: string, hash: string): string | null {
  const p = pathname.replace(/\.html$/, "");
  const t = (CROSS_LOCALE as Record<string, string>)[p] ?? redirectFor(p);
  if (t) return t + hash;
  return movedAnchor(p, hash);
}

// Direct hits on old URLs: the static host answers with 404.html (Vercel redirects before that, see vercel.json).
// (A #section that moved off an existing page is handled after mounting, see Layout.)
if (inBrowser) {
  const p = location.pathname.replace(/\.html$/, "");
  const t = (CROSS_LOCALE as Record<string, string>)[p] ?? redirectFor(p);
  if (t) location.replace(t + location.search + location.hash);
}

let mounted = false;

/** Default layout + product switcher at the top of the sidebar (and a compact one above the playground) + product
 *  cards under the home hero + a per-product accent class on the layout root. */
const Layout = defineComponent({
  setup() {
    const route = useRoute();
    const router = useRouter();
    const product = inject<Ref<Product>>("bm-product")!;
    const section = computed(() => productOfPath(route.data.relativePath));
    // the playground pages (no sidebar, so no sidebar switcher) get a compact Image | PDF switcher above the app
    const playground = computed(() => /^(?:vi\/)?(image|pdf)\/playground\.md$/.exec(route.data.relativePath ?? "")?.[1] as Product | undefined);
    onMounted(() => {
      mounted = true;
      loadRemembered(); // shared pages switch to the remembered product's sidebar now (not during hydration)
      watch(section, (p) => { if (p) saveRemembered(p); }, { immediate: true });
      const moved = movedAnchor(location.pathname, location.hash); // e.g. /getting-started#fonts -> /image/#fonts
      if (moved) setTimeout(() => router.go(moved)); // after hydration has finished
    });
    return () => h(DefaultTheme.Layout, { class: section.value === "pdf" ? "product-pdf" : section.value === "image" ? "product-image" : "product-shared", "data-product": product.value }, {
      "sidebar-nav-before": () => h(ProductSwitcher),
      "home-hero-after": () => h(ProductCards),
      "doc-before": () => (playground.value ? h(PlaygroundSwitcher, { product: playground.value }) : null),
    });
  },
});

export default {
  extends: DefaultTheme,
  Layout,
  enhanceApp({ app, router }) {
    app.component("PlaygroundFrame", PlaygroundFrame);
    app.provide("bm-product", installProductSidebar(app, router));
    router.onBeforeRouteChange = (to) => {
      // only for navigation inside the running app: the first route (server render, hydration) must load as is
      if (!mounted) return;
      const u = new URL(to, "http://x");
      const t = target(u.pathname, u.hash);
      if (t) { setTimeout(() => router.go(t)); return false; }
    };
  },
} satisfies Theme;
