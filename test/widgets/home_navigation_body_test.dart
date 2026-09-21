import 'dart:io';

import 'package:anx_reader/widgets/home_navigation_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:flutter_test/flutter_test.dart';

const _bar = ValueKey('bar');
const _viewport = ValueKey('viewport');
const _last = ValueKey('last-control');

Widget shell({
  required Widget Function(ScrollController) page,
  double bottom = 0,
  double scale = 1,
  double keyboard = 0,
  bool compact = true,
  bool autoHide = false,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 740),
          padding: EdgeInsets.only(bottom: keyboard > 0 ? 0 : bottom),
          viewPadding: EdgeInsets.only(bottom: bottom),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(scale),
        ),
        child: Builder(builder: (context) {
          final visible = compact && keyboard == 0;
          return Scaffold(
            body: BottomBar(
              width: 330,
              offset: HomeNavigationMetrics.barOffset,
              hideOnScroll: autoHide,
              showIcon: visible,
              body: (_, controller) => HomeNavigationBody(
                hasBottomBar: visible,
                child: SizedBox.expand(key: _viewport, child: page(controller)),
              ),
              child: Visibility(
                visible: visible,
                maintainState: true,
                child: SizedBox(
                  key: _bar,
                  height: HomeNavigationMetrics.barHeightFor(context),
                  child: BottomNavigationBar(
                    type: BottomNavigationBarType.fixed,
                    selectedFontSize: 12,
                    items: const [
                      BottomNavigationBarItem(
                          icon: Icon(Icons.book), label: '书架'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.cloud), label: '远程书库'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.bar_chart), label: '统计'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.star), label: 'AI'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.note), label: '笔记'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.settings), label: '设置'),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final bottom in [0.0, 24.0, 48.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      for (final layout in ['grid', 'list', 'fixed']) {
        testWidgets('$layout clears bar: bottom=$bottom scale=$scale',
            (tester) async {
          phone(tester);
          late ScrollController controller;
          var taps = 0;
          await tester.pumpWidget(shell(
            bottom: bottom,
            scale: scale,
            page: (supplied) {
              controller = supplied;
              final last = TextButton(
                key: _last,
                onPressed: () => taps++,
                child: const Text('操作'),
              );
              if (layout == 'fixed') {
                return Column(children: [const Spacer(), last]);
              }
              final children = [
                for (var i = 0; i < 60; i++) const SizedBox(height: 50),
                last,
              ];
              if (layout == 'grid') {
                return GridView.count(
                  controller: controller,
                  crossAxisCount: 3,
                  children: children,
                );
              }
              return ListView(controller: controller, children: children);
            },
          ));
          await tester.pumpAndSettle();
          if (layout != 'fixed') {
            controller.jumpTo(controller.position.maxScrollExtent);
            await tester.pumpAndSettle();
          }
          final barTop = tester.getRect(find.byKey(_bar)).top;
          expect(tester.getRect(find.byKey(_viewport)).bottom,
              lessThanOrEqualTo(barTop - HomeNavigationMetrics.contentGap));
          expect(tester.getRect(find.byKey(_last)).bottom,
              lessThanOrEqualTo(barTop - HomeNavigationMetrics.contentGap));
          expect(
              MediaQuery.paddingOf(tester.element(find.byKey(_viewport)))
                  .bottom,
              0);
          await tester.tap(find.byKey(_last));
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('keyboard hides bar without resetting input or double insets',
      (tester) async {
    phone(tester);
    final input = TextEditingController();
    addTearDown(input.dispose);
    Widget page(ScrollController _) => Column(children: [
          const Spacer(),
          TextField(key: _last, controller: input),
        ]);
    await tester.pumpWidget(shell(page: page, bottom: 24));
    await tester.enterText(find.byKey(_last), '保留输入');
    await tester.pumpWidget(shell(page: page, bottom: 24, keyboard: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(_bar), findsNothing);
    expect(input.text, '保留输入');
    expect(tester.getRect(find.byKey(_viewport)).bottom, 440);
    expect(tester.getRect(find.byKey(_last)).bottom, lessThanOrEqualTo(440));
    await tester.pumpWidget(shell(page: page, bottom: 24));
    await tester.pumpAndSettle();
    expect(find.byKey(_bar), findsOneWidget);
    expect(input.text, '保留输入');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rail layout has no bottom-bar gap and retains system safe area',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(shell(
      page: (_) => const SizedBox(),
      bottom: 24,
      compact: false,
    ));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_viewport)).height, 740);
    expect(
        MediaQuery.paddingOf(tester.element(find.byKey(_viewport))).bottom, 24);
    expect(find.byKey(_bar), findsNothing);
  });

  testWidgets('auto-hide/reveal keeps viewport stable and controls reachable',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(shell(
      autoHide: true,
      bottom: 48,
      page: (controller) => ListView.builder(
        controller: controller,
        itemCount: 80,
        itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$i')),
      ),
    ));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byKey(_viewport));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_viewport)), viewport);
    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_viewport)), viewport);
    expect(
        viewport.bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(_bar)).top -
            HomeNavigationMetrics.contentGap));
    expect(tester.takeException(), isNull);
  });

  test('production home wraps all compact pages, not only settings', () {
    final source = File('lib/page/home_page.dart').readAsStringSync();
    expect(source, contains('body: (_, controller) => HomeNavigationBody('));
    expect(source, contains('hasBottomBar: !keyboardOpen'));
    expect(source, contains('visible: !keyboardOpen'));
    expect(source, isNot(contains('bottomContentInset:')));
  });
}
