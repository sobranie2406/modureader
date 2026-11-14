import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_dictionary_transform.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';

class _Runtime extends PluginScriptRuntime {
  final inputs = <Map<String, Object?>>[];
  final cancelled = <String>[];
  final running = <String>{};
  Map<String, dynamic> result = {
    'candidates': ['apple']
  };
  Completer<Map<String, dynamic>>? delayed;
  bool fail = false, busy = false;
  @override
  bool isRunning(String id) => busy || running.contains(id);
  @override
  Future<Map<String, dynamic>> run(
      {required String pluginId,
      required ScriptActionContribution action,
      Map<String, Object?> input = const {},
      PluginHostCall? hostCall,
      bool Function()? isContextValid}) {
    inputs.add(input);
    running.add(pluginId);
    expect(hostCall, isNull);
    final Future<Map<String, dynamic>> response = fail
        ? Future.error(const PluginScriptFailure('timeout'))
        : delayed?.future ?? Future.value(result);
    return response.whenComplete(() => running.remove(pluginId));
  }

  @override
  void cancelPlugin(String id) => cancelled.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Runtime runtime;
  late PluginScriptActionRegistry registry;
  late PluginDictionaryTransform transforms;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    runtime = _Runtime();
    registry = PluginScriptActionRegistry();
    transforms =
        PluginDictionaryTransform(runtime: runtime, registry: registry);
  });
  tearDown(() {
    transforms.cancel();
    runtime.dispose();
    registry.dispose();
  });
  void register([String plugin = 'com.example.forms']) {
    registry.replacePlugin(plugin, [
      ScriptActionContribution.parse(
          kind: kScriptActionContributionKind,
          schema: 1,
          id: 'forms',
          index: 0,
          raw: {'entry': 'main.js', 'surface': 'dictionary', 'name': 'Forms'})
    ]);
  }

  Future<List<String>> candidates() =>
      transforms.candidates('apples', isContextValid: () => true);

  test('no contribution or disabled plugins never create or call an engine',
      () async {
    expect(await candidates(), isEmpty);
    expect(
        await PluginDictionaryTransform(registry: registry)
            .candidates('apples', isContextValid: () => true),
        isEmpty);
    register();
    await Prefs().prefs.setBool('experimentalPluginsEnabled', false);
    expect(await candidates(), isEmpty);
    expect(runtime.inputs, isEmpty);
  });
  test('candidate text is bounded, deduplicated and receives only the query',
      () async {
    register();
    runtime.result = {
      'candidates': [
        'apples',
        ' apple ',
        'apple',
        'approve',
        '',
        4,
        'a\nb',
        'x' * 257
      ]
    };
    expect(await candidates(), ['apple', 'approve']);
    expect(runtime.inputs.single, {'selection': 'apples'});
  });
  test('failed or busy plugins fall back without affecting exact lookup',
      () async {
    register();
    runtime.fail = true;
    expect(await candidates(), isEmpty);
    runtime.fail = false;
    runtime.busy = true;
    expect(await candidates(), isEmpty);
    expect(runtime.inputs, hasLength(1));
  });
  test('rejects an over-budget result and caps combined candidates', () async {
    register();
    runtime.result = {'candidates': List.generate(13, (i) => 'word$i')};
    expect(await candidates(), isEmpty);
    runtime.result = {'candidates': List.generate(12, (i) => 'word$i')};
    register('com.example.second');
    expect(await candidates(), hasLength(12));
  });
  test('a replaced or disposed lookup cancels only its running transform',
      () async {
    register();
    runtime.delayed = Completer<Map<String, dynamic>>();
    final result = candidates();
    expect(runtime.inputs, hasLength(1));
    transforms.cancel();
    runtime.delayed!.complete({
      'candidates': ['apple']
    });
    expect(await result, isEmpty);
    expect(runtime.cancelled, ['com.example.forms']);
  });
  test('a stale context never starts or publishes transformation', () async {
    register();
    expect(await transforms.candidates('apples', isContextValid: () => false),
        isEmpty);
    var current = true;
    runtime.delayed = Completer<Map<String, dynamic>>();
    final result =
        transforms.candidates('apples', isContextValid: () => current);
    current = false;
    runtime.delayed!.complete({
      'candidates': ['apple']
    });
    expect(await result, isEmpty);
    expect(runtime.inputs, hasLength(1));
  });
  test(
      'disabling plugins or removing the contribution discards late candidates',
      () async {
    register();
    runtime.delayed = Completer<Map<String, dynamic>>();
    final disabled = candidates();
    await Prefs().prefs.setBool('experimentalPluginsEnabled', false);
    runtime.delayed!.complete({
      'candidates': ['apple']
    });
    expect(await disabled, isEmpty);
    await Prefs().prefs.setBool('experimentalPluginsEnabled', true);
    runtime.delayed = Completer<Map<String, dynamic>>();
    final removed = candidates();
    registry.replacePlugin('com.example.forms', []);
    runtime.delayed!.complete({
      'candidates': ['apple']
    });
    expect(await removed, isEmpty);
  });
  test(
      'another lookup cannot cancel an already running plugin job it does not own',
      () async {
    register();
    runtime.delayed = Completer<Map<String, dynamic>>();
    final first = candidates();
    final second =
        PluginDictionaryTransform(runtime: runtime, registry: registry);
    expect(await second.candidates('studies', isContextValid: () => true),
        isEmpty);
    second.cancel();
    expect(runtime.cancelled, isEmpty);
    runtime.delayed!.complete({
      'candidates': ['apple']
    });
    expect(await first, ['apple']);
  });
}
