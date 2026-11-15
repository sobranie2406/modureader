# 示例提示词包

启用后，AI 提示词中会出现「深度摘要」和「苏格拉底提问」，划词工具栏中会出现「简明解释」。

在插件设置中调整回答语气、最大字数和是否引用原文。三个动作都会在运行时使用当前设置；默认简洁表达，最多 300 字，不引用原文。

提示词使用 `{setting.tone}`、`{setting.max_words}`、`{setting.quote_original}`，划词动作另用 `{selection}`。修改提示词或默认设置时，增加插件版本号，审核后即可独立更新。

本包没有执行脚本，使用 CC0-1.0 许可。安装、设置和开发方式见[插件开发规范](https://github.com/sobranie2406/modu-plugin/blob/main/DEVELOPMENT.md)。
