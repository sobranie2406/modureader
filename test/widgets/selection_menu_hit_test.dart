import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/widgets/context_menu/context_menu.dart';
import 'package:modu_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:modu_reader/widgets/context_menu/selection_action_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final axis in Axis.values) {
    testWidgets('$axis menu blank space passes handle drags to the reader',
        (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var readerDrags = 0;
      var menuClosed = 0;
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(
            body: Stack(children: [
          Positioned.fill(
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (_) => readerDrags++,
            child: const SizedBox.expand(),
          )),
          ReaderContextMenuOverlay(
            axis: axis,
            selectionRect: const Rect.fromLTWH(0, 750, 400, 20),
            viewportRect: const Rect.fromLTWH(0, 0, 400, 850),
            annoContent: '测试正文',
            annoCfi: 'epubcfi(/6/4!/4/2,/1:0,/1:4)',
            annoId: null,
            annotationIds: const [],
            bookId: 7,
            footnote: false,
            allowAnnotations: true,
            decoration: const BoxDecoration(color: Colors.green),
            onClose: () => menuClosed++,
            menuConstraints:
                const BoxConstraints(maxWidth: 350, maxHeight: 550),
            initialPosition: Offset.zero,
            initialReverse: false,
            showTranslationDefault: false,
            horizontalMargin: 16,
            verticalMargin: 16,
            gap: 32,
            initialBottomInset: 0,
          ),
        ])),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final area = tester.getRect(find.byType(ExcerptMenu));
      final buttons = tester.getRect(find.byType(SelectionActionToolbar));
      final point = axis == Axis.horizontal
          ? Offset(area.right - 8, buttons.center.dy)
          : Offset(buttons.center.dx, area.bottom - 8);
      expect(buttons.contains(point), false,
          reason: 'The landing-page handle sits outside the painted buttons');
      for (final interceptor in find.byType(PointerInterceptor).evaluate()) {
        expect(
            tester.getRect(find.byWidget(interceptor.widget)).contains(point),
            false,
            reason: 'Native interceptors must not cover blank layout');
      }
      await tester.dragFrom(
          point,
          axis == Axis.horizontal
              ? const Offset(0, -60)
              : const Offset(-60, 0));
      expect(readerDrags, greaterThan(0),
          reason:
              'Transparent menu layout must not swallow the handle gesture');
      expect(menuClosed, 0);

      final before = readerDrags;
      await tester.dragFrom(buttons.center, const Offset(0, -60));
      expect(readerDrags, before,
          reason: 'Visible menu surfaces must still shield the reader');
      await tester.tap(find.byKey(const ValueKey('selection-action-copy')));
      await tester.pumpAndSettle();
      expect(copied, '测试正文');
      expect(menuClosed, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
