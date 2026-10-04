import 'package:flutter/material.dart';

/// Compact reader chrome: unlike a square icon font, the battery only occupies
/// one metadata line. Never inherit body text size or system icon scaling.
class ReadingBatteryIndicator extends StatelessWidget {
  const ReadingBatteryIndicator({
    super.key,
    required this.level,
    required this.color,
    this.fontSize = 10,
  });

  final int level;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final height = (fontSize.isFinite ? fontSize : 10.0).clamp(8.0, 16.0);
    final percent = level.clamp(0, 100);
    return Semantics(
      label: '$percent%',
      child: ExcludeSemantics(
        child: SizedBox(
          width: height * 2.2,
          height: height,
          child: CustomPaint(
            painter: _BatteryOutline(color),
            child: Padding(
              padding: EdgeInsets.fromLTRB(2, 1, height * .2 + 2, 1),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$percent',
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                        color: color,
                        fontSize: height * .8,
                        height: 1,
                        fontWeight: FontWeight.normal)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BatteryOutline extends CustomPainter {
  const _BatteryOutline(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final tip = size.height * .2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(.5, .5, size.width - tip - .5, size.height - .5),
            const Radius.circular(1.5)),
        paint);
    paint.style = PaintingStyle.fill;
    canvas.drawRect(
        Rect.fromLTRB(
            size.width - tip, size.height * .3, size.width, size.height * .7),
        paint);
  }

  @override
  bool shouldRepaint(_BatteryOutline oldDelegate) => oldDelegate.color != color;
}
