// Power-up costs: stardust and candy per half-level step, XL candy from level 40.
// step(level) is the cost of the power-up that starts at `level` and ends at level + 0.5.

function bracket(level, table) {
  for (const [from, to, value] of table) if (level >= from && level <= to) return value;
  throw new RangeError(`no cost entry for level ${level}`);
}

// [fromLevel, toLevel inclusive, value] — each row covers the power-ups starting in that range.
const DUST = [
  [1, 2.5, 200], [3, 4.5, 400], [5, 6.5, 600], [7, 8.5, 800], [9, 10.5, 1000],
  [11, 12.5, 1300], [13, 14.5, 1600], [15, 16.5, 1900], [17, 18.5, 2200], [19, 20.5, 2500],
  [21, 22.5, 3000], [23, 24.5, 3500], [25, 26.5, 4000], [27, 28.5, 4500], [29, 30.5, 5000],
  [31, 32.5, 6000], [33, 34.5, 7000], [35, 36.5, 8000], [37, 38.5, 9000], [39, 40.5, 10000],
  [41, 42.5, 11000], [43, 44.5, 12000], [45, 46.5, 13000], [47, 48.5, 14000], [49, 50.5, 15000],
];
// Fitted against 183 start/target pairs from a Poke Genie export (see test/cpm.test.js).
const CANDY = [
  [1, 10.5, 1], [11, 20.5, 2], [21, 25.5, 3], [26, 30.5, 4], [31, 32.5, 6], [33, 34.5, 8],
  [35, 36.5, 10], [37, 38.5, 12], [39, 39.5, 15],
];
const XL = [
  [40, 41.5, 10], [42, 43.5, 12], [44, 45.5, 15], [46, 47.5, 17], [48, 49.5, 20], [50, 50.5, 0],
];

export const SHADOW_MULTIPLIER = 1.2;
export const PURIFIED_MULTIPLIER = 0.9;
export const LUCKY_DUST_MULTIPLIER = 0.5;

/** Cost of one power-up starting at `level`. */
export function step(level) {
  if (level >= 50) return { dust: 0, candy: 0, xl: 0 }; // 50 -> 51 is the Best Buddy boost, not a power-up
  const dust = bracket(level, DUST);
  return level >= 40
    ? { dust, candy: 0, xl: bracket(level, XL) }
    : { dust, candy: bracket(level, CANDY), xl: 0 };
}

/**
 * Total cost to go from `from` to `to` (both half-levels, to > from).
 * flags: { shadow, purified, lucky } apply the standard multipliers.
 * Shadow multiplies dust and candy; purified multiplies dust and candy; lucky halves dust only.
 */
export function powerUpCost(from, to, flags = {}) {
  if (to <= from) return { dust: 0, candy: 0, xl: 0, steps: 0 };
  let dust = 0, candy = 0, xl = 0, steps = 0;
  for (let lv = from; lv < to; lv += 0.5) {
    const s = step(lv);
    dust += s.dust; candy += s.candy; xl += s.xl; steps += 1;
  }
  let mult = 1;
  if (flags.shadow) mult *= SHADOW_MULTIPLIER;
  if (flags.purified) mult *= PURIFIED_MULTIPLIER;
  let dustMult = mult;
  if (flags.lucky) dustMult *= LUCKY_DUST_MULTIPLIER;
  return {
    dust: Math.round(dust * dustMult),
    candy: Math.ceil(candy * mult),
    xl: Math.ceil(xl * mult),
    steps,
  };
}

/** Second charged move cost from the game master's thirdMoveCost (stardust); candy is dust / 1000. Shadows pay 1.2×. */
export function secondMoveCost(thirdMoveCostDust, flags = {}) {
  const mult = flags.shadow ? SHADOW_MULTIPLIER : flags.purified ? PURIFIED_MULTIPLIER : 1;
  return { dust: Math.round(thirdMoveCostDust * mult), candy: Math.round((thirdMoveCostDust / 1000) * mult) };
}
