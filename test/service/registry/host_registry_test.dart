import 'package:anx_reader/service/registry/host_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class _Entry implements RegistryEntry {
  const _Entry({
    required this.id,
    required this.domain,
    this.aliases = const [],
    this.owner = const RegistryOwner.builtIn(),
  });

  @override
  final String id;

  @override
  final RegistryDomain domain;

  @override
  final RegistryOwner owner;

  @override
  final List<String> aliases;
}

void main() {
  late HostRegistry<_Entry> registry;

  setUp(() => registry = HostRegistry<_Entry>(RegistryDomain.aiTool));

  test('registers entries and resolves by id', () {
    registry.register(const _Entry(id: 'calculator', domain: RegistryDomain.aiTool));
    expect(registry.byId('calculator')?.id, 'calculator');
    expect(registry.resolve('calculator')?.id, 'calculator');
    expect(registry.resolve('missing'), isNull);
    expect(registry.all, hasLength(1));
  });

  test('resolves aliases to the canonical entry', () {
    registry.register(const _Entry(
      id: 'microsoftApi',
      domain: RegistryDomain.aiTool,
      aliases: ['microsoft'],
    ));
    expect(registry.resolve('microsoft')?.id, 'microsoftApi');
    // The alias does not become a separate entry.
    expect(registry.all, hasLength(1));
    expect(registry.byId('microsoft'), isNull);
  });

  test('rejects duplicate ids and conflicting aliases', () {
    registry.register(const _Entry(id: 'calculator', domain: RegistryDomain.aiTool));
    expect(
      () => registry.register(
          const _Entry(id: 'calculator', domain: RegistryDomain.aiTool)),
      throwsA(isA<StateError>()),
    );
    expect(
      () => registry.register(const _Entry(
          id: 'other', domain: RegistryDomain.aiTool, aliases: ['calculator'])),
      throwsA(isA<StateError>()),
    );
    expect(
      () => registry.register(const _Entry(
          id: 'second', domain: RegistryDomain.aiTool, aliases: ['calculator'])),
      throwsA(isA<StateError>()),
    );
    // An alias must not repeat within one entry or equal its own id.
    expect(
      () => registry.register(const _Entry(
          id: 'third', domain: RegistryDomain.aiTool, aliases: ['x', 'x'])),
      throwsA(isA<StateError>()),
    );
    expect(
      () => registry.register(const _Entry(
          id: 'fourth', domain: RegistryDomain.aiTool, aliases: ['fourth'])),
      throwsA(isA<StateError>()),
    );
  });

  test('a new id may not shadow an existing alias', () {
    // Otherwise the alias would silently start resolving to the new entry and
    // the token's old meaning would be lost without any error.
    registry.register(const _Entry(
        id: 'microsoftApi', domain: RegistryDomain.aiTool, aliases: ['microsoft']));
    expect(
      () => registry.register(
          const _Entry(id: 'microsoft', domain: RegistryDomain.aiTool)),
      throwsA(isA<StateError>()),
    );
    expect(registry.resolve('microsoft')?.id, 'microsoftApi');
  });

  test('rejects entries from another domain', () {
    expect(
      () => registry.register(
          const _Entry(id: 'wrong', domain: RegistryDomain.translate)),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('only the owner may unregister, so built-ins are undeletable', () {
    const plugin = PluginOwner('com.example.pack');
    registry.register(const _Entry(id: 'builtin', domain: RegistryDomain.aiTool));
    registry.register(const _Entry(
        id: 'plugin:com.example.pack:x',
        domain: RegistryDomain.aiTool,
        owner: plugin));

    expect(registry.unregister('builtin', owner: plugin), isFalse);
    expect(registry.unregister('plugin:com.example.pack:x',
        owner: const RegistryOwner.builtIn()), isFalse);
    expect(registry.all, hasLength(2));

    expect(registry.unregister('plugin:com.example.pack:x', owner: plugin), isTrue);
    expect(registry.all, hasLength(1));
  });

  test('removeAllOwnedBy removes only that owner and its aliases', () {
    const plugin = PluginOwner('com.example.pack');
    registry.register(const _Entry(
        id: 'plugin:com.example.pack:a',
        domain: RegistryDomain.aiTool,
        aliases: ['old-a'],
        owner: plugin));
    registry.register(const _Entry(id: 'builtin', domain: RegistryDomain.aiTool));

    registry.removeAllOwnedBy(plugin);

    expect(registry.all.map((entry) => entry.id), ['builtin']);
    expect(registry.resolve('old-a'), isNull);
  });

  test('notifies listeners on registration and removal', () {
    var calls = 0;
    void listener() => calls++;
    registry.addListener(listener);

    registry.register(const _Entry(id: 'calculator', domain: RegistryDomain.aiTool));
    expect(calls, 1);

    registry.removeAllOwnedBy(const RegistryOwner.builtIn());
    expect(calls, 2);

    registry.removeListener(listener);
    registry.register(const _Entry(id: 'currentTime', domain: RegistryDomain.aiTool));
    expect(calls, 2);
  });
}
