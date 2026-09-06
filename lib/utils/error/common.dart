import 'dart:ui';
import 'package:anx_reader/service/feedback/crash_journal.dart';

import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class AnxError {
  static Future<void> init() async {
    AnxLog.info('AnxError init');
    FlutterError.onError = (details) {
      CrashJournal.recordError(details.exception, details.stack,
          framework: true);
      FlutterError.presentError(details);
      AnxLog.severe(details.exceptionAsString(), details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashJournal.recordError(error, stack);
      AnxLog.severe(error.toString(), stack);
      return false;
    };
  }
}
