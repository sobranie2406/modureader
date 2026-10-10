# Display assets

## Current: Modu 1.2.0+10082

Feature claims follow the stable Modu publishing repository's `v1.2.0` commit `77dc238fb2ae2ce02455bd80c500ee9fd140f219`, not uncommitted application changes. The default Chinese homepage is [README.md](../../README.md); the English homepage is [README_EN.md](../../README_EN.md). `README_zh.md` keeps the previous Chinese URL working.

The 35 images in `showcase/cross-platform/` are the current homepage set, including later documentation artwork for the stable features. A macOS window sits behind an overlapping foreground iPhone, with a clear headline, light backdrop and soft shadows. Each major feature has its own image beside its description; Chinese artwork also includes framed vertical reading.

Artwork uses actual interfaces and code-supported behavior as its basis, with composition/redrawing by the built-in image-generation tool. It is composed showcase imagery rather than an untouched device capture. Preserve the actual Mac interface structure and control relationships; replace private content only inside that layout. The iPhone retains its Dynamic Island, status bar, bottom home indicator and iOS-style typography. Desktop recording markers and mouse cursors are removed.

Feature configuration/result pairs use phone configuration → Mac result. The phone stays in the foreground and shows controls or editing; the larger Mac window shows the resulting behavior. Bookshelf-home overviews instead show the library on both devices. Keep EN and ZH as separate localized assets (`*-en` and `*-zh`), matching labels, prose and language-specific examples. Do not mix the two languages into a single showcase panel.

| Assets | Phone configuration | Mac result |
| --- | --- | --- |
| `bookshelf-home-*` | Bookshelf home with fictional books and index/format labels | Bookshelf home with Indexed, original-format and Scanned badges |
| `library-*` | Create a folder for selected books | Books organized into a folder |
| `styles-*` | Font, thickness and spacing | Comfortable book typography |
| `scanned-pdf-*` | Original-page crop preview, per-page automatic crop and safety margin | The same page enlarged after cropping its outer margins |
| `ocr-*` | Optional OCR model cards, with V4 recommended and actual model sources | Current-page reflowed text with selection handles and reader toolbar |
| `css-*` | Visual CSS and highlight rules | Colored dialogue, wavy underlines and keyword highlights |
| `listening-*` | Narration template and voice description | Passage highlighting and compact playback controls |
| `skills-*` | A chapter-summary prompt | A reader AI answer and follow-up input |
| `selection-*` | Custom AI action and scope | Selection handles, toolbar and annotation controls |
| `translation-*` | Full-text engine, target language and bilingual display | Multiple inline translated paragraphs: English–Spanish for EN, English–Chinese for ZH |
| `dictionary-*` | Imported dictionary enabled | An offline word definition beside the book |
| `notes-*` | Highlight and comment editing | Saved book notes |
| `statistics-*` | Add a dashboard card | Reading charts and records |
| `vector-*` | Local embedding model | An AI answer citing retrieved chapter excerpts |
| `sync-*` | Record sync and database backup | Restored reading progress and annotation, without vector-index transfer |
| `backup-*` | Global settings export | Export completion and saved file location |

The opening `reading-*` banners and `vertical-zh` show reading layouts directly. PDF and OCR layouts were previously checked against the local Mac app and use original demonstration prose. PDF page surfaces must be white in both language variants, including the phone's original-page preview and Mac reading result; device backdrops can remain light. Crop settings show the original page and rectangle while the Mac shows that page's cropped result, without implying source-file overwrite.

OCR artwork shows Text Reflow/OCR Reflow directly in the reader for the current original page or its whole saved crop. It must not depict a region-selection popup as the reflow reader: only Extract opens that editor and can fill an editable AI input without automatically sending. Model downloads are optional; V4 is recommended, V5 upstream is ModelScope, and V3/V4 upstream is Hugging Face, with Gitee alternatives. Artwork is not an OCR accuracy measurement. Ordinary text books retain their normal controls; E-Ink refresh claims apply only to supported devices.

Only selected final assets are tracked; prompt drafts and discarded variants remain outside the published source tree. The 2026-10-10 update adds `bookshelf-home-zh.png` and `bookshelf-home-en.png` using the built-in image-generation tool, matching the existing Mac-window/iPhone composition. Unlike configuration/result pairs, both screens show the bookshelf home. Badge positions, labels and colors were checked against `book_item.dart` and `book_type_badges.dart`: green indexed status at the top left, colored original-format labels at the bottom left, plus an orange scanned label where applicable. All books, covers and progress values are fictional. These are labeled illustrative images, not untouched device screenshots; no new application/device testing is claimed.

Reading examples use the original [Chinese demonstration book](../examples/modu-reading-demo.epub) and [The Quiet Reader](../examples/modu-reading-demo-en.epub), plus original sample passages and dictionary definitions written for artwork. Source/redistribution terms are in [example books](../examples/README.md). Statistics, notes, retrieval excerpts and AI answers are illustrative data, not private accounts or performance benchmarks. No private bookshelf, notes, AI conversation or credentials are included. Settings illustrate features and are not necessarily factory defaults.

## Historical source archive

Source images were removed from the current tracked tree on 2026-10-03 to avoid shipping unused, duplicate or upstream marketing material. They remain recoverable in [the previous Git revision](https://github.com/sobranie2406/modureader/tree/dae8ecc4ef7ac34cfe252f8039008716d5cee6ff/docs/images), and local copies are ignored rather than deleted:

- `showcase/*.png`: previous iPhone-only renders used to compose the current artwork.
- `v1.1.9/`: Android and Mac Modu `1.1.9+10063` captures from 2026-10-01, including original demo books/settings.
- Seven older `*-macos.jpg` files: Modu `1.1.1+10033` captures from 2026-09-21, including the then-approved vertical-reading example.
- `Anx-logo.jpg`, `main.jpg`, `wide*.png`, `mobile*.png` and `zh/`: inherited Anx Reader promotional assets, not current Modu UI.

These retired assets retain local copies and Git history for recovery/design work. Do not republish upstream screenshots as current Modu. Dependencies' licenses, copyrights and provenance are outside this asset-cleanup scope.
