import 'dart:convert';
import 'package:anx_reader/models/reader_shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  testWidgets('shifted symbol capture matches native and DOM key names',
      (tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (final (logical, physical, key) in [
      (LogicalKeyboardKey.exclamation, PhysicalKeyboardKey.digit1, '1'),
      (LogicalKeyboardKey.braceLeft, PhysicalKeyboardKey.bracketLeft, '['),
    ]) {
      final binding = ReaderKey.fromEvent(KeyDownEvent(
          logicalKey: logical,
          physicalKey: physical,
          timeStamp: Duration.zero));
      expect(binding?.id, '2:$key');
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });
  test(
      'defaults retain paging keys and all actions cross native/DOM boundaries',
      () {
    final defaults = ReaderShortcuts.defaults();
    expect(defaults.bindings[ReaderAction.previous], hasLength(3));
    expect(defaults.bindings[ReaderAction.next], hasLength(4));
    expect(defaults.actions()['0:enter'], 'menu');
    expect(defaults.actions()['0:p'], 'playPause');
    expect(defaults.actions()['0:o'], isNull);
    expect(defaults.actions(ctrlBrackets: true)['1:['], 'previous');
    expect(defaults.nativeBindings().length, defaults.actions().length);
    expect(
        ReaderShortcuts.decode(defaults.encode()).encode(), defaults.encode());
  });
  test('legacy play migrates to toggle without changing other bindings', () {
    final migrated = ReaderShortcuts.decode(jsonEncode({
      'play': [
        {'key': 'j', 'modifiers': 1}
      ],
      'pause': [
        {'key': 'k', 'modifiers': 2}
      ],
      'next': [
        {'key': 'n', 'modifiers': 0}
      ],
    }));
    expect(migrated.actions()['1:j'], 'playPause');
    expect(migrated.actions()['2:k'], isNull);
    expect(migrated.actions()['0:n'], 'next');
    expect(jsonDecode(migrated.encode()).keys, isNot(contains('play')));
    expect(jsonDecode(migrated.encode()).keys, isNot(contains('pause')));
    expect(migrated.nativeBindings(),
        contains(equals({'keyCode': 38, 'modifiers': 1, 'action': 4})));
    expect(
        ReaderShortcuts.decode('{"play":[]}').bindings[ReaderAction.playPause],
        isEmpty);
    expect(
        ReaderShortcuts.decode(
                '{"playPause":[],"play":[{"key":"j","modifiers":0}]}')
            .bindings[ReaderAction.playPause],
        isEmpty);
    expect(
        ReaderShortcuts.decode('{"pause":[{"key":"k","modifiers":0}]}')
            .actions()['0:k'],
        'playPause');
  });
  test(
      'invalid data is bounded; removed defaults stay removed and conflicts deduplicate',
      () {
    expect(ReaderShortcuts.decode('bad').actions(),
        ReaderShortcuts.defaults().actions());
    final config = ReaderShortcuts.decode(jsonEncode({
      'previous': [],
      'next': [
        {'key': 'x', 'modifiers': 3},
        {'key': 'bad', 'modifiers': 0}
      ],
      'menu': [
        {'key': 'x', 'modifiers': 3},
        {'key': 'm', 'modifiers': 16}
      ],
    }));
    expect(config.bindings[ReaderAction.previous], isEmpty);
    expect(config.actions()['3:x'], 'next');
    expect(config.bindings[ReaderAction.menu], isEmpty);
    expect(config.nativeBindings().first,
        {'keyCode': 52, 'modifiers': 3, 'action': 1});
  });
}
