// 复习生词本：列出保存的单词，可复制或清空。
var STORE = "notebook.json";
var entries = [];
try {
  var existing = await modu.storage.read({ name: STORE });
  if (existing && typeof existing.text === "string" && existing.text) {
    var parsed = JSON.parse(existing.text);
    if (Array.isArray(parsed)) entries = parsed;
  }
} catch (_) {}

if (entries.length === 0) {
  return { title: "生词本", text: "生词本还是空的。选中单词后点「加入生词本」。" };
}

var settings = input.settings || {};
var limit = parseInt(settings.max_entries, 10);
if (!(limit > 0)) limit = 300;

var lines = ["共 " + entries.length + " 个生词：", ""];
for (var i = 0; i < entries.length && i < limit; i++) {
  var entry = entries[i] || {};
  var word = String(entry.word || "").trim();
  if (!word) continue;
  var line = (i + 1) + ". " + word;
  var brief = String(entry.translation || entry.definition || "").trim();
  if (brief) {
    if (brief.length > 80) brief = brief.slice(0, 80) + "…";
    line += " — " + brief;
  }
  var times = Number(entry.count) || 1;
  if (times > 1) line += "（复习 " + times + " 次）";
  lines.push(line);
}
var text = lines.join("\n");

// 询问是否复制或清空；用户取消时只显示列表。
var action = null;
try {
  action = await modu.ui.select({
    title: "生词本",
    options: ["只查看", "复制到剪贴板", "清空生词本"]
  });
} catch (_) {}

var selected = action && typeof action.selected === "string" ? action.selected : "只查看";
if (selected === "复制到剪贴板") {
  try {
    await modu.clipboard.write({ text: text });
    text += "\n\n（已复制到剪贴板）";
  } catch (_) {}
} else if (selected === "清空生词本") {
  var ok = await modu.ui.confirm({
    title: "清空生词本？",
    message: "将删除全部 " + entries.length + " 个生词，无法撤销。"
  });
  if (ok && ok.confirmed === true) {
    await modu.storage.remove({ name: STORE });
    return { title: "生词本", text: "生词本已清空。" };
  }
}

return { title: "生词本 · " + entries.length + " 条", text: text };
