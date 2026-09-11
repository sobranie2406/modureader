import 'dart:async';
import 'package:anx_reader/utils/webView/reader_operation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const timeout = Duration(milliseconds: 20);
  test('native result and error propagate', () async {
    expect(
        await waitForReaderOperation(Future.value(7),
            stage: 'toc', timeout: timeout),
        7);
    await expectLater(
        waitForReaderOperation(Future<int>.error(StateError('x')),
            stage: 'toc', timeout: timeout),
        throwsStateError);
  });
  test('a silent native channel cannot hold the task indefinitely', () async {
    await expectLater(
        waitForReaderOperation(Completer<int>().future,
            stage: 'create', timeout: timeout),
        throwsA(isA<TimeoutException>()));
  });
  test('late native failure after timeout is observed', () async {
    final native = Completer<int>();
    await expectLater(
        waitForReaderOperation(native.future,
            stage: 'chapter', timeout: timeout),
        throwsA(isA<TimeoutException>()));
    native.completeError(StateError('late callback'));
    await Future<void>.delayed(Duration.zero);
  });
  test('cancellation interrupts a pending call and ignores late success',
      () async {
    final native = Completer<int>();
    var cancelled = false;
    final pending = waitForReaderOperation(native.future,
        stage: 'chapter',
        timeout: const Duration(seconds: 3),
        isCancelled: () => cancelled);
    cancelled = true;
    await expectLater(pending, throwsA(isA<ReaderOperationCancelled>()));
    native.complete(7);
    await Future<void>.delayed(Duration.zero);
  });
  test('already cancelled operation still observes later errors', () async {
    final native = Completer<int>();
    await expectLater(
        waitForReaderOperation(native.future,
            stage: 'load', timeout: timeout, isCancelled: () => true),
        throwsA(isA<ReaderOperationCancelled>()));
    native.completeError(StateError('late'));
    await Future<void>.delayed(Duration.zero);
  });
}
