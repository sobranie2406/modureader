import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/sync_preview.dart';
import 'package:anx_reader/widgets/sync/sync_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/sync/sync_preview_test.dart' show book, life;

void main() {
  testWidgets('changing the conflict policy must update the deletion preview',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final context = SyncPreviewContext(
      local: [book('a'), life('a', deleted: false)],
      remote: [book('a'), life('a', deleted: true, clock: 2000)],
    );
    final initial = buildSyncPreview(context: context);
    expect(initial.removedBooks, hasLength(1));
    expect(
        buildSyncPreview(
                context: context,
                resolution: SyncConflictResolution.preferLocal)
            .removedBooks,
        isEmpty);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SyncPreviewDialog(
              buildPreview: (resolution) =>
                  buildSyncPreview(context: context, resolution: resolution))),
    ));
    expect(find.text('Will be removed'), findsOneWidget);
    await tester.ensureVisible(find.text('Keep local'));
    await tester.tap(find.text('Keep local'));
    await tester.pumpAndSettle();
    expect(find.text('Will be removed'), findsNothing,
        reason: 'The selected policy now keeps the book');
  });
}
