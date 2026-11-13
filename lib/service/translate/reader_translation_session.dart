import 'dart:async';
import 'package:modu_reader/service/ai/langchain_runner.dart';

class TranslationCancelled implements Exception {}

/// Explicit, in-memory consent for one reader instance. Never restored on open.
class ReaderTranslationSession {
  /// WKWebView can bridge an integral JavaScript number as a Dart double.
  static int? bridgeGeneration(Object? value) => value is num &&
          value.isFinite &&
          value >= 0 &&
          value <= 9007199254740991 &&
          value == value.truncateToDouble()
      ? value.toInt()
      : null;

  int generation = 0;
  bool enabled = false;
  final _cancelRequests = <void Function()>{};

  int start() {
    stop();
    enabled = true;
    return generation;
  }

  void stop() {
    enabled = false;
    generation++;
    for (final cancel in _cancelRequests.toList()) {
      cancel();
    }
  }

  Future<String> translate(int requestGeneration,
      Stream<String> Function(CancelableLangchainRunner) source) async {
    if (!enabled || requestGeneration != generation) {
      throw TranslationCancelled();
    }
    final runner = CancelableLangchainRunner();
    final done = Completer<String>();
    StreamSubscription<String>? subscription;
    String last = '';
    void cancel() {
      if (!done.isCompleted) done.completeError(TranslationCancelled());
      unawaited(runner.cancel());
      unawaited(subscription?.cancel());
    }

    _cancelRequests.add(cancel);
    try {
      subscription = source(runner).listen((value) {
        last = value;
      }, onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      }, onDone: () {
        if (!done.isCompleted) {
          if (last.trim().isEmpty || last == '...') {
            done.completeError(StateError('Translation returned no answer'));
          } else {
            done.complete(last);
          }
        }
      });
      return await done.future;
    } finally {
      _cancelRequests.remove(cancel);
      unawaited(runner.cancel());
      unawaited(subscription?.cancel());
    }
  }
}
