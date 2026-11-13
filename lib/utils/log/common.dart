import 'dart:async';
import 'dart:io';
import 'package:modu_reader/utils/log/environment.dart';
import 'package:modu_reader/service/feedback/detailed_runtime_log.dart';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/utils/log/string_to_level.dart';
import 'package:modu_reader/utils/get_path/log_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class AnxLog {
  static final log = Logger('Modu');
  static late File? logFile;

  Level level;
  DateTime time;
  String message;

  AnxLog(this.level, this.time, this.message);

  get color => level == Level.SEVERE
      ? Colors.red
      : level == Level.WARNING
          ? Colors.orange
          : Colors.grey;

  static AnxLog parse(String log) {
    try {
      final logParts = log.split('^*^');
      final level = stringToLevel(logParts[0]);
      final time = DateTime.parse(logParts[1].trim());
      final message = logParts[2];
      return AnxLog(level, time, message);
    } catch (e) {
      return AnxLog(Level.SEVERE, DateTime.now(), 'Parse log error: $e');
    }
  }

  static Future<void> init() async {
    logFile = await getLogFile();

    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      try {
        DetailedRuntimeLog.record(record);
      } catch (_) {
        // Diagnostic extraction must not interrupt ordinary logging/app work.
      }
      if (kDebugMode) {
        String colorCode = '';
        if (record.level == Level.SEVERE) {
          colorCode = '\x1B[31m';
        } else if (record.level == Level.WARNING) {
          colorCode = '\x1B[33m';
        } else if (record.level == Level.INFO) {
          colorCode = '\x1B[34m';
        }
        print(
            '$colorCode${record.level.name}: ${record.time}: ${record.message} \x1B[0m');
        if (record.error != null) {
          print('$colorCode${record.error} \x1B[0m');
        }
        if (record.stackTrace != null) {
          print('$colorCode${record.stackTrace} \x1B[0m');
        }
      }
      String error = record.error == null ? '' : ' : ${record.error}';
      logFile!.writeAsStringSync(
          '${'${record.level.name}^*^ ${record.time}^*^ [${record.message}]$error,${record.stackTrace}'.replaceAll('\n', ' ')}\n',
          mode: FileMode.append);
    });
    if (Prefs().clearLogWhenStart) {
      clear();
    }
    info('Log file: ${logFile!.path}');
    unawaited(LogEnvironment.collect().then((environment) {
      for (final line in environment.split('\n')) {
        info('Environment: $line');
      }
    }));
  }

  static void clear() {
    logFile!.writeAsStringSync('');
    DetailedRuntimeLog.clear();
  }

  static info(String message, [Object? error, StackTrace? stackTrace]) {
    log.info(message, error, stackTrace);
  }

  static warning(String message, [Object? error, StackTrace? stackTrace]) {
    log.warning(message, error, stackTrace);
  }

  static severe(String message, [Object? error, StackTrace? stackTrace]) {
    stackTrace ??= StackTrace.current;
    log.severe(message, error, stackTrace);
  }
}
