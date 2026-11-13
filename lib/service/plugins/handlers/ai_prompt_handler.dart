import 'dart:convert';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/models/user_prompt.dart';
import 'package:modu_reader/service/plugins/handlers/plugin_locale.dart';
import 'package:modu_reader/service/plugins/plugin_contribution_handler.dart';
import 'package:modu_reader/service/plugins/plugin_prompt_template.dart';
import 'package:crypto/crypto.dart';

/// Materialises `aiSkill` contributions as ordinary user prompts.
///
/// The prompt list stays the single source of truth for the AI prompt picker;
/// no plugin-specific UI is required. Prompt ids embed the plugin id so an
/// uninstall can identify its own entries.
class AiPromptContributionHandler implements PluginContributionHandler {
  AiPromptContributionHandler({String Function()? localeResolver})
      : _localeResolver = localeResolver ?? currentPluginLocaleKey;

  final String Function() _localeResolver;

  @override
  String get kind => kAiSkillContributionKind;

  @override
  Set<String> get requiredCapabilities => const {kAiPromptPackCapability};

  @override
  void validate(
      PluginManifest manifest, List<PluginContribution> contributions) {
    if (!manifest.capabilities.containsAll(requiredCapabilities)) {
      throw PluginInstallError(PluginErrorCode.capabilityUnavailable,
          "Plugin uses 'aiSkill' but does not declare '$kAiPromptPackCapability'.");
    }
    if (contributions.length > PluginLimits.maxPromptsPerPlugin) {
      throw PluginInstallError(PluginErrorCode.tooManyContributions,
          'A plugin may add at most ${PluginLimits.maxPromptsPerPlugin} prompt templates.');
    }
    for (final contribution in contributions) {
      if (contribution is! AiSkillContribution) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            "Contribution '${contribution.id}' is not a valid aiSkill.");
      }
      if (contribution.prompt.trim().isEmpty) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            "Prompt '${contribution.id}' must not be empty.");
      }
      if (contribution.prompt.runes.length > PluginLimits.maxPromptLength) {
        throw PluginInstallError(PluginErrorCode.promptTooLong,
            "Prompt '${contribution.id}' exceeds ${PluginLimits.maxPromptLength} characters.");
      }
      if (!contribution.name.values.values
          .any((value) => value.trim().isNotEmpty)) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            "Prompt '${contribution.id}' has no display name.");
      }
    }
  }

  @override
  Future<List<AppliedContribution>> apply(
      PluginManifest manifest, List<PluginContribution> contributions) async {
    final locale = _localeResolver();
    final existing = Prefs().userPrompts;
    final next = List<UserPrompt>.from(existing);
    final ids = next.map((prompt) => prompt.id).toSet();
    var maxOrder = 0;
    for (final prompt in existing) {
      if (prompt.order > maxOrder) maxOrder = prompt.order;
    }
    final now = DateTime.now();
    final applied = <AppliedContribution>[];
    final installed = Prefs().pluginState.byId(manifest.id);
    final ownedIds =
        installed?.applied.map((entry) => entry.id).toSet() ?? const <String>{};

    for (final contribution in contributions) {
      final skill = contribution as AiSkillContribution;
      final id = promptIdFor(manifest.id, skill.id);
      final name = _displayName(skill, locale);
      final content = skill.prompt;
      final index = next.indexWhere((prompt) => prompt.id == id);
      if (index >= 0) {
        if (!ownedIds.contains(id)) {
          throw PluginInstallError(PluginErrorCode.promptConflict,
              "Prompt id '$id' is already in use by another prompt.",
              entry: skill.id);
        }
        final previous = next[index];
        // Upgrade: keep position and creation time, replace plugin content.
        next[index] = previous.copyWith(
          name: name,
          content: content,
          enabled: skill.enabled,
          updatedAt: now,
        );
      } else {
        if (ids.contains(id)) {
          throw PluginInstallError(PluginErrorCode.promptConflict,
              "Prompt id '$id' is already in use.",
              entry: skill.id);
        }
        next.add(UserPrompt(
          id: id,
          name: name,
          content: content,
          enabled: skill.enabled,
          order: ++maxOrder,
          createdAt: now,
          updatedAt: now,
        ));
      }
      ids.add(id);
      applied.add(AppliedContribution(
        kind: kind,
        id: id,
        contentSha256: contentHash(content),
      ));
    }

    if (next.length != existing.length || !_samePrompts(existing, next)) {
      Prefs().userPrompts = next;
    }
    return applied;
  }

  /// Prompts are stored in preferences, not an in-memory registry.
  @override
  bool get runtimeOnly => false;

  /// Prompts persist in userPrompts, so a missing id means the contribution
  /// was removed (settings import) and has to be re-materialised.
  @override
  bool isApplied(AppliedContribution applied) =>
      applied.kind == kind && Prefs().userPrompts.any((p) => p.id == applied.id);

  @override
  Future<void> remove(List<AppliedContribution> applied) async {
    final promptEntries = applied.where((entry) => entry.kind == kind).toList();
    if (promptEntries.isEmpty) return;

    final existing = Prefs().userPrompts;
    final next = List<UserPrompt>.from(existing);
    final usedIds = next.map((prompt) => prompt.id).toSet();
    var changed = false;
    final now = DateTime.now();
    var renamed = 0;

    for (final entry in promptEntries) {
      final index = next.indexWhere((prompt) => prompt.id == entry.id);
      if (index < 0) continue;
      final prompt = next[index];
      if (contentHash(prompt.content) == entry.contentSha256) {
        next.removeAt(index);
        usedIds.remove(entry.id);
      } else {
        // The user edited this prompt: keep it as a normal custom prompt so a
        // reinstall cannot collide with the old id and the edit is not lost.
        var customId =
            'custom-${now.millisecondsSinceEpoch}${renamed == 0 ? '' : '-$renamed'}';
        while (usedIds.contains(customId)) {
          renamed++;
          customId = 'custom-${now.millisecondsSinceEpoch}-$renamed';
        }
        renamed++;
        usedIds.remove(entry.id);
        usedIds.add(customId);
        next[index] = prompt.copyWith(id: customId, updatedAt: now);
      }
      changed = true;
    }

    if (changed) {
      // Re-number orders so the list stays deterministic after removals.
      for (var i = 0; i < next.length; i++) {
        if (next[i].order != i) next[i] = next[i].copyWith(order: i);
      }
      Prefs().userPrompts = next;
    }
  }

  static String promptIdFor(String pluginId, String skillId) =>
      PluginPromptTemplate.promptId(pluginId, skillId);

  static String contentHash(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  static String _displayName(AiSkillContribution skill, String locale) {
    final name = skill.name.resolve(locale).trim();
    return name.isEmpty ? skill.id : name;
  }

  static bool _samePrompts(List<UserPrompt> a, List<UserPrompt> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].content != b[i].content ||
          a[i].enabled != b[i].enabled ||
          a[i].order != b[i].order) {
        return false;
      }
    }
    return true;
  }
}
