import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:modu_reader/service/feedback/detailed_runtime_log.dart';
import 'package:modu_reader/service/ocr/document_ocr_precache.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/ocr/document_reflow_loader.dart';
import 'package:modu_reader/service/ocr/ocr_model_store.dart';
import 'package:modu_reader/service/ocr/local_ocr_service.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'prefetch failures retain safe diagnosis without private payloads',
      (tester) async {
    final records = <LogRecord>[];
    final listener = Logger.root.onRecord.listen(records.add);
    addTearDown(listener.cancel);
    var failure = const FormatException('Invalid image page');
    final cache = DocumentOcrPrecache(
        canRun: () => true, load: (_, __) async => throw failure);
    cache.update(0, 1);
    await tester.pump(const Duration(milliseconds: 300));
    final record = records.singleWhere(
        (record) => record.message.startsWith('OCR precache failed:'));
    expect(record.stackTrace, isNotNull);
    final details = jsonDecode(DetailedRuntimeLog.format(record)) as Map;
    expect(details['operation'], 'ocr');
    expect(details['reasons'], ['ocr_invalid_page']);
    expect(details['errors'], ['FormatException']);

    records.clear();
    failure = const FormatException('/Users/private/book.pdf SECRET_CONTENT');
    cache.resume();
    await tester.pump(const Duration(milliseconds: 300));
    final privateRecord = records.single;
    expect(privateRecord.message, contains('reason=unknown'));
    expect(privateRecord.message, isNot(contains('private')));
    expect(privateRecord.message, isNot(contains('SECRET_CONTENT')));
    expect(privateRecord.error, isNull);
    cache.dispose();
  });

  testWidgets('cancelled prefetch does not log a failure', (tester) async {
    final records = <LogRecord>[];
    final listener = Logger.root.onRecord.listen(records.add);
    addTearDown(listener.cancel);
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        load: (_, token) async {
          token.cancel();
          throw StateError('cancelled');
        });
    cache.update(0, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.where((r) => r.message.startsWith('OCR precache failed:')),
        isEmpty);
    expect(cache.error, isNull);
    cache.dispose();
  });

  testWidgets('foreground failure releases worker but respects lifecycle pause',
      (tester) async {
    final loaded = <int>[];
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        load: (page, _) async {
          loaded.add(page);
        });
    cache.update(0, 2);
    final finish = Completer<void>();
    final task = cache.runForeground(() => finish.future);
    final checked = expectLater(task, throwsStateError);
    await tester.pump(const Duration(seconds: 1));
    expect(loaded, isEmpty);
    await cache.pause();
    finish.completeError(StateError('foreground OCR failed'));
    await checked;
    await tester.pump(const Duration(seconds: 1));
    expect(loaded, isEmpty);
    cache.resume();
    await tester.pump(const Duration(milliseconds: 300));
    expect(loaded, [0]);
    cache.dispose();
  });
  test('original pages fall back to section index without crop metadata', () {
    expect(documentOcrPage({'currentChapter': 4}), 3);
    expect(documentOcrPage({'pdfRegion': null, 'currentChapter': 1}), 0);
    expect(
        documentOcrPage({
          'pdfRegion': {'page': 8},
          'currentChapter': 4
        }),
        8);
    expect(documentOcrPage({'currentChapter': 0}), -1);
    expect(documentOcrPage({'currentChapter': 1.5}), -1);
    expect(documentOcrPage({}), -1);
  });
  testWidgets(
      'failed prefetch retries the same page and never reports it cached',
      (tester) async {
    var attempts = 0;
    final pages = <int>[];
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        load: (page, _) async {
          pages.add(page);
          if (++attempts < 3) throw StateError('temporary render failure');
        },
        delay: const Duration(seconds: 2));
    cache.update(8, 5, totalPages: 10);
    expect(cache.total, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(cache.completed, 0);
    expect(cache.error, isNotNull);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 8));
    expect(pages, [8, 8, 8]);
    expect(cache.completed, 1);
    expect(cache.error, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(pages, [8, 8, 8, 9]);
    expect(cache.completed, 2);
    cache.dispose();
  });
  testWidgets('persistent failure stops retrying until reader resumes',
      (tester) async {
    var calls = 0;
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        load: (_, __) async {
          calls++;
          throw ReflowModelUnavailable();
        },
        delay: const Duration(seconds: 2));
    cache.update(0, 3);
    for (final seconds in [2, 4, 8, 20]) {
      await tester.pump(Duration(seconds: seconds));
    }
    expect(calls, 3);
    expect(cache.completed, 0);
    expect(cache.error, isA<ReflowModelUnavailable>());
    cache.resume();
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 4);
    cache.dispose();
  });
  test('foreground reflow reuses disk prefetch without rendering or OCR',
      () async {
    final dir = await Directory.systemTemp.createTemp('modu-cache-read-');
    addTearDown(() => dir.delete(recursive: true));
    final store = DocumentReflowStore('book', directory: dir);
    final saved =
        DocumentReflowPage(page: 2, ocr: true, rawText: 'Cached page');
    await store.save(saved, '');
    final model = OcrModelStore(directory: dir);
    addTearDown(model.close);
    final result = await loadDocumentReflowPage(
      info: {'page': 2, 'total': 5},
      store: store,
      model: model,
      cancel: OcrCancellation(),
      extract: (_) async => throw StateError('must not extract'),
      render: (_) async => throw StateError('must not render'),
      recognize: (_, __, ___) async => throw StateError('must not recognize'),
    );
    expect(result.text, 'Cached page');
  });
  testWidgets(
      'rolling window includes current page, caps at five and stays serial',
      (tester) async {
    final pages = <int>[];
    final cache = DocumentOcrPrecache(
        canRun: () => true, load: (page, _) async => pages.add(page));
    cache.update(10, 99);
    await tester.pump(const Duration(milliseconds: 100));
    expect(pages, isEmpty);
    for (var n = 0; n < 7; n++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(pages, [10, 11, 12, 13, 14]);
    cache.update(11, 3);
    for (var n = 0; n < 4; n++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(pages, [10, 11, 12, 13, 14]);
    expect(cache.completed, 3);
    cache.dispose();
  });
  testWidgets(
      'navigation preserves in-flight work; foreground pause cancels and waits',
      (tester) async {
    final pending = Completer<void>();
    final pages = <int>[];
    OcrCancellation? token;
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        load: (page, cancel) async {
          pages.add(page);
          token = cancel;
          if (page == 0) await pending.future;
        },
        delay: const Duration(seconds: 2));
    cache.update(0, 5);
    await tester.pump(const Duration(seconds: 2));
    cache.update(8, 2);
    expect(token!.cancelled, isFalse);
    await tester.pump(const Duration(seconds: 4));
    expect(pages, [0]);
    var paused = false;
    final pause = cache.pause().then((_) => paused = true);
    expect(token!.cancelled, isTrue);
    await tester.pump();
    expect(paused, isFalse);
    pending.complete();
    await tester.pump();
    await pause;
    expect(paused, isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(pages, [0]);
    cache.resume();
    await tester.pump(const Duration(seconds: 2));
    expect(pages, [0, 8]);
    cache.update(8, 0);
    await tester.pump(const Duration(seconds: 4));
    expect(pages, [0, 8]);
    cache.dispose();
  });
  testWidgets('inactive reader does not start OCR and disposal stops the timer',
      (tester) async {
    var allowed = false, calls = 0;
    final cache = DocumentOcrPrecache(
        canRun: () => allowed,
        delay: const Duration(seconds: 2),
        load: (_, __) async {
          calls++;
        });
    cache.update(0, 3);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    allowed = true;
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 1);
    cache.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 1);
  });
  testWidgets(
      'finish current page then use only the latest page and configured count',
      (tester) async {
    final pending = Completer<void>();
    final saved = <int>{};
    final jobs = <int>[];
    OcrCancellation? token;
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        cachedPages: (_, __) async => saved,
        load: (page, cancel) async {
          jobs.add(page);
          if (page == 0) {
            token = cancel;
            await pending.future;
          }
          cancel.check();
          saved.add(page);
        });
    cache.update(0, 5);
    await tester.pump(const Duration(milliseconds: 300));
    cache.update(6, 4);
    cache.update(12, 2);
    await tester.pump(const Duration(seconds: 10));
    expect(jobs, [0]);
    expect(token!.cancelled, isFalse);
    pending.complete();
    await tester.pump();
    expect(saved, {0});
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(jobs, [0, 12, 13]);
    expect(cache.completed, 2);
    cache.dispose();
  });
  testWidgets(
      'touches and overlapping navigation let one OCR finish without restarting',
      (tester) async {
    final pending = Completer<void>();
    final pages = <int>[];
    OcrCancellation? token;
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        load: (page, cancel) async {
          pages.add(page);
          if (page == 2) {
            token = cancel;
            await pending.future;
          }
        });
    cache.update(2, 3);
    await tester.pump(const Duration(milliseconds: 300));
    for (var n = 0; n < 8; n++) {
      await cache.pause(cancelRunning: false);
      cache.resume();
      await tester.pump(const Duration(seconds: 1));
      expect(token!.cancelled, isFalse);
    }
    cache.update(3, 3);
    expect(token!.cancelled, isFalse);
    cache.reportProgress(3, 10);
    expect(cache.progress, (3, 10));
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pages, [2, 3]);
    expect(cache.completed, 1);
    cache.dispose();
  });
  testWidgets(
      'scan skips all existing pages immediately and only recognizes missing pages',
      (tester) async {
    final pages = <int>[];
    var scans = 0;
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        cachedPages: (start, count) async {
          scans++;
          return {7, 8, 10, 11};
        },
        load: (page, _) async => pages.add(page));
    cache.update(7, 5);
    await tester.pump(const Duration(milliseconds: 300));
    expect(scans, 1);
    expect(pages, [9]);
    expect(cache.completed, 5);
    await tester.pump(const Duration(seconds: 10));
    expect(pages, [9]);
    cache.dispose();
  });
  test('prefetch cannot replace a saved correction or its annotated revision',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('modu-ocr-prefetch-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store = DocumentReflowStore('book', directory: dir);
    final page =
        DocumentReflowPage(page: 1, ocr: true, rawText: 'Original paragraph');
    await store.save(page, '');
    final edited = await store.saveEdit(page, 'Corrected paragraph');
    expect(await store.cachedPages(0, 5), {1});
    await store.save(
        DocumentReflowPage(page: 1, ocr: true, rawText: 'Stale result'), '',
        onlyIfAbsent: true);
    expect((await store.read(1, ''))!.text, edited.text);
    expect((await store.readAnchor(page.anchor(0, 8)))!.text, page.text);
  });
  test(
      'cache settings validate page count and survive settings export validation',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    expect(Prefs().ocrPrecacheEnabled, isFalse);
    expect(Prefs().ocrPrecachePages, 3);
    await Prefs().saveOcrPrecache(enabled: true, pages: 5);
    expect(Prefs().ocrPrecacheEnabled, isTrue);
    expect(Prefs().ocrPrecachePages, 5);
    await expectLater(Prefs().saveOcrPrecache(pages: 6), throwsArgumentError);
    GlobalSettingsTransfer.validate({
      '__prefsBackupVersion': 1,
      'ocrPrecacheEnabled': {'type': 'bool', 'value': true},
      'ocrPrecachePages': {'type': 'int', 'value': 5},
    });
    expect(
        () => GlobalSettingsTransfer.validate({
              '__prefsBackupVersion': 1,
              'ocrPrecachePages': {'type': 'int', 'value': 6},
            }),
        throwsFormatException);
  });
}
