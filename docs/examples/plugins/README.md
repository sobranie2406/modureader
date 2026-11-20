# 插件示例

这里是为了演示 **P6 新增宿主接口**而写的示例插件，每个都覆盖一组不同的能力。

它们可以直接用默读的「插件 → 开发者调试」导入本机验证：

```sh
# 在默读源码目录打包
dart run scripts/dev/pack_plugin.dart docs/examples/plugins/reading-stats
dart run scripts/dev/pack_plugin.dart docs/examples/plugins/note-cards
dart run scripts/dev/pack_plugin.dart docs/examples/plugins/ai-annotator
dart run scripts/dev/pack_plugin.dart docs/examples/plugins/vocab-notebook
dart run scripts/dev/pack_plugin.dart docs/examples/plugins/chapter-digest
```

打包产物是同目录下的 `<目录名>-<版本>.moduplugin`，在「插件 → 开发者调试」中导入即可。
本机调试包不进入官方目录，也不参与同步与备份。

## 一览

| 插件 | 演示的新接口 | 运行期权限 |
| --- | --- | --- |
| [阅读统计卡](reading-stats/) | `reading.stats`、`clipboard.write` | `reading:read`、`clipboard:write` |
| [批注整理](note-cards/) | `notes.list`、`search.library`、`share.text` | `note:read`、`search:library`、`share:text`、`library:read` |
| [AI 批注助手](ai-annotator/) | `ai.complete`、`notes.save`、`ui.confirm`、`ui.progress` | `ai:invoke`、`note:write`、`ui:dialog`、`ui:progress` |
| [生词本](vocab-notebook/) | `storage.*`、`dictionary.lookup`、`translate.text`、`ui.select` | `dictionary:lookup`、`translate:invoke`、`ui:dialog`、`clipboard:write` |
| [章节速览](chapter-digest/) | `books.content`、`knowledge.search`、`ai.complete` | `book:content`、`knowledge:query`、`ai:invoke`、`note:write` |

## 权限模型要点

安装插件只授予「随安装生效」的能力（脚本执行、菜单入口等）。上表列出的能力都是**运行期权限**，
安装后**默认关闭**，需要在「插件 → 详情 → 权限」中逐项开启，脚本才能调用对应接口。

- 未授权时调用返回 `denied`，UI 会提示去开权限，而不是显示插件损坏。
- 撤回授权会立即取消该插件正在运行的任务。
- 授权属于本机：不导出、不备份、不同步。
- 旧版本就已存在的插件会按原有能力补齐授权，之后新增的能力一律默认关闭。

## 与官方仓库的关系

这些示例演示的是**宿主接口**，不是审核上架记录。正式分发仍按
[插件审核与上架](../../development/plugin-trust.md) 的流程：提交源码、审核、更新文件指纹、签名清单。
官方插件源码在 <https://github.com/sobranie2406/modu-plugin>。
