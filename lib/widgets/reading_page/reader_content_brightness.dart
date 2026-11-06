import 'package:anx_reader/service/app_brightness.dart';
import 'package:flutter/material.dart';

/// An opt-in surface for reading content; never inherited by menus or routes.
class ReaderContentBrightness extends StatelessWidget {
  const ReaderContentBrightness({
    super.key,
    required this.child,
    required this.backgroundColor,
    this.controller,
  });

  final Widget child;
  final Color backgroundColor;
  final AppBrightness? controller;

  @override
  Widget build(BuildContext context) {
    final brightness = controller ?? AppBrightness.instance;
    return ListenableBuilder(
      listenable: brightness,
      child: Material(
          color: backgroundColor,
          surfaceTintColor: Colors.transparent,
          child: child),
      builder: (_, content) {
        final dim = brightness.dimOpacity;
        final alpha = backgroundColor.a;
        // Preserve the configured surface alpha while darkening its color.
        final blackAlpha =
            dim == 0 ? 0.0 : alpha * dim / (1 - alpha * (1 - dim));
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
                child: ColoredBox(
                    color: Colors.black.withValues(alpha: blackAlpha))),
            // Native WebViews support opacity. A painted overlay above them
            // would intercept their macOS hit regions, even with IgnorePointer.
            Opacity(opacity: 1 - dim, child: content),
          ],
        );
      },
    );
  }
}
