# Modu documentation

Current documentation baseline: **stable 1.2.3+10090**, checked against source on 2026-10-08. The detailed feature guides identify their source revision and validation limits.

[English homepage](../README.md) · [中文首页](../README_zh.md)

## User guides and policies

English is the default. These core documents have separate Chinese editions:

| Document | English | 简体中文 |
| --- | --- | --- |
| Detailed features, workflows and limits | [Feature guide](FEATURES.md) | [详细功能介绍](FEATURES_zh.md) |
| Settings and features | [Settings guide](SETTINGS.md) | [设置指南](SETTINGS_zh.md) |
| Privacy and network behavior | [Privacy](../PRIVACY.md) | [隐私说明](../PRIVACY_zh.md) |
| Security reporting | [Security](../SECURITY.md) | [安全报告](../SECURITY_zh.md) |
| Contributing | [Contributing](../CONTRIBUTING.md) | [参与贡献](../CONTRIBUTING_zh.md) |

Other guides are maintained as a single English edition. Release notes from 1.2.0 onward put English before Chinese.

## Features and migration

- [PDF, scanned books, crop, image enhancement and OCR](SCANNED_DOCUMENT_DEVELOPMENT.md)
- [CSS profiles and regex highlights](CSS_PRESETS.md)
- [AI retrieval and book indexes](AI_INDEX_USAGE.md)
- [AI reasoning parameters](AI_REASONING_CONTROL.md)
- [Local indexing and reading controls](INDEX_SYNC_AND_READING_CONTROLS.md)
- [WebDAV record sync and migration](WEBDAV_RECORD_SYNC.md)
- [S3-compatible object-storage sync](OBJECT_STORAGE_SYNC.md)
- [WebDAV request budgets, cooldowns and maintenance](development/webdav-request-policy.md)
- [ANX Reader backup import](ANX_BACKUP_IMPORT.md)
- [Local dictionaries](LOCAL_DICTIONARIES.md)
- [Markdown books](MARKDOWN_BOOKS.md)
- [Reading-position links in notes](NOTE_READING_LINKS.md)
- [Quick-mark merging](QUICK_MARK_MERGE.md)
- [Speech-rate recovery](TTS_RATE_RECOVERY.md)
- [Paragraph narration](tts-paragraph-narration.md)
- [Troubleshooting](troubleshooting.md)

## Building and maintenance

- [Installation, signing and release procedure](RELEASING.md)
- [Current release notes](RELEASE_NOTES.md) · [Published releases](https://github.com/sobranie2406/modureader/releases)
- [Model mirrors](MODEL_MIRROR.md) · [App update mirrors](UPDATE_MIRROR.md)
- [Issue triage](issue-triage.md)
- [Testing scope and historical evidence](TESTING.md)
- [Architecture/source audit](PROJECT_AUDIT.md)
- [Demo books](examples/README.md) · [Screenshots and artwork](images/README.md)
- [Upstream attribution](../UPSTREAM.md) · [NOTICE](../NOTICE) · [License](../LICENSE)

## Historical evidence

Dated tests, earlier preview notes and implementation milestones retain their original versions, test counts and limits. They are not fresh 1.2.3 device acceptance claims. For current instructions, start with the feature and settings guides above.

- [Reader regression evidence](tts-reader-regression.md)
- [Background narration diagnostics](tts-background-chapter-recovery.md)
- [Crash-report diagnostics](crash-feedback-verification.md)
- [Android ONNX/haptics](android-onnx-haptics-verification.md)
- [Android vector memory](android-vector-memory-verification.md)
- [Earlier index-memory evidence](beta4-index-memory-verification.md)
- [Per-feature test records](testing/)
- [Preview 3](releases/1.1.12-preview.3.md) · [Preview 4](releases/1.1.12-preview.4.md)

Upstream changelogs, vendored dependency documentation and license texts remain in their original form. Historical Fastlane/store templates are not current Modu distribution instructions.
