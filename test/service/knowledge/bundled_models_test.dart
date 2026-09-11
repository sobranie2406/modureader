import 'package:anx_reader/service/knowledge/bundled_model_defaults.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install defaults to local Chinese BGE without auto indexing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await applyBundledModelDefaults(prefs);
    expect(prefs.getString('vectorModelMode'), 'builtin');
    expect(prefs.getString('vectorLocalModelId'), 'bge-small-zh-v1.5');
    expect(prefs.getBool('autoVectorizeOnImport'), isFalse);
  });

  test('upgrade disables auto/remote once, preserves keys and later choices',
      () async {
    SharedPreferences.setMockInitialValues({
      'vectorModelMode': 'remote',
      'autoVectorizeOnImport': true,
      'vectorModelConfig': '{"apiKey":"test-not-a-real-key"}',
      'vectorModelEnabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await applyBundledModelDefaults(prefs);
    expect(prefs.getString('vectorModelMode'), 'builtin');
    expect(prefs.getBool('autoVectorizeOnImport'), isFalse);
    expect(prefs.getBool('vectorModelEnabled'), isFalse);
    expect(prefs.getString('vectorModelConfig'),
        '{"apiKey":"test-not-a-real-key"}');
    await prefs.setString('vectorModelMode', 'remote');
    await prefs.setBool('autoVectorizeOnImport', true);
    await applyBundledModelDefaults(prefs);
    expect(prefs.getString('vectorModelMode'), 'remote');
    expect(prefs.getBool('autoVectorizeOnImport'), isTrue);
  });
}
