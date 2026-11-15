import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_contribution_handler.dart';

class RegisteredPluginBookAction {
  const RegisteredPluginBookAction(this.pluginId, this.action);

  final String pluginId;
  final BookActionContribution action;
  String get id => 'book:$pluginId:${action.id}';
}

class PluginBookActionRegistry extends ChangeNotifier {
  static final instance = PluginBookActionRegistry();
  final _actions = <String, RegisteredPluginBookAction>{};

  List<RegisteredPluginBookAction> get all =>
      List.unmodifiable(_actions.values);

  List<RegisteredPluginBookAction> forPlugin(String pluginId) =>
      List.unmodifiable(
          _actions.values.where((entry) => entry.pluginId == pluginId));

  RegisteredPluginBookAction? byId(String id) => _actions[id];

  void replacePlugin(String pluginId, List<BookActionContribution> actions) {
    _actions.removeWhere((_, entry) => entry.pluginId == pluginId);
    for (final action in actions) {
      final registered = RegisteredPluginBookAction(pluginId, action);
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

class BookActionContributionHandler implements PluginContributionHandler {
  BookActionContributionHandler({PluginBookActionRegistry? registry})
      : registry = registry ?? PluginBookActionRegistry.instance;

  final PluginBookActionRegistry registry;

  @override
  String get kind => kBookActionContributionKind;

  @override
  Set<String> get requiredCapabilities =>
      const {kBookActionCapability, kLibraryPrivateCapability};

  @override
  bool get runtimeOnly => true;

  @override
  bool isApplied(AppliedContribution applied) =>
      applied.kind == kind && registry.byId(applied.id) != null;

  @override
  void validate(
      PluginManifest manifest, List<PluginContribution> contributions) {
    if (contributions.isEmpty) return;
    if (!manifest.capabilities.containsAll(requiredCapabilities)) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'Book actions require their book-menu and private-library capabilities.');
    }
    if (contributions.length > PluginLimits.maxBookActionsPerPlugin) {
      throw const PluginInstallError(PluginErrorCode.tooManyContributions,
          'A package has too many book actions.');
    }
    for (final action in contributions) {
      if (action is! BookActionContribution ||
          action.kind != kind ||
          action.schema != 1 ||
          action.command != 'privateLibrary.hide' ||
          action.name.resolve(null).trim().isEmpty) {
        throw const PluginInstallError(PluginErrorCode.invalidContribution,
            'The book action is not supported.');
      }
    }
  }

  @override
  Future<List<AppliedContribution>> apply(
      PluginManifest manifest, List<PluginContribution> contributions) async {
    validate(manifest, contributions);
    final actions = contributions.cast<BookActionContribution>();
    registry.replacePlugin(manifest.id, actions);
    return [
      for (final action in actions)
        AppliedContribution(
            kind: kind,
            id: RegisteredPluginBookAction(manifest.id, action).id,
            contentSha256:
                sha256.convert(utf8.encode(jsonEncode(action.raw))).toString()),
    ];
  }

  @override
  Future<void> remove(List<AppliedContribution> applied) async {
    registry.removeIds(
        applied.where((entry) => entry.kind == kind).map((entry) => entry.id));
  }
}
