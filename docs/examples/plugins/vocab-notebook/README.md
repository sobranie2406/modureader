# 生词本

插件自己维护一本生词本，数据存在**插件的私有目录**里，不进书库、不进同步、不进设置备份。

## 两个入口

- **加入生词本**：选中单词后运行。查本地词典取释义，可选调用翻译引擎，写入 `notebook.json`。同一个词再次加入会累加复习次数。
- **复习生词本**：列出全部生词，可选复制到剪贴板或清空。

## 演示的宿主接口

| 接口 | 权限 | 用途 |
| --- | --- | --- |
| `modu.storage.read({name})` | `storage:plugin` | 读回上次保存的生词本 |
| `modu.storage.write({name,text})` | `storage:plugin` | 保存生词本 |
| `modu.storage.remove({name})` | `storage:plugin` | 清空 |
| `modu.dictionary.lookup({word,limit})` | `dictionary:lookup` | 查已安装的本地词典 |
| `modu.translate.text({text})` | `translate:invoke` | 用用户配置的翻译引擎 |
| `modu.ui.select` / `ui.confirm` | `ui:dialog` | 复习时选择动作 |
| `modu.clipboard.write` | `clipboard:write` | 复制词表 |

## 权限

- `storage:plugin` 是**安装即授予**：每个插件本来就拥有自己的私有目录。
- `dictionary:lookup`、`translate:invoke`、`ui:dialog`、`clipboard:write` 都是**运行期权限**，默认关闭。关掉翻译后依然能收词，只是没有译文。

## 存储限制

宿主对 `storage.*` 的限制：文件名只能是平铺的 `*.json`（最多 64 字符），单文件 256 KiB，最多 200 个文件、合计 4 MiB。写超限会失败而不是静默丢失；本插件在此之上再做一次按条数截断（默认 300 条）。

卸载插件会连带删除这个目录。
