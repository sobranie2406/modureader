import 'package:modu_reader/models/selection_toolbar.dart';
import 'package:modu_reader/service/registry/host_registry.dart';
import 'package:modu_reader/service/registry/toolbar_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => ToolbarRegistry.useForTesting(null));

  test('the catalog covers every shipped action', () {
    final ids = ToolbarRegistry.instance.registry.all.map((e) => e.id).toList();
    final expected = [
      ...SelectionToolbarConfig.defaultItems.map((i) => i.id),
      ...SelectionToolbarConfig.defaultAnnotations.map((i) => i.id),
      ...SelectionToolbarConfig.templateItems.map((i) => i.id),
    ];
    expect(ids, expected);
    expect(ids.toSet(), hasLength(expected.length));
  });

  test('built-in actions are recognised by id and verb', () {
    expect(ToolbarRegistry.instance.matchesBuiltIn('query', 'query'), isTrue);
    expect(ToolbarRegistry.instance.matchesBuiltIn('query', 'copy'), isFalse);
    expect(ToolbarRegistry.instance.matchesBuiltIn('custom-preset-summary', 'aiCommand'),
        isTrue);
    expect(ToolbarRegistry.instance.matchesBuiltIn('custom-user-123', 'aiCommand'),
        isFalse, reason: 'user commands are not built-ins');
  });

  test('template presets are distinguishable from other built-ins', () {
    expect(ToolbarRegistry.instance.isTemplate('custom-preset-summary'), isTrue);
    expect(ToolbarRegistry.instance.isTemplate('query'), isFalse);
    expect(ToolbarRegistry.instance.isBuiltIn('query'), isTrue);
  });

  test('icon and skill id sets still cover every shipped item', () {
    for (final item in [
      ...SelectionToolbarConfig.defaultItems,
      ...SelectionToolbarConfig.defaultAnnotations,
      ...SelectionToolbarConfig.templateItems,
    ]) {
      if (item.icon.isNotEmpty) {
        expect(ToolbarRegistry.iconIds, contains(item.icon), reason: item.id);
      }
      expect(ToolbarRegistry.skillIds, contains(item.skillId), reason: item.id);
    }
  });

  test('a plugin entry cannot take a built-in id', () {
    expect(
      () => ToolbarRegistry.instance.registry.register(
        const ToolbarActionEntry(
          id: 'query',
          action: 'query',
          owner: PluginOwner('com.example.pack'),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('a user command is not registered but still validates', () {
    final config = SelectionToolbarConfig(items: [
      ...SelectionToolbarConfig.initialItems,
      const SelectionToolbarItem('custom-user-1', 'aiCommand',
          name: 'Mine', prompt: 'Explain {selection}'),
    ]);
    config.validate();
    expect(() => config.encode(), returnsNormally);
  });

  test('deleting a built-in action is still rejected', () {
    final config = SelectionToolbarConfig(
        items: SelectionToolbarConfig.initialItems
            .where((item) => item.id != 'query')
            .toList());
    expect(config.validate, throwsFormatException);
  });

  test('round-tripping an old configuration keeps its ids and order', () {
    // Golden: a configuration written before P2 must decode byte-identically.
    final original = SelectionToolbarConfig(
      items: [
        ...SelectionToolbarConfig.initialItems.reversed,
        const SelectionToolbarItem('custom-plugin:com.example.pack:explain',
            'aiCommand',
            name: 'Explain', prompt: 'Explain {selection}'),
      ],
    ).encode();
    final decoded = SelectionToolbarConfig.decode(original);
    expect(decoded.encode(), original);
  });
}