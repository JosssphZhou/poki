import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, value } from './fixture.mjs';

test('MCP variation reaches input through schema and serialized dispatch', async t => {
 const f = await fixture(t);
 const r = await f.call('tap_text', { text: 'First', variation: true });
 assert.ok(!r.isError, JSON.stringify(r));
 const tap = (await f.events()).find(e => e.op === 'tap').request;
 // Fixture display is 100 x 200; First is centered on (30,20).
 assert.ok(tap.x >= Math.round(27 / 99 * 65535) && tap.x <= Math.round(33 / 99 * 65535));
 assert.ok(tap.y >= Math.round(17 / 199 * 65535) && tap.y <= Math.round(23 / 199 * 65535));
 assert.ok(tap.duration_ms >= 42 && tap.duration_ms <= 58);
});
test('MCP unlock rejects secret arguments and stays disabled without host device binding', async t => {
 const f = await fixture(t);
 const args = { observation_id: 'none', empty_keypad_confirmed: true, digits: Array.from({length:10}, () => ({x:10,y:50})) };
 assert.equal((await f.call('unlock_device', {...args, passcode:'000000'})).isError, true);
 const denied = await f.call('unlock_device', args); assert.equal(denied.isError, true);
 assert.match(denied.content[0].text, /disabled/);
 assert.equal((await f.events()).filter(e => e.op === 'tap').length, 0);
});
