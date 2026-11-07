import test from 'node:test';
import assert from 'node:assert/strict';
import { Devices } from '../src/device.mjs';
import { runBatch } from '../src/batch.mjs';

test('uncertain unlock preserves stop metadata and stops even a permissive batch', async () => {
 const oldDevice = process.env.POKI_UNLOCK_DEVICE, oldPin = process.env.POKI_IPHONE_PASSCODE;
 process.env.POKI_UNLOCK_DEVICE = 'unlock-dispatch-test'; process.env.POKI_IPHONE_PASSCODE = '000000';
 try {
  const d = new Devices(), id = process.env.POKI_UNLOCK_DEVICE;
  const digits = [{x:215,y:695}, ...Array.from({length:9}, (_,i)=>({x:103+i%3*112,y:371+Math.floor(i/3)*108}))];
  d.target = async () => ({id,kind:'physical'});
  d.frame = {id:'frame',device:id,at:Date.now(),revision:0,width:430,height:932};
  d.bridge = async r => r.op === 'process_info' ? {executable:'/System/Library/CoreServices/SpringBoard.app/SpringBoard'} : {foreground:{pid:39},elements:[{label:'输入密码'},{role:'TextField',value:'共6位数，已输入0位'},...digits.map((p,i)=>({label:String(i),role:'Key',frame:{x:p.x-40,y:p.y-40,width:80,height:80}}))]};
  let taps=0;d.input=async()=>{taps++;return{sent:false,isError:true};};
  d.capture=async()=>{throw Error('No screen');};
  const args={observation_id:'frame',empty_keypad_confirmed:true,digits};
  const result=await d.dispatch('unlock_device',args);
  assert.equal(result.isError,true);assert.equal(result._meta.stop_reason,'unknown');assert.equal(taps,1);
  let calls=0;
  const batch=await runBatch({dispatch:async()=>{calls++;return result;},readback:async()=>({screen:{}})}, {stop_on_error:false,commands:[{tool:'unlock_device',arguments:args},{tool:'wait',arguments:{seconds:0}}]});
  assert.equal(calls,1);assert.equal(batch.isError,true);
 } finally {
  if(oldDevice===undefined)delete process.env.POKI_UNLOCK_DEVICE;else process.env.POKI_UNLOCK_DEVICE=oldDevice;
  if(oldPin===undefined)delete process.env.POKI_IPHONE_PASSCODE;else process.env.POKI_IPHONE_PASSCODE=oldPin;
 }
});
