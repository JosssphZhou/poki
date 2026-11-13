// The sample chats, and the state the whole prototype shares.
/* ---------- the chats ---------- */
const seed = () => [
  {
    title: 'Message to Mia',
    day: 'Today',
    T: [{ k: 'you', t: 'Tell Mia I’m running ten minutes late' }, useOf('mia'), { k: 'poki', t: 'Sent.' }],
  },
  {
    title: 'Refund for the blue jacket',
    day: 'Today',
    T: [
      { k: 'you', t: 'Get a refund for the blue jacket I returned last week' },
      useOf('refund'),
      {
        k: 'fail',
        t: 'I couldn’t finish. The store asks for an order number, and I can’t find one in your mail.',
      },
    ],
  },
  {
    title: 'Dentist, spin class, and whether there is time to walk between the two',
    day: 'Yesterday',
    T: [
      {
        k: 'talk',
        d: '1 min 48 s',
        t: 'Talked for 1 min 48 s',
        out: [
          { a: 1, b: 'This afternoon', s: 'Dentist at 2:30, spin class at 7:30' },
          { a: 1, b: 'Time to walk between the two', s: '25 minutes on foot, and you have 40' },
        ],
      },
    ],
  },
  {
    title: 'Flights to Lisbon',
    day: 'Saturday',
    T: [
      { k: 'you', t: 'Find me a flight to Lisbon in March under $600' },
      useOf('flights'),
      {
        k: 'poki',
        t: 'Three options under $600. The 9:15 on the 12th has one stop and is the cheapest, at $548.',
      },
    ],
  },
  {
    title: 'What Poki can do',
    day: 'Last week',
    T: [
      { k: 'you', t: 'What can you do?' },
      {
        k: 'poki',
        t: 'I use your iPhone the way you would: open apps, tap, type and read the screen. I stop and ask before I send, pay or delete.',
      },
    ],
  },
];
let idleMode = '',
  theme = 'light',
  mi = 0,
  vnow = 'window',
  timers = [],
  idleT = null,
  tick = null,
  job = null,
  CHATS = [],
  cur = null,
  px = 0,
  t0 = 0,
  toastT = null;
const ph = () => $('#phone'),
  later = (fn, ms) => {
    const t = setTimeout(fn, ms);
    timers.push(t);
    return t;
  },
  stopTimers = () => {
    timers.forEach(clearTimeout);
    timers = [];
    clearTimeout(idleT);
    idleMode = '';
  };
const fmt = (ms) => {
  const s = Math.round(ms / 1000);
  return `${(s / 60) | 0}:${String(s % 60).padStart(2, '0')}`;
};
const newChat = () => {
  const c = { title: 'New chat', day: 'Today', T: [] };
  CHATS.unshift(c);
  return c;
};
