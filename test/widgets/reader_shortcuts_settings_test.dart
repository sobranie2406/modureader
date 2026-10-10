import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/reader_shortcuts.dart';
import 'package:anx_reader/page/settings_page/reader_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'scrollPagePercent': 93});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh'));
  });
  testWidgets(
      'capture multiple keys, report conflict, delete and confirm reset',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: const ReaderShortcutsSettings()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Add shortcut').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('Already assigned to'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(Prefs().readerShortcuts.actions()['1:j'], 'previous');
    final chip = find.widgetWithText(InputChip, 'Ctrl + J');
    expect(chip, findsOneWidget);
    tester.widget<InputChip>(chip).onDeleted!();
    await tester.pumpAndSettle();
    expect(Prefs().readerShortcuts.actions()['1:j'], isNull);
    final custom = Prefs().readerShortcuts;
    custom.bindings[ReaderAction.next]!.clear();
    Prefs().readerShortcuts = custom;
    // Reopen to check persistence and the reset confirmation.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: const ReaderShortcutsSettings()));
    await tester.pumpAndSettle();
    final restore = find.text('Restore default shortcuts');
    await tester.scrollUntilVisible(restore, 250);
    await tester.pumpAndSettle();
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(Prefs().readerShortcuts.bindings[ReaderAction.next], isEmpty);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore defaults'));
    await tester.pumpAndSettle();
    expect(
        Prefs().readerShortcuts.encode(), ReaderShortcuts.defaults().encode());
    expect(Prefs().prefs.getInt('scrollPagePercent'), 93);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Chinese narrow layout and Escape cancel leave bindings unchanged',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: const ReaderShortcutsSettings()));
    await tester.pumpAndSettle();
    expect(find.text('自定义按键'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '添加按键').first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        Prefs().readerShortcuts.encode(), ReaderShortcuts.defaults().encode());
    final restore = find.text('恢复默认按键');
    await tester.scrollUntilVisible(restore, 250);
    expect(find.text('朗读：播放 / 暂停'), findsOneWidget);
    expect(find.text('朗读：播放'), findsNothing);
    expect(find.text('朗读：暂停'), findsNothing);
    expect(restore, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
