import 'package:flutter/material.dart';

/// Equal slider intervals represent fine low-speed steps, then 3x and 4x.
/// Positions are indices, not multipliers, so the high-speed range stays small.
class TtsRateSlider extends StatelessWidget {
  const TtsRateSlider({
    super.key,
    required this.rate,
    required this.onChanged,
    required this.onChangeEnd,
    this.isMimo = false,
    this.isOnline = true,
  });

  final double rate;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final bool isMimo;
  final bool isOnline;

  List<double> get steps => [
        if (isMimo)
          for (var i = 5; i <= 20; i++) i / 10
        else
          for (var i = 0; i <= 10; i++) i / 5,
        if (isOnline) ...[3.0, 4.0],
      ];

  double _position(double value, List<double> steps) {
    if (!value.isFinite) value = 1;
    if (value <= steps.first) return 0;
    for (var i = 1; i < steps.length; i++) {
      if (value <= steps[i]) {
        return i - 1 + (value - steps[i - 1]) / (steps[i] - steps[i - 1]);
      }
    }
    return (steps.length - 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final values = steps;
    final display =
        (rate.isFinite ? rate : 1.0).clamp(values.first, values.last);
    double selected(double position) => values[position.round()];
    return Slider(
      key: const ValueKey('tts-rate-slider'),
      value: _position(display, values),
      min: 0,
      max: (values.length - 1).toDouble(),
      divisions: values.length - 1,
      label: '${display.toStringAsFixed(1)}${isOnline ? '×' : ''}',
      onChanged: (position) => onChanged(selected(position)),
      // Preview while dragging; only commit once to avoid repeated synthesis.
      onChangeEnd: (position) => onChangeEnd(selected(position)),
    );
  }
}
