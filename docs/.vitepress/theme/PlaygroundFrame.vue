<script setup lang="ts">
// Embeds the self-contained playground build (docs/public/playground-app/ -> /playground-app/, produced by docs/playground-app/build.mjs)
// and keeps its language and colour scheme in sync with the docs site.
import { computed, ref, watch } from "vue";
import { useData, withBase } from "vitepress";

const props = defineProps<{ lang: "en" | "vi" }>();
const { isDark } = useData();
const frame = ref<HTMLIFrameElement | null>(null);
// The initial theme goes into the URL; later toggles are posted so the app is not reloaded.
// The production host (Vercel, cleanUrls) serves the folder URL; the Vite dev server only serves public/ files by
// their exact name, so dev uses index.html explicitly.
const entry = import.meta.env.DEV ? "/playground-app/index.html" : "/playground-app/";
const initialTheme = isDark.value ? "dark" : "light";
const src = computed(() => withBase(`${entry}?lang=${props.lang}&theme=${initialTheme}`));
const openHref = computed(() => withBase(`${entry}?lang=${props.lang}`));
watch(isDark, (d) => {
  frame.value?.contentWindow?.postMessage({ type: "bm-playground:theme", theme: d ? "dark" : "light" }, location.origin);
});
const label = computed(() => (props.lang === "vi" ? "Mở playground trong tab mới" : "Open the playground in a new tab"));
</script>

<template>
  <div class="pg-embed">
    <div class="pg-embed-bar">
      <a :href="openHref" target="_blank" rel="noopener">{{ label }} ↗</a>
    </div>
    <iframe ref="frame" class="pg-embed-frame" :src="src" title="bm-engine playground" loading="eager"
      allow="clipboard-write" />
  </div>
</template>
