import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { copyFile, mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fixture } from './fixture.mjs';
import { root } from '../src/config.mjs';

async function sessionBridge(t, { screenError, screenThrows, extraArgs = [] } = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'poki-voice-token-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
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
      if (url === 'https://api.openai.com/v1/realtime/client_secrets') return Response.json({ value: 'ek_test' });
      if (url === 'https://api.openai.com/v1/live/sessions') return Response.json({ transport: { sdp: 'sdp-answer' } }, { status: 201 });
      if (url === 'https://api.openai.com/v1/responses') return ${screenAction};
      throw new Error('Unexpected upstream URL');
    };
  `;
  const child = spawn(process.execPath, ['--import', `data:text/javascript,${encodeURIComponent(preload)}`, join(root, 'bin/voice-bridge.mjs'), '--port', '0', '--host', '127.0.0.1', ...extraArgs], {
    env: { ...process.env, POKI_MCP_STATE_DIR: dir, POKI_VOICE_MODEL: '', OPENAI_API_KEY: 'unused' }, stdio: ['ignore', 'pipe', 'inherit'],
  });
  const exited = once(child, 'exit');
  t.after(async () => { child.kill(); await exited; });
  const lines = createInterface({ input: child.stdout });
  const [line] = await Promise.race([once(lines, 'line'), exited.then(() => { throw new Error('Voice bridge exited before it was ready'); })]);
  const { port } = JSON.parse(line);
  const { secret } = JSON.parse(await readFile(join(dir, 'voice-bridge.json'), 'utf8'));
  return {
    base: `http://127.0.0.1:${port}/voice/${secret}`,
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

async function annotatedMacBridge(t, f) {
  await copyFile(join(root, 'bin/voice-bridge.mjs'), join(f.dir, 'bin/voice-bridge.mjs'));
  const child = spawn(process.execPath, [join(f.dir, 'bin/voice-bridge.mjs'), '--port', '0', '--host', '127.0.0.1', '--mac-tools', '--test-dir', f.dir], {
    env: { ...f.env, OPENAI_API_KEY: 'unused' }, stdio: ['ignore', 'pipe', 'inherit'],
  });
  const exited = once(child, 'exit');
  t.after(async () => { child.kill(); await exited; });
  const events = [];
  const lines = createInterface({ input: child.stdout });
  lines.on('line', line => { try { events.push(JSON.parse(line)); } catch {} });
  const ready = await new Promise((resolve, reject) => {
    const checkReady = line => {
      try {
        const parsed = JSON.parse(line);
        if (parsed.event === 'ready') { lines.off('line', checkReady); resolve(parsed); }
      } catch {}
    };
    lines.on('line', checkReady);
    exited.then(() => reject(new Error('bridge exited before ready')));
  });
  const { secret } = JSON.parse(await readFile(join(f.env.POKI_MCP_STATE_DIR, 'voice-bridge.json'), 'utf8'));
  const base = `http://127.0.0.1:${ready.port}/voice/${secret}`;
  return {
    ready,
    base,
    events,
    callTool: body => fetch(`${base}/tool`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }).then(r => r.json()),
  };
}

test('Mac bridge rejects unconfirmed touches and wrong Calculator readback, and confirms only matching post-action state', async t => {
  const f = await fixture(t);
  const target7 = { kind: 'screen_text', expected: '7', app: 'Calculator' };
  const wrongElements = [
    { role: 'StaticText', label: '9', frame: { x: 10, y: 10, width: 80, height: 30 } },
    { role: 'Button', label: '7', frame: { x: 10, y: 80, width: 40, height: 40 } },
  ];
  await f.set({ bundleId: 'com.apple.calculator', appName: 'Calculator', elements: wrongElements });
  const { ready, callTool } = await annotatedMacBridge(t, f);
  assert.equal(ready.voice_host, 'voice_bridge');
  assert.equal(ready.action_host, 'mac_tools');

  const preRead = await callTool({ call_id: 'r-pre', name: 'read_screen', arguments: {}, target_condition: target7, after_action: false });
  assert.equal(preRead.state, 'done', JSON.stringify(preRead));
  assert.equal(preRead.action_host, 'mac_tools');
  assert.equal(preRead.observation_source, 'mac_mcp_accessibility');
  assert.equal(preRead.effective_action, false);
  assert.equal(preRead.target_confirmed, false, 'pre-action read showing 9 must not confirm target 7');

  const checkUnchanged = await callTool({ call_id: 't-unchanged', name: 'tap_text', arguments: { text: '7' }, target_condition: target7 });
  assert.equal(checkUnchanged.state, 'check', JSON.stringify(checkUnchanged));
  assert.equal(checkUnchanged.effective_action, false);
  assert.equal(checkUnchanged.target_confirmed, false);

  const unchangedTap = await callTool({
    call_id: 't-unchanged', name: 'tap_text', arguments: { text: '7' },
    checked: { app: checkUnchanged.app.bundle_id, text: checkUnchanged.target.text },
    target_condition: target7,
  });
  assert.equal(unchangedTap.state, 'done', JSON.stringify(unchangedTap));
  assert.equal(unchangedTap.action_host, 'mac_tools');
  assert.equal(unchangedTap.effective_action, false, 'unchanged tap must not count as an effective action');
  assert.equal(unchangedTap.target_confirmed, false, 'unchanged tap must not confirm the target');

  const afterFailedRead = await callTool({ call_id: 'r-after-fail', name: 'read_screen', arguments: {}, target_condition: target7, after_action: false });
  assert.equal(afterFailedRead.target_confirmed, false, 'read showing 9 after an ineffective tap must not confirm target 7');

  await f.set({
    bundleId: 'com.apple.calculator',
    appName: 'Calculator',
    elements: wrongElements,
    afterInput: {
      elements: [
        { role: 'StaticText', label: '9', frame: { x: 10, y: 10, width: 80, height: 30 } },
        { role: 'StaticText', label: 'Error', frame: { x: 10, y: 45, width: 80, height: 20 } },
        { role: 'Button', label: '7', frame: { x: 10, y: 80, width: 40, height: 40 } },
      ],
    },
  });
  const checkWrongChange = await callTool({ call_id: 't-wrong', name: 'tap_text', arguments: { text: '7' }, target_condition: target7 });
  assert.equal(checkWrongChange.state, 'check');
  const wrongChangeTap = await callTool({
    call_id: 't-wrong', name: 'tap_text', arguments: { text: '7' },
    checked: { app: checkWrongChange.app.bundle_id, text: checkWrongChange.target.text },
    target_condition: target7,
  });
  assert.equal(wrongChangeTap.state, 'done', JSON.stringify(wrongChangeTap));
  assert.equal(wrongChangeTap.effective_action, true, 'verified screen change counts as an effective action');
  assert.equal(wrongChangeTap.target_confirmed, false, 'screen showing 9 alongside keypad button 7 must not confirm target 7');

  const postActionWrongRead = await callTool({ call_id: 'r-wrong-post', name: 'read_screen', arguments: {}, target_condition: target7, after_action: true });
  assert.equal(postActionWrongRead.target_confirmed, false, 'post-action read showing 9 must not confirm target 7');

  await f.set({
    bundleId: 'com.apple.calculator',
    appName: 'Calculator',
    elements: wrongElements,
    afterInput: {
      elements: [
        { role: 'StaticText', label: '7', frame: { x: 10, y: 10, width: 80, height: 30 } },
        { role: 'Button', label: '7', frame: { x: 10, y: 80, width: 40, height: 40 } },
      ],
    },
  });
  const checkRightChange = await callTool({ call_id: 't-right', name: 'tap_text', arguments: { text: '7' }, target_condition: target7 });
  assert.equal(checkRightChange.state, 'check');
  const rightTap = await callTool({
    call_id: 't-right', name: 'tap_text', arguments: { text: '7' },
    checked: { app: checkRightChange.app.bundle_id, text: checkRightChange.target.text },
    target_condition: target7,
  });
  assert.equal(rightTap.state, 'done', JSON.stringify(rightTap));
  assert.equal(rightTap.action_host, 'mac_tools');
  assert.equal(rightTap.observation_source, 'mac_mcp_action_readback');
  assert.equal(rightTap.effective_action, true);
  assert.equal(rightTap.target_confirmed, true, 'verified screen showing display 7 confirms target 7');

  const postActionRightRead = await callTool({ call_id: 'r-right-post', name: 'read_screen', arguments: {}, target_condition: target7, after_action: true });
  assert.equal(postActionRightRead.effective_action, false);
  assert.equal(postActionRightRead.observation_source, 'mac_mcp_accessibility');
  assert.equal(postActionRightRead.target_confirmed, true, 'independent post-action read showing display 7 confirms target 7');

  const preActionSkip = await callTool({ call_id: 'r-pre-even-if-7', name: 'read_screen', arguments: {}, target_condition: target7, after_action: false });
  assert.equal(preActionSkip.target_confirmed, false, 'pre-action read must not confirm an action target');
});

test('Mac bridge fails closed without a target condition, preserves ledger privacy, and logs timeline reports', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Send', afterInput: { label: 'Sent' } });
  const { base, events, callTool } = await annotatedMacBridge(t, f);

  const untargetedRead = await callTool({ call_id: 'r-none', name: 'read_screen', arguments: {} });
  assert.equal(untargetedRead.state, 'done');
  assert.equal(untargetedRead.effective_action, false);
  assert.equal(untargetedRead.target_confirmed, false, 'read_screen without a screen_read target fails closed');

  const screenReadTarget = await callTool({ call_id: 'r-screen', name: 'read_screen', arguments: {}, target_condition: { kind: 'screen_read' } });
  assert.equal(screenReadTarget.state, 'done');
  assert.equal(screenReadTarget.effective_action, false);
  assert.equal(screenReadTarget.target_confirmed, true);

  const check = await callTool({ call_id: 't-untargeted', name: 'tap_text', arguments: { text: 'Send' } });
  assert.equal(check.state, 'check');
  const untargetedTap = await callTool({
    call_id: 't-untargeted', name: 'tap_text', arguments: { text: 'Send' },
    checked: { app: check.app.bundle_id, text: check.target.text },
  });
  assert.equal(untargetedTap.state, 'done');
  assert.equal(untargetedTap.effective_action, true);
  assert.equal(untargetedTap.target_confirmed, false, 'tap_text without target_condition fails closed');

  await f.set({ label: 'Send', afterInput: { label: 'Sent' } });
  const checkSent = await callTool({ call_id: 't-sent', name: 'tap_text', arguments: { text: 'Send' } });
  const sentTap = await callTool({
    call_id: 't-sent', name: 'tap_text', arguments: { text: 'Send' },
    checked: { app: checkSent.app.bundle_id, text: checkSent.target.text },
    target_condition: { kind: 'screen_text', expected: 'Sent' },
  });
  assert.equal(sentTap.state, 'done');
  assert.equal(sentTap.effective_action, true);
  assert.equal(sentTap.target_confirmed, true);
  assert.equal(sentTap.observation_source, 'mac_mcp_action_readback');

  await f.set({ bundleId: 'com.apple.Preferences', appName: 'Settings' });
  const opened = await callTool({ call_id: 'o-settings', name: 'open_app', arguments: { name: 'Settings' } });
  assert.equal(opened.state, 'done', JSON.stringify(opened));
  assert.equal(opened.effective_action, true);
  assert.equal(opened.target_confirmed, true);

  const ledgerLines = (await readFile(join(f.env.POKI_MCP_STATE_DIR, 'voice-ledger.jsonl'), 'utf8')).trim().split('\n').map(JSON.parse);
  const tapLedger = ledgerLines.find(entry => entry.call_id === 't-sent');
  assert.equal(tapLedger.voice_host, 'voice_bridge');
  assert.equal(tapLedger.action_host, 'mac_tools');
  assert.equal(tapLedger.effective_action, true);
  assert.equal(tapLedger.target_confirmed, true);
  assert.equal(typeof tapLedger.ms, 'number');
  assert.equal(typeof tapLedger.output_chars, 'number');
  assert.equal(tapLedger.args, undefined, 'ledger must not persist raw tool arguments');
  assert.equal(tapLedger.output, undefined, 'ledger must not persist raw tool outputs');

  const reportPayload = {
    n: 1,
    ok: true,
    entry_route: 'voice_bridge',
    voice_host: 'voice_bridge',
    action_host: 'mac_tools',
    observation_source: 'mac_mcp_action_readback',
    host_ms: { phone_local: 0, mac_tools: sentTap.ms, mac_tools_roundtrip: sentTap.ms + 12 },
    calls: ['tap_text'],
    ms: { said: 0, heard: 20, call: 60, first_effective_action: 80, toolDone: 180, target_confirmed: 180, delivered: 185, spoken: 240 },
  };
  const reportRes = await fetch(`${base}/report`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(reportPayload) });
  assert.equal(reportRes.status, 200);
  const reported = JSON.parse((await readFile(join(f.env.POKI_MCP_STATE_DIR, 'voice-test-report.jsonl'), 'utf8')).trim().split('\n').at(-1));
  assert.equal(reported.entry_route, 'voice_bridge');
  assert.equal(reported.voice_host, 'voice_bridge');
  assert.equal(reported.action_host, 'mac_tools');
  assert.equal(reported.observation_source, 'mac_mcp_action_readback');
  assert.equal(reported.host_ms.phone_local, 0);
  assert.equal(reported.host_ms.mac_tools, sentTap.ms);
  assert.equal(reported.host_ms.mac_tools_roundtrip, sentTap.ms + 12);
  assert.equal(reported.ms.first_effective_action, 80);
  assert.equal(reported.ms.target_confirmed, 180);
  assert.ok(events.some(event => event.event === 'tool' && event.call_id === 't-sent' && event.action_host === 'mac_tools' && event.voice_host === 'voice_bridge'));
  assert.ok(events.some(event => event.event === 'test-turn' && event.action_host === 'mac_tools' && event.ms?.target_confirmed === 180));
});

test('voice bridge timing annotations keep Live and Realtime prompts and tool schemas unchanged in size', async t => {
  const { base, request } = await sessionBridge(t);
  assert.equal((await fetch(`${base}/token?language=en`)).status, 200);
  const rt = (await request()).body.session;
  assert.equal(rt.instructions.length, 2973);
  assert.equal(JSON.stringify(rt.tools).length, 2116);
  assert.ok(!/first_effective_action|target_confirmed|voice_host|action_host|observation_source/i.test(rt.instructions));

  assert.equal((await fetch(`${base}/session?language=en`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  })).status, 200);
  const live = (await request()).body.session;
  assert.equal(live.instructions.length, 1470);
  assert.equal(live.delegation.responses.instructions.length, 3045);
  assert.equal(JSON.stringify(live.delegation.responses.tools).length, 2527);
  assert.ok(!/first_effective_action|target_confirmed|voice_host|action_host|observation_source/i.test(live.instructions + live.delegation.responses.instructions));
});
