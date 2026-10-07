import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/sync/s3_config.dart';
import 'package:anx_reader/widgets/settings/s3_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> open(WidgetTester tester, Map<String, dynamic> initial) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: S3SettingsDialog(initial: initial))));
    await tester.pumpAndSettle();
  }

  TextFormField field(WidgetTester tester, String key) {
    final target = find.byKey(ValueKey('s3-$key'));
    final descendants =
        find.descendant(of: target, matching: find.byType(TextFormField));
    return tester.widget<TextFormField>(
        descendants.evaluate().isEmpty ? target : descendants);
  }

  for (final preset in S3Preset.values) {
    testWidgets(
        '${preset.name} preset uses documented defaults and clears old credentials',
        (tester) async {
      await open(tester, {
        'provider': preset == S3Preset.aws ? 'custom' : 'aws',
        'endpoint': 'https://old.example.test',
        'bucket': 'old-bucket',
        'accessKeyId': 'old-id',
        'secretAccessKey': 'old-secret',
        'sessionToken': 'old-token',
        'allowInsecure': true,
        'listVersion': 'v1',
      });
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(preset.label).last);
      await tester.pumpAndSettle();
      expect(field(tester, 'endpoint').controller!.text, preset.endpoint);
      expect(field(tester, 'region').controller!.text, preset.region);
      for (final key in ['bucket', 'accessKeyId', 'secretAccessKey']) {
        expect(field(tester, key).controller!.text, isEmpty);
      }
      await tester.ensureVisible(find.text('Advanced settings'));
      await tester.tap(find.text('Advanced settings'));
      await tester.pumpAndSettle();
      expect(field(tester, 'sessionToken').controller!.text, isEmpty);
      expect(find.byKey(ValueKey('s3-addressing-${preset.addressing}')),
          findsOneWidget);
      expect(find.byKey(ValueKey('s3-signature-${preset.signature}')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('s3-listVersion-v2')), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          false);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reselecting the same preset preserves edited region and keys',
      (tester) async {
    await open(tester, {
      'provider': 'aws',
      'endpoint': 'https://s3.eu-west-1.amazonaws.com',
      'region': 'eu-west-1',
      'bucket': 'existing-bucket',
      'accessKeyId': 'existing-id',
      'secretAccessKey': 'existing-secret',
    });
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(S3Preset.aws.label).last);
    await tester.pumpAndSettle();
    expect(field(tester, 'region').controller!.text, 'eu-west-1');
    expect(field(tester, 'bucket').controller!.text, 'existing-bucket');
    expect(
        field(tester, 'secretAccessKey').controller!.text, 'existing-secret');
  });

  for (final entry in {
    'region':
        'Endpoint and Region do not match. Use your bucket’s actual region.',
    'path':
        'Use virtual-host addressing for this service, or custom-domain addressing for a bucket-bound domain.',
    'appid': 'COS bucket names must end with -APPID.',
  }.entries) {
    testWidgets('rejects incorrect ${entry.key} before saving or connecting',
        (tester) async {
      await open(tester, {
        'provider': 'tencent',
        'endpoint': 'https://cos.ap-guangzhou.myqcloud.com',
        'region': entry.key == 'region' ? 'ap-beijing' : 'ap-guangzhou',
        'addressing': entry.key == 'path' ? 'path' : 'virtual',
        'bucket': entry.key == 'appid' ? 'books' : 'books-1250000000',
        'accessKeyId': 'test-id',
        'secretAccessKey': 'test-secret',
      });
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byType(S3SettingsDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
