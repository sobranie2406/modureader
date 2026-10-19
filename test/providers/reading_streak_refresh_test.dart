import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/providers/heatmap_data.dart';
import 'package:anx_reader/providers/reading_streak_provider.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../service/sync/row_sync_test.dart' show bookRow;

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late PathProviderPlatform previousPaths;
  late String previousDocumentPath;
  late Database db;
  late ProviderContainer container;
  late DateTime today;

  setUp(() async {
    await DBHelper.close();
    root = await Directory.systemTemp.createTemp('modu-checkin-test-');
    previousPaths = PathProviderPlatform.instance;
    previousDocumentPath = documentPath;
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await initBasePath();
    db = await DBHelper().database;
    await db.insert('tb_books', bookRow(1));
    await db.insert('tb_books', bookRow(2));
    final now = DateTime.now();
    today = DateTime(now.year, now.month, now.day);
    container = ProviderContainer();
    container.listen(readingStreakProvider, (_, __) {});
    container.listen(heatmapDataProvider, (_, __) {});
    await container.read(readingStreakProvider.future);
    await container.read(heatmapDataProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await DBHelper.close();
    PathProviderPlatform.instance = previousPaths;
    documentPath = previousDocumentPath;
    await root.delete(recursive: true);
  });

  test('DAO writes refresh cross-book goals and heatmap without a widget ref',
      () async {
    await readingTimeDao.insertReadingSession(
        bookId: 1, readingTime: 360, startedAt: today);
    await container.pump();
    expect(
        (await container.read(readingStreakProvider.future)).qualifiedDays, 0);
    await readingTimeDao.insertReadingSession(
        bookId: 2, readingTime: 300, startedAt: today);
    await container.pump();
    final data = await container.read(readingStreakProvider.future);
    expect(data.todaySeconds, 660);
    expect(data.hasQualifiedToday, true);
    expect((await container.read(heatmapDataProvider.future))[today], 660);
  });

  test('sync/import revisions refresh totals even when DAO was bypassed',
      () async {
    await db.insert('tb_reading_time', {
      'book_id': 1,
      'date': today.toIso8601String(),
      'reading_time': 600,
      'round': 1
    });
    container.read(syncDatabaseRevisionProvider.notifier).state++;
    await container.pump();
    expect(
        (await container.read(readingStreakProvider.future)).hasQualifiedToday,
        true);
    expect((await container.read(heatmapDataProvider.future))[today], 600);
    await db.delete('tb_reading_time');
    container.read(syncDatabaseRevisionProvider.notifier).state++;
    await container.pump();
    expect(
        (await container.read(readingStreakProvider.future)).qualifiedDays, 0);
    expect(await container.read(heatmapDataProvider.future), isEmpty);
  });

  test('goal changes outside settings UI recalculate without altering history',
      () async {
    await readingTimeDao.insertReadingSession(
        bookId: 1, readingTime: 600, startedAt: today);
    await container.pump();
    expect(
        (await container.read(readingStreakProvider.future)).qualifiedDays, 1);
    Prefs().dailyCheckInMinutes = 30;
    await container.pump();
    final data = await container.read(readingStreakProvider.future);
    expect(data.goalSeconds, 1800);
    expect(data.qualifiedDays, 0);
    expect(data.remainingSeconds, 1200);
    Prefs().dailyCheckInMinutes = 0;
    await container.pump();
    expect(
        (await container.read(readingStreakProvider.future)).qualifiedDays, 1);
    expect(await readingTimeDao.selectTotalReadingTime(), 600);
  });
}
