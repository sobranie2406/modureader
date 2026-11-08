import 'dart:async';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/widgets.dart';
import 'reader_content_brightness.dart';

/// Native popup content has exactly one owner for brightness.
class ReaderWebBrightness {
  ReaderWebBrightness(this.evaluate, {AnxPlatformEnum? platform})
      : platform = platform ?? AnxPlatform.type;
  final Future<void> Function(String) evaluate;
  final AnxPlatformEnum platform;
  AppBrightness? _brightness;

  void bind(BuildContext context) {
    final surface =
        context.findAncestorWidgetOfExactType<ReaderContentBrightness>();
    // The pinned OHOS mutator applies clips/transforms but not opacity.
    // Android uses texture composition; Apple/desktop views use outer Opacity.
    final next = platform == AnxPlatformEnum.ohos && surface != null
        ? surface.controller ?? AppBrightness.instance
        : null;
    if (identical(next, _brightness)) return;
    _brightness?.removeListener(_changed);
    _brightness = next;
    _brightness?.addListener(_changed);
    _changed();
  }

  void _changed() => unawaited(apply());

  Future<void> apply() async {
    final brightness = _brightness;
    if (brightness == null) return;
    final opacity = 1 - brightness.dimOpacity;
    try {
      await evaluate(
          "document.documentElement.style.setProperty('opacity', '$opacity', 'important');");
    } catch (_) {
      // A navigating/disposed view is retried on the next load.
    }
  }

  void dispose() => _brightness?.removeListener(_changed);
}
