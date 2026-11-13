import 'dart:async';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/version_check_type.dart';
import 'package:modu_reader/main.dart';
import 'package:modu_reader/utils/app_version.dart';
import 'package:flutter/cupertino.dart';
import 'package:modu_reader/page/changelog_screen.dart';
import 'package:modu_reader/utils/log/common.dart';

class InitializationCheck {
  static String? _lastVersion;
  static String? _currentVersion;
  static Future<void>? _checking;
  static bool _showingUpdate = false;

  static Future<String> get lastVersion async {
    if (_lastVersion == null) await _checkVersion();
    return _lastVersion ?? _currentVersion!;
  }

  static Future<String> get currentVersion async {
    if (_currentVersion == null) await _checkVersion();
    return _currentVersion!;
  }

  static Future<void> check() =>
      _checking ??= _runCheck().whenComplete(() => _checking = null);

  static Future<void> _runCheck() async {
    if (_showingUpdate) return;
    final result = await _checkVersion();
    AnxLog.info('Version check result: $result');
    if (result == VersionCheckType.firstLaunch) {
      await Prefs().saveLastAppVersion(_currentVersion!);
      _handleNormalStartup();
    } else if (result == VersionCheckType.updated) {
      unawaited(_handleUpdateAvailable(_lastVersion!, _currentVersion!));
    } else {
      _handleNormalStartup();
    }
  }

  static Future<VersionCheckType> _checkVersion() async {
    _lastVersion = Prefs().lastAppVersion;
    _currentVersion = await getAppVersion();
    if (_lastVersion == null) return VersionCheckType.firstLaunch;
    return _lastVersion != _currentVersion
        ? VersionCheckType.updated
        : VersionCheckType.normal;
  }

  static Future<void> _handleUpdateAvailable(
      String previous, String current) async {
    _showingUpdate = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final dismissed = showCupertinoSheet<void>(
        context: context,
        scrollableBuilder: (sheetContext, controller) => ChangelogScreen(
          lastVersion: previous,
          currentVersion: current,
          onComplete: () => Navigator.pop(sheetContext),
        ),
      );
      // Back, swipe-to-dismiss and process exit must not show the same notes again.
      try {
        await Prefs().saveLastAppVersion(current);
      } catch (_) {
        AnxLog.warning('Could not persist the displayed release notes version');
      }
      await dismissed;
    } catch (_) {
      AnxLog.warning('Could not open release notes');
    } finally {
      _showingUpdate = false;
    }
  }

  static void _handleNormalStartup() {
    AnxLog.info('Normal startup, proceeding to main app');
  }
}
