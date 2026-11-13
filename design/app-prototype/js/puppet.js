// The bear as a puppet: its states, its one-shot moves, and the clock that keeps it alive.
/* ---------- the puppet: one clock drives every continuous move; one-shot moves are separate ---------- */
const ST = {
  rest: { n: 'Resting', g: 'Idle', art: 'rest' },
  along: { n: 'Reading along', g: 'Idle', art: 'rest' },
  wave: { n: 'Hello', g: 'Idle', art: 'wave' },
  sleep: { n: 'Asleep', g: 'Idle', art: 'sleep' },
  off: { n: 'Switched off', g: 'Idle', art: 'sleep', nofx: 1, dim: 1 },
  connect: { n: 'Connecting', g: 'On a call', art: 'rest', mark: 'dots' },
  listen: { n: 'Listening', g: 'On a call', art: 'listen' },
  hearing: { n: 'Hearing you', g: 'On a call', art: 'listen' },
  speak: { n: 'Speaking', g: 'On a call', art: 'speak' },
  muted: { n: 'Muted', g: 'On a call', art: 'rest', mark: 'mute' },
  think: { n: 'Thinking', g: 'Working', art: 'think' },
  read: { n: 'Reading the screen', g: 'Working', art: 'search' },
  search: { n: 'Looking for it', g: 'Working', art: 'search' },
  phone: { n: 'Tapping', g: 'Working', art: 'phone' },
  type: { n: 'Typing', g: 'Working', art: 'phone' },
  scroll: { n: 'Scrolling', g: 'Working', art: 'phone' },
  wait: { n: 'Waiting on the app', g: 'Working', art: 'phone', mark: 'dots' },
  remember: { n: 'Remembering', g: 'Working', art: 'think', mark: 'spark' },
  ask: { n: 'Your turn', g: 'Needs you', art: 'ask' },
  urgent: { n: 'Last seconds', g: 'Needs you', art: 'ask' },
  hide: { n: 'Hands off', g: 'Needs you', art: 'hide' },
  paused: { n: 'Paused', g: 'Needs you', art: 'wave', nofx: 1, mark: 'pause' },
  happy: { n: 'Done', g: 'Result', art: 'happy' },
  cheer: { n: 'Big win', g: 'Result', art: 'happy' },
  worry: { n: 'Went wrong', g: 'Result', art: 'worry' },
  lost: { n: 'Lost link', g: 'Result', art: 'lost' },
};
const MARK = {
  dots: '<i></i><i></i><i></i>',
  pause:
    '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="5" y="4" width="5" height="16" rx="2"/><rect x="14" y="4" width="5" height="16" rx="2"/></svg>',
  mute: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11.5" rx="3" fill="currentColor" stroke="none"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M4 3l16 18"/></svg>',
  spark:
    '<svg class="tw" viewBox="0 0 24 24" fill="currentColor"><path d="M12 1.5c.9 5.600 3 7.700 8.600 8.600-5.600.9-7.700 3-8.600 8.600-.9-5.600-3-7.700-8.600-8.600 5.600-.9 7.700-3 8.600-8.600z"/></svg>',
};
const B = {
  pose: '',
  t: 0,
  amp: 0,
  ampT: 0,
  gaze: { x: 0, y: 0 },
  g: { x: 0, y: 0 },
  kick: 0,
  energy: 1,
  speed: 1,
  still: matchMedia('(prefers-reduced-motion: reduce)').matches,
  pinned: false,
  typing: false,
  eyes: false,
  ptr: -1e9,
  wave: -9,
};
const isStill = () =>
  B.still ||
  !!(
    ph() && ph().dataset.at === 'island'
  ); /* a Live Activity cannot animate, so in the island the bear is a still picture */
let lidN = 0;
const lid = (e) => {
  const n = ++lidN;
  return `<svg class="lid" viewBox="0 0 100 100" preserveAspectRatio="none" style="left:${e.x}%;top:${e.y}%;width:${e.w}%;height:${e.h}%" aria-hidden="true"><defs><clipPath id="lc${n}"><ellipse cx="50" cy="50" rx="50" ry="50"/></clipPath><linearGradient id="lg${n}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${e.top}"/><stop offset="1" stop-color="${e.bot}"/></linearGradient></defs><g clip-path="url(#lc${n})"><rect class="lf" y="-2" width="100" height="104" fill="url(#lg${n})"/></g><path class="ll" d="M13 57 Q50 82 87 57" fill="none" stroke="#3c1f17" stroke-width="9" stroke-linecap="round"/></svg>`;
};
const MOVES = {
  pop: [['scale(1,1)', 'scale(1.07,.9)', 'scale(.96,1.05)', 'scale(1,1)'], [0, 0.35, 0.7, 1], 360],
  poke: [['scale(1,1)', 'scale(1.12,.86)', 'scale(.96,1.05)', 'scale(1,1)'], [0, 0.3, 0.65, 1], 380],
  crouch: [['scale(1,1)', 'translateY(3%) scale(1.15,.8)'], [0, 1], 170, 1],
  fly: [
    [
      'translateY(3%) scale(1.15,.8)',
      'translateY(-6%) scale(.88,1.2) rotate(-10deg)',
      'scale(.92,1.12) rotate(-4deg)',
      'scale(1.18,.82)',
      'scale(1,1)',
    ],
    [0, 0.28, 0.68, 0.86, 1],
    720,
  ],
  stretch: [
    ['scale(1,1)', 'scale(1.08,.9)', 'scale(.92,1.18)', 'scale(1.04,.97)', 'scale(1,1)'],
    [0, 0.18, 0.5, 0.8, 1],
    900,
  ],
  land: [
    [
      'translateY(-12%) scale(.9,1.14)',
      'scale(1.16,.84)',
      'scale(.96,1.05)',
      'scale(1.02,.98)',
      'scale(1,1)',
    ],
    [0, 0.38, 0.62, 0.82, 1],
    520,
  ],
  hop: [
    [
      'scale(1,1)',
      'translateY(2%) scale(1.1,.88)',
      'translateY(-22%) scale(.93,1.1)',
      'translateY(0) scale(1.12,.88)',
      'translateY(-9%) scale(.97,1.04)',
      'scale(1.05,.95)',
      'scale(1,1)',
    ],
    [0, 0.12, 0.38, 0.58, 0.74, 0.88, 1],
    760,
  ],
  wiggle: [
    ['rotate(0deg)', 'rotate(-8deg)', 'rotate(7deg)', 'rotate(-6deg)', 'rotate(4deg)', 'rotate(0deg)'],
    [0, 0.16, 0.38, 0.6, 0.8, 1],
    820,
  ],
  nod: [
    ['scale(1,1)', 'translateY(4%) scale(1.03,.95)', 'translateY(-1%) scale(.99,1.02)', 'scale(1,1)'],
    [0, 0.35, 0.7, 1],
    300,
  ],
  shake: [
    [
      'translateX(0)',
      'translateX(-4%)',
      'translateX(4%)',
      'translateX(-3%)',
      'translateX(2%)',
      'translateX(0)',
    ],
    [0, 0.15, 0.35, 0.55, 0.78, 1],
    420,
  ],
};
function act(n) {
  const el = $('.b-act');
  if (!el) return Promise.resolve();
  el.getAnimations().forEach((a) => a.cancel());
  if (B.still) return Promise.resolve();
  const [fr, off, ms, hold] = MOVES[n];
  const a = el.animate(
    fr.map((t, i) => ({ transform: t, offset: off[i] })),
    { duration: ms, easing: 'cubic-bezier(.3,.6,.3,1)', fill: hold ? 'forwards' : 'none' },
  );
  a.playbackRate = B.speed;
  return a.finished.catch(() => {});
}
function setPose(p, quiet) {
  const live = $('#bLive'),
    root = $('#bear');
  if (!live) return;
  if (B.pose === p && live.firstChild) return;
  const prev = ST[B.pose],
    S0 = ST[p],
    S = SPR[S0.art],
    C = CFG[S0.art] || {},
    same = !!(prev && prev.art === S0.art && live.firstChild);
  B.pose = p;
  if (!same) {
    const lids = (BLINK.has(S0.art) ? S.eyes : []).map(lid).join(''),
      el = document.createElement('div');
    el.className = 'b-pose';
    el.innerHTML = C.split
      ? `<img src="${S.bear}" alt="" style="-webkit-mask-image:linear-gradient(transparent ${C.neck - 16}%,#000 ${C.neck - 8}%);mask-image:linear-gradient(transparent ${C.neck - 16}%,#000 ${C.neck - 8}%)"><div class="b-head split" style="--neck:${C.neck}%;-webkit-mask-image:linear-gradient(#000 ${C.neck - 4}%,transparent ${C.neck + 6}%);mask-image:linear-gradient(#000 ${C.neck - 4}%,transparent ${C.neck + 6}%)"><img src="${S.bear}" alt="">${lids}</div>`
      : `<div class="b-head"><img src="${S.bear}" alt="">${lids}</div>`;
    const old = [...live.children];
    live.appendChild(el);
    old.forEach((o) => {
      if (B.still) return o.remove();
      o.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 120, fill: 'forwards' }).finished.then(
        () => o.remove(),
        () => o.remove(),
      );
    });
  }
  B.eyes = BLINK.has(S0.art) && S.eyes.length > 0 && !S0.dim;
  root.toggleAttribute('data-dim', !!S0.dim);
  const fx = $('#bFx'),
    mk = $('#bMark'),
    grow = [
      { scale: 0.3, opacity: 0 },
      { scale: 1.18, opacity: 1, offset: 0.6 },
      { scale: 1, opacity: 1 },
    ],
    go = { duration: 340, easing: 'ease-out' };
  if (S.fx && !S0.nofx) {
    if (fx.hidden || fx.dataset.art !== S0.art) {
      fx.src = S.fx;
      fx.dataset.art = S0.art;
      fx.style.transformOrigin = S.fxo;
      fx.hidden = false;
      if (!isStill()) fx.animate(grow, go).playbackRate = B.speed;
    }
  } else fx.hidden = true;
  mk.innerHTML = S0.mark ? MARK[S0.mark] : '';
  mk.hidden = !S0.mark;
  if (S0.mark && !isStill()) mk.animate(grow, go).playbackRate = B.speed;
  if (p === 'wave') B.wave = B.t;
  if (!quiet && !isStill())
    act(S0.art === 'happy' ? 'hop' : p === 'worry' || p === 'lost' ? 'shake' : same ? 'nod' : 'pop');
  document
    .querySelectorAll('#poses button')
    .forEach((b) => b.setAttribute('aria-pressed', b.dataset.pose === p));
}
let lastF = performance.now();
let FC = 0;
function frame(now) {
  if (!(EMBED && ++FC > 40)) requestAnimationFrame(frame);
  const el = $('#bear'),
    dt = Math.min(50, now - lastF) * B.speed;
  lastF = now;
  if (!el) return;
  B.t += dt / 1000;
  const t = B.t,
    e = B.energy,
    s = Math.sin,
    p = B.pose,
    S0 = ST[p] || {},
    A = S0.art,
    o = { lx: 0, ly: 0, lr: 0, sx: 0, sy: 0, hx: 0, hy: 0, hr: 0 };
  let fs = 1,
    fr = 0,
    fy = 0,
    fo = 1;
  if (B.pinned) B.ampT = +$('#cAmp').value * (0.55 + 0.45 * s(t * 9) * s(t * 2.3));
  if (now - B.ptr > 2600 && !B.glance) B.gaze.x = B.gaze.y = 0;
  if (p === 'along') {
    B.gaze.x = 0.5 * s(t * 1.1);
    B.gaze.y = 1;
  }
  B.amp += (B.ampT - B.amp) * Math.min(1, dt / 90);
  B.g.x += (B.gaze.x - B.g.x) * Math.min(1, dt / 170);
  B.g.y += (B.gaze.y - B.g.y) * Math.min(1, dt / 170);
  B.kick *= Math.exp(-dt / 130);
  const a = B.amp;
  if (!isStill() && !S0.dim) {
    const br = s((t * 6.283) / (A === 'sleep' ? 5.5 : 4.2));
    o.sy = (A === 'sleep' ? 0.04 : 0.016) * br * e;
    o.sx = -0.5 * o.sy;
    o.ly = B.kick * 3;
    o.lr = B.g.x * 1.2;
    if (A === 'rest') {
      o.hr = B.g.x * 4.5 + s(t * 0.7) * 0.9 * e;
      o.hx = B.g.x * 2;
      o.hy = B.g.y * 2.2 + br * 0.5 * e;
      o.lr = B.g.x * 0.7;
    }
    if (p === 'along') o.hy += Math.max(0, s(t * 7)) ** 4 * 0.9 * e; /* small nods as the words arrive */
    else if (p === 'connect') {
      o.hr += s(t * 5) * 3 * e;
      o.hy -= 1.4;
    } /* looks up, sways like a ring */ else if (p === 'muted') o.hy += 1.4;
    else if (p === 'think') {
      o.lr += s(t * 1.1) * 2.4 * e;
      o.lx = s(t * 1.1) * 0.8 * e;
    } else if (p === 'remember') {
      o.lr += s(t * 1.1) * 1.4 * e;
      o.ly += Math.max(0, s(t * 2.2)) ** 6 * 2.2 * e;
    } else if (p === 'phone') {
      o.ly += (s(t * 6.5) > 0.55 ? 1.1 : 0) * e;
      o.lr += s(t * 0.9) * 1.1 * e;
    } /* a tap now and then */ else if (p === 'type') {
      o.ly += (s(t * 21) > 0 ? 0.8 : 0) * (s(t * 1.7) > -0.3 ? 1 : 0) * e;
      o.lr += s(t * 1.7) * 0.9 * e;
    } /* fast bursts */ else if (p === 'scroll') {
      const q = (t * 0.75) % 1;
      o.ly += (q < 0.3 ? -q / 0.3 : -1 + (q - 0.3) / 0.7) * 2.4 * e;
      o.sy += (q < 0.3 ? q / 0.3 : 1 - (q - 0.3) / 0.7) * 0.025 * e;
    } else if (p === 'wait') {
      o.lr += s(t * 0.8) * 1.6 * e;
      o.ly += (s(t * 4.2) > 0.8 ? 0.8 : 0) * e;
    } else if (p === 'read') {
      const q = (t * 0.45) % 1,
        x = q < 0.85 ? (q / 0.85) * 2 - 1 : 1 - ((q - 0.85) / 0.15) * 2;
      o.lx = x * 3.6 * e;
      o.lr += x * 2.2 * e;
    } /* across the line, then back */ else if (p === 'search') {
      o.lx = s(t * 2.1) * 4 * e;
      o.lr += s(t * 2.1) * 3.2 * e;
    } else if (p === 'ask') {
      o.ly -= Math.abs(s(t * 2.6)) * 3.5 * e;
      fy = s(t * 2.6 + 1) * 5 * e;
      fr = s(t * 1.3) * 7 * e;
    } else if (p === 'urgent') {
      o.ly -= Math.abs(s(t * 5.5)) * 4.5 * e;
      o.lx = s(t * 22) * 0.4 * e;
      fy = s(t * 5.5 + 1) * 6 * e;
      fr = s(t * 11) * 9 * e;
      fs = 1 + 0.1 * s(t * 11) * e;
    } else if (p === 'hide') {
      o.lx = s(t * 40) * 0.55 * e * (s(t * 1.4) > 0 ? 1 : 0);
      fr = s(t * 5) * 5 * e;
    } else if (p === 'happy') {
      o.ly -= Math.abs(s(t * 4.4)) * 5 * e;
      o.sy += 0.03 * s(t * 8.8) * e;
      fs = 1 + 0.14 * s(t * 6) * e;
      fr = s(t * 3) * 10 * e;
    } else if (p === 'cheer') {
      o.ly -= Math.abs(s(t * 5.2)) * 9 * e;
      o.lr += s(t * 5.2) * 6 * e;
      o.sy += 0.04 * s(t * 10.4) * e;
      fs = 1 + 0.22 * s(t * 7) * e;
      fr = s(t * 4) * 16 * e;
    } else if (p === 'worry') {
      o.lx = s(t * 30) * 0.6 * e;
      fs = 1 + 0.06 * s(t * 7) * e;
    } else if (p === 'sleep') {
      o.lr += 1.2 * br * e;
      const q = (t * 0.3) % 1;
      fy = -q * 9;
      fo = q < 0.15 ? q / 0.15 : 1 - (q - 0.15) / 0.85;
      fs = 0.9 + q * 0.2;
    } else if (p === 'lost') {
      o.lr += s(t * 3) * 3 * e;
      fr = s(t * 2) * 3 * e;
    } else if (p === 'listen') {
      o.lr += 2 * e;
      fs = 1 + 0.06 * s(t * 2.5);
      fo = 0.5 + 0.2 * s(t * 2.5);
    } else if (p === 'hearing') {
      o.lr += (3 + a * 4) * e;
      o.ly -= a * 1.5;
      fs = 1 + a * 0.3;
      fo = 0.45 + a * 0.55;
    } else if (p === 'speak') {
      o.ly -= a * 4.5 * e;
      o.sy += a * 0.045 * e;
      o.lr += s(t * 3) * 1.6 * e;
      fs = 1 + a * 0.35;
      fo = 0.45 + a * 0.55;
    } else if (p === 'wave') {
      const w = Math.max(0, 1 - (t - B.wave) / 1.6);
      o.lr += s((t - B.wave) * 11) * 6 * w * e;
      fr = s((t - B.wave) * 11) * 10 * w;
    }
  }
  for (const k in o) el.style.setProperty('--' + k, o[k].toFixed(3));
  const fx = $('#bFx');
  if (fx && !fx.hidden) {
    fx.style.transform = `translateY(${fy.toFixed(2)}%) rotate(${fr.toFixed(2)}deg) scale(${fs.toFixed(3)})`;
    fx.style.opacity = fo.toFixed(2);
  }
}
function blink() {
  const el = $('#bear');
  if (!el) return;
  el.setAttribute('data-blink', '');
  setTimeout(() => el.removeAttribute('data-blink'), 130);
}
function blinkLoop() {
  setTimeout(
    () => {
      const el = $('#bear'),
        now = performance.now();
      if (el && !isStill() && B.eyes) {
        blink();
        if (Math.random() < 0.2) setTimeout(blink, 270);
      }
      if (el && B.pose === 'rest' && !B.typing && !isStill() && now - B.ptr > 3000 && Math.random() < 0.4) {
        B.glance = true;
        B.gaze = {
          x: (Math.random() < 0.5 ? -1 : 1) * (0.5 + Math.random() * 0.5),
          y: (Math.random() - 0.5) * 0.6,
        };
        setTimeout(() => {
          B.glance = false;
        }, 1400);
      }
      blinkLoop();
    },
    (2200 + Math.random() * 3200) / Math.max(0.35, B.energy),
  );
}
function wake() {
  clearTimeout(idleT);
  act('stretch');
  setPose('rest', true);
  setTimeout(blink, 300);
  setTimeout(blink, 680);
  if (!B.pinned) idle();
}
