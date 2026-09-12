import 'package:anx_reader/service/reader_focus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.android,
    TargetPlatform.iOS
  ]) {
    test('$platform restores the current book native WebView', () async {
      debugDefaultTargetPlatformOverride = platform;
      var requests = 0;
      await restoreNativeReaderFocus(() async {
        requests++;
        return true;
      });
      expect(requests, 1);
    });
  }
  test('Windows leaves focus to its texture-backed plugin scope', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var called = false;
    await restoreNativeReaderFocus(() async {
      called = true;
      return true;
    });
    expect(called, isFalse);
  });
  test('missing native host does not crash the reader', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await restoreNativeReaderFocus(() async => throw MissingPluginException());
  });
  test('disposed native view and rejected focus do not crash the reader',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await restoreNativeReaderFocus(() async => false);
    await restoreNativeReaderFocus(
        () async => throw PlatformException(code: 'disposed'));
    await restoreNativeReaderFocus(() async => throw UnimplementedError());
  });

  testWidgets(
      'book scope restores the plugin child after an external editor without focusing the wrapper',
      (tester) async {
    final scope = FocusScopeNode();
    final plugin = FocusNode();
    final editor = FocusNode();
    final outer = FocusNode();
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      Focus(
          focusNode: outer,
          child: FocusScope(
              node: scope,
              child: Focus(
                  focusNode: plugin,
                  child: const SizedBox(width: 40, height: 40)))),
      Focus(focusNode: editor, child: const SizedBox(width: 40, height: 40)),
    ])));
    plugin.requestFocus();
    await tester.pump();
    expect(plugin.hasPrimaryFocus, isTrue);
    for (var i = 0; i < 3; i++) {
      editor.requestFocus();
      await tester.pump();
      expect(editor.hasPrimaryFocus, isTrue);
      scope.requestFocus();
      await tester.pump();
      expect(plugin.hasPrimaryFocus, isTrue);
      expect(outer.hasPrimaryFocus, isFalse);
      expect(editor.hasFocus, isFalse);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    scope.dispose();
    plugin.dispose();
    editor.dispose();
    outer.dispose();
  });
}
