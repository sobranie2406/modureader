import 'package:anx_reader/models/toolbar_action_definition.dart';
import 'package:anx_reader/service/registry/host_registry.dart';

/// One toolbar action known to the app.
///
/// Built-in entries come from [ToolbarCatalog]; plugin contributions are
/// registered with the `custom-plugin:` prefix by the selection-action handler
/// and keep their own 24-slot budget.
class ToolbarActionEntry implements RegistryEntry {
  const ToolbarActionEntry({
    required this.id,
    required this.action,
    this.aliases = const [],
    this.owner = const RegistryOwner.builtIn(),
    this.template = false,
  });

  @override
  final String id;

  final String action;

  @override
  final List<String> aliases;

  @override
  final RegistryOwner owner;

  /// Shipped preset, as opposed to a user- or plugin-created command.
  final bool template;

  @override
  RegistryDomain get domain => RegistryDomain.toolbar;

  bool get isBuiltIn => owner is BuiltInOwner;
}

class ToolbarRegistry {
  ToolbarRegistry(Iterable<ToolbarActionEntry> entries) {
    for (final entry in entries) {
      registry.register(entry);
    }
  }

  static final ToolbarRegistry instance =
      ToolbarRegistry.fromCatalog(ToolbarCatalog.standard);

  factory ToolbarRegistry.fromCatalog(ToolbarCatalog catalog) =>
      ToolbarRegistry([
        for (final definition in catalog.actions)
          ToolbarActionEntry(
            id: definition.id,
            action: definition.action,
            template: definition.group == ToolbarActionGroup.template,
          ),
      ]);

  static ToolbarRegistry _current = instance;

  static ToolbarRegistry get current => _current;

  static void useForTesting(ToolbarRegistry? value) => _current = value ?? instance;

  final HostRegistry<ToolbarActionEntry> registry =
      HostRegistry<ToolbarActionEntry>(RegistryDomain.toolbar);

  /// True when [id] is a shipped action that carries the [action] verb.
  ///
  /// Replaces the old `identical(defaults, defaultItems)` comparison: the check
  /// is now "is this id shipped with this verb", which survives a list being
  /// reorganised and lets a plugin action be told apart from a built-in one.
  bool matchesBuiltIn(String id, String action) {
    final entry = registry.byId(id);
    return entry != null && entry.isBuiltIn && entry.action == action;
  }

  bool isBuiltIn(String id) => registry.byId(id)?.isBuiltIn ?? false;

  bool isTemplate(String id) => registry.byId(id)?.template ?? false;

  /// Icon ids a command may use. Built-ins ship their own set; plugin actions
  /// are validated against the same set by `SelectionActionHandler`.
  static const Set<String> iconIds = {
    'query',
    'copy',
    'search',
    'translate',
    'dictionary',
    'narrate',
    'note',
    'ai',
    'share',
    'delete',
    'highlight',
    'underline',
    'colors',
    'star',
    'heart',
    'lightbulb',
    'summary',
    'quote',
    'mindmap',
  };

  /// Reading-skill ids a toolbar command may reference.
  static const Set<String> skillIds = {
    'selection_toolbar',
    'ai_dictionary',
    'concept_explainer',
    'smart_translator',
    'vocabulary_helper',
    'mindmap',
  };
}
