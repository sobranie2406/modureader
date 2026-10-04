# Beta4 index memory and exit diagnostics verification

> Historical record for Beta4 build 6331 and the Beta3 report described below; this is not certification of the latest 1.2.0 release. See the [documentation index](README.md).

## Evidence and root-cause limits

User report: Beta3, iQOO Neo8 / Android 16, Chinese BGE with 512 dimensions; EPUB vectorization exited partway through, and a restart showed “Indexed.” System logs for that exit were unavailable, so LMK/OOM, an ONNX native fault or another exception could not be identified directly.

Shared risks confirmed by code inspection:

1. The background WebView used for index extraction still used the normal search cache of 3 minutes, potentially keeping EPUB JS/DOM/archive data in memory alongside subsequent model weights and vectors. It was replaced with a dedicated extraction session, disposed immediately after extraction completed, failed or was cancelled, without affecting normal reading or search sessions.
2. `FileKnowledgeIndexStore.save` previously called `jsonEncode` on the entire snapshot and wrote one large string. It was changed to line-by-line standard JSON writing, awaiting I/O for each line and retaining the temporary file and final rename. It no longer generated a JSON string the size of the entire file.
3. The old “Indexed” status read the full JSON and deserialized all vectors; refreshing the label after task completion could overlap with a resident model. It was replaced with a completion record of at most 4 KiB that checked the book fingerprint, index file size, mtime and chunk/vector counts without loading vectors. Small legacy indexes were migrated serially once. Legacy indexes larger than 4 MiB were not read in full in the background; their files were retained, with the verified label restored after manual rebuilding.
4. Float64List values returned by the Android channel were previously converted into per-element object lists, which the indexing task retained. Values were now retained/converted as compact Float64List without reducing precision; restored indexes also used compact vectors.
5. The local provider inherited an empty close and relied on a 15-second idle timer to release the model. An awaitable release was added and awaited before persistence, with fallback release on completion/exception. Release reused the serial inference queue and did not close a running session concurrently.
6. Content hashing stopped constructing one canonical string for the entire book and instead streamed UTF-8/SHA-256. Tests confirmed compatibility with the original algorithm.

“Indexed after restart” established only that a readable index file existed. It might have been an old index, or the app might have exited after the current save completed; the label alone could not prove normal vectorization completion. New building markers and crash checkpoints distinguished subsequent cases without fabricating earlier records retrospectively.

## Synthetic host comparison

Both modes of `test/native/index_memory_probe.dart` ran in separate macOS Dart processes. Each used 5,000 chunks of about 800 characters and 512-dimensional synthetic values; index sizes were about 43,171,737 / 43,181,764 bytes, with a slight whitespace-layout difference. ONNX was not loaded; no real books or keys were accessed.

| Stage | Old save/label flow RSS MiB | Compact vectors/line-by-line writing/small summary RSS MiB |
| --- | ---: | ---: |
| Process start | 213.6 | 212.9 |
| Retaining chunks and vectors | 284.4 | 241.6 |
| After saving | 491.5 | 248.2 |
| After label refresh | 592.8 | 248.4 |

This demonstrated reduced memory amplification during save/label stages in the local synthetic scenario. It did not prove that Android device crashes were fully resolved or measure the memory released from native model weights/EPUB WebViews. The old mode restored vectors with the current decoder, already more compact than the original Beta3 implementation; it was not a byte-for-byte execution of the old release package.

## Regressions and release gates

- Added tests covered standard JSON restoration; label reads without full load; rejection of stale summaries after index corruption/replacement; small-index migration and no automatic loading of large legacy indexes; missing, non-finite or invalid vectors not overwriting an old index; model release completing before save; cancellation during release/save not committing; incremental hash compatibility; and 384/512-dimensional channels retaining Float64List.
- Local full Flutter regression: 276 passed, 2 skipped; packaging tool tests: 18 passed. GitHub Actions was to rerun the full suite, reader JS and packaging validation on the Beta4 tag.
- Verification limits for the new native diagnostics were documented in `crash-feedback-verification.md`. Windows standalone subprocess tests and Apple native summary tests were added to desktop build gates.
- Packages for all platforms used new build 6331 from the same Beta4 tag, retaining the original Android signature, four bundled models, architecture validation, native installer formats, licenses and SHA-256 checks.
- The original iQOO Neo8 was still not connected; the original EPUB required device retesting. Beta4 did not upload logs by default. Users could choose to preview and submit redacted logs and device information.
