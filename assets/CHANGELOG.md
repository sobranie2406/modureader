# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.0.7-preview.1

- Tighten iframe permissions when EPUB scripts are disabled; retain scoped WebKit event compatibility and content sanitization.
- Coalesce AI streaming updates, reuse unchanged Markdown, normalize typography and hide skill prompts by default.
- Require local book files before indexing and skip unavailable books in batch requests.
- Add reading-only timed sync and terminal-only sync feedback.
- Disable all book-opening transitions with one setting and export mind maps as PNG, SVG, Markdown, FreeMind or JSON.
- Add bounded continuous chapter scrolling for horizontal reflowable books with scripts disabled; keep speech bound to its original chapter until it finishes.

- 收紧 EPUB 脚本关闭时的 iframe 权限；WebKit 保留受控事件兼容，书籍脚本仍受清理和禁用策略约束。
- AI 输出合并高频刷新、减少重复渲染，统一字号；技能提示词默认收起。
- 向量化前检查本地书籍，未下载时明确提示；批量操作跳过缺失文件。
- 阅读时定时同步支持 1、2、3、5、10、15、30 分钟及 1 小时；同步仅提示最终结果。
- 完整关闭打开书籍的动画；思维导图支持 PNG、SVG、Markdown、FreeMind 和 JSON 导出。
- 横排流式书籍在关闭书籍脚本时支持跨章连续滚动，限制预排版窗口；TTS 保持原章节游标，读完后再续章。
