import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:flutter/material.dart';

class TranslationWidget extends StatefulWidget {
  const TranslationWidget({
    super.key,
    required this.bookId,
    required this.epubPlayerKey,
  });

  final int bookId;
  final GlobalKey<EpubPlayerState> epubPlayerKey;

  @override
  State<TranslationWidget> createState() => _TranslationWidgetState();
}

class _TranslationWidgetState extends State<TranslationWidget> {
  late TranslationModeEnum _displayMode;
  late TranslationModeEnum _activeMode;
  late TranslateService _activeService;
  late LangListEnum _activeTarget;
  bool _translating = false;
  String? _error;

  bool get _isChinese => Localizations.localeOf(context).languageCode == 'zh';

  String _label(String zh, String en) => _isChinese ? zh : en;

  @override
  void initState() {
    super.initState();
    final savedMode = Prefs().getBookTranslationMode(widget.bookId);
    _activeMode = savedMode;
    _displayMode = savedMode == TranslationModeEnum.translationOnly
        ? TranslationModeEnum.translationOnly
        : TranslationModeEnum.bilingual;
    _activeService = Prefs().fullTextTranslateService;
    _activeTarget = Prefs().fullTextTranslateTo;
  }

  Future<void> _showServicePicker() async {
    final selected = await showModalBottomSheet<TranslateService>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _label('翻译引擎', 'Translation engine'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            for (final service in TranslateService.readAnyValues)
              RadioListTile<TranslateService>(
                value: service,
                groupValue: Prefs().fullTextTranslateService,
                title: Text(service.getLabel(context)),
                onChanged: (value) => Navigator.pop(context, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) return;
    Prefs().translateService = selected;
    Prefs().fullTextTranslateService = selected;
    setState(() => _error = null);
  }

  Future<void> _showLanguagePicker() async {
    final languages = LangListEnum.values
        .where((language) => language != LangListEnum.auto)
        .toList(growable: false);
    final selected = await showModalBottomSheet<LangListEnum>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _label('目标语言', 'Target language'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: languages.length,
                  itemBuilder: (context, index) {
                    final language = languages[index];
                    return RadioListTile<LangListEnum>(
                      value: language,
                      groupValue: Prefs().fullTextTranslateTo,
                      title: Text(language.nativeName),
                      onChanged: (value) => Navigator.pop(context, value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    Prefs().translateFrom = LangListEnum.auto;
    Prefs().fullTextTranslateFrom = LangListEnum.auto;
    Prefs().translateTo = selected;
    Prefs().fullTextTranslateTo = selected;
    setState(() => _error = null);
  }

  Future<void> _translate() async {
    if (_translating) return;
    final player = widget.epubPlayerKey.currentState;
    if (player == null) return;

    final service = Prefs().fullTextTranslateService;
    final target = Prefs().fullTextTranslateTo;
    final needsFreshTranslation = _activeMode != TranslationModeEnum.off &&
        (service != _activeService || target != _activeTarget);

    setState(() {
      _translating = true;
      _error = null;
    });
    try {
      await player.translateCurrentChapter(
        _displayMode,
        force: needsFreshTranslation,
      );
      Prefs().setBookTranslationMode(widget.bookId, _displayMode);
      if (!mounted) return;
      setState(() {
        _activeMode = _displayMode;
        _activeService = service;
        _activeTarget = target;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      AnxToast.show(_label('翻译失败：$error', 'Translation failed: $error'));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _stopTranslation() async {
    final player = widget.epubPlayerKey.currentState;
    if (player == null) return;
    try {
      await player.setTranslationMode(TranslationModeEnum.off);
      Prefs().setBookTranslationMode(widget.bookId, TranslationModeEnum.off);
      if (mounted) {
        setState(() {
          _activeMode = TranslationModeEnum.off;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = Prefs().fullTextTranslateService;
    final target = Prefs().fullTextTranslateTo;
    final settingsChanged =
        service != _activeService || target != _activeTarget;
    final modeChanged = _displayMode != _activeMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.translate_outlined),
              const SizedBox(width: 8),
              Text(
                _label('阅读翻译', 'Reader translation'),
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              if (_activeMode != TranslationModeEnum.off)
                TextButton.icon(
                  onPressed: _translating ? null : _stopTranslation,
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: Text(_label('隐藏翻译', 'Hide translation')),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ChoiceButton(
                  label: _label('翻译引擎', 'Engine'),
                  value: service.getLabel(context),
                  icon: Icons.translate_outlined,
                  onTap: _translating ? null : _showServicePicker,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChoiceButton(
                  label: _label('目标语言', 'Target language'),
                  value: target.nativeName,
                  icon: Icons.language_outlined,
                  onTap: _translating ? null : _showLanguagePicker,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _label('显示方式', 'Display'),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: AnxSegmentedButton<TranslationModeEnum>(
              enabled: !_translating,
              segments: [
                SegmentButtonItem(
                  label: _label('仅译文', 'Translation only'),
                  value: TranslationModeEnum.translationOnly,
                  icon: const Icon(Icons.g_translate),
                ),
                SegmentButtonItem(
                  label: _label('原文 + 译文', 'Original + translation'),
                  value: TranslationModeEnum.bilingual,
                  icon: const Icon(Icons.compare_outlined),
                ),
              ],
              selected: {_displayMode},
              onSelectionChanged: (value) {
                setState(() {
                  _displayMode = value.first;
                  _error = null;
                });
              },
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _translating ? null : _translate,
              icon: _translating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate),
              label: Text(
                _translating
                    ? _label('翻译中…', 'Translating…')
                    : _activeMode == TranslationModeEnum.off
                        ? _label('开始翻译', 'Start translation')
                        : settingsChanged
                            ? _label(
                                '按新设置重新翻译', 'Retranslate with new settings')
                            : modeChanged
                                ? _label('应用显示方式', 'Apply display mode')
                                : _label(
                                    '重新翻译当前内容', 'Retranslate current content'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _label(
              '按下开始翻译后，正文会发送到所选服务；翻译按当前阅读内容逐步加载。',
              'After you start, text is sent to the selected service and translation loads progressively.',
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: AlignmentDirectional.centerStart,
      ),
      child: Row(
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}
