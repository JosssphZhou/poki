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
  const setupArgs = ['--channel', 'imessage', '--provider', 'photon', '--config-dir', configDir, '--answers', answers];
  const mistyped = join(directory, 'mistyped.json');
  await writeFile(mistyped, JSON.stringify({ sender: 'allowed@example.test', device: 'synthetic-device', projectId: 'pho_prj_abc', apiKey: api.key }), { mode: 0o600 });
  const env = { ...process.env, PHOTON_API_URL: api.url };
  const rejected = await cli('./bin/setup-channels', ['--channel', 'imessage', '--provider', 'photon', '--config-dir', configDir, '--answers', mistyped], { env });
  assert.equal(rejected.code, 1);
  assert.match(rejected.stderr, /26 lowercase letters or digits/);
  await assert.rejects(stat(configDir), { code: 'ENOENT' }, 'A mistyped project ID writes nothing');
  const setup = await cli('./bin/setup-channels', setupArgs, { env });
  assert.equal(setup.code, 0, setup.stderr);
  assert.equal((await stat(configDir)).mode & 0o777, 0o700);
  for (const name of ['photon.json', 'connection.json']) assert.equal((await stat(join(configDir, name))).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(await readFile(join(configDir, 'photon.json'), 'utf8')),
    { sender: 'allowed@example.test', device: 'synthetic-device', auth: 'chatgpt' });
  assert.deepEqual(JSON.parse(await readFile(join(configDir, 'connection.json'), 'utf8')), { projectId: api.project, apiKey: api.key });
  const existing = await cli('./bin/setup-channels', setupArgs, { env });
  assert.equal(existing.code, 1);
  assert.match(existing.stderr, /already exists/);
  const unwritable = await cli('sh', ['-c', 'ulimit -f 0 && exec ./bin/setup-channels "$@"', 'sh', ...setupArgs.slice(0, 5), join(directory, 'unwritable'), ...setupArgs.slice(6)], { env });
  assert.equal(unwritable.stderr, 'Setup failed: Setup could not finish. Check destination permissions and available disk space, then retry.\n',
    'A supplied key that cannot be saved is not reported as a key Photon created');
  await assert.rejects(stat(join(directory, 'unwritable')), { code: 'ENOENT' });
  assert.equal(api.calls, 0, 'Setup with a supplied key contacts no service');
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

test('Photon setup describes both iMessage routes, signs in with a device code, prepares the project and stores the key it creates', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-photon-login-'));
  const browser = await mkdtemp(join(tmpdir(), 'poki-photon-browser-'));
  const api = await makePhoton();
  t.after(async () => { await api.close(); await rm(directory, { recursive: true, force: true }); await rm(browser, { recursive: true, force: true }); });
  await writeFile(join(browser, 'open'), '#!/bin/sh\nprintf "%s\\n" "$1" >> "$POKI_OPENED"\n', { mode: 0o755 });
  const env = { ...process.env, PHOTON_API_URL: api.url, BROWSER: join(browser, 'open'), POKI_OPENED: join(browser, 'opened') };
  delete env.CI;
  const terminal = (args, input, extra = {}) => {
    const child = run('python3', ['-c', 'import os, pty, sys; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))',
      './bin/setup-channels', '--channel', 'imessage', ...args], { cwd: root, env: { ...env, ...extra } });
    child.child.stdin.end(input);
    return child.then(result => ({ code: 0, ...result }), error => ({ code: error.code, stdout: error.stdout, stderr: error.stderr }));
  };
  const answers = join(directory, 'answers.json');
  const placed = join(directory, 'placed.json');
  const other = { organizationId: `pho_org_${'0'.repeat(25)}2`, name: 'Other org' };
  await writeFile(answers, JSON.stringify({ sender: 'allowed@example.test', device: 'synthetic-device' }), { mode: 0o600 });
  const setup = (configDir, fileLimit, args = [], file = answers) => cli('sh', ['-c', `${fileLimit ? 'ulimit -f 0 && ' : ''}exec ./bin/setup-channels "$@"`, 'sh',
    '--channel', 'imessage', '--provider', 'photon', '--config-dir', configDir, '--answers', file, ...args], { env });
  const connection = async configDir => JSON.parse(await readFile(join(configDir, 'connection.json'), 'utf8'));
  const earlier = { projectId: `pho_prj_${'0'.repeat(25)}2`, name: 'Earlier project' };
  api.projects = [earlier];

  api.login.denied = true;
  const denied = await setup(join(directory, 'denied'));
  assert.equal(denied.code, 1);
  assert.match(denied.stderr, /sign-in did not complete \(access_denied\)/);
  for (const [fault, problem] of [['projects', /did not list the projects of Example org \(HTTP 500\)/], ['redirect', /did not list your organizations \(HTTP 307\)/],
    ['create', /did not create the project "Poki Agent" in Example org \(HTTP 409, SLUG_TAKEN\)\. Nothing was changed/]]) {
    api.accountFault = fault;
    api.login = { pending: 0, polls: 0 };
    const result = await setup(join(directory, fault));
    assert.equal(result.code, 1);
    assert.match(result.stderr, problem);
  }
  api.accountFault = null;
  api.organizations.push(other);
  const unplaced = await setup(join(directory, 'unplaced'));
  assert.equal(unplaced.code, 1);
  assert.match(unplaced.stderr, /Add organizationId to the answers file[^\n]*"Poki Agent" project:\n1\. Example org \(pho_org_0{25}1\)\n2\. Other org \(pho_org_0{25}2\)/);
  api.organizations.pop();
  assert.deepEqual(api.redirected, [], 'The sign-in is not sent to a redirect target');
  assert.deepEqual([await readdir(directory), api.keys, api.created], [['answers.json'], [], []], 'A sign-in that cannot finish creates no project or key and writes nothing');

  api.billing = 1;
  const unsaved = {};
  for (const [fault, target, problem, outcome] of [
    ['refused', 'refused', /did not accept the API key it had just created \(HTTP 403\)/, /The new Photon API key "Poki Agent[^"]*" \(pho_sk_0{25}1\) was not saved\. Setup revoked it\./],
    ['moved', 'moved', /did not accept the API key it had just created \(HTTP 307\)/, /The new Photon API key "Poki Agent[^"]*" \(pho_sk_0{25}1\) was not saved\. Setup revoked it\./],
    ['dropped', 'dropped', /Cannot reach Photon/, /The new Photon API key "Poki Agent[^"]*" \(pho_sk_0{25}1\) was not saved\. Setup revoked it\./],
    ['no secret', 'malformed', /unexpected form/, /The new Photon API key "Poki Agent[^"]*" \(pho_sk_0{25}1\) was not saved\. Setup revoked it\./],
    [null, 'answers.json/inside', /Setup could not finish/, /The new Photon API key "Poki Agent[^"]*" \(pho_sk_0{25}1\) was not saved\. Setup revoked it\./],
    [null, 'unwritable', /Setup could not finish/, /The new Photon API key "Poki Agent[^"]*" \(pho_sk_0{25}1\) was not saved\. Setup revoked it\./],
    ['no revoke', 'answers.json/inside', /Setup could not finish/, /\(pho_sk_0{25}1\) was not saved\. It is still active: revoke it/],
  ]) {
    api.keyFault = fault;
    api.login = { pending: 0, polls: 0 };
    const result = unsaved[`${fault} ${target}`] = await setup(join(directory, target), target === 'unwritable');
    assert.equal(result.code, 1);
    assert.match(result.stderr, problem);
    assert.match(result.stderr, outcome);
  }
  api.keyFault = null;
  assert.deepEqual([await readdir(directory), api.keys.length, api.revoked.length], [['answers.json'], 7, 6], 'A key that cannot be saved is revoked and leaves nothing behind');
  assert.deepEqual(api.redirected, [], 'The new key is not sent to a redirect target');
  assert.deepEqual(api.created.map(({ projectId, organizationId, name }) => ({ projectId, organizationId, name })),
    [{ projectId: api.project, organizationId: api.organizations[0].organizationId, name: 'Poki Agent' }], 'Setup creates the project once; later runs find it by name');
  assert.match(api.created[0].slug, /^poki-agent-[0-9a-f]{8}$/);
  assert.equal(api.waited, 1, 'Setup waits until a new project is ready before it creates a key');
  assert.match(unsaved['refused refused'].stdout, /Created the Photon project "Poki Agent" \(Example org, pho_prj_0{25}1\)\./);
  assert.match(unsaved['moved moved'].stdout, /Using your Photon project "Poki Agent" \(Example org, pho_prj_0{25}1\)\./);
  api.keys.length = 0;

  api.login = { pending: 2, polls: 0 };
  const configDir = join(directory, 'photon');
  const signedIn = await setup(configDir);
  assert.equal(signedIn.code, 0, signedIn.stderr);
  assert.ok(signedIn.stdout.includes(`${api.url}/device?user_code=WXYZ-1234`) && signedIn.stdout.includes('confirm the code WXYZ-1234'));
  assert.equal(api.login.polls, 3, 'Setup keeps asking while the sign-in is pending');
  assert.deepEqual(api.keys.map(({ project, permissions }) => ({ project, permissions })),
    [{ project: api.project, permissions: ['project:read', 'project:write', 'platforms:read', 'platforms:write'] }]);
  assert.match(api.keys[0].name, /^Poki Agent/);
  assert.equal((await stat(configDir)).mode & 0o777, 0o700);
  for (const name of ['photon.json', 'connection.json']) assert.equal((await stat(join(configDir, name))).mode & 0o777, 0o600);
  assert.deepEqual(await connection(configDir), { projectId: api.project, apiKey: api.key });
  assert.match(signedIn.stdout, /Shared line assigned\. From allowed@example\.test, send an iMessage to \+14155550188 to start\.\nNext \(no message was sent and no worker was started\):\n1\. Send that iMessage/);
  assert.ok(!signedIn.stdout.includes('--assign'), 'Setup that assigned the line does not ask for the assignment again');
  assert.deepEqual(api.assignments.map(({ projectId, handle }) => ({ projectId, handle })), [{ projectId: api.project, handle: 'allowed@example.test' }]);
  const check = await cli(process.execPath, ['bin/poki-photon.mjs', '--config-dir', configDir, '--check'], { env });
  assert.equal(check.code, 0, check.stderr);
  assert.match(check.stdout, /authentication and read check succeeded/);

  api.assignError = { status: 403, code: 'INSUFFICIENT_SCOPE' };
  const named = join(directory, 'named');
  const unassigned = await setup(named, false, ['--project-name', ' earlier PROJECT ']);
  assert.equal(unassigned.code, 0, unassigned.stderr);
  assert.match(unassigned.stdout, /Using your Photon project "Earlier project" \(Example org, pho_prj_0{25}2\)\./);
  assert.match(unassigned.stdout, /Setup could not assign a shared iMessage line: This API key cannot assign shared lines[^\n]*\nFinish setup yourself[^]*1\. Run node bin\/poki-photon\.mjs --assign/);
  assert.equal((await connection(named)).projectId, earlier.projectId);
  api.assignError = null;
  const bare = join(directory, 'bare');
  await mkdir(join(bare, 'bin'), { recursive: true });
  for (const name of ['setup-channels', 'poki-photon.mjs']) await writeFile(join(bare, 'bin', name), await readFile(join(root, 'bin', name)), { mode: 0o755 });
  const uninstalled = await cli(join(bare, 'bin/setup-channels'), ['--channel', 'imessage', '--provider', 'photon', '--config-dir', join(bare, 'photon'), '--answers', answers], { env });
  assert.equal(uninstalled.code, 0, uninstalled.stderr);
  assert.match(uninstalled.stdout, /Setup could not assign a shared iMessage line: Poki Agent's packages are not installed \(Cannot find module '[^']*photon-source\.mjs'\)\. Run npm ci --prefix agent from the repository root first\.\nFinish setup yourself/,
    'A checkout without the agent packages keeps the configuration and names what to install');
  const unloaded = await cli(process.execPath, [join(bare, 'bin/poki-photon.mjs'), '--config-dir', join(bare, 'photon')], { env });
  assert.equal(unloaded.code, 1);
  assert.match(unloaded.stderr, /^Poki Agent's packages are not installed \(Cannot find module '[^']*photon\.mjs'\)\. Run npm ci --prefix agent from the repository root first\.\n$/);

  api.organizations.push(other);
  await writeFile(placed, JSON.stringify({ sender: 'allowed@example.test', device: 'synthetic-device', organizationId: `pho_org_${'0'.repeat(25)}9` }), { mode: 0o600 });
  const stranger = await setup(join(directory, 'stranger'), false, [], placed);
  assert.equal(stranger.code, 1);
  assert.match(stranger.stderr, /does not belong to that organization ID/);
  await writeFile(placed, JSON.stringify({ sender: 'allowed@example.test', device: 'synthetic-device', organizationId: other.organizationId }));
  const team = await setup(join(directory, 'team'), false, [], placed);
  assert.equal(team.code, 0, team.stderr);
  assert.match(team.stdout, /Created the Photon project "Poki Agent" \(Other org, pho_prj_0{23}101\)\.[^]*Shared line assigned\./, 'An organizationId answer keeps the search and the new project to that organization');
  assert.deepEqual(await connection(join(directory, 'team')), { projectId: api.created[1].projectId, apiKey: api.key });

  api.fullSecret = true;
  const chosen = join(directory, 'chosen');
  const interactive = await terminal(['--config-dir', chosen, '--project-name', 'Side line'], '2\nallowed@example.test\nsynthetic-device\n2\n');
  assert.equal(interactive.code, 0, interactive.stdout);
  assert.match(interactive.stdout, /The code is valid for 5 minutes\.\s+Opened the link in your browser\.\s+Waiting for your approval/);
  const link = `${api.url}/device?user_code=WXYZ-1234\n`;
  assert.equal(await readFile(env.POKI_OPENED, 'utf8'), link, 'Only setup in a terminal opens the sign-in link, and once');
  api.login.denied = true;
  for (const [args, extra] of [[['--no-browser'], {}], [[], { CI: 'true' }]]) {
    const printed = await terminal([...args, '--config-dir', join(directory, 'printed')], '2\nallowed@example.test\nsynthetic-device\n', extra);
    assert.equal(printed.code, 1);
    assert.ok(printed.stdout.includes(link.trim()) && !printed.stdout.includes('Opened the link'), printed.stdout);
  }
  assert.equal(await readFile(env.POKI_OPENED, 'utf8'), link, 'The link is not opened with --no-browser or in CI');
  assert.match(interactive.stdout, /1\. BlueBubbles \(default\)[^]*stay on your machine[^]*2\. Photon[^]*pass through Photon's servers/);
  assert.match(interactive.stdout, /Your Photon organizations:\s+1\. Example org [^\n]*\s+2\. Other org [^]*Created the Photon project "Side line" \(Other org, pho_prj_0{23}102\)\./);
  assert.match(interactive.stdout, /Shared line assigned\. From allowed@example\.test, send an iMessage to \+14155550188 to start\./);
  assert.deepEqual(api.created.slice(1).map(({ organizationId, name, slug }) => ({ organizationId, name, slug: slug.slice(0, -8) })),
    [{ organizationId: other.organizationId, name: 'Poki Agent', slug: 'poki-agent-' }, { organizationId: other.organizationId, name: 'Side line', slug: 'side-line-' }]);
  assert.deepEqual(JSON.parse(await readFile(join(chosen, 'photon.json'), 'utf8')), { sender: 'allowed@example.test', device: 'synthetic-device', auth: 'chatgpt' });
  assert.deepEqual(await connection(chosen), { projectId: api.created[2].projectId, apiKey: api.key });
  const output = JSON.stringify([denied, unplaced, unsaved, signedIn, check, unassigned, uninstalled, unloaded, stranger, team, interactive]);
  assert.ok(!output.includes(api.key) && !output.includes(api.account) && !output.includes('local-device-code'));
  await evidence('photon-sign-in-setup.json', { denied, unplaced, unsaved, signedIn, check, unassigned, uninstalled, unloaded, stranger, team, interactive, keys: api.keys, created: api.created });
});
