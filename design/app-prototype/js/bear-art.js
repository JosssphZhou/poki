// The bear’s pictures, cut from one sheet (assets/bear-poses.png) into poses and layers.
/* ---------- the bear ---------- */
const POSES = [
    'rest',
    'think',
    'phone',
    'search',
    'ask',
    'hide',
    'happy',
    'worry',
    'sleep',
    'lost',
    'listen',
    'speak',
    'wave',
  ],
  SPR = {};
const CFG = { rest: { split: 1, neck: 74 } },
  BLINK = new Set(['rest', 'think', 'phone', 'ask', 'worry', 'lost', 'listen', 'speak', 'wave']);
function cut(img) {
  const X = [15, 412, 808, 1206, 1602],
    Y = [15, 412, 808],
    T = 382,
    N = T * T,
    st = new Int32Array(N);
  /* regions(test): connected groups of pixels passing test, with size and box */
  const regions = (test) => {
    const lab = new Int32Array(N),
      R = [null];
    for (let i = 0; i < N; i++) {
      if (lab[i] || !test(i)) continue;
      const L = R.length,
        r = { n: 0, x0: T, y0: T, x1: 0, y1: 0 };
      let sp = 0;
      st[sp++] = i;
      lab[i] = L;
      while (sp) {
        const j = st[--sp],
          jx = j % T,
          jy = (j / T) | 0;
        r.n++;
        if (jx < r.x0) r.x0 = jx;
        if (jx > r.x1) r.x1 = jx;
        if (jy < r.y0) r.y0 = jy;
        if (jy > r.y1) r.y1 = jy;
        for (const k of [
          jx > 0 ? j - 1 : -1,
          jx < T - 1 ? j + 1 : -1,
          jy > 0 ? j - T : -1,
          jy < T - 1 ? j + T : -1,
        ])
          if (k >= 0 && !lab[k] && test(k)) {
            lab[k] = L;
            st[sp++] = k;
          }
      }
      R.push(r);
    }
    return { lab, R };
  };
  const url = (d, keep) => {
    const c = document.createElement('canvas');
    c.width = c.height = T;
    const o = new ImageData(new Uint8ClampedArray(d.data), T, T);
    for (let i = 0; i < N; i++) if (!keep(i)) o.data[i * 4 + 3] = 0;
    c.getContext('2d').putImageData(o, 0, 0);
    return c.toDataURL();
  };
  POSES.forEach((name, n) => {
    const c = document.createElement('canvas');
    c.width = c.height = T;
    const x = c.getContext('2d', { willReadFrequently: true });
    x.drawImage(img, X[n % 5], Y[(n / 5) | 0], T, T, 0, 0, T, T);
    const d = x.getImageData(0, 0, T, T),
      p = d.data,
      bg = [0, 0, 0];
    let k = 0;
    for (let yy = 3; yy < 9; yy++)
      for (let xx = 3; xx < 9; xx++, k++) {
        const i = (yy * T + xx) * 4;
        bg[0] += p[i];
        bg[1] += p[i + 1];
        bg[2] += p[i + 2];
      }
    bg[0] /= k;
    bg[1] /= k;
    bg[2] /= k;
    for (let i = 0; i < p.length; i += 4) {
      const dr = p[i] - bg[0],
        dg = p[i + 1] - bg[1],
        db = p[i + 2] - bg[2],
        dist = Math.sqrt(dr * dr * 0.6 + dg * dg + db * db * 0.4);
      let a = (dist - 26) / (72 - 26);
      a = a <= 0 ? 0 : a >= 1 ? 1 : a * a * (3 - 2 * a);
      if (a > 0 && a < 1) {
        p[i] = Math.max(0, Math.min(255, bg[0] + dr / a));
        p[i + 1] = Math.max(0, Math.min(255, bg[1] + dg / a));
        p[i + 2] = Math.max(0, Math.min(255, bg[2] + db / a));
      }
      const q = i >> 2,
        px = q % T,
        py = (q / T) | 0;
      if (px < 4 || py < 4 || px > T - 5 || py > T - 5) a = 0;
      p[i + 3] = a * 255;
    }
    /* the largest solid region is the bear; every other region is one of its marks (question mark, sparkles, sound arcs, zzz) */
    const solid = regions((i) => p[i * 4 + 3] > 110);
    let bear = 1;
    solid.R.forEach((r, L) => {
      if (r && r.n > solid.R[bear].n) bear = L;
    });
    const own = new Uint8Array(N);
    for (let i = 0; i < N; i++) {
      const L = solid.lab[i];
      own[i] = L === bear ? 1 : L && solid.R[L].n > 14 ? 2 : 0;
    }
    const edge = [];
    for (let i = 0; i < N; i++) {
      if (own[i] || !p[i * 4 + 3] || solid.lab[i]) continue;
      const ix = i % T,
        iy = (i / T) | 0;
      let f = 0;
      for (let dy = -3; dy <= 3 && f !== 1; dy++)
        for (let dx = -3; dx <= 3; dx++) {
          const xx = ix + dx,
            yy = iy + dy;
          if (xx < 0 || yy < 0 || xx >= T || yy >= T) continue;
          const o = own[yy * T + xx];
          if (o === 1) {
            f = 1;
            break;
          }
          if (o === 2) f = 2;
        }
      edge.push(i, f);
    }
    for (let e = 0; e < edge.length; e += 2) own[edge[e]] = edge[e + 1];
    let fn = 0,
      fx0 = 0,
      fy0 = 0;
    for (let i = 0; i < N; i++)
      if (own[i] === 2) {
        fn++;
        fx0 += i % T;
        fy0 += (i / T) | 0;
      }
    /* eyes: the two largest dark brown regions on the bear */
    const dark = regions(
      (i) =>
        own[i] === 1 &&
        p[i * 4 + 3] > 200 &&
        p[i * 4] < 125 &&
        p[i * 4 + 1] < 85 &&
        p[i * 4 + 2] < 80 &&
        p[i * 4] > p[i * 4 + 2] + 10,
    );
    const mean = (xa, xb, ya, yb) => {
      let r = 0,
        g = 0,
        b = 0,
        m = 0;
      for (let yy = Math.max(0, ya); yy <= Math.min(T - 1, yb); yy++)
        for (let xx = Math.max(0, xa | 0); xx <= Math.min(T - 1, xb | 0); xx++) {
          const i = yy * T + xx;
          if (own[i] !== 1 || dark.lab[i] || p[i * 4 + 3] < 250) continue;
          r += p[i * 4];
          g += p[i * 4 + 1];
          b += p[i * 4 + 2];
          m++;
        }
      return m ? `rgb(${(r / m) | 0},${(g / m) | 0},${(b / m) | 0})` : '#eef2fb';
    };
    const eyes = dark.R.filter(
      (r) =>
        r &&
        r.n > 500 &&
        (r.x1 - r.x0) / (r.y1 - r.y0 + 1) > 0.55 &&
        (r.x1 - r.x0) / (r.y1 - r.y0 + 1) < 1.8 &&
        (r.y0 + r.y1) / 2 < T * 0.8,
    )
      .sort((a, b) => b.n - a.n)
      .slice(0, 2)
      .sort((a, b) => a.x0 - b.x0)
      .map((r) => {
        const w = r.x1 - r.x0 + 1,
          h = r.y1 - r.y0 + 1,
          g = Math.max(w, h) * 0.09,
          cx = (r.x0 + r.x1) / 2;
        return {
          x: ((r.x0 - g) / T) * 100,
          y: ((r.y0 - g) / T) * 100,
          w: ((w + 2 * g) / T) * 100,
          h: ((h + 2 * g) / T) * 100,
          top: mean(cx - w / 4, cx + w / 4, r.y0 - 9, r.y0 - 4),
          bot: mean(cx - w / 4, cx + w / 4, r.y1 + 4, r.y1 + 9),
        };
      });
    SPR[name] = {
      bear: url(d, (i) => own[i] === 1),
      fx: fn ? url(d, (i) => own[i] === 2) : null,
      full: url(d, (i) => own[i] > 0),
      eyes: eyes.length === 2 ? eyes : [],
      fxo: fn ? `${((fx0 / fn / T) * 100).toFixed(1)}% ${((fy0 / fn / T) * 100).toFixed(1)}%` : '50% 50%',
    };
  });
}
