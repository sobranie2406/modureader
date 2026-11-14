var text = typeof input.selection === "string" ? input.selection : "";
text = text.replace(/\r\n?/g, "\n").replace(/[\t ]+/g, " ");
if (!input.settings || input.settings.trim_lines !== false) {
  text = text.split("\n").map(function (line) { return line.trim(); }).join("\n");
}
return {title: "整理文字", text: text.trim()};
