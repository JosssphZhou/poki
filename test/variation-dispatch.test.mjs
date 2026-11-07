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
