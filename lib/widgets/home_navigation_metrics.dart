import 'package:flutter/widgets.dart';

/// Shared geometry for the floating home bar and its reserved content area.
abstract final class HomeNavigationMetrics {
  static const barHeight = 64.0;
  static const barOffset = 10.0;
  static const contentGap = 12.0;

  static double barHeightFor(BuildContext context) =>
      barHeight +
      (MediaQuery.textScalerOf(context).scale(14) - 14)
          .clamp(0, double.infinity);

  static double bottomContentInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom +
      barHeightFor(context) +
      barOffset +
      contentGap;
}

/// Scrollable pages paint behind the floating bar and consume the clearance at
/// the end of their scroll content. Fixed layouts reserve it outside the page.
/// Keep clearance while auto-hiding so revealing the bar never moves content.
class HomeNavigationBody extends StatelessWidget {
  const HomeNavigationBody({
    super.key,
    required this.child,
    required this.hasBottomBar,
    this.scrollBehindBar = false,
  });

  final Widget child;
  final bool hasBottomBar;
  final bool scrollBehindBar;

  @override
  Widget build(BuildContext context) {
    final inset =
        hasBottomBar ? HomeNavigationMetrics.bottomContentInset(context) : 0.0;
    return HomeNavigationClearance(
      inset: scrollBehindBar ? inset : 0,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: scrollBehindBar ? 0 : inset,
        ),
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: hasBottomBar,
          child: child,
        ),
      ),
    );
  }
}

/// Additional trailing space for scroll views under the home navigation bar.
/// An inherited value keeps standalone pages and modal routes unaffected.
class HomeNavigationClearance extends InheritedWidget {
  const HomeNavigationClearance({
    super.key,
    required this.inset,
    required super.child,
  });

  final double inset;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<HomeNavigationClearance>()
          ?.inset ??
      0;

  @override
  bool updateShouldNotify(HomeNavigationClearance oldWidget) =>
      inset != oldWidget.inset;
}
