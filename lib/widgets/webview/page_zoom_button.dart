import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

class PageZoomButton extends StatelessWidget {
  const PageZoomButton(
      {super.key, required this.percent, required this.onChanged});
  final int percent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
        popUpAnimationStyle: AppMotion.style,
        tooltip: ModuStrings.text(context, '网页缩放', 'Page zoom'),
        initialValue: percent,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (var value = 50; value <= 200; value += 10)
            CheckedPopupMenuItem<int>(
              value: value,
              checked: value == percent,
              child: Text(value == 100
                  ? ModuStrings.text(context, '100%（恢复默认）', '100% (Reset)')
                  : '$value%'),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.zoom_in, size: 20),
            const SizedBox(width: 4),
            Text('$percent%'),
          ]),
        ),
      );
}
