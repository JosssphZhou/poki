import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fixture } from './fixture.mjs';

test('Remote screen capture survives client and daemon restarts after the phone stops accepting new connections', async t => {
  const f = await fixture(t, { beforeStart: async dir => {
    await mkdir(join(dir, 'state'));
    await writeFile(join(dir, 'state/remote-devices.json'), JSON.stringify([{ id: 'remote-phone', config_path: join(dir, 'remote.json') }]));
    await writeFile(join(dir, 'build/poki-native'), `#!/usr/bin/env node
import { createInterface } from 'node:readline';
import { createServer } from 'node:net';
import { copyFileSync, existsSync, writeFileSync } from 'node:fs';
const gate = process.env.FIXTURE_STATE + '.connected';
if (process.argv[2] !== '--remote-server' || existsSync(gate)) process.exit(1);
writeFileSync(gate, 'new connections refused');
writeFileSync(process.env.FIXTURE_STATE + '.pid', String(process.pid));
const server = createServer(socket => {
  socket.write(JSON.stringify({pid:process.pid})+'\\n');
  createInterface({input:socket}).once('line', line => {
    const request = JSON.parse(line);
    let response;
    if (request.op === 'screenshot') { copyFileSync(process.env.FIXTURE_IMAGE, request.path); response={saved:true}; }
    else if (request.op === 'device_info') response={scale:1,properties:{}};
    else if (request.op === 'disconnect') { response={disconnected:true}; server.close(); }
    else response={isError:true,error:'Unsupported fixture request'};
    socket.end(JSON.stringify(response)+'\\n');
  });
});
server.listen(process.argv[4], () => console.log(JSON.stringify({ready:true})));
`, { mode: 0o755 });
  }});
  t.after(async () => {
    const pid = Number(await readFile(join(f.dir, 'fixture.json.pid'), 'utf8').catch(() => ''));
    if (pid > 1) { try { process.kill(pid, 'SIGTERM'); } catch {} }
  });
  const args = { device: 'remote-phone' };
  const first = await f.call('take_screenshot', args);
  assert.ok(!first.isError, JSON.stringify(first));
  assert.ok(first.content.some(c => c.type === 'image'));
  await f.a.close();
  await f.daemon.stop();
  await f.startDaemon();
  const secondClient = await f.connect();
  const second = await secondClient.callTool({ name: 'take_screenshot', arguments: args });
  assert.ok(!second.isError, JSON.stringify(second));
  assert.ok(second.content.some(c => c.type === 'image'));
  const closed = await secondClient.callTool({ name: 'disconnect_device', arguments: args });
  assert.ok(!closed.isError, JSON.stringify(closed));
});
