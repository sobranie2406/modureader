import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/utils/color_scheme.dart';
import 'package:modu_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'global messages keep the home overlay after a remote page closes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    late BuildContext home;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      home = context;
      return const Scaffold();
    })));
    AnxToast.init(home);
    await tester.pump();
    Navigator.of(home).push(MaterialPageRoute<void>(
        builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => AnxToast.show('remote', context: context),
                  child: const Text('notify')),
            )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('notify'));
    await tester.pump();
    Navigator.of(home).pop();
    await tester.pumpAndSettle();
    Prefs().readerMenuOpacityPercent = 80;
    AnxToast.show('sync success');
    await tester.pumpAndSettle();
    expect(find.text('sync success'), findsOneWidget);
    final capsule =
        tester.widget<FilledContainer>(find.byType(FilledContainer));
    expect(capsule.fill, isTrue);
    expect(capsule.color!.a, closeTo(.5, .001));
    expect(tester.widget<Text>(find.text('sync success')).style!.color!.a, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('sync success'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final eink in [false, true]) {
    testWidgets('ordinary messages use floating capsule theme; eink=$eink',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      Prefs().eInkMode = eink;
      addTearDown(() => Prefs().eInkMode = false);
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        theme = colorSchema(Prefs(), context, Brightness.light);
        return Theme(data: theme, child: const Scaffold(body: Text('theme')));
      })));
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.shape, isA<StadiumBorder>());
      expect(theme.snackBarTheme.contentTextStyle?.color,
          theme.colorScheme.onSurface);
      expect(theme.snackBarTheme.backgroundColor!.a, closeTo(.5, .001));
      expect(theme.snackBarTheme.elevation, 0);
    }, variant: TargetPlatformVariant.all());

    testWidgets(
        'capsule wraps, replaces old messages and disappears; eink=$eink',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      Prefs().eInkMode = eink;
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() {
        AnxToast.fToast.removeQueuedCustomToasts();
        Prefs().eInkMode = false;
        tester.binding.setSurfaceSize(null);
      });
      Prefs().readerMenuOpacityPercent = 20;
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(cardTheme: const CardThemeData(elevation: 4)),
          home: Builder(builder: (value) {
            context = value;
            return const Scaffold(body: Text('remote library'));
          })));
      AnxToast.show('old message', context: context);
      await tester.pump();
      const message = '已下载并导入本地书架。Downloaded and imported to your bookshelf.';
      AnxToast.show(message, context: context);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('old message'), findsNothing);
      expect(find.text(message), findsOneWidget);
      final background = tester.widget<AnimatedContainer>(find
          .descendant(
              of: find.byType(FilledContainer),
              matching: find.byType(AnimatedContainer))
          .first);
      expect((background.decoration! as ShapeDecoration).color!.a,
          closeTo(.5, .001));
      expect(tester.widget<Text>(find.text(message)).style!.color!.a, 1);
      expect(
          tester.widget<FilledContainer>(find.byType(FilledContainer)).radius,
          1000);
      expect(
          find.ancestor(
              of: find.text(message),
              matching: find.byWidgetPredicate(
                  (widget) => widget is IgnorePointer && widget.ignoring)),
          findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
    }, variant: TargetPlatformVariant.all());
  }
}
