import 'dart:async';

import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/widgets.dart';

/// Observe slow reader calls from Dart, whose timer does not depend on the
/// reader's JavaScript timers. This does not retry cursor mutations, cancel
/// playback or change its state. Never pass book text/CFIs/credentials as phase.
Future<T> waitForTtsReader<T>(
  String phase,
  Future<T> Function() work, {
  Duration reportAfter = const Duration(seconds: 5),
  void Function(String)? report,
}) async {
  final watch = Stopwatch()..start();
  var slow = false;
  void log(String event) {
    try {
      final lifecycle =
          WidgetsBinding.instance.lifecycleState?.name ?? 'unknown';
      (report ?? AnxLog.warning)(
          'TTS reader $phase $event; lifecycle=$lifecycle; elapsedMs=${watch.elapsedMilliseconds}');
    } catch (_) {
      // Diagnostics must never change the result of a navigation request.
    }
  }

  final timer = Timer(reportAfter, () {
    slow = true;
    log('waiting');
  });
  try {
    return await work();
  } finally {
    timer.cancel();
    if (slow) log('settled');
    watch.stop();
  }
}
