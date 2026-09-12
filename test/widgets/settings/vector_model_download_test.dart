import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/settings_page/vector_model.dart';
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
  testWidgets('bundled models show offline availability without downloading',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
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
      expect(find.text('本地模型 · 离线内嵌'), findsOneWidget);
      expect(find.text('下载并使用'), findsNWidgets(4));
      expect(find.text('测试推理'), findsNothing);
      expect(store.calls, 0);
      final download = find.text('下载并使用').first;
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pump();
      expect(store.calls, 1);
      expect(find.text('正在下载 50%'), findsOneWidget);
      expect(find.text('测试推理'), findsNothing);
      store.done.complete();
      await tester.pumpAndSettle();
      expect(find.text('测试推理'), findsOneWidget);
      expect(find.text('使用中'), findsOneWidget);
      expect(Prefs().vectorLocalModelId, LocalEmbeddingModels.all.first.id);
      expect(find.text('下载并使用'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      AnxToast.fToast.removeCustomToast();
      AnxToast.fToast.removeQueuedCustomToasts();
      await tester.pumpWidget(const SizedBox());
      expect(store.closed, isTrue);
    });
  }
}
