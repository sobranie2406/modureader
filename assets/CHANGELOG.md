# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.0.8

- Display footnotes at 80% of the reader font size, retaining the area cap and end padding.
- Ignore known system sidecar files in WebDAV sync logs while retaining real record validation.
- Remove AI reasoning from translations; add explicit stop controls and prevent automatic restart after reopening.
- List search results without changing reading position until a result is selected.
- Reclaim explicitly replaced remote book paths only after verification and creation of a recovery copy; recovery copies still use cloud storage.
- Correct WebDAV deletion paths containing special characters.
- Keep all four offline embedding models bundled. Stable release, build 10026.

- 弹出注释字号调整为正文的 80%，保留面积上限和底部留白。
- WebDAV 同步记录扫描忽略明确的系统辅助文件，保留真实数据校验，无需清空云端。
- 翻译过滤 AI 思考内容，提供停止入口，重新打开书籍不会自动恢复翻译。
- 搜索只展示结果，用户选择后才跳转，不自动改变阅读位置。
- 明确替换过的远程书籍文件经校验并保存恢复副本后才移除旧路径；恢复副本仍占用云端空间。
- 修正包含特殊字符的 WebDAV 删除路径。
- 保留四个内嵌离线向量模型。正式版，构建号 10026。
