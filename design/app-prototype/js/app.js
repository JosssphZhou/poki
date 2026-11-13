// Moving between screens, drawing the chats, and the flows a message starts (a question, a phone task).
function toIsland(hidden) {
  const p = ph();
  if (hidden || B.still) {
    p.dataset.at = 'gone';
    return Promise.resolve();
  }
  return act('crouch').then(() => {
    p.dataset.at = 'island';
    act('fly');
  });
}
function paint() {
  const p = ph();
  if (!p) return;
  p.dataset.theme = theme;
  S.look = theme === 'dark' ? 'Dark' : 'Light';
  {
    const m = MIXES[mi],
      K = 0.72,
      sv = (k, v) => p.style.setProperty(k, v);
    sv('--c-b0d', col(0.3, m.body[0], K * 0.85));
    sv('--c-b0', col(0.5, m.body[0], K));
    sv('--c-b0l', col(0.66, m.body[0], K));
    sv('--c-b1', col(0.72, m.body[1], K));
    sv('--c-b2', col(0.7, m.body[2], K));
    sv('--c-w0', col(0.72, m.warm[0], K));
    sv('--c-w1', col(0.8, m.warm[1], K));
  }
  const g = hue(MIXES[mi], theme === 'dark'),
    r = hue(MIXES[mi], true);
  for (const k in g) {
    p.style.setProperty('--g' + k, g[k]);
    p.style.setProperty('--r' + k, r[k]);
  }
  document
    .querySelectorAll('.side [data-theme]')
    .forEach((b) => b.setAttribute('aria-pressed', b.dataset.theme === theme));
  document.querySelectorAll('#dots button').forEach((b, i) => b.setAttribute('aria-pressed', i === mi));
  $('#pTheme').value = theme;
  const u = new URL(location);
  u.searchParams.set('mode', theme);
  u.searchParams.set('mix', mi + 1);
  history.replaceState(null, '', u);
}
function sync() {
  const p = ph(),
    d = p.dataset,
    busy = d.chat || d.call || d.away || d.set || d.ob;
  $('.home').inert = !!busy || px !== 0;
  $('.list').inert = !!busy || px !== -390;
  $('.chat').inert = !d.chat || !!d.away;
  $('.callui').inert = !d.call || !!d.away;
  $('.set').inert = !d.set;
  $('#ob').inert = !d.ob;
  $('.over').inert = !!busy;
  mind();
}
const AT0 = {
    c: [104, 16, 380, 16, 46],
    pr: [46, 46],
    pc: [104, 16, 380, 16],
    g: [19, 196, 1],
    b: [123, 328, 1.56],
  },
  AT1 = {
    c: [746, 20, 34, 212, 32],
    pr: [32, 32],
    pc: [746, 20, 34, 212],
    g: [74, 627, 0.3],
    b: [216, 747, 0.7],
  };
let morphT = null;
function setP(p, how) {
  const P = ph(),
    m = Math.max(0, Math.min(1, p)),
    L = (a, b) => (a + (b - a) * m).toFixed(2),
    mix = (k) => AT0[k].map((v, i) => L(v, AT1[k][i])),
    c = mix('c'),
    pc = mix('pc'),
    pr = mix('pr'),
    g = mix('g'),
    b = mix('b'),
    st = P.style;
  if (how === true) P.setAttribute('data-drag', '');
  else if (how !== 'drag') {
    P.setAttribute('data-morph', '');
    clearTimeout(morphT);
    morphT = setTimeout(() => P.removeAttribute('data-morph'), 520);
  }
  st.setProperty('--px', (-390 * p).toFixed(1) + 'px');
  ['--wt', '--wr', '--wb', '--wl'].forEach((k, i) => st.setProperty(k, c[i] + 'px'));
  st.setProperty('--clip', `inset(${c[0]}px ${c[1]}px ${c[2]}px ${c[3]}px round ${c[4]}px)`);
  st.setProperty(
    '--pclip',
    `inset(${pc[0]}px ${pc[1]}px ${pc[2]}px ${pc[3]}px round ${pr[0]}px ${pr[0]}px ${pr[1]}px ${pr[1]}px)`,
  );
  st.setProperty('--grest', `translate(${g[0]}px,${g[1]}px) scale(${g[2]})`);
  st.setProperty('--bx', b[0] + 'px');
  st.setProperty('--by', b[1] + 'px');
  st.setProperty('--bs', b[2]);
  st.setProperty('--so', Math.max(0, 1 - m * 3).toFixed(2));
  st.setProperty('--fo', Math.max(0, (m - 0.55) / 0.45).toFixed(2));
  st.setProperty('--ho', Math.max(0, 1 - m * 1.3).toFixed(2));
  if (how === 'drag') return;
  px = Math.round(-390 * p);
  P.dataset.pg = m > 0.5 ? 'chats' : 'home';
  if (how === true) {
    void P.offsetWidth;
    requestAnimationFrame(() => P.removeAttribute('data-drag'));
  }
  sync();
}
function setPx(v, instant) {
  setP(-v / 390, instant ? true : undefined);
}
function drawList() {
  drawList0();
  if (S.conn !== 'ok')
    $('#rows').insertAdjacentHTML(
      'afterbegin',
      `<button class="l-warn" data-go="conn"><i class="mk no">!</i><span><b>Poki can’t use this iPhone</b><small>UI Automation is switched off. Fix it</small></span><i class="chev">${I.go}</i></button>`,
    );
}
function drawList0() {
  const f = ($('#find').value || '').trim().toLowerCase(),
    rows = CHATS.map((c, i) => ({ c, i })).filter(
      (o) => o.c.T.length && (!f || o.c.title.toLowerCase().includes(f)),
    );
  let day = '';
  $('#rows').innerHTML = rows.length
    ? rows
        .map(({ c, i }) => {
          const last = [...c.T].reverse().find((m) => m.k === 'poki' || m.k === 'fail'),
            cl = c.T.find((m) => m.k === 'talk'),
            h = c.day !== day ? `<h3>${(day = c.day)}</h3>` : '';
          return `${h}<button class="l-row" data-open="${i}"><span><b>${esc(c.title)}</b><small>${cl ? WAVE13 : ''}${esc(last ? last.t : cl ? (cl.out.length ? cl.out.map((o) => o.b).join(', ') : cl.t) : '')}</small></span>${c.flag ? `<img src="${SPR[ST[c.flag].art].full}" alt="Poki needs you">` : ''}</button>`;
        })
        .join('')
    : `<div class="l-none">${f ? `No chat is called “${esc($('#find').value.trim())}”.` : 'No chats yet. Write or talk to start one.'}</div>`;
}
function drawThread() {
  const th = $('#thread');
  if (!th || !cur) return;
  $('#cTitle').textContent = cur.title;
  th.innerHTML = cur.T.map((m, i) =>
    m.k === 'ask'
      ? `<div class="cask"><b>${esc(m.h)}</b><p>${esc(m.q)}</p><div><button data-act="deny">${esc(m.no)}</button><button class="pri" data-act="allow">Allow</button></div><small>Waiting for you · 1:52 left</small></div>`
      : m.k === 'fail'
        ? `<div class="poki">${esc(m.t)}</div><button class="again" data-toast="Trying again is not part of this prototype">Try again</button>`
        : m.k === 'you'
          ? `<div class="you">${m.mic ? MICI : ''}${esc(m.t)}</div>`
          : m.k === 'poki'
            ? `<div class="poki">${esc(m.t)}</div>`
            : m.k === 'talk'
              ? tkCard(m)
              : m.k === 'use'
                ? useCard(m, i)
                : '',
  ).join('');
  th.scrollTop = th.scrollHeight;
  paintTalk();
}
function idle() {
  clearTimeout(idleT);
  if (EMBED) return;
  const pill = ph().dataset.pg === 'chats';
  idleMode = pill ? 'pill' : 'home';
  /* on the New chat pill Poki is busy with its own phone: scrolls, types, looks up, has a think, goes looking for something, and round again */
  const seq = pill
    ? [
        ['scroll', 5200],
        ['rest', 1500],
        ['type', 3200],
        ['along', 1800],
        ['scroll', 6400],
        ['think', 2600],
        ['scroll', 4600],
        ['search', 3000],
        ['rest', 1400],
      ]
    : [
        ['rest', 7000],
        ['phone', 4200],
        ['rest', 6500],
        ['think', 3600],
        ['rest', 9000],
        ['sleep', 0],
      ];
  let n = 0;
  if (pill) setPose(seq[0][0]);
  const loop = () => {
    idleT = setTimeout(
      () => {
        if (B.typing) return loop();
        n++;
        if (pill) n %= seq.length;
        setPose(seq[n][0]);
        if (pill && n % 3 === 1) act(['wiggle', 'stretch', 'nod'][((n / 3) | 0) % 3]);
        if (seq[n][1]) loop();
      },
      seq[n][1] / Math.max(0.4, B.energy),
    );
  };
  loop();
}
function mind() {
  const d = ph().dataset,
    free = !(d.chat || d.away || d.set || d.ob || d.voice || d.talk || d.call) && d.at === 'home';
  if (EMBED) {
    if (free && d.pg === 'chats') setPose('scroll', true);
    return;
  }
  if (!free || B.pinned || B.typing) return;
  if (d.pg === 'chats' && idleMode !== 'pill') idle();
  else if (d.pg !== 'chats' && idleMode === 'pill') {
    setPose('rest');
    idle();
  }
}
function clearCall() {
  clearInterval(tick);
  const p = ph();
  delete p.dataset.call;
  delete p.dataset.hear;
  B.ampT = 0;
  p.style.setProperty('--amp', 0);
  $('#cState').textContent = '';
}
function rest() {
  stopTimers();
  clearCall();
  const p = ph();
  const was = p.dataset.at;
  B.pinned = false;
  hush();
  p.style.setProperty('--flow', 0.3);
  delete p.dataset.islx;
  delete p.dataset.kb;
  delete p.dataset.ob;
  delete p.dataset.set;
  delete p.dataset.away;
  delete p.dataset.chat;
  delete p.dataset.write;
  p.dataset.at = 'home';
  if (was === 'island') act('land');
  ISL.go('rest');
  cur = null;
  job = null;
  CHATS = CHATS.filter((c) => c.T.length);
  setPx(0);
  setPose('rest', true);
  idle();
}
function openChat(c) {
  stopTimers();
  clearCall();
  const p = ph();
  cur = c;
  delete p.dataset.islx;
  delete p.dataset.away;
  delete p.dataset.write;
  p.dataset.chat = '1';
  p.dataset.at = 'gone';
  ISL.go('rest');
  drawThread();
  sync();
}
function closeChat() {
  hush();
  stopTimers();
  const p = ph();
  CHATS = CHATS.filter((c) => c.T.length);
  drawList();
  setPx(-390, true);
  delete p.dataset.chat;
  p.dataset.at = 'home';
  cur = null;
  setPose('rest', true);
  sync();
}
function call() {
  stopTimers();
  const p = ph();
  if (!cur) cur = newChat();
  delete p.dataset.write;
  setPx(0, true);
  p.dataset.at = 'home';
  p.dataset.call = '1';
  delete p.dataset.chat;
  sync();
  t0 = Date.now();
  $('#cTime').textContent = '0:00';
  clearInterval(tick);
  tick = setInterval(() => {
    const e = $('#cTime');
    if (e) e.textContent = fmt(Date.now() - t0);
  }, 500);
  let who = 'you';
  const set = () => {
    p.dataset.hear = who;
    setPose(who === 'you' ? 'listen' : 'speak');
    $('#cState').textContent = who === 'you' ? 'Listening' : 'Poki is speaking';
  };
  const amp = () => {
    B.ampT = who === 'you' ? 0.2 + Math.random() * 0.8 : 0.25 + Math.random() * 0.75;
    p.style.setProperty('--amp', (who === 'you' ? B.ampT : B.ampT * 0.45).toFixed(2));
    later(amp, 160);
  };
  setPose('connect');
  $('#cState').textContent = 'Connecting';
  later(() => {
    set();
    later(() => {
      setPose('hearing');
      amp();
    }, 900);
    later(() => {
      who = 'poki';
      set();
      later(() => {
        if (cur.title === 'New chat') cur.title = 'Lunch order';
        task();
      }, 1900);
    }, 4100);
  }, 1100);
}
function endCall(write) {
  if (!ph().dataset.call) return;
  cur.T.push({ k: 'call', t: 'Call · ' + fmt(Date.now() - t0) });
  if (cur.title === 'New chat') cur.title = 'Quick call';
  openChat(cur);
  if (write) later(() => $('#ask2').focus(), 480);
}
function task() {
  stopTimers();
  const p = ph(),
    inChat = !!p.dataset.chat,
    inCall = !!p.dataset.call;
  delete p.dataset.hear;
  B.ampT = 0;
  B.pinned = false;
  p.style.setProperty('--amp', 0);
  if (!inChat && !inCall) setPose('think');
  job = { step: 0, st: 'think', inCall };
  later(
    () => {
      $('#away').innerHTML =
        `<h3>Lunch</h3><div class="sub">Your usual, from Green Bowl</div><div class="row" data-r="0"><i></i><div class="t">Chicken grain bowl<span>Large, extra greens</span></div><span class="ck" aria-hidden="true">✓</span></div><div class="row" data-r="1"><i></i><div class="t">Sparkling water<span>Lime</span></div><span class="ck" aria-hidden="true">✓</span></div><div class="row"><i></i><div class="t">Miso soup<span>Small</span></div><span class="ck" aria-hidden="true">✓</span></div><button class="pay" data-act="yours"><span>Pay</span><span>$14.20</span></button>`;
      if (inChat) setPx(0, true);
      p.dataset.away = '1';
      job.st = 'work';
      sync();
      toIsland(inChat);
      later(work, inChat ? 80 : 640);
    },
    inChat ? 350 : inCall ? 200 : 900,
  );
}
function work() {
  const j = job;
  if (j.st !== 'work') return;
  setPose(['read', 'scroll', 'type'][j.step]);
  isl(['l1', 'l2', 'l3'][j.step]);
  const r = $(`.away .row[data-r="${Math.min(j.step, 1)}"]`);
  later(() => {
    if (j.st !== 'work') return;
    setPose('phone');
    r.setAttribute('data-press', '');
    later(() => {
      r.removeAttribute('data-press');
      if (j.step < 2) r.setAttribute('data-in', '');
    }, 260);
  }, 700);
  later(() => {
    if (j.st !== 'work') return;
    if (j.step < 2) {
      j.step++;
      work();
    } else {
      j.st = 'yours';
      setPose('ask');
      isl('pay');
      $('.pay').setAttribute('data-on', '');
      later(() => {
        if (j.st === 'yours') setPose('urgent');
      }, 5000);
    }
  }, 1900);
}
function done() {
  stopTimers();
  job.st = 'done';
  setPose('happy');
  ISL.done('Ordered');
  if (job.inCall) cur.T.push({ k: 'call', t: 'Call · ' + fmt(Date.now() - t0) });
  cur.T.push(useOf('lunch'), { k: 'poki', t: 'Ordered. It arrives at 12:40.' });
  later(() => openChat(cur), 1700);
}
function question() {
  stopTimers();
  const p = ph(),
    inChat = !!p.dataset.chat;
  delete p.dataset.hear;
  B.ampT = 0;
  B.pinned = false;
  p.style.setProperty('--amp', 0);
  if (!inChat) setPose('think');
  const j = (job = { step: 0, st: 'look' });
  later(
    () => {
      $('#away').innerHTML = AWAY.cal();
      if (inChat) setPx(0, true);
      p.dataset.away = '1';
      sync();
      toIsland(inChat);
      later(
        () => {
          if (j.st !== 'look') return;
          setPose('read');
          isl('c1');
          later(() => {
            if (j.st === 'look') isl('c2');
          }, 1300);
        },
        inChat ? 80 : 640,
      );
      later(
        () => {
          if (j.st !== 'look') return;
          j.st = 'done';
          setPose('happy');
          ISL.done('Done');
          cur.T.push(useOf('cal'), {
            k: 'poki',
            t: 'Two things: the dentist at 2:30, at Harbor Dental on Market Street, and spin class at 7:30.',
          });
          later(() => openChat(cur), 1500);
        },
        inChat ? 2600 : 3200,
      );
    },
    inChat ? 350 : 900,
  );
}
function send(v, mic) {
  const ask = /\?$|^(what|when|who|where|how|why|is|are|do|does|did|can)\b/i.test(v);
  if (!cur) cur = newChat();
  cur.T.push({ k: 'you', t: v, mic });
  if (cur.title === 'New chat') cur.title = ask ? 'This afternoon' : 'Lunch order';
  if (ph().dataset.chat) drawThread();
  ask ? question() : task();
}
function toast(t) {
  const e = $('#toast');
  e.textContent = t;
  e.setAttribute('data-on', '');
  clearTimeout(toastT);
  toastT = setTimeout(() => e.removeAttribute('data-on'), 1800);
}
function hello() {
  clearTimeout(idleT);
  B.pinned = false;
  setPose('wave', true);
  B.wave = B.t;
  act('poke');
  idleT = setTimeout(() => {
    setPose('rest');
    idle();
  }, 1900);
}
function pin(p) {
  const P = ph();
  if (P.dataset.call || P.dataset.away || P.dataset.chat || px !== 0) rest();
  stopTimers();
  B.pinned = true;
  if (B.pose === p) act('pop');
  setPose(p);
}
function move(n) {
  const P = ph();
  if (P.dataset.call || P.dataset.away || P.dataset.chat || px !== 0) rest();
  if (n === 'wave') return hello();
  if (n === 'wake') {
    stopTimers();
    B.pinned = true;
    setPose('sleep');
    later(() => {
      wake();
      later(() => {
        B.pinned = false;
        idle();
      }, 1200);
    }, 3000);
    return;
  }
  if (n === 'jump') {
    stopTimers();
    B.pinned = true;
    setPose('phone', true);
    toIsland(false).then(() => later(() => isl('l1'), 420));
    later(() => {
      P.dataset.at = 'home';
      act('land');
      ISL.go('rest');
      later(() => {
        setPose('happy');
        later(() => {
          B.pinned = false;
          setPose('rest');
          idle();
        }, 1700);
      }, 420);
    }, 2700);
    return;
  }
  act(n);
}
document.addEventListener('pointermove', (e) => {
  const el = $('#bear'),
    P = ph();
  if (!el || !P || P.dataset.at !== 'home' || B.pose === 'along' || drag) return;
  const r = el.getBoundingClientRect(),
    c = (v) => Math.max(-1, Math.min(1, v)),
    dx = e.clientX - r.left - r.width / 2,
    dy = e.clientY - r.top - r.height / 2;
  B.gaze.x = c(dx / 220);
  B.gaze.y = c(dy / 260);
  B.ptr = performance.now();
  if (B.pose === 'sleep' && !B.pinned && Math.hypot(dx, dy) < 110) wake();
});
document.addEventListener('focusin', (e) => {
  if (e.target.id === 'ask') {
    B.typing = true;
    B.pinned = false;
    clearTimeout(idleT);
    setPose('along', true);
  }
});
document.addEventListener('focusout', (e) => {
  if (e.target.id === 'ask') {
    B.typing = false;
    if (B.pose === 'along') {
      setPose('rest', true);
      idle();
    }
  }
});
document.addEventListener('input', (e) => {
  if (e.target.id === 'ask') B.kick = 1;
});
