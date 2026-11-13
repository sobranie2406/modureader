import 'dart:async';

import 'package:modu_reader/dao/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

class _Database implements Database {
  int reads = 0;
  final pending = Completer<List<Map<String, Object?>>>();

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) {
    expect(table, 'tb_themes');
    reads++;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Dao extends ThemeDao {
  _Dao(this.db);
  Database db;
  @override
  Future<Database> get database async => db;
}

void main() {
  test('opening book and menus shares in-flight and completed theme queries',
      () async {
    final db = _Database();
    final dao = _Dao(db);
    final requests = List.generate(20, (_) => dao.selectThemes());
    db.pending.complete([
      {'id': 1, 'background_color': 'FFFAFAFA', 'text_color': 'FF111111'}
    ]);
    final results = await Future.wait(requests);
    expect(db.reads, 1);
    for (var i = 0; i < 20; i++) {
      await dao.selectThemes();
    }
    expect(db.reads, 1);
    results.first.first.backgroundColor = 'FF000000';
    expect((await dao.selectThemes()).first.backgroundColor, 'FFFAFAFA');
  });

  test('late read from replaced database cannot overwrite the new cache',
      () async {
    final old = _Database();
    final restored = _Database();
    final dao = _Dao(old);
    final beforeRestore = dao.selectThemes();
    await Future<void>.delayed(Duration.zero);
    dao.db = restored;
    final afterRestore = dao.selectThemes();
    restored.pending.complete([
      {'id': 1, 'background_color': 'FF123456'}
    ]);
    expect((await afterRestore).first.backgroundColor, 'FF123456');
    old.pending.complete([
      {'id': 1, 'background_color': 'FFABCDEF'}
    ]);
    await beforeRestore;
    expect((await dao.selectThemes()).first.backgroundColor, 'FF123456');
    expect(restored.reads, 1);
  });
}
