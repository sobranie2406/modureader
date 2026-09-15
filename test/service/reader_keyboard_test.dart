import 'package:anx_reader/service/reader_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  KeyDownEvent key(LogicalKeyboardKey logical,
          [PhysicalKeyboardKey physical = PhysicalKeyboardKey.arrowRight]) =>
      KeyDownEvent(
          physicalKey: physical, logicalKey: logical, timeStamp: Duration.zero);

  test('arrows page without modifiers; Ctrl brackets require the setting', () {
    for (final k in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space
    ]) {
      expect(readerPageKeyDirection(key(k)), 1);
    }
    for (final k in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageUp
    ]) {
      expect(readerPageKeyDirection(key(k)), -1);
    }
    for (final enabled in [false, true]) {
      expect(
          readerPageKeyDirection(key(LogicalKeyboardKey.bracketLeft),
              control: true, ctrlBrackets: enabled),
          enabled ? -1 : 0);
      expect(
          readerPageKeyDirection(key(LogicalKeyboardKey.bracketRight),
              control: true, ctrlBrackets: enabled),
          enabled ? 1 : 0);
    }
    expect(
        readerPageKeyDirection(
            key(LogicalKeyboardKey.braceRight,
                PhysicalKeyboardKey.bracketRight),
            control: true,
            ctrlBrackets: true),
        1);
    expect(
        readerPageKeyDirection(key(LogicalKeyboardKey.arrowRight),
            control: true, ctrlBrackets: true),
        0);
    expect(
        readerPageKeyDirection(key(LogicalKeyboardKey.arrowRight), shift: true),
        0);
    expect(
        readerPageKeyDirection(key(LogicalKeyboardKey.bracketLeft),
            control: true, alt: true, ctrlBrackets: true),
        0);
    expect(
        readerPageKeyDirection(key(LogicalKeyboardKey.bracketLeft),
            meta: true, ctrlBrackets: true),
        0);
    expect(
        readerPageKeyDirection(key(LogicalKeyboardKey.escape),
            ctrlBrackets: true),
        0);
    expect(
        readerPageKeyDirection(const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.arrowRight,
            logicalKey: LogicalKeyboardKey.arrowRight,
            timeStamp: Duration.zero)),
        0);
  });

  testWidgets(
      'Windows child-focus keys reach paging once; editor focus never pages',
      (tester) async {
    final reader = FocusNode(),
        plugin = FocusNode(),
        editor = FocusNode(),
        insideEditor = FocusNode();
    final scope = FocusScopeNode();
    final turns = <int>[];
    var shortcuts = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      Focus(
          focusNode: reader,
          onKeyEvent: (_, event) {
            if (!readerOwnsPageKeys(reader, scope, windows: true)) {
              return KeyEventResult.ignored;
            }
            final d = readerPageKeyDirection(event,
                control: HardwareKeyboard.instance.isControlPressed,
                ctrlBrackets: shortcuts);
            if (d == 0) return KeyEventResult.ignored;
            turns.add(d);
            return KeyEventResult.handled;
          },
          child: FocusScope(
              node: scope,
              child: Column(children: [
                Focus(
                    focusNode: plugin,
                    child: const SizedBox(width: 100, height: 30)),
                TextField(focusNode: insideEditor),
              ]))),
      TextField(focusNode: editor),
    ]))));
    plugin.requestFocus();
    await tester.pump();
    expect(reader.hasPrimaryFocus, isFalse);
    expect(readerOwnsPageKeys(reader, scope, windows: false), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(turns, [1, -1]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    expect(turns, [1, -1]);
    shortcuts = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(turns, [1, -1, 1, -1]);
    for (final field in [editor, insideEditor]) {
      field.requestFocus();
      await tester.pump();
      expect(readerOwnsPageKeys(reader, scope, windows: true), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    expect(turns, [1, -1, 1, -1]);
    scope.requestFocus();
    plugin.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(turns, [1, -1, 1, -1, 1]);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final node in [reader, plugin, editor, insideEditor, scope]) {
      node.dispose();
    }
  });
}
