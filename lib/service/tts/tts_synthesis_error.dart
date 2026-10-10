import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

enum TtsFailureReason {
  configuration,
  network,
  timeout,
  http,
  invalidAudio,
  truncated,
  blocked,
  unknown
}

/// Only fixed categories/status codes may be logged, never a server body or URL.
class TtsSynthesisError extends StateError {
  TtsSynthesisError(this.reason, String message,
      {this.statusCode, this.retryAfter})
      : super(message);

  final TtsFailureReason reason;
  final int? statusCode;
  final Duration? retryAfter;

  bool get retryable => switch (reason) {
        TtsFailureReason.network ||
        TtsFailureReason.timeout ||
        TtsFailureReason.invalidAudio ||
        TtsFailureReason.unknown =>
          true,
        TtsFailureReason.http => statusCode == 408 ||
            statusCode == 429 ||
            (statusCode != null && statusCode! >= 500 && statusCode! <= 599),
        _ => false,
      };

  static TtsSynthesisError classify(Object error) {
    if (error is TtsSynthesisError) return error;
    final reason = switch (error) {
      TimeoutException() => TtsFailureReason.timeout,
      SocketException() ||
      WebSocketException() ||
      http.ClientException() =>
        TtsFailureReason.network,
      FormatException() || ArgumentError() => TtsFailureReason.configuration,
      _ => TtsFailureReason.unknown,
    };
    return TtsSynthesisError(reason, 'Speech request failed');
  }

  static Duration? parseRetryAfter(String? value, {DateTime? now}) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) {
      // A very long server cooldown disables automatic retry; avoid overflow.
      return seconds < 0
          ? null
          : Duration(seconds: seconds > 86400 ? 86400 : seconds);
    }
    try {
      final delay = HttpDate.parse(value).difference(now ?? DateTime.now());
      return delay.isNegative ? Duration.zero : delay;
    } catch (_) {
      return null;
    }
  }
}
