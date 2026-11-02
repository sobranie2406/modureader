import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/registry/host_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(AiToolRegistry.resetForTesting);

  test('built-in tool ids and order are unchanged', () {
    final ids = AiToolRegistry.current
        .defaultEnabledToolIds();
    // These ids are persisted in 'enabledAiTools'; renaming one would silently
    // disable that tool for every existing user.
    expect(ids, [
      'calculator',
      'current_time',
      'mindmap_draw',
      'book_content_search',
      'bookshelf_lookup',
      'bookshelf_organize',
      'notes_search',
      'reading_history',
      'current_reading_metadata',
      'current_book_toc',
      'current_chapter_content',
      'chapter_content_by_href',
      'tags_list',
      'books_tags_list',
      'apply_book_tags',
    ]);
    expect(AiToolRegistry.current.definitions, hasLength(ids.length));
  });

  test('sanitizeIds keeps unknown ids instead of dropping them', () {
    // A tool hidden by a newer/older build or a disabled plugin must keep its
    // saved selection so re-enabling restores it.
    expect(
      AiToolRegistry.current
          .sanitizeIds(['calculator', 'removed_tool', 'calculator', 'current_time']),
      ['calculator', 'removed_tool', 'current_time'],
    );
  });

  test('unknown ids resolve to null and keep their raw display name', () {
    expect(AiToolRegistry.current.byId('removed_tool'), isNull);
    expect(AiToolRegistry.current.displayNameForId('removed_tool'),
        'removed_tool');
    expect(AiToolRegistry.current.descriptionForId('removed_tool'), '');
  });

  test('an injected registry replaces the table without touching built-ins', () {
    final injected = AiToolRegistry(const []);
    AiToolRegistry.useForTesting(injected);
    expect(AiToolRegistry.current.definitions, isEmpty);
    expect(AiToolRegistry.current.defaultEnabledToolIds(), isEmpty);

    AiToolRegistry.resetForTesting();
    expect(AiToolRegistry.current.definitions, hasLength(15));
  });

  test('entries declare the aiTool domain and a built-in owner', () {
    final entry = AiToolRegistry.current.registry.byId('calculator')!;
    expect(entry.domain, RegistryDomain.aiTool);
    expect(entry.owner, const RegistryOwner.builtIn());
    expect(entry.aliases, isEmpty);
  });

  test('registers a plugin-owned tool with a namespaced id', () {
    final injected = AiToolRegistry(const []);
    const owner = PluginOwner('com.example.pack');
    injected.registry.register(AiToolEntry(
      definition: AiToolRegistry.current.definitions.first,
      owner: owner,
    ));
    expect(injected.registry.all, hasLength(1));
    injected.registry.removeAllOwnedBy(owner);
    expect(injected.registry.all, isEmpty);
  });
}