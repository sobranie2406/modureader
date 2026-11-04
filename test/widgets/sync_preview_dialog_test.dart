import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/config_transfer/settings_modules.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/sync_preview.dart';
import 'package:anx_reader/widgets/sync/sync_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncPreview preview({bool uploading = false}) => SyncPreview(
      localChangedAt: DateTime(2026, 11, 3, 18, 10),
      remoteChangedAt: DateTime(2026, 11, 3, 17, 40),
      remoteFileAt: DateTime(2026, 11, 3, 17, 41),
      remoteMissing: false,
      sharedBooks: 8,
      localOnlyBooks: 1,
      remoteOnlyBooks: 2,
      bothDeletedBooks: 1,
      addedBooks: uploading
          ? const []
          : const [
              SyncPreviewBook(
                  title: 'Cloud novel',
                  filePath: 'file/cloud.epub',
                  after: 0.4)
            ],
      removedBooks: uploading
          ? const []
          : const [
              SyncPreviewBook(
                  title: 'Deleted novel', filePath: 'file/deleted.epub'),
            ],
      progressChangedBooks: uploading
          ? const []
          : const [
              SyncPreviewBook(
                  title: 'Progress novel',
                  filePath: 'file/progress.epub',
                  before: 0.2,
                  after: 0.75),
            ],
      uploadedBooks: uploading
          ? const [
              SyncPreviewBook(
                  title: 'Local novel', filePath: 'file/local.epub', after: 0.3)
            ]
          : const [],
      cloudRemovedBooks: uploading
          ? const [
              SyncPreviewBook(
                  title: 'Removed cloud novel', filePath: 'file/old.epub')
            ]
          : const [],
      uploadedProgressChangedBooks: uploading
          ? const [
              SyncPreviewBook(
                  title: 'Upload progress novel',
                  filePath: 'file/upload.epub',
                  before: 0.4,
                  after: 0.5),
            ]
          : const [],
      localNoteCount: uploading ? 13 : 10,
      mergedNoteCount: 13,
      remoteNoteCount: uploading ? 10 : 13,
      localReadingSeconds: uploading ? 5400 : 3600,
      mergedReadingSeconds: 5400,
      remoteReadingSeconds: uploading ? 3600 : 5400,
      divergentRecords: 2,
      divergentByKind: const {'note': 1, 'position': 1},
      resolution: SyncConflictResolution.newest,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> openDialog(WidgetTester tester,
      {required void Function(SyncConflictResolution?) onResult,
      bool uploading = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(await showSyncPreviewDialog(context, preview(uploading: uploading)));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows timestamps, book changes and reading deltas',
      (tester) async {
    await openDialog(tester, onResult: (_) {});

    expect(find.byKey(const ValueKey('sync-preview-dialog')), findsOneWidget);
    expect(find.text('Sync preview'), findsOneWidget);
    expect(find.text('Local changes last modified'), findsOneWidget);
    expect(find.text('2026-11-03 18:10'), findsOneWidget);
    expect(find.text('Cloud changes last modified'), findsOneWidget);
    expect(find.text('Will be added'), findsOneWidget);
    expect(find.text('· Cloud novel'), findsOneWidget);
    expect(find.text('Will be removed'), findsOneWidget);
    expect(
        find.textContaining('will leave this shelf'), findsOneWidget);
    expect(find.text('· Progress novel'), findsOneWidget);
    expect(find.text('20% → 75%'), findsOneWidget);
    expect(find.text('+3 (10 → 13)'), findsOneWidget);
    expect(find.text('+30 min'), findsOneWidget);
    expect(find.text('Divergent records'), findsOneWidget);
  });

  testWidgets('an uploading device sees its own changes as upload deltas',
      (tester) async {
    await openDialog(tester, uploading: true, onResult: (_) {});

    expect(find.byKey(const ValueKey('sync-preview-upload')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-preview-download')), findsNothing);
    expect(find.text('To the cloud'), findsOneWidget);
    expect(find.text('Cloud gains'), findsOneWidget);
    expect(find.text('· Local novel'), findsOneWidget);
    expect(find.text('Cloud loses'), findsOneWidget);
    expect(find.text('· Removed cloud novel'), findsOneWidget);
    expect(find.text('· Upload progress novel'), findsOneWidget);
    expect(find.text('40% → 50%'), findsOneWidget);
    expect(find.text('Cloud notes'), findsOneWidget);
    expect(find.text('+3 (10 → 13)'), findsOneWidget);
    expect(find.text('+30 min'), findsOneWidget);
  });

  testWidgets('defaults to newest and returns the chosen preference',
      (tester) async {
    SyncConflictResolution? result;
    var opened = false;
    await openDialog(tester, onResult: (value) {
      result = value;
      opened = true;
    });

    await tester.tap(find.byKey(const ValueKey('sync-preview-confirm')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(result, SyncConflictResolution.newest);
  });

  testWidgets('choosing the cloud preference returns preferRemote',
      (tester) async {
    SyncConflictResolution? result;
    await openDialog(tester, onResult: (value) => result = value);

    await tester.ensureVisible(find.text('Keep cloud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep cloud'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unsynced local changes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-preview-confirm')));
    await tester.pumpAndSettle();
    expect(result, SyncConflictResolution.preferRemote);
  });

  testWidgets('cancel returns null so the caller can abort the merge',
      (tester) async {
    SyncConflictResolution? result;
    var opened = false;
    await openDialog(tester, onResult: (value) {
      result = value;
      opened = true;
    });

    await tester.tap(find.byKey(const ValueKey('sync-preview-cancel')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(result, isNull);
  });

  test('the preview preference defaults off and belongs to the webdav module',
      () async {
    expect(Prefs().syncPreviewBeforeSync, isFalse);
    Prefs().syncPreviewBeforeSync = true;
    expect(Prefs().syncPreviewBeforeSync, isTrue);
    expect((await SharedPreferences.getInstance())
        .getBool('syncPreviewBeforeSync'), isTrue);
    expect(settingsModuleForKey('syncPreviewBeforeSync'), 'webdav');
  });
}
