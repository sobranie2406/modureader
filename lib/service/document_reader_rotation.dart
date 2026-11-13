import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:modu_reader/utils/platform_utils.dart';

/// Rotate the reader viewport, not just its bitmap. Dialogs and fit-width then
/// receive the same real window metrics as the page.
class DocumentReaderRotation {
  int _angle = 0;
  Size? _windowSize;
  bool _closed = false;
  Future<void> _pending = Future.value();
  Future<void> set(int angle) {
    final operation = _pending.then((_) async {
      if (_closed || angle == _angle) return;
      if (![0, 90, 180, 270].contains(angle)) {
        throw ArgumentError('Invalid rotation');
      }
      if (AnxPlatform.isMobile) {
        await SystemChrome.setPreferredOrientations(angle == 0
            ? []
            : [
                {
                  90: DeviceOrientation.landscapeLeft,
                  180: DeviceOrientation.portraitDown,
                  270: DeviceOrientation.landscapeRight
                }[angle]!,
              ]);
      } else {
        _windowSize ??= await windowManager.getSize();
        final size = _windowSize!;
        await windowManager
            .setSize(angle % 180 == 0 ? size : Size(size.height, size.width));
      }
      _angle = angle;
    });
    _pending = operation.catchError((_) {});
    return operation;
  }

  Future<void> close() async {
    _closed = true;
    await _pending;
    if (AnxPlatform.isMobile && _angle != 0) {
      await SystemChrome.setPreferredOrientations([]);
    }
    if (_windowSize != null) await windowManager.setSize(_windowSize!);
  }
}
