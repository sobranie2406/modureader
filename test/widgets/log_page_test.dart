import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/settings_page/subpage/log_page.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/service/tts/media_diagnostics.dart';
import 'package:modu_reader/service/feedback/detailed_runtime_log.dart';
import 'package:logging/logging.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/widgets/common/app_scroll_behavior.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Picker extends FilePicker {
  String? output;
  bool fail = false;
  int calls = 0;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    calls++;
    if (fail) throw PlatformException(code: 'export_failed');
    return output;
  }
}

void main() {
  FilePicker.platform = _Picker();
  late Directory directory;
  late PathProviderPlatform oldPaths;
  late FilePicker oldPicker;
  late _Picker picker;
  late File log;
  const text = 'WARNING^*^2026-10-11 21:19:47^*^测试日志\n';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    directory = await Directory.systemTemp.createTemp('modu-log-page-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    oldPicker = FilePicker.platform;
    picker = _Picker();
    FilePicker.platform = picker;
    log = await File('${directory.path}/modu.log').writeAsString(text);
    AnxLog.logFile = log;
    DetailedRuntimeLog.clear();
    DetailedRuntimeLog.record(LogRecord(
        Level.INFO,
        'TTS media diagnostic: {"source":"android","event":"state","state":3,"canPause":true,"title":"PRIVATE BOOK"}',
        'test'));
  });
  tearDown(() async {
    AnxToast.fToast.removeCustomToast();
    AnxToast.fToast.removeQueuedCustomToasts();
    PathProviderPlatform.instance = oldPaths;
    FilePicker.platform = oldPicker;
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: const LogPage(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('导出日志').hitTestable(), findsOneWidget);
    expect(find.text('清空日志').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  for (final outcome in ['success', 'cancel', 'error']) {
    testWidgets('log menu $outcome preserves original and stays on page',
        (tester) async {
      picker.output =
          outcome == 'success' ? '${directory.path}/export.txt' : null;
      picker.fail = outcome == 'error';
      await open(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('导出日志'));
        await tester.pumpAndSettle();
        // Let real filesystem IO complete outside the widget test's fake clock.
        for (var i = 0; i < 150; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 50));
          if (outcome == 'success'
              ? find.textContaining('保存成功').evaluate().isNotEmpty
              : picker.calls > 0) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(find.byType(LogPage), findsOneWidget);
      expect(log.readAsStringSync(), text);
      if (outcome == 'success') {
        final exported = File(picker.output!).readAsStringSync();
        if (MediaDiagnostics.enabled) {
          expect(exported, contains('"canPause":true'));
          expect(exported, isNot(contains('PRIVATE BOOK')));
          expect(exported, isNot(contains(text)));
        } else {
          expect(exported, endsWith(text));
        }
        expect(exported, contains('Current export environment'));
        expect(exported, contains('Modu version:'));
        expect(exported, contains('Device environment:'));
        expect(find.textContaining('保存成功'), findsOneWidget);
      } else if (outcome == 'error') {
        expect(find.textContaining('日志导出失败'), findsOneWidget);
      } else {
        expect(find.textContaining('保存成功'), findsNothing);
        expect(find.textContaining('saved null'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('clear remains operable without popping the log page',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('清空日志'));
    await tester.pumpAndSettle();
    expect(find.byType(LogPage), findsOneWidget);
    expect(log.readAsStringSync(), isEmpty);
    expect(find.text('测试日志'), findsNothing);
    expect(picker.calls, 0);
  });
}
