// The walkthrough (?scene=tour): plays the whole flow by pressing the real controls.
/* ---------- the walkthrough: it presses the same controls a person would ---------- */
let tourId = 0;
function tourStop() {
  tourId++;
  delete document.body.dataset.tour;
}
async function tour() {
  const me = ++tourId,
    P = () => ph(),
    isle = () => document.getElementById('isle').shadowRoot;
  const alive = () => me === tourId,
    wait = (ms) => new Promise((ok, no) => setTimeout(() => (alive() ? ok() : no('stopped')), ms));
  const until = async (fn, max = 20000) => {
    const t0 = Date.now();
    while (!fn()) {
      if (Date.now() - t0 > max) throw 'timed out';
      await wait(120);
    }
  };
  const tap = async (el, hold = 520) => {
    el = typeof el === 'string' ? $(el) : el;
    if (!el) throw 'nothing to tap';
    const r = el.getBoundingClientRect(),
      d = $('#tapdot');
    d.style.left = r.left + r.width / 2 + 'px';
    d.style.top = r.top + r.height / 2 + 'px';
    d.removeAttribute('data-on');
    void d.offsetWidth;
    d.setAttribute('data-on', '');
    await wait(300);
    el.click();
    await wait(hold);
  };
  const type = async (sel, text) => {
    const i = $(sel),
      f = i.closest('form');
    i.focus({ preventScroll: true });
    for (let n = 1; n <= text.length; n++) {
      i.value = text.slice(0, n);
      f.setAttribute('data-typing', '');
      i.dispatchEvent(new Event('input', { bubbles: true }));
      await wait(38);
    }
    await wait(450);
    i.blur();
    f.requestSubmit();
  };
  const STEPS = 12;
  let n = 0;
  const say = (h, p) => {
    n++;
    $('#tourN').textContent = `${n} of ${STEPS}`;
    $('#tourBar').style.width = (n / STEPS) * 100 + '%';
    $('#tourH').textContent = h;
    $('#tourP').textContent = p;
  };
  document.body.dataset.tour = '1';
  try {
    // Started from the URL, mount() is what called us: clear the request first, or it would call us again.
    first = null;
    mount();
    await wait(300);
    say(
      'First run',
      'Seven short screens: hello, pick the light, switch on what Poki needs, choose a model, allow the microphone.',
    );
    ob(0);
    await wait(1900);
    for (let i = 0; i < 6; i++) {
      await tap('#ob [data-act=obnext]', 300);
      await wait(i === 1 ? 1700 : 1300);
    }
    await tap('#ob [data-act=obnext]', 600);
    say(
      'The front page',
      'A new chat. Poki in its window, two suggestions, and one glass input to write or speak in.',
    );
    await wait(2600);
    say('Asking a question', 'You write. Poki leaves for Calendar to look; you only see it in the island.');
    await type('#ask', 'What’s on this afternoon?');
    await until(() => P().dataset.away);
    await until(() => P().dataset.chat && !P().dataset.away);
    say(
      'The answer, and the record',
      'Nothing was drawn in the chat while Poki used the phone. Afterwards there is one card: the app, the actions, the time.',
    );
    await wait(2200);
    await tap('#thread [data-act=useopen]', 2400);
    await tap('#thread [data-act=useopen]', 500);
    say(
      'A phone task',
      'You ask for lunch. Poki works in the other app, and the island says each action in the app’s own words.',
    );
    await type('#ask2', 'Reorder my usual lunch');
    await until(() => P().dataset.away);
    await until(() => document.getElementById('isle').dataset.s === 'l2');
    say(
      'Pause and resume',
      'The button in the island pauses Poki where it is. The island stays, and the same button resumes.',
    );
    await wait(700);
    await tap(isle().querySelector('.stop'), 2600);
    await tap(isle().querySelector('.stop'), 400);
    await until(() => document.getElementById('isle').dataset.s === 'pay');
    say('Your turn', 'Poki never pays. It hands the phone back, waits, and carries on when you say so.');
    await wait(2800);
    await tap(isle().querySelector('.c[data-k=pay] .yes'), 400);
    await until(() => P().dataset.chat && !P().dataset.away);
    say(
      'The record of the task',
      'The steps Poki named, the one you did yourself, and every action behind the last line.',
    );
    await wait(2200);
    {
      const b = [...document.querySelectorAll('#thread [data-act=useopen]')].pop();
      await tap(b, 2800);
    }
    say(
      'Every chat',
      'Back out to the list. The window has shrunk into the New chat pill, where Poki minds its own business.',
    );
    await tap('.chat [data-act=back]', 2800);
    say(
      'Settings',
      'One status card, four rows and the approvals switch. Everything else sits behind a row.',
    );
    await tap('.list [data-act=settings]', 1700);
    await tap('#sBody .s-card', 2000);
    await tap('.set [data-act=setback]', 700);
    for (const g of ['model', 'agents', 'memory', 'light']) {
      await tap(`#sBody [data-go=${g}]`, 1700);
      if (g === 'agents') {
        await tap('#sBody [data-go=relay]', 1700);
        await tap('.set [data-act=setback]', 600);
      }
      await tap('.set [data-act=setback]', 700);
    }
    await tap('.set [data-act=setback]', 900);
    say(
      'Talking with Poki',
      'The black button offers two ways to speak. A talk is live: Poki listens and answers, and what comes of it collects below.',
    );
    await tap('.fab', 1700);
    await tap('.home [data-act=voice]', 1500);
    await tap('.home [data-act=live]', 600);
    await until(() => document.querySelectorAll('#lvOut li').length >= 3, 30000);
    await wait(2600);
    if (P().dataset.talk) await tap('.home [data-act=endtalk]', 400);
    await until(() => P().dataset.chat, 8000);
    say(
      'What a talk leaves behind',
      'Not the conversation: a card with what came of it. That is the whole flow.',
    );
    await wait(4000);
  } catch (e) {
    if (e !== 'stopped') {
      $('#tourH').textContent = 'The walkthrough stopped';
      $('#tourP').textContent = 'A step did not happen in time (' + e + '). Play it again.';
    }
  }
}
document.getElementById('tourAgain').addEventListener('click', tour);
document.getElementById('tourStop').addEventListener('click', tourStop);
