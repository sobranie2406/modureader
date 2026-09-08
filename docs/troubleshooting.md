# 默读排障 / Modu troubleshooting

[中文](#中文) | [English](#english)

## 中文

### 无法导入或阅读

- 确认格式为 EPUB、PDF、MOBI、AZW3、FB2 或 TXT，文件已完整下载；先用项目的[原创示例书](examples/modu-reading-demo.epub)区分环境问题和单本书问题。
- 正常文件名中的空格和中文不应被视为非法。不要为了排障删除原书；可使用副本测试。
- 扫描 PDF 没有 OCR，密码 PDF 暂不支持，不承诺 DRM 兼容。文字层、目录和排版可能影响提取。
- Android 可检查系统 WebView 是否正常。其他平台的系统依赖、签名和安装要求见[发布说明](RELEASING.md)。

### 远程书库连接或下载失败

- 使用「设置 → 书库 WebDAV」，不是原有「同步」连接。填写最终目录地址，确认账号可列出和读取该目录。
- 推荐 HTTPS；客户端不跟随重定向。密码仅当前运行期间保留，退出应用后需要重填。
- 一次下载一本，单文件最多 512 MiB；离开远程书库标签会取消未完成的下载。检查本机空间，不要在公开反馈中提供密码或私有目录地址。

### 向量化失败或应用退出

- 在书籍菜单检查任务是否完成，记录错误及所选模型。本地嵌入与在线 AI 对话是不同设置；远程模型需要有效接口配置。
- 切换模型后需重新向量化；不要以旧的「已索引」标签代替本次任务成功，也不要通过卸载应用来清除错误。
- 更新到[当前发布版](https://github.com/sobranie2406/modureader/releases/latest)。设备相关限制和已知问题以对应 Release 为准。

### 提交问题

进入「设置 → 提交 Bug」，说明版本、操作步骤及结果。运行环境与崩溃诊断分别可选；先预览，再复制到本仓库的 [GitHub Issue](https://github.com/sobranie2406/modureader/issues/new/choose) 中提交。
诊断记录可能缺失或延迟；没有日志不能证明没有崩溃。不要公开正文、私人书籍、API Key、WebDAV 密码、二维码或未经检查的完整日志。
「高级 → 日志」中的普通日志与可选的脱敏崩溃报告不同，不应直接作为公开附件。

## English

### Import or reading problems

- Confirm the format is EPUB, PDF, MOBI, AZW3, FB2 or TXT and the download is complete. Try the project's [original demo book](examples/modu-reading-demo.epub) to distinguish an environment issue from a book-specific issue.
- Spaces and Chinese characters in ordinary filenames are not inherently invalid. Preserve the original book and test with a copy.
- Scanned PDFs have no OCR; password-protected PDFs are unsupported and DRM compatibility is not guaranteed. Text layers, contents and layout affect extraction.
- On Android, check that the system WebView works. See [release guidance](RELEASING.md) for platform dependencies and signing requirements.

### Remote library problems

Use Settings → Library WebDAV, separate from sync. Enter the final directory URL and use an account with listing/read access. Prefer HTTPS; redirects are not followed. The password is session-only and must be entered again after restarting.
Only one download runs at a time, up to 512 MiB. Leaving the remote-library tab cancels an unfinished download. Check local free space and never post credentials or private directory URLs.

### Indexing failures or unexpected exits

Check the task result and selected model in the book menu. Local embedding and online AI chat are separate settings; remote models require valid configuration.
Rebuild the index after changing models. An old indexed badge does not establish that the latest task succeeded. Do not uninstall the app merely to clear an error.
Use the [current release](https://github.com/sobranie2406/modureader/releases/latest) and read its device-specific limitations.

### Reporting a bug

Open Settings → Report a Bug. Describe the version, steps and outcome. Environment information and crash diagnostics are separately optional: preview first, then copy and submit to [this repository](https://github.com/sobranie2406/modureader/issues/new/choose).
Missing or delayed diagnostics do not prove that no crash occurred. Never publish book text, private books, API keys, WebDAV passwords, configuration QRs or unreviewed full logs. Ordinary logs under Advanced → Logs are not the same as the optional sanitized crash report.
