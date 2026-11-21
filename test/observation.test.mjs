import test from 'node:test';
import assert from 'node:assert/strict';
import { rm, writeFile } from 'node:fs/promises';
import { Devices } from '../src/device.mjs';
import { join } from 'node:path';
import sharp from 'sharp';
import { fixture, value } from './fixture.mjs';

test('action readback distinguishes disabled, zero, off, empty, and unavailable control values', async t => {
  const f = await fixture(t);
  const frame = { x: 10, y: 10, width: 40, height: 20 };
  await f.set({ elements: [
    { role: 'Button', label: 'Disabled sample', enabled: 0, frame },
    { role: 'Slider', label: 'Volume', value: 0, frame },
    { role: 'Switch', label: 'Notifications', value: false, frame },
    { role: 'ProgressIndicator', label: 'Upload', value: '', frame },
    { role: 'Slider', label: 'Brightness', value: null, frame },
  ] });
  const result = value(await f.call('tap', { x: 12, y: 12 }));
  const text = result.screen.text.join('\n');
  assert.match(text, /Disabled sample.*disabled/i);
  assert.match(text, /Volume = 0\b/);
  assert.match(text, /Notifications = off\b/i);
  assert.match(text, /Upload.*empty/i);
  assert.match(text, /Brightness.*unknown/i);
});

test('wait_for returns a visible AX match even when screenshots are unavailable', async t => {
  const f = await fixture(t);
  await f.call('take_screenshot');
  await f.set({ label: 'Ready', screenshotUnavailable: true });
  const reply = await f.call('wait_for', { text: 'Ready', timeout_seconds: 3 });
  assert.equal(reply.isError, undefined);
  const result = value(reply);
  assert.equal(result.matched, true);
  assert.equal(result.source, 'accessibility');
  assert.equal(result.elements[0].label, 'Ready');
  assert.ok(reply.content.every(block => block.type === 'text'));
  await f.set({ label: 'Ready' });
  const pictured = await f.call('wait_for', { text: 'Ready', include_image: true, timeout_seconds: 3 });
  assert.equal(value(pictured).matched, true);
  assert.ok(pictured.content.some(block => block.type === 'image'));
});

test('wait_for timeout reports the last OCR lookalike and the time spent reading', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Other', ocrLabel: 'Rei Al' });
  const reply = await f.call('wait_for', { text: 'Rei AI', timeout_seconds: 2 });
  assert.equal(reply.isError, true);
  const result = value(reply);
  assert.equal(result.matched, false);
  assert.ok(result.candidates.some(candidate => candidate.text === 'Rei Al' && candidate.source === 'ocr'));
  for (const key of ['accessibility', 'screen_capture', 'ocr', 'polling']) assert.equal(typeof result.timing_ms[key], 'number');
});

test('a delayed page change returns a stable observation of the new page', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Open', afterInput: { label: 'Destination', staleReads: 2, staleLabel: 'Open' } });
  const response = await f.call('tap', { x: 12, y: 12, return_observation: true });
  assert.ok(!response.isError, response.content[0].text);
  const receipt = value(response);
  assert.equal(receipt.screen_change, 'changed');
  assert.ok(receipt.screen.text.includes('Button: Destination'));
  assert.notEqual(receipt.screen.screen_stable, false);
  assert.equal(receipt.post_action_observation?.elements[0].label, 'Destination');
});

test('a loading screen cannot supply a stable post-action receipt', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Open', afterInput: { label: 'Destination', staleReads: 4, staleLabel: 'Loading…' } });
  const reply = await f.call('tap', { x: 12, y: 12, return_observation: true });
  assert.ok(!reply.isError, reply.content[0].text);
  const receipt = value(reply);
  if (receipt.screen.partial) {
    assert.equal(receipt.screen.screen_stable, false);
    assert.equal(receipt.post_action_observation, undefined);
  } else {
    assert.ok(receipt.screen.text.includes('Button: Destination'), JSON.stringify(receipt.screen));
    assert.equal(receipt.post_action_observation?.elements[0].label, 'Destination');
  }
});

async function screenshotScenes(f, entries) {
  return Promise.all(entries.map(async ([color, label]) => {
    const path = join(f.dir, `${color}.png`);
    await sharp({ create: { width: 100, height: 200, channels: 3, background: color } }).png().toFile(path);
    return { path, elements: label ? [{ text: label, x: 10, y: 10, width: 40, height: 20 }] : [] };
  }));
}

test('changing frames with empty accessibility do not count as settled', async t => {
  const f = await fixture(t);
  const scenes = await screenshotScenes(f, [['red', 'Transition'], ['gray', 'Transition'], ['blue', 'Destination']]);
  await f.set({ axEmpty: true, afterInput: { screenshotScenes: scenes } });
  const reply = await f.call('tap', { x: 12, y: 12 });
  assert.ok(!reply.isError, reply.content[0].text);
  const receipt = value(reply);
  if (receipt.screen.partial) assert.equal(receipt.screen.screen_stable, false);
  else assert.ok(receipt.screen.text.includes('StaticText: Destination'), JSON.stringify(receipt.screen));
});

test('wait_for excludes offscreen and covered accessibility matches on a cold screen', async t => {
  const f = await fixture(t);
  await f.set({ ocrElements: [], elements: [
    { role: 'Button', label: 'Continue', identifier: 'offscreen', depth: 1, frame: { x: 10, y: 300, width: 50, height: 20 } },
    { role: 'Button', label: 'Continue', identifier: 'under-alert', depth: 1, frame: { x: 20, y: 55, width: 50, height: 20 } },
    { role: 'Alert', depth: 1, frame: { x: 5, y: 45, width: 90, height: 100 } },
    { role: 'Button', label: 'Continue', identifier: 'in-alert', depth: 2, frame: { x: 20, y: 95, width: 50, height: 20 } },
  ] });
  const reply = await f.call('wait_for', { text: 'Continue', timeout_seconds: 5 });
  assert.ok(!reply.isError, reply.content[0].text);
  assert.deepEqual(value(reply).elements.map(element => element.identifier), ['in-alert']);
});

test('wait_for gone confirms an empty OCR screen after transient absence', async t => {
  const f = await fixture(t);
  const scenes = await screenshotScenes(f, [['red', ''], ['gray', 'Loading'], ['blue', '']]);
  await f.set({ axEmpty: true, screenshotScenes: scenes });
  const reply = await f.call('wait_for', { text: 'Loading', gone: true, timeout_seconds: 10 });
  assert.ok(!reply.isError, reply.content[0].text);
  assert.equal(value(reply).matched, true);
  assert.deepEqual(value(reply).elements, []);
  const image = reply.content.find(block => block.type === 'image');
  const { channels } = await sharp(Buffer.from(image.data, 'base64')).stats();
  assert.deepEqual(channels.slice(0, 3).map(channel => channel.mean), [0, 0, 255]);
});

test('wait_for gone ignores unrelated changing pixels', async t => {
  const f = await fixture(t);
  const scenes = await screenshotScenes(f, Array.from({ length: 16 }, (_, index) => [`#${(0x380000 + index * 0x100).toString(16)}`, 'Playback']));
  await f.set({ label: 'Playback', screenshotScenes: scenes });
  const reply = await f.call('wait_for', { text: 'Loading', gone: true, timeout_seconds: 5 });
  assert.ok(!reply.isError, reply.content[0].text);
  assert.equal(value(reply).matched, true);
  assert.deepEqual(value(reply).elements, []);
});

test('a completed progress control neither holds disappearance nor blocks a stable action receipt', async t => {
  const f = await fixture(t);
  await f.set({ ocrElements: [], elements: [
    { role: 'Button', label: 'Done', frame: { x: 8, y: 15, width: 40, height: 30 } },
    { role: 'ProgressIndicator', label: 'Storage used', value: 100, frame: { x: 8, y: 60, width: 50, height: 10 } },
  ] });
  const gone = await f.call('wait_for', { text: 'Uploading', gone: true, timeout_seconds: 8 });
  assert.ok(!gone.isError, gone.content[0].text);
  assert.equal(value(gone).matched, true);
  const tap = await f.call('tap', { x: 12, y: 20, return_observation: true });
  assert.ok(!tap.isError, tap.content[0].text);
  assert.ok(value(tap).post_action_observation?.elements.some(element => element.label === 'Storage used'));
});

test('wait_for matches provide usable tap refs with and without an attached screenshot', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Continue' });
  for (const include_image of [true, false]) {
    const reply = await f.call('wait_for', { text: 'Continue', include_image, timeout_seconds: 5 });
    assert.ok(!reply.isError, reply.content[0].text);
    assert.equal(reply.content.some(block => block.type === 'image'), include_image);
    const tap = await f.call('tap', { ref: value(reply).elements[0].ref, verify: false });
    assert.ok(!tap.isError, tap.content[0].text);
    assert.equal(value(tap).sent, true);
  }
  assert.equal((await f.events()).filter(event => event.op === 'tap').length, 2);
});

test('tap follows a wait ref after rotation even when the first tree still reports portrait', async t => {
  const f = await fixture(t);
  const control = (x, y) => ({ role: 'Button', label: 'Continue', identifier: 'continue-action', frame: { x, y, width: 40, height: 20 } });
  const portrait = [control(10, 60)], landscape = [control(120, 40)];
  await f.set({ elements: portrait });
  const ref = value(await f.call('wait_for', { text: 'Continue' })).elements[0].ref;
  await sharp({ create: { width: 200, height: 100, channels: 3, background: 'white' } }).png().toFile(f.image);
  await f.set({ elements: landscape, staleReads: 1, staleElements: portrait });
  const reply = await f.call('tap', { ref, verify: false });
  assert.ok(!reply.isError, reply.content[0].text);
  const taps = (await f.events()).filter(event => event.op === 'tap');
  assert.equal(taps.length, 1);
  assert.deepEqual([taps[0].request.x, taps[0].request.y], [
    Math.round(140 / 199 * 65535), Math.round(50 / 99 * 65535),
  ]);

  const nextRef = value(await f.call('wait_for', { text: 'Continue' })).elements[0].ref;
  await f.set({ elements: [{ ...landscape[0], identifier: 'cancel-action', label: 'Cancel' }] });
  const missing = await f.call('tap', { ref: nextRef, verify: false });
  assert.equal(missing.isError, true);
  assert.match(missing.content[0].text, /same control could not be confirmed.*No input was sent/i);
  assert.equal((await f.events()).filter(event => event.op === 'tap').length, 1);
});

test('a slow post-action receipt can tap the same control after it moves', { timeout: 30000 }, async t => {
  const f = await fixture(t);
  const control = y => ({ role: 'Button', label: 'Destination', identifier: 'destination-action', frame: { x: 20, y, width: 40, height: 20 } });
  await f.set({ label: 'Open', afterInput: { axDelayMs: 1700, elements: [control(20)] } });
  const action = await f.call('tap', { x: 12, y: 12, return_observation: true });
  assert.ok(!action.isError, action.content[0].text);
  const receipt = value(action);
  assert.equal(receipt.screen_change, 'changed');
  const ref = receipt.post_action_observation?.elements.find(element => element.identifier === 'destination-action')?.ref;
  assert.match(ref ?? '', /^e\d+$/, JSON.stringify(receipt.screen));
  await f.set({ axDelayMs: 1700, elements: [control(105)] });
  const reply = await f.call('tap', { ref, verify: false });
  assert.ok(!reply.isError, reply.content[0].text);
  const taps = (await f.events()).filter(event => event.op === 'tap');
  assert.equal(taps.length, 2);
  assert.deepEqual([taps[1].request.x, taps[1].request.y], [
    Math.round(40 / 99 * 65535), Math.round(115 / 199 * 65535),
  ]);
});

// A phone over a network tunnel takes seconds per accessibility read; the fixture's delay stands in for it.
test('a tap on a phone with slow accessibility reads still ends with the screen', { timeout: 30000 }, async t => {
 const f=await fixture(t);await f.set({axDelayMs:2200});
 const result=await f.call('tap',{x:10,y:10});
 assert.notEqual(result.isError,true,result.content[0].text);
 const receipt=value(result);
 assert.equal(receipt.screen.unavailable,undefined,JSON.stringify(receipt));
 assert.ok(receipt.screen.text.includes('Button: First'),JSON.stringify(receipt));
});

test('a readback cut off by its deadline reports the last complete read instead of nothing', { timeout: 30000 }, async t => {
 const f=await fixture(t);await f.set({afterInput:{axDelays:[300,20000]}});
 const result=await f.call('tap',{x:10,y:10});
 assert.notEqual(result.isError,true,result.content[0].text);
 const receipt=value(result);
 assert.equal(receipt.screen.partial,true,JSON.stringify(receipt));
 assert.ok(receipt.screen.text.includes('Button: First'));
 assert.match(receipt.screen.reason,/deadline/);
});

test('screen_change says changed, unchanged, or unknown, and only unchanged carries the no-change advice', { timeout: 60000 }, async t => {
 const f=await fixture(t);await f.set({label:'Row 1',afterInput:{label:'Row 9',axDelays:[300,20000]}});
 // The readback is cut off, but its one complete read already differs from the screen before the scroll.
 const moved=value(await f.call('scroll',{direction:'down', return_observation:true}));
 assert.equal(moved.screen.partial,true);assert.equal(moved.screen_change,'changed');assert.equal(moved.screen_changed,true);
 assert.equal(moved.post_action_observation,undefined,'An unconfirmed post-input tree must not supply refs');
 await f.set({label:'Same',afterInput:{axDelays:[300,20000]}});
 const unknown=value(await f.call('tap',{x:10,y:10}));
 assert.equal(unknown.screen_change,'unknown');assert.equal(unknown.screen_changed,undefined);assert.equal(unknown.instruction,undefined);
 await f.set({label:'Same'});
 const still=value(await f.call('tap',{x:10,y:10}));
 assert.equal(still.screen_change,'unchanged');assert.match(still.instruction,/no change was observed/);
});

// The field report's Photos selection: six coordinate taps in one batch took about 61 s.
test('six coordinate taps in one batch read the screen once at the end, not around every tap', { timeout: 90000 }, async t => {
 const f=await fixture(t);await f.set({axDelayMs:2200});
 const started=performance.now();
 const result=await f.call('batch_commands',{commands:Array.from({length:6},(_,i)=>({tool:'tap',arguments:{x:10+i*10,y:100}}))});
 const elapsed=performance.now()-started;
 assert.notEqual(result.isError,true,JSON.stringify(result.content));
 const events=await f.events();
 assert.equal(events.filter(e=>e.op==='tap').length,6);
 assert.equal(events.filter(e=>e.args?.includes('screenshot')).length,1);
 // The last tap is compared with the screen before it, and the batch's own readback reuses that read.
 assert.ok(events.filter(e=>e.op==='ax_tree').length<=5,String(events.filter(e=>e.op==='ax_tree').length));
const summary=JSON.parse(result.content.at(-1).text);
 assert.ok(summary.screen.text.includes('Button: First'));
 assert.ok(elapsed<20000,`batch took ${Math.round(elapsed)} ms`);
});

test('a gated tool says who approved it, and the status names the tools approval covers', { timeout: 30000 }, async t => {
 const f=await fixture(t,{approvalMode:'allow'});await f.set({simulatorOnly:true,simulatorBooted:true});
 const status=value(await f.call('poki_mcp_status'));
 assert.equal(status.approval_mode,'operator-preapproved');
 assert.ok(status.approval_covers.includes('open_url')&&!status.approval_covers.includes('tap'));
 const opened=await f.call('open_url',{url:'https://example.com'});
 assert.notEqual(opened.isError,true,JSON.stringify(opened));
 assert.deepEqual(value(opened).approval,{mode:'operator-preapproved',approved_by:'operator'});
 assert.equal(value(await f.call('tap',{x:10,y:10})).approval,undefined);
});

test('launch_app on a phone ends with the screen, says when the app resumed, and fresh relaunches it', { timeout: 60000 }, async t => {
 const f=await fixture(t);
 const first=value(await f.call('launch_app',{bundle_id:'local.fixture'}));
 assert.equal(first.foreground_verified,true);assert.equal(first.resumed,false);
 assert.ok(first.screen.text.includes('Button: First'),JSON.stringify(first));
 const again=value(await f.call('launch_app',{bundle_id:'local.fixture'}));
 assert.equal(again.resumed,true);assert.match(again.notice,/fresh=true/);
 const fresh=value(await f.call('launch_app',{bundle_id:'local.fixture',fresh:true}));
 assert.equal(fresh.resumed,false);
 assert.equal((await f.events()).filter(e=>e.op==='launch_app').at(-1).request.terminate_existing,true);
});

test('a screenshot says it was not saved to the device Photos library', { timeout: 30000 }, async t => {
 const f=await fixture(t);
 const shot=await f.call('take_screenshot');
 assert.ok(shot.content.some(c=>c.type==='text'&&/not saved to the device's Photos library/.test(c.text)));
});

// On the phone an app opening from the Home Screen kept reporting the Home Screen's tree for two reads.
test('a screen that only lags behind the touch is not called unchanged', { timeout: 60000 }, async t => {
 const f=await fixture(t);
 await f.set({label:'Settings',afterInput:{label:'General',staleReads:2,staleLabel:'Settings'}});
 const lagging=value(await f.call('tap_text',{text:'Settings'}));
 assert.equal(lagging.screen_change,'changed',JSON.stringify(lagging));assert.equal(lagging.instruction,undefined);
 assert.ok(lagging.screen.text.includes('Button: General'));
 // An app icon is given longer to bring its app to the front.
 await f.set({label:'Settings',role:'Icon',afterInput:{label:'General',staleReads:5,staleLabel:'Settings'}});
 assert.equal(value(await f.call('tap_text',{text:'Settings'})).screen_change,'changed');
 // A stationary page should still report an unchanged action.
 await f.set({label:'Settings'});
 assert.equal(value(await f.call('tap_text',{text:'Settings'})).screen_change,'unchanged');
});

test('a different app in front counts as a change even when its tree has not arrived', { timeout: 30000 }, async t => {
 const f=await fixture(t);await f.set({launched:true,afterInput:{foregroundPid:999}});
 const receipt=value(await f.call('tap',{x:10,y:10}));
 assert.equal(receipt.screen_change,'changed',JSON.stringify(receipt));
});

test('a screen says when its read began and how old it is', { timeout: 30000 }, async t => {
 const f=await fixture(t);
 const receipt=value(await f.call('tap',{x:10,y:10}));
 assert.ok(!Number.isNaN(Date.parse(receipt.screen.observed_at)),JSON.stringify(receipt.screen));
 assert.ok(receipt.screen.tree_age_ms>=0);
});

test('launch_app gives the app a moment to come to the front and says how long it took', { timeout: 30000 }, async t => {
 const f=await fixture(t);await f.set({foregroundLagReads:6});
 const result=await f.call('launch_app',{bundle_id:'local.fixture'});
 assert.notEqual(result.isError,true,result.content[0].text);
 const launched=value(result);
 assert.equal(launched.foreground_verified,true);assert.ok(launched.foreground_after_ms>0);
});

test('the Home Screen is named com.apple.springboard, and later reads of it say so too', async () => {
 const devices=new Devices(),id='fixture-phone';
 devices.target=async()=>({id,kind:'physical',name:'Phone'});devices.size={device:id,width:100,height:200};
 devices.bridge=async request=>request.op==='ax'?{foreground:{object_id:'o1',name:' ',bundle_id:null,pid:34},elements:[{label:'Phone',role:'Icon',frame:{x:10,y:10,width:40,height:40}}]}:{pid:34,running:true,executable:'/System/Library/CoreServices/SpringBoard.app/SpringBoard',bundle_id:null,name:null};
 const front=JSON.parse((await devices.dispatch('get_foreground_app',{})).content[0].text);
 assert.equal(front.bundle_id,'com.apple.springboard');assert.equal(front.bundle_id_source,'executable');
 assert.equal((await devices.structure()).foreground.bundle_id,'com.apple.springboard');
});

test('the status shows the commit recorded at build time when git is not there', { timeout: 30000 }, async t => {
 const f=await fixture(t,{beforeStart:dir=>writeFile(join(dir,'build/commit'),'abc1234\n')});
 assert.equal(value(await f.call('poki_mcp_status')).commit,'abc1234');
});
