# 查词预处理

原词优先查询，未命中的字典再依次尝试候选词。例如 `apples → apple`、`approves → approve`、`studies → study`、`stopped → stop`，以及 `l’épaule → épaule`。

在插件设置中可分别开关英语词形和法语前缀处理。自定义正则填写 JSON 数组，按顺序从原词生成候选：

```json
[{"pattern":"^s['’]","replacement":"","flags":"i"},{"pattern":"s$","replacement":"","flags":"i"}]
```

`pattern` 是匹配表达式，`replacement` 是替换文字（可用 `$1` 捕获组），`flags` 可选 `g`、`i`、`m`、`s`、`u`。自定义候选排在内置候选前。插件只处理查询词，不读取书籍或联网。
