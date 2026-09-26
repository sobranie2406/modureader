import 'package:anx_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:flutter/material.dart';

class CssSettings extends StatelessWidget {
  const CssSettings({super.key});
  @override
  Widget build(BuildContext context) => const Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: CustomCSSEditor(manage: true),
        ),
      );
}
