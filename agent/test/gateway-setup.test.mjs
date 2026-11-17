import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm, chmod, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { makeMessages } from './fixtures/messages.mjs';
import { makePhoton } from './fixtures/photon.mjs';

const run = promisify(execFile);
const root = resolve(import.meta.dirname, '../..');

async function cli(command, args, options = {}) {
  try { return { code: 0, ...await run(command, args, { cwd: root, ...options }) }; }
  catch (error) { return { code: error.code, stdout: error.stdout, stderr: error.stderr }; }
}

async function evidence(name, value) {
  if (!process.env.POKI_GATEWAY_EVIDENCE) return;
  await mkdir(process.env.POKI_GATEWAY_EVIDENCE, { recursive: true });
  await writeFile(join(process.env.POKI_GATEWAY_EVIDENCE, name), JSON.stringify(value, null, 2));
}

test('Optional gateway CLI skips downloads, cleans failures and preserves existing destinations', { skip: process.platform !== 'darwin' }, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-gateway-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const commands = join(directory, 'commands');
  const temporary = join(directory, 'temporary');
  await mkdir(commands); await mkdir(temporary);
  const marker = join(directory, 'download-attempted');
  await writeFile(join(commands, 'curl'), '#!/bin/sh\ntouch "$POKI_DOWNLOAD_MARKER"\nexit 22\n', { mode: 0o755 });
  const env = { ...process.env, PATH: `${commands}:${process.env.PATH}`, TMPDIR: temporary, POKI_DOWNLOAD_MARKER: marker };
  const appDir = join(directory, 'Applications'), configDir = join(directory, 'config');
  const destinations = ['--app-dir', appDir, '--config-dir', configDir];
  const results = {};
  results.skip = await cli('./bin/setup-channels', ['--channel', 'none', ...destinations], { env });
  assert.equal(results.skip.code, 0);
  assert.match(results.skip.stdout, /Skipped iMessage/);
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  await assert.rejects(readdir(appDir), { code: 'ENOENT' });
  await assert.rejects(readdir(configDir), { code: 'ENOENT' });
  const secret = 'fixture-password-not-for-logs';
  const answers = join(directory, 'answers.json');
  await writeFile(answers, JSON.stringify({ url: 'http://127.0.0.1:1234', password: secret,
    sender: 'allowed@example.test', device: 'synthetic-device' }), { mode: 0o600 });
  const args = ['--channel', 'imessage', ...destinations, '--answers', answers];
  results.downloadFailure = await cli('./bin/setup-channels', args, { env });
  assert.equal(results.downloadFailure.code, 1);
  assert.match(results.downloadFailure.stderr, /Download failed/);
  await readFile(marker);
  const archive = join(directory, 'invalid.zip');
  await writeFile(archive, 'not the official release');
  results.checksumFailure = await cli('./bin/setup-channels', [...args, '--archive', archive], { env });
  assert.equal(results.checksumFailure.code, 1);
  assert.match(results.checksumFailure.stderr, /Checksum verification failed/);
  assert.deepEqual(await readdir(temporary), [], 'Failed downloads and checks leave no staging files');
  await assert.rejects(readdir(appDir), { code: 'ENOENT' });
  await assert.rejects(readdir(configDir), { code: 'ENOENT' });
  for (const [name, path] of [['existingApp', join(appDir, 'BlueBubbles.app')], ['existingConfig', configDir]]) {
    await mkdir(path, { recursive: true });
    await writeFile(join(path, 'keep'), 'existing user data');
    results[name] = await cli('./bin/setup-channels', args, { env });
    assert.equal(results[name].code, 1);
    assert.match(results[name].stderr, /already exists/);
    assert.equal(await readFile(join(path, 'keep'), 'utf8'), 'existing user data');
    await rm(path, { recursive: true });
  }
  assert.ok(!JSON.stringify(results).includes(secret));
  await evidence('installer-failure-and-skip.json', results);
});

test('Private-config launcher checks only the configured chat and does not disclose credentials', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-gateway-launch-'));
  const api = await makeMessages();
  t.after(async () => { await api.close(); await rm(directory, { recursive: true, force: true }); });
  await writeFile(join(directory, 'imessage.json'), JSON.stringify({ sender: 'allowed@example.test',
    chatGuid: 'iMessage;-;allowed@example.test', device: 'synthetic-device', auth: 'chatgpt' }), { mode: 0o600 });
  const connection = join(directory, 'connection.json');
  await writeFile(connection, JSON.stringify({ url: api.url, password: api.password }), { mode: 0o600 });
  const args = ['bin/poki-imessage.mjs', '--config-dir', directory, '--check'];
  const result = await cli(process.execPath, args);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /authentication and read check succeeded/);
  assert.deepEqual(api.requests.map(request => request.path), ['/api/v1/ping', '/api/v1/message/query']);
  const filters = api.requests[1].body.where;
  assert.ok(filters.some(filter => filter.args?.chatGuid === 'iMessage;-;allowed@example.test'));
  assert.equal(api.sent.length, 0);
  await assert.rejects(readFile(join(directory, 'state/messages.lock')), { code: 'ENOENT' });
  await chmod(connection, 0o644);
  const permissions = await cli(process.execPath, args);
  assert.equal(permissions.code, 1);
  await chmod(connection, 0o600);
  await writeFile(connection, '{invalid:' + api.password);
  const malformed = await cli(process.execPath, args);
  assert.equal(malformed.code, 1);
  assert.equal(api.requests.length, 2, 'Invalid credentials must not reach the gateway');
  assert.ok(!JSON.stringify([result, permissions, malformed]).includes(api.password));
  await evidence('private-launcher.json', { result, permissions, malformed, requests: api.requests, messagesSent: api.sent.length });
});

test('Photon setup writes private configuration, and its launcher checks and assigns without disclosing the key', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-photon-setup-'));
  const api = await makePhoton();
  t.after(async () => { await api.close(); await rm(directory, { recursive: true, force: true }); });
  const configDir = join(directory, 'photon');
  const answers = join(directory, 'answers.json');
  await writeFile(answers, JSON.stringify({ sender: ' allowed@example.test ', device: 'synthetic-device\n',
    projectId: ` ${api.project}`, apiKey: `${api.key}\n` }), { mode: 0o600 });
  const setupArgs = ['--channel', 'photon', '--config-dir', configDir, '--answers', answers];
  const mistyped = join(directory, 'mistyped.json');
  await writeFile(mistyped, JSON.stringify({ sender: 'allowed@example.test', device: 'synthetic-device', projectId: 'pho_prj_abc', apiKey: api.key }), { mode: 0o600 });
  const rejected = await cli('./bin/setup-channels', ['--channel', 'photon', '--config-dir', configDir, '--answers', mistyped]);
  assert.equal(rejected.code, 1);
  assert.match(rejected.stderr, /26 lowercase letters or digits/);
  await assert.rejects(stat(configDir), { code: 'ENOENT' }, 'A mistyped project ID writes nothing');
  const setup = await cli('./bin/setup-channels', setupArgs);
  assert.equal(setup.code, 0, setup.stderr);
  assert.equal((await stat(configDir)).mode & 0o777, 0o700);
  for (const name of ['photon.json', 'connection.json']) assert.equal((await stat(join(configDir, name))).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(await readFile(join(configDir, 'photon.json'), 'utf8')),
    { sender: 'allowed@example.test', device: 'synthetic-device', auth: 'chatgpt' });
  assert.deepEqual(JSON.parse(await readFile(join(configDir, 'connection.json'), 'utf8')), { projectId: api.project, apiKey: api.key });
  assert.equal(api.requests.length, 0, 'Setup contacts no service');
  const existing = await cli('./bin/setup-channels', setupArgs);
  assert.equal(existing.code, 1);
  assert.match(existing.stderr, /already exists/);
  const env = { ...process.env, PHOTON_API_URL: api.url };
  const args = ['bin/poki-photon.mjs', '--config-dir', configDir];
  const check = await cli(process.execPath, [...args, '--check'], { env });
  assert.equal(check.code, 0, check.stderr);
  assert.match(check.stdout, /authentication and read check succeeded/);
  assert.deepEqual(api.subscriptions, [0]);
  assert.equal(api.requests.length, 0, 'A check sends no request beyond the event subscription');
  await assert.rejects(readFile(join(configDir, 'state/messages.lock')), { code: 'ENOENT' });
  const assign = await cli(process.execPath, [...args, '--assign'], { env });
  assert.equal(assign.code, 0, assign.stderr);
  assert.ok(assign.stdout.includes(`From allowed@example.test, send an iMessage to ${api.agent.handle}`));
  assert.deepEqual(api.assignments.map(assignment => assignment.handle), ['allowed@example.test']);
  api.assignError = { status: 403, code: 'INSUFFICIENT_SCOPE' };
  const forbidden = await cli(process.execPath, [...args, '--assign'], { env });
  assert.equal(forbidden.code, 1);
  assert.match(forbidden.stderr, /platforms:write/);
  const connection = join(configDir, 'connection.json');
  await chmod(connection, 0o644);
  const permissions = await cli(process.execPath, [...args, '--check'], { env });
  assert.equal(permissions.code, 1);
  assert.deepEqual(api.subscriptions, [0], 'A readable key file must not reach Photon');
  assert.equal(api.sent.length, 0);
  assert.ok(!JSON.stringify([rejected, setup, existing, check, assign, forbidden, permissions]).includes(api.key));
  await evidence('photon-setup-and-launcher.json', { setup, existing, check, assign, forbidden, permissions, requests: api.requests });
});
