import 'package:shared_preferences/shared_preferences.dart';

const bundledModelDefaultsKey = 'bundledModelDefaults6326';

/// Reissued-Beta migration: retain credentials, but require explicit opt-in
/// before automatic indexing or remote embedding requests.
Future<void> applyBundledModelDefaults(SharedPreferences preferences) async {
  if (preferences.getBool(bundledModelDefaultsKey) == true) return;
  await preferences.setString('vectorModelMode', 'builtin');
  await preferences.setString('vectorLocalModelId', 'bge-small-zh-v1.5');
  await preferences.setBool('autoVectorizeOnImport', false);
  await preferences.setBool(bundledModelDefaultsKey, true);
}
