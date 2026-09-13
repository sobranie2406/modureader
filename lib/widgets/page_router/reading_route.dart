import 'package:flutter/cupertino.dart';

/// Keep normal navigation semantics, but disable both route and Hero animation
/// when the user switches off bookshelf-to-reader transitions.
Route<T> readingRoute<T>(
    {required WidgetBuilder builder, required bool animate}) {
  if (animate) return CupertinoPageRoute<T>(builder: builder);
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) =>
        HeroMode(enabled: false, child: builder(context)),
  );
}
