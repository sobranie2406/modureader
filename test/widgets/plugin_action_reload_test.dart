import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/database.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/main.dart' show navigatorKey;
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/plugins/plugin_developer_session.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:modu_reader/widgets/plugins/plugin_script_action.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../service/plugins/plugin_test_utils.dart';
import '../service/sync/row_sync_test.dart' show bookRow;

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Host extends PluginHost {
  _Host()
      : super(paths: PluginPaths(rootPath: '/tmp/modu_native_plugin_action'));
  PluginManifest manifest = createManifest();
  static PluginManifest createManifest() =>
      PluginManifest.parse(manifestJson(id: 'dev.example.notes', capabilities: [
        'script:run',
        'note:write'
      ], contributes: [
        {
          'kind': 'scriptAction',
          'schema': 1,
          'id': 'save',
          'name': 'Save note',
          'entry': 'main.js',
          'surface': 'library'
        }
      ]));
  @override
  PluginManifest? manifestFor(String id) => manifest;
  @override
  bool isScriptRunnable(String id) => true;
  void reload() {
    manifest = createManifest();
    notifyListeners();
  }
}

class _Runtime extends PluginScriptRuntime {
  _Runtime(PluginHost host) : super(host: host);
  final ready = Completer<void>();
  final result = Completer<Map<String, dynamic>>();
  late PluginHostCall call;
  bool running = false;
  @override
  bool isRunning(String id) => running;
  @override
  Future<Map<String, dynamic>> run(
      {required String pluginId,
      required ScriptActionContribution action,
      Map<String, Object?> input = const {},
      PluginHostCall? hostCall,
      bool Function()? isContextValid}) {
    running = true;
    call = hostCall!;
    ready.complete();
    return result.future.whenComplete(() => running = false);
  }

  @override
  void cancelPlugin(String id) {
    running = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sharedPrivacy = PrivateLibrary.instance;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late PathProviderPlatform previousPaths;
  late String previousDocumentPath;
  late Database db;
  late _Host host;
  late _Runtime runtime;
  Future<void>? actionTask;
  setUp(() async {
    await DBHelper.close();
    root = await Directory.systemTemp.createTemp('modu-native-plugin-');
    previousPaths = PathProviderPlatform.instance;
    previousDocumentPath = documentPath;
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    await initBasePath();
    db = await DBHelper().database;
    await db.insert('tb_books', bookRow(1));
    host = _Host();
    runtime = _Runtime(host);
    actionTask = null;
  });
  tearDown(() async {
    runtime.dispose();
    host.dispose();
    await DBHelper.close();
    PathProviderPlatform.instance = previousPaths;
    documentPath = previousDocumentPath;
    await root.delete(recursive: true);
  });
  Future<void> beginSave(
      WidgetTester tester, void Function(Future<Object?>) capture) async {
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () {
                      actionTask = runPluginAction(context,
                          pluginId: host.manifest.id,
                          action: host.manifest.contributions
                              .whereType<ScriptActionContribution>()
                              .single,
                          scriptRuntime: runtime,
                          bookId: 1,
                          selection: 'original selection',
                          cfi: 'epubcfi(/6/2)',
                          chapter: 'chapter');
                    },
                    child: const Text('Run'))))));
    await tester.runAsync(() => tester.tap(find.text('Run')));
    await tester.runAsync(() => runtime.ready.future);
    Future<Object?>? outcome;
    await tester.runAsync(() async {
      outcome = runtime
          .call('notes.save', {'text': 'old job generated note'}).then<Object?>(
              (value) => value,
              onError: (Object e) => e);
    });
    await tester.pumpAndSettle();
    expect(find.text('Save as a note?'), findsOneWidget);
    capture(outcome!);
  }

  testWidgets(
      'old native confirmation cannot save into a reloaded plugin session',
      (tester) async {
    Future<Object?>? outcome;
    // Do not await the native dialog result before interacting with its buttons.
    await beginSave(tester, (future) => outcome = future);
    host.reload();
    runtime.running =
        true; // A same-ID job has already begun in the new session.
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final result = await tester.runAsync(() => outcome!);
    expect(result,
        isA<PluginScriptFailure>().having((e) => e.code, 'code', 'cancelled'));
    expect(await tester.runAsync(() => db.query('tb_notes')), isEmpty);
    runtime.result.complete({'text': ''});
    await tester.pumpAndSettle();
    await tester.runAsync(() => actionTask!);
  });

  testWidgets(
      'a completed worker cannot borrow a later job while its native dialog remains',
      (tester) async {
    Future<Object?>? outcome;
    await beginSave(tester, (future) => outcome = future);
    runtime.result.complete({'text': ''});
    await tester.pumpAndSettle();
    await tester.runAsync(() => actionTask!);
    runtime.running = true; // New job, same action object, no package reload.
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final result = await tester.runAsync(() => outcome!);
    expect(result,
        isA<PluginScriptFailure>().having((e) => e.code, 'code', 'cancelled'));
    expect(await tester.runAsync(() => db.query('tb_notes')), isEmpty);
  });
  testWidgets(
      'global close authenticates once across both private hosts and cancellation preserves both',
      (tester) async {
    Future<void> settleNative() async {
      for (var i = 0; i < 3; i++) {
        await tester.pumpAndSettle();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
      }
      await tester.pumpAndSettle();
    }

    late PluginHost official;
    late PluginDeveloperSession developer;
    addTearDown(() {
      developer.dispose();
      official.dispose();
    });
    final library = sharedPrivacy;
    final book = Book.mock().copyWith(
        id: 1, md5: 'same-content', filePath: 'file/same-content.epub');

    await tester.pump();
    await tester.runAsync(() async {
      official = PluginHost(
          paths: PluginPaths(rootPath: '${root.path}/official'),
          trust: FixturePluginTrust(),
          appVersionResolver: () async => '1.3.10');
      developer = PluginDeveloperSession(
          officialHost: official,
          cacheDirectory: () async =>
              Directory('${root.path}/cache')..createSync(recursive: true));

      await official.initialize();
      Future<File> package(String id) => writePluginZip(root, {
            'manifest.json': manifestJson(id: id, capabilities: [
              'script:run',
              'library:private'
            ], contributes: [
              {
                'kind': 'scriptAction',
                'schema': 1,
                'id': 'open',
                'name': 'Open',
                'surface': 'library',
                'entry': 'main.js'
              }
            ]),
            'main.js': 'return {};'
          });
      await official.install(await package('official.example.private'));
      await developer.setEnabled(true);
      final file = await package('dev.example.private');
      final preview = await developer.preview(file);
      await developer.install(file, expectedSha256: preview.sha256);

      await library.unlock();
      await library.setBooksPrivate([book], true);
      library.lock();
    });

    Future<Object?>? result;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        home: Scaffold(
            body: TextButton(
                onPressed: () {
                  result = official
                      .setExperimentalEnabled(false)
                      .then<Object?>((_) => true, onError: (Object e) => e);
                },
                child: const Text('Close all plugins')))));
    await tester.runAsync(() => tester.tap(find.text('Close all plugins')));
    await settleNative();

    expect(find.text('Unlock private library'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await settleNative();

    expect(await tester.runAsync(() => result!), isA<PluginInstallError>());

    expect(developer.enabled, true);
    expect(official.byId('official.example.private')!.status,
        PluginStatus.enabled);
    expect(Prefs().experimentalPluginsEnabled, true);
    expect(library.isPrivate(book), true);
    await tester.runAsync(() => tester.tap(find.text('Close all plugins')));
    await settleNative();
    await tester.runAsync(() => tester.tap(find.text('Unlock').last));
    await settleNative();

    expect(find.text('Disable private library'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Disable').last));
    await settleNative();

    expect(await tester.runAsync(() => result!), true);

    expect(find.text('Unlock private library'), findsNothing);
    expect(developer.enabled, false);
    expect(Prefs().experimentalPluginsEnabled, false);
    expect(official.byId('official.example.private')!.status,
        PluginStatus.disabled);
    expect(library.hasPrivateBooks, false);
    expect(
        (await tester.runAsync(() => db.query('tb_books')))!.single['id'], 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
