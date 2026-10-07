# Cloud-only WebView 6.1.5 compatibility patch

Scope: CPF-Flutter/flutter_inappwebview commit
`528fa913763148719cde7dae2dc22dc33f15da36` only. No app `lib/`, root
`pubspec.yaml`, cached dependency source, or existing platform code is edited.

## Actions integration

After the **first** successful `flutter pub get`, and before readiness checks,
code generation, or HAP compilation, add this step to the cloud workflow:

```yaml
- name: Patch pinned Harmony WebView adapters and re-resolve
  shell: bash
  run: python3 scripts/harmony/patch_webview.py
```

The caller must already provide PyYAML, `MODU_OHOS_FLUTTER` (the isolated OH SDK),
and the Harmony dependency overlay. The script verifies Actions/Linux/workspace,
the three lockfile entries, Git HEAD, and every copied Git blob. It copies only
the three packages into `build/harmony-adapters`, relocates their sibling path
dependencies to the existing resolved packages, preserves other override entries
and top-level keys, then invokes `$MODU_OHOS_FLUTTER/bin/flutter pub get` itself.
It checks the resulting package roots. Do not add `continue-on-error`.

This change deliberately does **not** edit the current workflow; integration is
one explicit step above. Include both new Python files in the clean cloud snapshot.
The runtime `pubspec.lock` changes are confined to that temporary checkout.

The script refuses an existing adapter directory. On failure after publishing,
it restores the previous overlay, lockfile and package_config, leaves adapters for
inspection, and exits nonzero. Other pub-generated metadata may have changed;
discard the failed checkout rather than continuing a build or reusing it.

## Native behavior

* `requestFocus` routes Dart wrapper -> platform interface -> OHOS method channel
  -> `WebviewController.requestFocus()`. The native API returns void; Dart true
  means the request completed without a native exception, not an observed focus
  event. Native errors become PlatformException; no controller returns false.
  [Official SDK declaration](https://github.com/openharmony/interface_sdk-js/blob/master/api/@ohos.web.webview.d.ts)
  declares the method from API 9.
* `javaScriptBridgeEnabled` defaults to true and is serialized in both directions.
  It is a **creation-time policy**, preserved across navigation/settings changes.
  Changing it via setSettings errors: recreate the WebView. This avoids unsafe
  attempts to revoke an already-exposed page proxy asynchronously.
* False prevents native proxy registration (and revokes an adopted controller's
  proxy), all plugin-script scheduling, platform-ready injection, runtime plugin
  enablement, script-file bridge prelude, and popup bridge hooks. Both exported
  native proxy methods reject calls before accessing app state or dispatching
  built-in/user callbacks. The console popup fallback is gated too.
* Page JavaScript remains enabled. Page `evaluateJavascript` and page-world
  user scripts (including Modu zoom/layout scripts) still execute. Local readers
  with the default true retain the existing bridge.
* With false, callAsyncJavaScript, WebMessage bridge APIs and non-page-world
  evaluation explicitly error; upstream implements these with bridge callbacks.
  Non-page user scripts are rejected. This is not an origin-allowlist feature or
  a general JavaScript sandbox; callers choose false for untrusted WebViews.
* Other platform implementations inherit an explicit unsupported requestFocus
  method in this cloud-only package graph. This overlay must not be used to build
  normal Android/iOS/desktop distributions.

## Tests (no SDK installation)

Using an existing checkout of the exact upstream commit:

```sh
PYTHONDONTWRITEBYTECODE=1 \
HARMONY_WEBVIEW_UPSTREAM=/absolute/path/to/pinned/upstream \
python3 -m unittest discover -s test -p harmony_webview_patch_test.py -v
```

Requires PyYAML and Node >=22.13 for TypeScript erasure. An existing cached Dart
binary is used only for syntax checks; alternatively set `HARMONY_TEST_DART` to
that binary (not Flutter's update-capable wrapper). Without the upstream variable,
integration tests are explicitly skipped, not counted as verification.

Tests apply exact anchors to real upstream files, validate the complete patched
native TypeScript syntax, execute the actual bridge/focus/channel method bodies
with instrumented platform dependencies, execute retained zoom JS in a VM, and
check overlay preservation, second pub-get invocation and rollback. They do not
substitute for an OH SDK ArkTS type-check/HAP build or device focus behavior.
