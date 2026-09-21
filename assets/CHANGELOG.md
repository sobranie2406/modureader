# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.1.1

- Reserve floating navigation space on every home tab, including large text and system safe areas; hide navigation while typing.
- Vertical reading gains optional red frames, column rules, side headers/footers and Chinese page numbers; fix macOS click handling.
- Footnotes use 80% of actual paragraph text size, not reference-marker size; vertical notes scroll horizontally within the 25% area limit.
- Verified Android data migration to Android/data/com.modu.reader/files, retaining private credentials and the original recovery copy.
- Delete downloaded embedding models and stream larger local indexes; remove WebDAV vector index sync while preserving local indexes.
- Recoverable cleanup of replaced cloud book files; books, notes and reading progress continue to sync.
- Stable build 10033. Models remain on-demand; updates prefer Gitee with SHA-256 verification and GitHub fallback.

- 首页各标签统一避让底部悬浮导航，适配大字体和系统安全区；输入时隐藏导航。
- 竖排新增可选红框、分栏线、左右页眉页脚和中文页码，修复 macOS 点击交互。
- 注释字号取实际段落正文的 80%，不取注释序号；竖排注释横向滚动，保留屏幕 25% 面积上限。
- Android 数据校验迁移至 Android/data/com.modu.reader/files，密钥仍保留私有目录，旧数据保留用于恢复。
- 可删除已下载模型，以流式方式读取更大本地索引；移除 WebDAV 向量索引同步，保留本地索引。
- 替换后的云端旧书文件采用可恢复清理；书籍、笔记和阅读进度继续同步。
- 正式版构建 10033；模型继续按需下载，应用更新优先 Gitee，校验 SHA-256 并支持 GitHub 回退。
