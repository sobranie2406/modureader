import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';

/// Optional lookup candidates; dictionary content and host APIs stay outside JS.
class PluginDictionaryTransform {
  PluginDictionaryTransform({
    PluginScriptRuntime? runtime,
    PluginScriptActionRegistry? registry,
  })  : _runtime = runtime,
        _registry = registry ?? PluginScriptActionRegistry.instance;

  PluginScriptRuntime? _runtime;
  final PluginScriptActionRegistry _registry;
  final _pending = <String>{};
  int _generation = 0;

  void cancel() {
    _generation++;
    for (final id in _pending) {
      _runtime?.cancelPlugin(id);
    }
    _pending.clear();
  }

  Future<List<String>> candidates(String word,
      {required bool Function() isContextValid}) async {
    if (!Prefs.isReady ||
        !PluginHost.isEnabled ||
        !Prefs().experimentalPluginsEnabled ||
        word.trim().isEmpty ||
        word.length > 256) {
      return [];
    }
    final actions = _registry.forSurface(PluginScriptSurface.dictionary);
    if (actions.isEmpty || !isContextValid()) return [];
    final generation = _generation;
    bool current() =>
        generation == _generation &&
        isContextValid() &&
        Prefs.isReady &&
        PluginHost.isEnabled &&
        Prefs().experimentalPluginsEnabled;
    final result = <String>{};
    final runtime = _runtime ??= PluginScriptRuntime.instance;
    for (final registered in actions) {
      if (!current()) return [];
      if (!identical(_registry.byId(registered.id), registered)) continue;
      if (runtime.isRunning(registered.pluginId)) continue;
      _pending.add(registered.pluginId);
      try {
        final value = await runtime.run(
            pluginId: registered.pluginId,
            action: registered.action,
            input: {'selection': word},
            isContextValid: current);
        if (!current()) return [];
        if (!identical(_registry.byId(registered.id), registered)) continue;
        final candidates = value['candidates'];
        if (candidates is! List || candidates.length > 12) continue;
        for (final candidate in candidates) {
          if (candidate is! String ||
              candidate.length > 256 ||
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(candidate)) {
            continue;
          }
          final text = candidate.trim();
          if (text.isNotEmpty && text != word.trim()) result.add(text);
          if (result.length == 12) return result.toList();
        }
      } catch (_) {
        // A disabled, busy or failed plugin never prevents an exact lookup.
      } finally {
        _pending.remove(registered.pluginId);
      }
    }
    return current() ? result.toList() : [];
  }
}
