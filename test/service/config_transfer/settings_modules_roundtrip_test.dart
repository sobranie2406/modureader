import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/service/config_transfer/config_qr_bridge.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/config_transfer/settings_modules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = <String, Object>{
    'themeColor': 12,
    'trueDarkMode': true,
    'pageTurnStyle': 'scroll',
    'readStyle': BookStyle(fontSize: 1.8, fontFamily: 'source-only').toJson(),
    'readingRules': '{"convertChineseMode":"none","bionicReading":true}',
    'customPageTurnConfig': '2,3,1,2,3,1,2,3,1',
    'bgimg':
        '{"type":"localFile","path":"source.png","alignment":"top","blur":5.0,"opacity":0.5}',
    'customCSS': 'p { color: red; }',
    'customCSSEnabled': true,
    'customCssDefaultIndices': '[0,1]',
    'customCssProfiles':
        '[{"name":"test","css":"p{color:red}","scope":"body","visual":"{\\"size\\":18}"}]',
    'selectionSearchSettings': '{"selectedId":"google","custom":[]}',
    'aiProviders':
        '[{"id":"test","title":"Test","url":"https://example.test","protocol":"openai","keyIndex":5,"apiKeys":[{"id":"key","key":"test-only-secret"}]}]',
    'aiTemperature': 0.3,
    'enabledAiTools': <String>['search_books'],
    'readAnySkillStates': '{"summary":false}',
    'readAnySkillPrompts': '{"summary":"Summarize briefly"}',
    'vectorModelEnabled': false,
    'vectorModelConfig': '{"apiKey":"test-only-secret","dimensions":512}',
    'ttsRate': 1.2,
    'ttsService': 'xiaomi',
    'ttsVoiceModel_xiaomi': 'mimo_default',
    'onlineTtsConfig_xiaomi':
        '{"key":"test-only-secret","instructions":"stable"}',
    'translateService': 'microsoftFree',
    'translateServiceConfig_microsoftApi': '{"api_key":"test-only-secret"}',
    'webdavInfo':
        '{"url":"https://example.test","password":"test-only-secret"}',
    'onlySyncWhenWifi': true,
    'remoteLibraryConnection':
        '{"url":"https://example.test/books","password":"test-only-secret"}',
    'remoteLibraryViewOptions':
        '{"sort":"size","ascending":false,"filter":"epub"}',
    'excerptShareBgimgIndex': 3,
    'notesExportMergeChapters': false,
    'statisticsDashboardTiles': <String>['heatmap'],
    'httpProxyPort': 8888,
    'clearLogWhenStart': false,
  };
  Future<void> initialize(Map<String, Object> data) async {
    SharedPreferences.setMockInitialValues(data);
    await Prefs().initPrefs();
  }

  Map<String, Object?> snapshot() => {
        for (final key in Prefs().prefs.getKeys()) key: Prefs().prefs.get(key),
      };

  for (final module in GlobalSettingsTransfer.scopes.skip(1)) {
    test('$module: file, link and QR roundtrip, scoped restore and isolation',
        () async {
      await initialize(source);
      final file = await GlobalSettingsTransfer.export(Prefs(),
          scope: module, includeSecrets: true);
      final expected = await GlobalSettingsTransfer.decode(file);
      final link = GlobalSettingsTransfer.link(file);
      expect(await GlobalSettingsTransfer.decode(link), expected);
      final directory =
          await Directory.systemTemp.createTemp('modu-module-qr-');
      try {
        final bytes = await ConfigQrBridge.generate(link);
        final image = File('${directory.path}/qr.png');
        await image.writeAsBytes(bytes!);
        final decoded = await ConfigQrBridge.decodeImage(image.path);
        expect(decoded, link);
        expect(await GlobalSettingsTransfer.decode(decoded!), expected);
      } finally {
        await directory.delete(recursive: true);
      }
      expect(GlobalSettingsTransfer.includedScopes(expected), [module]);

      // Import the same module from a whole-app backup, not just a scoped file.
      final full = await GlobalSettingsTransfer.decode(
          await GlobalSettingsTransfer.export(Prefs(), includeSecrets: true));
      expect(GlobalSettingsTransfer.selectScope(full, module), expected);
      await initialize({
        ...source,
        'webdavStatus': true,
        'autoSync': true,
        'readingTimedSync': true,
        'customStoragePath': '/target/private',
        'syncAiSettingsEncryptionPassword': 'target-local',
        'bookCustomCssSelections': '{"local-book":{"index":2,"enabled":true}}',
        'readStyle': BookStyle(fontFamily: 'target-font').toJson(),
        'readTheme': ReadTheme(
                id: 7,
                backgroundColor: 'FFFFFFFF',
                textColor: 'FF000000',
                backgroundImagePath: '/target/bg')
            .toJson(),
        'bgimg':
            '{"type":"localFile","path":"target.png","alignment":"bottom","blur":0.0,"opacity":1.0}',
      });
      // Seed stale values for EVERY explicit default in the selected module.
      for (final entry in expected.entries) {
        if (entry.value is Map && entry.value['type'] == 'reset') {
          await Prefs().prefs.setString(entry.key, 'stale target default');
        }
      }
      final before = snapshot();
      await GlobalSettingsTransfer.apply(Prefs(), expected);
      final after = snapshot();
      for (final key in {...before.keys, ...after.keys}) {
        if (module == 'webdav' &&
            ['webdavStatus', 'autoSync', 'readingTimedSync'].contains(key)) {
          expect(after[key], false, reason: key);
        } else if (!expected.containsKey(key)) {
          expect(after[key], before[key],
              reason: '$module changed unrelated $key');
        } else if (['readStyle', 'readTheme', 'bgimg'].contains(key)) {
          continue; // Mixed local/portable objects checked below.
        } else if (expected[key]['type'] == 'reset') {
          expect(after.containsKey(key), false, reason: key);
        } else {
          expect(after[key], expected[key]['value'], reason: key);
        }
      }
      expect(Prefs().bookStyle.fontFamily, 'target-font');
      expect(Prefs().readTheme.backgroundImagePath, '/target/bg');
      expect(Prefs().bgimg.path, 'target.png');
      if (module == 'reading') {
        expect(Prefs().bookStyle.fontSize, 1.8);
        expect(Prefs().bgimg.opacity, 0.5);
      }
    });

    test(
        '$module: credential switch omits secrets and preserves target credentials',
        () async {
      await initialize(source);
      final file = await GlobalSettingsTransfer.export(Prefs(), scope: module);
      expect(file, isNot(contains('test-only-secret')));
      final values = await GlobalSettingsTransfer.decode(file);
      await initialize(source);
      await GlobalSettingsTransfer.apply(Prefs(), values);
      for (final key in source.keys.where(
          (key) => source[key].toString().contains('test-only-secret'))) {
        expect(Prefs().prefs.get(key), source[key], reason: key);
      }
    });
  }

  test('registry covers every exported field exactly once', () async {
    await initialize(source);
    final keys = settingsModuleKeys.values
        .expand((s) => s.split(RegExp(r'\s+')))
        .toList();
    expect(keys.toSet().length, keys.length);
    final values = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(), includeSecrets: true));
    for (final key in values.keys.where((k) => k != prefsBackupVersionKey)) {
      expect(settingsModuleForKey(key), isNotNull, reason: key);
    }
  });

  test(
      'legacy defaults and format 1 remain readable without resetting omissions',
      () async {
    await initialize({'ttsRate': 1.4, 'fullTextTranslateRpm': 9});
    final migrated = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(), scope: 'ai'));
    expect(migrated['aiRpm']['value'], 9);
    expect(Prefs().prefs.getInt('fullTextTranslateRpm'), 9);
    final values = await GlobalSettingsTransfer.decode(jsonEncode({
      'kind': GlobalSettingsTransfer.kind,
      'version': 1,
      'preferences': {
        prefsBackupVersionKey: 1,
        'ttsVolume': {'type': 'double', 'value': 0.4}
      },
    }));
    await GlobalSettingsTransfer.apply(Prefs(), values);
    expect(Prefs().ttsRate, 1.4);
  });

  test('defaults reject attempts to erase local data or omitted secrets',
      () async {
    await initialize(source);
    for (final key in [
      'customStoragePath',
      'webdavInfo',
      'syncAiSettingsEncryptionPassword',
      'readStyle'
    ]) {
      final before = snapshot();
      await expectLater(
          GlobalSettingsTransfer.apply(Prefs(), {
            prefsBackupVersionKey: 1,
            key: {'type': 'reset', 'value': null},
          }),
          throwsFormatException);
      expect(snapshot(), before);
    }
  });

  test('global import credential switch is independent and off by default',
      () async {
    await initialize(source);
    final full = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(), includeSecrets: true));
    final filtered = GlobalSettingsTransfer.forImport(full);
    expect(jsonEncode(filtered), isNot(contains('test-only-secret')));
    expect(GlobalSettingsTransfer.forImport(full, includeSecrets: true), full);
    await initialize({'onlineTtsConfig_xiaomi': '{"key":"target-key"}'});
    await GlobalSettingsTransfer.apply(Prefs(), filtered);
    expect(Prefs().getOnlineTtsConfig('xiaomi')['key'], 'target-key');
    expect(Prefs().ttsRate, 1.2);
  });

  test('legacy ReadAny payloads are detected without a scope selector', () {
    final link = 'readany:${base64Encode(utf8.encode(jsonEncode({
          'backendType': 'webdav',
          'config': {'url': 'https://example.test'},
        })))}';
    final values = GlobalSettingsTransfer.legacy(link)!;
    expect(GlobalSettingsTransfer.includedScopes(values), ['webdav']);
  });

  for (final entry in <String, String>{
    'aiProviders': '[{"id":7}]',
    'webdavInfo': '[]',
    'readingRules': '{"convertChineseMode":"none","bionicReading":"yes"}',
    'customPageTurnConfig': 'x',
    'pageTurnStyle': 'unknown',
    'readAnySkillStates': '{"summary":"yes"}',
    'onlineTtsConfig_xiaomi': '{"instructions":false}',
    'customCssDefaultIndices': '[99]',
    'customCssProfiles': '[{"name":5,"css":""}]',
    'chapterSplitCustomRules':
        '[{"id":"a","name":"a","pattern":"[","samples":[]}]',
  }.entries) {
    test('invalid ${entry.key} cannot partially modify preferences', () async {
      await initialize(source);
      final before = snapshot();
      await expectLater(
          GlobalSettingsTransfer.apply(Prefs(), {
            prefsBackupVersionKey: 1,
            'ttsRate': {'type': 'double', 'value': 0.5},
            entry.key: {'type': 'string', 'value': entry.value},
          }),
          throwsA(anything));
      expect(snapshot(), before);
    });
  }
}
