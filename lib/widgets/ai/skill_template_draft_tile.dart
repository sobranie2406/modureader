import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

/// Both settings and the live conversation observe the same preference.
class SkillTemplateDraftTile extends StatefulWidget {
  const SkillTemplateDraftTile({super.key, this.compact = false});

  final bool compact;

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
    final help = ModuStrings.value(locale, 'ai_skill_template_draft_help',
        'Off: send templates immediately. On: fill the input so you can edit before sending. Saved templates stay unchanged.');
    return Tooltip(
      message: help,
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: const ValueKey('ai-skill-template-draft-switch'),
          title: Text(
              ModuStrings.value(locale, 'ai_skill_template_draft',
                  'Edit skill templates before sending'),
              style: widget.compact
                  ? Theme.of(context).textTheme.bodySmall
                  : null),
          subtitle: widget.compact ? null : Text(help),
          contentPadding:
              widget.compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
          dense: widget.compact,
          visualDensity: widget.compact
              ? const VisualDensity(horizontal: -2, vertical: -3)
              : null,
          value: Prefs().aiSkillTemplateDraft,
          onChanged: (value) => Prefs().aiSkillTemplateDraft = value,
        ),
      ),
    );
  }
}
