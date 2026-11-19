#!/usr/bin/env node
// Poki voice bridge: hands the Poki app short-lived OpenAI Realtime credentials, so the phone never
// holds the API key, and runs the voice tools that move the phone through the local Poki MCP.
//
//   OPENAI_API_KEY=... POKI_MCP_STATE_DIR=... node bin/voice-bridge.mjs [--port 47830] [--host 0.0.0.0] [--device <id>] [--mac-tools]
//
// By default the voice model only listens and speaks: it can read the screen (look) and hands work on the
// phone to Poki's chat agent on the phone (run_task, check_task, stop_task), and the bridge only hands out
// credentials. --mac-tools instead offers the tools below that move the phone through this Mac's Poki MCP
// (it must be running).
//
// The phone opens http://<this Mac>:<port>/voice/<secret>/ ; the secret is in voice-bridge.json in the
// state directory. Endpoints under that prefix:
//   GET  token   a client secret for one Realtime session (expires in 60 s), plus the session it opens
//   POST tool    {call_id, name, arguments}: runs one voice tool once; the same call_id never runs twice.
//                tap_text first comes without `checked` and taps nothing: the answer is {state: "check", app,
//                target}, the element it would tap and the app in front. The phone checks that with Poki's
//                approval rules (PokiCore), asks the owner when they say so, and sends the same call again
//                with checked: {app, text}; only then is the element tapped, matched exactly, in that app.
// With --test-dir <dir> (test runs of a development build, launched with -pokiVoiceLink "poki://voice?test=1-20"):
//   GET  utterance?n=01  recorded speech <dir>/u01.24k.pcm (24 kHz mono PCM16)
//   POST report          one finished test turn, appended to voice-test-report.jsonl in the state directory
import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { networkInterfaces } from 'node:os';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { root, stateDir } from '../src/config.mjs';
import { matching } from '../src/interaction.mjs';

const arg = (name, fallback) => { const i = process.argv.indexOf(`--${name}`); return i < 0 ? fallback : process.argv[i + 1]; };
const port = Number(arg('port', '47830'));
const host = arg('host', '0.0.0.0');
const device = arg('device', process.env.POKI_VOICE_DEVICE);
const testDir = arg('test-dir');
const macTools = process.argv.includes('--mac-tools');
const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) { console.error('Set OPENAI_API_KEY (for example from the keychain) before starting the voice bridge.'); process.exit(1); }

const model = process.env.POKI_VOICE_MODEL ?? 'gpt-realtime-2.1';
// The phone says the iPhone's language (?language=zh-Hans-CN): the one the session hears and speaks.
const languageName = code => { try { return /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(code ?? '') ? new Intl.DisplayNames(['en'], { type: 'language' }).of(code) : 'English'; } catch { return 'English'; } };
// The same text as the phone's own (VoiceDirect.swift); --mac-tools keeps the Mac's tools and leaves out the phone's agent.
const instructions = language => `# Role
${macTools ? "You are Poki, a voice assistant that operates the user's iPhone with tools." : "You are Poki, a voice assistant on the user's iPhone. You listen and speak; Poki's agent does the work on the phone."}

# Language
- Speak ${languageName(language)}, the iPhone's language, from your first sentence to your last.
- Never change language on your own: not for tool results, screen text, screenshots or notes from Poki in another language, not for a short sound, a word or a name in another language, and not for audio you could not make out. Change only when the user asks you to speak another language.
- Translate only when the user asks for a translation.

# Short sounds and unclear audio
- When the latest audio holds no request (a filler or backchannel such as 嗯, 哦, 啊, uh-huh or ok, a cough, noise, or a word cut off as the talk opens), call wait_for_user and say nothing.
- When the user clearly spoke to you but you could not make out the request, ask in one short sentence what they want, and do nothing until they answer. Never act on a guess.
- When a request leaves out what it is about (帮我打开 with no app named, 发给他 with nobody named), ask for that one thing in a few words (打开哪个？) and call no tool. Never fill it in from earlier in the talk.

# Replies
- A clear request to do something on the phone: first say only "好" ("OK" in English), one word and nothing after it (never "好，我来帮你打开" or "好，我帮你往下翻"), then call the tool in the same turn. A question about the screen gets no such word: call look at once.
- A request that sends something to someone (a message, a file, an email): first say in one short sentence what you will send to whom ("我把 hello 发给文件传输助手"), then call run_task in the same turn. Do not wait for the user to confirm; they can say stop.
- After you call run_task, say nothing until its result arrives: no "我来处理", no "稍等", no "已经加到任务里", no "正在处理中". Its progress shows on the phone. Say how it is going only when the user asks.
- When it is done, say the result in one short sentence; once an app is open, say that it is open ("微信打开了").
- When the user says stop (停, 别说了, stop) at any time: stop talking, and call stop_task at once when a task is running.
- Do not describe what you did or what else is on the screen, and add no greetings, filler or offers of more help. Explain only when the user asks.

${macTools ? macRules : taskRules}`;
// The phone's VoiceDirect.taskRules, word for word.
const taskRules = `# Tools
- Never guess facts about the phone. To say what is on the screen right now, call look. A screenshot of the screen follows each look answer as an image: use it with the numbered elements to say what is on the screen. Asked what is on the screen, name the app and its main content in one sentence, without listing buttons.
- To open an app and do nothing more in it, call open_app with its name: it opens at once.
- To scroll the screen in front (往下翻, 往上翻, 下一页), go back one page (返回, 返回上一页) or go to the Home Screen (回到桌面, 回主屏幕), call phone_step: it is done at once.
- To do anything else on the phone (tap, type, send, change a setting, find or read something in an app, go to an app's own first page, open an app and do something in it), call run_task at once with the whole request. Poki's agent does every step and answers with how it ended. Never repeat a task that already ran, including tasks from before a reconnect that the conversation says have finished.
- Short commands are phone actions too: 往下翻, 翻一下 and 下一页 mean scroll. When you hear 翻译 with no language named and nothing to translate, the user said 翻 (scroll).
- While a task runs: when the user adds to it or changes it, call run_task with only what they added; it goes to the running task. When they ask how it is going (到哪了), call check_task and say where it is in one sentence. When they tell you to stop or cancel it, call stop_task at once.
- Poki's agent can open and operate every app installed on this iPhone, Apple's and anyone else's (WeChat, Instagram, Uber, a bank, a game): never tell the user an app is out of reach before a task has tried.

# Approvals and stopping
- A step that sends, pays, deletes or calls waits until the user allows it on the phone; if the result says they did not, say so in one sentence and do not try another way.
- Only the user approves, with their own finger: never ask for a task that opens Poki to tap Allow, Deny or anything else in it.`;
const macRules = `# Tools
- When a tool can answer or do what the user asks, call it at once. Never guess facts about the phone.
- A request can take several steps (open an app, tap, type): call one tool after another until it is done.
- Never repeat an action that already ran, including actions from before a reconnect that the conversation says have finished.
- To read a page, open it first, then read the screen.

# Approvals and stopping
- Tapping something that sends, pays, deletes or calls waits until the user allows it on the phone; if the result says they did not, tell them in one sentence and do not try another way.
- Only the user approves, with their own finger: never open Poki to tap Allow, Deny or anything else in it.
- If the user tells you to stop or be quiet, stop talking, but anything already running keeps running; when its result arrives, report it in one sentence.`;

// The voice tools. `local` tools are answered by the phone itself; the bridge runs the others through Poki MCP.
// run_task, check_task and stop_task are the phone's VoiceTasks.tools.
const none = { type: 'object', properties: {}, additionalProperties: false };
// The phone closes this call and asks for no answer after it (VoiceDirect.waitForUser).
const waitForUser = { name: 'wait_for_user', local: true, description: 'End your turn without speaking, when the latest audio needs no answer: a filler or backchannel such as 嗯 or uh-huh, a cough, noise, or speech not meant for you.', parameters: none };
const phoneTools = [
  waitForUser,
  { name: 'get_ios_version', local: true, description: 'Read the iPhone model and its iOS version. Changes nothing on the phone.', parameters: none },
  { name: 'look', local: true, description: 'Read the iPhone screen now: the app in front, its numbered elements (role, label, frame in points) and a screenshot. Changes nothing.', parameters: none },
  { name: 'open_app', local: true, description: "Open one app on the iPhone by the name the user said (微信, Settings, 支付宝), and do nothing more in it. It opens in a few seconds, without Poki's agent. Before it say only 好, one word, and nothing else.", parameters: { type: 'object', properties: { app: { type: 'string', description: "The app's name as the user said it." } }, required: ['app'], additionalProperties: false } },
  { name: 'phone_step', local: true, description: "One gesture on the screen in front, without Poki's agent: scroll_down (往下翻), scroll_up (往上翻), back (返回上一页) or home (回到桌面). Done in a second or two; the answer says what is on the screen after it. Before it say only 好, one word, and nothing else.", parameters: { type: 'object', properties: { step: { type: 'string', enum: ['back', 'home', 'scroll_down', 'scroll_up'] } }, required: ['step'], additionalProperties: false } },
  { name: 'run_task', local: true, description: "Hand one task on the iPhone to Poki's agent, which does every step (opens apps, taps, types, reads) and answers with how it ended. It can take from a few seconds to a few minutes; the user can talk meanwhile. While a task runs, a second run_task adds to that task instead of starting another. Before it say only 好, one word, and nothing else; only a task that sends something gets the one sentence that says what it sends to whom.", parameters: { type: 'object', properties: { task: { type: 'string', description: "What to do, in the user's own language and plain words, as you would ask a person. Include every detail the user gave (names, the exact text to type or send). Poki's agent hears nothing else of this conversation." } }, required: ['task'], additionalProperties: false } },
  { name: 'check_task', local: true, description: "Say how the task Poki's agent is doing is going: how long it has run, its plan and the step under way, and whether it waits for the user to allow something on the phone. Changes nothing.", parameters: none },
  { name: 'stop_task', local: true, description: "Stop the task Poki's agent is doing. The action the phone is in the middle of finishes; nothing more is done.", parameters: none },
];
const macVoiceTools = [
  waitForUser,
  { name: 'get_ios_version', local: true, description: 'Read the iPhone model and its iOS version. Changes nothing on the phone.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'open_settings', description: 'Open the Settings app on the iPhone, or one of its pages (about, general, software_update, battery, wifi, display, and so on). Leave out page to open Settings itself.', parameters: { type: 'object', properties: { page: { type: 'string', enum: ['about', 'general', 'software_update', 'battery', 'wifi', 'bluetooth', 'display', 'sounds', 'notifications', 'privacy', 'screen_time'] } }, additionalProperties: false } },
  { name: 'read_screen', description: 'Read the text and controls on the iPhone screen now.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'open_app', description: 'Open an app on the iPhone by its name, for example Calculator, Clock, Weather.', parameters: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'], additionalProperties: false } },
  { name: 'tap_text', description: 'Tap the visible button or row whose text matches.', parameters: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false } },
  { name: 'go_home', description: 'Go to the Home Screen.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
];
const voiceTools = macTools ? macVoiceTools : phoneTools;

// How the user's speech is written into the talk (the model hears the audio itself): the iPhone's language and
// English as the languages to expect, as VoiceDirect.transcription does.
const transcription = language => {
  const main = /^[A-Za-z]{2,3}/.exec(language ?? '')?.[0].toLowerCase() ?? 'en';
  return { model: 'gpt-transcribe', languages: [...new Set([main, 'en'])], prompt: transcriptionPrompt };
};
const transcriptionPrompt = 'Someone talking to Poki, a voice assistant, to use their iPhone: opening apps, scrolling, tapping, reading the screen.';

function sessionConfig({ effort = 'low', vad = 'server_vad', voice = 'marin', language } = {}) {
  const turn = vad === 'semantic_vad'
    ? { type: 'semantic_vad', eagerness: 'high', create_response: true, interrupt_response: true }
    : { type: 'server_vad', silence_duration_ms: 450, prefix_padding_ms: 300, threshold: 0.5, create_response: true, interrupt_response: true };
  return {
    type: 'realtime',
    model,
    instructions: instructions(language),
    output_modalities: ['audio'],
    audio: {
      input: { turn_detection: turn, noise_reduction: { type: 'near_field' }, transcription: transcription(language) },
      output: { voice },
    },
    tools: voiceTools.map(({ name, description, parameters }) => ({ type: 'function', name, description, parameters })),
    tool_choice: 'auto',
    parallel_tool_calls: false,
    reasoning: { effort },
  };
}

const text = result => result.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
const clip = (s, n = 1800) => s.length > n ? `${s.slice(0, n)}…` : s;

// Voice tool → Poki MCP call. Each returns the string the model reads.
const runners = {
  async get_ios_version(mcp) {
    const info = JSON.parse(text(await mcp.call('get_device_info', {})));
    return JSON.stringify({ model: info.model, ios_version: info.osVersion });
  },
  open_settings: async (mcp, a) => clip(text(await mcp.call('open_settings', a.page ? { page: a.page } : {}))),
  read_screen: async mcp => clip(text(await mcp.call('list_elements', { max_elements: 60 }))),
  open_app: async (mcp, a) => clip(text(await mcp.call('launch_app', { name: a.name }))),
  // Only with `checked`, the app and element text the phone cleared (see runTool).
  async tap_text(mcp, a, checked) {
    if (isPoki(checked.app)) throw new Error(ownAppRefusal);
    // Unknown when the screen names no app; then the checked app is opened again.
    const front = await mcp.call('get_foreground_app', {}).then(result => JSON.parse(text(result)), () => null);
    // The owner may have opened Poki to allow it; the tap belongs to the app that was checked.
    if (checked.app && front?.bundle_id !== checked.app) await mcp.call('launch_app', { bundle_id: checked.app });
    else if (!checked.app && isPoki(front?.bundle_id)) throw new Error(ownAppRefusal);
    return clip(text(await mcp.call('tap_text', { text: checked.text, exact: true })));
  },
  go_home: async mcp => clip(text(await mcp.call('press_button', { button: 'home' }))),
};

class Mcp {
  async connect() {
    this.client = new Client({ name: 'poki-voice-bridge', version: '0.1.0' });
    await this.client.connect(new StdioClientTransport({ command: process.execPath, args: [join(root, 'src/stdio.mjs')], env: { ...process.env, POKI_MCP_SESSION: 'voice-bridge' } }));
  }
  async call(name, args) {
    const result = await this.client.callTool({ name, arguments: device ? { device, ...args } : args }, { timeout: 60000 });
    if (result.isError) throw new Error(clip(text(result), 600));
    return result;
  }
}

// The approval card is in Poki: a voice tap never lands there (the phone refuses it too).
const isPoki = id => typeof id === 'string' && (id === 'nz.zheha.poki' || id.startsWith('nz.zheha.poki.'));
const ownAppRefusal = "only the phone's owner can approve, by tapping it on the phone themselves; Poki takes no taps inside the Poki app. Nothing was tapped.";

// Every name tap_text matches on (src/interaction.mjs), so the phone checks what the tap would match.
const names = e => [e.label, e.text, e.value, e.identifier, e.placeholder].filter(s => typeof s === 'string' && s.trim());

// What tap_text would tap, read without touching the phone: Poki MCP's own matching on the screen.
async function tapTarget(mcp, wanted) {
  if (typeof wanted !== 'string' || !wanted.trim()) throw new Error('tap_text needs text');
  let screen = JSON.parse(text(await mcp.call('list_elements', { max_elements: 400 })));
  if (isPoki(screen.foreground?.bundle_id)) throw new Error(ownAppRefusal);
  let found = matching(screen.elements, wanted);
  if (!found.length && screen.source !== 'ocr') {
    screen = JSON.parse(text(await mcp.call('list_elements', { source: 'ocr', max_elements: 400 })));
    found = matching(screen.elements, wanted);
  }
  if (!found.length) throw new Error(`nothing on screen reads ${JSON.stringify(wanted)}; nothing was tapped. Read the screen first.`);
  if (found.length > 1) throw new Error(`${found.length} elements match ${JSON.stringify(wanted)}: ${found.map(e => JSON.stringify(names(e)[0] ?? '')).join(', ')}; nothing was tapped. Name one exactly.`);
  const [first, ...rest] = names(found[0]);
  return { app: { bundle_id: screen.foreground?.bundle_id ?? null, name: screen.foreground?.name ?? null }, target: { text: first ?? wanted, says: [first, ...rest].filter(Boolean).join(' = ') } };
}

async function bridgeSecret() {
  const file = join(stateDir, 'voice-bridge.json');
  const saved = await readFile(file, 'utf8').then(JSON.parse).catch(() => null);
  if (saved?.secret) return { secret: saved.secret, file };
  const secret = randomBytes(24).toString('base64url');
  await mkdir(stateDir, { recursive: true, mode: 0o700 });
  await writeFile(file, JSON.stringify({ secret }) + '\n', { mode: 0o600 });
  return { secret, file };
}

// voice-ledger.jsonl: what ran, for the person reading it later. The phone keeps its own record of calls.
const ledgerFile = join(stateDir, 'voice-ledger.jsonl');
const ledger = new Map();   // call_id → { entry, done: Promise }

async function runTool(mcp, { call_id, name, arguments: args = {}, checked }) {
  const seen = ledger.get(call_id);
  if (seen) { await seen.done; return { ...seen.entry, replayed: true }; }
  // A tap the phone has not checked yet: say what it would tap. Nothing runs, so it is not in the ledger.
  if (name === 'tap_text' && !(typeof checked?.text === 'string' && checked.text)) {
    const started = Date.now();
    try { return { state: 'check', ...await tapTarget(mcp, args.text), started, finished: Date.now() }; }
    catch (error) { return { state: 'failed', output: `error: ${error.message}`, started, finished: Date.now() }; }
  }
  const entry = { call_id, name, args, ...(checked ? { checked } : {}), state: 'running', started: Date.now() };
  const done = (async () => {
    const runner = runners[name];
    try {
      if (!runner) throw new Error(`unknown voice tool ${name}`);
      entry.output = await runner(mcp, args, checked);
      entry.state = 'done';
    } catch (error) {
      entry.output = `error: ${error.message}`;
      entry.state = 'failed';
    }
    entry.finished = Date.now();
    await appendFile(ledgerFile, JSON.stringify({ call_id, name, args, state: entry.state, started: entry.started, finished: entry.finished, output: clip(entry.output, 300) }) + '\n', { mode: 0o600 });
  })();
  ledger.set(call_id, { entry, done });
  await done;
  return entry;
}

async function mintToken(options) {
  const session = sessionConfig(options);
  const response = await fetch('https://api.openai.com/v1/realtime/client_secrets', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ expires_after: { anchor: 'created_at', seconds: 60 }, session }),
  });
  const body = await response.json();
  // OpenAI echoes a masked key in some errors; keep even that out of logs and replies.
  const reason = (body.error?.message ?? `client_secrets ${response.status}`).replace(/sk-[\w*-]+/g, 'the API key');
  if (!response.ok) throw Object.assign(new Error(reason), { status: response.status });
  return { value: body.value, expires_at: body.expires_at, model, local_tools: voiceTools.filter(t => t.local).map(t => t.name) };
}

// A body that is not JSON is the caller's mistake: 400, not 500.
const readJSON = async req => {
  const body = await readBody(req);
  try { return JSON.parse(body); } catch { throw Object.assign(new Error('the body is not JSON'), { status: 400 }); }
};

const readBody = req => new Promise((resolve, reject) => {
  let data = '';
  req.setEncoding('utf8');
  req.on('data', chunk => { data += chunk; if (data.length > 65536) reject(new Error('body too large')); });
  req.on('end', () => resolve(data));
  req.on('error', reject);
});

const { secret, file } = await bridgeSecret();
const mcp = new Mcp();
if (macTools) await mcp.connect();

const server = http.createServer(async (req, res) => {
  const reply = (status, body) => { res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(JSON.stringify(body)); };
  const url = new URL(req.url, 'http://bridge');
  const [, scope, given, action] = url.pathname.split('/');
  const ok = scope === 'voice' && given && given.length === secret.length && timingSafeEqual(Buffer.from(given), Buffer.from(secret));
  if (!ok) return reply(404, { error: 'not found' });
  try {
    if (req.method === 'GET' && action === 'token') {
      const options = Object.fromEntries(['effort', 'vad', 'voice', 'language'].map(k => [k, url.searchParams.get(k) ?? undefined]).filter(([, v]) => v));
      const started = Date.now();
      const token = await mintToken(options);
      console.log(JSON.stringify({ event: 'token', ms: Date.now() - started, options }));
      return reply(200, token);
    }
    if (req.method === 'POST' && action === 'tool') {
      const call = await readJSON(req);
      if (typeof call.call_id !== 'string' || typeof call.name !== 'string') return reply(400, { error: 'call_id and name are required' });
      const entry = await runTool(mcp, call);
      console.log(JSON.stringify({ event: 'tool', call_id: call.call_id, name: call.name, state: entry.state, ms: entry.finished - entry.started, replayed: !!entry.replayed }));
      return reply(200, { call_id: call.call_id, state: entry.state, output: entry.output, ...(entry.state === 'check' ? { app: entry.app, target: entry.target } : {}), ms: entry.finished - entry.started, replayed: !!entry.replayed });
    }
    if (testDir && req.method === 'GET' && action === 'utterance') {
      const n = url.searchParams.get('n') ?? '';
      if (!/^\d{2}$/.test(n)) return reply(400, { error: 'n is two digits' });
      const audio = await readFile(join(testDir, `u${n}.24k.pcm`));
      res.writeHead(200, { 'content-type': 'application/octet-stream', 'cache-control': 'no-store' });
      return res.end(audio);
    }
    if (testDir && req.method === 'POST' && action === 'report') {
      const turn = await readJSON(req);
      await appendFile(join(stateDir, 'voice-test-report.jsonl'), JSON.stringify({ at: new Date().toISOString(), ...turn }) + '\n', { mode: 0o600 });
      console.log(JSON.stringify({ event: 'test-turn', n: turn.n, ok: turn.ok, calls: turn.calls, ms: turn.ms }));
      return reply(200, {});
    }
    return reply(404, { error: 'not found' });
  } catch (error) {
    console.log(JSON.stringify({ event: 'error', action, message: error.message }));
    return reply(error.status ?? 500, { error: error.message });
  }
});
server.listen(port, host, () => {
  const addresses = Object.values(networkInterfaces()).flat().filter(a => a.family === 'IPv4' && !a.internal).map(a => a.address);
  console.log(JSON.stringify({ event: 'ready', port: server.address().port, addresses, model, secretFile: file, device: device ?? null }));
});
