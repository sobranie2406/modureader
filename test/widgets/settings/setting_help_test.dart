import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(320, 600), const Size(800, 480)]) {
    testWidgets('help is anchored, scrollable and dismisses outside at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var toggles = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
        alignment: Alignment.topLeft,
        child: SettingsTile.switchTile(
            title: const Text('OCR'),
            description: Text(List.filled(40, 'Explanation').join('\n')),
            initialValue: false,
            onToggle: (_) => toggles++),
      ))));
      expect(find.textContaining('Explanation'), findsNothing);
      final anchor = tester.getRect(find.byIcon(Icons.help_outline));
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();
      expect(find.textContaining('Explanation'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(toggles, 0);
      final popup = tester.getRect(find.byType(PopupMenuItem<void>));
      expect(popup.top, greaterThanOrEqualTo(anchor.top));
      expect(popup.top - anchor.bottom, lessThan(80));
      await tester.tapAt(Offset(size.width - 4, size.height - 4));
      await tester.pumpAndSettle();
      expect(find.textContaining('Explanation'), findsNothing);
      expect(toggles, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('disabled controls still allow reading help', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsTile.switchTile(
                title: const Text('Disabled'),
                description: const Text('Why unavailable'),
                enabled: false,
                initialValue: false,
                onToggle: (_) => toggles++))));
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.text('Why unavailable'), findsOneWidget);
    expect(toggles, 0);
  });
  testWidgets('values and opted-out warnings remain visible', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      SettingsTile(
          title: const Text('Model'),
          value: const Text('v5'),
          description: const Text('How it works')),
      SettingsTile(
          title: const Text('Warning'),
          description: const Text('Failed'),
          descriptionAsHelp: false),
    ]))));
    expect(find.text('v5'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('How it works'), findsNothing);
    expect(find.byType(SettingHelp), findsOneWidget);
  });
}
