// The page around the phone: side panel, fitting the window, URL options.
/* ---------- harness ---------- */
$('#dots').innerHTML = MIXES.map((m) => {
  const h = hue(m, true);
  return `<button aria-label="${m.n}" title="${m.n}" style="background:radial-gradient(circle at 62% 66%,${h['2b']} 0 22%,transparent 46%),linear-gradient(160deg,${h['1a']},${h['1b']})"></button>`;
}).join('');
{
  let g = '';
  $('#poses').innerHTML = Object.keys(ST)
    .map(
      (k) =>
        (ST[k].g !== g ? `<h5>${(g = ST[k].g)}</h5>` : '') + `<button data-pose="${k}">${ST[k].n}</button>`,
    )
    .join('');
}
$('#cEnergy').addEventListener('input', (e) => (B.energy = +e.target.value));
$('#cSlow').addEventListener('change', (e) => {
  B.speed = e.target.checked ? 0.25 : 1;
  document.documentElement.style.setProperty('--slow', e.target.checked ? 4 : 1);
});
$('#cStill').addEventListener('change', (e) => {
  B.still = e.target.checked;
  if (B.still) {
    const a = $('.b-act');
    a && a.getAnimations().forEach((x) => x.cancel());
  }
});
$('#side').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  if (b.dataset.sc) SC[b.dataset.sc]();
  else if (b.dataset.pose) pin(b.dataset.pose);
  else if (b.dataset.move) move(b.dataset.move);
  else if (b.dataset.theme) {
    theme = b.dataset.theme;
    paint();
  } else if (b.dataset.run) RUN[b.dataset.run]();
  else if (b.parentElement.id === 'dots') {
    mi = [...b.parentElement.children].indexOf(b);
    paint();
  }
});
$('#pTheme').addEventListener('change', (e) => {
  theme = e.target.value;
  paint();
});
$('#pRun').addEventListener('change', (e) => RUN[e.target.value]());
function fit() {
  document.documentElement.style.setProperty(
    '--s',
    EMBED
      ? 1
      : PHONE
        ? Math.min(innerWidth / 390, innerHeight / 844)
        : Math.min(1, (innerHeight - 40) / 864, (innerWidth - 24) / 410),
  );
}
const q = new URLSearchParams(location.search),
  EMBED = q.get('embed') === '1',
  // On a phone the prototype is the screen itself: no drawn bezel and no side panel.
  PHONE = !EMBED && matchMedia('(max-width: 480px)').matches;
if (PHONE) document.body.classList.add('onphone');
// Opened from the Home Screen, the real status bar is on top of the page.
if (PHONE && (navigator.standalone || matchMedia('(display-mode: standalone)').matches))
  document.body.classList.add('standalone');
addEventListener('resize', fit);
fit();
if (q.get('mode') === 'dark') theme = 'dark';
if (q.get('mix')) mi = Math.max(0, Math.min(4, +q.get('mix') - 1));
let first = q.get('frame') || q.get('scene');
if (EMBED) {
  document.body.classList.add('embed');
  B.still = true;
}
