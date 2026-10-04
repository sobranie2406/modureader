# Original demonstration books

## Current: Modu 1.2.0+10082

These two books were written for Modu's public documentation. They are not private library content or actual model-generated answers. The text and EPUBs are distributed with the project under GPL-3.0-or-later; their complete original text is retained in the generator scripts for reproducible public distribution.

| Language | Book | Content |
| --- | --- | --- |
| Chinese | [阅读，让思考慢下来](modu-reading-demo.epub) | Six chapters, 50 paragraphs and approximately 3400 Chinese characters on reading, AI reading companions, notes, questions, knowledge connections and rereading |
| English | [The Quiet Reader](modu-reading-demo-en.epub) | Six chapters, 46 paragraphs and approximately 2200 words, originally written in English |

Both EPUBs have a navigable six-chapter table of contents and can demonstrate page turns, chapter navigation, continuous reading, selection tools and settings. The Chinese book supports framed vertical-reading examples; the English book supports English UI and horizontal-reading examples. The English book is not a machine translation of the Chinese book. Neither contains private material or excerpts from third-party books.

These are ordinary text EPUBs, not scanned-book classification fixtures. Their use in artwork does not imply PDF crop/OCR controls apply to ordinary text books. PDF/OCR artwork uses separate original demonstration passages with white page backgrounds.

## Rebuilding

Run from the repository root using only the Python standard library:

```sh
python3 docs/examples/make_screenshot_book.py
python3 docs/examples/make_english_screenshot_book.py
```

The scripts generate EPUBs beside their sources. Both include an EPUB 3 manifest, spine and navigation document, with the uncompressed `mimetype` entry first in the archive.

Screenshot versions, device roles and provenance are described in [display assets](../images/README.md): preserve the actual Mac interface layout, show phone configuration in the foreground and the Mac result behind it, and keep EN/ZH artwork separate. Demonstration answers, statistics and excerpts are illustrative, not recognition or performance benchmarks.

This document is aligned to the stable Modu publishing repository's `v1.2.0` baseline (`77dc238fb2ae2ce02455bd80c500ee9fd140f219`). No example books were regenerated and no application tests were run for this documentation update.
