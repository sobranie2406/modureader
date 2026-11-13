import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/providers/current_reading.dart';
import 'package:modu_reader/service/ai/tools/apply_book_tags_tool.dart';
import 'package:modu_reader/service/ai/tools/book_content_search_tool.dart';
import 'package:modu_reader/service/ai/tools/books_tags_list_tool.dart';
import 'package:modu_reader/service/ai/tools/bookshelf_lookup_tool.dart';
import 'package:modu_reader/service/ai/tools/bookshelf_organize_tool.dart';
import 'package:modu_reader/service/ai/tools/calculator_tool.dart';
import 'package:modu_reader/service/ai/tools/chapter_content_by_href_tool.dart';
import 'package:modu_reader/service/ai/tools/current_book_toc_tool.dart';
import 'package:modu_reader/service/ai/tools/current_chapter_content_tool.dart';
import 'package:modu_reader/service/ai/tools/current_reading_metadata_tool.dart';
import 'package:modu_reader/service/ai/tools/current_time_tool.dart';
import 'package:modu_reader/service/ai/tools/mindmap_tool.dart';
import 'package:modu_reader/service/ai/tools/notes_search_tool.dart';
import 'package:modu_reader/service/ai/tools/reading_history_tool.dart';
import 'package:modu_reader/service/ai/tools/tags_list_tool.dart';
import 'package:modu_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:modu_reader/service/ai/tools/repository/books_repository.dart';
import 'package:modu_reader/service/ai/tools/repository/groups_repository.dart';
import 'package:modu_reader/service/ai/tools/repository/notes_repository.dart';
import 'package:modu_reader/service/ai/tools/repository/reading_history_repository.dart';
import 'package:modu_reader/service/ai/tools/repository/tag_repository.dart';
import 'package:modu_reader/service/registry/host_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/tools.dart';

/// Context object shared by AI tools so builders don't need long constructors.
class AiToolContext {
  AiToolContext({required this.ref});

  final WidgetRef ref;

  late final NotesRepository notesRepository = NotesRepository();
  late final BooksRepository booksRepository = BooksRepository();
  late final BookContentSearchRepository bookContentSearchRepository =
      BookContentSearchRepository(booksRepository: booksRepository);
  late final GroupsRepository groupsRepository = GroupsRepository();
  late final ReadingHistoryRepository readingHistoryRepository =
      ReadingHistoryRepository();
  late final TagRepository tagRepository = TagRepository();

  bool get isReading => ref.read(currentReadingProvider).isReading;
}

class AiToolDefinition {
  const AiToolDefinition({
    required this.id,
    required this.displayNameBuilder,
    required this.descriptionBuilder,
    required this.build,
  });

  final String id;
  final String Function(L10n l10n) displayNameBuilder;
  final String Function(L10n l10n) descriptionBuilder;
  final Tool Function(AiToolContext context) build;

  String displayName(L10n l10n) => displayNameBuilder(l10n);

  String description(L10n l10n) => descriptionBuilder(l10n);

  String displayNameOrDefault([L10n? l10n]) =>
      l10n == null ? id : displayName(l10n);

  String descriptionOrDefault([L10n? l10n]) =>
      l10n == null ? '' : description(l10n);
}

/// A tool registered with the app. Tools are built in only: plugins cannot
/// register executable tools in P2 (script tools arrive with a separate
/// permission in a later phase).
class AiToolEntry implements RegistryEntry {
  const AiToolEntry({
    required this.definition,
    this.owner = const RegistryOwner.builtIn(),
  });

  final AiToolDefinition definition;

  @override
  String get id => definition.id;

  @override
  RegistryDomain get domain => RegistryDomain.aiTool;

  @override
  final RegistryOwner owner;

  @override
  List<String> get aliases => const [];
}

class AiToolRegistry {
  AiToolRegistry(Iterable<AiToolDefinition> definitions) {
    for (final definition in definitions) {
      register(definition);
    }
  }

  /// Production table. Built-in ids are frozen: they are persisted in
  /// 'enabledAiTools', so a rename would silently disable a tool for existing
  /// users. Add entries, never rename them.
  static final AiToolRegistry instance = AiToolRegistry(_builtInDefinitions);

  /// Registry backing every lookup. Tests replace it with an injected instance
  /// and must restore it afterwards.
  static AiToolRegistry _current = instance;

  static AiToolRegistry get current => _current;

  @visibleForTesting
  static void useForTesting(AiToolRegistry registry) => _current = registry;

  @visibleForTesting
  static void resetForTesting() => _current = instance;

  final HostRegistry<AiToolEntry> registry =
      HostRegistry<AiToolEntry>(RegistryDomain.aiTool);

  void register(AiToolDefinition definition, {RegistryOwner? owner}) {
    registry.register(AiToolEntry(
      definition: definition,
      owner: owner ?? const RegistryOwner.builtIn(),
    ));
  }

  /// Built-in entries only, in registration order.
  List<AiToolDefinition> get definitions => [
        for (final entry in registry.all)
          if (entry.owner is BuiltInOwner) entry.definition,
      ];

  AiToolDefinition? byId(String id) => registry.resolve(id)?.definition;

  List<String> defaultEnabledToolIds() =>
      definitions.map((definition) => definition.id).toList(growable: false);

  /// Storage sanitiser: drops duplicates but **keeps unknown ids**, so a tool
  /// that is temporarily unavailable (disabled plugin, newer app version) does
  /// not lose its saved selection. Unknown ids are filtered when tools are
  /// built, never when they are read from storage.
  List<String> sanitizeIds(List<String> ids) => ids.toSet().toList(growable: false);

  List<Tool> buildTools(
    AiToolContext context,
    List<String> enabledIds,
  ) {
    final enabled = enabledIds.toSet();
    return definitions
        .where((definition) => enabled.contains(definition.id))
        .map((definition) => definition.build(context))
        .toList(growable: false);
  }

  String displayNameForId(String id, {L10n? l10n}) =>
      byId(id)?.displayNameOrDefault(l10n) ?? id;

  String descriptionForId(String id, {L10n? l10n}) =>
      byId(id)?.descriptionOrDefault(l10n) ?? '';

  static final List<AiToolDefinition> _builtInDefinitions = [
    calculatorToolDefinition,
    currentTimeToolDefinition,
    mindmapToolDefinition,
    bookContentSearchToolDefinition,
    bookshelfLookupToolDefinition,
    bookshelfOrganizeToolDefinition,
    notesSearchToolDefinition,
    readingHistoryToolDefinition,
    currentReadingMetadataToolDefinition,
    currentBookTocToolDefinition,
    currentChapterContentToolDefinition,
    chapterContentByHrefToolDefinition,
    tagsListToolDefinition,
    booksTagsListToolDefinition,
    applyBookTagsToolDefinition,
  ];
}
