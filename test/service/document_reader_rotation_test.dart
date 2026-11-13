import 'package:modu_reader/service/document_reader_rotation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('desktop rotation resizes the whole viewport and restores on exit',
      () async {
    const channel = MethodChannel('window_manager');
    final sizes = <List<num>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getBounds') {
        return {'x': 0.0, 'y': 0.0, 'width': 800.0, 'height': 600.0};
      }
      if (call.method == 'setBounds') {
        sizes.add([call.arguments['width'], call.arguments['height']]);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final rotation = DocumentReaderRotation();
    await rotation.set(0);
    expect(sizes, isEmpty);
    await rotation.set(90);
    await rotation.set(180);
    await rotation.set(270);
    await rotation.close();
    expect(sizes, [
      [600, 800],
      [800, 600],
      [600, 800],
      [800, 600]
    ]);
    await rotation.set(90);
    expect(sizes.length, 4);
  });
}
