import 'package:modu_reader/service/knowledge/bundled_model_defaults.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install defaults to local Chinese BGE without auto indexing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await applyBundledModelDefaults(prefs);
    expect(prefs.getString('vectorLocalModelId'), 'bge-small-zh-v1.5');
    expect(prefs.getBool('autoVectorizeOnImport'), isFalse);
  });

  test('upgrade disables auto indexing once and preserves later choices',
      () async {
    SharedPreferences.setMockInitialValues({
      'autoVectorizeOnImport': true,
      'vectorModelEnabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await applyBundledModelDefaults(prefs);
    expect(prefs.getBool('autoVectorizeOnImport'), isFalse);
    expect(prefs.getBool('vectorModelEnabled'), isFalse);
    await prefs.setString('vectorLocalModelId', 'all-MiniLM-L6-v2');
    await prefs.setBool('autoVectorizeOnImport', true);
    await applyBundledModelDefaults(prefs);
    expect(prefs.getString('vectorLocalModelId'), 'all-MiniLM-L6-v2');
    expect(prefs.getBool('autoVectorizeOnImport'), isTrue);
  });
}
