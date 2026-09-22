# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.1.3

- Separate Chinese/body and English fonts, with independent import/application and legacy-compatible defaults; supports reflowable text and footnotes.
- Eight named, editable CSS profiles; per-book choices on this device, shared defaults and legacy CSS preservation.
- Update checks and downloads prefer GitHub and fall back to Gitee for all network, timeout, TLS and HTTP request failures, including 403 and 404.
- Preserve HTTPS verification, matching version/architecture, size and SHA-256 checks; cancellation, invalid metadata and local errors still stop safely.
- Distinguish rate limiting from access denial instead of labelling every 403 as throttling.
- Remove old Gitee application releases before publishing each new release; preserve GitHub history from 1.1.0, source tags and the model mirror.
- Stable build 10036 replaces 10035; build-only updates require a manual download. Models remain on demand; upgrade in place without uninstalling or clearing library data.

- 中英文独立字体：英文默认跟随正文，也可单独选择或导入，兼容横排、竖排与注释，不拆分文字节点。
- 新增 8 套可命名、编辑的 CSS 方案；每本书在本机记住选择，可跟随默认，并保留旧 CSS。
- 检查更新和安装包下载优先 GitHub，全部网络、超时、TLS 和 HTTP 请求错误均回退 Gitee，包括 403 和 404。
- 保留 HTTPS、版本与架构、大小及 SHA-256 校验；主动取消、无效清单和本地错误仍安全停止。
- 区分限流和拒绝访问，不再把所有 403 统一提示为请求频率限制。
- Gitee 每次先删除旧应用发行版再发布新版；保留 GitHub 1.1.0 起历史、源码标签及独立模型镜像。
- 正式版构建 10036 替换 10035，同版本构建更新需手动下载；模型继续按需下载，请直接覆盖升级，不卸载或清空书库数据。
