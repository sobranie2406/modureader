# Modu localization translation instructions

Maintenance baseline: **1.2.0+10082**, reviewed 2026-10-04. Match actual catalog keys and current UI, not historical prompts. User-edited prompts are preserved, and settings backups store overrides rather than redundant built-in defaults.

Translate the `lib/l10n/modu_source.json` application catalog for the assigned language. This is a software-localization task, not an article: emit a flat JSON object of identical keys and translated string values. Use `apply_patch` to create/edit translation files. Do not edit source or other languages. Preserve existing user changes.

## Analysis and shared context

Audience: everyday ebook readers. Style: natural, concise technical UI language. Use a consistent vocabulary for settings, reading, speech synthesis, selection toolbar, highlights, backups, WebDAV synchronization and AI prompts. Preserve Modu, ANX Reader, OpenAI, MiMo, GitHub, Gitee, API, CSS, JSON, Markdown, IPA, URLs, version numbers and technical identifiers. Avoid unnecessary annotations in UI labels.

Each source entry has Chinese `zh` and/or English `en`. Prefer available English for UI terms, using Chinese to disambiguate; preserve all substantive requirements of long prompts. Translate the complete prompt, not just its first sentence. Users can edit prompts, but bundled defaults must display in their chosen language. Do not remove safety, no-spoiler, dictionary scope, citation, evidence or formatting requirements.

Preserve placeholders literally: `{selection}`, `{{selection}}`, `{{language_locale}}`, `{{previous_content}}`, `{{to_locale}}`, `{{from_locale}}`, `{{text}}`, `{{contextText}}` and all other brace variables. Preserve backtick-enclosed API/tool/property names exactly. Never replace a source placeholder with a translated name. Text may contain newlines: preserve valid JSON escaping.

Do not translate IDs. Localize display strings and instructions only. Chinese traditional and classical variants should be legible and terminology-consistent; classical Chinese UI concise, prompts retain full precise requirements. For Chinese simplified, preserve supplied Chinese and translate English-only entries.

For AI prompts referring to output language, use the user's chosen language instead of requiring the original text's language, except explicit translation targets (`{{to_locale}}`) and explicit requirements of a user-defined template. For the selection translation template, translate foreign text into the user's chosen language, or text already in that language into English (English users: explain/translate into English as appropriate). Do not add arbitrary translation into Chinese for non-Chinese users.

AI Knowledge asks for relevant knowledge in the appropriate language, not mandatory pinyin, IPA, example sentences or English translations. Selection commands choose selected text only by default, optional context and optional online search; reading skills are managed separately. Translate these settings without inventing extra requirements.

Also fill missing keys in your assigned `lib/l10n/app_<locale>.arb`, using English ARB as reference, including unchanged placeholder metadata. Never overwrite existing translations. No code edits, generation commands or build/test processes are needed. Report the exact files changed.
