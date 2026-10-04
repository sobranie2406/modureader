# On-demand model mirrors

## Current: Modu 1.2.0+10082

This guide follows the Modu publishing repository's `v1.2.0` commit `77dc238fb2ae2ce02455bd80c500ee9fd140f219`. Model weights are optional downloads, not installer assets. The dated checks below are recorded historical results; no new downloads, inference runs or tests were performed for this documentation update.

Public repository: [sobranie2406/modu-models](https://gitee.com/sobranie2406/modu-models). Embedding release: [models-v1](https://gitee.com/sobranie2406/modu-models/releases/tag/models-v1).

On 2026-09-16, nine model/tokenizer assets, three licenses, a manifest and checksum file were published. Anonymous downloads of all four embedding models passed the application's size and SHA-256 checks, including E5 shard reassembly. New installations default to Hugging Face; existing source preferences are retained and users can select Gitee.

The mirror contains only the quantized Xenova ONNX models and tokenizers pinned in `assets/models/embeddings/manifest.json`. MiniLM retains Apache-2.0; BGE and E5 retain their MIT licenses, copyrights and provenance rather than becoming GPL-licensed Modu code.

## Preparing embedding assets

```sh
python3 scripts/release/model_mirror.py --fetch
```

This downloads missing public files, reuses SHA-256-verified caches and creates release assets in `build/model-mirror`; it does not upload. Verified identical Hugging Face files do not need to be fetched again.

- Asset names include the model ID, upstream 40-character revision and original filename.
- Files over 64 MiB are split into `.part-01`, `.part-02`, etc.; currently only E5 weights require this. Splitting preserves the original bytes without recompression. The client streams parts in order, then verifies the original full-file SHA-256. Truncated, reordered or corrupt weights cannot be used for inference.
- Include `manifest.json`, `SHA256SUMS` and the three original license files.
- Release notes identify all four Hugging Face repositories, revisions, sizes and licenses. Upload assets before publishing the release. Any Gitee account verification or public-review requirement is handled by the account owner.
- Verify public downloads, redirects and the reassembled original SHA-256. The recorded chain is Gitee Release → same-repository attach_files → `https://foruda.gitee.com/attach_file/`. The client accepts only the corresponding HTTPS paths; any new CDN needs verification and a precise allowlist entry.

## Verification commands (not run for this update)

```sh
flutter test --no-pub test/service/knowledge test/widgets/settings/vector_model_download_test.dart
python3 test/model_mirror_test.py
python3 test/release_package_test.py
```

Live checks are skipped by default. The opt-in embedding check uses approximately 218 MB of traffic and cleans up its temporary copies:

```sh
flutter test --no-pub --dart-define=MODU_VERIFY_MODEL_MIRROR=true test/service/knowledge/model_mirror_live_test.dart
```

## Builds and migration

`pubspec.yaml` declares the embedding manifest, not the weights directory. Release validation rejects stale artifacts containing weights/tokenizers. CI model files serve separate native inference checks: Android uses a test APK; Windows/macOS download from a local test server. The four-model inference checks are retained.

Upgrading preserves downloaded models; files with the same size and SHA-256 remain usable. Automatic indexing is off by default. Missing models prompt for a download rather than silently fetching all four. Changing source does not change revisions, dimensions or index format. Vector indexes are local and do not synchronize through WebDAV; local vectorization, retrieval and Stop Vectorization remain available.

## Lightweight OCR, separate from embedding models

Settings → OCR Model selects the model and download source. V4 is the recommended default with upstream selected; V5 is optional and does not replace an existing selection automatically. Only a model explicitly requested by the user is downloaded, and recognition runs locally. Model/source choices are included in global settings backups; weights are not. The old V4 cache path is preserved, and switching sources reuses files that pass SHA-256 verification.

| Model | Detection + recognition download | Upstream | Alternative |
| --- | --- | --- | --- |
| PP-OCRv4 Chinese/English (recommended) | 14.9 MiB | Hugging Face | Gitee |
| PP-OCRv5 Chinese/English mobile | 20.5 MiB | ModelScope | Gitee |
| PP-OCRv3 Chinese/English | 12.5 MiB | Hugging Face | Gitee |
| PP-OCRv3 English | 10.9 MiB | Hugging Face | Gitee |

Download size is not peak inference memory. Cards show size, actual upstream/mirror, verification state and progress; users can download/use, switch, reverify, cancel or confirm deletion of that model's local files. Deletion is restricted to its listed model/temporary files and preserves books, recognized text, reflow caches and other models. Downloads, deletion and inference are coordinated to avoid concurrent file use.

On 2026-10-04, [ocr-v1](https://gitee.com/sobranie2406/modu-models/releases/tag/ocr-v1) was published with eight model files and four provenance/license/manifest/checksum assets, without replacing `models-v1`. Recorded checks verified anonymous downloads, byte lengths and SHA-256 for all four Gitee model sets and the V5 upstream files, plus Mac native inference for all four models. These are historical checks, not all-platform accuracy or performance guarantees.

Exact files, revisions and checksums are in `lib/service/ocr/ocr_models.dart` at the release commit. V3/V4 pin a Hugging Face revision; V5 pins RapidOCR distribution `v3.9.2` and its official SHA-256. Models retain Apache-2.0 and their original bytes; they are not retrained. There is no GitHub-weights source option for these ONNX files: their actual upstream distributors are Hugging Face and ModelScope.

Prepare OCR assets with:

```sh
python3 scripts/release/ocr_model_mirror.py --source <downloaded-original-model-directory>
```

Output goes to `build/ocr-model-mirror` without uploading. Inputs use the original filenames; mismatched size or SHA-256 prevents copying.

Opt-in live verification uses approximately 80 MiB; routine regressions are separate:

```sh
flutter test --no-pub --dart-define=MODU_VERIFY_OCR_MIRROR=true test/service/ocr_model_live_test.dart
flutter test --no-pub test/service/ocr_model_store_test.dart test/widgets/settings/ocr_model_test.dart test/service/config_transfer
```

The downloader accepts only HTTPS redirects allowed for the selected source and does not silently switch on failure. Recognition uses at most two CPU threads. V5's larger alphabet has corresponding input-width and output-tensor limits to bound single-line inference output.

In 1.2.0, Text Reflow/OCR Reflow process the current page or its whole saved crop directly into the reader. Only Extract opens region selection and can populate an editable AI draft without sending. See [scanned-document status](SCANNED_DOCUMENT_DEVELOPMENT.md) for current scope and earlier cancellation/restoration history.
