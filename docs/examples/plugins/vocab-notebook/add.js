// 加入生词本：查词典、可选翻译，然后写进插件自己的生词本文件。
var word = typeof input.selection === "string" ? input.selection.trim() : "";
if (!word) return { title: "生词本", text: "请先选择要加入的单词。" };
if (word.length > 64) word = word.slice(0, 64);

var settings = input.settings || {};
var maxEntries = parseInt(settings.max_entries, 10);
if (!(maxEntries > 0)) maxEntries = 300;
if (maxEntries > 1000) maxEntries = 1000;

var STORE = "notebook.json";

// 读旧记录；文件不存在或损坏都从空开始，不让坏文件卡住整个动作。
var entries = [];
try {
  var existing = await modu.storage.read({ name: STORE });
  if (existing && typeof existing.text === "string" && existing.text) {
    var parsed = JSON.parse(existing.text);
    if (Array.isArray(parsed)) entries = parsed;
  }
} catch (_) {}

var now = new Date().toISOString();
var lower = word.toLowerCase();
var found = -1;
for (var i = 0; i < entries.length; i++) {
  if (entries[i] && typeof entries[i].word === "string" &&
      entries[i].word.toLowerCase() === lower) {
    found = i;
    break;
  }
}

var definition = "";
try {
  var looked = await modu.dictionary.lookup({ word: word, limit: 3 });
  if (Array.isArray(looked) && looked.length > 0) {
    definition = String(looked[0].definition || "").trim();
    if (definition.length > 500) definition = definition.slice(0, 500);
  }
} catch (_) {
  // 没装词典时继续，只记单词本身。
}

var translation = "";
if (settings.translate_on_add !== false) {
  try {
    var translated = await modu.translate.text({ text: word });
    if (translated && typeof translated.text === "string") {
      translation = translated.text.trim();
      if (translation.length > 200) translation = translation.slice(0, 200);
    }
  } catch (_) {
    // 翻译失败不影响收录。
  }
}

if (found >= 0) {
  entries[found].definition = definition || entries[found].definition || "";
  entries[found].translation = translation || entries[found].translation || "";
  entries[found].count = (Number(entries[found].count) || 1) + 1;
  entries[found].updatedAt = now;
} else {
  entries.unshift({
    word: word,
    definition: definition,
    translation: translation,
    count: 1,
    createdAt: now,
    updatedAt: now
  });
}

// 新的在前，超出上限时丢弃最旧的。
if (entries.length > maxEntries) entries = entries.slice(0, maxEntries);

var payload = JSON.stringify(entries);
if (payload.length > 200000) {
  entries = entries.slice(0, Math.max(20, Math.floor(entries.length / 2)));
  payload = JSON.stringify(entries);
}
await modu.storage.write({ name: STORE, text: payload });

var lines = [found >= 0 ? "已在生词本中：**" + word + "**" : "已加入生词本：**" + word + "**"];
if (definition) lines.push(definition);
if (translation) lines.push("释义：" + translation);
lines.push("共 " + entries.length + " 条，本次" + (found >= 0 ? "复习" : "新增") + "。");
return { title: "生词本", text: lines.join("\n") };
