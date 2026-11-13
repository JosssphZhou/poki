// Start: build the phone, load the bear, run the scene the URL asks for.
function mount() {
  stopTimers();
  clearInterval(tick);
  vnow = 'window';
  CHATS = seed();
  cur = null;
  px = 0;
  B.pose = '';
  $('#stage').innerHTML = phoneHTML('window');
  paint();
  rest();
  const go = first && (SC[first] || RUN[first]);
  if (go) {
    go();
    first = null;
  }
}
document.addEventListener('keydown', (e) => {
  if (/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === 'r' || e.key === 'R') {
    mount();
    setTimeout(talk, 500);
  } else if (e.key === 'd' || e.key === 'D') {
    theme = theme === 'dark' ? 'light' : 'dark';
    paint();
  }
});
RUN.tour = tour;
const boot = () => {
  mount();
  requestAnimationFrame(frame);
  if (!EMBED) blinkLoop();
};
let shared = null;
try {
  shared = parent !== window && parent.POKI_SPR;
} catch (e) {}
if (shared) {
  Object.assign(SPR, shared);
  boot();
} else {
  const img = new Image();
  img.onload = () => {
    cut(img);
    try {
      if (parent !== window) parent.POKI_SPR = SPR;
    } catch (e) {}
    boot();
  };
  img.src = 'assets/bear-poses.png';
}
