// The other apps Poki works in, and every frame as a state you can jump to (?scene=… or ?frame=…).
const AWAY = {
  cal: () =>
    `<h3>Today</h3><div class="sub">Calendar</div><div class="row"><i></i><div class="t">Dentist<span>2:30 PM · Harbor Dental, Market Street</span></div></div><div class="row"><i></i><div class="t">Spin class<span>7:30 PM · Studio 4</span></div></div>`,
  lunch: () =>
    `<h3>Lunch</h3><div class="sub">Your usual, from Green Bowl</div><div class="row" data-in><i></i><div class="t">Chicken grain bowl<span>Large, extra greens</span></div><span class="ck" aria-hidden="true">✓</span></div><div class="row" data-in><i></i><div class="t">Sparkling water<span>Lime</span></div><span class="ck" aria-hidden="true">✓</span></div><div class="row"><i></i><div class="t">Miso soup<span>Small</span></div><span class="ck" aria-hidden="true">✓</span></div><button class="pay" data-on><span>Pay</span><span>$14.20</span></button>`,
  msg: () =>
    `<h3>Mia</h3><div class="sub">Messages</div><div class="am them">Are you close?</div><div class="am them">We got the table by the window.</div><div class="afield" style="position:absolute;left:20px;right:20px;bottom:44px">Running ten minutes late.<i>↑</i></div>`,
  login: () =>
    `<h3>Sign in</h3><div class="sub">To see your orders</div><div class="afield sq">you@example.com</div><div class="afield sq dim foc">Password</div><button class="pay" data-on style="position:static;width:100%;margin-top:8px"><span>Sign in</span><span></span></button>`,
};
const base = () => {
  S.conn = 'ok';
  CHATS = seed();
  $('#find').value = '';
  rest();
  stopTimers();
};
const chatSc = (title, T) => () => {
  base();
  const c = { title, day: 'Today', T };
  CHATS.unshift(c);
  setP(1, true);
  openChat(c);
  $('#thread').scrollTop = 0;
};
const callSc = (st, label, time) => () => {
  base();
  const P = ph();
  cur = newChat();
  P.dataset.call = '1';
  if (st !== 'connect' && st !== 'lost') P.dataset.hear = st === 'speak' ? 'poki' : 'you';
  B.pinned = true;
  setPose(st, true);
  $('#cState').textContent = label;
  $('#cTime').textContent = time;
  $('[data-act=mute]').setAttribute('aria-pressed', st === 'muted');
  sync();
};
const taskSc = (app, k, how) => () => {
  base();
  const P = ph();
  cur = newChat();
  cur.T.push({
    k: 'you',
    t:
      app === 'lunch'
        ? 'Reorder my usual lunch'
        : app === 'msg'
          ? 'Tell Mia I’m running ten minutes late'
          : 'Get a refund for the blue jacket I returned last week',
  });
  job = { step: 2, st: how === 'held' ? 'work' : 'scene' };
  $('#away').innerHTML = AWAY[app]();
  P.dataset.away = '1';
  B.pinned = true;
  if (k === 'ask' || k === 'yours' || k === 'fail') P.dataset.islx = k === 'ask' ? 'allow' : k;
  if (how === 'quiet' || how === 'black') ISL.opt(how === 'quiet' ? { mode: 'quiet' } : { mat: 'black' });
  if (k === 'done') {
    P.dataset.at = 'gone';
    ISL.done('Ordered');
  } else isl(k);
  if (how === 'held') ISL.hold();
  sync();
};
const setSc = (pg, conn) => () => {
  base();
  S.conn = conn || 'ok';
  drawList();
  setP(1, true);
  stack = [];
  delete ph().dataset.set;
  openSet(pg);
};
const SC = {
  'ob-welcome': () => {
    base();
    ob(0);
  },
  'ob-light': () => {
    base();
    ob(1);
  },
  'ob-setup': () => {
    base();
    ob(2);
  },
  'ob-step': () => {
    base();
    ob(3);
  },
  'ob-model': () => {
    base();
    ob(4);
  },
  'ob-voice': () => {
    base();
    ob(5);
  },
  'ob-ready': () => {
    base();
    ob(6);
  },
  home: () => base(),
  'home-typing': () => {
    base();
    ph().dataset.kb = '1';
    $('#ask').value = 'Reorder my usual lu';
    $('#ask').closest('form').setAttribute('data-typing', '');
    B.pinned = true;
    setPose('along', true);
  },
  'to-chats': () => {
    base();
    drawList();
    setP(0.5, true);
  },
  chats: () => {
    base();
    drawList();
    setP(1, true);
  },
  'chats-search': () => {
    base();
    $('#find').value = 'li';
    drawList();
    setP(1, true);
  },
  'chats-empty': () => {
    base();
    CHATS = [];
    drawList();
    setP(1, true);
  },
  'chats-alert': () => {
    base();
    S.conn = 'warn';
    drawList();
    setP(1, true);
  },
  'chat-answer': chatSc('This afternoon', [
    { k: 'you', t: 'What’s on this afternoon?' },
    useOf('cal'),
    {
      k: 'poki',
      t: 'Two things: the dentist at 2:30, at Harbor Dental on Market Street, and spin class at 7:30.',
    },
  ]),
  'chat-done': chatSc('Lunch order', [
    { k: 'you', t: 'Reorder my usual lunch' },
    useOf('lunch'),
    { k: 'poki', t: 'Ordered. It arrives at 12:40.' },
  ]),
  'chat-steps': chatSc('Lunch order', [
    { k: 'you', t: 'Reorder my usual lunch' },
    { ...useOf('lunch'), open: true },
    { k: 'poki', t: 'Ordered. It arrives at 12:40.' },
  ]),
  'chat-allowed': chatSc('Message to Mia', [
    { k: 'you', t: 'Tell Mia I’m running ten minutes late' },
    useOf('mia'),
    { k: 'poki', t: 'Sent.' },
  ]),
  'chat-talked': chatSc('This afternoon', [
    { k: 'talk', d: '1 min 12 s', t: 'Talked for 1 min 12 s', out: OUT },
    { k: 'you', t: 'Thanks. Tell Mia I’m running ten minutes late' },
    useOf('mia'),
    { k: 'poki', t: 'Sent.' },
  ]),
  'chat-talked-none': chatSc('Talk with Poki', [{ k: 'talk', d: '14 s', t: 'Talked for 14 s', out: [] }]),
  'chat-fail': chatSc('Refund for the blue jacket', [
    { k: 'you', t: 'Get a refund for the blue jacket I returned last week' },
    useOf('refund'),
    {
      k: 'fail',
      t: 'I couldn’t finish. The store asks for an order number, and I can’t find one in your mail.',
    },
  ]),
  'home-voice': () => {
    base();
    menu(true);
    document.activeElement.blur();
  },
  'home-dictating': () => {
    base();
    const P = ph(),
      i = $('#ask');
    P.dataset.voice = 'dictate';
    i.dataset.ph = i.placeholder;
    i.placeholder = 'Listening';
    i.value = 'Reorder my usual';
    B.pinned = true;
    setPose('along', true);
  },
  'home-talking': () => {
    base();
    talkSc('you', 'Hi. What do you need?', []);
  },
  'home-talk-poki': () => {
    base();
    talkSc(
      'poki',
      'Done. Spin class is now at 8, and I’ll remind you at 2 to leave for the dentist.',
      OUT.slice(),
    );
  },
  'chat-talking': () => {
    SC['chat-answer']();
    talkSc(
      'poki',
      'You have time to walk. It’s 25 minutes on foot.',
      [{ a: 1, b: 'Time to walk between the two', s: '25 minutes on foot, and you have 40' }],
      true,
    );
  },
  'task-work': taskSc('lunch', 'l3'),
  'task-paused': taskSc('lunch', 'l3', 'held'),
  'task-pill': taskSc('lunch', 'l3', 'quiet'),
  'task-black': taskSc('lunch', 'l3', 'black'),
  'task-allow': taskSc('msg', 'ask'),
  'task-yours': taskSc('login', 'yours'),
  'task-done': taskSc('lunch', 'done'),
  'task-fail': taskSc('login', 'fail'),
  set: setSc('root'),
  'set-conn': setSc('conn'),
  'set-conn-warn': setSc('conn', 'warn'),
  'set-agents': setSc('agents'),
  'set-activity': setSc('activity'),
  'set-model': setSc('model'),
  'set-memory': setSc('memory'),
  'set-light': setSc('light'),
  'set-sign': setSc('sign'),
  'set-adv': setSc('adv'),
  'set-diag': setSc('diag'),
  'set-acct': setSc('acct'),
  'set-relay': setSc('relay'),
  'set-agent': setSc('agent'),
};
