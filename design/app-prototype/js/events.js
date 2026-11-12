// The demo runs in the side panel, dragging between pages, and every click and key.
const RUN = {
  rest: () => rest(),
  talk: () => {
    rest();
    live(true);
  },
  dictate: () => {
    rest();
    dictate(true);
  },
  call: () => {
    rest();
    live(true);
  },
  task: () => {
    rest();
    send('Reorder my usual lunch');
  },
  ask: () => {
    rest();
    send('What’s on this afternoon?');
  },
  chats: () => {
    rest();
    drawList();
    setPx(-390);
  },
  hear: () => pin('hearing'),
  jump: () => move('jump'),
};

/* drag the page sideways, 1:1 with the finger */
let drag = null,
  swallow = false;
document.addEventListener('pointerdown', (e) => {
  const p = ph();
  if (
    !p ||
    !e.target.closest('#phone') ||
    e.target.closest('input') ||
    p.dataset.call ||
    p.dataset.away ||
    p.dataset.chat ||
    p.dataset.set ||
    p.dataset.ob ||
    p.dataset.at !== 'home'
  )
    return;
  drag = { x: e.clientX, y: e.clientY, base: px, on: false, lx: e.clientX, lt: e.timeStamp, v: 0 };
});
document.addEventListener('pointermove', (e) => {
  if (!drag) return;
  const s = +getComputedStyle(document.documentElement).getPropertyValue('--s') || 1,
    dx = (e.clientX - drag.x) / s,
    dy = (e.clientY - drag.y) / s;
  if (!drag.on) {
    if (Math.abs(dx) < 8 || Math.abs(dx) < Math.abs(dy)) return;
    drag.on = true;
    ph().setAttribute('data-drag', '');
    if (drag.base === 0) drawList();
  }
  let v = drag.base + dx;
  if (v > 0) v = v * 0.25;
  if (v < -390) v = -390 + (v + 390) * 0.25;
  setP(-v / 390, 'drag');
  drag.v = (e.clientX - drag.lx) / Math.max(1, e.timeStamp - drag.lt) / s;
  drag.lx = e.clientX;
  drag.lt = e.timeStamp;
  drag.cur = v;
});
const drop = () => {
  if (!drag) return;
  const d = drag;
  drag = null;
  if (!d.on) return;
  ph().removeAttribute('data-drag');
  swallow = true;
  setTimeout(() => (swallow = false), 60);
  const to = d.v < -0.35 ? -390 : d.v > 0.35 ? 0 : d.cur < -195 ? -390 : 0;
  if (to === 0) cur = null;
  setPx(to);
};
document.addEventListener('pointerup', drop);
document.addEventListener('pointercancel', drop);
document.addEventListener(
  'click',
  (e) => {
    if (swallow) {
      e.stopPropagation();
      e.preventDefault();
    }
  },
  true,
);

document.addEventListener('click', (e) => {
  const p = ph();
  if (!p || !e.target.closest('#phone')) return;
  const b = e.target.closest('[data-act]'),
    a = b && b.dataset.act,
    say = e.target.closest('[data-say]'),
    row = e.target.closest('[data-open]'),
    tt = e.target.closest('[data-toast]');
  if (e.target.closest('#bear')) {
    if (p.dataset.ob) return;
    if (p.dataset.pg === 'chats' && !p.dataset.call) return rest();
    if (p.dataset.at === 'home' && !p.dataset.call) hello();
    return;
  }
  const go = e.target.closest('[data-go]'),
    tog = e.target.closest('[data-tog]'),
    pick = e.target.closest('[data-pick]'),
    mixb = e.target.closest('[data-mix]');
  if (go) return openSet(go.dataset.go);
  if (tog) {
    S[tog.dataset.tog] = !S[tog.dataset.tog];
    return drawSet();
  }
  if (mixb) {
    mi = +mixb.dataset.mix;
    paint();
    return p.dataset.ob ? ob(obi) : drawSet();
  }
  if (pick) {
    S[pick.dataset.pick] = pick.dataset.val;
    if (pick.dataset.pick === 'look') {
      theme = S.look === 'Dark' ? 'dark' : 'light';
      paint();
    }
    return p.dataset.ob ? ob(obi) : drawSet();
  }
  if (say) return send(say.dataset.say);
  if (row) return openChat(CHATS[+row.dataset.open]);
  if (tt) return toast(tt.dataset.toast);
  if (a === 'useopen') {
    const m = cur.T[+b.dataset.i],
      th = $('#thread'),
      y = th.scrollTop;
    m.open = !m.open;
    drawThread();
    th.scrollTop = y;
    const nb = th.querySelector(`[data-act=useopen][data-i="${b.dataset.i}"]`);
    if (nb) nb.focus({ preventScroll: true });
  } else if (a === 'voice') voice();
  else if (a === 'dictate') dictate();
  else if (a === 'live') live();
  else if (a === 'endtalk') endTalk();
  else if (a === 'tmute') tmute(b);
  else if (a === 'settings') openSet('root');
  else if (a === 'setback') setBack();
  else if (a === 'replay') {
    delete p.dataset.set;
    ob(0);
  } else if (a === 'fix') {
    S.conn = 'ok';
    drawSet();
    toast('UI Automation is on');
  } else if (a === 'obnext') {
    if (obi < OB.length - 1) ob(obi + 1);
    else rest();
  } else if (a === 'obback') ob(Math.max(0, obi - 1));
  else if (a === 'allow' || a === 'deny') {
    cur.T.pop();
    cur.T.push({ k: 'poki', t: a === 'allow' ? 'Sent.' : 'Okay, I didn’t send it.' });
    drawThread();
  } else if (a === 'call') call();
  else if (a === 'hang') endCall();
  else if (a === 'keys') endCall(true);
  else if (a === 'mute') {
    const on = b.getAttribute('aria-pressed') !== 'true';
    b.setAttribute('aria-pressed', on);
    if (on) {
      B.back = B.pose;
      setPose('muted');
    } else setPose(B.back && B.back !== 'muted' ? B.back : 'listen');
  } else if (a === 'chats') {
    drawList();
    setPx(-390);
  } else if (a === 'home') rest();
  else if (a === 'back') closeChat();
  else if (a === 'write') {
    p.dataset.write = '1';
    setTimeout(() => $('#ask').focus(), 30);
  } else if (a === 'yours') {
    if (job && job.st === 'yours') done();
  }
});
document.addEventListener('submit', (e) => {
  e.preventDefault();
  const i = e.target.querySelector('input'),
    v = i.value.trim();
  if (!v) return i.focus();
  i.value = '';
  e.target.removeAttribute('data-typing');
  i.blur();
  send(v);
});
document.addEventListener('focusout', (e) => {
  if (e.target.id === 'ask' && !e.target.value && ph())
    setTimeout(() => {
      if (document.activeElement !== e.target) delete ph().dataset.write;
    }, 120);
});
document.addEventListener('input', (e) => {
  if (e.target.id === 'find') drawList();
  const f = e.target.closest('.comp');
  if (f) f.toggleAttribute('data-typing', !!e.target.value.trim());
});
document.addEventListener('keydown', (e) => {
  if (e.target.id === 'bear' && (e.key === 'Enter' || e.key === ' ')) {
    e.preventDefault();
    e.target.click();
  }
});
