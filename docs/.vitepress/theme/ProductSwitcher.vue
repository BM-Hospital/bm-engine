<script setup lang="ts">
// Product switcher at the top of the left sidebar (desktop) and of the sidebar drawer (mobile): a button showing the
// current product that opens a listbox with both products. Choosing one navigates to the same page in that product
// when it exists (fonts, api, css-support, recipes, ...) and to its index otherwise, in the current locale.
import { computed, inject, nextTick, onBeforeUnmount, onMounted, ref, type Ref } from "vue";
import { useData, useRouter, withBase } from "vitepress";
import { PRODUCTS, counterpart, saveRemembered, type Product } from "./product";

const { theme } = useData();
const router = useRouter();
const product = inject<Ref<Product>>("bm-product")!;
const open = ref(false);
const active = ref(0); // index of the highlighted option while the list is open
const root = ref<HTMLElement | null>(null);
const button = ref<HTMLButtonElement | null>(null);
const list = ref<HTMLElement | null>(null);
const uid = "bm-product-switcher";

const info = computed(() => (theme.value as any).products ?? {
  label: "Choose a product",
  image: { title: "Image", description: "PNG, JPEG, WebP, SVG, animations" },
  pdf: { title: "PDF", description: "Paged documents" },
});
const current = computed(() => info.value[product.value]);

function show() {
  open.value = true;
  active.value = PRODUCTS.indexOf(product.value);
  nextTick(() => list.value?.focus());
}
function hide(focusButton = true) {
  open.value = false;
  if (focusButton) nextTick(() => button.value?.focus());
}
function choose(p: Product) {
  hide(false);
  saveRemembered(p);
  const here = router.route.path;
  const target = counterpart(here, p);
  if (target !== here) router.go(withBase(target));
}
function onButtonKey(e: KeyboardEvent) {
  if (["ArrowDown", "ArrowUp", "Enter", " "].includes(e.key)) { e.preventDefault(); show(); }
}
function onListKey(e: KeyboardEvent) {
  const n = PRODUCTS.length;
  switch (e.key) {
    case "ArrowDown": e.preventDefault(); active.value = (active.value + 1) % n; break;
    case "ArrowUp": e.preventDefault(); active.value = (active.value + n - 1) % n; break;
    case "Home": e.preventDefault(); active.value = 0; break;
    case "End": e.preventDefault(); active.value = n - 1; break;
    case "Enter": case " ": e.preventDefault(); choose(PRODUCTS[active.value]); break;
    case "Escape": e.preventDefault(); e.stopPropagation(); hide(); break;
    case "Tab": hide(false); break;
  }
}
function onDocClick(e: MouseEvent) {
  if (open.value && root.value && !root.value.contains(e.target as Node)) hide(false);
}
onMounted(() => document.addEventListener("mousedown", onDocClick));
onBeforeUnmount(() => document.removeEventListener("mousedown", onDocClick));
</script>

<template>
  <div ref="root" class="bm-switcher" :class="{ open }">
    <button ref="button" type="button" class="bm-switcher-button" :aria-expanded="open ? 'true' : 'false'"
      aria-haspopup="listbox" :aria-controls="uid + '-list'" :aria-label="`${info.label}: ${current.title}`"
      @click="open ? hide() : show()" @keydown="onButtonKey">
      <span class="bm-switcher-icon" :class="'is-' + product" aria-hidden="true">
        <svg v-if="product === 'image'" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2" /><circle cx="9" cy="9" r="2" /><path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21" /></svg>
        <svg v-else viewBox="0 0 24 24"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z" /><path d="M14 2v4a2 2 0 0 0 2 2h4" /><path d="M10 9H8M16 13H8M16 17H8" /></svg>
      </span>
      <span class="bm-switcher-text">
        <span class="bm-switcher-title">{{ current.title }}</span>
        <span class="bm-switcher-desc">{{ current.description }}</span>
      </span>
      <svg class="bm-switcher-chevron" viewBox="0 0 24 24" aria-hidden="true"><path d="m7 15 5 5 5-5M7 9l5-5 5 5" /></svg>
    </button>
    <ul v-show="open" :id="uid + '-list'" ref="list" class="bm-switcher-list" role="listbox" tabindex="-1"
      :aria-label="info.label" :aria-activedescendant="`${uid}-${PRODUCTS[active]}`" @keydown="onListKey">
      <li v-for="(p, i) in PRODUCTS" :id="`${uid}-${p}`" :key="p" role="option" class="bm-switcher-option"
        :class="{ active: i === active, selected: p === product }" :aria-selected="p === product ? 'true' : 'false'"
        @click="choose(p)" @mousemove="active = i">
        <span class="bm-switcher-icon" :class="'is-' + p" aria-hidden="true">
          <svg v-if="p === 'image'" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2" /><circle cx="9" cy="9" r="2" /><path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21" /></svg>
          <svg v-else viewBox="0 0 24 24"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z" /><path d="M14 2v4a2 2 0 0 0 2 2h4" /><path d="M10 9H8M16 13H8M16 17H8" /></svg>
        </span>
        <span class="bm-switcher-text">
          <span class="bm-switcher-title">{{ info[p].title }}</span>
          <span class="bm-switcher-desc">{{ info[p].description }}</span>
        </span>
        <svg v-if="p === product" class="bm-switcher-check" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6 9 17l-5-5" /></svg>
      </li>
    </ul>
  </div>
</template>
