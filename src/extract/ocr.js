// tesseract.js wrapper shared by Node and the browser. Takes RGBA buffers, hands tesseract a PNG,
// returns text plus word boxes so callers can anchor on found text ("Attack", "CP").

import { encodePng } from './png.js';
import { toGray, invert, upscale, crop, binariseByBackground, binariseByMask, padImage } from './image.js';

export const WHITELIST = {
  cp: 'CP0123456789',
  hp: '0123456789/HP ',
  name: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'-. ",
  digits: '0123456789',
};

/**
 * Create an OCR worker. `createWorker` is tesseract.js's; it is injected so this module has no
 * import of tesseract.js itself (Node loads the package, the browser loads the CDN build).
 * `options` go straight to createWorker (langPath, cachePath, gzip, workerPath, corePath...).
 */
export async function createOcr(createWorker, options = {}) {
  const worker = await createWorker('eng', 1, { ...options });
  let current = { whitelist: null, psm: null };

  async function setMode(whitelist, psm) {
    if (current.whitelist === whitelist && current.psm === psm) return;
    await worker.setParameters({ tessedit_char_whitelist: whitelist, tessedit_pageseg_mode: String(psm) });
    current = { whitelist, psm };
  }

  return {
    /**
     * Recognise text in an RGBA image. Options: whitelist, psm (7 = one line, 6 = block),
     * scale (upscale factor), invert (white-on-dark text), gray (default true), binarise (a colour
     * predicate, true, or { contrast, border }: text of any colour against its background, for the CP).
     * Returns { text, confidence, words: [{ text, confidence, bbox: {x0,y0,x1,y1} }] } with boxes in the
     * coordinates of the image passed in (upscaling is undone).
     */
    async read(img, { whitelist = '', psm = 7, scale = 1, invert: inv = false, gray = true, binarise = false, pad = 0 } = {}) {
      if (!img.width || !img.height) return { text: '', confidence: 0, words: [] };
      let work = typeof binarise === 'function' ? binariseByMask(img, binarise) : binarise ? binariseByBackground(img, binarise === true ? {} : binarise) : gray ? toGray(img) : img;
      if (inv && !binarise) work = invert(work);
      if (scale !== 1) work = upscale(work, scale);
      if (pad) work = padImage(work, Math.round(pad * work.height), inv ? [0, 0, 0] : [255, 255, 255]);
      await setMode(whitelist, psm);
      const { data } = await worker.recognize(encodePng(work), {}, { text: true, blocks: true });
      const words = [];
      for (const b of data.blocks ?? []) for (const p of b.paragraphs ?? []) for (const l of p.lines ?? []) for (const w of l.words ?? []) {
        const off = pad ? Math.round(pad * (work.height / (1 + 2 * pad))) : 0;
        words.push({ text: w.text, confidence: w.confidence, bbox: { x0: (w.bbox.x0 - off) / scale, y0: (w.bbox.y0 - off) / scale, x1: (w.bbox.x1 - off) / scale, y1: (w.bbox.y1 - off) / scale } });
      }
      return { text: (data.text ?? '').trim(), confidence: data.confidence ?? 0, words };
    },

    /**
     * Find a word in a band of the frame. Returns the word's box in frame coordinates, or null.
     * Used to anchor the appraisal panel on "Attack".
     */
    async findText(img, band, word, { scale = 1, minConfidence = 50 } = {}) {
      const c = crop(img, band);
      const { words } = await this.read(c, { whitelist: '', psm: 11, scale });
      const target = word.toLowerCase();
      const hit = words.find((w) => w.text.toLowerCase().replace(/[^a-z]/g, '') === target && w.confidence >= minConfidence);
      if (!hit) return null;
      return { x0: band.x + hit.bbox.x0, y0: band.y + hit.bbox.y0, x1: band.x + hit.bbox.x1, y1: band.y + hit.bbox.y1, confidence: hit.confidence };
    },

    terminate: () => worker.terminate(),
  };
}

/** Parse "CP3028", "CP 3028", "P2651", "cp3O28" style reads: the digits after the last letter. */
export function parseCp(text) {
  const t = String(text).replace(/[Oo]/g, '0');
  const at = t.search(/[A-Za-z][^A-Za-z]*$/);
  const tail = at >= 0 ? t.slice(at + 1) : t;
  const m = tail.match(/(\d{2,4})\s*$/);
  return m ? Number(m[1]) : null;
}

/** Parse "145 / 145 HP" style reads; returns { current, max } or null. */
export function parseHp(text) {
  const m = String(text).replace(/[Oo]/g, '0').match(/(\d{1,3})\s*\/\s*(\d{1,3})/);
  return m ? { current: Number(m[1]), max: Number(m[2]) } : null;
}
