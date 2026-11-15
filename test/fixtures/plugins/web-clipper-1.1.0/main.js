if (input.actionId !== "capture") throw new Error("Unknown article action");
await modu.articles.capture({});
return {title: "网页稍后阅读", text: ""};
