import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MacOSWebViewHitRegion extends StatelessWidget {
  const MacOSWebViewHitRegion({super.key});

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) => supported
      // AppKit defers to Flutter in painted regions. Keep the paint operation
      // while its alpha rounds to zero in the macOS backing store.
      ? const ColoredBox(
          color: Color.from(alpha: 0.0001, red: 0, green: 0, blue: 0),
          child: SizedBox.expand(),
        )
      : const SizedBox.expand();
}

/// Let the top Flutter route handle clicks when it covers this native view.
class WebViewRouteGuard extends StatelessWidget {
  const WebViewRouteGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!MacOSWebViewHitRegion.supported) return child;
    return Stack(
      children: [
        child,
        if (ModalRoute.isCurrentOf(context) == false)
          const Positioned.fill(
              child: IgnorePointer(child: MacOSWebViewHitRegion())),
      ],
    );
  }
}
