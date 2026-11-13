// Poki’s light: five hue sets, worked out in OKLCH so every set has the same brightness.
/* ---------- the hue ---------- */
const MIXES = [
  { n: 'First light', body: [262, 250, 235], warm: [35, 60, 88] },
  { n: 'Dusk', body: [266, 290, 320], warm: [350, 35, 70] },
  { n: 'Lagoon', body: [258, 222, 192], warm: [168, 125, 104] },
  { n: 'Sorbet', body: [305, 335, 355], warm: [20, 48, 80] },
  { n: 'Firefly', body: [245, 232, 215], warm: [62, 84, 100] },
];
const linOK = (L, C, H) => {
  const h = (H * Math.PI) / 180,
    a = C * Math.cos(h),
    b = C * Math.sin(h),
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3,
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3,
    s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ].every((v) => v >= -0.0005 && v <= 1.0005);
};
const CEIL = {};
const ceil = (L, H) =>
  CEIL[L + '/' + H] ??
  (CEIL[L + '/' + H] = (() => {
    let lo = 0,
      hi = 0.4;
    for (let i = 0; i < 16; i++) {
      const md = (lo + hi) / 2;
      linOK(L, md, H) ? (lo = md) : (hi = md);
    }
    return lo;
  })());
const col = (L, H, k = 0.55) => `oklch(${L} ${(ceil(L, H) * k).toFixed(3)} ${H})`;
const hue = (m, dark) =>
  dark
    ? {
        0: col(0.28, m.body[0], 0.5),
        '1a': col(0.48, m.body[0]),
        '1b': col(0.66, m.body[1]),
        '2a': col(0.72, m.warm[0]),
        '2b': col(0.8, m.warm[1]),
        3: col(0.93, m.warm[2]),
      }
    : {
        0: col(0.92, m.body[2], 0.45),
        '1a': col(0.7, m.body[0]),
        '1b': col(0.8, m.body[1]),
        '2a': col(0.76, m.warm[0]),
        '2b': col(0.83, m.warm[1]),
        3: col(0.95, m.warm[2], 0.4),
      };
