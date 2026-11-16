import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../.github/scripts/promotion.py', import.meta.url));

async function makeDir(t, scorecards) {
  const dir = await mkdtemp(join(tmpdir(), 'poki-gym-gate-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  await mkdir(dir, { recursive: true });
  for (const [name, content] of Object.entries(scorecards)) {
    await writeFile(join(dir, name), content);
  }
  return dir;
}

function runGym(...args) {
  return spawnSync('python3', [script, 'gym', ...args], { encoding: 'utf8' });
}

test('promotion.py gym passes only when both scorecards report zero failures', async t => {
  const clean = await makeDir(t, {
    'gym-scorecard.txt': 'path: runner; calls: 149, slowest: Safari / launch 21000 ms, failures: 0\n',
    'gym-scorecard-inprocess.txt': 'path: in-process; calls: 133, slowest: Safari / launch 8801 ms, failures: 0\n',
  });
  const ok = runGym(clean);
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout, /gym-scorecard\.txt: 0 failures/);
  assert.match(ok.stdout, /gym-scorecard-inprocess\.txt: 0 failures/);
});

test('promotion.py gym blocks nonzero in-process failures even when lower than prior beta', async t => {
  const withInProcessFailures = await makeDir(t, {
    'gym-scorecard.txt': 'path: runner; calls: 149, slowest: Safari / launch 21000 ms, failures: 0\n',
    'gym-scorecard-inprocess.txt': 'path: in-process; calls: 133, slowest: Safari / launch 8801 ms, failures: 6\n  - setup / look (cold): no picture\n',
  });
  const failed = runGym(withInProcessFailures);
  assert.notEqual(failed.status, 0);
  assert.match(failed.stderr, /gym-scorecard-inprocess\.txt: 6 failures/);
});

test('promotion.py gym blocks missing scorecards', async t => {
  const missingInProcess = await makeDir(t, {
    'gym-scorecard.txt': 'path: runner; calls: 149, slowest: Safari / launch 21000 ms, failures: 0\n',
  });
  const failed = runGym(missingInProcess);
  assert.notEqual(failed.status, 0);
  assert.match(failed.stderr, /gym-scorecard-inprocess\.txt has no scorecard/);
});
