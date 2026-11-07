import test from 'node:test';
import assert from 'node:assert/strict';
import { matching, candidatesFor, conditionsMatch } from '../fast/task.mjs';
import { learnReadout, readCurrent } from '../readout.mjs';
import { answerCurrentScreen } from '../answer-current-screen.mjs';
import { PiSession } from '../pi-session.mjs';

// Missing/unknown flags retain their permissive compatibility behavior.
const allowed = [{}, { value: undefined }, { value: null }, { value: true }, { value: 1 },
  { value: 'false' }, { value: '0' }, { value: '' }, { value: 2 }];
const flags = (name, entry) => Object.hasOwn(entry, 'value') ? { [name]: entry.value } : {};
const button = { ref: 'e1', role: 'Button', label: 'Save' };
const selector = { role: 'Button', label: 'Save' };
const task = { allowed: [{ id: 'save', op: 'tap', ...selector }] };

test('Native false flags exclude targets and conditions; unknown flags keep compatibility', () => {
  for (const name of ['visible', 'enabled']) {
    for (const value of [false, 0]) {
      const elements = [{ ...button, [name]: value }];
      assert.equal(matching(elements, selector).length, 0, `${name}=${value}`);
      assert.equal(candidatesFor(task, { elements }).length, 0);
      assert.equal(conditionsMatch([selector], { elements }), false);
    }
    for (const entry of allowed) {
      const elements = [{ ...button, ...flags(name, entry) }];
      assert.equal(candidatesFor(task, { elements }).length, 1);
      assert.equal(conditionsMatch([selector], { elements }), true);
    }
  }
});

test('Unavailable duplicate targets do not create ambiguity; two available targets still do', () => {
  for (const name of ['visible', 'enabled']) for (const value of [false, 0]) {
    const elements = [button, { ...button, ref: 'e2', [name]: value }];
    assert.equal(candidatesFor(task, { elements })[0].ref, 'e1');
    assert.equal(conditionsMatch([selector], { elements }), true);
  }
  assert.throws(() => candidatesFor(task, { elements: [button, { ...button, ref: 'e2' }] }), /ambiguous_target/);
  assert.equal(conditionsMatch([selector], { elements: [button, { ...button, ref: 'e2' }] }), false);
});

const field = { ref: 'e1', role: 'TextField', label: 'Capacity', value: '90%' };
const fieldAnswer = { kind: 'field', items: [{ ref: 'e1', field: 'value' }] };
test('Learned fields reject unavailable values and preserve uniqueness and unknown flags', () => {
  const readout = learnReadout(fieldAnswer, { elements: [field] });
  for (const name of ['visible', 'enabled']) {
    for (const value of [false, 0]) {
      const unavailable = { ...field, [name]: value };
      assert.equal(learnReadout(fieldAnswer, { elements: [unavailable] }), null);
      assert.equal(readCurrent(readout, { elements: [unavailable] }), null);
      assert.equal(readCurrent(readout, { elements: [field, { ...unavailable, ref: 'e2' }] }).details[0].value, '90%');
    }
    for (const entry of allowed) {
      const elements = [{ ...field, ...flags(name, entry) }];
      assert.ok(learnReadout(fieldAnswer, { elements }));
      assert.equal(readCurrent(readout, { elements }).details[0].value, '90%');
    }
  }
  assert.equal(readCurrent(readout, { elements: [field, { ...field, ref: 'e2' }] }), null);
});

const start = { ref: 'e1', role: 'Heading', label: 'Events' };
const row = { ref: 'e2', role: 'StaticText', label: '09:00 Synthetic event' };
const end = { ref: 'e3', role: 'Heading', label: 'End' };
const listAnswer = { kind: 'list', start_ref: 'e1', end_ref: 'e3', items: [{ ref: 'e2', field: 'label' }] };
test('Learned lists exclude unavailable rows in learning and current answers', () => {
  const readout = learnReadout(listAnswer, { elements: [start, row, end] });
  for (const name of ['visible', 'enabled']) {
    for (const value of [false, 0]) {
      const unavailable = { ...row, [name]: value };
      assert.deepEqual(learnReadout(listAnswer, { elements: [start, unavailable, end] }), { kind: 'list' });
      assert.equal(readCurrent(readout, { elements: [start, unavailable, end] }), null);
      const elements = [start, row, { ...unavailable, ref: 'e4' }, end];
      assert.deepEqual(learnReadout(listAnswer, { elements }), readout);
      assert.deepEqual(readCurrent(readout, { elements }).details, [{ label: 'Events', value: row.label }]);
      for (const boundary of [0, 2]) {
        const bounded = [start, row, end].map((e, i) => i === boundary ? { ...e, [name]: value } : e);
        assert.deepEqual(learnReadout(listAnswer, { elements: bounded }), { kind: 'list' });
        assert.equal(readCurrent(readout, { elements: bounded }), null);
      }
    }
    for (const entry of allowed) {
      const elements = [start, { ...row, ...flags(name, entry) }, end];
      assert.deepEqual(learnReadout(listAnswer, { elements }), readout);
      assert.equal(readCurrent(readout, { elements }).details[0].value, row.label);
    }
  }
});

test('Current-screen fallback applies the same visibility semantics to selected refs', async t => {
  t.mock.method(PiSession.prototype, 'open', async () => {});
  t.mock.method(PiSession.prototype, 'close', () => {});
  t.mock.method(PiSession.prototype, 'request', async function (method) {
    if (method === 'thread/start') return { thread: { id: 'fixture' } };
    this.emit('response', {});
    this.emit('message', { method: 'item/completed', params: { item: { type: 'agentMessage', text: JSON.stringify({ complete: true, items: [{ ref: 'e2', field: 'label' }] }) } } });
    this.emit('message', { method: 'turn/completed', params: { turn: { status: 'completed' } } });
    return {};
  });
  const answer = elements => answerCurrentScreen({ prompt: 'Read the event.', observation: { elements }, modelConfig: { auth: 'api-key', model: 'fixture' } });
  for (const value of [false, 0]) {
    const unavailable = { ...row, visible: value };
    assert.equal((await answer([unavailable])).success, false);
    assert.equal((await answer([row, unavailable])).success, true);
  }
  assert.equal((await answer([row, { ...row }])).success, false);
  for (const entry of allowed) assert.equal((await answer([{ ...row, ...flags('visible', entry) }])).success, true);
  // This consumer historically checks visibility only, not actionability.
  assert.equal((await answer([{ ...row, enabled: false }])).success, true);
});
