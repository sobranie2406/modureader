# Converted EPUB note-link compatibility — 2026-11-01

The supplied EPUB contains 62 paired annotations in 26 chapters whose forward and return links both point to themselves. The reader previously extracted the source paragraph. Another 90 semantic noteref links resolve correctly.

`repairSelfReferentialNotes` repairs only unique `_note_N` / `_noteBack_N` pairs with self-referencing marker links at both ends and nonempty annotation text. It updates href attributes during document loading. Already-correct links, missing or ambiguous targets and ordinary navigation remain unchanged; source files, text nodes, element order and IDs are preserved.

The actual supplied chapter documents were tested against the existing FootnoteHandler after repair: all 62 paired notes extract their correct annotation and all 90 semantic links retain their correct contents. Return targets were checked, and text and element identity remained unchanged. The EPUB itself is not committed or modified. Regression fixtures use synthetic text and cover split markers, rich note markup, repeated processing, missing pairs, duplicate IDs and unrelated links.

This is DOM/handler verification, not a physical-device UI acceptance test. The release retains the original nine architecture-specific installers and eight automatic-update targets; Mac/Windows universal packaging was withdrawn at the user's request.
