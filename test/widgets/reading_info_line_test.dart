import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:anx_reader/models/reading_info.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/widgets/reading_page/reading_battery_indicator.dart';
import 'package:anx_reader/widgets/reading_page/reading_info_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const batteryChannel = MethodChannel('dev.fluttercommunity.plus/battery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  tearDown(() => messenger.setMockMethodCallHandler(batteryChannel, null));

  for (final header in [true, false]) {
    for (final size in [8.0, 10.0, 24.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            '${header ? 'header' : 'footer'} size=$size scale=$scale keeps geometry with/without battery',
            (tester) async {
          messenger.setMockMethodCallHandler(batteryChannel, (_) async => 80);
          final player = EpubPlayerState()
            ..chapterCurrentPage = 1
            ..percentage = .25
            ..chapterTitle = '第262章'
            ..textColor = '000000';
          Rect? referenceTitle;
          Rect? referenceLine;
          for (final right in [
            ReadingInfoEnum.none,
            ReadingInfoEnum.chapterProgress,
            ReadingInfoEnum.battery,
            ReadingInfoEnum.batteryAndTime
          ]) {
            final section = ReadingInfoSectionModel(
                left: ReadingInfoEnum.time,
                center: ReadingInfoEnum.chapterTitle,
                right: right,
                fontSize: size,
                verticalMargin: 20);
            Prefs().readingInfo = header
                ? ReadingInfoModel(
                    header: section, footer: const ReadingInfoSectionModel())
                : ReadingInfoModel(
                    footer: section, header: const ReadingInfoSectionModel());
            await tester.pumpWidget(MaterialApp(
                home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: player.readingInfoWidget()),
            )));
            await tester.pumpAndSettle();
            final title = tester.getRect(find.text('第262章'));
            final line =
                tester.getRect(find.byType(ReadingInfoLine).at(header ? 0 : 1));
            referenceTitle ??= title;
            referenceLine ??= line;
            expect(line, referenceLine);
            expect(title.top, closeTo(referenceTitle.top, .001));
            expect(title.center.dy, closeTo(line.center.dy, .001));
            expect(title.bottom, lessThanOrEqualTo(line.bottom + .001));
            if (right == ReadingInfoEnum.battery ||
                right == ReadingInfoEnum.batteryAndTime) {
              final battery =
                  tester.getRect(find.byType(ReadingBatteryIndicator));
              expect(battery.center.dy, closeTo(line.center.dy, .001));
              expect(battery.bottom, lessThanOrEqualTo(line.bottom));
              expect(battery.top, greaterThanOrEqualTo(line.top));
            }
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          // MinuteClock's existing initial delayed callback checks mounted.
          await tester.pump(const Duration(minutes: 1));
          player.documentReadingMode.dispose();
          player.readingProgress.dispose();
          player.translationMode.dispose();
        });
      }
    }
  }

  testWidgets('asynchronous battery arrival does not move real reader header',
      (tester) async {
    final level = Completer<int>();
    messenger.setMockMethodCallHandler(batteryChannel, (_) => level.future);
    Prefs().readingInfo = const ReadingInfoModel(
        header: ReadingInfoSectionModel(
            center: ReadingInfoEnum.chapterTitle,
            right: ReadingInfoEnum.battery,
            fontSize: 10),
        footer: ReadingInfoSectionModel());
    final player = EpubPlayerState()
      ..chapterCurrentPage = 1
      ..percentage = .25
      ..chapterTitle = '第262章'
      ..textColor = '000000';
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: player.readingInfoWidget())));
    final before = tester.getRect(find.text('第262章'));
    final lineBefore = tester.getRect(find.byType(ReadingInfoLine).first);
    expect(find.byType(ReadingBatteryIndicator), findsNothing);
    level.complete(100);
    await tester.pumpAndSettle();
    expect(find.byType(ReadingBatteryIndicator), findsOneWidget);
    final after = tester.getRect(find.text('第262章'));
    expect(after.top, before.top);
    expect(after.height, before.height);
    expect(tester.getRect(find.byType(ReadingInfoLine).first), lineBefore);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    player.documentReadingMode.dispose();
    player.readingProgress.dispose();
    player.translationMode.dispose();
  });
}
