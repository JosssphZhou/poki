// Settings: every page as data.
/* ---------- settings ---------- */
const S = {
  conn: 'ok',
  relay: true,
  ask: true,
  face: true,
  hang: true,
  provider: 'Anthropic',
  lang: 'English',
  look: 'Light',
};
let stack = [],
  obi = 0;
const row = (o) => {
  const act = o.go || o.tog || o.pick || o.act || o.toast,
    tag = act ? 'button' : 'div';
  return `<${tag} class="s-row"${o.go ? ` data-go="${o.go}"` : ''}${o.tog ? ` role="switch" aria-checked="${!!S[o.tog]}" data-tog="${o.tog}"` : ''}${o.pick ? ` data-pick="${o.pick}" data-val="${esc(o.t)}" aria-pressed="${S[o.pick] === o.t}"` : ''}${o.act ? ` data-act="${o.act}"` : ''}${o.toast ? ` data-toast="${esc(o.toast)}"` : ''}>${o.mk ? `<i class="mk ${o.mk}">${o.mk === 'ok' ? '✓' : o.mk === 'no' ? '!' : o.n || ''}</i>` : ''}<span><b>${esc(o.t)}</b>${o.s ? `<small>${esc(o.s)}</small>` : ''}</span>${o.v ? `<em>${esc(o.v)}</em>` : ''}${o.tog ? '<i class="sw"></i>' : o.pick ? (S[o.pick] === o.t ? I.ok : '') : o.go || o.act || o.toast ? `<i class="chev">${I.go}</i>` : ''}</${tag}>`;
};
const grp = (h, rows, f) =>
    `${h ? `<h3 class="s-h">${h}</h3>` : ''}<div class="s-g">${rows.map(row).join('')}</div>${f ? `<p class="s-f">${f}</p>` : ''}`,
  NO = 'This is not part of the prototype yet';
const lights = () =>
  `<div class="lights">${MIXES.map((m, i) => {
    const h = hue(m, true);
    return `<button class="lightb" data-mix="${i}" aria-pressed="${i === mi}" aria-label="${m.n}" style="background:radial-gradient(circle at 62% 66%,${h['2b']} 0 22%,transparent 46%),linear-gradient(160deg,${h['1a']},${h['1b']})"></button>`;
  }).join('')}</div>`;
const card = (tag) =>
  `<${tag} class="s-card"${tag === 'button' ? ' data-go="conn"' : ''}><img src="${SPR[S.conn === 'ok' ? 'happy' : 'worry'].bear}" alt=""><span><b>${S.conn === 'ok' ? 'Poki is ready' : 'Poki needs a hand'}</b><small>${S.conn === 'ok' ? 'It can use this iPhone' : 'UI Automation is switched off'}</small></span>${tag === 'button' ? `<i class="chev">${I.go}</i>` : ''}</${tag}>`;
Object.assign(S, { on: true, mute: false, hide: false, askpoki: false, auto: false, chat: true });
const qr = () => {
  let h = 7,
    c = '';
  for (let y = 0; y < 21; y++)
    for (let x = 0; x < 21; x++) {
      h = (h * 1103515245 + 12345) >>> 0;
      const f = (x < 7 && y < 7) || (x > 13 && y < 7) || (x < 7 && y > 13),
        fx = x > 13 ? x - 14 : x,
        fy = y > 13 ? y - 14 : y,
        on = f
          ? fx === 0 || fx === 6 || fy === 0 || fy === 6 || (fx > 1 && fx < 5 && fy > 1 && fy < 5)
          : (h >> 16) % 5 < 2;
      if (on) c += `<rect x="${x}" y="${y}" width="1" height="1"/>`;
    }
  return `<svg class="s-qr" viewBox="-1 -1 23 23" role="img" aria-label="QR code of the address" fill="currentColor">${c}</svg>`;
};
const PAGES = {
  root: () => [
    'Settings',
    card('button') +
      grp('', [
        { t: 'Model', v: 'Claude Haiku 5.5', go: 'model' },
        { t: 'Agents', v: S.relay ? '2 connected' : 'Off', go: 'agents' },
        { t: 'Memory', v: '3 routines', go: 'memory' },
        { t: 'Appearance', v: MIXES[mi].n, go: 'light' },
      ]) +
      grp(
        '',
        [{ t: 'Ask before sensitive steps', tog: 'ask' }],
        'Poki asks you before it or an agent pays, deletes, sends a message, places a call, types a password or does anything in Wallet.',
      ) +
      `<p class="s-ver">Poki 0.4 · Up to date</p>`,
  ],
  conn: () => [
    'Connection',
    card('div') +
      grp('', [
        {
          t: 'Poki',
          s: S.on ? 'On. Poki and your agents can use this iPhone' : 'Paused. Nothing can use this iPhone',
          tog: 'on',
        },
      ]) +
      grp(
        'On this iPhone',
        [
          { mk: 'ok', t: 'Developer Mode', v: 'On' },
          { mk: 'ok', t: 'Loopback', v: 'On' },
          { mk: 'ok', t: 'Paired with Poki', v: 'Done' },
          S.conn === 'ok'
            ? { mk: 'ok', t: 'UI Automation', v: 'On' }
            : { mk: 'no', t: 'UI Automation', s: 'Switched off in Settings', v: 'Turn on', act: 'fix' },
          { mk: 'ok', t: 'Poki keeps running', v: 'On' },
        ],
        'Poki drives this iPhone through Apple’s developer tools, so all five have to stay on.',
      ) +
      grp('', [
        { t: 'Signing and updates', v: '6 days left', go: 'sign' },
        { t: 'Advanced', go: 'adv' },
        { t: 'Set up again', act: 'replay' },
      ]),
  ],
  sign: () => [
    'Signing and updates',
    grp(
      'Signing',
      [
        { t: 'Signed until', v: 'Nov 17 · 6 days left' },
        { t: 'Renew now', toast: NO },
        { t: 'Apple Account', s: 'Optional. Renews Poki without a Mac', v: 'Not signed in', toast: NO },
        { t: 'Anisette server', v: 'Default', toast: NO },
      ],
      'Poki Setup on your Mac renews Poki when this iPhone is connected.',
    ) +
      grp(
        'Version',
        [
          { t: 'Installed', v: '0.4 (12)' },
          { t: 'Release channel', v: 'Alpha', toast: NO },
          { t: 'Newest on this channel', v: '0.4 (12)' },
          { t: 'Status', v: 'Up to date' },
        ],
        'Poki looks on GitHub for the newest build on the chosen channel.',
      ),
  ],
  adv: () => [
    'Advanced',
    grp(
      'Poki Runner',
      [
        { t: 'Runner', v: 'Running' },
        { t: 'Stop when idle for', v: '2 minutes', toast: NO },
        { t: 'Hide banner when idle', s: 'When Poki automates without the runner', tog: 'hide' },
      ],
      'iOS shows the automation banner only while the runner is active. Poki starts it when needed and stops it when idle.',
    ) +
      grp('', [
        { t: 'Notifications', s: 'Opens iPhone Settings', toast: NO },
        { t: 'Diagnostics', go: 'diag' },
        { t: 'Log', v: '412 lines', toast: NO },
        { t: 'Live Activity preview', toast: NO },
      ]),
  ],
  diag: () => [
    'Diagnostics',
    grp('Checks', [
      { mk: 'ok', t: 'Proxy loopback interface', v: '10.7.0.2' },
      { mk: 'ok', t: 'Port on 10.7.0.1', v: 'Open' },
    ]) +
      grp(
        'Background hold',
        [
          { t: 'Experiment', v: 'Location', toast: NO },
          { t: 'Start hold', toast: NO },
        ],
        'Start, leave the app for a while, then return. The log records the gaps.',
      ) +
      grp('Addresses', [{ t: 'This iPhone', v: '192.168.1.24' }]) +
      grp(
        'Testing',
        [
          { t: 'ask_poki tool', s: 'Agents can hand a task to Poki', tog: 'askpoki' },
          { t: 'Auto-classifier', s: 'Your chat model answers approvals for you', tog: 'auto' },
        ].concat(S.auto ? [{ t: 'Permissiveness', v: 'Balanced', toast: NO }] : []),
        'Both off by default.',
      ),
  ],
  model: () => [
    'Model',
    grp('In use', [
      { t: 'Text chat', v: 'Claude Haiku 5.5', go: 'acct' },
      { t: 'Live voice', s: 'Talking with Poki needs an OpenAI key', v: 'Not available', toast: NO },
      { t: 'Dictation', v: 'On this iPhone' },
    ]) +
      grp(
        'Accounts',
        [
          { t: 'Anthropic', v: 'API key', go: 'acct' },
          { t: 'Add an account', toast: NO },
        ],
        'Keys and sign-ins stay in this iPhone’s Keychain. Poki sends each one only to its own provider.',
      ) +
      grp('Voice', [
        { t: 'Mute Poki’s voice', tog: 'mute' },
        { t: 'Mac voice bridge', v: 'Not set', toast: NO },
      ]),
  ],
  acct: () => [
    'Anthropic',
    grp('', [
      { t: 'Type', v: 'API key' },
      { t: 'Connection', v: 'Working' },
      { t: 'Address', v: 'api.anthropic.com' },
    ]) +
      grp(
        'Use this account for',
        [
          { t: 'Text chat', tog: 'chat' },
          { t: 'Chat model', v: 'Claude Haiku 5.5', toast: NO },
          { t: 'Live voice', s: 'Runs on OpenAI’s Realtime API only', v: 'Not available' },
        ],
        'Only one account runs the text chat at a time.',
      ) +
      grp('', [
        { t: 'Refresh the model list', toast: NO },
        { t: 'Replace the key', toast: NO },
        { t: 'Remove the key', toast: NO },
      ]),
  ],
  agents: () => [
    'Agents',
    `<p class="s-p">Other agents, such as Claude Code or Codex on your Mac, can use this iPhone through Poki.</p>` +
      grp(
        'MCP relay',
        [
          { t: 'MCP relay', s: S.relay ? 'Connected' : 'Off. No agent can reach this iPhone', tog: 'relay' },
          { t: 'Address', v: 'poki-relay.you.workers.dev', go: 'relay' },
        ],
        'The relay forwards agents’ requests to this iPhone while Poki is open or in the background. It stores nothing.',
      ) +
      (S.relay
        ? grp(
            'Agents',
            [
              { t: 'Claude Code', v: 'Today', go: 'agent' },
              { t: 'Codex', v: 'Yesterday', go: 'agent' },
              { t: 'Add an agent', toast: NO },
            ],
            'Each agent gets its own MCP address.',
          )
        : '') +
      grp(
        '',
        [{ t: 'Activity', s: 'Every action an agent took here', go: 'activity' }],
        'What agents do shows up here only, never in your chats.',
      ),
  ],
  relay: () => [
    'Relay',
    `<h3 class="s-h">Relay address</h3><div class="s-field">https://poki-relay.you.workers.dev</div><p class="s-f">Poki has no default relay. Deploy your own to your Cloudflare account, then enter the address it prints. Screenshots and taps pass only through that relay.</p>` +
      grp('Status', [{ mk: 'ok', t: 'Relay', v: 'Connected' }]),
  ],
  agent: () => [
    'Claude Code',
    `<h3 class="s-h">MCP address</h3><div class="s-field sm">https://poki-relay.you.workers.dev/c/7f3a…e21b</div>${qr()}<p class="s-f" style="text-align:center">Add it as a remote MCP server in Claude Code, Codex or any MCP client.</p>` +
      grp('', [
        { t: 'Name', v: 'Claude Code', toast: NO },
        { t: 'Added', v: 'Nov 3' },
        { t: 'Last used', v: 'Today, 10:32' },
      ]) +
      grp('', [{ t: 'Revoke access', toast: NO }]),
  ],
  activity: () => [
    'Activity',
    grp('Today', [
      { mk: 'ok', t: 'Tap “Mia”', s: 'Messages · Claude Code', v: '10:32' },
      { mk: 'ok', t: 'Open Messages', s: 'Messages · Claude Code', v: '10:32' },
      { mk: 'no', t: 'Scroll to “Reading List”', s: 'Safari · Claude Code · not found', v: '10:31' },
      { mk: 'ok', t: 'Type “harbor dental”', s: 'Safari · Claude Code', v: '10:31' },
      { mk: 'ok', t: 'Open Safari', s: 'Safari · Claude Code', v: '10:30' },
    ]) +
      grp(
        'Yesterday',
        [
          { mk: 'ok', t: 'Look at the screen', s: 'Settings · Codex', v: '18:04' },
          { mk: 'ok', t: 'Swipe up', s: 'Settings · Codex', v: '18:03' },
          { mk: 'ok', t: 'Open Settings', s: 'Settings · Codex', v: '18:03' },
        ],
        'This log can’t be deleted.',
      ),
  ],
  memory: () => [
    'Memory',
    grp('Routines', [
      { t: 'Usual lunch', s: 'Chicken grain bowl from Green Bowl', toast: NO },
      { t: 'Morning summary', s: 'Calendar, weather and unread mail', toast: NO },
      { t: 'Gym booking', s: 'Spin class, Thursdays at 7:30', toast: NO },
    ]) +
      grp(
        'Notes',
        [
          { t: 'Mom is “Mama” in Contacts', s: 'Added by you', toast: NO },
          { t: 'Work calendar is the blue one', s: 'Added by Claude Code', toast: NO },
          { t: 'Add a note', toast: NO },
        ],
        'Every agent sees these notes before a task. They stay on this iPhone.',
      ) +
      grp('Move or back up', [
        { t: 'Export memory', toast: NO },
        { t: 'Import memory', toast: NO },
      ]) +
      grp(
        'Advanced',
        [
          { t: 'Share the run log', s: 'For the Poki maintainers. No typed text', toast: NO },
          { t: 'Clear memory', toast: NO },
        ],
        'Clearing cannot be undone.',
      ),
  ],
  light: () => [
    'Appearance',
    `<p class="s-p">Poki’s light is the one colour in the app. It sits behind Poki in the window and when you talk.</p>` +
      lights() +
      `<p class="s-f" style="margin-top:0;text-align:center">${MIXES[mi].n}</p>` +
      grp(
        '',
        ['Light', 'Dark'].map((t) => ({ t, pick: 'look' })),
      ),
  ],
};
function drawSet() {
  const [t, h] = PAGES[stack[stack.length - 1]]();
  $('#sTitle').textContent = t;
  $('#sBody').innerHTML = h;
  $('#sBody').scrollTop = 0;
}
function openSet(pg) {
  const P = ph();
  if (!P.dataset.set) stack = pg === 'root' ? [] : ['root'];
  stack.push(pg);
  P.dataset.set = '1';
  drawSet();
  sync();
}
function setBack() {
  stack.pop();
  if (stack.length) drawSet();
  else {
    delete ph().dataset.set;
    drawList();
    sync();
  }
}
