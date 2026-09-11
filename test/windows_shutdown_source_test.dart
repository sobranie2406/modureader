import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Structural safeguards complement the native CI launch/close smoke test.
  test('explicit runner teardown precedes COM uninitialization', () {
    final main = File('windows/runner/main.cpp').readAsStringSync();
    expect(main.indexOf('window.Destroy();'), greaterThan(0));
    expect(main.indexOf('window.Destroy();'),
        lessThan(main.indexOf('::CoUninitialize();')));
  });
  test('creation resets the pre-Create Destroy guard; teardown is idempotent',
      () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final create = source.substring(
        source.indexOf('bool FlutterWindow::OnCreate()'),
        source.indexOf('void FlutterWindow::OnDestroy()'));
    expect(create, contains('destroying_ = false;'));
    final destroy = source.substring(
        source.indexOf('void FlutterWindow::OnDestroy()'),
        source.indexOf('LRESULT\nFlutterWindow::MessageHandler'));
    expect(destroy.indexOf('destroying_ = true;'),
        lessThan(destroy.indexOf('flutter_controller_ = nullptr;')));
    expect(destroy, contains('if (destroying_) return;'));
    expect(source, contains('if (!destroying_ && flutter_controller_)'));
  });
}
