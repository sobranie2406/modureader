import 'package:modu_reader/dao/base_dao.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart';
import 'package:modu_reader/models/read_theme.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:sqflite/sqflite.dart';

class ThemeDao extends BaseDao {
  ThemeDao();

  static const String table = 'tb_themes';
  Database? _cachedDatabase;
  Future<List<Map<String, Object?>>>? _themes;

  Future<int> insertTheme(ReadTheme readTheme) async {
    try {
      return await insert(table, readTheme.toMap());
    } finally {
      _themes = null;
    }
  }

  Future<List<ReadTheme>> selectThemes() async {
    final db = await database;
    // Restoring a backup replaces the database handle, even at the same path.
    if (!identical(_cachedDatabase, db)) {
      _cachedDatabase = db;
      _themes = null;
    }
    final pending = _themes ??= db.query(table);
    try {
      final rows = await pending;
      // Editors mutate ReadTheme; never let an unsaved edit change the cache.
      return rows.map(ReadTheme.fromDb).toList(growable: false);
    } catch (_) {
      if (identical(_themes, pending)) _themes = null;
      rethrow;
    }
  }

  Future<void> deleteTheme(int id) async {
    final currentThemes = await queryList(
      table,
      mapper: ReadTheme.fromDb,
    );
    if (currentThemes.length <= 2) {
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).readingPageAtLeastTwoThemes);
      return;
    }

    try {
      await delete(
        table,
        where: 'id = ?',
        whereArgs: [id],
      );
    } finally {
      _themes = null;
    }
  }

  Future<void> updateTheme(ReadTheme readTheme) async {
    try {
      await update(
        table,
        readTheme.toMap(),
        where: 'id = ?',
        whereArgs: [readTheme.id],
      );
    } finally {
      _themes = null;
    }
  }

  Future<ReadTheme> selectReadThemeById(int id) async {
    final theme = await querySingle(
      table,
      mapper: ReadTheme.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (theme == null) {
      throw StateError('Theme with id $id not found');
    }
    return theme;
  }
}

final themeDao = ThemeDao();
