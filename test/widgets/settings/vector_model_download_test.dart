import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/settings_page/vector_model.dart';
import 'package:anx_reader/service/knowledge/embedding_model_manifest.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControlledModelStore extends LocalEmbeddingModelStore {
  ControlledModelStore({this.bundled = false});
  final bool bundled;
  final ready = <String>{};
  final done = Completer<void>();
  var calls = 0;
  bool closed = false;
  int deletes = 0;
  @override
  Future<void> deleteDownloaded(LocalEmbeddingModel model,
      {required Future<void> Function() releaseModel}) async {
    // This fake has no native session; filesystem/lifetime guards are covered
    // by local_embedding_models_test.dart outside the widget fake-async zone.
    deletes++;
    ready.remove(model.id);
  }

  @override
  Future<bool> isBundled(LocalEmbeddingModel model) async => bundled;
  @override
  Future<bool> isDownloaded(LocalEmbeddingModel model) async =>
      ready.contains(model.id);
  @override
  Future<void> download(LocalEmbeddingModel model,
      {ModelDownloadProgress? onProgress}) async {
    calls++;
    onProgress?.call(.5);
    await done.future;
    ready.add(model.id);
    onProgress?.call(1);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test('model source defaults to Hugging Face and preserves saved choices',
      () async {
    for (final value in [null, 'huggingFace', 'gitee', 'invalid']) {
      SharedPreferences.setMockInitialValues({
        if (value != null) 'vectorModelDownloadSource': value,
      });
      await Prefs().initPrefs();
      expect(Prefs().vectorModelDownloadSource,
          value == 'gitee' ? 'gitee' : 'huggingFace');
    }
    Prefs().vectorModelDownloadSource = 'gitee';
    await Prefs().initPrefs();
    expect(Prefs().vectorModelDownloadSource, 'gitee');
    Prefs().vectorModelDownloadSource = 'huggingFace';
    await Prefs().initPrefs();
    expect(Prefs().vectorModelDownloadSource, 'huggingFace');
  });

  testWidgets('bundled models show offline availability without downloading',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    expect(Prefs().vectorModelDownloadSource, 'huggingFace');
    final store = ControlledModelStore(bundled: true);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(body: VectorModelSettings(modelStore: store)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('已内嵌 · 离线可用'), findsNWidgets(4));
    expect(find.text('测试推理'), findsNWidgets(4));
    expect(find.text('下载并使用'), findsNothing);
    expect(store.calls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [const Size(390, 844), const Size(1100, 1000)]) {
    testWidgets('on-demand download, progress and availability at $size',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      final store = ControlledModelStore();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(body: VectorModelSettings(modelStore: store)),
      ));
      await tester.pumpAndSettle();
      AnxToast.fToast.init(tester.element(find.byType(VectorModelSettings)));
      expect(find.text('本地模型 · 按需下载'), findsOneWidget);
      expect(find.text('下载并使用'), findsNWidgets(4));
      expect(find.text('测试推理'), findsNothing);
      expect(store.calls, 0);
      expect(store.downloadSource, EmbeddingDownloadSource.huggingFace);
      final source = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(source);
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gitee 镜像').last);
      await tester.pumpAndSettle();
      expect(Prefs().vectorModelDownloadSource, 'gitee');
      expect(store.downloadSource, EmbeddingDownloadSource.gitee);
      expect(store.calls, 0,
          reason: 'Selecting a source does not download models');
      final download = find.text('下载并使用').first;
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pump();
      expect(store.calls, 1);
      expect(find.text('正在下载 50%'), findsOneWidget);
      expect(tester.widget<DropdownButtonFormField<String>>(source).onChanged,
          isNull,
          reason: 'Source cannot change during a download');
      expect(find.text('测试推理'), findsNothing);
      store.done.complete();
      await tester.pumpAndSettle();
      expect(find.text('测试推理'), findsOneWidget);
      expect(find.text('使用中'), findsOneWidget);
      expect(Prefs().vectorLocalModelId, LocalEmbeddingModels.all.first.id);
      expect(find.text('下载并使用'), findsNWidgets(3));
      final delete = find
          .byKey(ValueKey('delete-model-${LocalEmbeddingModels.all.first.id}'));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.textContaining('书籍和已有索引不会删除'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.deletes, 0);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(store.deletes, 1);
      expect(find.text('下载并使用'), findsNWidgets(4));
      expect(find.text('测试推理'), findsNothing);
      expect(Prefs().vectorLocalModelId, LocalEmbeddingModels.all.first.id,
          reason: 'Deleting weights must not silently select another model');
      await tester.ensureVisible(find.text('下载并使用').first);
      await tester.tap(find.text('下载并使用').first);
      await tester.pumpAndSettle();
      expect(store.calls, 2);
      expect(find.text('测试推理'), findsOneWidget);
      expect(tester.takeException(), isNull);
      AnxToast.fToast.removeCustomToast();
      AnxToast.fToast.removeQueuedCustomToasts();
      await tester.pumpWidget(const SizedBox());
      expect(store.closed, isTrue);
    });
  }
}
