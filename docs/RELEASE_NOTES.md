# Modu 1.3.7

Build / 构建：**10171** · Stable / 正式版

### English

- Feat(tts): Add optional narration/dialogue voices and independent speed multipliers, with per-book voice overrides and consistent buffered playback. ([PR #69](https://github.com/sobranie2406/modureader/pull/69) / [#74](https://github.com/sobranie2406/modureader/pull/74)) Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Feat(appearance): Add theme presets, custom palettes and optional reading-page colours. ([PR #70](https://github.com/sobranie2406/modureader/pull/70)) Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Feat(sync): Add optional manual-sync preview and conflict confirmation; preserve cancellation, deletion safeguards and cross-device convergence. ([PR #71](https://github.com/sobranie2406/modureader/pull/71) / [#73](https://github.com/sobranie2406/modureader/pull/73)) Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Feat(appearance): Restore scheduled day/night switching with custom hours, off by default.

- Feat(reader): Consolidate font management with multiple-file/folder import and previews in the installed list and reader selectors.

- Feat(pdf): Resize original/reflow comparison panes by dragging the divider; the temporary ratio is neither saved nor synced.

- Fix(reader): Hide More when all enabled toolbar actions fit, and show setting/PDF explanations through anchored question-mark popovers.

- Fix(dictionary): Import loose dictionary resources correctly when the Android picker caches files in separate folders.

- Fix(pdf): Use the PDF filename for newly imported titles instead of unreliable embedded metadata. ([Issue #68](https://github.com/sobranie2406/modureader/issues/68)) Thanks [@h9413](https://github.com/h9413).

- Feat(ocr): Use PP-OCRv5 Mobile as the default for new model selections while retaining existing choices.

### 简体中文

- Feat(tts): 新增可选的旁白／对话音色及独立语速倍率，支持按书覆盖音色，并保持缓存播放与暂停继续的速度一致。 ([PR #69](https://github.com/sobranie2406/modureader/pull/69) / [#74](https://github.com/sobranie2406/modureader/pull/74)) 感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Feat(appearance): 新增主题预设、自定义配色及可选的阅读页配色联动。 ([PR #70](https://github.com/sobranie2406/modureader/pull/70)) 感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Feat(sync): 新增可选的手动同步预览和冲突确认，保留取消、删除保护及跨设备一致性。 ([PR #71](https://github.com/sobranie2406/modureader/pull/71) / [#73](https://github.com/sobranie2406/modureader/pull/73)) 感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Feat(appearance): 恢复定时日夜切换，支持自定义时段，默认关闭。

- Feat(reader): 整合字体管理，支持多文件／整文件夹导入，已安装列表和阅读选择器按字体样式预览。

- Feat(pdf): 原文对照重排支持拖动分隔条调整比例，比例不记忆、不同步。

- Fix(reader): 顶部按钮全部显示时隐藏“更多”，设置及 PDF 菜单说明改为问号周边弹层。

- Fix(dictionary): 修复安卓文件选择器将文件缓存到不同目录时，字典附属资源导入失败。

- Fix(pdf): 新导入 PDF 使用文件名作为标题，避免内嵌元数据导致标题乱码。 ([Issue #68](https://github.com/sobranie2406/modureader/issues/68)) 感谢 [@h9413](https://github.com/h9413).

- Feat(ocr): 新模型选择默认使用 PP-OCRv5 移动版，保留已有模型选择。

### Downloads / 下载

Android ARM64 · iOS ARM64 · macOS ARM64 / x64 · Windows ARM64 / x64 · Linux x64 / ARM64 · HarmonyOS ARM64.

Nine architecture-specific packages, each with a SHA-256 sidecar. Existing automatic-update filenames are preserved. / 共九个分架构安装包，均提供 SHA-256 校验文件，沿用原有自动更新文件名。

iOS IPA and HarmonyOS HAP require your own signing. macOS uses ad-hoc signing without notarization; Windows has no commercial Authenticode signature and requires WebView2. Linux DEB targets Debian 13. / iOS IPA 与鸿蒙 HAP 需自行签名；macOS 为临时签名、未公证；Windows 无商业 Authenticode 签名，需 WebView2；Linux DEB 面向 Debian 13。

[Source / 源码](https://github.com/sobranie2406/modureader/tree/v1.3.7) · [Installation / 安装说明](https://github.com/sobranie2406/modureader/blob/v1.3.7/docs/RELEASING.md) · [License](https://github.com/sobranie2406/modureader/blob/v1.3.7/LICENSE) · [Notice](https://github.com/sobranie2406/modureader/blob/v1.3.7/NOTICE)
