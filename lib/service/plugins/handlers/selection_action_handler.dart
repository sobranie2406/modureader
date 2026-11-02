import 'dart:convert';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/models/plugin_state.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/service/plugins/handlers/plugin_locale.dart';
import 'package:anx_reader/service/plugins/plugin_contribution_handler.dart';
import 'package:anx_reader/service/plugins/plugin_prompt_template.dart';
import 'package:crypto/crypto.dart';

/// Materialises `selectionAction` contributions as ordinary custom AI
/// commands. The toolbar runtime already knows how to run `aiCommand` items,
/// so no plugin branch is needed while handling a selection.
class SelectionActionContributionHandler implements PluginContributionHandler {
  SelectionActionContributionHandler({String Function()? localeResolver})
      : _localeResolver = localeResolver ?? currentPluginLocaleKey;

  final String Function() _localeResolver;

  static const int maxToolbarSlots = 24;

  @override
  String get kind => kSelectionActionContributionKind;

  @override
  Set<String> get requiredCapabilities => const {kSelectionActionCapability};

  @override
  void validate(
      PluginManifest manifest, List<PluginContribution> contributions) {
    if (!manifest.capabilities.containsAll(requiredCapabilities)) {
      throw PluginInstallError(PluginErrorCode.capabilityUnavailable,
          "Plugin uses 'selectionAction' but does not declare '$kSelectionActionCapability'.");
    }
    if (contributions.length > PluginLimits.maxSelectionActionsPerPlugin) {
      throw PluginInstallError(PluginErrorCode.tooManyContributions,
          'A plugin may add at most ${PluginLimits.maxSelectionActionsPerPlugin} selection actions.');
    }

    final config = Prefs().selectionToolbar;
    final installed = Prefs().pluginState.byId(manifest.id);
    final ownedIds = installed?.applied
            .where((entry) => entry.kind == kind)
            .map((entry) => entry.id)
            .toSet() ??
        const <String>{};

    var newActions = 0;
    for (final contribution in contributions) {
      if (contribution is! SelectionActionContribution) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            "Contribution '${contribution.id}' is not a valid selectionAction.");
      }
      final id = toolbarIdFor(manifest.id, contribution.id);
      if (id.length > 100) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            "Selection action '${contribution.id}' produces an id that is too long.",
            entry: contribution.id);
      }
      if (!SelectionToolbarConfig.iconIds.contains(contribution.icon)) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            "Selection action '${contribution.id}' uses an unknown icon.",
            entry: contribution.id);
      }
      if (contribution.prompt.trim().isEmpty) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            "Selection action '${contribution.id}' must have a prompt.",
            entry: contribution.id);
      }
      if (contribution.name.resolve(_localeResolver()).trim().isEmpty) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            "Selection action '${contribution.id}' has no display name.",
            entry: contribution.id);
      }
      final existing = config.items.any((item) => item.id == id);
      if (existing && !ownedIds.contains(id)) {
        throw PluginInstallError(PluginErrorCode.toolbarConflict,
            "Toolbar action id '$id' is already in use.",
            entry: contribution.id);
      }
      if (!existing) newActions++;
    }

    final custom = config.items
        .where((item) =>
            item.isCustom &&
            !SelectionToolbarConfig.templateItems
                .any((preset) => preset.id == item.id))
        .length;
    if (custom + newActions > maxToolbarSlots) {
      throw PluginInstallError.noToolbarSlots(
          math.max(0, maxToolbarSlots - custom));
    }
  }

  @override
  Future<List<AppliedContribution>> apply(
      PluginManifest manifest, List<PluginContribution> contributions) async {
    final locale = _localeResolver();
    final config = Prefs().selectionToolbar;
    final next = List<SelectionToolbarItem>.from(config.items);
    final installed = Prefs().pluginState.byId(manifest.id);
    final ownedIds = installed?.applied
            .where((entry) => entry.kind == kind)
            .map((entry) => entry.id)
            .toSet() ??
        const <String>{};
    final applied = <AppliedContribution>[];

    for (final contribution in contributions) {
      final action = contribution as SelectionActionContribution;
      final id = toolbarIdFor(manifest.id, action.id);
      final name = action.name.resolve(locale).trim();
      final scope = SelectionAiScope.values.byName(action.scope.name);
      final index = next.indexWhere((item) => item.id == id);
      if (index >= 0) {
        if (!ownedIds.contains(id)) {
          throw PluginInstallError(PluginErrorCode.toolbarConflict,
              "Toolbar action id '$id' is already in use.",
              entry: action.id);
        }
        next[index] = next[index].copyWith(
          name: name,
          icon: action.icon,
          prompt: action.prompt,
          scope: scope,
          enabled: action.enabled,
        );
      } else {
        next.add(SelectionToolbarItem(
          id,
          'aiCommand',
          enabled: action.enabled,
          name: name,
          icon: action.icon,
          prompt: action.prompt,
          scope: scope,
          skillId: 'selection_toolbar',
        ));
      }
      applied.add(AppliedContribution(
        kind: kind,
        id: id,
        contentSha256: _hash(_canonical(
          name: name,
          icon: action.icon,
          prompt: action.prompt,
          scope: scope,
        )),
      ));
    }

    await Prefs()
        .saveSelectionToolbar(config.copyWith(items: List.unmodifiable(next)));
    return applied;
  }

  @override
  Future<void> remove(List<AppliedContribution> applied) async {
    final entries = applied.where((entry) => entry.kind == kind).toList();
    if (entries.isEmpty) return;

    final config = Prefs().selectionToolbar;
    final next = List<SelectionToolbarItem>.from(config.items);
    final usedIds = next.map((item) => item.id).toSet();
    var changed = false;
    var renamed = 0;
    final now = DateTime.now();

    for (final entry in entries) {
      final index = next.indexWhere((item) => item.id == entry.id);
      if (index < 0) continue;
      final item = next[index];
      if (_hash(_canonical(
            name: item.name,
            icon: item.icon,
            prompt: item.prompt,
            scope: item.scope,
          )) ==
          entry.contentSha256) {
        next.removeAt(index);
        usedIds.remove(entry.id);
      } else {
        // The user edited this action: keep it as an ordinary custom command so
        // a reinstall cannot collide with the old id and the edit is not lost.
        var customId = 'custom-${now.millisecondsSinceEpoch}';
        while (usedIds.contains(customId)) {
          renamed++;
          customId = 'custom-${now.millisecondsSinceEpoch}-$renamed';
        }
        renamed++;
        usedIds.remove(entry.id);
        usedIds.add(customId);
        next[index] = item.copyWith(id: customId);
      }
      changed = true;
    }

    if (changed) {
      await Prefs().saveSelectionToolbar(
          config.copyWith(items: List.unmodifiable(next)));
    }
  }

  static String toolbarIdFor(String pluginId, String actionId) =>
      PluginPromptTemplate.actionId(pluginId, actionId);

  static String _hash(String canonical) =>
      sha256.convert(utf8.encode(canonical)).toString();

  static String _canonical({
    required String name,
    required String icon,
    required String prompt,
    required SelectionAiScope scope,
  }) =>
      jsonEncode({
        'name': name,
        'icon': icon,
        'prompt': prompt,
        'scope': scope.name,
      });
}