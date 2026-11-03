import 'package:anx_reader/widgets/settings/font_name_preview.dart';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/settings_page/subpage/installed_fonts.dart';
import 'package:anx_reader/page/settings_page/subpage/font_management.dart';
import 'package:anx_reader/providers/fonts.dart';
import 'package:anx_reader/service/installed_fonts.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Downloads extends FontDownloads {
  _Downloads(this.status);
  final DownloadStatus status;
  @override
  Map<String, FontDownloadState> build() => {
        'test': FontDownloadState(
            fontId: 'test', filePath: 'download.ttf', status: status),
      };
}

void main() {
  late Directory root;
  late String oldPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    oldPath = documentPath;
    root = await Directory.systemTemp.createTemp('modu-font-manager-');
    documentPath = root.path;
    await getFontDir().create();
    await File('${getFontDir().path}/import.ttf').writeAsString('test');
    await File('${getFontDir().path}/$bundledFontFilename')
        .writeAsString('builtin');
  });
  tearDown(() async {
    documentPath = oldPath;
    await root.delete(recursive: true);
  });
  Future<void> show(WidgetTester tester,
      {DownloadStatus status = DownloadStatus.none,
      Widget page = const InstalledFontsPage()}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          fontDownloadsProvider.overrideWith(() => _Downloads(status)),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: page,
        )));
    await tester.pumpAndSettle();
  }

  testWidgets('font names use their installed face when preview is available',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          fontPreviewProvider('example.ttf')
              .overrideWith((ref) async => 'preview-face'),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: FontNamePreview('示例字体', filename: 'example.ttf')))));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('示例字体')).style?.fontFamily,
        'preview-face');
  });

  testWidgets('font management groups actions and opens installed fonts',
      (tester) async {
    await show(tester, page: const FontManagementPage());
    final rows = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(rows.map((row) => (row.title as Text).data),
        ['Download Fonts', 'Import fonts', 'Manage installed fonts']);
    await tester.tap(find.text('Manage installed fonts'));
    await tester.pumpAndSettle();
    expect(find.byType(InstalledFontsPage), findsOneWidget);
    expect(find.text('import.ttf'), findsOneWidget);
  });

  testWidgets(
      'cancel keeps file, confirm removes it, bundled has no delete button',
      (tester) async {
    await show(tester);
    expect(find.byTooltip('Remove font'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await tester.tap(find.byTooltip('Remove font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(File('${getFontDir().path}/import.ttf').existsSync(), isTrue);
    await tester.tap(find.byTooltip('Remove font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.runAsync(() async {
      for (var i = 0;
          i < 100 && File('${getFontDir().path}/import.ttf').existsSync();
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(File('${getFontDir().path}/import.ttf').existsSync(), isFalse);
    expect(find.text('import.ttf'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });
  for (final status in [DownloadStatus.downloading, DownloadStatus.paused]) {
    testWidgets('blocks deletion during $status', (tester) async {
      await show(tester, status: status);
      final removeButton = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Remove font');
      final button = tester.widget<IconButton>(removeButton);
      expect(button.onPressed, isNull);
      expect(File('${getFontDir().path}/import.ttf').existsSync(), isTrue);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(InstalledFontsPage)));
      container.read(fontDownloadsProvider.notifier).cancelDownload('test');
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(removeButton).onPressed, isNotNull);
    });
  }
}
