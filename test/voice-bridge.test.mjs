import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { copyFile, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fixture } from './fixture.mjs';
import { root } from '../src/config.mjs';
import { VOICE_SPEC_VERSION } from '../src/voice-behavior-spec.mjs';

async function sessionBridge(t, { screenError, screenThrows, extraArgs = [], extraEnv = {}, failUpstream = false, upstreamErrorMessage = 'upstream failed', fixtureEnv = null, bridgeScript = join(root, 'bin/voice-bridge.mjs') } = {}) {
  const dir = fixtureEnv ? fixtureEnv.POKI_MCP_STATE_DIR : await mkdtemp(join(tmpdir(), 'poki-voice-token-'));
  if (!fixtureEnv) t.after(() => rm(dir, { recursive: true, force: true }));
  const screenAction = screenThrows
    ? `(() => { throw new Error(${JSON.stringify(screenThrows)}); })()`
    : screenError
      ? `Response.json(${JSON.stringify(screenError.body ?? { error: { message: screenError.message } })}, { status: ${screenError.status} })`
      : `Response.json({ output: [{ type: 'message', content: [{ type: 'output_text', text: 'Screen description' }] }] })`;
  const preload = `
    import { writeFile } from 'node:fs/promises';
    import { join } from 'node:path';
    globalThis.fetch = async (url, options) => {
      await writeFile(join(process.env.POKI_MCP_STATE_DIR, 'request.json'), JSON.stringify({ url, body: JSON.parse(options.body) }));
      if (${JSON.stringify(failUpstream)}) return Response.json({ error: { message: ${JSON.stringify(upstreamErrorMessage)} } }, { status: 502 });
      if (url === 'https://api.openai.com/v1/realtime/client_secrets') return Response.json({ value: 'ek_test' });
      if (url === 'https://api.openai.com/v1/live/sessions') return Response.json({ transport: { sdp: 'sdp-answer' } }, { status: 201 });
      if (url === 'https://api.openai.com/v1/responses') return ${screenAction};
      throw new Error('Unexpected upstream URL');
    };
  `;
  const child = spawn(process.execPath, ['--import', `data:text/javascript,${encodeURIComponent(preload)}`, bridgeScript, '--port', '0', '--host', '127.0.0.1', ...extraArgs], {
    env: { ...(fixtureEnv ?? process.env), POKI_MCP_STATE_DIR: dir, POKI_VOICE_MODEL: '', OPENAI_API_KEY: 'unused', ...extraEnv }, stdio: ['ignore', 'pipe', 'inherit'],
  });
  const exited = once(child, 'exit');
  t.after(async () => { child.kill(); await exited; });
  const lines = createInterface({ input: child.stdout });
  const events = [];
  const waiters = [];
  const [line] = await Promise.race([once(lines, 'line'), exited.then(() => { throw new Error('Voice bridge exited before it was ready'); })]);
  lines.on('line', entry => {
    try {
      const parsed = JSON.parse(entry);
      events.push(parsed);
      for (let i = waiters.length - 1; i >= 0; i -= 1) {
        if (waiters[i].predicate(parsed)) {
          waiters[i].resolve(parsed);
          waiters.splice(i, 1);
        }
      }
    } catch {}
  });
  const waitForEvent = (predicate, timeoutMs = 2000) => {
    const existing = events.find(predicate);
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const index = waiters.findIndex(w => w.resolve === onMatch);
        if (index >= 0) waiters.splice(index, 1);
        reject(new Error('Timed out waiting for voice bridge event'));
      }, timeoutMs);
      const onMatch = event => { clearTimeout(timer); resolve(event); };
      waiters.push({ predicate, resolve: onMatch });
    });
  };
  const { port } = JSON.parse(line);
  const { secret } = JSON.parse(await readFile(join(dir, 'voice-bridge.json'), 'utf8'));
  return {
    base: `http://127.0.0.1:${port}/voice/${secret}`,
    events,
    waitForEvent,
    request: async () => JSON.parse(await readFile(join(dir, 'request.json'), 'utf8')),
  };
}

test('legacy voice token requests hint Chinese transcription for each interface language', async t => {
  const { base, request } = await sessionBridge(t);
  for (const language of ['', 'zh-Hans', 'en']) {
    const response = await fetch(`${base}/token?language=${language}`);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).value, 'ek_test');
    const { body: { session } } = await request();
    assert.equal(session.audio.input.transcription.language, 'zh');
    assert.ok(!session.tools.some(tool => tool.name === 'cancel_current_task'));
  }
});

test('a Realtime client opts in to requesting its own replies after audio is committed', async t => {
  const { base, request } = await sessionBridge(t);
  for (const [query, autoRespond] of [['', true], ['?turns=committed', false]]) {
    assert.equal((await fetch(`${base}/token${query}`)).status, 200);
    const { body: { session } } = await request();
    assert.equal(session.audio.input.turn_detection.create_response, autoRespond);
    assert.equal(session.audio.input.turn_detection.interrupt_response, true);
  }
});

test('the voice bridge exchanges a Live offer and returns only the SDP answer', async t => {
  const { base, request } = await sessionBridge(t);
  const token = await fetch(`${base}/token?transport=live`);
  assert.deepEqual(await token.json(), {
    model: 'gpt-live-1.1', live: true, local_tools: ['get_ios_version', 'look', 'open_app', 'do'],
  });
  const response = await fetch(`${base}/session?language=zh-Hans`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { sdp: 'sdp-answer' });
  const upstream = await request();
  assert.equal(upstream.url, 'https://api.openai.com/v1/live/sessions');
  assert.deepEqual(upstream.body.transport, { type: 'webrtc', sdp: 'sdp-offer' });
  const { session } = upstream.body;
  assert.equal(session.model, 'gpt-live-1.1');
  assert.equal(session.delegation.type, 'responses');
  assert.ok(session.delegation.responses.tools.some(tool => tool.name === 'do'));
  assert.ok(session.delegation.responses.tools.some(tool => tool.name === 'cancel_current_task'));
  for (const prompt of [session.instructions, session.delegation.responses.instructions]) {
    assert.match(prompt, /cancel_current_task/);
    assert.match(prompt, /把停字发过去/);
  }
  assert.match(session.instructions, /Chinese/i);
  assert.match(session.instructions, /Before delegating a new task, say one short sentence about what you will do\./);
  assert.match(session.instructions, /give one short progress update when a meaningful step is confirmed and more work remains/);
  assert.match(session.instructions, /state the verified result and ask one brief, specific follow-up question/);
  assert.match(session.instructions, /For casual chat, reply in two or three short sentences/);
});

test('each Live screenshot uses its own unsaved vision request', async t => {
  const { base, request } = await sessionBridge(t);
  for (const [screen, previous] of [['first', 'second'], ['second', 'first']]) {
    const url = name => `data:image/jpeg;base64,${Buffer.from(`synthetic ${name} screenshot`).toString('base64')}`;
    const response = await fetch(`${base}/screen`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ image: url(screen) }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { text: 'Screen description' });
    const upstream = await request();
    assert.equal(upstream.url, 'https://api.openai.com/v1/responses');
    assert.equal(upstream.body.store, false);
    assert.equal(upstream.body.previous_response_id, undefined);
    assert.equal(upstream.body.conversation, undefined);
    const images = upstream.body.input.flatMap(item => item.content).filter(part => part.type === 'input_image');
    assert.deepEqual(images.map(image => image.image_url), [url(screen)]);
    assert.ok(!JSON.stringify(upstream.body).includes(url(previous)));
  }
});

test('Live and Realtime voice prompts scope screen delegation, exclude greetings, require look before action, and stay within baseline length', async t => {
  const { base, request } = await sessionBridge(t);
  const liveResponse = await fetch(`${base}/session?language=en`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  });
  assert.equal(liveResponse.status, 200);
  const { body: { session: live } } = await request();
  assert.match(live.instructions, /reads and operates the iPhone via the backend/i);
  assert.match(live.instructions, /Delegate only screen questions and phone actions; answer greetings and casual chat directly without delegating/i);
  assert.match(live.instructions, /Never say you cannot see the screen before delegating/i);
  assert.ok(live.instructions.length <= 1859, `Live foreground prompt exceeded 0.4.7 baseline (1859): ${live.instructions.length}`);

  const backend = live.delegation.responses;
  assert.match(backend.instructions, /Use tools only for screen questions or phone tasks, not greetings or chat/i);
  assert.match(backend.instructions, /Call look first for screen questions or current-screen actions before acting or saying you cannot see/i);
  assert.match(backend.instructions, /state the failure/i);
  assert.ok(backend.instructions.length <= 3407, `Live backend prompt exceeded 0.4.7 baseline (3407): ${backend.instructions.length}`);
  const liveToolsLen = backend.tools.reduce((sum, tool) => sum + tool.description.length, 0);
  assert.ok(backend.instructions.length + liveToolsLen <= 5848, `Live backend prompt+tools exceeded 0.4.7 baseline (5848): ${backend.instructions.length + liveToolsLen}`);
  const liveLook = backend.tools.find(tool => tool.name === 'look');
  assert.ok(liveLook);
  assert.match(liveLook.description, /screenshot description/i);
  assert.match(liveLook.description, /Call first for screen questions or current-screen actions/i);
  assert.match(liveLook.description, /report failures/i);

  const realtimeResponse = await fetch(`${base}/token?language=en`);
  assert.equal(realtimeResponse.status, 200);
  const { body: { session: realtime } } = await request();
  assert.match(realtime.instructions, /Use tools only for screen questions or phone tasks, not greetings or chat/i);
  assert.match(realtime.instructions, /Call look first for screen questions or current-screen actions before acting or saying you cannot see/i);
  assert.match(realtime.instructions, /state the failure/i);
  assert.ok(realtime.instructions.length <= 3370, `Realtime prompt exceeded 0.4.7 baseline (3370): ${realtime.instructions.length}`);
  const rtToolsLen = realtime.tools.reduce((sum, tool) => sum + tool.description.length, 0);
  assert.ok(realtime.instructions.length + rtToolsLen <= 5623, `Realtime prompt+tools exceeded 0.4.7 baseline (5623): ${realtime.instructions.length + rtToolsLen}`);
  const realtimeLook = realtime.tools.find(tool => tool.name === 'look');
  assert.ok(realtimeLook);
  assert.match(realtimeLook.description, /screenshot image/i);
  assert.match(realtimeLook.description, /Call first for screen questions or current-screen actions/i);
  assert.match(realtimeLook.description, /report failures/i);
});

test('Live screenshot description failures distinguish upstream 404, non-string errors, malformed output, and secret redaction', async t => {
  const url = `data:image/jpeg;base64,${Buffer.from('synthetic screenshot').toString('base64')}`;

  const notFound = await sessionBridge(t, {
    screenError: { status: 404, message: 'model gpt-6-luna does not exist' },
  });
  const upstream404 = await fetch(`${notFound.base}/screen`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ image: url }),
  });
  assert.equal(upstream404.status, 502);
  const payload404 = await upstream404.json();
  assert.equal(payload404.source, 'upstream');
  assert.equal(payload404.upstream_status, 404);
  assert.match(payload404.error, /model gpt-6-luna does not exist/);

  const wrongRoute = await fetch(`${notFound.base.replace(/\/voice\/[^/]+$/, '/voice/wrongsecret000000')}/screen`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ image: url }),
  });
  assert.equal(wrongRoute.status, 404);
  assert.equal((await wrongRoute.json()).source, undefined);

  const nonString = await sessionBridge(t, {
    screenError: { status: 503, body: { error: { message: { detail: 'overloaded' } } } },
  });
  const nonStringRes = await fetch(`${nonString.base}/screen`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ image: url }),
  });
  assert.equal(nonStringRes.status, 503);
  const nonStringPayload = await nonStringRes.json();
  assert.equal(nonStringPayload.source, 'upstream');
  assert.match(nonStringPayload.error, /Screen description failed \(503\)/);

  const secretLeak = await sessionBridge(t, {
    screenError: { status: 503, message: 'vision down for sk-secret123456 and Bearer tok_abcdef123456' },
  });
  const secretRes = await fetch(`${secretLeak.base}/screen`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ image: url }),
  });
  assert.equal(secretRes.status, 503);
  const secretPayload = await secretRes.json();
  assert.match(secretPayload.error, /vision down/);
  assert.match(secretPayload.error, /the API key/);
  assert.ok(!secretPayload.error.includes('sk-secret123456'));
  assert.ok(!secretPayload.error.includes('tok_abcdef123456'));

  const networkDown = await sessionBridge(t, { screenThrows: 'connect ECONNREFUSED' });
  const networkRes = await fetch(`${networkDown.base}/screen`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ image: url }),
  });
  assert.equal(networkRes.status, 502);
  const networkPayload = await networkRes.json();
  assert.equal(networkPayload.source, 'upstream');
  assert.equal(networkPayload.upstream_status, 502);
  assert.match(networkPayload.error, /Could not reach OpenAI for screen description/);

  const malformedOutput = await sessionBridge(t, {
    screenError: { status: 200, body: { output: { unexpected: true } } },
  });
  const malformedRes = await fetch(`${malformedOutput.base}/screen`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ image: url }),
  });
  assert.equal(malformedRes.status, 502);
  const malformedPayload = await malformedRes.json();
  assert.equal(malformedPayload.source, 'upstream');
  assert.equal(malformedPayload.upstream_status, 502);
  assert.match(malformedPayload.error, /OpenAI returned no screen description/);
});

// The voice bridge in front of a fixture daemon and phone, as the Poki app reaches it.
async function bridge(t, f) {
  await copyFile(join(root, 'bin/voice-bridge.mjs'), join(f.dir, 'bin/voice-bridge.mjs'));
  const child = spawn(process.execPath, [join(f.dir, 'bin/voice-bridge.mjs'), '--port', '0', '--host', '127.0.0.1', '--mac-tools'], { env: { ...f.env, OPENAI_API_KEY: 'unused' }, stdio: ['ignore', 'pipe', 'inherit'] });
  const exited = once(child, 'exit');
  t.after(async () => { child.kill(); await exited; });
  const lines = createInterface({ input: child.stdout });
  const [line] = await once(lines, 'line');
  const { port } = JSON.parse(line);
  const { secret } = JSON.parse(await readFile(join(f.env.POKI_MCP_STATE_DIR, 'voice-bridge.json'), 'utf8'));
  return body => fetch(`http://127.0.0.1:${port}/voice/${secret}/tool`, { method: 'POST', body: JSON.stringify(body) }).then(r => r.json());
}

test('a voice tap_text the phone has not checked taps nothing; once checked it taps once', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Send' });
  const tool = await bridge(t, f);
  const taps = async () => (await f.events()).filter(e => e.op === 'tap').length;

  // "tap Send", as the model asks for it: the bridge says what it would tap and where, and taps nothing.
  const check = await tool({ call_id: 'c1', name: 'tap_text', arguments: { text: 'Send' } });
  assert.equal(await taps(), 0, JSON.stringify(check));
  assert.equal(check.state, 'check', JSON.stringify(check));
  assert.equal(check.target.text, 'Send');

  // The phone cleared it (its rules, or the owner's OK): the same call taps that element once.
  const done = await tool({ call_id: 'c1', name: 'tap_text', arguments: { text: 'Send' }, checked: { app: check.app.bundle_id, text: check.target.text } });
  assert.equal(done.state, 'done', JSON.stringify(done));
  assert.equal(await taps(), 1);
});

test('a voice tap_text with Poki in front taps nothing, checked or not', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Allow', bundleId: 'nz.zheha.poki', appName: 'Poki' });
  const tool = await bridge(t, f);
  const taps = async () => (await f.events()).filter(e => e.op === 'tap').length;

  // The approval card is in Poki: "tap Allow" is refused before the phone is asked.
  const check = await tool({ call_id: 'c1', name: 'tap_text', arguments: { text: 'Allow' } });
  assert.equal(check.state, 'failed', JSON.stringify(check));
  assert.match(check.output, /only the phone's owner/);

  // A call that says Poki was checked is refused too.
  const done = await tool({ call_id: 'c2', name: 'tap_text', arguments: { text: 'Allow' }, checked: { app: 'nz.zheha.poki', text: 'Allow' } });
  assert.equal(done.state, 'failed', JSON.stringify(done));
  assert.equal(await taps(), 0);
});

test('a voice tap_text on an element known only by its identifier shows the phone that name', async t => {
  const f = await fixture(t);
  await f.set({ elements: [{ role: 'Button', identifier: 'Send', frame: { x: 10, y: 10, width: 40, height: 20 } }] });
  const tool = await bridge(t, f);

  // The phone checks what it is told the element says: the identifier the tap matches, not nothing.
  const check = await tool({ call_id: 'c1', name: 'tap_text', arguments: { text: 'Send' } });
  assert.equal(check.state, 'check', JSON.stringify(check));
  assert.match(check.target.says, /\bSend\b/);
  assert.equal((await f.events()).filter(e => e.op === 'tap').length, 0);
});

const extractHeadings = prompt => prompt.split('\n').filter(line => line.startsWith('# ')).map(line => line.slice(2));

test('voice bridge emits all stable sections, reports template header, and stays within main prompt budget', async t => {
  const { base, request } = await sessionBridge(t);
  const expectedAll = ['Executor', 'Language', 'Brevity', 'Capabilities', 'Evidence', 'Interruption', 'Recovery'];
  const expectedLiveVoice = ['Executor', 'Language', 'Brevity', 'Evidence', 'Interruption', 'Recovery'];
  const budgets = {
    'zh-Hans': { languageName: 'Chinese, Simplified', realtime: 2944, liveVoice: 1451, liveExecutor: 2882 },
    en: { languageName: 'English', realtime: 2932, liveVoice: 1439, liveExecutor: 2870 },
    'zh-Hant': { languageName: 'Chinese, Traditional', realtime: 2945, liveVoice: 1452, liveExecutor: 2883 },
  };

  const liveToken = await fetch(`${base}/token?transport=live`);
  assert.equal(liveToken.status, 200);
  assert.equal(liveToken.headers.get('x-poki-voice-template'), VOICE_SPEC_VERSION);

  for (const [language, spec] of Object.entries(budgets)) {
    const rtRes = await fetch(`${base}/token?language=${language}`);
    assert.equal(rtRes.status, 200);
    assert.equal(rtRes.headers.get('x-poki-voice-template'), VOICE_SPEC_VERSION);
    const realtime = (await request()).body.session;
    assert.deepEqual(extractHeadings(realtime.instructions), expectedAll);
    assert.ok(realtime.instructions.includes(`Speak ${spec.languageName}, the language of Poki's interface, from your first sentence on.`));
    assert.ok(realtime.instructions.includes('Before using tools for a new task, say one short sentence about what you will do.'));
    assert.ok(realtime.instructions.includes('Automatic Unlock setting'));
    assert.ok(realtime.instructions.includes('Never repeat an action already finished'));
    assert.ok(realtime.instructions.length <= spec.realtime, `${language} realtime ${realtime.instructions.length} > ${spec.realtime}`);
    assert.equal(realtime.tools.reduce((sum, tool) => sum + tool.description.length, 0), 1133);

    const lvRes = await fetch(`${base}/session?language=${language}`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
    });
    assert.equal(lvRes.status, 200);
    assert.equal(lvRes.headers.get('x-poki-voice-template'), VOICE_SPEC_VERSION);
    const live = (await request()).body.session;
    assert.deepEqual(extractHeadings(live.instructions), expectedLiveVoice);
    assert.deepEqual(extractHeadings(live.delegation.responses.instructions), expectedAll);
    assert.ok(live.instructions.includes(`Speak ${spec.languageName}.`));
    assert.ok(live.delegation.responses.instructions.includes('Start promptly.'));
    assert.ok(live.instructions.length <= spec.liveVoice, `${language} live voice ${live.instructions.length} > ${spec.liveVoice}`);
    assert.ok(live.delegation.responses.instructions.length <= spec.liveExecutor, `${language} live executor ${live.delegation.responses.instructions.length} > ${spec.liveExecutor}`);
    assert.equal(live.delegation.responses.tools.reduce((sum, tool) => sum + tool.description.length, 0), 1327);
  }
});

test('hiding tools removes their promises from voice bridge prompts, including cancel-only and tap-only sets', async t => {
  const withoutOpenApp = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'open_app' } });
  assert.equal((await fetch(`${withoutOpenApp.base}/token?language=zh-Hans`)).status, 200);
  const rtNoOpen = (await withoutOpenApp.request()).body.session;
  assert.ok(!rtNoOpen.tools.some(tool => tool.name === 'open_app'));
  assert.ok(!rtNoOpen.instructions.includes('open_app'));
  assert.ok(!rtNoOpen.instructions.includes('Settings page'));

  const withoutDo = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'do' } });
  assert.equal((await fetch(`${withoutDo.base}/token?language=en`)).status, 200);
  const rtNoDo = (await withoutDo.request()).body.session;
  assert.ok(!rtNoDo.tools.some(tool => tool.name === 'do'));
  assert.ok(!rtNoDo.instructions.includes('one do'));
  assert.ok(!rtNoDo.instructions.includes('button: "home"'));
  assert.ok(!rtNoDo.instructions.includes('Taps that send'));

  const withoutLook = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'look' } });
  assert.equal((await fetch(`${withoutLook.base}/token?language=en`)).status, 200);
  const rtNoLook = (await withoutLook.request()).body.session;
  assert.ok(!rtNoLook.tools.some(tool => tool.name === 'look'));
  assert.ok(!rtNoLook.instructions.includes('Call look first'));
  assert.ok(!rtNoLook.instructions.includes('latest look'));

  const withoutCancel = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'cancel_current_task' } });
  assert.equal((await fetch(`${withoutCancel.base}/session?language=zh-Hans`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  })).status, 200);
  const liveNoCancel = (await withoutCancel.request()).body.session;
  assert.ok(!liveNoCancel.delegation.responses.tools.some(tool => tool.name === 'cancel_current_task'));
  assert.ok(!liveNoCancel.instructions.includes('cancel_current_task'));
  assert.ok(!liveNoCancel.delegation.responses.instructions.includes('cancel_current_task'));

  const cancelOnly = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'get_ios_version,open_app,do,look' } });
  assert.equal((await fetch(`${cancelOnly.base}/session?language=zh-Hans`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  })).status, 200);
  const liveCancelOnly = (await cancelOnly.request()).body.session;
  assert.deepEqual(liveCancelOnly.delegation.responses.tools.map(tool => tool.name), ['cancel_current_task']);
  for (const prompt of [liveCancelOnly.instructions, liveCancelOnly.delegation.responses.instructions]) {
    assert.ok(prompt.includes('cancel_current_task'));
    for (const forbidden of [
      '把停字发过去',
      '在备忘录输入停',
      'normal phone tools',
      'Before delegating a new task',
      'Start promptly.',
      'Use tools only',
      'reads and operates the iPhone',
      "operates the user's iPhone with tools",
    ]) {
      assert.ok(!prompt.includes(forbidden), `unexpected promise ${JSON.stringify(forbidden)} in cancel-only prompt`);
    }
  }

  const f = await fixture(t);
  await copyFile(join(root, 'bin/voice-bridge.mjs'), join(f.dir, 'bin/voice-bridge.mjs'));
  const tapAndCancelMac = await sessionBridge(t, {
    extraArgs: ['--mac-tools'],
    extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'get_ios_version,open_settings,read_screen,open_app,go_home' },
    fixtureEnv: f.env,
    bridgeScript: join(f.dir, 'bin/voice-bridge.mjs'),
  });
  assert.equal((await fetch(`${tapAndCancelMac.base}/session?language=zh-Hans`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  })).status, 200);
  const macTapOnly = (await tapAndCancelMac.request()).body.session;
  assert.deepEqual(macTapOnly.delegation.responses.tools.map(tool => tool.name), ['tap_text', 'cancel_current_task']);
  for (const prompt of [macTapOnly.instructions, macTapOnly.delegation.responses.instructions]) {
    assert.ok(prompt.includes('cancel_current_task'));
    for (const forbidden of [
      '在备忘录输入停',
      '把停字发过去',
      'reads and operates the iPhone',
      'read_screen',
      'open_app',
      'open_settings',
      'go_home',
    ]) {
      assert.ok(!prompt.includes(forbidden), `unexpected promise ${JSON.stringify(forbidden)} when only tap_text and cancel_current_task are exposed`);
    }
  }
});

test('voice bridge startup logs record version, mode, and controlled error codes without upstream text or query params', async t => {
  const okBridge = await sessionBridge(t);
  assert.equal((await fetch(`${okBridge.base}/token?language=zh-Hans&voice=QUERY_SENTINEL_OK`)).status, 200);
  const rtEvent = await okBridge.waitForEvent(e => e.event === 'voice_startup' && e.mode === 'realtime' && e.commit_state === 'confirmed');
  assert.equal(rtEvent.template_version, VOICE_SPEC_VERSION);
  assert.equal(rtEvent.options, undefined);
  assert.ok(!JSON.stringify(okBridge.events).includes('QUERY_SENTINEL_OK'));

  assert.equal((await fetch(`${okBridge.base}/token?transport=live`)).status, 200);
  const queuedEvent = await okBridge.waitForEvent(e => e.event === 'voice_startup' && e.mode === 'live' && e.commit_state === 'queued');
  assert.equal(queuedEvent.template_version, VOICE_SPEC_VERSION);

  assert.equal((await fetch(`${okBridge.base}/session?language=zh-Hans&voice=QUERY_SENTINEL_LIVE`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  })).status, 200);
  const liveEvent = await okBridge.waitForEvent(e => e.event === 'voice_startup' && e.mode === 'live' && e.commit_state === 'confirmed');
  assert.equal(liveEvent.template_version, VOICE_SPEC_VERSION);
  assert.equal(liveEvent.options, undefined);
  assert.ok(!JSON.stringify(okBridge.events).includes('QUERY_SENTINEL_LIVE'));

  const failingBridge = await sessionBridge(t, { failUpstream: true, upstreamErrorMessage: 'UPSTREAM_SENTINEL_SECRET_9911' });
  const rtFailRes = await fetch(`${failingBridge.base}/token?language=en&voice=QUERY_SENTINEL_FAIL`);
  assert.equal(rtFailRes.status, 502);
  const rtFailBody = await rtFailRes.json();
  assert.equal(rtFailBody.error, 'upstream_server_error');
  assert.ok(!JSON.stringify(rtFailBody).includes('UPSTREAM_SENTINEL_SECRET_9911'));
  const rtFailed = await failingBridge.waitForEvent(e => e.event === 'voice_startup' && e.mode === 'realtime' && e.commit_state === 'failed');
  const rtErrorEvent = await failingBridge.waitForEvent(e => e.event === 'error' && e.action === 'token');
  assert.equal(rtFailed.template_version, VOICE_SPEC_VERSION);
  assert.equal(rtFailed.error_code, 'upstream_server_error');
  assert.equal(rtFailed.status, 502);
  assert.equal(rtFailed.message, undefined);
  assert.equal(rtFailed.options, undefined);
  assert.equal(rtErrorEvent.error_code, 'upstream_server_error');
  assert.equal(rtErrorEvent.message, undefined);

  const lvFailRes = await fetch(`${failingBridge.base}/session?language=zh-Hans&voice=QUERY_SENTINEL_LIVE_FAIL`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  });
  assert.equal(lvFailRes.status, 502);
  const lvFailBody = await lvFailRes.json();
  assert.equal(lvFailBody.error, 'upstream_server_error');
  assert.ok(!JSON.stringify(lvFailBody).includes('UPSTREAM_SENTINEL_SECRET_9911'));
  const liveFailed = await failingBridge.waitForEvent(e => e.event === 'voice_startup' && e.mode === 'live' && e.commit_state === 'failed');
  const lvErrorEvent = await failingBridge.waitForEvent(e => e.event === 'error' && e.action === 'session');
  assert.equal(liveFailed.template_version, VOICE_SPEC_VERSION);
  assert.equal(liveFailed.error_code, 'upstream_server_error');
  assert.equal(liveFailed.status, 502);
  assert.equal(liveFailed.message, undefined);
  assert.equal(liveFailed.options, undefined);
  assert.equal(lvErrorEvent.error_code, 'upstream_server_error');
  assert.equal(lvErrorEvent.message, undefined);

  const allFailLogs = JSON.stringify(failingBridge.events);
  assert.ok(!allFailLogs.includes('UPSTREAM_SENTINEL_SECRET_9911'));
  assert.ok(!allFailLogs.includes('QUERY_SENTINEL_FAIL'));
  assert.ok(!allFailLogs.includes('QUERY_SENTINEL_LIVE_FAIL'));

  const validationBridge = await sessionBridge(t);
  assert.equal((await fetch(`${validationBridge.base}/token?transport=live`)).status, 200);
  await validationBridge.waitForEvent(e => e.event === 'voice_startup' && e.mode === 'live' && e.commit_state === 'queued');

  const missingSdpRes = await fetch(`${validationBridge.base}/session?language=zh-Hans&voice=QUERY_SENTINEL_MISSING_SDP`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({}),
  });
  assert.equal(missingSdpRes.status, 400);
  const missingSdpBody = await missingSdpRes.json();
  assert.equal(missingSdpBody.error, 'invalid_sdp');
  const missingSdpEvent = await validationBridge.waitForEvent(
    e => e.event === 'voice_startup' && e.mode === 'live' && e.commit_state === 'failed' && e.error_code === 'invalid_sdp',
  );
  assert.equal(missingSdpEvent.template_version, VOICE_SPEC_VERSION);
  assert.equal(missingSdpEvent.status, 400);
  assert.equal(missingSdpEvent.message, undefined);
  const missingSdpError = await validationBridge.waitForEvent(e => e.event === 'error' && e.action === 'session' && e.error_code === 'invalid_sdp');
  assert.equal(missingSdpError.status, 400);
  assert.equal(missingSdpError.message, undefined);

  const badJsonRes = await fetch(`${validationBridge.base}/session?language=zh-Hans&voice=QUERY_SENTINEL_BAD_JSON`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: '{bad-json-BODY_SENTINEL_8822',
  });
  assert.equal(badJsonRes.status, 400);
  const badJsonBody = await badJsonRes.json();
  assert.equal(badJsonBody.error, 'bad_request');
  const badJsonEvent = await validationBridge.waitForEvent(
    e => e.event === 'voice_startup' && e.mode === 'live' && e.commit_state === 'failed' && e.error_code === 'bad_request',
  );
  assert.equal(badJsonEvent.template_version, VOICE_SPEC_VERSION);
  assert.equal(badJsonEvent.status, 400);
  assert.equal(badJsonEvent.message, undefined);
  const badJsonError = await validationBridge.waitForEvent(e => e.event === 'error' && e.action === 'session' && e.error_code === 'bad_request');
  assert.equal(badJsonError.status, 400);
  assert.equal(badJsonError.message, undefined);

  const allValidationLogs = JSON.stringify(validationBridge.events);
  assert.ok(!allValidationLogs.includes('QUERY_SENTINEL_MISSING_SDP'));
  assert.ok(!allValidationLogs.includes('QUERY_SENTINEL_BAD_JSON'));
  assert.ok(!allValidationLogs.includes('BODY_SENTINEL_8822'));
});

test('phone direct Swift renderer and live Node voice bridge produce identical prompts', async t => {
  if (process.platform !== 'darwin') {
    t.skip('Swift parity check runs on macOS');
    return;
  }
  const execFileAsync = promisify(execFile);
  const dir = await mkdtemp(join(tmpdir(), 'poki-voice-parity-'));
  t.after(() => rm(dir, { recursive: true, force: true }));

  const defaultBridge = await sessionBridge(t);
  const noOpenBridge = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'open_app' } });
  const cancelOnlyBridge = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'get_ios_version,open_app,do,look' } });
  const f = await fixture(t);
  await copyFile(join(root, 'bin/voice-bridge.mjs'), join(f.dir, 'bin/voice-bridge.mjs'));
  const macTapOnlyBridge = await sessionBridge(t, {
    extraArgs: ['--mac-tools'],
    extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'get_ios_version,open_settings,read_screen,open_app,go_home' },
    fixtureEnv: f.env,
    bridgeScript: join(f.dir, 'bin/voice-bridge.mjs'),
  });

  const captureRealtime = async (bridgeServer, language) => {
    assert.equal((await fetch(`${bridgeServer.base}/token?language=${language}`)).status, 200);
    const { session } = (await bridgeServer.request()).body;
    return { tools: session.tools.map(tool => tool.name), text: session.instructions };
  };
  const captureLive = async (bridgeServer, language) => {
    assert.equal((await fetch(`${bridgeServer.base}/session?language=${language}`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
    })).status, 200);
    const { session } = (await bridgeServer.request()).body;
    const tools = session.delegation.responses.tools.map(tool => tool.name);
    return {
      voice: { tools, text: session.instructions },
      executor: { tools, text: session.delegation.responses.instructions },
    };
  };

  const rtZh = await captureRealtime(defaultBridge, 'zh-Hans');
  const rtEn = await captureRealtime(defaultBridge, 'en');
  const rtHant = await captureRealtime(defaultBridge, 'zh-Hant');
  const lvZh = await captureLive(defaultBridge, 'zh-Hans');
  const rtNoOpen = await captureRealtime(noOpenBridge, 'zh-Hans');
  const lvCancelOnly = await captureLive(cancelOnlyBridge, 'zh-Hans');
  const lvMacTapOnly = await captureLive(macTapOnlyBridge, 'zh-Hans');

  const cases = [
    { role: 'realtime', language: 'zh-Hans', tools: rtZh.tools, host: 'phone', bridgeText: rtZh.text },
    { role: 'realtime', language: 'en', tools: rtEn.tools, host: 'phone', bridgeText: rtEn.text },
    { role: 'realtime', language: 'zh-Hant', tools: rtHant.tools, host: 'phone', bridgeText: rtHant.text },
    { role: 'live_voice', language: 'zh-Hans', tools: lvZh.voice.tools, host: 'phone', bridgeText: lvZh.voice.text },
    { role: 'live_executor', language: 'zh-Hans', tools: lvZh.executor.tools, host: 'phone', bridgeText: lvZh.executor.text },
    { role: 'realtime', language: 'zh-Hans', tools: rtNoOpen.tools, host: 'phone', bridgeText: rtNoOpen.text },
    { role: 'live_voice', language: 'zh-Hans', tools: lvCancelOnly.voice.tools, host: 'phone', bridgeText: lvCancelOnly.voice.text },
    { role: 'live_executor', language: 'zh-Hans', tools: lvCancelOnly.executor.tools, host: 'phone', bridgeText: lvCancelOnly.executor.text },
    { role: 'live_voice', language: 'zh-Hans', tools: lvMacTapOnly.voice.tools, host: 'mac', bridgeText: lvMacTapOnly.voice.text },
    { role: 'live_executor', language: 'zh-Hans', tools: lvMacTapOnly.executor.tools, host: 'mac', bridgeText: lvMacTapOnly.executor.text },
  ];

  const inputPath = join(dir, 'cases.json');
  const mainPath = join(dir, 'main.swift');
  const binPath = join(dir, 'parity');
  await writeFile(inputPath, JSON.stringify(cases.map(({ role, language, tools, host }) => ({ role, language, tools, host }))));
  await writeFile(mainPath, `
import Foundation
struct CaseInput: Decodable { let role: String; let language: String; let tools: [String]; let host: String }
struct CaseOutput: Encodable { let templateVersion: String; let sectionIds: [String]; let text: String }
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let inputs = try JSONDecoder().decode([CaseInput].self, from: data)
let outputs = inputs.map { item -> CaseOutput in
    let built = VoiceBehaviorSpec.shared.build(
        role: VoicePromptRole(rawValue: item.role)!,
        language: item.language,
        tools: item.tools,
        host: VoicePromptHost(rawValue: item.host)!
    )
    return CaseOutput(templateVersion: built.templateVersion, sectionIds: built.sectionIds, text: built.text)
}
let encoded = try JSONEncoder().encode(outputs)
FileHandle.standardOutput.write(encoded)
`);
  await execFileAsync('swiftc', ['-DDEBUG', join(root, 'native/ios-app/Poki/Voice/VoiceBehaviorSpec.swift'), mainPath, '-o', binPath]);
  const { stdout } = await execFileAsync(binPath, [inputPath]);
  const swiftResults = JSON.parse(stdout);
  assert.equal(swiftResults.length, cases.length);
  for (let i = 0; i < cases.length; i += 1) {
    assert.equal(swiftResults[i].templateVersion, VOICE_SPEC_VERSION);
    assert.equal(swiftResults[i].text, cases[i].bridgeText, `mismatch for case ${i} (${cases[i].role}/${cases[i].language})`);
  }
});

test('bridge Realtime and Live prompts cover source distinction, quiet/pause/resume, progress and noise rules', async t => {
  const { base, request } = await sessionBridge(t);
  for (const language of ['zh-Hans', 'en']) {
    assert.equal((await fetch(`${base}/token?language=${language}&turns=committed`)).status, 200);
    const realtime = (await request()).body.session.instructions;
    assert.equal((await fetch(`${base}/session?language=${language}`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
    })).status, 200);
    const liveBody = (await request()).body.session;
    for (const prompt of [realtime, liveBody.instructions, liveBody.delegation.responses.instructions]) {
      assert.match(prompt, /Quoted media transcript/);
      assert.match(prompt, /bystander/i);
      assert.match(prompt, /screen reader/i);
      assert.match(prompt, /quoted screen/i);
      assert.match(prompt, /别说话/);
      assert.match(prompt, /pause/i);
      assert.match(prompt, /continue/i);
      assert.match(prompt, /progress/i);
      assert.match(prompt, /stay quiet if asked/i);
      assert.match(prompt, /noise/i);
    }
  }
});
