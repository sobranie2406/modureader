import {qqRoutes, qqSchedule, qqArchive, qqSummary, qqWindow, qqQuestionRoute, qqQuestionText, qqDocsAnswer, qqChatAnswer, qqWebAnswer, QQ_CLARIFY} from './qq-bot.mjs';

const REPO = 'https://github.com/sobranie2406/modureader';
const BOT = 'ModuReaderRelease_bot';
const HELP = `📚 ModuReader 助手 / Helper\n/ask 问题 — 默读项目文档 / Project docs\n/search 外部问题 — 免费联网搜索 / Web search\n提问按内容选择：群里发言查本群记录，默读功能与版本查项目资料（不联网），外部问题查网页。\n/release — 最新正式版下载 / Latest stable release\n/help — 使用说明 / Help\n也可 @${BOT} 提问或回复机器人的消息。\n新成员需在 2 分钟内验证；禁止广告邀请和刷屏。\n每天北京时间 12:00 汇总过去 24 小时的默读建议与 Bug 反馈；管理员可用 /summary-test 24h 测试。\n群文字先隐藏明显密钥和联系方式，在 Cloudflare 保存 24 小时并由 AI 汇总；不下载图片或文件。请勿提交密钥、个人信息或私密书籍。AI 可能出错，请核对引用文档。`;
const now = () => Math.floor(Date.now()/1000);
const json = (data,status=200) => new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json; charset=utf-8'}});
async function telegram(env,method,data) {
  const response = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(data)});
  const result = await response.json();
  if (!response.ok || !result.ok) throw new Error(`Telegram ${method} failed (${response.status})`);
  return result.result;
}
async function get(env,key) {
  const row = await env.DB.prepare('SELECT value FROM bot_state WHERE key=? AND expires>?').bind(key,now()).first();
  return row ? JSON.parse(row.value) : null;
}
async function put(env,key,value,ttl) {
  await env.DB.prepare('INSERT INTO bot_state(key,value,expires) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,expires=excluded.expires').bind(key,JSON.stringify(value),now()+ttl).run();
}
async function drop(env,key) { await env.DB.prepare('DELETE FROM bot_state WHERE key=?').bind(key).run(); }
async function claim(env,key,ttl) {
  const result = await env.DB.prepare('INSERT INTO bot_state(key,value,expires) VALUES(?,\'true\',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,expires=excluded.expires WHERE bot_state.expires<=? RETURNING key').bind(key,now()+ttl,now()).first();
  return !!result;
}
async function count(env,key,ttl) {
  const row = await env.DB.prepare('INSERT INTO bot_state(key,value,expires) VALUES(?,\'1\',?) ON CONFLICT(key) DO UPDATE SET value=CAST(CAST(bot_state.value AS INTEGER)+1 AS TEXT) RETURNING value').bind(key,now()+ttl).first();
  return Number(row.value);
}
async function send(env,text,message) {
  return telegram(env,'sendMessage',{chat_id:env.GROUP_ID,text:text.slice(0,3800),link_preview_options:{is_disabled:true},...(message?{reply_parameters:{message_id:message.message_id,allow_sending_without_reply:true}}:{})});
}
async function admin(env,id) {
  const info = await telegram(env,'getChatMember',{chat_id:env.GROUP_ID,user_id:id});
  return ['creator','administrator'].includes(info.status);
}
async function mute(env,id,until_date=0) {
  await telegram(env,'restrictChatMember',{chat_id:env.GROUP_ID,user_id:id,permissions:{can_send_messages:false},use_independent_chat_permissions:true,until_date});
}
async function join(env,user) {
  if (user.is_bot || await admin(env,user.id)) return;
  const key = `join:${user.id}`;
  if (await get(env,key)) return;
  const chat = await telegram(env,'getChat',{chat_id:env.GROUP_ID});
  const a = crypto.getRandomValues(new Uint8Array(1))[0]%8+2;
  const b = crypto.getRandomValues(new Uint8Array(1))[0]%8+2;
  const nonce = crypto.randomUUID().slice(0,8);
  const challenge = {user:user.id,answer:a+b,nonce,permissions:chat.permissions,deadline:now()+120};
  await put(env,key,challenge,3600);
  await mute(env,user.id);
  const options = [a+b,a+b+1,a+b-1].sort(()=>crypto.getRandomValues(new Uint8Array(1))[0]-128);
  const welcome = await telegram(env,'sendMessage',{chat_id:env.GROUP_ID,text:`欢迎 ${user.first_name || '新朋友'}！请在 2 分钟内验证：${a} + ${b} = ?\nWelcome! Verify within 2 minutes.`,reply_markup:{inline_keyboard:[options.map(answer=>({text:String(answer),callback_data:`v:${user.id}:${nonce}:${answer}`}))]}});
  challenge.message=welcome.message_id;
  await put(env,key,challenge,3600);
}
async function callback(env,q) {
  const match = /^v:(\d+):([a-f0-9-]+):(\d+)$/.exec(q.data || '');
  if (!match || String(q.message?.chat?.id)!==String(env.GROUP_ID)) return;
  const id=Number(match[1]);
  const challenge=await get(env,`join:${id}`);
  if (id!==q.from.id || !challenge || match[2]!==challenge.nonce || challenge.deadline<now()) {
    await telegram(env,'answerCallbackQuery',{callback_query_id:q.id,text:'仅本人可验证；验证码可能已过期。 / Invalid or expired.',show_alert:true}); return;
  }
  if (Number(match[3])!==challenge.answer) {
    await telegram(env,'answerCallbackQuery',{callback_query_id:q.id,text:'答案不正确，请重试。 / Try again.',show_alert:true}); return;
  }
  await telegram(env,'restrictChatMember',{chat_id:env.GROUP_ID,user_id:id,permissions:challenge.permissions,use_independent_chat_permissions:true});
  await put(env,`verified:${id}`,{at:now()},86400*30);
  await drop(env,`join:${id}`);
  await telegram(env,'answerCallbackQuery',{callback_query_id:q.id,text:'验证成功！ / Verified!'});
  if (challenge.message) await telegram(env,'deleteMessage',{chat_id:env.GROUP_ID,message_id:challenge.message});
}
function question(message) {
  const text=(message.text || '').normalize('NFKC').trim();
  if (/^\/(?:ask|search)(?:@ModuReaderRelease_bot)?(?:\s|$)/i.test(text)) return text;
  if (new RegExp('@'+BOT,'i').test(text)) return text.replace(new RegExp('@'+BOT,'ig'),'').trim();
  if (message.reply_to_message?.from?.username?.toLowerCase()===BOT.toLowerCase()) return text;
  return null;
}
async function answer(env,q,message) {
  if (!q) { await send(env,'请使用 /ask 问题，例如：/ask 如何导入 EPUB？\nUse /ask followed by your question.',message); return; }
  if (q.length>1500) { await send(env,'问题请控制在 1500 字以内。 / Maximum 1500 characters.',message); return; }
  if (!await claim(env,`cooldown:${message.from.id}`,30)) { await send(env,'请稍等 30 秒再提问。 / Wait 30 seconds.',message); return; }
  const total=await count(env,`ai:${new Date().toISOString().slice(0,10)}`,86400*2);
  if (total>100) { await send(env,'今天的免费提问额度已用完，UTC 00:00（北京时间 08:00）恢复。请先查看 GitHub 文档。\nDaily question limit reached. Resets at 00:00 UTC.',message); return; }
  const context=String(message.reply_to_message?.text || '').slice(0,2000);
  const route=qqQuestionRoute(q,context),query=qqQuestionText(q);
  await put(env,'tg:last-question',{at:now(),route},86400*7);
  const text=route==='chat' ? await qqChatAnswer(env,String(env.GROUP_ID),query,'tg',String(message.message_id),context)
    : route==='docs' ? await qqDocsAnswer(env,query,context)
    : route==='web' ? await qqWebAnswer(env,query) : QQ_CLARIFY;
  await send(env,text,message);
}
async function handle(env,update) {
  if (update.callback_query) return callback(env,update.callback_query);
  const m=update.message;
  if (!m || String(m.chat.id)!==String(env.GROUP_ID)) return;
  if (m.new_chat_members) { for (const user of m.new_chat_members) await join(env,user); return; }
  if (m.is_automatic_forward) return;
  if (m.sender_chat) {
    if (String(m.sender_chat.id)!==String(env.GROUP_ID)) return;
    // Telegram only lets anonymous group admins send as this group.
    m.from={id:m.sender_chat.id,is_bot:false};
  }
  if (!m.from || m.from.is_bot) return;
  const isAdmin=!!m.sender_chat || await admin(env,m.from.id);
  const text=m.text || m.caption || '';
  if (!isAdmin) {
    if (await get(env,`join:${m.from.id}`)) { await telegram(env,'deleteMessage',{chat_id:env.GROUP_ID,message_id:m.message_id}); return; }
    const flood=await count(env,`flood:${m.from.id}:${Math.floor(now()/10)}`,60);
    if (flood>6) { await telegram(env,'deleteMessage',{chat_id:env.GROUP_ID,message_id:m.message_id}); await mute(env,m.from.id,now()+60); return; }
    if (/(?:t\.me\/\+|t\.me\/joinchat\/|telegram\.me\/joinchat\/)/i.test(text)) { await telegram(env,'deleteMessage',{chat_id:env.GROUP_ID,message_id:m.message_id}); return; }
  }
  if (m.text) await qqArchive(env,String(env.GROUP_ID),{
    id:String(m.message_id),timestamp:new Date(m.date*1000).toISOString(),content:m.text,
    author:{id:String(m.from.id),username:[m.from.first_name,m.from.last_name].filter(Boolean).join(' ') || m.from.username || m.sender_chat?.title || ''},
    message_scene:{ext:[`msg_idx=${m.message_id}`,...(m.reply_to_message ? [`ref_msg_idx=${m.reply_to_message.message_id}`] : [])]},
    msg_elements:m.reply_to_message?.text && !m.reply_to_message.from?.is_bot ? [{content:m.reply_to_message.text}] : []
  },'tg');
  if (/^\/summary-test(?:@ModuReaderRelease_bot)?(?:\s|$)/i.test(text)) {
    if (!isAdmin || !await claim(env,'tg:summary-test-cooldown',600)) return;
    const end=now(),last24h=/\s24h\s*$/i.test(text);
    await put(env,`tg:summary-test-pending:${env.GROUP_ID}`,{id:m.message_id,end,
      start:last24h ? end-86400 : qqWindow(Date.now()).end,last24h},600);
    return;
  }
  if (/^\/(help|start)(?:@ModuReaderRelease_bot)?(?:\s|$)/i.test(text)) return send(env,HELP,m);
  if (/^\/release(?:@ModuReaderRelease_bot)?(?:\s|$)/i.test(text)) return send(env,`📦 最新正式版 / Latest stable release\n${REPO}/releases/latest\n测试版 / All releases: ${REPO}/releases`,m);
  const q=question(m);
  if (q!==null) await answer(env,q,m);
}
export async function telegramSchedule(controller,env) {
  if (!env.BOT_TOKEN || !env.DB || !env.AI) return;
  env={...env,GROUP_ID:env.GROUP_ID || '-1004201042022'};
  const pending=await get(env,`tg:summary-test-pending:${env.GROUP_ID}`);
  if(pending && await claim(env,`tg:summary-test-job:${env.GROUP_ID}:${pending.id}`,86400)) {
    try {
      let text, generated=true;
      try {text=await qqSummary(env,String(env.GROUP_ID),pending,'tg');}
      catch {generated=false;text='反馈汇总暂时不可用，请稍后重试。';}
      await send(env,`🧪 ${pending.last24h ? '过去24小时反馈汇总测试' : '当前阶段反馈汇总测试'}\n${text}`,{message_id:pending.id});
      await put(env,'tg:last-summary-test',{at:now(),ok:generated},86400);
    } catch {await put(env,'tg:last-summary-test',{at:now(),ok:false},86400);}
  }
  const at=controller.scheduledTime || Date.now();
  if (Math.floor(at/60000)%1440!==240) return;
  const window=qqWindow(at);
  if (!await claim(env,`tg:summary:${env.GROUP_ID}:${window.end}`,86400*7)) return;
  try {
    const text=await qqSummary(env,String(env.GROUP_ID),window,'tg');
    await send(env,text);
    await put(env,'tg:last-summary',{at:now(),...window,ok:true},86400*7);
  } catch {
    // Do not retry ambiguous sends or publish an invented recap.
    await put(env,'tg:last-summary',{at:now(),...window,ok:false},86400*7);
  }
}
export default {
  async fetch(request,env,ctx) {
    const qqResponse = await qqRoutes(request,env,ctx);
    if (qqResponse) return qqResponse;
    const url=new URL(request.url);
    if (request.method==='GET' && url.pathname==='/') return json({service:'ModuReader community bot',docs:`${REPO}/tree/main/docs`,commands:['/ask','/release','/help','/summary-test'],summary_times:['12:00 Asia/Shanghai'],summary_window_hours:24,last_summary:env.DB ? await get(env,'tg:last-summary') : null,last_chat:env.DB ? await get(env,'tg:last-chat') : null});
    env={BOT_TOKEN:env.BOT_TOKEN,WEBHOOK_SECRET:env.WEBHOOK_SECRET,TAVILY_API_KEY:env.TAVILY_API_KEY,AI:env.AI,DB:env.DB,GROUP_ID:env.GROUP_ID || '-1004201042022'};
    if (request.method==='POST' && url.pathname==='/diagnostics') {
      if (!env.WEBHOOK_SECRET || request.headers.get('authorization')!==`Bearer ${env.WEBHOOK_SECRET}`) return json({error:'Unauthorized'},401);
      try {
        const me=await telegram(env,'getMe',{});
        const info=await telegram(env,'getWebhookInfo',{});
        const member=await telegram(env,'getChatMember',{chat_id:env.GROUP_ID,user_id:me.id});
        const db=await env.DB.prepare('SELECT COUNT(*) AS records FROM bot_state').first();
        return json({bot:me.username,group:env.GROUP_ID,webhook:info.url,pending:info.pending_update_count,last_error:info.last_error_message || null,role:member.status,can_delete:member.can_delete_messages,can_restrict:member.can_restrict_members,ai_bound:!!env.AI,db_records:db.records});
      } catch (error) {return json({error:error.message},502);}
    }
    if (request.method==='POST' && url.pathname==='/setup') {
      if (!env.WEBHOOK_SECRET || request.headers.get('authorization')!==`Bearer ${env.WEBHOOK_SECRET}`) return json({error:'Unauthorized'},401);
      try {
        const me=await telegram(env,'getMe',{});
        if (me.username!==BOT) return json({error:'Wrong bot credential'},400);
        await telegram(env,'setMyCommands',{commands:[{command:'ask',description:'功能问答 / Ask about ModuReader'},{command:'release',description:'下载最新版 / Latest release'},{command:'help',description:'使用说明 / Help'}]});
        await telegram(env,'setWebhook',{url:'https://modureader-bot.2406.fun/webhook',secret_token:env.WEBHOOK_SECRET,allowed_updates:['message','callback_query'],max_connections:1,drop_pending_updates:false});
        const info=await telegram(env,'getWebhookInfo',{});
        return json({ok:true,bot:me.username,webhook:info.url,pending:info.pending_update_count});
      } catch { return json({error:'Setup failed; check bindings and secrets'},502); }
    }
    if (request.method!=='POST' || url.pathname!=='/webhook') return json({error:'Not found'},404);
    if (!env.WEBHOOK_SECRET || request.headers.get('X-Telegram-Bot-Api-Secret-Token')!==env.WEBHOOK_SECRET) return json({error:'Unauthorized'},401);
    if (Number(request.headers.get('content-length') || 0)>100000) return json({error:'Too large'},413);
    let update;
    try { const raw=await request.text(); if(raw.length>100000) return json({error:'Too large'},413); update=JSON.parse(raw); } catch { return json({error:'Invalid JSON'},400); }
    if (!Number.isSafeInteger(update.update_id)) return json({error:'Invalid update'},400);
    const chat=update.message?.chat?.id ?? update.callback_query?.message?.chat?.id;
    if (String(chat)!==String(env.GROUP_ID)) return json({ok:true});
    try {
      if (!await claim(env,`update:${update.update_id}`,86400)) return json({ok:true});
      await handle(env,update);
      return json({ok:true});
    } catch {
      // Retrying an ambiguous Telegram call could duplicate messages. Keep the update claimed.
      return json({ok:true,handled:false});
    }
  },
  async scheduled(controller,env) {
    await Promise.allSettled([qqSchedule(controller,env),telegramSchedule(controller,env)]);
    env={BOT_TOKEN:env.BOT_TOKEN,WEBHOOK_SECRET:env.WEBHOOK_SECRET,TAVILY_API_KEY:env.TAVILY_API_KEY,AI:env.AI,DB:env.DB,GROUP_ID:env.GROUP_ID || '-1004201042022'};
    const rows=await env.DB.prepare("SELECT key,value FROM bot_state WHERE key LIKE 'join:%'").all();
    for (const row of rows.results) {
      const c=JSON.parse(row.value);
      if(c.deadline>now()) continue;
      try {
        await telegram(env,'banChatMember',{chat_id:env.GROUP_ID,user_id:c.user,until_date:now()+60});
        if(c.message) await telegram(env,'deleteMessage',{chat_id:env.GROUP_ID,message_id:c.message});
        await drop(env,row.key);
      } catch { /* Retry cleanup on next cron tick. No secrets in logs. */ }
    }
    await env.DB.prepare("DELETE FROM bot_state WHERE expires<=? AND key NOT LIKE 'join:%'").bind(now()).run();
  }
};
