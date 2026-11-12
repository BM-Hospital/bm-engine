<script setup lang="ts">
// Embeds the self-contained playground build (docs/public/playground-app/ -> /playground-app/, produced by docs/playground-app/build.mjs)
// in Image or PDF mode and keeps its language and colour scheme in sync with the docs site. The app hides its own
// Image | PDF switch when embedded (?embed=1): the page shows PlaygroundSwitcher above it, which moves between
// /image/playground and /pdf/playground. A #s=... share hash on the docs URL is handed to the app.
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useData, useRouter, withBase } from "vitepress";

const props = withDefaults(defineProps<{ lang: "en" | "vi"; mode?: "image" | "pdf" }>(), { mode: "image" });
const { isDark } = useData();
const router = useRouter();
const frame = ref<HTMLIFrameElement | null>(null);
// The initial theme goes into the URL; later toggles are posted so the app is not reloaded.
// The production host (Vercel, cleanUrls) serves the folder URL; the Vite dev server only serves public/ files by
// their exact name, so dev uses index.html explicitly.
const entry = import.meta.env.DEV ? "/playground-app/index.html" : "/playground-app/";
const initialTheme = isDark.value ? "dark" : "light";
const hash = typeof location !== "undefined" && /^#s=[zp]\./.test(location.hash) ? location.hash : "";
const src = computed(() => withBase(`${entry}?lang=${props.lang}&mode=${props.mode}&embed=1&theme=${initialTheme}`) + hash);
const openHref = computed(() => withBase(`${entry}?lang=${props.lang}&mode=${props.mode}`));
watch(isDark, (d) => {
  frame.value?.contentWindow?.postMessage({ type: "bm-playground:theme", theme: d ? "dark" : "light" }, location.origin);
});
// The app announces a mode change (only possible when its switch is shown): follow it with the matching page.
function onMessage(e: MessageEvent) {
  if (e.origin !== location.origin || e.source !== frame.value?.contentWindow || e.data?.type !== "bm-playground:mode") return;
  if (e.data.mode !== props.mode && (e.data.mode === "image" || e.data.mode === "pdf")) router.go(withBase(`${props.lang === "vi" ? "/vi" : ""}/${e.data.mode}/playground`));
}
onMounted(() => window.addEventListener("message", onMessage));
onBeforeUnmount(() => window.removeEventListener("message", onMessage));
const label = computed(() => (props.lang === "vi" ? "Mở playground trong tab mới" : "Open the playground in a new tab"));
</script>

<template>
  <div class="pg-embed" :data-mode="mode">
    <div class="pg-embed-bar">
      <a :href="openHref" target="_blank" rel="noopener">{{ label }} ↗</a>
    </div>
    <iframe ref="frame" class="pg-embed-frame" :src="src" :title="mode === 'pdf' ? 'bm-engine PDF playground' : 'bm-engine playground'"
      loading="eager" allow="clipboard-write" />
  </div>
</template>
