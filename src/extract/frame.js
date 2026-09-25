// Read one frame: anchors, OCR of CP / name / HP, bar IVs, sharpness. Pure function of the image
// plus an OCR worker; the pipeline decides what to do with the readings.

import { contentRect, crop, laplacianVariance } from './image.js';
import { findCpText, findHpBar, regionsFrom, CP_MASKS } from './layout.js';
import { readBars } from './bars.js';
import { WHITELIST, parseCp, parseHp } from './ocr.js';
import { matchName } from './names.js';

const scaleFor = (h, target) => target / h;

/**
 * @param img        RGBA frame
 * @param ocr        from createOcr
 * @param names      displayNames(gm)
 * @param opts       { frame, time, readHp: true, readBars: true }
 * @returns a reading; `cp` and `name` are null when the frame is not a settled Pokémon screen.
 */
export async function readFrame(img, ocr, names, { frame = null, time = null, wantHp = true, wantBars = true } = {}) {
  const rect = contentRect(img);
  const cpText = findCpText(img, rect);
  const hpBar = findHpBar(img, rect);
  const regions = regionsFrom(rect, cpText, hpBar);
  const out = { frame, time, rect, cp: null, cpText: '', name: null, nameText: '', nameConfidence: 0, hp: null, hpText: '', ivs: null, ivConfidence: 0, fills: null, sharpness: 0, flags: [] };
  if (!cpText || !hpBar) { out.flags.push(!cpText ? 'no-cp-text' : 'no-hp-bar'); return out; }
  if (!cpText.centred) { out.flags.push('mid-swipe'); return out; }

  // Tesseract drops or invents a digit now and then in any one mode, so read the CP twice
  // (single line, single word) and take the read they agree on, else the single-line one.
  const cpCrop = crop(img, regions.cp);
  const cpOpts = { whitelist: WHITELIST.digits, binarise: CP_MASKS[cpText.mask], scale: scaleFor(cpCrop.height, 40), pad: 0.3 };
  const cpReads = [await ocr.read(cpCrop, { ...cpOpts, psm: 7 }), await ocr.read(cpCrop, { ...cpOpts, psm: 8 })];
  const cpValues = cpReads.map((r) => parseCp(r.text));
  out.cpText = cpReads.map((r) => r.text).join('|');
  out.cp = cpValues[0] !== null && cpValues[0] === cpValues[1] ? cpValues[0] : cpValues[0] ?? cpValues[1];
  out.cpAgreed = cpValues[0] !== null && cpValues[0] === cpValues[1];
  out.cpReads = cpValues.filter((v) => v !== null);

  const nameCrop = crop(img, regions.name);
  out.sharpness = laplacianVariance(nameCrop);
  const nameRead = await ocr.read(nameCrop, { whitelist: WHITELIST.name, psm: 7, scale: scaleFor(nameCrop.height, 70) });
  out.nameText = nameRead.text;
  const letterWords = nameRead.words.filter((w) => /[a-z]{2,}/i.test(w.text));
  out.nameConfidence = letterWords.length ? letterWords.reduce((s, w) => s + w.confidence, 0) / letterWords.length : 0;
  const match = out.nameConfidence >= 40 ? matchName(nameRead.text, names) : null;
  if (match) {
    out.name = match.candidate.display;
    out.baseName = match.candidate.name;
    out.form = match.candidate.form;
    out.speciesIds = match.candidate.speciesIds;
    out.nameDistance = match.distance;
  } else if (nameRead.text) out.flags.push('name-unmatched');

  if (!out.cp) out.flags.push('cp-unread');
  if (!out.name) { out.cp = null; return out; } // a frame without an identifiable Pokémon is not a reading

  if (wantHp) {
    const hpCrop = crop(img, regions.hp);
    const hpRead = await ocr.read(hpCrop, { whitelist: WHITELIST.hp, psm: 7, scale: scaleFor(hpCrop.height, 60) });
    out.hpText = hpRead.text;
    out.hp = parseHp(hpRead.text);
    if (!out.hp) out.flags.push('hp-unread');
  }
  if (wantBars) {
    const { result } = readBars(img, rect, regions.panelSearch);
    if (result) { out.ivs = result.ivs; out.ivConfidence = result.confidence; out.fills = result.fills; }
    else out.flags.push('no-bars');
  }
  return out;
}
