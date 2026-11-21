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

// 阅读报告：汇总 reading.stats，可选用 clipboard.write 复制。
// 只读取本机阅读时长，不接触书籍正文。
var allowed = await ensurePermissions(["reading:read"],
    "生成阅读报告需要读取阅读时长。");
if (!allowed) {
  return { title: "阅读报告", text: "需要读取阅读时长的权限。" };
}

var settings = input.settings || {};
var days = parseInt(settings.days, 10);
if (!(days > 0) || days > 365) days = 30;
var topCount = parseInt(settings.top_books, 10);
if (!(topCount > 0)) topCount = 5;
if (topCount > 20) topCount = 20;

var stats = await modu.reading.stats({ days: days });
var totalSeconds = Number(stats && stats.totalSeconds) || 0;
var books = Array.isArray(stats && stats.books) ? stats.books : [];

function formatHours(seconds) {
  var minutes = Math.round(seconds / 60);
  if (minutes < 60) return minutes + " 分钟";
  var hours = Math.floor(minutes / 60);
  var rest = minutes % 60;
  return rest === 0 ? hours + " 小时" : hours + " 小时 " + rest + " 分钟";
}

var lines = [];
lines.push("最近 " + days + " 天共阅读 " + formatHours(totalSeconds) + "。");
if (books.length === 0) {
  lines.push("这段时间还没有阅读记录。");
} else {
  lines.push("");
  lines.push("书目排行：");
  for (var i = 0; i < books.length && i < topCount; i++) {
    var book = books[i];
    var title = typeof book.title === "string" && book.title ? book.title : "未命名";
    lines.push((i + 1) + ". " + title + " — " + formatHours(Number(book.seconds) || 0));
  }
}
var text = lines.join("\n");

if (settings.copy !== false) {
  try {
    await modu.clipboard.write({ text: text });
  } catch (_) {
    // 复制失败不影响报告本身。
  }
}

return { title: "阅读报告 · 最近 " + days + " 天", text: text };
