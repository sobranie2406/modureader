import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Windows' texture WebView owns a child Focus and may bubble unhandled keys.
/// Do not steal focus from it (which would deactivate the native selection).
bool readerOwnsPageKeys(FocusNode reader, FocusScopeNode webView,
    {required bool windows}) {
  if (reader.hasPrimaryFocus) return true;
  if (!windows || !reader.hasFocus || !webView.hasFocus) return false;
  final context = FocusManager.instance.primaryFocus?.context;
  if (context?.findAncestorWidgetOfExactType<EditableText>() != null) {
    return false;
  }
  return true;
}

int readerPageKeyDirection(KeyEvent event,
    {bool control = false,
    bool shift = false,
    bool alt = false,
    bool meta = false,
    bool ctrlBrackets = false}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return 0;
  if (shift || alt || meta) return 0;
  final key = event.logicalKey;
  if (control) {
    if (!ctrlBrackets) return 0;
    if (key == LogicalKeyboardKey.bracketLeft ||
        event.physicalKey == PhysicalKeyboardKey.bracketLeft) {
      return -1;
    }
    if (key == LogicalKeyboardKey.bracketRight ||
        event.physicalKey == PhysicalKeyboardKey.bracketRight) {
      return 1;
    }
    return 0;
  }
  if (const [
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.space,
  ].contains(key)) {
    return 1;
  }
  if (const [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.pageUp,
  ].contains(key)) {
    return -1;
  }
  return 0;
}
