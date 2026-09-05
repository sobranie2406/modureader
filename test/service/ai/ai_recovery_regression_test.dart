// Permanent regressions promoted from the September 5 QA probes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain/langchain.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.directory);
  final Directory directory;
  @override
  Future<String?> getApplicationCachePath() async => directory.path;
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '${directory.path}/data';
  @override
  Future<String?> getApplicationSupportPath() async => '${directory.path}/data';
}

class _ControlledModel extends FakeChatModel {
  _ControlledModel() : super(responses: const ['unused']) {
    source = StreamController<ChatResult>(onCancel: () => cancelled = true);
  }
  late final StreamController<ChatResult> source;
  bool cancelled = false;
  int closeCount = 0;

  @override
  void close() {
    closeCount++;
    super.close();
  }

  @override
  Stream<ChatResult> stream(PromptValue input,
          {FakeChatModelOptions? options}) =>
      source.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('history writes', () {
    late Directory directory;
    late PathProviderPlatform oldPaths;
    AiChatHistoryEntry entry(String id, {String scope = 'reader'}) =>
        AiChatHistoryEntry(
            id: id,
            scope: scope,
            serviceId: 'fixture',
            model: 'fixture',
            createdAt: 1,
            updatedAt: 1,
            messages: [ChatMessage.humanText(id)],
            completed: true);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      directory =
          await Directory.systemTemp.createTemp('modu-history-regression-');
      oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TemporaryPaths(directory);
    });
    tearDown(() async {
      PathProviderPlatform.instance = oldPaths;
      await directory.delete(recursive: true);
    });

    test('truncated source survives reads and is backed up before repair',
        () async {
      final file = File('${directory.path}/ai_history.json');
      const damaged = '[{"id":"truncated"';
      await file.writeAsString(damaged);
      expect(await AiHistoryStore.readHistory(), isEmpty);
      expect(await file.readAsString(), damaged);
      await AiHistoryStore.upsertEntry(entry('new'));
      final backups = await directory
          .list(recursive: true)
          .where((f) => f.path.contains('.corrupt-'))
          .toList();
      expect(backups, hasLength(1));
      expect(await File(backups.single.path).readAsString(), damaged);
      expect((await AiHistoryStore.readHistory()).single.id, 'new');
    });

    test('concurrent updates do not overwrite other sessions', () async {
      await Future.wait(
          List.generate(20, (i) => AiHistoryStore.upsertEntry(entry('$i'))));
      expect((await AiHistoryStore.readHistory()).map((e) => e.id).toSet(),
          List.generate(20, (i) => '$i').toSet());
      expect(
          await File('${directory.path}/data/ai/ai_history.json.tmp').exists(),
          isFalse);
    });

    test('clearing reader history preserves library sessions', () async {
      await AiHistoryStore.upsertEntry(entry('reader'));
      await AiHistoryStore.upsertEntry(entry('home', scope: 'library'));
      await Future.wait([
        AiHistoryStore.clearScope('reader'),
        AiHistoryStore.upsertEntry(entry('new-reader'))
      ]);
      expect((await AiHistoryStore.readHistory()).map((e) => e.id).toSet(),
          {'home', 'new-reader'});
    });

    test(
        'cache limits cannot discard conversations or resurrect cleared legacy history',
        () async {
      Prefs().maxAiCacheCount = 1;
      final legacy = File('${directory.path}/ai_history.json');
      await legacy.writeAsString(jsonEncode([entry('legacy').toJson()]));
      await AiHistoryStore.upsertEntry(entry('one'));
      await AiHistoryStore.upsertEntry(entry('two'));
      expect(await AiHistoryStore.readHistory(), hasLength(3));
      expect(await File('${directory.path}/data/ai/ai_history.json').exists(),
          isTrue);
      await AiHistoryStore.clear();
      expect(await legacy.exists(), isTrue);
      expect(await AiHistoryStore.readHistory(), isEmpty);
    });
  });

  test('agent cancellation stops a silent transport without affecting siblings',
      () async {
    final runner = CancelableLangchainRunner();
    final agent = _ControlledModel();
    final sibling = _ControlledModel();
    final a = runner
        .streamAgent(model: agent, tools: [], history: [], input: 'fixture')
        .listen((_) {});
    final b = runner
        .stream(model: sibling, prompt: PromptValue.string('fixture'))
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await a.cancel().timeout(const Duration(seconds: 1));
    expect(agent.cancelled, isTrue);
    expect(agent.closeCount, 1);
    expect(sibling.cancelled, isFalse);
    await b.cancel();
    unawaited(agent.source.close());
    unawaited(sibling.source.close());
  });

  test('request cancellation terminates an active silent agent', () async {
    final runner = CancelableLangchainRunner();
    final model = _ControlledModel();
    final done = runner
        .streamAgent(model: model, tools: [], history: [], input: 'fixture')
        .drain<void>();
    await Future<void>.delayed(Duration.zero);
    await runner.cancel().timeout(const Duration(seconds: 1));
    await done.timeout(const Duration(seconds: 1));
    expect(model.cancelled, isTrue);
    expect(model.closeCount, 1);
    unawaited(model.source.close());
  });

  test('one malformed history record must not delete all saved conversations',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final directory =
        await Directory.systemTemp.createTemp('modu-history-probe-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(directory);
    addTearDown(() async {
      PathProviderPlatform.instance = oldPaths;
      await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/ai_history.json');
    final valid = AiChatHistoryEntry(
      id: 'valid-fixture',
      scope: 'reader',
      serviceId: 'fake',
      model: 'fake',
      createdAt: 1,
      updatedAt: 1,
      completed: true,
      messages: [ChatMessage.humanText('fixture question')],
    ).toJson();
    final malformed = {
      ...valid,
      'id': 'malformed-fixture',
      'messages': [
        {'type': 'unknown-message-type', 'content': 'fixture'}
      ]
    };
    await file.writeAsString(jsonEncode([valid, malformed]));
    final restored = await AiHistoryStore.readHistory();
    final stillExists = await file.exists();
    expect(stillExists, isTrue,
        reason: 'Reading history must not erase its source file');
    expect(restored.map((entry) => entry.id), contains('valid-fixture'));
  });

  test('cancelling one model stream must not cancel a concurrent request',
      () async {
    final runner = CancelableLangchainRunner();
    final first = _ControlledModel();
    final second = _ControlledModel();
    final prompt = PromptValue.string('fixture');
    final firstSubscription =
        runner.stream(model: first, prompt: prompt).listen((_) {});
    final secondSubscription =
        runner.stream(model: second, prompt: prompt).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    addTearDown(() async {
      unawaited(first.source.close());
      unawaited(second.source.close());
      await secondSubscription
          .cancel()
          .timeout(const Duration(seconds: 1), onTimeout: () {});
    });
    await firstSubscription
        .cancel()
        .timeout(const Duration(seconds: 1), onTimeout: () {});
    expect(second.cancelled, isFalse,
        reason: 'The second request must keep running');
    expect(first.cancelled, isTrue,
        reason: 'The cancelled request must stop its own transport');
  });
}
