import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/book_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/widgets/plugins/plugin_book_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/plugins/plugin_test_utils.dart';

class _Host extends PluginHost {
  _Host(this.manifest);
  final PluginManifest manifest;
  bool installed = true, runnable = true;
  @override
  PluginManifest? manifestFor(String id) => installed ? manifest : null;
  @override
  bool isScriptRunnable(String id) => installed && runnable;
}

void main() {
  late PrivateLibrary library;
  late _Host host;
  late RegisteredPluginBookAction action;
  final book = Book.mock()
      .copyWith(id: 42, filePath: 'not-downloaded.epub', md5: 'a' * 32);
  Future<bool>? pending;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    library = PrivateLibrary(preferences: Prefs().prefs)..setPluginActive(true);
    await library.unlock();
    final manifest = PluginManifest.parse(manifestJson(capabilities: [
      'ui:book-action',
      'library:private'
    ], contributes: [
      {
        'kind': 'bookAction',
        'schema': 1,
        'id': 'hide',
        'name': 'Hide',
        'command': 'privateLibrary.hide'
      }
    ]));
    host = _Host(manifest);
    action = RegisteredPluginBookAction(manifest.id,
        manifest.contributions.whereType<BookActionContribution>().single);
    pending = null;
  });
  tearDown(() {
    host.dispose();
    library.dispose();
  });

  bool available([RegisteredPluginBookAction? item]) =>
      isPluginBookActionAvailable(item ?? action,
          host: host, privateLibrary: library);

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
              onPressed: () => pending = runPluginBookAction(context,
                  item: action,
                  book: book,
                  host: host,
                  privateLibrary: library,
                  readBook: (_) async => book),
              child: const Text('Hide'));
        }))));
    await tester.runAsync(() => tester.tap(find.text('Hide')));
    await tester.pumpAndSettle();
  }

  test('only a registered action from an active enabled plugin is available',
      () async {
    expect(available(), true);
    host.installed = false;
    expect(available(), false);
    host.installed = true;
    host.runnable = false;
    expect(available(), false);
    host.runnable = true;
    library.setPluginActive(false);
    expect(available(), false);
    library.setPluginActive(true);
    await library.unlock();
    await library.setEnabled(false);
    expect(available(), false);
  });

  test('a forged or stale action cannot borrow another plugin permission', () {
    final forged = BookActionContribution.parse(
        kind: kBookActionContributionKind,
        schema: 1,
        id: 'other',
        index: 0,
        raw: {'name': 'Hide', 'command': 'privateLibrary.hide'});
    expect(
        available(RegisteredPluginBookAction(action.pluginId, forged)), false);
  });

  for (final lockAfter in [false, true]) {
    testWidgets('plugin setting chooses lock after hiding: $lockAfter',
        (tester) async {
      host.dispose();
      final manifest = PluginManifest.parse(manifestJson(capabilities: [
        'ui:book-action',
        'library:private',
        'library:private-control'
      ], contributes: [
        {
          'kind': 'bookAction',
          'schema': 1,
          'id': 'hide',
          'name': 'Hide',
          'command': 'privateLibrary.setPrivate',
          'private': true,
          'lockAfter': lockAfter,
          'when': 'public'
        }
      ]));
      host = _Host(manifest);
      action = RegisteredPluginBookAction(manifest.id,
          manifest.contributions.whereType<BookActionContribution>().single);
      expect(
          isPluginBookActionAvailable(action,
              host: host, privateLibrary: library, book: book),
          true);
      await mount(tester);
      expect(await tester.runAsync(() => pending!), true);
      expect(library.isPrivate(book), true);
      expect(library.unlocked, !lockAfter);
      if (lockAfter) await tester.runAsync(library.unlock);
      expect(
          isPluginBookActionAvailable(action,
              host: host, privateLibrary: library, book: book),
          false);
    });
  }

  testWidgets('plugin restore changes only the selected private book',
      (tester) async {
    await tester.runAsync(() => library.setBooksPrivate([book], true));
    host.dispose();
    final manifest = PluginManifest.parse(manifestJson(capabilities: [
      'ui:book-action',
      'library:private',
      'library:private-control'
    ], contributes: [
      {
        'kind': 'bookAction',
        'schema': 1,
        'id': 'restore',
        'name': 'Restore',
        'command': 'privateLibrary.setPrivate',
        'private': false,
        'when': 'private'
      }
    ]));
    host = _Host(manifest);
    action = RegisteredPluginBookAction(manifest.id,
        manifest.contributions.whereType<BookActionContribution>().single);
    await mount(tester);
    expect(await tester.runAsync(() => pending!), true);
    expect(library.isPrivate(book), false);
    expect(library.unlocked, true);
    expect(
        isPluginBookActionAvailable(action,
            host: host, privateLibrary: library, book: book),
        false);
  });

  testWidgets('hiding an unavailable local file marks only metadata and locks',
      (tester) async {
    expect(library.unlocked, true);
    expect(library.privateOnly, false);
    expect(library.isVisible(book), true);
    await mount(tester);
    expect(await tester.runAsync(() => pending!), true);
    expect(library.isPrivate(book), true);
    expect(library.unlocked, false);
    expect(library.isVisible(book), false);
    expect(library.privateOnly, false);
    expect(book.filePath, 'not-downloaded.epub');
  });

  testWidgets('cancelled authentication leaves the book public',
      (tester) async {
    library.lock();
    await mount(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => pending!), false);
    expect(library.isPrivate(book), false);
    expect(library.unlocked, false);
  });

  testWidgets(
      'a plugin disabled while the authentication dialog is open cannot hide',
      (tester) async {
    library.lock();
    await mount(tester);
    host.runnable = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => pending!), false);
    expect(library.isPrivate(book), false);
  });

  testWidgets('a plugin removed after a menu was built cannot execute',
      (tester) async {
    host.installed = false;
    await mount(tester);
    expect(await tester.runAsync(() => pending!), false);
    expect(library.isPrivate(book), false);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
