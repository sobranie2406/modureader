import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/service/config_transfer/config_qr_bridge.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ttsRate': 1.2,
      'customCSS': 'p { color: red; }',
      'onlineTtsConfig_openai': '{"key":"test-secret"}',
      'webdavInfo': '{"url":"https://example.test/","password":"dav-secret"}',
      'autoSync': true,
      'webdavStatus': true,
      'syncAiSettingsEncryptionPassword': 'sync-only-password',
      'customStoragePath': '/device/local',
      'lastBook': 42,
      'readStyle': BookStyle(fontFamily: 'device-font').toJson(),
      'readTheme': ReadTheme(
              id: 8,
              backgroundColor: 'FFFFFFFF',
              textColor: 'FF000000',
              backgroundImagePath: '/device/bg.png')
          .toJson(),
    });
    await Prefs().initPrefs();
  });

  test('default export omits credentials, sync password and local assets',
      () async {
    final text = await GlobalSettingsTransfer.export(Prefs());
    final data = await GlobalSettingsTransfer.decode(text);
    expect(data['ttsRate']['value'], 1.2);
    for (final key in [
      'webdavInfo',
      'onlineTtsConfig_openai',
      'syncAiSettingsEncryptionPassword',
      'customStoragePath',
      'lastBook'
    ]) {
      expect(data.containsKey(key), false, reason: key);
    }
    expect(text, isNot(contains('device-font')));
    expect(text, isNot(contains('/device/bg.png')));
  });

  test('CSS multi-selection and highlight rules travel through global export', () async {
    await Prefs().saveCustomCssProfile(1, customCssTemplates.last);
    await Prefs().saveCustomCssSelection(const CustomCssSelection(index: 1, enabled: true, indices: [0, 1]));
    final data = await GlobalSettingsTransfer.decode(await GlobalSettingsTransfer.export(Prefs()));
    expect(jsonDecode(data['customCssDefaultIndices']['value'] as String), [0, 1]);
    final profiles = jsonDecode(data['customCssProfiles']['value'] as String) as List;
    expect(profiles[1]['pattern'], customCssTemplates.last.pattern);
    expect(profiles[1]['scope'], 'title');
  });

  test(
      'opt-in plaintext file and modu link include secrets without backup password',
      () async {
    final text =
        await GlobalSettingsTransfer.export(Prefs(), includeSecrets: true);
    expect(text, contains('test-secret'));
    expect(text, contains('dav-secret'));
    expect(text, isNot(contains('encryptedPreferences')));
    expect(text, isNot(contains('sync-only-password')));
    final data =
        await GlobalSettingsTransfer.decode(GlobalSettingsTransfer.link(text));
    expect(data, await GlobalSettingsTransfer.decode(text));
  });

  test('restore preserves local paths, assets, books and omitted credentials',
      () async {
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    await Prefs().prefs.setDouble('ttsRate', 0.7);
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().ttsRate, 1.2);
    expect(Prefs().bookStyle.fontFamily, 'device-font');
    expect(Prefs().readTheme.backgroundImagePath, '/device/bg.png');
    expect(Prefs().readTheme.id, 8);
    expect(Prefs().prefs.getInt('lastBook'), 42);
    expect(Prefs().prefs.getString('customStoragePath'), '/device/local');
    expect(Prefs().prefs.getString('onlineTtsConfig_openai'),
        contains('test-secret'));
    expect(Prefs().prefs.getString('syncAiSettingsEncryptionPassword'),
        'sync-only-password');
    expect(Prefs().webdavStatus, false);
    expect(Prefs().autoSync, false);
  });

  test('subscope does not include unrelated settings or disable sync',
      () async {
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(),
            scope: 'tts', includeSecrets: true));
    expect(data.containsKey('customCSS'), false);
    expect(data.containsKey('webdavInfo'), false);
    expect(data.containsKey('onlineTtsConfig_openai'), true);
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().webdavStatus, true);
  });

  for (final entry in {
    'unknown field': {
      'customStoragePath': {'type': 'string', 'value': '/wrong'}
    },
    'wrong type': {
      'ttsRate': {'type': 'string', 'value': 'fast'}
    },
    'bad range': {
      'ttsRate': {'type': 'double', 'value': 999.0}
    },
    'broken style': {
      'readStyle': {'type': 'string', 'value': '{}'}
    },
    'broken theme': {
      'readTheme': {'type': 'string', 'value': '{}'}
    },
  }.entries) {
    test('reject ${entry.key} before applying any setting', () async {
      final data = await GlobalSettingsTransfer.decode(
          await GlobalSettingsTransfer.export(Prefs()));
      data['ttsVolume'] = {'type': 'double', 'value': 0.2};
      data.addAll(entry.value);
      final before =
          Prefs().prefs.getKeys().map((k) => MapEntry(k, Prefs().prefs.get(k)));
      final snapshot = Map.fromEntries(before);
      await expectLater(
          GlobalSettingsTransfer.apply(Prefs(), data), throwsA(anything));
      expect({
        for (final key in Prefs().prefs.getKeys()) key: Prefs().prefs.get(key)
      }, snapshot);
    });
  }

  test('legacy TTS link remains importable at central entry', () async {
    final source = TtsConfigTransfer.defaults();
    source['rate'] = 1.3;
    final token = ConfigTransferCodec.encode(kind: 'tts', data: source);
    final data = GlobalSettingsTransfer.legacy(token)!;
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().ttsRate, 1.3);
    expect(Prefs().webdavStatus, true);
  });

  test('small settings QR roundtrip keeps complete modu link', () async {
    final text = await GlobalSettingsTransfer.export(Prefs(),
        scope: 'tts', includeSecrets: true);
    final token = GlobalSettingsTransfer.link(text);
    final bytes = await ConfigQrBridge.generate(token);
    final directory = await Directory.systemTemp.createTemp('modu-global-qr-');
    try {
      final image = File('${directory.path}/qr.png');
      await image.writeAsBytes(bytes!);
      expect(await ConfigQrBridge.decodeImage(image.path), token);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('unsupported envelope rejected', () async {
    final envelope =
        jsonDecode(await GlobalSettingsTransfer.export(Prefs())) as Map;
    envelope['version'] = 99;
    await expectLater(GlobalSettingsTransfer.decode(jsonEncode(envelope)),
        throwsFormatException);
  });
}
