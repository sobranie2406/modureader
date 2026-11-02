import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/service/plugins/plugin_config.dart';
import 'package:anx_reader/service/plugins/plugin_host.dart';
import 'package:flutter/foundation.dart';

/// Instantiation of plugin prompts.
///
/// A plugin contributes a template; its settings only become text when the user
/// runs the contribution, so substitution happens here instead of at install
/// time. Stored prompt content keeps the raw template, which also keeps the
/// uninstall "the user edited this" hash guard meaningful.
class PluginPromptTemplate {
  const PluginPromptTemplate._();

  /// `{setting.<key>}`.
  ///
  /// The syntax matches the placeholder plan for declarative network plugins, so
  /// one package uses one placeholder style for prompts and request templates.
  static final RegExp placeholder =
      RegExp(r'\{setting\.([a-z][a-z0-9_]{0,39})\}');

  static const String promptPrefix = 'plugin:';
  static const String actionPrefix = 'custom-plugin:';

  /// `plugin:<pluginId>:<contributionId>` for AI prompts.
  static String promptId(String pluginId, String contributionId) =>
      '$promptPrefix$pluginId:$contributionId';

  /// `custom-plugin:<pluginId>:<contributionId>` for toolbar actions.
  static String actionId(String pluginId, String contributionId) =>
      '$actionPrefix$pluginId:$contributionId';

  /// Splits a plugin-owned id into `(pluginId, contributionId)`.
  ///
  /// Returns null for built-in and user-created entries so callers never need a
  /// plugin-specific branch.
  static (String, String)? splitId(String id) {
    final String? prefix = id.startsWith(promptPrefix)
        ? promptPrefix
        : (id.startsWith(actionPrefix) ? actionPrefix : null);
    if (prefix == null) return null;
    final rest = id.substring(prefix.length);
    final separator = rest.indexOf(':');
    if (separator <= 0 || separator == rest.length - 1) return null;
    return (rest.substring(0, separator), rest.substring(separator + 1));
  }

  /// Replaces every known placeholder in [template].
  ///
  /// Unknown keys, values that cannot be rendered as text and packages that are
  /// currently missing or broken keep their placeholder verbatim: a user must
  /// never silently lose part of a prompt because a plugin is unavailable.
  static String render(
    String template, {
    required PluginManifest manifest,
    required Map<String, dynamic> values,
  }) {
    if (template.isEmpty || !template.contains('{setting.')) return template;
    return template.replaceAllMapped(placeholder, (match) {
      final key = match.group(1)!;
      final spec = _specFor(manifest, key);
      if (spec == null || spec.type == PluginSettingType.tip) {
        return match.group(0)!;
      }
      final raw = values.containsKey(key) ? values[key] : spec.defaultValue;
      return _render(raw) ?? match.group(0)!;
    });
  }

  /// Renders a stored contribution against the current plugin state.
  ///
  /// Anything that is not a resolvable plugin entry is returned unchanged, so
  /// call sites can apply this unconditionally.
  static String renderForId(String id, String template) {
    if (template.isEmpty || !template.contains('{setting.')) return template;
    final ids = splitId(id);
    if (ids == null) return template;
    final pluginId = ids.$1;
    final manifest = _manifestFor(pluginId);
    if (manifest == null) return template;
    return render(
      template,
      manifest: manifest,
      values: PluginConfig.sanitize(manifest, _configFor(pluginId)),
    );
  }

  /// Resolves the prompt content of [prompt] when it belongs to a plugin.
  static String resolveUserPrompt(UserPrompt prompt) =>
      renderForId(prompt.id, prompt.content);

  /// Overridden by tests so they never touch app data; production resolves the
  /// app-wide host.
  @visibleForTesting
  static PluginHost? hostOverride;

  static PluginHost get _host => hostOverride ?? PluginHost.instance;

  static PluginManifest? _manifestFor(String pluginId) {
    if (!PluginHost.isEnabled) return null;
    final host = _host;
    if (!host.isInitialized) return null;
    final record = host.byId(pluginId);
    if (record == null || !record.isUsable) return null;
    return host.manifestFor(pluginId);
  }

  static Map<String, dynamic> _configFor(String pluginId) {
    try {
      return _host.isInitialized ? Prefs().pluginConfig(pluginId) : const {};
    } catch (_) {
      return const {};
    }
  }

  static PluginSettingSpec? _specFor(PluginManifest manifest, String key) {
    for (final spec in manifest.settings) {
      if (spec.key == key) return spec;
    }
    return null;
  }

  /// Settings are scalar declarations; anything else keeps its placeholder.
  static String? _render(Object? value) {
    if (value is String) return value;
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is num) {
      return value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
    }
    return null;
  }
}