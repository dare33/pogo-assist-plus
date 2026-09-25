// Minimal PNG encoder (RGBA, 8-bit, stored deflate blocks) so the same OCR module can hand a
// crop to tesseract.js in Node and in the browser without pngjs or a canvas. Crops are small, so
// no compression is fine.

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function adler32(bytes) {
  let a = 1, b = 0;
  for (let i = 0; i < bytes.length; i++) { a = (a + bytes[i]) % 65521; b = (b + a) % 65521; }
  return ((b << 16) | a) >>> 0;
}

function u32(v) { return [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255]; }

function chunk(type, body) {
  const t = [...type].map((ch) => ch.charCodeAt(0));
  const tb = new Uint8Array(t.length + body.length);
  tb.set(t, 0); tb.set(body, t.length);
  return [...u32(body.length), ...tb, ...u32(crc32(tb))];
}

/** Encode an RGBA { width, height, data } image as PNG bytes. */
export function encodePng({ width, height, data }) {
  const stride = width * 4 + 1;
  const raw = new Uint8Array(stride * height);
  for (let y = 0; y < height; y++) {
    raw[y * stride] = 0; // filter: none
    raw.set(data.subarray(y * width * 4, (y + 1) * width * 4), y * stride + 1);
  }
  // zlib stream of stored blocks
  const blocks = [];
  const MAX = 65535;
  for (let off = 0; off < raw.length || off === 0; off += MAX) {
    const n = Math.min(MAX, raw.length - off);
    const last = off + n >= raw.length ? 1 : 0;
    blocks.push(last, n & 255, n >> 8, (~n) & 255, ((~n) >> 8) & 255);
    for (let i = 0; i < n; i++) blocks.push(raw[off + i]);
    if (n === 0) break;
  }
  const z = new Uint8Array(2 + blocks.length + 4);
  z[0] = 0x78; z[1] = 0x01;
  z.set(blocks, 2);
  z.set(u32(adler32(raw)), 2 + blocks.length);
  const ihdr = new Uint8Array([...u32(width), ...u32(height), 8, 6, 0, 0, 0]);
  return new Uint8Array([
    137, 80, 78, 71, 13, 10, 26, 10,
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', z),
    ...chunk('IEND', new Uint8Array(0)),
  ]);
}
