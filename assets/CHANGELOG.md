# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.0.7

- Move book search between Translation and Bookmark; highlight matches in the text with previous/next navigation, current/total count, return-to-origin and close controls.
- Restore visible skill shortcuts in AI chat; display skill names instead of full prompt bodies without changing model requests.
- Refine reader navigation history and desktop keyboard handling; move Windows native embedding work off the platform thread (Windows runtime verification pending).
- Add a Spotlight-style floating book search dialog with keyboard-aware layout and Escape/outside-click dismissal.
- Use selection-style text highlights for exact search ranges, including inline-tag and chapter-end matches; scale footnote text to 70% of the reader font size while retaining the area cap and end padding.
- Correct annotation overlay origins and refresh marks when cached chapters are activated or internally scrolled.
- Stable release, build 10025.

- Tighten iframe permissions when EPUB scripts are disabled; retain scoped WebKit event compatibility and content sanitization.
- Coalesce AI streaming updates, reuse unchanged Markdown and normalize typography.
- Require local book files before indexing and skip unavailable books in batch requests.
- Add reading-only timed sync and terminal-only sync feedback.
- Disable all book-opening transitions with one setting and export mind maps as PNG, SVG, Markdown, FreeMind or JSON.
- Add bounded continuous chapter scrolling for horizontal reflowable books with scripts disabled; keep speech bound to its original chapter until it finishes.
- Stop registering Android web links; preserve local book opening and explicit file sharing.
- Prepare adjacent long chapters earlier and fix repeated page turns from chapter-boundary taps; retain the speaking document when restoring cached chapters.

- 书内搜索独立放在翻译与书签之间；正文高亮匹配，底部提供上一处、下一处、当前/总数、返回原处及关闭。
- AI 对话恢复默认显示技能标签；技能消息仅展示名称，隐藏长提示词正文，不改变实际模型请求。
- 调整阅读导航历史和桌面键盘处理；Windows 原生向量化移至后台工作线程（尚待 Windows 实机验证）。
- 书内搜索改为聚焦搜索风格的浮动弹框，适配键盘弹出，支持 Esc 和点击框外关闭。
- 搜索匹配改为文字选中式底色，修正跨标签和章末匹配范围，不再绘制外围框；注释字号为正文的 70%，保留面积限制和底部留白。
- 修正跨章批注图层原点，缓存章节恢复和内部滚动时更新标记，避免跨章偏移。
- 正式版，构建号 10025。
- 收紧 EPUB 脚本关闭时的 iframe 权限；WebKit 保留受控事件兼容，书籍脚本仍受清理和禁用策略约束。
- AI 输出合并高频刷新、减少重复渲染，统一字号。
- 向量化前检查本地书籍，未下载时明确提示；批量操作跳过缺失文件。
- 阅读时定时同步支持 1、2、3、5、10、15、30 分钟及 1 小时；同步仅提示最终结果。
- 完整关闭打开书籍的动画；思维导图支持 PNG、SVG、Markdown、FreeMind 和 JSON 导出。
- 横排流式书籍在关闭书籍脚本时支持跨章连续滚动，限制预排版窗口；TTS 保持原章节游标，读完后再续章。
- 取消安卓普通网页链接关联，保留本地书籍打开和主动分享文件导入。
- 提前预排版长章节的前后邻章，修复章末点击重复翻页；恢复缓存章节时保留正在朗读的文档。
