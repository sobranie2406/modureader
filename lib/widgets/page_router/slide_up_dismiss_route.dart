import 'package:flutter/material.dart';
import 'package:anx_reader/utils/app_motion.dart';

class SlideUpDismissRoute<T> extends PageRouteBuilder<T> {
  final Widget child;

  SlideUpDismissRoute({required this.child})
      : super(
          opaque: false,
          transitionDuration:
              AppMotion.duration(const Duration(milliseconds: 300)),
          reverseTransitionDuration:
              AppMotion.duration(const Duration(milliseconds: 300)),
          pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) =>
              child,
        );
}
