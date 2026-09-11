import 'dart:async';

class ReaderOperationCancelled implements Exception {
  const ReaderOperationCancelled();
  @override
  String toString() => 'Reader operation cancelled';
}

/// Bounds the caller's wait, not the native operation itself. The owner must
/// still dispose its WebView, including a creation that completes late.
Future<T> waitForReaderOperation<T>(
  Future<T> operation, {
  required String stage,
  required Duration timeout,
  bool Function()? isCancelled,
}) async {
  final result = Completer<T>();
  void cancelIfNeeded() {
    if (!result.isCompleted && (isCancelled?.call() ?? false)) {
      result.completeError(const ReaderOperationCancelled());
    }
  }

  // Attach handlers before checking cancellation: late native failures must
  // never become unhandled errors after a timeout/cancel has won the race.
  operation.then((value) {
    cancelIfNeeded();
    if (!result.isCompleted) result.complete(value);
  }, onError: (Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  });
  final deadline = Timer(timeout, () {
    if (!result.isCompleted) {
      result
          .completeError(TimeoutException('Reader $stage timed out', timeout));
    }
  });
  final cancellation = isCancelled == null
      ? null
      : Timer.periodic(
          const Duration(milliseconds: 100), (_) => cancelIfNeeded());
  cancelIfNeeded();
  try {
    return await result.future;
  } finally {
    deadline.cancel();
    cancellation?.cancel();
  }
}
