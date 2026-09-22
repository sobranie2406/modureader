import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local brightness. Android uses a window override; macOS uses an
/// input-transparent native dimmer so Flutter does not obscure WKWebView input.
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
  static const minimum = 0.2;

  final bool _nativeWindow;
  final bool _nativeDimming;
  SharedPreferences? _prefs;
  bool _nativeFailed = false;
  bool _followSystem = true;
  double _level = 0.6;
  int _revision = 0;

  bool get followSystem => _followSystem;
  double get level => _level;
  bool get usesWindowBrightness => _nativeWindow && !_nativeFailed;
  // Never fall back to Flutter painting on macOS: that blocks native input.
  bool get paintsFlutterDimming => !_nativeDimming;
  bool get nativeDimmingUnavailable => _nativeDimming && _nativeFailed;
  double get dimOpacity =>
      _followSystem || usesWindowBrightness || _nativeDimming ? 0 : 1 - _level;

  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    final stored = prefs.get(levelKey);
    _level = stored is num && stored.isFinite
        ? stored.toDouble().clamp(minimum, 1.0)
        : 0.6;
    _followSystem = prefs.get(followSystemKey) != false;
    await _apply();
  }

  void setLevel(double value) {
    if (!value.isFinite) return;
    _level = value.clamp(minimum, 1.0);
    _followSystem = false;
    notifyListeners();
    unawaited(_apply());
  }

  void setFollowSystem(bool value) {
    _followSystem = value;
    notifyListeners();
    unawaited(_apply());
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

  Future<void> _apply() async {
    if (!_nativeWindow && !_nativeDimming) return;
    final revision = ++_revision;
    try {
      await channel.invokeMethod<void>('setBrightness', {
        'brightness': _followSystem ? null : _level,
      });
      if (revision != _revision) return;
      if (_nativeFailed) {
        _nativeFailed = false;
        notifyListeners();
      }
    } on PlatformException {
      _useDimmingFallback(revision);
    } on MissingPluginException {
      _useDimmingFallback(revision);
    }
  }

  void _useDimmingFallback(int revision) {
    if (revision != _revision || _nativeFailed) return;
    _nativeFailed = true;
    notifyListeners();
  }
}
