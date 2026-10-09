import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared by both ends of the Hero so closing first folds the cover shut,
/// then shrinks it back to the shelf on every platform.
CreateRectTween get readerCoverRectTween =>
    (begin, end) => ReaderCoverRectTween(begin: begin, end: end);

class ReaderCoverRectTween extends RectTween {
  ReaderCoverRectTween({super.begin, super.end});

  static const expansionEnd = 0.55;

  static double expansion(double progress) => Curves.easeInOutCubic
      .transform((progress / expansionEnd).clamp(0.0, 1.0));

  @override
  Rect? lerp(double t) {
    final growing = end!.width * end!.height >= begin!.width * begin!.height;
    final fraction = growing ? expansion(t) : 1 - expansion(1 - t);
    return Rect.lerp(begin, end, fraction);
  }
}

/// Never move the native platform view into the Hero overlay. It must keep
/// its original constraints and parent while the cover flies between routes.
/// The reader still mounts immediately; this does not defer book loading.
class ReaderCoverHero extends StatelessWidget {
  const ReaderCoverHero({
    super.key,
    required this.tag,
    required this.cover,
    required this.child,
  });

  final Object tag;
  final Widget cover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A destination Hero normally removes its child during flight. Keep the
    // native reader outside it, otherwise even a cover-only shuttle disposes
    // and recreates the WebView at the end of each transition.
    return Stack(fit: StackFit.expand, children: [
      child,
      IgnorePointer(
        child: Hero(
          tag: tag,
          transitionOnUserGestures: true,
          curve: Curves.linear,
          reverseCurve: Curves.linear,
          createRectTween: readerCoverRectTween,
          flightShuttleBuilder: (context, animation, direction, from, to) {
            final shelfContext =
                direction == HeroFlightDirection.push ? from : to;
            final shelfBox = shelfContext.findRenderObject()! as RenderBox;
            final size = shelfBox.size;
            // Paint at a stable size once and scale the cached layer. Resizing
            // the image/rounded border on every flight frame defeats caching.
            // Use the thumbnail's aspect ratio to avoid an initial crop jump.
            return ReaderCoverTurn(
              animation: animation,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox.fromSize(
                  size: size,
                  child: RepaintBoundary(child: cover),
                ),
              ),
            );
          },
          child: const SizedBox.expand(),
        ),
      ),
    ]);
  }
}

/// The route animation always describes openness (0 = shelf, 1 = reader),
/// including on pop or an interrupted/reversed flight. Never reverse it twice.
class ReaderCoverTurn extends StatelessWidget {
  const ReaderCoverTurn(
      {super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final turn = Curves.easeInOutCubic.transform(
              ((animation.value - ReaderCoverRectTween.expansionEnd) /
                      (1 - ReaderCoverRectTween.expansionEnd))
                  .clamp(0.0, 1.0));
          return LayoutBuilder(builder: (context, constraints) {
            // Open outward around the left spine, like a physical front cover.
            // Positive Y brings the free/right edge toward the viewer; negative
            // Y folds it inward into the page. Perspective
            // scales with width, so phone and tablet covers turn identically.
            final transform = Matrix4.identity()
              ..setEntry(3, 2, 0.6 / math.max(1, constraints.maxWidth))
              ..rotateY(math.pi / 2 * turn);
            return ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                // A painted shadow, not a blurred/filter layer over the WebView.
                if (turn > 0 && turn < 1)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Color.fromRGBO(
                            0, 0, 0, 0.16 * math.sin(math.pi * turn)),
                        const Color(0x00000000),
                      ]),
                    ),
                  ),
                if (turn < 1)
                  Transform(
                    key: const ValueKey('reader-cover-spine-turn'),
                    alignment: Alignment.centerLeft,
                    transform: transform,
                    child: child,
                  ),
              ]),
            );
          });
        },
      );
}
