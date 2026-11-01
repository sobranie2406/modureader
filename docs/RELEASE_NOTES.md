# Modu 1.3.6

Build / 构建：**10168** · Stable / 正式版

### English

- Fix(reader): Recover verified self-referencing EPUB note links so popups show the actual annotation instead of the source paragraph, preserving text layout and reading positions.

- Feat(reader): Swipe through other images in the book from the enlarged image viewer, retaining zoom and sharing.

- Feat(reader): Add text-filter profiles alongside CSS presets: hide matching text or its whole paragraph and skip filtered content during narration.

- Feat(reader): Apply supported font, spacing, color and alignment CSS settings to PDF/OCR reflow, and turn reflow pages using the configured tap regions.

- Fix(pdf): Restore single-finger swipe paging in unzoomed single-page reading while preserving enlarged-page panning, pinch zoom and text selection.

- Fix(sync): Keep success notices silent in every reader; retry failed sync three times before one notice with the reason, and silently defer offline or Wi-Fi-restricted attempts. Other screens retain their notices.

- Fix(dictionary): Allow MDD resource packages up to 2 GiB while retaining the 256 MiB MDX text limit and import validation.

- Fix(bookshelf): Restore scrolling to the last row of HarmonyOS book folders ([#65](https://github.com/sobranie2406/modureader/issues/65)). Thanks [@zggnice](https://github.com/zggnice) for the report.

- Fix(appearance): Accept integer-valued cover widths after restart and recover invalid values, preventing blank bookshelf and appearance pages ([#67](https://github.com/sobranie2406/modureader/issues/67)). Thanks [@zggnice](https://github.com/zggnice).

- Fix(history): Keep wide-screen reading-history content aligned to the top.

- Feat(update): Show all intervening stable-version changes when upgrading across multiple versions.

- Chore(settings): Remove the ANX-backup import entry from Advanced settings.

### 简体中文

- Fix(reader): 兼容部分 EPUB 注释链接错误指向自身的情况，核实配对后显示真正的注释，保留正文排版与阅读定位。

- Feat(reader): 放大书中图片后可左右滑动浏览其他图片，保留缩放与分享。

- Feat(reader): CSS 方案中新增文字过滤模板，可隐藏匹配文字或所在整段，朗读同步跳过过滤内容。

- Feat(reader): PDF／OCR 重排支持适用的字号、间距、配色与对齐 CSS 设置，并可按已配置的点击区域翻页。

- Fix(pdf): 恢复 PDF 单页未放大时的单指滑动翻页，保留放大平移、双指缩放及划词选择。

- Fix(sync): 所有阅读界面隐藏同步成功提示；失败后再重试 3 次，仍失败仅提醒一次并附原因；断网或不满足仅 Wi-Fi 条件时静默跳过，其他界面提示照旧。

- Fix(dictionary): MDD 资源包导入上限提高至 2 GiB，保留 MDX 正文 256 MiB 上限及导入校验。

- Fix(bookshelf): 修复鸿蒙书架分组无法滚动到末行（[#65](https://github.com/sobranie2406/modureader/issues/65)）。感谢 [@zggnice](https://github.com/zggnice) 反馈。

- Fix(appearance): 兼容重启后以整数读取的封面宽度，并为异常值提供兜底，避免书架和外观页面空白（[#67](https://github.com/sobranie2406/modureader/issues/67)）。感谢 [@zggnice](https://github.com/zggnice)。

- Fix(history): 阅读历史在宽屏下保持顶部对齐。

- Feat(update): 跨版本升级后汇总展示原版本至当前版本之间的正式版更新说明。

- Chore(settings): 移除高级设置中的 ANX 备份导入入口。

### Downloads / 下载

Android ARM64 · iOS ARM64 · macOS ARM64 / x64 · Windows ARM64 / x64 · Linux x64 / ARM64 · HarmonyOS ARM64.

Nine architecture-specific packages, each with a SHA-256 sidecar. Existing automatic-update filenames are preserved. / 共九个分架构安装包，均提供 SHA-256 校验文件，沿用原有自动更新文件名。

iOS IPA and HarmonyOS HAP require your own signing. macOS uses ad-hoc signing without notarization; Windows has no commercial Authenticode signature and requires WebView2. Linux DEB targets Debian 13. / iOS IPA 与鸿蒙 HAP 需自行签名；macOS 为临时签名、未公证；Windows 无商业 Authenticode 签名，需 WebView2；Linux DEB 面向 Debian 13。

[Source / 源码](https://github.com/sobranie2406/modureader/tree/v1.3.6) · [Installation / 安装说明](https://github.com/sobranie2406/modureader/blob/v1.3.6/docs/RELEASING.md) · [License](https://github.com/sobranie2406/modureader/blob/v1.3.6/LICENSE) · [Notice](https://github.com/sobranie2406/modureader/blob/v1.3.6/NOTICE)
