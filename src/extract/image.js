// Pixel helpers on a plain RGBA buffer { width, height, data } so Node (pngjs) and the browser
// (ImageData) share every routine. No canvas, no DOM.

/** Make an empty RGBA image. */
export function makeImage(width, height) {
  return { width, height, data: new Uint8ClampedArray(width * height * 4) };
}

/** Luma of the pixel at (x, y). */
export function lumaAt(img, x, y) {
  const i = (y * img.width + x) * 4;
  return 0.299 * img.data[i] + 0.587 * img.data[i + 1] + 0.114 * img.data[i + 2];
}

/**
 * The rectangle of the frame that holds the phone screen: the widest run of columns whose mean
 * brightness clears `threshold`, then the widest run of rows within those columns. Handles the
 * black pillarboxing of a landscape re-encode and letterboxing of a portrait one. On a frame with
 * no dark border it returns the whole frame.
 */
export function contentRect(img, { threshold = 30, step = 4 } = {}) {
  const { width, height, data } = img;
  const colOn = new Array(width);
  for (let x = 0; x < width; x++) {
    let s = 0, n = 0;
    for (let y = 0; y < height; y += step) { const i = (y * width + x) * 4; s += data[i] + data[i + 1] + data[i + 2]; n++; }
    colOn[x] = s / (3 * n) > threshold;
  }
  const [x0, x1] = widestRun(colOn);
  const rowOn = new Array(height);
  for (let y = 0; y < height; y++) {
    let s = 0, n = 0;
    for (let x = x0; x < x1; x += step) { const i = (y * width + x) * 4; s += data[i] + data[i + 1] + data[i + 2]; n++; }
    rowOn[y] = s / (3 * n) > threshold;
  }
  const [y0, y1] = widestRun(rowOn);
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}

/** [start, end) of the longest run of true values. */
export function widestRun(flags) {
  let best = [0, 0], cur = null;
  for (let i = 0; i <= flags.length; i++) {
    if (i < flags.length && flags[i]) { if (cur === null) cur = i; }
    else if (cur !== null) { if (i - cur > best[1] - best[0]) best = [cur, i]; cur = null; }
  }
  return best;
}

/** Copy a pixel rectangle. Clamped to the image. */
export function crop(img, { x, y, w, h }) {
  const x0 = Math.max(0, Math.round(x)), y0 = Math.max(0, Math.round(y));
  const x1 = Math.min(img.width, Math.round(x + w)), y1 = Math.min(img.height, Math.round(y + h));
  const out = makeImage(Math.max(0, x1 - x0), Math.max(0, y1 - y0));
  for (let yy = y0; yy < y1; yy++) {
    const src = (yy * img.width + x0) * 4, dst = (yy - y0) * out.width * 4;
    out.data.set(img.data.subarray(src, src + out.width * 4), dst);
  }
  return out;
}

/** Rectangle given as fractions (fx, fy, fw, fh) of a base rectangle. */
export function fracRect(rect, fx, fy, fw, fh) {
  return { x: rect.x + fx * rect.w, y: rect.y + fy * rect.h, w: fw * rect.w, h: fh * rect.h };
}

/** Crop by fractions of a base rectangle. */
export function cropFrac(img, rect, fx, fy, fw, fh) {
  return crop(img, fracRect(rect, fx, fy, fw, fh));
}

/** Grayscale copy (RGBA, R=G=B). */
export function toGray(img) {
  const out = makeImage(img.width, img.height);
  const { data } = img;
  for (let i = 0; i < data.length; i += 4) {
    const g = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
    out.data[i] = out.data[i + 1] = out.data[i + 2] = g; out.data[i + 3] = 255;
  }
  return out;
}

/** Inverted copy (white text on colour becomes dark text on light). */
export function invert(img) {
  const out = makeImage(img.width, img.height);
  const { data } = img;
  for (let i = 0; i < data.length; i += 4) {
    out.data[i] = 255 - data[i]; out.data[i + 1] = 255 - data[i + 1]; out.data[i + 2] = 255 - data[i + 2]; out.data[i + 3] = 255;
  }
  return out;
}

/** Bilinear upscale by an integer or fractional factor. Tesseract likes glyphs about 30 px tall. */
export function upscale(img, factor) {
  const w = Math.max(1, Math.round(img.width * factor)), h = Math.max(1, Math.round(img.height * factor));
  const out = makeImage(w, h);
  const { data, width, height } = img;
  for (let y = 0; y < h; y++) {
    const sy = Math.min(height - 1, (y + 0.5) / factor - 0.5), y0 = Math.max(0, Math.floor(sy)), y1 = Math.min(height - 1, y0 + 1), fy = Math.max(0, sy - y0);
    for (let x = 0; x < w; x++) {
      const sx = Math.min(width - 1, (x + 0.5) / factor - 0.5), x0 = Math.max(0, Math.floor(sx)), x1 = Math.min(width - 1, x0 + 1), fx = Math.max(0, sx - x0);
      const o = (y * w + x) * 4;
      for (let c = 0; c < 4; c++) {
        const a = data[(y0 * width + x0) * 4 + c], b = data[(y0 * width + x1) * 4 + c];
        const cc = data[(y1 * width + x0) * 4 + c], d = data[(y1 * width + x1) * 4 + c];
        out.data[o + c] = (a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy;
      }
    }
  }
  return out;
}

/** Binarise a gray image: pixels darker than `threshold` become black, the rest white. */
export function threshold(img, level) {
  const out = makeImage(img.width, img.height);
  const { data } = img;
  for (let i = 0; i < data.length; i += 4) {
    const v = data[i] < level ? 0 : 255;
    out.data[i] = out.data[i + 1] = out.data[i + 2] = v; out.data[i + 3] = 255;
  }
  return out;
}

/** Variance of the 3×3 Laplacian of the luma: higher means sharper. Blurred swipe frames score low. */
export function laplacianVariance(img) {
  const { width, height } = img;
  if (width < 3 || height < 3) return 0;
  const g = new Float32Array(width * height);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) g[y * width + x] = lumaAt(img, x, y);
  let sum = 0, sumSq = 0, n = 0;
  for (let y = 1; y < height - 1; y++) for (let x = 1; x < width - 1; x++) {
    const i = y * width + x;
    const l = 4 * g[i] - g[i - 1] - g[i + 1] - g[i - width] - g[i + width];
    sum += l; sumSq += l * l; n++;
  }
  const mean = sum / n;
  return sumSq / n - mean * mean;
}

/** Mean RGB over a rectangle. */
export function meanColour(img, { x, y, w, h }) {
  let r = 0, g = 0, b = 0, n = 0;
  const x0 = Math.max(0, Math.round(x)), y0 = Math.max(0, Math.round(y));
  const x1 = Math.min(img.width, Math.round(x + w)), y1 = Math.min(img.height, Math.round(y + h));
  for (let yy = y0; yy < y1; yy++) for (let xx = x0; xx < x1; xx++) {
    const i = (yy * img.width + xx) * 4; r += img.data[i]; g += img.data[i + 1]; b += img.data[i + 2]; n++;
  }
  return n ? { r: r / n, g: g / n, b: b / n } : { r: 0, g: 0, b: 0 };
}

/** Fill a rectangle with a colour (used by tests to draw synthetic frames). */
export function fillRect(img, { x, y, w, h }, [r, g, b, a = 255]) {
  const x0 = Math.max(0, Math.round(x)), y0 = Math.max(0, Math.round(y));
  const x1 = Math.min(img.width, Math.round(x + w)), y1 = Math.min(img.height, Math.round(y + h));
  for (let yy = y0; yy < y1; yy++) for (let xx = x0; xx < x1; xx++) {
    const i = (yy * img.width + xx) * 4; img.data[i] = r; img.data[i + 1] = g; img.data[i + 2] = b; img.data[i + 3] = a;
  }
  return img;
}

/**
 * Binarise text against its background whatever the colours: each row's background is the
 * median colour of the row (or of its outer `border` columns when given, for a crop padded
 * around the text); pixels whose largest channel difference from it exceeds `contrast` become
 * black, the rest white. Handles white CP text on the header and the coloured CP of a Mega.
 */
export function binariseByBackground(img, { contrast = 50, border = 0 } = {}) {
  const { width, height, data } = img;
  const out = makeImage(width, height);
  const b = Math.min(border, Math.floor(width / 2));
  const chan = [new Uint8Array(width), new Uint8Array(width), new Uint8Array(width)];
  for (let y = 0; y < height; y++) {
    const bg = [0, 0, 0];
    for (let c = 0; c < 3; c++) {
      let n = 0;
      for (let x = 0; x < width; x++) if (!b || x < b || x >= width - b) chan[c][n++] = data[(y * width + x) * 4 + c];
      bg[c] = chan[c].subarray(0, n).sort()[n >> 1];
    }
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      const d = Math.max(Math.abs(data[i] - bg[0]), Math.abs(data[i + 1] - bg[1]), Math.abs(data[i + 2] - bg[2]));
      const v = d > contrast ? 0 : 255;
      out.data[i] = out.data[i + 1] = out.data[i + 2] = v; out.data[i + 3] = 255;
    }
  }
  return out;
}

/** Binarise with a colour predicate: pixels where `mask(r, g, b)` is true become black, the rest white. */
export function binariseByMask(img, mask) {
  const { width, height, data } = img;
  const out = makeImage(width, height);
  for (let i = 0; i < data.length; i += 4) {
    const v = mask(data[i], data[i + 1], data[i + 2]) ? 0 : 255;
    out.data[i] = out.data[i + 1] = out.data[i + 2] = v; out.data[i + 3] = 255;
  }
  return out;
}

/** Copy with a border of `px` pixels of one colour on every side (tesseract wants margins). */
export function padImage(img, px, [r, g, b] = [255, 255, 255]) {
  const out = makeImage(img.width + 2 * px, img.height + 2 * px);
  fillRect(out, { x: 0, y: 0, w: out.width, h: out.height }, [r, g, b]);
  for (let y = 0; y < img.height; y++) out.data.set(img.data.subarray(y * img.width * 4, (y + 1) * img.width * 4), ((y + px) * out.width + px) * 4);
  return out;
}
