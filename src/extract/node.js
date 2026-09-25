// Node-only adapters: PNG in and out via pngjs. The browser gets the same buffers from ImageData.
import { readFileSync, writeFileSync } from 'node:fs';
import { PNG } from 'pngjs';

export function readPng(path) {
  const png = PNG.sync.read(readFileSync(path));
  return { width: png.width, height: png.height, data: new Uint8ClampedArray(png.data.buffer, png.data.byteOffset, png.data.length) };
}

export function pngBuffer(img) {
  const png = new PNG({ width: img.width, height: img.height });
  png.data = Buffer.from(img.data.buffer, img.data.byteOffset, img.data.length);
  return PNG.sync.write(png);
}

export function writePng(path, img) {
  writeFileSync(path, pngBuffer(img));
}
