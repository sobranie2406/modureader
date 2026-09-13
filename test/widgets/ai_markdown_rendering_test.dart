import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('invalid stored AI sizes fall back without a cast error', () async {
    for (final value in <Object>[100, -1, '24', double.nan, double.infinity]) {
      SharedPreferences.setMockInitialValues({'aiChatFontSize': value});
      await Prefs().initPrefs();
      expect(Prefs().aiChatFontSize, 14);
    }
    for (final value in [10, 14, 24]) {
      SharedPreferences.setMockInitialValues({'aiChatFontSize': value});
      await Prefs().initPrefs();
      expect(Prefs().aiChatFontSize, value.toDouble());
    }
    Prefs().aiChatFontSize = double.nan;
    expect(Prefs().aiChatFontSize, 14);
  });

  testWidgets(
      'headings and list body use AI size and retain accessibility scaling',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
      child: const Scaffold(
          body: SingleChildScrollView(
              child: StyledMarkdown(
                  data:
                      '# Heading\n\n1. **Summary**: ordinary body\n\n## Second',
                  fontSize: 14))),
    )));
    final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
    final context = tester.element(find.byType(GptMarkdown));
    expect(markdown.style!.fontSize, 14);
    expect(GptMarkdownTheme.of(context).h1!.fontSize, 18);
    expect(GptMarkdownTheme.of(context).h2!.fontSize, 17);
    expect(MediaQuery.textScalerOf(context).scale(14), closeTo(25.2, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unchanged Markdown subtree is reused, content and style changes invalidate it',
      (tester) async {
    late StateSetter update;
    var text = 'Existing answer';
    var size = 14.0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return StyledMarkdown(data: text, fontSize: size);
    }))));
    final original = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
    update(() {});
    await tester.pump();
    expect(
        tester.widget<GptMarkdown>(find.byType(GptMarkdown)), same(original));
    update(() => text += ' more');
    await tester.pump();
    final changed = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
    expect(changed, isNot(same(original)));
    expect(changed.data, 'Existing answer more');
    update(() => size = 10);
    await tester.pump();
    expect(tester.widget<GptMarkdown>(find.byType(GptMarkdown)).style!.fontSize,
        10);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'theme changes invalidate cache and nonselectable output omits selection region',
      (tester) async {
    late StateSetter update;
    var dark = false;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      update = setState;
      return MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: const Scaffold(
              body: StyledMarkdown(
                  data: '**Answer**', fontSize: 14, selectable: false)));
    }));
    final original = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
    update(() => dark = true);
    await tester.pumpAndSettle();
    final changed = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
    expect(changed, isNot(same(original)));
    expect(changed.style!.color, isNot(original.style!.color));
    expect(find.byType(SelectableRegion), findsNothing);
  });
}
