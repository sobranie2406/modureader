# 自动更新镜像发布

客户端优先检查 GitHub 最新正式版；任何网络连接失败、超时、TLS 握手/证书失败或 HTTP 请求错误时读取以下固定 HTTPS 备用清单（不跳过内容校验）：

`https://gitee.com/sobranie2406/modureader/raw/master/updates/latest.json`

镜像仓库仅存放说明、更新清单和发行附件，不导入应用源码。1.0.9 的九个平台附件和校验文件已匿名下载核对，与 GitHub 摘要一致。正式更新清单已上线；1.0.9+10028 起兼容 Gitee 原始文件 CDN 跳转，1.0.9+10027 仍可通过 GitHub 元数据检查并优先下载 Gitee 附件。

## 发布顺序

1. 在 GitHub 完成正式 Release；保留全部安装包、SHA-256 文件及相应源码。
2. **先删除 Gitee 旧应用发行版及附件，再创建并上传新版**。先确认 GitHub 新版九包齐全、旧版仍可下载，本机保留待上传原包；逐个核对旧 Release 的仓库、标签与附件，删除后确认列表已清空。不得删除 Git 标签、源码、分支或 `modu-models` 独立模型仓库。此顺序适用于以后每次发布，不再先上传后清理。
3. 把同版本、同名、字节完全相同的安装包及校验文件发布到 Gitee。不要替换模型、重新压缩安装器或复用其他版本的文件。
4. 逐一验证公开、无需登录的 Gitee 下载入口、重定向、长度和 SHA-256；与 GitHub 已发布资产的 `digest` 对比。镜像 URL 为 `https://gitee.com/sobranie2406/modureader/releases/download/v版本号/安装包名称`。
5. 使用 GitHub Release API 返回的 JSON 生成清单：`python3 scripts/release/update_manifest.py github-release.json`。脚本输出 JSON 到标准输出，不上传、不修改仓库。
6. 最后才把生成结果发布到镜像仓库 `master` 分支的 `updates/latest.json`。客户端只接受 `modu_update_schema: 1`、正式版本、匹配系统/架构的有效文件大小和 SHA-256。清理到上传完成之间，镜像可能暂时不可用；不得为消除空窗提前指向未经验证的附件。若上传中断，使用本机原包重试，完成后确认镜像只剩新版。

GitHub 的历史清理范围为 1.0.9 及更早的 Release 和附件，保留标签与对应源码；1.1.0 起的发行版继续保留。此规则不等于 GitHub 每次只保留最新版。

清单保留 GitHub 的 `tag_name`、`draft`、`prerelease`、`body`、`assets` 字段及原始 GitHub 下载 URL；客户端自行推导 Gitee 镜像 URL，清单不能指定任意下载网站。生成脚本只接收九个平台安装包，不把令牌、上传地址等其他 API 字段复制进去。

## 回退与安全

- 检查首先请求 GitHub，完整检查限时 12 秒；成功后不请求镜像。DNS、连接重置、超时、TLS/证书失败及所有 HTTP 请求错误（含 401、403、404、407、429、5xx）均请求 Gitee 清单，限时 8 秒。不会关闭任一来源的 HTTPS 证书验证。两端都不可用时显示检查失败，不能误报“最新”。
- GitHub 可用时始终以其版本和校验信息为准；不会因镜像的新旧或摘要差异改变结果。当前安装版本不会被降级。
- 下载也首先使用 GitHub；上述网络和 HTTP 请求错误时清除部分文件，从头下载同版本 Gitee 资产。两源使用同一大小与 SHA-256，校验失败即终止。
- 无效清单、不安全跳转、用户取消、文件校验失败、程序错误或磁盘写入失败不会开始备用请求。已有完整文件重新校验通过才复用，安装前再次校验。
- 仅允许 HTTPS；Gitee 跳转限制在 `gitee.com/sobranie2406/modureader/`、已核实的附件 CDN `foruda.gitee.com/attach_file/`，以及 `raw.giteeusercontent.com` 上与清单完全相同的 `/sobranie2406/modureader/raw/master/updates/latest.json` 路径。拒绝其他账号、文件路径、端口和相似域名。GitHub 跳转限制在代码列出的官方资源域名。不能改成允许任意跳转。
- 镜像清单通过固定官方账号地址及 HTTPS 建立信任，SHA-256 用于完整性校验，不等于数字签名。需保护两个发布账号；不能把不受信任的第三方镜像当作官方更新源。
- Gitee 单文件容量、总附件容量或审核限制若无法承载现有完整安装包，应报告限制并确认方案；不要用分卷或 HTML 下载页冒充可安装文件。

客户端无需 Gitee 登录，不读取浏览器登录状态，不携带书库配置或 API Key。商店分发、Android 系统安装确认和 iOS 自签名限制保持不变。

发布后可运行 `flutter test test/service/update/app_update_mirror_live_test.dart --dart-define=MODU_VERIFY_UPDATE_MIRROR=true`，验证真实清单跳转，并模拟 GitHub 不可用。该检查仅取公开元数据，不下载或安装应用，不替代九个平台包的独立 SHA-256 验证。
