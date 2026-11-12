// Speaking: the two-row menu, dictation, and a live talk with Poki.
let talkT = null,
  tk = null,
  tkI = null;
/* one short talk: who has the floor, what Poki says (or how long you speak), and what comes of it */
const TALK = [
  ['poki', 'Hi. What do you need?', 1500, []],
  ['you', 2600],
  ['poki', 'This afternoon you have the dentist at 2:30 and spin class at 7:30.', 3400, [0]],
  ['you', 2800],
  ['poki', 'Done. Spin class is now at 8, and I’ll remind you at 2 to leave for the dentist.', 4000, [1, 2]],
  ['you', 0],
];
const dur = (ms) => {
  const n = Math.max(1, Math.round(ms / 1000));
  return n < 60 ? `${n} s` : `${(n / 60) | 0} min ${n % 60} s`;
};
const comp = () => $(ph().dataset.chat ? '#ask2' : '#ask').closest('.comp');
function menu(on) {
  const me = comp();
  document.querySelectorAll('.comp').forEach((f) => {
    const o = !!on && f === me;
    f.toggleAttribute('data-menu', o);
    f.querySelector('.vmenu').inert = !o;
    f.querySelector('[data-act=voice]').setAttribute('aria-expanded', o);
  });
  if (!on && document.activeElement && document.activeElement.closest('.vmenu'))
    document.activeElement.blur();
  if (on) me.querySelector('.vmenu button').focus({ preventScroll: true });
}
function unhear() {
  const P = ph();
  clearTimeout(talkT);
  if (!P.dataset.voice) return false;
  delete P.dataset.voice;
  document.querySelectorAll('.comp input').forEach((i) => {
    if (i.dataset.ph) {
      i.placeholder = i.dataset.ph;
      delete i.dataset.ph;
    }
  });
  return true;
}
/* everything spoken stops: used when the page is reset or left */
function hush() {
  const P = ph();
  clearInterval(tkI);
  unhear();
  menu(false);
  if (tk) {
    tk.m.live = 0;
    tk.m.d = dur(Date.now() - tk.t0);
    tk.m.t = 'Talked for ' + tk.m.d;
    tk = null;
  }
  delete P.dataset.talk;
  delete P.dataset.hear;
  delete P.dataset.mute;
  document.querySelectorAll('[data-act=tmute]').forEach((b) => b.setAttribute('aria-pressed', 'false'));
}
function voice() {
  if (ph().dataset.voice) return endDictate();
  menu(!comp().hasAttribute('data-menu'));
}
/* dictation: what you say becomes text in the input. Nothing is sent until you send it, and it is saved like anything typed. */
function dictate(auto) {
  const P = ph(),
    inChat = !!P.dataset.chat,
    inp = $(inChat ? '#ask2' : '#ask'),
    f = inp.closest('.comp'),
    words = (inChat ? 'And can I walk between the two?' : 'Reorder my usual lunch').split(' '),
    had = inp.value.trim();
  let n = 0;
  menu(false);
  stopTimers();
  P.dataset.voice = 'dictate';
  inp.dataset.ph = inp.placeholder;
  inp.placeholder = 'Listening';
  B.pinned = false;
  if (!inChat) setPose('along');
  const step = () => {
    if (n === words.length) {
      talkT = setTimeout(() => {
        endDictate();
        if (auto) later(() => f.requestSubmit(), 700);
      }, 1100);
      return;
    }
    n++;
    inp.value = (had ? had + ' ' : '') + words.slice(0, n).join(' ');
    f.setAttribute('data-typing', '');
    inp.scrollLeft = 9999;
    talkT = setTimeout(step, 230 + Math.random() * 190);
  };
  talkT = setTimeout(step, 1000);
}
function endDictate() {
  if (!unhear()) return;
  if (!ph().dataset.chat) {
    setPose('rest');
    idle();
  }
}
/* talking with Poki: live, out loud. On the front page it happens in the window; inside a chat the card that will remain is built as you talk. */
function live(auto) {
  const P = ph(),
    inChat = !!P.dataset.chat;
  menu(false);
  unhear();
  stopTimers();
  delete P.dataset.kb;
  if (!cur) cur = newChat();
  tk = {
    t0: Date.now(),
    who: 'poki',
    say: '',
    inChat,
    auto,
    m: { k: 'talk', live: 1, t: 'Talking now', out: [] },
  };
  if (inChat) {
    cur.T.push(tk.m);
    drawThread();
  } else $('#lvOut').innerHTML = '';
  P.dataset.talk = '1';
  B.pinned = false;
  clearInterval(tkI);
  tkI = setInterval(paintTalk, 500);
  sync();
  turn(0);
}
function turn(i) {
  if (!tk) return;
  const P = ph(),
    [who, a, ms, outs] = TALK[i],
    flow = (v) => P.style.setProperty('--flow', v);
  clearTimeout(talkT);
  tk.who = who;
  P.dataset.hear = who;
  const amp = () => {
    B.ampT = 0.25 + Math.random() * 0.75;
    flow((0.7 + B.ampT * 0.6).toFixed(2));
    talkT = setTimeout(amp, 380);
  };
  amp();
  if (who === 'you') {
    if (!tk.inChat) setPose(tk.mute ? 'muted' : 'hearing');
    paintTalk();
    let left = a;
    const wait = () => {
      if (!tk) return;
      if (!tk.mute) left -= 200;
      if (left <= 0) turn(i + 1);
      else later(wait, 200);
    };
    if (a) wait();
    else if (tk.auto) later(endTalk, 1800);
    return;
  }
  if (!tk.inChat) setPose('speak');
  const w = a.split(' '),
    per = Math.max(90, (ms - 500) / w.length);
  let n = 0;
  tk.say = '';
  const word = () => {
    if (!tk) return;
    n++;
    tk.say = w.slice(0, n).join(' ');
    paintTalk();
    if (n < w.length) return later(word, per);
    outs.forEach((o) => tk.m.out.push(OUT[o]));
    if (outs.length && tk.inChat) drawThread();
    paintTalk();
    later(() => turn(i + 1), 800);
  };
  later(word, 260);
}
function paintTalk() {
  if (!tk) return;
  const P = ph(),
    t = fmt(Date.now() - tk.t0),
    poki = tk.who === 'poki',
    who = poki ? 'Poki' : tk.mute ? 'You’re muted' : 'Listening',
    A = (q, fn) => P.querySelectorAll(q).forEach(fn);
  A('.tkT', (e) => (e.textContent = t));
  A('.tkS', (e) => (e.textContent = poki ? 'Speaking' : tk.mute ? 'Muted' : 'Listening'));
  A('.lvWho', (e) => (e.textContent = who));
  A('.lvSay', (e) => {
    if (e.textContent !== tk.say) e.textContent = tk.say;
  });
  const ul = $('#lvOut'),
    out = tk.inChat ? [] : tk.m.out;
  if (ul.children.length > out.length) ul.innerHTML = '';
  for (let k = ul.children.length; k < out.length; k++)
    ul.insertAdjacentHTML('beforeend', `<li><i>${out[k].a ? TXT : CHK}</i>${esc(out[k].b)}</li>`);
  A('.tkc[data-live] img', (e) => {
    const src = SPR[poki ? 'speak' : 'listen'].full;
    if (e.getAttribute('src') !== src) e.src = src;
  });
}
function tmute(b) {
  if (!tk) return;
  tk.mute = !tk.mute;
  const P = ph();
  document.querySelectorAll('[data-act=tmute]').forEach((x) => {
    x.setAttribute('aria-pressed', tk.mute);
    x.setAttribute('aria-label', tk.mute ? 'Unmute' : 'Mute');
  });
  if (tk.mute) P.dataset.mute = '1';
  else delete P.dataset.mute;
  if (tk.who === 'you' && !tk.inChat) setPose(tk.mute ? 'muted' : 'hearing');
  paintTalk();
}
function endTalk() {
  if (!tk) return;
  const P = ph(),
    m = tk.m,
    inChat = tk.inChat;
  hush();
  stopTimers();
  B.ampT = 0;
  P.style.setProperty('--flow', 0.3);
  if (cur.title === 'New chat') cur.title = m.out.length ? 'This afternoon' : 'Talk with Poki';
  if (inChat) {
    drawThread();
    sync();
    return;
  }
  cur.T.push(m);
  setPose('happy');
  later(() => openChat(cur), 700);
}
const talk = () => live(true);
document.addEventListener('click', (e) => {
  if (ph() && !e.target.closest('.vmenu,[data-act=voice]')) menu(false);
});
document.addEventListener('keydown', (e) => {
  const f = document.querySelector('.comp[data-menu]');
  if (!f) return;
  if (e.key === 'Escape') {
    menu(false);
    f.querySelector('[data-act=voice]').focus();
  } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    const bs = [...f.querySelectorAll('.vmenu button')];
    bs[
      (bs.indexOf(document.activeElement) + (e.key === 'ArrowDown' ? 1 : bs.length - 1)) % bs.length
    ].focus();
  }
});
const talkSc = (who, say, out, inChat) => {
  const P = ph();
  if (!cur) cur = newChat();
  tk = { t0: Date.now() - 42000, who, say, inChat, m: { k: 'talk', live: 1, t: 'Talking now', out } };
  if (inChat) {
    cur.T.push(tk.m);
    drawThread();
  }
  P.dataset.talk = '1';
  P.dataset.hear = who;
  B.pinned = true;
  if (!inChat) setPose(who === 'you' ? 'hearing' : 'speak', true);
  P.style.setProperty('--flow', 1);
  paintTalk();
  sync();
};
