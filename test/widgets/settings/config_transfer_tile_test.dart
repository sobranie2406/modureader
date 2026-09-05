import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/widgets/settings/config_transfer_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('import dialog owns its controller through route dismissal',
      (tester) async {
    Map<String, dynamic>? importedData;
    final token = ConfigTransferCodec.encode(
      kind: 'ai',
      data: const {'provider': 'test-provider'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ConfigTransferTile(
                kind: 'ai',
                label: 'AI settings',
                getData: () => const {},
                applyData: (data) => importedData = data,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Import AI settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), token);
    await tester.tap(find.text('Import configuration'));
    await tester.pumpAndSettle();

    expect(importedData, {'provider': 'test-provider'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
