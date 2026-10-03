import 'dart:async';
import 'package:anx_reader/widgets/reading_page/document_analysis_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only PDF evidence exposes the region preview action',
      (tester) async {
    var opened = 0;
    for (final format in ['epub', 'pdf']) {
      await tester.pumpWidget(MaterialApp(
          home: DocumentAnalysisPanel(
        key: ValueKey(format),
        analyze: () async => {
          'format': format,
          'kind': 'text',
          'sampled': 1,
          'total': 1,
          'pages': []
        },
        cancel: () {},
        previewPdf: () => opened++,
      )));
      await tester.pumpAndSettle();
      final button = find.text('PDF region preview · 100%–1500%');
      expect(button, format == 'pdf' ? findsOneWidget : findsNothing);
      if (format == 'pdf') await tester.tap(button);
    }
    expect(opened, 1);
  });
  testWidgets('manual correction is saved and can be reset to automatic',
      (tester) async {
    final changes = <String?>[];
    await tester.pumpWidget(MaterialApp(
        home: DocumentAnalysisPanel(
      analyze: () async =>
          {'kind': 'unknown', 'sampled': 1, 'total': 1, 'pages': []},
      cancel: () {},
      initialOverride: 'scanned',
      saveOverride: (value) async {
        changes.add(value);
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic').last);
    await tester.pumpAndSettle();
    expect(changes, [null]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('inspection shows real evidence and cancellation on close',
      (tester) async {
    var calls = 0, cancelled = 0;
    await tester.pumpWidget(MaterialApp(
        home: DocumentAnalysisPanel(
      analyze: () async {
        calls++;
        return {
          'kind': 'mixed',
          'sampled': 2,
          'total': 50,
          'pages': [
            {'page': 0, 'kind': 'text', 'characters': 95},
            {
              'page': 49,
              'kind': 'scanned',
              'characters': 0,
              'imageCoverage': 1.0
            },
          ],
        };
      },
      cancel: () => cancelled++,
    )));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Mixed document'), findsOneWidget);
    expect(find.text('Inspected 2 / 50 pages or sections'), findsOneWidget);
    expect(find.textContaining('100% image coverage'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(cancelled, 1);
  });

  testWidgets('closing while pending cancels without setState after dispose',
      (tester) async {
    var cancelled = 0;
    final completer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: DocumentAnalysisPanel(
      analyze: () => completer.future,
      cancel: () => cancelled++,
    )));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    completer.completeError(StateError('cancelled'));
    await tester.pump();
    expect(cancelled, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure has a retry action, never a blank success panel',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DocumentAnalysisPanel(
      analyze: () async => throw StateError('bad PDF'),
      cancel: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Inspection failed'), findsOneWidget);
    expect(find.text('Inspect again'), findsOneWidget);
  });
}
