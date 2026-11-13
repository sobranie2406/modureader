import 'dart:async';

import 'package:modu_reader/widgets/reading_page/harmony_reader_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('modu/reader_cutout');
  const back = Key('back');
  late List<num> nativeInsets;
  late int requests;

  setUp(() {
    nativeInsets = [0, 120, 0, 0];
    requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getInsets');
      requests++;
      return nativeInsets;
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Widget reader({bool harmony = true, EdgeInsets padding = EdgeInsets.zero}) =>
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(devicePixelRatio: 2, padding: padding),
            child: Stack(children: [
              Builder(
                  builder: (context) =>
                      Text('page inset ${MediaQuery.paddingOf(context).top}')),
              Column(children: [
                HarmonyReaderToolbar(
                  enabled: harmony,
                  child: AppBar(
                    leading: IconButton(
                        key: back,
                        onPressed: () {},
                        icon: const Icon(Icons.arrow_back)),
                    title: const Text('Book title'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );

  testWidgets(
      'immersive Harmony toolbar avoids physical cutout only in overlay',
      (tester) async {
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(tester.getTopLeft(find.byKey(back)).dy, greaterThanOrEqualTo(60));
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 60);
    expect(find.text('page inset 0.0'), findsOneWidget);
  });

  testWidgets('other platforms do not call native channel or change geometry',
      (tester) async {
    await tester.pumpWidget(reader(harmony: false));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
  });

  testWidgets('existing safe area is not added twice', (tester) async {
    await tester.pumpWidget(reader(padding: const EdgeInsets.only(top: 70)));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 70);
  });

  testWidgets('rotation replaces top exclusion with side exclusion',
      (tester) async {
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();
    nativeInsets = [120, 0, 0, 0];
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    expect(tester.getTopLeft(find.byKey(back)).dx, greaterThanOrEqualTo(60));
  });

  testWidgets(
      'no cutout and unavailable native window preserve Flutter padding',
      (tester) async {
    nativeInsets = [0, 0, 0, 0];
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (_) async => throw PlatformException(code: 'unavailable'));
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
  });

  testWidgets('out-of-order responses cannot restore the old orientation',
      (tester) async {
    final first = Completer<List<num>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      requests++;
      return requests == 1 ? first.future : [120, 0, 0, 0];
    });
    await tester.pumpWidget(reader());
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    first.complete([0, 120, 0, 0]);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    expect(tester.getTopLeft(find.byKey(back)).dx, greaterThanOrEqualTo(60));
  });
}
