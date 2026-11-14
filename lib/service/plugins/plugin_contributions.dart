import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/handlers/ai_prompt_handler.dart';
import 'package:modu_reader/service/plugins/handlers/selection_action_handler.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_contribution_handler.dart';

/// Orchestrates contribution handlers: validates all kinds first, then applies
/// them in manifest order and rolls back materialised values on failure.
class PluginContributions {
  PluginContributions(this.registry);

  factory PluginContributions.standard() => PluginContributions(
        PluginContributionRegistry([
          AiPromptContributionHandler(),
          SelectionActionContributionHandler(),
          ScriptActionContributionHandler(),
        ]),
      );

  final PluginContributionRegistry registry;

  /// Applies every contribution whose kind has a registered handler.
  ///
  /// Contributions with unknown kinds were already skipped during manifest
  /// parsing; they are deliberately ignored here too (decision D1).
  Future<List<AppliedContribution>> apply(PluginManifest manifest) async {
    final groups = <String, List<PluginContribution>>{};
    for (final contribution in manifest.contributions) {
      if (registry.forKind(contribution.kind) == null) continue;
      groups.putIfAbsent(contribution.kind, () => []).add(contribution);
    }

    // Fail before writing anything if any group is invalid.
    for (final entry in groups.entries) {
      registry.forKind(entry.key)!.validate(manifest, entry.value);
    }

    final applied = <AppliedContribution>[];
    try {
      for (final entry in groups.entries) {
        final handler = registry.forKind(entry.key)!;
        applied.addAll(await handler.apply(manifest, entry.value));
      }
    } catch (_) {
      await _rollback(applied);
      rethrow;
    }
    return applied;
  }

  Future<void> remove(List<AppliedContribution> applied) async {
    if (applied.isEmpty) return;
    final groups = <String, List<AppliedContribution>>{};
    for (final contribution in applied) {
      groups.putIfAbsent(contribution.kind, () => []).add(contribution);
    }
    for (final entry in groups.entries) {
      final handler = registry.forKind(entry.key);
      if (handler == null) continue;
      await handler.remove(entry.value);
    }
  }

  Future<void> _rollback(List<AppliedContribution> applied) async {
    if (applied.isEmpty) return;
    try {
      await remove(applied);
    } catch (_) {
      // Best effort only; the caller reports the original failure.
    }
  }
}
