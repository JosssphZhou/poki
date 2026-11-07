import test from 'node:test';
import assert from 'node:assert/strict';
process.env.POKI_IPHONE_PASSCODE = '000000'; // Synthetic test credential.
const { Devices } = await import('../src/device.mjs');

function device(id) {
 const d = new Devices();
 const digits = [{x:215,y:695}, ...Array.from({length:9}, (_,i)=>({x:103+i%3*112,y:371+Math.floor(i/3)*108}))];
 d.target = async () => ({id,kind:'physical'});
 d.frame = {id:'frame',device:id,at:Date.now(),revision:0,width:430,height:932};
 d.bridge = async r => r.op === 'process_info' ? {executable:'/System/Library/CoreServices/SpringBoard.app/SpringBoard'} : {foreground:{pid:39},elements:[{label:'输入密码'},{role:'TextField',value:'共6位数，已输入0位'},...digits.map((p,i)=>({label:String(i),role:'Key',frame:{x:p.x-40,y:p.y-40,width:80,height:80}}))]};
 let taps=0;d.input=async()=>{taps++;throw Error('000000');};
 d.capture=async()=>{throw Error('No screen');};
 return {d,args:{observation_id:'frame',empty_keypad_confirmed:true,digits},taps:()=>taps};
}
test('uncertain unlock preserves dispatch stop metadata and blocks a second Devices session', async () => {
 const id='unlock-dispatch-test';process.env.POKI_UNLOCK_DEVICE=id;
 const first=device(id), second=device(id);
 const result=await first.d.dispatch('unlock_device',first.args);
 assert.equal(result.isError,true);assert.equal(result._meta.stop_reason,'unknown');assert.equal(first.taps(),1);
 assert.ok(!JSON.stringify(result).includes('000000'));
 await assert.rejects(second.d.dispatch('unlock_device',second.args), /human review/);
 assert.equal(second.taps(),0);
});
test('unlock refuses a recording owned by this or another Devices session before reading or tapping', async () => {
 for (const foreign of [false,true]) {
  const id=`unlock-recording-${foreign}`;process.env.POKI_UNLOCK_DEVICE=id;
  const current=device(id), owner=foreign?new Devices():current.d;
  owner.ownBackground(id,'recording');current.d.peers=()=>[current.d,owner].values();
  current.d.bridge=async()=>{throw Error('Should not read');};
  await assert.rejects(current.d.dispatch('unlock_device',current.args), /Stop recording/);
  assert.equal(current.taps(),0);
 }
});
