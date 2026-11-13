import 'package:modu_reader/service/dictionary/dictionary_preferences.dart';
import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:modu_reader/widgets/dictionary/dictionary_sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'local selections persist before closing, barrier dismissal reports changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      dictionaryPreferencesKey: ['local:*', 'online:plugin:example:dictionary'],
    });
    bool? changed;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      changed = await showDictionarySources(context, const [
                        LocalDictionary('a', 'Dictionary A', 'MDX', 2, true),
                        LocalDictionary('b', 'Dictionary B', 'MDX', 2, true),
                      ]);
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dictionary A'));
    await tester.pumpAndSettle();
    expect((await DictionaryPreferences.load()).localIds, {'b'});
    expect((await DictionaryPreferences.load()).online, isEmpty);
    expect((await DictionaryPreferences.load()).unknownTokens,
        {'online:plugin:example:dictionary'});
    expect(find.text('Apply'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(changed, true);
    expect((await DictionaryPreferences.load()).localIds, {'b'});
    expect(tester.takeException(), isNull);
  });
}
