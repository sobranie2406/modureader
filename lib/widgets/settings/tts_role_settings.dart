import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/tts_role_config.dart';
import 'package:modu_reader/providers/tts_providers.dart';
import 'package:modu_reader/service/tts/models/tts_voice.dart';
import 'package:modu_reader/service/tts/tts_handler.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Narration/dialogue voices, plus an optional per-book override.
///
/// Splitting a passage into two voices doubles the number of synthesis
/// requests for dialogue-heavy books, so the switch is off by default and the
/// whole section stays hidden for the system engine, which cannot reliably
/// switch voices per sentence on every platform.
class TtsRoleSettingsSection extends ConsumerStatefulWidget {
  const TtsRoleSettingsSection({super.key, this.bookId});

  /// Book whose overrides are edited. Null falls back to the book that is
  /// currently being narrated (null too when opened from the settings list).
  final int? bookId;

  @override
  ConsumerState<TtsRoleSettingsSection> createState() =>
      _TtsRoleSettingsSectionState();
}

class _TtsRoleSettingsSectionState
    extends ConsumerState<TtsRoleSettingsSection> {
  List<TtsVoice>? _voices;
  String? _voicesService;
  bool _loadingVoices = false;

  TtsRoleConfig get _config => Prefs().ttsRoleConfig;

  bool get _systemEngine => Prefs().ttsService == 'system';

  int? get _bookId => widget.bookId ?? TtsHandler().playingBookId;

  Future<List<TtsVoice>?> _loadVoices() async {
    final service = Prefs().ttsService;
    if (_voices != null && _voicesService == service) return _voices;
    if (_loadingVoices) return null;
    setState(() => _loadingVoices = true);
    try {
      final voices = await ref.read(ttsVoicesProvider.future);
      if (!mounted) return null;
      if (Prefs().ttsService != service) {
        setState(() => _loadingVoices = false);
        return null;
      }
      setState(() {
        _voicesService = service;
        _voices = voices;
        _loadingVoices = false;
      });
      return voices;
    } catch (_) {
      if (mounted) setState(() => _loadingVoices = false);
      return null;
    }
  }

  String _voiceName(String shortName) {
    if (shortName.isEmpty) return '';
    for (final voice in _voices ?? const <TtsVoice>[]) {
      if (voice.shortName == shortName) return voice.name;
    }
    return shortName;
  }

  Future<void> _save(TtsRoleConfig config) async {
    await Prefs().saveTtsRoleConfig(config);
    if (mounted) setState(() {});
  }

  Future<void> _saveBook(TtsRoleBookOverride override) async {
    await Prefs().saveTtsRoleBookOverride(_bookId, override);
    if (mounted) setState(() {});
  }

  /// Per-role speed multiplier, relative to the reader's global speed.
  Future<void> _pickRate({
    required String title,
    required double current,
    required TtsRoleConfig Function(double rate) apply,
  }) async {
    var value = current;
    final result = await showDialog<double>(
      context: context,
      animationStyle: AppMotion.style,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('×${value.toStringAsFixed(2)}',
                  style: Theme.of(dialogContext).textTheme.headlineSmall),
              Slider(
                value: value,
                min: TtsRoleConfig.minRate,
                max: TtsRoleConfig.maxRate,
                divisions: 30,
                label: '×${value.toStringAsFixed(2)}',
                onChanged: (next) => setDialogState(() => value = next),
              ),
              SettingHelp(
                  title: Text(
                      ModuStrings.text(context, "速度校准", "Rate calibration")),
                  description: Text(ModuStrings.text(
                      dialogContext,
                      "调整倍率，使旁白和对话速度一致。",
                      "Adjust the rate to match narration and dialogue."))),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(1.0),
              child: Text(ModuStrings.text(dialogContext, '重置', 'Reset')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(ModuStrings.text(dialogContext, '取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(ModuStrings.text(dialogContext, '确定', 'OK')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _save(apply(result));
  }

  Future<String?> _pickVoice({
    required String title,
    required String current,
    bool allowInherit = false,
    String inheritLabel = '',
  }) async {
    final voices = await _loadVoices();
    if (!mounted) return null;
    if (voices == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ModuStrings.text(context, '无法获取音色列表，请检查朗读服务配置后重试。',
            'Could not load voices. Check the narration service settings and retry.')),
      ));
      return null;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(title,
                      style: Theme.of(sheetContext).textTheme.titleMedium),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (allowInherit)
                        ListTile(
                          leading: const Icon(Icons.subdirectory_arrow_right),
                          title: Text(inheritLabel),
                          selected: current.isEmpty,
                          onTap: () => Navigator.pop(sheetContext, ''),
                        ),
                      for (final voice in voices)
                        ListTile(
                          title: Text(voice.name.isEmpty
                              ? voice.shortName
                              : voice.name),
                          subtitle: Text(voice.locale),
                          selected: voice.shortName == current,
                          onTap: () =>
                              Navigator.pop(sheetContext, voice.shortName),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return selected;
  }

  Future<void> _pickNarration() async {
    final picked = await _pickVoice(
      title: ModuStrings.text(context, '旁白音色', 'Narration voice'),
      current: _config.narrationVoice,
      allowInherit: true,
      inheritLabel: ModuStrings.text(
          context, '跟随当前朗读音色', 'Follow the current narration voice'),
    );
    if (picked == null) return;
    await _save(_config.copyWith(narrationVoice: picked));
  }

  Future<void> _pickDialogue() async {
    final picked = await _pickVoice(
      title: ModuStrings.text(context, '对话音色', 'Dialogue voice'),
      current: _config.dialogueVoice,
      allowInherit: true,
      inheritLabel:
          ModuStrings.text(context, '跟随旁白', 'Follow the narration voice'),
    );
    if (picked == null) return;
    await _save(_config.copyWith(dialogueVoice: picked));
  }

  Future<void> _pickBookVoice({required bool dialogue}) async {
    final bookId = _bookId;
    if (bookId == null) return;
    final override = Prefs().ttsRoleBookOverride(bookId);
    final effective = override.resolve(_config);
    final picked = await _pickVoice(
      title: dialogue
          ? ModuStrings.text(context, '本书对话音色', 'Dialogue voice for this book')
          : ModuStrings.text(
              context, '本书旁白音色', 'Narration voice for this book'),
      current: dialogue ? effective.dialogueVoice : effective.narrationVoice,
      allowInherit: true,
      inheritLabel:
          ModuStrings.text(context, '跟随全局设置', 'Follow the global setting'),
    );
    if (picked == null) return;
    await _saveBook(TtsRoleBookOverride(
      enabled: true,
      narrationVoice:
          dialogue ? override.narrationVoice : (picked.isEmpty ? null : picked),
      dialogueVoice:
          dialogue ? (picked.isEmpty ? null : picked) : override.dialogueVoice,
    ));
  }

  AbstractSettingsTile _voiceTile({
    required Key key,
    required String title,
    required String value,
    required String emptyLabel,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return SettingsTile.navigation(
      key: key,
      title: Text(title),
      value: Text(
        value.isEmpty ? emptyLabel : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      enabled: enabled,
      onPressed: enabled ? (_) => onTap() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The parent settings page may rebuild without this section being replaced
    // (the tile is not a const child any more), and the narration service can
    // also change elsewhere. Listening to Prefs keeps the enabled state of the
    // switch in sync with the selected engine.
    return ListenableBuilder(
      listenable: Prefs(),
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final config = _config;
    final enabled = config.enabled && !_systemEngine;
    final dialogueValue = config.dialogueVoice.isEmpty
        ? ModuStrings.text(context, '跟随旁白', 'Follow narration')
        : _voiceName(config.dialogueVoice);

    // A settings page already provides the scrolling ListView; a nested
    // ListView here would get unbounded height and fail to lay out.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsSection(
            title: Text(
                ModuStrings.text(context, '多角色朗读', 'Multi-speaker narration')),
            tiles: [
              SettingsTile.switchTile(
                key: const ValueKey('tts-role-enabled'),
                leading: const Icon(Icons.record_voice_over_outlined),
                title: Text(ModuStrings.text(
                    context, '旁白与对话分音色', 'Separate narration and dialogue')),
                description: Text(_systemEngine
                    ? ModuStrings.text(context, '请先选择在线朗读服务。',
                        'Choose an online speech service first.')
                    : ModuStrings.text(context, "引号内使用对话音色，其余使用旁白音色。",
                        "Use the dialogue voice inside quotation marks and the narrator voice elsewhere.")),
                initialValue: enabled,
                enabled: !_systemEngine,
                onToggle: (value) async {
                  await _save(config.copyWith(enabled: value));
                },
              ),
              if (enabled)
                _voiceTile(
                  key: const ValueKey('tts-role-narration'),
                  title: ModuStrings.text(context, '旁白音色', 'Narration voice'),
                  value: _voiceName(config.narrationVoice),
                  emptyLabel:
                      ModuStrings.text(context, '跟随当前音色', 'Current voice'),
                  onTap: _pickNarration,
                ),
              if (enabled)
                _voiceTile(
                  key: const ValueKey('tts-role-dialogue'),
                  title: ModuStrings.text(context, '对话音色', 'Dialogue voice'),
                  value: config.dialogueVoice.isEmpty ? '' : dialogueValue,
                  emptyLabel:
                      ModuStrings.text(context, '跟随旁白', 'Follow narration'),
                  onTap: _pickDialogue,
                ),
              if (enabled)
                SettingsTile.navigation(
                  key: const ValueKey('tts-role-narration-rate'),
                  leading: const Icon(Icons.speed),
                  title: Text(
                      ModuStrings.text(context, '旁白语速', 'Narration speed')),
                  value: Text('×${config.narrationRate.toStringAsFixed(2)}'),
                  description: Text(ModuStrings.text(
                      context,
                      "调整旁白和对话的倍率，使听感速度一致。",
                      "Adjust narrator and dialogue rates to match their pace.")),
                  onPressed: (_) => _pickRate(
                    title: ModuStrings.text(context, '旁白语速', 'Narration speed'),
                    current: config.narrationRate,
                    apply: (rate) => config.copyWith(narrationRate: rate),
                  ),
                ),
              if (enabled)
                SettingsTile.navigation(
                  key: const ValueKey('tts-role-dialogue-rate'),
                  leading: const Icon(Icons.speed),
                  title:
                      Text(ModuStrings.text(context, '对话语速', 'Dialogue speed')),
                  value: Text('×${config.dialogueRate.toStringAsFixed(2)}'),
                  description: Text(ModuStrings.text(context, "调整对话音色的朗读速度。",
                      "Adjust the dialogue voice’s rate.")),
                  onPressed: (_) => _pickRate(
                    title: ModuStrings.text(context, '对话语速', 'Dialogue speed'),
                    current: config.dialogueRate,
                    apply: (rate) => config.copyWith(dialogueRate: rate),
                  ),
                ),
            ],
          ),
          if (enabled && _bookId != null) _buildBookSection(),
        ]);
  }

  AbstractSettingsSection _buildBookSection() {
    final bookId = _bookId!;
    final override = Prefs().ttsRoleBookOverride(bookId);
    final effective = override.resolve(_config);
    final custom = !override.isEmpty;
    return SettingsSection(
      title: Text(ModuStrings.text(context, '本书音色', 'Voices for this book')),
      tiles: [
        SettingsTile.switchTile(
          key: const ValueKey('tts-role-book-enabled'),
          leading: const Icon(Icons.auto_stories_outlined),
          title: Text(ModuStrings.text(
              context, '这本书使用独立音色', 'Use custom voices for this book')),
          description: Text(ModuStrings.text(
              context, "为当前书籍单独设置音色。", "Set voices for this book.")),
          initialValue: custom,
          onToggle: (value) async {
            if (!value) {
              await _saveBook(const TtsRoleBookOverride());
              return;
            }
            await _saveBook(TtsRoleBookOverride(
              enabled: true,
              narrationVoice: effective.narrationVoice,
              dialogueVoice: effective.dialogueVoice,
            ));
          },
        ),
        if (custom)
          _voiceTile(
            key: const ValueKey('tts-role-book-narration'),
            title: ModuStrings.text(context, '本书旁白', 'Narration here'),
            value: _voiceName(effective.narrationVoice),
            emptyLabel: ModuStrings.text(context, '跟随全局', 'Global'),
            onTap: () => _pickBookVoice(dialogue: false),
          ),
        if (custom)
          _voiceTile(
            key: const ValueKey('tts-role-book-dialogue'),
            title: ModuStrings.text(context, '本书对话', 'Dialogue here'),
            value: effective.dialogueVoice.isEmpty
                ? ''
                : _voiceName(effective.dialogueVoice),
            emptyLabel: ModuStrings.text(context, '跟随旁白', 'Follow narration'),
            onTap: () => _pickBookVoice(dialogue: true),
          ),
      ],
    );
  }
}
