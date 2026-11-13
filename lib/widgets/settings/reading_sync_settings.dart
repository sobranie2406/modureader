import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/sync/reading_sync_scheduler.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
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
              ? (ModuStrings.text(context, '1 小时', '1 hour'))
              : zh
                  ? '$minutes 分钟'
                  : '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
          final enabled = prefs.webdavStatus && prefs.autoSync;
          return Column(children: [
            SettingsTile.switchTile(
              key: const ValueKey('reading-timed-sync'),
              title: Text(ModuStrings.text(
                  context, '阅读时定时同步', 'Sync periodically while reading')),
              descriptionAsHelp: enabled,
              description: Text(!enabled
                  ? (ModuStrings.text(context, '请先启用云端同步和自动同步。',
                      'Enable cloud sync and automatic sync first.'))
                  : (ModuStrings.text(context, "阅读时按设定间隔同步笔记和进度。",
                      "Sync notes and progress at the selected interval while reading."))),
              leading: const Icon(Icons.schedule),
              initialValue: prefs.readingTimedSync,
              enabled: enabled,
              onToggle:
                  enabled ? (value) => prefs.readingTimedSync = value : null,
            ),
            SettingsTile.navigation(
              key: const ValueKey('reading-sync-interval'),
              title: Text(
                  ModuStrings.text(context, '阅读同步间隔', 'Reading sync interval')),
              value: Text(duration(prefs.readingSyncMinutes)),
              description: Text(ModuStrings.text(context, '选择两次自动同步之间的间隔。',
                  'Choose the interval between automatic syncs.')),
              leading: const Icon(Icons.timer_outlined),
              enabled: enabled && prefs.readingTimedSync,
              onPressed: (_) async {
                final selected = await showDialog<int>(
                    animationStyle: AppMotion.style,
                    context: context,
                    builder: (dialogContext) => SimpleDialog(
                          title: Text(ModuStrings.text(
                              context, '阅读同步间隔', 'Reading sync interval')),
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
