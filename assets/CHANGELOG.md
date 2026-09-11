# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.0.3

- Download local embedding models on demand with size and SHA-256 verification; installers no longer include weights. Automatic indexing remains off.
- Persist remote-library credentials locally; include library configuration in encrypted backups and optional encrypted API-key sync, never plain backups.
- Use bundled official provider icons, including recognized custom endpoints, with a generic fallback.
- Fix desktop reader keyboard focus with the AI panel open; preserve cursor movement inside input fields.
- Show Android selection tools after the initial long press; wait for chapter fonts before revealing text, with a bounded fallback.
- Scroll-mode page turns retain 20 percent overlap. Use local sync timestamps; refresh saved WebDAV addresses and fix backup-dialog Cancel.

- 本地向量模型改为按需下载，校验大小和 SHA-256；安装包不再内嵌权重，自动向量化仍默认关闭。
- 远程书库密码保存在本地；配置参与加密备份及可选的 API Key 加密同步，不进入明文备份。
- 使用本地打包的官方服务商图标，自定义接口可识别对应品牌，无法识别时使用通用图标。
- 修复桌面 AI 面板打开后的阅读器方向键焦点；输入框中的方向键仍正常移动光标。
- 安卓首次长按选字即可弹出工具栏，无需拖动手柄；章节字体就绪后再显示正文，并保留超时回退。
- 滚动翻页保留 20% 重叠；同步时间统一为本地时区，WebDAV 保存后立即刷新地址，修复备份弹窗取消按钮。
