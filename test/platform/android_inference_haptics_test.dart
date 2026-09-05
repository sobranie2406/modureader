import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // These are packaging/source guards, not a substitute for Android inference.
  test('Android pins the ARM instruction-detection fix without changing Apple',
      () {
    final gradle = File('android/build.gradle').readAsStringSync();
    expect(gradle,
        contains("details.requested.group == 'com.microsoft.onnxruntime'"));
    expect(gradle, contains("details.requested.name == 'onnxruntime-android'"));
    expect(gradle, contains("details.useVersion '1.24.3'"));
    expect(gradle, contains('onnxruntime#27884'));
    final provider = File('lib/service/knowledge/onnx_embedding_provider.dart')
        .readAsStringSync();
    expect(provider, contains('providers: const [OrtProvider.CPU]'));
    expect(File('LICENSES/ONNXRuntime-1.24.3-MIT.txt').existsSync(), isTrue);
    expect(
        File('LICENSES/ONNXRuntime-1.24.3-ThirdPartyNotices.txt').existsSync(),
        isTrue);
  });

  test('vibration plugins, service, settings and developer page are removed',
      () {
    final dependencies = File('pubspec.yaml').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();
    for (final name in [
      'vibration',
      'vibration_platform_interface',
      'haptic_feedback'
    ]) {
      expect(dependencies, isNot(contains('$name:')));
      expect(lock, isNot(contains('$name:')));
    }
    expect(File('lib/service/vibration_service.dart').existsSync(), isFalse);
    expect(
        File('lib/page/settings_page/developer/vibration_test_page.dart')
            .existsSync(),
        isFalse);
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') && !file.path.endsWith('.arb')) continue;
      final source = file.readAsStringSync();
      for (final removed in [
        'VibrationService',
        'VibrationTestPage',
        'reduceVibrationFeedback',
        'HapticFeedback.'
      ]) {
        expect(source, isNot(contains(removed)), reason: file.path);
      }
    }
  });

  test('Android blocks permission merging and framework decor-view haptics',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
        manifest,
        contains(
            'android:name="android.permission.VIBRATE" tools:node="remove"'));
    final activity =
        File('android/app/src/main/kotlin/com/modu/reader/MainActivity.kt')
            .readAsStringSync();
    expect(
        activity, contains('window.decorView.isHapticFeedbackEnabled = false'));
    expect(File('lib/page/home_page.dart').readAsStringSync(),
        contains('enableFeedback: false'));
  });
}
