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

// 批注整理：把划线与批注按书汇总成复习清单。
// 只读取当前可读的书籍与笔记；私密书籍在未解锁时不会出现。
var allowed = await ensurePermissions(["note:read"],
    "汇总批注需要读取你的笔记。");
if (!allowed) {
  return { title: "批注汇总", text: "需要读取笔记的权限。" };
}

var settings = input.settings || {};
var limit = parseInt(settings.limit, 10);
if (!(limit > 0)) limit = 40;
if (limit > 50) limit = 50;

var notes = await modu.notes.list({ limit: limit });
if (!Array.isArray(notes) || notes.length === 0) {
  return { title: "批注整理", text: "书库里还没有划线与批注。" };
}

// 按书分组，保留接口返回的顺序（越新的笔记越靠前）。
var order = [];
var groups = {};
for (var i = 0; i < notes.length; i++) {
  var note = notes[i];
  var key = String(note.bookId);
  if (!groups[key]) {
    groups[key] = { title: note.bookTitle || "未命名", items: [] };
    order.push(key);
  }
  groups[key].items.push(note);
}

function clean(value) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
}

var lines = [];
var count = 0;
for (var g = 0; g < order.length; g++) {
  var group = groups[order[g]];
  if (group.items.length === 0) continue;
  lines.push("《" + group.title + "》");
  for (var k = 0; k < group.items.length; k++) {
    var item = group.items[k];
    var text = clean(item.text);
    if (!text) continue;
    if (text.length > 200) text = text.slice(0, 200) + "…";
    var chapter = clean(item.chapter);
    var line = "- " + text;
    if (chapter) line += "（" + chapter + "）";
    var own = clean(item.note);
    if (settings.with_note !== false && own) {
      line += "\n  批注：" + (own.length > 200 ? own.slice(0, 200) + "…" : own);
    }
    lines.push(line);
    count++;
  }
  lines.push("");
}
if (count === 0) {
  return { title: "批注整理", text: "没有可整理的批注内容。" };
}

var text = lines.join("\n").trim();
if (settings.share === true) {
  try {
    await modu.share.text({ text: text, subject: "批注整理" });
  } catch (_) {
    // 分享失败不影响清单本身。
  }
}
return { title: "批注整理 · " + count + " 条", text: text };
