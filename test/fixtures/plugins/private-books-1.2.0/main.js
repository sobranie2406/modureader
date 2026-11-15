if (input.actionId === "open") {
  await modu.privateLibrary.open();
  return {title: "私密书籍", text: ""};
}
if (input.actionId === "lock") {
  await modu.privateLibrary.lock();
  return {title: "私密书籍", text: "已锁定私密书籍。"};
}
if (input.actionId !== "add" && input.actionId !== "remove") {
  throw new Error("Unknown private library action");
}
const makePrivate = input.actionId === "add";
const books = await modu.privateLibrary.selectBooks({private: !makePrivate});
if (!Array.isArray(books) || books.length > 100 || books.some(book =>
  !book || !Number.isSafeInteger(book.id) || book.id <= 0)) {
  throw new Error("Invalid book selection");
}
if (books.length === 0) return {title: "私密书籍", text: ""};
const bookIds = Array.from(new Set(books.map(book => book.id)));
await modu.privateLibrary.setPrivate({
  bookIds,
  private: makePrivate,
  lockAfter: makePrivate && (!input.settings || input.settings.lock_after_hide !== false),
});
return {title: "私密书籍", text: makePrivate ? "已加入私密书籍。" : "已移出私密书籍。"};
