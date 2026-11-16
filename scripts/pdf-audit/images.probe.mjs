// Image probes: how each raster format, SVG and `object-fit` end up in the PDF (image XObject dictionary: size, colour
// space, bits, filter, soft mask, ICC profile; passthrough or re-encoded; vector or raster SVG), compared between
// bm-render/pdf and takumi-pdf with the canonical pages of paint.probe.mjs. The decoded data of an image is part of
// the comparison (a hash), so an image that is passed through by one engine and re-encoded by the other fails, and so
// do different pixels.
import zlib from "node:zlib";
import { cases, cmp, dataUri, fileBytes, probeAs, summary, svgUri, vp } from "./paint.probe.mjs";

const b64 = (buf, mime) => `data:${mime};base64,${Buffer.from(buf).toString("base64")}`;
// inside a <div>: an <img> that is the only top-level element is stretched to the viewport by bm-render (images.root-img)
const img = (src, style = "width:40px;height:40px") => `<div style="margin:10px"><img src="${src}" style="${style}"></div>`;
const suite = (name) => dataUri(`src/codec/testdata/png_suite/${name}.png`);
const codec = (name) => dataUri(`src/codec/testdata/${name}`);

// ------------------------------------------------------------------------------------------------ crafted files

function pngChunks(buf) {
  const out = []; let p = 8;
  while (p < buf.length) { const len = buf.readUInt32BE(p); out.push({ type: buf.toString("latin1", p + 4, p + 8), data: buf.subarray(p + 8, p + 8 + len) }); p += 12 + len; }
  return out;
}
function pngFrom(chunks) {
  const parts = [Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])];
  for (const c of chunks) {
    const head = Buffer.alloc(8); head.writeUInt32BE(c.data.length, 0); head.write(c.type, 4, "latin1");
    const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(Buffer.concat([head.subarray(4), c.data])) >>> 0, 0);
    parts.push(head, c.data, crc);
  }
  return Buffer.concat(parts);
}
/** A PNG with extra ancillary chunks inserted after IHDR. */
function pngWith(rel, extra) {
  const chunks = pngChunks(fileBytes(rel));
  return pngFrom([chunks[0], ...extra, ...chunks.slice(1)]);
}
/** A minimal valid ICC v2 sRGB-like RGB profile header + required tags are not needed by the engines' checks: a real one is built. */
function tinyIcc(space = "RGB ") {
  // 128-byte header + tag table with 0 tags: enough for krilla's ICCProfile::new (reads the header fields)
  const b = Buffer.alloc(132);
  b.writeUInt32BE(132, 0); b.writeUInt32BE(0x02100000, 8); b.write("mntr", 12, "latin1"); b.write(space, 16, "latin1"); b.write("XYZ ", 20, "latin1");
  b.write("acsp", 36, "latin1"); b.writeUInt32BE(0, 128);
  return b;
}
const iccp = (space) => ({ type: "iCCP", data: Buffer.concat([Buffer.from("icc\0\0", "latin1"), zlib.deflateSync(tinyIcc(space))]) });
const gama = { type: "gAMA", data: Buffer.from([0, 0, 0xb1, 0x8f]) }; // 1/2.2
const srgb = { type: "sRGB", data: Buffer.from([0]) };
const CHECKER = "takumi-pdf/tests/images/checker.png";

/** A raw 8-bit PNG from pixel rows (colour type 2 / 6 / 0 / 4), optionally Adam7-free "interlace" flag off. */
function rawPng(w, h, colorType, pixels, extra = []) {
  const ch = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType];
  const rows = Buffer.alloc(h * (1 + w * ch));
  for (let y = 0; y < h; y++) { rows[y * (1 + w * ch)] = 0; Buffer.from(pixels.slice(y * w * ch, (y + 1) * w * ch)).copy(rows, y * (1 + w * ch) + 1); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = colorType;
  return pngFrom([{ type: "IHDR", data: ihdr }, ...extra, { type: "IDAT", data: zlib.deflateSync(rows) }, { type: "IEND", data: Buffer.alloc(0) }]);
}
const opaqueRgba = rawPng(2, 2, 6, [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255]);
const alphaRgba = rawPng(2, 2, 6, [255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 0, 255, 255, 0, 255]);
/** One-frame APNG: acTL + fcTL before IDAT. */
function apng() {
  const chunks = pngChunks(alphaRgba);
  const actl = Buffer.alloc(8); actl.writeUInt32BE(1, 0);
  const fctl = Buffer.alloc(26); fctl.writeUInt32BE(0, 0); fctl.writeUInt32BE(2, 4); fctl.writeUInt32BE(2, 8); fctl.writeUInt16BE(1, 20); fctl.writeUInt16BE(10, 22);
  return pngFrom([chunks[0], { type: "acTL", data: actl }, { type: "fcTL", data: fctl }, ...chunks.slice(1)]);
}
/** Indexed PNG with a tRNS chunk. */
function indexedTrns() {
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(2, 0); ihdr.writeUInt32BE(2, 4); ihdr[8] = 8; ihdr[9] = 3;
  return pngFrom([{ type: "IHDR", data: ihdr }, { type: "PLTE", data: Buffer.from([255, 0, 0, 0, 255, 0, 0, 0, 255]) }, { type: "tRNS", data: Buffer.from([255, 128, 0]) },
    { type: "IDAT", data: zlib.deflateSync(Buffer.from([0, 0, 1, 0, 2, 0])) }, { type: "IEND", data: Buffer.alloc(0) }]);
}
/** 2x2 24-bit BMP. */
function bmp() {
  const b = Buffer.alloc(54 + 16);
  b.write("BM", 0, "latin1"); b.writeUInt32LE(70, 2); b.writeUInt32LE(54, 10); b.writeUInt32LE(40, 14); b.writeInt32LE(2, 18); b.writeInt32LE(2, 22); b.writeUInt16LE(1, 26); b.writeUInt16LE(24, 28); b.writeUInt32LE(16, 34);
  Buffer.from([0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 0, 255, 255, 255, 0, 0]).copy(b, 54);
  return b;
}
/** An ICO holding one PNG. */
function ico(png) {
  const h = Buffer.alloc(22);
  h.writeUInt16LE(1, 2); h.writeUInt16LE(1, 4); h[6] = 2; h[7] = 2; h.writeUInt16LE(1, 10); h.writeUInt16LE(32, 12); h.writeUInt32LE(png.length, 14); h.writeUInt32LE(22, 18);
  return Buffer.concat([h, png]);
}
/** A JPEG with every APP1 removed and an Exif APP1 carrying `orientation` inserted after SOI. */
function jpegOrientation(rel, orientation) {
  const src = fileBytes(rel);
  const segs = []; let p = 2;
  while (p < src.length && src[p] === 0xff && src[p + 1] !== 0xda) { const len = src.readUInt16BE(p + 2); if (src[p + 1] !== 0xe1) segs.push(src.subarray(p, p + 2 + len)); p += 2 + len; }
  const tiff = Buffer.alloc(26);
  tiff.write("MM", 0, "latin1"); tiff.writeUInt16BE(42, 2); tiff.writeUInt32BE(8, 4); tiff.writeUInt16BE(1, 8);
  tiff.writeUInt16BE(0x0112, 10); tiff.writeUInt16BE(3, 12); tiff.writeUInt32BE(1, 14); tiff.writeUInt16BE(orientation, 18);
  const body = Buffer.concat([Buffer.from("Exif\0\0", "latin1"), tiff]);
  const app1 = Buffer.alloc(4); app1[0] = 0xff; app1[1] = 0xe1; app1.writeUInt16BE(body.length + 2, 2);
  return Buffer.concat([src.subarray(0, 2), app1, body, ...segs, src.subarray(p)]);
}
/** An 8x8 baseline JPEG of `n` components (4: Adobe CMYK, transform 0 or 2), every block DC 0 (mid grey). */
function flatJpeg(n, adobeTransform) {
  const seg = (marker, body) => { const h = Buffer.alloc(4); h[0] = 0xff; h[1] = marker; h.writeUInt16BE(body.length + 2, 2); return Buffer.concat([h, Buffer.from(body)]); };
  const parts = [Buffer.from([0xff, 0xd8])];
  if (adobeTransform !== undefined) parts.push(seg(0xee, [0x41, 0x64, 0x6f, 0x62, 0x65, 0, 100, 0, 0, 0, 0, adobeTransform]));
  parts.push(seg(0xdb, [0, ...new Array(64).fill(16)]));
  const comps = []; for (let i = 1; i <= n; i++) comps.push(i, 0x11, 0);
  parts.push(seg(0xc0, [8, 0, 8, 0, 8, n, ...comps]));
  // one-symbol Huffman tables: DC category 0 and AC end-of-block, each the 1-bit code "0"
  parts.push(seg(0xc4, [0x00, 1, ...new Array(15).fill(0), 0x00]));
  parts.push(seg(0xc4, [0x10, 1, ...new Array(15).fill(0), 0x00]));
  const sc = []; for (let i = 1; i <= n; i++) sc.push(i, 0x00);
  parts.push(seg(0xda, [n, ...sc, 0, 63, 0]));
  // n blocks x 2 bits "00", padded with ones
  const bits = n * 2; const bytes = Math.ceil(bits / 8); const data = Buffer.alloc(bytes);
  for (let i = bits; i < bytes * 8; i++) data[i >> 3] |= 0x80 >> (i & 7);
  parts.push(data, Buffer.from([0xff, 0xd9]));
  return Buffer.concat(parts);
}

// ------------------------------------------------------------------------------------------------ PNG

cases("images.png", "PNG images", [
  ["rgb8", img(dataUri(CHECKER))],
  ["rgb8-suite", img(suite("rgb8"))],
  ["rgba8", img(suite("rgba8"))],
  ["rgba8-opaque", img(b64(opaqueRgba, "image/png"))],
  ["rgba8-alpha", img(b64(alphaRgba, "image/png"))],
  ["rgb16", img(suite("rgb16"))],
  ["rgba16", img(suite("rgba16"))],
  ["gray8", img(suite("g8"))],
  ["gray16", img(suite("g16"))],
  ["gray1", img(suite("g1"))],
  ["gray2", img(suite("g2"))],
  ["gray4", img(suite("g4"))],
  ["gray-alpha8", img(suite("ga8"))],
  ["gray-alpha16", img(suite("ga16"))],
  ["indexed8", img(suite("p8"))],
  ["indexed4", img(suite("p4"))],
  ["indexed2", img(suite("p2"))],
  ["indexed1", img(suite("p1"))],
  ["indexed-checker", img(dataUri("takumi-pdf/tests/images/checker-indexed.png"))],
  ["indexed-trns", img(b64(indexedTrns(), "image/png"))],
  ["rgb8-colorkey", img(suite("rgb8key"))],
  ["gray8-colorkey", img(suite("g8key"))],
  ["gray16-colorkey", img(suite("g16key"))],
  ["interlaced-rgb8", img(suite("rgb8_i"))],
  ["interlaced-rgba8", img(suite("rgba8_i"))],
  ["interlaced-gray16", img(suite("g16_i"))],
  ["interlaced-indexed", img(suite("p8_i"))],
  ["icc-profile", img(b64(pngWith(CHECKER, [iccp("RGB ")]), "image/png"))],
  ["icc-profile-rgba", img(b64(pngFrom([pngChunks(alphaRgba)[0], iccp("RGB "), ...pngChunks(alphaRgba).slice(1)]), "image/png"))],
  ["icc-profile-gray-on-rgb", img(b64(pngWith(CHECKER, [iccp("GRAY")]), "image/png"))],
  ["gamma", img(b64(pngWith(CHECKER, [gama]), "image/png"))],
  ["gamma-rgba", img(b64(pngFrom([pngChunks(alphaRgba)[0], gama, ...pngChunks(alphaRgba).slice(1)]), "image/png"))],
  ["srgb-chunk", img(b64(pngWith(CHECKER, [srgb, gama]), "image/png"))],
  ["apng", img(b64(apng(), "image/png"))],
  ["real-rgba", img(dataUri("assets/images/yeecord.png"))],
  ["truncated", img(b64(fileBytes(CHECKER).subarray(0, 60), "image/png"))],
  ["bad-crc", img(b64((() => { const b = Buffer.from(fileBytes(CHECKER)); b[b.length - 14] ^= 0xff; return b; })(), "image/png"))],
]);

// ------------------------------------------------------------------------------------------------ JPEG

cases("images.jpeg", "JPEG images", [
  ["baseline", img(dataUri("takumi-pdf/tests/images/checker.jpg"))],
  ["baseline-420", img(codec("jpeg_b420.jpg"))],
  ["baseline-444", img(codec("jpeg_b444.jpg"))],
  ["baseline-411", img(codec("jpeg_b411.jpg"))],
  ["restart-markers", img(codec("jpeg_b420r.jpg"))],
  ["grayscale", img(codec("jpeg_gray.jpg"))],
  ["progressive", img(codec("jpeg_p444.jpg"))],
  ["progressive-420", img(codec("jpeg_p420.jpg"))],
  ["progressive-gray", img(codec("jpeg_pgray.jpg"))],
  ["mozjpeg", img(codec("jpeg_mozb420.jpg"))],
  ["cmyk-adobe", img(b64(flatJpeg(4, 0), "image/jpeg"))],
  ["ycck-adobe", img(b64(flatJpeg(4, 2), "image/jpeg"))],
  ["cmyk-no-adobe", img(b64(flatJpeg(4), "image/jpeg"))],
  ["rgb-adobe-transform0", img(b64(flatJpeg(3, 0), "image/jpeg"))],
  ["gray-flat", img(b64(flatJpeg(1), "image/jpeg"))],
  ["exif-orientation-6", img(b64(jpegOrientation("takumi-pdf/tests/images/checker.jpg", 6), "image/jpeg"), "width:40px")],
  ["exif-orientation-3", img(b64(jpegOrientation("takumi-pdf/tests/images/checker.jpg", 3), "image/jpeg"))],
  ["exif-orientation-none", img(b64(jpegOrientation("takumi-pdf/tests/images/checker.jpg", 6), "image/jpeg"), "width:40px;image-orientation:none")],
  ["exif-orientation-nonsquare", img(b64(jpegOrientation("src/codec/testdata/jpeg_b420.jpg", 6), "image/jpeg"), "width:40px")],
  ["photo", img(dataUri("assets/images/luma-cover-0dfbf65d-0f58-4941-947c-d84a5b131dc0.jpeg"), "width:60px")],
  ["truncated", img(b64(fileBytes("takumi-pdf/tests/images/checker.jpg").subarray(0, 300), "image/jpeg"))],
]);

// ------------------------------------------------------------------------------------------------ other formats

cases("images.webp", "WebP images", [
  ["lossless", img(dataUri("takumi-pdf/tests/images/checker.webp"))],
  ["lossy", img(codec("vp8_q75.webp"))],
  ["lossy-alpha", img(codec("vp8_alpha_ll.webp"))],
  ["lossy-alpha-raw", img(codec("vp8_alpha_raw.webp"))],
  ["lossless-palette", img(codec("webp_lib_pal.webp"))],
  ["lossless-mix", img(codec("webp_lib_mix.webp"))],
  ["animated-lossless", img(codec("anim_ll.webp"))],
  ["animated-lossy", img(codec("anim_lossy.webp"))],
  ["animated-from-gif", img(codec("anim_gif.webp"))],
]);

cases("images.gif", "GIF images", [
  ["static", img(codec("gif_takumi.gif"))],
  ["animated", img(codec("anim.gif"))],
]);

cases("images.other-formats", "BMP, ICO, AVIF, unknown bytes", [
  ["bmp", img(b64(bmp(), "image/bmp"))],
  ["ico", img(b64(ico(opaqueRgba), "image/x-icon"))],
  ["avif-header-only", img(b64(Buffer.concat([Buffer.from([0, 0, 0, 0x1c]), Buffer.from("ftypavif\0\0\0\0avifmif1miaf", "latin1")]), "image/avif"))],
  ["tiff-header-only", img(b64(Buffer.from("II*\0\x08\0\0\0\0\0", "latin1"), "image/tiff"))],
  ["garbage", img(b64(Buffer.from("not an image at all"), "image/png"))],
  ["empty-src", `<img src="" style="margin:10px;width:40px;height:40px;background:#eee">`],
  ["missing-url", `<img src="https://example.invalid/x.png" style="margin:10px;width:40px;height:40px;background:#eee">`],
  ["missing-url-alt", `<img src="https://example.invalid/x.png" alt="Alt text" style="margin:10px;width:80px;height:40px;font:12px Inter">`],
  ["no-src", `<img alt="Alt" style="margin:10px;width:40px;height:40px;background:#eee;font:12px Inter">`],
]);

cases("images.root-img", "an <img> that is the only top-level element keeps its intrinsic size", [
  ["png", `<img src="${dataUri(CHECKER)}">`],
  ["png-margin", `<img src="${dataUri(CHECKER)}" style="margin:10px">`],
  ["svg", `<img src="${svgUri('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><rect width="40" height="40" fill="red"/></svg>')}">`],
]);

// ------------------------------------------------------------------------------------------------ sources

probeAs("images.option.images-list", "the `images` option (src -> bytes)", async (t) => {
  const data = new Uint8Array(fileBytes(CHECKER));
  await cmp(t, "png", `<img src="logo.png" style="margin:10px;width:40px;height:40px"><div style="width:60px;height:30px;background:url(logo.png)"></div>`, { ...vp(), images: [{ src: "logo.png", data }] });
  await cmp(t, "jpeg", `<img src="https://cdn.example/a.jpg" style="margin:10px;width:40px;height:40px">`, { ...vp(), images: [{ src: "https://cdn.example/a.jpg", data: new Uint8Array(fileBytes("takumi-pdf/tests/images/checker.jpg")) }] });
  await cmp(t, "svg", `<img src="a.svg" style="margin:10px;width:40px;height:40px">`, { ...vp(), images: [{ src: "a.svg", data: new TextEncoder().encode(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" fill="red"/></svg>`) }] });
});

probeAs("images.node.raw-bitmap", "an image node with raw RGBA pixels", async (t) => {
  const px = { width: 2, height: 2, data: new Uint8Array([255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 128, 255, 0, 0, 0]) };
  await cmp(t, "", { type: "image", src: px, style: { width: 40, height: 40 } }, vp(60, 60));
});

probeAs("images.node.bytes", "an image node with encoded bytes", async (t) => {
  await cmp(t, "png", { type: "image", src: new Uint8Array(fileBytes(CHECKER)), style: { width: 40, height: 40 } }, vp(60, 60));
  await cmp(t, "jpeg", { type: "image", src: new Uint8Array(fileBytes("takumi-pdf/tests/images/checker.jpg")), style: { width: 40, height: 40 } }, vp(60, 60));
});

// ------------------------------------------------------------------------------------------------ reuse, resampling

const PNG = dataUri(CHECKER);
const JPG = dataUri("takumi-pdf/tests/images/checker.jpg");
const BIG = dataUri("src/codec/testdata/fuma.jpg");
const countImages = (r) => r.subtyped("Image").length;

probeAs("images.dedup", "the same image used several times is one XObject", async (t) => {
  const list = [
    ["img-x3", img(PNG) + img(PNG) + img(PNG, "width:20px;height:60px")],
    ["img-and-background", img(PNG) + `<div style="width:60px;height:30px;background:url(${PNG})"></div>`],
    ["jpeg-x3", img(JPG) + img(JPG) + img(JPG)],
    ["rgba-x2", img(b64(alphaRgba, "image/png")) + img(b64(alphaRgba, "image/png"))],
    ["same-pixels-other-src", img(PNG) + img(b64(Buffer.concat([fileBytes(CHECKER)]), "image/png;x=1"))],
    ["filtered-and-plain", img(PNG) + img(PNG, "width:40px;height:40px;filter:invert(1)") + img(PNG, "width:40px;height:40px;filter:invert(1)")],
    ["two-pages", `<div style="height:200px">${img(PNG)}</div><div style="break-before:page">${img(PNG)}</div>`, { width: 200, height: 220 }],
  ];
  for (const [id, html, page] of list) {
    const r = await cmp(t, id, html, page ? page : vp(260, 120), undefined, { quiet: true });
    if (r.ref && !r.bm.error && !r.ref.error) {
      t.same(id + ": image XObjects in the file", countImages(r.bm), countImages(r.ref));
      t.note(`${id}: takumi writes ${countImages(r.ref)} image object(s), bm ${countImages(r.bm)}`);
    }
  }
});

probeAs("images.resample", "an image is embedded at its own resolution whatever its displayed size", async (t) => {
  for (const [id, html] of [
    ["big-jpeg-small-box", img(BIG, "width:20px;height:20px")],
    ["big-jpeg-filtered", img(dataUri("src/codec/testdata/jpeg_b420.jpg"), "width:10px;height:10px;filter:grayscale(1)")],
    ["png-upscaled", img(PNG, "width:200px;height:100px")],
    ["png-downscaled", img(dataUri("assets/images/yeecord.png"), "width:8px;height:8px")],
    ["background-cover-big", `<div style="width:30px;height:30px;background:url(${BIG}) center/cover"></div>`],
  ]) {
    const r = await cmp(t, id, html, vp(260, 120));
    if (r.ref && !r.bm.error && !r.ref.error) {
      const dims = (d) => d.subtyped("Image").map((o) => `${o.dict.Width}x${o.dict.Height}`).sort();
      t.same(id + ": embedded pixel sizes", dims(r.bm), dims(r.ref));
    }
  }
});

// ------------------------------------------------------------------------------------------------ placement

const RECT = dataUri("src/codec/testdata/jpeg_b420.jpg");
cases("images.object-fit", "object-fit / object-position", [
  ["fill", img(RECT, "width:80px;height:30px;object-fit:fill")],
  ["contain", img(RECT, "width:80px;height:30px;object-fit:contain")],
  ["cover", img(RECT, "width:80px;height:30px;object-fit:cover")],
  ["none", img(RECT, "width:20px;height:20px;object-fit:none")],
  ["scale-down", img(RECT, "width:80px;height:30px;object-fit:scale-down")],
  ["scale-down-small", img(PNG, "width:80px;height:30px;object-fit:scale-down")],
  ["position", img(RECT, "width:80px;height:30px;object-fit:contain;object-position:left top")],
  ["position-percent", img(RECT, "width:80px;height:30px;object-fit:cover;object-position:20% 80%")],
  ["position-px", img(RECT, "width:20px;height:20px;object-fit:none;object-position:-5px 3px")],
  ["cover-radius", img(RECT, "width:80px;height:30px;object-fit:cover;border-radius:10px")],
  ["padding-border", img(RECT, "width:60px;height:30px;padding:5px;border:3px solid #333;background:#ff0")],
  ["aspect-ratio-auto-height", img(RECT, "width:60px")],
  ["intrinsic-size", `<div><img src="${PNG}" style="margin:10px"></div>`],
  ["width-height-attrs", `<img src="${PNG}" width="30" height="20" style="margin:10px">`],
  ["svg-contain", img(svgUri(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 20"><rect width="10" height="20" fill="red"/></svg>`), "width:80px;height:30px;object-fit:contain")],
  ["svg-cover", img(svgUri(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 20"><rect width="10" height="20" fill="red"/></svg>`), "width:80px;height:30px;object-fit:cover")],
]);

cases("images.image-rendering", "image-rendering (pixelated is a known bug owned elsewhere: recorded only)", [
  ["auto", img(PNG, "width:80px;height:80px")],
  ["pixelated", img(PNG, "width:80px;height:80px;image-rendering:pixelated")],
  ["crisp-edges", img(PNG, "width:80px;height:80px;image-rendering:crisp-edges")],
  ["smooth", img(PNG, "width:80px;height:80px;image-rendering:smooth")],
  ["pixelated-jpeg", img(JPG, "width:80px;height:80px;image-rendering:pixelated")],
  ["pixelated-rgba", img(b64(alphaRgba, "image/png"), "width:80px;height:80px;image-rendering:pixelated")],
  ["pixelated-background", `<div style="width:80px;height:40px;background:url(${PNG}) 0 0/40px 40px;image-rendering:pixelated"></div>`],
]);

// ------------------------------------------------------------------------------------------------ SVG

const svg = (body, attrs = `width="40" height="40" viewBox="0 0 40 40"`) => `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" ${attrs}>${body}</svg>`;
const svgImg = (body, attrs, style = "") => `<div style="margin:10px"><img src="${svgUri(svg(body, attrs))}" style="${style}"></div>`;
const SVG_FEATURES = [
  ["shapes", `<rect x="2" y="2" width="16" height="10" fill="#c00"/><circle cx="30" cy="10" r="6" fill="#0a0"/><ellipse cx="10" cy="30" rx="8" ry="4" fill="#00c"/><polygon points="24,24 38,24 31,38" fill="#fa0"/><polyline points="2,20 10,16 18,20" fill="none" stroke="#000"/>`],
  ["line", `<line x1="2" y1="2" x2="38" y2="38" stroke="#c00" stroke-width="3"/>`],
  ["path-arcs", `<path d="M5 20 A15 15 0 0 1 35 20 Q20 40 5 20 Z" fill="#06c"/>`],
  ["rounded-rect", `<rect x="4" y="4" width="32" height="20" rx="6" ry="3" fill="#06c"/>`],
  ["stroke", `<path d="M5 5 L35 5 L20 35 Z" fill="none" stroke="#c00" stroke-width="4" stroke-linejoin="round" stroke-linecap="square" stroke-miterlimit="2"/>`],
  ["stroke-dash", `<circle cx="20" cy="20" r="14" fill="none" stroke="#c00" stroke-width="2" stroke-dasharray="4 2" stroke-dashoffset="1"/>`],
  ["fill-rule", `<path fill-rule="evenodd" d="M0 0H40V40H0Z M10 10H30V30H10Z" fill="#06c"/>`],
  ["opacity", `<g opacity=".5"><rect width="30" height="30" fill="#c00"/><rect x="10" y="10" width="30" height="30" fill="#00c"/></g><rect width="10" height="10" fill="#0a0" fill-opacity=".3" stroke="#000" stroke-opacity=".6"/>`],
  ["transform", `<g transform="translate(20 20) rotate(30) scale(.5)"><rect x="-10" y="-10" width="20" height="20" fill="#c00"/></g>`],
  ["linear-gradient", `<defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><rect width="40" height="40" fill="url(#g)"/>`],
  ["linear-gradient-user-space", `<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="5" y1="5" x2="35" y2="35" gradientTransform="rotate(10)"><stop offset="0" stop-color="#f00"/><stop offset=".5" stop-color="#0f0" stop-opacity=".5"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><rect width="40" height="40" fill="url(#g)"/>`],
  ["linear-gradient-spread", `<defs><linearGradient id="g" x1="0" x2=".25" spreadMethod="reflect"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient><linearGradient id="h" x1="0" x2=".25" spreadMethod="repeat"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><rect width="40" height="20" fill="url(#g)"/><rect y="20" width="40" height="20" fill="url(#h)"/>`],
  ["radial-gradient", `<defs><radialGradient id="g" cx=".5" cy=".5" r=".5" fx=".3" fy=".3"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#00f"/></radialGradient></defs><circle cx="20" cy="20" r="18" fill="url(#g)"/>`],
  ["gradient-href", `<defs><linearGradient id="a"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient><linearGradient id="g" xlink:href="#a" x1="0" y1="0" x2="0" y2="1"/></defs><rect width="40" height="40" fill="url(#g)"/>`],
  ["gradient-stroke", `<defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><rect x="5" y="5" width="30" height="30" fill="none" stroke="url(#g)" stroke-width="4"/>`],
  ["pattern", `<defs><pattern id="p" width="8" height="8" patternUnits="userSpaceOnUse"><circle cx="4" cy="4" r="2" fill="#c00"/></pattern></defs><rect width="40" height="40" fill="url(#p)"/>`],
  ["clip-path", `<defs><clipPath id="c"><circle cx="20" cy="20" r="12"/></clipPath></defs><rect width="40" height="40" fill="#06c" clip-path="url(#c)"/>`],
  ["mask", `<defs><mask id="m"><rect width="40" height="40" fill="#fff"/><circle cx="20" cy="20" r="10" fill="#000"/></mask></defs><rect width="40" height="40" fill="#06c" mask="url(#m)"/>`],
  ["mask-alpha", `<defs><mask id="m" mask-type="alpha"><circle cx="20" cy="20" r="10" fill="#000" fill-opacity=".5"/></mask></defs><rect width="40" height="40" fill="#06c" mask="url(#m)"/>`],
  ["filter-blur", `<defs><filter id="f"><feGaussianBlur stdDeviation="2"/></filter></defs><rect x="8" y="8" width="24" height="24" fill="#06c" filter="url(#f)"/>`],
  ["filter-drop-shadow", `<defs><filter id="f"><feDropShadow dx="2" dy="2" stdDeviation="1"/></filter></defs><rect x="8" y="8" width="20" height="20" fill="#06c" filter="url(#f)"/>`],
  ["blend-mode", `<rect width="30" height="30" fill="#fc0"/><rect x="10" y="10" width="30" height="30" fill="#06c" style="mix-blend-mode:multiply"/>`],
  ["isolation", `<g style="isolation:isolate"><rect width="30" height="30" fill="#fc0"/></g>`],
  ["use", `<defs><rect id="r" width="10" height="10" fill="#c00"/></defs><use href="#r" x="5" y="5"/><use xlink:href="#r" x="20" y="20" fill="#00c"/>`],
  ["symbol", `<defs><symbol id="s" viewBox="0 0 10 10"><circle cx="5" cy="5" r="5" fill="#c00"/></symbol></defs><use href="#s" x="5" y="5" width="20" height="20"/>`],
  ["nested-svg", `<svg x="10" y="10" width="20" height="20" viewBox="0 0 10 10"><rect width="10" height="10" fill="#c00"/></svg>`],
  ["text", `<text x="2" y="20" font-family="Inter" font-size="12" fill="#c00">Svg</text>`],
  ["text-tspan-anchor", `<text x="20" y="20" font-family="Inter" font-size="10" text-anchor="middle">a<tspan fill="red" dy="5">b</tspan></text>`],
  ["text-x-list", `<text x="2 14 28" y="20" font-family="Inter" font-size="10">abc</text>`],
  ["text-dx-dy-list", `<text x="2" y="20" dx="0 3 -2" dy="0 -4 2" font-family="Inter" font-size="10">abc</text>`],
  ["text-rotate-list", `<text x="2" y="20" rotate="0 30 -20" font-family="Inter" font-size="10">abcd</text>`],
  ["text-nested-position-list", `<text x="2 12 22 32" y="20" font-family="Inter" font-size="10">a<tspan x="15" fill="red">bc</tspan>d</text>`],
  ["text-unicode-position-list", `<text x="2 14 28" y="20" font-family="Inter" font-size="10">éab</text>`],
  ["text-path-line", `<defs><path id="p" d="M2 20 L38 20"/></defs><text font-family="Inter" font-size="10"><textPath href="#p">abc</textPath></text>`],
  ["text-path-curve", `<defs><path id="p" d="M2 25 Q20 0 38 25"/></defs><text font-family="Inter" font-size="10"><textPath href="#p">abc</textPath></text>`],
  ["text-path-offset", `<defs><path id="p" d="M2 20 L38 20"/></defs><text font-family="Inter" font-size="10"><textPath href="#p" startOffset="25%">abc</textPath></text>`],
  ["text-path-tspan-x", `<defs><path id="p" d="M2 20 L38 20"/></defs><text font-family="Inter" font-size="10"><textPath href="#p"><tspan>a</tspan><tspan x="20">b</tspan></textPath></text>`],
  ["text-path-outside", `<defs><path id="p" d="M2 20 L38 20"/></defs><text dx="-10 20" font-family="Inter" font-size="10"><textPath href="#p">abc</textPath></text>`],
  ["text-decoration-underline", `<text x="2" y="20" font-family="Inter" font-size="10" text-decoration="underline">abc</text>`],
  ["text-decoration-all", `<text x="2" y="20" font-family="Inter" font-size="10" text-decoration="underline overline line-through" fill="blue">abc</text>`],
  ["text-decoration-parent-paint", `<text x="2" y="20" font-family="Inter" font-size="10" text-decoration="underline" fill="blue">a<tspan fill="red">bc</tspan></text>`],
  ["text-decoration-rotated", `<text x="2" y="20" rotate="0 30 -20" font-family="Inter" font-size="10" text-decoration="underline">abc</text>`],
  ["text-decoration-path", `<defs><path id="p" d="M2 25 Q20 0 38 25"/></defs><text font-family="Inter" font-size="10" text-decoration="underline"><textPath href="#p">abc</textPath></text>`],
  ["embedded-png", `<image href="${PNG}" x="4" y="4" width="32" height="32"/>`],
  ["embedded-jpeg", `<image xlink:href="${JPG}" x="4" y="4" width="32" height="32" preserveAspectRatio="none"/>`],
  ["embedded-svg", `<image href="${svgUri(svg(`<circle cx="20" cy="20" r="15" fill="#0a0"/>`))}" x="4" y="4" width="32" height="32"/>`],
  ["marker", `<defs><marker id="m" markerWidth="6" markerHeight="6" refX="3" refY="3" orient="auto"><circle cx="3" cy="3" r="3" fill="#c00"/></marker></defs><path d="M5 20 L35 20" stroke="#000" marker-end="url(#m)"/>`],
  ["current-color", `<rect width="40" height="40" fill="currentColor"/><circle cx="20" cy="20" r="8" stroke="currentColor" fill="#fff"/>`],
  ["style-element", `<style>.a{fill:#c00}rect{stroke:#000}</style><rect class="a" x="5" y="5" width="30" height="30"/>`],
  ["style-attr", `<rect style="fill:#c00;stroke:#00c;stroke-width:3" x="5" y="5" width="30" height="30"/>`],
  ["visibility-display", `<rect width="20" height="20" fill="#c00" visibility="hidden"/><rect x="20" width="20" height="20" fill="#0a0" display="none"/><rect y="20" width="20" height="20" fill="#00c"/>`],
  ["paint-order", `<rect x="8" y="8" width="24" height="24" fill="#fc0" stroke="#06c" stroke-width="6" paint-order="stroke"/>`],
  ["vector-effect", `<g transform="scale(2)"><rect x="2" y="2" width="12" height="12" fill="none" stroke="#06c" stroke-width="2" vector-effect="non-scaling-stroke"/></g>`],
  ["switch", `<switch><rect width="20" height="20" fill="#c00"/><rect width="40" height="40" fill="#00c"/></switch>`],
  ["a-link", `<a href="https://example.com"><rect width="20" height="20" fill="#c00"/></a>`],
  ["color-formats", `<rect width="10" height="10" fill="rgb(10 20 30 / 50%)"/><rect x="10" width="10" height="10" fill="hsl(120,50%,50%)"/><rect x="20" width="10" height="10" fill="rgba(255,0,0,.5)"/><rect x="30" width="10" height="10" fill="oklch(0.7 0.2 150)"/>`],
  ["empty", ``],
];
cases("images.svg-img", "SVG in <img>: vector operators", SVG_FEATURES.map(([id, body]) => [id, svgImg(body, undefined, "color:#909")]), vp(80, 80));

cases("images.svg-sizing", "SVG image sizing", [
  ["viewbox-only", svgImg(`<rect width="10" height="10" fill="#c00"/>`, `viewBox="0 0 10 10"`, "width:40px;height:20px")],
  ["no-viewbox", svgImg(`<rect width="10" height="10" fill="#c00"/>`, `width="20" height="10"`, "width:40px;height:40px")],
  ["no-size-no-viewbox", svgImg(`<rect width="10" height="10" fill="#c00"/>`, ``, "")],
  ["par-none", svgImg(`<circle cx="5" cy="5" r="5" fill="#c00"/>`, `viewBox="0 0 10 10" preserveAspectRatio="none"`, "width:60px;height:20px")],
  ["par-xminymin-slice", svgImg(`<circle cx="5" cy="5" r="5" fill="#c00"/>`, `viewBox="0 0 10 10" preserveAspectRatio="xMinYMin slice"`, "width:60px;height:20px")],
  ["viewbox-offset", svgImg(`<circle cx="5" cy="5" r="5" fill="#c00"/>`, `viewBox="-5 -5 20 20" width="40" height="40"`, "")],
  ["percent-size", svgImg(`<rect width="10" height="10" fill="#c00"/>`, `width="100%" height="100%" viewBox="0 0 10 10"`, "width:30px;height:30px")],
  ["overflow-content", svgImg(`<circle cx="0" cy="0" r="30" fill="#c00"/>`, `width="40" height="40"`, "")],
  ["upscaled", svgImg(`<circle cx="5" cy="5" r="5" fill="#c00"/>`, `width="10" height="10"`, "width:60px;height:60px")],
  ["real-file", `<div><img src="${dataUri("assets/images/takumi.svg")}" style="margin:10px;width:60px"></div>`],
  ["real-file-sticker", `<div><img src="${dataUri("assets/images/sticker.svg")}" style="margin:10px;width:60px"></div>`],
  ["real-file-avatar", `<div><img src="${dataUri("assets/images/avatar.svg")}" style="margin:10px;width:60px"></div>`],
  ["real-file-luma", `<img src="${dataUri("assets/images/luma.svg")}" style="margin:10px;width:60px">`],
  ["invalid-xml", `<img src="${svgUri("<svg xmlns='http://www.w3.org/2000/svg'><rect")}" style="margin:10px;width:40px;height:40px">`],
], vp(100, 80));

const inlineSvg = (body, attrs = `width="40" height="40" viewBox="0 0 40 40"`, style = "") => `<div style="margin:10px;color:#909;${style}"><svg xmlns="http://www.w3.org/2000/svg" ${attrs}>${body}</svg></div>`;
cases("images.svg-inline", "inline <svg> element", [
  ["shapes", inlineSvg(SVG_FEATURES[0][1])],
  ["current-color", inlineSvg(`<rect width="40" height="40" fill="currentColor"/>`)],
  ["css-fill", `<style>svg rect{fill:#0a0}</style>` + inlineSvg(`<rect width="40" height="40"/>`)],
  ["css-ancestor-child", `<style>.outer > svg rect.a{fill:#0a0}</style><div class="outer"><svg width="40" height="40"><rect class="a" width="40" height="40"/></svg></div>`],
  ["css-inline-precedence", `<style>svg rect{fill:red}</style>` + inlineSvg(`<rect width="40" height="40" style="fill:#0a0"/>`)],
  ["css-important", `<style>svg rect{fill:#0a0!important}</style>` + inlineSvg(`<rect width="40" height="40" style="fill:red"/>`)],
  ["css-internal-specificity", `<style>svg rect{fill:red}</style>` + inlineSvg(`<style>#r{fill:#0a0}</style><rect id="r" width="40" height="40"/>`)],
  ["css-image-isolation", `<style>svg rect{fill:#0a0!important}</style>` + svgImg(`<rect width="40" height="40" fill="red"/>`)],
  ["css-size", inlineSvg(`<rect width="40" height="40" fill="#c00"/>`, `viewBox="0 0 40 40" style="width:60px;height:20px"`)],
  ["gradient", inlineSvg(SVG_FEATURES.find((f) => f[0] === "linear-gradient")[1])],
  ["text", inlineSvg(`<text x="2" y="20" font-family="Inter" font-size="12">Svg</text>`)],
  ["mask", inlineSvg(SVG_FEATURES.find((f) => f[0] === "mask")[1])],
  ["filter", inlineSvg(SVG_FEATURES.find((f) => f[0] === "filter-blur")[1])],
  ["use", inlineSvg(SVG_FEATURES.find((f) => f[0] === "use")[1])],
  ["no-xmlns", `<div style="margin:10px"><svg width="40" height="40"><circle cx="20" cy="20" r="15" fill="#c00"/></svg></div>`],
  ["in-text", `<p style="margin:10px;font:14px Inter">a <svg width="12" height="12" viewBox="0 0 12 12"><circle cx="6" cy="6" r="5" fill="#c00"/></svg> b</p>`],
  ["with-css-filter", inlineSvg(`<rect width="40" height="40" fill="#c00"/>`, undefined, "filter:grayscale(1)")],
  ["with-opacity", inlineSvg(`<rect width="40" height="40" fill="#c00"/>`, undefined, "opacity:.5")],
], vp(100, 80));

const bgSvg = (body, css = "", attrs) => `<div style="margin:10px;width:60px;height:40px;background:url(${svgUri(svg(body, attrs))}) ${css}"></div>`;
cases("images.svg-background", "SVG as background-image / mask / border-image", [
  ["no-repeat", bgSvg(SVG_FEATURES[0][1], "no-repeat")],
  ["repeat", bgSvg(`<circle cx="20" cy="20" r="15" fill="#c00"/>`, "0 0/20px 20px")],
  ["cover", bgSvg(`<circle cx="20" cy="20" r="15" fill="#c00"/>`, "center/cover no-repeat")],
  ["contain-viewbox-only", bgSvg(`<circle cx="5" cy="5" r="5" fill="#c00"/>`, "center/contain no-repeat", `viewBox="0 0 10 10"`)],
  ["gradient-fill", bgSvg(SVG_FEATURES.find((f) => f[0] === "linear-gradient")[1], "no-repeat")],
  ["with-mask", bgSvg(SVG_FEATURES.find((f) => f[0] === "mask")[1], "no-repeat")],
  ["with-filter", bgSvg(SVG_FEATURES.find((f) => f[0] === "filter-blur")[1], "no-repeat")],
  ["css-filter-on-box", `<div style="margin:10px;width:60px;height:40px;filter:invert(1);background:url(${svgUri(svg(`<circle cx="20" cy="20" r="15" fill="#c00"/>`))}) no-repeat"></div>`],
  ["as-mask-image", `<div style="margin:10px;width:60px;height:40px;background:#06c;mask-image:url(${svgUri(svg(`<circle cx="20" cy="20" r="15"/>`))});mask-repeat:no-repeat"></div>`],
  ["as-list-style-image", `<ul style="font:14px Inter;list-style-image:url(${svgUri(svg(`<circle cx="20" cy="20" r="15" fill="#c00"/>`, `width="8" height="8" viewBox="0 0 40 40"`))})"><li>a</li></ul>`],
], vp(100, 80));

// ------------------------------------------------------------------------------------------------ colour spaces of what is written

probeAs("images.colorspace.device", "colour spaces used for device colours and images (no PDF/A)", async (t) => {
  const r = await cmp(t, "", `<div style="margin:10px;width:40px;height:20px;background:#808080;border:2px solid #f00;color:#00f;font:12px Inter">x</div>${img(PNG)}${img(suite("g8"))}`, vp(200, 100));
  for (const k of ["bm", "ref"]) {
    const d = r[k]; if (!d || d.error) continue;
    const icc = [...d.pdf.objs.values()].filter((o) => o.dict && o.data && typeof o.dict.N === "number" && !o.dict.Type).length;
    const oi = d.catalog.OutputIntents ? "yes" : "no";
    t.note(`${k === "bm" ? "bm" : "takumi"}: ICC profile streams ${icc}, /OutputIntents ${oi}, page content colour operators ${[...new Set((d.content(0).match(/\b(rg|RG|g|G|k|K|cs|CS|scn|SCN)\b/g) || []))].join(" ")}`);
  }
});

probeAs("images.colorspace.pdfa", "colour spaces under pdfa (ICC based)", async (t) => {
  const html = `<html lang="en"><head><title>T</title></head><body><div style="margin:10px;width:40px;height:20px;background:#808080;border:2px solid #f00;color:#00f;font:12px Inter">x</div><img alt="a" src="${PNG}" style="width:40px;height:40px"><img alt="g" src="${suite("g8")}" style="width:40px;height:40px"><div style="width:40px;height:20px;background:linear-gradient(red,rgba(0,0,255,.5))"></div></body></html>`;
  for (const level of ["2b", "3b", "2a", "4"]) {
    await cmp(t, level, html, { ...vp(200, 160), pdfa: level, metadata: { title: "T", language: "en" } });
  }
});
