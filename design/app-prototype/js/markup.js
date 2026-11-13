// The phone’s HTML: icons, the input bar, the pages.
/* ---------- markup ---------- */
const svg = (w, body, sw = 1.7) =>
  `<svg width="${w}" height="${w}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
const PH =
  '<path d="M6.6 3.5h2.6l1.5 4-2 1.4a12 12 0 0 0 6.4 6.4l1.4-2 4 1.5v2.6a2 2 0 0 1-2.2 2A16.5 16.5 0 0 1 4.6 5.7a2 2 0 0 1 2-2.2z" fill="currentColor" stroke="none"/>';
const I = {
  gear: svg(
    22,
    '<circle cx="12" cy="12" r="3.1"/><path d="M12 2.6l1.5 2.5 2.8-.5 1 2.7 2.7 1-.5 2.8L22 12l-2.5 1.5.5 2.8-2.7 1-1 2.7-2.8-.5L12 21.4l-1.5-2.5-2.8.5-1-2.7-2.7-1 .5-2.8L2 12l2.5-1.5-.5-2.8 2.7-1 1-2.7 2.8.5z"/>',
    1.6,
  ),
  go: svg(18, '<path d="M9 5l7 7-7 7"/>', 2),
  ok: svg(20, '<path d="M5 12.5l4.5 4.5L19 7.5"/>', 2.2),
  phone: (w) => svg(w, PH),
  pen: svg(22, '<path d="M4 20l1-4L16.5 4.5a2.1 2.1 0 0 1 3 3L8 19l-4 1zM14.5 6.5l3 3"/>'),
  up: svg(20, '<path d="M12 19V5M6 11l6-6 6 6"/>', 2.1),
  set: svg(
    22,
    '<path d="M3 8h9M17 8h4M3 16h4M12 16h9"/><circle cx="14.5" cy="8" r="2.2"/><circle cx="9.5" cy="16" r="2.2"/>',
  ),
  ag: svg(
    22,
    '<circle cx="6.5" cy="6.5" r="2.7"/><circle cx="17.5" cy="17.5" r="2.7"/><path d="M9.2 6.5h5.3a3 3 0 0 1 3 3v5.3"/>',
  ),
  chats: svg(22, '<path d="M4 6h16M4 12h16M4 18h10"/>'),
  back: svg(22, '<path d="M14.5 5l-7 7 7 7"/>', 2),
  find: svg(18, '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>', 2),
  neu: svg(24, '<path d="M12 5v14M5 12h14"/>', 2.1),
  mic: svg(
    24,
    '<rect x="9" y="3" width="6" height="11.5" rx="3" fill="currentColor"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"/>',
  ),
  keys: svg(
    24,
    '<rect x="2.5" y="6" width="19" height="12" rx="3"/><path d="M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M7.5 14h9"/>',
  ),
  down: svg(
    24,
    '<path d="M3.2 14.6c-.7-2 .3-3.600 2-4.300a19 19 0 0 1 13.600 0c1.700.7 2.7 2.300 2 4.300l-.5 1.300-4.300-.9-.4-2.600a11 11 0 0 0-7.200 0l-.4 2.600-4.300.9z" fill="currentColor" stroke="none"/>',
  ),
};
const G =
  '<div class="glow" aria-hidden="true"><div class="glow-in"><i class="g0"></i><i class="g1"></i><i class="g2"></i><i class="g3"></i></div></div>';
const TOP = `<div class="top"><span></span><button class="ic" data-act="chats" aria-label="Chats">${I.chats}</button></div>`,
  KB = `<div class="kb" aria-hidden="true"><div>${[...'qwertyuiop'].map((k) => `<i>${k}</i>`).join('')}</div><div>${[...'asdfghjkl'].map((k) => `<i>${k}</i>`).join('')}</div><div><i class="w">⇧</i>${[...'zxcvbnm'].map((k) => `<i>${k}</i>`).join('')}<i class="w">⌫</i></div><div><i class="w">123</i><i class="sp"></i><i class="rt">send</i></div></div>`;
const field = (id, ph) =>
  `<label class="sr" for="${id}">Write to Poki</label><input id="${id}" autocomplete="off" enterkeyhint="send" placeholder="${ph}">`;
const SEND = (c) => `<button class="send ${c || ''}" aria-label="Send">${I.up}</button>`;
const CHIPS =
  '<div class="chips"><button class="chip" data-say="Reorder my usual lunch">Reorder my usual lunch</button><button class="chip" data-say="What’s on this afternoon?">What’s on this afternoon?</button></div>';
const WAVE = svg(22, '<path d="M4 10v4M8 6.5v11M12 3.5v17M16 7.5v9M20 10.5v3"/>', 2.1),
  MICI = svg(
    14,
    '<rect x="9" y="3" width="6" height="11.5" rx="3" fill="currentColor" stroke="none"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"/>',
    2.2,
  );
const MIC20 = svg(
    20,
    '<rect x="9" y="3" width="6" height="11.5" rx="3" fill="currentColor" stroke="none"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"/>',
    2,
  ),
  WAVE20 = svg(20, '<path d="M4 10v4M8 6.5v11M12 3.5v17M16 7.5v9M20 10.5v3"/>', 2.2),
  WAVE13 = svg(13, '<path d="M4 10v4M8 6.5v11M12 3.5v17M16 7.5v9M20 10.5v3"/>', 2.6),
  CHK = svg(13, '<path d="M5 12.5l4.5 4.5L19 7.5"/>', 3.2),
  TXT = svg(13, '<path d="M5 8h14M5 12h14M5 16h8"/>', 2.8);
const OUT = [
  { a: 1, b: 'This afternoon', s: 'Dentist at 2:30, spin class at 7:30' },
  { b: 'Moved spin class to 8:00', s: 'Calendar · 3 steps' },
  { b: 'Reminder at 2:00', s: 'Leave for the dentist' },
];
const BARS = '<span class="lvl" aria-hidden="true"><i></i><i></i><i></i><i></i></span>';
const COMP = (
  id,
) => `<form class="bar comp" data-form><button type="button" class="mini plus" data-toast="Adding a photo or file is not part of this prototype" aria-label="Add a photo or file">${I.neu}</button><button type="button" class="mini mute" data-act="tmute" aria-pressed="false" aria-label="Mute">${MIC20}</button>${BARS}${field(id, 'Ask Poki')}<span class="tkm" role="status"><b class="tkS">Listening</b><time class="tkT">0:00</time></span><button type="button" class="mini voice" data-act="voice" aria-haspopup="menu" aria-expanded="false" aria-label="Speak"><span class="mic">${WAVE}</span><svg class="stop" width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><rect x="2" y="2" width="12" height="12" rx="3" fill="currentColor"/></svg></button><button class="mini send" aria-label="Send">${I.up}</button><button type="button" class="end" data-act="endtalk">End</button>
  <div class="vmenu" role="menu" aria-label="Speak" inert><button type="button" role="menuitem" data-act="dictate"><i>${MIC20}</i><span><b>Dictate</b><small>Speak, and it becomes text</small></span></button><button type="button" role="menuitem" data-act="live"><i>${WAVE20}</i><span><b>Talk with Poki</b><small>A live conversation, out loud</small></span></button></div></form>`;
const LIVE =
  '<div class="live"><small class="lvWho"></small><p class="lvSay" aria-live="polite"></p><ul id="lvOut"></ul></div>';
const tkCard = (m) =>
  `<div class="tkc"${m.live ? ' data-live' : ''}><div class="tkh"><b>${m.live ? 'Talking with Poki' : 'Talked with Poki'}</b><small>${m.live ? '<time class="tkT">0:00</time>' : esc(m.d)}</small><img src="${SPR[m.live ? 'listen' : 'happy'].full}" alt=""></div>${m.live ? '<p class="tks"><small class="lvWho"></small><span class="lvSay"></span></p>' : ''}${m.out.length ? `<ul class="tko">${m.out.map((o) => `<li><i>${o.a ? TXT : CHK}</i><span><b>${esc(o.b)}</b><small>${esc(o.s)}</small></span></li>`).join('')}</ul>` : ''}${m.live ? '' : `<p class="tkn">${m.out.length ? 'Poki keeps what came of a talk, not the conversation.' : 'Nothing came of this one, so there is nothing to keep.'}</p>`}</div>`;
const LAY = {
  window: {
    about:
      'Window. Poki lives in a lit window; the sill is the call and the bar below is for writing. On a call the window opens to fill the screen.',
    html: `${TOP}<h2 class="hello">Good afternoon.<span>What should Poki do?</span></h2>${CHIPS}${LIVE}${COMP('ask')}${KB}`,
  },
  twins: {
    about:
      'Twins. One bar in two equal halves: the lit half calls, the plain half writes. Poki stands alone on the page above.',
    html: `${G}${TOP}<h2 class="hello">What should Poki do?<span>Call to talk it through, or write it down.</span></h2>${CHIPS}<div class="duo"><button class="half c" data-act="call">${I.phone(24)}<span><b>Call</b><small>Talk it through</small></span></button><button class="half w" data-act="write">${I.pen}<span><b>Write</b><small>Type it out</small></span></button><form class="field" data-form>${field('ask', 'Write to Poki')}<button type="button" class="mini" data-act="call" aria-label="Call Poki">${I.phone(20)}</button>${SEND()}</form></div>`,
  },
  card: {
    about:
      'Card. A question and a writing card. The call is the one lit pill inside the card, next to send, and Poki looks over the edge.',
    html: `${G}${TOP}<h2 class="hello">Good afternoon.<span>What should Poki do?</span></h2>${CHIPS}<form class="card" data-form>${field('ask', 'Write to Poki, or call')}<div class="rowb"><button type="button" class="pillc" data-act="call">${I.phone(20)}Call Poki</button>${SEND('big')}</div></form>`,
  },
};
const phoneHTML = (v) => `<div class="phone" id="phone" data-v="${v}" data-theme="${theme}" data-at="home">
  <div class="sb" aria-hidden="true"><span>9:41</span><i><svg width="18" height="12" viewBox="0 0 18 12" fill="currentColor"><rect y="7" width="3" height="5" rx="1"/><rect x="5" y="5" width="3" height="7" rx="1"/><rect x="10" y="2.5" width="3" height="9.5" rx="1"/><rect x="15" width="3" height="12" rx="1" opacity=".35"/></svg><svg width="25" height="12" viewBox="0 0 25 12" fill="none"><rect x=".5" y=".5" width="21" height="11" rx="3.5" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="15" height="8" rx="2" fill="currentColor"/></svg></i></div>
  <div class="isle" id="isle"></div>
  <div class="pager" id="pager">
    <section class="page home" aria-label="New chat"><div class="ui">${LAY[v].html}</div></section>
    <section class="page list" aria-label="Chats"><div class="top"><span></span><button class="ic" data-act="settings" aria-label="Settings">${I.gear}</button></div><h2 class="l-title">Chats</h2>
      <label class="l-find">${I.find}<span class="sr">Search chats</span><input id="find" autocomplete="off" placeholder="Search chats"></label><div class="l-scroll" id="rows"></div></section>
  </div>
  <section class="ob" id="ob" aria-label="Setting up Poki"></section>
  <div class="room" aria-hidden="true"><div class="hz"><i class="a0"></i><i class="a4"></i><i class="a1"></i><i class="a2"></i><i class="a3"></i><i class="grain"></i></div></div>
  <div class="over"><button class="fab" data-act="home">New chat</button></div>
  <div class="perch"><div class="bx"><div class="by"><div class="bear" id="bear" role="button" tabindex="0" aria-label="Poki the bear"><div class="b-act"><div class="b-live" id="bLive"></div><img class="b-fx" id="bFx" alt="" hidden><div class="b-mark" id="bMark" hidden></div></div></div></div></div></div>
  <div class="callui"><div class="c-top">Poki<span id="cTime">0:00</span></div><div class="c-state" id="cState" aria-live="polite"></div>
    <div class="c-row"><button class="c-btn" data-act="mute" aria-label="Mute" aria-pressed="false">${I.mic}</button><button class="c-end" data-act="hang">${I.down}End</button><button class="c-btn" data-act="keys" aria-label="Write instead">${I.keys}</button></div></div>
  <section class="chat" aria-label="Chat"><div class="hd"><button class="ic" data-act="back" aria-label="Back to every chat">${I.back}</button><b id="cTitle"></b><span style="width:44px"></span></div><div class="thread" id="thread" role="log"></div>${COMP('ask2')}</section>
  <section class="set" aria-label="Settings"><div class="hd"><button class="ic" data-act="setback" aria-label="Back">${I.back}</button><b id="sTitle"></b><span></span></div><div class="s-body" id="sBody"></div></section>
  <div class="away" id="away" data-app></div><div class="islx" id="islx"></div><div class="toast" id="toast" role="status"></div></div>`;
