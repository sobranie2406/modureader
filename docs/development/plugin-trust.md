# Plugin trust / 插件审核与上架

Only releases listed in the project-reviewed catalog can run. The official source
is https://github.com/sobranie2406/modu-plugin. Repository commits are not admission:
`catalog.source.json` is the readable review record, and `catalog.json` is its
Ed25519-signed envelope. Modu embeds the verification public key, never the signing
key. Unsigned catalogs, altered payloads and unknown signing keys are rejected.

只有官方插件仓库中审核上架的版本可以启用。提交源码不等于上架；目录签名和包内每个文件都必须校验通过。

## Download sources

The plugin page can select GitHub or the Gitee mirror at
https://gitee.com/sobranie2406/modu-plugin. Both serve the same signed catalog and
artifacts; the signed repository identity remains the canonical GitHub URL.
Switching sources cancels pending requests and reloads the catalog. A mirror cannot
grant approval or change package hashes.

## Independent plugin updates

A signed new plugin or version does not require a new Modu build when its host API,
capabilities and minimum app version are already supported. New native capabilities
or host APIs still require an app update. The catalog page shows that distinction
before downloading. Installation remains an explicit preview-and-confirm action;
refreshing a catalog neither installs nor executes code.

兼容现有接口和权限的插件可独立更新；需要新增宿主能力时才更新默读。插件页自动加载目录，下载安装前显示权限，确认后安装。

## Integrity and offline use

`PluginTrust` verifies the complete package inventory, including README and license,
against an app-shipped approval or a project-signed review proof. Matching id/version
alone is never sufficient. Existing versions are immutable: a later catalog cannot
silently redefine their file hashes. Scripts are checked again before execution.

Verified signed proofs are saved per release under `plugins/.catalog-proofs`, outside
package files and settings backups. Restart revalidates the proof signature. A new
catalog does not remove earlier proofs, so reviewed installed versions can still
start offline. Package fields, preferences, backups and unsigned network responses
cannot add approvals. The three initial reviewed releases also have compiled
fingerprints for offline installation.

## Review and publication

1. Review source, declared permissions, license and user-visible behavior; run package,
   runtime, removal and compatibility tests.
2. Add the explicit reviewed entry to `catalog.source.json`, with exact source-file
   and artifact SHA-256 values, host API, capabilities and minimum app version.
3. Run `python3 scripts/pack.py` and the repository tests. Packing checks the review
   record; it never promotes submitted source or rewrites approval hashes.
4. Sign with `python3 scripts/sign_catalog.py --private-key /protected/path/key.pem`.
   The signing key must remain outside the repository with owner-only permissions.
5. Publish source, packages, review record and signed catalog together. The signature
   verifier and signing-script tests include OpenSSL interoperability fixtures.

The initial records identify agent technical review as such; they do not claim a
human review that did not occur. Catalog signatures establish project admission,
not a guarantee that plugin output is correct. JavaScript remains constrained by
[the runtime contract](plugin-script-runtime.md), including timeout, concurrency,
transport limits and host-owned permissions. No native plugin modules or silent
package execution are supported.
