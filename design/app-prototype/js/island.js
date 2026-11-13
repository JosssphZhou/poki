// The Dynamic Island. It lives in its own shadow root; only its states are specific to this prototype.
/* ---------- the island ---------- */
/* An action's words are the app's own ("Open Mail", "Tap “Send”"). There is no total, so nothing here counts towards one. */
const ISL = (() => {
  const OPT = {
      mode: ['line', 'peek', 'quiet'].includes(q.get('isl')) ? q.get('isl') : 'line',
      // Black is what an app can draw: iOS paints a Live Activity's island solid black.
      mat: q.get('mat') === 'glass' ? 'glass' : 'black',
    },
    HOOK = { pause() {}, resume() {}, answer() {} };
  const ST = {
    rest: { n: 'Nothing running' },
    think: { n: 'Thinking', pose: 'think', move: 'think', t: 'Working out what to do' },
    l1: { pose: 'phone', move: 'tap', t: 'Open Green Bowl', step: 1 },
    l2: { pose: 'phone', move: 'tap', t: 'Tap “Order again”', step: 2 },
    l3: { pose: 'search', move: 'scroll', t: 'Scroll to “Checkout”', step: 3 },
    c1: { pose: 'phone', move: 'tap', t: 'Open Calendar', step: 1 },
    c2: { pose: 'search', move: 'think', t: 'Look at the screen', step: 2 },
    m3: { pose: 'phone', move: 'type', t: 'Type “Running ten minutes late.”', step: 3 },
    pay: {
      pose: 'hide',
      h: 'Your turn',
      s: 'Pay in Green Bowl. I never pay for you.',
      yes: 'Done, carry on',
      step: 3,
    },
    ask: {
      pose: 'ask',
      h: 'Send this to Mia?',
      q: 'Running ten minutes late.',
      yes: 'Allow',
      no: 'Don’t allow',
      step: 3,
    },
    yours: {
      pose: 'hide',
      h: 'Your turn',
      s: 'Type your password. I’m not looking.',
      yes: 'Done, carry on',
      step: 2,
    },
    fail: {
      pose: 'worry',
      h: 'I couldn’t finish',
      s: 'The store asks for an order number I can’t find.',
      yes: 'Open Poki',
      step: 2,
    },
    done: { pose: 'happy', move: 'done', t: 'Done', step: 4 },
  };
  const KEYS = Object.keys(ST),
    Q = q,
    RM = EMBED || matchMedia('(prefers-reduced-motion: reduce)').matches;
  const GL = {
    think: '<i class="g g-orb" aria-hidden="true"><b></b><b></b><b></b></i>',
    done: '<i class="g g-done" aria-hidden="true"><svg viewBox="0 0 20 20"><path d="M4.5 10.5l3.6 3.6 7.4-8"/></svg></i>',
  };
  const bear = (pose) => `<img class="bb" src="${SPR[pose].bear}" alt="">`,
    isCard = (s) => !!s.h;
  const btns = (s) =>
    `<div class="btns">${s.no ? `<button class="no" data-go="no">${s.no}</button>` : ''}<button class="yes" data-go="yes">${s.yes}</button></div>`;
  let host = null,
    root = null,
    stage = null,
    phone = null,
    V = null,
    vi = 0,
    cur = 'rest',
    timers = [],
    auto = false,
    hearT = null;
  const $ = (sel, r) => (r || root).querySelector(sel),
    $$ = (sel, r) => [...(r || root).querySelectorAll(sel)];
  const later = (fn, ms) => timers.push(setTimeout(fn, ms)),
    stop = () => {
      timers.forEach(clearTimeout);
      timers = [];
    };
  const mk = () => [
    /* ---------- Ribbon, third pass: three ways to show work, using only what the app knows (the action's own words, went through or failed, a running count, never a total) ---------- */
    ...(() => {
      const SQ = window.CSS && CSS.supports('corner-shape', 'squircle') ? 1.2 : 1,
        LQ = /Chrome\//.test(navigator.userAgent);
      let MAT = OPT.mat;
      const gp = () => (MAT === 'glass' ? 6 : 0),
        WORK = (k) => !!ST[k].step && k !== 'done' && !isCard(ST[k]);
      /* the lens: a picture that tells the filter how far to pull the background at each point. Flat in the middle, steep at the rim, like the edge of a glass drop. */
      const lensC = {};
      function lens(w, h, r) {
        w = Math.round(w);
        h = Math.round(h);
        r = Math.min(r, h / 2, w / 2);
        const key = w + 'x' + h + 'x' + Math.round(r);
        if (lensC[key]) return lensC[key];
        const b = Math.min(26, r * 0.92),
          c = document.createElement('canvas');
        c.width = w;
        c.height = h;
        const x = c.getContext('2d'),
          im = x.createImageData(w, h),
          p = im.data;
        for (let j = 0; j < h; j++)
          for (let i = 0; i < w; i++) {
            const px = i + 0.5 - w / 2,
              py = j + 0.5 - h / 2,
              qx = Math.abs(px) - (w / 2 - r),
              qy = Math.abs(py) - (h / 2 - r);
            const d = r - Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) - Math.min(Math.max(qx, qy), 0);
            let nx = 0,
              ny = 0;
            if (qx > 0 && qy > 0) {
              const l = Math.hypot(qx, qy) || 1;
              nx = (qx / l) * Math.sign(px);
              ny = (qy / l) * Math.sign(py);
            } else if (qx > qy) nx = Math.sign(px);
            else ny = Math.sign(py);
            const t = Math.max(0, Math.min(1, 1 - d / b)),
              f = 1 - Math.sqrt(1 - t * t),
              o = (j * w + i) * 4;
            p[o] = 128 - nx * f * 127;
            p[o + 1] = 128 - ny * f * 127;
            p[o + 2] = 128;
            p[o + 3] = 255;
          }
        x.putImageData(im, 0, 0);
        return (lensC[key] = c.toDataURL());
      }
      /* the hue's top edge, drawn every frame: a soft band that swells with the voice, and once when an action starts */
      const H = {
        sh: null,
        k: 'rest',
        glass: false,
        cur: { lv: 0, amp: 0, sp: 0.3 },
        tgt: { lv: 0, amp: 0, sp: 0.3 },
        env: 0,
        envT: 0,
        kick: 0,
        t: 0,
        raf: 0,
        last: 0,
        lw: 0,
        lh: 0,
        pt: 0,
        ct: 0,
        open: false,
        held: false,
      };
      const HB = 110,
        BASE = HB - 24,
        N = 24;
      function draw() {
        const u = $('.hue u', H.sh),
          a = H.cur,
          hear = H.k === 'listen',
          env = H.env;
        if (!u) return;
        let top = '';
        for (let i = 0; i <= N; i++) {
          const x = i / N,
            win = Math.sin(Math.PI * x),
            w =
              (0.62 * Math.sin(6.283 * (1.15 * x - 0.55 * H.t)) +
                0.38 * Math.sin(6.283 * (2.4 * x + 0.8 * H.t) + 1.3)) *
              win;
          top +=
            (x * 100).toFixed(1) +
            '% ' +
            (
              BASE -
              (a.lv + 10 * env + 7 * H.kick) * (0.28 + 0.72 * Math.pow(win, 0.8)) -
              w * a.amp * (hear ? 0.3 + env : 1)
            ).toFixed(1) +
            'px,';
        }
        u.style.clipPath = `polygon(${top}100% ${HB}px,0% ${HB}px)`;
      }
      function sync() {
        const sh = H.sh,
          fe = $('#lqi');
        if (!H.glass || !fe) return;
        const w = sh.offsetWidth,
          h = sh.offsetHeight;
        if (w === H.lw && h === H.lh) return;
        H.lw = w;
        H.lh = h;
        fe.setAttribute('width', w);
        fe.setAttribute('height', h);
      }
      function frame(now) {
        const sh = H.sh;
        if (!sh || !sh.isConnected) {
          H.raf = 0;
          return;
        }
        const dt = Math.min(0.05, (now - (H.last || now)) / 1000),
          a = H.cur,
          b = H.tgt;
        H.last = now;
        a.lv += (b.lv - a.lv) * 0.1;
        a.amp += (b.amp - a.amp) * 0.1;
        a.sp += (b.sp - a.sp) * 0.1;
        H.env += ((H.k === 'listen' ? H.envT : 0) - H.env) * 0.17;
        H.kick *= 0.94;
        H.t += dt * a.sp;
        draw();
        sync();
        H.raf = requestAnimationFrame(frame);
      }
      /* shapes */
      const pill = () => {
        const c = 37 + 2 * gp();
        return [226, c, c / 2];
      };
      const sheet = (k) => {
        const s = ST[k],
          el = $(`.c[data-k=${k}]`, stage);
        return [
          isCard(s) ? 372 : k === 'done' ? 300 : 362,
          el ? el.offsetHeight : 100,
          (isCard(s) ? 44 : 38) * SQ,
        ];
      };
      function shape(sh, z) {
        sh.style.width = z[0] + 'px';
        sh.style.height = z[1] + 'px';
        sh.style.marginLeft = -z[0] / 2 + 'px';
        sh.style.borderRadius = z[2] + 'px';
        phone.toggleAttribute('data-wide', z[0] > 226);
        if (H.glass) $('#lqi').setAttribute('href', lens(z[0], z[1], z[2] / SQ));
        H.lw = 0;
        if (RM) requestAnimationFrame(sync);
      }
      /* where Poki and the control sit. In the drop Poki is in the middle. In a pill both flank the camera, because there is nowhere else. In a sheet they come down to the row of words: Poki at its left end, the control at its right. */
      function place(sh, kind, w) {
        const g = gp(),
          T = (el, x, y, sc) => {
            el.style.transform = `translate(${x}px,${y}px)` + (sc ? ` scale(${sc})` : '');
          },
          pk = $('#pk'),
          chip = $('#chip'),
          st = $('.stop', sh);
        if (kind === 'drop') return T(pk, 0, 0, 1);
        if (kind === 'pill') {
          T(pk, -85, -58.5, 0.425);
          T(chip, 0, 0);
          T(st, 0, 0);
          return;
        }
        const cy = kind === 'card' ? g + 66.5 : g + 58,
          ps = kind === 'card' ? 40 : 42,
          rx = w / 2 - 34;
        T(pk, -(w / 2 - (kind === 'card' ? 14 : 16) - ps / 2), cy - (g + 77), ps / 80);
        T(chip, rx - 86, cy - (g + 18.5));
        T(st, rx - 85, cy - (g + 18.5));
      }
      /* while Poki works the island is either a sheet with one line and a Stop button, or a pill with a dot that beats once per action */
      function show(sh, yes) {
        if (!WORK(H.k)) return;
        H.open = yes;
        sh.toggleAttribute('data-shut', !yes);
        sh.toggleAttribute('data-stop', yes);
        sh.toggleAttribute('data-pill', !yes);
        $('.stop', sh).inert = !yes;
        if (yes) {
          sh.removeAttribute('tabindex');
          sh.removeAttribute('role');
          sh.removeAttribute('aria-label');
        } else {
          sh.tabIndex = 0;
          sh.setAttribute('role', 'button');
          sh.setAttribute(
            'aria-label',
            H.held ? 'Poki is paused. Show it' : 'Poki is working. Show what it is doing',
          );
        }
        $('#chip').dataset.m = yes ? '' : H.held ? 'hold' : 'beat';
        shape(sh, yes ? sheet(H.k) : pill());
        place(sh, yes ? 'row' : 'pill', 362);
      }
      const peek = (sh) => {
        clearTimeout(H.pt);
        show(sh, true);
        H.pt = setTimeout(() => show(sh, false), 4000);
      };
      /* Stop pauses Poki where it is. The island stays, and the same button resumes. */
      const NEXT = { open: 'find', find: 'type', type: 'ask' };
      function hold(sh, mode) {
        const k = H.k,
          pk = $('#pk'),
          b = $('.stop', sh);
        if (!WORK(k)) return;
        if (H.held) {
          go(k);
          HOOK.resume(k);
          return;
        }
        stop();
        auto = false;
        clearTimeout(H.pt);
        H.held = true;
        sh.setAttribute('data-held', '');
        b.setAttribute('aria-label', 'Resume Poki');
        H.tgt = { ...H.tgt, sp: 0 };
        pk.innerHTML = bear('rest');
        pk.dataset.pose = 'rest';
        pk.className = 'pk mv-none';
        $('#live').textContent = 'Paused';
        HOOK.pause(k);
        if (mode !== 'line') H.pt = setTimeout(() => show(sh, false), 3000);
      }
      stage.addEventListener('click', (e) => {
        const b = e.target.closest('.stop');
        if (b) {
          const sh = b.closest('.gl');
          hold(sh, sh.dataset.work);
          return;
        }
        const sh = e.target.closest('.gl[data-pill]');
        if (sh) peek(sh);
      });
      stage.addEventListener('keydown', (e) => {
        if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('.gl[data-pill]')) {
          e.preventDefault();
          peek(e.target);
        }
      });
      /* M switches the material */
      const matName = () => 'Material: ' + (MAT === 'glass' ? 'Glass' : 'Black') + ' <small>M</small>';
      window.flipMat = () => {
        MAT = MAT === 'glass' ? 'black' : 'glass';
        const u = new URL(location);
        u.searchParams.set('mat', MAT);
        history.replaceState(null, '', u);
        $('#mat').innerHTML = matName();
        document.querySelector('.proto-picker-replay').click();
      };

      const lab = (t) => {
        const i = t.indexOf(' ');
        return i < 0 ? t : `<i>${t.slice(0, i)}</i>${t.slice(i)}`;
      };
      const REAL =
        'An app cannot draw glass here: iOS paints the island solid black and nothing shows through. Press M to see the same design in black, which an app can draw. ';
      const NOTE = {
        line: [
          'It always says what it is doing',
          'The sheet stays open while Poki works. One line carries the app’s own words for the action in hand, and the words change with each action. Poki sits at the left end of the line and Stop at the right.',
          [
            ['Working', 'One line: the action, as the app reports it'],
            ['Top right', 'Stop. Pressed, it pauses Poki and becomes Resume; the island stays'],
            ['New action', 'The words blur over, the hue swells once'],
            ['Wins when', 'You want to follow along, or catch a wrong move early'],
            ['Costs', 'It covers the top of the app Poki is using for the whole task'],
          ],
          REAL +
            'iOS opens an island for a moment or while you hold it; it does not keep one open for a whole task.',
        ],
        peek: [
          'It speaks up, then gets out of the way',
          'A pill most of the time. At each new action it opens, says the action, and closes again. A dot right of the camera beats once per action. Tap the pill to open it and reach Stop.',
          [
            ['Working', 'A pill; the line shows for a second and a half per action'],
            ['Top right', 'A dot that beats per action; Stop while open. Paused, the pill shows two bars'],
            ['New action', 'Opens, speaks, closes'],
            ['Wins when', 'You want to know what happened without losing the screen'],
            ['Costs', 'A lot of movement when actions come fast; Stop is not always there'],
          ],
          REAL + 'This is close to what iOS does by itself when a Live Activity updates.',
        ],
        quiet: [
          'A pill, and nothing more until you ask',
          'Poki’s pose and a beating dot say that work is going on. No words unless you tap the pill. It still opens by itself when Poki needs an answer, and when it is done.',
          [
            ['Working', 'A pill: Poki, the camera, a dot'],
            ['Top right', 'A dot that beats per action; two bars when paused'],
            ['New action', 'One beat, and Poki changes pose'],
            ['Wins when', 'You trust it and want your screen'],
            ['Costs', 'You cannot read what it is doing, or stop it, without a tap'],
          ],
          REAL + 'This is the island as iOS keeps it between updates.',
        ],
      };
      return ['line', 'peek', 'quiet'].map((mode) => ({
        id: mode,
        name: mode[0].toUpperCase() + mode.slice(1),
        size(k) {
          const g = gp(),
            c = 37 + 2 * g;
          return k === 'rest'
            ? [126 + 2 * g, c, c / 2]
            : k === 'think' || (WORK(k) && mode === 'quiet')
              ? pill()
              : k === 'listen'
                ? [172 + 2 * g, g + 114, 58 * SQ]
                : sheet(k);
        },
        html() {
          const w = (k) =>
              !ST[k]
                ? 362
                : isCard(ST[k])
                  ? 372
                  : k === 'done'
                    ? 300
                    : k === 'listen'
                      ? 184
                      : k === 'think'
                        ? 226
                        : 362,
            box = (k, cls, body) =>
              `<div class="c ${cls}" data-k="${k}" style="width:${w(k)}px;margin-left:${-w(k) / 2}px">${body}</div>`;
          return `<div class="gl m-${MAT}${LQ && MAT === 'glass' ? ' lq' : ''}" id="sh" data-work="${mode}"><i class="hue" aria-hidden="true"><u></u></i><i class="el" aria-hidden="true"></i>
        <span class="pk" id="pk" aria-hidden="true"></span><span class="chip" id="chip" data-m="" aria-hidden="true"><i class="g-beat"><b></b></i><i class="g-hold"><b></b><b></b></i>${GL.think}${GL.done}<i class="g-time"><svg viewBox="0 0 22 22"><circle class="tr" cx="11" cy="11" r="9"/><circle class="pr" cx="11" cy="11" r="9"/></svg><em>20</em></i></span>
        <button class="stop" aria-label="Stop Poki" inert></button>${box('held', 'cx hold', '<p class="line one">Paused</p>')}
        ${KEYS.filter((k) => k !== 'rest')
          .map((k) => {
            const s = ST[k];
            return isCard(s)
              ? box(
                  k,
                  'cdn',
                  `<h5>${s.hn || s.h}</h5><p class="${s.q ? 'q' : 'dim'}">${s.q ? '“' + s.q + '”' : s.s}</p>${btns(s)}`,
                )
              : s.step
                ? box(k, 'cx', `<p class="line one">${WORK(k) ? lab(s.t) : s.t}</p>`)
                : box(k, '', `<span class="sr">${s.n}</span>`);
          })
          .join('')}</div><div class="hw"></div>
        <svg aria-hidden="true" style="position:absolute;width:0;height:0"><filter id="lq" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB"><feImage id="lqi" x="0" y="0" width="138" height="49" preserveAspectRatio="none" result="m"/><feDisplacementMap in="SourceGraphic" in2="m" scale="56" xChannelSelector="R" yChannelSelector="G"/></filter></svg>`;
        },
        set(k, sh) {
          const s = ST[k],
            card = isCard(s),
            work = WORK(k),
            pk = $('#pk'),
            chip = $('#chip');
          clearTimeout(H.pt);
          clearInterval(H.ct);
          sh.toggleAttribute('data-card', card);
          H.held = false;
          sh.removeAttribute('data-held');
          $('.stop', sh).setAttribute('aria-label', 'Stop Poki');
          if (s.pose && pk.dataset.pose !== s.pose) {
            pk.innerHTML = bear(s.pose);
            pk.dataset.pose = s.pose;
            pk.removeAttribute('data-pop');
            void pk.offsetWidth;
            pk.setAttribute('data-pop', '');
          }
          pk.className = 'pk mv-' + (s.move || 'none');
          pk.style.opacity = k === 'rest' ? 0 : 1;
          chip.style.opacity = k === 'rest' || k === 'listen' ? 0 : 1;
          H.sh = sh;
          H.k = k;
          H.glass = MAT === 'glass' && LQ;
          H.lw = H.lh = 0;
          /* the hue: a little higher and moving while listening, low and dim while working, still when it needs you */
          H.tgt =
            k === 'rest'
              ? { lv: 0, amp: 0, sp: 0.3 }
              : k === 'listen'
                ? { lv: 16, amp: 3, sp: 0.8 }
                : k === 'think'
                  ? { lv: 4, amp: 1, sp: 0.6 }
                  : k === 'done'
                    ? { lv: 22, amp: 1.4, sp: 0.4 }
                    : card
                      ? { lv: 19, amp: 1.2, sp: k === 'fail' ? 0 : 0.25 }
                      : { lv: 15, amp: 1.4, sp: 0.3 };
          if (work || k === 'done') H.kick = 1;
          if (work) {
            chip.removeAttribute('data-hit');
            void chip.offsetWidth;
            chip.setAttribute('data-hit', '');
            show(sh, mode !== 'quiet');
            if (mode === 'peek') H.pt = setTimeout(() => show(sh, false), 1500);
          } else {
            ['data-shut', 'data-stop', 'data-pill', 'tabindex', 'role', 'aria-label'].forEach((a) =>
              sh.removeAttribute(a),
            );
            $('.stop', sh).inert = true;
            H.open = false;
            chip.dataset.m = k === 'think' ? 'orb' : k === 'done' ? 'ok' : k === 'ask' ? 'time' : '';
            place(
              sh,
              k === 'listen' ? 'drop' : k === 'think' || k === 'rest' ? 'pill' : card ? 'card' : 'row',
              this.size(k)[0],
            );
            if (H.glass) {
              const z = this.size(k);
              $('#lqi').setAttribute('href', lens(z[0], z[1], z[2] / SQ));
            }
          }
          /* asking: the time left to answer drains around a ring */
          if (k === 'ask') {
            let n = 20;
            const em = $('.g-time em', sh),
              pr = $('.g-time .pr', sh),
              paint = () => {
                em.textContent = n;
                pr.style.strokeDashoffset = (56.5 * (1 - n / 20)).toFixed(1);
              };
            paint();
            H.ct = setInterval(() => {
              n = n > 0 ? n - 1 : 20;
              paint();
            }, 1000);
          }
          if (k === 'listen' && !RM) {
            let n = 0;
            H.envT = 0.8;
            hearT = setInterval(() => {
              if (n++ % 3 === 0) H.envT = Math.random() < 0.2 ? 0.05 : 0.35 + Math.random() * 0.65;
              else H.envT *= 0.75 + Math.random() * 0.5;
              H.envT = Math.min(1, H.envT);
            }, 120);
          }
          if (RM) {
            H.cur = { ...H.tgt };
            H.kick = 0;
            H.env = k === 'listen' ? 0.5 : 0;
            draw();
            requestAnimationFrame(sync);
          } else if (!H.raf) H.raf = requestAnimationFrame(frame);
        },
        note: NOTE[mode],
      }));
    })(),
  ];
  function build() {
    root.innerHTML = `<style>${ISLAND_CSS}${EMBED ? ISLAND_STILL : ''}</style><div id="st"></div><span id="live" class="sr" role="status"></span>`;
    stage = $('#st');
    phone = host;
    stage.addEventListener('click', (e) => {
      const b = e.target.closest('[data-go]');
      if (b) HOOK.answer(b.dataset.go === 'yes');
    });
    V = mk();
    vi = ['line', 'peek', 'quiet'].indexOf(OPT.mode);
    stage.innerHTML = V[vi].html();
    const k = cur;
    cur = 'rest';
    go('rest', true);
    void stage.offsetWidth;
    if (k !== 'rest') go(k);
  }
  function ensure() {
    const h = document.getElementById('isle');
    if (!h) return false;
    if (h !== host) {
      stop();
      host = h;
      root = h.shadowRoot || h.attachShadow({ mode: 'open' });
      cur = 'rest';
      build();
    }
    return true;
  }
  function go(k, keep) {
    if (!host && !ensure()) return;
    clearInterval(hearT);
    if (!keep) {
      stop();
      auto = false;
    }
    const s = ST[k],
      v = V[vi],
      sh = $('#sh');
    if (!sh) return;
    cur = k;
    phone.dataset.s = k;
    const z = v.size(k);
    sh.style.width = z[0] + 'px';
    sh.style.height = z[1] + 'px';
    sh.style.marginLeft = -z[0] / 2 + 'px';
    sh.style.borderRadius = z[2] + 'px';
    sh.dataset.k = k;
    sh.dataset.move = s.move || '';
    phone.toggleAttribute('data-wide', z[0] > 226);
    $$('.c', stage).forEach((c) => {
      const on = c.dataset.k === k;
      c.toggleAttribute('data-on', on);
      c.inert = !on;
    });
    if (v.set) v.set(k, sh);
    $('#live').textContent = s.h || s.t || '';
  }
  const paint = () => {
    document
      .querySelectorAll('.side [data-isl]')
      .forEach((b) => b.setAttribute('aria-pressed', b.dataset.isl === OPT.mode));
    document
      .querySelectorAll('.side [data-mat]')
      .forEach((b) => b.setAttribute('aria-pressed', b.dataset.mat === OPT.mat));
  };
  return {
    hook: HOOK,
    get now() {
      return cur;
    },
    paint,
    go(k) {
      if (ensure()) go(k);
    },
    done(t) {
      if (!ensure()) return;
      ST.done.t = t;
      const el = $('.c[data-k=done] .line');
      if (el) el.textContent = t;
      go('done');
    },
    hold() {
      const b = root && $('.stop');
      if (b) b.click();
    },
    opt(o) {
      Object.assign(OPT, o);
      paint();
      if (host) build();
    },
  };
})();
function isl(k) {
  ph().dataset.at = 'gone';
  ISL.go(k);
}
/* a card's answer: your turn in the lunch task ends it; in the frames it writes the record the task would leave */
function ixAnswer(yes) {
  const p = ph(),
    k = p.dataset.islx;
  if (job && job.st === 'yours') return done();
  if (!k || !cur) return;
  if (k === 'fail')
    cur.T.push(useOf('refund'), {
      k: 'fail',
      t: 'I couldn’t finish. The store asks for an order number, and I can’t find one in your mail.',
    });
  else
    cur.T.push(useOf(k === 'yours' ? 'refundOk' : yes ? 'mia' : 'miaNo'), {
      k: 'poki',
      t: !yes ? 'Okay, I didn’t send it.' : k === 'yours' ? 'Thanks. The refund is on its way.' : 'Sent.',
    });
  cur.title = k === 'allow' ? 'Message to Mia' : 'Refund for the blue jacket';
  setP(1, true);
  openChat(cur);
}
ISL.hook.answer = ixAnswer;
ISL.hook.pause = () => {
  if (job && job.st === 'work') {
    stopTimers();
    job.st = 'paused';
  }
};
ISL.hook.resume = () => {
  if (job && job.st === 'paused') {
    job.st = 'work';
    work();
  }
};
document.getElementById('side').addEventListener('click', (e) => {
  const b = e.target.closest('[data-isl],[data-mat]');
  if (b) ISL.opt(b.dataset.isl ? { mode: b.dataset.isl } : { mat: b.dataset.mat });
});
ISL.paint();
