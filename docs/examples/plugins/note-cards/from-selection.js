// 查找相关批注：用所选文字搜索整个书库的笔记与书名。
var query = typeof input.selection === "string" ? input.selection.trim() : "";
if (!query) return { title: "查找相关批注", text: "请先选择要查找的文字。" };
if (query.length > 200) query = query.slice(0, 200);

var result = await modu.search.library({ query: query, limit: 20, includeNotes: true });
var notes = Array.isArray(result && result.notes) ? result.notes : [];
var books = Array.isArray(result && result.books) ? result.books : [];

if (notes.length === 0 && books.length === 0) {
  return { title: "查找相关批注", text: "没有找到与“" + query + "”相关的批注或书籍。" };
}

function clean(value) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
}

var lines = [];
if (books.length > 0) {
  lines.push("相关书籍：");
  for (var i = 0; i < books.length; i++) {
    lines.push("- 《" + clean(books[i].title) + "》");
  }
  lines.push("");
}
if (notes.length > 0) {
  lines.push("相关批注：");
  for (var j = 0; j < notes.length; j++) {
    var note = notes[j];
    var text = clean(note.text);
    if (!text) continue;
    if (text.length > 160) text = text.slice(0, 160) + "…";
    lines.push("- " + text + "（《" + clean(note.bookTitle) + "》）");
  }
}
return { title: "与“" + query + "”相关", text: lines.join("\n").trim() };
