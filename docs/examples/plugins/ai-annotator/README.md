# AI 批注助手

在阅读界面选中文字，点击划词工具栏的「AI 解释并存为批注」。

## 流程

1. `modu.ui.progress` 先给出「正在请求模型…」提示。
2. `modu.ai.complete` 用**你自己在「设置 → AI」里配置的模型**生成解释。
3. 默认再问一次「保存为批注？」，确认后调用 `modu.notes.save`。
4. 结果弹窗里可以复制。

## 演示的宿主接口

| 接口 | 权限 | 用途 |
| --- | --- | --- |
| `modu.ai.complete({prompt,system})` | `ai:invoke` | 调用用户配置的模型 |
| `modu.notes.save({text})` | `note:write` | 存为当前划线的批注（宿主确认） |
| `modu.ui.confirm({title,message})` | `ui:dialog` | 保存前询问 |
| `modu.ui.progress({label,fraction})` | `ui:progress` | 长任务进度提示 |

## 权限

全部是**运行期权限**，安装后默认关闭：

- `ai:invoke` 会消耗你自己的模型额度，因此被标为需要额外确认的危险权限。插件拿不到 API Key，也看不到模型配置。
- `note:write` 会让宿主在写入前弹确认框，笔记最后绑定到真实的书籍与阅读位置。
- `ui:dialog` / `ui:progress` 只影响界面，不改数据。

## 设置

- **解释风格**：plain / example / exam，对应三种提示词。
- **回答上限（字）**：截断长度提示，最多 2000。
- **无需确认直接存为批注**：默认关闭，打开后跳过确认框。

## 说明

`ai.complete` 是**同步等待**的：脚本会一直等到模型返回，期间执行计时暂停，因此慢模型不会导致插件超时。
