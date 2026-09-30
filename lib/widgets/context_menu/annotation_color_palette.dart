import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/constants/note_annotations.dart';
import 'package:flutter/material.dart';

/// Two rows (two columns in vertical reading) keep every colour accessible
/// without stretching the selection toolbar beyond a phone's viewport.
class AnnotationColorPalette extends StatelessWidget {
  const AnnotationColorPalette({
    super.key,
    required this.axis,
    required this.selectedColor,
    required this.onSelected,
    this.colors = notesColors,
  });

  final Axis axis;
  final String selectedColor;
  final ValueChanged<String> onSelected;
  final List<String> colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: axis == Axis.horizontal ? 160 : null,
      height: axis == Axis.vertical ? 160 : null,
      child: Wrap(
        direction: axis,
        children: [
          for (final color in colors)
            Semantics(
              selected: selectedColor.toUpperCase() == color,
              child: IconButton(
                key: ValueKey('annotation-color-$color'),
                tooltip:
                    '${ModuStrings.text(context, '批注颜色', 'Annotation colour')} #$color',
                padding: const EdgeInsets.all(4),
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(int.parse('88$color', radix: 16)),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 0.75,
                        ),
                      ),
                    ),
                    if (selectedColor.toUpperCase() == color)
                      Icon(Icons.check,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurface),
                  ],
                ),
                onPressed: () => onSelected(color),
              ),
            ),
        ],
      ),
    );
  }
}
