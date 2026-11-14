import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/reader_toolbar_visibility.dart';

void main() {
  test('enabling reveals once and hides after five seconds', () {
    fakeAsync((clock) {
      final visibility = ReaderToolbarVisibility();
      var changes = 0;
      visibility.addListener(() => changes++);
      expect(visibility.visible, isFalse);
      expect(visibility.enabled, isFalse);
      visibility.reveal();
      expect(changes, 0);

      visibility.setEnabled(true);
      expect(visibility.visible, isTrue);
      expect(visibility.enabled, isTrue);
      clock.elapse(const Duration(seconds: 4));
      visibility.setEnabled(true);
      clock.elapse(const Duration(seconds: 1));
      expect(visibility.visible, isFalse);
      expect(visibility.enabled, isTrue);
      expect(changes, 2);
      visibility.dispose();
    });
  });

  test('revealing shows a hidden toolbar and resets its timeout', () {
    fakeAsync((clock) {
      final visibility = ReaderToolbarVisibility()..setEnabled(true);
      clock.elapse(ReaderToolbarVisibility.hideDelay);
      visibility.reveal();
      expect(visibility.visible, isTrue);
      clock.elapse(const Duration(seconds: 4));
      visibility.reveal();
      clock.elapse(const Duration(seconds: 4));
      expect(visibility.visible, isTrue);
      clock.elapse(const Duration(seconds: 1));
      expect(visibility.visible, isFalse);
      visibility.dispose();
    });
  });

  test('holding pauses hiding until five seconds after release', () {
    fakeAsync((clock) {
      final visibility = ReaderToolbarVisibility()..setEnabled(true);
      clock.elapse(const Duration(seconds: 4));
      visibility.hold(true);
      clock.elapse(const Duration(minutes: 1));
      visibility.reveal();
      clock.elapse(const Duration(minutes: 1));
      expect(visibility.visible, isTrue);
      expect(clock.pendingTimers, isEmpty);
      visibility.hold(false);
      clock.elapse(const Duration(seconds: 4));
      expect(visibility.visible, isTrue);
      clock.elapse(const Duration(seconds: 1));
      expect(visibility.visible, isFalse);
      visibility.dispose();
    });
  });

  test('disabling cancels timers and ignores reveal until enabled again', () {
    fakeAsync((clock) {
      final visibility = ReaderToolbarVisibility()..setEnabled(true);
      visibility.hold(true);
      visibility.setEnabled(false);
      visibility.setEnabled(false);
      visibility.reveal();
      expect(visibility.visible, isFalse);
      expect(visibility.enabled, isFalse);
      expect(clock.pendingTimers, isEmpty);
      visibility.setEnabled(true);
      expect(visibility.visible, isTrue);
      clock.elapse(ReaderToolbarVisibility.hideDelay);
      expect(visibility.visible, isFalse);
      visibility.dispose();
    });
  });

  test('disposing cancels timers and rejects subsequent changes', () {
    fakeAsync((clock) {
      final visibility = ReaderToolbarVisibility()..setEnabled(true);
      var changes = 0;
      visibility.addListener(() => changes++);
      visibility.dispose();
      visibility.setEnabled(true);
      visibility.reveal();
      visibility.hold(false);
      clock.elapse(const Duration(minutes: 1));
      expect(clock.pendingTimers, isEmpty);
      expect(visibility.visible, isFalse);
      expect(visibility.enabled, isFalse);
      expect(changes, 0);
    });
  });
}
