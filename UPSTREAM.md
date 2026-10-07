# Upstream sources

Modu is an independently modified GPL-3.0-or-later derivative application.
It derives from **Anx Reader** and **ReadAny (Reader Any)**. Thank you to their authors and contributors.
It is not affiliated with, endorsed by, or an official release of either upstream.

## Anx Reader

- Repository: https://github.com/anxcye/anx-reader
- Imported commit: 107f4fa74db0e7247c846c49d6211df3edf9887c
- License: MIT, preserved in `LICENSES/Anx-Reader-MIT.txt`.
- Role: Flutter app, reader UI, rendering, local library, notes, statistics, and WebDAV baseline.

## ReadAny

- Repository: https://github.com/codedogQBY/ReadAny
- Reference commit: 021137eb3dbb398096193ee7b6819e665a281d32
- License: GPL-3.0-or-later, preserved in `LICENSES/ReadAny-GPL-3.0-or-later.txt`.
- Role: source and behavior reference for reading agent, hybrid RAG, AI tools, provider configuration, and TTS.

Ported files retain source attribution and GPL-3.0 compatibility. Upstream updates are reviewed and merged explicitly.

### Object storage synchronization references

- ReadAny reference commit `40d4a8d6131394e139e073d04a72d955611ff065`: `packages/core/src/sync/s3-backend.ts`, `s3-paths.ts` and the Expo `S3Form.tsx` informed transport boundaries and connection fields. Modu implements its own Dart HTTP transport and uses its existing record merge engine rather than adopting ReadAny's cloud database format.
- Readest reference commit `4c3ccfe85d4afd81e674b67d6a0627d83ba0744d`: `apps/readest-app/src/components/settings/integrations/S3Form.tsx` informed the settings interaction. Repository: https://github.com/readest/readest. No Readest source code is copied into this implementation.
- Signature regression values are checked against AWS `@smithy/signature-v4` and the published S3 V2 signing example. No AWS JavaScript SDK is bundled in Modu.

## Modifications (2026)

Modu branding and application identifiers; AI reading skills and per-model parameters;
hybrid RAG, ONNX models and background indexing queue; translation and TTS services;
encrypted opt-in credential sync and backups; local-file access restrictions;
PDF import/navigation fixes; multi-platform release packaging. See git history.

## On-demand embedding models

Reviewed for Modu 1.2.0 on 2026-10-04. Embedding weights and tokenizer files are
not bundled in production installers. Pinned upstream revisions, file sizes and
SHA-256 hashes are recorded in `assets/models/embeddings/manifest.json`.
Users choose Hugging Face or Gitee and download verified files on demand.
Prepared models run locally; Modu does not modify their weights. Missing models
are not silently downloaded. CI uses `scripts/release/bundle_models.py` for
isolated inference fixtures, not production asset installation. See
[model mirrors](docs/MODEL_MIRROR.md) and [Privacy](PRIVACY.md).

- MiniLM: https://huggingface.co/Xenova/all-MiniLM-L6-v2; original model
  https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2, Apache-2.0.
  License preserved in `LICENSES/MiniLM-Embedding-Apache-2.0.txt`, from
  https://github.com/UKPLab/sentence-transformers/blob/master/LICENSE.
- BGE English/Chinese: https://huggingface.co/Xenova/bge-small-en-v1.5 and
  https://huggingface.co/Xenova/bge-small-zh-v1.5; original models by BAAI,
  https://huggingface.co/BAAI/bge-small-en-v1.5 and
  https://huggingface.co/BAAI/bge-small-zh-v1.5, MIT.
  License preserved in `LICENSES/BGE-Embedding-MIT.txt`, from
  https://github.com/FlagOpen/FlagEmbedding/blob/master/LICENSE.
- E5: https://huggingface.co/Xenova/multilingual-e5-small; original model
  https://huggingface.co/intfloat/multilingual-e5-small, MIT.
  License preserved in `LICENSES/E5-Embedding-MIT.txt`, from
  https://github.com/microsoft/unilm/blob/master/LICENSE.

## On-demand OCR models

PP-OCRv4 Chinese/English is recommended; v5 mobile Chinese/English, v3
Chinese/English and v3 English are available. The catalog pins revisions,
file sizes and SHA-256 in `lib/service/ocr/ocr_models.dart`. v4/v3 originate
from SWHL/RapidOCR on Hugging Face; v5 uses RapidAI/RapidOCR on ModelScope.
Gitee provides mirrors of the same files. Models download only on request;
recognition runs locally. The PaddleOCR Apache-2.0 license is preserved in
LICENSES/PaddleOCR-Apache-2.0.txt; model provenance is also recorded in NOTICE.

## Vendored libraries

- `third_party/flutter_inappwebview_windows`: 0.7.0-beta.3, Apache-2.0,
  from https://github.com/pichillilorenzo/flutter_inappwebview. Modu fixes native
  JavaScript callback null-pointer handling; details in `MODU_PATCH.md` and
  original LICENSE are preserved alongside the source.
- `third_party/hf_tokenizers`: hf_tokenizers 1.2.1, MIT, Yusuf Ihsan Gorgel.
  Original Dart API and Rust tokenizers implementation retained; Modu adds explicit
  mobile/ARM cross-compilation in the build hook. Original license is included.
- `third_party/icons_plus`: icons_plus 5.0.0, MIT; existing compatibility override.
  Icon brands remain the property of their respective owners.
- `third_party/audioplayers_android`: audioplayers_android 5.2.0, MIT, Blue Fire.
  Explicit Android MediaPlayer.start() after setting the rate restores system
  playback tracking/media-key routing and wake-lock activation. See its
  MODU_PATCHES.md and LICENSE; upstream https://github.com/bluefireteam/audioplayers.
- `assets/foliate-js`: Foliate-js, MIT; PDF.js and other embedded components retain
  their license notices. Modified renderer code is included in the source release.
- ONNX Runtime: Microsoft, MIT. Windows/Linux use 1.22.0; Apple uses 1.23.0.
  Android pins 1.24.3 to address ARM CPU instruction detection crashes
  (https://github.com/microsoft/onnxruntime/issues/27282). These versions' LICENSE and
  ThirdPartyNotices.txt are preserved in LICENSES and copied into packages.
- Linux WPE/WebKit libraries: distribution-provided dynamic libraries. Packages
  retain the Debian copyright files and record exact corresponding source
  package versions in SOURCE.txt; the app remains dynamically linked.
