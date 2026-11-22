import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> asked;
  late PluginHostServices services;

  PluginHostApi api({
    PluginHostServices? overrides,
    int maxResults = 50,
    Directory? storageRoot,
  }) =>
      PluginHostApi(
        pluginId: 'com.example.host-api',
        services: overrides ?? services,
        maxResults: maxResults,
        storageRoot: storageRoot,
      );

  setUp(() {
    asked = [];
    services = PluginHostServices(
      copyToClipboard: (text) async => asked.add('clipboard:$text'),
      readClipboard: () async => 'pasted',
      shareText: (text, subject) async => asked.add('share:$text'),
      openUrl: (uri) async {
        asked.add('open:$uri');
        return true;
      },
      askConfirm: (title, message) async {
        asked.add('confirm:$title');
        return true;
      },
      askPrompt: (title, message, initial) async {
        asked.add('prompt:$title');
        return 'typed';
      },
      askSelect: (title, options) async {
        asked.add('select:$title');
        return options.first;
      },
      showProgress: (label, fraction) async =>
          asked.add('progress:$label:$fraction'),
    );
  });

  Matcher denied() => throwsA(
      isA<PluginScriptFailure>().having((e) => e.code, 'code', 'permission'));

  group('argument validation', () {
    test('an unknown argument is refused rather than ignored', () async {
      await expectLater(
          api().call('clipboard.write', {'text': 'hi', 'extra': 1}), denied());
      expect(asked, isEmpty);
    });

    test('a missing required argument is refused', () async {
      await expectLater(api().call('clipboard.write', {}), denied());
    });

    test('an over-long string is refused', () async {
      await expectLater(
          api().call('clipboard.write', {'text': 'x' * 9000}), denied());
    });

    test('a wrong-typed integer is refused', () async {
      await expectLater(
          api().call('library.list', {'limit': 'many'}), denied());
    });

    test('an out-of-range integer is refused', () async {
      await expectLater(api().call('library.list', {'limit': 0}), denied());
      await expectLater(api().call('library.list', {'limit': 500}), denied());
    });
  });

  group('clipboard', () {
    test('write passes the text to the host', () async {
      expect(await api().call('clipboard.write', {'text': 'copied'}),
          {'written': true});
      expect(asked, ['clipboard:copied']);
    });

    test('read returns what the platform gave', () async {
      expect(await api().call('clipboard.read', {}), {'text': 'pasted'});
    });

    test('read with an argument is refused', () async {
      await expectLater(
          api().call('clipboard.read', {'quiet': true}), denied());
    });

    test('a missing native surface reports permission, not a crash', () async {
      final bare = api(overrides: const PluginHostServices());
      await expectLater(bare.call('clipboard.write', {'text': 'x'}), denied());
    });
  });

  group('share and links', () {
    test('share passes text and subject', () async {
      expect(
          await api()
              .call('share.text', {'text': 'hello', 'subject': 'greeting'}),
          {'shared': true});
      expect(asked, ['share:hello']);
    });

    test('a non-web URL is refused', () async {
      for (final url in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'intent://scan#Intent;end',
        'https://user:pass@example.com/',
        'not a url',
      ]) {
        await expectLater(api().call('open.url', {'url': url}), denied(),
            reason: url);
      }
      expect(asked, isEmpty);
    });

    test('an ordinary web URL is opened', () async {
      expect(
          await api().call('open.url', {'url': 'https://example.com/page?q=1'}),
          {'opened': true});
      expect(asked, ['open:https://example.com/page?q=1']);
    });
  });

  group('dialogs', () {
    test('confirm returns the answer', () async {
      expect(
          await api().call('ui.confirm', {'title': 'Sure?', 'message': 'Go'}),
          {'confirmed': true});
      expect(asked, ['confirm:Sure?']);
    });

    test('prompt returns what was typed', () async {
      expect(await api().call('ui.prompt', {'title': 'Name', 'message': ''}),
          {'text': 'typed'});
    });

    test('select refuses an empty option list', () async {
      await expectLater(
          api().call('ui.select', {'title': 'Pick', 'options': []}), denied());
      await expectLater(
          api().call('ui.select', {
            'title': 'Pick',
            'options': ['', 'b']
          }),
          denied());
    });

    test('select returns the first option', () async {
      expect(
          await api().call('ui.select', {
            'title': 'Pick',
            'options': ['a', 'b']
          }),
          {'selected': 'a'});
    });

    test('progress refuses a fraction outside 0..1', () async {
      for (final fraction in [-0.1, 1.1]) {
        await expectLater(
            api().call('ui.progress', {'label': 'x', 'fraction': fraction}),
            denied());
      }
    });

    test('progress forwards a valid fraction', () async {
      expect(
          await api().call('ui.progress', {'label': 'Load', 'fraction': 0.5}),
          {'shown': true});
      expect(asked, ['progress:Load:0.5']);
    });
  });

  group('AI answers', () {
    test('the answer is the last emission, not every prefix of it', () {
      // aiGenerateStream re-sends the whole answer on every event, so appending
      // the events repeats the answer with each prefix. A plugin's "save as
      // note" dialog once showed
      // "一句话结论一句话结论：“一句话结论：…" because of it.
      expect(
          PluginHostApi.aiAnswerFromEmissions(const [
            '一句话结论',
            '一句话结论：日语',
            '一句话结论：日语是一门语言。',
          ]),
          '一句话结论：日语是一门语言。');
    });

    test('reasoning is stripped before the plugin sees the answer', () {
      expect(
          PluginHostApi.aiAnswerFromEmissions(
              const ['<think>先想一想</think>\n答案在这里']),
          '答案在这里');
    });

    test('an oversized answer is truncated, not rejected', () {
      final answer = PluginHostApi.aiAnswerFromEmissions(['x' * 40000]);
      expect(answer.length, 32000);
    });

    test('an empty answer stays empty so the caller can report it', () {
      expect(PluginHostApi.aiAnswerFromEmissions(const []), isEmpty);
      expect(PluginHostApi.aiAnswerFromEmissions(const ['<think>只有思考</think>']),
          isEmpty);
    });
  });

  group('plugin storage', () {
    late Directory storageRoot;
    PluginHostApi storageApi() => api(storageRoot: storageRoot);

    setUp(() {
      storageRoot = Directory.systemTemp.createTempSync('modu-api-storage');
    });

    tearDown(() {
      if (storageRoot.existsSync()) storageRoot.deleteSync(recursive: true);
    });

    test('a name that escapes the plugin directory is refused', () async {
      for (final name in [
        '../escape.json',
        'sub/dir.json',
        'no-extension',
        '.hidden.json',
        'a' * 100 + '.json',
      ]) {
        await expectLater(
            storageApi().call('storage.write', {'name': name, 'text': 'x'}),
            denied(),
            reason: name);
        await expectLater(
            storageApi().call('storage.read', {'name': name}), denied(),
            reason: name);
      }
    });

    test('storage methods reject unexpected arguments', () async {
      await expectLater(
          storageApi().call('storage.list', {'path': '/'}), denied());
      await expectLater(
          storageApi().call('storage.read', {'file': 'a.json'}), denied());
    });

    test('overwriting an owned file still works at the file limit', () async {
      // Fill the quota through the API so the test exercises the same path the
      // plugin does, then update one of those files.
      for (var index = 0; index < 200; index++) {
        await storageApi()
            .call('storage.write', {'name': 'f$index.json', 'text': 'x'});
      }
      expect(
          await storageApi()
              .call('storage.write', {'name': 'f0.json', 'text': 'new'}),
          {'bytes': 3});
      expect(await storageApi().call('storage.read', {'name': 'f0.json'}),
          {'text': 'new'});
    });

    test('writing more than the file limit is refused', () async {
      await expectLater(
          storageApi()
              .call('storage.write', {'name': 'a.json', 'text': 'x' * 300000}),
          denied());
    });

    test('writes measure UTF-8 bytes in the chosen host directory', () async {
      expect(
          await storageApi()
              .call('storage.write', {'name': 'a.json', 'text': '默读'}),
          {'bytes': 6});
      expect(await File('${storageRoot.path}/a.json').readAsString(), '默读');
      await expectLater(
          storageApi()
              .call('storage.write', {'name': 'b.json', 'text': '读' * 90000}),
          throwsA(isA<PluginScriptFailure>()
              .having((e) => e.code, 'code', 'size')));
    });
  });

  group('runtime permissions', () {
    test('request returns the grants the user actually made', () async {
      final call = <String, Object>{};
      final service = api(
        overrides: PluginHostServices(
          requestPermissions: (id, capabilities, reason) async {
            call['id'] = id;
            call['capabilities'] = capabilities;
            call['reason'] = reason;
            // The user allowed one of the two.
            return {capabilities.first};
          },
          grantedPermissions: (_) async => {'ai:invoke'},
        ),
      );
      expect(
          await service.call('permissions.request', {
            'capabilities': ['ai:invoke', 'clipboard:read'],
            'reason': 'Needs to summarise the chapter',
          }),
          {
            'granted': ['ai:invoke'],
            'denied': ['clipboard:read'],
          });
      expect(call['id'], 'com.example.host-api');
      expect(call['capabilities'], ['ai:invoke', 'clipboard:read']);
      expect(call['reason'], 'Needs to summarise the chapter');
    });

    test('the reason is optional and bounded', () async {
      String? seen = 'unset';
      final service = api(
        overrides: PluginHostServices(
          requestPermissions: (_, capabilities, reason) async {
            seen = reason;
            return <String>{};
          },
          grantedPermissions: (_) async => <String>{},
        ),
      );
      await service.call('permissions.request', {
        'capabilities': ['ai:invoke'],
      });
      expect(seen, '');
      await expectLater(
          service.call('permissions.request', {
            'capabilities': ['ai:invoke'],
            'reason': 'x' * 400,
          }),
          denied());
    });

    test('an install-tier or unknown capability cannot be requested', () async {
      var asked = 0;
      final service = api(
        overrides: PluginHostServices(
          requestPermissions: (_, capabilities, reason) async {
            asked++;
            return <String>{};
          },
          grantedPermissions: (_) async => <String>{},
        ),
      );
      for (final capability in ['script:run', 'made:up', 42]) {
        await expectLater(
            service.call('permissions.request', {
              'capabilities': [capability],
            }),
            denied(),
            reason: '$capability');
      }
      expect(asked, 0);
    });

    test('a malformed capability list is refused without opening the sheet',
        () async {
      var asked = 0;
      final service = api(
        overrides: PluginHostServices(
          requestPermissions: (_, capabilities, reason) async {
            asked++;
            return <String>{};
          },
          grantedPermissions: (_) async => <String>{},
        ),
      );
      for (final raw in [
        null,
        'ai:invoke',
        <Object>[],
        ['a' * 200]
      ]) {
        await expectLater(
            service.call('permissions.request', {'capabilities': raw}),
            denied(),
            reason: '$raw');
      }
      expect(asked, 0);
    });

    test('duplicate requests are collapsed before the user sees them',
        () async {
      List<String>? seen;
      final service = api(
        overrides: PluginHostServices(
          requestPermissions: (_, capabilities, reason) async {
            seen = capabilities;
            return capabilities.toSet();
          },
          grantedPermissions: (_) async => <String>{},
        ),
      );
      final result = await service.call('permissions.request', {
        'capabilities': ['ai:invoke', 'ai:invoke'],
      });
      expect(seen, ['ai:invoke']);
      expect(result, {
        'granted': ['ai:invoke'],
        'denied': <String>[],
      });
    });

    test('status reports the grants in force', () async {
      final service = api(
        overrides: PluginHostServices(
          requestPermissions: (id, capabilities, reason) async =>
              const <String>{},
          grantedPermissions: (_) async => {'note:read', 'ai:invoke'},
        ),
      );
      expect(await service.call('permissions.status', {}), {
        'granted': ['ai:invoke', 'note:read']
      });
    });

    test('without the native surface the calls report permission', () async {
      final bare = api(overrides: const PluginHostServices());
      await expectLater(
          bare.call('permissions.request', {
            'capabilities': ['ai:invoke']
          }),
          denied());
      await expectLater(bare.call('permissions.status', {}), denied());
    });
  });

  group('reader-bound methods', () {
    test('without a reader they report permission', () async {
      await expectLater(api().call('books.content', {}), denied());
      await expectLater(
          api().call('books.chapter', {'href': 'ch1.xhtml'}), denied());
    });

    test('chapter requests stay on the reader and pass the requested bound',
        () async {
      final result = await api(
          overrides: PluginHostServices(
        reader: PluginReaderSnapshot(
          book: Book.mock().copyWith(id: 11),
          chapter: 'Chapter 2',
          chapterByHref: (href, {maxCharacters}) async {
            expect(href, 'ch2.xhtml');
            expect(maxCharacters, 4);
            return 'chapter';
          },
        ),
      )).call('books.chapter', {'href': 'ch2.xhtml', 'maxCharacters': 4});
      expect(result, {'bookId': 11, 'href': 'ch2.xhtml', 'text': 'chap'});
    });

    test('an unknown method is refused', () async {
      await expectLater(api().call('made.up', {}), denied());
    });
  });
}
