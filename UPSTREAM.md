# Upstream sources

Modu is an independently modified GPL-3.0-or-later derivative application.
本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，感谢原作者及贡献者。
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

## Modifications (2026)

Modu branding and application identifiers; AI reading skills and per-model parameters;
hybrid RAG, ONNX models and background indexing queue; translation and TTS services;
encrypted opt-in credential sync and backups; local-file access restrictions;
PDF import/navigation fixes; multi-platform release packaging. See git history.

## Bundled embedding models (build 6326)

All four quantized ONNX models and tokenizer files are distributed in installers.
Exact Xenova repository revisions, file sizes and SHA-256 hashes are pinned in
`assets/models/embeddings/manifest.json`; `scripts/release/bundle_models.py` fetches
them at build time. No weight modifications are made by Modu. Native inference
uses locally prepared assets, with no runtime model download required.

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

## Vendored libraries

- `third_party/hf_tokenizers`: hf_tokenizers 1.2.1, MIT, Yusuf Ihsan Gorgel.
  Original Dart API and Rust tokenizers implementation retained; Modu adds explicit
  mobile/ARM cross-compilation in the build hook. Original license is included.
- `third_party/icons_plus`: icons_plus 5.0.0, MIT; existing compatibility override.
  Icon brands remain the property of their respective owners.
- `assets/foliate-js`: Foliate-js, MIT; PDF.js and other embedded components retain
  their license notices. Modified renderer code is included in the source release.
- ONNX Runtime: Microsoft, MIT. Windows/Linux use 1.22.0; Apple uses 1.23.0.
  Android pins 1.24.3 to address ARM CPU instruction detection crashes
  (https://github.com/microsoft/onnxruntime/issues/27282). These versions' LICENSE and
  ThirdPartyNotices.txt are preserved in LICENSES and copied into packages.
- Linux WPE/WebKit libraries: distribution-provided dynamic libraries. Packages
  retain the Debian copyright files and record exact corresponding source
  package versions in SOURCE.txt; the app remains dynamically linked.
