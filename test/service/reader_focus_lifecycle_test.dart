import 'dart:io';

import 'package:anx_reader/service/reader_keyboard.dart';
import 'package:anx_reader/service/reader_page_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeactivationProbe extends StatefulWidget {
  const _DeactivationProbe({required this.onDeactivate});
  final void Function(BuildContext) onDeactivate;

  @override
  StatefulElement createElement() => _DeactivationElement(this);

  @override
  State<_DeactivationProbe> createState() => _DeactivationProbeState();
}

class _DeactivationProbeState extends State<_DeactivationProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _DeactivationElement extends StatefulElement {
  _DeactivationElement(_DeactivationProbe super.widget);

  @override
  void deactivate() {
    super.deactivate();
    (widget as _DeactivationProbe).onDeactivate(this);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a retained, unmounted focus context blocks keys without throwing',
      (tester) async {
    late BuildContext oldFocus;
    await tester.pumpWidget(Builder(builder: (context) {
      oldFocus = context;
      return const SizedBox();
    }));
    await tester.pumpWidget(const SizedBox());
    expect(oldFocus.mounted, isFalse);
    // The user's framework.dart:3666 frame is this exact null assertion.
    expect(() => oldFocus.widget, throwsA(isA<TypeError>()));
    expect(() => readerFocusBlocksPageKeys(oldFocus), returnsNormally);
    expect(readerFocusBlocksPageKeys(oldFocus), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a context being deactivated must not be searched for ancestors',
      (tester) async {
    bool? blocked;
    await tester.pumpWidget(_DeactivationProbe(onDeactivate: (context) {
      expect(context.mounted, isTrue);
      blocked = readerFocusBlocksPageKeys(context);
    }));
    await tester.pumpWidget(const SizedBox());
    expect(blocked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editor descendants block paging and ordinary reader focus allows it',
      (tester) async {
    final controller = TextEditingController();
    final editorFocus = FocusNode();
    final readerFocus = FocusNode();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TextField(controller: controller, focusNode: editorFocus),
      Focus(focusNode: readerFocus, child: const Text('正文')),
    ]))));
    editorFocus.requestFocus();
    await tester.pump();
    expect(
        readerFocusBlocksPageKeys(FocusManager.instance.primaryFocus?.context),
        isTrue);
    final editable = tester.element(find.byType(EditableText));
    expect(readerFocusBlocksPageKeys(editable), isTrue);
    readerFocus.requestFocus();
    await tester.pump();
    expect(
        readerFocusBlocksPageKeys(FocusManager.instance.primaryFocus?.context),
        isFalse);
    expect(readerFocusBlocksPageKeys(null), isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    editorFocus.dispose();
    readerFocus.dispose();
  });

  testWidgets(
      'repeated menu removal, drawer focus and return keep the reader usable',
      (tester) async {
    final scaffold = GlobalKey<ScaffoldState>();
    final editor = FocusNode(), reader = FocusNode();
    late StateSetter rebuild;
    var controls = true, drawer = false;
    BuildContext? retained;
    final configurations = <MethodCall>[];
    final bridge = ReaderPageKeys(android: true, onDirection: (_) {});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(ReaderPageKeys.channel, (call) async {
      configurations.add(call);
      return null;
    });
    void updateKeys() => bridge.update(
        active: !controls &&
            !drawer &&
            !readerFocusBlocksPageKeys(
                retained ?? FocusManager.instance.primaryFocus?.context),
        volume: false);
    FocusManager.instance.addListener(updateKeys);
    addTearDown(() {
      FocusManager.instance.removeListener(updateKeys);
      bridge.dispose();
      messenger.setMockMethodCallHandler(ReaderPageKeys.channel, null);
    });
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      updateKeys();
      return Scaffold(
        key: scaffold,
        onDrawerChanged: (open) {
          drawer = open;
          updateKeys();
        },
        drawer: const Drawer(child: Center(child: Text('目录'))),
        body: Column(children: [
          Focus(focusNode: reader, child: const Text('正文仍显示')),
          if (controls)
            Builder(builder: (context) {
              retained = context;
              return TextField(focusNode: editor);
            }),
          TextButton(
              onPressed: () {
                drawer = true;
                rebuild(() => controls = false);
                scaffold.currentState!.openDrawer();
              },
              child: const Text('打开目录')),
        ]),
      );
    })));
    for (var i = 0; i < 5; i++) {
      editor.requestFocus();
      await tester.pump();
      await tester.tap(find.text('打开目录'));
      await tester.pumpAndSettle();
      expect(retained!.mounted, isFalse);
      updateKeys();
      expect(find.text('目录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      scaffold.currentState!.closeDrawer();
      await tester.pumpAndSettle();
      updateKeys(); // Still using the stale focus context, as in the report.
      expect(tester.takeException(), isNull);
      expect(find.text('正文仍显示'), findsOneWidget);
      retained = null;
      reader.requestFocus();
      await tester.pump();
      updateKeys();
      expect(configurations.last.arguments, {'active': true, 'volume': false});
      rebuild(() => controls = true);
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
    reader.dispose();
  });

  test('reading-page eligibility stops before reading any stale focus context',
      () {
    final source = File('lib/page/reading_page.dart').readAsStringSync();
    final eligibility = source.substring(
        source.indexOf('bool get _canUsePageKeys'),
        source.indexOf('void _updatePageKeys'));
    expect(eligibility, isNot(contains('focused?.widget')));
    expect(eligibility.indexOf('!mounted'),
        lessThan(eligibility.indexOf('readerFocusBlocksPageKeys')));
    expect(eligibility.indexOf('_readerDrawerOpen'),
        lessThan(eligibility.indexOf('readerFocusBlocksPageKeys')));
  });
}
