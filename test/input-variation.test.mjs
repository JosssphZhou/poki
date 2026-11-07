import test from 'node:test';
import assert from 'node:assert/strict';
import { variedInput } from '../src/input-variation.mjs';
import { interaction } from '../src/interaction.mjs';
import { work } from '../src/work.mjs';

test('default input is identical and does not sample randomness', async () => {
 const request = { op: 'tap', x: 2, y: 3, duration_ms: 50 };
 await variedInput({ input: async r => assert.equal(r, request) }, request, false, undefined, true, () => { throw Error('sampled'); });
});
test('variation stays inside small targets and preserves raw coordinates and explicit durations', async () => {
 for (const sample of [() => 0, () => .999999]) {
  let sent; const ctx = { input: async r => { sent = r; } };
  await variedInput(ctx, { op: 'tap', x: 1, y: 2, duration_ms: 50 }, true, { x: 0, y: 0, width: 2, height: 4 }, true, sample);
  assert.ok(sent.x >= .5 && sent.x <= 1.5); assert.ok(sent.y >= 1 && sent.y <= 3);
  assert.ok(sent.duration_ms >= 42 && sent.duration_ms <= 58);
  await variedInput(ctx, { op: 'drag', x1: 0, y1: 0, x2: 50, y2: 100, duration_ms: 900 }, true, undefined, false, sample);
  assert.deepEqual(sent, { op: 'drag', x1: 0, y1: 0, x2: 50, y2: 100, duration_ms: 900 });
 }
});
test('cancelled variation does not dispatch input', async () => {
 const control = new AbortController(); control.abort();
 await assert.rejects(work.run({ signal: control.signal }, () => variedInput({ input() { assert.fail('sent'); } }, { op: 'tap' }, true)));
});
test('interaction forwards opt-in variation without leaking target bounds', async () => {
 let sent; const ctx = { viewport: async () => {}, elementsAt: Date.now(), elements: [{ ref: 'e1', frame: { x: 10, y: 20, width: 40, height: 30 } }], input: async r => { sent = r; } };
 await interaction(ctx, 'tap', { ref: 'e1', variation: true });
 assert.ok(sent.x >= 27 && sent.x <= 33); assert.ok(sent.y >= 32 && sent.y <= 38); assert.equal(sent.bounds, undefined);
 await interaction(ctx, 'long_press', { x: 10, y: 20, duration: 2, variation: true });
 assert.deepEqual(sent, { op: 'long_press', x: 10, y: 20, duration_ms: 2000 });
});
