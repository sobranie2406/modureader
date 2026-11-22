# 章节速览

阅读时选中任意文字（或直接点击划词工具栏对应动作），在当前书上下文里使用。

## 两个入口

- **本章速览**：`modu.books.content` 取当前章节正文（默认截取 6000 字），交给模型提炼要点，可存为本章批注。
- **问本书**：先 `modu.knowledge.search` 在**本地向量索引**里检索相关片段，再让模型只根据这些片段回答，并要求标注引用编号。

## 演示的宿主接口

| 接口 | 权限 | 用途 |
| --- | --- | --- |
| `modu.books.content({maxCharacters})` | `book:content` | 当前章节正文（上限 12000 字） |
| `modu.knowledge.search({query,limit})` | `knowledge:query` | 本地向量索引检索，5 秒预算 |
| `modu.ai.complete({prompt,system})` | `ai:invoke` | 用户配置的模型 |
| `modu.notes.save({text})` | `note:write` | 存为批注 |
| `modu.ui.confirm` / `ui.progress` | `ui:dialog` / `ui:progress` | 确认与进度 |

## 权限

全部为**运行期权限**，默认关闭。特别说明：

- `book:content` 只能取**当前正在读的这本书**的正文，插件拿不到其他书，也拿不到文件路径。
- `knowledge:query` 依赖宿主建立的本地索引；没建索引时「问本书」会明确提示，不会退回瞎编。
- `ai:invoke` 会消耗你的模型额度。

## 为什么「问本书」要两段式

向量检索在宿主里完成（`knowledge.search`），模型只看到检索到的片段而不是整本书。这样既控制了提示词体积，也让回答可以被片段约束，减少凭空发挥。
