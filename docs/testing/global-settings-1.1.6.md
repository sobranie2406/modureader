# 1.1.6 global settings migration verification

> Historical record for 1.1.6 and the 2026-09-26 checks described below; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

Final interaction: import/export of global settings through a file, QR code or modu link only, with no feature-module selection. Accounts, passwords and API configuration were controlled by a separate switch, off by default, applying to both import and export. Legacy individual links remained compatible; the confirmation page described the affected scope from the actual fields.

## Check scope

An internal ownership table covered appearance, reading, CSS, text-selection search, AI, skills, vectors, narration, translation, sync, remote library, notes, statistics, network and advanced settings. It supported completeness and isolation regressions without adding user-facing module controls.

- Encode/decode round trips for files, compressed links and actual PNG QR codes.
- Preservation of books, progress, local fonts, background files, storage paths, per-book choices and the sync encryption password.
- Validation of nested types, CSS parameters, page-turn regions, provider models and regex chapter rules before import.
- With the credentials switch off, export excluded sensitive containers and import did not overwrite credentials on the target device.
- Format 2 explicitly recorded defaults; only allowlisted configuration could be cleared, not credentials, local files or arbitrary preferences.
- Format 1 restored only present values under the old rules; legacy AI/TTS/WebDAV/library links remained readable.
- Added omitted built-in excerpt-background IDs, remote-library display preferences and reading-background blur/opacity/alignment parameters.
- Imported synchronization settings remained disabled until manually enabled on the device.
- A generated dense QR-code example with failed finder-pattern detection used pure QR decoding as a fallback.

## Automated results (2026-09-26)

- Configuration migration and targeted UI tests: 123 passed.
- Full Flutter regression: 1226 passed, 7 skipped according to test conditions.
- Reader JavaScript: 259 passed.
- Python release and project checks: 57 passed.
- Static analysis had no errors; existing informational findings were not release blockers.

Tests used only synthetic configurations and test credentials. Local resources such as fonts and dictionaries were outside this settings format. Users still needed to review text in arbitrary custom CSS, prompts and URLs and should not embed private credentials there.
