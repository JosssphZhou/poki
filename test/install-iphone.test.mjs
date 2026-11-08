import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createInterface } from 'node:readline';
import { mkdtemp, mkdir, readFile, rm, writeFile, chmod } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { root } from '../src/config.mjs';

const exec = promisify(execFile);
const cli = join(root, 'bin/install-iphone.mjs');
const fakeBridge = join(root, 'src/install/fake-bridge.mjs');
const fastEnv = { POKI_INSTALL_POLL_MS: '20', POKI_INSTALL_RETRY_MS: '20', POKI_FAKE_DELAY_MS: '30' };

async function stateDir(t) {
  const dir = await mkdtemp(join(tmpdir(), 'poki-install-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return dir;
}

// Runs the installer the way an agent does: reads its JSON lines and answers each person stop
// with the same subcommands the guide tells the agent to use.
function runInstaller(state, { scenario = 'happy', env = {}, answer = {} } = {}) {
  const child = spawn(process.execPath, [cli, 'run', '--json', '--bridge', fakeBridge, '--state', state], {
    env: { ...process.env, ...fastEnv, POKI_FAKE_SCENARIO: scenario, POKI_APPLE_ID: 'tester@example.com', POKI_SETUP_PASSWORD: 'correct horse', ...env },
  });
  const events = [];
  let stderr = '';
  child.stderr.on('data', chunk => { stderr += chunk; });
  createInterface({ input: child.stdout }).on('line', async line => {
    const event = JSON.parse(line);
    events.push(event);
    if (event.event === 'wait' && answer[event.wait]) await answer[event.wait]();
  });
  return new Promise(resolve => child.on('close', code => resolve({ code, events, stderr })));
}

const sub = (state, ...args) => exec(process.execPath, [cli, ...args, '--state', state]);
const personAnswers = state => ({
  apple_code: () => sub(state, 'code', '123456'),
  open_poki: () => sub(state, 'done', 'open_poki'),
});

test('runs every step in order, stops at each person step with one sentence, and continues once it is done', async t => {
  const state = await stateDir(t);
  const { code, events, stderr } = await runInstaller(state, { answer: personAnswers(state) });
  assert.equal(code, 0, stderr);
  const stepOrder = events.filter(e => e.event === 'step').map(e => e.step);
  assert.deepEqual(stepOrder, ['setup_app', 'bridge', 'channel', 'apple_account', 'phone', 'install', 'open_poki', 'relay', 'check']);
  const waits = events.filter(e => e.event === 'wait').map(e => [e.wait, e.who]);
  assert.deepEqual(waits, [['apple_code', 'input'], ['phone_plug', 'phone'], ['pair', 'phone'], ['devmode', 'phone'], ['open_poki', 'phone']]);
  for (const wait of events.filter(e => e.event === 'wait')) assert.match(wait.say, /^[A-Z].{10,}[.:]$/s, `wait ${wait.wait} has a sentence for the person`);
  assert.ok(events.findIndex(e => e.event === 'wait' && e.wait === 'pair') < events.findIndex(e => e.event === 'done' && e.step === 'install'), 'install finishes after the Trust tap');
  const result = events.at(-1);
  assert.equal(result.event, 'result');
  assert.equal(result.ok, true);
  assert.deepEqual(result.check, { poki: '0.2.8 (501)', developer_mode: true, paired: true, ddi_mounted: true, days_left: 7, relay: 'skipped' });
  const saved = JSON.parse(await readFile(join(state, 'run.json'), 'utf8'));
  assert.equal(saved.steps.check.status, 'ok');
  assert.doesNotMatch(JSON.stringify(events) + stderr + JSON.stringify(saved), /correct horse/, 'the Apple Account password never reaches output or state');
});

test('a step that fails gives a machine-readable code, its reason and what to do, and retries only what can heal', async t => {
  for (const [scenario, expectCode, expectExit] of [
    ['trust-timeout', null, 0],
    ['sign-fails', 'sign_failed', 2],
    ['usbmuxd', 'usbmuxd_unreachable', 2],
  ]) await t.test(scenario, async t => {
    const state = await stateDir(t);
    const { code, events, stderr } = await runInstaller(state, { scenario, answer: personAnswers(state) });
    assert.equal(code, expectExit, stderr);
    const errors = events.filter(e => e.event === 'error');
    if (expectCode === null) {
      assert.equal(errors.length, 1, 'the missed Trust tap is reported once');
      assert.equal(errors[0].code, 'trust_not_answered');
      assert.equal(errors[0].retrying, true);
      assert.equal(events.at(-1).ok, true);
      return;
    }
    const last = errors.at(-1);
    assert.equal(last.code, expectCode);
    assert.equal(last.retrying, false);
    assert.ok(last.reason.length > 10 && last.agent_fix.length > 10, 'reason and fix are filled in');
    assert.equal(events.at(-1).event, 'result');
    assert.equal(events.at(-1).ok, false);
    assert.equal(events.at(-1).code, expectCode);
    const saved = JSON.parse(await readFile(join(state, 'run.json'), 'utf8'));
    assert.equal(Object.values(saved.steps).find(s => s.status === 'failed').code, expectCode);
  });
});

test('a person stop that nobody answers ends with exit 3 and a rerun resumes from that step', async t => {
  const state = await stateDir(t);
  const first = await runInstaller(state, { env: { POKI_INSTALL_WAIT_MS: '150' } });
  assert.equal(first.code, 3, first.stderr);
  assert.deepEqual(first.events.at(-1), { event: 'result', ok: false, waiting: 'apple_code', step: 'apple_account', rerun: 'node bin/install-iphone.mjs run' });
  const saved = JSON.parse(await readFile(join(state, 'run.json'), 'utf8'));
  assert.deepEqual(saved.steps.apple_account, { ...saved.steps.apple_account, status: 'waiting', wait: 'apple_code' });
  const second = await runInstaller(state, { answer: personAnswers(state) });
  assert.equal(second.code, 0, second.stderr);
  assert.equal(second.events.find(e => e.event === 'wait').wait, 'apple_code', 'the rerun picks up at the open sign-in');
});

const secrets = {
  udid: '00008999-000A11B22C33D44E',
  oldUdid: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
  serial: '000081500002349C2188401C',
  name: "Jamie's iPhone",
  anthropic: ['sk', 'ant', 'api03', 'FAKEFAKEFAKEFAKEFAKEFAKEFAKE0123456789'].join('-'),
  cloudflare: 'Zx9fakeCloudflareToken0123456789abcdefGHIJ',
  relay: 'https://poki-relay.jamie-fake.workers.dev',
  relayLink: 'poki://setup?relay=https%3A%2F%2Fpoki-relay.jamie-fake.workers.dev&secret=s3cr3tvalue',
  email: 'jamie.fake@example.com',
  wifi: '192.168.1.44',
  pairing: '<key>HostPrivateKey</key>\n<data>\nLS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFb3dJQkFBS0NBUUVB\n</data>',
};

async function seedFailedRun(state) {
  await mkdir(join(state, 'setup-home/logs'), { recursive: true });
  await writeFile(join(state, 'run.json'), JSON.stringify({
    started_at: '2026-11-08T22:00:00Z', channel: 'alpha', poki_setup: '0.2.1-319',
    steps: {
      setup_app: { status: 'ok', detail: 'Poki Setup 0.2.1-319' },
      phone: { status: 'ok', detail: `${secrets.udid} ${secrets.name}` },
      install: { status: 'failed', code: 'trust_not_answered', reason: `Pairing ${secrets.udid} (${secrets.name}) timed out`, agent_fix: 'Ask the person to tap Trust and run again.' },
    },
    phones: [{ udid: secrets.udid, name: secrets.name, ios: '27.1', link: 'usb', wifi_address: secrets.wifi }],
    relay: { address: secrets.relay },
  }));
  await writeFile(join(state, 'setup-home/logs/poki-setup.log'), [
    `INFO pairing ${secrets.udid} name="${secrets.name}" serial ${secrets.serial}`,
    `INFO old style udid ${secrets.oldUdid}`,
    `DEBUG anthropic key ${secrets.anthropic}`,
    `DEBUG Authorization: Bearer ${secrets.cloudflare}`,
    `INFO cloudflare token=${secrets.cloudflare}`,
    `INFO relay ${secrets.relay}/v1/frames link ${secrets.relayLink}`,
    `INFO signed in as ${secrets.email} from ${secrets.wifi}`,
    secrets.pairing,
    // Built from parts so secret scanners do not take the fixture for a real key.
    [`-----BEGIN ${'PRIVATE'} KEY-----`, 'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7', `-----END ${'PRIVATE'} KEY-----`].join('\n'),
    'INFO install step failed: The iPhone did not answer the Trust dialog in time.',
  ].join('\n'));
}

test('the diagnostics bundle and the issue draft keep the failure but drop identifiers, tokens, keys, pairing records and relay addresses', async t => {
  const state = await stateDir(t);
  await seedFailedRun(state);
  const { stdout: bundle } = await sub(state, 'diagnose', '--no-device');
  const { stdout: issue } = await sub(state, 'issue');
  for (const [label, output] of [['diagnose', bundle], ['issue', issue]]) {
    for (const [kind, value] of Object.entries(secrets)) {
      for (const piece of value.split('\n').filter(p => p.length > 12 && !p.startsWith('<'))) assert.ok(!output.includes(piece), `${label} leaks the ${kind}`);
    }
    assert.doesNotMatch(output, /s3cr3tvalue|jamie/i, `${label} leaks a relay secret or the owner's name`);
    assert.match(output, /trust_not_answered/, `${label} keeps the failing code`);
    assert.match(output, /did not answer the Trust dialog in time/, `${label} keeps the last log lines`);
  }
  const parsed = JSON.parse(bundle);
  assert.equal(parsed.steps.install.code, 'trust_not_answered');
  assert.equal(parsed.phones[0].ios, '27.1');
  assert.ok(parsed.system.macos, 'the bundle names the macOS version');
});

test('the issue draft is only printed: it never runs gh, and it says the person must approve it first', async t => {
  const state = await stateDir(t);
  await seedFailedRun(state);
  const bin = join(state, 'fake-bin');
  await mkdir(bin);
  await writeFile(join(bin, 'gh'), `#!/bin/sh\necho "$@" >> ${JSON.stringify(join(state, 'gh-called'))}\n`);
  await chmod(join(bin, 'gh'), 0o755);
  const { stdout } = await exec(process.execPath, [cli, 'issue', '--state', state], { env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
  await assert.rejects(readFile(join(state, 'gh-called')), { code: 'ENOENT' }, 'gh was not run');
  assert.match(stdout, /Show this draft to the person and submit it only after they say yes/);
  assert.match(stdout, /gh issue create --repo JosssphZhou\/poki --template install-failure.yml|gh issue create --repo JosssphZhou\/poki --title/);
  const draft = await readFile(join(state, 'issue-draft.md'), 'utf8');
  const template = await readFile(join(root, '.github/ISSUE_TEMPLATE/install-failure.yml'), 'utf8');
  const labels = [...template.matchAll(/^\s+label: (.+)$/gm)].map(m => m[1]);
  assert.deepEqual([...draft.matchAll(/^### (.+)$/gm)].map(m => m[1]), labels, 'the draft follows the install-failure template field by field');
  assert.match(draft, /### Step it stopped at\n\nPair \(Trust This Computer\)\n/, 'the step is one of the template options');
});

test('the agent guide documents every error code the installer can print', async () => {
  const { errors } = JSON.parse(await readFile(join(root, 'src/install/steps.json'), 'utf8'));
  const guide = await readFile(join(root, 'INSTALL-IPHONE.md'), 'utf8');
  for (const code of Object.keys(errors)) assert.ok(guide.includes(`\`${code}\``), `INSTALL-IPHONE.md explains ${code}`);
});
