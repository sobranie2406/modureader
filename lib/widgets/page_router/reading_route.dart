import 'package:anx_reader/utils/app_motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// Keep normal navigation semantics, but disable both route and Hero animation
/// when the user switches off bookshelf-to-reader transitions.
Route<T> readingRoute<T>(
    {required WidgetBuilder builder, required bool animate}) {
  if (animate && !AppMotion.disabled) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _IosReadingRoute<T>(builder: builder);
    }
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 720),
      reverseTransitionDuration: const Duration(milliseconds: 620),
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          _revealReader(animation, child),
    );
  }
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) =>
        HeroMode(enabled: false, child: builder(context)),
  );
}

// Mount the reader at its final size; only the cached cover moves, never WebView.
Widget _revealReader(Animation<double> animation, Widget child) =>
    FadeTransition(
      opacity: animation.drive(CurveTween(
          curve: const Interval(0.35, 0.55, curve: Curves.easeInOut))),
      child: child,
    );

class _IosReadingRoute<T> extends CupertinoPageRoute<T> {
  _IosReadingRoute({required super.builder}) : super(allowSnapshotting: false);

  @override
  Duration get transitionDuration => const Duration(milliseconds: 720);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 620);
  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => false;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // Retain Cupertino's edge-swipe controller, but freeze its slide transform.
    // The real route animation drives the cover for both completed/cancelled swipes.
    return super.buildTransitions(
        context,
        const AlwaysStoppedAnimation<double>(1),
        const AlwaysStoppedAnimation<double>(0),
        _revealReader(animation, child));
  }
}
