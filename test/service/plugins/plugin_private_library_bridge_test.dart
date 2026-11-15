import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_private_library_bridge.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

class _Host extends PluginHost {
  _Host({super.development}) : manifest = createManifest();
  PluginManifest manifest;
  static PluginManifest createManifest() => PluginManifest.parse(
          manifestJson(capabilities: [
            'script:run',
            'library:private',
            'library:private-control'
          ], contributes: []),
          allowedCapabilities: {
            ...kP1SupportedCapabilities,
            'library:private-control'
          });
  @override
  PluginManifest? manifestFor(String id) => manifest;
  @override
  bool isScriptRunnable(String id) => true;
  void reload() {
    manifest = createManifest();
    notifyListeners();
  }
}

void main() {
  late _Host host;
  late PrivateLibrary library;
  late BuildContext context;
  bool current = true;
  final selected = Book.mock().copyWith(
      id: 42,
      title: 'Selected book',
      md5: 'selected',
      filePath: 'selected.epub');
  final other = Book.mock().copyWith(
      id: 43, title: 'Other book', md5: 'other', filePath: 'other.epub');
  Matcher failure(String code) =>
      isA<PluginScriptFailure>().having((error) => error.code, 'code', code);

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    library = PrivateLibrary(preferences: Prefs().prefs)..setPluginActive(true);
    await library.unlock();
    host = _Host();
    current = true;
  });
  tearDown(() {
    host.dispose();
    library.dispose();
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Reader'));
    })));
  }

  PluginPrivateLibraryBridge bridge(
      {Book? book,
      PrivateLibraryBookPicker? picker,
      Future<Book> Function(int)? readBook}) {
    final value = PluginPrivateLibraryBridge(
        context: context,
        host: host,
        pluginId: host.manifest.id,
        isCurrent: () => current,
        book: book,
        library: library,
        pickBooks: picker,
        readBook:
            readBook ?? ((id) async => id == selected.id ? selected : other));
    addTearDown(value.dispose);
    return value;
  }

  testWidgets('state exposes only safe flags and validates method arguments',
      (tester) async {
    await mount(tester);
    final api = bridge();
    final state = await api.call('privateLibrary.state', {}) as Map;
    expect(state.keys.toSet(), {
      'active',
      'enabled',
      'unlocked',
      'hasPin',
      'privateOnly',
      'autoImport',
      'lockAfterHide'
    });
    expect(state['lockAfterHide'], true);
    for (final entry in {
      'privateLibrary.state': {
        'bookIds': [42]
      },
      'privateLibrary.updateOptions': {'salt': 'secret'},
      'privateLibrary.selectBooks': {'limit': 101},
      'privateLibrary.setPrivate': {
        'bookIds': [42],
        'private': 'true'
      },
    }.entries) {
      await expectLater(
          api.call(entry.key, entry.value), throwsA(failure('permission')));
    }
  });

  testWidgets('a script cannot mark books without a native or bound selection',
      (tester) async {
    await mount(tester);
    final api = bridge();
    await expectLater(
        api.call('privateLibrary.setPrivate', {
          'bookIds': [selected.id],
          'private': true
        }),
        throwsA(failure('permission')));
    expect(library.isPrivate(selected), false);
    expect(api.didCommit, false);
  });

  testWidgets('the bound book can be marked and unmarked without implicit lock',
      (tester) async {
    await mount(tester);
    final api = bridge(book: selected);
    await tester.runAsync(() => api.call('privateLibrary.setPrivate', {
          'bookIds': [selected.id],
          'private': true
        }));
    expect(library.isPrivate(selected), true);
    expect(library.unlocked, true);
    expect(api.didCommit, true);
    await tester.runAsync(() => api.call('privateLibrary.setPrivate', {
          'bookIds': [selected.id],
          'private': false
        }));
    expect(library.isPrivate(selected), false);
    expect(library.canSyncBook(selected), true);
  });

  testWidgets(
      'native selection grants only chosen books and locks redact output',
      (tester) async {
    await mount(tester);
    await tester.runAsync(() => library.setBooksPrivate([selected], true));
    final api = bridge(
        picker: (
                {required isCurrent,
                privateOnly,
                required multiple,
                required limit}) async =>
            [selected]);
    final summaries = await api.call('privateLibrary.selectBooks', {}) as List;
    expect(summaries.single, {
      'id': selected.id,
      'title': selected.title,
      'author': selected.author,
      'private': true
    });
    expect(api.exposedBooks.single.id, selected.id);
    expect(api.canReadExposedData, true);
    await expectLater(
        api.call('privateLibrary.setPrivate', {
          'bookIds': [other.id],
          'private': true
        }),
        throwsA(failure('permission')));
    library.lock();
    expect(api.canReadExposedData, false);
    await library.unlock();
    expect(api.canReadExposedData, false);
    await expectLater(
        api.call('privateLibrary.setPrivate', {
          'bookIds': [selected.id],
          'private': false
        }),
        throwsA(failure('cancelled')));
  });

  testWidgets(
      'explicit lockAfter acknowledges a commit before cancelling access',
      (tester) async {
    await mount(tester);
    final api = bridge(book: selected);
    final result =
        await tester.runAsync(() => api.call('privateLibrary.setPrivate', {
              'bookIds': [selected.id],
              'private': true,
              'lockAfter': true
            }));
    expect(result, {'updated': 1});
    expect(api.didCommit, true);
    expect(library.unlocked, false);
    expect(library.isPrivate(selected), true);
  });

  testWidgets('same-version reload invalidates a late native picker',
      (tester) async {
    await mount(tester);
    final picker = Completer<List<Book>?>();
    final api = bridge(
        picker: (
                {required isCurrent,
                privateOnly,
                required multiple,
                required limit}) =>
            picker.future);
    final request = api.call('privateLibrary.selectBooks', {});
    final rejected = expectLater(request, throwsA(failure('cancelled')));
    host.reload();
    picker.complete([selected]);
    await rejected;
    expect(api.exposedBooks, isEmpty);
    expect(library.isPrivate(selected), false);
  });

  testWidgets(
      'a late book lookup cannot write after cancellation or replacement',
      (tester) async {
    await mount(tester);
    final lookup = Completer<Book>();
    final api = bridge(book: selected, readBook: (_) => lookup.future);
    final request = api.call('privateLibrary.setPrivate', {
      'bookIds': [selected.id],
      'private': true
    });
    final rejected = expectLater(request, throwsA(failure('cancelled')));
    current = false;
    lookup.complete(selected);
    await rejected;
    expect(library.isPrivate(selected), false);
    expect(api.didCommit, false);
    current = true;
    final replaced = bridge(
        book: selected,
        readBook: (_) async => selected.copyWith(filePath: 'replacement.epub'));
    await expectLater(
        replaced.call('privateLibrary.setPrivate', {
          'bookIds': [selected.id],
          'private': true
        }),
        throwsA(failure('permission')));
  });

  testWidgets('development option changes never persist or replace real marks',
      (tester) async {
    await mount(tester);
    host.dispose();
    host = _Host(development: true);
    await tester.runAsync(() => library.setBooksPrivate([selected], true));
    final saved = Prefs().prefs.getString(PrivateLibrary.storageKey);
    final api = bridge();
    await api.call('privateLibrary.updateOptions',
        {'privateOnly': true, 'autoImport': true, 'lockAfterHide': false});
    expect(library.privateOnly, true);
    expect(library.storedPolicyOptions['privateOnly'], false);
    expect(Prefs().prefs.getString(PrivateLibrary.storageKey), saved);
    library.clearOptionsOverlay(host);
    expect(library.privateOnly, false);
    expect(library.isPrivate(selected), true);
  });

  testWidgets(
      'revoking the owner dismisses native authentication without unlock',
      (tester) async {
    await mount(tester);
    library.lock();
    final api = bridge();
    final request =
        api.call('privateLibrary.updateOptions', {'autoImport': true});
    final rejected = expectLater(request, throwsA(failure('cancelled')));
    await tester.pumpAndSettle();
    expect(find.text('Unlock private library'), findsOneWidget);
    host.reload();
    await tester.pumpAndSettle();
    await rejected;
    expect(library.unlocked, false);
    expect(library.autoImport, false);
    expect(find.text('Unlock private library'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
