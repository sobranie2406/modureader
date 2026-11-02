# Plugin System P2–P3 Design and Execution Document (Registries + Declarative Network Plugins)

> Roadmap only, not approved functionality. [Plugin trust](plugin-trust.md) takes
> precedence: no third-party sources, network plugins or script execution are
> enabled by the current experimental switch.

Status: design draft, pending review · 2026-10-24 · baseline `3cdf7365` (P1 implemented; the working tree also contains uncommitted P1b/P1c changes) · this document defines P2/P3 only, with no implementation

This document continues [Plugin system P0–P1 execution plan](plugin-system-p0-p1.md). P2 turns the dispatch paths for translation, speech (TTS), dictionaries, AI tools/skills and the selection toolbar into registries keyed by stable IDs. P3 opens **declarative network plugins** on top of those registries, starting with dictionary HTTP sources. The P4 WebView script host and P5 signing/ecosystem work are out of scope.

---

## 0. Handover summary (read this first)

### 0.1 One-line conclusion

P2 is an **internal architecture change** that adds no user-visible plugin capability. P3 is the **first new plugin capability**: plugins may only issue HTTP requests through a host proxy, constrained by a domain allowlist, request templates and quotas. P2 must land first so P3 can safely reuse the same registries, lifecycle and settings migration.

### 0.2 Phase boundaries

| Phase | Content | Deliverables | Estimate | Gate |
|---|---|---|---|---|
| **P2a** | Registry core + AI tools/reading skills on registries | `HostRegistry`, `RegistryCatalog`, AI tool and skill descriptors, compatibility checks and unit tests | 3–4 person-days | Existing `enabledAiTools` / `readAnySkill*` data lost: zero; no behaviour change |
| **P2b** | Translation + TTS on registries | Translation/TTS descriptors, factories, config-key allowlists, backup migration | 3–4 person-days | Old enum names and config still readable; export/import round-trips |
| **P2c** | Dictionary + selection toolbar on registries, wired into the P1 contribution lifecycle | Dictionary source descriptors, toolbar action descriptors, `isApplied` lifecycle | 3–4 person-days | Old toolbar JSON, old dictionary selections and P1 plugin actions all unchanged |
| **P3** | Declarative network plugins v1: dictionary HTTP sources | `net:http`, `dictionarySource`, host HTTP proxy, domains/quotas/secrets | 8–10 person-days | Unauthorised requests rejected; secrets never in backups; text lookup works on all 6 platforms |

P2 totals about **9–12 person-days**; P3 about **8–10 person-days**. Each of the three P2 PRs can be reverted independently; P3 starts after all of P2 has landed.

### 0.3 Two adjustments to the P0 roadmap

The P0 document (§14) said "P2 adds kinds such as `ttsProvider`". This document changes that explicitly:

1. **P2 does not open `ttsProvider` / `translatorProvider` contributions.** Without a network transport or script runtime these contributions would be metadata only and could not actually work. Opening them early would create dead UI ("installs but cannot be selected" or "selected but does nothing") and force another manifest change in P3. P2 only moves the built-in engines onto registries and completes the plugin contribution lifecycle; P3 then opens provider-like contributions on the same declarative HTTP adapter.
2. **P3 v1 opens `dictionarySource` only.** Translation and TTS have larger request/response differences (streaming, audio, auth headers); leave them to P3.1 on the same HTTP adapter. P3 v1 makes no promise of plugin TTS/translation.

Neither adjustment changes the conclusions "target form C, script host in P4, WebView as the only host".

### 0.4 Current code facts (P1 baseline)

- Plugin host: `lib/service/plugins/plugin_host.dart`, with install/enable/disable/uninstall/upgrade, `PluginStatus`, startup reconciliation and the `AppliedContribution` hash guard.
- Contribution registry: `lib/service/plugins/plugin_contribution_handler.dart` + `plugin_contributions.dart`, resolving handlers by `kind`; P1 registers `aiSkill` and `selectionAction`.
- Plugin state: the single `pluginState` key plus `pluginConfig_<id>`; P1 already wires both into settings export and strict validation.
- Built-in dispatch state (**P2a/P2b/P2c landed: all six domains are registry-based**):
  - Translation: `TranslateRegistry.current` wraps `HostRegistry<TranslateProviderEntry>`; the enum stays only because its `name` is the persisted token. `microsoft` is an alias of `microsoftApi`, and picker orders are explicit lists rather than registration order (`lib/service/translate/translate_registry.dart`).
  - TTS: `TtsRegistry.current` wraps `HostRegistry<TtsProviderEntry>`; `aliyun`/`azure` are aliases of `system`, and the transfer snapshot keeps the historical five-provider order while preserving unknown providers on import (`lib/service/tts/tts_service.dart`, `lib/service/config_transfer/tts_config_transfer.dart`).
  - Dictionary: `DictionarySourceRegistry.current` wraps `HostRegistry<DictionarySourceEntry>`. Built-in tokens (`online:wiktionaryZh`, `local:<uuid>`) are unchanged; unknown tokens (including `online:plugin:...`) are kept in storage and hidden from the UI so reinstalling a plugin restores the selection (`lib/service/dictionary/dictionary_source_registry.dart`).
  - AI tools: `AiToolRegistry.current` wraps `HostRegistry<AiToolEntry>`; ids unchanged and persisted on purpose (`lib/service/ai/tools/ai_tool_registry.dart`).
  - Reading skills: `ReadingSkillRegistry.current` wraps `HostRegistry<ReadingSkillEntry>` and keeps retired prompts visible to recognition only (`lib/service/ai/reading_skill_registry.dart`).
  - Selection toolbar: `SelectionToolbarConfig.validate()` no longer compares list identities (`identical(defaults, defaultItems)`); built-in identity comes from `ToolbarCatalog` in `lib/models/toolbar_action_definition.dart`, wrapped by `ToolbarRegistry` (`lib/service/registry/toolbar_registry.dart`). The model layer stays free of service imports.
- Contribution lifecycle (P2a): `PluginContributionHandler` gained `isApplied` and `runtimeOnly`; `PluginHost` no longer switches on `kind`. Declarative kinds keep P1's "rebuild only when every entry is gone" rule, runtime-only kinds are rebuilt on every start.
- Network: existing dictionaries call `Dio` directly (`online_dictionary.dart:42-80`); there is no shared plugin network exit, no domain allowlist, no quota and no secret isolation.

### 0.5 Next steps

1. Review this document, focusing on D10–D22 in §3 and the manifest shape in §5.3.
2. Run a 1-person-day spike for P2a proving that `HostRegistry` can replace the static AI tool and skill tables without changing existing settings keys, and that tests can inject substitutes.
3. Before P2, repeat a real cross-device plugin acceptance run (install → disable → back up → restore on another device → reinstall) as the P2/P3 regression baseline.
4. Write the P3 security review after P2 lands; do not write P3 code first and add the review later.

---

## 1. Goals and non-goals

### 1.1 P2 goals

1. Build **stable string ID + descriptor** registries for six built-in extension points: translation, TTS, dictionary sources, AI tools, reading skills and selection-toolbar actions.
2. Remove dispatch-time `switch` statements and dependencies on static `const` lists; UI, preset data and import validation all read from the registries.
3. Keep every **existing persisted key and value unchanged**: old enum names/tool IDs/skill IDs/toolbar IDs stay readable, and P2 requires no user reconfiguration.
4. Let the P1 plugin contribution lifecycle know whether the runtime registry actually contains a contribution. This fixes `_isMaterialised`, which after a restart only checks prompts/toolbar entries and cannot cover future provider kinds.
5. Reserve registration, unregistration, conflict detection and UI presentation interfaces for P3's `dictionarySource`, without opening network capabilities in P2.

### 1.2 P3 goals

1. Add the `net:http` capability token; plugins may only reach the exact domains declared in their manifest through a **host HTTP proxy**.
2. Add a `dictionarySource` contribution: a declarative request template plus a declarative JSON response mapping, with no plugin code executed.
3. Implement the domain allowlist, HTTPS-only, no redirects, private/loopback address blocking, timeouts, response-size limits, concurrency/rate/daily quotas, cancellation and an in-memory cache.
4. Separate plugin secrets from ordinary settings: `pluginSecret_<id>` stays on the device and **never enters settings export, WebDAV sync or database backups**; logs and error messages are redacted.
5. Show plugin sources alongside built-in online sources in the dictionary lookup UI, including source, licence and attribution. Disabling/uninstalling a plugin removes its source while keeping configuration and the user's selection.
6. Behave identically on all 6 platforms (Android / iOS / macOS / Windows / Linux / HarmonyOS); add no native dependencies and do not change the database version.

### 1.3 Explicitly out of scope

- P2 adds no plugin contribution kind and does not change the manifest's open capability set (still `ai:prompt-pack` and `ui:selection-action`).
- P2/P3 execute no plugin JS/Dart/native code; they introduce no QuickJS, dynamic libraries or WebView script host.
- P3 v1 does not support POST, request bodies, cookies, arbitrary headers, HTML parsing, pagination, OAuth, file uploads or WebSocket.
- P3 v1 does not open `translatorProvider` / `ttsProvider` plugin contributions; those wait for P3.1 or P4, depending on the P3 adapter review.
- No plugin marketplace, remote installation or signature/revocation list; P3 still has SHA-256 integrity checks only.
- Plugin packages, plugin private files and dictionary data do not enter settings backups; no new database tables, and `currentDbVersion` stays at 11.
- Plugins may not override built-in IDs, and two plugins may not register the same ID.

### 1.4 Definition of done (DoD)

**P2**

- `flutter analyze` reports no new warnings and `flutter test` is green.
- With the same old settings (including `translateService`, `ttsService`, `enabledAiTools`, `readAnySkill*`, `selectionToolbar` and `dictionaryLookupSources`), selections, ordering and enabled states match those before the upgrade.
- After an export/import round trip those keys keep their meaning, and unknown provider configuration is not dropped.
- P1's `aiSkill` / `selectionAction` behave the same across restart, disable, uninstall and upgrade; the new `isApplied` keeps the conservative policy of "if it cannot be determined, keep it" for unknown kinds.
- New tests cover the items marked P2 in §7.

**P3**

- Packages containing `net:http` show domains, purpose and quotas on the install page; packages that do not declare `net:http` cannot register `dictionarySource`.
- Plugins can only request allowlisted exact domains; redirects, private addresses, IP literals, userinfo, non-443 ports and non-HTTPS are all rejected.
- Per-lookup request count, response size, timeout, concurrency and rate all stay within quota; overruns return readable errors without affecting local dictionaries or other online sources.
- Plugin secrets never appear in settings export, database backups, logs, error pages or diagnostic text.
- Uninstalling/disabling a plugin removes its dictionary source immediately; reinstalling restores configuration and the source selection; a missing plugin does not crash.
- Manual acceptance passes on all 6 platforms; malicious-package tests reject everything.

---

## 2. Current state, gaps and constraints

### 2.1 Reusable P1 assets

| Asset | Location | P2/P3 use |
|---|---|---|
| `PluginHost` singleton and state machine | `plugin_host.dart` | Remains the only install/enable entry point; add registry reconciliation |
| `PluginContributionHandler` | `plugin_contribution_handler.dart` | P3 adds `DictionarySourceHandler`; P2 adds `isApplied` |
| `AppliedContribution` | `plugin_state.dart` | Do not extend its JSON fields; provider kinds use only `kind/id/contentSha256` |
| `PluginConfig` | `plugin_config.dart` | P3 adds a secret type and separate storage |
| Settings export/import | `settings_modules.dart`, `global_settings_transfer.dart`, `settings_value_validation.dart` | P2 switches to registry-driven allowlists; P3 excludes secrets |
| Backup redaction | `backup_safety.dart` | P3 must classify `pluginSecret_` as a credential |

### 2.2 Concrete gaps

1. **Enums are the dispatch centre**: `TranslateService` / `TtsService` simultaneously act as UI options, persisted values, factory and config-key source; adding a provider means touching the enum and several switches.
2. **Static tables are an implicit schema**: AI tools, skills, toolbar presets, icon IDs and skill IDs are all `const` lists; plugins cannot register into them and tests cannot inject substitutes.
3. **Config keys are coupled to provider names**: `translateServiceConfig_<enum.name>`, `onlineTtsConfig_<serviceId>` and `ttsVoiceModel_<serviceId>` concatenate the name directly; migration must preserve the old keys.
4. **Import validation hard-codes the service list**: `TtsConfigTransfer.services` fixes five entries, and `settings_value_validation.dart` checks `TtsConfigTransfer.services.contains(id)`; unknown providers degrade to "validate object shape only". P2 should preserve unknown keys explicitly rather than relying on branches that happen not to drop them.
5. **Plugin contribution reconciliation is incomplete**: `PluginHost._isMaterialised` only knows `aiSkill` and `selectionAction` and returns `true` for everything else; registry-backed contributions are empty in memory after a restart and would be misjudged as "still materialised".
6. **No shared network exit**: existing online dictionaries call `Dio()` directly, so domains, quotas, secrets and log redaction cannot be centralised. P3 must build the host proxy before allowing plugin sources.
7. **No secret setting type**: P1 explicitly forbids `password` because `pluginConfig_*` enters settings export. P3 secrets require isolated storage and must not reuse `pluginConfig_*`.

### 2.3 Design constraints

- Do not change the database schema; plugin configuration and secrets use SharedPreferences.
- Do not change the `pluginState` JSON shape written by P1; new behaviour lives in runtime and preference keys.
- Every new ID must be safe for SharedPreferences keys, JSON values and UI `ValueKey`s; no spaces or control characters other than colons.
- Network errors log only structured codes, plugin IDs, domains and status codes; **never the query term, full URL, headers or response body**.
- All user-visible copy uses `ModuStrings.text(context, zh, en)`; logs and exceptions use English.

---

## 3. Frozen decisions (P2/P3)

| No. | Decision | Rationale |
|---|---|---|
| D10 | Built-in extension-point IDs **reuse existing persisted tokens** (e.g. `googleApi`, `edge`, `wiktionaryZh`, `calculator`, `smart_summary`, `query`) | Zero migration and no backup breakage; the old value is the new ID |
| D11 | Plugin IDs use the `plugin:<pluginId>:<contributionId>` namespace; selection actions use `custom-plugin:<pluginId>:<actionId>` because of `validate()` | Matches P1 prompt/action IDs and avoids collisions with built-ins |
| D12 | Registries are split by domain (translate / tts / dictionary / aiTool / readingSkill / toolbar); each entry has a unique `id`, `owner` and `aliases` | One global table creates cross-domain coupling; per-domain registration is easier to test and permission |
| D13 | Plugins cannot override built-in IDs; duplicate registration in a domain throws and rolls back the install | Prevents malicious packages from hijacking default entry points such as translation or speech |
| D14 | P2 opens no provider-like contributions; P3 starts with `dictionarySource` | Providers without a transport are dead UI; introduce one real capability at a time |
| D15 | P3 network requests may only go through the host proxy; plugins get no `Dio` / `HttpClient` / socket | Central allowlist, quota and redaction, and the minimum-privilege boundary for a future script host |
| D16 | The allowlist contains **exact host names**, HTTPS, port 443, redirects disabled; no wildcards, IPs, userinfo or fragments | Reduces SSRF, DNS rebinding and open-redirect risk; wildcards await a concrete requirement and review |
| D17 | P3 responses support JSON with declarative path mapping only; no HTML/CSS selectors | Avoids introducing a small parsing engine in P3; HTML waits for P3.1/P4 |
| D18 | Secrets live in `pluginSecret_<id>` and are **never exported** (even with `includeSecrets=true`) and never logged | Plugin secrets should not travel with settings/backups across devices; matches the existing `isCredentialPreference` boundary |
| D19 | Per-plugin quotas: 1 concurrent, 20/minute, 300/day, 1 request per lookup; global: 4 concurrent, 60/minute | Stops one bad source from stalling every dictionary lookup or exhausting the network |
| D20 | GET only, no request body, fixed header allowlist (`Accept`, `Accept-Language`, `Authorization` for secrets) | Eliminates CSRF, arbitrary header injection and cookie leakage; sufficient for read-only dictionary lookups |
| D21 | Lookup results go to an in-memory cache only (64 entries per plugin, 10-minute TTL) and are never written to disk; query terms never enter logs | Dictionary content is licence-constrained; query terms may contain sensitive reading content |
| D22 | Read old tokens, write old tokens; only new plugin tokens use `plugin:`; no DB bump and no `pluginState` schema change | Downgradable and revertible; P2 is a refactor, not a data migration |

Additional notes:

- D10 means P2 **needs no migration script**. The only old aliases to map are `translateService`'s `microsoft` (old value) → `microsoftApi`, and TTS's retired `aliyun`/`azure` → `system`; P1 already handles both in `getTranslateService` / `Prefs.ttsService`, and P2 moves them into registry aliases.
- D11's `plugin:` prefix is not part of the manifest `id` regex; contribution `id`s still match `^[a-z0-9][a-z0-9._-]{0,62}$`. The host joins the parts so manifests cannot supply their own namespace.
- D16's "exact host name" means a DNS name, not an IP. Validate both at install time and at request time; at request time every resolved A/AAAA record must pass the private-network check.

---

## 4. P2: registries

### 4.1 Target architecture

```
                    ┌─────────────────────────────┐
                    │        RegistryCatalog      │
                    │  translate / tts / dict /   │
                    │  aiTool / skill / toolbar   │
                    └──────────────┬──────────────┘
                                   │ resolve(id)
   UI / Prefs / backup  ───────────┤
                                   │
   PluginContributions ── handler ─┘
          │
          ├─ AiPromptHandler          (P1)
          ├─ SelectionActionHandler   (P1)
          └─ DictionarySourceHandler  (P3)
```

- **Built-in entries** are registered once in `RegistryCatalog.standard()` with owner `RegistryOwner.builtIn`.
- **Plugin entries** are registered by handlers in `apply` with owner `RegistryOwner.plugin(pluginId)`; `remove` unregisters only entries whose owner matches.
- **UI and import validation** read through `resolve(id)` only; they no longer read enums or const lists directly.
- Registries are in-memory state rebuilt at startup by `PluginHost.initialize()`; the persisted `pluginState.applied` is used only for reconciliation and cleanup.

### 4.2 Registry core

Add `lib/service/registry/host_registry.dart`:

```dart
enum RegistryDomain { translate, tts, dictionary, aiTool, readingSkill, toolbar }

sealed class RegistryOwner {
  const RegistryOwner();
  const factory RegistryOwner.builtIn() = BuiltInOwner;
  const factory RegistryOwner.plugin(String pluginId) = PluginOwner;
}

class BuiltInOwner extends RegistryOwner {
  const BuiltInOwner();
  @override
  bool operator ==(Object other) => other is BuiltInOwner;
  @override
  int get hashCode => 0;
}

class PluginOwner extends RegistryOwner {
  const PluginOwner(this.pluginId);
  final String pluginId;
  @override
  bool operator ==(Object other) =>
      other is PluginOwner && other.pluginId == pluginId;
  @override
  int get hashCode => pluginId.hashCode;
}

abstract interface class RegistryEntry {
  String get id;
  RegistryDomain get domain;
  RegistryOwner get owner;
  List<String> get aliases; // old tokens, may be empty
}

class HostRegistry<T extends RegistryEntry> {
  HostRegistry(this.domain);

  final RegistryDomain domain;
  final Map<String, T> _byId = {};
  final Map<String, String> _aliases = {};
  final List<void Function()> _listeners = [];

  List<T> get all => List.unmodifiable(_byId.values);

  T? byId(String id) => _byId[id];

  /// Exact ID first, then alias; returns null when not found (callers decide
  /// the fallback policy).
  T? resolve(String id) {
    final direct = _byId[id];
    if (direct != null) return direct;
    final canonical = _aliases[id];
    return canonical == null ? null : _byId[canonical];
  }

  void register(T entry) {
    if (entry.domain != domain) {
      throw ArgumentError('Entry ' + entry.id + ' belongs to ' + entry.domain.name);
    }
    if (_byId.containsKey(entry.id)) {
      throw StateError('Duplicate ' + domain.name + ' id: ' + entry.id);
    }
    final seenAliases = <String>{};
    for (final alias in entry.aliases) {
      if (alias == entry.id || !seenAliases.add(alias)) {
        throw StateError('Invalid ' + domain.name + ' alias: ' + alias);
      }
      final existing = _byId[alias] ?? _aliases[alias];
      if (existing != null) {
        throw StateError('Duplicate ' + domain.name + ' alias: ' + alias);
      }
    }
    _byId[entry.id] = entry;
    for (final alias in entry.aliases) {
      _aliases[alias] = entry.id;
    }
    _notify();
  }

  /// Only the owner may unregister; built-in entries can never be removed by a
  /// plugin.
  bool unregister(String id, {required RegistryOwner owner}) {
    final entry = _byId[id];
    if (entry == null || entry.owner != owner) return false;
    _byId.remove(id);
    _aliases.removeWhere((_, canonical) => canonical == id);
    _notify();
    return true;
  }

  void removeAllOwnedBy(RegistryOwner owner) {
    for (final id in _byId.entries
        .where((entry) => entry.value.owner == owner)
        .map((entry) => entry.key)
        .toList()) {
      unregister(id, owner: owner);
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
```

Implementation notes:

- Do not use one generic `Map<String, dynamic>` global table; one instance per domain keeps type safety and clear error messages.
- `RegistryCatalog` owns six `HostRegistry` instances and registers built-ins during construction. Tests use `RegistryCatalog.forTesting()` to inject empty tables or substitutes.
- `RegistryEntry.aliases` exist only for old values; an alias may not equal another entry's ID.
- Registration failures must be converted from `StateError` to `PluginInstallError(duplicateContribution)` and trigger rollback of applied contributions.
- Registry changes notify the UI through listeners; do not call `Prefs.notifyListeners()` directly, which would rebuild unrelated widgets.

### 4.3 Lifecycle: add `isApplied` to handlers

P1's `PluginHost._isMaterialised` hard-codes `switch (kind)`. P2 lets each handler decide:

```dart
abstract class PluginContributionHandler {
  String get kind;
  Set<String> get requiredCapabilities;

  void validate(PluginManifest manifest, List<PluginContribution> contributions);

  Future<List<AppliedContribution>> apply(
      PluginManifest manifest, List<PluginContribution> contributions);

  Future<void> remove(List<AppliedContribution> applied);

  /// Whether the contribution still exists at runtime. Defaults to true
  /// (unknown/stateless kinds stay conservative).
  bool isApplied(AppliedContribution applied) => true;

  /// True when this kind lives only in an in-memory registry and must be
  /// rebuilt after a restart. P1 prompts/toolbar actions are false; P3
  /// dictionary sources are true.
  bool get runtimeOnly => false;
}
```

`PluginHost._reconcile` becomes:

```dart
final lost = record.applied.isEmpty ||
    record.applied.every((entry) => !_isMaterialised(entry));

bool _isMaterialised(AppliedContribution entry) {
  final handler = _contributions.registry.forKind(entry.kind);
  return handler?.isApplied(entry) ?? true;
}
```

- `AiPromptHandler.isApplied`: checks whether `userPrompts` contains the ID (keeps P1 logic).
- `SelectionActionHandler.isApplied`: checks whether `selectionToolbar.items` contains the ID (keeps P1 logic).
- A future `DictionarySourceHandler.isApplied`: checks whether the dictionary registry contains the ID with a matching owner.
- Unknown kinds still return `true`, so contributions written by a newer version are not wrongly deleted by an older one.

> This change is the crux of P2: without it, P3 provider sources would be misjudged as "materialised" after a restart while the actual registry is empty, and users would see sources disappear without automatic recovery.

P3's `DictionarySourceHandler` must declare `runtimeOnly = true`, and `apply` must be idempotent (unregister the owner's old sources first, then register the current manifest's sources). Introducing the flag in P2 does **not** change the `every` semantics of the two P1 handlers; for `runtimeOnly` kinds `PluginHost` rebuilds unconditionally on every start, so a partial loss ("some sources gone, others still present") cannot be missed. The rebuild logic can live in P3's handler/coordinator, but the interface must be frozen in P2.
### 4.4 Per-domain registries

#### 4.4.1 Translation

Current state: a `TranslateService` enum plus the `provider` switch; configuration is stored under `translateServiceConfig_<enum.name>`.

Target descriptor:

```dart
class TranslateProviderEntry implements RegistryEntry {
  const TranslateProviderEntry({
    required this.id,
    required this.factory,
    required this.label,
    required this.configPrefix,
    this.aliases = const [],
    this.supportsFullText = true,
    this.isWebView = false,
    this.description,
    this.owner = const RegistryOwner.builtIn(),
  });

  @override final String id;
  @override final List<String> aliases;
  @override final RegistryOwner owner;
  @override RegistryDomain get domain => RegistryDomain.translate;

  final TranslateServiceProvider Function() factory;
  final String Function(BuildContext) label;
  final String configPrefix; // 'translateServiceConfig_'
  final bool supportsFullText;
  final bool isWebView;
  final String? description;

  TranslateServiceProvider create() => factory();
}
```

Built-in IDs and migration (registration order matches the current `enum` order so the UI order does not change):

| ID (= old `enum.name`) | Aliases | Config key | Full-text translation | WebView |
|---|---|---|---|---|
| `microsoftFree` | — | `translateServiceConfig_microsoftFree` | yes | no |
| `bingWeb` | — | — | no | yes |
| `googleWeb` | — | — | no | yes |
| `microsoftApi` | `microsoft` | `translateServiceConfig_microsoftApi` | yes | no |
| `googleApi` | — | `translateServiceConfig_googleApi` | yes | no |
| `deepl` | — | `translateServiceConfig_deepl` | yes | no |
| `ai` | — | — | yes | no |
| `baiduWeb` | — | — | no | yes |
| `youdaoWeb` | — | — | no | yes |

Changes:

- `TranslateService.provider` no longer switches; it calls `TranslateProviderRegistry.instance.resolve(name)!.create()`. Keep the enum for one release as a UI type and delete it in P4.
- `getTranslateService(name)` resolves through the registry first, falling back to `microsoftFree` with a warning when unresolved (no exception, preserving old behaviour).
- Build the `TranslateService.values` UI list from registry order; derive `readAnyValues` / `selectionValues` / `webValues` from each entry's `supportsFullText` and `isWebView` instead of hard-coded enum sets.
- Configuration files keep building keys from `<id>`; P2 renames no keys.
- Import validation still checks object shape only for `translateServiceConfig_*`; P2 may add type checks from registry config items (optional, not blocking).

#### 4.4.2 TTS

Current state: a `TtsService` enum plus the `provider` switch; `TtsConfigTransfer.services` fixes five entries; `Prefs.ttsService` already maps `aliyun/azure → system`.

Target descriptor:

```dart
class TtsProviderEntry implements RegistryEntry {
  const TtsProviderEntry({
    required this.id,
    required this.factory,
    required this.label,
    required this.isOnline,
    this.aliases = const [],
    this.configurable = true,
    this.owner = const RegistryOwner.builtIn(),
  });

  @override final String id;
  @override final List<String> aliases;
  @override final RegistryOwner owner;
  @override RegistryDomain get domain => RegistryDomain.tts;

  final TtsServiceProvider Function() factory;
  final String Function(BuildContext) label;
  final bool isOnline;
  final bool configurable; // system has no onlineTtsConfig_
}
```

Built-in IDs: `system`, `edge`, `dashscope`, `xiaomi`, `openai`. Aliases: `aliyun` → `system`, `azure` → `system` (preserving old behaviour).

Changes:

- `TtsService.provider` resolves through the registry; keep the enum for `ttsVoiceModel_` `serviceId` compatibility.
- `TtsConfigTransfer.services` becomes `TtsProviderRegistry.instance.configurableIds`, but **export still writes the keys of the five known providers in a fixed order** so older versions can read them. On import:
  - known providers are validated under existing rules;
  - unknown providers keep their raw `config`/`voice` keys, do not participate in the current run and are not dropped; diagnostics only count them.
- The `onlineTtsConfig_` branch in `settings_value_validation.dart` becomes "registry resolves → strict validation; does not resolve → keep the object shape"; never drop silently just because a provider is unknown.
- `ttsService` still persists a string ID; the key does not change.

#### 4.4.3 AI tools

Current state: static `_definitions` in `AiToolRegistry`; `sanitizeIds` drops unknown IDs.

Target:

- `AiToolEntry` wraps the existing `AiToolDefinition`; IDs stay the same (`calculator`, `currentTime`, `mindmap`, etc.).
- Convert `definitions` / `byId` / `defaultEnabledToolIds` / `sanitizeIds` / `buildTools` into instance methods; production uses `AiToolRegistry.instance` and tests can inject.
- New semantics for `sanitizeIds`: **keep unknown IDs in storage and filter them when building tools**. That way a tool removed by a plugin or a newer version does not lose its configuration when re-enabled; the current run builds only known tools.
- Import validation for `enabledAiTools` is unchanged (string list); P2 adds no tool contribution kind, and plugins cannot register executable tools here. P4 script tools enter through a new `scriptTool` type with separate permissions.
- Compatibility: `AiToolRegistry.displayNameForId` still returns the ID itself for unknown IDs, so historical messages do not break.

#### 4.4.4 Reading skills

Current state: `const readAnySkills` + `legacyAiKnowledgeSkill`; user-defined skills are already `UserPrompt` entries merged through `ReadingSkillEntry.custom`.

Target:

- Add `ReadingSkillRegistry`; built-in IDs stay unchanged (`smart_summary`, `book_summary`, `concept_explainer`, `argument_analyzer`, `character_tracker`, `quote_collector`, `reading_guide`, `smart_translator`, `vocabulary_helper`, `mindmap`).
- `legacyAiKnowledgeSkill` only supports old prompt/history compatibility and is not registered as a visible skill; `readingSkillPromptDefinitions` keeps the union of "visible skills + retired definitions".
- `orderedReadingSkills` reads built-in skills from the registry; custom skills still come from `UserPrompt`.
- `isReadingSkillOrderId` already accepts `builtin:` / `custom:`; P2 does not change the ordering ID format.
- Plugin `aiSkill` contributions already enter the custom skill list through `UserPrompt`; P2 adds no `readingSkill` contribution kind, avoiding two prompt semantics.

#### 4.4.5 Selection toolbar

This is the riskiest part of P2 because `SelectionToolbarConfig.validate()` simultaneously constrains built-in items, the 24 custom slots, field lengths and serialisation.

Target:

- `ToolbarActionEntry` describes built-in actions: `id`, `action`, default `name/icon/prompt`, group (default/annotation/template), whether it is AI, and default enabled state.
- `defaultItems` / `defaultAnnotations` / `templateItems` are generated from the registry; IDs stay `query`, `narrate`, `custom-preset-*`, etc., and **no serialised ID changes**.
- `iconIds` / `skillIds` become registry-exported sets; plugin actions keep the `custom-plugin:` prefix and the 24-slot check in `SelectionActionHandler`.
- `validate()` becomes read-only catalog lookups:
  - built-in actions must exist in the catalog with a matching `action`;
  - custom actions still need the `custom-` prefix, non-empty name/prompt and a valid icon;
  - stop comparing static identities such as `identical(defaults, defaultItems)`; use `entry.isBuiltIn` instead.
- **Layering constraint**: `lib/models/selection_toolbar.dart` must not import `lib/service/registry` (that would create a model ↔ service cycle). Put the pure-data definition of built-in actions in `lib/models/toolbar_action_definition.dart`, wrap it with the registry, and let `SelectionToolbarConfig` access a `ToolbarCatalog` injected at startup or a static default catalog; tests can inject a substitute.
- Keep the v1 serialised shape: `items`, `annotations`, `colors`, `version` and `templateRevision` are unchanged. P2 must add golden tests for old configurations: default config, a preset the user deleted, renamed/edited prompts, plugin actions and the 24-slot boundary.
- `SelectionActionHandler.isApplied` reads the toolbar config (same as P1), but built-in/plugin ID validity is checked through the registry.

> Do not move toolbar IDs to a new namespace in P2; that would break settings backups, sync and older-version reads with zero benefit.

#### 4.4.6 Dictionary sources

Current state: the `OnlineDictionary` enum has only two values; `DictionaryPreferences` stores `local:<uuid>` / `online:<enum.name>`.

Target:

- `DictionarySourceEntry`: `id`, localised display name, `kind` (local/online/plugin), `lookup` callback, `license`, `attribution`, `isAvailable`.
- Built-in online source IDs stay `wiktionaryZh` / `wiktionaryEn`; `DictionaryPreferences` tokens stay `online:wiktionaryZh` with zero migration.
- P3 plugin source tokens are `online:plugin:<pluginId>:<sourceId>`; resolution tries built-ins first, then the plugin registry.
- Unknown tokens are **kept** in SharedPreferences but hidden from the UI; reinstalling the plugin restores the selection automatically. P2 implements resolution and preservation; P3 fills in plugin sources.
- Change `DictionaryLookup`'s `OnlineDictionary` type to `DictionarySourceEntry`; key the UI's "looking up/failed/no entry" states by string ID instead of enum. P2 must preserve the behaviour and ordering of the two built-in sources.

### 4.5 Prefs, export and import

P2 changes no key names, but does change **validation and where enumerations come from**:

| Key/prefix | P2 change | Compatibility requirement |
|---|---|---|
| `translateService` | alias resolution on read; still writes the ID | old `microsoft` value readable |
| `fullTextTranslateService` | same; WebView still falls back to `microsoftFree` | full-text translation may not select a WebView engine |
| `translateServiceConfig_*` | config items come from the registry; unknown IDs keep their object | old config not lost |
| `ttsService` | registry resolution; `aliyun/azure` → `system` | old values do not break |
| `onlineTtsConfig_*` | strict validation for known, preserved for unknown | import does not drop unknown providers |
| `ttsVoiceModel_*` | keys unchanged; keep voice for unknown providers | as above |
| `enabledAiTools` | keep unknown IDs, filter at runtime | reinstall/upgrade does not lose them |
| `readAnySkillStates` / `readAnySkillPrompts` / `readAnySkillOrder` | registry supplies built-in IDs; unknown ordering IDs preserved | old ordering not lost |
| `selectionToolbar` | registry supplies built-in actions; serialisation unchanged | old JSON readable |
| `dictionaryLookupSources` | parse tokens; preserve unknown tokens | local/online selections not lost |

`settingsModuleForKey` in `settings_modules.dart` currently detects `onlineTtsConfig_`, `translateServiceConfig_` and `pluginConfig_` by prefix. P2 keeps those branches; if the registry gains a config prefix, this function must be updated too, with a unit test asserting "every registry config prefix has an owner" so export never silently drops it.

`isCredentialPreference` stays as-is in P2; P3 adds `pluginSecret_`.

### 4.6 UI changes

- Translation settings: the engine list comes from the registry; keep the existing groups (selection translation / full-text translation) and the `readAnyValues` ordering semantics.
- Speech settings: the service picker comes from the registry; the config form is still generated by `TtsServiceProvider.getConfigItems`.
- Dictionary settings: built-in online sources come from the registry; P3 adds a "plugin sources" group and a network badge.
- AI settings: the tool list comes from the registry; unknown saved IDs are hidden but not deleted.
- Plugin details: P2 adds a "registered runtime items" section listing the providers/dictionary sources/tools the plugin registered (in P2 this is only P1 prompts/actions), hidden when empty.
- No new ARB keys; new copy uses `ModuStrings.text`.

### 4.7 P2 tests

| Layer | File (new/modified) | Coverage |
|---|---|---|
| Registry core | `test/service/registry/host_registry_test.dart` | register, duplicate IDs, alias conflicts, owner unregister, built-ins undeletable, listener notification |
| AI tools | `test/service/ai/tools/ai_tool_registry_test.dart` | built-in IDs unchanged, unknown IDs preserved, build filtering, ordering |
| Reading skills | `test/service/ai/reading_skill_registry_test.dart` | built-in list, retired definitions, ordering merge, unknown IDs preserved |
| Translation | `test/service/translate/translate_registry_test.dart` | 9 IDs, `microsoft` alias, WebView/full-text filtering, reading old config |
| TTS | `test/service/tts/tts_registry_test.dart`, `test/service/config_transfer/tts_config_transfer_test.dart` | 5 IDs, `aliyun/azure`, unknown provider preserved, backup round trip |
| Dictionary | `test/service/dictionary/dictionary_preferences_test.dart` | old tokens, unknown token preserved, `local:*` compatibility |
| Toolbar | `test/models/selection_toolbar_test.dart`, `test/widgets/selection_toolbar_test.dart` | old JSON golden, default/deleted/edited/plugin actions, 24 slots |
| Plugin lifecycle | `test/service/plugins/plugin_host_test.dart` | `isApplied` restart reconciliation, P1 behaviour unchanged, unknown kinds conservative |
| Import | `test/service/config_transfer/settings_transfer_registry_test.dart` | every registry prefix has an owner, unknown providers not lost, invalid IDs rejected |

P2 manual acceptance:

1. Generate a settings backup with the P1 build (including plugins, translation, TTS, AI tools, skill ordering and toolbar), import it into the P2 build, and compare every selection and order.
2. Install the P1 sample plugin and confirm prompts/toolbar actions behave the same across restart, disable, uninstall and upgrade.
3. Set `translateService` to `microsoft` and `ttsService` to `aliyun`; after a restart they resolve to `microsoftApi` / `system` without crashing.
4. Inject a fake provider in a registry test, confirm the UI shows it, configuration saves and export keeps it; the test must not pollute global state.
5. On each of the 6 platforms, run install/enable/disable/uninstall and open the settings page once.

### 4.8 P2 PR split and rollback

| PR | Content | Independent rollback |
|---|---|---|
| **P2a** | `HostRegistry` / `RegistryCatalog`, AI tools, reading skills, `isApplied` interface (only the two P1 handlers change at first) | Delete the registries and restore static tables; no data change |
| **P2b** | Translation, TTS, config import/export changes | Restore enum switches and the fixed services list; settings keys unchanged |
| **P2c** | Dictionary, toolbar, plugin-details runtime section, full regression | Restore the enum and static toolbar lists; plugin data unchanged |

Rollback principle: P2 writes no new keys, changes no old keys and does not bump the DB, so rollback only reverts code; user settings need no recovery script. The only cleanup needed is test-injected global registries; production code must never write test entries to prefs.

---

## 5. P3: declarative network plugins

### 5.1 Scope and threat model

P3 v1 allows exactly one network use: **dictionary lookup**. Lifecycle of one lookup:

```
user selects a word → DictionaryLookup
  → read DictionaryPreferences (local + built-in online + plugin sources)
  → for each plugin source call PluginDictionarySource.lookup(word)
      → NetworkGuard validates URL/host/port/resolved address
      → HostHttpClient sends GET (budget, timeout, cancellation)
      → read and limit the response body
      → JsonMapping parses it into DictionaryEntry
  → render alongside local/built-in results (plain text)
```

Threat model:

| Asset | Threat | Mitigation |
|---|---|---|
| User query term | Sent by a plugin to arbitrary hosts, written to logs | Domain allowlist; never log terms; GET only against declared templates |
| Local network | SSRF to `127.0.0.1`, LAN, cloud metadata | Block IPs/local names; post-resolution private-network check; no redirects |
| Plugin secret | Leaked via settings export/backup | `pluginSecret_` never exported; errors/logs redacted |
| App stability | Endless responses, slow requests, concurrency exhaustion | 1 MiB, 8 s, concurrency/rate/daily quotas, cancellation |
| Content licence | Scraping copyrighted content, losing attribution | Required license/attribution/sourceUrl; shown in UI; never written to disk |
| Ecosystem trust | Plugin impersonating/overriding a built-in source | ID namespace; built-ins immutable; install page shows domains |

### 5.2 Capability and install authorisation

New capability constants:

```dart
const String kNetHttpCapability = 'net:http';
const String kDictionarySourceContributionKind = 'dictionarySource';
```

- P3's `kSupportedCapabilities = {..., 'net:http'}`; `script:run` and `library:read` are still rejected.
- Only packages declaring `net:http` may contain `dictionarySource`; conversely, a package with `dictionarySource` but no `net:http` is rejected during manifest validation (`capabilityUnavailable` or `invalidContribution`; pick one during implementation and test it).
- The install page must show:
  - the exact domains that will be contacted;
  - "query terms will be sent to these domains";
  - quotas and "HTTPS only";
  - the licence and attribution supplied by the plugin.
- `pluginState` is written only after the user confirms; P1's install flow already has a confirmation step, and P3 only extends what it displays rather than adding a second authorisation state.
- Reinstalling the same plugin ID with a changed domain list must show and confirm again; an unchanged list may reuse the installed record but is still displayed.

### 5.3 manifest v1 shape (P3)

Add a top-level `network` object, a `dictionarySource` contribution and a `secret` setting type to the P1 manifest.

```json
{
  "schemaVersion": 1,
  "id": "com.example.dictionary",
  "version": "1.0.0",
  "name": { "zh-CN": "示例词典", "en": "Example dictionary" },
  "description": { "zh-CN": "通过公开 JSON API 查询示例词条。", "en": "Looks up entries from a public JSON API." },
  "author": { "name": "Example", "url": "https://example.com" },
  "license": "MIT",
  "minAppVersion": "1.4.0",
  "capabilities": ["net:http"],
  "network": {
    "domains": ["api.example.com"],
    "timeoutMs": 8000,
    "maxResponseBytes": 1048576,
    "requestsPerLookup": 1
  },
  "settings": [
    {
      "key": "lang",
      "type": "select",
      "label": { "zh-CN": "词典语言", "en": "Dictionary language" },
      "options": ["en", "zh"],
      "defaultValue": "en"
    },
    {
      "key": "api_key",
      "type": "secret",
      "label": { "zh-CN": "API 密钥（可选）", "en": "API key (optional)" },
      "required": false
    }
  ],
  "contributes": [
    {
      "kind": "dictionarySource",
      "schema": 1,
      "id": "example-en",
      "name": { "zh-CN": "示例词典 · 英文", "en": "Example Dictionary · English" },
      "request": {
        "method": "GET",
        "url": "https://api.example.com/v1/lookup",
        "query": {
          "q": "{word}",
          "lang": "{setting.lang}"
        },
        "headers": {
          "Accept": "application/json",
          "Authorization": "Bearer {secret.api_key}"
        }
      },
      "response": {
        "format": "json",
        "root": "data.entries[*]",
        "fields": {
          "word": "headword",
          "definition": "senses[*].definition",
          "partOfSpeech": "senses[*].partOfSpeech",
          "sourceUrl": "source.url",
          "license": "source.license",
          "attribution": "source.attribution"
        },
        "maxEntries": 5,
        "maxDefinitionChars": 4000
      },
      "license": "CC-BY-4.0",
      "licenseUri": "https://creativecommons.org/licenses/by/4.0/",
      "attribution": "Example Dictionary contributors",
      "sourceUrl": "https://example.com/dictionary"
    }
  ],
  "hostApi": 1
}
```

Field rules:

| Field | Rule |
|---|---|
| `network.domains` | 1–8; exact DNS names, lowercase, max 253 chars; no IPs, localhost, `.local` or `.internal`; no wildcards |
| `network.timeoutMs` | 1000–15000, default 8000 |
| `network.maxResponseBytes` | 4096–1048576, default 1048576; may not exceed the global limit |
| `network.requestsPerLookup` | fixed at 1 (P3 v1); any other value is rejected |
| `request.method` | `GET` only |
| `request.url` | HTTPS, no userinfo, no fragment, port 443; the host must be in `network.domains` |
| `request.query` | 1–16 keys, values 1–256 chars; only `{word}` and `{setting.<key>}` placeholders; secrets not allowed |
| `request.headers` | only `Accept`, `Accept-Language` and `Authorization`; `Authorization` may reference only a secret |
| `settings[].type = secret` | allowed only in `net:http` packages; the key still matches `settingKeyPattern`; optional `required` (bool, default false); no `defaultValue` |
| `response.format` | `json` only |
| `response.root` | optional; JSON path subset; defaults to the root |
| `response.fields` | must contain `definition`; may contain `word`, `partOfSpeech`, `sourceUrl`, `license`, `attribution`, `licenseUri` |
| `response.maxEntries` | 1–20, default 5 |
| `response.maxDefinitionChars` | 100–20000, default 4000 |
| contribution `license`/`attribution` | required; `licenseUri`/`sourceUrl` optional but must be https |

Structural limits carry over from P1: ≤ 40 contributions, ≤ 40 settings, manifest ≤ 64 KB, package ≤ 5 MB / 20 MB. P3 adds a limit of ≤ 8 `dictionarySource` entries per plugin.

### 5.4 Request model

**GET only.** The host builds the request; plugins cannot supply a full header set or a body.

Template syntax:

- `{word}`: the term typed in the dictionary lookup box, trimmed first, length 1–256. Use `Uri.encodeQueryComponent` when placing it in the query and `Uri.encodeComponent` when placing it in the path.
- `{setting.<key>}`: a scalar from `PluginConfig` after defaults are merged; only text/number/toggle/select, never secrets; the value is encoded as a string.
- `{secret.<key>}`: allowed only inside header values; reads `pluginSecret_<id>`. When unset:
  - if the setting has `required=true`, the lookup fails with "a key is required";
  - otherwise omit the whole header (never send an empty `Bearer `).
- Reject every other `{...}`; no recursive expansion; templates are at most 1024 chars.
- URL-encode both query keys and values; do not hard-code `?` or `#` in templates; `request.url` may contain only a path and no query (queries must go through `request.query`).

Header rules:

- `Accept` defaults to `application/json` and may be overridden by the manifest to `application/json` or `application/*+json`.
- `Accept-Language` is fixed by the manifest only; it accepts no user input.
- `Authorization` may only be `Bearer {secret.<key>}` or `{secret.<key>}`; no other text may be concatenated, preventing header injection.
- The host force-overrides `User-Agent`, `Host`, `Content-Length` and `Connection`; a manifest specifying these is rejected outright.
- `Cookie`, `Referer`, `Origin` and `X-Forwarded-*` are not allowed.

### 5.5 Response model (JSON path subset)

Syntax:

```
path      := segment (('.' segment) | ('[' (index | '*') ']'))*
segment   := [A-Za-z_][A-Za-z0-9_-]{0,63}
index     := 0..999
```

Example: `data.entries[*].senses[*].definition`.

Evaluation rules:

- Start from `response.root`; a missing `root` means the whole JSON document.
- `segment` reads only object keys; a missing key yields empty.
- `[n]` reads only array element n; out-of-range yields empty.
- `[*]` expands an array; the remaining path is evaluated for each element and flattened.
- Final values may be strings, numbers, booleans, string arrays or number arrays; other types are stringified or dropped.
- Join multiple `definition` values with `\n`; drop empty strings; truncate past `maxDefinitionChars` and append an ellipsis.
- `sourceUrl` / `licenseUri` must be https URLs, otherwise drop that field (do not fail the whole result).
- Every entry must have a non-empty `definition`; entries without one are skipped; if everything is empty return "no entry found".
- Do not execute expressions, functions, filters or recursive descent; the parser is pure data traversal and must not call `eval`.

Safety limits:

- Read the body up to the byte limit first, then decode UTF-8; reject invalid UTF-8.
- After JSON parsing enforce depth ≤ 32, nodes ≤ 100000 and total string length ≤ 2 MB; reject beyond that.
- Truncate to `response.maxEntries`; truncate each definition; never render remote HTML as HTML — the UI uses `SelectableText` only.
- Strip control characters from content (except `\n` and `\t`).

### 5.6 Network guard

Add `lib/service/network/plugin_network_guard.dart`:

1. **URL validation**: `Uri.tryParse`; scheme must be `https`; no userinfo, no fragment; port empty or 443; non-empty host.
2. **Host normalisation**: lowercase, strip trailing dots (but reject user input that includes one), convert IDN to punycode; compare exactly with `network.domains`. Reject:
   - IP literals (IPv4/IPv6/decimal/octal/hex);
   - `localhost`, `*.localhost`, `.local`, `.internal`, `.home.arpa`;
   - values containing `@`, `%`, spaces, backslashes or control characters;
   - any port other than 443.
3. **DNS resolution**: resolve all A/AAAA records; if any address is loopback, private, link-local, multicast, unspecified, broadcast or an IPv4-mapped private IPv6 range, reject the whole request. Use the same resolution result for the connection to prevent DNS rebinding; re-check the remote address after connecting.
4. **Redirects**: `followRedirects = false`; any 3xx fails, and `Location` is never read.
5. **Proxy**: respect the app's existing `httpProxyEnabled` setting; the domain allowlist is still enforced at the URL layer. The proxy server is treated as an exit the user trusts, and the documentation must state this. Forbidding plugins from using the proxy would require a separate review.
6. **TLS**: certificate validation cannot be disabled; no custom `badCertificateCallback`; plugin certificates are not imported.
7. **Connection**: 5 s connect timeout, total timeout from `network.timeoutMs`; use a dedicated `Dio` instance or `HttpClient` rather than reusing the AI/sync client; read the response stream up to `maxResponseBytes + 1` and cancel immediately when exceeded.

Implementation advice: do not use the default redirect handling or automatic JSON decoding of `Dio().get`; use `ResponseType.stream` and count, decode and parse manually. Dio interceptors handle only log redaction and budget counting, never security decisions.

### 5.7 Quotas, cache and cancellation

| Dimension | Limit | Behaviour when exceeded |
|---|---|---|
| Per-plugin concurrency | 1 | New requests queue; queue timeout of 2 s fails the request |
| Per-plugin rate | 20/minute (sliding window) | Return `rateLimited`; no automatic retry |
| Per-plugin daily | 300 | Return `dailyLimit`; resets at local midnight |
| Global concurrency | 4 | Queue; fail when the queue is full |
| Global rate | 60/minute | Return `rateLimited` |
| Requests per lookup | 1 | Manifest validation rejects other values |
| Timeout | `network.timeoutMs` (≤ 15 s) | Cancel the request and return `timeout` |
| Response body | `maxResponseBytes` (≤ 1 MiB) | Cancel and return `responseTooLarge` |
| Cache | 64 entries per plugin, 10-minute TTL, memory only | Never written to disk or synced across devices |
| Cancellation | Page closes / word changes | `CancelToken.cancel()`, not recorded as a failure |

- Counters are held in memory per plugin ID and reset when the app restarts. P3 writes no prefs, avoiding frequent I/O and backup pollution.
- Failure classes: `configuration`, `network`, `timeout`, `rateLimited`, `dailyLimit`, `invalidResponse`, `license`, `disabled`. The UI shows readable copy only, never full URLs or responses.
- Do not retry 4xx/5xx automatically; 429/503 may surface `Retry-After` as a UI hint, but still without automatic retry.

### 5.8 Secrets and privacy

Add `PluginSettingType.secret` and `pluginSecret_<id>`:

```dart
const String pluginSecretPrefix = 'pluginSecret_';

Future<void> savePluginSecret(String id, String key, String value);
Future<void> removePluginSecret(String id, String key);
Map<String, String> pluginSecrets(String id); // readable only by the host network layer
```

Rules:

- Secret values live only in SharedPreferences: **never logged, never in `pluginConfig_`, never in settings export, never in database backups, never in WebDAV sync**.
- The details page shows only "configured / not configured" with no echo-back; users may clear or replace a secret.
- `PluginConfig.validate` always rejects secret keys (secrets are not ordinary configuration objects).
- `backup_safety.isCredentialPreference` adds `pluginSecret_`; even `includeSecrets=true` must not export them (a deliberate hard constraint, consistent with "plugin secrets stay on the device").
- Error messages, diagnostics and `lastError` must not contain header values, query terms or full URLs; only plugin IDs, error codes, domains and status codes are allowed.
- The export confirmation page adds: "Plugin keys are not exported with settings or backups; configure them again on each device."
- State the security boundary clearly: P3 introduces no platform Keychain/Keystore, so secrets remain plaintext in SharedPreferences. This phase guarantees only "no leakage through export/backup/logs" and **cannot** defend against rooted/jailbroken or physically controlled devices. If stronger protection is needed later, evaluate a secure-storage abstraction in P4/P5; do not pretend it is encrypted now.

### 5.9 Dictionary materialisation and UI

`DictionarySourceHandler` responsibilities:

- `validate`: check the manifest `network`, `request`, `response`, license/attribution, domains and setting references; any failure rejects the whole install before writing.
- `apply`: create a `PluginDictionarySource` for each `dictionarySource` and register it in `DictionarySourceRegistry` under `plugin:<pluginId>:<sourceId>`. Return `AppliedContribution(kind: 'dictionarySource', id: ...)`.
- `remove`: unregister by ID; P3 does not allow editing plugin source names (avoiding hash complexity), so unregister directly; configuration and secrets persist until uninstall.
- `isApplied`: the registry contains the ID and the owner matches.
- Failure isolation: one source failing to register does not affect the plugin's other sources; a failure during install still rolls back the whole install (matching P1).

UI:

- The dictionary source picker has three groups: "Local dictionaries", "Built-in online dictionaries" and "Plugin dictionaries".
- Plugin sources show their name, a network badge and licence/attribution links; the first time one is enabled, warn "query terms will be sent to `api.example.com`".
- Looking up/failed/no-entry states are shown per source ID; one failing plugin source does not affect the others.
- Plugin details add a "Network" section: domains, quotas and the last error code; never query terms or responses.
- Disabling/uninstalling a plugin removes its sources from the UI; tokens in `dictionaryLookupSources` are kept and the selection is restored after reinstall.
- When a plugin is missing (settings restored only), sources are hidden without errors; the settings page notes "plugin files must be reinstalled".

### 5.10 Backup, export and migration

- `pluginState` and `pluginConfig_<id>` enter settings export as usual; `pluginSecret_<id>` never does.
- Plugin packages do not enter backups; after restoring on another device a plugin is `missing` and its sources are unavailable; reinstalling restores them.
- `dictionaryLookupSources` is a device-local setting; P3 does not change its current "not exported with settings" behaviour. Exporting source selections later requires a separate review of token compatibility and missing-plugin semantics.
- On import:
  - `pluginState` is parsed strictly;
  - `pluginConfig_*` is validated against the manifest, preserving unknown keys;
  - `pluginSecret_*` is ignored/stripped even if it appears in a backup (preventing injection from older versions or hand-crafted backups).
- P3 adds no database migration; `currentDbVersion` stays at 11.

### 5.11 Licence and attribution

- `dictionarySource` must declare an SPDX `license` and `attribution`; providing `licenseUri` and `sourceUrl` is recommended.
- The UI shows source and licence; `DictionaryEntry` already has `license`, `licenseUri`, `attribution` and `sourceUri` fields, which are reused directly.
- No disk cache, no bulk scraping and no full-text indexing; only user-initiated lookups are served.
- Plugin authors must document data sources and licences in their README; the sample plugin uses a public test API or a static JSON service inside the repository (tests only).

### 5.12 Implementation structure

New/modified files:

| File | Content |
|---|---|
| `lib/models/plugin_network.dart` | `PluginNetworkPolicy`, `PluginHttpRequestSpec`, `PluginJsonResponseSpec` with strict `fromJson` |
| `lib/models/plugin_manifest.dart` | parse `network`; add `DictionarySourceContribution`; secret setting type; P3 capability set |
| `lib/service/network/plugin_network_guard.dart` | URL/host/port/private-network/redirect validation |
| `lib/service/network/plugin_http_client.dart` | budget, timeout, response limit, cancellation, redacted logs |
| `lib/service/network/plugin_json_path.dart` | JSON path subset parsing and limits |
| `lib/service/plugins/handlers/dictionary_source_handler.dart` | validate/apply/remove/isApplied |
| `lib/service/dictionary/plugin_dictionary_source.dart` | plugin implementation of `DictionarySourceEntry`, calling the network and mapping |
| `lib/service/dictionary/dictionary_source_registry.dart` | built-in + plugin source registry |
| `lib/service/plugins/plugin_secrets.dart` | `pluginSecret_<id>` read/write/clear |
| `lib/config/shared_preference_provider.dart` | secret methods; not exposed to the ordinary settings UI |
| `lib/service/local_data/backup_safety.dart` | classify `pluginSecret_` as a credential |
| `lib/service/config_transfer/settings_value_validation.dart` | reject secrets in `pluginConfig_`; strip `pluginSecret_` on import |
| `lib/widgets/dictionary/dictionary_sources.dart` | plugin source group, network warnings |
| `lib/widgets/dictionary/dictionary_lookup.dart` | source IDs, plugin source states |
| `lib/page/settings_page/plugins/plugin_detail_page.dart` | network permissions, domains, quotas, diagnostics |

Implementation order (each step compiles and is testable):

1. `plugin_network.dart` + manifest parsing + rejection cases.
2. `plugin_json_path.dart` + unit tests (no network).
3. `plugin_network_guard.dart` + unit tests (inject a DNS resolver).
4. `plugin_http_client.dart` + budget/timeout/size/cancellation tests (local HTTP server or mock adapter).
5. `plugin_secrets.dart` + export/backup exclusion tests.
6. `dictionary_source_handler.dart` + registry + dictionary UI.
7. Sample plugin and end-to-end tests.

### 5.13 P3 test matrix

| Layer | Coverage |
|---|---|
| manifest | valid source, missing license/attribution, missing network, too many domains, wildcard, IP, userinfo, non-443, http, POST, body, illegal header, illegal template, illegal JSON path, secret not declared, source without net:http |
| URL/host | case, trailing dot, IDN, unicode homoglyph, `api.example.com.evil.com`, `evil.com@api.example.com`, `%40`, backslash, IPv4/decimal/IPv6, localhost, `.local`, private ranges |
| DNS | resolves to 127.0.0.1, 10.x, 192.168.x, 169.254.x, ::1, fc00::/7, fe80::/10; DNS rebinding (public first, private second) |
| HTTP | 200 JSON, 404, 500, 429, 301/302/307 redirects, missing Content-Type, `text/html`, gzip bomb, over 1 MiB, invalid UTF-8, slow response, connection reset |
| parsing | object/array roots, `[*]`, multi-value definition, missing fields, numbers/booleans, invalid URL fields, excessive depth/nodes, control characters |
| quotas | per-plugin 1 concurrent, 20/min, 300/day, global 4 concurrent, queue timeout, cancellation not counted |
| secrets | required-but-unset fails, optional omits the header, absent from export/backup/logs/errors, invalid after clearing |
| lifecycle | install, disable, enable, uninstall, upgrade, restart, missing, broken, source selection preserved, domain changes re-confirmed |
| UI | three source groups, network warning, per-source failure isolation, licence/attribution, empty state without plugin sources |
| export | `pluginState`/`pluginConfig_` round trip; `pluginSecret_` stripped; `dictionaryLookupSources` not exported; malicious backup rejected |

P3 manual acceptance:

1. Install the sample dictionary plugin on all 6 platforms, look up a word and confirm plain-text-only results with visible source/licence.
2. Disconnect the network: local dictionaries still work, plugin sources show a readable failure and nothing crashes.
3. Change a domain to one outside the allowlist and confirm install/request rejection; set a redirect target to another domain and confirm it is not followed.
4. Trigger the rate limit with rapid lookups, confirm recovery after stopping, and confirm closing the page cancels the request.
5. Export settings (with and without secrets) and confirm secrets are absent from the file; after restoring on another device the plugin is missing and reinstalling restores configuration.
6. Uninstall the plugin and confirm sources disappear, configuration is cleared and the saved dictionary token does not affect other sources.

### 5.14 P3 PR split and rollback

| PR | Content | Acceptance |
|---|---|---|
| **P3a** | manifest/`network`/`dictionarySource` models + strict validation + malicious-package tests | rejects illegal packages fully even without network code |
| **P3b** | network guard + HTTP client + JSON path + quotas/cache/cancellation | local mock server green; no real Internet dependency |
| **P3c** | secret storage + export/backup exclusion + handler + dictionary registry/UI | end-to-end lookup; secrets do not leak |
| **P3d** | sample plugin, documentation, 6-platform acceptance, performance and error copy | every DoD item |

Rollback:

- Remove `net:http` from the supported set and every network plugin fails to install; contributions of installed plugins are removed during startup reconciliation, while configuration/secrets are kept.
- Finer rollback: remove only the `DictionarySourceHandler` registration; the P2 registries and other plugins are unaffected.
- Do not roll back by hiding UI; rejection must happen at the capability/install layer, avoiding "installs but does not work".

---

## 6. File-level change list

### 6.1 P2 additions

| File | Content |
|---|---|
| `lib/service/registry/host_registry.dart` | `HostRegistry`, `RegistryEntry`, `RegistryOwner`, `RegistryDomain` |
| `lib/service/registry/registry_catalog.dart` | six domain instances and the built-in registration entry point |
| `lib/service/translate/translate_provider_registry.dart` | translation descriptors and built-in registrations |
| `lib/service/tts/tts_provider_registry.dart` | TTS descriptors and built-in registrations |
| `lib/service/ai/reading_skill_registry.dart` | reading skill descriptors and built-in registrations |
| `lib/service/dictionary/dictionary_source_registry.dart` | dictionary source descriptors (built-ins only in P2; plugin sources in P3) |
| `lib/models/toolbar_action_definition.dart` | descriptor for built-in toolbar actions |
| Corresponding tests | see §4.7 |

### 6.2 P2 modifications

| File | Change |
|---|---|
| `lib/service/translate/index.dart` | remove the `provider` switch; keep the enum as a UI adapter; filter lists through the registry |
| `lib/service/tts/tts_service.dart` | remove the `provider` switch; `getTtsService` goes through the registry |
| `lib/service/tts/tts_service_provider.dart` | minimal interface needed by descriptor adaptation (if required) |
| `lib/service/dictionary/online_dictionary.dart` | enum becomes descriptors; entries provide host/URI |
| `lib/service/dictionary/dictionary_preferences.dart` | token resolution, preserving unknown tokens |
| `lib/service/ai/tools/ai_tool_registry.dart` | instantiate; keep unknown IDs, filter at build time |
| `lib/service/ai/readany_skills.dart` | list comes from the registry; keep retired definitions |
| `lib/service/ai/reading_skill_layout.dart` | read built-in skills from the registry |
| `lib/models/selection_toolbar.dart` | static tables generated from the registry; `validate()` queries the registry; serialisation unchanged |
| `lib/service/plugins/plugin_contribution_handler.dart` | add `isApplied` |
| `lib/service/plugins/plugin_host.dart` | `_isMaterialised` delegates to handlers |
| `lib/service/plugins/handlers/ai_prompt_handler.dart` / `selection_action_handler.dart` | implement `isApplied` |
| `lib/service/config_transfer/tts_config_transfer.dart` | services from the registry; preserve unknown providers |
| `lib/service/config_transfer/settings_modules.dart` | test coverage for config-prefix owners |
| `lib/service/config_transfer/settings_value_validation.dart` | registry-driven provider validation |
| Settings pages | translation/speech/dictionary/AI/plugin details read from the registries |

### 6.3 P3 additions/modifications

See §5.12. P3 must not modify the database, sync protocol, TTS playback pipeline, AI provider configuration or the P1 package format (beyond the new optional fields).

---

## 7. Test matrix summary

| Phase | Must test |
|---|---|
| P2 | zero loss of old settings; six registries; old toolbar JSON; P1 plugin lifecycle; importing unknown providers; manual checks on 6 platforms |
| P3 | malicious manifests; SSRF/redirect/DNS; quotas/cancellation; secrets not leaking; dictionary UI; backup stripping; manual checks on 6 platforms |

Use the same CI command order as P1 §16.1:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Prefer pure-Dart tests without real Internet access; use a local `HttpServer` or injected `DioAdapter` for network tests and an injected resolver for DNS.

---

## 8. Timeline and acceptance

| Week | Content | Output |
|---|---|---|
| W1 | P2a registry core + AI tools/skills | PR P2a + unit tests |
| W2 | P2b translation/TTS + migration | PR P2b + settings round-trip tests |
| W3 | P2c dictionary/toolbar + regression | PR P2c + 6-platform baseline |
| W4–W5 | P3a/P3b models and network guard | PR P3a/P3b + security tests |
| W6 | P3c handler/secrets/UI | PR P3c + end to end |
| W7 | P3d sample/docs/acceptance | PR P3d + DoD record |

P2 exit criteria: zero loss of old settings, unchanged P1 behaviour, injectable registries, and settings pages open without errors on all 6 platforms.
P3 exit criteria: malicious packages all rejected, allowlist/quota/secret tests green, real lookups on 6 platforms, reproducible docs and sample.

---

## 9. Risk register

| Risk | Phase | Impact | Mitigation |
|---|---|---|---|
| Changes to toolbar `validate()` make old configs invalid | P2c | user toolbar lost | golden tests + read-before-write; keep old IDs; do not change serialisation |
| A global registry singleton pollutes tests | P2a | test cross-talk | instance injection; empty `forTesting` tables; clean up in tearDown |
| Unknown providers dropped by import logic | P2b | cross-device config loss | explicitly preserve unknown keys; test coverage |
| `isApplied` defaults wrongly delete new contributions | P2 | contributions disappear after upgrade | unknown kinds return true; only judge known handlers |
| Domain validation bypassed via userinfo/IDN/trailing dot | P3 | SSRF | normalisation + exact comparison + test corpus |
| DNS rebinding | P3 | private-network access | validate resolved result + re-check after connecting |
| Oversized responses/compression bombs | P3 | OOM | stream counting, decompressed limit, JSON node limits |
| Secrets in backups/logs | P3 | credential leak | separate key, strip on export, log allowlist, tests |
| Plugin sources slow down lookups | P3 | UI stalls | 1 concurrent/source, timeout, cancellation, failure isolation |
| Missing licence/attribution | P3 | compliance risk | required fields in manifest, shown in UI, install rejected |

Overall rollback principle: P2 reverts code only; P3 first removes the capability/handler registration, then reverts the UI; installed plugin data is retained with no destructive migration.

---

## 10. Handover runbook

### 10.1 Suggested reading order

1. §3 (decisions) and §0.3 (differences from P0) of this document.
2. §3–§6 of the P1 document (package spec, contribution materialisation, hash guard).
3. `lib/service/plugins/plugin_host.dart`, `plugin_contribution_handler.dart`, `plugin_contributions.dart`.
4. P2 domain code: `translate/index.dart`, `tts/tts_service.dart`, `dictionary/online_dictionary.dart`, `ai/tools/ai_tool_registry.dart`, `models/selection_toolbar.dart`.
5. P3 prerequisites: `network/http_proxy_overrides.dart`, `backup_safety.dart`, `settings_value_validation.dart`.

### 10.2 Glossary

| Term | Meaning |
|---|---|
| registry | per-domain ID → descriptor table replacing enum switches and static const lists |
| entry / descriptor | metadata and factory for one provider/tool/skill/action |
| owner | entry ownership: built-in or a specific plugin |
| alias | mapping from an old persisted token to a new ID; P2 uses it for compatibility only |
| `plugin:` | namespace for plugin contribution IDs; the toolbar uses `custom-plugin:` |
| `net:http` | P3 capability token allowing host-proxied HTTP |
| `dictionarySource` | P3 declarative dictionary source contribution |
| `pluginSecret_` | device-local plugin secret, never exported |
| NetworkGuard | central validation of URL, host, DNS, port and redirects |

### 10.3 Known pitfalls

- Do not add a "migration script" to P2: D10 deliberately makes old tokens the new IDs; a migration would create dual writes and rollback risk.
- Do not change `SelectionToolbarConfig`'s serialised fields or the `custom-` prefix rules; P1 plugin actions depend on them.
- Do not write another `switch (kind)` in `PluginHost`; P2 reconciliation must go through handlers.
- Do not reuse `pluginConfig_` for secrets; P3 secrets need separate keys.
- Do not handle plugin responses with `Dio`'s default redirects or automatic JSON decoding; stream with limits and parse manually.
- Do not put query terms into logs or error copy; dictionary lookups may contain sensitive reading content.
- Do not let plugins override built-in IDs; registry conflicts must fail at install time, not overwrite at runtime.
- Do not assume OHOS network behaviour matches Android exactly; P3 needs real-device validation of proxy, TLS and timeouts on OHOS.

### 10.4 Open questions

1. Should P3's `dictionarySource` support JSON only, or also a minimal HTML text extraction in v1? This document defaults to JSON-only.
2. Should plugin secrets be exported when `includeSecrets=true`? This document defaults to **never export**; if maintainers want exportable secrets, that needs a separate security review and a second UI confirmation.
3. May a plugin declare multiple domains for one API (primary/backup)? This document allows 1–8 but permits exactly one host per request and no runtime switching.
4. Should the P2 registry show "runtime registered items" on the plugin details page? This document recommends it, but it can remain an optional P2c UI.
5. Should P3.1 translation/TTS plugins reuse the same `PluginHttpClient`? This document recommends reuse, but TTS audio responses and streaming playback need a separate review.

---

## 11. Interface contracts with P0/P1 and P4

| Interface | P2/P3 guarantee | P4 use |
|---|---|---|
| `PluginContributionHandler` | adds `isApplied`; validate/apply/remove unchanged | script contributions use the same lifecycle |
| `AppliedContribution` | shape unchanged; kind/id/hash | script contributions record entry/hash |
| `HostRegistry` | plugin entries are unregisterable by owner; built-ins immutable | script-registered tools/translators use the same registries |
| `PluginConfig` | ordinary config exportable; secrets separate | script settings reuse it |
| `net:http` | P3 exposes declarative dictionaries only | P4 script networking still goes through the host proxy, never a raw socket |
| `dictionarySource` | P3's declarative source | P4 script sources may supplement but not replace the allowlist |

The P4 script runtime must not bypass the P3 network guard; if scripts need network access the capability remains `net:http` and requests are still constructed/audited by the host proxy. P3's quotas and log redaction are P4 infrastructure, not one-off code.

---

## 12. Document maintenance

- This document is a design draft; after implementation, change each "recommended/default" into "implemented" and add the actual test counts and 6-platform acceptance record.
- If P2/P3 implementation deviates from D10–D22, add a "decision change" section here explaining the reason, impact and rollback; silent changes are not allowed.
- For changes that affect user-visible behaviour, update `docs/SETTINGS.md` / `docs/SETTINGS_zh.md`, `docs/LOCAL_DICTIONARIES.md` and the `docs/README.md` index.
- Document language: this design guide is maintained in English, as required by `CONTRIBUTING.md` ("singleton guides use English"). The P1 execution document is still a Chinese working draft and should be translated separately; keep both entries in the existing style in the documentation index.
