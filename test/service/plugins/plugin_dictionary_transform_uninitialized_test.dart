import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/plugins/plugin_dictionary_transform.dart';

void main() {
  test(
      'without preferences a dictionary lookup creates no runtime or platform call',
      () async {
    expect(Prefs.isReady, false);
    final transform = PluginDictionaryTransform();
    expect(await transform.candidates('apples', isContextValid: () => true),
        isEmpty);
    transform.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(Prefs.isReady, false);
  });
}
