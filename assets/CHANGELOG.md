# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.0.5

- Reject stale reading-position writes after sync; preserve intentional backward reading.
- Keep note drafts on conflicts instead of overwriting newer or deleted notes.
- Support unreliable ETag servers through verified immutable record batches; retain conditional writes for reliable servers.
- Prepare chapter fonts and layout before switching pages; remove unnecessary transition delays.
- Include Anx progress compatibility, book-end boundaries and per-book embedding model selection; keep four offline models bundled.
- Back up and upgrade every syncing device to 1.0.5; older clients cannot read the compatible record log.

- 同步后拒绝旧页面进度回写，主动往回阅读仍正常保存。
- 笔记冲突时保留草稿，不覆盖新版或恢复已删除笔记。
- 无可靠 ETag 服务使用校验过的独立记录批次，可靠服务仍使用条件写入。
- 新章节字体和布局就绪后再切换页面，减少不必要的切章等待。
- 纳入 Anx 进度兼容、书末边界和每书向量模型选择，保留四个内嵌离线模型。
- 请先备份并将所有同步设备升级到 1.0.5，旧版不能读取兼容记录通道。
