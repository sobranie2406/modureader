import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> asked;
  late PluginHostServices services;

  PluginHostApi api({
    PluginHostServices? overrides,
    int maxResults = 50,
  }) =>
      PluginHostApi(
        pluginId: 'com.example.host-api',
        services: overrides ?? services,
        maxResults: maxResults,
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
      await expectLater(
          api().call('library.list', {'limit': 0}), denied());
      await expectLater(
          api().call('library.list', {'limit': 500}), denied());
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
      await expectLater(
          bare.call('clipboard.write', {'text': 'x'}), denied());
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
        await expectLater(
            api().call('open.url', {'url': url}), denied(),
            reason: url);
      }
      expect(asked, isEmpty);
    });

    test('an ordinary web URL is opened', () async {
      expect(
          await api()
              .call('open.url', {'url': 'https://example.com/page?q=1'}),
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
      expect(
          await api().call('ui.prompt', {'title': 'Name', 'message': ''}),
          {'text': 'typed'});
    });

    test('select refuses an empty option list', () async {
      await expectLater(
          api().call('ui.select', {'title': 'Pick', 'options': []}), denied());
      await expectLater(
          api().call('ui.select', {'title': 'Pick', 'options': ['', 'b']}),
          denied());
    });

    test('select returns the first option', () async {
      expect(
          await api()
              .call('ui.select', {'title': 'Pick', 'options': ['a', 'b']}),
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

  group('reader-bound methods', () {
    test('without a reader they report permission', () async {
      await expectLater(api().call('books.content', {}), denied());
      await expectLater(
          api().call('books.chapter', {'href': 'ch1.xhtml'}), denied());
    });

    test('an unknown method is refused', () async {
      await expectLater(api().call('made.up', {}), denied());
    });
  });
}
