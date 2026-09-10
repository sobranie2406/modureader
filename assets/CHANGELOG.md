# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.0.2

- Merge WebDAV records instead of replacing the local database; sync the latest reading action, deduplicate new reading time and retain deletion markers. Fonts stay local.
- Back up all devices and the server before upgrading every syncing client; database 8 requires server ETags and conditional writes.
- Fix database initialization and local fonts with spaces or non-ASCII characters in their filenames.
- Move translation next to AI; use readable text sizes and a scrollable popup matching AI chat.
- Sort and filter the remote library; transfer library WebDAV settings through codes or QR images. Password export is on by default; codes are not encrypted.
- Add a mobile tap-only page-turn switch and prevent accidental page dragging. See the GitHub Release for package and verification limits.

- WebDAV 改为逐条合并，使用最近阅读操作、新时长去重与删除标记，不再替换本机整库；字体留在本机。
- 升级前备份各端和服务器，所有同步设备一起升级；数据库 8 要求服务器支持 ETag 与条件写入。
- 修复数据库初始化，以及含空格或中文等字符的本地字体文件加载。
- 翻译入口移到 AI 旁，统一字号并采用与 AI 对话一致的可滚动弹窗。
- 远程书库支持排序筛选及代码、二维码配置迁移。默认导出密码，代码未加密，请勿公开。
- 移动端新增仅点击翻页开关，防止误拖页面；安装要求和验证限制见 GitHub Release。
