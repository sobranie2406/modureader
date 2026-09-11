# Modu Reader · 默读

[简体中文](README.md) | [English](README_EN.md)

Only these Chinese and English project homepages are maintained.

<p align="center"><img src="assets/icon/modu-app-icon.png" width="120" alt="Modu app icon"></p>

**Derived from [Anx Reader](https://github.com/anxcye/anx-reader) and [ReadAny (Reader Any)](https://github.com/codedogQBY/ReadAny). Thanks to the authors and contributors of both projects.** This is an independently modified derivative, not an official release of either upstream.

Modu is an open-source AI ebook reader built with Flutter. It brings books, notes, reading progress and AI conversations together: read first, then ask questions about the current chapter. For semantic search, index your books using local models or a remote embedding service.

**Local reading does not require an AI account.** AI, online translation and online speech are optional; availability and costs depend on your chosen providers. See [Releases](https://github.com/sobranie2406/modureader/releases) for version updates and usage notes.

Modu has no in-app unlock purchases or subscriptions. Fees charged by online service providers are separate from Modu.

If Modu helps you enjoy reading, please give the repository a **Star ⭐** in the top-right corner. It helps more readers discover the project and encourages continued development. Thank you!

[Features](#features) · [Screenshots](#screenshots) · [Getting started](#getting-started) · [Settings guide (Chinese)](docs/SETTINGS.md) · [Downloads](#downloads)

## Downloads

[GitHub Releases](https://github.com/sobranie2406/modureader/releases) · [Build status](https://github.com/sobranie2406/modureader/actions) · [Report an issue](https://github.com/sobranie2406/modureader/issues)

| Platform | Published architectures | Package and limitations |
| --- | --- | --- |
| Windows | x64, ARM64 | EXE installer with shortcuts and an uninstaller; no commercial code signature; requires WebView2 Runtime |
| Linux | x64, ARM64 | DEB for Debian 13 (trixie); install with APT to resolve system dependencies |
| Android | x86_64, arm64-v8a | APK signed with the project's dedicated key; verify the download source before installing |
| macOS | x64, ARM64 | DMG; drag the app to Applications; unnotarized, not an App Store release |
| iOS | ARM64 devices | iOS 16+; IPA has no Apple distribution signature and cannot be installed directly; you must sign it yourself using a valid signing identity |

Here, x64 means x86-64; ARM64 is also 64-bit. There is no x64 iPhone/iPad device package.
Download the installer and its SHA-256 file from [Releases](https://github.com/sobranie2406/modureader/releases), choosing your system and architecture.

Desktop apps use native installers, not ZIP or tar.gz downloads. Licenses remain in the application packages and source repository; no separate notices ZIP is provided. GitHub's automatically generated `Source code (zip)` downloads contain source code, not an application installer. We do not provide scripts to bypass operating-system security protections. See [Release and installation instructions (Chinese)](docs/RELEASING.md) for details.

## Features

The current version provides the following reading, AI and library features.

| Area | What it does | Where to find it |
| --- | --- | --- |
| Library and import | Import EPUB, PDF, MOBI, AZW3, FB2 and TXT; filter by reading status, search, group books and manage tags | Home → Library; add button or book menu |
| Remote library | Browse a separate WebDAV server; sort by name, creation/modification time or size in either direction, search, filter by format and download books | Home → Remote library; Settings → Library WebDAV |
| Reading and layout | Chapter navigation, progress, paginated/scrolling modes, fonts, sizes, spacing, backgrounds and themes; rule-based TXT-to-EPUB conversion | Reader; Settings → Reading |
| Highlights and notes | Highlight text, record thoughts and organize notes by chapter; copy or export Markdown, TXT and CSV | Text selection menu; Home → Notes |
| Mobile quick mark | Swipe directly across text and release to save a highlight; select across lines, backwards or across paragraphs on the same page | Pen button in the mobile reader; persistent Exit button restores normal gestures |
| Reading statistics | Reading time, trends, heatmap and per-book records | Home → Statistics |
| AI conversations | Home quick prompts, in-book questions and chat history; enabled tools access the library, contents, chapters, notes and reading records | Home → AI; reader AI panel |
| AI reading skills | Ten built-in skills with Chinese names; enable/disable, inspect/edit prompts and create custom skills | Settings → AI Reading Skills |
| Semantic search and RAG | Combined keyword and vector search, locally stored indexes, background indexing queue and reindexing | Book menu; Settings → Embedding Models |
| Translation | Free Google translation, AI translation and DeepL/DeepLX; selected-text results use the same popup sizing as AI chat, with scrolling for long output | Settings → Translation; top reader toolbar, next to AI |
| Read aloud | System speech, Edge TTS, Xiaomi MiMo and compatible online services; voice selection, previews and speech parameters | Settings → Read Aloud; reader playback controls |
| Sync and backup | WebDAV sync for books, notes and reading progress; local backups; separately enabled encrypted API-key sync | Settings → Sync |
| Configuration transfer | Import/export AI, sync WebDAV and separate library WebDAV configurations using codes and QR images | Corresponding settings page → Import and Export |
| Appearance and tools | System/dark/light themes, cover display, font import/download, network and logging options | Settings → Appearance / Reading / Advanced |
| Bug reporting | Describe a problem and reproduction steps, preview the report, then submit it on GitHub | Settings → Report a Bug |

### WebDAV remote library

Enter the full book-directory URL, username and password in Settings → Library WebDAV, test the connection and save. Open Home → Remote library to browse. Tap folders to navigate, or use Parent folder and Root to go back. A book's download button downloads and imports it into your local library for offline reading. Downloads show progress, support cancellation and check for duplicates. The limit is 512 MiB per file, with one download at a time; leaving the tab cancels an unfinished download.

This connection is separate from WebDAV sync. It only reads and downloads files; it never uploads or deletes server files. Anonymous and username/password access are supported. Prefer HTTPS and a dedicated read-only account. The URL, username and password persist in local app preferences without additional local encryption. Enabling **Sync API keys** includes the library connection in automatic WebDAV sync with AES-256-GCM encryption; devices need the same sync encryption password. Encrypted service-settings backups also include the connection; ordinary unencrypted backups omit it. Clearing the connection propagates to other opted-in devices and removes its saved password, not books or server files.

Library WebDAV settings support explicit export to a `modu:` configuration code or QR image, and import from a code or QR image. **Password export is on by default and can be turned off. Codes and QR images are not encrypted; do not share them publicly.** Import only fills the form; it does not automatically connect or save. Creation and modification dates come from the server; missing dates remain unknown rather than being replaced with local import times.

### Mobile page-turn controls

In scrolling mode, page-turn taps and shortcuts move by 80% of the reading viewport, leaving 20% overlap for text near the screen edges. Free scrolling is unchanged. Desktop arrow keys turn pages when the reader is focused; in the AI input field they move the text cursor.

Reader styles → More settings → Other includes **Tap-only page turning**, off by default. When enabled in paginated mode, swipes and drags neither turn pages nor trigger pull gestures; taps still work. Turn it off to restore swipe navigation. Text selection, Quick mark and scrolling mode remain available. This mobile-only switch is not shown on desktop.

### Quick marking on mobile

Adjacent same-color highlights without comments can merge across pages within one chapter document. Missing text, intervening images or existing comments keep marks separate.

Open a reflowable ebook and tap the pen button in the reader toolbar to enable Quick mark. No long press is needed: swipe from the beginning of the text you want to capture, then release to save the highlight. It uses your current highlight color and appears in the existing notes list. Marking the same location again preserves any existing comment.

While enabled, swiping over text selects it. Tap text to open the reading controls, or use the persistent Quick mark · Exit button to restore normal page turns and scrolling. The mode starts off each time you enter a book and is not shown on desktop. PDF, scanned images and fixed-layout books are not supported; selection does not automatically continue across pages.

### AI grounded in your reading

Reasoning effort is configurable per model, including **Off** for supported models. Full-text translation uses the selected model's parameters. Actual support depends on the provider and model.

Home AI is intended for library, note and reading-history questions. In-book AI focuses on the current book, chapter or selected text. Home offers quick prompts, while the reader uses enabled reading skills. Their contexts are different: a home-screen question should not automatically be treated as referring to a current chapter.

Add or edit models under Settings → AI Settings → Provider Configuration. Each model can have its own endpoint, model name, API key, temperature, maximum output tokens and number of conversation-history turns. OpenAI-compatible, Claude and Gemini protocols are supported. Presets include OpenAI, Claude, Gemini, DeepSeek, Zhipu GLM and OpenRouter; compatible custom endpoints can also be configured. Model discovery, tool calling and parameter ranges depend on the provider.

Enable AI tools as needed, including finding books and notes, searching text, reading chapters, inspecting reading records and generating mind maps. AI output can be wrong. Book summaries are limited by the text retrieved, search results and the model's context window; one request is not guaranteed to read an arbitrarily long book in full.

### Ten built-in reading skills

The built-in names are displayed in Chinese; their English meanings are provided below.

| Skill | Purpose |
| --- | --- |
| 本章总结 — Chapter Summary | Outline the current chapter's content, plot and themes |
| 全书总结 — Book Summary | Summarize available book content and structure |
| 概念解析 — Concept Explainer | Explain concepts, terminology and abstract ideas |
| 论证分析 — Argument Analyzer | Break down claims, reasoning and supporting evidence |
| 人物追踪 — Character Tracker | Track character relationships and development |
| 金句摘录 — Quote Collector | Extract noteworthy passages from the original text |
| 阅读指南 — Reading Guide | Suggest reading approaches, discussion questions and reflection topics |
| 智能翻译 — Smart Translator | Translate content in its book context |
| 词汇助手 — Vocabulary Helper | Explain unfamiliar words, idioms and technical expressions |
| 思维导图 — Mind Map | Organize content into a hierarchy |

Open a skill to inspect its prompt, edit and save it, or restore the default. Custom skills appear alongside built-in skills in the reader AI panel. Prompts for recalling previous content, translation/dictionary and full-text translation are managed on the same settings page.

### Book indexing and local models

Choose **Index** or **Reindex** from a book's pop-up menu. Books enter a background queue, so you can leave the indexing screen. Check task status and error messages to confirm completion. For automatic indexing of new imports, enable both the embedding model and **Automatically index after import** in Settings → Embedding Models. Automatic indexing is off by default.

| Local ONNX model | Languages | Embedding dimensions |
| --- | --- | --- |
| all-MiniLM-L6-v2 | English | 384 |
| BGE Small EN v1.5 | English | 384 |
| BGE Small ZH v1.5 | Chinese | 512 |
| Multilingual E5 Small | Multilingual | 384 |

The four models are **downloaded on demand, not bundled in installers**. In Settings → Embedding Models, choose **Download and use** to fetch only the selected model and tokenizer. Size and SHA-256 checks must pass before offline use; no API key is needed. Downloads use Hugging Face and consume network data. Keep the settings page open during download; interrupted transfers can be retried. Verified files prepared by older versions are reused. Chinese BGE is selected by default and automatic indexing is off. Missing models prompt you to download first; indexing never silently downloads them. Remote embedding APIs remain optional. Reindex books after switching models; chat and embedding settings are separate.

Local embeddings only mean that embedding computation happens on your device. Remote chat, embedding, translation or speech services still receive the relevant text. The whole AI workflow should not be described as completely offline.

### Translation and read-aloud

Mobile inline images fit the reading area proportionally. Footnote popups resize to content, capped at 25% of the visible reader viewport area; longer notes scroll inside the popup.

At a chapter boundary, narration automatically continues with the next chapter's heading and body, skipping empty chapters.

Translate selected text or use the translation button next to AI in the top reader toolbar, with Google translation, AI translation or DeepL/DeepLX. Selected-text results use consistent body text and capped heading sizes; long translations scroll inside a popup sized like AI chat.

Read-aloud controls include play, pause, resume, previous/next sentence and chapter navigation. System speech uses device voices; online speech offers provider, voice and speech-parameter settings. Xiaomi MiMo supports built-in voices, text-based voice design and MP3/WAV audio; style, pace and pitch are controlled through natural-language instructions. Synthesis or playback failures pause at the current position for retry.

### Sync and key security

- WebDAV syncs your library, notes and reading progress in the `modu` folder under the configured endpoint, without a Modu cloud account. See the relevant Release notes for legacy-folder migration.
- Books, notes, bookmarks and reading positions merge record by record. The latest reading action wins, rather than the furthest progress; new reading-time records are deduplicated and deletions retain markers. Fonts, theme images and local vector indexes are not synced. Concurrent uploads use server ETag checks; see the [sync guide (Chinese)](docs/WEBDAV_RECORD_SYNC.md) for migration and server requirements.
- **Sync API Keys** is off by default and separate from the main WebDAV switch. Enabling it requires a separate password and acknowledgment of the risks.
- Sensitive service settings are encrypted with **AES-256-GCM** before being written to the sync database. Other devices need the same password. The password is not synced and cannot be recovered if lost.
- This does not encrypt all books, notes or the entire backup, and does not replace a trustworthy WebDAV service and a strong password.
- **Configuration codes and QR codes are not encrypted** and may contain passwords or API keys. Do not post them in public screenshots, issues or group chats. Configuration transfer is separate from encrypted key sync.

## Screenshots

These actual Modu macOS screenshots use the project's original demo book. They come from an earlier build and illustrate the layout; available options and defaults depend on the installed version.

### Reading: text, fonts and themes

The original demo book *Reading: Let Your Thinking Slow Down* (《阅读，让思考慢下来》) is shown in the EPUB reader with a single-column layout, Chinese font, light theme and progress information. Font size, line spacing and columns can be adjusted in reading settings.

![Modu EPUB reader with the original demo book, single-column layout and a light theme](docs/images/reading-epub-macos.jpg)

### In-book AI: read and ask side by side

The AI sidebar keeps the book text visible on the left. The right side provides the ten reading skills listed above, or you can type your own question.

![Modu in-book AI sidebar with book text on the left and ten reading skills on the right](docs/images/reading-ai-panel-macos.jpg)

### Home AI: start with a quick question

Home offers twelve quick questions about your library and reading records, covering recent reading, notes, unread books, reading time and library organization. The input area also provides general explanation, summary and analysis prompts.

![Modu home AI with twelve quick questions and general prompt entry points](docs/images/ai-home-prompts-macos.jpg)

The screenshots show reading and AI controls. [Download the original demo EPUB](docs/examples/modu-reading-demo.epub) to try them yourself.

<details>
<summary>More screenshots: chapter navigation, AI skills and local embedding models</summary>

### Contents and bookmarks

![Modu chapter navigation, chapter search and reading position](docs/images/reading-toc-macos.jpg)

### AI reading skills and prompt management

![Modu AI reading skill settings](docs/images/ai-reading-skills-macos.jpg)

### Local embedding models and automatic indexing

![Modu embedding model settings](docs/images/vector-models-macos.jpg)

</details>

## Getting started

1. Download the package for your system and architecture from [Releases](https://github.com/sobranie2406/modureader/releases). Read the installation limitations first.
2. Add an ebook to the library and open it. No API key is required if you do not use AI.
3. To use AI, configure a model in Settings → AI Settings and test the connection.
4. For semantic search, first download a local model in Settings → Embedding Models (Chinese BGE is the default), then index a book from its menu. You can also configure a remote embedding endpoint.
5. Choose translation, read-aloud and sync services as needed. See the [Settings guide (Chinese)](docs/SETTINGS.md) for instructions, parameter explanations and security considerations.

## Feedback

Version changes, compatibility notes and caveats are collected in the [release notes](https://github.com/sobranie2406/modureader/releases).

When reporting an issue in [this repository](https://github.com/sobranie2406/modureader/issues), include your version, system, architecture, reproduction steps and a sample without private information. Never submit API keys, WebDAV passwords or configuration QR codes.

## Build from source

The pinned Flutter version is recorded in [.github/flutter-version](.github/flutter-version); dependencies are locked in pubspec.lock. You need Flutter's native toolchain for your platform. Building the tokenizer from source also requires Rust, including the appropriate mobile targets.

```sh
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter test --concurrency 1
# Run on the appropriate host platform:
flutter build macos --release --build-name "$(python3 scripts/release/verify_mobile.py --apple-build-name)"
# Configure Android release signing as described in docs/RELEASING.md first.
flutter build apk --release --target-platform android-arm64,android-x64 --split-per-abi
```

See [.github/workflows/build.yaml](.github/workflows/build.yaml) and scripts/release for the complete build and packaging procedure. The Dart package name remains `anx_reader` for compatibility with existing imports. The user-facing brand and application ID are Modu / `com.modu.reader`.

## Star history

Thank you to everyone supporting Modu. Click the chart to explore its growth on [Star History](https://www.star-history.com/?repos=sobranie2406%2Fmodureader&type=date&legend=top-left).

<a href="https://www.star-history.com/?repos=sobranie2406%2Fmodureader&amp;type=date&amp;legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=sobranie2406%2Fmodureader&amp;type=date&amp;theme=dark&amp;legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=sobranie2406%2Fmodureader&amp;type=date&amp;legend=top-left" />
    <img alt="Modu GitHub stars over time" src="https://api.star-history.com/chart?repos=sobranie2406%2Fmodureader&amp;type=date&amp;legend=top-left" width="800" />
  </picture>
</a>

## License and origins

The project is distributed under **GPL-3.0-or-later**; see [LICENSE](LICENSE).
Anx Reader's MIT copyright and license are preserved in [LICENSES/Anx-Reader-MIT.txt](LICENSES/Anx-Reader-MIT.txt).
ReadAny's copyright and license are preserved in [LICENSES/ReadAny-GPL-3.0-or-later.txt](LICENSES/ReadAny-GPL-3.0-or-later.txt).
See [UPSTREAM.md](UPSTREAM.md) and [NOTICE](NOTICE) for pinned upstream revisions, modification scope and third-party attribution. When distributing binaries, retain the licenses, identify your modifications and provide the complete corresponding source and build scripts for that version.

[Privacy (Chinese)](PRIVACY.md) · [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md)
