// AI 批注助手：解释所选文字，按需存为笔记。
// 使用用户在「设置 → AI」中配置的模型，插件不接触任何 API Key。
var selection = typeof input.selection === "string" ? input.selection.trim() : "";
if (!selection) return { title: "AI 解释", text: "请先选择要解释的文字。" };
if (selection.length > 4000) selection = selection.slice(0, 4000);

var settings = input.settings || {};
var maxChars = parseInt(settings.max_chars, 10);
if (!(maxChars > 0)) maxChars = 400;
if (maxChars > 2000) maxChars = 2000;

var styleHint = {
  plain: "用平实的中文解释，先给一句话结论，再分点展开关键概念。",
  example: "用一个具体的例子贯穿解释，最后总结。",
  exam: "按考点整理：定义、要点、易混淆之处。"
}[settings.style] || "用平实的中文解释。";

var system = "你是阅读辅助工具。" + styleHint +
  "只解释给定文字，不编造事实，不使用 Markdown 标题。总字数不超过 " + maxChars + " 字。";

var context = typeof input.context === "string" ? input.context.trim() : "";
if (context.length > 1200) context = context.slice(0, 1200);

var prompt = (context ? "上下文：\n" + context + "\n\n" : "") +
  "要解释的文字：\n" + selection;

// 模型调用可能较慢，先给一个进度提示。
try {
  await modu.ui.progress({ label: "正在请求模型…", fraction: 0.2 });
} catch (_) {}

var answer = await modu.ai.complete({ prompt: prompt, system: system });
var text = answer && typeof answer.text === "string" ? answer.text.trim() : "";
if (!text) return { title: "AI 解释", text: "模型没有返回内容，请检查 AI 设置。" };

var shouldSave = settings.auto_save === true;
if (!shouldSave) {
  var choice = await modu.ui.confirm({
    title: "保存为批注？",
    message: text.length > 600 ? text.slice(0, 600) + "…" : text
  });
  shouldSave = choice && choice.confirmed === true;
}

var saved = false;
if (shouldSave) {
  try {
    await modu.notes.save({ text: text });
    saved = true;
  } catch (_) {
    // 未在阅读位置运行或用户取消时保存会失败，结果仍然显示。
  }
}

return {
  title: saved ? "AI 解释（已存为批注）" : "AI 解释",
  text: text
};
