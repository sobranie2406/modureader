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
      title: Text(title),
      subtitle: Text(hint),
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
                child: Text(widget.online
                    ? tr(
                        '缓冲量、合成字数、并发和段落停顿在停止后重新开始朗读时生效；暂停继续保持原设置。预合成可能产生额外用量，并发过高可能触发服务限流。',
                        'Buffering, text limits, concurrency and paragraph pauses apply after stopping and restarting speech, not pause/resume. Prefetching may incur extra usage; high concurrency may trigger service limits.')
                    : tr('系统 TTS 由设备语音引擎管理，不应用以下在线预合成设置。切换到在线朗读后可调整。',
                        'System TTS is managed by the device engine. Switch to an online service to adjust these pre-synthesis settings.')),
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
                  tr('按自然段和句子边界分段，长句安全拆分；这是上限，不强行凑满。',
                      'Respects paragraphs and sentence boundaries; long sentences are split. This is a limit, not a target.'),
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
                  tr('只在自然段末尾额外停顿，不在长段落的拆分处停顿。',
                      'Extra pause at paragraph ends, not between chunks of a long paragraph.'),
                  settings.paragraphPauseMs,
                  [0, 100, 200, 300, 500, 1000, 2000, 3000]),
              _choice(
                  'cacheMinutes',
                  tr('音频缓存保留时间（分钟）', 'Audio cache retention (minutes)'),
                  tr('立即生效。0：停止朗读时清理。仅内存缓存，上限 32 MiB；退出应用不保留。',
                      'Applies immediately. 0 clears on stop. Memory only, up to 32 MiB; not retained after app exit.'),
                  settings.cacheMinutes,
                  [0, 5, 10, 30, 60, 120]),
              CustomSettingsTile(
                  child: Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        key: const ValueKey('tts-clear-cache'),
                        leading: const Icon(Icons.delete_outline),
                        title: Text(tr('清理音频缓存', 'Clear audio cache')),
                        subtitle: Text(tr('可复用缓存 $size MiB；不打断当前朗读，已准备的播放队列保留。',
                            '$size MiB reusable cache; current playback and prepared queue are retained.')),
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
