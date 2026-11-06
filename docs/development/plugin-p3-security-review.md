# P3 network plugin security review / P3 网络插件安全评审

Status: **design review; not approval to enable networking** · 2026-11-06.
PR #72 contains manifest validation and standalone transport helpers. It does
not contain the dictionary host integration, consent flow or secret storage.
`PluginHost` rejects `net:http` during preview, installation, enablement and
startup reconciliation. Script execution and signature-based trust are not
implemented here; the existing package catalog still governs trust.

Before the network capability is enabled, complete and test the end-to-end
pipeline, including bounded DNS/cancellation, transition-address policy,
secret isolation and real-device TLS behavior. The threats and proposed
controls below remain a design checklist, not a claim of completed coverage.

---

## 1. Deciding question: is the marginal risk acceptable?

P1/P2 plugins are **inert data**. They add prompts, toolbar actions and
settings; the host decides what those mean and no package can make the app
contact anything. P3 changes that: a package can now cause the app to send the
user's typed words to a host of the package author's choosing.

That is a real capability increase, so the review states the trade plainly:

| | Before P3 | After P3 |
|---|---|---|
| Worst case if a package is malicious | a bad prompt the user can delete | the user's lookup terms are sent to an author-chosen host |
| Who chooses the destination | app code, reviewed | package manifest, reviewed but per-package |
| Data leaving the device | only when the user invokes an AI action | every lookup through that source |
| Blast radius | one app feature | every word the user looks up |

The mitigation strategy is therefore not "make it safe" (it cannot be) but
**make the exposure small, visible and revocable**:

1. exactly one request shape (HTTPS GET, declared template, declared host);
2. the destination is shown at install time and re-shown when it changes;
3. nothing is cached to disk and nothing is written to logs;
4. removing the catalog entry revokes the package in the next app version.

If a reviewer is not satisfied that those four hold, P3 should not ship.

---

## 2. Attack surface inventory

Everything P3 adds, in the order a malicious package reaches it.

| # | Surface | Attacker input | Consequence if unmitigated |
|---|---|---|---|
| 1 | `network.domains` | host names | SSRF, exfiltration to author host |
| 2 | `request.url` | path template | query injection, host confusion |
| 3 | `request.query` | key/value templates | leaking more of the user's text than the word |
| 4 | `request.headers` | header names/values | header injection, cookie theft |
| 5 | `response.*` JSON path | path expression | parser blowup, CPU/memory exhaustion |
| 6 | response body | server-controlled bytes | OOM, zip bomb, huge JSON, invalid UTF-8 |
| 7 | `settings[].type = secret` | secret values | credential leak via export/logs |
| 8 | contribution `license`/`attribution` | strings | licence misrepresentation (legal, not memory) |
| 9 | repeated lookups | timing | resource exhaustion of the whole lookup path |

---

## 3. Threat-by-threat analysis

### T1 — SSRF to local network or cloud metadata

**Attack.** Declare `network.domains: ["127.0.0.1"]`, or a public hostname that
resolves to `169.254.169.254`, so a lookup makes the app fetch an internal
service and (depending on response mapping) show it back to the user.

**Why the naive check fails.** Validating the URL string is not enough: DNS can
return a private address for an innocuous name (DNS rebinding), and a host can
redirect to a different destination after the first hop.

**Required control.**

1. Host must be an exact, lowercased DNS name in the allowlist; reject anything
   parseable as an IP literal in any notation (dotted, decimal, octal, hex,
   bracketed IPv6) — the allowlist is a name allowlist, never an address one.
2. Reject `localhost`, `*.localhost`, `.local`, `.internal`, `.home.arpa`,
   and names containing `@`, `%`, whitespace, backslash or control characters.
3. Resolve DNS in the host, then **check every returned A/AAAA record** against
   loopback, RFC1918, CGNAT, link-local, multicast, unspecified, broadcast,
   IPv4-mapped IPv6, `fc00::/7` and `fe80::/10`. Any single bad record rejects
   the whole request.
4. Connect **to the resolved address that was validated**, not by re-resolving
   the name. This is the only reliable mitigation for rebinding; a re-resolve at
   connect time reopens the window. Implementation: `HttpClient.connectionFactory`
   receives the connection task, and the socket is checked with
   `socket.remoteAddress` after connect as a second, independent check.
5. `followRedirects = false`. Any 3xx is a failure; `Location` is never read.

**Residual risk.** A resolver controlled by a hostile network can still answer
with a public address that later serves different content to a different
audience. P3 accepts this: the app is talking HTTPS to a host the user approved,
which is the same trust model as any other client.

### T2 — Query leakage beyond the looked-up word

**Attack.** Template `{setting.context}` with a number/select setting the user
filled in innocently, or a query key that invites the user to paste a whole
paragraph; the term is sent to the author's host.

**Control.** Query values may only use `{word}` and `{setting.<key>}`;
`{word}` is the trimmed lookup term, capped at 256 chars, and `{secret.*}` is
**forbidden** in query and path (secrets are header-only). Templates are capped
at 1024 chars, `{...}` of any other shape is rejected, and there is no recursive
expansion.

**Residual risk.** A plugin can still ask the user for a free-text setting and
put it in the query. That is visible in the install page (the settings form is
rendered there) and is the same exposure as any dictionary the user configures
deliberately. Document it; do not pretend it is prevented.

### T3 — Header injection and cookie theft

**Attack.** `Authorization: Bearer {secret.k}\r\nCookie: ...`, or a header
value built by concatenating attacker text with the secret, or a `Cookie`
header that steals the user's session for a host they also use.

**Control.** Fixed allowlist: `Accept`, `Accept-Language`, `Authorization`
(others rejected at manifest validation). `Authorization` may be exactly
`Bearer {secret.<key>}` or `{secret.<key>}` and nothing else — no concatenation,
no literals. The host forces `User-Agent`, `Host`, `Content-Length`,
`Connection`; `Cookie`, `Referer`, `Origin`, `X-Forwarded-*` are rejected.
Values are whitespace/control-character checked before being set.

### T4 — Parser and memory exhaustion

**Attack.** A 900 MB response, a gzip bomb, deeply nested JSON, or a JSON path
with `[*]` over a million elements.

**Control.** Stream the body and stop at `maxResponseBytes + 1` (≤ 1 MiB
hard ceiling regardless of manifest). Enforce decompressed size, not just
compressed. Validate UTF-8 after the byte cap. After parsing: depth ≤ 32, nodes
≤ 100000, total string length ≤ 2 MB. JSON path is a **data traversal only** —
no eval, no filters, no functions, no recursive descent; `[*]` expansion count
is bounded by the node limit. Human-facing text is truncated to
`maxDefinitionChars` and rendered with `SelectableText` (never as HTML).

### T5 — Secret exfiltration

**Attack.** A prompt-injection-ish package asks the user for an API key and a
free-text setting, then puts the setting into the query; or the key ends up in
`pluginConfig_`, settings export, WebDAV sync or `lastError`.

**Control.**

- Secrets live only in `pluginSecret_<id>`, never in `pluginConfig_`;
  `PluginConfig.validate` rejects secret keys by construction.
- Never exported: `includeSecrets=true` must **not** include them. This is a
  deliberate exception to the existing credential-transfer switch, and it needs
  user-facing copy saying so (§6).
- `backup_safety.isCredentialPreference` gains the `pluginSecret_` prefix so
  backup, import and sync paths all treat it as a credential.
- Host-side logging allowlist: plugin id, error code, domain, status code.
  Never header values, query values, full URLs or response bodies. `lastError`
  is built from that allowlist only.

**Residual risk (must be stated to users).** P3 does **not** add platform
Keychain/Keystore. Secrets are plaintext in SharedPreferences. The guarantee is
"no leakage through export, backup, sync or logs", **not** "encrypted at rest".
A device-level attacker is outside this boundary.

### T6 — Resource exhaustion of the lookup path

*(Failure taxonomy note: P3 reuses the existing `DictionaryFailure(code)` from
`lib/service/dictionary/local_dictionary.dart` rather than inventing a second
error type, so the lookup UI keeps one failure path. Codes add
`rateLimited`, `dailyLimit`, `invalidResponse`, `license` and `disabled` to the
existing `timeout`. Only the code reaches the UI and `lastError`; never a URL,
header or body.)*

**Attack.** A source that is slow or always fails, making the dictionary tab
unusable; or rapid repeated lookups hitting a paid upstream.

**Control.** Per-plugin: 1 concurrent (2 s queue timeout), 20/min sliding
window, 300/day. Global: 4 concurrent, 60/min. Per-request timeout from
`network.timeoutMs` (≤ 15 s). Cancellation on word change or page close is a
cancellation, not a failure, and does not count against quotas. One failing
source must not affect local dictionaries or other sources (per-source failure
isolation). No automatic retry.

### T7 — Impersonation of a built-in source

**Attack.** Register a source with the same display name as a built-in
Wiktionary source so the user believes they are using the trusted one.

**Control.** Plugin sources live under `online:plugin:<pluginId>:<sourceId>`
and the registry rejects an id collision with a built-in (P2 `HostRegistry`
already enforces this, including the id-over-alias case). The UI groups plugin
sources separately and shows the plugin name, licence and attribution.

### T8 — Content licence and attribution

**Attack (not malicious, but a compliance risk).** A plugin scrapes a
copyrighted dictionary and presents it without attribution.

**Control.** `license` and `attribution` are **required** manifest fields for
`dictionarySource`; `licenseUri`/`sourceUrl` must be `https` or are dropped.
The UI shows them next to results. Results are cached in memory only (64
entries/plugin, 10 min TTL) and never written to disk, so no scraped corpus is
persisted by the app. This does not make scraping lawful — it makes the licence
visible and reviewable at admission time, which is the only point the project
controls.

---

## 4. Controls that are *not* being built (and why)

Being explicit about non-goals matters as much as the controls.

| Not built | Why |
|---|---|
| Post-quantum / certificate pinning | Uses the platform TLS stack; pinning a third-party dictionary would break on certificate rotation. |
| Per-plugin proxy exemption | The app proxy is user-configured and the user trusts it. Documented as a limitation instead (§7). |
| Request signing / response authenticity | The host has nothing to authenticate against; TLS is the boundary. |
| Sandboxing the parser | The JSON path is a bounded traversal with no eval; a separate isolate is a P4 consideration, not a P3 requirement. |
| Rate limiting by bytes | Byte caps are per-response; aggregate volume is bounded by the daily quota × 1 MiB, which is acceptable. |
| Redaction of the *domain* in logs | Domains are already shown to the user in the install page; hiding them would hurt diagnosability more than it helps. |

---

## 5. Admission requirements for a P3 package

Extends [plugin trust](plugin-trust.md) — the catalog mechanism does not change.

Before a `net:http` package may be added to `PluginTrust.approved`:

1. Every declared domain is reviewed: not a redirector, not an ad/tracking
   endpoint, not a host the project would not itself call.
2. The request template is read line by line: what exactly is sent, to which
   path, with which query keys, and whether any setting could carry user text
   beyond the word.
3. The response mapping is checked for "reflect arbitrary server content into
   the UI" patterns (that is an injection vector for whatever renders it).
4. Licence and attribution are verified against the actual upstream terms, and
   `sourceUrl` points at the documented API.
5. Secrets: confirm the plugin genuinely needs one, and that it is used only in
   `Authorization`.
6. The package is re-reviewed when **any** of domains, templates, headers or
   response mapping changes — a version bump is not sufficient. Changing
   `domains` requires a fresh install confirmation on the user's device (§6).

---

## 6. User-facing disclosure requirements

These are DoD items, not nice-to-haves.

1. **Install page** lists the exact domains, states "query terms will be sent to
   these domains", shows "HTTPS only", and shows the licence/attribution.
2. **Changing the domain list** on reinstall shows the confirmation again.
   An unchanged list may reuse the record but is still displayed.
3. **Settings export** page adds: "Plugin keys are not exported with settings or
   backups; configure them again on each device."
4. **Plugin details page** shows: domains, per-plugin quota state, last error
   code (from the allowlist), and "configured / not configured" for each secret
   with no echo-back.
5. **First lookup** through a new plugin source shows the source name and its
   licence next to the results, grouped apart from local and built-in sources.
6. **SECURITY.md / PRIVACY.md** gain a paragraph stating: plugin lookups send
   the searched word to the plugin author's declared host over HTTPS; results are
   not stored on disk; plugin secrets are stored unencrypted on the device.

---

## 7. Accepted residual risks

| # | Risk | Why accepted | Mitigation in place |
|---|---|---|---|
| R1 | Plugin author receives every word the user looks up | That is the feature; disclosed at install | Domain shown, revocable by catalog update |
| R2 | Secrets are plaintext on disk | No Keystore/Keychain abstraction in P3 | Not exported, not logged; device attacker out of scope |
| R3 | A user-configured HTTP proxy sees plugin traffic | The proxy is the user's own trusted exit elsewhere in the app | Documented; allowlist still enforced at URL layer |
| R4 | Hostile DNS serves different content per client | HTTPS to an approved host is the same trust as any client | Certificate validation; no redirects |
| R5 | A plugin asks for a free-text setting and sends it | Visible in the settings form at install | `{secret.*}` forbidden in query/path |
| R6 | Scraping may still violate upstream terms | The project cannot police a user's chosen source | Licence visible; results not persisted |
| R7 | HarmonyOS network behaviour is unverified | OHOS is an unsigned cloud build with no device acceptance so far | Must be validated on a real device before P3 ships; degrade to "unavailable" otherwise |

---

## 8. Rollback and revocation

1. **Capability rollback**: remove `net:http` from the supported set → every
   network package fails to install; already-installed ones lose their
   contributions at startup reconciliation while configuration and secrets stay
   (no destructive migration).
2. **Finer rollback**: unregister only `DictionarySourceHandler`; P2 registries
   and declarative plugins are unaffected.
3. **Revocation**: deleting a catalog entry revokes that package in the next
   shipped version. There is **no** remote kill switch and this review will not
   claim one.
4. Never roll back by hiding UI: rejection must happen at the capability or
   install layer, so a package cannot be "installed but silently inert".

---

## 9. Open questions blocking P3a

| # | Question | Recommendation | Blocks |
|---|---|---|---|
| Q1 | JSON-only responses, or also minimal HTML text extraction? | **JSON only** in v1. HTML extraction means shipping a tolerance-tuned parser over untrusted markup — a much larger surface for one capability. | P3a manifest shape |
| Q2 | Export `pluginSecret_` when `includeSecrets=true`? | **Never export.** The user's mental model of that switch is "my own account credentials"; plugin secrets belong to package authors and users cannot be expected to track them. Making them exportable needs a second confirmation and its own review. | P3c |
| Q3 | Multiple domains per source (primary/backup)? | Allow 1–8 declared, but **one host per request and no runtime switching**. Backup hosts are a P3.2 feature with its own review. | P3a validation |
| Q4 | Should quota counters survive a restart? | **No.** In-memory only; a restart resetting the daily counter is acceptable and avoids I/O on a hot path. | P3b |
| Q5 | Is a per-plugin dedicated `HttpClient` required, or may it share one? | **Dedicated instance** per plugin source, created lazily and closed on disable/uninstall, so no cookies, connection reuse or interceptor state leaks between plugins. | P3b |

---

## 10. Testability requirements

A control that cannot be tested is not a control. P3a/P3b must be testable
**without real Internet access**:

- DNS: inject a resolver so the guard can be driven with private/public/
  rebinding answers.
- HTTP: a local server or a mock adapter for status codes, redirects, oversized
  bodies, slow responses, invalid UTF-8 and compression bombs.
- Time: an injectable clock for the sliding window, daily reset and cache TTL.
- Secrets: assert absence from export, backup, sync payloads, log output and
  `lastError` by scanning the produced strings, not by inspection.

The P3 test matrix in the design document (§5.13) is the checklist; a control
without a corresponding row there is either untested or unspecified.

---

## 11. Sign-off checklist

Before P3a merges:

- [ ] §9 Q1–Q5 answered and recorded in the design document.
- [ ] §2 surfaces each map to an implementation file and at least one test.
- [ ] §3 T1 controls implemented including connect-to-validated-address.
- [ ] §6 disclosure items present in the UI strings.
- [ ] §7 residual risks stated in user-facing docs, not only here.

Before P3 ships:

- [ ] §5 admission run against a real candidate package.
- [ ] §7 R7 (OHOS) validated on a device, or the capability reported unavailable.
- [ ] §8 rollback exercised once (flip the capability off and confirm clean
      degradation).
