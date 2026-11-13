import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

/// Settings and conversation share only this screen's device-local preference.
class SkillTemplateDraftTile extends StatefulWidget {
  const SkillTemplateDraftTile(
      {super.key,
      this.compact = false,
      this.screen = 'reader',
      this.legacyDefault,
      this.title});

  final bool compact;
  final String screen;
  final bool? legacyDefault;
  final String? title;

  @override
  State<SkillTemplateDraftTile> createState() => _SkillTemplateDraftTileState();
}

class _SkillTemplateDraftTileState extends State<SkillTemplateDraftTile> {
  @override
  void initState() {
    super.initState();
    Prefs().addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Prefs().removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final localHelp = ModuStrings.text(context, '仅记忆当前 AI 界面，不影响其他界面，不参与同步。',
        'Saved for this AI screen only, on this device. Not synced.');
    final help =
        '${ModuStrings.value(locale, 'ai_skill_template_draft_help', 'Off: send templates immediately. On: fill the input so you can edit before sending. Saved templates stay unchanged.')}\n$localHelp';
    return Tooltip(
      message: help,
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: const ValueKey('ai-skill-template-draft-switch'),
          title: Text(
              widget.title ??
                  ModuStrings.value(locale, 'ai_skill_template_draft',
                      'Edit skill templates before sending'),
              style: widget.compact
                  ? Theme.of(context).textTheme.bodySmall
                  : null),
          subtitle: widget.compact ? null : Text(localHelp),
          contentPadding:
              widget.compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
          dense: widget.compact,
          visualDensity: widget.compact
              ? const VisualDensity(horizontal: -2, vertical: -3)
              : null,
          value: Prefs()
              .aiDraftFor(widget.screen, legacyDefault: widget.legacyDefault),
          onChanged: (value) => Prefs().setAiDraftFor(widget.screen, value),
        ),
      ),
    );
  }
}
