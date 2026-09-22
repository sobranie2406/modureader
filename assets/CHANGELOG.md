# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.1.3

- Fix Edge reading cache preparation on immutable configuration, distinguish system voices by name and locale, and add contextual Android notification permission requests plus a settings entry.
- TXT note exports separate reader notes from excerpts with labelled rules and local creation/last-modified timestamps; legacy unknown times are not fabricated.
- Reading notifications show book/chapter and previous, play/pause, next and exit controls; paused controls remain available and speech-driven chapter metadata follows background playback.
- Compact reader brightness controls: follow-system toggle, slider and night mode; night mode preserves and restores the original palette and background.
- Separate Chinese/body and English fonts, with independent import/application and legacy-compatible defaults; supports reflowable text and footnotes.
- Eight named, editable CSS profiles; per-book choices on this device, shared defaults and legacy CSS preservation.
- Update checks and downloads prefer GitHub and fall back to Gitee for all network, timeout, TLS and HTTP request failures, including 403 and 404.
- Preserve HTTPS verification, matching version/architecture, size and SHA-256 checks; cancellation, invalid metadata and local errors still stop safely.
- Distinguish rate limiting from access denial instead of labelling every 403 as throttling.
- Remove old Gitee application releases before publishing each new release; preserve GitHub history from 1.1.0, source tags and the model mirror.
- Stable build 10036 replaces 10035; build-only updates require a manual download. Models remain on demand; upgrade in place without uninstalling or clearing library data.

- 修复 Edge 能试听却不能读书的只读配置异常；系统语音用名称＋语言区域区分并迁移旧选择；补充安卓通知权限声明、首次前台朗读申请和设置入口。
- TXT 导出用横线和“笔记”标签区分摘录与笔记，标注本地时区的创建或最后修改时间；旧数据无时间时不伪造日期。
- 朗读通知显示书名和章节，提供上一段、播放/暂停、下一段、停止退出；暂停仍保留完整控制，章节信息跟随后台朗读更新。
- 阅读亮度改为左侧自动、中间滑杆、右侧夜间模式；夜间配色不覆盖原有配色和背景图，关闭后恢复。
- 中英文独立字体：英文默认跟随正文，也可单独选择或导入，兼容横排、竖排与注释，不拆分文字节点。
- 新增 8 套可命名、编辑的 CSS 方案；每本书在本机记住选择，可跟随默认，并保留旧 CSS。
- 检查更新和安装包下载优先 GitHub，全部网络、超时、TLS 和 HTTP 请求错误均回退 Gitee，包括 403 和 404。
- 保留 HTTPS、版本与架构、大小及 SHA-256 校验；主动取消、无效清单和本地错误仍安全停止。
- 区分限流和拒绝访问，不再把所有 403 统一提示为请求频率限制。
- Gitee 每次先删除旧应用发行版再发布新版；保留 GitHub 1.1.0 起历史、源码标签及独立模型镜像。
- 正式版构建 10036 替换 10035，同版本构建更新需手动下载；模型继续按需下载，请直接覆盖升级，不卸载或清空书库数据。
