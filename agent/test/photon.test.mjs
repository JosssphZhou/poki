import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { makePhoton } from './fixtures/photon.mjs';
import { PhotonSource, assignSharedLine } from '../photon-source.mjs';

const names = ['PHOTON_API_URL', 'PHOTON_PROJECT_ID', 'PHOTON_API_KEY'];

async function prepare(t) {
  const directory = await mkdtemp(join(tmpdir(), 'poki-photon-test-'));
  const fixture = await makePhoton();
  const before = names.map(name => process.env[name]);
  Object.assign(process.env, { PHOTON_API_URL: fixture.url, PHOTON_PROJECT_ID: fixture.project, PHOTON_API_KEY: fixture.key });
  const sources = [];
  t.after(async () => {
    for (const source of sources) source.close();
    names.forEach((name, index) => { if (before[index] === undefined) delete process.env[name]; else process.env[name] = before[index]; });
    await fixture.close(); await rm(directory, { recursive: true, force: true });
  });
  const start = () => { sources.push(new PhotonSource({ sender: 'allowed@example.test', stateDirectory: directory })); return sources.at(-1); };
  return { directory, fixture, start };
}

async function read(source, cursor) {
  while (source.lastQueued < cursor && !source.failure) await sleep(5);
  const messages = [];
  for await (const message of source.read()) messages.push(message);
  return messages;
}

test('Photon limits tasks and replies to one sender, skips history and resumes from its cursor', async t => {
  const { directory, fixture, start } = await prepare(t);
  fixture.add('History must not execute');
  let source = start();
  await source.open();
  assert.deepEqual(fixture.subscriptions, [0], 'A first start subscribes to new events only');
  const task = fixture.add('Allowed task');
  fixture.add('Private other task', { sender: 2 });
  fixture.add('Group content', { group: true });
  fixture.add(null, { content: { type: 'message.read', messageId: 'pho_msg_00000000000000000000001000' } });
  const photo = fixture.add(null, { content: { type: 'attachment', attachmentId: 'pho_att_00000000000000000000000001' } });
  const typing = fixture.add(null, { content: { type: 'space.typing.update', typing: true } });
  assert.deepEqual(await read(source, typing), [{ id: task, text: 'Allowed task' }, { id: photo, text: null }]);
  assert.deepEqual(await readdir(directory), [], 'Events after an unacknowledged task must not advance the cursor');
  await source.acknowledge(photo);
  await source.send('Task received');
  assert.deepEqual(fixture.sent, [{ spaceId: fixture.space.id, senderId: fixture.agent.id, content: { type: 'text', format: 'plain', text: 'Task received' } }]);
  await source.send('  ');
  assert.equal(fixture.sent.length, 1, 'Photon rejects empty text, so none is sent');

  source.close();
  const down = fixture.add('Sent while the worker was stopped');
  source = start();
  await source.open();
  assert.equal(fixture.subscriptions.at(-1), photo, 'A restart resumes after the acknowledged cursor');
  assert.deepEqual(await read(source, down), [{ id: down, text: 'Sent while the worker was stopped' }]);
  await source.acknowledge(down);

  fixture.drop();
  const dropped = fixture.add('Sent during a dropped connection');
  assert.deepEqual(await read(source, dropped), [{ id: dropped, text: 'Sent during a dropped connection' }]);
  assert.equal(fixture.subscriptions.at(-1), down, 'A reconnect resumes after the last received cursor');
  await source.acknowledge(dropped);
  fixture.deliver(down);
  const fresh = fixture.add('Fresh task');
  assert.deepEqual(await read(source, fresh), [{ id: fresh, text: 'Fresh task' }], 'A replayed event must not become a second task');
  await source.acknowledge(fresh);

  fixture.sendError = { status: 503, code: 'UPSTREAM_UNAVAILABLE', once: true };
  await source.send('Retried reply');
  const attempts = fixture.requests.filter(request => request.body?.content?.text === 'Retried reply');
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0].key, attempts[1].key, 'A retry reuses the idempotency key');
  assert.equal(fixture.sent.length, 2);
  fixture.sendError = { status: 403, code: 'SHARED_LINE_INBOUND_REQUIRED' };
  await assert.rejects(source.send('Must not claim delivery'), error =>
    /HTTP 403, SHARED_LINE_INBOUND_REQUIRED/.test(error.message) && !error.message.includes(fixture.key));
  fixture.sendError = null;
  assert.equal(fixture.sent.length, 2);

  const errors = t.mock.method(console, 'error', () => {});
  assert.deepEqual(await read(source, fixture.fail(1)), []);
  assert.equal(errors.mock.callCount(), 1);
  assert.match(errors.mock.calls[0].arguments[0], /reply was not delivered \(recipient_unreachable\)/);

  fixture.kick();
  await assert.rejects(read(source, Infinity), /Photon closed the event stream/);
  assert.throws(() => new PhotonSource({ sender: '', stateDirectory: directory }), /sender/);
  for (const [name, value, message] of [['PHOTON_API_URL', 'https://example.test', /PHOTON_API_URL must be the Photon API/],
    ['PHOTON_PROJECT_ID', 'project', /PHOTON_PROJECT_ID/], ['PHOTON_API_KEY', '', /PHOTON_API_KEY/]]) {
    const valid = process.env[name];
    process.env[name] = value;
    assert.throws(start, message);
    process.env[name] = valid;
  }
});

test('Photon marks the sender\'s messages read and shows typing from the opening to the final reply', async t => {
  const { fixture, start } = await prepare(t);
  t.mock.timers.enable({ apis: ['setInterval'] });
  const source = start();
  await source.open();
  fixture.add('Private other task', { sender: 2 });
  const task = fixture.add('Allowed task');
  await read(source, task);
  await source.presence;
  assert.deepEqual(fixture.read, [fixture.events.at(-1).event.data.object.id], 'Only the configured sender\'s message is marked read');
  assert.match(fixture.requests.at(-1).key, /^[0-9a-f-]{36}$/);
  await source.send('No task is running.');
  await source.presence;
  assert.deepEqual(fixture.typing, [], 'A reply outside a task shows no typing');

  await source.send('I\'ll work on "Allowed task".', { kind: 'opening' });
  await source.send('Added to the current task. Send /stop to stop it now.');
  t.mock.timers.tick(20000);
  await source.presence;
  assert.deepEqual(fixture.typing, [true, true, true], 'Typing restarts after each reply during a task and is refreshed while it runs');
  await source.send('Done.', { kind: 'final' });
  t.mock.timers.tick(60000);
  await source.presence;
  assert.deepEqual(fixture.typing, [true, true, true, false], 'The final reply ends typing and its refreshes');
  assert.deepEqual(fixture.requests.at(-1).body, { senderId: fixture.agent.id, typing: false });

  const errors = t.mock.method(console, 'error', () => {});
  fixture.presenceError = { status: 422, code: 'OPERATION_UNAVAILABLE' };
  await read(source, fixture.add('Second task'));
  await source.send('I\'ll work on "Second task".', { kind: 'opening' });
  t.mock.timers.tick(20000);
  await source.send('Done again.', { kind: 'final' });
  await source.presence;
  assert.deepEqual(fixture.sent.slice(-2).map(message => message.content.text), ['I\'ll work on "Second task".', 'Done again.'], 'Replies continue when Photon rejects read receipts and typing');
  assert.deepEqual(errors.mock.calls.map(call => call.arguments[0]), [
    'photon: read receipts are unavailable (HTTP 422, OPERATION_UNAVAILABLE); continuing without them.',
    'photon: typing indicators are unavailable (HTTP 422, OPERATION_UNAVAILABLE); continuing without them.',
  ], 'Each is reported once and not tried again');
  assert.equal(fixture.requests.filter(request => /\/(read|typing)$/.test(request.path)).length, 7);
});

test('Photon check connects without saving a cursor or sending, and refuses a wrong key', async t => {
  const { directory, fixture, start } = await prepare(t);
  await start().check();
  assert.deepEqual(fixture.subscriptions, [0]);
  assert.deepEqual(await readdir(directory), []);
  assert.equal(fixture.sent.length, 0);
  process.env.PHOTON_API_KEY = 'pho_sk_wrong-key';
  await assert.rejects(start().check(), error => /Photon refused the event connection/.test(error.message) && !error.message.includes('pho_sk_wrong-key'));
});

test('Photon assignment returns the shared line, finds an existing one and explains a missing permission', async t => {
  const { fixture } = await prepare(t);
  assert.equal(await assignSharedLine('allowed@example.test'), fixture.agent.handle);
  const created = fixture.requests.at(-1);
  assert.deepEqual(created.body, { handle: 'allowed@example.test' });
  assert.match(created.key, /^[0-9a-f-]{36}$/);
  assert.equal(await assignSharedLine('allowed@example.test'), fixture.agent.handle, 'An existing assignment is looked up, not duplicated');
  assert.equal(fixture.assignments.length, 1);
  fixture.assignError = { status: 403, code: 'INSUFFICIENT_SCOPE' };
  await assert.rejects(assignSharedLine('other@example.test'), /platforms:write/);
});
