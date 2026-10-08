import 'package:anx_reader/utils/app_motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// Keep normal navigation semantics, but disable both route and Hero animation
/// when the user switches off bookshelf-to-reader transitions.
Route<T> readingRoute<T>(
    {required WidgetBuilder builder, required bool animate}) {
  if (animate && !AppMotion.disabled) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 720),
        reverseTransitionDuration: const Duration(milliseconds: 620),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        // The reader mounts immediately at its final size. Only reveal it
        // behind the almost-expanded cover; do not slide/scale the WebView.
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
          opacity: animation.drive(CurveTween(
              curve: const Interval(0.35, 0.55, curve: Curves.easeInOut))),
          child: child,
        ),
      );
    }
    return MotionCupertinoPageRoute<T>(builder: builder);
  }
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) =>
        HeroMode(enabled: false, child: builder(context)),
  );
}
