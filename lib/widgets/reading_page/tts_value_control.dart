import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

class TtsValueControl extends StatefulWidget {
  const TtsValueControl(
      {super.key,
      required this.value,
      required this.onChanged,
      this.pitch = false});

  final double value;
  final bool pitch;
  final ValueChanged<double> onChanged;

  static TextStyle? _valueStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 16,
          height: 1.2,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()]);

  static double _inputWidth(BuildContext context) {
    final painter = TextPainter(
        text: TextSpan(text: '0.0×', style: _valueStyle(context)),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context))
      ..layout();
    // Include field padding and caret space; fixed widths clip some fonts.
    final width = painter.width.ceilToDouble() + 12;
    painter.dispose();
    return width;
  }

  static double width(BuildContext context) => 98 + _inputWidth(context);

  @override
  State<TtsValueControl> createState() => _TtsValueControlState();
}

class _TtsValueControlState extends State<TtsValueControl> {
  double get _min => widget.pitch ? 0.5 : 0.1;
  double get _max => widget.pitch ? 2.0 : 4.0;
  String get _prefix => widget.pitch ? 'pitch' : 'rate';
  double _bounded(double value) =>
      (value.isFinite ? value : 1.0).clamp(_min, _max);
  late final _controller =
      TextEditingController(text: _bounded(widget.value).toStringAsFixed(1));
  final _focus = FocusNode();
  late double _lastCommitted = _bounded(widget.value);
  bool _invalid = false;

  double? get _input {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value >= _min && value <= _max
        ? value
        : null;
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _commit();
  }

  @override
  void didUpdateWidget(TtsValueControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _lastCommitted = _bounded(widget.value);
      if (!_focus.hasFocus) {
        _controller.text = _lastCommitted.toStringAsFixed(1);
        _invalid = false;
      }
    }
  }

  void _apply(double value) {
    final next = (_bounded(value) * 10).round() / 10;
    _controller.text = next.toStringAsFixed(1);
    setState(() => _invalid = false);
    if (next == _lastCommitted) return;
    _lastCommitted = next;
    widget.onChanged(next);
  }

  void _commit() {
    final value = _input;
    if (value == null) {
      setState(() => _invalid = true);
    } else {
      _apply(value);
    }
  }

  void _step(int direction) {
    final ticks = ((_input ?? _lastCommitted) * 10).round();
    _apply((ticks + direction).clamp((_min * 10).round(), (_max * 10).round()) /
        10);
    _focus.unfocus();
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = _input ?? _lastCommitted;
    final textStyle = TtsValueControl._valueStyle(context);
    return TextFieldTapRegion(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(
          key: ValueKey('tts-$_prefix-control'),
          alignment: Alignment.center,
          children: [
            Positioned(
                left: 0,
                right: 0,
                child: Container(
                  key: ValueKey('tts-$_prefix-border'),
                  height: (MediaQuery.textScalerOf(context).scale(16) * 1.2 + 8)
                      .clamp(28, double.infinity),
                  decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              _invalid ? colors.error : colors.outlineVariant)),
                )),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  key: ValueKey('tts-$_prefix-decrease'),
                  tooltip:
                      ModuStrings.text(context, '降低 0.1', 'Decrease by 0.1'),
                  onPressed: value <= _min ? null : () => _step(-1),
                  color: colors.primary,
                  icon: const Icon(Icons.remove_rounded, size: 20)),
              SizedBox(
                  height: 16,
                  child:
                      VerticalDivider(width: 1, color: colors.outlineVariant)),
              SizedBox(
                  width: TtsValueControl._inputWidth(context),
                  child: Semantics(
                      label: ModuStrings.format(context,
                          '{label}，{min} 至 {max}', '{label}, {min} to {max}',
                          values: {
                            'label': widget.pitch
                                ? L10n.of(context).ttsPitch
                                : L10n.of(context).ttsRate,
                            'min': '$_min',
                            'max': '$_max'
                          }),
                      child: TextField(
                        key: ValueKey('tts-$_prefix-input'),
                        controller: _controller,
                        focusNode: _focus,
                        textAlign: TextAlign.center,
                        style: textStyle,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                            hintText: '1.0',
                            suffixText: '×',
                            suffixStyle: textStyle?.copyWith(
                                color: colors.onSurfaceVariant),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4)),
                        onTap: () => _controller.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _controller.text.length),
                        onChanged: (_) => setState(() => _invalid = false),
                        onSubmitted: (_) {
                          _commit();
                          _focus.unfocus();
                        },
                        onTapOutside: (_) => _focus.unfocus(),
                      ))),
              SizedBox(
                  height: 16,
                  child:
                      VerticalDivider(width: 1, color: colors.outlineVariant)),
              IconButton(
                  key: ValueKey('tts-$_prefix-increase'),
                  tooltip:
                      ModuStrings.text(context, '提高 0.1', 'Increase by 0.1'),
                  onPressed: value >= _max ? null : () => _step(1),
                  color: colors.primary,
                  icon: const Icon(Icons.add_rounded, size: 20)),
            ]),
          ],
        ),
        if (_invalid)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  ModuStrings.format(context, '请输入 {min}～{max} 之间的数字',
                      'Enter a number from {min} to {max}',
                      values: {'min': '$_min', 'max': '$_max'}),
                  key: ValueKey('tts-$_prefix-error'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.error))),
      ]),
    );
  }
}

/// Equal-width pitch and speed controls, with labels above on narrow screens.
class TtsVoiceControls extends StatelessWidget {
  const TtsVoiceControls(
      {super.key,
      required this.pitch,
      required this.rate,
      required this.onPitchChanged,
      required this.onRateChanged});

  final double pitch;
  final double rate;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onRateChanged;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final inline = constraints.maxWidth >= 480 * scale;
        // Very large accessibility text can scroll without shrinking text or touch targets.
        final controlWidth = TtsValueControl.width(context);
        final width =
            constraints.maxWidth.clamp(2 * controlWidth, double.infinity);
        Widget half(bool isPitch) {
          final label = Text(
              isPitch ? L10n.of(context).ttsPitch : L10n.of(context).ttsRate);
          final control = SizedBox(
              width: controlWidth,
              child: TtsValueControl(
                  pitch: isPitch,
                  value: isPitch ? pitch : rate,
                  onChanged: isPitch ? onPitchChanged : onRateChanged));
          return Expanded(
              child: Center(
                  key: ValueKey(isPitch ? 'tts-pitch-half' : 'tts-rate-half'),
                  child: inline
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [label, const SizedBox(width: 8), control])
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [label, control])));
        }

        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: width,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [half(true), half(false)])));
      });
}
