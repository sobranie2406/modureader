import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/page/settings_page/private_library_page.dart';
import 'package:modu_reader/service/private_library.dart';

class _PendingUnlock extends PrivateLibrary {
  _PendingUnlock(SharedPreferences prefs) : super(preferences: prefs);
  final result = Completer<bool>();
  int cancellations = 0;
  @override
  bool get hasPin => true;
  @override
  Future<bool> unlock([String pin = '']) => result.future;
  @override
  void cancelPendingAuthentication() {
    cancellations++;
    super.cancelPendingAuthentication();
  }
}

class _PendingPin extends PrivateLibrary {
  _PendingPin(SharedPreferences prefs) : super(preferences: prefs);
  final result = Completer<void>();
  int cancellations = 0;
  @override
  Future<void> setPin(String? pin) => result.future;
  @override
  void cancelPendingAuthentication() {
    cancellations++;
    super.cancelPendingAuthentication();
  }
}

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
      'policy-aware plugins keep only the native authentication controls',
      (tester) async {
    await tester.runAsync(() => library.unlock());
    await tester.pumpWidget(MaterialApp(
        home: PrivateLibraryPage(library: library, showPolicyOptions: false)));
    await tester.pumpAndSettle();
    expect(find.text('Authentication'), findsOneWidget);
    expect(find.text('After unlocking'), findsNothing);
    expect(find.text('Make new imports private'), findsNothing);
    expect(find.text('Manage private books'), findsNothing);
    expect(find.text('Set'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'native book selection grants explicit choices and closes on lock',
      (tester) async {
    final public = Book.mock().copyWith(id: 1, title: 'Public title');
    final secret = Book.mock().copyWith(
        id: 2,
        title: 'Private title',
        md5: 'private',
        filePath: 'private.epub');
    await tester.runAsync(() async {
      await library.unlock();
      await library.setBooksPrivate([secret], true);
    });
    List<Book>? selected;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () => selectPrivateLibraryBooks(context,
                      library: library,
                      isCurrent: () => true,
                      privateOnly: true,
                      multiple: false,
                      loadBooks: () async => [public, secret])
                  .then((value) => selected = value),
              child: const Text('Select')));
    })));
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Public title'), findsNothing);
    expect(find.text('Private title'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('private-select-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('private-select-confirm')));
    await tester.pumpAndSettle();
    expect(selected?.single.id, 2);
    selected = null;
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Private title'), findsOneWidget);
    library.lock();
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Private title'), findsNothing);
    expect(find.text('Select'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy development settings use only a temporary option overlay',
      (tester) async {
    await tester.runAsync(() => library.unlock());
    final owner = Object();
    final saved = Prefs().prefs.getString(PrivateLibrary.storageKey);
    await tester.pumpWidget(MaterialApp(
        home: PrivateLibraryPage(library: library, optionsOwner: owner)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private only'));
    await tester.pumpAndSettle();
    expect(library.privateOnly, true);
    expect(library.storedPolicyOptions['privateOnly'], false);
    expect(Prefs().prefs.getString(PrivateLibrary.storageKey), saved);
    library.clearOptionsOverlay(owner);
    await tester.pumpAndSettle();
    expect(library.privateOnly, false);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets(
      'PIN verification shows progress and cancellation ignores its late result',
      (tester) async {
    final pending = _PendingUnlock(Prefs().prefs)..setPluginActive(true);
    addTearDown(pending.dispose);
    bool? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showPrivateLibraryUnlock(context, pending)
                    .then((value) => result = value),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('private-library-pin')), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, false);
    expect(pending.cancellations, 1);
    pending.result.complete(true);
    await tester.pumpAndSettle();
    expect(result, false);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cancelling PIN creation preserves its settings route after a late completion',
      (tester) async {
    final pending = _PendingPin(Prefs().prefs)..setPluginActive(true);
    addTearDown(pending.dispose);
    await tester.runAsync(() => pending.unlock());
    await tester
        .pumpWidget(MaterialApp(home: PrivateLibraryPage(library: pending)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(pending.cancellations, 1);
    pending.result.complete();
    await tester.pumpAndSettle();
    expect(find.text('Manage private books'), findsOneWidget);
    expect(find.text('Could not save. Try again.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a failed PIN worker restores the unlock controls without exposing its error',
      (tester) async {
    final pending = _PendingUnlock(Prefs().prefs)..setPluginActive(true);
    addTearDown(pending.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showPrivateLibraryUnlock(context, pending),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('private-library-pin')), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pump();
    pending.result.completeError(StateError('PRIVATE_PIN_SECRET'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Unlock'))
            .onPressed,
        isNotNull);
    expect(find.text('Could not unlock. Try again.'), findsOneWidget);
    expect(find.textContaining('PRIVATE_PIN_SECRET'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
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
