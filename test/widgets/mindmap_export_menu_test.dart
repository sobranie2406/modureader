import 'dart:convert';
import 'dart:typed_data';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Future<String?> Function(Uint8List, String, String) save,
        {bool ready = true}) =>
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      home: Scaffold(
          body: SingleChildScrollView(
              child: MindmapStepTile(
        saveExport: save,
        step: ParsedToolStep(
            name: 'mindmap_draw',
            status: ready ? 'success' : 'running',
            output: ready
                ? jsonEncode({
                    'status': 'ok',
                    'data': {
                      'title': '总标题',
                      'root': {
                        'label': '总标题',
                        'children': [
                          {'label': '唯一子节点'}
                        ],
                      }
                    }
                  })
                : null),
      ))),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  testWidgets('menu exposes five formats and exports the complete root',
      (tester) async {
    String? savedName, savedMime;
    Uint8List? savedBytes;
    await tester.pumpWidget(app((bytes, name, mime) async {
      savedBytes = bytes;
      savedName = name;
      savedMime = mime;
      return '/synthetic/export.json';
    }));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('mindmap-export')));
    await tester.pumpAndSettle();
    for (final text in [
      'PNG (.png)',
      'SVG (.svg)',
      'Markdown (.md)',
      'FreeMind (.mm)',
      'JSON (.json)'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    await tester.tap(find.text('JSON (.json)'));
    await tester.pumpAndSettle();
    expect(savedName, endsWith('.json'));
    expect(savedMime, 'application/json');
    final data = jsonDecode(utf8.decode(savedBytes!));
    expect(data['root']['label'], '总标题');
    expect(data['root']['children'][0]['label'], '唯一子节点');
    expect(find.textContaining('导图已保存'), findsOneWidget);
  });
  testWidgets('cancelled save does not claim success', (tester) async {
    await tester.pumpWidget(app((_, __, ___) async => null));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown (.md)'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
  testWidgets('save failure allows retry and preserves the diagram',
      (tester) async {
    await tester
        .pumpWidget(app((_, __, ___) async => throw StateError('synthetic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JSON (.json)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('导出失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('mindmap-export')), findsOneWidget);
  });
  testWidgets('incomplete output has no export button or initialization error',
      (tester) async {
    await tester.pumpWidget(app((_, __, ___) async => null, ready: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('mindmap-export')), findsNothing);
  });
}
