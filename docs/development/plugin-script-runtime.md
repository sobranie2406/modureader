# Reviewed JavaScript plugins

UI placement and local development follow [the plugin development rules](plugin-development.md).
Plugin features and settings belong on the plugin page and its detail pages, not
as independent main-settings entries. Book and reader menus expose only registered
actions. The default-off local development session is an explicit exception to
review admission, with separate temporary packages, state and trust; ordinary
installation still requires the signed catalog.

Packages remain schema 1 / host API 1. `scriptAction` declares `id`, localized
`name`, relative `.js` `entry`, `surface` (`selection`, `library`, `dictionary`, `article` or `bookImport`) and `scope`
(`selection` or `context`). It requires `script:run`; selection actions also
require `ui:selection-action`. Existing prompt and AI toolbar formats are unchanged.
The dictionary surface additionally requires `dictionary:transform` and uses
`scope: "selection"`. Dictionary transforms and article capture require Modu
1.3.10 or later; packages declare that minimum and their capabilities in both
the manifest and signed review record. Host API remains 1.

An entry is an async function body. It receives `input.selection`, optional
`input.context`, declared non-secret `input.settings`, fixed `input.actionId`,
and optional book id/title/author/format. Return `{title, text}`. Results are plain
text, never HTML. Files and application preferences are not exposed.

Host API methods:

| Method | Permission | Behavior |
| --- | --- | --- |
| `modu.http.get({url})` | `net:http` | One HTTPS GET per invocation, exact declared domains, pinned public DNS address, no redirects, headers or cookies |
| `modu.library.list({offset,limit})` | `library:read` | At most 50 readable book summaries; no file paths or locked private books |
| `modu.notes.save({text})` | `note:write` | Native confirmation; app binds the note to the actual selected book/CFI and uses the existing DAO |
| `modu.privateLibrary.open()` | `library:private` | Opens the native protection UI; no credentials cross the bridge |
| `modu.privateLibrary.lock()` | `library:private` | Revokes the private session |
| `modu.privateLibrary.state()` | `library:private-control` + `library:private` | Native state and local policy booleans, no credentials or book data |
| `modu.privateLibrary.updateOptions({privateOnly,autoImport,lockAfterHide})` | Same | Authenticated local options; only supplied booleans change |
| `modu.privateLibrary.selectBooks({private,multiple,limit})` | Same | Native picker, at most 100 summaries with id/title/author/private; grants belong to this invocation and authentication session |
| `modu.privateLibrary.setPrivate({bookIds,private,lockAfter})` | Same | Revalidates selected IDs against native grants and saves local marks; optional lock after commit |
| `modu.articles.capture()` | `article:capture` | Opens native URL capture, Markdown preview, export and bookshelf import; returns `{opened: true}` |

### Reading content and library

| Method | Permission | Behavior |
| --- | --- | --- |
| `modu.library.tags({bookId})` | `library:read` | Tags of one readable book, with id and colour; no tags of a locked private book |
| `modu.library.groups()` | `library:read` | At most 500 folders with id, name and parent |
| `modu.library.tag({bookIds,name,remove?})` | `library:write` | Creates the tag when missing, then attaches or detaches it; every book is re-checked as readable |
| `modu.library.move({bookIds,groupId})` | `library:write` | Moves readable books into a folder; `0` means the shelf root |
| `modu.books.content({maxCharacters?})` | `book:content` | Current chapter text of the open book, at most 12k characters |
| `modu.books.chapter({href,maxCharacters?})` | `book:content` | One chapter by href, same bound |
| `modu.notes.list({bookId?,keyword?,limit?})` | `note:read` | Highlights and notes with their chapter and text |
| `modu.reading.stats({days?})` | `reading:read` | Total and per-book reading seconds for a window |
| `modu.reading.history({bookId?,limit?})` | `reading:read` | Daily reading entries |
| `modu.search.library({query,limit?,includeNotes?})` | `search:library` | One query across books and notes |
| `modu.knowledge.search({query,limit?})` | `knowledge:query` | Local vector index of one book, five-second budget |
| `modu.dictionary.lookup({word,limit?})` | `dictionary:lookup` | Installed local dictionaries |

### Models

| Method | Permission | Behavior |
| --- | --- | --- |
| `modu.ai.complete({prompt,system?})` | `ai:invoke` | The user's configured model, capped at 32k output characters. Billed to the user |
| `modu.translate.text({text})` | `translate:invoke` | The user's configured translation engine |
| `modu.tts.speak({text})` | `tts:invoke` | The user's configured voice. The plugin never receives the audio bytes |

### System surfaces

| Method | Permission | Behavior |
| --- | --- | --- |
| `modu.clipboard.write({text})` | `clipboard:write` | Copies up to 8k characters |
| `modu.clipboard.read()` | `clipboard:read` | Returns the plain-text clipboard, at most 8k characters |
| `modu.share.text({text,subject?})` | `share:text` | Opens the system share sheet |
| `modu.ui.confirm({title,message})` | `ui:dialog` | Yes/no dialog, returns `{confirmed}` |
| `modu.ui.prompt({title,message,initial?})` | `ui:dialog` | Text dialog, returns `{text}` |
| `modu.ui.select({title,options})` | `ui:dialog` | At most 30 options, returns `{selected}` |
| `modu.ui.progress({label,fraction})` | `ui:progress` | Transient progress bar, grows with a long task |
| `modu.open.url({url})` | `url:open` | http(s) only; `file:`, `javascript:` and `intent:` are refused |
| `modu.storage.list()` | `storage:plugin` | Files the plugin owns, with sizes |
| `modu.storage.read({name})` | `storage:plugin` | Returns `{text}`, or `{text: null}` when absent |
| `modu.storage.write({name,text})` | `storage:plugin` | Replaces one file |
| `modu.storage.remove({name})` | `storage:plugin` | Deletes one file; `{removed}` |

`storage.*` writes under `<plugins>/.data/<pluginId>`, a sibling of the verified
package rather than a child, so a plugin cannot overwrite the files the reviewed
inventory hashes. Names must be flat `*.json` of at most 64 characters, checked by
pattern and again after normalisation. Limits are 256 KiB per file, 200 files and
4 MiB total per plugin. Uninstalling deletes the directory with the package.

Every argument is validated against a named-argument allowlist, so an unknown
key fails the call instead of being ignored, and every list and string has a
hard bound. A call whose capability the user has not granted fails with
`denied`, which the UI explains as a missing permission rather than a broken
package.

Methods that wait on the network or on native UI (`privateLibrary.update*/`
`selectBooks`/`setPrivate`, `ui.*`, `share.text`, `clipboard.read`,
`ai.complete`, `translate.text`, `tts.speak`) pause the execution clock while one
is pending and charge it to a separate two-minute interaction budget. A slow model
server therefore does not turn a correct plugin into a `timeout`; total wall time
is still bounded, so a hung plugin cannot run forever.

Worked examples of this surface live in
[`docs/examples/plugins`](../examples/plugins/README.md): reading reports,
annotation digests, model-assisted explanation, an owned vocabulary notebook and
chapter digests.

## Permissions

Capabilities split in two tiers:

- **Install tier** — materialised by installing the package (`ai:prompt-pack`,
  `ui:selection-action`, `ui:book-action`, `script:run`, the private-library
  trio, `settings:device`, `dictionary:transform`, `article:capture`,
  `article:extract`). Refusing them means not installing, so the details page
  lists them as information.
- **Runtime tier** — off by default and switched on per plugin in
  **插件 → 详情 → 权限**. This covers `net:http`, book and note reads and writes,
  the library, reading statistics, search, the local vector index, `ai:invoke`,
  `translate:invoke`, `tts:invoke`, `dictionary:lookup`, the clipboard, the
  share sheet, `ui:dialog`, `ui:progress` and `url:open`.

Grants are device-local consent, exactly like the experimental switch: they are
never exported, never travel in a settings backup and never sync. Restoring a
backup on another device therefore cannot hand a plugin new powers. Revoking a
capability cancels the plugin's running task, so work already in flight cannot
finish with a permission that was just withdrawn. Uninstalling removes every
grant.

Packages that shipped before manual grants existed keep the capabilities they
already implied (network, library read, notes, the private-library trio and
article capture) so an app upgrade does not break a working plugin. Every
capability added later starts denied.

## Plugin-owned private policies and settings

Private plugin rules, visibility choices, import decisions and book-menu behavior
are declared or executed by the package. Native code retains authentication,
selection grants, access checks and synchronization/backup exclusions. A package
with `library:private-control` opens only the native protection controls; its
business settings are rendered from its manifest in plugin details. Legacy
packages retain their original native page and `privateLibrary.hide` action.

Settings default to synced plugin storage. `storage: "device"` requires
`settings:device` and excludes that value from sync, settings export and backup.
Device toggles may bind to `privateLibrary.privateOnly`,
`privateLibrary.autoImport` or `privateLibrary.lockAfterHide` with private-control
permission. These bindings preserve existing native values and require native
authentication to edit. Development sessions use temporary overrides. Template
placeholders `{setting.<key>}` and script `input.settings` receive effective,
declared non-secret settings from the same host configuration.

A `bookImport` action requires `library:private-policy`, `library:private` and
`script:run`, uses `scope: "selection"` and optionally declares `enabledSetting`
referencing a package toggle. A false gate skips the Worker. Input contains only
`book: {id,title,author,format}`, settings and actionId; return exactly
`{private: boolean}`. All host calls are denied and the deadline is two seconds.
Enabled policies run before the database insert. Any true decision marks the
book private; errors, changed settings or replaced owners abort the import.
Without this surface, older plugins retain the existing local auto-import
option. New capabilities reject unsupported hosts before installation; the
first host upgrade is required even where older Beta builds share version 1.3.10.

## Dictionary preprocessing

A `dictionary` action runs after an exact lookup misses. It receives only the
lookup word in `input.selection`, its declared non-secret settings and action ID.
Return `{candidates: [...]}` with at most 12 non-empty strings, each at most 256
characters. The host tries candidates in order for dictionaries that missed the
original word. The worker deadline is two seconds, and all host bridge calls are
denied on this surface. Cancelling or changing the query invalidates late results.

The reviewed preprocessing plugin provides English inflection candidates, French
elision-prefix removal and JSON regex rules. Each rule has `pattern`,
`replacement` and optional `flags` (`gimsu`); `$1` references a capture group.
Rules independently process the original word, preserving candidate order.

## Web read later

The plugin's library action calls `modu.articles.capture()`. The native page owns
the URL, acquisition and save actions. Acquisition fetches public HTTPS content
with bounded redirects, revalidates DNS and pins the connection to the checked
address. It does not execute website scripts, send login credentials or fetch
images. Downloads are limited to 2 MiB.

The plugin declares one `scriptAction` with `surface: "article"`,
`scope: "selection"` and the `article:extract` capability in addition to
`script:run`. This action is a pure offline conversion. Its input contains only
`html`, the validated final `url`, a `plainText` flag, declared non-secret
`settings` and `actionId`. It receives no book, selection or application secrets;
all host calls are denied, including HTTP calls declared elsewhere in the package.
Return exactly `{title, markdown}`. The host retains the verified source URL
rather than accepting one from the result.

Content recognition, advertisement removal, metadata, image handling and Markdown
conversion belong in the plugin package. Bundle offline parsers and dependencies
with pinned versions and their licenses. Future extraction rules, website fixes
and conversion features update through the plugin catalog without an app update.
The host has no article extraction fallback. Older packages without an article
entry prompt for a plugin update; apps without `article:extract` reject a package
requiring it before installation.

The article execution profile permits a 512 KiB bundled script, 2 MiB of decoded
HTML, a 200-character title and 512 KiB of Markdown. Separate bounded JSON wire
budgets allow escaping overhead: 16 MiB for startup and 4 MiB for result messages.
These limits apply only to the article action, not every action in the same
package. Acquisition and conversion share a cancellable 15-second deadline.
The host preview suppresses automatic image requests; the reviewed plugin emits
ordinary image links, so capturing and previewing do not fetch subresources.

The user previews the result before exporting Markdown or adding it through the
existing book-import path. Once the user submits a native save or import, that
operation belongs to the file saver or book importer and may finish after the
plugin is disabled; it does not run more plugin code or receive new plugin data.
Disabling still cancels acquisition, conversion and pending plugin callbacks.
Imported articles follow normal private-import rules,
sync and local backup. Plugin settings can be backed up; plugin packages and
signed proof files are obtained separately after restoring to another device.

## Runtime and catalog transport

GitHub and Gitee are fixed catalog sources with one canonical GitHub identity.
Both require the same signed envelope and artifact hashes. Gitee permits one
same-path HTTPS redirect to its official raw CDN. A network failure may fall back
to the fixed repository contents API; its path, base64 encoding, decoded size and
final signature or package hash are verified. No API-provided download URL or
account token is used. Switching sources cancels pending requests and drops their
catalog selections; installed packages retain their offline review proofs.

The runtime creates a fresh dedicated WebView and Blob Worker for each action.
Only the fixed bootstrap is HTML. Package source crosses as a JSON value and
never executes in the parent document or reading view. CSP blocks direct network,
frames and forms; platform callbacks additionally deny navigation, resources,
windows and permissions. No global cookie clearing or incognito-profile mutation
is used. OHOS uses the separate overlay adapter; Windows reuses the initialized
WebView2 environment. Missing Worker support fails closed, without parent eval.

Ordinary-action limits: 128 KiB source, 64 KiB input/result/bridge messages, 16 host calls,
one call in flight, one execution per plugin, two per runtime, and a ten-second
execution deadline. Native private-option editing, selection and marking pause
that execution clock while their host call is pending, with a shared two-minute
interaction budget per invocation. This is a wall-clock budget, not a CPU quota;
reviewed scripts must await the native reply. State reads and other calls retain
the ordinary deadline. HTTP additionally uses the shared burst/daily budget. Disabling,
upgrading, removing or globally disabling plugins cancels tasks before changing
their files or contributions. Backgrounding also cancels tasks. Late DNS and
bridge replies must pass the same live-job check before doing work.

These are execution/transport limits, not a hard renderer memory quota. Signed, reviewed
catalog admission remains mandatory. Compatible new releases can be installed independently
of the app version; only new host APIs/capabilities require an app update. Worker termination and renderer-loss cleanup
contain failures; no claim of arbitrary third-party code safety is made.

Private books is not bundled. Its package registers actions; protection UI is
mounted only while that reviewed plugin is active. Native enforcement is needed
at the reading route and data exits so script removal cannot bypass protection.
Explicit deactivation requires native verification before clearing protection;
passive package loss locks remaining private marks until the plugin is restored.
The local credential record is excluded from settings export/import and backup.
Private books and their associated notes, positions and assets are excluded from
synchronization and outgoing backups even while unlocked. Complete device-local
recovery snapshots remain intact. Existing cloud copies are not automatically
deleted. No book-file encryption or new synchronization format is introduced.

Implementation reference: HapeLee/legado-with-MD3 at
`4efe24965915a326f5e910197cb73966892f2eb0`, especially PrivateAccessGateway,
PrivateReadGateViewModel and PrivateListMasking. The Flutter implementation is
independent; it does not inherit the reference's legacy plaintext password.

Validation covers real Worker execution/termination in Node, native adapter
callbacks, runtime permission/timeout/cancellation, malicious manifests, exact
package inventory, SQLite visibility and native protection UI. A real Chromium smoke check also verified text execution, controlled private-library
calls, Blob-worker connect-src enforcement and termination of an infinite loop.
Physical-device WebView/CSP and platform-specific performance remain acceptance checks.
