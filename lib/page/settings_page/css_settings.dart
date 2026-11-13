import 'package:modu_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

class CssSettings extends StatelessWidget {
  const CssSettings({super.key});
  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          child: SettingsSection.content(
            title: Text(ModuStrings.text(context, '样式方案', 'Style profiles')),
            child: const CustomCSSEditor(manage: true),
          ),
        ),
      );
}
