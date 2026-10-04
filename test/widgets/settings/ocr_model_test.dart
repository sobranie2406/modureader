import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ocr_model.dart';
import 'package:anx_reader/service/ocr/ocr_model_store.dart';
import 'package:anx_reader/service/ocr/ocr_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeOcrStore extends OcrModelStore {
  FakeOcrStore(OcrModelSpec model) : super(model: model);
  bool ready = false, closed = false, corrupt = false, partial = false;
  bool failDownload = false, failDelete = false;
  int downloads = 0, deletes = 0;
  CancelToken? token;
  Completer<void>? pending;
  @override
  Future<bool> available() async => ready;
  @override
  Future<bool> hasLocalFiles() async => ready || partial;
  @override
  Future<void> deleteDownloaded() async {
    if (failDelete) throw StateError('in use');
    deletes++;
    ready = false;
    partial = false;
  }

  @override
  Future<void> verify() async {
    if (corrupt) throw const FormatException('corrupt');
  }

  @override
  Future<void> download(
      CancelToken cancel, void Function(int, int) progress) async {
    token = cancel;
    downloads++;
    progress(1, 2);
    if (failDownload) throw StateError('download failed');
    if (pending != null) {
      await Future.any([pending!.future, cancel.whenCancel]);
      if (cancel.isCancelled) throw cancel.cancelError!;
    }
    ready = true;
    progress(2, 2);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

Future<void> show(
    WidgetTester tester, FakeOcrStore Function(OcrModelSpec) factory,
    {Locale locale = const Locale('zh'), double scale = 1}) async {
  // Deferred locale libraries complete outside the fake-async frame clock.
  await tester.runAsync(() => L10n.delegate.load(locale));
  await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(body: OcrModelSettings(storeFactory: factory))));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  test('settings defaults and selection persist without modifying vector model',
      () async {
    expect(Prefs().ocrModelId, OcrModels.defaultModel.id);
    expect(Prefs().ocrModelDownloadSource, 'upstream');
    final vector = Prefs().vectorLocalModelId;
    await Prefs()
        .saveOcrModelSettings(model: 'ppocr-v5-mobile-1', source: 'gitee');
    await Prefs().initPrefs();
    expect(Prefs().ocrModelId, 'ppocr-v5-mobile-1');
    expect(Prefs().ocrModelDownloadSource, 'gitee');
    expect(Prefs().vectorLocalModelId, vector);
    await expectLater(
        Prefs().saveOcrModelSettings(model: 'invalid', source: 'gitee'),
        throwsFormatException);
    await expectLater(
        Prefs().saveOcrModelSettings(
            model: 'ppocr-v5-mobile-1', source: 'invalid'),
        throwsFormatException);
    expect(Prefs().ocrModelId, 'ppocr-v5-mobile-1');
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('small-screen layout and opt-in downloads $locale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stores = <FakeOcrStore>[];
      await show(tester, (model) {
        final store = FakeOcrStore(model);
        stores.add(store);
        return store;
      }, locale: locale);
      expect(stores.length, 4);
      expect(stores.every((store) => store.downloads == 0), isTrue);
      expect(find.byType(Card), findsNWidgets(4));
      await tester
          .ensureVisible(find.byKey(const ValueKey('ocr-source-upstream')));
      await tester.tap(find.byKey(const ValueKey('ocr-source-upstream')));
      await tester.pumpAndSettle();
      await tester.tap(find
          .text(locale.languageCode == 'zh' ? 'Gitee 镜像' : 'Gitee mirror')
          .last);
      await tester.pumpAndSettle();
      expect(Prefs().ocrModelDownloadSource, 'gitee');
      final download =
          find.byKey(const ValueKey('ocr-download-ppocr-v5-mobile-1'));
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(stores[1].downloads, 1);
      expect(stores[1].downloadSource, OcrDownloadSource.gitee);
      expect(stores[1].ready, isTrue);
      expect(Prefs().ocrModelId, 'ppocr-v5-mobile-1');
      expect(stores.where((store) => store.downloads != 0).length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(stores.every((store) => store.closed), isTrue);
    });
  }
  testWidgets('leaving settings cancels download and closes store',
      (tester) async {
    final store = FakeOcrStore(OcrModels.defaultModel)
      ..pending = Completer<void>();
    await show(tester,
        (model) => model.id == store.model.id ? store : FakeOcrStore(model));
    final download = find.byKey(ValueKey('ocr-download-${store.model.id}'));
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pump();
    expect(store.token?.isCancelled, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(store.token?.isCancelled, isTrue);
    expect(store.closed, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('corrupt cached model offers redownload not ready status',
      (tester) async {
    final store = FakeOcrStore(OcrModels.defaultModel)
      ..ready = true
      ..corrupt = true;
    await show(tester,
        (model) => model.id == store.model.id ? store : FakeOcrStore(model));
    expect(find.text('模型校验失败，请重新下载'), findsOneWidget);
    expect(
        find.byKey(ValueKey('ocr-download-${store.model.id}')), findsOneWidget);
    expect(
        find.byKey(ValueKey('ocr-delete-${store.model.id}')), findsOneWidget);
    expect(store.downloads, 0);
  });

  testWidgets(
      'delete confirms, preserves selection and other models, and allows redownload',
      (tester) async {
    final stores = {
      for (final m in OcrModels.all) m.id: FakeOcrStore(m)..ready = true
    };
    await show(tester, (m) => stores[m.id]!);
    final id = Prefs().ocrModelId, selected = stores[Prefs().ocrModelId]!;
    final button = find.byKey(ValueKey('ocr-delete-$id'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(selected.deletes, 0);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ocr-delete-confirm')));
    await tester.pumpAndSettle();
    expect(selected.deletes, 1);
    expect(Prefs().ocrModelId, id);
    expect(stores.values.where((s) => s.model.id != id).every((s) => s.ready),
        isTrue);
    final download = find.byKey(ValueKey('ocr-download-$id'));
    expect(download, findsOneWidget);
    expect(button, findsNothing);
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(selected.ready, isTrue);
    expect(selected.downloads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'using a downloaded card never redownloads and delete failure keeps ready state',
      (tester) async {
    final stores = {
      for (final m in OcrModels.all) m.id: FakeOcrStore(m)..ready = true
    };
    await show(tester, (m) => stores[m.id]!);
    final model = OcrModels.all[1], store = stores[OcrModels.all[1].id]!;
    final use = find.byKey(ValueKey('ocr-use-${model.id}'));
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(Prefs().ocrModelId, model.id);
    expect(store.downloads, 0);
    store.failDelete = true;
    await tester.tap(find.byKey(ValueKey('ocr-delete-${model.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ocr-delete-confirm')));
    await tester.pumpAndSettle();
    expect(store.ready, isTrue);
    expect(store.deletes, 0);
    expect(find.textContaining('删除失败'), findsOneWidget);
    expect(find.byKey(ValueKey('ocr-use-${model.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and download failure never switch the current model',
      (tester) async {
    final stores = {for (final m in OcrModels.all) m.id: FakeOcrStore(m)};
    final store = stores[OcrModels.all[1].id]!..pending = Completer<void>();
    await show(tester, (m) => stores[m.id]!);
    final selected = Prefs().ocrModelId,
        download = find.byKey(ValueKey('ocr-download-${store.model.id}'));
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pump();
    final cancel = find.byKey(ValueKey('ocr-cancel-${store.model.id}'));
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(store.token!.isCancelled, isTrue);
    expect(Prefs().ocrModelId, selected);
    store.pending = null;
    store.failDownload = true;
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(find.textContaining('下载或校验失败'), findsOneWidget);
    expect(Prefs().ocrModelId, selected);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('cards and actions wrap at $width with large English text',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, (m) => FakeOcrStore(m)..ready = true,
          locale: const Locale('en'), scale: 1.5);
      for (final model in OcrModels.all) {
        await tester
            .ensureVisible(find.byKey(ValueKey('ocr-delete-${model.id}')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
