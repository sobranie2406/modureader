import 'dart:async';

import 'package:anx_reader/page/settings_page/bug_report.dart';
import 'package:anx_reader/page/settings_page/settings_page.dart';
import 'package:anx_reader/service/feedback/bug_report.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mount(
  WidgetTester tester, {
  Future<bool> Function(Uri)? open,
  Future<String> Function()? version,
  Future<String> Function()? crashLog,
  Future<String> Function()? environment,
  bool mobile = false,
  bool chinese = false,
  Locale? locale,
}) async {
  tester.view.physicalSize =
      mobile ? const Size(390, 844) : const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: locale ?? Locale(chinese ? 'zh' : 'en'),
    supportedLocales: [...appLocales, const Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
        body: SettingsPageBody(
      title: chinese ? '提交 Bug' : 'Report a bug',
      isMobile: mobile,
      sections: BugReportSettings(
        openUrl: open ?? (_) async => true,
        loadVersion: version ?? () async => '0.1.0-beta.1+6326',
        loadCrashLog: crashLog,
        loadEnvironment: environment ?? () async => '',
      ),
    )),
  ));
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester,
    {String description = 'Blank PDF'}) async {
  final values = [
    'PDF reader',
    description,
    'Import and open PDF',
    'A blank page appears',
    'Show page'
  ];
  for (var i = 0; i < values.length; i++) {
    await tester.enterText(find.byType(TextFormField).at(i), values[i]);
  }
  // Avoid a focused field fighting scroll-to-button in a nested settings page.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> selectType(WidgetTester tester, FeedbackType type) async {
  final chip = find.byKey(ValueKey('feedback-type-${type.name}'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  // NestedScrollView can leave a translated chip below the screen even after
  // ensureVisible. Use the same scrolling gesture a user needs to reach it.
  final formScroll = find.descendant(
      of: find.byType(BugReportSettings),
      matching: find.byType(SingleChildScrollView));
  for (var attempt = 0;
      attempt < 6 && chip.hitTestable().evaluate().isEmpty;
      attempt++) {
    final direction = tester.getCenter(chip).dy >
            tester.view.physicalSize.height / tester.view.devicePixelRatio / 2
        ? -160.0
        : 160.0;
    await tester.drag(formScroll.first, Offset(0, direction));
    await tester.pumpAndSettle();
  }
  expect(chip.hitTestable(), findsOneWidget);
  await tester.tap(chip.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> fillFeature(WidgetTester tester,
    {String problem = 'A missing workflow'}) async {
  final values = ['A useful feature', problem, 'Add a shortcut'];
  for (var i = 0; i < values.length; i++) {
    await tester.enterText(find.byType(TextFormField).at(i), values[i]);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'feature needs only title, use case and solution; no automatic submission',
      (tester) async {
    final opened = <Uri>[];
    await mount(tester, open: (uri) async {
      opened.add(uri);
      return true;
    });
    await selectType(tester, FeedbackType.feature);
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.text('Steps to reproduce'), findsNothing);
    expect(find.byKey(const ValueKey('include-crash-log')), findsNothing);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
    await click(tester, 'Preview and submit');
    expect(find.text('This field is required'), findsNWidgets(3));
    expect(opened, isEmpty);
    await fillFeature(tester);
    await click(tester, 'Preview and submit');
    expect(find.text('Preview feature request'), findsOneWidget);
    expect(opened, isEmpty);
    await click(tester, 'Continue on GitHub');
    expect(opened.single.queryParameters['template'], 'feature_request.md');
    expect(
        opened.single.queryParameters['title'], '[Feature]: A useful feature');
    expect(opened.single.queryParameters['body'], contains('Add a shortcut'));
    expect(
        opened.single.queryParameters['body'], isNot(contains('Environment')));
    expect(find.textContaining('Nothing submitted yet'), findsOneWidget);
  });

  testWidgets(
      'switching types preserves independent drafts and environment choices',
      (tester) async {
    await mount(tester);
    await fill(tester);
    final bugTitle = tester
        .widget<TextFormField>(find.byType(TextFormField).first)
        .controller!;
    bugTitle.selection = const TextSelection.collapsed(offset: 3);
    await selectType(tester, FeedbackType.feature);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty);
    await fillFeature(tester);
    await click(tester, 'Include device and environment info');
    await selectType(tester, FeedbackType.bug);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller,
        same(bugTitle));
    expect(bugTitle.text, 'PDF reader');
    expect(bugTitle.selection.baseOffset, 3);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(3))
            .controller!
            .text,
        'A blank page appears');
    await click(tester, 'Include device and environment info');
    await selectType(tester, FeedbackType.feature);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'A useful feature');
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await click(tester, 'Preview and submit');
    expect(find.textContaining('6326'), findsWidgets);
    expect(find.textContaining('Blank PDF'), findsNothing);
    await click(tester, 'Keep editing');
  });

  testWidgets(
      'switching to feature cancels diagnostics and requires fresh bug opt-in',
      (tester) async {
    final log = Completer<String>();
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester, crashLog: () => log.future);
    final tile = find.byKey(const ValueKey('include-crash-log'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    final chip = find.byKey(const ValueKey('feedback-type-feature'));
    await tester.ensureVisible(chip);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(chip);
    await tester.pumpAndSettle();
    log.complete('BUG_ONLY_DIAGNOSTICS');
    await tester.pumpAndSettle();
    await fillFeature(tester);
    await click(tester, 'Copy report');
    expect(copied, contains('[Feature]: A useful feature'));
    expect(copied, isNot(contains('BUG_ONLY_DIAGNOSTICS')));
    await selectType(tester, FeedbackType.bug);
    expect(tester.widget<CheckboxListTile>(tile).value, isFalse);
    expect(find.textContaining('BUG_ONLY_DIAGNOSTICS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long feature copies full text only after preview and opens feature template',
      (tester) async {
    String? copied;
    final opened = <Uri>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester, open: (uri) async {
      opened.add(uri);
      return true;
    });
    await selectType(tester, FeedbackType.feature);
    await fillFeature(tester, problem: '需' * 1000);
    await click(tester, 'Preview and submit');
    expect(copied, isNull);
    expect(opened, isEmpty);
    await click(tester, 'Copy and open GitHub');
    expect(copied, contains('需' * 1000));
    expect(opened, [FeatureRequest.newIssueUri]);
    expect(opened.single.toString(), isNot(contains('需')));
  });

  testWidgets('failed feature navigation retains draft and correct manual URL',
      (tester) async {
    await mount(tester, open: (_) async => false);
    await selectType(tester, FeedbackType.feature);
    await fillFeature(tester);
    await click(tester, 'Preview and submit');
    await click(tester, 'Continue on GitHub');
    expect(find.textContaining('Could not open the browser'), findsOneWidget);
    expect(find.text(FeatureRequest.newIssueUri.toString()), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'A useful feature');
  });

  testWidgets('search uses active draft title with safe query encoding',
      (tester) async {
    Uri? opened;
    await mount(tester, open: (uri) async {
      opened = uri;
      return true;
    });
    await selectType(tester, FeedbackType.feature);
    await tester.enterText(find.byType(TextFormField).first, '阅读 & ? #1');
    await click(tester, 'Existing issues');
    expect(opened, FeedbackReport.searchUri('阅读 & ? #1'));
    expect(opened!.fragment, isEmpty);
    expect(opened!.queryParameters['q'], 'is:issue 阅读 & ? #1');
  });

  testWidgets('environment refresh preserves IME composition and caret',
      (tester) async {
    final environment = Completer<String>();
    await mount(tester, environment: () => environment.future);
    await selectType(tester, FeedbackType.feature);
    final field = find.byType(TextFormField).first;
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pump();
    const editing = TextEditingValue(
        text: '功能abcdef',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2));
    tester.testTextInput.updateEditingValue(editing);
    await tester.pump();
    final controller = tester.widget<TextFormField>(field).controller!;
    environment.complete('Windows 11 / x64');
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(field).controller, same(controller));
    expect(controller.value, editing);
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
  });

  for (final locale in appLocales) {
    testWidgets(
        '$locale feature form is localized on a narrow large-text display',
        (tester) async {
      await mount(tester, locale: locale, mobile: true);
      final context = tester.element(find.byType(BugReportSettings));
      final strings = [
        ModuStrings.text(context, '预览功能建议', 'Preview feature request'),
        ModuStrings.text(context, '使用场景与需求', 'Problem or use case'),
        ModuStrings.text(context, '希望实现的功能', 'Proposed solution'),
      ];
      if (locale.languageCode != 'en') {
        expect(strings[1], isNot('Problem or use case'));
        expect(strings[2], isNot('Proposed solution'));
      }
      await selectType(tester, FeedbackType.feature);
      expect(find.text(strings[1]), findsOneWidget);
      expect(find.text(strings[2]), findsOneWidget);
      await fillFeature(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await click(
          tester, ModuStrings.text(context, '预览并提交', 'Preview and submit'));
      expect(find.text(strings[0]), findsOneWidget);
      await click(tester, ModuStrings.text(context, '返回修改', 'Keep editing'));
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [
    const Locale('fr'),
    const Locale('ja'),
    const Locale('ar')
  ]) {
    testWidgets(
        '$locale feedback labels are localized and privacy remains visible',
        (tester) async {
      await mount(tester, locale: locale, mobile: true);
      final context = tester.element(find.byType(BugReportSettings));
      expect(
          find.text(ModuStrings.text(context, '提交 Bug', 'Report a bug')).last,
          findsOneWidget);
      expect(find.text('问题描述'), findsNothing);
      expect(find.text('Description'), findsNothing);
      expect(find.byType(TextFormField), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'checked diagnostics reach clipboard only after preview confirmation, never URL',
      (tester) async {
    String? copied;
    final opened = <Uri>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester,
        crashLog: () async => 'SANITIZED_CRASH_FIXTURE',
        open: (uri) async {
          opened.add(uri);
          return true;
        });
    await fill(tester);
    await click(tester, 'Include crash diagnostics (optional)');
    await click(tester, 'Preview and submit');
    expect(copied, isNull);
    expect(opened, isEmpty);
    await click(tester, 'Copy and open GitHub');
    expect(copied, contains('SANITIZED_CRASH_FIXTURE'));
    expect(opened.single, BugReport.newIssueUri);
    expect(
        opened.single.toString(), isNot(contains('SANITIZED_CRASH_FIXTURE')));
  });
  testWidgets(
      'crash checkbox defaults off, previews only after opt-in and opt-out removes it',
      (tester) async {
    var reads = 0;
    await mount(tester,
        crashLog: () async {
          reads++;
          return 'NATIVE_CRASH fixture';
        },
        environment: () async => 'Android 16 / iQOO Neo8 / ARM64');
    expect(reads, 0);
    expect(find.textContaining('Android 16 / iQOO'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('include-crash-log')))
            .value,
        isFalse);
    await fill(tester);
    await click(tester, 'Include crash diagnostics (optional)');
    expect(reads, 1);
    await click(tester, 'Preview and submit');
    expect(find.textContaining('NATIVE_CRASH fixture'), findsWidgets);
    expect(find.text('Copy and open GitHub'), findsOneWidget);
    await click(tester, 'Keep editing');
    await click(tester, 'Include crash diagnostics (optional)');
    await click(tester, 'Preview and submit');
    expect(find.textContaining('NATIVE_CRASH fixture'), findsNothing);
    expect(find.text('Continue on GitHub'), findsOneWidget);
  });

  testWidgets('late diagnostic load cannot restore opted-out or disposed state',
      (tester) async {
    final log = Completer<String>();
    await mount(tester, crashLog: () => log.future);
    final tile = find.byKey(const ValueKey('include-crash-log'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    log.complete('private fixture');
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(tile).value, isFalse);
    expect(find.textContaining('private fixture'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'diagnostic read failure allows retry without blocking ordinary report',
      (tester) async {
    await mount(tester,
        crashLog: () async => throw StateError('private error'));
    await click(tester, 'Include crash diagnostics (optional)');
    expect(find.textContaining('Could not load crash diagnostics'),
        findsOneWidget);
    expect(find.textContaining('private error'), findsNothing);
    await fill(tester);
    await click(tester, 'Preview and submit');
    expect(find.text('Continue on GitHub'), findsOneWidget);
  });
  testWidgets('no navigation until a valid report is previewed and confirmed',
      (tester) async {
    final opened = <Uri>[];
    await mount(tester, open: (uri) async {
      opened.add(uri);
      return true;
    });
    expect(opened, isEmpty);
    await click(tester, 'Preview and submit');
    expect(find.text('This field is required'), findsNWidgets(5));
    expect(opened, isEmpty);
    await fill(tester);
    await click(tester, 'Preview and submit');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(opened, isEmpty);
    await click(tester, 'Keep editing');
    expect(opened, isEmpty);
    await click(tester, 'Preview and submit');
    await click(tester, 'Continue on GitHub');
    expect(opened.single.queryParameters['bug_report_description'],
        contains('Blank PDF'));
    expect(opened.single.queryParameters['bug_report_description'],
        contains('A blank page appears'));
    expect(
        opened.single.queryParameters['bug_report_desktop'], contains('6326'));
    expect(find.textContaining('Nothing submitted yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opt-out and browser failure retain a reusable draft',
      (tester) async {
    Uri? opened;
    await mount(tester, open: (uri) async {
      opened = uri;
      return false;
    });
    await fill(tester);
    await click(tester, 'Include device and environment info');
    await click(tester, 'Preview and submit');
    await click(tester, 'Continue on GitHub');
    expect(opened!.queryParameters['bug_report_desktop'], isEmpty);
    expect(find.textContaining('Could not open the browser'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'PDF reader');
    expect(find.text(BugReport.newIssueUri.toString()), findsOneWidget);
  });

  testWidgets('long report is copied only after consent, never put in URL',
      (tester) async {
    String? clipboard;
    final opened = <Uri>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester, open: (uri) async {
      opened.add(uri);
      return true;
    });
    await fill(tester, description: '书' * 1000);
    await click(tester, 'Preview and submit');
    expect(clipboard, isNull);
    expect(opened, isEmpty);
    await click(tester, 'Copy and open GitHub');
    expect(clipboard, contains('书' * 1000));
    expect(opened.single, BugReport.newIssueUri);
    expect(find.textContaining('Full report copied'), findsOneWidget);
  });

  testWidgets('clipboard failure never discards long report or opens browser',
      (tester) async {
    var opens = 0;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'denied');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester, open: (_) async {
      opens++;
      return true;
    });
    await fill(tester, description: '书' * 1000);
    await click(tester, 'Preview and submit');
    await click(tester, 'Copy and open GitHub');
    expect(opens, 0);
    expect(find.textContaining('Your draft is retained'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Chinese narrow settings layout supports preview without overflow',
      (tester) async {
    await mount(tester, mobile: true, chinese: true);
    await fill(tester);
    await click(tester, '预览并提交');
    expect(find.text('预览 Bug 报告'), findsOneWidget);
    await click(tester, '返回修改');
    expect(tester.takeException(), isNull);
  });

  testWidgets('issue browsing points only to Modu and handles launcher errors',
      (tester) async {
    final opened = <Uri>[];
    await mount(tester, open: (uri) async {
      opened.add(uri);
      throw StateError('offline');
    });
    await click(tester, 'Existing issues');
    await click(tester, 'My reports (GitHub)');
    expect(opened, [BugReport.issuesUri, BugReport.myIssuesUri]);
    expect(find.textContaining('Your draft is retained'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late environment loading is safe after leaving settings',
      (tester) async {
    final version = Completer<String>();
    await mount(tester, version: () => version.future);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    version.complete('test');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('version loading failure still allows reporting', (tester) async {
    await mount(tester, version: () async => throw StateError('asset missing'));
    expect(find.textContaining('Modu: unknown'), findsOneWidget);
    await fill(tester);
    await click(tester, 'Preview and submit');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
