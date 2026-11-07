import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, value } from './fixture.mjs';

test('MCP unlock rejects secret arguments and stays disabled without host device binding', async t => {
 const f = await fixture(t);
 const args = { observation_id: 'none', empty_keypad_confirmed: true, digits: Array.from({length:10}, () => ({x:10,y:50})) };
 assert.equal((await f.call('unlock_device', {...args, passcode:'000000'})).isError, true);
 const denied = await f.call('unlock_device', args); assert.equal(denied.isError, true);
 assert.match(denied.content[0].text, /disabled/);
 assert.equal((await f.events()).filter(e => e.op === 'tap').length, 0);
});
