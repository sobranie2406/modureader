import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/page/settings_page/selection_toolbar.dart';
import 'package:anx_reader/widgets/context_menu/selection_action_toolbar.dart';
import 'package:anx_reader/widgets/context_menu/selection_toolbar_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget child, {double scale = 1}) => ProviderScope(
    child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          ...GlobalMaterialLocalizations.delegates
        ],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(body: child)));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  Finder key(String name) => find.byKey(ValueKey(name));
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find
        .descendant(
            of: key('selection-toolbar-scroll'),
            matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 180,
        scrollable: scrollable, maxScrolls: 100);
    await tester.pumpAndSettle();
  }

  testWidgets('settings expose templates disabled and persist switches',
      (tester) async {
    await tester.pumpWidget(app(const SelectionToolbarSettings()));
    await tester.pumpAndSettle();
    for (final template in SelectionToolbarConfig.templateItems) {
      await reveal(tester, key('toolbar-toggle-${template.id}'));
      expect(tester.widget<Switch>(key('toolbar-toggle-${template.id}')).value,
          false);
    }
    await reveal(tester, key('toolbar-toggle-custom-preset-explain'));
    await tester.tap(key('toolbar-toggle-custom-preset-explain'));
    await tester.pumpAndSettle();
    expect(
        Prefs()
            .selectionToolbar
            .items
            .firstWhere((i) => i.id == 'custom-preset-explain')
            .enabled,
        true);
    await reveal(tester, key('toolbar-toggle-copy'));
    await tester.tap(key('toolbar-toggle-copy'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.items.first.enabled, false);
    await reveal(tester, key('selection-toolbar-enabled'));
    await tester.tap(key('selection-toolbar-enabled'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.enabled, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag order persists and annotation order is independent',
      (tester) async {
    await tester.pumpWidget(app(const SelectionToolbarSettings()));
    await tester.pumpAndSettle();
    await reveal(tester, key('toolbar-item-copy'));
    await tester.pumpAndSettle();
    final handle = find.descendant(
        of: key('toolbar-item-copy'),
        matching: find.byType(ReorderableDragStartListener));
    final first = tester.getCenter(handle);
    final third = tester.getCenter(key('toolbar-item-translate'));
    expect(handle.hitTestable(), findsOneWidget);
    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    await gesture.moveTo(Offset(first.dx, third.dy));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveBy(const Offset(0, 1));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.items.take(3).map((i) => i.id),
        ['search', 'copy', 'translate']);
    expect(Prefs().selectionToolbar.annotations.first.id, 'delete');
    await reveal(tester, key('toolbar-item-delete'));
    final annotations =
        tester.widget<SliverReorderableList>(key('selection-annotation-order'));
    annotations.onReorderItem!(0, 3);
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.annotations.last.id, 'delete');
    expect(tester.takeException(), isNull);
  });

  testWidgets('long pressing a label also reorders without changing switches',
      (tester) async {
    await tester.pumpWidget(app(const SelectionToolbarSettings()));
    await tester.pumpAndSettle();
    await reveal(tester, key('toolbar-item-copy'));
    final label = find.descendant(
        of: key('toolbar-item-copy'),
        matching: find.byType(ReorderableDelayedDragStartListener));
    final first = tester.getCenter(label);
    final third = tester.getCenter(key('toolbar-item-translate'));
    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(Offset(first.dx, third.dy));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.items.take(3).map((i) => i.id),
        ['search', 'copy', 'translate']);
    expect(Prefs().selectionToolbar.items.first.enabled, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preset prompt, label and icon can be edited without enabling it',
      (tester) async {
    await tester.pumpWidget(app(const SelectionToolbarSettings()));
    await tester.pumpAndSettle();
    await reveal(tester, key('toolbar-edit-custom-preset-summary'));
    await tester.tap(key('toolbar-edit-custom-preset-summary'));
    await tester.pumpAndSettle();
    await tester.enterText(key('toolbar-name'), '一句话摘要');
    await tester.enterText(key('toolbar-prompt'), '用一句话概括 {selection}');
    await tester.ensureVisible(key('toolbar-icon-star'));
    await tester.tap(key('toolbar-icon-star'));
    await tester.tap(key('toolbar-editor-save'));
    await tester.pumpAndSettle();
    final saved = Prefs()
        .selectionToolbar
        .items
        .firstWhere((i) => i.id == 'custom-preset-summary');
    expect(saved.name, '一句话摘要');
    expect(saved.prompt, '用一句话概括 {selection}');
    expect(saved.icon, 'star');
    expect(saved.enabled, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new custom command validates required fields and restore keeps it',
      (tester) async {
    await tester.pumpWidget(app(const SelectionToolbarSettings()));
    await tester.pumpAndSettle();
    await tester.tap(key('toolbar-add-ai'));
    await tester.pumpAndSettle();
    await tester.tap(key('toolbar-editor-save'));
    await tester.pumpAndSettle();
    expect(find.text('请填写名称和提示词。'), findsOneWidget);
    await tester.enterText(key('toolbar-name'), '校对');
    await tester.enterText(key('toolbar-prompt'), '校对 {selection}，指出错字');
    expect(
        tester
            .widget<DropdownButtonFormField<SelectionAiScope>>(
                key('toolbar-ai-scope'))
            .initialValue,
        SelectionAiScope.selection);
    expect(tester.widget<CheckboxListTile>(key('toolbar-ai-web-search')).value,
        false);
    await tester.ensureVisible(key('toolbar-ai-scope'));
    await tester.tap(key('toolbar-ai-scope'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结合上下文').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('toolbar-ai-web-search'));
    await tester.tap(key('toolbar-ai-web-search'));
    await tester.pumpAndSettle();
    await tester.tap(key('toolbar-editor-save'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.items.last.name, '校对');
    expect(Prefs().selectionToolbar.items.last.scope, SelectionAiScope.context);
    expect(Prefs().selectionToolbar.items.last.webSearch, true);
    final ownId = Prefs().selectionToolbar.items.last.id;
    await reveal(tester, key('toolbar-restore'));
    await tester.tap(key('toolbar-restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '恢复默认'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.items.last.id, ownId);
    expect(
        Prefs()
            .selectionToolbar
            .items
            .where((i) => i.id.startsWith('custom-preset-'))
            .every((i) => !i.enabled),
        true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('palette validation is atomic; cancel changes nothing',
      (tester) async {
    await tester.pumpWidget(app(const SelectionToolbarSettings()));
    await tester.pumpAndSettle();
    await reveal(tester, key('toolbar-edit-colors'));
    await tester.tap(key('toolbar-edit-colors'));
    await tester.pumpAndSettle();
    final before = Prefs().selectionToolbar.encode();
    await tester.enterText(key('toolbar-name'), '我的颜色');
    await tester.enterText(key('toolbar-colors'), 'not-colour');
    await tester.tap(key('toolbar-editor-save'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.encode(), before);
    expect(find.textContaining('填写 1–20'), findsOneWidget);
    await tester.enterText(key('toolbar-colors'), '#00897B, FF8C00');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.encode(), before);
    await tester.tap(key('toolbar-edit-colors'));
    await tester.pumpAndSettle();
    await tester.enterText(key('toolbar-name'), '我的颜色');
    await tester.enterText(key('toolbar-colors'), '#00897B, FF8C00');
    await tester.tap(key('toolbar-editor-save'));
    await tester.pumpAndSettle();
    expect(Prefs().selectionToolbar.colors, ['00897B', 'FF8C00']);
    expect(Prefs().selectionToolbar.annotations.last.name, '我的颜色');
    expect(tester.takeException(), isNull);
  });

  for (final id in [
    'ai',
    'custom-preset-dictionary',
    'custom-preset-explain',
    'custom-preset-classical-chinese'
  ]) {
    testWidgets('$id exposes independent scope and optional online search',
        (tester) async {
      await tester.pumpWidget(app(const SelectionToolbarSettings()));
      await tester.pumpAndSettle();
      await reveal(tester, key('toolbar-edit-$id'));
      await tester.tap(key('toolbar-edit-$id'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<DropdownButtonFormField<SelectionAiScope>>(
                  key('toolbar-ai-scope'))
              .initialValue,
          SelectionAiScope.selection);
      expect(
          tester.widget<CheckboxListTile>(key('toolbar-ai-web-search')).value,
          false);
      await tester.ensureVisible(key('toolbar-ai-scope'));
      await tester.tap(key('toolbar-ai-scope'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('结合上下文').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('toolbar-ai-web-search'));
      await tester.tap(key('toolbar-ai-web-search'));
      await tester.pumpAndSettle();
      await tester.tap(key('toolbar-editor-save'));
      await tester.pumpAndSettle();
      final item = Prefs().selectionToolbar.items.firstWhere((i) => i.id == id);
      expect(item.scope, SelectionAiScope.context);
      expect(item.webSearch, true);
      expect(
          Prefs()
              .selectionToolbar
              .items
              .where((i) => i.id != id)
              .every((i) => !i.webSearch),
          true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('enabled classical translation dispatches from selection toolbar',
      (tester) async {
    final preset = SelectionToolbarConfig.templateItems.singleWhere(
        (item) => item.id == 'custom-preset-classical-chinese');
    SelectionToolbarItem? selected;
    final config = SelectionToolbarConfig(items: [
      preset.copyWith(enabled: true),
      ...SelectionToolbarConfig.initialItems.where((item) => item.id != preset.id),
    ]);
    await tester.pumpWidget(app(SelectionActionToolbar(
      items: config.availableItems(),
      visibleCount: 5,
      axis: Axis.horizontal,
      maxExtent: 600,
      onAction: (item) => selected = item,
      onSettings: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('文言文翻译'), findsOneWidget);
    await tester.tap(key('selection-action-${preset.id}'));
    expect(selected?.id, preset.id);
    expect(selected?.promptForSelection('学而时习之'), contains('现代汉语'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'small screen and enlarged text retain all settings without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const SelectionToolbarSettings(), scale: 1.5));
    await tester.pumpAndSettle();
    for (final id in [
      'copy',
      'custom-preset-dictionary',
      'custom-preset-points',
      'colors'
    ]) {
      await reveal(tester, key('toolbar-edit-$id'));
      await tester.pumpAndSettle();
      expect(key('toolbar-edit-$id').hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await reveal(tester, key('toolbar-edit-custom-preset-dictionary'));
    await tester.tap(key('toolbar-edit-custom-preset-dictionary'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final axis in Axis.values) {
    testWidgets('$axis menu respects order, overrides and overflow callbacks',
        (tester) async {
      final chosen = <String>[];
      final items = [
        SelectionToolbarConfig.defaultItems.last
            .copyWith(name: '海报', icon: 'star'),
        ...SelectionToolbarConfig.defaultItems.take(7)
      ];
      await tester.pumpWidget(app(Center(
          child: SelectionActionToolbar(
              items: items,
              visibleCount: 2,
              axis: axis,
              maxExtent: 300,
              onAction: (i) => chosen.add(i.id),
              onSettings: () => chosen.add('settings')))));
      await tester.pumpAndSettle();
      expect(find.text('海报'), findsOneWidget);
      expect(find.byIcon(selectionToolbarIcons['star']!), findsOneWidget);
      expect(key('selection-action-share'), findsOneWidget);
      expect(key('selection-action-search'), findsNothing);
      await tester.tap(key('selection-action-share'));
      await tester.tap(key('selection-toolbar-more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      await tester.tap(key('selection-toolbar-settings'));
      expect(chosen, ['share', 'search', 'settings']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('all disabled still leaves a settings button', (tester) async {
    await tester.pumpWidget(app(SelectionActionToolbar(
        items: const [],
        visibleCount: 5,
        axis: Axis.horizontal,
        maxExtent: 120,
        onAction: (_) {},
        onSettings: () {})));
    await tester.pumpAndSettle();
    expect(key('selection-toolbar-more'), findsNothing);
    expect(key('selection-toolbar-settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow in a reader overlay stays above annotation controls',
      (tester) async {
    final chosen = <String>[];
    late ModalRoute<dynamic> route;
    await tester.pumpWidget(app(Builder(builder: (context) {
      route = ModalRoute.of(context)!;
      return const SizedBox.shrink();
    })));
    await tester.pumpAndSettle();
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);
    final entry = OverlayEntry(
        builder: (_) => Positioned(
            left: 40,
            top: 120,
            child: Material(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              SelectionActionToolbar(
                  items: SelectionToolbarConfig.defaultItems,
                  visibleCount: 5,
                  axis: Axis.horizontal,
                  maxExtent: 350,
                  parentRoute: route,
                  onAction: (item) => chosen.add(item.id),
                  onSettings: () {}),
              GestureDetector(
                  onTap: () => chosen.add('annotation'),
                  child: Container(
                      key: const ValueKey('annotation-controls'),
                      width: 350,
                      height: 180,
                      color: Colors.red)),
            ]))));
    overlay.insert(entry);
    var removed = false;
    addTearDown(() {
      if (!removed) {
        entry.remove();
        entry.dispose();
      }
    });
    await tester.pumpAndSettle();
    await tester.tap(key('selection-toolbar-more'));
    await tester.pumpAndSettle();
    final target = find.text('AI');
    expect(
        tester
            .getRect(key('annotation-controls'))
            .contains(tester.getCenter(target)),
        isTrue);
    await tester.tap(target, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(chosen, ['ai']);
    expect(find.text('AI'), findsNothing);

    // An outside tap must dismiss without applying the annotation below it.
    await tester.tap(key('selection-toolbar-more'));
    await tester.pumpAndSettle();
    await tester.tapAt(
        tester.getTopLeft(key('annotation-controls')) + const Offset(8, 130));
    await tester.pumpAndSettle();
    expect(chosen, ['ai']);
    expect(find.text('AI'), findsNothing);

    // Android Back consumes the menu's local history, not the book's route.
    await tester.tap(key('selection-toolbar-more'));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), true);
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('AI'), findsNothing);
    expect(key('selection-toolbar-more'), findsOneWidget);
    expect(navigator.canPop(), false);

    // Removing a selection must also remove its open menu and Back handler.
    await tester.tap(key('selection-toolbar-more'));
    await tester.pumpAndSettle();
    entry.remove();
    entry.dispose();
    removed = true;
    await tester.pumpAndSettle();
    expect(find.text('AI'), findsNothing);
    expect(navigator.canPop(), false);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('many overflow templates remain reachable at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final chosen = <String>[];
      final items = [
        ...SelectionToolbarConfig.defaultItems,
        for (var i = 0; i < 24; i++)
          SelectionToolbarItem('custom-$i', 'aiCommand',
              name: '模板 $i', prompt: '解释 {selection}')
      ];
      await tester.pumpWidget(app(
          Center(
              child: SelectionActionToolbar(
                  items: items,
                  visibleCount: 1,
                  axis: Axis.horizontal,
                  maxExtent: 280,
                  onAction: (item) => chosen.add(item.id),
                  onSettings: () {})),
          scale: scale));
      await tester.pumpAndSettle();
      await tester.tap(key('selection-toolbar-more'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(key('selection-overflow-custom-23'), 200,
          scrollable: find.byType(Scrollable).last, maxScrolls: 30);
      await tester.pumpAndSettle();
      await tester.tap(key('selection-overflow-custom-23'));
      await tester.pumpAndSettle();
      expect(chosen, ['custom-23']);
      expect(tester.takeException(), isNull);
    });
  }
}
