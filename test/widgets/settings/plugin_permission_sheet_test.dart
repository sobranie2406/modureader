import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_labels.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/widgets/plugins/plugin_permission_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/plugins/plugin_test_utils.dart';

const _id = 'com.example.permission-sheet';

void main() {
  // Package installation touches the file system, which the widget fake clock
  // cannot drive, so it happens here rather than inside a testWidgets body.
  late Directory temp;
  late PluginHost host;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    await Prefs().savePluginState(PluginState.empty);
    await Prefs().savePluginPermissions({});
    await Prefs().saveLocaleToPrefs('en');
    temp = await Directory.systemTemp.createTemp('modu_plugin_sheet_');
    host = PluginHost(
      trust: FixturePluginTrust(),
      paths: PluginPaths(rootPath: p.join(temp.path, 'plugins')),
      appVersionResolver: () async => '1.3.10',
    );
    await host.initialize();
    await host.install(await writePluginZip(
        temp,
        samplePackageFiles(
            manifest: manifestJson(
                id: _id,
                capabilities: const [
                  'script:run',
                  'ai:invoke',
                  'note:read',
                  'clipboard:read'
                ],
                contributes: const []))));
  });

  tearDown(() async {
    host.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Opens the sheet, lets [answer] drive it, and returns the resulting grants.
  Future<Set<String> Function()> open(WidgetTester tester,
      {required List<String> capabilities,
      required Future<void> Function(WidgetTester tester) answer}) async {
    late Future<Set<String>> pending;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              pending = showPluginPermissionRequest(context,
                  host: host,
                  pluginId: _id,
                  capabilities: capabilities,
                  reason: 'Needs the model to summarise this chapter.');
            },
            child: const Text('ask'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    await answer(tester);
    // Granting writes preferences and notifies listeners, which schedules work
    // outside the fake clock; a bounded pump lets the dialog close first.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    late Set<String> result;
    await tester.runAsync(() async => result = await pending);
    await tester.pump();
    return () => result;
  }

  testWidgets('every requested capability gets its own unticked row',
      (tester) async {
    await open(tester,
        capabilities: ['ai:invoke', 'note:read'],
        answer: (tester) async {
          expect(find.text('Plugin permission request'), findsOneWidget);
          expect(find.text('Needs the model to summarise this chapter.'),
              findsOneWidget);
          // Labels come from the shared catalogue, so the sheet and the details
          // page can never describe the same capability differently.
          final context = tester.element(find.text('ask'));
          for (final token in ['ai:invoke', 'note:read']) {
            expect(find.text(pluginCapabilityLabel(context, token)),
                findsOneWidget);
            expect(find.text(token), findsOneWidget);
          }
          final boxes = tester
              .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
              .toList();
          expect(boxes, hasLength(2));
          expect(boxes.every((box) => box.value == false), isTrue);
          // The expensive capability is flagged before the user decides.
          expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
          await tester.tap(find.text('Deny'));
          await tester.pump();
        });
    expect(host.grantedPermissions(_id), isEmpty);
  });

  testWidgets('confirming with nothing ticked grants nothing', (tester) async {
    final result = await open(tester,
        capabilities: ['ai:invoke'],
        answer: (tester) async {
          expect(find.text('Keep everything off'), findsOneWidget);
          await tester.tap(find.text('Keep everything off'));
          await tester.pump();
        });
    expect(result(), isEmpty);
    expect(host.grantedPermissions(_id), isEmpty);
  });

  testWidgets('a capability the package never declared is not offered',
      (tester) async {
    // note:write is a real runtime capability the package never declares.
    await open(tester,
        capabilities: ['note:write', 'ai:invoke'],
        answer: (tester) async {
          expect(find.byType(CheckboxListTile), findsOneWidget);
          await tester.tap(find.text('Deny'));
          await tester.pump();
        });
  });

  testWidgets('an install-tier capability opens no sheet', (tester) async {
    final result = await open(tester,
        capabilities: ['script:run'],
        answer: (tester) async {
          // Nothing is runtime-tier and undeclared, so there is nothing to ask.
          expect(find.text('Plugin permission request'), findsNothing);
        });
    expect(result(), isEmpty);
  });

}
