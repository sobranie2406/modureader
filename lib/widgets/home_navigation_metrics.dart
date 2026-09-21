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

/// Reserve space outside every compact home page, including fixed controls and
/// empty states, not just the last item of individual scroll views. Keep this
/// space while the bar auto-hides so revealing it never covers content or makes
/// the viewport jump. The containing Scaffold already handles keyboard insets.
class HomeNavigationBody extends StatelessWidget {
  const HomeNavigationBody({
    super.key,
    required this.child,
    required this.hasBottomBar,
  });

  final Widget child;
  final bool hasBottomBar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: hasBottomBar
            ? HomeNavigationMetrics.bottomContentInset(context)
            : 0,
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: hasBottomBar,
        child: child,
      ),
    );
  }
}
