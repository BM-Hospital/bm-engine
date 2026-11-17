<script setup lang="ts">
// Home hero image: two real outputs of bm-render (the images are produced by docs/examples/templates.mjs and
// docs/examples/pdf-recipes.mjs), an Open Graph card and the first page of an invoice PDF.
import { computed } from "vue";
import { useData, withBase } from "vitepress";

const { localeIndex } = useData();
const vi = computed(() => localeIndex.value === "vi");
</script>

<template>
  <div class="bm-hero-visual">
    <figure class="bm-hero-shot is-pdf">
      <img :src="withBase('/img/guide/recipe-invoice.png')" width="560" height="790" loading="eager"
        :alt="vi ? 'Trang đầu của một hoá đơn PDF render bằng bm-render' : 'First page of an invoice PDF rendered by bm-render'" />
      <span class="bm-hero-tag">invoice.pdf</span>
    </figure>
    <figure class="bm-hero-shot is-image">
      <img :src="withBase('/img/guide/templates-og-card.png')" width="800" height="420" loading="eager"
        :alt="vi ? 'Thẻ Open Graph render bằng bm-render' : 'Open Graph card rendered by bm-render'" />
      <span class="bm-hero-tag">og.png</span>
    </figure>
    <p class="bm-hero-caption">{{ vi ? "Cả hai đều render bằng bm-render" : "Both rendered by bm-render" }}</p>
  </div>
</template>
