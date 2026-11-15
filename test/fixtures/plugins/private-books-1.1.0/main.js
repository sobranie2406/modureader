if (input.actionId === "open") {
  await modu.privateLibrary.open();
  return {title: "私密书籍", text: ""};
}
if (input.actionId === "lock") {
  await modu.privateLibrary.lock();
  return {title: "私密书籍", text: "已锁定私密书籍。"};
}
throw new Error("Unknown private library action");
