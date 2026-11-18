import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { fixture, value } from './fixture.mjs';

const DEFAULT_TOOLS = [
  'do',
  'list_apps',
  'list_devices',
  'look',
  'poki_mcp_status',
  'select_device',
];

const textOf = result => result.content.find(item => item.type === 'text')?.text ?? '';

test('default MCP profile exposes only the slim phone-agent toolset and guides callers away from legacy tools', { timeout: 30000 }, async t => {
  const f = await fixture(t);
  const endpoint = JSON.parse(await readFile(join(f.dir, 'state/mcp.json'), 'utf8'));
  const httpClient = new Client({ name: 'slim-http-check', version: '1' });
  t.after(() => httpClient.close());
  await httpClient.connect(new StreamableHTTPClientTransport(new URL(endpoint.url), {
    requestInit: { headers: { Authorization: `Bearer ${endpoint.token}`, 'x-poki-mcp-session': 'slim-http-check' } },
  }));

  for (const client of [f.a, httpClient]) {
    const listed = (await client.listTools()).tools.map(tool => tool.name).sort();
    assert.deepEqual(listed, DEFAULT_TOOLS);
  }

  const looked = await f.call('look', {});
  assert.equal(looked.isError ?? false, false, textOf(looked));
  assert.match(textOf(looked), /1 Button "First"/);
  assert.equal(looked.content.some(item => item.type === 'image'), true);

  const acted = await f.call('do', {
    actions: [
      { double_tap: 1 },
      { back: true },
    ],
    finish: true,
  });
  assert.equal(acted.isError ?? false, false, textOf(acted));
  assert.match(textOf(acted), /did: double_tap 1 \(sent/);
  assert.match(textOf(acted), /did: back \(sent/);
  assert.match(textOf(acted), /finish:/);

  await f.set({ dialogAnswer: 'done' });
  const beforeEvents = (await f.events()).length;
  const approvedUrl = await f.call('do', {
    actions: [{ open_url: 'https://example.invalid' }],
  });
  assert.equal(approvedUrl.isError ?? false, false, textOf(approvedUrl));
  assert.match(textOf(approvedUrl), /did: open_url https:\/\/example\.invalid \(sent/);
  const recentEvents = (await f.events()).slice(beforeEvents);
  assert.equal(recentEvents.some(event => event.dialog === true), true, 'sensitive do action should require local approval');

  for (const [legacy, expectedHint] of [
    ['tap', /\bdo\b[\s\S]*actions[\s\S]*tap/],
    ['double_tap', /\bdo\b[\s\S]*double_tap/],
    ['type_text', /\bdo\b[\s\S]*type/],
    ['press_button', /\bdo\b[\s\S]*button/],
    ['open_url', /\bdo\b[\s\S]*open_url/],
    ['take_screenshot', /\blook\b/],
    ['batch_commands', /\bdo\b[\s\S]*actions/],
    ['start_simulator', /(--dev-tools|POKI_MCP_DEV_TOOLS)/],
    ['start_recording', /(--dev-tools|POKI_MCP_DEV_TOOLS)/],
    ['list_crashes', /(--dev-tools|POKI_MCP_DEV_TOOLS)/],
  ]) {
    const rejected = await f.call(legacy, {});
    assert.equal(rejected.isError, true, `${legacy} should be rejected in default mode`);
    assert.match(textOf(rejected), expectedHint, `${legacy} error should explain replacement or switch`);
  }
});

test('enabling the developer tool group via POKI_MCP_DEV_TOOLS=1 or --dev-tools restores all legacy and developer tools', { timeout: 30000 }, async t => {
  const f = await fixture(t);

  const envTransport = new StdioClientTransport({
    command: process.execPath,
    args: [join(f.dir, 'src/stdio.mjs')],
    env: { ...f.env, POKI_MCP_DEV_TOOLS: '1' },
  });
  const envClient = new Client({ name: 'dev-env-client', version: '1' });
  t.after(() => envClient.close());
  await envClient.connect(envTransport);

  const flagTransport = new StdioClientTransport({
    command: process.execPath,
    args: [join(f.dir, 'src/stdio.mjs'), '--dev-tools'],
    env: f.env,
  });
  const flagClient = new Client({ name: 'dev-flag-client', version: '1' });
  t.after(() => flagClient.close());
  await flagClient.connect(flagTransport);

  const daemonFlagFixture = await fixture(t, { daemonArgs: ['--dev-tools'] });

  for (const client of [envClient, flagClient, daemonFlagFixture.a]) {
    const { tools } = await client.listTools();
    assert.equal(tools.length, 63);
    for (const expected of [
      'tap', 'double_tap', 'long_press', 'swipe', 'type_text', 'fill', 'press_button',
      'take_screenshot', 'batch_commands', 'start_simulator', 'start_recording', 'stop_recording',
      'build_and_run', 'set_location', 'set_appearance', 'set_accessibility', 'list_crashes',
      'touch_path', 'run_code', 'acquire_device', 'look', 'do',
    ]) {
      assert.equal(tools.some(tool => tool.name === expected), true, `missing ${expected}`);
    }
  }

  const screen = value(await envClient.callTool({ name: 'list_elements', arguments: {} }));
  const tapped = await envClient.callTool({ name: 'tap', arguments: { ref: screen.elements[0].ref } });
  assert.equal(tapped.isError ?? false, false, textOf(tapped));

  const recStarted = value(await flagClient.callTool({ name: 'start_recording', arguments: {} }));
  assert.equal(recStarted.recording, true);
  const recStopped = value(await flagClient.callTool({ name: 'stop_recording', arguments: {} }));
  assert.equal(typeof recStopped.path, 'string');

  const lease = value(await flagClient.callTool({ name: 'acquire_device', arguments: { device: 'fixture-phone' } }));
  assert.equal(lease.state, 'active');
  const released = value(await flagClient.callTool({ name: 'release_device', arguments: { lease_id: lease.lease_id } }));
  assert.equal(released.stopped, true);
});
