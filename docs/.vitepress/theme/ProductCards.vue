<script setup lang="ts">
// Two entry cards under the home hero: Image and PDF documentation, in the current locale.
import { computed } from "vue";
import { useData, withBase } from "vitepress";

const { theme, localeIndex } = useData();
const vi = computed(() => localeIndex.value === "vi");
const p = computed(() => (vi.value ? "/vi/" : "/"));
const info = computed(() => (theme.value as any).products);
const cards = computed(() => [
  {
    key: "image", href: withBase(p.value + "image/"),
    lead: vi.value ? "Thẻ OG, ảnh mạng xã hội, biểu đồ, ảnh động từ cây node, HTML và Tailwind." : "OG cards, social images, charts and animations from node trees, HTML and Tailwind.",
    links: vi.value
      ? [["Bắt đầu nhanh", "image/"], ["Tham chiếu API", "image/api"], ["Hỗ trợ CSS", "image/css-support"], ["Framework", "image/frameworks/"]]
      : [["Quick start", "image/"], ["API reference", "image/api"], ["CSS support", "image/css-support"], ["Frameworks", "image/frameworks/"]],
  },
  {
    key: "pdf", href: withBase(p.value + "pdf/"),
    lead: vi.value ? "Hoá đơn, báo cáo, vé: chữ bôi chọn được, phân trang, header và footer, PDF/UA và PDF/A." : "Invoices, reports and tickets: selectable text, pagination, headers and footers, PDF/UA and PDF/A.",
    links: vi.value
      ? [["Bắt đầu nhanh", "pdf/"], ["Phân trang", "pdf/pagination"], ["Tham chiếu API", "pdf/api"], ["Công thức", "pdf/recipes"]]
      : [["Quick start", "pdf/"], ["Pagination", "pdf/pagination"], ["API reference", "pdf/api"], ["Recipes", "pdf/recipes"]],
  },
]);
</script>

<template>
  <div v-if="info" class="bm-products">
    <div class="bm-products-inner">
      <section v-for="c in cards" :key="c.key" class="bm-product-card" :class="'is-' + c.key">
        <a class="bm-product-head" :href="c.href">
          <span class="bm-switcher-icon" :class="'is-' + c.key" aria-hidden="true">
            <svg v-if="c.key === 'image'" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2" /><circle cx="9" cy="9" r="2" /><path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21" /></svg>
            <svg v-else viewBox="0 0 24 24"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z" /><path d="M14 2v4a2 2 0 0 0 2 2h4" /><path d="M10 9H8M16 13H8M16 17H8" /></svg>
          </span>
          <span class="bm-product-name">{{ info[c.key].title }}</span>
          <span class="bm-product-desc">{{ info[c.key].description }}</span>
        </a>
        <p class="bm-product-lead">{{ c.lead }}</p>
        <ul class="bm-product-links">
          <li v-for="[t, l] in c.links" :key="l"><a :href="withBase(p + l)">{{ t }}</a></li>
        </ul>
      </section>
    </div>
  </div>
</template>
