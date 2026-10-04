# Return to source text from exported notes

Current guide for Modu 1.2.0+10082. See the [documentation index](README.md) and [settings guide](SETTINGS.md).

In newly exported Markdown notes, click an excerpt or **Open in Modu** to launch Modu at the corresponding reading position. TXT, copy and CSV exports also include `modu://read` links. Whether they are clickable depends on the viewer's custom-protocol support.

The existing excerpt format (`Excerpt: 【…】` in English), highlights and created/last-modified timestamps are retained. Older exports must be exported again to receive links.

## Book matching

- Links match the same book-file version by MD5, not a local database ID, so an identical file can be located across devices.
- Older records without MD5 require the title, author and creation time to match together.
- If the file is not downloaded, Modu asks whether to download it. If the book is missing from the bookshelf or its version has been replaced, Modu reports that instead of importing a book automatically or opening another version.
- If multiple copies of the same file exist, the user chooses one.
- Links contain no book text, accounts, keys or local file paths, but do contain the title, author and source CFI position.

## Platform integration

Android uses a VIEW intent restricted to `modu://read`; iOS/macOS register the `modu` scheme. iOS UIScene explicitly forwards reading links while other file sharing retains its existing handling.

Windows installers register the protocol for the current user and forward links to an already-open window. A portable copy requires protocol registration through the installed version first, with that installation path kept available. Linux DEB desktop entries register the protocol and pass URLs to the existing instance.

The receiving app and system association must support this feature. Plain-text viewers and some Markdown viewers block custom-protocol links; use a viewer that allows external links. CFI locations are reliable only while the original book file remains unchanged.

Stable distribution provides eight application packages: Android ARM64 and iOS ARM64, plus ARM64/x64 for macOS, Windows and Linux. There is no Android x64 release package. Protocol support does not imply every viewer or device has been tested.

## Regression coverage

```sh
flutter test --no-pub test/service/notes test/utils/reader_initial_input_test.dart test/widgets/settings/global_settings_export_test.dart
```

Existing coverage includes multiple excerpt links, special characters, format compatibility, book matching, notes without locatable positions, cold-start buffering, repeated clicks and failure recovery. Native entry points were checked separately through platform builds and configuration tests. This documentation update did not rerun those checks.

Implementation: [note export](../lib/service/notes/export_notes.dart).
