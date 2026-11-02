/// Pure-data catalog of the built-in selection-toolbar actions.
///
/// The catalog is **derived** from the const tables in
/// `selection_toolbar.dart`; it never restates them, so the localised template
/// prompts have exactly one home. It exists so validation can ask "is this a
/// shipped action with this verb?" through one lookup instead of comparing
/// static list identities.
///
/// Ids are persisted in 'selectionToolbar' and in settings backups. They must
/// never be renamed; only added.
library;

import 'package:anx_reader/models/selection_toolbar.dart';

/// Which list an action belongs to; the settings page renders one group each.
enum ToolbarActionGroup { primary, annotation, template }

/// One built-in toolbar action, identified by id + verb.
class ToolbarActionDefinition {
  const ToolbarActionDefinition({
    required this.id,
    required this.action,
    required this.group,
  });

  final String id;
  final String action;
  final ToolbarActionGroup group;

  bool get isAi => action == 'ai' || action == 'aiCommand';
}

class ToolbarCatalog {
  ToolbarCatalog({
    required this.primaryItems,
    required this.annotationItems,
    required this.templateItems,
  });

  final List<SelectionToolbarItem> primaryItems;
  final List<SelectionToolbarItem> annotationItems;
  final List<SelectionToolbarItem> templateItems;

  static final ToolbarCatalog standard = ToolbarCatalog(
    primaryItems: SelectionToolbarConfig.defaultItems,
    annotationItems: SelectionToolbarConfig.defaultAnnotations,
    templateItems: SelectionToolbarConfig.templateItems,
  );

  /// Every built-in action, primary first, in toolbar order.
  late final List<ToolbarActionDefinition> actions = [
    for (final item in primaryItems)
      ToolbarActionDefinition(
          id: item.id,
          action: item.action,
          group: ToolbarActionGroup.primary),
    for (final item in annotationItems)
      ToolbarActionDefinition(
          id: item.id,
          action: item.action,
          group: ToolbarActionGroup.annotation),
    for (final item in templateItems)
      ToolbarActionDefinition(
          id: item.id,
          action: item.action,
          group: ToolbarActionGroup.template),
  ];

  late final Map<String, ToolbarActionDefinition> _byId = {
    for (final action in actions) action.id: action,
  };

  ToolbarActionDefinition? byId(String id) => _byId[id];

  /// True when [id] is a shipped action carrying the matching [action] verb.
  bool matches(String id, String action) {
    final definition = _byId[id];
    return definition != null && definition.action == action;
  }

  /// Ids that belong to the shipped presets, as opposed to user/plugin entries.
  bool isTemplateId(String id) => templateItems.any((item) => item.id == id);

  bool get containsAi => actions.any((definition) => definition.isAi);
}
