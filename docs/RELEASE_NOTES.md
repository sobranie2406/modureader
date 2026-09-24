# 默读 / Modu 1.1.4 正式版

版本：**1.1.4+10042**。基于 Anx Reader 和 ReadAny（Reader Any）的 GPL-3.0-or-later 独立修改版本，保留原作者版权与许可。

## 本次更新

- **朗读设置迁移**：设置 → 朗读新增保存设置、清除设置，以及二维码图片与 `modu:` 配置链接导出/导入。接口修改保存后生效；迁移包含各朗读服务配置、API Key、声音、语速、音调和音量。导入先校验并停止当前朗读，不自动播放；清除需确认，不影响 AI、书籍、笔记或同步配置。配置含密钥，请勿公开分享；跨设备系统声音可能需要重新选择。
- **AI 技能选择**：技能默认隐藏，点击星光按钮后在对话框内从上到下展开，不再横向滑动；选中后收起，保留输入草稿。长提示词正文继续隐藏；小屏或大字号时允许纵向滚动。
- **Android 后台朗读与耳机控制**：修复原生播放状态未正确启动导致媒体按键不能控制的问题，补齐延迟创建播放器时的唤醒锁配置。继续保留音频焦点与暂停恢复处理。测试机上已验证相关播放/暂停操作，但不同厂商的后台限制仍可能影响长时间锁屏播放。
- **正文朗读过滤**：跳过可识别的弹出脚注、注释引用编号和章节注释内容；仅省略号或分隔符的段落直接略过，不再因没有可合成文字而停住。真实网络或合成错误仍保留当前位置供重试，不静默跳过正文。
- **替换书籍后的同步**：刷新文件身份及传输状态，避免旧缓存导致重复上传、重复下载或进度停在 100%；下载完成后及时更新本地状态。清理已确认被替换、且不再使用的旧云端文件，保留数据一致性检查，不清空 WebDAV。
- **阅读加载与连续滚动**：调整章节预加载与前台加载顺序，增加明确的加载/失败状态；指定字体未就绪时不使用替代字体排版。阅读菜单作为浮层显示，打开顶部和底部菜单不再触发正文避让重排。
- **竖排与工具栏**：修复初次进入竖排时分栏线未铺满的布局更新问题，抬高移动端阅读底部菜单。macOS 调光层进一步与窗口标题栏、输入事件隔离，保留原有左侧导航位置。

## 升级与下载

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.4) · [Gitee 安装包镜像](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.4)

覆盖升级即可，**不要先卸载或清空数据**，升级前建议导出书库备份。Android 沿用原签名。更新检查与下载仍优先 GitHub，网络、超时、TLS 或 HTTP 请求失败后尝试 Gitee；完整性校验失败不会绕过校验安装。macOS 继续交由外部浏览器下载。

Gitee 仅存放安装包、说明和更新清单，不上传应用源码。镜像按约定先删除旧发行版和附件，再上传新版，切换期间可能短暂不可用；逐包验证大小、SHA-256 与 GitHub 一致后才更新自动更新清单。GitHub 保留 1.1.0 起的历史发行版，不删除源码标签、分支或独立模型镜像。未验证完成的镜像不宣称发布完成。

## 平台与签名

九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64，各附 SHA-256。

- macOS 为 ad-hoc 签名，未经 Apple 公证；退出旧应用后使用 DMG 覆盖安装。
- Windows 附对应架构 VC++ CRT，仍需 WebView2 Runtime，暂无商业 Authenticode 签名。
- Linux 面向 Debian 13，不保证其他发行版兼容。
- iOS IPA 没有分发签名，需要自行合法签署主应用及 Share Extension，不能直接安装。
- 向量模型仍按需下载，不内嵌模型，不恢复已取消的向量索引 WebDAV 同步。

完整对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.4) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.4.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.4/docs/RELEASING.md)。许可与来源见同标签 LICENSE、NOTICE、UPSTREAM.md、LICENSES 和依赖锁文件。

正式发布由全部安装包构建、架构与签名检查及 CI 回归共同把关。自动化测试不等于所有设备、语音服务和网络条件下的实测。

## English

Modu **1.1.4 (build 10042)** adds explicit speech configuration saving/clearing and private QR/`modu:` configuration transfer, including providers, keys, voices and playback parameters. Import validates before replacing TTS settings and stops speech without autoplay. System voices may require reselection on another device.

AI skills stay hidden until the sparkle button opens a vertical in-chat picker. This release also addresses Android native playback/media-key state and wake locks, filters recognizable notes and punctuation-only speech segments, fixes stale book-transfer state after file replacement, improves reader loading/continuous scrolling and vertical rules, and keeps reader menus from reflowing the text. Genuine synthesis/network failures still pause rather than silently dropping body text.

Install in place and back up first; do not uninstall or clear your library. Nine packages cover Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is not notarized, Windows has no commercial signing, and iOS requires your own signing. Gitee mirrors the exact GitHub artifacts; metadata is updated only after byte-level verification. Source and all licenses remain available through the links above.
