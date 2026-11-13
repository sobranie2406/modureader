import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AnxToast {
  static FToast fToast = FToast();
  static BuildContext? _context;

  static void init(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        _context = context;
        fToast.init(context);
      }
    });
  }

  /// Shared by both toast hosts. Keep the background fixed and text opaque.
  static Widget content(BuildContext context, String message, {Icon? icon}) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Theme(
        // Rounded containers otherwise blend their translucent fill over an
        // opaque surface to cover the card shadow.
        data: theme.copyWith(cardTheme: theme.cardTheme.copyWith(elevation: 0)),
        child: FilledContainer(
          fill: true,
          color: theme.colorScheme.surface.withValues(alpha: .5),
          radius: 1000,
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon ?? const Icon(Icons.info_outline),
              const SizedBox(width: 12),
              Flexible(
                child: Text(message,
                    style: TextStyle(color: theme.colorScheme.onSurface)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void show(String message,
      {Icon? icon, int duration = 2000, BuildContext? context}) {
    final toastContext = context ?? _context ?? fToast.context;
    if (toastContext == null || !toastContext.mounted) return;
    fToast.init(toastContext);
    fToast.removeQueuedCustomToasts();
    fToast.showToast(
      child: content(toastContext, message, icon: icon),
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(milliseconds: duration),
      fadeDuration: AppMotion.duration(const Duration(milliseconds: 200)),
      ignorePointer: true,
    );
  }
}
