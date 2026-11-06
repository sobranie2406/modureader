import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local book dimming; never changes application or system brightness.
class AppBrightness extends ChangeNotifier {
  AppBrightness({bool? nativeWindow, bool? nativeDimming})
      : _nativeWindow = nativeWindow ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
        _nativeDimming = nativeDimming ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);

  static final instance = AppBrightness();
  static const levelKey = 'appBrightnessLevel';
  static const followSystemKey = 'appBrightnessFollowSystem';
  static const channel = MethodChannel('com.modu.reader/brightness');
  static const minimum = 0.0;

  final bool _nativeWindow;
  final bool _nativeDimming;
  SharedPreferences? _prefs;
  bool _followSystem = true;
  double _level = 0.6;

  bool get followSystem => _followSystem;
  double get level => _level;
  double get dimOpacity => _followSystem ? 0 : (1 - _level).clamp(0.0, 0.95);

  // Paint inside the reader DOM, including footnotes, to preserve native WebView
  // hit testing on macOS. Fixed positioning does not affect book pagination.
  String readerDimmingScript() {
    final opacity = dimOpacity;
    return '''(function () {
      var dimmer = document.getElementById('modu-book-brightness');
      if (!dimmer && $opacity > 0 && document.body) {
        dimmer = document.createElement('div');
        dimmer.id = 'modu-book-brightness';
        dimmer.setAttribute('aria-hidden', 'true');
        dimmer.style.cssText = 'position:fixed;top:0;right:0;bottom:0;left:0;pointer-events:none;z-index:1001;';
        document.body.appendChild(dimmer);
      }
      if (dimmer) {
        dimmer.style.backgroundColor = 'rgba(0,0,0,$opacity)';
        dimmer.style.display = $opacity > 0 ? 'block' : 'none';
      }
    })();''';
  }

  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    final stored = prefs.get(levelKey);
    _level = stored is num && stored.isFinite
        ? stored.toDouble().clamp(minimum, 1.0)
        : 0.6;
    _followSystem = prefs.get(followSystemKey) != false;
    // Clear overrides left by older builds; sliders never call this bridge.
    if (_nativeWindow || _nativeDimming) {
      try {
        await channel.invokeMethod<void>('setBrightness', {'brightness': null});
      } on PlatformException {
        // A fresh window already follows system brightness.
      } on MissingPluginException {
        // No window override exists on platforms without this bridge.
      }
    }
  }

  void setLevel(double value) {
    if (!value.isFinite) return;
    _level = value.clamp(minimum, 1.0);
    _followSystem = false;
    notifyListeners();
  }

  void setFollowSystem(bool value) {
    _followSystem = value;
    notifyListeners();
    unawaited(save());
  }

  /// Persist at the end of a drag, not on every slider frame.
  Future<void> save() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setDouble(levelKey, _level);
      await prefs.setBool(followSystemKey, _followSystem);
    } catch (_) {
      // A settings write failure must not interrupt reading or slider input.
    }
  }
}
