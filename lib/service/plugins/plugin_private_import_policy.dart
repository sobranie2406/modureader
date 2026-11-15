import 'dart:convert';

import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:path/path.dart' as p;

/// Pure plugin policies complete before a new book enters the database.
class PluginPrivateImportPolicy {
  const PluginPrivateImportPolicy._();
  static PrivateLibrary? _attached;

  static void attach(PrivateLibrary library) {
    if (identical(_attached, library)) return;
    _attached = library;
    library.importPolicy = (book) => evaluate(book);
  }

  static Future<bool?> evaluate(Book book,
      {PluginScriptActionRegistry? registry,
      PluginHost Function(String)? resolveHost,
      PluginScriptRuntime Function(String)? resolveRuntime}) async {
    final source = registry ?? PluginScriptActionRegistry.instance;
    final actions = source.forSurface(PluginScriptSurface.bookImport);
    final guards = <bool Function()>[];
    bool policiesCurrent() {
      final latest = source.forSurface(PluginScriptSurface.bookImport);
      return latest.length == actions.length &&
          List.generate(actions.length, (i) => identical(latest[i], actions[i]))
              .every((value) => value) &&
          guards.every((guard) => guard());
    }

    var hasPolicy = false;
    for (final registered in actions) {
      final owner =
          (resolveHost ?? PluginHost.executionHostFor)(registered.pluginId);
      final manifest = owner.manifestFor(registered.pluginId);
      if (manifest == null ||
          !owner.isScriptRunnable(registered.pluginId) ||
          !manifest.capabilities.containsAll({
            kLibraryPrivateCapability,
            kLibraryPrivatePolicyCapability,
            kScriptRunCapability
          }) ||
          !manifest.contributions
              .any((entry) => identical(entry, registered.action))) {
        continue;
      }
      hasPolicy = true;
      final config = jsonEncode(owner.configFor(registered.pluginId));
      bool current() =>
          identical(owner.manifestFor(registered.pluginId), manifest) &&
          owner.isScriptRunnable(registered.pluginId) &&
          identical(source.byId(registered.id), registered) &&
          jsonEncode(owner.configFor(registered.pluginId)) == config;
      guards.add(current);
      final gate = registered.action.enabledSetting;
      if (gate != null) {
        final spec =
            manifest.settings.singleWhere((entry) => entry.key == gate);
        final value =
            owner.configFor(registered.pluginId)[gate] ?? spec.defaultValue;
        if (value != true) continue;
      }
      final runtime =
          (resolveRuntime ?? PluginHost.runtimeFor)(registered.pluginId);
      if (!identical(runtime.host, owner)) {
        throw const PluginScriptFailure('unavailable');
      }
      final result = await runtime.run(
          pluginId: registered.pluginId,
          action: registered.action,
          input: {
            'book': {
              'id': book.id,
              'title': book.title,
              'author': book.author,
              'format': p
                  .extension(book.filePath)
                  .replaceFirst('.', '')
                  .toLowerCase(),
            }
          },
          isContextValid: policiesCurrent);
      if (!policiesCurrent()) throw const PluginScriptFailure('cancelled');
      if (result.length != 1 || result['private'] is! bool) {
        throw const PluginScriptFailure('result');
      }
      if (result['private'] == true) return true;
    }
    if (!policiesCurrent()) throw const PluginScriptFailure('cancelled');
    return hasPolicy ? false : null;
  }
}
