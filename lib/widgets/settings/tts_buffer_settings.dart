import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/tts_buffer_settings.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

class TtsBufferSettingsSection extends StatefulWidget {
  const TtsBufferSettingsSection({super.key, required this.online});
  final bool online;

  @override
  State<TtsBufferSettingsSection> createState() =>
      _TtsBufferSettingsSectionState();
}

class _TtsBufferSettingsSectionState extends State<TtsBufferSettingsSection> {
  String tr(String zh, String en) => ModuStrings.text(context, zh, en);

  void _save(String key, int value) {
    final map = Prefs().ttsBufferSettings.toMap()..[key] = value;
    Prefs().ttsBufferSettings = TtsBufferSettings.fromMap(map);
    if (key == 'cacheMinutes') OnlineTts.updateCacheRetention();
  }

  AbstractSettingsTile _choice(
      String key, String title, String hint, int value, List<int> options) {
    final choices = {...options, value}.toList()..sort();
    return CustomSettingsTile(
        child: ListTile(
      enabled: widget.online,
      title: SettingHelp(title: Text(title), description: Text(hint)),
      trailing: DropdownButton<int>(
        key: ValueKey('tts-buffer-$key'),
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final choice in choices)
            DropdownMenuItem(value: choice, child: Text('$choice'))
        ],
        onChanged: widget.online
            ? (v) {
                if (v != null) _save(key, v);
              }
            : null,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Prefs(),
        builder: (context, _) {
          final settings = Prefs().ttsBufferSettings;
          final size =
              (OnlineTts.cachedAudioBytes / (1024 * 1024)).toStringAsFixed(1);
          return SettingsSection(
            title: Text(tr('在线朗读缓冲与缓存', 'Online speech buffering and cache')),
            tiles: [
              CustomSettingsTile(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: SettingHelp(
                    title: Text(
                        ModuStrings.text(context, "缓冲设置", "Buffer settings")),
                    description: Text(widget.online
                        ? tr("修改后停止朗读，再重新开始即可生效。",
                            "Stop and restart narration to apply these changes.")
                        : tr("选择在线朗读服务后，可调整预合成设置。",
                            "Select an online speech service to adjust pre-synthesis settings."))),
              )),
              _choice(
                  'ahead',
                  tr('提前缓冲量（段）', 'Lookahead (passages)'),
                  tr('不含当前正在朗读的一段；0 表示不提前合成。',
                      'Excludes the active passage; 0 disables lookahead.'),
                  settings.ahead,
                  [0, 1, 3, 5, 8, 12]),
              _choice(
                  'maxCharacters',
                  tr('单次合成字数上限', 'Maximum characters per request'),
                  tr("设置每段合成文字的字数上限。",
                      "Set the maximum text length per synthesis request."),
                  settings.maxCharacters,
                  [100, 240, 400, 600, 1000, 1500, 2000]),
              _choice(
                  'concurrency',
                  tr('预合成并发数', 'Synthesis concurrency'),
                  tr('优先准备首段，其余请求按此上限并发。',
                      'Prepare the first passage first, then use this concurrency limit.'),
                  settings.concurrency,
                  [1, 2, 3, 4]),
              _choice(
                  'paragraphPauseMs',
                  tr('段落停顿（毫秒）', 'Paragraph pause (ms)'),
                  tr("设置自然段之间的停顿。", "Set the pause between paragraphs."),
                  settings.paragraphPauseMs,
                  [0, 100, 200, 300, 500, 1000, 2000, 3000]),
              _choice(
                  'cacheMinutes',
                  tr('音频缓存保留时间（分钟）', 'Audio cache retention (minutes)'),
                  tr("设置音频缓存保留时长，0 表示停止朗读时清理。",
                      "Set how long to keep cached audio. Use 0 to clear it when narration stops."),
                  settings.cacheMinutes,
                  [0, 5, 10, 30, 60, 120]),
              CustomSettingsTile(
                  child: Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        key: const ValueKey('tts-clear-cache'),
                        leading: const Icon(Icons.delete_outline),
                        title: Text(tr('清理音频缓存', 'Clear audio cache')),
                        subtitle: Text(tr('缓存 $size MiB', '$size MiB cached')),
                        onTap: () {
                          OnlineTts.clearCachedAudio();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text(tr('音频缓存已清理', 'Audio cache cleared'))));
                        },
                      ))),
            ],
          );
        },
      );
}
