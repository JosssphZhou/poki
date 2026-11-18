import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { makeMessages } from './fixtures/messages.mjs';
import { makeTelegram } from './fixtures/telegram.mjs';
import { makePhoton } from './fixtures/photon.mjs';
import { taskServices } from './fixtures/task-services.mjs';

const root = resolve(import.meta.dirname, '../..');
function run(args, env = {}, entry = 'bin/poki') {
  return new Promise((resolveRun, reject) => {
    const child = spawn(entry === 'bin/poki' ? join(root, entry) : process.execPath,
      entry === 'bin/poki' ? args : [entry, ...args], { cwd: root, env: { ...process.env, ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    child.stdout.on('data', data => { output += data; });
    child.stderr.on('data', data => { output += data; });
    child.on('error', reject);
    child.on('close', code => resolveRun({ code, output }));
  });
}

test('public commands report help and reject API secrets without echoing them', async () => {
  for (const args of [['--help'], ['login', '--help'], ['status', '--help'], ['imessage', '--help'], ['telegram', '--help']]) {
    const result = await run(args);
    assert.equal(result.code, 0, result.output);
    assert.match(result.output, /poki/);
  }
  const result = await run(['login', '--api-key', 'synthetic-private-key']);
  assert.notEqual(result.code, 0);
  assert.doesNotMatch(result.output, /synthetic-private-key/);
});

test('login reuses SDK credentials and API key stays in the environment', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-login-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const auth = join(dir, 'auth.json');
  const content = JSON.stringify({ 'openai-codex': { type: 'oauth', access: 'synthetic-access', refresh: 'synthetic-refresh', expires: Date.now() + 3600000 } });
  await writeFile(auth, content, { mode: 0o600 });
  const env = { POKI_AGENT_AUTH_FILE: auth, OPENAI_API_KEY: '', OPENAI_BASE_URL: '' };
  const reused = await run(['login', '--auth', 'chatgpt'], env);
  assert.equal(reused.code, 0, reused.output);
  assert.match(reused.output, /existing/i);
  t.diagnostic(`$ poki login --auth chatgpt (synthetic credentials)\n${reused.output.trim()}`);
  assert.doesNotMatch(reused.output, /synthetic-access|synthetic-refresh/);
  const api = await run(['login', '--auth', 'api-key'], { ...env, OPENAI_API_KEY: 'synthetic-api-secret' });
  assert.equal(api.code, 0, api.output);
  assert.doesNotMatch(api.output, /synthetic-api-secret/);
  assert.equal(await readFile(auth, 'utf8'), content);
  const absent = await run(['login', '--auth', 'api-key'], env);
  assert.notEqual(absent.code, 0);
  assert.match(absent.output, /OPENAI_API_KEY/);
});

test('task forwarding preserves the real CLI result and model request count', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-entry-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const counts = [];
  for (const entry of ['agent/cli.mjs', 'bin/poki', 'auto']) {
    const state = join(dir, entry.replaceAll('/', '-'));
    const services = await taskServices(join(state, 'mcp'), { devices: [{ id: 'synthetic-device', name: 'Fixture phone', kind: 'physical' }, { id: 'sim', name: 'Fixture simulator', kind: 'simulator' }] });
    try {
      const result = await run([...(entry === 'auto' ? [] : ['--device', 'synthetic-device']), '--state', state, '--model', 'gpt-5.4', '--auth', 'api-key', 'Fixture ready.'], {
        IDEVICE_TOOLS: process.execPath, POKI_MCP_STATE_DIR: join(state, 'mcp'), OPENAI_API_KEY: 'sk-local-channel-fixture', OPENAI_BASE_URL: services.modelURL,
      }, entry === 'auto' ? 'bin/poki' : entry);
      assert.equal(result.code, 0, result.output);
      const final = result.output.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line)).find(value => value.type === 'result');
      assert.equal(final.phase, 'completed');
      assert.equal(final.result, 'Fixture ready.');
      t.diagnostic(`$ ${entry} Fixture ready. (synthetic model and device)\nphase=${final.phase}; result=${final.result}`);
      counts.push(services.modelRequests.length);
    } finally { await services.close(); }
  }
  assert.equal(counts[1], counts[0]);
  assert.equal(counts[2], counts[0]);
  t.diagnostic(`Model requests: old=${counts[0]}, explicit=${counts[1]}, automatic=${counts[2]}`);
});


test('device discovery lists ambiguous phones and status reports service failure', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-devices-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  for (const devices of [[], [{ id: 'one', name: 'One', kind: 'physical' }, { id: 'two', name: 'Two', kind: 'physical' }]]) {
    const mcp = join(dir, String(devices.length));
    const services = await taskServices(mcp, { devices });
    try {
      const env = { POKI_MCP_STATE_DIR: mcp, OPENAI_API_KEY: 'synthetic-api-secret', POKI_AGENT_AUTH: 'api-key', OPENAI_BASE_URL: '' };
      const result = await run(['Open Settings'], env);
      assert.equal(result.code, 2, result.output);
      assert.match(result.output, devices.length ? /one.*One[\s\S]*two.*Two/ : /No physical phone/);
      assert.equal(services.modelRequests.length, 0);
      assert.deepEqual(services.deviceCalls.map(call => call.name), ['list_devices']);
      const status = await run(['status'], env);
      assert.equal(status.code, 0, status.output);
      assert.match(status.output, /Poki MCP: connected/);
      t.diagnostic(`$ poki status (synthetic MCP)\n${status.output.trim()}`);
      assert.match(status.output, new RegExp(`Devices: ${devices.length}`));
      assert.doesNotMatch(status.output, /synthetic-api-secret/);
    } finally { await services.close(); }
  }
  const unavailable = await run(['status'], { POKI_MCP_STATE_DIR: join(dir, 'missing'), OPENAI_API_KEY: 'synthetic-api-secret', POKI_AGENT_AUTH: 'api-key', OPENAI_BASE_URL: '' });
  assert.equal(unavailable.code, 1);
  assert.match(unavailable.output, /Poki MCP: unavailable/);
});

test('fresh OAuth login persists through the SDK and hides provider failures', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-oauth-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const preload = join(root, 'agent/test/fixtures/poki-oauth.mjs');
  const auth = join(dir, 'auth.json');
  const env = { NODE_OPTIONS: `--import=${preload}`, POKI_AGENT_AUTH_FILE: auth, OPENAI_API_KEY: '', OPENAI_BASE_URL: '' };
  const result = await run(['login', '--auth', 'chatgpt'], env);
  assert.equal(result.code, 0, result.output);
  assert.match(result.output, /ChatGPT sign-in saved/);
  assert.doesNotMatch(result.output, /synthetic-oauth-secret/);
  const saved = JSON.parse(await readFile(auth, 'utf8'));
  assert.equal(saved.openai.type, 'oauth');
  assert.equal(saved.openai.access, 'synthetic-oauth-secret');
  const failure = await run(['login', '--auth', 'chatgpt'], { ...env, POKI_AGENT_AUTH_FILE: join(dir, 'failed.json'), POKI_TEST_AUTH_FAIL: '1' });
  assert.equal(failure.code, 1);
  assert.match(failure.output, /Poki login did not complete/);
  assert.doesNotMatch(failure.output, /synthetic-oauth-secret/);
});


test('channel commands reach existing read checks without sending messages', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-channels-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  for (const [channel, command] of [['imessage', ['imessage']], ['telegram', ['telegram']], ['photon', ['imessage']], ['photon', ['imessage', '--provider=photon']]]) {
    const api = await (channel === 'imessage' ? makeMessages() : channel === 'photon' ? makePhoton() : makeTelegram());
    try {
      const config = join(dir, `${channel}.json`);
      await writeFile(config, JSON.stringify({ device: 'synthetic-device', ...(channel === 'telegram' ? { allowedUsers: [101] } : { sender: 'allowed@example.test' }) }));
      const result = await run([...command, '--config', config, '--state', join(dir, channel), '--check'], {
        BLUEBUBBLES_URL: api.url, BLUEBUBBLES_PASSWORD: api.password ?? '', TELEGRAM_API_URL: api.url, TELEGRAM_BOT_TOKEN: api.token ?? '',
        PHOTON_API_URL: api.url, PHOTON_PROJECT_ID: api.project ?? '', PHOTON_API_KEY: api.key ?? '',
      });
      assert.equal(result.code, 0, result.output);
      assert.match(result.output, /authentication and read check succeeded/);
      assert.ok(result.output.startsWith(`${channel === 'imessage' ? 'bluebubbles' : channel}:`), result.output);
      assert.equal((api.sent ?? api.messages).length, 0);
      t.diagnostic(`$ poki ${command.join(' ')} --config <synthetic config> --check\n${result.output.trim()}`);
    } finally { await api.close(); }
  }
});

test('poki imessage starts the chosen provider and asks only in a terminal with both configured', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-provider-'));
  const messages = await makeMessages();
  const photon = await makePhoton();
  t.after(async () => { await messages.close(); await photon.close(); await rm(dir, { recursive: true, force: true }); });
  const config = join(dir, 'imessage.json');
  await writeFile(config, JSON.stringify({ device: 'synthetic-device', sender: 'allowed@example.test' }));
  const env = { BLUEBUBBLES_URL: messages.url, BLUEBUBBLES_PASSWORD: messages.password,
    PHOTON_API_URL: photon.url, PHOTON_PROJECT_ID: photon.project, PHOTON_API_KEY: photon.key };
  const check = (args, state) => [...args, '--config', config, '--state', join(dir, state), '--check'];
  const reached = () => ({ bluebubbles: messages.requests.length, photon: photon.subscriptions.length });

  const unattended = await run(check(['imessage'], 'unattended'), env);
  assert.equal(unattended.code, 0, unattended.output);
  assert.equal(unattended.output, 'BlueBubbles and Photon are both configured for iMessage. Starting BlueBubbles; pass --provider photon to start Photon.\n'
    + 'bluebubbles: authentication and read check succeeded. No tasks or replies sent.\n');
  assert.deepEqual(reached(), { bluebubbles: 2, photon: 0 }, 'Without a terminal, existing BlueBubbles starts stay BlueBubbles');

  const named = await run(check(['imessage', '--provider', 'photon'], 'named'), env);
  assert.equal(named.output, 'photon: authentication and read check succeeded. No tasks or replies sent.\n');
  const kept = await run(check(['imessage', '--provider', 'bluebubbles'], 'kept'), env);
  assert.equal(kept.output, 'bluebubbles: authentication and read check succeeded. No tasks or replies sent.\n');
  assert.deepEqual(reached(), { bluebubbles: 4, photon: 1 });

  for (const [args, message] of [
    [check(['imessage', '--provider', 'signal'], 'refused'), /^Choose --provider bluebubbles or --provider photon\.\n$/],
    [[...check(['imessage'], 'refused'), '--provider'], /^Choose --provider bluebubbles or --provider photon\.\n$/],
    [check(['telegram', '--provider', 'photon'], 'refused'), /^Unknown option '--provider'/],
    [check(['photon'], 'refused'), /^Invalid arguments\. Use poki --help\./],
  ]) {
    const refused = await run(args, env);
    assert.equal(refused.code, 1, refused.output);
    assert.match(refused.output, message);
  }
  assert.deepEqual(reached(), { bluebubbles: 4, photon: 1 }, 'A refused provider reaches neither service');

  const terminal = async input => {
    const before = reached();
    const result = await new Promise((resolveRun, reject) => {
      const child = spawn('python3', ['-c', 'import os, pty, sys; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))',
        join(root, 'bin/poki'), ...check(['imessage'], 'terminal')], { cwd: root, env: { ...process.env, ...env }, stdio: ['pipe', 'pipe', 'pipe'] });
      let output = '';
      child.stdout.on('data', data => { output += data; });
      child.stderr.on('data', data => { output += data; });
      child.on('error', reject);
      child.on('close', code => resolveRun({ code, output }));
      child.stdin.end(input);
    });
    const after = reached();
    return { ...result, bluebubbles: after.bluebubbles - before.bluebubbles, photon: after.photon - before.photon };
  };
  const second = await terminal('2\n');
  assert.equal(second.code, 0, second.output);
  assert.match(second.output, /BlueBubbles and Photon are both configured for iMessage\.\r?\n  1\. BlueBubbles\r?\n  2\. Photon\r?\nChoose 1 or 2 \[1\]: [^]*photon: authentication and read check succeeded/);
  assert.deepEqual([second.bluebubbles, second.photon], [0, 1]);
  const entered = await terminal('\n');
  assert.match(entered.output, /Choose 1 or 2 \[1\]: [^]*bluebubbles: authentication and read check succeeded/);
  assert.deepEqual([entered.bluebubbles, entered.photon], [2, 0]);
  const other = await terminal('3\n');
  assert.equal(other.code, 1, other.output);
  assert.match(other.output, /Choose 1 for BlueBubbles or 2 for Photon\./);
  assert.deepEqual([other.bluebubbles, other.photon], [0, 0], 'An answer that names no provider starts nothing');
  t.diagnostic(`$ poki imessage --config <synthetic config> --check (terminal, answer 2)\n${second.output.trim()}`);
});
