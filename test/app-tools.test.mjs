import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, value } from './fixture.mjs';

test('compact MCP discovery, Mac extension and one-release compatibility work through stdio', async t => {
  const f = await fixture(t);
  assert.deepEqual((await f.a.listTools()).tools.map(x => x.name).sort(), ['do', 'look', 'mac', 'status']);
  assert.match(f.a.getInstructions(), /no approval protection/i);
  const status = value(await f.call('status'));
  assert.equal(status.implementation, 'Poki MCP 0.1.1');
  assert.match(status.approval_scope, /not gated/);
  const old = await f.call('wait', { seconds: 0 });
  assert.equal(value(old).waited, 0);
  assert.equal(old.content.filter(x => x.text?.includes('Deprecated')).length, 1);
  assert.match(old.content.at(-1).text, /mac/);
  const schema = value(await f.call('mac', { tool: 'wait', describe: true }));
  assert.equal(schema.inputSchema.properties.seconds.type, 'number');
  assert.equal(value(await f.call('mac', { tool: 'wait', arguments: { seconds: 0 } })).waited, 0);
  const apps = value(await f.call('mac', { tool: 'list_apps', arguments: { include_system: true } }));
  assert.ok(JSON.stringify(apps).includes('Settings'));
  const look = await f.call('look');
  assert.ok(!look.isError, JSON.stringify(look));
  assert.ok(look.content.some(x => x.type === 'image'));
  const action = await f.call('do', { actions: [{ tap: [20, 20] }], finish: false });
  assert.ok(!action.isError, JSON.stringify(action));
  assert.match(action.content.find(x => x.type === 'text').text, /sent/);
  t.diagnostic('stdio -> HTTP -> device fixture: look image, do tap sent, mac list_apps, status, old wait all succeeded');
});

test('Mac extension rejects unknown tools and original-schema violations; unsupported App behavior sends nothing', async t => {
  const f = await fixture(t);
  for (const args of [
    { tool: 'mac', arguments: {} },
    { tool: 'toString', arguments: {} },
    { tool: 'wait', arguments: { seconds: -1 } },
    { tool: 'touch_path', arguments: { points: [{ x: 1, y: 1, time_ms: 1 }, { x: 2, y: 2, time_ms: 0 }] } },
  ]) assert.equal((await f.call('mac', args)).isError, true, JSON.stringify(args));
  for (const args of [
    { actions: [{ tap: [20, 20] }], finish: true },
    { actions: [{ tap: [20, 20] }, { run: 'saved' }] },
    { actions: [{ handoff: false }] },
  ]) {
    const result = await f.call('do', args);
    assert.equal(result.isError, true);
    assert.match(result.content[0].text, /not supported on Mac/);
  }
  assert.equal((await f.events()).filter(e => ['tap', 'key', 'hid', 'type_keys', 'type_text'].includes(e.op)).length, 0);
  t.diagnostic('invalid tool/schema and unsupported finish/run/handoff rejected before device actions');
});
