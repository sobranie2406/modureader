# Mobile quick marking: merge consecutive highlights

Current guide for Modu 1.2.0+10082. See the [documentation index](README.md) and [settings guide](SETTINGS.md).

Enable quick marking and select through the end of the body text on one page. Turn the page and continue selecting from the start of the next page's body text. Adjacent highlights with the same color and no annotations merge into one. Reverse continuation, overlapping selections and filling the text between two highlights are also supported. You do not need to drag one finger across both pages; this feature does not turn pages automatically.

- Continuity is determined from source-text positions, not text similarity or screen coordinates. Whitespace between paragraphs can connect selections; omitted text or an intervening image prevents a merge.
- Highlights with annotations, different colors, underlines and bookmarks remain separate.
- Selections can span multiple pages within the same EPUB chapter document. Different chapter files, PDF and fixed layouts are outside this feature's scope.
- The merged text and location range are stored in the database, retaining the first mark's ID, chapter and creation time. The merge is not merely a visual concatenation.
- Updating and removing merged records happens in one database transaction. A save failure rolls back and preserves the original marks. If a source mark is edited or deleted while saving, merging is abandoned and the current selection is saved separately.
- Desktop has no new quick-mark entry.

Existing automated coverage includes forward/reverse/overlapping selections, missing text, image gaps, annotation protection, CFI decoding, database merges, changed source records and transaction-failure rollback. The original verification did not assess page-turn selection feel on physical Android/iOS devices. This documentation update did not rerun tests or perform that device assessment.

Implementation: [quick-mark service](../lib/service/book_player/quick_mark_service.dart).
