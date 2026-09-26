import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ttsRate': 1.2,
      'aiTemperature': 0.5,
      'autoSync': true,
      'customCSS': 'p { color: red; }',
      'remoteLibraryConnection': '{"url":"https://example.test/books/"}',
    });
    await Prefs().initPrefs();
  });

  for (final scope in GlobalSettingsTransfer.scopes.skip(1)) {
    test('$scope file and link describe only their actual settings', () async {
      final file = await GlobalSettingsTransfer.export(Prefs(),
          scope: scope, includeSecrets: true);
      for (final text in [file, GlobalSettingsTransfer.link(file)]) {
        final values = await GlobalSettingsTransfer.decode(text);
        expect(GlobalSettingsTransfer.includedScopes(values), [scope]);
        expect(GlobalSettingsTransfer.disablesSync(values), scope == 'webdav');
      }
    });
  }

  test('misleading scope metadata cannot hide other included settings',
      () async {
    final file = jsonDecode(
            await GlobalSettingsTransfer.export(Prefs(), includeSecrets: true))
        as Map<String, dynamic>;
    file['scope'] = 'tts';
    final values = await GlobalSettingsTransfer.decode(jsonEncode(file));
    expect(GlobalSettingsTransfer.includedScopes(values),
        GlobalSettingsTransfer.scopes.skip(1).toList());
    expect(GlobalSettingsTransfer.disablesSync(values), true);
  });

  test('legacy links are described by payload rather than selected scope', () {
    final link = ConfigTransferCodec.encode(
        kind: 'tts', data: TtsConfigTransfer.defaults());
    final values = GlobalSettingsTransfer.legacy(link, scope: 'ai')!;
    expect(GlobalSettingsTransfer.includedScopes(values), ['tts']);
    expect(GlobalSettingsTransfer.disablesSync(values), false);
  });

  test('version-only payload has no affected settings', () async {
    final values = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(), scope: 'tts'));
    values.removeWhere((_, value) => value is Map);
    expect(values, isNotEmpty);
    expect(GlobalSettingsTransfer.includedScopes(values), isEmpty);
    expect(GlobalSettingsTransfer.disablesSync(values), false);
  });
}
