// The first-run screens.
/* ---------- first run ---------- */
const OB = [
  {
    big: 1,
    pose: 'wave',
    h: 'Hi, I’m Poki.',
    p: 'I use your iPhone for you. Write to me or just talk, then watch me do it.',
    go: 'Get started',
  },
  {
    big: 1,
    pose: 'rest',
    h: 'Pick my light',
    p: 'It is the one colour in the app. You can change it later in Settings.',
    body: () => lights(),
    go: 'Continue',
  },
  {
    pose: 'search',
    h: 'Let me use this iPhone',
    p: 'Four things to switch on, once. I check each one as you go.',
    body: () =>
      `<div class="s-g">${[
        { mk: 'ok', t: 'Turn on Developer Mode', v: 'Done' },
        { mk: 'ok', t: 'Pair Poki with this iPhone', v: 'Done' },
        { mk: 'todo', n: '3', t: 'Turn on UI Automation', v: 'Next' },
        { mk: 'todo', n: '4', t: 'Keep Poki running' },
      ]
        .map(row)
        .join('')}</div>`,
    go: 'Continue with step 3',
  },
  {
    pose: 'phone',
    h: 'Turn on UI Automation',
    p: 'This lets me tap and type for you.',
    body: () =>
      '<ol class="ob-ol"><li>Open Settings, then Developer.</li><li>Scroll down to UI Automation.</li><li>Switch on Enable UI Automation.</li></ol>',
    go: 'Open Settings',
    alt: 'I’ve done it',
  },
  {
    pose: 'think',
    h: 'Choose what I think with',
    p: 'Sign in or add a key. You can switch later.',
    body: () =>
      `<div class="s-g">${[
        { t: 'ChatGPT', s: 'Sign in with your account', pick: 'provider' },
        { t: 'Anthropic', pick: 'provider' },
        { t: 'OpenAI', pick: 'provider' },
        { t: 'More', v: '4', toast: NO },
      ]
        .map(row)
        .join('')}</div>`,
    go: 'Continue',
  },
  {
    pose: 'listen',
    h: 'Talk to me',
    p: 'You can talk to me instead of typing. I need the microphone for that.',
    go: 'Allow microphone',
    alt: 'Not now',
  },
  {
    big: 1,
    pose: 'happy',
    h: 'I’m ready',
    p: 'Try “Reorder my usual lunch”, or tap the black button and say it.',
    go: 'Start',
  },
];
function ob(i) {
  stopTimers();
  clearCall();
  const P = ph(),
    o = OB[i];
  obi = i;
  delete P.dataset.chat;
  delete P.dataset.away;
  delete P.dataset.set;
  delete P.dataset.islx;
  delete P.dataset.kb;
  P.dataset.at = 'home';
  P.dataset.ob = o.big ? 'big' : 'small';
  B.pinned = true;
  setPose(o.pose, i === 0);
  $('#ob').innerHTML =
    `${i ? `<button class="ic ob-back" data-act="obback" aria-label="Back">${I.back}</button>` : ''}<div class="ob-in"><div class="ob-dots" aria-label="Step ${i + 1} of ${OB.length}">${OB.map((_, n) => `<i${n === i ? ' class="on"' : ''}></i>`).join('')}</div><h2>${o.h}</h2><p>${o.p}</p><div class="ob-body">${o.body ? o.body() : ''}</div><button class="btn" data-act="obnext">${o.go}</button>${o.alt ? `<button class="btn q" data-act="obnext">${o.alt}</button>` : ''}</div>`;
  sync();
}
