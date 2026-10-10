import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
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

  static void show(String message,
      {Icon? icon, int duration = 2000, BuildContext? context}) {
    final toastContext = context ?? _context ?? fToast.context;
    if (toastContext == null || !toastContext.mounted) return;
    fToast.init(toastContext);
    Widget toast = Semantics(
        liveRegion: true,
        child: FilledContainer(
          radius: 1000,
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon ?? const Icon(Icons.info_outline),
              const SizedBox(
                width: 12.0,
              ),
              Flexible(
                child: Text(
                  message,
                  // wrap
                  style: TextStyle(
                    color: Theme.of(toastContext).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ));

    // close previous toast
    fToast.removeQueuedCustomToasts();

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(milliseconds: duration),
      fadeDuration: AppMotion.duration(const Duration(milliseconds: 200)),
      ignorePointer: true,
    );
  }
}
