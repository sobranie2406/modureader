import 'package:anx_reader/config/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Modu public identity is stable', () {
    expect(AppIdentity.zhDisplayName, '默读');
    expect(AppIdentity.globalDisplayName, 'Modu');
    expect(AppIdentity.bundleId, 'com.modu.reader');
  });
}
