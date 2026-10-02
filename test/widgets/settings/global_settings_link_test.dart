import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_catalogs.g.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/page/settings_page/global_settings.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Picker extends FilePicker {
  String? path;
  int calls = 0;
  FileType? requestedType;
  List<String>? requestedExtensions;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls++;
    requestedType = type;
    requestedExtensions = allowedExtensions;
    return path == null
        ? null
        : FilePickerResult([
            PlatformFile(name: 'settings.json', size: 0, path: path),
          ]);
  }
}

void main() {
  late ProviderContainer container;
  late _Picker picker;
  setUpAll(() async {
    container = ProviderContainer();
    for (final locale in appLocales) {
      await L10n.delegate.load(locale);
    }
  });
  tearDownAll(() => container.dispose());
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ttsRate': 1.2,
      'onlineTtsConfig_openai': '{"key":"local-fixture-key"}',
    });
    await Prefs().initPrefs();
    picker = _Picker();
    FilePicker.platform = picker;
  });

  Future<void> open(WidgetTester tester,
      {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        supportedLocales: appLocales,
        localeListResolutionCallback: resolveAppLocale,
        localizationsDelegates: L10n.localizationsDelegates,
        home: const Scaffold(body: GlobalSettingsPage()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await reveal(tester, find.text(text));
    await tester.tap(find.text(text));
    // The page stays busy behind an export/import dialog until it is closed.
    // Its indeterminate progress indicator cannot settle while a dialog is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  String largeCss() {
    final random = Random(17);
    return '/* ${base64Encode(List.generate(8192, (_) => random.nextInt(256)))} */';
  }

  for (final locale in appLocales) {
    testWidgets(
        '$locale backup offers only files and links, with localized dialog',
        (tester) async {
      await open(tester, locale: locale);
      final catalog = moduCatalogs[appLocaleKey(locale)]!;
      final exportLabel = catalog['ui_settings_link_export']!;
      expect(ModuStrings.label(locale, '导出 modu 链接', 'Export modu link'),
          exportLabel);
      expect(find.byIcon(Icons.qr_code_2), findsNothing);
      expect(find.byIcon(Icons.image_search), findsNothing);
      await reveal(tester, find.byType(SwitchListTile));
      final credentialDescription = tester
          .widget<SwitchListTile>(find.byType(SwitchListTile))
          .subtitle as Text;
      expect(credentialDescription.data,
          isNot(matches(RegExp(r'QR|二维码', caseSensitive: false))));
      for (final label in [
        ModuStrings.label(locale, '导出全局设置文件', 'Export global settings file'),
        ModuStrings.label(locale, '从文件恢复设置', 'Restore settings from file'),
        ModuStrings.label(locale, '粘贴 modu 链接恢复', 'Restore from modu link'),
      ]) {
        await reveal(tester, find.text(label));
        expect(find.text(label), findsOneWidget);
      }
      await tap(tester, exportLabel);
      final scope = ModuStrings.label(locale, '全部全局设置', 'All global settings');
      expect(
          find.text(
              catalog['ui_settings_link_title']!.replaceAll('{scope}', scope)),
          findsOneWidget);
      expect(find.text(catalog['ui_settings_link_help']!), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(picker.calls, 0);
      await tap(tester, ModuStrings.label(locale, '关闭', 'Close'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final includeSecrets in [false, true]) {
    testWidgets(
        'large full link copies without truncation (secrets: $includeSecrets)',
        (tester) async {
      final css = largeCss();
      await Prefs().prefs.setString('customCSS', css);
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
      await open(tester);
      if (includeSecrets) {
        await reveal(tester, find.byType(SwitchListTile));
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
      }
      await tap(tester, 'Export modu link');
      final token =
          tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(token.length, greaterThan(2953));
      expect(find.text('Save QR'), findsNothing);
      expect(find.byType(Image), findsNothing);
      await tap(tester, 'Copy link');
      expect(copied, token);
      final data = await GlobalSettingsTransfer.decode(copied!);
      expect(data['customCSS']['value'], css);
      expect(data['ttsRate']['value'], 1.2);
      expect(data.containsKey('onlineTtsConfig_openai'), includeSecrets);
      expect(picker.calls, 0);
      await tap(tester, 'Close');
      // Closing export releases the busy state; restoring a link still works.
      await tap(tester, 'Restore from modu link');
      expect(find.text('Paste modu link'), findsOneWidget);
      await tap(tester, 'Cancel');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large JSON file restores settings while preserving local keys',
      (tester) async {
    final css = largeCss();
    await Prefs().prefs.setString('customCSS', css);
    final file = await GlobalSettingsTransfer.export(Prefs());
    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('modu-file-import-'));
    addTearDown(() => directory!.delete(recursive: true));
    final path = '${directory!.path}/settings.json';
    await tester.runAsync(() => File(path).writeAsString(file));
    picker.path = path;
    await Prefs().prefs.setString('customCSS', 'p { color: blue; }');
    Prefs().ttsRate = 0.6;
    await open(tester);
    await reveal(tester, find.text('Restore settings from file'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Restore settings from file'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(picker.requestedType, FileType.custom);
    expect(picker.requestedExtensions, ['json']);
    expect(find.text('Restore multiple settings?'), findsOneWidget);
    expect(Prefs().ttsRate, 0.6);
    await tester.runAsync(() async {
      await tester.tap(find.text('Restore'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(Prefs().ttsRate, 1.2);
    expect(Prefs().prefs.getString('customCSS'), css);
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'local-fixture-key');
    expect(tester.takeException(), isNull);
  });
}
