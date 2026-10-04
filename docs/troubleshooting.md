# Modu troubleshooting

Current guide for Modu 1.2.0+10082. See the [documentation index](README.md), [settings guide](SETTINGS.md) and [installation guidance](RELEASING.md).

## Import or reading problems

- Confirm the format is EPUB, PDF, MOBI, AZW3, FB2, TXT, MD or Markdown and the file has downloaded completely. Try the project's [original demo book](examples/modu-reading-demo.epub) to distinguish an environment problem from a book-specific problem.
- Spaces and Chinese characters in ordinary filenames are not inherently invalid. Preserve the original book and test with a copy.
- PDFs and confirmed scanned-image EPUBs use dedicated original-page controls, including crop and image enhancement. Ordinary text books keep their text-reader controls.
- For scanned pages, **Text reflow** prefers an existing text layer; **OCR reflow** performs local recognition. Download a lightweight model through **Settings → OCR models** when needed. OCR runs on-device without an API key; sending extracted text to an online AI service is a separate action. Recognition quality depends on scan clarity, language and layout; check the result against the original. This is not automatic whole-book OCR.
- Password-protected PDFs are unsupported and DRM compatibility is not guaranteed. Text layers, tables of contents and layout affect extraction and navigation.
- On Android, check that the system WebView works. See [release guidance](RELEASING.md) for platform dependencies, signing and installation requirements. Stable distribution has eight application packages: Android ARM64, iOS ARM64, and ARM64/x64 for each of macOS, Windows and Linux. There is no Android x64 release package.

## Remote library connection or download problems

Use **Settings → Library WebDAV**, which is separate from the existing sync connection. Enter the final directory URL and an account with listing/read access. Prefer HTTPS; the remote-library client refuses redirects, so use the destination URL directly.

Saving retains the server, username and password locally across restarts, without additional local encryption. Older configurations that did not save a password need it entered and saved once. **Sync → Sync API keys** optionally includes the connection/password in encrypted automatic sync; participating devices need the same sync-encryption password. Clearing the connection propagates to other opted-in devices. It does not delete books or server files.

Only one download runs at a time, up to 512 MiB per file. Leaving the remote-library tab cancels an unfinished download; once import starts, wait for it to finish. Check local free space and never post credentials or private directory URLs.

For settings migration, use the top-level **Settings → Global settings backup**, with settings files or `modu:` links. These exports are not encrypted and can contain restorable credentials when included. Global and separate TTS configuration export have no QR export. The encrypted service-settings option belongs to the database ZIP backup, a different backup workflow; see [Settings](SETTINGS.md).

## Indexing failures or unexpected exits

Check the task result and selected model in the book menu. Local embedding and online AI chat are separate settings; remote models require valid API configuration.

Re-vectorize after changing the embedding model. An old indexed badge does not establish that the latest task succeeded. Do not uninstall the app merely to clear an error. Vector indexes remain local; vector-index synchronization has been removed.

Use the [current release](https://github.com/sobranie2406/modureader/releases/latest) and read its device-specific limitations. For retrieval scope and fallback, see [AI and book indexes](AI_INDEX_USAGE.md).

## Reporting a bug

Open **Settings → Bug reports and feature requests → Report a bug** and describe the version/build, steps and outcome. Environment information and crash diagnostics are separately optional. Preview the report, then follow the submission flow in [issue triage](issue-triage.md) using [this repository's GitHub templates](https://github.com/sobranie2406/modureader/issues/new/choose). Reports with diagnostics are copied in full for you to paste into GitHub; opening GitHub does not submit them.

Missing or delayed diagnostics do not prove that no crash occurred. Never publish book text, private books, API keys, WebDAV passwords, private configuration links/QRs or unreviewed full logs. Ordinary logs under **Advanced → Logs** are different from optional sanitized crash diagnostics. The [crash verification record](crash-feedback-verification.md) documents earlier implementation checks and their limits; it does not claim the reported crashes were fixed.

This update checked documentation against stable source behavior. It did not run builds, tests or device acceptance checks.
