# Markdown books

Source-reviewed for Modu 1.2.3+10090 on 2026-10-08 ([b6bf820a](https://github.com/sobranie2406/modureader/tree/b6bf820a4a3fd5ee1f657c80c061f64349a1aedb)). Detailed workflows and current boundaries: [English](FEATURES.md) · [简体中文](FEATURES_zh.md). See the [documentation index](README.md) and [settings guide](SETTINGS.md).

Bookshelf import, desktop drag-and-drop, system sharing and book replacement accept `.md` and `.markdown` (case-insensitive). Remote WebDAV library's books-only filter includes Markdown, with an MD-only filter also available.

Use UTF-8. Import converts Markdown to EPUB in the background, then uses the existing reader, notes, narration and library-sync workflows. Receiving devices do not convert it again. The selected original document is not modified; import cleans up its temporary copy.

- The first level-one heading supplies the title; otherwise the filename is used.
- Headings at levels one through six form a hierarchical table of contents. Both `#` and underline-style headings are supported; `#` inside code blocks does not create a chapter.
- Bold, italics, strikethrough, block quotes, ordered/unordered lists, tables, code blocks, links and basic static HTML are preserved. Heading-anchor links still work after splitting into chapters.
- Embedded Base64 PNG, JPEG, GIF and WebP images are supported. Single-file import does not read adjacent folders automatically. Relative-path images show fallback descriptions; network images become clickable links and are not downloaded automatically. Package complete text/image resources as EPUB if needed.
- Scripts are not executed. Event handlers, iframes, external styles and unsafe links are removed. Mermaid, LaTeX and other Markdown extension programs are not executed.
- A file is limited to 64 MiB; blank files fail import. Long text without headings is divided at content-block boundaries to avoid breaking tables or code blocks.

Parsing uses the Dart-maintained [markdown](https://pub.dev/packages/markdown) library. Generated content is sanitized with an allowlist and serialized as XHTML.

Implementation: [Markdown-to-EPUB converter](../lib/service/convert_to_epub/markdown/convert_from_markdown.dart). This documentation update reviewed source behavior without running imports or tests.
