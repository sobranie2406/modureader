import 'dart:async';

import 'package:anx_reader/page/settings_page/bug_report.dart';
import 'package:anx_reader/page/settings_page/settings_page.dart';
import 'package:anx_reader/service/feedback/bug_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mount(
  WidgetTester tester, {
  Future<bool> Function(Uri)? open,
  Future<String> Function()? version,
  bool mobile = false,
  bool chinese = false,
}) async {
  tester.view.physicalSize =
      mobile ? const Size(390, 844) : const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: Locale(chinese ? 'zh' : 'en'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
        body: SettingsPageBody(
      title: chinese ? '提交 Bug' : 'Report a bug',
      isMobile: mobile,
      sections: BugReportSettings(
        openUrl: open ?? (_) async => true,
        loadVersion: version ?? () async => '0.1.0-beta.1+6326',
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
    'Show page'
  ];
  for (var i = 0; i < values.length; i++) {
    await tester.enterText(find.byType(TextFormField).at(i), values[i]);
  }
  // Avoid a focused field fighting scroll-to-button in a nested settings page.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no navigation until a valid report is previewed and confirmed',
      (tester) async {
    final opened = <Uri>[];
    await mount(tester, open: (uri) async {
      opened.add(uri);
      return true;
    });
    expect(opened, isEmpty);
    await click(tester, 'Preview and submit');
    expect(find.text('This field is required'), findsNWidgets(4));
    expect(opened, isEmpty);
    await fill(tester);
    await click(tester, 'Preview and submit');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(opened, isEmpty);
    await click(tester, 'Keep editing');
    expect(opened, isEmpty);
    await click(tester, 'Preview and submit');
    await click(tester, 'Continue on GitHub');
    expect(
        opened.single.queryParameters['bug_report_description'], 'Blank PDF');
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
    await click(tester, 'Include basic environment info');
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
