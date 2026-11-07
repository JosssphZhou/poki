import test from 'node:test';
import assert from 'node:assert/strict';
process.env.POKI_IPHONE_PASSCODE = '102938'; // Synthetic test credential.
const { unlockDevice } = await import('../src/unlock.mjs');
let nextId = 0;
const digits = [{ x: 215, y: 780 }, ...Array.from({length: 9}, (_, i) => ({ x: 100 + i % 3 * 115, y: 450 + Math.floor(i / 3) * 110 }))];
function keypad() { return { foreground: { pid: 39 }, elements: [{ label: '输入密码' }, { role: 'TextField', value: '共6位数，已输入0位' }, ...digits.map((p, i) => ({ label: String(i), role: 'Key', frame: {x:p.x-40,y:p.y-40,width:80,height:80} }))] }; }
function fixture() {
 const sent = [], id = `unlock-unit-${nextId++}`;
 const ctx = { target: async () => ({ id, kind: 'physical' }), frame: { id: 'frame', device: id, at: Date.now(), revision: 0, width: 430, height: 932 }, coordinator: { revision: () => 0 }, bridge: async r => r.op === 'process_info' ? { executable: '/System/Library/CoreServices/SpringBoard.app/SpringBoard' } : r.op === 'launch_app' ? { pid: 42 } : sent.length ? { foreground: { pid: 42 }, elements: [{}] } : keypad(), input: async r => { sent.push(r); return { sent: true }; }, settle: async () => {} };
 const env = { POKI_UNLOCK_DEVICE: id, POKI_IPHONE_PASSCODE: '102938' };
 const args = { observation_id: 'frame', empty_keypad_confirmed: true, digits };
 return { ctx, env, args, sent, call: () => { process.env.POKI_UNLOCK_DEVICE = env.POKI_UNLOCK_DEVICE; return unlockDevice(ctx, args); } };
}
test('one configured attempt uses observed layout and reports verified foreground', async () => {
 const f = fixture(); const result = await f.call(); assert.equal(result.unlock_verified, true);
 assert.deepEqual(f.sent.map(r => [r.x, r.y]), [...f.env.POKI_IPHONE_PASSCODE].map(d => [digits[+d].x, digits[+d].y]));
 assert.ok(!JSON.stringify(result).includes(f.env.POKI_IPHONE_PASSCODE));
});
test('wrong device, stale observation and app keypad send nothing for the stated reason', async () => {
 for (const [mutate, reason] of [
  [f => f.env.POKI_UNLOCK_DEVICE = 'other', /disabled/],
  [f => f.ctx.frame.at -= 31000, /expired/],
  [f => f.ctx.frame.revision++, /expired/],
  [f => f.args.empty_keypad_confirmed = false, /Observe an empty/],
  [f => f.ctx.bridge = async () => ({ elements: [{ label: '输入密码' }] }), /system passcode screen/],
 ]) {
  const f = fixture(); mutate(f); await assert.rejects(f.call(), reason); assert.equal(f.sent.length, 0);
 }
});
test('unchanged keypad stays unverified and blocks repeated PIN input', async () => {
 const f = fixture(); f.ctx.bridge = async r => r.op === 'process_info' ? { executable: '/System/Library/CoreServices/SpringBoard.app/SpringBoard' } : keypad();
 const result = await f.call(); assert.equal(result.unlock_verified, false); assert.equal(result.isError, true); assert.equal(result.stop_reason, 'unknown'); await assert.rejects(f.call(), /human review/); assert.equal(f.sent.length, 6);
});
test('invalid and landscape keypad layouts send no input', async () => {
 for (const [mutate, reason] of [
  [f => Object.assign(f.ctx.frame, {width:932,height:430}), /portrait/],
  [f => f.args.digits = digits.map(p => ({...p,x:20})), /rows/],
  [f => f.args.digits = digits.map(p => ({...p,y:NaN})), /inside the observed/],
 ]) {
  const f=fixture();mutate(f);await assert.rejects(f.call(),reason);assert.equal(f.sent.length,0);
 }
});

test('partial PIN, mismatched keys and spoofed app do not receive any digits', async () => {
 for (const kind of ['partial', 'keys', 'process']) {
  const f = fixture(), bridge = f.ctx.bridge;
  f.ctx.bridge = async r => {
   const result = await bridge(r);
   if (kind === 'partial' && r.op === 'ax') result.elements[1].value = '共6位数，已输入1位';
   if (kind === 'keys' && r.op === 'ax') result.elements[2].frame.x += 10;
   if (kind === 'process' && r.op === 'process_info') result.executable = '/Applications/Fake.app/Fake';
   return result;
  };
  await assert.rejects(f.call(), {partial:/empty six-digit/,keys:/coordinates/,process:/system passcode screen/}[kind]); assert.equal(f.sent.length, 0);
 }
});

test('verified unlock clears the shared attempt guard', async () => {
 const f=fixture();assert.equal((await f.call()).unlock_verified,true);
 f.sent.length=0;assert.equal((await f.call()).unlock_verified,true);
});
