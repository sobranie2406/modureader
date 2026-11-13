import 'dart:async';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/ocr/document_ocr_precache.dart';
import 'package:modu_reader/service/ocr/document_reflow_loader.dart';
import 'package:modu_reader/widgets/reading_page/ocr_precache_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'cache progress and missing model are visible without content or error details',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ocrPrecacheEnabled': true});
    await Prefs().initPrefs();
    var missingModel = false;
    final cache = DocumentOcrPrecache(
        delay: const Duration(seconds: 2),
        canRun: () => true,
        load: (_, __) async {
          if (missingModel) throw ReflowModelUnavailable();
        });
    cache.update(3, 2);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: OcrPrecacheSettings(cache: cache)))));
    expect(find.textContaining('0/2 processed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('1/2 processed'), findsOneWidget);
    missingModel = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('Install or import'), findsOneWidget);
    expect(cache.completed, 1);
    await tester.pumpWidget(const SizedBox());
    cache.dispose();
  });

  testWidgets('page stepper saves values and stops at one and five',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ocrPrecacheEnabled': true});
    await Prefs().initPrefs();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OcrPrecacheSettings())));
    expect(find.text('3'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    final minus = find.byTooltip('Fewer pages');
    final plus = find.byTooltip('More pages');
    for (final value in [2, 1]) {
      await tester.tap(minus);
      await tester.pumpAndSettle();
      expect(Prefs().ocrPrecachePages, value);
      expect(find.text('$value'), findsOneWidget);
    }
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove))
            .onPressed,
        isNull);
    for (final value in [2, 3, 4, 5]) {
      await tester.tap(plus);
      await tester.pumpAndSettle();
      expect(Prefs().ocrPrecachePages, value);
    }
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
            .onPressed,
        isNull);
  });

  testWidgets('saved OCR and corrections count before missing page completes',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ocrPrecacheEnabled': true});
    await Prefs().initPrefs();
    final pending = Completer<void>();
    final loaded = <int>[];
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        cachedPages: (_, __) async => {4, 6},
        load: (page, _) {
          loaded.add(page);
          return pending.future;
        });
    cache.update(4, 3);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OcrPrecacheSettings(cache: cache))));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(loaded, [5]);
    expect(find.textContaining('2/3 processed'), findsOneWidget);
    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('3/3 processed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    cache.dispose();
  });
}
