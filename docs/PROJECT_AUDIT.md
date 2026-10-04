# Project identity and documentation cleanup record

## Current: Modu 1.2.0+10082

The current product baseline is the stable Modu publishing repository's `v1.2.0` commit `77dc238fb2ae2ce02455bd80c500ee9fd140f219`. Current guides must describe that release rather than uncommitted application changes. The homepage is English `README.md` with a separate Chinese `README_zh.md`; `README_EN.md` redirects the old English address. Single-version guides use English, while dated historical records retain their evidence and version boundaries.

Current document reading includes PDF and classified image books, optional local OCR, current-page/cropped-whole-page reader reflow and Extract's region editor/editable AI input. The earlier OCR cancellation was superseded by later implementation. Ordinary text books retain their normal reader. Vector indexes stay local; Stop Vectorization remains available. Release guidance uses eight installers, excluding Android x64, GitHub-first checking and the same resolved download source, with browser DMG downloads on macOS rather than an in-app file-hash claim. See the [scanned-document status](SCANNED_DOCUMENT_DEVELOPMENT.md), [indexing guide](INDEX_SYNC_AND_READING_CONTROLS.md) and [update mirror](UPDATE_MIRROR.md).

The current homepage set contains 33 images, following later documented expansion of the nine-image set retained on 2026-10-03. Current imagery preserves actual Mac layout, places phone configuration in the foreground and Mac results behind it, uses white PDF pages, and separates EN/ZH artwork. These are display/provenance requirements, not new app or device verification. See [display assets](images/README.md).

No new tests, builds, device checks or full security audit were performed for this documentation update. The records below describe earlier work and do not move tags or alter published assets.

## Historical identity cleanup

The original audit covered tracked files on the GitHub main branch from `8021c97c`, homepage text, app/configuration copy, store metadata, release scripts and the five GitHub release descriptions then present.

### Completed at that stage

- Maintained only Chinese `README.md` and English `README_EN.md` at the root. Removed Russian/Turkish homepages containing upstream branding/download/feedback/sponsorship links and inconsistent license wording, plus a duplicate Chinese redirect. This historical language arrangement was superseded by the 2026-10-03 change below.
- Corrected troubleshooting setting paths and log submission: no requirement to remove filename spaces or publish unchecked complete logs. Added separate remote-library guidance.
- Rewrote Chinese/English store-copy drafts, removed unsupported promotional claims and unmaintained Russian drafts, and clarified that drafts do not indicate store publication. Fastlane references and historical images were not current Modu promotional assets.
- Archived upstream version history in `docs/upstream/anx-reader-changelog.md`; app-facing `assets/CHANGELOG.md` contains the current Modu summary, with detailed history in individual releases.
- Pointed issue-handling examples to this repository and documented the actual automation scope without enabling additional upstream policies.
- Removed nine unused upstream packaging/store-release workflows, retaining the current complete build, quality checks and historical native repackaging workflow.
- Removed disabled in-app-purchase pages/state/services, product IDs, upstream privacy/terms links, the plugin and corresponding Apple native-lockfile dependencies. Reading no longer passes through purchase checks.
- Stopped calling the whole project Beta in security documentation; explained tags, signing, security audits and actual test scope separately.

### Deliberately retained

- `LICENSE`, `NOTICE`, `LICENSES/`, `UPSTREAM.md` and dependencies' own READMEs, copyright and provenance.
- Internal Dart package name `anx_reader`, old-data migration paths and sanitized stack rules; string matches alone do not justify global replacement.
- The user-requested `fonts.anxcye.com` font service.
- Real repositories for pinned third-party dependencies, which are not Modu download/feedback destinations.
- Upstream-scoped maintenance-task protections, without changing existing issue policy.
- Original screenshot/historical-asset provenance in `docs/images/README.md` and `fastlane/metadata/README.md`. Upstream screenshots were not republished as current Modu UI.

### Recorded verification and version boundary

`test/project_identity_test.py` was added to quality checks to constrain homepage languages, reject incorrect download/feedback links, check the current changelog summary, prevent purchase/old-release-entry regressions and confirm license/font-service preservation.

This cleanup changed main-branch source without moving released tags, overwriting installers or rewriting commits. Historical tag source archives still show their original files; source cleanup is not an update already installed on users' devices.

## Historical source-asset cleanup (2026-10-03)

- Changed the homepage arrangement to English `README.md` and Chinese `README_zh.md`, retaining `README_EN.md` as an old-address redirect and updating identity regressions.
- Removed 105 old promotional images, historical screenshots and intermediate phone renders, plus 19 obsolete store-image symlinks, from current Git tracking: 67,867,671 bytes (about 64.7 MiB). Local source assets and Git history were retained.
- Retained the nine then-current `docs/images/showcase/cross-platform/` images, provenance documentation and original example books. The current 33-image set reflects later expansion; it does not change this historical count.
- Retained PDF/EPUB regression fixtures, reader build resources used by the app, runtimes referenced by Windows build scripts, third-party dependencies and all licenses.
- The then-tracked tree showed no APK/AAB/IPA/DMG installers, crash dumps, build-cache directories or common private-key/token-pattern matches. This was file/pattern screening, not a complete history or binary-secret audit.
- Added ignore rules for retired assets and installer/diagnostic files without rewriting Git history or deleting releases, tags, branches or the local library.
