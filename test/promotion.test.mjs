// .github/scripts/promotion.py picks the build a Beta is made from. It runs here against a stand-in
// for gh that answers from a fixed copy of the repository's tags, Pre-alpha runs and artifacts, so
// no request leaves this machine.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const script = join(root, '.github/scripts/promotion.py');
const BUILT = '69585293051fee03c7ad110f037d8f4dd2a4e96f';
const FAILED = '55b04d6b3c9190f223271ffc748538291c396e6a';
const UNTESTED = 'c3f1e2a0b9d84c7e6f5a4b3c2d1e0f9a8b7c6d5e';
const TESTS = ['prealpha', 'app-tests / inprocess', 'app-tests / agent-chat', 'app-tests / app', 'setup-tests'];
const RUN = id => `https://github.com/example/poki/actions/runs/${id}`;

const repo = {
  tags: { 'app-0.4.5-prealpha.1724': BUILT, 'app-0.4.5-prealpha.1700': UNTESTED, 'app-0.4.4-beta.1': 'b5d72f3dd156b5f7f9cbe4d6605ef10a41d5b6d3' },
  commits: { [FAILED]: FAILED, [BUILT]: BUILT },
  runs: {
    [BUILT]: [{ databaseId: 44047275802, status: 'completed', conclusion: 'success', url: RUN(44047275802) }],
    [FAILED]: [{ databaseId: 43694260348, status: 'completed', conclusion: 'failure', url: RUN(43694260348) }],
    [UNTESTED]: [{ databaseId: 43000000001, status: 'completed', conclusion: 'success', url: RUN(43000000001) }],
  },
  // A run from before the tests joined prealpha.yml has the build job alone.
  jobs: {
    44047275802: TESTS.map(name => ({ name, conclusion: 'success' })),
    43000000001: [{ name: 'prealpha', conclusion: 'success' }],
  },
  artifacts: { 44047275802: [{ name: 'Poki-unsigned', expired: false }], 43000000001: [{ name: 'Poki-unsigned', expired: false }] },
  rolling: { 'app-prealpha-latest': ['Poki-external-0.4.5-1724.ipa', 'Poki-signing.zip', 'SHA256SUMS'] },
};

const GH = `#!/usr/bin/env node
const repo = JSON.parse(require('node:fs').readFileSync(process.env.GH_STUB, 'utf8'));
const args = process.argv.slice(2), path = args.find(a => a.startsWith('repos/')) ?? '';
const out = value => process.stdout.write((typeof value === 'string' ? value : JSON.stringify(value)) + '\\n');
const last = path.split('/').pop();
if (args[0] === 'release' && args[1] === 'view') {
  if (!repo.rolling[args[2]]) process.exit(1);
  out(repo.rolling[args[2]].join('\\n'));
} else if (args[0] === 'run' && args[1] === 'list') out(repo.runs[args[args.indexOf('--commit') + 1]] ?? []);
else if (path.includes('/git/ref/tags/')) process.exit(repo.tags[last] ? 0 : 1);
else if (path.includes('/commits/')) {
  const sha = repo.tags[last] ?? repo.commits[last];
  if (!sha) process.exit(1);
  out(sha);
} else if (path.includes('/jobs?')) out(repo.jobs[path.split('/').at(-2)] ?? []);
else if (path.includes('/artifacts')) out(repo.artifacts[path.split('/').at(-2)] ?? []);
else if (path.includes('/tags?')) out(Object.keys(repo.tags).join('\\n'));
else process.exit(2);
`;

function propose(t, from) {
  const dir = mkdtempSync(join(tmpdir(), 'promotion-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  mkdirSync(join(dir, '.github'));
  mkdirSync(join(dir, 'native/ios-app'), { recursive: true });
  writeFileSync(join(dir, 'bin/gh'), GH);
  chmodSync(join(dir, 'bin/gh'), 0o755);
  writeFileSync(join(dir, 'repo.json'), JSON.stringify(repo));
  const channels = JSON.stringify({ soak_days: 3, promotions: [] }, null, 2) + '\n';
  writeFileSync(join(dir, '.github/channels.json'), channels);
  writeFileSync(join(dir, 'native/ios-app/VERSION'), '0.4.5\n');
  const done = spawnSync('python3', [script, 'propose', 'beta', from, ''], {
    cwd: dir, encoding: 'utf8',
    env: { ...process.env, GH_STUB: join(dir, 'repo.json'), GH_REPO: 'example/poki', PATH: `${join(dir, 'bin')}:${process.env.PATH}` },
  });
  const after = readFileSync(join(dir, '.github/channels.json'), 'utf8');
  return {
    status: done.status, output: done.stdout + done.stderr, channelsChanged: after !== channels,
    promotions: JSON.parse(after).promotions, version: readFileSync(join(dir, 'native/ios-app/VERSION'), 'utf8').trim(),
  };
}

test('a beta is proposed from the build on app-prealpha-latest, with no alpha', t => {
  const r = propose(t, '');
  assert.equal(r.status, 0, r.output);
  assert.equal(r.promotions.length, 1);
  assert.deepEqual(
    { ...r.promotions[0], proposed: undefined },
    { channel: 'beta', proposed: undefined, version: '0.4.5-beta.1', tag: 'app-0.4.5-beta.1', base_version: '0.4.5', build: '1724',
      source: 'app-0.4.5-prealpha.1724', sha: BUILT, built_by: RUN(44047275802), version_bump: '0.4.5 -> 0.4.6' },
  );
  assert.equal(r.version, '0.4.6');
});

test('a build whose Pre-alpha run failed, in its build or its tests, is refused, naming the run, and nothing is proposed', t => {
  const r = propose(t, FAILED);
  assert.notEqual(r.status, 0);
  assert.match(r.output, /did not succeed \(failure\)/);
  assert.ok(r.output.includes(RUN(43694260348)), r.output);
  assert.equal(r.channelsChanged, false);
  assert.equal(r.version, '0.4.5');
});

test('a build whose run never ran the app tests is refused, naming the missing tests', t => {
  const r = propose(t, 'app-0.4.5-prealpha.1700');
  assert.notEqual(r.status, 0);
  assert.ok(r.output.includes(RUN(43000000001)), r.output);
  assert.match(r.output, /did not pass app-tests \/ inprocess, app-tests \/ agent-chat, app-tests \/ app, setup-tests/);
  assert.equal(r.channelsChanged, false);
  assert.equal(r.version, '0.4.5');
});

// Older Poki and Poki Setup install whatever the Alpha releases carry, on every channel, so the
// merged promotion may only write them from a job that waits for the beta approval.
test('publish-promotion.yml writes the Alpha records only from a job behind the beta approval', () => {
  const workflow = readFileSync(join(root, '.github/workflows/publish-promotion.yml'), 'utf8');
  const jobs = workflow.slice(workflow.indexOf('\njobs:\n')).split(/\n(?=  [a-z0-9-]+:\n)/).slice(1);
  const writers = jobs.filter(job => /publish-rolling\.sh alpha/.test(job));
  assert.ok(writers.length > 0, 'no job publishes the Alpha records');
  for (const job of writers) {
    assert.match(job, /\n    environment: .*'beta'/, `${job.split('\n')[0].trim()} writes the Alpha records without waiting for the beta approval`);
  }
});
