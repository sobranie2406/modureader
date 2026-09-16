# 自动更新镜像发布

客户端优先读取以下固定 HTTPS 清单，再核对 GitHub 最新正式版：

`https://gitee.com/sobranie2406/modureader/raw/master/updates/latest.json`

这是待部署的协议地址，不代表镜像已上线。未部署、需要登录、请求失败、清单无效时，客户端回退到 GitHub。不要在 README 宣称镜像可下载，直到实际验证通过。

## 发布顺序

1. 在 GitHub 完成正式 Release；保留全部安装包、SHA-256 文件及相应源码。
2. 把同版本、同名、字节完全相同的安装包及校验文件发布到 Gitee。不要替换模型、重新压缩安装器或复用其他版本的文件。
3. 逐一验证公开、无需登录的 Gitee 下载入口、重定向、长度和 SHA-256；与 GitHub 已发布资产的 `digest` 对比。镜像 URL 为 `https://gitee.com/sobranie2406/modureader/releases/download/v版本号/安装包名称`。
4. 使用 GitHub Release API 返回的 JSON 生成清单：`python3 scripts/release/update_manifest.py github-release.json`。脚本输出 JSON 到标准输出，不上传、不修改仓库。
5. 最后才把生成结果发布到镜像仓库 `master` 分支的 `updates/latest.json`。客户端只接受 `modu_update_schema: 1`、正式版本、匹配系统/架构的有效文件大小和 SHA-256。

清单保留 GitHub 的 `tag_name`、`draft`、`prerelease`、`body`、`assets` 字段及原始 GitHub 下载 URL；客户端自行推导 Gitee 镜像 URL，清单不能指定任意下载网站。生成脚本只接收九个平台安装包，不把令牌、上传地址等其他 API 字段复制进去。

## 回退与安全

- Gitee 清单请求限时 8 秒，GitHub 核对限时 12 秒。GitHub 不可用时可以继续使用有效镜像；两端都不可用时显示检查失败，不能误报“最新”。
- 镜像版本滞后时使用较新的 GitHub 版本；相同版本大小或摘要不一致时以 GitHub 信息为准。当前安装版本不会被降级。
- 下载首先使用镜像；请求失败、大小或摘要不符则清除部分文件，从头下载同版本 GitHub 资产。镜像和备用源使用同一 SHA-256，备用源再次校验失败即终止。
- 用户取消或磁盘写入失败不会开始备用下载。已有完整文件重新校验通过才复用，安装前再次校验。
- 仅允许 HTTPS；Gitee 跳转限制在 `gitee.com/sobranie2406/modureader/` 和已核实的 `foruda.gitee.com/attach_file/`，GitHub 跳转限制在代码列出的官方资源域名。若 Gitee 改用新的附件 CDN，须先核对实际官方域名并补充测试，不能改成允许任意跳转。
- 镜像清单通过固定官方账号地址及 HTTPS 建立信任，SHA-256 用于完整性校验，不等于数字签名。需保护两个发布账号；不能把不受信任的第三方镜像当作官方更新源。
- Gitee 单文件容量、总附件容量或审核限制若无法承载现有完整安装包，应报告限制并确认方案；不要用分卷或 HTML 下载页冒充可安装文件。

客户端无需 Gitee 登录，不读取浏览器登录状态，不携带书库配置或 API Key。商店分发、Android 系统安装确认和 iOS 自签名限制保持不变。
