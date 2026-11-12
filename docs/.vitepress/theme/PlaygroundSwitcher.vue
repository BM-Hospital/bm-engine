<script setup lang="ts">
// Compact product switcher of the playground pages (/image/playground, /pdf/playground and the /vi/ versions).
// Those pages are full width without the sidebar, so the sidebar's ProductSwitcher is not there; this one sits in
// the page header above the embedded app: two links (Image | PDF) styled like the sidebar switcher, the current
// product marked with aria-current. Choosing the other product loads its playground page in the same locale (the
// app restores the editor content from localStorage, so the document carries over).
import { computed } from "vue";
import { useData, withBase } from "vitepress";
import { PRODUCTS, saveRemembered, type Product } from "./product";

const props = defineProps<{ product: Product }>();
const { theme, localeIndex } = useData();
const vi = computed(() => localeIndex.value === "vi");
const info = computed(() => (theme.value as any).products ?? {
  label: "Choose a product", image: { title: "Image" }, pdf: { title: "PDF" },
});
const href = (p: Product) => withBase(`${vi.value ? "/vi" : ""}/${p}/playground`);
const label = computed(() => (vi.value ? "Playground cho" : "Playground for"));
// The app opens PDF mode on its first PDF template the first time; coming from the other playground it keeps the
// editor content instead (the app reads and clears this mark).
function choose(p: Product) {
  saveRemembered(p);
  if (p !== props.product) { try { localStorage.setItem("bm-playground-carry", String(Date.now())); } catch { /* storage blocked */ } }
}
</script>

<template>
  <nav class="bm-pg-switcher" :aria-label="info.label">
    <span class="bm-pg-switcher-label">{{ label }}</span>
    <div class="bm-pg-switcher-group">
      <a v-for="p in PRODUCTS" :key="p" :href="href(p)" class="bm-pg-switcher-item" :class="['is-' + p, { active: p === props.product }]"
        :aria-current="p === props.product ? 'page' : undefined" @click="choose(p)">
        <span class="bm-switcher-icon" :class="'is-' + p" aria-hidden="true">
          <svg v-if="p === 'image'" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2" /><circle cx="9" cy="9" r="2" /><path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21" /></svg>
          <svg v-else viewBox="0 0 24 24"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z" /><path d="M14 2v4a2 2 0 0 0 2 2h4" /><path d="M10 9H8M16 13H8M16 17H8" /></svg>
        </span>
        <span>{{ info[p].title }}</span>
      </a>
    </div>
  </nav>
</template>
