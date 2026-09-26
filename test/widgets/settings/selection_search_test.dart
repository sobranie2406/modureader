import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/selection_search.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  Future<void> open(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(body: child),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('built-in search switches engines in place and retains the query',
      (tester) async {
    Uri? shown;
    await open(
        tester,
        SelectionSearchBrowser(
            text: '古文 & 注释',
            pageBuilder: (_, uri) {
              shown = uri;
              return const SizedBox.expand();
            }));
    expect(shown!.host, 'www.bing.com');
    expect(shown!.queryParameters['q'], '古文 & 注释');
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('百度百科').last);
    await tester.pumpAndSettle();
    expect(shown!.host, 'baike.baidu.com');
    expect(shown!.queryParameters['word'], '古文 & 注释');
    expect(Prefs().selectionSearchSettings.selectedId, 'baike');
    await tester.enterText(find.byType(TextField), '新词');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(shown!.queryParameters['word'], '新词');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'settings default is used by search and popup settings stay in sync',
      (tester) async {
    await open(tester, const SelectionSearchSettings());
    await tester.tap(find.text('百度'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionSearchSettings.selectedId, 'baidu');

    Uri? shown;
    await open(
        tester,
        SelectionSearchBrowser(
            text: '原来的选词',
            pageBuilder: (_, uri) {
              shown = uri;
              return const SizedBox.expand();
            }));
    expect(shown!.host, 'www.baidu.com');
    await tester.tap(find.byTooltip('搜索引擎设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(shown!.host, 'www.google.com');
    expect(shown!.queryParameters['q'], '原来的选词');
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom engine can be added, selected, edited and deleted',
      (tester) async {
    await open(tester, const SelectionSearchSettings());
    await tester.tap(find.text('添加自定义搜索引擎'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '我的搜索');
    await tester.enterText(
        find.byType(TextField).at(1), 'https://example.test/?q={query}');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionSearchSettings.custom.single.name, '我的搜索');
    await tester.ensureVisible(find.text('我的搜索'));
    await tester.tap(find.text('我的搜索'));
    await tester.pumpAndSettle();
    final selected = Prefs().selectionSearchSettings.selectedId;
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '新名称');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionSearchSettings.selectedId, selected);
    expect(Prefs().selectionSearchSettings.selected.name, '新名称');
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionSearchSettings.custom, isEmpty);
    expect(Prefs().selectionSearchSettings.selectedId, 'bing');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsafe custom URL stays in editor and is never saved',
      (tester) async {
    await open(tester, const SelectionSearchSettings());
    await tester.tap(find.text('添加自定义搜索引擎'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Bad');
    await tester.enterText(find.byType(TextField).at(1), 'javascript:{query}');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(Prefs().selectionSearchSettings.custom, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
