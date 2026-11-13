import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

Future<bool> confirmColorReset(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.style,
      builder: (context) => AlertDialog(
        title: Text(ModuStrings.text(context, '恢复默认', 'Restore default')),
        content: Text(message),
        actions: [
          TextButton(
              key: const ValueKey('cancel-color-reset'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
          TextButton(
              key: const ValueKey('confirm-color-reset'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(ModuStrings.text(context, '确认恢复', 'Restore'))),
        ],
      ),
    ) ??
    false;

/// Reusable RGB color picker dialog.
/// Returns selected color as RGB int (0xRRGGBB), alpha is always 0xFF when displaying.
Future<Color?> showRgbColorPicker({
  required BuildContext context,
  required Color initialColor,
  bool allowAlpha = true,
}) async {
  Color pickedColor = initialColor;

  final result = await showDialog<Color>(
    animationStyle: AppMotion.style,
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        content: SingleChildScrollView(
          child: ColorPicker(
            hexInputBar: true,
            enableAlpha: allowAlpha,
            pickerColor: pickedColor,
            onColorChanged: (Color color) {
              pickedColor = allowAlpha ? color : color.withAlpha(0xFF);
            },
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(L10n.of(context).commonCancel),
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
          ),
          TextButton(
            child: Text(L10n.of(context).commonOk),
            onPressed: () {
              Navigator.of(dialogContext).pop(pickedColor);
            },
          ),
        ],
      );
    },
  );

  return result;
}
