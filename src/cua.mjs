// Default phone-agent tools: look and do.
//
// Modeled on Poki's on-device agent: one call does some actions and then reads the
// screen once. The answer is facts only: the numbered elements of that one read (marked new when
// they were not in the previous read), the app in front, timings, and a screenshot as visual
// confirmation. There is no verdict, no expectation engine and no live video; the model looks at
// the facts and decides what happened. Refs are numbers from the latest read and are replaced by
// the next one.
import sharp from 'sharp';
import { pause, stopped } from './work.mjs';
import { wdaContext } from './cua-wda.mjs';
import { platformTool } from './platform.mjs';
import { leavesUnnamedBand, textOutside } from './ocr-supplement.mjs';
import { askHuman } from './human.mjs';
import { matching } from './interaction.mjs';

const settleAfterMs = { tap: 450, type: 250, key: 300, swipe: 600, drag: 600, button: 700, launch: 900, wait: 0 };
const imageWidth = 300, lineLimit = 120;
// A read waits this long for accessibility; after that the screenshot's OCR answers instead, so a
// silent accessibility service costs seconds, not tens of seconds.
const treeWaitMs = Number(process.env.POKI_CUA_TREE_MS) || 2500;

const roleName = element => String(element.type ?? element.role ?? 'Text').replace(/^XCUIElementType/, '');
const labelOf = element => [element.label ?? element.text, element.value].filter(value => value !== undefined && value !== null && value !== '').map(String).join(' = ');
const box = element => element.frame ?? element;
const keyOf = element => `${roleName(element)}|${labelOf(element)}`;

function state(ctx, deviceId) {
  if (deviceId && ctx.cua?.deviceId && ctx.cua.deviceId !== deviceId) ctx.cua = undefined;
  ctx.cua ??= { deviceId, refs: new Map(), previous: new Set(), originApp: undefined };
  if (deviceId) ctx.cua.deviceId = deviceId;
  return ctx.cua;
}

const SENSITIVE_PAYMENTS = ['pay', 'payment', 'buy', 'purchase', 'subscribe', 'checkout', 'place order', 'transfer', 'send money', 'confirm payment', 'apple pay', '支付', '付款', '购买', '订阅', '转账', '确认支付', '下单', '購買', '訂閱', '轉賬', '轉帳', '確認支付', '下單'];
const SENSITIVE_DELETIONS = ['delete', 'remove', 'erase', 'reset', 'delete all', '删除', '移除', '抹掉', '清空', '还原', '刪除', '還原'];
const SENSITIVE_CALLING = ['call', '拨打', '呼叫', '撥打'];
const SENSITIVE_SENDING = ['send', 'post', 'reply', '发送', '回复', '发布', '發送', '回覆', '發布'];
const GUARDED_APPS = new Set(['com.apple.Passbook']);
const CALLING_APPS = new Set(['com.apple.mobilephone', 'com.apple.facetime']);
const MESSAGING_APPS = new Set(['com.apple.MobileSMS', 'com.apple.mobilemail', 'com.tencent.xin', 'net.whatsapp.WhatsApp', 'ph.telegra.Telegraph', 'com.burbn.instagram', 'com.atebits.Tweetie2', 'com.facebook.Messenger', 'com.hammerandchisel.discord', 'com.tinyspeck.chatlyio']);

function matchesWord(text, words, role = 'Other') {
  const lowered = String(text ?? '').toLowerCase();
  if (!lowered) return undefined;
  const short = lowered.trim().split(/\s+/).length <= 4;
  const boundary = ch => !ch || !/[\p{L}\p{N}]/u.test(ch);
  for (const word of words) {
    const w = word.toLowerCase();
    if (!w) continue;
    if ([...w].some(ch => ch.codePointAt(0) > 0x2e80)) {
      if (lowered.includes(w)) return word;
      continue;
    }
    let from = 0;
    for (;;) {
      const idx = lowered.indexOf(w, from);
      if (idx < 0) break;
      const before = idx === 0 ? '' : lowered[idx - 1];
      const after = idx + w.length >= lowered.length ? '' : lowered[idx + w.length];
      const opens = !/[\p{L}\p{N}]/u.test(lowered.slice(0, idx));
      if (boundary(before) && boundary(after) && (role === 'Button' || opens || short)) return word;
      from = idx + w.length;
    }
  }
  return undefined;
}

function sensitiveReason(element, { typing = false, appBundle = '', secureOnScreen = false } = {}) {
  if (appBundle && GUARDED_APPS.has(appBundle)) return `input in ${appBundle}`;
  const isSecure = element && /secure/i.test(roleName(element));
  if (typing) return isSecure || (!element && secureOnScreen) ? 'typing into a password field' : undefined;
  if (!element) return appBundle && CALLING_APPS.has(appBundle) ? `a call in ${appBundle}` : undefined;
  const role = roleName(element);
  const texts = [labelOf(element), element.identifier ?? ''];
  const find = words => texts.map(t => matchesWord(t, words, role)).find(Boolean);
  const payment = find(SENSITIVE_PAYMENTS);
  if (payment) return `payment ("${payment}")`;
  const deletion = find(SENSITIVE_DELETIONS);
  if (deletion) return `deletion ("${deletion}")`;
  if (appBundle && CALLING_APPS.has(appBundle)) return `a call in ${appBundle}`;
  const call = find(SENSITIVE_CALLING);
  if (call) return `call ("${call}")`;
  if (appBundle && MESSAGING_APPS.has(appBundle)) {
    const sendWord = find(SENSITIVE_SENDING);
    if (sendWord) return `sending a message ("${sendWord}")`;
  }
  return undefined;
}

async function requireApproval(ctx, promptText, budget, { alwaysAsk = false } = {}) {
  if (!alwaysAsk && process.env.POKI_MCP_APPROVAL_MODE === 'allow') return;
  const askedAt = performance.now();
  const result = await askHuman(promptText, alwaysAsk ? 300 : 120);
  budget.until += performance.now() - askedAt;
  if (!result.completed) throw new NotSent(`approval ${result.status}; nothing was sent`);
}

// Elements worth listing: on screen, not the application root, with something to say.
function listable(elements, size) {
  return elements.filter(element => {
    if ((element.depth === 0 && roleName(element) === 'Application') || !labelOf(element)) return false;
    const f = box(element);
    return f.width > 0 && f.height > 0 && f.x + f.width > 0 && f.y + f.height > 0 && f.x < size.width && f.y < size.height;
  });
}

// One read of the screen: a screenshot and the accessibility tree together; OCR of that
// screenshot when the tree is empty or fails, or names only part of the screen.
async function read(ctx) {
  const started = performance.now();
  // Both at once: the bridge runs the screenshot beside an accessibility read, so the read ends at
  // the slower of the two, and the tree is not waited for past treeWaitMs.
  const tree = ctx.bridge({ op: 'ax', include_offscreen: false });
  tree.catch(() => {});
  const late = new Promise((_, reject) => setTimeout(() => reject(new Error(`accessibility did not answer within ${treeWaitMs} ms`)), treeWaitMs).unref?.());
  const [frameResult, treeResult] = await Promise.allSettled([ctx.capture(), Promise.race([tree, late])]);
  if (frameResult.status === 'rejected') throw frameResult.reason;
  const frame = frameResult.value;
  let elements = [], source = 'accessibility', foreground, note;
  // A dark, uniform picture is a locked or sleeping display: say so instead of reading it.
  const { channels } = await sharp(frame.data).stats();
  const dark = channels.slice(0, 3).every(c => c.mean < 12 && c.stdev < 6);
  if (dark && !(treeResult.status === 'fulfilled' && treeResult.value.elements?.length)) {
    return { frame, elements: [], source: 'none', note: 'screen: dark (the phone is locked or its display is off)', ms: Math.round(performance.now() - started) };
  }
  if (treeResult.status === 'fulfilled' && treeResult.value.elements?.length) {
    elements = treeResult.value.elements; foreground = treeResult.value.foreground;
    if (leavesUnnamedBand(listable(elements, frame), frame)) {
      try {
        const added = textOutside(await ctx.ocr(frame), elements, frame);
        if (added.length) { elements = [...elements, ...added]; source = 'accessibility + ocr'; }
      } catch (error) { if (stopped(error)) throw error; }
    }
  } else {
    if (treeResult.status === 'rejected' && stopped(treeResult.reason)) throw treeResult.reason;
    note = treeResult.status === 'rejected' ? treeResult.reason.message : 'accessibility returned no elements';
    try { elements = await ctx.ocr(frame); source = 'ocr'; }
    catch (error) { if (stopped(error)) throw error; note += `; OCR failed too: ${error.message}`; source = 'none'; }
  }
  return { frame, elements: listable(elements, frame), source, foreground, note, ms: Math.round(performance.now() - started) };
}

async function reply(ctx, seen, { full = false, actions = [], error } = {}) {
  const memory = state(ctx);
  memory.refs = new Map();
  const keysNow = new Set();
  const lines = seen.elements.map((element, index) => {
    const ref = index + 1, key = keyOf(element), f = box(element);
    memory.refs.set(ref, element); keysNow.add(key);
    const isNew = memory.previous.size > 0 && !memory.previous.has(key);
    return { isNew, text: `${isNew ? '+' : ' '}${ref} ${roleName(element)} "${labelOf(element)}" [${[f.x, f.y, f.width, f.height].map(Math.round).join(',')}]` };
  });
  const gone = [...memory.previous].filter(key => !keysNow.has(key)).slice(0, 20).map(key => key.replace('|', ' "') + '"');
  const fresh = memory.previous.size === 0;
  memory.previous = keysNow;
  const shown = full || fresh ? lines : lines.filter((line, index) => line.isNew || index < lineLimit);
  const app = seen.foreground ? (seen.foreground.name ?? seen.foreground.bundle_id ?? `pid ${seen.foreground.pid}`) : 'unknown';
  const header = [
    `app: ${app}   read: ${new Date().toISOString()} (${seen.ms} ms, ${seen.source})${seen.note ? `   note: ${seen.note}` : ''}`,
    ...actions.map(a => `did: ${a}`),
    ...(error ? [`error: ${error}`] : []),
    fresh ? `elements (${lines.length}):` : `elements (${lines.length}; + = new since the last read):`,
  ];
  const footer = gone.length ? [`gone since the last read: ${gone.join(', ')}`] : [];
  const image = await sharp(seen.frame.data).resize({ width: imageWidth }).jpeg({ quality: 60 }).toBuffer();
  return { content: [
    { type: 'text', text: [...header, ...shown.slice(0, full ? 1000 : lineLimit).map(l => l.text), ...footer].join('\n') },
    { type: 'image', data: image.toString('base64'), mimeType: 'image/jpeg' },
  ] };
}

const centre = element => { const f = box(element); return { x: f.x + f.width / 2, y: f.y + f.height / 2 }; };
// The device time one do call may spend on its actions and the wait after them; the read has its own cap.
const actionCapMs = Number(process.env.POKI_CUA_ACTION_CAP_MS) || 4000;
const quietMinMs = 150, quietMaxMs = 1500, stalledClockMs = 400;

class NotSent extends Error {}
function elementOf(ctx, ref) {
  const element = state(ctx).refs.get(Number(ref));
  if (!element) throw new NotSent(`No element ${ref} in the latest read; use a number from the last list.`);
  return element;
}
function pointOf(ctx, target) {
  if (Array.isArray(target)) return { x: Number(target[0]), y: Number(target[1]) };
  if (target && typeof target === 'object') return target.ref !== undefined ? centre(elementOf(ctx, target.ref)) : { x: Number(target.x), y: Number(target.y) };
  return centre(elementOf(ctx, target));
}
// Every element number an action names, so a stale one is refused before anything is sent.
function refsIn(action) {
  const refs = [];
  const add = value => { if (typeof value === 'number' || (typeof value === 'string' && /^\d+$/.test(value))) refs.push(Number(value)); else if (value && typeof value === 'object' && !Array.isArray(value) && value.ref !== undefined) refs.push(Number(value.ref)); };
  for (const key of ['tap', 'double_tap', 'long_press', 'pinch']) if (key in action) add(action[key]);
  if (action.ref !== undefined) add(action.ref);
  if (action.in !== undefined) add(action.in);
  if (action.drag && !Array.isArray(action.drag)) { add(action.drag.from); add(action.drag.to); }
  if (action.scroll_to && typeof action.scroll_to === 'object' && action.scroll_to.ref !== undefined) add(action.scroll_to.ref);
  return refs;
}

// One input to the device, and what is known about its delivery: sent, not_sent (refused before
// anything reached the phone) or unknown (it may have been delivered).
async function send(ctx, request) {
  const answer = await ctx.input(request);
  // An absent or contradictory delivery receipt cannot authorize the next input.
  // Unknown delivery must stay unknown: it may already have reached the iPhone.
  if (answer?.sent === true && !answer.isError && !answer.stopped && !['unknown', 'not_sent'].includes(answer.outcome)) return answer;
  const why = answer?.error ?? answer?.message ?? 'the bridge did not confirm input delivery';
  const failure = new Error(why);
  failure.delivery = answer?.outcome === 'unknown' ? 'unknown'
    : answer?.sent === false || answer?.outcome === 'not_sent' ? 'not_sent' : 'unknown';
  throw failure;
}

// The pasteboard as it is, when it can be put back exactly: empty, or one plain text item.
async function savedClipboard(ctx) {
  try {
    const { items } = await ctx.bridge({ op: 'pasteboard', action: 'items' });
    if (!Array.isArray(items)) return undefined;
    if (!items.length) return { empty: true };
    if (items.length !== 1 || items[0].state !== 'inline' || !/text|string/i.test(items[0].uti ?? '')) return undefined;
    const { text } = await ctx.bridge({ op: 'pasteboard', action: 'get' });
    return typeof text === 'string' ? { text } : undefined;
  } catch (error) { if (stopped(error)) throw error; return undefined; }
}
async function restoreClipboard(ctx, saved) {
  if (saved.empty) return 'was empty';
  try {
    const { text } = await ctx.bridge({ op: 'pasteboard', action: 'get' });
    if (text !== saved.text) await ctx.bridge({ op: 'pasteboard', action: 'set', text: saved.text });
    return 'restored';
  } catch (error) { if (stopped(error)) throw error; return 'restore failed'; }
}

// Text into the field being edited: the whole string as hardware key presses in one request; the
// pasteboard only when the keyboard cannot type it, with the user's clipboard saved first and put
// back afterwards. A clipboard that cannot be read back exactly is never pasted over.
// A simulator types with its own type_text instead: key presses, and a paste through the
// simulator's pasteboard for text the keyboard has no key for.
async function typeText(ctx, text, clear = false) {
  const simulator = (await ctx.target()).kind === 'simulator';
  const typed = await ctx.input(simulator ? { op: 'type_text', text, clear, submit: false } : { op: 'type_keys', text, clear });
  if (typed?.sent === true && !typed.isError && !typed.stopped && !['unknown', 'not_sent'].includes(typed.outcome)) return typed?.clipboard_changed ? "pasted; the simulator's clipboard keeps the text" : 'keys';
  // A backend that types every character in one request (WebDriverAgent, a simulator) has no paste to fall back on.
  if (ctx.typesEverything || simulator) { const e = new Error(`typing failed: ${typed?.error ?? typed?.instruction ?? 'no answer'}`); e.delivery = typed?.outcome === 'not_sent' ? 'not_sent' : 'unknown'; throw e; }
  // Only a request the bridge refused before sending (a character with no key, an older bridge) may
  // be pasted instead: after a failure part way, some keys may have reached the field, and what
  // they did (a return that submitted, a field that moved on) a paste cannot undo, clear or not.
  if (!/cannot type|unknown variant|at most 2000/i.test(String(typed?.error ?? ''))) { const e = new Error(`typing failed part way (${typed?.error ?? 'no answer'}); not pasted, so the text is not entered twice`); e.delivery = 'unknown'; throw e; }
  const saved = await savedClipboard(ctx);
  if (!saved) { const e = new Error('the keyboard cannot type this text, and the clipboard cannot be saved and put back, so it was not pasted over'); e.delivery = 'not_sent'; throw e; }
  let restored;
  try { await send(ctx, { op: 'type_text', text, clear, submit: false }); }
  finally { restored = await restoreClipboard(ctx, saved); }
  return `pasted, clipboard ${restored}`;
}

// Gestures are named verbs with defaults: the model names a direction or a target, never a path.
// The area a swipe moves is the element named by in, or the screen. direction is where the finger goes.
function areaOf(ctx, ref, size) { return ref === undefined ? { x: 0, y: 0, width: size.width, height: size.height } : box(elementOf(ctx, ref)); }
function swipePath(area, direction, distance = 'long') {
  const d = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }[direction];
  if (!d) throw new NotSent('swipe must be up, down, left or right');
  const half = (d[0] ? area.width : area.height) * (distance === 'short' ? 0.2 : 0.35);
  const cx = area.x + area.width / 2, cy = area.y + area.height / 2;
  return { x1: cx - d[0] * half, y1: cy - d[1] * half, x2: cx + d[0] * half, y2: cy + d[1] * half };
}
const finger = { down: 'up', up: 'down', right: 'left', left: 'right' };
const onScreen = (e, size) => { const f = box(e); return f.x >= 0 && f.y >= 0 && f.x + f.width <= size.width && f.y + f.height <= size.height; };
const shows = (e, text) => labelOf(e).toLocaleLowerCase().includes(text.toLocaleLowerCase());

// Swipes until the target is fully on screen, with a quick tree read after each swipe: one action
// for the model however many swipes it takes. Stops at the end of the list, at max_swipes, or when
// the action time runs out.
async function scrollTo(ctx, spec, size, until) {
  const target = typeof spec === 'string' ? { text: spec } : spec;
  const wanted = target.ref !== undefined ? keyOf(elementOf(ctx, target.ref)) : undefined;
  if (!wanted && typeof target.text !== 'string') throw new NotSent('scroll_to takes text or ref');
  const area = areaOf(ctx, target.in, size), max = Math.min(12, target.max_swipes ?? 6);
  const hit = elements => elements.find(e => (wanted ? keyOf(e) === wanted : shows(e, target.text)) && onScreen(e, size));
  let elements = [...state(ctx).refs.values()], swipes = 0, last;
  while (!hit(elements) && swipes < max && until - performance.now() > 900) {
    await send(ctx, { op: 'drag', ...swipePath(area, finger[target.direction ?? 'down']), duration_ms: 250, hold_ms: 0, end_hold_ms: 100 });
    swipes++;
    await pause(250);
    let seen;
    try { seen = await Promise.race([ctx.bridge({ op: 'ax', include_offscreen: false }), new Promise(done => setTimeout(done, Math.max(200, Math.min(1200, until - performance.now()))))]); }
    catch (error) { if (stopped(error)) throw error; }
    if (!seen?.elements?.length) continue;
    const key = seen.elements.map(e => `${keyOf(e)}@${Math.round(box(e).y)}`).join(';');
    if (key === last) return `${swipes} swipes, not found: the list stopped moving`;
    last = key; elements = seen.elements;
  }
  const found = hit(elements);
  return found ? `${swipes} swipes, found at [${[box(found).x, box(found).y].map(Math.round).join(',')}]` : `${swipes} swipes, not found${swipes >= max ? ` within ${max} swipes` : ''}`;
}

function targetElement(ctx, spec, point) {
  const memory = state(ctx);
  if (typeof spec === 'number' || (typeof spec === 'string' && /^\d+$/.test(spec))) return elementOf(ctx, spec);
  if (spec && typeof spec === 'object' && !Array.isArray(spec) && spec.ref !== undefined) return elementOf(ctx, spec.ref);
  if (!point) return undefined;
  return [...memory.refs.values()].filter(e => {
    const f = box(e);
    return point.x >= f.x && point.x <= f.x + f.width && point.y >= f.y && point.y <= f.y + f.height;
  }).at(-1);
}

async function deviceLabel(ctx) {
  const target = await ctx.target?.().catch(() => undefined);
  return target?.name ?? target?.id ?? 'selected device';
}

async function guardAction(ctx, element, budget, options = {}) {
  const memory = state(ctx);
  const secureOnScreen = [...memory.refs.values()].some(e => /secure/i.test(roleName(e)));
  const reason = sensitiveReason(element, { ...options, appBundle: memory.lastForeground?.bundle_id ?? '', secureOnScreen });
  if (!reason) return;
  await requireApproval(ctx, `是否允许执行敏感操作（${reason}）？\n设备：${await deviceLabel(ctx)}`, budget);
}

async function tapByText(ctx, spec, budget) {
  const wanted = typeof spec === 'string' ? { text: spec } : spec ?? {};
  const query = String(wanted.text ?? '').trim();
  if (!query) throw new NotSent('tap_text takes non-empty text');
  const limit = Math.min(budget.until, performance.now() + 3000);
  let lastElements = [...state(ctx).refs.values()];
  for (let attempt = 0; ; attempt++) {
    if (attempt > 0 || !lastElements.length) {
      const seen = await read(ctx);
      lastElements = seen.elements;
      state(ctx).lastForeground = seen.foreground;
    }
    const found = matching(lastElements.map(e => ({ ...e, visible: true })), query, Boolean(wanted.exact));
    if (found.length === 1) {
      await guardAction(ctx, found[0], budget);
      const p = centre(found[0]);
      await send(ctx, { op: 'tap', x: p.x, y: p.y, duration_ms: 50 });
      return `tap_text ${JSON.stringify(query)}`;
    }
    if (found.length > 1) throw new NotSent(`${found.length} elements match ${JSON.stringify(query)}; call look and tap by element number`);
    if (performance.now() + 250 >= limit) throw new NotSent(`no visible element matches ${JSON.stringify(query)}`);
    await pause(200);
  }
}

async function waitUntil(ctx, spec, budget) {
  const target = typeof spec === 'string' ? { text: spec } : spec ?? {};
  const waitMs = Math.min(10000, Math.max(200, Number(target.ms ?? 3000)));
  if (performance.now() + waitMs > budget.until) budget.until = performance.now() + waitMs + 500;
  const deadlineAt = Math.min(budget.until - 200, performance.now() + waitMs);
  const started = performance.now();
  let previousKey;
  while (performance.now() < deadlineAt) {
    const seen = await read(ctx);
    state(ctx).lastForeground = seen.foreground;
    if (target.settled) {
      const currentKey = seen.elements.map(e => `${keyOf(e)}@${Math.round(box(e).x)},${Math.round(box(e).y)}`).join(';');
      if (previousKey !== undefined && currentKey === previousKey) return `settled in ${Math.round(performance.now() - started)} ms`;
      previousKey = currentKey;
    } else {
      const query = String(target.text ?? '').trim();
      if (!query) throw new NotSent('wait_until takes text or settled: true');
      const found = matching(seen.elements.map(e => ({ ...e, visible: true })), query, false);
      if (target.gone ? found.length === 0 : found.length > 0) return `${target.gone ? 'gone' : 'found'} in ${Math.round(performance.now() - started)} ms`;
    }
    await pause(Math.min(250, Math.max(50, deadlineAt - performance.now())));
  }
  throw new NotSent(`wait_until timed out after ${Math.round(performance.now() - started)} ms`);
}

async function navigateBack(ctx, size, budget) {
  const elements = [...state(ctx).refs.values()];
  const backControls = elements.filter(e => /^(back|返回|上一页|上一頁)$/i.test(e.label ?? e.text ?? '') && box(e).x < size.width / 2);
  if (backControls.length === 1) {
    await guardAction(ctx, backControls[0], budget);
    const p = centre(backControls[0]);
    await send(ctx, { op: 'tap', x: p.x, y: p.y, duration_ms: 50 });
    return 'back';
  }
  await send(ctx, { op: 'drag', x1: 1, y1: Math.round(size.height / 2), x2: Math.round(size.width * 0.8), y2: Math.round(size.height / 2), duration_ms: 400, hold_ms: 0 });
  return 'back';
}

async function perform(ctx, action, size, budget) {
  if ('tap' in action) {
    const p = pointOf(ctx, action.tap);
    await guardAction(ctx, targetElement(ctx, action.tap, p), budget);
    await send(ctx, { op: 'tap', x: p.x, y: p.y, duration_ms: 50 });
    return ['tap', `tap ${JSON.stringify(action.tap)}`];
  }
  if ('double_tap' in action) {
    const p = pointOf(ctx, action.double_tap);
    await guardAction(ctx, targetElement(ctx, action.double_tap, p), budget);
    await send(ctx, { op: 'double_tap', x: p.x, y: p.y, duration_ms: 50 });
    return ['tap', `double_tap ${JSON.stringify(action.double_tap)}`];
  }
  if ('tap_text' in action) return ['tap', await tapByText(ctx, action.tap_text, budget)];
  if ('type' in action) {
    const p = action.ref !== undefined ? pointOf(ctx, action.ref) : undefined;
    const target = action.ref !== undefined ? targetElement(ctx, action.ref, p) : undefined;
    await guardAction(ctx, target, budget, { typing: true });
    if (p) { await send(ctx, { op: 'tap', x: p.x, y: p.y, duration_ms: 50 }); await pause(250); }
    const how = await typeText(ctx, String(action.type), Boolean(action.clear));
    return ['type', `type ${JSON.stringify(action.type)} (${how})`];
  }
  if ('key' in action) { await send(ctx, { op: 'key', key: String(action.key) }); return ['key', `key ${action.key}`]; }
  if ('swipe' in action) {
    const spec = typeof action.swipe === 'string' ? { direction: action.swipe } : action.swipe ?? {};
    const path = swipePath(areaOf(ctx, spec.in ?? action.in, size), spec.direction, spec.distance);
    await send(ctx, { op: 'drag', ...path, duration_ms: 300 }); return ['swipe', `swipe ${spec.direction}${spec.in ?? action.in ? ` in ${spec.in ?? action.in}` : ''}`];
  }
  if ('scroll_to' in action) return ['scroll_to', `scroll_to ${JSON.stringify(action.scroll_to)}: ${await scrollTo(ctx, action.scroll_to, size, budget.until)}`];
  if ('long_press' in action) {
    const spec = action.long_press, p = pointOf(ctx, spec), ms = Math.min(5000, Math.max(100, spec?.ms ?? action.ms ?? 600));
    await guardAction(ctx, targetElement(ctx, spec, p), budget);
    await send(ctx, { op: 'long_press', x: p.x, y: p.y, duration_ms: ms }); return ['long_press', `long_press ${JSON.stringify(spec)} ${ms} ms`];
  }
  if ('drag' in action) {
    const spec = action.drag;
    const [from, to] = Array.isArray(spec) ? [{ x: spec[0], y: spec[1] }, { x: spec[2], y: spec[3] }] : [pointOf(ctx, spec.from), pointOf(ctx, spec.to)];
    const ms = Math.min(3000, Math.max(100, spec.ms ?? 400));
    const holdMs = Array.isArray(spec) ? 0 : Math.min(3000, Math.max(0, spec.hold_ms ?? 300));
    await send(ctx, { op: 'drag', x1: Number(from.x), y1: Number(from.y), x2: Number(to.x), y2: Number(to.y), duration_ms: ms, hold_ms: holdMs });
    return ['drag', `drag ${JSON.stringify(spec)}`];
  }
  if ('pinch' in action) {
    const spec = action.pinch, p = pointOf(ctx, spec), scale = Math.min(4, Math.max(0.25, Number(spec?.scale ?? action.scale ?? 2)));
    const start = Math.min(size.width, size.height) * (scale > 1 ? 0.12 : 0.3);
    await send(ctx, { op: 'pinch', x: p.x, y: p.y, start_distance: start, end_distance: start * scale, duration_ms: 500 }); return ['pinch', `pinch ${JSON.stringify(spec)} x${scale}`];
  }
  if ('button' in action) { await send(ctx, { op: 'button', button: String(action.button) }); return ['button', `button ${action.button}`]; }
  if ('back' in action) {
    if (!action.back) throw new NotSent('back takes true');
    return ['swipe', await navigateBack(ctx, size, budget)];
  }
  if ('launch' in action) {
    // {launch: "id"} brings the app to the front as it was; {launch: {bundle, fresh: true}} starts it anew.
    const spec = typeof action.launch === 'string' ? { bundle: action.launch } : action.launch ?? {};
    if (!spec.bundle && !spec.name) throw new NotSent('launch takes a bundle id');
    if (!spec.bundle && spec.name) {
      await platformTool(ctx, 'launch_app', { name: String(spec.name), fresh: Boolean(spec.fresh) });
      return ['launch', `launch ${spec.name}${spec.fresh ? ' (fresh)' : ''}`];
    }
    // A simulator has no bridge op for it; launch_app starts it with simctl and waits for its interface.
    if ((await ctx.target()).kind === 'simulator') await platformTool(ctx, 'launch_app', { bundle_id: String(spec.bundle), fresh: Boolean(spec.fresh) });
    else await ctx.bridge({ op: 'launch_app', bundle_id: String(spec.bundle), ...(spec.fresh ? { terminate_existing: true } : {}) });
    return ['launch', `launch ${spec.bundle}${spec.fresh ? ' (fresh)' : ''}`];
  }
  if ('open_url' in action) {
    const url = typeof action.open_url === 'string' ? action.open_url : action.open_url?.url;
    if (typeof url !== 'string' || !url.trim()) throw new NotSent('open_url takes a URL string');
    await requireApproval(ctx, `是否允许打开链接？\n设备：${await deviceLabel(ctx)}\n${url}`, budget);
    if (ctx.wda) await ctx.bridge({ op: 'open_url', url });
    else await platformTool(ctx, 'open_url', { url });
    return ['launch', `open_url ${url}`];
  }
  if ('wait_until' in action) return ['wait', `wait_until ${JSON.stringify(action.wait_until)}: ${await waitUntil(ctx, action.wait_until, budget)}`];
  if ('handoff' in action) {
    const spec = typeof action.handoff === 'string' ? { kind: 'other', text: action.handoff } : action.handoff ?? {};
    const reason = String(spec.text ?? '').trim();
    if (!reason) throw new NotSent('handoff takes {kind, text}');
    await requireApproval(ctx, reason, budget, { alwaysAsk: true });
    return ['wait', `handoff (${spec.kind ?? 'other'}): confirmed`];
  }
  if ('wait' in action) { await pause(Math.min(Number(action.wait) || 0, 3000)); return ['wait', `wait ${action.wait} ms`]; }
  throw new NotSent(`Unknown action ${JSON.stringify(action)}`);
}

// After the last action: until the phone's packet clock goes quiet (at least quietMinMs, at most
// quietMaxMs, a fixed stalledClockMs when the clock does not answer), or a fixed pause per action
// kind without a live screen.
async function quiet(ctx, kind, budget) {
  const started = performance.now();
  let screen;
  try { screen = ctx.liveScreen?.(await ctx.target()); } catch (error) { if (stopped(error)) throw error; }
  if (!screen?.waitSettled) { await pause(Math.min(budget, settleAfterMs[kind] ?? 400)); return `${Math.round(performance.now() - started)} ms (fixed)`; }
  await pause(Math.min(quietMinMs, budget));
  const left = Math.min(quietMaxMs, budget) - (performance.now() - started);
  let settled;
  try { settled = await Promise.race([screen.waitSettled({ timeoutMs: Math.max(50, Math.round(left)), maxWidth: 64 }), new Promise(done => setTimeout(done, left + 200))]); }
  catch (error) { if (stopped(error)) throw error; }
  if (!settled) { const rest = Math.min(stalledClockMs, budget) - (performance.now() - started); if (rest > 0) await pause(rest); return `${Math.round(performance.now() - started)} ms (packet clock silent)`; }
  return `${Math.round(performance.now() - started)} ms (${settled.settled ? 'quiet' : 'still moving'})`;
}

// What stops dispatching: a phone that is locked or dark, or Poki's own app in front.
function holdReason(memory) {
  if (memory.lastNote && /dark|locked/i.test(memory.lastNote)) return 'the phone is locked or its display is off; unlock it';
  if (/poki/i.test(memory.lastForeground?.bundle_id ?? '')) return "Poki's own app is in front";
  return undefined;
}

async function returnToOrigin(ctx, origin, currentBundle) {
  if (!origin) return 'finish: task completed';
  if (currentBundle === origin) return `finish: ${origin} is already in front`;
  try {
    if (origin === 'com.apple.springboard') {
      await ctx.input({ op: 'button', button: 'home' });
      return 'finish: returned to Home Screen';
    }
    if ((await ctx.target()).kind === 'simulator') await platformTool(ctx, 'launch_app', { bundle_id: origin, fresh: false });
    else await ctx.bridge({ op: 'launch_app', bundle_id: origin });
    return `finish: returned to ${origin}`;
  } catch (error) {
    if (stopped(error)) throw error;
    return `finish: could not return to ${origin} (${error.message})`;
  }
}

async function readAndReply(ctx, options) {
  const memory = state(ctx);
  let seen;
  try { seen = await read(ctx); }
  catch (error) {
    if (stopped(error)) throw error;
    // No read: what was sent is reported, with each sent action's result unknown, and nothing else.
    const actions = (options.actions ?? []).map(line => line.replace(/\(sent,/, '(unknown: no read after it,'));
    return { isError: true, content: [{ type: 'text', text: [`read: failed: ${error.message}`, ...actions.map(a => `did: ${a}`), ...(options.error ? [`error: ${options.error}`] : [])].join('\n') }] };
  }
  memory.lastNote = seen.note; memory.lastForeground = seen.foreground;
  if (!memory.originApp && seen.foreground?.bundle_id && !/poki/i.test(seen.foreground.bundle_id)) {
    memory.originApp = seen.foreground.bundle_id;
  }
  const result = await reply(ctx, seen, options);
  if (options.finish && !options.error) {
    const origin = memory.originApp;
    memory.originApp = undefined;
    const finishLine = await returnToOrigin(ctx, origin, seen.foreground?.bundle_id);
    const textBlock = result.content.find(c => c.type === 'text');
    if (textBlock) {
      const lines = textBlock.text.split('\n');
      lines.splice(Math.min(1, lines.length), 0, finishLine);
      textBlock.text = lines.join('\n');
    }
  }
  return result;
}

// The device the tools drive: the bridge by default, or WebDriverAgent on the phone
// (POKI_CUA_BACKEND=wda, POKI_WDA_URL), with the same answers either way.
const backend = ctx => process.env.POKI_CUA_BACKEND === 'wda' ? wdaContext(ctx) : ctx;

export async function look(ctx, args = {}) {
  ctx = backend(ctx);
  const target = await ctx.target?.().catch(() => undefined);
  state(ctx, target?.id);
  return readAndReply(ctx, { full: args.full });
}

export async function act(ctx, args = {}) {
  ctx = backend(ctx);
  const target = await ctx.target?.().catch(() => undefined);
  const memory = state(ctx, target?.id), actions = args.actions ?? [], done = [];
  // A number that is not in the latest read is refused before anything is sent, with the list now.
  const stale = actions.flatMap(refsIn).filter(ref => !memory.refs.has(ref));
  if (stale.length) return { isError: true, ...await readAndReply(ctx, { full: true, error: `element ${[...new Set(stale)].join(', ')} is not in the latest read; nothing was sent. The current elements are below.` }) };
  let error, last;
  const started = performance.now(), budget = { until: started + actionCapMs };
  const size = ctx.size ?? await ctx.screenSize();
  for (const [index, action] of actions.entries()) {
    const held = holdReason(memory);
    if (held) { error = `stopped before action ${index + 1}: ${held}; nothing more was sent`; break; }
    if (budget.until - performance.now() < 300) { error = `stopped before action ${index + 1}: the ${actionCapMs} ms action time ran out; nothing more was sent`; break; }
    const began = performance.now();
    try {
      const [kind, text] = await perform(ctx, action, size, budget);
      last = kind;
      done.push(`${text} (sent, ${Math.round(performance.now() - began)} ms)`);
    } catch (e) {
      if (stopped(e)) throw e;
      const delivery = e instanceof NotSent ? 'not_sent' : e.delivery ?? 'unknown';
      done.push(`${JSON.stringify(action)} (${delivery}, ${Math.round(performance.now() - began)} ms)`);
      // An action that may have been delivered is never sent again by us, and nothing after it is sent.
      error = `action ${index + 1} ${delivery === 'unknown' ? 'may have been delivered' : 'was not sent'}: ${e.message}${index + 1 < actions.length ? '; the actions after it were not sent' : ''}`;
      break;
    }
  }
  if (last) done.push(`waited ${await quiet(ctx, last, Math.max(0, budget.until - performance.now()))}`);
  return { ...(error ? { isError: true } : {}), ...await readAndReply(ctx, { full: args.full, finish: args.finish, actions: done, error }) };
}

export const definitions = [
  ['look', 'Read the screen now: the app in front, the numbered elements (role, label = value, [x,y,w,h] in screen points; + marks elements new since the last read), and a screenshot. full=true lists every element. Optional device selects an attached device by id or name. Numbers refer to this read only.', { type: 'object', properties: { full: { type: 'boolean' }, device: { type: 'string' } }, additionalProperties: false }, true],
  ['do', 'Run actions in order, then read the screen once and return the same facts as look, with a screenshot. Actions: {tap: n} or {tap: [x, y]}; {double_tap: n or [x, y]}; {tap_text: "text"}; {type: "text", ref?: n, clear?} (taps n first, then types the text as key presses; text the keyboard cannot type is pasted with your clipboard saved and put back); {key: "return"|"delete"|"tab"|"space"|"escape"|...}; {swipe: "up"|"down"|"left"|"right"} or {swipe: {direction, in?: n, distance?: "short"|"long"}} (direction is where the finger moves); {scroll_to: "text"} or {scroll_to: {text or ref, in?: n, direction?: "down", max_swipes?: 6}} (swipes until it is fully on screen); {long_press: n or [x, y] or {ref, ms?}}; {drag: {from: n or [x, y], to: n or [x, y], ms?, hold_ms?}} or {drag: [x1, y1, x2, y2]}; {pinch: {ref or x, y, scale}}; {button: "home"|"lock"|"volume_up"|"volume_down"}; {back: true}; {launch: "bundle id"} or {launch: {bundle, fresh: true}} (use list_apps if you need the bundle id); {open_url: "https://..."}; {wait_until: "text"} or {wait_until: {text, gone?, ms?}} or {wait_until: {settled: true, ms?}}; {wait: ms}; {handoff: {kind, text}}. Set finish=true on the final do call of a task (actions may be empty) to return to the app where the task started. Sensitive actions (payments, deletions, calls, message sends, password entry, and open_url) ask for local approval unless preapproved. Each action is reported as sent, not_sent or unknown; execution stops at the first failed action and never re-sends an unknown one.', { type: 'object', properties: { actions: { type: 'array', items: { type: 'object' }, minItems: 0, maxItems: 20 }, full: { type: 'boolean' }, finish: { type: 'boolean' }, device: { type: 'string' } }, required: ['actions'], additionalProperties: false }, false],
];
export const tools = new Set(['look', 'do', 'list_apps', 'list_devices', 'select_device', 'poki_mcp_status']);
export const instructions = 'look reads the screen; do runs actions in order and then reads the screen once. Both return numbered elements and a screenshot. Use element numbers from the latest answer, call list_apps when you need an app bundle id for launch, and set finish=true on your final do call when the task is complete. With one device attached, skip list_devices and select_device.';
