import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker, {telegramSchedule} from './worker.mjs';

const at=Date.parse('2026-10-09T12:00:00+08:00'), group='-1004201042022';
async function fixture(fn) {
  const clock=Date.now, network=globalThis.fetch;
  Date.now=()=>at;
  const raw=new DatabaseSync(':memory:');
  raw.exec('CREATE TABLE bot_state(key TEXT PRIMARY KEY,value TEXT NOT NULL,expires INTEGER NOT NULL)');
  const DB={prepare(sql) {let args=[]; return {bind(...v){args=v;return this;},async first(){return raw.prepare(sql).get(...args);},async all(){return {results:raw.prepare(sql).all(...args)};},async run(){return raw.prepare(sql).run(...args);}};}};
  const calls=[],prompts=[];
  const f={raw,env:{DB,BOT_TOKEN:'test-token',WEBHOOK_SECRET:'test-secret',GROUP_ID:group,AI:{async run(model,input){prompts.push(input);return {response:'1. 小明（U1）：【Bug反馈】导入 👉 后续测试仍失败，待排查。'};}}},calls,prompts,isAdmin:false,failSend:false};
  globalThis.fetch=async (url,options)=>{
    const method=String(url).split('/').at(-1),body=JSON.parse(options.body);calls.push({method,body});
    if(method==='getChatMember') return Response.json({ok:true,result:{status:f.isAdmin?'administrator':'member'}});
    if(method==='sendMessage') return Response.json({ok:!f.failSend,result:{message_id:20}});
    throw new Error('Unexpected network request');
  };
  f.message=(id,text,changes={})=>({update_id:id,message:{message_id:id,date:at/1000-60,chat:{id:Number(group)},from:{id:123,first_name:'小明',is_bot:false},text,...changes}});
  f.receive=async (update,secret='test-secret')=>worker.fetch(new Request('https://example.test/webhook',{method:'POST',headers:{'X-Telegram-Bot-Api-Secret-Token':secret},body:JSON.stringify(update)}),f.env);
  f.store=(key,value,expires=at/1000+86400)=>raw.prepare('INSERT OR REPLACE INTO bot_state VALUES(?,?,?)').run(key,JSON.stringify(value),expires);
  try {await fn(f);} finally {globalThis.fetch=network;Date.now=clock;raw.close();}
}

test('Telegram archives only authenticated bound-group human text, redacts contacts, retains reply links for 24h',async()=>fixture(async f=>{
  assert.equal((await f.receive(f.message(1,'Private forged text'),'wrong')).status,401);
  await f.receive(f.message(2,'Other group',{chat:{id:-123}}));
  await f.receive(f.message(3,'Robot text',{from:{id:456,is_bot:true}}));
  await f.receive(f.message(4,undefined,{caption:'Attachment caption',photo:[{}]}));
  await f.receive(f.message(5,'默读导入失败 token=private-key，联系 a@example.test'));
  await f.receive(f.message(6,'重新测试还是失败',{reply_to_message:{message_id:5,from:{id:123,is_bot:false},text:'默读导入失败'}}));
  await f.receive(f.message(6,'重复投递'));
  const rows=f.raw.prepare("SELECT value,expires FROM bot_state WHERE key LIKE 'tg:chat:%' ORDER BY key").all();
  assert.equal(rows.length,2);assert.equal(rows[0].expires,at/1000+86400);
  assert.doesNotMatch(JSON.stringify(rows),/private-key|a@example|123|重复投递/);
  const first=JSON.parse(rows[0].value),second=JSON.parse(rows[1].value);
  assert.equal(first.speaker.name,'小明');assert.equal(first.speaker.key,second.speaker.key);
  assert.equal(first.messageKey,second.replyTo);assert.equal(f.calls.filter(c=>c.method==='sendMessage').length,0);
}));

test('Telegram noon digest includes 23-hour feedback, excludes other platforms and expired records, and deduplicates',async()=>fixture(async f=>{
  f.store(`tg:started:${group}`,{at:at/1000-86400});
  f.store(`tg:chat:${group}:1`,{ts:at/1000-23*3600,text:'默读导入失败',speaker:{key:'one',name:'小明'}});
  f.store(`tg:chat:${group}:2`,{ts:at/1000-60,text:'重新测试还是失败',speaker:{key:'one',name:'小明'}});
  f.store(`tg:chat:${group}:expired`,{ts:at/1000-90,text:'Expired text'},at/1000);
  f.store('qq:chat:qq-group:1',{ts:at/1000-30,text:'QQ private text'});
  f.store('tg:chat:other-group:1',{ts:at/1000-30,text:'Other private text'});
  for(const hours of [-4,8,-1]) await telegramSchedule({scheduledTime:at+hours*3600000},f.env);
  assert.equal(f.prompts.length,0);
  await telegramSchedule({scheduledTime:at},f.env);await telegramSchedule({scheduledTime:at},f.env);
  assert.equal(f.prompts.length,2);
  assert.match(f.prompts[0].messages[1].content,/默读导入失败[\s\S]*重新测试还是失败/);
  assert.doesNotMatch(f.prompts[0].messages[1].content,/QQ private|Other private|Expired text/);
  const sent=f.calls.filter(c=>c.method==='sendMessage');assert.equal(sent.length,1);
  assert.equal(sent[0].body.chat_id,group);assert.equal(sent[0].body.reply_parameters,undefined);
  assert.match(sent[0].body.text,/2026-10-08 12:00 — 2026-10-09 12:00/);assert.doesNotMatch(sent[0].body.text,/U1/);
}));

test('QQ scheduling failure does not stop Telegram summary or expired-text cleanup',async()=>fixture(async f=>{
  f.env.QQ_GROUP_OPENID='qq-group';f.env.QQ_APP_SECRET='test-secret';
  f.store('qq:push-permission','invalid-json');f.raw.prepare("UPDATE bot_state SET value='invalid-json' WHERE key='qq:push-permission'").run();
  f.store(`tg:chat:${group}:expired`,{ts:at/1000-86401,text:'Old text'},at/1000-1);
  await worker.scheduled({scheduledTime:at},f.env);
  assert.equal(f.calls.filter(c=>c.method==='sendMessage').length,1);
  assert.equal(f.prompts.length,0);
  assert.equal(f.raw.prepare("SELECT COUNT(*) n FROM bot_state WHERE key LIKE 'tg:chat:%'").get().n,0);
}));

test('ambiguous Telegram send is marked failed without retrying or blocking QQ gate',async()=>fixture(async f=>{
  f.failSend=true;
  await telegramSchedule({scheduledTime:at},f.env);await telegramSchedule({scheduledTime:at},f.env);
  assert.equal(f.calls.filter(c=>c.method==='sendMessage').length,1);
  assert.equal(JSON.parse(f.raw.prepare("SELECT value FROM bot_state WHERE key='tg:last-summary'").get().value).ok,false);
  assert.equal(f.raw.prepare("SELECT COUNT(*) n FROM bot_state WHERE key LIKE 'qq:summary:%'").get().n,0);
}));

test('manual Telegram digest requires administrator and excludes its own diagnostic command',async()=>fixture(async f=>{
  await f.receive(f.message(10,'/summary-test@ModuReaderRelease_bot 24h'));
  assert.equal(f.calls.filter(c=>c.method==='sendMessage').length,0);
  f.isAdmin=true;
  await f.receive(f.message(11,'默读导入失败'));
  await f.receive(f.message(12,'/summary-test@ModuReaderRelease_bot 24h'));
  assert.equal(f.prompts.length,2);
  assert.doesNotMatch(f.prompts[0].messages[1].content,/summary-test/);
  assert.match(f.calls.find(c=>c.method==='sendMessage').body.text,/过去24小时反馈汇总测试/);
  assert.equal(f.raw.prepare("SELECT COUNT(*) n FROM bot_state WHERE key LIKE 'tg:summary:-%'").get().n,0);
}));

test('diagnostic-only Telegram period does not call AI or invent feedback',async()=>fixture(async f=>{
  f.store(`tg:chat:${group}:1`,{ts:at/1000-30,text:'/help@ModuReaderRelease_bot'});
  await telegramSchedule({scheduledTime:at},f.env);
  assert.equal(f.prompts.length,0);
  assert.match(f.calls.find(c=>c.method==='sendMessage').body.text,/没有可供汇总的聊天文字/);
}));
