import 'package:sqflite/sqflite.dart';

import '../../domain/reader/reader_preferences.dart';
import '../repositories/reader_repository.dart';
import 'ibuki_database.dart';

class SQLiteReaderRepository implements ReaderRepository {
  SQLiteReaderRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<ReaderPreferences> loadPreferences(String projectId) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'reader_preferences',
      where: 'project_id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    if (rows.isEmpty) return ReaderPreferences.defaults(projectId);
    final row = rows.single;
    return ReaderPreferences(
      projectId: projectId,
      fontSize: (row['font_size'] as num).toDouble(),
      lineHeight: (row['line_height'] as num).toDouble(),
      horizontalMargin: (row['horizontal_margin'] as num).toDouble(),
      theme: ReaderThemeMode.fromJson(row['theme']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    );
  }

  @override
  Future<void> savePreferences(ReaderPreferences preferences) async {
    final db = await ibukiDatabase.database;
    await db.insert('reader_preferences', {
      'project_id': preferences.projectId,
      'font_size': preferences.fontSize,
      'line_height': preferences.lineHeight,
      'horizontal_margin': preferences.horizontalMargin,
      'theme': preferences.theme.jsonValue,
      'updated_at': preferences.updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<ReaderProgress> loadProgress(String projectId) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'reader_progress',
      where: 'project_id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    if (rows.isEmpty) return ReaderProgress.empty(projectId);
    final row = rows.single;
    return ReaderProgress(
      projectId: projectId,
      lastReadSegmentId: row['last_read_segment_id'] as String?,
      scrollOffset: (row['scroll_offset'] as num).toDouble(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    );
  }

  @override
  Future<void> saveProgress(ReaderProgress progress) async {
    final db = await ibukiDatabase.database;
    await db.insert('reader_progress', {
      'project_id': progress.projectId,
      'last_read_segment_id': progress.lastReadSegmentId,
      'scroll_offset': progress.scrollOffset,
      'updated_at': progress.updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
