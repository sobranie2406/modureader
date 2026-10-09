import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {webcrypto} from 'node:crypto';
import {qqKeys, qqVerify, qqRedact, qqSplit, qqWindow, qqRoutes, qqSchedule, qqReleaseText, qqReleaseIdentity, qqReadingAnswer, qqDigestTranscript} from './qq-bot.mjs';

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
  const f = {env, DB, sent, prompts, network,
    release:{id:123,tag_name:'v1.0-beta',prerelease:true,draft:false,
      published_at:new Date().toISOString(),body:'中文：修复阅读问题。\nEnglish: Fix reader issues.'},
    async fetch(url, options = {}) {
    network.push(String(url));
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

test('08:00 and 20:00 Beijing boundaries cover the previous twelve hours exactly', () => {
  assert.deepEqual(qqWindow(Date.parse('2026-10-07T08:00:00+08:00')),
    {start:Date.parse('2026-10-06T20:00:00+08:00')/1000, end:Date.parse('2026-10-07T08:00:00+08:00')/1000});
  assert.deepEqual(qqWindow(Date.parse('2026-10-07T20:00:00+08:00')),
    {start:Date.parse('2026-10-07T08:00:00+08:00')/1000, end:Date.parse('2026-10-07T20:00:00+08:00')/1000});
});

test('summary cron filters the interval, redacts text, sends proactively and deduplicates', async () => {
  const originalNow = Date.now;
  const at = Date.parse('2026-10-07T08:00:00+08:00');
  Date.now = () => at;
  try {
    await withFixture(async f => {
      const seconds = at/1000;
      store(f.DB, 'qq:started', {at:seconds-86400}, seconds);
      store(f.DB, 'qq:push-permission', {allowed:true,tested:true}, seconds);
      store(f.DB, 'qq:chat:allowed-group:inside', {ts:seconds-60,text:qqRedact('EPUB 导入讨论 token=test-secret')}, seconds);
      store(f.DB, 'qq:chat:allowed-group:before', {ts:seconds-43201,text:'Outside previous interval'}, seconds);
      store(f.DB, 'qq:chat:allowed-group:end', {ts:seconds,text:'Outside current interval'}, seconds);
      const summarize = f.env.AI.run;
      f.env.AI.run = async (...args) => {
        await summarize(...args);
        return {response:'1. 小明（U1）、用户 U2、群友(U3)、U4：阅读器反馈 👉 小明（U1）报告闪退，用户U2回应仍待确认。'};
      };
      await qqSchedule({scheduledTime:at-60000}, f.env);
      assert.equal(f.sent.length, 0);
      await qqSchedule({scheduledTime:at}, f.env);
      await qqSchedule({scheduledTime:at}, f.env);
      assert.equal(f.prompts.length, 1);
      assert.match(f.prompts[0].messages[1].content, /EPUB 导入/);
      assert.doesNotMatch(f.prompts[0].messages[1].content, /test-secret|Outside/);
      assert.match(f.sent[0].content, /2026-10-06 20:00 — 2026-10-07 08:00/);
      assert.equal(f.sent[0].msg_id, undefined);
      assert.match(f.sent[0].content, /1\. 小明、群友、群友、群友：阅读器反馈/);
      assert.match(f.sent[0].content, /小明报告闪退，群友回应仍待确认/);
      assert.doesNotMatch(f.sent[0].content, /\bU\d+\b/);
      assert.equal(JSON.parse(f.DB.raw.prepare("SELECT value FROM bot_state WHERE key='qq:last-summary'").get().value).ok, true);
    });
  } finally {Date.now = originalNow;}
});

test('no scheduled push happens until proactive permission is actually tested', async () => {
  await withFixture(async f => {
    const seconds = Math.floor(Date.now()/1000);
    store(f.DB, 'qq:started', {at:seconds}, seconds);
    store(f.DB, 'qq:push-permission', {allowed:true,tested:false}, seconds);
    await qqSchedule({scheduledTime:Date.parse('2026-10-07T08:00:00+08:00')}, f.env);
    assert.equal(f.sent.length, 0);
  });
});

test('large summaries sample both the beginning and end of the whole interval', async () => {
  const originalNow = Date.now;
  const at = Date.parse('2026-10-07T20:00:00+08:00');
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
    assert.match(text, /08:00 Asia\/Shanghai/);
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
