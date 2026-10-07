import 'package:anx_reader/utils/app_motion.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';

import 'package:anx_reader/service/feedback/crash_journal.dart';

/// Do not expose the library or start sync until storage is ready.
class AndroidStorageStartup extends StatefulWidget {
  const AndroidStorageStartup({super.key, required this.start});
  final Future<void> Function() start;

  @override
  State<AndroidStorageStartup> createState() => _AndroidStorageStartupState();
}

class _AndroidStorageStartupState extends State<AndroidStorageStartup> {
  bool? _storageError;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _storageError = null;
    });
    try {
      await widget.start();
    } catch (error, stack) {
      CrashJournal.recordError(error, stack);
      if (mounted) {
        setState(() {
          _running = false;
          _storageError = error is FileSystemException;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        // Preferences are unavailable until storage preparation finishes.
        // Use the system locale here without accessing the preferences store.
        localeListResolutionCallback: resolveAppLocale,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Builder(
            builder: (context) => Scaffold(
                    body: SafeArea(
                        child: Center(
                            child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_running)
                      const EinkStaticIndicator(
                          child: CircularProgressIndicator()),
                    const SizedBox(height: 20),
                    Text(
                        _storageError == null
                            ? ModuStrings.text(
                                context,
                                '正在准备应用数据…\n首次迁移到 Android/data 可能需要一些时间。',
                                'Preparing app data…\nThe first migration to Android/data may take some time.')
                            : _storageError!
                                ? ModuStrings.text(
                                    context,
                                    '存储读写或迁移未完成。请检查可用空间和存储权限后重试。',
                                    'Storage access or migration did not complete. Check free space and storage permissions, then retry.')
                                : ModuStrings.text(
                                    context,
                                    '应用数据准备失败，请重试；若持续失败，请保留数据并反馈问题。',
                                    'App data preparation failed. Retry; if the problem persists, keep your data and report the issue.'),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text(
                        ModuStrings.text(context, '不会清空书库。迁移完成前请勿卸载应用或手动移动文件。',
                            'Your library will not be cleared. Do not uninstall the app or move files manually before migration finishes.'),
                        textAlign: TextAlign.center),
                    if (!_running)
                      TextButton(
                          onPressed: _start,
                          child:
                              Text(ModuStrings.text(context, '重试', 'Retry'))),
                  ]),
                ))))),
      );
}
