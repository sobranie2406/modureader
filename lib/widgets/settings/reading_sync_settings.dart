import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/sync/reading_sync_scheduler.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

class ReadingSyncSettings extends AbstractSettingsTile {
  const ReadingSyncSettings({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Prefs(),
        builder: (context, _) {
          final prefs = Prefs();
          final zh = Localizations.localeOf(context).languageCode == 'zh';
          String duration(int minutes) => minutes == 60
              ? (zh ? '1 小时' : '1 hour')
              : zh
                  ? '$minutes 分钟'
                  : '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
          final enabled = prefs.webdavStatus && prefs.autoSync;
          return Column(children: [
            SettingsTile.switchTile(
              key: const ValueKey('reading-timed-sync'),
              title: Text(zh ? '阅读时定时同步' : 'Sync periodically while reading'),
              description: Text(!enabled
                  ? (zh
                      ? '请先启用 WebDAV 和自动同步。'
                      : 'Enable WebDAV and automatic sync first.')
                  : (zh
                      ? '仅前台阅读时计时；退出书籍、切换其他页面或锁屏后暂停。使用双向合并，同步已保存的笔记、阅读进度及其他正常同步内容；不自动保存编辑草稿。'
                      : 'Runs only while reading in the foreground. Pauses on other pages or in the background. Merges saved notes, reading positions and normal sync data; unsaved drafts are not submitted.')),
              leading: const Icon(Icons.schedule),
              initialValue: prefs.readingTimedSync,
              enabled: enabled,
              onToggle:
                  enabled ? (value) => prefs.readingTimedSync = value : null,
            ),
            SettingsTile.navigation(
              key: const ValueKey('reading-sync-interval'),
              title: Text(zh ? '阅读同步间隔' : 'Reading sync interval'),
              value: Text(duration(prefs.readingSyncMinutes)),
              description: Text(zh
                  ? '进入或恢复阅读后等待一个完整间隔；同步期间不重复发起，结束后重新计时。遵循“仅 Wi-Fi”设置。'
                  : 'Waits a full interval on entry or resume. No overlapping runs; restarts the interval after completion. Respects Wi-Fi-only sync.'),
              leading: const Icon(Icons.timer_outlined),
              enabled: enabled && prefs.readingTimedSync,
              onPressed: (_) async {
                final selected = await showDialog<int>(
                    context: context,
                    builder: (dialogContext) => SimpleDialog(
                          title: Text(zh ? '阅读同步间隔' : 'Reading sync interval'),
                          children: readingSyncIntervals
                              .map((minutes) => SimpleDialogOption(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, minutes),
                                    child: Row(children: [
                                      SizedBox(
                                          width: 32,
                                          child: prefs.readingSyncMinutes ==
                                                  minutes
                                              ? const Icon(Icons.check,
                                                  size: 20)
                                              : null),
                                      Text(duration(minutes)),
                                    ]),
                                  ))
                              .toList(),
                        ));
                if (selected != null) prefs.readingSyncMinutes = selected;
              },
            ),
          ]);
        },
      );
}
