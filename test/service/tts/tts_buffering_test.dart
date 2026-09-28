import 'dart:async';

import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:flutter_test/flutter_test.dart';

class BufferingBackend extends BaseTts {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('short chapter transitions do not flash a loading notification',
      (tester) async {
    final backend = BufferingBackend();
    final finish = backend.beginBuffering();
    await tester.pump(const Duration(milliseconds: 200));
    expect(backend.bufferingNotifier.value, isFalse);
    finish();
    await tester.pump(const Duration(seconds: 1));
    expect(backend.bufferingNotifier.value, isFalse);
  });

  testWidgets(
      'loading clears on completion and overlapping waits remain loading',
      (tester) async {
    final backend = BufferingBackend();
    final finishFirst = backend.beginBuffering();
    final finishSecond = backend.beginBuffering();
    await tester.pump(const Duration(milliseconds: 301));
    expect(backend.bufferingNotifier.value, isTrue);
    finishFirst();
    expect(backend.bufferingNotifier.value, isTrue);
    finishSecond();
    expect(backend.bufferingNotifier.value, isFalse);
  });

  testWidgets('old wait cannot clear a new session after stop', (tester) async {
    final backend = BufferingBackend();
    final old = backend.beginBuffering();
    backend.clearBuffering();
    final fresh = backend.beginBuffering();
    await tester.pump(const Duration(milliseconds: 301));
    old();
    expect(backend.bufferingNotifier.value, isTrue);
    fresh();
    expect(backend.bufferingNotifier.value, isFalse);
  });

  testWidgets('reader errors clear waiting without swallowing the failure',
      (tester) async {
    final backend = BufferingBackend();
    final input = Completer<String>();
    final waiting = backend.waitForSpeechInput(() => input.future);
    final failure = expectLater(waiting, throwsStateError);
    await tester.pump(const Duration(milliseconds: 301));
    expect(backend.bufferingNotifier.value, isTrue);
    input.completeError(StateError('chapter unavailable'));
    await tester.pump();
    await failure;
    expect(backend.bufferingNotifier.value, isFalse);
  });
}
