// What a chat keeps of a phone use: the card, and the sample records it is drawn from.
/* ---------- every frame as a state you can jump to ---------- */
const PHN =
    '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><rect x="7" y="2.8" width="10" height="18.400" rx="2.600"/><path d="M10.800 5.700h2.400"/></svg>',
  XI = (w) =>
    `<svg viewBox="0 0 24 24" width="${w}" height="${w}" fill="none" stroke="currentColor" stroke-width="2.400" stroke-linecap="round" aria-hidden="true"><path d="M7 7l10 10M17 7L7 17"/></svg>`,
  TICK = (w) =>
    `<svg viewBox="0 0 24 24" width="${w}" height="${w}" fill="none" stroke="currentColor" stroke-width="2.600" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.500l4.500 4.500L19 7.500"/></svg>`,
  YOU = (w) =>
    `<svg viewBox="0 0 24 24" width="${w}" height="${w}" fill="none" stroke="currentColor" stroke-width="2.200" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="8.500" r="3.300"/><path d="M5.500 19.500c1-3.400 3.500-5 6.500-5s5.500 1.600 6.500 5"/></svg>`;
/* a step of the plan: t its words, m 'x' did not go through, m 'you' the person did it, s a line underneath.
   an action: a string went through, { x } did not, { you } was handed to the person. */
const USE = {
  cal: {
    apps: ['Calendar'],
    d: '6 s',
    plan: [],
    acts: [['Calendar', ['Open Calendar', 'Look at the screen']]],
  },
  lunch: {
    apps: ['Green Bowl', 'Wallet'],
    d: '48 s',
    plan: [
      { t: 'Open your usual order' },
      { t: 'Check the three items' },
      { t: 'Pay $14.20', m: 'you', s: 'You paid. Poki never pays for you' },
      { t: 'Check the order went through' },
    ],
    acts: [
      [
        'Green Bowl',
        ['Open Green Bowl', 'Tap “Orders”', 'Tap “Order again”', 'Scroll to “Checkout”', 'Tap “Checkout”'],
      ],
      ['Wallet', [{ you: 'Your turn: pay $14.20' }]],
      ['Green Bowl', ['Look at the screen']],
    ],
  },
  mia: {
    apps: ['Messages'],
    d: '12 s',
    plan: [
      { t: 'Open your chat with Mia' },
      { t: 'Write “Running ten minutes late.”' },
      { t: 'Send it', s: 'You allowed this at 9:41' },
    ],
    acts: [['Messages', ['Open Messages', 'Tap “Mia”', 'Type “Running ten minutes late.”', 'Tap “Send”']]],
  },
  miaNo: {
    apps: ['Messages'],
    d: '10 s',
    plan: [
      { t: 'Open your chat with Mia' },
      { t: 'Write “Running ten minutes late.”' },
      { t: 'Send it', m: 'x', s: 'You said no, so it was not sent' },
    ],
    acts: [
      ['Messages', ['Open Messages', 'Tap “Mia”', 'Type “Running ten minutes late.”', { x: 'Tap “Send”' }]],
    ],
  },
  refund: {
    apps: ['Mail', 'Safari'],
    d: '1 min 12 s',
    plan: [
      { t: 'Find the return email' },
      { t: 'Open the store’s refund page' },
      { t: 'Fill in the order number', m: 'x', s: 'There is no order number in your mail' },
    ],
    acts: [
      [
        'Mail',
        [
          'Open Mail',
          'Tap “Search”',
          'Type “blue jacket”',
          'Tap “Your return is on its way”',
          'Scroll to “Order details”',
        ],
      ],
      ['Safari', ['Open Safari', 'Tap “Refunds”', { x: 'Scroll to “Order number”' }]],
      ['Mail', ['Open Mail', { x: 'Scroll to “Order number”' }]],
    ],
  },
  refundOk: {
    apps: ['Mail', 'Safari'],
    d: '1 min 30 s',
    plan: [
      { t: 'Find the return email' },
      { t: 'Sign in to the store', m: 'you', s: 'You typed your password' },
      { t: 'Ask for the refund' },
    ],
    acts: [
      ['Mail', ['Open Mail', 'Tap “Search”', 'Type “blue jacket”', 'Tap “Your return is on its way”']],
      [
        'Safari',
        [
          'Open Safari',
          'Tap “Sign in”',
          { you: 'Your turn: type your password' },
          'Tap “Refunds”',
          'Tap “Refund this order”',
          'Look at the screen',
        ],
      ],
    ],
  },
  flights: {
    apps: ['Safari'],
    d: '2 min 40 s',
    plan: [
      { t: 'Search flights to Lisbon in March' },
      { t: 'Sort by price' },
      { t: 'Compare the three cheapest' },
    ],
    acts: [
      [
        'Safari',
        [
          'Open Safari',
          'Tap “Search”',
          'Type “flights to Lisbon”',
          'Tap “Flights”',
          'Tap “Dates”',
          'Tap “March”',
          'Tap “Done”',
          'Tap “Sort”',
          'Tap “Price”',
          'Look at the screen',
          'Tap “9:15 on the 12th”',
          'Look at the screen',
          'Swipe down',
          'Look at the screen',
        ],
      ],
    ],
  },
};
const useOf = (k) => ({ k: 'use', ...JSON.parse(JSON.stringify(USE[k])) });
const useCard = (m, i) => {
  const all = m.acts.flatMap((g) => g[1]),
    n = all.filter((a) => !a.you).length,
    miss = all.filter((a) => a.x).length,
    plan = m.plan.length,
    count = `${n} action${n === 1 ? '' : 's'}${miss ? `, ${miss} didn’t go through` : ''}`,
    bt = ` data-act="useopen" data-i="${i}" aria-expanded="${!!m.open}"`,
    head = `<i class="usei">${PHN}</i><span><b>Used your iPhone</b><small>${esc(m.apps.join(', '))} · ${plan ? '' : count + ' · '}${esc(m.d)}</small></span>`;
  return `<div class="use"${m.open ? ' data-open' : ''}>${plan ? `<div class="useh">${head}</div>` : `<button class="useh"${bt}>${head}<i class="chev">${I.go}</i></button>`}
    ${plan ? `<ol class="usep">${m.plan.map((p) => `<li${p.m ? ` data-m="${p.m}"` : ''}><i>${p.m === 'x' ? XI(13) : p.m === 'you' ? YOU(14) : TICK(13)}</i><span><b>${esc(p.t)}</b>${p.s ? `<small>${esc(p.s)}</small>` : ''}</span></li>`).join('')}</ol><button class="usef"${bt}><span>${count}</span><i class="chev">${I.go}</i></button>` : ''}
    ${m.open ? `<div class="usea">${m.acts.map(([app, L]) => `<h6>${esc(app)}</h6><ol>${L.map((a) => `<li${a.x ? ' data-m="x"' : a.you ? ' data-m="you"' : ''}><i>${a.x ? XI(12) : a.you ? YOU(13) : TICK(12)}</i><span>${esc(a.x || a.you || a)}</span></li>`).join('')}</ol>`).join('')}</div>` : ''}</div>`;
};
