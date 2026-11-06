# Plugin System Execution Document (P0 specification freeze + P1 declarative plugins)

> Historical PR design. The implemented source/permission policy is now governed
> by [Plugin trust](plugin-trust.md): default-off experimental opt-in, project-reviewed
> built-in catalog only, no arbitrary third-party packages or executable plugins.

Status: P1a/P1b/P1c implemented, pending review · 2026-10-24 · baseline `main` @ `0feceeb9` (Modu 1.3.1+10152) · scope of this round: **P1b + P1c**

This document covers **P0 (design freeze)** and **P1 (declarative plugins)**. P1 is split into P1a (install + AI prompt registration + sample plugin), P1b (selection actions + plugin settings) and P1c (settings export). P2–P5 (registries, declarative network plugins, WebView JS script host, ecosystem hardening) are described in the §0 roadmap and the §14 handover section and are out of scope for this round.

---

## 0. Handover summary (read this first)

### 0.1 Target form and delivery route

The product target is **C: plugins can execute scripts inside a sandbox**. Dependency order, however, rules out starting with the runtime:

| Phase | Content | Deliverables | Estimate | Gate |
|---|---|---|---|---|
| **P0** | Specification freeze: package format, capability model, Host API, `ScriptRuntime` interface, threat model, store compliance | §2–§4 of this document (the spec *is* the document; no separate `PLUGIN_SPEC.md`) | 2–3 person-days | Spec review passes; the manifest can express script contributions without a schema change |
| **P1** | Minimal declarative loop: install/enable/disable/uninstall/upgrade + **AI prompt registration (`aiSkill`)** + **selection actions (`selectionAction`)** + settings migration | §5–§13 of this document | 11–14 person-days (P1a/b/c) | Install/uninstall/disable on 6 platforms; sample plugin works; malicious packages all rejected |
| **P2** | Registries: TTS, translation, dictionary, AI tools/skills and toolbar dispatch by ID registry | Registry API + migration shims | 8–12 person-days | Zero loss of existing configuration; full regression |
| **P3** | Declarative network plugins: dictionary HTTP sources, endpoint templates, domain allowlists and quotas | Security review + quota tests | 8–10 person-days | Unauthorised requests rejected; backup round-trip consistent |
| **P4** | Script runtime v1: `ScriptRuntime` + WebView implementation, Host API bridge, watchdog | 2–3 script samples | 10–15 person-days | Sandbox-escape review; real iOS/Android devices; explicit OHOS degradation |
| **P5** | Ecosystem and hardening: signing/revocation, packaging CLI, developer panel, template repository | Developer docs + CLI | 8–10 person-days | An external developer completes the sample in 1 hour |

Total about 47–64 person-days (9–13 weeks for one person); the critical path is P0 → P1 → P2 → P4.

**P1 is further split into three PRs** (no JS in this phase):

| PR | Content |
|---|---|
| **P1a (implemented)** | Package install/enable/disable/uninstall/upgrade + `aiSkill` prompt registration + sample plugin + settings pages + unit tests |
| **P1b** | `selectionAction` selection actions (reusing the prompt mechanism, including toolbar slots and the hash guard) + plugin settings form and `pluginConfig_` |
| **P1c** | Plugin state/configuration in settings export and validation (`settings_modules`, `_types`, `value_validation`) |

This makes the first PR demonstrable end to end while avoiding the two high-risk paths: the selection toolbar and configuration export.

**Why not build C first**: landing the script host first would force rework of the manifest, capability model and configuration migration; moreover, iOS only exempts code "interpreted by WebKit/WKWebView", while embedded QuickJS or dynamic libraries carry policy or toolchain risk on iOS/Android/HarmonyOS. The script route is therefore locked to **WebView JS**, added as a fifth contribution type on top of the already-stable registries.

### 0.2 Current repository state (2026-10-23)

- Baseline: `main` = `origin/main` = `upstream/main` = `0feceeb9` (Modu 1.3.1+10152); the working tree was clean before this round. This round fast-forwarded 19 upstream commits and pushed.
- This round: added `docs/development/plugin-system-p0-p1.md` and an index entry in `docs/README.md`.
- 2026-10-23 follow-up: P1a implemented (see §16.6 v0.3): added `lib/models/plugin_manifest.dart`, `plugin_state.dart`, `lib/service/plugins/`, `lib/page/settings_page/plugins/`, `scripts/dev/pack_plugin.dart`, `docs/examples/plugins/prompt-pack/` and matching tests; changed `main.dart`, `Prefs`, `get_base_path.dart`, the settings entry point and `pubspec.yaml` (explicit `pub_semver`). Did not touch the database, sync, TTS/translation/dictionary, the selection toolbar or settings export.
- 2026-10-23 P1b/P1c (see §16.6 v0.4): opened `ui:selection-action`; added `SelectionActionContribution` and `SelectionActionContributionHandler` (24 slots, name/icon validation, hash guard, user edits kept as `custom-*`); enabled `pluginConfig_<id>` and the plugin settings form on the details page; wired `pluginState`/`pluginConfig_*` into settings export, import and strict validation; updated the English and Chinese settings documentation. The database remains v11, and `SelectionToolbarConfig.validate()` is unchanged.
- 2026-10-24 the sample plugin was upgraded to 1.1.0 (see §16.6 v0.5): added one `selectionAction` and four `settings`, and updated the README and sample test; this supports manual acceptance of P1b install, disable, uninstall and settings backup.

### 0.3 Decision status

Confirmed:

- Target form C, delivered in phases; this round only writes and implements P0–P1.
- **First PR scope**: plugin installation + `aiSkill` (AI prompt) registration + sample plugin; no JS, selection actions or configuration export.
- P1 is split by capability: P1a install + AI prompt registration + sample plugin; P1b selection actions + plugin settings; P1c configuration export. Each can be reverted independently.
- Script host direction: **WebView JS is the only host** (no QuickJS/native dynamic libraries in P4).
- Platforms: all platforms, following store rules where possible, with no hard-coded per-platform capability.

Open (defaults; see §15):

1. Plugin prompts are enabled by default.
2. The "plugins" module in settings export is included by default (P1c implemented; both `all` and `plugins` scopes include it).
3. The "Plugins" entry is not gated behind developer options.
4. The sample plugin uses CC0.

### 0.4 Next steps

P1a/P1b/P1c are implemented and passed local automated tests. Next:

1. Review the P1b/P1c code and this document; run the 6-platform manual acceptance in §10.
2. Focus regression on the 24 custom toolbar slots, preservation of user-edited entries after uninstall, settings-backup round trips and the missing-plugin notice.
3. Before P2, repeat a real cross-device acceptance of a plugin package (install → disable → back up → restore on another device → reinstall).

### 0.5 Implementation guardrails (throughout P1)

- Do not modify `SelectionToolbarConfig.validate()`; plugin actions materialise under the existing `custom-` rules.
- Add no database tables and do not bump `currentDbVersion` (P1 stays at 11).
- Introduce no script runtime or new native dependencies (P1 is pure data).
- Do not log full plugin prompts, user book content or credentials.
- Do not allow a `password` plugin-setting type (plaintext credentials would enter settings export; see §5.2).
- Plugin package files must not enter settings backups; backups carry only `pluginState` and `pluginConfig_*`.

---

## 1. Goals and non-goals

### 1.1 Goals for this round

1. Freeze plugin package specification v1: package structure, `manifest.json`, capability tokens, versions and limits, rejection reasons, and **reserve the script contribution slot without a schema change**.
2. Ship a plugin host that can install, enable, disable, uninstall and upgrade packages that are **pure data** with no executable code.
3. First contribution types: `aiSkill` (AI prompt registration) and `selectionAction` (selection-toolbar actions), materialised as user prompts and custom AI commands respectively, mounted through the `ContributionHandler` registry to leave room for later types.
4. Persist plugin state and plugin settings and wire them into settings export/import; plugin package files do not enter backups.
5. Behave consistently on all 6 platforms (Android / iOS / macOS / Windows / Linux / HarmonyOS): **install, enable/disable, uninstall, plugin settings and settings migration all work**.

### 1.2 Non-goals (explicitly not done this round)

- Execute any plugin code (JS/Dart/native).
- Allow plugins to ship Flutter UI or access the library, notes, AI keys or sync credentials.
- No plugin marketplace, no remote installation and no signature verification (only SHA-256 integrity).
- Add no database tables and do not change the DB version (stays at `currentDbVersion = 11`).
- Do not include plugin packages in settings backups (backups carry state and configuration only; see §5.4).
- Do not modify `AiToolRegistry` / reading-skill policies / TTS / translation / dictionary dispatch (those belong to P2).

### 1.3 Definition of done (DoD, P1)

- `flutter analyze` reports no new warnings; `flutter test` is green; new tests cover the P1a/P1b/P1c rows in §10.
- With the sample plugin, all 6 platforms complete "install → enable → the AI prompt picker shows the templates → disable removes them → uninstall cleans up".
- On all 6 platforms, a package with `selectionAction` completes "install → the action appears in the selection toolbar → disable/uninstall removes it → user edits are preserved".
- After restoring a settings backup on another device the plugin shows `missing`, and after reinstalling the settings are still there; invalid `pluginState`/`pluginConfig_*` is rejected as a whole.
- Malicious packages (path traversal, zip bomb, duplicate ids, oversized manifest, unknown capabilities) are all rejected with readable reasons.
- Plugin state survives restarts; a missing package shows `missing` without crashing.

---

## 2. Frozen design decisions

| No. | Decision | Rationale |
|---|---|---|
| D1 | `contributes[]` uses a string `kind` + integer `schema`; unknown kinds are **ignored with a warning** | Forward compatibility: P4's `script` contribution needs no schema change in older clients |
| D2 | Unknown **capabilities** reject the install; unknown **contribution kinds** are ignored | Secure by default on rejection; presentation is lenient by default |
| D3 | Capability tokens instead of boolean switches; each is shown and authorised during install | Reserves the same model for P3/P4 networking, scripts and library reads |
| D4 | The script runtime is abstracted as `ScriptRuntime` (`none` / `webview` / future adapters), chosen by "capability + runtime availability" | No hard-coded platform branches this round; OHOS can plug in an overlay host later |
| D5 | Plugin state lives in the single SharedPreferences key `pluginState`; plugin configuration in `pluginConfig_<id>` | Reuses the existing export/migration pipeline; P1 avoids DB migration risk |
| D6 | `minAppVersion` is compared with `pub_semver`, comparing `x.y.z` only (ignoring `+build`) | Compatible with the existing `getAppVersion()` output |
| D7 | Contribution materialisation uses **snapshot + hash guard**, not live references | Uninstall/upgrade never deletes user edits; instantiation is cheap |
| D8 | Host initialisation is idempotent, allowing Android's delayed start and macOS's post-migration second init | See the two startup paths in `lib/main.dart` |
| D9 | Contribution types are dispatched by a `ContributionHandler` registry keyed by `kind`; the host has no `switch` | The first PR registers only `aiSkill`; P1b and later engines add to the same interface |

### 2.1 About architecture decision records (ADR)

P0 does not produce separate ADR files: the "Decision / Rationale" columns above are the ADR Decision/Context summary, and this table prevails on conflict. If formal ADRs are needed later, they can be extracted into `docs/development/adr/` from this table without changing the document's authority.

---

## 3. Plugin package specification v1

### 3.1 Package structure

```
my-pack-1.0.0.moduplugin        # actually a zip; the extension only distinguishes it
├── manifest.json               # required, UTF-8, ≤ 64 KB
├── LICENSE                     # optional; the license field is an SPDX id
├── README.md                   # optional; the details page shows only the first 8 KB as plain text
└── assets/…                    # optional; not loaded this round, reserved for P3/P4
```

- Accept both `.moduplugin` and `.zip` extensions; the file picker filters on both.
- Paths inside the package must be relative; `..`, absolute paths, drive letters and symlinks are forbidden. Backslashes are normalised to `/` while `archive` decodes, and the installer handles the normalised path and then performs an additional containment check (see §9.1); do not rely on backslashes for directory structure.
- Package limits: 5 MB compressed, 20 MB total extracted, ≤ 200 entries, ≤ 1 MB per file; reject compression ratios above 200:1 (zip-bomb protection).
### 3.2 `manifest.json`

```json
{
  "schemaVersion": 1,
  "id": "com.example.prompt-pack",
  "version": "1.1.0",
  "name": { "zh-CN": "示例提示词包", "en": "Example prompt pack" },
  "description": { "zh-CN": "两个 AI 提示词模板、一个划词动作和一组插件设置。", "en": "Two AI prompts, one selection action and plugin settings." },
  "author": { "name": "Example", "url": "https://example.com" },
  "license": "CC0-1.0",
  "minAppVersion": "1.3.1",
  "capabilities": ["ai:prompt-pack", "ui:selection-action"],
  "contributes": [
    {
      "kind": "aiSkill",
      "schema": 1,
      "id": "deep-summary",
      "name": { "zh-CN": "深度摘要", "en": "Deep summary" },
      "description": { "zh-CN": "按论点—证据—结论归纳。", "en": "Claim–evidence–conclusion." },
      "prompt": "阅读当前内容，按“核心结论 / 论证链 / 证据 / 隐含假设”输出。",
      "enabled": true
    },
    {
      "kind": "aiSkill",
      "schema": 1,
      "id": "socratic-questions",
      "name": { "zh-CN": "苏格拉底提问", "en": "Socratic questions" },
      "description": { "zh-CN": "针对当前内容提出 3 个追问。", "en": "Three follow-up questions." },
      "prompt": "针对当前内容提出 3 个由浅入深的追问，并说明每个问题想检验什么。",
      "enabled": true
    },
    {
      "kind": "selectionAction",
      "schema": 1,
      "id": "explain-selection",
      "name": { "zh-CN": "简明解释", "en": "Explain simply" },
      "icon": "lightbulb",
      "prompt": "解释 {selection} 的含义与关键概念，简明直接，不编造。",
      "scope": "context",
      "enabled": true
    }
  ],
  "settings": [
    {
      "key": "tone",
      "type": "select",
      "label": { "zh-CN": "回答语气", "en": "Answer tone" },
      "options": ["concise", "detailed"],
      "defaultValue": "concise"
    },
    {
      "key": "quote_original",
      "type": "toggle",
      "label": { "zh-CN": "引用原文", "en": "Quote the original" },
      "defaultValue": false
    },
    {
      "key": "max_words",
      "type": "number",
      "label": { "zh-CN": "最大字数", "en": "Maximum words" },
      "defaultValue": 300
    },
    {
      "key": "hint",
      "type": "tip",
      "description": { "zh-CN": "设置会被保存和导出；当前版本不执行插件代码。", "en": "Settings are stored and exported; this version runs no plugin code." }
    }
  ],
  "hostApi": 1
}
```

Field rules:

| Field | Rule |
|---|---|
| `schemaVersion` | must be `1`; newer versions are rejected (with a prompt to update the app) |
| `id` | `^[a-z0-9]([a-z0-9._-]{1,62}[a-z0-9])?$`, globally unique, also the install directory name |
| `version` | strict semver `x.y.z`; upgrades must be greater than the installed version, downgrades require uninstalling first |
| `name`/`description`/`label` | string or `{locale: string}`; locale keys accept `zh-CN`/`en` etc.; fallback chain: exact → language prefix → `en` → first value |
| `license` | SPDX id, required; the UI shows it and asks the user to confirm |
| `minAppVersion` | optional; parsed with `pub_semver`; rejected when higher than the current version |
| `capabilities` | see §3.4; P1 opens `ai:prompt-pack` and `ui:selection-action` |
| `contributes` | ≤ 40 items; `kind` values in §3.3 |
| `settings` | optional; rendered on the details page from P1b, types limited to `text`/`number`/`toggle`/`select`/`tip`; `password` is unsupported (plaintext credential risk, see §5.2). Since P1.5, prompts and selection actions may reference `{setting.<key>}`; the placeholder is resolved when the contribution runs, not when it is installed, so stored content keeps the template and the uninstall hash guard stays meaningful |
| `hostApi` | optional, default 1; this round accepts only 1 |

### 3.3 Contribution types (opened by phase)

| `kind` | Phase | Semantics | Key fields |
|---|---|---|---|
| `aiSkill` | **implemented in P1a** | User prompt template shown in the AI prompt picker | `id` `name` `description` `prompt` `enabled` |
| `selectionAction` | **implemented in P1b** | Selection-toolbar action that sends a prompt to the AI panel when run | `id` `name` `icon` `prompt` `scope` `enabled` |
| `translatorProvider` | P2 | Translation engine declaration | — |
| `ttsProvider` | P2 | TTS engine declaration | — |
| `dictionarySource` | P3 | Dictionary HTTP source mapping | — |
| `script` | P4 | `{entry, runtime:"webview", api:1}`; parsed but not executed this round | `entry` |

Unrecognised `kind`: log one warning, skip the item and continue the install. This is D1's forward-compatibility guarantee; therefore a P1a client installing a package with `selectionAction` does not fail, the action simply has no effect (the user sees a "skipped N items" notice).

### 3.4 Capability tokens

| Token | Meaning | P1 |
|---|---|---|
| `ai:prompt-pack` | Add prompt templates | allowed |
| `ui:selection-action` | Add selection-toolbar actions | allowed (from P1b) |
| `net:http` | Issue HTTP through a host proxy (domain allowlist) | reject install |
| `script:run` | Execute JS from the package | reject install |
| `library:read` | Read the library/notes | reject install |
| `storage:plugin` | Read/write the plugin's private directory (always allowed, no declaration needed) | implicit |

Rejection messages must list the **missing capabilities** so users can tell whether their app is too old. Note the difference from contribution kinds: **unknown kinds are ignored, known-but-unopened capabilities reject the install**; this is the D2 boundary.

### 3.5 Validation order and rejection reasons

1. The file exists, is ≤ 5 MB and can be extracted.
2. Entry count, total extracted size and path-safety checks.
3. `manifest.json` exists, is ≤ 64 KB and is valid JSON.
4. `schemaVersion` → `id` → `version` → `license` → `hostApi` → `minAppVersion`.
5. The capability set is a subset of the **currently open set** (P1: `ai:prompt-pack`, `ui:selection-action`). Known-but-unopened capabilities report "requires a newer version"; unknown capabilities report "unknown capability"; both reject the install.
6. Each contribution is validated (count, unique ids, field types, prompt ≤ 8000 chars, display name ≤ 40 chars; `selectionAction.name` ≤ 30 chars, `icon` ∈ existing `iconIds`, total custom actions ≤ 24).
7. Settings are validated (unique keys, supported types, `select` has options, `defaultValue` type matches) — written to `pluginConfig_<id>` from P1b.
8. Conflict checks against installed plugins (version relationship for the same id).

Every failure branch returns a structured `PluginInstallError { code, message, offendingEntry? }`; the UI shows the message directly, while logs record only the code and entry, never the full prompt.

### 3.6 Sample plugin (updated after P1b)

Location: `docs/examples/plugins/prompt-pack/`

```
prompt-pack/
├── manifest.json          # the §3.2 example: two aiSkills, one selectionAction, four settings
├── LICENSE                # CC0-1.0
└── README.md              # install steps, contribution notes, how to edit prompts
```

Packaging: `dart run scripts/dev/pack_plugin.dart docs/examples/plugins/prompt-pack` produces `prompt-pack-1.1.0.moduplugin`, which you then select under Settings → Plugins → Install. Automated tests must be able to build the sample directly (without a manual zip), so `PluginPackageReader` tests pack the same directory into an in-memory zip. `sample_plugin_test.dart` installs the checked-in sample and asserts the two prompts, one selection action and the settings declarations.

---

## 4. Runtime architecture (P1)

### 4.1 Components

| Component | Location | Responsibility |
|---|---|---|
| `PluginManifest` / `PluginContribution` / `PluginSettingSpec` | `lib/models/plugin_manifest.dart` | Pure data + strict `fromJson`, hand-written parsing (no freezed, to avoid lenient unknown-field behaviour) |
| `PluginRecord` / `PluginState` | `lib/models/plugin_state.dart` | Install records: id, version, enabled, sha256, installedAt, applied contribution ids, lastError |
| `PluginPackageReader` | `lib/service/plugins/plugin_package.dart` | Extract to staging, limits and path safety, manifest parsing |
| `PluginPaths` | `lib/service/plugins/plugin_paths.dart` | Paths and creation for `plugins/`, `plugins/.staging/` and `plugins/.trash/` |
| `PluginHost` | `lib/service/plugins/plugin_host.dart` | Singleton + `ChangeNotifier`; initialize/install/enable/disable/uninstall/upgrade; state persistence; error isolation |
| `PluginContributionHandler` | `lib/service/plugins/plugin_contribution_handler.dart` | Contribution interface + registry keyed by `kind` (D9) |
| `SelectionActionHandler` | `lib/service/plugins/handlers/selection_action_handler.dart` | P1b: materialises `selectionAction` as toolbar `aiCommand` entries, with the 24-slot limit and hash guard |
| `PluginConfig` | `lib/service/plugins/plugin_config.dart` | Encode/decode, import validation and default merging for `pluginConfig_<id>` |
| `PluginContributions` | `lib/service/plugins/plugin_contributions.dart` | Orchestrates apply/remove: per-handler calls, snapshot rollback, hash guard |
| `ScriptRuntime` | `lib/service/plugins/script_runtime.dart` | Interface and `NoopScriptRuntime` only; P4 implements `WebViewScriptRuntime` |
| Settings pages | `lib/page/settings_page/plugins/` | List, details, permissions, install/uninstall interactions |

The public `PluginHost` API (shape frozen for P2–P4):

```dart
Future<void> initialize();                 // idempotent
List<PluginRecord> get plugins;
PluginRecord? byId(String id);
Future<PluginInstallResult> install(File package);
Future<void> enable(String id);
Future<void> disable(String id);
Future<void> uninstall(String id);
void dispose();                            // P1 only releases listeners
```

### 4.2 State machine

```
                 install                 enable
  (none) ───────────────▶ installed ───────────────▶ enabled
                          │  ▲                      │
              disable ◀───┘  └────── enable ◀───────┘
                          │
       missing package/broken manifest ──▶ broken / missing (cannot enable, can uninstall)
```

- The only side effect of `enabled` is "contributions are materialised"; P1 runs no plugin logic.
- `broken`: manifest parsing failed or the hash does not match; configuration is kept and the UI offers "Reinstall" and "Uninstall".
- `missing`: `pluginState` has a record but the directory does not exist (typically after restoring a settings backup only).
### 4.3 Startup sequence

```
main()
 └─ Prefs().initPrefs()                       # existing, main.dart:103
 └─ _startConfiguredApp()
     ├─ initBasePath()                        # existing, main.dart:170
     ├─ AnxLog.init(); AnxError.init()
     ├─ DBHelper().initDB()                   # existing, main.dart:173
     ├─ PluginHost.instance.initialize()      # new: try/catch; failure must not block startup
     ├─ Server().start()                      # existing
     └─ runApp(...)                           # existing
```

- `initialize()` has an internal `_initialized` guard; calling it again after the macOS migration only re-scans and re-applies contributions, without re-registering listeners (`main.dart:462-475`).
- Shutdown: `PluginHost.instance.dispose()` in `onWindowClose()`, before `DBHelper.close()` (`main.dart:291`).
- Emergency switch: with `--dart-define=MODU_PLUGINS=false`, `initialize()` returns immediately, providing a build-level rollback when a plugin breaks startup.

### 4.4 Storage layout

```
<basePath>/plugins/
├── com.example.prompt-pack/
│   ├── manifest.json
│   └── README.md
├── .staging/<uuid>/            # temporary install directory, cleared at startup
└── .trash/<uuid>/              # temporary uninstall/upgrade directory, cleared at startup
```

`initBasePath()` additionally creates `plugins/` (`lib/utils/get_path/get_base_path.dart:67-87`). Android's `prepareAndroidStorage()` only migrates old data to app-private external storage and then still goes through `_startConfiguredApp() → initBasePath()` (`lib/utils/get_path/android_storage.dart:19-32`, `lib/main.dart:155-173`), so the plugin directory needs no Android-specific branch.

### 4.5 Error isolation

- Any single plugin's exception affects only that plugin: catch → `lastError` (≤ 500 chars, redacted) → status `broken` or remains `disabled`.
- Overall `initialize()` failure: log `AnxLog.severe`, empty the registry and let the app continue starting.
- Contribution materialisation failure: roll back to the `userPrompts` and `selectionToolbar` snapshots taken before install, fail the install and clean staging.

### 4.6 Contribution type registry (D9)

The host writes no `switch (kind)`; it maintains `Map<String, PluginContributionHandler>`:

```dart
abstract class PluginContributionHandler {
  String get kind;                       // 'aiSkill'
  Set<String> get requiredCapabilities;  // {'ai:prompt-pack'}
  void validate(PluginContribution c, PluginManifest m);   // throws PluginInstallError
  Future<AppliedContribution> apply(PluginManifest m);      // writes host data structures
  Future<void> remove(AppliedContribution applied);         // cleans up after the hash guard
}
```

P1 registers `AiPromptContributionHandler` and `SelectionActionContributionHandler`; P2/P4 engines and scripts reuse the same interface. A new type = a new handler file + one registration line; `plugin_host.dart` does not change.

---

## 5. Configuration, export and migration

### 5.1 New Prefs keys

| Key | Phase | Content |
|---|---|---|
| `pluginState` | **P1a** | `{"schemaVersion":1,"plugins":[PluginRecord…]}` |
| `pluginConfig_<id>` | **P1b** | Plugin settings object, storing only keys the user changed; missing keys use the manifest `settings[].defaultValue` |

`Prefs` implements:

```dart
PluginState get pluginState;
Future<void> savePluginState(PluginState state);   // calls notifyListeners() after writing
Future<void> removePluginData(String id);          // uninstall: deletes the state record and pluginConfig_<id>

Map<String, dynamic> pluginConfig(String id);
Future<void> savePluginConfig(String id, Map<String, dynamic> values);
```

### 5.2 Settings export/import wiring (P1c, implemented)

Three places change together:

1. `lib/service/config_transfer/settings_modules.dart`
   - `settingsModuleKeys['plugins'] = 'pluginState'`
   - `settingsModuleForKey()` adds `if (key.startsWith('pluginConfig_')) return 'plugins';`
2. `lib/service/config_transfer/global_settings_transfer.dart`
   - `_types` adds `'pluginState': 'string'`
   - the `_type()` prefix allowlist adds `'pluginConfig_'`
3. `lib/service/config_transfer/settings_value_validation.dart`
   - `pluginState`: `PluginState.parseStrict()` validates `schemaVersion`, id format and uniqueness, field types and the record limit (100).
   - `pluginConfig_*`: must be a JSON object; when the plugin is installed, each manifest `settings` entry is type-checked along with `select` options; when missing, only the object shape is checked; unknown keys are preserved for forward compatibility with newer settings.

After export, plugin packages **do not travel with settings**: the importing device shows `missing` and the UI explains that "plugin files must be reinstalled; configuration has been kept".

Credential boundary: plugin settings do not support the `password` type, so `pluginConfig_*` contains no secrets; when P3 introduces plugins that need keys (dictionary/TTS), `isCredentialPreference()` (`lib/service/local_data/backup_safety.dart`) must be extended to treat `pluginConfig_*` as sensitive and to redact manifest-declared secret fields, otherwise an `includeSecrets=false` export would leak plugin keys.

### 5.3 Database backup

`Prefs.buildPrefsBackupMap()` packs SharedPreferences, so plugin state travels with database backups without changes; `test/service/config_transfer/plugin_settings_transfer_test.dart` verifies that the restored `pluginState` parses and that the `missing` state is correct.

### 5.4 Uninstall semantics

- Uninstall deletes: the plugin directory, the `pluginState` record, and prompts materialised by that plugin (hash guard in §6.2).
- It does not delete prompts edited by the user — those become ordinary prompts (see §6.2).
- Upgrade: install into staging → validate → move the old directory to `.trash` → place the new directory → remove old contributions before applying new ones → clean `.trash`.

---

## 6. Contribution materialisation rules

### 6.1 `aiSkill` → user prompts (P1a)

- Materialises as `UserPrompt`:
  - `id`: `plugin:<pluginId>:<skillId>`
  - `name` / `content`: the localised manifest values; `content` ≤ 8000 chars, `name` ≤ 40 chars
  - `enabled`: the manifest value (default `true`)
  - `order`: increments in manifest order after the current maximum
  - `createdAt` / `updatedAt`: the install time
- Write path: `Prefs().userPrompts = [...]`; the AI prompt picker groups "from plugins" by whether the plugin is still installed, without relying on id prefixes for display decisions.
- Limit: ≤ 30 prompts per plugin; `id` is globally unique.
- Note: these are **prompt templates**, not reading-skill policies (`readingSkillPolicies` belong to P2), so `readany_skills.dart` and `reading_skill_execution.dart` are untouched.
- Same-id conflicts: an upgrade replaces this plugin's old entry; if the same id already exists and belongs to another owner (an abnormal case), reject the install with a message.

### 6.2 Uninstall/upgrade cleanup and the hash guard (P1a)

A successful install records:

```json
"applied": {
  "prompts": [{ "id": "plugin:com.example.prompt-pack:deep-summary", "contentSha256": "…" }]
}
```

- On uninstall/upgrade, delete only when the current `content` hash matches the record.
- A hash mismatch means the user edited it: **rename the id to `custom-<timestamp>` and keep the content**, removing it from the plugin's entries. Reinstalling the same plugin therefore cannot collide with the old entry, and the user's edit survives.
- Save a raw `userPrompts` JSON snapshot before materialising; on any failure write the snapshot back, clean staging and roll back state.
- Write order: write `userPrompts` first, then `pluginState` only after success, so a crash cannot leave "state recorded, contribution missing".

### 6.3 `selectionAction` (P1b, implemented)

The same prompt mechanism, but targeting `SelectionToolbarItem` (`action: aiCommand`):

- Materialised id: `custom-plugin:<pluginId>:<actionId>`. The prefix must be `custom-` to reuse the existing `validate()` custom-action rules; reject the install when the combined id exceeds 100 chars.
- Custom action slots ≤ 24 (checked before install, without changing `validate()`); on upgrade, actions already owned by this plugin do not consume new slots.
- `name` ≤ 30, `icon` ∈ `SelectionToolbarConfig.iconIds`, `skillId` fixed to `selection_toolbar`, `scope` either `context` or `selection`.
- The hash covers name, icon, prompt and scope; delete on uninstall only when it matches, otherwise rename the id to `custom-<timestamp>` and keep it as an ordinary custom command.
- Snapshot and rollback cover both `userPrompts` and `selectionToolbar`.

---

## 7. UI

### 7.1 Entry point

Add one row to the `settings` list of `SubMoreSettings` (`lib/page/settings_page/more_settings_page.dart:97-207`):

- Title: `ModuStrings.text(context, '插件', 'Plugins')`
- Icon: `Icons.extension_outlined`
- Subtitle: "N installed · M enabled"
- Position: before **Advanced** (always shown, not gated behind developer options)

Mobile reuses the same `SubMoreSettings`; no extra entry is needed.

### 7.2 Plugin list page

- Top "Install plugin…" button → `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['moduplugin','zip'])`.
- List items: name, version, author, status badge (enabled/disabled/missing/broken), switch.
- Menu: details, reinstall, uninstall (with a second confirmation describing what will be deleted).
- Empty state: explains the package format and links to the sample plugin documentation.

### 7.3 Details page (P1)

- Basic information: id, version, licence, author, install time, package SHA-256.
- Permissions: host-maintained capability descriptions (`ai:prompt-pack` → "Add AI prompt templates"), never the plugin's own claims.
- Contribution list: prompt names and enabled state.
- Settings: from P1b, rendered on the details page with `ServiceConfigForm`; edits autosave to `pluginConfig_<id>` after a short debounce.
- Selection actions: the details page shows action names and the used/remaining 24 custom slots.
- Diagnostics: the last error (redacted) and the raw manifest text (collapsed).

### 7.4 Copy

New UI copy uses `ModuStrings.text(context, zh, en)` and adds no ARB keys (plugin copy itself comes from the manifest through the §3.2 fallback chain). Logs and exceptions use English for easier searching.

---

## 8. File-level change list

### 8.1 Additions

| File | Content |
|---|---|
| `lib/models/plugin_manifest.dart` | `PluginManifest`, `PluginContribution` (`AiSkillContribution`, `SelectionActionContribution` + `UnknownContribution` fallback), `PluginSettingSpec`; hand-written strict `fromJson` and limit constants |
| `lib/models/plugin_state.dart` | `PluginRecord`, `PluginState` (normal parsing + `parseStrict` for import), `PluginStatus` enum; JSON encode/decode |
| `lib/service/plugins/plugin_package.dart` | `PluginPackageReader.read(File)`: limits, path safety, extraction staging, manifest parsing, `PluginInstallError` |
| `lib/service/plugins/plugin_paths.dart` | Directory constants, `ensureCreated()`, `cleanStale()` |
| `lib/service/plugins/plugin_host.dart` | Singleton, `ChangeNotifier`, install/enable/disable/uninstall/upgrade, startup scan, error isolation |
| `lib/service/plugins/plugin_contribution_handler.dart` | D9 handler interface and registry |
| `lib/service/plugins/handlers/ai_prompt_handler.dart` | P1a: `aiSkill` → `UserPrompt` apply/remove and hash guard |
| `lib/service/plugins/handlers/selection_action_handler.dart` | P1b: `selectionAction` → custom toolbar command apply/remove, 24 slots and hash guard |
| `lib/service/plugins/handlers/plugin_locale.dart` | Resolves the current locale once when materialising contributions |
| `lib/service/plugins/plugin_config.dart` | `pluginConfig_<id>` encode/decode, import validation and default merging |
| `lib/service/plugins/plugin_contributions.dart` | Orchestration: find handler by kind, snapshot rollback |
| `lib/service/plugins/script_runtime.dart` | `ScriptRuntime` interface + `NoopScriptRuntime` (P4 extension point) |
| `lib/page/settings_page/plugins/plugins_page.dart` | List page |
| `lib/page/settings_page/plugins/plugin_detail_page.dart` | Details page (permissions/contributions/plugin settings/diagnostics/slots) |
| `scripts/dev/pack_plugin.dart` | Packs a directory into a deterministic zip (sorted entries, fixed timestamps) for tests and sample releases |
| `docs/examples/plugins/prompt-pack/` | Sample plugin: `manifest.json` + `LICENSE` (CC0) + `README.md`, two `aiSkill` entries |

### 8.2 Modifications

| File | Change | Anchor |
|---|---|---|
| `lib/main.dart` | call `PluginHost.initialize()` after `DBHelper().initDB()`; `dispose()` in `onWindowClose()` | `:173`, `:287` |
| `lib/utils/get_path/get_base_path.dart` | add `getPluginDir()` and create it in `initBasePath()` | adjacent to `:67-87`, `:95-113` |
| `lib/models/selection_toolbar.dart` | `SelectionToolbarItem.copyWith` gains `id` (so an edited plugin action can be renamed to `custom-*` on uninstall); `validate()` unchanged | `:31` |
| `lib/widgets/settings/service_config_form.dart` | number inputs accept decimals; text items support `maxLength` (plugin text limit 8000) | `:147` |
| `lib/service/config/config_item.dart` | add optional `maxLength` for plugin text input limits | `:20` |
| `lib/config/shared_preference_provider.dart` | `pluginState` read/write, `pluginConfig_<id>` read/write, `removePluginData` (state + settings) | around `:1461` |
| `docs/SETTINGS.md` / `docs/SETTINGS_zh.md` | add the "Plugins" section and the backup boundary | settings entry and backup sections |
| `lib/page/settings_page/more_settings_page.dart` | add the "Plugins" row to settings | `:97-207` |
| `pubspec.yaml` | declare `pub_semver` explicitly (currently available transitively via `pubspec_parse`) | `dependencies` |
| `docs/SETTINGS.md` / `docs/SETTINGS_zh.md` | add the "Plugins" section and the backup boundary | settings category section |

P1b changes `copyWith` in `lib/models/selection_toolbar.dart` (not `validate()`); P1c changes `settings_modules.dart`, `global_settings_transfer.dart` and `settings_value_validation.dart`.

Untouched: database, sync, TTS, translation, dictionary, the AI tool registry and `SelectionToolbarConfig.validate()`.

---

## 9. Key implementation details

### 9.1 Path-safe extraction

`extractArchiveToDiskSync` from the `archive` package does not constrain target paths; existing uses only handle trusted archives (`lib/page/settings_page/sync.dart:827-835`). Plugin packages must write entries manually, one by one:

```dart
var total = 0;
for (final entry in archive.files) {
  if (!entry.isFile) continue;                 // reject directories and symlinks
  final name = entry.name.replaceAll('\\', '/');
  if (name.startsWith('/') || name.contains('..') || name.contains(':')) {
    throw PluginInstallError.invalidPath(name);
  }
  final target = File(p.join(staging.path, name));
  if (!p.isWithin(staging.path, target.path)) throw PluginInstallError.invalidPath(name);
  // Limit by the size declared in the header before extracting, so a bomb is
  // rejected before it is decompressed.
  if (entry.size > maxFileBytes || total + entry.size > maxTotalBytes) {
    throw PluginInstallError.tooLarge(name);
  }
  total += entry.size;
  final bytes = entry.content as List<int>;    // ZipFile.content returns decompressed bytes synchronously
  await target.parent.create(recursive: true);
  await target.writeAsBytes(bytes, flush: true);
}
```

Implementation note: `archive` 3.x already normalises backslashes to `/` in entry names while decoding, so the backslash check above is defence in depth; tests observe `assets\evil.txt` being safely written as `assets/evil.txt`. What actually blocks escapes is the `..` segment, absolute path, drive letter, empty segment and `p.isWithin` checks; `test/service/plugins/plugin_package_test.dart` covers these branches.

### 9.2 Version comparison

```dart
bool meetsMinAppVersion(String current /* 1.3.1+10152 */, String min) {
  Version.parse(current.split('+').first)
      .compareTo(Version.parse(min)) >= 0;
}
```

### 9.3 Count checks

P1a: ≤ 30 `aiSkill` entries per plugin; no new limit on the total number of `UserPrompt` entries (current behaviour appends without bound), but prompt content ≤ 8000 chars and names ≤ 40 chars.

P1b (selection actions) additionally checks toolbar slots:

```dart
final config = Prefs().selectionToolbar;
final custom = config.items.where((i) => i.isCustom).length;
if (custom + actions.length > 24) throw PluginInstallError.noToolbarSlots(24 - custom);
```

### 9.4 Install pseudocode (P1)

```
install(file):
  pkg = PluginPackageReader.read(file)          # validation + staging + manifest
  check minAppVersion / capabilities / conflicts
  snapshot = userPrompts.raw
  try:
    applied = PluginContributions.apply(pkg)    # goes only through the aiSkill handler
    Prefs().userPrompts = merge(applied.prompts) # write contributions first
    move staging -> plugins/<id> (old dir -> .trash)
    state.upsert(record(applied))
    savePluginState                              # then write state
    notifyListeners()
  catch:
    restore snapshot; clean staging; rethrow
```

The order applies contributions before persisting, so a failure never writes state; `savePluginState` calls `notifyListeners()` after writing and the UI refreshes immediately. From P1b the snapshot contains both `userPrompts` and `selectionToolbar`, and rollback restores both.

---

## 10. Test matrix

| Phase | Layer | File | Coverage |
|---|---|---|---|
| P1a | Models | `test/models/plugin_manifest_test.dart` | valid/missing fields/type errors/oversized/unknown kind ignored/unopened capability rejected/i18n fallback/`settings` parsing |
| P1a | Package reading | `test/service/plugins/plugin_package_test.dart` | normal package, missing manifest, oversized, too many entries, zip-bomb ratio, `..`, absolute path, empty segment, backslash normalisation, non-zip, unopened capability |
| P1a | Host | `test/service/plugins/plugin_host_test.dart` | install, duplicate install, upgrade, downgrade rejection, enable/disable, uninstall, missing, broken, `initialize` idempotence |
| P1a | Contributions | `test/service/plugins/plugin_contributions_test.dart` | `aiSkill` materialised fields, ordering, 30-entry limit, rename-and-keep after user edits, failure rollback, upgrade replacement |
| P1a | Widgets | `test/widgets/settings/plugins_page_test.dart` | empty state, status badges, switches, uninstall confirmation, details permissions and contribution list, plugin settings render and persist |
| P1a/P1b | Sample | `test/service/plugins/sample_plugin_test.dart` | reads `docs/examples/plugins/prompt-pack/` directly, packs and installs it into mock Prefs, asserts two prompts, one selection action and settings declarations |
| P1b | Toolbar | `test/service/plugins/selection_action_test.dart` | 24-slot boundary, name/icon/scope validation, hash guard, user edits preserved, upgrade does not double-count slots |
| P1b | Settings | `test/widgets/settings/plugins_page_test.dart` | details actions and plugin settings render; edits persist |
| P1b | Regression | existing `test/models/selection_toolbar_test.dart`, `test/widgets/selection_toolbar_test.dart` | toolbar encode/decode and limits intact (46 tests pass) |
| P1c | Configuration | `test/service/config_transfer/plugin_settings_transfer_test.dart` | export includes `pluginState`/`pluginConfig_*`, round trip, invalid shapes and types rejected, uninstall cleanup |

P1a manual acceptance (record in the PR):

1. Install the same `.moduplugin` on all 6 platforms.
2. The AI panel prompt picker shows both templates; running one sends the full prompt to the AI.
3. Disable the plugin → templates disappear; re-enable → they return.
4. Manually edit a plugin template → uninstall → it remains as an ordinary prompt (id already changed to `custom-*`).
5. Delete the plugin directory and restart → it shows `missing`, the app does not crash and uninstall still works.
6. Malicious packages are built by `test/service/plugins/plugin_package_test.dart` (path traversal, zip bomb, oversized entry, unknown capability) and each is rejected with a readable reason.
7. Export/import settings are accepted in P1c; for P1a just confirm export does not break the app (plugin keys ignored).

P1b/P1c manual acceptance (record in the PR):

1. Install a package with `selectionAction` → the action appears in the selection toolbar and sends the full prompt to the AI; disabling/uninstalling removes it.
2. Manually edit the action's name/icon/prompt → uninstall → the action remains as an ordinary custom command (id changed to `custom-*`).
3. With 24 custom actions already present, installing another is rejected with the remaining-slot count; deleting one allows the install.
4. Edit plugin settings → they persist across restarts; export settings to another device → the plugin shows `missing` with settings intact, and reinstalling the package makes it usable again.
5. Import a tampered `pluginState` or `pluginConfig_*` → rejected as a whole, with no local settings modified.
---

## 11. PR split and acceptance

P1 is split into three PRs; all three are implemented:

| PR | Content | Estimate | Acceptance |
|---|---|---|---|
| **P1a (implemented)** | manifest/state models, package reading, host, `aiSkill` handler, settings pages (list/details/permissions), `main.dart` wiring, sample plugin, `pack_plugin.dart`, all P1a tests | 6–7 person-days | install/uninstall/disable on 6 platforms; templates appear in the AI panel after installing the sample; malicious packages all rejected; `flutter analyze` clean |
| **P1b (implemented)** | `selectionAction` handler + toolbar slots/hash guard + details action list + `pluginConfig_` settings form | 3–4 person-days | 24-slot boundary; user edits preserved; existing toolbar regression passes |
| **P1c (implemented)** | settings export/import wiring + validation + `docs/SETTINGS.md` / `SETTINGS_zh.md` | 2–3 person-days | backup round trip consistent; missing plugin shows `missing` |

P1 internal commit order (P1a complete; P1b/P1c each one commit, every commit compiles and passes tests):

1. `plugin_manifest.dart` + `plugin_state.dart` + unit tests (limits, i18n, unknown kind/capability).
2. `plugin_package.dart` + `plugin_paths.dart` + path-safety/limit tests.
3. `plugin_contribution_handler.dart` + `plugin_contributions.dart` + `handlers/ai_prompt_handler.dart` + unit tests.
4. `plugin_host.dart` + `pluginState` read/write in `Prefs` + unit tests.
5. Settings pages + entry point + widget tests.
6. `main.dart` wiring + sample plugin + `pack_plugin.dart` + documentation.

P1 totals about **11–14 person-days** (including integration and rework buffer). P1a touches no database, settings export, sync, TTS/translation/dictionary or selection toolbar; P1b changes only toolbar materialisation and the settings form; P1c changes only settings migration. Each can be reverted independently.

---

## 12. Compliance and licence checklist

- [ ] Plugins must declare an SPDX `license`; the install page shows it and refuses installation when missing.
- [ ] Documentation states: plugins are independent works; Modu is distributed under GPL-3.0-or-later and plugins must be GPL-compatible (more permissive is allowed; proprietary redistribution restrictions are not).
- [ ] Plugin code is not linked into the app binary (P1 is pure data, which satisfies this inherently).
- [ ] Store compliance: P1 has no executable content; P4 JS is interpreted only by WebKit/WKWebView, matching the iOS 2.5.2 interpreted-code exception; no dex/so/dylib downloads.
- [ ] The install page shows no unverified "official" badge; the sample plugin states "example, not officially supported".
- [ ] Privacy: plugin packages contain no user data; host logs never record full prompts or credentials.

---

## 13. Risks and rollback

| Risk | Phase | Mitigation |
|---|---|---|
| Prompt lists drowned by plugin entries | P1a | ≤ 30 per plugin; grouped UI; uninstall cleans up |
| User edits conflict with uninstall cleanup | P1a | Hash guard; edited entries renamed to `custom-*` and kept |
| Package missing while state exists | P1a | `missing` status + uninstall available; startup does not crash |
| Multiple startup paths (Android delay, macOS migration) | P1a | `initialize()` idempotent; both paths call it; failures never block startup |
| Package parsing crash | P1a | All parsing wrapped in try/catch; `lastError` persisted; broken packages can be uninstalled |
| Toolbar slots exhausted | P1b | Explicit pre-install check and rejection; details page shows used/remaining slots |
| Missing plugin after config export confuses users | P1c | `missing` status + explicit copy + "configuration kept" notice |
| Future script contributions conflict with P1 data | from P1a | Manifest reserves the `script` kind and `hostApi`; unknown kinds are ignored, never misread |

Rollback: remove the `initialize()` call in `main.dart` and all plugins stop working (data is kept); alternatively use `--dart-define=MODU_PLUGINS=false`.

---

## 14. Handover to later phases

| Phase | Interface this document must guarantee | Later change |
|---|---|---|
| P1b | `PluginContributionHandler` registry, generic `AppliedContribution` structure | `selectionAction` handler added; snapshot and rollback extended to `selectionToolbar` |
| P1c | Stable `pluginState` structure, `PluginStatus.missing` implemented | Wired into export/import, strict validation and module scopes |
| P2 registries | String `PluginContribution.kind`, capability tokens, generic `PluginRecord.applied` structure | TTS/translation/dictionary/tools move to ID registries; P2 opens no provider contributions (see the P2–P3 document) |
| P3 network plugins | Capability model already contains `net:http`; `PluginSettingSpec` can carry domains/secrets | First opening of `dictionarySource`; domain allowlist, quotas, request proxy; translation/TTS deferred to P3.1 |
| P4 script host | `ScriptRuntime` interface, `script` kind, `hostApi` version | Implement `WebViewScriptRuntime`, capability `script:run`, OHOS overlay adapter |
| P5 ecosystem | Package SHA-256 already present; `broken/missing` states exist | Add signing/revocation lists, marketplace metadata, developer tools |

For the P2/P3 manifest shape, registry interfaces, network guard, secret boundary, test plan and PR split, see the [Plugin system P2–P3 design and execution document](plugin-system-p2-p3.md).

### About HarmonyOS

OHOS has an ArkWeb build of `flutter_inappwebview`, but it is enabled only in the cloud-built dependency overlay (`scripts/harmony/audio_webview_overrides.json:79-113`, `scripts/harmony/prepare.py:15-28`), and:

1. `HeadlessInAppWebView` is unavailable on OHOS, so `AnxHeadlessWebView` falls back to an Overlay (`lib/utils/webView/anx_headless_webview.dart:60-80`).
2. That adapter carries a creation-time `javaScriptBridgeEnabled` security policy; disabling it also disables `callAsyncJavaScript`, WebMessage and non-page-world scripts (`scripts/harmony/WEBVIEW_PATCH.md:43-58`).
3. It is currently an unsigned HAP, built in the cloud, with no real-device acceptance (`docs/development/harmonyos-support.md:3-7`, `:104-108`).

Therefore, for the P4 script host to work on OHOS it needs **a separate overlay host implementation + real-device validation**, not a hidden WebView reuse. P1 declarative plugins are platform-independent and identical on all 6 platforms; script capabilities should appear unavailable in the UI based on "capability + runtime availability", not hard-coded per platform.

---

## 15. Confirmed decisions (basis for P1 implementation)

1. Plugin prompts default to enabled — implemented per spec (manifest `enabled` defaults to `true`).
2. The "plugins" module in settings export — implemented as included by default (`all` and `plugins` scopes); it is only a small JSON payload.
3. The "Plugins" entry is not gated behind developer options — implemented and visible to ordinary users.
4. Sample plugin licence — CC0-1.0 is used.
---

## 16. Handover runbook

### 16.1 Environment and commands

Toolchain (`docs/development/local-toolchain.md`): **Flutter 3.47.2 / Dart 3.13.2** (FVM, `.fvmrc`), JDK 17, Android SDK 36 / Build Tools 36.0.0, Gradle 9.2.1, AGP 9.0.1, Kotlin 2.3.20.

CI commands in order (`pr-check.yml:57-67`):

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Single-file debugging:

```bash
flutter test test/models/plugin_manifest_test.dart
flutter test test/service/plugins/
```

Notes:

- Flutter 3.47.2's LSP `Content-Length` has a known defect under Chinese workspace paths; the local SDK is patched. **Do not reinstall the SDK casually** (see "Flutter analysis with Chinese workspace paths" in `local-toolchain.md`).
- P1 models use hand-written parsing and produce no `.g.dart`; CI still runs `build_runner`, so run it locally before committing and check `git status` for unexpected generated files.
- Do not commit `build/`, `.dart_tool/` or log files.

### 16.2 Suggested reading order (for the next engineer/agent)

1. §2–§4 of this document: constraints, package spec, host architecture.
2. `lib/models/user_prompt.dart`, `lib/providers/user_prompts.dart`: the P1a materialisation target and write path.
3. `lib/models/selection_toolbar.dart`: the P1b materialisation target, especially the 24 custom slots and `custom-` prefix rules in `validate()`.
4. Around `lib/config/shared_preference_provider.dart:1438`: the existing pattern for JSON settings.
5. `lib/main.dart:103-207`, `:257-296`, `:462-475`: startup and shutdown paths.
6. P1c configuration migration: `lib/service/config_transfer/{settings_modules,global_settings_transfer,settings_value_validation}.dart`.
7. The P1b plugin settings form: `lib/widgets/settings/service_config_form.dart`.

### 16.3 Glossary

| Term | Meaning |
|---|---|
| package | `.moduplugin` (a zip), pure data |
| contribution | one item in manifest `contributes[]`, dispatched by `kind` |
| capability | a category of operations a plugin may perform, authorised at install |
| staging / trash | temporary directories for install and uninstall |
| applied | records of materialised contributions (including content hashes) |
| `broken` / `missing` | package damaged / state exists but the package is absent |
| `PluginHost` | host singleton and the only state entry point |
| `ScriptRuntime` | script runtime interface (P1 has `NoopScriptRuntime` only) |

### 16.4 Known pitfalls

- `Prefs` is a `ChangeNotifier` singleton that calls `notifyListeners()` after writes; do not read uninitialised `prefs` during construction (`shared_preference_provider.dart:195-230`).
- The macOS migration can run `initBasePath` / `initDB` twice, so `PluginHost.initialize()` must be idempotent.
- Plugin actions go through `validate()` in `SelectionToolbarConfig.encode()` (total count, 24 slots, field lengths), so plugin ids must keep the `custom-` prefix; do not modify `validate()`.
- P1a writes prompts through `Prefs().userPrompts = list` (internal `jsonEncode` + `setString`), so there is no async save issue; still "write contributions first, then pluginState".
- Plugin settings store only keys the user changed; reads backfill manifest defaults, and export keeps the stored shape to avoid polluting backups with defaults.
- User prompt ids are strings; do not assume timestamps or numbers. Plugin entries use `plugin:<pluginId>:<skillId>`.
- A user-edited plugin prompt must be renamed to `custom-<timestamp>` before uninstall, otherwise reinstalling collides on the id.
- `ZipFile.size` is the decompressed size: **check the limit against `size` before reading `content`**, otherwise a zip bomb exhausts memory during extraction.
- Settings export adds a `reset` entry for every key in `_types`; when P1c adds keys, define what "not set" means on another device.

### 16.5 Document language policy

`CONTRIBUTING.md` requires singleton guides to be written in English. This execution document is maintained in English, and so is the [P2–P3 design document](plugin-system-p2-p3.md). User-facing English/Chinese pairs (`docs/SETTINGS.md` / `docs/SETTINGS_zh.md`) remain bilingual as required for core user guides. Update this document in English from now on.

### 16.6 Change log

| Date | Version | Change |
|---|---|---|
| 2026-10-23 | v0.1 | First draft: P0 spec + P1 execution plan; added handover summary (§0), ADR note (§2.1), runbook (§16); upstream synced to `0feceeb9` |
| 2026-10-23 | v0.2 | Narrowed the first PR per review: P1 split into P1a (install + `aiSkill` + sample plugin) / P1b (selection actions) / P1c (configuration export); added the `ContributionHandler` registry (D9); deferred `settings` to P1b; updated tests and PR split accordingly |
| 2026-10-23 | v0.3 | Implemented P1a: manifest/state models, package reading and path safety, host (install/enable/disable/uninstall/upgrade/idempotent scan), `aiSkill` handler, `Prefs.pluginState`, settings pages and entry, `main.dart` wiring, sample plugin and `pack_plugin.dart`; 45 tests pass. Recorded `archive`'s backslash normalisation; noted that `flutter analyze` only reports the pre-existing `avoid_print` info |
| 2026-10-23 | v0.4 | Implemented P1b/P1c: opened `ui:selection-action`; added `SelectionActionContribution`/handler (24 slots, name/icon/scope validation, hash guard, edits kept as `custom-*`); enabled `pluginConfig_` and the details-page `ServiceConfigForm`; wired `pluginState`/`pluginConfig_*` into settings export, strict validation and module scopes; added the English and Chinese `SETTINGS` plugin sections. 46 toolbar regression tests and all new plugin/configuration tests pass |
| 2026-10-24 | v0.5 | Sample plugin upgraded to 1.1.0: added a `selectionAction` (`explain-selection`) and `settings` (select/toggle/number/tip); updated the README, execution document and `sample_plugin_test` |
| 2026-10-24 | v0.6 | Translated the whole document into English per `CONTRIBUTING.md`; no technical content changed except the language policy in §16.5 |

### 16.7 Starter prompt for the next agent (P1a/P1b/P1c are done; kept as a reproduction/redo instruction)

```text
Repository: D:Codemodureader (Flutter 3.47.2, FVM). Baseline: main @ 0feceeb9; the working tree
should be clean except for docs/development/plugin-system-p0-p1.md and docs/README.md.

Read docs/development/plugin-system-p0-p1.md in full first, especially §0 (handover summary),
§2 (frozen decisions), §3 (package spec), §4 (host architecture and handler registry),
§8 (file-level changes), §10 (tests), §11 (PR split) and §16 (runbook).

Task: implement P1a (one PR, with the six commits in §11):
- package models and strict validation: lib/models/plugin_manifest.dart, lib/models/plugin_state.dart
- package reading and path safety: lib/service/plugins/plugin_package.dart, plugin_paths.dart
- host: plugin_host.dart (install/enable/disable/uninstall/upgrade/startup scan/idempotent init)
- contribution registry: plugin_contribution_handler.dart + handlers/ai_prompt_handler.dart + plugin_contributions.dart
- Prefs: pluginState read/write + removePluginData
- settings pages: lib/page/settings_page/plugins/ (list, details, install/uninstall, permissions and contributions)
- wiring: lib/main.dart (initialize after DB init, dispose on close), more_settings_page.dart entry
- sample plugin: docs/examples/plugins/prompt-pack/ (manifest + LICENSE(CC0) + README)
- packaging script: scripts/dev/pack_plugin.dart
- tests: the P1a rows in §10

Do not do: selectionAction (P1b), settings form and pluginConfig_ (P1b), settings export (P1c),
JS/script runtime, any database migration, any SelectionToolbarConfig change.

Hard constraints:
- Open only ai:prompt-pack in capabilities; unknown capabilities reject the install, unknown
  contribution kinds are ignored with a warning.
- Limits, path safety and zip-bomb protection follow §3.5 and §9.1.
- Prompt ids use plugin:<pluginId>:<skillId>; on uninstall delete only when the hash matches,
  otherwise rename the id to custom-* and keep the entry.
- Add no native dependencies; do not commit .g.dart outputs.
- Before committing run: flutter pub get, flutter gen-l10n,
  dart run build_runner build --delete-conflicting-outputs,
  flutter analyze --no-fatal-infos --no-fatal-warnings,
  flutter test test/models/plugin_manifest_test.dart, flutter test test/service/plugins/.

Acceptance: all P1a rows in §10 pass; the §1.3 DoD is met; report the change list, test results
and 6-platform manual acceptance status.
```

### 16.8 Related documents

- [Local toolchain](local-toolchain.md): Flutter/Dart/Android versions and the Chinese-path analysis patch.
- [HarmonyOS support](harmonyos-support.md): cloud overlay, unsigned HAP, current ArkWeb adapter state.
- [Testing strategy](../TESTING.md): build, automated checks and real-device acceptance must be reported separately.
- [Contributing guide](../../CONTRIBUTING.md): GPL licensing, regression tests, documentation language policy.
