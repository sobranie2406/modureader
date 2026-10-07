import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';

/// Visual motion only. Never use this for debounce, network, or task timeouts.
abstract final class AppMotion {
  // Set before building the app; unlike Prefs, safe during binding startup.
  static bool platformDisabled = false;
  static bool get disabled => Prefs().isInitialized && Prefs().eInkMode;
  static Duration duration(Duration normal) =>
      disabled ? Duration.zero : normal;
  static AnimationStyle? get style =>
      disabled ? AnimationStyle.noAnimation : null;
}

/// Framework controls (checkboxes, switches, selection cursors) consult the
/// binding rather than MediaQuery. Keep both reduced-motion signals in sync.
class ModuWidgetsBinding extends WidgetsFlutterBinding {
  @override
  bool get disableAnimations =>
      AppMotion.platformDisabled || super.disableAnimations;
}

class EinkScrollPhysics extends ClampingScrollPhysics {
  const EinkScrollPhysics({super.parent});
  @override
  EinkScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      EinkScrollPhysics(parent: buildParent(ancestor));
  @override
  Simulation? createBallisticSimulation(
          ScrollMetrics position, double velocity) =>
      null;
}

/// Do not mute the whole app's tickers: that can leave routes, switches and
/// awaited operations stuck halfway through a transition.
class EinkMotionScope extends StatelessWidget {
  const EinkMotionScope(
      {super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: enabled || media.disableAnimations,
        accessibleNavigation: enabled || media.accessibleNavigation,
      ),
      child: HeroMode(enabled: !enabled, child: child),
    );
  }
}

class MotionHeroine extends StatelessWidget {
  const MotionHeroine(
      {super.key,
      required this.child,
      required this.tag,
      this.flightShuttleBuilder,
      this.motion = const CupertinoMotion.smooth()});
  final Widget child;
  final Object tag;
  final HeroineShuttleBuilder? flightShuttleBuilder;
  final Motion motion;
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : Heroine(
          tag: tag,
          motion: motion,
          flightShuttleBuilder: flightShuttleBuilder,
          child: child);
}

/// Only decorative indefinite indicators may be frozen. Their labels and
/// determinate values still rebuild as the underlying operation progresses.
class EinkStaticIndicator extends StatelessWidget {
  const EinkStaticIndicator({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TickerMode(
      enabled: !MediaQuery.disableAnimationsOf(context), child: child);
}

class NoMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoMotionPageTransitionsBuilder();
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;
  @override
  Widget buildTransitions<T>(
          PageRoute<T> route,
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child) =>
      child;
}

class MotionCupertinoPageRoute<T> extends CupertinoPageRoute<T> {
  MotionCupertinoPageRoute(
      {required super.builder,
      super.settings,
      super.title,
      super.fullscreenDialog,
      super.maintainState});
  @override
  Duration get transitionDuration =>
      AppMotion.duration(super.transitionDuration);
  @override
  Duration get reverseTransitionDuration =>
      AppMotion.duration(super.reverseTransitionDuration);
  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      AppMotion.disabled
          ? child
          : super
              .buildTransitions(context, animation, secondaryAnimation, child);
}
