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

test('default discovery follows daemon binding for HTTP and stdio, including after restart', async t => {
 const { Client, StreamableHTTPClientTransport } = await import('@modelcontextprotocol/client');
 const { readFile } = await import('node:fs/promises');
 const { join } = await import('node:path');
 const daemonEnv={POKI_UNLOCK_DEVICE:'fixture-phone'};
 const f=await fixture(t,{daemonEnv});
 assert.equal(f.env.POKI_UNLOCK_DEVICE,undefined,'The stdio client has no device binding');
 assert.ok((await f.a.listTools()).tools.some(x=>x.name==='unlock_device'));
 const endpoint=JSON.parse(await readFile(join(f.dir,'state/mcp.json'),'utf8'));
 const client=new Client({name:'unlock-discovery',version:'1'});
 try {
  await client.connect(new StreamableHTTPClientTransport(new URL(endpoint.url),{requestInit:{headers:{Authorization:`Bearer ${endpoint.token}`,'x-poki-mcp-session':'unlock-discovery'}}}));
  assert.ok((await client.listTools()).tools.some(x=>x.name==='unlock_device'));
 } finally {await client.close();}
 const args={observation_id:'none',empty_keypad_confirmed:true,digits:Array.from({length:10},()=>({x:10,y:50}))};
 assert.match((await f.call('unlock_device',args)).content[0].text,/Configure a six-digit/);
 await f.daemon.stop();
 const offline=await f.a.listTools();
 assert.equal(offline.tools.length,29);
 assert.ok(!offline.tools.some(x=>x.name==='unlock_device'));
 const stopped=await f.call('wait',{seconds:0});
 assert.equal(stopped.isError,true);assert.match(stopped.content[0].text,/not running/);
 daemonEnv.POKI_UNLOCK_DEVICE='';await f.startDaemon();
 assert.ok(!(await f.a.listTools()).tools.some(x=>x.name==='unlock_device'));
 assert.ok((await (await f.connect('all')).listTools()).tools.some(x=>x.name==='unlock_device'));
});

test('daemon retains its configured secret but execute and native helper children do not inherit it', async t => {
 const { readFile,writeFile }=await import('node:fs/promises');
 const { join }=await import('node:path');
 const f=await fixture(t,{daemonEnv:{POKI_UNLOCK_DEVICE:'fixture-phone',POKI_IPHONE_PASSCODE:'102938'},beforeStart:async dir=>{
  for(const path of ['bin/python3','build/poki-native']) {
   const file=join(dir,path),source=await readFile(file,'utf8');
   await writeFile(file,source.replace("const args=process.argv.slice(2)","if(Object.hasOwn(process.env,'POKI_IPHONE_PASSCODE'))throw Error('Secret inherited by child');\nconst args=process.argv.slice(2)"));
  }
 }});
 const result=await f.call('list_elements');assert.ok(!result.isError,JSON.stringify(result));
 const events=await f.events();assert.ok(events.some(e=>e.tool==='python3'));assert.ok(events.some(e=>e.tool==='poki-native'&&e.args?.includes('--local-server')));
 const refused=await f.call('unlock_device',{observation_id:'stale',empty_keypad_confirmed:true,digits:Array.from({length:10},()=>({x:10,y:50}))});
 assert.match(refused.content[0].text,/fresh screenshot/,'The secret remains configured after its environment entry is removed');
 assert.ok(!JSON.stringify(refused).includes('102938'));
});
