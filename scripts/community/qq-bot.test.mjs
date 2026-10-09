import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {webcrypto} from 'node:crypto';
import {qqKeys, qqVerify, qqRedact, qqSplit, qqWindow, qqRoutes, qqSchedule, qqReleaseText, qqReleaseIdentity, qqReadingAnswer, qqDigestTranscript, qqQuestionRoute, qqQuestionText, qqWebAnswer, qqChatAnswer, qqBingResults} from './qq-bot.mjs';

const secret = 'DG5g3B4j9X2KOErG'; // Public test vector in Tencent's official documentation.
const encode = new TextEncoder();
const hex = bytes => Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2,'0')).join('');
const releaseKey = await webcrypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',
  modulusLength:2048, publicExponent:new Uint8Array([1,0,1]), hash:'SHA-256'}, true, ['sign','verify']);
const releaseJwk = {...await webcrypto.subtle.exportKey('jwk', releaseKey.publicKey), kid:'test-oidc-key', alg:'RS256', use:'sig'};
async function identity(changes = {}, headerChanges = {}) {
  const now = Math.floor(Date.now()/1000);
  const claims = {iss:'https://token.actions.githubusercontent.com',
    aud:'https://modureader-bot.2406.fun/qq/release', repository:'sobranie2406/modureader',
    repository_id:'1357833506', repository_owner:'sobranie2406',
    workflow_ref:'sobranie2406/modureader/.github/workflows/qq-release.yml@refs/heads/main',
    event_name:'workflow_dispatch', ref:'refs/heads/main', iat:now, nbf:now-5, exp:now+300, ...changes};
  const parts = [{alg:'RS256',kid:'test-oidc-key',...headerChanges}, claims]
    .map(value => Buffer.from(JSON.stringify(value)).toString('base64url'));
  const signature = await webcrypto.subtle.sign('RSASSA-PKCS1-v1_5', releaseKey.privateKey, encode.encode(parts.join('.')));
  return parts.join('.') + '.' + Buffer.from(signature).toString('base64url');
}
function releaseRequest(token, tag = 'v1.0-beta', testNotice = false) {
  return new Request('https://modureader-bot.2406.fun/qq/release', {method:'POST',
    headers:{authorization:'Bearer '+token}, body:JSON.stringify({release_tag:tag,test_notice:testNotice})});
}

function database() {
  const db = new DatabaseSync(':memory:');
  db.exec('CREATE TABLE bot_state(key TEXT PRIMARY KEY,value TEXT NOT NULL,expires INTEGER NOT NULL)');
  return {raw: db, prepare(sql) {
    let args = [];
    return {bind(...values) {args = values; return this;},
      async first() {return db.prepare(sql).get(...args);},
      async all() {return {results: db.prepare(sql).all(...args)};},
      async run() {return db.prepare(sql).run(...args);}};
  }};
}
function store(db, key, value, at) {
  db.raw.prepare('INSERT OR REPLACE INTO bot_state VALUES(?,?,?)').run(key, JSON.stringify(value), at + 86400*365);
}
async function signed(payload, appId = 'test-app') {
  const raw = JSON.stringify(payload);
  const timestamp = String(Math.floor(Date.now()/1000));
  const signature = hex(await webcrypto.subtle.sign('Ed25519', (await qqKeys(secret)).privateKey,
    encode.encode(timestamp + raw)));
  return new Request('https://example.test/qq/webhook', {method: 'POST', body: raw,
    headers: {'X-Bot-Appid': appId, 'X-Signature-Timestamp': timestamp, 'X-Signature-Ed25519': signature}});
}
function fixture() {
  const DB = database();
  const sent = [];
  const prompts = [];
  const network = [];
  const env = {DB, QQ_APP_ID: 'test-app', QQ_APP_SECRET: secret, QQ_GROUP_OPENID: 'allowed-group',
    QQ_SUMMARIES_ENABLED: 'true', QQ_RELEASE_PUSH_ENABLED: 'false',
    AI: {async run(model, input) {
      prompts.push(input);
      return {response: input.messages[0].content.includes('Summarize') ?
        '• 群友讨论了 EPUB 导入，相关问题尚待确认。' : 'Supported formats are documented in the README. https://github.com/sobranie2406/modureader/blob/main/README.md'};
    }}};
  const f = {env, DB, sent, prompts, network, searches: [], searchItems: [], tavilyRequests: [],
    release:{id:123,tag_name:'v1.0-beta',prerelease:true,draft:false,
      published_at:new Date().toISOString(),body:'中文：修复阅读问题。\nEnglish: Fix reader issues.'},
    async fetch(url, options = {}) {
    network.push(String(url));
    if (String(url) === 'https://api.tavily.com/usage') {
      assert.equal(options.headers.authorization, 'Bearer test-tavily-key');
      return f.tavilyUsageResponse || Response.json({account:{current_plan:'Researcher',plan_limit:1000,plan_usage:0}});
    }
    if (String(url) === 'https://api.tavily.com/search') {
      assert.equal(options.headers.authorization, 'Bearer test-tavily-key');
      f.tavilyRequests.push(JSON.parse(options.body));
      return f.tavilyResponse || Response.json({results:f.searchItems});
    }
    if (String(url) === 'https://api.anysearch.com/v1/search') {
      assert.equal(options.method, 'POST');
      assert.equal(options.headers.authorization, undefined);
      f.searches.push(JSON.parse(options.body).query);
      return f.searchResponse || Response.json({code:0,data:{results:f.searchItems}});
    }
    if (String(url).startsWith('https://www.bing.com/search?')) return f.bingResponse || new Response('<html>No static results</html>');
    if (String(url).includes('/.well-known/jwks')) return Response.json({keys:[releaseJwk]});
    if (String(url).includes('getAppAccessToken')) return Response.json({access_token: 'test-access', expires_in: 3600});
    if (String(url).includes('/messages')) {sent.push(JSON.parse(options.body)); return Response.json({id:'reply-'+sent.length});}
    if (String(url).includes('raw.githubusercontent.com')) return new Response('Public Modu Reader documentation.');
    if (String(url).includes('api.github.com')) return Response.json(f.release);
    throw new Error('Unexpected test network request');
  }};
  return f;
}
async function withFixture(fn) {
  const f = fixture();
  const original = globalThis.fetch;
  globalThis.fetch = f.fetch;
  try {await fn(f);} finally {globalThis.fetch = original; f.DB.raw.close();}
}
function event(id, content, group = 'allowed-group', type = 'GROUP_MESSAGE_CREATE') {
  return {op: 0, t: type, id:'event-'+id, d: {id, group_openid: group, content,
    timestamp: new Date().toISOString(), author: {id:'member-'+id, member_role:'member', bot:false}}};
}

test('Ed25519 challenge matches the official Tencent test vector', async () => {
  const signature = hex(await webcrypto.subtle.sign('Ed25519', (await qqKeys(secret)).privateKey,
    encode.encode('1725442341Arq0D5A61EgUu4OxUvOp')));
  assert.equal(signature, '87befc99c42c651b3aac0278e71ada338433ae26fcb24307bdc5ad38c1adc2d01bcfcadc0842edac85e85205028a1132afe09280305f13aa6909ffc2d652c706');
  assert.equal(await qqVerify(secret, '1725442341', 'Arq0D5A61EgUu4OxUvOp', signature, 1725442341), true);
  assert.equal(await qqVerify(secret, '1725442341', 'changed', signature, 1725442341), false);
  assert.equal(await qqVerify(secret, '1725442341', 'Arq0D5A61EgUu4OxUvOp', signature, 1725443000), false);
  assert.equal(await qqVerify('different-secret', '1725442341', 'Arq0D5A61EgUu4OxUvOp', signature, 1725442341), false);
});

test('rejects forged callbacks and another application before archiving messages', async () => {
  await withFixture(async f => {
    const forged = new Request('https://example.test/qq/webhook', {method:'POST', body:JSON.stringify(event('1','text')),
      headers:{'X-Bot-Appid':'test-app'}});
    assert.equal((await qqRoutes(forged, f.env)).status, 401);
    assert.equal((await qqRoutes(await signed(event('2','text'), 'wrong-app'), f.env)).status, 401);
    assert.equal(f.DB.raw.prepare('SELECT COUNT(*) n FROM bot_state').get().n, 0);
  });
});

test('accepts URL validation and returns a verifiable challenge signature', async () => {
  await withFixture(async f => {
    const at = String(Math.floor(Date.now()/1000));
    const request = new Request('https://example.test/qq/webhook', {method:'POST',
      headers:{'X-Bot-Appid':'test-app'}, body:JSON.stringify({op:13,d:{plain_token:'validation',event_ts:at}})});
    const body = await (await qqRoutes(request, f.env)).json();
    assert.equal(body.plain_token, 'validation');
    assert.equal(await qqVerify(secret, at, 'validation', body.signature), true);
  });
});

test('full mode archives only the bound group and leaves ordinary conversation unanswered', async () => {
  await withFixture(async f => {
    await qqRoutes(await signed(event('3','无关群的内容', 'other-group')), f.env);
    assert.equal(f.DB.raw.prepare("SELECT COUNT(*) n FROM bot_state WHERE key LIKE 'qq:chat:%'").get().n, 0);
    await qqRoutes(await signed(event('4','讨论 EPUB，联系 a@example.test，token=private-test-key，QQ号：123456789，微信：private_wechat，phone: +1 (555) 123-4567')), f.env);
    const row = f.DB.raw.prepare("SELECT value FROM bot_state WHERE key LIKE 'qq:chat:%'").get();
    assert.match(row.value, /讨论 EPUB/);
    assert.doesNotMatch(row.value, /a@example.test|private-test-key|123456789|private_wechat|555/);
    assert.equal(f.sent.length, 0);
    assert.equal(f.prompts.length, 0);
  });
});

test('an explicit question is answered once even when QQ redelivers it', async () => {
  await withFixture(async f => {
    const payload = event('5', '/ask What formats does Modu support?');
    const response = await qqRoutes(await signed(payload), f.env);
    assert.deepEqual(await response.json(), {op:12});
    await qqRoutes(await signed(payload), f.env);
    assert.equal(f.prompts.length, 1);
    assert.equal(f.sent.length, 1);
    assert.equal(f.sent[0].msg_id, '5');
    assert.equal(f.sent[0].msg_seq, 1);
    assert.match(f.sent[0].content, /README.md/);
  });
});

test('Beijing noon boundaries cover the previous 24 hours exactly', () => {
  for (const time of ['2026-10-07T12:00:00+08:00','2026-10-07T20:00:00+08:00','2026-10-08T11:59:59+08:00'])
    assert.deepEqual(qqWindow(Date.parse(time)),
      {start:Date.parse('2026-10-06T12:00:00+08:00')/1000, end:Date.parse('2026-10-07T12:00:00+08:00')/1000});
  assert.deepEqual(qqWindow(Date.parse('2026-10-08T12:00:00+08:00')),
    {start:Date.parse('2026-10-07T12:00:00+08:00')/1000, end:Date.parse('2026-10-08T12:00:00+08:00')/1000});
});

test('summary cron filters the interval, redacts text, sends proactively and deduplicates', async () => {
  const originalNow = Date.now;
  const at = Date.parse('2026-10-07T12:00:00+08:00');
  Date.now = () => at;
  try {
    await withFixture(async f => {
      const seconds = at/1000;
      store(f.DB, 'qq:started', {at:seconds-86400}, seconds);
      store(f.DB, 'qq:push-permission', {allowed:true,tested:true}, seconds);
      store(f.DB, 'qq:chat:allowed-group:inside', {ts:seconds-60,text:qqRedact('EPUB 导入讨论 token=test-secret')}, seconds);
      store(f.DB, 'qq:chat:allowed-group:before', {ts:seconds-86401,text:'Outside retained context'}, seconds);
      store(f.DB, 'qq:chat:allowed-group:end', {ts:seconds,text:'Outside current interval'}, seconds);
      const summarize = f.env.AI.run;
      f.env.AI.run = async (...args) => {
        await summarize(...args);
        return {response:'1. 小明（U1）、用户 U2、群友(U3)、U4：阅读器反馈 👉 小明（U1）报告闪退，用户U2回应仍待确认。'};
      };
      for (const hours of [-4,8,-24+8]) await qqSchedule({scheduledTime:at+hours*3600000}, f.env);
      await qqSchedule({scheduledTime:at-60000}, f.env);
      assert.equal(f.sent.length, 0);
      await qqSchedule({scheduledTime:at}, f.env);
      await qqSchedule({scheduledTime:at}, f.env);
      assert.equal(f.prompts.length, 2);
      assert.match(f.prompts[0].messages[1].content, /EPUB 导入/);
      assert.doesNotMatch(f.prompts[0].messages[1].content, /test-secret|Outside/);
      assert.match(f.sent[0].content, /2026-10-06 12:00 — 2026-10-07 12:00/);
      assert.equal(f.sent[0].msg_id, undefined);
      assert.match(f.sent[0].content, /1\. 小明、群友、群友、群友：阅读器反馈/);
      assert.match(f.sent[0].content, /小明报告闪退，群友回应仍待确认/);
      assert.doesNotMatch(f.sent[0].content, /\bU\d+\b/);
      assert.equal(JSON.parse(f.DB.raw.prepare("SELECT value FROM bot_state WHERE key='qq:last-summary'").get().value).ok, true);
    });
  } finally {Date.now = originalNow;}
});

test('daily feedback digest keeps unmentioned follow-ups in chronological order', async () => {
  const originalNow = Date.now;
  const at = Date.parse('2026-10-09T12:00:00+08:00');
  Date.now = () => at;
  try {
    await withFixture(async f => {
      const end = at/1000, start = end-86400;
      store(f.DB,'qq:started',{at:end-86400},end);
      store(f.DB,'qq:push-permission',{allowed:true,tested:true},end);
      store(f.DB,'qq:chat:allowed-group:context',{ts:start+30,text:'默读在 WiFi 下朗读无声，Android 15。',speaker:{key:'one',name:'甲'}},end);
      store(f.DB,'qq:chat:allowed-group:interleaved',{ts:start+60,text:'今天港股下跌',speaker:{key:'two',name:'乙'}},end);
      store(f.DB,'qq:chat:allowed-group:followup',{ts:start+120,text:'重启后还是不行，切换流量就正常了。',speaker:{key:'one',name:'甲'}},end);
      store(f.DB,'qq:chat:allowed-group:resolved',{ts:start+180,text:'换了家里的网络就好了，暂时怀疑单位网络。',speaker:{key:'one',name:'甲'}},end);
      store(f.DB,'qq:chat:other-group:secret',{ts:start-30,text:'Other group private text'},end);
      store(f.DB,'qq:chat:allowed-group:expired',{ts:start-20,text:'Expired private text'},end);
      f.DB.raw.prepare('UPDATE bot_state SET expires=? WHERE key=?').run(end,'qq:chat:allowed-group:expired');
      await qqSchedule({scheduledTime:at},f.env);
      const input = f.prompts[0].messages[1].content;
      const sections = input.split('【本时段新消息，汇总对象】\n');
      const background = sections[0].split('\n').filter(line=>line.startsWith('{')).map(JSON.parse);
      const current = sections[1].split('\n').filter(line=>line.startsWith('{')).map(JSON.parse);
      assert.equal(background.length,0);
      assert.match(current[0].text,/默读在 WiFi/);
      assert.deepEqual(current.slice(1).map(m=>m.text),['今天港股下跌','重启后还是不行，切换流量就正常了。','换了家里的网络就好了，暂时怀疑单位网络。']);
      assert.equal(current[0].speaker,current[2].speaker);
      assert.equal(current[2].speaker,current[3].speaker);
      assert.ok(current.every(m=>!m.mentions && !m.replyTo));
      assert.doesNotMatch(input,/Other group|Expired private/);
      assert.match(f.sent[0].content,/^默读反馈汇总/);
    });
  } finally {Date.now=originalNow;}
});

test('a quiet period never republishes previous feedback or calls AI for background alone', async () => {
  const originalNow=Date.now;
  const at=Date.parse('2026-10-09T12:00:00+08:00');
  Date.now=()=>at;
  try {
    await withFixture(async f=>{
      const end=at/1000;
      store(f.DB,'qq:started',{at:end-86400},end);
      store(f.DB,'qq:push-permission',{allowed:true,tested:true},end);
      store(f.DB,'qq:chat:allowed-group:old',{ts:end-86460,text:'默读闪退'},end);
      await qqSchedule({scheduledTime:at},f.env);
      assert.equal(f.prompts.length,0);
      assert.match(f.sent[0].content,/尚未记录到群文字消息/);
      assert.doesNotMatch(f.sent[0].content,/闪退/);
    });
  } finally {Date.now=originalNow;}
});

test('only the source-reviewed digest is posted, never the unchecked draft', async () => {
  await withFixture(async f => {
    const now=Math.floor(Date.now()/1000);
    store(f.DB,'qq:started',{at:now-86400},now);
    store(f.DB,'qq:push-permission',{allowed:true,tested:true},now);
    store(f.DB,'qq:chat:allowed-group:issue',{ts:now-60,text:'默读 iOS 选中文字无法批注'},now);
    let calls=0;
    f.env.AI.run=async (model,input)=> {
      assert.equal(model,'@cf/zai-org/glm-4.7-flash');
      assert.equal(input.chat_template_kwargs.enable_thinking,false);
      if (++calls===1) return {choices:[{message:{content:'1. 群友：【使用意见】无关新闻草稿'}}]};
      assert.match(input.messages[1].content,/无关新闻草稿/);
      assert.match(input.messages[1].content,/默读 iOS 选中文字无法批注/);
      assert.match(input.messages[0].content,/草稿漏掉的事项必须补齐/);
      return {choices:[{message:{content:'1. 群友（U1）：【Bug反馈】文字选择 👉 等待复现。'}}]};
    };
    const admin=event('review-test','/summary-test 24h');
    admin.d.author.member_role='admin';
    await qqRoutes(await signed(admin),f.env);
    assert.equal(calls,0);
    await qqSchedule({scheduledTime:Date.parse('2026-10-09T12:31:00+08:00')},f.env);
    await qqSchedule({scheduledTime:Date.parse('2026-10-09T12:32:00+08:00')},f.env);
    assert.equal(calls,2);
    assert.equal(f.sent.length,1);
    assert.match(f.sent[0].content,/等待复现/);
    assert.doesNotMatch(f.sent[0].content,/无关新闻草稿|U1/);
  });
});

test('24-hour summary test includes retained earlier feedback and excludes expired text', async () => {
  await withFixture(async f => {
    const now=Math.floor(Date.now()/1000);
    store(f.DB,'qq:chat:allowed-group:earlier',{ts:now-23*3600,text:'默读选中文字后无法添加批注'},now);
    store(f.DB,'qq:chat:allowed-group:expired',{ts:now-25*3600,text:'Outside 24-hour interval'},now);
    const member=event('member-summary','/summary-test 24h');
    await qqRoutes(await signed(member),f.env);
    assert.equal(f.sent.length,0);
    const admin=event('admin-summary','/summary-test 24h');
    admin.d.author.member_role='admin';
    await qqRoutes(await signed(admin),f.env);
    assert.equal(f.prompts.length,0);
    await qqSchedule({scheduledTime:Date.parse('2026-10-09T12:31:00+08:00')},f.env);
    const input=f.prompts[0].messages[1].content;
    assert.match(input,/无法添加批注/);
    assert.doesNotMatch(input,/Outside 24-hour/);
    assert.match(f.sent[0].content,/过去24小时反馈汇总测试/);
  });
});

test('no scheduled push happens until proactive permission is actually tested', async () => {
  await withFixture(async f => {
    const seconds = Math.floor(Date.now()/1000);
    store(f.DB, 'qq:started', {at:seconds}, seconds);
    store(f.DB, 'qq:push-permission', {allowed:true,tested:false}, seconds);
    await qqSchedule({scheduledTime:Date.parse('2026-10-07T12:00:00+08:00')}, f.env);
    assert.equal(f.sent.length, 0);
  });
});

test('large summaries sample both the beginning and end of the whole interval', async () => {
  const originalNow = Date.now;
  const at = Date.parse('2026-10-07T12:00:00+08:00');
  Date.now = () => at;
  try {
    await withFixture(async f => {
      const seconds = at/1000;
      store(f.DB, 'qq:started', {at:seconds-86400}, seconds);
      store(f.DB, 'qq:push-permission', {allowed:true,tested:true}, seconds);
      for (let i=0; i<2201; i++) store(f.DB, 'qq:chat:allowed-group:'+i,
        {ts:seconds-43000+i*10,text:i===0 ? 'Early interval topic' : i===2200 ? 'Late interval topic' : 'Reading discussion '+i}, seconds);
      await qqSchedule({scheduledTime:at}, f.env);
      assert.match(f.prompts[0].messages[1].content, /Early interval topic/);
      assert.match(f.prompts[0].messages[1].content, /Late interval topic/);
      assert.ok(f.prompts[0].messages[1].content.length < 32100);
      assert.match(f.sent[0].content, /抽样总结/);
    });
  } finally {Date.now = originalNow;}
});

test('split preserves complete bilingual notes and Unicode; drafts are rejected', () => {
  const text = '中文版本说明\nEnglish release notes 📚\n'.repeat(100);
  const parts = qqSplit(text, 70);
  assert.equal(parts.join(''), text);
  assert.ok(parts.every(p => p.length <= 70 && !/[\uD800-\uDBFF]$/.test(p)));
  const notes = qqReleaseText({tag_name:'v1.0-beta',prerelease:true,body:text});
  assert.match(notes,/预发布版 \/ Prerelease/);
  assert.match(notes,/English release notes/);
  assert.match(notes,/releases\/tag\/v1.0-beta/);
  assert.throws(() => qqReleaseText({draft:true}), /unpublished/);
});

test('public status does not expose identifiers, text or credentials', async () => {
  await withFixture(async f => {
    const response = await qqRoutes(new Request('https://example.test/qq/status'), f.env);
    const text = await response.text();
    assert.doesNotMatch(text, /allowed-group|DG5g3B4j9X2KOErG|test-access/);
    assert.match(text, /12:00 Asia\/Shanghai/);
    assert.match(text, /"release_polling":false/);
  });
});

test('release endpoint rejects wrong repositories, workflows, audiences, events and expired or forged identities', async () => {
  await withFixture(async f => {
    const invalid = [
      {repository:'attacker/modureader'}, {repository_id:'1'}, {repository_owner:'attacker'},
      {aud:'https://another.example/qq/release'}, {iss:'https://attacker.example'},
      {workflow_ref:'sobranie2406/modureader/.github/workflows/other.yml@refs/heads/main'},
      {workflow_ref:'sobranie2406/modureader/.github/workflows/qq-release.yml@refs/heads/untrusted'},
      {event_name:'pull_request'}, {event_name:'push', ref:'refs/heads/main'},
      {exp:Math.floor(Date.now()/1000)-1}, {nbf:Math.floor(Date.now()/1000)+100},
    ];
    for (const claims of invalid) assert.equal((await qqRoutes(releaseRequest(await identity(claims)), f.env)).status, 401);
    assert.equal(await qqReleaseIdentity(await identity({}, {alg:'HS256'})), null);
    const token = await identity();
    const forged = token.split('.');
    forged[1] = Buffer.from(JSON.stringify({aud:'modified'})).toString('base64url');
    assert.equal(await qqReleaseIdentity(forged.join('.')), null);
    const signature = token.split('.');
    const bytes = Buffer.from(signature[2], 'base64url'); bytes[0] ^= 1;
    signature[2] = bytes.toString('base64url');
    assert.equal(await qqReleaseIdentity(signature.join('.')), null);
    assert.equal(f.sent.length, 0);
  });
});

test('release event and reusable build job deliver published bilingual notes once without a passive message ID', async () => {
  await withFixture(async f => {
    f.env.QQ_RELEASE_PUSH_ENABLED = 'true';
    store(f.DB, 'qq:push-permission', {allowed:true,tested:true}, Math.floor(Date.now()/1000));
    const ref = 'refs/tags/v1.0-beta';
    const token = await identity({event_name:'release',ref,
      workflow_ref:'sobranie2406/modureader/.github/workflows/qq-release.yml@'+ref});
    const first = await (await qqRoutes(releaseRequest(token), f.env)).json();
    assert.equal(first.ok, true);
    assert.equal(first.duplicate, false);
    const buildToken = await identity({event_name:'push',ref,
      workflow_ref:'sobranie2406/modureader/.github/workflows/build.yaml@'+ref,
      job_workflow_ref:'sobranie2406/modureader/.github/workflows/qq-release.yml@'+ref});
    const second = await (await qqRoutes(releaseRequest(buildToken), f.env)).json();
    assert.equal(second.duplicate, true);
    assert.equal(f.sent.length, 1);
    assert.match(f.sent[0].content,/预发布版 \/ Prerelease/);
    assert.match(f.sent[0].content,/中文：修复阅读问题/);
    assert.match(f.sent[0].content,/English: Fix reader issues/);
    assert.match(f.sent[0].content,/releases\/tag\/v1.0-beta/);
    assert.equal(f.sent[0].msg_id, undefined);
  });
});

test('release notifications require tested permission and a published matching tag; tests do not suppress the real notice', async () => {
  await withFixture(async f => {
    f.env.QQ_RELEASE_PUSH_ENABLED = 'true';
    const token = await identity();
    assert.equal((await qqRoutes(releaseRequest(token), f.env)).status, 503);
    store(f.DB, 'qq:push-permission', {allowed:true,tested:true}, Math.floor(Date.now()/1000));
    f.release.draft = true;
    assert.equal((await qqRoutes(releaseRequest(token), f.env)).status, 400);
    f.release.draft = false;
    assert.equal((await qqRoutes(releaseRequest(token, 'wrong-tag'), f.env)).status, 400);
    f.release.prerelease = false;
    assert.equal((await qqRoutes(releaseRequest(token, 'v1.0-beta', true), f.env)).status, 200);
    assert.equal((await qqRoutes(releaseRequest(token), f.env)).status, 200);
    assert.equal(f.sent.length, 2);
    assert.match(f.sent[0].content, /发布通知测试/);
    assert.doesNotMatch(f.sent[1].content, /发布通知测试/);
    assert.match(f.sent[1].content, /正式版 \/ Stable/);
  });
});

test('scheduled summaries never poll GitHub for releases, even at five-minute boundaries', async () => {
  await withFixture(async f => {
    f.env.QQ_RELEASE_PUSH_ENABLED = 'true';
    const seconds = Math.floor(Date.now()/1000);
    store(f.DB, 'qq:started', {at:seconds-86400}, seconds);
    store(f.DB, 'qq:push-permission', {allowed:true,tested:true}, seconds);
    for (const time of ['08:05','08:10','20:05'])
      await qqSchedule({scheduledTime:Date.parse('2026-10-07T'+time+':00+08:00')}, f.env);
    assert.equal(f.network.length, 0);
    assert.equal(f.sent.length, 0);
  });
});

test('join answers accept reading expressions, case and full-width input', () => {
  for (const answer of ['阅读器', '想阅读', 'READ', 'Reader', 'reading books', 'Ｒｅａｄｅｒ',
    '我来读书', '看书软件', '電子書', '默讀', 'ModuReader', 'AnxReader', 'e-book', 'ebooks']) {
    assert.equal(qqReadingAnswer({method:'admin_review_qa',review_qa_list:[{question:'用途？',answer}]}), true, answer);
  }
  for (const answer of ['', 'hello', '推广广告', 'thread', 'bread', '读卡器', null, {}]) {
    assert.equal(qqReadingAnswer({method:'verify_message',verify_message:answer}), false);
  }
  assert.equal(qqReadingAnswer({method:'admin_review_qa',review_qa_list:[{question:'阅读器？',answer:'不知道'}]}), false);
  assert.equal(qqReadingAnswer({method:'unknown',verify_message:'read'}), false);
});

function joinEvent(id, changes = {}) {
  return {op:0,t:'GROUP_JOIN_REQUEST',id:'join-event-'+id,d:{group_openid:'allowed-group',
    member_openid:'applicant',join_request_id:'request-'+id,
    verify_info:{method:'admin_review_qa',review_qa_list:[{question:'本群主题？',answer:'阅读器'}]},...changes}};
}

test('signed join event approves only matching answers once and retains no answer text', async () => {
  await withFixture(async f => {
    f.env.QQ_JOIN_APPROVAL_ENABLED = 'true';
    const approvals = [];
    globalThis.fetch = async (url, options) => {
      if (String(url).includes('/approval_join_request/')) {
        approvals.push({url:String(url),body:JSON.parse(options.body)}); return Response.json({});
      }
      return f.fetch(url, options);
    };
    const payload = joinEvent('valid');
    await qqRoutes(await signed(payload), f.env);
    await qqRoutes(await signed(payload), f.env);
    await qqRoutes(await signed({...payload,id:'redelivery-other-event'}), f.env);
    assert.deepEqual(approvals,[{url:'https://api.bot.qq.com/v2/groups/allowed-group/approval_join_request/applicant',
      body:{op:'approve',join_request_id:'request-valid'}}]);
    assert.equal(f.prompts.length,0);
    assert.equal(f.sent.length,0);
    const rows = JSON.stringify(f.DB.raw.prepare('SELECT * FROM bot_state').all());
    assert.doesNotMatch(rows,/阅读器|本群主题|applicant/);
    const status = await (await qqRoutes(new Request('https://example.test/qq/status'), f.env)).json();
    assert.equal(status.last_join_approval.outcome,'approved');
  });
});

test('disabled, other-group, unknown, malformed and already-approved joins stay untouched', async () => {
  await withFixture(async f => {
    await qqRoutes(await signed(joinEvent('disabled')),f.env);
    f.env.QQ_JOIN_APPROVAL_ENABLED = 'true';
    for (const [id,changes] of [
      ['other',{group_openid:'other-group'}],
      ['unmatched',{verify_info:{method:'admin_review_qa',review_qa_list:[{question:'阅读器',answer:'广告'}]}}],
      ['missing-answer',{verify_info:null}], ['missing-id',{join_request_id:''}],
      ['missing-member',{member_openid:''}], ['already',{auto_approved:{strategy_id:'external'}}],
    ]) await qqRoutes(await signed(joinEvent(id,changes)),f.env);
    assert.equal(f.network.length,0);
    assert.equal(f.prompts.length,0);
    assert.equal(f.sent.length,0);
  });
});

test('approval permission failure records only numeric status and leaves manual review available', async () => {
  await withFixture(async f => {
    f.env.QQ_JOIN_APPROVAL_ENABLED = 'true';
    globalThis.fetch = async (url, options) => String(url).includes('/approval_join_request/')
      ? Response.json({code:11703,message:'private-details'},{status:403}) : f.fetch(url,options);
    await qqRoutes(await signed(joinEvent('permission')),f.env);
    const status = await (await qqRoutes(new Request('https://example.test/qq/status'),f.env)).json();
    assert.equal(status.last_join_approval.outcome,'approval_failed');
    assert.equal(status.last_join_approval.code,11703);
    assert.doesNotMatch(JSON.stringify(status),/private-details|applicant/);
  });
});

test('conversation archive preserves speaker, mentions and reply links without raw IDs or auth tokens', async () => {
  await withFixture(async f => {
    const first = event('digest-1','阅读器闪退');
    first.d.author = {member_openid:'private-openid-one',username:'小明',bot:false};
    first.d.message_scene = {ext:['msg_idx=private-index-1','auth_token=private-auth-token']};
    await qqRoutes(await signed(first),f.env);
    const reply = event('digest-2','我也遇到了');
    reply.d.author = {member_openid:'private-openid-two',username:'小明',bot:false};
    reply.d.mentions = [first.d.author];
    reply.d.message_scene = {ext:['msg_idx=private-index-2','ref_msg_idx=private-index-1','auth_token=never-store']};
    reply.d.msg_elements = [{content:'token=quoted-private-key 原消息引用'}];
    await qqRoutes(await signed(reply),f.env);
    const renamed = event('digest-3','重启后正常');
    renamed.d.author = {...first.d.author,username:'小明改名'};
    await qqRoutes(await signed(renamed),f.env);
    const records = f.DB.raw.prepare("SELECT value,expires FROM bot_state WHERE key LIKE 'qq:chat:%' ORDER BY key").all();
    const values = records.map(r=>JSON.parse(r.value));
    assert.equal(values[0].speaker.key,values[2].speaker.key);
    assert.notEqual(values[0].speaker.key,values[1].speaker.key);
    assert.equal(values[1].replyTo,values[0].messageKey);
    assert.ok(records.every(r=>r.expires<=Math.floor(Date.now()/1000)+86400));
    assert.doesNotMatch(JSON.stringify(values),/private-openid|private-index|private-auth|never-store|quoted-private-key/);
    const transcript = qqDigestTranscript(values).map(JSON.parse);
    assert.equal(transcript[0].speaker,'小明改名（U1）');
    assert.equal(transcript[1].speaker,'小明（U2）');
    assert.deepEqual(transcript[1].mentions,['小明改名（U1）']);
    assert.deepEqual(transcript[1].replyTo,{message:'M1',speaker:'小明改名（U1）'});
    assert.equal(f.prompts.length,0);
  });
});

test('legacy messages and unavailable referenced messages never acquire an invented speaker', () => {
  const values = [{ts:100,text:'旧消息'},
    {ts:101,text:'跟进',speaker:{key:'one'},replyTo:'missing'},
    {ts:102,text:'同名甲',speaker:{key:'two',name:'同名'}},
    {ts:103,text:'同名乙',speaker:{key:'three',name:'同名'}}];
  const lines = qqDigestTranscript(values).map(JSON.parse);
  assert.equal(lines[0].speaker,'未记录发言人');
  assert.equal(lines[1].speaker,'群友（U1）');
  assert.equal(lines[1].replyTo,'引用消息不在本时段记录中');
  assert.notEqual(lines[2].speaker,lines[3].speaker);
});

test('diagnostic commands are excluded before AI sees the digest transcript', () => {
  const rows = ['/summary-test','/permissions','/push-test','/help','阅读器导入问题']
    .map(text=>({ts:100,text,speaker:{key:'one',name:'甲'}}));
  const lines = qqDigestTranscript(rows).map(JSON.parse);
  assert.deepEqual(lines.map(m=>m.text),['阅读器导入问题']);
});



test('mentioned questions search the redacted question once and cite only provider URLs', async () => {
  await withFixture(async f => {
    f.searchItems = [
      {url:'https://developers.cloudflare.com/web-search/',title:'官方搜索文档',content:'Web search supports AI binding.'},
      {url:'javascript:alert(1)',title:'invalid',content:'ignore'},
      {url:'https://user:password@example.com/',title:'invalid',content:'ignore'},
      {url:'https://developers.cloudflare.com/web-search/',title:'duplicate',content:'ignore'}];
    f.env.AI.run = async (model, input) => {
      f.prompts.push(input);
      return {response: '搜索支持 AI binding [1]。虚构来源 [9] https://fake.example/bogus'};
    };
    const payload = event('search1', '<@test-app> 搜索 Cloudflare token=private-key 联系 a@example.test', 'allowed-group', 'GROUP_AT_MESSAGE_CREATE');
    await qqRoutes(await signed(payload), f.env);
    await qqRoutes(await signed(payload), f.env);
    assert.match(f.searches[0], /搜索 Cloudflare/);
    assert.doesNotMatch(JSON.stringify(f.searches), /private-key|a@example.test|member-search1|test-app/);
    assert.doesNotMatch(JSON.stringify(f.prompts), /private-key|a@example.test|member-search1|test-app/);
    assert.equal(f.prompts.length, 1);
    assert.doesNotMatch(f.prompts[0].messages[0].content, /invalid|duplicate/);
    const reply = f.sent.map(x => x.content).join('');
    assert.match(reply, /联网搜索汇总（AnySearch）/);
    assert.match(reply, /https:\/\/developers.cloudflare.com\/web-search\//);
    assert.doesNotMatch(reply, /fake.example|\[9\]|javascript:|password/);
    assert.ok(f.network.every(url => !url.includes('api.cloudflare.com') && !url.includes('websearch')));
  });
});

test('ordinary chat never searches, /search works, and /ask remains documentation only', async () => {
  await withFixture(async f => {
    await qqRoutes(await signed(event('plain-search','帮忙联网搜索一下')), f.env);
    await qqRoutes(await signed(event('explicit-search','/search 最新技术新闻')), f.env);
    assert.equal(f.searches.length, 1);
    assert.equal(f.prompts.length, 0); // Empty evidence never reaches the model.
    assert.match(f.sent[0].content, /未找到可用来源/);
    await qqRoutes(await signed(event('docs-search','/ask Modu 支持什么格式？')), f.env);
    assert.equal(f.searches.length, 1);
    assert.equal(f.prompts.length, 1);
    assert.match(f.sent[1].content, /README.md/);
  });
});

test('free search failure never switches to paid service or generates an unsupported answer', async () => {
  await withFixture(async f => {
    f.searchResponse = new Response('Rate limited', {status:429});
    await qqRoutes(await signed(event('search-fail','/search 最新新闻')), f.env);
    assert.equal(f.prompts.length, 0);
    assert.equal(f.searches.length, 1);
    assert.match(f.sent[0].content, /未能完成联网汇总/);
    const audit = JSON.parse(f.DB.raw.prepare("SELECT value FROM bot_state WHERE key='qq:last-web-search'").get().value);
    assert.equal(audit.stage, 'search');
    assert.equal(audit.code, 429);
    assert.doesNotMatch(JSON.stringify(audit), /最新新闻|member-/);
    assert.equal(f.network.filter(url => url.includes('api.anysearch.com')).length, 1);
    assert.ok(f.network.every(url => !url.includes('api.cloudflare.com')));
  });
});

test('query size is bounded and the public free search has a group-wide rate limit', async () => {
  await withFixture(async f => {
    await qqRoutes(await signed(event('search-long','/search '+ '文'.repeat(1025))), f.env);
    assert.equal(f.searches.length, 0);
    assert.equal(f.prompts.length, 0);
    assert.match(f.sent[0].content, /1024/);
    await qqRoutes(await signed(event('search-short1','/search EPUB 阅读器')), f.env);
    await qqRoutes(await signed(event('search-short2','/search PDF 阅读器')), f.env);
    assert.equal(f.searches.length, 1);
    assert.match(f.sent[2].content, /5 秒/);
  });
});

test('search shares the per-user cooldown and daily answer limit', async () => {
  await withFixture(async f => {
    const first = event('search-rate1','/search 最新技术新闻');
    const second = event('search-rate2','/search 再搜索');
    second.d.author = first.d.author;
    await qqRoutes(await signed(first), f.env);
    await qqRoutes(await signed(second), f.env);
    assert.equal(f.searches.length, 1);
    assert.match(f.sent[1].content, /30 秒/);
    store(f.DB, 'qq:ai:'+new Date().toISOString().slice(0,10), 80, Math.floor(Date.now()/1000));
    await qqRoutes(await signed(event('search-daily','/search 最新新闻')), f.env);
    assert.equal(f.searches.length, 1);
    assert.match(f.sent[2].content, /80 次/);
  });
});


test('anonymous quota credentials and malformed results are never reused or exposed', async () => {
  for (const response of [new Response('username=x password=private-password api_key=private-key', {status:402}),
    Response.json({code:-1, message:'api_key=private-key'}), Response.json({code:0,data:{results:{}}})]) {
    await withFixture(async f => {
      f.searchResponse = response;
      await qqRoutes(await signed(event('bad-search','/search EPUB')), f.env);
      assert.equal(f.searches.length, 1);
      assert.equal(f.prompts.length, 0);
      assert.match(f.sent[0].content, /未能完成联网汇总/);
      assert.doesNotMatch(JSON.stringify(f.sent)+JSON.stringify(f.DB.raw.prepare('SELECT value FROM bot_state').all()),
        /private-key|private-password|username=x/);
    });
  }
});


test('Tavily free basic search is primary, redacts the question and preserves published dates', async () => {
  await withFixture(async f => {
    f.env.TAVILY_API_KEY = 'test-tavily-key';
    f.searchItems = [{title:'EPUB spec',url:'https://www.w3.org/TR/epub-33/',content:'EPUB specification',published_date:'2026-01-01'}];
    await qqRoutes(await signed(event('tavily-primary','/search EPUB token=private-key')), f.env);
    assert.equal(f.tavilyRequests.length, 1);
    assert.equal(f.searches.length, 0);
    const request = f.tavilyRequests[0];
    assert.equal(request.search_depth, 'basic');
    assert.equal(request.auto_parameters, false);
    assert.equal(request.include_answer, false);
    assert.equal(request.include_raw_content, false);
    assert.equal(request.max_results, 5);
    assert.doesNotMatch(JSON.stringify(request), /private-key|test-tavily-key|member-/);
    assert.match(JSON.stringify(f.prompts), /2026-01-01/);
    assert.match(f.sent[0].content, /联网搜索汇总（Tavily）/);
    assert.doesNotMatch(f.sent[0].content, /test-tavily-key/);
  });
});

test('Tavily failures, empty results and quota exhaustion use only the anonymous free fallback', async () => {
  for (const response of [new Response('private-key', {status:401}),new Response('',{status:432}),
    new Response('',{status:429}),Response.json({results:[]}),Response.json({results:null})]) {
    await withFixture(async f => {
      f.env.TAVILY_API_KEY = 'test-tavily-key'; f.tavilyResponse = response;
      f.searchItems = [{title:'EPUB',url:'https://www.w3.org/TR/epub-33/',snippet:'EPUB'}];
      await qqRoutes(await signed(event('tavily-fallback','/search EPUB')), f.env);
      assert.equal(f.tavilyRequests.length, 1);
      assert.equal(f.searches.length, 1);
      assert.match(f.sent[0].content, /联网搜索汇总（AnySearch）/);
      assert.doesNotMatch(JSON.stringify(f.sent)+JSON.stringify(f.DB.raw.prepare('SELECT value FROM bot_state').all()), /private-key|test-tavily-key/);
    });
  }
});

test('paid plans, unknown usage and exhausted free allowance never call Tavily search', async () => {
  for (const usage of [{current_plan:'Project',plan_limit:4000,plan_usage:0},
    {current_plan:'Researcher',plan_limit:1000,plan_usage:950},
    {current_plan:'Researcher',plan_limit:1000,plan_usage:null},
    {current_plan:'Researcher',plan_limit:1000,plan_usage:-1}, {}]) {
    await withFixture(async f => {
      f.env.TAVILY_API_KEY = 'test-tavily-key';
      f.tavilyUsageResponse = Response.json({account:usage});
      await qqRoutes(await signed(event('tavily-budget','/search EPUB')), f.env);
      assert.equal(f.tavilyRequests.length, 0);
      assert.equal(f.searches.length, 1);
    });
  }
  await withFixture(async f => {
    f.env.TAVILY_API_KEY = 'test-tavily-key';
    store(f.DB,'qq:tavily:'+new Date().toISOString().slice(0,7),950,Math.floor(Date.now()/1000));
    await qqRoutes(await signed(event('tavily-monthly','/search EPUB')), f.env);
    assert.equal(f.tavilyRequests.length, 0);
    assert.equal(f.network.filter(url => url.includes('tavily.com')).length, 0);
    assert.equal(f.searches.length, 1);
  });
});

test('unavailable account usage skips Tavily search; two provider failures never reach AI', async () => {
  await withFixture(async f => {
    f.env.TAVILY_API_KEY = 'test-tavily-key';
    f.tavilyUsageResponse = new Response('private-key', {status:503});
    f.searchResponse = new Response('private-key', {status:429});
    await qqRoutes(await signed(event('both-search-fail','/search EPUB')), f.env);
    assert.equal(f.tavilyRequests.length, 0);
    assert.equal(f.searches.length, 1);
    assert.equal(f.prompts.length, 0);
    assert.match(f.sent[0].content, /未能完成联网汇总/);
    assert.doesNotMatch(JSON.stringify(f.sent)+JSON.stringify(f.DB.raw.prepare('SELECT value FROM bot_state').all()), /private-key|test-tavily-key/);
  });
});


test('daily transcript retains dates across midnight for contextual feedback', () => {
  const rows=[{ts:Date.parse('2026-10-08T16:52:00+08:00')/1000,text:'iOS选中文字无法批注'},
    {ts:Date.parse('2026-10-09T08:10:00+08:00')/1000,text:'测试后可以了'}];
  const transcript=qqDigestTranscript(rows).map(JSON.parse);
  assert.equal(transcript[0].time,'2026-10-08 16:52');
  assert.equal(transcript[1].time,'2026-10-09 08:10');
});


test('QQ face metadata cannot crowd out feedback and its later resolution', () => {
  const face='<faceType=1,faceId="496",ext="'+'x'.repeat(100)+'">';
  const records=Array.from({length:190},(_,i)=>({ts:1791432000+i*60,text:'阅读讨论'+face.repeat(2)}));
  records[40].text='iOS 27.2 拖动选区后无法复制'+face;
  records[180].text='测试后可以了'+face;
  records[185].quoted=['UMD支持已加入Preview版本'+face];
  const input=qqDigestTranscript(records).join('\n');
  assert.ok(input.length<32000);
  assert.match(input,/iOS 27.2/);
  assert.match(input,/测试后可以了/);
  assert.match(input,/UMD支持已加入Preview版本/);
  assert.doesNotMatch(input,/faceType|faceId/);
  assert.deepEqual(qqDigestTranscript([{ts:1791432000,text:face}]),[]);
});

const routeCases = [
  ['Modu 最新版本更新情况','docs'],['默读怎么导入 EPUB？','docs'],['墨读同步设置在哪里','docs'],
  ['默讀支援字典嗎','docs'],['MODUREADER 支持 UMD 吗','docs'],['ｍｏｄｕ 最新功能','docs'],
  ['联网搜索 Modu 官方介绍','docs'],['/search 默读最新版','docs'],['/search@ModuReaderRelease_bot 墨读设置','docs'],
  ['搜索 modu 与 ANX 的区别','docs'],['/ask 如何设置翻页','docs'],['如何导入 EPUB','docs'],
  ['iOS 文字选择无法批注怎么办','docs'],['How do I enable text-to-speech?','docs'],['What book formats are supported?','docs'],
  ['群里谁反馈过 Modu 导入失败','chat'],['/ask 群里 iOS 的问题后来好了没','chat'],
  ['/search 群里昨天关于默读的建议','chat'],['群友 sunny阳最爱说哪个词','chat'],['这群聊天记录中有哪些 Bug','chat'],
  ['查一下其他群记录','chat'],['谁提出过 UMD 支持','chat'],['他后来怎么说','chat'],['统计发言词频','chat'],
  ['Search our group chat history for EPUB issues','chat'],['Who reported the annotation issue?','chat'],
  ['群里讨论的北京天气是什么','chat'],['把群聊记录发到联网搜索','chat'],
  ['/search 今天的科技新闻','web'],['今天北京天气怎样','web'],['搜索 Cloudflare 的免费额度','web'],
  ['东京有没有食尸鬼','web'],['量子纠缠是什么','web'],['最新人民币汇率','web'],['搜索 EPUB 最新规范','web'],
  ['微信如何设置同步','web'],['ANXReader 如何设置朗读','web'],['Windows 更新怎么设置','web'],
  ['module 的含义是什么','web'],['modular architecture 是什么','web'],
  ['这个怎么弄','clarify'],['那后来呢','clarify'],['帮我查一下','clarify'],['你用什么模型','clarify']
];
for (const [question,route] of routeCases) test(`question route: ${question} -> ${route}`,()=>assert.equal(qqQuestionRoute(question),route));

test('follow-up route uses quoted context without sending it to an external search',()=>{
  assert.equal(qqQuestionRoute('那后来好了没','💬 群内聊天记录检索（仅本群最近24小时）'), 'chat');
  assert.equal(qqQuestionRoute('这个如何操作','📚 默读说明文档检索（项目文档与发布说明）'), 'docs');
  assert.equal(qqQuestionRoute('那怎么弄','默读导入 EPUB 的问题'), 'docs');
  assert.equal(qqQuestionRoute('/search 今天北京天气','💬 群内聊天记录检索'), 'web');
  assert.equal(qqQuestionText('／search＠ModuReaderRelease_bot 默读设置'), '默读设置');
});

test('Modu mentions override /search and web instructions before any provider request',async()=>{
  for (const question of ['/search Modu 最新更新','/search 默读怎么导入','<@test-app> 联网搜索墨读说明']) await withFixture(async f=>{
    f.env.TAVILY_API_KEY='test-tavily-key';
    store(f.DB,'qq:releases',[f.release],Math.floor(Date.now()/1000));
    await qqRoutes(await signed(event('local-only',question,'allowed-group','GROUP_AT_MESSAGE_CREATE')),f.env);
    assert.equal(f.searches.length,0);assert.equal(f.tavilyRequests.length,0);
    assert.ok(!f.network.some(url=>/api\.(?:tavily|anysearch)\.com/.test(url)));
    assert.match(f.sent.map(m=>m.content).join(''),/默读说明文档检索/);
    assert.match(f.prompts[0].messages[0].content,/PUBLIC PROJECT DOCUMENT/);
    assert.equal(JSON.parse(f.DB.raw.prepare("SELECT value FROM bot_state WHERE key='qq:last-question'").get().value).route,'docs');
  });
});

test('documentation selects related current files, reuses the cache and cites project release notes',async()=>withFixture(async f=>{
  store(f.DB,'qq:releases',[f.release],Math.floor(Date.now()/1000));
  await qqRoutes(await signed(event('dict-docs','<@test-app> 默读本地字典怎么导入','allowed-group','GROUP_AT_MESSAGE_CREATE')),f.env);
  assert.ok(f.network.some(url=>url.endsWith('/docs/LOCAL_DICTIONARIES.md')));
  assert.ok(f.network.some(url=>url.endsWith('/docs/FEATURES_zh.md')));
  const downloads=f.network.filter(url=>url.includes('raw.githubusercontent.com')).length;
  await qqRoutes(await signed(event('dict-docs-again','/ask 默读本地字典设置')),f.env);
  assert.equal(f.network.filter(url=>url.includes('raw.githubusercontent.com')).length,downloads);
  await qqRoutes(await signed(event('release-docs','/search Modu 最新版更新情况')),f.env);
  assert.match(f.prompts.at(-1).messages[0].content,/v1.0-beta/);
  assert.match(f.prompts.at(-1).messages[0].content,/releases\/tag\//);
  assert.equal(f.searches.length,0);
}));

test('failed documentation never falls back to a web provider',async()=>withFixture(async f=>{
  globalThis.fetch=async (url,options)=>String(url).includes('raw.githubusercontent.com') ? new Response('',{status:404}) : f.fetch(url,options);
  await qqRoutes(await signed(event('docs-down','/search 默读翻页设置')),f.env);
  assert.equal(f.searches.length,0);assert.equal(f.prompts.length,0);
  assert.match(f.sent[0].content,/没有转为联网搜索/);
}));

test('group-history requests use only retained bound QQ records, exclude the question and include later replies',async()=>withFixture(async f=>{
  const now=Math.floor(Date.now()/1000);
  store(f.DB,'qq:chat:allowed-group:old',{ts:now-23*3600,text:'默读 iOS 27.2 选中文字后无法批注',speaker:{key:'one',name:'小明'}},now);
  store(f.DB,'qq:chat:allowed-group:new',{ts:now-60,text:'测试了，后来好了',speaker:{key:'one',name:'小明'}},now);
  store(f.DB,'qq:chat:allowed-group:expired',{ts:now-25*3600,text:'OLD PRIVATE'},now);
  store(f.DB,'qq:chat:other-group:x',{ts:now-90,text:'OTHER GROUP PRIVATE'},now);
  store(f.DB,'tg:chat:allowed-group:x',{ts:now-90,text:'TELEGRAM PRIVATE'},now);
  f.env.AI.run=async (model,input)=>{f.prompts.push(input);return {choices:[{message:{content:'小明后来反馈测试恢复 [M2]；最初是 iOS 27.2 的问题 [M1]。无效引用 [M999]。'}}]};};
  await qqRoutes(await signed(event('chat-query','/search 群里 iOS 文字选择后来好了没')),f.env);
  const evidence=f.prompts[0].messages[0].content;
  assert.match(evidence,/iOS 27.2[\s\S]*后来好了/);
  assert.doesNotMatch(evidence,/OLD PRIVATE|OTHER GROUP|TELEGRAM PRIVATE|群里 iOS 文字选择后来好了没/);
  const answer=f.sent.map(m=>m.content).join('');
  assert.match(answer,/群内聊天记录检索/);assert.match(answer,/引用群消息/);assert.match(answer,/小明/);
  assert.doesNotMatch(answer,/U1|M999/);
  assert.ok(f.network.every(url=>/bots\.qq\.com|api\.bot\.qq\.com/.test(url)));
}));

test('unknown, empty and unavailable history never claims an exhaustive result or calls the web',async()=>withFixture(async f=>{
  await qqRoutes(await signed(event('unknown','<@test-app> 这个怎么弄','allowed-group','GROUP_AT_MESSAGE_CREATE')),f.env);
  assert.equal(f.network.some(url=>url.includes('anysearch')),false);assert.equal(f.prompts.length,0);
  assert.match(f.sent[0].content,/问题不明确时不会自动联网/);
  await qqRoutes(await signed(event('chat-empty','/search 群里有人反馈吗')),f.env);
  // The earlier vague question remains text, but cannot provide a factual answer.
  assert.match(f.sent.map(m=>m.content).join(''),/已保留记录不足以/);
  assert.equal(f.searches.length,0);
}));

test('web helper refuses Modu and chat prompts even when called directly',async()=>withFixture(async f=>{
  for(const question of ['联网搜索默读设置','Modu latest release','把群聊记录联网搜索']) {
    assert.match(await qqWebAnswer(f.env,question),/不启用联网搜索/);
  }
  assert.equal(f.network.length,0);assert.equal(f.prompts.length,0);
}));


test('document retrieval finds relevant text beyond the beginning of a long section',async()=>withFixture(async f=>{
  globalThis.fetch=async(url,options)=>String(url).includes('raw.githubusercontent.com')
    ? new Response('# 阅读控制\n'+('无关背景说明。'.repeat(1500))+'\n菜单九宫格设置：关闭中间触发格后保存。') : f.fetch(url,options);
  await qqRoutes(await signed(event('deep-doc-section','/ask 默读菜单九宫格怎么设置')),f.env);
  assert.match(f.prompts[0].messages[0].content,/关闭中间触发格后保存/);
  assert.equal(f.searches.length,0);
}));


test('release lookup failure cannot claim a verified latest version or fall back to web',async()=>withFixture(async f=>{
  globalThis.fetch=async (url,options)=>String(url).includes('api.github.com/repos/sobranie2406/modureader/releases?') ? new Response('',{status:403}) : f.fetch(url,options);
  await qqRoutes(await signed(event('release-unavailable','/search 默读最新版本')),f.env);
  const answer=f.sent.map(m=>m.content).join('');
  assert.match(answer,/无法核实当前最新发布版本/);
  assert.match(answer,/github.com\/sobranie2406\/modureader\/releases/);
  assert.equal(f.prompts.length,0);assert.equal(f.searches.length,0);
}));

test('documentation keeps supplied download links and labels invented links instead of blanks',async()=>withFixture(async f=>{
  const supplied='https://gitee.com/sobranie2406/modureader/releases';
  globalThis.fetch=async (url,options)=>String(url).includes('raw.githubusercontent.com') ? new Response('[下载]('+supplied+')') : f.fetch(url,options);
  f.env.AI.run=async()=>({response:'[下载]('+supplied+')\\n[假链接](https://invented.example/download)'});
  await qqRoutes(await signed(event('doc-download','/ask 默读下载地址')),f.env);
  const answer=f.sent.map(m=>m.content).join('');
  assert.match(answer,/https:\/\/gitee.com\/sobranie2406\/modureader\/releases/);
  assert.doesNotMatch(answer,/invented.example/);assert.match(answer,/检索资料未提供此链接/);
  assert.equal(f.searches.length,0);
}));

const bingCard = (url='https://www.w3.org/TR/epub-33/',title='EPUB 标准',snippet='电子书规范 &amp; 可访问性') =>
  `<li class="b_algo"><h2><a href="${url}">${title}</a></h2><div class="b_caption"><p>${snippet}</p></div></li>`;
test('Bing static results decode tracking URLs and text; scripts, unsafe links and shells are rejected', () => {
  const url='https://zh.wikipedia.org/wiki/电子书';
  const tracking='https://www.bing.com/ck/a?u=a1'+Buffer.from(url).toString('base64url');
  const result=qqBingResults(bingCard(tracking,'<strong>电子书</strong>','&#x4e2d;&#25991;&nbsp;摘要<script>bad()</script>'));
  assert.deepEqual(result,[{title:'电子书',url:new URL(url).href,snippet:'中文 摘要'}]);
  for(const href of ['javascript:alert(1)','http://example.org','https://user:pass@example.org','https://www.bing.com/ck/a?u=bad'])
    assert.deepEqual(qqBingResults(bingCard(href)),[]);
  assert.deepEqual(qqBingResults('<html><script>results()</script></html>'),[]);
  assert.deepEqual(qqBingResults('x'.repeat(1000001)+bingCard()),[]);
});
test('explicit Bing uses public HTML first and never mislabels a free API fallback', async () => {
  await withFixture(async f=>{
    f.env.TAVILY_API_KEY='test-tavily-key'; f.bingResponse=new Response(bingCard());
    const answer=await qqWebAnswer(f.env,'用Bing搜索 EPUB 标准');
    assert.match(answer,/汇总（Bing 网页）/); assert.equal(f.tavilyRequests.length,0); assert.equal(f.searches.length,0);
    assert.equal(new URL(f.network[0]).searchParams.get('q'),'EPUB 标准');
  });
  await withFixture(async f=>{
    f.env.TAVILY_API_KEY='test-tavily-key'; f.searchItems=[{title:'EPUB',url:'https://www.w3.org/TR/epub-33/',content:'标准'}];
    const answer=await qqWebAnswer(f.env,'Bing搜索 EPUB');
    assert.match(answer,/汇总（Tavily）/);assert.match(answer,/Bing 网页未返回可用结果/);
  });
});
test('Wikipedia and Baidu Baike queries restrict both Tavily requests and all cited hosts',async()=>{
  for(const [term,domain] of [['维基百科','wikipedia.org'],['百度百科','baike.baidu.com']]) {
    await withFixture(async f=>{
      f.env.TAVILY_API_KEY='test-tavily-key';
      f.searchItems=[{title:'wrong',url:'https://example.org/',content:'wrong'},
        {title:'spoof',url:'https://'+domain+'.evil.org/',content:'spoof'},
        {title:'百科',url:'https://'+domain+'/item/example',content:'百科摘要'}];
      const answer=await qqWebAnswer(f.env,term+' 电子书是什么');
      assert.equal(f.tavilyRequests[0].query,'电子书是什么');
      assert.deepEqual(f.tavilyRequests[0].include_domains,[domain]);assert.equal(f.tavilyRequests[0].include_domains_mode,'restrict');
      assert.match(answer,/限定来源/);assert.ok(answer.includes('https://'+domain+'/'));
      assert.doesNotMatch(answer,/evil.org|example.org|wrong/);
      assert.doesNotMatch(JSON.stringify(f.prompts),/spoof|wrong/);
    });
  }
});
test('Bing is the final free fallback; encyclopedia pages from other hosts never reach AI',async()=>{
  await withFixture(async f=>{
    f.searchResponse=new Response('',{status:429}); f.bingResponse=new Response(bingCard());
    assert.match(await qqWebAnswer(f.env,'EPUB 标准'),/汇总（Bing 网页）/);
  });
  await withFixture(async f=>{
    f.searchItems=[{title:'wrong',url:'https://example.org/',content:'wrong'}];f.bingResponse=new Response(bingCard());
    assert.match(await qqWebAnswer(f.env,'百度百科 电子书'),/未找到可用来源/);assert.equal(f.prompts.length,0);
    assert.match(f.searches[0],/^site:baike.baidu.com /);
  });
});
test('Google requests disclose unavailable public pages; internal requests cannot use any web provider',async()=>{
  await withFixture(async f=>{
    f.env.TAVILY_API_KEY='test-tavily-key';f.searchItems=[{title:'EPUB',url:'https://www.w3.org/TR/epub-33/',content:'标准'}];
    const answer=await qqWebAnswer(f.env,'谷歌搜索 EPUB 标准');
    assert.match(answer,/汇总（Tavily）/);assert.match(answer,/Google 公开搜索页面暂不可读取/);
    assert.ok(!f.network.some(url=>url.includes('google.com')));
  });
  for(const question of ['用Bing搜索 默读怎么设置','百度百科 Modu 支持的格式','维基百科 群里昨天谁反馈Bug']) {
    await withFixture(async f=>{
      assert.match(await qqWebAnswer(f.env,question),/不启用联网搜索/);assert.equal(f.network.length,0);
    });
  }
});


test('Telegram chat citations link to actual retained message IDs after diagnostic filtering',async()=>withFixture(async f=>{
  const now=Math.floor(Date.now()/1000), group='-1004201042022';
  store(f.DB,`tg:chat:${group}:10`,{ts:now-300,text:'/summary-test 24h'},now);
  store(f.DB,`tg:chat:${group}:11`,{ts:now-200,text:'默读导入失败',speaker:{key:'one',name:'小明'}},now);
  store(f.DB,`tg:chat:${group}:12`,{ts:now-100,text:'重启后好了',speaker:{key:'one',name:'小明'},sourceMessageId:'999'},now);
  store(f.DB,'tg:chat:-100999:13',{ts:now-60,text:'Other group'},now);
  f.env.AI.run=async(model,input)=>{f.prompts.push(input);return {response:'已恢复 [M2]，最初导入失败 [M1]。伪造链接 https://t.me/c/999/999 [M999]'};};
  const answer=await qqChatAnswer(f.env,group,'群里导入失败后来好了没','tg','20');
  assert.match(answer,/\[M2\][^\n]*重启后好了\n查看原消息：https:\/\/t.me\/c\/4201042022\/12/);
  assert.match(answer,/\[M1\][^\n]*默读导入失败\n查看原消息：https:\/\/t.me\/c\/4201042022\/11/);
  assert.doesNotMatch(answer,/\/10\b|\/999\b|M999|Other group/);
  assert.doesNotMatch(JSON.stringify(f.prompts),/sourceMessageId|t.me\/c\//);
  assert.equal(f.network.length,0);
}));
test('QQ, basic Telegram groups and malformed message IDs do not get fabricated jump links',async()=>{
  for(const [platform,group,messageId] of [['qq','allowed-group','11'],['tg','-12345','11'],['tg','-1004201042022','bad/12']]) {
    await withFixture(async f=>{
      const now=Math.floor(Date.now()/1000);
      store(f.DB,`${platform}:chat:${group}:${messageId}`,{ts:now-60,text:'默读导入失败'},now);
      f.env.AI.run=async()=>({response:'导入失败 [M1]'});
      const answer=await qqChatAnswer(f.env,group,'群里导入失败',platform);
      assert.match(answer,/引用群消息/);assert.doesNotMatch(answer,/查看原消息|https:\/\/t.me\/c\//);
    });
  }
});
