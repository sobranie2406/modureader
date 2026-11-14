# Reviewed JavaScript plugins

Packages remain schema 1 / host API 1. `scriptAction` declares `id`, localized
`name`, relative `.js` `entry`, `surface` (`selection`, `library` or `dictionary`) and `scope`
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
| `modu.articles.capture()` | `article:capture` | Opens native URL capture, Markdown preview, export and bookshelf import; returns `{opened: true}` |

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
the URL, acquisition and save actions; page content does not return through the
script bridge. It fetches a public HTTPS page with bounded redirects, revalidates
DNS and pins the connection to the checked address. HTML is parsed offline in an
isolate. Markdown retains headings, paragraphs, lists, quotes, code, tables and
links; images become ordinary links without subresource downloads.
Native acquisition has a 15-second deadline and a 2 MiB response limit; generated
Markdown is capped at 512 KiB and stays in the native preview/save workflow.

The user previews the result before exporting Markdown or adding it through the
existing book-import path. Imported articles follow normal private-import rules,
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

Limits: 128 KiB source, 64 KiB input/result/bridge messages, 16 host calls,
one call in flight, one execution per plugin, two globally, and a ten-second
total deadline. HTTP additionally uses the shared burst/daily budget. Disabling,
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
No book-file encryption or new synchronization format is introduced.

Implementation reference: HapeLee/legado-with-MD3 at
`4efe24965915a326f5e910197cb73966892f2eb0`, especially PrivateAccessGateway,
PrivateReadGateViewModel and PrivateListMasking. The Flutter implementation is
independent; it does not inherit the reference's legacy plaintext password.

Validation covers real Worker execution/termination in Node, native adapter
callbacks, runtime permission/timeout/cancellation, malicious manifests, exact
package inventory, SQLite visibility and native protection UI. A real Chromium smoke check also verified text execution, controlled private-library
calls, Blob-worker connect-src enforcement and termination of an infinite loop.
Physical-device WebView/CSP and platform-specific performance remain acceptance checks.
