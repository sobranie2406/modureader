import 'package:shared_preferences/shared_preferences.dart';

const bundledModelDefaultsKey = 'bundledModelDefaults6326';

/// Reissued-Beta migration: require explicit opt-in for automatic indexing.
Future<void> applyBundledModelDefaults(SharedPreferences preferences) async {
  if (preferences.getBool(bundledModelDefaultsKey) == true) return;
  await preferences.setString('vectorLocalModelId', 'bge-small-zh-v1.5');
  await preferences.setBool('autoVectorizeOnImport', false);
  await preferences.setBool(bundledModelDefaultsKey, true);
}
