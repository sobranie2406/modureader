import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter focus alone cannot restore AppKit's first responder after a native
/// platform view / text input overlay resigns it on macOS.
Future<void> restoreNativeReaderFocus() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
  try {
    await const MethodChannel('com.modu.reader/reader_focus')
        .invokeMethod<bool>('restore');
  } on MissingPluginException {
    // Tests and non-desktop hosts still use the regular Flutter focus path.
  } on PlatformException catch (error) {
    debugPrint('Unable to restore native reader focus: ${error.code}');
  }
}
