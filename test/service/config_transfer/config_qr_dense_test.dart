import 'dart:io';
import 'package:anx_reader/service/config_transfer/config_qr_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dense generated symbol roundtrips when finder-pattern detection fails',
      () async {
    // Synthetic configuration only; fixed payload reproduces the QR mask.
    const token =
        'modu:H4sIAAAAAAAAE42SQWvbQBCF/8ucJUdWQ0r35rqUlDZgGtFCI2PWu1Nr0GpH7I6MVaP/XqQSx9CDdX18b96bYc5wxBCJPahlAjV5Cwoatl16cLzXLo0oQv4QIQGrRYM636Au8/IEouEWQYEmSMAE1IJ2JaAgz/KHNPuQ5g9Flqv7TOXLxft8md8vf0ECbcDfGNAbjGPebjcK8aM2ddf+uKqraRP4SBbDxEk/hUUJ5A9jE+26UXg5l0C2BFWCYJQSkhKExOEkFa9SF9wkVCJtVHd3eNJN63Bx8bSBhQ3/o7hFr2nSa+y/eIunElSWlKBb+op9LEFdBdfYv7KXIil716cRTUApYdgOWxjGpQpsWgxauoBXa1nu9g7f1soW74YE0Ou9Q7uigtn9f4VvFOXN8gIRdTDVbs9cR9hOad/b5soWMOKVw3fOTdSTPhVco48z2DV7wZMUXZiBN/q0orU2Fa658zJnfKXlM3t5pj84A99oj+4nWanmwo9Ih+p2k4gOzfjQ9IzhSGZ2mQ1HkumHb/CGLT7SoXJjn6LCZk7EeJ5PFFun+ye2txzDMPwF1oDwZgMEAAA=';
    final dir = await Directory.systemTemp.createTemp('modu-dense-qr-');
    try {
      final path = '${dir.path}/config.png';
      await File(path).writeAsBytes((await ConfigQrBridge.generate(token))!);
      expect(await ConfigQrBridge.decodeImage(path), token);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
