import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_common.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    for (final locale in appLocales) {
      await L10n.delegate.load(locale);
    }
  });
  for (final locale in appLocales) {
    testWidgets('$locale templates preserve user names and dictionary errors',
        (tester) async {
      late String deletion, progress, error;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: appLocales,
        localeListResolutionCallback: resolveAppLocale,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Builder(builder: (context) {
          deletion = ModuStrings.format(
              context,
              '仅删除默读中的“{name}”及其查询索引，不删除原始字典文件。',
              'Remove “{name}” and its lookup index from Modu only. Original source files are not deleted.',
              values: {'name': 'My 字典 {count}'});
          progress = ModuStrings.format(context, '正在处理字典，已导入 {count} 条…',
              'Processing dictionary: {count} entries…',
              values: {'count': 239685});
          error = dictionaryError(context, const DictionaryFailure('empty'));
          return Text('$deletion\n$progress\n$error');
        }),
      ));
      await tester.pumpAndSettle();
      expect(deletion, contains('My 字典 {count}'));
      expect(deletion, isNot(contains('{name}')));
      expect(progress, contains('239685'));
      expect(progress, isNot(contains('{count}')));
      if (!['zh', 'en'].contains(locale.languageCode)) {
        expect(error, isNot('Dictionary has no entries.'));
        expect(error, isNot('字典没有可查询的词条。'));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
