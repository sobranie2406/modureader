import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Shared geometry for reader AI and selection-translation popups.
class ReaderPopup extends StatelessWidget {
  const ReaderPopup({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = math.max(
        0.0,
        math.min(media.size.height * 0.8,
            media.size.height - media.viewInsets.bottom - media.padding.top));
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: PointerInterceptor(
        child: SizedBox(
          key: const ValueKey('reader-popup-body'),
          width: double.infinity,
          height: height,
          child: Padding(padding: const EdgeInsets.only(top: 8), child: child),
        ),
      ),
    );
  }
}

Future<void> showReaderPopup(BuildContext context,
    {required WidgetBuilder builder}) async {
  ModalRoute<dynamic>? route;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    clipBehavior: Clip.hardEdge,
    builder: (context) {
      route = ModalRoute.of(context);
      return ReaderPopup(child: builder(context));
    },
  );
  // Native reader views must not regain focus during the reverse animation.
  await route?.completed;
}
