// Named-page inline-size changes while parallel formatting contexts are unfinished.
import { probeAs, cmp } from './paint.probe.mjs';
import { squash } from './lib.mjs';
import { SMALL, cmp as comparePaged, doc, lines } from './paged-helpers.mjs';
import { rasterise } from '../../bench/pdf/lib/raster.mjs';

const words = (prefix, n = 45) => Array.from({ length: n }, (_, i) => `${prefix}${i} word`).join(' ');
const sheet = `<style>@page{size:240px 140px;margin:10px}@page:left{size:360px 140px;margin:10px}p{margin:0}td{padding:0;vertical-align:top}table{border-spacing:0}</style>`;
probeAs('pagination.continuation.rowspan-fixed-width', 'rowspanning cells retain an independent continuation flow', async t => {
  const html = `<style>@page{size:240px 140px;margin:10px}p{margin:0}td{padding:0;vertical-align:top}table{border-spacing:0}</style><div style="font:14px/20px Inter"><table style="width:100%"><tr><td rowspan="2" style="width:50%">${words('L')}</td><td>${words('R').slice(0,130)}</td></tr><tr><td>${words('B')}</td></tr></table><p>AFTER</p></div>`;
  const r = await cmp(t, '', html, {});
  if (r.ref && !r.bm.error && !r.ref.error) t.same('text per page', r.bm.textPages.map(squash), r.ref.textPages.map(squash));
});
probeAs('pagination.continuation.rowspan-width-reflow', 'rowspanning cells resume against each named-page width', async t => {
  const html = `${sheet}<div style="font:14px/20px Inter"><table style="width:100%"><tr><td rowspan="2" style="width:35%"><a href="#end">${words('SPAN', 20)}</a></td><td style="width:65%"><a href="#end">${words('ROW1', 12)}</a></td></tr><tr><td><a href="#end">${words('ROW2', 12)}</a></td></tr></table><p id="end">END</p></div>`;
  const r = await comparePaged(t, 'rowspan width change', html, {}, { geom: true });
  if (r.ref && !r.bm.error && !r.ref.error) {
    t.same('rowspan text per page', r.bm.textPages.map(squash), r.ref.textPages.map(squash));
    t.same('rowspan page boxes', r.bm.pages.map(p => p.media), r.ref.pages.map(p => p.media));
    const { inspect } = await import('../../bench/pdf/lib/pdfjs.mjs');
    const a = await inspect(r.bm.bytes), b = await inspect(r.ref.bytes);
    t.same('rowspan links per page', a.pages.map(p => p.links), b.pages.map(p => p.links));
  }
});
for (const [id, content] of [
  ['table-row', `<table style="width:100%"><tr><td style="width:50%">${words('L')}</td><td>${words('R')}</td></tr></table>`],
  ['table-plain', `<table style="width:100%"><tr><td style="width:50%">${'left word '.repeat(45)}</td><td>${'right word '.repeat(45)}</td></tr></table>`],
  ['table-unequal', `<table style="width:100%"><tr><td style="width:50%">${'short word '.repeat(8)}</td><td>${'long word '.repeat(55)}</td></tr></table>`],
  ['table-painted', `<table style="width:100%"><tr><td style="width:50%;background:#cde;border:1px solid blue">${words('L')}</td><td style="background:#edc;border:1px solid red">${words('R')}</td></tr></table>`],
  // a cell whose content ends at the page end keeps its block-end padding and border in that
  // fragment, past the page; the row's rest shrinks by it but still holds them on its last page
  ['table-painted-padded', `<table style="width:100%"><tr><td style="width:50%;background:#cde;border:1px solid blue;padding-bottom:3px">${words('L')}</td><td style="background:#edc;border:1px solid red;padding-bottom:3px">${words('R')}</td></tr></table>`],
  ['table-painted-unequal', `<table style="width:100%"><tr><td style="width:50%;background:#cde;border:1px solid blue">${words('L')}</td><td style="background:#edc;border:1px solid red">${words('R', 30)}</td></tr></table>`],
  ['table-links', `<table style="width:100%"><tr><td style="width:50%"><a href="https://example.com/left">${words('L')}</a></td><td><a href="#after">${words('R')}</a></td></tr></table><p id="after">Destination</p>`],
  ['table-rowspan', `<table style="width:100%"><tr><td rowspan="2" style="width:50%">${words('L')}</td><td>${words('R').slice(0, 130)}</td></tr><tr><td>${words('B')}</td></tr></table>`],
  ['flex-row', `<div style="display:flex"><div style="flex:1;min-width:0">${words('L')}</div><div style="flex:1;min-width:0">${words('R')}</div></div>`],
  ['grid-row', `<div style="display:grid;grid-template-columns:1fr 1fr"><div>${words('L')}</div><div>${words('R')}</div></div>`],
]) {
  probeAs(`pagination.continuation.${id}`, 'parallel continuation across alternating page widths', async t => {
    const r = await cmp(t, '', `${sheet}<div style="font:14px/20px Inter">${content}<p>AFTER</p></div>`, {});
    if (r.ref && !r.bm.error && !r.ref.error) {
      t.same('text per page', r.bm.textPages.map(squash), r.ref.textPages.map(squash));
      t.same('page boxes', r.bm.pages.map(p => p.media), r.ref.pages.map(p => p.media));
      if (id === 'table-links') {
        const { inspect } = await import('../../bench/pdf/lib/pdfjs.mjs');
        const a = await inspect(r.bm.bytes), b = await inspect(r.ref.bytes);
        t.same('links per page', a.pages.map(p => p.links), b.pages.map(p => p.links));
      }
    }
  });
}

probeAs('pagination.continuation.collapsed-border-overflow', 'collapsed table borders and cell backgrounds continue across a page cut', async t => {
  const html = `${sheet}<style>table{border-collapse:collapse}td{padding:0 2px 4px;border-left:3px solid #1673c9;border-right:3px solid #1673c9;border-top:3px solid red;border-bottom:3px solid blue}td:first-child{background:#cde}td:last-child{background:#edc}</style><div style="font:14px/20px Inter"><div style="height:40px"></div><table style="width:100%"><tr><td>${words('SHORT', 12)}</td><td>${words('LONG', 42)}</td></tr></table><p>AFTER</p></div>`;
  const r = await comparePaged(t, 'collapsed border overflow', html, {}, { geom: true, expect: 'render' });
  if (!r.bm.error && r.ref && !r.ref.error) {
    const [bmFirst, bmSecond, refFirst, refSecond] = await Promise.all([
      rasterise('pdfium', r.bm.bytes, 0, 144), rasterise('pdfium', r.bm.bytes, 1, 144),
      rasterise('pdfium', r.ref.bytes, 0, 144), rasterise('pdfium', r.ref.bytes, 1, 144),
    ]);
    const hasColorAtX = (page, x, ys, rgb) => ys.some(y => {
      const i = (y * page.width + x) * 4;
      return page.rgba[i] === rgb[0] && page.rgba[i + 1] === rgb[1] && page.rgba[i + 2] === rgb[2];
    });
    for (const [name, first, second] of [['bm', bmFirst, bmSecond], ['takumi', refFirst, refSecond]]) {
      t.ok(hasColorAtX(first, 100, Array.from({ length: 12 }, (_, i) => 188 + i), [0, 0, 255]), `${name}: collapsed block-end border paints at page 1 bottom`);
      t.ok(hasColorAtX(second, 100, Array.from({ length: 12 }, (_, i) => 10 + i), [255, 0, 0]), `${name}: collapsed block-start border paints at page 2 top`);
    }
  }
});

// An aligned item can have an empty first fragment while its sibling already
// paints. On resumption the original row alignment offset must not be repeated.
for (const align of ['start', 'center', 'end']) {
  for (const prefix of [0, 3]) {
    probeAs(`pagination.continuation.grid-aligned-${align}-${prefix}`, 'aligned grid items resume at the fragment start', async t => {
      const html = doc(lines(1, prefix) + `<div style="display:grid;grid-template-columns:1fr 1fr;align-items:${align}"><div>${lines(1, 24)}</div><div class="l">ALIGNED</div></div>` + lines(1, 2, () => '', 'AFTER'));
      await comparePaged(t, '', html, SMALL, { geom: true, expect: 'render' });
    });
  }
}
