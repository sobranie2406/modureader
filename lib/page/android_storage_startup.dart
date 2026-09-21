import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:anx_reader/service/feedback/crash_journal.dart';

/// Do not expose the library or start sync until storage is ready.
class AndroidStorageStartup extends StatefulWidget {
  const AndroidStorageStartup({super.key, required this.start});
  final Future<void> Function() start;

  @override
  State<AndroidStorageStartup> createState() => _AndroidStorageStartupState();
}

class _AndroidStorageStartupState extends State<AndroidStorageStartup> {
  String? _error;
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
      _error = null;
    });
    try {
      await widget.start();
    } catch (error, stack) {
      CrashJournal.recordError(error, stack);
      if (mounted) {
        setState(() {
          _running = false;
          _error = error is FileSystemException
              ? '存储读写或迁移未完成。请检查可用空间和存储权限后重试。'
              : '应用数据准备失败，请重试；若持续失败，请保留数据并反馈问题。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            body: SafeArea(
                child: Center(
                    child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_running) const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_error ?? '正在准备应用数据…\n首次迁移到 Android/data 可能需要一些时间。',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text('不会清空书库。迁移完成前请勿卸载应用或手动移动文件。',
                textAlign: TextAlign.center),
            if (!_running)
              TextButton(onPressed: _start, child: const Text('重试')),
          ]),
        )))),
      );
}
