import 'package:anx_reader/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('uses bundled version when native metadata is unavailable', () async {
    expect(await getAppVersion(), matches(RegExp(r'^\d+\.\d+\.\d+')));
  });
  test('uses installed test build rather than bundled source version',
      () async {
    PackageInfo.setMockInitialValues(
        appName: 'Modu',
        packageName: 'com.modu.reader',
        version: '1.1.6-test.1',
        buildNumber: '10048',
        buildSignature: '');
    expect(await getAppVersion(), '1.1.6-test.1+10048');
  });
}
