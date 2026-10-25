// Example data from the handover (25 Sep 2026 export). Figures the handover did not list in full
// (Eevee Ultra/Master detail, Charmander Ultra, Rookidee, Lugia) are illustrative and marked `illustrative`.
window.LEAGUE_DATA = (() => {
  const o = (name, strength, iv, cost, extra = {}) => ({ speciesId: name.toLowerCase(), name, self: false, strength, iv, cost, overCap: false, moves: null, needs: null, ...extra });
  const S = (rank, score, of) => ({ rank, score, of });
  const IV = (rank, pct, level, cp) => ({ rank, pct, rankPct: Math.round((1 - rank / 4096) * 1000) / 10, level, cp });
  const C = (dust, candy, xl, evolveCandy, toLevel) => ({ dust, candy, xl, evolveCandy, toLevel });
  const L50 = C(488800, 0, 296, 25, 50);

  const eevee = {
    id: 'eevee', name: 'Eevee', cp: 461, level: 17, hp: 72, ivs: [6, 7, 12], ivPct: 56,
    gl: { source: 'export', pick: 3, experimental: 3, options: [
      o('Umbreon', S(24, 90.2, 1152), IV(1879, 94.75, 26.5, 1481), C(56800, 50, 0, 25, 26.5)),
      o('Sylveon', S(192, 82.9, 1152), IV(1583, 95.06, 18, 1475), C(4400, 0, 0, 25, 18)),
      o('Vaporeon', S(550, 73.5, 1152), IV(681, 96.59, 14.5, 1498), C(0, 0, 0, 25, 14.5), { illustrative: true }),
      o('Flareon', S(710, 68.9, 1152), IV(216, 97.24, 18.5, 1500), C(6600, 6, 0, 25, 18.5), { moves: { fast: 'Ember', charged: ['Overheat', 'Flamethrower'] } }),
      o('Leafeon', null, IV(511, 96.8, 17.5, 1497), C(4000, 4, 0, 25, 17.5), { illustrative: true }),
      o('Jolteon', null, IV(2826, 93.1, 20, 1499), C(14000, 16, 0, 25, 20), { illustrative: true }),
      o('Espeon', null, IV(933, 96.1, 15.5, 1486), C(0, 0, 0, 25, 15.5), { illustrative: true }),
      o('Eevee', null, IV(1778, 95.2, 50, 1016), C(488800, 0, 296, 0, 50), { self: true, needs: ['Last Resort'] }),
      o('Glaceon', null, IV(2618, 93.4, 16.5, 1492), C(0, 0, 0, 25, 16.5), { illustrative: true }),
    ] },
    ul: { source: 'export', pick: 3, experimental: 0, options: [
      o('Sylveon', S(100, 85.9, 849), IV(1583, 95.06, 31, 2497), C(165000, 78, 0, 25, 31), { illustrative: true }),
      o('Umbreon', S(116, 85.5, 849), IV(1879, 94.75, 50, 2160), L50, { illustrative: true }),
      o('Vaporeon', S(301, 79.0, 849), IV(681, 96.59, 24.5, 2492), C(70000, 46, 0, 25, 24.5), { illustrative: true }),
      o('Flareon', S(623, 70.2, 849), IV(216, 97.24, 32, 2499), C(178000, 84, 0, 25, 32), { moves: { fast: 'Ember', charged: ['Overheat', 'Flamethrower'] }, illustrative: true }),
      o('Leafeon', null, IV(511, 96.8, 30, 2487), C(150000, 70, 0, 25, 30), { illustrative: true }),
      o('Espeon', null, IV(933, 96.1, 26.5, 2490), C(90000, 56, 0, 25, 26.5), { illustrative: true }),
      o('Glaceon', null, IV(2618, 93.4, 28, 2495), C(110000, 62, 0, 25, 28), { illustrative: true }),
      o('Jolteon', null, IV(2826, 93.1, 34, 2498), C(200000, 94, 0, 25, 34), { illustrative: true }),
      o('Eevee', null, IV(1778, 95.2, 50, 1016), C(488800, 0, 296, 0, 50), { self: true, needs: ['Last Resort'] }),
    ] },
    ml: { source: 'ranked', pick: 0, experimental: 0, options: [
      o('Sylveon', S(70, 80.1, 409), IV(1778, 95.2, 50, 3069), L50, { moves: { fast: 'Fairy Wind', charged: ['Draining Kiss', 'Shadow Ball'] } }),
      o('Umbreon', S(141, 72.4, 409), IV(1778, 95.2, 50, 2160), L50, { illustrative: true }),
      o('Vaporeon', S(188, 68.0, 409), IV(1778, 95.2, 50, 3114), L50, { illustrative: true }),
      o('Leafeon', null, IV(1778, 95.2, 50, 3054), L50, { illustrative: true }),
      o('Glaceon', null, IV(1778, 95.2, 50, 3090), L50, { illustrative: true }),
      o('Espeon', null, IV(1778, 95.2, 50, 3156), L50, { illustrative: true }),
      o('Jolteon', null, IV(1778, 95.2, 50, 2965), L50, { illustrative: true }),
      o('Flareon', null, IV(1778, 95.2, 50, 3194), L50, { illustrative: true }),
      o('Eevee', null, IV(1778, 95.2, 50, 1016), C(488800, 0, 296, 0, 50), { self: true, needs: ['Last Resort'] }),
    ] },
  };

  const magnemite = {
    id: 'magnemite', name: 'Magnemite', cp: 305, level: 9, hp: 38, ivs: [2, 5, 11], ivPct: 40,
    gl: { source: 'export', pick: 1, experimental: 1, options: [
      o('Magnezone', S(365, 78.4, 1152), IV(1606, 94.9, 17.5, 1494), C(25400, 0, 0, 125, 17.5)),
      o('Magneton', S(449, 76.4, 1152), IV(1293, 95.5, 23, 1497), C(54000, 56, 0, 25, 23), { moves: { fast: 'Spark', charged: ['Discharge', 'Magnet Bomb'] } }),
      o('Magnemite', S(480, 75.5, 1152), IV(2396, 93.6, 50, 1211), C(512000, 0, 296, 0, 50), { self: true, needs: ['Discharge'] }),
    ] },
    ul: { source: 'export', pick: 1, experimental: 1, options: [
      o('Magnezone', S(210, 80.3, 849), IV(1606, 94.9, 29.5, 2494), C(140000, 70, 0, 125, 29.5), { illustrative: true }),
      o('Magneton', S(540, 72.1, 849), IV(1293, 95.5, 40.5, 2498), C(290000, 150, 20, 25, 40.5), { moves: { fast: 'Spark', charged: ['Discharge', 'Magnet Bomb'] }, illustrative: true }),
      o('Magnemite', null, IV(2396, 93.6, 50, 1211), C(512000, 0, 296, 0, 50), { self: true, needs: ['Discharge'] }),
    ] },
    ml: { source: 'ranked', pick: 0, experimental: 0, options: [
      o('Magnezone', S(155, 70.6, 409), IV(2396, 93.6, 50, 3205), C(512000, 0, 296, 125, 50), { moves: { fast: 'Spark', charged: ['Wild Charge', 'Mirror Shot'] }, illustrative: true }),
      o('Magneton', null, IV(2396, 93.6, 50, 2237), C(512000, 0, 296, 25, 50)),
      o('Magnemite', null, IV(2396, 93.6, 50, 1211), C(512000, 0, 296, 0, 50), { self: true, needs: ['Discharge'] }),
    ] },
  };

  const charmander = {
    id: 'charmander', name: 'Charmander', cp: 53, level: 2.5, hp: 15, ivs: [10, 10, 10], ivPct: 67,
    gl: { source: 'export', pick: 0, experimental: 0, options: [
      o('Charizard', S(260, 80.8, 1152), IV(607, 96.7, 19, 1499), C(39400, 0, 0, 125, 19), { moves: { fast: 'Wing Attack', charged: ['Blast Burn', 'Dragon Claw'] } }),
      o('Charmeleon', S(651, 70.8, 1152), IV(2155, 94.2, 31.5, 1498), C(134000, 74, 0, 25, 31.5), { illustrative: true }),
      o('Charmander', null, IV(743, 96.5, 50, 1187), C(512000, 0, 296, 0, 50), { self: true, needs: [] }),
    ] },
    ul: { source: 'export', pick: 0, experimental: 0, options: [
      o('Charizard', S(97, 86.0, 849), IV(607, 96.7, 33.5, 2497), C(190000, 100, 0, 125, 33.5), { moves: { fast: 'Wing Attack', charged: ['Blast Burn', 'Dragon Claw'] }, illustrative: true }),
      o('Charmeleon', null, IV(2155, 94.2, 50, 1980), C(512000, 0, 296, 25, 50), { illustrative: true }),
      o('Charmander', null, IV(743, 96.5, 50, 1187), C(512000, 0, 296, 0, 50), { self: true, needs: [] }),
    ] },
    ml: { source: 'ranked', pick: 0, experimental: 0, options: [
      o('Charizard', S(96, 74.9, 409), IV(743, 96.5, 50, 3114), C(512000, 0, 296, 125, 50), { moves: { fast: 'Dragon Breath', charged: ['Blast Burn', 'Dragon Claw'] }, illustrative: true }),
      o('Charmeleon', null, IV(743, 96.5, 50, 1980), C(512000, 0, 296, 25, 50), { illustrative: true }),
      o('Charmander', null, IV(743, 96.5, 50, 1187), C(512000, 0, 296, 0, 50), { self: true, needs: [] }),
    ] },
  };

  // Level 35, already too high for Great League as anything in the family.
  const rookidee = {
    id: 'rookidee', name: 'Rookidee', cp: 1082, level: 35, hp: 109, ivs: [15, 14, 13], ivPct: 93, illustrative: true,
    gl: { source: 'fallback', pick: 0, experimental: 0, options: [
      o('Corviknight', null, null, null, { overCap: true, moves: { fast: 'Steel Wing', charged: ['Iron Head', 'Brave Bird'] } }),
      o('Corvisquire', null, IV(31, 98.9, 35, 1388), C(0, 0, 0, 50, 35), { moves: { fast: 'Peck', charged: ['Brave Bird', 'Drill Peck'] } }),
      o('Rookidee', null, IV(31, 98.9, 35, 924), C(0, 0, 0, 0, 35), { self: true, needs: [] }),
    ] },
    ul: { source: 'emulated', pick: 0, experimental: 0, options: [
      o('Corviknight', S(88, 86.3, 849), IV(31, 98.9, 27.5, 2491), C(0, 0, 0, 100, 27.5), { moves: { fast: 'Steel Wing', charged: ['Iron Head', 'Brave Bird'] } }),
      o('Corvisquire', null, IV(31, 98.9, 50, 1879), C(488800, 0, 296, 50, 50)),
      o('Rookidee', null, IV(31, 98.9, 50, 1246), C(488800, 0, 296, 0, 50), { self: true, needs: [] }),
    ] },
    ml: { source: 'ranked', pick: 0, experimental: 0, options: [
      o('Corviknight', S(52, 82.0, 409), IV(31, 98.9, 50, 3054), C(488800, 0, 296, 100, 50), { moves: { fast: 'Steel Wing', charged: ['Iron Head', 'Brave Bird'] } }),
      o('Corvisquire', null, IV(31, 98.9, 50, 1879), C(488800, 0, 296, 50, 50)),
      o('Rookidee', null, IV(31, 98.9, 50, 1246), C(488800, 0, 296, 0, 50), { self: true, needs: [] }),
    ] },
  };

  // A scan that could not read the appraisal bars: iv and cost null everywhere; the pick is the strongest species.
  const noIV = (opts) => opts.map(x => ({ ...x, iv: null, cost: null }));
  const eeveeNoIV = {
    id: 'eevee-noiv', name: 'Eevee', cp: 174, level: 6, hp: 51, ivs: null, ivPct: null, illustrative: true,
    gl: { source: 'ranked', pick: 0, experimental: 0, options: noIV(eevee.gl.options).map(x => ({ ...x, moves: x.name === 'Umbreon' ? { fast: 'Snarl', charged: ['Foul Play', 'Last Resort'] } : null })) },
    ul: { source: 'ranked', pick: 0, experimental: 0, options: noIV(eevee.ul.options).map(x => ({ ...x, moves: x.name === 'Sylveon' ? { fast: 'Charm', charged: ['Moonblast', 'Psyshock'] } : null })) },
    ml: { source: 'ranked', pick: 0, experimental: 0, options: noIV(eevee.ml.options) },
  };

  // A one-member family.
  const lugia = {
    id: 'lugia', name: 'Lugia', cp: 2834, level: 25, hp: 190, ivs: [14, 15, 15], ivPct: 98, illustrative: true,
    gl: { source: 'fallback', pick: 0, experimental: 0, options: [o('Lugia', S(118, 83.0, 1152), null, null, { overCap: true, self: true, needs: [], moves: { fast: 'Dragon Tail', charged: ['Aeroblast', 'Sky Attack'] } })] },
    ul: { source: 'export', pick: 0, experimental: 0, options: [o('Lugia', S(14, 91.8, 849), null, null, { overCap: true, self: true, needs: [], moves: { fast: 'Dragon Tail', charged: ['Aeroblast', 'Sky Attack'] } })] },
    ml: { source: 'ranked', pick: 0, experimental: 0, options: [o('Lugia', S(9, 88.6, 409), IV(5, 99.6, 50, 4186), C(483400, 216, 296, 0, 50), { self: true, needs: ['Aeroblast'], moves: { fast: 'Dragon Tail', charged: ['Aeroblast', 'Sky Attack'] } })] },
  };

  // Kirlia whose sex was not read: Gallade needs a male. Great League, pick Gallade (emulated).
  const kirlia = {
    id: 'kirlia', name: 'Kirlia', cp: 612, level: 20, hp: 70, ivs: [4, 14, 13], ivPct: 69, illustrative: true,
    gl: { source: 'emulated', pick: 0, experimental: 0, options: [
      o('Gallade', S(96, 86.1, 1152), IV(412, 96.9, 23.5, 1497), C(52000, 54, 0, 100, 23.5), { genderLocked: 'male', moves: { fast: 'Confusion', charged: ['Leaf Blade', 'Close Combat'] } }),
      o('Gardevoir', S(301, 78.9, 1152), IV(1022, 95.8, 22, 1496), C(44000, 48, 0, 100, 22)),
      o('Kirlia', null, IV(1890, 94.6, 50, 1071), C(488800, 0, 296, 0, 50), { self: true, needs: [] }),
    ] },
    ul: { source: 'emulated', pick: 0, experimental: 0, options: [
      o('Gallade', S(72, 86.8, 849), IV(412, 96.9, 40, 2498), C(300000, 160, 20, 100, 40), { genderLocked: 'male', moves: { fast: 'Confusion', charged: ['Leaf Blade', 'Close Combat'] } }),
      o('Gardevoir', S(140, 83.0, 849), IV(1022, 95.8, 37.5, 2497), C(260000, 140, 0, 100, 37.5)),
      o('Kirlia', null, IV(1890, 94.6, 50, 1071), C(488800, 0, 296, 0, 50), { self: true, needs: [] }),
    ] },
    ml: { source: 'ranked', pick: 1, experimental: 1, options: [
      o('Gardevoir', S(180, 68.0, 409), IV(1890, 94.6, 50, 3220), C(488800, 0, 296, 100, 50), { moves: { fast: 'Charm', charged: ['Shadow Ball', 'Synchronoise'] } }),
      o('Gallade', S(205, 65.5, 409), IV(1890, 94.6, 50, 3230), C(488800, 0, 296, 100, 50), { genderLocked: 'male' }),
      o('Kirlia', null, IV(1890, 94.6, 50, 1071), C(488800, 0, 296, 0, 50), { self: true, needs: [] }),
    ] },
  };

  // A level-51 Best Buddy Pupitar, past its best Ultra League level as Tyranitar: cost 0, evolution candy only.
  const pupitar = {
    id: 'pupitar', name: 'Pupitar', cp: 1766, level: 51, hp: 142, ivs: [15, 15, 15], ivPct: 100, illustrative: true,
    gl: { source: 'export', pick: 0, experimental: 0, options: [
      o('Tyranitar', null, null, null, { overCap: true, moves: { fast: 'Smack Down', charged: ['Crunch', 'Brutal Swing'] } }),
      o('Pupitar', null, null, null, { overCap: true, self: true, needs: [] }),
    ] },
    ul: { source: 'export', pick: 0, experimental: 0, options: [
      o('Tyranitar', S(88, 84.9, 849), IV(1, 100, 24.5, 2492), C(0, 0, 0, 100, 24.5), { moves: { fast: 'Smack Down', charged: ['Crunch', 'Brutal Swing'] } }),
      o('Pupitar', null, null, null, { overCap: true, self: true, needs: [] }),
    ] },
    ml: { source: 'ranked', pick: 0, experimental: 0, options: [
      o('Tyranitar', S(40, 85.2, 409), IV(1, 100, 51, 4335), C(0, 0, 0, 100, 51), { moves: { fast: 'Smack Down', charged: ['Crunch', 'Brutal Swing'] } }),
      o('Pupitar', null, IV(1, 100, 51, 1766), C(0, 0, 0, 0, 51), { self: true, needs: [] }),
    ] },
  };

  return { eevee, magnemite, charmander, rookidee, eeveeNoIV, lugia, kirlia, pupitar };
})();
