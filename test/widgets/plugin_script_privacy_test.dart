import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/widgets/plugins/plugin_script_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Host extends PluginHost {
  _Host() : super(paths: PluginPaths(rootPath: '/tmp/modu_script_privacy'));
  @override
  bool isScriptRunnable(String id) => true;
}

class _Runtime extends PluginScriptRuntime {
  _Runtime(PluginHost host) : super(host: host);
  late Completer<Map<String, dynamic>> result;
  PluginHostCall? call;
  bool Function()? contextValid;
  bool running = false;
  final cancelled = <String>[];
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
    result = Completer<Map<String, dynamic>>();
    call = hostCall;
    contextValid = isContextValid;
    return result.future.whenComplete(() {
      running = false;
    });
  }

  @override
  void cancelPlugin(String id) {
    cancelled.add(id);
    running = false;
  }
}

class _LockOnPopup extends NavigatorObserver {
  _LockOnPopup(this.lock);
  final VoidCallback lock;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) lock();
  }
}

void main() {
  late PrivateLibrary privacy;
  late _Host host;
  late _Runtime runtime;
  late Book secret, public;
  Future<void>? task;
  var finished = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    privacy = PrivateLibrary(preferences: Prefs().prefs)..setPluginActive(true);
    await privacy.unlock();
    secret = Book.mock().copyWith(
        id: 1, title: 'PRIVATE SECRET TITLE', filePath: 'private.epub');
    public = Book.mock()
        .copyWith(id: 2, title: 'Public book', filePath: 'public.epub');
    await privacy.setBooksPrivate([secret], true);
    host = _Host();
    runtime = _Runtime(host);
    task = null;
    finished = false;
  });
  tearDown(() {
    runtime.dispose();
    host.dispose();
    privacy.dispose();
  });

  final action = ScriptActionContribution.parse(
      kind: kScriptActionContributionKind,
      schema: 1,
      id: 'list',
      index: 0,
      raw: {'name': 'List books', 'surface': 'library', 'entry': 'main.js'});
  const plugin = 'com.example.library-reader';
  const textKey = ValueKey('other-menu');
  BuildContext? owner;
  Future<void> show(WidgetTester tester,
      {bool lockOnPush = false, List<Book>? books}) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        navigatorObservers: lockOnPush ? [_LockOnPopup(privacy.lock)] : [],
        home: Scaffold(body: Builder(builder: (context) {
          owner = context;
          return TextButton(
              onPressed: () {
                task = runPluginAction(context,
                    pluginId: plugin,
                    action: action,
                    scriptRuntime: runtime,
                    privateLibrary: privacy,
                    selectBooks: () async => books ?? [secret]);
                unawaited(task!.then((_) {
                  finished = true;
                }));
              },
              child: const Text('Run'));
        }))));
    await tester.tap(find.text('Run'));
    await tester.pump();
    expect(runtime.call, isNotNull);
  }

  Future<void> complete(WidgetTester tester, String text) async {
    runtime.result.complete({'title': 'Plugin result', 'text': text});
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a library action that received a private title is cancelled on lock and cannot return late',
      (tester) async {
    await show(tester);
    final rows = await runtime.call!('library.list', {}) as List;
    expect((rows.single as Map)['title'], secret.title);
    expect(runtime.contextValid!(), isTrue);
    privacy.lock();
    expect(runtime.cancelled, [plugin]);
    expect(runtime.contextValid!(), isFalse);
    await tester.runAsync(() => privacy.unlock());
    expect(runtime.contextValid!(), isFalse,
        reason: 'unlocking cannot revive the old private job');
    await complete(tester, secret.title);
    expect(find.text(secret.title, skipOffstage: false), findsNothing);
    expect(find.byType(SelectableText, skipOffstage: false), findsNothing);
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locking removes an already shown private result immediately',
      (tester) async {
    await show(tester);
    await runtime.call!('library.list', {});
    await complete(tester, secret.title);
    expect(find.text(secret.title), findsOneWidget);
    privacy.lock();
    await tester.pump();
    expect(find.text(secret.title, skipOffstage: false), findsNothing);
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(runtime.cancelled, [plugin]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'only the private result route is removed while another menu stays open',
      (tester) async {
    await show(tester);
    await runtime.call!('library.list', {});
    await complete(tester, secret.title);
    unawaited(showDialog<void>(
        context: owner!,
        builder: (_) =>
            const AlertDialog(content: Text('Other menu', key: textKey))));
    await tester.pumpAndSettle();
    privacy.lock();
    await tester.pump();
    expect(find.text(secret.title, skipOffstage: false), findsNothing);
    expect(find.byKey(textKey), findsOneWidget);
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    Navigator.of(owner!).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a lock during popup push prevents the private text from building for its first frame',
      (tester) async {
    await show(tester, lockOnPush: true);
    await runtime.call!('library.list', {});
    runtime.result.complete({'text': secret.title});
    await tester.pump();
    expect(find.text(secret.title, skipOffstage: false), findsNothing);
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(privacy.unlocked, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'private books outside the returned page do not taint a public result',
      (tester) async {
    await show(tester, books: [public, secret]);
    final rows = await runtime.call!('library.list', {'limit': 1}) as List;
    expect((rows.single as Map)['title'], public.title);
    await complete(tester, public.title);
    privacy.lock();
    await tester.pumpAndSettle();
    expect(find.text(public.title), findsOneWidget);
    expect(runtime.cancelled, isEmpty);
    expect(runtime.contextValid!(), isTrue);
    Navigator.of(owner!).pop();
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a public-only running action is not cancelled when privacy locks',
      (tester) async {
    await show(tester, books: [public]);
    await runtime.call!('library.list', {});
    privacy.lock();
    expect(runtime.cancelled, isEmpty);
    expect(runtime.contextValid!(), isTrue);
    await complete(tester, public.title);
    expect(find.text(public.title), findsOneWidget);
    Navigator.of(owner!).pop();
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('a library read begun while locked returns only public books',
      (tester) async {
    privacy.lock();
    await show(tester, books: [secret, public]);
    final rows = await runtime.call!('library.list', {}) as List;
    expect(rows, hasLength(1));
    expect((rows.single as Map)['title'], public.title);
    await complete(tester, public.title);
    Navigator.of(owner!).pop();
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  for (final displayed in [false, true]) {
    testWidgets(
        'a returned public book later marked private clears the ${displayed ? 'displayed' : 'pending'} result on lock',
        (tester) async {
      await show(tester, books: [public]);
      final rows = await runtime.call!('library.list', {}) as List;
      expect((rows.single as Map)['title'], public.title);
      if (displayed) {
        await complete(tester, public.title);
        expect(find.text(public.title), findsOneWidget);
      }
      await tester.runAsync(() => privacy.setBooksPrivate([public], true));
      expect(privacy.isPrivate(public), isTrue);
      expect(runtime.cancelled, isEmpty);
      privacy.lock();
      expect(runtime.cancelled, [plugin]);
      expect(runtime.contextValid!(), isFalse);
      if (displayed) {
        await tester.pump();
      } else {
        await complete(tester, public.title);
      }
      expect(find.text(public.title, skipOffstage: false), findsNothing);
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'marking a book outside the returned page private does not clear a public result',
      (tester) async {
    final other =
        public.copyWith(id: 3, title: 'Other book', filePath: 'other.epub');
    await show(tester, books: [public, other]);
    final rows = await runtime.call!('library.list', {'limit': 1}) as List;
    expect((rows.single as Map)['title'], public.title);
    await complete(tester, public.title);
    await tester.runAsync(() => privacy.setBooksPrivate([other], true));
    privacy.lock();
    await tester.pumpAndSettle();
    expect(find.text(public.title), findsOneWidget);
    expect(runtime.cancelled, isEmpty);
    expect(runtime.contextValid!(), isTrue);
    Navigator.of(owner!).pop();
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });
}
