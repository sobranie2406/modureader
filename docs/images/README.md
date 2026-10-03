# Display assets / 展示素材

## Current homepage / 当前首页

The English homepage is [`README.md`](../../README.md); the Chinese homepage is [`README_zh.md`](../../README_zh.md). `README_EN.md` retains a link for older bookmarks. The `showcase/cross-platform/` series pairs a large macOS window behind an overlapping iPhone for each feature: reading/navigation, voice templates, reading skills and selection-tool customization. The Chinese page also includes framed vertical reading. Images sit beside their relevant feature descriptions.

当前首页使用 `showcase/cross-platform/` 目录内的中英文双端展示图：Mac 窗口在后、iPhone 在前错位叠放，保留两端主要内容，搭配简洁标题、浅色背景与柔和阴影。Mac 部分以归档的实际界面为依据，iPhone 部分沿用已生成的 `showcase/` 手机图作为来源，保留灵动岛、状态栏与底部横条。界面字体采用系统字体风格，书籍正文保留阅读字体；已移除桌面录屏标记与鼠标指针。阅读内容来自项目原创示例书，不包含私人书架、笔记、对话或账号密钥。图中设置用于功能展示，不代表所有选项的出厂默认值。单独的手机图与 Mac 原始截图保留，不覆盖源素材。

## Archived Mac captures — 1.1.9 / Mac 截图归档

The `v1.1.9/macos-zh/` and `v1.1.9/macos-en/` directories contain captures from **Modu 1.1.9+10063**, taken on **2026-10-01**. The app was built from release commit `584a6bb3daa3d30978ccb0599ef809beaef0c9bb`. Computer Use captured the local Release app window without replacing the installed application. These original files remain unchanged as source material.

- `v1.1.9/macos-zh/`: Chinese interface; reading screens use **《阅读，让思考慢下来》**, six chapters and approximately 3,400 Chinese characters. The vertical reading image includes red frames and column rules. [Original Chinese EPUB](../examples/modu-reading-demo.epub).
- `v1.1.9/macos-en/`: English interface; reading screens use **The Quiet Reader**, six chapters and approximately 2,200 words originally written in English. No vertical reading screenshot is used in the English README. [Original English EPUB](../examples/modu-reading-demo-en.epub).

Both books were authored for this project, not copied from private books or third-party publications. Their source and redistribution terms are documented in [`../examples/README.md`](../examples/README.md). No personal bookshelf, private notes or conversation history appears in the current feature screenshots.

The screenshots cover horizontal reading, Chinese vertical reading, chapter/page controls, reader styles, selection toolbar customization, AI templates and prompt editors, CSS profiles and visual controls, appearance, language selection, translation engines and global settings transfer. Settings reflect the capture session rather than factory defaults. Screens are uncomposited captures, not generated illustrations; no AI answer was fabricated. No account passwords, API keys or configuration QR codes are shown.

上述两个目录保留 Mac 实拍原图。中文阅读图采用六章原创中文书，竖排展示红色边框与分栏线；英文阅读图采用六章原创英文书。设置画面只展示功能参数和模板，不公开账号密钥、私人笔记或对话。

The current Mac set also includes `tts-style-templates.jpg` and `tts-prompt-editor.jpg` in each language directory: actual MiMo template selection and editable narration instructions with shortcut suggestions. Templates were selected in the unsaved draft only; no synthesis request was sent and no credentials were captured. The original system-speech selection and system-following UI language were restored after capture.

## Historical captures / 历史截图

The earlier Android screenshots and `v1.1.9/reading-horizontal-macos.jpg` remain for provenance but are no longer linked from the root READMEs. They were captured from 1.1.9+10063 on 2026-10-01 before the current Mac-only set; Android captures used ADB and the Mac capture used Computer Use. Their reading views use the original Chinese demonstration book.

The older seven Modu screenshots outside `v1.1.9/` were captured with Computer Use from the actual macOS release **1.1.1+10033** on **2026-09-21**. They are retained for history and are no longer linked from the current root READMEs. The release was temporarily launched from its disk image without replacing the installed app.

- `reading-epub-macos.jpg`, `reading-ai-panel-macos.jpg`, `reading-toc-macos.jpg`: the project's original demo book, 《阅读，让思考慢下来》.
- `reading-vertical-border-macos.jpg`: the user-approved local 《古文观止译注评（全二册）》 reading view, with a red frame and column rules. Only the screenshot is published, not the book file.
- `ai-home-prompts-macos.jpg`, `ai-reading-skills-macos.jpg`, `vector-models-macos.jpg`: the release's actual AI and model-management interfaces.

These are uncomposited app-window captures. No AI request was sent for the captures and no generated answer was fabricated. No credentials, private conversations or library overview are included. Visible settings reflect this session, not default values. These images are not evidence of universal endpoint or device compatibility.

`Anx-logo.jpg`, `main.jpg` and the inherited `wide*.png` / `mobile*.png` series were linked from the old upstream homepages. They are historical Anx Reader material, not current Modu screenshots or evidence of Modu store availability. Do not reuse them as current Modu marketing images.

历史七张截图于 2026-09-21 实拍自默读 macOS 正式版 1.1.1+10033。它们和上游旧图仅保留用于来源追溯，不再用于当前首页展示，不能只换标题后重新宣传。
