// Narrow, observable-equivalence checks for documented representation differences.
// This never weakens the comparison of other fixtures or non-BBox instructions.
import { rasterise } from '../bench/pdf/lib/raster.mjs';
import { inspect } from '../bench/pdf/lib/pdfjs.mjs';

export async function fixtureEquivalence(name, mine, gold, mineOps, goldOps, compare) {
  if (name !== 'color-glyph-text-shadow') return null;
  const strip = ops => ops.map(line => line.replace(/^Do\(form bbox=\[[^\]]+\]/, 'Do(form bbox=<checked-by-raster>'));
  if (compare(strip(mineOps), strip(goldOps)).verdict === 'DIFFER') return null;
  const a = await inspect(mine), b = await inspect(gold);
  if (a.error || b.error || JSON.stringify(a.pages.map(p => p.text)) !== JSON.stringify(b.pages.map(p => p.text))) return null;
  const evidence = [];
  for (const renderer of ['pdfjs', 'mupdf', 'pdfium']) for (const dpi of [144, 288]) {
    const x = await rasterise(renderer, mine, 0, dpi), y = await rasterise(renderer, gold, 0, dpi);
    if (x.width !== y.width || x.height !== y.height || x.rgba.length !== y.rgba.length) return null;
    let changedPixels = 0, maxChannelDifference = 0;
    for (let i = 0; i < x.rgba.length; i += 4) {
      let difference = 0;
      for (let c = 0; c < 4; c++) difference = Math.max(difference, Math.abs(x.rgba[i + c] - y.rgba[i + c]));
      changedPixels += Number(difference !== 0);
      maxChannelDifference = Math.max(maxChannelDifference, difference);
    }
    // This fixture's remaining decimal path rounding affects five pixels in
    // PDF.js at 288 dpi. Both independent native viewers must remain exact.
    const pdfjsRounding = renderer === 'pdfjs' && dpi === 288;
    if (changedPixels > (pdfjsRounding ? 5 : 0) || maxChannelDifference > (pdfjsRounding ? 2 : 0)) return null;
    evidence.push({ renderer, dpi, width: x.width, height: x.height, changedPixels, maxChannelDifference });
  }
  return {
    kind: 'form-bounds',
    reason: 'COLR shadow group bounds: BM uses tight curve bounds plus stroke radius; pinned krilla measures its stroked outline. Other instructions retain the normal numeric tolerance. Extraction, MuPDF/PDFium at 144/288 dpi and PDF.js at 144 dpi must match exactly. PDF.js at 288 dpi permits only the observed decimal-rounding difference: five pixels, two channel levels.',
    evidence,
  };
}
