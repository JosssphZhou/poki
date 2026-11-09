import assert from 'node:assert/strict';
import { createHash, createHmac, generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { Miniflare } from 'miniflare';
import test from 'node:test';

const file = relative => fileURLToPath(new URL(relative, import.meta.url));
const owner = '+15555550100';
const signingKey = 'only-for-the-local-fixture';
const conversation = '0e7f23b2-b6f2-43d3-a4f0-4ab279b5af63';

function base32(raw) {
  const bits = Array.from(raw, byte => byte.toString(2).padStart(8, '0')).join('');
  return (bits + '0000').match(/.{5}/g).map(group => 'abcdefghijklmnopqrstuvwxyz234567'[parseInt(group, 2)]).join('');
}

function signedMessage(id, content, fields = {}, context = []) {
  const body = JSON.stringify({
    event_type: 'imessage.received',
    data: {
      message: { id, conversation_id: conversation, service: 'imessage', direction: 'inbound',
        remote_number: owner, content, created_at: new Date().toISOString(), ...fields },
      context: { texts: { items: context } },
    },
  });
  const requestId = randomBytes(8).toString('hex');
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = createHmac('sha256', signingKey).update(requestId + '.' + timestamp + '.' + body).digest('hex');
  return { method: 'POST', body, headers: {
    'x-inkbox-request-id': requestId, 'x-inkbox-timestamp': timestamp, 'x-inkbox-signature': 'sha256=' + signature,
  } };
}

for (const structured of [true, false]) {
test(`signed iMessage follows real relay OAuth (${structured ? 'threaded' : 'older Poki'})`, { timeout: 30_000 }, async t => {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const raw = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
  const label = base32(raw);
  const secret = randomBytes(32).toString('base64url');
  const pokiUrl = 'https://relay.test/v1/' + label + '/' + secret + '/mcp';
  const requests = [];
  const replies = [];
  const sendAttempts = [];
  const relay = new Miniflare({
    modules: true, modulesRoot: file('../cf-relay/src/'),
    scriptPath: file('../cf-relay/src/index.js'),
    compatibilityDate: '2025-10-01', bindings: { TOKEN_SECRET: randomBytes(32).toString('hex') },
    durableObjects: { DEVICE: { className: 'DeviceRelay', useSQLite: true }, BUDGET: { className: 'Budget', useSQLite: true } },
  });
  t.after(() => relay.dispose());
  const upgrade = await relay.dispatchFetch('https://relay.test/v1/' + label + '/connect', {
    headers: { Upgrade: 'websocket' },
  });
  assert.equal(upgrade.status, 101);
  const ws = upgrade.webSocket;
  const connected = Promise.withResolvers();
  const session = 'fixture-mcp-session';
  let taskNumber = 0;
  ws.addEventListener('message', event => {
    const frame = JSON.parse(event.data);
    if (frame.t === 'challenge') {
      const sig = sign(null, Buffer.concat([Buffer.from('poki-relay-v1:' + label + ':'), Buffer.from(frame.nonce, 'base64')]), privateKey);
      ws.send(JSON.stringify({ t: 'hello', v: 1, key: raw.toString('base64'), sig: sig.toString('base64'),
        access: [createHash('sha256').update(secret).digest('hex')], app: 'fixture' }));
    } else if (frame.t === 'ready') {
      connected.resolve();
    } else if (frame.t === 'req') {
      try {
        if (frame.method === 'DELETE') {
          ws.send(JSON.stringify({ t: 'res', id: frame.id, status: 200, headers: {}, body: '' }));
          return;
        }
        const request = JSON.parse(frame.body);
        requests.push(request);
        let result;
        if (request.method !== 'initialize') assert.equal(frame.headers['mcp-session-id'], session);
        if (request.method === 'initialize') result = { protocolVersion: request.params.protocolVersion };
        if (request.method === 'tools/list') {
          const properties = structured ? { task: {}, conversation_id: {}, message: {} } : { task: {} };
          result = { tools: [{ name: 'ask_poki', inputSchema: { type: 'object', properties } }] };
        }
        if (request.method === 'tools/call') {
          assert.equal(request.params.name, 'ask_poki');
          const args = request.params.arguments;
          let text;
          if (args.check === true) text = structured ? '已打开设置。' : 'result: done: 已打开设置。\nPoki said: 已打开设置。';
          else text = ++taskNumber === 1 ? 'working: Poki is still on the task.' : '已点开通用。';
          result = { content: [{ type: 'text', text }] };
        }
        ws.send(JSON.stringify({ t: 'res', id: frame.id, status: request.id === undefined ? 202 : 200,
          headers: { 'content-type': 'application/json', 'mcp-session-id': session },
          body: request.id === undefined ? '' : JSON.stringify({ jsonrpc: '2.0', id: request.id, result }) }));
      } catch (error) { t.diagnostic(error.message); ws.close(); }
    }
  });
  ws.accept();
  t.after(() => { try { ws.close(); } catch {} });
  await connected.promise;
  const bridge = new Miniflare({
    modules: true, scriptPath: file('./worker.mjs'), compatibilityDate: '2026-07-30',
    durableObjects: { INBOX: { className: 'Inbox', useSQLite: true } },
    bindings: { INKBOX_SIGNING_KEY: 'whsec_' + signingKey, INKBOX_API_KEY: 'fixture-api-key',
      INKBOX_ALLOWED_SENDER: owner, POKI_MCP_URL: pokiUrl },
    async outboundService(request) {
      const url = new URL(request.url);
      if (url.hostname === 'relay.test') {
        const response = await relay.dispatchFetch(request.url, {
          method: request.method, headers: request.headers, body: request.body ? await request.arrayBuffer() : undefined,
          redirect: 'manual',
        });
        return new Response(await response.arrayBuffer(), { status: response.status, headers: response.headers });
      }
      assert.equal(request.url, 'https://inkbox.ai/api/v1/imessage/messages');
      assert.equal(request.headers.get('x-api-key'), 'fixture-api-key');
      sendAttempts.push(request.headers.get('idempotency-key'));
      replies.push(await request.json());
      return Response.json({ message: { id: 'fixture-reply-' + replies.length } });
    },
  });
  t.after(() => bridge.dispose());
  const post = request => bridge.dispatchFetch('https://bridge.test/webhook', request);
  const first = signedMessage('first', '打开设置');
  assert.equal((await post({ ...first, body: first.body + ' ' })).status, 401);
  assert.equal((await post(signedMessage('outsider', '打开设置', { remote_number: '+15555550199' }))).status, 204);
  assert.equal((await post(signedMessage('group', '打开设置', { is_group: true }))).status, 204);
  assert.equal((await post(first)).status, 202);
  assert.equal((await post(signedMessage('first', '打开设置'))).status, 204);
  const now = new Date().toISOString();
  const context = [
    { id: 'prior', channel: 'imessage', direction: 'inbound', sender: owner, created_at: now, text: '接下来看手机设置' },
    { id: 'sms', channel: 'sms', direction: 'outbound', created_at: now, text: '不要带上这条短信' },
  ];
  assert.equal((await post(signedMessage('second', '再点通用', {}, context))).status, 202);

  const deadline = Date.now() + 14_000;
  while (replies.length < 2 && Date.now() < deadline) await delay(75);
  assert.deepEqual(replies, [
    { conversation_id: conversation, text: '已打开设置。' },
    { conversation_id: conversation, text: '已点开通用。' },
  ]);
  const calls = requests.filter(r => r.method === 'tools/call').map(r => r.params.arguments);
  assert.equal(calls.length, 3);
  assert.deepEqual(calls[1], { check: true });
  for (const [call, message] of [[calls[0], '打开设置'], [calls[2], '再点通用']]) {
    if (structured) {
      assert.equal(call.conversation_id, conversation);
      assert.equal(call.message, message);
    } else {
      assert.deepEqual(Object.keys(call), ['task']);
    }
  }
  assert.match(calls[0].task, /打开设置/);
  assert.match(calls[2].task, /接下来看手机设置/);
  assert.match(calls[2].task, /已打开设置/);
  assert.match(calls[2].task, /再点通用/);
  assert.doesNotMatch(calls[2].task, /不要带上这条短信/);
  assert.equal(new Set(sendAttempts).size, 2);
});
}
