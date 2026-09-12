import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Restore the book's native WebView, not the surrounding Flutter controls.
/// Windows' texture-backed plugin restores its own Flutter focus scope instead;
/// its controller does not implement requestFocus in the pinned version.
Future<void> restoreNativeReaderFocus(
    Future<bool?> Function() requestWebViewFocus) async {
  if (kIsWeb ||
      !const {
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform)) {
    return;
  }
  try {
    await requestWebViewFocus();
  } on MissingPluginException {
    // A missing/disposed native host must not break menu dismissal.
  } on UnimplementedError {
    // Older plugin hosts may not expose the method yet.
  } on PlatformException catch (error) {
    debugPrint('Unable to restore native reader focus: ${error.code}');
  }
}
