# Application update mirror

## Current: Modu 1.2.5+10102

This guide describes the Modu publishing repository's `v1.2.5` release procedure and client behavior. A mirror is current only after all nine packages and their checksums have been verified and its manifest updated.

A single Update Source option controls both checking and downloading. Each fresh app launch starts with GitHub preferred. A GitHub check that fails because of connection, timeout, TLS/certificate or HTTP request errors falls back to the fixed HTTPS Gitee manifest and switches the source for the whole workflow:

```text
https://gitee.com/sobranie2406/modureader/raw/master/updates/latest.json
```

Successful GitHub checks use GitHub metadata and downloads. A check resolved through Gitee uses Gitee downloads. Changing the source clears pending release/download information and requires a fresh check; downloads never silently switch sources or combine responses from two sources.

### Nine-package release matrix

| Platform | Architectures | Package |
| --- | --- | --- |
| Android | ARM64 only | APK |
| iOS | ARM64 | IPA (unsigned; user signing required) |
| macOS | ARM64, x64 | DMG |
| Windows | ARM64, x64 | setup EXE |
| Linux | ARM64, x64 | DEB |
| HarmonyOS | ARM64 | Unsigned HAP; manual signing/installation, not device-validated |

There are nine packages in total. Android x64 is excluded from the release matrix and update manifest. The existing update manifest still contains the eight supported installer targets; HarmonyOS HAP is distributed as a manual download with a checksum, not through an unimplemented automatic HAP installer.

### macOS browser downloads

On macOS, the app opens the checked source's DMG download link in the default browser. It does not download the DMG in-app, monitor browser completion, verify the browser-downloaded file's SHA-256 or confirm installation. A successful browser handoff means only that the link opened. Do not reuse an old in-app DMG cache. Open the downloaded DMG, quit Modu and replace the app in Applications; the library is preserved. These packages are not Apple-notarized.

If a GitHub browser download fails, select Gitee, check again and download from that source. The app does not switch the browser download automatically. Manual checksum verification can use the release's checksum file; this is separate from the in-app integrity checks on platforms that download internally.

## Publishing order

The mirror repository contains explanations, update manifests and release assets, not imported application source. The existing release policy allows cleanup of old Gitee application releases within the previously agreed scope; it still requires target checks, backups and integrity verification. Any tool-enforced approval or expansion of scope is handled separately. This guide does not itself perform those actions.

1. Finish the stable GitHub release with all nine packages, SHA-256 files and corresponding source.
2. Delete the old Gitee application releases and assets before creating/uploading the new one. First confirm the nine new GitHub packages are complete, the old version remains downloadable from GitHub, and local originals for uploading are retained. Check each old release's repository, tag and assets, then confirm the release list is empty. Preserve Git tags, source, branches and the separate `modu-models` repository.
3. Upload the same-version, same-name, byte-identical installers and checksum files to Gitee. Do not replace model assets, recompress installers or reuse another version's files.
4. Verify every public, anonymous Gitee download, redirect, byte length and SHA-256 against GitHub's asset `digest`. Mirror installer URLs follow `https://gitee.com/sobranie2406/modureader/releases/download/v<version>/<installer-name>`.
5. Generate the manifest from the GitHub Release API JSON: `python3 scripts/release/update_manifest.py github-release.json`. The script prints JSON; it neither uploads nor modifies the repository.
6. Only after verification, publish the result to `updates/latest.json` on the mirror repository's `master` branch. Clients require `modu_update_schema: 1`, a stable version and valid sizes/SHA-256 for their OS/architecture. The mirror can be unavailable between cleanup and upload; do not point the manifest at unverified assets to avoid that gap. Retry interrupted uploads from the local originals and confirm that only the new Gitee application release remains.

The historical GitHub cleanup scope covers releases/assets through 1.0.9, preserving tags and source. Releases from 1.1.0 onward remain. This does not mean GitHub retains only the newest release.

The manifest retains GitHub's `tag_name`, `draft`, `prerelease`, `body`, `assets` and original GitHub download URLs. The client derives the Gitee URLs itself; the manifest cannot choose arbitrary download hosts. The generator accepts only the eight expected installers and excludes tokens, upload URLs and other API fields.

## Fallback and integrity

- GitHub checking has a 12-second overall limit. Success avoids requesting the mirror. DNS errors, resets, timeouts, TLS/certificate failures and HTTP request errors, including 401, 403, 404, 407, 429 and 5xx, trigger an eight-second Gitee check. HTTPS certificate verification remains enabled. If both checks fail, the app reports failure rather than claiming to be current.
- When GitHub is available, its version/checksum information is authoritative; differing mirror versions or digests do not override it. The app does not downgrade the installed version.
- Internal downloads use the source resolved by that check. The expected size and SHA-256 are the same across sources; failure stops the download. Complete cached files are reverified before reuse and again before handing an installer to the OS. These file checks do not apply to the macOS browser handoff described above.
- Invalid manifests, unsafe redirects, cancellation, checksum failure, application errors and disk-write failures do not start a fallback request.
- Only HTTPS is accepted. Allowed Gitee paths are under `gitee.com/sobranie2406/modureader/`, the verified attachment CDN `foruda.gitee.com/attach_file/`, and the exact manifest path `/sobranie2406/modureader/raw/master/updates/latest.json` on `raw.giteeusercontent.com`. Other accounts, paths, ports and lookalike domains are rejected. GitHub redirects are restricted to official resource hosts listed in the code.
- The fixed official account and HTTPS establish manifest trust. SHA-256 verifies integrity, not a digital signature. Protect both publishing accounts and do not treat untrusted mirrors as official sources.
- If Gitee file-size, total-capacity or review limits cannot accommodate complete installers, report the limitation and resolve the publishing approach. Split archives or HTML download pages do not substitute for installable assets.

The client needs no Gitee login, does not read browser sessions and does not attach library configuration or API keys to update requests. Store distribution, Android installation confirmation and iOS self-signing restrictions remain applicable.

## Historical milestones and optional verification

The nine installers for 1.0.9 and their checksums were anonymously downloaded and matched GitHub digests; nine was that historical matrix, not the current one. The stable mirror manifest was published. Starting with `1.0.9+10028`, the client accepted Gitee raw-file CDN redirects; `1.0.9+10027` could still check GitHub metadata and preferentially download Gitee assets under its earlier policy. Those results do not establish that current release assets were rechecked here.

After a release, the following opt-in check verifies public metadata redirects and simulates GitHub unavailability:

```sh
flutter test test/service/update/app_update_mirror_live_test.dart --dart-define=MODU_VERIFY_UPDATE_MIRROR=true
```

It does not download/install the app or replace independent SHA-256 verification of all eight installers. It was not run for this documentation update.
