import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/page/settings_page/private_library_page.dart';
import 'package:modu_reader/service/private_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrivateLibrary library;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    library = PrivateLibrary(preferences: Prefs().prefs)..setPluginActive(true);
  });
  tearDown(() {
    library.dispose();
    PrivateLibrary.instance.setPluginActive(false);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [L10n.delegate],
        supportedLocales: L10n.supportedLocales,
        home: PrivateLibraryPage(library: library)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'native unlocking and cancellation keep dialog controllers alive through exit',
      (tester) async {
    await open(tester);
    expect(
        find.byKey(const ValueKey('private-library-enabled')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('private-library-unlock')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(library.unlocked, false);
    await tester.tap(find.byKey(const ValueKey('private-library-unlock')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(library.unlocked, true);
    expect(find.text('Manage private books'), findsOneWidget);
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(library.hasPin, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'deactivation cancel retains marks and confirmation authorizes cleanup',
      (tester) async {
    await tester.runAsync(() async {
      await library.unlock();
      await library.setBooksPrivate(
          [Book.mock().copyWith(filePath: 'private.epub')], true);
    });
    bool? allowed;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () {
                  library
                      .authorizeDeactivate(context)
                      .then((value) => allowed = value);
                },
                child: const Text('Deactivate')))));
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(library.hasPrivateBooks, true);
    expect(allowed, false);
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disable'));
    await tester.pumpAndSettle();
    expect(allowed, true);
    expect(library.hasPrivateBooks, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mounted reading route removes content again when locked',
      (tester) async {
    final global = PrivateLibrary.instance;
    global.setPluginActive(true);
    final book = Book.mock().copyWith(filePath: 'private.epub');
    await tester.runAsync(() async {
      await global.unlock();
      await global.setBooksPrivate([book], true);
    });
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
        home: PrivateBookGate(
            book: book,
            builder: (_) {
              builds++;
              return const Text('PRIVATE BODY');
            })));
    expect(find.text('PRIVATE BODY'), findsOneWidget);
    global.lock();
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE BODY'), findsNothing);
    expect(builds, 1);
    global.setPluginActive(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('private-library-unlock')), findsNothing);
    expect(find.text('PRIVATE BODY'), findsNothing);
  });

  for (final popup in ['sheet', 'adjustable', 'nested settings']) {
    testWidgets('locking clears $popup above its private owner route',
        (tester) async {
      final global = PrivateLibrary.instance;
      global.setPluginActive(true);
      final book = Book.mock().copyWith(filePath: 'private.epub');
      await tester.runAsync(() async {
        await global.unlock();
        await global.setBooksPrivate([book], true);
      });
      await tester.pumpWidget(MaterialApp(
          home: PrivateBookGate(
              book: book,
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () {
                        if (popup == 'sheet') {
                          showModalBottomSheet<void>(
                              context: context,
                              builder: (_) => const Text('PRIVATE POPUP'));
                        } else {
                          Navigator.of(context).push(RawDialogRoute<void>(
                              pageBuilder: (context, _, __) => Center(
                                  child: TextButton(
                                      onPressed: popup == 'nested settings'
                                          ? () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                  builder: (_) => const Scaffold(
                                                      body: Text(
                                                          'PRIVATE SETTINGS'))))
                                          : null,
                                      child: const Text('PRIVATE POPUP')))));
                        }
                      },
                      child: const Text('Open private popup'))))));
      await tester.tap(find.text('Open private popup'));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE POPUP'), findsOneWidget);
      if (popup == 'nested settings') {
        await tester.tap(find.text('PRIVATE POPUP'));
        await tester.pumpAndSettle();
        expect(find.text('PRIVATE SETTINGS'), findsOneWidget);
      }
      global.lock();
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE POPUP'), findsNothing);
      expect(find.text('PRIVATE SETTINGS'), findsNothing);
      expect(
          find.byKey(const ValueKey('private-library-unlock')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
