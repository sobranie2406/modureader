import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';

/// One contribution type. The host never switches on kind; it looks the
/// handler up in [PluginContributionRegistry] (decision D9), so new types are
/// added by writing a handler and registering it.
abstract class PluginContributionHandler {
  String get kind;

  /// Capabilities the manifest must declare before this handler runs.
  Set<String> get requiredCapabilities;

  /// Validates every contribution of this kind before anything is written.
  /// Throws [PluginInstallError].
  void validate(
      PluginManifest manifest, List<PluginContribution> contributions);

  /// Materialises the contributions and returns the records used by the
  /// uninstall hash guard.
  Future<List<AppliedContribution>> apply(
      PluginManifest manifest, List<PluginContribution> contributions);

  /// Removes previously materialised contributions. Implementations keep
  /// user-edited values (renaming them instead of deleting).
  Future<void> remove(List<AppliedContribution> applied);

  /// Whether [applied] still exists at runtime.
  ///
  /// Startup reconciliation uses this to decide whether contributions must be
  /// re-materialised, for example after a settings import removed them. Kinds
  /// without a cheap check, and kinds unknown to this build, stay conservative
  /// and report true so an older client never deletes what a newer one wrote.
  bool isApplied(AppliedContribution applied) => true;

  /// True when the contribution lives only in an in-memory registry and is
  /// therefore rebuilt on every start. Declarative kinds (prompts, toolbar
  /// actions) persist in preferences and are false.
  bool get runtimeOnly => false;
}

class PluginContributionRegistry {
  PluginContributionRegistry(Iterable<PluginContributionHandler> handlers)
      : _handlers = {
          for (final handler in handlers) handler.kind: handler,
        } {
    final duplicates = handlers
        .map((handler) => handler.kind)
        .where((kind) => handlers.where((h) => h.kind == kind).length > 1)
        .toSet();
    if (duplicates.isNotEmpty) {
      throw ArgumentError(
          "Duplicate plugin contribution handlers: ${duplicates.join(', ')}");
    }
  }

  final Map<String, PluginContributionHandler> _handlers;

  Iterable<String> get kinds => _handlers.keys;

  PluginContributionHandler? forKind(String kind) => _handlers[kind];
}
