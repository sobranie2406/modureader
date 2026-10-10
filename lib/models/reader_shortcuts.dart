import 'dart:convert';
import 'package:flutter/services.dart';

enum ReaderAction {
  previous('上一页', 'Previous page', -1),
  next('下一页', 'Next page', 1),
  menu('打开菜单', 'Open menu', 3),
  playPause('朗读：播放 / 暂停', 'Narration: play / pause', 4),
  previousPassage('朗读：上一段', 'Narration: previous passage', 6),
  nextPassage('朗读：下一段', 'Narration: next passage', 7);

  const ReaderAction(this.zh, this.en, this.nativeCode);
  final String zh, en;
  final int nativeCode;
}

// The same names are used by Flutter, DOM KeyboardEvent and Android key codes.
final readerShortcutKeys = <String, (LogicalKeyboardKey, int)>{
  'arrowleft': (LogicalKeyboardKey.arrowLeft, 21),
  'arrowright': (LogicalKeyboardKey.arrowRight, 22),
  'arrowup': (LogicalKeyboardKey.arrowUp, 19),
  'arrowdown': (LogicalKeyboardKey.arrowDown, 20),
  'pageup': (LogicalKeyboardKey.pageUp, 92),
  'pagedown': (LogicalKeyboardKey.pageDown, 93),
  'space': (LogicalKeyboardKey.space, 62),
  'enter': (LogicalKeyboardKey.enter, 66),
  'home': (LogicalKeyboardKey.home, 122),
  'end': (LogicalKeyboardKey.end, 123),
  '[': (LogicalKeyboardKey.bracketLeft, 71),
  ']': (LogicalKeyboardKey.bracketRight, 72),
  for (var i = 0; i < 26; i++)
    String.fromCharCode(97 + i): (LogicalKeyboardKey(97 + i), 29 + i),
  for (var i = 0; i < 10; i++) '$i': (LogicalKeyboardKey(48 + i), 7 + i),
  for (var i = 0; i < 12; i++)
    'f${i + 1}': (LogicalKeyboardKey(LogicalKeyboardKey.f1.keyId + i), 131 + i),
};

class ReaderKey {
  const ReaderKey(this.key, [this.modifiers = 0]);
  final String key;
  // Ctrl=1, Shift=2, Alt=4, Meta=8; exact matching avoids stealing OS shortcuts.
  final int modifiers;
  String get id => '$modifiers:$key';
  String get label => [
        if (modifiers & 1 != 0) 'Ctrl',
        if (modifiers & 2 != 0) 'Shift',
        if (modifiers & 4 != 0) 'Alt',
        if (modifiers & 8 != 0) 'Meta',
        switch (key) {
          'space' => 'Space',
          'pageup' => 'Page Up',
          'pagedown' => 'Page Down',
          _ => readerShortcutKeys[key]?.$1.keyLabel ?? key,
        },
      ].join(' + ');
  static ReaderKey? fromEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
    final keyboard = HardwareKeyboard.instance;
    var logicalKey = event.logicalKey;
    // Shift/Option can turn a supported key into a symbol (e.g. Shift+1 = !).
    if (!readerShortcutKeys.values.any((value) => value.$1 == logicalKey)) {
      final physical = event.physicalKey.usbHidUsage;
      if (physical >= PhysicalKeyboardKey.keyA.usbHidUsage &&
          physical <= PhysicalKeyboardKey.keyZ.usbHidUsage) {
        logicalKey = LogicalKeyboardKey(
            97 + physical - PhysicalKeyboardKey.keyA.usbHidUsage);
      } else if (physical >= PhysicalKeyboardKey.digit1.usbHidUsage &&
          physical <= PhysicalKeyboardKey.digit0.usbHidUsage) {
        logicalKey = LogicalKeyboardKey(
            48 + (physical - PhysicalKeyboardKey.digit1.usbHidUsage + 1) % 10);
      } else if (event.physicalKey == PhysicalKeyboardKey.bracketLeft) {
        logicalKey = LogicalKeyboardKey.bracketLeft;
      } else if (event.physicalKey == PhysicalKeyboardKey.bracketRight) {
        logicalKey = LogicalKeyboardKey.bracketRight;
      }
    }
    for (final entry in readerShortcutKeys.entries) {
      if (entry.value.$1 == logicalKey) {
        return ReaderKey(
            entry.key,
            (keyboard.isControlPressed ? 1 : 0) |
                (keyboard.isShiftPressed ? 2 : 0) |
                (keyboard.isAltPressed ? 4 : 0) |
                (keyboard.isMetaPressed ? 8 : 0));
      }
    }
    return null;
  }
}

class ReaderShortcuts {
  ReaderShortcuts(this.bindings);
  final Map<ReaderAction, List<ReaderKey>> bindings;
  factory ReaderShortcuts.defaults() => ReaderShortcuts({
        ReaderAction.previous: [
          const ReaderKey('arrowleft'),
          const ReaderKey('arrowup'),
          const ReaderKey('pageup')
        ],
        ReaderAction.next: [
          const ReaderKey('arrowright'),
          const ReaderKey('arrowdown'),
          const ReaderKey('pagedown'),
          const ReaderKey('space')
        ],
        ReaderAction.menu: [const ReaderKey('enter'), const ReaderKey('m')],
        ReaderAction.playPause: [const ReaderKey('p')],
        ReaderAction.previousPassage: [const ReaderKey('[')],
        ReaderAction.nextPassage: [const ReaderKey(']')],
      });
  factory ReaderShortcuts.decode(String? source) {
    if (source == null) return ReaderShortcuts.defaults();
    try {
      final json = jsonDecode(source);
      if (json is! Map) return ReaderShortcuts.defaults();
      // Reuse the old play binding (including an intentionally empty list).
      if (!json.containsKey('playPause')) {
        if (json['play'] is List) {
          json['playPause'] = json['play'];
        } else if (json['pause'] is List) {
          json['playPause'] = json['pause'];
        }
      }
      final result = ReaderShortcuts.defaults();
      final used = <String>{};
      for (final action in ReaderAction.values) {
        if (json[action.name] is List) {
          result.bindings[action] = [
            for (final value in (json[action.name] as List).take(8))
              if (value is Map &&
                  readerShortcutKeys.containsKey(value['key']) &&
                  value['modifiers'] is int &&
                  value['modifiers'] >= 0 &&
                  value['modifiers'] <= 15)
                ReaderKey(value['key'], value['modifiers']),
          ];
        }
        result.bindings[action]!.removeWhere((key) => !used.add(key.id));
      }
      return result;
    } catch (_) {
      return ReaderShortcuts.defaults();
    }
  }
  String encode() => jsonEncode({
        for (final entry in bindings.entries)
          entry.key.name: [
            for (final key in entry.value)
              {'key': key.key, 'modifiers': key.modifiers}
          ]
      });
  Map<String, String> actions({bool ctrlBrackets = false}) => {
        if (ctrlBrackets) '1:[': ReaderAction.previous.name,
        if (ctrlBrackets) '1:]': ReaderAction.next.name,
        for (final entry in bindings.entries)
          for (final key in entry.value) key.id: entry.key.name,
      };
  List<Map<String, int>> nativeBindings({bool ctrlBrackets = false}) => [
        for (final entry in actions(ctrlBrackets: ctrlBrackets).entries)
          {
            'keyCode': readerShortcutKeys[entry.key.split(':').last]!.$2,
            'modifiers': int.parse(entry.key.split(':').first),
            'action': ReaderAction.values.byName(entry.value).nativeCode
          },
      ];
}
