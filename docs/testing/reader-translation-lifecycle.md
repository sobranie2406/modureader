# Reader translation content and stop-control regression

> Historical record of the 2026-09-16 source checks described below. No release version was specified; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

## Fix scope

- A translation-specific output filter removed `<think>` content, including case variants, nesting, unclosed tags and missing opening tags, without changing normal AI conversations.
- Reader translation ran only after explicit activation in the current session; requests were not restored from book display preferences.
- Only visible paragraphs were queued, with requests made one at a time. Visibility calculation transformed chapter iframe coordinates; offscreen preloaded chapters were not translated in advance.
- Stop controls were available in the translation panel and reader. Stopping or closing the reader cancelled the current request, cleared the waiting queue and discarded late results. Computation already received by a remote service could not be guaranteed to stop immediately.
- AI, free-translation and DeepL requests supported cancellation. Translation errors were no longer inserted as body text; an error stopped the current session.

## Automated verification (2026-09-16)

- `flutter test --reporter expanded`: 693 passed, 5 skipped.
- `MODU_JSDOM_ROOT=<jsdom安装目录> node --test test/reader_*.test.mjs`: 162 passed. The historical placeholder means the jsdom installation directory.
- Built-in Dart static analysis: no errors or warnings in the affected files, with 12 existing informational findings. Additional analyzer plugins could not complete because dependency retrieval failed; this was not recorded as all plugin checks passing.
- `npm run build` in `assets/foliate-js`: successful, retaining 3 existing topLevelAwait target-environment warnings.

Key cases in `test/service/translate/reader_translation_session_test.dart` and `test/reader_translation_lifecycle.test.mjs` covered reasoning-tag filtering, late results after stopping, no restoration after closing, repeated start/stop, a single-request queue, offscreen chapters, paragraph segmentation within containers and failed results.

## Device confirmation still pending

No real translation service was called and no package was built, published or installed over the existing app in this round. Android/macOS confirmation was still needed: the floating stop button appears after starting translation; stopping while awaiting a response appends no translation; leaving and reopening the book sends no requests; only visible paragraphs are translated after changing chapters; selected-text translation displays no reasoning content.
