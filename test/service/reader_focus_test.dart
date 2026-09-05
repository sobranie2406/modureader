import 'package:anx_reader/service/reader_focus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.modu.reader/reader_focus');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('macOS restores AppKit first responder through the desktop bridge',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return true;
    });
    await restoreNativeReaderFocus();
    expect(methods, ['restore']);
  });
  test('other platforms do not invoke the desktop bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return true;
    });
    await restoreNativeReaderFocus();
    expect(called, isFalse);
  });
  test('missing native host does not crash the reader', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await restoreNativeReaderFocus();
  });
}
