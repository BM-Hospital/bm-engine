import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { fixtureEquivalence } from '../pdf-fixture-equivalence.mjs';
import { parseWordBoxes, wordBoxes } from './paged-helpers.mjs';

test('word geometry rejects empty extraction and retains genuinely empty pages', () => {
  assert.throws(() => parseWordBoxes(''), /no page elements/);
  assert.throws(() => parseWordBoxes('tool failed'), /no page elements/);
  assert.deepEqual(parseWordBoxes('<page width="10" height="10"></page>'), [[]]);
  assert.deepEqual(parseWordBoxes('<page width="10" height="10"><word xMin="1" yMin="2" xMax="3" yMax="4">A</word></page>'), [[['A', 1, 2, 3, 4]]]);
});

const runner = fileURLToPath(new URL('./run.mjs', import.meta.url));
function run(args) {
  const env = { ...process.env, BM_RENDER_BACKEND: 'wasm' };
  delete env.TAKUMI_PDF_REF;
  delete env.TAKUMI_PDF_REF_ENTRY;
  return spawnSync(process.execPath, [runner, ...args], { env, encoding: 'utf8', windowsHide: true, timeout: 120_000 });
}
test('strict audit rejects missing reference even when bm-only assertions pass', () => {
  const r = run(['--strict', 'paint.outline.inline-paged']);
  assert.equal(r.status, 1, r.stderr);
  assert.match(r.stdout, /UNVERIFIED\s+paint\.outline\.inline-paged/);
  assert.match(r.stdout, /0 pass, 0 fail, 1 unverified/);
});
test('a misspelled probe filter cannot create an empty passing gate', () => {
  const r = run(['--strict', 'gate.nonexistent-probe']);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /No PDF audit probes matched/);
});
test('unknown flags cannot silently disable the requested gate', () => {
  const r = run(['--strcit', 'paint.outline.inline-paged']);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /Unknown PDF audit option/);
});

test('a fixture equivalence never applies to another fixture or other instruction differences', async () => {
  const bytes = new Uint8Array();
  assert.equal(await fixtureEquivalence('another-fixture', bytes, bytes, [], [], () => { throw new Error('unexpected comparison'); }), null);
  assert.equal(await fixtureEquivalence('color-glyph-text-shadow', bytes, bytes, ['new paint'], ['old paint'], () => ({ verdict: 'DIFFER' })), null);
});

test('a changed mark cannot pass the form-bounds exception', async () => {
  const { PdfRenderer } = await import('../../js/node-pdf.mjs');
  const renderer = new PdfRenderer();
  const options = { viewport: { width: 64, height: 64 }, tagged: false };
  const red = await renderer.render('<div style="width:40px;height:40px;background:red"></div>', options);
  const blue = await renderer.render('<div style="width:40px;height:40px;background:blue"></div>', options);
  assert.deepEqual(wordBoxes(red), [[]], 'a real blank text page remains verifiable');
  // Even if the structural precondition admitted it, the viewer gate must reject it.
  const result = await fixtureEquivalence('color-glyph-text-shadow', red, blue, [], [], () => ({ verdict: 'CLOSE' }));
  assert.equal(result, null);
  renderer[Symbol.dispose]();
});
