# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.1.4

- Save or clear speech settings and transfer saved providers, keys, voices and playback parameters through private QR images or Modu configuration links.
- Skills stay hidden until the sparkle button opens a vertical in-chat picker; selection closes it without discarding your draft.
- Fix Android native playback state and media-key routing; apply wake locks when the player is created lazily.
- Skip recognizable footnotes, note references and punctuation-only speech segments; genuine synthesis failures still preserve the reading position.
- Refresh replaced-book identities and transfer state to avoid duplicate uploads/downloads and stale completion indicators; safely clean confirmed obsolete files.
- Improve chapter loading and continuous scrolling without using substitute fonts; reader menus overlay text without reflowing it.
- Refresh vertical column rules on initial layout, raise the mobile reader toolbar, and isolate macOS dimming from title-bar and input handling.
- GitHub remains the primary update source and Gitee the verified fallback. Models remain on demand. Upgrade in place without uninstalling or clearing data.

- 新增朗读设置保存、清除，以及私密二维码图片和默读配置链接迁移，包含服务、密钥、声音及语音参数。
- 技能默认隐藏，点击星光按钮后在对话框内纵向展开；选择后收起并保留输入草稿。
- 修复 Android 原生播放状态与媒体按键控制，补齐播放器延迟创建时的唤醒锁。
- 跳过可识别脚注、注释编号与纯标点段落；真正的合成失败仍保留阅读位置。
- 刷新替换书籍的文件身份与传输状态，避免重复上传、下载和完成状态卡住；安全清理已确认过期文件。
- 优化章节加载与连续滚动，不使用替代字体；阅读菜单覆盖显示，不再引发正文重排。
- 修复首次竖排分栏线布局，抬高移动端阅读底部菜单，并隔离 macOS 调光层与标题栏、输入事件。
- 更新继续优先 GitHub，失败后使用经过校验的 Gitee 镜像；模型按需下载，请覆盖升级，不卸载或清空数据。
