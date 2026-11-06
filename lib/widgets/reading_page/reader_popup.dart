import 'reader_menu_appearance.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/reading_page/adjustable_reader_popup.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:anx_reader/widgets/common/app_scroll_behavior.dart';

/// Shared geometry for reader query and settings panels.
class ReaderPopup extends StatelessWidget {
  const ReaderPopup({super.key, required this.child});
  final Widget child;

  static BoxConstraints constraints(BuildContext context) =>
      Theme.of(context).bottomSheetTheme.constraints ??
      BoxConstraints(
          maxWidth: Theme.of(context).useMaterial3 ? 640 : double.infinity);

  static double height(BuildContext context) {
    final media = MediaQuery.of(context);
    return math.max(
        0.0,
        math.min(media.size.height * Prefs().readerPopupMaxHeightPercent / 100,
            media.size.height - media.viewInsets.bottom - media.padding.top));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: PointerInterceptor(
        child: SizedBox(
          key: const ValueKey('reader-popup-body'),
          width: double.infinity,
          height: height(context),
          // This container already consumes the keyboard inset. Nested chat
          // Scaffolds must not resize by that same inset a second time.
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: RepaintBoundary(
              child: ScrollConfiguration(
                  behavior: const AppScrollBehavior(symmetricGutter: true),
                  child: Padding(
                      padding: const EdgeInsets.only(top: 8), child: child)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keep quick settings compact without moving the toolbar offscreen.
class ReaderQuickStylePanel extends StatelessWidget {
  const ReaderQuickStylePanel(
      {super.key, required this.content, required this.toolbar});

  final Widget content;
  final Widget toolbar;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
      behavior: const AppScrollBehavior(symmetricGutter: true),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: ReaderPopup.height(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
                child: ListTileTheme.merge(
                    subtitleTextStyle: Theme.of(context).textTheme.bodySmall,
                    child: content)),
            toolbar
          ],
        ),
      ));
}

Future<void> showReaderPopup(BuildContext context,
    {required WidgetBuilder builder,
    bool enableDrag = true,
    bool readerAppearance = true,
    bool allowWindowAdjustment = false,
    Rect? selectionRect,
    Color? barrierColor,
    double initialHeightFraction = 0.8}) async {
  if (selectionRect != null ||
      (allowWindowAdjustment && Prefs().readerPopupAdjustmentEnabled)) {
    await showAdjustableReaderPopup(context,
        builder: builder,
        selectionRect: selectionRect,
        barrierColor: barrierColor,
        initialHeightFraction: initialHeightFraction,
        readerAppearance: readerAppearance);
    return;
  }
  final menuTheme = readerAppearance
      ? ReaderMenuAppearance.theme(context)
      : Theme.of(context);
  ModalRoute<dynamic>? route;
  // Keep the content widget stable while the bottom-sheet route responds to
  // keyboard metrics; build it below the consumed-inset MediaQuery.
  final content = Builder(builder: builder);
  await showModalBottomSheet<void>(
    sheetAnimationStyle: AppMotion.style,
    barrierColor: barrierColor,
    backgroundColor: menuTheme.bottomSheetTheme.modalBackgroundColor ??
        menuTheme.bottomSheetTheme.backgroundColor,
    elevation: menuTheme.bottomSheetTheme.modalElevation ??
        menuTheme.bottomSheetTheme.elevation,
    context: context,
    constraints: ReaderPopup.constraints(context),
    isScrollControlled: true,
    enableDrag: enableDrag,
    showDragHandle: false,
    clipBehavior: Clip.antiAlias,
    builder: (context) {
      route = ModalRoute.of(context);
      return Theme(data: menuTheme, child: ReaderPopup(child: content));
    },
  );
  // Native reader views must not regain focus during the reverse animation.
  await route?.completed;
}
