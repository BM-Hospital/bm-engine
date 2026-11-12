import DefaultTheme from "vitepress/theme";
import type { Theme } from "vitepress";
import PlaygroundFrame from "./PlaygroundFrame.vue";
import "./custom.css";

// Pages that exist in one language only. The language switcher links to the "same" path in the other locale;
// send those to the closest real page instead of a 404 (vercel.json has the same redirects for direct hits).
const CROSS_LOCALE: Record<string, string> = {
  "/benchmark-report": "/benchmark",
  "/vi/results-full": "/results-full",
  "/vi/dev/architecture": "/dev/architecture",
  "/vi/dev/takumi-notes": "/dev/takumi-notes",
  "/vi/dev/conventions": "/dev/conventions",
};

export default {
  extends: DefaultTheme,
  enhanceApp({ app, router }) {
    app.component("PlaygroundFrame", PlaygroundFrame);
    router.onBeforeRouteChange = (to) => {
      const u = new URL(to, "http://x");
      const target = CROSS_LOCALE[u.pathname.replace(/\.html$/, "")];
      if (target) { setTimeout(() => router.go(target + u.hash)); return false; }
    };
  },
} satisfies Theme;
