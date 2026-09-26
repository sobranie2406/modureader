import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/global_settings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getDownloadsPath() async => path;
}

class _Picker extends FilePicker {
  _Picker(this.path);
  final String? path;
  @override
  Future<String?> saveFile(
          {String? dialogTitle,
          String? fileName,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Uint8List? bytes,
          bool lockParentWindow = false}) async =>
      path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform oldPaths;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    directory = await Directory.systemTemp.createTemp('modu-settings-export-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = oldPaths;
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: Locale('zh'),
      home: Scaffold(body: GlobalSettingsPage()),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> export(WidgetTester tester) async {
    await tester.ensureVisible(find.text('导出全局设置文件'));
    await tester.runAsync(() async {
      await tester.tap(find.text('导出全局设置文件'));
      // Let file writes finish outside Flutter's fake clock.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    // The page remains busy until the success dialog is dismissed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('successful export shows exact selectable location and copies it',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final requestedPath = '${directory.path}/全局设置.json';
    FilePicker.platform = _Picker(requestedPath);
    await open(tester);
    await export(tester);
    final path = directory
        .listSync()
        .whereType<File>()
        .single
        .path
        .replaceAll('\\', '/');
    expect(File(path).existsSync(), isTrue);
    expect(find.text('导出成功'), findsOneWidget);
    expect(find.widgetWithText(SelectableText, path), findsOneWidget);
    await tester.tap(find.text('复制保存位置'));
    await tester.pump();
    expect(copied, path);
    await tester.runAsync(() async {
      await tester.tap(find.text('完成'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('已保存至：\n$path'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled save does not report a successful export',
      (tester) async {
    FilePicker.platform = _Picker(null);
    await open(tester);
    await export(tester);
    expect(find.text('导出成功'), findsNothing);
    expect(find.textContaining('已保存至：'), findsNothing);
    expect(directory.listSync(), isEmpty);
    expect(tester.takeException(), isNull);
  }, skip: Platform.isWindows); // Windows saves directly to Downloads.
}
