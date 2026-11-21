// Ask for anything this package declares but the device has not granted yet.
// Grants start denied, so without this the first run always fails with a bare
// "could not run" and the reader has to find the permission page themselves.
async function ensurePermissions(capabilities, reason) {
  var status = await modu.permissions.status();
  var granted = (status && status.granted) || [];
  var missing = [];
  for (var i = 0; i < capabilities.length; i++) {
    if (granted.indexOf(capabilities[i]) < 0) missing.push(capabilities[i]);
  }
  if (missing.length === 0) return true;
  var answer = await modu.permissions.request({
    capabilities: missing,
    reason: reason
  });
  return !!answer && Array.isArray(answer.granted) && answer.granted.length > 0;
}

// 本章速览：读取当前章节正文，交给用户自己的模型提炼要点。
var allowed = await ensurePermissions(["book:content", "ai:invoke", "note:write"],
    "要总结本章，需要正文、模型与保存笔记。");
if (!allowed) {
  return { title: "本章速览", text: "需要正文、模型与笔记权限。" };
}

var settings = input.settings || {};
var maxChars = parseInt(settings.max_chars, 10);
if (!(maxChars > 0)) maxChars = 6000;
if (maxChars > 12000) maxChars = 12000;
var bullets = parseInt(settings.bullets, 10);
if (!(bullets > 0)) bullets = 5;
if (bullets > 10) bullets = 10;

// 当前章节正文；私密书籍未解锁时宿主会拒绝。
var chapter = await modu.books.content({ maxCharacters: maxChars });
var text = chapter && typeof chapter.text === "string" ? chapter.text.trim() : "";
if (!text) {
  return { title: "本章速览", text: "没有取到本章正文，请确认正在阅读一本书。" };
}
var chapterName = typeof chapter.chapter === "string" ? chapter.chapter.trim() : "";

try {
  await modu.ui.progress({ label: "正在提炼要点…", fraction: 0.3 });
} catch (_) {}

var system = "你是阅读辅助工具。用中文输出 " + bullets + " 条要点，" +
  "每条一行，以「- 」开头，不复述原文长句，不编造未出现的内容。";
var prompt = (chapterName ? "章节：" + chapterName + "\n\n" : "") + "正文：\n" + text;

var answer = await modu.ai.complete({ prompt: prompt, system: system });
var summary = answer && typeof answer.text === "string" ? answer.text.trim() : "";
if (!summary) return { title: "本章速览", text: "模型没有返回内容，请检查 AI 设置。" };

var save = await modu.ui.confirm({
  title: "存为批注？",
  message: "会把这段速览保存为本章的一条批注。"
});
var saved = false;
if (save && save.confirmed === true) {
  try {
    await modu.notes.save({ text: summary });
    saved = true;
  } catch (_) {}
}

var head = chapterName ? "《" + chapterName + "》速览" : "本章速览";
return { title: saved ? head + "（已存为批注）" : head, text: summary };
