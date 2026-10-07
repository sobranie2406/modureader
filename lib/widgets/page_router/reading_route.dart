import 'package:anx_reader/utils/app_motion.dart';
import 'package:flutter/cupertino.dart';

/// Keep normal navigation semantics, but disable both route and Hero animation
/// when the user switches off bookshelf-to-reader transitions.
Route<T> readingRoute<T>(
    {required WidgetBuilder builder,
    required bool animate,
    bool deferReaderUntilTransition = false,
    Widget openingPlaceholder = const SizedBox.expand()}) {
  if (animate && !AppMotion.disabled && deferReaderUntilTransition) {
    // Android's native WebView must not be created/scaled during the cover
    // transition. Animate a Flutter-only placeholder, then mount the reader.
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => HeroMode(
        enabled: false,
        child: _DeferredReader(
          animation: animation,
          builder: builder,
          placeholder: openingPlaceholder,
        ),
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
  if (animate && !AppMotion.disabled)
    return MotionCupertinoPageRoute<T>(builder: builder);
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) =>
        HeroMode(enabled: false, child: builder(context)),
  );
}

class _DeferredReader extends StatefulWidget {
  const _DeferredReader(
      {required this.animation,
      required this.builder,
      required this.placeholder});
  final Animation<double> animation;
  final WidgetBuilder builder;
  final Widget placeholder;

  @override
  State<_DeferredReader> createState() => _DeferredReaderState();
}

class _DeferredReaderState extends State<_DeferredReader> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
    // ModalRoute temporarily reports a completed animation during its first
    // offstage Hero measurement, even though the push has not finished.
    _onStatus(widget.animation.status);
  }

  void _onStatus(AnimationStatus status) {
    if (_ready || status != AnimationStatus.completed) return;
    // Finish painting the transition before initializing platform views.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_ready &&
          ModalRoute.of(context)?.offstage != true &&
          widget.animation.status == AnimationStatus.completed) {
        setState(() => _ready = true);
      }
    });
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ready
      ? widget.builder(context)
      : RepaintBoundary(child: widget.placeholder);
}
