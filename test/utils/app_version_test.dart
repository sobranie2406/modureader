import 'package:modu_reader/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Harmony restores beta identity only for matching native version/build',
      () {
    const release = '1.2.11-beta.1+10130';
    expect(
        installedAppVersion('1.2.11', '10130', harmonyReleaseVersion: release),
        release);
    expect(
        installedAppVersion('1.2.11', '10131', harmonyReleaseVersion: release),
        '1.2.11+10131');
    expect(
        installedAppVersion('1.2.12', '10130', harmonyReleaseVersion: release),
        '1.2.12+10130');
    expect(
        installedAppVersion('1.2.11.1', '10130',
            harmonyReleaseVersion: release),
        '1.2.11.1+10130');
    expect(
        installedAppVersion('1.2.11', '10130',
            harmonyReleaseVersion: 'invalid'),
        '1.2.11+10130');
    expect(installedAppVersion('1.2.11-beta.1', '10130'), release);
    expect(installedAppVersion('1.2.11', ''), '1.2.11');
  });
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
