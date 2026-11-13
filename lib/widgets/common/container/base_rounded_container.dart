import 'package:flutter/material.dart';
import 'package:modu_reader/utils/app_motion.dart';

abstract class BaseRoundedContainer extends StatelessWidget {
  const BaseRoundedContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.radius,
    this.constraints,
    this.animationDuration = const Duration(milliseconds: 250),
    this.animationCurve = Curves.easeInOut,
  });

  static const double _defaultRadius = 30;

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final BoxConstraints? constraints;
  final Duration animationDuration;
  final Curve animationCurve;

  BorderRadiusGeometry get _borderRadius =>
      BorderRadiusGeometry.circular(radius ?? _defaultRadius);

  @override
  Widget build(BuildContext context) {
    final BorderRadiusGeometry borderRadius = _borderRadius;
    final cardTheme = Theme.of(context).cardTheme;
    final baseDecoration = decoration(context, borderRadius);
    final hasShadow = (cardTheme.elevation ?? 0) > 0;

    return AnimatedContainer(
      duration: AppMotion.duration(animationDuration),
      curve: animationCurve,
      margin: margin?.add(const EdgeInsets.all(1)) ?? const EdgeInsets.all(1),
      width: width,
      height: height,
      constraints: constraints,
      decoration: ShapeDecoration(
        // Cover the shadow inside the shape with the same page colour.
        color: hasShadow
            ? Color.alphaBlend(baseDecoration.color ?? Colors.transparent,
                Theme.of(context).colorScheme.surface)
            : baseDecoration.color,
        image: baseDecoration.image,
        gradient: baseDecoration.gradient,
        shape: baseDecoration.shape,
        shadows: hasShadow
            ? [
                BoxShadow(
                  color: cardTheme.shadowColor ?? Colors.transparent,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                  // Outer blur cuts a displaced hole, leaving a second rim.
                  blurStyle: BlurStyle.normal,
                ),
              ]
            : const [],
      ),
      child: ClipRSuperellipse(
        borderRadius: borderRadius,
        child: Material(
          type: MaterialType.transparency,
          textStyle: DefaultTextStyle.of(context).style,
          child: Container(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  ShapeDecoration decoration(
    BuildContext context,
    BorderRadiusGeometry borderRadius,
  );

  @protected
  ShapeDecoration buildShapeDecoration({
    Color? color,
    required BorderSide borderSide,
    required BorderRadiusGeometry borderRadius,
  }) {
    return ShapeDecoration(
      color: color,
      shape: RoundedSuperellipseBorder(
        borderRadius: borderRadius,
        side: borderSide,
      ),
    );
  }
}
