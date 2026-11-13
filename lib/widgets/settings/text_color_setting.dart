import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/text_color.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/widgets/common/color_picker_sheet.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';

class TextColorSetting extends StatelessWidget {
  const TextColorSetting(
      {super.key,
      required this.value,
      required this.onChanged,
      required this.defaultLabel});
  final String value, defaultLabel;
  final ValueChanged<String> onChanged;

  Color color(String hex) =>
      Color(int.parse('FF${hex.substring(1)}', radix: 16));

  Future<void> pick(BuildContext context) async {
    var selected = value.isEmpty ? textColorPresets.first : value.toUpperCase();
    final result = await showDialog<String>(
      context: context,
      animationStyle: AppMotion.style,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: Text(ModuStrings.text(context, '字体颜色', 'Font colour')),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final hex in textColorPresets)
                      IconButton(
                        key: ValueKey('text-color-preset-$hex'),
                        tooltip: hex,
                        isSelected: selected == hex,
                        onPressed: () => setState(() => selected = hex),
                        icon: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                                color: color(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.outline)),
                            child: selected == hex
                                ? Icon(Icons.check,
                                    size: 18,
                                    color: color(hex).computeLuminance() > .5
                                        ? Colors.black
                                        : Colors.white)
                                : null),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  ColorPicker(
                    pickerColor: color(selected),
                    portraitOnly: true,
                    colorPickerWidth: (MediaQuery.sizeOf(context).width - 128)
                        .clamp(160, 300),
                    enableAlpha: false,
                    hexInputBar: true,
                    displayThumbColor: true,
                    pickerAreaHeightPercent: .8,
                    onColorChanged: (color) => setState(() => selected =
                        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'),
                  ),
                ])),
                actions: [
                  TextButton.icon(
                    key: const ValueKey('reset-font-color'),
                    icon: const Icon(Icons.restore),
                    label: Text(
                        ModuStrings.text(context, '恢复默认', 'Restore default')),
                    onPressed: () async {
                      if (await confirmColorReset(
                              context,
                              ModuStrings.text(context, "恢复默认字体颜色？",
                                  "Reset the text color?")) &&
                          context.mounted) {
                        Navigator.pop(context, '');
                      }
                    },
                  ),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                  TextButton(
                      key: const ValueKey('save-font-color'),
                      onPressed: () => Navigator.pop(context, selected),
                      child: Text(ModuStrings.text(context, '确定', 'OK'))),
                ],
              )),
    );
    if (result != null && context.mounted) onChanged(result);
  }

  @override
  Widget build(BuildContext context) => SettingsTile.navigation(
        leading: Icon(Icons.format_color_text,
            color: value.isEmpty ? null : color(value)),
        title: Text(ModuStrings.text(context, '字体颜色', 'Font colour')),
        value: Text(value.isEmpty ? defaultLabel : value.toUpperCase()),
        onPressed: pick,
      );
}
