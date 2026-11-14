import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_contribution_handler.dart';

class RegisteredPluginScriptAction {
  const RegisteredPluginScriptAction(this.pluginId, this.action);

  final String pluginId;
  final ScriptActionContribution action;
  String get id => 'script:$pluginId:${action.id}';
}

class PluginScriptActionRegistry extends ChangeNotifier {
  static final instance = PluginScriptActionRegistry();
  final _actions = <String, RegisteredPluginScriptAction>{};

  List<RegisteredPluginScriptAction> forSurface(PluginScriptSurface surface) =>
      List.unmodifiable(
          _actions.values.where((item) => item.action.surface == surface));

  List<RegisteredPluginScriptAction> forPlugin(String pluginId) =>
      List.unmodifiable(
          _actions.values.where((item) => item.pluginId == pluginId));

  RegisteredPluginScriptAction? byId(String id) => _actions[id];

  void replacePlugin(String pluginId, List<ScriptActionContribution> actions) {
    _actions.removeWhere((_, item) => item.pluginId == pluginId);
    for (final action in actions) {
      final registered = RegisteredPluginScriptAction(pluginId, action);
      _actions[registered.id] = registered;
    }
    notifyListeners();
  }

  void removeIds(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      changed = _actions.remove(id) != null || changed;
    }
    if (changed) notifyListeners();
  }
}

class ScriptActionContributionHandler implements PluginContributionHandler {
  ScriptActionContributionHandler({PluginScriptActionRegistry? registry})
      : registry = registry ?? PluginScriptActionRegistry.instance;

  final PluginScriptActionRegistry registry;

  @override
  String get kind => kScriptActionContributionKind;

  @override
  Set<String> get requiredCapabilities => const {kScriptRunCapability};

  @override
  bool get runtimeOnly => true;

  @override
  bool isApplied(AppliedContribution applied) =>
      registry.byId(applied.id) != null;

  @override
  void validate(
      PluginManifest manifest, List<PluginContribution> contributions) {
    if (!manifest.capabilities.contains(kScriptRunCapability)) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'Script actions require script:run.');
    }
    for (final action in contributions) {
      if (action is! ScriptActionContribution ||
          (action.surface == PluginScriptSurface.selection &&
              !manifest.capabilities.contains(kSelectionActionCapability)) ||
          (action.surface == PluginScriptSurface.dictionary &&
              !manifest.capabilities
                  .contains(kDictionaryTransformCapability))) {
        throw const PluginInstallError(PluginErrorCode.invalidContribution,
            'Script action or its declared permissions are invalid.');
      }
    }
  }

  @override
  Future<List<AppliedContribution>> apply(
      PluginManifest manifest, List<PluginContribution> contributions) async {
    validate(manifest, contributions);
    final actions = contributions.cast<ScriptActionContribution>();
    registry.replacePlugin(manifest.id, actions);
    return [
      for (final action in actions)
        AppliedContribution(
          kind: kind,
          id: RegisteredPluginScriptAction(manifest.id, action).id,
          contentSha256:
              sha256.convert(utf8.encode(jsonEncode(action.raw))).toString(),
        ),
    ];
  }

  @override
  Future<void> remove(List<AppliedContribution> applied) async {
    registry.removeIds(
        applied.where((item) => item.kind == kind).map((item) => item.id));
  }
}
