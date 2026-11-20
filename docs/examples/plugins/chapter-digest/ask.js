// 问本书：用本地向量索引检索相关内容，再让模型基于检索结果回答。
var question = typeof input.selection === "string" ? input.selection.trim() : "";
if (!question) return { title: "问本书", text: "请先选中一个要问的问题。" };
if (question.length > 500) question = question.slice(0, 500);

try {
  await modu.ui.progress({ label: "正在检索本书…", fraction: 0.25 });
} catch (_) {}

var hits = [];
try {
  var searched = await modu.knowledge.search({ query: question, limit: 5 });
  if (searched && Array.isArray(searched.results)) hits = searched.results;
} catch (_) {
  // 没有建立索引时继续，退化为普通问答。
}

if (hits.length === 0) {
  return {
    title: "问本书",
    text: "本书还没有可用的检索索引。请先在书籍菜单里建立索引后再试。"
  };
}

var context = [];
for (var i = 0; i < hits.length; i++) {
  var snippet = hits[i] && typeof hits[i].text === "string" ? hits[i].text.trim() : "";
  if (!snippet) continue;
  if (snippet.length > 800) snippet = snippet.slice(0, 800);
  context.push("[" + (i + 1) + "] " + snippet);
}
if (context.length === 0) {
  return { title: "问本书", text: "检索没有返回可用内容。" };
}

var system = "只根据给出的原文片段回答。若片段不足以回答，明确说明缺少什么，" +
  "不要用常识补足。回答后用 [编号] 标注引用的片段。";
var prompt = "问题：" + question + "\n\n原文片段：\n" + context.join("\n\n");

var answer = await modu.ai.complete({ prompt: prompt, system: system });
var text = answer && typeof answer.text === "string" ? answer.text.trim() : "";
if (!text) return { title: "问本书", text: "模型没有返回内容，请检查 AI 设置。" };
return { title: "问本书", text: text };
