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
 * @param opts       { frame, time, wantHp: true, wantBars: true }
 * @returns a reading; `cp` and `name` are null when the frame is not a settled Pokémon screen.
 */
export async function readFrame(img, ocr, names, { frame = null, time = null, wantHp = true, wantBars = true } = {}) {
  const rect = contentRect(img);
  const cpText = findCpText(img, rect);
  const hpBar = findHpBar(img, rect);
  const regions = regionsFrom(rect, cpText, hpBar);
  const out = { frame, time, rect, cp: null, cpText: '', name: null, nameText: '', nameConfidence: 0, hp: null, hpText: '', ivs: null, ivConfidence: 0, fills: null, sharpness: 0, flags: [] };
  if (!hpBar) { out.flags.push(!cpText ? 'no-cp-text' : 'no-hp-bar'); return out; }
  if (cpText && !cpText.centred) { out.flags.push('mid-swipe'); return out; }
  // A tall model (Zapdos, Moltres) can cover the CP completely. The name, HP and bars are still
  // on screen, and the pipeline can work the CP out from them, so read on when the HP bar sits
  // where a settled card puts it (its left edge does not move when the Pokémon is damaged).
  if (!cpText) {
    out.flags.push('no-cp-text');
    const left = (hpBar.x0 - rect.x) / rect.w;
    if (left < 0.2 || left > 0.33) return out;
  }
  if (cpText) await readCp(img, ocr, regions, cpText, out);

  const nameCrop = crop(img, regions.name);
  out.sharpness = laplacianVariance(nameCrop);
  const nameRead = await ocr.read(nameCrop, { whitelist: WHITELIST.name, psm: 7, scale: scaleFor(nameCrop.height, 70) });
  out.nameText = nameRead.text;
  const letterWords = nameRead.words.filter((w) => /[a-z]{2,}/i.test(w.text));
  out.nameConfidence = letterWords.length ? letterWords.reduce((s, w) => s + w.confidence, 0) / letterWords.length : 0;
  // Tesseract reports confidence 0 for a line with anything it could not place (the gender
  // symbol, the leader's hair on the iPad) even when the word itself is right, so a read that is
  // exactly a species name (of four letters or more) is taken whatever the confidence; a near
  // miss still needs confidence.
  const found = matchName(nameRead.text, names);
  const match = found && (out.nameConfidence >= 40 || (found.distance === 0 && found.text.length >= 4)) ? found : null;
  if (match) {
    out.name = match.candidate.display;
    out.baseName = match.candidate.name;
    out.form = match.candidate.form;
    out.speciesIds = match.candidate.speciesIds;
    out.nameDistance = match.distance;
  } else if (nameRead.text) out.flags.push('name-unmatched');

  if (!out.cp && cpText) out.flags.push('cp-unread');
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

async function readCp(img, ocr, regions, cpText, out) {
  // Tesseract drops or invents a digit now and then in any one mode, so read the CP twice
  // (single line, single word) and take the read they agree on, else the single-line one.
  const cpCrop = crop(img, regions.cp);
  const cpOpts = { whitelist: WHITELIST.digits, binarise: CP_MASKS[cpText.mask], scale: scaleFor(cpCrop.height, 40), pad: 0.3 };
  const cpReads = [await ocr.read(cpCrop, { ...cpOpts, psm: 7 }), await ocr.read(cpCrop, { ...cpOpts, psm: 8 })];
  const cpValues = cpReads.map((r) => parseCp(r.text));
  out.cpText = cpReads.map((r) => r.text).join('|');
  out.cp = cpValues[0] !== null && cpValues[0] === cpValues[1] ? cpValues[0] : cpValues[0] ?? cpValues[1];
  out.cpReads = cpValues.filter((v) => v !== null);
}
